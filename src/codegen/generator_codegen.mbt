// Generator wasm-gc Code Generation
// Generates state machine code for generators.

///|
/// Compile a generator function to wasm-gc.
/// Returns None if the function is not a generator or cannot be AOT compiled.
pub fn compile_generator_func(
  func : @ast.TsFunc,
  state_struct_type_idx : UInt,
) -> GeneratorWasmCode? {
  if not(func.is_generator) {
    return None
  }

  // Analyze the generator
  let analysis = @analysis.analyze_generator(func)
  if not(analysis.compilable) {
    return None
  }

  // Transform to state machine IR
  let sm = transform_to_state_machine(func, analysis)

  // Compile to wasm-gc
  Some(compile_generator(sm, state_struct_type_idx))
}

///|
/// Result of compiling a generator to wasm-gc.
pub struct GeneratorWasmCode {
  /// State struct type definition
  state_struct_type : @core.TypeDef
  /// The next() function type
  next_func_type : @core.TypeDef
  /// The create() function type (returns generator state)
  create_func_type : @core.TypeDef
  /// The next() function code
  next_func_code : @core.Code
  /// The create() function code
  create_func_code : @core.Code
}

///|
/// Compile a generator state machine to wasm-gc instructions.
/// Uses br_table for efficient state dispatch.
pub fn compile_generator(
  sm : GenStateMachine,
  state_struct_type_idx : UInt,
) -> GeneratorWasmCode {
  compile_generator_impl(sm, state_struct_type_idx, true)
}

///|
/// Generate signal check code (for throw/return handling).
/// Returns instructions that check signal_mode and handle accordingly.
fn generate_signal_check(state_struct_type_idx : UInt) -> Array[@core.Instr] {
  let instrs : Array[@core.Instr] = []
  // Check if signal_mode != signal_mode_normal (0)
  // If throw (1): set done, return (signal_value, 1)
  // If return (2): set done, return (signal_value, 1)
  instrs.push(@core.Instr::LocalGet(0U)) // state
  instrs.push(
    @core.Instr::StructGet(state_struct_type_idx, field_idx_signal_mode),
  )
  instrs.push(@core.Instr::I32Const(signal_mode_normal.reinterpret_as_uint()))
  instrs.push(@core.Instr::I32Ne)
  // If signal_mode != 0, handle throw/return
  let handle_signal : Array[@core.Instr] = []
  // Set done = 1
  handle_signal.push(@core.Instr::LocalGet(0U))
  handle_signal.push(@core.Instr::I32Const(1U))
  handle_signal.push(
    @core.Instr::StructSet(state_struct_type_idx, field_idx_done),
  )
  // Reset signal_mode to 0
  handle_signal.push(@core.Instr::LocalGet(0U))
  handle_signal.push(@core.Instr::I32Const(0U))
  handle_signal.push(
    @core.Instr::StructSet(state_struct_type_idx, field_idx_signal_mode),
  )
  // Return (signal_value, 1)
  handle_signal.push(@core.Instr::LocalGet(0U))
  handle_signal.push(
    @core.Instr::StructGet(state_struct_type_idx, field_idx_signal_value),
  )
  handle_signal.push(@core.Instr::I32Const(1U))
  handle_signal.push(@core.Instr::Return)
  instrs.push(@core.Instr::If(@core.BlockType::Empty, handle_signal, []))
  instrs
}

