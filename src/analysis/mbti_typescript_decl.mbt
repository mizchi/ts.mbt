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
  autolink_facade_mbt : String
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
}

///|
priv struct MbtiMarkerTraitDecl {
  name : String
  arity : Int
}

///|
priv struct MbtiAutolinkFacadeDecl {
  export_name : String
  ts_decl : String
  mbt_decl : String
}

///|
priv struct MbtiRawFacadeParam {
  name : String
  ty_src : String
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
  ["pub \{keyword} ", "pub(all) \{keyword} "]
}

///|
fn strip_mbti_public_prefix(line : String, keyword : String) -> String? {
  let trimmed = line.trim().to_string()
  for prefix in mbti_public_prefixes(keyword) {
    if trimmed.has_prefix(prefix) {
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
      '>' => if i == 0 || mbti_char_at(source, i - 1) != '=' { angle -= 1 }
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
        let extends_ty = translate_mbti_type(
          trimmed[idx + 1:trimmed.length()].trim().to_string(),
          imports,
          used_aliases,
          None,
          [],
        )
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
fn collect_mbti_import_block_lines(source : String) -> Array[String] {
  let imports : Array[String] = []
  let mut collecting = false
  for line_view in source.split("\n") {
    let line = line_view.to_string()
    let trimmed = line.trim().to_string()
    if !collecting {
      if trimmed == "import {" {
        collecting = true
        imports.push(line)
      }
      continue
    }
    imports.push(line)
    if trimmed == "}" {
      break
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
            let name = rest[:open_idx].trim().to_string()
            if name.contains("::") && !members.contains(name) {
              members.push(name)
            }
          }
          None => ()
        }
      None => ()
    }
  }
  members
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
    "# Autolink Diagnostics", "", "Public members omitted from link.js.exports because MoonBit JS autolink currently exports top-level public free functions only.",
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
        if raw_name.has_suffix("?") {
          return None
        }
        let name = if idx == 0 && trimmed.has_prefix("Self") {
          "self"
        } else {
          raw_name
        }
        let ty_src = replace_mbti_self_refs(
          trimmed[colon_idx + 1:trimmed.length()].trim().to_string(),
          owner_name,
        )
        params.push({ name, ty_src })
      }
      None => {
        let name = if idx == 0 && trimmed.has_prefix("Self") {
          "self"
        } else {
          "arg\{idx}"
        }
        let ty_src = replace_mbti_self_refs(trimmed, owner_name)
        params.push({ name, ty_src })
      }
    }
    idx += 1
  }
  Some(params)
}

///|
fn render_mbt_facade_params(params : Array[MbtiRawFacadeParam]) -> String {
  let rendered : Array[String] = []
  for param in params {
    rendered.push("\{param.name} : \{param.ty_src}")
  }
  rendered.join(", ")
}

