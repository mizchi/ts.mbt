// Type-driven constant folding.
//
// Looks for two specific patterns where TS type annotations let
// us decide a runtime check at compile time:
//
//   typeof x === "type" / typeof x !== "type"
//   x === null / x !== null  (and `=== undefined` / `!== undefined`)
//
// When `x` has a static, single-primitive type annotation in
// scope (a `let x: number`, a function parameter `x: string`,
// etc.), the result is statically `true` / `false` and the
// surrounding fold pass folds it further.
//
// Scope tracking is intentionally simple: we maintain a
// `Map[String, TsType]` that grows as we enter function /
// arrow bodies (for parameters) and Let / Const / Var
// declarations. We do NOT do narrowing across `if (typeof x ===
// "string")` branches — that's full flow-sensitive analysis and
// out of scope for this pass.

///|
pub fn type_fold_block(block : @ast.TsBlock) -> @ast.TsBlock {
  let scope : Map[String, @ast.TsType] = {}
  type_fold_block_in(block, scope)
}

///|
fn type_fold_block_in(
  block : @ast.TsBlock,
  scope : Map[String, @ast.TsType],
) -> @ast.TsBlock {
  // Each block introduces a fresh layer — we just copy-extend
  // the parent scope so we don't pollute siblings.
  let local : Map[String, @ast.TsType] = {}
  for entry in scope {
    let (k, v) = entry
    local[k] = v
  }
  let stmts : Array[@ast.TsStmt] = []
  for s in block.stmts {
    stmts.push(type_fold_stmt(s, local))
  }
  { stmts, stmt_positions: [] }
}

///|
fn type_fold_stmt(
  stmt : @ast.TsStmt,
  scope : Map[String, @ast.TsType],
) -> @ast.TsStmt {
  match stmt {
    Var(b, t, e) | Let(b, t, e) | Const(b, t, e) => {
      let new_init = type_fold_expr(e, scope)
      // Record the binding's type if it's a simple identifier
      // and the annotation is one we can reason about.
      match b {
        @ast.TsBinding::Ident(name) =>
          if is_useful_type(t) {
            scope[name] = t
          }
        _ => ()
      }
      match stmt {
        Var(_, _, _) => Var(b, t, new_init)
        Let(_, _, _) => Let(b, t, new_init)
        Const(_, _, _) => Const(b, t, new_init)
        _ => stmt
      }
    }
    Assign(n, e) => Assign(n, type_fold_expr(e, scope))
    CompoundAssign(n, op, e) =>
      CompoundAssign(n, op, type_fold_expr(e, scope))
    IndexAssign(t, idx, v) =>
      IndexAssign(
        type_fold_expr(t, scope),
        type_fold_expr(idx, scope),
        type_fold_expr(v, scope),
      )
    PropAssign(t, p, v) =>
      PropAssign(type_fold_expr(t, scope), p, type_fold_expr(v, scope))
    Expr(e) => Expr(type_fold_expr(e, scope))
    Return(Some(e)) => Return(Some(type_fold_expr(e, scope)))
    Return(None) | Empty | Debugger | Break(_) | Continue(_) => stmt
    Throw(e) => Throw(type_fold_expr(e, scope))
    If(c, t, e) =>
      If(
        type_fold_expr(c, scope),
        type_fold_block_in(t, scope),
        match e {
          Some(b) => Some(type_fold_block_in(b, scope))
          None => None
        },
      )
    While(c, body) =>
      While(type_fold_expr(c, scope), type_fold_block_in(body, scope))
    DoWhile(c, body) =>
      DoWhile(type_fold_expr(c, scope), type_fold_block_in(body, scope))
    With(c, body) =>
      With(type_fold_expr(c, scope), type_fold_block_in(body, scope))
    For(init, cond, update, body) =>
      For(
        match init {
          Some(s) => Some(type_fold_stmt(s, scope))
          None => None
        },
        match cond {
          Some(e) => Some(type_fold_expr(e, scope))
          None => None
        },
        match update {
          Some(s) => Some(type_fold_stmt(s, scope))
          None => None
        },
        type_fold_block_in(body, scope),
      )
    ForOf(k, b, t, iter, body) =>
      ForOf(k, b, t, type_fold_expr(iter, scope), type_fold_block_in(body, scope))
    ForAwaitOf(k, b, t, iter, body) =>
      ForAwaitOf(
        k, b, t, type_fold_expr(iter, scope), type_fold_block_in(body, scope),
      )
    ForIn(k, b, t, iter, body) =>
      ForIn(k, b, t, type_fold_expr(iter, scope), type_fold_block_in(body, scope))
    Switch(e, cases) => {
      let new_cases : Array[@ast.TsSwitchCase] = []
      for c in cases {
        new_cases.push({
          test_expr: match c.test_expr {
            Some(te) => Some(type_fold_expr(te, scope))
            None => None
          },
          body: type_fold_block_in(c.body, scope),
        })
      }
      Switch(type_fold_expr(e, scope), new_cases)
    }
    Try(b, bnd, cb, fb) =>
      Try(
        type_fold_block_in(b, scope),
        bnd,
        match cb {
          Some(blk) => Some(type_fold_block_in(blk, scope))
          None => None
        },
        match fb {
          Some(blk) => Some(type_fold_block_in(blk, scope))
          None => None
        },
      )
    Label(name, inner) => Label(name, type_fold_stmt(inner, scope))
    Block(b) => Block(type_fold_block_in(b, scope))
    NativeClassStmt(_, _) => stmt
  }
}

