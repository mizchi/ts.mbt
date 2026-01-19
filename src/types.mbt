// TypeScript サブセットの型システム

///|
/// 型
pub enum TsType {
  // プリミティブ
  Number // f64 にマップ
  Int // i32 にマップ (最適化用)
  Boolean // i32 (0/1) にマップ
  String_ // 文字列 (メモリ上のポインタ)
  Void
  // Any (JavaScript互換 - 型推論で解決)
  Any
  // 複合型 (Phase 2)
  Array(TsType)
  Struct(String, Array[(String, TsType)]) // name, fields
  Func(Array[TsType], TsType) // params, return
  // 型参照
  Named(String)
} derive(Eq, Show)

///|
/// 型付き式
pub enum TsExpr {
  // リテラル
  NumberLit(Double)
  IntLit(Int)
  BoolLit(Bool)
  StringLit(String)
  NullLit // null リテラル

  // 変数
  Var(String)

  // 二項演算
  BinOp(TsBinOp, TsExpr, TsExpr)

  // 単項演算
  UnaryOp(TsUnaryOp, TsExpr)

  // 関数呼び出し
  Call(String, Array[TsExpr])

  // 条件式 (三項演算子)
  Cond(TsExpr, TsExpr, TsExpr)

  // 配列リテラル
  ArrayLit(Array[TsExpr])

  // オブジェクトリテラル
  ObjectLit(Array[(String, TsExpr)]) // [(key, value)]

  // 配列アクセス
  IndexAccess(TsExpr, TsExpr)

  // プロパティアクセス
  PropAccess(TsExpr, String)

  // new 式 (配列等)
  New(String, Array[TsExpr])

  // メソッド呼び出し (receiver.method(args))
  MethodCall(TsExpr, String, Array[TsExpr])

  // 代入式 (式として)
  AssignExpr(String, TsExpr)

  // アロー関数
  ArrowFunc(Array[TsParam], TsArrowBody)

  // 関数式 (function() {})
  FuncExpr(TsFunc)
} derive(Show)

///|
/// アロー関数の本体
pub enum TsArrowBody {
  ArrowExpr(TsExpr) // () => expr
  ArrowBlock(TsBlock) // () => { ... }
} derive(Show)

///|
/// 二項演算子
pub enum TsBinOp {
  // 算術
  Add // +
  Sub // -
  Mul // *
  Div // /
  Mod // %
  // 比較 (厳密)
  BinEq // ===
  BinNe // !==
  // 比較 (抽象 - 型変換あり)
  AbstractEq // ==
  AbstractNe // !=
  // 比較 (順序)
  BinLt // <
  BinLe // <=
  BinGt // >
  BinGe // >=
  // 論理
  And // &&
  Or // ||
} derive(Eq, Show)

///|
/// 単項演算子
pub enum TsUnaryOp {
  Neg // -
  Not // !
  Plus // + (単項プラス)
  Typeof // typeof
  PreInc // ++x
  PreDec // --x
  PostInc // x++
  PostDec // x--
} derive(Eq, Show)

///|
/// 複合代入演算子
pub enum TsCompoundOp {
  AddAssign // +=
  SubAssign // -=
  MulAssign // *=
  DivAssign // /=
} derive(Eq, Show)

///|
/// 文
pub enum TsStmt {
  // 変数宣言
  Let(String, TsType, TsExpr)
  Const(String, TsType, TsExpr)

  // 代入
  Assign(String, TsExpr)

  // 複合代入: x += 1
  CompoundAssign(String, TsCompoundOp, TsExpr)

  // 配列要素への代入
  IndexAssign(TsExpr, TsExpr, TsExpr) // array, index, value

  // プロパティへの代入
  PropAssign(TsExpr, String, TsExpr) // object, property, value

  // 式文
  Expr(TsExpr)

  // return
  Return(TsExpr?)

  // 制御フロー
  If(TsExpr, TsBlock, TsBlock?)
  While(TsExpr, TsBlock)
  For(TsStmt?, TsExpr?, TsStmt?, TsBlock) // init, cond, update, body
  ForOf(String, TsType, TsExpr, TsBlock) // varName, varType, iterable, body

  // break/continue
  Break
  Continue
} derive(Show)

///|
/// ブロック (文の配列)
pub struct TsBlock {
  stmts : Array[TsStmt]
} derive(Show)

///|
/// 関数パラメータ
pub struct TsParam {
  name : String
  type_ : TsType
  default : TsExpr? // デフォルト値 (省略可能)
} derive(Show)

///|
/// 関数定義
pub struct TsFunc {
  name : String
  params : Array[TsParam]
  return_type : TsType
  body : TsBlock
} derive(Show)

///|
/// インターフェース (構造体型)
pub struct TsInterface {
  name : String
  fields : Array[(String, TsType)] // (fieldName, type)
} derive(Show)

///|
/// 外部関数インポート宣言
pub struct TsImport {
  name : String // 関数名
  module_ : String // インポート元モジュール (デフォルト: "env")
  params : Array[(String, TsType)] // パラメータ (name, type)
  return_type : TsType // 戻り値型
} derive(Show)

///|
/// モジュール (トップレベル)
pub struct TsModule {
  funcs : Array[TsFunc]
  interfaces : Array[TsInterface]
  imports : Array[TsImport] // 外部インポート
} derive(Show)

// ============================================
// Typed AST (型解決済み)
// ============================================

///|
/// 型付き式 (型情報付き)
pub struct TypedExpr {
  expr : TsExpr
  type_ : TsType
} derive(Show)

///|
/// 型付き文
pub struct TypedStmt {
  stmt : TsStmt
  // 追加のメタ情報があれば
} derive(Show)

///|
/// 型付き関数
pub struct TypedFunc {
  func : TsFunc
  // ローカル変数の型マップ
  locals : Array[(String, TsType)]
} derive(Show)

///|
/// 型付きモジュール
pub struct TypedModule {
  funcs : Array[TypedFunc]
} derive(Show)
