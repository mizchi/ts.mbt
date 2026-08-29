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
/// Scope narrowing. The table is keyed by the dispatcher's NAME, so a
/// scope that re-binds that name means the call resolves somewhere else
/// and the specialization is wrong:
///
///     function dispatch(k: "a" | "b") { switch (k) { … } }
///     function sw(dispatch: (k: "a") => number) { return dispatch("a"); }
///
/// `sw(() => 42)` returned 1 — the outer dispatcher's `case "a"` arm,
/// substituted over a call to the PARAMETER. A wrong value, not a
/// crash. The helpers are shared; see the top of `call_inline.mbt`.
fn SwitchFoldTable::narrow(
  self : SwitchFoldTable,
  names : Array[String],
) -> SwitchFoldTable {
  { entries: narrow_trivial_fns(self.entries, names) }
}

///|
fn SwitchFoldTable::narrow_block(
  self : SwitchFoldTable,
  block : @ast.TsBlock,
) -> SwitchFoldTable {
  let names : Array[String] = []
  collect_block_bound_names(block, names)
  self.narrow(names)
}

///|
fn SwitchFoldTable::narrow_params(
  self : SwitchFoldTable,
  params : Array[@ast.TsParam],
) -> SwitchFoldTable {
  let names : Array[String] = []
  collect_param_bound_names(params, names)
  self.narrow(names)
}

///|
fn SwitchFoldTable::narrow_named_params(
  self : SwitchFoldTable,
  params : Array[(String, @ast.TsType)],
) -> SwitchFoldTable {
  let names : Array[String] = []
  for pr in params {
    if pr.0 != "" {
      names.push(pr.0)
    }
  }
  self.narrow(names)
}

