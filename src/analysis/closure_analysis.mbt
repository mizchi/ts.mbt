// Closure Analysis - Analyze closures for AOT compilation.

///|
/// Information about a captured variable.
pub struct CapturedVar {
  name : String
  /// Whether the variable is written to inside the closure
  is_mutated : Bool
  /// Type hint (if known)
  type_hint : @ast.TsType?
}

///|
/// Information about a closure (arrow function or function expression).
pub struct ClosureInfo {
  /// Parameters of the closure
  params : Array[String]
  /// Variables captured from outer scope
  captures : Array[CapturedVar]
  /// Whether the closure can be AOT compiled
  compilable : Bool
  /// Reason if not compilable
  not_compilable_reason : String?
}

///|
/// Analyze an arrow function for closure conversion.
pub fn analyze_arrow_func(
  params : Array[@ast.TsParam],
  body : @ast.TsArrowBody,
  outer_scope : Array[String],
) -> ClosureInfo {
  let param_names : Array[String] = []
  for p in params {
    param_names.push(p.name)
  }
  let captures : Map[String, CapturedVar] = {}

  // Find captured variables
  match body {
    @ast.TsArrowBody::ArrowExpr(expr) =>
      find_captures_in_expr(expr, param_names, outer_scope, captures)
    @ast.TsArrowBody::ArrowBlock(block) =>
      find_captures_in_block(block, param_names, outer_scope, captures)
  }
  let captures_arr : Array[CapturedVar] = []
  for entry in captures {
    captures_arr.push(entry.1)
  }

  // Check compilability
  let (compilable, reason) = check_closure_compilable(body, captures_arr)
  {
    params: param_names,
    captures: captures_arr,
    compilable,
    not_compilable_reason: reason,
  }
}

///|
/// Analyze a function expression for closure conversion.
pub fn analyze_func_expr(
  func : @ast.TsFunc,
  outer_scope : Array[String],
) -> ClosureInfo {
  let param_names : Array[String] = []
  for p in func.params {
    param_names.push(p.name)
  }
  let captures : Map[String, CapturedVar] = {}

  // Find captured variables in function body
  find_captures_in_block(func.body, param_names, outer_scope, captures)
  let captures_arr : Array[CapturedVar] = []
  for entry in captures {
    captures_arr.push(entry.1)
  }

  // Check compilability - generators and async not supported yet
  if func.is_generator {
    return {
      params: param_names,
      captures: captures_arr,
      compilable: false,
      not_compilable_reason: Some(
        "generator function expressions not supported",
      ),
    }
  }
  if func.is_async {
    return {
      params: param_names,
      captures: captures_arr,
      compilable: false,
      not_compilable_reason: Some("async function expressions not supported"),
    }
  }
  let (compilable, reason) = check_closure_compilable_block(
    func.body,
    captures_arr,
  )
  {
    params: param_names,
    captures: captures_arr,
    compilable,
    not_compilable_reason: reason,
  }
}

///|
pub fn find_captures_in_block(
  block : @ast.TsBlock,
  local_vars : Array[String],
  outer_scope : Array[String],
  captures : Map[String, CapturedVar],
) -> Unit {
  // Collect locally declared variables
  let all_locals = local_vars.copy()
  collect_local_declarations(block, all_locals)
  for stmt in block.stmts {
    find_captures_in_stmt(stmt, all_locals, outer_scope, captures)
  }
}

///|
fn collect_local_declarations(
  block : @ast.TsBlock,
  locals : Array[String],
) -> Unit {
  for stmt in block.stmts {
    match stmt {
      @ast.TsStmt::Var(binding, _, _)
      | @ast.TsStmt::Let(binding, _, _)
      | @ast.TsStmt::Const(binding, _, _) =>
        closure_collect_binding_names(binding, locals)
      _ => ()
    }
  }
}