///|
/// Generate next() using br_table for efficient state dispatch.
fn generate_next_instrs_br_table(
  sm : GenStateMachine,
  state_struct_type_idx : UInt,
) -> Array[@core.Instr] {
  let instrs : Array[@core.Instr] = []
  let num_states = sm.states.length()

  // First, check for throw/return signals
  let signal_check = generate_signal_check(state_struct_type_idx)
  for sc in signal_check {
    instrs.push(sc)
  }

  // Structure:
  // block $done (result f64 i32)
  //   block $state_n
  //     ...
  //     block $state_0
  //       local.get 0
  //       struct.get $state 0
  //       br_table $state_0 $state_1 ... $done
  //     end ;; $state_0
  //     <state_0 code>
  //     br $done
  //   end ;; $state_1
  //   ...
  // end ;; $done

  // Build nested blocks for each state
  // We need to build from inside out
  let mut inner : Array[@core.Instr] = []

  // Innermost: br_table dispatch
  inner.push(@core.Instr::LocalGet(0U))
  inner.push(@core.Instr::StructGet(state_struct_type_idx, field_idx_state_num))

  // br_table targets: [0, 1, 2, ..., num_states-1], default=num_states (done)
  let targets : Array[UInt] = []
  for i in 0..<num_states {
    targets.push(i.reinterpret_as_uint())
  }
  let default_target = num_states.reinterpret_as_uint()
  inner.push(@core.Instr::BrTable(targets, default_target))

  // Wrap in blocks from state 0 to state n-1
  for i in 0..<num_states {
    let state = sm.states[i]
    let state_body = generate_state_body(sm, state, state_struct_type_idx)

    // Wrap current inner in a block, then add state code
    let block_inner = inner
    inner = []
    inner.push(@core.Instr::Block(@core.BlockType::Empty, block_inner))

    // Add state code after the block
    for c in state_body {
      inner.push(c)
    }

    // Break to outer done block (depth = num_states - i)
    let done_depth = (num_states - i).reinterpret_as_uint()
    inner.push(@core.Instr::Br(done_depth))
  }

  // Outer done block
  instrs.push(@core.Instr::Block(@core.BlockType::Empty, inner))

  // Default: return (0.0, 1) for done state
  instrs.push(@core.Instr::F64Const(0.0))
  instrs.push(@core.Instr::I32Const(1U))
  instrs
}

///|
/// Compile a generator with if-else chain dispatch (for debugging).
pub fn compile_generator_if_else(
  sm : GenStateMachine,
  state_struct_type_idx : UInt,
) -> GeneratorWasmCode {
  compile_generator_impl(sm, state_struct_type_idx, false)
}

// Signal modes for generator throw/return
// 0 = normal, 1 = throw, 2 = return

///|
let signal_mode_normal : Int = 0

// Used in runtime interpreter_aot_gen.mbt for throw/return

///|
let _signal_mode_throw : Int = 1

///|
let _signal_mode_return : Int = 2

// Field indices in the state struct (after signal support)

///|
let field_idx_state_num : UInt = 0U

///|
let field_idx_done : UInt = 1U

///|
let field_idx_signal_mode : UInt = 2U

///|
let field_idx_signal_value : UInt = 3U

///|
let field_idx_params_start : UInt = 4U

///|
/// Internal implementation with dispatch method selection.
fn compile_generator_impl(
  sm : GenStateMachine,
  state_struct_type_idx : UInt,
  use_br_table : Bool,
) -> GeneratorWasmCode {
  // Build field types for state struct
  // Layout: [state_num, done, signal_mode, signal_value, params..., locals...]
  let struct_fields : Array[@core.FieldType] = []

  // Field 0: State number
  struct_fields.push({
    storage: @core.StorageType::Val(@core.ValType::I32),
    mutable: true,
  })
  // Field 1: Done flag
  struct_fields.push({
    storage: @core.StorageType::Val(@core.ValType::I32),
    mutable: true,
  })
  // Field 2: Signal mode (0=normal, 1=throw, 2=return)
  struct_fields.push({
    storage: @core.StorageType::Val(@core.ValType::I32),
    mutable: true,
  })
  // Field 3: Signal value (for throw/return)
  struct_fields.push({
    storage: @core.StorageType::Val(@core.ValType::F64),
    mutable: true,
  })

  // Field 4+: Params (all f64)
  for _ in sm.params {
    struct_fields.push({
      storage: @core.StorageType::Val(@core.ValType::F64),
      mutable: true,
    })
  }

  // Field 4+num_params+: Locals (all f64)
  for _ in sm.locals {
    struct_fields.push({
      storage: @core.StorageType::Val(@core.ValType::F64),
      mutable: true,
    })
  }
  let state_struct_type = @core.TypeDef::Struct({ fields: struct_fields })

  // State ref type
  let state_ref_type = @core.ValType::Ref(
    @core.RefType::TypeIndex(state_struct_type_idx.reinterpret_as_int()),
    true,
  )

  // next(state: ref $state, sent: f64) -> (value: f64, done: i32)
  let next_func_type = @core.TypeDef::Func({
    params: [state_ref_type, @core.ValType::F64],
    results: [@core.ValType::F64, @core.ValType::I32],
  })

  // create(params...) -> ref $state
  let create_params : Array[@core.ValType] = []
  for _ in sm.params {
    create_params.push(@core.ValType::F64)
  }
  let create_func_type = @core.TypeDef::Func({
    params: create_params,
    results: [state_ref_type],
  })

  // Generate next() function code
  let next_instrs = if use_br_table {
    generate_next_instrs_br_table(sm, state_struct_type_idx)
  } else {
    generate_next_instrs_if_else(sm, state_struct_type_idx)
  }
  let next_func_code : @core.Code = {
    locals: [],
    body: @core.Expr::{ instrs: next_instrs },
    compiled: None,
    max_stack_height: 0,
  }

  // Generate create() function code
  let create_instrs = generate_create_instrs(sm, state_struct_type_idx)
  let create_func_code : @core.Code = {
    locals: [],
    body: @core.Expr::{ instrs: create_instrs },
    compiled: None,
    max_stack_height: 0,
  }
  {
    state_struct_type,
    next_func_type,
    create_func_type,
    next_func_code,
    create_func_code,
  }
}

