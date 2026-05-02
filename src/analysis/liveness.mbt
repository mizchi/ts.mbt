// Liveness analysis - track variable lifetimes for GC optimization.

///|
/// Usage point of a variable.
pub(all) struct UsePoint {
  // Statement index within function
  stmt_index : Int
}

///|
/// Lifetime information for a variable.
pub(all) struct VarLifetime {
  name : String
  // First use (definition point)
  first_use : Int
  // Last use point
  mut last_use : Int
  // All use points
  uses : Array[UsePoint]
  // Does this variable escape the function?
  mut escapes : Bool
  // Is this variable captured by a closure?
  mut is_captured : Bool
}

///|
/// Liveness analysis result.
pub(all) struct LivenessInfo {
  // Lifetime info for each variable
  lifetimes : Map[String, VarLifetime]
  // Variables that are live at each statement index
  live_at : Map[Int, Array[String]]
  // Drop points - where variables should be deallocated
  // Maps statement index to list of variables to drop after that statement
  drop_points : Map[Int, Array[String]]
  // Variables captured by closures (cannot be dropped)
  captured_vars : Array[String]
}

///|
pub fn LivenessInfo::new() -> LivenessInfo {
  { lifetimes: {}, live_at: {}, drop_points: {}, captured_vars: [] }
}

///|
/// Analyze liveness for a function.
pub fn analyze_liveness(func : @ast.TsFunc) -> LivenessInfo {
  let info = LivenessInfo::new()

  // Phase 1: Collect all variable uses with statement indices
  let mut stmt_idx = 0

  // Parameters are defined at index 0
  for param in func.params {
    let lifetime : VarLifetime = {
      name: param.name,
      first_use: 0,
      last_use: 0,
      uses: [{ stmt_index: 0 }],
      escapes: false,
      is_captured: false,
    }
    info.lifetimes[param.name] = lifetime
  }

  // Analyze each statement
  for stmt in func.body.stmts {
    stmt_idx = stmt_idx + 1
    collect_uses_in_stmt(stmt, stmt_idx, info)
  }

  // Phase 2: Find closures and mark captured variables
  for stmt in func.body.stmts {
    find_captured_vars(stmt, info)
  }

  // Phase 3: Calculate last use points
  for entry in info.lifetimes {
    let lifetime = entry.1
    if lifetime.uses.length() > 0 {
      // Find max statement index
      let mut max_idx = 0
      for use_point in lifetime.uses {
        if use_point.stmt_index > max_idx {
          max_idx = use_point.stmt_index
        }
      }
      lifetime.last_use = max_idx
    }
  }

  // Phase 4: Calculate live variables at each statement
  for i = 1; i <= stmt_idx; i = i + 1 {
    let live : Array[String] = []
    for entry in info.lifetimes {
      let name = entry.0
      let lifetime = entry.1
      // Variable is live if we're between first and last use
      if lifetime.first_use <= i && i <= lifetime.last_use {
        live.push(name)
      }
    }
    info.live_at[i] = live
  }

  // Phase 5: Calculate drop points
  for entry in info.lifetimes {
    let name = entry.0
    let lifetime = entry.1

    // Don't drop captured variables or escaping variables
    if lifetime.is_captured || lifetime.escapes {
      continue
    }

    // Drop at last use point
    let drop_idx = lifetime.last_use
    if drop_idx > 0 {
      match info.drop_points.get(drop_idx) {
        Some(vars) => vars.push(name)
        None => info.drop_points[drop_idx] = [name]
      }
    }
  }
  info
}

