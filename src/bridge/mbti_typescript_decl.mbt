///|
pub suberror MbtiTypescriptDeclError {
  ReadError(String)
  ParseError(String)
} derive(@debug.Debug)

///|
pub struct MbtiTypescriptPackageFile {
  relative_path : String
  content : String
}

///|
pub struct MbtiTypescriptScaffoldBundle {
  moon_pkg_json : String
  package_json : String
  autolink_diagnostics_md : String
  autolink_glue_mbt : String
  files : Array[MbtiTypescriptPackageFile]
}

///|
pub fn parse_typescript_import_rewrite_map_source(
  source : String,
) -> Map[String, String]? {
  let json = @json.parse(source) catch { _ => return None }
  guard json is Object(members) else { return None }
  let rewrites : Map[String, String] = {}
  for pair in members {
    let (module_spec, value) = pair
    guard value is String(rewritten_spec) else { return None }
    if module_spec == "" || rewritten_spec == "" {
      return None
    }
    rewrites[module_spec] = rewritten_spec
  }
  Some(rewrites)
}

///|
priv struct MbtiImportRef {
  alias_name : String
  ts_alias : String
  module_spec : String
}

///|
priv struct ParsedMbtiImportLine {
  alias_name : String
  module_spec : String
}

///|
priv struct MbtiParam {
  name : String
  ty : String
  optional : Bool
}

///|
priv struct MbtiTypeParam {
  name : String
  extends_ty : String?
}

///|
priv struct MbtiStructDecl {
  name : String
  type_params : Array[MbtiTypeParam]
  fields : Array[String]
}

///|
priv struct MbtiEnumLikeDecl {
  name : String
  type_params : Array[MbtiTypeParam]
  union_body : String
}

///|
priv struct MbtiTypeAliasDecl {
  name : String
  type_params : Array[MbtiTypeParam]
  body : String
  is_opaque : Bool
}

///|
priv struct MbtiTraitDecl {
  name : String
  type_params : Array[MbtiTypeParam]
  methods : Array[String]
}

///|
priv struct LoadedMbtiPackageSources {
  root_package_name : String
  ordered_packages : Array[String]
  package_sources : Map[String, String]
}

///|
priv struct MbtiImplDecl {
  trait_name : String
  owner_name : String
}

///|
priv struct MbtiFunctionDecl {
  owner_name : String?
  fn_name : String
  type_params : Array[MbtiTypeParam]
  params_src : String
  return_src : String
  return_src_with_effect : String
  is_async : Bool
}

///|
priv struct MbtiMarkerTraitDecl {
  name : String
  arity : Int
}

///|
priv struct MbtiAutolinkGlueDecl {
  package_name : String
  export_name : String
  runtime_export_name : String
  ts_decl : String
  mbt_decl : String
}

///|
priv struct MbtiRawFacadeParam {
  name : String
  ty_src : String
  optional : Bool
}

///|
fn mbti_char_at(s : String, idx : Int) -> Char {
  s[idx].to_int().unsafe_to_char()
}