///|
/// Generate next() using if-else chain (fallback for debugging).
fn generate_next_instrs_if_else(
  sm : GenStateMachine,
  state_struct_type_idx : UInt,
) -> Array[@core.Instr] {
  let instrs : Array[@core.Instr] = []

  // First, check for throw/return signals
  let signal_check = generate_signal_check(state_struct_type_idx)
  for sc in signal_check {
    instrs.push(sc)
  }

  // Build state dispatch using if-else chain
  // Get current state
  instrs.push(@core.Instr::LocalGet(0U)) // state struct
  instrs.push(
    @core.Instr::StructGet(state_struct_type_idx, field_idx_state_num),
  )

  // Build if-else chain for states
  let state_code = build_state_dispatch(sm, state_struct_type_idx, 0)
  for instr in state_code {
    instrs.push(instr)
  }
  instrs
}

///|
/// Build state dispatch code using if-else chain.
fn build_state_dispatch(
  sm : GenStateMachine,
  state_struct_type_idx : UInt,
  state_idx : Int,
) -> Array[@core.Instr] {
  if state_idx >= sm.states.length() {
    // Done state - return (undefined, true)
    return [@core.Instr::F64Const(0.0), @core.Instr::I32Const(1U)]
  }
  let state = sm.states[state_idx]
  let instrs : Array[@core.Instr] = []

  // Generate code for this state
  let state_body = generate_state_body(sm, state, state_struct_type_idx)

  // Generate code for remaining states (else branch)
  let else_code = build_state_dispatch(sm, state_struct_type_idx, state_idx + 1)

  // Build if statement
  // Get state number and compare
  instrs.push(@core.Instr::LocalGet(0U))
  instrs.push(
    @core.Instr::StructGet(state_struct_type_idx, field_idx_state_num),
  )
  instrs.push(@core.Instr::I32Const(state_idx.reinterpret_as_uint()))
  instrs.push(@core.Instr::I32Eq)

  // Multi-value block type for (f64, i32) result
  // For simplicity, use nested blocks to return both values
  instrs.push(@core.Instr::If(@core.BlockType::Empty, state_body, else_code))

  // Default return if no state matched
  instrs.push(@core.Instr::F64Const(0.0))
  instrs.push(@core.Instr::I32Const(1U))
  instrs
}

///|
/// Generate code for a single state.
fn generate_state_body(
  sm : GenStateMachine,
  state : GenState,
  state_struct_type_idx : UInt,
) -> Array[@core.Instr] {
  let instrs : Array[@core.Instr] = []
  for instr in state.body {
    let code = generate_gen_instr(sm, instr, state_struct_type_idx)
    for c in code {
      instrs.push(c)
    }
  }

  // If no explicit return/yield, return done
  if instrs.is_empty() {
    instrs.push(@core.Instr::F64Const(0.0))
    instrs.push(@core.Instr::I32Const(1U))
  }
  instrs
}

