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
  // Check all statements in body
  for stmt in func.body.stmts {
    match can_compile_stmt(stmt) {
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
        match can_compile_expr(elem) {
          NotCompilable(r) => return NotCompilable(r)
          Compilable => continue
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
        for arg in args {
          match can_compile_expr(arg) {
            NotCompilable(r) => return NotCompilable(r)
            Compilable => continue
          }
        }
        Compilable
      } else {
        // User-defined functions need to be checked separately
        // For now, allow named calls (will fail at codegen if not found)
        for arg in args {
          match can_compile_expr(arg) {
            NotCompilable(r) => return NotCompilable(r)
            Compilable => continue
          }
        }
        Compilable
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
    // Not supported: template literals
    @ast.TsExpr::TemplateLiteral(_, _) =>
      NotCompilable("template literals not supported")
    @ast.TsExpr::TaggedTemplate(_, _, _, _) =>
      NotCompilable("tagged templates not supported")
    // Not supported: comma operator
    @ast.TsExpr::Seq(_, _) => NotCompilable("comma operator not supported")
    // Not supported: spread, computed property
    @ast.TsExpr::Spread(_) => NotCompilable("spread operator not supported")
    @ast.TsExpr::ComputedProp(_, _) =>
      NotCompilable("computed property not supported")
    // Not supported: object literal (complex)
    @ast.TsExpr::ObjectLit(_) => NotCompilable("object literals not supported")
    // Function expressions: could be supported but complex due to closures
    @ast.TsExpr::ArrowFunc(_, _, _) =>
      NotCompilable("arrow functions not supported (closures)")
    @ast.TsExpr::FuncExpr(_) =>
      NotCompilable("function expressions not supported (closures)")
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
