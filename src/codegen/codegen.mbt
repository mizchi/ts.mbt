// TypeScript AST -> wasm5 Instr lowering

///|
// / codegenerror
pub suberror CodeGenError {
  CodeGenError(String)
} derive(Show)

///|
// / string (snapshot)
priv struct StringPool {
  // string ->
  strings : Map[String, Int]
  // stringdata (order)
  data : Array[Byte]
}

///|
// / stringcreate
fn StringPool::new() -> StringPool {
  { strings: {}, data: [] }
}

///|
// / currentget
fn StringPool::offset(self : StringPool) -> Int {
  self.data.length()
}

///|
// / stringadd
fn StringPool::add(self : StringPool, s : String) -> Int {
  // existencecheck
  match self.strings.get(s) {
    Some(offset) => offset
    None => {
      let offset = self.data.length()
      self.strings[s] = offset

      // length (4, )
      let len = s.length()
      self.data.push((len & 0xFF).to_byte())
      self.data.push(((len >> 8) & 0xFF).to_byte())
      self.data.push(((len >> 16) & 0xFF).to_byte())
      self.data.push(((len >> 24) & 0xFF).to_byte())

      // stringdata
      for i = 0; i < len; i = i + 1 {
        self.data.push((s[i].to_int() & 0xFF).to_byte())
      }

      // 4
      let total = 4 + len
      let aligned = (total + 3) / 4 * 4
      let padding = aligned - total
      let mut j = 0
      while j < padding {
        self.data.push(b'\x00')
        j += 1
      }
      offset
    }
  }
}

// ============================================
// type metadata (snapshot)
// ============================================

///|
// / @ast.TsType 1 encode
fn encode_type(t : @ast.TsType) -> Byte {
  match t {
    @ast.TsType::Number => b'\x00'
    @ast.TsType::Int => b'\x01'
    @ast.TsType::Boolean => b'\x02'
    @ast.TsType::String_ => b'\x03'
    @ast.TsType::Void => b'\x04'
    @ast.TsType::Any => b'\x05'
    @ast.TsType::Array(_) => b'\x06'
    @ast.TsType::Struct(_, _) => b'\x07'
    @ast.TsType::Func(_, _) => b'\x08'
    @ast.TsType::Named(_) => b'\x09'
  }
}

///|
// / type metadataserialize
fn serialize_type_metadata(module_ : @ast.TsModule) -> Bytes {
  let buf : Array[Byte] = []

  // magic "TSTY"
  buf.push(b'\x54') // T
  buf.push(b'\x53') // S
  buf.push(b'\x54') // T
  buf.push(b'\x59') // Y

  // version
  buf.push(b'\x01')

  // import (u16 LE)
  let import_count = module_.imports.length()
  buf.push((import_count & 0xFF).to_byte())
  buf.push(((import_count >> 8) & 0xFF).to_byte())

  // interface (u16 LE)
  let iface_count = module_.interfaces.length()
  buf.push((iface_count & 0xFF).to_byte())
  buf.push(((iface_count >> 8) & 0xFF).to_byte())

  // export (u16 LE)
  let export_count = module_.funcs.length()
  buf.push((export_count & 0xFF).to_byte())
  buf.push(((export_count >> 8) & 0xFF).to_byte())

  // importarray
  for imp in module_.imports {
    // function
    let name_len = imp.name.length()
    buf.push((name_len & 0xFF).to_byte())
    for i = 0; i < name_len; i = i + 1 {
      buf.push((imp.name[i].to_int() & 0xFF).to_byte())
    }
    let mod_len = imp.module_.length()
    buf.push((mod_len & 0xFF).to_byte())
    for i = 0; i < mod_len; i = i + 1 {
      buf.push((imp.module_[i].to_int() & 0xFF).to_byte())
    }
    // parameter
    buf.push((imp.params.length() & 0xFF).to_byte())
    // parametertype
    for param in imp.params {
      buf.push(encode_type(param.1))
    }
    // return valuetype
    buf.push(encode_type(imp.return_type))
  }

  // interfacearray
  for iface in module_.interfaces {
    // interface
    let name_len = iface.name.length()
    buf.push((name_len & 0xFF).to_byte())
    for i = 0; i < name_len; i = i + 1 {
      buf.push((iface.name[i].to_int() & 0xFF).to_byte())
    }
    // field
    buf.push((iface.fields.length() & 0xFF).to_byte())
    // field
    for field in iface.fields {
      let (field_name, field_type) = field
      let fn_len = field_name.length()
      buf.push((fn_len & 0xFF).to_byte())
      for i = 0; i < fn_len; i = i + 1 {
        buf.push((field_name[i].to_int() & 0xFF).to_byte())
      }
      buf.push(encode_type(field_type))
    }
  }

  // exportarray (function)
  for func in module_.funcs {
    let name_len = func.name.length()
    buf.push((name_len & 0xFF).to_byte())
    for i = 0; i < name_len; i = i + 1 {
      buf.push((func.name[i].to_int() & 0xFF).to_byte())
    }
  }
  Bytes::from_array(buf)
}

// ============================================
// type inference (literal)
// ============================================

///|
// / literaltype()
fn infer_literal_type(expr : @ast.TsExpr) -> @ast.TsType {
  match expr {
    @ast.TsExpr::IntLit(_) => @ast.TsType::Int
    @ast.TsExpr::NumberLit(_) => @ast.TsType::Number
    @ast.TsExpr::BigIntLit(_) => @ast.TsType::Any
    @ast.TsExpr::BoolLit(_) => @ast.TsType::Boolean
    @ast.TsExpr::StringLit(_) => @ast.TsType::String_
    @ast.TsExpr::NullLit => @ast.TsType::Any // null @ast.TsType::Any
    @ast.TsExpr::ArrayHole => @ast.TsType::Any
    @ast.TsExpr::ArrayLit(_) => @ast.TsType::Any // elementtype @ast.TsType::Any
    @ast.TsExpr::Spread(_) => @ast.TsType::Any
    @ast.TsExpr::ComputedProp(_, _) => @ast.TsType::Any
    @ast.TsExpr::ObjectLit(_) => @ast.TsType::Any // objectliteral @ast.TsType::Any
    @ast.TsExpr::Var(_) => @ast.TsType::Any // variablestatement
    @ast.TsExpr::Yield(_) => @ast.TsType::Any
    @ast.TsExpr::YieldStar(_) => @ast.TsType::Any
    @ast.TsExpr::Await(_) => @ast.TsType::Any
    @ast.TsExpr::DynamicImport(_) => @ast.TsType::Any
    @ast.TsExpr::ImportMeta => @ast.TsType::Any
    @ast.TsExpr::Seq(_, right) => infer_literal_type(right)
    @ast.TsExpr::PropAssignExpr(_, _, value) => infer_literal_type(value)
    @ast.TsExpr::IndexAssignExpr(_, _, value) => infer_literal_type(value)
    @ast.TsExpr::CompoundAssignExpr(left, _, _) => infer_literal_type(left)
    @ast.TsExpr::BinOp(op, lhs, _) =>
      // comparisonoperator @ast.TsType::Boolean
      match op {
        @ast.TsBinOp::BinEq
        | @ast.TsBinOp::BinNe
        | @ast.TsBinOp::AbstractEq
        | @ast.TsBinOp::AbstractNe
        | @ast.TsBinOp::BinLt
        | @ast.TsBinOp::BinLe
        | @ast.TsBinOp::BinGt
        | @ast.TsBinOp::BinGe
        | @ast.TsBinOp::Instanceof
        | @ast.TsBinOp::In
        | @ast.TsBinOp::And
        | @ast.TsBinOp::Or
        | @ast.TsBinOp::Coalesce => @ast.TsType::Boolean
        @ast.TsBinOp::Add
        | @ast.TsBinOp::Sub
        | @ast.TsBinOp::Mul
        | @ast.TsBinOp::Div
        | @ast.TsBinOp::Mod
        | @ast.TsBinOp::Pow
        | @ast.TsBinOp::BitAnd
        | @ast.TsBinOp::BitOr
        | @ast.TsBinOp::BitXor
        | @ast.TsBinOp::Shl
        | @ast.TsBinOp::Shr
        | @ast.TsBinOp::UShr => infer_literal_type(lhs) // type
      }
    @ast.TsExpr::UnaryOp(op, e) =>
      match op {
        @ast.TsUnaryOp::Neg | @ast.TsUnaryOp::Plus => infer_literal_type(e)
        @ast.TsUnaryOp::Not => @ast.TsType::Boolean
        @ast.TsUnaryOp::BitwiseNot => @ast.TsType::Number // i32 result
        @ast.TsUnaryOp::Typeof => @ast.TsType::String_
        @ast.TsUnaryOp::Void => @ast.TsType::Any
        @ast.TsUnaryOp::Delete => @ast.TsType::Boolean
        @ast.TsUnaryOp::PreInc
        | @ast.TsUnaryOp::PreDec
        | @ast.TsUnaryOp::PostInc
        | @ast.TsUnaryOp::PostDec => infer_literal_type(e)
      }
    @ast.TsExpr::Call(_, _) => @ast.TsType::Any // functionreturn valuetypestatement
    @ast.TsExpr::CallExpr(_, _) => @ast.TsType::Any
    @ast.TsExpr::Cond(_, then_, _) => infer_literal_type(then_) // then type
    @ast.TsExpr::IndexAccess(_, _) => @ast.TsType::Any // arrayelementtype
    @ast.TsExpr::PropAccess(_, prop) =>
      if prop == "length" {
        @ast.TsType::Int
      } else {
        @ast.TsType::Any
      }
    @ast.TsExpr::New(_, _) => @ast.TsType::Any // type
    @ast.TsExpr::NewExpr(_, _) => @ast.TsType::Any
    @ast.TsExpr::MethodCall(_, _, _) => @ast.TsType::Any // methodreturn valuetype
    @ast.TsExpr::AssignExpr(_, e) => infer_literal_type(e) // assignmentexpressiontypetype
    @ast.TsExpr::AssignPattern(_, e) => infer_literal_type(e)
    @ast.TsExpr::ArrowFunc(_, _, _) => @ast.TsType::Any // function @ast.TsType::Any
    @ast.TsExpr::FuncExpr(_) => @ast.TsType::Any // functionexpression @ast.TsType::Any
  }
}

///|
// / @ast.TsType::Any typeresolve()
fn resolve_any(declared : @ast.TsType, init : @ast.TsExpr) -> @ast.TsType {
  match declared {
    @ast.TsType::Any => infer_literal_type(init)
    _ => declared
  }
}

///|
// / variable
priv struct LocalVar {
  index : UInt
  type_ : @ast.TsType
}

///|
// / codegen
priv struct CodeGenCtx {
  // variable ( -> )
  locals : Map[String, LocalVar]
  // variabletype ()
  local_types : Array[@ast.TsType]
  // variable
  mut next_local : UInt
  // function ( -> )
  funcs : Map[String, UInt]
  // interface ( -> field)
  interfaces : Map[String, Array[(String, @ast.TsType)]]
  // importfunctiontype ( -> parametertypereturn valuetype)
  import_types : Map[String, (Array[@ast.TsType], @ast.TsType)]
  // generate
  instrs : Array[@core.Instr]
  // loopnest (break/continue )
  mut loop_depth : Int
  // string
  string_pool : StringPool
  // function
  builtins_used : Map[String, Bool]
}

///|
// / create
fn CodeGenCtx::new(
  funcs : Map[String, UInt],
  interfaces : Map[String, Array[(String, @ast.TsType)]],
  import_types : Map[String, (Array[@ast.TsType], @ast.TsType)],
  string_pool : StringPool,
  builtins_used : Map[String, Bool],
) -> CodeGenCtx {
  {
    locals: {},
    local_types: [],
    next_local: 0,
    funcs,
    interfaces,
    import_types,
    instrs: [],
    loop_depth: 0,
    string_pool,
    builtins_used,
  }
}

