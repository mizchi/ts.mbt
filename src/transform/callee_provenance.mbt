// Where does a value come from, and who is on the other side of a
// call?
//
// This is the inverted half of the sink rule (see `pure_builtins.mbt`
// for the allowlist and why the inversion matters). The old rule asked
// "is this one of the calls I know to be dangerous?" and reserved
// nothing when the answer was no. The rule here asks "can I PROVE the
// callee is bundle-internal?" and reserves when the answer is no.
//
// Two questions, one recursion:
//
//   * `value_is_host_shaped(e)` — is `e`'s value owned by something
//     outside the bundle? An imported binding, an ambient global, the
//     result of a call into either, `JSON.parse` output, a parameter
//     the host fills in. Names read off such a value belong to
//     somebody else's ABI, so they can't be renamed.
//   * `classify_callee(callee)` — calling a host-shaped value is a
//     foreign call, and every argument of a foreign call escapes.
//
// They feed each other: the result of a foreign call is host-shaped,
// and calling a host-shaped value is a foreign call. `host_shaped_value_names`
// runs the resulting equations to a fixed point over a whole block
// before the symbol graph walk starts, so the walk can classify each
// call site with the provenance of every binding already known.

///|
/// Who answers when this callee is called?
enum CalleeClass {
  /// A binding the bundle declares. Whatever it does with its
  /// arguments is code the analysis can see, so the flow analysis
  /// handles it via `FuncArg` / `FuncReturn` edges.
  InternalCallee
  /// A host built-in from the `pure_builtins.mbt` allowlist: either
  /// name-blind, or already modelled as a precise sink.
  PureBuiltinCallee
  /// Anything else. The body is invisible, so every argument's
  /// property names escape.
  ForeignCallee
} derive(Eq, Show)

///|
/// The facts a provenance question needs.
///
/// `resolves` is how the two callers differ. The pre-pass (which runs
/// before any symbol graph exists) answers "yes" for every name, so it
/// decides purely on the known-host-name sets. The symbol-graph walk
/// answers from the live scope chain, which adds the fail-closed rule
/// "a name no scope declares is provided by the host".
priv struct CalleeCtx {
  // Names whose value is owned by the host.
  roots : Map[String, Bool]
  // Bundle functions that return a host-shaped value, so that a thin
  // wrapper (`function load() { return fetch(u); }`) doesn't launder
  // provenance away.
  host_returning : Map[String, Bool]
  // Does some scope declare this name?
  resolves : (String) -> Bool
}

///|
fn classify_callee(callee : @ast.TsExpr, ctx : CalleeCtx) -> CalleeClass {
  // The allowlist wins first, but only for an unshadowed host name:
  // a bundle that declares its own `Math` gets no exemption.
  match callee {
    PropAccess(@ast.TsExpr::Var(ns), m) =>
      if is_pure_static_member(ns, m) && !(ctx.resolves)(ns) {
        return PureBuiltinCallee
      }
    Var(n) =>
      if is_pure_global_function(n) && !(ctx.resolves)(n) {
        return PureBuiltinCallee
      }
    _ => ()
  }
  if value_is_host_shaped(callee, ctx) {
    ForeignCallee
  } else {
    InternalCallee
  }
}

