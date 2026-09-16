// Heterogeneous union -> auto-enum lowering.
//
// A heterogeneous union mixes runtime-discriminable members such as primitives
// and named classes (e.g. `number | string | Date`). When every member can be
// distinguished at the JS boundary via `typeof` or `instanceof`, the union can
// be lowered to a `pub(all) enum` whose cases each wrap one MoonBit type.
//
// This file currently provides only the detection and constructor-naming
// helpers. Bridge wiring (enum declaration emission, conversion helpers,
// JS-side discrimination) lands in subsequent commits.

///|
pub fn tagged_union_primitive_constructor_name(t : @ast.TsType) -> String? {
  match t {
    @ast.TsType::Number => Some("NumberValue")
    @ast.TsType::Int => Some("IntValue")
    @ast.TsType::String_ => Some("StringValue")
    @ast.TsType::Boolean => Some("BoolValue")
    @ast.TsType::BigInt => Some("BigIntValue")
    _ => None
  }
}

///|
pub fn tagged_union_named_constructor_name(name : String) -> String? {
  if name == "" {
    return None
  }
  // Already-PascalCase named types map to a `<Name>Value` constructor.
  let first = name[0].unsafe_to_char()
  if first < 'A' || first > 'Z' {
    return None
  }
  // Reject identifiers that contain non-MoonBit characters such as `.`
  // (e.g. `NodeJS.ArrayBufferView`) — they cannot be referenced from the
  // generated `pub(all) enum` body even via a `pub extern type` shim.
  for c in name {
    if !((c >= 'A' && c <= 'Z') ||
      (c >= 'a' && c <= 'z') ||
      (c >= '0' && c <= '9') ||
      c == '_') {
      return None
    }
  }
  Some(name + "Value")
}

///|
pub fn tagged_union_array_constructor_name(inner : @ast.TsType) -> String? {
  match inner {
    @ast.TsType::Number => Some("NumberArray")
    @ast.TsType::Int => Some("IntArray")
    @ast.TsType::String_ => Some("StringArray")
    @ast.TsType::Boolean => Some("BoolArray")
    @ast.TsType::Named(name) =>
      tagged_union_named_constructor_name(name + "Array")
    _ => None
  }
}

///|
pub fn tagged_union_member_constructor_name(t : @ast.TsType) -> String? {
  match tagged_union_primitive_constructor_name(t) {
    Some(name) => return Some(name)
    None => ()
  }
  match t {
    @ast.TsType::Named(name) => tagged_union_named_constructor_name(name)
    @ast.TsType::Array(inner) => tagged_union_array_constructor_name(inner)
    // A function-typed member discriminates via `typeof === "function"`
    // (`NeonAuthToken = string | (() => ...)`,
    // `ElementType = string | ((props) => ReactElement)`). At most one
    // function member per union — a second one collides on the
    // constructor name and rejects the alias.
    @ast.TsType::Func(_, _) => Some("FnValue")
    @ast.TsType::Literal(_)
    | @ast.TsType::NumberLiteral(_)
    | @ast.TsType::BooleanLiteral(_)
    | @ast.TsType::BigIntLiteral(_) => tagged_union_literal_constructor_name(t)
    _ => None
  }
}

///|
/// PascalCase constructor name for a literal-typed union member. Returns
/// `None` for empty / unsanitisable values; callers fall back to widening.
pub fn tagged_union_literal_constructor_name(t : @ast.TsType) -> String? {
  match t {
    @ast.TsType::Literal(value) =>
      tagged_union_literal_string_to_constructor(value)
    @ast.TsType::NumberLiteral(value) =>
      tagged_union_literal_numeric_to_constructor("Lit", value)
    @ast.TsType::BigIntLiteral(value) =>
      tagged_union_literal_numeric_to_constructor("LitBigInt", value)
    @ast.TsType::BooleanLiteral(value) =>
      Some(if value { "TrueValue" } else { "FalseValue" })
    _ => None
  }
}

///|
fn tagged_union_literal_string_to_constructor(value : String) -> String? {
  if value == "" {
    return None
  }
  let mut out = ""
  let mut next_upper = true
  for c in value {
    if (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') {
      let ch = if next_upper && c >= 'a' && c <= 'z' {
        (c.to_int() - 32).unsafe_to_char()
      } else if !next_upper && c >= 'A' && c <= 'Z' {
        c
      } else {
        c
      }
      out += ch.to_string()
      next_upper = false
    } else if c >= '0' && c <= '9' {
      if out == "" {
        out += "Lit"
      }
      out += c.to_string()
      next_upper = true
    } else {
      next_upper = true
    }
  }
  if out == "" {
    return None
  }
  let first = out[0].unsafe_to_char()
  if first >= '0' && first <= '9' {
    out = "Lit" + out
  }
  Some(out)
}

