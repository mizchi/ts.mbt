// Escape analysis for the bundle's own export surface.
//
// `mangle_safety.mbt` proves which property names leak through the
// *sinks* a bundle calls (fetch, JSON.stringify, an external
// package's function). This pass covers the other door: the names
// that leak because the bundle hands the value to its consumer.
//
// Why a separate pass, and why syntactic: the declared type surface
// (`type_props.mbt`) only sees names that appear in an interface /
// type alias / class. That misses two very common shapes:
//
//   export const make = (): Result => ({ v1: 1 });   // Result lives
//                                                    // in another module
//   export function run() { return { first, rest }; } // inferred shape
//
// Both put property names in the package ABI, and neither shows up
// in the entry module's own type declarations. Deleting or renaming
// those keys silently changes what a consumer reads — the exact
// failure the `fixtures/mangle-safety` corpus reproduces.
//
// So this pass walks the *values*, starting from the entry's
// exported bindings, and reserves every property name a consumer
// could reach:
//
//   - keys of an object literal that reaches an export (recursively,
//     since a consumer can read `x.a.b`);
//   - property names read on a parameter of an exported function —
//     the caller has to construct that shape, so the names are ABI;
//   - members of an exported class;
//   - the return values of exported functions, and of function
//     arguments handed to a call whose result escapes
//     (`[…].map(x => ({ www: … }))`).
//
// The analysis is deliberately an over-approximation: when a value's
// origin can't be resolved (a call into an unknown callee, a
// property read off an opaque object) it widens to "everything this
// object holds escapes" rather than assuming the value is private.
// Reserving a name that could have been renamed costs a few bytes;
// renaming one that escapes breaks the consumer.

///|
/// Property names reachable from the bundle's export surface.
///
/// `exported_locals` are the names of the merged block's top-level
/// bindings that the entry module exports (post-link, pre-mangle).
pub fn exported_surface_props(
  block : @ast.TsBlock,
  exported_locals : Map[String, Bool],
) -> Array[String] {
  let w = SurfaceWalk::{
    decls: {},
    classes: {},
    funcs: {},
    prop_assigns: {},
    reserved: {},
    visited: {},
    queue: [],
  }
  index_top_level_decls(w, block)
  index_prop_assigns(w, block)
  for name in exported_locals.keys() {
    surface_enqueue(w, name)
  }
  while w.queue.length() > 0 {
    let name = w.queue.pop().unwrap()
    match w.decls.get(name) {
      Some(init) => surface_escape_expr(w, init, 0)
      None => ()
    }
    match w.classes.get(name) {
      Some(decl) => surface_escape_class(w, decl, 0)
      None => ()
    }
    // Anything written onto this object is part of what the consumer
    // reads off it.
    match w.prop_assigns.get(name) {
      Some(assigns) =>
        for entry in assigns {
          if !is_internal_marker_prop(entry.0) {
            w.reserved[entry.0] = true
          }
          surface_escape_expr(w, entry.1, 1)
        }
      None => ()
    }
  }
  let out : Array[String] = []
  for k in w.reserved.keys() {
    out.push(k)
  }
  out
}

///|
priv struct SurfaceWalk {
  // Top-level binding name -> its initializer.
  decls : Map[String, @ast.TsExpr]
  // Top-level `class X { … }` declarations.
  classes : Map[String, @ast.TsClassDecl]
  // Top-level `function f(…) { … }` declarations, for resolving a
  // call whose result escapes back to the callee's returns.
  funcs : Map[String, @ast.TsFunc]
  // `NAME.prop = value` / `Object.defineProperty(NAME, "prop", …)`
  // sites, keyed by NAME. A namespace's members arrive this way (the
  // lowering assigns them onto the namespace object inside an IIFE), as
  // does any `Foo.prototype.m = …` style declaration.
  prop_assigns : Map[String, Array[(String, @ast.TsExpr)]]
  // Property names that must survive mangling.
  reserved : Map[String, Bool]
  // Names already processed, so a cyclic reference terminates.
  visited : Map[String, Bool]
  queue : Array[String]
}

