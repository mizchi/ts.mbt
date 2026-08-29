// Phase 4 of the observability analysis: backward flow propagation.
//
// Given the sinks collected by Phase 3 and the data-flow graph
// from Phase 1, compute for every binding whether ITS value can
// reach an end-user observation point — and if so, how (direct
// property enumeration, recursive serialization, etc.).
//
// Why this is needed: Phase 3 v1 reserved only the property names
// that appear directly on the sink-receiver binding. But most
// real-world sinks read a value handed in through a parameter or
// a function return:
//
//   function read(opts) { return Object.keys(opts.tasks); }
//   read(loaded);
//
// Without backward flow, Phase 3 sees `opts.tasks` and falls
// back to `*` because the immediate receiver is a PropAccess.
// With it, we trace
//
//   `opts.tasks` -> opts (PropReceiver) -> param of read
//                -> caller's arg `loaded` -> the binding `loaded`
//
// and reserve the property names visible on `loaded` plus the
// `.tasks` accessor itself.
//
// The lattice (defined separately so Phase 4 can ratchet
// observability monotonically):

///|
pub(all) enum Observability {
  /// No observation path reaches this binding. Its non-built-in
  /// properties are free to rename.
  Hidden
  /// The binding's value is only stringified (toString /
  /// type coercion). String contents leak but property names
  /// don't.
  ViaStringify
  /// `Object.keys(x)` / `for-in x` semantics — only direct
  /// (first-level) property names are observed.
  DirectProps
  /// `JSON.stringify(x)` / `console.log(x)` / `throw x` semantics
  /// — every nested property name on the value tree is observed.
  RecursiveProps
  /// The binding crosses the bundle boundary or reaches a
  /// fully-dynamic sink. All names escape — equivalent to the
  /// wildcard `*` reservation.
  External
} derive(Eq, Debug)

///|
/// Can this function's recorded return set be trusted as COMPLETE?
///
/// `g.funcs[fid].returns` is what lets the analysis look through a call
/// instead of assuming the wildcard. That is only valid while the name
/// still holds the function the walk saw: `let f = () => a; f = external`
/// makes the recorded returns one of several possibilities, and the
/// analysis would under-reserve.
///
/// Checked here rather than at registration because a reassignment can
/// appear anywhere in the file, including after the declaration — the
/// walk does not know yet, and this does.
fn func_returns_are_complete(g : SymbolGraph, fid : SymbolId) -> Bool {
  !g.symbols[fid].reassigned
}

///|
/// Lattice join: max of the two arguments according to the
/// ordering `Hidden < ViaStringify < DirectProps < RecursiveProps
/// < External`. Used by the fixed-point loop so observability
/// can only grow.
fn obs_join(a : Observability, b : Observability) -> Observability {
  let av = obs_rank(a)
  let bv = obs_rank(b)
  if av >= bv {
    a
  } else {
    b
  }
}

///|
fn obs_rank(o : Observability) -> Int {
  match o {
    Hidden => 0
    ViaStringify => 1
    DirectProps => 2
    RecursiveProps => 3
    External => 4
  }
}

///|
fn obs_from_sink_kind(k : SinkObservation) -> Observability {
  match k {
    DirectKeys => DirectProps
    Recursive => RecursiveProps
    ExternalCallArg => External
    ExternalPropWrite => External
    StringifyOnly => ViaStringify
  }
}

// ---------------------------------------------------------------------------
// Worklist algorithm
// ---------------------------------------------------------------------------

