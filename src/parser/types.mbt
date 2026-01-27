// TypeScript type

///|
// / type
pub(all) enum TsType {

  Number // f64
  Int // i32 ()
  Boolean // i32 (0/1)
  String_ // string ()
  Void
  // Any (JavaScript - type inferenceresolve)
  Any
  // compoundtype (Phase 2)
  Array(TsType)
  Struct(String, Array[(String, TsType)]) // name, fields
  Func(Array[TsType], TsType) // params, return
  // typereference
  Named(String)
} derive(Eq, Show)

///|
// / typedexpression
pub(all) enum TsExpr {
  // literal
  NumberLit(Double)
  IntLit(Int)
  BoolLit(Bool)
  StringLit(String)
  NullLit // null literal

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

  // objectliteral
  ObjectLit(Array[(String, TsExpr)]) // [(key, value)]

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

  // compoundassignmentexpression (expression)
  CompoundAssignExpr(TsExpr, TsCompoundOp, TsExpr)

  // propertyassignmentexpression
  PropAssignExpr(TsExpr, String, TsExpr)

  // assignmentexpression
  IndexAssignExpr(TsExpr, TsExpr, TsExpr)

  // operator
  Seq(TsExpr, TsExpr)

  // function
  ArrowFunc(Array[TsParam], TsArrowBody)

  // functionexpression (function() {})
  FuncExpr(TsFunc)

  // yield expression (generator)
  Yield(TsExpr?)
} derive(Show)

///|
// / function
pub(all) enum TsArrowBody {
  ArrowExpr(TsExpr) // () => expr
  ArrowBlock(TsBlock) // () => { ... }
} derive(Show)

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
} derive(Eq, Show)

///|
// / unaryoperator
pub(all) enum TsUnaryOp {
  Neg // -
  Not // !
  Plus // + (unary)
  Typeof // typeof
  Void // void
  Delete // delete
  PreInc // ++x
  PreDec // --x
  PostInc // x++
  PostDec // x--
} derive(Eq, Show)

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
} derive(Eq, Show)

///|
// / statement
pub(all) enum TsStmt {
  // variable
  Let(String, TsType, TsExpr)
  Const(String, TsType, TsExpr)

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
  Try(TsBlock, String?, TsBlock?, TsBlock?)


  If(TsExpr, TsBlock, TsBlock?)
  While(TsExpr, TsBlock)
  For(TsStmt?, TsExpr?, TsStmt?, TsBlock) // init, cond, update, body
  ForOf(String, TsType, TsExpr, TsBlock) // varName, varType, iterable, body
  Block(TsBlock)

  // break/continue
  Break
  Continue
} derive(Show)

///|
// / block (statementarray)
pub(all) struct TsBlock {
  stmts : Array[TsStmt]
} derive(Show)

///|
// / functionparameter
pub(all) struct TsParam {
  name : String
  binding : TsBinding?
  is_rest : Bool
  type_ : TsType
  default : TsExpr? // ()
} derive(Show)

///|
// /
pub(all) enum TsBinding {
  Ident(String)
  Array(TsArrayBinding)
  Object(TsObjectBinding)
} derive(Show)

///|
pub(all) struct TsBindingElem {
  binding : TsBinding
  default : TsExpr?
} derive(Show)

///|
pub(all) struct TsArrayBinding {
  items : Array[TsBindingElem?]
  rest : TsBinding?
} derive(Show)

///|
pub(all) struct TsObjectBindingProp {
  key : String
  binding : TsBinding
  default : TsExpr?
} derive(Show)

///|
pub(all) struct TsObjectBinding {
  props : Array[TsObjectBindingProp]
  rest : String?
} derive(Show)

///|
// / functiondefine
pub(all) struct TsFunc {
  name : String
  params : Array[TsParam]
  return_type : TsType
  body : TsBlock
  is_generator : Bool
} derive(Show)

///|
// / interface (structtype)
pub(all) struct TsInterface {
  name : String
  fields : Array[(String, TsType)] // (fieldName, type)
} derive(Show)

///|
// / externalfunctionimport
pub(all) struct TsImport {
  name : String // function
  module_ : String // import (: "env")
  params : Array[(String, TsType)] // parameter (name, type)
  return_type : TsType // return valuetype
} derive(Show)

///|
// / ()
pub(all) struct TsModule {
  funcs : Array[TsFunc]
  interfaces : Array[TsInterface]
  imports : Array[TsImport] // externalimport
} derive(Show)

// ============================================
// Typed AST (type-resolved)
// ============================================

///|
// / typedexpression (type)
pub(all) struct TypedExpr {
  expr : TsExpr
  type_ : TsType
} derive(Show)

///|
// / typedstatement
pub(all) struct TypedStmt {
  stmt : TsStmt
  // add
} derive(Show)

///|
// / typedfunction
pub(all) struct TypedFunc {
  func : TsFunc
  // variabletype
  locals : Array[(String, TsType)]
} derive(Show)

///|
// / typed
pub(all) struct TypedModule {
  funcs : Array[TypedFunc]
} derive(Show)