///|
/// Bound on expression recursion. Deeply nested literals are fine;
/// this only guards against a pathological AST.
const SURFACE_MAX_DEPTH : Int = 96

///|
fn surface_enqueue(w : SurfaceWalk, name : String) -> Unit {
  if w.visited.contains(name) {
    return
  }
  w.visited[name] = true
  w.queue.push(name)
}

///|
fn index_top_level_decls(w : SurfaceWalk, block : @ast.TsBlock) -> Unit {
  for s in block.stmts {
    match s {
      Var(@ast.TsBinding::Ident(n), _, e)
      | Let(@ast.TsBinding::Ident(n), _, e)
      | Const(@ast.TsBinding::Ident(n), _, e) => {
        w.decls[n] = e
        match e {
          @ast.TsExpr::FuncExpr(f) => w.funcs[n] = f
          _ => ()
        }
      }
      NativeClassStmt(decl, _) => w.classes[decl.name] = decl
      // `var a = 1, b = 2;` and the class-lift pass both nest
      // declarations one block deep.
      Block(inner) => index_top_level_decls(w, inner)
      _ => ()
    }
  }
}

///|
/// Index `NAME.prop = value` and
/// `Object.defineProperty(NAME, "prop", { get: … })` sites anywhere in
/// the block, nested function bodies included — a namespace's members
/// are assigned inside an IIFE, so a top-level-only scan misses them.
fn index_prop_assigns(w : SurfaceWalk, block : @ast.TsBlock) -> Unit {
  fn record(name : String, prop : String, value : @ast.TsExpr) -> Unit {
    match w.prop_assigns.get(name) {
      Some(arr) => arr.push((prop, value))
      None => w.prop_assigns[name] = [(prop, value)]
    }
  }

  for stmt in block.stmts {
    match stmt {
      PropAssign(@ast.TsExpr::Var(n), prop, value) => record(n, prop, value)
      _ => ()
    }
    // Nested statement blocks (the namespace lowering wraps its two
    // statements in one) and nested function bodies.
    match stmt {
      Block(inner) => index_prop_assigns(w, inner)
      If(_, t, e) => {
        index_prop_assigns(w, t)
        match e {
          Some(b) => index_prop_assigns(w, b)
          None => ()
        }
      }
      While(_, b)
      | DoWhile(_, b)
      | With(_, b)
      | For(_, _, _, b)
      | ForOf(_, _, _, _, b)
      | ForAwaitOf(_, _, _, _, b)
      | ForIn(_, _, _, _, b) => index_prop_assigns(w, b)
      Try(b, _, c, f) => {
        index_prop_assigns(w, b)
        match c {
          Some(cb) => index_prop_assigns(w, cb)
          None => ()
        }
        match f {
          Some(fb) => index_prop_assigns(w, fb)
          None => ()
        }
      }
      Switch(_, cases) =>
        for case_ in cases {
          index_prop_assigns(w, case_.body)
        }
      _ => ()
    }
  }
  // Function bodies and `Object.defineProperty` calls, wherever they sit
  // in an expression.
  surface_visit_exprs_block(block, e => {
    match e {
      @ast.TsExpr::FuncExpr(f) => index_prop_assigns(w, f.body)
      @ast.TsExpr::ArrowFunc(_, _, ArrowBlock(b), _) => index_prop_assigns(w, b)
      @ast.TsExpr::PropAssignExpr(@ast.TsExpr::Var(n), prop, value) =>
        record(n, prop, value)
      @ast.TsExpr::MethodCall(
        @ast.TsExpr::Var("Object"),
        "defineProperty",
        args
      ) =>
        if args.length() >= 3 {
          match (args[0], args[1]) {
            (@ast.TsExpr::Var(n), @ast.TsExpr::StringLit(prop)) =>
              record(n, prop, args[2])
            _ => ()
          }
        }
      _ => ()
    }
  })
}

