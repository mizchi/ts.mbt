// Type checking pass with full type inference and error detection.

///|
/// Result of type checking.
pub(all) struct TypeCheckResult {
  typed_module : @ast.TypedModule
  errors : Array[TypeError]
  warnings : Array[String]
}

///|
/// Type check a module with full analysis.
pub fn type_check_module(
  module_ : @ast.TsModule,
  source : String,
) -> TypeCheckResult {
  let ctx = FlowTypeCtx::new(source)
  // Register built-in types
  register_builtins(ctx)
  // First pass: collect function signatures
  for func in module_.funcs {
    ctx.base_ctx.func_return_types[func.name] = func.return_type
    register_func_type(ctx, func)
  }
  // Second pass: check each function
  let typed_funcs : Array[@ast.TypedFunc] = []
  for func in module_.funcs {
    let typed_func = type_check_function(ctx, func)
    typed_funcs.push(typed_func)
  }
  // Solve constraints
  ctx.solver.solve()
  {
    typed_module: { funcs: typed_funcs },
    errors: ctx.solver.errors,
    warnings: [],
  }
}

///|
/// Register built-in types and functions.
fn register_builtins(ctx : FlowTypeCtx) -> Unit {
  // Register global functions
  ctx.base_ctx.func_return_types["parseInt"] = @ast.TsType::Int
  ctx.base_ctx.func_return_types["parseFloat"] = @ast.TsType::Number
  ctx.base_ctx.func_return_types["isNaN"] = @ast.TsType::Boolean
  ctx.base_ctx.func_return_types["isFinite"] = @ast.TsType::Boolean
  ctx.base_ctx.func_return_types["String"] = @ast.TsType::String_
  ctx.base_ctx.func_return_types["Number"] = @ast.TsType::Number
  ctx.base_ctx.func_return_types["Boolean"] = @ast.TsType::Boolean

  // Register console object
  let console_type = ObjectType::new()
  console_type.set_prop("log", @ast.TsType::Func([], @ast.TsType::Void))
  console_type.set_prop("error", @ast.TsType::Func([], @ast.TsType::Void))
  console_type.set_prop("warn", @ast.TsType::Func([], @ast.TsType::Void))
  ctx.registry.register_object("console", console_type)
  ctx.set_type("console", @ast.TsType::Any) // Simplified

  // Register Math object
  let math_type = ObjectType::new()
  math_type.set_prop(
    "floor",
    @ast.TsType::Func([@ast.TsType::Number], @ast.TsType::Int),
  )
  math_type.set_prop(
    "ceil",
    @ast.TsType::Func([@ast.TsType::Number], @ast.TsType::Int),
  )
  math_type.set_prop(
    "round",
    @ast.TsType::Func([@ast.TsType::Number], @ast.TsType::Int),
  )
  math_type.set_prop(
    "abs",
    @ast.TsType::Func([@ast.TsType::Number], @ast.TsType::Number),
  )
  math_type.set_prop(
    "sqrt",
    @ast.TsType::Func([@ast.TsType::Number], @ast.TsType::Number),
  )
  math_type.set_prop(
    "pow",
    @ast.TsType::Func(
      [@ast.TsType::Number, @ast.TsType::Number],
      @ast.TsType::Number,
    ),
  )
  math_type.set_prop(
    "min",
    @ast.TsType::Func(
      [@ast.TsType::Number, @ast.TsType::Number],
      @ast.TsType::Number,
    ),
  )
  math_type.set_prop(
    "max",
    @ast.TsType::Func(
      [@ast.TsType::Number, @ast.TsType::Number],
      @ast.TsType::Number,
    ),
  )
  math_type.set_prop("random", @ast.TsType::Func([], @ast.TsType::Number))
  math_type.set_prop("PI", @ast.TsType::Number)
  math_type.set_prop("E", @ast.TsType::Number)
  ctx.registry.register_object("Math", math_type)
  ctx.set_type("Math", @ast.TsType::Any)

  // Register Array constructor
  ctx.base_ctx.func_return_types["Array"] = @ast.TsType::Array(@ast.TsType::Any)

  // Register Object constructor
  ctx.base_ctx.func_return_types["Object"] = @ast.TsType::Any
}

