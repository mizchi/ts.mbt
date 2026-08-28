// Inline a call to a trivial function at its call site.
//
// terser's `inline` compress rule. It was the largest single loss in
// `scripts/compare_terser.mjs` (+27 bytes on a two-line program) and,
// more importantly, the reason three TYPE-AWARE cases lost or tied:
//
//   const enum Level { Low = 1, High = 2 }
//   export function f() { return Level.Low + Level.High; }
//   console.log(f());
//
// The type-driven half already worked — the body folded to `return 3` —
// but terser then wrote `console.log(3)` where we wrote
// `console.log(f())`. Winning the type argument and losing the byte
// count is the worst of both, so this closes it.
//
// The subset here is deliberately narrow, because inlining a call is
// where a minifier most easily changes semantics. Every one of these
// must hold:
//
//   * the callee is a function DECLARED in this block, whose body is
//     exactly `return <expr>` — no statements, no branches
//   * `<expr>` is pure, so evaluating it at the call site instead of
//     inside the call changes nothing observable
//   * `<expr>` mentions no `this`, `arguments`, `super`, `new.target`,
//     and contains no nested function — a nested function could capture
//     a parameter, and moving it changes what it closes over
//   * `<expr>` does not mention the function's own name, so a recursive
//     function cannot expand forever
//   * the call passes exactly one argument per parameter, and every
//     argument is pure
//   * each parameter is read AT MOST ONCE in `<expr>`, so substituting
//     an argument cannot duplicate work or reorder effects
//
// The function itself is left alone. It may be exported, and something
// else may call it; deleting it is `treeshake`'s decision, made after
// this pass has removed the call that kept it alive.

///|
/// A function this pass is allowed to expand at a call site.
priv struct TrivialFn {
  params : Array[String]
  body : @ast.TsExpr
}

///|
/// Top-level functions that qualify. The parser desugars a top-level
/// `function f(…) {…}` into `Let(Ident("f"), _, FuncExpr(…))`, so that
/// is the shape to look for, alongside an arrow with an expression body.
fn collect_trivial_fns(block : @ast.TsBlock) -> Map[String, TrivialFn] {
  let out : Map[String, TrivialFn] = {}
  // A name declared more than once, or reassigned anywhere, is not safe
  // to resolve syntactically — the call site might reach a different
  // value than the declaration this pass read.
  let declared_count : Map[String, Int] = {}
  for s in block.stmts {
    match s {
      Let(@ast.TsBinding::Ident(n), _, _)
      | Const(@ast.TsBinding::Ident(n), _, _)
      | Var(@ast.TsBinding::Ident(n), _, _) =>
        declared_count[n] = declared_count.get(n).unwrap_or(0) + 1
      _ => ()
    }
  }
  let reassigned : Map[String, Bool] = {}
  for s in block.stmts {
    collect_reassigned_stmt(s, reassigned)
  }
  for s in block.stmts {
    let (name, candidate) = match s {
      Let(@ast.TsBinding::Ident(n), _, rhs)
      | Const(@ast.TsBinding::Ident(n), _, rhs)
      | Var(@ast.TsBinding::Ident(n), _, rhs) => (n, trivial_fn_of(n, rhs))
      _ => ("", None)
    }
    if name == "" {
      continue
    }
    if declared_count.get(name).unwrap_or(0) != 1 || reassigned.contains(name) {
      continue
    }
    match candidate {
      Some(fn_) => out[name] = fn_
      None => ()
    }
  }
  out
}