///|
/// Generate wasm instructions from GenInstr.
fn generate_gen_instr(
  sm : GenStateMachine,
  instr : GenInstr,
  state_struct_type_idx : UInt,
) -> Array[@core.Instr] {
  match instr {
    GenInstr::Yield(expr, next_state) => {
      let instrs : Array[@core.Instr] = []
      // Set next state
      instrs.push(@core.Instr::LocalGet(0U))
      instrs.push(@core.Instr::I32Const(next_state.reinterpret_as_uint()))
      instrs.push(
        @core.Instr::StructSet(state_struct_type_idx, field_idx_state_num),
      )
      // Return (value, false)
      let expr_code = generate_gen_expr(sm, expr, state_struct_type_idx)
      for c in expr_code {
        instrs.push(c)
      }
      instrs.push(@core.Instr::I32Const(0U)) // done = false
      instrs.push(@core.Instr::Return)
      instrs
    }
    GenInstr::Return(expr) => {
      let instrs : Array[@core.Instr] = []
      // Set done state
      instrs.push(@core.Instr::LocalGet(0U))
      instrs.push(@core.Instr::I32Const(1U))
      instrs.push(@core.Instr::StructSet(state_struct_type_idx, field_idx_done))
      // Return (value, true)
      let expr_code = generate_gen_expr(sm, expr, state_struct_type_idx)
      for c in expr_code {
        instrs.push(c)
      }
      instrs.push(@core.Instr::I32Const(1U)) // done = true
      instrs.push(@core.Instr::Return)
      instrs
    }
    GenInstr::SetLocal(name, expr) => {
      let instrs : Array[@core.Instr] = []
      let field_idx = get_field_index(sm, name)
      instrs.push(@core.Instr::LocalGet(0U))
      let expr_code = generate_gen_expr(sm, expr, state_struct_type_idx)
      for c in expr_code {
        instrs.push(c)
      }
      instrs.push(@core.Instr::StructSet(state_struct_type_idx, field_idx))
      instrs
    }
    GenInstr::While(cond, body) => {
      // Generate loop
      let loop_body : Array[@core.Instr] = []
      // Check condition
      let cond_code = generate_gen_expr(sm, cond, state_struct_type_idx)
      for c in cond_code {
        loop_body.push(c)
      }
      // Convert to i32 for branch
      loop_body.push(@core.Instr::I32TruncF64S)
      loop_body.push(@core.Instr::I32Eqz)
      loop_body.push(@core.Instr::BrIf(1U)) // Exit loop if false
      // Body
      for body_instr in body {
        let body_code = generate_gen_instr(
          sm, body_instr, state_struct_type_idx,
        )
        for c in body_code {
          loop_body.push(c)
        }
      }
      loop_body.push(@core.Instr::Br(0U)) // Continue loop
      [
        @core.Instr::Block(@core.BlockType::Empty, [
          @core.Instr::Loop(@core.BlockType::Empty, loop_body),
        ]),
      ]
    }
    GenInstr::Branch(cond, then_body, else_body) => {
      let instrs : Array[@core.Instr] = []
      let cond_code = generate_gen_expr(sm, cond, state_struct_type_idx)
      for c in cond_code {
        instrs.push(c)
      }
      instrs.push(@core.Instr::I32TruncF64S)
      let then_instrs : Array[@core.Instr] = []
      for ti in then_body {
        let tc = generate_gen_instr(sm, ti, state_struct_type_idx)
        for c in tc {
          then_instrs.push(c)
        }
      }
      let else_instrs : Array[@core.Instr] = []
      for ei in else_body {
        let ec = generate_gen_instr(sm, ei, state_struct_type_idx)
        for c in ec {
          else_instrs.push(c)
        }
      }
      instrs.push(
        @core.Instr::If(@core.BlockType::Empty, then_instrs, else_instrs),
      )
      instrs
    }
    GenInstr::Exec(expr) => {
      let instrs : Array[@core.Instr] = []
      let expr_code = generate_gen_expr(sm, expr, state_struct_type_idx)
      for c in expr_code {
        instrs.push(c)
      }
      instrs.push(@core.Instr::Drop)
      instrs
    }
    GenInstr::Nop => []
    GenInstr::TryCatch(try_body, catch_param, catch_body, finally_body) => {
      // Generate try-catch using wasm TryTable
      // For now, simplified implementation without actual wasm exception handling
      // Just execute try body, and if it completes normally, skip catch
      let instrs : Array[@core.Instr] = []

      // Generate try body instructions
      let try_instrs : Array[@core.Instr] = []
      for ti in try_body {
        let tc = generate_gen_instr(sm, ti, state_struct_type_idx)
        for c in tc {
          try_instrs.push(c)
        }
      }

      // Generate catch body instructions
      let catch_instrs : Array[@core.Instr] = []
      // If catch_param is set, store the exception value
      match catch_param {
        Some(param_name) => {
          let field_idx = get_field_index(sm, param_name)
          // The exception value would be on stack, store it
          catch_instrs.push(@core.Instr::LocalGet(0U))
          catch_instrs.push(@core.Instr::F64Const(0.0)) // Placeholder: exception value
          catch_instrs.push(
            @core.Instr::StructSet(state_struct_type_idx, field_idx),
          )
        }
        None => ()
      }
      for ci in catch_body {
        let cc = generate_gen_instr(sm, ci, state_struct_type_idx)
        for c in cc {
          catch_instrs.push(c)
        }
      }

      // Generate finally body instructions (if present)
      let finally_instrs : Array[@core.Instr] = []
      match finally_body {
        Some(fb) =>
          for fi in fb {
            let fc = generate_gen_instr(sm, fi, state_struct_type_idx)
            for c in fc {
              finally_instrs.push(c)
            }
          }
        None => ()
      }

      // For Phase 3 basic implementation:
      // Use TryTable with CatchAll to catch any exception
      // Label 0 is the outer block (catch handler target)
      let try_table_body : Array[@core.Instr] = []
      for c in try_instrs {
        try_table_body.push(c)
      }

      // Wrap in block $catch_target + try_table
      // Structure:
      // block $done
      //   block $catch_target
      //     try_table (catch_all $catch_target)
      //       <try_body>
      //     end
      //     br $done  ;; normal completion, skip catch
      //   end  ;; $catch_target
      //   <catch_body>
      // end  ;; $done
      // <finally_body>

      let inner_block : Array[@core.Instr] = []
      inner_block.push(
        @core.Instr::TryTable(
          @core.BlockType::Empty,
          [@core.CatchClause::CatchAll(0U)], // catch_all jumps to label 0 (inner block end)
          try_table_body,
        ),
      )
      inner_block.push(@core.Instr::Br(1U)) // Skip catch, jump to outer block end
      let outer_block : Array[@core.Instr] = []
      outer_block.push(@core.Instr::Block(@core.BlockType::Empty, inner_block))
      // Catch handler here
      for c in catch_instrs {
        outer_block.push(c)
      }
      instrs.push(@core.Instr::Block(@core.BlockType::Empty, outer_block))

      // Finally always executes
      for c in finally_instrs {
        instrs.push(c)
      }
      instrs
    }
    GenInstr::Throw(expr) => {
      // For now, throw is implemented as setting signal_mode and returning
      // Full wasm exception support would use @core.Instr::Throw
      let instrs : Array[@core.Instr] = []
      // Set signal_mode = throw (1)
      instrs.push(@core.Instr::LocalGet(0U))
      instrs.push(@core.Instr::I32Const(1U)) // signal_mode_throw
      instrs.push(
        @core.Instr::StructSet(state_struct_type_idx, field_idx_signal_mode),
      )
      // Set signal_value
      instrs.push(@core.Instr::LocalGet(0U))
      let expr_code = generate_gen_expr(sm, expr, state_struct_type_idx)
      for c in expr_code {
        instrs.push(c)
      }
      instrs.push(
        @core.Instr::StructSet(state_struct_type_idx, field_idx_signal_value),
      )
      // Set done
      instrs.push(@core.Instr::LocalGet(0U))
      instrs.push(@core.Instr::I32Const(1U))
      instrs.push(@core.Instr::StructSet(state_struct_type_idx, field_idx_done))
      // Return (0.0, true)
      instrs.push(@core.Instr::F64Const(0.0))
      instrs.push(@core.Instr::I32Const(1U))
      instrs.push(@core.Instr::Return)
      instrs
    }
  }
}