///|
fn tagged_union_literal_numeric_to_constructor(
  prefix : String,
  value : String,
) -> String? {
  if value == "" {
    return None
  }
  let mut out = prefix
  for c in value {
    if (c >= '0' && c <= '9') ||
      (c >= 'a' && c <= 'z') ||
      (c >= 'A' && c <= 'Z') {
      out += c.to_string()
    } else if c == '-' {
      out += "Neg"
    } else if c == '.' {
      out += "Dot"
    } else if c == '_' {
      out += "_"
    }
  }
  if out == prefix {
    None
  } else {
    Some(out)
  }
}

///|
pub fn tagged_union_case_is_no_payload(t : @ast.TsType) -> Bool {
  match t {
    @ast.TsType::Literal(_)
    | @ast.TsType::NumberLiteral(_)
    | @ast.TsType::BigIntLiteral(_)
    | @ast.TsType::BooleanLiteral(_) => true
    _ => false
  }
}

///|
pub fn tagged_union_member_is_literal_like(t : @ast.TsType) -> Bool {
  match t {
    @ast.TsType::Literal(_) => true
    @ast.TsType::NumberLiteral(_) => true
    @ast.TsType::BigIntLiteral(_) => true
    @ast.TsType::BooleanLiteral(_) => true
    _ => false
  }
}

///|
/// Decide whether a union of member types can be lowered to a tagged enum.
///
/// Returns `Some` of `(constructor_name, inner_type)` pairs when every member:
/// - is runtime-discriminable (primitive, `Array<primitive>`, `Named`, or a
///   literal whose primitive type does not overlap a non-literal sibling),
/// - has at least one non-literal member (pure literal-only unions defer to
///   `enum_lowering`),
/// - has a unique constructor name after PascalCase normalization.
///
/// Returns `None` otherwise. Callers must fall back to existing JSValue widening.
pub fn tagged_union_cases(
  members : Array[@ast.TsType],
) -> Array[(String, @ast.TsType)]? {
  if members.length() < 2 {
    return None
  }
  let cases : Array[(String, @ast.TsType)] = []
  let seen_names : Array[String] = []
  let mut has_non_literal = false
  for entry in members {
    if !tagged_union_member_is_literal_like(entry) {
      has_non_literal = true
    }
    let name = match tagged_union_member_constructor_name(entry) {
      Some(n) => n
      None => return None
    }
    if seen_names.contains(name) {
      return None
    }
    seen_names.push(name)
    cases.push((name, entry))
  }
  // Pure literal unions defer to enum_lowering; that path already produces
  // a closed `pub(all) enum` with primitive bridge conversion.
  if !has_non_literal {
    return None
  }
  // A literal whose underlying primitive type collides with a non-literal
  // sibling cannot be discriminated unambiguously at runtime.
  if tagged_union_has_primitive_overlap(members) {
    return None
  }
  Some(cases)
}

///|
fn tagged_union_member_primitive_kind(t : @ast.TsType) -> String? {
  match t {
    @ast.TsType::String_ => Some("string")
    @ast.TsType::Number => Some("number")
    @ast.TsType::Int => Some("number")
    @ast.TsType::Boolean => Some("boolean")
    @ast.TsType::BigInt => Some("bigint")
    _ => None
  }
}

///|
fn tagged_union_literal_primitive_kind(t : @ast.TsType) -> String? {
  match t {
    @ast.TsType::Literal(_) => Some("string")
    @ast.TsType::NumberLiteral(_) => Some("number")
    @ast.TsType::BooleanLiteral(_) => Some("boolean")
    @ast.TsType::BigIntLiteral(_) => Some("bigint")
    _ => None
  }
}

///|
fn tagged_union_has_primitive_overlap(members : Array[@ast.TsType]) -> Bool {
  let primitive_kinds : Array[String] = []
  for m in members {
    match tagged_union_member_primitive_kind(m) {
      Some(k) => if !primitive_kinds.contains(k) { primitive_kinds.push(k) }
      None => ()
    }
  }
  for m in members {
    match tagged_union_literal_primitive_kind(m) {
      Some(k) => if primitive_kinds.contains(k) { return true }
      None => ()
    }
  }
  false
}

///|
/// Bridge-local description of a tagged enum lowered from a heterogeneous
/// union type alias. The cases preserve declaration order and pair each
/// PascalCase constructor name with the lowered MoonBit-side inner type.
pub(all) struct BridgeTaggedUnionDecl {
  name : String
  cases : Array[(String, @ast.TsType)]
} derive(Eq, Debug)

