// TypeScript AST → wasm5 Instr 変換

///|
/// コード生成エラー
pub suberror CodeGenError {
  CodeGenError(String)
} derive(Show)

///|
/// 文字列プール (スナップショット用)
priv struct StringPool {
  // 文字列 → オフセット
  strings : Map[String, Int]
  // 文字列データ (順番に格納)
  data : Array[Byte]
}

///|
/// 文字列プール作成
fn StringPool::new() -> StringPool {
  { strings: {}, data: [] }
}

///|
/// 現在のオフセットを取得
fn StringPool::offset(self : StringPool) -> Int {
  self.data.length()
}

///|
/// 文字列を追加してオフセットを返す
fn StringPool::add(self : StringPool, s : String) -> Int {
  // 既に存在するかチェック
  match self.strings.get(s) {
    Some(offset) => offset
    None => {
      let offset = self.data.length()
      self.strings[s] = offset

      // 長さを格納 (4バイト、リトルエンディアン)
      let len = s.length()
      self.data.push((len & 0xFF).to_byte())
      self.data.push(((len >> 8) & 0xFF).to_byte())
      self.data.push(((len >> 16) & 0xFF).to_byte())
      self.data.push(((len >> 24) & 0xFF).to_byte())

      // 文字列データを格納
      for i = 0; i < len; i = i + 1 {
        self.data.push((s[i].to_int() & 0xFF).to_byte())
      }

      // 4バイトアライン
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
// 型メタデータシリアライザ (スナップショット用)
// ============================================

///|
/// @parser.TsType を 1 バイトにエンコード
fn encode_type(t : @parser.TsType) -> Byte {
  match t {
    @parser.TsType::Number => b'\x00'
    @parser.TsType::Int => b'\x01'
    @parser.TsType::Boolean => b'\x02'
    @parser.TsType::String_ => b'\x03'
    @parser.TsType::Void => b'\x04'
    @parser.TsType::Any => b'\x05'
    @parser.TsType::Array(_) => b'\x06'
    @parser.TsType::Struct(_, _) => b'\x07'
    @parser.TsType::Func(_, _) => b'\x08'
    @parser.TsType::Named(_) => b'\x09'
  }
}

///|
/// 型メタデータをシリアライズ
fn serialize_type_metadata(module_ : @parser.TsModule) -> Bytes {
  let buf : Array[Byte] = []

  // マジック "TSTY"
  buf.push(b'\x54') // T
  buf.push(b'\x53') // S
  buf.push(b'\x54') // T
  buf.push(b'\x59') // Y

  // バージョン
  buf.push(b'\x01')

  // インポート数 (u16 LE)
  let import_count = module_.imports.length()
  buf.push((import_count & 0xFF).to_byte())
  buf.push(((import_count >> 8) & 0xFF).to_byte())

  // インターフェース数 (u16 LE)
  let iface_count = module_.interfaces.length()
  buf.push((iface_count & 0xFF).to_byte())
  buf.push(((iface_count >> 8) & 0xFF).to_byte())

  // エクスポート数 (u16 LE)
  let export_count = module_.funcs.length()
  buf.push((export_count & 0xFF).to_byte())
  buf.push(((export_count >> 8) & 0xFF).to_byte())

  // インポート配列
  for imp in module_.imports {
    // 関数名
    let name_len = imp.name.length()
    buf.push((name_len & 0xFF).to_byte())
    for i = 0; i < name_len; i = i + 1 {
      buf.push((imp.name[i].to_int() & 0xFF).to_byte())
    }
    // モジュール名
    let mod_len = imp.module_.length()
    buf.push((mod_len & 0xFF).to_byte())
    for i = 0; i < mod_len; i = i + 1 {
      buf.push((imp.module_[i].to_int() & 0xFF).to_byte())
    }
    // パラメータ数
    buf.push((imp.params.length() & 0xFF).to_byte())
    // パラメータ型
    for param in imp.params {
      buf.push(encode_type(param.1))
    }
    // 戻り値型
    buf.push(encode_type(imp.return_type))
  }

  // インターフェース配列
  for iface in module_.interfaces {
    // インターフェース名
    let name_len = iface.name.length()
    buf.push((name_len & 0xFF).to_byte())
    for i = 0; i < name_len; i = i + 1 {
      buf.push((iface.name[i].to_int() & 0xFF).to_byte())
    }
    // フィールド数
    buf.push((iface.fields.length() & 0xFF).to_byte())
    // 各フィールド
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

  // エクスポート配列 (関数名のみ)
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
// 型推論 (リテラルから)
// ============================================

///|
/// リテラルから型を推論（コンテキスト不要）
fn infer_literal_type(expr : @parser.TsExpr) -> @parser.TsType {
  match expr {
    @parser.TsExpr::IntLit(_) => @parser.TsType::Int
    @parser.TsExpr::NumberLit(_) => @parser.TsType::Number
    @parser.TsExpr::BoolLit(_) => @parser.TsType::Boolean
    @parser.TsExpr::StringLit(_) => @parser.TsType::String_
    @parser.TsExpr::NullLit => @parser.TsType::Any // null は @parser.TsType::Any
    @parser.TsExpr::ArrayLit(_) => @parser.TsType::Any // 要素型の推論は複雑なので @parser.TsType::Any
    @parser.TsExpr::ObjectLit(_) => @parser.TsType::Any // オブジェクトリテラルは @parser.TsType::Any
    @parser.TsExpr::Var(_) => @parser.TsType::Any // 変数は文脈から推論する必要あり
    @parser.TsExpr::Seq(_, right) => infer_literal_type(right)
    @parser.TsExpr::PropAssignExpr(_, _, value) => infer_literal_type(value)
    @parser.TsExpr::IndexAssignExpr(_, _, value) => infer_literal_type(value)
    @parser.TsExpr::BinOp(op, lhs, _) =>
      // 比較演算子は @parser.TsType::Boolean を返す
      match op {
        @parser.TsBinOp::BinEq
        | @parser.TsBinOp::BinNe
        | @parser.TsBinOp::AbstractEq
        | @parser.TsBinOp::AbstractNe
        | @parser.TsBinOp::BinLt
        | @parser.TsBinOp::BinLe
        | @parser.TsBinOp::BinGt
        | @parser.TsBinOp::BinGe
        | @parser.TsBinOp::Instanceof
        | @parser.TsBinOp::In
        | @parser.TsBinOp::And
        | @parser.TsBinOp::Or => @parser.TsType::Boolean
        @parser.TsBinOp::Add | @parser.TsBinOp::Sub | @parser.TsBinOp::Mul | @parser.TsBinOp::Div | @parser.TsBinOp::Mod | @parser.TsBinOp::Pow | @parser.TsBinOp::BitAnd | @parser.TsBinOp::BitOr | @parser.TsBinOp::BitXor | @parser.TsBinOp::Shl | @parser.TsBinOp::Shr
        | @parser.TsBinOp::UShr =>
          infer_literal_type(lhs) // 左辺の型を継承
      }
    @parser.TsExpr::UnaryOp(op, e) =>
      match op {
        @parser.TsUnaryOp::Neg | @parser.TsUnaryOp::Plus => infer_literal_type(e)
        @parser.TsUnaryOp::Not => @parser.TsType::Boolean
        @parser.TsUnaryOp::Typeof => @parser.TsType::String_
        @parser.TsUnaryOp::Void => @parser.TsType::Any
        @parser.TsUnaryOp::Delete => @parser.TsType::Boolean
        @parser.TsUnaryOp::PreInc | @parser.TsUnaryOp::PreDec | @parser.TsUnaryOp::PostInc | @parser.TsUnaryOp::PostDec => infer_literal_type(e)
      }
    @parser.TsExpr::Call(_, _) => @parser.TsType::Any // 関数の戻り値型は文脈が必要
    @parser.TsExpr::CallExpr(_, _) => @parser.TsType::Any
    @parser.TsExpr::Cond(_, then_, _) => infer_literal_type(then_) // then 節の型
    @parser.TsExpr::IndexAccess(_, _) => @parser.TsType::Any // 配列要素型
    @parser.TsExpr::PropAccess(_, prop) =>
      if prop == "length" {
        @parser.TsType::Int
      } else {
        @parser.TsType::Any
      }
    @parser.TsExpr::New(_, _) => @parser.TsType::Any // コンストラクタの型
    @parser.TsExpr::NewExpr(_, _) => @parser.TsType::Any
    @parser.TsExpr::MethodCall(_, _, _) => @parser.TsType::Any // メソッドの戻り値型
    @parser.TsExpr::AssignExpr(_, e) => infer_literal_type(e) // 代入式の型は右辺の型
    @parser.TsExpr::ArrowFunc(_, _) => @parser.TsType::Any // アロー関数は @parser.TsType::Any
    @parser.TsExpr::FuncExpr(_) => @parser.TsType::Any // 関数式は @parser.TsType::Any
  }
}

///|
/// @parser.TsType::Any 型を解決する（可能であれば）
fn resolve_any(declared : @parser.TsType, init : @parser.TsExpr) -> @parser.TsType {
  match declared {
    @parser.TsType::Any => infer_literal_type(init)
    _ => declared
  }
}

///|
/// ローカル変数情報
priv struct LocalVar {
  index : UInt
  type_ : @parser.TsType
}

///|
/// コード生成コンテキスト
priv struct CodeGenCtx {
  // ローカル変数マップ (名前 → インデックス)
  locals : Map[String, LocalVar]
  // ローカル変数の型リスト (インデックス順)
  local_types : Array[@parser.TsType]
  // 次のローカル変数インデックス
  mut next_local : UInt
  // 関数マップ (名前 → インデックス)
  funcs : Map[String, UInt]
  // インターフェースマップ (名前 → フィールド情報)
  interfaces : Map[String, Array[(String, @parser.TsType)]]
  // インポート関数の型情報 (名前 → パラメータ型と戻り値型)
  import_types : Map[String, (Array[@parser.TsType], @parser.TsType)]
  // 生成された命令列
  instrs : Array[@core.Instr]
  // ループのネスト深さ (break/continue 用)
  mut loop_depth : Int
  // 文字列プール
  string_pool : StringPool
  // 使用されたビルトイン関数
  builtins_used : Map[String, Bool]
}

///|
/// コンテキスト作成
fn CodeGenCtx::new(
  funcs : Map[String, UInt],
  interfaces : Map[String, Array[(String, @parser.TsType)]],
  import_types : Map[String, (Array[@parser.TsType], @parser.TsType)],
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
/// ローカル変数を追加
fn CodeGenCtx::add_local(
  self : CodeGenCtx,
  name : String,
  type_ : @parser.TsType,
) -> UInt {
  let idx = self.next_local
  self.locals[name] = { index: idx, type_ }
  self.local_types.push(type_)
  self.next_local += 1
  idx
}

///|
/// ローカル変数を検索
fn CodeGenCtx::get_local(self : CodeGenCtx, name : String) -> LocalVar? {
  self.locals.get(name)
}

///|
/// 命令を追加
fn CodeGenCtx::emit(self : CodeGenCtx, instr : @core.Instr) -> Unit {
  self.instrs.push(instr)
}

// ============================================
// 型変換
// ============================================

///|
/// @parser.TsType → ValType
fn ts_type_to_valtype(t : @parser.TsType) -> @core.ValType {
  match t {
    @parser.TsType::Number => F64
    @parser.TsType::Int => I32
    @parser.TsType::Boolean => I32
    @parser.TsType::String_ => I32 // 文字列はメモリ上のポインタ
    @parser.TsType::Void => I32 // void は実際には使わない
    _ => F64 // デフォルトは f64
  }
}

///|
/// @parser.TsType が f64 か
fn is_f64_type(t : @parser.TsType) -> Bool {
  match t {
    @parser.TsType::Number => true
    _ => false
  }
}

///|
/// 式の型を推論
fn infer_type(ctx : CodeGenCtx, expr : @parser.TsExpr) -> @parser.TsType {
  match expr {
    @parser.TsExpr::NumberLit(_) => @parser.TsType::Number
    @parser.TsExpr::IntLit(_) => @parser.TsType::Int
    @parser.TsExpr::BoolLit(_) => @parser.TsType::Boolean
    @parser.TsExpr::StringLit(_) => @parser.TsType::String_
    @parser.TsExpr::NullLit => @parser.TsType::Any // null は @parser.TsType::Any
    @parser.TsExpr::ObjectLit(_) => @parser.TsType::Any // オブジェクトリテラルは @parser.TsType::Any
    @parser.TsExpr::Seq(_, right) => infer_type(ctx, right)
    @parser.TsExpr::PropAssignExpr(_, _, value) => infer_type(ctx, value)
    @parser.TsExpr::IndexAssignExpr(_, _, value) => infer_type(ctx, value)
    @parser.TsExpr::Var(name) =>
      match ctx.get_local(name) {
        Some(local_var) => local_var.type_
        None => @parser.TsType::Number // デフォルト
      }
    @parser.TsExpr::BinOp(op, left, right) =>
      match op {
        // 比較演算子は @parser.TsType::Boolean を返す
        @parser.TsBinOp::BinLt
        | @parser.TsBinOp::BinLe
        | @parser.TsBinOp::BinGt
        | @parser.TsBinOp::BinGe
        | @parser.TsBinOp::BinEq
        | @parser.TsBinOp::BinNe
        | @parser.TsBinOp::AbstractEq
        | @parser.TsBinOp::AbstractNe
        | @parser.TsBinOp::Instanceof
        | @parser.TsBinOp::In => @parser.TsType::Boolean
        // 論理演算子は @parser.TsType::Boolean を返す
        @parser.TsBinOp::And | @parser.TsBinOp::Or => @parser.TsType::Boolean
        // @parser.TsBinOp::Add: 文字列連結のチェック
        @parser.TsBinOp::Add => {
          let left_t = infer_type(ctx, left)
          let right_t = infer_type(ctx, right)
          if left_t == @parser.TsType::String_ || right_t == @parser.TsType::String_ {
            @parser.TsType::String_
          } else {
            left_t
          }
        }
        // その他の算術演算子は左辺の型を継承
        _ => infer_type(ctx, left)
      }
    @parser.TsExpr::UnaryOp(op, operand) =>
      match op {
        @parser.TsUnaryOp::Neg | @parser.TsUnaryOp::Plus => infer_type(ctx, operand)
        @parser.TsUnaryOp::Not => @parser.TsType::Boolean
        @parser.TsUnaryOp::Typeof => @parser.TsType::String_
        @parser.TsUnaryOp::Void => @parser.TsType::Any
        @parser.TsUnaryOp::Delete => @parser.TsType::Boolean
        @parser.TsUnaryOp::PreInc | @parser.TsUnaryOp::PreDec | @parser.TsUnaryOp::PostInc | @parser.TsUnaryOp::PostDec => infer_type(ctx, operand)
      }
    @parser.TsExpr::Call(_, _) => @parser.TsType::Number // 関数の戻り値型は後で取得
    @parser.TsExpr::CallExpr(_, _) => @parser.TsType::Number
    @parser.TsExpr::Cond(_, then_expr, _) => infer_type(ctx, then_expr)
    @parser.TsExpr::ArrayLit(elements) =>
      if elements.length() > 0 {
        @parser.TsType::Array(infer_type(ctx, elements[0]))
      } else {
        @parser.TsType::Array(@parser.TsType::Number) // デフォルト
      }
    @parser.TsExpr::IndexAccess(arr, _) =>
      match infer_type(ctx, arr) {
        @parser.TsType::Array(elem_type) => elem_type
        _ => @parser.TsType::Number
      }
    @parser.TsExpr::PropAccess(_, prop) =>
      if prop == "length" {
        @parser.TsType::Int
      } else {
        @parser.TsType::Number
      }
    @parser.TsExpr::New(_, _) => @parser.TsType::Array(@parser.TsType::Number) // new Array<T>() → @parser.TsType::Array(T)
    @parser.TsExpr::NewExpr(_, _) => @parser.TsType::Any
    @parser.TsExpr::MethodCall(receiver, method_name, _) => {
      let recv_type = infer_type(ctx, receiver)
      match recv_type {
        @parser.TsType::String_ =>
          match method_name {
            "charAt" => @parser.TsType::String_ // charAt returns string (single char)
            "charCodeAt" => @parser.TsType::Int // charCodeAt returns int
            "substring" => @parser.TsType::String_ // substring returns string
            "concat" => @parser.TsType::String_ // concat returns string
            _ => @parser.TsType::Number
          }
        @parser.TsType::Array(_) =>
          match method_name {
            "push" => @parser.TsType::Int // push returns new length
            "pop" => @parser.TsType::Number // pop returns element
            _ => @parser.TsType::Number
          }
        _ => @parser.TsType::Number
      }
    }
    @parser.TsExpr::AssignExpr(_, e) => infer_type(ctx, e) // 代入式の型は右辺の型
    @parser.TsExpr::ArrowFunc(_, _) => @parser.TsType::Any // アロー関数は @parser.TsType::Any
    @parser.TsExpr::FuncExpr(_) => @parser.TsType::Any // 関数式は @parser.TsType::Any
  }
}

///|
/// 要素サイズを取得 (バイト単位)
fn element_size(t : @parser.TsType) -> Int {
  match t {
    @parser.TsType::Number => 8 // f64 = 8 bytes
    @parser.TsType::Int => 4 // i32 = 4 bytes
    @parser.TsType::Boolean => 4 // i32 = 4 bytes
    @parser.TsType::String_ => 4 // ポインタ = 4 bytes
    @parser.TsType::Array(_) => 4 // ポインタ = 4 bytes
    @parser.TsType::Named(_) => 4 // 構造体ポインタ = 4 bytes
    @parser.TsType::Struct(_, _) => 4 // 構造体ポインタ = 4 bytes
    _ => 8
  }
}

///|
/// 構造体のサイズを計算
fn struct_size(fields : Array[(String, @parser.TsType)]) -> Int {
  let mut size = 0
  for i = 0; i < fields.length(); i = i + 1 {
    let (_, field_type) = fields[i]
    size += element_size(field_type)
  }
  size
}

///|
/// 構造体フィールドのオフセットを計算
fn field_offset(fields : Array[(String, @parser.TsType)], field_name : String) -> Int? {
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
/// 構造体フィールドの型を取得
fn field_type(fields : Array[(String, @parser.TsType)], field_name : String) -> @parser.TsType? {
  for i = 0; i < fields.length(); i = i + 1 {
    let (name, field_type) = fields[i]
    if name == field_name {
      return Some(field_type)
    }
  }
  None
}

// ============================================
// 式のコード生成
// ============================================

///|
/// 式をコンパイル
fn compile_expr(
  ctx : CodeGenCtx,
  expr : @parser.TsExpr,
  expected_type : @parser.TsType,
) -> Unit raise CodeGenError {
  match expr {
    @parser.TsExpr::NumberLit(n) =>
      if is_f64_type(expected_type) {
        ctx.emit(F64Const(n))
      } else {
        // i32 にキャスト
        ctx.emit(I32Const(n.to_int().reinterpret_as_uint()))
      }
    @parser.TsExpr::IntLit(i) =>
      if is_f64_type(expected_type) {
        ctx.emit(F64Const(i.to_double()))
      } else {
        ctx.emit(I32Const(i.reinterpret_as_uint()))
      }
    @parser.TsExpr::BoolLit(b) => ctx.emit(I32Const(if b { 1U } else { 0U }))
    @parser.TsExpr::StringLit(s) => {
      // 文字列プールに追加してオフセットを取得 (スナップショット方式)
      let offset = ctx.string_pool.add(s)
      // データセクションへのポインタを返す
      ctx.emit(I32Const(offset.reinterpret_as_uint()))
    }
    @parser.TsExpr::Var(name) =>
      match ctx.get_local(name) {
        Some(local_var) => ctx.emit(LocalGet(local_var.index))
        None => raise CodeGenError("Undefined variable: \{name}")
      }
    @parser.TsExpr::Seq(_, _) =>
      raise CodeGenError(
        "comma operator is not supported in Wasm compiler (use interpreter)",
      )
    @parser.TsExpr::PropAssignExpr(_, _, _) =>
      raise CodeGenError(
        "property assignment expression is not supported in Wasm compiler",
      )
    @parser.TsExpr::IndexAssignExpr(_, _, _) =>
      raise CodeGenError(
        "index assignment expression is not supported in Wasm compiler",
      )
    @parser.TsExpr::BinOp(op, left, right) => compile_binop(ctx, op, left, right, expected_type)
    @parser.TsExpr::UnaryOp(op, operand) => compile_unaryop(ctx, op, operand, expected_type)
    @parser.TsExpr::Call(name, args) => compile_call(ctx, name, args, expected_type)
    @parser.TsExpr::CallExpr(_, _) =>
      raise CodeGenError("call expression is not supported in Wasm compiler")
    @parser.TsExpr::Cond(cond, then_expr, else_expr) => {
      // 条件をコンパイル
      compile_expr(ctx, cond, @parser.TsType::Boolean)
      // then 部分
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
      // else 部分
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
      // If 式として生成
      let result_type = ts_type_to_valtype(expected_type)
      ctx.emit(If(Value(result_type), then_ctx.instrs, else_ctx.instrs))
    }
    @parser.TsExpr::ArrayLit(elements) => compile_array_lit(ctx, elements, expected_type)
    @parser.TsExpr::IndexAccess(arr, index) =>
      compile_index_access(ctx, arr, index, expected_type)
    @parser.TsExpr::PropAccess(obj, prop) => compile_prop_access(ctx, obj, prop, expected_type)
    @parser.TsExpr::New(type_name, args) =>
      compile_new_expr(ctx, type_name, args, expected_type)
    @parser.TsExpr::NewExpr(_, _) =>
      raise CodeGenError("new expression is not supported in Wasm compiler")
    @parser.TsExpr::MethodCall(receiver, method_name, args) =>
      compile_method_call(ctx, receiver, method_name, args, expected_type)
    // 以下は静的Wasmコンパイラでは未サポート（インタプリタのみ）
    @parser.TsExpr::NullLit => ctx.emit(I32Const(0U)) // null = 0
    @parser.TsExpr::ObjectLit(_) =>
      raise CodeGenError(
        "ObjectLit is not supported in Wasm compiler (use interpreter)",
      )
    @parser.TsExpr::AssignExpr(_, _) =>
      raise CodeGenError(
        "AssignExpr is not supported in Wasm compiler (use interpreter)",
      )
    @parser.TsExpr::ArrowFunc(_, _) =>
      raise CodeGenError(
        "ArrowFunc is not supported in Wasm compiler (use interpreter)",
      )
    @parser.TsExpr::FuncExpr(_) =>
      raise CodeGenError(
        "FuncExpr is not supported in Wasm compiler (use interpreter)",
      )
  }
}

///|
/// 配列リテラルをコンパイル
fn compile_array_lit(
  ctx : CodeGenCtx,
  elements : Array[@parser.TsExpr],
  expected_type : @parser.TsType,
) -> Unit raise CodeGenError {
  let elem_type = match expected_type {
    @parser.TsType::Array(t) => t
    _ => @parser.TsType::Number
  }
  let elem_sz = element_size(elem_type)
  let length = elements.length()

  // メモリ割り当て: 4 (length) + length * elem_size
  // グローバル変数 0 = ヒープポインタ
  ctx.emit(GlobalGet(0U)) // 現在のヒープポインタを取得

  // 長さを格納
  ctx.emit(GlobalGet(0U))
  ctx.emit(I32Const(length.reinterpret_as_uint()))
  ctx.emit(I32Store(2U, 0U, 0U))

  // 各要素を格納
  for i, elem in elements {
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

  // ヒープポインタを進める
  ctx.emit(GlobalGet(0U))
  ctx.emit(I32Const((4 + length * elem_sz).reinterpret_as_uint()))
  ctx.emit(I32Add)
  ctx.emit(GlobalSet(0U))
}

///|
/// 配列アクセスをコンパイル
fn compile_index_access(
  ctx : CodeGenCtx,
  arr : @parser.TsExpr,
  index : @parser.TsExpr,
  expected_type : @parser.TsType,
) -> Unit raise CodeGenError {
  let arr_type = infer_type(ctx, arr)
  let elem_type = match arr_type {
    @parser.TsType::Array(t) => t
    _ => expected_type
  }
  let elem_sz = element_size(elem_type)

  // アドレス計算: arr + 4 + index * elem_size
  compile_expr(ctx, arr, arr_type) // 配列のベースアドレス
  ctx.emit(I32Const(4U)) // 長さフィールドをスキップ
  ctx.emit(I32Add)
  compile_expr(ctx, index, @parser.TsType::Int)
  ctx.emit(I32Const(elem_sz.reinterpret_as_uint()))
  ctx.emit(I32Mul)
  ctx.emit(I32Add)

  // 値をロード
  if is_f64_type(elem_type) {
    ctx.emit(F64Load(3U, 0U, 0U))
  } else {
    ctx.emit(I32Load(2U, 0U, 0U))
  }
}

///|
/// プロパティアクセスをコンパイル
fn compile_prop_access(
  ctx : CodeGenCtx,
  obj : @parser.TsExpr,
  prop : String,
  _expected_type : @parser.TsType,
) -> Unit raise CodeGenError {
  let obj_type = infer_type(ctx, obj)

  // 配列/文字列の length プロパティ
  match obj_type {
    @parser.TsType::Array(_) =>
      if prop == "length" {
        compile_expr(ctx, obj, obj_type)
        ctx.emit(I32Load(2U, 0U, 0U)) // 最初の4バイト = 長さ
        return
      }
    @parser.TsType::String_ =>
      if prop == "length" {
        compile_expr(ctx, obj, obj_type)
        ctx.emit(I32Load(2U, 0U, 0U)) // 最初の4バイト = 長さ
        return
      }
    @parser.TsType::Named(type_name) =>
      // 構造体フィールドアクセス
      match ctx.interfaces.get(type_name) {
        Some(fields) =>
          match field_offset(fields, prop) {
            Some(offset) => {
              compile_expr(ctx, obj, obj_type) // 構造体のアドレス
              ctx.emit(I32Const(offset.reinterpret_as_uint()))
              ctx.emit(I32Add)
              // フィールドの型に応じてロード
              match field_type(fields, prop) {
                Some(@parser.TsType::Number) => ctx.emit(F64Load(3U, 0U, 0U))
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
/// new 式をコンパイル
fn compile_new_expr(
  ctx : CodeGenCtx,
  type_name : String,
  args : Array[@parser.TsExpr],
  _expected_type : @parser.TsType,
) -> Unit raise CodeGenError {
  if type_name == "Array" {
    // new Array<T>(size)
    let elem_type = match _expected_type {
      @parser.TsType::Array(t) => t
      _ => @parser.TsType::Number
    }
    let elem_sz = element_size(elem_type)
    if args.length() < 1 {
      raise CodeGenError("Array constructor requires size argument")
    }

    // サイズを取得
    compile_expr(ctx, args[0], @parser.TsType::Int)
    let size_local = ctx.add_local("__array_size__", @parser.TsType::Int)
    ctx.emit(LocalSet(size_local))

    // 現在のヒープポインタを配列のアドレスとして使う
    ctx.emit(GlobalGet(0U))

    // 長さを格納
    ctx.emit(GlobalGet(0U))
    ctx.emit(LocalGet(size_local))
    ctx.emit(I32Store(2U, 0U, 0U))

    // ヒープポインタを進める: 4 + size * elem_size
    ctx.emit(GlobalGet(0U))
    ctx.emit(I32Const(4U))
    ctx.emit(I32Add)
    ctx.emit(LocalGet(size_local))
    ctx.emit(I32Const(elem_sz.reinterpret_as_uint()))
    ctx.emit(I32Mul)
    ctx.emit(I32Add)
    ctx.emit(GlobalSet(0U))
  } else {
    // 構造体の new
    match ctx.interfaces.get(type_name) {
      Some(fields) => {
        let size = struct_size(fields)

        // 現在のヒープポインタを構造体のアドレスとして使う
        ctx.emit(GlobalGet(0U))

        // ヒープポインタを進める
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
/// メソッド呼び出しをコンパイル
fn compile_method_call(
  ctx : CodeGenCtx,
  receiver : @parser.TsExpr,
  method_name : String,
  args : Array[@parser.TsExpr],
  _expected_type : @parser.TsType,
) -> Unit raise CodeGenError {
  let recv_type = infer_type(ctx, receiver)
  match recv_type {
    @parser.TsType::String_ => compile_string_method(ctx, receiver, method_name, args)
    @parser.TsType::Array(_) => compile_array_method(ctx, receiver, method_name, args, recv_type)
    _ => raise CodeGenError("Cannot call method on type: \{recv_type}")
  }
}

///|
/// 文字列メソッドをコンパイル
fn compile_string_method(
  ctx : CodeGenCtx,
  receiver : @parser.TsExpr,
  method_name : String,
  args : Array[@parser.TsExpr],
) -> Unit raise CodeGenError {
  match method_name {
    "charCodeAt" => {
      // str.charCodeAt(index) → str[4 + index] (1バイト読み込み)
      if args.length() < 1 {
        raise CodeGenError("charCodeAt requires 1 argument")
      }
      compile_expr(ctx, receiver, @parser.TsType::String_) // 文字列のアドレス
      ctx.emit(I32Const(4U)) // 長さフィールドをスキップ
      ctx.emit(I32Add)
      compile_expr(ctx, args[0], @parser.TsType::Int) // インデックス
      ctx.emit(I32Add)
      ctx.emit(I32Load8U(0U, 0U, 0U)) // 1バイト読み込み (符号なし)
    }
    "charAt" => {
      // str.charAt(index) → 新しい1文字の文字列を作成
      if args.length() < 1 {
        raise CodeGenError("charAt requires 1 argument")
      }
      // 文字コードを取得
      compile_expr(ctx, receiver, @parser.TsType::String_)
      ctx.emit(I32Const(4U))
      ctx.emit(I32Add)
      compile_expr(ctx, args[0], @parser.TsType::Int)
      ctx.emit(I32Add)
      ctx.emit(I32Load8U(0U, 0U, 0U))
      let char_local = ctx.add_local("__char__", @parser.TsType::Int)
      ctx.emit(LocalSet(char_local))

      // 新しい文字列を作成: [length=1][char]
      ctx.emit(GlobalGet(0U)) // 結果のアドレス

      // 長さを格納
      ctx.emit(GlobalGet(0U))
      ctx.emit(I32Const(1U)) // length = 1
      ctx.emit(I32Store(2U, 0U, 0U))

      // 文字を格納
      ctx.emit(GlobalGet(0U))
      ctx.emit(I32Const(4U))
      ctx.emit(I32Add)
      ctx.emit(LocalGet(char_local))
      ctx.emit(I32Store8(0U, 0U, 0U))

      // ヒープポインタを進める (8バイトアライン)
      ctx.emit(GlobalGet(0U))
      ctx.emit(I32Const(8U))
      ctx.emit(I32Add)
      ctx.emit(GlobalSet(0U))
    }
    "substring" => {
      // str.substring(start, end) → 部分文字列
      if args.length() < 2 {
        raise CodeGenError("substring requires 2 arguments")
      }
      // 引数を評価
      compile_expr(ctx, args[0], @parser.TsType::Int)
      let start_local = ctx.add_local("__substr_start__", @parser.TsType::Int)
      ctx.emit(LocalSet(start_local))
      compile_expr(ctx, args[1], @parser.TsType::Int)
      let end_local = ctx.add_local("__substr_end__", @parser.TsType::Int)
      ctx.emit(LocalSet(end_local))

      // 長さを計算
      ctx.emit(LocalGet(end_local))
      ctx.emit(LocalGet(start_local))
      ctx.emit(I32Sub)
      let len_local = ctx.add_local("__substr_len__", @parser.TsType::Int)
      ctx.emit(LocalSet(len_local))

      // 新しい文字列のアドレス
      ctx.emit(GlobalGet(0U))

      // 長さを格納
      ctx.emit(GlobalGet(0U))
      ctx.emit(LocalGet(len_local))
      ctx.emit(I32Store(2U, 0U, 0U))

      // 元の文字列のアドレスを取得
      compile_expr(ctx, receiver, @parser.TsType::String_)
      let src_local = ctx.add_local("__substr_src__", @parser.TsType::Int)
      ctx.emit(LocalSet(src_local))

      // コピーループ (memory.copy がない場合の簡易実装)
      let i_local = ctx.add_local("__substr_i__", @parser.TsType::Int)
      ctx.emit(I32Const(0U))
      ctx.emit(LocalSet(i_local))

      // ループ開始
      let loop_instrs : Array[@core.Instr] = []
      // 条件: i < len
      loop_instrs.push(LocalGet(i_local))
      loop_instrs.push(LocalGet(len_local))
      loop_instrs.push(I32GeS)
      loop_instrs.push(BrIf(1U))

      // コピー: dst[4+i] = src[4+start+i]
      // dst アドレス
      loop_instrs.push(GlobalGet(0U))
      loop_instrs.push(I32Const(4U))
      loop_instrs.push(I32Add)
      loop_instrs.push(LocalGet(i_local))
      loop_instrs.push(I32Add)

      // src から読み込み
      loop_instrs.push(LocalGet(src_local))
      loop_instrs.push(I32Const(4U))
      loop_instrs.push(I32Add)
      loop_instrs.push(LocalGet(start_local))
      loop_instrs.push(I32Add)
      loop_instrs.push(LocalGet(i_local))
      loop_instrs.push(I32Add)
      loop_instrs.push(I32Load8U(0U, 0U, 0U))

      // 書き込み
      loop_instrs.push(I32Store8(0U, 0U, 0U))

      // i++
      loop_instrs.push(LocalGet(i_local))
      loop_instrs.push(I32Const(1U))
      loop_instrs.push(I32Add)
      loop_instrs.push(LocalSet(i_local))
      loop_instrs.push(Br(0U))
      ctx.emit(Block(Empty, [Loop(Empty, loop_instrs)]))

      // ヒープポインタを進める
      ctx.emit(GlobalGet(0U))
      ctx.emit(I32Const(4U))
      ctx.emit(LocalGet(len_local))
      ctx.emit(I32Add)
      // 4バイトアライン
      ctx.emit(I32Const(3U))
      ctx.emit(I32Add)
      ctx.emit(I32Const(0xFFFFFFFCU))
      ctx.emit(I32And)
      ctx.emit(I32Add)
      ctx.emit(GlobalSet(0U))
    }
    "concat" => {
      // str.concat(other) → 連結した新しい文字列
      if args.length() < 1 {
        raise CodeGenError("concat requires 1 argument")
      }
      compile_string_concat(ctx, receiver, args[0])
    }
    _ => raise CodeGenError("Unknown string method: \{method_name}")
  }
}

///|
/// 文字列連結をコンパイル
fn compile_string_concat(
  ctx : CodeGenCtx,
  left : @parser.TsExpr,
  right : @parser.TsExpr,
) -> Unit raise CodeGenError {
  // 左の文字列
  compile_expr(ctx, left, @parser.TsType::String_)
  let left_local = ctx.add_local("__concat_left__", @parser.TsType::Int)
  ctx.emit(LocalSet(left_local))

  // 右の文字列
  compile_expr(ctx, right, @parser.TsType::String_)
  let right_local = ctx.add_local("__concat_right__", @parser.TsType::Int)
  ctx.emit(LocalSet(right_local))

  // 左の長さ
  ctx.emit(LocalGet(left_local))
  ctx.emit(I32Load(2U, 0U, 0U))
  let left_len = ctx.add_local("__concat_left_len__", @parser.TsType::Int)
  ctx.emit(LocalSet(left_len))

  // 右の長さ
  ctx.emit(LocalGet(right_local))
  ctx.emit(I32Load(2U, 0U, 0U))
  let right_len = ctx.add_local("__concat_right_len__", @parser.TsType::Int)
  ctx.emit(LocalSet(right_len))

  // 合計長さ
  ctx.emit(LocalGet(left_len))
  ctx.emit(LocalGet(right_len))
  ctx.emit(I32Add)
  let total_len = ctx.add_local("__concat_total_len__", @parser.TsType::Int)
  ctx.emit(LocalSet(total_len))

  // 新しい文字列のアドレス
  ctx.emit(GlobalGet(0U))

  // 長さを格納
  ctx.emit(GlobalGet(0U))
  ctx.emit(LocalGet(total_len))
  ctx.emit(I32Store(2U, 0U, 0U))

  // 左側をコピー
  let i_local = ctx.add_local("__concat_i__", @parser.TsType::Int)
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

  // 右側をコピー
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

  // ヒープポインタを進める
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
/// 配列メソッドをコンパイル
fn compile_array_method(
  ctx : CodeGenCtx,
  receiver : @parser.TsExpr,
  method_name : String,
  args : Array[@parser.TsExpr],
  arr_type : @parser.TsType,
) -> Unit raise CodeGenError {
  let elem_type = match arr_type {
    @parser.TsType::Array(t) => t
    _ => @parser.TsType::Number
  }
  match method_name {
    "push" => {
      // arr.push(value) → 要素を追加して新しい長さを返す
      if args.length() < 1 {
        raise CodeGenError("push requires 1 argument")
      }
      // 配列のアドレスを取得
      compile_expr(ctx, receiver, arr_type)
      let arr_local = ctx.add_local("__push_arr__", @parser.TsType::Int)
      ctx.emit(LocalSet(arr_local))

      // 現在の長さを取得
      ctx.emit(LocalGet(arr_local))
      ctx.emit(I32Load(2U, 0U, 0U))
      let len_local = ctx.add_local("__push_len__", @parser.TsType::Int)
      ctx.emit(LocalSet(len_local))

      // 新しい要素を格納
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

      // 長さを更新
      ctx.emit(LocalGet(arr_local))
      ctx.emit(LocalGet(len_local))
      ctx.emit(I32Const(1U))
      ctx.emit(I32Add)
      ctx.emit(I32Store(2U, 0U, 0U))

      // 新しい長さを返す
      ctx.emit(LocalGet(len_local))
      ctx.emit(I32Const(1U))
      ctx.emit(I32Add)
    }
    _ => raise CodeGenError("Unknown array method: \{method_name}")
  }
}

///|
/// プロパティへの代入をコンパイル
fn compile_prop_assign(
  ctx : CodeGenCtx,
  obj : @parser.TsExpr,
  prop : String,
  value : @parser.TsExpr,
) -> Unit raise CodeGenError {
  let obj_type = infer_type(ctx, obj)
  match obj_type {
    @parser.TsType::Named(type_name) =>
      match ctx.interfaces.get(type_name) {
        Some(fields) =>
          match field_offset(fields, prop) {
            Some(offset) => {
              // アドレス計算
              compile_expr(ctx, obj, obj_type)
              ctx.emit(I32Const(offset.reinterpret_as_uint()))
              ctx.emit(I32Add)
              // 値をストア
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
/// 配列要素への代入をコンパイル
fn compile_index_assign(
  ctx : CodeGenCtx,
  arr : @parser.TsExpr,
  index : @parser.TsExpr,
  value : @parser.TsExpr,
) -> Unit raise CodeGenError {
  let arr_type = infer_type(ctx, arr)
  let elem_type = match arr_type {
    @parser.TsType::Array(t) => t
    _ => @parser.TsType::Number
  }
  let elem_sz = element_size(elem_type)

  // アドレス計算: arr + 4 + index * elem_size
  compile_expr(ctx, arr, arr_type) // 配列のベースアドレス
  ctx.emit(I32Const(4U)) // 長さフィールドをスキップ
  ctx.emit(I32Add)
  compile_expr(ctx, index, @parser.TsType::Int)
  ctx.emit(I32Const(elem_sz.reinterpret_as_uint()))
  ctx.emit(I32Mul)
  ctx.emit(I32Add)

  // 値をストア
  compile_expr(ctx, value, elem_type)
  if is_f64_type(elem_type) {
    ctx.emit(F64Store(3U, 0U, 0U))
  } else {
    ctx.emit(I32Store(2U, 0U, 0U))
  }
}

///|
/// 二項演算をコンパイル
fn compile_binop(
  ctx : CodeGenCtx,
  op : @parser.TsBinOp,
  left : @parser.TsExpr,
  right : @parser.TsExpr,
  expected_type : @parser.TsType,
) -> Unit raise CodeGenError {
  // 文字列連結のチェック
  let left_type = infer_type(ctx, left)
  let right_type = infer_type(ctx, right)
  if op == @parser.TsBinOp::Add && (left_type == @parser.TsType::String_ || right_type == @parser.TsType::String_) {
    // 文字列連結
    compile_string_concat(ctx, left, right)
    return
  }
  match op {
    @parser.TsBinOp::Pow | @parser.TsBinOp::BitAnd | @parser.TsBinOp::BitOr | @parser.TsBinOp::BitXor | @parser.TsBinOp::Shl | @parser.TsBinOp::Shr | @parser.TsBinOp::UShr | @parser.TsBinOp::In =>
      raise CodeGenError(
        "binary op is not supported in Wasm compiler (use interpreter)",
      )
    _ => ()
  }

  // 比較演算子のオペランドはオペランドの型を推論、論理演算子は @parser.TsType::Boolean
  let operand_type = match op {
    @parser.TsBinOp::Add
    | @parser.TsBinOp::Sub
    | @parser.TsBinOp::Mul
    | @parser.TsBinOp::Div
    | @parser.TsBinOp::Mod
    | @parser.TsBinOp::Pow => expected_type
    @parser.TsBinOp::BitAnd
    | @parser.TsBinOp::BitOr
    | @parser.TsBinOp::BitXor
    | @parser.TsBinOp::Shl
    | @parser.TsBinOp::Shr
    | @parser.TsBinOp::UShr => @parser.TsType::Int
    @parser.TsBinOp::BinLt
    | @parser.TsBinOp::BinLe
    | @parser.TsBinOp::BinGt
    | @parser.TsBinOp::BinGe
    | @parser.TsBinOp::BinEq
    | @parser.TsBinOp::BinNe
    | @parser.TsBinOp::AbstractEq
    | @parser.TsBinOp::AbstractNe =>
      // 両方 Int なら Int、それ以外は @parser.TsType::Number
      if left_type == @parser.TsType::Int && right_type == @parser.TsType::Int {
        @parser.TsType::Int
      } else {
        @parser.TsType::Number
      }
    @parser.TsBinOp::Instanceof | @parser.TsBinOp::In =>
      raise CodeGenError(
        "instanceof is not supported in Wasm compiler (use interpreter)",
      )
    @parser.TsBinOp::And | @parser.TsBinOp::Or => @parser.TsType::Boolean
  }
  compile_expr(ctx, left, operand_type)
  compile_expr(ctx, right, operand_type)
  if is_f64_type(operand_type) {
    // f64 演算
    match op {
      @parser.TsBinOp::Add => ctx.emit(F64Add)
      @parser.TsBinOp::Sub => ctx.emit(F64Sub)
      @parser.TsBinOp::Mul => ctx.emit(F64Mul)
      @parser.TsBinOp::Div => ctx.emit(F64Div)
      @parser.TsBinOp::Mod => raise CodeGenError("f64 mod not supported")
      @parser.TsBinOp::Pow =>
        raise CodeGenError(
          "pow is not supported in Wasm compiler (use interpreter)",
        )
      @parser.TsBinOp::BinLt => ctx.emit(F64Lt)
      @parser.TsBinOp::BinLe => ctx.emit(F64Le)
      @parser.TsBinOp::BinGt => ctx.emit(F64Gt)
      @parser.TsBinOp::BinGe => ctx.emit(F64Ge)
      @parser.TsBinOp::BinEq | @parser.TsBinOp::AbstractEq => ctx.emit(F64Eq)
      @parser.TsBinOp::BinNe | @parser.TsBinOp::AbstractNe => ctx.emit(F64Ne)
      @parser.TsBinOp::Instanceof | @parser.TsBinOp::In =>
        raise CodeGenError(
          "instanceof is not supported in Wasm compiler (use interpreter)",
        )
      @parser.TsBinOp::BitAnd | @parser.TsBinOp::BitOr | @parser.TsBinOp::BitXor | @parser.TsBinOp::Shl | @parser.TsBinOp::Shr | @parser.TsBinOp::UShr =>
        raise CodeGenError("bitwise op on f64")
      @parser.TsBinOp::And | @parser.TsBinOp::Or => raise CodeGenError("Logical op on f64")
    }
  } else {
    // i32 演算
    match op {
      @parser.TsBinOp::Add => ctx.emit(I32Add)
      @parser.TsBinOp::Sub => ctx.emit(I32Sub)
      @parser.TsBinOp::Mul => ctx.emit(I32Mul)
      @parser.TsBinOp::Div => ctx.emit(I32DivS)
      @parser.TsBinOp::Mod => ctx.emit(I32RemS)
      @parser.TsBinOp::Pow =>
        raise CodeGenError(
          "pow is not supported in Wasm compiler (use interpreter)",
        )
      @parser.TsBinOp::BitAnd => ctx.emit(I32And)
      @parser.TsBinOp::BitOr => ctx.emit(I32Or)
      @parser.TsBinOp::BitXor => ctx.emit(I32Xor)
      @parser.TsBinOp::Shl => ctx.emit(I32Shl)
      @parser.TsBinOp::Shr => ctx.emit(I32ShrS)
      @parser.TsBinOp::UShr => ctx.emit(I32ShrU)
      @parser.TsBinOp::BinLt => ctx.emit(I32LtS)
      @parser.TsBinOp::BinLe => ctx.emit(I32LeS)
      @parser.TsBinOp::BinGt => ctx.emit(I32GtS)
      @parser.TsBinOp::BinGe => ctx.emit(I32GeS)
      @parser.TsBinOp::BinEq | @parser.TsBinOp::AbstractEq => ctx.emit(I32Eq)
      @parser.TsBinOp::BinNe | @parser.TsBinOp::AbstractNe => ctx.emit(I32Ne)
      @parser.TsBinOp::Instanceof | @parser.TsBinOp::In =>
        raise CodeGenError(
          "instanceof is not supported in Wasm compiler (use interpreter)",
        )
      @parser.TsBinOp::And => ctx.emit(I32And)
      @parser.TsBinOp::Or => ctx.emit(I32Or)
    }
  }
}

///|
/// 単項演算をコンパイル
fn compile_unaryop(
  ctx : CodeGenCtx,
  op : @parser.TsUnaryOp,
  operand : @parser.TsExpr,
  expected_type : @parser.TsType,
) -> Unit raise CodeGenError {
  match op {
    @parser.TsUnaryOp::Neg =>
      if is_f64_type(expected_type) {
        compile_expr(ctx, operand, expected_type)
        ctx.emit(F64Neg)
      } else {
        // i32: 0 - x
        ctx.emit(I32Const(0U))
        compile_expr(ctx, operand, expected_type)
        ctx.emit(I32Sub)
      }
    @parser.TsUnaryOp::Not => {
      compile_expr(ctx, operand, @parser.TsType::Boolean)
      ctx.emit(I32Eqz)
    }
    @parser.TsUnaryOp::PreInc =>
      // ++x: x = x + 1, return new value
      match operand {
        @parser.TsExpr::Var(name) =>
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
    @parser.TsUnaryOp::PreDec =>
      // --x: x = x - 1, return new value
      match operand {
        @parser.TsExpr::Var(name) =>
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
    @parser.TsUnaryOp::PostInc =>
      // x++: return old value, then x = x + 1
      match operand {
        @parser.TsExpr::Var(name) =>
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
    @parser.TsUnaryOp::PostDec =>
      // x--: return old value, then x = x - 1
      match operand {
        @parser.TsExpr::Var(name) =>
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
    @parser.TsUnaryOp::Plus =>
      // 単項プラス: 数値への変換（そのまま出力）
      compile_expr(ctx, operand, expected_type)
    @parser.TsUnaryOp::Typeof =>
      // typeof は静的Wasmコンパイラでは未サポート
      raise CodeGenError(
        "typeof is not supported in Wasm compiler (use interpreter)",
      )
    @parser.TsUnaryOp::Void =>
      // void も未サポート
      raise CodeGenError(
        "void is not supported in Wasm compiler (use interpreter)",
      )
    @parser.TsUnaryOp::Delete =>
      raise CodeGenError(
        "delete is not supported in Wasm compiler (use interpreter)",
      )
  }
}

///|
/// 関数呼び出しをコンパイル
fn compile_call(
  ctx : CodeGenCtx,
  name : String,
  args : Array[@parser.TsExpr],
  expected_type : @parser.TsType,
) -> Unit raise CodeGenError {
  // 関数インデックスを取得
  match ctx.funcs.get(name) {
    Some(idx) => {
      // インポート関数の型情報があれば使用
      match ctx.import_types.get(name) {
        Some((param_types, _)) =>
          // インポート関数: パラメータ型を参照
          for i, arg in args {
            let param_type = if i < param_types.length() {
              param_types[i]
            } else {
              expected_type // 可変長引数の場合
            }
            compile_expr(ctx, arg, param_type)
          }
        None =>
          // ユーザー定義関数: expected_type を使用
          for arg in args {
            compile_expr(ctx, arg, expected_type)
          }
      }
      ctx.emit(Call(idx))
    }
    None => raise CodeGenError("Undefined function: \{name}")
  }
}

// ============================================
// 文のコード生成
// ============================================

///|
/// 文をコンパイル
fn compile_stmt(
  ctx : CodeGenCtx,
  stmt : @parser.TsStmt,
  return_type : @parser.TsType,
) -> Unit raise CodeGenError {
  match stmt {
    @parser.TsStmt::Let(name, type_, init) => {
      // @parser.TsType::Any 型はリテラルから推論
      let resolved_type = resolve_any(type_, init)
      let idx = ctx.add_local(name, resolved_type)
      compile_expr(ctx, init, resolved_type)
      ctx.emit(LocalSet(idx))
    }
    @parser.TsStmt::Const(name, type_, init) => {
      // const も let と同じ扱い、@parser.TsType::Any 型はリテラルから推論
      let resolved_type = resolve_any(type_, init)
      let idx = ctx.add_local(name, resolved_type)
      compile_expr(ctx, init, resolved_type)
      ctx.emit(LocalSet(idx))
    }
    @parser.TsStmt::Assign(name, expr) =>
      match ctx.get_local(name) {
        Some(lvar) => {
          compile_expr(ctx, expr, lvar.type_)
          ctx.emit(LocalSet(lvar.index))
        }
        None => raise CodeGenError("Undefined variable: \{name}")
      }
    @parser.TsStmt::CompoundAssign(name, op, expr) =>
      match ctx.get_local(name) {
        Some(lvar) => {
          // x op= expr → x = x op expr
          ctx.emit(LocalGet(lvar.index))
          compile_expr(ctx, expr, lvar.type_)
          if is_f64_type(lvar.type_) {
            match op {
              @parser.TsCompoundOp::AddAssign => ctx.emit(F64Add)
              @parser.TsCompoundOp::SubAssign => ctx.emit(F64Sub)
              @parser.TsCompoundOp::MulAssign => ctx.emit(F64Mul)
              @parser.TsCompoundOp::DivAssign => ctx.emit(F64Div)
              @parser.TsCompoundOp::ModAssign
              | @parser.TsCompoundOp::BitAndAssign
              | @parser.TsCompoundOp::BitOrAssign
              | @parser.TsCompoundOp::BitXorAssign
              | @parser.TsCompoundOp::ShlAssign
              | @parser.TsCompoundOp::ShrAssign
              | @parser.TsCompoundOp::UShrAssign
              | @parser.TsCompoundOp::PowAssign =>
                raise CodeGenError(
                  "compound op is not supported on f64 in Wasm compiler",
                )
            }
          } else {
            match op {
              @parser.TsCompoundOp::AddAssign => ctx.emit(I32Add)
              @parser.TsCompoundOp::SubAssign => ctx.emit(I32Sub)
              @parser.TsCompoundOp::MulAssign => ctx.emit(I32Mul)
              @parser.TsCompoundOp::DivAssign => ctx.emit(I32DivS)
              @parser.TsCompoundOp::ModAssign => ctx.emit(I32RemS)
              @parser.TsCompoundOp::BitAndAssign => ctx.emit(I32And)
              @parser.TsCompoundOp::BitOrAssign => ctx.emit(I32Or)
              @parser.TsCompoundOp::BitXorAssign => ctx.emit(I32Xor)
              @parser.TsCompoundOp::ShlAssign => ctx.emit(I32Shl)
              @parser.TsCompoundOp::ShrAssign => ctx.emit(I32ShrS)
              @parser.TsCompoundOp::UShrAssign => ctx.emit(I32ShrU)
              @parser.TsCompoundOp::PowAssign =>
                raise CodeGenError(
                  "pow= is not supported in Wasm compiler (use interpreter)",
                )
            }
          }
          ctx.emit(LocalSet(lvar.index))
        }
        None => raise CodeGenError("Undefined variable: \{name}")
      }
    @parser.TsStmt::IndexAssign(arr, index, value) =>
      compile_index_assign(ctx, arr, index, value)
    @parser.TsStmt::PropAssign(obj, prop, value) => compile_prop_assign(ctx, obj, prop, value)
    @parser.TsStmt::Expr(expr) => {
      compile_expr(ctx, expr, return_type)
      ctx.emit(Drop)
    }
    Empty => ()
    @parser.TsStmt::Block(block) => {
      for stmt in block.stmts {
        compile_stmt(ctx, stmt, return_type)
      }
    }
    @parser.TsStmt::Return(Some(expr)) => {
      compile_expr(ctx, expr, return_type)
      ctx.emit(Return)
    }
    @parser.TsStmt::Return(None) => ctx.emit(Return)
    @parser.TsStmt::Throw(_) =>
      raise CodeGenError("throw is not supported in Wasm compiler")
    @parser.TsStmt::Try(_, _, _, _) =>
      raise CodeGenError("try/catch/finally is not supported in Wasm compiler")
    @parser.TsStmt::If(cond, then_block, else_block) =>
      compile_if(ctx, cond, then_block, else_block, return_type)
    @parser.TsStmt::While(cond, body) => compile_while(ctx, cond, body, return_type)
    @parser.TsStmt::For(init, cond, update, body) =>
      compile_for(ctx, init, cond, update, body, return_type)
    @parser.TsStmt::ForOf(var_name, var_type, iterable, body) =>
      compile_for_of(ctx, var_name, var_type, iterable, body, return_type)
    Break =>
      // loop の外側の block へジャンプ
      ctx.emit(Br((ctx.loop_depth * 2 - 1).reinterpret_as_uint()))
    Continue =>
      // loop の先頭へジャンプ
      ctx.emit(Br(((ctx.loop_depth - 1) * 2).reinterpret_as_uint()))
  }
}

///|
/// if 文をコンパイル
fn compile_if(
  ctx : CodeGenCtx,
  cond : @parser.TsExpr,
  then_block : @parser.TsBlock,
  else_block : @parser.TsBlock?,
  return_type : @parser.TsType,
) -> Unit raise CodeGenError {
  compile_expr(ctx, cond, @parser.TsType::Boolean)
  let then_instrs = compile_block_to_instrs(ctx, then_block, return_type)
  let else_instrs = match else_block {
    Some(block) => compile_block_to_instrs(ctx, block, return_type)
    None => []
  }
  ctx.emit(If(Empty, then_instrs, else_instrs))
}

///|
/// while 文をコンパイル
fn compile_while(
  ctx : CodeGenCtx,
  cond : @parser.TsExpr,
  body : @parser.TsBlock,
  return_type : @parser.TsType,
) -> Unit raise CodeGenError {
  ctx.loop_depth += 1

  // Block(Loop([cond, BrIf(1), ...body, Br(0)]))
  let loop_instrs : Array[@core.Instr] = []

  // 条件チェック用の一時コンテキスト
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
  compile_expr(cond_ctx, cond, @parser.TsType::Boolean)
  for instr in cond_ctx.instrs {
    loop_instrs.push(instr)
  }
  loop_instrs.push(I32Eqz)
  loop_instrs.push(BrIf(1U)) // 条件が偽なら外のブロックへ

  // body
  let body_instrs = compile_block_to_instrs(ctx, body, return_type)
  for instr in body_instrs {
    loop_instrs.push(instr)
  }
  loop_instrs.push(Br(0U)) // ループ先頭へ
  ctx.emit(Block(Empty, [Loop(Empty, loop_instrs)]))
  ctx.loop_depth -= 1
}

///|
/// for 文をコンパイル
fn compile_for(
  ctx : CodeGenCtx,
  init : @parser.TsStmt?,
  cond : @parser.TsExpr?,
  update : @parser.TsStmt?,
  body : @parser.TsBlock,
  return_type : @parser.TsType,
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
      compile_expr(cond_ctx, c, @parser.TsType::Boolean)
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
  loop_instrs.push(Br(0U)) // ループ先頭へ
  ctx.emit(Block(Empty, [Loop(Empty, loop_instrs)]))
  ctx.loop_depth -= 1
}

///|
/// for...of をコンパイル
fn compile_for_of(
  ctx : CodeGenCtx,
  var_name : String,
  _var_type : @parser.TsType,
  iterable : @parser.TsExpr,
  body : @parser.TsBlock,
  return_type : @parser.TsType,
) -> Unit raise CodeGenError {
  // 配列を取得してローカル変数に保存
  let arr_type = infer_type(ctx, iterable)
  let elem_type = match arr_type {
    @parser.TsType::Array(t) => t
    _ => @parser.TsType::Number
  }

  // 配列のアドレスを保存
  let arr_local = ctx.add_local("__for_of_arr__", arr_type)
  compile_expr(ctx, iterable, arr_type)
  ctx.emit(LocalSet(arr_local))

  // 配列の長さを取得して保存
  let len_local = ctx.add_local("__for_of_len__", @parser.TsType::Int)
  ctx.emit(LocalGet(arr_local))
  ctx.emit(I32Load(2U, 0U, 0U))
  ctx.emit(LocalSet(len_local))

  // インデックス変数
  let idx_local = ctx.add_local("__for_of_idx__", @parser.TsType::Int)
  ctx.emit(I32Const(0U))
  ctx.emit(LocalSet(idx_local))

  // ループ変数
  let loop_var_idx = ctx.add_local(var_name, elem_type)
  ctx.loop_depth += 1
  let loop_instrs : Array[@core.Instr] = []

  // 条件: idx < len
  loop_instrs.push(LocalGet(idx_local))
  loop_instrs.push(LocalGet(len_local))
  loop_instrs.push(I32GeS)
  loop_instrs.push(BrIf(1U))

  // ループ変数に arr[idx] を代入
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
/// ブロックを命令列に変換（コンテキストを共有）
fn compile_block_to_instrs(
  ctx : CodeGenCtx,
  block : @parser.TsBlock,
  return_type : @parser.TsType,
) -> Array[@core.Instr] raise CodeGenError {
  // 同じコンテキストの locals と local_types を使う
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

  // ローカル変数の更新を反映
  ctx.next_local = sub_ctx.next_local
  sub_ctx.instrs
}

// ============================================
// 関数のコード生成
// ============================================

///|
/// 関数をコンパイル
fn compile_function(
  func : @parser.TsFunc,
  func_map : Map[String, UInt],
  interfaces : Map[String, Array[(String, @parser.TsType)]],
  import_types : Map[String, (Array[@parser.TsType], @parser.TsType)],
  string_pool : StringPool,
  builtins_used : Map[String, Bool],
) -> (@core.TypeDef, @core.Code) raise CodeGenError {
  let ctx = CodeGenCtx::new(
    func_map, interfaces, import_types, string_pool, builtins_used,
  )

  // パラメータをローカル変数として登録
  for param in func.params {
    let _ = ctx.add_local(param.name, param.type_)

  }

  // パラメータ以外のローカル変数を追跡
  let param_count = func.params.length().reinterpret_as_uint()

  // 関数本体をコンパイル
  for stmt in func.body.stmts {
    compile_stmt(ctx, stmt, func.return_type)
  }

  // 型定義
  let params : Array[@core.ValType] = []
  for param in func.params {
    params.push(ts_type_to_valtype(param.type_))
  }
  let results : Array[@core.ValType] = match func.return_type {
    @parser.TsType::Void => []
    t => [ts_type_to_valtype(t)]
  }
  let func_type : @core.TypeDef = @core.TypeDef::Func({ params, results })

  // ローカル変数（パラメータ以外）
  let locals : Array[@core.ValType] = []
  let mut i = param_count.reinterpret_as_int()
  while i < ctx.next_local.reinterpret_as_int() {
    locals.push(ts_type_to_valtype(ctx.local_types[i]))
    i += 1
  }

  // コード
  let code : @core.Code = {
    locals,
    body: @core.Expr::{ instrs: ctx.instrs },
    compiled: None,
    max_stack_height: 0,
  }
  (func_type, code)
}

// ============================================
// モジュールのコード生成
// ============================================

///|
/// モジュールをコンパイル
pub fn compile_module(module_ : @parser.TsModule) -> @core.Module raise CodeGenError {
  // インポート数を計算
  let num_imports = module_.imports.length().reinterpret_as_uint()

  // 関数マップを作成
  let func_map : Map[String, UInt] = {}

  // インポート関数を func_map に追加 (インデックス 0 から)
  for i, imp in module_.imports {
    func_map[imp.name] = i.reinterpret_as_uint()
  }

  // ユーザー定義関数を func_map に追加 (インポートの後)
  for i, func in module_.funcs {
    func_map[func.name] = i.reinterpret_as_uint() + num_imports
  }

  // インターフェースマップを作成
  let interface_map : Map[String, Array[(String, @parser.TsType)]] = {}
  for iface in module_.interfaces {
    interface_map[iface.name] = iface.fields
  }

  // インポート関数の型情報マップを作成
  let import_types : Map[String, (Array[@parser.TsType], @parser.TsType)] = {}
  for imp in module_.imports {
    let param_types : Array[@parser.TsType] = []
    for param in imp.params {
      param_types.push(param.1)
    }
    import_types[imp.name] = (param_types, imp.return_type)
  }

  // 文字列プールを作成 (スナップショット)
  let string_pool = StringPool::new()

  // 型定義 (インポート関数の型を先に追加)
  let types : Array[@core.TypeDef] = []
  for imp in module_.imports {
    let params : Array[@core.ValType] = []
    for param in imp.params {
      params.push(ts_type_to_valtype(param.1))
    }
    let results : Array[@core.ValType] = match imp.return_type {
      @parser.TsType::Void => []
      t => [ts_type_to_valtype(t)]
    }
    types.push(@core.TypeDef::Func({ params, results }))
  }

  // 各関数をコンパイル
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

    // すべての関数をエクスポート
    let name_bytes = string_to_bytes(func.name)
    exports.push({ name: name_bytes, desc: @core.ExportDesc::Func(func_idx) })
  }

  // Wasm インポートを生成
  let imports : Array[@core.Import] = []
  for i, imp in module_.imports {
    imports.push({
      module_: string_to_bytes(imp.module_),
      name: string_to_bytes(imp.name),
      desc: @core.ImportDesc::Func(i.reinterpret_as_uint()), // 型インデックス
    })
  }

  // メモリ (1ページ = 64KB)
  let mems : Array[@core.MemType] = [
    { limits: { min: 1UL, max: Some(16UL) }, shared: false, memory64: false },
  ]

  // 文字列プールデータをデータセクションに格納
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

  // ヒープポインタの初期値 = 文字列プールの終端 (4バイトアライン)
  let heap_start = (string_pool.offset() + 3) / 4 * 4
  let heap_start_aligned = if heap_start < 1024 { 1024 } else { heap_start }

  // グローバル変数 (ヒープポインタ)
  let globals : Array[@core.Global] = [
    {
      type_: { val_type: I32, mutable: true },
      init: { instrs: [I32Const(heap_start_aligned.reinterpret_as_uint())] },
    },
  ]

  // 型メタデータをカスタムセクションに格納 (スナップショット)
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
/// 文字列を Bytes に変換 (ASCII)
fn string_to_bytes(s : String) -> Bytes {
  let arr : Array[Byte] = []
  for i = 0; i < s.length(); i = i + 1 {
    arr.push((s[i].to_int() & 0xFF).to_byte())
  }
  Bytes::from_array(arr)
}

// ============================================
// 便利な統合関数
// ============================================

///|
/// コンパイルエラー (パース + コード生成)
pub suberror CompileError {
  CompileError(String)
} derive(Show)

///|
/// TypeScript ソースコードを Wasm バイナリにコンパイル
pub fn compile_to_wasm(source : String) -> Bytes raise CompileError {
  // パース
  let parser = @parser.Parser::from_source(source)
  let ts_module = parser.parse_module() catch {
    @parser.ParseError::ParseError(msg) =>
      raise CompileError("Parse error: \{msg}")
  }

  // コード生成
  let wasm_module = compile_module(ts_module) catch {
    CodeGenError(msg) => raise CompileError("CodeGen error: \{msg}")
  }

  // Wasm バイナリにエンコード
  @encode.encode(wasm_module) catch {
    @encode.EncodeError::Unsupported(msg) =>
      raise CompileError("Encode error: \{msg}")
  }
}

///|
/// TypeScript ソースコードをパースして wasm5 Module を生成
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
