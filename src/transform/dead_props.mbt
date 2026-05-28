// Dead-property elimination on object literals.
//
// Walks the merged bundle block and drops `key: value` pairs from
// every `ObjectLit` when the key satisfies all of:
//
//   1. Not in the caller-supplied reserved set (no type
//      declaration mentions this name).
//   2. Not read anywhere in the bundle — i.e. no `obj.name`,
//      `obj["name"]`, or destructure `{ name } = obj` access.
//   3. The value expression is pure (no side effects). A dead
//      `y: 2` is safe to drop; a dead `y: sideEffect()` is NOT
//      — even if `y` is unread, the call must still fire when
//      the object is constructed.
//
// Used by the bundler ONLY after the property-mangling safety
// analysis cleared the bundle for renaming. The same safety net
// (`JSON.stringify` / `for-in` wildcard) gates both passes.

///|
/// Drop unread, pure-valued keys from every ObjectLit in `block`.
pub fn drop_dead_properties_block(
  block : @ast.TsBlock,
  reserved : Map[String, Bool],
) -> @ast.TsBlock {
  let read_props : Map[String, Bool] = {}
  collect_read_property_names_block(block, read_props)
  let stmts : Array[@ast.TsStmt] = []
  for s in block.stmts {
    stmts.push(drop_dead_props_stmt(s, reserved, read_props))
  }
  { stmts, stmt_positions: block.stmt_positions }
}

///|
/// Names referenced as a property (`obj.name` / `obj["name"]` /
/// `{name} = obj`). Anything in this set is kept verbatim by the
/// dead-prop pass even when it's not in `reserved`.
fn collect_read_property_names_block(
  block : @ast.TsBlock,
  out : Map[String, Bool],
) -> Unit {
  for s in block.stmts {
    collect_read_property_names_stmt(s, out)
  }
}

///|
fn collect_read_property_names_stmt(
  stmt : @ast.TsStmt,
  out : Map[String, Bool],
) -> Unit {
  match stmt {
    Var(b, _, e) | Let(b, _, e) | Const(b, _, e) => {
      collect_read_property_names_binding(b, out)
      collect_read_property_names_expr(e, out)
    }
    Assign(_, e) | CompoundAssign(_, _, e) | Expr(e) | Throw(e) =>
      collect_read_property_names_expr(e, out)
    Return(Some(e)) => collect_read_property_names_expr(e, out)
    IndexAssign(t, idx, v) => {
      collect_read_property_names_expr(t, out)
      collect_read_property_names_expr(idx, out)
      collect_read_property_names_expr(v, out)
    }
    PropAssign(t, name, v) => {
      // `obj.x = …` writes to `x`, but it also makes `x` a
      // potentially-observable name; keep it reserved.
      out[name] = true
      collect_read_property_names_expr(t, out)
      collect_read_property_names_expr(v, out)
    }
    If(c, t, e) => {
      collect_read_property_names_expr(c, out)
      collect_read_property_names_block(t, out)
      match e {
        Some(b) => collect_read_property_names_block(b, out)
        None => ()
      }
    }
    While(c, b) | DoWhile(c, b) | With(c, b) => {
      collect_read_property_names_expr(c, out)
      collect_read_property_names_block(b, out)
    }
    For(init, cond, update, body) => {
      match init {
        Some(s) => collect_read_property_names_stmt(s, out)
        None => ()
      }
      match cond {
        Some(e) => collect_read_property_names_expr(e, out)
        None => ()
      }
      match update {
        Some(s) => collect_read_property_names_stmt(s, out)
        None => ()
      }
      collect_read_property_names_block(body, out)
    }
    ForOf(_, b, _, iter, body)
    | ForAwaitOf(_, b, _, iter, body)
    | ForIn(_, b, _, iter, body) => {
      collect_read_property_names_binding(b, out)
      collect_read_property_names_expr(iter, out)
      collect_read_property_names_block(body, out)
    }
    Switch(e, cases) => {
      collect_read_property_names_expr(e, out)
      for c in cases {
        match c.test_expr {
          Some(te) => collect_read_property_names_expr(te, out)
          None => ()
        }
        collect_read_property_names_block(c.body, out)
      }
    }
    Try(b, _, cb, fb) => {
      collect_read_property_names_block(b, out)
      match cb {
        Some(blk) => collect_read_property_names_block(blk, out)
        None => ()
      }
      match fb {
        Some(blk) => collect_read_property_names_block(blk, out)
        None => ()
      }
    }
    Label(_, inner) => collect_read_property_names_stmt(inner, out)
    Block(b) => collect_read_property_names_block(b, out)
    NativeClassStmt(_, _) => ()
    _ => ()
  }
}

