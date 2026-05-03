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
  // Already-PascalCase named types map to a `<Name>Value` constructor unless
  // the inner type name is already distinct enough to stand alone. We always
  // suffix `Value` for primitives via the helper above; for named types we
  // suffix `Value` too so cases stay grammatically uniform.
  let first = name[0].unsafe_to_char()
  if first < 'A' || first > 'Z' {
    return None
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
    @ast.TsType::Named(name) => tagged_union_named_constructor_name(name + "Array")
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
    _ => None
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
/// - is runtime-discriminable (primitive, `Array<primitive>`, or `Named`),
/// - is not a string / number / boolean literal (those go through the existing
///   literal-union enum lowering instead),
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
  for entry in members {
    if tagged_union_member_is_literal_like(entry) {
      return None
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
  Some(cases)
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
/// Discrimination strategy for one heterogeneous-union case at the JS
/// boundary. The detector restricts inner types to runtime-discriminable
/// shapes; this enum names the JS predicate the converter should use.
pub(all) enum TaggedUnionCaseDiscriminator {
  TypeofString
  TypeofNumber
  TypeofBoolean
  TypeofBigInt
  IsArrayPredicate
  InstanceOfNamed(String)
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
    @ast.TsType::Named(name) => Some(InstanceOfNamed(name))
    _ => None
  }
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
    IsArrayPredicate => "Array.isArray(" + expr + ")"
    InstanceOfNamed(name) => expr + " instanceof " + name
  }
}

///|
/// JS-side snippet that takes a MoonBit tagged-union value bound to `expr`
/// and returns its inner JS payload by reading `$tag` and the positional
/// `_0` field. Cases keep declaration order so `$tag === i` matches the
/// `i`-th case in the MoonBit enum.
pub fn tagged_union_to_js_expression(
  decl : BridgeTaggedUnionDecl,
  expr : String,
) -> String {
  let mut body = "(() => { "
  for i, _entry in decl.cases {
    if i == 0 {
      body = body + "if (" + expr + ".$tag === " + i.to_string() + ") "
    } else {
      body = body + "else if (" + expr + ".$tag === " + i.to_string() + ") "
    }
    body = body + "return " + expr + "._0; "
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
/// `None` if any case lacks a runtime discriminator. Call sites must fall
/// back to a primitive widening when this returns `None`.
pub fn tagged_union_from_js_expression(
  decl : BridgeTaggedUnionDecl,
  expr : String,
) -> String? {
  let mut body = "(() => { "
  for i, entry in decl.cases {
    let (_, inner) = entry
    let predicate = match tagged_union_case_discriminator(inner) {
      Some(d) => tagged_union_case_predicate_text(d, expr)
      None => return None
    }
    if i == 0 {
      body = body + "if (" + predicate + ") "
    } else {
      body = body + "else if (" + predicate + ") "
    }
    body = body + "return { \"$tag\": " + i.to_string() + ", \"_0\": " + expr +
      " }; "
  }
  body = body + "throw new Error(\"unexpected " + decl.name + " value\"); })()"
  Some(body)
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
    Some(cases) => Some({ name: type_alias.name, cases })
    None => None
  }
}
