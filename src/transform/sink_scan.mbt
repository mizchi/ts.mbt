// Sink scan — auto-reserved property names from dynamic / reflective
// access patterns the mangler can't otherwise see.
//
// The static mangler renames every property name it can prove safe.
// It bails on names listed in `reserved_properties` (built-in plus
// user-supplied). But there are categories of access where the
// receiver's identity isn't known statically:
//
//   - `obj[runtimeVar]`         — bracket access with non-literal index
//   - `for (const k in obj)`    — iterates keys at runtime
//   - `Object.keys / values / entries(obj)` — reads keys
//   - `Object.assign(t, src)`   — copies keys from src
//   - `Object.fromEntries(pairs)`/`JSON.stringify(obj)` — round-trip keys
//   - `JSON.parse(s)`           — returns an object with runtime keys
//
// When any of these appear in the bundle, the property names involved
// at the source / receiver side must stay verbatim — otherwise the
// runtime key string the user wrote (`"alpha"`, `"userField"`, …)
// won't match the mangled property anymore.
//
// `collect_dynamic_property_reservations(blocks)` walks every
// expression in every block and returns a `Set[String]` of property
// names that should be added to the mangler's reserved set. The
// bundler layers this on top of the user-supplied `reserved_properties`
// before invoking `mangle_blocks_together`.

///|
/// Walk every block and return the set of property names that
/// dynamic / reflective access patterns force into the reserved
/// set. Always conservative — when an analysis can't pin down the
/// exact receiver, every candidate key on the suspected receiver
/// is reserved.
pub fn collect_dynamic_property_reservations(
  blocks : Array[@ast.TsBlock],
) -> Array[String] {
  let reserved : Map[String, Bool] = {}
  // Index every top-level `const X = ObjectLit/ArrayLit(…)` so we
  // can recover its key list when an `obj[…]` style access lands
  // on a known immutable target.
  let const_keys : Map[String, Array[String]] = {}
  // Bindings whose RHS is an opaque runtime constructor — every
  // PropAccess on these has to be reserved because we can't see
  // the actual keys at compile time.
  let opaque_bindings : Map[String, Bool] = {}
  for b in blocks {
    for s in b.stmts {
      match s {
        Const(@ast.TsBinding::Ident(name), _, init)
        | Let(@ast.TsBinding::Ident(name), _, init)
        | Var(@ast.TsBinding::Ident(name), _, init) => {
          let peeled = @ast.peel_const_assertion(init)
          match peeled {
            ObjectLit(entries) => {
              let keys : Array[String] = []
              for ent in entries {
                if ent.0 != "..." {
                  keys.push(ent.0)
                }
              }
              const_keys[name] = keys
            }
            _ =>
              if is_opaque_constructor(peeled) {
                opaque_bindings[name] = true
              }
          }
        }
        _ => ()
      }
    }
  }
  for b in blocks {
    scan_block(b, reserved, const_keys)
    // Second pass: reserve every property key read off an opaque-
    // bound name. `JSON.parse(s)` returns runtime-typed data, so
    // `data.userField` cannot be mangled without breaking the
    // lookup against the original JSON keys.
    collect_opaque_access_keys(b, opaque_bindings, reserved)
  }
  let out : Array[String] = []
  for kv in reserved {
    out.push(kv.0)
  }
  out
}

///|
/// `true` when `expr` is a call whose result is an object with
/// runtime-determined property names — accessing any field on the
/// returned binding requires reserving that field's name.
fn is_opaque_constructor(expr : @ast.TsExpr) -> Bool {
  match expr {
    // Peel through type assertions / non-null markers — they don't
    // change the runtime value, just its declared type.
    As(inner, _) | Satisfies(inner, _) | NonNull(inner) =>
      is_opaque_constructor(inner)
    MethodCall(recv, method, _) =>
      match recv {
        Var(g) =>
          (g == "JSON" && method == "parse") ||
          (g == "Object" && method == "fromEntries") ||
          (g == "Object" && method == "assign") ||
          (g == "Array" && method == "from") ||
          (g == "Reflect" && method == "get") ||
          // localStorage / sessionStorage / Map / Set getItem style
          (method == "getItem")
        _ => false
      }
    // `fetch(...)`, `myReq.json()`, top-level function returns are
    // opaque too, but we limit the conservative set here so the
    // sink-scan doesn't reserve every random property in the bundle.
    _ => false
  }
}

