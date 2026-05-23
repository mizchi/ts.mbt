// Dead-declaration elimination for a runtime statement block.
//
// `tree_shake_block` keeps a top-level declaration only when it is in
// the supplied root set or transitively referenced from a root. Stmts
// that aren't pure declarations (top-level calls, assignments, control
// flow with side effects, etc.) are always kept — we can't tell from
// the AST alone whether they have observable effects, and dropping a
// `console.log(...)` that the user wrote is worse than missing a
// theoretical size win.
//
// The pass is purely structural — it doesn't know about the type
// system, side-effect freedom, or import semantics. The bundle layer
// drives the root set by computing, per module, which of its exports
// are consumed by some live downstream module.
//
//   block + roots ──► tree_shake_block ──► block (dead decls dropped)

///|
/// Drop top-level `let` / `const` / `var` declarations whose bound
/// name is neither in `roots` nor reachable from a root. Roots are
/// typically the module's exported names plus anything the consuming
/// module imports from it. The pass keeps the order of surviving
/// stmts unchanged.
pub fn tree_shake_block(
  block : @ast.TsBlock,
  roots : Array[String],
) -> @ast.TsBlock {
  // 1. For each top-level stmt, decide whether it's a "named decl"
  //    we can drop (Let/Const/Var binding an Ident) or a "keeper"
  //    (any other shape — side-effect, control flow, assignment).
  let n = block.stmts.length()
  let decl_name : Array[String?] = Array::make(n, None)
  let refs_per_stmt : Array[Map[String, Bool]] = Array::make(n, {})
  for i, stmt in block.stmts {
    decl_name[i] = decl_binding_name(stmt)
    let refs : Map[String, Bool] = {}
    collect_refs_in_stmt(stmt, refs)
    refs_per_stmt[i] = refs
  }
  // 2. Seed `live` with every name in `roots` plus every name
  //    bound by a keeper stmt. Keeper stmts also propagate their
  //    references into `live` (they will be emitted, so anything
  //    they reach has to survive too).
  let live : Map[String, Bool] = {}
  for r in roots {
    live[r] = true
  }
  let keeper : Array[Bool] = Array::make(n, false)
  for i, stmt in block.stmts {
    match decl_name[i] {
      None => {
        // Non-decl stmt — always kept.
        keeper[i] = true
        for k in refs_per_stmt[i] {
          live[k.0] = true
        }
      }
      Some(_) => ()
    }
    let _ = stmt
  }
  // 3. Fixed-point: when a named decl's name becomes live, mark
  //    every name it references as live too. Repeat until stable.
  let mut changed = true
  while changed {
    changed = false
    for i in 0..<n {
      match decl_name[i] {
        Some(name) =>
          if live.contains(name) {
            for k in refs_per_stmt[i] {
              if !live.contains(k.0) {
                live[k.0] = true
                changed = true
              }
            }
          }
        None => ()
      }
    }
  }
  // 4. Filter — keep every keeper plus every named decl whose
  //    binding is live.
  let kept_stmts : Array[@ast.TsStmt] = []
  let kept_positions : Array[Int] = []
  let has_positions = block.stmt_positions.length() == n
  for i, stmt in block.stmts {
    let alive = match decl_name[i] {
      Some(name) => live.contains(name)
      None => true
    }
    if alive {
      kept_stmts.push(stmt)
      if has_positions {
        kept_positions.push(block.stmt_positions[i])
      }
    }
  }
  { stmts: kept_stmts, stmt_positions: kept_positions }
}

///|
/// If `stmt` is a top-level Let/Const/Var binding a single Ident,
/// return that name. Returns `None` for destructuring patterns
/// (we can't safely drop those without losing the binding shape)
/// and for any other stmt kind.
fn decl_binding_name(stmt : @ast.TsStmt) -> String? {
  match stmt {
    Let(@ast.TsBinding::Ident(name), _, _)
    | Const(@ast.TsBinding::Ident(name), _, _)
    | Var(@ast.TsBinding::Ident(name), _, _) => Some(name)
    _ => None
  }
}

// ---------------------------------------------------------------------------
// Reference collection — walk a stmt's RHS / body and record every
// `Var(name)` / `Call(name, …)` it reaches. We deliberately *don't*
// recurse into nested function bodies for the purpose of "what
// top-level names does this stmt need", because shadowing analysis
// would require full scope tracking. Recursion into nested funcs is
// safe over-approximation: it may keep more than necessary, never
// fewer. For v0 we just walk everything.
// ---------------------------------------------------------------------------