///|
// / variableadd
fn CodeGenCtx::add_local(
  self : CodeGenCtx,
  name : String,
  type_ : @ast.TsType,
) -> UInt {
  let idx = self.next_local
  self.locals[name] = { index: idx, type_ }
  self.local_types.push(type_)
  self.next_local += 1
  idx
}

///|
// / add(resolve)
fn CodeGenCtx::add_temp_local(self : CodeGenCtx, type_ : @ast.TsType) -> UInt {
  let idx = self.next_local
  self.local_types.push(type_)
  self.next_local += 1
  idx
}

///|
// / variablelookup
fn CodeGenCtx::get_local(self : CodeGenCtx, name : String) -> LocalVar? {
  self.locals.get(name)
}

///|
// / add
fn CodeGenCtx::emit(self : CodeGenCtx, instr : @core.Instr) -> Unit {
  self.instrs.push(instr)
}

// ============================================
// typeconversion
// ============================================

///|
/// @ast.TsType → ValType
fn ts_type_to_valtype(t : @ast.TsType) -> @core.ValType {
  match t {
    @ast.TsType::Number => F64
    @ast.TsType::Int => I32
    @ast.TsType::Boolean => I32
    @ast.TsType::String_ => I32 // string
    @ast.TsType::Array(_) => I32 // array
    @ast.TsType::Named(_) => I32 // struct reference
    @ast.TsType::Void => I32 // void
    _ => F64 // f64
  }
}

///|
// / @ast.TsType f64
fn is_f64_type(t : @ast.TsType) -> Bool {
  match t {
    @ast.TsType::Number => true
    _ => false
  }
}

///|
// / expressiontype
fn infer_type(ctx : CodeGenCtx, expr : @ast.TsExpr) -> @ast.TsType {
  match expr {
    @ast.TsExpr::NumberLit(_) => @ast.TsType::Number
    @ast.TsExpr::IntLit(_) => @ast.TsType::Int
    @ast.TsExpr::BigIntLit(_) => @ast.TsType::Any
    @ast.TsExpr::BoolLit(_) => @ast.TsType::Boolean
    @ast.TsExpr::StringLit(_) => @ast.TsType::String_
    @ast.TsExpr::NullLit => @ast.TsType::Any // null @ast.TsType::Any
    @ast.TsExpr::ArrayHole => @ast.TsType::Any
    @ast.TsExpr::Spread(_) => @ast.TsType::Any
    @ast.TsExpr::ComputedProp(_, _) => @ast.TsType::Any
    @ast.TsExpr::ObjectLit(_) => @ast.TsType::Any // objectliteral @ast.TsType::Any
    @ast.TsExpr::Seq(_, right) => infer_type(ctx, right)
    @ast.TsExpr::PropAssignExpr(_, _, value) => infer_type(ctx, value)
    @ast.TsExpr::IndexAssignExpr(_, _, value) => infer_type(ctx, value)
    @ast.TsExpr::CompoundAssignExpr(left, _, _) => infer_type(ctx, left)
    @ast.TsExpr::Yield(_) => @ast.TsType::Any
    @ast.TsExpr::YieldStar(_) => @ast.TsType::Any
    @ast.TsExpr::Await(_) => @ast.TsType::Any
    @ast.TsExpr::DynamicImport(_) => @ast.TsType::Any
    @ast.TsExpr::ImportMeta => @ast.TsType::Any
    @ast.TsExpr::Var(name) =>
      match ctx.get_local(name) {
        Some(local_var) => local_var.type_
        None => @ast.TsType::Number
      }
    @ast.TsExpr::BinOp(op, left, right) =>
      match op {
        // comparisonoperator @ast.TsType::Boolean
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
        // operator @ast.TsType::Boolean
        @ast.TsBinOp::And | @ast.TsBinOp::Or | @ast.TsBinOp::Coalesce =>
          @ast.TsType::Boolean
        // @ast.TsBinOp::Add: stringcheck
        @ast.TsBinOp::Add => {
          let left_t = infer_type(ctx, left)
          let right_t = infer_type(ctx, right)
          if left_t == @ast.TsType::String_ || right_t == @ast.TsType::String_ {
            @ast.TsType::String_
          } else {
            left_t
          }
        }
        // operatortype
        _ => infer_type(ctx, left)
      }
    @ast.TsExpr::UnaryOp(op, operand) =>
      match op {
        @ast.TsUnaryOp::Neg | @ast.TsUnaryOp::Plus => infer_type(ctx, operand)
        @ast.TsUnaryOp::Not => @ast.TsType::Boolean
        @ast.TsUnaryOp::BitwiseNot => @ast.TsType::Number
        @ast.TsUnaryOp::Typeof => @ast.TsType::String_
        @ast.TsUnaryOp::Void => @ast.TsType::Any
        @ast.TsUnaryOp::Delete => @ast.TsType::Boolean
        @ast.TsUnaryOp::PreInc
        | @ast.TsUnaryOp::PreDec
        | @ast.TsUnaryOp::PostInc
        | @ast.TsUnaryOp::PostDec => infer_type(ctx, operand)
      }
    @ast.TsExpr::Call(_, _) => @ast.TsType::Number // functionreturn valuetypeget
    @ast.TsExpr::CallExpr(_, _) => @ast.TsType::Number
    @ast.TsExpr::Cond(_, then_expr, _) => infer_type(ctx, then_expr)
    @ast.TsExpr::ArrayLit(elements) =>
      if elements.length() > 0 {
        @ast.TsType::Array(infer_type(ctx, elements[0]))
      } else {
        @ast.TsType::Array(@ast.TsType::Number)
      }
    @ast.TsExpr::IndexAccess(arr, _) =>
      match infer_type(ctx, arr) {
        @ast.TsType::Array(elem_type) => elem_type
        _ => @ast.TsType::Number
      }
    @ast.TsExpr::PropAccess(_, prop) =>
      if prop == "length" {
        @ast.TsType::Int
      } else {
        @ast.TsType::Number
      }
    @ast.TsExpr::New(_, _) => @ast.TsType::Array(@ast.TsType::Number) // new Array<T>() → @ast.TsType::Array(T)
    @ast.TsExpr::NewExpr(_, _) => @ast.TsType::Any
    @ast.TsExpr::MethodCall(receiver, method_name, _) => {
      let recv_type = infer_type(ctx, receiver)
      match recv_type {
        @ast.TsType::String_ =>
          match method_name {
            "charAt" => @ast.TsType::String_ // charAt returns string (single char)
            "charCodeAt" => @ast.TsType::Int // charCodeAt returns int
            "substring" => @ast.TsType::String_ // substring returns string
            "concat" => @ast.TsType::String_ // concat returns string
            _ => @ast.TsType::Number
          }
        @ast.TsType::Array(_) =>
          match method_name {
            "push" => @ast.TsType::Int // push returns new length
            "pop" => @ast.TsType::Number // pop returns element
            _ => @ast.TsType::Number
          }
        _ => @ast.TsType::Number
      }
    }
    @ast.TsExpr::AssignExpr(_, e) => infer_type(ctx, e) // assignmentexpressiontypetype
    @ast.TsExpr::AssignPattern(_, e) => infer_type(ctx, e)
    @ast.TsExpr::ArrowFunc(_, _, _) => @ast.TsType::Any // function @ast.TsType::Any
    @ast.TsExpr::FuncExpr(_) => @ast.TsType::Any // functionexpression @ast.TsType::Any
  }
}

///|
// / elementget ()
fn element_size(t : @ast.TsType) -> Int {
  match t {
    @ast.TsType::Number => 8 // f64 = 8 bytes
    @ast.TsType::Int => 4 // i32 = 4 bytes
    @ast.TsType::Boolean => 4 // i32 = 4 bytes
    @ast.TsType::String_ => 4 // = 4 bytes
    @ast.TsType::Array(_) => 4 // = 4 bytes
    @ast.TsType::Named(_) => 4 // struct = 4 bytes
    @ast.TsType::Struct(_, _) => 4 // struct = 4 bytes
    _ => 8
  }
}

///|
// / structcompute
fn struct_size(fields : Array[(String, @ast.TsType)]) -> Int {
  let mut size = 0
  for i = 0; i < fields.length(); i = i + 1 {
    let (_, field_type) = fields[i]
    size += element_size(field_type)
  }
  size
}

///|
// / structfieldcompute
fn field_offset(
  fields : Array[(String, @ast.TsType)],
  field_name : String,
) -> Int? {
  let mut offset = 0
  for i = 0; i < fields.length(); i = i + 1 {
    let (name, field_type) = fields[i]
    if name == field_name {
      return Some(offset)
    }
    offset += element_size(field_type)
  }
  None
}

///|
// / structfieldtypeget
fn field_type(
  fields : Array[(String, @ast.TsType)],
  field_name : String,
) -> @ast.TsType? {
  for i = 0; i < fields.length(); i = i + 1 {
    let (name, field_type) = fields[i]
    if name == field_name {
      return Some(field_type)
    }
  }
  None
}

// ============================================
// expressioncodegen
// ============================================

