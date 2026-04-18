// Purity analysis - detect functions and expressions without side effects.

///|
/// Side effect classification.
pub(all) enum SideEffect {
  Pure // No side effects
  ReadGlobal // Reads global state
  WriteGlobal // Writes global state
  IO // Console, network, etc.
  Throws // May throw exception
  Unknown // Cannot determine
} derive(Eq, Debug)

///|
/// Purity information for a function.
pub(all) struct PurityInfo {
  is_pure : Bool
  effects : Array[SideEffect]
  // Functions called that may have side effects
  impure_calls : Array[String]
}

///|
pub fn PurityInfo::pure() -> PurityInfo {
  { is_pure: true, effects: [], impure_calls: [] }
}

///|
pub fn PurityInfo::impure(effect : SideEffect) -> PurityInfo {
  { is_pure: false, effects: [effect], impure_calls: [] }
}

///|
/// Known pure built-in functions.
fn is_known_pure_function(name : String) -> Bool {
  match name {
    // Math functions
    "Math.abs"
    | "Math.floor"
    | "Math.ceil"
    | "Math.round"
    | "Math.sqrt"
    | "Math.pow"
    | "Math.min"
    | "Math.max"
    | "Math.sin"
    | "Math.cos"
    | "Math.tan"
    | "Math.log"
    | "Math.exp" => true
    // Type conversions
    "Number" | "String" | "Boolean" | "parseInt" | "parseFloat" => true
    // String methods (most are pure)
    "charAt"
    | "charCodeAt"
    | "substring"
    | "slice"
    | "indexOf"
    | "lastIndexOf"
    | "toLowerCase"
    | "toUpperCase"
    | "trim"
    | "split"
    | "startsWith"
    | "endsWith"
    | "includes"
    | "repeat"
    | "padStart"
    | "padEnd"
    | "concat" => true
    // Array methods (non-mutating) - only ones not already listed
    "find" | "findIndex" | "filter" | "map" | "reduce" | "every" | "some" =>
      true
    // Object
    "Object.keys"
    | "Object.values"
    | "Object.entries"
    | "Object.hasOwnProperty" => true
    // JSON (parse can throw but is otherwise pure)
    "JSON.stringify" => true
    _ => false
  }
}

///|
/// Known impure functions.
fn is_known_impure_function(name : String) -> SideEffect? {
  match name {
    // Console
    "console.log"
    | "console.error"
    | "console.warn"
    | "console.info"
    | "console.debug"
    | "console.trace"
    | "console.dir"
    | "console.table" => Some(IO)
    // DOM
    "alert" | "confirm" | "prompt" => Some(IO)
    "document.write" | "document.writeln" => Some(IO)
    // Timing
    "setTimeout" | "setInterval" | "clearTimeout" | "clearInterval" => Some(IO)
    // Network
    "fetch" | "XMLHttpRequest" => Some(IO)
    // Storage
    "localStorage.setItem"
    | "localStorage.removeItem"
    | "localStorage.clear"
    | "sessionStorage.setItem"
    | "sessionStorage.removeItem"
    | "sessionStorage.clear" => Some(IO)
    // Mutating array methods
    "push"
    | "pop"
    | "shift"
    | "unshift"
    | "splice"
    | "sort"
    | "reverse"
    | "fill" => Some(WriteGlobal)
    // Date (current time)
    "Date.now" => Some(ReadGlobal)
    // Random
    "Math.random" => Some(ReadGlobal)
    _ => None
  }
}

///|
/// Check if an expression is pure (no side effects).
pub fn is_pure_expr(expr : @ast.TsExpr) -> Bool {
  analyze_expr_purity(expr).is_pure
}

