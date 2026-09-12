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
  moon_pkg : String
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
priv struct BridgeParamDecl {
  type_name : String
}

///|
priv struct BridgeEnumConverter {
  type_name : String
  to_js_name : String
  from_js_name : String
  to_js_optional_name : String
  from_js_optional_name : String
}

///|
priv struct BridgeTypeGuardHelper {
  source_type : String
  target_type : String
  guard_name : String
  helper_name : String
}

///|
priv struct BridgeStructDecl {
  name : String
  type_param_suffix : String
  fields : Array[String]
}

///|
fn render_bridge_pkg_json(_needs_js_import : Bool) -> String {
  // Generated bridge packages are now fully self-contained: `JSValue`
  // and `Promise[X]` are emitted as `#external` types in the bridge
  // itself, so there's no compile-time `mizchi/js` dependency.
  //
  // Returned content is the new `moon.pkg` text format (an empty
  // body); written by callers as `moon.pkg`, never `moon.pkg.json`.
  // The MoonBit toolchain auto-migrates a stray `moon.pkg.json` to
  // `moon.pkg` on every build, so emitting the JSON form would print
  // a "deprecated moon.pkg.json is removed" warning every vendor run.
  ""
}

///|
fn bridge_bundle_needs_js_import(_bundle : MoonBitTsBridgeBundle) -> Bool {
  false
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
  name[start:end_].to_owned()
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
      parts.push(current.trim().to_owned())
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
  let tail = current.trim().to_owned()
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
    let part = part_view.to_owned()
    if part == "" {
      continue
    }
    let head = bridge_to_upper_ascii(part[0].unsafe_to_char()).to_string()
    result += head + part[1:].to_owned()
  }
  result
}

///|
/// Index of the `)` matching the `(` at `open_index`, or `None` when
/// unbalanced. A plain `rev_find(")")` is wrong for value getters whose
/// return type is itself a (curried) function type -- the last `)` on the
/// line belongs to the RETURN type, not the parameter list
/// (`declare pub fn get_use_() -> (A) -> (B) -> C`).
fn bridge_find_matching_paren(text : String, open_index : Int) -> Int? {
  let mut depth = 0
  for i, c in text.iter2() {
    if i < open_index {
      continue
    }
    if c == '(' {
      depth += 1
    } else if c == ')' {
      depth -= 1
      if depth == 0 {
        return Some(i)
      }
    }
  }
  None
}

