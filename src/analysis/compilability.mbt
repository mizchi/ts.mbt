// Compilability analysis - detect functions that can be compiled to wasm-gc.

///|
/// Result of compilability analysis.
pub(all) enum CompilabilityResult {
  Compilable
  NotCompilable(String) // Reason
}

///|
pub fn CompilabilityResult::is_compilable(self : CompilabilityResult) -> Bool {
  match self {
    Compilable => true
    NotCompilable(_) => false
  }
}

///|
/// Check if a function can be compiled to wasm-gc.
pub fn can_compile_to_wasm(func : @ast.TsFunc) -> CompilabilityResult {
  // Check if generator or async
  if func.is_generator {
    return NotCompilable("generator functions not supported")
  }
  if func.is_async {
    return NotCompilable("async functions not supported")
  }
  // Check all statements in body. Local reusable function values are only
  // accepted when they are called directly in the same function body.
  let local_function_values : Map[String, @ast.TsExpr] = {}
  for stmt in func.body.stmts {
    match can_compile_stmt_with_local_functions(stmt, local_function_values) {
      NotCompilable(reason) => return NotCompilable(reason)
      Compilable => continue
    }
  }
  Compilable
}

///|
/// Check if a statement can be compiled.
fn can_compile_stmt(stmt : @ast.TsStmt) -> CompilabilityResult {
  match stmt {
    // Supported: variable declarations with simple bindings
    @ast.TsStmt::Var(binding, _, init)
    | @ast.TsStmt::Let(binding, _, init)
    | @ast.TsStmt::Const(binding, _, init) =>
      match binding {
        @ast.TsBinding::Ident(_) => can_compile_expr(init)
        @ast.TsBinding::Array(_) =>
          NotCompilable("array destructuring not supported")
        @ast.TsBinding::Object(_) =>
          NotCompilable("object destructuring not supported")
        @ast.TsBinding::Target(_) =>
          NotCompilable("target binding not supported")
      }
    // Supported: assignments
    @ast.TsStmt::Assign(_, expr) => can_compile_expr(expr)
    @ast.TsStmt::CompoundAssign(_, _, expr) => can_compile_expr(expr)
    @ast.TsStmt::IndexAssign(arr, idx, val) => {
      match can_compile_expr(arr) {
        NotCompilable(r) => return NotCompilable(r)
        Compilable => ()
      }
      match can_compile_expr(idx) {
        NotCompilable(r) => return NotCompilable(r)
        Compilable => ()
      }
      can_compile_expr(val)
    }
    @ast.TsStmt::PropAssign(obj, _, val) => {
      match can_compile_expr(obj) {
        NotCompilable(r) => return NotCompilable(r)
        Compilable => ()
      }
      can_compile_expr(val)
    }
    // Supported: expression statement
    @ast.TsStmt::Expr(expr) => can_compile_expr(expr)
    // Supported: empty
    @ast.TsStmt::Empty => Compilable
    // Supported: block
    @ast.TsStmt::Block(block) => {
      for s in block.stmts {
        match can_compile_stmt(s) {
          NotCompilable(r) => return NotCompilable(r)
          Compilable => continue
        }
      }
      Compilable
    }
    // Supported: label (but not labeled break/continue)
    @ast.TsStmt::Label(_, inner) => can_compile_stmt(inner)
    // Supported: return
    @ast.TsStmt::Return(None) => Compilable
    @ast.TsStmt::Return(Some(expr)) => can_compile_expr(expr)
    // Supported: if
    @ast.TsStmt::If(cond, then_block, else_block) => {
      match can_compile_expr(cond) {
        NotCompilable(r) => return NotCompilable(r)
        Compilable => ()
      }
      for s in then_block.stmts {
        match can_compile_stmt(s) {
          NotCompilable(r) => return NotCompilable(r)
          Compilable => continue
        }
      }
      match else_block {
        Some(eb) =>
          for s in eb.stmts {
            match can_compile_stmt(s) {
              NotCompilable(r) => return NotCompilable(r)
              Compilable => continue
            }
          }
        None => ()
      }
      Compilable
    }
    // Supported: while, do-while
    @ast.TsStmt::While(cond, body) | @ast.TsStmt::DoWhile(cond, body) => {
      match can_compile_expr(cond) {
        NotCompilable(r) => return NotCompilable(r)
        Compilable => ()
      }
      for s in body.stmts {
        match can_compile_stmt(s) {
          NotCompilable(r) => return NotCompilable(r)
          Compilable => continue
        }
      }
      Compilable
    }
    // Supported: for
    @ast.TsStmt::For(init, cond, update, body) => {
      match init {
        Some(i) =>
          match can_compile_stmt(i) {
            NotCompilable(r) => return NotCompilable(r)
            Compilable => ()
          }
        None => ()
      }
      match cond {
        Some(c) =>
          match can_compile_expr(c) {
            NotCompilable(r) => return NotCompilable(r)
            Compilable => ()
          }
        None => ()
      }
      match update {
        Some(u) =>
          match can_compile_stmt(u) {
            NotCompilable(r) => return NotCompilable(r)
            Compilable => ()
          }
        None => ()
      }
      for s in body.stmts {
        match can_compile_stmt(s) {
          NotCompilable(r) => return NotCompilable(r)
          Compilable => continue
        }
      }
      Compilable
    }
    // Supported: for-of (limited)
    @ast.TsStmt::ForOf(_, binding, _, iterable, body) =>
      match binding {
        @ast.TsBinding::Ident(_) => {
          match can_compile_expr(iterable) {
            NotCompilable(r) => return NotCompilable(r)
            Compilable => ()
          }
          for s in body.stmts {
            match can_compile_stmt(s) {
              NotCompilable(r) => return NotCompilable(r)
              Compilable => continue
            }
          }
          Compilable
        }
        _ => NotCompilable("for-of with destructuring not supported")
      }
    // Supported: switch
    @ast.TsStmt::Switch(discriminant, cases) => {
      match can_compile_expr(discriminant) {
        NotCompilable(r) => return NotCompilable(r)
        Compilable => ()
      }
      for case in cases {
        match case.test_expr {
          Some(e) =>
            match can_compile_expr(e) {
              NotCompilable(r) => return NotCompilable(r)
              Compilable => ()
            }
          None => ()
        }
        for s in case.body.stmts {
          match can_compile_stmt(s) {
            NotCompilable(r) => return NotCompilable(r)
            Compilable => continue
          }
        }
      }
      Compilable
    }
    // Supported: break/continue without labels
    @ast.TsStmt::Break(None) | @ast.TsStmt::Continue(None) => Compilable
    @ast.TsStmt::Break(Some(_)) => NotCompilable("labeled break not supported")
    @ast.TsStmt::Continue(Some(_)) =>
      NotCompilable("labeled continue not supported")
    // Supported: debugger (no-op)
    @ast.TsStmt::Debugger => Compilable
    // Not supported: throw, try/catch
    @ast.TsStmt::Throw(_) => NotCompilable("throw not supported")
    @ast.TsStmt::Try(_, _, _, _) => NotCompilable("try/catch not supported")
    // Not supported: with
    @ast.TsStmt::With(_, _) => NotCompilable("with statement not supported")
    // Not supported: for-in, for-await-of
    @ast.TsStmt::ForIn(_, _, _, _, _) => NotCompilable("for-in not supported")
    @ast.TsStmt::ForAwaitOf(_, _, _, _, _) =>
      NotCompilable("for-await-of not supported")
  }
}

