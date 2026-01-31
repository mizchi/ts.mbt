// AOT Compilability Check
// Validates whether code can be AOT compiled.

///|
/// Result of AOT compilability check.
pub struct AOTCheckResult {
  /// Whether the code is AOT compilable
  compilable : Bool
  /// AOT groups that can be compiled
  groups : Array[AOTGroup]
  /// Functions that cannot be AOT compiled
  incompatible_funcs : Array[AOTIncompatibleFunc]
  /// Overall diagnostics
  diagnostics : Array[String]
}

///|
/// Information about a function that cannot be AOT compiled.
pub struct AOTIncompatibleFunc {
  name : String
  reason : String
}

///|
/// Check if a TypeScript module can be AOT compiled.
/// Returns detailed information about AOT compatibility.
pub fn check_aot_compilable(ts_module : @ast.TsModule) -> AOTCheckResult {
  let diagnostics : Array[String] = []
  let incompatible_funcs : Array[AOTIncompatibleFunc] = []

  // Check each function for AOT compatibility
  for func in ts_module.funcs {
    match check_func_aot_compatible(func) {
      Some(reason) => incompatible_funcs.push({ name: func.name, reason })
      None => ()
    }
  }

  // Build call graph
  let graph = build_call_graph(ts_module)

  // Find AOT groups
  let groups = find_aot_groups(ts_module, graph)

  // Determine overall compilability
  let has_generators = ts_module.funcs.iter().any(fn(f) { f.is_generator })
  let has_aot_groups = groups.length() > 0
  let compilable = if has_generators {
    has_aot_groups
  } else {
    // Non-generator code: check if all functions are compatible
    incompatible_funcs.length() == 0
  }

  // Add diagnostics
  if groups.length() > 0 {
    for group in groups {
      diagnostics.push(
        "AOT group found: \{group.root} with \{group.members.length()} members",
      )
      if group.external_calls.length() > 0 {
        diagnostics.push(
          "  Warning: \{group.external_calls.length()} functions have external callers",
        )
      }
    }
  }
  for inc in incompatible_funcs {
    diagnostics.push("Incompatible: \{inc.name} - \{inc.reason}")
  }
  { compilable, groups, incompatible_funcs, diagnostics }
}

///|
/// Check if a single function is AOT compatible.
/// Returns None if compatible, Some(reason) if not.
pub fn check_func_aot_compatible(func : @ast.TsFunc) -> String? {
  // Check for generator-specific issues
  if func.is_generator {
    let analysis = analyze_generator(func)
    if not(analysis.compilable) {
      return analysis.not_compilable_reason
    }
  }

  // Check for general incompatibilities
  check_block_aot_issues(func.body)
}

///|
fn check_block_aot_issues(block : @ast.TsBlock) -> String? {
  for stmt in block.stmts {
    match check_stmt_aot_issues(stmt) {
      Some(reason) => return Some(reason)
      None => continue
    }
  }
  None
}

