///|
priv struct MoonBitDeclState {
  declared_interface_names : Array[String]
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
fn mark_referenced_type(state : MoonBitDeclState, name : String) -> Unit {
  if name == "Array" || name == "ReadonlyArray" {
    return
  }
  if state.declared_interface_names.contains(name) {
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
      sanitize_identifier(name, "OpaqueType")
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
  let type_name = sanitize_identifier(iface.name, "OpaqueType")
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
pub fn emit_moonbit_decl(module_ : @ast.TsModule) -> String {
  let declared_interface_names : Array[String] = []
  for iface in module_.interfaces {
    declared_interface_names.push(iface.name)
  }
  let state : MoonBitDeclState = {
    declared_interface_names,
    referenced_type_names: [],
    needs_jsvalue: false,
  }
  let interface_sections : Array[String] = []
  for iface in module_.interfaces {
    interface_sections.push(interface_decl_to_moonbit(state, iface))
  }
  let import_sections : Array[String] = []
  for import_ in module_.imports {
    import_sections.push(import_decl_to_moonbit(state, import_))
  }
  let sections : Array[String] = [
    "///|\n/// Generated from TypeScript declarations by mizchi/ts/parser.\n/// Complex or unsupported TypeScript types are widened to JSValue.",
  ]
  if state.needs_jsvalue {
    sections.push("///|\ndeclare pub type JSValue")
  }
  for section in interface_sections {
    sections.push(section)
  }
  let referenced : Array[String] = []
  for name in state.referenced_type_names {
    referenced.push(sanitize_identifier(name, "OpaqueType"))
  }
  referenced.sort()
  for name in referenced {
    sections.push("///|\ndeclare pub type \{name}")
  }
  for section in import_sections {
    sections.push(section)
  }
  sections.join("\n\n")
}

///|
pub fn emit_moonbit_decl_from_source(
  source : String,
) -> String raise ParseError {
  let parser = Parser::from_source(source)
  let module_ = parser.parse_module()
  emit_moonbit_decl(module_)
}