///|
fn resolve_local_function_value_for_analysis(
  local_function_values : Map[String, @ast.TsExpr],
  init : @ast.TsExpr,
) -> @ast.TsExpr? {
  match init {
    @ast.TsExpr::ArrowFunc(_, _, _) | @ast.TsExpr::FuncExpr(_) => Some(init)
    @ast.TsExpr::Var(source_name) =>
      match local_function_values.get(source_name) {
        Some(source_func) => Some(source_func)
        None => None
      }
    @ast.TsExpr::Cond(
      _,
      @ast.TsExpr::Var(then_name),
      @ast.TsExpr::Var(else_name)
    ) =>
      if local_function_values.contains(then_name) &&
        local_function_values.contains(else_name) {
        Some(init)
      } else {
        None
      }
    @ast.TsExpr::CallExpr(producer, producer_args) =>
      resolve_returned_local_function_value_for_analysis(
        local_function_values, producer, producer_args,
      )
    _ => None
  }
}

///|
fn make_static_function_value_iife_map_for_analysis(
  local_function_values : Map[String, @ast.TsExpr],
  params : Array[@ast.TsParam],
  args : Array[@ast.TsExpr],
) -> Map[String, @ast.TsExpr]? {
  if params.length() != args.length() {
    return None
  }
  let body_function_values = local_function_values.copy()
  for i, param in params {
    if param.is_rest {
      return None
    }
    match param.default {
      Some(_) => return None
      None => ()
    }
    match
      resolve_local_function_value_for_analysis(local_function_values, args[i]) {
      Some(function_value) => body_function_values[param.name] = function_value
      None => return None
    }
  }
  Some(body_function_values)
}

///|
fn resolve_returned_local_function_value_for_analysis(
  local_function_values : Map[String, @ast.TsExpr],
  producer : @ast.TsExpr,
  producer_args : Array[@ast.TsExpr],
) -> @ast.TsExpr? {
  match producer {
    @ast.TsExpr::ArrowFunc(params, body, is_async) => {
      if is_async {
        return None
      }
      match
        make_static_function_value_iife_map_for_analysis(
          local_function_values, params, producer_args,
        ) {
        Some(body_function_values) => {
          let returned_expr = match body {
            @ast.TsArrowBody::ArrowExpr(expr) => Some(expr)
            @ast.TsArrowBody::ArrowBlock(block) =>
              iife_return_expr_for_analysis(block)
          }
          match returned_expr {
            Some(expr) =>
              resolve_local_function_value_for_analysis(
                body_function_values, expr,
              )
            None => None
          }
        }
        None => None
      }
    }
    @ast.TsExpr::FuncExpr(func) => {
      if func.is_async || func.is_generator {
        return None
      }
      match
        make_static_function_value_iife_map_for_analysis(
          local_function_values,
          func.params,
          producer_args,
        ) {
        Some(body_function_values) =>
          match iife_return_expr_for_analysis(func.body) {
            Some(expr) =>
              resolve_local_function_value_for_analysis(
                body_function_values, expr,
              )
            None => None
          }
        None => None
      }
    }
    _ => None
  }
}

///|
fn register_local_function_value_for_analysis(
  local_function_values : Map[String, @ast.TsExpr],
  name : String,
  init : @ast.TsExpr,
) -> Bool {
  match resolve_local_function_value_for_analysis(local_function_values, init) {
    Some(function_value) => {
      local_function_values[name] = function_value
      true
    }
    None => false
  }
}

