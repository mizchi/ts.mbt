// Constant folding analysis - detect compile-time computable expressions.

///|
/// Result of constant evaluation.
pub(all) enum ConstValue {
  Int(Int)
  Number(Double)
  String_(String)
  Boolean(Bool)
  Null
  Undefined
  NotConst // Cannot be computed at compile time
} derive(Eq, Debug)

///|
/// Check if this value is a compile-time constant.
pub fn ConstValue::is_const(self : ConstValue) -> Bool {
  !(self is NotConst)
}

///|
/// Check if expression is a compile-time constant.
pub fn is_const_expr(expr : @ast.TsExpr) -> Bool {
  eval_const(expr).is_const()
}

///|
/// Evaluate expression at compile time if possible.
pub fn eval_const(expr : @ast.TsExpr) -> ConstValue {
  match expr {
    @ast.TsExpr::IntLit(n) => Int(n)
    @ast.TsExpr::NumberLit(n) => Number(n)
    @ast.TsExpr::StringLit(s) => String_(s)
    @ast.TsExpr::BoolLit(b) => Boolean(b)
    @ast.TsExpr::NullLit => Null
    // Binary operations
    @ast.TsExpr::BinOp(op, left, right) => eval_binop_const(op, left, right)
    // Unary operations
    @ast.TsExpr::UnaryOp(op, operand) => eval_unary_const(op, operand)
    // Parenthesized / sequence
    @ast.TsExpr::Seq(_, right) => eval_const(right)
    // Conditional with constant condition
    @ast.TsExpr::Cond(cond, then_e, else_e) =>
      match eval_const(cond) {
        Boolean(true) => eval_const(then_e)
        Boolean(false) => eval_const(else_e)
        _ => NotConst
      }
    // Template literals with no interpolations
    @ast.TsExpr::TemplateLiteral(parts, exprs) =>
      if exprs.length() == 0 && parts.length() == 1 {
        String_(parts[0])
      } else {
        // Try to fold all parts
        eval_template_const(parts, exprs)
      }
    // Everything else is not constant
    _ => NotConst
  }
}

///|
/// Evaluate binary operation at compile time.
fn eval_binop_const(
  op : @ast.TsBinOp,
  left : @ast.TsExpr,
  right : @ast.TsExpr,
) -> ConstValue {
  let left_val = eval_const(left)
  let right_val = eval_const(right)
  match (left_val, right_val) {
    (NotConst, _) => NotConst
    (_, NotConst) => NotConst
    (Int(a), Int(b)) => eval_int_binop(op, a, b)
    (Number(a), Number(b)) => eval_number_binop(op, a, b)
    (Int(a), Number(b)) => eval_number_binop(op, a.to_double(), b)
    (Number(a), Int(b)) => eval_number_binop(op, a, b.to_double())
    (String_(a), String_(b)) => eval_string_binop(op, a, b)
    (String_(a), Int(b)) =>
      match op {
        @ast.TsBinOp::Add => String_(a + b.to_string())
        _ => NotConst
      }
    (Int(a), String_(b)) =>
      match op {
        @ast.TsBinOp::Add => String_(a.to_string() + b)
        _ => NotConst
      }
    (String_(a), Number(b)) =>
      match op {
        @ast.TsBinOp::Add => String_(a + b.to_string())
        _ => NotConst
      }
    (Number(a), String_(b)) =>
      match op {
        @ast.TsBinOp::Add => String_(a.to_string() + b)
        _ => NotConst
      }
    (Boolean(a), Boolean(b)) => eval_bool_binop(op, a, b)
    _ => NotConst
  }
}