///|
fn SwitchFoldTable::narrow_binding(
  self : SwitchFoldTable,
  b : @ast.TsBinding,
) -> SwitchFoldTable {
  let names : Array[String] = []
  collect_binding_bound_names(b, names)
  self.narrow(names)
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
pub fn build_switch_fold_table(
  block : @ast.TsBlock,
  // `--explain-mangle`: why the table came out empty. Same reason
  // `tag_rewrite_block` gained one — the pass moves zero bytes on all
  // ten type-aware corpus targets, and "zero" means either that no
  // bundle declares the shape (nothing to fix) or that the shape is
  // there and a gate refused it (the reason names the fix). The byte
  // count cannot tell those apart.
  explain? : Array[String]? = None,
) -> SwitchFoldTable {
  let entries : Map[String, SwitchFoldEntry] = {}
  for stmt in block.stmts {
    match stmt {
      Let(@ast.TsBinding::Ident(name), _, @ast.TsExpr::FuncExpr(f))
      | Const(@ast.TsBinding::Ident(name), _, @ast.TsExpr::FuncExpr(f))
      | Var(@ast.TsBinding::Ident(name), _, @ast.TsExpr::FuncExpr(f)) =>
        match try_extract_switch_fold(f) {
          Ok(entry) => entries[name] = entry
          Err(_) => ()
        }
      _ => ()
    }
  }
  match explain {
    Some(out) => explain_switch_fold_candidates(out, block, entries)
    None => ()
  }
  { entries, }
}

///|
/// Why a function with the pass's entry shape did not become an entry.
/// `NotADispatcher` is the "shape absent" answer — no first parameter,
/// or one that is not a closed string-literal union — and every other
/// variant is a gate that could in principle be opened.
priv enum SwitchFoldReject {
  NotADispatcher
  DestructuredOrRestParam
  BodyNotOneSwitchOnTheParam
  ArmNotASingleReturn
  CaseNotAStringLiteral
  LiteralWithNoArm
} derive(Eq)

///|
fn SwitchFoldReject::label(self : SwitchFoldReject) -> String {
  match self {
    NotADispatcher => "no closed string-literal union as the first parameter"
    DestructuredOrRestParam => "a destructured or rest parameter"
    BodyNotOneSwitchOnTheParam =>
      "the body is not exactly one `switch` on that parameter"
    ArmNotASingleReturn => "an arm is not exactly one `return EXPR`"
    CaseNotAStringLiteral => "a case label is not a string literal"
    LiteralWithNoArm => "a union literal has no arm and there is no `default`"
  }
}

///|
/// `--explain-mangle` for the pass's candidate step. Counts the whole
/// block, nested functions included, because the table itself only
/// reads TOP-LEVEL declarations: a dispatcher declared inside another
/// function is invisible to it, and whether that is where real code
/// puts them is exactly the question the byte count cannot answer.
fn explain_switch_fold_candidates(
  out : Array[String],
  block : @ast.TsBlock,
  entries : Map[String, SwitchFoldEntry],
) -> Unit {
  let top : Array[(String, SwitchFoldReject?)] = []
  for stmt in block.stmts {
    match stmt {
      Let(@ast.TsBinding::Ident(name), _, @ast.TsExpr::FuncExpr(f))
      | Const(@ast.TsBinding::Ident(name), _, @ast.TsExpr::FuncExpr(f))
      | Var(@ast.TsBinding::Ident(name), _, @ast.TsExpr::FuncExpr(f)) =>
        match try_extract_switch_fold(f) {
          Ok(_) => top.push((name, None))
          Err(r) => top.push((name, Some(r)))
        }
      _ => ()
    }
  }
  // Functions anywhere in the block whose first parameter IS a closed
  // string-literal union — the pass's target shape, wherever it sits.
  let all_shaped : Array[SwitchFoldReject?] = []
  collect_switch_fold_shapes_block(block, all_shaped)
  let shaped = all_shaped.length()
  if shaped == 0 {
    out.push(
      "no candidate at all: no function in the bundle takes a closed string-literal union as its first parameter. The shape this pass specializes is absent.",
    )
    return
  }
  let mut top_shaped = 0
  for e in top {
    if e.1 != Some(SwitchFoldReject::NotADispatcher) {
      top_shaped = top_shaped + 1
    }
  }
  out.push(
    "\{shaped} function(s) take a closed string-literal union as their first parameter; \{entries.size()} became specializable.",
  )
  if top_shaped < shaped {
    out.push(
      "  \{shaped - top_shaped} of them are not top-level declarations, and the table only reads top-level ones, so they were never considered.",
    )
  }
  // Group the rejections by reason.
  let counts : Map[String, Int] = {}
  for r in all_shaped {
    match r {
      Some(rej) => {
        if rej == SwitchFoldReject::NotADispatcher {
          continue
        }
        let l = rej.label()
        counts[l] = counts.get(l).unwrap_or(0) + 1
      }
      None => ()
    }
  }
  let keys = counts.keys().to_array()
  keys.sort()
  for k in keys {
    out.push("  \{counts.get(k).unwrap_or(0)} rejected: \{k}.")
  }
}

///|
/// Push one entry per function in the block whose first parameter is a
/// closed string-literal union: `None` when it is specializable,
/// `Some(reason)` when a later gate refused it. Functions without the
/// entry shape contribute nothing.
fn collect_switch_fold_shapes_block(
  block : @ast.TsBlock,
  out : Array[SwitchFoldReject?],
) -> Unit {
  for s in block.stmts {
    collect_switch_fold_shapes_stmt(s, out)
  }
}

///|
fn collect_switch_fold_shapes_func(
  f : @ast.TsFunc,
  out : Array[SwitchFoldReject?],
) -> Unit {
  match try_extract_switch_fold(f) {
    Ok(_) => out.push(None)
    Err(SwitchFoldReject::NotADispatcher) => ()
    Err(r) => out.push(Some(r))
  }
  collect_switch_fold_shapes_block(f.body, out)
}

///|
fn try_extract_switch_fold(
  f : @ast.TsFunc,
) -> Result[SwitchFoldEntry, SwitchFoldReject] {
  if f.params.length() == 0 {
    return Err(NotADispatcher)
  }
  // First param must carry a closed string-literal union annotation.
  let first = f.params[0]
  let literals = match string_literal_union(first.type_) {
    Some(ls) => ls
    None => return Err(NotADispatcher)
  }
  let switch_param_name = match first.binding {
    Some(@ast.TsBinding::Ident(n)) => n
    Some(_) => return Err(DestructuredOrRestParam)
    None => first.name
  }
  // Collect every parameter name; bail on destructured / rest params.
  let param_names : Array[String] = []
  for p in f.params {
    if p.is_rest {
      return Err(DestructuredOrRestParam)
    }
    let n = match p.binding {
      Some(@ast.TsBinding::Ident(s)) => s
      Some(_) => return Err(DestructuredOrRestParam)
      None => p.name
    }
    param_names.push(n)
  }
  // Body must be a single `switch (param) { ... }`.
  if f.body.stmts.length() != 1 {
    return Err(BodyNotOneSwitchOnTheParam)
  }
  let cases = match f.body.stmts[0] {
    Switch(@ast.TsExpr::Var(n), cs) =>
      if n == switch_param_name {
        cs
      } else {
        return Err(BodyNotOneSwitchOnTheParam)
      }
    _ => return Err(BodyNotOneSwitchOnTheParam)
  }
  // Every arm must be `case "lit": return EXPR;`.
  // A single `default: return EXPR;` is also accepted: it acts as a
  // fallback for any union literal that doesn't have an explicit arm.
  let arms : Map[String, @ast.TsExpr] = {}
  let mut default_expr : @ast.TsExpr? = None
  for c in cases {
    match c.test_expr {
      Some(@ast.TsExpr::StringLit(s)) => {
        if c.body.stmts.length() != 1 {
          return Err(ArmNotASingleReturn)
        }
        let expr = match c.body.stmts[0] {
          Return(Some(e)) => e
          _ => return Err(ArmNotASingleReturn)
        }
        arms[s] = expr
      }
      None =>
        // `default:` arm — accept exactly one.
        if default_expr is None {
          if c.body.stmts.length() != 1 {
            return Err(ArmNotASingleReturn)
          }
          let expr = match c.body.stmts[0] {
            Return(Some(e)) => e
            _ => return Err(ArmNotASingleReturn)
          }
          default_expr = Some(expr)
        } else {
          // Two defaults — shouldn't happen but bail.
          return Err(CaseNotAStringLiteral)
        }
      _ => return Err(CaseNotAStringLiteral)
    }
  }
  // Fill in missing literals from the default arm (if any).
  match default_expr {
    Some(d) =>
      for l in literals {
        if !arms.contains(l) {
          arms[l] = d
        }
      }
    None =>
      // No default: every literal must have an explicit arm.
      for l in literals {
        if !arms.contains(l) {
          return Err(LiteralWithNoArm)
        }
      }
  }
  Ok({ param_names, switch_param_index: 0, arms })
}

///|
fn collect_switch_fold_shapes_stmt(
  stmt : @ast.TsStmt,
  out : Array[SwitchFoldReject?],
) -> Unit {
  match stmt {
    Var(_, _, e) | Let(_, _, e) | Const(_, _, e) | Expr(e) | Assign(_, e) =>
      collect_switch_fold_shapes_expr(e, out)
    Return(Some(e)) | Throw(e) => collect_switch_fold_shapes_expr(e, out)
    PropAssign(_, _, v) => collect_switch_fold_shapes_expr(v, out)
    If(_, t, e) => {
      collect_switch_fold_shapes_block(t, out)
      match e {
        Some(b) => collect_switch_fold_shapes_block(b, out)
        None => ()
      }
    }
    While(_, b)
    | DoWhile(_, b)
    | With(_, b)
    | ForOf(_, _, _, _, b)
    | ForAwaitOf(_, _, _, _, b)
    | ForIn(_, _, _, _, b)
    | Block(b) => collect_switch_fold_shapes_block(b, out)
    For(init, _, update, b) => {
      match init {
        Some(s) => collect_switch_fold_shapes_stmt(s, out)
        None => ()
      }
      match update {
        Some(s) => collect_switch_fold_shapes_stmt(s, out)
        None => ()
      }
      collect_switch_fold_shapes_block(b, out)
    }
    Switch(_, cases) =>
      for c in cases {
        collect_switch_fold_shapes_block(c.body, out)
      }
    Try(b, _, cb, fb) => {
      collect_switch_fold_shapes_block(b, out)
      match cb {
        Some(blk) => collect_switch_fold_shapes_block(blk, out)
        None => ()
      }
      match fb {
        Some(blk) => collect_switch_fold_shapes_block(blk, out)
        None => ()
      }
    }
    Label(_, inner) => collect_switch_fold_shapes_stmt(inner, out)
    NativeClassStmt(decl, ctor) => {
      match ctor {
        Some(f) => collect_switch_fold_shapes_func(f, out)
        None => ()
      }
      for m in decl.methods {
        match m.body {
          Some(b) => collect_switch_fold_shapes_block(b, out)
          None => ()
        }
      }
    }
    _ => ()
  }
}

///|
/// Only descends through the expression forms that can CARRY a
/// function body. The count is a diagnostic, so missing an exotic
/// nesting site understates it rather than making it wrong.
fn collect_switch_fold_shapes_expr(
  expr : @ast.TsExpr,
  out : Array[SwitchFoldReject?],
) -> Unit {
  match expr {
    FuncExpr(f) => collect_switch_fold_shapes_func(f, out)
    ArrowFunc(_, _, body, _) =>
      match body {
        ArrowExpr(e) => collect_switch_fold_shapes_expr(e, out)
        ArrowBlock(b) => collect_switch_fold_shapes_block(b, out)
      }
    Call(_, args) | New(_, args) =>
      for a in args {
        collect_switch_fold_shapes_expr(a, out)
      }
    MethodCall(recv, _, args) => {
      collect_switch_fold_shapes_expr(recv, out)
      for a in args {
        collect_switch_fold_shapes_expr(a, out)
      }
    }
    CallExpr(callee, args) | NewExpr(callee, args) => {
      collect_switch_fold_shapes_expr(callee, out)
      for a in args {
        collect_switch_fold_shapes_expr(a, out)
      }
    }
    BinOp(_, l, r) | Seq(l, r) => {
      collect_switch_fold_shapes_expr(l, out)
      collect_switch_fold_shapes_expr(r, out)
    }
    UnaryOp(_, i)
    | Await(i)
    | NonNull(i)
    | OptionalChain(i)
    | PureCall(i)
    | TypeArgs(_, i)
    | YieldStar(i) => collect_switch_fold_shapes_expr(i, out)
    Cond(c, t, e) => {
      collect_switch_fold_shapes_expr(c, out)
      collect_switch_fold_shapes_expr(t, out)
      collect_switch_fold_shapes_expr(e, out)
    }
    ArrayLit(items) =>
      for i in items {
        collect_switch_fold_shapes_expr(i, out)
      }
    ObjectLit(entries) =>
      for ent in entries {
        collect_switch_fold_shapes_expr(ent.1, out)
      }
    AssignExpr(_, v) | PropAssignExpr(_, _, v) =>
      collect_switch_fold_shapes_expr(v, out)
    Yield(Some(i)) => collect_switch_fold_shapes_expr(i, out)
    _ => ()
  }
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
  // Every nested block is a scope; the top-level entry walks statements
  // directly so the dispatchers' own declarations survive.
  let table = table.narrow_block(block)
  let stmts : Array[@ast.TsStmt] = []
  for s in block.stmts {
    stmts.push(switch_fold_stmt(s, table))
  }
  { stmts, stmt_positions: block.stmt_positions }
}

///|
fn switch_fold_stmt(stmt : @ast.TsStmt, table : SwitchFoldTable) -> @ast.TsStmt {
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
    For(init, cond, update, body) => {
      let inner = match init {
        Some(s) => {
          let names : Array[String] = []
          collect_stmt_bound_names(s, names)
          table.narrow(names)
        }
        None => table
      }
      For(
        match init {
          Some(s) => Some(switch_fold_stmt(s, table))
          None => None
        },
        match cond {
          Some(e) => Some(switch_fold_expr(e, inner))
          None => None
        },
        match update {
          Some(s) => Some(switch_fold_stmt(s, inner))
          None => None
        },
        switch_fold_block(body, inner),
      )
    }
    ForOf(k, b, t, iter, body) =>
      ForOf(
        k,
        b,
        t,
        switch_fold_expr(iter, table),
        switch_fold_block(body, table.narrow_binding(b)),
      )
    ForAwaitOf(k, b, t, iter, body) =>
      ForAwaitOf(
        k,
        b,
        t,
        switch_fold_expr(iter, table),
        switch_fold_block(body, table.narrow_binding(b)),
      )
    ForIn(k, b, t, iter, body) =>
      ForIn(
        k,
        b,
        t,
        switch_fold_expr(iter, table),
        switch_fold_block(body, table.narrow_binding(b)),
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
    Try(b, bnd, cb, fb) => {
      let catch_table = match bnd {
        Some(binding) => table.narrow_binding(binding)
        None => table
      }
      Try(
        switch_fold_block(b, table),
        bnd,
        match cb {
          Some(blk) => Some(switch_fold_block(blk, catch_table))
          None => None
        },
        match fb {
          Some(blk) => Some(switch_fold_block(blk, table))
          None => None
        },
      )
    }
    Label(name, inner) => Label(name, switch_fold_stmt(inner, table))
    Block(b) => Block(switch_fold_block(b, table))
    NativeClassStmt(decl, ctor) => {
      let new_ctor = match ctor {
        Some(f) =>
          Some({
            ..f,
            body: switch_fold_block(f.body, table.narrow_params(f.params)),
          })
        None => None
      }
      let new_methods : Array[@ast.TsClassMethodDecl] = []
      for m in decl.methods {
        let method_table = table.narrow_named_params(m.params)
        let new_body = match m.body {
          Some(b) => Some(switch_fold_block(b, method_table))
          None => None
        }
        new_methods.push({ ..m, body: new_body })
      }
      let new_static_fields : Array[(String, @ast.TsExpr)] = []
      for sf in decl.static_field_inits {
        new_static_fields.push((sf.0, switch_fold_expr(sf.1, table)))
      }
      let new_base_expr = match decl.base_expr {
        Some(b) => Some(switch_fold_expr(b, table))
        None => None
      }
      NativeClassStmt(
        {
          ..decl,
          base_expr: new_base_expr,
          methods: new_methods,
          static_field_inits: new_static_fields,
        },
        new_ctor,
      )
    }
  }
}

///|
fn switch_fold_expr(expr : @ast.TsExpr, table : SwitchFoldTable) -> @ast.TsExpr {
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
      // `CallExpr(Var(name), args)` — try the switch-fold rewrite
      // the same as the `Call(name, args)` form above.
      match callee {
        @ast.TsExpr::Var(name) =>
          match table.entries.get(name) {
            Some(entry) =>
              match try_fold_call(entry, args) {
                Some(folded) => return folded
                None => ()
              }
            None => ()
          }
        _ => ()
      }
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
      PropAssignExpr(
        switch_fold_expr(recv, table),
        p,
        switch_fold_expr(v, table),
      )
    IndexAssignExpr(recv, idx, v) =>
      IndexAssignExpr(
        switch_fold_expr(recv, table),
        switch_fold_expr(idx, table),
        switch_fold_expr(v, table),
      )
    ComputedProp(k, v) =>
      ComputedProp(switch_fold_expr(k, table), switch_fold_expr(v, table))
    ArrowFunc(params, ret, body, is_async) => {
      // A parameter shadowing a dispatcher is the case no block-level
      // check can see: `function sw(dispatch) { return dispatch("a") }`.
      let table = table.narrow_params(params)
      let new_body = match body {
        ArrowExpr(e) => @ast.TsArrowBody::ArrowExpr(switch_fold_expr(e, table))
        ArrowBlock(b) =>
          @ast.TsArrowBody::ArrowBlock(switch_fold_block(b, table))
      }
      ArrowFunc(params, ret, new_body, is_async)
    }
    FuncExpr(f) => {
      let table = table.narrow_params(f.params)
      let table = if f.name == "" { table } else { table.narrow([f.name]) }
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
    TypeArgs(tys, inner) => TypeArgs(tys, switch_fold_expr(inner, table))
    OptionalChain(inner) => OptionalChain(switch_fold_expr(inner, table))
    PureCall(inner) => PureCall(switch_fold_expr(inner, table))
    NativeClassExpr(decl, ctor) => {
      let new_ctor = match ctor {
        Some(f) => Some({ ..f, body: switch_fold_block(f.body, table) })
        None => None
      }
      let new_methods : Array[@ast.TsClassMethodDecl] = []
      for m in decl.methods {
        let new_body = match m.body {
          Some(b) => Some(switch_fold_block(b, table))
          None => None
        }
        new_methods.push({ ..m, body: new_body })
      }
      let new_static_fields : Array[(String, @ast.TsExpr)] = []
      for sf in decl.static_field_inits {
        new_static_fields.push((sf.0, switch_fold_expr(sf.1, table)))
      }
      let new_base_expr = match decl.base_expr {
        Some(b) => Some(switch_fold_expr(b, table))
        None => None
      }
      NativeClassExpr(
        {
          ..decl,
          base_expr: new_base_expr,
          methods: new_methods,
          static_field_inits: new_static_fields,
        },
        new_ctor,
      )
    }
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
    if !is_trivially_substitutable(args[i]) {
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
    StringLit(_)
    | NumberLit(_)
    | IntLit(_)
    | BoolLit(_)
    | NullLit
    | BigIntLit(_)
    | Var(_) => true
    _ => false
  }
}