///|
fn mbti_is_ascii_letter(c : Char) -> Bool {
  (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
}

///|
fn mbti_is_ascii_digit(c : Char) -> Bool {
  c >= '0' && c <= '9'
}

///|
fn mbti_to_lower_ascii(c : Char) -> Char {
  if c >= 'A' && c <= 'Z' {
    (c.to_int() + 32).unsafe_to_char()
  } else {
    c
  }
}

///|
fn mbti_trim_underscores(name : String) -> String {
  let mut start = 0
  let mut end_ = name.length()
  while start < end_ && mbti_char_at(name, start) == '_' {
    start += 1
  }
  while end_ > start && mbti_char_at(name, end_ - 1) == '_' {
    end_ -= 1
  }
  name[start:end_].to_string()
}

///|
fn mbti_to_snake_case(name : String) -> String {
  let mut result = ""
  let mut prev_is_lower_or_digit = false
  for c in name {
    if c >= 'A' && c <= 'Z' {
      if result != "" && prev_is_lower_or_digit {
        result += "_"
      }
      result += mbti_to_lower_ascii(c).to_string()
      prev_is_lower_or_digit = false
    } else if mbti_is_ascii_letter(c) || mbti_is_ascii_digit(c) {
      result += c.to_string()
      prev_is_lower_or_digit = (c >= 'a' && c <= 'z') || mbti_is_ascii_digit(c)
    } else {
      if result != "" && !result.has_suffix("_") {
        result += "_"
      }
      prev_is_lower_or_digit = false
    }
  }
  let trimmed = mbti_trim_underscores(result)
  if trimmed == "" {
    "facade"
  } else {
    trimmed
  }
}

///|
fn mbti_ascii_lower_char(c : Char) -> Char {
  if c >= 'A' && c <= 'Z' {
    (c.to_int() + 32).unsafe_to_char()
  } else {
    c
  }
}

///|
fn mbti_is_generated_param_name(name : String) -> Bool {
  if !name.has_prefix("arg") || name.length() <= 3 {
    return false
  }
  for c in name[3:name.length()] {
    if !mbti_is_ascii_digit(c) {
      return false
    }
  }
  true
}

///|
fn mbti_count_char(source : String, target : Char) -> Int {
  let mut count = 0
  for c in source {
    if c == target {
      count += 1
    }
  }
  count
}

///|
fn mbti_push_unique_string(items : Array[String], value : String) -> Unit {
  if !items.contains(value) {
    items.push(value)
  }
}

///|
fn upsert_marker_trait_decl(
  decls : Map[String, MbtiMarkerTraitDecl],
  order : Array[String],
  name : String,
  arity : Int,
) -> Unit {
  match decls.get(name) {
    Some(existing) =>
      if arity > existing.arity {
        decls[name] = { name, arity }
      }
    None => {
      decls[name] = { name, arity }
      order.push(name)
    }
  }
}

///|
fn sanitize_ts_identifier(name : String, fallback : String) -> String {
  let mut result = ""
  for c in name {
    if mbti_is_ascii_letter(c) || mbti_is_ascii_digit(c) || c == '_' || c == '$' {
      result += c.to_string()
    } else {
      result += "_"
    }
  }
  if result == "" {
    result = fallback
  }
  let first = result[0].unsafe_to_char()
  if mbti_is_ascii_digit(first) {
    result = "_" + result
  }
  match result {
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
    | "enum"
    | "export"
    | "extends"
    | "false"
    | "finally"
    | "for"
    | "function"
    | "if"
    | "import"
    | "in"
    | "instanceof"
    | "new"
    | "null"
    | "return"
    | "super"
    | "switch"
    | "this"
    | "throw"
    | "true"
    | "try"
    | "typeof"
    | "undefined"
    | "var"
    | "void"
    | "while"
    | "with"
    | "yield" => result + "_"
    _ => result
  }
}

///|
fn trim_trailing_comma_or_semicolon(source : String) -> String {
  let mut result = source.trim().to_string()
  while result.has_suffix(",") || result.has_suffix(";") {
    result = result[:result.length() - 1].trim().to_string()
  }
  result
}

///|
fn strip_mbti_derive_suffix(source : String) -> String {
  match source.find(" derive(") {
    Some(derive_idx) => source[:derive_idx].trim().to_string()
    None => source.trim().to_string()
  }
}

///|
fn infer_mbti_import_alias_name(module_spec : String) -> String {
  let mut alias_name = ""
  for part in module_spec.split("/") {
    alias_name = part.to_string()
  }
  alias_name
}

///|
fn parse_mbti_import_line(line : String) -> ParsedMbtiImportLine? {
  if line.length() < 2 || !line.has_prefix("\"") {
    return None
  }
  match line[1:line.length()].find("\"") {
    Some(relative_end) => {
      let closing_idx = relative_end + 1
      let module_spec = line[1:closing_idx].to_string()
      if module_spec == "" {
        return None
      }
      let rest = if closing_idx + 1 < line.length() {
        line[closing_idx + 1:line.length()].trim().to_string()
      } else {
        ""
      }
      let alias_name = if rest.has_prefix("@") {
        let explicit_alias = rest[1:rest.length()].trim().to_string()
        if explicit_alias != "" {
          explicit_alias
        } else {
          infer_mbti_import_alias_name(module_spec)
        }
      } else {
        infer_mbti_import_alias_name(module_spec)
      }
      if alias_name == "" {
        None
      } else {
        Some({ alias_name, module_spec })
      }
    }
    None => None
  }
}

///|
fn mbti_public_prefixes(keyword : String) -> Array[String] {
  ["pub \{keyword} ", "pub(all) \{keyword} ", "pub(open) \{keyword} "]
}

///|
fn mbti_public_generic_prefixes(keyword : String) -> Array[String] {
  ["pub \{keyword}", "pub(all) \{keyword}", "pub(open) \{keyword}"]
}

///|
fn strip_mbti_public_prefix(line : String, keyword : String) -> String? {
  let trimmed = line.trim().to_string()
  for prefix in mbti_public_prefixes(keyword) {
    if trimmed.has_prefix(prefix) {
      return Some(trimmed[prefix.length():trimmed.length()].to_string())
    }
  }
  for prefix in mbti_public_generic_prefixes(keyword) {
    if trimmed.has_prefix(prefix + "[") {
      return Some(trimmed[prefix.length():trimmed.length()].to_string())
    }
  }
  None
}

///|
fn strip_mbti_impl_prefix(line : String) -> String? {
  let trimmed = line.trim().to_string()
  if !trimmed.has_prefix("pub impl") {
    return None
  }
  let mut idx = "pub impl".length()
  if idx < trimmed.length() && mbti_char_at(trimmed, idx) == '[' {
    match find_matching(trimmed, idx, '[', ']') {
      Some(end_idx) => idx = end_idx + 1
      None => return None
    }
  }
  while idx < trimmed.length() && mbti_char_at(trimmed, idx) == ' ' {
    idx += 1
  }
  Some(trimmed[idx:trimmed.length()].to_string())
}

///|
fn split_top_level_items(source : String) -> Array[String] {
  let parts : Array[String] = []
  let mut start = 0
  let mut paren = 0
  let mut bracket = 0
  let mut brace = 0
  let mut angle = 0
  for i = 0; i < source.length(); i = i + 1 {
    let c = mbti_char_at(source, i)
    match c {
      '(' => paren += 1
      ')' => paren -= 1
      '[' => bracket += 1
      ']' => bracket -= 1
      '{' => brace += 1
      '}' => brace -= 1
      '<' => angle += 1
      '>' =>
        if i == 0 ||
          (
            mbti_char_at(source, i - 1) != '=' &&
            mbti_char_at(source, i - 1) != '-'
          ) {
          angle -= 1
        }
      ',' if paren == 0 && bracket == 0 && brace == 0 && angle == 0 => {
        parts.push(source[start:i].trim().to_string())
        start = i + 1
      }
      _ => ()
    }
  }
  let tail = source[start:source.length()].trim().to_string()
  if tail != "" {
    parts.push(tail)
  }
  parts
}

///|
fn split_top_level_plus_items(source : String) -> Array[String] {
  let parts : Array[String] = []
  let mut start = 0
  let mut paren = 0
  let mut bracket = 0
  let mut brace = 0
  for i = 0; i < source.length(); i = i + 1 {
    let c = mbti_char_at(source, i)
    match c {
      '(' => paren += 1
      ')' => paren -= 1
      '[' => bracket += 1
      ']' => bracket -= 1
      '{' => brace += 1
      '}' => brace -= 1
      '+' if paren == 0 && bracket == 0 && brace == 0 => {
        parts.push(source[start:i].trim().to_string())
        start = i + 1
      }
      _ => ()
    }
  }
  let tail = source[start:source.length()].trim().to_string()
  if tail != "" {
    parts.push(tail)
  }
  parts
}

///|
fn find_matching(
  source : String,
  start : Int,
  open_char : Char,
  close_char : Char,
) -> Int? {
  let mut depth = 0
  for i = start; i < source.length(); i = i + 1 {
    let c = mbti_char_at(source, i)
    if c == open_char {
      depth += 1
    } else if c == close_char {
      depth -= 1
      if depth == 0 {
        return Some(i)
      }
    }
  }
  None
}

///|
fn find_top_level_tuple_payload_open(source : String) -> Int? {
  let mut bracket = 0
  for i = 0; i < source.length(); i = i + 1 {
    let c = mbti_char_at(source, i)
    match c {
      '[' => bracket += 1
      ']' => bracket -= 1
      '(' if bracket == 0 => return Some(i)
      _ => ()
    }
  }
  None
}

///|
fn find_top_level_arrow(source : String) -> Int? {
  let mut paren = 0
  let mut bracket = 0
  let mut brace = 0
  for i = 0; i + 1 < source.length(); i = i + 1 {
    let c = mbti_char_at(source, i)
    match c {
      '(' => paren += 1
      ')' => paren -= 1
      '[' => bracket += 1
      ']' => bracket -= 1
      '{' => brace += 1
      '}' => brace -= 1
      '-' if paren == 0 &&
        bracket == 0 &&
        brace == 0 &&
        mbti_char_at(source, i + 1) == '>' => return Some(i)
      _ => ()
    }
  }
  None
}

///|
fn is_mbti_effect_marker_at(
  source : String,
  space_idx : Int,
  keyword : String,
) -> Bool {
  let keyword_start = space_idx + 1
  let keyword_end = keyword_start + keyword.length()
  if keyword_end > source.length() {
    return false
  }
  if source[keyword_start:keyword_end].to_string() != keyword {
    return false
  }
  if keyword_end >= source.length() {
    return true
  }
  let next = mbti_char_at(source, keyword_end)
  next == ' ' || next == '?'
}

///|
fn find_top_level_effect_marker(source : String) -> Int? {
  let mut paren = 0
  let mut bracket = 0
  let mut brace = 0
  for i = 0; i < source.length(); i = i + 1 {
    let c = mbti_char_at(source, i)
    match c {
      '(' => paren += 1
      ')' => paren -= 1
      '[' => bracket += 1
      ']' => bracket -= 1
      '{' => brace += 1
      '}' => brace -= 1
      ' ' if paren == 0 && bracket == 0 && brace == 0 =>
        if is_mbti_effect_marker_at(source, i, "raise") ||
          is_mbti_effect_marker_at(source, i, "noraise") {
          return Some(i)
        }
      _ => ()
    }
  }
  None
}

///|
fn strip_mbti_top_level_effect(source : String) -> String {
  let trimmed = source.trim().to_string()
  match find_top_level_effect_marker(trimmed) {
    Some(effect_idx) => trimmed[:effect_idx].trim().to_string()
    None => trimmed
  }
}

///|
fn mbti_top_level_effect_suffix(source : String) -> String {
  let trimmed = source.trim().to_string()
  match find_top_level_effect_marker(trimmed) {
    Some(effect_idx) => trimmed[effect_idx:trimmed.length()].trim().to_string()
    None => ""
  }
}

///|
fn mbti_return_source_with_effect_from_function_line(line : String) -> String {
  let trimmed = line.trim().to_string()
  match trimmed.find("(") {
    Some(open_idx) =>
      match find_matching(trimmed, open_idx, '(', ')') {
        Some(close_idx) => {
          let rest = trimmed[close_idx + 1:trimmed.length()].trim().to_string()
          if rest.has_prefix("->") {
            rest[2:rest.length()].trim().to_string()
          } else {
            ""
          }
        }
        None => ""
      }
    None => ""
  }
}

///|
fn mbti_qualified_effect_suffix_for_glue(
  return_source : String,
  local_type_names : Array[String],
  type_param_names : Array[String],
  source_alias : String,
) -> String {
  let raw_suffix = mbti_top_level_effect_suffix(return_source)
  if raw_suffix == "" || raw_suffix.has_prefix("noraise") {
    return ""
  }
  let qualified = mbti_qualify_root_type_refs_for_glue(
    raw_suffix, local_type_names, type_param_names, source_alias,
  )
  " " + qualified
}

///|
fn parse_type_params(
  source : String,
  imports : Array[MbtiImportRef],
  used_aliases : Array[String],
) -> Array[MbtiTypeParam] raise MbtiTypescriptDeclError {
  let normalized : Array[MbtiTypeParam] = []
  for raw in split_top_level_items(source) {
    if raw == "" {
      continue
    }
    let trimmed = raw.trim().to_string()
    match trimmed.find(":") {
      Some(idx) => {
        let name = trimmed[:idx].trim().to_string()
        let extends_src = trimmed[idx + 1:trimmed.length()].trim().to_string()
        let bound_parts = split_top_level_plus_items(extends_src)
        let rendered_bounds : Array[String] = []
        for bound_part in bound_parts {
          rendered_bounds.push(
            translate_mbti_type(bound_part, imports, used_aliases, None, []),
          )
        }
        let extends_ty = rendered_bounds.join(" & ")
        normalized.push({ name, extends_ty: Some(extends_ty) })
      }
      None => normalized.push({ name: trimmed, extends_ty: None })
    }
  }
  normalized
}

///|
fn type_param_names(type_params : Array[MbtiTypeParam]) -> Array[String] {
  let names : Array[String] = []
  for type_param in type_params {
    names.push(type_param.name)
  }
  names
}

///|
fn parse_mbti_imports(source : String) -> Array[MbtiImportRef] {
  let imports : Array[MbtiImportRef] = []
  let mut collecting = false
  for line_view in source.split("\n") {
    let trimmed = line_view.trim().to_string()
    if !collecting {
      if trimmed == "import {" {
        collecting = true
      }
      continue
    }
    if trimmed == "}" {
      collecting = false
      continue
    }
    let line = trim_trailing_comma_or_semicolon(trimmed)
    match parse_mbti_import_line(line) {
      Some({ alias_name, module_spec }) => {
        let mut ts_alias = sanitize_ts_identifier(alias_name, "pkg")
        while imports.any(fn(existing) { existing.ts_alias == ts_alias }) {
          ts_alias += "_"
        }
        imports.push({ alias_name, ts_alias, module_spec })
      }
      None => ()
    }
  }
  imports
}

///|
fn collect_mbti_omitted_autolink_members(source : String) -> Array[String] {
  let members : Array[String] = []
  for line_view in source.split("\n") {
    let line = line_view.to_string()
    match strip_mbti_public_prefix(line, "fn") {
      Some(rest) =>
        match rest.find("(") {
          Some(open_idx) => {
            let name = if rest.has_prefix("[") {
              match rest.find("]") {
                Some(close_idx) =>
                  rest[close_idx + 1:open_idx].trim().to_string()
                None => rest[:open_idx].trim().to_string()
              }
            } else {
              rest[:open_idx].trim().to_string()
            }
            if (name.contains("::") || rest.has_prefix("[")) &&
              !members.contains(name) {
              members.push(name)
            }
          }
          None => ()
        }
      None => ()
    }
  }
  for name in collect_runtime_inaccessible_free_function_names(source) {
    if !members.contains(name) {
      members.push(name)
    }
  }
  members
}

///|
fn collect_runtime_inaccessible_free_function_names(
  source : String,
) -> Array[String] {
  let imports = parse_mbti_imports(source)
  let used_aliases : Array[String] = []
  let private_type_names = collect_root_mbti_private_type_names(source) catch {
    _ => []
  }
  let names : Array[String] = []
  for line_view in source.split("\n") {
    let trimmed = line_view.trim().to_string()
    let parsed = parse_mbti_function_signature(trimmed, imports, used_aliases) catch {
      _ => None
    }
    match parsed {
      Some(signature) => {
        let (
          owner_name,
          fn_name,
          fn_type_params,
          params_src,
          _return_src,
          _is_async,
        ) = signature
        match owner_name {
          None => {
            let export_name = sanitize_ts_identifier(fn_name, "fn")
            if fn_type_params.length() > 0 {
              if !names.contains(export_name) {
                names.push(export_name)
              }
              continue
            }
            let raw_params = match
              parse_mbti_raw_facade_params(params_src, "") {
              Some(params) => params
              None => {
                if !names.contains(export_name) {
                  names.push(export_name)
                }
                continue
              }
            }
            let fn_type_param_names = type_param_names(fn_type_params)
            let return_src_with_effect = mbti_return_source_with_effect_from_function_line(
              trimmed,
            )
            if mbti_raw_facade_uses_private_types(
                raw_params, return_src_with_effect, private_type_names, fn_type_param_names,
              ) &&
              !names.contains(export_name) {
              names.push(export_name)
            }
          }
          Some(_) => ()
        }
      }
      None => ()
    }
  }
  names
}

///|
fn parse_mbti_package_name(source : String) -> String? {
  for line_view in source.split("\n") {
    let trimmed = line_view.trim().to_string()
    if !trimmed.has_prefix("package \"") {
      continue
    }
    let rest = trimmed["package \"".length():trimmed.length()].to_string()
    match rest.find("\"") {
      Some(end_idx) => {
        let package_name = rest[:end_idx].to_string()
        if package_name != "" {
          return Some(package_name)
        }
      }
      None => ()
    }
  }
  None
}

///|
fn render_autolink_diagnostics_md(
  ordered_packages : Array[String],
  package_sources : Map[String, String],
) -> String {
  let lines : Array[String] = [
    "# Autolink Diagnostics", "", "Public members omitted from link.js.exports because MoonBit JS autolink currently exports non-generic top-level public free functions with runtime-public boundary types.",
    "",
  ]
  let mut has_entries = false
  for package_name in ordered_packages {
    let source = match package_sources.get(package_name) {
      Some(source) => source
      None => continue
    }
    let omitted_members = collect_mbti_omitted_autolink_members(source)
    if omitted_members.length() == 0 {
      continue
    }
    has_entries = true
    lines.push("## " + package_name)
    lines.push("")
    for omitted in omitted_members {
      lines.push("- `" + omitted + "`")
    }
    lines.push("")
  }
  if !has_entries {
    lines.push("No omitted public members were detected.")
    lines.push("")
  }
  lines.join("\n")
}

///|
fn replace_mbti_self_refs(source : String, owner_name : String) -> String {
  source.replace(old="Self", new=owner_name)
}

///|
fn parse_mbti_raw_facade_params(
  source : String,
  owner_name : String,
) -> Array[MbtiRawFacadeParam]? {
  let params : Array[MbtiRawFacadeParam] = []
  let mut idx = 0
  for raw in split_top_level_items(source) {
    let trimmed = raw.trim().to_string()
    if trimmed == "" {
      continue
    }
    match trimmed.find(":") {
      Some(colon_idx) => {
        let raw_name = trimmed[:colon_idx].trim().to_string()
        let optional = raw_name.has_suffix("?")
        let name = if idx == 0 && trimmed.has_prefix("Self") {
          "self"
        } else if optional {
          raw_name[:raw_name.length() - 1].trim().to_string()
        } else {
          raw_name
        }
        let ty_src = replace_mbti_self_refs(
          trimmed[colon_idx + 1:trimmed.length()].trim().to_string(),
          owner_name,
        )
        params.push({ name, ty_src, optional })
      }
      None => {
        let name = if idx == 0 && trimmed.has_prefix("Self") {
          "self"
        } else {
          "arg\{idx}"
        }
        let ty_src = replace_mbti_self_refs(trimmed, owner_name)
        params.push({ name, ty_src, optional: false })
      }
    }
    idx += 1
  }
  Some(params)
}

///|
fn mbti_source_alias() -> String {
  "tsmbt_source"
}

///|
fn mbti_source_alias_for_package(
  root_package_name : String,
  package_name : String,
) -> String {
  if package_name == root_package_name {
    mbti_source_alias()
  } else {
    let alias_suffix = match
      mbti_local_package_segments(root_package_name, package_name) {
      Some(segments) if segments.length() > 0 => {
        let parts : Array[String] = []
        for segment in segments {
          parts.push(mbti_to_snake_case(segment))
        }
        parts.join("_")
      }
      _ => mbti_to_snake_case(package_name)
    }
    "tsmbt_source_\{alias_suffix}"
  }
}

///|
fn mbti_is_identifier_start(c : Char) -> Bool {
  mbti_is_ascii_letter(c) || c == '_'
}

///|
fn mbti_is_identifier_continue(c : Char) -> Bool {
  mbti_is_identifier_start(c) || mbti_is_ascii_digit(c)
}

///|
fn mbti_qualify_root_type_refs_for_glue(
  source : String,
  local_type_names : Array[String],
  type_param_names : Array[String],
  source_alias : String,
) -> String {
  let mut rendered = ""
  let mut idx = 0
  while idx < source.length() {
    let c = mbti_char_at(source, idx)
    if mbti_is_identifier_start(c) {
      let start = idx
      idx += 1
      while idx < source.length() &&
            mbti_is_identifier_continue(mbti_char_at(source, idx)) {
        idx += 1
      }
      let ident = source[start:idx].to_string()
      let prev = if start > 0 {
        Some(mbti_char_at(source, start - 1))
      } else {
        None
      }
      if local_type_names.contains(ident) &&
        !type_param_names.contains(ident) &&
        prev != Some('.') &&
        prev != Some('@') {
        rendered += "@\{source_alias}.\{ident}"
      } else {
        rendered += ident
      }
    } else {
      rendered += c.to_string()
      idx += 1
    }
  }
  rendered
}

///|
fn render_mbt_glue_params(
  params : Array[MbtiRawFacadeParam],
  local_type_names : Array[String],
  type_param_names : Array[String],
  source_alias : String,
) -> String {
  let rendered : Array[String] = []
  for param in params {
    let ty_src = mbti_render_js_boundary_glue_param_type(
      param.ty_src,
      local_type_names,
      type_param_names,
      source_alias,
    )
    let rendered_ty_src = if param.optional { "(\{ty_src})?" } else { ty_src }
    let name = if param.name == "self" { "self_" } else { param.name }
    rendered.push("\{name} : \{rendered_ty_src}")
  }
  rendered.join(", ")
}

///|
fn mbti_strip_borrow_prefix(source : String) -> String {
  let trimmed = source.trim().to_string()
  if trimmed.has_prefix("&") {
    trimmed[1:trimmed.length()].trim().to_string()
  } else {
    trimmed
  }
}

///|
fn mbti_render_js_boundary_glue_param_type(
  source : String,
  local_type_names : Array[String],
  type_param_names : Array[String],
  source_alias : String,
) -> String {
  let unborrowed = mbti_strip_borrow_prefix(source)
  if unborrowed == "StringView" {
    return "String"
  }
  if unborrowed == "BytesView" {
    return "Bytes"
  }
  if unborrowed.has_prefix("ArrayView[") {
    let inner = unborrowed["ArrayView[".length():unborrowed.length() - 1].to_string()
    let rendered_inner = mbti_qualify_root_type_refs_for_glue(
      inner, local_type_names, type_param_names, source_alias,
    )
    return "Array[\{rendered_inner}]"
  }
  mbti_qualify_root_type_refs_for_glue(
    source, local_type_names, type_param_names, source_alias,
  )
}

///|
fn mbti_render_js_boundary_call_arg(param : MbtiRawFacadeParam) -> String {
  let unborrowed = mbti_strip_borrow_prefix(param.ty_src)
  let name = if param.name == "self" { "self_" } else { param.name }
  if unborrowed == "StringView" {
    return "\{name}.view()"
  }
  if unborrowed == "BytesView" {
    return "\{name}.view()"
  }
  if unborrowed.has_prefix("ArrayView[") {
    return "\{name}[:]"
  }
  if param.name == "self" {
    return "self_"
  }
  if param.optional {
    return "\{param.name}?"
  }
  param.name
}

///|
fn render_mbt_glue_call_args(params : Array[MbtiRawFacadeParam]) -> String {
  let args : Array[String] = []
  for param in params {
    args.push(mbti_render_js_boundary_call_arg(param))
  }
  args.join(", ")
}

///|
fn render_mbt_glue_method_tail_call_args(
  params : Array[MbtiRawFacadeParam],
) -> String {
  if params.length() <= 1 {
    return ""
  }
  let args : Array[String] = []
  for idx in 1..<params.length() {
    args.push(mbti_render_js_boundary_call_arg(params[idx]))
  }
  args.join(", ")
}

///|
fn render_mbt_raw_type_param_suffix_from_line(line : String) -> String {
  let trimmed = line.trim().to_string()
  let mut idx = if trimmed.has_prefix("pub async fn") {
    "pub async fn".length()
  } else if trimmed.has_prefix("pub fn") && !trimmed.has_prefix("pub fn(") {
    "pub fn".length()
  } else {
    return ""
  }
  while idx < trimmed.length() && mbti_char_at(trimmed, idx) == ' ' {
    idx += 1
  }
  if idx < trimmed.length() && mbti_char_at(trimmed, idx) == '[' {
    match find_matching(trimmed, idx, '[', ']') {
      Some(end_idx) => trimmed[idx:end_idx + 1].to_string()
      None => ""
    }
  } else {
    ""
  }
}

///|
fn collect_root_mbti_local_type_params(
  source : String,
) -> Map[String, Array[MbtiTypeParam]] raise MbtiTypescriptDeclError {
  let imports = parse_mbti_imports(source)
  let used_aliases : Array[String] = []
  let type_params_by_name : Map[String, Array[MbtiTypeParam]] = {}
  let lines : Array[String] = []
  for line in source.split("\n") {
    lines.push(line.to_string())
  }
  let mut idx = 0
  while idx < lines.length() {
    let line = lines[idx]
    let trimmed = line.trim().to_string()
    if trimmed.has_prefix("pub struct ") ||
      trimmed.has_prefix("pub(all) struct ") {
      let (block, next_idx) = collect_mbti_decl_block(lines, idx)
      let struct_decl = parse_struct_block_decl(block, imports, used_aliases)
      type_params_by_name[struct_decl.name] = struct_decl.type_params
      idx = next_idx
      continue
    }
    if trimmed.has_prefix("pub enum ") || trimmed.has_prefix("pub(all) enum ") {
      let (block, next_idx) = collect_brace_block(lines, idx)
      let enum_decl = parse_enum_like_block_decl(
        block, "enum", imports, used_aliases,
      )
      type_params_by_name[enum_decl.name] = enum_decl.type_params
      idx = next_idx
      continue
    }
    if trimmed.has_prefix("pub suberror ") ||
      trimmed.has_prefix("pub(all) suberror ") {
      let (block, next_idx) = collect_brace_block(lines, idx)
      let enum_decl = parse_enum_like_block_decl(
        block, "suberror", imports, used_aliases,
      )
      type_params_by_name[enum_decl.name] = enum_decl.type_params
      idx = next_idx
      continue
    }
    if trimmed.has_prefix("pub type ") || trimmed.has_prefix("pub(all) type ") {
      let alias_decl = parse_type_alias_decl(trimmed, imports, used_aliases)
      type_params_by_name[alias_decl.name] = alias_decl.type_params
      idx += 1
      continue
    }
    idx += 1
  }
  type_params_by_name
}

///|
fn collect_root_mbti_local_trait_names(
  source : String,
) -> Array[String] raise MbtiTypescriptDeclError {
  let imports = parse_mbti_imports(source)
  let used_aliases : Array[String] = []
  let names : Array[String] = []
  for line in source.split("\n") {
    let trimmed = line.trim().to_string()
    if trimmed.has_prefix("pub trait ") ||
      trimmed.has_prefix("pub(all) trait ") ||
      trimmed.has_prefix("pub(open) trait ") {
      match parse_mbti_type_header(trimmed, "trait", imports, used_aliases) {
        Some((name, _)) if !names.contains(name) => names.push(name)
        _ => ()
      }
    }
  }
  names
}

///|
fn parse_private_mbti_type_name(
  trimmed : String,
  keyword : String,
  imports : Array[MbtiImportRef],
  used_aliases : Array[String],
) -> String? raise MbtiTypescriptDeclError {
  if !trimmed.has_prefix(keyword + " ") {
    return None
  }
  let header = trimmed[keyword.length() + 1:trimmed.length()].trim().to_string()
  match parse_mbti_type_name_and_params(header, imports, used_aliases) {
    Some((name, _)) => Some(name)
    None => None
  }
}

///|
fn collect_root_mbti_private_type_names(
  source : String,
) -> Array[String] raise MbtiTypescriptDeclError {
  let imports = parse_mbti_imports(source)
  let used_aliases : Array[String] = []
  let names : Array[String] = []
  for line in source.split("\n") {
    let trimmed = line.trim().to_string()
    if trimmed == "" || trimmed.has_prefix("//") {
      continue
    }
    let name = if trimmed.has_prefix("type ") {
      match parse_private_type_alias_decl(trimmed, imports, used_aliases) {
        Some(alias_decl) => Some(alias_decl.name)
        None => None
      }
    } else if trimmed.has_prefix("struct ") {
      parse_private_mbti_type_name(trimmed, "struct", imports, used_aliases)
    } else if trimmed.has_prefix("enum ") {
      parse_private_mbti_type_name(trimmed, "enum", imports, used_aliases)
    } else if trimmed.has_prefix("suberror ") {
      parse_private_mbti_type_name(trimmed, "suberror", imports, used_aliases)
    } else {
      None
    }
    match name {
      Some(name) if !names.contains(name) => names.push(name)
      _ => ()
    }
  }
  names
}

///|
fn mbti_type_source_mentions_private_local_type(
  source : String,
  private_type_names : Array[String],
  type_param_names : Array[String],
) -> Bool {
  let mut idx = 0
  while idx < source.length() {
    let c = mbti_char_at(source, idx)
    if mbti_is_identifier_start(c) {
      let start = idx
      idx += 1
      while idx < source.length() &&
            mbti_is_identifier_continue(mbti_char_at(source, idx)) {
        idx += 1
      }
      let ident = source[start:idx].to_string()
      let prev = if start > 0 {
        Some(mbti_char_at(source, start - 1))
      } else {
        None
      }
      if private_type_names.contains(ident) &&
        !type_param_names.contains(ident) &&
        prev != Some('.') &&
        prev != Some('@') {
        return true
      }
    } else {
      idx += 1
    }
  }
  false
}

///|
fn mbti_raw_facade_uses_private_types(
  raw_params : Array[MbtiRawFacadeParam],
  return_src : String,
  private_type_names : Array[String],
  type_param_names : Array[String],
) -> Bool {
  if mbti_type_source_mentions_private_local_type(
      return_src, private_type_names, type_param_names,
    ) {
    return true
  }
  for param in raw_params {
    if mbti_type_source_mentions_private_local_type(
        param.ty_src,
        private_type_names,
        type_param_names,
      ) {
      return true
    }
  }
  false
}

///|
fn collect_mbti_autolink_glue_decls(
  package_name : String,
  source : String,
  source_alias : String,
  include_facades : Bool,
  local_package_import_alias_rewrites : Map[String, String],
  runtime_export_prefix : String,
) -> Array[MbtiAutolinkGlueDecl] raise MbtiTypescriptDeclError {
  let imports = parse_mbti_imports(source)
  let used_aliases : Array[String] = []
  let local_type_params = collect_root_mbti_local_type_params(source)
  let local_type_names : Array[String] = []
  for pair in local_type_params {
    let (name, _) = pair
    local_type_names.push(name)
  }
  let local_glue_ref_names = local_type_names.copy()
  for trait_name in collect_root_mbti_local_trait_names(source) {
    if !local_glue_ref_names.contains(trait_name) {
      local_glue_ref_names.push(trait_name)
    }
  }
  let private_type_names = collect_root_mbti_private_type_names(source)
  let decls : Array[MbtiAutolinkGlueDecl] = []
  let free_function_names : Array[String] = []
  for line_view in source.split("\n") {
    let trimmed = line_view.trim().to_string()
    match parse_mbti_function_signature(trimmed, imports, used_aliases) {
      Some(signature) => {
        let (
          owner_name,
          fn_name,
          fn_type_params,
          params_src,
          return_src,
          is_async,
        ) = signature
        let return_src_with_effect = mbti_return_source_with_effect_from_function_line(
          trimmed,
        )
        let glue_params_src = rewrite_mbti_glue_import_alias_refs(
          params_src, local_package_import_alias_rewrites,
        )
        let glue_return_src = rewrite_mbti_glue_import_alias_refs(
          return_src, local_package_import_alias_rewrites,
        )
        let glue_return_src_with_effect = rewrite_mbti_glue_import_alias_refs(
          return_src_with_effect, local_package_import_alias_rewrites,
        )
        let fn_type_param_names = type_param_names(fn_type_params)
        let raw_type_param_suffix = rewrite_mbti_glue_import_alias_refs(
          render_mbt_raw_type_param_suffix_from_line(trimmed),
          local_package_import_alias_rewrites,
        )
        let type_param_suffix = mbti_qualify_root_type_refs_for_glue(
          raw_type_param_suffix, local_glue_ref_names, fn_type_param_names, source_alias,
        )
        match owner_name {
          None => {
            if fn_type_params.length() > 0 {
              continue
            }
            let raw_params = match
              parse_mbti_raw_facade_params(glue_params_src, "") {
              Some(params) => params
              None => continue
            }
            if mbti_raw_facade_uses_private_types(
                raw_params, glue_return_src_with_effect, private_type_names, fn_type_param_names,
              ) {
              continue
            }
            let return_ty = mbti_qualify_root_type_refs_for_glue(
              glue_return_src, local_type_names, fn_type_param_names, source_alias,
            )
            let rendered_mbt_params = render_mbt_glue_params(
              raw_params, local_type_names, fn_type_param_names, source_alias,
            )
            let call_args = render_mbt_glue_call_args(raw_params)
            let async_prefix = if is_async { "async " } else { "" }
            let effect_suffix = mbti_qualified_effect_suffix_for_glue(
              glue_return_src_with_effect, local_type_names, fn_type_param_names,
              source_alias,
            )
            let export_name = sanitize_ts_identifier(fn_name, "fn")
            let runtime_export_name = runtime_export_prefix + export_name
            let body_expr = if call_args == "" {
              "@\{source_alias}.\{fn_name}()"
            } else {
              "@\{source_alias}.\{fn_name}(\{call_args})"
            }
            let mbt_decl = "pub \{async_prefix}fn\{type_param_suffix} \{runtime_export_name}(\{rendered_mbt_params}) -> \{return_ty}\{effect_suffix} {\n  \{body_expr}\n}"
            decls.push({
              package_name,
              export_name,
              runtime_export_name,
              ts_decl: "",
              mbt_decl,
            })
            free_function_names.push(export_name)
          }
          Some(owner_name) if include_facades =>
            match local_type_params.get(owner_name) {
              Some(owner_type_params) => {
                if owner_type_params.length() > 0 || fn_type_params.length() > 0 {
                  continue
                }
                let owner_type_param_names = type_param_names(owner_type_params)
                let params = parse_mbti_params(
                  params_src,
                  imports,
                  used_aliases,
                  Some(owner_name),
                  owner_type_param_names,
                )
                let raw_params = match
                  parse_mbti_raw_facade_params(glue_params_src, owner_name) {
                  Some(params) => params
                  None => continue
                }
                if mbti_raw_facade_uses_private_types(
                    raw_params,
                    replace_mbti_self_refs(
                      glue_return_src_with_effect, owner_name,
                    ),
                    private_type_names,
                    owner_type_param_names,
                  ) {
                  continue
                }
                let return_ty = translate_mbti_type(
                  return_src,
                  imports,
                  used_aliases,
                  Some(owner_name),
                  owner_type_param_names,
                )
                let rendered_return_ty = render_ts_return_type_with_effect(
                  return_src_with_effect,
                  return_ty,
                  is_async,
                  imports,
                  used_aliases,
                  Some(owner_name),
                  owner_type_param_names,
                )
                let export_name = "\{mbti_to_snake_case(owner_name)}_\{mbti_to_snake_case(fn_name)}"
                let mut unique_export_name = export_name
                while free_function_names.contains(unique_export_name) ||
                      decls.any(fn(decl) {
                        decl.export_name == unique_export_name
                      }) {
                  unique_export_name += "_facade"
                }
                let rendered_ts_params = render_ts_params(params)
                let facade_ts_decl = "export function \{unique_export_name}(\{rendered_ts_params}): \{rendered_return_ty};"
                let runtime_unique_export_name = runtime_export_prefix +
                  unique_export_name
                let async_prefix = if is_async { "async " } else { "" }
                let rendered_mbt_params = render_mbt_glue_params(
                  raw_params,
                  local_type_names,
                  [],
                  source_alias,
                )
                let rendered_mbt_return = mbti_qualify_root_type_refs_for_glue(
                  replace_mbti_self_refs(glue_return_src, owner_name),
                  local_type_names,
                  [],
                  source_alias,
                )
                let effect_suffix = mbti_qualified_effect_suffix_for_glue(
                  replace_mbti_self_refs(
                    glue_return_src_with_effect, owner_name,
                  ),
                  local_type_names,
                  [],
                  source_alias,
                )
                let call_args = render_mbt_glue_call_args(raw_params)
                let body_expr = if raw_params.length() > 0 &&
                  raw_params[0].name == "self" {
                  let tail_args = render_mbt_glue_method_tail_call_args(
                    raw_params,
                  )
                  if tail_args == "" {
                    "self_.\{fn_name}()"
                  } else {
                    "self_.\{fn_name}(\{tail_args})"
                  }
                } else {
                  "@\{source_alias}.\{owner_name}::\{fn_name}(\{call_args})"
                }
                let facade_mbt_decl = "pub \{async_prefix}fn \{runtime_unique_export_name}(\{rendered_mbt_params}) -> \{rendered_mbt_return}\{effect_suffix} {\n  \{body_expr}\n}"
                decls.push({
                  package_name,
                  export_name: unique_export_name,
                  runtime_export_name: runtime_unique_export_name,
                  ts_decl: facade_ts_decl,
                  mbt_decl: facade_mbt_decl,
                })
              }
              None => ()
            }
          _ => ()
        }
      }
      None => ()
    }
  }
  decls
}

///|
fn collect_mbti_bundle_autolink_glue_decls(
  loaded : LoadedMbtiPackageSources,
  include_facades : Bool,
) -> Array[MbtiAutolinkGlueDecl] raise MbtiTypescriptDeclError {
  let decls : Array[MbtiAutolinkGlueDecl] = []
  let local_package_aliases : Map[String, String] = {}
  for package_name in loaded.ordered_packages {
    local_package_aliases[package_name] = mbti_source_alias_for_package(
      loaded.root_package_name,
      package_name,
    )
  }
  for package_name in loaded.ordered_packages {
    let source = match loaded.package_sources.get(package_name) {
      Some(source) => source
      None =>
        raise MbtiTypescriptDeclError::ParseError(
          "missing loaded package source for \{package_name}",
        )
    }
    let source_alias = match local_package_aliases.get(package_name) {
      Some(alias_name) => alias_name
      None =>
        raise MbtiTypescriptDeclError::ParseError(
          "missing generated package alias for \{package_name}",
        )
    }
    let local_package_import_alias_rewrites : Map[String, String] = {}
    for import_ref in parse_mbti_imports(source) {
      match local_package_aliases.get(import_ref.module_spec) {
        Some(alias_name) if alias_name != import_ref.alias_name =>
          local_package_import_alias_rewrites[import_ref.alias_name] = alias_name
        _ => ()
      }
    }
    let runtime_export_prefix = if package_name == loaded.root_package_name {
      ""
    } else {
      source_alias + "_"
    }
    let package_decls = collect_mbti_autolink_glue_decls(
      package_name, source, source_alias, include_facades, local_package_import_alias_rewrites,
      runtime_export_prefix,
    )
    for decl in package_decls {
      decls.push(decl)
    }
  }
  sort_mbti_autolink_glue_decls(decls)
}

///|
fn mbti_compare_string_ascending(lhs : String, rhs : String) -> Int {
  let min_len = if lhs.length() < rhs.length() {
    lhs.length()
  } else {
    rhs.length()
  }
  for idx in 0..<min_len {
    let lhs_code = lhs[idx].to_int()
    let rhs_code = rhs[idx].to_int()
    if lhs_code < rhs_code {
      return -1
    }
    if lhs_code > rhs_code {
      return 1
    }
  }
  if lhs.length() < rhs.length() {
    -1
  } else if lhs.length() > rhs.length() {
    1
  } else {
    0
  }
}

///|
fn sort_strings_ascending(items : Array[String]) -> Unit {
  items.sort_by(fn(lhs, rhs) { mbti_compare_string_ascending(lhs, rhs) })
}

///|
fn sort_mbti_autolink_glue_decls(
  decls : Array[MbtiAutolinkGlueDecl],
) -> Array[MbtiAutolinkGlueDecl] {
  let sorted = decls.copy()
  sorted.sort_by(fn(lhs, rhs) {
    let package_cmp = mbti_compare_string_ascending(
      lhs.package_name,
      rhs.package_name,
    )
    if package_cmp != 0 {
      return package_cmp
    }
    let export_cmp = mbti_compare_string_ascending(
      lhs.export_name,
      rhs.export_name,
    )
    if export_cmp != 0 {
      return export_cmp
    }
    mbti_compare_string_ascending(
      lhs.runtime_export_name,
      rhs.runtime_export_name,
    )
  })
  sorted
}

///|
fn render_autolink_glue_mbt(decls : Array[MbtiAutolinkGlueDecl]) -> String {
  if decls.length() == 0 {
    return ""
  }
  let sections : Array[String] = []
  sections.push("///|")
  sections.push(
    "/// Auto-generated glue wrappers for MoonBit JS package output.",
  )
  for decl in decls {
    sections.push("")
    sections.push(decl.mbt_decl)
  }
  sections.join("\n")
}

///|
fn json_escape_string(source : String) -> String {
  let mut escaped = ""
  for c in source {
    if c == '\\' {
      escaped += "\\\\"
    } else if c == '"' {
      escaped += "\\\""
    } else if c == '\n' {
      escaped += "\\n"
    } else if c == '\r' {
      escaped += "\\r"
    } else if c == '\t' {
      escaped += "\\t"
    } else {
      escaped += c.to_string()
    }
  }
  escaped
}

///|
fn render_glue_import_entry(path : String, alias_name : String) -> String {
  "    { \"path\": \"\{json_escape_string(path)}\", \"alias\": \"\{json_escape_string(alias_name)}\" }"
}

///|
fn push_unique_glue_import_entry(
  entries : Array[String],
  seen : Array[String],
  path : String,
  alias_name : String,
) -> Unit {
  let key = path + "\n" + alias_name
  if !seen.contains(key) {
    seen.push(key)
    entries.push(render_glue_import_entry(path, alias_name))
  }
}

///|
fn render_moonbit_js_glue_pkg_json(
  loaded : LoadedMbtiPackageSources,
  export_names : Array[String],
) -> String raise MbtiTypescriptDeclError {
  let import_entries : Array[String] = []
  let seen_import_entries : Array[String] = []
  for package_name in loaded.ordered_packages {
    let source = match loaded.package_sources.get(package_name) {
      Some(source) => source
      None =>
        raise MbtiTypescriptDeclError::ParseError(
          "missing loaded package source for \{package_name}",
        )
    }
    push_unique_glue_import_entry(
      import_entries,
      seen_import_entries,
      package_name,
      mbti_source_alias_for_package(loaded.root_package_name, package_name),
    )
    for import_ref in parse_mbti_imports(source) {
      let alias_name = match
        mbti_local_package_segments(
          loaded.root_package_name,
          import_ref.module_spec,
        ) {
        Some(_) =>
          mbti_source_alias_for_package(
            loaded.root_package_name,
            import_ref.module_spec,
          )
        None => import_ref.alias_name
      }
      push_unique_glue_import_entry(
        import_entries,
        seen_import_entries,
        import_ref.module_spec,
        alias_name,
      )
    }
  }
  sort_strings_ascending(import_entries)
  let sorted_export_names = export_names.copy()
  sort_strings_ascending(sorted_export_names)
  let lines : Array[String] = ["{"]
  lines.push("  \"import\": [")
  for idx in 0..<import_entries.length() {
    let suffix = if idx + 1 < import_entries.length() { "," } else { "" }
    lines.push(import_entries[idx] + suffix)
  }
  lines.push("  ],")
  lines.push("  \"link\": {")
  lines.push("    \"js\": {")
  lines.push("      \"exports\": [")
  for idx in 0..<sorted_export_names.length() {
    let suffix = if idx + 1 < sorted_export_names.length() { "," } else { "" }
    lines.push(
      "        \"\{json_escape_string(sorted_export_names[idx])}\"\{suffix}",
    )
  }
  lines.push("      ],")
  lines.push("      \"format\": \"esm\"")
  lines.push("    }")
  lines.push("  }")
  lines.push("}")
  lines.join("\n")
}

///|
fn mbti_join_path(base : String, child : String) -> String {
  if base == "." || base == "" {
    child
  } else if base.has_suffix("/") {
    base + child
  } else {
    base + "/" + child
  }
}

///|
fn mbti_dirname(path : String) -> String {
  match path.rev_find("/") {
    Some(0) => "/"
    Some(idx) => path[:idx].to_string()
    None => "."
  }
}

///|
fn mbti_generated_package_relative_path(segments : Array[String]) -> String {
  if segments.length() == 0 {
    "pkg.generated.mbti"
  } else {
    segments.join("/") + "/pkg.generated.mbti"
  }
}

///|
fn collect_mbti_fully_qualified_package_refs(source : String) -> Array[String] {
  let refs : Array[String] = []
  for idx = 0; idx < source.length(); idx = idx + 1 {
    if mbti_char_at(source, idx) != '@' {
      continue
    }
    let start = idx + 1
    let mut end_ = start
    while end_ < source.length() {
      let c = mbti_char_at(source, end_)
      if c == '.' || c == ']' || c == ')' || c == ',' || c == ' ' || c == '\n' {
        break
      }
      end_ += 1
    }
    if end_ <= start ||
      end_ >= source.length() ||
      mbti_char_at(source, end_) != '.' {
      continue
    }
    let package_name = source[start:end_].to_string()
    if package_name.contains("/") && !refs.contains(package_name) {
      refs.push(package_name)
    }
  }
  refs
}

///|
async fn load_mbti_package_sources(
  root_file_path : String,
) -> LoadedMbtiPackageSources raise MbtiTypescriptDeclError {
  let root_source = @fs.read_file(root_file_path).text() catch {
    e => raise MbtiTypescriptDeclError::ReadError("\{e}")
  }
  let root_package_name = match parse_mbti_package_name(root_source) {
    Some(package_name) => package_name
    None =>
      raise MbtiTypescriptDeclError::ParseError(
        "missing package declaration in \{root_file_path}",
      )
  }
  let source_root_dir = mbti_dirname(root_file_path)
  let package_sources : Map[String, String] = {}
  let pending_packages : Array[String] = [root_package_name]
  let ordered_packages : Array[String] = []
  package_sources[root_package_name] = root_source
  while pending_packages.length() > 0 {
    let package_name = pending_packages[pending_packages.length() - 1]
    let _ = pending_packages.pop()
    if ordered_packages.contains(package_name) {
      continue
    }
    let source = match package_sources.get(package_name) {
      Some(source) => source
      None =>
        raise MbtiTypescriptDeclError::ParseError(
          "missing loaded package source for \{package_name}",
        )
    }
    ordered_packages.push(package_name)
    for import_ref in parse_mbti_imports(source) {
      match
        mbti_local_package_segments(root_package_name, import_ref.module_spec) {
        Some(target_segments) => {
          if !package_sources.contains(import_ref.module_spec) {
            let relative_pkg_path = mbti_generated_package_relative_path(
              target_segments,
            )
            let target_file_path = mbti_join_path(
              source_root_dir, relative_pkg_path,
            )
            let target_source = @fs.read_file(target_file_path).text() catch {
              e => raise MbtiTypescriptDeclError::ReadError("\{e}")
            }
            package_sources[import_ref.module_spec] = target_source
          }
          if !ordered_packages.contains(import_ref.module_spec) &&
            !pending_packages.contains(import_ref.module_spec) {
            pending_packages.push(import_ref.module_spec)
          }
        }
        None => ()
      }
    }
    for referenced_package in collect_mbti_fully_qualified_package_refs(source) {
      match mbti_local_package_segments(root_package_name, referenced_package) {
        Some(target_segments) => {
          if !package_sources.contains(referenced_package) {
            let target_file_path = mbti_join_path(
              source_root_dir,
              mbti_generated_package_relative_path(target_segments),
            )
            let file_kind = @fs.kind(target_file_path, follow_symlink=false) catch {
              _ => @fs.FileKind::Unknown
            }
            if !(file_kind is @fs.FileKind::Regular) {
              continue
            }
            let target_source = @fs.read_file(target_file_path).text() catch {
              e => raise MbtiTypescriptDeclError::ReadError("\{e}")
            }
            package_sources[referenced_package] = target_source
          }
          if !ordered_packages.contains(referenced_package) &&
            !pending_packages.contains(referenced_package) {
            pending_packages.push(referenced_package)
          }
        }
        None => ()
      }
    }
  }
  { root_package_name, ordered_packages, package_sources }
}

///|
fn mbti_local_package_segments(
  root_package_name : String,
  package_name : String,
) -> Array[String]? {
  if package_name == root_package_name {
    return Some([])
  }
  let prefix = root_package_name + "/"
  if !package_name.has_prefix(prefix) {
    return None
  }
  let suffix = package_name[prefix.length():package_name.length()].to_string()
  if suffix == "" {
    return Some([])
  }
  let segments : Array[String] = []
  for part_view in suffix.split("/") {
    let part = part_view.to_string()
    if part != "" {
      segments.push(part)
    }
  }
  Some(segments)
}

///|
fn mbti_bundle_relative_path_from_segments(segments : Array[String]) -> String {
  if segments.length() == 0 {
    "index.d.ts"
  } else {
    segments.join("/") + "/index.d.ts"
  }
}

///|
fn trim_edge_char(source : String, target : Char) -> String {
  let mut start = 0
  let mut end_ = source.length()
  while start < end_ && mbti_char_at(source, start) == target {
    start += 1
  }
  while end_ > start && mbti_char_at(source, end_ - 1) == target {
    end_ -= 1
  }
  source[start:end_].to_string()
}

///|
fn sanitize_npm_package_segment(segment : String, fallback : String) -> String {
  let mut result = ""
  for c in segment {
    let normalized = mbti_ascii_lower_char(c)
    if mbti_is_ascii_letter(normalized) ||
      mbti_is_ascii_digit(normalized) ||
      normalized == '-' ||
      normalized == '_' ||
      normalized == '.' {
      result += normalized.to_string()
    } else {
      result += "-"
    }
  }
  while result.contains("--") {
    result = result.replace(old="--", new="-")
  }
  result = trim_edge_char(result, '-')
  if result == "" {
    fallback
  } else {
    result
  }
}

///|
fn mbti_root_package_npm_name(root_package_name : String) -> String {
  let segments : Array[String] = []
  for part_view in root_package_name.split("/") {
    let part = part_view.to_string()
    if part != "" {
      segments.push(part)
    }
  }
  if segments.length() == 0 {
    return "moonbit-package"
  }
  if segments.length() == 1 {
    return sanitize_npm_package_segment(segments[0], "moonbit-package")
  }
  let scope = sanitize_npm_package_segment(segments[0], "moonbit")
  let pkg_parts : Array[String] = []
  for idx in 1..<segments.length() {
    pkg_parts.push(sanitize_npm_package_segment(segments[idx], "pkg"))
  }
  "@\{scope}/" + pkg_parts.join("-")
}

///|
fn mbti_export_key_from_relative_path(relative_path : String) -> String? {
  if relative_path == "index.d.ts" {
    return Some(".")
  }
  if !relative_path.has_suffix("/index.d.ts") {
    return None
  }
  let export_path = relative_path[:relative_path.length() -
  "/index.d.ts".length()].to_string()
  if export_path == "" {
    Some(".")
  } else {
    Some("./" + export_path)
  }
}

///|
fn package_file_exists(
  files : Array[MbtiTypescriptPackageFile],
  relative_path : String,
) -> Bool {
  files.any(fn(file) { file.relative_path == relative_path })
}

///|
fn mbti_runtime_js_path_for_decl_path(relative_path : String) -> String {
  if relative_path.has_suffix(".d.ts") {
    relative_path[:relative_path.length() - ".d.ts".length()].to_string() +
    ".js"
  } else {
    relative_path
  }
}

///|
fn render_typescript_package_json(
  root_package_name : String,
  files : Array[MbtiTypescriptPackageFile],
) -> String {
  let package_name = mbti_root_package_npm_name(root_package_name)
  let exports_lines : Array[String] = []
  for file in files {
    match mbti_export_key_from_relative_path(file.relative_path) {
      Some(export_key) =>
        if export_key == "." {
          exports_lines.push(
            "    \".\": { \"types\": \"./index.d.ts\", \"import\": \"./index.js\" }",
          )
        } else {
          let js_path = mbti_runtime_js_path_for_decl_path(file.relative_path)
          if package_file_exists(files, js_path) {
            exports_lines.push(
              "    \"\{export_key}\": { \"types\": \"./\{file.relative_path}\", \"import\": \"./\{js_path}\" }",
            )
          } else {
            exports_lines.push(
              "    \"\{export_key}\": { \"types\": \"./\{file.relative_path}\" }",
            )
          }
        }
      None => ()
    }
  }
  sort_strings_ascending(exports_lines)
  let lines : Array[String] = [
    "{",
    "  \"name\": \"\{package_name}\",",
    "  \"version\": \"0.0.0\",",
    "  \"type\": \"module\",",
    "  \"sideEffects\": false,",
    "  \"main\": \"./index.js\",",
    "  \"module\": \"./index.js\",",
    "  \"types\": \"./index.d.ts\",",
    "  \"exports\": {",
  ]
  for idx in 0..<exports_lines.length() {
    let suffix = if idx + 1 < exports_lines.length() { "," } else { "" }
    lines.push(exports_lines[idx] + suffix)
  }
  lines.push("  }")
  lines.push("}")
  lines.join("\n")
}

///|
fn mbti_relative_package_import_spec(
  from_segments : Array[String],
  to_segments : Array[String],
) -> String {
  let mut shared = 0
  while shared < from_segments.length() &&
        shared < to_segments.length() &&
        from_segments[shared] == to_segments[shared] {
    shared += 1
  }
  let parts : Array[String] = []
  for _ in shared..<from_segments.length() {
    parts.push("..")
  }
  for idx in shared..<to_segments.length() {
    parts.push(to_segments[idx])
  }
  if parts.length() == 0 {
    "."
  } else if parts[0] == ".." {
    parts.join("/")
  } else {
    "./" + parts.join("/")
  }
}

///|
fn lookup_import_ts_alias(
  imports : Array[MbtiImportRef],
  alias_name : String,
) -> String {
  for import_ref in imports {
    if import_ref.alias_name == alias_name {
      return import_ref.ts_alias
    }
  }
  sanitize_ts_identifier(alias_name, "pkg")
}

///|
fn collect_used_import_refs(
  imports : Array[MbtiImportRef],
  used_aliases : Array[String],
) -> Array[MbtiImportRef] {
  let refs : Array[MbtiImportRef] = []
  for alias_name in used_aliases {
    let mut found = false
    for import_ref in imports {
      if import_ref.alias_name == alias_name {
        refs.push(import_ref)
        found = true
        break
      }
    }
    if !found {
      refs.push({
        alias_name,
        ts_alias: sanitize_ts_identifier(alias_name, "pkg"),
        module_spec: alias_name,
      })
    }
  }
  refs
}

///|
fn parse_mbti_params(
  source : String,
  imports : Array[MbtiImportRef],
  used_aliases : Array[String],
  owner_name : String?,
  owner_type_params : Array[String],
) -> Array[MbtiParam] raise MbtiTypescriptDeclError {
  let params : Array[MbtiParam] = []
  let mut idx = 0
  for raw in split_top_level_items(source) {
    let trimmed = raw.trim().to_string()
    if trimmed == "" {
      continue
    }
    match trimmed.find(":") {
      Some(colon_idx) => {
        let raw_name = trimmed[:colon_idx].trim().to_string()
        let name = if raw_name.has_suffix("?") {
          raw_name[:raw_name.length() - 1].trim().to_string()
        } else {
          raw_name
        }
        let ty = translate_mbti_type(
          trimmed[colon_idx + 1:trimmed.length()].trim().to_string(),
          imports,
          used_aliases,
          owner_name,
          owner_type_params,
        )
        let param_name = if idx == 0 && trimmed.has_prefix("Self") {
          "self"
        } else {
          sanitize_ts_identifier(name, "arg\{idx}")
        }
        params.push({ name: param_name, ty, optional: raw_name.has_suffix("?") })
      }
      None => {
        let ty = translate_mbti_type(
          trimmed, imports, used_aliases, owner_name, owner_type_params,
        )
        let param_name = if idx == 0 && trimmed.has_prefix("Self") {
          "self"
        } else {
          "arg\{idx}"
        }
        params.push({ name: param_name, ty, optional: false })
      }
    }
    idx += 1
  }
  params
}

///|
fn translate_named_type(
  name : String,
  type_args_src : String?,
  imports : Array[MbtiImportRef],
  used_aliases : Array[String],
  owner_name : String?,
  owner_type_params : Array[String],
) -> String raise MbtiTypescriptDeclError {
  let args = match type_args_src {
    Some(src) => {
      let normalized : Array[String] = []
      for arg in split_top_level_items(src) {
        normalized.push(
          translate_mbti_type(
            arg, imports, used_aliases, owner_name, owner_type_params,
          ),
        )
      }
      normalized
    }
    None => []
  }
  match name {
    "Unit" => "void"
    "Bool" => "boolean"
    "Byte"
    | "Char"
    | "Int"
    | "UInt"
    | "Int16"
    | "UInt16"
    | "Int32"
    | "UInt32"
    | "Int8"
    | "UInt8"
    | "Float"
    | "Double" => "number"
    "Int64" | "UInt64" => "bigint"
    "String" | "StringView" => "string"
    "Bytes" | "BytesView" => "Uint8Array"
    "Array" | "FixedArray" =>
      if args.length() == 1 {
        "Array<\{args[0]}>"
      } else {
        "Array<unknown>"
      }
    "ArrayView" | "ReadOnlyArray" =>
      if args.length() == 1 {
        "ReadonlyArray<\{args[0]}>"
      } else {
        "ReadonlyArray<unknown>"
      }
    "Map" =>
      if args.length() == 2 {
        "Map<\{args[0]}, \{args[1]}>"
      } else {
        "Map<unknown, unknown>"
      }
    "Set" => if args.length() == 1 { "Set<\{args[0]}>" } else { "Set<unknown>" }
    "Iter" =>
      if args.length() == 1 {
        "Iterable<\{args[0]}>"
      } else {
        "Iterable<unknown>"
      }
    "Ref" =>
      if args.length() == 1 {
        "{ val: \{args[0]} }"
      } else {
        "{ val: unknown }"
      }
    "Self" =>
      match owner_name {
        Some(type_name) =>
          if args.length() > 0 {
            let joined_args = args.join(", ")
            "\{type_name}<\{joined_args}>"
          } else if owner_type_params.length() > 0 {
            let joined_owner_params = owner_type_params.join(", ")
            "\{type_name}<\{joined_owner_params}>"
          } else {
            type_name
          }
        None => "Self"
      }
    _ =>
      if name.has_prefix("@") {
        match name.find(".") {
          Some(dot_idx) => {
            let alias_name = name[1:dot_idx].to_string()
            mbti_push_unique_string(used_aliases, alias_name)
            let ts_alias = lookup_import_ts_alias(imports, alias_name)
            let rest = name[dot_idx + 1:name.length()].to_string()
            if args.length() > 0 {
              let joined_args = args.join(", ")
              "\{ts_alias}.\{rest}<\{joined_args}>"
            } else {
              "\{ts_alias}.\{rest}"
            }
          }
          None => name
        }
      } else if args.length() > 0 {
        let joined_args = args.join(", ")
        "\{name}<\{joined_args}>"
      } else {
        name
      }
  }
}

///|
fn translate_mbti_type(
  source : String,
  imports : Array[MbtiImportRef],
  used_aliases : Array[String],
  owner_name : String?,
  owner_type_params : Array[String],
) -> String raise MbtiTypescriptDeclError {
  let trimmed = strip_mbti_top_level_effect(source)
  if trimmed == "" {
    return ""
  }
  if trimmed.has_prefix("&") {
    let borrowed_inner = trimmed[1:trimmed.length()].trim().to_string()
    return translate_mbti_type(
      borrowed_inner, imports, used_aliases, owner_name, owner_type_params,
    )
  }
  let (function_source, is_async_function) = if trimmed.has_prefix("async ") {
    (trimmed["async ".length():trimmed.length()].trim().to_string(), true)
  } else {
    (trimmed, false)
  }
  match find_top_level_arrow(function_source) {
    Some(arrow_idx) => {
      let left = function_source[:arrow_idx].trim().to_string()
      let right = function_source[arrow_idx + 2:function_source.length()]
        .trim()
        .to_string()
      let params_src = if left.has_prefix("(") && left.has_suffix(")") {
        left[1:left.length() - 1].to_string()
      } else {
        left
      }
      let params = parse_mbti_params(
        params_src, imports, used_aliases, owner_name, owner_type_params,
      )
      let rendered : Array[String] = []
      for param in params {
        rendered.push("\{param.name}: \{param.ty}")
      }
      let rendered_params = rendered.join(", ")
      let rendered_return = translate_mbti_type(
        right, imports, used_aliases, owner_name, owner_type_params,
      )
      let final_return = if is_async_function {
        "Promise<\{rendered_return}>"
      } else {
        rendered_return
      }
      return "(\{rendered_params}) => \{final_return}"
    }
    None => ()
  }
  if function_source.has_suffix("?") {
    let inner = function_source[:function_source.length() - 1]
      .trim()
      .to_string()
    let normalized_inner = translate_mbti_type(
      inner, imports, used_aliases, owner_name, owner_type_params,
    )
    if normalized_inner.contains("=>") {
      return "(\{normalized_inner}) | undefined"
    }
    return "\{normalized_inner} | undefined"
  }
  let trimmed = function_source
  if trimmed.has_prefix("(") && trimmed.has_suffix(")") {
    let inner = trimmed[1:trimmed.length() - 1].to_string()
    let items = split_top_level_items(inner)
    if items.length() > 1 {
      let rendered : Array[String] = []
      for item in items {
        rendered.push(
          translate_mbti_type(
            item, imports, used_aliases, owner_name, owner_type_params,
          ),
        )
      }
      let joined_items = rendered.join(", ")
      return "[\{joined_items}]"
    }
    return translate_mbti_type(
      inner, imports, used_aliases, owner_name, owner_type_params,
    )
  }
  match trimmed.find("[") {
    Some(idx) if trimmed.has_suffix("]") => {
      let name = trimmed[:idx].trim().to_string()
      let args_src = trimmed[idx + 1:trimmed.length() - 1].to_string()
      translate_named_type(
        name,
        Some(args_src),
        imports,
        used_aliases,
        owner_name,
        owner_type_params,
      )
    }
    _ =>
      translate_named_type(
        trimmed,
        None,
        imports,
        used_aliases,
        owner_name,
        owner_type_params,
      )
  }
}

///|
fn parse_mbti_function_signature(
  line : String,
  imports : Array[MbtiImportRef],
  used_aliases : Array[String],
) -> (String?, String, Array[MbtiTypeParam], String, String, Bool)? raise MbtiTypescriptDeclError {
  let trimmed = line.trim().to_string()
  let mut idx = 0
  let is_async = if trimmed.has_prefix("pub async fn") {
    idx = "pub async fn".length()
    true
  } else if trimmed.has_prefix("pub fn") && !trimmed.has_prefix("pub fn(") {
    idx = "pub fn".length()
    false
  } else {
    return None
  }
  let type_params : Array[MbtiTypeParam] = []
  if idx < trimmed.length() && mbti_char_at(trimmed, idx) == '[' {
    match find_matching(trimmed, idx, '[', ']') {
      Some(end_idx) => {
        let params_src = trimmed[idx + 1:end_idx].to_string()
        for param in parse_type_params(params_src, imports, used_aliases) {
          type_params.push(param)
        }
        idx = end_idx + 1
      }
      None => return None
    }
  }
  while idx < trimmed.length() && mbti_char_at(trimmed, idx) == ' ' {
    idx += 1
  }
  match trimmed.find("(") {
    Some(open_idx) if open_idx >= idx =>
      match find_matching(trimmed, open_idx, '(', ')') {
        Some(close_idx) => {
          let raw_name = trimmed[idx:open_idx].trim().to_string()
          let params_src = trimmed[open_idx + 1:close_idx].to_string()
          let rest = trimmed[close_idx + 1:trimmed.length()].trim().to_string()
          if !rest.has_prefix("->") {
            return None
          }
          let return_ty = strip_mbti_top_level_effect(
            rest[2:rest.length()].trim().to_string(),
          )
          match raw_name.find("::") {
            Some(sep_idx) =>
              Some(
                (
                  Some(raw_name[:sep_idx].to_string()),
                  raw_name[sep_idx + 2:raw_name.length()].to_string(),
                  type_params,
                  params_src,
                  return_ty,
                  is_async,
                ),
              )
            None =>
              Some(
                (None, raw_name, type_params, params_src, return_ty, is_async),
              )
          }
        }
        None => None
      }
    _ => None
  }
}

///|
fn parse_mbti_type_name_and_params(
  source : String,
  imports : Array[MbtiImportRef],
  used_aliases : Array[String],
) -> (String, Array[MbtiTypeParam])? raise MbtiTypescriptDeclError {
  let mut header = strip_mbti_derive_suffix(source)
  match header.find("{") {
    Some(open_idx) => header = header[:open_idx].trim().to_string()
    None => ()
  }
  match find_top_level_tuple_payload_open(header) {
    Some(open_idx) => header = header[:open_idx].trim().to_string()
    None => ()
  }
  if header == "" {
    return None
  }
  match header.find("[") {
    Some(idx) if header.has_suffix("]") => {
      let name = header[:idx].trim().to_string()
      let params = parse_type_params(
        header[idx + 1:header.length() - 1].to_string(),
        imports,
        used_aliases,
      )
      Some((name, params))
    }
    _ => Some((header, []))
  }
}

///|
fn parse_mbti_type_header(
  line : String,
  keyword : String,
  imports : Array[MbtiImportRef],
  used_aliases : Array[String],
) -> (String, Array[MbtiTypeParam])? raise MbtiTypescriptDeclError {
  match strip_mbti_public_prefix(line, keyword) {
    Some(rest) => parse_mbti_type_name_and_params(rest, imports, used_aliases)
    None => None
  }
}

///|
fn collect_brace_block(
  lines : Array[String],
  start : Int,
) -> (Array[String], Int) {
  let block : Array[String] = []
  let mut brace_depth = 0
  let mut seen_open = false
  let mut idx = start
  while idx < lines.length() {
    let line = lines[idx]
    block.push(line)
    let opens = mbti_count_char(line, '{')
    let closes = mbti_count_char(line, '}')
    brace_depth += opens - closes
    if opens > 0 {
      seen_open = true
    }
    idx += 1
    if seen_open && brace_depth <= 0 {
      break
    }
  }
  (block, idx)
}

///|
fn collect_mbti_decl_block(
  lines : Array[String],
  start : Int,
) -> (Array[String], Int) {
  if lines[start].contains("{") {
    collect_brace_block(lines, start)
  } else {
    ([lines[start]], start + 1)
  }
}

///|
fn parse_tuple_struct_fields(
  line : String,
  imports : Array[MbtiImportRef],
  used_aliases : Array[String],
  owner_name : String,
  owner_type_params : Array[String],
) -> Array[String]? raise MbtiTypescriptDeclError {
  let header = match strip_mbti_public_prefix(line, "struct") {
    Some(rest) => strip_mbti_derive_suffix(rest)
    None => return None
  }
  match find_top_level_tuple_payload_open(header) {
    Some(open_idx) =>
      match find_matching(header, open_idx, '(', ')') {
        Some(close_idx) => {
          let rest = header[close_idx + 1:header.length()].trim().to_string()
          if rest != "" {
            return None
          }
          let payload_src = header[open_idx + 1:close_idx].to_string()
          let fields = parse_variant_payload(
            payload_src, imports, used_aliases, owner_name, owner_type_params,
          )
          let field_lines : Array[String] = []
          for field in fields {
            field_lines.push("  \{field};")
          }
          Some(field_lines)
        }
        None => None
      }
    None => None
  }
}

///|
fn parse_struct_block_decl(
  lines : Array[String],
  imports : Array[MbtiImportRef],
  used_aliases : Array[String],
) -> MbtiStructDecl raise MbtiTypescriptDeclError {
  match parse_mbti_type_header(lines[0], "struct", imports, used_aliases) {
    Some(header) => {
      let (name, type_params) = header
      let owner_type_param_names = type_param_names(type_params)
      match
        parse_tuple_struct_fields(
          lines[0],
          imports,
          used_aliases,
          name,
          owner_type_param_names,
        ) {
        Some(fields) => return { name, type_params, fields }
        None => ()
      }
      let field_lines : Array[String] = []
      for idx in 1..<lines.length() {
        let trimmed = trim_trailing_comma_or_semicolon(
          lines[idx].trim().to_string(),
        )
        if trimmed == "" || trimmed == "}" {
          continue
        }
        if trimmed.has_prefix("}") {
          continue
        }
        match trimmed.find(":") {
          Some(colon_idx) => {
            let mut field_name = trimmed[:colon_idx].trim().to_string()
            if field_name.has_prefix("mut ") {
              field_name = field_name[4:field_name.length()].trim().to_string()
            }
            let field_ty = translate_mbti_type(
              trimmed[colon_idx + 1:trimmed.length()].trim().to_string(),
              imports,
              used_aliases,
              Some(name),
              owner_type_param_names,
            )
            let safe_field_name = sanitize_ts_identifier(field_name, "field")
            field_lines.push("  \{safe_field_name}: \{field_ty};")
          }
          None => ()
        }
      }
      { name, type_params, fields: field_lines }
    }
    None =>
      raise MbtiTypescriptDeclError::ParseError(
        "invalid struct block: \{lines[0]}",
      )
  }
}

///|
fn parse_variant_payload(
  payload_src : String,
  imports : Array[MbtiImportRef],
  used_aliases : Array[String],
  owner_name : String,
  owner_type_params : Array[String],
) -> Array[String] raise MbtiTypescriptDeclError {
  let fields : Array[String] = []
  let mut positional_index = 0
  for item in split_top_level_items(payload_src) {
    let trimmed = item.trim().to_string()
    if trimmed == "" {
      continue
    }
    match trimmed.find(":") {
      Some(colon_idx) => {
        let raw_name = trimmed[:colon_idx].trim().to_string()
        let field_name = if raw_name.has_suffix("~") {
          raw_name[:raw_name.length() - 1].trim().to_string()
        } else {
          raw_name
        }
        let field_ty = translate_mbti_type(
          trimmed[colon_idx + 1:trimmed.length()].trim().to_string(),
          imports,
          used_aliases,
          Some(owner_name),
          owner_type_params,
        )
        let safe_field_name = sanitize_ts_identifier(
          field_name,
          "field\{positional_index}",
        )
        fields.push("\{safe_field_name}: \{field_ty}")
      }
      None => {
        let field_ty = translate_mbti_type(
          trimmed,
          imports,
          used_aliases,
          Some(owner_name),
          owner_type_params,
        )
        fields.push("_\{positional_index}: \{field_ty}")
      }
    }
    positional_index += 1
  }
  fields
}

///|
fn parse_enum_like_block_decl(
  lines : Array[String],
  keyword : String,
  imports : Array[MbtiImportRef],
  used_aliases : Array[String],
) -> MbtiEnumLikeDecl raise MbtiTypescriptDeclError {
  match parse_mbti_type_header(lines[0], keyword, imports, used_aliases) {
    Some(header) => {
      let (name, type_params) = header
      let owner_type_param_names = type_param_names(type_params)
      let variants : Array[String] = []
      for idx in 1..<lines.length() {
        let trimmed = trim_trailing_comma_or_semicolon(
          lines[idx].trim().to_string(),
        )
        if trimmed == "" || trimmed == "}" || trimmed.has_prefix("}") {
          continue
        }
        match trimmed.find("(") {
          Some(open_idx) if trimmed.has_suffix(")") => {
            let variant_name = trimmed[:open_idx].trim().to_string()
            let payload_src = trimmed[open_idx + 1:trimmed.length() - 1].to_string()
            let fields = parse_variant_payload(
              payload_src, imports, used_aliases, name, owner_type_param_names,
            )
            if fields.length() == 0 {
              variants.push("{ $tag: \"\{variant_name}\" }")
            } else {
              let joined_fields = fields.join("; ")
              variants.push("{ $tag: \"\{variant_name}\"; \{joined_fields} }")
            }
          }
          _ => variants.push("{ $tag: \"\{trimmed}\" }")
        }
      }
      let joined_variants = variants.join(" | ")
      { name, type_params, union_body: joined_variants }
    }
    None =>
      raise MbtiTypescriptDeclError::ParseError(
        "invalid \{keyword} block: \{lines[0]}",
      )
  }
}

///|
fn parse_type_alias_decl_source(
  decl_source : String,
  original_line : String,
  imports : Array[MbtiImportRef],
  used_aliases : Array[String],
) -> MbtiTypeAliasDecl raise MbtiTypescriptDeclError {
  let decl_src = strip_mbti_derive_suffix(decl_source)
  match decl_src.find("=") {
    Some(eq_idx) => {
      let left = decl_src[:eq_idx].trim().to_string()
      let right = trim_trailing_comma_or_semicolon(
        decl_src[eq_idx + 1:decl_src.length()].trim().to_string(),
      )
      let (name, type_params) = match
        parse_mbti_type_name_and_params(left, imports, used_aliases) {
        Some(header) => header
        None =>
          raise MbtiTypescriptDeclError::ParseError(
            "invalid type alias: \{original_line}",
          )
      }
      let rendered = translate_mbti_type(right, imports, used_aliases, None, [])
      { name, type_params, body: rendered, is_opaque: false }
    }
    None =>
      match parse_mbti_type_name_and_params(decl_src, imports, used_aliases) {
        Some((name, type_params)) =>
          { name, type_params, body: "unknown", is_opaque: true }
        None =>
          raise MbtiTypescriptDeclError::ParseError(
            "invalid type alias: \{original_line}",
          )
      }
  }
}

///|
fn parse_type_alias_decl(
  line : String,
  imports : Array[MbtiImportRef],
  used_aliases : Array[String],
) -> MbtiTypeAliasDecl raise MbtiTypescriptDeclError {
  match strip_mbti_public_prefix(line, "type") {
    Some(rest) =>
      parse_type_alias_decl_source(rest, line, imports, used_aliases)
    None =>
      raise MbtiTypescriptDeclError::ParseError("invalid type alias: \{line}")
  }
}

///|
fn parse_private_type_alias_decl(
  line : String,
  imports : Array[MbtiImportRef],
  used_aliases : Array[String],
) -> MbtiTypeAliasDecl? raise MbtiTypescriptDeclError {
  let trimmed = line.trim().to_string()
  if !trimmed.has_prefix("type ") {
    return None
  }
  Some(
    parse_type_alias_decl_source(
      trimmed["type ".length():trimmed.length()].to_string(),
      line,
      imports,
      used_aliases,
    ),
  )
}

///|
fn parse_trait_block_decl(
  lines : Array[String],
  imports : Array[MbtiImportRef],
  used_aliases : Array[String],
) -> MbtiTraitDecl raise MbtiTypescriptDeclError {
  match parse_mbti_type_header(lines[0], "trait", imports, used_aliases) {
    Some(header) => {
      let (name, type_params) = header
      let owner_type_param_names = type_param_names(type_params)
      let methods : Array[String] = []
      for idx in 1..<lines.length() {
        let trimmed = trim_trailing_comma_or_semicolon(
          lines[idx].trim().to_string(),
        )
        if trimmed == "" || trimmed == "}" || trimmed.has_prefix("}") {
          continue
        }
        let synthetic_line = "pub fn \{name}::\{trimmed}"
        match
          parse_mbti_function_signature(synthetic_line, imports, used_aliases) {
          Some(signature) => {
            let (_, fn_name, type_params, params_src, return_src, is_async) = signature
            let params = parse_mbti_params(
              params_src,
              imports,
              used_aliases,
              Some(name),
              owner_type_param_names,
            )
            let instance_params : Array[MbtiParam] = []
            for param_idx in 0..<params.length() {
              let param = params[param_idx]
              if param_idx == 0 && param.name == "self" {
                continue
              }
              let normalized_name = if mbti_is_generated_param_name(param.name) {
                "arg\{instance_params.length()}"
              } else {
                param.name
              }
              instance_params.push({
                name: normalized_name,
                ty: param.ty,
                optional: param.optional,
              })
            }
            let method_type_params = filter_method_type_params(type_params, [])
            let type_param_suffix = render_type_param_suffix(method_type_params)
            let return_ty = translate_mbti_type(
              return_src,
              imports,
              used_aliases,
              Some(name),
              owner_type_param_names,
            )
            let rendered_return_ty = render_ts_return_type_with_effect(
              mbti_return_source_with_effect_from_function_line(synthetic_line),
              return_ty,
              is_async,
              imports,
              used_aliases,
              Some(name),
              owner_type_param_names,
            )
            let method_name = sanitize_ts_identifier(fn_name, "method")
            if instance_params.length() == 0 {
              methods.push(
                "\{method_name}\{type_param_suffix}: \{rendered_return_ty};",
              )
            } else {
              methods.push(
                "\{method_name}\{type_param_suffix}(\{render_ts_params(instance_params)}): \{rendered_return_ty};",
              )
            }
          }
          None => ()
        }
      }
      { name, type_params, methods }
    }
    None =>
      raise MbtiTypescriptDeclError::ParseError(
        "invalid trait block: \{lines[0]}",
      )
  }
}

///|
fn render_ts_params(params : Array[MbtiParam]) -> String {
  let rendered : Array[String] = []
  for param_idx in 0..<params.length() {
    let param = params[param_idx]
    let mut has_required_after = false
    for next_idx in (param_idx + 1)..<params.length() {
      if !params[next_idx].optional {
        has_required_after = true
        break
      }
    }
    if param.optional && has_required_after {
      let optional_ty = if contains_unqualified_type_name(param.ty, "undefined") {
        param.ty
      } else {
        let base_ty = if param.ty.contains("=>") {
          "(\{param.ty})"
        } else {
          param.ty
        }
        "\{base_ty} | undefined"
      }
      rendered.push("\{param.name}: \{optional_ty}")
    } else {
      let optional_suffix = if param.optional { "?" } else { "" }
      rendered.push("\{param.name}\{optional_suffix}: \{param.ty}")
    }
  }
  rendered.join(", ")
}

///|
fn render_ts_return_type(return_ty : String, is_async : Bool) -> String {
  if is_async {
    "Promise<\{return_ty}>"
  } else {
    return_ty
  }
}

///|
fn mbti_effect_error_ts_type(
  return_src_with_effect : String,
  imports : Array[MbtiImportRef],
  used_aliases : Array[String],
  owner_name : String?,
  owner_type_params : Array[String],
) -> String? raise MbtiTypescriptDeclError {
  let effect_suffix = mbti_top_level_effect_suffix(return_src_with_effect)
  if effect_suffix == "" || effect_suffix.has_prefix("noraise") {
    return None
  }
  if !effect_suffix.has_prefix("raise") {
    return None
  }
  let error_src = effect_suffix["raise".length():effect_suffix.length()]
    .trim()
    .to_string()
  if error_src == "" {
    Some("Error")
  } else {
    Some(
      translate_mbti_type(
        error_src, imports, used_aliases, owner_name, owner_type_params,
      ),
    )
  }
}

///|
fn render_ts_return_type_with_effect(
  return_src_with_effect : String,
  return_ty : String,
  is_async : Bool,
  imports : Array[MbtiImportRef],
  used_aliases : Array[String],
  owner_name : String?,
  owner_type_params : Array[String],
) -> String raise MbtiTypescriptDeclError {
  let effect_return_ty = match
    mbti_effect_error_ts_type(
      return_src_with_effect, imports, used_aliases, owner_name, owner_type_params,
    ) {
    Some(error_ty) => "Result<\{return_ty}, \{error_ty}>"
    None => return_ty
  }
  render_ts_return_type(effect_return_ty, is_async)
}

///|
fn struct_decl_has_field_name(
  struct_decl : MbtiStructDecl,
  field_name : String,
) -> Bool {
  let field_prefix = field_name + ":"
  let optional_field_prefix = field_name + "?:"
  for field_decl in struct_decl.fields {
    let trimmed = field_decl.trim().to_string()
    if trimmed.has_prefix(field_prefix) ||
      trimmed.has_prefix(optional_field_prefix) {
      return true
    }
  }
  false
}

///|
fn render_builtin_result_decl() -> String {
  "export type Result<T, E> = { $tag: \"Ok\"; _0: T } | { $tag: \"Err\"; _0: E };"
}

///|
fn is_ts_identifier_part(c : Char) -> Bool {
  mbti_is_ascii_letter(c) || mbti_is_ascii_digit(c) || c == '_' || c == '$'
}

///|
fn contains_unqualified_result_type_ref(source : String) -> Bool {
  let needle = "Result<"
  if source.length() < needle.length() {
    return false
  }
  for idx = 0; idx + needle.length() <= source.length(); idx = idx + 1 {
    if source[idx:idx + needle.length()].to_string() != needle {
      continue
    }
    if idx == 0 {
      return true
    }
    let prev = mbti_char_at(source, idx - 1)
    if !is_ts_identifier_part(prev) && prev != '.' {
      return true
    }
  }
  false
}

///|
fn contains_unqualified_type_name(source : String, type_name : String) -> Bool {
  if source.length() < type_name.length() {
    return false
  }
  for idx = 0; idx + type_name.length() <= source.length(); idx = idx + 1 {
    if source[idx:idx + type_name.length()].to_string() != type_name {
      continue
    }
    if idx > 0 {
      let prev = mbti_char_at(source, idx - 1)
      if is_ts_identifier_part(prev) || prev == '.' {
        continue
      }
    }
    let next_idx = idx + type_name.length()
    if next_idx < source.length() {
      let next = mbti_char_at(source, next_idx)
      if is_ts_identifier_part(next) {
        continue
      }
    }
    return true
  }
  false
}

///|
fn decls_reference_builtin_result(
  decls : Array[String],
  type_kinds : Map[String, String],
) -> Bool {
  match type_kinds.get("Result") {
    Some(_) => return false
    None => ()
  }
  for decl in decls {
    if contains_unqualified_result_type_ref(decl) {
      return true
    }
  }
  false
}

///|
fn render_builtin_json_decl() -> String {
  "export type Json = null | boolean | number | string | Array<Json> | { [key: string]: Json };"
}

///|
fn decls_reference_builtin_json(
  decls : Array[String],
  type_kinds : Map[String, String],
) -> Bool {
  match type_kinds.get("Json") {
    Some(_) => return false
    None => ()
  }
  for decl in decls {
    if contains_unqualified_type_name(decl, "Json") {
      return true
    }
  }
  false
}

///|
fn render_builtin_string_builder_decl() -> String {
  "export interface StringBuilder {\n}"
}

///|
fn decls_reference_builtin_string_builder(
  decls : Array[String],
  type_kinds : Map[String, String],
) -> Bool {
  match type_kinds.get("StringBuilder") {
    Some(_) => return false
    None => ()
  }
  for decl in decls {
    if contains_unqualified_type_name(decl, "StringBuilder") {
      return true
    }
  }
  false
}

///|
fn mbti_push_unique_ts_name(names : Array[String], name : String) -> Unit {
  if name != "" && !names.contains(name) {
    names.push(name)
  }
}

///|
fn compute_import_alias_rewrites(
  imports : Array[MbtiImportRef],
  used_aliases : Array[String],
  occupied_names : Array[String],
  rewrite_order : Array[String],
) -> Map[String, String] {
  let rewrites : Map[String, String] = {}
  let occupied : Array[String] = []
  for name in occupied_names {
    mbti_push_unique_ts_name(occupied, name)
  }
  for import_ref in imports {
    if !used_aliases.contains(import_ref.alias_name) {
      continue
    }
    let original_alias = import_ref.ts_alias
    let mut rewritten_alias = original_alias
    while occupied.contains(rewritten_alias) {
      rewritten_alias += "_"
    }
    mbti_push_unique_ts_name(occupied, rewritten_alias)
    if rewritten_alias != original_alias {
      rewrites[original_alias] = rewritten_alias
      rewrite_order.push(original_alias)
    }
  }
  rewrites
}

///|
fn rewrite_import_alias_refs(
  source : String,
  rewrites : Map[String, String],
  rewrite_order : Array[String],
) -> String {
  let mut rewritten = source
  for original_alias in rewrite_order {
    match rewrites.get(original_alias) {
      Some(rewritten_alias) =>
        rewritten = rewritten.replace(
          old=original_alias + ".",
          new=rewritten_alias + ".",
        )
      None => ()
    }
  }
  rewritten
}

///|
fn rewrite_mbti_glue_import_alias_refs(
  source : String,
  rewrites : Map[String, String],
) -> String {
  if source == "" {
    return source
  }
  let mut rewritten = ""
  let mut idx = 0
  while idx < source.length() {
    let c = mbti_char_at(source, idx)
    if c == '@' &&
      idx + 1 < source.length() &&
      mbti_is_identifier_start(mbti_char_at(source, idx + 1)) {
      let start = idx + 1
      let mut end_ = start + 1
      while end_ < source.length() &&
            mbti_is_identifier_continue(mbti_char_at(source, end_)) {
        end_ += 1
      }
      let alias_name = source[start:end_].to_string()
      match rewrites.get(alias_name) {
        Some(rewritten_alias) => rewritten += "@\{rewritten_alias}"
        None => rewritten += source[idx:end_].to_string()
      }
      idx = end_
    } else {
      rewritten += c.to_string()
      idx += 1
    }
  }
  rewritten
}

///|
fn is_builtin_ts_bound_name(name : String) -> Bool {
  match name {
    "Array"
    | "Date"
    | "Error"
    | "Iterable"
    | "Map"
    | "Promise"
    | "ReadonlyArray"
    | "Record"
    | "Set"
    | "Uint8Array"
    | "unknown"
    | "void"
    | "string"
    | "number"
    | "boolean"
    | "bigint" => true
    _ => false
  }
}

///|
fn is_unqualified_marker_bound_name(name : String) -> Bool {
  if !is_simple_ts_trait_name(name) || is_builtin_ts_bound_name(name) {
    return false
  }
  let first = name[0].unsafe_to_char()
  first >= 'A' && first <= 'Z'
}

///|
fn take_ts_extends_clause(source : String) -> String {
  let mut angle = 0
  let mut saw_angle = false
  for idx = 0; idx < source.length(); idx = idx + 1 {
    let c = mbti_char_at(source, idx)
    match c {
      '<' => {
        angle += 1
        saw_angle = true
      }
      '>' =>
        if angle > 0 {
          angle -= 1
        } else if !saw_angle {
          return source[:idx].trim().to_string()
        }
      '{' | '(' | ')' | ';' | '\n' if angle == 0 =>
        return source[:idx].trim().to_string()
      _ => ()
    }
  }
  source.trim().to_string()
}

///|
fn collect_marker_bounds_from_decl(
  decl : String,
  order : Array[String],
) -> Unit {
  let mut seen_prefix = false
  for part_view in decl.split(" extends ") {
    if !seen_prefix {
      seen_prefix = true
      continue
    }
    let clause = take_ts_extends_clause(part_view.to_string())
    for comma_part_view in clause.split(",") {
      let comma_part = comma_part_view.to_string()
      for amp_part_view in comma_part.split("&") {
        let name = amp_part_view.trim().to_string()
        if is_unqualified_marker_bound_name(name) {
          mbti_push_unique_ts_name(order, name)
        }
      }
    }
  }
}

///|
fn render_type_param_suffix(type_params : Array[MbtiTypeParam]) -> String {
  if type_params.length() > 0 {
    let rendered : Array[String] = []
    for type_param in type_params {
      match type_param.extends_ty {
        Some(extends_ty) =>
          rendered.push("\{type_param.name} extends \{extends_ty}")
        None => rendered.push(type_param.name)
      }
    }
    let joined_params = rendered.join(", ")
    "<\{joined_params}>"
  } else {
    ""
  }
}

///|
fn render_trait_refs(
  traits : Array[String],
  owner_name : String,
  type_param_suffix : String,
) -> Array[String] {
  let refs : Array[String] = []
  for trait_name in traits {
    if trait_name == "Show" {
      refs.push("Show")
    } else if trait_name == "Eq" {
      refs.push("Eq<\{owner_name}\{type_param_suffix}>")
    } else {
      refs.push(trait_name)
    }
  }
  refs
}

///|
fn render_type_alias_trait_suffix(
  traits : Array[String],
  owner_name : String,
  type_param_suffix : String,
) -> String {
  let parts = render_trait_refs(traits, owner_name, type_param_suffix)
  if parts.length() == 0 {
    ""
  } else {
    " & " + parts.join(" & ")
  }
}

///|
fn render_struct_decl(
  struct_decl : MbtiStructDecl,
  methods : Array[String],
  traits : Array[String],
) -> String {
  let type_param_suffix = render_type_param_suffix(struct_decl.type_params)
  let extends_items = render_trait_refs(
    traits,
    struct_decl.name,
    type_param_suffix,
  )
  let extends_suffix = if extends_items.length() > 0 {
    " extends " + extends_items.join(", ")
  } else {
    ""
  }
  let body_lines : Array[String] = []
  for field_decl in struct_decl.fields {
    body_lines.push(field_decl)
  }
  for method_decl in methods {
    body_lines.push("  " + method_decl)
  }
  let rendered_body = body_lines.join("\n")
  "export interface \{struct_decl.name}\{type_param_suffix}\{extends_suffix} {\n\{rendered_body}\n}"
}

///|
fn render_enum_like_decl(
  enum_decl : MbtiEnumLikeDecl,
  methods : Array[String],
  traits : Array[String],
) -> String {
  let type_param_suffix = render_type_param_suffix(enum_decl.type_params)
  let trait_suffix = render_type_alias_trait_suffix(
    traits,
    enum_decl.name,
    type_param_suffix,
  )
  if methods.length() == 0 {
    if trait_suffix != "" {
      return "export type \{enum_decl.name}\{type_param_suffix} = (\{enum_decl.union_body})\{trait_suffix};"
    }
    return "export type \{enum_decl.name}\{type_param_suffix} = \{enum_decl.union_body};"
  }
  let methods_name = "\{enum_decl.name}Methods"
  let body_lines : Array[String] = []
  for method_decl in methods {
    body_lines.push("  " + method_decl)
  }
  let rendered_body = body_lines.join("\n")
  "export interface \{methods_name}\{type_param_suffix} {\n\{rendered_body}\n}\n\nexport type \{enum_decl.name}\{type_param_suffix} = (\{enum_decl.union_body}) & \{methods_name}\{type_param_suffix}\{trait_suffix};"
}

///|
fn render_type_alias_decl(
  alias_decl : MbtiTypeAliasDecl,
  methods : Array[String],
  traits : Array[String],
) -> String {
  let type_param_suffix = render_type_param_suffix(alias_decl.type_params)
  if alias_decl.is_opaque {
    let extends_items = render_trait_refs(
      traits,
      alias_decl.name,
      type_param_suffix,
    )
    let extends_suffix = if extends_items.length() > 0 {
      " extends " + extends_items.join(", ")
    } else {
      ""
    }
    let body_lines : Array[String] = []
    for method_decl in methods {
      body_lines.push("  " + method_decl)
    }
    let rendered_body = body_lines.join("\n")
    return "export interface \{alias_decl.name}\{type_param_suffix}\{extends_suffix} {\n\{rendered_body}\n}"
  }
  let trait_suffix = render_type_alias_trait_suffix(
    traits,
    alias_decl.name,
    type_param_suffix,
  )
  if methods.length() == 0 {
    if trait_suffix != "" {
      return "export type \{alias_decl.name}\{type_param_suffix} = (\{alias_decl.body})\{trait_suffix};"
    }
    return "export type \{alias_decl.name}\{type_param_suffix} = \{alias_decl.body};"
  }
  let methods_name = "\{alias_decl.name}Methods"
  let body_lines : Array[String] = []
  for method_decl in methods {
    body_lines.push("  " + method_decl)
  }
  let rendered_body = body_lines.join("\n")
  "export interface \{methods_name}\{type_param_suffix} {\n\{rendered_body}\n}\n\nexport type \{alias_decl.name}\{type_param_suffix} = (\{alias_decl.body}) & \{methods_name}\{type_param_suffix}\{trait_suffix};"
}

///|
fn render_private_type_alias_decl(alias_decl : MbtiTypeAliasDecl) -> String {
  let type_param_suffix = render_type_param_suffix(alias_decl.type_params)
  if alias_decl.is_opaque {
    return "interface \{alias_decl.name}\{type_param_suffix} {\n}"
  }
  "type \{alias_decl.name}\{type_param_suffix} = \{alias_decl.body};"
}

///|
fn render_trait_decl(trait_decl : MbtiTraitDecl) -> String {
  let type_param_suffix = render_type_param_suffix(trait_decl.type_params)
  let body_lines : Array[String] = []
  for method_decl in trait_decl.methods {
    body_lines.push("  " + method_decl)
  }
  let rendered_body = body_lines.join("\n")
  "export interface \{trait_decl.name}\{type_param_suffix} {\n\{rendered_body}\n}"
}

///|
fn render_namespace_decl(name : String, members : Array[String]) -> String {
  let body_lines : Array[String] = []
  for member_decl in members {
    body_lines.push("  " + member_decl)
  }
  let rendered_body = body_lines.join("\n")
  "export namespace \{name} {\n\{rendered_body}\n}"
}

///|
fn parse_mbti_impl_decl(line : String) -> MbtiImplDecl? {
  let trimmed = match strip_mbti_impl_prefix(line) {
    Some(rest) => rest
    None => return None
  }
  match trimmed.find(" for ") {
    Some(for_idx) => {
      let trait_name = trimmed[:for_idx].trim().to_string()
      let owner_src = trimmed[for_idx + " for ".length():trimmed.length()]
        .trim()
        .to_string()
      let owner_name = match owner_src.find("[") {
        Some(idx) => owner_src[:idx].trim().to_string()
        None => owner_src
      }
      Some({ trait_name, owner_name })
    }
    None => None
  }
}

///|
fn parse_mbti_derive_trait_names(line : String) -> Array[String] {
  let traits : Array[String] = []
  match line.find("derive(") {
    Some(derive_idx) => {
      let open_idx = derive_idx + "derive".length()
      match find_matching(line, open_idx, '(', ')') {
        Some(close_idx) => {
          let inner = line[open_idx + 1:close_idx].to_string()
          for item in split_top_level_items(inner) {
            let trimmed = item.trim().to_string()
            if trimmed != "" {
              traits.push(trimmed)
            }
          }
        }
        None => ()
      }
    }
    None => ()
  }
  traits
}

///|
fn parse_local_marker_trait_decl(
  raw_trait_name : String,
) -> MbtiMarkerTraitDecl? {
  if raw_trait_name == "" ||
    raw_trait_name.has_prefix("@") ||
    raw_trait_name.contains(".") {
    return None
  }
  match raw_trait_name.find("[") {
    Some(idx) if raw_trait_name.has_suffix("]") => {
      let name = raw_trait_name[:idx].trim().to_string()
      if name == "" {
        return None
      }
      let args_src = raw_trait_name[idx + 1:raw_trait_name.length() - 1].to_string()
      let arity = split_top_level_items(args_src).length()
      Some({ name, arity })
    }
    _ => Some({ name: raw_trait_name, arity: 0 })
  }
}

///|
fn is_show_trait_name(name : String) -> Bool {
  name == "Show" || name.has_suffix(".Show")
}

///|
fn is_eq_trait_name(name : String) -> Bool {
  name == "Eq" || name.has_suffix(".Eq")
}

///|
fn is_ignored_trait_name(name : String) -> Bool {
  name == "@debug.Debug" || name == "debug.Debug"
}

///|
fn is_simple_ts_trait_name(name : String) -> Bool {
  if name == "" {
    return false
  }
  if name.contains(".") || name.contains("<") {
    return false
  }
  let first = name[0].unsafe_to_char()
  if !mbti_is_ascii_letter(first) && first != '_' && first != '$' {
    return false
  }
  for c in name {
    if !mbti_is_ascii_letter(c) &&
      !mbti_is_ascii_digit(c) &&
      c != '_' &&
      c != '$' {
      return false
    }
  }
  true
}

///|
fn render_marker_trait_decl(decl : MbtiMarkerTraitDecl) -> String {
  if decl.arity == 0 {
    return "export interface \{decl.name} {\n}"
  }
  let type_params : Array[String] = []
  for idx = 0; idx < decl.arity; idx = idx + 1 {
    type_params.push("T\{idx}")
  }
  let joined_type_params = type_params.join(", ")
  let suffix = "<\{joined_type_params}>"
  "export interface \{decl.name}\{suffix} {\n}"
}

///|
fn filter_method_type_params(
  type_params : Array[MbtiTypeParam],
  owner_type_params : Array[MbtiTypeParam],
) -> Array[MbtiTypeParam] {
  let owner_param_names = type_param_names(owner_type_params)
  let filtered : Array[MbtiTypeParam] = []
  for type_param in type_params {
    if !owner_param_names.contains(type_param.name) {
      filtered.push(type_param)
    }
  }
  filtered
}

///|
fn parse_mbti_to_typescript_with_import_rewrites(
  source : String,
  import_spec_rewrites : Map[String, String],
) -> String raise MbtiTypescriptDeclError {
  let imports = parse_mbti_imports(source)
  let used_aliases : Array[String] = []
  let top_level_decls : Array[String] = []
  let top_level_export_names : Array[String] = []
  let type_order : Array[String] = []
  let type_kinds : Map[String, String] = {}
  let type_params_by_name : Map[String, Array[MbtiTypeParam]] = {}
  let struct_decls : Map[String, MbtiStructDecl] = {}
  let enum_like_decls : Map[String, MbtiEnumLikeDecl] = {}
  let type_alias_decls : Map[String, MbtiTypeAliasDecl] = {}
  let private_type_order : Array[String] = []
  let private_type_alias_decls : Map[String, MbtiTypeAliasDecl] = {}
  let trait_order : Array[String] = []
  let trait_decls : Map[String, MbtiTraitDecl] = {}
  let struct_method_decls : Map[String, Array[String]] = {}
  let enum_method_decls : Map[String, Array[String]] = {}
  let alias_method_decls : Map[String, Array[String]] = {}
  let struct_traits : Map[String, Array[String]] = {}
  let enum_traits : Map[String, Array[String]] = {}
  let alias_traits : Map[String, Array[String]] = {}
  let mut has_show_trait = false
  let mut has_eq_trait = false
  let marker_trait_order : Array[String] = []
  let marker_trait_decls : Map[String, MbtiMarkerTraitDecl] = {}
  let namespace_member_decls : Map[String, Array[String]] = {}
  let function_decls : Array[MbtiFunctionDecl] = []
  let impl_decls : Array[MbtiImplDecl] = []
  let lines : Array[String] = []
  for line in source.split("\n") {
    lines.push(line.to_string())
  }
  let mut idx = 0
  while idx < lines.length() {
    let line = lines[idx]
    let trimmed = line.trim().to_string()
    if trimmed == "" || trimmed.has_prefix("//") {
      idx += 1
      continue
    }
    if trimmed.has_prefix("pub struct ") ||
      trimmed.has_prefix("pub(all) struct ") {
      let (block, next_idx) = collect_mbti_decl_block(lines, idx)
      let struct_decl = parse_struct_block_decl(block, imports, used_aliases)
      match parse_mbti_type_header(trimmed, "struct", imports, used_aliases) {
        Some(header) => {
          let (name, _) = header
          type_order.push(name)
          type_kinds[name] = "struct"
          type_params_by_name[name] = struct_decl.type_params
          struct_decls[name] = struct_decl
          for derive_line in block {
            for trait_name in parse_mbti_derive_trait_names(derive_line) {
              impl_decls.push({ trait_name, owner_name: name })
            }
          }
        }
        None => ()
      }
      idx = next_idx
      continue
    }
    if trimmed.has_prefix("pub enum ") || trimmed.has_prefix("pub(all) enum ") {
      let (block, next_idx) = collect_brace_block(lines, idx)
      let enum_decl = parse_enum_like_block_decl(
        block, "enum", imports, used_aliases,
      )
      match parse_mbti_type_header(trimmed, "enum", imports, used_aliases) {
        Some(header) => {
          let (name, type_params) = header
          type_order.push(name)
          type_kinds[name] = "enum"
          type_params_by_name[name] = type_params
          enum_like_decls[name] = enum_decl
          for derive_line in block {
            for trait_name in parse_mbti_derive_trait_names(derive_line) {
              impl_decls.push({ trait_name, owner_name: name })
            }
          }
        }
        None => ()
      }
      idx = next_idx
      continue
    }
    if trimmed.has_prefix("pub suberror ") ||
      trimmed.has_prefix("pub(all) suberror ") {
      let (block, next_idx) = collect_brace_block(lines, idx)
      let enum_decl = parse_enum_like_block_decl(
        block, "suberror", imports, used_aliases,
      )
      match parse_mbti_type_header(trimmed, "suberror", imports, used_aliases) {
        Some(header) => {
          let (name, type_params) = header
          type_order.push(name)
          type_kinds[name] = "suberror"
          type_params_by_name[name] = type_params
          enum_like_decls[name] = enum_decl
          for derive_line in block {
            for trait_name in parse_mbti_derive_trait_names(derive_line) {
              impl_decls.push({ trait_name, owner_name: name })
            }
          }
        }
        None => ()
      }
      idx = next_idx
      continue
    }
    if trimmed.has_prefix("pub type ") || trimmed.has_prefix("pub(all) type ") {
      let alias_decl = parse_type_alias_decl(trimmed, imports, used_aliases)
      let name = alias_decl.name
      type_order.push(name)
      type_kinds[name] = "type"
      type_params_by_name[name] = alias_decl.type_params
      type_alias_decls[name] = alias_decl
      for trait_name in parse_mbti_derive_trait_names(trimmed) {
        impl_decls.push({ trait_name, owner_name: name })
      }
      idx += 1
      continue
    }
    if trimmed.has_prefix("type ") {
      match parse_private_type_alias_decl(trimmed, imports, used_aliases) {
        Some(alias_decl) => {
          let name = alias_decl.name
          if !private_type_order.contains(name) {
            private_type_order.push(name)
          }
          private_type_alias_decls[name] = alias_decl
        }
        None => ()
      }
      idx += 1
      continue
    }
    if trimmed.has_prefix("pub trait ") ||
      trimmed.has_prefix("pub(all) trait ") ||
      trimmed.has_prefix("pub(open) trait ") {
      let (block, next_idx) = collect_brace_block(lines, idx)
      let trait_decl = parse_trait_block_decl(block, imports, used_aliases)
      if !trait_order.contains(trait_decl.name) {
        trait_order.push(trait_decl.name)
      }
      trait_decls[trait_decl.name] = trait_decl
      idx = next_idx
      continue
    }
    if trimmed.has_prefix("pub fn") || trimmed.has_prefix("pub async fn") {
      match parse_mbti_function_signature(trimmed, imports, used_aliases) {
        Some(signature) => {
          let (
            owner_name,
            fn_name,
            type_params,
            params_src,
            return_src,
            is_async,
          ) = signature
          function_decls.push({
            owner_name,
            fn_name,
            type_params,
            params_src,
            return_src,
            return_src_with_effect: mbti_return_source_with_effect_from_function_line(
              trimmed,
            ),
            is_async,
          })
          idx += 1
          continue
        }
        None => ()
      }
    }
    if trimmed.has_prefix("pub impl") {
      match parse_mbti_impl_decl(trimmed) {
        Some(impl_decl) => impl_decls.push(impl_decl)
        None => ()
      }
      idx += 1
      continue
    }
    idx += 1
  }
  for function_decl in function_decls {
    match function_decl.owner_name {
      Some(owner) =>
        match type_kinds.get(owner) {
          Some(kind) => {
            let owner_type_params = match type_params_by_name.get(owner) {
              Some(params) => params
              None => []
            }
            let owner_type_param_names = type_param_names(owner_type_params)
            let params = parse_mbti_params(
              function_decl.params_src,
              imports,
              used_aliases,
              Some(owner),
              owner_type_param_names,
            )
            let return_ty = translate_mbti_type(
              function_decl.return_src,
              imports,
              used_aliases,
              Some(owner),
              owner_type_param_names,
            )
            let rendered_return_ty = render_ts_return_type_with_effect(
              function_decl.return_src_with_effect,
              return_ty,
              function_decl.is_async,
              imports,
              used_aliases,
              Some(owner),
              owner_type_param_names,
            )
            let member_name = sanitize_ts_identifier(
              function_decl.fn_name,
              "method",
            )
            let member_name = if kind == "struct" {
              match struct_decls.get(owner) {
                Some(struct_decl) =>
                  if struct_decl_has_field_name(struct_decl, member_name) {
                    member_name + "_"
                  } else {
                    member_name
                  }
                None => member_name
              }
            } else {
              member_name
            }
            if (
                kind == "struct" ||
                kind == "enum" ||
                kind == "suberror" ||
                kind == "type"
              ) &&
              params.length() > 0 &&
              params[0].name == "self" {
              let instance_params : Array[MbtiParam] = []
              for idx in 1..<params.length() {
                let param = params[idx]
                let normalized_name = if mbti_is_generated_param_name(
                    param.name,
                  ) {
                  "arg\{idx - 1}"
                } else {
                  param.name
                }
                instance_params.push({
                  name: normalized_name,
                  ty: param.ty,
                  optional: param.optional,
                })
              }
              let method_type_params = filter_method_type_params(
                function_decl.type_params,
                owner_type_params,
              )
              let type_param_suffix = render_type_param_suffix(
                method_type_params,
              )
              let rendered_params = render_ts_params(instance_params)
              let member_decl = "\{member_name}\{type_param_suffix}(\{rendered_params}): \{rendered_return_ty};"
              if kind == "struct" {
                match struct_method_decls.get(owner) {
                  Some(methods) => methods.push(member_decl)
                  None => struct_method_decls[owner] = [member_decl]
                }
              } else if kind == "enum" || kind == "suberror" {
                match enum_method_decls.get(owner) {
                  Some(methods) => methods.push(member_decl)
                  None => enum_method_decls[owner] = [member_decl]
                }
              } else {
                match alias_method_decls.get(owner) {
                  Some(methods) => methods.push(member_decl)
                  None => alias_method_decls[owner] = [member_decl]
                }
              }
            } else {
              let type_param_suffix = render_type_param_suffix(
                function_decl.type_params,
              )
              let rendered_params = render_ts_params(params)
              let member_decl = "function \{member_name}\{type_param_suffix}(\{rendered_params}): \{rendered_return_ty};"
              match namespace_member_decls.get(owner) {
                Some(methods) => methods.push(member_decl)
                None => namespace_member_decls[owner] = [member_decl]
              }
            }
          }
          None => ()
        }
      None => {
        let params = parse_mbti_params(
          function_decl.params_src,
          imports,
          used_aliases,
          None,
          [],
        )
        let return_ty = translate_mbti_type(
          function_decl.return_src,
          imports,
          used_aliases,
          None,
          [],
        )
        let rendered_return_ty = render_ts_return_type_with_effect(
          function_decl.return_src_with_effect,
          return_ty,
          function_decl.is_async,
          imports,
          used_aliases,
          None,
          [],
        )
        let fn_type_params = render_type_param_suffix(function_decl.type_params)
        let safe_fn_name = sanitize_ts_identifier(function_decl.fn_name, "fn")
        let rendered_params = render_ts_params(params)
        mbti_push_unique_ts_name(top_level_export_names, safe_fn_name)
        top_level_decls.push(
          "export function \{safe_fn_name}\{fn_type_params}(\{rendered_params}): \{rendered_return_ty};",
        )
      }
    }
  }
  for impl_decl in impl_decls {
    let normalized_trait = if is_show_trait_name(impl_decl.trait_name) {
      has_show_trait = true
      Some("Show")
    } else if is_eq_trait_name(impl_decl.trait_name) {
      has_eq_trait = true
      Some("Eq")
    } else if is_ignored_trait_name(impl_decl.trait_name) {
      None
    } else {
      match parse_local_marker_trait_decl(impl_decl.trait_name) {
        Some(marker_trait_decl) =>
          upsert_marker_trait_decl(
            marker_trait_decls,
            marker_trait_order,
            marker_trait_decl.name,
            marker_trait_decl.arity,
          )
        None => ()
      }
      let owner_type_params = match
        type_params_by_name.get(impl_decl.owner_name) {
        Some(params) => params
        None => []
      }
      let owner_type_param_names = type_param_names(owner_type_params)
      let rendered_trait = translate_mbti_type(
        impl_decl.trait_name,
        imports,
        used_aliases,
        Some(impl_decl.owner_name),
        owner_type_param_names,
      )
      if is_ignored_trait_name(rendered_trait) {
        None
      } else {
        if is_simple_ts_trait_name(rendered_trait) {
          match parse_local_marker_trait_decl(rendered_trait) {
            Some(marker_trait_decl) =>
              upsert_marker_trait_decl(
                marker_trait_decls,
                marker_trait_order,
                marker_trait_decl.name,
                marker_trait_decl.arity,
              )
            None => ()
          }
        }
        Some(rendered_trait)
      }
    }
    match normalized_trait {
      Some(trait_name) =>
        match type_kinds.get(impl_decl.owner_name) {
          Some("struct") =>
            match struct_traits.get(impl_decl.owner_name) {
              Some(traits) =>
                if !traits.contains(trait_name) {
                  traits.push(trait_name)
                }
              None => struct_traits[impl_decl.owner_name] = [trait_name]
            }
          Some("enum") | Some("suberror") =>
            match enum_traits.get(impl_decl.owner_name) {
              Some(traits) =>
                if !traits.contains(trait_name) {
                  traits.push(trait_name)
                }
              None => enum_traits[impl_decl.owner_name] = [trait_name]
            }
          Some("type") =>
            match alias_traits.get(impl_decl.owner_name) {
              Some(traits) =>
                if !traits.contains(trait_name) {
                  traits.push(trait_name)
                }
              None => alias_traits[impl_decl.owner_name] = [trait_name]
            }
          _ => ()
        }
      None => ()
    }
  }
  let decls : Array[String] = []
  if has_show_trait {
    decls.push("export interface Show {\n  toString(): string;\n}")
  }
  if has_eq_trait {
    decls.push("export interface Eq<T> {\n  equals(other: T): boolean;\n}")
  }
  for trait_name in trait_order {
    match trait_decls.get(trait_name) {
      Some(trait_decl) => decls.push(render_trait_decl(trait_decl))
      None => ()
    }
  }
  for marker_trait_name in marker_trait_order {
    match trait_decls.get(marker_trait_name) {
      Some(_) => ()
      None =>
        match marker_trait_decls.get(marker_trait_name) {
          Some(marker_trait_decl) =>
            decls.push(render_marker_trait_decl(marker_trait_decl))
          None => ()
        }
    }
  }
  for type_name in private_type_order {
    match private_type_alias_decls.get(type_name) {
      Some(alias_decl) => decls.push(render_private_type_alias_decl(alias_decl))
      None => ()
    }
  }
  for decl in top_level_decls {
    decls.push(decl)
  }
  for type_name in type_order {
    match type_kinds.get(type_name) {
      Some("struct") =>
        match struct_decls.get(type_name) {
          Some(struct_decl) => {
            let struct_methods = match struct_method_decls.get(type_name) {
              Some(methods) => methods
              None => []
            }
            let traits = match struct_traits.get(type_name) {
              Some(items) => items
              None => []
            }
            decls.push(render_struct_decl(struct_decl, struct_methods, traits))
          }
          None => ()
        }
      Some("enum") | Some("suberror") =>
        match enum_like_decls.get(type_name) {
          Some(enum_decl) => {
            let enum_methods = match enum_method_decls.get(type_name) {
              Some(methods) => methods
              None => []
            }
            let traits = match enum_traits.get(type_name) {
              Some(items) => items
              None => []
            }
            decls.push(render_enum_like_decl(enum_decl, enum_methods, traits))
          }
          None => ()
        }
      Some("type") =>
        match type_alias_decls.get(type_name) {
          Some(alias_decl) => {
            let alias_methods = match alias_method_decls.get(type_name) {
              Some(methods) => methods
              None => []
            }
            let traits = match alias_traits.get(type_name) {
              Some(items) => items
              None => []
            }
            decls.push(
              render_type_alias_decl(alias_decl, alias_methods, traits),
            )
          }
          None => ()
        }
      Some(_) =>
        match type_alias_decls.get(type_name) {
          Some(alias_decl) => {
            let traits = match alias_traits.get(type_name) {
              Some(items) => items
              None => []
            }
            decls.push(render_type_alias_decl(alias_decl, [], traits))
          }
          None => ()
        }
      None => ()
    }
    match namespace_member_decls.get(type_name) {
      Some(members) if members.length() > 0 =>
        decls.push(render_namespace_decl(type_name, members))
      _ => ()
    }
  }
  let bound_marker_order : Array[String] = []
  for decl in decls {
    collect_marker_bounds_from_decl(decl, bound_marker_order)
  }
  let final_decls : Array[String] = []
  if decls_reference_builtin_result(decls, type_kinds) {
    final_decls.push(render_builtin_result_decl())
  }
  if decls_reference_builtin_json(decls, type_kinds) {
    final_decls.push(render_builtin_json_decl())
  }
  if decls_reference_builtin_string_builder(decls, type_kinds) {
    final_decls.push(render_builtin_string_builder_decl())
  }
  for marker_name in bound_marker_order {
    if marker_name == "Show" {
      if !has_show_trait {
        final_decls.push("export interface Show {\n}")
      }
    } else if marker_name == "Eq" {
      if !has_eq_trait {
        final_decls.push("export interface Eq {\n}")
      }
    } else if !marker_trait_order.contains(marker_name) &&
      !trait_order.contains(marker_name) {
      final_decls.push("export interface \{marker_name} {\n}")
    }
  }
  for decl in decls {
    final_decls.push(decl)
  }
  let occupied_import_names : Array[String] = []
  for type_name in type_order {
    mbti_push_unique_ts_name(occupied_import_names, type_name)
  }
  for type_name in private_type_order {
    mbti_push_unique_ts_name(occupied_import_names, type_name)
  }
  for fn_name in top_level_export_names {
    mbti_push_unique_ts_name(occupied_import_names, fn_name)
  }
  if has_show_trait {
    mbti_push_unique_ts_name(occupied_import_names, "Show")
  }
  if has_eq_trait {
    mbti_push_unique_ts_name(occupied_import_names, "Eq")
  }
  for marker_trait_name in marker_trait_order {
    mbti_push_unique_ts_name(occupied_import_names, marker_trait_name)
  }
  for trait_name in trait_order {
    mbti_push_unique_ts_name(occupied_import_names, trait_name)
  }
  for marker_name in bound_marker_order {
    mbti_push_unique_ts_name(occupied_import_names, marker_name)
  }
  let used_import_refs = collect_used_import_refs(imports, used_aliases)
  let import_alias_rewrite_order : Array[String] = []
  let import_alias_rewrites = compute_import_alias_rewrites(
    used_import_refs, used_aliases, occupied_import_names, import_alias_rewrite_order,
  )
  let rendered_decls : Array[String] = []
  for decl in final_decls {
    rendered_decls.push(
      rewrite_import_alias_refs(
        decl, import_alias_rewrites, import_alias_rewrite_order,
      ),
    )
  }
  let import_lines : Array[String] = []
  for import_ref in used_import_refs {
    let import_spec = match import_spec_rewrites.get(import_ref.module_spec) {
      Some(rewritten) => rewritten
      None => import_ref.module_spec
    }
    let ts_alias = match import_alias_rewrites.get(import_ref.ts_alias) {
      Some(rewritten) => rewritten
      None => import_ref.ts_alias
    }
    import_lines.push("import type * as \{ts_alias} from \"\{import_spec}\";")
  }
  import_lines.sort()
  let all_parts : Array[String] = []
  if import_lines.length() > 0 {
    all_parts.push(import_lines.join("\n"))
  }
  if rendered_decls.length() > 0 {
    all_parts.push(rendered_decls.join("\n\n"))
  }
  all_parts.join("\n\n")
}

///|
fn parse_mbti_to_typescript(
  source : String,
) -> String raise MbtiTypescriptDeclError {
  parse_mbti_to_typescript_with_import_rewrites(source, {})
}

///|
pub async fn emit_typescript_package_bundle_from_mbti_path(
  root_file_path : String,
) -> Array[MbtiTypescriptPackageFile] raise MbtiTypescriptDeclError {
  emit_typescript_package_bundle_from_mbti_path_with_import_rewrites(
    root_file_path,
    {},
  )
}

///|
pub async fn emit_typescript_package_bundle_from_mbti_path_with_import_rewrites(
  root_file_path : String,
  external_import_spec_rewrites : Map[String, String],
) -> Array[MbtiTypescriptPackageFile] raise MbtiTypescriptDeclError {
  let loaded = load_mbti_package_sources(root_file_path)
  let root_package_name = loaded.root_package_name
  let ordered_packages = loaded.ordered_packages
  let package_sources = loaded.package_sources
  let files : Array[MbtiTypescriptPackageFile] = []
  for package_name in ordered_packages {
    let source = match package_sources.get(package_name) {
      Some(source) => source
      None =>
        raise MbtiTypescriptDeclError::ParseError(
          "missing emitted package source for \{package_name}",
        )
    }
    let current_segments = match
      mbti_local_package_segments(root_package_name, package_name) {
      Some(segments) => segments
      None =>
        raise MbtiTypescriptDeclError::ParseError(
          "package \{package_name} is outside root bundle \{root_package_name}",
        )
    }
    let import_rewrites : Map[String, String] = {}
    for pair in external_import_spec_rewrites {
      let (module_spec, rewritten_spec) = pair
      import_rewrites[module_spec] = rewritten_spec
    }
    for target_package_name in ordered_packages {
      if target_package_name == package_name {
        continue
      }
      match
        mbti_local_package_segments(root_package_name, target_package_name) {
        Some(target_segments) =>
          import_rewrites[target_package_name] = mbti_relative_package_import_spec(
            current_segments, target_segments,
          )
        None => ()
      }
    }
    for import_ref in parse_mbti_imports(source) {
      if import_ref.module_spec == package_name {
        continue
      }
      match
        mbti_local_package_segments(root_package_name, import_ref.module_spec) {
        Some(target_segments) =>
          import_rewrites[import_ref.module_spec] = mbti_relative_package_import_spec(
            current_segments, target_segments,
          )
        None => ()
      }
    }
    files.push({
      relative_path: mbti_bundle_relative_path_from_segments(current_segments),
      content: parse_mbti_to_typescript_with_import_rewrites(
        source, import_rewrites,
      ),
    })
  }
  files
}

///|
fn ts_decl_line_is_runtime_inaccessible_method(line : String) -> Bool {
  let trimmed = line.trim().to_string()
  match trimmed.find("(") {
    Some(paren_idx) => {
      let before = trimmed[:paren_idx].to_string()
      !before.contains(":") && trimmed.has_suffix(";")
    }
    None => false
  }
}

///|
fn ts_decl_line_is_runtime_inaccessible_function(line : String) -> Bool {
  let trimmed = line.trim().to_string()
  if !trimmed.has_prefix("export function ") {
    return false
  }
  match trimmed.find("(") {
    Some(paren_idx) => {
      let before = trimmed[:paren_idx].to_string()
      before.contains("<") && before.contains(">")
    }
    None => false
  }
}

///|
fn ts_decl_export_function_name(line : String) -> String? {
  let trimmed = line.trim().to_string()
  let prefix = "export function "
  if !trimmed.has_prefix(prefix) {
    return None
  }
  let rest = trimmed[prefix.length():trimmed.length()].to_string()
  let mut end_idx = rest.length()
  match rest.find("(") {
    Some(idx) => end_idx = idx
    None => ()
  }
  match rest.find("<") {
    Some(idx) if idx < end_idx => end_idx = idx
    _ => ()
  }
  let name = rest[:end_idx].trim().to_string()
  if name == "" {
    None
  } else {
    Some(name)
  }
}

///|
fn strip_runtime_inaccessible_typescript_members(
  source : String,
  inaccessible_function_names : Array[String],
) -> String {
  let lines : Array[String] = []
  let mut in_interface = false
  let mut in_namespace = false
  for line_view in source.split("\n") {
    let line = line_view.to_string()
    let trimmed = line.trim().to_string()
    if in_namespace {
      if trimmed == "}" {
        in_namespace = false
      }
      continue
    }
    if trimmed.has_prefix("export namespace ") && trimmed.has_suffix("{") {
      in_namespace = true
      continue
    }
    if in_interface {
      if trimmed == "}" {
        in_interface = false
        lines.push(line)
        continue
      }
      if ts_decl_line_is_runtime_inaccessible_method(line) {
        continue
      }
      lines.push(line)
      continue
    }
    if trimmed.has_prefix("export interface ") && trimmed.has_suffix("{") {
      in_interface = true
    }
    match ts_decl_export_function_name(line) {
      Some(name) if inaccessible_function_names.contains(name) => continue
      _ => ()
    }
    if ts_decl_line_is_runtime_inaccessible_function(line) {
      continue
    }
    lines.push(line)
  }
  lines.join("\n")
}

///|
fn strip_runtime_inaccessible_typescript_package_files(
  loaded : LoadedMbtiPackageSources,
  files : Array[MbtiTypescriptPackageFile],
) -> Array[MbtiTypescriptPackageFile] {
  let inaccessible_by_path : Map[String, Array[String]] = {}
  for package_name in loaded.ordered_packages {
    let source = match loaded.package_sources.get(package_name) {
      Some(source) => source
      None => continue
    }
    let segments = match
      mbti_local_package_segments(loaded.root_package_name, package_name) {
      Some(segments) => segments
      None => continue
    }
    inaccessible_by_path[mbti_bundle_relative_path_from_segments(segments)] = collect_runtime_inaccessible_free_function_names(
      source,
    )
  }
  let stripped : Array[MbtiTypescriptPackageFile] = []
  for file in files {
    let inaccessible_function_names = match
      inaccessible_by_path.get(file.relative_path) {
      Some(names) => names
      None => []
    }
    stripped.push({
      relative_path: file.relative_path,
      content: strip_runtime_inaccessible_typescript_members(
        file.content,
        inaccessible_function_names,
      ),
    })
  }
  stripped
}

///|
fn mbti_bundle_js_relative_path_from_segments(
  segments : Array[String],
) -> String {
  if segments.length() == 0 {
    "index.js"
  } else {
    segments.join("/") + "/index.js"
  }
}

///|
fn mbti_runtime_root_import_from_segments(segments : Array[String]) -> String {
  if segments.length() == 0 {
    "./index.js"
  } else {
    let parts : Array[String] = []
    for _ in 0..<segments.length() {
      parts.push("..")
    }
    parts.join("/") + "/index.js"
  }
}

///|
fn render_runtime_reexport_js(
  export_items : Array[String],
  root_import : String,
) -> String {
  if export_items.length() == 0 {
    return "export {};\n"
  }
  let lines : Array[String] = [
    "import * as __tsmbtRoot from \"\{root_import}\";",
  ]
  for item in export_items {
    match item.find(" as ") {
      Some(alias_idx) => {
        let runtime_name = item[:alias_idx].trim().to_string()
        let export_name = item[alias_idx + 4:item.length()].trim().to_string()
        lines.push("export const \{export_name} = __tsmbtRoot.\{runtime_name};")
      }
      None => lines.push("export const \{item} = __tsmbtRoot.\{item};")
    }
  }
  lines.join("\n") + "\n"
}

///|
fn collect_runtime_reexport_files_for_mbti_bundle(
  root_package_name : String,
  ordered_packages : Array[String],
  glue_decls : Array[MbtiAutolinkGlueDecl],
) -> Array[MbtiTypescriptPackageFile] {
  let files : Array[MbtiTypescriptPackageFile] = []
  for package_name in ordered_packages {
    if package_name == root_package_name {
      continue
    }
    let segments = match
      mbti_local_package_segments(root_package_name, package_name) {
      Some(segments) => segments
      None => continue
    }
    let export_items : Array[String] = []
    let seen_export_names : Array[String] = []
    for decl in glue_decls {
      if decl.package_name == package_name &&
        !seen_export_names.contains(decl.export_name) {
        seen_export_names.push(decl.export_name)
        if decl.runtime_export_name == decl.export_name {
          export_items.push(decl.export_name)
        } else {
          export_items.push(
            "\{decl.runtime_export_name} as \{decl.export_name}",
          )
        }
      }
    }
    if export_items.length() == 0 {
      continue
    }
    sort_strings_ascending(export_items)
    files.push({
      relative_path: mbti_bundle_js_relative_path_from_segments(segments),
      content: render_runtime_reexport_js(
        export_items,
        mbti_runtime_root_import_from_segments(segments),
      ),
    })
  }
  files.sort_by(fn(lhs, rhs) {
    mbti_compare_string_ascending(lhs.relative_path, rhs.relative_path)
  })
  files
}

///|
pub async fn emit_typescript_scaffold_bundle_from_mbti_path(
  root_file_path : String,
) -> MbtiTypescriptScaffoldBundle raise MbtiTypescriptDeclError {
  emit_typescript_scaffold_bundle_from_mbti_path_with_import_rewrites(
    root_file_path,
    {},
  )
}

///|
pub async fn emit_typescript_scaffold_bundle_from_mbti_path_with_import_rewrites(
  root_file_path : String,
  external_import_spec_rewrites : Map[String, String],
) -> MbtiTypescriptScaffoldBundle raise MbtiTypescriptDeclError {
  let loaded = load_mbti_package_sources(root_file_path)
  let root_package_name = loaded.root_package_name
  let glue_decls = collect_mbti_bundle_autolink_glue_decls(loaded, false)
  let export_names : Array[String] = []
  for decl in glue_decls {
    export_names.push(decl.runtime_export_name)
  }
  let moon_pkg_json = render_moonbit_js_glue_pkg_json(loaded, export_names)
  let files = strip_runtime_inaccessible_typescript_package_files(
    loaded,
    emit_typescript_package_bundle_from_mbti_path_with_import_rewrites(
      root_file_path, external_import_spec_rewrites,
    ),
  )
  let files_with_runtime : Array[MbtiTypescriptPackageFile] = []
  for file in files {
    files_with_runtime.push(file)
  }
  for
    file in collect_runtime_reexport_files_for_mbti_bundle(
      root_package_name,
      loaded.ordered_packages,
      glue_decls,
    ) {
    files_with_runtime.push(file)
  }
  {
    moon_pkg_json,
    package_json: render_typescript_package_json(
      root_package_name, files_with_runtime,
    ),
    autolink_diagnostics_md: render_autolink_diagnostics_md(
      loaded.ordered_packages,
      loaded.package_sources,
    ),
    autolink_glue_mbt: render_autolink_glue_mbt(glue_decls),
    files: files_with_runtime,
  }
}

///|
pub async fn emit_typescript_facade_scaffold_bundle_from_mbti_path(
  root_file_path : String,
) -> MbtiTypescriptScaffoldBundle raise MbtiTypescriptDeclError {
  emit_typescript_facade_scaffold_bundle_from_mbti_path_with_import_rewrites(
    root_file_path,
    {},
  )
}

///|
pub async fn emit_typescript_facade_scaffold_bundle_from_mbti_path_with_import_rewrites(
  root_file_path : String,
  external_import_spec_rewrites : Map[String, String],
) -> MbtiTypescriptScaffoldBundle raise MbtiTypescriptDeclError {
  let loaded = load_mbti_package_sources(root_file_path)
  let root_package_name = loaded.root_package_name
  let glue_decls = collect_mbti_bundle_autolink_glue_decls(loaded, true)
  let facade_export_names : Array[String] = []
  let facade_ts_decls_by_path : Map[String, Array[String]] = {}
  for decl in glue_decls {
    facade_export_names.push(decl.runtime_export_name)
    if decl.ts_decl != "" {
      match mbti_local_package_segments(root_package_name, decl.package_name) {
        Some(segments) => {
          let relative_path = mbti_bundle_relative_path_from_segments(segments)
          match facade_ts_decls_by_path.get(relative_path) {
            Some(items) => items.push(decl.ts_decl)
            None => facade_ts_decls_by_path[relative_path] = [decl.ts_decl]
          }
        }
        None => ()
      }
    }
  }
  let moon_pkg_json = render_moonbit_js_glue_pkg_json(
    loaded, facade_export_names,
  )
  let files = strip_runtime_inaccessible_typescript_package_files(
    loaded,
    emit_typescript_package_bundle_from_mbti_path_with_import_rewrites(
      root_file_path, external_import_spec_rewrites,
    ),
  )
  let files_with_facades : Array[MbtiTypescriptPackageFile] = []
  for file in files {
    match facade_ts_decls_by_path.get(file.relative_path) {
      Some(facade_ts_decls) if facade_ts_decls.length() > 0 => {
        let rendered_facade_ts = facade_ts_decls.join("\n")
        files_with_facades.push({
          relative_path: file.relative_path,
          content: file.content + "\n\n" + rendered_facade_ts,
        })
      }
      _ => files_with_facades.push(file)
    }
  }
  for
    file in collect_runtime_reexport_files_for_mbti_bundle(
      root_package_name,
      loaded.ordered_packages,
      glue_decls,
    ) {
    files_with_facades.push(file)
  }
  {
    moon_pkg_json,
    package_json: render_typescript_package_json(
      root_package_name, files_with_facades,
    ),
    autolink_diagnostics_md: render_autolink_diagnostics_md(
      loaded.ordered_packages,
      loaded.package_sources,
    ),
    autolink_glue_mbt: render_autolink_glue_mbt(glue_decls),
    files: files_with_facades,
  }
}

///|
pub async fn emit_typescript_decl_from_mbti_path(
  file_path : String,
) -> String raise MbtiTypescriptDeclError {
  let source = @fs.read_file(file_path).text() catch {
    e => raise MbtiTypescriptDeclError::ReadError("\{e}")
  }
  parse_mbti_to_typescript(source)
}