///|
/// Every property name declared on a class the consumer can hold.
/// Private (`#x`) and mtsc-synthesised brand fields stay manglable —
/// no consumer can name them.
fn surface_escape_class(
  w : SurfaceWalk,
  decl : @ast.TsClassDecl,
  depth : Int,
) -> Unit {
  let private_ : Map[String, Bool] = {}
  for n in decl.private_members {
    private_[n] = true
  }
  let visible = (name : String) => {
    !is_internal_marker_prop(name) && !private_.contains(name)
  }
  for p in decl.properties {
    if visible(p.name) {
      w.reserved[p.name] = true
    }
  }
  for init in decl.static_field_inits {
    if visible(init.0) {
      w.reserved[init.0] = true
      surface_escape_expr(w, init.1, depth + 1)
    }
  }
  for init in decl.instance_field_inits {
    if visible(init.0) {
      surface_escape_expr(w, init.1, depth + 1)
    }
  }
  for m in decl.methods {
    if !visible(m.name) {
      continue
    }
    w.reserved[m.name] = true
    // A method's return value is as public as the method, and its
    // parameters are shapes the caller has to build.
    match m.body {
      Some(body) => {
        for p in m.params {
          if p.0 != "" {
            surface_reserve_props_on_name_block(w, body, p.0, depth + 1)
          }
        }
        let returns : Array[@ast.TsExpr] = []
        collect_own_returns_block(body, returns)
        for r in returns {
          surface_escape_expr(w, r, depth + 1)
        }
      }
      None => ()
    }
  }
  match decl.constructor_body {
    Some(body) =>
      match decl.constructor_params {
        Some(params) =>
          for p in params {
            if p.0 != "" {
              surface_reserve_props_on_name_block(w, body, p.0, depth + 1)
            }
          }
        None => ()
      }
    None => ()
  }
  for base in decl.base_names {
    surface_enqueue(w, base)
  }
}

