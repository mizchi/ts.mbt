// Closure Code Generation
// Converts closures to wasm-gc using closure conversion.

///|
/// Result of compiling a closure to wasm-gc.
pub struct ClosureWasmCode {
  /// Environment struct type definition (for captured variables)
  env_struct_type : @core.TypeDef?
  /// The closure function type
  func_type : @core.TypeDef
  /// The closure function code
  func_code : @core.Code
  /// Name of the generated function
  func_name : String
  /// Captured variable names (in order)
  capture_names : Array[String]
}

///|
/// Information about variables lifted to an environment struct.
pub struct LiftedVarsInfo {
  /// Variables that need to be lifted to the environment
  lifted_vars : Array[String]
  /// Whether each lifted var is mutated by closures
  is_mutated : Map[String, Bool]
  /// Field index in env struct for each lifted var
  field_indices : Map[String, UInt]
}

///|
/// Create empty lifted vars info.
pub fn LiftedVarsInfo::empty() -> LiftedVarsInfo {
  { lifted_vars: [], is_mutated: {}, field_indices: {} }
}

///|
/// Analyze a function body to find variables that need to be lifted.
/// Returns info about which variables are captured by closures.
pub fn analyze_lifted_vars(
  block : @ast.TsBlock,
  params : Array[String],
) -> LiftedVarsInfo {
  let captured : Map[String, Bool] = {} // name -> is_mutated

  // Collect all local variable declarations
  let locals : Array[String] = []
  collect_local_decls(block, locals)

  // Combine params and locals as the outer scope
  let outer_scope : Array[String] = []
  for p in params {
    outer_scope.push(p)
  }
  for l in locals {
    if not(outer_scope.contains(l)) {
      outer_scope.push(l)
    }
  }

  // Find closures and their captures
  find_closure_captures_in_block(block, outer_scope, captured)

  // Build result
  let lifted_vars : Array[String] = []
  let is_mutated : Map[String, Bool] = {}
  let field_indices : Map[String, UInt] = {}
  let mut idx : UInt = 0
  for entry in captured {
    lifted_vars.push(entry.0)
    is_mutated[entry.0] = entry.1
    field_indices[entry.0] = idx
    idx += 1
  }
  { lifted_vars, is_mutated, field_indices }
}

///|
fn collect_local_decls(block : @ast.TsBlock, locals : Array[String]) -> Unit {
  for stmt in block.stmts {
    match stmt {
      @ast.TsStmt::Var(binding, _, _)
      | @ast.TsStmt::Let(binding, _, _)
      | @ast.TsStmt::Const(binding, _, _) =>
        collect_binding_names_for_lift(binding, locals)
      @ast.TsStmt::If(_, then_block, else_block) => {
        collect_local_decls(then_block, locals)
        match else_block {
          Some(eb) => collect_local_decls(eb, locals)
          None => ()
        }
      }
      @ast.TsStmt::While(_, body) | @ast.TsStmt::DoWhile(_, body) =>
        collect_local_decls(body, locals)
      @ast.TsStmt::For(init, _, _, body) => {
        match init {
          Some(@ast.TsStmt::Var(binding, _, _))
          | Some(@ast.TsStmt::Let(binding, _, _))
          | Some(@ast.TsStmt::Const(binding, _, _)) =>
            collect_binding_names_for_lift(binding, locals)
          _ => ()
        }
        collect_local_decls(body, locals)
      }
      @ast.TsStmt::ForOf(_, binding, _, _, body)
      | @ast.TsStmt::ForIn(_, binding, _, _, body) => {
        collect_binding_names_for_lift(binding, locals)
        collect_local_decls(body, locals)
      }
      @ast.TsStmt::Block(inner) => collect_local_decls(inner, locals)
      @ast.TsStmt::Try(try_block, catch_param, catch_block, finally_block) => {
        collect_local_decls(try_block, locals)
        match catch_param {
          Some(binding) => collect_binding_names_for_lift(binding, locals)
          None => ()
        }
        match catch_block {
          Some(cb) => collect_local_decls(cb, locals)
          None => ()
        }
        match finally_block {
          Some(fb) => collect_local_decls(fb, locals)
          None => ()
        }
      }
      @ast.TsStmt::Switch(_, cases) =>
        for c in cases {
          collect_local_decls(c.body, locals)
        }
      _ => ()
    }
  }
}

///|
fn collect_binding_names_for_lift(
  binding : @ast.TsBinding,
  names : Array[String],
) -> Unit {
  match binding {
    @ast.TsBinding::Ident(name) =>
      if not(names.contains(name)) {
        names.push(name)
      }
    @ast.TsBinding::Array(arr) => {
      for item in arr.items {
        match item {
          Some(elem) => collect_binding_names_for_lift(elem.binding, names)
          None => ()
        }
      }
      match arr.rest {
        Some(rest) => collect_binding_names_for_lift(rest, names)
        None => ()
      }
    }
    @ast.TsBinding::Object(obj) => {
      for prop in obj.props {
        collect_binding_names_for_lift(prop.binding, names)
      }
      match obj.rest {
        Some(rest_name) =>
          if not(names.contains(rest_name)) {
            names.push(rest_name)
          }
        None => ()
      }
    }
    @ast.TsBinding::Target(_) => ()
  }
}

///|
fn find_closure_captures_in_block(
  block : @ast.TsBlock,
  outer_scope : Array[String],
  captured : Map[String, Bool],
) -> Unit {
  for stmt in block.stmts {
    find_closure_captures_in_stmt(stmt, outer_scope, captured)
  }
}