///|
/// Is `rhs` a function whose call this pass may expand? `own_name` is
/// the binding it is being declared as, so recursion can be rejected.
fn trivial_fn_of(own_name : String, rhs : @ast.TsExpr) -> TrivialFn? {
  let (params, body) = match rhs {
    @ast.TsExpr::FuncExpr(f) => {
      if f.is_generator || f.is_async {
        return None
      }
      if f.body.stmts.length() != 1 {
        return None
      }
      match f.body.stmts[0] {
        @ast.TsStmt::Return(Some(e)) => (f.params, e)
        _ => return None
      }
    }
    // `const f = (n) => n + 1`. An expression body is already the
    // single-return shape.
    @ast.TsExpr::ArrowFunc(params, _, @ast.TsArrowBody::ArrowExpr(e), is_async) => {
      if is_async {
        return None
      }
      (params, e)
    }
    _ => return None
  }
  let names : Array[String] = []
  for p in params {
    // A default, a rest, or a destructuring pattern all make the
    // parameter-to-argument correspondence something other than
    // positional, which is the only mapping this pass performs.
    if p.is_rest || p.default is Some(_) {
      return None
    }
    match p.binding {
      Some(@ast.TsBinding::Ident(_)) | None => ()
      Some(_) => return None
    }
    if p.name == "" {
      return None
    }
    names.push(p.name)
  }
  // The recursion check uses the function's own name — but only when a
  // parameter does not shadow it. The mangler reuses short names freely,
  // and `function a(a) { return a + 1 }` is what it produces for
  // `function helper(n) { return n + 1 }`: the `a` in the body is the
  // PARAMETER, and reading it as a self-reference declined every
  // function the mangler had touched. Which was all of them, so the
  // whole rule silently did nothing in the real pipeline while passing
  // its own unit tests on unmangled input.
  let shadowed_by_param = names.contains(own_name)
  if !expr_is_inlinable_body(
      body,
      if shadowed_by_param {
        ""
      } else {
        own_name
      },
    ) {
    return None
  }
  // Each parameter at most once, so substitution cannot duplicate an
  // argument's evaluation.
  for n in names {
    let (local_, nested) = count_var_uses_expr(body, n, 0, 0, false)
    if local_ + nested > 1 {
      return None
    }
  }
  Some({ params: names, body })
}

///|
/// May this expression be moved to a call site?
fn expr_is_inlinable_body(expr : @ast.TsExpr, own_name : String) -> Bool {
  if !is_pure_value(expr) {
    return false
  }
  // A nested function could close over a parameter; moving it changes
  // what it captures. `is_pure_value` accepts one, so exclude it here.
  if expr_contains_function(expr) {
    return false
  }
  // `this` / `arguments` / `super` mean something different at the call
  // site than inside the callee.
  if expr_references_name(expr, "this") ||
    expr_references_name(expr, "arguments") ||
    expr_references_name(expr, "super") {
    return false
  }
  // Recursion would expand without end.
  if own_name != "" && expr_references_name(expr, own_name) {
    return false
  }
  true
}

///|
fn expr_contains_function(expr : @ast.TsExpr) -> Bool {
  match expr {
    FuncExpr(_) | ArrowFunc(_, _, _, _) | NativeClassExpr(_, _) => true
    BinOp(_, l, r) | Seq(l, r) =>
      expr_contains_function(l) || expr_contains_function(r)
    Cond(c, t, e) =>
      expr_contains_function(c) ||
      expr_contains_function(t) ||
      expr_contains_function(e)
    UnaryOp(_, inner)
    | As(inner, _)
    | Satisfies(inner, _)
    | NonNull(inner)
    | OptionalChain(inner)
    | PureCall(inner)
    | Await(inner)
    | TypeArgs(_, inner)
    | Spread(inner) => expr_contains_function(inner)
    PropAccess(recv, _) => expr_contains_function(recv)
    IndexAccess(recv, idx) =>
      expr_contains_function(recv) || expr_contains_function(idx)
    Call(_, args) | New(_, args) => {
      for a in args {
        if expr_contains_function(a) {
          return true
        }
      }
      false
    }
    CallExpr(callee, args) | NewExpr(callee, args) => {
      if expr_contains_function(callee) {
        return true
      }
      for a in args {
        if expr_contains_function(a) {
          return true
        }
      }
      false
    }
    MethodCall(recv, _, args) => {
      if expr_contains_function(recv) {
        return true
      }
      for a in args {
        if expr_contains_function(a) {
          return true
        }
      }
      false
    }
    ArrayLit(items) => {
      for i in items {
        if expr_contains_function(i) {
          return true
        }
      }
      false
    }
    ObjectLit(entries) => {
      for e in entries {
        if expr_contains_function(e.1) {
          return true
        }
      }
      false
    }
    TemplateLiteral(_, exprs) => {
      for e in exprs {
        if expr_contains_function(e) {
          return true
        }
      }
      false
    }
    _ => false
  }
}

