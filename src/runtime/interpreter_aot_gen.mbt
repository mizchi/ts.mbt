// AOT Generator execution - runs generators using state machine IR.
// This module provides a pure interpreter-based state machine execution
// without depending on codegen/wasm packages to avoid circular dependencies.

///|
/// Generator state machine IR for AOT execution (runtime-local copy).
/// This is a simplified version that can be evaluated directly.
pub(all) struct AOTGenStateMachine {
  name : String
  params : Array[String]
  locals : Array[String]
  states : Array[AOTGenState]
  done_state : Int
}

///|
/// A state in the AOT generator state machine.
pub(all) struct AOTGenState {
  id : Int
  body : Array[AOTGenInstr]
}

///|
/// Instructions for AOT generator state machine.
pub(all) enum AOTGenInstr {
  Yield(AOTGenExpr, Int) // value, next_state
  Return(AOTGenExpr)
  SetLocal(String, AOTGenExpr)
  While(AOTGenExpr, Array[AOTGenInstr])
  Branch(AOTGenExpr, Array[AOTGenInstr], Array[AOTGenInstr])
  Exec(AOTGenExpr)
  Nop
}

///|
/// Expressions for AOT generator state machine.
pub(all) enum AOTGenExpr {
  Number(Double)
  Bool(Bool)
  Undefined
  Var(String)
  Sent // The value sent to generator via next(value)
  BinOp(AOTGenBinOp, AOTGenExpr, AOTGenExpr)
  UnaryOp(AOTGenUnaryOp, AOTGenExpr)
}

///|
/// Binary operators.
pub(all) enum AOTGenBinOp {
  Add
  Sub
  Mul
  Div
  Mod
  Lt
  Le
  Gt
  Ge
  Eq
  Ne
  And
  Or
  BitAnd
  BitOr
  BitXor
  Shl
  Shr
  Ushr
}

///|
/// Unary operators.
pub(all) enum AOTGenUnaryOp {
  Neg
  Not
  BitNot
}

///|
/// Execution context for AOT generator.
/// State data layout: [state_num, done_flag, signal_mode, signal_value, params..., locals...]
/// Indices: 0=state_num, 1=done, 2=signal_mode, 3=signal_value, 4+=params/locals
priv struct AOTExecContext {
  state_data : Array[Double] // [state_num, done_flag, signal_mode, signal_value, params..., locals...]
  sm : AOTGenStateMachine
  sent_value : Double
}

// State data field indices (matching generator_codegen.mbt)
let aot_idx_state_num : Int = 0

let aot_idx_done : Int = 1

let aot_idx_signal_mode : Int = 2

let aot_idx_signal_value : Int = 3

let aot_idx_params_start : Int = 4

// Signal modes (matching generator_codegen.mbt)
let aot_signal_normal : Double = 0.0

let aot_signal_throw : Double = 1.0

let aot_signal_return : Double = 2.0

///|
/// Try to build an AOT state machine from a generator function.
/// Returns None if the generator is too complex for AOT compilation.
fn try_build_aot_state_machine(
  func : @ast.TsFunc,
  args : Array[JSValue],
) -> (AOTGenStateMachine, Array[Double])? {
  if not(func.is_generator) {
    return None
  }

  // Check if the generator body is simple enough for AOT
  if not(is_simple_generator_body(func.body)) {
    return None
  }

  // Collect params and locals
  let params : Array[String] = []
  for p in func.params {
    params.push(p.name)
  }

  let locals : Array[String] = []
  collect_local_names(func.body, locals, params)

  // Build state machine from body
  let builder = AOTStateBuilder::new()
  let states = builder.build_states(func.body)

  let sm : AOTGenStateMachine = {
    name: func.name,
    params,
    locals,
    states,
    done_state: states.length(),
  }

  // Build initial state data
  // Layout: [state_num=0, done=0, signal_mode=0, signal_value=0, params..., locals...]
  let state_data : Array[Double] = []
  state_data.push(0.0) // state_num = 0
  state_data.push(0.0) // done = 0
  state_data.push(aot_signal_normal) // signal_mode = 0 (normal)
  state_data.push(0.0) // signal_value = 0.0

  // Add params
  for i in 0..<params.length() {
    let val = if i < args.length() {
      js_to_f64(args[i])
    } else {
      0.0
    }
    state_data.push(val)
  }

  // Add locals initialized to 0
  for _ in locals {
    state_data.push(0.0)
  }

  Some((sm, state_data))
}