///|
/// Compute the Observability map for every binding in the graph.
///
/// Algorithm:
///   1. Seed: for each (sink, scope) entry, resolve the sink
///      expression's free variables in `scope`. Each resolved
///      symbol gets the sink's observability as its initial value.
///   2. Propagate: for each symbol whose observability changes,
///      walk inbound edges:
///        - `from = SymVal(src)`        -> src inherits.
///        - `from = FuncReturn(fid)`    -> every entry in
///          `funcs[fid].returns` inherits.
///        - `from = FuncArg(fid, i)`    -> NOT inbound to this
///          symbol; handled in the dual direction below.
///        - `from = External | Unknown` -> mark sym as External.
///      For parameter symbols, walk inbound `FuncArg(fid, i)`
///      edges in the dual direction: every caller's argument
///      expression inherits.
///   3. Repeat until no changes. Lattice is finite + monotone, so
///      convergence is guaranteed in O(|symbols| * |edges|)
///      worst case (linear on real bundles).
pub fn analyze_observability(
  g : SymbolGraph,
  scoped_sinks : Array[(Sink, ScopeId)],
) -> Map[SymbolId, Observability] {
  let result : Map[SymbolId, Observability] = {}
  let worklist : Array[SymbolId] = []

  // Pre-build a reverse index `FuncArg(fid, i) -> arg expressions
  // landing here` so the parameter-side propagation is O(degree)
  // per param instead of O(edges).
  //
  // And the same index for `SymVal` targets, which the propagation loop
  // below used to find by scanning EVERY flow edge per popped symbol —
  // O(symbols x edges), i.e. quadratic. That was 40 of the 43 seconds
  // `mtsc --bundle --mangle` spent on the 9 MB TypeScript bundle. It
  // had been invisible because the only consumer was
  // `--mangle-properties`, which nothing in the corpus enables on a
  // target that size; `class_method_dce` now asks the same question on
  // every bundle, which is what surfaced it.
  let arg_edges_by_param : Map[SymbolId, Array[FlowNode]] = {}
  let val_edges_by_sym : Map[SymbolId, Array[FlowNode]] = {}
  for edge in g.flow_edges {
    match edge.to {
      FuncArg(fid, idx) =>
        match g.funcs.get(fid) {
          Some(info) =>
            if idx < info.params.length() {
              let pid = info.params[idx]
              match arg_edges_by_param.get(pid) {
                Some(arr) => arr.push(edge.from)
                None => arg_edges_by_param[pid] = [edge.from]
              }
            }
          None => ()
        }
      SymVal(s) =>
        match val_edges_by_sym.get(s) {
          Some(arr) => arr.push(edge.from)
          None => val_edges_by_sym[s] = [edge.from]
        }
      _ => ()
    }
  }

  // Step 1: seed
  for entry in scoped_sinks {
    let (sink, scope) = entry
    let initial = obs_from_sink_kind(sink.observation)
    seed_from_expr(sink.expr, scope, initial, g, result, worklist)
  }

  // Step 2: backward propagation
  while worklist.length() > 0 {
    let sym = worklist.pop().unwrap()
    let target = result.get(sym).unwrap_or(Hidden)
    // For every inbound edge to SymVal(sym), propagate `target`
    // to the source.
    match val_edges_by_sym.get(sym) {
      Some(sources) =>
        for src in sources {
          propagate_to_flow_source(src, target, g, result, worklist)
        }
      None => ()
    }
    // If sym is a parameter, every call-site argument also
    // inherits the target.
    match arg_edges_by_param.get(sym) {
      Some(arg_sources) =>
        for src in arg_sources {
          propagate_to_flow_source(src, target, g, result, worklist)
        }
      None => ()
    }
  }

  result
}