///|
/// Walk an expression whose value reaches the consumer.
fn surface_escape_expr(
  w : SurfaceWalk,
  expr : @ast.TsExpr,
  depth : Int,
) -> Unit {
  if depth > SURFACE_MAX_DEPTH {
    return
  }
  match expr {
    ObjectLit(entries) =>
      for ent in entries {
        if !is_internal_marker_prop(ent.0) {
          w.reserved[ent.0] = true
        }
        surface_escape_expr(w, ent.1, depth + 1)
      }
    ArrayLit(items) =>
      for it in items {
        surface_escape_expr(w, it, depth + 1)
      }
    Spread(inner) => surface_escape_expr(w, inner, depth + 1)
    // A reference to a top-level binding: its value escapes too.
    Var(n) => surface_enqueue(w, n)
    FuncExpr(f) => surface_escape_func_body(w, f.params, f.body, depth + 1)
    ArrowFunc(params, _, body, _) =>
      match body {
        // `(o) => o.x` is a body with one return. Model it as such so
        // the parameter scan sees `o.x` — an expression-bodied arrow
        // publishes its parameter shape exactly like a block-bodied
        // one does.
        ArrowExpr(e) =>
          surface_escape_func_body(
            w,
            params,
            { stmts: [@ast.TsStmt::Return(Some(e))], stmt_positions: [] },
            depth + 1,
          )
        ArrowBlock(b) => surface_escape_func_body(w, params, b, depth + 1)
      }
    NativeClassExpr(decl, _) => surface_escape_class(w, decl, depth + 1)
    // Calls: the result escapes. Resolve what produced it —
    //   - a named local function: its returns escape;
    //   - a callback argument: its returns escape, which is how
    //     `[…].map(x => ({ www: … }))` keeps `www`;
    //   - a method receiver: the elements it carries can pass
    //     through (`.filter(…)`), so it escapes as well.
    Call(name, args) => {
      match w.funcs.get(name) {
        Some(f) =>
          if !w.visited.contains("fn:" + name) {
            w.visited["fn:" + name] = true
            surface_escape_func_body(w, f.params, f.body, depth + 1)
          }
        None => surface_enqueue(w, name)
      }
      surface_escape_callback_args(w, args, depth)
    }
    CallExpr(callee, args) => {
      surface_escape_expr(w, callee, depth + 1)
      surface_escape_callback_args(w, args, depth)
    }
    MethodCall(recv, _, args) => {
      surface_escape_expr(w, recv, depth + 1)
      surface_escape_callback_args(w, args, depth)
    }
    New(name, args) | NewExpr(Var(name), args) => {
      match w.classes.get(name) {
        Some(decl) => surface_escape_class(w, decl, depth + 1)
        None => surface_enqueue(w, name)
      }
      surface_escape_callback_args(w, args, depth)
    }
    NewExpr(callee, args) => {
      surface_escape_expr(w, callee, depth + 1)
      surface_escape_callback_args(w, args, depth)
    }
    // `obj.k` hands out the value AT `k`, not `k` itself: the path is
    // internal, only the value is ABI. Resolve the value precisely
    // when `obj` is a known object literal; otherwise widen to the
    // whole object, since we can't tell which part left.
    PropAccess(obj, key) =>
      match surface_lookup_member(w, obj, key) {
        Some(value) => surface_escape_expr(w, value, depth + 1)
        None => surface_escape_expr(w, obj, depth + 1)
      }
    IndexAccess(obj, @ast.TsExpr::StringLit(key)) =>
      match surface_lookup_member(w, obj, key) {
        Some(value) => surface_escape_expr(w, value, depth + 1)
        None => surface_escape_expr(w, obj, depth + 1)
      }
    IndexAccess(obj, _) => surface_escape_expr(w, obj, depth + 1)
    Cond(_, t, e) => {
      surface_escape_expr(w, t, depth + 1)
      surface_escape_expr(w, e, depth + 1)
    }
    // `a ?? b`, `a || b`, `a && b` can each yield either side. Other
    // binary operators produce primitives, but recursing costs
    // nothing beyond a few reserved names.
    BinOp(_, l, r) => {
      surface_escape_expr(w, l, depth + 1)
      surface_escape_expr(w, r, depth + 1)
    }
    Seq(_, r) => surface_escape_expr(w, r, depth + 1)
    Await(inner)
    | Yield(Some(inner))
    | YieldStar(inner)
    | NonNull(inner)
    | OptionalChain(inner)
    | PureCall(inner)
    | As(inner, _)
    | Satisfies(inner, _)
    | TypeArgs(_, inner) => surface_escape_expr(w, inner, depth + 1)
    AssignExpr(_, inner) => surface_escape_expr(w, inner, depth + 1)
    ComputedProp(_, value) => surface_escape_expr(w, value, depth + 1)
    _ => ()
  }
}

///|
/// Function-typed arguments produce values that flow out of the call
/// (`map`, `then`, `reduce`, a user-defined higher-order function),
/// so their bodies escape along with the call's result.
fn surface_escape_callback_args(
  w : SurfaceWalk,
  args : Array[@ast.TsExpr],
  depth : Int,
) -> Unit {
  for a in args {
    match a {
      @ast.TsExpr::FuncExpr(_) | @ast.TsExpr::ArrowFunc(_, _, _, _) =>
        surface_escape_expr(w, a, depth + 1)
      _ => ()
    }
  }
}

///|
/// `obj.key` where `obj` resolves to an object literal: hand back the
/// expression stored at `key`. Returns `None` when the receiver isn't
/// a literal we can see through, which makes the caller widen.
fn surface_lookup_member(
  w : SurfaceWalk,
  obj : @ast.TsExpr,
  key : String,
) -> @ast.TsExpr? {
  let entries = match obj {
    @ast.TsExpr::ObjectLit(entries) => entries
    @ast.TsExpr::Var(n) =>
      match w.decls.get(n) {
        Some(@ast.TsExpr::ObjectLit(entries)) => entries
        _ => return None
      }
    _ => return None
  }
  for ent in entries {
    if ent.0 == key {
      return Some(ent.1)
    }
  }
  None
}