///|
/// Register function type signature.
fn register_func_type(ctx : FlowTypeCtx, func : @ast.TsFunc) -> Unit {
  let param_types : Array[@ast.TsType] = []
  for param in func.params {
    param_types.push(param.type_)
  }
  let func_type = @ast.TsType::Func(param_types, func.return_type)
  ctx.set_type(func.name, func_type)
}

///|
/// Type check a function.
fn type_check_function(ctx : FlowTypeCtx, func : @ast.TsFunc) -> @ast.TypedFunc {
  ctx.enter_scope()
  ctx.base_ctx.expected_return = func.return_type
  ctx.return_types = []

  // Add parameters to context
  for param in func.params {
    ctx.set_type(param.name, param.type_)
  }

  // Collect and check locals
  let locals : Array[(String, @ast.TsType)] = []
  for stmt in func.body.stmts {
    type_check_stmt(ctx, stmt, locals)
  }

  // Check return type consistency
  if func.return_type != @ast.TsType::Void &&
    func.return_type != @ast.TsType::Any {
    let inferred_return = ctx.get_return_type()
    if inferred_return != @ast.TsType::Void &&
      not(is_assignable(inferred_return, func.return_type)) {
      ctx.add_constraint(
        Assignable(inferred_return, func.return_type, SourceLoc::unknown()),
      )
    }
  }
  ctx.leave_scope()
  { func, locals }
}