///|
fn can_compile_stmt_with_local_functions(
  stmt : @ast.TsStmt,
  local_function_values : Map[String, @ast.TsExpr],
) -> CompilabilityResult {
  match stmt {
    @ast.TsStmt::Var(binding, _, init)
    | @ast.TsStmt::Let(binding, _, init)
    | @ast.TsStmt::Const(binding, _, init) =>
      match binding {
        @ast.TsBinding::Ident(name) =>
          if register_local_function_value_for_analysis(
              local_function_values, name, init,
            ) {
            Compilable
          } else {
            can_compile_expr_with_local_functions(init, local_function_values)
          }
        @ast.TsBinding::Array(_) =>
          NotCompilable("array destructuring not supported")
        @ast.TsBinding::Object(_) =>
          NotCompilable("object destructuring not supported")
        @ast.TsBinding::Target(_) =>
          NotCompilable("target binding not supported")
      }
    @ast.TsStmt::Assign(name, expr) => {
      match local_function_values.get(name) {
        Some(_) =>
          if register_local_function_value_for_analysis(
              local_function_values, name, expr,
            ) {
            return Compilable
          } else {
            return NotCompilable("function value reassignment not supported")
          }
        None => ()
      }
      can_compile_expr_with_local_functions(expr, local_function_values)
    }
    @ast.TsStmt::CompoundAssign(name, _, expr) => {
      match local_function_values.get(name) {
        Some(_) =>
          return NotCompilable("function value reassignment not supported")
        None => ()
      }
      can_compile_expr_with_local_functions(expr, local_function_values)
    }
    @ast.TsStmt::IndexAssign(arr, idx, val) => {
      match can_compile_expr_with_local_functions(arr, local_function_values) {
        NotCompilable(r) => return NotCompilable(r)
        Compilable => ()
      }
      match can_compile_expr_with_local_functions(idx, local_function_values) {
        NotCompilable(r) => return NotCompilable(r)
        Compilable => ()
      }
      can_compile_expr_with_local_functions(val, local_function_values)
    }
    @ast.TsStmt::PropAssign(obj, _, val) => {
      match can_compile_expr_with_local_functions(obj, local_function_values) {
        NotCompilable(r) => return NotCompilable(r)
        Compilable => ()
      }
      can_compile_expr_with_local_functions(val, local_function_values)
    }
    @ast.TsStmt::Expr(expr) =>
      can_compile_expr_with_local_functions(expr, local_function_values)
    @ast.TsStmt::Empty => Compilable
    @ast.TsStmt::Block(block) =>
      can_compile_block_with_local_functions(block, local_function_values)
    @ast.TsStmt::Label(_, inner) =>
      can_compile_stmt_with_local_functions(inner, local_function_values)
    @ast.TsStmt::Return(None) => Compilable
    @ast.TsStmt::Return(Some(expr)) =>
      can_compile_expr_with_local_functions(expr, local_function_values)
    @ast.TsStmt::If(cond, then_block, else_block) => {
      match can_compile_expr_with_local_functions(cond, local_function_values) {
        NotCompilable(r) => return NotCompilable(r)
        Compilable => ()
      }
      match
        can_compile_block_with_local_functions(
          then_block, local_function_values,
        ) {
        NotCompilable(r) => return NotCompilable(r)
        Compilable => ()
      }
      match else_block {
        Some(eb) =>
          can_compile_block_with_local_functions(eb, local_function_values)
        None => Compilable
      }
    }
    @ast.TsStmt::While(cond, body) | @ast.TsStmt::DoWhile(cond, body) => {
      match can_compile_expr_with_local_functions(cond, local_function_values) {
        NotCompilable(r) => return NotCompilable(r)
        Compilable => ()
      }
      can_compile_block_with_local_functions(body, local_function_values)
    }
    @ast.TsStmt::For(init, cond, update, body) => {
      match init {
        Some(i) =>
          match
            can_compile_stmt_with_local_functions(i, local_function_values) {
            NotCompilable(r) => return NotCompilable(r)
            Compilable => ()
          }
        None => ()
      }
      match cond {
        Some(c) =>
          match
            can_compile_expr_with_local_functions(c, local_function_values) {
            NotCompilable(r) => return NotCompilable(r)
            Compilable => ()
          }
        None => ()
      }
      match update {
        Some(u) =>
          match
            can_compile_stmt_with_local_functions(u, local_function_values) {
            NotCompilable(r) => return NotCompilable(r)
            Compilable => ()
          }
        None => ()
      }
      can_compile_block_with_local_functions(body, local_function_values)
    }
    @ast.TsStmt::ForOf(kind, binding, type_, iterable, body) => {
      match
        can_compile_expr_with_local_functions(iterable, local_function_values) {
        NotCompilable(r) => return NotCompilable(r)
        Compilable => ()
      }
      match
        can_compile_stmt(
          @ast.TsStmt::ForOf(kind, binding, type_, iterable, body),
        ) {
        NotCompilable(r) => NotCompilable(r)
        Compilable =>
          can_compile_block_with_local_functions(body, local_function_values)
      }
    }
    @ast.TsStmt::Switch(discriminant, cases) => {
      match
        can_compile_expr_with_local_functions(
          discriminant, local_function_values,
        ) {
        NotCompilable(r) => return NotCompilable(r)
        Compilable => ()
      }
      for case in cases {
        match case.test_expr {
          Some(e) =>
            match
              can_compile_expr_with_local_functions(e, local_function_values) {
              NotCompilable(r) => return NotCompilable(r)
              Compilable => ()
            }
          None => ()
        }
        match
          can_compile_block_with_local_functions(
            case.body,
            local_function_values,
          ) {
          NotCompilable(r) => return NotCompilable(r)
          Compilable => ()
        }
      }
      Compilable
    }
    _ => can_compile_stmt(stmt)
  }
}

///|
fn can_compile_block_with_local_functions(
  block : @ast.TsBlock,
  local_function_values : Map[String, @ast.TsExpr],
) -> CompilabilityResult {
  for s in block.stmts {
    match can_compile_stmt_with_local_functions(s, local_function_values) {
      NotCompilable(r) => return NotCompilable(r)
      Compilable => continue
    }
  }
  Compilable
}

