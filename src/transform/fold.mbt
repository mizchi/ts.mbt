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
//   typeof 5 -> "number"  (typeof any known literal)
//   typeof "" -> "string" / typeof true -> "boolean" / etc.
//   (pure, x) -> x            (comma-expression with pure left operand)
//   function bodies: trailing `return;` dropped (implicit fall-through)
//   `expr;` statements that are pure are dropped entirely
//   `=> { return expr; }` arrow blocks collapse to `=> expr` concise form
//   Math.abs(-5) -> 5, Math.min(1,2) -> 1, Math.max(1,2) -> 2  (literal args)
//   true && y  -> y
//   false && y -> false  (y is pure)
//   true || y  -> true   (y is pure)
//   false || y -> y
//   0 && y     -> 0      (short-circuit: y never runs)
//   1 && y     -> y      (truthy literal, y always runs)
//   1 || y     -> 1      (short-circuit: y never runs)
//   "" || y    -> y      (falsy literal, y always runs)
//   cond ? a : b with cond literal (including truthy/falsy) -> the live arm
//   if (true/1/"x") {…} / if (false/0/null/…) else {…} -> the live block
//
//   "a" + "b"  -> "ab"  (string literal concatenation)
//   1 === 1    -> true  (literal strict-equality comparisons)
//   1 !== 2    -> true
//   1 < 2      -> true  (and <=, >, >= for integers)
//   "a" === "b" -> false
//   null ?? x  -> x     (null coalescing with known-nullish LHS)
//   42 ?? x    -> 42    (null coalescing with known-non-nullish LHS)
//
// "Pure" here mirrors the tree-shaker's `is_pure_init`: literals,
// function expressions, variable reads, and (recursively) pure
// object / array literals. Anything that could fire a side effect
// (calls, assignments, new, await, yield) blocks the fold so we
// don't accidentally elide observable behavior.

///|
/// If `block` is exactly `{ return EXPR; }` (one statement, a return
/// with a value), return `Some(EXPR)`. Otherwise `None`.
fn single_return_expr(block : @ast.TsBlock) -> @ast.TsExpr? {
  if block.stmts.length() == 1 {
    match block.stmts[0] {
      Return(Some(e)) => Some(e)
      _ => None
    }
  } else {
    None
  }
}