///|
/// Type check a statement.
fn type_check_stmt(
  ctx : FlowTypeCtx,
  stmt : @ast.TsStmt,
  locals : Array[(String, @ast.TsType)],
) -> Unit {
  match stmt {
    @ast.TsStmt::Var(binding, declared, init) =>
      type_check_var_decl(ctx, binding, declared, init, locals)
    @ast.TsStmt::Let(binding, declared, init) =>
      type_check_var_decl(ctx, binding, declared, init, locals)
    @ast.TsStmt::Const(binding, declared, init) =>
      type_check_var_decl(ctx, binding, declared, init, locals)
    @ast.TsStmt::Expr(e) => {
      let _ = infer_expr_flow(ctx, e)
    }
    @ast.TsStmt::Return(Some(e)) => {
      let ret_type = infer_expr_flow(ctx, e)
      ctx.record_return(ret_type)
      // Check against expected return type
      if ctx.base_ctx.expected_return != @ast.TsType::Any {
        ctx.add_constraint(
          Assignable(
            ret_type,
            ctx.base_ctx.expected_return,
            SourceLoc::unknown(),
          ),
        )
      }
    }
    @ast.TsStmt::Return(None) => ctx.record_return(@ast.TsType::Void)
    @ast.TsStmt::If(cond, then_block, else_block) =>
      type_check_if(ctx, cond, then_block, else_block, locals)
    @ast.TsStmt::While(cond, body) => {
      let _ = infer_expr_flow(ctx, cond)
      ctx.enter_scope()
      for s in body.stmts {
        type_check_stmt(ctx, s, locals)
      }
      ctx.leave_scope()
    }
    @ast.TsStmt::DoWhile(cond, body) => {
      ctx.enter_scope()
      for s in body.stmts {
        type_check_stmt(ctx, s, locals)
      }
      ctx.leave_scope()
      let _ = infer_expr_flow(ctx, cond)
    }
    @ast.TsStmt::For(init, cond, update, body) => {
      ctx.enter_scope()
      match init {
        Some(init_stmt) => type_check_stmt(ctx, init_stmt, locals)
        None => ()
      }
      match cond {
        Some(c) => {
          let _ = infer_expr_flow(ctx, c)
        }
        None => ()
      }
      match update {
        Some(u) =>
          // update is a TsStmt, not TsExpr
          type_check_stmt(ctx, u, locals)
        None => ()
      }
      for s in body.stmts {
        type_check_stmt(ctx, s, locals)
      }
      ctx.leave_scope()
    }
    @ast.TsStmt::ForOf(_, binding, declared, iter_expr, body) => {
      ctx.enter_scope()
      let iter_type = infer_expr_flow(ctx, iter_expr)
      let elem_type = match iter_type {
        @ast.TsType::Array(t) => t
        _ => declared
      }
      let names : Array[String] = []
      collect_binding_names(binding, names)
      for name in names {
        locals.push((name, elem_type))
        ctx.set_type(name, elem_type)
      }
      for s in body.stmts {
        type_check_stmt(ctx, s, locals)
      }
      ctx.leave_scope()
    }
    @ast.TsStmt::ForAwaitOf(_, binding, declared, iter_expr, body) => {
      ctx.enter_scope()
      let iter_type = infer_expr_flow(ctx, iter_expr)
      let elem_type = match iter_type {
        @ast.TsType::Array(t) => t
        _ => declared
      }
      let names : Array[String] = []
      collect_binding_names(binding, names)
      for name in names {
        locals.push((name, elem_type))
        ctx.set_type(name, elem_type)
      }
      for s in body.stmts {
        type_check_stmt(ctx, s, locals)
      }
      ctx.leave_scope()
    }
    @ast.TsStmt::ForIn(_, binding, declared, obj_expr, body) => {
      ctx.enter_scope()
      let _ = infer_expr_flow(ctx, obj_expr)
      let names : Array[String] = []
      collect_binding_names(binding, names)
      for name in names {
        locals.push((name, declared))
        ctx.set_type(name, declared)
      }
      for s in body.stmts {
        type_check_stmt(ctx, s, locals)
      }
      ctx.leave_scope()
    }
    @ast.TsStmt::Switch(discriminant, cases) => {
      let disc_type = infer_expr_flow(ctx, discriminant)
      for case_ in cases {
        match case_.test_expr {
          Some(test_e) => {
            let case_type = infer_expr_flow(ctx, test_e)
            // Check case type is compatible
            if not(is_assignable(case_type, disc_type)) &&
              not(is_assignable(disc_type, case_type)) {
              ctx.add_constraint(
                Equal(case_type, disc_type, SourceLoc::unknown()),
              )
            }
          }
          None => () // default case
        }
        ctx.enter_scope()
        for s in case_.body.stmts {
          type_check_stmt(ctx, s, locals)
        }
        ctx.leave_scope()
      }
    }
    @ast.TsStmt::Try(try_block, binding, catch_block, finally_block) => {
      ctx.enter_scope()
      for s in try_block.stmts {
        type_check_stmt(ctx, s, locals)
      }
      ctx.leave_scope()
      match (binding, catch_block) {
        (Some(b), Some(cb)) => {
          ctx.enter_scope()
          let names : Array[String] = []
          collect_binding_names(b, names)
          for name in names {
            ctx.set_type(name, @ast.TsType::Any)
            locals.push((name, @ast.TsType::Any))
          }
          for s in cb.stmts {
            type_check_stmt(ctx, s, locals)
          }
          ctx.leave_scope()
        }
        (None, Some(cb)) => {
          ctx.enter_scope()
          for s in cb.stmts {
            type_check_stmt(ctx, s, locals)
          }
          ctx.leave_scope()
        }
        _ => ()
      }
      match finally_block {
        Some(fb) => {
          ctx.enter_scope()
          for s in fb.stmts {
            type_check_stmt(ctx, s, locals)
          }
          ctx.leave_scope()
        }
        None => ()
      }
    }
    @ast.TsStmt::Block(block) => {
      ctx.enter_scope()
      for s in block.stmts {
        type_check_stmt(ctx, s, locals)
      }
      ctx.leave_scope()
    }
    @ast.TsStmt::Throw(e) => {
      let _ = infer_expr_flow(ctx, e)
    }
    @ast.TsStmt::Label(_, inner) => type_check_stmt(ctx, inner, locals)
    @ast.TsStmt::With(obj, body) => {
      let _ = infer_expr_flow(ctx, obj)
      ctx.enter_scope()
      for s in body.stmts {
        type_check_stmt(ctx, s, locals)
      }
      ctx.leave_scope()
    }
    _ => ()
  }
}

