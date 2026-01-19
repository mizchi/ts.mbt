// TypeScript AST → wasm5 Instr 変換

///|
/// コード生成エラー
pub suberror CodeGenError {
  CodeGenError(String)
} derive(Show)

///|
/// 文字列プール (スナップショット用)
struct StringPool {
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
/// TsType を 1 バイトにエンコード
fn encode_type(t : TsType) -> Byte {
  match t {
    Number => b'\x00'
    Int => b'\x01'
    Boolean => b'\x02'
    String_ => b'\x03'
    Void => b'\x04'
    Any => b'\x05'
    Array(_) => b'\x06'
    Struct(_, _) => b'\x07'
    Func(_, _) => b'\x08'
    Named(_) => b'\x09'
  }
}

///|
/// 型メタデータをシリアライズ
fn serialize_type_metadata(module_ : TsModule) -> Bytes {
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
fn infer_literal_type(expr : TsExpr) -> TsType {
  match expr {
    IntLit(_) => Int
    NumberLit(_) => Number
    BoolLit(_) => Boolean
    StringLit(_) => String_
    NullLit => Any // null は Any
    ArrayLit(_) => Any // 要素型の推論は複雑なので Any
    ObjectLit(_) => Any // オブジェクトリテラルは Any
    Var(_) => Any // 変数は文脈から推論する必要あり
    BinOp(op, lhs, _) =>
      // 比較演算子は Boolean を返す
      match op {
        BinEq
        | BinNe
        | AbstractEq
        | AbstractNe
        | BinLt
        | BinLe
        | BinGt
        | BinGe
        | And
        | Or => Boolean
        Add | Sub | Mul | Div | Mod => infer_literal_type(lhs) // 左辺の型を継承
      }
    UnaryOp(op, e) =>
      match op {
        Neg | Plus => infer_literal_type(e)
        Not => Boolean
        Typeof => String_
        PreInc | PreDec | PostInc | PostDec => infer_literal_type(e)
      }
    Call(_, _) => Any // 関数の戻り値型は文脈が必要
    Cond(_, then_, _) => infer_literal_type(then_) // then 節の型
    IndexAccess(_, _) => Any // 配列要素型
    PropAccess(_, prop) => if prop == "length" { Int } else { Any }
    New(_, _) => Any // コンストラクタの型
    MethodCall(_, _, _) => Any // メソッドの戻り値型
    AssignExpr(_, e) => infer_literal_type(e) // 代入式の型は右辺の型
    ArrowFunc(_, _) => Any // アロー関数は Any
    FuncExpr(_) => Any // 関数式は Any
  }
}

///|
/// Any 型を解決する（可能であれば）
fn resolve_any(declared : TsType, init : TsExpr) -> TsType {
  match declared {
    Any => infer_literal_type(init)
    _ => declared
  }
}

///|
/// ローカル変数情報
struct LocalVar {
  index : UInt
  type_ : TsType
}

///|
/// コード生成コンテキスト
struct CodeGenCtx {
  // ローカル変数マップ (名前 → インデックス)
  locals : Map[String, LocalVar]
  // ローカル変数の型リスト (インデックス順)
  local_types : Array[TsType]
  // 次のローカル変数インデックス
  mut next_local : UInt
  // 関数マップ (名前 → インデックス)
  funcs : Map[String, UInt]
  // インターフェースマップ (名前 → フィールド情報)
  interfaces : Map[String, Array[(String, TsType)]]
  // インポート関数の型情報 (名前 → パラメータ型と戻り値型)
  import_types : Map[String, (Array[TsType], TsType)]
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
  interfaces : Map[String, Array[(String, TsType)]],
  import_types : Map[String, (Array[TsType], TsType)],
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
  type_ : TsType,
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
// ビルトイン関数使用チェック
// ============================================

///|
/// 式内で print が使われているかチェック
fn uses_print_expr(expr : TsExpr) -> Bool {
  match expr {
    Call("print", _) => true
    BinOp(_, lhs, rhs) => uses_print_expr(lhs) || uses_print_expr(rhs)
    UnaryOp(_, e) => uses_print_expr(e)
    Call(_, args) => args.iter().any(uses_print_expr)
    Cond(c, t, e) =>
      uses_print_expr(c) || uses_print_expr(t) || uses_print_expr(e)
    ArrayLit(elems) => elems.iter().any(uses_print_expr)
    IndexAccess(arr, idx) => uses_print_expr(arr) || uses_print_expr(idx)
    PropAccess(obj, _) => uses_print_expr(obj)
    New(_, args) => args.iter().any(uses_print_expr)
    MethodCall(recv, _, args) =>
      uses_print_expr(recv) || args.iter().any(uses_print_expr)
    _ => false
  }
}

///|
/// 文内で print が使われているかチェック
fn uses_print_stmt(stmt : TsStmt) -> Bool {
  match stmt {
    Let(_, _, expr) => uses_print_expr(expr)
    Const(_, _, expr) => uses_print_expr(expr)
    Assign(_, expr) => uses_print_expr(expr)
    CompoundAssign(_, _, expr) => uses_print_expr(expr)
    IndexAssign(arr, idx, val) =>
      uses_print_expr(arr) || uses_print_expr(idx) || uses_print_expr(val)
    PropAssign(obj, _, val) => uses_print_expr(obj) || uses_print_expr(val)
    Expr(expr) => uses_print_expr(expr)
    Return(Some(expr)) => uses_print_expr(expr)
    Return(None) => false
    If(cond, then_block, else_block) =>
      uses_print_expr(cond) ||
      uses_print_block(then_block) ||
      else_block.map_or(false, uses_print_block)
    While(cond, body) => uses_print_expr(cond) || uses_print_block(body)
    For(init, cond, update, body) =>
      init.map_or(false, uses_print_stmt) ||
      cond.map_or(false, uses_print_expr) ||
      update.map_or(false, uses_print_stmt) ||
      uses_print_block(body)
    ForOf(_, _, iter, body) => uses_print_expr(iter) || uses_print_block(body)
    Break | Continue => false
  }
}

///|
/// ブロック内で print が使われているかチェック
fn uses_print_block(block : TsBlock) -> Bool {
  block.stmts.iter().any(uses_print_stmt)
}

///|
/// 関数内で print が使われているかチェック
fn uses_print_func(func : TsFunc) -> Bool {
  uses_print_block(func.body)
}

///|
/// モジュール内で print が使われているかチェック
fn uses_print_module(module_ : TsModule) -> Bool {
  module_.funcs.iter().any(uses_print_func)
}

// ============================================
// 型変換
// ============================================

///|
/// TsType → ValType
fn ts_type_to_valtype(t : TsType) -> @core.ValType {
  match t {
    Number => F64
    Int => I32
    Boolean => I32
    String_ => I32 // 文字列はメモリ上のポインタ
    Void => I32 // void は実際には使わない
    _ => F64 // デフォルトは f64
  }
}

///|
/// TsType が f64 か
fn is_f64_type(t : TsType) -> Bool {
  match t {
    Number => true
    _ => false
  }
}

///|
/// 式の型を推論
fn infer_type(ctx : CodeGenCtx, expr : TsExpr) -> TsType {
  match expr {
    NumberLit(_) => Number
    IntLit(_) => Int
    BoolLit(_) => Boolean
    StringLit(_) => String_
    NullLit => Any // null は Any
    ObjectLit(_) => Any // オブジェクトリテラルは Any
    Var(name) =>
      match ctx.get_local(name) {
        Some(local_var) => local_var.type_
        None => Number // デフォルト
      }
    BinOp(op, left, right) =>
      match op {
        // 比較演算子は Boolean を返す
        BinLt
        | BinLe
        | BinGt
        | BinGe
        | BinEq
        | BinNe
        | AbstractEq
        | AbstractNe => Boolean
        // 論理演算子は Boolean を返す
        And | Or => Boolean
        // Add: 文字列連結のチェック
        Add => {
          let left_t = infer_type(ctx, left)
          let right_t = infer_type(ctx, right)
          if left_t == String_ || right_t == String_ {
            String_
          } else {
            left_t
          }
        }
        // その他の算術演算子は左辺の型を継承
        _ => infer_type(ctx, left)
      }
    UnaryOp(op, operand) =>
      match op {
        Neg | Plus => infer_type(ctx, operand)
        Not => Boolean
        Typeof => String_
        PreInc | PreDec | PostInc | PostDec => infer_type(ctx, operand)
      }
    Call(_, _) => Number // 関数の戻り値型は後で取得
    Cond(_, then_expr, _) => infer_type(ctx, then_expr)
    ArrayLit(elements) =>
      if elements.length() > 0 {
        Array(infer_type(ctx, elements[0]))
      } else {
        Array(Number) // デフォルト
      }
    IndexAccess(arr, _) =>
      match infer_type(ctx, arr) {
        Array(elem_type) => elem_type
        _ => Number
      }
    PropAccess(_, prop) => if prop == "length" { Int } else { Number }
    New(_, _) => Array(Number) // new Array<T>() → Array(T)
    MethodCall(receiver, method, _) => {
      let recv_type = infer_type(ctx, receiver)
      match recv_type {
        String_ =>
          match method {
            "charAt" => String_ // charAt returns string (single char)
            "charCodeAt" => Int // charCodeAt returns int
            "substring" => String_ // substring returns string
            "concat" => String_ // concat returns string
            _ => Number
          }
        Array(_) =>
          match method {
            "push" => Int // push returns new length
            "pop" => Number // pop returns element
            _ => Number
          }
        _ => Number
      }
    }
    AssignExpr(_, e) => infer_type(ctx, e) // 代入式の型は右辺の型
    ArrowFunc(_, _) => Any // アロー関数は Any
    FuncExpr(_) => Any // 関数式は Any
  }
}

///|
/// 要素サイズを取得 (バイト単位)
fn element_size(t : TsType) -> Int {
  match t {
    Number => 8 // f64 = 8 bytes
    Int => 4 // i32 = 4 bytes
    Boolean => 4 // i32 = 4 bytes
    String_ => 4 // ポインタ = 4 bytes
    Array(_) => 4 // ポインタ = 4 bytes
    Named(_) => 4 // 構造体ポインタ = 4 bytes
    Struct(_, _) => 4 // 構造体ポインタ = 4 bytes
    _ => 8
  }
}

///|
/// 構造体のサイズを計算
fn struct_size(fields : Array[(String, TsType)]) -> Int {
  let mut size = 0
  for i = 0; i < fields.length(); i = i + 1 {
    let (_, field_type) = fields[i]
    size += element_size(field_type)
  }
  size
}

///|
/// 構造体フィールドのオフセットを計算
fn field_offset(fields : Array[(String, TsType)], field_name : String) -> Int? {
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
fn field_type(fields : Array[(String, TsType)], field_name : String) -> TsType? {
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
  expr : TsExpr,
  expected_type : TsType,
) -> Unit raise CodeGenError {
  match expr {
    NumberLit(n) =>
      if is_f64_type(expected_type) {
        ctx.emit(F64Const(n))
      } else {
        // i32 にキャスト
        ctx.emit(I32Const(n.to_int().reinterpret_as_uint()))
      }
    IntLit(i) =>
      if is_f64_type(expected_type) {
        ctx.emit(F64Const(i.to_double()))
      } else {
        ctx.emit(I32Const(i.reinterpret_as_uint()))
      }
    BoolLit(b) => ctx.emit(I32Const(if b { 1U } else { 0U }))
    StringLit(s) => {
      // 文字列プールに追加してオフセットを取得 (スナップショット方式)
      let offset = ctx.string_pool.add(s)
      // データセクションへのポインタを返す
      ctx.emit(I32Const(offset.reinterpret_as_uint()))
    }
    Var(name) =>
      match ctx.get_local(name) {
        Some(local) => ctx.emit(LocalGet(local.index))
        None => raise CodeGenError("Undefined variable: \{name}")
      }
    BinOp(op, left, right) => compile_binop(ctx, op, left, right, expected_type)
    UnaryOp(op, operand) => compile_unaryop(ctx, op, operand, expected_type)
    Call(name, args) => compile_call(ctx, name, args, expected_type)
    Cond(cond, then_expr, else_expr) => {
      // 条件をコンパイル
      compile_expr(ctx, cond, Boolean)
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
    ArrayLit(elements) => compile_array_lit(ctx, elements, expected_type)
    IndexAccess(arr, index) =>
      compile_index_access(ctx, arr, index, expected_type)
    PropAccess(obj, prop) => compile_prop_access(ctx, obj, prop, expected_type)
    New(type_name, args) =>
      compile_new_expr(ctx, type_name, args, expected_type)
    MethodCall(receiver, method, args) =>
      compile_method_call(ctx, receiver, method, args, expected_type)
    // 以下は静的Wasmコンパイラでは未サポート（インタプリタのみ）
    NullLit => ctx.emit(I32Const(0U)) // null = 0
    ObjectLit(_) =>
      raise CodeGenError(
        "ObjectLit is not supported in Wasm compiler (use interpreter)",
      )
    AssignExpr(_, _) =>
      raise CodeGenError(
        "AssignExpr is not supported in Wasm compiler (use interpreter)",
      )
    ArrowFunc(_, _) =>
      raise CodeGenError(
        "ArrowFunc is not supported in Wasm compiler (use interpreter)",
      )
    FuncExpr(_) =>
      raise CodeGenError(
        "FuncExpr is not supported in Wasm compiler (use interpreter)",
      )
  }
}

///|
/// 配列リテラルをコンパイル
fn compile_array_lit(
  ctx : CodeGenCtx,
  elements : Array[TsExpr],
  expected_type : TsType,
) -> Unit raise CodeGenError {
  let elem_type = match expected_type {
    Array(t) => t
    _ => Number
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
  arr : TsExpr,
  index : TsExpr,
  expected_type : TsType,
) -> Unit raise CodeGenError {
  let arr_type = infer_type(ctx, arr)
  let elem_type = match arr_type {
    Array(t) => t
    _ => expected_type
  }
  let elem_sz = element_size(elem_type)

  // アドレス計算: arr + 4 + index * elem_size
  compile_expr(ctx, arr, arr_type) // 配列のベースアドレス
  ctx.emit(I32Const(4U)) // 長さフィールドをスキップ
  ctx.emit(I32Add)
  compile_expr(ctx, index, Int)
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
  obj : TsExpr,
  prop : String,
  _expected_type : TsType,
) -> Unit raise CodeGenError {
  let obj_type = infer_type(ctx, obj)

  // 配列/文字列の length プロパティ
  match obj_type {
    Array(_) =>
      if prop == "length" {
        compile_expr(ctx, obj, obj_type)
        ctx.emit(I32Load(2U, 0U, 0U)) // 最初の4バイト = 長さ
        return
      }
    String_ =>
      if prop == "length" {
        compile_expr(ctx, obj, obj_type)
        ctx.emit(I32Load(2U, 0U, 0U)) // 最初の4バイト = 長さ
        return
      }
    Named(type_name) =>
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
                Some(Number) => ctx.emit(F64Load(3U, 0U, 0U))
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
  args : Array[TsExpr],
  _expected_type : TsType,
) -> Unit raise CodeGenError {
  if type_name == "Array" {
    // new Array<T>(size)
    let elem_type = match _expected_type {
      Array(t) => t
      _ => Number
    }
    let elem_sz = element_size(elem_type)
    if args.length() < 1 {
      raise CodeGenError("Array constructor requires size argument")
    }

    // サイズを取得
    compile_expr(ctx, args[0], Int)
    let size_local = ctx.add_local("__array_size__", Int)
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
  receiver : TsExpr,
  method : String,
  args : Array[TsExpr],
  _expected_type : TsType,
) -> Unit raise CodeGenError {
  let recv_type = infer_type(ctx, receiver)
  match recv_type {
    String_ => compile_string_method(ctx, receiver, method, args)
    Array(_) => compile_array_method(ctx, receiver, method, args, recv_type)
    _ => raise CodeGenError("Cannot call method on type: \{recv_type}")
  }
}

///|
/// 文字列メソッドをコンパイル
fn compile_string_method(
  ctx : CodeGenCtx,
  receiver : TsExpr,
  method : String,
  args : Array[TsExpr],
) -> Unit raise CodeGenError {
  match method {
    "charCodeAt" => {
      // str.charCodeAt(index) → str[4 + index] (1バイト読み込み)
      if args.length() < 1 {
        raise CodeGenError("charCodeAt requires 1 argument")
      }
      compile_expr(ctx, receiver, String_) // 文字列のアドレス
      ctx.emit(I32Const(4U)) // 長さフィールドをスキップ
      ctx.emit(I32Add)
      compile_expr(ctx, args[0], Int) // インデックス
      ctx.emit(I32Add)
      ctx.emit(I32Load8U(0U, 0U, 0U)) // 1バイト読み込み (符号なし)
    }
    "charAt" => {
      // str.charAt(index) → 新しい1文字の文字列を作成
      if args.length() < 1 {
        raise CodeGenError("charAt requires 1 argument")
      }
      // 文字コードを取得
      compile_expr(ctx, receiver, String_)
      ctx.emit(I32Const(4U))
      ctx.emit(I32Add)
      compile_expr(ctx, args[0], Int)
      ctx.emit(I32Add)
      ctx.emit(I32Load8U(0U, 0U, 0U))
      let char_local = ctx.add_local("__char__", Int)
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
      compile_expr(ctx, args[0], Int)
      let start_local = ctx.add_local("__substr_start__", Int)
      ctx.emit(LocalSet(start_local))
      compile_expr(ctx, args[1], Int)
      let end_local = ctx.add_local("__substr_end__", Int)
      ctx.emit(LocalSet(end_local))

      // 長さを計算
      ctx.emit(LocalGet(end_local))
      ctx.emit(LocalGet(start_local))
      ctx.emit(I32Sub)
      let len_local = ctx.add_local("__substr_len__", Int)
      ctx.emit(LocalSet(len_local))

      // 新しい文字列のアドレス
      ctx.emit(GlobalGet(0U))

      // 長さを格納
      ctx.emit(GlobalGet(0U))
      ctx.emit(LocalGet(len_local))
      ctx.emit(I32Store(2U, 0U, 0U))

      // 元の文字列のアドレスを取得
      compile_expr(ctx, receiver, String_)
      let src_local = ctx.add_local("__substr_src__", Int)
      ctx.emit(LocalSet(src_local))

      // コピーループ (memory.copy がない場合の簡易実装)
      let i_local = ctx.add_local("__substr_i__", Int)
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
    _ => raise CodeGenError("Unknown string method: \{method}")
  }
}

///|
/// 文字列連結をコンパイル
fn compile_string_concat(
  ctx : CodeGenCtx,
  left : TsExpr,
  right : TsExpr,
) -> Unit raise CodeGenError {
  // 左の文字列
  compile_expr(ctx, left, String_)
  let left_local = ctx.add_local("__concat_left__", Int)
  ctx.emit(LocalSet(left_local))

  // 右の文字列
  compile_expr(ctx, right, String_)
  let right_local = ctx.add_local("__concat_right__", Int)
  ctx.emit(LocalSet(right_local))

  // 左の長さ
  ctx.emit(LocalGet(left_local))
  ctx.emit(I32Load(2U, 0U, 0U))
  let left_len = ctx.add_local("__concat_left_len__", Int)
  ctx.emit(LocalSet(left_len))

  // 右の長さ
  ctx.emit(LocalGet(right_local))
  ctx.emit(I32Load(2U, 0U, 0U))
  let right_len = ctx.add_local("__concat_right_len__", Int)
  ctx.emit(LocalSet(right_len))

  // 合計長さ
  ctx.emit(LocalGet(left_len))
  ctx.emit(LocalGet(right_len))
  ctx.emit(I32Add)
  let total_len = ctx.add_local("__concat_total_len__", Int)
  ctx.emit(LocalSet(total_len))

  // 新しい文字列のアドレス
  ctx.emit(GlobalGet(0U))

  // 長さを格納
  ctx.emit(GlobalGet(0U))
  ctx.emit(LocalGet(total_len))
  ctx.emit(I32Store(2U, 0U, 0U))

  // 左側をコピー
  let i_local = ctx.add_local("__concat_i__", Int)
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
  receiver : TsExpr,
  method : String,
  args : Array[TsExpr],
  arr_type : TsType,
) -> Unit raise CodeGenError {
  let elem_type = match arr_type {
    Array(t) => t
    _ => Number
  }
  match method {
    "push" => {
      // arr.push(value) → 要素を追加して新しい長さを返す
      if args.length() < 1 {
        raise CodeGenError("push requires 1 argument")
      }
      // 配列のアドレスを取得
      compile_expr(ctx, receiver, arr_type)
      let arr_local = ctx.add_local("__push_arr__", Int)
      ctx.emit(LocalSet(arr_local))

      // 現在の長さを取得
      ctx.emit(LocalGet(arr_local))
      ctx.emit(I32Load(2U, 0U, 0U))
      let len_local = ctx.add_local("__push_len__", Int)
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
    _ => raise CodeGenError("Unknown array method: \{method}")
  }
}

///|
/// プロパティへの代入をコンパイル
fn compile_prop_assign(
  ctx : CodeGenCtx,
  obj : TsExpr,
  prop : String,
  value : TsExpr,
) -> Unit raise CodeGenError {
  let obj_type = infer_type(ctx, obj)
  match obj_type {
    Named(type_name) =>
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
  arr : TsExpr,
  index : TsExpr,
  value : TsExpr,
) -> Unit raise CodeGenError {
  let arr_type = infer_type(ctx, arr)
  let elem_type = match arr_type {
    Array(t) => t
    _ => Number
  }
  let elem_sz = element_size(elem_type)

  // アドレス計算: arr + 4 + index * elem_size
  compile_expr(ctx, arr, arr_type) // 配列のベースアドレス
  ctx.emit(I32Const(4U)) // 長さフィールドをスキップ
  ctx.emit(I32Add)
  compile_expr(ctx, index, Int)
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
  op : TsBinOp,
  left : TsExpr,
  right : TsExpr,
  expected_type : TsType,
) -> Unit raise CodeGenError {
  // 文字列連結のチェック
  let left_type = infer_type(ctx, left)
  let right_type = infer_type(ctx, right)
  if op == Add && (left_type == String_ || right_type == String_) {
    // 文字列連結
    compile_string_concat(ctx, left, right)
    return
  }

  // 比較演算子のオペランドはオペランドの型を推論、論理演算子は Boolean
  let operand_type = match op {
    Add | Sub | Mul | Div | Mod => expected_type
    BinLt | BinLe | BinGt | BinGe | BinEq | BinNe | AbstractEq | AbstractNe =>
      // 両方 Int なら Int、それ以外は Number
      if left_type == Int && right_type == Int {
        Int
      } else {
        Number
      }
    And | Or => Boolean
  }
  compile_expr(ctx, left, operand_type)
  compile_expr(ctx, right, operand_type)
  if is_f64_type(operand_type) {
    // f64 演算
    match op {
      Add => ctx.emit(F64Add)
      Sub => ctx.emit(F64Sub)
      Mul => ctx.emit(F64Mul)
      Div => ctx.emit(F64Div)
      Mod => raise CodeGenError("f64 mod not supported")
      BinLt => ctx.emit(F64Lt)
      BinLe => ctx.emit(F64Le)
      BinGt => ctx.emit(F64Gt)
      BinGe => ctx.emit(F64Ge)
      BinEq | AbstractEq => ctx.emit(F64Eq)
      BinNe | AbstractNe => ctx.emit(F64Ne)
      And | Or => raise CodeGenError("Logical op on f64")
    }
  } else {
    // i32 演算
    match op {
      Add => ctx.emit(I32Add)
      Sub => ctx.emit(I32Sub)
      Mul => ctx.emit(I32Mul)
      Div => ctx.emit(I32DivS)
      Mod => ctx.emit(I32RemS)
      BinLt => ctx.emit(I32LtS)
      BinLe => ctx.emit(I32LeS)
      BinGt => ctx.emit(I32GtS)
      BinGe => ctx.emit(I32GeS)
      BinEq | AbstractEq => ctx.emit(I32Eq)
      BinNe | AbstractNe => ctx.emit(I32Ne)
      And => ctx.emit(I32And)
      Or => ctx.emit(I32Or)
    }
  }
}

///|
/// 単項演算をコンパイル
fn compile_unaryop(
  ctx : CodeGenCtx,
  op : TsUnaryOp,
  operand : TsExpr,
  expected_type : TsType,
) -> Unit raise CodeGenError {
  match op {
    Neg =>
      if is_f64_type(expected_type) {
        compile_expr(ctx, operand, expected_type)
        ctx.emit(F64Neg)
      } else {
        // i32: 0 - x
        ctx.emit(I32Const(0U))
        compile_expr(ctx, operand, expected_type)
        ctx.emit(I32Sub)
      }
    Not => {
      compile_expr(ctx, operand, Boolean)
      ctx.emit(I32Eqz)
    }
    PreInc =>
      // ++x: x = x + 1, return new value
      match operand {
        Var(name) =>
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
    PreDec =>
      // --x: x = x - 1, return new value
      match operand {
        Var(name) =>
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
    PostInc =>
      // x++: return old value, then x = x + 1
      match operand {
        Var(name) =>
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
    PostDec =>
      // x--: return old value, then x = x - 1
      match operand {
        Var(name) =>
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
    Plus =>
      // 単項プラス: 数値への変換（そのまま出力）
      compile_expr(ctx, operand, expected_type)
    Typeof =>
      // typeof は静的Wasmコンパイラでは未サポート
      raise CodeGenError(
        "typeof is not supported in Wasm compiler (use interpreter)",
      )
  }
}

///|
/// 関数呼び出しをコンパイル
fn compile_call(
  ctx : CodeGenCtx,
  name : String,
  args : Array[TsExpr],
  expected_type : TsType,
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
  stmt : TsStmt,
  return_type : TsType,
) -> Unit raise CodeGenError {
  match stmt {
    Let(name, type_, init) => {
      // Any 型はリテラルから推論
      let resolved_type = resolve_any(type_, init)
      let idx = ctx.add_local(name, resolved_type)
      compile_expr(ctx, init, resolved_type)
      ctx.emit(LocalSet(idx))
    }
    Const(name, type_, init) => {
      // const も let と同じ扱い、Any 型はリテラルから推論
      let resolved_type = resolve_any(type_, init)
      let idx = ctx.add_local(name, resolved_type)
      compile_expr(ctx, init, resolved_type)
      ctx.emit(LocalSet(idx))
    }
    Assign(name, expr) =>
      match ctx.get_local(name) {
        Some(lvar) => {
          compile_expr(ctx, expr, lvar.type_)
          ctx.emit(LocalSet(lvar.index))
        }
        None => raise CodeGenError("Undefined variable: \{name}")
      }
    CompoundAssign(name, op, expr) =>
      match ctx.get_local(name) {
        Some(lvar) => {
          // x op= expr → x = x op expr
          ctx.emit(LocalGet(lvar.index))
          compile_expr(ctx, expr, lvar.type_)
          if is_f64_type(lvar.type_) {
            match op {
              AddAssign => ctx.emit(F64Add)
              SubAssign => ctx.emit(F64Sub)
              MulAssign => ctx.emit(F64Mul)
              DivAssign => ctx.emit(F64Div)
            }
          } else {
            match op {
              AddAssign => ctx.emit(I32Add)
              SubAssign => ctx.emit(I32Sub)
              MulAssign => ctx.emit(I32Mul)
              DivAssign => ctx.emit(I32DivS)
            }
          }
          ctx.emit(LocalSet(lvar.index))
        }
        None => raise CodeGenError("Undefined variable: \{name}")
      }
    IndexAssign(arr, index, value) =>
      compile_index_assign(ctx, arr, index, value)
    PropAssign(obj, prop, value) => compile_prop_assign(ctx, obj, prop, value)
    Expr(expr) => {
      compile_expr(ctx, expr, return_type)
      ctx.emit(Drop)
    }
    Return(Some(expr)) => {
      compile_expr(ctx, expr, return_type)
      ctx.emit(Return)
    }
    Return(None) => ctx.emit(Return)
    If(cond, then_block, else_block) =>
      compile_if(ctx, cond, then_block, else_block, return_type)
    While(cond, body) => compile_while(ctx, cond, body, return_type)
    For(init, cond, update, body) =>
      compile_for(ctx, init, cond, update, body, return_type)
    ForOf(var_name, var_type, iterable, body) =>
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
  cond : TsExpr,
  then_block : TsBlock,
  else_block : TsBlock?,
  return_type : TsType,
) -> Unit raise CodeGenError {
  compile_expr(ctx, cond, Boolean)
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
  cond : TsExpr,
  body : TsBlock,
  return_type : TsType,
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
  compile_expr(cond_ctx, cond, Boolean)
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
  init : TsStmt?,
  cond : TsExpr?,
  update : TsStmt?,
  body : TsBlock,
  return_type : TsType,
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
      compile_expr(cond_ctx, c, Boolean)
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
  _var_type : TsType,
  iterable : TsExpr,
  body : TsBlock,
  return_type : TsType,
) -> Unit raise CodeGenError {
  // 配列を取得してローカル変数に保存
  let arr_type = infer_type(ctx, iterable)
  let elem_type = match arr_type {
    Array(t) => t
    _ => Number
  }

  // 配列のアドレスを保存
  let arr_local = ctx.add_local("__for_of_arr__", arr_type)
  compile_expr(ctx, iterable, arr_type)
  ctx.emit(LocalSet(arr_local))

  // 配列の長さを取得して保存
  let len_local = ctx.add_local("__for_of_len__", Int)
  ctx.emit(LocalGet(arr_local))
  ctx.emit(I32Load(2U, 0U, 0U))
  ctx.emit(LocalSet(len_local))

  // インデックス変数
  let idx_local = ctx.add_local("__for_of_idx__", Int)
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
  block : TsBlock,
  return_type : TsType,
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
  func : TsFunc,
  func_map : Map[String, UInt],
  interfaces : Map[String, Array[(String, TsType)]],
  import_types : Map[String, (Array[TsType], TsType)],
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
    Void => []
    t => [ts_type_to_valtype(t)]
  }
  let func_type : @core.TypeDef = Func({ params, results })

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
pub fn compile_module(module_ : TsModule) -> @core.Module raise CodeGenError {
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
  let interface_map : Map[String, Array[(String, TsType)]] = {}
  for iface in module_.interfaces {
    interface_map[iface.name] = iface.fields
  }

  // インポート関数の型情報マップを作成
  let import_types : Map[String, (Array[TsType], TsType)] = {}
  for imp in module_.imports {
    let param_types : Array[TsType] = []
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
      Void => []
      t => [ts_type_to_valtype(t)]
    }
    types.push(Func({ params, results }))
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
    exports.push({ name: name_bytes, desc: Func(func_idx) })
  }

  // Wasm インポートを生成
  let imports : Array[@core.Import] = []
  for i, imp in module_.imports {
    imports.push({
      module_: string_to_bytes(imp.module_),
      name: string_to_bytes(imp.name),
      desc: Func(i.reinterpret_as_uint()), // 型インデックス
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
  let parser = Parser::from_source(source)
  let ts_module = parser.parse_module() catch {
    ParseError(msg) => raise CompileError("Parse error: \{msg}")
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
  let parser = Parser::from_source(source)
  let ts_module = parser.parse_module() catch {
    ParseError(msg) => raise CompileError("Parse error: \{msg}")
  }
  compile_module(ts_module) catch {
    CodeGenError(msg) => raise CompileError("CodeGen error: \{msg}")
  }
}