///|
fn collect_uses_in_stmt(
  stmt : @ast.TsStmt,
  idx : Int,
  info : LivenessInfo,
) -> Unit {
  match stmt {
    @ast.TsStmt::Var(binding, _, init)
    | @ast.TsStmt::Let(binding, _, init)
    | @ast.TsStmt::Const(binding, _, init) => {
      // Definition is a write
      let names : Array[String] = []
      collect_binding_names(binding, names)
      for name in names {
        let lifetime : VarLifetime = {
          name,
          first_use: idx,
          last_use: idx,
          uses: [{ stmt_index: idx }],
          escapes: false,
          is_captured: false,
        }
        info.lifetimes[name] = lifetime
      }
      // Collect reads from initializer
      collect_uses_in_expr(init, idx, false, info)
    }
    @ast.TsStmt::Assign(name, value) => {
      record_use(name, idx, true, info)
      collect_uses_in_expr(value, idx, false, info)
    }
    @ast.TsStmt::Expr(e) => collect_uses_in_expr(e, idx, false, info)
    @ast.TsStmt::Return(Some(e)) => {
      // Returned values escape
      mark_expr_escapes(e, info)
      collect_uses_in_expr(e, idx, false, info)
    }
    @ast.TsStmt::Return(None) => ()
    @ast.TsStmt::If(cond, then_block, else_block) => {
      collect_uses_in_expr(cond, idx, false, info)
      for s in then_block.stmts {
        collect_uses_in_stmt(s, idx, info)
      }
      match else_block {
        Some(eb) =>
          for s in eb.stmts {
            collect_uses_in_stmt(s, idx, info)
          }
        None => ()
      }
    }
    @ast.TsStmt::While(cond, body) | @ast.TsStmt::DoWhile(cond, body) => {
      collect_uses_in_expr(cond, idx, false, info)
      for s in body.stmts {
        collect_uses_in_stmt(s, idx, info)
      }
    }
    @ast.TsStmt::For(init, cond, update, body) => {
      match init {
        Some(i) => collect_uses_in_stmt(i, idx, info)
        None => ()
      }
      match cond {
        Some(c) => collect_uses_in_expr(c, idx, false, info)
        None => ()
      }
      match update {
        Some(u) => collect_uses_in_stmt(u, idx, info)
        None => ()
      }
      for s in body.stmts {
        collect_uses_in_stmt(s, idx, info)
      }
    }
    @ast.TsStmt::ForOf(_, binding, _, iter, body)
    | @ast.TsStmt::ForAwaitOf(_, binding, _, iter, body)
    | @ast.TsStmt::ForIn(_, binding, _, iter, body) => {
      let names : Array[String] = []
      collect_binding_names(binding, names)
      for name in names {
        record_use(name, idx, true, info)
      }
      collect_uses_in_expr(iter, idx, false, info)
      for s in body.stmts {
        collect_uses_in_stmt(s, idx, info)
      }
    }
    @ast.TsStmt::Block(block) =>
      for s in block.stmts {
        collect_uses_in_stmt(s, idx, info)
      }
    @ast.TsStmt::Throw(e) => {
      mark_expr_escapes(e, info)
      collect_uses_in_expr(e, idx, false, info)
    }
    @ast.TsStmt::Try(try_block, binding, catch_block, finally_block) => {
      for s in try_block.stmts {
        collect_uses_in_stmt(s, idx, info)
      }
      match binding {
        Some(b) => {
          let names : Array[String] = []
          collect_binding_names(b, names)
          for name in names {
            record_use(name, idx, true, info)
          }
        }
        None => ()
      }
      match catch_block {
        Some(cb) =>
          for s in cb.stmts {
            collect_uses_in_stmt(s, idx, info)
          }
        None => ()
      }
      match finally_block {
        Some(fb) =>
          for s in fb.stmts {
            collect_uses_in_stmt(s, idx, info)
          }
        None => ()
      }
    }
    _ => ()
  }
}

