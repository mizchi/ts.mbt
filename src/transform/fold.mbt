// Lightweight constant folder.
//
// Pre-order rewrite over expressions and statements that collapses
// the obvious-but-pervasive patterns user code (and the bundler's
// merged blocks) generate:
//
//   x + 0    -> x
//   0 + x    -> x  (x is pure; otherwise we keep the form)
//   x - 0    -> x
//   x * 1    -> x
//   1 * x    -> x
//   x * 0    -> 0  (x is pure)
//   !true    -> false
//   !false   -> true
//   true && y  -> y
//   false && y -> false  (y is pure)
//   true || y  -> true   (y is pure)
//   false || y -> y
//   cond ? a : b with cond literal -> the live arm
//   if (true) {…} / if (false) {…} else {…} statements -> the live block
//
// "Pure" here mirrors the tree-shaker's `is_pure_init`: literals,
// function expressions, variable reads, and (recursively) pure
// object / array literals. Anything that could fire a side effect
// (calls, assignments, new, await, yield) blocks the fold so we
// don't accidentally elide observable behavior.

///|
/// Fold every statement in `block`, recurse into nested blocks. The
/// returned block is fresh — the input is not mutated.
pub fn fold_block(block : @ast.TsBlock) -> @ast.TsBlock {
  let stmts : Array[@ast.TsStmt] = []
  let positions : Array[Int] = []
  let has_positions = block.stmt_positions.length() == block.stmts.length()
  for i, s in block.stmts {
    let before_len = stmts.length()
    fold_stmt_into(s, stmts)
    let added = stmts.length() - before_len
    if has_positions {
      for _j in 0..<added {
        positions.push(block.stmt_positions[i])
      }
    }
  }
  { stmts, stmt_positions: positions }
}

///|
/// Fold a single statement and push the result(s) into `out`. The
/// shape is `into` rather than `-> Stmt?` because `if (true) {…}`
/// expands into multiple top-level statements (the then-branch's
/// statements) and `if (false) {…}` with no else collapses to zero.
fn fold_stmt_into(stmt : @ast.TsStmt, out : Array[@ast.TsStmt]) -> Unit {
  match stmt {
    If(cond, then_b, else_b) => {
      let cond_f = fold_expr(cond)
      match cond_f {
        BoolLit(true) =>
          // Then-branch wins; splice its statements in directly so
          // subsequent passes (treeshake, mangle) see them at the
          // top level.
          for s in fold_block(then_b).stmts {
            out.push(s)
          }
        BoolLit(false) =>
          match else_b {
            Some(b) =>
              for s in fold_block(b).stmts {
                out.push(s)
              }
            None => ()
          }
        _ =>
          out.push(
            If(
              cond_f,
              fold_block(then_b),
              match else_b {
                Some(b) => Some(fold_block(b))
                None => None
              },
            ),
          )
      }
    }
    Var(b, t, rhs) => out.push(Var(b, t, fold_expr(rhs)))
    Let(b, t, rhs) => out.push(Let(b, t, fold_expr(rhs)))
    Const(b, t, rhs) => out.push(Const(b, t, fold_expr(rhs)))
    Assign(n, rhs) => out.push(Assign(n, fold_expr(rhs)))
    CompoundAssign(n, op, rhs) =>
      out.push(CompoundAssign(n, op, fold_expr(rhs)))
    IndexAssign(target, idx, val) =>
      out.push(IndexAssign(fold_expr(target), fold_expr(idx), fold_expr(val)))
    PropAssign(target, prop, val) =>
      out.push(PropAssign(fold_expr(target), prop, fold_expr(val)))
    Expr(e) => out.push(Expr(fold_expr(e)))
    Return(Some(e)) => out.push(Return(Some(fold_expr(e))))
    Return(None) | Empty | Debugger | Break(_) | Continue(_) => out.push(stmt)
    Throw(e) => out.push(Throw(fold_expr(e)))
    While(c, body) => {
      let cf = fold_expr(c)
      match cf {
        BoolLit(false) => ()
        _ => out.push(While(cf, fold_block(body)))
      }
    }
    DoWhile(c, body) => out.push(DoWhile(fold_expr(c), fold_block(body)))
    With(c, body) => out.push(With(fold_expr(c), fold_block(body)))
    For(init, cond, update, body) => {
      let init_f = match init {
        Some(s) => {
          let tmp : Array[@ast.TsStmt] = []
          fold_stmt_into(s, tmp)
          if tmp.length() == 1 {
            Some(tmp[0])
          } else {
            init
          }
        }
        None => None
      }
      let cond_f = match cond {
        Some(e) => Some(fold_expr(e))
        None => None
      }
      let update_f = match update {
        Some(s) => {
          let tmp : Array[@ast.TsStmt] = []
          fold_stmt_into(s, tmp)
          if tmp.length() == 1 {
            Some(tmp[0])
          } else {
            update
          }
        }
        None => None
      }
      out.push(For(init_f, cond_f, update_f, fold_block(body)))
    }
    ForOf(k, b, t, iter, body) =>
      out.push(ForOf(k, b, t, fold_expr(iter), fold_block(body)))
    ForAwaitOf(k, b, t, iter, body) =>
      out.push(ForAwaitOf(k, b, t, fold_expr(iter), fold_block(body)))
    ForIn(k, b, t, iter, body) =>
      out.push(ForIn(k, b, t, fold_expr(iter), fold_block(body)))
    Switch(e, cases) => {
      let folded_cases : Array[@ast.TsSwitchCase] = []
      for c in cases {
        let t = match c.test_expr {
          Some(te) => Some(fold_expr(te))
          None => None
        }
        folded_cases.push({ test_expr: t, body: fold_block(c.body) })
      }
      out.push(Switch(fold_expr(e), folded_cases))
    }
    Try(b, bnd, cb, fb) => {
      let cb_f = match cb {
        Some(blk) => Some(fold_block(blk))
        None => None
      }
      let fb_f = match fb {
        Some(blk) => Some(fold_block(blk))
        None => None
      }
      out.push(Try(fold_block(b), bnd, cb_f, fb_f))
    }
    Label(name, inner) => {
      let tmp : Array[@ast.TsStmt] = []
      fold_stmt_into(inner, tmp)
      if tmp.length() == 1 {
        out.push(Label(name, tmp[0]))
      } else {
        // `label: { ...; ... }` — fall back to wrapping the spliced
        // stmts in a block so the label still targets exactly one
        // statement.
        out.push(Label(name, Block({ stmts: tmp, stmt_positions: [] })))
      }
    }
    Block(b) => out.push(Block(fold_block(b)))
    NativeClassStmt(_, _) => out.push(stmt)
  }
}