///|
/// Strip a trailing `return;` from an already-folded function body.
/// A bare `return` at the end of a function is the implicit fall-through
/// — it adds bytes without changing behavior, so we drop it.
/// Also merges `if (c) return e1; return e2;` tail into
/// `return c ? e1 : e2;`.
fn fold_func_body(block : @ast.TsBlock) -> @ast.TsBlock {
  let n = block.stmts.length()
  if n == 0 {
    return block
  }
  // `if (c) { return e1; } else { return e2; }` → `return c ? e1 : e2`
  // (also handles the else-less form: `if (c) { return e1; } return e2;`)
  let merged = if n >= 1 {
    match block.stmts[n - 1] {
      // `if (c) return e1; else return e2;` as last stmt
      If(cond, then_b, Some(else_b)) =>
        match (single_return_expr(then_b), single_return_expr(else_b)) {
          (Some(e1), Some(e2)) => {
            let prefix : Array[@ast.TsStmt] = []
            for i, s in block.stmts {
              if i < n - 1 {
                prefix.push(s)
              }
            }
            prefix.push(Return(Some(Cond(cond, e1, e2))))
            let pos : Array[Int] = []
            if block.stmt_positions.length() == n {
              for i in 0..<(n - 1) {
                pos.push(block.stmt_positions[i])
              }
              pos.push(block.stmt_positions[n - 1])
            }
            Some({ stmts: prefix, stmt_positions: pos })
          }
          _ => None
        }
      _ =>
        // `if (c) return e1; return e2;` — last two stmts
        if n >= 2 {
          match (block.stmts[n - 2], block.stmts[n - 1]) {
            (If(cond, then_b, None), Return(Some(e2))) =>
              match single_return_expr(then_b) {
                Some(e1) => {
                  let prefix : Array[@ast.TsStmt] = []
                  for i, s in block.stmts {
                    if i < n - 2 {
                      prefix.push(s)
                    }
                  }
                  prefix.push(Return(Some(Cond(cond, e1, e2))))
                  let pos : Array[Int] = []
                  if block.stmt_positions.length() == n {
                    for i in 0..<(n - 2) {
                      pos.push(block.stmt_positions[i])
                    }
                    pos.push(block.stmt_positions[n - 1])
                  }
                  Some({ stmts: prefix, stmt_positions: pos })
                }
                None => None
              }
            _ => None
          }
        } else {
          None
        }
    }
  } else {
    None
  }
  let block = match merged {
    Some(b) => b
    None => block
  }
  // Strip trailing `return;`
  let n = block.stmts.length()
  if n == 0 {
    return block
  }
  match block.stmts[n - 1] {
    Return(None) => {
      let trimmed : Array[@ast.TsStmt] = []
      for i, s in block.stmts {
        if i < n - 1 {
          trimmed.push(s)
        }
      }
      let pos : Array[Int] = []
      if block.stmt_positions.length() == n {
        for i in 0..<(n - 1) {
          pos.push(block.stmt_positions[i])
        }
      }
      { stmts: trimmed, stmt_positions: pos }
    }
    _ => block
  }
}

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
      // Generalised: any statically truthy/falsy literal may fold the
      // branch. `is_js_truthy` / `is_js_falsy` cover `BoolLit`,
      // `IntLit(0)`, `StringLit("")`, `NullLit`, and friends.
      if is_js_truthy(cond_f) {
        // Then-branch wins; splice its statements in directly so
        // subsequent passes (treeshake, mangle) see them at the
        // top level.
        for s in fold_block(then_b).stmts {
          out.push(s)
        }
      } else if is_js_falsy(cond_f) {
        match else_b {
          Some(b) =>
            for s in fold_block(b).stmts {
              out.push(s)
            }
          None => ()
        }
      } else {
        let then_f = fold_block(then_b)
        let else_f = match else_b {
          Some(b) => Some(fold_block(b))
          None => None
        }
        // `if (cond) {} else { stmts }` → `if (!cond) { stmts }`
        // saves the empty-block bytes and avoids a spurious `else`.
        let (cond_emit, then_emit, else_emit) = if then_f.stmts.is_empty() {
          match else_f {
            Some(el) if not(el.stmts.is_empty()) =>
              (UnaryOp(Not, cond_f), el, None)
            _ => (cond_f, then_f, else_f)
          }
        } else {
          (cond_f, then_f, else_f)
        }
        out.push(If(cond_emit, then_emit, else_emit))
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
    Expr(e) => {
      let ef = fold_expr(e)
      // A pure expression used as a statement has no observable effect;
      // drop it so subsequent passes don't need to prove it safe.
      if not(is_pure_value(ef)) {
        out.push(Expr(ef))
      }
    }
    Return(Some(e)) => out.push(Return(Some(fold_expr(e))))
    Return(None) | Empty | Debugger | Break(_) | Continue(_) => out.push(stmt)
    Throw(e) => out.push(Throw(fold_expr(e)))
    While(c, body) => {
      let cf = fold_expr(c)
      // `while (0)` / `while ("")` / `while (false)` → dead loop.
      if not(is_js_falsy(cf)) {
        out.push(While(cf, fold_block(body)))
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
      let disc = fold_expr(e)
      let folded_cases : Array[@ast.TsSwitchCase] = []
      for c in cases {
        let t = match c.test_expr {
          Some(te) => Some(fold_expr(te))
          None => None
        }
        folded_cases.push({ test_expr: t, body: fold_block(c.body) })
      }
      // When the discriminant is a literal, try to find the matching case.
      // If found and the case body ends with `break` (no fallthrough), splice
      // the body statements in directly and drop the switch.
      let matched = try_fold_switch(disc, folded_cases)
      match matched {
        Some(stmts) =>
          for s in stmts {
            out.push(s)
          }
        None => out.push(Switch(disc, folded_cases))
      }
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
    NativeClassStmt(decl, ctor) => {
      // Fold + strip trailing `return;` from constructor and method bodies.
      let new_ctor = match ctor {
        Some(f) =>
          Some({ ..f, body: fold_func_body(fold_block(f.body)) })
        None => None
      }
      let new_methods : Array[@ast.TsClassMethodDecl] = []
      for m in decl.methods {
        let new_body = match m.body {
          Some(b) => Some(fold_func_body(fold_block(b)))
          None => None
        }
        new_methods.push({ ..m, body: new_body })
      }
      out.push(NativeClassStmt({ ..decl, methods: new_methods }, new_ctor))
    }
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
        (Not, _) if is_js_truthy(inner_f) => BoolLit(false)
        (Not, _) if is_js_falsy(inner_f) => BoolLit(true)
        (BitwiseNot, IntLit(n)) => IntLit(-(n + 1))
        (Plus, IntLit(_)) | (Plus, NumberLit(_)) => inner_f
        // `void PURE_EXPR` → `void 0` — the argument is evaluated for
        // side effects only; since it's pure, replace with the standard
        // `void 0` idiom (saves bytes on complex pure expressions).
        (Void, _) if is_pure_value(inner_f) => UnaryOp(Void, IntLit(0))
        // `typeof LITERAL` is always a known string — fold directly.
        // Combined with `StringLit === StringLit` folding, this
        // eliminates `typeof 5 === "number"` and similar guards.
        (Typeof, IntLit(_)) | (Typeof, NumberLit(_)) => StringLit("number")
        (Typeof, StringLit(_)) => StringLit("string")
        (Typeof, BoolLit(_)) => StringLit("boolean")
        (Typeof, NullLit) => StringLit("object")
        (Typeof, FuncExpr(_)) | (Typeof, ArrowFunc(_, _, _, _)) =>
          StringLit("function")
        (Typeof, ArrayLit(_)) | (Typeof, ObjectLit(_)) => StringLit("object")
        (Typeof, BigIntLit(_)) => StringLit("bigint")
        _ => UnaryOp(op, inner_f)
      }
    }
    Cond(c, t, e) => {
      let cf = fold_expr(c)
      if is_js_truthy(cf) {
        fold_expr(t)
      } else if is_js_falsy(cf) {
        fold_expr(e)
      } else {
        Cond(cf, fold_expr(t), fold_expr(e))
      }
    }
    Call(name, args) => {
      let new_args : Array[@ast.TsExpr] = []
      for a in args {
        new_args.push(fold_expr(a))
      }
      // `String(literal)` / `Number(literal)` / `Boolean(literal)` → literal.
      if new_args.length() == 1 {
        let arg = new_args[0]
        match name {
          "String" =>
            match arg {
              StringLit(_) => arg
              IntLit(n) => StringLit(n.to_string())
              NumberLit(n) => StringLit(n.to_string())
              BoolLit(b) => StringLit(b.to_string())
              NullLit => StringLit("null")
              _ => Call(name, new_args)
            }
          "Number" =>
            match arg {
              NumberLit(_) | IntLit(_) => arg
              StringLit(s) =>
                match (try? @strconv.parse_double(s)) {
                  Ok(n) => {
                    let as_int = n.to_int()
                    if as_int.to_double() == n {
                      IntLit(as_int)
                    } else {
                      NumberLit(n)
                    }
                  }
                  Err(_) => Call(name, new_args)
                }
              BoolLit(true) => IntLit(1)
              BoolLit(false) => IntLit(0)
              NullLit => IntLit(0)
              _ => Call(name, new_args)
            }
          "Boolean" =>
            if is_js_truthy(arg) {
              BoolLit(true)
            } else if is_js_falsy(arg) {
              BoolLit(false)
            } else {
              Call(name, new_args)
            }
          _ => Call(name, new_args)
        }
      } else {
        Call(name, new_args)
      }
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
      let recv_f = fold_expr(recv)
      // `Math.method(literal)` → constant result.
      match fold_math_call(recv_f, m, new_args) {
        Some(result) => result
        None =>
          // String method folding on string literals.
          match fold_string_method(recv_f, m, new_args) {
            Some(result) => result
            None => MethodCall(recv_f, m, new_args)
          }
      }
    }
    PropAccess(recv, p) => {
      let recv_f = fold_expr(recv)
      // `"str".length` / `[…].length` → integer literal
      match (recv_f, p) {
        (StringLit(s), "length") => IntLit(s.length())
        (ArrayLit(items), "length") => IntLit(items.length())
        // `{a:1, b:2}.a` → `1` (constant prop access on object literal)
        (ObjectLit(entries), key) => {
          let mut found : @ast.TsExpr? = None
          for ent in entries {
            if ent.0 == key {
              found = Some(ent.1)
            }
          }
          match found {
            Some(v) => v
            None => PropAccess(recv_f, p)
          }
        }
        _ => PropAccess(recv_f, p)
      }
    }
    IndexAccess(recv, idx) => {
      let recv_f = fold_expr(recv)
      let idx_f = fold_expr(idx)
      // `[a,b,c][1]` → `b` (constant index into array literal)
      match (recv_f, idx_f) {
        (ArrayLit(items), IntLit(i)) =>
          if i >= 0 && i < items.length() {
            items[i]
          } else {
            IndexAccess(recv_f, idx_f)
          }
        // `{a:1,b:2}["a"]` → `1` (constant string key into object literal)
        (ObjectLit(entries), StringLit(k)) => {
          let mut found : @ast.TsExpr? = None
          for ent in entries {
            if ent.0 == k {
              found = Some(ent.1)
            }
          }
          match found {
            Some(v) => v
            None => IndexAccess(recv_f, idx_f)
          }
        }
        _ => IndexAccess(recv_f, idx_f)
      }
    }
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
    Seq(a, b) => {
      let af = fold_expr(a)
      let bf = fold_expr(b)
      // `(pure, x)` → `x`: the left side has no observable effect
      // so only the right value matters.
      if is_pure_value(af) { bf } else { Seq(af, bf) }
    }
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
        ArrowBlock(b) => {
          let folded = fold_func_body(fold_block(b))
          // `=> { return expr; }` → `=> expr` (concise form, saves
          // the `{ return ` + ` }` wrapper). Only when the block
          // has a single `return EXPR` statement.
          match single_return_expr(folded) {
            Some(e) => @ast.TsArrowBody::ArrowExpr(e)
            None => @ast.TsArrowBody::ArrowBlock(folded)
          }
        }
      }
      ArrowFunc(params, ret, new_body, is_async)
    }
    FuncExpr(f) => {
      let folded : @ast.TsFunc = { ..f, body: fold_func_body(fold_block(f.body)) }
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
      // `` `no ${expr} parts` `` with all literal expressions → plain string.
      if new_exprs.is_empty() {
        StringLit(parts[0])
      } else {
        // Try to fold all expressions to their string representations.
        let mut all_lit = true
        let buf = StringBuilder::new()
        buf.write_string(parts[0])
        for i, e in new_exprs {
          match e {
            IntLit(n) => buf.write_string(n.to_string())
            NumberLit(n) => buf.write_string(n.to_string())
            StringLit(s) => buf.write_string(s)
            BoolLit(b) => buf.write_string(b.to_string())
            _ => { all_lit = false; break }
          }
          if all_lit {
            buf.write_string(parts[i + 1])
          }
        }
        if all_lit { StringLit(buf.to_string()) } else { TemplateLiteral(parts, new_exprs) }
      }
    }
    As(inner, ty) => As(fold_expr(inner), ty)
    Satisfies(inner, ty) => Satisfies(fold_expr(inner), ty)
    NonNull(inner) => NonNull(fold_expr(inner))
    OptionalChain(inner) => OptionalChain(fold_expr(inner))
    _ => expr
  }
}