///|
fn find_closure_captures_in_stmt(
  stmt : @ast.TsStmt,
  outer_scope : Array[String],
  captured : Map[String, Bool],
) -> Unit {
  match stmt {
    @ast.TsStmt::Expr(expr) =>
      find_closure_captures_in_expr(expr, outer_scope, captured)
    @ast.TsStmt::Return(Some(expr)) =>
      find_closure_captures_in_expr(expr, outer_scope, captured)
    @ast.TsStmt::Var(_, _, init)
    | @ast.TsStmt::Let(_, _, init)
    | @ast.TsStmt::Const(_, _, init) =>
      find_closure_captures_in_expr(init, outer_scope, captured)
    @ast.TsStmt::Assign(_, expr) =>
      find_closure_captures_in_expr(expr, outer_scope, captured)
    @ast.TsStmt::CompoundAssign(_, _, expr) =>
      find_closure_captures_in_expr(expr, outer_scope, captured)
    @ast.TsStmt::If(cond, then_block, else_block) => {
      find_closure_captures_in_expr(cond, outer_scope, captured)
      find_closure_captures_in_block(then_block, outer_scope, captured)
      match else_block {
        Some(eb) => find_closure_captures_in_block(eb, outer_scope, captured)
        None => ()
      }
    }
    @ast.TsStmt::While(cond, body) | @ast.TsStmt::DoWhile(cond, body) => {
      find_closure_captures_in_expr(cond, outer_scope, captured)
      find_closure_captures_in_block(body, outer_scope, captured)
    }
    @ast.TsStmt::For(init, cond, update, body) => {
      match init {
        Some(s) => find_closure_captures_in_stmt(s, outer_scope, captured)
        None => ()
      }
      match cond {
        Some(e) => find_closure_captures_in_expr(e, outer_scope, captured)
        None => ()
      }
      match update {
        Some(s) => find_closure_captures_in_stmt(s, outer_scope, captured)
        None => ()
      }
      find_closure_captures_in_block(body, outer_scope, captured)
    }
    @ast.TsStmt::ForOf(_, _, _, iter, body)
    | @ast.TsStmt::ForIn(_, _, _, iter, body) => {
      find_closure_captures_in_expr(iter, outer_scope, captured)
      find_closure_captures_in_block(body, outer_scope, captured)
    }
    @ast.TsStmt::Block(block) =>
      find_closure_captures_in_block(block, outer_scope, captured)
    @ast.TsStmt::Try(try_block, _, catch_block, finally_block) => {
      find_closure_captures_in_block(try_block, outer_scope, captured)
      match catch_block {
        Some(cb) => find_closure_captures_in_block(cb, outer_scope, captured)
        None => ()
      }
      match finally_block {
        Some(fb) => find_closure_captures_in_block(fb, outer_scope, captured)
        None => ()
      }
    }
    @ast.TsStmt::Switch(expr, cases) => {
      find_closure_captures_in_expr(expr, outer_scope, captured)
      for c in cases {
        find_closure_captures_in_block(c.body, outer_scope, captured)
      }
    }
    @ast.TsStmt::Throw(expr) =>
      find_closure_captures_in_expr(expr, outer_scope, captured)
    _ => ()
  }
}

///|
fn find_closure_captures_in_expr(
  expr : @ast.TsExpr,
  outer_scope : Array[String],
  captured : Map[String, Bool],
) -> Unit {
  match expr {
    // Found a closure - analyze its captures
    @ast.TsExpr::ArrowFunc(params, body, _) => {
      let param_names : Array[String] = []
      for p in params {
        param_names.push(p.name)
      }
      // Find what this closure captures and whether it mutates
      let closure_captures : Map[String, @analysis.CapturedVar] = {}
      match body {
        @ast.TsArrowBody::ArrowExpr(e) =>
          @analysis.find_captures_in_expr(
            e, param_names, outer_scope, closure_captures,
          )
        @ast.TsArrowBody::ArrowBlock(block) =>
          @analysis.find_captures_in_block(
            block, param_names, outer_scope, closure_captures,
          )
      }
      // Add to captured map
      for entry in closure_captures {
        let name = entry.0
        let cap = entry.1
        match captured.get(name) {
          Some(existing_mut) => captured[name] = existing_mut || cap.is_mutated
          None => captured[name] = cap.is_mutated
        }
      }
    }
    @ast.TsExpr::FuncExpr(func) => {
      let param_names : Array[String] = []
      for p in func.params {
        param_names.push(p.name)
      }
      let closure_captures : Map[String, @analysis.CapturedVar] = {}
      @analysis.find_captures_in_block(
        func.body,
        param_names,
        outer_scope,
        closure_captures,
      )
      for entry in closure_captures {
        let name = entry.0
        let cap = entry.1
        match captured.get(name) {
          Some(existing_mut) => captured[name] = existing_mut || cap.is_mutated
          None => captured[name] = cap.is_mutated
        }
      }
    }
    // Recurse into subexpressions
    @ast.TsExpr::BinOp(_, left, right) => {
      find_closure_captures_in_expr(left, outer_scope, captured)
      find_closure_captures_in_expr(right, outer_scope, captured)
    }
    @ast.TsExpr::UnaryOp(_, operand) =>
      find_closure_captures_in_expr(operand, outer_scope, captured)
    @ast.TsExpr::Call(_, args) =>
      for arg in args {
        find_closure_captures_in_expr(arg, outer_scope, captured)
      }
    @ast.TsExpr::CallExpr(callee, args) => {
      find_closure_captures_in_expr(callee, outer_scope, captured)
      for arg in args {
        find_closure_captures_in_expr(arg, outer_scope, captured)
      }
    }
    @ast.TsExpr::MethodCall(recv, _, args) => {
      find_closure_captures_in_expr(recv, outer_scope, captured)
      for arg in args {
        find_closure_captures_in_expr(arg, outer_scope, captured)
      }
    }
    @ast.TsExpr::PropAccess(obj, _) =>
      find_closure_captures_in_expr(obj, outer_scope, captured)
    @ast.TsExpr::IndexAccess(arr, idx) => {
      find_closure_captures_in_expr(arr, outer_scope, captured)
      find_closure_captures_in_expr(idx, outer_scope, captured)
    }
    @ast.TsExpr::ArrayLit(elements) =>
      for elem in elements {
        find_closure_captures_in_expr(elem, outer_scope, captured)
      }
    @ast.TsExpr::ObjectLit(fields) =>
      for field in fields {
        find_closure_captures_in_expr(field.1, outer_scope, captured)
      }
    @ast.TsExpr::Cond(cond, then_e, else_e) => {
      find_closure_captures_in_expr(cond, outer_scope, captured)
      find_closure_captures_in_expr(then_e, outer_scope, captured)
      find_closure_captures_in_expr(else_e, outer_scope, captured)
    }
    @ast.TsExpr::AssignExpr(_, value) =>
      find_closure_captures_in_expr(value, outer_scope, captured)
    @ast.TsExpr::Seq(left, right) => {
      find_closure_captures_in_expr(left, outer_scope, captured)
      find_closure_captures_in_expr(right, outer_scope, captured)
    }
    @ast.TsExpr::New(_, args) =>
      for arg in args {
        find_closure_captures_in_expr(arg, outer_scope, captured)
      }
    _ => ()
  }
}

