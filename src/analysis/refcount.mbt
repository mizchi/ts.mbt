// Reference counting insertion points - where to insert incref/decref calls.

///|
/// Reference count operation.
pub(all) enum RefOp {
  Incref(String) // Increment reference count
  Decref(String) // Decrement reference count
  Move(String) // Transfer ownership (no ref change)
} derive(Debug)

///|
/// A reference operation at a specific point.
pub(all) struct RefPoint {
  stmt_index : Int
  op : RefOp
  // Is this before or after the statement?
  is_before : Bool
}

///|
/// Reference counting analysis result.
pub(all) struct RefCountInfo {
  // All reference operations needed
  ops : Array[RefPoint]
  // Variables that need reference counting (heap-allocated)
  rc_vars : Array[String]
  // Variables that are moved (ownership transferred)
  moved_vars : Array[String]
}

///|
pub fn RefCountInfo::new() -> RefCountInfo {
  { ops: [], rc_vars: [], moved_vars: [] }
}

///|
/// Analyze a function for reference counting operations.
pub fn analyze_refcount(
  func : @ast.TsFunc,
  type_info : Map[String, @ast.TsType],
) -> RefCountInfo {
  let info = RefCountInfo::new()
  let liveness = analyze_liveness(func)
  let aliases = analyze_aliases(func)

  // Determine which variables need RC
  for entry in type_info {
    let name = entry.0
    let type_ = entry.1
    if needs_gc(type_) {
      info.rc_vars.push(name)
    }
  }

  // Analyze each statement
  let mut stmt_idx = 0
  for stmt in func.body.stmts {
    stmt_idx = stmt_idx + 1
    analyze_stmt_refcount(stmt, stmt_idx, info, aliases, liveness, type_info)
  }
  info
}

///|
fn analyze_stmt_refcount(
  stmt : @ast.TsStmt,
  idx : Int,
  info : RefCountInfo,
  aliases : AliasInfo,
  liveness : LivenessInfo,
  type_info : Map[String, @ast.TsType],
) -> Unit {
  match stmt {
    // Variable declaration with initializer
    @ast.TsStmt::Var(binding, _, init)
    | @ast.TsStmt::Let(binding, _, init)
    | @ast.TsStmt::Const(binding, _, init) => {
      let names : Array[String] = []
      collect_binding_names(binding, names)
      for name in names {
        // Check if this is a copy of another variable (needs incref)
        match init {
          @ast.TsExpr::Var(source) =>
            // Copying from another variable
            if is_rc_var(source, info, type_info) {
              info.ops.push({
                stmt_index: idx,
                op: Incref(name),
                is_before: false,
              })
            }
          // Object/array literal - already has refcount 1
          @ast.TsExpr::ObjectLit(_) | @ast.TsExpr::ArrayLit(_) => ()
          // Function call result - returned with refcount 1
          @ast.TsExpr::Call(_, _)
          | @ast.TsExpr::CallExpr(_, _)
          | @ast.TsExpr::MethodCall(_, _, _) => ()
          _ => ()
        }
      }
    }
    // Assignment
    @ast.TsStmt::Assign(name, value) => {
      // Old value needs decref before assignment
      if is_rc_var(name, info, type_info) {
        info.ops.push({ stmt_index: idx, op: Decref(name), is_before: true })
      }

      // New value may need incref
      match value {
        @ast.TsExpr::Var(source) =>
          if is_rc_var(source, info, type_info) {
            info.ops.push({
              stmt_index: idx,
              op: Incref(name),
              is_before: false,
            })
          }
        _ => ()
      }
    }
    // Return - may transfer ownership
    @ast.TsStmt::Return(Some(e)) =>
      match e {
        @ast.TsExpr::Var(name) =>
          // Returning transfers ownership - mark as moved
          if is_rc_var(name, info, type_info) {
            if !info.moved_vars.contains(name) {
              info.moved_vars.push(name)
            }
            info.ops.push({ stmt_index: idx, op: Move(name), is_before: false })
          }
        _ => ()
      }
    // Function call - arguments may be borrowed or consumed
    @ast.TsStmt::Expr(e) => analyze_expr_refcount(e, idx, info, type_info)
    _ => ()
  }

  // Add decrefs for variables that are last used at this statement
  for var_name in get_drop_vars(liveness, idx) {
    if is_rc_var(var_name, info, type_info) {
      // Don't decref if already moved
      if !info.moved_vars.contains(var_name) {
        // Check if this is the last alias
        if is_unique(aliases, var_name) {
          info.ops.push({
            stmt_index: idx,
            op: Decref(var_name),
            is_before: false,
          })
        }
      }
    }
  }
}

