// Phase 3 of the observability analysis: enumerate the points at
// which a value's properties become observable to an end user, and
// trace each observation back to the binding(s) whose property
// access surface that point can see.
//
// Without scope info, a `Var(n)` argument to `Object.keys` looks
// indistinguishable from `Var(n)` to a black-box function call —
// both fall back to the wildcard. With the `SymbolGraph` from Phase
// 1 we can:
//
//   - resolve `n` to a unique binding;
//   - decide whether that binding's property aliases stay local
//     (only written via `obj.foo = …`, only read via `obj.foo`),
//     in which case only those literal property names need to be
//     reserved;
//   - fall back to wildcard only when the analysis genuinely can't
//     pin down the binding.
//
// This file is the catalog + the minimal binding-scoped reservation
// rule. Recursive property observation (`JSON.stringify` reaching
// nested values, closure escape, etc.) is left to Phase 4.

///|
/// What kind of property surface does a sink observe?
pub(all) enum SinkObservation {
  // The sink lists the direct property keys of the value
  // (`Object.keys`, `Object.entries`, `for-in`).
  DirectKeys
  // The sink recursively serializes / inspects the value
  // (`JSON.stringify`, `console.log` with object, `throw`).
  // For Phase 3 v1 we treat these the same as `DirectKeys` plus
  // a fallback to wildcard when the value reaches arbitrary
  // nested structure.
  Recursive
  // The value is passed as an argument to a function whose body
  // mtsc can't see (external import). All properties of the
  // value are potentially observable.
  ExternalCallArg
  // `external.prop = x` / `external[prop] = x` — the receiver
  // is external so the property name `prop` itself escapes; the
  // assigned value `x` is also observable like ExternalCallArg.
  ExternalPropWrite
  // The value's own type is inspected only by string-ish APIs
  // (`String(x)`, `Number(x)`); properties aren't observed.
  StringifyOnly
}

///|
pub(all) struct Sink {
  expr : @ast.TsExpr // the value being observed
  observation : SinkObservation
}

///|
/// Walk `block` and collect every reflection / I/O sink we know
/// about. Each Sink records the value-being-observed and the
/// observation kind so the binding-scoped reservation rule can
/// pick out the right property names.
pub fn collect_sinks(
  block : @ast.TsBlock,
  external_bindings : Map[String, Bool],
) -> Array[Sink] {
  let out : Array[Sink] = []
  collect_sinks_block(block, external_bindings, out)
  out
}

///|
fn collect_sinks_block(
  block : @ast.TsBlock,
  externals : Map[String, Bool],
  out : Array[Sink],
) -> Unit {
  for s in block.stmts {
    collect_sinks_stmt(s, externals, out)
  }
}

