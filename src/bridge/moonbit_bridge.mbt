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
/// (`op_get` / `op_set`) emitted into `bridge.mbt`, keyed by the struct's
/// type name. The FFI side renders these as
/// `pub extern "js" fn Foo::op_get(...) -> V? = #| <js body>`; the `.mbti`
/// form drops the `extern "js"` keyword and the trailing JS body so the
/// generated contract advertises that `Foo` supports `foo[key]` indexing
/// instead of presenting a bare, seemingly field-less struct.
fn collect_bridge_index_accessor_mbti(
  bridge_mbt : String,
) -> Map[String, Array[String]] {
  let marker = "pub extern \"js\" fn "
  let result : Map[String, Array[String]] = {}
  for line_view in bridge_mbt.split("\n") {
    let trimmed = line_view.to_owned().trim().to_owned()
    if !trimmed.has_prefix(marker) {
      continue
    }
    if !(trimmed.contains("::op_get(") || trimmed.contains("::op_set(")) {
      continue
    }
    let rest = trimmed[marker.length():].to_owned()
    let name = match rest.find("::") {
      Some(idx) => rest[:idx].to_owned()
      None => continue
    }
    // Drop the trailing ` =` that precedes the multi-line `#|` JS body.
    let mut sig = rest.trim().to_owned()
    if sig.has_suffix("=") {
      sig = sig[:sig.length() - 1].to_owned().trim().to_owned()
    }
    let mbti_line = "pub fn \{sig}"
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
fn add_bridge_ergonomic_helper_decls(
  bridge_mbti : String,
  bridge_mbt : String,
) -> String {
  let mut next_bridge_mbti = bridge_mbti
  for line_view in bridge_mbt.split("\n") {
    let line = line_view.to_owned().trim().to_owned()
    match parse_bridge_pub_extern_fn_decl_line(line) {
      Some(fn_decl) => {
        let helper_decl = "declare pub fn \{fn_decl.public_name}(\{fn_decl.params_src}) -> \{fn_decl.return_type}"
        if !next_bridge_mbti.contains(helper_decl) {
          next_bridge_mbti += "\n\n///|\n" + helper_decl
        }
      }
      None => ()
    }
  }
  let unsafe_cast_decl = "declare pub fn[A, B] unsafeCast(value : A) -> B"
  if !next_bridge_mbti.contains(unsafe_cast_decl) {
    next_bridge_mbti += "\n\n///|\n" + unsafe_cast_decl
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
  if internal_name == "" ||
    (
      !needs_conversion &&
      !wrap_option_return &&
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
    call_args.push(bridge_arg_expr_for_type(converters, arg_name, type_name))
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
  Some(
    "pub fn \{fn_decl.public_name}(\{fn_decl.params_src}) -> \{fn_decl.return_type} {\n  \{body_expr}\n}",
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
fn add_bridge_public_wrappers(
  bridge_mbti : String,
  bridge_mbt : String,
) -> String {
  let mut next_bridge_mbt = inject_bridge_public_type_aliases(
    bridge_mbti, bridge_mbt,
  )
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
        let internal_name = if (needs_conversion || needs_option_wrap) &&
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
            }
          }
          None => ()
        }
      }
      None => ()
    }
  }
  let helpers : Array[String] = [
    "pub fn[A, B] unsafeCast(value : A) -> B = \"%identity\"",
  ]
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
  let base_bridge_mbti = add_bridge_namespace_public_decls(
    bundle.decl_mbt,
    export_surface,
  )
  let bridge_mbt = add_bridge_public_wrappers(base_bridge_mbti, bundle.ffi_mbt)
  let public_bridge_mbti = expose_bridge_struct_decls_in_mbti(
    base_bridge_mbti, bridge_mbt,
  )
  let bridge_mbti = add_bridge_ergonomic_helper_decls(
    public_bridge_mbti, bridge_mbt,
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