///|
/// `const { x, y: z } = obj` reads `x` and `y` off `obj`. The pass
/// records both source-side keys (the names in `obj`) so that the
/// dead-prop pass keeps them in object literals.
fn collect_read_property_names_binding(
  binding : @ast.TsBinding,
  out : Map[String, Bool],
) -> Unit {
  match binding {
    Object(ob) =>
      for p in ob.props {
        out[p.key] = true
        collect_read_property_names_binding(p.binding, out)
      }
    Array(ab) => {
      for elem in ab.items {
        match elem {
          Some(be) => collect_read_property_names_binding(be.binding, out)
          None => ()
        }
      }
      match ab.rest {
        Some(r) => collect_read_property_names_binding(r, out)
        None => ()
      }
    }
    _ => ()
  }
}

///|
fn collect_read_property_names_expr(
  expr : @ast.TsExpr,
  out : Map[String, Bool],
) -> Unit {
  match expr {
    PropAccess(recv, name) => {
      out[name] = true
      collect_read_property_names_expr(recv, out)
    }
    MethodCall(recv, name, args) => {
      out[name] = true
      collect_read_property_names_expr(recv, out)
      for a in args {
        collect_read_property_names_expr(a, out)
      }
    }
    PropAssignExpr(recv, name, v) => {
      out[name] = true
      collect_read_property_names_expr(recv, out)
      collect_read_property_names_expr(v, out)
    }
    IndexAccess(recv, idx) => {
      // `obj["name"]` — record the literal so we don't drop it.
      match idx {
        StringLit(s) => out[s] = true
        _ => ()
      }
      collect_read_property_names_expr(recv, out)
      collect_read_property_names_expr(idx, out)
    }
    IndexAssignExpr(recv, idx, v) => {
      match idx {
        StringLit(s) => out[s] = true
        _ => ()
      }
      collect_read_property_names_expr(recv, out)
      collect_read_property_names_expr(idx, out)
      collect_read_property_names_expr(v, out)
    }
    Call(_, args) | New(_, args) =>
      for a in args {
        collect_read_property_names_expr(a, out)
      }
    CallExpr(callee, args) | NewExpr(callee, args) => {
      collect_read_property_names_expr(callee, out)
      for a in args {
        collect_read_property_names_expr(a, out)
      }
    }
    BinOp(_, l, r) => {
      collect_read_property_names_expr(l, out)
      collect_read_property_names_expr(r, out)
    }
    UnaryOp(_, inner)
    | Spread(inner)
    | Await(inner)
    | YieldStar(inner)
    | As(inner, _)
    | Satisfies(inner, _)
    | NonNull(inner)
    | OptionalChain(inner) => collect_read_property_names_expr(inner, out)
    Yield(Some(inner)) => collect_read_property_names_expr(inner, out)
    Cond(c, t, e) => {
      collect_read_property_names_expr(c, out)
      collect_read_property_names_expr(t, out)
      collect_read_property_names_expr(e, out)
    }
    ArrayLit(items) =>
      for it in items {
        collect_read_property_names_expr(it, out)
      }
    ObjectLit(entries) =>
      for ent in entries {
        collect_read_property_names_expr(ent.1, out)
      }
    ComputedProp(k, v) => {
      // `{[k]: v}` keys are dynamic; we can't analyse what they
      // map to. The safety analysis upstream already escapes such
      // bundles via the wildcard, but be conservative anyway.
      match k {
        StringLit(s) => out[s] = true
        _ => ()
      }
      collect_read_property_names_expr(k, out)
      collect_read_property_names_expr(v, out)
    }
    AssignExpr(_, v) => collect_read_property_names_expr(v, out)
    CompoundAssignExpr(t, _, v) => {
      collect_read_property_names_expr(t, out)
      collect_read_property_names_expr(v, out)
    }
    AssignPattern(b, v) => {
      collect_read_property_names_binding(b, out)
      collect_read_property_names_expr(v, out)
    }
    Seq(a, b) => {
      collect_read_property_names_expr(a, out)
      collect_read_property_names_expr(b, out)
    }
    ArrowFunc(params, _, body, _) => {
      // Destructured parameter bindings READ the property names
      // from the caller's argument — walk them so a destructured
      // `({ a, b })` doesn't make `a` / `b` look unused.
      for p in params {
        match p.binding {
          Some(b) => collect_read_property_names_binding(b, out)
          None => ()
        }
        match p.default {
          Some(d) => collect_read_property_names_expr(d, out)
          None => ()
        }
      }
      match body {
        ArrowExpr(e) => collect_read_property_names_expr(e, out)
        ArrowBlock(b) => collect_read_property_names_block(b, out)
      }
    }
    FuncExpr(f) => {
      for p in f.params {
        match p.binding {
          Some(b) => collect_read_property_names_binding(b, out)
          None => ()
        }
        match p.default {
          Some(d) => collect_read_property_names_expr(d, out)
          None => ()
        }
      }
      collect_read_property_names_block(f.body, out)
    }
    DynamicImport(spec, opts) => {
      collect_read_property_names_expr(spec, out)
      match opts {
        Some(o) => collect_read_property_names_expr(o, out)
        None => ()
      }
    }
    TaggedTemplate(tag, _, _, exprs) => {
      collect_read_property_names_expr(tag, out)
      for e in exprs {
        collect_read_property_names_expr(e, out)
      }
    }
    TemplateLiteral(_, exprs) =>
      for e in exprs {
        collect_read_property_names_expr(e, out)
      }
    _ => ()
  }
}