///|
/// Fold an expression. Recurses into sub-expressions first so we
/// see literals that only appear after lower-level folds (e.g.
/// `1 + 0 + x` -> `1 + x` -> after the outer add fold, `1 + x`
/// stays put because `1` isn't an identity element for `+`).
fn fold_expr(expr : @ast.TsExpr) -> @ast.TsExpr {
  match expr {
    BinOp(op, l, r) => {
      let lf = fold_expr(l)
      let rf = fold_expr(r)
      fold_binop(op, lf, rf)
    }
    UnaryOp(op, inner) => {
      let inner_f = fold_expr(inner)
      match (op, inner_f) {
        (Not, BoolLit(b)) => BoolLit(not(b))
        _ => UnaryOp(op, inner_f)
      }
    }
    Cond(c, t, e) => {
      let cf = fold_expr(c)
      match cf {
        BoolLit(true) => fold_expr(t)
        BoolLit(false) => fold_expr(e)
        _ => Cond(cf, fold_expr(t), fold_expr(e))
      }
    }
    Call(name, args) => {
      let new_args : Array[@ast.TsExpr] = []
      for a in args {
        new_args.push(fold_expr(a))
      }
      Call(name, new_args)
    }
    CallExpr(callee, args) => {
      let new_args : Array[@ast.TsExpr] = []
      for a in args {
        new_args.push(fold_expr(a))
      }
      CallExpr(fold_expr(callee), new_args)
    }
    New(name, args) => {
      let new_args : Array[@ast.TsExpr] = []
      for a in args {
        new_args.push(fold_expr(a))
      }
      New(name, new_args)
    }
    NewExpr(callee, args) => {
      let new_args : Array[@ast.TsExpr] = []
      for a in args {
        new_args.push(fold_expr(a))
      }
      NewExpr(fold_expr(callee), new_args)
    }
    MethodCall(recv, m, args) => {
      let new_args : Array[@ast.TsExpr] = []
      for a in args {
        new_args.push(fold_expr(a))
      }
      MethodCall(fold_expr(recv), m, new_args)
    }
    PropAccess(recv, p) => PropAccess(fold_expr(recv), p)
    IndexAccess(recv, idx) => IndexAccess(fold_expr(recv), fold_expr(idx))
    ArrayLit(items) => {
      let new_items : Array[@ast.TsExpr] = []
      for i in items {
        new_items.push(fold_expr(i))
      }
      ArrayLit(new_items)
    }
    ObjectLit(entries) => {
      let new_entries : Array[(String, @ast.TsExpr)] = []
      for ent in entries {
        new_entries.push((ent.0, fold_expr(ent.1)))
      }
      ObjectLit(new_entries)
    }
    ComputedProp(k, v) => ComputedProp(fold_expr(k), fold_expr(v))
    Spread(inner) => Spread(fold_expr(inner))
    Yield(Some(inner)) => Yield(Some(fold_expr(inner)))
    YieldStar(inner) => YieldStar(fold_expr(inner))
    Await(inner) => Await(fold_expr(inner))
    Seq(a, b) => Seq(fold_expr(a), fold_expr(b))
    AssignExpr(n, v) => AssignExpr(n, fold_expr(v))
    CompoundAssignExpr(t, op, v) =>
      CompoundAssignExpr(fold_expr(t), op, fold_expr(v))
    AssignPattern(b, v) => AssignPattern(b, fold_expr(v))
    PropAssignExpr(recv, p, v) =>
      PropAssignExpr(fold_expr(recv), p, fold_expr(v))
    IndexAssignExpr(recv, idx, v) =>
      IndexAssignExpr(fold_expr(recv), fold_expr(idx), fold_expr(v))
    ArrowFunc(params, ret, body, is_async) => {
      let new_body = match body {
        ArrowExpr(e) => @ast.TsArrowBody::ArrowExpr(fold_expr(e))
        ArrowBlock(b) => @ast.TsArrowBody::ArrowBlock(fold_block(b))
      }
      ArrowFunc(params, ret, new_body, is_async)
    }
    FuncExpr(f) => {
      let folded : @ast.TsFunc = { ..f, body: fold_block(f.body) }
      FuncExpr(folded)
    }
    DynamicImport(spec, opts) => {
      let opts_f = match opts {
        Some(o) => Some(fold_expr(o))
        None => None
      }
      DynamicImport(fold_expr(spec), opts_f)
    }
    TaggedTemplate(tag, raw, cooked, exprs) => {
      let new_exprs : Array[@ast.TsExpr] = []
      for e in exprs {
        new_exprs.push(fold_expr(e))
      }
      TaggedTemplate(fold_expr(tag), raw, cooked, new_exprs)
    }
    TemplateLiteral(parts, exprs) => {
      let new_exprs : Array[@ast.TsExpr] = []
      for e in exprs {
        new_exprs.push(fold_expr(e))
      }
      TemplateLiteral(parts, new_exprs)
    }
    As(inner, ty) => As(fold_expr(inner), ty)
    Satisfies(inner, ty) => Satisfies(fold_expr(inner), ty)
    NonNull(inner) => NonNull(fold_expr(inner))
    OptionalChain(inner) => OptionalChain(fold_expr(inner))
    _ => expr
  }
}