///|
/// Is the value this expression produces owned by the host?
///
/// Every arm is spelled out rather than ending in a `_` fallback: a
/// new AST node should surface as a compile error here, not silently
/// pick a default. The shapes that DO default are grouped at the
/// bottom, and they default to `true` — an expression form nobody
/// taught this function about is treated as host-owned, which
/// over-reserves rather than renaming something it shouldn't.
fn value_is_host_shaped(expr : @ast.TsExpr, ctx : CalleeCtx) -> Bool {
  match expr {
    Var(n) =>
      // `this` / `super` / `arguments` are bound by the call, not by a
      // declaration; treating them as undeclared would make every
      // `this.field` in the bundle a foreign read.
      if is_dynamically_bound_name(n) {
        false
      } else {
        ctx.roots.contains(n) || !(ctx.resolves)(n)
      }
    // Reading a property or element of a host-shaped value yields
    // another host-shaped value. Reading one off an internal value
    // stays internal — the imprecision that leaves (an internal
    // object holding a foreign function, `const o = { cb: ext.f }`)
    // is the same one the pre-inversion rule accepted.
    PropAccess(recv, _) | IndexAccess(recv, _) =>
      value_is_host_shaped(recv, ctx)
    MethodCall(recv, m, _) =>
      call_result_is_host_shaped(PropAccess(recv, m), ctx)
    Call(n, _) => call_result_is_host_shaped(Var(n), ctx)
    CallExpr(callee, _) => call_result_is_host_shaped(callee, ctx)
    // `new Map()` / `new Error(msg)` build a container of the bundle's
    // own values, so the result is internal even though the
    // constructor is a host global.
    New(n, _) =>
      if is_pure_builtin_constructor(n) {
        false
      } else {
        call_result_is_host_shaped(Var(n), ctx)
      }
    NewExpr(@ast.TsExpr::Var(n), _) =>
      if is_pure_builtin_constructor(n) {
        false
      } else {
        call_result_is_host_shaped(Var(n), ctx)
      }
    NewExpr(callee, _) => call_result_is_host_shaped(callee, ctx)
    // Casts, awaits and optional links don't move a value across the
    // boundary in either direction.
    TypeArgs(_, inner)
    | Await(inner)
    | As(inner, _)
    | Satisfies(inner, _)
    | NonNull(inner)
    | OptionalChain(inner)
    | PureCall(inner)
    | Spread(inner) => value_is_host_shaped(inner, ctx)
    Cond(_, t, e) =>
      value_is_host_shaped(t, ctx) || value_is_host_shaped(e, ctx)
    BinOp(_, l, r) =>
      value_is_host_shaped(l, ctx) || value_is_host_shaped(r, ctx)
    Seq(_, b) => value_is_host_shaped(b, ctx)
    AssignExpr(_, v) | AssignPattern(_, v) | PropAssignExpr(_, _, v) =>
      value_is_host_shaped(v, ctx)
    IndexAssignExpr(_, _, v) => value_is_host_shaped(v, ctx)
    CompoundAssignExpr(target, _, v) =>
      value_is_host_shaped(target, ctx) || value_is_host_shaped(v, ctx)
    TaggedTemplate(tag, _, _, _) => value_is_host_shaped(tag, ctx)
    // Values the bundle constructs on the spot.
    NumberLit(_)
    | IntLit(_)
    | BigIntLit(_)
    | BoolLit(_)
    | StringLit(_)
    | NullLit
    | ArrayHole
    | ObjectLit(_)
    | ArrayLit(_)
    | ComputedProp(_, _)
    | ArrowFunc(_, _, _, _)
    | FuncExpr(_)
    | NativeClassExpr(_, _)
    | TemplateLiteral(_, _)
    | UnaryOp(_, _)
    | JsxElement(_, _, _) => false
    // `import(spec)` resolves to a module the bundle doesn't contain,
    // `import.meta` is filled in by the loader, and a `yield` result
    // is whatever the driver of the generator sent back in.
    DynamicImport(_, _) | ImportMeta | Yield(_) | YieldStar(_) => true
  }
}

///|
/// Does calling `callee` produce a host-shaped value?
fn call_result_is_host_shaped(callee : @ast.TsExpr, ctx : CalleeCtx) -> Bool {
  match classify_callee(callee, ctx) {
    ForeignCallee => true
    PureBuiltinCallee =>
      match callee {
        PropAccess(@ast.TsExpr::Var(ns), m) => returns_host_shaped(ns, m)
        _ => false
      }
    InternalCallee =>
      match callee {
        Var(n) => ctx.host_returning.contains(n)
        _ => false
      }
  }
}

