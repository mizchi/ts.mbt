// Literal-union switch folding at typed call sites.
//
// Specialize calls to functions whose first parameter is a
// closed string-literal union and whose body is a single
// `switch` on that parameter, with every arm returning an
// expression. At a call site where the corresponding argument
// is a `StringLit`, substitute the matching arm's expression
// directly (with the other parameters replaced by their
// trivially-safe call arguments).
//
//   function dispatch(k: "x" | "y", n: number): number {
//     switch (k) {
//       case "x": return n + 1;
//       case "y": return n + 2;
//     }
//   }
//
//   dispatch("x", 5)    // -> 5 + 1   (fold will collapse to 6)
//   dispatch("y", n)    // -> n + 2
//
// Constraints (kept conservative for the first cut):
//   - First parameter has type `Union(parts)` where every part
//     is `Literal(s)`.
//   - Body is a single `switch (<first param>) { ... }`.
//   - Every case's `test_expr` is a `StringLit` matching one of
//     the union literals; every literal in the union is covered.
//   - Each case body is exactly one stmt: `Return(Some(EXPR))`.
//   - No `default:` arm. (Union is closed so it's unreachable.)
//   - At the call site, all non-discriminant arguments must be
//     trivially safe to substitute (literal or `Var(name)`)
//     so duplicating or dropping them doesn't change semantics.

///|
pub(all) struct SwitchFoldTable {
  entries : Map[String, SwitchFoldEntry]
}

///|
pub(all) struct SwitchFoldEntry {
  // Parameter names in declaration order.
  param_names : Array[String]
  // Index of the parameter that the switch tests. First param
  // for now, but the field makes the call-site code uniform.
  switch_param_index : Int
  // Literal value -> matched arm's `return EXPR` body.
  arms : Map[String, @ast.TsExpr]
}

///|
pub fn build_switch_fold_table(block : @ast.TsBlock) -> SwitchFoldTable {
  let entries : Map[String, SwitchFoldEntry] = {}
  for stmt in block.stmts {
    match stmt {
      Let(@ast.TsBinding::Ident(name), _, @ast.TsExpr::FuncExpr(f))
      | Const(@ast.TsBinding::Ident(name), _, @ast.TsExpr::FuncExpr(f))
      | Var(@ast.TsBinding::Ident(name), _, @ast.TsExpr::FuncExpr(f)) =>
        match try_extract_switch_fold(f) {
          Some(entry) => entries[name] = entry
          None => ()
        }
      _ => ()
    }
  }
  { entries, }
}

///|
fn try_extract_switch_fold(f : @ast.TsFunc) -> SwitchFoldEntry? {
  if f.params.length() == 0 {
    return None
  }
  // First param must carry a closed string-literal union annotation.
  let first = f.params[0]
  let literals = match string_literal_union(first.type_) {
    Some(ls) => ls
    None => return None
  }
  let switch_param_name = match first.binding {
    Some(@ast.TsBinding::Ident(n)) => n
    Some(_) => return None
    None => first.name
  }
  // Collect every parameter name; bail on destructured / rest params.
  let param_names : Array[String] = []
  for p in f.params {
    if p.is_rest {
      return None
    }
    let n = match p.binding {
      Some(@ast.TsBinding::Ident(s)) => s
      Some(_) => return None
      None => p.name
    }
    param_names.push(n)
  }
  // Body must be a single `switch (param) { ... }`.
  if f.body.stmts.length() != 1 {
    return None
  }
  let cases = match f.body.stmts[0] {
    Switch(@ast.TsExpr::Var(n), cs) =>
      if n == switch_param_name {
        cs
      } else {
        return None
      }
    _ => return None
  }
  // Every arm must be `case "lit": return EXPR;`. No `default:`.
  let arms : Map[String, @ast.TsExpr] = {}
  for c in cases {
    let lit = match c.test_expr {
      Some(@ast.TsExpr::StringLit(s)) => s
      _ => return None
    }
    if c.body.stmts.length() != 1 {
      return None
    }
    let expr = match c.body.stmts[0] {
      Return(Some(e)) => e
      _ => return None
    }
    arms[lit] = expr
  }
  // Every literal in the union must have a matching arm.
  for l in literals {
    if not(arms.contains(l)) {
      return None
    }
  }
  Some({ param_names, switch_param_index: 0, arms })
}

