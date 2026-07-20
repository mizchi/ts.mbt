///|
priv struct MoonBitDeclState {
  declared_type_names : Array[String]
  referenced_type_names : Array[String]
  local_type_param_names : Array[String]
  // Names of declared types whose generic parameters should appear on
  // `Applied(name, args)` references (e.g. `Box<string>` ⇒ `Box[String]`).
  generic_preserved_type_names : Array[String]
  // Arity of each generic-preserved type, keyed by interface name. Used
  // to widen bare references (`Ref` ⇒ `Ref[JSValue]`) and arity-mismatched
  // references to a syntactically valid form matching the struct decl.
  generic_preserved_type_arity_by_name : Map[String, Int]
  mut needs_jsvalue : Bool
  // Track whether `Applied("Promise"|"PromiseLike", ...)` was emitted so
  // the declarations file can append a self-contained
  // `declare pub type Promise[X]` opaque alias instead of pulling in
  // `mizchi/js/core::Promise`.
  mut needs_promise : Bool
}

///|
fn generic_preserved_type_arity(state : MoonBitDeclState, name : String) -> Int {
  match state.generic_preserved_type_arity_by_name.get(name) {
    Some(arity) => arity
    None => 0
  }
}

///|
let moonbit_function_field_method_wrapper_limit : Int = 128