///|
fn collect_opaque_access_keys(
  block : @ast.TsBlock,
  opaque : Map[String, Bool],
  reserved : Map[String, Bool],
) -> Unit {
  for s in block.stmts {
    collect_opaque_access_keys_stmt(s, opaque, reserved)
  }
}

///|
fn collect_opaque_access_keys_stmt(
  stmt : @ast.TsStmt,
  opaque : Map[String, Bool],
  reserved : Map[String, Bool],
) -> Unit {
  match stmt {
    Var(_, _, e) | Let(_, _, e) | Const(_, _, e) | Expr(e) | Throw(e) =>
      collect_opaque_access_keys_expr(e, opaque, reserved)
    Return(opt) =>
      match opt {
        Some(e) => collect_opaque_access_keys_expr(e, opaque, reserved)
        None => ()
      }
    Assign(_, e) | CompoundAssign(_, _, e) =>
      collect_opaque_access_keys_expr(e, opaque, reserved)
    PropAssign(recv, _, value) => {
      collect_opaque_access_keys_expr(recv, opaque, reserved)
      collect_opaque_access_keys_expr(value, opaque, reserved)
    }
    IndexAssign(recv, idx, value) => {
      collect_opaque_access_keys_expr(recv, opaque, reserved)
      collect_opaque_access_keys_expr(idx, opaque, reserved)
      collect_opaque_access_keys_expr(value, opaque, reserved)
    }
    If(c, t, e_opt) => {
      collect_opaque_access_keys_expr(c, opaque, reserved)
      collect_opaque_access_keys(t, opaque, reserved)
      match e_opt {
        Some(b) => collect_opaque_access_keys(b, opaque, reserved)
        None => ()
      }
    }
    While(c, b) | DoWhile(c, b) => {
      collect_opaque_access_keys_expr(c, opaque, reserved)
      collect_opaque_access_keys(b, opaque, reserved)
    }
    For(init_opt, cond_opt, update_opt, body) => {
      match init_opt {
        Some(s) => collect_opaque_access_keys_stmt(s, opaque, reserved)
        None => ()
      }
      match cond_opt {
        Some(c) => collect_opaque_access_keys_expr(c, opaque, reserved)
        None => ()
      }
      match update_opt {
        Some(s) => collect_opaque_access_keys_stmt(s, opaque, reserved)
        None => ()
      }
      collect_opaque_access_keys(body, opaque, reserved)
    }
    ForOf(_, _, _, iter, body)
    | ForAwaitOf(_, _, _, iter, body)
    | ForIn(_, _, _, iter, body) => {
      collect_opaque_access_keys_expr(iter, opaque, reserved)
      collect_opaque_access_keys(body, opaque, reserved)
    }
    Switch(scrut, cases) => {
      collect_opaque_access_keys_expr(scrut, opaque, reserved)
      for c in cases {
        match c.test_expr {
          Some(t) => collect_opaque_access_keys_expr(t, opaque, reserved)
          None => ()
        }
        collect_opaque_access_keys(c.body, opaque, reserved)
      }
    }
    Try(t, _, c, f) => {
      collect_opaque_access_keys(t, opaque, reserved)
      match c {
        Some(b) => collect_opaque_access_keys(b, opaque, reserved)
        None => ()
      }
      match f {
        Some(b) => collect_opaque_access_keys(b, opaque, reserved)
        None => ()
      }
    }
    Block(b) => collect_opaque_access_keys(b, opaque, reserved)
    Label(_, inner) => collect_opaque_access_keys_stmt(inner, opaque, reserved)
    With(target, body) => {
      collect_opaque_access_keys_expr(target, opaque, reserved)
      collect_opaque_access_keys(body, opaque, reserved)
    }
    Break(_) | Continue(_) | Empty | Debugger => ()
  }
}