///|
// / expression
fn compile_expr(
  ctx : CodeGenCtx,
  expr : @ast.TsExpr,
  expected_type : @ast.TsType,
) -> Unit raise CodeGenError {
  match expr {
    @ast.TsExpr::NumberLit(n) =>
      if is_f64_type(expected_type) {
        ctx.emit(F64Const(n))
      } else {
        // i32
        ctx.emit(I32Const(n.to_int().reinterpret_as_uint()))
      }
    @ast.TsExpr::IntLit(i) =>
      if is_f64_type(expected_type) {
        ctx.emit(F64Const(i.to_double()))
      } else {
        ctx.emit(I32Const(i.reinterpret_as_uint()))
      }
    @ast.TsExpr::BigIntLit(_) =>
      raise CodeGenError(
        "BigInt is not supported in Wasm compiler (use interpreter)",
      )
    @ast.TsExpr::BoolLit(b) => ctx.emit(I32Const(if b { 1U } else { 0U }))
    @ast.TsExpr::StringLit(s) => {
      // stringaddget (snapshotexpression)
      let offset = ctx.string_pool.add(s)
      // datasection
      ctx.emit(I32Const(offset.reinterpret_as_uint()))
    }
    @ast.TsExpr::Var(name) =>
      match ctx.get_local(name) {
        Some(local_var) => ctx.emit(LocalGet(local_var.index))
        None => raise CodeGenError("Undefined variable: \{name}")
      }
    @ast.TsExpr::Yield(_) =>
      raise CodeGenError(
        "yield is not supported in Wasm compiler (use interpreter)",
      )
    @ast.TsExpr::YieldStar(_) =>
      raise CodeGenError(
        "yield* is not supported in Wasm compiler (use interpreter)",
      )
    @ast.TsExpr::Await(_) =>
      raise CodeGenError(
        "await is not supported in Wasm compiler (use interpreter)",
      )
    @ast.TsExpr::DynamicImport(_) =>
      raise CodeGenError(
        "dynamic import is not supported in Wasm compiler (use interpreter)",
      )
    @ast.TsExpr::ImportMeta =>
      raise CodeGenError(
        "import.meta is not supported in Wasm compiler (use interpreter)",
      )
    @ast.TsExpr::Seq(_, _) =>
      raise CodeGenError(
        "comma operator is not supported in Wasm compiler (use interpreter)",
      )
    @ast.TsExpr::PropAssignExpr(obj, prop, value) =>
      compile_prop_assign_expr(ctx, obj, prop, value)
    @ast.TsExpr::IndexAssignExpr(arr, index, value) =>
      compile_index_assign_expr(ctx, arr, index, value)
    @ast.TsExpr::CompoundAssignExpr(left, op, right) =>
      compile_compound_assign_expr(ctx, left, op, right)
    @ast.TsExpr::BinOp(op, left, right) =>
      compile_binop(ctx, op, left, right, expected_type)
    @ast.TsExpr::UnaryOp(op, operand) =>
      compile_unaryop(ctx, op, operand, expected_type)
    @ast.TsExpr::Call(name, args) =>
      compile_call(ctx, name, args, expected_type)
    @ast.TsExpr::CallExpr(_, _) =>
      raise CodeGenError("call expression is not supported in Wasm compiler")
    @ast.TsExpr::Cond(cond, then_expr, else_expr) => {
      // condition
      compile_expr(ctx, cond, @ast.TsType::Boolean)
      // then
      let then_ctx : CodeGenCtx = {
        locals: ctx.locals,
        local_types: ctx.local_types,
        next_local: ctx.next_local,
        funcs: ctx.funcs,
        interfaces: ctx.interfaces,
        import_types: ctx.import_types,
        instrs: [],
        loop_depth: ctx.loop_depth,
        string_pool: ctx.string_pool,
        builtins_used: ctx.builtins_used,
      }
      compile_expr(then_ctx, then_expr, expected_type)
      // else
      let else_ctx : CodeGenCtx = {
        locals: ctx.locals,
        local_types: ctx.local_types,
        next_local: ctx.next_local,
        funcs: ctx.funcs,
        interfaces: ctx.interfaces,
        import_types: ctx.import_types,
        instrs: [],
        loop_depth: ctx.loop_depth,
        string_pool: ctx.string_pool,
        builtins_used: ctx.builtins_used,
      }
      compile_expr(else_ctx, else_expr, expected_type)
      // If expressiongenerate
      let result_type = ts_type_to_valtype(expected_type)
      ctx.emit(If(Value(result_type), then_ctx.instrs, else_ctx.instrs))
    }
    @ast.TsExpr::Spread(_) =>
      raise CodeGenError(
        "Spread is not supported in Wasm compiler (use interpreter)",
      )
    @ast.TsExpr::ComputedProp(_, _) =>
      raise CodeGenError(
        "ComputedProp is not supported in Wasm compiler (use interpreter)",
      )
    @ast.TsExpr::ArrayLit(elements) =>
      compile_array_lit(ctx, elements, expected_type)
    @ast.TsExpr::IndexAccess(arr, index) =>
      compile_index_access(ctx, arr, index, expected_type)
    @ast.TsExpr::PropAccess(obj, prop) =>
      compile_prop_access(ctx, obj, prop, expected_type)
    @ast.TsExpr::New(type_name, args) =>
      compile_new_expr(ctx, type_name, args, expected_type)
    @ast.TsExpr::NewExpr(_, _) =>
      raise CodeGenError("new expression is not supported in Wasm compiler")
    @ast.TsExpr::MethodCall(receiver, method_name, args) =>
      compile_method_call(ctx, receiver, method_name, args, expected_type)
    // Wasm(interpreter)
    @ast.TsExpr::NullLit => ctx.emit(I32Const(0U)) // null = 0
    @ast.TsExpr::ArrayHole => ctx.emit(I32Const(0U))
    @ast.TsExpr::ObjectLit(_) =>
      raise CodeGenError(
        "ObjectLit is not supported in Wasm compiler (use interpreter)",
      )
    @ast.TsExpr::AssignExpr(name, value) =>
      match ctx.get_local(name) {
        Some(lvar) => {
          compile_expr(ctx, value, lvar.type_)
          ctx.emit(LocalTee(lvar.index))
        }
        None => raise CodeGenError("Undefined variable: \{name}")
      }
    @ast.TsExpr::AssignPattern(_, _) =>
      raise CodeGenError(
        "Destructuring assignment is not supported in Wasm compiler (use interpreter)",
      )
    @ast.TsExpr::ArrowFunc(_, _, _) =>
      raise CodeGenError(
        "ArrowFunc is not supported in Wasm compiler (use interpreter)",
      )
    @ast.TsExpr::FuncExpr(_) =>
      raise CodeGenError(
        "FuncExpr is not supported in Wasm compiler (use interpreter)",
      )
  }
}

///|
// / arrayliteral
fn compile_array_lit(
  ctx : CodeGenCtx,
  elements : Array[@ast.TsExpr],
  expected_type : @ast.TsType,
) -> Unit raise CodeGenError {
  let elem_type = match expected_type {
    @ast.TsType::Array(t) => t
    _ => @ast.TsType::Number
  }
  let elem_sz = element_size(elem_type)
  let length = elements.length()

  // : 4 (length) + length * elem_size
  // variable 0 =
  ctx.emit(GlobalGet(0U)) // currentget

  // length
  ctx.emit(GlobalGet(0U))
  ctx.emit(I32Const(length.reinterpret_as_uint()))
  ctx.emit(I32Store(2U, 0U, 0U))

  // element
  for i, elem in elements {
    match elem {
      @ast.TsExpr::Spread(_) =>
        raise CodeGenError(
          "Spread is not supported in Wasm compiler (use interpreter)",
        )
      _ => ()
    }
    ctx.emit(GlobalGet(0U))
    ctx.emit(I32Const((4 + i * elem_sz).reinterpret_as_uint()))
    ctx.emit(I32Add)
    compile_expr(ctx, elem, elem_type)
    if is_f64_type(elem_type) {
      ctx.emit(F64Store(3U, 0U, 0U))
    } else {
      ctx.emit(I32Store(2U, 0U, 0U))
    }
  }
  ctx.emit(GlobalGet(0U))
  ctx.emit(I32Const((4 + length * elem_sz).reinterpret_as_uint()))
  ctx.emit(I32Add)
  ctx.emit(GlobalSet(0U))
}

///|
// / array
fn compile_index_access(
  ctx : CodeGenCtx,
  arr : @ast.TsExpr,
  index : @ast.TsExpr,
  expected_type : @ast.TsType,
) -> Unit raise CodeGenError {
  let arr_type = infer_type(ctx, arr)
  let elem_type = match arr_type {
    @ast.TsType::Array(t) => t
    _ => expected_type
  }
  let elem_sz = element_size(elem_type)

  // compute: arr + 4 + index * elem_size
  compile_expr(ctx, arr, arr_type) // array
  ctx.emit(I32Const(4U)) // lengthfield
  ctx.emit(I32Add)
  compile_expr(ctx, index, @ast.TsType::Int)
  ctx.emit(I32Const(elem_sz.reinterpret_as_uint()))
  ctx.emit(I32Mul)
  ctx.emit(I32Add)
  if is_f64_type(elem_type) {
    ctx.emit(F64Load(3U, 0U, 0U))
  } else {
    ctx.emit(I32Load(2U, 0U, 0U))
  }
}

///|
// / property
fn compile_prop_access(
  ctx : CodeGenCtx,
  obj : @ast.TsExpr,
  prop : String,
  _expected_type : @ast.TsType,
) -> Unit raise CodeGenError {
  let obj_type = infer_type(ctx, obj)

  // array/string length property
  match obj_type {
    @ast.TsType::Array(_) =>
      if prop == "length" {
        compile_expr(ctx, obj, obj_type)
        ctx.emit(I32Load(2U, 0U, 0U)) // 4 = length
        return
      }
    @ast.TsType::String_ =>
      if prop == "length" {
        compile_expr(ctx, obj, obj_type)
        ctx.emit(I32Load(2U, 0U, 0U)) // 4 = length
        return
      }
    @ast.TsType::Named(type_name) =>
      // structfield
      match ctx.interfaces.get(type_name) {
        Some(fields) =>
          match field_offset(fields, prop) {
            Some(offset) => {
              compile_expr(ctx, obj, obj_type) // struct
              ctx.emit(I32Const(offset.reinterpret_as_uint()))
              ctx.emit(I32Add)
              // fieldtype
              match field_type(fields, prop) {
                Some(@ast.TsType::Number) => ctx.emit(F64Load(3U, 0U, 0U))
                Some(_) => ctx.emit(I32Load(2U, 0U, 0U))
                None => raise CodeGenError("Field not found: \{prop}")
              }
              return
            }
            None => ()
          }
        None => ()
      }
    _ => ()
  }
  raise CodeGenError("Unknown property: \{prop}")
}

///|
// / new expression
fn compile_new_expr(
  ctx : CodeGenCtx,
  type_name : String,
  args : Array[@ast.TsExpr],
  _expected_type : @ast.TsType,
) -> Unit raise CodeGenError {
  if type_name == "Array" {
    // new Array<T>(size)
    let elem_type = match _expected_type {
      @ast.TsType::Array(t) => t
      _ => @ast.TsType::Number
    }
    let elem_sz = element_size(elem_type)
    if args.length() < 1 {
      raise CodeGenError("Array constructor requires size argument")
    }

    // get
    compile_expr(ctx, args[0], @ast.TsType::Int)
    let size_local = ctx.add_local("__array_size__", @ast.TsType::Int)
    ctx.emit(LocalSet(size_local))

    // currentarray
    ctx.emit(GlobalGet(0U))

    // length
    ctx.emit(GlobalGet(0U))
    ctx.emit(LocalGet(size_local))
    ctx.emit(I32Store(2U, 0U, 0U))

    // : 4 + size * elem_size
    ctx.emit(GlobalGet(0U))
    ctx.emit(I32Const(4U))
    ctx.emit(I32Add)
    ctx.emit(LocalGet(size_local))
    ctx.emit(I32Const(elem_sz.reinterpret_as_uint()))
    ctx.emit(I32Mul)
    ctx.emit(I32Add)
    ctx.emit(GlobalSet(0U))
  } else {
    // struct new
    match ctx.interfaces.get(type_name) {
      Some(fields) => {
        let size = struct_size(fields)

        // currentstruct
        ctx.emit(GlobalGet(0U))
        ctx.emit(GlobalGet(0U))
        ctx.emit(I32Const(size.reinterpret_as_uint()))
        ctx.emit(I32Add)
        ctx.emit(GlobalSet(0U))
      }
      None => raise CodeGenError("Unknown constructor: \{type_name}")
    }
  }
}

///|
// / method
fn compile_method_call(
  ctx : CodeGenCtx,
  receiver : @ast.TsExpr,
  method_name : String,
  args : Array[@ast.TsExpr],
  _expected_type : @ast.TsType,
) -> Unit raise CodeGenError {
  let recv_type = infer_type(ctx, receiver)
  match recv_type {
    @ast.TsType::String_ =>
      compile_string_method(ctx, receiver, method_name, args)
    @ast.TsType::Array(_) =>
      compile_array_method(ctx, receiver, method_name, args, recv_type)
    _ => raise CodeGenError("Cannot call method on type: \{recv_type}")
  }
}