///|
/// Check if a generator body is simple enough for AOT compilation.
fn is_simple_generator_body(block : @ast.TsBlock) -> Bool {
  for stmt in block.stmts {
    if not(is_simple_stmt(stmt)) {
      return false
    }
  }
  true
}

///|
/// Check if a statement is simple enough for AOT.
fn is_simple_stmt(stmt : @ast.TsStmt) -> Bool {
  match stmt {
    @ast.TsStmt::Expr(expr) => is_simple_expr(expr)
    @ast.TsStmt::Return(opt) =>
      match opt {
        Some(e) => is_simple_expr(e)
        None => true
      }
    @ast.TsStmt::Var(binding, _, init)
    | @ast.TsStmt::Let(binding, _, init)
    | @ast.TsStmt::Const(binding, _, init) =>
      is_simple_binding(binding) && is_simple_expr(init)
    @ast.TsStmt::Assign(_, expr) => is_simple_expr(expr)
    @ast.TsStmt::CompoundAssign(_, _, expr) => is_simple_expr(expr)
    @ast.TsStmt::If(cond, then_block, else_block) => {
      if not(is_simple_expr(cond)) || not(is_simple_generator_body(then_block)) {
        return false
      }
      match else_block {
        Some(eb) => is_simple_generator_body(eb)
        None => true
      }
    }
    @ast.TsStmt::While(cond, body) =>
      is_simple_expr(cond) && is_simple_generator_body(body)
    @ast.TsStmt::DoWhile(cond, body) =>
      is_simple_expr(cond) && is_simple_generator_body(body)
    @ast.TsStmt::For(init, cond, update, body) => {
      match init {
        Some(s) => if not(is_simple_stmt(s)) { return false }
        None => ()
      }
      match cond {
        Some(e) => if not(is_simple_expr(e)) { return false }
        None => ()
      }
      match update {
        Some(s) => if not(is_simple_stmt(s)) { return false }
        None => ()
      }
      is_simple_generator_body(body)
    }
    @ast.TsStmt::Block(block) => is_simple_generator_body(block)
    @ast.TsStmt::Break(_) | @ast.TsStmt::Continue(_) | @ast.TsStmt::Empty => true
    // Try/catch, function declarations, classes, etc. are not simple
    _ => false
  }
}

///|
/// Check if an expression is simple enough for AOT.
fn is_simple_expr(expr : @ast.TsExpr) -> Bool {
  match expr {
    @ast.TsExpr::NumberLit(_)
    | @ast.TsExpr::IntLit(_)
    | @ast.TsExpr::BoolLit(_)
    | @ast.TsExpr::NullLit
    | @ast.TsExpr::Var(_) => true
    @ast.TsExpr::Yield(opt) =>
      match opt {
        Some(e) => is_simple_expr(e)
        None => true
      }
    @ast.TsExpr::BinOp(_, left, right) =>
      is_simple_expr(left) && is_simple_expr(right)
    @ast.TsExpr::UnaryOp(_, operand) => is_simple_expr(operand)
    @ast.TsExpr::Cond(c, t, e) =>
      is_simple_expr(c) && is_simple_expr(t) && is_simple_expr(e)
    @ast.TsExpr::AssignExpr(_, val) => is_simple_expr(val)
    @ast.TsExpr::CompoundAssignExpr(left, _, right) =>
      is_simple_expr(left) && is_simple_expr(right)
    // Calls, property access, yield*, etc. are not simple
    _ => false
  }
}

///|
/// Check if a binding is simple (just an identifier).
fn is_simple_binding(binding : @ast.TsBinding) -> Bool {
  match binding {
    @ast.TsBinding::Ident(_) => true
    _ => false
  }
}

///|
/// Collect local variable names from a block.
fn collect_local_names(
  block : @ast.TsBlock,
  locals : Array[String],
  params : Array[String],
) -> Unit {
  for stmt in block.stmts {
    collect_local_names_stmt(stmt, locals, params)
  }
}