///|
/// Type check variable declaration.
fn type_check_var_decl(
  ctx : FlowTypeCtx,
  binding : @ast.TsBinding,
  declared : @ast.TsType,
  init : @ast.TsExpr,
  locals : Array[(String, @ast.TsType)],
) -> Unit {
  let init_type = infer_expr_flow(ctx, init)
  let resolved = if declared == @ast.TsType::Any { init_type } else { declared }
  // Check initializer type matches declared type
  if declared != @ast.TsType::Any && init_type != @ast.TsType::Any {
    ctx.add_constraint(Assignable(init_type, declared, SourceLoc::unknown()))
  }
  let names : Array[String] = []
  collect_binding_names(binding, names)
  for name in names {
    locals.push((name, resolved))
    ctx.set_type(name, resolved)
  }
}

///|
/// Type check if statement with type narrowing.
fn type_check_if(
  ctx : FlowTypeCtx,
  cond : @ast.TsExpr,
  then_block : @ast.TsBlock,
  else_block : @ast.TsBlock?,
  locals : Array[(String, @ast.TsType)],
) -> Unit {
  let _ = infer_expr_flow(ctx, cond)

  // Check for type guards
  ctx.enter_scope()
  // Apply narrowing for typeof guards
  match analyze_typeof_guard(cond) {
    Some((var_name, type_str)) => {
      let base_type = ctx.get_type(var_name)
      let narrowed = narrow_type(base_type, type_str)
      ctx.narrow(var_name, narrowed)
    }
    None => ()
  }
  // Apply narrowing for null guards
  match analyze_null_guard(cond) {
    Some((var_name, is_not_null)) =>
      if is_not_null {
        let base_type = ctx.get_type(var_name)
        let narrowed = remove_null_undefined(base_type)
        ctx.narrow(var_name, narrowed)
      }
    None => ()
  }
  // Apply truthiness narrowing
  match analyze_truthiness_guard(cond) {
    Some(var_name) => {
      let base_type = ctx.get_type(var_name)
      let narrowed = remove_falsy(base_type)
      ctx.narrow(var_name, narrowed)
    }
    None => ()
  }
  for s in then_block.stmts {
    type_check_stmt(ctx, s, locals)
  }
  ctx.leave_scope()
  // Else branch with negated narrowing
  match else_block {
    Some(eb) => {
      ctx.enter_scope()
      // Apply negated narrowing
      match analyze_typeof_guard(cond) {
        Some((var_name, type_str)) => {
          let base_type = ctx.get_type(var_name)
          let narrowed = narrow_type_negated(base_type, type_str)
          ctx.narrow(var_name, narrowed)
        }
        None => ()
      }
      for s in eb.stmts {
        type_check_stmt(ctx, s, locals)
      }
      ctx.leave_scope()
    }
    None => ()
  }
}

