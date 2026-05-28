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
  // Cheap pre-scan: type-fold only does work when something it can
  // act on appears in the block — `typeof` comparisons, `=== null`
  // checks, or a switch on a literal-string union. If none of those
  // are present, the full recursive walk would do nothing useful;
  // skip it and avoid the cost on bundles that don't need it.
  if not(block_needs_type_fold(block)) {
    return block
  }
  let scope : Map[String, @ast.TsType] = {}
  type_fold_block_in(block, scope)
}

///|
fn block_needs_type_fold(block : @ast.TsBlock) -> Bool {
  for s in block.stmts {
    if stmt_needs_type_fold(s) {
      return true
    }
  }
  false
}

///|
fn stmt_needs_type_fold(stmt : @ast.TsStmt) -> Bool {
  match stmt {
    Var(_, _, e)
    | Let(_, _, e)
    | Const(_, _, e)
    | Expr(e)
    | Assign(_, e)
    | CompoundAssign(_, _, e)
    | Throw(e) => expr_needs_type_fold(e)
    Return(Some(e)) => expr_needs_type_fold(e)
    Return(None) | Empty | Debugger | Break(_) | Continue(_) => false
    IndexAssign(t, idx, v) =>
      expr_needs_type_fold(t) ||
      expr_needs_type_fold(idx) ||
      expr_needs_type_fold(v)
    PropAssign(t, _, v) => expr_needs_type_fold(t) || expr_needs_type_fold(v)
    If(c, t, e) => {
      if expr_needs_type_fold(c) {
        return true
      }
      if block_needs_type_fold(t) {
        return true
      }
      match e {
        Some(b) => block_needs_type_fold(b)
        None => false
      }
    }
    While(c, body) | DoWhile(c, body) | With(c, body) =>
      expr_needs_type_fold(c) || block_needs_type_fold(body)
    For(init, cond, update, body) => {
      let init_b = match init {
        Some(s) => stmt_needs_type_fold(s)
        None => false
      }
      if init_b {
        return true
      }
      let cond_b = match cond {
        Some(e) => expr_needs_type_fold(e)
        None => false
      }
      if cond_b {
        return true
      }
      let upd_b = match update {
        Some(s) => stmt_needs_type_fold(s)
        None => false
      }
      if upd_b {
        return true
      }
      block_needs_type_fold(body)
    }
    ForOf(_, _, _, iter, body)
    | ForAwaitOf(_, _, _, iter, body)
    | ForIn(_, _, _, iter, body) =>
      expr_needs_type_fold(iter) || block_needs_type_fold(body)
    // Switch with an exhaustive default-drop target counts.
    Switch(e, cases) => {
      if expr_needs_type_fold(e) {
        return true
      }
      // Default arm with `throw …` is the drop-target shape.
      for c in cases {
        match c.test_expr {
          None =>
            if c.body.stmts.length() == 1 {
              match c.body.stmts[0] {
                Throw(_) => return true
                _ => ()
              }
            }
          Some(te) => if expr_needs_type_fold(te) { return true }
        }
        if block_needs_type_fold(c.body) {
          return true
        }
      }
      false
    }
    Try(b, _, cb, fb) => {
      if block_needs_type_fold(b) {
        return true
      }
      let cb_b = match cb {
        Some(blk) => block_needs_type_fold(blk)
        None => false
      }
      if cb_b {
        return true
      }
      match fb {
        Some(blk) => block_needs_type_fold(blk)
        None => false
      }
    }
    Label(_, inner) => stmt_needs_type_fold(inner)
    Block(b) => block_needs_type_fold(b)
    NativeClassStmt(decl, ctor_body) => {
      for m in decl.methods {
        match m.body {
          Some(b) => if block_needs_type_fold(b) { return true }
          None => ()
        }
      }
      for sf in decl.static_field_inits {
        if expr_needs_type_fold(sf.1) {
          return true
        }
      }
      match ctor_body {
        Some(f) => block_needs_type_fold(f.body)
        None => false
      }
    }
  }
}

