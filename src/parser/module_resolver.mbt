///|
priv enum ModuleResolutionMode {
  Types
  Runtime
}

///|
priv enum JsonFieldValue {
  String(String)
  Object(String)
  Other
}

///|
fn char_at(s : String, idx : Int) -> Char {
  s[idx].to_int().unsafe_to_char()
}

///|
fn is_json_space(c : Char) -> Bool {
  c == ' ' || c == '\n' || c == '\r' || c == '\t'
}

///|
fn skip_json_space(src : String, start : Int) -> Int {
  let mut i = start
  while i < src.length() && is_json_space(char_at(src, i)) {
    i += 1
  }
  i
}

///|
fn json_parse_string(src : String, start : Int) -> (String, Int) {
  let mut i = start + 1
  let buf = StringBuilder::new()
  while i < src.length() {
    let c = char_at(src, i)
    if c == '"' {
      return (buf.to_string(), i + 1)
    }
    if c == '\\' && i + 1 < src.length() {
      let escaped = char_at(src, i + 1)
      match escaped {
        '"' | '\\' | '/' => buf.write_char(escaped)
        'b' => buf.write_char('\u0008'.to_int().unsafe_to_char())
        'f' => buf.write_char('\u000c'.to_int().unsafe_to_char())
        'n' => buf.write_char('\n')
        'r' => buf.write_char('\r')
        't' => buf.write_char('\t')
        'u' =>
          if i + 5 < src.length() {
            let hex = src[i + 2:i + 6].to_string()
            let code = @string.parse_int(hex, base=16) catch { _ => -1 }
            if code >= 0 && code <= 0x10FFFF {
              buf.write_char(code.unsafe_to_char())
            }
            i += 4
          } else {
            buf.write_char(escaped)
          }
        _ => buf.write_char(escaped)
      }
      i += 2
      continue
    }
    buf.write_char(c)
    i += 1
  }
  (buf.to_string(), i)
}

///|
fn scan_json_compound(
  src : String,
  start : Int,
  open : Char,
  close : Char,
) -> Int {
  let mut depth = 0
  let mut i = start
  while i < src.length() {
    let c = char_at(src, i)
    if c == '"' {
      let (_, next) = json_parse_string(src, i)
      i = next
      continue
    }
    if c == '[' {
      i = scan_json_compound(src, i, '[', ']')
      continue
    }
    if c == open {
      depth += 1
    } else if c == close {
      depth -= 1
      if depth == 0 {
        return i + 1
      }
    }
    i += 1
  }
  i
}

///|
fn scan_json_value(src : String, start : Int) -> (JsonFieldValue, Int) {
  let i = skip_json_space(src, start)
  if i >= src.length() {
    return (Other, i)
  }
  let c = char_at(src, i)
  if c == '"' {
    let (value, next) = json_parse_string(src, i)
    return (String(value), next)
  }
  if c == '{' {
    let end_ = scan_json_compound(src, i, '{', '}')
    return (Object(src[i:end_].to_string()), end_)
  }
  if c == '[' {
    let end_ = scan_json_compound(src, i, '[', ']')
    return (Other, end_)
  }
  let mut end_ = i
  while end_ < src.length() {
    let cur = char_at(src, end_)
    if cur == ',' || cur == '}' {
      break
    }
    end_ += 1
  }
  (Other, end_)
}

///|
fn find_json_field(src : String, name : String) -> JsonFieldValue? {
  let mut i = skip_json_space(src, 0)
  if i >= src.length() || char_at(src, i) != '{' {
    return None
  }
  i += 1
  while i < src.length() {
    i = skip_json_space(src, i)
    if i >= src.length() {
      break
    }
    let c = char_at(src, i)
    if c == '}' {
      return None
    }
    if c == ',' {
      i += 1
      continue
    }
    if c != '"' {
      i += 1
      continue
    }
    let (key, next) = json_parse_string(src, i)
    i = skip_json_space(src, next)
    if i >= src.length() || char_at(src, i) != ':' {
      continue
    }
    i += 1
    let (value, value_end) = scan_json_value(src, i)
    if key == name {
      return Some(value)
    }
    i = value_end
  }
  None
}

