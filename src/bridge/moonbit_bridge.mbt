///|
pub struct MoonBitTsBridgeBundle {
  entry_path : String
  module_spec : String
  decl_mbt : String
  ffi_mbt : String
  bridge_js : String
} derive(Debug)

///|
pub struct MoonBitTsBridgePackageBundle {
  entry_path : String
  module_spec : String
  moon_pkg_json : String
  bridge_mbti : String
  bridge_mbt : String
  bridge_js : String
} derive(Debug)

///|
priv struct BridgeTopLevelFnDecl {
  public_name : String
  params_src : String
  arg_names : Array[String]
  return_type : String
}

///|
priv struct BridgeTypeGuardHelper {
  source_type : String
  target_type : String
  guard_name : String
  helper_name : String
}

///|
fn render_bridge_pkg_json(needs_js_import : Bool) -> String {
  if needs_js_import {
    let content =
      #|{
      #|  "import": [
      #|    { "path": "mizchi/js/core", "alias": "js" }
      #|  ]
      #|}
    content
  } else {
    "{}"
  }
}

///|
fn bridge_bundle_needs_js_import(bundle : MoonBitTsBridgeBundle) -> Bool {
  bundle.ffi_mbt.contains("@js.")
}

///|
fn bridge_is_ascii_letter(c : Char) -> Bool {
  (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
}

///|
fn bridge_is_ascii_digit(c : Char) -> Bool {
  c >= '0' && c <= '9'
}

///|
fn bridge_to_lower_ascii(c : Char) -> Char {
  if c >= 'A' && c <= 'Z' {
    (c.to_int() + 32).unsafe_to_char()
  } else {
    c
  }
}

///|
fn bridge_trim_underscores(name : String) -> String {
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
fn bridge_to_snake_case(name : String) -> String {
  let mut result = ""
  let mut prev_is_lower_or_digit = false
  for c in name {
    if c >= 'A' && c <= 'Z' {
      if result != "" && prev_is_lower_or_digit {
        result += "_"
      }
      result += bridge_to_lower_ascii(c).to_string()
      prev_is_lower_or_digit = false
    } else if bridge_is_ascii_letter(c) || bridge_is_ascii_digit(c) {
      result += c.to_string()
      prev_is_lower_or_digit = (c >= 'a' && c <= 'z') ||
        bridge_is_ascii_digit(c)
    } else {
      if result != "" && !result.has_suffix("_") {
        result += "_"
      }
      prev_is_lower_or_digit = false
    }
  }
  bridge_trim_underscores(result)
}

///|
fn bridge_value_identifier_needs_suffix(name : String) -> Bool {
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
    | "include"
    | "import"
    | "in"
    | "interface"
    | "is"
    | "guard"
    | "lazy"
    | "let"
    | "loop"
    | "match"
    | "module"
    | "namespace"
    | "new"
    | "null"
    | "or"
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
fn bridge_value_fn_name(name : String) -> String {
  let mut result = bridge_to_snake_case(name)
  if bridge_value_identifier_needs_suffix(result) {
    result += "_"
  }
  result
}

///|
fn bridge_split_top_level_commas(source : String) -> Array[String] {
  let parts : Array[String] = []
  let mut current = ""
  let mut paren_depth = 0
  let mut bracket_depth = 0
  let mut brace_depth = 0
  for c in source {
    if c == ',' && paren_depth == 0 && bracket_depth == 0 && brace_depth == 0 {
      parts.push(current.trim().to_string())
      current = ""
      continue
    }
    current += c.to_string()
    if c == '(' {
      paren_depth += 1
    } else if c == ')' {
      if paren_depth > 0 {
        paren_depth -= 1
      }
    } else if c == '[' {
      bracket_depth += 1
    } else if c == ']' {
      if bracket_depth > 0 {
        bracket_depth -= 1
      }
    } else if c == '{' {
      brace_depth += 1
    } else if c == '}' {
      if brace_depth > 0 {
        brace_depth -= 1
      }
    }
  }
  let tail = current.trim().to_string()
  if tail != "" || source.trim() != "" {
    parts.push(tail)
  }
  parts
}

///|
fn bridge_to_upper_ascii(c : Char) -> Char {
  if c >= 'a' && c <= 'z' {
    (c.to_int() - 32).unsafe_to_char()
  } else {
    c
  }
}

///|
fn bridge_to_pascal_case(name : String) -> String {
  let snake = bridge_to_snake_case(name)
  let mut result = ""
  for part_view in snake.split("_") {
    let part = part_view.to_string()
    if part == "" {
      continue
    }
    let head = bridge_to_upper_ascii(part[0].unsafe_to_char()).to_string()
    result += head + part[1:].to_string()
  }
  result
}

///|
fn parse_bridge_top_level_fn_decl_line(line : String) -> BridgeTopLevelFnDecl? {
  let prefix = "declare pub fn "
  if !line.has_prefix(prefix) {
    return None
  }
  let rest = line[prefix.length():].to_string()
  let open = rest.find("(")
  let close = rest.rev_find(")")
  match open {
    Some(open_index) =>
      match close {
        Some(close_index) => {
          if close_index < open_index {
            return None
          }
          let public_name = rest[:open_index].to_string().trim().to_string()
          if public_name.contains("::") {
            return None
          }
          let params_src = rest[open_index + 1:close_index].to_string()
          let after = rest[close_index + 1:].to_string().trim().to_string()
          if !after.has_prefix("->") {
            return None
          }
          let return_type = after[2:].to_string().trim().to_string()
          let arg_names : Array[String] = []
          if params_src.trim() != "" {
            for item in bridge_split_top_level_commas(params_src) {
              if item == "" {
                continue
              }
              match item.find(":") {
                Some(index) =>
                  arg_names.push(item[:index].to_string().trim().to_string())
                None => arg_names.push(item)
              }
            }
          }
          Some({ public_name, params_src, arg_names, return_type })
        }
        None => None
      }
    None => None
  }
}

///|
fn parse_bridge_public_type_name_line(line : String) -> String? {
  let prefix = "declare pub type "
  if !line.has_prefix(prefix) {
    return None
  }
  let rest = line[prefix.length():].to_string().trim().to_string()
  if rest == "" {
    return None
  }
  let mut end_ = rest.length()
  match rest.find("[") {
    Some(idx) => end_ = idx
    None => ()
  }
  match rest.find(" ") {
    Some(idx) => if idx < end_ { end_ = idx }
    None => ()
  }
  let type_name = rest[:end_].to_string().trim().to_string()
  if type_name == "" {
    None
  } else {
    Some(type_name)
  }
}

///|
fn collect_bridge_public_type_names(bridge_mbti : String) -> Array[String] {
  let names : Array[String] = []
  for line_view in bridge_mbti.split("\n") {
    let line = line_view.to_string().trim().to_string()
    match parse_bridge_public_type_name_line(line) {
      Some(name) => if !names.contains(name) { names.push(name) }
      None => ()
    }
  }
  names
}

///|
fn parse_bridge_first_param_type(params_src : String) -> String? {
  if params_src.trim() == "" {
    return None
  }
  let first_param_src = match params_src.find(",") {
    Some(index) => params_src[:index].to_string()
    None => params_src
  }
  let first_param = first_param_src.trim().to_string()
  match first_param.find(":") {
    Some(index) => {
      let type_src = first_param[index + 1:].to_string().trim().to_string()
      if type_src == "" {
        return None
      }
      let normalized = if type_src.has_suffix("?") {
        type_src[:type_src.length() - 1].to_string()
      } else {
        type_src
      }
      Some(normalized.trim().to_string())
    }
    None => None
  }
}

///|
fn bridge_type_guard_target_name(
  public_name : String,
  type_names : Array[String],
) -> String? {
  if !public_name.has_prefix("is") || public_name.length() <= 2 {
    return None
  }
  let target_name = public_name[2:].to_string()
  if type_names.contains(target_name) {
    Some(target_name)
  } else {
    None
  }
}

///|
fn collect_bridge_type_guard_helpers(
  bridge_mbti : String,
) -> Array[BridgeTypeGuardHelper] {
  let type_names = collect_bridge_public_type_names(bridge_mbti)
  let helpers : Array[BridgeTypeGuardHelper] = []
  let seen_helpers : Array[String] = []
  for line_view in bridge_mbti.split("\n") {
    let line = line_view.to_string().trim().to_string()
    match parse_bridge_top_level_fn_decl_line(line) {
      Some(fn_decl) => {
        if fn_decl.return_type != "Bool" {
          continue
        }
        if fn_decl.arg_names.length() != 1 {
          continue
        }
        let source_type = match
          parse_bridge_first_param_type(fn_decl.params_src) {
          Some(source_type) => source_type
          None => continue
        }
        // The current parser lowers TS type predicates to Bool. Restricting
        // helpers to Node-based guards keeps the generated casts aligned with
        // the common TypeScript AST narrowing pattern and avoids broad false
        // positives such as arbitrary boolean predicates.
        if source_type != "Node" {
          continue
        }
        let target_type = match
          bridge_type_guard_target_name(fn_decl.public_name, type_names) {
          Some(target_type) => target_type
          None => continue
        }
        if target_type == source_type {
          continue
        }
        let helper_name = "as" + target_type
        let helper_key = source_type + "::" + helper_name
        if seen_helpers.contains(helper_key) {
          continue
        }
        seen_helpers.push(helper_key)
        helpers.push({
          source_type,
          target_type,
          guard_name: fn_decl.public_name,
          helper_name,
        })
      }
      None => ()
    }
  }
  helpers
}

///|
fn add_bridge_ergonomic_helper_decls(bridge_mbti : String) -> String {
  let mut next_bridge_mbti = bridge_mbti
  let unsafe_cast_decl = "declare pub fn[A, B] unsafeCast(value : A) -> B"
  if !next_bridge_mbti.contains(unsafe_cast_decl) {
    next_bridge_mbti += "\n\n///|\n" + unsafe_cast_decl
  }
  for helper in collect_bridge_type_guard_helpers(bridge_mbti) {
    let helper_decl = "declare pub fn \{helper.helper_name}(self : \{helper.source_type}) -> \{helper.target_type}?"
    if !next_bridge_mbti.contains(helper_decl) {
      next_bridge_mbti += "\n\n///|\n" + helper_decl
    }
  }
  next_bridge_mbti
}

///|
fn add_bridge_namespace_public_decls(
  bridge_mbti : String,
  export_surface : Array[ResolvedExport],
) -> String {
  let mut next_bridge_mbti = bridge_mbti
  for export_ in export_surface {
    if export_.kind != Namespace {
      continue
    }
    let export_name = export_.export_name
    let unsupported_note = "///|\n/// Unsupported export \{export_name}: namespace export is widened to JSValue."
    if !next_bridge_mbti.contains(unsupported_note) {
      continue
    }
    if next_bridge_mbti.contains(unsupported_note) {
      next_bridge_mbti = next_bridge_mbti.replace(
        old=unsupported_note,
        new="///|\n/// Namespace export \{export_name} is exposed as an opaque getter.",
      )
    }
    let type_name = bridge_to_pascal_case(export_name)
    let getter_name = "get_" + bridge_to_snake_case(export_name)
    let type_decl = "declare pub type \{type_name}"
    if !next_bridge_mbti.contains(type_decl) {
      next_bridge_mbti += "\n\n///|\n" + type_decl
    }
    let getter_decl = "declare pub fn \{getter_name}() -> \{type_name}"
    if !next_bridge_mbti.contains(getter_decl) {
      next_bridge_mbti += "\n\n///|\n" + getter_decl
    }
  }
  next_bridge_mbti
}

///|
fn render_bridge_public_wrapper(fn_decl : BridgeTopLevelFnDecl) -> String? {
  if bridge_value_identifier_needs_suffix(fn_decl.public_name) {
    return None
  }
  let internal_name = bridge_value_fn_name(fn_decl.public_name)
  if internal_name == "" || internal_name == fn_decl.public_name {
    return None
  }
  let call_args = fn_decl.arg_names.join(", ")
  let call_expr = if call_args == "" {
    internal_name + "()"
  } else {
    internal_name + "(" + call_args + ")"
  }
  Some(
    "pub fn \{fn_decl.public_name}(\{fn_decl.params_src}) -> \{fn_decl.return_type} {\n  \{call_expr}\n}",
  )
}

///|
fn inject_bridge_public_type_aliases(
  bridge_mbti : String,
  bridge_mbt : String,
) -> String {
  let mut next_bridge_mbt = bridge_mbt
  if bridge_mbti.contains("declare pub type JSValue") &&
    !next_bridge_mbt.contains("pub type JSValue = @js.Any") {
    next_bridge_mbt = "pub type JSValue = @js.Any\n\n" + next_bridge_mbt
  }
  next_bridge_mbt
}

///|
fn add_bridge_public_wrappers(
  bridge_mbti : String,
  bridge_mbt : String,
) -> String {
  let mut next_bridge_mbt = inject_bridge_public_type_aliases(
    bridge_mbti, bridge_mbt,
  )
  let wrappers : Array[String] = []
  for line_view in bridge_mbti.split("\n") {
    let line = line_view.to_string().trim().to_string()
    match parse_bridge_top_level_fn_decl_line(line) {
      Some(fn_decl) =>
        match render_bridge_public_wrapper(fn_decl) {
          Some(wrapper) => {
            let internal_name = bridge_to_snake_case(fn_decl.public_name)
            let raw_decl = "pub extern \"js\" fn \{internal_name}("
            if next_bridge_mbt.contains(raw_decl) {
              next_bridge_mbt = next_bridge_mbt.replace(
                old=raw_decl,
                new="extern \"js\" fn \{internal_name}(",
              )
              wrappers.push(wrapper)
            }
          }
          None => ()
        }
      None => ()
    }
  }
  let helpers : Array[String] = [
    "pub fn[A, B] unsafeCast(value : A) -> B = \"%identity\"",
  ]
  for helper in collect_bridge_type_guard_helpers(bridge_mbti) {
    helpers.push(
      "pub fn \{helper.source_type}::\{helper.helper_name}(self : \{helper.source_type}) -> \{helper.target_type}? {\n  if \{helper.guard_name}(self) {\n    Some(unsafeCast(self))\n  } else {\n    None\n  }\n}",
    )
  }
  let sections : Array[String] = []
  for wrapper in wrappers {
    sections.push(wrapper)
  }
  for helper in helpers {
    if !next_bridge_mbt.contains(helper) {
      sections.push(helper)
    }
  }
  if sections.length() == 0 {
    next_bridge_mbt
  } else {
    next_bridge_mbt + "\n\n" + sections.join("\n\n")
  }
}

///|
pub async fn emit_moonbit_ts_bridge_bundle_from_entry_path(
  entry_path : String,
  module_spec : String,
) -> MoonBitTsBridgeBundle raise ModuleGraphError {
  let decl_mbt = emit_moonbit_decl_from_entry_path(entry_path)
  let ffi_bundle = emit_moonbit_js_ffi_bundle_from_entry_path(
    entry_path, module_spec,
  )
  {
    entry_path,
    module_spec,
    decl_mbt,
    ffi_mbt: ffi_bundle.ffi_mbt,
    bridge_js: ffi_bundle.bridge_js,
  }
}

///|
pub async fn emit_moonbit_ts_bridge_package_bundle_from_entry_path(
  entry_path : String,
  module_spec : String,
) -> MoonBitTsBridgePackageBundle raise ModuleGraphError {
  let bundle = emit_moonbit_ts_bridge_bundle_from_entry_path(
    entry_path, module_spec,
  )
  let graph = load_type_module_graph(entry_path)
  let export_surface = resolve_export_surface(graph)
  let bridge_mbti = add_bridge_ergonomic_helper_decls(
    add_bridge_namespace_public_decls(bundle.decl_mbt, export_surface),
  )
  let bridge_mbt = add_bridge_public_wrappers(bridge_mbti, bundle.ffi_mbt)
  {
    entry_path: bundle.entry_path,
    module_spec: bundle.module_spec,
    moon_pkg_json: render_bridge_pkg_json(
      bridge_bundle_needs_js_import(bundle) || bridge_mbt.contains("@js."),
    ),
    bridge_mbti,
    bridge_mbt,
    bridge_js: bundle.bridge_js,
  }
}
