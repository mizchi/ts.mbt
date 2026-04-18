// Loop invariant analysis - detect expressions that can be hoisted out of loops.

///|
/// A loop invariant expression that can be hoisted.
pub(all) struct LoopInvariant {
  expr : @ast.TsExpr
  // Variables this expression depends on
  depends_on : Array[String]
  // Is this expression pure?
  is_pure : Bool
}

///|
/// Information about loop invariants in a function.
pub(all) struct LoopInvariantInfo {
  // Expressions that can be hoisted out of loops
  invariants : Array[LoopInvariant]
  // Variables modified in the loop
  modified_vars : Array[String]
}

///|
pub fn LoopInvariantInfo::new() -> LoopInvariantInfo {
  { invariants: [], modified_vars: [] }
}

///|
/// Analyze a loop for invariant expressions.
pub fn analyze_loop_invariants(
  cond : @ast.TsExpr?,
  body : @ast.TsBlock,
) -> LoopInvariantInfo {
  let info = LoopInvariantInfo::new()
  // First, find all variables modified in the loop
  for stmt in body.stmts {
    collect_modified_vars(stmt, info.modified_vars)
  }
  // Then find invariant expressions
  match cond {
    Some(c) => find_invariants_in_expr(c, info)
    None => ()
  }
  for stmt in body.stmts {
    find_invariants_in_stmt(stmt, info)
  }
  info
}

///|
/// Collect variables that are modified in a statement.
fn collect_modified_vars(stmt : @ast.TsStmt, vars : Array[String]) -> Unit {
  match stmt {
    @ast.TsStmt::Assign(name, _) => if !vars.contains(name) { vars.push(name) }
    @ast.TsStmt::Var(binding, _, _)
    | @ast.TsStmt::Let(binding, _, _)
    | @ast.TsStmt::Const(binding, _, _) => {
      let names : Array[String] = []
      collect_binding_names(binding, names)
      for name in names {
        if !vars.contains(name) {
          vars.push(name)
        }
      }
    }
    @ast.TsStmt::CompoundAssign(name, _, _) =>
      if !vars.contains(name) {
        vars.push(name)
      }
    @ast.TsStmt::Expr(e) => collect_modified_vars_in_expr(e, vars)
    @ast.TsStmt::If(_, then_block, else_block) => {
      for s in then_block.stmts {
        collect_modified_vars(s, vars)
      }
      match else_block {
        Some(eb) =>
          for s in eb.stmts {
            collect_modified_vars(s, vars)
          }
        None => ()
      }
    }
    @ast.TsStmt::Block(block) =>
      for s in block.stmts {
        collect_modified_vars(s, vars)
      }
    @ast.TsStmt::While(_, body) | @ast.TsStmt::DoWhile(_, body) =>
      for s in body.stmts {
        collect_modified_vars(s, vars)
      }
    @ast.TsStmt::For(init, _, update, body) => {
      match init {
        Some(i) => collect_modified_vars(i, vars)
        None => ()
      }
      match update {
        Some(u) => collect_modified_vars(u, vars)
        None => ()
      }
      for s in body.stmts {
        collect_modified_vars(s, vars)
      }
    }
    _ => ()
  }
}

///|
fn collect_modified_vars_in_expr(
  expr : @ast.TsExpr,
  vars : Array[String],
) -> Unit {
  match expr {
    @ast.TsExpr::AssignExpr(name, _) =>
      if !vars.contains(name) {
        vars.push(name)
      }
    @ast.TsExpr::CompoundAssignExpr(target, _, _) =>
      match target {
        @ast.TsExpr::Var(name) => if !vars.contains(name) { vars.push(name) }
        _ => ()
      }
    @ast.TsExpr::UnaryOp(op, operand) =>
      match op {
        @ast.TsUnaryOp::PreInc
        | @ast.TsUnaryOp::PreDec
        | @ast.TsUnaryOp::PostInc
        | @ast.TsUnaryOp::PostDec =>
          match operand {
            @ast.TsExpr::Var(name) =>
              if !vars.contains(name) {
                vars.push(name)
              }
            _ => ()
          }
        _ => ()
      }
    @ast.TsExpr::Call(_, args) =>
      for arg in args {
        collect_modified_vars_in_expr(arg, vars)
      }
    @ast.TsExpr::CallExpr(callee, args) => {
      collect_modified_vars_in_expr(callee, vars)
      for arg in args {
        collect_modified_vars_in_expr(arg, vars)
      }
    }
    @ast.TsExpr::MethodCall(recv, _, args) => {
      collect_modified_vars_in_expr(recv, vars)
      for arg in args {
        collect_modified_vars_in_expr(arg, vars)
      }
    }
    @ast.TsExpr::BinOp(_, left, right) => {
      collect_modified_vars_in_expr(left, vars)
      collect_modified_vars_in_expr(right, vars)
    }
    @ast.TsExpr::Cond(cond, then_e, else_e) => {
      collect_modified_vars_in_expr(cond, vars)
      collect_modified_vars_in_expr(then_e, vars)
      collect_modified_vars_in_expr(else_e, vars)
    }
    @ast.TsExpr::Seq(left, right) => {
      collect_modified_vars_in_expr(left, vars)
      collect_modified_vars_in_expr(right, vars)
    }
    _ => ()
  }
}

