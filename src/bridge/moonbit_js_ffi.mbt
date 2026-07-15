///|
pub struct MoonBitJsFfiBundle {
  ffi_mbt : String
  bridge_js : String
} derive(Debug)

///|
priv struct MoonBitBridgeImport {
  imported_name : String
  local_name : String
  is_default : Bool
  is_namespace : Bool
}

///|
priv struct FfiAliasConstructor {
  fn_name : String
  binding_name : String
  params_src : String
  bridge_params : Array[String]
  bridge_expr : String
}

///|
priv struct MoonBitJsFfiState {
  declared_type_names : Array[String]
  struct_type_names : Array[String]
  generic_type_params_by_name : Map[String, Array[String]]
  enums : Array[@ast.TsEnumDecl]
  external_type_names : Array[String]
  local_type_param_names : Array[String]
  function_field_method_wrapper_limit : Int
  tagged_union_decls_by_name : Map[String, BridgeTaggedUnionDecl]
  // Inline `A | B` unions encountered while lowering parameter / return /
  // field types are auto-synthesized into PascalCase tagged-union aliases
  // and stashed here so a later emission pass can append both the enum
  // declaration and the bridge.js converter pair. Keyed by synthetic name
  // for stable dedup across all lowering call sites.
  synthesized_inline_unions : Map[String, BridgeTaggedUnionDecl]
  // `JSValue` / `Promise[X]` are emitted as self-contained `#external`
  // types so the generated bridge package has no `mizchi/js` dependency.
  // Track whether either appeared in the lowered output so the emission
  // pass can decide whether to write the corresponding extern declaration.
  mut needs_js_any : Bool
  mut needs_promise : Bool
}

///|
let ffi_function_field_method_wrapper_limit : Int = 8