///|
/// Check if an expression can be compiled.
fn can_compile_expr(expr : @ast.TsExpr) -> CompilabilityResult {
  match expr {
    // Supported: literals
    @ast.TsExpr::IntLit(_)
    | @ast.TsExpr::NumberLit(_)
    | @ast.TsExpr::BoolLit(_)
    | @ast.TsExpr::StringLit(_)
    | @ast.TsExpr::NullLit
    | @ast.TsExpr::ArrayHole => Compilable
    // Not supported: BigInt
    @ast.TsExpr::BigIntLit(_) => NotCompilable("BigInt not supported")
    // Supported: variable reference
    @ast.TsExpr::Var(_) => Compilable
    // Supported: binary and unary ops
    @ast.TsExpr::BinOp(_, left, right) => {
      match can_compile_expr(left) {
        NotCompilable(r) => return NotCompilable(r)
        Compilable => ()
      }
      can_compile_expr(right)
    }
    @ast.TsExpr::UnaryOp(op, operand) =>
      match op {
        @ast.TsUnaryOp::Delete => NotCompilable("delete operator not supported")
        _ => can_compile_expr(operand)
      }
    // Supported: conditional
    @ast.TsExpr::Cond(cond, then_e, else_e) => {
      match can_compile_expr(cond) {
        NotCompilable(r) => return NotCompilable(r)
        Compilable => ()
      }
      match can_compile_expr(then_e) {
        NotCompilable(r) => return NotCompilable(r)
        Compilable => ()
      }
      can_compile_expr(else_e)
    }
    // Supported: array literal
    @ast.TsExpr::ArrayLit(elements) => {
      for elem in elements {
        match elem {
          @ast.TsExpr::Spread(inner) =>
            match can_compile_expr(inner) {
              NotCompilable(r) => return NotCompilable(r)
              Compilable => ()
            }
          _ =>
            match can_compile_expr(elem) {
              NotCompilable(r) => return NotCompilable(r)
              Compilable => ()
            }
        }
      }
      Compilable
    }
    // Supported: index access
    @ast.TsExpr::IndexAccess(arr, idx) => {
      match can_compile_expr(arr) {
        NotCompilable(r) => return NotCompilable(r)
        Compilable => ()
      }
      can_compile_expr(idx)
    }
    // Supported: property access
    @ast.TsExpr::PropAccess(obj, _) => can_compile_expr(obj)
    // Supported: assignments
    @ast.TsExpr::AssignExpr(_, value) => can_compile_expr(value)
    @ast.TsExpr::AssignPattern(_, _) =>
      NotCompilable("destructuring assignment not supported")
    @ast.TsExpr::PropAssignExpr(obj, _, value) => {
      match can_compile_expr(obj) {
        NotCompilable(r) => return NotCompilable(r)
        Compilable => ()
      }
      can_compile_expr(value)
    }
    @ast.TsExpr::IndexAssignExpr(arr, idx, value) => {
      match can_compile_expr(arr) {
        NotCompilable(r) => return NotCompilable(r)
        Compilable => ()
      }
      match can_compile_expr(idx) {
        NotCompilable(r) => return NotCompilable(r)
        Compilable => ()
      }
      can_compile_expr(value)
    }
    @ast.TsExpr::CompoundAssignExpr(left, _, right) => {
      match can_compile_expr(left) {
        NotCompilable(r) => return NotCompilable(r)
        Compilable => ()
      }
      can_compile_expr(right)
    }
    // Supported: named call (limited)
    @ast.TsExpr::Call(name, args) =>
      // Check if it's a known compilable function
      if is_compilable_call(name) {
        let mut spread_index = -1
        for i, arg in args {
          match arg {
            @ast.TsExpr::Spread(inner) =>
              if spread_index >= 0 {
                return NotCompilable("multiple spread arguments not supported")
              } else {
                spread_index = i
                match can_compile_expr(inner) {
                  NotCompilable(r) => return NotCompilable(r)
                  Compilable => ()
                }
              }
            _ =>
              match can_compile_expr(arg) {
                NotCompilable(r) => return NotCompilable(r)
                Compilable => ()
              }
          }
        }
        if spread_index >= 0 && spread_index != args.length() - 1 {
          return NotCompilable("spread argument must be last in call")
        }
        Compilable
      } else {
        // User-defined functions need to be checked separately
        // For now, allow named calls (will fail at codegen if not found)
        let mut spread_index = -1
        for i, arg in args {
          match arg {
            @ast.TsExpr::Spread(inner) =>
              if spread_index >= 0 {
                return NotCompilable("multiple spread arguments not supported")
              } else {
                spread_index = i
                match can_compile_expr(inner) {
                  NotCompilable(r) => return NotCompilable(r)
                  Compilable => ()
                }
              }
            _ =>
              match can_compile_expr(arg) {
                NotCompilable(r) => return NotCompilable(r)
                Compilable => ()
              }
          }
        }
        if spread_index >= 0 && spread_index != args.length() - 1 {
          return NotCompilable("spread argument must be last in call")
        }
        Compilable
      }
    @ast.TsExpr::CallExpr(@ast.TsExpr::Var(name), args) =>
      can_compile_expr(@ast.TsExpr::Call(name, args))
    @ast.TsExpr::CallExpr(@ast.TsExpr::ArrowFunc(params, body, is_async), args) =>
      can_compile_arrow_iife(params, body, is_async, args)
    @ast.TsExpr::CallExpr(@ast.TsExpr::FuncExpr(func), args) =>
      can_compile_func_expr_iife(func, args)
    @ast.TsExpr::CallExpr(
      @ast.TsExpr::Cond(
        cond,
        @ast.TsExpr::Var(then_name),
        @ast.TsExpr::Var(else_name)
      ),
      args
    ) => {
      match can_compile_expr(cond) {
        NotCompilable(r) => return NotCompilable(r)
        Compilable => ()
      }
      match can_compile_expr(@ast.TsExpr::Call(then_name, args)) {
        NotCompilable(r) => return NotCompilable(r)
        Compilable => ()
      }
      can_compile_expr(@ast.TsExpr::Call(else_name, args))
    }
    // Not supported: arbitrary call expression
    @ast.TsExpr::CallExpr(_, _) =>
      NotCompilable("arbitrary call expression not supported")
    // Supported: method call (limited)
    @ast.TsExpr::MethodCall(receiver, method_name, args) => {
      match can_compile_expr(receiver) {
        NotCompilable(r) => return NotCompilable(r)
        Compilable => ()
      }
      for arg in args {
        match can_compile_expr(arg) {
          NotCompilable(r) => return NotCompilable(r)
          Compilable => continue
        }
      }
      // Check if method is compilable
      if is_compilable_method(method_name) {
        Compilable
      } else {
        NotCompilable("method '\{method_name}' not supported")
      }
    }
    // Supported: new with type name
    @ast.TsExpr::New(_, args) => {
      for arg in args {
        match can_compile_expr(arg) {
          NotCompilable(r) => return NotCompilable(r)
          Compilable => continue
        }
      }
      Compilable
    }
    // Not supported: arbitrary new expression
    @ast.TsExpr::NewExpr(_, _) =>
      NotCompilable("arbitrary new expression not supported")
    // Not supported: generators/async
    @ast.TsExpr::Yield(_) => NotCompilable("yield not supported")
    @ast.TsExpr::YieldStar(_) => NotCompilable("yield* not supported")
    @ast.TsExpr::Await(_) => NotCompilable("await not supported")
    // Not supported: dynamic import
    @ast.TsExpr::DynamicImport(_) =>
      NotCompilable("dynamic import not supported")
    @ast.TsExpr::ImportMeta => NotCompilable("import.meta not supported")
    // Supported: template literals (string-only expressions)
    @ast.TsExpr::TemplateLiteral(_, exprs) => {
      for expr in exprs {
        match can_compile_expr(expr) {
          NotCompilable(r) => return NotCompilable(r)
          Compilable => continue
        }
      }
      Compilable
    }
    @ast.TsExpr::TaggedTemplate(_, _, _, _) =>
      NotCompilable("tagged templates not supported")
    // Not supported: comma operator
    @ast.TsExpr::Seq(left, right) => {
      match can_compile_expr(left) {
        NotCompilable(r) => return NotCompilable(r)
        Compilable => ()
      }
      can_compile_expr(right)
    }
    // Not supported: spread
    @ast.TsExpr::Spread(_) => NotCompilable("spread operator not supported")
    @ast.TsExpr::ComputedProp(key, value) =>
      match eval_const(key) {
        ConstValue::NotConst =>
          NotCompilable("computed property key must be constant")
        _ => can_compile_expr(value)
      }
    @ast.TsExpr::ObjectLit(fields) => {
      for item in fields {
        let (key, value) = item
        if key.has_prefix("@@spread:") {
          return NotCompilable("object spread not supported")
        }
        if key.has_prefix("@@get:") || key.has_prefix("@@set:") {
          return NotCompilable("object accessors not supported")
        }
        match can_compile_expr(value) {
          NotCompilable(r) => return NotCompilable(r)
          Compilable => ()
        }
      }
      Compilable
    }
    // Function expressions: could be supported but complex due to closures
    @ast.TsExpr::ArrowFunc(_, _, _) =>
      NotCompilable("arrow functions not supported (closures)")
    @ast.TsExpr::FuncExpr(_) =>
      NotCompilable("function expressions not supported (closures)")
  }
}