///|
fn collect_local_names_stmt(
  stmt : @ast.TsStmt,
  locals : Array[String],
  params : Array[String],
) -> Unit {
  match stmt {
    @ast.TsStmt::Var(@ast.TsBinding::Ident(name), _, _)
    | @ast.TsStmt::Let(@ast.TsBinding::Ident(name), _, _)
    | @ast.TsStmt::Const(@ast.TsBinding::Ident(name), _, _) => {
      if not(params.contains(name)) && not(locals.contains(name)) {
        locals.push(name)
      }
    }
    @ast.TsStmt::If(_, then_block, else_block) => {
      collect_local_names(then_block, locals, params)
      match else_block {
        Some(eb) => collect_local_names(eb, locals, params)
        None => ()
      }
    }
    @ast.TsStmt::While(_, body)
    | @ast.TsStmt::DoWhile(_, body) => collect_local_names(body, locals, params)
    @ast.TsStmt::For(init, _, _, body) => {
      match init {
        Some(s) => collect_local_names_stmt(s, locals, params)
        None => ()
      }
      collect_local_names(body, locals, params)
    }
    @ast.TsStmt::Block(block) => collect_local_names(block, locals, params)
    _ => ()
  }
}

///|
/// Builder for AOT state machine states.
priv struct AOTStateBuilder {
  states : Array[AOTGenState]
  mut next_yield_state : Int
}

///|
fn AOTStateBuilder::new() -> AOTStateBuilder {
  { states: [], next_yield_state: 1 }
}

///|
fn AOTStateBuilder::build_states(
  self : AOTStateBuilder,
  block : @ast.TsBlock,
) -> Array[AOTGenState] {
  // State 0: initial state
  let body = self.build_block(block)
  self.states.push({ id: 0, body })
  self.states
}

///|
fn AOTStateBuilder::build_block(
  self : AOTStateBuilder,
  block : @ast.TsBlock,
) -> Array[AOTGenInstr] {
  let instrs : Array[AOTGenInstr] = []
  for stmt in block.stmts {
    let stmt_instrs = self.build_stmt(stmt)
    for instr in stmt_instrs {
      instrs.push(instr)
    }
  }
  instrs
}

///|
fn AOTStateBuilder::build_stmt(
  self : AOTStateBuilder,
  stmt : @ast.TsStmt,
) -> Array[AOTGenInstr] {
  match stmt {
    @ast.TsStmt::Expr(expr) => self.build_expr_stmt(expr)
    @ast.TsStmt::Return(opt) =>
      match opt {
        Some(e) => [AOTGenInstr::Return(self.build_expr(e))]
        None => [AOTGenInstr::Return(AOTGenExpr::Undefined)]
      }
    @ast.TsStmt::Var(@ast.TsBinding::Ident(name), _, init)
    | @ast.TsStmt::Let(@ast.TsBinding::Ident(name), _, init)
    | @ast.TsStmt::Const(@ast.TsBinding::Ident(name), _, init) =>
      [AOTGenInstr::SetLocal(name, self.build_expr(init))]
    @ast.TsStmt::Assign(name, expr) =>
      [AOTGenInstr::SetLocal(name, self.build_expr(expr))]
    @ast.TsStmt::CompoundAssign(name, op, expr) => {
      let bin_op = compound_to_aot_binop(op)
      let new_val = AOTGenExpr::BinOp(
        bin_op,
        AOTGenExpr::Var(name),
        self.build_expr(expr),
      )
      [AOTGenInstr::SetLocal(name, new_val)]
    }
    @ast.TsStmt::If(cond, then_block, else_block) => {
      let cond_expr = self.build_expr(cond)
      let then_instrs = self.build_block(then_block)
      let else_instrs = match else_block {
        Some(eb) => self.build_block(eb)
        None => []
      }
      [AOTGenInstr::Branch(cond_expr, then_instrs, else_instrs)]
    }
    @ast.TsStmt::While(cond, body) => {
      let cond_expr = self.build_expr(cond)
      let body_instrs = self.build_block(body)
      [AOTGenInstr::While(cond_expr, body_instrs)]
    }
    @ast.TsStmt::DoWhile(cond, body) => {
      // do-while: execute body once, then while
      let cond_expr = self.build_expr(cond)
      let body_instrs = self.build_block(body)
      let result : Array[AOTGenInstr] = []
      for instr in body_instrs {
        result.push(instr)
      }
      result.push(AOTGenInstr::While(cond_expr, body_instrs))
      result
    }
    @ast.TsStmt::For(init, cond, update, body) =>
      self.build_for_stmt(init, cond, update, body)
    @ast.TsStmt::Block(block) => self.build_block(block)
    _ => [AOTGenInstr::Nop]
  }
}