///|
/// The body of a function whose value (or whose return value) is
/// public: its parameters' observed shape and its returns both
/// escape.
fn surface_escape_func_body(
  w : SurfaceWalk,
  params : Array[@ast.TsParam],
  body : @ast.TsBlock,
  depth : Int,
) -> Unit {
  if depth > SURFACE_MAX_DEPTH {
    return
  }
  surface_escape_params(w, params, body, depth)
  let returns : Array[@ast.TsExpr] = []
  collect_own_returns_block(body, returns)
  for r in returns {
    surface_escape_expr(w, r, depth + 1)
  }
}

///|
/// Reserve every property name the function reads off its own
/// parameters — the caller builds those objects, so it names those
/// keys. Also follows a parameter handed straight to another local
/// function, whose parameters then carry the same exposure.
fn surface_escape_params(
  w : SurfaceWalk,
  params : Array[@ast.TsParam],
  body : @ast.TsBlock,
  depth : Int,
) -> Unit {
  for p in params {
    // Destructured parameters name their keys inline:
    // `function f({ prop1, prop2 })`.
    match p.binding {
      Some(b) => surface_reserve_binding_keys(w, b)
      None => ()
    }
    if p.name != "" {
      surface_reserve_props_on_name_block(w, body, p.name, depth)
    }
  }
}

///|
fn surface_reserve_binding_keys(w : SurfaceWalk, b : @ast.TsBinding) -> Unit {
  match b {
    Ident(_) => ()
    // `({ a } = expr)` assignment target: the keys live on the
    // expression side, which the expression walk already covers.
    Target(_) => ()
    Object(ob) => {
      for prop in ob.props {
        if !is_internal_marker_prop(prop.key) {
          w.reserved[prop.key] = true
        }
        surface_reserve_binding_keys(w, prop.binding)
      }
      match ob.rest {
        Some(_) => ()
        None => ()
      }
    }
    Array(ab) => {
      for item in ab.items {
        match item {
          Some(be) => surface_reserve_binding_keys(w, be.binding)
          None => ()
        }
      }
      match ab.rest {
        Some(r) => surface_reserve_binding_keys(w, r)
        None => ()
      }
    }
  }
}

///|
/// Every `name.p` / `name["p"]` / `{ p } = name` read inside `block`.
/// Shadowing is ignored on purpose: a false positive reserves one
/// extra name, a false negative breaks the consumer.
fn surface_reserve_props_on_name_block(
  w : SurfaceWalk,
  block : @ast.TsBlock,
  name : String,
  depth : Int,
) -> Unit {
  surface_visit_exprs_block(block, e => {
    surface_reserve_props_on_name_expr(w, e, name, depth)
  })
  // `const { a, b } = param` names the keys directly.
  let destructured : Array[@ast.TsBinding] = []
  collect_destructures_of_name(block, name, destructured)
  for b in destructured {
    surface_reserve_binding_keys(w, b)
  }
}

///|
fn surface_reserve_props_on_name_expr(
  w : SurfaceWalk,
  expr : @ast.TsExpr,
  name : String,
  depth : Int,
) -> Unit {
  if depth > SURFACE_MAX_DEPTH {
    return
  }
  match expr {
    PropAccess(@ast.TsExpr::Var(n), p) =>
      if n == name && !is_internal_marker_prop(p) {
        w.reserved[p] = true
      }
    IndexAccess(@ast.TsExpr::Var(n), @ast.TsExpr::StringLit(p)) =>
      if n == name && !is_internal_marker_prop(p) {
        w.reserved[p] = true
      }
    MethodCall(@ast.TsExpr::Var(n), m, _) =>
      if n == name && !is_internal_marker_prop(m) {
        w.reserved[m] = true
      }
    // The parameter is handed to another local function: whatever
    // that one reads off its own parameters is reachable from the
    // caller's shape too.
    Call(callee, args) =>
      for a in args {
        if a is @ast.TsExpr::Var(n) && n == name {
          match w.funcs.get(callee) {
            Some(f) =>
              if !w.visited.contains("fn:" + callee) {
                w.visited["fn:" + callee] = true
                surface_escape_func_body(w, f.params, f.body, depth + 1)
              }
            None => ()
          }
        }
      }
    _ => ()
  }
}