///|
/// Try to lower a `type X = A | B | C` alias to a tagged-union declaration.
///
/// Currently rejects:
/// - generic aliases (any `type_params` present),
/// - aliases whose body is not a `Union` of at least two members,
/// - any union that fails the `tagged_union_cases` discriminability check
///   (literal members, duplicate constructor names, non-PascalCase named
///   members, etc.).
///
/// Returns `None` so callers fall back to existing widening behavior; this
/// preserves the no-op contract of the current commit until later steps wire
/// the decl through bridge emission.

///|
/// Human-readable shape of a union member that has no tagged-union case, for
/// the widening diagnostic. The point is to say what would have to be
/// SUPPORTED, not merely that something was not: an anonymous object type
/// and an object intersection both need a synthesized payload struct plus an
/// object-shaped predicate, a lowercase `Named` needs nothing (it is simply
/// not spellable), and a qualified name needs namespace flattening. Those are
/// four different pieces of work and the old wording made them one line.
fn tagged_union_member_shape_description(t : @ast.TsType) -> String {
  match t {
    @ast.TsType::Named(name) =>
      if name.contains(".") {
        "the qualified name `\{name}` cannot be spelled as an enum case"
      } else {
        "the name `\{name}` is not PascalCase-spellable as an enum case"
      }
    @ast.TsType::Applied(name, _) =>
      "the generic reference `\{name}<...>` has no monomorphic payload type"
    @ast.TsType::Object(_) =>
      "an anonymous object type needs a synthesized payload struct and an object-shaped predicate"
    @ast.TsType::Intersection(_) =>
      "an object intersection needs a flattened payload struct and an object-shaped predicate"
    @ast.TsType::Tuple(_) =>
      "a tuple type has no discriminator distinct from an array member"
    @ast.TsType::Constructor(_, _, _) =>
      "a constructor type is indistinguishable from a function member at runtime"
    @ast.TsType::Any | @ast.TsType::Unknown =>
      "`any` / `unknown` admits every runtime value, so no sibling stays discriminable"
    @ast.TsType::NonPrimitiveObject =>
      "the `object` keyword type admits every non-primitive, so no object sibling stays discriminable"
    @ast.TsType::Symbol | @ast.TsType::UniqueSymbol(_) =>
      "a symbol member has no MoonBit payload type"
    _ => "the member shape has no runtime discriminator"
  }
}

///|
/// Diagnose why a tagged-union-shaped alias would be widened to `JSValue`.
/// Returns `Some(reason)` for unions of at least two members where every
/// member is a literal but `tagged_union_cases` rejects (e.g. literal
/// primitive overlaps a non-literal sibling, or a named member is not
/// runtime-discriminable). Returns `None` when the alias is not even
/// union-shaped, when it is accepted, or when it is a pure-literal union
/// (those defer silently to `enum_lowering`).
pub fn tagged_union_widen_reason_for_alias(
  type_alias : @ast.TsTypeAlias,
) -> String? {
  if type_alias.type_params.length() != 0 {
    return None
  }
  let members = match type_alias.type_ {
    @ast.TsType::Union(items) => items
    _ => return None
  }
  if members.length() < 2 {
    return None
  }
  // Already accepted? No reason to widen.
  match tagged_union_cases(members) {
    Some(_) => return None
    None => ()
  }
  // Pure-literal unions defer to `enum_lowering`; no rejection diagnostic.
  let mut all_literal = true
  for m in members {
    if !tagged_union_member_is_literal_like(m) {
      all_literal = false
      break
    }
  }
  if all_literal {
    return None
  }
  // Filter out the optional-ish marker members. `Null` / `Undefined`
  // appear in many TypeScript declarations as nullability markers
  // (`Foo | null | undefined`); they aren't tagged-union shape failures,
  // they are simply optional widening that the existing optional-pass
  // already records elsewhere.
  let load_bearing : Array[@ast.TsType] = []
  for m in members {
    match m {
      @ast.TsType::Null | @ast.TsType::Undefined => ()
      _ => load_bearing.push(m)
    }
  }
  if load_bearing.length() < 2 {
    return None
  }
  // Primitive overlap: a literal of type T sits next to a non-literal T.
  if tagged_union_has_primitive_overlap(load_bearing) {
    return Some(
      "heterogeneous union has overlapping primitive discriminators (a literal collides with a non-literal sibling).",
    )
  }
  // Member with no constructor name. The old wording listed
  // "non-PascalCase named, function, or unsupported shape", which named a
  // cause that cannot occur — a function member IS accepted, as `FnValue` —
  // and lumped everything real under "unsupported shape". The two
  // occurrences in the fixture corpus are an anonymous object type and an
  // object intersection, and neither could be told apart from a lowercase
  // name by reading the message. Name the member instead, so
  // `scripts/bridge_widened_unions.txt` can declare it by cause.
  for m in load_bearing {
    if tagged_union_member_constructor_name(m) is None {
      return Some(
        "heterogeneous union member is not runtime-discriminable: " +
        tagged_union_member_shape_description(m) +
        ".",
      )
    }
  }
  // Duplicate constructor name after PascalCase normalisation.
  let seen : Array[String] = []
  for m in load_bearing {
    match tagged_union_member_constructor_name(m) {
      Some(name) =>
        if seen.contains(name) {
          return Some(
            "heterogeneous union has duplicate constructor names after PascalCase normalisation.",
          )
        } else {
          seen.push(name)
        }
      None => ()
    }
  }
  None
}