///|
/// Resolve `expr`'s free variables in the given scope and seed
/// each with `obs`. Recurses through property / index chains so
/// `obj.foo.bar` seeds `obj`.
fn seed_from_expr(
  expr : @ast.TsExpr,
  scope : ScopeId,
  obs : Observability,
  g : SymbolGraph,
  result : Map[SymbolId, Observability],
  worklist : Array[SymbolId],
) -> Unit {
  match expr {
    @ast.TsExpr::Var(n) =>
      match lookup_symbol_in_scope(g, scope, n) {
        Some(id) => bump_obs(id, obs, result, worklist)
        None => ()
      }
    PropAccess(recv, _) => seed_from_expr(recv, scope, obs, g, result, worklist)
    MethodCall(recv, _, _) =>
      seed_from_expr(recv, scope, obs, g, result, worklist)
    IndexAccess(recv, _) =>
      seed_from_expr(recv, scope, obs, g, result, worklist)
    Call(callee, _) =>
      match lookup_symbol_in_scope(g, scope, callee) {
        Some(fid) =>
          match g.funcs.get(fid) {
            Some(info) if func_returns_are_complete(g, fid) =>
              for src in info.returns {
                propagate_to_flow_source(src, obs, g, result, worklist)
              }
            // No recorded return set, or one that cannot be trusted:
            // the callee is opaque, so the wildcard.
            _ => bump_obs(fid, External, result, worklist)
          }
        None => ()
      }
    CallExpr(callee, _) => {
      let fid = match callee {
        @ast.TsExpr::Var(n) => lookup_symbol_in_scope(g, scope, n)
        _ => None
      }
      match fid {
        Some(id) =>
          match g.funcs.get(id) {
            Some(info) if func_returns_are_complete(g, id) =>
              for src in info.returns {
                propagate_to_flow_source(src, obs, g, result, worklist)
              }
            _ => bump_obs(id, External, result, worklist)
          }
        None => ()
      }
    }
    Cond(_, t, e) => {
      seed_from_expr(t, scope, obs, g, result, worklist)
      seed_from_expr(e, scope, obs, g, result, worklist)
    }
    BinOp(_, _, r) => seed_from_expr(r, scope, obs, g, result, worklist)
    // Containers pass the observation through to what they hold. A
    // value handed to a sink INSIDE an array or as an object-literal
    // value is observed exactly as much as one handed over directly:
    // `console.log(o)` and `console.log([o])` both print `o`'s keys.
    //
    // Without these arms the seed walk stopped at the container and the
    // binding inside it was never marked, so its properties stayed
    // manglable and the dead-property pass deleted them. `console.log`
    // printed `[ {} ]` where the unmangled bundle printed `[ { k: 1 } ]`.
    //
    // `collect_object_literal_keys` already reserved the container's OWN
    // keys for this reason; what it could not do is follow the values.
    // Found by `just fuzz-mangle`.
    ArrayLit(items) =>
      for item in items {
        seed_from_expr(item, scope, obs, g, result, worklist)
      }
    ObjectLit(entries) =>
      for ent in entries {
        seed_from_expr(ent.1, scope, obs, g, result, worklist)
      }
    Spread(inner) => seed_from_expr(inner, scope, obs, g, result, worklist)
    // A template literal stringifies its holes, so the names inside are
    // observed the way `JSON.stringify` observes them.
    TemplateLiteral(_, exprs) =>
      for sub in exprs {
        seed_from_expr(sub, scope, obs, g, result, worklist)
      }
    // A comma expression's VALUE is its right operand; the left is
    // evaluated and discarded, so only the right is observed.
    Seq(_, r) => seed_from_expr(r, scope, obs, g, result, worklist)
    // `console.log(new C())` observes the INSTANCE, so C's members are
    // observable — but an anonymous `new` has no binding to seed, which
    // is why a binding held the fix (`const i = new C(); log(i)` was
    // already correct) and the direct form was not. Seed the class
    // declaration's own symbol instead;
    // `reserved_props_from_observability` turns an observed `ClassDecl`
    // into that class's member names.
    New(name, _) =>
      match lookup_symbol_in_scope(g, scope, name) {
        Some(id) => bump_obs(id, obs, result, worklist)
        None => ()
      }
    NewExpr(callee, _) =>
      seed_from_expr(callee, scope, obs, g, result, worklist)
    As(inner, _)
    | Satisfies(inner, _)
    | NonNull(inner)
    | OptionalChain(inner)
    | PureCall(inner)
    | TypeArgs(_, inner)
    | Await(inner) => seed_from_expr(inner, scope, obs, g, result, worklist)
    _ => ()
  }
}