///|
/// Is this call site one whose arguments leave the bundle?
///
/// Split out from `classify_callee` because `new` needs the
/// pure-constructor exemption before the callee expression is even
/// built: `new Map(pairs)` reads `pairs` by index, and classifying
/// `Map` as a callee would make it foreign (it IS a host global).
fn call_site_is_foreign(expr : @ast.TsExpr, ctx : CalleeCtx) -> Bool {
  match expr {
    New(n, _) =>
      !is_pure_builtin_constructor(n) &&
      classify_callee(@ast.TsExpr::Var(n), ctx) is ForeignCallee
    NewExpr(@ast.TsExpr::Var(n), _) =>
      !is_pure_builtin_constructor(n) &&
      classify_callee(@ast.TsExpr::Var(n), ctx) is ForeignCallee
    Call(n, _) => classify_callee(@ast.TsExpr::Var(n), ctx) is ForeignCallee
    CallExpr(callee, _) | NewExpr(callee, _) =>
      classify_callee(callee, ctx) is ForeignCallee
    MethodCall(recv, m, _) =>
      classify_callee(@ast.TsExpr::PropAccess(recv, m), ctx) is ForeignCallee
    _ => false
  }
}

///|
/// The argument list of a call-like expression, or `None` when the
/// expression isn't a call.
fn call_site_args(expr : @ast.TsExpr) -> Array[@ast.TsExpr]? {
  match expr {
    Call(_, args)
    | CallExpr(_, args)
    | New(_, args)
    | NewExpr(_, args)
    | MethodCall(_, _, args) => Some(args)
    _ => None
  }
}

// ---------------------------------------------------------------------------
// Whole-block pre-pass
// ---------------------------------------------------------------------------

///|
priv struct HsScan {
  roots : Map[String, Bool]
  host_returning : Map[String, Bool]
  // Name of the function whose body we're inside, so a `return` can
  // be attributed. Empty when the enclosing function is anonymous —
  // an anonymous function's returns can't be looked up by name at a
  // call site, so there's nothing to record.
  mut current_func : String
  mut changed : Bool
}

///|
fn hs_ctx(scan : HsScan) -> CalleeCtx {
  {
    roots: scan.roots,
    host_returning: scan.host_returning,
    // Name-based pass: no symbol graph exists yet, so "does anything
    // declare this?" can't be answered. Saying yes for everything
    // keeps the pre-pass to the facts it does have; the symbol-graph
    // walk applies the stricter rule later.
    resolves: fn(_) { true },
  }
}

///|
/// Whole-block provenance facts, as
/// `(host-shaped value names, host-returning function names)`, seeded
/// with `externals` (external import bindings plus the ambient
/// globals).
///
/// The rules are mutually dependent — a binding is host-shaped when
/// its initializer is, a function is host-returning when one of its
/// returns is, a callback parameter is host-shaped when the host fills
/// it in — so they run to a fixed point. Both sets only grow and are
/// bounded by the block's identifier count, which makes termination
/// automatic; the round cap is a guard against a pathological input,
/// not part of the algorithm.
///
/// Names, not symbols: the pass runs before the symbol graph exists,
/// so a host-shaped `data` in one function marks `data` everywhere. It
/// errs toward reserving too much, never too little.
fn host_provenance_names(
  block : @ast.TsBlock,
  externals : Map[String, Bool],
) -> (Map[String, Bool], Map[String, Bool]) {
  let roots : Map[String, Bool] = {}
  for n in externals.keys() {
    roots[n] = true
  }
  let host_returning : Map[String, Bool] = {}
  let mut round = 0
  let mut changed = true
  while changed && round < 8 {
    let scan : HsScan = {
      roots,
      host_returning,
      current_func: "",
      changed: false,
    }
    hs_scan_block(scan, block)
    changed = scan.changed
    round = round + 1
  }
  (roots, host_returning)
}