///|
fn can_compile_expr_with_local_functions(
  expr : @ast.TsExpr,
  local_function_values : Map[String, @ast.TsExpr],
) -> CompilabilityResult {
  match expr {
    @ast.TsExpr::Var(name) =>
      match local_function_values.get(name) {
        Some(_) => NotCompilable("function value escape not supported")
        None => Compilable
      }
    @ast.TsExpr::BinOp(_, left, right) => {
      match can_compile_expr_with_local_functions(left, local_function_values) {
        NotCompilable(r) => return NotCompilable(r)
        Compilable => ()
      }
      can_compile_expr_with_local_functions(right, local_function_values)
    }
    @ast.TsExpr::UnaryOp(op, operand) =>
      match op {
        @ast.TsUnaryOp::Delete => NotCompilable("delete operator not supported")
        _ =>
          can_compile_expr_with_local_functions(operand, local_function_values)
      }
    @ast.TsExpr::Cond(cond, then_e, else_e) => {
      match can_compile_expr_with_local_functions(cond, local_function_values) {
        NotCompilable(r) => return NotCompilable(r)
        Compilable => ()
      }
      match
        can_compile_expr_with_local_functions(then_e, local_function_values) {
        NotCompilable(r) => return NotCompilable(r)
        Compilable => ()
      }
      can_compile_expr_with_local_functions(else_e, local_function_values)
    }
    @ast.TsExpr::ArrayLit(elements) => {
      for elem in elements {
        match elem {
          @ast.TsExpr::Spread(inner) =>
            match
              can_compile_expr_with_local_functions(
                inner, local_function_values,
              ) {
              NotCompilable(r) => return NotCompilable(r)
              Compilable => ()
            }
          _ =>
            match
              can_compile_expr_with_local_functions(elem, local_function_values) {
              NotCompilable(r) => return NotCompilable(r)
              Compilable => ()
            }
        }
      }
      Compilable
    }
    @ast.TsExpr::IndexAccess(arr, idx) => {
      match can_compile_expr_with_local_functions(arr, local_function_values) {
        NotCompilable(r) => return NotCompilable(r)
        Compilable => ()
      }
      can_compile_expr_with_local_functions(idx, local_function_values)
    }
    @ast.TsExpr::PropAccess(obj, _) =>
      can_compile_expr_with_local_functions(obj, local_function_values)
    @ast.TsExpr::AssignExpr(name, value) => {
      match local_function_values.get(name) {
        Some(_) =>
          if register_local_function_value_for_analysis(
              local_function_values, name, value,
            ) {
            return Compilable
          } else {
            return NotCompilable("function value reassignment not supported")
          }
        None => ()
      }
      can_compile_expr_with_local_functions(value, local_function_values)
    }
    @ast.TsExpr::AssignPattern(_, _) =>
      NotCompilable("destructuring assignment not supported")
    @ast.TsExpr::PropAssignExpr(obj, _, value) => {
      match can_compile_expr_with_local_functions(obj, local_function_values) {
        NotCompilable(r) => return NotCompilable(r)
        Compilable => ()
      }
      can_compile_expr_with_local_functions(value, local_function_values)
    }
    @ast.TsExpr::IndexAssignExpr(arr, idx, value) => {
      match can_compile_expr_with_local_functions(arr, local_function_values) {
        NotCompilable(r) => return NotCompilable(r)
        Compilable => ()
      }
      match can_compile_expr_with_local_functions(idx, local_function_values) {
        NotCompilable(r) => return NotCompilable(r)
        Compilable => ()
      }
      can_compile_expr_with_local_functions(value, local_function_values)
    }
    @ast.TsExpr::CompoundAssignExpr(left, _, right) => {
      match can_compile_expr_with_local_functions(left, local_function_values) {
        NotCompilable(r) => return NotCompilable(r)
        Compilable => ()
      }
      can_compile_expr_with_local_functions(right, local_function_values)
    }
    @ast.TsExpr::Call(name, args) =>
      can_compile_local_function_call_or_named_call(
        name, args, local_function_values,
      )
    @ast.TsExpr::CallExpr(callee, args) =>
      can_compile_callable_expr_with_local_functions(
        callee, args, local_function_values, true,
      )
    @ast.TsExpr::MethodCall(receiver, method_name, args) => {
      match
        can_compile_expr_with_local_functions(receiver, local_function_values) {
        NotCompilable(r) => return NotCompilable(r)
        Compilable => ()
      }
      match
        can_compile_call_args_with_local_functions(args, local_function_values) {
        NotCompilable(r) => return NotCompilable(r)
        Compilable => ()
      }
      if is_compilable_method(method_name) {
        Compilable
      } else {
        NotCompilable("method '\{method_name}' not supported")
      }
    }
    @ast.TsExpr::New(_, args) => {
      match
        can_compile_call_args_with_local_functions(args, local_function_values) {
        NotCompilable(r) => return NotCompilable(r)
        Compilable => ()
      }
      Compilable
    }
    @ast.TsExpr::TemplateLiteral(_, exprs) => {
      for item in exprs {
        match
          can_compile_expr_with_local_functions(item, local_function_values) {
          NotCompilable(r) => return NotCompilable(r)
          Compilable => continue
        }
      }
      Compilable
    }
    @ast.TsExpr::Seq(left, right) => {
      match can_compile_expr_with_local_functions(left, local_function_values) {
        NotCompilable(r) => return NotCompilable(r)
        Compilable => ()
      }
      can_compile_expr_with_local_functions(right, local_function_values)
    }
    @ast.TsExpr::ComputedProp(key, value) =>
      match eval_const(key) {
        ConstValue::NotConst =>
          NotCompilable("computed property key must be constant")
        _ => can_compile_expr_with_local_functions(value, local_function_values)
      }
    @ast.TsExpr::ObjectLit(fields) => {
      for item in fields {
        let (key, value) = item
        if key.has_prefix("@@spread:") {
          return NotCompilable("object spread not supported")
        }
        if key.has_prefix("@@get:") || key.has_prefix("@@set:") {
          return NotCompilable("object accessors not supported")
        }
        match
          can_compile_expr_with_local_functions(value, local_function_values) {
          NotCompilable(r) => return NotCompilable(r)
          Compilable => ()
        }
      }
      Compilable
    }
    @ast.TsExpr::ArrowFunc(_, _, _) =>
      NotCompilable("arrow functions not supported (closures)")
    @ast.TsExpr::FuncExpr(_) =>
      NotCompilable("function expressions not supported (closures)")
    _ => can_compile_expr(expr)
  }
}