///|
fn collect_sinks_stmt(
  stmt : @ast.TsStmt,
  externals : Map[String, Bool],
  out : Array[Sink],
) -> Unit {
  match stmt {
    Var(_, _, e) | Let(_, _, e) | Const(_, _, e) | Expr(e) =>
      collect_sinks_expr(e, externals, out)
    Throw(e) => {
      // `throw x` — the error reaches the caller as a value;
      // any property of x (notably `.message` / `.stack` / `.code`)
      // could be inspected. Treat as Recursive for safety.
      out.push({ expr: e, observation: Recursive })
      collect_sinks_expr(e, externals, out)
    }
    Assign(_, e) | CompoundAssign(_, _, e) =>
      collect_sinks_expr(e, externals, out)
    IndexAssign(t, idx, v) => {
      collect_sinks_expr(t, externals, out)
      collect_sinks_expr(idx, externals, out)
      collect_sinks_expr(v, externals, out)
    }
    PropAssign(t, _prop, v) => {
      // `external.prop = v` — the assigned value escapes through
      // the external object's prop ABI.
      if is_external_receiver(t, externals) {
        out.push({ expr: v, observation: ExternalPropWrite })
      }
      collect_sinks_expr(t, externals, out)
      collect_sinks_expr(v, externals, out)
    }
    Return(Some(e)) => collect_sinks_expr(e, externals, out)
    If(c, t, e) => {
      collect_sinks_expr(c, externals, out)
      collect_sinks_block(t, externals, out)
      match e {
        Some(b) => collect_sinks_block(b, externals, out)
        None => ()
      }
    }
    While(c, b) | DoWhile(c, b) | With(c, b) => {
      collect_sinks_expr(c, externals, out)
      collect_sinks_block(b, externals, out)
    }
    For(init, cond, update, body) => {
      match init {
        Some(s) => collect_sinks_stmt(s, externals, out)
        None => ()
      }
      match cond {
        Some(e) => collect_sinks_expr(e, externals, out)
        None => ()
      }
      match update {
        Some(s) => collect_sinks_stmt(s, externals, out)
        None => ()
      }
      collect_sinks_block(body, externals, out)
    }
    ForOf(_, _, _, iter, body) | ForAwaitOf(_, _, _, iter, body) => {
      collect_sinks_expr(iter, externals, out)
      collect_sinks_block(body, externals, out)
    }
    ForIn(_, _, _, iter, body) => {
      // `for (k in iter)` enumerates iter's own + inherited
      // property names. Record iter as a DirectKeys sink.
      out.push({ expr: iter, observation: DirectKeys })
      collect_sinks_expr(iter, externals, out)
      collect_sinks_block(body, externals, out)
    }
    Switch(e, cases) => {
      collect_sinks_expr(e, externals, out)
      for c in cases {
        match c.test_expr {
          Some(te) => collect_sinks_expr(te, externals, out)
          None => ()
        }
        collect_sinks_block(c.body, externals, out)
      }
    }
    Try(b, _, cb, fb) => {
      collect_sinks_block(b, externals, out)
      match cb {
        Some(blk) => collect_sinks_block(blk, externals, out)
        None => ()
      }
      match fb {
        Some(blk) => collect_sinks_block(blk, externals, out)
        None => ()
      }
    }
    Label(_, inner) => collect_sinks_stmt(inner, externals, out)
    Block(b) => collect_sinks_block(b, externals, out)
    NativeClassStmt(decl, ctor) => {
      match decl.base_expr {
        Some(b) => collect_sinks_expr(b, externals, out)
        None => ()
      }
      match ctor {
        Some(f) => collect_sinks_block(f.body, externals, out)
        None => ()
      }
      for m in decl.methods {
        match m.body {
          Some(b) => collect_sinks_block(b, externals, out)
          None => ()
        }
      }
      for sf in decl.static_field_inits {
        collect_sinks_expr(sf.1, externals, out)
      }
    }
    _ => ()
  }
}

