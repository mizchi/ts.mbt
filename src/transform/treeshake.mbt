// Bundle-level tree-shaking pass.
//
// `treeshake_block` takes the merged top-level block produced by the
// bundler and removes name-binding declarations that aren't reachable
// from any side-effect statement. The pass is intentionally
// conservative: it only drops a declaration when (a) it's a single-
// name binding and (b) its initializer is statically pure (literal,
// function expression, arrow, object/array literal of pure values).
// Anything else is treated as a side-effect root and kept verbatim.
//
// Cross-function references over-approximate: a function body's
// inner references count toward the names it pulls in, even when an
// inner local shadows a top-level binding. That over-approximation
// keeps live code; it only costs a marginal amount of dead bytes,
// which is acceptable for a v0 pass.

///|
priv struct DeclEntry {
  name : String
  // Index into the block's `stmts` array — preserves original order
  // when we re-emit the kept declarations.
  index : Int
  // Names referenced by the rhs of this declaration. Computed once
  // and cached so the BFS doesn't re-walk function bodies.
  refs : Map[String, Bool]
}

///|
/// Drop top-level declarations that no live statement transitively
/// references. Only run me on a flattened bundle block — sub-blocks
/// (function bodies, control flow) are left alone.
pub fn treeshake_block(block : @ast.TsBlock) -> @ast.TsBlock {
  // Pass 1: classify every stmt as either a droppable declaration
  // (single name + pure rhs) or a side-effect root. Build a name ->
  // DeclEntry index for the BFS.
  let decls : Array[DeclEntry] = []
  let decl_by_name : Map[String, Int] = {}
  let is_decl : Array[Bool] = []
  for stmt in block.stmts {
    let _ = stmt
    is_decl.push(false)
  }
  for i, stmt in block.stmts {
    match stmt {
      Let(@ast.TsBinding::Ident(name), _, rhs)
      | Const(@ast.TsBinding::Ident(name), _, rhs)
      | Var(@ast.TsBinding::Ident(name), _, rhs) =>
        if is_pure_init(rhs) {
          let refs : Map[String, Bool] = {}
          collect_var_refs_in_expr(rhs, refs)
          decl_by_name[name] = decls.length()
          decls.push({ name, index: i, refs })
          is_decl[i] = true
        }
      _ => ()
    }
  }

  // Pass 2: seed the live set with every name that appears in a
  // root (non-droppable) stmt. Walk the stmt's full expression tree.
  let live : Map[String, Bool] = {}
  let worklist : Array[String] = []
  for i, stmt in block.stmts {
    if is_decl[i] {
      continue
    }
    let refs : Map[String, Bool] = {}
    collect_var_refs_in_stmt(stmt, refs)
    for r in refs.keys() {
      if decl_by_name.contains(r) && !live.contains(r) {
        live[r] = true
        worklist.push(r)
      }
    }
  }

  // Pass 3: BFS through decl-to-decl references.
  while worklist.length() > 0 {
    let n = worklist[worklist.length() - 1]
    let _ = worklist.pop()
    let idx = match decl_by_name.get(n) {
      Some(i) => i
      None => continue
    }
    for r in decls[idx].refs.keys() {
      if decl_by_name.contains(r) && !live.contains(r) {
        live[r] = true
        worklist.push(r)
      }
    }
  }

  // Pass 4: re-emit. Keep every root stmt in order; keep declarations
  // only when their name is live. Statement positions are dropped —
  // they no longer line up with the original module and source maps
  // aren't emitted in mangle mode anyway.
  let kept : Array[@ast.TsStmt] = []
  for i, stmt in block.stmts {
    if is_decl[i] {
      let name = match stmt {
        Let(@ast.TsBinding::Ident(n), _, _)
        | Const(@ast.TsBinding::Ident(n), _, _)
        | Var(@ast.TsBinding::Ident(n), _, _) => n
        _ => ""
      }
      if live.contains(name) {
        kept.push(stmt)
      }
    } else {
      kept.push(stmt)
    }
  }
  { stmts: kept, stmt_positions: [] }
}