///|
fn collect_uses_in_expr(
  expr : @ast.TsExpr,
  idx : Int,
  is_write : Bool,
  info : LivenessInfo,
) -> Unit {
  match expr {
    @ast.TsExpr::Var(name) => record_use(name, idx, is_write, info)
    @ast.TsExpr::BinOp(_, left, right) => {
      collect_uses_in_expr(left, idx, false, info)
      collect_uses_in_expr(right, idx, false, info)
    }
    @ast.TsExpr::UnaryOp(op, operand) => {
      let writes = match op {
        @ast.TsUnaryOp::PreInc
        | @ast.TsUnaryOp::PreDec
        | @ast.TsUnaryOp::PostInc
        | @ast.TsUnaryOp::PostDec => true
        _ => false
      }
      collect_uses_in_expr(operand, idx, writes, info)
    }
    @ast.TsExpr::Call(_, args) =>
      // Arguments passed to functions may escape
      for arg in args {
        mark_expr_escapes(arg, info)
        collect_uses_in_expr(arg, idx, false, info)
      }
    @ast.TsExpr::CallExpr(callee, args) => {
      collect_uses_in_expr(callee, idx, false, info)
      for arg in args {
        mark_expr_escapes(arg, info)
        collect_uses_in_expr(arg, idx, false, info)
      }
    }
    @ast.TsExpr::MethodCall(recv, _, args) => {
      collect_uses_in_expr(recv, idx, false, info)
      for arg in args {
        mark_expr_escapes(arg, info)
        collect_uses_in_expr(arg, idx, false, info)
      }
    }
    @ast.TsExpr::PropAccess(obj, _) =>
      collect_uses_in_expr(obj, idx, false, info)
    @ast.TsExpr::IndexAccess(arr, index) => {
      collect_uses_in_expr(arr, idx, false, info)
      collect_uses_in_expr(index, idx, false, info)
    }
    @ast.TsExpr::ArrayLit(elements) =>
      for elem in elements {
        collect_uses_in_expr(elem, idx, false, info)
      }
    @ast.TsExpr::ObjectLit(props) =>
      for prop in props {
        collect_uses_in_expr(prop.1, idx, false, info)
      }
    @ast.TsExpr::Cond(cond, then_e, else_e) => {
      collect_uses_in_expr(cond, idx, false, info)
      collect_uses_in_expr(then_e, idx, false, info)
      collect_uses_in_expr(else_e, idx, false, info)
    }
    @ast.TsExpr::AssignExpr(name, value) => {
      record_use(name, idx, true, info)
      collect_uses_in_expr(value, idx, false, info)
    }
    @ast.TsExpr::Seq(left, right) => {
      collect_uses_in_expr(left, idx, false, info)
      collect_uses_in_expr(right, idx, false, info)
    }
    @ast.TsExpr::ArrowFunc(params, body, _) => {
      // Arrow function captures variables from outer scope
      let param_names : Array[String] = []
      for p in params {
        param_names.push(p.name)
      }
      match body {
        @ast.TsArrowBody::ArrowExpr(e) =>
          find_captured_in_expr(e, param_names, info)
        @ast.TsArrowBody::ArrowBlock(block) =>
          for s in block.stmts {
            find_captured_in_stmt(s, param_names, info)
          }
      }
    }
    @ast.TsExpr::TemplateLiteral(_, exprs) =>
      for e in exprs {
        collect_uses_in_expr(e, idx, false, info)
      }
    _ => ()
  }
}

///|
fn record_use(
  name : String,
  idx : Int,
  _is_write : Bool,
  info : LivenessInfo,
) -> Unit {
  match info.lifetimes.get(name) {
    Some(lifetime) => {
      lifetime.uses.push({ stmt_index: idx })
      if idx > lifetime.last_use {
        lifetime.last_use = idx
      }
    }
    None => {
      // Variable from outer scope - create lifetime entry
      let lifetime : VarLifetime = {
        name,
        first_use: idx,
        last_use: idx,
        uses: [{ stmt_index: idx }],
        escapes: false,
        is_captured: false,
      }
      info.lifetimes[name] = lifetime
    }
  }
}

///|
fn mark_expr_escapes(expr : @ast.TsExpr, info : LivenessInfo) -> Unit {
  match expr {
    @ast.TsExpr::Var(name) =>
      match info.lifetimes.get(name) {
        Some(lifetime) => lifetime.escapes = true
        None => ()
      }
    @ast.TsExpr::ArrayLit(elements) =>
      for elem in elements {
        mark_expr_escapes(elem, info)
      }
    @ast.TsExpr::ObjectLit(props) =>
      for prop in props {
        mark_expr_escapes(prop.1, info)
      }
    _ => ()
  }
}