///|
/// Analyze expression for purity.
pub fn analyze_expr_purity(expr : @ast.TsExpr) -> PurityInfo {
  match expr {
    // Literals are pure
    @ast.TsExpr::IntLit(_)
    | @ast.TsExpr::NumberLit(_)
    | @ast.TsExpr::StringLit(_)
    | @ast.TsExpr::BoolLit(_)
    | @ast.TsExpr::NullLit
    | @ast.TsExpr::ArrayHole => PurityInfo::pure()
    // Variable read is pure
    @ast.TsExpr::Var(_) => PurityInfo::pure()
    // Binary operations are pure if operands are pure
    @ast.TsExpr::BinOp(_, left, right) =>
      combine_purity(analyze_expr_purity(left), analyze_expr_purity(right))
    // Unary operations are mostly pure
    @ast.TsExpr::UnaryOp(op, operand) =>
      match op {
        @ast.TsUnaryOp::Delete => PurityInfo::impure(WriteGlobal)
        _ => analyze_expr_purity(operand)
      }
    // Array literal
    @ast.TsExpr::ArrayLit(elements) => {
      let mut result = PurityInfo::pure()
      for elem in elements {
        result = combine_purity(result, analyze_expr_purity(elem))
      }
      result
    }
    // Object literal
    @ast.TsExpr::ObjectLit(props) => {
      let mut result = PurityInfo::pure()
      for prop in props {
        result = combine_purity(result, analyze_expr_purity(prop.1))
      }
      result
    }
    // Function call
    @ast.TsExpr::Call(name, args) => analyze_call_purity(name, args)
    @ast.TsExpr::CallExpr(_, args) => {
      // Unknown function - assume impure
      let mut result = PurityInfo::impure(Unknown)
      for arg in args {
        result = combine_purity(result, analyze_expr_purity(arg))
      }
      result
    }
    // Method call
    @ast.TsExpr::MethodCall(receiver, method_name, args) =>
      analyze_method_call_purity(receiver, method_name, args)
    // Property access is pure
    @ast.TsExpr::PropAccess(obj, _) => analyze_expr_purity(obj)
    @ast.TsExpr::IndexAccess(arr, idx) =>
      combine_purity(analyze_expr_purity(arr), analyze_expr_purity(idx))
    // Conditional
    @ast.TsExpr::Cond(cond, then_e, else_e) =>
      combine_purity(
        analyze_expr_purity(cond),
        combine_purity(analyze_expr_purity(then_e), analyze_expr_purity(else_e)),
      )
    // Assignments are impure
    @ast.TsExpr::AssignExpr(_, _)
    | @ast.TsExpr::AssignPattern(_, _)
    | @ast.TsExpr::PropAssignExpr(_, _, _)
    | @ast.TsExpr::IndexAssignExpr(_, _, _)
    | @ast.TsExpr::CompoundAssignExpr(_, _, _) =>
      PurityInfo::impure(WriteGlobal)
    // New expression - may have side effects in constructor
    @ast.TsExpr::New(_, _) | @ast.TsExpr::NewExpr(_, _) =>
      PurityInfo::impure(Unknown)
    // Yield/await
    @ast.TsExpr::Yield(_) | @ast.TsExpr::YieldStar(_) | @ast.TsExpr::Await(_) =>
      PurityInfo::impure(Unknown)
    // Dynamic import
    @ast.TsExpr::DynamicImport(_) => PurityInfo::impure(IO)
    // Function expressions are pure (creating them doesn't execute)
    @ast.TsExpr::ArrowFunc(_, _, _) | @ast.TsExpr::FuncExpr(_) =>
      PurityInfo::pure()
    // Sequence
    @ast.TsExpr::Seq(left, right) =>
      combine_purity(analyze_expr_purity(left), analyze_expr_purity(right))
    // Template literals
    @ast.TsExpr::TemplateLiteral(_, exprs) => {
      let mut result = PurityInfo::pure()
      for expr in exprs {
        result = combine_purity(result, analyze_expr_purity(expr))
      }
      result
    }
    @ast.TsExpr::TaggedTemplate(_, _, _, _) => PurityInfo::impure(Unknown) // Tag function may have side effects
    _ => PurityInfo::impure(Unknown)
  }
}

///|
fn analyze_call_purity(name : String, args : Array[@ast.TsExpr]) -> PurityInfo {
  // Check args purity first
  let mut args_purity = PurityInfo::pure()
  for arg in args {
    args_purity = combine_purity(args_purity, analyze_expr_purity(arg))
  }
  // Check if function is known pure/impure
  if is_known_pure_function(name) {
    return args_purity
  }
  match is_known_impure_function(name) {
    Some(effect) => {
      let result = PurityInfo::impure(effect)
      combine_purity(result, args_purity)
    }
    None => {
      // Unknown function - assume impure
      let result = PurityInfo::impure(Unknown)
      result.impure_calls.push(name)
      combine_purity(result, args_purity)
    }
  }
}