///|
fn propagate_to_flow_source(
  src : FlowNode,
  obs : Observability,
  g : SymbolGraph,
  result : Map[SymbolId, Observability],
  worklist : Array[SymbolId],
) -> Unit {
  let visited : Map[SymbolId, Bool] = {}
  propagate_to_flow_source_visited(src, obs, g, result, worklist, visited)
}

///|
/// Recursion helper that tracks which function returns it has
/// already expanded. Mutually-recursive functions
/// (`A returns B(); B returns A();`) would otherwise blow the
/// stack — typescript's own bundle has dozens of these in its
/// generated parser.
fn propagate_to_flow_source_visited(
  src : FlowNode,
  obs : Observability,
  g : SymbolGraph,
  result : Map[SymbolId, Observability],
  worklist : Array[SymbolId],
  visited : Map[SymbolId, Bool],
) -> Unit {
  match src {
    SymVal(id) => bump_obs(id, obs, result, worklist)
    FuncReturn(fid) => {
      if visited.contains(fid) {
        return
      }
      visited[fid] = true
      // Also mark the function's own binding. An object literal
      // RETURNED by the function introduces keys that exist nowhere
      // else — `return { ...obj, g10: v }` — and nothing else in the
      // bundle can keep them. `symbol_graph.mbt` records the return
      // expressions on the function's symbol, and
      // `collect_direct_props` reserves their literal keys, but only
      // for a symbol the observability map contains.
      bump_obs(fid, obs, result, worklist)
      match g.funcs.get(fid) {
        Some(info) if func_returns_are_complete(g, fid) =>
          for ret in info.returns {
            propagate_to_flow_source_visited(
              ret, obs, g, result, worklist, visited,
            )
          }
        // Anonymous function, or a name that does not only ever hold
        // this one — either way the return set is not the whole story,
        // so fall back to the wildcard rather than to silence.
        _ => bump_obs(fid, External, result, worklist)
      }
    }
    FuncArg(_, _) => ()
    External | Unknown => ()
    Literal(_) => ()
  }
}

///|
fn bump_obs(
  sym : SymbolId,
  new_obs : Observability,
  result : Map[SymbolId, Observability],
  worklist : Array[SymbolId],
) -> Unit {
  let cur = result.get(sym).unwrap_or(Hidden)
  let joined = obs_join(cur, new_obs)
  if obs_rank(joined) > obs_rank(cur) {
    result[sym] = joined
    worklist.push(sym)
  }
}

// ---------------------------------------------------------------------------
// Reserved-props derivation
// ---------------------------------------------------------------------------