///|
fn find_captured_vars(stmt : @ast.TsStmt, info : LivenessInfo) -> Unit {
  match stmt {
    @ast.TsStmt::Expr(e) => find_captured_in_top_expr(e, info)
    @ast.TsStmt::Var(_, _, init)
    | @ast.TsStmt::Let(_, _, init)
    | @ast.TsStmt::Const(_, _, init) => find_captured_in_top_expr(init, info)
    @ast.TsStmt::Return(Some(e)) => find_captured_in_top_expr(e, info)
    @ast.TsStmt::If(cond, then_block, else_block) => {
      find_captured_in_top_expr(cond, info)
      for s in then_block.stmts {
        find_captured_vars(s, info)
      }
      match else_block {
        Some(eb) =>
          for s in eb.stmts {
            find_captured_vars(s, info)
          }
        None => ()
      }
    }
    @ast.TsStmt::Block(block) =>
      for s in block.stmts {
        find_captured_vars(s, info)
      }
    _ => ()
  }
}

///|
fn find_captured_in_top_expr(expr : @ast.TsExpr, info : LivenessInfo) -> Unit {
  match expr {
    @ast.TsExpr::ArrowFunc(params, body, _) => {
      let param_names : Array[String] = []
      for p in params {
        param_names.push(p.name)
      }
      match body {
        @ast.TsArrowBody::ArrowExpr(e) =>
          find_captured_in_expr(e, param_names, info)
        @ast.TsArrowBody::ArrowBlock(block) =>
          for s in block.stmts {
            find_captured_in_stmt(s, param_names, info)
          }
      }
    }
    @ast.TsExpr::FuncExpr(func) => {
      let param_names : Array[String] = []
      for p in func.params {
        param_names.push(p.name)
      }
      for s in func.body.stmts {
        find_captured_in_stmt(s, param_names, info)
      }
    }
    @ast.TsExpr::Call(_, args) =>
      for arg in args {
        find_captured_in_top_expr(arg, info)
      }
    @ast.TsExpr::BinOp(_, left, right) => {
      find_captured_in_top_expr(left, info)
      find_captured_in_top_expr(right, info)
    }
    _ => ()
  }
}

///|
fn find_captured_in_expr(
  expr : @ast.TsExpr,
  local_params : Array[String],
  info : LivenessInfo,
) -> Unit {
  match expr {
    @ast.TsExpr::Var(name) =>
      // If variable is not a local parameter, it's captured from outer scope
      if !local_params.contains(name) {
        match info.lifetimes.get(name) {
          Some(lifetime) => {
            lifetime.is_captured = true
            if !info.captured_vars.contains(name) {
              info.captured_vars.push(name)
            }
          }
          None => ()
        }
      }
    @ast.TsExpr::BinOp(_, left, right) => {
      find_captured_in_expr(left, local_params, info)
      find_captured_in_expr(right, local_params, info)
    }
    @ast.TsExpr::UnaryOp(_, operand) =>
      find_captured_in_expr(operand, local_params, info)
    @ast.TsExpr::Call(_, args) =>
      for arg in args {
        find_captured_in_expr(arg, local_params, info)
      }
    @ast.TsExpr::CallExpr(callee, args) => {
      find_captured_in_expr(callee, local_params, info)
      for arg in args {
        find_captured_in_expr(arg, local_params, info)
      }
    }
    @ast.TsExpr::MethodCall(recv, _, args) => {
      find_captured_in_expr(recv, local_params, info)
      for arg in args {
        find_captured_in_expr(arg, local_params, info)
      }
    }
    @ast.TsExpr::PropAccess(obj, _) =>
      find_captured_in_expr(obj, local_params, info)
    @ast.TsExpr::IndexAccess(arr, idx) => {
      find_captured_in_expr(arr, local_params, info)
      find_captured_in_expr(idx, local_params, info)
    }
    @ast.TsExpr::Cond(cond, then_e, else_e) => {
      find_captured_in_expr(cond, local_params, info)
      find_captured_in_expr(then_e, local_params, info)
      find_captured_in_expr(else_e, local_params, info)
    }
    @ast.TsExpr::ArrayLit(elements) =>
      for elem in elements {
        find_captured_in_expr(elem, local_params, info)
      }
    @ast.TsExpr::ObjectLit(props) =>
      for prop in props {
        find_captured_in_expr(prop.1, local_params, info)
      }
    _ => ()
  }
}