///|
// / stringmethod
fn compile_string_method(
  ctx : CodeGenCtx,
  receiver : @ast.TsExpr,
  method_name : String,
  args : Array[@ast.TsExpr],
) -> Unit raise CodeGenError {
  match method_name {
    "charCodeAt" => {
      // str.charCodeAt(index) -> str[4 + index] (1load)
      if args.length() < 1 {
        raise CodeGenError("charCodeAt requires 1 argument")
      }
      compile_expr(ctx, receiver, @ast.TsType::String_) // string
      ctx.emit(I32Const(4U)) // lengthfield
      ctx.emit(I32Add)
      compile_expr(ctx, args[0], @ast.TsType::Int)
      ctx.emit(I32Add)
      ctx.emit(I32Load8U(0U, 0U, 0U)) // 1load ()
    }
    "charAt" => {
      // str.charAt(index) -> 1statementstringcreate
      if args.length() < 1 {
        raise CodeGenError("charAt requires 1 argument")
      }
      // statementget
      compile_expr(ctx, receiver, @ast.TsType::String_)
      ctx.emit(I32Const(4U))
      ctx.emit(I32Add)
      compile_expr(ctx, args[0], @ast.TsType::Int)
      ctx.emit(I32Add)
      ctx.emit(I32Load8U(0U, 0U, 0U))
      let char_local = ctx.add_local("__char__", @ast.TsType::Int)
      ctx.emit(LocalSet(char_local))

      // stringcreate: [length=1][char]
      ctx.emit(GlobalGet(0U)) // result

      // length
      ctx.emit(GlobalGet(0U))
      ctx.emit(I32Const(1U)) // length = 1
      ctx.emit(I32Store(2U, 0U, 0U))

      // statement
      ctx.emit(GlobalGet(0U))
      ctx.emit(I32Const(4U))
      ctx.emit(I32Add)
      ctx.emit(LocalGet(char_local))
      ctx.emit(I32Store8(0U, 0U, 0U))

      // (8)
      ctx.emit(GlobalGet(0U))
      ctx.emit(I32Const(8U))
      ctx.emit(I32Add)
      ctx.emit(GlobalSet(0U))
    }
    "substring" => {
      // str.substring(start, end) -> string
      if args.length() < 2 {
        raise CodeGenError("substring requires 2 arguments")
      }
      // argument
      compile_expr(ctx, args[0], @ast.TsType::Int)
      let start_local = ctx.add_local("__substr_start__", @ast.TsType::Int)
      ctx.emit(LocalSet(start_local))
      compile_expr(ctx, args[1], @ast.TsType::Int)
      let end_local = ctx.add_local("__substr_end__", @ast.TsType::Int)
      ctx.emit(LocalSet(end_local))

      // lengthcompute
      ctx.emit(LocalGet(end_local))
      ctx.emit(LocalGet(start_local))
      ctx.emit(I32Sub)
      let len_local = ctx.add_local("__substr_len__", @ast.TsType::Int)
      ctx.emit(LocalSet(len_local))

      // string
      ctx.emit(GlobalGet(0U))

      // length
      ctx.emit(GlobalGet(0U))
      ctx.emit(LocalGet(len_local))
      ctx.emit(I32Store(2U, 0U, 0U))

      // stringget
      compile_expr(ctx, receiver, @ast.TsType::String_)
      let src_local = ctx.add_local("__substr_src__", @ast.TsType::Int)
      ctx.emit(LocalSet(src_local))

      // loop (memory.copy simpleimplementation)
      let i_local = ctx.add_local("__substr_i__", @ast.TsType::Int)
      ctx.emit(I32Const(0U))
      ctx.emit(LocalSet(i_local))

      // loop
      let loop_instrs : Array[@core.Instr] = []
      // condition: i < len
      loop_instrs.push(LocalGet(i_local))
      loop_instrs.push(LocalGet(len_local))
      loop_instrs.push(I32GeS)
      loop_instrs.push(BrIf(1U))

      // : dst[4+i] = src[4+start+i]
      // dst
      loop_instrs.push(GlobalGet(0U))
      loop_instrs.push(I32Const(4U))
      loop_instrs.push(I32Add)
      loop_instrs.push(LocalGet(i_local))
      loop_instrs.push(I32Add)

      // src load
      loop_instrs.push(LocalGet(src_local))
      loop_instrs.push(I32Const(4U))
      loop_instrs.push(I32Add)
      loop_instrs.push(LocalGet(start_local))
      loop_instrs.push(I32Add)
      loop_instrs.push(LocalGet(i_local))
      loop_instrs.push(I32Add)
      loop_instrs.push(I32Load8U(0U, 0U, 0U))

      // store
      loop_instrs.push(I32Store8(0U, 0U, 0U))

      // i++
      loop_instrs.push(LocalGet(i_local))
      loop_instrs.push(I32Const(1U))
      loop_instrs.push(I32Add)
      loop_instrs.push(LocalSet(i_local))
      loop_instrs.push(Br(0U))
      ctx.emit(Block(Empty, [Loop(Empty, loop_instrs)]))
      ctx.emit(GlobalGet(0U))
      ctx.emit(I32Const(4U))
      ctx.emit(LocalGet(len_local))
      ctx.emit(I32Add)
      // 4
      ctx.emit(I32Const(3U))
      ctx.emit(I32Add)
      ctx.emit(I32Const(0xFFFFFFFCU))
      ctx.emit(I32And)
      ctx.emit(I32Add)
      ctx.emit(GlobalSet(0U))
    }
    "concat" => {
      // str.concat(other) -> string
      if args.length() < 1 {
        raise CodeGenError("concat requires 1 argument")
      }
      compile_string_concat(ctx, receiver, args[0])
    }
    _ => raise CodeGenError("Unknown string method: \{method_name}")
  }
}

///|
// / string
fn compile_string_concat(
  ctx : CodeGenCtx,
  left : @ast.TsExpr,
  right : @ast.TsExpr,
) -> Unit raise CodeGenError {
  // string
  compile_expr(ctx, left, @ast.TsType::String_)
  let left_local = ctx.add_local("__concat_left__", @ast.TsType::Int)
  ctx.emit(LocalSet(left_local))

  // string
  compile_expr(ctx, right, @ast.TsType::String_)
  let right_local = ctx.add_local("__concat_right__", @ast.TsType::Int)
  ctx.emit(LocalSet(right_local))

  // length
  ctx.emit(LocalGet(left_local))
  ctx.emit(I32Load(2U, 0U, 0U))
  let left_len = ctx.add_local("__concat_left_len__", @ast.TsType::Int)
  ctx.emit(LocalSet(left_len))

  // length
  ctx.emit(LocalGet(right_local))
  ctx.emit(I32Load(2U, 0U, 0U))
  let right_len = ctx.add_local("__concat_right_len__", @ast.TsType::Int)
  ctx.emit(LocalSet(right_len))

  // length
  ctx.emit(LocalGet(left_len))
  ctx.emit(LocalGet(right_len))
  ctx.emit(I32Add)
  let total_len = ctx.add_local("__concat_total_len__", @ast.TsType::Int)
  ctx.emit(LocalSet(total_len))

  // string
  ctx.emit(GlobalGet(0U))

  // length
  ctx.emit(GlobalGet(0U))
  ctx.emit(LocalGet(total_len))
  ctx.emit(I32Store(2U, 0U, 0U))
  let i_local = ctx.add_local("__concat_i__", @ast.TsType::Int)
  ctx.emit(I32Const(0U))
  ctx.emit(LocalSet(i_local))
  let loop1 : Array[@core.Instr] = []
  loop1.push(LocalGet(i_local))
  loop1.push(LocalGet(left_len))
  loop1.push(I32GeS)
  loop1.push(BrIf(1U))

  // dst[4+i] = left[4+i]
  loop1.push(GlobalGet(0U))
  loop1.push(I32Const(4U))
  loop1.push(I32Add)
  loop1.push(LocalGet(i_local))
  loop1.push(I32Add)
  loop1.push(LocalGet(left_local))
  loop1.push(I32Const(4U))
  loop1.push(I32Add)
  loop1.push(LocalGet(i_local))
  loop1.push(I32Add)
  loop1.push(I32Load8U(0U, 0U, 0U))
  loop1.push(I32Store8(0U, 0U, 0U))
  loop1.push(LocalGet(i_local))
  loop1.push(I32Const(1U))
  loop1.push(I32Add)
  loop1.push(LocalSet(i_local))
  loop1.push(Br(0U))
  ctx.emit(Block(Empty, [Loop(Empty, loop1)]))
  ctx.emit(I32Const(0U))
  ctx.emit(LocalSet(i_local))
  let loop2 : Array[@core.Instr] = []
  loop2.push(LocalGet(i_local))
  loop2.push(LocalGet(right_len))
  loop2.push(I32GeS)
  loop2.push(BrIf(1U))

  // dst[4+left_len+i] = right[4+i]
  loop2.push(GlobalGet(0U))
  loop2.push(I32Const(4U))
  loop2.push(I32Add)
  loop2.push(LocalGet(left_len))
  loop2.push(I32Add)
  loop2.push(LocalGet(i_local))
  loop2.push(I32Add)
  loop2.push(LocalGet(right_local))
  loop2.push(I32Const(4U))
  loop2.push(I32Add)
  loop2.push(LocalGet(i_local))
  loop2.push(I32Add)
  loop2.push(I32Load8U(0U, 0U, 0U))
  loop2.push(I32Store8(0U, 0U, 0U))
  loop2.push(LocalGet(i_local))
  loop2.push(I32Const(1U))
  loop2.push(I32Add)
  loop2.push(LocalSet(i_local))
  loop2.push(Br(0U))
  ctx.emit(Block(Empty, [Loop(Empty, loop2)]))
  ctx.emit(GlobalGet(0U))
  ctx.emit(I32Const(4U))
  ctx.emit(LocalGet(total_len))
  ctx.emit(I32Add)
  ctx.emit(I32Const(3U))
  ctx.emit(I32Add)
  ctx.emit(I32Const(0xFFFFFFFCU))
  ctx.emit(I32And)
  ctx.emit(I32Add)
  ctx.emit(GlobalSet(0U))
}

///|
// / arraymethod
fn compile_array_method(
  ctx : CodeGenCtx,
  receiver : @ast.TsExpr,
  method_name : String,
  args : Array[@ast.TsExpr],
  arr_type : @ast.TsType,
) -> Unit raise CodeGenError {
  let elem_type = match arr_type {
    @ast.TsType::Array(t) => t
    _ => @ast.TsType::Number
  }
  match method_name {
    "push" => {
      // arr.push(value) -> elementaddlength
      if args.length() < 1 {
        raise CodeGenError("push requires 1 argument")
      }
      // arrayget
      compile_expr(ctx, receiver, arr_type)
      let arr_local = ctx.add_local("__push_arr__", @ast.TsType::Int)
      ctx.emit(LocalSet(arr_local))

      // currentlengthget
      ctx.emit(LocalGet(arr_local))
      ctx.emit(I32Load(2U, 0U, 0U))
      let len_local = ctx.add_local("__push_len__", @ast.TsType::Int)
      ctx.emit(LocalSet(len_local))

      // element
      let elem_sz = element_size(elem_type)
      ctx.emit(LocalGet(arr_local))
      ctx.emit(I32Const(4U))
      ctx.emit(I32Add)
      ctx.emit(LocalGet(len_local))
      ctx.emit(I32Const(elem_sz.reinterpret_as_uint()))
      ctx.emit(I32Mul)
      ctx.emit(I32Add)
      compile_expr(ctx, args[0], elem_type)
      if is_f64_type(elem_type) {
        ctx.emit(F64Store(3U, 0U, 0U))
      } else {
        ctx.emit(I32Store(2U, 0U, 0U))
      }

      // lengthupdate
      ctx.emit(LocalGet(arr_local))
      ctx.emit(LocalGet(len_local))
      ctx.emit(I32Const(1U))
      ctx.emit(I32Add)
      ctx.emit(I32Store(2U, 0U, 0U))

      // length
      ctx.emit(LocalGet(len_local))
      ctx.emit(I32Const(1U))
      ctx.emit(I32Add)
    }
    _ => raise CodeGenError("Unknown array method: \{method_name}")
  }
}

///|
// / propertyassignment
fn compile_prop_assign(
  ctx : CodeGenCtx,
  obj : @ast.TsExpr,
  prop : String,
  value : @ast.TsExpr,
) -> Unit raise CodeGenError {
  let obj_type = infer_type(ctx, obj)
  match obj_type {
    @ast.TsType::Named(type_name) =>
      match ctx.interfaces.get(type_name) {
        Some(fields) =>
          match field_offset(fields, prop) {
            Some(offset) => {
              // compute
              compile_expr(ctx, obj, obj_type)
              ctx.emit(I32Const(offset.reinterpret_as_uint()))
              ctx.emit(I32Add)
              match field_type(fields, prop) {
                Some(ft) => {
                  compile_expr(ctx, value, ft)
                  if is_f64_type(ft) {
                    ctx.emit(F64Store(3U, 0U, 0U))
                  } else {
                    ctx.emit(I32Store(2U, 0U, 0U))
                  }
                  return
                }
                None => ()
              }
            }
            None => ()
          }
        None => ()
      }
    _ => ()
  }
  raise CodeGenError("Cannot assign to property: \{prop}")
}