///|
/// Discrimination strategy for one heterogeneous-union case at the JS
/// boundary. The detector restricts inner types to runtime-discriminable
/// shapes; this enum names the JS predicate the converter should use.
///
/// `InstanceOfNamed` is a SHAPE answer, not a runtime one: it says the
/// payload is a single named type, which is what the enum renderer and the
/// `$tag` dispatch need. Whether `value instanceof <Name>` can actually run
/// is a different question — see `tagged_union_case_runtime_discriminator`.
pub(all) enum TaggedUnionCaseDiscriminator {
  TypeofString
  TypeofNumber
  TypeofBoolean
  TypeofBigInt
  TypeofFunction
  IsArrayPredicate
  InstanceOfNamed(String)
  StrictEqualsString(String)
  StrictEqualsNumber(String)
  StrictEqualsBigInt(String)
  StrictEqualsBool(Bool)
} derive(Eq, Debug)

///|
pub fn tagged_union_case_discriminator(
  inner : @ast.TsType,
) -> TaggedUnionCaseDiscriminator? {
  match inner {
    @ast.TsType::String_ => Some(TypeofString)
    @ast.TsType::Number => Some(TypeofNumber)
    @ast.TsType::Int => Some(TypeofNumber)
    @ast.TsType::Boolean => Some(TypeofBoolean)
    @ast.TsType::BigInt => Some(TypeofBigInt)
    @ast.TsType::Array(_) => Some(IsArrayPredicate)
    @ast.TsType::Func(_, _) => Some(TypeofFunction)
    @ast.TsType::Named(name) => Some(InstanceOfNamed(name))
    @ast.TsType::Literal(value) => Some(StrictEqualsString(value))
    @ast.TsType::NumberLiteral(value) => Some(StrictEqualsNumber(value))
    @ast.TsType::BigIntLiteral(value) => Some(StrictEqualsBigInt(value))
    @ast.TsType::BooleanLiteral(value) => Some(StrictEqualsBool(value))
    _ => None
  }
}

///|
/// The runtime half of `tagged_union_case_discriminator`: the same answer,
/// except that a `Named` payload only keeps its `instanceof` predicate when
/// the name denotes a JS global constructor that exists at the bridge
/// boundary.
///
/// This distinction is the whole point. `tagged_union_named_constructor_name`
/// asks whether a name is PascalCase and MoonBit-spellable — a NAMING test —
/// and the discriminator took that as licence to emit `value instanceof
/// <Name>`. A TypeScript interface, type alias, enum or type parameter is
/// erased, so that predicate is a `ReferenceError` the first time it runs:
/// `_from_js` converters carrying `instanceof PathLike` (an alias),
/// `instanceof Expression` (an interface), `instanceof ScriptTarget` (an
/// enum) and `instanceof T` (a type parameter) were emitted 411 times across
/// the generated corpus, and 2,126 converter calls threw.
///
/// `moonbit_inline_union_runtime_named_ok` already knew this, and states it
/// in its own doc comment; it was consulted at exactly one site
/// (`ffi_synthesize_inline_union`) and there only for a union that has a
/// FUNCTION member, because the check was written inside the
/// `func_members > 0` branch. That condition is right for the thing next to
/// it — a second function case collides on `typeof === "function"` — and has
/// nothing to do with whether a sibling's `instanceof` resolves. Routing the
/// predicate through one place is what keeps the two from disagreeing again.
///
/// Declining costs a MISS, never a false positive: the alias still lowers to
/// an enum and its `_to_js` direction (a `$tag` dispatch that needs no
/// runtime predicate at all) is unaffected, so parameters keep their types.
/// Only the return-side `_from_js` wrapper is withheld — which is exactly
/// what `ffi_tagged_union_return_is_safe_to_wrap` already refused to call
/// for these cases, so the JS being dropped was never reachable.
pub fn tagged_union_case_runtime_discriminator(
  inner : @ast.TsType,
) -> TaggedUnionCaseDiscriminator? {
  match tagged_union_case_discriminator(inner) {
    Some(InstanceOfNamed(name)) =>
      if @parser.moonbit_inline_union_runtime_named_ok(name) {
        Some(InstanceOfNamed(name))
      } else {
        None
      }
    other => other
  }
}