///|
/// Try to constant-fold a `recv.method(args)` call when `recv` is
/// `Math` and the arguments are numeric literals. Only covers the
/// operations implementable without a floating-point math library.
fn fold_math_call(
  recv : @ast.TsExpr,
  method : String,
  args : Array[@ast.TsExpr],
) -> @ast.TsExpr? {
  match recv {
    Var("Math") => ()
    Var("Array") => {
      // `Array.isArray(literal)` → bool
      if method == "isArray" && args.length() == 1 {
        match args[0] {
          ArrayLit(_) => return Some(BoolLit(true))
          IntLit(_)
          | NumberLit(_)
          | StringLit(_)
          | BoolLit(_)
          | NullLit
          | ObjectLit(_)
          | FuncExpr(_)
          | ArrowFunc(_, _, _, _) => return Some(BoolLit(false))
          _ => ()
        }
      }
      return None
    }
    Var("Number") => {
      if args.length() == 1 {
        match (method, args[0]) {
          ("isFinite", IntLit(_)) | ("isFinite", NumberLit(_)) =>
            return Some(BoolLit(true))
          ("isInteger", IntLit(_)) => return Some(BoolLit(true))
          ("isInteger", NumberLit(n)) => {
            let as_int = n.to_int()
            return Some(BoolLit(as_int.to_double() == n))
          }
          ("isNaN", IntLit(_)) => return Some(BoolLit(false))
          ("isNaN", NumberLit(_)) => return Some(BoolLit(false))
          _ => ()
        }
      }
      return None
    }
    _ => return None
  }
  fn as_float(e : @ast.TsExpr) -> Double? {
    match e {
      NumberLit(n) => Some(n)
      IntLit(n) => Some(n.to_double())
      _ => None
    }
  }
  fn to_lit(n : Double) -> @ast.TsExpr {
    let as_int = n.to_int()
    if as_int.to_double() == n { IntLit(as_int) } else { NumberLit(n) }
  }
  match method {
    "abs" =>
      if args.length() == 1 {
        match as_float(args[0]) {
          Some(n) => Some(to_lit(if n < 0.0 { -n } else { n }))
          None => None
        }
      } else {
        None
      }
    "sign" =>
      if args.length() == 1 {
        match as_float(args[0]) {
          Some(n) =>
            Some(
              IntLit(
                if n > 0.0 {
                  1
                } else if n < 0.0 {
                  -1
                } else {
                  0
                },
              ),
            )
          None => None
        }
      } else {
        None
      }
    "min" =>
      if args.length() == 2 {
        match (as_float(args[0]), as_float(args[1])) {
          (Some(a), Some(b)) => Some(to_lit(if a <= b { a } else { b }))
          _ => None
        }
      } else {
        None
      }
    "max" =>
      if args.length() == 2 {
        match (as_float(args[0]), as_float(args[1])) {
          (Some(a), Some(b)) => Some(to_lit(if a >= b { a } else { b }))
          _ => None
        }
      } else {
        None
      }
    "floor" | "ceil" | "round" | "trunc" =>
      // Only fold integer-valued inputs — no approximation needed.
      if args.length() == 1 {
        match as_float(args[0]) {
          Some(n) => {
            let as_int = n.to_int()
            if as_int.to_double() == n { Some(IntLit(as_int)) } else { None }
          }
          None => None
        }
      } else {
        None
      }
    "pow" =>
      if args.length() == 2 {
        match (as_float(args[0]), as_float(args[1])) {
          (Some(base), Some(exp)) => {
            // Only fold small integer exponents to avoid precision loss
            let exp_int = exp.to_int()
            if exp_int.to_double() != exp || exp_int < 0 || exp_int > 20 {
              None
            } else {
              let mut result = 1.0
              let mut i = 0
              while i < exp_int {
                result = result * base
                i = i + 1
              }
              Some(to_lit(result))
            }
          }
          _ => None
        }
      } else {
        None
      }
    _ => None
  }
}

