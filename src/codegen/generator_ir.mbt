// Generator State Machine Intermediate Representation
// Transforms generator functions into state machine IR for wasm-gc compilation.

///|
/// State machine representation of a generator function.
pub struct GenStateMachine {
  /// Function name
  name : String
  /// Parameters that become part of state struct
  params : Array[GenVar]
  /// Local variables that persist across yields
  locals : Array[GenVar]
  /// State handlers (one per state)
  states : Array[GenState]
  /// Initial state index (usually 0)
  initial_state : Int
  /// Done state index
  done_state : Int
} derive(Show)

///|
/// A variable in the generator state struct.
pub struct GenVar {
  name : String
} derive(Show)

///|
/// A state in the generator state machine.
pub struct GenState {
  /// State index
  id : Int
  /// Label for debugging
  label : String
  /// Instructions to execute in this state
  body : Array[GenInstr]
} derive(Show)

///|
/// Instructions in the generator state machine IR.
pub enum GenInstr {
  /// Conditional branch: cond, then_instrs, else_instrs
  Branch(GenExpr, Array[GenInstr], Array[GenInstr])
  /// While loop: cond, body
  While(GenExpr, Array[GenInstr])
  /// Yield value and suspend (value_expr, next_state)
  Yield(GenExpr, Int)
  /// Return value and mark done
  Return(GenExpr)
  /// Set local variable in state struct
  SetLocal(String, GenExpr)
  /// Execute expression (for side effects)
  Exec(GenExpr)
  /// No operation
  Nop
  /// Try-catch block: try_body, catch_param (optional), catch_body, finally_body (optional)
  TryCatch(Array[GenInstr], String?, Array[GenInstr], Array[GenInstr]?)
  /// Throw exception with value
  Throw(GenExpr)
} derive(Show)

///|
/// Expressions in the generator IR (simplified from AST).
pub enum GenExpr {
  /// Literal number
  Number(Double)
  /// Literal boolean
  Bool(Bool)
  /// Literal string
  Str(String)
  /// Undefined (represented as special value)
  Undefined
  /// Null
  Null
  /// Variable reference (will be translated to struct field access)
  Var(String)
  /// Binary operation
  BinOp(GenBinOp, GenExpr, GenExpr)
  /// Unary operation
  UnaryOp(GenUnaryOp, GenExpr)
  /// Function call (name, args)
  Call(String, Array[GenExpr])
  /// Method call (receiver, method_name, args)
  MethodCall(GenExpr, String, Array[GenExpr])
  /// Property access
  PropAccess(GenExpr, String)
  /// Index access
  IndexAccess(GenExpr, GenExpr)
  /// Array literal
  ArrayLit(Array[GenExpr])
  /// Object literal (list of key-value pairs)
  ObjectLit(Array[(String, GenExpr)])
  /// Conditional expression
  Cond(GenExpr, GenExpr, GenExpr)
  /// Raw AST expression (fallback for complex cases)
  Raw(@ast.TsExpr)
} derive(Show)

///|
/// Binary operators in generator IR.
pub enum GenBinOp {
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
  Other(@ast.TsBinOp)
} derive(Show)

///|
/// Unary operators in generator IR.
pub enum GenUnaryOp {
  Neg
  Not
  BitNot
  TypeOf
  Other(@ast.TsUnaryOp)
} derive(Show)

///|
/// Transform a generator function and its analysis into state machine IR.
pub fn transform_to_state_machine(
  func : @ast.TsFunc,
  analysis : @analysis.GeneratorAnalysis,
) -> GenStateMachine {
  // Build params
  let params : Array[GenVar] = []
  for p in func.params {
    params.push({ name: p.name })
  }

  // Build locals from analysis
  let locals : Array[GenVar] = []
  for v in analysis.persisted_vars {
    if not(v.is_param) {
      locals.push({ name: v.name })
    }
  }

  // Build state handlers
  let builder = GenStateBuilder::new(analysis.yield_points)
  builder.build_states(func.body)
  {
    name: func.name,
    params,
    locals,
    states: builder.states,
    initial_state: 0,
    done_state: analysis.state_count - 1,
  }
}

///|
/// Builder for constructing state machine states.
priv struct GenStateBuilder {
  yield_points : Array[@analysis.YieldPoint]
  states : Array[GenState]
  mut next_yield_idx : Int
}

