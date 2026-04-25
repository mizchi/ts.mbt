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
            for item_view in params_src.split(",") {
              let item = item_view.to_string().trim().to_string()
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
  let internal_name = bridge_to_snake_case(fn_decl.public_name)
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
fn add_bridge_public_wrappers(
  bridge_mbti : String,
  bridge_mbt : String,
) -> String {
  let mut next_bridge_mbt = bridge_mbt
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
  if wrappers.length() == 0 {
    next_bridge_mbt
  } else {
    next_bridge_mbt + "\n\n" + wrappers.join("\n\n")
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
  let bridge_mbti = add_bridge_namespace_public_decls(
    bundle.decl_mbt,
    export_surface,
  )
  {
    entry_path: bundle.entry_path,
    module_spec: bundle.module_spec,
    moon_pkg_json: render_bridge_pkg_json(bridge_bundle_needs_js_import(bundle)),
    bridge_mbti,
    bridge_mbt: add_bridge_public_wrappers(bridge_mbti, bundle.ffi_mbt),
    bridge_js: bundle.bridge_js,
  }
}