///|
/// Infer expression type with flow context.
fn infer_expr_flow(ctx : FlowTypeCtx, expr : @ast.TsExpr) -> @ast.TsType {
  match expr {
    @ast.TsExpr::NumberLit(_) => @ast.TsType::Number
    @ast.TsExpr::IntLit(_) => @ast.TsType::Int
    @ast.TsExpr::BigIntLit(_) => @ast.TsType::BigInt
    @ast.TsExpr::BoolLit(_) => @ast.TsType::Boolean
    @ast.TsExpr::StringLit(_) => @ast.TsType::String_
    @ast.TsExpr::NullLit => @ast.TsType::Null
    @ast.TsExpr::Var(name) => ctx.get_type(name)
    @ast.TsExpr::ArrayHole => @ast.TsType::Undefined
    @ast.TsExpr::TemplateLiteral(_, _) => @ast.TsType::String_
    @ast.TsExpr::TaggedTemplate(_, _, _, _) => @ast.TsType::Any
    @ast.TsExpr::ArrayLit(elements) =>
      if elements.length() > 0 {
        // Infer common type from all elements
        let mut common_type = infer_expr_flow(ctx, elements[0])
        for i = 1; i < elements.length(); i = i + 1 {
          let elem_type = infer_expr_flow(ctx, elements[i])
          if elem_type != common_type {
            // If types differ, use union
            common_type = union_types(common_type, elem_type)
          }
        }
        @ast.TsType::Array(common_type)
      } else {
        @ast.TsType::Array(@ast.TsType::Any)
      }
    @ast.TsExpr::ObjectLit(props) => {
      let prop_types : Array[(@ast.TsType, @ast.TsType)] = []
      for prop in props {
        let (key, value) = prop
        let val_type = infer_expr_flow(ctx, value)
        prop_types.push((@ast.TsType::Literal(key), val_type))
      }
      @ast.TsType::Object(prop_types)
    }
    @ast.TsExpr::Spread(e) => infer_expr_flow(ctx, e)
    @ast.TsExpr::ComputedProp(_, value) => infer_expr_flow(ctx, value)
    @ast.TsExpr::BinOp(op, left, right) =>
      infer_binop_flow(ctx, op, left, right)
    @ast.TsExpr::UnaryOp(op, operand) =>
      match op {
        @ast.TsUnaryOp::Neg | @ast.TsUnaryOp::Plus =>
          infer_expr_flow(ctx, operand)
        @ast.TsUnaryOp::Not => @ast.TsType::Boolean
        @ast.TsUnaryOp::BitwiseNot => @ast.TsType::Number
        @ast.TsUnaryOp::Typeof => @ast.TsType::String_
        @ast.TsUnaryOp::Void => @ast.TsType::Undefined
        @ast.TsUnaryOp::Delete => @ast.TsType::Boolean
        @ast.TsUnaryOp::PreInc
        | @ast.TsUnaryOp::PreDec
        | @ast.TsUnaryOp::PostInc
        | @ast.TsUnaryOp::PostDec => infer_expr_flow(ctx, operand)
      }
    @ast.TsExpr::Call(name, args) => {
      // Get function type and check arguments
      let func_type = ctx.get_type(name)
      match func_type {
        @ast.TsType::Func(param_types, ret_type) => {
          // Check each argument against parameter type
          for i = 0; i < args.length(); i = i + 1 {
            let arg_type = infer_expr_flow(ctx, args[i])
            if i < param_types.length() {
              let param_type = param_types[i]
              if not(is_assignable(arg_type, param_type)) {
                ctx.add_constraint(
                  Assignable(arg_type, param_type, SourceLoc::unknown()),
                )
              }
            }
          }
          ret_type
        }
        _ =>
          // Fallback to registered return types
          match ctx.base_ctx.func_return_types.get(name) {
            Some(t) => t
            None => @ast.TsType::Any
          }
      }
    }
    @ast.TsExpr::CallExpr(callee, args) => {
      let callee_type = infer_expr_flow(ctx, callee)
      match callee_type {
        @ast.TsType::Func(param_types, ret_type) => {
          // Check each argument against parameter type
          for i = 0; i < args.length(); i = i + 1 {
            let arg_type = infer_expr_flow(ctx, args[i])
            if i < param_types.length() {
              let param_type = param_types[i]
              if not(is_assignable(arg_type, param_type)) {
                ctx.add_constraint(
                  Assignable(arg_type, param_type, SourceLoc::unknown()),
                )
              }
            }
          }
          ret_type
        }
        _ => {
          // Still infer argument types for side effects
          for arg in args {
            let _ = infer_expr_flow(ctx, arg)
          }
          @ast.TsType::Any
        }
      }
    }
    @ast.TsExpr::MethodCall(receiver, method_name, args) => {
      let recv_type = infer_expr_flow(ctx, receiver)
      // Get method type from receiver type
      let method_type = get_method_type(recv_type, method_name)
      match method_type {
        Some(@ast.TsType::Func(param_types, ret_type)) => {
          // Check arguments against parameter types
          for i = 0; i < args.length(); i = i + 1 {
            let arg_type = infer_expr_flow(ctx, args[i])
            if i < param_types.length() {
              let param_type = param_types[i]
              if not(is_assignable(arg_type, param_type)) {
                ctx.add_constraint(
                  Assignable(arg_type, param_type, SourceLoc::unknown()),
                )
              }
            }
          }
          ret_type
        }
        _ => {
          // Fallback: infer args and use method return type inference
          for arg in args {
            let _ = infer_expr_flow(ctx, arg)
          }
          infer_method_name_type(recv_type, method_name)
        }
      }
    }
    @ast.TsExpr::PropAccess(obj, prop) => {
      let obj_type = infer_expr_flow(ctx, obj)
      infer_prop_type(ctx, obj_type, prop)
    }
    @ast.TsExpr::IndexAccess(arr, index) => {
      let arr_type = infer_expr_flow(ctx, arr)
      let _ = infer_expr_flow(ctx, index)
      match arr_type {
        @ast.TsType::Array(elem) => elem
        @ast.TsType::Tuple(elems) =>
          match index {
            @ast.TsExpr::IntLit(i) =>
              if i >= 0 && i < elems.length() {
                elems[i]
              } else {
                @ast.TsType::Any
              }
            _ => @ast.TsType::Any
          }
        @ast.TsType::String_ => @ast.TsType::String_
        _ => @ast.TsType::Any
      }
    }
    @ast.TsExpr::Cond(cond, then_e, else_e) => {
      let _ = infer_expr_flow(ctx, cond)
      let then_type = infer_expr_flow(ctx, then_e)
      let else_type = infer_expr_flow(ctx, else_e)
      union_types(then_type, else_type)
    }
    @ast.TsExpr::AssignExpr(_, e) => infer_expr_flow(ctx, e)
    @ast.TsExpr::AssignPattern(_, e) => infer_expr_flow(ctx, e)
    @ast.TsExpr::PropAssignExpr(_, _, e) => infer_expr_flow(ctx, e)
    @ast.TsExpr::IndexAssignExpr(_, _, e) => infer_expr_flow(ctx, e)
    @ast.TsExpr::CompoundAssignExpr(left, _, _) => infer_expr_flow(ctx, left)
    @ast.TsExpr::Seq(_, right) => infer_expr_flow(ctx, right)
    @ast.TsExpr::New(name, args) => {
      for arg in args {
        let _ = infer_expr_flow(ctx, arg)
      }
      // Return the class type
      match ctx.registry.get_object(name) {
        Some(_) => @ast.TsType::Any // TODO: return proper instance type
        None => @ast.TsType::Any
      }
    }
    @ast.TsExpr::NewExpr(callee, args) => {
      let _ = infer_expr_flow(ctx, callee)
      for arg in args {
        let _ = infer_expr_flow(ctx, arg)
      }
      @ast.TsType::Any
    }
    @ast.TsExpr::ArrowFunc(params, body, _) =>
      infer_arrow_type(ctx, params, body)
    @ast.TsExpr::FuncExpr(func) => {
      let param_types : Array[@ast.TsType] = []
      for param in func.params {
        param_types.push(param.type_)
      }
      @ast.TsType::Func(param_types, func.return_type)
    }
    @ast.TsExpr::Yield(_) => @ast.TsType::Any
    @ast.TsExpr::YieldStar(_) => @ast.TsType::Any
    @ast.TsExpr::Await(e) => {
      let inner = infer_expr_flow(ctx, e)
      // Unwrap Promise type
      inner
    }
    @ast.TsExpr::DynamicImport(_) => @ast.TsType::Any // Promise<Module>
    @ast.TsExpr::ImportMeta => @ast.TsType::Any
  }
}