///|
fn AOTStateBuilder::build_for_stmt(
  self : AOTStateBuilder,
  init : @ast.TsStmt?,
  cond : @ast.TsExpr?,
  update : @ast.TsStmt?,
  body : @ast.TsBlock,
) -> Array[AOTGenInstr] {
  let result : Array[AOTGenInstr] = []

  // Init
  match init {
    Some(s) =>
      for instr in self.build_stmt(s) {
        result.push(instr)
      }
    None => ()
  }

  // Build loop body with update
  let loop_body : Array[AOTGenInstr] = []
  for instr in self.build_block(body) {
    loop_body.push(instr)
  }
  match update {
    Some(s) =>
      for instr in self.build_stmt(s) {
        loop_body.push(instr)
      }
    None => ()
  }

  // Condition
  let cond_expr = match cond {
    Some(e) => self.build_expr(e)
    None => AOTGenExpr::Bool(true)
  }

  result.push(AOTGenInstr::While(cond_expr, loop_body))
  result
}

///|
fn AOTStateBuilder::build_expr_stmt(
  self : AOTStateBuilder,
  expr : @ast.TsExpr,
) -> Array[AOTGenInstr] {
  match expr {
    @ast.TsExpr::Yield(opt) => {
      let yield_expr = match opt {
        Some(e) => self.build_expr(e)
        None => AOTGenExpr::Undefined
      }
      let next_state = self.next_yield_state
      self.next_yield_state += 1
      [AOTGenInstr::Yield(yield_expr, next_state)]
    }
    @ast.TsExpr::AssignExpr(name, value) =>
      [AOTGenInstr::SetLocal(name, self.build_expr(value))]
    @ast.TsExpr::CompoundAssignExpr(@ast.TsExpr::Var(name), op, right) => {
      let bin_op = compound_op_to_aot_binop(op)
      let new_val = AOTGenExpr::BinOp(
        bin_op,
        AOTGenExpr::Var(name),
        self.build_expr(right),
      )
      [AOTGenInstr::SetLocal(name, new_val)]
    }
    _ => [AOTGenInstr::Exec(self.build_expr(expr))]
  }
}

///|
fn AOTStateBuilder::build_expr(
  self : AOTStateBuilder,
  expr : @ast.TsExpr,
) -> AOTGenExpr {
  match expr {
    @ast.TsExpr::NumberLit(n) => AOTGenExpr::Number(n)
    @ast.TsExpr::IntLit(n) => AOTGenExpr::Number(n.to_double())
    @ast.TsExpr::BoolLit(b) => AOTGenExpr::Bool(b)
    @ast.TsExpr::NullLit => AOTGenExpr::Number(0.0)
    @ast.TsExpr::Var(name) => AOTGenExpr::Var(name)
    @ast.TsExpr::BinOp(op, left, right) => {
      let aot_op = ast_binop_to_aot(op)
      AOTGenExpr::BinOp(aot_op, self.build_expr(left), self.build_expr(right))
    }
    @ast.TsExpr::UnaryOp(op, operand) => {
      let aot_op = ast_unaryop_to_aot(op)
      AOTGenExpr::UnaryOp(aot_op, self.build_expr(operand))
    }
    @ast.TsExpr::Cond(c, t, e) =>
      // Convert to: c != 0 ? t : e
      // For now, just evaluate condition and branch
      AOTGenExpr::BinOp(
        AOTGenBinOp::Add,
        AOTGenExpr::BinOp(
          AOTGenBinOp::Mul,
          self.build_expr(c),
          self.build_expr(t),
        ),
        AOTGenExpr::BinOp(
          AOTGenBinOp::Mul,
          AOTGenExpr::UnaryOp(AOTGenUnaryOp::Not, self.build_expr(c)),
          self.build_expr(e),
        ),
      )
    _ => AOTGenExpr::Undefined
  }
}

///|
fn compound_to_aot_binop(op : @ast.TsCompoundOp) -> AOTGenBinOp {
  match op {
    @ast.TsCompoundOp::AddAssign => AOTGenBinOp::Add
    @ast.TsCompoundOp::SubAssign => AOTGenBinOp::Sub
    @ast.TsCompoundOp::MulAssign => AOTGenBinOp::Mul
    @ast.TsCompoundOp::DivAssign => AOTGenBinOp::Div
    @ast.TsCompoundOp::ModAssign => AOTGenBinOp::Mod
    @ast.TsCompoundOp::BitAndAssign => AOTGenBinOp::BitAnd
    @ast.TsCompoundOp::BitOrAssign => AOTGenBinOp::BitOr
    @ast.TsCompoundOp::BitXorAssign => AOTGenBinOp::BitXor
    @ast.TsCompoundOp::ShlAssign => AOTGenBinOp::Shl
    @ast.TsCompoundOp::ShrAssign => AOTGenBinOp::Shr
    @ast.TsCompoundOp::UShrAssign => AOTGenBinOp::Ushr
    _ => AOTGenBinOp::Add
  }
}