///|
/// Context for closure code generation.
pub struct ClosureCodegenCtx {
  /// Unique ID for generating names
  mut id : Int
  /// Base type index
  base_type_idx : UInt
}

///|
/// Create a new closure codegen context.
pub fn ClosureCodegenCtx::new(base_type_idx : UInt) -> ClosureCodegenCtx {
  { id: 0, base_type_idx }
}

///|
/// Generate a unique closure name.
fn ClosureCodegenCtx::gen_name(
  self : ClosureCodegenCtx,
  prefix : String,
) -> String {
  let name = "\{prefix}_\{self.id}"
  self.id += 1
  name
}

///|
/// Compile an arrow function to wasm-gc.
pub fn compile_arrow_func(
  params : Array[@ast.TsParam],
  body : @ast.TsArrowBody,
  outer_scope : Array[String],
  ctx : ClosureCodegenCtx,
) -> ClosureWasmCode? {
  // Analyze the closure
  let info = @analysis.analyze_arrow_func(params, body, outer_scope)
  if not(info.compilable) {
    return None
  }

  // Generate unique name
  let func_name = ctx.gen_name("$closure")

  // Build environment struct if there are captures
  let env_struct_type : @core.TypeDef? = if info.captures.length() > 0 {
    let fields : Array[@core.FieldType] = []
    for cap in info.captures {
      // All captured values are f64 for now
      // Use mutable field if the capture is mutated
      fields.push({
        storage: @core.StorageType::Val(@core.ValType::F64),
        mutable: cap.is_mutated,
      })
    }
    Some(@core.TypeDef::Struct({ fields, }))
  } else {
    None
  }

  // Build function type
  // Parameters: env (if captures exist) + closure params
  let param_types : Array[@core.ValType] = []
  if info.captures.length() > 0 {
    // Environment struct reference (nullable=false)
    param_types.push(
      @core.ValType::Ref(
        @core.RefType::TypeIndex(ctx.base_type_idx.reinterpret_as_int()),
        false,
      ),
    )
  }
  // Regular parameters (all f64 for now)
  for _ in params {
    param_types.push(@core.ValType::F64)
  }
  let func_type = @core.TypeDef::Func({
    params: param_types,
    results: [@core.ValType::F64],
  })

  // Generate function code
  let func_code = generate_closure_code(
    params,
    body,
    info,
    ctx.base_type_idx,
    func_name,
  )
  Some({
    env_struct_type,
    func_type,
    func_code,
    func_name,
    capture_names: @analysis.get_capture_names(info),
  })
}

///|
/// Compile a function expression to wasm-gc.
pub fn compile_func_expr(
  func : @ast.TsFunc,
  outer_scope : Array[String],
  ctx : ClosureCodegenCtx,
) -> ClosureWasmCode? {
  // Analyze the closure
  let info = @analysis.analyze_func_expr(func, outer_scope)
  if not(info.compilable) {
    return None
  }

  // Generate unique name
  let func_name = if func.name.length() > 0 {
    ctx.gen_name("$" + func.name)
  } else {
    ctx.gen_name("$anon")
  }

  // Build environment struct if there are captures
  let env_struct_type : @core.TypeDef? = if info.captures.length() > 0 {
    let fields : Array[@core.FieldType] = []
    for cap in info.captures {
      // Use mutable field if the capture is mutated
      fields.push({
        storage: @core.StorageType::Val(@core.ValType::F64),
        mutable: cap.is_mutated,
      })
    }
    Some(@core.TypeDef::Struct({ fields, }))
  } else {
    None
  }

  // Build function type
  let param_types : Array[@core.ValType] = []
  if info.captures.length() > 0 {
    param_types.push(
      @core.ValType::Ref(
        @core.RefType::TypeIndex(ctx.base_type_idx.reinterpret_as_int()),
        false,
      ),
    )
  }
  for _ in func.params {
    param_types.push(@core.ValType::F64)
  }
  let func_type = @core.TypeDef::Func({
    params: param_types,
    results: [@core.ValType::F64],
  })

  // Generate function code
  let func_code = generate_func_expr_code(
    func,
    info,
    ctx.base_type_idx,
    func_name,
  )
  Some({
    env_struct_type,
    func_type,
    func_code,
    func_name,
    capture_names: @analysis.get_capture_names(info),
  })
}

///|
fn generate_closure_code(
  params : Array[@ast.TsParam],
  body : @ast.TsArrowBody,
  info : @analysis.ClosureInfo,
  env_type_idx : UInt,
  _func_name : String,
) -> @core.Code {
  let instrs : Array[@core.Instr] = []
  let locals : Array[@core.ValType] = []

  // Build variable index mapping
  // local 0: env (if captures exist)
  // local 1..n: params
  // local n+1..m: local variables
  let var_indices : Map[String, UInt] = {}
  let mut local_idx : UInt = 0

  // Environment parameter (if captures exist)
  let has_env = info.captures.length() > 0
  if has_env {
    local_idx = 1
  }

  // Parameters
  for p in params {
    var_indices[p.name] = local_idx
    local_idx += 1
  }

  // Capture variable to field index mapping
  let capture_indices : Map[String, UInt] = {}
  for i, cap in info.captures {
    capture_indices[cap.name] = i.reinterpret_as_uint()
  }

  // Generate body code
  let body_instrs = match body {
    @ast.TsArrowBody::ArrowExpr(expr) =>
      generate_closure_expr(
        expr, var_indices, capture_indices, has_env, env_type_idx, locals,
      )
    @ast.TsArrowBody::ArrowBlock(block) =>
      generate_closure_block(
        block, var_indices, capture_indices, has_env, env_type_idx, locals,
      )
  }
  for i in body_instrs {
    instrs.push(i)
  }

  // Ensure return value (implicit return for expression)
  // For blocks, we add a default return at the end if needed
  // Expression bodies already leave value on stack

  { locals, body: { instrs, }, compiled: None, max_stack_height: 0 }
}