///|
/// Returns the set of string literal members if `ty` is a union
/// where every member is `Literal(s)`. Otherwise `None`.
fn string_literal_union(ty : @ast.TsType) -> Array[String]? {
  match ty {
    Union(parts) => {
      if parts.length() == 0 {
        return None
      }
      let out : Array[String] = []
      for p in parts {
        match p {
          Literal(s) => out.push(s)
          _ => return None
        }
      }
      Some(out)
    }
    _ => None
  }
}

///|
/// Walk the block, replacing every call to a known switch-fold
/// function (with a literal first argument and otherwise trivial
/// arguments) with the substituted arm body.
pub fn switch_fold(
  block : @ast.TsBlock,
  table : SwitchFoldTable,
) -> @ast.TsBlock {
  if table.entries.is_empty() {
    return block
  }
  let stmts : Array[@ast.TsStmt] = []
  for s in block.stmts {
    stmts.push(switch_fold_stmt(s, table))
  }
  { stmts, stmt_positions: block.stmt_positions }
}

///|
fn switch_fold_block(
  block : @ast.TsBlock,
  table : SwitchFoldTable,
) -> @ast.TsBlock {
  let stmts : Array[@ast.TsStmt] = []
  for s in block.stmts {
    stmts.push(switch_fold_stmt(s, table))
  }
  { stmts, stmt_positions: block.stmt_positions }
}

///|
fn switch_fold_stmt(
  stmt : @ast.TsStmt,
  table : SwitchFoldTable,
) -> @ast.TsStmt {
  match stmt {
    Var(b, t, e) => Var(b, t, switch_fold_expr(e, table))
    Let(b, t, e) => Let(b, t, switch_fold_expr(e, table))
    Const(b, t, e) => Const(b, t, switch_fold_expr(e, table))
    Assign(n, e) => Assign(n, switch_fold_expr(e, table))
    CompoundAssign(n, op, e) =>
      CompoundAssign(n, op, switch_fold_expr(e, table))
    IndexAssign(t, idx, v) =>
      IndexAssign(
        switch_fold_expr(t, table),
        switch_fold_expr(idx, table),
        switch_fold_expr(v, table),
      )
    PropAssign(t, prop, v) =>
      PropAssign(switch_fold_expr(t, table), prop, switch_fold_expr(v, table))
    Expr(e) => Expr(switch_fold_expr(e, table))
    Return(Some(e)) => Return(Some(switch_fold_expr(e, table)))
    Return(None) | Empty | Debugger | Break(_) | Continue(_) => stmt
    Throw(e) => Throw(switch_fold_expr(e, table))
    If(c, t, e) =>
      If(
        switch_fold_expr(c, table),
        switch_fold_block(t, table),
        match e {
          Some(b) => Some(switch_fold_block(b, table))
          None => None
        },
      )
    While(c, body) =>
      While(switch_fold_expr(c, table), switch_fold_block(body, table))
    DoWhile(c, body) =>
      DoWhile(switch_fold_expr(c, table), switch_fold_block(body, table))
    With(c, body) =>
      With(switch_fold_expr(c, table), switch_fold_block(body, table))
    For(init, cond, update, body) =>
      For(
        match init {
          Some(s) => Some(switch_fold_stmt(s, table))
          None => None
        },
        match cond {
          Some(e) => Some(switch_fold_expr(e, table))
          None => None
        },
        match update {
          Some(s) => Some(switch_fold_stmt(s, table))
          None => None
        },
        switch_fold_block(body, table),
      )
    ForOf(k, b, t, iter, body) =>
      ForOf(
        k, b, t, switch_fold_expr(iter, table), switch_fold_block(body, table),
      )
    ForAwaitOf(k, b, t, iter, body) =>
      ForAwaitOf(
        k, b, t, switch_fold_expr(iter, table), switch_fold_block(body, table),
      )
    ForIn(k, b, t, iter, body) =>
      ForIn(
        k, b, t, switch_fold_expr(iter, table), switch_fold_block(body, table),
      )
    Switch(e, cases) => {
      let new_cases : Array[@ast.TsSwitchCase] = []
      for c in cases {
        new_cases.push({
          test_expr: match c.test_expr {
            Some(te) => Some(switch_fold_expr(te, table))
            None => None
          },
          body: switch_fold_block(c.body, table),
        })
      }
      Switch(switch_fold_expr(e, table), new_cases)
    }
    Try(b, bnd, cb, fb) =>
      Try(
        switch_fold_block(b, table),
        bnd,
        match cb {
          Some(blk) => Some(switch_fold_block(blk, table))
          None => None
        },
        match fb {
          Some(blk) => Some(switch_fold_block(blk, table))
          None => None
        },
      )
    Label(name, inner) => Label(name, switch_fold_stmt(inner, table))
    Block(b) => Block(switch_fold_block(b, table))
    NativeClassStmt(_, _) => stmt
  }
}