///|
// / propertyassignmentexpression()
fn compile_prop_assign_expr(
  ctx : CodeGenCtx,
  obj : @ast.TsExpr,
  prop : String,
  value : @ast.TsExpr,
) -> Unit raise CodeGenError {
  let obj_type = infer_type(ctx, obj)
  match obj_type {
    @ast.TsType::Named(type_name) =>
      match ctx.interfaces.get(type_name) {
        Some(fields) =>
          match field_offset(fields, prop) {
            Some(offset) =>
              match field_type(fields, prop) {
                Some(ft) => {
                  let obj_local = ctx.add_temp_local(@ast.TsType::Int)
                  let val_local = ctx.add_temp_local(ft)
                  // obj
                  compile_expr(ctx, obj, obj_type)
                  ctx.emit(LocalSet(obj_local))
                  // value
                  compile_expr(ctx, value, ft)
                  ctx.emit(LocalSet(val_local))
                  ctx.emit(LocalGet(obj_local))
                  ctx.emit(I32Const(offset.reinterpret_as_uint()))
                  ctx.emit(I32Add)
                  ctx.emit(LocalGet(val_local))
                  if is_f64_type(ft) {
                    ctx.emit(F64Store(3U, 0U, 0U))
                  } else {
                    ctx.emit(I32Store(2U, 0U, 0U))
                  }
                  ctx.emit(LocalGet(val_local))
                  return
                }
                None => ()
              }
            None => ()
          }
        None => ()
      }
    _ => ()
  }
  raise CodeGenError("Cannot assign to property: \{prop}")
}

///|
// / arrayelementassignment
fn compile_index_assign(
  ctx : CodeGenCtx,
  arr : @ast.TsExpr,
  index : @ast.TsExpr,
  value : @ast.TsExpr,
) -> Unit raise CodeGenError {
  let arr_type = infer_type(ctx, arr)
  let elem_type = match arr_type {
    @ast.TsType::Array(t) => t
    _ => @ast.TsType::Number
  }
  let elem_sz = element_size(elem_type)

  // compute: arr + 4 + index * elem_size
  compile_expr(ctx, arr, arr_type) // array
  ctx.emit(I32Const(4U)) // lengthfield
  ctx.emit(I32Add)
  compile_expr(ctx, index, @ast.TsType::Int)
  ctx.emit(I32Const(elem_sz.reinterpret_as_uint()))
  ctx.emit(I32Mul)
  ctx.emit(I32Add)
  compile_expr(ctx, value, elem_type)
  if is_f64_type(elem_type) {
    ctx.emit(F64Store(3U, 0U, 0U))
  } else {
    ctx.emit(I32Store(2U, 0U, 0U))
  }
}

///|
// / arrayelementassignmentexpression()
fn compile_index_assign_expr(
  ctx : CodeGenCtx,
  arr : @ast.TsExpr,
  index : @ast.TsExpr,
  value : @ast.TsExpr,
) -> Unit raise CodeGenError {
  let arr_type = infer_type(ctx, arr)
  let elem_type = match arr_type {
    @ast.TsType::Array(t) => t
    _ => @ast.TsType::Number
  }
  let elem_sz = element_size(elem_type)
  let arr_local = ctx.add_temp_local(@ast.TsType::Int)
  let idx_local = ctx.add_temp_local(@ast.TsType::Int)
  let val_local = ctx.add_temp_local(elem_type)

  // arr -> index -> value
  compile_expr(ctx, arr, arr_type)
  ctx.emit(LocalSet(arr_local))
  compile_expr(ctx, index, @ast.TsType::Int)
  ctx.emit(LocalSet(idx_local))
  compile_expr(ctx, value, elem_type)
  ctx.emit(LocalSet(val_local))

  // compute: arr + 4 + index * elem_size
  ctx.emit(LocalGet(arr_local))
  ctx.emit(I32Const(4U))
  ctx.emit(I32Add)
  ctx.emit(LocalGet(idx_local))
  ctx.emit(I32Const(elem_sz.reinterpret_as_uint()))
  ctx.emit(I32Mul)
  ctx.emit(I32Add)
  ctx.emit(LocalGet(val_local))
  if is_f64_type(elem_type) {
    ctx.emit(F64Store(3U, 0U, 0U))
  } else {
    ctx.emit(I32Store(2U, 0U, 0U))
  }
  ctx.emit(LocalGet(val_local))
}

///|
fn emit_compound_op_instr(
  ctx : CodeGenCtx,
  op : @ast.TsCompoundOp,
  operand_type : @ast.TsType,
) -> Unit raise CodeGenError {
  if operand_type == @ast.TsType::String_ {
    raise CodeGenError(
      "string compound assignment is not supported in Wasm compiler",
    )
  }
  match op {
    @ast.TsCompoundOp::BitAndAssign
    | @ast.TsCompoundOp::BitOrAssign
    | @ast.TsCompoundOp::BitXorAssign
    | @ast.TsCompoundOp::ShlAssign
    | @ast.TsCompoundOp::ShrAssign
    | @ast.TsCompoundOp::UShrAssign
    | @ast.TsCompoundOp::PowAssign =>
      raise CodeGenError(
        "compound op is not supported in Wasm compiler (use interpreter)",
      )
    _ => ()
  }
  if is_f64_type(operand_type) {
    match op {
      @ast.TsCompoundOp::AddAssign => ctx.emit(F64Add)
      @ast.TsCompoundOp::SubAssign => ctx.emit(F64Sub)
      @ast.TsCompoundOp::MulAssign => ctx.emit(F64Mul)
      @ast.TsCompoundOp::DivAssign => ctx.emit(F64Div)
      @ast.TsCompoundOp::ModAssign =>
        raise CodeGenError("f64 mod is not supported in Wasm compiler")
      _ =>
        raise CodeGenError(
          "compound op is not supported in Wasm compiler (use interpreter)",
        )
    }
  } else {
    match op {
      @ast.TsCompoundOp::AddAssign => ctx.emit(I32Add)
      @ast.TsCompoundOp::SubAssign => ctx.emit(I32Sub)
      @ast.TsCompoundOp::MulAssign => ctx.emit(I32Mul)
      @ast.TsCompoundOp::DivAssign => ctx.emit(I32DivS)
      @ast.TsCompoundOp::ModAssign => ctx.emit(I32RemS)
      _ =>
        raise CodeGenError(
          "compound op is not supported in Wasm compiler (use interpreter)",
        )
    }
  }
}

///|
fn compile_var_compound_assign_expr(
  ctx : CodeGenCtx,
  name : String,
  op : @ast.TsCompoundOp,
  value : @ast.TsExpr,
) -> Unit raise CodeGenError {
  match ctx.get_local(name) {
    Some(lvar) => {
      let operand_type = lvar.type_
      ctx.emit(LocalGet(lvar.index))
      compile_expr(ctx, value, operand_type)
      emit_compound_op_instr(ctx, op, operand_type)
      ctx.emit(LocalTee(lvar.index))
    }
    None => raise CodeGenError("Undefined variable: \{name}")
  }
}

///|
fn compile_prop_compound_assign_expr(
  ctx : CodeGenCtx,
  obj : @ast.TsExpr,
  prop : String,
  op : @ast.TsCompoundOp,
  value : @ast.TsExpr,
) -> Unit raise CodeGenError {
  let obj_type = infer_type(ctx, obj)
  match obj_type {
    @ast.TsType::Named(type_name) =>
      match ctx.interfaces.get(type_name) {
        Some(fields) =>
          match field_offset(fields, prop) {
            Some(offset) =>
              match field_type(fields, prop) {
                Some(ft) => {
                  let obj_local = ctx.add_temp_local(@ast.TsType::Int)
                  let addr_local = ctx.add_temp_local(@ast.TsType::Int)
                  let val_local = ctx.add_temp_local(ft)
                  compile_expr(ctx, obj, obj_type)
                  ctx.emit(LocalSet(obj_local))
                  ctx.emit(LocalGet(obj_local))
                  ctx.emit(I32Const(offset.reinterpret_as_uint()))
                  ctx.emit(I32Add)
                  ctx.emit(LocalSet(addr_local))
                  ctx.emit(LocalGet(addr_local))
                  if is_f64_type(ft) {
                    ctx.emit(F64Load(3U, 0U, 0U))
                  } else {
                    ctx.emit(I32Load(2U, 0U, 0U))
                  }
                  compile_expr(ctx, value, ft)
                  emit_compound_op_instr(ctx, op, ft)
                  ctx.emit(LocalSet(val_local))
                  ctx.emit(LocalGet(addr_local))
                  ctx.emit(LocalGet(val_local))
                  if is_f64_type(ft) {
                    ctx.emit(F64Store(3U, 0U, 0U))
                  } else {
                    ctx.emit(I32Store(2U, 0U, 0U))
                  }
                  ctx.emit(LocalGet(val_local))
                  return
                }
                None => ()
              }
            None => ()
          }
        None => ()
      }
    _ => ()
  }
  raise CodeGenError("Cannot assign to property: \{prop}")
}

///|
fn compile_index_compound_assign_expr(
  ctx : CodeGenCtx,
  arr : @ast.TsExpr,
  index : @ast.TsExpr,
  op : @ast.TsCompoundOp,
  value : @ast.TsExpr,
) -> Unit raise CodeGenError {
  let arr_type = infer_type(ctx, arr)
  let elem_type = match arr_type {
    @ast.TsType::Array(t) => t
    _ => @ast.TsType::Number
  }
  let elem_sz = element_size(elem_type)
  let arr_local = ctx.add_temp_local(@ast.TsType::Int)
  let idx_local = ctx.add_temp_local(@ast.TsType::Int)
  let addr_local = ctx.add_temp_local(@ast.TsType::Int)
  let val_local = ctx.add_temp_local(elem_type)
  compile_expr(ctx, arr, arr_type)
  ctx.emit(LocalSet(arr_local))
  compile_expr(ctx, index, @ast.TsType::Int)
  ctx.emit(LocalSet(idx_local))
  ctx.emit(LocalGet(arr_local))
  ctx.emit(I32Const(4U))
  ctx.emit(I32Add)
  ctx.emit(LocalGet(idx_local))
  ctx.emit(I32Const(elem_sz.reinterpret_as_uint()))
  ctx.emit(I32Mul)
  ctx.emit(I32Add)
  ctx.emit(LocalSet(addr_local))
  ctx.emit(LocalGet(addr_local))
  if is_f64_type(elem_type) {
    ctx.emit(F64Load(3U, 0U, 0U))
  } else {
    ctx.emit(I32Load(2U, 0U, 0U))
  }
  compile_expr(ctx, value, elem_type)
  emit_compound_op_instr(ctx, op, elem_type)
  ctx.emit(LocalSet(val_local))
  ctx.emit(LocalGet(addr_local))
  ctx.emit(LocalGet(val_local))
  if is_f64_type(elem_type) {
    ctx.emit(F64Store(3U, 0U, 0U))
  } else {
    ctx.emit(I32Store(2U, 0U, 0U))
  }
  ctx.emit(LocalGet(val_local))
}

///|
fn compile_compound_assign_expr(
  ctx : CodeGenCtx,
  left : @ast.TsExpr,
  op : @ast.TsCompoundOp,
  value : @ast.TsExpr,
) -> Unit raise CodeGenError {
  match left {
    @ast.TsExpr::Var(name) =>
      compile_var_compound_assign_expr(ctx, name, op, value)
    @ast.TsExpr::PropAccess(obj, prop) =>
      compile_prop_compound_assign_expr(ctx, obj, prop, op, value)
    @ast.TsExpr::IndexAccess(arr, index) =>
      compile_index_compound_assign_expr(ctx, arr, index, op, value)
    _ =>
      raise CodeGenError(
        "compound assignment target is not supported in Wasm compiler",
      )
  }
}

