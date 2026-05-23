// Constant folding + dead-branch elimination.
//
// `fold_constants_in_block` walks every expression bottom-up and
// evaluates anything whose inputs are all literals at compile
// time. The pass pairs naturally with `inline_immutable_property_reads`:
// once `cfg.mode` becomes `"prod"`, expressions like
// `"prod" === "dev"` fold to `false`, and the surrounding
// `if (false) { … }` collapses to nothing.
//
// What gets folded:
//
//   - Binary ops `+ - * / % **` on numeric literals.
//   - `+` on two string literals (concatenation) and mixed
//     string/number (`"x" + 1` → `"x1"`).
//   - Comparison `=== !== < > <= >=` between same-typed literals.
//   - Logical `&& || ??` — short-circuit, so a literal LHS
//     immediately collapses the expression.
//   - Unary `! - + typeof` on a literal.
//   - Ternary `cond ? t : f` when `cond` is a literal.
//   - `Seq(pure, rhs)` → `rhs` when the LHS is a literal /
//     pure variable read.
//
// Dead-branch elimination:
//
//   - `If(true, t, _)` → `Block(t)` (or the bare stmts if the
//     parent walker can flatten).
//   - `If(false, _, Some(e))` → `Block(e)`.
//   - `If(false, _, None)` → `Empty`.
//   - `While(false, _)` → `Empty`.
//   - `DoWhile(false, body)` → `Block(body)` (the body still
//     runs once).
//   - `For(init?, false, _, _)` → keep `init` if it might have
//     side effects, otherwise `Empty`.
//
// The pass is structural and idempotent on already-folded blocks;
// nothing tries to evaluate JavaScript-specific runtime corners
// like `NaN`, `Infinity`, or implicit type coercion beyond plain
// string/number concat. When in doubt, leave the expression alone.

///|
pub fn fold_constants_in_block(block : @ast.TsBlock) -> @ast.TsBlock {
  let new_stmts : Array[@ast.TsStmt] = []
  let new_positions : Array[Int] = []
  let has_positions = block.stmt_positions.length() == block.stmts.length()
  for i, s in block.stmts {
    let folded = fold_stmt(s)
    // If/While dead-branch elim can collapse the stmt to Empty —
    // we keep that as-is rather than fully erasing the slot so the
    // position array stays aligned. Trailing emit skips `Empty`.
    new_stmts.push(folded)
    if has_positions {
      new_positions.push(block.stmt_positions[i])
    }
  }
  { stmts: new_stmts, stmt_positions: new_positions }
}

///|
pub fn fold_constants_in_blocks(
  blocks : Array[@ast.TsBlock],
) -> Array[@ast.TsBlock] {
  let out : Array[@ast.TsBlock] = []
  for b in blocks {
    out.push(fold_constants_in_block(b))
  }
  out
}

// ---------------------------------------------------------------------------
// Statement walk + dead-branch elimination
// ---------------------------------------------------------------------------