///|
fn find_captured_in_stmt(
  stmt : @ast.TsStmt,
  local_params : Array[String],
  info : LivenessInfo,
) -> Unit {
  match stmt {
    @ast.TsStmt::Expr(e) => find_captured_in_expr(e, local_params, info)
    @ast.TsStmt::Return(Some(e)) => find_captured_in_expr(e, local_params, info)
    @ast.TsStmt::Var(_, _, init)
    | @ast.TsStmt::Let(_, _, init)
    | @ast.TsStmt::Const(_, _, init) =>
      find_captured_in_expr(init, local_params, info)
    @ast.TsStmt::If(cond, then_block, else_block) => {
      find_captured_in_expr(cond, local_params, info)
      for s in then_block.stmts {
        find_captured_in_stmt(s, local_params, info)
      }
      match else_block {
        Some(eb) =>
          for s in eb.stmts {
            find_captured_in_stmt(s, local_params, info)
          }
        None => ()
      }
    }
    @ast.TsStmt::Block(block) =>
      for s in block.stmts {
        find_captured_in_stmt(s, local_params, info)
      }
    _ => ()
  }
}

///|
/// Get variables that should be dropped after a statement.
pub fn get_drop_vars(info : LivenessInfo, stmt_index : Int) -> Array[String] {
  match info.drop_points.get(stmt_index) {
    Some(vars) => vars
    None => []
  }
}

///|
/// Check if a variable is live at a given statement.
pub fn is_live_at(info : LivenessInfo, name : String, stmt_index : Int) -> Bool {
  match info.live_at.get(stmt_index) {
    Some(vars) => vars.contains(name)
    None => false
  }
}

///|
/// Check if a variable is captured by a closure.
pub fn is_captured(info : LivenessInfo, name : String) -> Bool {
  info.captured_vars.contains(name)
}

///|
/// Get the last use point of a variable.
pub fn get_last_use(info : LivenessInfo, name : String) -> Int? {
  match info.lifetimes.get(name) {
    Some(lifetime) => Some(lifetime.last_use)
    None => None
  }
}

///|
/// Check if a type needs GC (is heap-allocated).
pub fn needs_gc(type_ : @ast.TsType) -> Bool {
  match type_ {
    // Primitives - no GC needed
    @ast.TsType::Number
    | @ast.TsType::Int
    | @ast.TsType::Boolean
    | @ast.TsType::String_
    | @ast.TsType::Void
    | @ast.TsType::Null
    | @ast.TsType::Undefined
    | @ast.TsType::Never
    | @ast.TsType::BigInt
    | @ast.TsType::Symbol
    | @ast.TsType::Literal(_)
    | @ast.TsType::NumberLiteral(_)
    | @ast.TsType::BigIntLiteral(_)
    | @ast.TsType::BooleanLiteral(_) => false
    // Heap-allocated types - need GC
    @ast.TsType::Array(_)
    | @ast.TsType::Object(_)
    | @ast.TsType::Func(_, _)
    | @ast.TsType::Struct(_, _)
    | @ast.TsType::Named(_)
    | @ast.TsType::Applied(_, _)
    | @ast.TsType::Any => true
    // Union/Intersection - check components
    @ast.TsType::Union(types) | @ast.TsType::Intersection(types) =>
      types.iter().any(fn(t) { needs_gc(t) })
    @ast.TsType::Tuple(types) => types.iter().any(fn(t) { needs_gc(t) })
    @ast.TsType::Conditional(source, target, true_type, false_type) =>
      needs_gc(source) ||
      needs_gc(target) ||
      needs_gc(true_type) ||
      needs_gc(false_type)
    @ast.TsType::IndexedAccess(base, key) => needs_gc(base) || needs_gc(key)
  }
}
