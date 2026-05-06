// TypeScript type

///|
// / type
pub(all) enum TsType {
  // Primitive types
  Number // f64
  Int // i32 ()
  Boolean // i32 (0/1)
  String_ // string ()
  Void
  BigInt // bigint
  Symbol // symbol
  // Special types
  Any // unknown/any
  Never // bottom type (no value)
  Null // null
  Undefined // undefined
  // Literal types
  Literal(String) // string literal type and object property key
  NumberLiteral(String)
  BigIntLiteral(String)
  BooleanLiteral(Bool)
  // Compound types
  Array(TsType)
  Tuple(Array[TsType]) // [string, number]
  Object(Array[(TsType, TsType)]) // { key: value } - key is Literal for property names
  Struct(String, Array[(String, TsType)]) // name, fields (for codegen)
  Func(Array[TsType], TsType) // params, return
  // Type operators
  Union(Array[TsType]) // A | B
  Intersection(Array[TsType]) // A & B
  Conditional(TsType, TsType, TsType, TsType) // A extends B ? X : Y
  // Type reference
  Named(String)
  Applied(String, Array[TsType])
  // Indexed access: T[K]. The parser previously dropped this to Any; the
  // variant lets later passes resolve it when T is a concrete interface or
  // object literal and K is a string literal.
  IndexedAccess(TsType, TsType)
  // Template literal type: `prefix${T1}mid${T2}suffix`. Stored as
  // (parts, type_args) where parts.length() == type_args.length() + 1, so
  // the rendered string is parts[0] + type_args[0] + parts[1] + ... +
  // parts[N]. Used by patterns like `bg${ForegroundColorName}`.
  TemplateLiteralType(Array[String], Array[TsType])
} derive(Eq, Debug)

///|
// / typedexpression
pub(all) enum TsExpr {
  // literal
  NumberLit(Double)
  IntLit(Int)
  BigIntLit(String)
  BoolLit(Bool)
  StringLit(String)
  NullLit // null literal
  ArrayHole // array elision

  // variable
  Var(String)

  // binary
  BinOp(TsBinOp, TsExpr, TsExpr)

  // unary
  UnaryOp(TsUnaryOp, TsExpr)

  // function
  Call(String, Array[TsExpr])

  // function (expression)
  CallExpr(TsExpr, Array[TsExpr])

  // conditionexpression (operator)
  Cond(TsExpr, TsExpr, TsExpr)

  // arrayliteral
  ArrayLit(Array[TsExpr])
  Spread(TsExpr)

  // objectliteral
  ObjectLit(Array[(String, TsExpr)]) // [(key, value)]

  // computed property for object literal [keyExpr]: valueExpr
  ComputedProp(TsExpr, TsExpr) // (keyExpr, valueExpr)

  // array
  IndexAccess(TsExpr, TsExpr)

  // property
  PropAccess(TsExpr, String)

  // new expression (array)
  New(String, Array[TsExpr])

  // new expression (expression)
  NewExpr(TsExpr, Array[TsExpr])

  // method (receiver.method(args))
  MethodCall(TsExpr, String, Array[TsExpr])

  // assignmentexpression (expression)
  AssignExpr(String, TsExpr)

  // destructuring assignment expression
  AssignPattern(TsBinding, TsExpr)

  // compoundassignmentexpression (expression)
  CompoundAssignExpr(TsExpr, TsCompoundOp, TsExpr)

  // propertyassignmentexpression
  PropAssignExpr(TsExpr, String, TsExpr)

  // assignmentexpression
  IndexAssignExpr(TsExpr, TsExpr, TsExpr)

  // operator
  Seq(TsExpr, TsExpr)

  // function (is_async)
  ArrowFunc(Array[TsParam], TsArrowBody, Bool)

  // functionexpression (function() {})
  FuncExpr(TsFunc)

  // yield expression (generator)
  Yield(TsExpr?)
  YieldStar(TsExpr)

  // await expression (async)
  Await(TsExpr)

  // dynamic import expression: import(specifier)
  DynamicImport(TsExpr)

  // import.meta expression
  ImportMeta

  // tagged template literal: tag`string ${expr} string`
  // tag, strings (cooked), strings (raw), expressions
  TaggedTemplate(TsExpr, Array[String], Array[String], Array[TsExpr])

  // untagged template literal: `string ${expr} string`
  // strings (cooked), expressions
  TemplateLiteral(Array[String], Array[TsExpr])
} derive(Debug)

///|
// / function
pub(all) enum TsArrowBody {
  ArrowExpr(TsExpr) // () => expr
  ArrowBlock(TsBlock) // () => { ... }
} derive(Debug)

///|
// / binaryoperator
pub(all) enum TsBinOp {
  Add // +
  Sub // -
  Mul // *
  Div // /
  Mod // %
  Pow // **
  // /
  BitAnd // &
  BitOr // |
  BitXor // ^
  Shl // <<
  Shr // >>
  UShr // >>>
  // comparison ()
  BinEq // ===
  BinNe // !==
  // comparison ( - typeconversion)
  AbstractEq // ==
  AbstractNe // !=
  // comparison ()
  BinLt // <
  BinLe // <=
  BinGt // >
  BinGe // >=
  Instanceof // instanceof
  In // in
  And // &&
  Or // ||
  Coalesce // ??
} derive(Eq, Debug)