///|
fn eval_int_binop(op : @ast.TsBinOp, a : Int, b : Int) -> ConstValue {
  match op {
    @ast.TsBinOp::Add => Int(a + b)
    @ast.TsBinOp::Sub => Int(a - b)
    @ast.TsBinOp::Mul => Int(a * b)
    @ast.TsBinOp::Div =>
      if b != 0 {
        Number(a.to_double() / b.to_double())
      } else {
        NotConst
      }
    @ast.TsBinOp::Mod => if b != 0 { Int(a % b) } else { NotConst }
    @ast.TsBinOp::BitAnd => Int(a & b)
    @ast.TsBinOp::BitOr => Int(a | b)
    @ast.TsBinOp::BitXor => Int(a ^ b)
    @ast.TsBinOp::Shl => Int(a << b)
    @ast.TsBinOp::Shr => Int(a >> b)
    @ast.TsBinOp::UShr =>
      Int((a.reinterpret_as_uint() >> b).reinterpret_as_int())
    @ast.TsBinOp::BinLt => Boolean(a < b)
    @ast.TsBinOp::BinLe => Boolean(a <= b)
    @ast.TsBinOp::BinGt => Boolean(a > b)
    @ast.TsBinOp::BinGe => Boolean(a >= b)
    @ast.TsBinOp::BinEq | @ast.TsBinOp::AbstractEq => Boolean(a == b)
    @ast.TsBinOp::BinNe | @ast.TsBinOp::AbstractNe => Boolean(a != b)
    _ => NotConst
  }
}

///|
fn eval_number_binop(op : @ast.TsBinOp, a : Double, b : Double) -> ConstValue {
  match op {
    @ast.TsBinOp::Add => Number(a + b)
    @ast.TsBinOp::Sub => Number(a - b)
    @ast.TsBinOp::Mul => Number(a * b)
    @ast.TsBinOp::Div => Number(a / b)
    @ast.TsBinOp::BinLt => Boolean(a < b)
    @ast.TsBinOp::BinLe => Boolean(a <= b)
    @ast.TsBinOp::BinGt => Boolean(a > b)
    @ast.TsBinOp::BinGe => Boolean(a >= b)
    @ast.TsBinOp::BinEq | @ast.TsBinOp::AbstractEq => Boolean(a == b)
    @ast.TsBinOp::BinNe | @ast.TsBinOp::AbstractNe => Boolean(a != b)
    _ => NotConst
  }
}

///|
fn eval_string_binop(op : @ast.TsBinOp, a : String, b : String) -> ConstValue {
  match op {
    @ast.TsBinOp::Add => String_(a + b)
    @ast.TsBinOp::BinLt => Boolean(a < b)
    @ast.TsBinOp::BinLe => Boolean(a <= b)
    @ast.TsBinOp::BinGt => Boolean(a > b)
    @ast.TsBinOp::BinGe => Boolean(a >= b)
    @ast.TsBinOp::BinEq | @ast.TsBinOp::AbstractEq => Boolean(a == b)
    @ast.TsBinOp::BinNe | @ast.TsBinOp::AbstractNe => Boolean(a != b)
    _ => NotConst
  }
}

///|
fn eval_bool_binop(op : @ast.TsBinOp, a : Bool, b : Bool) -> ConstValue {
  match op {
    @ast.TsBinOp::And => Boolean(a && b)
    @ast.TsBinOp::Or => Boolean(a || b)
    @ast.TsBinOp::BinEq | @ast.TsBinOp::AbstractEq => Boolean(a == b)
    @ast.TsBinOp::BinNe | @ast.TsBinOp::AbstractNe => Boolean(a != b)
    _ => NotConst
  }
}