///|
/// Visit every expression in a block, descending through nested
/// statements *and* nested function bodies, so a `param.key` read
/// buried in a callback is still seen.
fn surface_visit_exprs_block(
  block : @ast.TsBlock,
  visit : (@ast.TsExpr) -> Unit,
) -> Unit {
  for s in block.stmts {
    surface_visit_exprs_stmt(s, visit)
  }
}

///|
fn surface_visit_exprs_stmt(
  stmt : @ast.TsStmt,
  visit : (@ast.TsExpr) -> Unit,
) -> Unit {
  match stmt {
    Var(_, _, e) | Let(_, _, e) | Const(_, _, e) =>
      surface_visit_exprs_expr(e, visit)
    Assign(_, e) | CompoundAssign(_, _, e) | Expr(e) | Throw(e) =>
      surface_visit_exprs_expr(e, visit)
    Return(Some(e)) => surface_visit_exprs_expr(e, visit)
    Return(None) | Break(_) | Continue(_) | Debugger | Empty => ()
    IndexAssign(a, b, c) => {
      surface_visit_exprs_expr(a, visit)
      surface_visit_exprs_expr(b, visit)
      surface_visit_exprs_expr(c, visit)
    }
    PropAssign(a, _, b) => {
      surface_visit_exprs_expr(a, visit)
      surface_visit_exprs_expr(b, visit)
    }
    Try(b, _, c, f) => {
      surface_visit_exprs_block(b, visit)
      match c {
        Some(cb) => surface_visit_exprs_block(cb, visit)
        None => ()
      }
      match f {
        Some(fb) => surface_visit_exprs_block(fb, visit)
        None => ()
      }
    }
    If(c, t, e) => {
      surface_visit_exprs_expr(c, visit)
      surface_visit_exprs_block(t, visit)
      match e {
        Some(b) => surface_visit_exprs_block(b, visit)
        None => ()
      }
    }
    While(c, b) | DoWhile(c, b) | With(c, b) => {
      surface_visit_exprs_expr(c, visit)
      surface_visit_exprs_block(b, visit)
    }
    For(init, cond, update, body) => {
      match init {
        Some(s) => surface_visit_exprs_stmt(s, visit)
        None => ()
      }
      match cond {
        Some(e) => surface_visit_exprs_expr(e, visit)
        None => ()
      }
      match update {
        Some(s) => surface_visit_exprs_stmt(s, visit)
        None => ()
      }
      surface_visit_exprs_block(body, visit)
    }
    ForOf(_, _, _, e, b) | ForAwaitOf(_, _, _, e, b) | ForIn(_, _, _, e, b) => {
      surface_visit_exprs_expr(e, visit)
      surface_visit_exprs_block(b, visit)
    }
    Switch(e, cases) => {
      surface_visit_exprs_expr(e, visit)
      for c in cases {
        match c.test_expr {
          Some(t) => surface_visit_exprs_expr(t, visit)
          None => ()
        }
        surface_visit_exprs_block(c.body, visit)
      }
    }
    Label(_, inner) => surface_visit_exprs_stmt(inner, visit)
    Block(b) => surface_visit_exprs_block(b, visit)
    NativeClassStmt(decl, ctor) => {
      surface_visit_exprs_class(decl, visit)
      match ctor {
        Some(f) => surface_visit_exprs_block(f.body, visit)
        None => ()
      }
    }
  }
}

///|
fn surface_visit_exprs_class(
  decl : @ast.TsClassDecl,
  visit : (@ast.TsExpr) -> Unit,
) -> Unit {
  for m in decl.methods {
    match m.body {
      Some(b) => surface_visit_exprs_block(b, visit)
      None => ()
    }
  }
  match decl.constructor_body {
    Some(b) => surface_visit_exprs_block(b, visit)
    None => ()
  }
  for init in decl.static_field_inits {
    surface_visit_exprs_expr(init.1, visit)
  }
  for init in decl.instance_field_inits {
    surface_visit_exprs_expr(init.1, visit)
  }
  for b in decl.static_blocks {
    surface_visit_exprs_block(b, visit)
  }
}