///|
fn type_fold_expr(
  expr : @ast.TsExpr,
  scope : Map[String, @ast.TsType],
) -> @ast.TsExpr {
  match expr {
    // typeof X === "literal" / typeof X !== "literal"
    BinOp(op, UnaryOp(Typeof, Var(x_name)), StringLit(ty_lit)) =>
      match try_typeof_fold(op, x_name, ty_lit, scope) {
        Some(b) => BoolLit(b)
        None => expr
      }
    BinOp(op, StringLit(ty_lit), UnaryOp(Typeof, Var(x_name))) =>
      match try_typeof_fold(op, x_name, ty_lit, scope) {
        Some(b) => BoolLit(b)
        None => expr
      }
    // x === null / x !== null / x === undefined / x !== undefined
    BinOp(op, Var(x_name), NullLit) =>
      match try_null_check_fold(op, x_name, "null", scope) {
        Some(b) => BoolLit(b)
        None => expr
      }
    BinOp(op, NullLit, Var(x_name)) =>
      match try_null_check_fold(op, x_name, "null", scope) {
        Some(b) => BoolLit(b)
        None => expr
      }
    BinOp(op, Var(x_name), Var("undefined")) =>
      match try_null_check_fold(op, x_name, "undefined", scope) {
        Some(b) => BoolLit(b)
        None => expr
      }
    BinOp(op, Var("undefined"), Var(x_name)) =>
      match try_null_check_fold(op, x_name, "undefined", scope) {
        Some(b) => BoolLit(b)
        None => expr
      }
    BinOp(op, l, r) =>
      BinOp(op, type_fold_expr(l, scope), type_fold_expr(r, scope))
    UnaryOp(op, inner) => UnaryOp(op, type_fold_expr(inner, scope))
    Cond(c, t, e) =>
      Cond(
        type_fold_expr(c, scope),
        type_fold_expr(t, scope),
        type_fold_expr(e, scope),
      )
    Call(n, args) => {
      let new_args : Array[@ast.TsExpr] = []
      for a in args {
        new_args.push(type_fold_expr(a, scope))
      }
      Call(n, new_args)
    }
    CallExpr(callee, args) => {
      let new_args : Array[@ast.TsExpr] = []
      for a in args {
        new_args.push(type_fold_expr(a, scope))
      }
      CallExpr(type_fold_expr(callee, scope), new_args)
    }
    MethodCall(recv, m, args) => {
      let new_args : Array[@ast.TsExpr] = []
      for a in args {
        new_args.push(type_fold_expr(a, scope))
      }
      MethodCall(type_fold_expr(recv, scope), m, new_args)
    }
    New(n, args) => {
      let new_args : Array[@ast.TsExpr] = []
      for a in args {
        new_args.push(type_fold_expr(a, scope))
      }
      New(n, new_args)
    }
    NewExpr(callee, args) => {
      let new_args : Array[@ast.TsExpr] = []
      for a in args {
        new_args.push(type_fold_expr(a, scope))
      }
      NewExpr(type_fold_expr(callee, scope), new_args)
    }
    PropAccess(recv, p) => PropAccess(type_fold_expr(recv, scope), p)
    IndexAccess(recv, idx) =>
      IndexAccess(type_fold_expr(recv, scope), type_fold_expr(idx, scope))
    ArrayLit(items) => {
      let new_items : Array[@ast.TsExpr] = []
      for i in items {
        new_items.push(type_fold_expr(i, scope))
      }
      ArrayLit(new_items)
    }
    ObjectLit(entries) => {
      let new_entries : Array[(String, @ast.TsExpr)] = []
      for ent in entries {
        new_entries.push((ent.0, type_fold_expr(ent.1, scope)))
      }
      ObjectLit(new_entries)
    }
    Spread(inner) => Spread(type_fold_expr(inner, scope))
    Yield(Some(inner)) => Yield(Some(type_fold_expr(inner, scope)))
    YieldStar(inner) => YieldStar(type_fold_expr(inner, scope))
    Await(inner) => Await(type_fold_expr(inner, scope))
    Seq(a, b) => Seq(type_fold_expr(a, scope), type_fold_expr(b, scope))
    AssignExpr(n, v) => AssignExpr(n, type_fold_expr(v, scope))
    AssignPattern(b, v) => AssignPattern(b, type_fold_expr(v, scope))
    PropAssignExpr(recv, p, v) =>
      PropAssignExpr(type_fold_expr(recv, scope), p, type_fold_expr(v, scope))
    IndexAssignExpr(recv, idx, v) =>
      IndexAssignExpr(
        type_fold_expr(recv, scope),
        type_fold_expr(idx, scope),
        type_fold_expr(v, scope),
      )
    CompoundAssignExpr(t, op, v) =>
      CompoundAssignExpr(type_fold_expr(t, scope), op, type_fold_expr(v, scope))
    ComputedProp(k, v) =>
      ComputedProp(type_fold_expr(k, scope), type_fold_expr(v, scope))
    ArrowFunc(params, ret, body, is_async) => {
      let local : Map[String, @ast.TsType] = {}
      for entry in scope {
        local[entry.0] = entry.1
      }
      for p in params {
        if is_useful_type(p.type_) {
          local[p.name] = p.type_
        }
      }
      let new_body = match body {
        ArrowExpr(e) => @ast.TsArrowBody::ArrowExpr(type_fold_expr(e, local))
        ArrowBlock(b) => @ast.TsArrowBody::ArrowBlock(type_fold_block_in(b, local))
      }
      ArrowFunc(params, ret, new_body, is_async)
    }
    FuncExpr(f) => {
      let local : Map[String, @ast.TsType] = {}
      for entry in scope {
        local[entry.0] = entry.1
      }
      for p in f.params {
        if is_useful_type(p.type_) {
          local[p.name] = p.type_
        }
      }
      FuncExpr({ ..f, body: type_fold_block_in(f.body, local) })
    }
    DynamicImport(spec, opts) => {
      let opts_f = match opts {
        Some(o) => Some(type_fold_expr(o, scope))
        None => None
      }
      DynamicImport(type_fold_expr(spec, scope), opts_f)
    }
    TaggedTemplate(tag, raw, cooked, exprs) => {
      let new_exprs : Array[@ast.TsExpr] = []
      for e in exprs {
        new_exprs.push(type_fold_expr(e, scope))
      }
      TaggedTemplate(type_fold_expr(tag, scope), raw, cooked, new_exprs)
    }
    TemplateLiteral(parts, exprs) => {
      let new_exprs : Array[@ast.TsExpr] = []
      for e in exprs {
        new_exprs.push(type_fold_expr(e, scope))
      }
      TemplateLiteral(parts, new_exprs)
    }
    As(inner, ty) => As(type_fold_expr(inner, scope), ty)
    Satisfies(inner, ty) => Satisfies(type_fold_expr(inner, scope), ty)
    NonNull(inner) => NonNull(type_fold_expr(inner, scope))
    OptionalChain(inner) => OptionalChain(type_fold_expr(inner, scope))
    PureCall(inner) => PureCall(type_fold_expr(inner, scope))
    _ => expr
  }
}