///|
/// Infer binary operation type with flow context.
fn infer_binop_flow(
  ctx : FlowTypeCtx,
  op : @ast.TsBinOp,
  left : @ast.TsExpr,
  right : @ast.TsExpr,
) -> @ast.TsType {
  let left_type = infer_expr_flow(ctx, left)
  let right_type = infer_expr_flow(ctx, right)
  match op {
    // Comparison operators
    @ast.TsBinOp::BinLt
    | @ast.TsBinOp::BinLe
    | @ast.TsBinOp::BinGt
    | @ast.TsBinOp::BinGe
    | @ast.TsBinOp::BinEq
    | @ast.TsBinOp::BinNe
    | @ast.TsBinOp::AbstractEq
    | @ast.TsBinOp::AbstractNe
    | @ast.TsBinOp::Instanceof
    | @ast.TsBinOp::In => @ast.TsType::Boolean
    // Logical and/or return one of the operand types
    @ast.TsBinOp::And => right_type // Returns right if left is truthy
    @ast.TsBinOp::Or => union_types(left_type, right_type)
    @ast.TsBinOp::Coalesce =>
      union_types(remove_null_undefined(left_type), right_type)
    // Add: string if either is string
    @ast.TsBinOp::Add =>
      if left_type == @ast.TsType::String_ || right_type == @ast.TsType::String_ {
        @ast.TsType::String_
      } else {
        left_type
      }
    // Arithmetic
    @ast.TsBinOp::Sub
    | @ast.TsBinOp::Mul
    | @ast.TsBinOp::Div
    | @ast.TsBinOp::Mod
    | @ast.TsBinOp::Pow => left_type
    // Bitwise
    @ast.TsBinOp::BitAnd
    | @ast.TsBinOp::BitOr
    | @ast.TsBinOp::BitXor
    | @ast.TsBinOp::Shl
    | @ast.TsBinOp::Shr
    | @ast.TsBinOp::UShr => @ast.TsType::Int
  }
}