///|
fn surface_visit_exprs_expr(
  expr : @ast.TsExpr,
  visit : (@ast.TsExpr) -> Unit,
) -> Unit {
  visit(expr)
  match expr {
    NumberLit(_)
    | IntLit(_)
    | BigIntLit(_)
    | BoolLit(_)
    | StringLit(_)
    | NullLit
    | ArrayHole
    | Var(_)
    | ImportMeta => ()
    BinOp(_, a, b)
    | Seq(a, b)
    | IndexAccess(a, b)
    | CompoundAssignExpr(a, _, b)
    | ComputedProp(a, b) => {
      surface_visit_exprs_expr(a, visit)
      surface_visit_exprs_expr(b, visit)
    }
    UnaryOp(_, a)
    | TypeArgs(_, a)
    | Spread(a)
    | PropAccess(a, _)
    | AssignExpr(_, a)
    | AssignPattern(_, a)
    | Await(a)
    | YieldStar(a)
    | NonNull(a)
    | OptionalChain(a)
    | PureCall(a)
    | As(a, _)
    | Satisfies(a, _) => surface_visit_exprs_expr(a, visit)
    Yield(inner) =>
      match inner {
        Some(a) => surface_visit_exprs_expr(a, visit)
        None => ()
      }
    Cond(a, b, c) | IndexAssignExpr(a, b, c) => {
      surface_visit_exprs_expr(a, visit)
      surface_visit_exprs_expr(b, visit)
      surface_visit_exprs_expr(c, visit)
    }
    PropAssignExpr(a, _, b) => {
      surface_visit_exprs_expr(a, visit)
      surface_visit_exprs_expr(b, visit)
    }
    Call(_, args) | New(_, args) => surface_visit_exprs_args(args, visit)
    CallExpr(callee, args) | NewExpr(callee, args) => {
      surface_visit_exprs_expr(callee, visit)
      surface_visit_exprs_args(args, visit)
    }
    MethodCall(recv, _, args) => {
      surface_visit_exprs_expr(recv, visit)
      surface_visit_exprs_args(args, visit)
    }
    ArrayLit(items) => surface_visit_exprs_args(items, visit)
    ObjectLit(entries) =>
      for ent in entries {
        surface_visit_exprs_expr(ent.1, visit)
      }
    ArrowFunc(params, _, body, _) => {
      surface_visit_exprs_params(params, visit)
      match body {
        ArrowExpr(e) => surface_visit_exprs_expr(e, visit)
        ArrowBlock(b) => surface_visit_exprs_block(b, visit)
      }
    }
    FuncExpr(f) => {
      surface_visit_exprs_params(f.params, visit)
      surface_visit_exprs_block(f.body, visit)
    }
    NativeClassExpr(decl, ctor) => {
      surface_visit_exprs_class(decl, visit)
      match ctor {
        Some(f) => surface_visit_exprs_block(f.body, visit)
        None => ()
      }
    }
    DynamicImport(a, b) => {
      surface_visit_exprs_expr(a, visit)
      match b {
        Some(e) => surface_visit_exprs_expr(e, visit)
        None => ()
      }
    }
    TaggedTemplate(tag, _, _, exprs) => {
      surface_visit_exprs_expr(tag, visit)
      surface_visit_exprs_args(exprs, visit)
    }
    TemplateLiteral(_, exprs) => surface_visit_exprs_args(exprs, visit)
    JsxElement(_, attrs, children) => {
      for attr in attrs {
        match attr.1 {
          Some(e) => surface_visit_exprs_expr(e, visit)
          None => ()
        }
      }
      surface_visit_exprs_args(children, visit)
    }
  }
}