///|
fn GenStateBuilder::new(
  yield_points : Array[@analysis.YieldPoint],
) -> GenStateBuilder {
  { yield_points, states: [], next_yield_idx: 0 }
}

///|
fn GenStateBuilder::build_states(
  self : GenStateBuilder,
  block : @ast.TsBlock,
) -> Unit {
  // State 0: Initial state
  let initial_instrs = self.build_block(block)
  self.states.push({ id: 0, label: "initial", body: initial_instrs })

  // Add done state
  let done_id = self.yield_points.length() + 1
  self.states.push({
    id: done_id,
    label: "done",
    body: [GenInstr::Return(GenExpr::Undefined)],
  })
}

///|
fn GenStateBuilder::build_block(
  self : GenStateBuilder,
  block : @ast.TsBlock,
) -> Array[GenInstr] {
  let instrs : Array[GenInstr] = []
  for stmt in block.stmts {
    let stmt_instrs = self.build_stmt(stmt)
    for instr in stmt_instrs {
      instrs.push(instr)
    }
  }
  instrs
}

///|
fn GenStateBuilder::build_stmt(
  self : GenStateBuilder,
  stmt : @ast.TsStmt,
) -> Array[GenInstr] {
  match stmt {
    @ast.TsStmt::Expr(expr) => self.build_expr_stmt(expr)
    @ast.TsStmt::Return(opt_expr) =>
      match opt_expr {
        Some(e) => [GenInstr::Return(self.build_expr(e))]
        None => [GenInstr::Return(GenExpr::Undefined)]
      }
    @ast.TsStmt::Var(binding, _, init)
    | @ast.TsStmt::Let(binding, _, init)
    | @ast.TsStmt::Const(binding, _, init) => self.build_var_decl(binding, init)
    @ast.TsStmt::Assign(name, expr) =>
      [GenInstr::SetLocal(name, self.build_expr(expr))]
    @ast.TsStmt::If(cond, then_block, else_block) => {
      let cond_expr = self.build_expr(cond)
      let then_instrs = self.build_block(then_block)
      let else_instrs = match else_block {
        Some(eb) => self.build_block(eb)
        None => []
      }
      [GenInstr::Branch(cond_expr, then_instrs, else_instrs)]
    }
    @ast.TsStmt::While(cond, body) => {
      let cond_expr = self.build_expr(cond)
      let body_instrs = self.build_block(body)
      [GenInstr::While(cond_expr, body_instrs)]
    }
    @ast.TsStmt::DoWhile(cond, body) => {
      // do-while: body + while
      let cond_expr = self.build_expr(cond)
      let body_instrs = self.build_block(body)
      // Execute body once, then loop
      let result : Array[GenInstr] = []
      for instr in body_instrs {
        result.push(instr)
      }
      result.push(GenInstr::While(cond_expr, body_instrs))
      result
    }
    @ast.TsStmt::For(init, cond, update, body) =>
      self.build_for_stmt(init, cond, update, body)
    @ast.TsStmt::Block(block) => self.build_block(block)
    @ast.TsStmt::CompoundAssign(name, op, expr) => {
      let bin_op = compound_to_binop(op)
      let new_val = GenExpr::BinOp(
        bin_op,
        GenExpr::Var(name),
        self.build_expr(expr),
      )
      [GenInstr::SetLocal(name, new_val)]
    }
    @ast.TsStmt::Try(try_block, catch_param, catch_block, finally_block) => {
      let try_instrs = self.build_block(try_block)
      // Extract catch parameter name from binding
      let catch_param_name : String? = match catch_param {
        Some(@ast.TsBinding::Ident(name)) => Some(name)
        _ => None
      }
      let catch_instrs = match catch_block {
        Some(cb) => self.build_block(cb)
        None => []
      }
      let finally_instrs = match finally_block {
        Some(fb) => Some(self.build_block(fb))
        None => None
      }
      [
        GenInstr::TryCatch(
          try_instrs, catch_param_name, catch_instrs, finally_instrs,
        ),
      ]
    }
    @ast.TsStmt::Throw(expr) => [GenInstr::Throw(self.build_expr(expr))]
    _ => [GenInstr::Nop]
  }
}