///|
fn ast_binop_to_aot(op : @ast.TsBinOp) -> AOTGenBinOp {
  match op {
    @ast.TsBinOp::Add => AOTGenBinOp::Add
    @ast.TsBinOp::Sub => AOTGenBinOp::Sub
    @ast.TsBinOp::Mul => AOTGenBinOp::Mul
    @ast.TsBinOp::Div => AOTGenBinOp::Div
    @ast.TsBinOp::Mod => AOTGenBinOp::Mod
    @ast.TsBinOp::BinLt => AOTGenBinOp::Lt
    @ast.TsBinOp::BinLe => AOTGenBinOp::Le
    @ast.TsBinOp::BinGt => AOTGenBinOp::Gt
    @ast.TsBinOp::BinGe => AOTGenBinOp::Ge
    @ast.TsBinOp::BinEq | @ast.TsBinOp::AbstractEq => AOTGenBinOp::Eq
    @ast.TsBinOp::BinNe | @ast.TsBinOp::AbstractNe => AOTGenBinOp::Ne
    @ast.TsBinOp::And => AOTGenBinOp::And
    @ast.TsBinOp::Or => AOTGenBinOp::Or
    @ast.TsBinOp::BitAnd => AOTGenBinOp::BitAnd
    @ast.TsBinOp::BitOr => AOTGenBinOp::BitOr
    @ast.TsBinOp::BitXor => AOTGenBinOp::BitXor
    @ast.TsBinOp::Shl => AOTGenBinOp::Shl
    @ast.TsBinOp::Shr => AOTGenBinOp::Shr
    @ast.TsBinOp::UShr => AOTGenBinOp::Ushr
    _ => AOTGenBinOp::Add
  }
}

///|
/// Convert compound op to AOT binop.
fn compound_op_to_aot_binop(op : @ast.TsCompoundOp) -> AOTGenBinOp {
  compound_to_aot_binop(op)
}

///|
fn ast_unaryop_to_aot(op : @ast.TsUnaryOp) -> AOTGenUnaryOp {
  match op {
    @ast.TsUnaryOp::Neg => AOTGenUnaryOp::Neg
    @ast.TsUnaryOp::Not => AOTGenUnaryOp::Not
    @ast.TsUnaryOp::BitwiseNot => AOTGenUnaryOp::BitNot
    _ => AOTGenUnaryOp::Neg
  }
}

///|
/// Convert JSValue to f64 for AOT state.
fn js_to_f64(val : JSValue) -> Double {
  match val {
    Number(n) => n
    Bool(b) => if b { 1.0 } else { 0.0 }
    Undefined | Null => 0.0
    String(s) =>
      try {
        @strconv.parse_double(s)
      } catch {
        _ => 0.0 / 0.0 // NaN
      }
    _ => 0.0 / 0.0 // NaN for non-numeric types
  }
}

///|
/// Convert f64 to JSValue for iterator result.
fn f64_to_js(val : Double) -> JSValue {
  Number(val)
}

///|
/// Try to compile a generator function to AOT.
/// Returns (empty_bytes, initial_state_data) on success.
fn try_compile_generator_aot(
  func : @ast.TsFunc,
  args : Array[JSValue],
) -> (Bytes, Array[Double], AOTGenStateMachine?)? {
  match try_build_aot_state_machine(func, args) {
    Some((sm, state_data)) => Some((b"", state_data, Some(sm)))
    None => None
  }
}

///|
/// Execute AOT generator next() call.
fn JSInterpreter::generator_next_aot(
  self : JSInterpreter,
  gen_id : Int,
  sent : JSValue,
) -> JSValue {
  if gen_id < 0 || gen_id >= self.generators.length() {
    return self.set_error_kind("TypeError", "Invalid generator")
  }

  let state = self.generators[gen_id]
  if state.done {
    return self.make_iter_result(Undefined, true)
  }

  // Rebuild state machine (could be cached in state)
  match try_build_aot_state_machine(state.func, []) {
    Some((sm, _)) => {
      let result = self.execute_aot_state_machine(gen_id, sm, sent)
      result
    }
    None =>
      // Fallback to CPS interpreter
      self.generator_next_cps(gen_id, sent)
  }
}