///|
fn collect_opaque_access_keys_expr(
  expr : @ast.TsExpr,
  opaque : Map[String, Bool],
  reserved : Map[String, Bool],
) -> Unit {
  match expr {
    PropAccess(Var(name), prop) =>
      if opaque.contains(name) {
        reserved[prop] = true
      }
    IndexAccess(Var(name), StringLit(prop)) =>
      if opaque.contains(name) {
        reserved[prop] = true
      }
    PropAccess(recv, _) => collect_opaque_access_keys_expr(recv, opaque, reserved)
    IndexAccess(recv, idx) => {
      collect_opaque_access_keys_expr(recv, opaque, reserved)
      collect_opaque_access_keys_expr(idx, opaque, reserved)
    }
    Call(_, args) | New(_, args) =>
      for a in args {
        collect_opaque_access_keys_expr(a, opaque, reserved)
      }
    CallExpr(callee, args) | NewExpr(callee, args) => {
      collect_opaque_access_keys_expr(callee, opaque, reserved)
      for a in args {
        collect_opaque_access_keys_expr(a, opaque, reserved)
      }
    }
    MethodCall(recv, _, args) => {
      collect_opaque_access_keys_expr(recv, opaque, reserved)
      for a in args {
        collect_opaque_access_keys_expr(a, opaque, reserved)
      }
    }
    BinOp(_, l, r) | Seq(l, r) => {
      collect_opaque_access_keys_expr(l, opaque, reserved)
      collect_opaque_access_keys_expr(r, opaque, reserved)
    }
    UnaryOp(_, e) | Spread(e) | Await(e) | YieldStar(e) | NonNull(e)
    | OptionalChain(e) => collect_opaque_access_keys_expr(e, opaque, reserved)
    Yield(opt) =>
      match opt {
        Some(e) => collect_opaque_access_keys_expr(e, opaque, reserved)
        None => ()
      }
    Cond(c, t, f) => {
      collect_opaque_access_keys_expr(c, opaque, reserved)
      collect_opaque_access_keys_expr(t, opaque, reserved)
      collect_opaque_access_keys_expr(f, opaque, reserved)
    }
    ArrayLit(items) =>
      for it in items {
        collect_opaque_access_keys_expr(it, opaque, reserved)
      }
    ObjectLit(entries) =>
      for ent in entries {
        collect_opaque_access_keys_expr(ent.1, opaque, reserved)
      }
    ComputedProp(k, v) => {
      collect_opaque_access_keys_expr(k, opaque, reserved)
      collect_opaque_access_keys_expr(v, opaque, reserved)
    }
    AssignExpr(_, e) | AssignPattern(_, e) =>
      collect_opaque_access_keys_expr(e, opaque, reserved)
    CompoundAssignExpr(t, _, e) => {
      collect_opaque_access_keys_expr(t, opaque, reserved)
      collect_opaque_access_keys_expr(e, opaque, reserved)
    }
    PropAssignExpr(recv, _, value) => {
      collect_opaque_access_keys_expr(recv, opaque, reserved)
      collect_opaque_access_keys_expr(value, opaque, reserved)
    }
    IndexAssignExpr(recv, idx, value) => {
      collect_opaque_access_keys_expr(recv, opaque, reserved)
      collect_opaque_access_keys_expr(idx, opaque, reserved)
      collect_opaque_access_keys_expr(value, opaque, reserved)
    }
    ArrowFunc(_, _, body, _) =>
      match body {
        ArrowExpr(e) => collect_opaque_access_keys_expr(e, opaque, reserved)
        ArrowBlock(b) => collect_opaque_access_keys(b, opaque, reserved)
      }
    FuncExpr(f) => collect_opaque_access_keys(f.body, opaque, reserved)
    TaggedTemplate(tag, _, _, exprs) => {
      collect_opaque_access_keys_expr(tag, opaque, reserved)
      for e in exprs {
        collect_opaque_access_keys_expr(e, opaque, reserved)
      }
    }
    TemplateLiteral(_, exprs) =>
      for e in exprs {
        collect_opaque_access_keys_expr(e, opaque, reserved)
      }
    As(e, _) | Satisfies(e, _) =>
      collect_opaque_access_keys_expr(e, opaque, reserved)
    DynamicImport(spec, opt) => {
      collect_opaque_access_keys_expr(spec, opaque, reserved)
      match opt {
        Some(o) => collect_opaque_access_keys_expr(o, opaque, reserved)
        None => ()
      }
    }
    _ => ()
  }
}

///|
fn scan_block(
  block : @ast.TsBlock,
  reserved : Map[String, Bool],
  const_keys : Map[String, Array[String]],
) -> Unit {
  for s in block.stmts {
    scan_stmt(s, reserved, const_keys)
  }
}

