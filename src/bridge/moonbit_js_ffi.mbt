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
    "and"
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
    | "finally"
    | "fn"
    | "for"
    | "if"
    | "import"
    | "in"
    | "interface"
    | "is"
    | "guard"
    | "lazy"
    | "let"
    | "loop"
    | "match"
    | "method"
    | "module"
    | "namespace"
    | "new"
    | "constructor"
    | "null"
    | "or"
    | "override"
    | "package"
    | "private"
    | "protected"
    | "pub"
    | "public"
    | "raise"
    | "readonly"
    | "ref"
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
    (first.to_int() + 32).unsafe_to_char().to_string() + name[1:].to_string()
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
  name[start:end_].to_string()
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
  let core = sanitized[idx:sanitized.length()].to_string()
  if core == "" {
    return fallback
  }
  let first = core[0].unsafe_to_char()
  let normalized_core = if first >= 'a' && first <= 'z' {
    ffi_to_upper_ascii(first).to_string() + core[1:].to_string()
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
fn ffi_normalize_literal_type(type_ : @ast.TsType) -> @ast.TsType {
  match type_ {
    Literal("true") | Literal("false") => Boolean
    Literal(_) => String_
    _ => type_
  }
}

///|
fn ffi_classify_optional_like_union(
  type_ : @ast.TsType,
) -> (@ast.TsType, Bool)? {
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
            let normalized = ffi_normalize_literal_type(item)
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
fn ffi_is_empty_object_type(type_ : @ast.TsType) -> Bool {
  match type_ {
    Object(fields) => fields.length() == 0
    _ => false
  }
}

///|
fn ffi_classify_transparent_intersection(type_ : @ast.TsType) -> @ast.TsType? {
  match type_ {
    Intersection(items) => {
      let concrete : Array[@ast.TsType] = []
      for item in items {
        if !ffi_is_empty_object_type(item) {
          concrete.push(item)
        }
      }
      if concrete.length() == 1 {
        Some(concrete[0])
      } else {
        None
      }
    }
    _ => None
  }
}

///|
fn ffi_type_name(state : MoonBitJsFfiState, type_ : @ast.TsType) -> String {
  match ffi_classify_optional_like_union(type_) {
    Some((collapsed, is_optional)) => {
      let suffix = if is_optional { "?" } else { "" }
      return ffi_type_name(state, collapsed) + suffix
    }
    None => ()
  }
  match ffi_classify_transparent_intersection(type_) {
    Some(inner) => return ffi_type_name(state, inner)
    None => ()
  }
  match type_ {
    Literal(_) => ffi_type_name(state, ffi_normalize_literal_type(type_))
    Number => "Double"
    Int => "Int"
    Boolean => "Bool"
    String_ => "String"
    Void => "Unit"
    Array(inner) => "Array[" + ffi_type_name(state, inner) + "]"
    Struct(name, _) => ffi_type_identifier(name, "OpaqueType")
    Named("any") | Named("Function") => {
      state.needs_js_any = true
      "@js.Any"
    }
    Named("Array") | Named("ReadonlyArray") => {
      state.needs_js_any = true
      "Array[@js.Any]"
    }
    Applied("Array", [inner]) | Applied("ReadonlyArray", [inner]) =>
      "Array[" + ffi_type_name(state, inner) + "]"
    Named(name) => ffi_mark_external_type(state, name)
    Applied(name, _) => ffi_mark_external_type(state, name)
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
  let type_name = ffi_type_identifier(iface.name, "OpaqueType")
  let lines : Array[String] = ["pub struct \{type_name} {"]
  let seen_fields : Array[String] = []
  for field in iface.fields {
    let (name, type_) = field
    let field_name = ffi_sanitize_identifier(name, "field")
    if seen_fields.contains(field_name) {
      continue
    }
    seen_fields.push(field_name)
    let field_type = ffi_type_name(state, type_)
    lines.push("  \{field_name} : \{field_type}")
  }
  lines.push("}")
  lines.join("\n")
}

///|
fn ffi_named_struct_decl_to_moonbit(
  state : MoonBitJsFfiState,
  name : String,
  fields : Array[(String, @ast.TsType)],
) -> String {
  let type_name = ffi_type_identifier(name, "OpaqueType")
  let lines : Array[String] = ["pub struct \{type_name} {"]
  let seen_fields : Array[String] = []
  for field in fields {
    let (field_name, field_type) = field
    let safe_name = ffi_sanitize_identifier(field_name, "field")
    if seen_fields.contains(safe_name) {
      continue
    }
    seen_fields.push(safe_name)
    let safe_type = ffi_type_name(state, field_type)
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
  "#external\ntype " + ffi_type_identifier(iface.name, "OpaqueType")
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
  ffi_type_identifier(class_name, "OpaqueType")
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
    let instance_params = if method_params == "" {
      "self : \{ffi_class_type_name(class_.name)}"
    } else {
      method_params
    }
    "pub extern \"js\" fn \{ffi_class_type_name(class_.name)}::\{fn_name}(\{instance_params}) -> \{return_type} =\n  #| (\{js_param_list}) => \{js_call}"
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
    "pub extern \"js\" fn \{ffi_class_type_name(class_.name)}::\{fn_name}(\{getter_params}) -> \{return_type} =\n  #| (self) => \{js_get}"
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
      "pub extern \"js\" fn \{ffi_class_type_name(class_.name)}::\{fn_name}(\{setter_params}) -> Unit =\n  #| (self, value) => (\{js_set} = value)",
    )
  }
}

///|
fn ffi_namespace_decl(export_name : String) -> (String, String) {
  let type_name = ffi_type_identifier(export_name, "OpaqueType")
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
    Some(index) => runtime_export_name[:index].to_string()
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
      let suffix = runtime_export_name[index + 1:].to_string()
      for part_view in suffix.split(".") {
        let part = part_view.to_string()
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
fn bridge_namespace_import_roots_for_export_equals(
  export_surface : Array[ResolvedExport],
  modules : Map[String, DeclModuleInfo],
  module_spec : String,
) -> Array[String] {
  let roots : Array[String] = []
  let module_basename = match module_spec.rev_find("/") {
    Some(idx) => module_spec[idx + 1:].to_string()
    None =>
      match module_spec.rev_find(":") {
        Some(idx) => module_spec[idx + 1:].to_string()
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
  let named_imports : Array[String] = []
  let namespace_imports : Array[String] = []
  for import_ in bridge_imports {
    if import_.is_namespace {
      namespace_imports.push(import_.local_name)
    } else if import_.is_default {
      default_import = Some(import_.local_name)
    } else if import_.imported_name == import_.local_name {
      named_imports.push(import_.imported_name)
    } else {
      named_imports.push("\{import_.imported_name} as \{import_.local_name}")
    }
  }
  let lines : Array[String] = []
  namespace_imports.sort()
  for local_name in namespace_imports {
    lines.push("import * as \{local_name} from \"\{module_spec}\";")
  }
  if named_imports.is_empty() {
    match default_import {
      Some(default_binding) =>
        lines.push("import \{default_binding} from \"\{module_spec}\";")
      None => ()
    }
  } else {
    named_imports.sort()
    let named_clause = "{ " + named_imports.join(", ") + " }"
    match default_import {
      Some(default_binding) =>
        lines.push(
          "import \{default_binding}, \{named_clause} from \"\{module_spec}\";",
        )
      None => lines.push("import \{named_clause} from \"\{module_spec}\";")
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
  modules : Map[String, DeclModuleInfo],
  canonical_types : Map[String, String],
) -> Array[@ast.TsClassDecl] {
  let classes : Array[@ast.TsClassDecl] = []
  for exported in exported_classes {
    match modules.get(exported.source_path) {
      Some(info) =>
        classes.push(
          clone_exported_class(exported, info, modules, canonical_types),
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
    exported_imports,
    exported_funcs,
    exported_values,
    exported_classes,
    decl_notes,
  ) = collect_exported_decls(graph, export_surface, modules)
  let canonical_types = build_canonical_type_name_map(
    exported_interfaces, exported_classes,
  )
  let tuple_result_interfaces = normalize_tuple_result_interfaces(
    exported_imports, exported_funcs, modules, canonical_types,
  )
  let react_utility_interfaces = normalize_react_utility_interfaces(
    exported_interfaces, exported_imports, exported_funcs, exported_values, exported_classes,
    modules, canonical_types,
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
  for
    iface in collect_interface_dependencies(
      exported_interfaces, exported_imports, exported_funcs, exported_values, exported_classes,
      modules, canonical_types, interfaces,
    ) {
    interfaces.push(iface)
  }
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
  let import_runtime_export_names : Map[String, String] = {}
  for exported in exported_imports {
    import_runtime_export_names[exported.export_name] = exported.source_export_name
  }
  let func_runtime_export_names : Map[String, String] = {}
  for exported in exported_funcs {
    func_runtime_export_names[exported.export_name] = exported.source_export_name
  }
  let value_runtime_export_names : Map[String, String] = {}
  for exported in exported_values {
    value_runtime_export_names[exported.export_name] = exported.source_export_name
  }
  let class_runtime_export_names : Map[String, String] = {}
  for exported in exported_classes {
    class_runtime_export_names[exported.export_name] = exported.source_export_name
  }
  let namespace_import_roots = bridge_namespace_import_roots_for_export_equals(
    export_surface, modules, module_spec,
  )
  let tuple_result_field_names : Map[String, Array[String]] = {}
  for spec in tuple_result_interfaces {
    let field_names : Array[String] = []
    for field in spec.iface.fields {
      field_names.push(field.0)
    }
    tuple_result_field_names[spec.export_name] = field_names
  }

  let declared_type_names : Array[String] = []
  for iface in interfaces {
    declared_type_names.push(ffi_type_identifier(iface.name, "OpaqueType"))
  }
  for class_ in classes {
    declared_type_names.push(ffi_class_type_name(class_.name))
  }
  let state : MoonBitJsFfiState = {
    declared_type_names,
    external_type_names: [],
    needs_js_any: false,
  }
  let emitted_type_names : Array[String] = []

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

  for iface in interfaces {
    let type_name = ffi_type_identifier(iface.name, "OpaqueType")
    if !emitted_type_names.contains(type_name) {
      emitted_type_names.push(type_name)
      if ffi_is_react_callable_component_interface(iface.name) {
        ffi_sections.push(ffi_interface_type_decl_to_moonbit(iface))
      } else {
        ffi_sections.push(ffi_struct_decl_to_moonbit(state, iface))
      }
    }
    handled_export_names.push(iface.name)
  }

  for class_ in classes {
    let class_type_name = ffi_class_type_name(class_.name)
    if !emitted_type_names.contains(class_type_name) {
      emitted_type_names.push(class_type_name)
      ffi_sections.push(ffi_class_type_decl(class_.name))
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
        let params_str = args.join(", ")
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
    let runtime_export_name = runtime_export_name_for(
      import_runtime_export_names,
      import_.name,
    )
    match tuple_result_field_names.get(import_.name) {
      Some(field_names) => {
        let binding_name = ffi_binding_name(import_.name)
        let args = ffi_import_param_names(import_)
        let args_str = args.join(", ")
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
        if ffi_can_use_direct_module(module_spec) &&
          !ffi_runtime_export_requires_bridge(runtime_export_name) {
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
              push_unique_bridge_binding(
                seen_bridge_binding_names, bridge_lines, binding_name, reexport_line,
              )
            None =>
              push_unique_bridge_binding(
                seen_bridge_binding_names,
                bridge_lines,
                binding_name,
                "export const \{binding_name} = \{ensure_bridge_runtime_access(seen_bridge_import_keys, bridge_imports, namespace_import_roots, runtime_export_name)};",
              )
          }
        }
    }
    handled_export_names.push(import_.name)
  }

  for func in funcs {
    let runtime_export_name = runtime_export_name_for(
      func_runtime_export_names,
      func.name,
    )
    match tuple_result_field_names.get(func.name) {
      Some(field_names) => {
        let binding_name = ffi_binding_name(func.name)
        let args = ffi_func_param_names(func)
        let args_str = args.join(", ")
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
        if ffi_can_use_direct_module(module_spec) &&
          !ffi_runtime_export_requires_bridge(runtime_export_name) {
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
              push_unique_bridge_binding(
                seen_bridge_binding_names, bridge_lines, binding_name, reexport_line,
              )
            None =>
              push_unique_bridge_binding(
                seen_bridge_binding_names,
                bridge_lines,
                binding_name,
                "export const \{binding_name} = \{ensure_bridge_runtime_access(seen_bridge_import_keys, bridge_imports, namespace_import_roots, runtime_export_name)};",
              )
          }
        }
    }
    handled_export_names.push(func.name)
  }

  for value in values {
    match value.type_ {
      Struct(name, fields) => {
        let type_name = ffi_type_identifier(name, "OpaqueType")
        if !state.declared_type_names.contains(type_name) {
          state.declared_type_names.push(type_name)
        }
        push_unique_ffi_section(
          seen_ffi_binding_names,
          ffi_sections,
          "struct:" + type_name,
          ffi_named_struct_decl_to_moonbit(state, name, fields),
        )
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
        ensure_bridge_runtime_access(
          seen_bridge_import_keys, bridge_imports, namespace_import_roots, runtime_export_name,
        ),
      ),
    )
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