///|
/// Given the observability map, derive the set of property names
/// that need to stay reserved. For each binding the rule is:
///
///   - Hidden / ViaStringify: nothing (mangle-free).
///   - DirectProps           : reserve names appearing in
///     PropReceiver uses + literal-init keys of the binding.
///   - RecursiveProps        : same as DirectProps, plus reserve
///     the same surface on any binding the value transitively
///     points to. Phase 4 v1 approximates "transitively" by
///     collecting prop names on the *immediate* binding only and
///     widening to `*` whenever the binding's initializer is
///     anything other than a literal scalar / object literal /
///     function (i.e. when nested object refs flow through).
///   - External              : wildcard.
pub fn reserved_props_from_observability(
  g : SymbolGraph,
  obs_map : Map[SymbolId, Observability],
  type_env? : Map[String, @ast.TsType] = {},
  // Class name -> its own member names, from `class_member_names`. A
  // `ClassDecl` symbol has no initializer for `collect_direct_props` to
  // read, so without this an observed class contributes nothing and its
  // fields are deleted as dead.
  class_members? : Map[String, Array[String]] = {},
  // `--explain-mangle` attribution: `name -> the facts that reserved
  // it`. The report's section for this set is labelled "reaches a
  // side-effect sink", which is what the biggest contributor does but
  // NOT what the set is — it also holds an observed class's members, the
  // direct props of every DirectProps/RecursiveProps binding, and the
  // linker's synthesized namespace keys. On typebox the section lists
  // 340 names and the label explains none of them, which is why
  // narrowing the wildcard next door bought zero bytes: nobody could see
  // which fact was doing the work. Filled only when asked.
  provenance? : Map[String, Array[String]]? = None,
  // Binding names the LINKER synthesized as namespace objects, from
  // `LinkRenames.synthesized_namespaces`. `None` means the caller does
  // not know, and then the structural guess below is used — it
  // over-reserves, so not knowing is the safe direction.
  synthesized_namespaces? : Map[String, Bool]? = None,
) -> Map[String, Bool] {
  let out : Map[String, Bool] = {}
  // One `out[k] = true` plus one attribution, so the two cannot drift.
  fn keep(k : String, why : String) -> Unit {
    out[k] = true
    match provenance {
      Some(p) => {
        let seen = p.get(k).unwrap_or([])
        if !seen.contains(why) {
          seen.push(why)
        }
        p[k] = seen
      }
      None => ()
    }
  }
  // `collect_direct_props` writes into a plain map; route it through
  // `keep` so its names carry the same attribution as everything else.
  fn keep_direct(sym : Symbol, why : String) -> Unit {
    let tmp : Map[String, Bool] = {}
    collect_direct_props(sym, tmp)
    for k in tmp.keys() {
      keep(k, why)
    }
  }
  // Linker-synthesised namespace stand-ins (`const ns = { exp1:
  // resolved1, … }`, emitted by `synthesize_namespace_bindings_for`
  // in `bundle_link.mbt`) carry their entire member surface in
  // an ObjectLit initializer. Even when no observation sink seeds
  // them, calls like `ns.exp1()` and references like `ns.exp2`
  // need the exported names to stay reserved — otherwise the
  // ObjectLit keys get renamed but the linker's individual
  // export bindings don't (they live as separate top-level
  // symbols), and the namespace stops resolving its members.
  //
  // We can't tell user-written `const config = {…}` from a
  // synthesised namespace structurally, so apply the rule to
  // every Const-with-ObjectLit binding. The cost is reserving a
  // few extra literal-key names; the win is "import * as ns"
  // patterns survive property mangling correctly.
  for sym in g.symbols {
    if !(sym.kind is Const) {
      continue
    }
    match synthesized_namespaces {
      // The linker told us. Two names on typebox instead of the guess's
      // several dozen.
      Some(names) =>
        if names.contains(sym.name) {
          keep_direct(sym, "a linker-synthesized namespace object's keys")
        }
      // Nobody told us, so guess — and the guess over-reserves, which is
      // the safe direction for a caller that cannot answer.
      None =>
        if is_linker_synthesized_namespace(sym) {
          keep_direct(
            sym, "an object literal of bare `Var`s, GUESSED to be a linker-synthesized namespace",
          )
        }
    }
  }
  for entry in obs_map {
    let (sym_id, obs) = entry
    let sym = g.symbols[sym_id]
    // An observed class contributes the members its instances carry.
    // `console.log(new C())` prints C's own enumerable fields, so those
    // names are observable even though nothing in the bundle reads them
    // — which is exactly what the dead-field pass was deleting.
    if sym.kind is ClassDecl && obs_at_least_direct(obs) {
      match class_members.get(sym.name) {
        Some(names) =>
          for n in names {
            keep(n, "a member of observed class `\{sym.name}`")
          }
        None => ()
      }
    }
    match obs {
      Hidden | ViaStringify => ()
      DirectProps =>
        keep_direct(sym, "read off `\{sym.name}`, whose props a sink observes")
      RecursiveProps =>
        keep_direct(
          sym,
          "read off `\{sym.name}`, observed recursively by a sink",
        )
      External =>
        // External escapes default to the wildcard because we
        // can't statically know what the foreign callee inspects.
        // BUT when the binding carries a TypeScript annotation
        // with a closed key set (interface / object literal type
        // / union of those), the consumer can only legally read
        // those names — anything beyond that would already be a
        // type error. Reserve just those keys instead of the
        // wildcard so internal-only properties (renamed by the
        // type-graph walk in Phase 1) stay manglable.
        //
        // Falls through to `*` when the binding has no useful
        // annotation, is index-signature shaped, or references
        // an opaque named type. The Const+ObjectLit pre-pass
        // still catches the linker-synthesised namespace case
        // independently of this fallback.
        match type_observed_keys(sym.ts_type, type_env~) {
          Some(keys) => {
            for k in keys {
              keep(k, "declared on `\{sym.name}`, which leaves the bundle")
            }
            // Also include any PropReceiver-observed names —
            // they're real uses the caller might depend on.
            keep_direct(sym, "read off `\{sym.name}`, which leaves the bundle")
          }
          None => keep("*", "`\{sym.name}` leaves the bundle untyped")
        }
    }
  }
  out
}