///|
fn parse_bridge_top_level_fn_decl_line(line : String) -> BridgeTopLevelFnDecl? {
  let prefix = "declare pub fn "
  if !line.has_prefix(prefix) {
    return None
  }
  let rest = line[prefix.length():].to_owned()
  let open = rest.find("(")
  let close = match open {
    Some(open_index) => bridge_find_matching_paren(rest, open_index)
    None => None
  }
  match open {
    Some(open_index) =>
      match close {
        Some(close_index) => {
          if close_index < open_index {
            return None
          }
          let public_name = rest[:open_index].to_owned().trim().to_owned()
          if public_name.contains("::") {
            return None
          }
          let params_src = rest[open_index + 1:close_index].to_owned()
          let after = rest[close_index + 1:].to_owned().trim().to_owned()
          if !after.has_prefix("->") {
            return None
          }
          let return_type = after[2:].to_owned().trim().to_owned()
          let arg_names : Array[String] = []
          if params_src.trim() != "" {
            for item in bridge_split_top_level_commas(params_src) {
              if item == "" {
                continue
              }
              match item.find(":") {
                Some(index) =>
                  arg_names.push(item[:index].to_owned().trim().to_owned())
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
fn parse_bridge_pub_extern_fn_decl_line(line : String) -> BridgeTopLevelFnDecl? {
  let prefix = "pub extern \"js\" fn "
  if !line.has_prefix(prefix) {
    return None
  }
  let rest = line[prefix.length():].to_owned()
  let open = rest.find("(")
  let close = match open {
    Some(open_index) => bridge_find_matching_paren(rest, open_index)
    None => None
  }
  match open {
    Some(open_index) =>
      match close {
        Some(close_index) => {
          if close_index < open_index {
            return None
          }
          let public_name = rest[:open_index].to_owned().trim().to_owned()
          if public_name.contains("::") {
            return None
          }
          let params_src = rest[open_index + 1:close_index].to_owned()
          let after = rest[close_index + 1:].to_owned().trim().to_owned()
          if !after.has_prefix("->") {
            return None
          }
          let return_src = after[2:].to_owned().trim().to_owned()
          let return_type = match return_src.find("=") {
            Some(index) => return_src[:index].to_owned().trim().to_owned()
            None => return_src
          }
          if return_type == "" {
            return None
          }
          let arg_names : Array[String] = []
          if params_src.trim() != "" {
            for item in bridge_split_top_level_commas(params_src) {
              if item == "" {
                continue
              }
              match item.find(":") {
                Some(index) =>
                  arg_names.push(item[:index].to_owned().trim().to_owned())
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
fn parse_bridge_param_decls(params_src : String) -> Array[BridgeParamDecl] {
  let decls : Array[BridgeParamDecl] = []
  if params_src.trim() == "" {
    return decls
  }
  for item in bridge_split_top_level_commas(params_src) {
    let trimmed = item.trim().to_owned()
    if trimmed == "" {
      continue
    }
    match trimmed.find(":") {
      Some(index) => {
        let type_name = trimmed[index + 1:].to_owned().trim().to_owned()
        decls.push({ type_name, })
      }
      None => decls.push({ type_name: "" })
    }
  }
  decls
}

///|
/// Async-callback lowering (`(A, B) -> Promise[T]` params accepting a
/// MoonBit `async fn`, optional form included) is shared with the decl
/// layer so `.mbti` and `bridge.mbt` cannot drift — see
/// `@parser.moonbit_async_callback_lowering` for the shape rules.
fn bridge_fn_decl_has_async_callback_param(
  fn_decl : BridgeTopLevelFnDecl,
) -> Bool {
  for param in parse_bridge_param_decls(fn_decl.params_src) {
    if @parser.moonbit_async_callback_lowering(param.type_name) is Some(_) {
      return true
    }
  }
  false
}

///|
/// Rebuild a params_src with every async-callback param lowered.
/// Returns `None` when nothing lowers (the params_src stays as-is).
fn bridge_lowered_async_callback_params_src(params_src : String) -> String? {
  if params_src.trim() == "" {
    return None
  }
  let mut lowered_any = false
  let rebuilt : Array[String] = []
  for item in bridge_split_top_level_commas(params_src) {
    if item == "" {
      continue
    }
    match item.find(":") {
      Some(index) => {
        let name = item[:index].to_owned().trim().to_owned()
        let type_name = item[index + 1:].to_owned().trim().to_owned()
        match @parser.moonbit_async_callback_lowering(type_name) {
          Some(lowering) => {
            lowered_any = true
            rebuilt.push("\{name} : \{lowering.lowered_type}")
          }
          None => rebuilt.push("\{name} : \{type_name}")
        }
      }
      None => rebuilt.push(item)
    }
  }
  if lowered_any {
    Some(rebuilt.join(", "))
  } else {
    None
  }
}

///|
fn parse_bridge_public_type_name_line(line : String) -> String? {
  let prefix = "declare pub type "
  let rest = if line.has_prefix(prefix) {
    line[prefix.length():].to_owned().trim().to_owned()
  } else {
    let struct_prefixes = [
      "pub(all) struct ", "pub struct ", "pub(all) enum ", "pub enum ",
    ]
    let mut parsed : String? = None
    for struct_prefix in struct_prefixes {
      if line.has_prefix(struct_prefix) {
        parsed = Some(
          line[struct_prefix.length():].to_owned().trim().to_owned(),
        )
        break
      }
    }
    match parsed {
      Some(rest) => rest
      None => return None
    }
  }
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
  let type_name = rest[:end_].to_owned().trim().to_owned()
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
    let line = line_view.to_owned().trim().to_owned()
    match parse_bridge_public_type_name_line(line) {
      Some(name) => if !names.contains(name) { names.push(name) }
      None => ()
    }
  }
  names
}

///|
fn parse_bridge_implemented_type_name_line(line : String) -> String? {
  let prefixes = [
    "pub(all) struct ", "pub struct ", "struct ", "pub(all) enum ", "pub enum ",
    "enum ", "pub type ", "type ",
  ]
  for prefix in prefixes {
    if !line.has_prefix(prefix) {
      continue
    }
    let rest = line[prefix.length():].to_owned().trim().to_owned()
    if rest == "" {
      continue
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
    match rest.find("{") {
      Some(idx) => if idx < end_ { end_ = idx }
      None => ()
    }
    match rest.find("=") {
      Some(idx) => if idx < end_ { end_ = idx }
      None => ()
    }
    let type_name = rest[:end_].to_owned().trim().to_owned()
    if type_name != "" {
      return Some(type_name)
    }
  }
  None
}

///|
/// Probe `bridge_mbt` for a top-level type declaration of `name` and
/// return its type-parameter arity. Inspects `pub(all) struct` /
/// `pub type` / `pub enum` style decls (with or without `#external`).
/// Returns `0` when no decl is found or the name appears bare.
fn bridge_struct_decl_arity(bridge_mbt : String, name : String) -> Int {
  let prefixes = [
    "pub(all) struct ", "pub struct ", "pub(all) enum ", "pub enum ", "pub type ",
  ]
  for line_view in bridge_mbt.split("\n") {
    let line = line_view.to_owned().trim().to_owned()
    for prefix in prefixes {
      if !line.has_prefix(prefix) {
        continue
      }
      let rest = line[prefix.length():].to_owned().trim().to_owned()
      if !rest.has_prefix(name) {
        continue
      }
      let after = rest[name.length():].to_owned()
      if after == "" ||
        after[0].to_int() == ' '.to_int() ||
        after[0].to_int() == '{'.to_int() ||
        after[0].to_int() == '='.to_int() {
        return 0
      }
      if after[0].to_int() != '['.to_int() {
        continue
      }
      // Count commas at depth 1 inside the bracket pair to derive arity.
      let mut depth = 0
      let mut count = 1
      for i in 0..<after.length() {
        let ch = after[i].unsafe_to_char()
        if ch == '[' {
          depth += 1
        } else if ch == ']' {
          depth -= 1
          if depth == 0 {
            return count
          }
        } else if ch == ',' && depth == 1 {
          count += 1
        }
      }
      return count
    }
  }
  0
}

///|
fn collect_bridge_implemented_type_names(bridge_mbt : String) -> Array[String] {
  let names : Array[String] = []
  for line_view in bridge_mbt.split("\n") {
    let line = line_view.to_owned().trim().to_owned()
    match parse_bridge_implemented_type_name_line(line) {
      Some(name) => if !names.contains(name) { names.push(name) }
      None => ()
    }
  }
  names
}

///|
fn parse_bridge_struct_header_line(line : String) -> (String, String)? {
  let prefixes = ["pub(all) struct ", "pub struct "]
  for prefix in prefixes {
    if !line.has_prefix(prefix) {
      continue
    }
    let rest = line[prefix.length():].to_owned().trim().to_owned()
    if rest == "" {
      continue
    }
    let mut end_ = rest.length()
    match rest.find("{") {
      Some(idx) => end_ = idx
      None => ()
    }
    match rest.find("[") {
      Some(idx) => if idx < end_ { end_ = idx }
      None => ()
    }
    match rest.find(" ") {
      Some(idx) => if idx < end_ { end_ = idx }
      None => ()
    }
    let name = rest[:end_].to_owned().trim().to_owned()
    let type_param_suffix = match rest.find("[") {
      Some(start) if start < rest.length() =>
        match rest.find("]") {
          Some(end_param) if end_param > start =>
            rest[start:end_param + 1].to_owned()
          _ => ""
        }
      _ => ""
    }
    if name != "" {
      return Some((name, type_param_suffix))
    }
  }
  None
}

///|
fn collect_bridge_struct_decls(bridge_mbt : String) -> Array[BridgeStructDecl] {
  let decls : Array[BridgeStructDecl] = []
  let mut current_name : String? = None
  let mut current_type_param_suffix = ""
  let mut fields : Array[String] = []
  for line_view in bridge_mbt.split("\n") {
    let line = line_view.to_owned().trim().to_owned()
    match current_name {
      Some(name) =>
        if line == "}" {
          decls.push({
            name,
            type_param_suffix: current_type_param_suffix,
            fields,
          })
          current_name = None
          current_type_param_suffix = ""
          fields = []
        } else if line.has_prefix("//") || line == "" {
          continue
        } else if line.contains(" : ") {
          fields.push(line)
        }
      None =>
        match parse_bridge_struct_header_line(line) {
          Some((name, type_param_suffix)) => {
            current_name = Some(name)
            current_type_param_suffix = type_param_suffix
            fields = []
          }
          None => ()
        }
    }
  }
  decls
}

///|
/// Collect the public-interface form of each index-signature accessor
/// (`index_get` / `index_set`) emitted into `bridge.mbt`, keyed by the
/// struct's type name. The FFI side renders these as
/// `#alias("_[_]")` + `pub extern "js" fn Foo::index_get(...) -> V? = #| <js
/// body>`; the `.mbti` form drops the `extern "js"` keyword and the trailing
/// JS body so the generated contract advertises that `Foo` supports
/// `foo[key]` indexing instead of presenting a bare, seemingly field-less
/// struct.
///
/// The `#alias(...)` line is carried through, and it is not decoration: it
/// is what makes `foo[key]` resolve. Emitting the signature without it
/// would advertise a method called `index_get` and silently drop the
/// operator from the published interface. `moon info` writes the attribute
/// on its own line above the signature, and this matches that.
///
/// The accessors were `op_get` / `op_set` until newer MoonBit deprecated
/// declaring the operator under those reserved names. Matching on the name
/// is why this had to move in lockstep with the emitter.
fn collect_bridge_index_accessor_mbti(
  bridge_mbt : String,
) -> Map[String, Array[String]] {
  let marker = "pub extern \"js\" fn "
  let plain_marker = "pub fn "
  let result : Map[String, Array[String]] = Map([])
  let mut pending_alias = ""
  for line_view in bridge_mbt.split("\n") {
    let trimmed = line_view.to_owned().trim().to_owned()
    // Remember an attribute line so it can be attached to the declaration
    // it precedes; anything else clears it, so an attribute never drifts
    // onto an unrelated signature further down the file.
    if trimmed.has_prefix("#alias(") {
      pending_alias = trimmed
      continue
    }
    let alias_ = pending_alias
    pending_alias = ""
    // The enum-valued setter is a plain `pub fn` wrapper over a private
    // extern rather than an extern itself, so both forms are accepted.
    let used_marker = if trimmed.has_prefix(marker) {
      marker
    } else if trimmed.has_prefix(plain_marker) {
      plain_marker
    } else {
      continue
    }
    if !(trimmed.contains("::index_get(") || trimmed.contains("::index_set(")) {
      continue
    }
    let rest = trimmed[used_marker.length():].to_owned()
    let name = match rest.find("::") {
      Some(idx) => rest[:idx].to_owned()
      None => continue
    }
    // Drop the trailing ` =` that precedes the multi-line `#|` JS body, or
    // the ` {` that opens a wrapper body.
    let mut sig = rest.trim().to_owned()
    if sig.has_suffix("=") || sig.has_suffix("{") {
      sig = sig[:sig.length() - 1].to_owned().trim().to_owned()
    }
    let mbti_line = if alias_ == "" {
      "pub fn \{sig}"
    } else {
      alias_ + "\npub fn \{sig}"
    }
    let entry = result.get(name).unwrap_or([])
    if !entry.contains(mbti_line) {
      entry.push(mbti_line)
    }
    result[name] = entry
  }
  result
}

///|
fn find_bridge_struct_decl(
  decls : Array[BridgeStructDecl],
  name : String,
) -> BridgeStructDecl? {
  for decl in decls {
    if decl.name == name {
      return Some(decl)
    }
  }
  None
}

///|
fn render_bridge_struct_mbti_decl(decl : BridgeStructDecl) -> String {
  let lines : Array[String] = [
    "pub(all) struct \{decl.name}\{decl.type_param_suffix} {",
  ]
  for field in decl.fields {
    lines.push("  " + field)
  }
  lines.push("}")
  lines.join("\n")
}

///|
fn expose_bridge_struct_decls_in_mbti(
  bridge_mbti : String,
  bridge_mbt : String,
) -> String {
  let struct_decls = collect_bridge_struct_decls(bridge_mbt)
  if struct_decls.is_empty() {
    return bridge_mbti
  }
  let accessors = collect_bridge_index_accessor_mbti(bridge_mbt)
  let lines : Array[String] = []
  for line_view in bridge_mbti.split("\n") {
    let line = line_view.to_owned()
    let trimmed = line.trim().to_owned()
    match parse_bridge_public_type_name_line(trimmed) {
      Some(name) =>
        match find_bridge_struct_decl(struct_decls, name) {
          Some(decl) => {
            let mut rendered = render_bridge_struct_mbti_decl(decl)
            match accessors.get(name) {
              Some(accessor_lines) =>
                for accessor in accessor_lines {
                  rendered = rendered + "\n\n///|\n" + accessor
                }
              None => ()
            }
            lines.push(rendered)
          }
          None => lines.push(line)
        }
      None => lines.push(line)
    }
  }
  lines.join("\n")
}

///|
fn parse_bridge_first_param_type(params_src : String) -> String? {
  if params_src.trim() == "" {
    return None
  }
  let first_param_src = match params_src.find(",") {
    Some(index) => params_src[:index].to_owned()
    None => params_src
  }
  let first_param = first_param_src.trim().to_owned()
  match first_param.find(":") {
    Some(index) => {
      let type_src = first_param[index + 1:].to_owned().trim().to_owned()
      if type_src == "" {
        return None
      }
      let normalized = if type_src.has_suffix("?") {
        type_src[:type_src.length() - 1].to_owned()
      } else {
        type_src
      }
      Some(normalized.trim().to_owned())
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
  let target_name = public_name[2:].to_owned()
  if type_names.contains(target_name) {
    Some(target_name)
  } else {
    None
  }
}

///|
fn collect_bridge_type_guard_helpers(
  bridge_mbti : String,
  bridge_mbt : String,
) -> Array[BridgeTypeGuardHelper] {
  let type_names = collect_bridge_public_type_names(bridge_mbti)
  let implemented_type_names = collect_bridge_implemented_type_names(bridge_mbt)
  let helpers : Array[BridgeTypeGuardHelper] = []
  let seen_helpers : Array[String] = []
  for line_view in bridge_mbti.split("\n") {
    let line = line_view.to_owned().trim().to_owned()
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
        if !implemented_type_names.contains(target_type) {
          continue
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
/// Arity of every type DECLARED in the assembled source text, scanned
/// from `pub(all) struct X[..]` / `pub type X[..]` /
/// `declare pub type X[..]` lines. Used to validate generated upcast
/// helpers against what actually got emitted.
fn bridge_declared_type_arities(text : String) -> Map[String, Int] {
  let arities : Map[String, Int] = Map([])
  for line_view in text.split("\n") {
    let line = line_view.to_owned().trim().to_owned()
    let rest = if line.has_prefix("pub(all) struct ") {
      line["pub(all) struct ".length():].to_owned()
    } else if line.has_prefix("pub type ") && !line.contains(" = ") {
      line["pub type ".length():].to_owned()
    } else if line.has_prefix("declare pub type ") {
      line["declare pub type ".length():].to_owned()
    } else {
      continue
    }
    let name_end = match rest.find("[") {
      Some(index) => index
      None =>
        match rest.find(" ") {
          Some(index) => index
          None => rest.length()
        }
    }
    let name = rest[:name_end].to_owned().trim().to_owned()
    if name == "" {
      continue
    }
    let arity = match rest.find("[") {
      Some(open) =>
        match bridge_find_matching_paren_char(rest, open, '[', ']') {
          Some(close) =>
            bridge_split_top_level_commas(rest[open + 1:close].to_owned()).length()
          None => 0
        }
      None => 0
    }
    // First declaration wins (matches how duplicate emissions resolve).
    if !(arities.get(name) is Some(_)) {
      arities[name] = arity
    }
  }
  arities
}

///|
fn bridge_find_matching_paren_char(
  text : String,
  open_index : Int,
  open_char : Char,
  close_char : Char,
) -> Int? {
  let mut depth = 0
  for i, c in text.iter2() {
    if i < open_index {
      continue
    }
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
/// Validate a generated `::as<Base>` upcast helper line against the
/// arities actually emitted: TypeScript names that collide after
/// sanitization (zod's `$ZodType<3 params>` and `_ZodType<1 param>`
/// both become `UnderscoreZodType`) can leave the helper referencing an
/// arity the surviving declaration does not have. Returns `false` when
/// the helper must be dropped.
fn bridge_upcast_helper_line_is_valid(
  line : String,
  arities : Map[String, Int],
) -> Bool {
  let marker = "::as"
  if !line.contains(marker) || !line.contains("(self : ") {
    return true
  }
  let arrow = match line.find(") -> ") {
    Some(index) => index
    None => return true
  }
  let mut ret = line[arrow + ") -> ".length():].to_owned().trim().to_owned()
  if ret.has_suffix(" = \"%identity\"") {
    ret = ret[:ret.length() - " = \"%identity\"".length()]
      .to_owned()
      .trim()
      .to_owned()
  }
  let (head, args_count) = match ret.find("[") {
    Some(open) =>
      match bridge_find_matching_paren_char(ret, open, '[', ']') {
        Some(close) =>
          (
            ret[:open].to_owned(),
            bridge_split_top_level_commas(ret[open + 1:close].to_owned()).length(),
          )
        None => (ret[:open].to_owned(), 0)
      }
    None => (ret, 0)
  }
  match arities.get(head) {
    Some(declared) => declared == args_count
    None => false
  }
}

///|
/// Drop upcast helper lines whose base reference does not match the
/// emitted declaration (see `bridge_upcast_helper_line_is_valid`).
/// Applied to BOTH the mbt and the mbti with the mbt's arities, so the
/// two surfaces keep the same helper set.
fn prune_mismatched_upcast_helpers(
  bridge_mbti : String,
  bridge_mbt : String,
) -> (String, String) {
  let arities = bridge_declared_type_arities(bridge_mbt)
  let keep_mbt : Array[String] = []
  for line_view in bridge_mbt.split("\n") {
    let line = line_view.to_owned()
    if line.contains("::as") &&
      line.contains("%identity") &&
      !bridge_upcast_helper_line_is_valid(line.trim().to_owned(), arities) {
      continue
    }
    keep_mbt.push(line)
  }
  let keep_mbti : Array[String] = []
  for line_view in bridge_mbti.split("\n") {
    let line = line_view.to_owned()
    if line.has_prefix("declare pub") &&
      line.contains("::as") &&
      !bridge_upcast_helper_line_is_valid(line.trim().to_owned(), arities) {
      continue
    }
    keep_mbti.push(line)
  }
  (keep_mbti.join("\n"), keep_mbt.join("\n"))
}

///|
/// The top-level function name a `declare pub fn NAME(...)` line declares.
/// `None` for any other line, and for a `Type::method` form — those are not
/// what `parse_bridge_pub_extern_fn_decl_line` produces, so they can never
/// collide with a derived declaration.
fn bridge_mbti_declared_fn_name(line : String) -> String? {
  let prefix = "declare pub fn "
  if !line.has_prefix(prefix) {
    return None
  }
  let rest = line[prefix.length():].to_owned()
  match rest.find("(") {
    Some(open) => {
      let name = rest[:open].to_owned()
      if name == "" || name.contains("::") {
        None
      } else {
        Some(name)
      }
    }
    None => None
  }
}

///|
/// Names of the PAYLOAD-bearing `pub(all) enum`s this package declares.
///
/// A payload-free enum -- what a TypeScript numeric or string-literal union
/// lowers to -- is an integer or string tag at the JS boundary, and that is
/// the family `collect_bridge_enum_converters` handles. Only a
/// payload-bearing one is a tagged union, whose JS representation is
/// `{ "$tag": i, "_0": v }`.
fn collect_bridge_payload_enum_names(bridge_mbt : String) -> Array[String] {
  let names : Array[String] = []
  let prefix = "pub(all) enum "
  let mut current = ""
  for line_view in bridge_mbt.split("\n") {
    let trimmed = line_view.to_owned().trim().to_owned()
    if trimmed.has_prefix(prefix) && trimmed.has_suffix("{") {
      let rest = trimmed[prefix.length():trimmed.length() - 1]
        .to_owned()
        .trim()
        .to_owned()
      current = if rest.contains("[") { "" } else { rest }
      continue
    }
    if current == "" {
      continue
    }
    if trimmed == "}" {
      current = ""
      continue
    }
    // `Case(Payload)` is a payload-bearing constructor; a bare `Case` is not.
    if trimmed.contains("(") && !names.contains(current) {
      names.push(current)
    }
  }
  names
}

///|
/// `(name, params_src, return_type)` for a `<prefix>NAME(params) -> RET` line,
/// accepting a `Type::method` name where
/// `parse_bridge_top_level_fn_decl_line` and
/// `parse_bridge_pub_extern_fn_decl_line` both reject one -- they feed the
/// public-wrapper machinery, which is about top-level names only. The trailing
/// ` = "..."` / ` =` of an extern is cut, so one parse serves both surfaces.
fn bridge_split_fn_decl_line(
  line : String,
  prefix : String,
) -> (String, String, String)? {
  if !line.has_prefix(prefix) {
    return None
  }
  let rest = line[prefix.length():].to_owned()
  let open = match rest.find("(") {
    Some(i) => i
    None => return None
  }
  let close = match bridge_find_matching_paren(rest, open) {
    Some(i) => i
    None => return None
  }
  let name = rest[:open].to_owned().trim().to_owned()
  if name == "" {
    return None
  }
  let params_src = rest[open + 1:close].to_owned()
  let after = rest[close + 1:].to_owned().trim().to_owned()
  if !after.has_prefix("->") {
    return None
  }
  let return_src = after[2:].to_owned().trim().to_owned()
  let return_type = match return_src.find("=") {
    Some(i) => return_src[:i].to_owned().trim().to_owned()
    None => return_src
  }
  if return_type == "" {
    return None
  }
  Some((name, params_src, return_type))
}

///|
/// Split a declared type into `(base, is_optional)`.
fn bridge_split_optional_type(type_src : String) -> (String, Bool) {
  let trimmed = type_src.trim().to_owned()
  if trimmed.has_suffix("?") {
    (trimmed[:trimmed.length() - 1].to_owned().trim().to_owned(), true)
  } else {
    (trimmed, false)
  }
}

///|
/// Make a `declare pub fn` line's RETURN type agree with the extern that
/// implements it, for the one decision the two layers make separately and can
/// therefore disagree about: a tagged-union return the bridge cannot BUILD at
/// runtime.
///
/// `ffi_widen_unbuildable_union_outputs` widens such a return to `JSValue`,
/// because no `_from_js` exists for it and the extern binds straight to the
/// raw JS function. That decision needs `MoonBitJsFfiState`. The `.mbti` line
/// comes from the DECL layer (`func_decl_to_moonbit` -> `moonbit_type_name`),
/// which holds no such state, and `add_bridge_public_wrappers` renders the
/// public wrapper FROM that line -- so one export has THREE renderings and
/// only the ffi one moved. `[4014] Expr Type Mismatch: has type JSValue?,
/// wanted Auto_...?` is what came out, and reverting the widening twice on
/// that message is what kept the erased-payload backlog open.
///
/// Located by instrumenting rather than reading: markers in the three
/// `declare pub fn` renderers of `parser_moonbit.mbt` attributed 0 of 11
/// lines, and the reason was the FIXTURE -- a class-only `.d.ts` declares no
/// top-level function, so `func_decl_to_moonbit` was never called. A zero
/// from a probe whose shape is absent is not an answer.
///
/// Scoped rather than blanket, and that is the whole difficulty: a `.mbti`
/// return type differing from its extern's is the NORMAL case. A literal-union
/// enum crosses as an `Int` and the wrapper converts it; an opaque type
/// arrives as `JSValue` and the wrapper wraps it in an option. Rewriting on
/// "they differ" would delete both families of wrapper. The extern handing
/// back `JSValue` at the SAME optionality as the declaration already excludes
/// both of those -- a literal enum crosses as `Int` or `String`, and the
/// option wrap turns a non-optional `JSValue` into a `T?`.
///
/// On top of that, the declared type has to be one of the two things the
/// widening can leave behind, and it takes both because they are the same
/// event seen from either side. When the union is mentioned somewhere else in
/// the package -- `Auto_IdentifierValue_or_PrivateIdentifierValue` is also a
/// PARAMETER of `idText` -- the enum stays declared and the stale declaration
/// is `[4014] has type JSValue?, wanted Auto_...?`. When the widened return
/// was the union's only mention, nothing synthesizes the enum any more and
/// the same stale declaration is `[4032] the type Auto_... is undefined`.
/// Writing only the first half is what made `walkUpBindingElementsAndPatterns`
/// fail to compile while `getNameOfJSDocTypedef` came out right.
fn reconcile_bridge_widened_union_returns(
  bridge_mbti : String,
  bridge_mbt : String,
) -> String {
  let payload_enums = collect_bridge_payload_enum_names(bridge_mbt)
  let implemented = collect_bridge_implemented_type_names(bridge_mbt)
  // A top-level extern is named for its snake_case binding
  // (`get_name_of_jsdoc_typedef`); a member extern keeps the `Type::method`
  // spelling the declaration uses. Both are keyed here under the name the
  // `.mbti` side will look up.
  let extern_returns : Map[String, String] = Map([])
  for line_view in bridge_mbt.split("\n") {
    let line = line_view.to_owned().trim().to_owned()
    match bridge_split_fn_decl_line(line, "pub extern \"js\" fn ") {
      Some((name, _, return_type)) =>
        if !extern_returns.contains(name) {
          extern_returns[name] = return_type
        }
      None => ()
    }
  }
  let kept : Array[String] = []
  for line_view in bridge_mbti.split("\n") {
    let line = line_view.to_owned()
    let mut rewritten : String? = None
    // Only an unindented line, so a nested declaration is left verbatim
    // rather than reconstructed without its indentation.
    if line == line.trim().to_owned() {
      match bridge_split_fn_decl_line(line, "declare pub fn ") {
        Some((name, params_src, declared_ret)) => {
          let (declared, declared_opt) = bridge_split_optional_type(
            declared_ret,
          )
          // A bare identifier only: a generic instantiation (`Token[JSValue]`)
          // is not a name either list can be consulted about, and reading one
          // as absent would rewrite a return the widening never touched.
          let is_plain_name = declared != "" &&
            declared != "JSValue" &&
            !declared.contains("[") &&
            !declared.contains("(") &&
            !declared.contains(" ")
          let extern_key = if name.contains("::") {
            name
          } else {
            bridge_value_fn_name(name)
          }
          if is_plain_name &&
            (
              payload_enums.contains(declared) ||
              !implemented.contains(declared)
            ) {
            match extern_returns.get(extern_key) {
              Some(extern_ret) => {
                let (ext_base, ext_opt) = bridge_split_optional_type(extern_ret)
                if ext_base == "JSValue" && ext_opt == declared_opt {
                  rewritten = Some(
                    "declare pub fn \{name}(\{params_src}) -> \{extern_ret}",
                  )
                }
              }
              None => ()
            }
          }
        }
        None => ()
      }
    }
    match rewritten {
      Some(next) => kept.push(next)
      None => kept.push(line)
    }
  }
  kept.join("\n")
}

///|
/// Derive a `declare pub fn` for every emitted extern, and make the `.mbti`
/// AGREE with the `.mbt` rather than merely accumulate beside it.
///
/// The guard here used to be `if !next_bridge_mbti.contains(helper_decl)` — a
/// substring test on the whole file using the full SIGNATURE, which asks "is
/// this exact line already present" where the question is "is this FUNCTION
/// already declared". MoonBit has no overloading, so two `pub fn` of one name
/// cannot both exist in a package; a second `declare pub fn` of that name is
/// therefore always wrong, and the `.mbt` is the one that says what the
/// package really is.
///
/// While the two layers happened to render the same text the duplication was
/// invisible, which is why it survived: the decl layer describes an exported
/// value independently of the ffi layer, and widening a tagged-union RETURN
/// made two renderings of `get_create_adaptor_server` differ for the first
/// time. Four cases in the corpus, all the same shape — the stale line is the
/// less precise one (`get_serve() -> JSValue` against the impl's
/// `() -> (Options, cb?) -> JSValue`, `mkdir`'s `callback : JSValue` against
/// its real callback type), except `get_create_adaptor_server`, whose stale
/// line was MORE precise and simply untrue.
///
/// Replacing in place rather than appending is what makes the agreement hold
/// by construction, so the next disagreement cannot hide the same way. Keyed
/// on the name via one map lookup per line, not a scan per name: the
/// `typescript` package has 2,161 of these, and a nested scan there is the
/// quadratic this repo keeps paying for.
fn add_bridge_ergonomic_helper_decls(
  bridge_mbti : String,
  bridge_mbt : String,
) -> String {
  let derived_names : Array[String] = []
  let derived_decl : Map[String, String] = Map([])
  for line_view in bridge_mbt.split("\n") {
    let line = line_view.to_owned().trim().to_owned()
    match parse_bridge_pub_extern_fn_decl_line(line) {
      Some(fn_decl) => {
        let helper_decl = "declare pub fn \{fn_decl.public_name}(\{fn_decl.params_src}) -> \{fn_decl.return_type}"
        if !derived_decl.contains(fn_decl.public_name) {
          derived_names.push(fn_decl.public_name)
          derived_decl[fn_decl.public_name] = helper_decl
        }
      }
      None => ()
    }
  }
  let consumed : Array[String] = []
  let kept : Array[String] = []
  for line_view in bridge_mbti.split("\n") {
    let line = line_view.to_owned()
    let mut rewritten = false
    match bridge_mbti_declared_fn_name(line) {
      Some(name) =>
        match derived_decl.get(name) {
          Some(decl) => {
            // First occurrence becomes the impl's own signature; a further
            // declaration of the same name is dropped, since only one can
            // exist.
            if !consumed.contains(name) {
              consumed.push(name)
              kept.push(decl)
            }
            rewritten = true
          }
          None => ()
        }
      None => ()
    }
    if !rewritten {
      kept.push(line)
    }
  }
  let mut next_bridge_mbti = kept.join("\n")
  for name in derived_names {
    if !consumed.contains(name) {
      next_bridge_mbti += "\n\n///|\n" + derived_decl.get(name).unwrap()
    }
  }
  for helper in collect_bridge_type_guard_helpers(bridge_mbti, bridge_mbt) {
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
fn bridge_enum_to_js_name(type_name : String) -> String {
  "__ts_mbt_" + bridge_to_snake_case(type_name) + "_to_js"
}

///|
fn bridge_enum_from_js_name(type_name : String) -> String {
  "__ts_mbt_" + bridge_to_snake_case(type_name) + "_from_js"
}

///|
fn bridge_enum_to_js_optional_name(type_name : String) -> String {
  bridge_enum_to_js_name(type_name) + "_optional"
}

///|
fn bridge_enum_from_js_optional_name(type_name : String) -> String {
  bridge_enum_from_js_name(type_name) + "_optional"
}

///|
fn collect_bridge_enum_converters(
  bridge_mbti : String,
  bridge_mbt : String,
) -> Array[BridgeEnumConverter] {
  let converters : Array[BridgeEnumConverter] = []
  for type_name in collect_bridge_public_type_names(bridge_mbti) {
    let to_js_name = bridge_enum_to_js_name(type_name)
    let from_js_name = bridge_enum_from_js_name(type_name)
    let to_js_optional_name = bridge_enum_to_js_optional_name(type_name)
    let from_js_optional_name = bridge_enum_from_js_optional_name(type_name)
    for raw_type in ["String", "Int", "Double"] {
      if bridge_mbt.contains(
          "fn \{to_js_name}(value : \{type_name}) -> \{raw_type}",
        ) &&
        bridge_mbt.contains(
          "fn \{from_js_name}(value : \{raw_type}) -> \{type_name}",
        ) &&
        bridge_mbt.contains(
          "fn \{to_js_optional_name}(value : \{type_name}?) -> \{raw_type}?",
        ) &&
        bridge_mbt.contains(
          "fn \{from_js_optional_name}(value : \{raw_type}?) -> \{type_name}?",
        ) {
        converters.push({
          type_name,
          to_js_name,
          from_js_name,
          to_js_optional_name,
          from_js_optional_name,
        })
        break
      }
    }
  }
  converters
}

///|
fn find_bridge_enum_converter(
  converters : Array[BridgeEnumConverter],
  type_name : String,
) -> BridgeEnumConverter? {
  let normalized = type_name.trim().to_owned()
  for converter in converters {
    if converter.type_name == normalized {
      return Some(converter)
    }
  }
  None
}

///|
fn bridge_type_optional_base_name(type_name : String) -> String? {
  let trimmed = type_name.trim().to_owned()
  if !trimmed.has_suffix("?") {
    return None
  }
  let base = trimmed[:trimmed.length() - 1].to_owned().trim().to_owned()
  if base == "" {
    None
  } else {
    Some(base)
  }
}

///|
fn find_bridge_enum_converter_for_type(
  converters : Array[BridgeEnumConverter],
  type_name : String,
) -> (BridgeEnumConverter, Bool)? {
  match bridge_type_optional_base_name(type_name) {
    Some(base) =>
      match find_bridge_enum_converter(converters, base) {
        Some(converter) => Some((converter, true))
        None => None
      }
    None =>
      match find_bridge_enum_converter(converters, type_name) {
        Some(converter) => Some((converter, false))
        None => None
      }
  }
}

///|
fn bridge_fn_decl_needs_enum_conversion(
  fn_decl : BridgeTopLevelFnDecl,
  converters : Array[BridgeEnumConverter],
) -> Bool {
  for param in parse_bridge_param_decls(fn_decl.params_src) {
    match find_bridge_enum_converter_for_type(converters, param.type_name) {
      Some(_) => return true
      None => ()
    }
  }
  match find_bridge_enum_converter_for_type(converters, fn_decl.return_type) {
    Some(_) => true
    None => false
  }
}

///|
fn bridge_arg_expr_for_type(
  converters : Array[BridgeEnumConverter],
  arg_name : String,
  type_name : String,
) -> String {
  match find_bridge_enum_converter_for_type(converters, type_name) {
    Some((converter, is_optional)) =>
      if is_optional {
        "\{converter.to_js_optional_name}(\{arg_name})"
      } else {
        "\{converter.to_js_name}(\{arg_name})"
      }
    None => arg_name
  }
}

///|
fn bridge_return_expr_for_type(
  converters : Array[BridgeEnumConverter],
  return_type : String,
  call_expr : String,
) -> String {
  match find_bridge_enum_converter_for_type(converters, return_type) {
    Some((converter, is_optional)) =>
      return if is_optional {
        "\{converter.from_js_optional_name}(\{call_expr})"
      } else {
        "\{converter.from_js_name}(\{call_expr})"
      }
    None => ()
  }
  // Nested enum inside a generic argument (`NormalizeAction[NormalizeForm?]`):
  // the raw extern returns the type with the enum collapsed to its primitive
  // (`NormalizeAction[String?]`) and MoonBit's structural type checker
  // rejects the assignment. Both representations share an identical runtime
  // layout — `NormalizeAction` is opaque and the inner enum was already
  // bridged to a primitive at the JS boundary — so an `unsafeCast` is
  // layout-safe. Public consumers that need to read the enum back must use a
  // dedicated converter helper; this only restores parity for round-tripping.
  if bridge_return_type_contains_nested_enum(converters, return_type) {
    return "unsafeCast(\{call_expr})"
  }
  call_expr
}

///|
fn bridge_return_type_contains_nested_enum(
  converters : Array[BridgeEnumConverter],
  return_type : String,
) -> Bool {
  if !return_type.contains("[") {
    return false
  }
  for converter in converters {
    let needle = converter.type_name
    if return_type.contains("[" + needle) ||
      return_type.contains(", " + needle) ||
      return_type.contains(" " + needle) {
      return true
    }
  }
  false
}

///|
/// Opaque (`declare pub type X`) names from the `.mbti` surface. Optional
/// returns of these types (plus `JSValue` / `Double` / arrays / function
/// types) use MoonBit's boxed `Option` repr, so raw `value | undefined`
/// extern returns break `match` — see `ffi_option_return_inner_is_boxed`
/// in `moonbit_js_ffi.mbt`, whose unboxed/boxed split this mirrors from
/// the `.mbti` side.
fn collect_bridge_opaque_type_names(bridge_mbti : String) -> Array[String] {
  let names : Array[String] = []
  let prefix = "declare pub type "
  for line_view in bridge_mbti.split("\n") {
    let line = line_view.to_owned().trim().to_owned()
    if !line.has_prefix(prefix) {
      continue
    }
    let rest = line[prefix.length():].to_owned()
    let name = match rest.find("[") {
      Some(index) => rest[:index].to_owned()
      None => rest
    }
    let trimmed = name.trim().to_owned()
    if trimmed != "" && !names.contains(trimmed) {
      names.push(trimmed)
    }
  }
  names
}

///|
fn bridge_optional_return_needs_wrap(
  opaque_type_names : Array[String],
  return_type : String,
) -> Bool {
  let inner = match ffi_rendered_return_type_optional_inner(return_type) {
    Some(inner) => inner
    None => return false
  }
  // Function / tuple types are always boxed.
  if inner.has_prefix("(") {
    return true
  }
  if inner == "JSValue" || inner == "Double" || inner == "Float" {
    return true
  }
  if inner.has_prefix("Array[") ||
    inner.has_prefix("FixedArray[") ||
    inner.has_prefix("Map[") ||
    inner.has_prefix("Promise[") ||
    inner.has_prefix("Iter[") {
    return true
  }
  let base = match inner.find("[") {
    Some(index) => inner[:index].to_owned()
    None => inner
  }
  opaque_type_names.contains(base)
}

///|
fn bridge_fn_decl_needs_option_return_wrap(
  fn_decl : BridgeTopLevelFnDecl,
  converters : Array[BridgeEnumConverter],
  opaque_type_names : Array[String],
) -> Bool {
  // Enum-converted returns already produce MoonBit values via
  // `_from_js_optional`; wrapping them again would be wrong.
  match find_bridge_enum_converter_for_type(converters, fn_decl.return_type) {
    Some(_) => return false
    None => ()
  }
  bridge_optional_return_needs_wrap(opaque_type_names, fn_decl.return_type)
}

///|
/// Mirror of `ffi_option_return_wrap_helper_decls` in
/// `moonbit_js_ffi.mbt` for packages where only the top-level wrapper
/// pass needs it. `contains` checks on the definition keep the two
/// injection points from duplicating it.
let bridge_option_return_wrap_helper_decls : String = "extern \"js\" fn __ts_mbt_option_return_is_absent(value : JSValue) -> Bool =\n  #| (value) => value === undefined || value === null\n\nfn[T] __ts_mbt_option_return_value(raw : JSValue) -> T = \"%identity\"\n\nfn[T] __ts_mbt_wrap_option_return(raw : JSValue) -> T? {\n  if __ts_mbt_option_return_is_absent(raw) {\n    None\n  } else {\n    Some(__ts_mbt_option_return_value(raw))\n  }\n}"

///|
fn render_bridge_public_wrapper_with_converters(
  fn_decl : BridgeTopLevelFnDecl,
  converters : Array[BridgeEnumConverter],
  internal_name : String,
  wrap_option_return? : Bool = false,
) -> String? {
  if bridge_value_identifier_needs_suffix(fn_decl.public_name) {
    return None
  }
  let needs_conversion = bridge_fn_decl_needs_enum_conversion(
    fn_decl, converters,
  )
  let lowered_params_src = bridge_lowered_async_callback_params_src(
    fn_decl.params_src,
  )
  if internal_name == "" ||
    (
      !needs_conversion &&
      !wrap_option_return &&
      lowered_params_src is None &&
      internal_name == fn_decl.public_name
    ) {
    return None
  }
  let param_decls = parse_bridge_param_decls(fn_decl.params_src)
  let call_args : Array[String] = []
  for i, arg_name in fn_decl.arg_names {
    let type_name = if i < param_decls.length() {
      param_decls[i].type_name
    } else {
      ""
    }
    match @parser.moonbit_async_callback_lowering(type_name) {
      Some(lowering) =>
        call_args.push(
          @parser.moonbit_async_callback_glue_expr(arg_name, lowering),
        )
      None =>
        call_args.push(
          bridge_arg_expr_for_type(converters, arg_name, type_name),
        )
    }
  }
  let call_expr = if call_args.length() == 0 {
    internal_name + "()"
  } else {
    internal_name + "(" + call_args.join(", ") + ")"
  }
  let body_expr = if wrap_option_return {
    // The raw extern keeps its declared `T?` return type, but the value
    // crossing the boundary is the raw JS `value | undefined | null` —
    // construct the `Option` on the MoonBit side instead of trusting it.
    "__ts_mbt_wrap_option_return(unsafeCast(\{call_expr}))"
  } else {
    bridge_return_expr_for_type(converters, fn_decl.return_type, call_expr)
  }
  let public_params_src = match lowered_params_src {
    Some(src) => src
    None => fn_decl.params_src
  }
  Some(
    "pub fn \{fn_decl.public_name}(\{public_params_src}) -> \{fn_decl.return_type} {\n  \{body_expr}\n}",
  )
}

///|
fn inject_bridge_public_type_aliases(
  bridge_mbti : String,
  bridge_mbt : String,
) -> String {
  let mut next_bridge_mbt = bridge_mbt
  // Match the public-interface forward declarations from `bridge.mbti`
  // with self-contained `#external` definitions in `bridge.mbt` so the
  // generated package compiles without a `mizchi/js` dependency.
  if bridge_mbti.contains("declare pub type Promise[X]") &&
    !next_bridge_mbt.contains("#external\npub type Promise[X]") {
    next_bridge_mbt = "#external\npub type Promise[X]\n\n" + next_bridge_mbt
  }
  if bridge_mbti.contains("declare pub type JSValue") &&
    !next_bridge_mbt.contains("#external\npub type JSValue") {
    next_bridge_mbt = "#external\npub type JSValue\n\n" + next_bridge_mbt
  }
  if (
      bridge_mbti.contains("declare pub type JSValue") ||
      next_bridge_mbt.contains("#external\npub type JSValue")
    ) &&
    !next_bridge_mbt.contains("pub fn JSValue::from_string") {
    // Typed entry points into the JSValue boundary: primitives are
    // identity-representable on the js backend, and the pair builder
    // covers heterogeneous object literals (`{ name: "x", age: 42 }`)
    // that MoonBit map/struct literals can't express — both previously
    // forced callers through bare `unsafeCast`.
    let jsvalue_constructors = "pub fn JSValue::from_string(value : String) -> JSValue = \"%identity\"\n\npub fn JSValue::from_double(value : Double) -> JSValue = \"%identity\"\n\npub fn JSValue::from_int(value : Int) -> JSValue = \"%identity\"\n\npub fn JSValue::from_bool(value : Bool) -> JSValue = \"%identity\"\n\npub fn JSValue::from_array(value : Array[JSValue]) -> JSValue = \"%identity\"\n\nextern \"js\" fn __ts_mbt_js_object_from_pairs(keys : Array[String], values : Array[JSValue]) -> JSValue =\n  #| (keys, values) => { const out = {}; for (let i = 0; i < keys.length; i++) out[keys[i]] = values[i]; return out; }\n\npub fn JSValue::object_from_pairs(pairs : Array[(String, JSValue)]) -> JSValue {\n  let keys : Array[String] = []\n  let values : Array[JSValue] = []\n  for pair in pairs {\n    keys.push(pair.0)\n    values.push(pair.1)\n  }\n  __ts_mbt_js_object_from_pairs(keys, values)\n}"
    next_bridge_mbt = jsvalue_constructors + "\n\n" + next_bridge_mbt
  }
  let type_aliases : Array[String] = []
  let implemented_type_names = collect_bridge_implemented_type_names(
    next_bridge_mbt,
  )
  for line_view in bridge_mbti.split("\n") {
    let line = line_view.to_owned().trim().to_owned()
    if line.has_prefix("pub type ") && line.contains(" = ") {
      match parse_bridge_implemented_type_name_line(line) {
        Some(type_name) =>
          if !implemented_type_names.contains(type_name) &&
            !next_bridge_mbt.contains(line) &&
            !type_aliases.contains(line) {
            implemented_type_names.push(type_name)
            type_aliases.push(line)
          }
        None => ()
      }
    }
  }
  if type_aliases.length() > 0 {
    next_bridge_mbt = type_aliases.join("\n") + "\n\n" + next_bridge_mbt
  }
  next_bridge_mbt
}

///|
/// Returns the rewritten `(bridge_mbt, bridge_mbti)` pair: the mbt gains
/// the natural-name public wrappers, and any `declare pub fn` line whose
/// wrapper lowered an async-callback param is rewritten to the lowered
/// signature so the interface keeps describing the real public surface.
fn add_bridge_public_wrappers(
  bridge_mbti : String,
  bridge_mbt : String,
) -> (String, String) {
  let mut next_bridge_mbt = inject_bridge_public_type_aliases(
    bridge_mbti, bridge_mbt,
  )
  let mut next_bridge_mbti = bridge_mbti
  let enum_converters = collect_bridge_enum_converters(
    bridge_mbti, next_bridge_mbt,
  )
  let opaque_type_names = collect_bridge_opaque_type_names(bridge_mbti)
  let wrappers : Array[String] = []
  let mut used_option_return_wrap = false
  for line_view in bridge_mbti.split("\n") {
    let line = line_view.to_owned().trim().to_owned()
    match parse_bridge_top_level_fn_decl_line(line) {
      Some(fn_decl) => {
        let base_internal_name = bridge_value_fn_name(fn_decl.public_name)
        let needs_conversion = bridge_fn_decl_needs_enum_conversion(
          fn_decl, enum_converters,
        )
        let needs_option_wrap = bridge_fn_decl_needs_option_return_wrap(
          fn_decl, enum_converters, opaque_type_names,
        )
        let has_async_callback = bridge_fn_decl_has_async_callback_param(
          fn_decl,
        )
        let internal_name = if (
            needs_conversion || needs_option_wrap || has_async_callback
          ) &&
          base_internal_name == fn_decl.public_name {
          base_internal_name + "_raw"
        } else {
          base_internal_name
        }
        let wrapper = render_bridge_public_wrapper_with_converters(
          fn_decl,
          enum_converters,
          internal_name,
          wrap_option_return=needs_option_wrap,
        )
        match wrapper {
          Some(wrapper) => {
            let raw_decl = "pub extern \"js\" fn \{base_internal_name}("
            if next_bridge_mbt.contains(raw_decl) {
              next_bridge_mbt = next_bridge_mbt.replace(
                old=raw_decl,
                new="extern \"js\" fn \{internal_name}(",
              )
              wrappers.push(wrapper)
              if needs_option_wrap {
                used_option_return_wrap = true
              }
              match
                bridge_lowered_async_callback_params_src(fn_decl.params_src) {
                Some(lowered_src) => {
                  let old_decl = "declare pub fn \{fn_decl.public_name}(\{fn_decl.params_src}) -> \{fn_decl.return_type}"
                  let new_decl = "declare pub fn \{fn_decl.public_name}(\{lowered_src}) -> \{fn_decl.return_type}"
                  if next_bridge_mbti.contains(old_decl) {
                    next_bridge_mbti = next_bridge_mbti.replace(
                      old=old_decl,
                      new=new_decl,
                    )
                  }
                }
                None => ()
              }
            }
          }
          None => ()
        }
      }
      None => ()
    }
  }
  let helpers : Array[String] = []
  if used_option_return_wrap &&
    !next_bridge_mbt.contains("fn[T] __ts_mbt_wrap_option_return") {
    helpers.push(bridge_option_return_wrap_helper_decls)
    // The helper references `JSValue`; make sure the package declares it.
    if !next_bridge_mbt.contains("type JSValue") {
      next_bridge_mbt = "#external\ntype JSValue\n\n" + next_bridge_mbt
    }
  }
  for helper in collect_bridge_type_guard_helpers(bridge_mbti, next_bridge_mbt) {
    // Widen `Token` to `Token[JSValue]` etc. when the target type was
    // emitted with generic parameters so the guard's `unsafeCast` lands
    // on a valid arity.
    let target_arity = bridge_struct_decl_arity(
      next_bridge_mbt,
      helper.target_type,
    )
    let target_with_args = if target_arity > 0 {
      let args : Array[String] = []
      for _ in 0..<target_arity {
        args.push("JSValue")
      }
      let joined = args.join(", ")
      "\{helper.target_type}[\{joined}]"
    } else {
      helper.target_type
    }
    helpers.push(
      "pub fn \{helper.source_type}::\{helper.helper_name}(self : \{helper.source_type}) -> \{target_with_args}? {\n  if \{helper.guard_name}(self) {\n    Some(unsafeCast(self))\n  } else {\n    None\n  }\n}",
    )
  }
  let sections : Array[String] = []
  let helper_text = helpers.join("\n")
  if (
      next_bridge_mbt.contains("unsafeCast(") ||
      helper_text.contains("unsafeCast(")
    ) &&
    !next_bridge_mbt.contains("fn[A, B] unsafeCast(value : A) -> B") {
    sections.push("fn[A, B] unsafeCast(value : A) -> B = \"%identity\"")
  }
  for wrapper in wrappers {
    sections.push(wrapper)
  }
  for helper in helpers {
    if !next_bridge_mbt.contains(helper) {
      sections.push(helper)
    }
  }
  let final_bridge_mbt = if sections.length() == 0 {
    next_bridge_mbt
  } else {
    next_bridge_mbt + "\n\n" + sections.join("\n\n")
  }
  (final_bridge_mbt, next_bridge_mbti)
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
  let base_bridge_mbti = reconcile_bridge_widened_union_returns(
    add_bridge_namespace_public_decls(bundle.decl_mbt, export_surface),
    bundle.ffi_mbt,
  )
  let (bridge_mbt, wrapped_bridge_mbti) = add_bridge_public_wrappers(
    base_bridge_mbti,
    bundle.ffi_mbt,
  )
  let public_bridge_mbti = expose_bridge_struct_decls_in_mbti(
    wrapped_bridge_mbti, bridge_mbt,
  )
  let pre_prune_mbti = add_bridge_ergonomic_helper_decls(
    public_bridge_mbti, bridge_mbt,
  )
  let (bridge_mbti, bridge_mbt) = prune_mismatched_upcast_helpers(
    pre_prune_mbti, bridge_mbt,
  )
  {
    entry_path: bundle.entry_path,
    module_spec: bundle.module_spec,
    moon_pkg: render_bridge_pkg_json(
      bridge_bundle_needs_js_import(bundle) || bridge_mbt.contains("@js."),
    ),
    bridge_mbti,
    bridge_mbt,
    bridge_js: bundle.bridge_js,
  }
}