///|
/// CPS-based generator next (original implementation).
fn JSInterpreter::generator_next_cps(
  self : JSInterpreter,
  gen_id : Int,
  sent : JSValue,
) -> JSValue {
  // This is the original implementation from generator_next
  let state = self.generators[gen_id]
  self.current_gen_id = Some(gen_id)
  match state.cont {
    Some(cont_fn) => {
      state.cont = None
      match cont_fn(sent) {
        GenSignal::Continue => self.generators[gen_id] = state
        GenSignal::Yield(val) => {
          self.generators[gen_id] = state
          self.current_gen_id = None
          return self.make_iter_result(val, false)
        }
        GenSignal::YieldRaw(result) => {
          self.generators[gen_id] = state
          self.current_gen_id = None
          return result
        }
        GenSignal::Suspend(val, cont) => {
          state.cont = Some(cont)
          self.generators[gen_id] = state
          self.current_gen_id = None
          return self.make_iter_result(val, false)
        }
        GenSignal::SuspendRaw(result, cont) => {
          state.cont = Some(cont)
          self.generators[gen_id] = state
          self.current_gen_id = None
          return result
        }
        GenSignal::Return(val) => {
          state.done = true
          self.generators[gen_id] = state
          self.current_gen_id = None
          return self.make_iter_result(val, true)
        }
      }
      match self.peek_error() {
        Some(err) => {
          state.done = true
          self.generators[gen_id] = state
          self.current_gen_id = None
          return err
        }
        None => ()
      }
    }
    None => ()
  }
  let stmts = state.func.body.stmts
  while state.index < stmts.length() {
    let stmt = stmts[state.index]
    state.index = state.index + 1
    match self.exec_stmt_gen(stmt, state.env) {
      GenSignal::Continue => ()
      GenSignal::Yield(val) => {
        self.generators[gen_id] = state
        self.current_gen_id = None
        return self.make_iter_result(val, false)
      }
      GenSignal::YieldRaw(result) => {
        self.generators[gen_id] = state
        self.current_gen_id = None
        return result
      }
      GenSignal::Suspend(val, cont) => {
        state.cont = Some(cont)
        self.generators[gen_id] = state
        self.current_gen_id = None
        return self.make_iter_result(val, false)
      }
      GenSignal::SuspendRaw(result, cont) => {
        state.cont = Some(cont)
        self.generators[gen_id] = state
        self.current_gen_id = None
        return result
      }
      GenSignal::Return(val) => {
        state.done = true
        self.generators[gen_id] = state
        self.current_gen_id = None
        return self.make_iter_result(val, true)
      }
    }
    match self.peek_error() {
      Some(err) => {
        state.done = true
        self.generators[gen_id] = state
        self.current_gen_id = None
        return err
      }
      None => ()
    }
  }
  state.done = true
  self.generators[gen_id] = state
  self.current_gen_id = None
  self.make_iter_result(Undefined, true)
}

///|
/// Execute AOT state machine.
fn JSInterpreter::execute_aot_state_machine(
  self : JSInterpreter,
  gen_id : Int,
  sm : AOTGenStateMachine,
  sent : JSValue,
) -> JSValue {
  let state = self.generators[gen_id]
  let state_data = state.aot_state_data

  // Check for throw/return signal (must be checked before state execution)
  if state_data[aot_idx_signal_mode] != aot_signal_normal {
    let signal_mode = state_data[aot_idx_signal_mode]
    let signal_value = state_data[aot_idx_signal_value]
    // Reset signal
    state_data[aot_idx_signal_mode] = aot_signal_normal
    state_data[aot_idx_signal_value] = 0.0
    // Set done flag
    state.done = true
    state_data[aot_idx_done] = 1.0
    self.generators[gen_id] = state
    // For throw, the value should cause an error
    // For return, just return the value with done=true
    if signal_mode == aot_signal_throw {
      // TODO: Properly throw the value as an error
      return self.make_iter_result(f64_to_js(signal_value), true)
    }
    // signal_mode == aot_signal_return
    return self.make_iter_result(f64_to_js(signal_value), true)
  }

  // Get current state number
  let state_num = state_data[aot_idx_state_num].to_int()

  // Check done flag
  if state_data[aot_idx_done] != 0.0 {
    state.done = true
    self.generators[gen_id] = state
    return self.make_iter_result(Undefined, true)
  }

  // Find current state
  if state_num >= sm.states.length() {
    // Done state
    state.done = true
    state_data[aot_idx_done] = 1.0
    self.generators[gen_id] = state
    return self.make_iter_result(Undefined, true)
  }

  let current_state = sm.states[state_num]
  let sent_f64 = js_to_f64(sent)

  // Execute state body
  let ctx : AOTExecContext = { state_data, sm, sent_value: sent_f64 }
  let (value, done, next_state) = self.execute_aot_state_body(
    ctx, current_state.body,
  )

  // Update state
  state_data[aot_idx_state_num] = next_state.to_double()
  if done {
    state.done = true
    state_data[aot_idx_done] = 1.0
  }
  self.generators[gen_id] = state

  self.make_iter_result(f64_to_js(value), done)
}

