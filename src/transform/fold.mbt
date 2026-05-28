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
/// If `block` is exactly `{ EXPR; }` (one expression statement),
/// return `Some(EXPR)`. Otherwise `None`.
fn single_expr_stmt(block : @ast.TsBlock) -> @ast.TsExpr? {
  if block.stmts.length() == 1 {
    match block.stmts[0] {
      Expr(e) => Some(e)
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
/// Dead code after an unconditional exit (`return`, `throw`, `break`,
/// `continue`) is silently dropped.
pub fn fold_block(block : @ast.TsBlock) -> @ast.TsBlock {
  let stmts : Array[@ast.TsStmt] = []
  let positions : Array[Int] = []
  let has_positions = block.stmt_positions.length() == block.stmts.length()
  let mut exited = false
  for i, s in block.stmts {
    if exited {
      break
    }
    let before_len = stmts.length()
    fold_stmt_into(s, stmts)
    let added = stmts.length() - before_len
    if has_positions {
      for _j in 0..<added {
        positions.push(block.stmt_positions[i])
      }
    }
    // Mark unconditional exits so dead trailing statements are dropped.
    if added > 0 {
      match stmts[stmts.length() - 1] {
        Return(_) | Throw(_) | Break(_) | Continue(_) => exited = true
        _ => ()
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
        // Helper: if a block has exactly one `expr;` or `x = rhs;` statement,
        // return the equivalent expression form. Used by both the ternary and
        // the `&&`/`||` short-circuit folds below.
        let as_single_expr = fn(block : @ast.TsBlock) -> @ast.TsExpr? {
          if block.stmts.length() == 1 {
            match block.stmts[0] {
              Expr(e) => Some(e)
              Assign(n, v) => Some(AssignExpr(n, v))
              _ => None
            }
          } else {
            None
          }
        }
        // `if (cond) { e1; } else { e2; }` → `cond ? e1 : e2;`
        // Also handles single-assign bodies.
        // Saves `if(` + `)` + `{` + `}else{` + `}` = 9 chars, adds `?` + `:` = 2 chars.
        // Special case: when both branches assign to the same bare variable,
        // `if (c) { x = e1; } else { x = e2; }` → `x = c ? e1 : e2`
        // (saves ~5 more bytes vs `c ? x = e1 : x = e2`).
        match (as_single_expr(then_f), else_f) {
          (Some(e1), Some(el)) =>
            match as_single_expr(el) {
              Some(e2) => {
                // Apply fold_expr to the synthesized Cond so patterns like
                // `!x ? e1 : e2 → x ? e2 : e1` and `!!x ? e1 : e2 → x ? e1 : e2`
                // fire even when the branches were produced by the block fold
                // rather than coming directly from a Cond expression.
                let lifted = match (e1, e2) {
                  (AssignExpr(n1, v1), AssignExpr(n2, v2)) if n1 == n2 =>
                    Assign(n1, fold_expr(Cond(cond_f, v1, v2)))
                  _ => Expr(fold_expr(Cond(cond_f, e1, e2)))
                }
                out.push(lifted)
                return
              }
              None => ()
            }
          _ => ()
        }
        // `if (cond) { expr; }` (no else) → `cond && expr;`
        // `if (cond) { x = rhs; }` (no else) → `cond && (x = rhs);`
        // Saves `if(` + `)` = 4, adds `&&` = 2 → net -2 bytes per site.
        // `if (!cond) { expr; }` → `cond || expr;`
        match (as_single_expr(then_f), else_f) {
          (Some(e), None) => {
            let short = match cond_f {
              UnaryOp(@ast.TsUnaryOp::Not, inner) =>
                BinOp(@ast.TsBinOp::Or, inner, e)
              _ => BinOp(@ast.TsBinOp::And, cond_f, e)
            }
            out.push(Expr(short))
            return
          }
          _ => ()
        }
        // `if (cond) {} else { stmts }` → `if (!cond) { stmts }`
        // saves the empty-block bytes and avoids a spurious `else`.
        // `if (cond) { stmts } else {}` → `if (cond) { stmts }`
        // An empty else branch contributes `else{}` bytes with no
        // semantic effect — drop it.
        let else_pruned = match else_f {
          Some(el) if el.stmts.is_empty() => None
          _ => else_f
        }
        let (cond_emit, then_emit, else_emit) = if then_f.stmts.is_empty() {
          match else_pruned {
            Some(el) =>
              (UnaryOp(Not, cond_f), el, None)
            _ => (cond_f, then_f, else_pruned)
          }
        } else {
          (cond_f, then_f, else_pruned)
        }
        // `if (a) { if (b) { stmts } }` → `if (a && b) { stmts }`
        // saves `if(` + `)` + wrapping braces = ~4 bytes.
        // Only applies when the outer `if` has no else, the then-branch
        // has exactly one statement, and that statement is an else-less `if`.
        let (cond_emit, then_emit, else_emit) = match else_emit {
          None =>
            if then_emit.stmts.length() == 1 {
              match then_emit.stmts[0] {
                If(inner_c, inner_t, None) =>
                  (fold_expr(BinOp(@ast.TsBinOp::And, cond_emit, inner_c)), inner_t, None)
                _ => (cond_emit, then_emit, else_emit)
              }
            } else {
              (cond_emit, then_emit, else_emit)
            }
          _ => (cond_emit, then_emit, else_emit)
        }
        out.push(If(cond_emit, then_emit, else_emit))
      }
    }
    Var(b, t, rhs) => out.push(Var(b, t, fold_expr(rhs)))
    Let(b, t, rhs) => out.push(Let(b, t, fold_expr(rhs)))
    Const(b, t, rhs) => out.push(Const(b, t, fold_expr(rhs)))
    Assign(n, rhs) => {
      let rhs_f = fold_expr(rhs)
      // `x = x` is a no-op; drop it.
      match rhs_f {
        Var(v) if v == n => ()
        _ => out.push(Assign(n, rhs_f))
      }
    }
    CompoundAssign(n, op, rhs) =>
      out.push(CompoundAssign(n, op, fold_expr(rhs)))
    IndexAssign(target, idx, val) =>
      out.push(IndexAssign(fold_expr(target), fold_expr(idx), fold_expr(val)))
    PropAssign(target, prop, val) =>
      out.push(PropAssign(fold_expr(target), prop, fold_expr(val)))
    Expr(e) => {
      let ef = fold_expr(e)
      // `void call()` in statement position → `call()`.
      // The result is discarded anyway, so the `void` wrapper saves nothing
      // and costs 5 bytes. Only strip when the inner expression is not pure
      // (a pure `void expr` is already dropped entirely by the purity check
      // below via `is_pure_value(UnaryOp(Void,pure)) = true`).
      let ef = match ef {
        UnaryOp(@ast.TsUnaryOp::Void, inner) if not(is_pure_value(inner)) =>
          inner
        _ => ef
      }
      // A pure expression used as a statement has no observable effect;
      // drop it so subsequent passes don't need to prove it safe.
      // `(a, b)` in statement position splits into two separate statements
      // so each part can be independently eliminated when pure.
      // Flatten nested Seqs using a stack to preserve left-to-right order.
      let stack : Array[@ast.TsExpr] = [ef]
      while not(stack.is_empty()) {
        let part = stack.pop().unwrap()
        match part {
          Seq(a, b) => {
            // Push right first so left is processed first (LIFO order).
            stack.push(b)
            stack.push(a)
          }
          UnaryOp(@ast.TsUnaryOp::Void, inner) =>
            if not(is_pure_value(inner)) {
              stack.push(inner)
            }
          _ => if not(is_pure_value(part)) { out.push(Expr(part)) }
        }
      }
    }
    Return(Some(e)) => {
      let ef = fold_expr(e)
      // `return undefined;` / `return void 0;` → `return;`.
      // Saves the expression bytes; `fold_func_body` then strips the
      // trailing bare `return;` from the body entirely.
      let normalized = match ef {
        Var("undefined") | UnaryOp(@ast.TsUnaryOp::Void, _) => Return(None)
        _ => Return(Some(ef))
      }
      out.push(normalized)
    }
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
      // `for (...; false; ...)` — dead loop, body never executes.
      // We still must emit the initializer (it may have side effects).
      let cond_always_false = match cond_f {
        Some(c) => is_js_falsy(c)
        None => false
      }
      if cond_always_false {
        match init_f {
          Some(s) => out.push(s)
          None => ()
        }
        return
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
    ForOf(k, b, t, iter, body) => {
      let iter_f = fold_expr(iter)
      // `for (... of [])` is a no-op — empty array produces zero iterations.
      match iter_f {
        ArrayLit([]) => ()
        _ => out.push(ForOf(k, b, t, iter_f, fold_block(body)))
      }
    }
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
      let b_f = fold_block(b)
      let cb_f = match cb {
        Some(blk) => Some(fold_block(blk))
        None => None
      }
      let fb_f = match fb {
        Some(blk) => {
          let folded = fold_block(blk)
          if folded.stmts.is_empty() { None } else { Some(folded) }
        }
        None => None
      }
      // `try { stmts } finally {}` — empty finally is a no-op; drop it.
      // If there's no catch and the finally became empty, the `try` wrapper
      // is redundant: splice the body statements in directly.
      match (cb_f, fb_f) {
        (None, None) =>
          for s in b_f.stmts {
            out.push(s)
          }
        _ => out.push(Try(b_f, bnd, cb_f, fb_f))
      }
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
      let folded_ctor : @ast.TsFunc? = match ctor {
        Some(f) => Some({ ..f, body: fold_func_body(fold_block(f.body)) })
        None => None
      }
      // Drop a no-op constructor (`constructor() {}` with no params, empty
      // body, and no base class) — JS provides an implicit default
      // constructor that is identical. When the class extends another class,
      // the implicit constructor calls `super(...arguments)` which differs
      // from an explicit empty constructor, so we only drop when base_names
      // is empty.
      let new_ctor = match folded_ctor {
        Some(f)
          if f.params.is_empty() &&
            f.body.stmts.is_empty() &&
            decl.base_names.is_empty() =>
          None
        _ => folded_ctor
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
        // `!(a === b)` → `a !== b` etc. (saves 2 bytes vs `!(...)`).
        (Not, BinOp(inner_op, a, b)) =>
          match negate_comparison_op(inner_op) {
            Some(negated) => BinOp(negated, a, b)
            None => UnaryOp(op, inner_f)
          }
        // `!!(comparison)` → `comparison` — comparisons already return
        // booleans; double negation is identity for boolean values.
        // The pattern here is `Not(Not(comparison_binop))`.
        (Not, UnaryOp(@ast.TsUnaryOp::Not, BinOp(inner_op, a, b)))
          if is_comparison_op(inner_op) =>
          BinOp(inner_op, a, b)
        (Neg, IntLit(n)) => IntLit(-n)
        (Neg, NumberLit(n)) => NumberLit(-n)
        (BitwiseNot, IntLit(n)) => IntLit(-(n + 1))
        // `~~x` → `x` when x is a pure integer literal (double bitwise-not = identity).
        (BitwiseNot, UnaryOp(@ast.TsUnaryOp::BitwiseNot, inner_inner)) =>
          if is_pure_value(inner_inner) {
            inner_inner
          } else {
            UnaryOp(op, inner_f)
          }
        (Plus, IntLit(_)) | (Plus, NumberLit(_)) => inner_f
        // `+true` → 1, `+false` → 0, `+null` → 0 (JS numeric coercion).
        (Plus, BoolLit(b)) => IntLit(if b { 1 } else { 0 })
        (Plus, NullLit) => IntLit(0)
        // `-(-x)` → `x` when x is pure (double negation cancels).
        (Neg, UnaryOp(@ast.TsUnaryOp::Neg, inner_inner)) =>
          if is_pure_value(inner_inner) {
            inner_inner
          } else {
            UnaryOp(op, inner_f)
          }
        // `-(a - b)` → `b - a` when both sides are pure.
        (Neg, BinOp(Sub, a, b)) =>
          if is_pure_value(a) && is_pure_value(b) {
            BinOp(Sub, b, a)
          } else {
            UnaryOp(op, inner_f)
          }
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
        // `typeof void 0` / `typeof undefined` → `"undefined"`.
        (Typeof, UnaryOp(@ast.TsUnaryOp::Void, _)) => StringLit("undefined")
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
        // `!!x ? a : b` → `x ? a : b` — double negation doesn't change
        // truthiness; stripping it saves 2 bytes and clarifies intent.
        // `!x ? a : b` → `x ? b : a` — single negation flips branches;
        // saves 1 byte by moving the `!` into a branch swap.
        // Both transforms are unconditionally safe: `x` is still evaluated
        // exactly once in the condition position; only branch ordering changes.
        let (cf, t, e) = match cf {
          UnaryOp(@ast.TsUnaryOp::Not, UnaryOp(@ast.TsUnaryOp::Not, inner)) =>
            (inner, t, e)
          UnaryOp(@ast.TsUnaryOp::Not, inner) => (inner, e, t)
          _ => (cf, t, e)
        }
        let tf = fold_expr(t)
        let ef = fold_expr(e)
        // `x ? x : y` → `x || y` (saves 3 bytes: `? x :` → `||`).
        // `x ? y : x` → `x && y` (saves 3 bytes: `? y :` → `&&`).
        // `c ? b : b` → `b` when `c` is pure, else `(c, b)`.
        match (cf, tf, ef) {
          (Var(cn), Var(tn), _) if cn == tn =>
            BinOp(@ast.TsBinOp::Or, Var(cn), ef)
          (Var(cn), _, Var(en)) if cn == en =>
            BinOp(@ast.TsBinOp::And, Var(cn), tf)
          (_, Var(tn), Var(en)) if tn == en =>
            // Both branches are the same var — result is always that var.
            if is_pure_value(cf) { Var(tn) } else { Seq(cf, Var(tn)) }
          // `c ? true : false` → `!!c` (saves 3+ bytes after peephole
          // turns true/false into !0/!1, making the ternary `c?!0:!1`).
          (_, BoolLit(true), BoolLit(false)) =>
            UnaryOp(
              @ast.TsUnaryOp::Not,
              UnaryOp(@ast.TsUnaryOp::Not, cf),
            )
          // `c ? false : true` → `!c`.
          (_, BoolLit(false), BoolLit(true)) =>
            UnaryOp(@ast.TsUnaryOp::Not, cf)
          // `x != null ? x : y` → `x ?? y`.
          // JS abstract-inequality with null covers both null and
          // undefined — exactly the semantics of `??`. Only safe for
          // a bare Var in the then-branch (no double evaluation).
          (BinOp(@ast.TsBinOp::AbstractNe, Var(cn), NullLit), Var(tn), _)
          | (BinOp(@ast.TsBinOp::AbstractNe, NullLit, Var(cn)), Var(tn), _)
            if cn == tn =>
            BinOp(@ast.TsBinOp::Coalesce, Var(cn), ef)
          // `x != null ? x.prop : undefined` → `x?.prop`
          // `x != null ? x.method(...) : undefined` → `x?.method(...)`
          // `x != null ? x[idx] : undefined` → `x?.[idx]`
          // Only when the else-branch is the undefined value.
          (BinOp(@ast.TsBinOp::AbstractNe, Var(cn), NullLit), PropAccess(Var(tn), prop), _)
          | (BinOp(@ast.TsBinOp::AbstractNe, NullLit, Var(cn)), PropAccess(Var(tn), prop), _)
            if cn == tn && is_nullish_or_void(ef) =>
            OptionalChain(PropAccess(Var(cn), prop))
          (BinOp(@ast.TsBinOp::AbstractNe, Var(cn), NullLit), MethodCall(Var(tn), m, args), _)
          | (BinOp(@ast.TsBinOp::AbstractNe, NullLit, Var(cn)), MethodCall(Var(tn), m, args), _)
            if cn == tn && is_nullish_or_void(ef) =>
            OptionalChain(MethodCall(Var(cn), m, args))
          (BinOp(@ast.TsBinOp::AbstractNe, Var(cn), NullLit), IndexAccess(Var(tn), idx), _)
          | (BinOp(@ast.TsBinOp::AbstractNe, NullLit, Var(cn)), IndexAccess(Var(tn), idx), _)
            if cn == tn && is_nullish_or_void(ef) =>
            OptionalChain(IndexAccess(Var(cn), idx))
          // `x == null ? void 0 : x` → `x` when x is non-nullish by context.
          // Actually: `x == null ? void 0 : x` IS equivalent to `x ?? void 0`
          // which reduces to nothing useful since void 0 is already undefined.
          // But `x == null ? y : x` where x is the else-branch → `x ?? y`.
          // This handles the `null != x ? x : y` form from the negated side.
          (BinOp(@ast.TsBinOp::AbstractEq, Var(cn), NullLit), _, Var(tn))
          | (BinOp(@ast.TsBinOp::AbstractEq, NullLit, Var(cn)), _, Var(tn))
            if cn == tn =>
            BinOp(@ast.TsBinOp::Coalesce, Var(cn), tf)
          // `x == null ? void 0 : x.prop` → `x?.prop` (negated condition form).
          // This is the TSC pattern for `x?.prop` where the ternary
          // puts the null case first.
          (BinOp(@ast.TsBinOp::AbstractEq, Var(cn), NullLit), _, PropAccess(Var(tn), prop))
          | (BinOp(@ast.TsBinOp::AbstractEq, NullLit, Var(cn)), _, PropAccess(Var(tn), prop))
            if cn == tn && is_nullish_or_void(tf) =>
            OptionalChain(PropAccess(Var(cn), prop))
          (BinOp(@ast.TsBinOp::AbstractEq, Var(cn), NullLit), _, MethodCall(Var(tn), m, args))
          | (BinOp(@ast.TsBinOp::AbstractEq, NullLit, Var(cn)), _, MethodCall(Var(tn), m, args))
            if cn == tn && is_nullish_or_void(tf) =>
            OptionalChain(MethodCall(Var(cn), m, args))
          (BinOp(@ast.TsBinOp::AbstractEq, Var(cn), NullLit), _, IndexAccess(Var(tn), idx))
          | (BinOp(@ast.TsBinOp::AbstractEq, NullLit, Var(cn)), _, IndexAccess(Var(tn), idx))
            if cn == tn && is_nullish_or_void(tf) =>
            OptionalChain(IndexAccess(Var(cn), idx))
          // `c ? (x = a) : (x = b)` → `x = c ? a : b`.
          // Both branches assign the same variable; hoist the assignment
          // outside the ternary. Saves `x=` bytes in the then-branch.
          // The expression value is the same (both sides evaluate to the
          // assigned value).
          (_, AssignExpr(n1, v1), AssignExpr(n2, v2)) if n1 == n2 =>
            AssignExpr(n1, Cond(cf, v1, v2))
          _ => Cond(cf, tf, ef)
        }
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
          "parseFloat" =>
            match arg {
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
              _ => Call(name, new_args)
            }
          "parseInt" =>
            match arg {
              StringLit(s) =>
                match parse_int_radix(s.trim().to_string(), 10) {
                  Some(n) => IntLit(n)
                  None => Call(name, new_args)
                }
              _ => Call(name, new_args)
            }
          // Global `isNaN(literal)` — numeric literals are never NaN.
          "isNaN" =>
            match arg {
              IntLit(_) | NumberLit(_) => BoolLit(false)
              BoolLit(_) | NullLit => BoolLit(false) // coerces to 0/0
              _ => Call(name, new_args)
            }
          // Global `isFinite(literal)` — integer/number literals are finite.
          "isFinite" =>
            match arg {
              IntLit(_) => BoolLit(true)
              NumberLit(n) => BoolLit(n != 1.0 / 0.0 && n != -1.0 / 0.0)
              BoolLit(_) | NullLit => BoolLit(true)
              _ => Call(name, new_args)
            }
          _ => Call(name, new_args)
        }
      } else if new_args.length() == 2 {
        // `parseInt("123", 10)` → `123` (explicit radix form).
        match (name, new_args[0], new_args[1]) {
          ("parseInt", StringLit(s), IntLit(radix)) if radix >= 2 && radix <= 36 =>
            match parse_int_radix(s.trim().to_string(), radix) {
              Some(n) => IntLit(n)
              None => Call(name, new_args)
            }
          _ => Call(name, new_args)
        }
      } else if new_args.length() == 0 {
        // Global `isNaN()` / `isFinite()` with no args: NaN / false.
        match name {
          "isNaN" => BoolLit(true) // isNaN() === isNaN(undefined) === true
          "isFinite" => BoolLit(false)
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
      let callee_f = fold_expr(callee)
      // IIFE: `((x, y) => expr)(arg1, arg2)` → substitute args for params
      // and fold the body. Only safe when:
      //   - Arrow has no rest param, no destructuring, no defaults.
      //   - Each param name appears at most once in the arg list.
      //   - All args are pure values (no side effects from evaluation order).
      //   - Body is a concise expression (not a block body).
      match callee_f {
        ArrowFunc(params, _, body, false) => {
          // Normalise both concise-expression and single-return-block bodies to
          // the body expression so one code path handles both shapes.
          //   `((x) => x + 1)(5)` — ArrowExpr
          //   `((x) => { return x + 1; })(5)` — ArrowBlock / single Return
          let body_expr_opt : @ast.TsExpr? = match body {
            ArrowExpr(e) => Some(e)
            ArrowBlock(b) =>
              if b.stmts.length() == 1 {
                match b.stmts[0] {
                  Return(Some(e)) => Some(e)
                  _ => None
                }
              } else {
                None
              }
          }
          match body_expr_opt {
            None => CallExpr(callee_f, new_args)
            Some(body_expr) => {
              // Filter out `this` type annotation params (TypeScript artifacts).
              let runtime_params : Array[@ast.TsParam] = []
              for p in params {
                if not(is_this_type_annotation_param(p)) {
                  runtime_params.push(p)
                }
              }
              if runtime_params.length() == new_args.length() {
                let mut can_inline = true
                let subs : Map[String, @ast.TsExpr] = {}
                for i, p in runtime_params {
                  if p.is_rest ||
                    p.binding != None ||
                    p.default != None ||
                    not(is_pure_value(new_args[i])) {
                    can_inline = false
                    break
                  }
                  subs[p.name] = new_args[i]
                }
                if can_inline {
                  let substituted = substitute_vars_in_expr(body_expr, subs)
                  return fold_expr(substituted)
                }
              }
              CallExpr(callee_f, new_args)
            }
          }
        }
        _ => CallExpr(callee_f, new_args)
      }
    }
    New(name, args) => {
      let new_args : Array[@ast.TsExpr] = []
      for a in args {
        new_args.push(fold_expr(a))
      }
      // `new Object()` → `{}`, `new Array()` → `[]`
      match (name, new_args.length()) {
        ("Object", 0) => ObjectLit([])
        ("Array", 0) => ArrayLit([])
        _ => New(name, new_args)
      }
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
            None =>
              // Array method folding on array literals.
              match fold_array_method(recv_f, m, new_args) {
                Some(result) => result
                None =>
                  // Number/bool/null `.toString()` folding.
                  match fold_scalar_method(recv_f, m, new_args) {
                    Some(result) => result
                    None => MethodCall(recv_f, m, new_args)
                  }
              }
          }
      }
    }
    PropAccess(recv, p) => {
      let recv_f = fold_expr(recv)
      // `"str".length` / `[…].length` → integer literal
      match (recv_f, p) {
        (StringLit(s), "length") => IntLit(s.length())
        (ArrayLit(items), "length") => IntLit(items.length())
        // Well-known Math / Number constants.
        (Var("Math"), "PI") => NumberLit(3.141592653589793)
        (Var("Math"), "E") => NumberLit(2.718281828459045)
        (Var("Math"), "LN2") => NumberLit(0.6931471805599453)
        (Var("Math"), "LN10") => NumberLit(2.302585092994046)
        (Var("Math"), "LOG2E") => NumberLit(1.4426950408889634)
        (Var("Math"), "LOG10E") => NumberLit(0.4342944819032518)
        (Var("Math"), "SQRT2") => NumberLit(1.4142135623730951)
        (Var("Number"), "MAX_SAFE_INTEGER") => NumberLit(9007199254740991.0)
        (Var("Number"), "MIN_SAFE_INTEGER") => NumberLit(-9007199254740991.0)
        (Var("Number"), "MAX_VALUE") => NumberLit(1.7976931348623157e308)
        (Var("Number"), "MIN_VALUE") => NumberLit(5.0e-324)
        (Var("Number"), "POSITIVE_INFINITY") => NumberLit(1.0 / 0.0)
        (Var("Number"), "NEGATIVE_INFINITY") => NumberLit(-1.0 / 0.0)
        (Var("Number"), "EPSILON") => NumberLit(2.220446049250313e-16)
        (Var("Number"), "NaN") => NumberLit(0.0 / 0.0)
        // `{a:1, b:2}.a` → `1` only when ALL other values are pure
        // (to avoid dropping side effects from other property initializers).
        (ObjectLit(entries), key) => {
          let mut found : @ast.TsExpr? = None
          let mut all_others_pure = true
          for ent in entries {
            if ent.0 == key {
              found = Some(ent.1)
            } else if not(is_pure_value(ent.1)) {
              all_others_pure = false
            }
          }
          match found {
            Some(v) if all_others_pure => v
            _ => PropAccess(recv_f, p)
          }
        }
        _ => PropAccess(recv_f, p)
      }
    }
    IndexAccess(recv, idx) => {
      let recv_f = fold_expr(recv)
      let idx_f = fold_expr(idx)
      // `[a,b,c][1]` → `b` only when all other items are pure.
      match (recv_f, idx_f) {
        (ArrayLit(items), IntLit(i)) =>
          if i >= 0 && i < items.length() {
            let mut all_others_pure = true
            for j, item in items {
              if j != i && not(is_pure_value(item)) {
                all_others_pure = false
                break
              }
            }
            if all_others_pure { items[i] } else { IndexAccess(recv_f, idx_f) }
          } else {
            IndexAccess(recv_f, idx_f)
          }
        // `{a:1,b:2}["a"]` → `1` only when all other values are pure.
        (ObjectLit(entries), StringLit(k)) => {
          let mut found : @ast.TsExpr? = None
          let mut all_others_pure = true
          for ent in entries {
            if ent.0 == k {
              found = Some(ent.1)
            } else if not(is_pure_value(ent.1)) {
              all_others_pure = false
            }
          }
          match found {
            Some(v) if all_others_pure => v
            _ => IndexAccess(recv_f, idx_f)
          }
        }
        // `obj["method"]` → `obj.method` when key is a valid ident.
        // Saves 2 bytes per access (drop quotes, `[`, `]`; add `.`).
        (_, StringLit(k)) if is_valid_js_ident(k) => PropAccess(recv_f, k)
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
    AssignExpr(n, v) => {
      let vf = fold_expr(v)
      // `x = x` in expression position evaluates to `x` with no other
      // observable effect (plain variable write, no setter). Simplify.
      match vf {
        Var(v2) if v2 == n => Var(n)
        _ => AssignExpr(n, vf)
      }
    }
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
    Var("Object") => {
      // `Object.keys({a:1,b:2})` → `["a","b"]` etc.
      if args.length() == 1 {
        match (method, args[0]) {
          ("keys", ObjectLit(entries)) => {
            let keys : Array[@ast.TsExpr] = []
            for ent in entries {
              keys.push(StringLit(ent.0))
            }
            return Some(ArrayLit(keys))
          }
          ("values", ObjectLit(entries)) => {
            let vals : Array[@ast.TsExpr] = []
            for ent in entries {
              vals.push(ent.1)
            }
            return Some(ArrayLit(vals))
          }
          ("entries", ObjectLit(entries)) => {
            let pairs : Array[@ast.TsExpr] = []
            for ent in entries {
              pairs.push(ArrayLit([StringLit(ent.0), ent.1]))
            }
            return Some(ArrayLit(pairs))
          }
          // `Object.freeze({...})` and `Object.seal({...})` are no-ops
          // for bundled output: the frozen/sealed state is observable only
          // via `Object.isFrozen` / attempted writes (which throw only in
          // strict mode). For minification purposes, dropping the call and
          // returning the object directly is always safe in non-strict-mode
          // code, and in practice bundlers do this.
          ("freeze", obj) | ("seal", obj) if is_pure_value(obj) =>
            return Some(obj)
          // `Object.fromEntries([["a",1],["b",2]])` → `{a:1,b:2}`
          ("fromEntries", ArrayLit(pairs)) => {
            let entries : Array[(String, @ast.TsExpr)] = []
            let mut all_ok = true
            for pair in pairs {
              match pair {
                ArrayLit([StringLit(k), v]) if is_pure_value(v) =>
                  entries.push((k, v))
                _ => { all_ok = false; break }
              }
            }
            if all_ok {
              return Some(ObjectLit(entries))
            }
          }
          _ => ()
        }
      }
      // `Object.assign({}, src1, src2, ...)` → merged object literal
      // when the first argument is `{}` and every source is a pure
      // object literal. Later sources shadow earlier ones (last-write wins).
      if method == "assign" && args.length() >= 1 {
        match args[0] {
          ObjectLit([]) => {
            let merged : Array[(String, @ast.TsExpr)] = []
            let mut all_obj_lit = true
            for i in 1..<args.length() {
              match args[i] {
                ObjectLit(src_entries) => {
                  for ent in src_entries {
                    // Remove earlier entry for the same key (last-write wins).
                    let mut found = false
                    for j in 0..<merged.length() {
                      if merged[j].0 == ent.0 {
                        merged[j] = ent
                        found = true
                        break
                      }
                    }
                    if not(found) {
                      merged.push(ent)
                    }
                  }
                }
                _ => { all_obj_lit = false; break }
              }
            }
            if all_obj_lit {
              return Some(ObjectLit(merged))
            }
          }
          _ => ()
        }
      }
      return None
    }
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
      // `Array.from([1,2,3])` → `[1,2,3]` (shallow copy of literal is
      // identical for all purely-literal elements).
      if method == "from" && args.length() == 1 {
        match args[0] {
          ArrayLit(items) => {
            let mut all_pure = true
            for item in items {
              if not(is_pure_value(item)) {
                all_pure = false
                break
              }
            }
            if all_pure {
              return Some(ArrayLit(items))
            }
          }
          _ => ()
        }
      }
      return None
    }
    Var("String") => {
      // `String.fromCharCode(65)` → `"A"` for single-char literal args.
      if method == "fromCharCode" && args.length() >= 1 {
        let buf = StringBuilder::new()
        let mut all_lit = true
        for arg in args {
          match arg {
            IntLit(n) if n >= 0 && n <= 65535 => {
              let ch = Char::from_int(n)
              buf.write_char(ch)
            }
            _ => { all_lit = false; break }
          }
        }
        if all_lit {
          return Some(StringLit(buf.to_string()))
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
          // `Number.parseFloat(s)` === `parseFloat(s)` — delegate.
          ("parseFloat", StringLit(s)) =>
            match (try? @strconv.parse_double(s)) {
              Ok(n) => {
                let as_int = n.to_int()
                return Some(
                  if as_int.to_double() == n { IntLit(as_int) } else { NumberLit(n) },
                )
              }
              Err(_) => ()
            }
          // `Number.parseInt(s)` === `parseInt(s)`.
          ("parseInt", StringLit(s)) =>
            match parse_int_radix(s.trim().to_string(), 10) {
              Some(n) => return Some(IntLit(n))
              None => ()
            }
          _ => ()
        }
      }
      // `Number.parseInt(s, radix)` with explicit radix.
      if args.length() == 2 {
        match (method, args[0], args[1]) {
          ("parseInt", StringLit(s), IntLit(radix)) if radix >= 2 && radix <= 36 =>
            match parse_int_radix(s.trim().to_string(), radix) {
              Some(n) => return Some(IntLit(n))
              None => ()
            }
          _ => ()
        }
      }
      return None
    }
    Var("JSON") => {
      if method == "stringify" && args.length() == 1 {
        // `JSON.stringify(literal)` → string literal for simple primitives.
        // Only fold when the result is unambiguous and matches V8/SpiderMonkey.
        let s = match args[0] {
          IntLit(n) => Some(n.to_string())
          NumberLit(n) => {
            let as_int = n.to_int()
            if as_int.to_double() == n { Some(as_int.to_string()) } else { None }
          }
          BoolLit(b) => Some(b.to_string())
          NullLit => Some("null")
          StringLit(s) => {
            // Produce the JSON-encoded form: `"..."` with escapes.
            let buf = StringBuilder::new()
            buf.write_char('"')
            for ch in s.iter() {
              match ch {
                '"' => buf.write_string("\\\"")
                '\\' => buf.write_string("\\\\")
                '\n' => buf.write_string("\\n")
                '\r' => buf.write_string("\\r")
                '\t' => buf.write_string("\\t")
                _ => buf.write_char(ch)
              }
            }
            buf.write_char('"')
            Some(buf.to_string())
          }
          _ => None
        }
        match s {
          Some(result) => return Some(StringLit(result))
          None => ()
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
    "min" => {
      // Fold when all arguments are numeric literals (handles 0, 1, 2+ args).
      if args.length() == 0 {
        return Some(NumberLit(1.0 / 0.0)) // Infinity
      }
      let mut result = 1.0 / 0.0 // start at Infinity
      let mut all_lit = true
      for arg in args {
        match as_float(arg) {
          Some(n) => if n < result { result = n }
          None => { all_lit = false; break }
        }
      }
      if all_lit { Some(to_lit(result)) } else { None }
    }
    "max" => {
      // Fold when all arguments are numeric literals.
      if args.length() == 0 {
        return Some(NumberLit(-1.0 / 0.0)) // -Infinity
      }
      let mut result = -1.0 / 0.0 // start at -Infinity
      let mut all_lit = true
      for arg in args {
        match as_float(arg) {
          Some(n) => if n > result { result = n }
          None => { all_lit = false; break }
        }
      }
      if all_lit { Some(to_lit(result)) } else { None }
    }
    "floor" | "ceil" | "round" | "trunc" =>
      if args.length() == 1 {
        match as_float(args[0]) {
          Some(n) => {
            // JS Math.round uses "round half away from zero" for positive,
            // and "round half up" (toward +Inf) — i.e. .5 rounds up.
            let result = match method {
              "floor" => n.floor()
              "ceil" => n.ceil()
              "round" => (n + 0.5).floor() // .5 rounds toward +Inf
              _ => if n >= 0.0 { n.floor() } else { n.ceil() } // trunc
            }
            let as_int = result.to_int()
            // Return integer form when it fits in Int, float form otherwise.
            if as_int.to_double() == result && result >= -2147483648.0 && result <= 2147483647.0 {
              Some(IntLit(as_int))
            } else {
              Some(NumberLit(result))
            }
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
/// Fold `.toString()` / `.valueOf()` on numeric, boolean, and null literals.
fn fold_scalar_method(
  recv : @ast.TsExpr,
  method : String,
  args : Array[@ast.TsExpr],
) -> @ast.TsExpr? {
  match method {
    "toString" => {
      match args.length() {
        0 =>
          match recv {
            // `(42).toString()` → `"42"`, `(3.14).toString()` → `"3.14"`
            IntLit(n) => Some(StringLit(n.to_string()))
            NumberLit(n) => Some(StringLit(n.to_string()))
            BoolLit(b) => Some(StringLit(b.to_string()))
            NullLit => Some(StringLit("null"))
            _ => None
          }
        1 =>
          // `(255).toString(16)` → `"ff"`, `(7).toString(2)` → `"111"`.
          // Only fold non-negative integers to keep it safe.
          match (recv, args[0]) {
            (IntLit(n), IntLit(radix)) if n >= 0 && radix >= 2 && radix <= 36 =>
              Some(StringLit(format_int_radix(n, radix)))
            _ => None
          }
        _ => None
      }
    }
    "valueOf" if args.length() == 0 =>
      // `.valueOf()` is identity for primitives.
      match recv {
        IntLit(_) | NumberLit(_) | BoolLit(_) | StringLit(_) => Some(recv)
        _ => None
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
        "trimStart" => s.trim_start().to_string()
        "trimEnd" => s.trim_end().to_string()
        _ => s.trim().to_string()
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
      // `"hello".slice(start[, end])` — fold all integer-arg forms,
      // including negative indices (we know the length at compile time).
      let len = s.length()
      // JS slice semantics: negative → clamp relative to end; out-of-bounds → 0/len.
      let resolve = fn(i : Int) -> Int {
        let resolved = if i < 0 { len + i } else { i }
        resolved.max(0).min(len)
      }
      match args.length() {
        1 =>
          match args[0] {
            IntLit(start) => {
              let s0 = resolve(start)
              Some(StringLit(s.substring(start=s0).to_string()))
            }
            _ => None
          }
        2 =>
          match (args[0], args[1]) {
            (IntLit(start), IntLit(end_)) => {
              let s0 = resolve(start)
              let e0 = resolve(end_)
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
    "substring" => {
      // `"hello".substring(start[, end])` — same as slice but clamps negatives to 0.
      let len = s.length()
      let clamp = fn(i : Int) -> Int { i.max(0).min(len) }
      match args.length() {
        1 =>
          match args[0] {
            IntLit(start) =>
              Some(StringLit(s.substring(start=clamp(start)).to_string()))
            _ => None
          }
        2 =>
          match (args[0], args[1]) {
            (IntLit(start), IntLit(end_)) => {
              let s0 = clamp(start)
              let e0 = clamp(end_)
              // `substring` swaps arguments when start > end.
              let lo = s0.min(e0)
              let hi = s0.max(e0)
              if lo >= hi {
                Some(StringLit(""))
              } else {
                Some(StringLit(s.substring(start=lo, end=hi).to_string()))
              }
            }
            _ => None
          }
        _ => None
      }
    }
    "at" if args.length() == 1 =>
      // `"hello".at(0)` / `"hello".at(-1)` → char at position (or empty string).
      match args[0] {
        IntLit(i) => {
          let len = s.length()
          let idx = if i < 0 { len + i } else { i }
          if idx >= 0 && idx < len {
            Some(StringLit(s.substring(start=idx, end=idx + 1).to_string()))
          } else {
            // `undefined` in JS — we can't return a meaningful value.
            None
          }
        }
        _ => None
      }
    "charCodeAt" if args.length() == 1 =>
      // `"A".charCodeAt(0)` → 65
      match args[0] {
        IntLit(i) if i >= 0 && i < s.length() =>
          Some(IntLit(s[i].to_int()))
        _ => None
      }
    "codePointAt" if args.length() == 1 =>
      // `"A".codePointAt(0)` → 65 (same as charCodeAt for BMP chars)
      match args[0] {
        IntLit(i) if i >= 0 && i < s.length() =>
          Some(IntLit(s[i].to_int()))
        _ => None
      }
    "padStart" => {
      // `"5".padStart(3, "0")` → `"005"`, `"5".padStart(3)` → `"  5"`
      let len = s.length()
      let (target_len, pad) = match args.length() {
        1 =>
          match args[0] {
            IntLit(n) if n >= 0 && n <= 1000 => (n, " ")
            _ => return None
          }
        2 =>
          match (args[0], args[1]) {
            (IntLit(n), StringLit(p)) if n >= 0 && n <= 1000 && p.length() > 0 =>
              (n, p)
            _ => return None
          }
        _ => return None
      }
      if target_len <= len {
        Some(StringLit(s))
      } else {
        let needed = target_len - len
        let pad_len = pad.length()
        let mut result = ""
        let mut i = 0
        while i < needed {
          result = result + pad.substring(start=i % pad_len, end=i % pad_len + 1).to_string()
          i = i + 1
        }
        Some(StringLit(result + s))
      }
    }
    "padEnd" => {
      // `"hello".padEnd(10)` → `"hello     "`
      let len = s.length()
      let (target_len, pad) = match args.length() {
        1 =>
          match args[0] {
            IntLit(n) if n >= 0 && n <= 1000 => (n, " ")
            _ => return None
          }
        2 =>
          match (args[0], args[1]) {
            (IntLit(n), StringLit(p)) if n >= 0 && n <= 1000 && p.length() > 0 =>
              (n, p)
            _ => return None
          }
        _ => return None
      }
      if target_len <= len {
        Some(StringLit(s))
      } else {
        let needed = target_len - len
        let pad_len = pad.length()
        let mut result = s
        let mut i = 0
        while i < needed {
          result = result + pad.substring(start=i % pad_len, end=i % pad_len + 1).to_string()
          i = i + 1
        }
        Some(StringLit(result))
      }
    }
    "split" if args.length() == 1 =>
      // `"a,b,c".split(",")` → `["a","b","c"]`
      // Only fold when the separator is a string literal.
      match args[0] {
        StringLit(sep) => {
          let parts = s.split(sep)
          let items : Array[@ast.TsExpr] = []
          for p in parts {
            items.push(StringLit(p.to_string()))
          }
          Some(ArrayLit(items))
        }
        _ => None
      }
    "replace" if args.length() == 2 =>
      // `"hello world".replace("world", "there")` → `"hello there"`
      // Only fold for string patterns (no regex). Replaces first occurrence.
      match (args[0], args[1]) {
        (StringLit(pat), StringLit(rep)) =>
          match s.find(pat) {
            Some(idx) => {
              let before = s.substring(end=idx).to_string()
              let after = s.substring(start=idx + pat.length()).to_string()
              Some(StringLit(before + rep + after))
            }
            None => Some(StringLit(s))
          }
        _ => None
      }
    "replaceAll" if args.length() == 2 =>
      // `"aXbXc".replaceAll("X", "-")` → `"a-b-c"` for literal patterns.
      match (args[0], args[1]) {
        (StringLit(pat), StringLit(rep)) if pat.length() > 0 => {
          let parts : Array[String] = []
          for p in s.split(pat) {
            parts.push(p.to_string())
          }
          Some(StringLit(parts.join(rep)))
        }
        _ => None
      }
    _ => None
  }
}

///|
/// Fold Array-literal method calls with constant arguments.
fn fold_array_method(
  recv : @ast.TsExpr,
  method : String,
  args : Array[@ast.TsExpr],
) -> @ast.TsExpr? {
  let items = match recv {
    ArrayLit(items) => items
    _ => return None
  }
  match method {
    "length" if args.length() == 0 => Some(IntLit(items.length()))
    "join" => {
      // `[a,b,c].join(sep)` → string literal when all items are literals.
      let sep = match args.length() {
        0 => ","
        1 =>
          match args[0] {
            StringLit(s) => s
            _ => return None
          }
        _ => return None
      }
      let parts : Array[String] = []
      let mut all_lit = true
      for item in items {
        match item {
          StringLit(s) => parts.push(s)
          IntLit(n) => parts.push(n.to_string())
          NumberLit(n) => parts.push(n.to_string())
          BoolLit(b) => parts.push(b.to_string())
          NullLit => parts.push("null")
          _ => {
            all_lit = false
            break
          }
        }
      }
      if all_lit { Some(StringLit(parts.join(sep))) } else { None }
    }
    "includes" if args.length() == 1 => {
      // `[1,2,3].includes(2)` → true/false when all items are literals.
      let needle = args[0]
      let mut all_pure = true
      for item in items {
        if not(is_pure_value(item)) {
          all_pure = false
          break
        }
      }
      if not(all_pure) {
        return None
      }
      // Check if any item is strictly equal to the needle.
      let mut found = false
      for item in items {
        match (item, needle) {
          (IntLit(a), IntLit(b)) => if a == b { found = true }
          (StringLit(a), StringLit(b)) => if a == b { found = true }
          (BoolLit(a), BoolLit(b)) => if a == b { found = true }
          (NullLit, NullLit) => found = true
          _ => ()
        }
      }
      Some(BoolLit(found))
    }
    "indexOf" if args.length() == 1 => {
      let needle = args[0]
      let mut all_pure = true
      for item in items {
        if not(is_pure_value(item)) {
          all_pure = false
          break
        }
      }
      if not(all_pure) {
        return None
      }
      let mut found_idx = -1
      for i, item in items {
        if found_idx >= 0 {
          break
        }
        match (item, needle) {
          (IntLit(a), IntLit(b)) => if a == b { found_idx = i }
          (StringLit(a), StringLit(b)) => if a == b { found_idx = i }
          (BoolLit(a), BoolLit(b)) => if a == b { found_idx = i }
          (NullLit, NullLit) => found_idx = i
          _ => ()
        }
      }
      Some(IntLit(found_idx))
    }
    "reverse" if args.length() == 0 => {
      // Only fold small pure arrays.
      if items.length() > 16 {
        return None
      }
      let mut all_pure = true
      for item in items {
        if not(is_pure_value(item)) {
          all_pure = false
          break
        }
      }
      if not(all_pure) {
        return None
      }
      let rev : Array[@ast.TsExpr] = []
      for i = items.length() - 1; i >= 0; i = i - 1 {
        rev.push(items[i])
      }
      Some(ArrayLit(rev))
    }
    "concat" => {
      // `[a,b].concat([c,d])` → `[a,b,c,d]` when all items are pure.
      let mut all_pure = true
      for item in items {
        if not(is_pure_value(item)) {
          all_pure = false
          break
        }
      }
      if not(all_pure) {
        return None
      }
      let result : Array[@ast.TsExpr] = []
      for item in items {
        result.push(item)
      }
      for arg in args {
        match arg {
          ArrayLit(extra) => {
            let mut arg_pure = true
            for item in extra {
              if not(is_pure_value(item)) {
                arg_pure = false
                break
              }
            }
            if not(arg_pure) {
              return None
            }
            for item in extra {
              result.push(item)
            }
          }
          _ =>
            // Non-array arg: JS pushes the arg itself, but we'd need
            // to handle that case carefully — just bail out.
            return None
        }
      }
      Some(ArrayLit(result))
    }
    "flat" if args.length() == 0 => {
      // `[a, [b, c], d].flat()` → `[a, b, c, d]` for one level of nesting.
      let result : Array[@ast.TsExpr] = []
      for item in items {
        match item {
          ArrayLit(inner) => {
            for inner_item in inner {
              if not(is_pure_value(inner_item)) {
                return None
              }
              result.push(inner_item)
            }
          }
          _ =>
            if is_pure_value(item) {
              result.push(item)
            } else {
              return None
            }
        }
      }
      Some(ArrayLit(result))
    }
    "slice" => {
      // `[1,2,3].slice(start[, end])` — same semantics as String.slice
      // but returns a new array.  Only fold when all items are pure.
      let len = items.length()
      let resolve = fn(i : Int) -> Int {
        let r = if i < 0 { len + i } else { i }
        r.max(0).min(len)
      }
      let mut all_pure = true
      for item in items {
        if not(is_pure_value(item)) {
          all_pure = false
          break
        }
      }
      if not(all_pure) {
        return None
      }
      let (s0, e0) = match args.length() {
        1 =>
          match args[0] {
            IntLit(start) => (resolve(start), len)
            _ => return None
          }
        2 =>
          match (args[0], args[1]) {
            (IntLit(start), IntLit(end_)) => (resolve(start), resolve(end_))
            _ => return None
          }
        _ => return None
      }
      let sliced : Array[@ast.TsExpr] = []
      for i in s0..<e0 {
        sliced.push(items[i])
      }
      Some(ArrayLit(sliced))
    }
    "at" if args.length() == 1 =>
      // `[1,2,3].at(-1)` → `3`
      match args[0] {
        IntLit(i) => {
          let len = items.length()
          let idx = if i < 0 { len + i } else { i }
          if idx >= 0 && idx < len && is_pure_value(items[idx]) {
            // Check all other items are also pure so we don't drop
            // side effects from items we skip.
            let mut all_pure = true
            for j, item in items {
              if j != idx && not(is_pure_value(item)) {
                all_pure = false
                break
              }
            }
            if all_pure { Some(items[idx]) } else { None }
          } else {
            None
          }
        }
        _ => None
      }
    // Empty-array vacuous folds — safe regardless of the callback purity.
    "every" if args.length() == 1 && items.is_empty() => Some(BoolLit(true))
    "some" if args.length() == 1 && items.is_empty() => Some(BoolLit(false))
    "find" if items.is_empty() => Some(Var("undefined"))
    "findIndex" if items.is_empty() => Some(IntLit(-1))
    "filter" | "map" if items.is_empty() => Some(ArrayLit([]))
    "reduce" if items.is_empty() && args.length() == 2 =>
      // `[].reduce(fn, init)` → init when init is pure.
      if is_pure_value(args[1]) { Some(args[1]) } else { None }
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
    // `x && x` → `x` and `x || x` → `x` for same-var operands.
    // Both operators always evaluate to `x` regardless of its value.
    (And, Var(ln), Var(rn)) | (Or, Var(ln), Var(rn)) if ln == rn => Var(ln)
    // Bitwise idempotency: `x | x → x`, `x & x → x`, `x ^ x → 0`.
    // String equality on Var names is sufficient since we only match
    // bare `Var` nodes (no side-effecting sub-expressions).
    (BitOr, Var(ln), Var(rn)) | (BitAnd, Var(ln), Var(rn)) if ln == rn =>
      Var(ln)
    (BitXor, Var(ln), Var(rn)) if ln == rn => IntLit(0)
    // `x - x → 0` when x is a bare variable (pure, no double evaluation).
    (Sub, Var(ln), Var(rn)) if ln == rn => IntLit(0)
    // Null coalescing: `null ?? x` and `undefined ?? x` → `x`.
    // A non-nullish left operand (any literal that isn't null/undefined)
    // short-circuits to that literal.
    // `null ?? x`, `undefined ?? x`, `void expr ?? x` → `x` (nullish LHS).
    (Coalesce, NullLit, _)
    | (Coalesce, Var("undefined"), _)
    | (Coalesce, UnaryOp(@ast.TsUnaryOp::Void, _), _) =>
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
    (Div, NumberLit(a), NumberLit(b)) if b != 0.0 => NumberLit(a / b)
    (Add, IntLit(a), NumberLit(b)) => NumberLit(a.to_double() + b)
    (Add, NumberLit(a), IntLit(b)) => NumberLit(a + b.to_double())
    (Sub, IntLit(a), NumberLit(b)) => NumberLit(a.to_double() - b)
    (Sub, NumberLit(a), IntLit(b)) => NumberLit(a - b.to_double())
    (Mul, IntLit(a), NumberLit(b)) => NumberLit(a.to_double() * b)
    (Mul, NumberLit(a), IntLit(b)) => NumberLit(a * b.to_double())
    // Integer-producing integer division (non-exact results folded to float)
    (Div, IntLit(a), IntLit(b)) if b != 0 && a % b != 0 =>
      NumberLit(a.to_double() / b.to_double())
    // String concatenation of two string literals.
    (Add, StringLit(a), StringLit(b)) => StringLit(a + b)
    // JS string coercion: `"str" + number` / `number + "str"` → string.
    // Only fold integer (not float) coercions to avoid MoonBit's
    // double-to-string representation differing from JS's.
    (Add, StringLit(a), IntLit(b)) => StringLit(a + b.to_string())
    (Add, IntLit(a), StringLit(b)) => StringLit(a.to_string() + b)
    // BoolLit and NullLit string coercions.
    (Add, StringLit(a), BoolLit(b)) => StringLit(a + b.to_string())
    (Add, BoolLit(a), StringLit(b)) => StringLit(a.to_string() + b)
    (Add, StringLit(a), NullLit) => StringLit(a + "null")
    (Add, NullLit, StringLit(b)) => StringLit("null" + b)
    // Strict-equality comparisons between homogeneous literals.
    (BinEq, IntLit(a), IntLit(b)) => BoolLit(a == b)
    (BinNe, IntLit(a), IntLit(b)) => BoolLit(a != b)
    (BinLt, IntLit(a), IntLit(b)) => BoolLit(a < b)
    (BinLe, IntLit(a), IntLit(b)) => BoolLit(a <= b)
    (BinGt, IntLit(a), IntLit(b)) => BoolLit(a > b)
    (BinGe, IntLit(a), IntLit(b)) => BoolLit(a >= b)
    (BinEq, NumberLit(a), NumberLit(b)) => BoolLit(a == b)
    (BinNe, NumberLit(a), NumberLit(b)) => BoolLit(a != b)
    (BinLt, NumberLit(a), NumberLit(b)) => BoolLit(a < b)
    (BinLe, NumberLit(a), NumberLit(b)) => BoolLit(a <= b)
    (BinGt, NumberLit(a), NumberLit(b)) => BoolLit(a > b)
    (BinGe, NumberLit(a), NumberLit(b)) => BoolLit(a >= b)
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
    | (BinEq, NullLit, BoolLit(_))
    | (BinEq, BoolLit(_), IntLit(_))
    | (BinEq, IntLit(_), BoolLit(_))
    | (BinEq, BoolLit(_), StringLit(_))
    | (BinEq, StringLit(_), BoolLit(_))
    | (BinEq, NumberLit(_), StringLit(_))
    | (BinEq, StringLit(_), NumberLit(_))
    | (BinEq, NumberLit(_), NullLit)
    | (BinEq, NullLit, NumberLit(_))
    | (BinEq, BoolLit(_), NumberLit(_))
    | (BinEq, NumberLit(_), BoolLit(_)) => BoolLit(false)
    (BinNe, StringLit(_), IntLit(_))
    | (BinNe, IntLit(_), StringLit(_))
    | (BinNe, StringLit(_), NullLit)
    | (BinNe, NullLit, StringLit(_))
    | (BinNe, IntLit(_), NullLit)
    | (BinNe, NullLit, IntLit(_))
    | (BinNe, BoolLit(_), NullLit)
    | (BinNe, NullLit, BoolLit(_))
    | (BinNe, BoolLit(_), IntLit(_))
    | (BinNe, IntLit(_), BoolLit(_))
    | (BinNe, BoolLit(_), StringLit(_))
    | (BinNe, StringLit(_), BoolLit(_))
    | (BinNe, NumberLit(_), StringLit(_))
    | (BinNe, StringLit(_), NumberLit(_))
    | (BinNe, NumberLit(_), NullLit)
    | (BinNe, NullLit, NumberLit(_))
    | (BinNe, BoolLit(_), NumberLit(_))
    | (BinNe, NumberLit(_), BoolLit(_)) => BoolLit(true)
    // Abstract-equality comparisons between known-type literals.
    // JS Abstract Equality: same-type → same as strict; null == undefined.
    (AbstractEq, IntLit(a), IntLit(b)) => BoolLit(a == b)
    (AbstractNe, IntLit(a), IntLit(b)) => BoolLit(a != b)
    (AbstractEq, NumberLit(a), NumberLit(b)) => BoolLit(a == b)
    (AbstractNe, NumberLit(a), NumberLit(b)) => BoolLit(a != b)
    (AbstractEq, StringLit(a), StringLit(b)) => BoolLit(a == b)
    (AbstractNe, StringLit(a), StringLit(b)) => BoolLit(a != b)
    (AbstractEq, BoolLit(a), BoolLit(b)) => BoolLit(a == b)
    (AbstractNe, BoolLit(a), BoolLit(b)) => BoolLit(a != b)
    (AbstractEq, NullLit, NullLit) => BoolLit(true)
    (AbstractNe, NullLit, NullLit) => BoolLit(false)
    // `null == undefined` and `undefined == null` → `true`.
    (AbstractEq, NullLit, Var("undefined"))
    | (AbstractEq, Var("undefined"), NullLit)
    | (AbstractEq, NullLit, UnaryOp(@ast.TsUnaryOp::Void, _))
    | (AbstractEq, UnaryOp(@ast.TsUnaryOp::Void, _), NullLit) =>
      if is_pure_value(l) && is_pure_value(r) { BoolLit(true) } else { BinOp(op, l, r) }
    (AbstractNe, NullLit, Var("undefined"))
    | (AbstractNe, Var("undefined"), NullLit)
    | (AbstractNe, NullLit, UnaryOp(@ast.TsUnaryOp::Void, _))
    | (AbstractNe, UnaryOp(@ast.TsUnaryOp::Void, _), NullLit) =>
      if is_pure_value(l) && is_pure_value(r) { BoolLit(false) } else { BinOp(op, l, r) }
    // `null == number/string/bool` → `false` (null only == null or undefined).
    (AbstractEq, NullLit, IntLit(_))
    | (AbstractEq, NullLit, NumberLit(_))
    | (AbstractEq, NullLit, StringLit(_))
    | (AbstractEq, NullLit, BoolLit(_))
    | (AbstractEq, IntLit(_), NullLit)
    | (AbstractEq, NumberLit(_), NullLit)
    | (AbstractEq, StringLit(_), NullLit)
    | (AbstractEq, BoolLit(_), NullLit) => BoolLit(false)
    (AbstractNe, NullLit, IntLit(_))
    | (AbstractNe, NullLit, NumberLit(_))
    | (AbstractNe, NullLit, StringLit(_))
    | (AbstractNe, NullLit, BoolLit(_))
    | (AbstractNe, IntLit(_), NullLit)
    | (AbstractNe, NumberLit(_), NullLit)
    | (AbstractNe, StringLit(_), NullLit)
    | (AbstractNe, BoolLit(_), NullLit) => BoolLit(true)
    // `x === null || x === undefined` → `x == null`
    // Also handles `x === void 0` as the `undefined` form.
    // Only fold when both sides reference the same simple variable.
    (Or, BinOp(BinEq, Var(an), NullLit), BinOp(BinEq, Var(bn), Var("undefined")))
    | (Or, BinOp(BinEq, Var(an), Var("undefined")), BinOp(BinEq, Var(bn), NullLit))
    | (Or, BinOp(BinEq, Var(an), NullLit), BinOp(BinEq, Var(bn), UnaryOp(@ast.TsUnaryOp::Void, _)))
    | (Or, BinOp(BinEq, Var(an), UnaryOp(@ast.TsUnaryOp::Void, _)), BinOp(BinEq, Var(bn), NullLit)) =>
      if an == bn {
        BinOp(AbstractEq, Var(an), NullLit)
      } else {
        BinOp(op, l, r)
      }
    // `x !== null && x !== undefined` → `x != null`
    (And, BinOp(BinNe, Var(an), NullLit), BinOp(BinNe, Var(bn), Var("undefined")))
    | (And, BinOp(BinNe, Var(an), Var("undefined")), BinOp(BinNe, Var(bn), NullLit))
    | (And, BinOp(BinNe, Var(an), NullLit), BinOp(BinNe, Var(bn), UnaryOp(@ast.TsUnaryOp::Void, _)))
    | (And, BinOp(BinNe, Var(an), UnaryOp(@ast.TsUnaryOp::Void, _)), BinOp(BinNe, Var(bn), NullLit)) =>
      if an == bn {
        BinOp(AbstractNe, Var(an), NullLit)
      } else {
        BinOp(op, l, r)
      }
    // Bitwise/shift ops on integer literals
    (BitAnd, IntLit(a), IntLit(b)) => IntLit(a.land(b))
    (BitOr, IntLit(a), IntLit(b)) => IntLit(a.lor(b))
    (BitXor, IntLit(a), IntLit(b)) => IntLit(a.lxor(b))
    (Shl, IntLit(a), IntLit(b)) => IntLit(a.lsl(b))
    (Shr, IntLit(a), IntLit(b)) => IntLit(a.asr(b))
    (UShr, IntLit(a), IntLit(b)) => IntLit(a.lsr(b))
    // `x & 0` → `0` (annihilator). Safe to fold only when the other operand
    // is pure — we can't drop a call with side effects.
    (BitAnd, _, IntLit(0)) if is_pure_value(l) => IntLit(0)
    (BitAnd, IntLit(0), _) if is_pure_value(r) => IntLit(0)
    // `x & -1` → `x` (AND with all-bits-set is identity, since -1 = 0xFFFFFFFF in 32-bit).
    (BitAnd, _, IntLit(-1)) => l
    (BitAnd, IntLit(-1), _) if is_pure_value(l) => r
    // `x | -1` → `-1` (OR with all-bits-set is annihilator).
    (BitOr, _, IntLit(-1)) if is_pure_value(l) => IntLit(-1)
    (BitOr, IntLit(-1), _) if is_pure_value(r) => IntLit(-1)
    // `x ** 0` → `1` for any pure x (JS spec: every value including NaN
    // and Infinity raised to the 0 power equals 1).
    (Pow, _, IntLit(0)) | (Pow, _, NumberLit(0.0)) =>
      if is_pure_value(l) { IntLit(1) } else { BinOp(op, l, r) }
    // `"key" in {key: v, ...}` → true/false when all values are pure.
    // Safe because object literals never have __proto__ side effects.
    (In, StringLit(k), ObjectLit(entries)) => {
      let mut all_pure = true
      for ent in entries {
        if not(is_pure_value(ent.1)) {
          all_pure = false
          break
        }
      }
      if all_pure {
        let mut found = false
        for ent in entries {
          if ent.0 == k {
            found = true
            break
          }
        }
        BoolLit(found)
      } else {
        BinOp(op, l, r)
      }
    }
    // Primitive values are never `instanceof` any constructor.
    // `null instanceof X`, `42 instanceof X`, `"s" instanceof X` → `false`.
    // Only safe when the rhs is pure (no side effects from evaluating X).
    (Instanceof, NullLit, _)
    | (Instanceof, IntLit(_), _)
    | (Instanceof, NumberLit(_), _)
    | (Instanceof, StringLit(_), _)
    | (Instanceof, BoolLit(_), _)
    | (Instanceof, UnaryOp(@ast.TsUnaryOp::Void, _), _)
    | (Instanceof, Var("undefined"), _) =>
      if is_pure_value(r) { BoolLit(false) } else { BinOp(op, l, r) }
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
/// Returns `true` when the expression is the JS `undefined` value or
/// `void 0`. Used to detect the else-branch of optional-chain lowering.
fn is_nullish_or_void(expr : @ast.TsExpr) -> Bool {
  match expr {
    NullLit => true
    Var("undefined") => true
    UnaryOp(@ast.TsUnaryOp::Void, _) => true
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

///|
/// Map a comparison operator to its logical negation.
/// Format a non-negative integer as a string in the given radix (2–36).
/// Produces lowercase digits for bases > 10, matching JS `toString(radix)`.
fn format_int_radix(n : Int, radix : Int) -> String {
  if n == 0 {
    return "0"
  }
  let digits = "0123456789abcdefghijklmnopqrstuvwxyz"
  let buf : Array[Char] = []
  let mut m = n
  while m > 0 {
    buf.push(digits[m % radix])
    m = m / radix
  }
  let sb = StringBuilder::new()
  for i = buf.length() - 1; i >= 0; i = i - 1 {
    sb.write_char(buf[i])
  }
  sb.to_string()
}

///|
/// `!(a op b)` → `a negate_op b` (saves 2 bytes).
/// Parse `s` as an integer in the given radix (2–36).
/// Returns `None` on parse error or overflow.
fn parse_int_radix(s : String, radix : Int) -> Int? {
  if s.length() == 0 {
    return None
  }
  let mut i = 0
  let mut neg = false
  if s[0] == '-' {
    neg = true
    i = 1
  } else if s[0] == '+' {
    i = 1
  }
  if i >= s.length() {
    return None
  }
  let mut result : Int64 = 0L
  let r = radix.to_int64()
  while i < s.length() {
    let c = s[i]
    let digit = if c >= '0' && c <= '9' {
      c.to_int() - '0'.to_int()
    } else if c >= 'a' && c <= 'z' {
      c.to_int() - 'a'.to_int() + 10
    } else if c >= 'A' && c <= 'Z' {
      c.to_int() - 'A'.to_int() + 10
    } else {
      return None
    }
    if digit >= radix {
      return None
    }
    result = result * r + digit.to_int64()
    // Guard against overflow into MoonBit Int range.
    if result > 2147483647L || result < -2147483648L {
      return None
    }
    i = i + 1
  }
  if neg {
    result = -result
  }
  Some(result.to_int())
}

///|
fn negate_comparison_op(op : @ast.TsBinOp) -> @ast.TsBinOp? {
  match op {
    BinEq => Some(BinNe)
    BinNe => Some(BinEq)
    BinLt => Some(BinGe)
    BinLe => Some(BinGt)
    BinGt => Some(BinLe)
    BinGe => Some(BinLt)
    _ => None
  }
}

///|
/// Returns true for operators that always produce a boolean result.
/// Used to simplify `!!(comparison)` → `comparison`.
fn is_comparison_op(op : @ast.TsBinOp) -> Bool {
  match op {
    BinEq | BinNe | BinLt | BinLe | BinGt | BinGe => true
    AbstractEq | AbstractNe => true
    Instanceof | In => true
    _ => false
  }
}

// Substitute free occurrences of variable names in `expr` with the
// corresponding values from `subs`. Does NOT descend into nested
// function bodies (arrow / function expressions) to avoid capturing.
fn substitute_vars_in_expr(
  expr : @ast.TsExpr,
  subs : Map[String, @ast.TsExpr]
) -> @ast.TsExpr {
  fn sub(e : @ast.TsExpr) -> @ast.TsExpr {
    match e {
      Var(name) =>
        match subs[name] {
          Some(v) => v
          None => e
        }
      // Do not descend into new binding scopes.
      ArrowFunc(_, _, _, _) | FuncExpr(_) => e
      // Recurse into everything else.
      UnaryOp(op, a) => UnaryOp(op, sub(a))
      BinOp(op, a, b) => BinOp(op, sub(a), sub(b))
      Cond(c, t, f) => Cond(sub(c), sub(t), sub(f))
      AssignExpr(name, rhs) => AssignExpr(name, sub(rhs))
      CompoundAssignExpr(lhs, op, rhs) =>
        CompoundAssignExpr(sub(lhs), op, sub(rhs))
      PropAssignExpr(obj, prop, rhs) => PropAssignExpr(sub(obj), prop, sub(rhs))
      IndexAssignExpr(obj, idx, rhs) =>
        IndexAssignExpr(sub(obj), sub(idx), sub(rhs))
      Call(name, args) => {
        let new_args : Array[@ast.TsExpr] = []
        for a in args {
          new_args.push(sub(a))
        }
        Call(name, new_args)
      }
      CallExpr(callee, args) => {
        let new_args : Array[@ast.TsExpr] = []
        for a in args {
          new_args.push(sub(a))
        }
        CallExpr(sub(callee), new_args)
      }
      MethodCall(recv, m, args) => {
        let new_args : Array[@ast.TsExpr] = []
        for a in args {
          new_args.push(sub(a))
        }
        MethodCall(sub(recv), m, new_args)
      }
      New(name, args) => {
        let new_args : Array[@ast.TsExpr] = []
        for a in args {
          new_args.push(sub(a))
        }
        New(name, new_args)
      }
      NewExpr(callee, args) => {
        let new_args : Array[@ast.TsExpr] = []
        for a in args {
          new_args.push(sub(a))
        }
        NewExpr(sub(callee), new_args)
      }
      PropAccess(obj, prop) => PropAccess(sub(obj), prop)
      IndexAccess(obj, idx) => IndexAccess(sub(obj), sub(idx))
      ComputedProp(key, val) => ComputedProp(sub(key), sub(val))
      ArrayLit(items) => {
        let new_items : Array[@ast.TsExpr] = []
        for item in items {
          new_items.push(sub(item))
        }
        ArrayLit(new_items)
      }
      ObjectLit(pairs) => {
        let new_pairs : Array[(String, @ast.TsExpr)] = []
        for pair in pairs {
          new_pairs.push((pair.0, sub(pair.1)))
        }
        ObjectLit(new_pairs)
      }
      Spread(inner) => Spread(sub(inner))
      Await(inner) => Await(sub(inner))
      Yield(inner) =>
        match inner {
          Some(v) => Yield(Some(sub(v)))
          None => e
        }
      YieldStar(inner) => YieldStar(sub(inner))
      Seq(a, b) => Seq(sub(a), sub(b))
      PureCall(inner) => PureCall(sub(inner))
      As(inner, t) => As(sub(inner), t)
      TaggedTemplate(tag, cooked, raw, exprs) => {
        let new_exprs : Array[@ast.TsExpr] = []
        for ex in exprs {
          new_exprs.push(sub(ex))
        }
        TaggedTemplate(sub(tag), cooked, raw, new_exprs)
      }
      TemplateLiteral(strings, exprs) => {
        let new_exprs : Array[@ast.TsExpr] = []
        for ex in exprs {
          new_exprs.push(sub(ex))
        }
        TemplateLiteral(strings, new_exprs)
      }
      DynamicImport(spec, opts) =>
        DynamicImport(
          sub(spec),
          match opts {
            Some(o) => Some(sub(o))
            None => None
          },
        )
      // Literals and other leaves need no substitution.
      _ => e
    }
  }

  sub(expr)
}