///|
/// Return `true` when `expr` is statically pure — safe to drop along
/// with its enclosing declaration if no live reference remains.
fn is_pure_init(expr : @ast.TsExpr) -> Bool {
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
    ArrayLit(items) => {
      for e in items {
        if not(is_pure_init(e)) {
          return false
        }
      }
      true
    }
    ObjectLit(entries) => {
      for ent in entries {
        if not(is_pure_init(ent.1)) {
          return false
        }
      }
      true
    }
    UnaryOp(_, inner) => is_pure_init(inner)
    BinOp(_, l, r) => is_pure_init(l) && is_pure_init(r)
    Cond(c, t, e) => is_pure_init(c) && is_pure_init(t) && is_pure_init(e)
    _ => false
  }
}

///|
/// Collect every name that `stmt` references in an rvalue position
/// (i.e. names that would resolve to a binding). `Var(n)` counts;
/// the receivers of `Call(n, args)`, `New(n, args)`,
/// `AssignExpr(n, _)`, `CompoundAssignExpr(_, _, _)` all count.
fn collect_var_refs_in_stmt(
  stmt : @ast.TsStmt,
  out : Map[String, Bool],
) -> Unit {
  match stmt {
    Var(b, _, rhs) | Let(b, _, rhs) | Const(b, _, rhs) => {
      let _ = b
      collect_var_refs_in_expr(rhs, out)
    }
    Assign(name, rhs) => {
      out[name] = true
      collect_var_refs_in_expr(rhs, out)
    }
    CompoundAssign(name, _, rhs) => {
      out[name] = true
      collect_var_refs_in_expr(rhs, out)
    }
    IndexAssign(target, idx, val) => {
      collect_var_refs_in_expr(target, out)
      collect_var_refs_in_expr(idx, out)
      collect_var_refs_in_expr(val, out)
    }
    PropAssign(target, _, val) => {
      collect_var_refs_in_expr(target, out)
      collect_var_refs_in_expr(val, out)
    }
    Expr(e) | Throw(e) => collect_var_refs_in_expr(e, out)
    Return(Some(e)) => collect_var_refs_in_expr(e, out)
    Return(None) | Empty | Debugger | Break(_) | Continue(_) => ()
    If(c, t, e) => {
      collect_var_refs_in_expr(c, out)
      collect_var_refs_in_block(t, out)
      match e {
        Some(b) => collect_var_refs_in_block(b, out)
        None => ()
      }
    }
    While(c, body) | DoWhile(c, body) | With(c, body) => {
      collect_var_refs_in_expr(c, out)
      collect_var_refs_in_block(body, out)
    }
    For(init, cond, update, body) => {
      match init {
        Some(s) => collect_var_refs_in_stmt(s, out)
        None => ()
      }
      match cond {
        Some(e) => collect_var_refs_in_expr(e, out)
        None => ()
      }
      match update {
        Some(s) => collect_var_refs_in_stmt(s, out)
        None => ()
      }
      collect_var_refs_in_block(body, out)
    }
    ForOf(_, _, _, iter, body)
    | ForAwaitOf(_, _, _, iter, body)
    | ForIn(_, _, _, iter, body) => {
      collect_var_refs_in_expr(iter, out)
      collect_var_refs_in_block(body, out)
    }
    Switch(e, cases) => {
      collect_var_refs_in_expr(e, out)
      for c in cases {
        match c.test_expr {
          Some(t) => collect_var_refs_in_expr(t, out)
          None => ()
        }
        collect_var_refs_in_block(c.body, out)
      }
    }
    Try(b, _, catch_b, finally_b) => {
      collect_var_refs_in_block(b, out)
      match catch_b {
        Some(cb) => collect_var_refs_in_block(cb, out)
        None => ()
      }
      match finally_b {
        Some(fb) => collect_var_refs_in_block(fb, out)
        None => ()
      }
    }
    Label(_, inner) => collect_var_refs_in_stmt(inner, out)
    Block(b) => collect_var_refs_in_block(b, out)
    NativeClassStmt(_, _) => ()
  }
}

///|
fn collect_var_refs_in_block(
  block : @ast.TsBlock,
  out : Map[String, Bool],
) -> Unit {
  for s in block.stmts {
    collect_var_refs_in_stmt(s, out)
  }
}