///|
fn closure_collect_binding_names(
  binding : @ast.TsBinding,
  names : Array[String],
) -> Unit {
  match binding {
    @ast.TsBinding::Ident(name) => names.push(name)
    @ast.TsBinding::Array(arr) => {
      for item in arr.items {
        match item {
          Some(elem) => closure_collect_binding_names(elem.binding, names)
          None => ()
        }
      }
      match arr.rest {
        Some(rest) => closure_collect_binding_names(rest, names)
        None => ()
      }
    }
    @ast.TsBinding::Object(obj) => {
      for prop in obj.props {
        closure_collect_binding_names(prop.binding, names)
      }
      match obj.rest {
        Some(rest_name) => names.push(rest_name)
        None => ()
      }
    }
    @ast.TsBinding::Target(_) => ()
  }
}

///|
fn find_captures_in_stmt(
  stmt : @ast.TsStmt,
  local_vars : Array[String],
  outer_scope : Array[String],
  captures : Map[String, CapturedVar],
) -> Unit {
  match stmt {
    @ast.TsStmt::Expr(expr) =>
      find_captures_in_expr(expr, local_vars, outer_scope, captures)
    @ast.TsStmt::Return(Some(expr)) =>
      find_captures_in_expr(expr, local_vars, outer_scope, captures)
    @ast.TsStmt::Var(_, _, init)
    | @ast.TsStmt::Let(_, _, init)
    | @ast.TsStmt::Const(_, _, init) =>
      find_captures_in_expr(init, local_vars, outer_scope, captures)
    @ast.TsStmt::Assign(name, expr) => {
      // Check if assigning to captured variable
      if not(local_vars.contains(name)) && outer_scope.contains(name) {
        match captures.get(name) {
          Some(cap) => captures[name] = { ..cap, is_mutated: true }
          None => captures[name] = { name, is_mutated: true, type_hint: None }
        }
      }
      find_captures_in_expr(expr, local_vars, outer_scope, captures)
    }
    @ast.TsStmt::CompoundAssign(name, _, expr) => {
      // Check if compound assigning to captured variable
      if not(local_vars.contains(name)) && outer_scope.contains(name) {
        match captures.get(name) {
          Some(cap) => captures[name] = { ..cap, is_mutated: true }
          None => captures[name] = { name, is_mutated: true, type_hint: None }
        }
      }
      find_captures_in_expr(expr, local_vars, outer_scope, captures)
    }
    @ast.TsStmt::If(cond, then_block, else_block) => {
      find_captures_in_expr(cond, local_vars, outer_scope, captures)
      find_captures_in_block(then_block, local_vars, outer_scope, captures)
      match else_block {
        Some(eb) =>
          find_captures_in_block(eb, local_vars, outer_scope, captures)
        None => ()
      }
    }
    @ast.TsStmt::While(cond, body) | @ast.TsStmt::DoWhile(cond, body) => {
      find_captures_in_expr(cond, local_vars, outer_scope, captures)
      find_captures_in_block(body, local_vars, outer_scope, captures)
    }
    @ast.TsStmt::For(init, cond, update, body) => {
      match init {
        Some(s) => find_captures_in_stmt(s, local_vars, outer_scope, captures)
        None => ()
      }
      match cond {
        Some(e) => find_captures_in_expr(e, local_vars, outer_scope, captures)
        None => ()
      }
      match update {
        Some(s) => find_captures_in_stmt(s, local_vars, outer_scope, captures)
        None => ()
      }
      find_captures_in_block(body, local_vars, outer_scope, captures)
    }
    @ast.TsStmt::ForOf(_, binding, _, iter, body)
    | @ast.TsStmt::ForIn(_, binding, _, iter, body) => {
      find_captures_in_expr(iter, local_vars, outer_scope, captures)
      let loop_locals = local_vars.copy()
      closure_collect_binding_names(binding, loop_locals)
      find_captures_in_block(body, loop_locals, outer_scope, captures)
    }
    @ast.TsStmt::Block(block) =>
      find_captures_in_block(block, local_vars, outer_scope, captures)
    @ast.TsStmt::Try(try_block, catch_param, catch_block, finally_block) => {
      find_captures_in_block(try_block, local_vars, outer_scope, captures)
      match catch_block {
        Some(cb) => {
          let catch_locals = local_vars.copy()
          match catch_param {
            Some(@ast.TsBinding::Ident(name)) => catch_locals.push(name)
            Some(binding) =>
              closure_collect_binding_names(binding, catch_locals)
            None => ()
          }
          find_captures_in_block(cb, catch_locals, outer_scope, captures)
        }
        None => ()
      }
      match finally_block {
        Some(fb) =>
          find_captures_in_block(fb, local_vars, outer_scope, captures)
        None => ()
      }
    }
    @ast.TsStmt::Switch(expr, cases) => {
      find_captures_in_expr(expr, local_vars, outer_scope, captures)
      for c in cases {
        find_captures_in_block(c.body, local_vars, outer_scope, captures)
      }
    }
    @ast.TsStmt::Throw(expr) =>
      find_captures_in_expr(expr, local_vars, outer_scope, captures)
    _ => ()
  }
}

