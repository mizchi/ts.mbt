// Call graph analysis for AOT optimization.
// Analyzes function call relationships to identify groups of functions
// that can be compiled together.

///|
/// Call graph representation.
pub struct CallGraph {
  /// Map from function name to list of functions it calls
  calls : Map[String, Array[String]]
  /// Map from function name to list of functions that call it
  callers : Map[String, Array[String]]
  /// Set of all function names
  functions : Array[String]
}

///|
/// Result of AOT group analysis.
pub struct AOTGroup {
  /// Root generator function
  root : String
  /// All functions in the group (including root)
  members : Array[String]
  /// Functions that are called from outside the group
  external_calls : Array[String]
}

///|
/// Build a call graph from a ts_module.
pub fn build_call_graph(ts_module : @ast.TsModule) -> CallGraph {
  let calls : Map[String, Array[String]] = {}
  let callers : Map[String, Array[String]] = {}
  let functions : Array[String] = []

  // Collect all function names
  for func in ts_module.funcs {
    functions.push(func.name)
    calls[func.name] = []
    callers[func.name] = []
  }

  // Analyze each function's calls
  for func in ts_module.funcs {
    let called = collect_calls_in_func(func)
    calls[func.name] = called

    // Update callers
    for callee in called {
      match callers.get(callee) {
        Some(arr) => arr.push(func.name)
        None => callers[callee] = [func.name]
      }
    }
  }

  { calls, callers, functions }
}

///|
/// Collect all function calls in a function body.
fn collect_calls_in_func(func : @ast.TsFunc) -> Array[String] {
  let calls : Array[String] = []
  collect_calls_in_block(func.body, calls)
  calls
}

///|
fn collect_calls_in_block(block : @ast.TsBlock, calls : Array[String]) -> Unit {
  for stmt in block.stmts {
    collect_calls_in_stmt(stmt, calls)
  }
}

///|
fn collect_calls_in_stmt(stmt : @ast.TsStmt, calls : Array[String]) -> Unit {
  match stmt {
    @ast.TsStmt::Expr(expr) => collect_calls_in_expr(expr, calls)
    @ast.TsStmt::Return(Some(expr)) => collect_calls_in_expr(expr, calls)
    @ast.TsStmt::Var(_, _, init)
    | @ast.TsStmt::Let(_, _, init)
    | @ast.TsStmt::Const(_, _, init) => collect_calls_in_expr(init, calls)
    @ast.TsStmt::Assign(_, expr) => collect_calls_in_expr(expr, calls)
    @ast.TsStmt::CompoundAssign(_, _, expr) => collect_calls_in_expr(expr, calls)
    @ast.TsStmt::If(cond, then_block, else_block) => {
      collect_calls_in_expr(cond, calls)
      collect_calls_in_block(then_block, calls)
      match else_block {
        Some(eb) => collect_calls_in_block(eb, calls)
        None => ()
      }
    }
    @ast.TsStmt::While(cond, body) | @ast.TsStmt::DoWhile(cond, body) => {
      collect_calls_in_expr(cond, calls)
      collect_calls_in_block(body, calls)
    }
    @ast.TsStmt::For(init, cond, update, body) => {
      match init {
        Some(s) => collect_calls_in_stmt(s, calls)
        None => ()
      }
      match cond {
        Some(e) => collect_calls_in_expr(e, calls)
        None => ()
      }
      match update {
        Some(s) => collect_calls_in_stmt(s, calls)
        None => ()
      }
      collect_calls_in_block(body, calls)
    }
    @ast.TsStmt::ForOf(_, _, _, iter, body)
    | @ast.TsStmt::ForIn(_, _, _, iter, body) => {
      collect_calls_in_expr(iter, calls)
      collect_calls_in_block(body, calls)
    }
    @ast.TsStmt::Block(block) => collect_calls_in_block(block, calls)
    @ast.TsStmt::Try(try_block, _, catch_block, finally_block) => {
      collect_calls_in_block(try_block, calls)
      match catch_block {
        Some(cb) => collect_calls_in_block(cb, calls)
        None => ()
      }
      match finally_block {
        Some(fb) => collect_calls_in_block(fb, calls)
        None => ()
      }
    }
    @ast.TsStmt::Switch(expr, cases) => {
      collect_calls_in_expr(expr, calls)
      for c in cases {
        collect_calls_in_block(c.body, calls)
      }
    }
    @ast.TsStmt::Throw(expr) => collect_calls_in_expr(expr, calls)
    _ => ()
  }
}