///|
/// Combine two already-folded sub-expressions through `op`,
/// applying identity / annihilator rewrites where it's safe.
fn fold_binop(
  op : @ast.TsBinOp,
  l : @ast.TsExpr,
  r : @ast.TsExpr,
) -> @ast.TsExpr {
  match (op, l, r) {
    // Numeric identity: x + 0, 0 + x, x - 0
    (Add, _, IntLit(0)) | (Add, _, NumberLit(0.0)) => l
    (Add, IntLit(0), _) | (Add, NumberLit(0.0), _) =>
      if is_pure_value(l) {
        r
      } else {
        BinOp(op, l, r)
      }
    (Sub, _, IntLit(0)) | (Sub, _, NumberLit(0.0)) => l
    // x * 1, 1 * x
    (Mul, _, IntLit(1)) | (Mul, _, NumberLit(1.0)) => l
    (Mul, IntLit(1), _) | (Mul, NumberLit(1.0), _) =>
      if is_pure_value(l) {
        r
      } else {
        BinOp(op, l, r)
      }
    // x * 0, 0 * x — only safe to fold when the other side is pure.
    (Mul, _, IntLit(0)) | (Mul, _, NumberLit(0.0)) =>
      if is_pure_value(l) {
        IntLit(0)
      } else {
        BinOp(op, l, r)
      }
    (Mul, IntLit(0), _) | (Mul, NumberLit(0.0), _) =>
      if is_pure_value(r) {
        IntLit(0)
      } else {
        BinOp(op, l, r)
      }
    // Boolean short-circuit
    (And, BoolLit(true), _) => r
    (And, BoolLit(false), _) => BoolLit(false)
    (Or, BoolLit(true), _) => BoolLit(true)
    (Or, BoolLit(false), _) => r
    // Numeric folds where both sides are literals.
    (Add, IntLit(a), IntLit(b)) => IntLit(a + b)
    (Sub, IntLit(a), IntLit(b)) => IntLit(a - b)
    (Mul, IntLit(a), IntLit(b)) => IntLit(a * b)
    _ => BinOp(op, l, r)
  }
}

///|
/// `is_pure_value` — does evaluating this expression have observable
/// side effects? Used to decide whether collapsing an annihilator
/// (`x * 0`) can drop the other operand.
fn is_pure_value(expr : @ast.TsExpr) -> Bool {
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
    BinOp(_, a, b) => is_pure_value(a) && is_pure_value(b)
    UnaryOp(op, inner) =>
      match op {
        PreInc | PreDec | PostInc | PostDec | Delete => false
        _ => is_pure_value(inner)
      }
    Cond(c, t, e) => is_pure_value(c) && is_pure_value(t) && is_pure_value(e)
    ArrayLit(items) => {
      for it in items {
        if not(is_pure_value(it)) {
          return false
        }
      }
      true
    }
    ObjectLit(entries) => {
      for ent in entries {
        if not(is_pure_value(ent.1)) {
          return false
        }
      }
      true
    }
    PropAccess(recv, _) => is_pure_value(recv)
    _ => false
  }
}