///|
fn hs_mark_name(scan : HsScan, name : String) -> Unit {
  if name != "" && !scan.roots.contains(name) {
    scan.roots[name] = true
    scan.changed = true
  }
}

///|
fn hs_mark_binding(scan : HsScan, b : @ast.TsBinding) -> Unit {
  let names : Array[String] = []
  collect_binding_names_into(b, names)
  for n in names {
    hs_mark_name(scan, n)
  }
}

///|
fn hs_mark_host_returning(scan : HsScan, name : String) -> Unit {
  if name != "" && !scan.host_returning.contains(name) {
    scan.host_returning[name] = true
    scan.changed = true
  }
}

///|
/// Parameters of a callback handed to a foreign call are filled in by
/// the host, so the names the bundle reads off them are the host's.
/// This is what makes `rows.map(r => r.id)` reserve `id` when `rows`
/// came from outside — `id` appears nowhere near an import, and
/// nothing else in the analysis would have seen it.
fn hs_mark_callback_params(scan : HsScan, arg : @ast.TsExpr) -> Unit {
  match arg {
    @ast.TsExpr::ArrowFunc(params, _, _, _) => hs_mark_params(scan, params)
    @ast.TsExpr::FuncExpr(f) => hs_mark_params(scan, f.params)
    @ast.TsExpr::As(inner, _)
    | @ast.TsExpr::Satisfies(inner, _)
    | @ast.TsExpr::TypeArgs(_, inner)
    | @ast.TsExpr::NonNull(inner) => hs_mark_callback_params(scan, inner)
    _ => ()
  }
}

///|
fn hs_mark_params(scan : HsScan, params : Array[@ast.TsParam]) -> Unit {
  for p in params {
    match p.binding {
      Some(b) => hs_mark_binding(scan, b)
      None => hs_mark_name(scan, p.name)
    }
  }
}

///|
fn hs_scan_block(scan : HsScan, block : @ast.TsBlock) -> Unit {
  for s in block.stmts {
    hs_scan_stmt(scan, s)
  }
}