///|
/// Fold String-literal method calls with constant arguments.
fn fold_string_method(
  recv : @ast.TsExpr,
  method : String,
  args : Array[@ast.TsExpr],
) -> @ast.TsExpr? {
  let s = match recv {
    StringLit(s) => s
    _ => return None
  }
  match method {
    "toUpperCase" | "toLowerCase" if args.length() == 0 =>
      Some(
        StringLit(
          if method == "toUpperCase" {
            s.to_upper()
          } else {
            s.to_lower()
          },
        ),
      )
    "trim" | "trimStart" | "trimEnd" if args.length() == 0 => {
      // Use simple whitespace trimming.
      let trimmed = match method {
        "trimStart" => s.trim_start()
        "trimEnd" => s.trim_end()
        _ => s.trim()
      }
      Some(StringLit(trimmed))
    }
    "includes" | "startsWith" | "endsWith" if args.length() == 1 =>
      match args[0] {
        StringLit(pat) =>
          Some(
            BoolLit(
              match method {
                "includes" => s.contains(pat)
                "startsWith" => s.has_prefix(pat)
                _ => s.has_suffix(pat)
              },
            ),
          )
        _ => None
      }
    "indexOf" if args.length() == 1 =>
      match args[0] {
        StringLit(pat) =>
          match s.find(pat) {
            Some(idx) => Some(IntLit(idx))
            None => Some(IntLit(-1))
          }
        _ => None
      }
    "charAt" if args.length() == 1 =>
      match args[0] {
        IntLit(i) =>
          if i >= 0 && i < s.length() {
            Some(StringLit(s.substring(start=i, end=i + 1).to_string()))
          } else {
            Some(StringLit(""))
          }
        _ => None
      }
    "repeat" if args.length() == 1 =>
      match args[0] {
        IntLit(n) if n >= 0 && n <= 100 => {
          let mut result = ""
          let mut i = 0
          while i < n {
            result = result + s
            i = i + 1
          }
          Some(StringLit(result))
        }
        _ => None
      }
    "slice" => {
      // `"hello".slice(start[, end])` with non-negative integer args only.
      // Negative indices require runtime string length, which we have, but
      // to keep the fold simple and correct, only fold non-negative cases.
      let len = s.length()
      let clamp = fn(i : Int) -> Int { i.max(0).min(len) }
      match args.length() {
        1 =>
          match args[0] {
            IntLit(start) if start >= 0 =>
              Some(StringLit(s.substring(start=clamp(start)).to_string()))
            _ => None
          }
        2 =>
          match (args[0], args[1]) {
            (IntLit(start), IntLit(end_)) if start >= 0 && end_ >= 0 => {
              let s0 = clamp(start)
              let e0 = clamp(end_)
              if s0 >= e0 {
                Some(StringLit(""))
              } else {
                Some(StringLit(s.substring(start=s0, end=e0).to_string()))
              }
            }
            _ => None
          }
        _ => None
      }
    }
    _ => None
  }
}