///|
fn scan_stmt(
  stmt : @ast.TsStmt,
  reserved : Map[String, Bool],
  const_keys : Map[String, Array[String]],
) -> Unit {
  match stmt {
    // `for (const k in obj)` — every key of `obj` is observed.
    // We reserve any top-level const we can resolve the receiver
    // to, plus every key referenced inside the body via `obj[k]`.
    ForIn(_, _, _, iter, body) => {
      reserve_keys_of(iter, reserved, const_keys)
      scan_block(body, reserved, const_keys)
    }
    ForOf(_, _, _, iter, body)
    | ForAwaitOf(_, _, _, iter, body) => {
      scan_expr(iter, reserved, const_keys)
      scan_block(body, reserved, const_keys)
    }
    Var(_, _, e) | Let(_, _, e) | Const(_, _, e) | Expr(e) | Throw(e) =>
      scan_expr(e, reserved, const_keys)
    Return(opt) =>
      match opt {
        Some(e) => scan_expr(e, reserved, const_keys)
        None => ()
      }
    Assign(_, e) | CompoundAssign(_, _, e) => scan_expr(e, reserved, const_keys)
    PropAssign(recv, _, value) => {
      scan_expr(recv, reserved, const_keys)
      scan_expr(value, reserved, const_keys)
    }
    IndexAssign(recv, idx, value) => {
      scan_expr(recv, reserved, const_keys)
      scan_expr(idx, reserved, const_keys)
      scan_expr(value, reserved, const_keys)
    }
    If(c, t, e_opt) => {
      scan_expr(c, reserved, const_keys)
      scan_block(t, reserved, const_keys)
      match e_opt {
        Some(b) => scan_block(b, reserved, const_keys)
        None => ()
      }
    }
    While(c, b) | DoWhile(c, b) => {
      scan_expr(c, reserved, const_keys)
      scan_block(b, reserved, const_keys)
    }
    For(init_opt, cond_opt, update_opt, body) => {
      match init_opt {
        Some(s) => scan_stmt(s, reserved, const_keys)
        None => ()
      }
      match cond_opt {
        Some(c) => scan_expr(c, reserved, const_keys)
        None => ()
      }
      match update_opt {
        Some(s) => scan_stmt(s, reserved, const_keys)
        None => ()
      }
      scan_block(body, reserved, const_keys)
    }
    Switch(scrut, cases) => {
      scan_expr(scrut, reserved, const_keys)
      for c in cases {
        match c.test_expr {
          Some(t) => scan_expr(t, reserved, const_keys)
          None => ()
        }
        scan_block(c.body, reserved, const_keys)
      }
    }
    Try(t, _, c, f) => {
      scan_block(t, reserved, const_keys)
      match c {
        Some(b) => scan_block(b, reserved, const_keys)
        None => ()
      }
      match f {
        Some(b) => scan_block(b, reserved, const_keys)
        None => ()
      }
    }
    Block(b) => scan_block(b, reserved, const_keys)
    Label(_, inner) => scan_stmt(inner, reserved, const_keys)
    With(target, body) => {
      scan_expr(target, reserved, const_keys)
      scan_block(body, reserved, const_keys)
    }
    Break(_) | Continue(_) | Empty | Debugger => ()
  }
}