///|
fn collect_refs_in_stmt(stmt : @ast.TsStmt, out : Map[String, Bool]) -> Unit {
  match stmt {
    Var(b, _, e) | Let(b, _, e) | Const(b, _, e) => {
      collect_refs_in_binding(b, out)
      collect_refs_in_expr(e, out)
    }
    Expr(e) | Throw(e) => collect_refs_in_expr(e, out)
    Return(opt) =>
      match opt {
        Some(e) => collect_refs_in_expr(e, out)
        None => ()
      }
    Assign(name, e) => {
      out[name] = true
      collect_refs_in_expr(e, out)
    }
    CompoundAssign(name, _, e) => {
      out[name] = true
      collect_refs_in_expr(e, out)
    }
    PropAssign(recv, _, value) => {
      collect_refs_in_expr(recv, out)
      collect_refs_in_expr(value, out)
    }
    IndexAssign(recv, idx, value) => {
      collect_refs_in_expr(recv, out)
      collect_refs_in_expr(idx, out)
      collect_refs_in_expr(value, out)
    }
    If(c, t, e_opt) => {
      collect_refs_in_expr(c, out)
      collect_refs_in_block(t, out)
      match e_opt {
        Some(b) => collect_refs_in_block(b, out)
        None => ()
      }
    }
    While(c, b) | DoWhile(c, b) => {
      collect_refs_in_expr(c, out)
      collect_refs_in_block(b, out)
    }
    For(init_opt, cond_opt, update_opt, body) => {
      match init_opt {
        Some(s) => collect_refs_in_stmt(s, out)
        None => ()
      }
      match cond_opt {
        Some(c) => collect_refs_in_expr(c, out)
        None => ()
      }
      match update_opt {
        Some(s) => collect_refs_in_stmt(s, out)
        None => ()
      }
      collect_refs_in_block(body, out)
    }
    ForOf(_, b, _, iter, body)
    | ForAwaitOf(_, b, _, iter, body)
    | ForIn(_, b, _, iter, body) => {
      collect_refs_in_binding(b, out)
      collect_refs_in_expr(iter, out)
      collect_refs_in_block(body, out)
    }
    Switch(scrut, cases) => {
      collect_refs_in_expr(scrut, out)
      for c in cases {
        match c.test_expr {
          Some(t) => collect_refs_in_expr(t, out)
          None => ()
        }
        collect_refs_in_block(c.body, out)
      }
    }
    Try(t, _, c, f) => {
      collect_refs_in_block(t, out)
      match c {
        Some(b) => collect_refs_in_block(b, out)
        None => ()
      }
      match f {
        Some(b) => collect_refs_in_block(b, out)
        None => ()
      }
    }
    Block(b) => collect_refs_in_block(b, out)
    Label(_, inner) => collect_refs_in_stmt(inner, out)
    With(target, body) => {
      collect_refs_in_expr(target, out)
      collect_refs_in_block(body, out)
    }
    Break(_) | Continue(_) | Empty | Debugger => ()
  }
}

///|
fn collect_refs_in_block(
  block : @ast.TsBlock,
  out : Map[String, Bool],
) -> Unit {
  for s in block.stmts {
    collect_refs_in_stmt(s, out)
  }
}

///|
fn collect_refs_in_binding(
  binding : @ast.TsBinding,
  out : Map[String, Bool],
) -> Unit {
  match binding {
    Ident(_) => ()
    Array(ab) => {
      for elem in ab.items {
        match elem {
          Some(be) => {
            collect_refs_in_binding(be.binding, out)
            match be.default {
              Some(d) => collect_refs_in_expr(d, out)
              None => ()
            }
          }
          None => ()
        }
      }
      match ab.rest {
        Some(r) => collect_refs_in_binding(r, out)
        None => ()
      }
    }
    Object(ob) =>
      for p in ob.props {
        // Computed keys (`{ [k]: local }`) reference `k` from the
        // surrounding scope — the reference walker has to follow
        // through `key_expr` or tree-shake silently drops the
        // computed-key binding.
        match p.key_expr {
          Some(k) => collect_refs_in_expr(k, out)
          None => ()
        }
        collect_refs_in_binding(p.binding, out)
        match p.default {
          Some(d) => collect_refs_in_expr(d, out)
          None => ()
        }
      }
    Target(e) => collect_refs_in_expr(e, out)
  }
}