///|
// Closed set of property keys observed when a value of type `t`
// flows to an external boundary. Mirrors the structural rule used
// in the checker: a concrete `Struct`, `Object` of all-literal
// keys, or a `Union` of such carries a bounded key set; anything
// else (index signatures, opaque `Named` references, `Any`,
// generic shapes) admits unbounded keys and the caller must keep
// the wildcard.
fn type_observed_keys(
  t : @ast.TsType,
  type_env? : Map[String, @ast.TsType] = {},
  seen? : Map[String, Bool] = {},
) -> Array[String]? {
  match t {
    Struct(_, fields) => {
      let out : Array[String] = []
      for f in fields {
        if !out.contains(f.0) {
          out.push(f.0)
        }
      }
      Some(out)
    }
    Object(fields) => {
      let out : Array[String] = []
      for f in fields {
        match f.0 {
          Literal(s) => if !out.contains(s) { out.push(s) }
          // String / Number / Symbol keys are index signatures —
          // the key set is unbounded at the type level.
          _ => return None
        }
      }
      Some(out)
    }
    Union(members) => {
      let combined : Array[String] = []
      for m in members {
        match type_observed_keys(m, type_env~, seen~) {
          Some(keys) =>
            for k in keys {
              if !combined.contains(k) {
                combined.push(k)
              }
            }
          None => return None
        }
      }
      Some(combined)
    }
    // An `interface`/`type` annotation is how a TypeScript codebase
    // actually spells a closed shape, so resolving the name is the
    // difference between "annotate it" being advice a user can follow
    // and advice that silently does nothing. `type_env` holds the
    // declarations the bundle itself parsed; a name that isn't there
    // came from somewhere we can't see, and stays unbounded.
    //
    // The key set is syntactic, so type ARGUMENTS never change it:
    // `Box<string>` and `Box<number>` have the same keys. A generic
    // body that computes its keys (a mapped type, `keyof`) has no arm
    // here and falls through to `None`, which is the safe answer.
    Named(n) | Applied(n, _) =>
      if seen.contains(n) {
        // A cyclic declaration (`interface Node { next: Node }`) is
        // fine — the recursion is on the type, not the key set — but
        // the walk still has to stop.
        Some([])
      } else {
        match type_env.get(n) {
          Some(resolved) => {
            seen[n] = true
            let keys = type_observed_keys(resolved, type_env~, seen~)
            seen.remove(n)
            keys
          }
          None => None
        }
      }
    // A primitive carries no user-declared property surface. Its members
    // are built-ins (`length`, `toFixed`, …) which the mangler reserves
    // globally anyway, so a `string` crossing the boundary reserves
    // nothing — it must not fall through to the wildcard.
    //
    // This mattered more than it looks. On real TypeScript libraries the
    // bindings that reached a foreign callee were overwhelmingly plain
    // `string` parameters (valibot: `lang`, `message`; a locale lookup
    // and an error message), and each one suppressed property mangling
    // for the entire bundle.
    Number
    | Int
    | Boolean
    | String_
    | BigInt
    | Symbol
    | Void
    | Null
    | Undefined
    | Never
    | Literal(_)
    | NumberLiteral(_)
    | BigIntLiteral(_)
    | BooleanLiteral(_) => Some([])
    // `A & B` observes the union of both key sets. Used to model
    // `interface I extends A, B`, so an unresolvable base collapses the
    // whole intersection to `None` rather than silently under-reserving.
    Intersection(members) => {
      let combined : Array[String] = []
      for m in members {
        match type_observed_keys(m, type_env~, seen~) {
          Some(keys) =>
            for k in keys {
              if !combined.contains(k) {
                combined.push(k)
              }
            }
          None => return None
        }
      }
      Some(combined)
    }
    _ => None
  }
}