///|
/// Generate wasm instructions from GenExpr.
fn generate_gen_expr(
  sm : GenStateMachine,
  expr : GenExpr,
  state_struct_type_idx : UInt,
) -> Array[@core.Instr] {
  match expr {
    GenExpr::Number(n) => [@core.Instr::F64Const(n)]
    GenExpr::Bool(b) => [@core.Instr::F64Const(if b { 1.0 } else { 0.0 })]
    GenExpr::Str(_) => [@core.Instr::F64Const(0.0)] // Strings not yet supported
    GenExpr::Undefined | GenExpr::Null => [@core.Instr::F64Const(0.0)]
    GenExpr::Var(name) => {
      let field_idx = get_field_index(sm, name)
      [
        @core.Instr::LocalGet(0U),
        @core.Instr::StructGet(state_struct_type_idx, field_idx),
      ]
    }
    GenExpr::BinOp(op, left, right) => {
      let instrs : Array[@core.Instr] = []
      let left_code = generate_gen_expr(sm, left, state_struct_type_idx)
      for c in left_code {
        instrs.push(c)
      }
      let right_code = generate_gen_expr(sm, right, state_struct_type_idx)
      for c in right_code {
        instrs.push(c)
      }
      match op {
        GenBinOp::Add => instrs.push(@core.Instr::F64Add)
        GenBinOp::Sub => instrs.push(@core.Instr::F64Sub)
        GenBinOp::Mul => instrs.push(@core.Instr::F64Mul)
        GenBinOp::Div => instrs.push(@core.Instr::F64Div)
        GenBinOp::Lt => {
          instrs.push(@core.Instr::F64Lt)
          instrs.push(@core.Instr::F64ConvertI32S)
        }
        GenBinOp::Le => {
          instrs.push(@core.Instr::F64Le)
          instrs.push(@core.Instr::F64ConvertI32S)
        }
        GenBinOp::Gt => {
          instrs.push(@core.Instr::F64Gt)
          instrs.push(@core.Instr::F64ConvertI32S)
        }
        GenBinOp::Ge => {
          instrs.push(@core.Instr::F64Ge)
          instrs.push(@core.Instr::F64ConvertI32S)
        }
        GenBinOp::Eq => {
          instrs.push(@core.Instr::F64Eq)
          instrs.push(@core.Instr::F64ConvertI32S)
        }
        GenBinOp::Ne => {
          instrs.push(@core.Instr::F64Ne)
          instrs.push(@core.Instr::F64ConvertI32S)
        }
        _ => instrs.push(@core.Instr::F64Add) // Fallback
      }
      instrs
    }
    GenExpr::UnaryOp(op, operand) => {
      let instrs : Array[@core.Instr] = []
      let operand_code = generate_gen_expr(sm, operand, state_struct_type_idx)
      for c in operand_code {
        instrs.push(c)
      }
      match op {
        GenUnaryOp::Neg => instrs.push(@core.Instr::F64Neg)
        GenUnaryOp::Not => {
          instrs.push(@core.Instr::F64Const(0.0))
          instrs.push(@core.Instr::F64Eq)
          instrs.push(@core.Instr::F64ConvertI32S)
        }
        _ => ()
      }
      instrs
    }
    _ => [@core.Instr::F64Const(0.0)] // Fallback for unsupported expressions
  }
}