///|
fn render_mbt_facade_call_args(params : Array[MbtiRawFacadeParam]) -> String {
  let args : Array[String] = []
  for param in params {
    args.push(param.name)
  }
  args.join(", ")
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
      let (block, next_idx) = collect_brace_block(lines, idx)
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
fn collect_mbti_root_autolink_facades(
  source : String,
) -> Array[MbtiAutolinkFacadeDecl] raise MbtiTypescriptDeclError {
  let imports = parse_mbti_imports(source)
  let used_aliases : Array[String] = []
  let local_type_params = collect_root_mbti_local_type_params(source)
  let local_free_function_names : Array[String] = []
  let facades : Array[MbtiAutolinkFacadeDecl] = []
  for line_view in source.split("\n") {
    let trimmed = line_view.trim().to_string()
    match parse_mbti_function_signature(trimmed, imports, used_aliases) {
      Some(signature) => {
        let (owner_name, fn_name, fn_type_params, params_src, return_src) = signature
        match owner_name {
          Some(owner_name) =>
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
                  parse_mbti_raw_facade_params(params_src, owner_name) {
                  Some(params) => params
                  None => continue
                }
                let return_ty = translate_mbti_type(
                  return_src,
                  imports,
                  used_aliases,
                  Some(owner_name),
                  owner_type_param_names,
                )
                let export_name = "\{mbti_to_snake_case(owner_name)}_\{mbti_to_snake_case(fn_name)}"
                let mut unique_export_name = export_name
                while local_free_function_names.contains(unique_export_name) ||
                      facades.any(fn(facade) {
                        facade.export_name == unique_export_name
                      }) {
                  unique_export_name += "_facade"
                }
                let rendered_ts_params = render_ts_params(params)
                let facade_ts_decl = "export function \{unique_export_name}(\{rendered_ts_params}): \{return_ty};"
                let rendered_mbt_params = render_mbt_facade_params(raw_params)
                let rendered_mbt_return = replace_mbti_self_refs(
                  return_src, owner_name,
                )
                let call_args = render_mbt_facade_call_args(raw_params)
                let body_expr = if raw_params.length() > 0 &&
                  raw_params[0].name == "self" {
                  let tail_args : Array[String] = []
                  for idx in 1..<raw_params.length() {
                    tail_args.push(raw_params[idx].name)
                  }
                  if tail_args.length() == 0 {
                    "self.\{fn_name}()"
                  } else {
                    let joined_tail_args = tail_args.join(", ")
                    "self.\{fn_name}(\{joined_tail_args})"
                  }
                } else {
                  "\{owner_name}::\{fn_name}(\{call_args})"
                }
                let facade_mbt_decl = "pub fn \{unique_export_name}(\{rendered_mbt_params}) -> \{rendered_mbt_return} {\n  \{body_expr}\n}"
                facades.push({
                  export_name: unique_export_name,
                  ts_decl: facade_ts_decl,
                  mbt_decl: facade_mbt_decl,
                })
              }
              None => ()
            }
          None => local_free_function_names.push(fn_name)
        }
      }
      None => ()
    }
  }
  facades
}

///|
fn render_autolink_facade_mbt(
  source : String,
  facades : Array[MbtiAutolinkFacadeDecl],
) -> String {
  if facades.length() == 0 {
    return ""
  }
  let sections : Array[String] = []
  let import_lines = collect_mbti_import_block_lines(source)
  for line in import_lines {
    sections.push(line)
  }
  if import_lines.length() > 0 {
    sections.push("")
  }
  sections.push("///|")
  sections.push("/// Auto-generated facade wrappers for JS autolink.")
  for facade in facades {
    sections.push("")
    sections.push(facade.mbt_decl)
  }
  sections.join("\n")
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
            let relative_pkg_path = if target_segments.length() == 0 {
              "pkg.generated.mbti"
            } else {
              target_segments.join("/") + "/pkg.generated.mbti"
            }
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
fn render_typescript_package_json(
  root_package_name : String,
  files : Array[MbtiTypescriptPackageFile],
) -> String {
  let package_name = mbti_root_package_npm_name(root_package_name)
  let exports_lines : Array[String] = []
  for file in files {
    match mbti_export_key_from_relative_path(file.relative_path) {
      Some(export_key) =>
        exports_lines.push(
          "    \"\{export_key}\": { \"types\": \"./\{file.relative_path}\" }",
        )
      None => ()
    }
  }
  let lines : Array[String] = [
    "{",
    "  \"name\": \"\{package_name}\",",
    "  \"version\": \"0.0.0\",",
    "  \"type\": \"module\",",
    "  \"sideEffects\": false,",
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
    "String" => "string"
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
  let trimmed = source.trim().to_string()
  if trimmed == "" {
    return ""
  }
  if trimmed.has_suffix("?") {
    let inner = trimmed[:trimmed.length() - 1].trim().to_string()
    let normalized_inner = translate_mbti_type(
      inner, imports, used_aliases, owner_name, owner_type_params,
    )
    if normalized_inner.contains("=>") {
      return "(\{normalized_inner}) | undefined"
    }
    return "\{normalized_inner} | undefined"
  }
  match find_top_level_arrow(trimmed) {
    Some(arrow_idx) => {
      let left = trimmed[:arrow_idx].trim().to_string()
      let right = trimmed[arrow_idx + 2:trimmed.length()].trim().to_string()
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
      return "(\{rendered_params}) => \{rendered_return}"
    }
    None => ()
  }
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
) -> (String?, String, Array[MbtiTypeParam], String, String)? raise MbtiTypescriptDeclError {
  let trimmed = line.trim().to_string()
  if !trimmed.has_prefix("pub fn") || trimmed.has_prefix("pub fn(") {
    return None
  }
  let mut idx = "pub fn".length()
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
          let mut return_ty = rest[2:rest.length()].trim().to_string()
          match return_ty.find(" raise ") {
            Some(raise_idx) =>
              return_ty = return_ty[:raise_idx].trim().to_string()
            None => ()
          }
          match raw_name.find("::") {
            Some(sep_idx) =>
              Some(
                (
                  Some(raw_name[:sep_idx].to_string()),
                  raw_name[sep_idx + 2:raw_name.length()].to_string(),
                  type_params,
                  params_src,
                  return_ty,
                ),
              )
            None => Some((None, raw_name, type_params, params_src, return_ty))
          }
        }
        None => None
      }
    _ => None
  }
}