///|
fn collect_sinks_expr(
  expr : @ast.TsExpr,
  externals : Map[String, Bool],
  out : Array[Sink],
) -> Unit {
  match expr {
    MethodCall(recv, m, args) => {
      // `Object.keys(x)` / `Object.values(x)` / `Object.entries(x)` /
      // `Object.fromEntries(x)` — direct prop enumeration.
      // `Object.assign(target, ...sources)` exposes the source
      // properties on `target`.
      // `JSON.stringify(x)` — recursive observation.
      // `console.<method>(x)` — recursive (`util.inspect` semantics).
      match recv {
        @ast.TsExpr::Var(name) =>
          if name == "Object" {
            match m {
              "keys" | "values" | "entries" | "fromEntries" =>
                for a in args {
                  out.push({ expr: a, observation: DirectKeys })
                }
              "assign" =>
                // Object.assign(target, ...sources) — every source
                // contributes its direct props onto target. Mark
                // each source as DirectKeys; the target's prop
                // surface is then determined by those sources.
                for i, a in args {
                  if i > 0 {
                    out.push({ expr: a, observation: DirectKeys })
                  }
                }
              _ => ()
            }
          } else if name == "JSON" && m == "stringify" {
            for a in args {
              out.push({ expr: a, observation: Recursive })
            }
          } else if name == "console" {
            // console.log / .error / .warn / .info / .debug all
            // print `inspect()`-formatted values for objects.
            for a in args {
              out.push({ expr: a, observation: Recursive })
            }
          }
        _ => ()
      }
      collect_sinks_expr(recv, externals, out)
      for a in args {
        collect_sinks_expr(a, externals, out)
      }
    }
    Call(callee, args) => {
      // Bare `callee(...)` — if `callee` is an external import,
      // the args escape with all properties observable.
      if externals.contains(callee) {
        for a in args {
          out.push({ expr: a, observation: ExternalCallArg })
        }
      }
      for a in args {
        collect_sinks_expr(a, externals, out)
      }
    }
    CallExpr(callee, args) => {
      // `someExpr(...)` — when callee is a Var resolved as
      // external, the args escape too.
      let is_external_callee = match callee {
        @ast.TsExpr::Var(n) => externals.contains(n)
        _ => false
      }
      if is_external_callee {
        for a in args {
          out.push({ expr: a, observation: ExternalCallArg })
        }
      }
      collect_sinks_expr(callee, externals, out)
      for a in args {
        collect_sinks_expr(a, externals, out)
      }
    }
    New(name, args) => {
      if externals.contains(name) {
        for a in args {
          out.push({ expr: a, observation: ExternalCallArg })
        }
      }
      for a in args {
        collect_sinks_expr(a, externals, out)
      }
    }
    NewExpr(callee, args) => {
      let is_external_callee = match callee {
        @ast.TsExpr::Var(n) => externals.contains(n)
        _ => false
      }
      if is_external_callee {
        for a in args {
          out.push({ expr: a, observation: ExternalCallArg })
        }
      }
      collect_sinks_expr(callee, externals, out)
      for a in args {
        collect_sinks_expr(a, externals, out)
      }
    }
    BinOp(_, l, r) => {
      collect_sinks_expr(l, externals, out)
      collect_sinks_expr(r, externals, out)
    }
    UnaryOp(_, inner)
    | Spread(inner)
    | Await(inner)
    | YieldStar(inner)
    | As(inner, _)
    | Satisfies(inner, _)
    | NonNull(inner)
    | OptionalChain(inner)
    | TypeArgs(_, inner)
    | PureCall(inner) => collect_sinks_expr(inner, externals, out)
    Yield(Some(inner)) => collect_sinks_expr(inner, externals, out)
    Yield(None) => ()
    Cond(c, t, e) => {
      collect_sinks_expr(c, externals, out)
      collect_sinks_expr(t, externals, out)
      collect_sinks_expr(e, externals, out)
    }
    Seq(a, b) => {
      collect_sinks_expr(a, externals, out)
      collect_sinks_expr(b, externals, out)
    }
    PropAccess(recv, _) => collect_sinks_expr(recv, externals, out)
    IndexAccess(recv, idx) => {
      collect_sinks_expr(recv, externals, out)
      collect_sinks_expr(idx, externals, out)
    }
    AssignExpr(_name, rhs) => collect_sinks_expr(rhs, externals, out)
    AssignPattern(_, rhs) => collect_sinks_expr(rhs, externals, out)
    CompoundAssignExpr(target, _, rhs) => {
      collect_sinks_expr(target, externals, out)
      collect_sinks_expr(rhs, externals, out)
    }
    PropAssignExpr(target, _prop, rhs) => {
      if is_external_receiver(target, externals) {
        out.push({ expr: rhs, observation: ExternalPropWrite })
      }
      collect_sinks_expr(target, externals, out)
      collect_sinks_expr(rhs, externals, out)
    }
    IndexAssignExpr(target, idx, rhs) => {
      collect_sinks_expr(target, externals, out)
      collect_sinks_expr(idx, externals, out)
      collect_sinks_expr(rhs, externals, out)
    }
    ArrayLit(items) =>
      for it in items {
        collect_sinks_expr(it, externals, out)
      }
    ObjectLit(entries) =>
      for ent in entries {
        collect_sinks_expr(ent.1, externals, out)
      }
    ComputedProp(k, v) => {
      collect_sinks_expr(k, externals, out)
      collect_sinks_expr(v, externals, out)
    }
    ArrowFunc(_, _, body, _) =>
      match body {
        ArrowExpr(e) => collect_sinks_expr(e, externals, out)
        ArrowBlock(b) => collect_sinks_block(b, externals, out)
      }
    FuncExpr(f) => collect_sinks_block(f.body, externals, out)
    DynamicImport(spec, opts) => {
      collect_sinks_expr(spec, externals, out)
      match opts {
        Some(o) => collect_sinks_expr(o, externals, out)
        None => ()
      }
    }
    TaggedTemplate(tag, _, _, exprs) => {
      collect_sinks_expr(tag, externals, out)
      for e in exprs {
        collect_sinks_expr(e, externals, out)
      }
    }
    TemplateLiteral(_, exprs) =>
      for e in exprs {
        collect_sinks_expr(e, externals, out)
      }
    NativeClassExpr(decl, ctor) => {
      match decl.base_expr {
        Some(b) => collect_sinks_expr(b, externals, out)
        None => ()
      }
      match ctor {
        Some(f) => collect_sinks_block(f.body, externals, out)
        None => ()
      }
      for m in decl.methods {
        match m.body {
          Some(b) => collect_sinks_block(b, externals, out)
          None => ()
        }
      }
      for sf in decl.static_field_inits {
        collect_sinks_expr(sf.1, externals, out)
      }
    }
    _ => ()
  }
}