///|
fn switch_fold_expr(
  expr : @ast.TsExpr,
  table : SwitchFoldTable,
) -> @ast.TsExpr {
  match expr {
    Call(name, args) => {
      // First try the switch-fold rewrite.
      match table.entries.get(name) {
        Some(entry) =>
          match try_fold_call(entry, args) {
            Some(folded) => return folded
            None => ()
          }
        None => ()
      }
      let new_args : Array[@ast.TsExpr] = []
      for a in args {
        new_args.push(switch_fold_expr(a, table))
      }
      Call(name, new_args)
    }
    CallExpr(callee, args) => {
      let new_args : Array[@ast.TsExpr] = []
      for a in args {
        new_args.push(switch_fold_expr(a, table))
      }
      CallExpr(switch_fold_expr(callee, table), new_args)
    }
    New(n, args) => {
      let new_args : Array[@ast.TsExpr] = []
      for a in args {
        new_args.push(switch_fold_expr(a, table))
      }
      New(n, new_args)
    }
    NewExpr(callee, args) => {
      let new_args : Array[@ast.TsExpr] = []
      for a in args {
        new_args.push(switch_fold_expr(a, table))
      }
      NewExpr(switch_fold_expr(callee, table), new_args)
    }
    MethodCall(recv, m, args) => {
      let new_args : Array[@ast.TsExpr] = []
      for a in args {
        new_args.push(switch_fold_expr(a, table))
      }
      MethodCall(switch_fold_expr(recv, table), m, new_args)
    }
    BinOp(op, l, r) =>
      BinOp(op, switch_fold_expr(l, table), switch_fold_expr(r, table))
    UnaryOp(op, inner) => UnaryOp(op, switch_fold_expr(inner, table))
    Cond(c, t, e) =>
      Cond(
        switch_fold_expr(c, table),
        switch_fold_expr(t, table),
        switch_fold_expr(e, table),
      )
    PropAccess(recv, p) => PropAccess(switch_fold_expr(recv, table), p)
    IndexAccess(recv, idx) =>
      IndexAccess(switch_fold_expr(recv, table), switch_fold_expr(idx, table))
    ArrayLit(items) => {
      let new_items : Array[@ast.TsExpr] = []
      for i in items {
        new_items.push(switch_fold_expr(i, table))
      }
      ArrayLit(new_items)
    }
    ObjectLit(entries) => {
      let new_entries : Array[(String, @ast.TsExpr)] = []
      for ent in entries {
        new_entries.push((ent.0, switch_fold_expr(ent.1, table)))
      }
      ObjectLit(new_entries)
    }
    Spread(inner) => Spread(switch_fold_expr(inner, table))
    Yield(Some(inner)) => Yield(Some(switch_fold_expr(inner, table)))
    YieldStar(inner) => YieldStar(switch_fold_expr(inner, table))
    Await(inner) => Await(switch_fold_expr(inner, table))
    Seq(a, b) => Seq(switch_fold_expr(a, table), switch_fold_expr(b, table))
    AssignExpr(n, v) => AssignExpr(n, switch_fold_expr(v, table))
    CompoundAssignExpr(t, op, v) =>
      CompoundAssignExpr(
        switch_fold_expr(t, table),
        op,
        switch_fold_expr(v, table),
      )
    AssignPattern(b, v) => AssignPattern(b, switch_fold_expr(v, table))
    PropAssignExpr(recv, p, v) =>
      PropAssignExpr(switch_fold_expr(recv, table), p, switch_fold_expr(v, table))
    IndexAssignExpr(recv, idx, v) =>
      IndexAssignExpr(
        switch_fold_expr(recv, table),
        switch_fold_expr(idx, table),
        switch_fold_expr(v, table),
      )
    ComputedProp(k, v) =>
      ComputedProp(switch_fold_expr(k, table), switch_fold_expr(v, table))
    ArrowFunc(params, ret, body, is_async) => {
      let new_body = match body {
        ArrowExpr(e) => @ast.TsArrowBody::ArrowExpr(switch_fold_expr(e, table))
        ArrowBlock(b) => @ast.TsArrowBody::ArrowBlock(switch_fold_block(b, table))
      }
      ArrowFunc(params, ret, new_body, is_async)
    }
    FuncExpr(f) => {
      let new_body = switch_fold_block(f.body, table)
      FuncExpr({ ..f, body: new_body })
    }
    DynamicImport(spec, opts) => {
      let opts_f = match opts {
        Some(o) => Some(switch_fold_expr(o, table))
        None => None
      }
      DynamicImport(switch_fold_expr(spec, table), opts_f)
    }
    TaggedTemplate(tag, raw, cooked, exprs) => {
      let new_exprs : Array[@ast.TsExpr] = []
      for e in exprs {
        new_exprs.push(switch_fold_expr(e, table))
      }
      TaggedTemplate(switch_fold_expr(tag, table), raw, cooked, new_exprs)
    }
    TemplateLiteral(parts, exprs) => {
      let new_exprs : Array[@ast.TsExpr] = []
      for e in exprs {
        new_exprs.push(switch_fold_expr(e, table))
      }
      TemplateLiteral(parts, new_exprs)
    }
    As(inner, ty) => As(switch_fold_expr(inner, table), ty)
    Satisfies(inner, ty) => Satisfies(switch_fold_expr(inner, table), ty)
    NonNull(inner) => NonNull(switch_fold_expr(inner, table))
    OptionalChain(inner) => OptionalChain(switch_fold_expr(inner, table))
    PureCall(inner) => PureCall(switch_fold_expr(inner, table))
    _ => expr
  }
}

