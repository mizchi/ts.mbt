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
} derive(Eq, Show)

///|
/// Lattice join: max of the two arguments according to the
/// ordering `Hidden < ViaStringify < DirectProps < RecursiveProps
/// < External`. Used by the fixed-point loop so observability
/// can only grow.
fn obs_join(a : Observability, b : Observability) -> Observability {
  let av = obs_rank(a)
  let bv = obs_rank(b)
  if av >= bv { a } else { b }
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
  let arg_edges_by_param : Map[SymbolId, Array[FlowNode]] = {}
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
    for edge in g.flow_edges {
      if edge.to is SymVal(s) && s == sym {
        propagate_to_flow_source(
          edge.from, target, g, result, worklist,
        )
      }
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
    PropAccess(recv, _) =>
      seed_from_expr(recv, scope, obs, g, result, worklist)
    MethodCall(recv, _, _) =>
      seed_from_expr(recv, scope, obs, g, result, worklist)
    IndexAccess(recv, _) =>
      seed_from_expr(recv, scope, obs, g, result, worklist)
    Call(callee, _) =>
      match lookup_symbol_in_scope(g, scope, callee) {
        Some(fid) =>
          match g.funcs.get(fid) {
            Some(info) =>
              for src in info.returns {
                propagate_to_flow_source(src, obs, g, result, worklist)
              }
            None => bump_obs(fid, External, result, worklist)
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
            Some(info) =>
              for src in info.returns {
                propagate_to_flow_source(src, obs, g, result, worklist)
              }
            None => bump_obs(id, External, result, worklist)
          }
        None => ()
      }
    }
    Cond(_, t, e) => {
      seed_from_expr(t, scope, obs, g, result, worklist)
      seed_from_expr(e, scope, obs, g, result, worklist)
    }
    BinOp(_, _, r) =>
      seed_from_expr(r, scope, obs, g, result, worklist)
    As(inner, _) | Satisfies(inner, _) | NonNull(inner)
    | OptionalChain(inner) | PureCall(inner) | Await(inner) =>
      seed_from_expr(inner, scope, obs, g, result, worklist)
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
      match g.funcs.get(fid) {
        Some(info) =>
          for ret in info.returns {
            propagate_to_flow_source_visited(
              ret, obs, g, result, worklist, visited,
            )
          }
        // Anonymous function — can't pin down the source.
        None => ()
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
) -> Map[String, Bool] {
  let out : Map[String, Bool] = {}
  for entry in obs_map {
    let (sym_id, obs) = entry
    let sym = g.symbols[sym_id]
    match obs {
      Hidden | ViaStringify => ()
      DirectProps => collect_direct_props(sym, out)
      RecursiveProps => collect_direct_props(sym, out)
      External =>
        // The binding escapes through an external call / prop
        // assignment, OR through one of the linker's synthesised
        // namespace objects (the `import * as util from
        // "./mod"` pattern, where `util` is built up at link
        // time and the per-prop assignments aren't visible as
        // source-level `util.foo = …` writes). Without
        // distinguishing those, fall back to `*` — preserving
        // the conservative behaviour the older
        // collect-reflection-sinks path used. (Phase 5+:
        // thread the linker's namespace synthesis into the
        // graph so the safe-to-rename External cases can be
        // refined.)
        out["*"] = true
    }
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
}

///|
fn binding_carries_nested_values(sym : Symbol) -> Bool {
  // ObjectLit with non-scalar values, or any init we couldn't
  // classify as a pure leaf, means the value tree extends past
  // this binding — recursive observation could reach further.
  for d in sym.defs {
    match d.init {
      Some(@ast.TsExpr::ObjectLit(entries)) =>
        for ent in entries {
          if not(is_leaf_value(ent.1)) {
            return true
          }
        }
      Some(@ast.TsExpr::ArrayLit(items)) =>
        for it in items {
          if not(is_leaf_value(it)) {
            return true
          }
        }
      Some(@ast.TsExpr::Call(_, _))
      | Some(@ast.TsExpr::CallExpr(_, _))
      | Some(@ast.TsExpr::MethodCall(_, _, _))
      | Some(@ast.TsExpr::New(_, _))
      | Some(@ast.TsExpr::NewExpr(_, _))
      | Some(@ast.TsExpr::PropAccess(_, _))
      | Some(@ast.TsExpr::IndexAccess(_, _)) => return true
      _ => ()
    }
  }
  false
}

///|
fn is_leaf_value(expr : @ast.TsExpr) -> Bool {
  match expr {
    NumberLit(_) | IntLit(_) | BigIntLit(_) | BoolLit(_)
    | StringLit(_) | NullLit | ArrayHole => true
    _ => false
  }
}