///|
fn expr_needs_type_fold(expr : @ast.TsExpr) -> Bool {
  match expr {
    // `typeof x === "lit"` — discriminant we can fold.
    BinOp(op, l, r) => {
      let is_eq_op = match op {
        BinEq | BinNe | AbstractEq | AbstractNe => true
        _ => false
      }
      if is_eq_op {
        match (l, r) {
          (
            @ast.TsExpr::UnaryOp(@ast.TsUnaryOp::Typeof, _),
            @ast.TsExpr::StringLit(_),
          )
          | (
            @ast.TsExpr::StringLit(_),
            @ast.TsExpr::UnaryOp(@ast.TsUnaryOp::Typeof, _),
          ) => return true
          // `x === null` / `x === undefined`.
          (@ast.TsExpr::Var(_), @ast.TsExpr::NullLit)
          | (@ast.TsExpr::NullLit, @ast.TsExpr::Var(_)) => return true
          (@ast.TsExpr::Var(_), @ast.TsExpr::Var("undefined"))
          | (@ast.TsExpr::Var("undefined"), @ast.TsExpr::Var(_)) => return true
          _ => ()
        }
      }
      expr_needs_type_fold(l) || expr_needs_type_fold(r)
    }
    UnaryOp(_, inner)
    | Spread(inner)
    | Await(inner)
    | NonNull(inner)
    | OptionalChain(inner)
    | PureCall(inner)
    | YieldStar(inner) => expr_needs_type_fold(inner)
    Cond(c, t, e) =>
      expr_needs_type_fold(c) ||
      expr_needs_type_fold(t) ||
      expr_needs_type_fold(e)
    Seq(l, r) => expr_needs_type_fold(l) || expr_needs_type_fold(r)
    PropAccess(recv, _) => expr_needs_type_fold(recv)
    IndexAccess(recv, idx) =>
      expr_needs_type_fold(recv) || expr_needs_type_fold(idx)
    Call(_, args) | New(_, args) => {
      for a in args {
        if expr_needs_type_fold(a) {
          return true
        }
      }
      false
    }
    CallExpr(callee, args) | NewExpr(callee, args) => {
      if expr_needs_type_fold(callee) {
        return true
      }
      for a in args {
        if expr_needs_type_fold(a) {
          return true
        }
      }
      false
    }
    MethodCall(recv, _, args) => {
      if expr_needs_type_fold(recv) {
        return true
      }
      for a in args {
        if expr_needs_type_fold(a) {
          return true
        }
      }
      false
    }
    ArrayLit(items) => {
      for i in items {
        if expr_needs_type_fold(i) {
          return true
        }
      }
      false
    }
    ObjectLit(entries) => {
      for ent in entries {
        if expr_needs_type_fold(ent.1) {
          return true
        }
      }
      false
    }
    ArrowFunc(_, _, body, _) =>
      match body {
        ArrowExpr(e) => expr_needs_type_fold(e)
        ArrowBlock(b) => block_needs_type_fold(b)
      }
    FuncExpr(f) => block_needs_type_fold(f.body)
    AssignExpr(_, v) | AssignPattern(_, v) | PropAssignExpr(_, _, v) =>
      expr_needs_type_fold(v)
    CompoundAssignExpr(t, _, v) =>
      expr_needs_type_fold(t) || expr_needs_type_fold(v)
    IndexAssignExpr(recv, idx, v) =>
      expr_needs_type_fold(recv) ||
      expr_needs_type_fold(idx) ||
      expr_needs_type_fold(v)
    ComputedProp(k, v) => expr_needs_type_fold(k) || expr_needs_type_fold(v)
    As(inner, _) | Satisfies(inner, _) => expr_needs_type_fold(inner)
    Yield(Some(inner)) => expr_needs_type_fold(inner)
    TaggedTemplate(tag, _, _, exprs) => {
      if expr_needs_type_fold(tag) {
        return true
      }
      for e in exprs {
        if expr_needs_type_fold(e) {
          return true
        }
      }
      false
    }
    TemplateLiteral(_, exprs) => {
      for e in exprs {
        if expr_needs_type_fold(e) {
          return true
        }
      }
      false
    }
    DynamicImport(spec, opts) => {
      if expr_needs_type_fold(spec) {
        return true
      }
      match opts {
        Some(o) => expr_needs_type_fold(o)
        None => false
      }
    }
    _ => false
  }
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
  { stmts, stmt_positions: block.stmt_positions }
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
        @ast.TsBinding::Ident(name) => if is_useful_type(t) { scope[name] = t }
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
    CompoundAssign(n, op, e) => CompoundAssign(n, op, type_fold_expr(e, scope))
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
      ForOf(
        k,
        b,
        t,
        type_fold_expr(iter, scope),
        type_fold_block_in(body, scope),
      )
    ForAwaitOf(k, b, t, iter, body) =>
      ForAwaitOf(
        k,
        b,
        t,
        type_fold_expr(iter, scope),
        type_fold_block_in(body, scope),
      )
    ForIn(k, b, t, iter, body) =>
      ForIn(
        k,
        b,
        t,
        type_fold_expr(iter, scope),
        type_fold_block_in(body, scope),
      )
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
      let folded_e = type_fold_expr(e, scope)
      // Exhaustive-default drop: when the discriminant's static
      // type is a closed string-literal union, every literal is
      // covered by a `case`, and the `default:` body is the
      // unreachable-assertion shape (`[Throw(...)]`), the default
      // can be dropped — TS guarantees it never fires.
      let pruned_cases = drop_exhaustive_default(folded_e, new_cases, scope)
      Switch(folded_e, pruned_cases)
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
    NativeClassStmt(decl, ctor) => {
      let new_ctor = match ctor {
        Some(f) => Some({ ..f, body: type_fold_block_in(f.body, scope) })
        None => None
      }
      let new_methods : Array[@ast.TsClassMethodDecl] = []
      for m in decl.methods {
        let new_body = match m.body {
          Some(b) => Some(type_fold_block_in(b, scope))
          None => None
        }
        new_methods.push({ ..m, body: new_body })
      }
      let new_static_fields : Array[(String, @ast.TsExpr)] = []
      for sf in decl.static_field_inits {
        new_static_fields.push((sf.0, type_fold_expr(sf.1, scope)))
      }
      NativeClassStmt(
        { ..decl, methods: new_methods, static_field_inits: new_static_fields },
        new_ctor,
      )
    }
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
        ArrowBlock(b) =>
          @ast.TsArrowBody::ArrowBlock(type_fold_block_in(b, local))
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
    // Closed string-literal unions feed `drop_exhaustive_default`.
    Union(parts) => {
      if parts.length() == 0 {
        return false
      }
      for p in parts {
        match p {
          Literal(_) => ()
          _ => return false
        }
      }
      true
    }
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
/// Drop the trailing `default:` arm of a `switch` when the
/// discriminant's static type is a closed string-literal union,
/// every literal is covered by a `case`, and the default body is
/// the unreachable-assertion shape (`[Throw(...)]`).
fn drop_exhaustive_default(
  disc : @ast.TsExpr,
  cases : Array[@ast.TsSwitchCase],
  scope : Map[String, @ast.TsType],
) -> Array[@ast.TsSwitchCase] {
  if cases.length() == 0 {
    return cases
  }
  // Default must be the final arm to be a safe drop.
  let last = cases[cases.length() - 1]
  let default_block = match last.test_expr {
    None => last.body
    Some(_) => return cases
  }
  // Default body must be a single `throw <expr>;` to keep this
  // safe — any other statement could carry observable behavior
  // we can't preserve.
  if default_block.stmts.length() != 1 {
    return cases
  }
  match default_block.stmts[0] {
    Throw(_) => ()
    _ => return cases
  }
  // Discriminant must be a tracked variable carrying a literal-
  // string union annotation.
  let name = match disc {
    Var(n) => n
    _ => return cases
  }
  let ty = match scope.get(name) {
    Some(t) => t
    None => return cases
  }
  let literals = match ty {
    Union(parts) => {
      let out : Array[String] = []
      for p in parts {
        match p {
          Literal(s) => out.push(s)
          _ => return cases
        }
      }
      out
    }
    _ => return cases
  }
  // Every literal in the union must be matched by a case.
  let covered : Map[String, Bool] = {}
  for c in cases {
    match c.test_expr {
      Some(@ast.TsExpr::StringLit(s)) => covered[s] = true
      _ => ()
    }
  }
  for l in literals {
    if not(covered.contains(l)) {
      return cases
    }
  }
  // All literals covered — drop the default.
  let pruned : Array[@ast.TsSwitchCase] = []
  for i in 0..<(cases.length() - 1) {
    pruned.push(cases[i])
  }
  pruned
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
    Literal(_) | NumberLiteral(_) | BigIntLiteral(_) | BooleanLiteral(_) =>
      false
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
