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
  // `unique symbol`: TS treats each occurrence as a nominally distinct
  // type. The string carries a stable per-occurrence tag the parser
  // assigns so two `unique symbol` references that point to the same
  // declaration are interchangeable while distinct declarations are
  // not. Bridge emit still lowers the type to `Symbol` / `JSValue`.
  UniqueSymbol(String)
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
  // Variadic tuple element marker: `[A, ...B, C]` parses as
  // `Tuple([A, Rest(B), C])`. Only meaningful as a direct child of
  // `Tuple(...)`; outside of that position, `Rest(T)` behaves like
  // `Array(T)` (or like `T` itself when `T` is already an array / tuple).
  Rest(TsType)
  Object(Array[(TsType, TsType)]) // { key: value } - key is Literal for property names
  Struct(String, Array[(String, TsType)]) // name, fields (for codegen)
  Func(Array[TsType], TsType) // params, return
  // Constructor type: `new (...args) => T` or `abstract new (...) => T`.
  // Stored separately from `Func` so utility passes (`ConstructorParameters`,
  // `InstanceType`) can pattern-match on the call form, and so a bridge
  // emitter can decide between a class wrapper and a plain callable.
  // The last field is `is_abstract`.
  Constructor(Array[TsType], TsType, Bool)
  // Type operators
  Union(Array[TsType]) // A | B
  Intersection(Array[TsType]) // A & B
  Conditional(TsType, TsType, TsType, TsType) // A extends B ? X : Y
  // Type reference
  Named(String)
  Applied(String, Array[TsType])
  // Type query: `typeof Foo`, `typeof ns.Foo`, or
  // `typeof import("./mod").Foo`. The operand is stored as a stable textual
  // entity query so bridge passes can resolve class constructor-side utility
  // types without widening to `Any` in the parser.
  TypeOf(String)
  // Indexed access: T[K]. The parser previously dropped this to Any; the
  // variant lets later passes resolve it when T is a concrete interface or
  // object literal and K is a string literal.
  IndexedAccess(TsType, TsType)
  // Template literal type: `prefix${T1}mid${T2}suffix`. Stored as
  // (parts, type_args) where parts.length() == type_args.length() + 1, so
  // the rendered string is parts[0] + type_args[0] + parts[1] + ... +
  // parts[N]. Used by patterns like `bg${ForegroundColorName}`.
  TemplateLiteralType(Array[String], Array[TsType])
  // `keyof T`. Resolved to `Union[Literal(name), ...]` for struct/object
  // bases by `simplify_type`; preserved otherwise so later passes can
  // retry after substitution.
  Keyof(TsType)
  // Mapped type `{ [K in Source]: Value }` (with optional `?` on the
  // value position). `key_param` is the binder name (e.g. `K`); inside
  // `value` it appears as `Named(key_param)` and is substituted per key
  // when the source resolves to a union of literals. `optional` reflects
  // the literal `?` after `]`; the parser already handles `+?` / `-?`.
  MappedType(String, TsType, TsType, Bool)
  // Mapped type with key remapping
  // `{ [K in Source as Remap]: Value }`. Fields:
  //   - `key_param`: binder name (e.g. `K`);
  //   - `source`: original key union (e.g. `keyof T`);
  //   - `remap`: the `as` expression, normally a string-mapping intrinsic
  //     or a `Conditional` filter that references `Named(key_param)`;
  //   - `value`: value type that may also reference `Named(key_param)`;
  //   - `optional`: literal `?` after `]`.
  // Evaluated by `simplify_mapped_type`: per key `k` in `source`, the
  // remap is substituted-and-simplified; `Never` means the key is
  // filtered out, a `Literal(new_k)` rewrites the key, and a union of
  // literals emits one field per produced literal. Falls back to keeping
  // the variant for opaque sources / remaps so later substitution can
  // retry.
  MappedTypeRemap(String, TsType, TsType, TsType, Bool)
  // Type predicate: `paramName is T`. Used as a function return type to
  // mark a user-defined type guard. Outside of the return-type position
  // it behaves like `Boolean`.
  TypePredicate(String, TsType)
  // Assertion predicate: `asserts paramName` (truthy assertion) or
  // `asserts paramName is T` (typed assertion). The `TsType?` carries
  // the optional `is T` payload. Function runtime return is `void`;
  // the predicate is meaningful at call sites where the checker can
  // narrow the named binding for code that follows.
  AssertsPredicate(String, TsType?)
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

  // function (params, return_type, body, is_async). `return_type` is the
  // explicit `(x): T => …` annotation; `Any` when omitted. Carrying it on
  // the AST lets the checker spot `(x): x is Foo => …` predicates.
  ArrowFunc(Array[TsParam], TsType, TsArrowBody, Bool)

  // functionexpression (function() {})
  FuncExpr(TsFunc)

  // Native class expression `class [Name] extends Base { … }`.
  // Used by the parser when the source's class can't safely be
  // lowered to the `(function() { … })()` IIFE because it extends
  // another class — `super(…)` would be invalid outside a real
  // class body. The optional name is the class's declared name
  // (anonymous when "").
  NativeClassExpr(TsClassDecl, TsFunc?)

  // yield expression (generator)
  Yield(TsExpr?)
  YieldStar(TsExpr)

  // await expression (async)
  Await(TsExpr)

  // dynamic import expression: `import(specifier)` or
  // `import(specifier, options)`. The optional second argument is
  // typically `{ with: { type: "json" } }` — retained as a plain
  // expression so downstream code can read the attribute literal.
  DynamicImport(TsExpr, TsExpr?)

  // import.meta expression
  ImportMeta

  // tagged template literal: tag`string ${expr} string`
  // tag, strings (cooked), strings (raw), expressions
  TaggedTemplate(TsExpr, Array[String], Array[String], Array[TsExpr])

  // untagged template literal: `string ${expr} string`
  // strings (cooked), expressions
  TemplateLiteral(Array[String], Array[TsExpr])

  // `x as T` — type assertion cast. Result type is `T`.
  As(TsExpr, TsType)

  // `x satisfies T` — structural check, result type is left unchanged
  // (kept as `typeof x`). Used to verify shapes without narrowing.
  Satisfies(TsExpr, TsType)

  // `x!` — non-null assertion. Strips `null` / `undefined` from the
  // operand's type at use sites.
  NonNull(TsExpr)

  // `a?.b…` — wraps a chain expression that contains at least one
  // optional `?.` link. The wrapped expression has its conventional
  // shape (`PropAccess` / `MethodCall` / `IndexAccess` / `CallExpr`),
  // and at use sites the result type is widened with `undefined`.
  OptionalChain(TsExpr)

  // JSX element / fragment. Carries:
  //   - the tag name (`""` for fragments `<>…</>`; dotted for member
  //     refs like `<Foo.Bar/>`);
  //   - the attribute list as `(name, value?)` pairs — `value` is
  //     `None` for boolean attrs (`<Foo bar />`) and string-literal
  //     attrs are wrapped as `StringLit(...)`;
  //   - the children list — one entry per logical child. Each child
  //     is encoded as a `TsExpr`:
  //       * `StringLit(text)` for the text segments between tags;
  //       * the parsed `TsExpr` for `{expr}` blocks;
  //       * a nested `JsxElement(...)` for inline JSX.
  //
  // The checker recurses into every child expression and (when the
  // tag resolves to a known component or HTML element) validates the
  // attribute values against the receiving prop / element type.
  JsxElement(String, Array[(String, TsExpr?)], Array[TsExpr])
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
  // Native `class Name extends Base { … }` declaration. Used by the
  // parser when the source can't be safely lowered to the
  // `let X = (function() { … })()` IIFE — primarily because the
  // class extends another class (the IIFE's `super(…)` call is a
  // syntax error outside a real class body). The `TsClassDecl`
  // carries the structural shape (name, base, fields, methods);
  // `ctor_func` carries the constructor's full signature + body so
  // the emitter can preserve rest / default / destructuring
  // parameters that the checker-side declaration doesn't model.
  NativeClassStmt(TsClassDecl, TsFunc?)

  // break/continue
  Break(String?)
  Continue(String?)
} derive(Debug)