///|
/// Get field index for a variable name.
fn get_field_index(sm : GenStateMachine, name : String) -> UInt {
  // Field 0: state_num
  // Field 1: done
  // Field 2: signal_mode
  // Field 3: signal_value
  // Fields 4+: params
  // Fields 4+num_params: locals
  let mut idx = field_idx_params_start
  for p in sm.params {
    if p.name == name {
      return idx
    }
    idx += 1
  }
  for l in sm.locals {
    if l.name == name {
      return idx
    }
    idx += 1
  }
  field_idx_params_start // Fallback
}

///|
/// Generate instructions for the create() function.
fn generate_create_instrs(
  sm : GenStateMachine,
  state_struct_type_idx : UInt,
) -> Array[@core.Instr] {
  let instrs : Array[@core.Instr] = []

  // Build initial field values
  // Layout: [state_num, done, signal_mode, signal_value, params..., locals...]
  let field_values : Array[@core.Instr] = []

  // State = 0
  field_values.push(@core.Instr::I32Const(0U))
  // Done = 0
  field_values.push(@core.Instr::I32Const(0U))
  // Signal mode = 0 (normal)
  field_values.push(@core.Instr::I32Const(0U))
  // Signal value = 0.0
  field_values.push(@core.Instr::F64Const(0.0))

  // Params from arguments
  for i in 0..<sm.params.length() {
    field_values.push(@core.Instr::LocalGet(i.reinterpret_as_uint()))
  }

  // Locals initialized to 0
  for _ in sm.locals {
    field_values.push(@core.Instr::F64Const(0.0))
  }

  // Create struct
  for fv in field_values {
    instrs.push(fv)
  }
  instrs.push(@core.Instr::StructNew(state_struct_type_idx))
  instrs
}

///|
/// Debug: print generated wasm code info.
pub fn GeneratorWasmCode::debug_info(self : GeneratorWasmCode) -> String {
  let mut s = "GeneratorWasmCode:\n"
  s += "  state_struct: \{self.state_struct_type}\n"
  s += "  next_func instrs: \{self.next_func_code.body.instrs.length()}\n"
  s += "  create_func instrs: \{self.create_func_code.body.instrs.length()}\n"
  s
}

// =============================================================================
// AOT Group Compilation
// =============================================================================