///|
pub fn find_captures_in_expr(
  expr : @ast.TsExpr,
  local_vars : Array[String],
  outer_scope : Array[String],
  captures : Map[String, CapturedVar],
) -> Unit {
  match expr {
    @ast.TsExpr::Var(name) =>
      // Check if it's from outer scope (not local)
      if not(local_vars.contains(name)) && outer_scope.contains(name) {
        if not(captures.contains(name)) {
          captures[name] = { name, is_mutated: false, type_hint: None }
        }
      }
    @ast.TsExpr::BinOp(_, left, right) => {
      find_captures_in_expr(left, local_vars, outer_scope, captures)
      find_captures_in_expr(right, local_vars, outer_scope, captures)
    }
    @ast.TsExpr::UnaryOp(_, operand) =>
      find_captures_in_expr(operand, local_vars, outer_scope, captures)
    @ast.TsExpr::Call(_, args) =>
      for arg in args {
        find_captures_in_expr(arg, local_vars, outer_scope, captures)
      }
    @ast.TsExpr::CallExpr(callee, args) => {
      find_captures_in_expr(callee, local_vars, outer_scope, captures)
      for arg in args {
        find_captures_in_expr(arg, local_vars, outer_scope, captures)
      }
    }
    @ast.TsExpr::MethodCall(recv, _, args) => {
      find_captures_in_expr(recv, local_vars, outer_scope, captures)
      for arg in args {
        find_captures_in_expr(arg, local_vars, outer_scope, captures)
      }
    }
    @ast.TsExpr::PropAccess(obj, _) =>
      find_captures_in_expr(obj, local_vars, outer_scope, captures)
    @ast.TsExpr::IndexAccess(arr, idx) => {
      find_captures_in_expr(arr, local_vars, outer_scope, captures)
      find_captures_in_expr(idx, local_vars, outer_scope, captures)
    }
    @ast.TsExpr::ArrayLit(elements) =>
      for elem in elements {
        find_captures_in_expr(elem, local_vars, outer_scope, captures)
      }
    @ast.TsExpr::ObjectLit(fields) =>
      for field in fields {
        find_captures_in_expr(field.1, local_vars, outer_scope, captures)
      }
    @ast.TsExpr::Cond(cond, then_e, else_e) => {
      find_captures_in_expr(cond, local_vars, outer_scope, captures)
      find_captures_in_expr(then_e, local_vars, outer_scope, captures)
      find_captures_in_expr(else_e, local_vars, outer_scope, captures)
    }
    @ast.TsExpr::AssignExpr(name, value) => {
      // Assignment to captured variable
      if not(local_vars.contains(name)) && outer_scope.contains(name) {
        match captures.get(name) {
          Some(cap) => captures[name] = { ..cap, is_mutated: true }
          None => captures[name] = { name, is_mutated: true, type_hint: None }
        }
      }
      find_captures_in_expr(value, local_vars, outer_scope, captures)
    }
    @ast.TsExpr::CompoundAssignExpr(target, _, value) => {
      find_captures_in_expr(target, local_vars, outer_scope, captures)
      find_captures_in_expr(value, local_vars, outer_scope, captures)
    }
    @ast.TsExpr::Seq(left, right) => {
      find_captures_in_expr(left, local_vars, outer_scope, captures)
      find_captures_in_expr(right, local_vars, outer_scope, captures)
    }
    @ast.TsExpr::New(_, args) =>
      for arg in args {
        find_captures_in_expr(arg, local_vars, outer_scope, captures)
      }
    @ast.TsExpr::NewExpr(callee, args) => {
      find_captures_in_expr(callee, local_vars, outer_scope, captures)
      for arg in args {
        find_captures_in_expr(arg, local_vars, outer_scope, captures)
      }
    }
    @ast.TsExpr::TemplateLiteral(_, exprs) =>
      for e in exprs {
        find_captures_in_expr(e, local_vars, outer_scope, captures)
      }
    // Nested closures - recursively analyze
    @ast.TsExpr::ArrowFunc(params, body, _) => {
      let inner_params : Array[String] = []
      for p in params {
        inner_params.push(p.name)
      }
      // Extend outer scope with current locals for nested closure
      let extended_scope = outer_scope.copy()
      for v in local_vars {
        if not(extended_scope.contains(v)) {
          extended_scope.push(v)
        }
      }
      match body {
        @ast.TsArrowBody::ArrowExpr(e) =>
          find_captures_in_expr(e, inner_params, extended_scope, captures)
        @ast.TsArrowBody::ArrowBlock(block) =>
          find_captures_in_block(block, inner_params, extended_scope, captures)
      }
    }
    @ast.TsExpr::FuncExpr(func) => {
      let inner_params : Array[String] = []
      for p in func.params {
        inner_params.push(p.name)
      }
      let extended_scope = outer_scope.copy()
      for v in local_vars {
        if not(extended_scope.contains(v)) {
          extended_scope.push(v)
        }
      }
      find_captures_in_block(func.body, inner_params, extended_scope, captures)
    }
    _ => ()
  }
}