///|
// / unaryoperator
pub(all) enum TsUnaryOp {
  Neg // -
  Not // !
  BitwiseNot // ~
  Plus // + (unary)
  Typeof // typeof
  Void // void
  Delete // delete
  PreInc // ++x
  PreDec // --x
  PostInc // x++
  PostDec // x--
} derive(Eq, Debug)

///|
// / compoundassignmentoperator
pub(all) enum TsCompoundOp {
  AddAssign // +=
  SubAssign // -=
  MulAssign // *=
  DivAssign // /=
  ModAssign // %=
  BitAndAssign // &=
  BitOrAssign // |=
  BitXorAssign // ^=
  ShlAssign // <<=
  ShrAssign // >>=
  UShrAssign // >>>=
  PowAssign // **=
  // Logical assignment operators (ES2021)
  AndAssign // &&=
  OrAssign // ||=
  CoalesceAssign // ??=
} derive(Eq, Debug)

///|
// / for...of binding kind
pub(all) enum TsForOfKind {
  Var
  Let
  Const
  Assign
} derive(Eq, Debug)

///|
// / statement
pub(all) enum TsStmt {
  // variable
  Var(TsBinding, TsType, TsExpr) // var declaration (function-scoped)
  Let(TsBinding, TsType, TsExpr) // let declaration (block-scoped)
  Const(TsBinding, TsType, TsExpr) // const declaration (block-scoped)

  // assignment
  Assign(String, TsExpr)

  // compoundassignment: x += 1
  CompoundAssign(String, TsCompoundOp, TsExpr)

  // arrayelementassignment
  IndexAssign(TsExpr, TsExpr, TsExpr) // array, index, value

  // propertyassignment
  PropAssign(TsExpr, String, TsExpr) // object, property, value

  // expressionstatement
  Expr(TsExpr)
  Empty

  // return
  Return(TsExpr?)

  // throw
  Throw(TsExpr)

  // try/catch/finally
  Try(TsBlock, TsBinding?, TsBlock?, TsBlock?)
  If(TsExpr, TsBlock, TsBlock?)
  While(TsExpr, TsBlock)
  DoWhile(TsExpr, TsBlock) // do { body } while (cond)
  For(TsStmt?, TsExpr?, TsStmt?, TsBlock) // init, cond, update, body
  ForOf(TsForOfKind, TsBinding, TsType, TsExpr, TsBlock) // kind, binding, varType, iterable, body
  ForAwaitOf(TsForOfKind, TsBinding, TsType, TsExpr, TsBlock) // kind, binding, varType, async-iterable, body
  ForIn(TsForOfKind, TsBinding, TsType, TsExpr, TsBlock) // kind, binding, varType, iterable, body
  Switch(TsExpr, Array[TsSwitchCase])
  With(TsExpr, TsBlock)
  Debugger
  Label(String, TsStmt)
  Block(TsBlock)

  // break/continue
  Break(String?)
  Continue(String?)
} derive(Debug)

///|
// / block (statementarray)
pub(all) struct TsBlock {
  stmts : Array[TsStmt]
} derive(Debug)

///|
pub(all) struct TsSwitchCase {
  test_expr : TsExpr?
  body : TsBlock
} derive(Debug)

///|
// / functionparameter
pub(all) struct TsParam {
  name : String
  binding : TsBinding?
  is_rest : Bool
  type_ : TsType
  default : TsExpr? // ()
} derive(Debug)

///|
// /
pub(all) enum TsBinding {
  Ident(String)
  Array(TsArrayBinding)
  Object(TsObjectBinding)
  Target(TsExpr)
} derive(Debug)

///|
pub(all) struct TsBindingElem {
  binding : TsBinding
  default : TsExpr?
} derive(Debug)

///|
pub(all) struct TsArrayBinding {
  items : Array[TsBindingElem?]
  rest : TsBinding?
} derive(Debug)

///|
pub(all) struct TsObjectBindingProp {
  key : String
  key_expr : TsExpr?
  binding : TsBinding
  default : TsExpr?
} derive(Debug)

///|
pub(all) struct TsObjectBinding {
  props : Array[TsObjectBindingProp]
  rest : String?
} derive(Debug)

///|
// / functiondefine
pub(all) struct TsFunc {
  name : String
  params : Array[TsParam]
  return_type : TsType
  body : TsBlock
  is_generator : Bool
  is_async : Bool
} derive(Debug)

///|
// / interface (structtype)
pub(all) struct TsInterface {
  name : String
  type_params : Array[String]
  extends_names : Array[String]
  fields : Array[(String, TsType)] // (fieldName, type)
  readonly_fields : Array[String]
  // Index signatures `[k: K]: V` declared on this interface. Stored as
  // `(key_type, value_type)` pairs so bridge passes can lower them to
  // `op_get` / `op_set` accessors without conflating them with regular
  // named fields. Empty for interfaces with no index signature.
  index_signatures : Array[(TsType, TsType)]
} derive(Debug)