///|
/// The type declarations a bundle parsed, as a name → shape map for
/// `type_observed_keys`.
///
/// An interface becomes an `Intersection` of its own fields and a
/// `Named` reference per base, so `extends` resolves through the same
/// recursion and an invisible base yields `None` instead of a key set
/// that is missing the base's names. An index signature admits
/// unbounded keys, so it is modelled as one — the caller keeps the
/// wildcard.
pub fn build_type_env(
  interfaces : Array[@ast.TsInterface],
  type_aliases : Array[@ast.TsTypeAlias],
) -> Map[String, @ast.TsType] {
  let env : Map[String, @ast.TsType] = {}
  for ta in type_aliases {
    env[ta.name] = ta.type_
  }
  for i in interfaces {
    let own : @ast.TsType = if i.index_signatures.length() > 0 {
      @ast.TsType::Object([(@ast.TsType::String_, @ast.TsType::Any)])
    } else {
      @ast.TsType::Struct(i.name, i.fields)
    }
    if i.extends_names.length() == 0 {
      env[i.name] = own
    } else {
      let parts : Array[@ast.TsType] = [own]
      for b in i.extends_names {
        parts.push(@ast.TsType::Named(b))
      }
      env[i.name] = @ast.TsType::Intersection(parts)
    }
  }
  env
}

///|
fn obs_at_least_direct(obs : Observability) -> Bool {
  match obs {
    DirectProps | RecursiveProps | External => true
    Hidden | ViaStringify => false
  }
}

///|
/// Every member name a class puts on its instances or on itself:
/// declared methods, static fields, and the `this.x = …` writes the
/// constructor performs (which is what a `class C { x = 1 }` field
/// lowers to).
///
/// Keyed by class name. Two classes sharing a name across modules merge,
/// which over-reserves rather than under-reserves.
pub fn class_member_names(block : @ast.TsBlock) -> Map[String, Array[String]] {
  let out : Map[String, Array[String]] = {}
  fn record(class_name : String, member : String) -> Unit {
    let names = match out.get(class_name) {
      Some(existing) => existing
      None => {
        let fresh : Array[String] = []
        out[class_name] = fresh
        fresh
      }
    }
    if !names.contains(member) {
      names.push(member)
    }
  }

  fn visit_stmt(s : @ast.TsStmt) -> Unit {
    match s {
      @ast.TsStmt::NativeClassStmt(decl, ctor) => {
        for m in decl.methods {
          record(decl.name, m.name)
        }
        for sf in decl.static_field_inits {
          record(decl.name, sf.0)
        }
        // Instance fields arrive as constructor assignments.
        match ctor {
          Some(f) =>
            for cs in f.body.stmts {
              match cs {
                @ast.TsStmt::PropAssign(@ast.TsExpr::Var("this"), n, _) =>
                  record(decl.name, n)
                @ast.TsStmt::Expr(
                  @ast.TsExpr::PropAssignExpr(@ast.TsExpr::Var("this"), n, _)
                ) => record(decl.name, n)
                _ => ()
              }
            }
          None => ()
        }
      }
      @ast.TsStmt::Block(b) =>
        for inner in b.stmts {
          visit_stmt(inner)
        }
      @ast.TsStmt::If(_, t, e) => {
        for inner in t.stmts {
          visit_stmt(inner)
        }
        match e {
          Some(b) =>
            for inner in b.stmts {
              visit_stmt(inner)
            }
          None => ()
        }
      }
      _ => ()
    }
  }

  for s in block.stmts {
    visit_stmt(s)
  }
  out
}

