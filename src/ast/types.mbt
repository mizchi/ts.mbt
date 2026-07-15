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
  Any // TS `any` — bidirectional escape hatch (flows to and from anything).
  // TS `unknown` — the safe top type. Everything is assignable to it, but
  // it can only flow into `Unknown` / `Any` until narrowed. Distinct from
  // `Any` so the checker can enforce the narrowing requirement.
  Unknown
  Never // bottom type (no value)
  // The `object` *keyword* type: any non-primitive value. Distinct from
  // `Object(fields)` (an object literal type) and from `Any` (which used to
  // swallow it, making primitive-to-`object` mismatches invisible).
  NonPrimitiveObject
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
  // A function type that declares its own generic type parameters:
  // `<S>(x: S) => T`. Wraps the underlying `Func` (or `Constructor`) and
  // carries the bound type-parameter names so the checker can add them to
  // scope. Type-parameter names are erased everywhere the function type's
  // *value* shape matters (assignability, emit, bridge), so those consumers
  // peel the wrapper to the inner callable; only scope-aware checks read the
  // names. Kept as a wrapper (rather than a field on `Func`) so the pervasive
  // `Func(params, ret)` match sites stay unchanged.
  GenericFunc(Array[String], TsType)
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

  // A call / new / method-call carrying explicit type arguments
  // (`foo<number>(x)`, `new C<string>()`, `obj.m<T>(a)`). Wraps the
  // underlying call expression; the type arguments are erased for every
  // value-level consumer (JS emission, inlining, flow analysis), which peel
  // to the inner call. Only type-checking reads the arguments — e.g. to
  // report supplying type arguments to a non-generic callee (TS2558). Kept
  // as a wrapper so the pervasive `Call` / `New` / `MethodCall` match sites
  // stay unchanged.
  TypeArgs(Array[TsType], TsExpr)

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

  // `/* @__PURE__ */ f(args)` — terser / rolldown convention for
  // "this call has no observable side effects". Wraps any call-like
  // expression (`Call` / `CallExpr` / `MethodCall` / `New` /
  // `NewExpr`). Treeshake / DCE consult this marker to drop the
  // call when its result is unused; the emit pass restores the
  // comment so downstream minifiers preserve the annotation.
  PureCall(TsExpr)

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
  // `type_param_bounds` records `(P, Bound)` pairs for type parameters that
  // declared a constraint (`function f<T extends X>()`). Sparse: only
  // constrained parameters appear, so an empty array means "no constraints".
  // The checker uses it to validate explicit type arguments (TS2344).
  type_param_bounds : Array[(String, TsType)]
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
  // `(P, Bound)` pairs for constrained interface type parameters
  // (`interface I<T extends X> {}`). Sparse — only constrained parameters
  // appear, so an empty array means "no constraints". Used by the checker to
  // validate type-argument references (`I<number>` where `T extends string`).
  type_param_bounds : Array[(String, TsType)]
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
  // Method-level generic type parameters keyed by field name: a generic
  // method `foo<T>(...)` records `("foo", ["T"])`. The checker consults
  // this so the interface's own type-argument substitution does not
  // capture a method's *shadowing* type parameter (`interface I<T> { m<T>
  // (x: T): T }` — the `m`-level `T` is fresh, unrelated to `I`'s `T`).
  // Empty for interfaces with no generic methods.
  method_type_params : Array[(String, Array[String])]
  // `(P, Bound)` constraint pairs for each generic METHOD's type
  // parameters, keyed by member name (`pipe<T extends $ZodType>` records
  // `("pipe", [("T", $ZodType)])`). Sparse — only constrained parameters
  // appear. The bridge substitutes the bound for the parameter at the
  // FFI boundary (a `T`-typed argument always satisfies its bound), so
  // bounded generic methods keep a natural signature instead of `JSValue`.
  method_type_param_bounds : Array[(String, Array[(String, TsType)])]
  // Member names carrying a `/** @internal */` JSDoc tag. tsc strips
  // these from public declaration emit (`stripInternal`), so bridge
  // scaffolds omit them from the generated surface entirely.
  internal_members : Array[String]
  // Member names carrying `@deprecated`. Bridge scaffolds keep deprecated
  // members that still type naturally but drop the ones that could only
  // widen to `JSValue` — a deprecated member nobody should adopt is not
  // worth a fallback slot (zod's `_def` / `_input` / `_output`).
  deprecated_members : Array[String]
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
  // Positionally aligned with `params`: true when the parameter is a rest
  // parameter (`...name: T[]`). An empty array means "no rest params", so
  // older producers that don't populate it stay correct by default.
  param_is_rest : Array[Bool]
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
  // True when the source declared an `=` initializer for this field
  // (`class C { x = 5 }` / `class C { x: T = expr }`). Used by the
  // checker to detect the strict-property-initialization error
  // TS2564 ("Property 'X' has no initializer and is not definitely
  // assigned in the constructor"). Defaults to false on synthesised
  // properties (getters/setters wrapped as fields, downstream-built
  // ones) -- only the real parser sites set it true.
  has_initializer : Bool
  // True when the source carried a definite-assignment assertion
  // (`class C { x!: T }`). Suppresses TS2564 for the field even
  // when there is no initializer or constructor assignment.
  has_definite_assertion : Bool
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
  // Default-value initializers paired positionally with `params`, when the
  // source supplied them (`bar(x, y = 5)`). Empty array (or shorter than
  // `params`) means "no defaults"; `None` entries are non-default params.
  // Without this the native-class emitter drops `=5` and `parseProgram(t,
  // e=140, s=…)` (babel's parser) becomes `parseProgram(t, e, s)`, so
  // calls with one argument leave `e`/`s` undefined and the loop end
  // marker never matches — `match(undefined)` is always false and the
  // top-level statement loop never terminates.
  param_defaults : Array[TsExpr?]
  // Positionally aligned with `params`: true when the parameter is a rest
  // parameter (`...name`). Empty array means no rest params.
  param_is_rest : Array[Bool]
  return_type : TsType
  is_static : Bool
  // Method body, when the source supplied one. `None` for ambient class
  // declarations (`declare class`), abstract methods, and overload
  // signatures. The expression checker walks the body when present so
  // method internals get the same coverage as top-level functions.
  body : TsBlock?
  // `"get"` / `"set"` for accessor methods, `""` for regular methods.
  // The emitter uses this to restore native `get foo()` / `set foo(v)`
  // syntax on `NativeClassStmt` / `NativeClassExpr` outputs.
  accessor : String
  // Computed method key (`class X { [Symbol.iterator]() {…} }`).
  // When `Some`, emit prints `[<expr>](...)` instead of `<name>(...)` —
  // `name` carries the sentinel `"<computed>"` and is informational
  // only. Effect's FiberRuntime relies on `[OpCodes.OP_ON_SUCCESS]
  // (op) {…}` style runtime dispatch.
  key_expr : TsExpr?
  // `async foo()` / `*foo()` / `async *foo()` modifiers — without
  // these the emit drops the `async` keyword, and a method body
  // that uses `await` re-parses as plain `await x` which is a
  // SyntaxError in non-async functions.
  is_async : Bool
  is_generator : Bool
} derive(Debug)