///|
/// Get the full function type for a method (including parameters).
fn get_method_type(
  recv_type : @ast.TsType,
  method_name : String,
) -> @ast.TsType? {
  match recv_type {
    @ast.TsType::String_ =>
      match method_name {
        "charAt" =>
          Some(@ast.TsType::Func([@ast.TsType::Int], @ast.TsType::String_))
        "charCodeAt" =>
          Some(@ast.TsType::Func([@ast.TsType::Int], @ast.TsType::Int))
        "substring" | "slice" =>
          Some(
            @ast.TsType::Func(
              [@ast.TsType::Int, @ast.TsType::Int],
              @ast.TsType::String_,
            ),
          )
        "indexOf" | "lastIndexOf" =>
          Some(@ast.TsType::Func([@ast.TsType::String_], @ast.TsType::Int))
        "startsWith" | "endsWith" | "includes" =>
          Some(@ast.TsType::Func([@ast.TsType::String_], @ast.TsType::Boolean))
        "split" =>
          Some(
            @ast.TsType::Func(
              [@ast.TsType::String_],
              @ast.TsType::Array(@ast.TsType::String_),
            ),
          )
        "repeat" =>
          Some(@ast.TsType::Func([@ast.TsType::Int], @ast.TsType::String_))
        "padStart" | "padEnd" =>
          Some(
            @ast.TsType::Func(
              [@ast.TsType::Int, @ast.TsType::String_],
              @ast.TsType::String_,
            ),
          )
        _ => None
      }
    @ast.TsType::Array(elem) =>
      match method_name {
        "push" => Some(@ast.TsType::Func([elem], @ast.TsType::Int))
        "indexOf" | "lastIndexOf" =>
          Some(@ast.TsType::Func([elem], @ast.TsType::Int))
        "includes" => Some(@ast.TsType::Func([elem], @ast.TsType::Boolean))
        "join" =>
          Some(@ast.TsType::Func([@ast.TsType::String_], @ast.TsType::String_))
        "at" => Some(@ast.TsType::Func([@ast.TsType::Int], elem))
        "fill" => Some(@ast.TsType::Func([elem], @ast.TsType::Array(elem)))
        _ => None
      }
    @ast.TsType::Object(props) =>
      // Look up method in object properties
      for prop in props {
        match prop.0 {
          @ast.TsType::Literal(name) if name == method_name =>
            match prop.1 {
              @ast.TsType::Func(_, _) as func_type => return Some(func_type)
              _ => return None
            }
          _ => ()
        }
      } nobreak {
        None
      }
    _ => None
  }
}