///|
/// Execute AOT state body.
fn JSInterpreter::execute_aot_state_body(
  self : JSInterpreter,
  ctx : AOTExecContext,
  body : Array[AOTGenInstr],
) -> (Double, Bool, Int) {
  for instr in body {
    match self.execute_aot_instr(ctx, instr) {
      Some((value, done, next_state)) => return (value, done, next_state)
      None => continue
    }
  }
  // Default: return undefined, done
  (0.0, true, ctx.sm.done_state)
}

///|
/// Execute a single AOT instruction.
fn JSInterpreter::execute_aot_instr(
  self : JSInterpreter,
  ctx : AOTExecContext,
  instr : AOTGenInstr,
) -> (Double, Bool, Int)? {
  match instr {
    AOTGenInstr::Yield(expr, next_state) => {
      let value = self.eval_aot_expr(ctx, expr)
      Some((value, false, next_state))
    }
    AOTGenInstr::Return(expr) => {
      let value = self.eval_aot_expr(ctx, expr)
      Some((value, true, ctx.sm.done_state))
    }
    AOTGenInstr::SetLocal(name, expr) => {
      let value = self.eval_aot_expr(ctx, expr)
      let idx = get_aot_field_index(ctx.sm, name)
      if idx < ctx.state_data.length() {
        ctx.state_data[idx] = value
      }
      None
    }
    AOTGenInstr::While(cond, body) => {
      while self.eval_aot_expr(ctx, cond) != 0.0 {
        self.tick()
        match self.peek_error() {
          Some(_) => return Some((0.0, true, ctx.sm.done_state))
          None => ()
        }
        for inner in body {
          match self.execute_aot_instr(ctx, inner) {
            Some(result) => return Some(result)
            None => continue
          }
        }
      }
      None
    }
    AOTGenInstr::Branch(cond, then_body, else_body) => {
      let cond_val = self.eval_aot_expr(ctx, cond)
      let branch = if cond_val != 0.0 { then_body } else { else_body }
      for inner in branch {
        match self.execute_aot_instr(ctx, inner) {
          Some(result) => return Some(result)
          None => continue
        }
      }
      None
    }
    AOTGenInstr::Exec(expr) => {
      let _ = self.eval_aot_expr(ctx, expr)
      None
    }
    AOTGenInstr::Nop => None
  }
}

///|
/// Evaluate an AOT expression.
fn JSInterpreter::eval_aot_expr(
  self : JSInterpreter,
  ctx : AOTExecContext,
  expr : AOTGenExpr,
) -> Double {
  match expr {
    AOTGenExpr::Number(n) => n
    AOTGenExpr::Bool(b) => if b { 1.0 } else { 0.0 }
    AOTGenExpr::Undefined => 0.0
    AOTGenExpr::Var(name) => {
      let idx = get_aot_field_index(ctx.sm, name)
      if idx < ctx.state_data.length() {
        ctx.state_data[idx]
      } else {
        0.0 / 0.0
      }
    }
    AOTGenExpr::Sent => ctx.sent_value
    AOTGenExpr::BinOp(op, left, right) => {
      let l = self.eval_aot_expr(ctx, left)
      let r = self.eval_aot_expr(ctx, right)
      eval_aot_binop(op, l, r)
    }
    AOTGenExpr::UnaryOp(op, operand) => {
      let v = self.eval_aot_expr(ctx, operand)
      eval_aot_unaryop(op, v)
    }
  }
}

///|
/// Get field index for a variable in AOT state machine.
fn get_aot_field_index(sm : AOTGenStateMachine, name : String) -> Int {
  // Layout: [state_num, done, signal_mode, signal_value, params..., locals...]
  let mut idx = aot_idx_params_start
  for p in sm.params {
    if p == name {
      return idx
    }
    idx += 1
  }
  for l in sm.locals {
    if l == name {
      return idx
    }
    idx += 1
  }
  0 // Fallback
}