///|
/// Result of compiling an AOT group.
pub struct AOTGroupCode {
  /// Group information
  group : @analysis.AOTGroup
  /// Type definitions for the group
  types : Array[@core.TypeDef]
  /// Function codes
  funcs : Array[@core.Code]
  /// Function type indices
  func_types : Array[UInt]
  /// Export descriptors
  exports : Array[(String, UInt)] // (name, func_idx)
  /// Internal function index map (name -> index within group)
  func_map : Map[String, UInt]
}

///|
/// Compile an AOT group to wasm.
/// All functions in the group are compiled together, allowing internal calls.
pub fn compile_aot_group(
  group : @analysis.AOTGroup,
  ts_module : @ast.TsModule,
  base_type_idx : UInt,
) -> AOTGroupCode? {
  let types : Array[@core.TypeDef] = []
  let funcs : Array[@core.Code] = []
  let func_types : Array[UInt] = []
  let exports : Array[(String, UInt)] = []
  let func_map : Map[String, UInt] = {}

  // First pass: assign function indices
  let mut func_idx = 0U
  for name in group.members {
    match find_func(ts_module, name) {
      Some(func) =>
        if func.is_generator {
          // Generator produces 2 functions: create and next
          func_map[name + "_create"] = func_idx
          func_idx += 1
          func_map[name + "_next"] = func_idx
          func_idx += 1
        } else {
          func_map[name] = func_idx
          func_idx += 1
        }
      None => ()
    }
  }

  // Second pass: compile functions
  let mut type_idx = base_type_idx
  for name in group.members {
    match find_func(ts_module, name) {
      Some(func) =>
        if func.is_generator {
          // Compile generator
          let analysis = @analysis.analyze_generator(func)
          if not(analysis.compilable) {
            return None
          }
          let sm = transform_to_state_machine(func, analysis)

          // State struct type
          let state_struct_type_idx = type_idx
          type_idx += 1
          let gen_code = compile_generator_with_calls(
            sm, state_struct_type_idx, func_map,
          )
          types.push(gen_code.state_struct_type)
          types.push(gen_code.create_func_type)
          types.push(gen_code.next_func_type)
          funcs.push(gen_code.create_func_code)
          func_types.push(state_struct_type_idx + 1) // create type
          exports.push((name + "_create", func_map[name + "_create"]))
          funcs.push(gen_code.next_func_code)
          func_types.push(state_struct_type_idx + 2) // next type
          exports.push((name + "_next", func_map[name + "_next"]))
          type_idx += 2 // create and next types
        } else {
          // Compile helper function
          match compile_helper_func(func, func_map, type_idx) {
            Some((func_type, code)) => {
              types.push(func_type)
              funcs.push(code)
              func_types.push(type_idx)
              // Only export if it has external callers
              if group.external_calls.contains(name) {
                exports.push((name, func_map[name]))
              }
              type_idx += 1
            }
            None => return None
          }
        }
      None => return None
    }
  }
  Some({ group, types, funcs, func_types, exports, func_map })
}

///|
/// Find a function by name in the module.
fn find_func(ts_module : @ast.TsModule, name : String) -> @ast.TsFunc? {
  for func in ts_module.funcs {
    if func.name == name {
      return Some(func)
    }
  }
  None
}

///|
/// Compile a generator with support for internal function calls.
fn compile_generator_with_calls(
  sm : GenStateMachine,
  state_struct_type_idx : UInt,
  func_map : Map[String, UInt],
) -> GeneratorWasmCode {
  // For now, use the basic compilation
  // TODO: Replace Call expressions with wasm call instructions using func_map
  let _ = func_map
  compile_generator(sm, state_struct_type_idx)
}

///|
/// Compile a helper function (non-generator) to wasm.
fn compile_helper_func(
  func : @ast.TsFunc,
  func_map : Map[String, UInt],
  type_idx : UInt,
) -> (@core.TypeDef, @core.Code)? {
  // Build function type
  let params : Array[@core.ValType] = []
  for _ in func.params {
    params.push(@core.ValType::F64) // All params as f64 for now
  }
  let results : Array[@core.ValType] = [@core.ValType::F64] // All return f64
  let func_type = @core.TypeDef::Func({ params, results })

  // Build function body
  let instrs = compile_helper_body(func, func_map)
  let code : @core.Code = {
    locals: [],
    body: { instrs, },
    compiled: None,
    max_stack_height: 0,
  }
  let _ = type_idx
  Some((func_type, code))
}

