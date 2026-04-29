///|
priv struct MoonBitDeclState {
  declared_type_names : Array[String]
  referenced_type_names : Array[String]
  mut needs_jsvalue : Bool
}

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
    | "fn"
    | "for"
    | "if"
    | "in"
    | "is"
    | "let"
    | "loop"
    | "match"
    | "pub"
    | "ref"
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
    | "pub"
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
  let first = sanitized[0].unsafe_to_char()
  let normalized = if first >= 'a' && first <= 'z' {
    (first.to_int() - 32).unsafe_to_char().to_string() +
    sanitized[1:].to_string()
  } else {
    sanitized
  }
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
fn normalize_literal_type_for_moonbit_bridge(
  type_ : @ast.TsType,
) -> @ast.TsType {
  match type_ {
    Literal("true") | Literal("false") => Boolean
    Literal(_) => String_
    _ => type_
  }
}

///|
fn classify_optional_like_union(type_ : @ast.TsType) -> (@ast.TsType, Bool)? {
  match type_ {
    Union(items) => {
      let mut concrete : @ast.TsType? = None
      let mut has_any = false
      let mut is_optional = false
      for item in items {
        match item {
          Any => has_any = true
          Undefined | Null => is_optional = true
          _ => {
            let normalized = normalize_literal_type_for_moonbit_bridge(item)
            match concrete {
              Some(existing) => if existing != normalized { return None }
              None => concrete = Some(normalized)
            }
          }
        }
      }
      match concrete {
        Some(inner) => if has_any { None } else { Some((inner, is_optional)) }
        None => if has_any { Some((Any, is_optional)) } else { None }
      }
    }
    _ => None
  }
}

///|
fn moonbit_type_name(state : MoonBitDeclState, type_ : @ast.TsType) -> String {
  match classify_optional_like_union(type_) {
    Some((collapsed, is_optional)) => {
      let suffix = if is_optional { "?" } else { "" }
      return moonbit_type_name(state, collapsed) + suffix
    }
    None => ()
  }
  match type_ {
    Literal(_) =>
      moonbit_type_name(state, normalize_literal_type_for_moonbit_bridge(type_))
    Number => "Double"
    Int => "Int"
    Boolean => "Bool"
    String_ => "String"
    Void => "Unit"
    Array(inner) => "Array[" + moonbit_type_name(state, inner) + "]"
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
    Named(name) => {
      mark_referenced_type(state, name)
      moonbit_type_identifier(name, "OpaqueType")
    }
    Applied(name, _) => {
      mark_referenced_type(state, name)
      moonbit_type_identifier(name, "OpaqueType")
    }
    _ => {
      state.needs_jsvalue = true
      "JSValue"
    }
  }
}

///|
fn interface_decl_to_moonbit(
  state : MoonBitDeclState,
  iface : @ast.TsInterface,
) -> String {
  let lines : Array[String] = ["///|", "/// TS interface \{iface.name}"]
  for field in iface.fields {
    let (name, type_) = field
    let moonbit_type = moonbit_type_name(state, type_)
    lines.push("/// \{name} : \{moonbit_type}")
  }
  let type_name = moonbit_type_identifier(iface.name, "OpaqueType")
  lines.push("declare pub type \{type_name}")
  lines.join("\n")
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
pub fn emit_moonbit_decl_with_sections(
  module_ : @ast.TsModule,
  extra_sections : Array[String],
  force_jsvalue : Bool,
) -> String {
  let declared_type_names : Array[String] = []
  for iface in module_.interfaces {
    declared_type_names.push(iface.name)
  }
  for class_ in module_.classes {
    declared_type_names.push(class_.name)
  }
  let state : MoonBitDeclState = {
    declared_type_names,
    referenced_type_names: [],
    needs_jsvalue: false,
  }
  let interface_sections : Array[String] = []
  let seen_type_decl_names : Array[String] = []
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
