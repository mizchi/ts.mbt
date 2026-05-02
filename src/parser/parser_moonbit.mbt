///|
priv struct MoonBitDeclState {
  declared_type_names : Array[String]
  referenced_type_names : Array[String]
  local_type_param_names : Array[String]
  // Names of declared types whose generic parameters should appear on
  // `Applied(name, args)` references (e.g. `Box<string>` ⇒ `Box[String]`).
  generic_preserved_type_names : Array[String]
  mut needs_jsvalue : Bool
}

///|
let moonbit_function_field_method_wrapper_limit : Int = 16

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
    "as"
    | "break"
    | "catch"
    | "const"
    | "continue"
    | "defer"
    | "else"
    | "final"
    | "fn"
    | "for"
    | "if"
    | "in"
    | "is"
    | "let"
    | "loop"
    | "match"
    | "method"
    | "move"
    | "constructor"
    | "override"
    | "priv"
    | "pub"
    | "ref"
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
    | "while" => true
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
    (first.to_int() + 32).unsafe_to_char().to_string() + name[1:].to_string()
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
    "as"
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
  let core = sanitized[idx:sanitized.length()].to_string()
  if core == "" {
    return fallback
  }
  let first = core[0].unsafe_to_char()
  let normalized_core = if first >= 'a' && first <= 'z' {
    (first.to_int() - 32).unsafe_to_char().to_string() + core[1:].to_string()
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
    "[" + type_params.join(", ") + "]"
  }
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
fn moonbit_should_preserve_interface_type_params(
  iface : @ast.TsInterface,
) -> Bool {
  match iface.name {
    "StatsBase"
    | "StatsFsBase"
    | "SignalLike"
    | "RefObject"
    | "RefCallback"
    | "Router"
    | "TypedResponse" => true
    _ => false
  }
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
  let return_src = moonbit_type_name(state, return_type)
  "(\{params_src}) -> \{return_src}"
}

///|
fn moonbit_type_name(state : MoonBitDeclState, type_ : @ast.TsType) -> String {
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
    Applied("Promise", [inner]) | Applied("PromiseLike", [inner]) =>
      "@js.Promise[" + moonbit_type_name(state, inner) + "]"
    Named(name) if is_local_type_param(state, name) => name
    Applied(name, _) if is_local_type_param(state, name) => name
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
      moonbit_type_identifier(name, "OpaqueType")
    }
    Applied(name, args) => {
      mark_referenced_type(state, name)
      let rendered = moonbit_type_identifier(name, "OpaqueType")
      if state.generic_preserved_type_names.contains(name) && args.length() > 0 {
        let parts : Array[String] = []
        for arg in args {
          parts.push(moonbit_type_name(state, arg))
        }
        let joined = parts.join(", ")
        "\{rendered}[\{joined}]"
      } else {
        rendered
      }
    }
    _ => {
      state.needs_jsvalue = true
      "JSValue"
    }
  }
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
      Some((param_types, moonbit_type_name(state, return_type)))
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
    Some((param_types, return_type)) => {
      let self_type = moonbit_receiver_self_type(
        receiver_type, receiver_type_params,
      )
      let params : Array[String] = []
      for i, param_type in param_types {
        let arg_name = "arg" + i.to_string()
        params.push("\{arg_name} : \{param_type}")
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
fn interface_decl_to_moonbit(
  state : MoonBitDeclState,
  iface : @ast.TsInterface,
) -> String {
  let active_type_params = if moonbit_should_preserve_interface_type_params(
      iface,
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
    let (name, type_) = field
    let moonbit_type = moonbit_function_field_type_name(state, type_)
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
  name[start:end_].to_string()
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
fn class_decl_to_moonbit_sections(
  state : MoonBitDeclState,
  class_ : @ast.TsClassDecl,
) -> Array[String] {
  let sections : Array[String] = []
  let seen_binding_names : Array[String] = []
  let type_name = moonbit_type_identifier(class_.name, "OpaqueType")
  sections.push(
    "///|\n/// TS class \{class_.name}\ndeclare pub type \{type_name}",
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
      "///|\ndeclare pub fn new_\{ctor_name}(\{ctor_params}) -> \{type_name}",
    )
  }
  for class_property in class_.properties {
    let getter_name = "get_" +
      to_snake_case(class_.name) +
      "_" +
      to_snake_case(class_property.name)
    let getter_params : Array[String] = []
    if !class_property.is_static {
      getter_params.push("self : \{type_name}")
    }
    let getter_params_str = getter_params.join(", ")
    let getter_type = moonbit_type_name(state, class_property.type_)
    push_unique_decl_section(
      seen_binding_names,
      sections,
      getter_name,
      "///|\ndeclare pub fn \{getter_name}(\{getter_params_str}) -> \{getter_type}",
    )
    if !class_property.is_readonly {
      let setter_name = "set_" +
        to_snake_case(class_.name) +
        "_" +
        to_snake_case(class_property.name)
      let setter_params : Array[String] = []
      if !class_property.is_static {
        setter_params.push("self : \{type_name}")
      }
      setter_params.push("value : \{getter_type}")
      let setter_params_str = setter_params.join(", ")
      push_unique_decl_section(
        seen_binding_names,
        sections,
        setter_name,
        "///|\ndeclare pub fn \{setter_name}(\{setter_params_str}) -> Unit",
      )
    }
  }
  for class_method in class_.methods {
    let params : Array[String] = []
    if !class_method.is_static {
      params.push("self : \{type_name}")
    }
    for param in class_method.params {
      let (param_name, param_type) = param
      let safe_name = sanitize_value_identifier(param_name, "arg")
      let safe_type = moonbit_type_name(state, param_type)
      params.push("\{safe_name} : \{safe_type}")
    }
    let return_type = moonbit_type_name(state, class_method.return_type)
    let fn_name = if class_method.is_static {
      "\{to_snake_case(class_.name)}_\{to_snake_case(class_method.name)}"
    } else {
      "\{to_snake_case(class_.name)}_\{to_snake_case(class_method.name)}"
    }
    let method_params = params.join(", ")
    push_unique_decl_section(
      seen_binding_names,
      sections,
      fn_name,
      "///|\ndeclare pub fn \{fn_name}(\{method_params}) -> \{return_type}",
    )
  }
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
  let declared_type_names : Array[String] = []
  let generic_preserved_type_names : Array[String] = []
  for iface in module_.interfaces {
    declared_type_names.push(iface.name)
    if moonbit_should_preserve_interface_type_params(iface) {
      generic_preserved_type_names.push(iface.name)
    }
  }
  for class_ in module_.classes {
    declared_type_names.push(class_.name)
  }
  for enum_ in module_.enums {
    declared_type_names.push(enum_.name)
  }
  let state : MoonBitDeclState = {
    declared_type_names,
    referenced_type_names: [],
    local_type_param_names: [],
    generic_preserved_type_names,
    needs_jsvalue: false,
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
    "///|\n/// Generated from TypeScript declarations by mizchi/ts/parser.\n/// Complex or unsupported TypeScript types are widened to JSValue.",
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