///|
/// Infer method_name return type.
fn infer_method_name_type(
  recv_type : @ast.TsType,
  method_name : String,
) -> @ast.TsType {
  match recv_type {
    @ast.TsType::String_ =>
      match method_name {
        "charAt"
        | "substring"
        | "slice"
        | "substr"
        | "concat"
        | "repeat"
        | "trim"
        | "trimStart"
        | "trimEnd"
        | "toLowerCase"
        | "toUpperCase"
        | "padStart"
        | "padEnd"
        | "replace"
        | "replaceAll"
        | "normalize" => @ast.TsType::String_
        "charCodeAt"
        | "codePointAt"
        | "indexOf"
        | "lastIndexOf"
        | "localeCompare"
        | "search" => @ast.TsType::Int
        "split" => @ast.TsType::Array(@ast.TsType::String_)
        "match" | "matchAll" => @ast.TsType::Array(@ast.TsType::String_)
        "startsWith" | "endsWith" | "includes" => @ast.TsType::Boolean
        "at" => @ast.TsType::String_
        _ => @ast.TsType::Any
      }
    @ast.TsType::Array(elem) =>
      match method_name {
        "push" | "unshift" => @ast.TsType::Int
        "pop" | "shift" | "at" | "find" => elem
        "slice"
        | "concat"
        | "filter"
        | "map"
        | "flatMap"
        | "reverse"
        | "sort"
        | "fill"
        | "copyWithin"
        | "flat" => @ast.TsType::Array(elem)
        "join" | "toString" | "toLocaleString" => @ast.TsType::String_
        "indexOf" | "lastIndexOf" | "findIndex" | "findLastIndex" =>
          @ast.TsType::Int
        "includes" | "every" | "some" => @ast.TsType::Boolean
        "forEach" => @ast.TsType::Void
        "reduce" | "reduceRight" => @ast.TsType::Any
        "entries" | "keys" | "values" => @ast.TsType::Any // Iterator
        "with" | "toSorted" | "toReversed" | "toSpliced" =>
          @ast.TsType::Array(elem)
        _ => @ast.TsType::Any
      }
    @ast.TsType::Number | @ast.TsType::Int =>
      match method_name {
        "toString"
        | "toFixed"
        | "toExponential"
        | "toPrecision"
        | "toLocaleString" => @ast.TsType::String_
        _ => @ast.TsType::Any
      }
    @ast.TsType::Object(props) =>
      // Check if method_name exists in props
      for prop in props {
        match prop.0 {
          @ast.TsType::Literal(name) if name == method_name =>
            match prop.1 {
              @ast.TsType::Func(_, ret) => return ret
              _ => return prop.1
            }
          _ => ()
        }
      } nobreak {
        @ast.TsType::Any
      }
    _ => @ast.TsType::Any
  }
}

///|
/// Infer property access type.
fn infer_prop_type(
  ctx : FlowTypeCtx,
  obj_type : @ast.TsType,
  prop : String,
) -> @ast.TsType {
  match obj_type {
    @ast.TsType::String_ =>
      if prop == "length" {
        @ast.TsType::Int
      } else {
        @ast.TsType::Any
      }
    @ast.TsType::Array(_) =>
      if prop == "length" {
        @ast.TsType::Int
      } else {
        @ast.TsType::Any
      }
    @ast.TsType::Object(props) =>
      for p in props {
        match p.0 {
          @ast.TsType::Literal(name) if name == prop => return p.1
          _ => ()
        }
      } nobreak {
        @ast.TsType::Any
      }
    _ =>
      // Check registry for named types
      match ctx.registry.get_object(prop) {
        Some(obj) =>
          match obj.get_prop(prop) {
            Some(t) => t
            None => @ast.TsType::Any
          }
        None => @ast.TsType::Any
      }
  }
}

///|
/// Infer arrow function type.
fn infer_arrow_type(
  ctx : FlowTypeCtx,
  params : Array[@ast.TsParam],
  body : @ast.TsArrowBody,
) -> @ast.TsType {
  let param_types : Array[@ast.TsType] = []
  for param in params {
    param_types.push(param.type_)
  }
  // Infer return type from body
  let ret_type = match body {
    @ast.TsArrowBody::ArrowExpr(e) => infer_expr_flow(ctx, e)
    @ast.TsArrowBody::ArrowBlock(_) => @ast.TsType::Any // Would need full analysis
  }
  @ast.TsType::Func(param_types, ret_type)
}