///|
/// Find invariant expressions in a statement.
fn find_invariants_in_stmt(
  stmt : @ast.TsStmt,
  info : LoopInvariantInfo,
) -> Unit {
  match stmt {
    @ast.TsStmt::Expr(e) => find_invariants_in_expr(e, info)
    @ast.TsStmt::Return(Some(e)) => find_invariants_in_expr(e, info)
    @ast.TsStmt::Var(_, _, init)
    | @ast.TsStmt::Let(_, _, init)
    | @ast.TsStmt::Const(_, _, init) => find_invariants_in_expr(init, info)
    @ast.TsStmt::Assign(_, e) => find_invariants_in_expr(e, info)
    @ast.TsStmt::If(cond, then_block, else_block) => {
      find_invariants_in_expr(cond, info)
      for s in then_block.stmts {
        find_invariants_in_stmt(s, info)
      }
      match else_block {
        Some(eb) =>
          for s in eb.stmts {
            find_invariants_in_stmt(s, info)
          }
        None => ()
      }
    }
    @ast.TsStmt::Block(block) =>
      for s in block.stmts {
        find_invariants_in_stmt(s, info)
      }
    _ => ()
  }
}

///|
/// Find invariant expressions.
fn find_invariants_in_expr(
  expr : @ast.TsExpr,
  info : LoopInvariantInfo,
) -> Unit {
  // Check if this expression is loop invariant
  if is_loop_invariant(expr, info.modified_vars) {
    let deps : Array[String] = []
    collect_var_deps(expr, deps)
    let purity = analyze_expr_purity(expr)
    info.invariants.push({ expr, depends_on: deps, is_pure: purity.is_pure })
  }
  // Recurse into sub-expressions to find more invariants
  match expr {
    @ast.TsExpr::BinOp(_, left, right) => {
      find_invariants_in_expr(left, info)
      find_invariants_in_expr(right, info)
    }
    @ast.TsExpr::UnaryOp(_, operand) => find_invariants_in_expr(operand, info)
    @ast.TsExpr::Call(_, args) =>
      for arg in args {
        find_invariants_in_expr(arg, info)
      }
    @ast.TsExpr::CallExpr(callee, args) => {
      find_invariants_in_expr(callee, info)
      for arg in args {
        find_invariants_in_expr(arg, info)
      }
    }
    @ast.TsExpr::MethodCall(recv, _, args) => {
      find_invariants_in_expr(recv, info)
      for arg in args {
        find_invariants_in_expr(arg, info)
      }
    }
    @ast.TsExpr::PropAccess(obj, _) => find_invariants_in_expr(obj, info)
    @ast.TsExpr::IndexAccess(arr, idx) => {
      find_invariants_in_expr(arr, info)
      find_invariants_in_expr(idx, info)
    }
    @ast.TsExpr::Cond(cond, then_e, else_e) => {
      find_invariants_in_expr(cond, info)
      find_invariants_in_expr(then_e, info)
      find_invariants_in_expr(else_e, info)
    }
    @ast.TsExpr::ArrayLit(elements) =>
      for elem in elements {
        find_invariants_in_expr(elem, info)
      }
    _ => ()
  }
}