///|
// / binary
fn compile_binop(
  ctx : CodeGenCtx,
  op : @ast.TsBinOp,
  left : @ast.TsExpr,
  right : @ast.TsExpr,
  expected_type : @ast.TsType,
) -> Unit raise CodeGenError {
  // stringcheck
  let left_type = infer_type(ctx, left)
  let right_type = infer_type(ctx, right)
  if op == @ast.TsBinOp::Add &&
    (left_type == @ast.TsType::String_ || right_type == @ast.TsType::String_) {
    // string
    compile_string_concat(ctx, left, right)
    return
  }
  match op {
    @ast.TsBinOp::Pow
    | @ast.TsBinOp::BitAnd
    | @ast.TsBinOp::BitOr
    | @ast.TsBinOp::BitXor
    | @ast.TsBinOp::Shl
    | @ast.TsBinOp::Shr
    | @ast.TsBinOp::UShr
    | @ast.TsBinOp::In =>
      raise CodeGenError(
        "binary op is not supported in Wasm compiler (use interpreter)",
      )
    _ => ()
  }

  // comparisonoperatortype, operator @ast.TsType::Boolean
  let operand_type = match op {
    @ast.TsBinOp::Add
    | @ast.TsBinOp::Sub
    | @ast.TsBinOp::Mul
    | @ast.TsBinOp::Div
    | @ast.TsBinOp::Mod
    | @ast.TsBinOp::Pow => expected_type
    @ast.TsBinOp::BitAnd
    | @ast.TsBinOp::BitOr
    | @ast.TsBinOp::BitXor
    | @ast.TsBinOp::Shl
    | @ast.TsBinOp::Shr
    | @ast.TsBinOp::UShr => @ast.TsType::Int
    @ast.TsBinOp::BinLt
    | @ast.TsBinOp::BinLe
    | @ast.TsBinOp::BinGt
    | @ast.TsBinOp::BinGe
    | @ast.TsBinOp::BinEq
    | @ast.TsBinOp::BinNe
    | @ast.TsBinOp::AbstractEq
    | @ast.TsBinOp::AbstractNe =>
      // Int Int, @ast.TsType::Number
      if left_type == @ast.TsType::Int && right_type == @ast.TsType::Int {
        @ast.TsType::Int
      } else {
        @ast.TsType::Number
      }
    @ast.TsBinOp::Instanceof | @ast.TsBinOp::In =>
      raise CodeGenError(
        "instanceof is not supported in Wasm compiler (use interpreter)",
      )
    @ast.TsBinOp::And | @ast.TsBinOp::Or | @ast.TsBinOp::Coalesce =>
      @ast.TsType::Boolean
  }
  compile_expr(ctx, left, operand_type)
  compile_expr(ctx, right, operand_type)
  if is_f64_type(operand_type) {
    // f64
    match op {
      @ast.TsBinOp::Add => ctx.emit(F64Add)
      @ast.TsBinOp::Sub => ctx.emit(F64Sub)
      @ast.TsBinOp::Mul => ctx.emit(F64Mul)
      @ast.TsBinOp::Div => ctx.emit(F64Div)
      @ast.TsBinOp::Mod => raise CodeGenError("f64 mod not supported")
      @ast.TsBinOp::Pow =>
        raise CodeGenError(
          "pow is not supported in Wasm compiler (use interpreter)",
        )
      @ast.TsBinOp::BinLt => ctx.emit(F64Lt)
      @ast.TsBinOp::BinLe => ctx.emit(F64Le)
      @ast.TsBinOp::BinGt => ctx.emit(F64Gt)
      @ast.TsBinOp::BinGe => ctx.emit(F64Ge)
      @ast.TsBinOp::BinEq | @ast.TsBinOp::AbstractEq => ctx.emit(F64Eq)
      @ast.TsBinOp::BinNe | @ast.TsBinOp::AbstractNe => ctx.emit(F64Ne)
      @ast.TsBinOp::Instanceof | @ast.TsBinOp::In =>
        raise CodeGenError(
          "instanceof is not supported in Wasm compiler (use interpreter)",
        )
      @ast.TsBinOp::BitAnd
      | @ast.TsBinOp::BitOr
      | @ast.TsBinOp::BitXor
      | @ast.TsBinOp::Shl
      | @ast.TsBinOp::Shr
      | @ast.TsBinOp::UShr => raise CodeGenError("bitwise op on f64")
      @ast.TsBinOp::And | @ast.TsBinOp::Or | @ast.TsBinOp::Coalesce =>
        raise CodeGenError("Logical op on f64")
    }
  } else {
    // i32
    match op {
      @ast.TsBinOp::Add => ctx.emit(I32Add)
      @ast.TsBinOp::Sub => ctx.emit(I32Sub)
      @ast.TsBinOp::Mul => ctx.emit(I32Mul)
      @ast.TsBinOp::Div => ctx.emit(I32DivS)
      @ast.TsBinOp::Mod => ctx.emit(I32RemS)
      @ast.TsBinOp::Pow =>
        raise CodeGenError(
          "pow is not supported in Wasm compiler (use interpreter)",
        )
      @ast.TsBinOp::BitAnd => ctx.emit(I32And)
      @ast.TsBinOp::BitOr => ctx.emit(I32Or)
      @ast.TsBinOp::BitXor => ctx.emit(I32Xor)
      @ast.TsBinOp::Shl => ctx.emit(I32Shl)
      @ast.TsBinOp::Shr => ctx.emit(I32ShrS)
      @ast.TsBinOp::UShr => ctx.emit(I32ShrU)
      @ast.TsBinOp::BinLt => ctx.emit(I32LtS)
      @ast.TsBinOp::BinLe => ctx.emit(I32LeS)
      @ast.TsBinOp::BinGt => ctx.emit(I32GtS)
      @ast.TsBinOp::BinGe => ctx.emit(I32GeS)
      @ast.TsBinOp::BinEq | @ast.TsBinOp::AbstractEq => ctx.emit(I32Eq)
      @ast.TsBinOp::BinNe | @ast.TsBinOp::AbstractNe => ctx.emit(I32Ne)
      @ast.TsBinOp::Instanceof | @ast.TsBinOp::In =>
        raise CodeGenError(
          "instanceof is not supported in Wasm compiler (use interpreter)",
        )
      @ast.TsBinOp::And => ctx.emit(I32And)
      @ast.TsBinOp::Or => ctx.emit(I32Or)
      @ast.TsBinOp::Coalesce =>
        raise CodeGenError("Nullish coalescing not supported in Wasm compiler")
    }
  }
}

///|
// / unary
fn compile_unaryop(
  ctx : CodeGenCtx,
  op : @ast.TsUnaryOp,
  operand : @ast.TsExpr,
  expected_type : @ast.TsType,
) -> Unit raise CodeGenError {
  match op {
    @ast.TsUnaryOp::Neg =>
      if is_f64_type(expected_type) {
        compile_expr(ctx, operand, expected_type)
        ctx.emit(F64Neg)
      } else {
        // i32: 0 - x
        ctx.emit(I32Const(0U))
        compile_expr(ctx, operand, expected_type)
        ctx.emit(I32Sub)
      }
    @ast.TsUnaryOp::Not => {
      compile_expr(ctx, operand, @ast.TsType::Boolean)
      ctx.emit(I32Eqz)
    }
    @ast.TsUnaryOp::PreInc =>
      // ++x: x = x + 1, return new value
      match operand {
        @ast.TsExpr::Var(name) =>
          match ctx.get_local(name) {
            Some(lvar) => {
              // x + 1
              ctx.emit(LocalGet(lvar.index))
              if is_f64_type(lvar.type_) {
                ctx.emit(F64Const(1.0))
                ctx.emit(F64Add)
              } else {
                ctx.emit(I32Const(1U))
                ctx.emit(I32Add)
              }
              // store and keep on stack
              ctx.emit(LocalTee(lvar.index))
            }
            None => raise CodeGenError("Undefined variable in ++: \{name}")
          }
        _ => raise CodeGenError("Invalid operand for ++")
      }
    @ast.TsUnaryOp::PreDec =>
      // --x: x = x - 1, return new value
      match operand {
        @ast.TsExpr::Var(name) =>
          match ctx.get_local(name) {
            Some(lvar) => {
              ctx.emit(LocalGet(lvar.index))
              if is_f64_type(lvar.type_) {
                ctx.emit(F64Const(1.0))
                ctx.emit(F64Sub)
              } else {
                ctx.emit(I32Const(1U))
                ctx.emit(I32Sub)
              }
              ctx.emit(LocalTee(lvar.index))
            }
            None => raise CodeGenError("Undefined variable in --: \{name}")
          }
        _ => raise CodeGenError("Invalid operand for --")
      }
    @ast.TsUnaryOp::PostInc =>
      // x++: return old value, then x = x + 1
      match operand {
        @ast.TsExpr::Var(name) =>
          match ctx.get_local(name) {
            Some(lvar) => {
              // get old value
              ctx.emit(LocalGet(lvar.index))
              // x + 1
              ctx.emit(LocalGet(lvar.index))
              if is_f64_type(lvar.type_) {
                ctx.emit(F64Const(1.0))
                ctx.emit(F64Add)
              } else {
                ctx.emit(I32Const(1U))
                ctx.emit(I32Add)
              }
              ctx.emit(LocalSet(lvar.index))
              // old value is still on stack
            }
            None => raise CodeGenError("Undefined variable in ++: \{name}")
          }
        _ => raise CodeGenError("Invalid operand for ++")
      }
    @ast.TsUnaryOp::PostDec =>
      // x--: return old value, then x = x - 1
      match operand {
        @ast.TsExpr::Var(name) =>
          match ctx.get_local(name) {
            Some(lvar) => {
              ctx.emit(LocalGet(lvar.index))
              ctx.emit(LocalGet(lvar.index))
              if is_f64_type(lvar.type_) {
                ctx.emit(F64Const(1.0))
                ctx.emit(F64Sub)
              } else {
                ctx.emit(I32Const(1U))
                ctx.emit(I32Sub)
              }
              ctx.emit(LocalSet(lvar.index))
            }
            None => raise CodeGenError("Undefined variable in --: \{name}")
          }
        _ => raise CodeGenError("Invalid operand for --")
      }
    @ast.TsUnaryOp::Plus =>
      // unary: conversion()
      compile_expr(ctx, operand, expected_type)
    @ast.TsUnaryOp::Typeof =>
      // typeof Wasm
      raise CodeGenError(
        "typeof is not supported in Wasm compiler (use interpreter)",
      )
    @ast.TsUnaryOp::Void =>
      // void
      raise CodeGenError(
        "void is not supported in Wasm compiler (use interpreter)",
      )
    @ast.TsUnaryOp::Delete =>
      raise CodeGenError(
        "delete is not supported in Wasm compiler (use interpreter)",
      )
    @ast.TsUnaryOp::BitwiseNot =>
      // ~x: bitwise NOT (i32)
      raise CodeGenError(
        "Bitwise NOT is not supported in Wasm compiler (use interpreter)",
      )
  }
}