///|
fn join_path(base : String, name : String) -> String {
  if base == "." || base == "" {
    return name
  }
  if base.has_suffix("/") {
    base + name
  } else {
    base + "/" + name
  }
}

///|
fn normalize_path(path : String) -> String {
  let is_abs = path.has_prefix("/")
  let parts : Array[String] = []
  for part_view in path.split("/") {
    let part = part_view.to_string()
    if part == "" {
      if is_abs && parts.length() == 0 {
        parts.push("")
      }
      continue
    }
    if part == "." {
      continue
    }
    if part == ".." {
      if parts.length() > 0 {
        let last = parts[parts.length() - 1]
        if last != "" && last != ".." {
          let _ = parts.pop()
          continue
        }
      }
      parts.push("..")
    } else {
      parts.push(part)
    }
  }
  if parts.length() == 0 {
    return if is_abs { "/" } else { "." }
  }
  if parts.length() == 1 && parts[0] == "" {
    return "/"
  }
  let mut result = parts[0]
  if result == "" {
    result = "/"
  }
  for i in 1..<parts.length() {
    if result == "/" {
      result = result + parts[i]
    } else {
      result = result + "/" + parts[i]
    }
  }
  result
}

///|
fn dirname(path : String) -> String {
  let normalized = normalize_path(path)
  match normalized.rev_find("/") {
    Some(0) => "/"
    Some(idx) => normalized[:idx].to_string()
    None => "."
  }
}

///|
fn has_known_extension(path : String) -> Bool {
  path.has_suffix(".d.ts") ||
  path.has_suffix(".d.mts") ||
  path.has_suffix(".d.cts") ||
  path.has_suffix(".ts") ||
  path.has_suffix(".tsx") ||
  path.has_suffix(".mts") ||
  path.has_suffix(".cts") ||
  path.has_suffix(".js") ||
  path.has_suffix(".mjs") ||
  path.has_suffix(".cjs") ||
  path.has_suffix(".json")
}

///|
fn strip_suffix(path : String, suffix : String) -> String {
  path[:path.length() - suffix.length()].to_string()
}

///|
fn push_unique(paths : Array[String], path : String) -> Unit {
  if !paths.contains(path) {
    paths.push(path)
  }
}

///|
fn append_resolution_candidates(
  out : Array[String],
  candidate : String,
  mode : ModuleResolutionMode,
) -> Unit {
  if candidate.has_suffix(".js") {
    let stem = strip_suffix(candidate, ".js")
    match mode {
      Types => {
        push_unique(out, stem + ".d.ts")
        push_unique(out, stem + ".ts")
        push_unique(out, stem + ".tsx")
        push_unique(out, candidate)
      }
      Runtime => {
        push_unique(out, candidate)
        push_unique(out, stem + ".ts")
        push_unique(out, stem + ".tsx")
      }
    }
    return
  }
  if candidate.has_suffix(".mjs") {
    let stem = strip_suffix(candidate, ".mjs")
    match mode {
      Types => {
        push_unique(out, stem + ".d.mts")
        push_unique(out, stem + ".mts")
        push_unique(out, candidate)
      }
      Runtime => {
        push_unique(out, candidate)
        push_unique(out, stem + ".mts")
      }
    }
    return
  }
  if candidate.has_suffix(".cjs") {
    let stem = strip_suffix(candidate, ".cjs")
    match mode {
      Types => {
        push_unique(out, stem + ".d.cts")
        push_unique(out, stem + ".cts")
        push_unique(out, candidate)
      }
      Runtime => {
        push_unique(out, candidate)
        push_unique(out, stem + ".cts")
      }
    }
    return
  }
  if has_known_extension(candidate) {
    push_unique(out, candidate)
    return
  }
  push_unique(out, candidate)
  match mode {
    Types => {
      push_unique(out, candidate + ".d.ts")
      push_unique(out, candidate + ".d.mts")
      push_unique(out, candidate + ".d.cts")
      push_unique(out, candidate + ".ts")
      push_unique(out, candidate + ".tsx")
      push_unique(out, candidate + ".mts")
      push_unique(out, candidate + ".cts")
      push_unique(out, candidate + ".js")
      push_unique(out, candidate + ".mjs")
      push_unique(out, candidate + ".cjs")
    }
    Runtime => {
      push_unique(out, candidate + ".ts")
      push_unique(out, candidate + ".tsx")
      push_unique(out, candidate + ".mts")
      push_unique(out, candidate + ".cts")
      push_unique(out, candidate + ".js")
      push_unique(out, candidate + ".mjs")
      push_unique(out, candidate + ".cjs")
    }
  }
}