///|
fn check_closure_compilable(
  body : @ast.TsArrowBody,
  _captures : Array[CapturedVar],
) -> (Bool, String?) {
  // Mutable captures are now supported (Phase 3)
  // Check body for unsupported features
  match body {
    @ast.TsArrowBody::ArrowExpr(expr) => check_expr_closure_compatible(expr)
    @ast.TsArrowBody::ArrowBlock(block) => check_block_closure_compatible(block)
  }
}

///|
fn check_closure_compilable_block(
  block : @ast.TsBlock,
  _captures : Array[CapturedVar],
) -> (Bool, String?) {
  // Mutable captures are now supported (Phase 3)
  check_block_closure_compatible(block)
}

///|
fn check_block_closure_compatible(block : @ast.TsBlock) -> (Bool, String?) {
  for stmt in block.stmts {
    match check_stmt_closure_compatible(stmt) {
      (false, reason) => return (false, reason)
      _ => continue
    }
  }
  (true, None)
}

///|
fn check_stmt_closure_compatible(stmt : @ast.TsStmt) -> (Bool, String?) {
  match stmt {
    @ast.TsStmt::With(_, _) => (false, Some("'with' statement not supported"))
    @ast.TsStmt::Expr(expr) => check_expr_closure_compatible(expr)
    @ast.TsStmt::Return(Some(expr)) => check_expr_closure_compatible(expr)
    @ast.TsStmt::Var(_, _, init)
    | @ast.TsStmt::Let(_, _, init)
    | @ast.TsStmt::Const(_, _, init) => check_expr_closure_compatible(init)
    @ast.TsStmt::Assign(_, expr) => check_expr_closure_compatible(expr)
    @ast.TsStmt::CompoundAssign(_, _, expr) =>
      check_expr_closure_compatible(expr)
    @ast.TsStmt::If(cond, then_block, else_block) => {
      match check_expr_closure_compatible(cond) {
        (false, r) => return (false, r)
        _ => ()
      }
      match check_block_closure_compatible(then_block) {
        (false, r) => return (false, r)
        _ => ()
      }
      match else_block {
        Some(eb) => check_block_closure_compatible(eb)
        None => (true, None)
      }
    }
    @ast.TsStmt::While(cond, body) | @ast.TsStmt::DoWhile(cond, body) => {
      match check_expr_closure_compatible(cond) {
        (false, r) => return (false, r)
        _ => ()
      }
      check_block_closure_compatible(body)
    }
    @ast.TsStmt::For(init, cond, update, body) => {
      match init {
        Some(s) =>
          match check_stmt_closure_compatible(s) {
            (false, r) => return (false, r)
            _ => ()
          }
        None => ()
      }
      match cond {
        Some(e) =>
          match check_expr_closure_compatible(e) {
            (false, r) => return (false, r)
            _ => ()
          }
        None => ()
      }
      match update {
        Some(s) =>
          match check_stmt_closure_compatible(s) {
            (false, r) => return (false, r)
            _ => ()
          }
        None => ()
      }
      check_block_closure_compatible(body)
    }
    @ast.TsStmt::Block(block) => check_block_closure_compatible(block)
    _ => (true, None)
  }
}

