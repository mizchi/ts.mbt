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
    // Extended types (for analysis, not yet used in codegen)
    @ast.TsType::BigInt => b'\x0A'
    @ast.TsType::Symbol => b'\x0B'
    @ast.TsType::Never => b'\x0C'
    @ast.TsType::Null => b'\x0D'
    @ast.TsType::Undefined => b'\x0E'
    @ast.TsType::Literal(_) => b'\x0F'
    @ast.TsType::Tuple(_) => b'\x10'
    @ast.TsType::Object(_) => b'\x11'
    @ast.TsType::Union(_) => b'\x12'
    @ast.TsType::Intersection(_) => b'\x13'
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

///|
// / @ast.TsType::Any type resolve with context
fn resolve_any_with_ctx(
  ctx : CodeGenCtx,
  declared : @ast.TsType,
  init : @ast.TsExpr,
) -> @ast.TsType {
  match declared {
    @ast.TsType::Any => infer_type(ctx, init)
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
  // function signature map (name -> (param types, return type))
  func_types : Map[String, (Array[@ast.TsType], @ast.TsType)]
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
  // Constant propagation: track const variable values
  const_values : Map[String, @analysis.ConstValue]
  // wasm-gc mode: use GC types instead of linear memory
  use_gc : Bool
  // wasm-gc type indices (element type -> type index)
  gc_array_types : Map[String, UInt]
  // wasm-gc struct type indices (struct name -> type index)
  gc_struct_types : Map[String, UInt]
  // wasm-gc struct field indices (struct name -> (field name -> field index))
  gc_struct_fields : Map[String, Map[String, UInt]]
}

///|
// / create
fn CodeGenCtx::new(
  funcs : Map[String, UInt],
  interfaces : Map[String, Array[(String, @ast.TsType)]],
  import_types : Map[String, (Array[@ast.TsType], @ast.TsType)],
  func_types : Map[String, (Array[@ast.TsType], @ast.TsType)],
  string_pool : StringPool,
  builtins_used : Map[String, Bool],
) -> CodeGenCtx {
  {
    locals: {},
    local_types: [],
    next_local: 0,
    funcs,
    func_types,
    interfaces,
    import_types,
    instrs: [],
    loop_depth: 0,
    string_pool,
    builtins_used,
    const_values: {},
    use_gc: false,
    gc_array_types: {},
    gc_struct_types: {},
    gc_struct_fields: {},
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
/// @ast.TsType → ValType for wasm-gc mode
/// Uses ref types for arrays and structs
fn ts_type_to_valtype_gc(
  t : @ast.TsType,
  gc_array_types : Map[String, UInt],
  gc_struct_types : Map[String, UInt],
) -> @core.ValType {
  match t {
    @ast.TsType::Number => F64
    @ast.TsType::Int => I32
    @ast.TsType::Boolean => I32
    @ast.TsType::String_ => I32 // string (still i32 pointer for now)
    @ast.TsType::Array(elem_type) => {
      // Get GC array type index based on element type
      let type_key = if is_f64_type(elem_type) { "f64" } else { "i32" }
      match gc_array_types.get(type_key) {
        Some(type_idx) =>
          @core.ValType::Ref(
            @core.RefType::TypeIndex(type_idx.reinterpret_as_int()),
            true, // nullable
          )
        None => I32 // fallback
      }
    }
    @ast.TsType::Named(name) =>
      // Struct reference
      match gc_struct_types.get(name) {
        Some(type_idx) =>
          @core.ValType::Ref(
            @core.RefType::TypeIndex(type_idx.reinterpret_as_int()),
            true, // nullable
          )
        None => I32 // fallback for unknown types
      }
    @ast.TsType::Void => I32 // void
    _ => F64 // f64
  }
}

///|
// / @ast.TsType f64 (Any も F64 として扱う)
fn is_f64_type(t : @ast.TsType) -> Bool {
  match t {
    @ast.TsType::Number | @ast.TsType::Any => true
    _ => false
  }
}

///|
// / numeric/boolean coercion for codegen
fn emit_coerce(
  ctx : CodeGenCtx,
  from_type : @ast.TsType,
  to_type : @ast.TsType,
) -> Unit {
  if from_type == to_type {
    return
  }
  match (from_type, to_type) {
    // i32 -> f64 (including Any treated as f64)
    (@ast.TsType::Int, @ast.TsType::Any)
    | (@ast.TsType::Boolean, @ast.TsType::Any) => ctx.emit(F64ConvertI32S)
    // f64 (Any) -> i32/bool
    (@ast.TsType::Any, @ast.TsType::Int) => ctx.emit(I32TruncF64S)
    (@ast.TsType::Any, @ast.TsType::Boolean) => {
      ctx.emit(F64Const(0.0))
      ctx.emit(F64Ne)
    }
    // i32 -> f64
    (@ast.TsType::Int, @ast.TsType::Number)
    | (@ast.TsType::Boolean, @ast.TsType::Number) => ctx.emit(F64ConvertI32S)
    // f64 -> i32
    (@ast.TsType::Number, @ast.TsType::Int) => ctx.emit(I32TruncF64S)
    // f64 -> bool (non-zero)
    (@ast.TsType::Number, @ast.TsType::Boolean) => {
      ctx.emit(F64Const(0.0))
      ctx.emit(F64Ne)
    }
    // i32 -> bool (non-zero)
    (@ast.TsType::Int, @ast.TsType::Boolean) => {
      ctx.emit(I32Const(0U))
      ctx.emit(I32Ne)
    }
    _ => ()
  }
}

///|
/// Unify two types for codegen, preferring the more specific one.
fn codegen_unify_types(t1 : @ast.TsType, t2 : @ast.TsType) -> @ast.TsType {
  if t1 == t2 {
    return t1
  }
  match (t1, t2) {
    (@ast.TsType::Any, t) => t
    (t, @ast.TsType::Any) => t
    (@ast.TsType::Number, @ast.TsType::Int) => @ast.TsType::Number
    (@ast.TsType::Int, @ast.TsType::Number) => @ast.TsType::Number
    _ => t1
  }
}

///|
/// Get typeof string when it is statically known.
fn typeof_string_for_type(t : @ast.TsType) -> String? {
  match t {
    @ast.TsType::String_ | @ast.TsType::Literal(_) => Some("string")
    @ast.TsType::Number | @ast.TsType::Int => Some("number")
    @ast.TsType::Boolean => Some("boolean")
    @ast.TsType::Undefined | @ast.TsType::Void => Some("undefined")
    @ast.TsType::Func(_, _) => Some("function")
    @ast.TsType::Null => Some("object")
    @ast.TsType::Object(_)
    | @ast.TsType::Array(_)
    | @ast.TsType::Tuple(_)
    | @ast.TsType::Struct(_, _) => Some("object")
    @ast.TsType::Symbol => Some("symbol")
    @ast.TsType::BigInt => Some("bigint")
    @ast.TsType::Union(types) => {
      let mut kind : String? = None
      for t in types {
        match typeof_string_for_type(t) {
          Some(k) =>
            match kind {
              None => kind = Some(k)
              Some(prev) => if prev != k { return None }
            }
          None => return None
        }
      }
      kind
    }
    @ast.TsType::Intersection(types) => {
      let mut kind : String? = None
      for t in types {
        match typeof_string_for_type(t) {
          Some(k) =>
            match kind {
              None => kind = Some(k)
              Some(prev) => if prev != k { return None }
            }
          None => return None
        }
      }
      kind
    }
    _ => None
  }
}

///|
/// Unify numeric types for codegen, preferring Number over Int.
fn codegen_unify_numeric(t1 : @ast.TsType, t2 : @ast.TsType) -> @ast.TsType {
  match (t1, t2) {
    (@ast.TsType::Number, _) => @ast.TsType::Number
    (_, @ast.TsType::Number) => @ast.TsType::Number
    (@ast.TsType::Int, _) => @ast.TsType::Int
    (_, @ast.TsType::Int) => @ast.TsType::Int
    (@ast.TsType::Any, t) => t
    (t, @ast.TsType::Any) => t
    _ => t1
  }
}

///|
// / expressiontype
fn infer_type(ctx : CodeGenCtx, expr : @ast.TsExpr) -> @ast.TsType {
  match expr {
    // Number literals are f64; IntLit is i32
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
    @ast.TsExpr::TemplateLiteral(_, _) => @ast.TsType::String_
    @ast.TsExpr::TaggedTemplate(_, _, _, _) => @ast.TsType::Any
    @ast.TsExpr::Var(name) =>
      match ctx.get_local(name) {
        Some(local_var) => local_var.type_
        None => @ast.TsType::Any
      }
    @ast.TsExpr::BinOp(op, left, right) =>
      match op {
        // Comparison operators return Boolean
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
        // Logical operators return operand type (not Boolean)
        @ast.TsBinOp::And | @ast.TsBinOp::Or => {
          let left_t = infer_type(ctx, left)
          let right_t = infer_type(ctx, right)
          codegen_unify_types(left_t, right_t)
        }
        @ast.TsBinOp::Coalesce => {
          let left_t = infer_type(ctx, left)
          let right_t = infer_type(ctx, right)
          match left_t {
            @ast.TsType::Any | @ast.TsType::Null | @ast.TsType::Undefined =>
              right_t
            _ => codegen_unify_types(left_t, right_t)
          }
        }
        // Bitwise operators return Int
        @ast.TsBinOp::BitAnd
        | @ast.TsBinOp::BitOr
        | @ast.TsBinOp::BitXor
        | @ast.TsBinOp::Shl
        | @ast.TsBinOp::Shr
        | @ast.TsBinOp::UShr => @ast.TsType::Int
        // Add: string if either operand is string
        @ast.TsBinOp::Add => {
          let left_t = infer_type(ctx, left)
          let right_t = infer_type(ctx, right)
          if left_t == @ast.TsType::String_ || right_t == @ast.TsType::String_ {
            @ast.TsType::String_
          } else {
            codegen_unify_numeric(left_t, right_t)
          }
        }
        // Arithmetic operators: promote to wider numeric type
        @ast.TsBinOp::Sub
        | @ast.TsBinOp::Mul
        | @ast.TsBinOp::Div
        | @ast.TsBinOp::Mod
        | @ast.TsBinOp::Pow => {
          let left_t = infer_type(ctx, left)
          let right_t = infer_type(ctx, right)
          codegen_unify_numeric(left_t, right_t)
        }
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
    @ast.TsExpr::Call(name, _) =>
      match ctx.import_types.get(name) {
        Some((_, return_type)) => return_type
        None =>
          match ctx.func_types.get(name) {
            Some((_, return_type)) => return_type
            None => @ast.TsType::Any
          }
      }
    @ast.TsExpr::CallExpr(_, _) => @ast.TsType::Any
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
            "charAt" | "substring" | "slice" | "substr" => @ast.TsType::String_
            "concat" | "repeat" | "trim" | "toLowerCase" | "toUpperCase" =>
              @ast.TsType::String_
            "charCodeAt" | "indexOf" | "lastIndexOf" | "localeCompare" =>
              @ast.TsType::Int
            "split" => @ast.TsType::Array(@ast.TsType::String_)
            "startsWith" | "endsWith" | "includes" => @ast.TsType::Boolean
            _ => @ast.TsType::Any
          }
        @ast.TsType::Array(elem_type) =>
          match method_name {
            "push" | "unshift" | "indexOf" | "lastIndexOf" | "findIndex" =>
              @ast.TsType::Int
            "pop" | "shift" | "find" | "at" => elem_type
            "slice" | "concat" | "filter" | "reverse" | "sort" | "fill" =>
              @ast.TsType::Array(elem_type)
            "map" => @ast.TsType::Array(@ast.TsType::Any) // Return type depends on callback
            "join" => @ast.TsType::String_
            "includes" | "every" | "some" => @ast.TsType::Boolean
            "reduce" | "reduceRight" => @ast.TsType::Any
            _ => @ast.TsType::Any
          }
        @ast.TsType::Number | @ast.TsType::Int =>
          match method_name {
            "toString" | "toFixed" | "toExponential" | "toPrecision" =>
              @ast.TsType::String_
            _ => @ast.TsType::Any
          }
        _ => @ast.TsType::Any
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

///|
/// Get field type from interface map by type name and field name
fn field_type_from_interface(
  interfaces : Map[String, Array[(String, @ast.TsType)]],
  type_name : String,
  field_name : String,
) -> @ast.TsType? {
  match interfaces.get(type_name) {
    Some(fields) => field_type(fields, field_name)
    None => None
  }
}

// ============================================
// expressioncodegen
// ============================================

///|
/// Try to emit a constant value directly.
/// Returns true if the value was emitted, false otherwise.
fn try_emit_const(
  ctx : CodeGenCtx,
  expr : @ast.TsExpr,
  expected_type : @ast.TsType,
) -> Bool {
  match @analysis.eval_const(expr) {
    @analysis.ConstValue::Int(n) => {
      if is_f64_type(expected_type) {
        ctx.emit(F64Const(n.to_double()))
      } else {
        ctx.emit(I32Const(n.reinterpret_as_uint()))
      }
      true
    }
    @analysis.ConstValue::Number(n) => {
      if is_f64_type(expected_type) {
        ctx.emit(F64Const(n))
      } else {
        ctx.emit(I32Const(n.to_int().reinterpret_as_uint()))
      }
      true
    }
    @analysis.ConstValue::Boolean(b) => {
      ctx.emit(I32Const(if b { 1U } else { 0U }))
      true
    }
    @analysis.ConstValue::String_(s) => {
      let offset = ctx.string_pool.add(s)
      ctx.emit(I32Const(offset.reinterpret_as_uint()))
      true
    }
    @analysis.ConstValue::Null | @analysis.ConstValue::Undefined => {
      ctx.emit(I32Const(0U))
      true
    }
    @analysis.ConstValue::NotConst => false
  }
}

///|
// / expression
fn compile_expr(
  ctx : CodeGenCtx,
  expr : @ast.TsExpr,
  expected_type : @ast.TsType,
) -> Unit raise CodeGenError {
  // Try constant folding first for binary/unary operations
  match expr {
    @ast.TsExpr::BinOp(_, _, _) | @ast.TsExpr::UnaryOp(_, _) =>
      if try_emit_const(ctx, expr, expected_type) {
        return
      }
    _ => ()
  }
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
      // Constant propagation: emit constant directly if known
      match ctx.const_values.get(name) {
        Some(@analysis.ConstValue::Int(n)) =>
          if is_f64_type(expected_type) {
            ctx.emit(F64Const(n.to_double()))
          } else {
            ctx.emit(I32Const(n.reinterpret_as_uint()))
          }
        Some(@analysis.ConstValue::Number(f)) => ctx.emit(F64Const(f))
        Some(@analysis.ConstValue::Boolean(b)) =>
          ctx.emit(I32Const(if b { 1U } else { 0U }))
        Some(@analysis.ConstValue::String_(s)) => {
          let offset = ctx.string_pool.add(s)
          ctx.emit(I32Const(offset.reinterpret_as_uint()))
        }
        Some(@analysis.ConstValue::Null)
        | Some(@analysis.ConstValue::Undefined) => ctx.emit(I32Const(0U)) // null/undefined as 0
        Some(@analysis.ConstValue::NotConst) | None =>
          match ctx.get_local(name) {
            Some(local_var) => {
              ctx.emit(LocalGet(local_var.index))
              emit_coerce(ctx, local_var.type_, expected_type)
            }
            None => raise CodeGenError("Undefined variable: \{name}")
          }
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
    @ast.TsExpr::TemplateLiteral(parts, exprs) => {
      if parts.length() == 0 {
        raise CodeGenError("template literal must have at least one part")
      }
      let mut acc : @ast.TsExpr = @ast.TsExpr::StringLit(parts[0])
      for i in 0..<exprs.length() {
        let name = store_string_expr(ctx, exprs[i])
        acc = @ast.TsExpr::BinOp(@ast.TsBinOp::Add, acc, @ast.TsExpr::Var(name))
        if i + 1 < parts.length() {
          let part = parts[i + 1]
          if part.length() > 0 {
            acc = @ast.TsExpr::BinOp(
              @ast.TsBinOp::Add,
              acc,
              @ast.TsExpr::StringLit(part),
            )
          }
        }
      }
      compile_expr(ctx, acc, @ast.TsType::String_)
    }
    @ast.TsExpr::TaggedTemplate(_, _, _, _) =>
      raise CodeGenError(
        "tagged templates are not supported in Wasm compiler (use interpreter)",
      )
    @ast.TsExpr::Seq(left, right) => {
      let left_type = infer_type(ctx, left)
      compile_expr(ctx, left, left_type)
      ctx.emit(Drop)
      compile_expr(ctx, right, expected_type)
    }
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
    @ast.TsExpr::Call(name, args) => {
      let return_type = compile_call(ctx, name, args, expected_type)
      emit_coerce(ctx, return_type, expected_type)
    }
    @ast.TsExpr::CallExpr(_, _) =>
      raise CodeGenError("call expression is not supported in Wasm compiler")
    @ast.TsExpr::Cond(cond, then_expr, else_expr) => {
      // Try constant folding on condition
      match @analysis.eval_const(cond) {
        @analysis.ConstValue::Boolean(true)
        | @analysis.ConstValue::Int(_)
        | @analysis.ConstValue::Number(_)
        | @analysis.ConstValue::String_(_) => {
          // Truthy - only compile then branch
          compile_expr(ctx, then_expr, expected_type)
          return
        }
        @analysis.ConstValue::Boolean(false)
        | @analysis.ConstValue::Null
        | @analysis.ConstValue::Undefined => {
          // Falsy - only compile else branch
          compile_expr(ctx, else_expr, expected_type)
          return
        }
        @analysis.ConstValue::NotConst => ()
      }
      // Dynamic condition
      compile_expr(ctx, cond, @ast.TsType::Boolean)
      let then_ctx : CodeGenCtx = {
        locals: ctx.locals,
        local_types: ctx.local_types,
        next_local: ctx.next_local,
        funcs: ctx.funcs,
        func_types: ctx.func_types,
        interfaces: ctx.interfaces,
        import_types: ctx.import_types,
        instrs: [],
        loop_depth: ctx.loop_depth,
        string_pool: ctx.string_pool,
        builtins_used: ctx.builtins_used,
        const_values: ctx.const_values,
        use_gc: ctx.use_gc,
        gc_array_types: ctx.gc_array_types,
        gc_struct_types: ctx.gc_struct_types,
        gc_struct_fields: ctx.gc_struct_fields,
      }
      compile_expr(then_ctx, then_expr, expected_type)
      let else_ctx : CodeGenCtx = {
        locals: ctx.locals,
        local_types: ctx.local_types,
        next_local: ctx.next_local,
        funcs: ctx.funcs,
        func_types: ctx.func_types,
        interfaces: ctx.interfaces,
        import_types: ctx.import_types,
        instrs: [],
        loop_depth: ctx.loop_depth,
        string_pool: ctx.string_pool,
        builtins_used: ctx.builtins_used,
        const_values: ctx.const_values,
        use_gc: ctx.use_gc,
        gc_array_types: ctx.gc_array_types,
        gc_struct_types: ctx.gc_struct_types,
        gc_struct_fields: ctx.gc_struct_fields,
      }
      compile_expr(else_ctx, else_expr, expected_type)
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
    @ast.TsExpr::ObjectLit(fields) =>
      compile_object_lit(ctx, fields, expected_type)
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
fn const_key_to_string(key_expr : @ast.TsExpr) -> String? {
  match @analysis.eval_const(key_expr) {
    @analysis.ConstValue::String_(s) => Some(s)
    @analysis.ConstValue::Int(n) => Some(n.to_string())
    @analysis.ConstValue::Number(n) => Some(n.to_string())
    @analysis.ConstValue::Boolean(b) => Some(if b { "true" } else { "false" })
    @analysis.ConstValue::Null => Some("null")
    @analysis.ConstValue::Undefined => Some("undefined")
    @analysis.ConstValue::NotConst => None
  }
}

///|
fn resolve_object_lit_field(
  key : String,
  value : @ast.TsExpr,
) -> (String, @ast.TsExpr) raise CodeGenError {
  if key.has_prefix("@@spread:") {
    raise CodeGenError(
      "object spread is not supported in Wasm compiler (use interpreter)",
    )
  }
  if key.has_prefix("@@get:") || key.has_prefix("@@set:") {
    raise CodeGenError(
      "object accessors are not supported in Wasm compiler (use interpreter)",
    )
  }
  if key.has_prefix("@@computed:") {
    match value {
      @ast.TsExpr::ComputedProp(key_expr, value_expr) =>
        match const_key_to_string(key_expr) {
          Some(prop_key) => (prop_key, value_expr)
          None =>
            raise CodeGenError(
              "computed property key must be constant in Wasm compiler",
            )
        }
      _ => raise CodeGenError("computed property missing ComputedProp wrapper")
    }
  } else {
    (key, value)
  }
}

///|
fn compile_object_lit(
  ctx : CodeGenCtx,
  fields : Array[(String, @ast.TsExpr)],
  expected_type : @ast.TsType,
) -> Unit raise CodeGenError {
  let type_name = match expected_type {
    @ast.TsType::Named(name) => name
    _ => raise CodeGenError("ObjectLit requires a named type in Wasm compiler")
  }
  let obj_local = ctx.add_temp_local(@ast.TsType::Named(type_name))
  compile_new_expr(ctx, type_name, [], expected_type)
  ctx.emit(LocalSet(obj_local))

  if ctx.use_gc {
    match ctx.gc_struct_types.get(type_name) {
      Some(type_idx) =>
        match ctx.gc_struct_fields.get(type_name) {
          Some(field_map) =>
            for item in fields {
              let (raw_key, raw_val) = item
              let (prop_key, value_expr) = resolve_object_lit_field(
                raw_key, raw_val,
              )
              match field_map.get(prop_key) {
                Some(field_idx) =>
                  match
                    field_type_from_interface(
                      ctx.interfaces,
                      type_name,
                      prop_key,
                    ) {
                    Some(ft) => {
                      ctx.emit(LocalGet(obj_local))
                      compile_expr(ctx, value_expr, ft)
                      ctx.emit(StructSet(type_idx, field_idx))
                    }
                    None => raise CodeGenError("Field not found: \{prop_key}")
                  }
                None => raise CodeGenError("Unknown field: \{prop_key}")
              }
            }
          None => raise CodeGenError("Unknown struct fields: \{type_name}")
        }
      None => raise CodeGenError("Unknown gc struct type: \{type_name}")
    }
  } else {
    match ctx.interfaces.get(type_name) {
      Some(struct_fields) =>
        for item in fields {
          let (raw_key, raw_val) = item
          let (prop_key, value_expr) = resolve_object_lit_field(
            raw_key, raw_val,
          )
          match field_offset(struct_fields, prop_key) {
            Some(offset) =>
              match field_type(struct_fields, prop_key) {
                Some(ft) => {
                  ctx.emit(LocalGet(obj_local))
                  ctx.emit(I32Const(offset.reinterpret_as_uint()))
                  ctx.emit(I32Add)
                  compile_expr(ctx, value_expr, ft)
                  if is_f64_type(ft) {
                    ctx.emit(F64Store(3U, 0U, 0U))
                  } else {
                    ctx.emit(I32Store(2U, 0U, 0U))
                  }
                }
                None => raise CodeGenError("Field not found: \{prop_key}")
              }
            None => raise CodeGenError("Unknown field: \{prop_key}")
          }
        }
      None => raise CodeGenError("Unknown struct type: \{type_name}")
    }
  }

  ctx.emit(LocalGet(obj_local))
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
  let length = elements.length()
  let mut has_spread = false
  for elem in elements {
    match elem {
      @ast.TsExpr::Spread(_) => {
        has_spread = true
        break
      }
      _ => ()
    }
  }

  // wasm-gc mode: use ArrayNewFixed
  if ctx.use_gc && !has_spread {
    // Check for spread elements
    for elem in elements {
      match elem {
        @ast.TsExpr::Spread(_) =>
          raise CodeGenError(
            "Spread is not supported in Wasm compiler (use interpreter)",
          )
        _ => ()
      }
    }
    // Push all elements onto stack
    for elem in elements {
      compile_expr(ctx, elem, elem_type)
    }
    // Get array type index for this element type
    let type_key = if is_f64_type(elem_type) { "f64" } else { "i32" }
    match ctx.gc_array_types.get(type_key) {
      Some(type_idx) =>
        ctx.emit(ArrayNewFixed(type_idx, length.reinterpret_as_uint()))
      None =>
        raise CodeGenError("wasm-gc array type not defined for: \{type_key}")
    }
    return
  }
  if ctx.use_gc {
    let total_len = ctx.add_temp_local(@ast.TsType::Int)
    ctx.emit(I32Const(0U))
    ctx.emit(LocalSet(total_len))
    let segments : Array[(Bool, UInt, UInt)] = []
    for elem in elements {
      match elem {
        @ast.TsExpr::Spread(inner) => {
          let arr_type = infer_type(ctx, inner)
          match arr_type {
            @ast.TsType::Array(_) => ()
            _ =>
              raise CodeGenError(
                "spread element must be an array in Wasm compiler",
              )
          }
          let arr_local = ctx.add_temp_local(arr_type)
          compile_expr(ctx, inner, arr_type)
          ctx.emit(LocalSet(arr_local))
          let len_local = ctx.add_temp_local(@ast.TsType::Int)
          ctx.emit(LocalGet(arr_local))
          ctx.emit(ArrayLen)
          ctx.emit(LocalSet(len_local))
          ctx.emit(LocalGet(total_len))
          ctx.emit(LocalGet(len_local))
          ctx.emit(I32Add)
          ctx.emit(LocalSet(total_len))
          segments.push((true, arr_local, len_local))
        }
        _ => {
          compile_expr(ctx, elem, elem_type)
          let val_local = ctx.add_temp_local(elem_type)
          ctx.emit(LocalSet(val_local))
          ctx.emit(LocalGet(total_len))
          ctx.emit(I32Const(1U))
          ctx.emit(I32Add)
          ctx.emit(LocalSet(total_len))
          segments.push((false, val_local, 0U))
        }
      }
    }
    let type_key = if is_f64_type(elem_type) { "f64" } else { "i32" }
    let type_idx = match ctx.gc_array_types.get(type_key) {
      Some(idx) => idx
      None =>
        raise CodeGenError("wasm-gc array type not defined for: \{type_key}")
    }
    let arr_local = ctx.add_temp_local(@ast.TsType::Array(elem_type))
    ctx.emit(LocalGet(total_len))
    ctx.emit(ArrayNewDefault(type_idx))
    ctx.emit(LocalSet(arr_local))
    let idx_local = ctx.add_temp_local(@ast.TsType::Int)
    ctx.emit(I32Const(0U))
    ctx.emit(LocalSet(idx_local))
    for seg in segments {
      let (is_spread, a, b) = seg
      if is_spread {
        let i_local = ctx.add_temp_local(@ast.TsType::Int)
        ctx.emit(I32Const(0U))
        ctx.emit(LocalSet(i_local))
        let loop_instrs : Array[@core.Instr] = []
        loop_instrs.push(LocalGet(i_local))
        loop_instrs.push(LocalGet(b))
        loop_instrs.push(I32GeS)
        loop_instrs.push(BrIf(1U))
        loop_instrs.push(LocalGet(arr_local))
        loop_instrs.push(LocalGet(idx_local))
        loop_instrs.push(LocalGet(i_local))
        loop_instrs.push(I32Add)
        loop_instrs.push(LocalGet(a))
        loop_instrs.push(LocalGet(i_local))
        loop_instrs.push(ArrayGet(type_idx))
        loop_instrs.push(ArraySet(type_idx))
        loop_instrs.push(LocalGet(i_local))
        loop_instrs.push(I32Const(1U))
        loop_instrs.push(I32Add)
        loop_instrs.push(LocalSet(i_local))
        loop_instrs.push(Br(0U))
        ctx.emit(Block(Empty, [Loop(Empty, loop_instrs)]))
        ctx.emit(LocalGet(idx_local))
        ctx.emit(LocalGet(b))
        ctx.emit(I32Add)
        ctx.emit(LocalSet(idx_local))
      } else {
        ctx.emit(LocalGet(arr_local))
        ctx.emit(LocalGet(idx_local))
        ctx.emit(LocalGet(a))
        ctx.emit(ArraySet(type_idx))
        ctx.emit(LocalGet(idx_local))
        ctx.emit(I32Const(1U))
        ctx.emit(I32Add)
        ctx.emit(LocalSet(idx_local))
      }
    }
    ctx.emit(LocalGet(arr_local))
    return
  }

  // Linear memory mode (original implementation)
  let elem_sz = element_size(elem_type)
  if has_spread {
    let total_len = ctx.add_temp_local(@ast.TsType::Int)
    ctx.emit(I32Const(0U))
    ctx.emit(LocalSet(total_len))
    let segments : Array[(Bool, UInt, UInt)] = []
    for elem in elements {
      match elem {
        @ast.TsExpr::Spread(inner) => {
          let arr_type = infer_type(ctx, inner)
          match arr_type {
            @ast.TsType::Array(_) => ()
            _ =>
              raise CodeGenError(
                "spread element must be an array in Wasm compiler",
              )
          }
          let arr_local = ctx.add_temp_local(arr_type)
          compile_expr(ctx, inner, arr_type)
          ctx.emit(LocalSet(arr_local))
          let len_local = ctx.add_temp_local(@ast.TsType::Int)
          ctx.emit(LocalGet(arr_local))
          ctx.emit(I32Load(2U, 0U, 0U))
          ctx.emit(LocalSet(len_local))
          ctx.emit(LocalGet(total_len))
          ctx.emit(LocalGet(len_local))
          ctx.emit(I32Add)
          ctx.emit(LocalSet(total_len))
          segments.push((true, arr_local, len_local))
        }
        _ => {
          compile_expr(ctx, elem, elem_type)
          let val_local = ctx.add_temp_local(elem_type)
          ctx.emit(LocalSet(val_local))
          ctx.emit(LocalGet(total_len))
          ctx.emit(I32Const(1U))
          ctx.emit(I32Add)
          ctx.emit(LocalSet(total_len))
          segments.push((false, val_local, 0U))
        }
      }
    }
    let base_local = ctx.add_temp_local(@ast.TsType::Int)
    ctx.emit(GlobalGet(0U))
    ctx.emit(LocalSet(base_local))
    ctx.emit(LocalGet(base_local))
    ctx.emit(LocalGet(total_len))
    ctx.emit(I32Store(2U, 0U, 0U))
    let idx_local = ctx.add_temp_local(@ast.TsType::Int)
    ctx.emit(I32Const(0U))
    ctx.emit(LocalSet(idx_local))
    for seg in segments {
      let (is_spread, a, b) = seg
      if is_spread {
        let i_local = ctx.add_temp_local(@ast.TsType::Int)
        ctx.emit(I32Const(0U))
        ctx.emit(LocalSet(i_local))
        let loop_instrs : Array[@core.Instr] = []
        loop_instrs.push(LocalGet(i_local))
        loop_instrs.push(LocalGet(b))
        loop_instrs.push(I32GeS)
        loop_instrs.push(BrIf(1U))
        // dst
        loop_instrs.push(LocalGet(base_local))
        loop_instrs.push(I32Const(4U))
        loop_instrs.push(I32Add)
        loop_instrs.push(LocalGet(idx_local))
        loop_instrs.push(LocalGet(i_local))
        loop_instrs.push(I32Add)
        loop_instrs.push(I32Const(elem_sz.reinterpret_as_uint()))
        loop_instrs.push(I32Mul)
        loop_instrs.push(I32Add)
        // src
        loop_instrs.push(LocalGet(a))
        loop_instrs.push(I32Const(4U))
        loop_instrs.push(I32Add)
        loop_instrs.push(LocalGet(i_local))
        loop_instrs.push(I32Const(elem_sz.reinterpret_as_uint()))
        loop_instrs.push(I32Mul)
        loop_instrs.push(I32Add)
        if is_f64_type(elem_type) {
          loop_instrs.push(F64Load(3U, 0U, 0U))
          loop_instrs.push(F64Store(3U, 0U, 0U))
        } else {
          loop_instrs.push(I32Load(2U, 0U, 0U))
          loop_instrs.push(I32Store(2U, 0U, 0U))
        }
        loop_instrs.push(LocalGet(i_local))
        loop_instrs.push(I32Const(1U))
        loop_instrs.push(I32Add)
        loop_instrs.push(LocalSet(i_local))
        loop_instrs.push(Br(0U))
        ctx.emit(Block(Empty, [Loop(Empty, loop_instrs)]))
        ctx.emit(LocalGet(idx_local))
        ctx.emit(LocalGet(b))
        ctx.emit(I32Add)
        ctx.emit(LocalSet(idx_local))
      } else {
        ctx.emit(LocalGet(base_local))
        ctx.emit(I32Const(4U))
        ctx.emit(I32Add)
        ctx.emit(LocalGet(idx_local))
        ctx.emit(I32Const(elem_sz.reinterpret_as_uint()))
        ctx.emit(I32Mul)
        ctx.emit(I32Add)
        ctx.emit(LocalGet(a))
        if is_f64_type(elem_type) {
          ctx.emit(F64Store(3U, 0U, 0U))
        } else {
          ctx.emit(I32Store(2U, 0U, 0U))
        }
        ctx.emit(LocalGet(idx_local))
        ctx.emit(I32Const(1U))
        ctx.emit(I32Add)
        ctx.emit(LocalSet(idx_local))
      }
    }
    ctx.emit(LocalGet(base_local))
    ctx.emit(I32Const(4U))
    ctx.emit(I32Add)
    ctx.emit(LocalGet(total_len))
    ctx.emit(I32Const(elem_sz.reinterpret_as_uint()))
    ctx.emit(I32Mul)
    ctx.emit(I32Add)
    ctx.emit(GlobalSet(0U))
    ctx.emit(LocalGet(base_local))
    return
  }

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

  // wasm-gc mode: use ArrayGet
  if ctx.use_gc {
    compile_expr(ctx, arr, arr_type) // array reference
    compile_expr(ctx, index, @ast.TsType::Int) // index
    let type_key = if is_f64_type(elem_type) { "f64" } else { "i32" }
    match ctx.gc_array_types.get(type_key) {
      Some(type_idx) => ctx.emit(ArrayGet(type_idx))
      None =>
        raise CodeGenError("wasm-gc array type not defined for: \{type_key}")
    }
    emit_coerce(ctx, elem_type, expected_type)
    return
  }

  // Linear memory mode (original implementation)
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
  emit_coerce(ctx, elem_type, expected_type)
}

///|
// / property
fn compile_prop_access(
  ctx : CodeGenCtx,
  obj : @ast.TsExpr,
  prop : String,
  expected_type : @ast.TsType,
) -> Unit raise CodeGenError {
  let obj_type = infer_type(ctx, obj)

  // array/string length property
  match obj_type {
    @ast.TsType::Array(_) =>
      if prop == "length" {
        compile_expr(ctx, obj, obj_type)
        // wasm-gc mode: use ArrayLen
        if ctx.use_gc {
          ctx.emit(ArrayLen)
        } else {
          ctx.emit(I32Load(2U, 0U, 0U)) // 4 = length
        }
        emit_coerce(ctx, @ast.TsType::Int, expected_type)
        return
      }
    @ast.TsType::String_ =>
      if prop == "length" {
        compile_expr(ctx, obj, obj_type)
        ctx.emit(I32Load(2U, 0U, 0U)) // 4 = length
        emit_coerce(ctx, @ast.TsType::Int, expected_type)
        return
      }
    @ast.TsType::Named(type_name) =>
      // wasm-gc mode: use StructGet
      if ctx.use_gc {
        match ctx.gc_struct_types.get(type_name) {
          Some(type_idx) =>
            match ctx.gc_struct_fields.get(type_name) {
              Some(field_map) =>
                match field_map.get(prop) {
                  Some(field_idx) => {
                    compile_expr(ctx, obj, obj_type) // struct reference
                    ctx.emit(StructGet(type_idx, field_idx))
                    return
                  }
                  None => ()
                }
              None => ()
            }
          None => ()
        }
      } else {
        // Linear memory mode
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
    if args.length() < 1 {
      raise CodeGenError("Array constructor requires size argument")
    }

    // wasm-gc mode: use ArrayNewDefault
    if ctx.use_gc {
      // Get the GC array type index
      let type_key = if is_f64_type(elem_type) { "f64" } else { "i32" }
      match ctx.gc_array_types.get(type_key) {
        Some(type_idx) => {
          // Compile size expression
          compile_expr(ctx, args[0], @ast.TsType::Int)
          // ArrayNewDefault creates an array with default values
          ctx.emit(ArrayNewDefault(type_idx))
        }
        None => raise CodeGenError("Unknown gc array type: \{type_key}")
      }
      return
    }

    // Linear memory mode
    let elem_sz = element_size(elem_type)

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
    // wasm-gc mode: use StructNewDefault
    if ctx.use_gc {
      match ctx.gc_struct_types.get(type_name) {
        Some(type_idx) => ctx.emit(StructNewDefault(type_idx))
        None => raise CodeGenError("Unknown gc struct type: \{type_name}")
      }
      return
    }
    // Linear memory mode
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
  // Check for Math object methods first
  match receiver {
    @ast.TsExpr::Var("Math") => {
      compile_math_method(ctx, method_name, args)
      return
    }
    _ => ()
  }
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
/// Math object methods - mapped to wasm instructions
fn compile_math_method(
  ctx : CodeGenCtx,
  method_name : String,
  args : Array[@ast.TsExpr],
) -> Unit raise CodeGenError {
  match method_name {
    // Single argument functions
    "abs" => {
      if args.length() < 1 {
        raise CodeGenError("Math.abs requires 1 argument")
      }
      compile_expr(ctx, args[0], @ast.TsType::Number)
      ctx.emit(F64Abs)
    }
    "sqrt" => {
      if args.length() < 1 {
        raise CodeGenError("Math.sqrt requires 1 argument")
      }
      compile_expr(ctx, args[0], @ast.TsType::Number)
      ctx.emit(F64Sqrt)
    }
    "floor" => {
      if args.length() < 1 {
        raise CodeGenError("Math.floor requires 1 argument")
      }
      compile_expr(ctx, args[0], @ast.TsType::Number)
      ctx.emit(F64Floor)
    }
    "ceil" => {
      if args.length() < 1 {
        raise CodeGenError("Math.ceil requires 1 argument")
      }
      compile_expr(ctx, args[0], @ast.TsType::Number)
      ctx.emit(F64Ceil)
    }
    "trunc" => {
      if args.length() < 1 {
        raise CodeGenError("Math.trunc requires 1 argument")
      }
      compile_expr(ctx, args[0], @ast.TsType::Number)
      ctx.emit(F64Trunc)
    }
    "round" => {
      if args.length() < 1 {
        raise CodeGenError("Math.round requires 1 argument")
      }
      compile_expr(ctx, args[0], @ast.TsType::Number)
      ctx.emit(F64Nearest)
    }
    // Two argument functions
    "min" => {
      if args.length() < 2 {
        raise CodeGenError("Math.min requires 2 arguments")
      }
      compile_expr(ctx, args[0], @ast.TsType::Number)
      compile_expr(ctx, args[1], @ast.TsType::Number)
      ctx.emit(F64Min)
    }
    "max" => {
      if args.length() < 2 {
        raise CodeGenError("Math.max requires 2 arguments")
      }
      compile_expr(ctx, args[0], @ast.TsType::Number)
      compile_expr(ctx, args[1], @ast.TsType::Number)
      ctx.emit(F64Max)
    }
    "pow" => {
      // Math.pow(base, exp) - special case for integer exponents
      if args.length() < 2 {
        raise CodeGenError("Math.pow requires 2 arguments")
      }
      // Check if exponent is a constant integer for optimization
      match args[1] {
        @ast.TsExpr::NumberLit(n) => {
          let exp_int = n.to_int()
          if n == exp_int.to_double() && exp_int >= 0 && exp_int <= 10 {
            // Small integer exponent - unroll multiplication
            compile_expr(ctx, args[0], @ast.TsType::Number)
            if exp_int == 0 {
              ctx.emit(Drop)
              ctx.emit(F64Const(1.0))
            } else if exp_int == 1 {
              // base^1 = base, already on stack
              ()
            } else {
              // base^n = base * base * ... (n times)
              let base_local = ctx.add_local(
                "__pow_base__",
                @ast.TsType::Number,
              )
              ctx.emit(LocalTee(base_local))
              for _ in 1..<exp_int {
                ctx.emit(LocalGet(base_local))
                ctx.emit(F64Mul)
              }
            }
            return
          }
        }
        _ => ()
      }
      // General case: use loop-based power
      compile_pow_general(ctx, args[0], args[1])
    }
    "sign" => {
      // Math.sign(x) - returns -1, 0, or 1
      if args.length() < 1 {
        raise CodeGenError("Math.sign requires 1 argument")
      }
      compile_expr(ctx, args[0], @ast.TsType::Number)
      let x_local = ctx.add_local("__sign_x__", @ast.TsType::Number)
      ctx.emit(LocalTee(x_local))
      // if x > 0: 1, else if x < 0: -1, else: 0
      ctx.emit(F64Const(0.0))
      ctx.emit(F64Gt)
      ctx.emit(
        If(@core.BlockType::Value(F64), [F64Const(1.0)], [
          LocalGet(x_local),
          F64Const(0.0),
          F64Lt,
          If(@core.BlockType::Value(F64), [F64Const(-1.0)], [F64Const(0.0)]),
        ]),
      )
    }
    "fround" => {
      // Math.fround(x) - round to 32-bit float
      if args.length() < 1 {
        raise CodeGenError("Math.fround requires 1 argument")
      }
      compile_expr(ctx, args[0], @ast.TsType::Number)
      ctx.emit(F32DemoteF64)
      ctx.emit(F64PromoteF32)
    }
    _ =>
      raise CodeGenError(
        "Math.\{method_name} is not supported in Wasm compiler",
      )
  }
}

///|
/// General power function using loop
fn compile_pow_general(
  ctx : CodeGenCtx,
  base : @ast.TsExpr,
  exp : @ast.TsExpr,
) -> Unit raise CodeGenError {
  // result = 1, while (exp > 0) { result *= base; exp--; }
  compile_expr(ctx, base, @ast.TsType::Number)
  let base_local = ctx.add_local("__pow_base__", @ast.TsType::Number)
  ctx.emit(LocalSet(base_local))
  compile_expr(ctx, exp, @ast.TsType::Number)
  ctx.emit(F64Floor) // Ensure integer exponent
  ctx.emit(I32TruncF64S)
  let exp_local = ctx.add_local("__pow_exp__", @ast.TsType::Int)
  ctx.emit(LocalSet(exp_local))
  ctx.emit(F64Const(1.0))
  let result_local = ctx.add_local("__pow_result__", @ast.TsType::Number)
  ctx.emit(LocalSet(result_local))

  // Loop: while exp > 0
  let loop_body : Array[@core.Instr] = [
    LocalGet(exp_local),
    I32Const(0U),
    I32GtS,
    If(
      @core.BlockType::Empty,
      [
        // result *= base
        LocalGet(result_local),
        LocalGet(base_local),
        F64Mul,
        LocalSet(result_local),
        // exp--
        LocalGet(exp_local),
        I32Const(1U),
        I32Sub,
        LocalSet(exp_local),
        // continue loop
        Br(1U),
      ],
      [],
    ),
  ]
  ctx.emit(Loop(@core.BlockType::Empty, loop_body))
  ctx.emit(LocalGet(result_local))
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

  // result base pointer
  ctx.emit(GlobalGet(0U))
  let result_local = ctx.add_temp_local(@ast.TsType::Int)
  ctx.emit(LocalSet(result_local))

  // length
  ctx.emit(LocalGet(result_local))
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
  loop1.push(LocalGet(result_local))
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
  loop2.push(LocalGet(result_local))
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
  ctx.emit(LocalGet(result_local))
  ctx.emit(I32Const(4U))
  ctx.emit(I32Add)
  ctx.emit(LocalGet(total_len))
  ctx.emit(I32Add)
  ctx.emit(I32Const(3U))
  ctx.emit(I32Add)
  ctx.emit(I32Const(0xFFFFFFFCU))
  ctx.emit(I32And)
  ctx.emit(GlobalSet(0U))
  ctx.emit(LocalGet(result_local))
}

///|
fn emit_string_literal(ctx : CodeGenCtx, s : String) -> Unit {
  let offset = ctx.string_pool.add(s)
  ctx.emit(I32Const(offset.reinterpret_as_uint()))
}

///|
fn emit_int_to_string_from_local(ctx : CodeGenCtx, value_local : UInt) -> Unit {
  let sign_local = ctx.add_temp_local(@ast.TsType::Int)
  let abs_local = ctx.add_temp_local(@ast.TsType::Int)
  let tmp_local = ctx.add_temp_local(@ast.TsType::Int)
  let count_local = ctx.add_temp_local(@ast.TsType::Int)
  let total_len_local = ctx.add_temp_local(@ast.TsType::Int)
  let base_local = ctx.add_temp_local(@ast.TsType::Int)
  let write_local = ctx.add_temp_local(@ast.TsType::Int)
  let digit_local = ctx.add_temp_local(@ast.TsType::Int)

  // sign = value < 0 ? 1 : 0
  ctx.emit(LocalGet(value_local))
  ctx.emit(I32Const(0U))
  ctx.emit(I32LtS)
  ctx.emit(If(Value(I32), [I32Const(1U)], [I32Const(0U)]))
  ctx.emit(LocalSet(sign_local))

  // abs = sign ? (0 - value) : value
  ctx.emit(LocalGet(sign_local))
  ctx.emit(I32Eqz)
  ctx.emit(
    If(Value(I32), [LocalGet(value_local)], [
      I32Const(0U),
      LocalGet(value_local),
      I32Sub,
    ]),
  )
  ctx.emit(LocalSet(abs_local))

  let result_local = ctx.add_temp_local(@ast.TsType::String_)

  // if abs == 0 -> "0"
  ctx.emit(LocalGet(abs_local))
  ctx.emit(I32Eqz)
  let zero_ptr = ctx.string_pool.add("0")
  let then_instrs : Array[@core.Instr] = [
    I32Const(zero_ptr.reinterpret_as_uint()),
    LocalSet(result_local),
  ]

  let else_instrs : Array[@core.Instr] = []
  // tmp = abs
  else_instrs.push(LocalGet(abs_local))
  else_instrs.push(LocalSet(tmp_local))
  else_instrs.push(I32Const(0U))
  else_instrs.push(LocalSet(count_local))

  let count_loop : Array[@core.Instr] = []
  count_loop.push(LocalGet(tmp_local))
  count_loop.push(I32Eqz)
  count_loop.push(BrIf(1U))
  count_loop.push(LocalGet(count_local))
  count_loop.push(I32Const(1U))
  count_loop.push(I32Add)
  count_loop.push(LocalSet(count_local))
  count_loop.push(LocalGet(tmp_local))
  count_loop.push(I32Const(10U))
  count_loop.push(I32DivS)
  count_loop.push(LocalSet(tmp_local))
  count_loop.push(Br(0U))
  else_instrs.push(Block(Empty, [Loop(Empty, count_loop)]))

  // total_len = digits + sign
  else_instrs.push(LocalGet(count_local))
  else_instrs.push(LocalGet(sign_local))
  else_instrs.push(I32Add)
  else_instrs.push(LocalSet(total_len_local))

  // base = heap
  else_instrs.push(GlobalGet(0U))
  else_instrs.push(LocalSet(base_local))
  // store length
  else_instrs.push(LocalGet(base_local))
  else_instrs.push(LocalGet(total_len_local))
  else_instrs.push(I32Store(2U, 0U, 0U))

  // write_ptr = base + 4 + total_len - 1
  else_instrs.push(LocalGet(base_local))
  else_instrs.push(I32Const(4U))
  else_instrs.push(I32Add)
  else_instrs.push(LocalGet(total_len_local))
  else_instrs.push(I32Add)
  else_instrs.push(I32Const(1U))
  else_instrs.push(I32Sub)
  else_instrs.push(LocalSet(write_local))

  // tmp = abs
  else_instrs.push(LocalGet(abs_local))
  else_instrs.push(LocalSet(tmp_local))

  let digit_loop : Array[@core.Instr] = []
  digit_loop.push(LocalGet(tmp_local))
  digit_loop.push(I32Eqz)
  digit_loop.push(BrIf(1U))
  digit_loop.push(LocalGet(tmp_local))
  digit_loop.push(I32Const(10U))
  digit_loop.push(I32RemS)
  digit_loop.push(LocalSet(digit_local))
  digit_loop.push(LocalGet(write_local))
  digit_loop.push(LocalGet(digit_local))
  digit_loop.push(I32Const(48U))
  digit_loop.push(I32Add)
  digit_loop.push(I32Store8(0U, 0U, 0U))
  digit_loop.push(LocalGet(write_local))
  digit_loop.push(I32Const(1U))
  digit_loop.push(I32Sub)
  digit_loop.push(LocalSet(write_local))
  digit_loop.push(LocalGet(tmp_local))
  digit_loop.push(I32Const(10U))
  digit_loop.push(I32DivS)
  digit_loop.push(LocalSet(tmp_local))
  digit_loop.push(Br(0U))
  else_instrs.push(Block(Empty, [Loop(Empty, digit_loop)]))

  // write sign if needed
  else_instrs.push(LocalGet(sign_local))
  else_instrs.push(I32Eqz)
  let sign_else : Array[@core.Instr] = [
    LocalGet(base_local),
    I32Const(4U),
    I32Add,
    I32Const(45U),
    I32Store8(0U, 0U, 0U),
  ]
  else_instrs.push(If(Empty, [], sign_else))

  // update heap pointer
  else_instrs.push(LocalGet(base_local))
  else_instrs.push(I32Const(4U))
  else_instrs.push(I32Add)
  else_instrs.push(LocalGet(total_len_local))
  else_instrs.push(I32Add)
  else_instrs.push(I32Const(3U))
  else_instrs.push(I32Add)
  else_instrs.push(I32Const(0xFFFFFFFCU))
  else_instrs.push(I32And)
  else_instrs.push(GlobalSet(0U))

  // return base pointer
  else_instrs.push(LocalGet(base_local))
  else_instrs.push(LocalSet(result_local))

  ctx.emit(If(Empty, then_instrs, else_instrs))
  ctx.emit(LocalGet(result_local))
}

///|
fn compile_expr_to_string(
  ctx : CodeGenCtx,
  expr : @ast.TsExpr,
) -> Unit raise CodeGenError {
  match @analysis.eval_const(expr) {
    @analysis.ConstValue::String_(s) => {
      emit_string_literal(ctx, s)
      return
    }
    @analysis.ConstValue::Int(n) => {
      emit_string_literal(ctx, n.to_string())
      return
    }
    @analysis.ConstValue::Number(n) => {
      emit_string_literal(ctx, n.to_string())
      return
    }
    @analysis.ConstValue::Boolean(b) => {
      emit_string_literal(ctx, if b { "true" } else { "false" })
      return
    }
    @analysis.ConstValue::Null => {
      emit_string_literal(ctx, "null")
      return
    }
    @analysis.ConstValue::Undefined => {
      emit_string_literal(ctx, "undefined")
      return
    }
    @analysis.ConstValue::NotConst => ()
  }
  let expr_type = infer_type(ctx, expr)
  match expr_type {
    @ast.TsType::String_ => compile_expr(ctx, expr, @ast.TsType::String_)
    @ast.TsType::Boolean => {
      compile_expr(ctx, expr, @ast.TsType::Boolean)
      let true_ptr = ctx.string_pool.add("true")
      let false_ptr = ctx.string_pool.add("false")
      let result_local = ctx.add_temp_local(@ast.TsType::String_)
      let then_instrs : Array[@core.Instr] = [
        I32Const(true_ptr.reinterpret_as_uint()),
        LocalSet(result_local),
      ]
      let else_instrs : Array[@core.Instr] = [
        I32Const(false_ptr.reinterpret_as_uint()),
        LocalSet(result_local),
      ]
      ctx.emit(If(Empty, then_instrs, else_instrs))
      ctx.emit(LocalGet(result_local))
    }
    @ast.TsType::Int => {
      compile_expr(ctx, expr, @ast.TsType::Int)
      let value_local = ctx.add_temp_local(@ast.TsType::Int)
      ctx.emit(LocalSet(value_local))
      emit_int_to_string_from_local(ctx, value_local)
    }
    @ast.TsType::Number => {
      compile_expr(ctx, expr, @ast.TsType::Number)
      let num_local = ctx.add_temp_local(@ast.TsType::Number)
      ctx.emit(LocalSet(num_local))
      ctx.emit(LocalGet(num_local))
      ctx.emit(I32TruncF64S)
      let int_local = ctx.add_temp_local(@ast.TsType::Int)
      ctx.emit(LocalSet(int_local))
      emit_int_to_string_from_local(ctx, int_local)
    }
    @ast.TsType::Null => {
      compile_expr(ctx, expr, @ast.TsType::Any)
      ctx.emit(Drop)
      emit_string_literal(ctx, "null")
    }
    @ast.TsType::Undefined | @ast.TsType::Void => {
      compile_expr(ctx, expr, @ast.TsType::Any)
      ctx.emit(Drop)
      emit_string_literal(ctx, "undefined")
    }
    _ =>
      raise CodeGenError(
        "template literal ToString not supported for this type",
      )
  }
}

///|
fn store_string_expr(
  ctx : CodeGenCtx,
  expr : @ast.TsExpr,
) -> String raise CodeGenError {
  compile_expr_to_string(ctx, expr)
  let name = "__tpl_str_\{ctx.next_local.reinterpret_as_int().to_string()}"
  let idx = ctx.add_local(name, @ast.TsType::String_)
  ctx.emit(LocalSet(idx))
  name
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
      // wasm-gc mode: use StructSet
      if ctx.use_gc {
        match ctx.gc_struct_types.get(type_name) {
          Some(type_idx) =>
            match ctx.gc_struct_fields.get(type_name) {
              Some(field_map) =>
                match field_map.get(prop) {
                  Some(field_idx) =>
                    match
                      field_type_from_interface(ctx.interfaces, type_name, prop) {
                      Some(ft) => {
                        let val_local = ctx.add_temp_local(ft)
                        // Stack: structref, value
                        compile_expr(ctx, obj, obj_type) // struct reference
                        compile_expr(ctx, value, ft)
                        ctx.emit(LocalTee(val_local)) // Save value for return
                        ctx.emit(StructSet(type_idx, field_idx))
                        ctx.emit(LocalGet(val_local)) // Return assigned value
                        return
                      }
                      None => ()
                    }
                  None => ()
                }
              None => ()
            }
          None => ()
        }
      } else {
        // Linear memory mode
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

  // wasm-gc mode: use ArraySet
  if ctx.use_gc {
    let val_local = ctx.add_temp_local(elem_type)
    // Stack order for ArraySet: arrayref, index, value
    compile_expr(ctx, arr, arr_type)
    compile_expr(ctx, index, @ast.TsType::Int)
    compile_expr(ctx, value, elem_type)
    ctx.emit(LocalTee(val_local)) // Save value for return
    let type_key = if is_f64_type(elem_type) { "f64" } else { "i32" }
    match ctx.gc_array_types.get(type_key) {
      Some(type_idx) => ctx.emit(ArraySet(type_idx))
      None =>
        raise CodeGenError("wasm-gc array type not defined for: \{type_key}")
    }
    ctx.emit(LocalGet(val_local)) // Return the assigned value
    return
  }

  // Linear memory mode
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
    @ast.TsCompoundOp::PowAssign =>
      raise CodeGenError(
        "pow assignment (**=) is not supported in Wasm compiler (use interpreter)",
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
fn make_branch_ctx(ctx : CodeGenCtx) -> CodeGenCtx {
  {
    locals: ctx.locals,
    local_types: ctx.local_types,
    next_local: ctx.next_local,
    funcs: ctx.funcs,
    func_types: ctx.func_types,
    interfaces: ctx.interfaces,
    import_types: ctx.import_types,
    instrs: [],
    loop_depth: ctx.loop_depth,
    string_pool: ctx.string_pool,
    builtins_used: ctx.builtins_used,
    const_values: ctx.const_values,
    use_gc: ctx.use_gc,
    gc_array_types: ctx.gc_array_types,
    gc_struct_types: ctx.gc_struct_types,
    gc_struct_fields: ctx.gc_struct_fields,
  }
}

///|
fn emit_is_zero_check(ctx : CodeGenCtx, operand_type : @ast.TsType) -> Unit {
  if is_f64_type(operand_type) {
    ctx.emit(F64Const(0.0))
    ctx.emit(F64Eq)
  } else {
    ctx.emit(I32Eqz)
  }
}

///|
fn compile_var_logical_assign_expr(
  ctx : CodeGenCtx,
  name : String,
  op : @ast.TsCompoundOp,
  value : @ast.TsExpr,
) -> Unit raise CodeGenError {
  match ctx.get_local(name) {
    Some(lvar) => {
      let operand_type = lvar.type_
      let tmp_local = ctx.add_temp_local(operand_type)
      ctx.emit(LocalGet(lvar.index))
      ctx.emit(LocalTee(tmp_local))
      emit_is_zero_check(ctx, operand_type)

      let assign_ctx = make_branch_ctx(ctx)
      compile_expr(assign_ctx, value, operand_type)
      assign_ctx.emit(LocalTee(lvar.index))

      let result_type = ts_type_to_valtype(operand_type)
      match op {
        @ast.TsCompoundOp::AndAssign => {
          let then_instrs : Array[@core.Instr] = [LocalGet(tmp_local)]
          ctx.emit(If(Value(result_type), then_instrs, assign_ctx.instrs))
        }
        @ast.TsCompoundOp::OrAssign | @ast.TsCompoundOp::CoalesceAssign => {
          let else_instrs : Array[@core.Instr] = [LocalGet(tmp_local)]
          ctx.emit(If(Value(result_type), assign_ctx.instrs, else_instrs))
        }
        _ =>
          raise CodeGenError(
            "logical assignment expected, but got other compound op",
          )
      }
    }
    None => raise CodeGenError("Undefined variable: \{name}")
  }
}

///|
fn compile_prop_logical_assign_expr(
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
                  let tmp_local = ctx.add_temp_local(ft)
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
                  ctx.emit(LocalSet(tmp_local))
                  ctx.emit(LocalGet(tmp_local))
                  emit_is_zero_check(ctx, ft)

                  let assign_ctx = make_branch_ctx(ctx)
                  compile_expr(assign_ctx, value, ft)
                  assign_ctx.emit(LocalTee(val_local))
                  assign_ctx.emit(LocalGet(addr_local))
                  assign_ctx.emit(LocalGet(val_local))
                  if is_f64_type(ft) {
                    assign_ctx.emit(F64Store(3U, 0U, 0U))
                  } else {
                    assign_ctx.emit(I32Store(2U, 0U, 0U))
                  }

                  let result_type = ts_type_to_valtype(ft)
                  match op {
                    @ast.TsCompoundOp::AndAssign => {
                      let then_instrs : Array[@core.Instr] = [
                        LocalGet(tmp_local),
                      ]
                      ctx.emit(
                        If(Value(result_type), then_instrs, assign_ctx.instrs),
                      )
                    }
                    @ast.TsCompoundOp::OrAssign
                    | @ast.TsCompoundOp::CoalesceAssign => {
                      let else_instrs : Array[@core.Instr] = [
                        LocalGet(tmp_local),
                      ]
                      ctx.emit(
                        If(Value(result_type), assign_ctx.instrs, else_instrs),
                      )
                    }
                    _ =>
                      raise CodeGenError(
                        "logical assignment expected, but got other compound op",
                      )
                  }
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
fn compile_index_logical_assign_expr(
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
  let tmp_local = ctx.add_temp_local(elem_type)
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
  ctx.emit(LocalSet(tmp_local))
  ctx.emit(LocalGet(tmp_local))
  emit_is_zero_check(ctx, elem_type)

  let assign_ctx = make_branch_ctx(ctx)
  compile_expr(assign_ctx, value, elem_type)
  assign_ctx.emit(LocalTee(val_local))
  assign_ctx.emit(LocalGet(addr_local))
  assign_ctx.emit(LocalGet(val_local))
  if is_f64_type(elem_type) {
    assign_ctx.emit(F64Store(3U, 0U, 0U))
  } else {
    assign_ctx.emit(I32Store(2U, 0U, 0U))
  }

  let result_type = ts_type_to_valtype(elem_type)
  match op {
    @ast.TsCompoundOp::AndAssign => {
      let then_instrs : Array[@core.Instr] = [LocalGet(tmp_local)]
      ctx.emit(If(Value(result_type), then_instrs, assign_ctx.instrs))
    }
    @ast.TsCompoundOp::OrAssign | @ast.TsCompoundOp::CoalesceAssign => {
      let else_instrs : Array[@core.Instr] = [LocalGet(tmp_local)]
      ctx.emit(If(Value(result_type), assign_ctx.instrs, else_instrs))
    }
    _ =>
      raise CodeGenError(
        "logical assignment expected, but got other compound op",
      )
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
  match op {
    @ast.TsCompoundOp::AndAssign
    | @ast.TsCompoundOp::OrAssign
    | @ast.TsCompoundOp::CoalesceAssign =>
      match left {
        @ast.TsExpr::Var(name) =>
          compile_var_logical_assign_expr(ctx, name, op, value)
        @ast.TsExpr::PropAccess(obj, prop) =>
          compile_prop_logical_assign_expr(ctx, obj, prop, op, value)
        @ast.TsExpr::IndexAccess(arr, index) =>
          compile_index_logical_assign_expr(ctx, arr, index, op, value)
        _ =>
          raise CodeGenError(
            "logical assignment target is not supported in Wasm compiler",
          )
      }
    _ =>
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
    @ast.TsBinOp::Pow =>
      raise CodeGenError(
        "pow (**) is not supported in Wasm compiler (use interpreter)",
      )
    @ast.TsBinOp::In =>
      raise CodeGenError(
        "'in' operator is not supported in Wasm compiler (use interpreter)",
      )
    @ast.TsBinOp::And => {
      // a && b: if a is truthy, return b, else return a
      let tmp_type = if is_f64_type(expected_type) {
        @ast.TsType::Number
      } else {
        @ast.TsType::Int
      }
      let temp = ctx.add_local("__and_tmp__", tmp_type)
      compile_expr(ctx, left, tmp_type)
      ctx.emit(LocalTee(temp))
      if is_f64_type(tmp_type) {
        ctx.emit(F64Const(0.0))
        ctx.emit(F64Eq)
      } else {
        ctx.emit(I32Eqz)
      }
      let then_ctx : CodeGenCtx = {
        locals: ctx.locals,
        local_types: ctx.local_types,
        next_local: ctx.next_local,
        funcs: ctx.funcs,
        func_types: ctx.func_types,
        interfaces: ctx.interfaces,
        import_types: ctx.import_types,
        instrs: [],
        loop_depth: ctx.loop_depth,
        string_pool: ctx.string_pool,
        builtins_used: ctx.builtins_used,
        const_values: ctx.const_values,
        use_gc: ctx.use_gc,
        gc_array_types: ctx.gc_array_types,
        gc_struct_types: ctx.gc_struct_types,
        gc_struct_fields: ctx.gc_struct_fields,
      }
      // Then branch (a is falsy): return a (temp)
      let then_instrs : Array[@core.Instr] = [LocalGet(temp)]
      // Else branch (a truthy): evaluate b
      compile_expr(then_ctx, right, tmp_type)
      let result_type = ts_type_to_valtype(tmp_type)
      ctx.emit(If(Value(result_type), then_instrs, then_ctx.instrs))
      return
    }
    @ast.TsBinOp::Or => {
      // a || b: if a is truthy, return a, else return b
      let tmp_type = if is_f64_type(expected_type) {
        @ast.TsType::Number
      } else {
        @ast.TsType::Int
      }
      let temp = ctx.add_local("__or_tmp__", tmp_type)
      compile_expr(ctx, left, tmp_type)
      ctx.emit(LocalTee(temp))
      if is_f64_type(tmp_type) {
        ctx.emit(F64Const(0.0))
        ctx.emit(F64Eq)
      } else {
        ctx.emit(I32Eqz)
      }
      let then_ctx : CodeGenCtx = {
        locals: ctx.locals,
        local_types: ctx.local_types,
        next_local: ctx.next_local,
        funcs: ctx.funcs,
        func_types: ctx.func_types,
        interfaces: ctx.interfaces,
        import_types: ctx.import_types,
        instrs: [],
        loop_depth: ctx.loop_depth,
        string_pool: ctx.string_pool,
        builtins_used: ctx.builtins_used,
        const_values: ctx.const_values,
        use_gc: ctx.use_gc,
        gc_array_types: ctx.gc_array_types,
        gc_struct_types: ctx.gc_struct_types,
        gc_struct_fields: ctx.gc_struct_fields,
      }
      // Then branch (a is falsy): evaluate b
      compile_expr(then_ctx, right, tmp_type)
      // Else branch (a truthy): return a (temp)
      let else_instrs : Array[@core.Instr] = [LocalGet(temp)]
      let result_type = ts_type_to_valtype(tmp_type)
      ctx.emit(If(Value(result_type), then_ctx.instrs, else_instrs))
      return
    }
    @ast.TsBinOp::Coalesce => {
      // a ?? b: if a is null/undefined, return b, else return a
      // For i32: approximate null/undefined as 0
      // Note: This conflates 0 with null, which is not strictly correct
      let tmp_type = if is_f64_type(expected_type) {
        @ast.TsType::Number
      } else {
        @ast.TsType::Int
      }
      let temp = ctx.add_local("__coalesce_tmp__", tmp_type)
      compile_expr(ctx, left, tmp_type)
      ctx.emit(LocalTee(temp))
      if is_f64_type(tmp_type) {
        ctx.emit(F64Const(0.0))
        ctx.emit(F64Eq)
      } else {
        ctx.emit(I32Eqz)
      }

      // Then branch: left was null-ish, evaluate and return right
      let then_ctx : CodeGenCtx = {
        locals: ctx.locals,
        local_types: ctx.local_types,
        next_local: ctx.next_local,
        funcs: ctx.funcs,
        func_types: ctx.func_types,
        interfaces: ctx.interfaces,
        import_types: ctx.import_types,
        instrs: [],
        loop_depth: ctx.loop_depth,
        string_pool: ctx.string_pool,
        builtins_used: ctx.builtins_used,
        const_values: ctx.const_values,
        use_gc: ctx.use_gc,
        gc_array_types: ctx.gc_array_types,
        gc_struct_types: ctx.gc_struct_types,
        gc_struct_fields: ctx.gc_struct_fields,
      }
      compile_expr(then_ctx, right, tmp_type)

      // Else branch: left was not null-ish, return left from temp
      let else_instrs : Array[@core.Instr] = [LocalGet(temp)]
      let result_type = ts_type_to_valtype(tmp_type)
      ctx.emit(If(Value(result_type), then_ctx.instrs, else_instrs))
      return
    }
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
    @ast.TsUnaryOp::Typeof => {
      // typeof: restricted to statically known operand types
      let operand_type = infer_type(ctx, operand)
      match typeof_string_for_type(operand_type) {
        Some(kind) => {
          compile_expr(ctx, operand, operand_type)
          ctx.emit(Drop)
          let offset = ctx.string_pool.add(kind)
          ctx.emit(I32Const(offset.reinterpret_as_uint()))
        }
        None =>
          raise CodeGenError(
            "typeof is only supported for statically known operand types in Wasm compiler",
          )
      }
    }
    @ast.TsUnaryOp::Void => {
      // void: evaluate operand for side effects, return undefined (0)
      let operand_type = infer_type(ctx, operand)
      compile_expr(ctx, operand, operand_type)
      ctx.emit(Drop)
      ctx.emit(I32Const(0U))
      emit_coerce(ctx, @ast.TsType::Int, expected_type)
    }
    @ast.TsUnaryOp::Delete =>
      raise CodeGenError(
        "delete is not supported in Wasm compiler (use interpreter)",
      )
    @ast.TsUnaryOp::BitwiseNot => {
      // ~x: bitwise NOT = x XOR -1
      compile_expr(ctx, operand, @ast.TsType::Int)
      ctx.emit(I32Const(0xFFFFFFFFU)) // -1 as unsigned
      ctx.emit(I32Xor)
    }
  }
}

///|
// / function
fn compile_call(
  ctx : CodeGenCtx,
  name : String,
  args : Array[@ast.TsExpr],
  expected_type : @ast.TsType,
) -> @ast.TsType raise CodeGenError {
  fn compile_call_args(
    ctx : CodeGenCtx,
    args : Array[@ast.TsExpr],
    param_types : Array[@ast.TsType],
    expected_type : @ast.TsType,
  ) -> Unit raise CodeGenError {
    let mut spread_index = -1
    for i, arg in args {
      match arg {
        @ast.TsExpr::Spread(_) =>
          if spread_index >= 0 {
            raise CodeGenError("multiple spread arguments are not supported")
          } else {
            spread_index = i
          }
        _ => ()
      }
    }
    if spread_index < 0 {
      for i, arg in args {
        match arg {
          @ast.TsExpr::Spread(_) =>
            raise CodeGenError("spread is not supported in this call")
          _ => ()
        }
        let param_type = if i < param_types.length() {
          param_types[i]
        } else {
          expected_type
        }
        compile_expr(ctx, arg, param_type)
      }
      return
    }
    if spread_index != args.length() - 1 {
      raise CodeGenError("spread argument must be last in call")
    }
    let fixed_count = spread_index
    if fixed_count > param_types.length() {
      raise CodeGenError("too many arguments before spread")
    }
    for i in 0..<fixed_count {
      let param_type = if i < param_types.length() {
        param_types[i]
      } else {
        expected_type
      }
      compile_expr(ctx, args[i], param_type)
    }
    let spread_expr = match args[fixed_count] {
      @ast.TsExpr::Spread(inner) => inner
      _ => raise CodeGenError("spread argument missing")
    }
    if param_types.length() == fixed_count {
      let spread_type = infer_type(ctx, spread_expr)
      compile_expr(ctx, spread_expr, spread_type)
      ctx.emit(Drop)
      return
    }
    let arr_type = infer_type(ctx, spread_expr)
    let elem_type = match arr_type {
      @ast.TsType::Array(t) => t
      _ => raise CodeGenError("spread argument must be an array")
    }
    let arr_local = ctx.add_temp_local(arr_type)
    compile_expr(ctx, spread_expr, arr_type)
    ctx.emit(LocalSet(arr_local))
    let len_local = ctx.add_temp_local(@ast.TsType::Int)
    ctx.emit(LocalGet(arr_local))
    if ctx.use_gc {
      ctx.emit(ArrayLen)
    } else {
      ctx.emit(I32Load(2U, 0U, 0U))
    }
    ctx.emit(LocalSet(len_local))
    let type_key = if is_f64_type(elem_type) { "f64" } else { "i32" }
    let type_idx = if ctx.use_gc {
      match ctx.gc_array_types.get(type_key) {
        Some(idx) => idx
        None =>
          raise CodeGenError("wasm-gc array type not defined for: \{type_key}")
      }
    } else {
      0U
    }
    let elem_sz = element_size(elem_type)
    let val_type = if is_f64_type(elem_type) {
      @core.ValType::F64
    } else {
      @core.ValType::I32
    }
    for j in fixed_count..<param_types.length() {
      let idx = (j - fixed_count).reinterpret_as_uint()
      ctx.emit(I32Const(idx))
      ctx.emit(LocalGet(len_local))
      ctx.emit(I32LtS)
      let then_instrs : Array[@core.Instr] = []
      if ctx.use_gc {
        then_instrs.push(LocalGet(arr_local))
        then_instrs.push(I32Const(idx))
        then_instrs.push(ArrayGet(type_idx))
      } else {
        then_instrs.push(LocalGet(arr_local))
        then_instrs.push(I32Const(4U))
        then_instrs.push(I32Add)
        then_instrs.push(I32Const(idx))
        then_instrs.push(I32Const(elem_sz.reinterpret_as_uint()))
        then_instrs.push(I32Mul)
        then_instrs.push(I32Add)
        if is_f64_type(elem_type) {
          then_instrs.push(F64Load(3U, 0U, 0U))
        } else {
          then_instrs.push(I32Load(2U, 0U, 0U))
        }
      }
      let else_instrs : Array[@core.Instr] = if is_f64_type(elem_type) {
        [F64Const(0.0)]
      } else {
        [I32Const(0U)]
      }
      ctx.emit(If(Value(val_type), then_instrs, else_instrs))
      let param_type = param_types[j]
      emit_coerce(ctx, elem_type, param_type)
    }
  }

  // functionget
  match ctx.funcs.get(name) {
    Some(idx) =>
      // importfunctiontype
      match ctx.import_types.get(name) {
        Some((param_types, return_type)) => {
          // importfunction: parametertypereference
          compile_call_args(ctx, args, param_types, expected_type)
          ctx.emit(Call(idx))
          return return_type
        }
        None =>
          // definefunction: expected_type
          match ctx.func_types.get(name) {
            Some((param_types, return_type)) => {
              compile_call_args(ctx, args, param_types, expected_type)
              ctx.emit(Call(idx))
              return return_type
            }
            None => {
              for arg in args {
                match arg {
                  @ast.TsExpr::Spread(_) =>
                    raise CodeGenError(
                      "Spread requires a known function signature",
                    )
                  _ => compile_expr(ctx, arg, expected_type)
                }
              }
              ctx.emit(Call(idx))
              return expected_type
            }
          }
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
          // Use pre-registered type if available, otherwise infer from init
          let (idx, resolved_type) = match ctx.get_local(name) {
            Some(existing) => (existing.index, existing.type_)
            None => {
              let inferred = resolve_any_with_ctx(ctx, type_, init)
              (ctx.add_local(name, inferred), inferred)
            }
          }
          compile_expr(ctx, init, resolved_type)
          ctx.emit(LocalSet(idx))
        }
        _ => raise CodeGenError("Unsupported var/let binding pattern")
      }
    @ast.TsStmt::Const(binding, type_, init) =>
      match binding {
        @ast.TsBinding::Ident(name) => {
          // Track const value for constant propagation
          let const_val = @analysis.eval_const(init)
          match const_val {
            @analysis.ConstValue::NotConst => ()
            _ => ctx.const_values[name] = const_val
          }
          // Use pre-registered type if available, otherwise infer from init
          let (idx, resolved_type) = match ctx.get_local(name) {
            Some(existing) => (existing.index, existing.type_)
            None => {
              let inferred = resolve_any_with_ctx(ctx, type_, init)
              (ctx.add_local(name, inferred), inferred)
            }
          }
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
      match op {
        @ast.TsCompoundOp::AndAssign
        | @ast.TsCompoundOp::OrAssign
        | @ast.TsCompoundOp::CoalesceAssign => {
          compile_var_logical_assign_expr(ctx, name, op, expr)
          ctx.emit(Drop)
        }
        _ =>
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
    @ast.TsStmt::DoWhile(cond, body) =>
      compile_do_while(ctx, body, cond, return_type)
    @ast.TsStmt::Switch(discriminant, cases) =>
      compile_switch(ctx, discriminant, cases, return_type)
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
  // Try constant folding on condition - eliminate dead branches
  match @analysis.eval_const(cond) {
    @analysis.ConstValue::Boolean(true)
    | @analysis.ConstValue::Int(_)
    | @analysis.ConstValue::Number(_)
    | @analysis.ConstValue::String_(_) => {
      // Condition is truthy - only compile then branch
      for stmt in then_block.stmts {
        compile_stmt(ctx, stmt, return_type)
      }
      return
    }
    @analysis.ConstValue::Boolean(false)
    | @analysis.ConstValue::Null
    | @analysis.ConstValue::Undefined => {
      // Condition is falsy - only compile else branch
      match else_block {
        Some(block) =>
          for stmt in block.stmts {
            compile_stmt(ctx, stmt, return_type)
          }
        None => ()
      }
      return
    }
    @analysis.ConstValue::NotConst => ()
  }
  // Dynamic condition - compile both branches
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
  // Try constant folding on condition
  match @analysis.eval_const(cond) {
    @analysis.ConstValue::Boolean(false)
    | @analysis.ConstValue::Null
    | @analysis.ConstValue::Undefined =>
      // Condition is always false - skip the entire loop
      return
    // Note: We don't optimize `while(true)` to avoid generating infinite loops
    // that would hang the Wasm runtime
    _ => ()
  }
  ctx.loop_depth += 1

  // Block(Loop([cond, BrIf(1), ...body, Br(0)]))
  let loop_instrs : Array[@core.Instr] = []

  // conditioncheck
  let cond_ctx : CodeGenCtx = {
    locals: ctx.locals,
    local_types: ctx.local_types,
    next_local: ctx.next_local,
    funcs: ctx.funcs,
    func_types: ctx.func_types,
    interfaces: ctx.interfaces,
    import_types: ctx.import_types,
    instrs: [],
    loop_depth: ctx.loop_depth,
    string_pool: ctx.string_pool,
    builtins_used: ctx.builtins_used,
    const_values: ctx.const_values,
    use_gc: ctx.use_gc,
    gc_array_types: ctx.gc_array_types,
    gc_struct_types: ctx.gc_struct_types,
    gc_struct_fields: ctx.gc_struct_fields,
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
// Do-while statement: body executes at least once
fn compile_do_while(
  ctx : CodeGenCtx,
  body : @ast.TsBlock,
  cond : @ast.TsExpr,
  return_type : @ast.TsType,
) -> Unit raise CodeGenError {
  ctx.loop_depth += 1

  // Structure: loop { body; if cond { br 0 } }
  let loop_instrs : Array[@core.Instr] = []

  // body (executes first)
  let body_instrs = compile_block_to_instrs(ctx, body, return_type)
  for instr in body_instrs {
    loop_instrs.push(instr)
  }

  // condition check
  let cond_ctx : CodeGenCtx = {
    locals: ctx.locals,
    local_types: ctx.local_types,
    next_local: ctx.next_local,
    funcs: ctx.funcs,
    func_types: ctx.func_types,
    interfaces: ctx.interfaces,
    import_types: ctx.import_types,
    instrs: [],
    loop_depth: ctx.loop_depth,
    string_pool: ctx.string_pool,
    builtins_used: ctx.builtins_used,
    const_values: ctx.const_values,
    use_gc: ctx.use_gc,
    gc_array_types: ctx.gc_array_types,
    gc_struct_types: ctx.gc_struct_types,
    gc_struct_fields: ctx.gc_struct_fields,
  }
  compile_expr(cond_ctx, cond, @ast.TsType::Boolean)
  for instr in cond_ctx.instrs {
    loop_instrs.push(instr)
  }
  loop_instrs.push(BrIf(0U)) // if cond is true, jump back to loop start
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
        func_types: ctx.func_types,
        interfaces: ctx.interfaces,
        import_types: ctx.import_types,
        instrs: [],
        loop_depth: ctx.loop_depth,
        string_pool: ctx.string_pool,
        builtins_used: ctx.builtins_used,
        const_values: ctx.const_values,
        use_gc: ctx.use_gc,
        gc_array_types: ctx.gc_array_types,
        gc_struct_types: ctx.gc_struct_types,
        gc_struct_fields: ctx.gc_struct_fields,
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
        func_types: ctx.func_types,
        interfaces: ctx.interfaces,
        import_types: ctx.import_types,
        instrs: [],
        loop_depth: ctx.loop_depth,
        string_pool: ctx.string_pool,
        builtins_used: ctx.builtins_used,
        const_values: ctx.const_values,
        use_gc: ctx.use_gc,
        gc_array_types: ctx.gc_array_types,
        gc_struct_types: ctx.gc_struct_types,
        gc_struct_fields: ctx.gc_struct_fields,
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
// Switch statement compilation
// Compiles switch to nested if-else structure
fn compile_switch(
  ctx : CodeGenCtx,
  discriminant : @ast.TsExpr,
  cases : Array[@ast.TsSwitchCase],
  return_type : @ast.TsType,
) -> Unit raise CodeGenError {
  // Evaluate discriminant and store in temp local
  let disc_type = infer_type(ctx, discriminant)
  let disc_local = ctx.add_local("__switch_disc__", disc_type)
  compile_expr(ctx, discriminant, disc_type)
  ctx.emit(LocalSet(disc_local))

  // Find default case index
  let mut default_idx : Int? = None
  for i, case_ in cases {
    if case_.test_expr is None {
      default_idx = Some(i)
    }
  }

  // Compile as nested if-else
  // Use block/br structure for break support
  ctx.loop_depth += 1
  let switch_instrs = compile_switch_cases(
    ctx, disc_local, disc_type, cases, 0, default_idx, return_type,
  )
  ctx.emit(Block(Empty, switch_instrs))
  ctx.loop_depth -= 1
}

///|
fn compile_switch_cases(
  ctx : CodeGenCtx,
  disc_local : UInt,
  disc_type : @ast.TsType,
  cases : Array[@ast.TsSwitchCase],
  idx : Int,
  default_idx : Int?,
  return_type : @ast.TsType,
) -> Array[@core.Instr] raise CodeGenError {
  if idx >= cases.length() {
    // No more cases, compile default if exists
    match default_idx {
      Some(di) => {
        let default_case = cases[di]
        compile_block_to_instrs(ctx, default_case.body, return_type)
      }
      None => []
    }
  } else {
    let case_ = cases[idx]
    match case_.test_expr {
      None =>
        // Default case - skip here, will be handled at the end
        compile_switch_cases(
          ctx,
          disc_local,
          disc_type,
          cases,
          idx + 1,
          default_idx,
          return_type,
        )
      Some(test_expr) => {
        // Compile comparison: disc == test_expr
        let cond_ctx : CodeGenCtx = {
          locals: ctx.locals,
          local_types: ctx.local_types,
          next_local: ctx.next_local,
          funcs: ctx.funcs,
          func_types: ctx.func_types,
          interfaces: ctx.interfaces,
          import_types: ctx.import_types,
          instrs: [],
          loop_depth: ctx.loop_depth,
          string_pool: ctx.string_pool,
          builtins_used: ctx.builtins_used,
          const_values: ctx.const_values,
          use_gc: ctx.use_gc,
          gc_array_types: ctx.gc_array_types,
          gc_struct_types: ctx.gc_struct_types,
          gc_struct_fields: ctx.gc_struct_fields,
        }
        cond_ctx.emit(LocalGet(disc_local))
        compile_expr(cond_ctx, test_expr, disc_type)
        if is_f64_type(disc_type) {
          cond_ctx.emit(F64Eq)
        } else {
          cond_ctx.emit(I32Eq)
        }

        // Compile then branch (case body)
        let then_instrs = compile_block_to_instrs(ctx, case_.body, return_type)

        // Compile else branch (remaining cases)
        let else_instrs = compile_switch_cases(
          ctx,
          disc_local,
          disc_type,
          cases,
          idx + 1,
          default_idx,
          return_type,
        )

        // Build if-then-else
        let result : Array[@core.Instr] = []
        for instr in cond_ctx.instrs {
          result.push(instr)
        }
        result.push(If(Empty, then_instrs, else_instrs))
        result
      }
    }
  }
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
    func_types: ctx.func_types,
    interfaces: ctx.interfaces,
    import_types: ctx.import_types,
    instrs: [],
    loop_depth: ctx.loop_depth,
    string_pool: ctx.string_pool,
    builtins_used: ctx.builtins_used,
    const_values: ctx.const_values,
    use_gc: ctx.use_gc,
    gc_array_types: ctx.gc_array_types,
    gc_struct_types: ctx.gc_struct_types,
    gc_struct_fields: ctx.gc_struct_fields,
  }
  for stmt in block.stmts {
    compile_stmt(sub_ctx, stmt, return_type)
  }

  // variableupdate
  ctx.next_local = sub_ctx.next_local
  sub_ctx.instrs
}

///|
// / default return value for non-void functions
fn emit_default_return(ctx : CodeGenCtx, return_type : @ast.TsType) -> Unit {
  match return_type {
    @ast.TsType::Void => ()
    _ =>
      if is_f64_type(return_type) {
        ctx.emit(F64Const(0.0))
        ctx.emit(Return)
      } else {
        ctx.emit(I32Const(0U))
        ctx.emit(Return)
      }
  }
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
  func_types : Map[String, (Array[@ast.TsType], @ast.TsType)],
  string_pool : StringPool,
  builtins_used : Map[String, Bool],
) -> (@core.TypeDef, @core.Code) raise CodeGenError {
  let ctx = CodeGenCtx::new(
    func_map, interfaces, import_types, func_types, string_pool, builtins_used,
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
  emit_default_return(ctx, func.return_type)

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

  // function signature map
  let func_types : Map[String, (Array[@ast.TsType], @ast.TsType)] = {}
  for func in module_.funcs {
    let param_types : Array[@ast.TsType] = []
    for param in func.params {
      param_types.push(param.type_)
    }
    func_types[func.name] = (param_types, func.return_type)
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
      func, func_map, interface_map, import_types, func_types, string_pool, builtins_used,
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
        init: Bytes::from_array(string_pool.data)[:],
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
/// Compile module using wasm-gc types instead of linear memory.
/// Arrays are represented as GC arrays, no linear memory allocation.
pub fn compile_module_gc(
  module_ : @ast.TsModule,
) -> @core.Module raise CodeGenError {
  // Import count
  let num_imports = module_.imports.length().reinterpret_as_uint()

  // Function map
  let func_map : Map[String, UInt] = {}
  for i, imp in module_.imports {
    func_map[imp.name] = i.reinterpret_as_uint()
  }
  for i, func in module_.funcs {
    func_map[func.name] = i.reinterpret_as_uint() + num_imports
  }

  // Function signature map
  let func_types : Map[String, (Array[@ast.TsType], @ast.TsType)] = {}
  for func in module_.funcs {
    let param_types : Array[@ast.TsType] = []
    for param in func.params {
      param_types.push(param.type_)
    }
    func_types[func.name] = (param_types, func.return_type)
  }

  // Interface map
  let interface_map : Map[String, Array[(String, @ast.TsType)]] = {}
  for iface in module_.interfaces {
    interface_map[iface.name] = iface.fields
  }

  // Import types
  let import_types : Map[String, (Array[@ast.TsType], @ast.TsType)] = {}
  for imp in module_.imports {
    let param_types : Array[@ast.TsType] = []
    for param in imp.params {
      param_types.push(param.1)
    }
    import_types[imp.name] = (param_types, imp.return_type)
  }

  // String pool (still needed for string literals)
  let string_pool = StringPool::new()

  // Type definitions
  let types : Array[@core.TypeDef] = []

  // Add GC array types first
  // Type 0: (array i32) - for i32 arrays
  types.push(
    @core.TypeDef::Array({
      element: { storage: @core.StorageType::Val(I32), mutable: true },
    }),
  )
  // Type 1: (array f64) - for f64 arrays
  types.push(
    @core.TypeDef::Array({
      element: { storage: @core.StorageType::Val(F64), mutable: true },
    }),
  )

  // GC array type indices map
  let gc_array_types : Map[String, UInt] = {}
  gc_array_types["i32"] = 0U
  gc_array_types["f64"] = 1U

  // Add GC struct types for each interface
  let gc_struct_types : Map[String, UInt] = {}
  let gc_struct_fields : Map[String, Map[String, UInt]] = {}
  let mut next_type_idx = 2U // First 2 types are GC array types
  for iface in module_.interfaces {
    let fields : Array[@core.FieldType] = []
    let field_map : Map[String, UInt] = {}
    for i, field_tuple in iface.fields {
      let (_, field_type) = field_tuple
      let storage = if is_f64_type(field_type) {
        @core.StorageType::Val(F64)
      } else {
        @core.StorageType::Val(I32)
      }
      fields.push({ storage, mutable: true })
      field_map[field_tuple.0] = i.reinterpret_as_uint()
    }
    types.push(@core.TypeDef::Struct({ fields, }))
    gc_struct_types[iface.name] = next_type_idx
    gc_struct_fields[iface.name] = field_map
    next_type_idx += 1
  }

  // Add generator state struct types
  let generator_struct_types : Map[String, UInt] = {}
  for func in module_.funcs {
    if func.is_generator {
      // Analyze to get field count
      let analysis = @analysis.analyze_generator(func)
      if analysis.compilable {
        // Create struct fields: state (i32), done (i32), params... (f64), locals... (f64)
        let gen_fields : Array[@core.FieldType] = []
        gen_fields.push({
          storage: @core.StorageType::Val(@core.ValType::I32),
          mutable: true,
        })
        gen_fields.push({
          storage: @core.StorageType::Val(@core.ValType::I32),
          mutable: true,
        })
        for _ in func.params {
          gen_fields.push({
            storage: @core.StorageType::Val(@core.ValType::F64),
            mutable: true,
          })
        }
        for v in analysis.persisted_vars {
          if not(v.is_param) {
            gen_fields.push({
              storage: @core.StorageType::Val(@core.ValType::F64),
              mutable: true,
            })
          }
        }
        types.push(@core.TypeDef::Struct({ fields: gen_fields }))
        generator_struct_types[func.name] = next_type_idx
        next_type_idx += 1
      }
    }
  }
  let gc_type_offset = next_type_idx

  // Add import function types
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

  // Compile functions with GC mode
  let codes : Array[@core.Code] = []
  let funcs : Array[UInt] = []
  let exports : Array[@core.Export] = []
  let builtins_used : Map[String, Bool] = {}
  let mut func_idx_counter = 0U
  for func in module_.funcs {
    // Check if this is a compilable generator
    match generator_struct_types.get(func.name) {
      Some(struct_type_idx) => {
        // Compile generator: produces create() and next() functions
        let gen_code = compile_generator_func(func, struct_type_idx)
        match gen_code {
          Some(gc) => {
            // Add create function
            types.push(gc.create_func_type)
            codes.push(gc.create_func_code)
            let create_func_idx = func_idx_counter + num_imports
            funcs.push(create_func_idx + gc_type_offset)
            let create_name = string_to_bytes(func.name + "_create")
            exports.push({
              name: create_name,
              desc: @core.ExportDesc::Func(create_func_idx),
            })
            func_idx_counter += 1

            // Add next function
            types.push(gc.next_func_type)
            codes.push(gc.next_func_code)
            let next_func_idx = func_idx_counter + num_imports
            funcs.push(next_func_idx + gc_type_offset)
            let next_name = string_to_bytes(func.name + "_next")
            exports.push({
              name: next_name,
              desc: @core.ExportDesc::Func(next_func_idx),
            })
            func_idx_counter += 1
          }
          None => {
            // Fallback: compile as regular function (will fail at runtime for yield)
            let (func_type, code) = compile_function_gc(
              func, func_map, interface_map, import_types, func_types, string_pool,
              builtins_used, gc_array_types, gc_struct_types, gc_struct_fields,
            )
            types.push(func_type)
            codes.push(code)
            let func_idx = func_idx_counter + num_imports
            funcs.push(func_idx + gc_type_offset)
            let name_bytes = string_to_bytes(func.name)
            exports.push({
              name: name_bytes,
              desc: @core.ExportDesc::Func(func_idx),
            })
            func_idx_counter += 1
          }
        }
      }
      None => {
        // Regular function
        let (func_type, code) = compile_function_gc(
          func, func_map, interface_map, import_types, func_types, string_pool, builtins_used,
          gc_array_types, gc_struct_types, gc_struct_fields,
        )
        types.push(func_type)
        codes.push(code)
        let func_idx = func_idx_counter + num_imports
        funcs.push(func_idx + gc_type_offset)
        let name_bytes = string_to_bytes(func.name)
        exports.push({
          name: name_bytes,
          desc: @core.ExportDesc::Func(func_idx),
        })
        func_idx_counter += 1
      }
    }
  }

  // Imports
  let imports : Array[@core.Import] = []
  for i, imp in module_.imports {
    imports.push({
      module_: string_to_bytes(imp.module_),
      name: string_to_bytes(imp.name),
      desc: @core.ImportDesc::Func(i.reinterpret_as_uint() + gc_type_offset),
    })
  }

  // No linear memory for GC mode
  let mems : Array[@core.MemType] = []
  let globals : Array[@core.Global] = []
  let datas : Array[@core.Data] = []

  // Type metadata
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
/// Compile a function using wasm-gc mode
fn compile_function_gc(
  func : @ast.TsFunc,
  func_map : Map[String, UInt],
  interfaces : Map[String, Array[(String, @ast.TsType)]],
  import_types : Map[String, (Array[@ast.TsType], @ast.TsType)],
  func_types : Map[String, (Array[@ast.TsType], @ast.TsType)],
  string_pool : StringPool,
  builtins_used : Map[String, Bool],
  gc_array_types : Map[String, UInt],
  gc_struct_types : Map[String, UInt],
  gc_struct_fields : Map[String, Map[String, UInt]],
) -> (@core.TypeDef, @core.Code) raise CodeGenError {
  let ctx : CodeGenCtx = {
    locals: {},
    local_types: [],
    next_local: 0,
    funcs: func_map,
    func_types,
    interfaces,
    import_types,
    instrs: [],
    loop_depth: 0,
    string_pool,
    builtins_used,
    const_values: {},
    use_gc: true,
    gc_array_types,
    gc_struct_types,
    gc_struct_fields,
  }

  // Register parameters
  for param in func.params {
    ignore(ctx.add_local(param.name, param.type_))
  }
  let param_count = func.params.length().reinterpret_as_uint()

  // Compile function body
  for stmt in func.body.stmts {
    compile_stmt(ctx, stmt, func.return_type)
  }
  emit_default_return(ctx, func.return_type)

  // Build function type (use gc types for params and results)
  let params : Array[@core.ValType] = []
  for param in func.params {
    params.push(
      ts_type_to_valtype_gc(param.type_, gc_array_types, gc_struct_types),
    )
  }
  let results : Array[@core.ValType] = match func.return_type {
    @ast.TsType::Void => []
    t => [ts_type_to_valtype_gc(t, gc_array_types, gc_struct_types)]
  }
  let func_type : @core.TypeDef = @core.TypeDef::Func({ params, results })

  // Build locals (excluding parameters) - use gc types
  let locals : Array[@core.ValType] = []
  let mut i = param_count.reinterpret_as_int()
  while i < ctx.next_local.reinterpret_as_int() {
    locals.push(
      ts_type_to_valtype_gc(ctx.local_types[i], gc_array_types, gc_struct_types),
    )
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

///|
/// Compile a typed function with pre-resolved local variable types.
fn compile_typed_function(
  typed_func : @ast.TypedFunc,
  func_map : Map[String, UInt],
  interfaces : Map[String, Array[(String, @ast.TsType)]],
  import_types : Map[String, (Array[@ast.TsType], @ast.TsType)],
  func_types : Map[String, (Array[@ast.TsType], @ast.TsType)],
  string_pool : StringPool,
  builtins_used : Map[String, Bool],
) -> (@core.TypeDef, @core.Code) raise CodeGenError {
  let func = typed_func.func
  let ctx = CodeGenCtx::new(
    func_map, interfaces, import_types, func_types, string_pool, builtins_used,
  )

  // Register parameters
  for param in func.params {
    let _ = ctx.add_local(param.name, param.type_)
  }

  // Pre-register local variables with their inferred types
  // Skip Any types - let codegen infer them from context
  for var_info in typed_func.locals {
    let (name, type_) = var_info
    match type_ {
      @ast.TsType::Any => () // Skip - will be inferred during codegen
      _ =>
        // Skip if already registered (e.g., shadowing or params)
        if ctx.get_local(name) is None {
          let _ = ctx.add_local(name, type_)
        }
    }
  }
  let param_count = func.params.length().reinterpret_as_uint()

  // Compile function body
  for stmt in func.body.stmts {
    compile_stmt(ctx, stmt, func.return_type)
  }

  // Build type definition
  let params : Array[@core.ValType] = []
  for param in func.params {
    params.push(ts_type_to_valtype(param.type_))
  }
  let results : Array[@core.ValType] = match func.return_type {
    @ast.TsType::Void => []
    t => [ts_type_to_valtype(t)]
  }
  let func_type : @core.TypeDef = @core.TypeDef::Func({ params, results })

  // Build locals array (excluding parameters)
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

///|
/// Compile a TypedModule to WebAssembly.
/// Uses pre-analyzed type information for better optimization.
pub fn compile_typed_module(
  typed_module : @ast.TypedModule,
  original_module : @ast.TsModule,
) -> @core.Module raise CodeGenError {
  let num_imports = original_module.imports.length().reinterpret_as_uint()

  // Build function index map
  let func_map : Map[String, UInt] = {}
  for i, imp in original_module.imports {
    func_map[imp.name] = i.reinterpret_as_uint()
  }
  for i, func in original_module.funcs {
    func_map[func.name] = i.reinterpret_as_uint() + num_imports
  }

  // Build function signature map
  let func_types : Map[String, (Array[@ast.TsType], @ast.TsType)] = {}
  for typed_func in typed_module.funcs {
    let func = typed_func.func
    let param_types : Array[@ast.TsType] = []
    for param in func.params {
      param_types.push(param.type_)
    }
    func_types[func.name] = (param_types, func.return_type)
  }

  // Build interface map
  let interface_map : Map[String, Array[(String, @ast.TsType)]] = {}
  for iface in original_module.interfaces {
    interface_map[iface.name] = iface.fields
  }

  // Build import types map
  let import_types : Map[String, (Array[@ast.TsType], @ast.TsType)] = {}
  for imp in original_module.imports {
    let param_types : Array[@ast.TsType] = []
    for param in imp.params {
      param_types.push(param.1)
    }
    import_types[imp.name] = (param_types, imp.return_type)
  }
  let string_pool = StringPool::new()

  // Build type definitions for imports
  let types : Array[@core.TypeDef] = []
  for imp in original_module.imports {
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

  // Compile functions using typed function information
  let codes : Array[@core.Code] = []
  let funcs : Array[UInt] = []
  let exports : Array[@core.Export] = []
  let builtins_used : Map[String, Bool] = {}
  for i, typed_func in typed_module.funcs {
    let (func_type, code) = compile_typed_function(
      typed_func, func_map, interface_map, import_types, func_types, string_pool,
      builtins_used,
    )
    types.push(func_type)
    codes.push(code)
    let func_idx = i.reinterpret_as_uint() + num_imports
    funcs.push(func_idx)
    let name_bytes = string_to_bytes(typed_func.func.name)
    exports.push({ name: name_bytes, desc: @core.ExportDesc::Func(func_idx) })
  }

  // Build imports
  let imports : Array[@core.Import] = []
  for i, imp in original_module.imports {
    imports.push({
      module_: string_to_bytes(imp.module_),
      name: string_to_bytes(imp.name),
      desc: @core.ImportDesc::Func(i.reinterpret_as_uint()),
    })
  }

  // Memory
  let mems : Array[@core.MemType] = [
    { limits: { min: 1UL, max: Some(16UL) }, shared: false, memory64: false },
  ]

  // Data section for strings
  let datas : Array[@core.Data] = if string_pool.data.length() > 0 {
    [
      {
        mem_idx: 0U,
        offset: { instrs: [I32Const(0U)] },
        init: Bytes::from_array(string_pool.data)[:],
        is_active: true,
      },
    ]
  } else {
    []
  }

  // Heap pointer global
  let heap_start = (string_pool.offset() + 3) / 4 * 4
  let heap_start_aligned = if heap_start < 1024 { 1024 } else { heap_start }
  let globals : Array[@core.Global] = [
    {
      type_: { val_type: I32, mutable: true },
      init: { instrs: [I32Const(heap_start_aligned.reinterpret_as_uint())] },
    },
  ]

  // Type metadata
  let type_metadata = serialize_type_metadata(original_module)
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
/// Analyze and compile source code in one step.
pub fn analyze_and_compile(source : String) -> @core.Module raise CodeGenError {
  let parser = @parser.Parser::from_source(source)
  let module_ = parser.parse_module() catch {
    @parser.ParseError(msg) => raise CodeGenError(msg)
  }

  // Run static analysis
  let analysis_result = @analysis.analyze(module_, source)
  match analysis_result {
    @analysis.AnalysisResult::Err(errors) =>
      // Format first error as CodeGenError
      if errors.length() > 0 {
        let first_error = errors[0]
        raise CodeGenError(
          "\{first_error.kind.to_string()}: \{first_error.message}",
        )
      } else {
        raise CodeGenError("Analysis failed with unknown error")
      }
    @analysis.AnalysisResult::Ok(typed_module, _) =>
      compile_typed_module(typed_module, module_)
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
