// Binding analysis - scope and variable binding checks.

///|
/// Collect all binding names from a pattern.
pub fn collect_binding_names(
  binding : @ast.TsBinding,
  names : Array[String],
) -> Unit {
  match binding {
    @ast.TsBinding::Ident(name) => names.push(name)
    @ast.TsBinding::Array(arr) => {
      for item in arr.items {
        match item {
          Some(elem) => collect_binding_names(elem.binding, names)
          None => ()
        }
      }
      match arr.rest {
        Some(rest_binding) => collect_binding_names(rest_binding, names)
        None => ()
      }
    }
    @ast.TsBinding::Object(obj) => {
      for prop in obj.props {
        collect_binding_names(prop.binding, names)
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
/// Collect parameter names from function parameters.
pub fn collect_param_names(params : Array[@ast.TsParam]) -> Array[String] {
  let names : Array[String] = []
  for param in params {
    match param.binding {
      Some(binding) => collect_binding_names(binding, names)
      None => names.push(param.name)
    }
  }
  names
}

///|
/// Check for duplicate parameters (error in strict mode).
pub fn check_duplicate_params(
  ctx : AnalysisCtx,
  params : Array[@ast.TsParam],
  offset : Int,
) -> Unit {
  let seen : Map[String, Bool] = {}
  let names = collect_param_names(params)
  for name in names {
    if seen.contains(name) {
      ctx.add_error(SyntaxError, "Duplicate parameter name not allowed", offset)
    }
    seen[name] = true
  }
}

///|
/// Hoist var and function declarations to function scope.
pub fn hoist_declarations(ctx : AnalysisCtx, block : @ast.TsBlock) -> Unit {
  for stmt in block.stmts {
    hoist_stmt(ctx, stmt)
  }
}

///|
fn hoist_stmt(ctx : AnalysisCtx, stmt : @ast.TsStmt) -> Unit {
  match stmt {
    @ast.TsStmt::Var(binding, type_, _) => {
      // var is hoisted to function scope
      let names : Array[String] = []
      collect_binding_names(binding, names)
      for name in names {
        // var declarations are hoisted as undefined
        ctx.define_binding(name, Var, type_, true, 0)
      }
    }
    @ast.TsStmt::Block(inner_block) =>
      // Hoist through blocks
      hoist_declarations(ctx, inner_block)
    @ast.TsStmt::If(_, then_block, else_block) => {
      hoist_declarations(ctx, then_block)
      match else_block {
        Some(eb) => hoist_declarations(ctx, eb)
        None => ()
      }
    }
    @ast.TsStmt::While(_, body) => hoist_declarations(ctx, body)
    @ast.TsStmt::DoWhile(_, body) => hoist_declarations(ctx, body)
    @ast.TsStmt::For(init, _, _, body) => {
      match init {
        Some(init_stmt) => hoist_stmt(ctx, init_stmt)
        None => ()
      }
      hoist_declarations(ctx, body)
    }
    @ast.TsStmt::ForOf(kind, binding, type_, _, body) => {
      if kind == @ast.TsForOfKind::Var {
        let names : Array[String] = []
        collect_binding_names(binding, names)
        for name in names {
          ctx.define_binding(name, Var, type_, true, 0)
        }
      }
      hoist_declarations(ctx, body)
    }
    @ast.TsStmt::ForAwaitOf(kind, binding, type_, _, body) => {
      if kind == @ast.TsForOfKind::Var {
        let names : Array[String] = []
        collect_binding_names(binding, names)
        for name in names {
          ctx.define_binding(name, Var, type_, true, 0)
        }
      }
      hoist_declarations(ctx, body)
    }
    @ast.TsStmt::ForIn(kind, binding, type_, _, body) => {
      if kind == @ast.TsForOfKind::Var {
        let names : Array[String] = []
        collect_binding_names(binding, names)
        for name in names {
          ctx.define_binding(name, Var, type_, true, 0)
        }
      }
      hoist_declarations(ctx, body)
    }
    @ast.TsStmt::Try(try_block, _, catch_block, finally_block) => {
      hoist_declarations(ctx, try_block)
      match catch_block {
        Some(cb) => hoist_declarations(ctx, cb)
        None => ()
      }
      match finally_block {
        Some(fb) => hoist_declarations(ctx, fb)
        None => ()
      }
    }
    @ast.TsStmt::Switch(_, cases) =>
      for case_ in cases {
        hoist_declarations(ctx, case_.body)
      }
    @ast.TsStmt::With(_, body) => hoist_declarations(ctx, body)
    @ast.TsStmt::Label(_, inner_stmt) => hoist_stmt(ctx, inner_stmt)
    _ => ()
  }
}

///|
/// Register let/const declarations at block scope.
pub fn register_lexical_declarations(
  ctx : AnalysisCtx,
  block : @ast.TsBlock,
) -> Unit {
  for stmt in block.stmts {
    match stmt {
      @ast.TsStmt::Let(binding, type_, _) => {
        let names : Array[String] = []
        collect_binding_names(binding, names)
        for name in names {
          // let is in TDZ until initialized
          ctx.define_binding(name, Let, type_, false, 0)
        }
      }
      @ast.TsStmt::Const(binding, type_, _) => {
        let names : Array[String] = []
        collect_binding_names(binding, names)
        for name in names {
          // const is in TDZ until initialized
          ctx.define_binding(name, Const, type_, false, 0)
        }
      }
      _ => ()
    }
  }
}

///|
/// Analyze bindings in a block.
pub fn analyze_block_bindings(ctx : AnalysisCtx, block : @ast.TsBlock) -> Unit {
  // First, register lexical declarations for TDZ
  register_lexical_declarations(ctx, block)

  // Then analyze each statement
  for stmt in block.stmts {
    analyze_stmt_bindings(ctx, stmt)
  }
}

///|
fn analyze_stmt_bindings(ctx : AnalysisCtx, stmt : @ast.TsStmt) -> Unit {
  match stmt {
    @ast.TsStmt::Var(binding, _, init) => {
      // Analyze initializer expression
      analyze_expr_bindings(ctx, init)
      // var is already hoisted, just mark as initialized
      let names : Array[String] = []
      collect_binding_names(binding, names)
      for name in names {
        ctx.current_scope.initialize(name)
      }
    }
    @ast.TsStmt::Let(binding, _, init) => {
      // Analyze initializer first (before marking as initialized)
      analyze_expr_bindings(ctx, init)
      // Mark as initialized
      let names : Array[String] = []
      collect_binding_names(binding, names)
      for name in names {
        ctx.current_scope.initialize(name)
      }
    }
    @ast.TsStmt::Const(binding, _, init) => {
      // Analyze initializer first
      analyze_expr_bindings(ctx, init)
      // Mark as initialized
      let names : Array[String] = []
      collect_binding_names(binding, names)
      for name in names {
        ctx.current_scope.initialize(name)
      }
    }
    @ast.TsStmt::Assign(name, expr) => {
      analyze_expr_bindings(ctx, expr)
      // Check if assigning to const
      if ctx.current_scope.is_const(name) {
        ctx.add_error(TypeError, "Assignment to constant variable '\{name}'", 0)
      }
    }
    @ast.TsStmt::CompoundAssign(name, _, expr) => {
      analyze_expr_bindings(ctx, expr)
      if ctx.current_scope.is_const(name) {
        ctx.add_error(TypeError, "Assignment to constant variable '\{name}'", 0)
      }
    }
    @ast.TsStmt::IndexAssign(arr, idx, val) => {
      analyze_expr_bindings(ctx, arr)
      analyze_expr_bindings(ctx, idx)
      analyze_expr_bindings(ctx, val)
    }
    @ast.TsStmt::PropAssign(obj, _, val) => {
      analyze_expr_bindings(ctx, obj)
      analyze_expr_bindings(ctx, val)
    }
    @ast.TsStmt::Expr(expr) => analyze_expr_bindings(ctx, expr)
    @ast.TsStmt::Return(expr) =>
      match expr {
        Some(e) => analyze_expr_bindings(ctx, e)
        None => ()
      }
    @ast.TsStmt::Throw(expr) => analyze_expr_bindings(ctx, expr)
    @ast.TsStmt::If(cond, then_block, else_block) => {
      analyze_expr_bindings(ctx, cond)
      ctx.push_scope(Block)
      analyze_block_bindings(ctx, then_block)
      ctx.pop_scope()
      match else_block {
        Some(eb) => {
          ctx.push_scope(Block)
          analyze_block_bindings(ctx, eb)
          ctx.pop_scope()
        }
        None => ()
      }
    }
    @ast.TsStmt::While(cond, body) => {
      analyze_expr_bindings(ctx, cond)
      let old_in_loop = ctx.in_loop
      ctx.in_loop = true
      ctx.push_scope(Block)
      analyze_block_bindings(ctx, body)
      ctx.pop_scope()
      ctx.in_loop = old_in_loop
    }
    @ast.TsStmt::DoWhile(cond, body) => {
      let old_in_loop = ctx.in_loop
      ctx.in_loop = true
      ctx.push_scope(Block)
      analyze_block_bindings(ctx, body)
      ctx.pop_scope()
      analyze_expr_bindings(ctx, cond)
      ctx.in_loop = old_in_loop
    }
    @ast.TsStmt::For(init, cond, update, body) => {
      ctx.push_scope(ForLoop)
      match init {
        Some(init_stmt) => analyze_stmt_bindings(ctx, init_stmt)
        None => ()
      }
      match cond {
        Some(c) => analyze_expr_bindings(ctx, c)
        None => ()
      }
      match update {
        Some(u) => analyze_stmt_bindings(ctx, u)
        None => ()
      }
      let old_in_loop = ctx.in_loop
      ctx.in_loop = true
      ctx.push_scope(Block)
      analyze_block_bindings(ctx, body)
      ctx.pop_scope()
      ctx.in_loop = old_in_loop
      ctx.pop_scope()
    }
    @ast.TsStmt::ForOf(kind, binding, type_, iterable, body) => {
      analyze_expr_bindings(ctx, iterable)
      ctx.push_scope(ForLoop)
      let names : Array[String] = []
      collect_binding_names(binding, names)
      let decl_kind = match kind {
        @ast.TsForOfKind::Let => Let
        @ast.TsForOfKind::Const => Const
        @ast.TsForOfKind::Var => Var
        @ast.TsForOfKind::Assign => Var
      }
      for name in names {
        ctx.define_binding(name, decl_kind, type_, true, 0)
      }
      let old_in_loop = ctx.in_loop
      ctx.in_loop = true
      ctx.push_scope(Block)
      analyze_block_bindings(ctx, body)
      ctx.pop_scope()
      ctx.in_loop = old_in_loop
      ctx.pop_scope()
    }
    @ast.TsStmt::ForAwaitOf(kind, binding, type_, iterable, body) => {
      analyze_expr_bindings(ctx, iterable)
      ctx.push_scope(ForLoop)
      let names : Array[String] = []
      collect_binding_names(binding, names)
      let decl_kind = match kind {
        @ast.TsForOfKind::Let => Let
        @ast.TsForOfKind::Const => Const
        @ast.TsForOfKind::Var => Var
        @ast.TsForOfKind::Assign => Var
      }
      for name in names {
        ctx.define_binding(name, decl_kind, type_, true, 0)
      }
      let old_in_loop = ctx.in_loop
      ctx.in_loop = true
      ctx.push_scope(Block)
      analyze_block_bindings(ctx, body)
      ctx.pop_scope()
      ctx.in_loop = old_in_loop
      ctx.pop_scope()
    }
    @ast.TsStmt::ForIn(kind, binding, type_, obj, body) => {
      analyze_expr_bindings(ctx, obj)
      ctx.push_scope(ForLoop)
      let names : Array[String] = []
      collect_binding_names(binding, names)
      let decl_kind = match kind {
        @ast.TsForOfKind::Let => Let
        @ast.TsForOfKind::Const => Const
        @ast.TsForOfKind::Var => Var
        @ast.TsForOfKind::Assign => Var
      }
      for name in names {
        ctx.define_binding(name, decl_kind, type_, true, 0)
      }
      let old_in_loop = ctx.in_loop
      ctx.in_loop = true
      ctx.push_scope(Block)
      analyze_block_bindings(ctx, body)
      ctx.pop_scope()
      ctx.in_loop = old_in_loop
      ctx.pop_scope()
    }
    @ast.TsStmt::Switch(expr, cases) => {
      analyze_expr_bindings(ctx, expr)
      ctx.in_switch = true
      ctx.push_scope(Block)
      for case_ in cases {
        match case_.test_expr {
          Some(test_expr) => analyze_expr_bindings(ctx, test_expr)
          None => ()
        }
        analyze_block_bindings(ctx, case_.body)
      }
      ctx.pop_scope()
      ctx.in_switch = false
    }
    @ast.TsStmt::Try(try_block, catch_binding, catch_block, finally_block) => {
      ctx.push_scope(Block)
      analyze_block_bindings(ctx, try_block)
      ctx.pop_scope()
      match (catch_binding, catch_block) {
        (Some(binding), Some(cb)) => {
          ctx.push_scope(Catch)
          let names : Array[String] = []
          collect_binding_names(binding, names)
          for name in names {
            ctx.define_binding(name, CatchParam, @ast.TsType::Any, true, 0)
          }
          analyze_block_bindings(ctx, cb)
          ctx.pop_scope()
        }
        (None, Some(cb)) => {
          ctx.push_scope(Catch)
          analyze_block_bindings(ctx, cb)
          ctx.pop_scope()
        }
        _ => ()
      }
      match finally_block {
        Some(fb) => {
          ctx.push_scope(Block)
          analyze_block_bindings(ctx, fb)
          ctx.pop_scope()
        }
        None => ()
      }
    }
    @ast.TsStmt::With(expr, body) => {
      if ctx.is_strict {
        ctx.add_error(
          SyntaxError,
          "'with' statements are not allowed in strict mode",
          0,
        )
      }
      analyze_expr_bindings(ctx, expr)
      ctx.push_scope(With)
      analyze_block_bindings(ctx, body)
      ctx.pop_scope()
    }
    @ast.TsStmt::Block(inner_block) => {
      ctx.push_scope(Block)
      analyze_block_bindings(ctx, inner_block)
      ctx.pop_scope()
    }
    @ast.TsStmt::Label(_, inner_stmt) => analyze_stmt_bindings(ctx, inner_stmt)
    @ast.TsStmt::Break(label) =>
      if not(ctx.in_loop) && not(ctx.in_switch) && label is None {
        ctx.add_error(SyntaxError, "Illegal break statement", 0)
      }
    @ast.TsStmt::Continue(label) =>
      if not(ctx.in_loop) && label is None {
        ctx.add_error(SyntaxError, "Illegal continue statement", 0)
      }
    @ast.TsStmt::Empty | @ast.TsStmt::Debugger => ()
  }
}

///|
fn analyze_expr_bindings(ctx : AnalysisCtx, expr : @ast.TsExpr) -> Unit {
  match expr {
    @ast.TsExpr::Var(name) => {
      // Check if variable is accessible
      let _ = ctx.lookup_binding(name, 0)
    }
    @ast.TsExpr::BinOp(_, left, right) => {
      analyze_expr_bindings(ctx, left)
      analyze_expr_bindings(ctx, right)
    }
    @ast.TsExpr::UnaryOp(_, operand) => analyze_expr_bindings(ctx, operand)
    @ast.TsExpr::Call(_, args) =>
      for arg in args {
        analyze_expr_bindings(ctx, arg)
      }
    @ast.TsExpr::CallExpr(callee, args) => {
      analyze_expr_bindings(ctx, callee)
      for arg in args {
        analyze_expr_bindings(ctx, arg)
      }
    }
    @ast.TsExpr::Cond(cond, then_, else_) => {
      analyze_expr_bindings(ctx, cond)
      analyze_expr_bindings(ctx, then_)
      analyze_expr_bindings(ctx, else_)
    }
    @ast.TsExpr::ArrayLit(elements) =>
      for elem in elements {
        analyze_expr_bindings(ctx, elem)
      }
    @ast.TsExpr::Spread(inner) => analyze_expr_bindings(ctx, inner)
    @ast.TsExpr::ObjectLit(fields) =>
      for field in fields {
        let (_, value) = field
        analyze_expr_bindings(ctx, value)
      }
    @ast.TsExpr::ComputedProp(key, value) => {
      analyze_expr_bindings(ctx, key)
      analyze_expr_bindings(ctx, value)
    }
    @ast.TsExpr::IndexAccess(arr, idx) => {
      analyze_expr_bindings(ctx, arr)
      analyze_expr_bindings(ctx, idx)
    }
    @ast.TsExpr::PropAccess(obj, _) => analyze_expr_bindings(ctx, obj)
    @ast.TsExpr::New(_, args) =>
      for arg in args {
        analyze_expr_bindings(ctx, arg)
      }
    @ast.TsExpr::NewExpr(ctor, args) => {
      analyze_expr_bindings(ctx, ctor)
      for arg in args {
        analyze_expr_bindings(ctx, arg)
      }
    }
    @ast.TsExpr::MethodCall(receiver, _, args) => {
      analyze_expr_bindings(ctx, receiver)
      for arg in args {
        analyze_expr_bindings(ctx, arg)
      }
    }
    @ast.TsExpr::AssignExpr(name, value) => {
      analyze_expr_bindings(ctx, value)
      if ctx.current_scope.is_const(name) {
        ctx.add_error(TypeError, "Assignment to constant variable '\{name}'", 0)
      }
    }
    @ast.TsExpr::AssignPattern(_, value) => analyze_expr_bindings(ctx, value)
    @ast.TsExpr::CompoundAssignExpr(target, _, value) => {
      analyze_expr_bindings(ctx, target)
      analyze_expr_bindings(ctx, value)
    }
    @ast.TsExpr::PropAssignExpr(obj, _, value) => {
      analyze_expr_bindings(ctx, obj)
      analyze_expr_bindings(ctx, value)
    }
    @ast.TsExpr::IndexAssignExpr(obj, idx, value) => {
      analyze_expr_bindings(ctx, obj)
      analyze_expr_bindings(ctx, idx)
      analyze_expr_bindings(ctx, value)
    }
    @ast.TsExpr::Seq(left, right) => {
      analyze_expr_bindings(ctx, left)
      analyze_expr_bindings(ctx, right)
    }
    @ast.TsExpr::ArrowFunc(params, body, _) => {
      ctx.push_scope(Function)
      for param in params {
        ctx.define_binding(param.name, Param, param.type_, true, 0)
        match param.default {
          Some(def) => analyze_expr_bindings(ctx, def)
          None => ()
        }
      }
      match body {
        @ast.TsArrowBody::ArrowExpr(expr) => analyze_expr_bindings(ctx, expr)
        @ast.TsArrowBody::ArrowBlock(block) => {
          hoist_declarations(ctx, block)
          analyze_block_bindings(ctx, block)
        }
      }
      ctx.pop_scope()
    }
    @ast.TsExpr::FuncExpr(func) => analyze_function_bindings(ctx, func)
    @ast.TsExpr::Yield(inner) =>
      match inner {
        Some(e) => analyze_expr_bindings(ctx, e)
        None => ()
      }
    @ast.TsExpr::YieldStar(inner) => analyze_expr_bindings(ctx, inner)
    @ast.TsExpr::Await(inner) => analyze_expr_bindings(ctx, inner)
    @ast.TsExpr::DynamicImport(spec) => analyze_expr_bindings(ctx, spec)
    @ast.TsExpr::TemplateLiteral(_, exprs) =>
      for expr in exprs {
        analyze_expr_bindings(ctx, expr)
      }
    @ast.TsExpr::TaggedTemplate(tag, _, _, exprs) => {
      analyze_expr_bindings(ctx, tag)
      for expr in exprs {
        analyze_expr_bindings(ctx, expr)
      }
    }
    // Literals don't need binding analysis
    @ast.TsExpr::NumberLit(_)
    | @ast.TsExpr::IntLit(_)
    | @ast.TsExpr::BigIntLit(_)
    | @ast.TsExpr::BoolLit(_)
    | @ast.TsExpr::StringLit(_)
    | @ast.TsExpr::NullLit
    | @ast.TsExpr::ArrayHole
    | @ast.TsExpr::ImportMeta => ()
  }
}

///|
/// Analyze bindings in a function.
pub fn analyze_function_bindings(ctx : AnalysisCtx, func : @ast.TsFunc) -> Unit {
  ctx.push_scope(Function)

  // Check for duplicate parameters in strict mode
  if ctx.is_strict {
    check_duplicate_params(ctx, func.params, 0)
  }

  // Define parameters
  for param in func.params {
    match param.binding {
      Some(binding) => {
        let names : Array[String] = []
        collect_binding_names(binding, names)
        for name in names {
          ctx.define_binding(name, Param, param.type_, true, 0)
        }
      }
      None => ctx.define_binding(param.name, Param, param.type_, true, 0)
    }
    match param.default {
      Some(def) => analyze_expr_bindings(ctx, def)
      None => ()
    }
  }

  // Hoist var and function declarations
  hoist_declarations(ctx, func.body)

  // Analyze body
  analyze_block_bindings(ctx, func.body)
  ctx.pop_scope()
}

///|
/// Analyze bindings in a module.
pub fn analyze_module_bindings(
  ctx : AnalysisCtx,
  module_ : @ast.TsModule,
) -> Unit {
  // Hoist function declarations
  for func in module_.funcs {
    ctx.define_binding(func.name, Function, @ast.TsType::Any, true, 0)
  }

  // Analyze each function
  for func in module_.funcs {
    analyze_function_bindings(ctx, func)
  }
}