// ---------------------------------------------------------------
// Scope narrowing
// ---------------------------------------------------------------
//
// `try_inline_trivial_call` resolves a callee by NAME, and
// `inline_into_expr` carries one table into every nested scope. That is
// only sound while the name means the same thing down there.
//
// It usually does not. This pass runs AFTER the mangler, which hands out
// the same short names in every scope, so
//
//   function a(a) { return a.kind === 9 }        // top level
//   ...
//   function bU(x) { let a = pick(x); return a(1) }   // `a` is local
//
// is the ordinary shape of mangled code, not an edge case. Resolving
// `a(1)` against the top-level table gives the inner call site the outer
// function's body. `typescript.js` minified that way threw
// `Cannot read properties of undefined (reading 'exports')` inside its
// own binder — and a scope-blind table breaks quietly, in proportion to
// how well the mangler did its job.
//
// So every scope entry drops the names it re-binds. The narrowing is
// local (only what THIS scope binds) and copies nothing when nothing is
// shadowed, which is the common case.
//
// These helpers are generic in the table's value type because they are
// not specific to this pass, and the second pass that needed them had
// gone without: `as_const_inline.mbt` resolved a name against a
// top-level table with no narrowing at all, so
//
//   const S = ["ok", "warn"];
//   function f() { const S = ["x", "y"]; return S[0]; }
//   function h(S) { return S[0]; }
//
// compiled `f()` and `h(["param"])` to `"ok"` — a wrong VALUE, not a
// crash, under plain `--bundle --fold`, and for a parameter as much as
// for an inner declaration. One implementation of scope narrowing, used
// by every table that resolves names, is the point.

///|
fn[T] narrow_trivial_fns(
  tbl : Map[String, T],
  shadowed : Array[String],
) -> Map[String, T] {
  let drop : Array[String] = []
  for n in shadowed {
    if tbl.contains(n) {
      drop.push(n)
    }
  }
  if drop.is_empty() {
    return tbl
  }
  let out : Map[String, T] = Map::new()
  for k in tbl.keys() {
    if drop.contains(k) {
      continue
    }
    match tbl.get(k) {
      Some(v) => out[k] = v
      None => ()
    }
  }
  out
}

///|
/// Narrow by what a nested block's own statement list declares. Nested
/// blocks inside it narrow themselves when the walk reaches them.
fn[T] narrow_for_block(
  tbl : Map[String, T],
  block : @ast.TsBlock,
) -> Map[String, T] {
  if tbl.is_empty() {
    return tbl
  }
  let names : Array[String] = []
  collect_block_bound_names(block, names)
  narrow_trivial_fns(tbl, names)
}

///|
fn collect_block_bound_names(block : @ast.TsBlock, out : Array[String]) -> Unit {
  for s in block.stmts {
    collect_stmt_bound_names(s, out)
  }
}

///|
fn collect_stmt_bound_names(s : @ast.TsStmt, out : Array[String]) -> Unit {
  match s {
    Let(b, _, _) | Const(b, _, _) | Var(b, _, _) =>
      collect_binding_bound_names(b, out)
    // `let a = 1, b = 2;` parses as a wrapper Block whose bindings
    // belong to THIS scope, not to a nested one.
    Block(inner) =>
      if is_multi_decl_block(inner) {
        collect_block_bound_names(inner, out)
      }
    NativeClassStmt(decl, _) => out.push(decl.name)
    Label(_, inner) => collect_stmt_bound_names(inner, out)
    _ => ()
  }
}