///|
fn GenStateBuilder::build_expr_stmt(
  self : GenStateBuilder,
  expr : @ast.TsExpr,
) -> Array[GenInstr] {
  match expr {
    @ast.TsExpr::Yield(opt_expr) => {
      let yield_expr = match opt_expr {
        Some(e) => self.build_expr(e)
        None => GenExpr::Undefined
      }
      let next_state = self.next_yield_idx + 1
      self.next_yield_idx += 1
      [GenInstr::Yield(yield_expr, next_state)]
    }
    @ast.TsExpr::YieldStar(inner) => {
      // yield* is complex - for now mark as needing special handling
      let yield_expr = self.build_expr(inner)
      let next_state = self.next_yield_idx + 1
      self.next_yield_idx += 1
      [GenInstr::Yield(yield_expr, next_state)]
    }
    _ => [GenInstr::Exec(self.build_expr(expr))]
  }
}

///|
fn GenStateBuilder::build_var_decl(
  self : GenStateBuilder,
  binding : @ast.TsBinding,
  init : @ast.TsExpr,
) -> Array[GenInstr] {
  match binding {
    @ast.TsBinding::Ident(name) =>
      [GenInstr::SetLocal(name, self.build_expr(init))]
    _ => [GenInstr::Exec(self.build_expr(init))]
  }
}

///|
fn GenStateBuilder::build_for_stmt(
  self : GenStateBuilder,
  init : @ast.TsStmt?,
  cond : @ast.TsExpr?,
  update : @ast.TsStmt?,
  body : @ast.TsBlock,
) -> Array[GenInstr] {
  let result : Array[GenInstr] = []

  // Init
  match init {
    Some(s) =>
      for instr in self.build_stmt(s) {
        result.push(instr)
      }
    None => ()
  }

  // Build loop body
  let loop_body : Array[GenInstr] = []
  for instr in self.build_block(body) {
    loop_body.push(instr)
  }

  // Update
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
    None => GenExpr::Bool(true)
  }
  result.push(GenInstr::While(cond_expr, loop_body))
  result
}

///|
fn GenStateBuilder::build_expr(
  self : GenStateBuilder,
  expr : @ast.TsExpr,
) -> GenExpr {
  match expr {
    @ast.TsExpr::NumberLit(n) => GenExpr::Number(n)
    @ast.TsExpr::IntLit(n) => GenExpr::Number(n.to_double())
    @ast.TsExpr::BoolLit(b) => GenExpr::Bool(b)
    @ast.TsExpr::StringLit(s) => GenExpr::Str(s)
    @ast.TsExpr::NullLit => GenExpr::Null
    @ast.TsExpr::Var(name) => GenExpr::Var(name)
    @ast.TsExpr::BinOp(op, left, right) => {
      let gen_op = ast_binop_to_gen(op)
      GenExpr::BinOp(gen_op, self.build_expr(left), self.build_expr(right))
    }
    @ast.TsExpr::UnaryOp(op, operand) => {
      let gen_op = ast_unaryop_to_gen(op)
      GenExpr::UnaryOp(gen_op, self.build_expr(operand))
    }
    @ast.TsExpr::Call(name, args) => {
      let gen_args : Array[GenExpr] = []
      for arg in args {
        gen_args.push(self.build_expr(arg))
      }
      GenExpr::Call(name, gen_args)
    }
    @ast.TsExpr::MethodCall(receiver, meth, args) => {
      let gen_args : Array[GenExpr] = []
      for arg in args {
        gen_args.push(self.build_expr(arg))
      }
      GenExpr::MethodCall(self.build_expr(receiver), meth, gen_args)
    }
    @ast.TsExpr::PropAccess(obj, prop) =>
      GenExpr::PropAccess(self.build_expr(obj), prop)
    @ast.TsExpr::IndexAccess(obj, idx) =>
      GenExpr::IndexAccess(self.build_expr(obj), self.build_expr(idx))
    @ast.TsExpr::ArrayLit(elements) => {
      let gen_elems : Array[GenExpr] = []
      for elem in elements {
        gen_elems.push(self.build_expr(elem))
      }
      GenExpr::ArrayLit(gen_elems)
    }
    @ast.TsExpr::ObjectLit(fields) => {
      let gen_fields : Array[(String, GenExpr)] = []
      for field in fields {
        let (key, value) = field
        gen_fields.push((key, self.build_expr(value)))
      }
      GenExpr::ObjectLit(gen_fields)
    }
    @ast.TsExpr::Cond(cond, then_e, else_e) =>
      GenExpr::Cond(
        self.build_expr(cond),
        self.build_expr(then_e),
        self.build_expr(else_e),
      )
    _ => GenExpr::Raw(expr)
  }
}