///|
fn check_stmt_aot_issues(stmt : @ast.TsStmt) -> String? {
  match stmt {
    // with statement is never supported
    @ast.TsStmt::With(_, _) => Some("'with' statement not supported")
    // Check for eval calls
    @ast.TsStmt::Expr(expr) => check_expr_aot_issues(expr)
    @ast.TsStmt::Return(Some(expr)) => check_expr_aot_issues(expr)
    @ast.TsStmt::Var(_, _, init)
    | @ast.TsStmt::Let(_, _, init)
    | @ast.TsStmt::Const(_, _, init) => check_expr_aot_issues(init)
    @ast.TsStmt::Assign(_, expr) => check_expr_aot_issues(expr)
    @ast.TsStmt::CompoundAssign(_, _, expr) => check_expr_aot_issues(expr)
    @ast.TsStmt::If(cond, then_block, else_block) => {
      match check_expr_aot_issues(cond) {
        Some(r) => return Some(r)
        None => ()
      }
      match check_block_aot_issues(then_block) {
        Some(r) => return Some(r)
        None => ()
      }
      match else_block {
        Some(eb) => check_block_aot_issues(eb)
        None => None
      }
    }
    @ast.TsStmt::While(cond, body) | @ast.TsStmt::DoWhile(cond, body) => {
      match check_expr_aot_issues(cond) {
        Some(r) => return Some(r)
        None => ()
      }
      check_block_aot_issues(body)
    }
    @ast.TsStmt::For(init, cond, update, body) => {
      match init {
        Some(s) =>
          match check_stmt_aot_issues(s) {
            Some(r) => return Some(r)
            None => ()
          }
        None => ()
      }
      match cond {
        Some(e) =>
          match check_expr_aot_issues(e) {
            Some(r) => return Some(r)
            None => ()
          }
        None => ()
      }
      match update {
        Some(s) =>
          match check_stmt_aot_issues(s) {
            Some(r) => return Some(r)
            None => ()
          }
        None => ()
      }
      check_block_aot_issues(body)
    }
    @ast.TsStmt::ForOf(_, _, _, iter, body)
    | @ast.TsStmt::ForIn(_, _, _, iter, body) => {
      match check_expr_aot_issues(iter) {
        Some(r) => return Some(r)
        None => ()
      }
      check_block_aot_issues(body)
    }
    @ast.TsStmt::Block(block) => check_block_aot_issues(block)
    @ast.TsStmt::Try(try_block, _, catch_block, finally_block) => {
      match check_block_aot_issues(try_block) {
        Some(r) => return Some(r)
        None => ()
      }
      match catch_block {
        Some(cb) =>
          match check_block_aot_issues(cb) {
            Some(r) => return Some(r)
            None => ()
          }
        None => ()
      }
      match finally_block {
        Some(fb) => check_block_aot_issues(fb)
        None => None
      }
    }
    @ast.TsStmt::Switch(expr, cases) => {
      match check_expr_aot_issues(expr) {
        Some(r) => return Some(r)
        None => ()
      }
      for c in cases {
        match check_block_aot_issues(c.body) {
          Some(r) => return Some(r)
          None => continue
        }
      }
      None
    }
    @ast.TsStmt::Throw(expr) => check_expr_aot_issues(expr)
    _ => None
  }
}

///|
fn check_expr_aot_issues(expr : @ast.TsExpr) -> String? {
  match expr {
    // eval is not supported
    @ast.TsExpr::Call("eval", _) => Some("'eval' is not supported")
    // Function expressions - check if closure is AOT compatible
    @ast.TsExpr::FuncExpr(func) => check_func_expr_aot(func)
    @ast.TsExpr::ArrowFunc(params, body, _is_async) =>
      check_arrow_func_aot(params, body)
    // Recursive checks
    @ast.TsExpr::Call(_, args) => {
      for arg in args {
        match check_expr_aot_issues(arg) {
          Some(r) => return Some(r)
          None => continue
        }
      }
      None
    }
    @ast.TsExpr::CallExpr(callee, args) => {
      match check_expr_aot_issues(callee) {
        Some(r) => return Some(r)
        None => ()
      }
      for arg in args {
        match check_expr_aot_issues(arg) {
          Some(r) => return Some(r)
          None => continue
        }
      }
      None
    }
    @ast.TsExpr::MethodCall(receiver, _, args) => {
      match check_expr_aot_issues(receiver) {
        Some(r) => return Some(r)
        None => ()
      }
      for arg in args {
        match check_expr_aot_issues(arg) {
          Some(r) => return Some(r)
          None => continue
        }
      }
      None
    }
    @ast.TsExpr::BinOp(_, left, right) => {
      match check_expr_aot_issues(left) {
        Some(r) => return Some(r)
        None => ()
      }
      check_expr_aot_issues(right)
    }
    @ast.TsExpr::UnaryOp(_, operand) => check_expr_aot_issues(operand)
    @ast.TsExpr::Cond(cond, then_e, else_e) => {
      match check_expr_aot_issues(cond) {
        Some(r) => return Some(r)
        None => ()
      }
      match check_expr_aot_issues(then_e) {
        Some(r) => return Some(r)
        None => ()
      }
      check_expr_aot_issues(else_e)
    }
    @ast.TsExpr::PropAccess(obj, _) => check_expr_aot_issues(obj)
    @ast.TsExpr::IndexAccess(obj, idx) => {
      match check_expr_aot_issues(obj) {
        Some(r) => return Some(r)
        None => ()
      }
      check_expr_aot_issues(idx)
    }
    @ast.TsExpr::ArrayLit(elements) => {
      for elem in elements {
        match check_expr_aot_issues(elem) {
          Some(r) => return Some(r)
          None => continue
        }
      }
      None
    }
    @ast.TsExpr::ObjectLit(fields) => {
      for field in fields {
        let (_, value) = field
        match check_expr_aot_issues(value) {
          Some(r) => return Some(r)
          None => continue
        }
      }
      None
    }
    @ast.TsExpr::Yield(Some(inner)) | @ast.TsExpr::YieldStar(inner) =>
      check_expr_aot_issues(inner)
    @ast.TsExpr::Await(inner) => check_expr_aot_issues(inner)
    @ast.TsExpr::New(_, args) => {
      for arg in args {
        match check_expr_aot_issues(arg) {
          Some(r) => return Some(r)
          None => continue
        }
      }
      None
    }
    @ast.TsExpr::AssignExpr(_, value) => check_expr_aot_issues(value)
    @ast.TsExpr::AssignPattern(_, value) => check_expr_aot_issues(value)
    @ast.TsExpr::CompoundAssignExpr(target, _, value) => {
      match check_expr_aot_issues(target) {
        Some(r) => return Some(r)
        None => ()
      }
      check_expr_aot_issues(value)
    }
    _ => None
  }
}