///|
fn analyze_method_call_purity(
  receiver : @ast.TsExpr,
  method_name : String,
  args : Array[@ast.TsExpr],
) -> PurityInfo {
  let recv_purity = analyze_expr_purity(receiver)
  let mut args_purity = PurityInfo::pure()
  for arg in args {
    args_purity = combine_purity(args_purity, analyze_expr_purity(arg))
  }
  // Check if method is known pure/impure
  if is_known_pure_function(method_name) {
    return combine_purity(recv_purity, args_purity)
  }
  match is_known_impure_function(method_name) {
    Some(effect) =>
      combine_purity(
        combine_purity(recv_purity, args_purity),
        PurityInfo::impure(effect),
      )
    None =>
      // Unknown method - assume impure
      combine_purity(
        combine_purity(recv_purity, args_purity),
        PurityInfo::impure(Unknown),
      )
  }
}

///|
/// Combine two purity results.
fn combine_purity(a : PurityInfo, b : PurityInfo) -> PurityInfo {
  if a.is_pure && b.is_pure {
    return PurityInfo::pure()
  }
  let effects : Array[SideEffect] = []
  for e in a.effects {
    if !effects.contains(e) {
      effects.push(e)
    }
  }
  for e in b.effects {
    if !effects.contains(e) {
      effects.push(e)
    }
  }
  let impure_calls : Array[String] = []
  for c in a.impure_calls {
    if !impure_calls.contains(c) {
      impure_calls.push(c)
    }
  }
  for c in b.impure_calls {
    if !impure_calls.contains(c) {
      impure_calls.push(c)
    }
  }
  { is_pure: false, effects, impure_calls }
}

///|
/// Analyze a function for purity.
pub fn analyze_func_purity(func : @ast.TsFunc) -> PurityInfo {
  let mut result = PurityInfo::pure()
  for stmt in func.body.stmts {
    result = combine_purity(result, analyze_stmt_purity(stmt))
  }
  result
}

///|
fn analyze_stmt_purity(stmt : @ast.TsStmt) -> PurityInfo {
  match stmt {
    @ast.TsStmt::Expr(e) => analyze_expr_purity(e)
    @ast.TsStmt::Return(Some(e)) => analyze_expr_purity(e)
    @ast.TsStmt::Return(None) => PurityInfo::pure()
    @ast.TsStmt::Throw(_) => PurityInfo::impure(Throws)
    @ast.TsStmt::Var(_, _, init)
    | @ast.TsStmt::Let(_, _, init)
    | @ast.TsStmt::Const(_, _, init) => analyze_expr_purity(init)
    @ast.TsStmt::Assign(_, e) => {
      let expr_purity = analyze_expr_purity(e)
      combine_purity(expr_purity, PurityInfo::impure(WriteGlobal))
    }
    @ast.TsStmt::If(cond, then_block, else_block) => {
      let mut result = analyze_expr_purity(cond)
      for s in then_block.stmts {
        result = combine_purity(result, analyze_stmt_purity(s))
      }
      match else_block {
        Some(eb) =>
          for s in eb.stmts {
            result = combine_purity(result, analyze_stmt_purity(s))
          }
        None => ()
      }
      result
    }
    @ast.TsStmt::While(cond, body) => {
      let mut result = analyze_expr_purity(cond)
      for s in body.stmts {
        result = combine_purity(result, analyze_stmt_purity(s))
      }
      result
    }
    @ast.TsStmt::For(init, cond, update, body) => {
      let mut result = PurityInfo::pure()
      match init {
        Some(i) => result = combine_purity(result, analyze_stmt_purity(i))
        None => ()
      }
      match cond {
        Some(c) => result = combine_purity(result, analyze_expr_purity(c))
        None => ()
      }
      match update {
        Some(u) => result = combine_purity(result, analyze_stmt_purity(u))
        None => ()
      }
      for s in body.stmts {
        result = combine_purity(result, analyze_stmt_purity(s))
      }
      result
    }
    @ast.TsStmt::Block(block) => {
      let mut result = PurityInfo::pure()
      for s in block.stmts {
        result = combine_purity(result, analyze_stmt_purity(s))
      }
      result
    }
    @ast.TsStmt::Try(try_block, _, catch_block, finally_block) => {
      let mut result = PurityInfo::pure()
      for s in try_block.stmts {
        result = combine_purity(result, analyze_stmt_purity(s))
      }
      match catch_block {
        Some(cb) =>
          for s in cb.stmts {
            result = combine_purity(result, analyze_stmt_purity(s))
          }
        None => ()
      }
      match finally_block {
        Some(fb) =>
          for s in fb.stmts {
            result = combine_purity(result, analyze_stmt_purity(s))
          }
        None => ()
      }
      result
    }
    _ => PurityInfo::pure()
  }
}