///|
// / function
fn compile_call(
  ctx : CodeGenCtx,
  name : String,
  args : Array[@ast.TsExpr],
  expected_type : @ast.TsType,
) -> Unit raise CodeGenError {
  // functionget
  match ctx.funcs.get(name) {
    Some(idx) => {
      // importfunctiontype
      match ctx.import_types.get(name) {
        Some((param_types, _)) =>
          // importfunction: parametertypereference
          for i, arg in args {
            match arg {
              @ast.TsExpr::Spread(_) =>
                raise CodeGenError(
                  "Spread is not supported in Wasm compiler (use interpreter)",
                )
              _ => ()
            }
            let param_type = if i < param_types.length() {
              param_types[i]
            } else {
              expected_type // argument
            }
            compile_expr(ctx, arg, param_type)
          }
        None =>
          // definefunction: expected_type
          for arg in args {
            match arg {
              @ast.TsExpr::Spread(_) =>
                raise CodeGenError(
                  "Spread is not supported in Wasm compiler (use interpreter)",
                )
              _ => ()
            }
            compile_expr(ctx, arg, expected_type)
          }
      }
      ctx.emit(Call(idx))
    }
    None => raise CodeGenError("Undefined function: \{name}")
  }
}

// ============================================
// statementcodegen
// ============================================

///|
// / statement
fn compile_stmt(
  ctx : CodeGenCtx,
  stmt : @ast.TsStmt,
  return_type : @ast.TsType,
) -> Unit raise CodeGenError {
  match stmt {
    @ast.TsStmt::Var(binding, type_, init)
    | @ast.TsStmt::Let(binding, type_, init) =>
      match binding {
        @ast.TsBinding::Ident(name) => {
          // @ast.TsType::Any typeliteral
          let resolved_type = resolve_any(type_, init)
          let idx = ctx.add_local(name, resolved_type)
          compile_expr(ctx, init, resolved_type)
          ctx.emit(LocalSet(idx))
        }
        _ => raise CodeGenError("Unsupported var/let binding pattern")
      }
    @ast.TsStmt::Const(binding, type_, init) =>
      match binding {
        @ast.TsBinding::Ident(name) => {
          // const let , @ast.TsType::Any typeliteral
          let resolved_type = resolve_any(type_, init)
          let idx = ctx.add_local(name, resolved_type)
          compile_expr(ctx, init, resolved_type)
          ctx.emit(LocalSet(idx))
        }
        _ => raise CodeGenError("Unsupported const binding pattern")
      }
    @ast.TsStmt::Assign(name, expr) =>
      match ctx.get_local(name) {
        Some(lvar) => {
          compile_expr(ctx, expr, lvar.type_)
          ctx.emit(LocalSet(lvar.index))
        }
        None => raise CodeGenError("Undefined variable: \{name}")
      }
    @ast.TsStmt::CompoundAssign(name, op, expr) =>
      match ctx.get_local(name) {
        Some(lvar) => {
          // x op= expr → x = x op expr
          ctx.emit(LocalGet(lvar.index))
          compile_expr(ctx, expr, lvar.type_)
          if is_f64_type(lvar.type_) {
            match op {
              @ast.TsCompoundOp::AddAssign => ctx.emit(F64Add)
              @ast.TsCompoundOp::SubAssign => ctx.emit(F64Sub)
              @ast.TsCompoundOp::MulAssign => ctx.emit(F64Mul)
              @ast.TsCompoundOp::DivAssign => ctx.emit(F64Div)
              @ast.TsCompoundOp::ModAssign
              | @ast.TsCompoundOp::BitAndAssign
              | @ast.TsCompoundOp::BitOrAssign
              | @ast.TsCompoundOp::BitXorAssign
              | @ast.TsCompoundOp::ShlAssign
              | @ast.TsCompoundOp::ShrAssign
              | @ast.TsCompoundOp::UShrAssign
              | @ast.TsCompoundOp::PowAssign
              | @ast.TsCompoundOp::AndAssign
              | @ast.TsCompoundOp::OrAssign
              | @ast.TsCompoundOp::CoalesceAssign =>
                raise CodeGenError(
                  "compound op is not supported on f64 in Wasm compiler",
                )
            }
          } else {
            match op {
              @ast.TsCompoundOp::AddAssign => ctx.emit(I32Add)
              @ast.TsCompoundOp::SubAssign => ctx.emit(I32Sub)
              @ast.TsCompoundOp::MulAssign => ctx.emit(I32Mul)
              @ast.TsCompoundOp::DivAssign => ctx.emit(I32DivS)
              @ast.TsCompoundOp::ModAssign => ctx.emit(I32RemS)
              @ast.TsCompoundOp::BitAndAssign => ctx.emit(I32And)
              @ast.TsCompoundOp::BitOrAssign => ctx.emit(I32Or)
              @ast.TsCompoundOp::BitXorAssign => ctx.emit(I32Xor)
              @ast.TsCompoundOp::ShlAssign => ctx.emit(I32Shl)
              @ast.TsCompoundOp::ShrAssign => ctx.emit(I32ShrS)
              @ast.TsCompoundOp::UShrAssign => ctx.emit(I32ShrU)
              @ast.TsCompoundOp::PowAssign
              | @ast.TsCompoundOp::AndAssign
              | @ast.TsCompoundOp::OrAssign
              | @ast.TsCompoundOp::CoalesceAssign =>
                raise CodeGenError(
                  "logical/pow assignment is not supported in Wasm compiler (use interpreter)",
                )
            }
          }
          ctx.emit(LocalSet(lvar.index))
        }
        None => raise CodeGenError("Undefined variable: \{name}")
      }
    @ast.TsStmt::IndexAssign(arr, index, value) =>
      compile_index_assign(ctx, arr, index, value)
    @ast.TsStmt::PropAssign(obj, prop, value) =>
      compile_prop_assign(ctx, obj, prop, value)
    @ast.TsStmt::Expr(expr) => {
      compile_expr(ctx, expr, return_type)
      ctx.emit(Drop)
    }
    Empty => ()
    @ast.TsStmt::Block(block) =>
      for stmt in block.stmts {
        compile_stmt(ctx, stmt, return_type)
      }
    @ast.TsStmt::Label(_, inner) => compile_stmt(ctx, inner, return_type)
    @ast.TsStmt::Return(Some(expr)) => {
      compile_expr(ctx, expr, return_type)
      ctx.emit(Return)
    }
    @ast.TsStmt::Return(None) => ctx.emit(Return)
    @ast.TsStmt::Throw(_) =>
      raise CodeGenError("throw is not supported in Wasm compiler")
    @ast.TsStmt::Try(_, _, _, _) =>
      raise CodeGenError("try/catch/finally is not supported in Wasm compiler")
    @ast.TsStmt::If(cond, then_block, else_block) =>
      compile_if(ctx, cond, then_block, else_block, return_type)
    @ast.TsStmt::While(cond, body) =>
      compile_while(ctx, cond, body, return_type)
    @ast.TsStmt::DoWhile(_, _) =>
      raise CodeGenError("do-while is not yet supported in Wasm compiler")
    @ast.TsStmt::Switch(_, _) =>
      raise CodeGenError("switch is not supported in Wasm compiler")
    @ast.TsStmt::With(_, _) =>
      raise CodeGenError("with is not supported in Wasm compiler")
    @ast.TsStmt::Debugger => ()
    @ast.TsStmt::For(init, cond, update, body) =>
      compile_for(ctx, init, cond, update, body, return_type)
    @ast.TsStmt::ForOf(kind, binding, var_type, iterable, body) =>
      compile_for_of(ctx, kind, binding, var_type, iterable, body, return_type)
    @ast.TsStmt::ForAwaitOf(_, _, _, _, _) =>
      raise CodeGenError("for-await-of is not supported in Wasm compiler")
    @ast.TsStmt::ForIn(_, _, _, _, _) =>
      raise CodeGenError("for-in is not supported in Wasm compiler")
    @ast.TsStmt::Break(label) =>
      match label {
        None =>
          // loop block
          ctx.emit(Br((ctx.loop_depth * 2 - 1).reinterpret_as_uint()))
        Some(_) =>
          raise CodeGenError("labeled break is not supported in Wasm compiler")
      }
    @ast.TsStmt::Continue(label) =>
      match label {
        None =>
          // loop head
          ctx.emit(Br(((ctx.loop_depth - 1) * 2).reinterpret_as_uint()))
        Some(_) =>
          raise CodeGenError(
            "labeled continue is not supported in Wasm compiler",
          )
      }
  }
}

///|
// / if statement
fn compile_if(
  ctx : CodeGenCtx,
  cond : @ast.TsExpr,
  then_block : @ast.TsBlock,
  else_block : @ast.TsBlock?,
  return_type : @ast.TsType,
) -> Unit raise CodeGenError {
  compile_expr(ctx, cond, @ast.TsType::Boolean)
  let then_instrs = compile_block_to_instrs(ctx, then_block, return_type)
  let else_instrs = match else_block {
    Some(block) => compile_block_to_instrs(ctx, block, return_type)
    None => []
  }
  ctx.emit(If(Empty, then_instrs, else_instrs))
}

///|
// / while statement
fn compile_while(
  ctx : CodeGenCtx,
  cond : @ast.TsExpr,
  body : @ast.TsBlock,
  return_type : @ast.TsType,
) -> Unit raise CodeGenError {
  ctx.loop_depth += 1

  // Block(Loop([cond, BrIf(1), ...body, Br(0)]))
  let loop_instrs : Array[@core.Instr] = []

  // conditioncheck
  let cond_ctx : CodeGenCtx = {
    locals: ctx.locals,
    local_types: ctx.local_types,
    next_local: ctx.next_local,
    funcs: ctx.funcs,
    interfaces: ctx.interfaces,
    import_types: ctx.import_types,
    instrs: [],
    loop_depth: ctx.loop_depth,
    string_pool: ctx.string_pool,
    builtins_used: ctx.builtins_used,
  }
  compile_expr(cond_ctx, cond, @ast.TsType::Boolean)
  for instr in cond_ctx.instrs {
    loop_instrs.push(instr)
  }
  loop_instrs.push(I32Eqz)
  loop_instrs.push(BrIf(1U)) // conditionblock

  // body
  let body_instrs = compile_block_to_instrs(ctx, body, return_type)
  for instr in body_instrs {
    loop_instrs.push(instr)
  }
  loop_instrs.push(Br(0U)) // loophead
  ctx.emit(Block(Empty, [Loop(Empty, loop_instrs)]))
  ctx.loop_depth -= 1
}

///|
// / for statement
fn compile_for(
  ctx : CodeGenCtx,
  init : @ast.TsStmt?,
  cond : @ast.TsExpr?,
  update : @ast.TsStmt?,
  body : @ast.TsBlock,
  return_type : @ast.TsType,
) -> Unit raise CodeGenError {
  // init
  match init {
    Some(stmt) => compile_stmt(ctx, stmt, return_type)
    None => ()
  }
  ctx.loop_depth += 1
  let loop_instrs : Array[@core.Instr] = []

  // cond
  match cond {
    Some(c) => {
      let cond_ctx : CodeGenCtx = {
        locals: ctx.locals,
        local_types: ctx.local_types,
        next_local: ctx.next_local,
        funcs: ctx.funcs,
        interfaces: ctx.interfaces,
        import_types: ctx.import_types,
        instrs: [],
        loop_depth: ctx.loop_depth,
        string_pool: ctx.string_pool,
        builtins_used: ctx.builtins_used,
      }
      compile_expr(cond_ctx, c, @ast.TsType::Boolean)
      for instr in cond_ctx.instrs {
        loop_instrs.push(instr)
      }
      loop_instrs.push(I32Eqz)
      loop_instrs.push(BrIf(1U))
    }
    None => ()
  }

  // body
  let body_instrs = compile_block_to_instrs(ctx, body, return_type)
  for instr in body_instrs {
    loop_instrs.push(instr)
  }

  // update
  match update {
    Some(stmt) => {
      let update_ctx : CodeGenCtx = {
        locals: ctx.locals,
        local_types: ctx.local_types,
        next_local: ctx.next_local,
        funcs: ctx.funcs,
        interfaces: ctx.interfaces,
        import_types: ctx.import_types,
        instrs: [],
        loop_depth: ctx.loop_depth,
        string_pool: ctx.string_pool,
        builtins_used: ctx.builtins_used,
      }
      compile_stmt(update_ctx, stmt, return_type)
      for instr in update_ctx.instrs {
        loop_instrs.push(instr)
      }
    }
    None => ()
  }
  loop_instrs.push(Br(0U)) // loophead
  ctx.emit(Block(Empty, [Loop(Empty, loop_instrs)]))
  ctx.loop_depth -= 1
}