///|
fn scan_expr(
  expr : @ast.TsExpr,
  reserved : Map[String, Bool],
  const_keys : Map[String, Array[String]],
) -> Unit {
  match expr {
    // `obj[expr]` with a non-string-literal index — runtime decides
    // which key it lands on. Reserve every known key of the receiver.
    IndexAccess(recv, idx) => {
      match idx {
        StringLit(_) | IntLit(_) => () // static — mangler handles directly
        _ => reserve_keys_of(recv, reserved, const_keys)
      }
      scan_expr(recv, reserved, const_keys)
      scan_expr(idx, reserved, const_keys)
    }
    // `Object.X(obj)` and `JSON.stringify(obj)` — reflective sinks.
    MethodCall(recv, method, args) => {
      let recv_global = match recv {
        Var(n) => n
        _ => ""
      }
      let is_reflective_sink = (recv_global == "Object" &&
        (method == "keys" ||
          method == "values" ||
          method == "entries" ||
          method == "assign" ||
          method == "fromEntries" ||
          method == "getOwnPropertyNames" ||
          method == "getOwnPropertySymbols" ||
          method == "freeze" ||
          method == "seal" ||
          method == "defineProperty" ||
          method == "defineProperties")) ||
        (recv_global == "JSON" &&
          (method == "stringify" || method == "parse")) ||
        (recv_global == "Reflect" &&
          (method == "ownKeys" || method == "has" || method == "get"))
      if is_reflective_sink {
        for a in args {
          reserve_keys_of(a, reserved, const_keys)
        }
      }
      scan_expr(recv, reserved, const_keys)
      for a in args {
        scan_expr(a, reserved, const_keys)
      }
    }
    Call(_, args) | New(_, args) =>
      for a in args {
        scan_expr(a, reserved, const_keys)
      }
    CallExpr(callee, args) | NewExpr(callee, args) => {
      scan_expr(callee, reserved, const_keys)
      for a in args {
        scan_expr(a, reserved, const_keys)
      }
    }
    PropAccess(recv, _) => scan_expr(recv, reserved, const_keys)
    BinOp(_, l, r) | Seq(l, r) => {
      scan_expr(l, reserved, const_keys)
      scan_expr(r, reserved, const_keys)
    }
    UnaryOp(_, e) | Spread(e) | Await(e) | YieldStar(e) | NonNull(e)
    | OptionalChain(e) => scan_expr(e, reserved, const_keys)
    Yield(opt) =>
      match opt {
        Some(e) => scan_expr(e, reserved, const_keys)
        None => ()
      }
    Cond(c, t, f) => {
      scan_expr(c, reserved, const_keys)
      scan_expr(t, reserved, const_keys)
      scan_expr(f, reserved, const_keys)
    }
    ArrayLit(items) =>
      for it in items {
        scan_expr(it, reserved, const_keys)
      }
    ObjectLit(entries) =>
      for ent in entries {
        scan_expr(ent.1, reserved, const_keys)
      }
    ComputedProp(k, v) => {
      scan_expr(k, reserved, const_keys)
      scan_expr(v, reserved, const_keys)
    }
    AssignExpr(_, e) | AssignPattern(_, e) =>
      scan_expr(e, reserved, const_keys)
    CompoundAssignExpr(t, _, e) => {
      scan_expr(t, reserved, const_keys)
      scan_expr(e, reserved, const_keys)
    }
    PropAssignExpr(recv, _, value) => {
      scan_expr(recv, reserved, const_keys)
      scan_expr(value, reserved, const_keys)
    }
    IndexAssignExpr(recv, idx, value) => {
      match idx {
        StringLit(_) | IntLit(_) => ()
        _ => reserve_keys_of(recv, reserved, const_keys)
      }
      scan_expr(recv, reserved, const_keys)
      scan_expr(idx, reserved, const_keys)
      scan_expr(value, reserved, const_keys)
    }
    ArrowFunc(_, _, body, _) =>
      match body {
        ArrowExpr(e) => scan_expr(e, reserved, const_keys)
        ArrowBlock(b) => scan_block(b, reserved, const_keys)
      }
    FuncExpr(f) => scan_block(f.body, reserved, const_keys)
    TaggedTemplate(tag, _, _, exprs) => {
      scan_expr(tag, reserved, const_keys)
      for e in exprs {
        scan_expr(e, reserved, const_keys)
      }
    }
    TemplateLiteral(_, exprs) =>
      for e in exprs {
        scan_expr(e, reserved, const_keys)
      }
    As(e, _) | Satisfies(e, _) => scan_expr(e, reserved, const_keys)
    DynamicImport(spec, opt) => {
      scan_expr(spec, reserved, const_keys)
      match opt {
        Some(o) => scan_expr(o, reserved, const_keys)
        None => ()
      }
    }
    _ => ()
  }
}

///|
/// Try to figure out which property names belong on `expr` and add
/// them to the reserved set. Three cases are handled:
///
///   - `Var(name)` and `name` is a known top-level immutable const
///     → reserve every key from its initializer.
///   - `ObjectLit(entries)` → reserve every literal key.
///   - `ArrayLit(items)` → no string keys to reserve (numeric
///     indexing isn't subject to mangling).
///
/// Anything else (call result, dynamic chain, etc.) falls through —
/// the user must hand-reserve via `mangle.with_reserved_properties`.
fn reserve_keys_of(
  expr : @ast.TsExpr,
  reserved : Map[String, Bool],
  const_keys : Map[String, Array[String]],
) -> Unit {
  match expr {
    Var(name) =>
      match const_keys.get(name) {
        Some(keys) =>
          for k in keys {
            reserved[k] = true
          }
        None => ()
      }
    ObjectLit(entries) =>
      for ent in entries {
        if ent.0 != "..." {
          reserved[ent.0] = true
        }
      }
    As(inner, _) | Satisfies(inner, _) =>
      reserve_keys_of(inner, reserved, const_keys)
    _ => ()
  }
}