///|
/// The first case whose payload has no RUNTIME discriminator, as
/// `(case name, payload name)`. Drives the generated-source note that
/// replaces a `_from_js` converter we decline to emit, so the reason is
/// legible in `bridge.js` instead of only in this file.
fn tagged_union_first_undiscriminable_case(
  decl : BridgeTaggedUnionDecl,
) -> (String, String)? {
  for entry in decl.cases {
    let (case_name, inner) = entry
    if tagged_union_case_runtime_discriminator(inner) is None {
      let payload = match inner {
        @ast.TsType::Named(name) => name
        _ =>
          match tagged_union_inner_moonbit_text(inner) {
            Some(text) => text
            None => "<unsupported payload>"
          }
      }
      return Some((case_name, payload))
    }
  }
  None
}

///|
fn tagged_union_case_predicate_text(
  d : TaggedUnionCaseDiscriminator,
  expr : String,
) -> String {
  match d {
    TypeofString => "typeof " + expr + " === \"string\""
    TypeofNumber => "typeof " + expr + " === \"number\""
    TypeofBoolean => "typeof " + expr + " === \"boolean\""
    TypeofBigInt => "typeof " + expr + " === \"bigint\""
    TypeofFunction => "typeof " + expr + " === \"function\""
    IsArrayPredicate => "Array.isArray(" + expr + ")"
    InstanceOfNamed(name) => expr + " instanceof " + name
    StrictEqualsString(value) =>
      expr + " === " + tagged_union_js_string_literal(value)
    StrictEqualsNumber(value) => expr + " === " + value
    StrictEqualsBigInt(value) => expr + " === " + value + "n"
    StrictEqualsBool(true) => expr + " === true"
    StrictEqualsBool(false) => expr + " === false"
  }
}

///|
/// JS-quoted string literal text for use inside a generated `bridge.js` /
/// inline lambda body. Escapes `\\` and `"`, and replaces newlines with `\\n`
/// so the literal stays valid on a single source line.
fn tagged_union_js_string_literal(value : String) -> String {
  let mut out = "\""
  for c in value {
    if c == '\\' {
      out += "\\\\"
    } else if c == '"' {
      out += "\\\""
    } else if c == '\n' {
      out += "\\n"
    } else if c == '\r' {
      out += "\\r"
    } else if c == '\t' {
      out += "\\t"
    } else {
      out += c.to_string()
    }
  }
  out += "\""
  out
}

///|
/// Render the JS-side payload expression for a tagged-union case at the
/// `to_js` boundary. For literal cases we re-emit the literal text directly
/// instead of reading `_0`, since MoonBit no-payload enum cases are stored
/// as `{ "$tag": i }` without a `_0` slot.
fn tagged_union_case_to_js_literal_text(t : @ast.TsType) -> String? {
  match t {
    @ast.TsType::Literal(value) => Some(tagged_union_js_string_literal(value))
    @ast.TsType::NumberLiteral(value) => Some(value)
    @ast.TsType::BigIntLiteral(value) => Some(value + "n")
    @ast.TsType::BooleanLiteral(true) => Some("true")
    @ast.TsType::BooleanLiteral(false) => Some("false")
    _ => None
  }
}

///|
/// JS-side snippet that takes a MoonBit tagged-union value bound to `expr`
/// and returns its inner JS payload by reading `$tag` and the positional
/// `_0` field. Cases keep declaration order so `$tag === i` matches the
/// `i`-th case in the MoonBit enum.
///
/// `nested` maps `Named` payload types that are themselves tagged-union
/// aliases to their declaration; when a case payload references one of
/// those names the snippet recursively unwraps the inner value, so
/// nested aliases like `PathOrFileDescriptor = PathLike | number`
/// resolve to a single primitive at the JS boundary.
pub fn tagged_union_to_js_expression(
  decl : BridgeTaggedUnionDecl,
  expr : String,
) -> String {
  tagged_union_to_js_expression_with_nested(decl, expr, {})
}