///|
/// Try to fold a `switch(literal)` statement to the matching case body.
/// Returns `Some(stmts)` when:
///   1. The discriminant is a literal with a known strict-equality value.
///   2. A case matches that literal (or `default:` if no named case matches).
///   3. The matching case ends with a `break` statement (no fallthrough to
///      the next case — fallthrough would require emitting multiple cases).
/// Returns `None` to keep the switch as-is.
fn try_fold_switch(
  disc : @ast.TsExpr,
  cases : Array[@ast.TsSwitchCase],
) -> Array[@ast.TsStmt]? {
  // Only fold when the discriminant is a known-comparable literal.
  let is_lit = match disc {
    IntLit(_) | NumberLit(_) | StringLit(_) | BoolLit(_) | NullLit => true
    _ => false
  }
  if not(is_lit) {
    return None
  }
  // Walk cases to find the first one that matches `disc` under ===.
  let mut matched_idx : Int? = None
  let mut default_idx : Int? = None
  for i, c in cases {
    match c.test_expr {
      None => default_idx = Some(i)
      Some(t) =>
        if
          match (disc, t) {
            (IntLit(a), IntLit(b)) => a == b
            (NumberLit(a), NumberLit(b)) => a == b
            (IntLit(a), NumberLit(b)) => a.to_double() == b
            (NumberLit(a), IntLit(b)) => a == b.to_double()
            (StringLit(a), StringLit(b)) => a == b
            (BoolLit(a), BoolLit(b)) => a == b
            (NullLit, NullLit) => true
            _ => false
          } {
          matched_idx = Some(i)
          break
        }
    }
  }
  let chosen_idx = match matched_idx {
    Some(i) => i
    None =>
      match default_idx {
        Some(i) => i
        None => return Some([]) // switch with no matching case → empty
      }
  }
  let body = cases[chosen_idx].body
  // Only fold when the last statement is `break` (or empty body).
  let n = body.stmts.length()
  if n == 0 {
    return Some([])
  }
  let last = body.stmts[n - 1]
  match last {
    Break(None) => {
      // Return the body without the trailing `break`.
      let stmts : Array[@ast.TsStmt] = []
      for i, s in body.stmts {
        if i < n - 1 {
          stmts.push(s)
        }
      }
      Some(stmts)
    }
    _ => None // Fallthrough or labeled break — don't fold
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
    // x * 1, 1 * x, x / 1
    (Mul, _, IntLit(1)) | (Mul, _, NumberLit(1.0)) => l
    (Mul, IntLit(1), _) | (Mul, NumberLit(1.0), _) =>
      if is_pure_value(l) {
        r
      } else {
        BinOp(op, l, r)
      }
    (Div, _, IntLit(1)) | (Div, _, NumberLit(1.0)) => l
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
    // Boolean short-circuit — BoolLit cases come first; then extend
    // to integer / string / null literals whose truthiness is known.
    (And, BoolLit(true), _) => r
    (And, BoolLit(false), _) => BoolLit(false)
    (Or, BoolLit(true), _) => BoolLit(true)
    (Or, BoolLit(false), _) => r
    // Short-circuit with known-falsy/truthy literal LHS.
    // `&&`/`||` never evaluates the right side when the left side
    // is already determinate — so `r` is unreachable regardless of
    // its purity, and the fold is always safe.
    (And, _, _) if is_js_falsy(l) => l
    (And, _, _) if is_js_truthy(l) => r
    (Or, _, _) if is_js_truthy(l) => l
    (Or, _, _) if is_js_falsy(l) => r
    // Null coalescing: `null ?? x` and `undefined ?? x` → `x`.
    // A non-nullish left operand (any literal that isn't null/undefined)
    // short-circuits to that literal.
    (Coalesce, NullLit, _) =>
      if is_pure_value(l) {
        r
      } else {
        BinOp(op, l, r)
      }
    (Coalesce, _, _) if is_pure_value(l) && not(can_be_nullish(l)) => l
    // Numeric folds where both sides are literals.
    (Add, IntLit(a), IntLit(b)) => IntLit(a + b)
    (Sub, IntLit(a), IntLit(b)) => IntLit(a - b)
    (Mul, IntLit(a), IntLit(b)) => IntLit(a * b)
    (Div, IntLit(a), IntLit(b)) =>
      // Only fold integer division when it's exact (no remainder).
      if b != 0 && a % b == 0 { IntLit(a / b) } else { BinOp(op, l, r) }
    (Mod, IntLit(a), IntLit(b)) =>
      if b != 0 { IntLit(a % b) } else { BinOp(op, l, r) }
    (Pow, IntLit(a), IntLit(b)) =>
      // Fold small integer exponents only.
      if b >= 0 && b <= 20 {
        let mut result = 1
        let mut i = 0
        while i < b {
          result = result * a
          i = i + 1
        }
        IntLit(result)
      } else {
        BinOp(op, l, r)
      }
    // Mixed int/float numeric folds
    (Add, NumberLit(a), NumberLit(b)) => NumberLit(a + b)
    (Sub, NumberLit(a), NumberLit(b)) => NumberLit(a - b)
    (Mul, NumberLit(a), NumberLit(b)) => NumberLit(a * b)
    (Add, IntLit(a), NumberLit(b)) => NumberLit(a.to_double() + b)
    (Add, NumberLit(a), IntLit(b)) => NumberLit(a + b.to_double())
    (Sub, IntLit(a), NumberLit(b)) => NumberLit(a.to_double() - b)
    (Sub, NumberLit(a), IntLit(b)) => NumberLit(a - b.to_double())
    (Mul, IntLit(a), NumberLit(b)) => NumberLit(a.to_double() * b)
    (Mul, NumberLit(a), IntLit(b)) => NumberLit(a * b.to_double())
    // String concatenation of two string literals.
    (Add, StringLit(a), StringLit(b)) => StringLit(a + b)
    // JS string coercion: `"str" + integer` / `integer + "str"` → string.
    // Only fold integer (not float) coercions to avoid MoonBit's
    // double-to-string representation differing from JS's.
    (Add, StringLit(a), IntLit(b)) => StringLit(a + b.to_string())
    (Add, IntLit(a), StringLit(b)) => StringLit(a.to_string() + b)
    // Strict-equality comparisons between homogeneous literals.
    (BinEq, IntLit(a), IntLit(b)) => BoolLit(a == b)
    (BinNe, IntLit(a), IntLit(b)) => BoolLit(a != b)
    (BinLt, IntLit(a), IntLit(b)) => BoolLit(a < b)
    (BinLe, IntLit(a), IntLit(b)) => BoolLit(a <= b)
    (BinGt, IntLit(a), IntLit(b)) => BoolLit(a > b)
    (BinGe, IntLit(a), IntLit(b)) => BoolLit(a >= b)
    (BinEq, StringLit(a), StringLit(b)) => BoolLit(a == b)
    (BinNe, StringLit(a), StringLit(b)) => BoolLit(a != b)
    (BinEq, BoolLit(a), BoolLit(b)) => BoolLit(a == b)
    (BinNe, BoolLit(a), BoolLit(b)) => BoolLit(a != b)
    (BinEq, NullLit, NullLit) => BoolLit(true)
    (BinNe, NullLit, NullLit) => BoolLit(false)
    // Cross-type strict comparisons that are always false/true.
    // Two distinct literal types can never be ===.
    (BinEq, StringLit(_), IntLit(_))
    | (BinEq, IntLit(_), StringLit(_))
    | (BinEq, StringLit(_), NullLit)
    | (BinEq, NullLit, StringLit(_))
    | (BinEq, IntLit(_), NullLit)
    | (BinEq, NullLit, IntLit(_))
    | (BinEq, BoolLit(_), NullLit)
    | (BinEq, NullLit, BoolLit(_)) => BoolLit(false)
    (BinNe, StringLit(_), IntLit(_))
    | (BinNe, IntLit(_), StringLit(_))
    | (BinNe, StringLit(_), NullLit)
    | (BinNe, NullLit, StringLit(_))
    | (BinNe, IntLit(_), NullLit)
    | (BinNe, NullLit, IntLit(_))
    | (BinNe, BoolLit(_), NullLit)
    | (BinNe, NullLit, BoolLit(_)) => BoolLit(true)
    // Bitwise/shift ops on integer literals
    (BitAnd, IntLit(a), IntLit(b)) => IntLit(a.land(b))
    (BitOr, IntLit(a), IntLit(b)) => IntLit(a.lor(b))
    (BitXor, IntLit(a), IntLit(b)) => IntLit(a.lxor(b))
    (Shl, IntLit(a), IntLit(b)) => IntLit(a.lsl(b))
    (Shr, IntLit(a), IntLit(b)) => IntLit(a.asr(b))
    (UShr, IntLit(a), IntLit(b)) => IntLit(a.lsr(b))
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
    // `/* @__PURE__ */ f(...)` — the user asserted purity, so treat
    // the call as having no observable side effects.
    PureCall(_) => true
    _ => false
  }
}