///|
/// Recurse through stmts, rebuilding ObjectLits with dead keys
/// removed.
fn drop_dead_props_stmt(
  stmt : @ast.TsStmt,
  reserved : Map[String, Bool],
  read_props : Map[String, Bool],
) -> @ast.TsStmt {
  match stmt {
    Var(b, t, e) => Var(b, t, drop_dead_props_expr(e, reserved, read_props))
    Let(b, t, e) => Let(b, t, drop_dead_props_expr(e, reserved, read_props))
    Const(b, t, e) => Const(b, t, drop_dead_props_expr(e, reserved, read_props))
    Assign(n, e) => Assign(n, drop_dead_props_expr(e, reserved, read_props))
    CompoundAssign(n, op, e) =>
      CompoundAssign(n, op, drop_dead_props_expr(e, reserved, read_props))
    IndexAssign(t, idx, v) =>
      IndexAssign(
        drop_dead_props_expr(t, reserved, read_props),
        drop_dead_props_expr(idx, reserved, read_props),
        drop_dead_props_expr(v, reserved, read_props),
      )
    PropAssign(t, prop, v) =>
      PropAssign(
        drop_dead_props_expr(t, reserved, read_props),
        prop,
        drop_dead_props_expr(v, reserved, read_props),
      )
    Expr(e) => Expr(drop_dead_props_expr(e, reserved, read_props))
    Return(Some(e)) =>
      Return(Some(drop_dead_props_expr(e, reserved, read_props)))
    Return(None) | Empty | Debugger | Break(_) | Continue(_) => stmt
    Throw(e) => Throw(drop_dead_props_expr(e, reserved, read_props))
    If(c, t, e) =>
      If(
        drop_dead_props_expr(c, reserved, read_props),
        drop_dead_props_block(t, reserved, read_props),
        match e {
          Some(b) => Some(drop_dead_props_block(b, reserved, read_props))
          None => None
        },
      )
    While(c, body) =>
      While(
        drop_dead_props_expr(c, reserved, read_props),
        drop_dead_props_block(body, reserved, read_props),
      )
    DoWhile(c, body) =>
      DoWhile(
        drop_dead_props_expr(c, reserved, read_props),
        drop_dead_props_block(body, reserved, read_props),
      )
    With(c, body) =>
      With(
        drop_dead_props_expr(c, reserved, read_props),
        drop_dead_props_block(body, reserved, read_props),
      )
    For(init, cond, update, body) =>
      For(
        match init {
          Some(s) => Some(drop_dead_props_stmt(s, reserved, read_props))
          None => None
        },
        match cond {
          Some(e) => Some(drop_dead_props_expr(e, reserved, read_props))
          None => None
        },
        match update {
          Some(s) => Some(drop_dead_props_stmt(s, reserved, read_props))
          None => None
        },
        drop_dead_props_block(body, reserved, read_props),
      )
    ForOf(k, b, t, iter, body) =>
      ForOf(
        k,
        b,
        t,
        drop_dead_props_expr(iter, reserved, read_props),
        drop_dead_props_block(body, reserved, read_props),
      )
    ForAwaitOf(k, b, t, iter, body) =>
      ForAwaitOf(
        k,
        b,
        t,
        drop_dead_props_expr(iter, reserved, read_props),
        drop_dead_props_block(body, reserved, read_props),
      )
    ForIn(k, b, t, iter, body) =>
      ForIn(
        k,
        b,
        t,
        drop_dead_props_expr(iter, reserved, read_props),
        drop_dead_props_block(body, reserved, read_props),
      )
    Switch(e, cases) => {
      let new_cases : Array[@ast.TsSwitchCase] = []
      for c in cases {
        new_cases.push({
          test_expr: match c.test_expr {
            Some(te) => Some(drop_dead_props_expr(te, reserved, read_props))
            None => None
          },
          body: drop_dead_props_block(c.body, reserved, read_props),
        })
      }
      Switch(drop_dead_props_expr(e, reserved, read_props), new_cases)
    }
    Try(b, bnd, cb, fb) =>
      Try(
        drop_dead_props_block(b, reserved, read_props),
        bnd,
        match cb {
          Some(blk) => Some(drop_dead_props_block(blk, reserved, read_props))
          None => None
        },
        match fb {
          Some(blk) => Some(drop_dead_props_block(blk, reserved, read_props))
          None => None
        },
      )
    Label(name, inner) =>
      Label(name, drop_dead_props_stmt(inner, reserved, read_props))
    Block(b) => Block(drop_dead_props_block(b, reserved, read_props))
    NativeClassStmt(decl, ctor) => {
      let new_ctor = match ctor {
        Some(f) =>
          Some({ ..f, body: drop_dead_props_block(f.body, reserved, read_props) })
        None => None
      }
      let new_methods : Array[@ast.TsClassMethodDecl] = []
      for m in decl.methods {
        let new_body = match m.body {
          Some(b) => Some(drop_dead_props_block(b, reserved, read_props))
          None => None
        }
        new_methods.push({ ..m, body: new_body })
      }
      NativeClassStmt({ ..decl, methods: new_methods }, new_ctor)
    }
  }
}