///|
fn can_compile_call_args_with_local_functions(
  args : Array[@ast.TsExpr],
  local_function_values : Map[String, @ast.TsExpr],
) -> CompilabilityResult {
  for arg in args {
    match arg {
      @ast.TsExpr::Spread(_) =>
        return NotCompilable(
          "spread argument not supported for function value calls",
        )
      _ =>
        match
          can_compile_expr_with_local_functions(arg, local_function_values) {
          NotCompilable(r) => return NotCompilable(r)
          Compilable => continue
        }
    }
  }
  Compilable
}

///|
fn can_compile_local_function_call_or_named_call(
  name : String,
  args : Array[@ast.TsExpr],
  local_function_values : Map[String, @ast.TsExpr],
) -> CompilabilityResult {
  match local_function_values.get(name) {
    Some(@ast.TsExpr::ArrowFunc(params, body, is_async)) =>
      can_compile_arrow_iife_with_local_functions(
        params, body, is_async, args, local_function_values,
      )
    Some(@ast.TsExpr::FuncExpr(func)) =>
      can_compile_func_expr_iife_with_local_functions(
        func, args, local_function_values,
      )
    Some(
      @ast.TsExpr::Cond(
        cond,
        @ast.TsExpr::Var(then_name),
        @ast.TsExpr::Var(else_name)
      )
    ) => {
      match can_compile_expr_with_local_functions(cond, local_function_values) {
        NotCompilable(r) => return NotCompilable(r)
        Compilable => ()
      }
      match
        can_compile_local_function_call_or_named_call(
          then_name, args, local_function_values,
        ) {
        NotCompilable(r) => return NotCompilable(r)
        Compilable => ()
      }
      can_compile_local_function_call_or_named_call(
        else_name, args, local_function_values,
      )
    }
    Some(_) => NotCompilable("function value call not supported")
    None => {
      match
        can_compile_call_args_with_local_functions(args, local_function_values) {
        NotCompilable(r) => return NotCompilable(r)
        Compilable => ()
      }
      can_compile_expr(@ast.TsExpr::Call(name, args))
    }
  }
}

///|
fn can_compile_function_value_assignment_call(
  name : String,
  value : @ast.TsExpr,
  args : Array[@ast.TsExpr],
  local_function_values : Map[String, @ast.TsExpr],
) -> CompilabilityResult {
  match local_function_values.get(name) {
    Some(_) =>
      if register_local_function_value_for_analysis(
          local_function_values, name, value,
        ) {
        can_compile_local_function_call_or_named_call(
          name, args, local_function_values,
        )
      } else {
        NotCompilable("function value assignment call not supported")
      }
    None => NotCompilable("function value assignment call not supported")
  }
}