///|
/// Evaluate binary operation.
fn eval_aot_binop(op : AOTGenBinOp, l : Double, r : Double) -> Double {
  match op {
    AOTGenBinOp::Add => l + r
    AOTGenBinOp::Sub => l - r
    AOTGenBinOp::Mul => l * r
    AOTGenBinOp::Div => l / r
    AOTGenBinOp::Mod => l % r
    AOTGenBinOp::Lt => if l < r { 1.0 } else { 0.0 }
    AOTGenBinOp::Le => if l <= r { 1.0 } else { 0.0 }
    AOTGenBinOp::Gt => if l > r { 1.0 } else { 0.0 }
    AOTGenBinOp::Ge => if l >= r { 1.0 } else { 0.0 }
    AOTGenBinOp::Eq => if l == r { 1.0 } else { 0.0 }
    AOTGenBinOp::Ne => if l != r { 1.0 } else { 0.0 }
    AOTGenBinOp::And => if l != 0.0 && r != 0.0 { 1.0 } else { 0.0 }
    AOTGenBinOp::Or => if l != 0.0 || r != 0.0 { 1.0 } else { 0.0 }
    AOTGenBinOp::BitAnd => (l.to_int().land(r.to_int())).to_double()
    AOTGenBinOp::BitOr => (l.to_int().lor(r.to_int())).to_double()
    AOTGenBinOp::BitXor => (l.to_int().lxor(r.to_int())).to_double()
    AOTGenBinOp::Shl => (l.to_int() << r.to_int()).to_double()
    AOTGenBinOp::Shr => (l.to_int() >> r.to_int()).to_double()
    AOTGenBinOp::Ushr => {
      // Unsigned right shift
      let val = l.to_int()
      let shift_amt = r.to_int().land(0x1f)
      if shift_amt == 0 {
        val.to_double()
      } else if val >= 0 {
        // Positive values: signed >> is same as unsigned
        (val >> shift_amt).to_double()
      } else {
        // Negative values need special handling
        // JS >>> treats as 32-bit unsigned, shifting right fills with 0s
        // Use UInt >> Int which MoonBit supports
        let unsigned = val.reinterpret_as_uint()
        (unsigned >> shift_amt).reinterpret_as_int().to_double()
      }
    }
  }
}

///|
/// Evaluate unary operation.
fn eval_aot_unaryop(op : AOTGenUnaryOp, v : Double) -> Double {
  match op {
    AOTGenUnaryOp::Neg => -v
    AOTGenUnaryOp::Not => if v == 0.0 { 1.0 } else { 0.0 }
    AOTGenUnaryOp::BitNot => v.to_int().lnot().to_double()
  }
}

///|
/// Execute AOT generator throw().
fn JSInterpreter::generator_throw_aot(
  self : JSInterpreter,
  gen_id : Int,
  value : JSValue,
) -> JSValue {
  if gen_id < 0 || gen_id >= self.generators.length() {
    return self.set_error_kind("TypeError", "Invalid generator")
  }

  let state = self.generators[gen_id]
  if state.done {
    // If already done, throw the error
    self.last_error = Some(value)
    return value
  }

  let state_data = state.aot_state_data

  // Set signal mode to throw
  if state_data.length() >= aot_idx_params_start {
    state_data[aot_idx_signal_mode] = aot_signal_throw
    state_data[aot_idx_signal_value] = js_to_f64(value)
    // Call next to process the signal
    return self.generator_next_aot(gen_id, Undefined)
  }

  // Fallback: Set error and mark done
  self.last_error = Some(value)
  state.done = true
  state_data[aot_idx_done] = 1.0
  self.generators[gen_id] = state
  value
}

///|
/// Execute AOT generator return().
fn JSInterpreter::generator_return_aot(
  self : JSInterpreter,
  gen_id : Int,
  value : JSValue,
) -> JSValue {
  if gen_id < 0 || gen_id >= self.generators.length() {
    return self.set_error_kind("TypeError", "Invalid generator")
  }

  let state = self.generators[gen_id]
  if state.done {
    return self.make_iter_result(value, true)
  }

  let state_data = state.aot_state_data

  // Set signal mode to return
  if state_data.length() >= aot_idx_params_start {
    state_data[aot_idx_signal_mode] = aot_signal_return
    state_data[aot_idx_signal_value] = js_to_f64(value)
    // Call next to process the signal
    return self.generator_next_aot(gen_id, Undefined)
  }

  // Fallback: Mark done
  state.done = true
  state_data[aot_idx_done] = 1.0
  self.generators[gen_id] = state

  self.make_iter_result(value, true)
}