///|
pub fn tagged_union_to_js_expression_with_nested(
  decl : BridgeTaggedUnionDecl,
  expr : String,
  nested : Map[String, BridgeTaggedUnionDecl],
  struct_converter_names? : Array[String] = [],
) -> String {
  let mut body = "(() => { "
  // Allow `@sut.unsafeCast(rawValue)` callers to pass primitives or
  // already-shaped JS values straight through. A real MoonBit tagged-union
  // payload is an object with both `$tag` and `_0`; anything else is
  // already in the JS-side shape, so return it as-is.
  body = body +
    "if (" +
    expr +
    " === null || typeof " +
    expr +
    " !== \"object\" || !(\"$tag\" in " +
    expr +
    ")) return " +
    expr +
    "; "
  for i, entry in decl.cases {
    let (_, inner) = entry
    if i == 0 {
      body = body + "if (" + expr + ".$tag === " + i.to_string() + ") "
    } else {
      body = body + "else if (" + expr + ".$tag === " + i.to_string() + ") "
    }
    // For a `Named(name)` payload, prefer (1) a nested tagged-union
    // converter, (2) a per-struct `__ts_mbt_to_js_<snake>` converter when
    // the case wraps a generated interface that needs JS-shape conversion
    // (e.g. enum-tag fields rewritten from `type_: 0` to `type:
    // "increment"`), or (3) a bare `_0` unwrap when neither applies.
    let payload_expr = match tagged_union_case_to_js_literal_text(inner) {
      Some(literal_text) => literal_text
      None =>
        match inner {
          @ast.TsType::Named(name) =>
            match nested.get(name) {
              Some(_) =>
                tagged_union_to_js_function_name(name) + "(" + expr + "._0)"
              None =>
                if struct_converter_names.contains(name) {
                  ffi_struct_converter_name(name) + "(" + expr + "._0)"
                } else {
                  expr + "._0"
                }
            }
          _ => expr + "._0"
        }
    }
    body = body + "return " + payload_expr + "; "
  }
  body = body +
    "throw new Error(\"unexpected " +
    decl.name +
    " tag: \" + " +
    expr +
    ".$tag); })()"
  body
}

///|
/// JS-side snippet that takes a JS value bound to `expr` and constructs the
/// matching MoonBit tagged-union representation (`{$tag, _0}`). Returns
/// `None` when the construction cannot be decided at runtime; call sites must
/// fall back to a primitive widening then.
///
/// A case whose payload is an ERASED TypeScript name has no predicate that can
/// execute — `value instanceof <interface>` is a `ReferenceError` at the
/// boundary rather than a type we failed to narrow — so this used to refuse the
/// whole union the moment one case lacked a discriminator.
///
/// It only has to refuse when TWO or more do. The union is CLOSED: the value is
/// declared to be one of its members, so failing every other case's test IS the
/// remaining case, and that one needs no predicate. `string |
/// DiagnosticMessageChain` is exactly the shape — `typeof === "string"` decides
/// the first, and anything else is the second by declaration — and it is
/// `Diagnostic.messageText`, reached through
/// `Program::getSemanticDiagnostics`. With two undiscriminable cases the else
/// cannot choose between them (`CatchClause | VariableDeclarationList`, both
/// erased), and that is still `None`.
///
/// The fallback is emitted LAST whatever its declared position, which is what
/// makes it an else rather than a test that swallows its siblings, and it
/// replaces the `throw` rather than sitting before it. Worth being precise
/// about what is given up: the throw was the only thing that noticed a value
/// the `.d.ts` mis-declared. Now such a value is tagged as the fallback case
/// instead — but the alternative this replaces is the caller receiving the raw
/// JS value under a type claiming `{$tag, _0}`, which is wrong in the same
/// direction and silent, so nothing that used to be caught stops being caught.
pub fn tagged_union_from_js_expression(
  decl : BridgeTaggedUnionDecl,
  expr : String,
) -> String? {
  let undiscriminable : Array[Int] = []
  for i, entry in decl.cases {
    let (_, inner) = entry
    if tagged_union_case_runtime_discriminator(inner) is None {
      undiscriminable.push(i)
    }
  }
  if undiscriminable.length() > 1 {
    return None
  }
  let fallback = if undiscriminable.length() == 1 {
    Some(undiscriminable[0])
  } else {
    None
  }
  fn case_return(i : Int, inner : @ast.TsType) -> String {
    if tagged_union_case_is_no_payload(inner) {
      "return { \"$tag\": " + i.to_string() + " }; "
    } else {
      "return { \"$tag\": " + i.to_string() + ", \"_0\": " + expr + " }; "
    }
  }

  let mut body = "(() => { "
  // `emitted` rather than `i == 0`, because the fallback may BE case 0 and the
  // first real test then has to open the chain with `if`.
  let mut emitted = 0
  for i, entry in decl.cases {
    let (_, inner) = entry
    if fallback is Some(f) && f == i {
      continue
    }
    let predicate = match tagged_union_case_runtime_discriminator(inner) {
      Some(d) => tagged_union_case_predicate_text(d, expr)
      None => return None
    }
    if emitted == 0 {
      body = body + "if (" + predicate + ") "
    } else {
      body = body + "else if (" + predicate + ") "
    }
    emitted += 1
    body = body + case_return(i, inner)
  }
  match fallback {
    Some(f) => {
      let (_, inner) = decl.cases[f]
      if emitted > 0 {
        body = body + "else "
      }
      body = body + case_return(f, inner)
    }
    None =>
      body = body + "throw new Error(\"unexpected " + decl.name + " value\"); "
  }
  Some(body + "})()")
}