///|
fn analyze_expr_refcount(
  expr : @ast.TsExpr,
  idx : Int,
  info : RefCountInfo,
  type_info : Map[String, @ast.TsType],
) -> Unit {
  match expr {
    // Function call with arguments
    @ast.TsExpr::Call(_, args) | @ast.TsExpr::CallExpr(_, args) =>
      for arg in args {
        match arg {
          @ast.TsExpr::Var(name) =>
            // Arguments are borrowed by default (incref before, decref after)
            if is_rc_var(name, info, type_info) {
              info.ops.push({
                stmt_index: idx,
                op: Incref(name),
                is_before: true,
              })
              info.ops.push({
                stmt_index: idx,
                op: Decref(name),
                is_before: false,
              })
            }
          _ => ()
        }
      }
    @ast.TsExpr::MethodCall(recv, _, args) => {
      // Receiver is borrowed
      match recv {
        @ast.TsExpr::Var(name) =>
          if is_rc_var(name, info, type_info) {
            info.ops.push({ stmt_index: idx, op: Incref(name), is_before: true })
            info.ops.push({
              stmt_index: idx,
              op: Decref(name),
              is_before: false,
            })
          }
        _ => ()
      }
      for arg in args {
        match arg {
          @ast.TsExpr::Var(name) =>
            if is_rc_var(name, info, type_info) {
              info.ops.push({
                stmt_index: idx,
                op: Incref(name),
                is_before: true,
              })
              info.ops.push({
                stmt_index: idx,
                op: Decref(name),
                is_before: false,
              })
            }
          _ => ()
        }
      }
    }
    _ => ()
  }
}

///|
fn is_rc_var(
  name : String,
  info : RefCountInfo,
  type_info : Map[String, @ast.TsType],
) -> Bool {
  // Check if already in rc_vars list
  if info.rc_vars.contains(name) {
    return true
  }
  // Check type info
  match type_info.get(name) {
    Some(t) => needs_gc(t)
    None => false // Unknown type, assume no RC needed
  }
}

///|
/// Get all refcount operations at a specific statement.
pub fn get_ops_at(
  info : RefCountInfo,
  stmt_index : Int,
  before : Bool,
) -> Array[RefOp] {
  info.ops
  .iter()
  .filter(fn(p) { p.stmt_index == stmt_index && p.is_before == before })
  .map(fn(p) { p.op })
  .collect()
}

///|
/// Get incref operations at a specific statement.
pub fn get_increfs_at(info : RefCountInfo, stmt_index : Int) -> Array[String] {
  let results : Array[String] = []
  for p in info.ops {
    if p.stmt_index == stmt_index {
      match p.op {
        Incref(name) => results.push(name)
        _ => ()
      }
    }
  }
  results
}

///|
/// Get decref operations at a specific statement.
pub fn get_decrefs_at(info : RefCountInfo, stmt_index : Int) -> Array[String] {
  let results : Array[String] = []
  for p in info.ops {
    if p.stmt_index == stmt_index {
      match p.op {
        Decref(name) => results.push(name)
        _ => ()
      }
    }
  }
  results
}