///|
fn generate_func_expr_code(
  func : @ast.TsFunc,
  info : @analysis.ClosureInfo,
  env_type_idx : UInt,
  _func_name : String,
) -> @core.Code {
  let instrs : Array[@core.Instr] = []
  let locals : Array[@core.ValType] = []

  // Build variable index mapping
  let var_indices : Map[String, UInt] = {}
  let mut local_idx : UInt = 0
  let has_env = info.captures.length() > 0
  if has_env {
    local_idx = 1
  }
  for p in func.params {
    var_indices[p.name] = local_idx
    local_idx += 1
  }
  let capture_indices : Map[String, UInt] = {}
  for i, cap in info.captures {
    capture_indices[cap.name] = i.reinterpret_as_uint()
  }
  let body_instrs = generate_closure_block(
    func.body,
    var_indices,
    capture_indices,
    has_env,
    env_type_idx,
    locals,
  )
  for i in body_instrs {
    instrs.push(i)
  }

  // Default return value
  instrs.push(@core.Instr::F64Const(0.0))
  { locals, body: { instrs, }, compiled: None, max_stack_height: 0 }
}

///|
fn generate_closure_block(
  block : @ast.TsBlock,
  var_indices : Map[String, UInt],
  capture_indices : Map[String, UInt],
  has_env : Bool,
  env_type_idx : UInt,
  locals : Array[@core.ValType],
) -> Array[@core.Instr] {
  let instrs : Array[@core.Instr] = []

  // Collect local declarations and assign indices
  let local_var_indices = var_indices.copy()
  let mut next_local = var_indices
    .iter()
    .fold(init=0U, fn(max, entry) { if entry.1 > max { entry.1 } else { max } }) +
    1
  for stmt in block.stmts {
    match stmt {
      @ast.TsStmt::Var(binding, _, _)
      | @ast.TsStmt::Let(binding, _, _)
      | @ast.TsStmt::Const(binding, _, _) => {
        let names : Array[String] = []
        collect_binding_names_simple(binding, names)
        for name in names {
          if not(local_var_indices.contains(name)) {
            local_var_indices[name] = next_local
            locals.push(@core.ValType::F64)
            next_local += 1
          }
        }
      }
      _ => ()
    }
  }
  for stmt in block.stmts {
    let stmt_instrs = generate_closure_stmt(
      stmt, local_var_indices, capture_indices, has_env, env_type_idx, locals,
    )
    for i in stmt_instrs {
      instrs.push(i)
    }
  }
  instrs
}