///|
fn can_compile_callable_expr_with_local_functions(
  callee : @ast.TsExpr,
  args : Array[@ast.TsExpr],
  local_function_values : Map[String, @ast.TsExpr],
  allow_assignment : Bool,
) -> CompilabilityResult {
  match callee {
    @ast.TsExpr::Var(name) =>
      can_compile_local_function_call_or_named_call(
        name, args, local_function_values,
      )
    @ast.TsExpr::ArrowFunc(params, body, is_async) =>
      can_compile_arrow_iife_with_local_functions(
        params, body, is_async, args, local_function_values,
      )
    @ast.TsExpr::FuncExpr(func) =>
      can_compile_func_expr_iife_with_local_functions(
        func, args, local_function_values,
      )
    @ast.TsExpr::CallExpr(producer, producer_args) =>
      can_compile_returned_function_value_call_with_local_functions(
        producer, producer_args, args, local_function_values,
      )
    @ast.TsExpr::Cond(cond, then_callee, else_callee) => {
      match can_compile_expr_with_local_functions(cond, local_function_values) {
        NotCompilable(r) => return NotCompilable(r)
        Compilable => ()
      }
      let then_values = local_function_values.copy()
      match
        can_compile_callable_expr_with_local_functions(
          then_callee, args, then_values, false,
        ) {
        NotCompilable(r) => return NotCompilable(r)
        Compilable => ()
      }
      let else_values = local_function_values.copy()
      can_compile_callable_expr_with_local_functions(
        else_callee, args, else_values, false,
      )
    }
    @ast.TsExpr::AssignExpr(name, value) =>
      if allow_assignment {
        can_compile_function_value_assignment_call(
          name, value, args, local_function_values,
        )
      } else {
        NotCompilable(
          "function value assignment in conditional callee not supported",
        )
      }
    _ => NotCompilable("arbitrary call expression not supported")
  }
}

///|
fn iife_return_expr_for_analysis(block : @ast.TsBlock) -> @ast.TsExpr? {
  if block.stmts.length() != 1 {
    return None
  }
  match block.stmts[0] {
    @ast.TsStmt::Return(Some(expr)) => Some(expr)
    _ => None
  }
}

///|
fn can_compile_returned_function_value_call_with_local_functions(
  producer : @ast.TsExpr,
  producer_args : Array[@ast.TsExpr],
  args : Array[@ast.TsExpr],
  local_function_values : Map[String, @ast.TsExpr],
) -> CompilabilityResult {
  match producer {
    @ast.TsExpr::ArrowFunc(params, body, is_async) => {
      if is_async {
        return NotCompilable("async returned function value not supported")
      }
      if params.length() != producer_args.length() {
        return NotCompilable("returned function value iife arity mismatch")
      }
      for param in params {
        if param.is_rest {
          return NotCompilable(
            "rest parameter returned function value iife not supported",
          )
        }
        match param.default {
          Some(_) =>
            return NotCompilable(
              "default parameter returned function value iife not supported",
            )
          None => ()
        }
      }
      let (arg_result, body_function_values) = prepare_iife_local_function_values_for_analysis(
        params, producer_args, local_function_values,
      )
      match arg_result {
        NotCompilable(r) => return NotCompilable(r)
        Compilable => ()
      }
      let returned_expr = match body {
        @ast.TsArrowBody::ArrowExpr(expr) => expr
        @ast.TsArrowBody::ArrowBlock(block) =>
          match iife_return_expr_for_analysis(block) {
            Some(expr) => expr
            None =>
              return NotCompilable(
                "returned function value iife must contain exactly one return statement",
              )
          }
      }
      match
        resolve_local_function_value_for_analysis(
          body_function_values, returned_expr,
        ) {
        Some(function_value) =>
          can_compile_callable_expr_with_local_functions(
            function_value, args, body_function_values, false,
          )
        None => NotCompilable("returned function value call not supported")
      }
    }
    @ast.TsExpr::FuncExpr(func) => {
      if func.is_async {
        return NotCompilable("async returned function value not supported")
      }
      if func.is_generator {
        return NotCompilable("generator returned function value not supported")
      }
      if func.params.length() != producer_args.length() {
        return NotCompilable("returned function value iife arity mismatch")
      }
      for param in func.params {
        if param.is_rest {
          return NotCompilable(
            "rest parameter returned function value iife not supported",
          )
        }
        match param.default {
          Some(_) =>
            return NotCompilable(
              "default parameter returned function value iife not supported",
            )
          None => ()
        }
      }
      let (arg_result, body_function_values) = prepare_iife_local_function_values_for_analysis(
        func.params,
        producer_args,
        local_function_values,
      )
      match arg_result {
        NotCompilable(r) => return NotCompilable(r)
        Compilable => ()
      }
      let returned_expr = match iife_return_expr_for_analysis(func.body) {
        Some(expr) => expr
        None =>
          return NotCompilable(
            "returned function value iife must contain exactly one return statement",
          )
      }
      match
        resolve_local_function_value_for_analysis(
          body_function_values, returned_expr,
        ) {
        Some(function_value) =>
          can_compile_callable_expr_with_local_functions(
            function_value, args, body_function_values, false,
          )
        None => NotCompilable("returned function value call not supported")
      }
    }
    _ => NotCompilable("arbitrary call expression not supported")
  }
}

///|
fn prepare_iife_local_function_values_for_analysis(
  params : Array[@ast.TsParam],
  args : Array[@ast.TsExpr],
  local_function_values : Map[String, @ast.TsExpr],
) -> (CompilabilityResult, Map[String, @ast.TsExpr]) {
  let body_function_values = local_function_values.copy()
  for i, param in params {
    match
      resolve_local_function_value_for_analysis(local_function_values, args[i]) {
      Some(function_value) => body_function_values[param.name] = function_value
      None =>
        match
          can_compile_expr_with_local_functions(args[i], local_function_values) {
          NotCompilable(r) => return (NotCompilable(r), body_function_values)
          Compilable => ()
        }
    }
  }
  (Compilable, body_function_values)
}

///|
fn can_compile_arrow_iife_with_local_functions(
  params : Array[@ast.TsParam],
  body : @ast.TsArrowBody,
  is_async : Bool,
  args : Array[@ast.TsExpr],
  local_function_values : Map[String, @ast.TsExpr],
) -> CompilabilityResult {
  if is_async {
    return NotCompilable("async arrow iife not supported")
  }
  if params.length() != args.length() {
    return NotCompilable("arrow iife arity mismatch")
  }
  for param in params {
    if param.is_rest {
      return NotCompilable("rest parameter arrow iife not supported")
    }
    match param.default {
      Some(_) =>
        return NotCompilable("default parameter arrow iife not supported")
      None => ()
    }
  }
  let (arg_result, body_function_values) = prepare_iife_local_function_values_for_analysis(
    params, args, local_function_values,
  )
  match arg_result {
    NotCompilable(r) => return NotCompilable(r)
    Compilable => ()
  }
  match body {
    @ast.TsArrowBody::ArrowExpr(expr) =>
      can_compile_expr_with_local_functions(expr, body_function_values)
    @ast.TsArrowBody::ArrowBlock(block) =>
      can_compile_iife_return_block_with_local_functions(
        block, body_function_values,
      )
  }
}