///|
fn drop_dead_props_block(
  block : @ast.TsBlock,
  reserved : Map[String, Bool],
  read_props : Map[String, Bool],
) -> @ast.TsBlock {
  let stmts : Array[@ast.TsStmt] = []
  for s in block.stmts {
    stmts.push(drop_dead_props_stmt(s, reserved, read_props))
  }
  { stmts, stmt_positions: block.stmt_positions }
}

///|
fn drop_dead_props_expr(
  expr : @ast.TsExpr,
  reserved : Map[String, Bool],
  read_props : Map[String, Bool],
) -> @ast.TsExpr {
  match expr {
    ObjectLit(entries) => {
      let new_entries : Array[(String, @ast.TsExpr)] = []
      for ent in entries {
        let key = ent.0
        if key == "..." {
          // Spread — keep it.
          new_entries.push(
            (key, drop_dead_props_expr(ent.1, reserved, read_props)),
          )
          continue
        }
        if reserved.contains(key) || read_props.contains(key) {
          new_entries.push(
            (key, drop_dead_props_expr(ent.1, reserved, read_props)),
          )
          continue
        }
        // Dead key — preserve only if the rhs has side effects.
        if is_value_pure(ent.1) {
          continue
        }
        // Keep but recurse anyway.
        new_entries.push(
          (key, drop_dead_props_expr(ent.1, reserved, read_props)),
        )
      }
      ObjectLit(new_entries)
    }
    BinOp(op, l, r) =>
      BinOp(
        op,
        drop_dead_props_expr(l, reserved, read_props),
        drop_dead_props_expr(r, reserved, read_props),
      )
    UnaryOp(op, inner) =>
      UnaryOp(op, drop_dead_props_expr(inner, reserved, read_props))
    Cond(c, t, e) =>
      Cond(
        drop_dead_props_expr(c, reserved, read_props),
        drop_dead_props_expr(t, reserved, read_props),
        drop_dead_props_expr(e, reserved, read_props),
      )
    Call(n, args) => {
      let new_args : Array[@ast.TsExpr] = []
      for a in args {
        new_args.push(drop_dead_props_expr(a, reserved, read_props))
      }
      Call(n, new_args)
    }
    CallExpr(callee, args) => {
      let new_args : Array[@ast.TsExpr] = []
      for a in args {
        new_args.push(drop_dead_props_expr(a, reserved, read_props))
      }
      CallExpr(drop_dead_props_expr(callee, reserved, read_props), new_args)
    }
    New(n, args) => {
      let new_args : Array[@ast.TsExpr] = []
      for a in args {
        new_args.push(drop_dead_props_expr(a, reserved, read_props))
      }
      New(n, new_args)
    }
    NewExpr(callee, args) => {
      let new_args : Array[@ast.TsExpr] = []
      for a in args {
        new_args.push(drop_dead_props_expr(a, reserved, read_props))
      }
      NewExpr(drop_dead_props_expr(callee, reserved, read_props), new_args)
    }
    MethodCall(recv, m, args) => {
      let new_args : Array[@ast.TsExpr] = []
      for a in args {
        new_args.push(drop_dead_props_expr(a, reserved, read_props))
      }
      MethodCall(drop_dead_props_expr(recv, reserved, read_props), m, new_args)
    }
    PropAccess(recv, p) =>
      PropAccess(drop_dead_props_expr(recv, reserved, read_props), p)
    IndexAccess(recv, idx) =>
      IndexAccess(
        drop_dead_props_expr(recv, reserved, read_props),
        drop_dead_props_expr(idx, reserved, read_props),
      )
    ArrayLit(items) => {
      let new_items : Array[@ast.TsExpr] = []
      for i in items {
        new_items.push(drop_dead_props_expr(i, reserved, read_props))
      }
      ArrayLit(new_items)
    }
    ComputedProp(k, v) =>
      ComputedProp(
        drop_dead_props_expr(k, reserved, read_props),
        drop_dead_props_expr(v, reserved, read_props),
      )
    Spread(inner) => Spread(drop_dead_props_expr(inner, reserved, read_props))
    Yield(Some(inner)) =>
      Yield(Some(drop_dead_props_expr(inner, reserved, read_props)))
    YieldStar(inner) =>
      YieldStar(drop_dead_props_expr(inner, reserved, read_props))
    Await(inner) => Await(drop_dead_props_expr(inner, reserved, read_props))
    Seq(a, b) =>
      Seq(
        drop_dead_props_expr(a, reserved, read_props),
        drop_dead_props_expr(b, reserved, read_props),
      )
    AssignExpr(n, v) =>
      AssignExpr(n, drop_dead_props_expr(v, reserved, read_props))
    CompoundAssignExpr(t, op, v) =>
      CompoundAssignExpr(
        drop_dead_props_expr(t, reserved, read_props),
        op,
        drop_dead_props_expr(v, reserved, read_props),
      )
    AssignPattern(b, v) =>
      AssignPattern(b, drop_dead_props_expr(v, reserved, read_props))
    PropAssignExpr(recv, p, v) =>
      PropAssignExpr(
        drop_dead_props_expr(recv, reserved, read_props),
        p,
        drop_dead_props_expr(v, reserved, read_props),
      )
    IndexAssignExpr(recv, idx, v) =>
      IndexAssignExpr(
        drop_dead_props_expr(recv, reserved, read_props),
        drop_dead_props_expr(idx, reserved, read_props),
        drop_dead_props_expr(v, reserved, read_props),
      )
    ArrowFunc(params, ret, body, is_async) => {
      let new_body = match body {
        ArrowExpr(e) =>
          @ast.TsArrowBody::ArrowExpr(
            drop_dead_props_expr(e, reserved, read_props),
          )
        ArrowBlock(b) =>
          @ast.TsArrowBody::ArrowBlock(
            drop_dead_props_block(b, reserved, read_props),
          )
      }
      ArrowFunc(params, ret, new_body, is_async)
    }
    FuncExpr(f) => {
      let new_body = drop_dead_props_block(f.body, reserved, read_props)
      FuncExpr({ ..f, body: new_body })
    }
    DynamicImport(spec, opts) => {
      let opts_f = match opts {
        Some(o) => Some(drop_dead_props_expr(o, reserved, read_props))
        None => None
      }
      DynamicImport(drop_dead_props_expr(spec, reserved, read_props), opts_f)
    }
    TaggedTemplate(tag, raw, cooked, exprs) => {
      let new_exprs : Array[@ast.TsExpr] = []
      for e in exprs {
        new_exprs.push(drop_dead_props_expr(e, reserved, read_props))
      }
      TaggedTemplate(
        drop_dead_props_expr(tag, reserved, read_props),
        raw,
        cooked,
        new_exprs,
      )
    }
    TemplateLiteral(parts, exprs) => {
      let new_exprs : Array[@ast.TsExpr] = []
      for e in exprs {
        new_exprs.push(drop_dead_props_expr(e, reserved, read_props))
      }
      TemplateLiteral(parts, new_exprs)
    }
    As(inner, ty) => As(drop_dead_props_expr(inner, reserved, read_props), ty)
    Satisfies(inner, ty) =>
      Satisfies(drop_dead_props_expr(inner, reserved, read_props), ty)
    NonNull(inner) => NonNull(drop_dead_props_expr(inner, reserved, read_props))
    OptionalChain(inner) =>
      OptionalChain(drop_dead_props_expr(inner, reserved, read_props))
    _ => expr
  }
}

///|
/// "Pure value" for the dead-prop test: dropping such a value
/// has no observable effect. Side-effect-free shapes only.
fn is_value_pure(expr : @ast.TsExpr) -> Bool {
  match expr {
    NumberLit(_)
    | IntLit(_)
    | BigIntLit(_)
    | BoolLit(_)
    | StringLit(_)
    | NullLit
    | ArrayHole
    | Var(_)
    | FuncExpr(_)
    | ArrowFunc(_, _, _, _) => true
    UnaryOp(op, inner) =>
      match op {
        PreInc | PreDec | PostInc | PostDec | Delete => false
        _ => is_value_pure(inner)
      }
    BinOp(_, l, r) => is_value_pure(l) && is_value_pure(r)
    Cond(c, t, e) => is_value_pure(c) && is_value_pure(t) && is_value_pure(e)
    ArrayLit(items) => {
      for it in items {
        if not(is_value_pure(it)) {
          return false
        }
      }
      true
    }
    ObjectLit(entries) => {
      for ent in entries {
        if not(is_value_pure(ent.1)) {
          return false
        }
      }
      true
    }
    PropAccess(recv, _) => is_value_pure(recv)
    _ => false
  }
}
