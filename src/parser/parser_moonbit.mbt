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
fn sanitize_identifier(name : String, fallback : String) -> String {
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
  match result {
    "as"
    | "break"
    | "catch"
    | "const"
    | "continue"
    | "else"
    | "fn"
    | "for"
    | "if"
    | "in"
    | "let"
    | "match"
    | "pub"
    | "return"
    | "struct"
    | "test"
    | "trait"
    | "type"
    | "typealias"
    | "while" => result + "_"
    _ => result
  }
}

///|
fn moonbit_type_identifier(name : String, fallback : String) -> String {
  let sanitized = sanitize_identifier(name, fallback)
  if sanitized == "default" {
    "Default"
  } else {
    sanitized
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
fn moonbit_type_name(state : MoonBitDeclState, type_ : @ast.TsType) -> String {
  match type_ {
    Number => "Double"
    Int => "Int"
    Boolean => "Bool"
    String_ => "String"
    Void => "Unit"
    Array(inner) => "Array[" + moonbit_type_name(state, inner) + "]"
    Named("Array") | Named("ReadonlyArray") => {
      state.needs_jsvalue = true
      "Array[JSValue]"
    }
    Named(name) => {
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
    let param_name = sanitize_identifier(name, "arg")
    let param_type = moonbit_type_name(state, type_)
    params.push("\{param_name} : \{param_type}")
  }
  let return_type = moonbit_type_name(state, import_.return_type)
  let fn_name = sanitize_identifier(import_.name, "generated_fn")
  let params_str = params.join(", ")
  "///|\ndeclare pub fn \{fn_name}(\{params_str}) -> \{return_type}"
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
    let safe_name = sanitize_identifier(param_name, "arg")
    let param_type = moonbit_type_name(state, param.type_)
    params.push("\{safe_name} : \{param_type}")
  }
  let return_type = moonbit_type_name(state, func.return_type)
  let fn_name = sanitize_identifier(func.name, "generated_fn")
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
          let safe_name = sanitize_identifier(param_name, "arg")
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
      let safe_name = sanitize_identifier(param_name, "arg")
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
  for iface in module_.interfaces {
    interface_sections.push(interface_decl_to_moonbit(state, iface))
  }
  let class_sections : Array[String] = []
  for class_ in module_.classes {
    for section in class_decl_to_moonbit_sections(state, class_) {
      class_sections.push(section)
    }
  }
  let import_sections : Array[String] = []
  let seen_import_binding_names : Array[String] = []
  for import_ in module_.imports {
    let fn_name = sanitize_identifier(import_.name, "generated_fn")
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
  let func_sections : Array[String] = []
  let seen_func_binding_names : Array[String] = []
  for func in module_.funcs {
    let fn_name = sanitize_identifier(func.name, "generated_fn")
    push_unique_decl_section(
      seen_func_binding_names,
      func_sections,
      fn_name,
      func_decl_to_moonbit(state, func),
    )
  }
  let referenced : Array[String] = []
  for name in state.referenced_type_names {
    referenced.push(moonbit_type_identifier(name, "OpaqueType"))
  }
  referenced.sort()
  for name in referenced {
    sections.push("///|\ndeclare pub type \{name}")
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