///|
fn hs_scan_stmt(scan : HsScan, stmt : @ast.TsStmt) -> Unit {
  match stmt {
    Var(b, _, init) | Let(b, _, init) | Const(b, _, init) => {
      if value_is_host_shaped(init, hs_ctx(scan)) {
        hs_mark_binding(scan, b)
      }
      match b {
        @ast.TsBinding::Ident(n) => hs_scan_named_init(scan, n, init)
        _ => hs_scan_expr(scan, init)
      }
    }
    Assign(name, rhs) => {
      if value_is_host_shaped(rhs, hs_ctx(scan)) {
        hs_mark_name(scan, name)
      }
      hs_scan_expr(scan, rhs)
    }
    CompoundAssign(_, _, rhs) => hs_scan_expr(scan, rhs)
    IndexAssign(t, idx, v) => {
      hs_scan_expr(scan, t)
      hs_scan_expr(scan, idx)
      hs_scan_expr(scan, v)
    }
    PropAssign(t, _, v) => {
      hs_scan_expr(scan, t)
      hs_scan_expr(scan, v)
    }
    Expr(e) | Throw(e) => hs_scan_expr(scan, e)
    Return(Some(e)) => {
      if value_is_host_shaped(e, hs_ctx(scan)) {
        hs_mark_host_returning(scan, scan.current_func)
      }
      hs_scan_expr(scan, e)
    }
    Return(None) | Empty | Debugger | Break(_) | Continue(_) => ()
    Try(b, binding, cb, fb) => {
      hs_scan_block(scan, b)
      // A caught value can be anything the host threw.
      match binding {
        Some(bb) => hs_mark_binding(scan, bb)
        None => ()
      }
      match cb {
        Some(blk) => hs_scan_block(scan, blk)
        None => ()
      }
      match fb {
        Some(blk) => hs_scan_block(scan, blk)
        None => ()
      }
    }
    If(c, t, e) => {
      hs_scan_expr(scan, c)
      hs_scan_block(scan, t)
      match e {
        Some(b) => hs_scan_block(scan, b)
        None => ()
      }
    }
    While(c, b) | DoWhile(c, b) | With(c, b) => {
      hs_scan_expr(scan, c)
      hs_scan_block(scan, b)
    }
    For(init, cond, update, body) => {
      match init {
        Some(s) => hs_scan_stmt(scan, s)
        None => ()
      }
      match cond {
        Some(e) => hs_scan_expr(scan, e)
        None => ()
      }
      match update {
        Some(s) => hs_scan_stmt(scan, s)
        None => ()
      }
      hs_scan_block(scan, body)
    }
    // Iterating a host-shaped collection yields host-shaped elements.
    ForOf(_, b, _, iter, body) | ForAwaitOf(_, b, _, iter, body) => {
      if value_is_host_shaped(iter, hs_ctx(scan)) {
        hs_mark_binding(scan, b)
      }
      hs_scan_expr(scan, iter)
      hs_scan_block(scan, body)
    }
    // `for (k in obj)` binds a key string, not an object — nothing to
    // mark, even when `obj` is host-shaped.
    ForIn(_, _, _, iter, body) => {
      hs_scan_expr(scan, iter)
      hs_scan_block(scan, body)
    }
    Switch(e, cases) => {
      hs_scan_expr(scan, e)
      for c in cases {
        match c.test_expr {
          Some(te) => hs_scan_expr(scan, te)
          None => ()
        }
        hs_scan_block(scan, c.body)
      }
    }
    Label(_, inner) => hs_scan_stmt(scan, inner)
    Block(b) => hs_scan_block(scan, b)
    NativeClassStmt(decl, ctor) => {
      match decl.base_expr {
        Some(b) => hs_scan_expr(scan, b)
        None => ()
      }
      // A method's `return` can't be reached through a bare name, so
      // it contributes nothing to `host_returning`.
      let prev = scan.current_func
      scan.current_func = ""
      match ctor {
        Some(f) => hs_scan_block(scan, f.body)
        None => ()
      }
      for m in decl.methods {
        match m.body {
          Some(b) => hs_scan_block(scan, b)
          None => ()
        }
      }
      scan.current_func = prev
      for sf in decl.static_field_inits {
        hs_scan_expr(scan, sf.1)
      }
    }
  }
}

///|
/// Walk the initializer of `name`, attributing any `return` inside a
/// function-shaped initializer to `name`.
fn hs_scan_named_init(scan : HsScan, name : String, init : @ast.TsExpr) -> Unit {
  match init {
    @ast.TsExpr::FuncExpr(f) => {
      let prev = scan.current_func
      scan.current_func = name
      hs_scan_block(scan, f.body)
      scan.current_func = prev
    }
    @ast.TsExpr::ArrowFunc(_, _, body, _) => {
      let prev = scan.current_func
      scan.current_func = name
      match body {
        ArrowExpr(e) => {
          // An expression-bodied arrow returns its body.
          if value_is_host_shaped(e, hs_ctx(scan)) {
            hs_mark_host_returning(scan, name)
          }
          hs_scan_expr(scan, e)
        }
        ArrowBlock(b) => hs_scan_block(scan, b)
      }
      scan.current_func = prev
    }
    _ => hs_scan_expr(scan, init)
  }
}