///|
fn check_expr_closure_compatible(expr : @ast.TsExpr) -> (Bool, String?) {
  match expr {
    @ast.TsExpr::Call("eval", _) => (false, Some("'eval' not supported"))
    @ast.TsExpr::Yield(_) | @ast.TsExpr::YieldStar(_) =>
      (false, Some("yield in closure not supported"))
    @ast.TsExpr::Await(_) => (false, Some("await in closure not yet supported"))
    // Nested closures - check recursively
    @ast.TsExpr::ArrowFunc(_, body, _) =>
      match body {
        @ast.TsArrowBody::ArrowExpr(e) => check_expr_closure_compatible(e)
        @ast.TsArrowBody::ArrowBlock(block) =>
          check_block_closure_compatible(block)
      }
    @ast.TsExpr::FuncExpr(func) =>
      if func.is_generator {
        (false, Some("nested generator not supported"))
      } else if func.is_async {
        (false, Some("nested async function not supported"))
      } else {
        check_block_closure_compatible(func.body)
      }
    @ast.TsExpr::BinOp(_, left, right) => {
      match check_expr_closure_compatible(left) {
        (false, r) => return (false, r)
        _ => ()
      }
      check_expr_closure_compatible(right)
    }
    @ast.TsExpr::UnaryOp(_, operand) => check_expr_closure_compatible(operand)
    @ast.TsExpr::Call(_, args) => {
      for arg in args {
        match check_expr_closure_compatible(arg) {
          (false, r) => return (false, r)
          _ => continue
        }
      }
      (true, None)
    }
    @ast.TsExpr::CallExpr(callee, args) => {
      match check_expr_closure_compatible(callee) {
        (false, r) => return (false, r)
        _ => ()
      }
      for arg in args {
        match check_expr_closure_compatible(arg) {
          (false, r) => return (false, r)
          _ => continue
        }
      }
      (true, None)
    }
    @ast.TsExpr::MethodCall(recv, _, args) => {
      match check_expr_closure_compatible(recv) {
        (false, r) => return (false, r)
        _ => ()
      }
      for arg in args {
        match check_expr_closure_compatible(arg) {
          (false, r) => return (false, r)
          _ => continue
        }
      }
      (true, None)
    }
    @ast.TsExpr::Cond(cond, then_e, else_e) => {
      match check_expr_closure_compatible(cond) {
        (false, r) => return (false, r)
        _ => ()
      }
      match check_expr_closure_compatible(then_e) {
        (false, r) => return (false, r)
        _ => ()
      }
      check_expr_closure_compatible(else_e)
    }
    @ast.TsExpr::ArrayLit(elements) => {
      for elem in elements {
        match check_expr_closure_compatible(elem) {
          (false, r) => return (false, r)
          _ => continue
        }
      }
      (true, None)
    }
    @ast.TsExpr::ObjectLit(fields) => {
      for field in fields {
        match check_expr_closure_compatible(field.1) {
          (false, r) => return (false, r)
          _ => continue
        }
      }
      (true, None)
    }
    _ => (true, None)
  }
}

///|
/// Check if a closure has any mutable captures.
pub fn has_mutable_captures(info : ClosureInfo) -> Bool {
  info.captures.iter().any(fn(c) { c.is_mutated })
}

///|
/// Get the names of all captured variables.
pub fn get_capture_names(info : ClosureInfo) -> Array[String] {
  info.captures.map(fn(c) { c.name })
}