///|
// / type alias declaration
pub(all) struct TsTypeAlias {
  name : String
  type_params : Array[String]
  // `type T<P extends Bound = Default>` records `(P, Bound)` pairs here so
  // bridge passes can resolve `P` to its bound at use sites (e.g. for
  // `Record<P, ...>` key classification) without eagerly substituting the
  // bound into the alias body and erasing the generic shape.
  type_param_bounds : Array[(String, TsType)]
  type_ : TsType
} derive(Debug)

///|
// / externalfunctionimport
pub(all) struct TsImport {
  name : String // function
  module_ : String // import (: "env")
  params : Array[(String, TsType)] // parameter (name, type)
  return_type : TsType // return valuetype
} derive(Debug)

///|
// / ambient value declaration
pub(all) struct TsValueDecl {
  name : String
  type_ : TsType
} derive(Debug)

///|
// / class property declaration
pub(all) struct TsClassPropertyDecl {
  name : String
  type_ : TsType
  is_static : Bool
  is_readonly : Bool
} derive(Debug)

///|
// / class method declaration
pub(all) struct TsClassMethodDecl {
  name : String
  // Method-level generics: `get<Path extends string>(path: Path): ...` records
  // `(Path, string)` here so bridge passes can substitute the bound at the
  // method boundary without losing the generic shape on the public MoonBit
  // signature. Empty for non-generic methods.
  type_params : Array[String]
  type_param_bounds : Array[(String, TsType)]
  params : Array[(String, TsType)]
  return_type : TsType
  is_static : Bool
} derive(Debug)

///|
// / class declaration
pub(all) struct TsClassDecl {
  name : String
  type_params : Array[String]
  base_names : Array[String]
  constructor_params : Array[(String, TsType)]?
  properties : Array[TsClassPropertyDecl]
  methods : Array[TsClassMethodDecl]
  is_abstract : Bool
  is_constructible : Bool
} derive(Debug)

///|
pub(all) struct TsNamespaceDecl {
  name : String
  module_ : TsModule
} derive(Debug)

///|
// / enum member initializer literal
pub(all) enum TsEnumMemberValue {
  String(String)
  Number(String)
  BigInt(String)
  Bool(Bool)
} derive(Eq, Debug)

///|
// / enum member declaration
pub(all) struct TsEnumMember {
  name : String
  value : TsEnumMemberValue?
  is_computed : Bool
} derive(Eq, Debug)

///|
// / enum declaration
pub(all) struct TsEnumDecl {
  name : String
  members : Array[TsEnumMember]
  is_const : Bool
  is_declare : Bool
} derive(Eq, Debug)

///|
// / ()
pub(all) struct TsModule {
  funcs : Array[TsFunc]
  interfaces : Array[TsInterface]
  type_aliases : Array[TsTypeAlias]
  imports : Array[TsImport] // externalimport
  values : Array[TsValueDecl] // ambient value declarations
  classes : Array[TsClassDecl] // ambient class declarations
  namespaces : Array[TsNamespaceDecl]
  enums : Array[TsEnumDecl]
} derive(Debug)

///|
// / module import declaration
pub(all) struct TsImportDecl {
  module_spec : String
  default_binding : String?
  namespace_binding : String?
  named_bindings : Array[(String, String)] // imported, local
  side_effect_only : Bool
  type_only : Bool
} derive(Debug)

///|
// / module export specifier
pub(all) struct TsExportSpec {
  local_name : String
  export_name : String
} derive(Debug)

///|
// / module re-export kind
pub(all) enum TsReExportKind {
  Named(Array[(String, String)]) // imported, exported
  All
  Namespace(String) // export * as name from "mod"
} derive(Debug)

///|
// / module re-export specifier
pub(all) struct TsReExportSpec {
  module_spec : String
  kind : TsReExportKind
  type_only : Bool
} derive(Debug)

///|
// / module block with import/export metadata
pub(all) struct TsModuleBlock {
  block : TsBlock
  imports : Array[TsImportDecl]
  exports : Array[TsExportSpec]
  reexports : Array[TsReExportSpec]
  enums : Array[TsEnumDecl]
} derive(Debug)

// ============================================
// Typed AST (type-resolved)
// ============================================

///|
// / typedexpression (type)
pub(all) struct TypedExpr {
  expr : TsExpr
  type_ : TsType
} derive(Debug)

///|
// / typedstatement
pub(all) struct TypedStmt {
  stmt : TsStmt
  // add
} derive(Debug)

///|
// / typedfunction
pub(all) struct TypedFunc {
  func : TsFunc
  // variabletype
  locals : Array[(String, TsType)]
} derive(Debug)

///|
// / typed
pub(all) struct TypedModule {
  funcs : Array[TypedFunc]
} derive(Debug)