///|
/// Quick check if source code is AOT compilable.
/// Parses and checks the code.
pub fn is_aot_compilable(source : String) -> Bool {
  let parser = @parser.Parser::from_source(source)
  let ts_module = parser.parse_module() catch { _ => return false }
  let result = check_aot_compilable(ts_module)
  result.compilable
}

///|
/// Get detailed AOT check result from source code.
/// Returns a result with compilable=false if parsing fails.
pub fn check_aot_compilable_source(source : String) -> AOTCheckResult {
  let parser = @parser.Parser::from_source(source)
  let ts_module = parser.parse_module() catch {
    e =>
      return {
        compilable: false,
        groups: [],
        incompatible_funcs: [],
        diagnostics: ["Parse error: \{e}"],
      }
  }
  check_aot_compilable(ts_module)
}

///|
/// Debug string for AOTCheckResult.
pub fn AOTCheckResult::debug_string(self : AOTCheckResult) -> String {
  let mut s = "AOTCheckResult:\n"
  s += "  compilable: \{self.compilable}\n"
  s += "  groups: \{self.groups.length()}\n"
  s += "  incompatible_funcs: \{self.incompatible_funcs.length()}\n"
  s += "  diagnostics:\n"
  for d in self.diagnostics {
    s += "    - \{d}\n"
  }
  s
}

///|
/// Check if an arrow function is AOT compatible.
fn check_arrow_func_aot(
  params : Array[@ast.TsParam],
  body : @ast.TsArrowBody,
) -> String? {
  // Analyze the closure with empty outer scope (conservative)
  let info = analyze_arrow_func(params, body, [])
  if not(info.compilable) {
    return info.not_compilable_reason
  }
  // Mutable captures are now supported (Phase 3)
  // Check body for other issues
  match body {
    @ast.TsArrowBody::ArrowExpr(expr) => check_expr_aot_issues(expr)
    @ast.TsArrowBody::ArrowBlock(block) => check_block_aot_issues(block)
  }
}

///|
/// Check if a function expression is AOT compatible.
fn check_func_expr_aot(func : @ast.TsFunc) -> String? {
  // Generator and async not supported in closures
  if func.is_generator {
    return Some("generator function expressions not supported")
  }
  if func.is_async {
    return Some("async function expressions not yet supported")
  }
  // Analyze the closure with empty outer scope (conservative)
  let info = analyze_func_expr(func, [])
  if not(info.compilable) {
    return info.not_compilable_reason
  }
  // Mutable captures are now supported (Phase 3)
  // Check body for other issues
  check_block_aot_issues(func.body)
}