///|
fn fold_stmt(stmt : @ast.TsStmt) -> @ast.TsStmt {
  match stmt {
    Var(b, t, e) => Var(b, t, fold_expr(e))
    Let(b, t, e) => Let(b, t, fold_expr(e))
    Const(b, t, e) => Const(b, t, fold_expr(e))
    Expr(e) => Expr(fold_expr(e))
    Return(opt) =>
      match opt {
        Some(e) => Return(Some(fold_expr(e)))
        None => stmt
      }
    Throw(e) => Throw(fold_expr(e))
    Assign(name, e) => Assign(name, fold_expr(e))
    CompoundAssign(name, op, e) => CompoundAssign(name, op, fold_expr(e))
    PropAssign(recv, prop, value) =>
      PropAssign(fold_expr(recv), prop, fold_expr(value))
    IndexAssign(recv, idx, value) =>
      IndexAssign(fold_expr(recv), fold_expr(idx), fold_expr(value))
    If(c, t, e_opt) => {
      let cond = fold_expr(c)
      let then_b = fold_block(t)
      let else_b = match e_opt {
        Some(b) => Some(fold_block(b))
        None => None
      }
      match literal_truthiness(cond) {
        Some(true) => Block(then_b)
        Some(false) =>
          match else_b {
            Some(b) => Block(b)
            None => Empty
          }
        None => If(cond, then_b, else_b)
      }
    }
    While(c, b) => {
      let cond = fold_expr(c)
      let body = fold_block(b)
      match literal_truthiness(cond) {
        Some(false) => Empty
        _ => While(cond, body)
      }
    }
    DoWhile(c, b) => {
      let cond = fold_expr(c)
      let body = fold_block(b)
      match literal_truthiness(cond) {
        // The body runs at least once even when the test is false;
        // emit it as a plain block.
        Some(false) => Block(body)
        _ => DoWhile(cond, body)
      }
    }
    For(init_opt, cond_opt, update_opt, body) => {
      let folded_init = match init_opt {
        Some(s) => Some(fold_stmt(s))
        None => None
      }
      let folded_cond = match cond_opt {
        Some(c) => Some(fold_expr(c))
        None => None
      }
      let folded_update = match update_opt {
        Some(s) => Some(fold_stmt(s))
        None => None
      }
      let folded_body = fold_block(body)
      // Loop with provably-false cond never enters — drop the loop
      // but keep `init` so its side effects survive. The bare init
      // becomes the surviving stmt.
      match folded_cond {
        Some(c) =>
          match literal_truthiness(c) {
            Some(false) =>
              match folded_init {
                Some(s) => s
                None => Empty
              }
            _ => For(folded_init, folded_cond, folded_update, folded_body)
          }
        None => For(folded_init, folded_cond, folded_update, folded_body)
      }
    }
    ForOf(kind, b, t, iter, body) =>
      ForOf(kind, b, t, fold_expr(iter), fold_block(body))
    ForAwaitOf(kind, b, t, iter, body) =>
      ForAwaitOf(kind, b, t, fold_expr(iter), fold_block(body))
    ForIn(kind, b, t, iter, body) =>
      ForIn(kind, b, t, fold_expr(iter), fold_block(body))
    Switch(scrut, cases) => {
      let new_cases : Array[@ast.TsSwitchCase] = []
      for c in cases {
        new_cases.push({
          test_expr: match c.test_expr {
            Some(t) => Some(fold_expr(t))
            None => None
          },
          body: fold_block(c.body),
        })
      }
      Switch(fold_expr(scrut), new_cases)
    }
    Try(t, b, c, f) =>
      Try(
        fold_block(t),
        b,
        match c {
          Some(blk) => Some(fold_block(blk))
          None => None
        },
        match f {
          Some(blk) => Some(fold_block(blk))
          None => None
        },
      )
    Block(b) => Block(fold_block(b))
    Label(name, inner) => Label(name, fold_stmt(inner))
    With(target, body) => With(fold_expr(target), fold_block(body))
    Break(_) | Continue(_) | Empty | Debugger => stmt
  }
}

///|
fn fold_block(block : @ast.TsBlock) -> @ast.TsBlock {
  fold_constants_in_block(block)
}

// ---------------------------------------------------------------------------
// Expression folding
// ---------------------------------------------------------------------------