///|
fn can_compile_func_expr_iife_with_local_functions(
  func : @ast.TsFunc,
  args : Array[@ast.TsExpr],
  local_function_values : Map[String, @ast.TsExpr],
) -> CompilabilityResult {
  if func.is_async {
    return NotCompilable("async function expression iife not supported")
  }
  if func.is_generator {
    return NotCompilable("generator function expression iife not supported")
  }
  if func.params.length() != args.length() {
    return NotCompilable("function expression iife arity mismatch")
  }
  for param in func.params {
    if param.is_rest {
      return NotCompilable(
        "rest parameter function expression iife not supported",
      )
    }
    match param.default {
      Some(_) =>
        return NotCompilable(
          "default parameter function expression iife not supported",
        )
      None => ()
    }
  }
  let (arg_result, body_function_values) = prepare_iife_local_function_values_for_analysis(
    func.params,
    args,
    local_function_values,
  )
  match arg_result {
    NotCompilable(r) => return NotCompilable(r)
    Compilable => ()
  }
  can_compile_iife_return_block_with_local_functions(
    func.body,
    body_function_values,
  )
}

///|
fn can_compile_iife_return_block_with_local_functions(
  block : @ast.TsBlock,
  local_function_values : Map[String, @ast.TsExpr],
) -> CompilabilityResult {
  if block.stmts.length() != 1 {
    return NotCompilable("iife block must contain exactly one return statement")
  }
  match block.stmts[0] {
    @ast.TsStmt::Return(Some(expr)) =>
      can_compile_expr_with_local_functions(expr, local_function_values)
    @ast.TsStmt::Return(None) => Compilable
    _ => NotCompilable("iife block must contain exactly one return statement")
  }
}

///|
fn can_compile_arrow_iife(
  params : Array[@ast.TsParam],
  body : @ast.TsArrowBody,
  is_async : Bool,
  args : Array[@ast.TsExpr],
) -> CompilabilityResult {
  if is_async {
    return NotCompilable("async arrow iife not supported")
  }
  if params.length() != args.length() {
    return NotCompilable("arrow iife arity mismatch")
  }
  for param in params {
    if param.is_rest {
      return NotCompilable("rest parameter arrow iife not supported")
    }
    match param.default {
      Some(_) =>
        return NotCompilable("default parameter arrow iife not supported")
      None => ()
    }
  }
  for arg in args {
    match can_compile_expr(arg) {
      NotCompilable(r) => return NotCompilable(r)
      Compilable => ()
    }
  }
  match body {
    @ast.TsArrowBody::ArrowExpr(expr) => can_compile_expr(expr)
    @ast.TsArrowBody::ArrowBlock(block) => can_compile_iife_return_block(block)
  }
}

///|
fn can_compile_func_expr_iife(
  func : @ast.TsFunc,
  args : Array[@ast.TsExpr],
) -> CompilabilityResult {
  if func.is_async {
    return NotCompilable("async function expression iife not supported")
  }
  if func.is_generator {
    return NotCompilable("generator function expression iife not supported")
  }
  if func.params.length() != args.length() {
    return NotCompilable("function expression iife arity mismatch")
  }
  for param in func.params {
    if param.is_rest {
      return NotCompilable(
        "rest parameter function expression iife not supported",
      )
    }
    match param.default {
      Some(_) =>
        return NotCompilable(
          "default parameter function expression iife not supported",
        )
      None => ()
    }
  }
  for arg in args {
    match can_compile_expr(arg) {
      NotCompilable(r) => return NotCompilable(r)
      Compilable => ()
    }
  }
  can_compile_iife_return_block(func.body)
}

///|
fn can_compile_iife_return_block(block : @ast.TsBlock) -> CompilabilityResult {
  if block.stmts.length() != 1 {
    return NotCompilable("iife block must contain exactly one return statement")
  }
  match block.stmts[0] {
    @ast.TsStmt::Return(Some(expr)) => can_compile_expr(expr)
    @ast.TsStmt::Return(None) => Compilable
    _ => NotCompilable("iife block must contain exactly one return statement")
  }
}

///|
/// Check if a function call is known to be compilable.
fn is_compilable_call(name : String) -> Bool {
  match name {
    // Math functions (compile to wasm instructions)
    "Math.abs"
    | "Math.sqrt"
    | "Math.floor"
    | "Math.ceil"
    | "Math.round"
    | "Math.trunc"
    | "Math.min"
    | "Math.max"
    | "Math.pow"
    | "Math.sign"
    | "Math.fround" => true
    // Type conversions
    "Number" | "Boolean" => true
    _ => true // Allow user-defined functions
  }
}

///|
/// Check if a method is known to be compilable.
fn is_compilable_method(method_name : String) -> Bool {
  match method_name {
    // Array methods that are compiled
    "push" | "pop" | "length" => true
    // Math methods
    "abs"
    | "sqrt"
    | "floor"
    | "ceil"
    | "round"
    | "trunc"
    | "min"
    | "max"
    | "pow"
    | "sign"
    | "fround" => true
    _ => false
  }
}

///|
/// Analyze a module and return list of compilable functions.
pub fn find_compilable_functions(
  mod : @ast.TsModule,
) -> Array[(String, @ast.TsFunc)] {
  let result : Array[(String, @ast.TsFunc)] = []
  for func in mod.funcs {
    match can_compile_to_wasm(func) {
      Compilable => result.push((func.name, func))
      NotCompilable(_) => ()
    }
  }
  result
}