///|
fn is_ascii_letter(c : Char) -> Bool {
  (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
}

///|
fn is_ascii_digit(c : Char) -> Bool {
  c >= '0' && c <= '9'
}

///|
fn sanitize_identifier_chars(name : String, fallback : String) -> String {
  let mut result = ""
  for c in name {
    if is_ascii_letter(c) || is_ascii_digit(c) || c == '_' {
      result += c.to_string()
    } else {
      result += "_"
    }
  }
  if result == "" {
    result = fallback
  }
  let first = result[0].unsafe_to_char()
  if is_ascii_digit(first) {
    result = "_" + result
  }
  result
}

///|
fn is_all_underscores(name : String) -> Bool {
  if name == "" {
    return false
  }
  for c in name {
    if c != '_' {
      return false
    }
  }
  true
}

///|
fn value_identifier_needs_suffix(name : String) -> Bool {
  match name {
    "alias"
    | "and"
    | "as"
    | "assert"
    | "async"
    | "await"
    | "break"
    | "case"
    | "catch"
    | "class"
    | "const"
    | "constructor"
    | "continue"
    | "declare"
    | "defer"
    | "do"
    | "else"
    | "enum"
    | "export"
    | "extern"
    | "false"
    | "final"
    | "finally"
    | "fn"
    | "for"
    | "guard"
    | "if"
    | "import"
    | "in"
    | "include"
    | "interface"
    | "is"
    | "lazy"
    | "let"
    | "local"
    | "loop"
    | "match"
    | "method"
    | "module"
    | "move"
    | "namespace"
    | "new"
    | "null"
    | "or"
    | "override"
    | "package"
    | "priv"
    | "private"
    | "protected"
    | "pub"
    | "public"
    | "raise"
    | "readonly"
    | "ref"
    | "resume"
    | "return"
    | "static"
    | "struct"
    | "super"
    | "switch"
    | "test"
    | "throw"
    | "trait"
    | "true"
    | "try"
    | "type"
    | "typealias"
    | "typeof"
    | "use"
    | "using"
    | "var"
    | "void"
    | "while"
    | "with" => true
    _ => false
  }
}

///|
fn lower_leading_ascii(name : String) -> String {
  if name == "" {
    return name
  }
  let first = name[0].unsafe_to_char()
  if first >= 'A' && first <= 'Z' {
    (first.to_int() + 32).unsafe_to_char().to_string() + name[1:].to_owned()
  } else {
    name
  }
}

///|
fn sanitize_value_identifier(name : String, fallback : String) -> String {
  let mut result = lower_leading_ascii(
    sanitize_identifier_chars(name, fallback),
  )
  if value_identifier_needs_suffix(result) {
    result += "_"
  }
  result
}

///|
fn sanitize_identifier(name : String, fallback : String) -> String {
  let result = sanitize_identifier_chars(name, fallback)
  match result {
    "alias"
    | "as"
    | "break"
    | "catch"
    | "const"
    | "continue"
    | "defer"
    | "else"
    | "fn"
    | "for"
    | "if"
    | "in"
    | "is"
    | "let"
    | "loop"
    | "match"
    | "method"
    | "constructor"
    | "override"
    | "priv"
    | "pub"
    | "resume"
    | "return"
    | "struct"
    | "test"
    | "trait"
    | "type"
    | "typealias"
    | "using"
    | "use"
    | "with"
    | "while" => result + "_"
    _ => result
  }
}

///|
fn moonbit_type_identifier(name : String, fallback : String) -> String {
  let sanitized = sanitize_identifier_chars(name, fallback)
  if sanitized == "" || is_all_underscores(sanitized) {
    return fallback
  }
  let mut idx = 0
  let mut prefix = ""
  while idx < sanitized.length() && sanitized[idx].unsafe_to_char() == '_' {
    prefix += "Underscore"
    idx += 1
  }
  let core = sanitized[idx:].to_owned()
  if core == "" {
    return fallback
  }
  let first = core[0].unsafe_to_char()
  let normalized_core = if first >= 'a' && first <= 'z' {
    (first.to_int() - 32).unsafe_to_char().to_string() + core[1:].to_owned()
  } else {
    core
  }
  let normalized = prefix + normalized_core
  match normalized {
    "Array" | "Bool" | "Double" | "Error" | "Int" | "String" | "Unit" =>
      normalized + "_"
    _ => normalized
  }
}

///|
fn push_unique_decl_section(
  seen_names : Array[String],
  sections : Array[String],
  binding_name : String,
  section : String,
) -> Unit {
  if seen_names.contains(binding_name) {
    return
  }
  seen_names.push(binding_name)
  sections.push(section)
}

///|
fn mark_referenced_type(state : MoonBitDeclState, name : String) -> Unit {
  if name == "Array" || name == "ReadonlyArray" {
    return
  }
  if state.declared_type_names.contains(name) {
    return
  }
  if state.referenced_type_names.contains(name) {
    return
  }
  state.referenced_type_names.push(name)
}

///|
fn push_local_type_params(
  state : MoonBitDeclState,
  names : Array[String],
) -> Int {
  let old_len = state.local_type_param_names.length()
  for name in names {
    if !state.local_type_param_names.contains(name) {
      state.local_type_param_names.push(name)
    }
  }
  old_len
}

///|
fn restore_local_type_params(state : MoonBitDeclState, old_len : Int) -> Unit {
  while state.local_type_param_names.length() > old_len {
    let _ = state.local_type_param_names.pop()
  }
}

///|
fn is_local_type_param(state : MoonBitDeclState, name : String) -> Bool {
  state.local_type_param_names.contains(name)
}

///|
fn moonbit_type_param_suffix(type_params : Array[String]) -> String {
  if type_params.length() == 0 {
    ""
  } else {
    let sanitized : Array[String] = []
    for name in type_params {
      sanitized.push(moonbit_sanitize_type_param_name(name))
    }
    "[" + sanitized.join(", ") + "]"
  }
}

///|
/// MoonBit identifiers do not allow `$`, but TypeScript declarations
/// produced by tools like `tsc` can mint synthetic type parameter names
/// such as `TInput$1` to disambiguate scope-shadowed generics. Replace
/// `$` with `_` so both the declaration site and any reference (which
/// goes through this helper or `moonbit_type_name` below) end up with
/// the same MoonBit-legal identifier.
pub fn moonbit_sanitize_type_param_name(name : String) -> String {
  if name == "" {
    return name
  }
  let mut needs = false
  for c in name {
    if c == '$' {
      needs = true
      break
    }
  }
  if !needs {
    return name
  }
  let mut out = ""
  for c in name {
    if c == '$' {
      out += "_"
    } else {
      out += c.to_string()
    }
  }
  out
}

///|
fn moonbit_function_type_param_prefix(type_params : Array[String]) -> String {
  if type_params.length() == 0 {
    "fn"
  } else {
    "fn" + moonbit_type_param_suffix(type_params)
  }
}

///|
fn moonbit_receiver_self_type(
  type_name : String,
  type_params : Array[String],
) -> String {
  type_name + moonbit_type_param_suffix(type_params)
}

///|
/// Whether to keep an interface's TypeScript type parameters when emitting
/// MoonBit declarations. Mirrors `ffi_should_preserve_interface_type_params`
/// in `src/bridge/moonbit_js_ffi.mbt` so the FFI side and the decl side
/// agree on which interfaces emit `Foo[T, U]` vs bare `Foo`.
fn moonbit_should_preserve_interface_type_params(
  iface : @ast.TsInterface,
) -> Bool {
  iface.type_params.length() > 0
}

///|
fn is_likely_discarded_type_param_name(name : String) -> Bool {
  if name == "SS" {
    return true
  }
  if name.length() != 1 {
    return false
  }
  let c = name[0].unsafe_to_char()
  c >= 'A' && c <= 'Z'
}

///|
fn should_widen_unresolved_type_param(
  state : MoonBitDeclState,
  name : String,
) -> Bool {
  !state.declared_type_names.contains(name) &&
  is_likely_discarded_type_param_name(name)
}

// Structural classification helpers now live in `mizchi/ts/checker`. The
// parser-side aliases below keep call sites concise.

///|
fn moonbit_tuple_type_name(
  state : MoonBitDeclState,
  items : Array[@ast.TsType],
) -> String {
  if items.length() == 0 {
    return "Array[Unit]"
  }
  let first = moonbit_type_name(state, items[0])
  for i in 1..<items.length() {
    if moonbit_type_name(state, items[i]) != first {
      state.needs_jsvalue = true
      return "Array[JSValue]"
    }
  }
  "Array[\{first}]"
}

///|
fn moonbit_func_type_name(
  state : MoonBitDeclState,
  params : Array[@ast.TsType],
  return_type : @ast.TsType,
) -> String {
  let param_types : Array[String] = []
  for param in params {
    param_types.push(moonbit_type_name(state, param))
  }
  let params_src = param_types.join(", ")
  // Callback returns of the `T | Promise<T>` shape read as `Promise[T]`
  // (mirrors the ffi renderers; sound with the resolve-lenient wait and
  // required for the async-callback lowering on sync-or-async slots).
  let return_src = moonbit_type_name(
    state,
    @checker.normalize_promise_like_union_return(return_type),
  )
  "(\{params_src}) -> \{return_src}"
}

///|
fn moonbit_type_name(state : MoonBitDeclState, type_ : @ast.TsType) -> String {
  // Unresolved `infer X extends Bound` markers should collapse to the
  // `Bound` type at the bridge boundary instead of leaking the synthetic
  // `__tsmbt_infer` name as an opaque external type. Bare `infer X`
  // markers (no bound captured) keep the existing JSValue widening.
  match @checker.infer_marker_bound(type_) {
    Some(bound) => return moonbit_type_name(state, bound)
    None => ()
  }
  match @checker.classify_optional_like_union(type_) {
    Some((collapsed, is_optional)) => {
      let rendered = moonbit_type_name(state, collapsed)
      if is_optional {
        return match collapsed {
          Func(_, _) => "(\{rendered})?"
          _ => rendered + "?"
        }
      }
      return rendered
    }
    None => ()
  }
  match @checker.classify_transparent_intersection(type_) {
    Some(inner) => return moonbit_type_name(state, inner)
    None => ()
  }
  match type_ {
    Literal(_) | NumberLiteral(_) | BigIntLiteral(_) | BooleanLiteral(_) =>
      moonbit_type_name(state, @checker.normalize_literal_type(type_))
    Number => "Double"
    Int => "Int"
    BigInt => "Int64"
    Boolean => "Bool"
    String_ => "String"
    Void => "Unit"
    Array(inner) => "Array[" + moonbit_type_name(state, inner) + "]"
    Tuple(items) => moonbit_tuple_type_name(state, items)
    Func(params, return_type) =>
      moonbit_func_type_name(state, params, return_type)
    // Constructor types fall back to the same callable shape. There is
    // no `new` keyword on MoonBit's side, so the resulting type is the
    // params-to-instance arrow.
    Constructor(params, return_type, _) =>
      moonbit_func_type_name(state, params, return_type)
    Struct(name, _) => {
      mark_referenced_type(state, name)
      moonbit_type_identifier(name, "OpaqueType")
    }
    Named("any") | Named("Function") => {
      state.needs_jsvalue = true
      "JSValue"
    }
    Named("Array") | Named("ReadonlyArray") => {
      state.needs_jsvalue = true
      "Array[JSValue]"
    }
    Applied("Array", [inner]) | Applied("ReadonlyArray", [inner]) =>
      "Array[" + moonbit_type_name(state, inner) + "]"
    Applied("Promise", [inner]) | Applied("PromiseLike", [inner]) => {
      state.needs_promise = true
      "Promise[" + moonbit_type_name(state, inner) + "]"
    }
    TypeOf(_) => {
      state.needs_jsvalue = true
      "JSValue"
    }
    Named(name) if is_local_type_param(state, name) =>
      moonbit_sanitize_type_param_name(name)
    Applied(name, _) if is_local_type_param(state, name) =>
      moonbit_sanitize_type_param_name(name)
    Named(name) if should_widen_unresolved_type_param(state, name) => {
      state.needs_jsvalue = true
      "JSValue"
    }
    Applied(name, _) if should_widen_unresolved_type_param(state, name) => {
      state.needs_jsvalue = true
      "JSValue"
    }
    Named(name) => {
      mark_referenced_type(state, name)
      let rendered = moonbit_type_identifier(name, "OpaqueType")
      // A bare reference to a generic-preserved type fills in `JSValue`
      // for each missing type-parameter slot so the emitted name matches
      // the struct's arity (`Ref` -> `Ref[JSValue]`).
      let arity = generic_preserved_type_arity(state, name)
      if arity > 0 {
        state.needs_jsvalue = true
        let parts : Array[String] = []
        for _ in 0..<arity {
          parts.push("JSValue")
        }
        let joined = parts.join(", ")
        "\{rendered}[\{joined}]"
      } else {
        rendered
      }
    }
    Applied(name, args) => {
      mark_referenced_type(state, name)
      let rendered = moonbit_type_identifier(name, "OpaqueType")
      if state.generic_preserved_type_names.contains(name) {
        let arity = generic_preserved_type_arity(state, name)
        if arity == args.length() && arity > 0 {
          let parts : Array[String] = []
          for arg in args {
            parts.push(moonbit_type_name(state, arg))
          }
          let joined = parts.join(", ")
          "\{rendered}[\{joined}]"
        } else if arity > 0 {
          // Arity mismatch: widen each unfilled slot to `JSValue` so the
          // signature stays syntactically aligned with the struct decl.
          state.needs_jsvalue = true
          let parts : Array[String] = []
          for _ in 0..<arity {
            parts.push("JSValue")
          }
          let joined = parts.join(", ")
          "\{rendered}[\{joined}]"
        } else {
          rendered
        }
      } else {
        rendered
      }
    }
    // Template literal types resolve to a `string` subtype in TypeScript;
    // until enum lowering integrates them, fall back to plain `String`.
    TemplateLiteralType(_, _) => "String"
    // `paramName is T` is a boolean at the bridge boundary; the predicate
    // information survives in the AST for the type-guard helper collector.
    TypePredicate(_, _) => "Bool"
    // `asserts x [is T]` returns void at runtime; predicate-only metadata.
    AssertsPredicate(_, _) => "Unit"
    // `unique symbol` collapses to the runtime `Symbol` representation
    // — the per-occurrence tag is only meaningful inside the checker.
    UniqueSymbol(_) => {
      state.needs_jsvalue = true
      "JSValue"
    }
    // Outside a Tuple element, a bare `Rest(T)` behaves like `Array(T)`.
    Rest(inner) => "Array[" + moonbit_type_name(state, inner) + "]"
    Union(parts) =>
      match inline_union_synthesized_name_from_parts(parts) {
        Some(name) => name
        None =>
          if moonbit_string_params_subset_union(state, parts) {
            "String"
          } else {
            state.needs_jsvalue = true
            "JSValue"
          }
      }
    _ => {
      state.needs_jsvalue = true
      "JSValue"
    }
  }
}

///|
/// Decl-surface mirror of the bridge FFI string-subset policy: a
/// two-member union pairing `string` with a `*Params` option bag that is
/// not a declared type on this surface (zod's pervasive
/// `params?: string | core.$ZodEmailParams`) types the boundary as
/// `String`. The structured object form stays reachable via `unsafeCast`;
/// declared bags keep their real lowering.
fn moonbit_string_params_subset_union(
  state : MoonBitDeclState,
  parts : Array[@ast.TsType],
) -> Bool {
  if parts.length() != 2 {
    return false
  }
  let named = match (parts[0], parts[1]) {
    (String_, Named(n)) | (Named(n), String_) => n
    (String_, Applied(n, _)) | (Applied(n, _), String_) => n
    _ => return false
  }
  if !named.has_suffix("Params") {
    return false
  }
  if state.declared_type_names.contains(named) ||
    state.generic_preserved_type_names.contains(named) ||
    is_local_type_param(state, named) {
    return false
  }
  true
}

///|
fn moonbit_type_alias_target_is_simple(type_ : @ast.TsType) -> Bool {
  match @checker.classify_optional_like_union(type_) {
    Some((collapsed, _)) =>
      return moonbit_type_alias_target_is_simple(collapsed)
    None => ()
  }
  match @checker.classify_transparent_intersection(type_) {
    Some(inner) => return moonbit_type_alias_target_is_simple(inner)
    None => ()
  }
  match type_ {
    Literal(_) | NumberLiteral(_) | BigIntLiteral(_) | BooleanLiteral(_) => true
    Number | Int | BigInt | Boolean | String_ | Void => true
    Named(_) => true
    Array(inner) => moonbit_type_alias_target_is_simple(inner)
    Tuple(items) => {
      if items.length() == 0 {
        return true
      }
      for item in items {
        if item != items[0] || !moonbit_type_alias_target_is_simple(item) {
          return false
        }
      }
      true
    }
    Func(params, return_type) => {
      for param in params {
        if !moonbit_type_alias_target_is_simple(param) {
          return false
        }
      }
      moonbit_type_alias_target_is_simple(return_type)
    }
    Applied("Array", [inner]) | Applied("ReadonlyArray", [inner]) =>
      moonbit_type_alias_target_is_simple(inner)
    Applied("Promise", [inner]) | Applied("PromiseLike", [inner]) =>
      moonbit_type_alias_target_is_simple(inner)
    Applied(name, args) => {
      if name == "any" || name == "Function" {
        return false
      }
      for arg in args {
        if !moonbit_type_alias_target_is_simple(arg) {
          return false
        }
      }
      true
    }
    _ => false
  }
}

///|
fn type_alias_decl_to_moonbit(
  state : MoonBitDeclState,
  type_alias : @ast.TsTypeAlias,
) -> String? {
  if type_alias.type_params.length() > 0 ||
    !moonbit_type_alias_target_is_simple(type_alias.type_) {
    return None
  }
  let type_name = moonbit_type_identifier(type_alias.name, "AliasType")
  let target_type = moonbit_type_name(state, type_alias.type_)
  if target_type.contains("JSValue") {
    None
  } else {
    Some("///|\npub type \{type_name} = \{target_type}")
  }
}

///|
/// Constructor-name slot used by the inline union synthesiser. Mirrors the
/// FFI-side discriminator in `bridge/tagged_union_lowering.mbt` so the two
/// emission paths agree on the synthetic alias name without sharing state.
/// Only types the FFI-side lowering can actually represent are recognised;
/// any other shape returns `None` and the union widens back to JSValue.
fn inline_union_constructor_name_for_part(t : @ast.TsType) -> String? {
  match t {
    @ast.TsType::Number => Some("NumberValue")
    @ast.TsType::Int => Some("IntValue")
    @ast.TsType::String_ => Some("StringValue")
    @ast.TsType::Boolean => Some("BoolValue")
    @ast.TsType::BigInt => Some("BigIntValue")
    @ast.TsType::Array(@ast.TsType::Number) => Some("NumberArray")
    @ast.TsType::Array(@ast.TsType::Int) => Some("IntArray")
    @ast.TsType::Array(@ast.TsType::String_) => Some("StringArray")
    @ast.TsType::Array(@ast.TsType::Boolean) => Some("BoolArray")
    @ast.TsType::Array(@ast.TsType::Named(name)) =>
      inline_union_named_constructor_name(name + "Array")
    @ast.TsType::Named(name) => inline_union_named_constructor_name(name)
    @ast.TsType::Literal(value) =>
      inline_union_literal_string_constructor(value)
    @ast.TsType::NumberLiteral(value) =>
      inline_union_literal_numeric_constructor("Lit", value)
    @ast.TsType::BigIntLiteral(value) =>
      inline_union_literal_numeric_constructor("LitBigInt", value)
    @ast.TsType::BooleanLiteral(true) => Some("TrueValue")
    @ast.TsType::BooleanLiteral(false) => Some("FalseValue")
    _ => None
  }
}

///|
fn inline_union_literal_string_constructor(value : String) -> String? {
  if value == "" {
    return None
  }
  let mut out = ""
  let mut next_upper = true
  for c in value {
    if (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') {
      let ch = if next_upper && c >= 'a' && c <= 'z' {
        (c.to_int() - 32).unsafe_to_char()
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
fn inline_union_literal_numeric_constructor(
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
fn inline_union_named_constructor_name(name : String) -> String? {
  if name == "" {
    return None
  }
  let first = name[0].unsafe_to_char()
  if first < 'A' || first > 'Z' {
    return None
  }
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
fn inline_union_member_is_literal_like(t : @ast.TsType) -> Bool {
  match t {
    @ast.TsType::Literal(_) => true
    @ast.TsType::NumberLiteral(_) => true
    @ast.TsType::BigIntLiteral(_) => true
    @ast.TsType::BooleanLiteral(_) => true
    _ => false
  }
}

///|
/// Compute the synthetic alias name for an inline `A | B [| C ...]` shape,
/// matching the FFI-side lowering exactly. Returns `None` when any member
/// lacks a runtime discriminator, when the union is pure literals (those go
/// through the literal-union enum lowering), or when a literal's primitive
/// type collides with a non-literal sibling — those cases keep the existing
/// JSValue widening.
fn inline_union_synthesized_name_from_parts(
  parts : Array[@ast.TsType],
) -> String? {
  if parts.length() < 2 {
    return None
  }
  let names : Array[String] = []
  let mut has_non_literal = false
  for entry in parts {
    if !inline_union_member_is_literal_like(entry) {
      has_non_literal = true
    }
    let name = match inline_union_constructor_name_for_part(entry) {
      Some(n) => n
      None => return None
    }
    if names.contains(name) {
      return None
    }
    names.push(name)
  }
  if !has_non_literal {
    return None
  }
  if inline_union_has_primitive_overlap(parts) {
    return None
  }
  // Sort with the standard shortlex order (the MoonBit `String::compare`
  // ranks shorter strings ahead of longer ones, then breaks ties on code
  // units). This is deterministic and identical to the FFI-side sort so
  // both emission paths agree on the synthetic alias name.
  names.sort()
  Some("Auto_" + names.join("_or_"))
}

///|
fn inline_union_member_primitive_kind(t : @ast.TsType) -> String? {
  match t {
    @ast.TsType::String_ => Some("string")
    @ast.TsType::Number | @ast.TsType::Int => Some("number")
    @ast.TsType::Boolean => Some("boolean")
    @ast.TsType::BigInt => Some("bigint")
    _ => None
  }
}

///|
fn inline_union_literal_primitive_kind(t : @ast.TsType) -> String? {
  match t {
    @ast.TsType::Literal(_) => Some("string")
    @ast.TsType::NumberLiteral(_) => Some("number")
    @ast.TsType::BooleanLiteral(_) => Some("boolean")
    @ast.TsType::BigIntLiteral(_) => Some("bigint")
    _ => None
  }
}

///|
fn inline_union_has_primitive_overlap(parts : Array[@ast.TsType]) -> Bool {
  let primitive_kinds : Array[String] = []
  for m in parts {
    match inline_union_member_primitive_kind(m) {
      Some(k) => if !primitive_kinds.contains(k) { primitive_kinds.push(k) }
      None => ()
    }
  }
  for m in parts {
    match inline_union_literal_primitive_kind(m) {
      Some(k) => if primitive_kinds.contains(k) { return true }
      None => ()
    }
  }
  false
}

///|
fn moonbit_function_field_type_name(
  state : MoonBitDeclState,
  type_ : @ast.TsType,
) -> String {
  match @checker.classify_optional_like_union(type_) {
    Some((collapsed, is_optional)) => {
      let rendered = moonbit_function_field_type_name(state, collapsed)
      if is_optional {
        return match collapsed {
          Func(_, _) => "(\{rendered})?"
          _ => rendered + "?"
        }
      }
      return rendered
    }
    None => ()
  }
  match type_ {
    Func(params, return_type) =>
      moonbit_func_type_name(state, params, return_type)
    _ => moonbit_type_name(state, type_)
  }
}

///|
fn moonbit_function_type_parts(
  state : MoonBitDeclState,
  type_ : @ast.TsType,
) -> (Array[String], String)? {
  match type_ {
    Func(params, return_type) => {
      let param_types : Array[String] = []
      for param in params {
        param_types.push(moonbit_type_name(state, param))
      }
      // Mirror of `moonbit_func_type_name` on the return position.
      Some(
        (
          param_types,
          moonbit_type_name(
            state,
            @checker.normalize_promise_like_union_return(return_type),
          ),
        ),
      )
    }
    _ => None
  }
}

///|
fn interface_function_field_method_decl(
  state : MoonBitDeclState,
  receiver_type : String,
  receiver_type_params : Array[String],
  field_name : String,
  field_type : @ast.TsType,
) -> String? {
  match moonbit_function_type_parts(state, field_type) {
    Some((param_types, raw_return)) => {
      let self_type = moonbit_receiver_self_type(
        receiver_type, receiver_type_params,
      )
      // TypeScript `this` builder return -> owning receiver.
      let return_type = match raw_return {
        "This" => self_type
        "This?" => self_type + "?"
        _ => raw_return
      }
      let params : Array[String] = []
      for i, param_type in param_types {
        let arg_name = "arg" + i.to_string()
        // Mirror of the ffi side: async-callback params surface as
        // MoonBit async fns on the public method.
        let public_type = match moonbit_async_callback_lowering(param_type) {
          Some(lowering) => lowering.lowered_type
          None => param_type
        }
        params.push("\{arg_name} : \{public_type}")
      }
      let params_src = if params.length() == 0 {
        "self : \{self_type}"
      } else {
        "self : \{self_type}, " + params.join(", ")
      }
      let fn_prefix = moonbit_function_type_param_prefix(receiver_type_params)
      Some(
        "///|\ndeclare pub \{fn_prefix} \{receiver_type}::\{field_name}(\{params_src}) -> \{return_type}",
      )
    }
    None => None
  }
}

///|
fn moonbit_replace_this_in_function_return(
  type_ : @ast.TsType,
  owner_name : String,
) -> @ast.TsType {
  match type_ {
    @ast.TsType::Func(params, return_type) => {
      let new_return = match return_type {
        // Parser stores TypeScript `this` as `Named("this")` (lowercase);
        // some downstream paths sanitize to `Named("This")`. Match both.
        @ast.TsType::Named(n) if n == "this" || n == "This" =>
          @ast.TsType::Named(owner_name)
        _ => return_type
      }
      @ast.TsType::Func(params, new_return)
    }
    _ => type_
  }
}

///|
fn interface_decl_to_moonbit(
  state : MoonBitDeclState,
  iface : @ast.TsInterface,
) -> String {
  // Keep the full type-param list. The decl emitter only produces
  // `declare pub type Foo[T]` opaque forms (no struct body), so unused
  // type parameters don't trigger MoonBit's `unused_type_variable`
  // warning the way they would on a `pub(all) struct Foo[T] {...}`.
  //
  // Gate on whether this iface was registered as generic-preserved
  // (a class/iface name overlap leaves the iface unregistered so it
  // matches the class's bare `declare pub type ClassName`).
  let active_type_params = if state.generic_preserved_type_names.contains(
      iface.name,
    ) {
    iface.type_params
  } else {
    []
  }
  let local_type_param_len = push_local_type_params(state, active_type_params)
  let lines : Array[String] = ["///|", "/// TS interface \{iface.name}"]
  let method_decls : Array[String] = []
  let seen_method_names : Array[String] = []
  let mut method_wrapper_count = 0
  let type_name = moonbit_type_identifier(iface.name, "OpaqueType")
  for field in iface.fields {
    let (name, raw_type) = field
    // `@internal` members never surface (tsc's stripInternal hides them
    // from declaration consumers). `@deprecated` members stay only while
    // they type naturally — one that could only widen to `JSValue` is
    // dropped rather than kept as a fallback slot.
    if iface.internal_members.contains(name) {
      continue
    }
    // Replace TypeScript builder `this` return with the owning interface.
    let type_ = moonbit_replace_this_in_function_return(raw_type, iface.name)
    let moonbit_type = moonbit_function_field_type_name(state, type_)
    if iface.deprecated_members.contains(name) &&
      moonbit_type.contains("JSValue") {
      continue
    }
    if iface.readonly_fields.contains(name) {
      lines.push("/// readonly \{name} : \{moonbit_type}")
    } else {
      lines.push("/// \{name} : \{moonbit_type}")
    }
    let method_name = sanitize_value_identifier(name, "field")
    if method_wrapper_count < moonbit_function_field_method_wrapper_limit &&
      !seen_method_names.contains(method_name) {
      match
        interface_function_field_method_decl(
          state, type_name, active_type_params, method_name, type_,
        ) {
        Some(method_decl) => {
          seen_method_names.push(method_name)
          method_decls.push(method_decl)
          method_wrapper_count += 1
        }
        None => ()
      }
    }
  }
  lines.push(
    "declare pub type \{type_name}\{moonbit_type_param_suffix(active_type_params)}",
  )
  // Upcast helpers along the `extends` chain — mirror of the ffi side
  // (`ffi_struct_decl_to_moonbit`): sound %identity views replacing the
  // unsafeCast that TypeScript's implicit interface subtyping used to
  // force at every base-surface call.
  let upcast_fn_prefix = moonbit_function_type_param_prefix(active_type_params)
  let upcast_self_type = type_name +
    moonbit_type_param_suffix(active_type_params)
  let seen_upcasts : Array[String] = []
  for i, base_name in iface.extends_names {
    let base_args = if i < iface.extends_args.length() {
      iface.extends_args[i]
    } else {
      []
    }
    // Clamp to the EMITTED base arity — mirror of the ffi side (extra
    // or missing source args degrade to JSValue slots).
    let emitted_arity = generic_preserved_type_arity(state, base_name)
    let base_type : @ast.TsType = if emitted_arity == 0 {
      Named(base_name)
    } else if base_args.length() == emitted_arity {
      Applied(base_name, base_args)
    } else {
      let widened : Array[@ast.TsType] = []
      for _ in 0..<emitted_arity {
        widened.push(Any)
      }
      Applied(base_name, widened)
    }
    let rendered = moonbit_type_name(state, base_type)
    match moonbit_upcast_helper_name(rendered) {
      Some(helper_name) =>
        if !seen_upcasts.contains(helper_name) &&
          !seen_method_names.contains(helper_name) {
          seen_upcasts.push(helper_name)
          method_decls.push(
            "///|\ndeclare pub \{upcast_fn_prefix} \{type_name}::\{helper_name}(self : \{upcast_self_type}) -> \{rendered}",
          )
        }
      None => ()
    }
  }
  restore_local_type_params(state, local_type_param_len)
  if method_decls.length() == 0 {
    lines.join("\n")
  } else {
    lines.join("\n") + "\n\n" + method_decls.join("\n\n")
  }
}

///|
fn import_decl_to_moonbit(
  state : MoonBitDeclState,
  import_ : @ast.TsImport,
) -> String {
  let params : Array[String] = []
  for item in import_.params {
    let (name, type_) = item
    let param_name = sanitize_value_identifier(name, "arg")
    let param_type = moonbit_type_name(state, type_)
    params.push("\{param_name} : \{param_type}")
  }
  let return_type = moonbit_type_name(state, import_.return_type)
  let fn_name = sanitize_value_identifier(import_.name, "generated_fn")
  let params_str = params.join(", ")
  "///|\ndeclare pub fn \{fn_name}(\{params_str}) -> \{return_type}"
}

///|
fn value_decl_to_moonbit(
  state : MoonBitDeclState,
  value : @ast.TsValueDecl,
) -> String {
  let return_type = moonbit_type_name(state, value.type_)
  let fn_name = "get_" + to_snake_case(value.name)
  "///|\ndeclare pub fn \{fn_name}() -> \{return_type}"
}

///|
fn func_decl_to_moonbit(state : MoonBitDeclState, func : @ast.TsFunc) -> String {
  let params : Array[String] = []
  let mut next_index = 0
  for param in func.params {
    let param_name = if param.name == "" {
      let generated = "arg" + next_index.to_string()
      next_index += 1
      generated
    } else {
      param.name
    }
    let safe_name = sanitize_value_identifier(param_name, "arg")
    let param_type = moonbit_type_name(state, param.type_)
    params.push("\{safe_name} : \{param_type}")
  }
  let return_type = moonbit_type_name(state, func.return_type)
  let fn_name = sanitize_value_identifier(func.name, "generated_fn")
  let params_str = params.join(", ")
  "///|\ndeclare pub fn \{fn_name}(\{params_str}) -> \{return_type}"
}

///|
fn to_lower_ascii(c : Char) -> Char {
  if c >= 'A' && c <= 'Z' {
    (c.to_int() + 32).unsafe_to_char()
  } else {
    c
  }
}

///|
fn trim_underscores(name : String) -> String {
  let mut start = 0
  let mut end_ = name.length()
  while start < end_ && name[start].unsafe_to_char() == '_' {
    start += 1
  }
  while end_ > start && name[end_ - 1].unsafe_to_char() == '_' {
    end_ -= 1
  }
  name[start:end_].to_owned()
}

///|
fn to_snake_case(name : String) -> String {
  let mut result = ""
  let mut prev_is_lower_or_digit = false
  for c in name {
    if c >= 'A' && c <= 'Z' {
      if result != "" && prev_is_lower_or_digit {
        result += "_"
      }
      result += to_lower_ascii(c).to_string()
      prev_is_lower_or_digit = false
    } else if is_ascii_letter(c) || is_ascii_digit(c) {
      result += c.to_string()
      prev_is_lower_or_digit = (c >= 'a' && c <= 'z') || is_ascii_digit(c)
    } else {
      if result != "" && !result.has_suffix("_") {
        result += "_"
      }
      prev_is_lower_or_digit = false
    }
  }
  sanitize_identifier(trim_underscores(result), "generated_name")
}

///|
/// Whether to keep a class's TypeScript type parameters when emitting MoonBit
/// declarations. Mirrors `ffi_should_preserve_class_type_params` in
/// `src/bridge/moonbit_js_ffi.mbt` so the FFI and decl sides agree on which
/// classes emit `Foo[T, U]` vs bare `Foo`.
fn moonbit_should_preserve_class_type_params(class_ : @ast.TsClassDecl) -> Bool {
  class_.type_params.length() > 0
}

///|
fn class_decl_to_moonbit_sections(
  state : MoonBitDeclState,
  class_ : @ast.TsClassDecl,
) -> Array[String] {
  let sections : Array[String] = []
  let seen_binding_names : Array[String] = []
  let type_name = moonbit_type_identifier(class_.name, "OpaqueType")
  let active_type_params = if moonbit_should_preserve_class_type_params(class_) {
    class_.type_params
  } else {
    []
  }
  let local_type_param_len = push_local_type_params(state, active_type_params)
  let type_param_suffix = moonbit_type_param_suffix(active_type_params)
  let receiver_type = type_name + type_param_suffix
  let fn_type_param_prefix = moonbit_function_type_param_prefix(
    active_type_params,
  )
  sections.push(
    "///|\n/// TS class \{class_.name}\ndeclare pub type \{type_name}\{type_param_suffix}",
  )
  if class_.is_constructible {
    let params : Array[String] = []
    match class_.constructor_params {
      Some(constructor_params) =>
        for param in constructor_params {
          let (param_name, param_type) = param
          let safe_name = sanitize_value_identifier(param_name, "arg")
          let safe_type = moonbit_type_name(state, param_type)
          params.push("\{safe_name} : \{safe_type}")
        }
      None => ()
    }
    let ctor_params = params.join(", ")
    let ctor_name = to_snake_case(class_.name)
    push_unique_decl_section(
      seen_binding_names,
      sections,
      "new_\{ctor_name}",
      "///|\ndeclare pub \{fn_type_param_prefix} new_\{ctor_name}(\{ctor_params}) -> \{receiver_type}",
    )
  }
  for class_property in class_.properties {
    // Static getters/setters belong to the class itself, not an
    // instance, so they don't capture the class's instance-level type
    // parameters. Mirrors the FFI side's same gating in
    // `ffi_class_property_getter_decl_to_moonbit`.
    let property_fn_prefix = if class_property.is_static {
      "fn"
    } else {
      fn_type_param_prefix
    }
    let getter_name = "get_" +
      to_snake_case(class_.name) +
      "_" +
      to_snake_case(class_property.name)
    // Instance accessors live under the type on the FFI side
    // (`FlagMachine::get_flag_machine_mode`); mirror that here so the
    // advertised `.mbti` surface matches what `bridge.mbt` implements.
    let getter_decl_name = if class_property.is_static {
      getter_name
    } else {
      "\{type_name}::\{getter_name}"
    }
    let getter_params : Array[String] = []
    if !class_property.is_static {
      getter_params.push("self : \{receiver_type}")
    }
    let getter_params_str = getter_params.join(", ")
    let getter_type = moonbit_type_name(state, class_property.type_)
    push_unique_decl_section(
      seen_binding_names,
      sections,
      getter_decl_name,
      "///|\ndeclare pub \{property_fn_prefix} \{getter_decl_name}(\{getter_params_str}) -> \{getter_type}",
    )
    if !class_property.is_readonly {
      let setter_name = "set_" +
        to_snake_case(class_.name) +
        "_" +
        to_snake_case(class_property.name)
      let setter_decl_name = if class_property.is_static {
        setter_name
      } else {
        "\{type_name}::\{setter_name}"
      }
      let setter_params : Array[String] = []
      if !class_property.is_static {
        setter_params.push("self : \{receiver_type}")
      }
      setter_params.push("value : \{getter_type}")
      let setter_params_str = setter_params.join(", ")
      push_unique_decl_section(
        seen_binding_names,
        sections,
        setter_decl_name,
        "///|\ndeclare pub \{property_fn_prefix} \{setter_decl_name}(\{setter_params_str}) -> Unit",
      )
    }
  }
  for class_method in class_.methods {
    let params : Array[String] = []
    if !class_method.is_static {
      params.push("self : \{receiver_type}")
    }
    let method_extra_type_params : Array[String] = []
    for tp in class_method.type_params {
      if !active_type_params.contains(tp) &&
        !method_extra_type_params.contains(tp) {
        method_extra_type_params.push(tp)
      }
    }
    let method_local_len = push_local_type_params(
      state, method_extra_type_params,
    )
    for param in class_method.params {
      let (param_name, param_type) = param
      let safe_name = sanitize_value_identifier(param_name, "arg")
      let safe_type = moonbit_type_name(state, param_type)
      // Mirror of the ffi side: async-callback params surface as
      // MoonBit async fns on the public method.
      let public_type = match moonbit_async_callback_lowering(safe_type) {
        Some(lowering) => lowering.lowered_type
        None => safe_type
      }
      params.push("\{safe_name} : \{public_type}")
    }
    let raw_return = moonbit_type_name(state, class_method.return_type)
    let return_type = match raw_return {
      "This" => receiver_type
      "This?" => receiver_type + "?"
      _ => raw_return
    }
    // Instance methods live under the type on the FFI side
    // (`Hono::get`, reserved words suffixed like `match_`); statics stay
    // top-level `<class>_<method>` functions — mirror both here.
    let fn_name = if class_method.is_static {
      "\{to_snake_case(class_.name)}_\{to_snake_case(class_method.name)}"
    } else {
      let mut method_name = to_snake_case(class_method.name)
      if value_identifier_needs_suffix(method_name) {
        method_name += "_"
      }
      "\{type_name}::\{method_name}"
    }
    let method_params = params.join(", ")
    // Static methods skip the class-level type-params (they don't have
    // a `self`, so the class generics aren't in scope for the body).
    // Mirrors the FFI side's gating in `ffi_class_method_decl_to_moonbit`.
    let combined_type_params : Array[String] = []
    if !class_method.is_static {
      for tp in active_type_params {
        combined_type_params.push(tp)
      }
    }
    for tp in method_extra_type_params {
      combined_type_params.push(tp)
    }
    let method_type_param_prefix = moonbit_function_type_param_prefix(
      combined_type_params,
    )
    push_unique_decl_section(
      seen_binding_names,
      sections,
      fn_name,
      "///|\ndeclare pub \{method_type_param_prefix} \{fn_name}(\{method_params}) -> \{return_type}",
    )
    restore_local_type_params(state, method_local_len)
  }
  restore_local_type_params(state, local_type_param_len)
  sections
}

///|
fn enum_decl_to_moonbit(enum_ : @ast.TsEnumDecl) -> String {
  let type_name = moonbit_type_identifier(enum_.name, "GeneratedEnum")
  let lines : Array[String] = [
    "///|",
    "/// TS enum \{enum_.name}",
    "pub(all) enum \{type_name} {",
  ]
  let seen_cases : Array[String] = []
  for i, enum_member in enum_.members {
    let base_name = moonbit_type_identifier(enum_member.name, "Member")
    let mut case_name = base_name
    let mut suffix = 2
    while seen_cases.contains(case_name) {
      case_name = base_name + suffix.to_string()
      suffix += 1
    }
    seen_cases.push(case_name)
    if case_name == "" {
      lines.push("  Member" + i.to_string())
    } else {
      lines.push("  " + case_name)
    }
  }
  lines.push("}")
  lines.join("\n")
}

///|
pub fn emit_moonbit_decl_with_sections(
  module_ : @ast.TsModule,
  extra_sections : Array[String],
  force_jsvalue : Bool,
) -> String {
  emit_moonbit_decl_with_sections_and_types(
    module_,
    extra_sections,
    [],
    force_jsvalue,
  )
}

///|
pub fn emit_moonbit_decl_with_sections_and_types(
  module_ : @ast.TsModule,
  extra_sections : Array[String],
  extra_declared_type_names : Array[String],
  force_jsvalue : Bool,
) -> String {
  emit_moonbit_decl_with_sections_types_and_arities(
    module_,
    extra_sections,
    extra_declared_type_names,
    {},
    force_jsvalue,
  )
}

///|
/// Variant that also accepts an `extra_generic_arities` map so the
/// caller can register arities for cross-module types — typically
/// interfaces / classes declared in a different file but referenced
/// from this module's exported function / value signatures. Without
/// this, references like `(task : Test)` get rendered as bare
/// `Test` even when the actual decl elsewhere is `pub type
/// Test[ExtraContext]`, causing `[4040]` arity-mismatch on consumers.
pub fn emit_moonbit_decl_with_sections_types_and_arities(
  module_ : @ast.TsModule,
  extra_sections : Array[String],
  extra_declared_type_names : Array[String],
  extra_generic_arities : Map[String, Int],
  force_jsvalue : Bool,
) -> String {
  let declared_type_names : Array[String] = []
  let generic_preserved_type_names : Array[String] = []
  let generic_preserved_type_arity_by_name : Map[String, Int] = {}
  // When a class and an interface share a name (TS declaration merging) the
  // class drives the emitted shape: `class_decl_to_moonbit_sections` emits
  // `declare pub type ClassName[T, U]` with the class's type-params, and the
  // interface emission is skipped below. Pre-collect class names + their
  // arities so interface registration aligns with the class.
  let class_decl_names : Array[String] = []
  let class_arity_by_name : Map[String, Int] = {}
  for class_ in module_.classes {
    class_decl_names.push(class_.name)
    if moonbit_should_preserve_class_type_params(class_) {
      class_arity_by_name[class_.name] = class_.type_params.length()
    }
  }
  for iface in module_.interfaces {
    declared_type_names.push(iface.name)
    if class_decl_names.contains(iface.name) {
      // The class drives the shape. If the class itself preserves type
      // params, register that arity under the shared name.
      match class_arity_by_name.get(iface.name) {
        Some(arity) => {
          if !generic_preserved_type_names.contains(iface.name) {
            generic_preserved_type_names.push(iface.name)
          }
          generic_preserved_type_arity_by_name[iface.name] = arity
        }
        None => ()
      }
    } else if moonbit_should_preserve_interface_type_params(iface) &&
      iface.type_params.length() > 0 {
      // `interface_decl_to_moonbit` emits `declare pub type Foo[T, U]`
      // with the full type-param list, so call sites must propagate the
      // matching arity instead of widening to bare `Foo`.
      generic_preserved_type_names.push(iface.name)
      generic_preserved_type_arity_by_name[iface.name] = iface.type_params.length()
    }
  }
  for class_ in module_.classes {
    declared_type_names.push(class_.name)
    if moonbit_should_preserve_class_type_params(class_) &&
      !generic_preserved_type_names.contains(class_.name) {
      generic_preserved_type_names.push(class_.name)
      generic_preserved_type_arity_by_name[class_.name] = class_.type_params.length()
    }
  }
  for enum_ in module_.enums {
    declared_type_names.push(enum_.name)
  }
  let emitted_type_aliases : Array[@ast.TsTypeAlias] = []
  for type_alias in module_.type_aliases {
    if type_alias.type_params.length() == 0 &&
      moonbit_type_alias_target_is_simple(type_alias.type_) {
      emitted_type_aliases.push(type_alias)
    }
  }
  for name in extra_declared_type_names {
    if !declared_type_names.contains(name) {
      declared_type_names.push(name)
    }
  }
  for entry in extra_generic_arities {
    let (name, arity) = entry
    if !generic_preserved_type_names.contains(name) {
      generic_preserved_type_names.push(name)
    }
    match generic_preserved_type_arity_by_name.get(name) {
      Some(_) => ()
      None => generic_preserved_type_arity_by_name[name] = arity
    }
  }
  let state : MoonBitDeclState = {
    declared_type_names,
    referenced_type_names: [],
    local_type_param_names: [],
    generic_preserved_type_names,
    generic_preserved_type_arity_by_name,
    needs_jsvalue: false,
    needs_promise: false,
  }
  let interface_sections : Array[String] = []
  let seen_type_decl_names : Array[String] = []
  let enum_sections : Array[String] = []
  for enum_ in module_.enums {
    let type_name = moonbit_type_identifier(enum_.name, "GeneratedEnum")
    if !seen_type_decl_names.contains(type_name) {
      seen_type_decl_names.push(type_name)
      enum_sections.push(enum_decl_to_moonbit(enum_))
    }
  }
  for iface in module_.interfaces {
    let type_name = moonbit_type_identifier(iface.name, "OpaqueType")
    if !seen_type_decl_names.contains(type_name) {
      seen_type_decl_names.push(type_name)
      interface_sections.push(interface_decl_to_moonbit(state, iface))
    }
  }
  let class_sections : Array[String] = []
  for class_ in module_.classes {
    let type_name = moonbit_type_identifier(class_.name, "OpaqueType")
    for i, section in class_decl_to_moonbit_sections(state, class_) {
      if i == 0 {
        if seen_type_decl_names.contains(type_name) {
          continue
        }
        seen_type_decl_names.push(type_name)
      }
      class_sections.push(section)
    }
  }
  let type_alias_sections : Array[String] = []
  for type_alias in emitted_type_aliases {
    let type_name = moonbit_type_identifier(type_alias.name, "AliasType")
    if !seen_type_decl_names.contains(type_name) {
      match type_alias_decl_to_moonbit(state, type_alias) {
        Some(section) => {
          seen_type_decl_names.push(type_name)
          type_alias_sections.push(section)
        }
        None => ()
      }
    }
  }
  let import_sections : Array[String] = []
  let seen_import_binding_names : Array[String] = []
  for import_ in module_.imports {
    let fn_name = sanitize_value_identifier(import_.name, "generated_fn")
    push_unique_decl_section(
      seen_import_binding_names,
      import_sections,
      fn_name,
      import_decl_to_moonbit(state, import_),
    )
  }
  let sections : Array[String] = [
    "///|\n/// AUTO-GENERATED by `ts2mbt` (mizchi/ts). DO NOT EDIT -- your changes\n/// will be lost on the next `ts2mbt generate` / `ts2mbt vendor`.\n/// Complex or unsupported TypeScript types are widened to JSValue.",
  ]
  let value_sections : Array[String] = []
  let seen_value_binding_names : Array[String] = []
  for value in module_.values {
    let fn_name = "get_" + to_snake_case(value.name)
    push_unique_decl_section(
      seen_value_binding_names,
      value_sections,
      fn_name,
      value_decl_to_moonbit(state, value),
    )
  }
  let func_sections : Array[String] = []
  let seen_func_binding_names : Array[String] = []
  for func in module_.funcs {
    let fn_name = sanitize_value_identifier(func.name, "generated_fn")
    push_unique_decl_section(
      seen_func_binding_names,
      func_sections,
      fn_name,
      func_decl_to_moonbit(state, func),
    )
  }
  let referenced : Array[String] = []
  for name in state.referenced_type_names {
    let type_name = moonbit_type_identifier(name, "OpaqueType")
    if !seen_type_decl_names.contains(type_name) &&
      !referenced.contains(type_name) {
      referenced.push(type_name)
    }
  }
  referenced.sort()
  if state.needs_jsvalue || force_jsvalue {
    sections.push("///|\ndeclare pub type JSValue")
  }
  if state.needs_promise {
    sections.push("///|\ndeclare pub type Promise[X]")
  }
  for section in extra_sections {
    sections.push(section)
  }
  for section in enum_sections {
    sections.push(section)
  }
  for section in interface_sections {
    sections.push(section)
  }
  for section in class_sections {
    sections.push(section)
  }
  for section in type_alias_sections {
    sections.push(section)
  }
  for name in referenced {
    sections.push("///|\ndeclare pub type \{name}")
  }
  for section in value_sections {
    sections.push(section)
  }
  for section in func_sections {
    sections.push(section)
  }
  for section in import_sections {
    sections.push(section)
  }
  sections.join("\n\n")
}

///|
pub fn emit_moonbit_decl(module_ : @ast.TsModule) -> String {
  emit_moonbit_decl_with_sections(module_, [], false)
}

///|
pub fn emit_moonbit_decl_from_source(
  source : String,
) -> String raise ParseError {
  let parser = Parser::from_source(source)
  let module_ = parser.parse_module()
  emit_moonbit_decl(module_)
}