///|
// / class declaration
pub(all) struct TsClassDecl {
  name : String
  type_params : Array[String]
  // `(P, Bound)` pairs for constrained class type parameters
  // (`class C<T extends X> {}`). Sparse — only constrained parameters appear.
  // Used by the checker to validate explicit type arguments (TS2344).
  type_param_bounds : Array[(String, TsType)]
  // Computed-key expressions on class *fields* (`class C { [e] = 1 }`). The
  // key is an ordinary value expression; retaining it lets the checker flag an
  // undefined name in the key (TS2304). Method computed keys live on
  // `TsClassMethodDecl.key_expr`; fields have no key slot, so they are
  // collected here. Empty for classes with no computed field keys.
  computed_field_keys : Array[TsExpr]
  base_names : Array[String]
  // Names of interfaces the class `implements` (`class C implements I, J`).
  // Head identifiers only (qualified names joined with `.`, type arguments
  // dropped). The checker uses these to verify the class satisfies each
  // interface (TS2420). Empty when there is no `implements` clause.
  implements_names : Array[String]
  // Expression-shaped heritage clause (`class X extends declare(args) {…}`
  // / `class X extends make(ast) {…}`). When present this carries the
  // parsed expression and `base_names` holds the sentinel marker
  // `"<expr-base>"` so existing structural code that just counts the
  // number of bases still works. Emitters check `base_expr` first.
  base_expr : TsExpr?
  // Static-field initializers (`class X { static foo = expr; }`).
  // Only populated for `NativeClassStmt` / `NativeClassExpr` paths —
  // the IIFE-class lowering handles them via separate `PropAssign`
  // statements. Emit restores them as `static <name> = <init>;`
  // inside the class body so the binding is part of the class
  // scope rather than a post-declaration assignment.
  static_field_inits : Array[(String, TsExpr)]
  // Static initialization blocks (`class X { static { ... } }`) in source
  // order. They execute eagerly at class-definition time, so the checker's
  // definite-assignment (TS2454) pass treats an assignment to an outer
  // variable inside a static block as assigning it. Only populated for
  // runtime classes by the parser; empty elsewhere.
  static_blocks : Array[TsBlock]
  // Instance field initializers (`class X { foo = expr; }`). Populated
  // in declaration order so the checker can validate that an initializer
  // does not reference `this.bar` before `bar` has its own initializer
  // (TS2728, "Property 'X' is used before its initialization"). Only
  // populated for runtime classes by the parser; transforms ignore it
  // since the runtime path lowers these inits into the constructor body
  // separately, but keep an empty array to satisfy literal construction.
  instance_field_inits : Array[(String, TsExpr)]
  constructor_params : Array[(String, TsType)]?
  // Positionally aligned with `constructor_params`: true when the parameter
  // is a rest parameter (`constructor(...args: T[])`). Empty array means
  // "no rest params", so producers that don't populate it stay correct.
  constructor_param_is_rest : Array[Bool]
  // Positionally aligned with `constructor_params`: the default-value
  // initializer for each parameter (`constructor(x: string = 1)`), or
  // `None` when the parameter has no default. Empty / short arrays mean
  // "no defaults". The checker validates each default against its
  // parameter's declared type (TS2322) the same way it does for free
  // functions and methods.
  constructor_param_defaults : Array[TsExpr?]
  // The constructor's statement body, when the source declared a
  // constructor with an implementation (`constructor(...) { ... }`).
  // `None` for classes with no constructor, an overload signature only,
  // or an ambient `declare class`. The checker walks it with `this` bound
  // to the instance type so `this.method(args)` / `this.x` inside the
  // constructor are validated like any other method body.
  constructor_body : TsBlock?
  properties : Array[TsClassPropertyDecl]
  methods : Array[TsClassMethodDecl]
  is_abstract : Bool
  is_constructible : Bool
  // Index signatures declared on the class body (e.g. `[key: string]:
  // T` inside `class C { [key: string]: T }`). Each entry pairs the key
  // type with the value type so the checker can resolve `instance.foo`
  // when there is no named field matching `foo`.
  index_signatures : Array[(TsType, TsType)]
  // `static [key: string]: T` signatures. Kept apart from the instance
  // list: a static index signature constrains the class's *static*
  // members (TS2411) and never applies to instance member resolution.
  static_index_signatures : Array[(TsType, TsType)]
  // Stage-3 decorators applied to the class declaration (`@Foo`,
  // `@Foo()`, `@a.b()`). Each entry is the decorator's call /
  // reference expression in source order. Retained so downstream
  // tooling (NestJS / TypeORM-style scanners) can inspect them; the
  // checker does not currently interpret them.
  decorators : Array[TsExpr]
  // True for ambient `declare class` declarations and false for
  // native runtime `class` declarations. Used by the checker to
  // gate strict-property-initialization (TS2564) -- TS itself does
  // not raise TS2564 for ambient declarations.
  is_declare : Bool
  // Names of members (fields, methods, accessors, parameter properties)
  // declared with a `private` / `protected` accessibility modifier.
  // Kept as parallel name lists rather than per-member flags so the
  // checker can answer "is `X` private/protected on this class?" without
  // changing the member-decl structs. Empty for fully-public classes.
  private_members : Array[String]
  protected_members : Array[String]
  // Names of members declared `abstract` (`abstract foo(): void;` /
  // `abstract x: number;`). A non-abstract class extending a class that has
  // abstract members must implement each of them (TS2515). Stored as a name
  // list for the same reason as the visibility lists above. Empty unless the
  // class is `abstract` and declares abstract members.
  abstract_members : Array[String]
  // Member names the parser saw declared in two incompatible ways within
  // this class body -- a data field colliding with a method / accessor of
  // the same name, or a duplicated getter / setter. TypeScript reports
  // these as TS2300 ("Duplicate identifier"). Computed from declaration
  // shape alone (a data field can never share a name with a method or
  // accessor), so it is false-positive-free. Empty for the common case.
  duplicate_member_names : Array[String]
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
  // Top-level executable statements (const/let/var with type annotations,
  // class expressions, etc.) from non-ambient modules. Empty for .d.ts files.
  top_level_stmts : Array[TsStmt]
  // True when the source should be checked under
  // `strictPropertyInitialization`. The conformance test corpus uses
  // `// @strict: false` / `// @strict: true` header directives to opt
  // out of / into strict mode; the parser scans the file prefix and
  // sets this accordingly. Default is `true` (matches the
  // conformance harness baseline default, which has TS2564 emissions
  // for files without an explicit `@strict` directive).
  strict_property_initialization : Bool
  // True when the source should be checked under `noImplicitAny`
  // (detected from the conformance `@noImplicitAny` / `@strict` header
  // directives; defaults to true like the harness baseline). Checker-side
  // contextual-typing TS7006 rules gate on it.
  no_implicit_any : Bool
  // True when the source should be checked under `strictNullChecks`.
  // Distinct from `strict_property_initialization`: it shares the
  // default (`true`, matching the conformance baseline default) and the
  // `@strict: false` opt-out, but is *not* disabled by
  // `@strictPropertyInitialization: false`, and *is* disabled by
  // `@strictNullChecks: false`. Gates the nullish-literal assignability
  // checks (e.g. `null` is not assignable to `void` under strict mode,
  // but flows everywhere when off).
  strict_null_checks : Bool
  // True when class field initializers should be assumed to run via
  // ES2022 `[[DefineOwnProperty]]` semantics. This affects TS2729
  // ("property used before initialization") because the older
  // assignment-in-constructor semantics interleave field inits with
  // constructor parameter-property assigns, so a field reading a
  // param-property name isn't a use-before-init under that model.
  // Detected from `// @useDefineForClassFields: true` directives or
  // an `@target: es2022`/`esnext` directive (the TS default).
  use_define_for_class_fields : Bool
  // Deprecated compiler options detected in the conformance test header
  // directives (`// @target: es5`, etc.). Each entry is a human-readable
  // option string such as `"target=ES5"`; the checker surfaces one
  // diagnostic per entry (TS5107). Only populated from the `// @<option>`
  // directive comments that the test corpus uses — real `.d.ts` / `.ts`
  // bridge inputs never carry these, so the field stays empty for them.
  deprecated_compiler_options : Array[String]
  // Parameter properties (`public` / `private` / `protected` / `readonly`
  // on a parameter) found *outside* a class constructor. TypeScript only
  // permits them in a constructor implementation, so each entry is a real
  // TS2369. The parser records one human-readable location string per
  // offending parameter; the checker surfaces one diagnostic per entry.
  // Empty for any well-formed input (the modifier is always an error in
  // these positions), so it never costs precision.
  parameter_property_misuses : Array[String]
  // `eval` / `arguments` used as a binding identifier or assignment target
  // in strict-mode code (a `"use strict"` prologue, a class body, or a
  // conformance-header `@alwaysStrict: true` / `@strict: true` directive).
  // Always a TS1100-family grammar error in the strict variant, so each
  // recorded name is a real diagnostic. Empty for well-formed input.
  strict_mode_misuses : Array[String]
  // Decorators (`@dec`) parsed ahead of a declaration that cannot take
  // them (an enum, function, interface, variable statement, import, ...).
  // TypeScript reports TS1206 ("Decorators are not valid here") for each
  // such position; the parser records one entry per orphaned decorator
  // group. Empty for well-formed input.
  invalid_decorator_uses : Array[String]
  // Always-error grammar misuses recorded during lexing / parsing, each
  // entry a complete human-readable message: invalid source characters
  // (TS1127), unterminated template literals (TS1160), `let` as a
  // `let` / `const` binding name (TS2480), and `await` used as a binding
  // identifier inside an async context (TS1359). Empty for well-formed
  // input.
  grammar_misuses : Array[String]
  // Local binding names introduced by ES `import` statements. Consulted by
  // unresolved-reference checks so imported types / values read as
  // declared even though the import statements themselves are erased.
  imported_binding_names : Array[String]
  // Module specifiers of ES `import` statements, for the TS2307 check.
  import_module_specs : Array[String]
  // `(class, base, args)` recorded from `class C extends B<...>` heritage
  // clauses. Consulted when checking derived-class member compatibility
  // against a generic base (TS2415 index-signature subtyping).
  class_base_type_args : Array[(String, String, Array[TsType])]
  // Parameters declared with both an optional marker (`x?`) and an
  // initializer (`x = e`) -- always a TS1015 syntax error. The parser
  // records one parameter name per offending declaration; the checker
  // surfaces one diagnostic per entry. Empty for well-formed input.
  param_optional_initializer_misuses : Array[String]
  // Interface / type-literal members declared with an accessibility modifier
  // (`private` / `public` / `protected` x: T) -- always a TS1070 grammar error
  // ("'private' modifier cannot appear on a type member"). The parser records
  // one human-readable location string per offending member; the checker
  // surfaces one diagnostic per entry. Empty for well-formed input (the
  // modifier is never valid in these positions), so it never costs precision.
  interface_member_modifier_misuses : Array[String]
  // Class-body structural diagnostics for every class parsed (top-level *and*
  // nested in function bodies). Each entry is `(class_name, names)` where
  // `names` is the class's `duplicate_member_names` (duplicate members plus
  // the `<multiple-ctor-impl>` / `<index-sig-modifier>` / `<abstract-impl>`
  // sentinels). Lets the checker flag nested classes that the IIFE lowering
  // drops from `classes`. Empty for well-formed input.
  class_dup_diagnostics : Array[(String, Array[String])]
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
  // Names tagged with a `/** @internal */` JSDoc block. These are
  // exported at JS level but hidden from `.d.ts` emit — downstream
  // TypeScript consumers can't `import { x }` them through the
  // declaration, while runtime code in the same package can.
  internal_names : Map[String, Bool]
  // Names tagged with `@deprecated` along with the (optional)
  // deprecation message. The `.d.ts` emit renders this as a
  // JSDoc comment so downstream consumers' IDEs surface the
  // notice. Empty message means "deprecated but no explanation".
  deprecations : Map[String, String]
  // Function declarations annotated with `@__PURE__` or
  // `@__NO_SIDE_EFFECTS__` JSDoc. The purity pass adds these to
  // its pure set unconditionally, overriding the call-graph
  // fixpoint. Useful for functions that call into externally-
  // declared APIs the analyzer can't see through.
  pure_declarations : Map[String, Bool]
  // `type T = ...` aliases parsed at this module's top level.
  // Threaded through the bundler so whole-program type-driven
  // passes (e.g. discriminant-tag string→number rewrite) can
  // enumerate every declared shape.
  type_aliases : Array[TsTypeAlias]
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