///|
// / for...of
fn compile_for_of(
  ctx : CodeGenCtx,
  kind : @ast.TsForOfKind,
  binding : @ast.TsBinding,
  _var_type : @ast.TsType,
  iterable : @ast.TsExpr,
  body : @ast.TsBlock,
  return_type : @ast.TsType,
) -> Unit raise CodeGenError {
  let var_name = match binding {
    @ast.TsBinding::Ident(name) => name
    _ =>
      raise CodeGenError(
        "for...of destructuring is not supported in Wasm compiler",
      )
  }
  // arraygetvariablesave
  let arr_type = infer_type(ctx, iterable)
  let elem_type = match arr_type {
    @ast.TsType::Array(t) => t
    _ => @ast.TsType::Number
  }

  // arraysave
  let arr_local = ctx.add_local("__for_of_arr__", arr_type)
  compile_expr(ctx, iterable, arr_type)
  ctx.emit(LocalSet(arr_local))

  // arraylengthgetsave
  let len_local = ctx.add_local("__for_of_len__", @ast.TsType::Int)
  ctx.emit(LocalGet(arr_local))
  ctx.emit(I32Load(2U, 0U, 0U))
  ctx.emit(LocalSet(len_local))

  // variable
  let idx_local = ctx.add_local("__for_of_idx__", @ast.TsType::Int)
  ctx.emit(I32Const(0U))
  ctx.emit(LocalSet(idx_local))

  // loopvariable
  let loop_var_idx = match kind {
    @ast.TsForOfKind::Assign =>
      match ctx.get_local(var_name) {
        Some(lvar) => lvar.index
        None => raise CodeGenError("Undefined variable: \{var_name}")
      }
    _ => ctx.add_local(var_name, elem_type)
  }
  ctx.loop_depth += 1
  let loop_instrs : Array[@core.Instr] = []

  // condition: idx < len
  loop_instrs.push(LocalGet(idx_local))
  loop_instrs.push(LocalGet(len_local))
  loop_instrs.push(I32GeS)
  loop_instrs.push(BrIf(1U))

  // loopvariable arr[idx] assignment
  let elem_sz = element_size(elem_type)
  loop_instrs.push(LocalGet(arr_local))
  loop_instrs.push(I32Const(4U))
  loop_instrs.push(I32Add)
  loop_instrs.push(LocalGet(idx_local))
  loop_instrs.push(I32Const(elem_sz.reinterpret_as_uint()))
  loop_instrs.push(I32Mul)
  loop_instrs.push(I32Add)
  if is_f64_type(elem_type) {
    loop_instrs.push(F64Load(3U, 0U, 0U))
  } else {
    loop_instrs.push(I32Load(2U, 0U, 0U))
  }
  loop_instrs.push(LocalSet(loop_var_idx))

  // body
  let body_instrs = compile_block_to_instrs(ctx, body, return_type)
  for instr in body_instrs {
    loop_instrs.push(instr)
  }

  // idx++
  loop_instrs.push(LocalGet(idx_local))
  loop_instrs.push(I32Const(1U))
  loop_instrs.push(I32Add)
  loop_instrs.push(LocalSet(idx_local))
  loop_instrs.push(Br(0U))
  ctx.emit(Block(Empty, [Loop(Empty, loop_instrs)]))
  ctx.loop_depth -= 1
}

///|
// / blockconversion()
fn compile_block_to_instrs(
  ctx : CodeGenCtx,
  block : @ast.TsBlock,
  return_type : @ast.TsType,
) -> Array[@core.Instr] raise CodeGenError {
  // locals local_types
  let sub_ctx : CodeGenCtx = {
    locals: ctx.locals,
    local_types: ctx.local_types,
    next_local: ctx.next_local,
    funcs: ctx.funcs,
    interfaces: ctx.interfaces,
    import_types: ctx.import_types,
    instrs: [],
    loop_depth: ctx.loop_depth,
    string_pool: ctx.string_pool,
    builtins_used: ctx.builtins_used,
  }
  for stmt in block.stmts {
    compile_stmt(sub_ctx, stmt, return_type)
  }

  // variableupdate
  ctx.next_local = sub_ctx.next_local
  sub_ctx.instrs
}

// ============================================
// functioncodegen
// ============================================

///|
// / function
fn compile_function(
  func : @ast.TsFunc,
  func_map : Map[String, UInt],
  interfaces : Map[String, Array[(String, @ast.TsType)]],
  import_types : Map[String, (Array[@ast.TsType], @ast.TsType)],
  string_pool : StringPool,
  builtins_used : Map[String, Bool],
) -> (@core.TypeDef, @core.Code) raise CodeGenError {
  let ctx = CodeGenCtx::new(
    func_map, interfaces, import_types, string_pool, builtins_used,
  )

  // parametervariable
  for param in func.params {
    let _ = ctx.add_local(param.name, param.type_)

  }

  // parametervariable
  let param_count = func.params.length().reinterpret_as_uint()

  // function
  for stmt in func.body.stmts {
    compile_stmt(ctx, stmt, func.return_type)
  }

  // typedefine
  let params : Array[@core.ValType] = []
  for param in func.params {
    params.push(ts_type_to_valtype(param.type_))
  }
  let results : Array[@core.ValType] = match func.return_type {
    @ast.TsType::Void => []
    t => [ts_type_to_valtype(t)]
  }
  let func_type : @core.TypeDef = @core.TypeDef::Func({ params, results })

  // variable(parameter)
  let locals : Array[@core.ValType] = []
  let mut i = param_count.reinterpret_as_int()
  while i < ctx.next_local.reinterpret_as_int() {
    locals.push(ts_type_to_valtype(ctx.local_types[i]))
    i += 1
  }
  let code : @core.Code = {
    locals,
    body: @core.Expr::{ instrs: ctx.instrs },
    compiled: None,
    max_stack_height: 0,
  }
  (func_type, code)
}

// ============================================
// codegen
// ============================================

///|
// /
pub fn compile_module(
  module_ : @ast.TsModule,
) -> @core.Module raise CodeGenError {
  // importcompute
  let num_imports = module_.imports.length().reinterpret_as_uint()

  // functioncreate
  let func_map : Map[String, UInt] = {}

  // importfunction func_map add ( 0 )
  for i, imp in module_.imports {
    func_map[imp.name] = i.reinterpret_as_uint()
  }

  // definefunction func_map add (import)
  for i, func in module_.funcs {
    func_map[func.name] = i.reinterpret_as_uint() + num_imports
  }

  // interfacecreate
  let interface_map : Map[String, Array[(String, @ast.TsType)]] = {}
  for iface in module_.interfaces {
    interface_map[iface.name] = iface.fields
  }

  // importfunctiontypecreate
  let import_types : Map[String, (Array[@ast.TsType], @ast.TsType)] = {}
  for imp in module_.imports {
    let param_types : Array[@ast.TsType] = []
    for param in imp.params {
      param_types.push(param.1)
    }
    import_types[imp.name] = (param_types, imp.return_type)
  }

  // stringcreate (snapshot)
  let string_pool = StringPool::new()

  // typedefine (importfunctiontypeadd)
  let types : Array[@core.TypeDef] = []
  for imp in module_.imports {
    let params : Array[@core.ValType] = []
    for param in imp.params {
      params.push(ts_type_to_valtype(param.1))
    }
    let results : Array[@core.ValType] = match imp.return_type {
      @ast.TsType::Void => []
      t => [ts_type_to_valtype(t)]
    }
    types.push(@core.TypeDef::Func({ params, results }))
  }

  // function
  let codes : Array[@core.Code] = []
  let funcs : Array[UInt] = []
  let exports : Array[@core.Export] = []
  let builtins_used : Map[String, Bool] = {}
  for i, func in module_.funcs {
    let (func_type, code) = compile_function(
      func, func_map, interface_map, import_types, string_pool, builtins_used,
    )
    types.push(func_type)
    codes.push(code)
    let func_idx = i.reinterpret_as_uint() + num_imports
    funcs.push(func_idx)

    // functionexport
    let name_bytes = string_to_bytes(func.name)
    exports.push({ name: name_bytes, desc: @core.ExportDesc::Func(func_idx) })
  }

  // Wasm importgenerate
  let imports : Array[@core.Import] = []
  for i, imp in module_.imports {
    imports.push({
      module_: string_to_bytes(imp.module_),
      name: string_to_bytes(imp.name),
      desc: @core.ImportDesc::Func(i.reinterpret_as_uint()), // type
    })
  }

  // (1 = 64KB)
  let mems : Array[@core.MemType] = [
    { limits: { min: 1UL, max: Some(16UL) }, shared: false, memory64: false },
  ]

  // stringdatadatasection
  let datas : Array[@core.Data] = if string_pool.data.length() > 0 {
    [
      {
        mem_idx: 0U,
        offset: { instrs: [I32Const(0U)] },
        init: Bytes::from_array(string_pool.data).sub(),
        is_active: true,
      },
    ]
  } else {
    []
  }

  // = string (4)
  let heap_start = (string_pool.offset() + 3) / 4 * 4
  let heap_start_aligned = if heap_start < 1024 { 1024 } else { heap_start }

  // variable ()
  let globals : Array[@core.Global] = [
    {
      type_: { val_type: I32, mutable: true },
      init: { instrs: [I32Const(heap_start_aligned.reinterpret_as_uint())] },
    },
  ]

  // type metadatasection (snapshot)
  let type_metadata = serialize_type_metadata(module_)
  let customs : Array[@core.CustomSection] = [
    { name: string_to_bytes("tstype"), data: type_metadata, placement: End },
  ]
  @core.Module::{
    types,
    type_groups: [],
    customs,
    funcs,
    tables: [],
    mems,
    globals,
    tags: [],
    elems: [],
    datas,
    start: None,
    imports,
    exports,
    codes,
  }
}

///|
// / string Bytes conversion (ASCII)
fn string_to_bytes(s : String) -> Bytes {
  let arr : Array[Byte] = []
  for i = 0; i < s.length(); i = i + 1 {
    arr.push((s[i].to_int() & 0xFF).to_byte())
  }
  Bytes::from_array(arr)
}

// ============================================
// function
// ============================================

///|
// / error ( + codegen)
pub suberror CompileError {
  CompileError(String)
} derive(Show)

///|
// / TypeScript Wasm
pub fn compile_to_wasm(source : String) -> Bytes raise CompileError {
  let parser = @parser.Parser::from_source(source)
  let ts_module = parser.parse_module() catch {
    @parser.ParseError::ParseError(msg) =>
      raise CompileError("Parse error: \{msg}")
  }

  // codegen
  let wasm_module = compile_module(ts_module) catch {
    CodeGenError(msg) => raise CompileError("CodeGen error: \{msg}")
  }

  // Wasm encode
  @encode.encode(wasm_module) catch {
    @encode.EncodeError::Unsupported(msg) =>
      raise CompileError("Encode error: \{msg}")
  }
}

///|
// / TypeScript wasm5 Module generate
pub fn compile(source : String) -> @core.Module raise CompileError {
  let parser = @parser.Parser::from_source(source)
  let ts_module = parser.parse_module() catch {
    @parser.ParseError::ParseError(msg) =>
      raise CompileError("Parse error: \{msg}")
  }
  compile_module(ts_module) catch {
    CodeGenError(msg) => raise CompileError("CodeGen error: \{msg}")
  }
}