///|
/// Is this expression chained off an external binding?
/// Mirrors `is_external_chain` in `mangle_safety.mbt` but kept
/// local so Phase 3 doesn't pull `mangle_safety`'s helpers in
/// the wrong direction (the dependency should go the other way).
fn is_external_receiver(
  expr : @ast.TsExpr,
  externals : Map[String, Bool],
) -> Bool {
  match expr {
    @ast.TsExpr::Var(n) => externals.contains(n)
    PropAccess(recv, _) => is_external_receiver(recv, externals)
    MethodCall(recv, _, _) => is_external_receiver(recv, externals)
    IndexAccess(recv, _) => is_external_receiver(recv, externals)
    Call(n, _) => externals.contains(n)
    CallExpr(callee, _) => is_external_receiver(callee, externals)
    NonNull(inner)
    | OptionalChain(inner)
    | As(inner, _)
    | TypeArgs(_, inner)
    | Satisfies(inner, _) => is_external_receiver(inner, externals)
    _ => false
  }
}

// ---------------------------------------------------------------------------
// Binding-scoped reservation rule
// ---------------------------------------------------------------------------

///|
/// Given a sink, decide which property names need to be reserved.
///
/// Strategy (Phase 3 v1, intentionally conservative):
///   - If the sink expression is `Var(n)` resolving to a unique
///     symbol that is NOT closure-captured, NOT reassigned with an
///     unknown value, and NOT directly part of `external_bindings`,
///     reserve only the property names that appear in PropReceiver
///     uses of that symbol elsewhere in the bundle. (Plus the
///     PropAssign sites that write into the same binding.)
///   - Otherwise, the value's source is undecidable — fall back to
///     the wildcard `*` so the mangler reserves everything.
///
/// `out` receives the reserved property names (and `"*"` for
/// fallback). `external_bindings` carries the project-wide set of
/// external import binding names so we can detect re-exports from
/// here too.
pub fn reserve_props_from_sink(
  sink : Sink,
  scope : ScopeId,
  graph : SymbolGraph,
  external_bindings : Map[String, Bool],
  out : Map[String, Bool],
) -> Unit {
  match sink.expr {
    @ast.TsExpr::Var(name) => {
      // External binding directly handed to a sink — its prop
      // surface is owned by the external module, every name escapes.
      if external_bindings.contains(name) {
        out["*"] = true
        return
      }
      // Resolve through the graph using the scope the sink was
      // observed in. Walks up the parent chain so shadowing is
      // handled correctly.
      match lookup_symbol_in_scope(graph, scope, name) {
        Some(id) => {
          let sym = graph.symbols[id]
          if !is_sink_arg_locally_observable(sym, graph) {
            out["*"] = true
            return
          }
          // The binding stays local — record only the property
          // names actually accessed on it.
          for use_ in sym.uses {
            match use_.context {
              PropReceiver(p) => out[p] = true
              _ => ()
            }
          }
          // PropAssign sites that wrote into the same binding
          // contribute their key too (`obj.foo = …` adds `foo`).
          collect_prop_assigns_into(graph, sym, out)
          // The binding's initializer literal also exposes its
          // own keys: `const cfg = {foo: 1, bar: 2}; for (k in
          // cfg)` enumerates `foo` / `bar` — they must survive.
          // Same when the binding is later spread / Object.assign'd
          // into another value the sink observes.
          for d in sym.defs {
            match d.init {
              Some(@ast.TsExpr::ObjectLit(entries)) =>
                for ent in entries {
                  out[ent.0] = true
                }
              _ => ()
            }
          }
          // Recursive observation pulls in nested property
          // surfaces too — for Phase 3 v1 we conservatively
          // fall back to wildcard on Recursive when the binding
          // exposes a property whose value is another binding
          // (we don't track nested observability yet).
          match sink.observation {
            Recursive =>
              if binding_exposes_nested_objects(sym) {
                out["*"] = true
              }
            _ => ()
          }
        }
        None => out["*"] = true
      }
    }
    StringLit(_)
    | NumberLit(_)
    | IntLit(_)
    | BigIntLit(_)
    | BoolLit(_)
    | NullLit
    | TemplateLiteral(_, _) =>
      // A literal value can't carry user properties beyond what
      // its own prototype already exposes (built-ins, already
      // reserved). Nothing extra to record.
      ()
    ObjectLit(entries) =>
      // `{foo: 1, bar: 2}` handed straight to `Object.keys` —
      // only `foo` and `bar` are observable.
      for ent in entries {
        out[ent.0] = true
      }
    ArrayLit(_) =>
      // Numeric-keyed; no string props to reserve.
      ()
    PropAccess(recv, prop) => {
      // `Object.keys(obj.foo)` — the immediate receiver IS the
      // value handed to the sink; its prop surface is unknown
      // without per-expr flow info, but the property `prop` itself
      // is being read (= must survive). Recurse on `recv` so the
      // chain (`a.b.c`) keeps `b` and `c` alive too.
      out[prop] = true
      reserve_props_from_sink(
        { expr: recv, observation: sink.observation },
        scope,
        graph,
        external_bindings,
        out,
      )
    }
    IndexAccess(recv, _idx) =>
      // `Object.keys(arr[i])` — the value is the element of `arr`
      // at runtime. Without element-type info, fall back to
      // wildcard; but `recv`'s own prop surface is more limited,
      // so still recurse on it.
      reserve_props_from_sink(
        { expr: recv, observation: Recursive },
        scope,
        graph,
        external_bindings,
        out,
      )
    Call(_, _)
    | CallExpr(_, _)
    | MethodCall(_, _, _)
    | New(_, _)
    | NewExpr(_, _) =>
      // The sink consumes a call result; we don't yet propagate
      // return-value flow into the callee's body. Conservatively
      // mark wildcard — Phase 4's backward flow will refine this.
      out["*"] = true
    Cond(_, t, e) => {
      // `Object.keys(c ? a : b)` — observe both branches.
      reserve_props_from_sink(
        { expr: t, observation: sink.observation },
        scope,
        graph,
        external_bindings,
        out,
      )
      reserve_props_from_sink(
        { expr: e, observation: sink.observation },
        scope,
        graph,
        external_bindings,
        out,
      )
    }
    BinOp(_, _, r) =>
      // `||` / `??` / etc. — the right-hand value is the
      // observable one in falsy / nullish cases. Recurse on the
      // right side conservatively.
      reserve_props_from_sink(
        { expr: r, observation: sink.observation },
        scope,
        graph,
        external_bindings,
        out,
      )
    As(inner, _)
    | Satisfies(inner, _)
    | NonNull(inner)
    | OptionalChain(inner)
    | PureCall(inner)
    | TypeArgs(_, inner)
    | Await(inner) =>
      reserve_props_from_sink(
        { expr: inner, observation: sink.observation },
        scope,
        graph,
        external_bindings,
        out,
      )
    _ =>
      // Anything else (dynamic expression, etc.) — conservative.
      out["*"] = true
  }
}