///|
async fn path_kind(path : String) -> @fs.FileKind {
  @fs.kind(path) catch {
    _ => @fs.FileKind::Unknown
  }
}

///|
async fn file_exists(path : String) -> Bool {
  path_kind(path) is @fs.FileKind::Regular
}

///|
async fn dir_exists(path : String) -> Bool {
  path_kind(path) is @fs.FileKind::Directory
}

///|
async fn resolve_as_file(
  candidate : String,
  mode : ModuleResolutionMode,
) -> String? {
  let candidates : Array[String] = []
  append_resolution_candidates(candidates, normalize_path(candidate), mode)
  for item in candidates {
    if file_exists(item) {
      return Some(item)
    }
  }
  None
}

///|
fn split_package_specifier(specifier : String) -> (String, String) {
  let parts : Array[String] = []
  for part in specifier.split("/") {
    parts.push(part.to_string())
  }
  if specifier.has_prefix("@") {
    if parts.length() < 2 {
      return (specifier, "")
    }
    let package_name = parts[0].to_string() + "/" + parts[1].to_string()
    if parts.length() == 2 {
      return (package_name, "")
    }
    let rest : Array[String] = []
    for i in 2..<parts.length() {
      rest.push(parts[i].to_string())
    }
    return (package_name, rest.join("/"))
  }
  let package_name = parts[0].to_string()
  if parts.length() == 1 {
    return (package_name, "")
  }
  let rest : Array[String] = []
  for i in 1..<parts.length() {
    rest.push(parts[i].to_string())
  }
  (package_name, rest.join("/"))
}

///|
fn exports_subpath_key(subpath : String) -> String {
  if subpath == "" {
    "."
  } else {
    "./" + subpath
  }
}

///|
fn select_export_target(
  value : JsonFieldValue,
  mode : ModuleResolutionMode,
) -> String? {
  match value {
    String(path) => Some(path)
    Object(obj) => {
      let preferred = match mode {
        Types => ["types", "import", "default", "require", "node"]
        Runtime => ["import", "default", "require", "node", "types"]
      }
      for key in preferred {
        match find_json_field(obj, key) {
          Some(inner) =>
            match select_export_target(inner, mode) {
              Some(path) => return Some(path)
              None => ()
            }
          None => ()
        }
      }
      None
    }
    Other => None
  }
}

///|
fn resolve_exports_target(
  package_json : String,
  subpath : String,
  mode : ModuleResolutionMode,
) -> String? {
  match find_json_field(package_json, "exports") {
    Some(String(path)) => if subpath == "" { Some(path) } else { None }
    Some(Object(obj)) => {
      let key = exports_subpath_key(subpath)
      match find_json_field(obj, key) {
        Some(value) => select_export_target(value, mode)
        None =>
          if subpath == "" {
            select_export_target(Object(obj), mode)
          } else {
            None
          }
      }
    }
    _ => None
  }
}