///|
// / block (statementarray)
//
// `stmt_positions` is positionally aligned with `stmts`: when the
// parser knows the source byte offset of a statement's first token,
// it records that here. Synthesized blocks (e.g. the desugar of a
// `class` declaration) leave the array empty — callers that don't
// need positions can ignore it, and the source-map generator falls
// back to "no mapping" when the array is shorter than `stmts`.
pub(all) struct TsBlock {
  stmts : Array[TsStmt]
  stmt_positions : Array[Int]
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
  // Generic type parameters declared on this function (e.g. `T`, `R` in
  // `function map<T, R>(...)`). Empty for non-generic functions.
  type_params : Array[String]
  // Parallel to `type_params`: `true` when the param was declared as
  // `<const T>` (TypeScript 5.0+). Empty arrays are also acceptable
  // — callers treat a missing flag as `false`. Generic inference uses
  // this to skip literal widening for the matching parameter.
  const_type_params : Array[Bool]
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
  // Type arguments supplied alongside each `extends_names[i]`, parsed
  // from `extends Foo<A, B>`. Length matches `extends_names`; entries
  // are empty arrays for non-generic bases. Used by the checker to
  // substitute generic parameters when walking the inheritance chain.
  extends_args : Array[Array[TsType]]
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
  // Generic type-parameter names declared on this `declare function`
  // (e.g. `T`, `R` in `declare function map<T, R>(...)`). Empty for non-
  // generic ambient declarations.
  type_params : Array[String]
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
  // `accessor` field (TC39 stage-3 auto-accessor): `class C { accessor
  // x: number = 0 }`. Functionally a property with synthesized
  // getter/setter, so the checker treats it like a normal property
  // but the flag is retained for downstream tooling.
  is_accessor : Bool
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
  // Method body, when the source supplied one. `None` for ambient class
  // declarations (`declare class`), abstract methods, and overload
  // signatures. The expression checker walks the body when present so
  // method internals get the same coverage as top-level functions.
  body : TsBlock?
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
  // Index signatures declared on the class body (e.g. `[key: string]:
  // T` inside `class C { [key: string]: T }`). Each entry pairs the key
  // type with the value type so the checker can resolve `instance.foo`
  // when there is no named field matching `foo`.
  index_signatures : Array[(TsType, TsType)]
  // Stage-3 decorators applied to the class declaration (`@Foo`,
  // `@Foo()`, `@a.b()`). Each entry is the decorator's call /
  // reference expression in source order. Retained so downstream
  // tooling (NestJS / TypeORM-style scanners) can inspect them; the
  // checker does not currently interpret them.
  decorators : Array[TsExpr]
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
  // Ambient module-augmentation entries (`declare module "foo" { ... }`).
  // Each pair holds the augmented specifier string and the contributed
  // declarations. The resolver merges the body's interfaces / type
  // aliases / values into the matching module lookup so user code that
  // imports from `"foo"` sees the augmented shape.
  module_augmentations : Array[(String, TsModule)]
} derive(Debug)

///|
// / module import declaration
pub(all) struct TsImportDecl {
  module_spec : String
  default_binding : String?
  namespace_binding : String?
  named_bindings : Array[(String, String)] // imported, local
  // Per-specifier `type` modifier: `import { type X, Y } from "..."`.
  // Length matches `named_bindings`; entries are `true` when the
  // imported specifier was prefixed with `type`. When the whole
  // import is `import type { ... }`, `type_only` covers it and each
  // entry's flag is `false` (the top-level modifier implies all).
  named_type_only : Array[Bool]
  side_effect_only : Bool
  type_only : Bool
  // Import attributes: `import x from "y" with { type: "json" }`
  // (and the legacy `assert { ... }` form). Each entry is a
  // `(key, string_value)` pair; non-string values are omitted.
  attributes : Array[(String, String)]
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
