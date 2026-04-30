///|
priv enum ModuleResolutionMode {
  Types
  Runtime
}

///|
priv enum JsonFieldValue {
  String(String)
  Object(String)
  Array(String)
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
    if c == open {
      depth += 1
      i += 1
      continue
    }
    if c == close {
      depth -= 1
      if depth == 0 {
        return i + 1
      }
      i += 1
      continue
    }
    if c == '{' {
      i = scan_json_compound(src, i, '{', '}')
      continue
    }
    if c == '[' {
      i = scan_json_compound(src, i, '[', ']')
      continue
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
    return (Array(src[i:end_].to_string()), end_)
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
fn scan_json_value_end(src : String, start : Int) -> Int {
  let i = skip_json_space(src, start)
  if i >= src.length() {
    return i
  }
  let c = char_at(src, i)
  if c == '"' {
    let (_, next) = json_parse_string(src, i)
    return next
  }
  if c == '{' {
    return scan_json_compound(src, i, '{', '}')
  }
  if c == '[' {
    return scan_json_compound(src, i, '[', ']')
  }
  let mut end_ = i
  while end_ < src.length() {
    let cur = char_at(src, end_)
    if cur == ',' || cur == '}' {
      break
    }
    end_ += 1
  }
  end_
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
fn parse_json_string_array(src : String) -> Array[String] {
  let items : Array[String] = []
  let mut i = skip_json_space(src, 0)
  if i >= src.length() || char_at(src, i) != '[' {
    return items
  }
  i += 1
  while i < src.length() {
    i = skip_json_space(src, i)
    if i >= src.length() {
      break
    }
    let c = char_at(src, i)
    if c == ']' {
      return items
    }
    if c == ',' {
      i += 1
      continue
    }
    if c == '"' {
      let (value, next) = json_parse_string(src, i)
      items.push(value)
      i = next
      continue
    }
    let (_, next) = scan_json_value(src, i)
    i = next
  }
  items
}

///|
fn parse_json_array_values(src : String) -> Array[JsonFieldValue] {
  let values : Array[JsonFieldValue] = []
  let mut i = skip_json_space(src, 0)
  if i >= src.length() || char_at(src, i) != '[' {
    return values
  }
  i += 1
  while i < src.length() {
    i = skip_json_space(src, i)
    if i >= src.length() {
      break
    }
    let c = char_at(src, i)
    if c == ']' {
      return values
    }
    if c == ',' {
      i += 1
      continue
    }
    let (value, next) = scan_json_value(src, i)
    values.push(value)
    i = next
  }
  values
}

///|
fn find_object_field_value_range(
  src : String,
  object_start : Int,
  object_end : Int,
  field_name : String,
) -> (Int, Int)? {
  let mut i = skip_json_space(src, object_start)
  if i >= object_end || char_at(src, i) != '{' {
    return None
  }
  i += 1
  while i < object_end {
    i = skip_json_space(src, i)
    if i >= object_end {
      break
    }
    let c = char_at(src, i)
    if c == '}' {
      break
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
    if i >= object_end || char_at(src, i) != ':' {
      continue
    }
    i += 1
    let value_start = skip_json_space(src, i)
    let value_end = scan_json_value_end(src, value_start)
    if key == field_name {
      return Some((value_start, value_end))
    }
    i = value_end
  }
  None
}

///|
fn find_named_object_range(src : String, field_name : String) -> (Int, Int)? {
  match find_object_field_value_range(src, 0, src.length(), field_name) {
    Some((start, end_)) =>
      if char_at(src, start) == '{' {
        Some((start, end_))
      } else {
        None
      }
    None => None
  }
}

///|
fn find_named_object_range_in_object(
  src : String,
  object_start : Int,
  object_end : Int,
  field_name : String,
) -> (Int, Int)? {
  match
    find_object_field_value_range(src, object_start, object_end, field_name) {
    Some((start, end_)) =>
      if char_at(src, start) == '{' {
        Some((start, end_))
      } else {
        None
      }
    None => None
  }
}

///|
fn parse_json_string_at(src : String, start : Int) -> String? {
  if start >= src.length() || char_at(src, start) != '"' {
    return None
  }
  let (value, _) = json_parse_string(src, start)
  Some(value)
}

///|
fn parse_json_string_array_at(
  src : String,
  start : Int,
  end_ : Int,
) -> Array[String] {
  if start >= end_ || char_at(src, start) != '[' {
    return []
  }
  parse_json_string_array(src[start:end_].to_string())
}

///|
fn parse_string_targets_from_range(
  src : String,
  start : Int,
  end_ : Int,
) -> Array[String] {
  if start >= end_ {
    return []
  }
  let c = char_at(src, start)
  if c == '"' {
    match parse_json_string_at(src, start) {
      Some(value) => [value]
      None => []
    }
  } else if c == '[' {
    parse_json_string_array_at(src, start, end_)
  } else {
    []
  }
}

///|
fn resolve_string_array_mapping_in_object(
  src : String,
  object_start : Int,
  object_end : Int,
  specifier : String,
) -> Array[String] {
  match
    find_object_field_value_range(src, object_start, object_end, specifier) {
    Some((start, end_)) => {
      let exact = parse_string_targets_from_range(src, start, end_)
      if exact.length() > 0 {
        return exact
      }
    }
    None => ()
  }
  let parts = split_slash_parts(specifier)
  for i in 0..<parts.length() {
    let cut = parts.length() - 1 - i
    if cut <= 0 {
      continue
    }
    let pattern = join_slash_parts(parts, 0, cut) + "/*"
    let capture = join_slash_parts(parts, cut, parts.length())
    match
      find_object_field_value_range(src, object_start, object_end, pattern) {
      Some((start, end_)) => {
        let resolved : Array[String] = []
        for item in parse_string_targets_from_range(src, start, end_) {
          resolved.push(apply_single_wildcard(item, capture))
        }
        if resolved.length() > 0 {
          return resolved
        }
      }
      None => ()
    }
  }
  match find_object_field_value_range(src, object_start, object_end, "*") {
    Some((start, end_)) => {
      let resolved : Array[String] = []
      for item in parse_string_targets_from_range(src, start, end_) {
        resolved.push(apply_single_wildcard(item, specifier))
      }
      resolved
    }
    None => []
  }
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
fn apply_single_wildcard(pattern : String, replacement : String) -> String {
  match pattern.find("*") {
    Some(idx) => {
      let prefix = if idx == 0 { "" } else { pattern[:idx].to_string() }
      let suffix = if idx + 1 >= pattern.length() {
        ""
      } else {
        pattern[idx + 1:pattern.length()].to_string()
      }
      prefix + replacement + suffix
    }
    None => pattern
  }
}

///|
fn split_slash_parts(path : String) -> Array[String] {
  let parts : Array[String] = []
  for part in path.split("/") {
    parts.push(part.to_string())
  }
  parts
}

///|
fn join_slash_parts(parts : Array[String], start : Int, end_ : Int) -> String {
  if start >= end_ {
    return ""
  }
  let mut result = parts[start]
  for i in (start + 1)..<end_ {
    result = result + "/" + parts[i]
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
fn is_runtime_js_path(path : String) -> Bool {
  path.has_suffix(".js") || path.has_suffix(".mjs") || path.has_suffix(".cjs")
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
  if candidate.has_suffix(".ts") && !candidate.has_suffix(".d.ts") {
    let stem = strip_suffix(candidate, ".ts")
    match mode {
      Types => {
        push_unique(out, stem + ".d.ts")
        push_unique(out, candidate)
      }
      Runtime => push_unique(out, candidate)
    }
    return
  }
  if candidate.has_suffix(".tsx") {
    let stem = strip_suffix(candidate, ".tsx")
    match mode {
      Types => {
        push_unique(out, stem + ".d.ts")
        push_unique(out, candidate)
      }
      Runtime => push_unique(out, candidate)
    }
    return
  }
  if candidate.has_suffix(".mts") && !candidate.has_suffix(".d.mts") {
    let stem = strip_suffix(candidate, ".mts")
    match mode {
      Types => {
        push_unique(out, stem + ".d.mts")
        push_unique(out, candidate)
      }
      Runtime => push_unique(out, candidate)
    }
    return
  }
  if candidate.has_suffix(".cts") && !candidate.has_suffix(".d.cts") {
    let stem = strip_suffix(candidate, ".cts")
    match mode {
      Types => {
        push_unique(out, stem + ".d.cts")
        push_unique(out, candidate)
      }
      Runtime => push_unique(out, candidate)
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
async fn find_nearest_ancestor_file(
  base_path : String,
  file_name : String,
) -> String? {
  let mut current = dirname(normalize_path(base_path))
  while true {
    let candidate = normalize_path(join_path(current, file_name))
    if file_exists(candidate) {
      return Some(candidate)
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
fn resolve_conditional_mapping_targets(
  mapping_obj : String,
  specifier : String,
  mode : ModuleResolutionMode,
) -> Array[String] {
  match find_json_field(mapping_obj, specifier) {
    Some(value) => {
      let targets = select_export_targets(value, mode)
      if targets.length() > 0 {
        return targets
      }
    }
    None => ()
  }
  let parts = split_slash_parts(specifier)
  for i in 0..<parts.length() {
    let cut = parts.length() - 1 - i
    if cut <= 0 {
      continue
    }
    let pattern = join_slash_parts(parts, 0, cut) + "/*"
    let capture = join_slash_parts(parts, cut, parts.length())
    match find_json_field(mapping_obj, pattern) {
      Some(value) => {
        let resolved : Array[String] = []
        for target in select_export_targets(value, mode) {
          resolved.push(apply_single_wildcard(target, capture))
        }
        if resolved.length() > 0 {
          return resolved
        }
      }
      None => ()
    }
  }
  match find_json_field(mapping_obj, "*") {
    Some(value) => {
      let resolved : Array[String] = []
      for target in select_export_targets(value, mode) {
        resolved.push(apply_single_wildcard(target, specifier))
      }
      resolved
    }
    None => []
  }
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
fn types_package_name(package_name : String) -> String? {
  if package_name.has_prefix("@types/") {
    return None
  }
  if package_name.has_prefix("@") {
    let parts : Array[String] = []
    for part in package_name.split("/") {
      parts.push(part.to_string())
    }
    if parts.length() < 2 {
      return None
    }
    return Some("@types/" + parts[0][1:].to_string() + "__" + parts[1])
  }
  Some("@types/" + package_name)
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
fn select_export_targets(
  value : JsonFieldValue,
  mode : ModuleResolutionMode,
) -> Array[String] {
  match value {
    String(path) => [path]
    Array(items_src) => {
      let targets : Array[String] = []
      for item in parse_json_array_values(items_src) {
        for target in select_export_targets(item, mode) {
          push_unique(targets, target)
        }
      }
      targets
    }
    Object(obj) => {
      let preferred = match mode {
        Types => ["types", "import", "default", "require", "node"]
        Runtime => ["import", "default", "require", "node", "types"]
      }
      for key in preferred {
        match find_json_field(obj, key) {
          Some(inner) => {
            let targets = select_export_targets(inner, mode)
            if targets.length() > 0 {
              return targets
            }
          }
          None => ()
        }
      }
      []
    }
    Other => []
  }
}

///|
fn resolve_exports_target(
  package_json : String,
  subpath : String,
  mode : ModuleResolutionMode,
) -> Array[String] {
  match find_json_field(package_json, "exports") {
    Some(String(path)) => if subpath == "" { [path] } else { [] }
    Some(Array(items_src)) =>
      if subpath == "" {
        select_export_targets(Array(items_src), mode)
      } else {
        []
      }
    Some(Object(obj)) => {
      let key = exports_subpath_key(subpath)
      match find_json_field(obj, key) {
        Some(value) => select_export_targets(value, mode)
        None =>
          if subpath == "" {
            select_export_targets(Object(obj), mode)
          } else {
            resolve_conditional_mapping_targets(obj, key, mode)
          }
      }
    }
    _ => []
  }
}

///|
fn resolve_types_versions_targets(
  package_json : String,
  subpath : String,
) -> Array[String] {
  match find_named_object_range(package_json, "typesVersions") {
    Some((versions_start, versions_end)) =>
      match
        find_named_object_range_in_object(
          package_json, versions_start, versions_end, "*",
        ) {
        Some((selector_start, selector_end)) =>
          resolve_string_array_mapping_in_object(
            package_json, selector_start, selector_end, subpath,
          )
        None => []
      }
    _ => []
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
async fn read_nearest_package_json(base_path : String) -> (String, String)? {
  match find_nearest_ancestor_file(base_path, "package.json") {
    Some(package_json_path) => {
      let package_root = dirname(package_json_path)
      let package_json = @fs.read_file(package_json_path).text() catch {
        _ => return None
      }
      Some((package_root, package_json))
    }
    None => None
  }
}

///|
async fn resolve_tsconfig_specifier(
  base_path : String,
  specifier : String,
  mode : ModuleResolutionMode,
) -> String? {
  match find_nearest_ancestor_file(base_path, "tsconfig.json") {
    Some(tsconfig_path) => {
      let tsconfig_dir = dirname(tsconfig_path)
      let tsconfig_src = @fs.read_file(tsconfig_path).text() catch {
        _ => return None
      }
      match find_named_object_range(tsconfig_src, "compilerOptions") {
        Some((compiler_start, compiler_end)) => {
          let mut base_dir = ""
          match
            find_object_field_value_range(
              tsconfig_src, compiler_start, compiler_end, "baseUrl",
            ) {
            Some((start, _)) =>
              match parse_json_string_at(tsconfig_src, start) {
                Some(base_url) =>
                  base_dir = normalize_path(join_path(tsconfig_dir, base_url))
                None => ()
              }
            None => ()
          }
          match
            find_named_object_range_in_object(
              tsconfig_src, compiler_start, compiler_end, "paths",
            ) {
            Some((paths_start, paths_end)) => {
              let targets = resolve_string_array_mapping_in_object(
                tsconfig_src, paths_start, paths_end, specifier,
              )
              for target in targets {
                let candidate = if base_dir == "" {
                  normalize_path(join_path(tsconfig_dir, target))
                } else {
                  normalize_path(join_path(base_dir, target))
                }
                match resolve_path_like(candidate, mode) {
                  Some(path) => return Some(path)
                  None => ()
                }
              }
            }
            None => ()
          }
          if base_dir != "" {
            return resolve_path_like(
              normalize_path(join_path(base_dir, specifier)),
              mode,
            )
          }
          None
        }
        None => None
      }
    }
    None => None
  }
}

///|
async fn resolve_package_imports_specifier(
  base_path : String,
  specifier : String,
  mode : ModuleResolutionMode,
) -> String? {
  let seen : Array[String] = []
  resolve_package_imports_specifier_inner(base_path, specifier, mode, seen)
}

///|
async fn resolve_package_imports_specifier_inner(
  base_path : String,
  specifier : String,
  mode : ModuleResolutionMode,
  seen : Array[String],
) -> String? {
  if seen.contains(specifier) {
    return None
  }
  seen.push(specifier)
  match read_nearest_package_json(base_path) {
    Some((package_root, package_json)) =>
      match find_json_field(package_json, "imports") {
        Some(Object(imports_obj)) => {
          let targets = resolve_conditional_mapping_targets(
            imports_obj, specifier, mode,
          )
          for target in targets {
            if target.has_prefix("./") || target.has_prefix("../") {
              match resolve_package_target(package_root, target, mode) {
                Some(path) => return Some(path)
                None => ()
              }
            } else if target.has_prefix("/") {
              match resolve_path_like(normalize_path(target), mode) {
                Some(path) => return Some(path)
                None => ()
              }
            } else if target.has_prefix("#") {
              let package_base = normalize_path(
                join_path(package_root, "package.json"),
              )
              match
                resolve_package_imports_specifier_inner(
                  package_base, target, mode, seen,
                ) {
                Some(path) => return Some(path)
                None => ()
              }
            } else {
              let package_base = normalize_path(
                join_path(package_root, "package.json"),
              )
              match resolve_module_specifier(package_base, target, mode) {
                Some(path) => return Some(path)
                None => ()
              }
            }
          }
          None
        }
        _ => None
      }
    None => None
  }
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
      for target in resolve_exports_target(pkg, subpath, mode) {
        match resolve_package_target(package_root, target, mode) {
          Some(path) => return Some(path)
          None => ()
        }
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
      } else {
        match mode {
          Types =>
            for target in resolve_types_versions_targets(pkg, subpath) {
              match resolve_package_target(package_root, target, mode) {
                Some(path) => return Some(path)
                None => ()
              }
            }
          Runtime => ()
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
async fn resolve_at_types_package_entry(
  node_modules_root : String,
  package_name : String,
  subpath : String,
) -> String? {
  let types_name = match types_package_name(package_name) {
    Some(types_name) => types_name
    None => return None
  }
  let types_root = normalize_path(join_path(node_modules_root, types_name))
  if !dir_exists(types_root) {
    return None
  }
  resolve_package_entry(types_root, subpath, ModuleResolutionMode::Types)
}

///|
async fn resolve_node_builtin_type_specifier(
  base_path : String,
  specifier : String,
) -> String? {
  let builtin_path = specifier["node:".length():].to_string()
  if builtin_path == "" {
    return None
  }
  let mut current = dirname(base_path)
  while true {
    let types_node_root = normalize_path(
      join_path(join_path(current, "node_modules"), "@types/node"),
    )
    if dir_exists(types_node_root) {
      match
        resolve_path_like(
          normalize_path(join_path(types_node_root, builtin_path)),
          ModuleResolutionMode::Types,
        ) {
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
async fn resolve_bare_specifier(
  base_path : String,
  specifier : String,
  mode : ModuleResolutionMode,
) -> String? {
  let (package_name, subpath) = split_package_specifier(specifier)
  let mut current = dirname(base_path)
  let mut js_fallback : String? = None
  while true {
    let node_modules_root = normalize_path(join_path(current, "node_modules"))
    let package_root = normalize_path(
      join_path(node_modules_root, package_name),
    )
    if dir_exists(package_root) {
      match resolve_package_entry(package_root, subpath, mode) {
        Some(path) =>
          match mode {
            Runtime => return Some(path)
            Types =>
              if is_runtime_js_path(path) {
                match js_fallback {
                  Some(_) => ()
                  None => js_fallback = Some(path)
                }
              } else {
                return Some(path)
              }
          }
        None => ()
      }
    }
    match mode {
      Types =>
        match
          resolve_at_types_package_entry(
            node_modules_root, package_name, subpath,
          ) {
          Some(path) => return Some(path)
          None => ()
        }
      Runtime => ()
    }
    let parent = dirname(current)
    if parent == current {
      break
    }
    current = parent
  }
  match mode {
    Types => js_fallback
    Runtime => None
  }
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
  if specifier.has_prefix("#") {
    return resolve_package_imports_specifier(normalized_base, specifier, mode)
  }
  if specifier.has_prefix("node:") {
    return match mode {
      Types => resolve_node_builtin_type_specifier(normalized_base, specifier)
      Runtime => None
    }
  }
  match resolve_tsconfig_specifier(normalized_base, specifier, mode) {
    Some(path) => return Some(path)
    None => ()
  }
  match resolve_bare_specifier(normalized_base, specifier, mode) {
    Some(path) => Some(path)
    None => {
      let real_base = @fs.realpath(normalized_base) catch {
        _ => normalized_base
      }
      if real_base == normalized_base {
        None
      } else {
        resolve_bare_specifier(real_base, specifier, mode)
      }
    }
  }
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