///|
async fn read_package_json(package_root : String) -> String? {
  let canonical_root = @fs.realpath(package_root) catch { _ => package_root }
  let path = normalize_path(join_path(canonical_root, "package.json"))
  if !file_exists(path) {
    return None
  }
  Some(@fs.read_file(path).text() catch { _ => return None })
}

///|
async fn resolve_package_target(
  package_root : String,
  target : String,
  mode : ModuleResolutionMode,
) -> String? {
  let candidate = if target.has_prefix("./") {
    normalize_path(join_path(package_root, target))
  } else {
    normalize_path(join_path(package_root, "./" + target))
  }
  resolve_path_like(candidate, mode)
}

///|
async fn resolve_package_entry(
  package_root : String,
  subpath : String,
  mode : ModuleResolutionMode,
) -> String? {
  let package_json = read_package_json(package_root)
  match package_json {
    Some(pkg) => {
      match resolve_exports_target(pkg, subpath, mode) {
        Some(target) =>
          match resolve_package_target(package_root, target, mode) {
            Some(path) => return Some(path)
            None => ()
          }
        None => ()
      }
      if subpath == "" {
        let preferred_fields = match mode {
          Types => ["types", "typings", "main", "module"]
          Runtime => ["main", "module", "types", "typings"]
        }
        for field in preferred_fields {
          match find_json_field(pkg, field) {
            Some(String(target)) =>
              match resolve_package_target(package_root, target, mode) {
                Some(path) => return Some(path)
                None => ()
              }
            _ => ()
          }
        }
      }
    }
    None => ()
  }
  if subpath != "" {
    return resolve_path_like(
      normalize_path(join_path(package_root, subpath)),
      mode,
    )
  }
  None
}

///|
async fn resolve_as_directory(
  candidate : String,
  mode : ModuleResolutionMode,
) -> String? {
  let normalized = normalize_path(candidate)
  if !dir_exists(normalized) {
    return None
  }
  match resolve_package_entry(normalized, "", mode) {
    Some(path) => return Some(path)
    None => ()
  }
  resolve_as_file(normalize_path(join_path(normalized, "index")), mode)
}

///|
async fn resolve_path_like(
  candidate : String,
  mode : ModuleResolutionMode,
) -> String? {
  let normalized = normalize_path(candidate)
  match resolve_as_file(normalized, mode) {
    Some(path) => Some(path)
    None => resolve_as_directory(normalized, mode)
  }
}

///|
async fn resolve_bare_specifier(
  base_path : String,
  specifier : String,
  mode : ModuleResolutionMode,
) -> String? {
  let (package_name, subpath) = split_package_specifier(specifier)
  let mut current = dirname(base_path)
  while true {
    let package_root = normalize_path(
      join_path(join_path(current, "node_modules"), package_name),
    )
    if dir_exists(package_root) {
      match resolve_package_entry(package_root, subpath, mode) {
        Some(path) => return Some(path)
        None => ()
      }
    }
    let parent = dirname(current)
    if parent == current {
      break
    }
    current = parent
  }
  None
}

///|
async fn resolve_module_specifier(
  base_path : String,
  specifier : String,
  mode : ModuleResolutionMode,
) -> String? {
  let normalized_base = normalize_path(base_path)
  if specifier.has_prefix("./") || specifier.has_prefix("../") {
    return resolve_path_like(
      normalize_path(join_path(dirname(normalized_base), specifier)),
      mode,
    )
  }
  if specifier.has_prefix("/") {
    return resolve_path_like(normalize_path(specifier), mode)
  }
  resolve_bare_specifier(normalized_base, specifier, mode)
}

///|
pub async fn resolve_type_module_specifier(
  base_path : String,
  specifier : String,
) -> String? {
  resolve_module_specifier(base_path, specifier, ModuleResolutionMode::Types)
}

///|
pub async fn resolve_runtime_module_specifier(
  base_path : String,
  specifier : String,
) -> String? {
  resolve_module_specifier(base_path, specifier, ModuleResolutionMode::Runtime)
}