///|
fn compound_to_binop(op : @ast.TsCompoundOp) -> GenBinOp {
  match op {
    @ast.TsCompoundOp::AddAssign => GenBinOp::Add
    @ast.TsCompoundOp::SubAssign => GenBinOp::Sub
    @ast.TsCompoundOp::MulAssign => GenBinOp::Mul
    @ast.TsCompoundOp::DivAssign => GenBinOp::Div
    @ast.TsCompoundOp::ModAssign => GenBinOp::Mod
    @ast.TsCompoundOp::BitAndAssign => GenBinOp::BitAnd
    @ast.TsCompoundOp::BitOrAssign => GenBinOp::BitOr
    @ast.TsCompoundOp::BitXorAssign => GenBinOp::BitXor
    @ast.TsCompoundOp::ShlAssign => GenBinOp::Shl
    @ast.TsCompoundOp::ShrAssign => GenBinOp::Shr
    @ast.TsCompoundOp::UShrAssign => GenBinOp::Ushr
    _ => GenBinOp::Add
  }
}

///|
fn ast_binop_to_gen(op : @ast.TsBinOp) -> GenBinOp {
  match op {
    @ast.TsBinOp::Add => GenBinOp::Add
    @ast.TsBinOp::Sub => GenBinOp::Sub
    @ast.TsBinOp::Mul => GenBinOp::Mul
    @ast.TsBinOp::Div => GenBinOp::Div
    @ast.TsBinOp::Mod => GenBinOp::Mod
    @ast.TsBinOp::BinLt => GenBinOp::Lt
    @ast.TsBinOp::BinLe => GenBinOp::Le
    @ast.TsBinOp::BinGt => GenBinOp::Gt
    @ast.TsBinOp::BinGe => GenBinOp::Ge
    @ast.TsBinOp::BinEq | @ast.TsBinOp::AbstractEq => GenBinOp::Eq
    @ast.TsBinOp::BinNe | @ast.TsBinOp::AbstractNe => GenBinOp::Ne
    @ast.TsBinOp::And => GenBinOp::And
    @ast.TsBinOp::Or => GenBinOp::Or
    @ast.TsBinOp::BitAnd => GenBinOp::BitAnd
    @ast.TsBinOp::BitOr => GenBinOp::BitOr
    @ast.TsBinOp::BitXor => GenBinOp::BitXor
    @ast.TsBinOp::Shl => GenBinOp::Shl
    @ast.TsBinOp::Shr => GenBinOp::Shr
    @ast.TsBinOp::UShr => GenBinOp::Ushr
    _ => GenBinOp::Other(op)
  }
}

///|
fn ast_unaryop_to_gen(op : @ast.TsUnaryOp) -> GenUnaryOp {
  match op {
    @ast.TsUnaryOp::Neg => GenUnaryOp::Neg
    @ast.TsUnaryOp::Not => GenUnaryOp::Not
    @ast.TsUnaryOp::BitwiseNot => GenUnaryOp::BitNot
    @ast.TsUnaryOp::Typeof => GenUnaryOp::TypeOf
    _ => GenUnaryOp::Other(op)
  }
}

///|
/// Format GenStateMachine for debugging.
pub fn GenStateMachine::debug_string(self : GenStateMachine) -> String {
  let mut result = "GenStateMachine(\{self.name})\n"
  result += "  params: ["
  for i, p in self.params {
    if i > 0 {
      result += ", "
    }
    result += p.name
  }
  result += "]\n"
  result += "  locals: ["
  for i, l in self.locals {
    if i > 0 {
      result += ", "
    }
    result += l.name
  }
  result += "]\n"
  result += "  states:\n"
  for state in self.states {
    result += "    State \{state.id} (\{state.label}): \{state.body.length()} instrs\n"
  }
  result
}