///|
fn surface_visit_exprs_args(
  args : Array[@ast.TsExpr],
  visit : (@ast.TsExpr) -> Unit,
) -> Unit {
  for a in args {
    surface_visit_exprs_expr(a, visit)
  }
}

///|
fn surface_visit_exprs_params(
  params : Array[@ast.TsParam],
  visit : (@ast.TsExpr) -> Unit,
) -> Unit {
  for p in params {
    match p.default {
      Some(e) => surface_visit_exprs_expr(e, visit)
      None => ()
    }
  }
}

///|
/// `return` expressions belonging to THIS function body — the ones a
/// nested function owns are that function's business, and are reached
/// through the nested function expression instead.
fn collect_own_returns_block(
  block : @ast.TsBlock,
  out : Array[@ast.TsExpr],
) -> Unit {
  for s in block.stmts {
    match s {
      Return(Some(e)) => out.push(e)
      // A generator's `yield` is its output just as much as a return.
      Expr(@ast.TsExpr::Yield(Some(e))) | Expr(@ast.TsExpr::YieldStar(e)) =>
        out.push(e)
      If(_, t, e) => {
        collect_own_returns_block(t, out)
        match e {
          Some(b) => collect_own_returns_block(b, out)
          None => ()
        }
      }
      While(_, b)
      | DoWhile(_, b)
      | With(_, b)
      | Block(b)
      | ForOf(_, _, _, _, b)
      | ForAwaitOf(_, _, _, _, b)
      | ForIn(_, _, _, _, b) => collect_own_returns_block(b, out)
      For(_, _, _, b) => collect_own_returns_block(b, out)
      Label(_, inner) =>
        collect_own_returns_block({ stmts: [inner], stmt_positions: [] }, out)
      Try(b, _, c, f) => {
        collect_own_returns_block(b, out)
        match c {
          Some(cb) => collect_own_returns_block(cb, out)
          None => ()
        }
        match f {
          Some(fb) => collect_own_returns_block(fb, out)
          None => ()
        }
      }
      Switch(_, cases) =>
        for c in cases {
          collect_own_returns_block(c.body, out)
        }
      _ => ()
    }
  }
  // Yields nested inside expressions (`const x = yield v;`) surface
  // the value too. This walk also descends into nested functions, so
  // a nested generator's element shape is attributed to the outer
  // function as well — an over-approximation that only ever reserves
  // an extra name.
  surface_visit_exprs_block(block, e => {
    match e {
      @ast.TsExpr::Yield(Some(inner)) => out.push(inner)
      @ast.TsExpr::YieldStar(inner) => out.push(inner)
      _ => ()
    }
  })
}

///|
/// `const { a } = name` / `let [x] = name` bindings whose initializer
/// is exactly `name`.
fn collect_destructures_of_name(
  block : @ast.TsBlock,
  name : String,
  out : Array[@ast.TsBinding],
) -> Unit {
  for s in block.stmts {
    match s {
      Var(b, _, @ast.TsExpr::Var(n))
      | Let(b, _, @ast.TsExpr::Var(n))
      | Const(b, _, @ast.TsExpr::Var(n)) => if n == name { out.push(b) }
      If(_, t, e) => {
        collect_destructures_of_name(t, name, out)
        match e {
          Some(eb) => collect_destructures_of_name(eb, name, out)
          None => ()
        }
      }
      While(_, b)
      | DoWhile(_, b)
      | With(_, b)
      | Block(b)
      | For(_, _, _, b)
      | ForOf(_, _, _, _, b)
      | ForAwaitOf(_, _, _, _, b)
      | ForIn(_, _, _, _, b) => collect_destructures_of_name(b, name, out)
      Try(b, _, c, f) => {
        collect_destructures_of_name(b, name, out)
        match c {
          Some(cb) => collect_destructures_of_name(cb, name, out)
          None => ()
        }
        match f {
          Some(fb) => collect_destructures_of_name(fb, name, out)
          None => ()
        }
      }
      Switch(_, cases) =>
        for c in cases {
          collect_destructures_of_name(c.body, name, out)
        }
      _ => ()
    }
  }
}