///|
fn hs_scan_expr(scan : HsScan, expr : @ast.TsExpr) -> Unit {
  if call_site_is_foreign(expr, hs_ctx(scan)) {
    match call_site_args(expr) {
      Some(args) =>
        for a in args {
          hs_mark_callback_params(scan, a)
        }
      None => ()
    }
  }
  match expr {
    Call(_, args) | New(_, args) =>
      for a in args {
        hs_scan_expr(scan, a)
      }
    CallExpr(callee, args) | NewExpr(callee, args) => {
      hs_scan_expr(scan, callee)
      for a in args {
        hs_scan_expr(scan, a)
      }
    }
    MethodCall(recv, _, args) => {
      hs_scan_expr(scan, recv)
      for a in args {
        hs_scan_expr(scan, a)
      }
    }
    BinOp(_, l, r) | Seq(l, r) | ComputedProp(l, r) => {
      hs_scan_expr(scan, l)
      hs_scan_expr(scan, r)
    }
    UnaryOp(_, inner)
    | Spread(inner)
    | Await(inner)
    | YieldStar(inner)
    | As(inner, _)
    | Satisfies(inner, _)
    | NonNull(inner)
    | OptionalChain(inner)
    | PureCall(inner)
    | TypeArgs(_, inner) => hs_scan_expr(scan, inner)
    Yield(Some(inner)) => hs_scan_expr(scan, inner)
    Cond(c, t, e) => {
      hs_scan_expr(scan, c)
      hs_scan_expr(scan, t)
      hs_scan_expr(scan, e)
    }
    PropAccess(recv, _) => hs_scan_expr(scan, recv)
    IndexAccess(recv, idx) => {
      hs_scan_expr(scan, recv)
      hs_scan_expr(scan, idx)
    }
    AssignExpr(_, v) | AssignPattern(_, v) => hs_scan_expr(scan, v)
    CompoundAssignExpr(t, _, v) | PropAssignExpr(t, _, v) => {
      hs_scan_expr(scan, t)
      hs_scan_expr(scan, v)
    }
    IndexAssignExpr(t, idx, v) => {
      hs_scan_expr(scan, t)
      hs_scan_expr(scan, idx)
      hs_scan_expr(scan, v)
    }
    ArrayLit(items) =>
      for it in items {
        hs_scan_expr(scan, it)
      }
    ObjectLit(entries) =>
      for ent in entries {
        hs_scan_expr(scan, ent.1)
      }
    // An anonymous function's returns belong to nobody nameable.
    ArrowFunc(_, _, body, _) => {
      let prev = scan.current_func
      scan.current_func = ""
      match body {
        ArrowExpr(e) => hs_scan_expr(scan, e)
        ArrowBlock(b) => hs_scan_block(scan, b)
      }
      scan.current_func = prev
    }
    FuncExpr(f) => {
      let prev = scan.current_func
      scan.current_func = ""
      hs_scan_block(scan, f.body)
      scan.current_func = prev
    }
    NativeClassExpr(decl, ctor) => {
      let prev = scan.current_func
      scan.current_func = ""
      match decl.base_expr {
        Some(b) => hs_scan_expr(scan, b)
        None => ()
      }
      match ctor {
        Some(f) => hs_scan_block(scan, f.body)
        None => ()
      }
      for m in decl.methods {
        match m.body {
          Some(b) => hs_scan_block(scan, b)
          None => ()
        }
      }
      scan.current_func = prev
      for sf in decl.static_field_inits {
        hs_scan_expr(scan, sf.1)
      }
    }
    DynamicImport(spec, opts) => {
      hs_scan_expr(scan, spec)
      match opts {
        Some(o) => hs_scan_expr(scan, o)
        None => ()
      }
    }
    TaggedTemplate(tag, _, _, exprs) => {
      hs_scan_expr(scan, tag)
      for e in exprs {
        hs_scan_expr(scan, e)
      }
    }
    TemplateLiteral(_, exprs) =>
      for e in exprs {
        hs_scan_expr(scan, e)
      }
    JsxElement(_, attrs, children) => {
      for a in attrs {
        match a.1 {
          Some(v) => hs_scan_expr(scan, v)
          None => ()
        }
      }
      for c in children {
        hs_scan_expr(scan, c)
      }
    }
    Var(_)
    | NumberLit(_)
    | IntLit(_)
    | BigIntLit(_)
    | BoolLit(_)
    | StringLit(_)
    | NullLit
    | ArrayHole
    | ImportMeta
    | Yield(None) => ()
  }
}