///|
fn parse_mbti_type_header(
  line : String,
  keyword : String,
  imports : Array[MbtiImportRef],
  used_aliases : Array[String],
) -> (String, Array[MbtiTypeParam])? raise MbtiTypescriptDeclError {
  let trimmed = match strip_mbti_public_prefix(line, keyword) {
    Some(rest) => rest
    None => return None
  }
  if trimmed == "" {
    return None
  }
  match trimmed.find("{") {
    Some(open_idx) => {
      let header = trimmed[:open_idx].trim().to_string()
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
fn parse_struct_block_decl(
  lines : Array[String],
  imports : Array[MbtiImportRef],
  used_aliases : Array[String],
) -> MbtiStructDecl raise MbtiTypescriptDeclError {
  match parse_mbti_type_header(lines[0], "struct", imports, used_aliases) {
    Some(header) => {
      let (name, type_params) = header
      let owner_type_param_names = type_param_names(type_params)
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
fn parse_type_alias_decl(
  line : String,
  imports : Array[MbtiImportRef],
  used_aliases : Array[String],
) -> MbtiTypeAliasDecl raise MbtiTypescriptDeclError {
  let trimmed = match strip_mbti_public_prefix(line, "type") {
    Some(rest) => rest
    None =>
      raise MbtiTypescriptDeclError::ParseError("invalid type alias: \{line}")
  }
  match trimmed.find("=") {
    Some(eq_idx) => {
      let left = trimmed[:eq_idx].trim().to_string()
      let right = trim_trailing_comma_or_semicolon(
        trimmed[eq_idx + 1:trimmed.length()].trim().to_string(),
      )
      let (name, type_params) = match left.find("[") {
        Some(idx) if left.has_suffix("]") =>
          (
            left[:idx].trim().to_string(),
            parse_type_params(
              left[idx + 1:left.length() - 1].to_string(),
              imports,
              used_aliases,
            ),
          )
        _ => (left, [])
      }
      let rendered = translate_mbti_type(right, imports, used_aliases, None, [])
      { name, type_params, body: rendered }
    }
    None =>
      raise MbtiTypescriptDeclError::ParseError("invalid type alias: \{line}")
  }
}

///|
fn render_ts_params(params : Array[MbtiParam]) -> String {
  let rendered : Array[String] = []
  for param in params {
    let optional_suffix = if param.optional { "?" } else { "" }
    rendered.push("\{param.name}\{optional_suffix}: \{param.ty}")
  }
  rendered.join(", ")
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
  let type_order : Array[String] = []
  let type_kinds : Map[String, String] = {}
  let type_params_by_name : Map[String, Array[MbtiTypeParam]] = {}
  let struct_decls : Map[String, MbtiStructDecl] = {}
  let enum_like_decls : Map[String, MbtiEnumLikeDecl] = {}
  let type_alias_decls : Map[String, MbtiTypeAliasDecl] = {}
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
      let (block, next_idx) = collect_brace_block(lines, idx)
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
      let type_header = match strip_mbti_public_prefix(trimmed, "type") {
        Some(rest) => rest
        None => ""
      }
      match type_header.find("=") {
        Some(eq_idx) => {
          let left = type_header[:eq_idx].trim().to_string()
          let name = match left.find("[") {
            Some(name_idx) if left.has_suffix("]") =>
              left[:name_idx].trim().to_string()
            _ => left
          }
          type_order.push(name)
          type_kinds[name] = "type"
          type_params_by_name[name] = alias_decl.type_params
          type_alias_decls[name] = alias_decl
          for trait_name in parse_mbti_derive_trait_names(trimmed) {
            impl_decls.push({ trait_name, owner_name: name })
          }
        }
        None => ()
      }
      idx += 1
      continue
    }
    if trimmed.has_prefix("pub fn") {
      match parse_mbti_function_signature(trimmed, imports, used_aliases) {
        Some(signature) => {
          let (owner_name, fn_name, type_params, params_src, return_src) = signature
          function_decls.push({
            owner_name,
            fn_name,
            type_params,
            params_src,
            return_src,
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
            let member_name = sanitize_ts_identifier(
              function_decl.fn_name,
              "method",
            )
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
              let member_decl = "\{member_name}\{type_param_suffix}(\{rendered_params}): \{return_ty};"
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
              let member_decl = "function \{member_name}\{type_param_suffix}(\{rendered_params}): \{return_ty};"
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
        let fn_type_params = render_type_param_suffix(function_decl.type_params)
        let safe_fn_name = sanitize_ts_identifier(function_decl.fn_name, "fn")
        let rendered_params = render_ts_params(params)
        top_level_decls.push(
          "export function \{safe_fn_name}\{fn_type_params}(\{rendered_params}): \{return_ty};",
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
  for marker_trait_name in marker_trait_order {
    match marker_trait_decls.get(marker_trait_name) {
      Some(marker_trait_decl) =>
        decls.push(render_marker_trait_decl(marker_trait_decl))
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
  let import_lines : Array[String] = []
  for alias_name in used_aliases {
    for import_ref in imports {
      if import_ref.alias_name == alias_name {
        let import_spec = match
          import_spec_rewrites.get(import_ref.module_spec) {
          Some(rewritten) => rewritten
          None => import_ref.module_spec
        }
        import_lines.push(
          "import type * as \{import_ref.ts_alias} from \"\{import_spec}\";",
        )
        break
      }
    }
  }
  import_lines.sort()
  let all_parts : Array[String] = []
  if import_lines.length() > 0 {
    all_parts.push(import_lines.join("\n"))
  }
  if decls.length() > 0 {
    all_parts.push(decls.join("\n\n"))
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
  let root_source = loaded.package_sources[loaded.root_package_name]
  let root_package_name = loaded.root_package_name
  let moon_pkg_json = emit_moonbit_js_link_config_from_mbti_source(root_source) catch {
    MbtiJsLinkConfigError::ReadError(msg)
    | MbtiJsLinkConfigError::ParseError(msg) =>
      raise MbtiTypescriptDeclError::ParseError(msg)
  }
  let files = emit_typescript_package_bundle_from_mbti_path_with_import_rewrites(
    root_file_path, external_import_spec_rewrites,
  )
  {
    moon_pkg_json,
    package_json: render_typescript_package_json(root_package_name, files),
    autolink_diagnostics_md: render_autolink_diagnostics_md(
      loaded.ordered_packages,
      loaded.package_sources,
    ),
    autolink_facade_mbt: "",
    files,
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
  let root_source = loaded.package_sources[loaded.root_package_name]
  let root_package_name = loaded.root_package_name
  let facades = collect_mbti_root_autolink_facades(root_source)
  let facade_export_names : Array[String] = []
  let facade_ts_decls : Array[String] = []
  for facade in facades {
    facade_export_names.push(facade.export_name)
    facade_ts_decls.push(facade.ts_decl)
  }
  let moon_pkg_json = emit_moonbit_js_link_config_from_mbti_source_with_extra_exports(
    root_source, facade_export_names,
  ) catch {
    MbtiJsLinkConfigError::ReadError(msg)
    | MbtiJsLinkConfigError::ParseError(msg) =>
      raise MbtiTypescriptDeclError::ParseError(msg)
  }
  let files = emit_typescript_package_bundle_from_mbti_path_with_import_rewrites(
    root_file_path, external_import_spec_rewrites,
  )
  let files_with_facades : Array[MbtiTypescriptPackageFile] = []
  let rendered_facade_ts = facade_ts_decls.join("\n")
  for file in files {
    if file.relative_path == "index.d.ts" && rendered_facade_ts != "" {
      files_with_facades.push({
        relative_path: file.relative_path,
        content: file.content + "\n\n" + rendered_facade_ts,
      })
    } else {
      files_with_facades.push(file)
    }
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
    autolink_facade_mbt: render_autolink_facade_mbt(root_source, facades),
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