///|
fn collect_refs_in_expr(expr : @ast.TsExpr, out : Map[String, Bool]) -> Unit {
  match expr {
    Var(name) => out[name] = true
    Call(name, args) => {
      out[name] = true
      for a in args {
        collect_refs_in_expr(a, out)
      }
    }
    CallExpr(callee, args) => {
      collect_refs_in_expr(callee, out)
      for a in args {
        collect_refs_in_expr(a, out)
      }
    }
    New(name, args) => {
      out[name] = true
      for a in args {
        collect_refs_in_expr(a, out)
      }
    }
    NewExpr(callee, args) => {
      collect_refs_in_expr(callee, out)
      for a in args {
        collect_refs_in_expr(a, out)
      }
    }
    MethodCall(recv, _, args) => {
      collect_refs_in_expr(recv, out)
      for a in args {
        collect_refs_in_expr(a, out)
      }
    }
    BinOp(_, l, r) | Seq(l, r) => {
      collect_refs_in_expr(l, out)
      collect_refs_in_expr(r, out)
    }
    UnaryOp(_, e) | Spread(e) | Await(e) | YieldStar(e) | NonNull(e) =>
      collect_refs_in_expr(e, out)
    OptionalChain(e) => collect_refs_in_expr(e, out)
    Yield(opt) =>
      match opt {
        Some(e) => collect_refs_in_expr(e, out)
        None => ()
      }
    Cond(c, t, f) => {
      collect_refs_in_expr(c, out)
      collect_refs_in_expr(t, out)
      collect_refs_in_expr(f, out)
    }
    ArrayLit(items) =>
      for it in items {
        collect_refs_in_expr(it, out)
      }
    ObjectLit(pairs) =>
      for p in pairs {
        collect_refs_in_expr(p.1, out)
      }
    ComputedProp(k, v) => {
      collect_refs_in_expr(k, out)
      collect_refs_in_expr(v, out)
    }
    IndexAccess(b, k) => {
      collect_refs_in_expr(b, out)
      collect_refs_in_expr(k, out)
    }
    PropAccess(b, _) => collect_refs_in_expr(b, out)
    AssignExpr(name, e) => {
      out[name] = true
      collect_refs_in_expr(e, out)
    }
    AssignPattern(b, e) => {
      collect_refs_in_binding(b, out)
      collect_refs_in_expr(e, out)
    }
    CompoundAssignExpr(target, _, e) => {
      collect_refs_in_expr(target, out)
      collect_refs_in_expr(e, out)
    }
    PropAssignExpr(recv, _, value) => {
      collect_refs_in_expr(recv, out)
      collect_refs_in_expr(value, out)
    }
    IndexAssignExpr(recv, idx, value) => {
      collect_refs_in_expr(recv, out)
      collect_refs_in_expr(idx, out)
      collect_refs_in_expr(value, out)
    }
    ArrowFunc(params, _, body, _) => {
      for p in params {
        match p.binding {
          Some(b) => collect_refs_in_binding(b, out)
          None => ()
        }
      }
      match body {
        ArrowExpr(e) => collect_refs_in_expr(e, out)
        ArrowBlock(b) => collect_refs_in_block(b, out)
      }
    }
    FuncExpr(f) => {
      for p in f.params {
        match p.binding {
          Some(b) => collect_refs_in_binding(b, out)
          None => ()
        }
      }
      collect_refs_in_block(f.body, out)
    }
    TaggedTemplate(tag, _, _, exprs) => {
      collect_refs_in_expr(tag, out)
      for e in exprs {
        collect_refs_in_expr(e, out)
      }
    }
    TemplateLiteral(_, exprs) =>
      for e in exprs {
        collect_refs_in_expr(e, out)
      }
    As(e, _) | Satisfies(e, _) => collect_refs_in_expr(e, out)
    DynamicImport(spec, opt) => {
      collect_refs_in_expr(spec, out)
      match opt {
        Some(o) => collect_refs_in_expr(o, out)
        None => ()
      }
    }
    _ => ()
  }
}