///|

///|
/// Render a `TsType` as MoonBit-side type text for a tagged-union case
/// payload. Cases are restricted to primitive / `Named` / array-of-either,
/// which keeps the inner type text stateless.
pub fn tagged_union_inner_moonbit_text(t : @ast.TsType) -> String? {
  tagged_union_inner_moonbit_text_with_arity(t, {})
}

///|
/// State-aware variant: when `generic_type_params_by_name` says a `Named`
/// payload type was registered with arity > 0, fill the slots with
/// `JSValue` so the emitted enum case stays MoonBit-legal (e.g. preact's
/// generic `VNode<T>` becomes `VNode[JSValue]`). Callers that have no
/// arity registry can pass `{}` and keep the previous bare-name shape.
pub fn tagged_union_inner_moonbit_text_with_arity(
  t : @ast.TsType,
  generic_type_params_by_name : Map[String, Array[String]],
) -> String? {
  match t {
    @ast.TsType::Number => Some("Double")
    @ast.TsType::Int => Some("Int")
    @ast.TsType::String_ => Some("String")
    @ast.TsType::Boolean => Some("Bool")
    @ast.TsType::BigInt => Some("Int64")
    @ast.TsType::Named(name) =>
      match generic_type_params_by_name.get(name) {
        Some(type_params) if type_params.length() > 0 => {
          let widened : Array[String] = []
          for _ in 0..<type_params.length() {
            widened.push("JSValue")
          }
          Some(name + "[" + widened.join(", ") + "]")
        }
        _ => Some(name)
      }
    @ast.TsType::Array(inner) =>
      match
        tagged_union_inner_moonbit_text_with_arity(
          inner, generic_type_params_by_name,
        ) {
        Some(text) => Some("Array[" + text + "]")
        None => None
      }
    // A function payload renders as a MoonBit arrow; positions whose type
    // has no direct rendering widen to `JSValue` locally instead of
    // failing the whole enum (`AuthToken = string | (() => string)`).
    @ast.TsType::Func(params, ret) => {
      let rendered_params : Array[String] = []
      for p in params {
        rendered_params.push(
          match
            tagged_union_inner_moonbit_text_with_arity(
              p, generic_type_params_by_name,
            ) {
            Some(text) => text
            None => "JSValue"
          },
        )
      }
      let rendered_ret = match ret {
        @ast.TsType::Void => "Unit"
        other =>
          match
            tagged_union_inner_moonbit_text_with_arity(
              other, generic_type_params_by_name,
            ) {
            Some(text) => text
            None => "JSValue"
          }
      }
      Some("(" + rendered_params.join(", ") + ") -> " + rendered_ret)
    }
    _ => None
  }
}

///|
/// Render a `BridgeTaggedUnionDecl` as a `pub(all) enum` MoonBit section.
pub fn tagged_union_decl_to_moonbit_section(
  decl : BridgeTaggedUnionDecl,
) -> String? {
  tagged_union_decl_to_moonbit_section_with_arity(decl, {})
}

///|
pub fn tagged_union_decl_to_moonbit_section_with_arity(
  decl : BridgeTaggedUnionDecl,
  generic_type_params_by_name : Map[String, Array[String]],
) -> String? {
  let mut body = "///|\npub(all) enum " + decl.name + " {\n"
  for entry in decl.cases {
    let (case_name, inner) = entry
    if tagged_union_case_is_no_payload(inner) {
      body = body + "  " + case_name + "\n"
    } else {
      let inner_text = match
        tagged_union_inner_moonbit_text_with_arity(
          inner, generic_type_params_by_name,
        ) {
        Some(text) => text
        None => return None
      }
      body = body + "  " + case_name + "(" + inner_text + ")\n"
    }
  }
  body = body + "}"
  Some(body)
}

///|
/// Stable JS function name pair for the bridge.js converters of one
/// tagged-union alias.
pub fn tagged_union_to_js_function_name(decl_name : String) -> String {
  "__ts_mbt_tagged_union_" + tagged_union_to_snake_case(decl_name) + "_to_js"
}

///|
pub fn tagged_union_from_js_function_name(decl_name : String) -> String {
  "__ts_mbt_tagged_union_" + tagged_union_to_snake_case(decl_name) + "_from_js"
}

///|
fn tagged_union_to_snake_case(name : String) -> String {
  let mut out = ""
  for i, c in name {
    let ch = c
    if ch >= 'A' && ch <= 'Z' {
      if i > 0 {
        out = out + "_"
      }
      out = out + (ch.to_int() + 32).unsafe_to_char().to_string()
    } else {
      out = out + ch.to_string()
    }
  }
  out
}