///|
/// Check if an expression is loop invariant (doesn't depend on modified vars).
fn is_loop_invariant(expr : @ast.TsExpr, modified : Array[String]) -> Bool {
  match expr {
    // Literals are always invariant
    @ast.TsExpr::IntLit(_)
    | @ast.TsExpr::NumberLit(_)
    | @ast.TsExpr::StringLit(_)
    | @ast.TsExpr::BoolLit(_)
    | @ast.TsExpr::NullLit
    | @ast.TsExpr::ArrayHole => true
    // Variable is invariant if not modified
    @ast.TsExpr::Var(name) => !modified.contains(name)
    // Binary op is invariant if both operands are
    @ast.TsExpr::BinOp(_, left, right) =>
      is_loop_invariant(left, modified) && is_loop_invariant(right, modified)
    // Unary op is invariant if operand is
    @ast.TsExpr::UnaryOp(op, operand) =>
      match op {
        // Inc/dec modify the variable
        @ast.TsUnaryOp::PreInc
        | @ast.TsUnaryOp::PreDec
        | @ast.TsUnaryOp::PostInc
        | @ast.TsUnaryOp::PostDec => false
        _ => is_loop_invariant(operand, modified)
      }
    // Property access is invariant if object is and method is pure
    @ast.TsExpr::PropAccess(obj, prop) =>
      // Special case: arr.length is invariant if arr is not modified
      if prop == "length" {
        is_loop_invariant(obj, modified)
      } else {
        false // Other property accesses may not be invariant
      }
    // Index access is usually not invariant (array may change)
    @ast.TsExpr::IndexAccess(_, _) => false
    // Calls are usually not invariant (may have side effects)
    @ast.TsExpr::Call(_, _)
    | @ast.TsExpr::CallExpr(_, _)
    | @ast.TsExpr::MethodCall(_, _, _) => false
    // Assignments are never invariant
    @ast.TsExpr::AssignExpr(_, _)
    | @ast.TsExpr::AssignPattern(_, _)
    | @ast.TsExpr::CompoundAssignExpr(_, _, _) => false
    // Conditional is invariant if all parts are
    @ast.TsExpr::Cond(cond, then_e, else_e) =>
      is_loop_invariant(cond, modified) &&
      is_loop_invariant(then_e, modified) &&
      is_loop_invariant(else_e, modified)
    _ => false
  }
}

///|
/// Collect variable dependencies of an expression.
fn collect_var_deps(expr : @ast.TsExpr, deps : Array[String]) -> Unit {
  match expr {
    @ast.TsExpr::Var(name) => if !deps.contains(name) { deps.push(name) }
    @ast.TsExpr::BinOp(_, left, right) => {
      collect_var_deps(left, deps)
      collect_var_deps(right, deps)
    }
    @ast.TsExpr::UnaryOp(_, operand) => collect_var_deps(operand, deps)
    @ast.TsExpr::PropAccess(obj, _) => collect_var_deps(obj, deps)
    @ast.TsExpr::IndexAccess(arr, idx) => {
      collect_var_deps(arr, deps)
      collect_var_deps(idx, deps)
    }
    @ast.TsExpr::Call(_, args) =>
      for arg in args {
        collect_var_deps(arg, deps)
      }
    @ast.TsExpr::Cond(cond, then_e, else_e) => {
      collect_var_deps(cond, deps)
      collect_var_deps(then_e, deps)
      collect_var_deps(else_e, deps)
    }
    _ => ()
  }
}

///|
/// Analyze a function for loop invariants.
pub fn analyze_func_loop_invariants(
  func : @ast.TsFunc,
) -> Array[LoopInvariantInfo] {
  let results : Array[LoopInvariantInfo] = []
  for stmt in func.body.stmts {
    find_loops_and_analyze(stmt, results)
  }
  results
}

///|
fn find_loops_and_analyze(
  stmt : @ast.TsStmt,
  results : Array[LoopInvariantInfo],
) -> Unit {
  match stmt {
    @ast.TsStmt::While(cond, body) =>
      results.push(analyze_loop_invariants(Some(cond), body))
    @ast.TsStmt::DoWhile(cond, body) =>
      results.push(analyze_loop_invariants(Some(cond), body))
    @ast.TsStmt::For(_, cond, _, body) =>
      results.push(analyze_loop_invariants(cond, body))
    @ast.TsStmt::ForOf(_, _, _, _, body)
    | @ast.TsStmt::ForAwaitOf(_, _, _, _, body)
    | @ast.TsStmt::ForIn(_, _, _, _, body) =>
      results.push(analyze_loop_invariants(None, body))
    @ast.TsStmt::If(_, then_block, else_block) => {
      for s in then_block.stmts {
        find_loops_and_analyze(s, results)
      }
      match else_block {
        Some(eb) =>
          for s in eb.stmts {
            find_loops_and_analyze(s, results)
          }
        None => ()
      }
    }
    @ast.TsStmt::Block(block) =>
      for s in block.stmts {
        find_loops_and_analyze(s, results)
      }
    @ast.TsStmt::Try(try_block, _, catch_block, finally_block) => {
      for s in try_block.stmts {
        find_loops_and_analyze(s, results)
      }
      match catch_block {
        Some(cb) =>
          for s in cb.stmts {
            find_loops_and_analyze(s, results)
          }
        None => ()
      }
      match finally_block {
        Some(fb) =>
          for s in fb.stmts {
            find_loops_and_analyze(s, results)
          }
        None => ()
      }
    }
    _ => ()
  }
}