///|
fn collect_direct_props(sym : Symbol, out : Map[String, Bool]) -> Unit {
  for u in sym.uses {
    match u.context {
      PropReceiver(p) => out[p] = true
      _ => ()
    }
  }
  for d in sym.defs {
    match d.init {
      Some(@ast.TsExpr::ObjectLit(entries)) =>
        for ent in entries {
          out[ent.0] = true
        }
      _ => ()
    }
  }
  // Keys of every object literal WRITTEN into this binding. The flow
  // edge added for `obj.q = { ...bag, g7: v }` carries the target's
  // observability to `bag`, but `g7` names nothing else in the bundle,
  // so nothing else could keep it. Collected through nesting, because
  // an observed target observes the whole shape it holds.
  for v in sym.written_values {
    collect_literal_keys(v, out)
  }
}

///|
/// Every property key spelled by an object literal inside `expr`.
fn collect_literal_keys(expr : @ast.TsExpr, out : Map[String, Bool]) -> Unit {
  match expr {
    ObjectLit(entries) =>
      for ent in entries {
        // The parser spells a spread as `("@@spread:N", expr)` and a
        // computed key as `("@@computed:N", ComputedProp(k, v))`;
        // neither is a literal name to reserve.
        if !ent.0.has_prefix("@@") {
          out[ent.0] = true
        }
        collect_literal_keys(ent.1, out)
      }
    ArrayLit(items) =>
      for it in items {
        collect_literal_keys(it, out)
      }
    Spread(inner) | ComputedProp(_, inner) => collect_literal_keys(inner, out)
    Cond(_, t, e) => {
      collect_literal_keys(t, out)
      collect_literal_keys(e, out)
    }
    As(inner, _) | Satisfies(inner, _) | NonNull(inner) | TypeArgs(_, inner) =>
      collect_literal_keys(inner, out)
    _ => ()
  }
}

///|
/// Recognise the linker's synthesised-namespace shape:
///
///     const ns = { exp1: resolved1, exp2: resolved2, … };
///
/// where every value is a `Var(...)` referring to another
/// top-level binding (the resolved imported export). User-
/// authored object literals typically include at least one
/// scalar / call / nested-object value, so the "all values are
/// bare Var refs" shape is a strong heuristic for the linker's
/// `synthesize_namespace_bindings_for` output. Distinguishing
/// the two matters: synthesised namespaces NEED their literal
/// keys reserved (consumers will read them by name), but
/// user-written `const config = { y: 1 }` needs `y` to stay
/// drop-eligible for `drop_dead_properties` when no one reads
/// it.
fn is_linker_synthesized_namespace(sym : Symbol) -> Bool {
  for d in sym.defs {
    match d.init {
      Some(@ast.TsExpr::ObjectLit(entries)) => {
        if entries.length() == 0 {
          continue
        }
        let mut all_var_refs = true
        for ent in entries {
          match ent.1 {
            @ast.TsExpr::Var(_) => ()
            _ => {
              all_var_refs = false
              break
            }
          }
        }
        if all_var_refs {
          return true
        }
      }
      _ => ()
    }
  }
  false
}