///|
/// `is_useful_type` is the gate: we only record types we know
/// how to reason about. `Any`, generic refs, unions, and
/// complex shapes don't tell us a primitive `typeof`, so we
/// skip them.
fn is_useful_type(ty : @ast.TsType) -> Bool {
  match ty {
    Number | Int | String_ | Boolean | BigInt | Symbol => true
    Literal(_) | NumberLiteral(_) | BigIntLiteral(_) | BooleanLiteral(_) => true
    _ => false
  }
}

///|
/// Map a primitive type to its `typeof` JavaScript string.
fn typeof_of_type(ty : @ast.TsType) -> String? {
  match ty {
    Number | Int | NumberLiteral(_) => Some("number")
    String_ | Literal(_) => Some("string")
    Boolean | BooleanLiteral(_) => Some("boolean")
    BigInt | BigIntLiteral(_) => Some("bigint")
    Symbol => Some("symbol")
    _ => None
  }
}

///|
/// Fold `typeof x op "lit"` when x's static type lets us decide
/// the comparison. Returns `Some(b)` for the folded literal,
/// `None` to leave the expression untouched.
fn try_typeof_fold(
  op : @ast.TsBinOp,
  x_name : String,
  lit : String,
  scope : Map[String, @ast.TsType],
) -> Bool? {
  let ty = match scope.get(x_name) {
    Some(t) => t
    None => return None
  }
  let actual = match typeof_of_type(ty) {
    Some(s) => s
    None => return None
  }
  let equal = actual == lit
  match op {
    BinEq | AbstractEq => Some(equal)
    BinNe | AbstractNe => Some(not(equal))
    _ => None
  }
}

///|
/// Fold `x op null` / `x op undefined` for non-nullable
/// primitive types. (`number` can't be `null`, etc.)
fn try_null_check_fold(
  op : @ast.TsBinOp,
  x_name : String,
  rhs_kind : String,
  scope : Map[String, @ast.TsType],
) -> Bool? {
  let ty = match scope.get(x_name) {
    Some(t) => t
    None => return None
  }
  // The types we cleared in `is_useful_type` are all non-
  // nullable primitives — a `: number` parameter / binding
  // can't be `null` or `undefined` in a well-typed program.
  let _ = rhs_kind
  let can_be_null = match ty {
    Number | Int | String_ | Boolean | BigInt | Symbol => false
    Literal(_) | NumberLiteral(_) | BigIntLiteral(_) | BooleanLiteral(_) => false
    _ => return None
  }
  // `x === null` for non-nullable x → false; `x !== null` → true.
  let _ = can_be_null
  match op {
    BinEq | AbstractEq => Some(false)
    BinNe | AbstractNe => Some(true)
    _ => None
  }
}
