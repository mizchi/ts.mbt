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
}

///|
priv struct MoonBitJsFfiState {
  declared_type_names : Array[String]
  external_type_names : Array[String]
  mut needs_js_any : Bool
}

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
fn ffi_sanitize_identifier(name : String, fallback : String) -> String {
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
fn ffi_trim_underscores(name : String) -> String {
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
  ffi_sanitize_identifier(ffi_trim_underscores(result), "generated_name")
}

///|
fn ffi_to_pascal_case(name : String) -> String {
  let snake = ffi_to_snake_case(name)
  let parts = snake.split("_")
  let mut result = ""
  for part_view in parts {
    let part = part_view.to_string()
    if part == "" {
      continue
    }
    let first = ffi_to_upper_ascii(part[0].unsafe_to_char()).to_string()
    result += first + part[1:].to_string()
  }
  ffi_sanitize_identifier(result, "OpaqueType")
}

///|
fn ffi_mark_external_type(state : MoonBitJsFfiState, name : String) -> String {
  let type_name = ffi_to_pascal_case(name)
  if state.declared_type_names.contains(type_name) {
    return type_name
  }
  if !state.external_type_names.contains(type_name) {
    state.external_type_names.push(type_name)
  }
  type_name
}

///|
fn ffi_type_name(state : MoonBitJsFfiState, type_ : @ast.TsType) -> String {
  match type_ {
    Number => "Double"
    Int => "Int"
    Boolean => "Bool"
    String_ => "String"
    Void => "Unit"
    Array(inner) => "Array[" + ffi_type_name(state, inner) + "]"
    Named("Array") | Named("ReadonlyArray") => {
      state.needs_js_any = true
      "Array[@js.Any]"
    }
    Named(name) => ffi_mark_external_type(state, name)
    _ => {
      state.needs_js_any = true
      "@js.Any"
    }
  }
}

///|
fn ffi_struct_decl_to_moonbit(
  state : MoonBitJsFfiState,
  iface : @ast.TsInterface,
) -> String {
  let lines : Array[String] = ["pub struct \{ffi_to_pascal_case(iface.name)} {"]
  for field in iface.fields {
    let (name, type_) = field
    let field_name = ffi_sanitize_identifier(name, "field")
    let field_type = ffi_type_name(state, type_)
    lines.push("  \{field_name} : \{field_type}")
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
  let fn_name = ffi_to_snake_case(import_.name)
  let params_str = params.join(", ")
  "pub extern \"js\" fn \{fn_name}(\{params_str}) -> \{return_type} = \"\{ffi_binding_name(import_.name)}\""
}

///|
fn ffi_import_decl_to_moonbit_direct(
  state : MoonBitJsFfiState,
  import_ : @ast.TsImport,
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
  let fn_name = ffi_to_snake_case(import_.name)
  let params_str = params.join(", ")
  ffi_direct_module_decl(
    module_spec,
    "pub extern \"js\" fn \{fn_name}(\{params_str}) -> \{return_type} = \"\{import_.name}\"",
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
  let fn_name = ffi_to_snake_case(func.name)
  let params_str = params.join(", ")
  "pub extern \"js\" fn \{fn_name}(\{params_str}) -> \{return_type} = \"\{ffi_binding_name(func.name)}\""
}

///|
fn ffi_func_decl_to_moonbit_direct(
  state : MoonBitJsFfiState,
  func : @ast.TsFunc,
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
  let fn_name = ffi_to_snake_case(func.name)
  let params_str = params.join(", ")
  ffi_direct_module_decl(
    module_spec,
    "pub extern \"js\" fn \{fn_name}(\{params_str}) -> \{return_type} = \"\{func.name}\"",
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
  ffi_to_pascal_case(class_name)
}

///|
fn ffi_class_type_decl(class_name : String) -> String {
  "#external\ntype " + ffi_class_type_name(class_name)
}

///|
fn ffi_class_constructor_decl_to_moonbit(
  state : MoonBitJsFfiState,
  class_ : @ast.TsClassDecl,
) -> String? {
  if !class_.is_constructible {
    return None
  }
  let params : Array[String] = []
  match class_.constructor_params {
    Some(constructor_params) =>
      for param in constructor_params {
        let (name, type_) = param
        let safe_name = ffi_sanitize_identifier(name, "arg")
        let safe_type = ffi_type_name(state, type_)
        params.push("\{safe_name} : \{safe_type}")
      }
    None => ()
  }
  let ctor_params = params.join(", ")
  let ctor_name = ffi_to_snake_case(class_.name)
  let class_type_name = ffi_class_type_name(class_.name)
  let binding_name = ffi_class_ctor_binding_name(class_.name)
  Some(
    "pub extern \"js\" fn new_\{ctor_name}(\{ctor_params}) -> \{class_type_name} = \"\{binding_name}\"",
  )
}

///|
fn ffi_class_constructor_decl_to_moonbit_direct(
  state : MoonBitJsFfiState,
  class_ : @ast.TsClassDecl,
  module_spec : String,
) -> String? {
  if !class_.is_constructible {
    return None
  }
  let params : Array[String] = []
  let args : Array[String] = []
  match class_.constructor_params {
    Some(constructor_params) =>
      for param in constructor_params {
        let (name, type_) = param
        let safe_name = ffi_sanitize_identifier(name, "arg")
        let safe_type = ffi_type_name(state, type_)
        params.push("\{safe_name} : \{safe_type}")
        args.push(safe_name)
      }
    None => ()
  }
  let ctor_params = params.join(", ")
  let ctor_args = args.join(", ")
  let class_type_name = ffi_class_type_name(class_.name)
  let ctor_name = ffi_to_snake_case(class_.name)
  let extern_decl = ffi_direct_module_decl(
    module_spec,
    "extern \"js\" fn \{class_type_name}::new(\{ctor_params}) -> \{class_type_name} = \"\{class_.name}\"",
  )
  let wrapper_call = if ctor_args == "" {
    "\{class_type_name}::new()"
  } else {
    "\{class_type_name}::new(\{ctor_args})"
  }
  let wrapper_decl = "pub fn new_\{ctor_name}(\{ctor_params}) -> \{class_type_name} {\n  \{wrapper_call}\n}"
  Some(extern_decl + "\n\n" + wrapper_decl)
}

///|
fn ffi_class_method_decl_to_moonbit(
  state : MoonBitJsFfiState,
  class_ : @ast.TsClassDecl,
  class_method : @ast.TsClassMethodDecl,
) -> String {
  let params : Array[String] = []
  let js_args : Array[String] = []
  if !class_method.is_static {
    params.push("self : \{ffi_class_type_name(class_.name)}")
  }
  for param in class_method.params {
    let (name, type_) = param
    let safe_name = ffi_sanitize_identifier(name, "arg")
    let safe_type = ffi_type_name(state, type_)
    js_args.push(safe_name)
    params.push("\{safe_name} : \{safe_type}")
  }
  let return_type = ffi_type_name(state, class_method.return_type)
  let fn_name = ffi_to_snake_case(class_.name) +
    "_" +
    ffi_to_snake_case(class_method.name)
  let method_params = params.join(", ")
  let binding_name = ffi_class_method_binding_name(
    class_.name,
    class_method.name,
  )
  if class_method.is_static {
    "pub extern \"js\" fn \{fn_name}(\{method_params}) -> \{return_type} = \"\{binding_name}\""
  } else {
    let js_params : Array[String] = ["self"]
    for arg in js_args {
      js_params.push(arg)
    }
    let js_param_list = js_params.join(", ")
    let js_call = ffi_js_access("self", class_method.name) +
      "(" +
      js_args.join(", ") +
      ")"
    "pub extern \"js\" fn \{fn_name}(\{method_params}) -> \{return_type} =\n  #| (\{js_param_list}) => \{js_call}"
  }
}

///|
fn ffi_class_property_getter_decl_to_moonbit(
  state : MoonBitJsFfiState,
  class_ : @ast.TsClassDecl,
  class_property : @ast.TsClassPropertyDecl,
) -> String {
  let params : Array[String] = []
  if !class_property.is_static {
    params.push("self : \{ffi_class_type_name(class_.name)}")
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
  if class_property.is_static {
    "pub extern \"js\" fn \{fn_name}(\{getter_params}) -> \{return_type} = \"\{binding_name}\""
  } else {
    let js_get = ffi_js_access("self", class_property.name)
    "pub extern \"js\" fn \{fn_name}(\{getter_params}) -> \{return_type} =\n  #| (self) => \{js_get}"
  }
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
  let params : Array[String] = []
  if !class_property.is_static {
    params.push("self : \{ffi_class_type_name(class_.name)}")
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
  if class_property.is_static {
    Some(
      "pub extern \"js\" fn \{fn_name}(\{setter_params}) -> Unit = \"\{binding_name}\"",
    )
  } else {
    let js_set = ffi_js_access("self", class_property.name)
    Some(
      "pub extern \"js\" fn \{fn_name}(\{setter_params}) -> Unit =\n  #| (self, value) => (\{js_set} = value)",
    )
  }
}

///|
fn ffi_namespace_decl(export_name : String) -> (String, String) {
  let type_name = ffi_to_pascal_case(export_name)
  let ffi_decl = "#external\ntype \{type_name}\n\npub extern \"js\" fn \{ffi_namespace_getter_name(export_name)}() -> \{type_name} = \"__ts_mbt_get_\{ffi_to_snake_case(export_name)}\""
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
fn ffi_bridge_import_key(export_name : String) -> String {
  if export_name == "default" {
    "default:" + export_name
  } else {
    "named:" + export_name
  }
}

///|
fn ffi_bridge_reexport_line(
  module_spec : String,
  export_name : String,
  binding_name : String,
) -> String? {
  if export_name == "default" {
    return Some(
      "export { default as \{binding_name} } from \"\{module_spec}\";",
    )
  }
  if ffi_is_js_ident(export_name) {
    return Some(
      "export { \{export_name} as \{binding_name} } from \"\{module_spec}\";",
    )
  }
  None
}

///|
fn ensure_bridge_import(
  seen_import_keys : Array[String],
  bridge_imports : Array[MoonBitBridgeImport],
  export_name : String,
) -> String {
  let key = ffi_bridge_import_key(export_name)
  let local_name = ffi_bridge_import_local_name(export_name)
  if seen_import_keys.contains(key) {
    return local_name
  }
  seen_import_keys.push(key)
  bridge_imports.push({
    imported_name: export_name,
    local_name,
    is_default: export_name == "default",
  })
  local_name
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
  let named_imports : Array[String] = []
  for import_ in bridge_imports {
    if import_.is_default {
      default_import = Some(import_.local_name)
    } else if import_.imported_name == import_.local_name {
      named_imports.push(import_.imported_name)
    } else {
      named_imports.push("\{import_.imported_name} as \{import_.local_name}")
    }
  }
  if named_imports.is_empty() {
    match default_import {
      Some(default_binding) =>
        Some("import \{default_binding} from \"\{module_spec}\";")
      None => None
    }
  } else {
    named_imports.sort()
    let named_clause = "{ " + named_imports.join(", ") + " }"
    match default_import {
      Some(default_binding) =>
        Some(
          "import \{default_binding}, \{named_clause} from \"\{module_spec}\";",
        )
      None => Some("import \{named_clause} from \"\{module_spec}\";")
    }
  }
}

///|
fn normalize_interfaces_for_ffi(
  exported_interfaces : Array[ExportedInterfaceDecl],
  modules : Map[String, DeclModuleInfo],
  canonical_types : Map[String, String],
) -> Array[@ast.TsInterface] {
  let interfaces : Array[@ast.TsInterface] = []
  for exported in exported_interfaces {
    match modules.get(exported.source_path) {
      Some(info) =>
        interfaces.push(
          clone_exported_interface(exported, info, canonical_types),
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
        imports.push(clone_exported_import(exported, info, canonical_types))
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
        funcs.push(clone_exported_func(exported, info, canonical_types))
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
        values.push(clone_exported_value(exported, info, canonical_types))
      None => ()
    }
  }
  values
}

///|
fn normalize_classes_for_ffi(
  exported_classes : Array[ExportedClassDecl],
  modules : Map[String, DeclModuleInfo],
  canonical_types : Map[String, String],
) -> Array[@ast.TsClassDecl] {
  let classes : Array[@ast.TsClassDecl] = []
  for exported in exported_classes {
    match modules.get(exported.source_path) {
      Some(info) =>
        classes.push(clone_exported_class(exported, info, canonical_types))
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
    exported_imports,
    exported_funcs,
    exported_values,
    exported_classes,
    decl_notes,
  ) = collect_exported_decls(graph, export_surface, modules)
  let canonical_types = build_canonical_type_name_map(
    exported_interfaces, exported_classes,
  )
  let interfaces = normalize_interfaces_for_ffi(
    exported_interfaces, modules, canonical_types,
  )
  let imports = normalize_imports_for_ffi(
    exported_imports, modules, canonical_types,
  )
  let funcs = normalize_funcs_for_ffi(exported_funcs, modules, canonical_types)
  let values = normalize_values_for_ffi(
    exported_values, modules, canonical_types,
  )
  let classes = normalize_classes_for_ffi(
    exported_classes, modules, canonical_types,
  )

  let declared_type_names : Array[String] = []
  for iface in interfaces {
    declared_type_names.push(ffi_to_pascal_case(iface.name))
  }
  for class_ in classes {
    declared_type_names.push(ffi_class_type_name(class_.name))
  }
  let state : MoonBitJsFfiState = {
    declared_type_names,
    external_type_names: [],
    needs_js_any: false,
  }

  let ffi_sections : Array[String] = [
    "// Auto-generated by mizchi/ts/analysis", "// Load the generated bridge JS before calling these externs.",
  ]
  let seen_ffi_binding_names : Array[String] = []
  let bridge_lines : Array[String] = []
  let bridge_imports : Array[MoonBitBridgeImport] = []
  let seen_bridge_import_keys : Array[String] = []
  let seen_bridge_binding_names : Array[String] = []

  for note in decl_notes {
    let text = note.replace(old="///|\n/// ", new="")
    ffi_sections.push("// " + text)
    bridge_lines.push("// " + text)
  }

  let namespace_export_names : Array[String] = []
  let ambiguous_export_names : Array[String] = []
  let handled_export_names : Array[String] = []
  for export_ in export_surface {
    match export_.kind {
      Namespace => namespace_export_names.push(export_.export_name)
      Ambiguous => ambiguous_export_names.push(export_.export_name)
      _ => ()
    }
  }
  namespace_export_names.sort()
  ambiguous_export_names.sort()

  for export_name in ambiguous_export_names {
    let msg = "Unsupported export \{export_name}: ambiguous re-export surface cannot be bound safely."
    ffi_sections.push("// " + msg)
    bridge_lines.push("// " + msg)
  }

  for export_name in namespace_export_names {
    let (type_name, ffi_decl) = ffi_namespace_decl(export_name)
    if !state.declared_type_names.contains(type_name) &&
      !state.external_type_names.contains(type_name) {
      state.external_type_names.push(type_name)
    }
    let getter_binding_name = "__ts_mbt_get_" + ffi_to_snake_case(export_name)
    push_unique_ffi_section(
      seen_ffi_binding_names, ffi_sections, getter_binding_name, ffi_decl,
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

  for iface in interfaces {
    ffi_sections.push(ffi_struct_decl_to_moonbit(state, iface))
    handled_export_names.push(iface.name)
  }

  for class_ in classes {
    ffi_sections.push(ffi_class_type_decl(class_.name))
    let class_ctor_binding = ffi_class_ctor_binding_name(class_.name)
    let class_ctor_section = if ffi_can_use_direct_module(module_spec) {
      ffi_class_constructor_decl_to_moonbit_direct(state, class_, module_spec)
    } else {
      ffi_class_constructor_decl_to_moonbit(state, class_)
    }
    match class_ctor_section {
      Some(decl) =>
        push_unique_ffi_section(
          seen_ffi_binding_names, ffi_sections, class_ctor_binding, decl,
        )
      None => ()
    }
    for class_property in class_.properties {
      let getter_binding = ffi_class_property_getter_binding_name(
        class_.name,
        class_property.name,
      )
      push_unique_ffi_section(
        seen_ffi_binding_names,
        ffi_sections,
        getter_binding,
        ffi_class_property_getter_decl_to_moonbit(state, class_, class_property),
      )
      match
        ffi_class_property_setter_decl_to_moonbit(state, class_, class_property) {
        Some(decl) =>
          push_unique_ffi_section(
            seen_ffi_binding_names,
            ffi_sections,
            ffi_class_property_setter_binding_name(
              class_.name,
              class_property.name,
            ),
            decl,
          )
        None => ()
      }
    }
    for class_method in class_.methods {
      let binding_name = ffi_class_method_binding_name(
        class_.name,
        class_method.name,
      )
      push_unique_ffi_section(
        seen_ffi_binding_names,
        ffi_sections,
        binding_name,
        ffi_class_method_decl_to_moonbit(state, class_, class_method),
      )
    }
    handled_export_names.push(class_.name)
    if !ffi_can_use_direct_module(module_spec) {
      match class_.constructor_params {
        Some(constructor_params) if class_.is_constructible => {
          let args : Array[String] = []
          for param in constructor_params {
            let (param_name, _) = param
            args.push(ffi_sanitize_identifier(param_name, "arg"))
          }
          let params_str = args.join(", ")
          let class_access = ensure_bridge_import(
            seen_bridge_import_keys,
            bridge_imports,
            class_.name,
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
          let class_access = ensure_bridge_import(
            seen_bridge_import_keys,
            bridge_imports,
            class_.name,
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
    }
    for class_property in class_.properties {
      if !class_property.is_static {
        continue
      }
      let getter_binding = ffi_class_property_getter_binding_name(
        class_.name,
        class_property.name,
      )
      let class_access = ensure_bridge_import(
        seen_bridge_import_keys,
        bridge_imports,
        class_.name,
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
      let class_access = ensure_bridge_import(
        seen_bridge_import_keys,
        bridge_imports,
        class_.name,
      )
      let args_str = args.join(", ")
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
    if ffi_can_use_direct_module(module_spec) {
      push_unique_ffi_section(
        seen_ffi_binding_names,
        ffi_sections,
        "direct_import:" + import_.name,
        ffi_import_decl_to_moonbit_direct(state, import_, module_spec),
      )
    } else {
      let binding_name = ffi_binding_name(import_.name)
      push_unique_ffi_section(
        seen_ffi_binding_names,
        ffi_sections,
        binding_name,
        ffi_import_decl_to_moonbit(state, import_),
      )
      match ffi_bridge_reexport_line(module_spec, import_.name, binding_name) {
        Some(reexport_line) =>
          push_unique_bridge_binding(
            seen_bridge_binding_names, bridge_lines, binding_name, reexport_line,
          )
        None =>
          push_unique_bridge_binding(
            seen_bridge_binding_names,
            bridge_lines,
            binding_name,
            "export const \{binding_name} = \{ensure_bridge_import(seen_bridge_import_keys, bridge_imports, import_.name)};",
          )
      }
    }
    handled_export_names.push(import_.name)
  }

  for func in funcs {
    if ffi_can_use_direct_module(module_spec) {
      push_unique_ffi_section(
        seen_ffi_binding_names,
        ffi_sections,
        "direct_func:" + func.name,
        ffi_func_decl_to_moonbit_direct(state, func, module_spec),
      )
    } else {
      let binding_name = ffi_binding_name(func.name)
      push_unique_ffi_section(
        seen_ffi_binding_names,
        ffi_sections,
        binding_name,
        ffi_func_decl_to_moonbit(state, func),
      )
      match ffi_bridge_reexport_line(module_spec, func.name, binding_name) {
        Some(reexport_line) =>
          push_unique_bridge_binding(
            seen_bridge_binding_names, bridge_lines, binding_name, reexport_line,
          )
        None =>
          push_unique_bridge_binding(
            seen_bridge_binding_names,
            bridge_lines,
            binding_name,
            "export const \{binding_name} = \{ensure_bridge_import(seen_bridge_import_keys, bridge_imports, func.name)};",
          )
      }
    }
    handled_export_names.push(func.name)
  }

  for value in values {
    let getter_name = "__ts_mbt_get_" + ffi_to_snake_case(value.name)
    push_unique_ffi_section(
      seen_ffi_binding_names,
      ffi_sections,
      getter_name,
      ffi_value_decl_to_moonbit(state, value),
    )
    push_unique_bridge_binding(
      seen_bridge_binding_names,
      bridge_lines,
      getter_name,
      ffi_bridge_function_line(
        getter_name,
        [],
        ensure_bridge_import(
          seen_bridge_import_keys,
          bridge_imports,
          value.name,
        ),
      ),
    )
    handled_export_names.push(value.name)
  }

  for export_ in export_surface {
    if export_.kind == Namespace || export_.kind == Ambiguous {
      continue
    }
    if handled_export_names.contains(export_.export_name) {
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
      getter_name,
      ffi_value_decl_to_moonbit(state, fallback_value),
    )
    push_unique_bridge_binding(
      seen_bridge_binding_names,
      bridge_lines,
      getter_name,
      ffi_bridge_function_line(
        getter_name,
        [],
        ensure_bridge_import(
          seen_bridge_import_keys,
          bridge_imports,
          export_.export_name,
        ),
      ),
    )
  }

  state.external_type_names.sort()
  for type_name in state.external_type_names {
    if state.declared_type_names.contains(type_name) {
      continue
    }
    ffi_sections.push("#external\ntype \{type_name}")
  }

  if state.needs_js_any {
    ffi_sections.insert(
      2, "// Requires mizchi/js (alias @js) for @js.Any in widened signatures.",
    )
  }

  let rendered_bridge_lines : Array[String] = [
    "// Auto-generated by mizchi/ts/analysis",
  ]
  match render_bridge_import_line(module_spec, bridge_imports) {
    Some(import_line) => {
      rendered_bridge_lines.push(import_line)
      rendered_bridge_lines.push("")
    }
    None => ()
  }
  for line in bridge_lines {
    rendered_bridge_lines.push(line)
  }

  {
    ffi_mbt: ffi_sections.join("\n\n"),
    bridge_js: rendered_bridge_lines.join("\n"),
  }
}