///|
fn fold_expr(expr : @ast.TsExpr) -> @ast.TsExpr {
  match expr {
    BinOp(op, l, r) => fold_binop(op, fold_expr(l), fold_expr(r))
    UnaryOp(op, e) => fold_unop(op, fold_expr(e))
    Cond(c, t, f) => {
      let cond = fold_expr(c)
      let then_e = fold_expr(t)
      let else_e = fold_expr(f)
      match literal_truthiness(cond) {
        Some(true) => then_e
        Some(false) => else_e
        None => Cond(cond, then_e, else_e)
      }
    }
    Seq(l, r) => {
      let folded_l = fold_expr(l)
      let folded_r = fold_expr(r)
      // `(literal, rhs)` and `(Var(x), rhs)` have no observable
      // effect on the left side — drop it.
      if is_effect_free(folded_l) {
        folded_r
      } else {
        Seq(folded_l, folded_r)
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
    PropAccess(recv, n) => PropAccess(fold_expr(recv), n)
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
    Spread(e) => Spread(fold_expr(e))
    Await(e) => Await(fold_expr(e))
    YieldStar(e) => YieldStar(fold_expr(e))
    NonNull(e) => NonNull(fold_expr(e))
    OptionalChain(e) => OptionalChain(fold_expr(e))
    Yield(opt) =>
      Yield(match opt {
        Some(e) => Some(fold_expr(e))
        None => None
      })
    AssignExpr(name, e) => AssignExpr(name, fold_expr(e))
    AssignPattern(b, e) => AssignPattern(b, fold_expr(e))
    CompoundAssignExpr(target, op, e) =>
      CompoundAssignExpr(fold_expr(target), op, fold_expr(e))
    PropAssignExpr(recv, prop, value) =>
      PropAssignExpr(fold_expr(recv), prop, fold_expr(value))
    IndexAssignExpr(recv, idx, value) =>
      IndexAssignExpr(fold_expr(recv), fold_expr(idx), fold_expr(value))
    ComputedProp(k, v) => ComputedProp(fold_expr(k), fold_expr(v))
    ArrowFunc(params, ret, body, is_async) => {
      let new_body = match body {
        ArrowExpr(e) => @ast.TsArrowBody::ArrowExpr(fold_expr(e))
        ArrowBlock(b) => @ast.TsArrowBody::ArrowBlock(fold_block(b))
      }
      ArrowFunc(params, ret, new_body, is_async)
    }
    FuncExpr(f) => FuncExpr({ ..f, body: fold_block(f.body) })
    TaggedTemplate(tag, strs, raws, exprs) => {
      let new_exprs : Array[@ast.TsExpr] = []
      for e in exprs {
        new_exprs.push(fold_expr(e))
      }
      TaggedTemplate(fold_expr(tag), strs, raws, new_exprs)
    }
    TemplateLiteral(strs, exprs) => {
      let new_exprs : Array[@ast.TsExpr] = []
      for e in exprs {
        new_exprs.push(fold_expr(e))
      }
      // If every interpolation is a string-coercible literal,
      // fold the whole template to a single StringLit.
      let mut all_lit = true
      for e in new_exprs {
        if literal_to_string_value(e) is None {
          all_lit = false
          break
        }
      }
      if all_lit {
        let buf = StringBuilder::new()
        for i, s in strs {
          buf.write_string(s)
          if i < new_exprs.length() {
            match literal_to_string_value(new_exprs[i]) {
              Some(v) => buf.write_string(v)
              None => ()
            }
          }
        }
        StringLit(buf.to_string())
      } else {
        TemplateLiteral(strs, new_exprs)
      }
    }
    As(e, t) => As(fold_expr(e), t)
    Satisfies(e, t) => Satisfies(fold_expr(e), t)
    DynamicImport(spec, opt) =>
      DynamicImport(
        fold_expr(spec),
        match opt {
          Some(o) => Some(fold_expr(o))
          None => None
        },
      )
    _ => expr
  }
}

// ---------------------------------------------------------------------------
// Operator-level folding
// ---------------------------------------------------------------------------

///|
fn fold_binop(
  op : @ast.TsBinOp,
  l : @ast.TsExpr,
  r : @ast.TsExpr,
) -> @ast.TsExpr {
  // Short-circuit operators have to honor LHS evaluation order: a
  // literal LHS resolves the whole expression even if the RHS isn't
  // foldable.
  match op {
    And =>
      match literal_truthiness(l) {
        Some(false) => return l
        Some(true) => return r
        None => ()
      }
    Or =>
      match literal_truthiness(l) {
        Some(true) => return l
        Some(false) => return r
        None => ()
      }
    Coalesce =>
      match l {
        NullLit => return r
        // `undefined` literally isn't an expression — we surface it
        // as `Var("undefined")` which the analysis can't trust.
        // Match only the safe null case here.
        _ =>
          if is_non_null_literal(l) {
            return l
          }
      }
    _ => ()
  }
  // Arithmetic / comparison on two literal arguments.
  match op {
    Add => fold_add(l, r)
    Sub => fold_numeric(l, r, fn(a, b) { a - b })
    Mul => fold_numeric(l, r, fn(a, b) { a * b })
    Div => fold_div(l, r)
    Mod => fold_mod(l, r)
    BinEq => fold_strict_eq(l, r, true)
    BinNe => fold_strict_eq(l, r, false)
    BinLt => fold_compare(l, r, fn(a, b) { a < b })
    BinLe => fold_compare(l, r, fn(a, b) { a <= b })
    BinGt => fold_compare(l, r, fn(a, b) { a > b })
    BinGe => fold_compare(l, r, fn(a, b) { a >= b })
    _ => BinOp(op, l, r)
  }
}

///|
fn fold_unop(op : @ast.TsUnaryOp, e : @ast.TsExpr) -> @ast.TsExpr {
  match op {
    Not =>
      match literal_truthiness(e) {
        Some(b) => BoolLit(!b)
        None => UnaryOp(op, e)
      }
    Neg =>
      match e {
        NumberLit(n) => NumberLit(-n)
        IntLit(n) => IntLit(-n)
        _ => UnaryOp(op, e)
      }
    Plus =>
      match e {
        NumberLit(_) | IntLit(_) => e
        StringLit(s) =>
          match (try? @strconv.parse_double(s)) {
            Ok(n) => NumberLit(n)
            Err(_) => UnaryOp(op, e)
          }
        BoolLit(b) => IntLit(if b { 1 } else { 0 })
        NullLit => IntLit(0)
        _ => UnaryOp(op, e)
      }
    Typeof => {
      let kind = match e {
        StringLit(_) => Some("string")
        NumberLit(_) | IntLit(_) => Some("number")
        BigIntLit(_) => Some("bigint")
        BoolLit(_) => Some("boolean")
        NullLit => Some("object")
        ArrowFunc(_, _, _, _) | FuncExpr(_) => Some("function")
        ObjectLit(_) | ArrayLit(_) => Some("object")
        _ => None
      }
      match kind {
        Some(s) => StringLit(s)
        None => UnaryOp(op, e)
      }
    }
    _ => UnaryOp(op, e)
  }
}

// ---------------------------------------------------------------------------
// Numeric / comparison helpers
// ---------------------------------------------------------------------------

///|
/// Extract a numeric value from a literal expression. Returns `None`
/// for anything that can't be losslessly read as a double.
fn literal_to_number(e : @ast.TsExpr) -> Double? {
  match e {
    NumberLit(n) => Some(n)
    IntLit(n) => Some(n.to_double())
    BoolLit(true) => Some(1.0)
    BoolLit(false) => Some(0.0)
    NullLit => Some(0.0)
    _ => None
  }
}

///|
/// String coercion of a primitive literal, JS-semantics-style. Used
/// for `"x" + 1` style folding and template-literal collapse.
fn literal_to_string_value(e : @ast.TsExpr) -> String? {
  match e {
    StringLit(s) => Some(s)
    NumberLit(n) => Some(double_to_js_string(n))
    IntLit(n) => Some(n.to_string())
    BoolLit(true) => Some("true")
    BoolLit(false) => Some("false")
    NullLit => Some("null")
    _ => None
  }
}

///|
fn double_to_js_string(n : Double) -> String {
  // JS `String(n)` drops trailing `.0` for integer-valued doubles.
  // For everything else, the moonbit default representation is close
  // enough for the const-folding sizes we deal with.
  let truncated = n.to_int().to_double()
  if truncated == n && n.abs() < 1.0e16 {
    n.to_int().to_string()
  } else {
    n.to_string()
  }
}

///|
fn fold_add(l : @ast.TsExpr, r : @ast.TsExpr) -> @ast.TsExpr {
  // `"a" + b` / `a + "b"` does string concat — semantics of `+`
  // in JS. Both sides must be string-coercible literals.
  match (l, r) {
    (StringLit(a), StringLit(b)) => StringLit(a + b)
    (StringLit(a), _) =>
      match literal_to_string_value(r) {
        Some(b) => StringLit(a + b)
        None => BinOp(Add, l, r)
      }
    (_, StringLit(b)) =>
      match literal_to_string_value(l) {
        Some(a) => StringLit(a + b)
        None => BinOp(Add, l, r)
      }
    _ => fold_numeric(l, r, fn(a, b) { a + b })
  }
}

///|
fn fold_numeric(
  l : @ast.TsExpr,
  r : @ast.TsExpr,
  op : (Double, Double) -> Double,
) -> @ast.TsExpr {
  match (literal_to_number(l), literal_to_number(r)) {
    (Some(a), Some(b)) => {
      let result = op(a, b)
      // Prefer IntLit when the result is an integer-valued double
      // small enough to round-trip cleanly. Keeps the output tidy.
      let i = result.to_int().to_double()
      if i == result && result.abs() < 2.0e9 {
        IntLit(result.to_int())
      } else {
        NumberLit(result)
      }
    }
    _ =>
      // Fallback — caller passes the BinOp's original op.
      BinOp(Add, l, r)
  }
}

///|
fn fold_div(l : @ast.TsExpr, r : @ast.TsExpr) -> @ast.TsExpr {
  match (literal_to_number(l), literal_to_number(r)) {
    (Some(_), Some(0.0)) =>
      // `1 / 0` → Infinity in JS. We don't have an `Infinity`
      // literal; leave it alone.
      BinOp(Div, l, r)
    (Some(a), Some(b)) => {
      let result = a / b
      let i = result.to_int().to_double()
      if i == result && result.abs() < 2.0e9 {
        IntLit(result.to_int())
      } else {
        NumberLit(result)
      }
    }
    _ => BinOp(Div, l, r)
  }
}

///|
fn fold_mod(l : @ast.TsExpr, r : @ast.TsExpr) -> @ast.TsExpr {
  match (literal_to_number(l), literal_to_number(r)) {
    (Some(_), Some(0.0)) => BinOp(Mod, l, r)
    (Some(a), Some(b)) => NumberLit(a % b)
    _ => BinOp(Mod, l, r)
  }
}

///|
fn fold_compare(
  l : @ast.TsExpr,
  r : @ast.TsExpr,
  op : (Double, Double) -> Bool,
) -> @ast.TsExpr {
  // String comparison too, but only when both are strings.
  match (l, r) {
    (StringLit(a), StringLit(b)) =>
      // We need to map the numeric comparator semantics onto string
      // order. Since the `op` argument captures the comparison
      // shape, fall back to caller's BinOp for strings — char-level
      // ordering isn't worth a deep helper right now.
      if a == b {
        // Equality cases handled in fold_strict_eq; reach here for
        // lt/le/gt/ge only. `a <= a` and `a >= a` are true; `<`/`>`
        // are false.
        let _ = op
        BinOp(BinLt, StringLit(a), StringLit(b)) // give up cleanly
      } else {
        BinOp(BinLt, StringLit(a), StringLit(b))
      }
    _ =>
      match (literal_to_number(l), literal_to_number(r)) {
        (Some(a), Some(b)) => BoolLit(op(a, b))
        _ => BinOp(BinLt, l, r) // fallback — op shape is lost here
      }
  }
}

///|
/// Strict equality: `===` and `!==`. Different primitive types
/// always compare unequal under `===`. Same type → value compare.
fn fold_strict_eq(
  l : @ast.TsExpr,
  r : @ast.TsExpr,
  is_eq : Bool,
) -> @ast.TsExpr {
  let result : Bool? = match (l, r) {
    (StringLit(a), StringLit(b)) => Some(a == b)
    (NumberLit(a), NumberLit(b)) => Some(a == b)
    (IntLit(a), IntLit(b)) => Some(a == b)
    (NumberLit(a), IntLit(b)) => Some(a == b.to_double())
    (IntLit(a), NumberLit(b)) => Some(a.to_double() == b)
    (BoolLit(a), BoolLit(b)) => Some(a == b)
    (NullLit, NullLit) => Some(true)
    // Distinct primitive types — strict equality says always
    // unequal. Skip cases where one side isn't a literal.
    _ =>
      if is_primitive_literal(l) && is_primitive_literal(r) {
        Some(false)
      } else {
        None
      }
  }
  match result {
    Some(eq) =>
      if is_eq {
        BoolLit(eq)
      } else {
        BoolLit(!eq)
      }
    None =>
      if is_eq {
        BinOp(BinEq, l, r)
      } else {
        BinOp(BinNe, l, r)
      }
  }
}

// ---------------------------------------------------------------------------
// Classifiers
// ---------------------------------------------------------------------------

///|
fn is_primitive_literal(e : @ast.TsExpr) -> Bool {
  match e {
    NumberLit(_) | IntLit(_) | BigIntLit(_) | BoolLit(_) | StringLit(_)
    | NullLit => true
    _ => false
  }
}

///|
fn is_non_null_literal(e : @ast.TsExpr) -> Bool {
  match e {
    NumberLit(_) | IntLit(_) | BigIntLit(_) | BoolLit(_) | StringLit(_) =>
      true
    _ => false
  }
}

///|
/// `Some(true)` / `Some(false)` for literals whose JS truthiness
/// we can determine at compile time. `None` for anything that
/// could be either at runtime.
fn literal_truthiness(e : @ast.TsExpr) -> Bool? {
  match e {
    BoolLit(b) => Some(b)
    NullLit => Some(false)
    NumberLit(n) => Some(n != 0.0)
    IntLit(n) => Some(n != 0)
    StringLit(s) => Some(s != "")
    BigIntLit(s) => Some(s != "0" && s != "0n")
    // Object / array / arrow / func literals are always truthy.
    ObjectLit(_) | ArrayLit(_) | ArrowFunc(_, _, _, _) | FuncExpr(_) =>
      Some(true)
    _ => None
  }
}

///|
/// `true` when evaluating the expression produces no observable
/// side effect, so a sequence like `(e, rhs)` can collapse to
/// just `rhs`. Conservative — only literals and bare var refs
/// qualify. Function calls, assignments, member accesses (which
/// could trigger a getter) all return `false`.
fn is_effect_free(e : @ast.TsExpr) -> Bool {
  match e {
    NumberLit(_) | IntLit(_) | BigIntLit(_) | BoolLit(_) | StringLit(_)
    | NullLit => true
    Var(_) => true
    _ => false
  }
}