///|
/// Evaluate unary operation at compile time.
fn eval_unary_const(op : @ast.TsUnaryOp, operand : @ast.TsExpr) -> ConstValue {
  let val = eval_const(operand)
  match (op, val) {
    (_, NotConst) => NotConst
    (@ast.TsUnaryOp::Neg, Int(n)) => Int(-n)
    (@ast.TsUnaryOp::Neg, Number(n)) => Number(-n)
    (@ast.TsUnaryOp::Plus, Int(n)) => Int(n)
    (@ast.TsUnaryOp::Plus, Number(n)) => Number(n)
    (@ast.TsUnaryOp::Not, Boolean(b)) => Boolean(!b)
    (@ast.TsUnaryOp::Not, Int(0)) => Boolean(true)
    (@ast.TsUnaryOp::Not, Int(_)) => Boolean(false)
    (@ast.TsUnaryOp::Not, Number(0.0)) => Boolean(true)
    (@ast.TsUnaryOp::Not, Number(_)) => Boolean(false)
    (@ast.TsUnaryOp::Not, String_("")) => Boolean(true)
    (@ast.TsUnaryOp::Not, String_(_)) => Boolean(false)
    (@ast.TsUnaryOp::Not, Null) => Boolean(true)
    (@ast.TsUnaryOp::Not, Undefined) => Boolean(true)
    (@ast.TsUnaryOp::BitwiseNot, Int(n)) => Int(n.lnot())
    (@ast.TsUnaryOp::Typeof, Int(_)) => String_("number")
    (@ast.TsUnaryOp::Typeof, Number(_)) => String_("number")
    (@ast.TsUnaryOp::Typeof, String_(_)) => String_("string")
    (@ast.TsUnaryOp::Typeof, Boolean(_)) => String_("boolean")
    (@ast.TsUnaryOp::Typeof, Null) => String_("object")
    (@ast.TsUnaryOp::Typeof, Undefined) => String_("undefined")
    _ => NotConst
  }
}

///|
/// Evaluate template literal at compile time.
fn eval_template_const(
  parts : Array[String],
  exprs : Array[@ast.TsExpr],
) -> ConstValue {
  let buf = StringBuilder::new()
  for i in 0..<parts.length() {
    buf.write_string(parts[i])
    if i < exprs.length() {
      match eval_const(exprs[i]) {
        Int(n) => buf.write_string(n.to_string())
        Number(n) => buf.write_string(n.to_string())
        String_(s) => buf.write_string(s)
        Boolean(b) => buf.write_string(b.to_string())
        Null => buf.write_string("null")
        Undefined => buf.write_string("undefined")
        NotConst => return NotConst
      }
    }
  }
  String_(buf.to_string())
}

///|
/// Information about constant expressions in a function.
pub(all) struct ConstFoldInfo {
  // Expressions that can be folded (offset -> value)
  foldable : Array[(Int, ConstValue)]
  // Constant variables (name -> value)
  const_vars : Map[String, ConstValue]
}

///|
pub fn ConstFoldInfo::new() -> ConstFoldInfo {
  { foldable: [], const_vars: {} }
}

///|
/// Analyze a function for constant folding opportunities.
pub fn analyze_const_fold(
  func : @ast.TsFunc,
  _source : String,
) -> ConstFoldInfo {
  let info = ConstFoldInfo::new()
  // Collect const declarations
  for stmt in func.body.stmts {
    analyze_stmt_const(stmt, info)
  }
  info
}

///|
fn analyze_stmt_const(stmt : @ast.TsStmt, info : ConstFoldInfo) -> Unit {
  match stmt {
    @ast.TsStmt::Const(binding, _, init) => {
      let val = eval_const(init)
      match val {
        NotConst => ()
        _ => {
          let names : Array[String] = []
          collect_binding_names(binding, names)
          for name in names {
            info.const_vars[name] = val
          }
        }
      }
    }
    @ast.TsStmt::If(_, then_block, else_block) => {
      for s in then_block.stmts {
        analyze_stmt_const(s, info)
      }
      match else_block {
        Some(eb) =>
          for s in eb.stmts {
            analyze_stmt_const(s, info)
          }
        None => ()
      }
    }
    @ast.TsStmt::While(_, body) =>
      for s in body.stmts {
        analyze_stmt_const(s, info)
      }
    @ast.TsStmt::For(_, _, _, body) =>
      for s in body.stmts {
        analyze_stmt_const(s, info)
      }
    @ast.TsStmt::Block(block) =>
      for s in block.stmts {
        analyze_stmt_const(s, info)
      }
    _ => ()
  }
}