///|
fn collect_binding_names_simple(
  binding : @ast.TsBinding,
  names : Array[String],
) -> Unit {
  match binding {
    @ast.TsBinding::Ident(name) => names.push(name)
    @ast.TsBinding::Array(arr) => {
      for item in arr.items {
        match item {
          Some(elem) => collect_binding_names_simple(elem.binding, names)
          None => ()
        }
      }
      match arr.rest {
        Some(rest) => collect_binding_names_simple(rest, names)
        None => ()
      }
    }
    @ast.TsBinding::Object(obj) => {
      for prop in obj.props {
        collect_binding_names_simple(prop.binding, names)
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
fn generate_closure_stmt(
  stmt : @ast.TsStmt,
  var_indices : Map[String, UInt],
  capture_indices : Map[String, UInt],
  has_env : Bool,
  env_type_idx : UInt,
  locals : Array[@core.ValType],
) -> Array[@core.Instr] {
  match stmt {
    @ast.TsStmt::Expr(expr) => {
      let instrs = generate_closure_expr(
        expr, var_indices, capture_indices, has_env, env_type_idx, locals,
      )
      let result : Array[@core.Instr] = []
      for i in instrs {
        result.push(i)
      }
      result.push(@core.Instr::Drop)
      result
    }
    @ast.TsStmt::Return(expr_opt) =>
      match expr_opt {
        Some(expr) => {
          let instrs = generate_closure_expr(
            expr, var_indices, capture_indices, has_env, env_type_idx, locals,
          )
          let result : Array[@core.Instr] = []
          for i in instrs {
            result.push(i)
          }
          result.push(@core.Instr::Return)
          result
        }
        None => [@core.Instr::F64Const(0.0), @core.Instr::Return]
      }
    @ast.TsStmt::Var(binding, _, init)
    | @ast.TsStmt::Let(binding, _, init)
    | @ast.TsStmt::Const(binding, _, init) => {
      let instrs : Array[@core.Instr] = []
      // Simple case: single identifier
      match binding {
        @ast.TsBinding::Ident(name) =>
          match var_indices.get(name) {
            Some(idx) => {
              let expr_instrs = generate_closure_expr(
                init, var_indices, capture_indices, has_env, env_type_idx, locals,
              )
              for i in expr_instrs {
                instrs.push(i)
              }
              instrs.push(@core.Instr::LocalSet(idx))
            }
            None => ()
          }
        _ => {
          // Complex binding patterns - simplified for now
          let expr_instrs = generate_closure_expr(
            init, var_indices, capture_indices, has_env, env_type_idx, locals,
          )
          for i in expr_instrs {
            instrs.push(i)
          }
          instrs.push(@core.Instr::Drop)
        }
      }
      instrs
    }
    @ast.TsStmt::Assign(name, expr) =>
      // Check if it's a local variable first
      match var_indices.get(name) {
        Some(idx) => {
          let instrs = generate_closure_expr(
            expr, var_indices, capture_indices, has_env, env_type_idx, locals,
          )
          let result : Array[@core.Instr] = []
          for i in instrs {
            result.push(i)
          }
          result.push(@core.Instr::LocalSet(idx))
          result
        }
        None =>
          // Check if it's a captured variable (mutable capture)
          match capture_indices.get(name) {
            Some(field_idx) =>
              if has_env {
                let result : Array[@core.Instr] = []
                // Get env reference
                result.push(@core.Instr::LocalGet(0U))
                // Evaluate value
                let value_instrs = generate_closure_expr(
                  expr, var_indices, capture_indices, has_env, env_type_idx, locals,
                )
                for i in value_instrs {
                  result.push(i)
                }
                // Store to env struct field
                result.push(@core.Instr::StructSet(env_type_idx, field_idx))
                result
              } else {
                []
              }
            None => []
          }
      }
    @ast.TsStmt::If(cond, then_block, else_block) => {
      let instrs : Array[@core.Instr] = []
      let cond_instrs = generate_closure_expr(
        cond, var_indices, capture_indices, has_env, env_type_idx, locals,
      )
      for i in cond_instrs {
        instrs.push(i)
      }
      instrs.push(@core.Instr::I32TruncF64S)
      let then_instrs = generate_closure_block(
        then_block, var_indices, capture_indices, has_env, env_type_idx, locals,
      )
      let else_instrs = match else_block {
        Some(eb) =>
          generate_closure_block(
            eb, var_indices, capture_indices, has_env, env_type_idx, locals,
          )
        None => []
      }
      instrs.push(
        @core.Instr::If(@core.BlockType::Empty, then_instrs, else_instrs),
      )
      instrs
    }
    @ast.TsStmt::While(cond, body) => {
      let instrs : Array[@core.Instr] = []
      let loop_body : Array[@core.Instr] = []
      let cond_instrs = generate_closure_expr(
        cond, var_indices, capture_indices, has_env, env_type_idx, locals,
      )
      for i in cond_instrs {
        loop_body.push(i)
      }
      loop_body.push(@core.Instr::I32TruncF64S)
      loop_body.push(@core.Instr::I32Eqz)
      loop_body.push(@core.Instr::BrIf(1U))
      let body_instrs = generate_closure_block(
        body, var_indices, capture_indices, has_env, env_type_idx, locals,
      )
      for i in body_instrs {
        loop_body.push(i)
      }
      loop_body.push(@core.Instr::Br(0U))
      instrs.push(
        @core.Instr::Block(@core.BlockType::Empty, [
          @core.Instr::Loop(@core.BlockType::Empty, loop_body),
        ]),
      )
      instrs
    }
    _ => []
  }
}

///|
fn generate_closure_expr(
  expr : @ast.TsExpr,
  var_indices : Map[String, UInt],
  capture_indices : Map[String, UInt],
  has_env : Bool,
  env_type_idx : UInt,
  locals : Array[@core.ValType],
) -> Array[@core.Instr] {
  match expr {
    @ast.TsExpr::NumberLit(n) => [@core.Instr::F64Const(n)]
    @ast.TsExpr::IntLit(n) => [@core.Instr::F64Const(n.to_double())]
    @ast.TsExpr::BoolLit(b) =>
      [@core.Instr::F64Const(if b { 1.0 } else { 0.0 })]
    @ast.TsExpr::NullLit => [@core.Instr::F64Const(0.0)]
    @ast.TsExpr::Var(name) =>
      // Check if it's a captured variable
      match capture_indices.get(name) {
        Some(field_idx) =>
          if has_env {
            // Load from environment struct
            [
              @core.Instr::LocalGet(0U), // env is always local 0
              @core.Instr::StructGet(env_type_idx, field_idx),
            ]
          } else {
            [@core.Instr::F64Const(0.0)]
          }
        None =>
          // Local variable
          match var_indices.get(name) {
            Some(idx) => [@core.Instr::LocalGet(idx)]
            None => [@core.Instr::F64Const(0.0)] // Unknown variable
          }
      }
    @ast.TsExpr::BinOp(op, left, right) => {
      let instrs : Array[@core.Instr] = []
      let left_instrs = generate_closure_expr(
        left, var_indices, capture_indices, has_env, env_type_idx, locals,
      )
      let right_instrs = generate_closure_expr(
        right, var_indices, capture_indices, has_env, env_type_idx, locals,
      )
      for i in left_instrs {
        instrs.push(i)
      }
      for i in right_instrs {
        instrs.push(i)
      }
      instrs.push(binop_to_wasm(op))
      instrs
    }
    @ast.TsExpr::UnaryOp(op, operand) => {
      let instrs = generate_closure_expr(
        operand, var_indices, capture_indices, has_env, env_type_idx, locals,
      )
      let result : Array[@core.Instr] = []
      for i in instrs {
        result.push(i)
      }
      match op {
        @ast.TsUnaryOp::Neg => result.push(@core.Instr::F64Neg)
        @ast.TsUnaryOp::Not => {
          result.push(@core.Instr::I32TruncF64S)
          result.push(@core.Instr::I32Eqz)
          result.push(@core.Instr::F64ConvertI32S)
        }
        @ast.TsUnaryOp::BitwiseNot => {
          result.push(@core.Instr::I32TruncF64S)
          result.push(@core.Instr::I32Const(0xFFFFFFFF))
          result.push(@core.Instr::I32Xor)
          result.push(@core.Instr::F64ConvertI32S)
        }
        _ => ()
      }
      result
    }
    @ast.TsExpr::Cond(cond, then_e, else_e) => {
      let instrs : Array[@core.Instr] = []
      let cond_instrs = generate_closure_expr(
        cond, var_indices, capture_indices, has_env, env_type_idx, locals,
      )
      for i in cond_instrs {
        instrs.push(i)
      }
      instrs.push(@core.Instr::I32TruncF64S)
      let then_instrs = generate_closure_expr(
        then_e, var_indices, capture_indices, has_env, env_type_idx, locals,
      )
      let else_instrs = generate_closure_expr(
        else_e, var_indices, capture_indices, has_env, env_type_idx, locals,
      )
      instrs.push(
        @core.Instr::If(
          @core.BlockType::Value(@core.ValType::F64),
          then_instrs,
          else_instrs,
        ),
      )
      instrs
    }
    @ast.TsExpr::Seq(left, right) => {
      let instrs = generate_closure_expr(
        left, var_indices, capture_indices, has_env, env_type_idx, locals,
      )
      let result : Array[@core.Instr] = []
      for i in instrs {
        result.push(i)
      }
      result.push(@core.Instr::Drop)
      let right_instrs = generate_closure_expr(
        right, var_indices, capture_indices, has_env, env_type_idx, locals,
      )
      for i in right_instrs {
        result.push(i)
      }
      result
    }
    @ast.TsExpr::AssignExpr(name, value) =>
      // Check if it's a local variable first
      match var_indices.get(name) {
        Some(idx) => {
          let instrs = generate_closure_expr(
            value, var_indices, capture_indices, has_env, env_type_idx, locals,
          )
          let result : Array[@core.Instr] = []
          for i in instrs {
            result.push(i)
          }
          result.push(@core.Instr::LocalTee(idx))
          result
        }
        None =>
          // Check if it's a captured variable (mutable capture)
          match capture_indices.get(name) {
            Some(field_idx) =>
              if has_env {
                let result : Array[@core.Instr] = []
                // Get env reference
                result.push(@core.Instr::LocalGet(0U))
                // Evaluate value
                let value_instrs = generate_closure_expr(
                  value, var_indices, capture_indices, has_env, env_type_idx, locals,
                )
                for i in value_instrs {
                  result.push(i)
                }
                // Store to env struct field
                result.push(@core.Instr::StructSet(env_type_idx, field_idx))
                // Return the value (need to reload it for assignment expression semantics)
                result.push(@core.Instr::LocalGet(0U))
                result.push(@core.Instr::StructGet(env_type_idx, field_idx))
                result
              } else {
                [@core.Instr::F64Const(0.0)]
              }
            None => [@core.Instr::F64Const(0.0)]
          }
      }
    _ => [@core.Instr::F64Const(0.0)]
  }
}

///|
fn binop_to_wasm(op : @ast.TsBinOp) -> @core.Instr {
  match op {
    @ast.TsBinOp::Add => @core.Instr::F64Add
    @ast.TsBinOp::Sub => @core.Instr::F64Sub
    @ast.TsBinOp::Mul => @core.Instr::F64Mul
    @ast.TsBinOp::Div => @core.Instr::F64Div
    @ast.TsBinOp::Mod =>
      // f64 mod is tricky, need to implement with sub/trunc
      // For now, simplified
      @core.Instr::F64Sub
    @ast.TsBinOp::BinLt => @core.Instr::F64Lt
    @ast.TsBinOp::BinGt => @core.Instr::F64Gt
    @ast.TsBinOp::BinLe => @core.Instr::F64Le
    @ast.TsBinOp::BinGe => @core.Instr::F64Ge
    @ast.TsBinOp::BinEq | @ast.TsBinOp::AbstractEq => @core.Instr::F64Eq
    @ast.TsBinOp::BinNe | @ast.TsBinOp::AbstractNe => @core.Instr::F64Ne
    _ => @core.Instr::F64Add // Default
  }
}

// ============================================================
// Environment Sharing - Outer function code generation
// ============================================================

///|
/// Result of compiling a function with environment sharing.
pub struct FuncWithEnvCode {
  /// Environment struct type definition
  env_struct_type : @core.TypeDef?
  /// The main function code
  func_code : @core.Code
  /// Generated closure functions
  closure_funcs : Array[ClosureWasmCode]
  /// Environment local variable index in main function
  env_local_idx : UInt?
}

///|
/// Compile a function body with environment sharing for closures.
/// This handles the case where closures modify captured variables
/// and the outer function needs to see those modifications.
pub fn compile_func_body_with_env(
  block : @ast.TsBlock,
  params : Array[@ast.TsParam],
  lifted_info : LiftedVarsInfo,
  env_type_idx : UInt,
) -> FuncWithEnvCode {
  let instrs : Array[@core.Instr] = []
  let locals : Array[@core.ValType] = []
  let closure_funcs : Array[ClosureWasmCode] = []

  // Build variable index mapping
  // local 0..n-1: params
  // local n: env (if lifted vars exist)
  // local n+1..m: other local variables
  let var_indices : Map[String, UInt] = {}
  let mut local_idx : UInt = 0

  // Parameters
  let param_names : Array[String] = []
  for p in params {
    var_indices[p.name] = local_idx
    param_names.push(p.name)
    local_idx += 1
  }

  // Environment local (if we have lifted vars)
  let env_local_idx : UInt? = if lifted_info.lifted_vars.length() > 0 {
    let idx = local_idx
    locals.push(
      @core.ValType::Ref(
        @core.RefType::TypeIndex(env_type_idx.reinterpret_as_int()),
        true,
      ),
    )
    local_idx += 1
    Some(idx)
  } else {
    None
  }

  // Create environment struct at function entry
  let env_struct_type : @core.TypeDef? = if lifted_info.lifted_vars.length() > 0 {
    // Build struct type
    let fields : Array[@core.FieldType] = []
    for name in lifted_info.lifted_vars {
      let is_mut = lifted_info.is_mutated.get(name).unwrap_or(false)
      fields.push({
        storage: @core.StorageType::Val(@core.ValType::F64),
        mutable: is_mut,
      })
    }
    let struct_type = @core.TypeDef::Struct({ fields, })

    // Generate struct.new with initial values
    // For params, use the param value; for locals, use 0.0
    for name in lifted_info.lifted_vars {
      if param_names.contains(name) {
        // Use param value
        match var_indices.get(name) {
          Some(idx) => instrs.push(@core.Instr::LocalGet(idx))
          None => instrs.push(@core.Instr::F64Const(0.0))
        }
      } else {
        // Local variable - initialize to 0
        instrs.push(@core.Instr::F64Const(0.0))
      }
    }
    instrs.push(@core.Instr::StructNew(env_type_idx))
    match env_local_idx {
      Some(idx) => instrs.push(@core.Instr::LocalSet(idx))
      None => ()
    }
    Some(struct_type)
  } else {
    None
  }

  // Generate body code with env access
  let body_instrs = generate_body_with_env(
    block, var_indices, lifted_info, env_local_idx, env_type_idx, locals, closure_funcs,
  )
  for i in body_instrs {
    instrs.push(i)
  }

  // Default return
  instrs.push(@core.Instr::F64Const(0.0))
  {
    env_struct_type,
    func_code: {
      locals,
      body: { instrs, },
      compiled: None,
      max_stack_height: 0,
    },
    closure_funcs,
    env_local_idx,
  }
}

///|
fn generate_body_with_env(
  block : @ast.TsBlock,
  var_indices : Map[String, UInt],
  lifted_info : LiftedVarsInfo,
  env_local_idx : UInt?,
  env_type_idx : UInt,
  locals : Array[@core.ValType],
  _closure_funcs : Array[ClosureWasmCode],
) -> Array[@core.Instr] {
  let instrs : Array[@core.Instr] = []

  // Collect local declarations (non-lifted)
  let local_var_indices = var_indices.copy()
  let mut next_local = locals.length().reinterpret_as_uint() +
    var_indices
    .iter()
    .fold(init=0U, fn(max, entry) {
      if entry.1 >= max {
        entry.1 + 1
      } else {
        max
      }
    })
  for stmt in block.stmts {
    match stmt {
      @ast.TsStmt::Var(binding, _, _)
      | @ast.TsStmt::Let(binding, _, _)
      | @ast.TsStmt::Const(binding, _, _) => {
        let names : Array[String] = []
        collect_binding_names_simple(binding, names)
        for name in names {
          // Don't assign local index to lifted vars
          if not(lifted_info.lifted_vars.contains(name)) &&
            not(local_var_indices.contains(name)) {
            local_var_indices[name] = next_local
            locals.push(@core.ValType::F64)
            next_local += 1
          }
        }
      }
      _ => ()
    }
  }
  for stmt in block.stmts {
    let stmt_instrs = generate_stmt_with_env(
      stmt, local_var_indices, lifted_info, env_local_idx, env_type_idx, locals,
    )
    for i in stmt_instrs {
      instrs.push(i)
    }
  }
  instrs
}

///|
fn generate_stmt_with_env(
  stmt : @ast.TsStmt,
  var_indices : Map[String, UInt],
  lifted_info : LiftedVarsInfo,
  env_local_idx : UInt?,
  env_type_idx : UInt,
  locals : Array[@core.ValType],
) -> Array[@core.Instr] {
  match stmt {
    @ast.TsStmt::Expr(expr) => {
      let instrs = generate_expr_with_env(
        expr, var_indices, lifted_info, env_local_idx, env_type_idx, locals,
      )
      let result : Array[@core.Instr] = []
      for i in instrs {
        result.push(i)
      }
      result.push(@core.Instr::Drop)
      result
    }
    @ast.TsStmt::Return(expr_opt) =>
      match expr_opt {
        Some(expr) => {
          let instrs = generate_expr_with_env(
            expr, var_indices, lifted_info, env_local_idx, env_type_idx, locals,
          )
          let result : Array[@core.Instr] = []
          for i in instrs {
            result.push(i)
          }
          result.push(@core.Instr::Return)
          result
        }
        None => [@core.Instr::F64Const(0.0), @core.Instr::Return]
      }
    @ast.TsStmt::Var(binding, _, init)
    | @ast.TsStmt::Let(binding, _, init)
    | @ast.TsStmt::Const(binding, _, init) => {
      let instrs : Array[@core.Instr] = []
      match binding {
        @ast.TsBinding::Ident(name) => {
          let expr_instrs = generate_expr_with_env(
            init, var_indices, lifted_info, env_local_idx, env_type_idx, locals,
          )
          // Check if this is a lifted var
          match lifted_info.field_indices.get(name) {
            Some(field_idx) =>
              // Store to env struct
              match env_local_idx {
                Some(env_idx) => {
                  instrs.push(@core.Instr::LocalGet(env_idx))
                  for i in expr_instrs {
                    instrs.push(i)
                  }
                  instrs.push(@core.Instr::StructSet(env_type_idx, field_idx))
                }
                None => ()
              }
            None =>
              // Store to local
              match var_indices.get(name) {
                Some(idx) => {
                  for i in expr_instrs {
                    instrs.push(i)
                  }
                  instrs.push(@core.Instr::LocalSet(idx))
                }
                None => {
                  for i in expr_instrs {
                    instrs.push(i)
                  }
                  instrs.push(@core.Instr::Drop)
                }
              }
          }
        }
        _ => {
          let expr_instrs = generate_expr_with_env(
            init, var_indices, lifted_info, env_local_idx, env_type_idx, locals,
          )
          for i in expr_instrs {
            instrs.push(i)
          }
          instrs.push(@core.Instr::Drop)
        }
      }
      instrs
    }
    @ast.TsStmt::Assign(name, expr) => {
      let instrs : Array[@core.Instr] = []
      let expr_instrs = generate_expr_with_env(
        expr, var_indices, lifted_info, env_local_idx, env_type_idx, locals,
      )
      // Check if this is a lifted var
      match lifted_info.field_indices.get(name) {
        Some(field_idx) =>
          // Store to env struct
          match env_local_idx {
            Some(env_idx) => {
              instrs.push(@core.Instr::LocalGet(env_idx))
              for i in expr_instrs {
                instrs.push(i)
              }
              instrs.push(@core.Instr::StructSet(env_type_idx, field_idx))
            }
            None => ()
          }
        None =>
          // Store to local
          match var_indices.get(name) {
            Some(idx) => {
              for i in expr_instrs {
                instrs.push(i)
              }
              instrs.push(@core.Instr::LocalSet(idx))
            }
            None => ()
          }
      }
      instrs
    }
    @ast.TsStmt::If(cond, then_block, else_block) => {
      let instrs : Array[@core.Instr] = []
      let cond_instrs = generate_expr_with_env(
        cond, var_indices, lifted_info, env_local_idx, env_type_idx, locals,
      )
      for i in cond_instrs {
        instrs.push(i)
      }
      instrs.push(@core.Instr::I32TruncF64S)
      let then_instrs = generate_body_with_env(
        then_block,
        var_indices,
        lifted_info,
        env_local_idx,
        env_type_idx,
        locals,
        [],
      )
      let else_instrs = match else_block {
        Some(eb) =>
          generate_body_with_env(
            eb,
            var_indices,
            lifted_info,
            env_local_idx,
            env_type_idx,
            locals,
            [],
          )
        None => []
      }
      instrs.push(
        @core.Instr::If(@core.BlockType::Empty, then_instrs, else_instrs),
      )
      instrs
    }
    @ast.TsStmt::While(cond, body) => {
      let instrs : Array[@core.Instr] = []
      let loop_body : Array[@core.Instr] = []
      let cond_instrs = generate_expr_with_env(
        cond, var_indices, lifted_info, env_local_idx, env_type_idx, locals,
      )
      for i in cond_instrs {
        loop_body.push(i)
      }
      loop_body.push(@core.Instr::I32TruncF64S)
      loop_body.push(@core.Instr::I32Eqz)
      loop_body.push(@core.Instr::BrIf(1U))
      let body_instrs = generate_body_with_env(
        body,
        var_indices,
        lifted_info,
        env_local_idx,
        env_type_idx,
        locals,
        [],
      )
      for i in body_instrs {
        loop_body.push(i)
      }
      loop_body.push(@core.Instr::Br(0U))
      instrs.push(
        @core.Instr::Block(@core.BlockType::Empty, [
          @core.Instr::Loop(@core.BlockType::Empty, loop_body),
        ]),
      )
      instrs
    }
    _ => []
  }
}

///|
fn generate_expr_with_env(
  expr : @ast.TsExpr,
  var_indices : Map[String, UInt],
  lifted_info : LiftedVarsInfo,
  env_local_idx : UInt?,
  env_type_idx : UInt,
  locals : Array[@core.ValType],
) -> Array[@core.Instr] {
  match expr {
    @ast.TsExpr::NumberLit(n) => [@core.Instr::F64Const(n)]
    @ast.TsExpr::IntLit(n) => [@core.Instr::F64Const(n.to_double())]
    @ast.TsExpr::BoolLit(b) =>
      [@core.Instr::F64Const(if b { 1.0 } else { 0.0 })]
    @ast.TsExpr::NullLit => [@core.Instr::F64Const(0.0)]
    @ast.TsExpr::Var(name) =>
      // Check if it's a lifted var
      match lifted_info.field_indices.get(name) {
        Some(field_idx) =>
          // Load from env struct
          match env_local_idx {
            Some(env_idx) =>
              [
                @core.Instr::LocalGet(env_idx),
                @core.Instr::StructGet(env_type_idx, field_idx),
              ]
            None => [@core.Instr::F64Const(0.0)]
          }
        None =>
          // Local variable
          match var_indices.get(name) {
            Some(idx) => [@core.Instr::LocalGet(idx)]
            None => [@core.Instr::F64Const(0.0)]
          }
      }
    @ast.TsExpr::BinOp(op, left, right) => {
      let instrs : Array[@core.Instr] = []
      let left_instrs = generate_expr_with_env(
        left, var_indices, lifted_info, env_local_idx, env_type_idx, locals,
      )
      let right_instrs = generate_expr_with_env(
        right, var_indices, lifted_info, env_local_idx, env_type_idx, locals,
      )
      for i in left_instrs {
        instrs.push(i)
      }
      for i in right_instrs {
        instrs.push(i)
      }
      instrs.push(binop_to_wasm(op))
      instrs
    }
    @ast.TsExpr::UnaryOp(op, operand) => {
      let instrs = generate_expr_with_env(
        operand, var_indices, lifted_info, env_local_idx, env_type_idx, locals,
      )
      let result : Array[@core.Instr] = []
      for i in instrs {
        result.push(i)
      }
      match op {
        @ast.TsUnaryOp::Neg => result.push(@core.Instr::F64Neg)
        @ast.TsUnaryOp::Not => {
          result.push(@core.Instr::I32TruncF64S)
          result.push(@core.Instr::I32Eqz)
          result.push(@core.Instr::F64ConvertI32S)
        }
        _ => ()
      }
      result
    }
    @ast.TsExpr::Cond(cond, then_e, else_e) => {
      let instrs : Array[@core.Instr] = []
      let cond_instrs = generate_expr_with_env(
        cond, var_indices, lifted_info, env_local_idx, env_type_idx, locals,
      )
      for i in cond_instrs {
        instrs.push(i)
      }
      instrs.push(@core.Instr::I32TruncF64S)
      let then_instrs = generate_expr_with_env(
        then_e, var_indices, lifted_info, env_local_idx, env_type_idx, locals,
      )
      let else_instrs = generate_expr_with_env(
        else_e, var_indices, lifted_info, env_local_idx, env_type_idx, locals,
      )
      instrs.push(
        @core.Instr::If(
          @core.BlockType::Value(@core.ValType::F64),
          then_instrs,
          else_instrs,
        ),
      )
      instrs
    }
    @ast.TsExpr::AssignExpr(name, value) =>
      // Check if it's a lifted var
      match lifted_info.field_indices.get(name) {
        Some(field_idx) =>
          // Store to env struct
          match env_local_idx {
            Some(env_idx) => {
              let result : Array[@core.Instr] = []
              result.push(@core.Instr::LocalGet(env_idx))
              let value_instrs = generate_expr_with_env(
                value, var_indices, lifted_info, env_local_idx, env_type_idx, locals,
              )
              for i in value_instrs {
                result.push(i)
              }
              result.push(@core.Instr::StructSet(env_type_idx, field_idx))
              // Return the value
              result.push(@core.Instr::LocalGet(env_idx))
              result.push(@core.Instr::StructGet(env_type_idx, field_idx))
              result
            }
            None => [@core.Instr::F64Const(0.0)]
          }
        None =>
          // Local variable
          match var_indices.get(name) {
            Some(idx) => {
              let instrs = generate_expr_with_env(
                value, var_indices, lifted_info, env_local_idx, env_type_idx, locals,
              )
              let result : Array[@core.Instr] = []
              for i in instrs {
                result.push(i)
              }
              result.push(@core.Instr::LocalTee(idx))
              result
            }
            None => [@core.Instr::F64Const(0.0)]
          }
      }
    @ast.TsExpr::Seq(left, right) => {
      let instrs = generate_expr_with_env(
        left, var_indices, lifted_info, env_local_idx, env_type_idx, locals,
      )
      let result : Array[@core.Instr] = []
      for i in instrs {
        result.push(i)
      }
      result.push(@core.Instr::Drop)
      let right_instrs = generate_expr_with_env(
        right, var_indices, lifted_info, env_local_idx, env_type_idx, locals,
      )
      for i in right_instrs {
        result.push(i)
      }
      result
    }
    // For closures, we skip code generation here (handled separately)
    @ast.TsExpr::ArrowFunc(_, _, _) | @ast.TsExpr::FuncExpr(_) =>
      [@core.Instr::F64Const(0.0)]
    _ => [@core.Instr::F64Const(0.0)]
  }
}