///|
fn collect_var_refs_in_expr(
  expr : @ast.TsExpr,
  out : Map[String, Bool],
) -> Unit {
  match expr {
    Var(n) => out[n] = true
    Call(n, args) | New(n, args) => {
      out[n] = true
      for a in args {
        collect_var_refs_in_expr(a, out)
      }
    }
    CallExpr(callee, args) | NewExpr(callee, args) => {
      collect_var_refs_in_expr(callee, out)
      for a in args {
        collect_var_refs_in_expr(a, out)
      }
    }
    MethodCall(recv, _, args) => {
      collect_var_refs_in_expr(recv, out)
      for a in args {
        collect_var_refs_in_expr(a, out)
      }
    }
    BinOp(_, l, r) => {
      collect_var_refs_in_expr(l, out)
      collect_var_refs_in_expr(r, out)
    }
    UnaryOp(_, inner) | Spread(inner) | Await(inner) | YieldStar(inner) =>
      collect_var_refs_in_expr(inner, out)
    Yield(opt) =>
      match opt {
        Some(e) => collect_var_refs_in_expr(e, out)
        None => ()
      }
    Cond(c, t, e) => {
      collect_var_refs_in_expr(c, out)
      collect_var_refs_in_expr(t, out)
      collect_var_refs_in_expr(e, out)
    }
    ArrayLit(items) =>
      for i in items {
        collect_var_refs_in_expr(i, out)
      }
    ObjectLit(entries) =>
      for ent in entries {
        collect_var_refs_in_expr(ent.1, out)
      }
    ComputedProp(k, v) => {
      collect_var_refs_in_expr(k, out)
      collect_var_refs_in_expr(v, out)
    }
    IndexAccess(recv, idx) => {
      collect_var_refs_in_expr(recv, out)
      collect_var_refs_in_expr(idx, out)
    }
    PropAccess(recv, _) => collect_var_refs_in_expr(recv, out)
    AssignExpr(name, value) => {
      out[name] = true
      collect_var_refs_in_expr(value, out)
    }
    CompoundAssignExpr(target, _, value) => {
      collect_var_refs_in_expr(target, out)
      collect_var_refs_in_expr(value, out)
    }
    AssignPattern(_, value) => collect_var_refs_in_expr(value, out)
    PropAssignExpr(recv, _, value) => {
      collect_var_refs_in_expr(recv, out)
      collect_var_refs_in_expr(value, out)
    }
    IndexAssignExpr(recv, idx, value) => {
      collect_var_refs_in_expr(recv, out)
      collect_var_refs_in_expr(idx, out)
      collect_var_refs_in_expr(value, out)
    }
    Seq(a, b) => {
      collect_var_refs_in_expr(a, out)
      collect_var_refs_in_expr(b, out)
    }
    ArrowFunc(params, _, body, _) => {
      for p in params {
        match p.default {
          Some(d) => collect_var_refs_in_expr(d, out)
          None => ()
        }
      }
      match body {
        ArrowExpr(e) => collect_var_refs_in_expr(e, out)
        ArrowBlock(b) => collect_var_refs_in_block(b, out)
      }
    }
    FuncExpr(f) => {
      for p in f.params {
        match p.default {
          Some(d) => collect_var_refs_in_expr(d, out)
          None => ()
        }
      }
      collect_var_refs_in_block(f.body, out)
    }
    DynamicImport(spec, opts) => {
      collect_var_refs_in_expr(spec, out)
      match opts {
        Some(o) => collect_var_refs_in_expr(o, out)
        None => ()
      }
    }
    TaggedTemplate(tag, _, _, exprs) => {
      collect_var_refs_in_expr(tag, out)
      for e in exprs {
        collect_var_refs_in_expr(e, out)
      }
    }
    TemplateLiteral(_, exprs) =>
      for e in exprs {
        collect_var_refs_in_expr(e, out)
      }
    As(inner, _)
    | Satisfies(inner, _)
    | NonNull(inner)
    | OptionalChain(inner) => collect_var_refs_in_expr(inner, out)
    _ => ()
  }
}