///|
/// Returns the folded expression if the call matches a switch-fold
/// entry, the discriminant argument is a string literal hitting an
/// arm, and every other argument is trivially safe to substitute.
fn try_fold_call(
  entry : SwitchFoldEntry,
  args : Array[@ast.TsExpr],
) -> @ast.TsExpr? {
  if args.length() != entry.param_names.length() {
    return None
  }
  let disc = args[entry.switch_param_index]
  let lit = match disc {
    StringLit(s) => s
    _ => return None
  }
  let body = match entry.arms.get(lit) {
    Some(e) => e
    None => return None
  }
  for i in 0..<args.length() {
    if i == entry.switch_param_index {
      continue
    }
    if not(is_trivially_substitutable(args[i])) {
      return None
    }
  }
  // Substitute each parameter (including the discriminant, in case
  // the arm body references it by name — though typically it does
  // not since the switch already matched on it).
  let mut out = body
  for i in 0..<entry.param_names.length() {
    out = substitute_param_with_arg(out, entry.param_names[i], args[i])
  }
  Some(out)
}

///|
/// An argument is "trivially substitutable" when duplicating or
/// dropping it cannot change observable behavior. That covers
/// primitive literals and bare identifier references.
fn is_trivially_substitutable(e : @ast.TsExpr) -> Bool {
  match e {
    StringLit(_) | NumberLit(_) | IntLit(_) | BoolLit(_) | NullLit
    | BigIntLit(_) | Var(_) => true
    _ => false
  }
}