///|
/// Compile a helper function body to wasm instructions.
fn compile_helper_body(
  func : @ast.TsFunc,
  func_map : Map[String, UInt],
) -> Array[@core.Instr] {
  let instrs : Array[@core.Instr] = []

  // Build param map for local access
  let param_map : Map[String, UInt] = {}
  for i, p in func.params {
    param_map[p.name] = i.reinterpret_as_uint()
  }

  // Compile body statements
  for stmt in func.body.stmts {
    let stmt_instrs = compile_helper_stmt(stmt, param_map, func_map)
    for c in stmt_instrs {
      instrs.push(c)
    }
  }

  // Default return
  if instrs.length() == 0 ||
    not(
      match instrs[instrs.length() - 1] {
        @core.Instr::Return => true
        _ => false
      },
    ) {
    instrs.push(@core.Instr::F64Const(0.0))
  }
  instrs
}

///|
fn compile_helper_stmt(
  stmt : @ast.TsStmt,
  param_map : Map[String, UInt],
  func_map : Map[String, UInt],
) -> Array[@core.Instr] {
  match stmt {
    @ast.TsStmt::Return(Some(expr)) => {
      let instrs = compile_helper_expr(expr, param_map, func_map)
      let result : Array[@core.Instr] = []
      for c in instrs {
        result.push(c)
      }
      result.push(@core.Instr::Return)
      result
    }
    @ast.TsStmt::Return(None) =>
      [@core.Instr::F64Const(0.0), @core.Instr::Return]
    @ast.TsStmt::Expr(expr) => {
      let instrs = compile_helper_expr(expr, param_map, func_map)
      let result : Array[@core.Instr] = []
      for c in instrs {
        result.push(c)
      }
      result.push(@core.Instr::Drop)
      result
    }
    _ => []
  }
}

///|
fn compile_helper_expr(
  expr : @ast.TsExpr,
  param_map : Map[String, UInt],
  func_map : Map[String, UInt],
) -> Array[@core.Instr] {
  match expr {
    @ast.TsExpr::NumberLit(n) => [@core.Instr::F64Const(n)]
    @ast.TsExpr::IntLit(n) => [@core.Instr::F64Const(n.to_double())]
    @ast.TsExpr::BoolLit(b) =>
      [@core.Instr::F64Const(if b { 1.0 } else { 0.0 })]
    @ast.TsExpr::Var(name) =>
      match param_map.get(name) {
        Some(idx) => [@core.Instr::LocalGet(idx)]
        None => [@core.Instr::F64Const(0.0)] // Unknown var
      }
    @ast.TsExpr::BinOp(op, left, right) => {
      let instrs : Array[@core.Instr] = []
      let left_instrs = compile_helper_expr(left, param_map, func_map)
      let right_instrs = compile_helper_expr(right, param_map, func_map)
      for c in left_instrs {
        instrs.push(c)
      }
      for c in right_instrs {
        instrs.push(c)
      }
      let wasm_op = match op {
        @ast.TsBinOp::Add => @core.Instr::F64Add
        @ast.TsBinOp::Sub => @core.Instr::F64Sub
        @ast.TsBinOp::Mul => @core.Instr::F64Mul
        @ast.TsBinOp::Div => @core.Instr::F64Div
        _ => @core.Instr::F64Add // Default
      }
      instrs.push(wasm_op)
      instrs
    }
    @ast.TsExpr::Call(name, args) => {
      let instrs : Array[@core.Instr] = []
      // Compile arguments
      for arg in args {
        let arg_instrs = compile_helper_expr(arg, param_map, func_map)
        for c in arg_instrs {
          instrs.push(c)
        }
      }
      // Call function
      match func_map.get(name) {
        Some(func_idx) => instrs.push(@core.Instr::Call(func_idx))
        None => instrs.push(@core.Instr::F64Const(0.0)) // Unknown function
      }
      instrs
    }
    _ => [@core.Instr::F64Const(0.0)]
  }
}

///|
/// Debug string for AOTGroupCode.
pub fn AOTGroupCode::debug_string(self : AOTGroupCode) -> String {
  let mut s = "AOTGroupCode:\n"
  s += "  root: \{self.group.root}\n"
  s += "  members: \{self.group.members}\n"
  s += "  types: \{self.types.length()}\n"
  s += "  funcs: \{self.funcs.length()}\n"
  s += "  exports: \{self.exports}\n"
  s
}