///|
/// Render the bridge.js converters for one tagged-union alias.
///
/// The two directions are emitted independently, because only one of them
/// needs a runtime predicate. `_to_js` reads `$tag` off the MoonBit value
/// and can always be written; `_from_js` has to TEST an incoming JS value,
/// so it is withheld when a case payload has no executable discriminator
/// (`tagged_union_case_runtime_discriminator`). The withheld half is
/// replaced by a note naming the case, and the surviving `_to_js` keeps
/// parameter positions typed — before this split a declined `_from_js`
/// took the sound `_to_js` down with it.
///
/// Never returns `None` today; the option is kept for callers that already
/// handle a fully-undecidable alias.
pub fn tagged_union_bridge_js_converter_decls(
  decl : BridgeTaggedUnionDecl,
) -> String? {
  tagged_union_bridge_js_converter_decls_with_nested(decl, {})
}

///|
pub fn tagged_union_bridge_js_converter_decls_with_nested(
  decl : BridgeTaggedUnionDecl,
  nested : Map[String, BridgeTaggedUnionDecl],
  struct_converter_names? : Array[String] = [],
) -> String? {
  let to_js_body = tagged_union_to_js_expression_with_nested(
    decl,
    "value",
    nested,
    struct_converter_names~,
  )
  let to_name = tagged_union_to_js_function_name(decl.name)
  let from_name = tagged_union_from_js_function_name(decl.name)
  // `export function` so MoonBit `extern "js" fn ... = "<name>"` ESM
  // imports can resolve the helper from the generated bridge module.
  let to_decl = "export function " +
    to_name +
    "(value) { return " +
    to_js_body +
    "; }"
  match tagged_union_from_js_expression(decl, "value") {
    Some(from_js_body) => {
      let from_decl = "export function " +
        from_name +
        "(value) { return " +
        from_js_body +
        "; }"
      Some(to_decl + "\n" + from_decl)
    }
    None => {
      // Say which case and why, because the two reasons need different
      // fixes: an interface / alias / enum / type parameter has no runtime
      // value at all and never will, while a class the module exports could
      // be bound in `bridge.js` and then discriminated (see TODO.md).
      let reason = match tagged_union_first_undiscriminable_case(decl) {
        Some((case_name, payload)) =>
          "case " +
          case_name +
          " carries " +
          payload +
          ", which is not a JS global constructor, so no `instanceof` " +
          "predicate resolves in this module"
        None => "a case payload has no runtime discriminator"
      }
      Some(to_decl + "\n// No " + from_name + ": " + reason + ".")
    }
  }
}

///|
pub fn tagged_union_type_alias_decl(
  type_alias : @ast.TsTypeAlias,
) -> BridgeTaggedUnionDecl? {
  if type_alias.type_params.length() != 0 {
    return None
  }
  let union_members = match type_alias.type_ {
    @ast.TsType::Union(items) => items
    _ => return None
  }
  match tagged_union_cases(union_members) {
    Some(cases) => Some({ name: type_alias.name, cases, })
    None => None
  }
}

///|
/// Collect the Named heads a tagged-union case payload references,
/// including function-typed payloads' parameter / return types (the
/// instantiated `string | ((issue: T) => string)` aliases put their
/// interface references inside the `FnValue` case). Callers use the
/// result to pre-declare opaque companions; names that cannot appear
/// verbatim in a declaration (qualified or `$`-mangled) are skipped —
/// the renderer widens those payloads anyway.
pub fn tagged_union_case_named_refs(
  t : @ast.TsType,
  out : Array[String],
) -> Unit {
  fn keep(name : String) -> Bool {
    name != "" && !name.contains("$") && !name.contains(".")
  }

  match t {
    @ast.TsType::Named(name) =>
      if keep(name) && !out.contains(name) {
        out.push(name)
      }
    @ast.TsType::Applied(name, args) => {
      if keep(name) && !out.contains(name) {
        out.push(name)
      }
      for arg in args {
        tagged_union_case_named_refs(arg, out)
      }
    }
    @ast.TsType::Array(inner) | @ast.TsType::Rest(inner) =>
      tagged_union_case_named_refs(inner, out)
    @ast.TsType::Func(params, return_type) => {
      for param in params {
        tagged_union_case_named_refs(param, out)
      }
      tagged_union_case_named_refs(return_type, out)
    }
    @ast.TsType::Union(items) | @ast.TsType::Intersection(items) =>
      for item in items {
        tagged_union_case_named_refs(item, out)
      }
    @ast.TsType::Tuple(items) =>
      for item in items {
        tagged_union_case_named_refs(item, out)
      }
    _ => ()
  }
}