///|
/// Returns `true` when the expression is a literal known to be falsy
/// in JS boolean context: `0`, `0.0`, `""`, `false`, `null`, `undefined`.
fn is_js_falsy(expr : @ast.TsExpr) -> Bool {
  match expr {
    IntLit(0) => true
    NumberLit(n) => n == 0.0
    StringLit("") => true
    BoolLit(false) => true
    NullLit => true
    Var("undefined") => true
    // `void EXPR` always evaluates to `undefined` (falsy).
    UnaryOp(Void, _) => true
    _ => false
  }
}

///|
/// Returns `true` when the expression is a literal known to be truthy
/// in JS boolean context: non-zero integers, non-empty strings, `true`,
/// functions, arrays, objects. Only applied to values that are
/// provably literals — callers must not widen this to arbitrary exprs.
fn is_js_truthy(expr : @ast.TsExpr) -> Bool {
  match expr {
    IntLit(n) => n != 0
    NumberLit(n) => n != 0.0
    StringLit(s) => s != ""
    BoolLit(true) => true
    FuncExpr(_) | ArrowFunc(_, _, _, _) => true
    ArrayLit(_) | ObjectLit(_) => true
    BigIntLit(_) => true
    _ => false
  }
}

///|
/// Returns `true` when a pure expression could evaluate to `null` or
/// `undefined` at runtime. Used by the `??` folder to decide whether
/// the left side of a coalescing expression can short-circuit.
fn can_be_nullish(expr : @ast.TsExpr) -> Bool {
  match expr {
    NullLit => true
    Var("undefined") => true
    NumberLit(_) | IntLit(_) | BigIntLit(_) | BoolLit(_) | StringLit(_) => false
    FuncExpr(_) | ArrowFunc(_, _, _, _) => false
    ArrayLit(_) | ObjectLit(_) => false
    _ => true
  }
}