///|
fn collect_calls_in_expr(expr : @ast.TsExpr, calls : Array[String]) -> Unit {
  match expr {
    @ast.TsExpr::Call(name, args) => {
      // Direct function call
      if not(calls.contains(name)) {
        calls.push(name)
      }
      for arg in args {
        collect_calls_in_expr(arg, calls)
      }
    }
    @ast.TsExpr::MethodCall(receiver, _, args) => {
      collect_calls_in_expr(receiver, calls)
      for arg in args {
        collect_calls_in_expr(arg, calls)
      }
    }
    @ast.TsExpr::BinOp(_, left, right) => {
      collect_calls_in_expr(left, calls)
      collect_calls_in_expr(right, calls)
    }
    @ast.TsExpr::UnaryOp(_, operand) => collect_calls_in_expr(operand, calls)
    @ast.TsExpr::Cond(cond, then_e, else_e) => {
      collect_calls_in_expr(cond, calls)
      collect_calls_in_expr(then_e, calls)
      collect_calls_in_expr(else_e, calls)
    }
    @ast.TsExpr::PropAccess(obj, _) => collect_calls_in_expr(obj, calls)
    @ast.TsExpr::IndexAccess(obj, idx) => {
      collect_calls_in_expr(obj, calls)
      collect_calls_in_expr(idx, calls)
    }
    @ast.TsExpr::ArrayLit(elements) =>
      for elem in elements {
        collect_calls_in_expr(elem, calls)
      }
    @ast.TsExpr::ObjectLit(fields) =>
      for field in fields {
        let (_, value) = field
        collect_calls_in_expr(value, calls)
      }
    @ast.TsExpr::Yield(Some(inner)) | @ast.TsExpr::YieldStar(inner) =>
      collect_calls_in_expr(inner, calls)
    @ast.TsExpr::Await(inner) => collect_calls_in_expr(inner, calls)
    @ast.TsExpr::New(_, args) =>
      for arg in args {
        collect_calls_in_expr(arg, calls)
      }
    @ast.TsExpr::AssignExpr(_, value) => collect_calls_in_expr(value, calls)
    @ast.TsExpr::AssignPattern(_, value) => collect_calls_in_expr(value, calls)
    @ast.TsExpr::CompoundAssignExpr(target, _, value) => {
      collect_calls_in_expr(target, calls)
      collect_calls_in_expr(value, calls)
    }
    _ => ()
  }
}

///|
/// Find AOT groups starting from generator functions.
/// Returns groups where all member functions can be AOT compiled together.
pub fn find_aot_groups(
  ts_module : @ast.TsModule,
  graph : CallGraph,
) -> Array[AOTGroup] {
  let groups : Array[AOTGroup] = []

  // Find all generator functions
  for func in ts_module.funcs {
    if func.is_generator {
      match try_build_aot_group(ts_module, graph, func.name) {
        Some(group) => groups.push(group)
        None => ()
      }
    }
  }

  groups
}

///|
/// Try to build an AOT group starting from a generator function.
fn try_build_aot_group(
  ts_module : @ast.TsModule,
  graph : CallGraph,
  root : String,
) -> AOTGroup? {
  // Collect all functions reachable from root
  let reachable : Array[String] = []
  let visited : Map[String, Bool] = {}
  collect_reachable(graph, root, reachable, visited)

  // Check if all reachable functions are AOT-compilable
  for name in reachable {
    if not(is_function_aot_compatible(ts_module, name)) {
      return None
    }
  }

  // Check which functions have external callers
  let external_calls : Array[String] = []
  for name in reachable {
    if has_external_callers(graph, name, reachable) {
      external_calls.push(name)
    }
  }

  // If root has external callers (other than being the entry point), still allow
  // But other functions should not have external callers for full inlining
  Some({ root, members: reachable, external_calls })
}