///|
fn collect_binding_bound_names(b : @ast.TsBinding, out : Array[String]) -> Unit {
  match b {
    Ident(n) => out.push(n)
    Target(_) => ()
    Array(ab) => {
      for elem in ab.items {
        match elem {
          Some(be) => collect_binding_bound_names(be.binding, out)
          None => ()
        }
      }
      match ab.rest {
        Some(r) => collect_binding_bound_names(r, out)
        None => ()
      }
    }
    Object(ob) => {
      for prop in ob.props {
        collect_binding_bound_names(prop.binding, out)
      }
      match ob.rest {
        Some(r) => out.push(r)
        None => ()
      }
    }
  }
}

///|
/// Narrow by a function's parameters and its own name. A named function
/// expression binds its name inside itself, so a call to that name in
/// there is the inner function, not the top-level one.
fn narrow_for_func(
  tbl : Map[String, TrivialFn],
  f : @ast.TsFunc,
) -> Map[String, TrivialFn] {
  if tbl.is_empty() {
    return tbl
  }
  let names : Array[String] = []
  if f.name != "" {
    names.push(f.name)
  }
  collect_param_bound_names(f.params, names)
  narrow_trivial_fns(tbl, names)
}

///|
fn[T] narrow_for_params(
  tbl : Map[String, T],
  params : Array[@ast.TsParam],
) -> Map[String, T] {
  if tbl.is_empty() {
    return tbl
  }
  let names : Array[String] = []
  collect_param_bound_names(params, names)
  narrow_trivial_fns(tbl, names)
}

///|
/// A class method's parameter list is a `(name, type)` pair list rather
/// than a `TsParam` list.
fn[T] narrow_for_named_params(
  tbl : Map[String, T],
  params : Array[(String, @ast.TsType)],
) -> Map[String, T] {
  if tbl.is_empty() {
    return tbl
  }
  let names : Array[String] = []
  for p in params {
    if p.0 != "" {
      names.push(p.0)
    }
  }
  narrow_trivial_fns(tbl, names)
}

///|
fn collect_param_bound_names(
  params : Array[@ast.TsParam],
  out : Array[String],
) -> Unit {
  for p in params {
    if p.name != "" {
      out.push(p.name)
    }
    match p.binding {
      Some(b) => collect_binding_bound_names(b, out)
      None => ()
    }
  }
}

///|
/// Narrow by a single binding: a loop variable, a catch parameter.
fn[T] narrow_for_binding(
  tbl : Map[String, T],
  b : @ast.TsBinding,
) -> Map[String, T] {
  if tbl.is_empty() {
    return tbl
  }
  let names : Array[String] = []
  collect_binding_bound_names(b, names)
  narrow_trivial_fns(tbl, names)
}

// ---------------------------------------------------------------
// The rewrite
// ---------------------------------------------------------------
//
// No traversal lives here on purpose. `inline_into_expr` in
// `inline.mbt` already visits every expression in the block, so this
// file only answers "may this call be replaced, and by what". A second
// full-tree walker is exactly the shape of thing that has gone wrong
// repeatedly in this pipeline: two walkers, and only one of them knows
// about some construct.

///|
/// `Some(body)` when `expr` is a call this pass may replace.
fn try_inline_trivial_call(
  expr : @ast.TsExpr,
  table : Map[String, TrivialFn],
) -> @ast.TsExpr? {
  if table.is_empty() {
    return None
  }
  let (name, args) = match expr {
    @ast.TsExpr::Call(n, a) => (n, a)
    @ast.TsExpr::CallExpr(@ast.TsExpr::Var(n), a) => (n, a)
    _ => return None
  }
  let fn_ = match table.get(name) {
    Some(f) => f
    None => return None
  }
  // Positional, exact. A missing argument would bind `undefined`, which
  // is a different substitution than the one performed here.
  if args.length() != fn_.params.length() {
    return None
  }
  for a in args {
    // An impure argument has to be evaluated exactly once, in order. A
    // parameter the body never reads would drop it, and substitution can
    // move it past other work.
    if !is_pure_value(a) {
      return None
    }
  }
  let mut body = fn_.body
  for i, param in fn_.params {
    body = substitute_expr(body, param, args[i])
  }
  Some(body)
}