///|
fn ffi_is_ascii_letter(c : Char) -> Bool {
  (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
}

///|
fn ffi_is_ascii_digit(c : Char) -> Bool {
  c >= '0' && c <= '9'
}

///|
fn ffi_to_lower_ascii(c : Char) -> Char {
  if c >= 'A' && c <= 'Z' {
    (c.to_int() + 32).unsafe_to_char()
  } else {
    c
  }
}

///|
fn ffi_to_upper_ascii(c : Char) -> Char {
  if c >= 'a' && c <= 'z' {
    (c.to_int() - 32).unsafe_to_char()
  } else {
    c
  }
}

///|
fn ffi_sanitize_identifier_chars(name : String, fallback : String) -> String {
  let mut result = ""
  for c in name {
    if ffi_is_ascii_letter(c) || ffi_is_ascii_digit(c) || c == '_' {
      result += c.to_string()
    } else {
      result += "_"
    }
  }
  if result == "" {
    result = fallback
  }
  let first = result[0].unsafe_to_char()
  if ffi_is_ascii_digit(first) {
    result = "_" + result
  }
  result
}

///|
fn ffi_is_all_underscores(name : String) -> Bool {
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
fn ffi_value_identifier_needs_suffix(name : String) -> Bool {
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
    | "if"
    | "include"
    | "import"
    | "in"
    | "interface"
    | "is"
    | "guard"
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
    | "constructor"
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
    | "typeof"
    | "type"
    | "typealias"
    | "using"
    | "use"
    | "var"
    | "void"
    | "with"
    | "while" => true
    _ => false
  }
}

///|
fn ffi_lower_leading_ascii(name : String) -> String {
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
fn ffi_sanitize_identifier(name : String, fallback : String) -> String {
  let mut result = ffi_lower_leading_ascii(
    ffi_sanitize_identifier_chars(name, fallback),
  )
  if ffi_is_all_underscores(result) {
    result = fallback
  }
  if ffi_value_identifier_needs_suffix(result) {
    result += "_"
  }
  result
}

///|
fn ffi_trim_underscores(name : String) -> String {
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
fn ffi_ambiguous_export_message(export_ : ResolvedExport) -> String {
  let base = "Unsupported export \{export_.export_name}: ambiguous re-export surface cannot be bound safely"
  if export_.ambiguous_source_paths.length() == 0 {
    base + "."
  } else {
    base + "; candidates: " + export_.ambiguous_source_paths.join(", ") + "."
  }
}

///|
fn ffi_to_snake_case(name : String) -> String {
  let mut result = ""
  let mut prev_is_lower_or_digit = false
  for c in name {
    if c >= 'A' && c <= 'Z' {
      if result != "" && prev_is_lower_or_digit {
        result += "_"
      }
      result += ffi_to_lower_ascii(c).to_string()
      prev_is_lower_or_digit = false
    } else if ffi_is_ascii_letter(c) || ffi_is_ascii_digit(c) {
      result += c.to_string()
      prev_is_lower_or_digit = (c >= 'a' && c <= 'z') || ffi_is_ascii_digit(c)
    } else {
      if result != "" && !result.has_suffix("_") {
        result += "_"
      }
      prev_is_lower_or_digit = false
    }
  }
  ffi_sanitize_identifier_chars(ffi_trim_underscores(result), "generated_name")
}

///|
fn ffi_type_identifier(name : String, fallback : String) -> String {
  let sanitized = ffi_sanitize_identifier_chars(name, fallback)
  if sanitized == "" || ffi_trim_underscores(sanitized) == "" {
    return fallback
  }
  let mut idx = 0
  let mut prefix = ""
  while idx < sanitized.length() && sanitized[idx].unsafe_to_char() == '_' {
    prefix += "Underscore"
    idx += 1
  }
  let core = sanitized[idx:sanitized.length()].to_owned()
  if core == "" {
    return fallback
  }
  let first = core[0].unsafe_to_char()
  let normalized_core = if first >= 'a' && first <= 'z' {
    ffi_to_upper_ascii(first).to_string() + core[1:].to_owned()
  } else {
    core
  }
  let normalized = prefix + normalized_core
  match normalized {
    "Array" | "Bool" | "Double" | "Error" | "Int" | "String" | "Unit" =>
      normalized + "_"
    "default" => "Default"
    _ => normalized
  }
}

///|
fn ffi_value_fn_name(name : String) -> String {
  let mut result = ffi_to_snake_case(name)
  if ffi_value_identifier_needs_suffix(result) {
    result += "_"
  }
  result
}

///|
fn ffi_mark_external_type(state : MoonBitJsFfiState, name : String) -> String {
  let type_name = ffi_type_identifier(name, "OpaqueType")
  if state.declared_type_names.contains(type_name) {
    return type_name
  }
  if !state.external_type_names.contains(type_name) {
    state.external_type_names.push(type_name)
  }
  type_name
}

///|
fn ffi_push_local_type_params(
  state : MoonBitJsFfiState,
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
fn ffi_restore_local_type_params(
  state : MoonBitJsFfiState,
  old_len : Int,
) -> Unit {
  while state.local_type_param_names.length() > old_len {
    let _ = state.local_type_param_names.pop()
  }
}

///|
fn ffi_is_local_type_param(state : MoonBitJsFfiState, name : String) -> Bool {
  state.local_type_param_names.contains(name)
}

///|
fn ffi_type_param_suffix(type_params : Array[String]) -> String {
  if type_params.length() == 0 {
    ""
  } else {
    let sanitized : Array[String] = []
    for name in type_params {
      sanitized.push(@parser.moonbit_sanitize_type_param_name(name))
    }
    "[" + sanitized.join(", ") + "]"
  }
}

///|
fn ffi_receiver_self_type(
  type_name : String,
  type_params : Array[String],
) -> String {
  type_name + ffi_type_param_suffix(type_params)
}

///|
fn ffi_function_type_param_prefix(type_params : Array[String]) -> String {
  if type_params.length() == 0 {
    "fn"
  } else {
    "fn" + ffi_type_param_suffix(type_params)
  }
}

///|
/// Whether to keep an interface's TypeScript type parameters when emitting the
/// MoonBit struct. We preserve them whenever the interface declares any —
/// the resulting `pub(all) struct Foo[T, U] { ... }` lets call sites with
/// `Applied("Foo", [JSValue, String])` propagate concrete arguments instead
/// of widening to bare opaque external types.
fn ffi_should_preserve_interface_type_params(iface : @ast.TsInterface) -> Bool {
  iface.type_params.length() > 0
}

///|
/// Whether to keep a class's TypeScript type parameters when emitting
/// MoonBit FFI declarations. Mirrors
/// `moonbit_should_preserve_class_type_params` in `parser_moonbit.mbt`
/// so the FFI and decl sides agree on which classes emit `Foo[T, U]`
/// vs bare `Foo`.
fn ffi_should_preserve_class_type_params(class_ : @ast.TsClassDecl) -> Bool {
  class_.type_params.length() > 0
}

///|
fn ffi_is_likely_discarded_type_param_name(name : String) -> Bool {
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
/// Walk every loaded module's interfaces — including those nested
/// inside namespaces — and register their generic-parameter arity into
/// `generic_type_params_by_name`. Names already present in the map (or
/// in `class_type_names`, where a class drives runtime emission) are
/// left alone. Used to backfill arity for interfaces the FFI's
/// `normalize_interfaces_for_ffi` bailed on (>256 interfaces) so call
/// sites can still resolve `Foo[T, U]` against the decl-side
/// `declare pub type Foo[T, U]`.
///
/// Mirrors the decl-side namespace flattening from
/// `namespace_type_export_name`: for an entry module like
/// `declare namespace ts { namespace server { interface Foo<T> } }`,
/// the bridge name is `ServerFoo` (the outermost namespace gets
/// stripped as if export-equals'd; nested namespaces accumulate
/// PascalCase prefixes).
fn ffi_register_module_iface_arities(
  modules : Map[String, DeclModuleInfo],
  generic_type_params_by_name : Map[String, Array[String]],
  class_type_names : Array[String],
) -> Unit {
  for entry in modules {
    let (_, info) = entry
    ffi_register_module_iface_arities_in_ts_module(
      info.module_,
      "",
      true,
      generic_type_params_by_name,
      class_type_names,
    )
  }
}

///|
fn ffi_register_module_iface_arities_in_ts_module(
  ts_module : @ast.TsModule,
  prefix : String,
  is_outermost : Bool,
  generic_type_params_by_name : Map[String, Array[String]],
  class_type_names : Array[String],
) -> Unit {
  for iface in ts_module.interfaces {
    if iface.type_params.length() == 0 {
      continue
    }
    // Register both the raw name and the prefixed flattened form so
    // call sites referencing either style resolve.
    ffi_register_iface_arity(
      iface.name,
      iface.type_params,
      generic_type_params_by_name,
      class_type_names,
    )
    if prefix != "" {
      let flattened = prefix + ffi_pascal_case(iface.name)
      ffi_register_iface_arity(
        flattened,
        iface.type_params,
        generic_type_params_by_name,
        class_type_names,
      )
    }
  }
  for namespace_ in ts_module.namespaces {
    let next_prefix = if is_outermost {
      // Treat the entry's first namespace as `export = ns` and drop
      // its name from the prefix chain, matching how the decl side
      // emits `ts.NodeArray` as bare `NodeArray`.
      prefix
    } else if prefix == "" {
      ffi_pascal_case(namespace_.name)
    } else {
      prefix + ffi_pascal_case(namespace_.name)
    }
    ffi_register_module_iface_arities_in_ts_module(
      namespace_.module_,
      next_prefix,
      false,
      generic_type_params_by_name,
      class_type_names,
    )
  }
}

///|
fn ffi_register_iface_arity(
  iface_name : String,
  type_params : Array[String],
  generic_type_params_by_name : Map[String, Array[String]],
  class_type_names : Array[String],
) -> Unit {
  let type_name = ffi_type_identifier(iface_name, "OpaqueType")
  if class_type_names.contains(type_name) {
    return
  }
  match generic_type_params_by_name.get(type_name) {
    Some(_) => ()
    None => generic_type_params_by_name[type_name] = type_params
  }
}

///|
/// Uppercase the first ASCII letter of `name` to mirror the decl-side
/// `decl_to_pascal_case` namespace-prefix accumulation. Non-ASCII /
/// already-uppercase / leading-non-letter inputs pass through unchanged.
fn ffi_pascal_case(name : String) -> String {
  if name == "" {
    return name
  }
  let first = name[0].to_int().unsafe_to_char()
  if first >= 'a' && first <= 'z' {
    let upper = (first.to_int() - 32).unsafe_to_char()
    upper.to_string() + name[1:].to_owned()
  } else {
    name
  }
}

///|
fn ffi_should_widen_unresolved_type_param(
  state : MoonBitJsFfiState,
  name : String,
) -> Bool {
  !state.declared_type_names.contains(ffi_type_identifier(name, "OpaqueType")) &&
  !ffi_named_type_is_primitive_enum_in(state.enums, name) &&
  ffi_is_likely_discarded_type_param_name(name)
}

///|
fn ffi_find_enum_decl(
  state : MoonBitJsFfiState,
  name : String,
) -> @ast.TsEnumDecl? {
  ffi_find_enum_decl_in(state.enums, name)
}

///|
fn ffi_find_enum_decl_in(
  enums : Array[@ast.TsEnumDecl],
  name : String,
) -> @ast.TsEnumDecl? {
  let type_name = ffi_type_identifier(name, "GeneratedEnum")
  for enum_ in enums {
    if ffi_type_identifier(enum_.name, "GeneratedEnum") == type_name {
      return Some(enum_)
    }
  }
  None
}

// Structural classification helpers moved to `mizchi/ts/checker`.

///|
fn ffi_enum_case_names(
  enum_ : @ast.TsEnumDecl,
) -> Array[(String, @ast.TsEnumMember)] {
  enum_lowering_case_names(enum_)
}

///|
fn ffi_enum_string_cases(enum_ : @ast.TsEnumDecl) -> Array[(String, String)]? {
  enum_lowering_string_cases(enum_)
}

///|
fn ffi_enum_int_cases(enum_ : @ast.TsEnumDecl) -> Array[(String, Int)]? {
  match enum_lowering_int_cases(enum_) {
    Some(cases) =>
      if ffi_int_cases_need_double(cases) {
        None
      } else {
        Some(cases)
      }
    None => None
  }
}

///|
fn ffi_enum_double_int_cases(enum_ : @ast.TsEnumDecl) -> Array[(String, Int)]? {
  match enum_lowering_int_cases(enum_) {
    Some(cases) =>
      if ffi_int_cases_need_double(cases) {
        Some(cases)
      } else {
        None
      }
    None => None
  }
}

///|
fn ffi_named_type_is_string_enum(
  state : MoonBitJsFfiState,
  name : String,
) -> Bool {
  match ffi_find_enum_decl(state, name) {
    Some(enum_) =>
      match ffi_enum_string_cases(enum_) {
        Some(_) => true
        None => false
      }
    None => false
  }
}

///|
fn ffi_named_type_is_int_enum(state : MoonBitJsFfiState, name : String) -> Bool {
  match ffi_find_enum_decl(state, name) {
    Some(enum_) =>
      match ffi_enum_int_cases(enum_) {
        Some(_) => true
        None => false
      }
    None => false
  }
}

///|
fn ffi_named_type_is_double_int_enum(
  state : MoonBitJsFfiState,
  name : String,
) -> Bool {
  match ffi_find_enum_decl(state, name) {
    Some(enum_) =>
      match ffi_enum_double_int_cases(enum_) {
        Some(_) => true
        None => false
      }
    None => false
  }
}

///|
fn ffi_named_type_is_primitive_enum_in(
  enums : Array[@ast.TsEnumDecl],
  name : String,
) -> Bool {
  match ffi_find_enum_decl_in(enums, name) {
    Some(enum_) =>
      match ffi_enum_string_cases(enum_) {
        Some(_) => true
        None =>
          match ffi_enum_int_cases(enum_) {
            Some(_) => true
            None =>
              match ffi_enum_double_int_cases(enum_) {
                Some(_) => true
                None => false
              }
          }
      }
    None => false
  }
}

///|
fn ffi_type_has_primitive_enum(
  enums : Array[@ast.TsEnumDecl],
  type_ : @ast.TsType,
) -> Bool {
  match @checker.classify_optional_like_union(type_) {
    Some((collapsed, _)) => return ffi_type_has_primitive_enum(enums, collapsed)
    None => ()
  }
  match @checker.classify_transparent_intersection(type_) {
    Some(inner) => return ffi_type_has_primitive_enum(enums, inner)
    None => ()
  }
  match type_ {
    Named(name) | Applied(name, _) =>
      ffi_named_type_is_primitive_enum_in(enums, name)
    Array(inner) => ffi_type_has_primitive_enum(enums, inner)
    Tuple(items) | Intersection(items) | Union(items) => {
      for item in items {
        if ffi_type_has_primitive_enum(enums, item) {
          return true
        }
      }
      false
    }
    Struct(_, fields) => {
      for field in fields {
        if ffi_type_has_primitive_enum(enums, field.1) {
          return true
        }
      }
      false
    }
    Object(fields) => {
      for field in fields {
        if ffi_type_has_primitive_enum(enums, field.1) {
          return true
        }
      }
      false
    }
    Func(_, _) => false
    _ => false
  }
}

///|
fn ffi_tuple_type_name(
  state : MoonBitJsFfiState,
  items : Array[@ast.TsType],
) -> String {
  if items.length() == 0 {
    return "Array[Unit]"
  }
  let first = ffi_type_name(state, items[0])
  for i in 1..<items.length() {
    if ffi_type_name(state, items[i]) != first {
      state.needs_js_any = true
      return "Array[JSValue]"
    }
  }
  "Array[\{first}]"
}

///|
fn ffi_func_type_name(
  state : MoonBitJsFfiState,
  params : Array[@ast.TsType],
  return_type : @ast.TsType,
) -> String {
  let param_types : Array[String] = []
  for param in params {
    param_types.push(ffi_type_name(state, param))
  }
  let params_src = param_types.join(", ")
  let return_src = ffi_type_name(state, return_type)
  "(\{params_src}) -> \{return_src}"
}

///|
fn ffi_type_is_string_like(type_ : @ast.TsType) -> Bool {
  match @checker.normalize_literal_type(type_) {
    String_ => true
    _ => false
  }
}

///|
fn ffi_type_is_string_array_like(type_ : @ast.TsType) -> Bool {
  match type_ {
    Array(inner)
    | Applied("Array", [inner])
    | Applied("ReadonlyArray", [inner]) => ffi_type_is_string_like(inner)
    _ => false
  }
}

///|
fn ffi_type_is_string_or_string_array_union(type_ : @ast.TsType) -> Bool {
  match type_ {
    Union(items) => {
      let mut has_string = false
      let mut has_array = false
      for item in items {
        if ffi_type_is_string_like(item) {
          has_string = true
        } else if ffi_type_is_string_array_like(item) {
          has_array = true
        } else {
          return false
        }
      }
      has_string && has_array
    }
    _ => false
  }
}

///|
fn ffi_callable_value_param_type_name(
  state : MoonBitJsFfiState,
  type_ : @ast.TsType,
) -> String {
  if ffi_type_is_string_or_string_array_union(type_) {
    "String"
  } else {
    ffi_type_name(state, type_)
  }
}

///|
fn ffi_func_string_subset_param_type_name(
  state : MoonBitJsFfiState,
  type_ : @ast.TsType,
) -> String {
  if ffi_type_is_string_or_string_array_union(type_) {
    "String"
  } else {
    ffi_type_name(state, type_)
  }
}

///|
fn ffi_rendered_type_uses_js_any(type_name : String) -> Bool {
  type_name.contains("@js.Any") || type_name.contains("JSValue")
}

///|
fn ffi_callable_value_should_emit_wrapper(
  state : MoonBitJsFfiState,
  params : Array[@ast.TsType],
  return_type : @ast.TsType,
) -> Bool {
  for param in params {
    let param_type = ffi_callable_value_param_type_name(state, param)
    if ffi_rendered_type_uses_js_any(param_type) {
      return false
    }
  }
  !ffi_rendered_type_uses_js_any(ffi_type_name(state, return_type))
}

///|
fn ffi_type_name(state : MoonBitJsFfiState, type_ : @ast.TsType) -> String {
  // Unresolved `infer X extends Bound` markers collapse to the bound
  // type at the FFI boundary. Bare `infer X` markers (no bound) fall
  // through to the existing JSValue widening below.
  match @checker.infer_marker_bound(type_) {
    Some(bound) => return ffi_type_name(state, bound)
    None => ()
  }
  match @checker.classify_optional_like_union(type_) {
    Some((collapsed, is_optional)) => {
      let rendered = ffi_type_name(state, collapsed)
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
    Some(inner) => return ffi_type_name(state, inner)
    None => ()
  }
  match type_ {
    Literal(_) | NumberLiteral(_) | BigIntLiteral(_) | BooleanLiteral(_) =>
      ffi_type_name(state, @checker.normalize_literal_type(type_))
    Number => "Double"
    Int => "Int"
    BigInt => "Int64"
    Boolean => "Bool"
    String_ => "String"
    Void => "Unit"
    Array(inner) => "Array[" + ffi_type_name(state, inner) + "]"
    Tuple(items) => ffi_tuple_type_name(state, items)
    // Outside a Tuple element, a bare `Rest(T)` behaves like `Array(T)`.
    Rest(inner) => "Array[" + ffi_type_name(state, inner) + "]"
    Constructor(params, return_type, _) =>
      ffi_func_type_name(state, params, return_type)
    Func(params, return_type) => ffi_func_type_name(state, params, return_type)
    Struct(name, _) => ffi_type_identifier(name, "OpaqueType")
    Named("any") | Named("Function") => {
      state.needs_js_any = true
      "JSValue"
    }
    Named("Array") | Named("ReadonlyArray") => {
      state.needs_js_any = true
      "Array[JSValue]"
    }
    Applied("Array", [inner]) | Applied("ReadonlyArray", [inner]) =>
      "Array[" + ffi_type_name(state, inner) + "]"
    Applied("Promise", [inner]) | Applied("PromiseLike", [inner]) => {
      state.needs_promise = true
      "Promise[" + ffi_type_name(state, inner) + "]"
    }
    TypeOf(_) => {
      state.needs_js_any = true
      "JSValue"
    }
    Named(name) if ffi_is_local_type_param(state, name) =>
      @parser.moonbit_sanitize_type_param_name(name)
    Applied(name, _) if ffi_is_local_type_param(state, name) =>
      @parser.moonbit_sanitize_type_param_name(name)
    Named(name) if ffi_should_widen_unresolved_type_param(state, name) => {
      state.needs_js_any = true
      "JSValue"
    }
    Applied(name, _) if ffi_should_widen_unresolved_type_param(state, name) => {
      state.needs_js_any = true
      "JSValue"
    }
    Named(name) if ffi_named_type_is_string_enum(state, name) => "String"
    Applied(name, _) if ffi_named_type_is_string_enum(state, name) => "String"
    Named(name) if ffi_named_type_is_int_enum(state, name) => "Int"
    Applied(name, _) if ffi_named_type_is_int_enum(state, name) => "Int"
    Named(name) if ffi_named_type_is_double_int_enum(state, name) => "Double"
    Applied(name, _) if ffi_named_type_is_double_int_enum(state, name) =>
      "Double"
    // Bare `Promise` / `PromiseLike` references with no type argument can
    // appear in Vitest-style declarations where the resolved value type is
    // unrecoverable. Default to `Promise[JSValue]` so it stays compatible
    // with the public `pub type Promise[X]` declaration.
    Named("Promise") | Named("PromiseLike") => {
      state.needs_promise = true
      state.needs_js_any = true
      "Promise[JSValue]"
    }
    Named(name) => {
      // A bare reference to a generic-preserved type (`Ref` instead of
      // `Ref<T>`) leaves the type-parameter slots unspecified. Fill them
      // with `JSValue` so the emitted MoonBit signature matches the
      // struct's arity.
      let type_name = ffi_type_identifier(name, "OpaqueType")
      match state.generic_type_params_by_name.get(type_name) {
        Some(type_params) if type_params.length() > 0 => {
          state.needs_js_any = true
          // Mark the type so the trailing opaque-external loop emits
          // a matching `#external pub type Foo[T, U]` decl when no
          // struct decl was generated.
          let _ = ffi_mark_external_type(state, name)
          let rendered_args : Array[String] = []
          for _ in 0..<type_params.length() {
            rendered_args.push("JSValue")
          }
          type_name + "[" + rendered_args.join(", ") + "]"
        }
        _ => ffi_mark_external_type(state, name)
      }
    }
    Applied(name, args) => {
      let type_name = ffi_type_identifier(name, "OpaqueType")
      match state.generic_type_params_by_name.get(type_name) {
        Some(type_params) =>
          if type_params.length() == args.length() {
            let _ = ffi_mark_external_type(state, name)
            let rendered_args : Array[String] = []
            for arg in args {
              rendered_args.push(ffi_type_name(state, arg))
            }
            type_name + "[" + rendered_args.join(", ") + "]"
          } else if type_params.length() > 0 {
            // Arity mismatch: fall back to widened `JSValue` slots so we
            // still emit a syntactically valid `T[JSValue, ...]` form
            // matching the struct declaration.
            state.needs_js_any = true
            let _ = ffi_mark_external_type(state, name)
            let rendered_args : Array[String] = []
            for _ in 0..<type_params.length() {
              rendered_args.push("JSValue")
            }
            type_name + "[" + rendered_args.join(", ") + "]"
          } else {
            ffi_mark_external_type(state, name)
          }
        None => ffi_mark_external_type(state, name)
      }
    }
    // Template literal types resolve to a `string` subtype in TypeScript;
    // until step 4.3 lowers them to enum cases, fall back to plain String
    // rather than widening to JSValue.
    TemplateLiteralType(_, _) => "String"
    // `paramName is T` is a boolean at the FFI boundary; the predicate
    // information is consumed by the checker / bridge type-guard collector.
    TypePredicate(_, _) => "Bool"
    // `asserts x [is T]` returns `void` at runtime — the predicate is
    // only used by the checker to narrow the calling scope.
    AssertsPredicate(_, _) => "Unit"
    // `unique symbol` has no MoonBit equivalent that preserves the
    // nominal identity. The runtime value is a JS `symbol`.
    UniqueSymbol(_) => {
      state.needs_js_any = true
      "JSValue"
    }
    Union(parts) =>
      match ffi_synthesize_inline_union(state, parts) {
        Some(synth_name) => synth_name
        None =>
          match ffi_string_subset_union_text(state, parts) {
            Some(text) => text
            None => {
              state.needs_js_any = true
              "JSValue"
            }
          }
      }
    _ => {
      state.needs_js_any = true
      "JSValue"
    }
  }
}

///|
fn ffi_type_alias_decl_to_moonbit(
  state : MoonBitJsFfiState,
  type_alias : @ast.TsTypeAlias,
) -> String? {
  if !type_alias_passthrough_supported(type_alias) {
    return None
  }
  let type_name = ffi_type_identifier(type_alias.name, "AliasType")
  let target_type = ffi_type_alias_target_name(state, type_alias.type_)
  if target_type.contains("JSValue") {
    None
  } else {
    Some("pub type \{type_name} = \{target_type}")
  }
}

///|
fn ffi_type_alias_target_name(
  state : MoonBitJsFfiState,
  type_ : @ast.TsType,
) -> String {
  match @checker.classify_optional_like_union(type_) {
    Some((collapsed, _)) => {
      let rendered = ffi_type_alias_target_name(state, collapsed)
      if rendered.has_suffix("?") {
        return rendered
      }
      return rendered + "?"
    }
    None => ()
  }
  match @checker.classify_transparent_intersection(type_) {
    Some(inner) => return ffi_type_alias_target_name(state, inner)
    None => ()
  }
  match type_ {
    Literal(_) | NumberLiteral(_) | BigIntLiteral(_) | BooleanLiteral(_) =>
      ffi_type_alias_target_name(state, @checker.normalize_literal_type(type_))
    Array(inner) => "Array[" + ffi_type_alias_target_name(state, inner) + "]"
    Tuple(items) => ffi_type_alias_tuple_target_name(state, items)
    Func(params, return_type) =>
      ffi_type_alias_func_target_name(state, params, return_type)
    Applied("Array", [inner]) | Applied("ReadonlyArray", [inner]) =>
      "Array[" + ffi_type_alias_target_name(state, inner) + "]"
    Applied("Promise", [inner]) | Applied("PromiseLike", [inner]) => {
      state.needs_promise = true
      "Promise[" + ffi_type_alias_target_name(state, inner) + "]"
    }
    Named(name) if ffi_named_type_is_string_enum(state, name) ||
      ffi_named_type_is_int_enum(state, name) ||
      ffi_named_type_is_double_int_enum(state, name) =>
      ffi_type_identifier(name, "GeneratedEnum")
    Applied(name, _) if ffi_named_type_is_string_enum(state, name) ||
      ffi_named_type_is_int_enum(state, name) ||
      ffi_named_type_is_double_int_enum(state, name) =>
      ffi_type_identifier(name, "GeneratedEnum")
    _ => ffi_type_name(state, type_)
  }
}

///|
fn ffi_type_alias_tuple_target_name(
  state : MoonBitJsFfiState,
  items : Array[@ast.TsType],
) -> String {
  if items.length() == 0 {
    return "Array[JSValue]"
  }
  let first = ffi_type_alias_target_name(state, items[0])
  for i in 1..<items.length() {
    if ffi_type_alias_target_name(state, items[i]) != first {
      state.needs_js_any = true
      return "Array[JSValue]"
    }
  }
  "Array[" + first + "]"
}

///|
fn ffi_type_alias_func_target_name(
  state : MoonBitJsFfiState,
  params : Array[@ast.TsType],
  return_type : @ast.TsType,
) -> String {
  let param_types : Array[String] = []
  for param in params {
    param_types.push(ffi_type_alias_target_name(state, param))
  }
  let return_src = ffi_type_alias_target_name(state, return_type)
  "(" + param_types.join(", ") + ") -> " + return_src
}

///|
/// Build a deterministic PascalCase name for a heterogeneous inline union
/// that the auto-lowerer accepted as a tagged-union shape. Cases are sorted
/// by constructor name so two equivalent unions written in different orders
/// (e.g. `string | string[]` vs `string[] | string`) collapse to the same
/// synthetic alias instead of producing two parallel enums.
fn ffi_inline_union_synthesized_name(
  cases : Array[(String, @ast.TsType)],
) -> String {
  let names : Array[String] = []
  for entry in cases {
    let (case_name, _) = entry
    names.push(case_name)
  }
  // Shortlex order from `String::compare`; deterministic and matches the
  // parser-side helper so both paths produce the same synthetic alias name.
  names.sort()
  "Auto_" + names.join("_or_")
}

///|
/// String-subset policy for the pervasive optional-message pattern
/// (`params?: string | $ZodCheckMinLengthParams` across the zod check
/// surface): when a two-member union pairs `string` with a named
/// `...Params` bag that is NOT reachable as a declared type in this
/// bridge surface, type the boundary as `String`. The common string form
/// becomes naturally typed; the structured object form stays reachable
/// via `unsafeCast`. Restricted to the `*Params` suffix so option-bag
/// unions with reachable declarations keep their tagged lowering, and
/// shapes like `string | URL` keep the JSValue fallback.
fn ffi_string_subset_union_text(
  state : MoonBitJsFfiState,
  parts : Array[@ast.TsType],
) -> String? {
  if parts.length() != 2 {
    return None
  }
  // The bag reference survives in two shapes depending on how far alias
  // inlining got before rendering: `Named("core.$ZodEmailParams")` when the
  // qualified alias never resolved, or `Applied("StringFormatParams", ...)`
  // when it resolved into an applied generic alias the decl layer cannot
  // expand. Both keep the `*Params` suffix.
  let named = match (parts[0], parts[1]) {
    (String_, Named(n)) | (Named(n), String_) => n
    (String_, Applied(n, _)) | (Applied(n, _), String_) => n
    _ => return None
  }
  if !named.has_suffix("Params") {
    return None
  }
  let ident = ffi_type_identifier(named, "OpaqueType")
  if state.declared_type_names.contains(ident) ||
    state.generic_type_params_by_name.get(ident) is Some(_) ||
    ffi_is_local_type_param(state, named) {
    return None
  }
  Some("String")
}

///|
/// Try to lower an inline `Union(parts)` encountered while rendering a
/// MoonBit type signature into a synthetic tagged-union alias, returning the
/// alias name on success. The decl is registered both on the regular
/// tagged-union map (so the inline JS converter helpers find it via name
/// lookup) and on a dedicated `synthesized_inline_unions` map so the
/// emission pass can append the enum decl + bridge.js converter pair.
///
/// Returns `None` when the union cannot be discriminated at the JS boundary
/// or when any case payload is not MoonBit-renderable; callers fall back to
/// the existing `@js.Any` widening.
fn ffi_synthesize_inline_union(
  state : MoonBitJsFfiState,
  parts : Array[@ast.TsType],
) -> String? {
  // Function members are accepted for EXPORTED alias lowering (their
  // boundary stays passthrough), but inline synthesis would generate a
  // wrapper whose conversion glue can't produce the enum from a raw
  // value (`useState(initialState: S | (() => S))` — the JSValue
  // argument has no path into `Auto_SValue_or_FnValue`). Keep such
  // inline unions on the JSValue fallback.
  for part in parts {
    if part is Func(_, _) {
      return None
    }
  }
  let cases = match tagged_union_cases(parts) {
    Some(c) => c
    None => return None
  }
  for entry in cases {
    let (_, inner) = entry
    match tagged_union_case_discriminator(inner) {
      Some(_) => ()
      None => return None
    }
    // No-payload literal cases need no MoonBit-side payload type — only
    // payload-bearing cases gate on `tagged_union_inner_moonbit_text`.
    if !tagged_union_case_is_no_payload(inner) {
      match
        tagged_union_inner_moonbit_text_with_arity(
          inner,
          state.generic_type_params_by_name,
        ) {
        Some(_) => ()
        None => return None
      }
    }
  }
  let name = ffi_inline_union_synthesized_name(cases)
  if !state.synthesized_inline_unions.contains(name) {
    let decl : BridgeTaggedUnionDecl = { name, cases }
    state.synthesized_inline_unions[name] = decl
    state.tagged_union_decls_by_name[name] = decl
  }
  Some(name)
}

///|
/// Erase a generic callable's OWN type-parameter names to `Any` (rendered
/// `JSValue`). MoonBit forbids `extern "js" fn[T]`, so a member typed
/// `<E>(expected: E) => void` (vitest's `Assertion.toBe`) lowers to its
/// value shape with `E` widened — without this the whole member degrades
/// to a `JSValue` property and loses its method wrapper.
fn ffi_erase_generic_names(
  t : @ast.TsType,
  names : Array[String],
) -> @ast.TsType {
  fn go(x : @ast.TsType) -> @ast.TsType {
    ffi_erase_generic_names(x, names)
  }

  match t {
    Named(n) => if names.contains(n) { Any } else { t }
    Array(i) => Array(go(i))
    Rest(i) => Rest(go(i))
    Union(items) => Union(items.map(go))
    Intersection(items) => Intersection(items.map(go))
    Tuple(items) => Tuple(items.map(go))
    Func(ps, r) => Func(ps.map(go), go(r))
    Constructor(ps, r, a) => Constructor(ps.map(go), go(r), a)
    Applied(n, args) => Applied(n, args.map(go))
    Object(fields) => Object(fields.map(fn(f) { (f.0, go(f.1)) }))
    GenericFunc(inner_names, inner) => GenericFunc(inner_names, go(inner))
    _ => t
  }
}

///|
fn ffi_function_field_type_name(
  state : MoonBitJsFfiState,
  type_ : @ast.TsType,
) -> String {
  match @checker.classify_optional_like_union(type_) {
    Some((collapsed, is_optional)) => {
      let rendered = ffi_function_field_type_name(state, collapsed)
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
    Func(params, return_type) => ffi_func_type_name(state, params, return_type)
    // A member's own generic binder is erased at the FFI boundary
    // (`toBe: <E>(expected: E) => void` — vitest's Assertion).
    GenericFunc(names, inner) =>
      ffi_function_field_type_name(state, ffi_erase_generic_names(inner, names))
    _ => ffi_type_name(state, type_)
  }
}

///|
fn ffi_replace_this_token(rendered : String, owner_name : String) -> String {
  // Conservative: only rewrite ` This` and `>This` boundaries that appear in
  // generated MoonBit signatures (`-> This`, `> This`). The owner name is
  // already a sanitized type identifier so collision risk is bounded.
  let mut result = rendered.replace(
    old="-> This?",
    new="-> " + owner_name + "?",
  )
  result = result.replace(old="-> This\n", new="-> " + owner_name + "\n")
  result = result.replace(old="-> This)", new="-> " + owner_name + ")")
  if result.has_suffix("-> This") {
    result = result[:result.length() - 7].to_owned() + "-> " + owner_name
  }
  result
}

///|
fn ffi_struct_field_type_name(
  state : MoonBitJsFfiState,
  type_ : @ast.TsType,
) -> String {
  match @checker.classify_optional_like_union(type_) {
    Some((collapsed, is_optional)) => {
      let rendered = ffi_struct_field_type_name(state, collapsed)
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
    Some(inner) => return ffi_struct_field_type_name(state, inner)
    None => ()
  }
  match type_ {
    Literal(_) | NumberLiteral(_) | BigIntLiteral(_) | BooleanLiteral(_) =>
      ffi_struct_field_type_name(state, @checker.normalize_literal_type(type_))
    Array(inner) => "Array[" + ffi_struct_field_type_name(state, inner) + "]"
    Func(_, _) | GenericFunc(_, _) => ffi_function_field_type_name(state, type_)
    Named(name) if ffi_named_type_is_primitive_enum_in(state.enums, name) =>
      ffi_type_identifier(name, "GeneratedEnum")
    Applied(name, _) if ffi_named_type_is_primitive_enum_in(state.enums, name) =>
      ffi_type_identifier(name, "GeneratedEnum")
    _ => ffi_type_name(state, type_)
  }
}

///|
fn ffi_function_type_parts(
  state : MoonBitJsFfiState,
  type_ : @ast.TsType,
) -> (Array[@ast.TsType], Array[String], String)? {
  match type_ {
    Func(params, return_type) => {
      let param_types : Array[String] = []
      for param in params {
        param_types.push(ffi_type_name(state, param))
      }
      Some((params, param_types, ffi_type_name(state, return_type)))
    }
    // A member's own generic binder is erased at the FFI boundary
    // (`toBe: <E>(expected: E) => void` — vitest's Assertion), matching
    // the struct-field rendering so `(self.<field>)(args)` type-checks.
    GenericFunc(names, inner) =>
      ffi_function_type_parts(state, ffi_erase_generic_names(inner, names))
    _ => None
  }
}

///|
fn ffi_inline_js_unwrap_option_expr(expr : String) -> String {
  "(\{expr} == null ? undefined : (typeof \{expr} === \"object\" && \"$tag\" in \{expr} ? (\{expr}.$tag === 1 ? \{expr}._0 : undefined) : \{expr}))"
}

///|
fn ffi_inline_js_arg_expr_with_state(
  state : MoonBitJsFfiState?,
  type_ : @ast.TsType,
  expr : String,
) -> String {
  match @checker.classify_optional_like_union(type_) {
    Some((collapsed, is_optional)) => {
      if !is_optional {
        return ffi_inline_js_arg_expr_with_state(state, collapsed, expr)
      }
      // Tagged-union optional params come in as the raw value or `null` /
      // `undefined`: MoonBit's JS encoding for `Option[T]` of a non-primitive
      // `T` does not wrap with `{$tag, _0}`. Going through the generic
      // option unwrap would mis-read `value._0` (undefined for no-payload
      // cases like `Boundary`), so detect the tagged-union case first.
      let tagged_named_name = match state {
        Some(s) =>
          match collapsed {
            @ast.TsType::Named(name) =>
              if s.tagged_union_decls_by_name.contains(name) {
                Some(name)
              } else {
                None
              }
            _ => None
          }
        None => None
      }
      match tagged_named_name {
        Some(_) => {
          let inner_expr = "(\{expr} == null ? undefined : \{expr})"
          return ffi_inline_js_tagged_union_to_js(state, collapsed, inner_expr)
        }
        None => ()
      }
      let inner_expr = ffi_inline_js_unwrap_option_expr(expr)
      let collapsed_inner = ffi_inline_js_tagged_union_to_js(
        state, collapsed, inner_expr,
      )
      return match collapsed {
        Boolean => "(\{expr} === -1 ? undefined : \{collapsed_inner})"
        _ => collapsed_inner
      }
    }
    None => ()
  }
  match @checker.classify_transparent_intersection(type_) {
    Some(inner) => ffi_inline_js_arg_expr_with_state(state, inner, expr)
    None => ffi_inline_js_tagged_union_to_js(state, type_, expr)
  }
}

///|
fn ffi_inline_js_tagged_union_to_js(
  state : MoonBitJsFfiState?,
  type_ : @ast.TsType,
  expr : String,
) -> String {
  // Inline the tagged-union -> JS conversion expression directly into the
  // generated `extern "js" fn` lambda body. Calling the named bridge.js
  // helper (`__ts_mbt_tagged_union_X_to_js(...)`) by name would require
  // every consumer extern to also import that helper, which the MoonBit JS
  // backend doesn't do automatically for inline lambda bodies. Inlining
  // the IIFE keeps the conversion self-contained.
  match state {
    Some(s) =>
      match type_ {
        @ast.TsType::Named(name) =>
          match s.tagged_union_decls_by_name.get(name) {
            Some(decl) =>
              tagged_union_to_js_expression_with_nested(
                decl,
                expr,
                s.tagged_union_decls_by_name,
                struct_converter_names=s.struct_type_names,
              )
            None => expr
          }
        // Inline `A | B` lowered to a synthesised tagged-union alias: the
        // signature already reads `Auto_X_or_Y` but the AST keeps the
        // original `Union(parts)` shape, so re-derive the synthesised name
        // and route through its `_to_js` converter.
        @ast.TsType::Union(parts) =>
          match tagged_union_cases(parts) {
            Some(cases) => {
              let name = ffi_inline_union_synthesized_name(cases)
              match s.tagged_union_decls_by_name.get(name) {
                Some(decl) =>
                  tagged_union_to_js_expression_with_nested(
                    decl,
                    expr,
                    s.tagged_union_decls_by_name,
                    struct_converter_names=s.struct_type_names,
                  )
                None => expr
              }
            }
            None => expr
          }
        _ => expr
      }
    None => expr
  }
}

///|
fn ffi_function_field_method_decl(
  state : MoonBitJsFfiState,
  receiver_type : String,
  receiver_type_params : Array[String],
  field_name : String,
  js_field_name : String,
  field_type : @ast.TsType,
) -> String? {
  match ffi_function_type_parts(state, field_type) {
    Some((source_param_types, param_types, return_type)) => {
      let self_type = ffi_receiver_self_type(
        receiver_type, receiver_type_params,
      )
      // Replace TypeScript `this` return-type sentinel ("This" / "This?")
      // with the owning receiver so builder-style chains type-check.
      let return_type = match return_type {
        "This" => self_type
        "This?" => self_type + "?"
        _ => return_type
      }
      let params : Array[String] = ["self : \{self_type}"]
      let args : Array[String] = []
      for i, param_type in param_types {
        let arg_name = "arg" + i.to_string()
        params.push("\{arg_name} : \{param_type}")
        args.push(arg_name)
      }
      let params_src = params.join(", ")
      let args_src = args.join(", ")
      let js_args : Array[String] = []
      for i, arg in args {
        js_args.push(
          ffi_inline_js_arg_expr_with_state(
            Some(state),
            source_param_types[i],
            arg,
          ),
        )
      }
      let js_args_src = js_args.join(", ")
      let fn_prefix = ffi_function_type_param_prefix(receiver_type_params)
      // MoonBit's `extern "js" fn[T]` is forbidden ([4008]), so any method
      // on a generic-preserved receiver has to fall through to the
      // pure-MoonBit wrapper form which accesses the underlying function
      // field via `self.<field>(...)`.
      if receiver_type_params.length() > 0 {
        Some(
          "pub \{fn_prefix} \{receiver_type}::\{field_name}(\{params_src}) -> \{return_type} {\n  (self.\{field_name})(\{args_src})\n}",
        )
      } else if field_name == "_call_" {
        let js_params : Array[String] = ["self"]
        for arg in args {
          js_params.push(arg)
        }
        let js_params_src = js_params.join(", ")
        Some(
          "pub extern \"js\" \{fn_prefix} \{receiver_type}::\{field_name}(\{params_src}) -> \{return_type} =\n  #| (\{js_params_src}) => self(\{js_args_src})",
        )
      } else if receiver_type == "Assertion" {
        let js_params : Array[String] = ["self"]
        for arg in args {
          js_params.push(arg)
        }
        let js_params_src = js_params.join(", ")
        let js_call = ffi_js_access("self", js_field_name) +
          "(" +
          js_args_src +
          ")"
        Some(
          "pub extern \"js\" \{fn_prefix} \{receiver_type}::\{field_name}(\{params_src}) -> \{return_type} =\n  #| (\{js_params_src}) => \{js_call}",
        )
      } else {
        let js_params : Array[String] = ["self"]
        for arg in args {
          js_params.push(arg)
        }
        let js_params_src = js_params.join(", ")
        let js_call = ffi_js_access("self", js_field_name) +
          "(" +
          js_args_src +
          ")"
        Some(
          "pub extern \"js\" \{fn_prefix} \{receiver_type}::\{field_name}(\{params_src}) -> \{return_type} =\n  #| (\{js_params_src}) => \{js_call}",
        )
      }
    }
    None => None
  }
}

///|
/// `@internal` members never surface (tsc's stripInternal hides them
/// from declaration consumers). `@deprecated` members stay only while
/// they type naturally — one that could only widen to `JSValue` is
/// dropped rather than kept as a fallback slot (zod's `_def` /
/// `_input` / `_output`). The same predicate gates the struct decl and
/// its bridge.js converter so both sides agree on the field set.
fn ffi_interface_field_is_hidden(
  state : MoonBitJsFfiState,
  iface : @ast.TsInterface,
  name : String,
  type_ : @ast.TsType,
) -> Bool {
  if iface.internal_members.contains(name) {
    return true
  }
  if iface.deprecated_members.contains(name) {
    return ffi_struct_field_type_name(state, type_).contains("JSValue")
  }
  false
}

///|
fn ffi_visible_interface_fields(
  state : MoonBitJsFfiState,
  iface : @ast.TsInterface,
) -> Array[(String, @ast.TsType)] {
  if iface.internal_members.length() == 0 &&
    iface.deprecated_members.length() == 0 {
    return iface.fields
  }
  let out : Array[(String, @ast.TsType)] = []
  for field in iface.fields {
    let (name, type_) = field
    if !ffi_interface_field_is_hidden(state, iface, name, type_) {
      out.push(field)
    }
  }
  out
}

///|
fn ffi_struct_decl_to_moonbit(
  state : MoonBitJsFfiState,
  iface : @ast.TsInterface,
) -> String {
  // Keep the full type-param list. The arity registered in
  // `state.generic_type_params_by_name` matches `iface.type_params`, so
  // call sites referencing `Foo[A, B]` against a `pub(all) struct Foo[T, U]`
  // resolve correctly even when one of T/U is no longer referenced in the
  // body (the parser sometimes substitutes generic-bound references away
  // via `extends`). Unused-type-variable warnings ([0005]) on the
  // resulting decl can't be suppressed per-item, so `warning_guard.sh`
  // filters them out for the regenerated bridge.
  let active_type_params = if ffi_should_preserve_interface_type_params(iface) {
    iface.type_params
  } else {
    []
  }
  let local_type_param_len = ffi_push_local_type_params(
    state, active_type_params,
  )
  let type_name = ffi_type_identifier(iface.name, "OpaqueType")
  let type_param_suffix = ffi_type_param_suffix(active_type_params)
  let lines : Array[String] = [
    "#warnings(\"-9\")",
    "pub(all) struct \{type_name}\{type_param_suffix} {",
  ]
  let method_lines : Array[String] = []
  let mut method_wrapper_count = 0
  let seen_fields : Array[String] = []
  for field in iface.fields {
    let (name, type_) = field
    if ffi_interface_field_is_hidden(state, iface, name, type_) {
      continue
    }
    let field_name = ffi_sanitize_identifier(name, "field")
    if seen_fields.contains(field_name) {
      continue
    }
    seen_fields.push(field_name)
    if iface.readonly_fields.contains(name) {
      lines.push(
        "  // readonly in TypeScript; not enforced by generated MoonBit struct",
      )
    }
    let raw_struct_field_type = ffi_struct_field_type_name(state, type_)
    // TypeScript `this` builder return -> owning struct.
    let struct_field_type = ffi_replace_this_token(
      raw_struct_field_type, type_name,
    )
    lines.push("  \{field_name} : \{struct_field_type}")
    let force_method_wrapper = field_name == "_call_"
    if force_method_wrapper ||
      method_wrapper_count < state.function_field_method_wrapper_limit {
      match
        ffi_function_field_method_decl(
          state, type_name, active_type_params, field_name, name, type_,
        ) {
        Some(method_decl) => {
          method_lines.push(method_decl)
          if !force_method_wrapper {
            method_wrapper_count += 1
          }
        }
        None => ()
      }
    }
  }
  lines.push("}")
  // Skip index-signature accessors on generic-preserved interfaces:
  // `op_get` / `op_set` would need to be `extern "js" fn[T]` to thread
  // the value type, but MoonBit forbids generic FFI functions.
  if active_type_params.length() == 0 {
    for sig in iface.index_signatures {
      match ffi_index_signature_accessor_decls(state, type_name, sig) {
        Some(decls) =>
          for decl in decls {
            method_lines.push(decl)
          }
        None => ()
      }
    }
  }
  ffi_restore_local_type_params(state, local_type_param_len)
  if method_lines.length() == 0 {
    lines.join("\n")
  } else {
    lines.join("\n") + "\n\n" + method_lines.join("\n\n")
  }
}

///|
/// Render `op_get` / `op_set` extern wrappers for an index signature
/// `[k: K]: V`. Returns `None` when V is unknown/never, since emitting
/// `op_get(...) -> JSValue?` would only widen the public surface without
/// helping the caller — the dynamic access can still be done via raw JS.
fn ffi_index_signature_accessor_decls(
  state : MoonBitJsFfiState,
  type_name : String,
  sig : (@ast.TsType, @ast.TsType),
) -> Array[String]? {
  let (key_type, value_type) = sig
  match value_type {
    @ast.TsType::Any | @ast.TsType::Never => return None
    _ => ()
  }
  let key_name = ffi_struct_field_type_name(state, key_type)
  let value_name = ffi_struct_field_type_name(state, value_type)
  // Avoid double-wrapping when the value type is already an Option (e.g.
  // `[k: string]: string | undefined`). The accessor semantics — `None` for
  // missing keys — fold the explicit-undefined case into the same outer
  // `None`, which matches how callers use op_get on a record.
  let getter_return = if value_name.has_suffix("?") {
    value_name
  } else {
    value_name + "?"
  }
  let getter = "pub extern \"js\" fn \{type_name}::op_get(self : \{type_name}, key : \{key_name}) -> \{getter_return} =\n" +
    "  #| (self, key) => { const v = self[key]; return v === undefined ? null : v; }"
  let setter = "pub extern \"js\" fn \{type_name}::op_set(self : \{type_name}, key : \{key_name}, value : \{value_name}) -> Unit =\n" +
    "  #| (self, key, value) => { self[key] = value; }"
  Some([getter, setter])
}

///|
fn ffi_named_struct_decl_to_moonbit(
  state : MoonBitJsFfiState,
  name : String,
  fields : Array[(String, @ast.TsType)],
) -> String {
  let type_name = ffi_type_identifier(name, "OpaqueType")
  let lines : Array[String] = [
    "#warnings(\"-9\")",
    "pub(all) struct \{type_name} {",
  ]
  let seen_fields : Array[String] = []
  for field in fields {
    let (field_name, field_type) = field
    let safe_name = ffi_sanitize_identifier(field_name, "field")
    if seen_fields.contains(safe_name) {
      continue
    }
    seen_fields.push(safe_name)
    let safe_type = ffi_struct_field_type_name(state, field_type)
    lines.push("  \{safe_name} : \{safe_type}")
  }
  lines.push("}")
  lines.join("\n")
}

///|
fn ffi_is_react_callable_component_interface(name : String) -> Bool {
  name == "FunctionComponent" ||
  name == "ForwardRefExoticComponent" ||
  name == "MemoExoticComponent" ||
  name == "NamedExoticComponent"
}

///|
fn ffi_interface_type_decl_to_moonbit(iface : @ast.TsInterface) -> String {
  let type_param_suffix = if ffi_should_preserve_interface_type_params(iface) {
    ffi_type_param_suffix(iface.type_params)
  } else {
    ""
  }
  "#warnings(\"-3\")\n#external\npub type " +
  ffi_type_identifier(iface.name, "OpaqueType") +
  type_param_suffix
}

///|
fn ffi_enum_decl_to_moonbit(enum_ : @ast.TsEnumDecl) -> String {
  let type_name = ffi_type_identifier(enum_.name, "GeneratedEnum")
  let lines : Array[String] = ["pub(all) enum \{type_name} {"]
  for item in ffi_enum_case_names(enum_) {
    let (case_name, _) = item
    lines.push("  " + case_name)
  }
  lines.push("}")
  lines.join("\n")
}

///|
fn ffi_binding_name(export_name : String) -> String {
  "__ts_mbt_" + ffi_to_snake_case(export_name)
}

///|
fn ffi_namespace_getter_name(export_name : String) -> String {
  "get_" + ffi_to_snake_case(export_name)
}

///|
fn ffi_fn_decl_key(fn_name : String) -> String {
  "fn:" + fn_name
}

///|
fn ffi_escape_moonbit_string(s : String) -> String {
  let mut result = ""
  for c in s {
    if c == '\\' {
      result += "\\\\"
    } else if c == '"' {
      result += "\\\""
    } else {
      result += c.to_string()
    }
  }
  result
}

///|
fn ffi_enum_to_js_name(type_name : String) -> String {
  "__ts_mbt_" + ffi_to_snake_case(type_name) + "_to_js"
}

///|
fn ffi_enum_from_js_name(type_name : String) -> String {
  "__ts_mbt_" + ffi_to_snake_case(type_name) + "_from_js"
}

///|
fn ffi_bridge_enum_to_js_name(type_name : String) -> String {
  "__ts_mbt_bridge_" + ffi_to_snake_case(type_name) + "_to_js"
}

///|
fn ffi_bridge_enum_to_js_optional_name(type_name : String) -> String {
  ffi_bridge_enum_to_js_name(type_name) + "_optional"
}

///|
fn ffi_enum_string_converter_decl(enum_ : @ast.TsEnumDecl) -> String? {
  let type_name = ffi_type_identifier(enum_.name, "GeneratedEnum")
  match ffi_enum_string_cases(enum_) {
    Some(cases) => {
      let to_js_name = ffi_enum_to_js_name(type_name)
      let from_js_name = ffi_enum_from_js_name(type_name)
      let to_js_optional_name = to_js_name + "_optional"
      let from_js_optional_name = from_js_name + "_optional"
      let lines : Array[String] = [
        "fn \{to_js_name}(value : \{type_name}) -> String {",
        "  match value {",
      ]
      for item in cases {
        let (case_name, value) = item
        lines.push(
          "    \{case_name} => \"\{ffi_escape_moonbit_string(value)}\"",
        )
      }
      lines.push("  }")
      lines.push("}")
      lines.push("")
      lines.push("fn \{from_js_name}(value : String) -> \{type_name} {")
      lines.push("  match value {")
      for item in cases {
        let (case_name, value) = item
        lines.push(
          "    \"\{ffi_escape_moonbit_string(value)}\" => \{case_name}",
        )
      }
      lines.push("    _ => abort(\"unexpected \{type_name} value: \" + value)")
      lines.push("  }")
      lines.push("}")
      lines.push("")
      lines.push(
        "fn \{to_js_optional_name}(value : \{type_name}?) -> String? {",
      )
      lines.push("  match value {")
      lines.push("    Some(value) => Some(\{to_js_name}(value))")
      lines.push("    None => None")
      lines.push("  }")
      lines.push("}")
      lines.push("")
      lines.push(
        "fn \{from_js_optional_name}(value : String?) -> \{type_name}? {",
      )
      lines.push("  match value {")
      lines.push("    Some(value) => Some(\{from_js_name}(value))")
      lines.push("    None => None")
      lines.push("  }")
      lines.push("}")
      Some(lines.join("\n"))
    }
    None => None
  }
}

///|
fn ffi_enum_int_converter_decl(enum_ : @ast.TsEnumDecl) -> String? {
  let type_name = ffi_type_identifier(enum_.name, "GeneratedEnum")
  match ffi_enum_int_cases(enum_) {
    Some(cases) => {
      let to_js_name = ffi_enum_to_js_name(type_name)
      let from_js_name = ffi_enum_from_js_name(type_name)
      let to_js_optional_name = to_js_name + "_optional"
      let from_js_optional_name = from_js_name + "_optional"
      let lines : Array[String] = [
        "fn \{to_js_name}(value : \{type_name}) -> Int {",
        "  match value {",
      ]
      for item in cases {
        let (case_name, value) = item
        lines.push("    \{case_name} => \{ffi_int_literal_expr(value)}")
      }
      lines.push("  }")
      lines.push("}")
      lines.push("")
      lines.push("fn \{from_js_name}(value : Int) -> \{type_name} {")
      for i, item in cases {
        let (case_name, value) = item
        let prefix = if i == 0 { "if" } else { "else if" }
        lines.push("  \{prefix} value == \{ffi_int_literal_expr(value)} {")
        lines.push("    \{case_name}")
        lines.push("  }")
      }
      if cases.length() == 0 {
        lines.push(
          "  abort(\"unexpected \{type_name} value: \" + value.to_string())",
        )
      } else {
        lines.push("  else {")
        lines.push(
          "    abort(\"unexpected \{type_name} value: \" + value.to_string())",
        )
        lines.push("  }")
      }
      lines.push("}")
      lines.push("")
      lines.push("fn \{to_js_optional_name}(value : \{type_name}?) -> Int? {")
      lines.push("  match value {")
      lines.push("    Some(value) => Some(\{to_js_name}(value))")
      lines.push("    None => None")
      lines.push("  }")
      lines.push("}")
      lines.push("")
      lines.push("fn \{from_js_optional_name}(value : Int?) -> \{type_name}? {")
      lines.push("  match value {")
      lines.push("    Some(value) => Some(\{from_js_name}(value))")
      lines.push("    None => None")
      lines.push("  }")
      lines.push("}")
      Some(lines.join("\n"))
    }
    None => None
  }
}

///|
fn ffi_enum_double_int_converter_decl(enum_ : @ast.TsEnumDecl) -> String? {
  let type_name = ffi_type_identifier(enum_.name, "GeneratedEnum")
  match ffi_enum_double_int_cases(enum_) {
    Some(cases) => {
      let to_js_name = ffi_enum_to_js_name(type_name)
      let from_js_name = ffi_enum_from_js_name(type_name)
      let to_js_optional_name = to_js_name + "_optional"
      let from_js_optional_name = from_js_name + "_optional"
      let lines : Array[String] = [
        "fn \{to_js_name}(value : \{type_name}) -> Double {",
        "  match value {",
      ]
      for item in cases {
        let (case_name, value) = item
        lines.push("    \{case_name} => \{ffi_double_literal_expr(value)}")
      }
      lines.push("  }")
      lines.push("}")
      lines.push("")
      lines.push("fn \{from_js_name}(value : Double) -> \{type_name} {")
      for i, item in cases {
        let (case_name, value) = item
        let prefix = if i == 0 { "if" } else { "else if" }
        lines.push("  \{prefix} value == \{ffi_double_literal_expr(value)} {")
        lines.push("    \{case_name}")
        lines.push("  }")
      }
      if cases.length() == 0 {
        lines.push(
          "  abort(\"unexpected \{type_name} value: \" + value.to_string())",
        )
      } else {
        lines.push("  else {")
        lines.push(
          "    abort(\"unexpected \{type_name} value: \" + value.to_string())",
        )
        lines.push("  }")
      }
      lines.push("}")
      lines.push("")
      lines.push(
        "fn \{to_js_optional_name}(value : \{type_name}?) -> Double? {",
      )
      lines.push("  match value {")
      lines.push("    Some(value) => Some(\{to_js_name}(value))")
      lines.push("    None => None")
      lines.push("  }")
      lines.push("}")
      lines.push("")
      lines.push(
        "fn \{from_js_optional_name}(value : Double?) -> \{type_name}? {",
      )
      lines.push("  match value {")
      lines.push("    Some(value) => Some(\{from_js_name}(value))")
      lines.push("    None => None")
      lines.push("  }")
      lines.push("}")
      Some(lines.join("\n"))
    }
    None => None
  }
}

///|
fn ffi_enum_raw_type(enum_ : @ast.TsEnumDecl) -> String? {
  match ffi_enum_string_cases(enum_) {
    Some(_) => Some("String")
    None =>
      match ffi_enum_int_cases(enum_) {
        Some(_) => Some("Int")
        None =>
          match ffi_enum_double_int_cases(enum_) {
            Some(_) => Some("Double")
            None => None
          }
      }
  }
}

///|
fn ffi_enum_js_extern_converter_decl(enum_ : @ast.TsEnumDecl) -> String? {
  let type_name = ffi_type_identifier(enum_.name, "GeneratedEnum")
  let raw_type = match ffi_enum_raw_type(enum_) {
    Some(raw_type) => raw_type
    None => return None
  }
  let to_js_name = ffi_enum_to_js_name(type_name)
  let from_js_name = ffi_enum_from_js_name(type_name)
  let to_js_optional_name = to_js_name + "_optional"
  let from_js_optional_name = from_js_name + "_optional"
  let lines : Array[String] = [
    "extern \"js\" fn \{to_js_name}(value : \{type_name}) -> \{raw_type} = \"\{to_js_name}\"",
    "extern \"js\" fn \{from_js_name}(value : \{raw_type}) -> \{type_name} = \"\{from_js_name}\"",
    "extern \"js\" fn \{to_js_optional_name}(value : \{type_name}?) -> \{raw_type}? = \"\{to_js_optional_name}\"",
    "extern \"js\" fn \{from_js_optional_name}(value : \{raw_type}?) -> \{type_name}? = \"\{from_js_optional_name}\"",
  ]
  Some(lines.join("\n"))
}

///|
fn ffi_int_literal_expr(value : Int) -> String {
  let raw = value.to_string()
  if raw == "-2147483648" {
    "(-2147483647 - 1)"
  } else {
    raw
  }
}

///|
fn ffi_double_literal_expr(value : Int) -> String {
  let raw = value.to_string()
  if raw == "-2147483648" {
    "(-536870912.0 * 4.0)"
  } else {
    raw + ".0"
  }
}

///|
fn ffi_int_cases_need_double(cases : Array[(String, Int)]) -> Bool {
  for item in cases {
    if item.1.to_string() == "-2147483648" {
      return true
    }
  }
  false
}

///|
fn ffi_enum_js_raw_literal(enum_ : @ast.TsEnumDecl, index : Int) -> String? {
  match ffi_enum_string_cases(enum_) {
    Some(cases) => {
      let (_, value) = cases[index]
      Some("\"\{json_escape_string(value)}\"")
    }
    None =>
      match ffi_enum_int_cases(enum_) {
        Some(cases) => Some(cases[index].1.to_string())
        None =>
          match ffi_enum_double_int_cases(enum_) {
            Some(cases) => Some(cases[index].1.to_string())
            None => None
          }
      }
  }
}

///|
fn ffi_enum_case_count(enum_ : @ast.TsEnumDecl) -> Int {
  match ffi_enum_string_cases(enum_) {
    Some(cases) => cases.length()
    None =>
      match ffi_enum_int_cases(enum_) {
        Some(cases) => cases.length()
        None =>
          match ffi_enum_double_int_cases(enum_) {
            Some(cases) => cases.length()
            None => 0
          }
      }
  }
}

///|
fn ffi_enum_runtime_js_converter_decl(enum_ : @ast.TsEnumDecl) -> String? {
  let type_name = ffi_type_identifier(enum_.name, "GeneratedEnum")
  let case_count = ffi_enum_case_count(enum_)
  if case_count == 0 {
    return None
  }
  let to_js_name = ffi_enum_to_js_name(type_name)
  let from_js_name = ffi_enum_from_js_name(type_name)
  let lines : Array[String] = [
    "export function \{to_js_name}(value) {",
    "  switch (value) {",
  ]
  for i in 0..<case_count {
    match ffi_enum_js_raw_literal(enum_, i) {
      Some(raw) => lines.push("    case \{i}: return \{raw};")
      None => return None
    }
  }
  lines.push(
    "    default: throw new Error(\"unexpected \{type_name} tag: \" + value);",
  )
  lines.push("  }")
  lines.push("}")
  lines.push("")
  lines.push("export function \{from_js_name}(value) {")
  lines.push("  switch (value) {")
  for i in 0..<case_count {
    match ffi_enum_js_raw_literal(enum_, i) {
      Some(raw) => lines.push("    case \{raw}: return \{i};")
      None => return None
    }
  }
  lines.push(
    "    default: throw new Error(\"unexpected \{type_name} value: \" + value);",
  )
  lines.push("  }")
  lines.push("}")
  lines.push("")
  lines.push("export function \{to_js_name}_optional(value) {")
  lines.push("  value = __ts_mbt_unwrap_option(value);")
  lines.push("  return value === undefined ? undefined : \{to_js_name}(value);")
  lines.push("}")
  lines.push("")
  lines.push("export function \{from_js_name}_optional(value) {")
  lines.push("  return value == null ? undefined : \{from_js_name}(value);")
  lines.push("}")
  Some(lines.join("\n"))
}

///|
fn ffi_should_use_js_enum_converters(enums : Array[@ast.TsEnumDecl]) -> Bool {
  enums.length() > 32
}

///|
fn ffi_enum_bridge_js_converter_decl(enum_ : @ast.TsEnumDecl) -> String? {
  let type_name = ffi_type_identifier(enum_.name, "GeneratedEnum")
  let to_js_name = ffi_bridge_enum_to_js_name(type_name)
  let to_js_optional_name = ffi_bridge_enum_to_js_optional_name(type_name)
  let lines : Array[String] = [
    "function \{to_js_name}(value) {",
    "  switch (value) {",
  ]
  let mut case_index = 0
  match ffi_enum_string_cases(enum_) {
    Some(cases) =>
      for item in cases {
        let (_, value) = item
        lines.push(
          "    case \{case_index}: return \"\{json_escape_string(value)}\";",
        )
        case_index += 1
      }
    None =>
      match ffi_enum_int_cases(enum_) {
        Some(cases) =>
          for item in cases {
            let (_, value) = item
            lines.push("    case \{case_index}: return \{value};")
            case_index += 1
          }
        None =>
          match ffi_enum_double_int_cases(enum_) {
            Some(cases) =>
              for item in cases {
                let (_, value) = item
                lines.push("    case \{case_index}: return \{value};")
                case_index += 1
              }
            None => return None
          }
      }
  }
  lines.push(
    "    default: throw new Error(\"unexpected \{type_name} tag: \" + value);",
  )
  lines.push("  }")
  lines.push("}")
  lines.push("")
  lines.push("function \{to_js_optional_name}(value) {")
  lines.push("  value = __ts_mbt_unwrap_option(value);")
  lines.push("  return value === undefined ? undefined : \{to_js_name}(value);")
  lines.push("}")
  Some(lines.join("\n"))
}

///|
fn ffi_direct_module_decl(module_spec : String, decl : String) -> String {
  "#module(\"" + ffi_escape_moonbit_string(module_spec) + "\")\n" + decl
}

///|
fn ffi_can_use_direct_module(module_spec : String) -> Bool {
  // MoonBit #module currently rejects relative specifiers like ./foo or ../foo.
  // Use direct module imports only for bare/node:/rooted specifiers and keep
  // the generated bridge.js fallback for relative runtime paths.
  module_spec != "" &&
  !module_spec.has_prefix("./") &&
  !module_spec.has_prefix("../")
}

///|
fn ffi_can_use_direct_runtime_export(
  module_spec : String,
  runtime_export_name : String,
) -> Bool {
  ffi_can_use_direct_module(module_spec) &&
  !(runtime_export_name == "default" &&
  ffi_module_spec_prefers_namespace_named_imports(module_spec))
}

///|
fn push_unique_ffi_section(
  seen_binding_names : Array[String],
  ffi_sections : Array[String],
  binding_name : String,
  section : String,
) -> Unit {
  if seen_binding_names.contains(binding_name) {
    return
  }
  seen_binding_names.push(binding_name)
  ffi_sections.push(section)
}

///|
fn push_unique_bridge_binding(
  seen_binding_names : Array[String],
  bridge_lines : Array[String],
  binding_name : String,
  line : String,
) -> Unit {
  if seen_binding_names.contains(binding_name) {
    return
  }
  seen_binding_names.push(binding_name)
  bridge_lines.push(line)
}

///|
fn ffi_bridge_function_line(
  binding_name : String,
  params : Array[String],
  expr : String,
) -> String {
  let params_str = params.join(", ")
  "export function \{binding_name}(\{params_str}) { return \{expr}; }"
}

///|
fn ffi_bridge_tuple_wrapper_line(
  binding_name : String,
  params : Array[String],
  expr : String,
  field_names : Array[String],
) -> String {
  let params_str = params.join(", ")
  let fields : Array[String] = []
  for i, field_name in field_names {
    fields.push("\{field_name}: tuple_[\{i}]")
  }
  let fields_str = fields.join(", ")
  "export function \{binding_name}(\{params_str}) { const tuple_ = \{expr}; return { \{fields_str} }; }"
}

///|
fn ffi_import_param_names(import_ : @ast.TsImport) -> Array[String] {
  let params : Array[String] = []
  for item in import_.params {
    let (name, _) = item
    params.push(ffi_sanitize_identifier(name, "arg"))
  }
  params
}

///|
fn ffi_func_param_names(func : @ast.TsFunc) -> Array[String] {
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
    params.push(ffi_sanitize_identifier(param_name, "arg"))
  }
  params
}

///|
fn ffi_callable_value_param_names(
  params : Array[@ast.TsType],
  runtime_export_name : String,
) -> Array[String] {
  let names : Array[String] = []
  for i, _ in params {
    names.push("arg" + i.to_string())
  }
  ffi_avoid_bridge_param_name_collisions(
    names,
    ffi_bridge_runtime_avoid_names(runtime_export_name),
  )
}

///|
fn ffi_bridge_runtime_avoid_names(
  runtime_export_name : String,
) -> Array[String] {
  if runtime_export_name.contains(".") {
    [ffi_runtime_export_root_name(runtime_export_name)]
  } else {
    []
  }
}

///|
fn ffi_avoid_bridge_param_name_collisions(
  names : Array[String],
  avoid_names : Array[String],
) -> Array[String] {
  let safe_names : Array[String] = []
  for name in names {
    let mut candidate = name
    if avoid_names.contains(candidate) {
      candidate += "_"
    }
    while safe_names.contains(candidate) {
      candidate += "_"
    }
    safe_names.push(candidate)
  }
  safe_names
}

///|
fn ffi_import_bridge_param_names(
  import_ : @ast.TsImport,
  runtime_export_name : String,
) -> Array[String] {
  ffi_avoid_bridge_param_name_collisions(
    ffi_import_param_names(import_),
    ffi_bridge_runtime_avoid_names(runtime_export_name),
  )
}

///|
fn ffi_func_bridge_param_names(
  func : @ast.TsFunc,
  runtime_export_name : String,
) -> Array[String] {
  ffi_avoid_bridge_param_name_collisions(
    ffi_func_param_names(func),
    ffi_bridge_runtime_avoid_names(runtime_export_name),
  )
}

///|
fn ffi_type_is_optional(type_ : @ast.TsType) -> Bool {
  match @checker.classify_optional_like_union(type_) {
    Some((_, is_optional)) => is_optional
    None => false
  }
}

///|
fn ffi_struct_fields_need_js_converter(
  enums : Array[@ast.TsEnumDecl],
  fields : Array[(String, @ast.TsType)],
) -> Bool {
  for field in fields {
    let (field_name, field_type) = field
    if ffi_sanitize_identifier(field_name, "field") != field_name ||
      ffi_type_is_optional(field_type) ||
      ffi_type_has_primitive_enum(enums, field_type) {
      return true
    }
  }
  false
}

///|
fn ffi_struct_converter_name(type_name : String) -> String {
  "__ts_mbt_to_js_" + ffi_to_snake_case(type_name)
}

///|
fn ffi_struct_converter_call_expr(name : String, expr : String) -> String {
  let type_name = ffi_type_identifier(name, "OpaqueType")
  let converter_name = ffi_struct_converter_name(type_name)
  "\{converter_name}(\{expr})"
}

///|
fn ffi_type_alias_constructor_suffix(type_ : @ast.TsType) -> String? {
  match @checker.classify_optional_like_union(type_) {
    Some((collapsed, _)) => return ffi_type_alias_constructor_suffix(collapsed)
    None => ()
  }
  match @checker.classify_transparent_intersection(type_) {
    Some(inner) => return ffi_type_alias_constructor_suffix(inner)
    None => ()
  }
  match type_ {
    Literal(_) | String_ => Some("string")
    Number | Int | NumberLiteral(_) => Some("double")
    BigInt | BigIntLiteral(_) => Some("int64")
    Boolean | BooleanLiteral(_) => Some("bool")
    Struct(name, _) | Named(name) | Applied(name, _) =>
      Some(ffi_to_snake_case(name))
    Array(inner) =>
      match ffi_type_alias_constructor_suffix(inner) {
        Some(suffix) => Some(suffix + "_array")
        None => None
      }
    _ => None
  }
}

///|
fn ffi_type_alias_constructor_param_type(
  state : MoonBitJsFfiState,
  type_ : @ast.TsType,
) -> String? {
  match @checker.classify_optional_like_union(type_) {
    Some((collapsed, _)) =>
      return ffi_type_alias_constructor_param_type(state, collapsed)
    None => ()
  }
  match @checker.classify_transparent_intersection(type_) {
    Some(inner) => return ffi_type_alias_constructor_param_type(state, inner)
    None => ()
  }
  match type_ {
    Literal(_) | String_ => Some("String")
    Number | Int | NumberLiteral(_) => Some("Double")
    BigInt | BigIntLiteral(_) => Some("Int64")
    Boolean | BooleanLiteral(_) => Some("Bool")
    // Bare `Promise` / `PromiseLike` references default to `Promise[JSValue]`
    // so they don't collide with the public `pub type Promise[X]`.
    Named("Promise") | Named("PromiseLike") => {
      state.needs_promise = true
      state.needs_js_any = true
      Some("Promise[JSValue]")
    }
    Applied("Promise", [inner]) | Applied("PromiseLike", [inner]) => {
      state.needs_promise = true
      match ffi_type_alias_constructor_param_type(state, inner) {
        Some(inner_type) => Some("Promise[\{inner_type}]")
        None => {
          state.needs_js_any = true
          Some("Promise[JSValue]")
        }
      }
    }
    Struct(name, _) | Named(name) | Applied(name, _) => {
      let base = ffi_mark_external_type(state, name)
      // Generic-preserved alias param types must include matching arity:
      // `_ZodIssueInvalidType` was registered with arity 1, so the param
      // type needs to read `_ZodIssueInvalidType[JSValue]` (or whatever
      // applied args are present). Fall through to the bare base name if
      // the registry doesn't know about it.
      let resolved_name = match base {
        _ =>
          match state.generic_type_params_by_name.get(base) {
            Some(type_params) =>
              if type_params.length() == 0 {
                base
              } else {
                let widened : Array[String] = []
                for _ in 0..<type_params.length() {
                  widened.push("JSValue")
                }
                state.needs_js_any = true
                base + "[" + widened.join(", ") + "]"
              }
            None => base
          }
      }
      Some(resolved_name)
    }
    Array(inner) =>
      match ffi_type_alias_constructor_param_type(state, inner) {
        Some(inner_type) => Some("Array[\{inner_type}]")
        None => None
      }
    _ => None
  }
}

///|
fn ffi_type_alias_constructor_for_item(
  state : MoonBitJsFfiState,
  alias_fn_prefix : String,
  item : @ast.TsType,
) -> FfiAliasConstructor? {
  match item {
    Null =>
      return Some({
        fn_name: alias_fn_prefix + "_null",
        binding_name: "__ts_mbt_" + alias_fn_prefix + "_null",
        params_src: "",
        bridge_params: [],
        bridge_expr: "null",
      })
    Undefined =>
      return Some({
        fn_name: alias_fn_prefix + "_undefined",
        binding_name: "__ts_mbt_" + alias_fn_prefix + "_undefined",
        params_src: "",
        bridge_params: [],
        bridge_expr: "undefined",
      })
    _ => ()
  }
  let suffix = match ffi_type_alias_constructor_suffix(item) {
    Some(suffix) => suffix
    None => return None
  }
  let param_type = match ffi_type_alias_constructor_param_type(state, item) {
    Some(param_type) => param_type
    None => return None
  }
  Some({
    fn_name: alias_fn_prefix + "_from_" + suffix,
    binding_name: "__ts_mbt_" + alias_fn_prefix + "_from_" + suffix,
    params_src: "value : \{param_type}",
    bridge_params: ["value"],
    bridge_expr: ffi_type_js_converter_expr(state, item, "value"),
  })
}

///|
fn ffi_type_alias_union_items(type_ : @ast.TsType) -> Array[@ast.TsType]? {
  match type_ {
    Union(items) => Some(items)
    Null
    | Undefined
    | Literal(_)
    | String_
    | Number
    | Int
    | NumberLiteral(_)
    | BigInt
    | BigIntLiteral(_)
    | Boolean
    | BooleanLiteral(_)
    | Struct(_, _)
    | Named(_)
    | Applied(_, _)
    | Array(_) => Some([type_])
    _ => None
  }
}

///|
fn ffi_type_alias_constructors(
  state : MoonBitJsFfiState,
  type_alias : @ast.TsTypeAlias,
) -> Array[FfiAliasConstructor] {
  if type_alias.type_params.length() > 0 {
    return []
  }
  let alias_type_name = ffi_type_identifier(type_alias.name, "OpaqueType")
  let alias_fn_prefix = ffi_to_snake_case(alias_type_name)
  let tagged_decl = state.tagged_union_decls_by_name.get(alias_type_name)
  // When a tagged-union decl exists, its cases carry the NORMALIZED
  // member types (qualified namespace refs resolved, `never` members
  // dropped) in enum order — helpers built from the raw alias body would
  // reference unresolved names (`JSX.Element` -> opaque `JSX_Element`)
  // and mis-index `$tag` after a dropped member.
  let items = match tagged_decl {
    Some(decl) => {
      let case_types : Array[@ast.TsType] = []
      for entry in decl.cases {
        let (_, inner) = entry
        case_types.push(inner)
      }
      case_types
    }
    None =>
      match ffi_type_alias_union_items(type_alias.type_) {
        Some(items) => items
        None => return []
      }
  }
  let ctors : Array[FfiAliasConstructor] = []
  let seen_names : Array[String] = []
  for index, item in items {
    // Tagged-union cases whose payload is a no-payload literal already have
    // a public enum constructor (`Boundary`) — generating an
    // `<alias>_from_string(value)` helper would produce an invalid
    // `{$tag, _0}` runtime shape that doesn't match MoonBit's no-payload
    // representation, and would silently accept arbitrary strings.
    if tagged_decl is Some(_) && tagged_union_case_is_no_payload(item) {
      continue
    }
    match ffi_type_alias_constructor_for_item(state, alias_fn_prefix, item) {
      Some(ctor) =>
        if !seen_names.contains(ctor.fn_name) {
          seen_names.push(ctor.fn_name)
          let final_ctor = match tagged_decl {
            Some(_) =>
              {
                ..ctor,
                bridge_expr: "{ \"$tag\": " +
                index.to_string() +
                ", \"_0\": value }",
              }
            None => ctor
          }
          ctors.push(final_ctor)
        }
      None => ()
    }
  }
  ctors
}

///|
fn ffi_alias_constructor_decl(
  state : MoonBitJsFfiState,
  alias_type_name : String,
  ctor : FfiAliasConstructor,
) -> String {
  // Generic-preserved alias types (e.g. `_ZodIssueInvalidType[I]`) must
  // receive a matching arity suffix at the constructor's declared return
  // type. Without this the bare `_ZodIssueInvalidType` reference fails
  // `[4040]` (arity mismatch). Widen each slot to `JSValue` since the
  // raw constructor body has no type args to forward.
  let return_type = match
    state.generic_type_params_by_name.get(alias_type_name) {
    Some(type_params) =>
      if type_params.length() == 0 {
        alias_type_name
      } else {
        let widened : Array[String] = []
        for _ in 0..<type_params.length() {
          widened.push("JSValue")
        }
        state.needs_js_any = true
        alias_type_name + "[" + widened.join(", ") + "]"
      }
    None => alias_type_name
  }
  "pub extern \"js\" fn \{ctor.fn_name}(\{ctor.params_src}) -> \{return_type} = \"\{ctor.binding_name}\""
}

///|
fn ffi_alias_constructor_bridge_line(ctor : FfiAliasConstructor) -> String {
  ffi_bridge_function_line(
    ctor.binding_name,
    ctor.bridge_params,
    ctor.bridge_expr,
  )
}

///|
fn ffi_type_alias_map_by_type_name(
  modules : Map[String, DeclModuleInfo],
) -> Map[String, @ast.TsTypeAlias] {
  let aliases : Map[String, @ast.TsTypeAlias] = {}
  for entry in modules {
    let info = entry.1
    for type_alias in info.module_.type_aliases {
      let type_name = ffi_type_identifier(type_alias.name, "OpaqueType")
      match aliases.get(type_name) {
        Some(_) => ()
        None => aliases[type_name] = type_alias
      }
    }
  }
  aliases
}

///|
fn ffi_named_type_is_generated_struct(
  state : MoonBitJsFfiState,
  name : String,
) -> Bool {
  state.struct_type_names.contains(ffi_type_identifier(name, "OpaqueType"))
}

///|
fn ffi_bridge_named_enum_to_js_converter_call_expr(
  name : String,
  expr : String,
  optional : Bool,
) -> String {
  let type_name = ffi_type_identifier(name, "GeneratedEnum")
  let converter_name = if optional {
    ffi_bridge_enum_to_js_optional_name(type_name)
  } else {
    ffi_bridge_enum_to_js_name(type_name)
  }
  "\{converter_name}(\{expr})"
}

///|
fn ffi_type_js_converter_expr(
  state : MoonBitJsFfiState,
  type_ : @ast.TsType,
  expr : String,
) -> String {
  match @checker.classify_optional_like_union(type_) {
    Some((collapsed, is_optional)) => {
      if !is_optional {
        return ffi_type_js_converter_expr(state, collapsed, expr)
      }
      return match collapsed {
        Boolean => "__ts_mbt_unwrap_bool_option(\{expr})"
        Struct(name, _) => ffi_struct_converter_call_expr(name, expr)
        Named(name) if ffi_named_type_is_generated_struct(state, name) =>
          ffi_struct_converter_call_expr(name, expr)
        Named(name) if state.tagged_union_decls_by_name.contains(name) =>
          match state.tagged_union_decls_by_name.get(name) {
            Some(decl) => {
              // MoonBit JS encodes `Option[T]` for non-primitive `T` as the
              // raw value (or `undefined` for None) without the `{$tag, _0}`
              // wrap. Going through the generic option-unwrap would
              // mis-read tagged-union values whose own `$tag` happens to be
              // `1` (e.g. no-payload literal cases), so route the raw value
              // straight into the to-JS converter.
              let converted = tagged_union_to_js_expression_with_nested(
                decl,
                expr,
                state.tagged_union_decls_by_name,
                struct_converter_names=state.struct_type_names,
              )
              "(\{expr} == null ? undefined : \{converted})"
            }
            None => "__ts_mbt_unwrap_option(\{expr})"
          }
        Applied(name, _) if ffi_named_type_is_generated_struct(state, name) =>
          ffi_struct_converter_call_expr(name, expr)
        _ => "__ts_mbt_unwrap_option(\{expr})"
      }
    }
    None => ()
  }
  match @checker.classify_transparent_intersection(type_) {
    Some(inner) => return ffi_type_js_converter_expr(state, inner, expr)
    None => ()
  }
  match type_ {
    Struct(name, _) => ffi_struct_converter_call_expr(name, expr)
    Named(name) if ffi_named_type_is_generated_struct(state, name) =>
      ffi_struct_converter_call_expr(name, expr)
    Named(name) if state.tagged_union_decls_by_name.contains(name) =>
      match state.tagged_union_decls_by_name.get(name) {
        Some(decl) =>
          tagged_union_to_js_expression_with_nested(
            decl,
            expr,
            state.tagged_union_decls_by_name,
            struct_converter_names=state.struct_type_names,
          )
        None => expr
      }
    Applied(name, _) if ffi_named_type_is_generated_struct(state, name) =>
      ffi_struct_converter_call_expr(name, expr)
    Array(inner) => {
      let item_expr = ffi_type_js_converter_expr(state, inner, "item")
      if item_expr == "item" {
        expr
      } else {
        "Array.isArray(\{expr}) ? \{expr}.map((item) => \{item_expr}) : \{expr}"
      }
    }
    // Anonymous heterogeneous union encountered directly on a parameter
    // type (e.g. `string | string[]` on `new StringChunk(value)`). The
    // synthesised union alias was already registered when the type
    // signature was rendered; route through its to-JS converter so the
    // MoonBit `{$tag, _0}` shape gets unwrapped to the raw JS value
    // before reaching the call.
    Union(parts) =>
      match tagged_union_cases(parts) {
        Some(cases) => {
          let synth_name = ffi_inline_union_synthesized_name(cases)
          match state.tagged_union_decls_by_name.get(synth_name) {
            Some(decl) =>
              tagged_union_to_js_expression_with_nested(
                decl,
                expr,
                state.tagged_union_decls_by_name,
                struct_converter_names=state.struct_type_names,
              )
            None => expr
          }
        }
        None => expr
      }
    _ => expr
  }
}

///|
fn ffi_type_js_struct_field_converter_expr(
  state : MoonBitJsFfiState,
  type_ : @ast.TsType,
  expr : String,
) -> String {
  match @checker.classify_optional_like_union(type_) {
    Some((collapsed, is_optional)) => {
      if !is_optional {
        return ffi_type_js_struct_field_converter_expr(state, collapsed, expr)
      }
      return match collapsed {
        Named(name) if ffi_named_type_is_primitive_enum_in(state.enums, name) =>
          ffi_bridge_named_enum_to_js_converter_call_expr(name, expr, true)
        Applied(name, _) if ffi_named_type_is_primitive_enum_in(
            state.enums,
            name,
          ) => ffi_bridge_named_enum_to_js_converter_call_expr(name, expr, true)
        _ => ffi_type_js_converter_expr(state, type_, expr)
      }
    }
    None => ()
  }
  match @checker.classify_transparent_intersection(type_) {
    Some(inner) =>
      return ffi_type_js_struct_field_converter_expr(state, inner, expr)
    None => ()
  }
  match type_ {
    Named(name) if ffi_named_type_is_primitive_enum_in(state.enums, name) =>
      ffi_bridge_named_enum_to_js_converter_call_expr(name, expr, false)
    Applied(name, _) if ffi_named_type_is_primitive_enum_in(state.enums, name) =>
      ffi_bridge_named_enum_to_js_converter_call_expr(name, expr, false)
    Array(inner) => {
      let item_expr = ffi_type_js_struct_field_converter_expr(
        state, inner, "item",
      )
      if item_expr == "item" {
        expr
      } else {
        "Array.isArray(\{expr}) ? \{expr}.map((item) => \{item_expr}) : \{expr}"
      }
    }
    _ => ffi_type_js_converter_expr(state, type_, expr)
  }
}

///|
fn ffi_struct_field_is_call_signature(
  field_name : String,
  field_type : @ast.TsType,
) -> Bool {
  if ffi_sanitize_identifier(field_name, "field") != "_call_" {
    return false
  }
  match field_type {
    Func(_, _) => true
    _ => false
  }
}

///|
fn ffi_struct_has_call_signature(fields : Array[(String, @ast.TsType)]) -> Bool {
  for field in fields {
    let (field_name, field_type) = field
    if ffi_struct_field_is_call_signature(field_name, field_type) {
      return true
    }
  }
  false
}

///|
fn ffi_struct_js_converter_decl(
  state : MoonBitJsFfiState,
  name : String,
  fields : Array[(String, @ast.TsType)],
) -> String {
  let type_name = ffi_type_identifier(name, "OpaqueType")
  let converter_name = ffi_struct_converter_name(type_name)
  let has_call_signature = ffi_struct_has_call_signature(fields)
  let lines : Array[String] = [
    "function \{converter_name}(value) {",
    "  value = __ts_mbt_unwrap_option(value);",
    "  if (value == null) return undefined;",
  ]
  if has_call_signature {
    lines.push("  if (typeof value === \"function\") return value;")
    lines.push("  const result = (...args) => value[\"_call_\"](...args);")
  } else {
    lines.push("  const result = {};")
  }
  lines.push("  let field;")
  for field in fields {
    let (field_name, field_type) = field
    let safe_name = ffi_sanitize_identifier(field_name, "field")
    if has_call_signature &&
      ffi_struct_field_is_call_signature(field_name, field_type) {
      continue
    }
    let source_key = json_escape_string(safe_name)
    let target_key = json_escape_string(field_name)
    let converted_field = ffi_type_js_struct_field_converter_expr(
      state, field_type, "field",
    )
    lines.push("  field = value[\"\{source_key}\"];")
    lines.push("  field = \{converted_field};")
    if ffi_type_is_optional(field_type) {
      lines.push(
        "  if (field !== undefined) result[\"\{target_key}\"] = field;",
      )
    } else {
      lines.push("  result[\"\{target_key}\"] = field;")
    }
  }
  lines.push("  return result;")
  lines.push("}")
  lines.join("\n")
}

///|
fn ffi_type_needs_js_arg_conversion(
  state : MoonBitJsFfiState,
  type_ : @ast.TsType,
) -> Bool {
  ffi_type_js_converter_expr(state, type_, "arg") != "arg"
}

///|
fn ffi_import_needs_js_arg_conversion(
  state : MoonBitJsFfiState,
  import_ : @ast.TsImport,
) -> Bool {
  for item in import_.params {
    let (_, type_) = item
    if ffi_type_needs_js_arg_conversion(state, type_) {
      return true
    }
  }
  false
}

///|
/// Like `ffi_import_needs_js_arg_conversion` but evaluated against the
/// string-subset wrapper's effective param types (`string | string[]`
/// narrowed to plain `String`). Used to decide whether the subset
/// wrapper can compile to a direct `extern "js" fn ... = "<runtime>"`
/// even when the original signature had a tagged-enum converter that
/// would otherwise force the wrapper through bridge.js.
fn ffi_import_subset_needs_js_arg_conversion(
  state : MoonBitJsFfiState,
  import_ : @ast.TsImport,
) -> Bool {
  for item in import_.params {
    let (_, type_) = item
    if ffi_type_is_string_or_string_array_union(type_) {
      // The subset replaces this slot with plain `String`; no JS
      // conversion needed regardless of how the union would render.
      continue
    }
    if ffi_type_needs_js_arg_conversion(state, type_) {
      return true
    }
  }
  false
}

///|
fn ffi_func_needs_js_arg_conversion(
  state : MoonBitJsFfiState,
  func : @ast.TsFunc,
) -> Bool {
  for param in func.params {
    if ffi_type_needs_js_arg_conversion(state, param.type_) {
      return true
    }
  }
  false
}

///|
/// Subset variant: see `ffi_import_subset_needs_js_arg_conversion`.
fn ffi_func_subset_needs_js_arg_conversion(
  state : MoonBitJsFfiState,
  func : @ast.TsFunc,
) -> Bool {
  for param in func.params {
    if ffi_type_is_string_or_string_array_union(param.type_) {
      continue
    }
    if ffi_type_needs_js_arg_conversion(state, param.type_) {
      return true
    }
  }
  false
}

///|
fn ffi_callable_value_needs_js_arg_conversion(
  state : MoonBitJsFfiState,
  params : Array[@ast.TsType],
) -> Bool {
  for param in params {
    if ffi_type_needs_js_arg_conversion(state, param) {
      return true
    }
  }
  false
}

///|
fn ffi_type_needs_js_return_conversion(type_ : @ast.TsType) -> Bool {
  match @checker.classify_optional_like_union(type_) {
    Some((collapsed, is_optional)) => is_optional && collapsed == Boolean
    None => false
  }
}

///|
/// State-aware variant: also flags returns whose type is a tagged-union
/// alias known to the FFI state, since those need a `__ts_mbt_<alias>_from_js`
/// wrapper around the raw JS value.
fn ffi_type_needs_js_return_conversion_with_state(
  state : MoonBitJsFfiState,
  type_ : @ast.TsType,
) -> Bool {
  if ffi_type_needs_js_return_conversion(type_) {
    return true
  }
  match @checker.classify_optional_like_union(type_) {
    Some((collapsed, is_optional)) =>
      if is_optional {
        match collapsed {
          Named(name) =>
            return ffi_tagged_union_return_is_safe_to_wrap(state, name)
          _ => ()
        }
      }
    None => ()
  }
  match type_ {
    Named(name) => ffi_tagged_union_return_is_safe_to_wrap(state, name)
    _ => false
  }
}

///|
/// Decide whether the auto-emitted return-side `__ts_mbt_<alias>_from_js`
/// wrapper would actually run cleanly in `bridge.js`. The discriminator
/// `instanceof <Name>` requires the named JS class to be in scope; for
/// alias surfaces synthesised from ambient `node:*` exports those classes
/// are not reachable from the generated bridge module, so we skip the
/// auto-wrap and let the raw JS value flow through unchanged. Tagged
/// unions whose cases all use primitive `typeof` / `Array.isArray` /
/// strict-equality predicates are always safe to wrap.
fn ffi_tagged_union_return_is_safe_to_wrap(
  state : MoonBitJsFfiState,
  name : String,
) -> Bool {
  match state.tagged_union_decls_by_name.get(name) {
    Some(decl) => {
      for entry in decl.cases {
        let (_, inner) = entry
        match tagged_union_case_discriminator(inner) {
          Some(InstanceOfNamed(_)) => return false
          // Function payloads stay on the raw passthrough: the generic
          // wrapper would need closure conversion in both directions,
          // which the auto-wrap doesn't model.
          Some(TypeofFunction) => return false
          _ => ()
        }
      }
      true
    }
    None => false
  }
}

///|
fn ffi_import_needs_js_return_conversion(
  state : MoonBitJsFfiState,
  import_ : @ast.TsImport,
) -> Bool {
  ffi_type_needs_js_return_conversion_with_state(state, import_.return_type)
}

///|
fn ffi_func_needs_js_return_conversion(
  state : MoonBitJsFfiState,
  func : @ast.TsFunc,
) -> Bool {
  ffi_type_needs_js_return_conversion_with_state(state, func.return_type)
}

///|
fn ffi_type_js_return_expr(
  state : MoonBitJsFfiState,
  type_ : @ast.TsType,
  expr : String,
) -> String {
  match @checker.classify_optional_like_union(type_) {
    Some((collapsed, is_optional)) => {
      if is_optional && collapsed == Boolean {
        return "__ts_mbt_wrap_bool_option(\{expr})"
      }
      // `Hires?` returns: MoonBit JS encodes `Option[T]` for non-primitive
      // `T` as the raw value with `undefined` for `None` (instead of the
      // `{$tag, _0}` wrap form), so we just need to convert the raw JS
      // value to a Hires shape and pass `undefined` through unchanged.
      if is_optional {
        match collapsed {
          Named(name) if ffi_tagged_union_return_is_safe_to_wrap(state, name) => {
            let from_name = tagged_union_from_js_function_name(name)
            return "(\{expr} == null ? undefined : \{from_name}(\{expr}))"
          }
          _ => ()
        }
      }
    }
    None => ()
  }
  match type_ {
    Named(name) if ffi_tagged_union_return_is_safe_to_wrap(state, name) => {
      let from_name = tagged_union_from_js_function_name(name)
      "\{from_name}(\{expr})"
    }
    _ => expr
  }
}

///|
fn ffi_params_call_args_with_names(
  state : MoonBitJsFfiState,
  params : Array[(String, @ast.TsType)],
  names : Array[String],
) -> Array[String] {
  let args : Array[String] = []
  for i, param in params {
    let (_, type_) = param
    args.push(ffi_type_js_converter_expr(state, type_, names[i]))
  }
  args
}

///|
fn ffi_import_call_args_with_names(
  state : MoonBitJsFfiState,
  import_ : @ast.TsImport,
  names : Array[String],
) -> Array[String] {
  let args : Array[String] = []
  for i, item in import_.params {
    let (_, type_) = item
    args.push(ffi_type_js_converter_expr(state, type_, names[i]))
  }
  args
}

///|
fn ffi_func_call_args_with_names(
  state : MoonBitJsFfiState,
  func : @ast.TsFunc,
  names : Array[String],
) -> Array[String] {
  let args : Array[String] = []
  for i, param in func.params {
    args.push(ffi_type_js_converter_expr(state, param.type_, names[i]))
  }
  args
}

///|
fn ffi_callable_value_call_args_with_names(
  state : MoonBitJsFfiState,
  params : Array[@ast.TsType],
  names : Array[String],
) -> Array[String] {
  let args : Array[String] = []
  for i, param in params {
    args.push(ffi_type_js_converter_expr(state, param, names[i]))
  }
  args
}

///|
fn ffi_import_decl_to_moonbit(
  state : MoonBitJsFfiState,
  import_ : @ast.TsImport,
) -> String {
  let params : Array[String] = []
  for item in import_.params {
    let (name, type_) = item
    let param_name = ffi_sanitize_identifier(name, "arg")
    let param_type = ffi_type_name(state, type_)
    params.push("\{param_name} : \{param_type}")
  }
  let return_type = ffi_type_name(state, import_.return_type)
  let fn_name = ffi_value_fn_name(import_.name)
  let params_str = params.join(", ")
  "pub extern \"js\" fn \{fn_name}(\{params_str}) -> \{return_type} = \"\{ffi_binding_name(import_.name)}\""
}

///|
fn ffi_import_decl_to_moonbit_direct(
  state : MoonBitJsFfiState,
  import_ : @ast.TsImport,
  runtime_export_name : String,
  module_spec : String,
) -> String {
  let params : Array[String] = []
  for item in import_.params {
    let (name, type_) = item
    let param_name = ffi_sanitize_identifier(name, "arg")
    let param_type = ffi_type_name(state, type_)
    params.push("\{param_name} : \{param_type}")
  }
  let return_type = ffi_type_name(state, import_.return_type)
  let fn_name = ffi_value_fn_name(import_.name)
  let params_str = params.join(", ")
  ffi_direct_module_decl(
    module_spec,
    "pub extern \"js\" fn \{fn_name}(\{params_str}) -> \{return_type} = \"\{runtime_export_name}\"",
  )
}

///|
fn ffi_import_string_subset_decl_to_moonbit(
  state : MoonBitJsFfiState,
  import_ : @ast.TsImport,
) -> String {
  let params : Array[String] = []
  for item in import_.params {
    let (name, type_) = item
    let param_name = ffi_sanitize_identifier(name, "arg")
    let param_type = ffi_func_string_subset_param_type_name(state, type_)
    params.push("\{param_name} : \{param_type}")
  }
  let return_type = ffi_type_name(state, import_.return_type)
  let fn_name = ffi_func_string_subset_name(import_.name)
  let params_str = params.join(", ")
  "pub extern \"js\" fn \{fn_name}(\{params_str}) -> \{return_type} = \"\{ffi_func_string_subset_binding_name(import_.name)}\""
}

///|
fn ffi_import_string_subset_decl_to_moonbit_direct(
  state : MoonBitJsFfiState,
  import_ : @ast.TsImport,
  runtime_export_name : String,
  module_spec : String,
) -> String {
  let params : Array[String] = []
  for item in import_.params {
    let (name, type_) = item
    let param_name = ffi_sanitize_identifier(name, "arg")
    let param_type = ffi_func_string_subset_param_type_name(state, type_)
    params.push("\{param_name} : \{param_type}")
  }
  let return_type = ffi_type_name(state, import_.return_type)
  let fn_name = ffi_func_string_subset_name(import_.name)
  let params_str = params.join(", ")
  ffi_direct_module_decl(
    module_spec,
    "pub extern \"js\" fn \{fn_name}(\{params_str}) -> \{return_type} = \"\{runtime_export_name}\"",
  )
}

///|
fn ffi_func_decl_to_moonbit(
  state : MoonBitJsFfiState,
  func : @ast.TsFunc,
) -> String {
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
    let safe_name = ffi_sanitize_identifier(param_name, "arg")
    let safe_type = ffi_type_name(state, param.type_)
    params.push("\{safe_name} : \{safe_type}")
  }
  let return_type = ffi_type_name(state, func.return_type)
  let fn_name = ffi_value_fn_name(func.name)
  let params_str = params.join(", ")
  "pub extern \"js\" fn \{fn_name}(\{params_str}) -> \{return_type} = \"\{ffi_binding_name(func.name)}\""
}

///|
fn ffi_func_decl_to_moonbit_direct(
  state : MoonBitJsFfiState,
  func : @ast.TsFunc,
  runtime_export_name : String,
  module_spec : String,
) -> String {
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
    let safe_name = ffi_sanitize_identifier(param_name, "arg")
    let safe_type = ffi_type_name(state, param.type_)
    params.push("\{safe_name} : \{safe_type}")
  }
  let return_type = ffi_type_name(state, func.return_type)
  let fn_name = ffi_value_fn_name(func.name)
  let params_str = params.join(", ")
  ffi_direct_module_decl(
    module_spec,
    "pub extern \"js\" fn \{fn_name}(\{params_str}) -> \{return_type} = \"\{runtime_export_name}\"",
  )
}

///|
fn ffi_func_string_subset_name(func_name : String) -> String {
  ffi_value_fn_name(func_name) + "_string"
}

///|
fn ffi_func_string_subset_binding_name(func_name : String) -> String {
  "__ts_mbt_" + ffi_func_string_subset_name(func_name)
}

///|
fn ffi_is_node_assert_module_spec(module_spec : String) -> Bool {
  module_spec == "node:assert" || module_spec == "assert"
}

///|
fn ffi_is_node_util_module_spec(module_spec : String) -> Bool {
  module_spec == "node:util" || module_spec == "util"
}

///|
fn ffi_is_react_router_module_spec(module_spec : String) -> Bool {
  module_spec == "react-router" || module_spec.contains("/react-router")
}

///|
fn ffi_is_jose_module_spec(module_spec : String) -> Bool {
  module_spec == "jose" || module_spec.contains("/jose")
}

///|
fn ffi_node_assert_primitive_wrapper(
  source_name : String,
) -> (String, Array[String], Array[String], Array[String])? {
  let base_name = ffi_value_fn_name(source_name)
  match source_name {
    "ok" | "assertOk" =>
      Some(
        (
          base_name + "_bool",
          ["value : Bool", "message : String?"],
          ["value", "message"],
          ["value", "__ts_mbt_unwrap_option(message)"],
        ),
      )
    "equal" | "assertEqual" =>
      Some(
        (
          base_name + "_double",
          ["actual : Double", "expected : Double", "message : String?"],
          ["actual", "expected", "message"],
          ["actual", "expected", "__ts_mbt_unwrap_option(message)"],
        ),
      )
    "strictEqual" | "assertStrictEqual" =>
      Some(
        (
          base_name + "_string",
          ["actual : String", "expected : String", "message : String?"],
          ["actual", "expected", "message"],
          ["actual", "expected", "__ts_mbt_unwrap_option(message)"],
        ),
      )
    "notEqual" | "assertNotEqual" =>
      Some(
        (
          base_name + "_double",
          ["actual : Double", "expected : Double", "message : String?"],
          ["actual", "expected", "message"],
          ["actual", "expected", "__ts_mbt_unwrap_option(message)"],
        ),
      )
    "notStrictEqual" | "assertNotStrictEqual" =>
      Some(
        (
          base_name + "_string",
          ["actual : String", "expected : String", "message : String?"],
          ["actual", "expected", "message"],
          ["actual", "expected", "__ts_mbt_unwrap_option(message)"],
        ),
      )
    _ => None
  }
}

///|
fn ffi_node_assert_primitive_decl(source_name : String) -> String? {
  match ffi_node_assert_primitive_wrapper(source_name) {
    Some((fn_name, moonbit_params, _, _)) => {
      let params_src = moonbit_params.join(", ")
      Some(
        "pub extern \"js\" fn \{fn_name}(\{params_src}) -> Unit = \"__ts_mbt_\{fn_name}\"",
      )
    }
    None => None
  }
}

///|
fn ffi_func_string_subset_decl_to_moonbit(
  state : MoonBitJsFfiState,
  func : @ast.TsFunc,
) -> String {
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
    let safe_name = ffi_sanitize_identifier(param_name, "arg")
    let safe_type = ffi_func_string_subset_param_type_name(state, param.type_)
    params.push("\{safe_name} : \{safe_type}")
  }
  let return_type = ffi_type_name(state, func.return_type)
  let fn_name = ffi_func_string_subset_name(func.name)
  let params_str = params.join(", ")
  "pub extern \"js\" fn \{fn_name}(\{params_str}) -> \{return_type} = \"\{ffi_func_string_subset_binding_name(func.name)}\""
}

///|
fn ffi_func_string_subset_decl_to_moonbit_direct(
  state : MoonBitJsFfiState,
  func : @ast.TsFunc,
  runtime_export_name : String,
  module_spec : String,
) -> String {
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
    let safe_name = ffi_sanitize_identifier(param_name, "arg")
    let safe_type = ffi_func_string_subset_param_type_name(state, param.type_)
    params.push("\{safe_name} : \{safe_type}")
  }
  let return_type = ffi_type_name(state, func.return_type)
  let fn_name = ffi_func_string_subset_name(func.name)
  let params_str = params.join(", ")
  ffi_direct_module_decl(
    module_spec,
    "pub extern \"js\" fn \{fn_name}(\{params_str}) -> \{return_type} = \"\{runtime_export_name}\"",
  )
}

///|
fn ffi_value_decl_to_moonbit(
  state : MoonBitJsFfiState,
  value : @ast.TsValueDecl,
) -> String {
  let return_type = ffi_type_name(state, value.type_)
  let fn_name = ffi_namespace_getter_name(value.name)
  "pub extern \"js\" fn \{fn_name}() -> \{return_type} = \"__ts_mbt_get_\{ffi_to_snake_case(value.name)}\""
}

///|
fn ffi_callable_value_decl_to_moonbit(
  state : MoonBitJsFfiState,
  value : @ast.TsValueDecl,
  params : Array[@ast.TsType],
  return_type : @ast.TsType,
) -> String {
  let moonbit_params : Array[String] = []
  for i, param in params {
    let param_name = "arg" + i.to_string()
    let safe_type = ffi_callable_value_param_type_name(state, param)
    moonbit_params.push("\{param_name} : \{safe_type}")
  }
  let return_type_src = ffi_type_name(state, return_type)
  let fn_name = ffi_value_fn_name(value.name)
  let params_str = moonbit_params.join(", ")
  "pub extern \"js\" fn \{fn_name}(\{params_str}) -> \{return_type_src} = \"\{ffi_binding_name(value.name)}\""
}

///|
fn ffi_class_ctor_binding_name(class_name : String) -> String {
  "__ts_mbt_new_" + ffi_to_snake_case(class_name)
}

///|
fn ffi_class_method_binding_name(
  class_name : String,
  method_name : String,
) -> String {
  "__ts_mbt_" +
  ffi_to_snake_case(class_name) +
  "_" +
  ffi_to_snake_case(method_name)
}

///|
fn ffi_class_property_getter_binding_name(
  class_name : String,
  property_name : String,
) -> String {
  "__ts_mbt_get_" +
  ffi_to_snake_case(class_name) +
  "_" +
  ffi_to_snake_case(property_name)
}

///|
fn ffi_class_property_setter_binding_name(
  class_name : String,
  property_name : String,
) -> String {
  "__ts_mbt_set_" +
  ffi_to_snake_case(class_name) +
  "_" +
  ffi_to_snake_case(property_name)
}

///|
fn ffi_class_type_name(class_name : String) -> String {
  ffi_type_identifier(class_name, "OpaqueType")
}

///|
fn ffi_class_type_decl(class_ : @ast.TsClassDecl) -> String {
  let suffix = if ffi_should_preserve_class_type_params(class_) {
    ffi_type_param_suffix(class_.type_params)
  } else {
    ""
  }
  "#warnings(\"-3\")\n#external\npub type " +
  ffi_class_type_name(class_.name) +
  suffix
}

///|
fn ffi_class_constructor_decl_to_moonbit(
  state : MoonBitJsFfiState,
  class_ : @ast.TsClassDecl,
) -> String? {
  if !class_.is_constructible {
    return None
  }
  let preserve = ffi_should_preserve_class_type_params(class_)
  let active_type_params = if preserve { class_.type_params } else { [] }
  let local_type_param_len = ffi_push_local_type_params(
    state, active_type_params,
  )
  let params : Array[String] = []
  let arg_names : Array[String] = []
  match class_.constructor_params {
    Some(constructor_params) =>
      for param in constructor_params {
        let (name, type_) = param
        let safe_name = ffi_sanitize_identifier(name, "arg")
        let safe_type = ffi_type_name(state, type_)
        params.push("\{safe_name} : \{safe_type}")
        arg_names.push(safe_name)
      }
    None => ()
  }
  let ctor_params = params.join(", ")
  let ctor_name = ffi_to_snake_case(class_.name)
  let class_type_name = ffi_class_type_name(class_.name)
  let binding_name = ffi_class_ctor_binding_name(class_.name)
  let result = if preserve {
    let type_param_suffix = ffi_type_param_suffix(active_type_params)
    let fn_prefix = ffi_function_type_param_prefix(active_type_params)
    let extern_params : Array[String] = []
    for arg in arg_names {
      extern_params.push("\{arg} : JSValue")
    }
    let extern_params_src = extern_params.join(", ")
    let extern_name = "_new_\{ctor_name}_extern_js"
    let cast_args : Array[String] = []
    for arg in arg_names {
      cast_args.push("unsafeCast(\{arg})")
    }
    let cast_args_src = cast_args.join(", ")
    state.needs_js_any = true
    let extern_decl = "extern \"js\" fn \{extern_name}(\{extern_params_src}) -> JSValue = \"\{binding_name}\""
    let wrapper_decl = "pub \{fn_prefix} new_\{ctor_name}(\{ctor_params}) -> \{class_type_name}\{type_param_suffix} {\n  unsafeCast(\{extern_name}(\{cast_args_src}))\n}"
    "\{extern_decl}\n\n\{wrapper_decl}"
  } else {
    "pub extern \"js\" fn new_\{ctor_name}(\{ctor_params}) -> \{class_type_name} = \"\{binding_name}\""
  }
  ffi_restore_local_type_params(state, local_type_param_len)
  Some(result)
}

///|
fn ffi_class_method_decl_to_moonbit(
  state : MoonBitJsFfiState,
  class_ : @ast.TsClassDecl,
  class_method : @ast.TsClassMethodDecl,
) -> String {
  // Static methods don't take a `self`, so they shouldn't capture the
  // class's instance-level type parameters either — emitting `[E, S, B]`
  // on a static method that only references class-level state would
  // trip MoonBit's `unused_type_parameter` warning ([4027]) without
  // actually adding value at the call site.
  let preserve = ffi_should_preserve_class_type_params(class_) &&
    !class_method.is_static
  let class_type_params = if preserve { class_.type_params } else { [] }
  let class_local_len = ffi_push_local_type_params(state, class_type_params)
  let class_type_name = ffi_class_type_name(class_.name)
  let class_self_type_with_params = if preserve {
    class_type_name + ffi_type_param_suffix(class_type_params)
  } else {
    class_type_name
  }
  let params : Array[String] = []
  let arg_names : Array[String] = []
  let js_args : Array[String] = []
  if !class_method.is_static {
    params.push("self : \{class_self_type_with_params}")
  }
  for param in class_method.params {
    let (name, type_) = param
    let safe_name = ffi_sanitize_identifier(name, "arg")
    let safe_type = ffi_type_name(state, type_)
    arg_names.push(safe_name)
    js_args.push(
      ffi_inline_js_arg_expr_with_state(Some(state), type_, safe_name),
    )
    params.push("\{safe_name} : \{safe_type}")
  }
  let raw_return_type = ffi_type_name(state, class_method.return_type)
  let return_type = match raw_return_type {
    "This" => class_self_type_with_params
    "This?" => class_self_type_with_params + "?"
    _ => raw_return_type
  }
  let fn_name = ffi_to_snake_case(class_.name) +
    "_" +
    ffi_to_snake_case(class_method.name)
  let method_params = params.join(", ")
  let binding_name = ffi_class_method_binding_name(
    class_.name,
    class_method.name,
  )
  let result = if preserve {
    state.needs_js_any = true
    let fn_prefix = ffi_function_type_param_prefix(class_type_params)
    let extern_params : Array[String] = []
    if !class_method.is_static {
      // Avoid naming the first param `self` — MoonBit's parser treats
      // `extern "js" fn foo(self : T, ...)` as a deprecated method-on-T
      // declaration, which breaks the wrapper's reference to this fn.
      extern_params.push("this_ : JSValue")
    }
    for arg in arg_names {
      extern_params.push("\{arg} : JSValue")
    }
    let extern_params_src = extern_params.join(", ")
    let cast_args : Array[String] = []
    if !class_method.is_static {
      cast_args.push("unsafeCast(self)")
    }
    for arg in arg_names {
      cast_args.push("unsafeCast(\{arg})")
    }
    let cast_args_src = cast_args.join(", ")
    let method_name = ffi_value_fn_name(class_method.name)
    if class_method.is_static {
      let extern_name = "_\{fn_name}_extern_js"
      let extern_decl = "extern \"js\" fn \{extern_name}(\{extern_params_src}) -> JSValue = \"\{binding_name}\""
      let wrapper_decl = "pub \{fn_prefix} \{fn_name}(\{method_params}) -> \{return_type} {\n  unsafeCast(\{extern_name}(\{cast_args_src}))\n}"
      "\{extern_decl}\n\n\{wrapper_decl}"
    } else {
      let js_params : Array[String] = ["self"]
      for arg in arg_names {
        js_params.push(arg)
      }
      let js_param_list = js_params.join(", ")
      let js_call = ffi_js_access("self", class_method.name) +
        "(" +
        js_args.join(", ") +
        ")"
      let extern_name = "_\{fn_name}_extern_js"
      let extern_decl = "extern \"js\" fn \{extern_name}(\{extern_params_src}) -> JSValue =\n  #| (\{js_param_list}) => \{js_call}"
      let instance_params = if method_params == "" {
        "self : \{class_self_type_with_params}"
      } else {
        method_params
      }
      let wrapper_decl = "pub \{fn_prefix} \{class_type_name}::\{method_name}(\{instance_params}) -> \{return_type} {\n  unsafeCast(\{extern_name}(\{cast_args_src}))\n}"
      "\{extern_decl}\n\n\{wrapper_decl}"
    }
  } else if class_method.is_static {
    "pub extern \"js\" fn \{fn_name}(\{method_params}) -> \{return_type} = \"\{binding_name}\""
  } else {
    let js_params : Array[String] = ["self"]
    for arg in arg_names {
      js_params.push(arg)
    }
    let js_param_list = js_params.join(", ")
    let js_call = ffi_js_access("self", class_method.name) +
      "(" +
      js_args.join(", ") +
      ")"
    let instance_params = if method_params == "" {
      "self : \{class_type_name}"
    } else {
      method_params
    }
    // Emit the method under its natural TypeScript name
    // (`Hono::get`) — `<lowercased_class>_<method>` (`Hono::hono_get`)
    // was a redundant alias that doubled the type name in user code.
    // Reserved-word sanitization in `ffi_value_fn_name` keeps the
    // identifier safe (e.g. `match` -> `match_`).
    let method_name = ffi_value_fn_name(class_method.name)
    "pub extern \"js\" fn \{class_type_name}::\{method_name}(\{instance_params}) -> \{return_type} =\n  #| (\{js_param_list}) => \{js_call}"
  }
  ffi_restore_local_type_params(state, class_local_len)
  result
}

///|
fn ffi_class_property_getter_decl_to_moonbit(
  state : MoonBitJsFfiState,
  class_ : @ast.TsClassDecl,
  class_property : @ast.TsClassPropertyDecl,
) -> String {
  // Static getters belong to the class itself, not an instance, so they
  // don't capture the class's instance-level type parameters. Emitting
  // `[E, S, B]` on a static getter that only returns a class-level
  // constant trips `unused_type_parameter` ([4027]).
  let preserve = ffi_should_preserve_class_type_params(class_) &&
    !class_property.is_static
  let class_type_params = if preserve { class_.type_params } else { [] }
  let class_local_len = ffi_push_local_type_params(state, class_type_params)
  let class_type_name = ffi_class_type_name(class_.name)
  let class_self_type_with_params = if preserve {
    class_type_name + ffi_type_param_suffix(class_type_params)
  } else {
    class_type_name
  }
  let params : Array[String] = []
  if !class_property.is_static {
    params.push("self : \{class_self_type_with_params}")
  }
  let fn_name = "get_" +
    ffi_to_snake_case(class_.name) +
    "_" +
    ffi_to_snake_case(class_property.name)
  let binding_name = ffi_class_property_getter_binding_name(
    class_.name,
    class_property.name,
  )
  let return_type = ffi_type_name(state, class_property.type_)
  let getter_params = params.join(", ")
  let result = if preserve {
    state.needs_js_any = true
    let fn_prefix = ffi_function_type_param_prefix(class_type_params)
    let extern_name = "_\{fn_name}_extern_js"
    if class_property.is_static {
      let extern_decl = "extern \"js\" fn \{extern_name}() -> JSValue = \"\{binding_name}\""
      let wrapper_decl = "pub \{fn_prefix} \{fn_name}(\{getter_params}) -> \{return_type} {\n  unsafeCast(\{extern_name}())\n}"
      "\{extern_decl}\n\n\{wrapper_decl}"
    } else {
      let js_get = ffi_js_access("self", class_property.name)
      // First param can't be named `self` — MoonBit parses
      // `extern "js" fn foo(self : T, ...)` as a deprecated method.
      let extern_decl = "extern \"js\" fn \{extern_name}(this_ : JSValue) -> JSValue =\n  #| (self) => \{js_get}"
      let wrapper_decl = "pub \{fn_prefix} \{class_type_name}::\{fn_name}(\{getter_params}) -> \{return_type} {\n  unsafeCast(\{extern_name}(unsafeCast(self)))\n}"
      "\{extern_decl}\n\n\{wrapper_decl}"
    }
  } else if class_property.is_static {
    "pub extern \"js\" fn \{fn_name}(\{getter_params}) -> \{return_type} = \"\{binding_name}\""
  } else {
    let js_get = ffi_js_access("self", class_property.name)
    "pub extern \"js\" fn \{class_type_name}::\{fn_name}(\{getter_params}) -> \{return_type} =\n  #| (self) => \{js_get}"
  }
  ffi_restore_local_type_params(state, class_local_len)
  result
}

///|
fn ffi_class_property_setter_decl_to_moonbit(
  state : MoonBitJsFfiState,
  class_ : @ast.TsClassDecl,
  class_property : @ast.TsClassPropertyDecl,
) -> String? {
  if class_property.is_readonly {
    return None
  }
  // Static setters: see static-getter rationale above.
  let preserve = ffi_should_preserve_class_type_params(class_) &&
    !class_property.is_static
  let class_type_params = if preserve { class_.type_params } else { [] }
  let class_local_len = ffi_push_local_type_params(state, class_type_params)
  let class_type_name = ffi_class_type_name(class_.name)
  let class_self_type_with_params = if preserve {
    class_type_name + ffi_type_param_suffix(class_type_params)
  } else {
    class_type_name
  }
  let params : Array[String] = []
  if !class_property.is_static {
    params.push("self : \{class_self_type_with_params}")
  }
  let value_type = ffi_type_name(state, class_property.type_)
  params.push("value : \{value_type}")
  let fn_name = "set_" +
    ffi_to_snake_case(class_.name) +
    "_" +
    ffi_to_snake_case(class_property.name)
  let binding_name = ffi_class_property_setter_binding_name(
    class_.name,
    class_property.name,
  )
  let setter_params = params.join(", ")
  let result : String? = if preserve {
    state.needs_js_any = true
    let fn_prefix = ffi_function_type_param_prefix(class_type_params)
    let extern_name = "_\{fn_name}_extern_js"
    if class_property.is_static {
      let extern_decl = "extern \"js\" fn \{extern_name}(value : JSValue) -> Unit = \"\{binding_name}\""
      let wrapper_decl = "pub \{fn_prefix} \{fn_name}(\{setter_params}) -> Unit {\n  \{extern_name}(unsafeCast(value))\n}"
      Some("\{extern_decl}\n\n\{wrapper_decl}")
    } else {
      let js_set = ffi_js_access("self", class_property.name)
      // First param can't be named `self` — MoonBit parses
      // `extern "js" fn foo(self : T, ...)` as a deprecated method.
      let extern_decl = "extern \"js\" fn \{extern_name}(this_ : JSValue, value : JSValue) -> Unit =\n  #| (self, value) => (\{js_set} = value)"
      let wrapper_decl = "pub \{fn_prefix} \{class_type_name}::\{fn_name}(\{setter_params}) -> Unit {\n  \{extern_name}(unsafeCast(self), unsafeCast(value))\n}"
      Some("\{extern_decl}\n\n\{wrapper_decl}")
    }
  } else if class_property.is_static {
    Some(
      "pub extern \"js\" fn \{fn_name}(\{setter_params}) -> Unit = \"\{binding_name}\"",
    )
  } else {
    let js_set = ffi_js_access("self", class_property.name)
    Some(
      "pub extern \"js\" fn \{class_type_name}::\{fn_name}(\{setter_params}) -> Unit =\n  #| (self, value) => (\{js_set} = value)",
    )
  }
  ffi_restore_local_type_params(state, class_local_len)
  result
}

///|
fn ffi_namespace_decl(export_name : String) -> (String, String) {
  let type_name = ffi_type_identifier(export_name, "OpaqueType")
  let ffi_decl = "#warnings(\"-3\")\n#external\npub type \{type_name}\n\npub extern \"js\" fn \{ffi_namespace_getter_name(export_name)}() -> \{type_name} = \"__ts_mbt_get_\{ffi_to_snake_case(export_name)}\""
  (type_name, ffi_decl)
}

///|
fn ffi_is_js_ident(name : String) -> Bool {
  if name == "" {
    return false
  }
  let first = name[0].unsafe_to_char()
  if !(ffi_is_ascii_letter(first) || first == '_' || first == '$') {
    return false
  }
  for c in name {
    if !(ffi_is_ascii_letter(c) || ffi_is_ascii_digit(c) || c == '_' || c == '$') {
      return false
    }
  }
  true
}

///|
fn ffi_func_string_subset_should_emit_wrapper(
  state : MoonBitJsFfiState,
  func : @ast.TsFunc,
) -> Bool {
  let mut has_subset_param = false
  for param in func.params {
    if ffi_type_is_string_or_string_array_union(param.type_) {
      has_subset_param = true
    }
    let param_type = ffi_func_string_subset_param_type_name(state, param.type_)
    if ffi_rendered_type_uses_js_any(param_type) {
      return false
    }
  }
  if !has_subset_param {
    return false
  }
  let return_type = ffi_type_name(state, func.return_type)
  !ffi_rendered_type_uses_js_any(return_type)
}

///|
fn ffi_import_string_subset_should_emit_wrapper(
  state : MoonBitJsFfiState,
  import_ : @ast.TsImport,
) -> Bool {
  let mut has_subset_param = false
  for item in import_.params {
    let (_, type_) = item
    if ffi_type_is_string_or_string_array_union(type_) {
      has_subset_param = true
    }
    let param_type = ffi_func_string_subset_param_type_name(state, type_)
    if ffi_rendered_type_uses_js_any(param_type) {
      return false
    }
  }
  if !has_subset_param {
    return false
  }
  let return_type = ffi_type_name(state, import_.return_type)
  !ffi_rendered_type_uses_js_any(return_type)
}

///|
fn ffi_is_js_reserved_word(name : String) -> Bool {
  match name {
    "break"
    | "case"
    | "catch"
    | "class"
    | "const"
    | "continue"
    | "debugger"
    | "default"
    | "delete"
    | "do"
    | "else"
    | "export"
    | "extends"
    | "finally"
    | "for"
    | "function"
    | "if"
    | "import"
    | "in"
    | "instanceof"
    | "new"
    | "return"
    | "super"
    | "switch"
    | "this"
    | "throw"
    | "try"
    | "typeof"
    | "var"
    | "void"
    | "while"
    | "with"
    | "yield"
    | "let"
    | "enum"
    | "await"
    | "implements"
    | "package"
    | "protected"
    | "static"
    | "interface"
    | "private"
    | "public"
    | "null"
    | "true"
    | "false" => true
    _ => false
  }
}

///|
fn ffi_js_access(base : String, export_name : String) -> String {
  if ffi_is_js_ident(export_name) {
    base + "." + export_name
  } else {
    base + "[\"" + export_name + "\"]"
  }
}

///|
fn ffi_bridge_import_local_name(export_name : String) -> String {
  if export_name == "default" {
    "default_"
  } else if ffi_is_js_ident(export_name) &&
    !ffi_is_js_reserved_word(export_name) {
    export_name
  } else {
    "bridge_" + ffi_to_snake_case(export_name)
  }
}

///|
fn ffi_bridge_import_key(export_name : String, is_namespace : Bool) -> String {
  if is_namespace {
    "namespace:" + export_name
  } else if export_name == "default" {
    "default:" + export_name
  } else {
    "named:" + export_name
  }
}

///|
fn ffi_runtime_export_root_name(runtime_export_name : String) -> String {
  match runtime_export_name.find(".") {
    Some(index) => runtime_export_name[:index].to_owned()
    None => runtime_export_name
  }
}

///|
fn ffi_runtime_export_member_names(
  runtime_export_name : String,
) -> Array[String] {
  let members : Array[String] = []
  match runtime_export_name.find(".") {
    Some(index) => {
      let suffix = runtime_export_name[index + 1:].to_owned()
      for part_view in suffix.split(".") {
        let part = part_view.to_owned()
        if part != "" {
          members.push(part)
        }
      }
    }
    None => ()
  }
  members
}

///|
fn ffi_runtime_export_requires_bridge(runtime_export_name : String) -> Bool {
  runtime_export_name.contains(".")
}

///|
fn runtime_export_name_for(
  runtime_export_names : Map[String, String],
  public_name : String,
) -> String {
  match runtime_export_names.get(public_name) {
    Some(runtime_export_name) => runtime_export_name
    None => public_name
  }
}

///|
fn ffi_module_spec_uses_public_exports(module_spec : String) -> Bool {
  !module_spec.has_prefix("./") &&
  !module_spec.has_prefix("../") &&
  !module_spec.has_prefix("/")
}

///|
fn ffi_module_spec_prefers_namespace_named_imports(
  module_spec : String,
) -> Bool {
  ffi_module_spec_uses_public_exports(module_spec) && !module_spec.contains(":")
}

///|
fn ffi_runtime_export_name_for_module(
  module_spec : String,
  runtime_module_resolved_path : String?,
  source_path : String,
  public_name : String,
  source_name : String,
) -> String {
  if source_name.contains(".") {
    return source_name
  }
  match runtime_module_resolved_path {
    Some(resolved_path) if source_path == resolved_path => return source_name
    _ => ()
  }
  if source_path == module_spec {
    return source_name
  }
  if ffi_module_spec_uses_public_exports(module_spec) {
    public_name
  } else {
    source_name
  }
}

///|
fn ffi_bridge_reexport_line(
  module_spec : String,
  runtime_export_name : String,
  binding_name : String,
) -> String? {
  if ffi_runtime_export_requires_bridge(runtime_export_name) {
    return None
  }
  if runtime_export_name == "default" {
    return Some(
      "export { default as \{binding_name} } from \"\{module_spec}\";",
    )
  }
  if ffi_is_js_ident(runtime_export_name) {
    return Some(
      "export { \{runtime_export_name} as \{binding_name} } from \"\{module_spec}\";",
    )
  }
  None
}

///|
fn ensure_bridge_import_with_kind(
  seen_import_keys : Array[String],
  bridge_imports : Array[MoonBitBridgeImport],
  export_name : String,
  is_namespace : Bool,
) -> String {
  let key = ffi_bridge_import_key(export_name, is_namespace)
  let local_name = ffi_bridge_import_local_name(export_name)
  if seen_import_keys.contains(key) {
    return local_name
  }
  seen_import_keys.push(key)
  bridge_imports.push({
    imported_name: export_name,
    local_name,
    is_default: export_name == "default",
    is_namespace,
  })
  local_name
}

///|
fn ensure_bridge_import(
  seen_import_keys : Array[String],
  bridge_imports : Array[MoonBitBridgeImport],
  export_name : String,
) -> String {
  ensure_bridge_import_with_kind(
    seen_import_keys, bridge_imports, export_name, false,
  )
}

///|
fn ensure_bridge_runtime_access(
  seen_import_keys : Array[String],
  bridge_imports : Array[MoonBitBridgeImport],
  namespace_import_roots : Array[String],
  runtime_export_name : String,
) -> String {
  let root_name = ffi_runtime_export_root_name(runtime_export_name)
  let mut access = ensure_bridge_import_with_kind(
    seen_import_keys,
    bridge_imports,
    root_name,
    namespace_import_roots.contains(root_name),
  )
  for member_name in ffi_runtime_export_member_names(runtime_export_name) {
    access = ffi_js_access(access, member_name)
  }
  access
}

///|
fn ensure_bridge_module_runtime_access(
  seen_import_keys : Array[String],
  bridge_imports : Array[MoonBitBridgeImport],
  runtime_export_name : String,
) -> String {
  let mut access = ensure_bridge_import_with_kind(
    seen_import_keys, bridge_imports, "__ts_mbt_module", true,
  )
  access = ffi_js_access(
    access,
    ffi_runtime_export_root_name(runtime_export_name),
  )
  for member_name in ffi_runtime_export_member_names(runtime_export_name) {
    access = ffi_js_access(access, member_name)
  }
  access
}

///|
fn ensure_bridge_value_runtime_access(
  seen_import_keys : Array[String],
  bridge_imports : Array[MoonBitBridgeImport],
  namespace_import_roots : Array[String],
  module_spec : String,
  runtime_export_name : String,
) -> String {
  let root_name = ffi_runtime_export_root_name(runtime_export_name)
  if ffi_runtime_export_requires_bridge(runtime_export_name) ||
    namespace_import_roots.contains(root_name) {
    return ensure_bridge_runtime_access(
      seen_import_keys, bridge_imports, namespace_import_roots, runtime_export_name,
    )
  }
  if ffi_module_spec_uses_public_exports(module_spec) {
    ensure_bridge_module_runtime_access(
      seen_import_keys, bridge_imports, runtime_export_name,
    )
  } else {
    ensure_bridge_runtime_access(
      seen_import_keys, bridge_imports, namespace_import_roots, runtime_export_name,
    )
  }
}

///|
fn bridge_namespace_import_roots_for_export_equals(
  export_surface : Array[ResolvedExport],
  modules : Map[String, DeclModuleInfo],
  module_spec : String,
) -> Array[String] {
  let roots : Array[String] = []
  let module_basename = match module_spec.rev_find("/") {
    Some(idx) => module_spec[idx + 1:].to_owned()
    None =>
      match module_spec.rev_find(":") {
        Some(idx) => module_spec[idx + 1:].to_owned()
        None => module_spec
      }
  }
  for export_ in export_surface {
    if export_.export_name == "default" {
      continue
    }
    match exported_local_namespace_decl(export_, modules) {
      Some(_) => {
        let mut has_default_assignment = false
        for other in export_surface {
          if other.export_name == "default" &&
            other.source_path == export_.source_path &&
            other.local_name == export_.local_name {
            has_default_assignment = true
          }
        }
        if (
            has_default_assignment ||
            export_.source_export_name == module_basename
          ) &&
          !roots.contains(export_.source_export_name) {
          roots.push(export_.source_export_name)
        }
      }
      None => ()
    }
  }
  roots
}

///|
fn render_bridge_import_line(
  module_spec : String,
  bridge_imports : Array[MoonBitBridgeImport],
) -> String? {
  if bridge_imports.is_empty() {
    return None
  }
  let mut default_import : String? = None
  let named_bindings : Array[(String, String)] = []
  let namespace_imports : Array[String] = []
  for import_ in bridge_imports {
    if import_.is_namespace {
      namespace_imports.push(import_.local_name)
    } else if import_.is_default {
      default_import = Some(import_.local_name)
    } else {
      named_bindings.push((import_.imported_name, import_.local_name))
    }
  }
  let lines : Array[String] = []
  namespace_imports.sort()
  for local_name in namespace_imports {
    lines.push("import * as \{local_name} from \"\{module_spec}\";")
  }
  if !named_bindings.is_empty() {
    named_bindings.sort()
    if ffi_module_spec_prefers_namespace_named_imports(module_spec) {
      match default_import {
        Some(default_binding) =>
          lines.push("import \{default_binding} from \"\{module_spec}\";")
        None => ()
      }
      let namespace_local = "__ts_mbt_module"
      if !namespace_imports.contains(namespace_local) {
        lines.push("import * as \{namespace_local} from \"\{module_spec}\";")
      }
      for binding in named_bindings {
        let (imported_name, local_name) = binding
        lines.push(
          "const \{local_name} = \{ffi_js_access(namespace_local, imported_name)};",
        )
      }
    } else {
      let import_specs : Array[String] = []
      for binding in named_bindings {
        let (imported_name, local_name) = binding
        if imported_name == local_name {
          import_specs.push(imported_name)
        } else {
          import_specs.push("\{imported_name} as \{local_name}")
        }
      }
      let import_specs_src = import_specs.join(", ")
      match default_import {
        Some(default_binding) =>
          lines.push(
            "import \{default_binding}, { \{import_specs_src} } from \"\{module_spec}\";",
          )
        None =>
          lines.push("import { \{import_specs_src} } from \"\{module_spec}\";")
      }
    }
  } else {
    match default_import {
      Some(default_binding) =>
        lines.push("import \{default_binding} from \"\{module_spec}\";")
      None => ()
    }
  }
  if lines.is_empty() {
    None
  } else {
    Some(lines.join("\n"))
  }
}

///|
fn normalize_interfaces_for_ffi(
  exported_interfaces : Array[ExportedInterfaceDecl],
  modules : Map[String, DeclModuleInfo],
  canonical_types : Map[String, String],
) -> Array[@ast.TsInterface] {
  let interfaces : Array[@ast.TsInterface] = []
  if exported_interfaces.length() > 256 {
    return interfaces
  }
  for exported in exported_interfaces {
    match modules.get(exported.source_path) {
      Some(info) =>
        interfaces.push(
          clone_exported_interface(exported, info, modules, canonical_types),
        )
      None => ()
    }
  }
  interfaces
}

///|
fn normalize_imports_for_ffi(
  exported_imports : Array[ExportedImportDecl],
  modules : Map[String, DeclModuleInfo],
  canonical_types : Map[String, String],
) -> Array[@ast.TsImport] {
  let imports : Array[@ast.TsImport] = []
  for exported in exported_imports {
    match modules.get(exported.source_path) {
      Some(info) =>
        push_preferred_import_decl(
          imports,
          clone_exported_import(exported, info, modules, canonical_types),
        )
      None => ()
    }
  }
  imports
}

///|
fn normalize_funcs_for_ffi(
  exported_funcs : Array[ExportedFuncDecl],
  modules : Map[String, DeclModuleInfo],
  canonical_types : Map[String, String],
) -> Array[@ast.TsFunc] {
  let funcs : Array[@ast.TsFunc] = []
  for exported in exported_funcs {
    match modules.get(exported.source_path) {
      Some(info) =>
        push_preferred_func_decl(
          funcs,
          clone_exported_func(exported, info, modules, canonical_types),
        )
      None => ()
    }
  }
  funcs
}

///|
fn normalize_values_for_ffi(
  exported_values : Array[ExportedValueDecl],
  modules : Map[String, DeclModuleInfo],
  canonical_types : Map[String, String],
) -> Array[@ast.TsValueDecl] {
  let values : Array[@ast.TsValueDecl] = []
  for exported in exported_values {
    match modules.get(exported.source_path) {
      Some(info) =>
        values.push(
          clone_exported_value(exported, info, modules, canonical_types),
        )
      None => ()
    }
  }
  values
}

///|
fn normalize_classes_for_ffi(
  exported_classes : Array[ExportedClassDecl],
  graph : ModuleGraph,
  modules : Map[String, DeclModuleInfo],
  surface_cache : Map[String, Array[ResolvedExport]],
  canonical_types : Map[String, String],
) -> Array[@ast.TsClassDecl] {
  let classes : Array[@ast.TsClassDecl] = []
  for exported in exported_classes {
    match modules.get(exported.source_path) {
      Some(info) =>
        classes.push(
          clone_exported_class(
            exported, info, graph, modules, surface_cache, canonical_types,
          ),
        )
      None => ()
    }
  }
  classes
}

///|
pub async fn emit_moonbit_js_ffi_bundle_from_entry_path(
  entry_path : String,
  module_spec : String,
) -> MoonBitJsFfiBundle raise ModuleGraphError {
  let graph = load_type_module_graph(entry_path)
  let export_surface = resolve_export_surface(graph)
  let modules = build_decl_module_map(graph)
  let (
    exported_interfaces,
    exported_enums,
    exported_tagged_unions,
    exported_type_aliases,
    exported_imports,
    exported_funcs,
    exported_values,
    exported_classes,
    decl_notes,
  ) = collect_exported_decls(graph, export_surface, modules)
  let canonical_types = build_canonical_type_name_map(
    exported_interfaces, exported_enums, exported_classes,
  )
  let class_surface_cache : Map[String, Array[ResolvedExport]] = {}
  let emitted_exported_imports = append_exported_imports(
    exported_imports,
    exported_import_overload_wrappers(
      exported_imports, modules, canonical_types,
    ),
  )
  let emitted_exported_funcs = append_exported_funcs(
    exported_funcs,
    exported_func_overload_wrappers(exported_funcs, modules, canonical_types),
  )
  let tuple_result_interfaces = normalize_result_interfaces(
    emitted_exported_imports, emitted_exported_funcs, modules, canonical_types,
  )
  let dependency_exported_interfaces : Array[ExportedInterfaceDecl] = if exported_interfaces.length() >
    256 {
    []
  } else {
    exported_interfaces
  }
  let react_utility_interfaces = normalize_react_utility_interfaces(
    dependency_exported_interfaces, emitted_exported_imports, emitted_exported_funcs,
    exported_values, exported_classes, modules, canonical_types,
  )
  let specialized_node_interfaces = normalize_specialized_node_interfaces(
    dependency_exported_interfaces,
  )
  let interfaces = normalize_interfaces_for_ffi(
    exported_interfaces, modules, canonical_types,
  )
  for spec in tuple_result_interfaces {
    interfaces.push(spec.iface)
  }
  for iface in react_utility_interfaces {
    interfaces.push(iface)
  }
  for iface in specialized_node_interfaces {
    interfaces.push(iface)
  }
  for
    iface in collect_interface_dependencies(
      dependency_exported_interfaces, emitted_exported_imports, emitted_exported_funcs,
      exported_values, exported_classes, modules, canonical_types, interfaces,
    ) {
    interfaces.push(iface)
  }
  let imports = normalize_imports_for_ffi(
    emitted_exported_imports, modules, canonical_types,
  )
  let funcs = normalize_funcs_for_ffi(
    emitted_exported_funcs, modules, canonical_types,
  )
  let values = normalize_values_for_ffi(
    exported_values, modules, canonical_types,
  )
  let enums : Array[@ast.TsEnumDecl] = []
  for exported in exported_enums {
    enums.push(clone_exported_enum(exported))
  }
  let classes = normalize_classes_for_ffi(
    exported_classes, graph, modules, class_surface_cache, canonical_types,
  )
  enum_lowering_rewrite_anonymous_enum_surfaces(
    enums, interfaces, imports, funcs, values, classes,
  )
  push_remaining_anonymous_literal_union_notes(
    decl_notes, interfaces, imports, funcs,
  )
  let runtime_module_resolved_path = @parser.resolve_type_module_specifier(
    entry_path, module_spec,
  ) catch {
    _ => None
  }
  let base_import_export_names : Array[String] = []
  for exported in exported_imports {
    if !base_import_export_names.contains(exported.export_name) {
      base_import_export_names.push(exported.export_name)
    }
  }
  let base_func_export_names : Array[String] = []
  for exported in exported_funcs {
    if !base_func_export_names.contains(exported.export_name) {
      base_func_export_names.push(exported.export_name)
    }
  }
  let import_runtime_export_names : Map[String, String] = {}
  for exported in emitted_exported_imports {
    import_runtime_export_names[exported.export_name] = if base_import_export_names.contains(
        exported.export_name,
      ) {
      ffi_runtime_export_name_for_module(
        module_spec,
        runtime_module_resolved_path,
        exported.source_path,
        exported.export_name,
        exported.source_export_name,
      )
    } else {
      exported.source_export_name
    }
  }
  let func_runtime_export_names : Map[String, String] = {}
  for exported in emitted_exported_funcs {
    func_runtime_export_names[exported.export_name] = if base_func_export_names.contains(
        exported.export_name,
      ) {
      ffi_runtime_export_name_for_module(
        module_spec,
        runtime_module_resolved_path,
        exported.source_path,
        exported.export_name,
        exported.source_export_name,
      )
    } else {
      exported.source_export_name
    }
  }
  let value_runtime_export_names : Map[String, String] = {}
  for exported in exported_values {
    value_runtime_export_names[exported.export_name] = ffi_runtime_export_name_for_module(
      module_spec,
      runtime_module_resolved_path,
      exported.source_path,
      exported.export_name,
      exported.source_export_name,
    )
  }
  let class_runtime_export_names : Map[String, String] = {}
  for exported in exported_classes {
    class_runtime_export_names[exported.export_name] = ffi_runtime_export_name_for_module(
      module_spec,
      runtime_module_resolved_path,
      exported.source_path,
      exported.export_name,
      exported.source_export_name,
    )
  }
  let namespace_import_roots = bridge_namespace_import_roots_for_export_equals(
    export_surface, modules, module_spec,
  )
  let tuple_result_field_names : Map[String, Array[String]] = {}
  for spec in tuple_result_interfaces {
    if !spec.needs_runtime_tuple_wrapper {
      continue
    }
    let field_names : Array[String] = []
    for field in spec.iface.fields {
      field_names.push(field.0)
    }
    tuple_result_field_names[spec.export_name] = field_names
  }

  let declared_type_names : Array[String] = []
  let struct_type_names : Array[String] = []
  let generic_type_params_by_name : Map[String, Array[String]] = {}
  // Pre-collect class names + their generic-preserved arities so the
  // interface registration agrees with the class on shared names. When a
  // class and an interface share a name (TS declaration merging) the
  // class drives the emitted shape (`#external pub type ClassName[T]`)
  // and the interface's own emission is skipped below.
  let class_type_names : Array[String] = []
  let class_arity_by_type_name : Map[String, Array[String]] = {}
  for class_ in classes {
    let class_type_name = ffi_class_type_name(class_.name)
    class_type_names.push(class_type_name)
    if ffi_should_preserve_class_type_params(class_) {
      class_arity_by_type_name[class_type_name] = class_.type_params
    }
  }
  for iface in interfaces {
    let type_name = ffi_type_identifier(iface.name, "OpaqueType")
    declared_type_names.push(type_name)
    if class_type_names.contains(type_name) {
      // The class drives the shape. If the class itself preserves type
      // params, register that arity under the shared name.
      match class_arity_by_type_name.get(type_name) {
        Some(type_params) =>
          generic_type_params_by_name[type_name] = type_params
        None => ()
      }
    } else if ffi_should_preserve_interface_type_params(iface) &&
      iface.type_params.length() > 0 {
      // Match the arity actually emitted on the struct / `#external pub
      // type` declaration. Both `ffi_struct_decl_to_moonbit` and
      // `ffi_interface_type_decl_to_moonbit` use the full
      // `iface.type_params` list, so register the full arity here too.
      generic_type_params_by_name[type_name] = iface.type_params
    }
    if !ffi_is_react_callable_component_interface(iface.name) &&
      ffi_struct_fields_need_js_converter(enums, iface.fields) {
      struct_type_names.push(type_name)
    }
  }
  // For modules with so many interfaces that `normalize_interfaces_for_ffi`
  // bails on the 256 ceiling, the FFI's `interfaces` only contains
  // transitively reachable types — the rest never get their generic
  // arity registered. Walk all modules' interface lists (recursively
  // through nested namespaces) and fill in any missing arity entries so
  // call-site references like `Applied("ServerNormalizedPathMap", [...])`
  // match the decl-side `declare pub type ServerNormalizedPathMap[T]`.
  ffi_register_module_iface_arities(
    modules, generic_type_params_by_name, class_type_names,
  )
  for enum_ in enums {
    declared_type_names.push(ffi_type_identifier(enum_.name, "GeneratedEnum"))
  }
  for class_ in classes {
    let class_type_name = ffi_class_type_name(class_.name)
    declared_type_names.push(class_type_name)
    // Register the class's generic arity so call-site references like
    // `Applied("Hono", [E, S, BasePath])` match the emitted
    // `#external pub type Hono[E, S, BasePath]`.
    if ffi_should_preserve_class_type_params(class_) {
      generic_type_params_by_name[class_type_name] = class_.type_params
    }
  }
  let tagged_union_decls_by_name : Map[String, BridgeTaggedUnionDecl] = {}
  for tagged in exported_tagged_unions {
    let type_name = ffi_type_identifier(tagged.decl.name, "OpaqueType")
    declared_type_names.push(type_name)
    tagged_union_decls_by_name[type_name] = tagged.decl
  }
  let simple_type_aliases : Array[@ast.TsTypeAlias] = []
  for exported in exported_type_aliases {
    match modules.get(exported.source_path) {
      Some(info) => {
        let type_alias = clone_exported_type_alias(
          exported, info, modules, canonical_types,
        )
        if type_alias_passthrough_supported(type_alias) {
          simple_type_aliases.push(type_alias)
        }
      }
      None => ()
    }
  }
  let state : MoonBitJsFfiState = {
    declared_type_names,
    struct_type_names,
    generic_type_params_by_name,
    enums,
    external_type_names: [],
    local_type_param_names: [],
    function_field_method_wrapper_limit: ffi_function_field_method_wrapper_limit,
    tagged_union_decls_by_name,
    synthesized_inline_unions: {},
    needs_js_any: false,
    needs_promise: false,
  }
  let type_aliases_by_type_name = ffi_type_alias_map_by_type_name(modules)
  let emitted_type_names : Array[String] = []

  let ffi_sections : Array[String] = [
    "// AUTO-GENERATED by `ts2mbt` (mizchi/ts). DO NOT EDIT -- your changes\n// will be lost on the next `ts2mbt generate` / `ts2mbt vendor`.",
    "// Load the generated bridge JS before calling these externs.",
  ]
  for type_alias in simple_type_aliases {
    match ffi_type_alias_decl_to_moonbit(state, type_alias) {
      Some(section) => {
        if !state.declared_type_names.contains(
            ffi_type_identifier(type_alias.name, "AliasType"),
          ) {
          state.declared_type_names.push(
            ffi_type_identifier(type_alias.name, "AliasType"),
          )
        }
        emitted_type_names.push(
          ffi_type_identifier(type_alias.name, "AliasType"),
        )
        ffi_sections.push(section)
      }
      None => ()
    }
  }
  let seen_ffi_binding_names : Array[String] = []
  let bridge_lines : Array[String] = []
  let bridge_enum_converter_lines : Array[String] = []
  let bridge_struct_converter_lines : Array[String] = []
  let mut bridge_needs_option_unwrap = false
  let bridge_imports : Array[MoonBitBridgeImport] = []
  let seen_bridge_import_keys : Array[String] = []
  let seen_bridge_binding_names : Array[String] = []
  let use_js_enum_converters = ffi_should_use_js_enum_converters(enums)

  for note in decl_notes {
    let text = note.replace(old="///|\n/// ", new="")
    ffi_sections.push("// " + text)
    bridge_lines.push("// " + text)
  }

  let namespace_export_names : Array[String] = []
  let ambiguous_exports : Array[ResolvedExport] = []
  let handled_export_names : Array[String] = []
  for export_ in export_surface {
    match export_.kind {
      Namespace =>
        match exported_local_namespace_decl(export_, modules) {
          Some(_) => ()
          None => namespace_export_names.push(export_.export_name)
        }
      Ambiguous => ambiguous_exports.push(export_)
      _ => ()
    }
  }
  namespace_export_names.sort()
  ambiguous_exports.sort_by(fn(lhs, rhs) {
    lhs.export_name.compare(rhs.export_name)
  })

  for export_ in ambiguous_exports {
    let msg = ffi_ambiguous_export_message(export_)
    ffi_sections.push("// " + msg)
    bridge_lines.push("// " + msg)
  }

  for export_name in namespace_export_names {
    let (_, ffi_decl) = ffi_namespace_decl(export_name)
    let getter_binding_name = "__ts_mbt_get_" + ffi_to_snake_case(export_name)
    push_unique_ffi_section(
      seen_ffi_binding_names,
      ffi_sections,
      ffi_fn_decl_key(ffi_namespace_getter_name(export_name)),
      ffi_decl,
    )
    push_unique_bridge_binding(
      seen_bridge_binding_names,
      bridge_lines,
      getter_binding_name,
      ffi_bridge_function_line(
        getter_binding_name,
        [],
        ensure_bridge_import(
          seen_bridge_import_keys, bridge_imports, export_name,
        ),
      ),
    )
  }

  for enum_ in enums {
    let type_name = ffi_type_identifier(enum_.name, "GeneratedEnum")
    if !emitted_type_names.contains(type_name) {
      emitted_type_names.push(type_name)
      ffi_sections.push(ffi_enum_decl_to_moonbit(enum_))
      if use_js_enum_converters {
        match ffi_enum_js_extern_converter_decl(enum_) {
          Some(converter_decl) => ffi_sections.push(converter_decl)
          None => ()
        }
        match ffi_enum_runtime_js_converter_decl(enum_) {
          Some(converter_decl) =>
            bridge_enum_converter_lines.push(converter_decl)
          None => ()
        }
      } else {
        match ffi_enum_string_converter_decl(enum_) {
          Some(converter_decl) => ffi_sections.push(converter_decl)
          None =>
            match ffi_enum_int_converter_decl(enum_) {
              Some(converter_decl) => ffi_sections.push(converter_decl)
              None =>
                match ffi_enum_double_int_converter_decl(enum_) {
                  Some(converter_decl) => ffi_sections.push(converter_decl)
                  None => ()
                }
            }
        }
      }
      match ffi_enum_bridge_js_converter_decl(enum_) {
        Some(converter_decl) => bridge_enum_converter_lines.push(converter_decl)
        None => ()
      }
    }
    handled_export_names.push(enum_.name)
  }

  for tagged in exported_tagged_unions {
    let type_name = ffi_type_identifier(tagged.decl.name, "OpaqueType")
    if !emitted_type_names.contains(type_name) {
      // Inner Named payloads must already be visible to the .mbt
      // file. Register them as external so the existing
      // `state.external_type_names` loop emits a `#external; type N`
      // declaration once, and skips emission if the package already
      // declares N as an enum, struct, or class.
      for entry in tagged.decl.cases {
        let (_, inner) = entry
        let inner_named = match inner {
          @ast.TsType::Named(name) => Some(name)
          @ast.TsType::Array(@ast.TsType::Named(name)) => Some(name)
          _ => None
        }
        match inner_named {
          Some(inner_name) => {
            let _ = ffi_mark_external_type(state, inner_name)
          }
          None => ()
        }
      }
      emitted_type_names.push(type_name)
      match
        tagged_union_decl_to_moonbit_section_with_arity(
          tagged.decl,
          state.generic_type_params_by_name,
        ) {
        Some(section) => ffi_sections.push(section)
        None => ()
      }
    }
    match
      tagged_union_bridge_js_converter_decls_with_nested(
        tagged.decl,
        state.tagged_union_decls_by_name,
        struct_converter_names=state.struct_type_names,
      ) {
      Some(decls) => bridge_lines.push(decls)
      None =>
        bridge_lines.push(
          "// Heterogeneous union " +
          tagged.decl.name +
          " could not be auto-lowered (unsupported case payload).",
        )
    }
  }

  // TS lets you declare an `interface Foo<...>` and a `class Foo<...>`
  // together to merge them. When both exist with the same name, the
  // class drives the runtime emission (`#external pub type Foo` plus
  // bare-`Foo` class methods); skip the interface struct decl to avoid a
  // duplicate / arity-mismatched `pub(all) struct Foo[T, U, V]`.
  let class_type_names_for_iface_skip : Array[String] = []
  for class_ in classes {
    class_type_names_for_iface_skip.push(ffi_class_type_name(class_.name))
  }
  for iface in interfaces {
    let type_name = ffi_type_identifier(iface.name, "OpaqueType")
    if class_type_names_for_iface_skip.contains(type_name) {
      handled_export_names.push(iface.name)
      continue
    }
    if !emitted_type_names.contains(type_name) {
      emitted_type_names.push(type_name)
      if ffi_is_react_callable_component_interface(iface.name) {
        ffi_sections.push(ffi_interface_type_decl_to_moonbit(iface))
      } else {
        ffi_sections.push(ffi_struct_decl_to_moonbit(state, iface))
        if state.struct_type_names.contains(type_name) {
          bridge_struct_converter_lines.push(
            ffi_struct_js_converter_decl(
              state,
              iface.name,
              ffi_visible_interface_fields(state, iface),
            ),
          )
        }
      }
    }
    handled_export_names.push(iface.name)
  }

  for class_ in classes {
    let class_type_name = ffi_class_type_name(class_.name)
    if !emitted_type_names.contains(class_type_name) {
      emitted_type_names.push(class_type_name)
      ffi_sections.push(ffi_class_type_decl(class_))
    }
    let class_runtime_export_name = runtime_export_name_for(
      class_runtime_export_names,
      class_.name,
    )
    let class_ctor_section = ffi_class_constructor_decl_to_moonbit(
      state, class_,
    )
    match class_ctor_section {
      Some(decl) =>
        push_unique_ffi_section(
          seen_ffi_binding_names,
          ffi_sections,
          ffi_fn_decl_key("new_" + ffi_to_snake_case(class_.name)),
          decl,
        )
      None => ()
    }
    for class_property in class_.properties {
      push_unique_ffi_section(
        seen_ffi_binding_names,
        ffi_sections,
        ffi_fn_decl_key(
          "get_" +
          ffi_to_snake_case(class_.name) +
          "_" +
          ffi_to_snake_case(class_property.name),
        ),
        ffi_class_property_getter_decl_to_moonbit(state, class_, class_property),
      )
      match
        ffi_class_property_setter_decl_to_moonbit(state, class_, class_property) {
        Some(decl) =>
          push_unique_ffi_section(
            seen_ffi_binding_names,
            ffi_sections,
            ffi_fn_decl_key(
              "set_" +
              ffi_to_snake_case(class_.name) +
              "_" +
              ffi_to_snake_case(class_property.name),
            ),
            decl,
          )
        None => ()
      }
    }
    for class_method in class_.methods {
      push_unique_ffi_section(
        seen_ffi_binding_names,
        ffi_sections,
        ffi_fn_decl_key(
          ffi_to_snake_case(class_.name) +
          "_" +
          ffi_to_snake_case(class_method.name),
        ),
        ffi_class_method_decl_to_moonbit(state, class_, class_method),
      )
    }
    handled_export_names.push(class_.name)
    match class_.constructor_params {
      Some(constructor_params) if class_.is_constructible => {
        let args : Array[String] = []
        for param in constructor_params {
          let (param_name, _) = param
          args.push(ffi_sanitize_identifier(param_name, "arg"))
        }
        let call_args = ffi_params_call_args_with_names(
          state, constructor_params, args,
        )
        let params_str = call_args.join(", ")
        let class_access = ensure_bridge_runtime_access(
          seen_bridge_import_keys, bridge_imports, namespace_import_roots, class_runtime_export_name,
        )
        let ctor_binding_name = ffi_class_ctor_binding_name(class_.name)
        push_unique_bridge_binding(
          seen_bridge_binding_names,
          bridge_lines,
          ctor_binding_name,
          ffi_bridge_function_line(
            ctor_binding_name,
            args,
            "new \{class_access}(\{params_str})",
          ),
        )
      }
      None if class_.is_constructible => {
        let class_access = ensure_bridge_runtime_access(
          seen_bridge_import_keys, bridge_imports, namespace_import_roots, class_runtime_export_name,
        )
        let ctor_binding_name = ffi_class_ctor_binding_name(class_.name)
        push_unique_bridge_binding(
          seen_bridge_binding_names,
          bridge_lines,
          ctor_binding_name,
          ffi_bridge_function_line(
            ctor_binding_name,
            [],
            "new \{class_access}()",
          ),
        )
      }
      _ => ()
    }
    for class_property in class_.properties {
      if !class_property.is_static {
        continue
      }
      let getter_binding = ffi_class_property_getter_binding_name(
        class_.name,
        class_property.name,
      )
      let class_access = ensure_bridge_runtime_access(
        seen_bridge_import_keys, bridge_imports, namespace_import_roots, class_runtime_export_name,
      )
      let getter_access = ffi_js_access(class_access, class_property.name)
      push_unique_bridge_binding(
        seen_bridge_binding_names,
        bridge_lines,
        getter_binding,
        ffi_bridge_function_line(getter_binding, [], getter_access),
      )
      if !class_property.is_readonly {
        let setter_binding = ffi_class_property_setter_binding_name(
          class_.name,
          class_property.name,
        )
        let setter_target = ffi_js_access(class_access, class_property.name)
        push_unique_bridge_binding(
          seen_bridge_binding_names,
          bridge_lines,
          setter_binding,
          ffi_bridge_function_line(
            setter_binding,
            ["value"],
            "(\{setter_target} = value)",
          ),
        )
      }
    }
    for class_method in class_.methods {
      if !class_method.is_static {
        continue
      }
      let args : Array[String] = []
      for param in class_method.params {
        let (param_name, _) = param
        args.push(ffi_sanitize_identifier(param_name, "arg"))
      }
      let class_access = ensure_bridge_runtime_access(
        seen_bridge_import_keys, bridge_imports, namespace_import_roots, class_runtime_export_name,
      )
      let call_args = ffi_params_call_args_with_names(
        state,
        class_method.params,
        args,
      )
      let args_str = call_args.join(", ")
      let method_access = ffi_js_access(class_access, class_method.name)
      let binding_name = ffi_class_method_binding_name(
        class_.name,
        class_method.name,
      )
      push_unique_bridge_binding(
        seen_bridge_binding_names,
        bridge_lines,
        binding_name,
        ffi_bridge_function_line(
          binding_name,
          args,
          "\{method_access}(\{args_str})",
        ),
      )
    }
  }

  for import_ in imports {
    let runtime_export_name = runtime_export_name_for(
      import_runtime_export_names,
      import_.name,
    )
    let needs_js_arg_conversion = ffi_import_needs_js_arg_conversion(
      state, import_,
    )
    let needs_js_return_conversion = ffi_import_needs_js_return_conversion(
      state, import_,
    )
    if needs_js_arg_conversion || needs_js_return_conversion {
      bridge_needs_option_unwrap = true
    }
    match tuple_result_field_names.get(import_.name) {
      Some(field_names) => {
        let binding_name = ffi_binding_name(import_.name)
        let args = ffi_import_bridge_param_names(import_, runtime_export_name)
        let call_args = ffi_import_call_args_with_names(state, import_, args)
        let args_str = call_args.join(", ")
        let runtime_access = ensure_bridge_runtime_access(
          seen_bridge_import_keys, bridge_imports, namespace_import_roots, runtime_export_name,
        )
        let call_expr = "\{runtime_access}(\{args_str})"
        push_unique_ffi_section(
          seen_ffi_binding_names,
          ffi_sections,
          ffi_fn_decl_key(ffi_value_fn_name(import_.name)),
          ffi_import_decl_to_moonbit(state, import_),
        )
        push_unique_bridge_binding(
          seen_bridge_binding_names,
          bridge_lines,
          binding_name,
          ffi_bridge_tuple_wrapper_line(
            binding_name, args, call_expr, field_names,
          ),
        )
      }
      None =>
        if ffi_can_use_direct_runtime_export(module_spec, runtime_export_name) &&
          !ffi_runtime_export_requires_bridge(runtime_export_name) &&
          !needs_js_arg_conversion &&
          !needs_js_return_conversion {
          push_unique_ffi_section(
            seen_ffi_binding_names,
            ffi_sections,
            ffi_fn_decl_key(ffi_value_fn_name(import_.name)),
            ffi_import_decl_to_moonbit_direct(
              state, import_, runtime_export_name, module_spec,
            ),
          )
        } else {
          let binding_name = ffi_binding_name(import_.name)
          push_unique_ffi_section(
            seen_ffi_binding_names,
            ffi_sections,
            ffi_fn_decl_key(ffi_value_fn_name(import_.name)),
            ffi_import_decl_to_moonbit(state, import_),
          )
          match
            ffi_bridge_reexport_line(
              module_spec, runtime_export_name, binding_name,
            ) {
            Some(reexport_line) =>
              if !needs_js_arg_conversion && !needs_js_return_conversion {
                push_unique_bridge_binding(
                  seen_bridge_binding_names, bridge_lines, binding_name, reexport_line,
                )
              } else {
                let args = ffi_import_bridge_param_names(
                  import_, runtime_export_name,
                )
                let call_args = ffi_import_call_args_with_names(
                  state, import_, args,
                )
                let call_args_str = call_args.join(", ")
                let runtime_access = ensure_bridge_runtime_access(
                  seen_bridge_import_keys, bridge_imports, namespace_import_roots,
                  runtime_export_name,
                )
                let return_expr = ffi_type_js_return_expr(
                  state,
                  import_.return_type,
                  "\{runtime_access}(\{call_args_str})",
                )
                push_unique_bridge_binding(
                  seen_bridge_binding_names,
                  bridge_lines,
                  binding_name,
                  ffi_bridge_function_line(binding_name, args, return_expr),
                )
              }
            None =>
              if needs_js_arg_conversion || needs_js_return_conversion {
                let args = ffi_import_bridge_param_names(
                  import_, runtime_export_name,
                )
                let call_args = ffi_import_call_args_with_names(
                  state, import_, args,
                )
                let call_args_str = call_args.join(", ")
                let runtime_access = ensure_bridge_runtime_access(
                  seen_bridge_import_keys, bridge_imports, namespace_import_roots,
                  runtime_export_name,
                )
                let return_expr = ffi_type_js_return_expr(
                  state,
                  import_.return_type,
                  "\{runtime_access}(\{call_args_str})",
                )
                push_unique_bridge_binding(
                  seen_bridge_binding_names,
                  bridge_lines,
                  binding_name,
                  ffi_bridge_function_line(binding_name, args, return_expr),
                )
              } else {
                push_unique_bridge_binding(
                  seen_bridge_binding_names,
                  bridge_lines,
                  binding_name,
                  "export const \{binding_name} = \{ensure_bridge_runtime_access(seen_bridge_import_keys, bridge_imports, namespace_import_roots, runtime_export_name)};",
                )
              }
          }
        }
    }
    if ffi_import_string_subset_should_emit_wrapper(state, import_) {
      // The subset wrapper exposes the same runtime export with each
      // `string | string[]` param narrowed to plain `String`. Compute
      // whether THE SUBSET — not the original union-typed import —
      // needs JS-side arg conversion: a plain `String` slot is always
      // direct-able, even after the FFI started routing the original
      // union through a tagged-enum converter.
      let subset_needs_js_arg_conversion = ffi_import_subset_needs_js_arg_conversion(
        state, import_,
      )
      let subset_needs_js_return_conversion = ffi_import_needs_js_return_conversion(
        state, import_,
      )
      if subset_needs_js_arg_conversion || subset_needs_js_return_conversion {
        bridge_needs_option_unwrap = true
      }
      let subset_fn_name = ffi_func_string_subset_name(import_.name)
      if ffi_can_use_direct_runtime_export(module_spec, runtime_export_name) &&
        !ffi_runtime_export_requires_bridge(runtime_export_name) &&
        !subset_needs_js_arg_conversion &&
        !subset_needs_js_return_conversion {
        push_unique_ffi_section(
          seen_ffi_binding_names,
          ffi_sections,
          ffi_fn_decl_key(subset_fn_name),
          ffi_import_string_subset_decl_to_moonbit_direct(
            state, import_, runtime_export_name, module_spec,
          ),
        )
      } else {
        let subset_binding_name = ffi_func_string_subset_binding_name(
          import_.name,
        )
        push_unique_ffi_section(
          seen_ffi_binding_names,
          ffi_sections,
          ffi_fn_decl_key(subset_fn_name),
          ffi_import_string_subset_decl_to_moonbit(state, import_),
        )
        let args = ffi_import_bridge_param_names(import_, runtime_export_name)
        let call_args = ffi_import_call_args_with_names(state, import_, args)
        let call_args_str = call_args.join(", ")
        let runtime_access = ensure_bridge_runtime_access(
          seen_bridge_import_keys, bridge_imports, namespace_import_roots, runtime_export_name,
        )
        let return_expr = ffi_type_js_return_expr(
          state,
          import_.return_type,
          "\{runtime_access}(\{call_args_str})",
        )
        push_unique_bridge_binding(
          seen_bridge_binding_names,
          bridge_lines,
          subset_binding_name,
          ffi_bridge_function_line(subset_binding_name, args, return_expr),
        )
      }
    }
    if ffi_is_node_assert_module_spec(module_spec) {
      match ffi_node_assert_primitive_wrapper(import_.name) {
        Some((fn_name, _, bridge_params, call_args)) => {
          bridge_needs_option_unwrap = true
          let binding_name = "__ts_mbt_" + fn_name
          match ffi_node_assert_primitive_decl(import_.name) {
            Some(decl) =>
              push_unique_ffi_section(
                seen_ffi_binding_names,
                ffi_sections,
                ffi_fn_decl_key(fn_name),
                decl,
              )
            None => ()
          }
          let runtime_access = ensure_bridge_runtime_access(
            seen_bridge_import_keys, bridge_imports, namespace_import_roots, runtime_export_name,
          )
          let call_args_src = call_args.join(", ")
          push_unique_bridge_binding(
            seen_bridge_binding_names,
            bridge_lines,
            binding_name,
            ffi_bridge_function_line(
              binding_name,
              bridge_params,
              "\{runtime_access}(\{call_args_src})",
            ),
          )
        }
        None => ()
      }
    }
    handled_export_names.push(import_.name)
  }

  for func in funcs {
    let runtime_export_name = runtime_export_name_for(
      func_runtime_export_names,
      func.name,
    )
    let needs_js_arg_conversion = ffi_func_needs_js_arg_conversion(state, func)
    let needs_js_return_conversion = ffi_func_needs_js_return_conversion(
      state, func,
    )
    if needs_js_arg_conversion || needs_js_return_conversion {
      bridge_needs_option_unwrap = true
    }
    match tuple_result_field_names.get(func.name) {
      Some(field_names) => {
        let binding_name = ffi_binding_name(func.name)
        let args = ffi_func_bridge_param_names(func, runtime_export_name)
        let call_args = ffi_func_call_args_with_names(state, func, args)
        let args_str = call_args.join(", ")
        let runtime_access = ensure_bridge_runtime_access(
          seen_bridge_import_keys, bridge_imports, namespace_import_roots, runtime_export_name,
        )
        let call_expr = "\{runtime_access}(\{args_str})"
        push_unique_ffi_section(
          seen_ffi_binding_names,
          ffi_sections,
          ffi_fn_decl_key(ffi_value_fn_name(func.name)),
          ffi_func_decl_to_moonbit(state, func),
        )
        push_unique_bridge_binding(
          seen_bridge_binding_names,
          bridge_lines,
          binding_name,
          ffi_bridge_tuple_wrapper_line(
            binding_name, args, call_expr, field_names,
          ),
        )
      }
      None =>
        if ffi_can_use_direct_runtime_export(module_spec, runtime_export_name) &&
          !ffi_runtime_export_requires_bridge(runtime_export_name) &&
          !needs_js_arg_conversion &&
          !needs_js_return_conversion {
          push_unique_ffi_section(
            seen_ffi_binding_names,
            ffi_sections,
            ffi_fn_decl_key(ffi_value_fn_name(func.name)),
            ffi_func_decl_to_moonbit_direct(
              state, func, runtime_export_name, module_spec,
            ),
          )
        } else {
          let binding_name = ffi_binding_name(func.name)
          push_unique_ffi_section(
            seen_ffi_binding_names,
            ffi_sections,
            ffi_fn_decl_key(ffi_value_fn_name(func.name)),
            ffi_func_decl_to_moonbit(state, func),
          )
          match
            ffi_bridge_reexport_line(
              module_spec, runtime_export_name, binding_name,
            ) {
            Some(reexport_line) =>
              if !needs_js_arg_conversion && !needs_js_return_conversion {
                push_unique_bridge_binding(
                  seen_bridge_binding_names, bridge_lines, binding_name, reexport_line,
                )
              } else {
                let args = ffi_func_bridge_param_names(
                  func, runtime_export_name,
                )
                let call_args = ffi_func_call_args_with_names(state, func, args)
                let call_args_str = call_args.join(", ")
                let runtime_access = ensure_bridge_runtime_access(
                  seen_bridge_import_keys, bridge_imports, namespace_import_roots,
                  runtime_export_name,
                )
                let return_expr = ffi_type_js_return_expr(
                  state,
                  func.return_type,
                  "\{runtime_access}(\{call_args_str})",
                )
                push_unique_bridge_binding(
                  seen_bridge_binding_names,
                  bridge_lines,
                  binding_name,
                  ffi_bridge_function_line(binding_name, args, return_expr),
                )
              }
            None =>
              if needs_js_arg_conversion || needs_js_return_conversion {
                let args = ffi_func_bridge_param_names(
                  func, runtime_export_name,
                )
                let call_args = ffi_func_call_args_with_names(state, func, args)
                let call_args_str = call_args.join(", ")
                let runtime_access = ensure_bridge_runtime_access(
                  seen_bridge_import_keys, bridge_imports, namespace_import_roots,
                  runtime_export_name,
                )
                let return_expr = ffi_type_js_return_expr(
                  state,
                  func.return_type,
                  "\{runtime_access}(\{call_args_str})",
                )
                push_unique_bridge_binding(
                  seen_bridge_binding_names,
                  bridge_lines,
                  binding_name,
                  ffi_bridge_function_line(binding_name, args, return_expr),
                )
              } else {
                push_unique_bridge_binding(
                  seen_bridge_binding_names,
                  bridge_lines,
                  binding_name,
                  "export const \{binding_name} = \{ensure_bridge_runtime_access(seen_bridge_import_keys, bridge_imports, namespace_import_roots, runtime_export_name)};",
                )
              }
          }
        }
    }
    if ffi_func_string_subset_should_emit_wrapper(state, func) {
      let subset_needs_js_arg_conversion = ffi_func_subset_needs_js_arg_conversion(
        state, func,
      )
      let subset_needs_js_return_conversion = ffi_func_needs_js_return_conversion(
        state, func,
      )
      if subset_needs_js_arg_conversion || subset_needs_js_return_conversion {
        bridge_needs_option_unwrap = true
      }
      let subset_fn_name = ffi_func_string_subset_name(func.name)
      if ffi_can_use_direct_runtime_export(module_spec, runtime_export_name) &&
        !ffi_runtime_export_requires_bridge(runtime_export_name) &&
        !subset_needs_js_arg_conversion &&
        !subset_needs_js_return_conversion {
        push_unique_ffi_section(
          seen_ffi_binding_names,
          ffi_sections,
          ffi_fn_decl_key(subset_fn_name),
          ffi_func_string_subset_decl_to_moonbit_direct(
            state, func, runtime_export_name, module_spec,
          ),
        )
      } else {
        let subset_binding_name = ffi_func_string_subset_binding_name(func.name)
        push_unique_ffi_section(
          seen_ffi_binding_names,
          ffi_sections,
          ffi_fn_decl_key(subset_fn_name),
          ffi_func_string_subset_decl_to_moonbit(state, func),
        )
        let args = ffi_func_bridge_param_names(func, runtime_export_name)
        let call_args = ffi_func_call_args_with_names(state, func, args)
        let call_args_str = call_args.join(", ")
        let runtime_access = ensure_bridge_runtime_access(
          seen_bridge_import_keys, bridge_imports, namespace_import_roots, runtime_export_name,
        )
        let return_expr = ffi_type_js_return_expr(
          state,
          func.return_type,
          "\{runtime_access}(\{call_args_str})",
        )
        push_unique_bridge_binding(
          seen_bridge_binding_names,
          bridge_lines,
          subset_binding_name,
          ffi_bridge_function_line(subset_binding_name, args, return_expr),
        )
      }
    }
    if ffi_is_node_assert_module_spec(module_spec) {
      match ffi_node_assert_primitive_wrapper(func.name) {
        Some((fn_name, _, bridge_params, call_args)) => {
          bridge_needs_option_unwrap = true
          let binding_name = "__ts_mbt_" + fn_name
          match ffi_node_assert_primitive_decl(func.name) {
            Some(decl) =>
              push_unique_ffi_section(
                seen_ffi_binding_names,
                ffi_sections,
                ffi_fn_decl_key(fn_name),
                decl,
              )
            None => ()
          }
          let runtime_access = ensure_bridge_runtime_access(
            seen_bridge_import_keys, bridge_imports, namespace_import_roots, runtime_export_name,
          )
          let call_args_src = call_args.join(", ")
          push_unique_bridge_binding(
            seen_bridge_binding_names,
            bridge_lines,
            binding_name,
            ffi_bridge_function_line(
              binding_name,
              bridge_params,
              "\{runtime_access}(\{call_args_src})",
            ),
          )
        }
        None => ()
      }
    }
    handled_export_names.push(func.name)
  }

  if ffi_is_react_router_module_spec(module_spec) {
    push_unique_ffi_section(
      seen_ffi_binding_names,
      ffi_sections,
      ffi_fn_decl_key("params_from_pairs"),
      "pub extern \"js\" fn params_from_pairs(keys : Array[String], values : Array[String]) -> Params = \"__ts_mbt_params_from_pairs\"",
    )
    push_unique_bridge_binding(
      seen_bridge_binding_names, bridge_lines, "__ts_mbt_params_from_pairs", "export function __ts_mbt_params_from_pairs(keys, values) { const out = {}; for (let i = 0; i < keys.length; i++) out[keys[i]] = values[i]; return out; }",
    )
    let runtime_export_name = runtime_export_name_for(
      func_runtime_export_names, "generatePath",
    )
    let runtime_access = ensure_bridge_runtime_access(
      seen_bridge_import_keys, bridge_imports, namespace_import_roots, runtime_export_name,
    )
    push_unique_ffi_section(
      seen_ffi_binding_names,
      ffi_sections,
      ffi_fn_decl_key("generate_path_params"),
      "pub extern \"js\" fn generate_path_params(originalPath : String, params : Params) -> String = \"__ts_mbt_generate_path_params\"",
    )
    push_unique_bridge_binding(
      seen_bridge_binding_names,
      bridge_lines,
      "__ts_mbt_generate_path_params",
      "export function __ts_mbt_generate_path_params(originalPath, params) { return \{runtime_access}(originalPath, params); }",
    )
  }

  if ffi_is_jose_module_spec(module_spec) {
    push_unique_ffi_section(
      seen_ffi_binding_names,
      ffi_sections,
      ffi_fn_decl_key("unsecured_jwt_set_issued_at_double"),
      "pub extern \"js\" fn unsecured_jwt_set_issued_at_double(jwt : UnsecuredJWT, input : Double) -> UnsecuredJWT = \"__ts_mbt_unsecured_jwt_set_issued_at_double\"",
    )
    push_unique_bridge_binding(
      seen_bridge_binding_names, bridge_lines, "__ts_mbt_unsecured_jwt_set_issued_at_double",
      "export function __ts_mbt_unsecured_jwt_set_issued_at_double(jwt, input) { return jwt.setIssuedAt(input); }",
    )
    push_unique_ffi_section(
      seen_ffi_binding_names,
      ffi_sections,
      ffi_fn_decl_key("sign_jwt_set_issued_at_double"),
      "pub extern \"js\" fn sign_jwt_set_issued_at_double(signer : SignJWT, input : Double) -> SignJWT = \"__ts_mbt_sign_jwt_set_issued_at_double\"",
    )
    push_unique_bridge_binding(
      seen_bridge_binding_names, bridge_lines, "__ts_mbt_sign_jwt_set_issued_at_double",
      "export function __ts_mbt_sign_jwt_set_issued_at_double(signer, input) { return signer.setIssuedAt(input); }",
    )
    push_unique_ffi_section(
      seen_ffi_binding_names,
      ffi_sections,
      ffi_fn_decl_key("unsecured_jwt_set_not_before_double"),
      "pub extern \"js\" fn unsecured_jwt_set_not_before_double(jwt : UnsecuredJWT, input : Double) -> UnsecuredJWT = \"__ts_mbt_unsecured_jwt_set_not_before_double\"",
    )
    push_unique_bridge_binding(
      seen_bridge_binding_names, bridge_lines, "__ts_mbt_unsecured_jwt_set_not_before_double",
      "export function __ts_mbt_unsecured_jwt_set_not_before_double(jwt, input) { return jwt.setNotBefore(input); }",
    )
    push_unique_ffi_section(
      seen_ffi_binding_names,
      ffi_sections,
      ffi_fn_decl_key("sign_jwt_set_not_before_double"),
      "pub extern \"js\" fn sign_jwt_set_not_before_double(signer : SignJWT, input : Double) -> SignJWT = \"__ts_mbt_sign_jwt_set_not_before_double\"",
    )
    push_unique_bridge_binding(
      seen_bridge_binding_names, bridge_lines, "__ts_mbt_sign_jwt_set_not_before_double",
      "export function __ts_mbt_sign_jwt_set_not_before_double(signer, input) { return signer.setNotBefore(input); }",
    )
    push_unique_ffi_section(
      seen_ffi_binding_names,
      ffi_sections,
      ffi_fn_decl_key("unsecured_jwt_set_expiration_time_double"),
      "pub extern \"js\" fn unsecured_jwt_set_expiration_time_double(jwt : UnsecuredJWT, input : Double) -> UnsecuredJWT = \"__ts_mbt_unsecured_jwt_set_expiration_time_double\"",
    )
    push_unique_bridge_binding(
      seen_bridge_binding_names, bridge_lines, "__ts_mbt_unsecured_jwt_set_expiration_time_double",
      "export function __ts_mbt_unsecured_jwt_set_expiration_time_double(jwt, input) { return jwt.setExpirationTime(input); }",
    )
    push_unique_ffi_section(
      seen_ffi_binding_names,
      ffi_sections,
      ffi_fn_decl_key("sign_jwt_set_expiration_time_double"),
      "pub extern \"js\" fn sign_jwt_set_expiration_time_double(signer : SignJWT, input : Double) -> SignJWT = \"__ts_mbt_sign_jwt_set_expiration_time_double\"",
    )
    push_unique_bridge_binding(
      seen_bridge_binding_names, bridge_lines, "__ts_mbt_sign_jwt_set_expiration_time_double",
      "export function __ts_mbt_sign_jwt_set_expiration_time_double(signer, input) { return signer.setExpirationTime(input); }",
    )
  }

  if ffi_is_node_util_module_spec(module_spec) {
    let runtime_access = ensure_bridge_runtime_access(
      seen_bridge_import_keys, bridge_imports, namespace_import_roots, "isArray",
    )
    push_unique_ffi_section(
      seen_ffi_binding_names,
      ffi_sections,
      ffi_fn_decl_key("is_array_string_array"),
      "pub extern \"js\" fn is_array_string_array(value : Array[String]) -> Bool = \"__ts_mbt_is_array_string_array\"",
    )
    push_unique_bridge_binding(
      seen_bridge_binding_names,
      bridge_lines,
      "__ts_mbt_is_array_string_array",
      "export function __ts_mbt_is_array_string_array(value) { return \{runtime_access}(value); }",
    )
  }

  for value in values {
    match value.type_ {
      Struct(name, fields) => {
        let type_name = ffi_type_identifier(name, "OpaqueType")
        if !state.declared_type_names.contains(type_name) {
          state.declared_type_names.push(type_name)
        }
        if ffi_struct_fields_need_js_converter(state.enums, fields) &&
          !state.struct_type_names.contains(type_name) {
          state.struct_type_names.push(type_name)
        }
        push_unique_ffi_section(
          seen_ffi_binding_names,
          ffi_sections,
          "struct:" + type_name,
          ffi_named_struct_decl_to_moonbit(state, name, fields),
        )
        if state.struct_type_names.contains(type_name) {
          bridge_struct_converter_lines.push(
            ffi_struct_js_converter_decl(state, name, fields),
          )
        }
      }
      _ => ()
    }
    let runtime_export_name = runtime_export_name_for(
      value_runtime_export_names,
      value.name,
    )
    let getter_name = "__ts_mbt_get_" + ffi_to_snake_case(value.name)
    push_unique_ffi_section(
      seen_ffi_binding_names,
      ffi_sections,
      ffi_fn_decl_key(ffi_namespace_getter_name(value.name)),
      ffi_value_decl_to_moonbit(state, value),
    )
    push_unique_bridge_binding(
      seen_bridge_binding_names,
      bridge_lines,
      getter_name,
      ffi_bridge_function_line(
        getter_name,
        [],
        ensure_bridge_value_runtime_access(
          seen_bridge_import_keys, bridge_imports, namespace_import_roots, module_spec,
          runtime_export_name,
        ),
      ),
    )
    match value.type_ {
      Func(params, return_type) =>
        if ffi_callable_value_should_emit_wrapper(state, params, return_type) {
          let binding_name = ffi_binding_name(value.name)
          let needs_js_arg_conversion = ffi_callable_value_needs_js_arg_conversion(
            state, params,
          )
          let needs_js_return_conversion = ffi_type_needs_js_return_conversion(
            return_type,
          )
          if needs_js_arg_conversion || needs_js_return_conversion {
            bridge_needs_option_unwrap = true
          }
          push_unique_ffi_section(
            seen_ffi_binding_names,
            ffi_sections,
            ffi_fn_decl_key(ffi_value_fn_name(value.name)),
            ffi_callable_value_decl_to_moonbit(
              state, value, params, return_type,
            ),
          )
          let args = ffi_callable_value_param_names(params, runtime_export_name)
          let call_args = ffi_callable_value_call_args_with_names(
            state, params, args,
          )
          let call_args_str = call_args.join(", ")
          let runtime_access = ensure_bridge_value_runtime_access(
            seen_bridge_import_keys, bridge_imports, namespace_import_roots, module_spec,
            runtime_export_name,
          )
          let return_expr = ffi_type_js_return_expr(
            state,
            return_type,
            "\{runtime_access}(\{call_args_str})",
          )
          push_unique_bridge_binding(
            seen_bridge_binding_names,
            bridge_lines,
            binding_name,
            ffi_bridge_function_line(binding_name, args, return_expr),
          )
        } else {
          ()
        }
      _ => ()
    }
    handled_export_names.push(value.name)
  }

  for export_ in export_surface {
    if export_.kind == Namespace || export_.kind == Ambiguous {
      continue
    }
    match exported_local_namespace_decl(export_, modules) {
      Some(_) => continue
      None => ()
    }
    if handled_export_names.contains(export_.export_name) {
      continue
    }
    if resolved_export_is_non_runtime_value(export_, modules) {
      continue
    }
    let fallback_value : @ast.TsValueDecl = {
      name: export_.export_name,
      type_: @ast.TsType::Any,
    }
    let getter_name = "__ts_mbt_get_" + ffi_to_snake_case(export_.export_name)
    push_unique_ffi_section(
      seen_ffi_binding_names,
      ffi_sections,
      ffi_fn_decl_key(ffi_namespace_getter_name(export_.export_name)),
      ffi_value_decl_to_moonbit(state, fallback_value),
    )
    push_unique_bridge_binding(
      seen_bridge_binding_names,
      bridge_lines,
      getter_name,
      ffi_bridge_function_line(
        getter_name,
        [],
        if ffi_module_spec_uses_public_exports(module_spec) {
          ensure_bridge_module_runtime_access(
            seen_bridge_import_keys,
            bridge_imports,
            export_.export_name,
          )
        } else {
          ensure_bridge_import(
            seen_bridge_import_keys,
            bridge_imports,
            export_.export_name,
          )
        },
      ),
    )
  }

  let alias_constructor_sections : Array[String] = []
  let alias_candidate_type_names : Array[String] = []
  for type_name in state.external_type_names {
    alias_candidate_type_names.push(type_name)
  }
  for tagged in exported_tagged_unions {
    let type_name = ffi_type_identifier(tagged.decl.name, "OpaqueType")
    if !alias_candidate_type_names.contains(type_name) {
      alias_candidate_type_names.push(type_name)
    }
  }
  for type_name in alias_candidate_type_names {
    if state.declared_type_names.contains(type_name) &&
      !state.tagged_union_decls_by_name.contains(type_name) {
      continue
    }
    match type_aliases_by_type_name.get(type_name) {
      Some(type_alias) => {
        let ctors = ffi_type_alias_constructors(state, type_alias)
        for ctor in ctors {
          alias_constructor_sections.push(
            ffi_alias_constructor_decl(state, type_name, ctor),
          )
          push_unique_bridge_binding(
            seen_bridge_binding_names,
            bridge_lines,
            ctor.binding_name,
            ffi_alias_constructor_bridge_line(ctor),
          )
        }
      }
      None => ()
    }
  }

  // Emit any inline-union aliases that the lowering passes synthesised on
  // the side. Names are sorted for deterministic output across runs. Run
  // before the external-type emission below so any inner Named payloads
  // referenced from synthesized cases get a `#external; type N` companion
  // declaration in the same file.
  let synthesized_names : Array[String] = []
  for entry in state.synthesized_inline_unions {
    synthesized_names.push(entry.0)
  }
  synthesized_names.sort()
  for synth_name in synthesized_names {
    let decl = state.synthesized_inline_unions.get(synth_name).unwrap()
    if !emitted_type_names.contains(synth_name) {
      emitted_type_names.push(synth_name)
      for entry in decl.cases {
        let (_, inner) = entry
        let inner_named = match inner {
          @ast.TsType::Named(name) => Some(name)
          @ast.TsType::Array(@ast.TsType::Named(name)) => Some(name)
          _ => None
        }
        match inner_named {
          Some(inner_name) => {
            let _ = ffi_mark_external_type(state, inner_name)
          }
          None => ()
        }
      }
      match
        tagged_union_decl_to_moonbit_section_with_arity(
          decl,
          state.generic_type_params_by_name,
        ) {
        Some(section) => ffi_sections.push(section)
        None => ()
      }
    }
    match
      tagged_union_bridge_js_converter_decls_with_nested(
        decl,
        state.tagged_union_decls_by_name,
        struct_converter_names=state.struct_type_names,
      ) {
      Some(decls) => bridge_lines.push(decls)
      None => ()
    }
  }

  state.external_type_names.sort()
  for type_name in state.external_type_names {
    if state.declared_type_names.contains(type_name) {
      continue
    }
    // The self-contained `pub type Promise[X]` / `pub type JSValue`
    // declarations below own these names. Skip the parameterless
    // `#external type Promise` / `#external type JSValue` emission so the
    // generated package doesn't redeclare them.
    if (type_name == "Promise" && state.needs_promise) ||
      (type_name == "JSValue" && state.needs_js_any) {
      continue
    }
    // Match the `.mbti` declaration of the same type (`declare pub type X`)
    // by emitting `pub type X` here. Without `pub`, consumers of the
    // generated package can't see the type even though `.mbti` says they
    // can, breaking the publicly-advertised surface.
    //
    // If the type was registered as generic-preserved, suffix the
    // declaration with the type-param list so call-site references
    // `Foo[JSValue]` resolve against a matching arity.
    let type_param_suffix = match
      state.generic_type_params_by_name.get(type_name) {
      Some(type_params) => ffi_type_param_suffix(type_params)
      None => ""
    }
    ffi_sections.push(
      "#warnings(\"-3\")\n#external\npub type \{type_name}\{type_param_suffix}",
    )
  }
  for section in alias_constructor_sections {
    ffi_sections.push(section)
  }

  // Emit self-contained `#external` declarations for the opaque types
  // the FFI layer references. Keeping them in `externs.mbt` (instead of
  // only `bridge.mbt`) means the file still compiles in isolation
  // without any `mizchi/js` import.
  if state.needs_js_any {
    ffi_sections.insert(2, "#external\npub type JSValue")
  }
  if state.needs_promise {
    ffi_sections.insert(2, "#external\npub type Promise[X]")
  }

  let rendered_bridge_lines : Array[String] = [
    "// AUTO-GENERATED by `ts2mbt` (mizchi/ts). DO NOT EDIT -- your changes", "// will be lost on the next `ts2mbt generate` / `ts2mbt vendor`.",
  ]
  match render_bridge_import_line(module_spec, bridge_imports) {
    Some(import_line) => {
      rendered_bridge_lines.push(import_line)
      rendered_bridge_lines.push("")
    }
    None => ()
  }
  if bridge_needs_option_unwrap || !bridge_struct_converter_lines.is_empty() {
    rendered_bridge_lines.push(
      "function __ts_mbt_unwrap_option(value) { if (value == null) return undefined; if (typeof value === \"object\" && \"$tag\" in value) return value.$tag === 1 ? value._0 : undefined; return value; }",
    )
    rendered_bridge_lines.push(
      "function __ts_mbt_unwrap_bool_option(value) { return value === -1 ? undefined : __ts_mbt_unwrap_option(value); }",
    )
    rendered_bridge_lines.push(
      "function __ts_mbt_wrap_bool_option(value) { return value == null ? -1 : value; }",
    )
    rendered_bridge_lines.push("")
  }
  if !bridge_struct_converter_lines.is_empty() {
    for line in bridge_enum_converter_lines {
      rendered_bridge_lines.push(line)
      rendered_bridge_lines.push("")
    }
  }
  for line in bridge_struct_converter_lines {
    rendered_bridge_lines.push(line)
    rendered_bridge_lines.push("")
  }
  for line in bridge_lines {
    rendered_bridge_lines.push(line)
  }

  {
    ffi_mbt: ffi_sections.join("\n\n"),
    bridge_js: rendered_bridge_lines.join("\n"),
  }
}