///|
/// Collect all functions reachable from a starting function.
fn collect_reachable(
  graph : CallGraph,
  start : String,
  result : Array[String],
  visited : Map[String, Bool],
) -> Unit {
  match visited.get(start) {
    Some(true) => return
    _ => ()
  }
  visited[start] = true
  result.push(start)

  match graph.calls.get(start) {
    Some(callees) =>
      for callee in callees {
        // Only include if it's a known function in the ts_module
        if graph.functions.contains(callee) {
          collect_reachable(graph, callee, result, visited)
        }
      }
    None => ()
  }
}

///|
/// Check if a function has callers outside the given group.
fn has_external_callers(
  graph : CallGraph,
  name : String,
  group : Array[String],
) -> Bool {
  match graph.callers.get(name) {
    Some(callers) =>
      for caller in callers {
        if not(group.contains(caller)) {
          return true
        }
      }
    None => ()
  }
  false
}

///|
/// Check if a function is compatible with AOT compilation.
fn is_function_aot_compatible(ts_module : @ast.TsModule, name : String) -> Bool {
  for func in ts_module.funcs {
    if func.name == name {
      return is_func_body_aot_compatible(func)
    }
  }
  false
}

///|
/// Check if a function body is AOT-compatible (simplified check).
fn is_func_body_aot_compatible(func : @ast.TsFunc) -> Bool {
  // For now, check for common incompatible patterns
  // - eval
  // - with statement
  // - complex closures
  is_block_aot_compatible(func.body)
}

///|
fn is_block_aot_compatible(block : @ast.TsBlock) -> Bool {
  for stmt in block.stmts {
    if not(is_stmt_aot_compatible(stmt)) {
      return false
    }
  }
  true
}

///|
fn is_stmt_aot_compatible(stmt : @ast.TsStmt) -> Bool {
  match stmt {
    @ast.TsStmt::With(_, _) => false // with statement not compatible
    @ast.TsStmt::If(_, then_block, else_block) => {
      if not(is_block_aot_compatible(then_block)) {
        return false
      }
      match else_block {
        Some(eb) => is_block_aot_compatible(eb)
        None => true
      }
    }
    @ast.TsStmt::While(_, body)
    | @ast.TsStmt::DoWhile(_, body)
    | @ast.TsStmt::Block(body) => is_block_aot_compatible(body)
    @ast.TsStmt::For(_, _, _, body) => is_block_aot_compatible(body)
    @ast.TsStmt::ForOf(_, _, _, _, body)
    | @ast.TsStmt::ForIn(_, _, _, _, body) => is_block_aot_compatible(body)
    @ast.TsStmt::Try(try_block, _, catch_block, finally_block) => {
      if not(is_block_aot_compatible(try_block)) {
        return false
      }
      match catch_block {
        Some(cb) =>
          if not(is_block_aot_compatible(cb)) {
            return false
          }
        None => ()
      }
      match finally_block {
        Some(fb) => is_block_aot_compatible(fb)
        None => true
      }
    }
    @ast.TsStmt::Switch(_, cases) => {
      for c in cases {
        if not(is_block_aot_compatible(c.body)) {
          return false
        }
      }
      true
    }
    _ => true
  }
}

///|
/// Debug string for CallGraph.
pub fn CallGraph::debug_string(self : CallGraph) -> String {
  let mut result = "CallGraph:\n"
  for name in self.functions {
    result += "  \{name}:\n"
    match self.calls.get(name) {
      Some(callees) =>
        if callees.length() > 0 {
          result += "    calls: \{callees}\n"
        }
      None => ()
    }
    match self.callers.get(name) {
      Some(callers) =>
        if callers.length() > 0 {
          result += "    called by: \{callers}\n"
        }
      None => ()
    }
  }
  result
}

///|
/// Debug string for AOTGroup.
pub fn AOTGroup::debug_string(self : AOTGroup) -> String {
  let mut result = "AOTGroup(root=\{self.root}):\n"
  result += "  members: \{self.members}\n"
  if self.external_calls.length() > 0 {
    result += "  external_calls: \{self.external_calls}\n"
  }
  result
}