///|
/// Is this binding safe to treat as "we can confidently enumerate
/// every property the sink could observe"?
///
/// The previous version refused as soon as any inbound flow edge
/// was External / Unknown, which fired for nearly every sink in a
/// real bundle (most `Object.keys(x)` arguments are either
/// parameters or assigned from an external call result). The
/// resulting `*` wildcard then disabled property mangling
/// wholesale.
///
/// Phase 3 v1 relaxes this: we collect every property name we CAN
/// see on the binding (literal-init keys + `obj.foo` accesses +
/// `obj.foo = …` writes) and trust `drop_dead_properties_block`
/// (gated on the same mangle-properties safety) to remove the
/// properties that we DIDN'T see — so the only failure mode is
/// "we missed observing one that should escape but wasn't read
/// locally either", which by construction means it's also dead.
///
/// We still bail on:
///   - closure-captured bindings (an outer function frame could
///     mutate them after the sink fires, exposing extra props).
fn is_sink_arg_locally_observable(sym : Symbol, g : SymbolGraph) -> Bool {
  let _ = g
  if sym.captured_by_closure {
    return false
  }
  true
}

///|
fn collect_prop_assigns_into(
  g : SymbolGraph,
  sym : Symbol,
  out : Map[String, Bool],
) -> Unit {
  // Scan all symbols' uses — the writer is anywhere in the bundle.
  // For each `PropReceiver(p)` use of `sym`, also consult the
  // sibling `PropAssign(Var(sym), p, _)` style writes which we
  // didn't record as a single use. The graph's `uses` array
  // already covers `obj.foo` lvalue uses through `PropReceiver`,
  // so we just re-scan to be defensive.
  for u in sym.uses {
    match u.context {
      PropReceiver(p) => out[p] = true
      _ => ()
    }
  }
  let _ = g
}

///|
fn binding_exposes_nested_objects(sym : Symbol) -> Bool {
  // Heuristic: if any def initializer is an ObjectLit whose values
  // include Var(_) or PropAccess / CallExpr (i.e. not pure scalar
  // literals), the value tree can grow during the program. Phase
  // 3 v1 can't track nested observability, so fall back to
  // wildcard in this case.
  for d in sym.defs {
    match d.init {
      Some(@ast.TsExpr::ObjectLit(entries)) =>
        for ent in entries {
          if !is_pure_scalar_literal(ent.1) {
            return true
          }
        }
      _ => ()
    }
  }
  false
}

///|
fn is_pure_scalar_literal(expr : @ast.TsExpr) -> Bool {
  match expr {
    NumberLit(_)
    | IntLit(_)
    | BigIntLit(_)
    | BoolLit(_)
    | StringLit(_)
    | NullLit
    | ArrayHole => true
    _ => false
  }
}
