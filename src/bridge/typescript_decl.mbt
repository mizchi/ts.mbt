///|
priv struct TypeScriptDeclNormalizationState {
  named_imports : Array[String]
}

///|
priv struct TypeScriptDeclImportRules {
  ns_alias : String
  module_spec : String
  rules : TypeScriptDeclNormalizationRules
}

///|
priv struct InterfaceExpansion {
  name : String
  type_params : Array[String]
  extends_refs : Array[String]
  body : String
}

///|
priv struct TypeScriptDeclNormalizationRules {
  primitive_aliases : Array[(String, String)]
  fixed_array_aliases : Array[String]
  unboxed_option_aliases : Array[String]
  unboxed_option_as_int_aliases : Array[String]
  generic_alias_expansions : Array[(String, Array[String], String)]
  interface_expansions : Array[InterfaceExpansion]
}

///|

///| `normalize-moonbit-dts` is a readability pass for MoonBit-generated `.d.ts`.

///| It can borrow limited object-shape checks from this package, but it is not

///| intended to reimplement the full TypeScript checker.

///|
fn char_at(s : String, idx : Int) -> Char {
  s[idx].to_int().unsafe_to_char()
}

///|
fn is_ascii_letter(c : Char) -> Bool {
  (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
}

///|
fn is_ascii_digit(c : Char) -> Bool {
  c >= '0' && c <= '9'
}

///|
fn is_ident_char(c : Char) -> Bool {
  is_ascii_letter(c) || is_ascii_digit(c) || c == '_' || c == '$'
}

///|
fn push_unique_string(items : Array[String], value : String) -> Unit {
  if items.contains(value) {
    return
  }
  items.push(value)
}

///|
fn default_normalization_rules() -> TypeScriptDeclNormalizationRules {
  {
    primitive_aliases: [
      ("Unit", "undefined"),
      ("Bool", "boolean"),
      ("Int", "number"),
      ("UInt", "number"),
      ("Char", "number"),
      ("Byte", "number"),
      ("Float", "number"),
      ("Double", "number"),
      ("Int64", "bigint"),
      ("UInt64", "bigint"),
      ("String", "string"),
      ("Bytes", "Uint8Array"),
    ],
    fixed_array_aliases: ["FixedArray"],
    unboxed_option_aliases: ["UnboxedOption"],
    unboxed_option_as_int_aliases: ["UnboxedOptionAsInt"],
    generic_alias_expansions: [],
    interface_expansions: [],
  }
}

///|
fn push_unique_alias(items : Array[String], value : String) -> Unit {
  if items.contains(value) {
    return
  }
  items.push(value)
}

///|
fn push_unique_primitive_alias(
  items : Array[(String, String)],
  name : String,
  replacement : String,
) -> Unit {
  for item in items {
    let (item_name, _) = item
    if item_name == name {
      return
    }
  }
  items.push((name, replacement))
}

///|
fn primitive_alias_replacement(
  rules : TypeScriptDeclNormalizationRules,
  name : String,
) -> String? {
  for item in rules.primitive_aliases {
    let (alias_name, replacement) = item
    if alias_name == name {
      return Some(replacement)
    }
  }
  None
}

///|
fn find_generic_alias_expansion(
  rules : TypeScriptDeclNormalizationRules,
  name : String,
) -> (Array[String], String)? {
  for item in rules.generic_alias_expansions {
    let (alias_name, type_params, rhs) = item
    if alias_name == name {
      return Some((type_params, rhs))
    }
  }
  None
}

///|
fn find_interface_expansion(
  rules : TypeScriptDeclNormalizationRules,
  name : String,
) -> InterfaceExpansion? {
  for item in rules.interface_expansions {
    if item.name == name {
      return Some(item)
    }
  }
  None
}

///|
fn parse_moonbit_namespace_import_line(line : String) -> (String, String)? {
  let prefix = "import type * as "
  if !line.has_prefix(prefix) {
    return None
  }
  let part_list : Array[String] = []
  for part in line.split(" from ") {
    part_list.push(part.to_owned())
  }
  if part_list.length() != 2 {
    return None
  }
  let ns_alias = part_list[0][prefix.length():].trim().to_owned()
  if ns_alias == "" {
    return None
  }
  let mut module_spec = part_list[1].trim().to_owned()
  if module_spec.has_suffix(";") {
    module_spec = module_spec[:module_spec.length() - 1].to_owned()
  }
  if module_spec.length() >= 2 &&
    (
      (module_spec.has_prefix("\"") && module_spec.has_suffix("\"")) ||
      (module_spec.has_prefix("'") && module_spec.has_suffix("'"))
    ) {
    module_spec = module_spec[1:module_spec.length() - 1].to_owned()
  }
  if module_spec == "" {
    return None
  }
  Some((ns_alias, module_spec))
}

///|
fn parse_named_type_import_line(line : String) -> (Array[String], String)? {
  let trimmed = line.trim().to_owned()
  let prefix = "import type {"
  if !trimmed.has_prefix(prefix) {
    return None
  }
  let part_list : Array[String] = []
  for part in trimmed.split(" from ") {
    part_list.push(part.to_owned())
  }
  if part_list.length() != 2 {
    return None
  }
  let names_src = part_list[0][prefix.length():].trim().to_owned()
  if !names_src.has_suffix("}") {
    return None
  }
  let raw_names = names_src[:names_src.length() - 1].trim().to_owned()
  let names : Array[String] = []
  if raw_names != "" {
    for part in raw_names.split(",") {
      let name = part.trim().to_owned()
      if name != "" && !names.contains(name) {
        names.push(name)
      }
    }
  }
  let mut module_spec = part_list[1].trim().to_owned()
  if module_spec.has_suffix(";") {
    module_spec = module_spec[:module_spec.length() - 1].to_owned()
  }
  if module_spec.length() >= 2 &&
    (
      (module_spec.has_prefix("\"") && module_spec.has_suffix("\"")) ||
      (module_spec.has_prefix("'") && module_spec.has_suffix("'"))
    ) {
    module_spec = module_spec[1:module_spec.length() - 1].to_owned()
  }
  if module_spec == "" {
    return None
  }
  Some((names, module_spec))
}

///|
fn collect_moonbit_namespace_imports(
  source : String,
) -> Array[(String, String)] {
  let imports : Array[(String, String)] = []
  for line_view in source.split("\n") {
    match parse_moonbit_namespace_import_line(line_view.to_owned()) {
      Some(parsed) => {
        let (ns_alias, module_spec) = parsed
        let mut already_seen = false
        for item in imports {
          let (existing_alias, existing_module_spec) = item
          if existing_alias == ns_alias && existing_module_spec == module_spec {
            already_seen = true
            break
          }
        }
        if !already_seen {
          imports.push(parsed)
        }
      }
      None => ()
    }
  }
  imports
}

///|
fn has_prefix_at(source : String, prefix : String, start : Int) -> Bool {
  start + prefix.length() <= source.length() &&
  source[start:start + prefix.length()].to_owned() == prefix
}

///|
fn take_identifier_at(source : String, start : Int) -> (String, Int) {
  let mut i = start
  let mut result = ""
  while i < source.length() {
    let c = char_at(source, i)
    if result == "" {
      if !is_ascii_letter(c) && c != '_' && c != '$' {
        return ("", start)
      }
    } else if !is_ident_char(c) {
      return (result, i)
    }
    result += c.to_string()
    i += 1
  }
  (result, i)
}

///|
fn split_top_level_type_args(source : String) -> Array[String] {
  let args : Array[String] = []
  let mut start = 0
  let mut angle = 0
  let mut paren = 0
  let mut bracket = 0
  let mut brace = 0
  for i = 0; i < source.length(); i = i + 1 {
    let c = char_at(source, i)
    match c {
      '<' => angle += 1
      '>' => if i == 0 || char_at(source, i - 1) != '=' { angle -= 1 }
      '(' => paren += 1
      ')' => paren -= 1
      '[' => bracket += 1
      ']' => bracket -= 1
      '{' => brace += 1
      '}' => brace -= 1
      ',' if angle == 0 && paren == 0 && bracket == 0 && brace == 0 => {
        args.push(source[start:i].trim().to_owned())
        start = i + 1
      }
      _ => ()
    }
  }
  args.push(source[start:source.length()].trim().to_owned())
  args
}

///|
fn strip_ascii_space(source : String) -> String {
  let buf = StringBuilder::new()
  for c in source {
    if c != ' ' && c != '\n' && c != '\r' && c != '\t' {
      buf.write_char(c)
    }
  }
  buf.to_string()
}

///|
fn compact_ascii_space(source : String) -> String {
  let buf = StringBuilder::new()
  let mut last_was_space = false
  for c in source {
    let is_space = c == ' ' || c == '\n' || c == '\r' || c == '\t'
    if is_space {
      if !last_was_space {
        buf.write_char(' ')
      }
      last_was_space = true
    } else {
      buf.write_char(c)
      last_was_space = false
    }
  }
  buf.to_string().trim().to_owned()
}

///|
fn strip_block_comments(source : String) -> String {
  let buf = StringBuilder::new()
  let mut i = 0
  while i < source.length() {
    if i + 1 < source.length() &&
      char_at(source, i) == '/' &&
      char_at(source, i + 1) == '*' {
      i += 2
      while i + 1 < source.length() &&
            !(char_at(source, i) == '*' && char_at(source, i + 1) == '/') {
        i += 1
      }
      if i + 1 < source.length() {
        i += 2
      }
      continue
    }
    buf.write_char(char_at(source, i))
    i += 1
  }
  buf.to_string()
}

///|
fn strip_leading_union_bar(source : String) -> String {
  let trimmed = source.trim().to_owned()
  if trimmed.has_prefix("|") {
    trimmed[1:trimmed.length()].trim().to_owned()
  } else {
    trimmed
  }
}

///|
fn next_non_space_index(source : String, start : Int) -> Int {
  let mut i = start
  while i < source.length() {
    let c = char_at(source, i)
    if c != ' ' && c != '\n' && c != '\r' && c != '\t' {
      return i
    }
    i += 1
  }
  source.length()
}

///|
fn normalize_path(path : String) -> String {
  let is_abs = path.has_prefix("/")
  let parts : Array[String] = []
  for part_view in path.split("/") {
    let part = part_view.to_owned()
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
    Some(idx) => normalized[:idx].to_owned()
    None => "."
  }
}

///|
fn join_path(base : String, name : String) -> String {
  if base == "." || base == "" {
    name
  } else if base.has_suffix("/") {
    base + name
  } else {
    base + "/" + name
  }
}

///|
fn parse_export_type_alias_line(
  line : String,
) -> (String, Array[String], String)? {
  let prefix = "export type "
  if !line.has_prefix(prefix) {
    return None
  }
  match line.find("=") {
    Some(eq_idx) => {
      let left = line[prefix.length():eq_idx].trim().to_owned()
      let mut right = line[eq_idx + 1:line.length()].trim().to_owned()
      if right.has_suffix(";") {
        right = right[:right.length() - 1].trim().to_owned()
      }
      match left.find("<") {
        Some(lt_idx) if left.has_suffix(">") => {
          let name = left[:lt_idx].trim().to_owned()
          let params_src = left[lt_idx + 1:left.length() - 1].to_owned()
          let params = split_top_level_type_args(params_src)
          Some((name, params, right))
        }
        _ => Some((left, [], right))
      }
    }
    None => None
  }
}

///|
fn collect_export_type_alias_blocks(source : String) -> Array[String] {
  let blocks : Array[String] = []
  let current : Array[String] = []
  let mut collecting = false
  let mut paren_depth = 0
  let mut bracket_depth = 0
  let mut brace_depth = 0
  let mut angle_depth = 0
  for line_view in source.split("\n") {
    let line = line_view.to_owned()
    let trimmed = line.trim().to_owned()
    if !collecting {
      if trimmed.has_prefix("export type ") {
        current.push(line)
        collecting = true
        for i = 0; i < line.length(); i = i + 1 {
          let c = char_at(line, i)
          match c {
            '(' => paren_depth += 1
            ')' => paren_depth -= 1
            '[' => bracket_depth += 1
            ']' => bracket_depth -= 1
            '{' => brace_depth += 1
            '}' => brace_depth -= 1
            '<' => angle_depth += 1
            '>' => if i == 0 || char_at(line, i - 1) != '=' { angle_depth -= 1 }
            ';' if paren_depth == 0 &&
              bracket_depth == 0 &&
              brace_depth == 0 &&
              angle_depth == 0 => {
              blocks.push(current.join("\n"))
              current.clear()
              collecting = false
              paren_depth = 0
              bracket_depth = 0
              brace_depth = 0
              angle_depth = 0
              break
            }
            _ => ()
          }
        }
      }
      continue
    }
    current.push(line)
    for i = 0; i < line.length(); i = i + 1 {
      let c = char_at(line, i)
      match c {
        '(' => paren_depth += 1
        ')' => paren_depth -= 1
        '[' => bracket_depth += 1
        ']' => bracket_depth -= 1
        '{' => brace_depth += 1
        '}' => brace_depth -= 1
        '<' => angle_depth += 1
        '>' => if i == 0 || char_at(line, i - 1) != '=' { angle_depth -= 1 }
        ';' if paren_depth == 0 &&
          bracket_depth == 0 &&
          brace_depth == 0 &&
          angle_depth == 0 => {
          blocks.push(current.join("\n"))
          current.clear()
          collecting = false
          paren_depth = 0
          bracket_depth = 0
          brace_depth = 0
          angle_depth = 0
          break
        }
        _ => ()
      }
    }
  }
  blocks
}

///|
fn count_char(source : String, target : Char) -> Int {
  let mut count = 0
  for c in source {
    if c == target {
      count += 1
    }
  }
  count
}

///|
fn collect_export_interface_blocks(source : String) -> Array[String] {
  let blocks : Array[String] = []
  let current : Array[String] = []
  let mut collecting = false
  let mut brace_depth = 0
  let mut seen_open = false
  for line_view in source.split("\n") {
    let line = line_view.to_owned()
    let trimmed = line.trim().to_owned()
    if !collecting {
      if trimmed.has_prefix("export interface ") {
        current.push(line)
        collecting = true
        let opens = count_char(line, '{')
        let closes = count_char(line, '}')
        brace_depth = opens - closes
        seen_open = opens > 0
        if seen_open && brace_depth <= 0 {
          blocks.push(current.join("\n"))
          current.clear()
          collecting = false
          brace_depth = 0
          seen_open = false
        }
      }
      continue
    }
    current.push(line)
    let opens = count_char(line, '{')
    let closes = count_char(line, '}')
    brace_depth += opens - closes
    if opens > 0 {
      seen_open = true
    }
    if seen_open && brace_depth <= 0 {
      blocks.push(current.join("\n"))
      current.clear()
      collecting = false
      brace_depth = 0
      seen_open = false
    }
  }
  blocks
}

///|
fn substitute_type_params(
  source : String,
  type_params : Array[String],
  type_args : Array[String],
) -> String {
  let buf = StringBuilder::new()
  let mut i = 0
  while i < source.length() {
    let c = char_at(source, i)
    if !is_ascii_letter(c) && c != '_' && c != '$' {
      buf.write_char(c)
      i += 1
      continue
    }
    let (ident, end_) = take_identifier_at(source, i)
    let mut replaced = None
    for idx = 0; idx < type_params.length(); idx = idx + 1 {
      if type_params[idx] == ident && idx < type_args.length() {
        replaced = Some(type_args[idx])
        break
      }
    }
    match replaced {
      Some(value) => buf.write_string(value)
      None => buf.write_string(ident)
    }
    i = end_
  }
  buf.to_string()
}

///|
fn normalize_object_type_body(source : String) -> String {
  source.replace(old="; }", new=" }")
}

///|
fn render_intersection_types(parts : Array[String]) -> String {
  let normalized_parts : Array[String] = []
  for part in parts {
    let trimmed = part.trim().to_owned()
    if trimmed != "" && !normalized_parts.contains(trimmed) {
      normalized_parts.push(trimmed)
    }
  }
  if normalized_parts.length() == 0 {
    "{}"
  } else {
    normalized_parts.join(" & ")
  }
}

///|
fn parse_export_interface_block(block : String) -> InterfaceExpansion? {
  let normalized = compact_ascii_space(strip_block_comments(block))
  let prefix = "export interface "
  if !normalized.has_prefix(prefix) {
    return None
  }
  match normalized.find("{") {
    Some(open_idx) =>
      match normalized.rev_find("}") {
        Some(close_idx) if close_idx > open_idx => {
          let header_src = normalized[prefix.length():open_idx]
            .trim()
            .to_owned()
          let body = normalize_object_type_body(
            normalized[open_idx:close_idx + 1].to_owned(),
          )
          let extends_keyword = " extends "
          let (header, extends_refs) = match header_src.find(extends_keyword) {
            Some(extends_idx) => {
              let base_header = header_src[:extends_idx].trim().to_owned()
              let parents_src = header_src[extends_idx +
                extends_keyword.length():header_src.length()]
                .trim()
                .to_owned()
              let parents = if parents_src == "" {
                []
              } else {
                split_top_level_type_args(parents_src)
              }
              (base_header, parents)
            }
            None => (header_src, [])
          }
          match header.find("<") {
            Some(lt_idx) if header.has_suffix(">") => {
              let name = header[:lt_idx].trim().to_owned()
              let params_src = header[lt_idx + 1:header.length() - 1].to_owned()
              let params = split_top_level_type_args(params_src)
              Some({ name, type_params: params, extends_refs, body })
            }
            _ => Some({ name: header, type_params: [], extends_refs, body })
          }
        }
        _ => None
      }
    None => None
  }
}

///|
fn expand_interface_expansion_body(
  expansion : InterfaceExpansion,
  type_args : Array[String],
  rules : TypeScriptDeclNormalizationRules,
) -> String {
  let expanded_parts : Array[String] = []
  for extends_ref in expansion.extends_refs {
    let substituted_ref = substitute_type_params(
      extends_ref,
      expansion.type_params,
      type_args,
    )
    let parent_body = expand_known_alias_refs(substituted_ref, rules)
      .trim()
      .to_owned()
    if parent_body != "" {
      expanded_parts.push(parent_body)
    }
  }
  expanded_parts.push(
    expand_known_alias_refs(
      substitute_type_params(expansion.body, expansion.type_params, type_args),
      rules,
    ),
  )
  if can_merge_object_shapes(expanded_parts) {
    expand_known_alias_refs(merge_object_shapes(expanded_parts), rules)
  } else {
    render_intersection_types(expanded_parts)
  }
}

///|
fn expand_known_alias_refs(
  source : String,
  rules : TypeScriptDeclNormalizationRules,
) -> String {
  let buf = StringBuilder::new()
  let mut i = 0
  while i < source.length() {
    let c = char_at(source, i)
    if !is_ascii_letter(c) && c != '_' && c != '$' {
      buf.write_char(c)
      i += 1
      continue
    }
    let (ident, end_) = take_identifier_at(source, i)
    if end_ < source.length() && char_at(source, end_) == '<' {
      match find_matching_type_args_end(source, end_) {
        Some(args_end) => {
          let args_src = source[end_ + 1:args_end - 1].to_owned()
          let normalized_args : Array[String] = []
          for arg in split_top_level_type_args(args_src) {
            normalized_args.push(expand_known_alias_refs(arg, rules))
          }
          if rules.fixed_array_aliases.contains(ident) &&
            normalized_args.length() == 1 {
            buf.write_string("Array<\{normalized_args[0]}>")
          } else if rules.unboxed_option_aliases.contains(ident) &&
            normalized_args.length() == 1 {
            buf.write_string("\{normalized_args[0]} | undefined")
          } else if rules.unboxed_option_as_int_aliases.contains(ident) &&
            normalized_args.length() == 1 {
            buf.write_string("\{normalized_args[0]} | -1")
          } else {
            match find_generic_alias_expansion(rules, ident) {
              Some(expansion) => {
                let (type_params, rhs) = expansion
                if type_params.length() == normalized_args.length() {
                  let expanded = expand_known_alias_refs(
                    substitute_type_params(rhs, type_params, normalized_args),
                    rules,
                  )
                  let next_idx = next_non_space_index(source, args_end)
                  if next_idx < source.length() &&
                    char_at(source, next_idx) == '[' {
                    buf.write_string("(" + expanded + ")")
                  } else {
                    buf.write_string(expanded)
                  }
                } else {
                  buf.write_string(ident)
                  buf.write_string("<")
                  buf.write_string(normalized_args.join(", "))
                  buf.write_string(">")
                }
              }
              None =>
                match find_interface_expansion(rules, ident) {
                  Some(expansion) =>
                    if expansion.type_params.length() ==
                      normalized_args.length() {
                      buf.write_string(
                        expand_interface_expansion_body(
                          expansion, normalized_args, rules,
                        ),
                      )
                    } else {
                      buf.write_string(ident)
                      buf.write_string("<")
                      buf.write_string(normalized_args.join(", "))
                      buf.write_string(">")
                    }
                  None => {
                    buf.write_string(ident)
                    buf.write_string("<")
                    buf.write_string(normalized_args.join(", "))
                    buf.write_string(">")
                  }
                }
            }
          }
          i = args_end
          continue
        }
        None => ()
      }
    }
    match find_generic_alias_expansion(rules, ident) {
      Some((type_params, rhs)) if type_params.length() == 0 =>
        buf.write_string(expand_known_alias_refs(rhs, rules))
      _ =>
        match find_interface_expansion(rules, ident) {
          Some(expansion) if expansion.type_params.length() == 0 =>
            buf.write_string(
              expand_interface_expansion_body(expansion, [], rules),
            )
          _ =>
            match primitive_alias_replacement(rules, ident) {
              Some(replacement) => buf.write_string(replacement)
              None => buf.write_string(ident)
            }
        }
    }
    i = end_
  }
  buf.to_string()
}

///|
fn parse_normalization_rules_from_moonbit_decl(
  moonbit_decl : String,
) -> TypeScriptDeclNormalizationRules {
  let rules = default_normalization_rules()
  for block in collect_export_type_alias_blocks(moonbit_decl) {
    let line = compact_ascii_space(strip_block_comments(block))
    match parse_export_type_alias_line(line) {
      Some((name, type_params, rhs)) => {
        let compact_rhs = strip_ascii_space(rhs)
        match type_params {
          [] =>
            if compact_rhs == "undefined" ||
              compact_rhs == "boolean" ||
              compact_rhs == "number" ||
              compact_rhs == "string" ||
              compact_rhs == "Uint8Array" {
              push_unique_primitive_alias(rules.primitive_aliases, name, rhs)
            } else if compact_rhs.has_prefix("bigint") {
              push_unique_primitive_alias(
                rules.primitive_aliases,
                name,
                "bigint",
              )
            }
          [type_param] =>
            if compact_rhs == type_param + "[]" {
              push_unique_alias(rules.fixed_array_aliases, name)
            } else if compact_rhs.contains(type_param) &&
              compact_rhs.contains("|undefined") {
              push_unique_alias(rules.unboxed_option_aliases, name)
            } else if compact_rhs.contains(type_param) &&
              compact_rhs.contains("|-1") {
              push_unique_alias(rules.unboxed_option_as_int_aliases, name)
            }
          _ => ()
        }
        if !rules.fixed_array_aliases.contains(name) &&
          !rules.unboxed_option_aliases.contains(name) &&
          !rules.unboxed_option_as_int_aliases.contains(name) {
          rules.generic_alias_expansions.push(
            (
              name,
              type_params,
              normalize_object_type_body(strip_leading_union_bar(rhs)),
            ),
          )
        }
      }
      None => ()
    }
  }
  for block in collect_export_interface_blocks(moonbit_decl) {
    match parse_export_interface_block(block) {
      Some(expansion) => rules.interface_expansions.push(expansion)
      _ => ()
    }
  }
  rules
}

///|
fn resolve_imported_decl_path(
  entry_path : String,
  module_spec : String,
) -> String? {
  if module_spec.has_prefix("./") || module_spec.has_prefix("../") {
    Some(normalize_path(join_path(dirname(entry_path), module_spec)))
  } else {
    None
  }
}

///|
fn find_matching_type_args_end(source : String, start : Int) -> Int? {
  let mut angle = 0
  let mut paren = 0
  let mut bracket = 0
  let mut brace = 0
  for i = start; i < source.length(); i = i + 1 {
    let c = char_at(source, i)
    match c {
      '<' => angle += 1
      '>' =>
        if i == 0 || char_at(source, i - 1) != '=' {
          angle -= 1
          if angle == 0 && paren == 0 && bracket == 0 && brace == 0 {
            return Some(i + 1)
          }
        }
      '(' => paren += 1
      ')' => paren -= 1
      '[' => bracket += 1
      ']' => bracket -= 1
      '{' => brace += 1
      '}' => brace -= 1
      _ => ()
    }
  }
  None
}

///|
fn replace_prefixed_type_refs(
  source : String,
  ns_alias : String,
  rules : TypeScriptDeclNormalizationRules,
  state : TypeScriptDeclNormalizationState,
) -> String {
  let prefix = ns_alias + "."
  let buf = StringBuilder::new()
  let mut i = 0
  while i < source.length() {
    if !has_prefix_at(source, prefix, i) {
      buf.write_char(char_at(source, i))
      i += 1
      continue
    }
    let (type_name, after_name) = take_identifier_at(
      source,
      i + prefix.length(),
    )
    if type_name == "" {
      buf.write_char(char_at(source, i))
      i += 1
      continue
    }
    if after_name < source.length() && char_at(source, after_name) == '<' {
      match find_matching_type_args_end(source, after_name) {
        Some(end_) => {
          let args_src = source[after_name + 1:end_ - 1].to_owned()
          let normalized_args : Array[String] = []
          for arg in split_top_level_type_args(args_src) {
            normalized_args.push(
              replace_prefixed_type_refs(arg, ns_alias, rules, state),
            )
          }
          if rules.fixed_array_aliases.contains(type_name) &&
            normalized_args.length() == 1 {
            buf.write_string("Array<\{normalized_args[0]}>")
          } else if rules.unboxed_option_aliases.contains(type_name) &&
            normalized_args.length() == 1 {
            buf.write_string("\{normalized_args[0]} | undefined")
          } else if rules.unboxed_option_as_int_aliases.contains(type_name) &&
            normalized_args.length() == 1 {
            buf.write_string("\{normalized_args[0]} | -1")
          } else {
            match find_generic_alias_expansion(rules, type_name) {
              Some(expansion) => {
                let (type_params, rhs) = expansion
                if type_params.length() == normalized_args.length() {
                  let expanded = expand_known_alias_refs(
                    substitute_type_params(rhs, type_params, normalized_args),
                    rules,
                  )
                  let next_idx = next_non_space_index(source, end_)
                  if next_idx < source.length() &&
                    char_at(source, next_idx) == '[' {
                    buf.write_string("(" + expanded + ")")
                  } else {
                    buf.write_string(expanded)
                  }
                } else {
                  push_unique_string(state.named_imports, type_name)
                  buf.write_string(type_name)
                  buf.write_string("<")
                  buf.write_string(normalized_args.join(", "))
                  buf.write_string(">")
                }
              }
              _ =>
                match find_interface_expansion(rules, type_name) {
                  Some(expansion) =>
                    if expansion.type_params.length() ==
                      normalized_args.length() {
                      buf.write_string(
                        expand_interface_expansion_body(
                          expansion, normalized_args, rules,
                        ),
                      )
                    } else {
                      push_unique_string(state.named_imports, type_name)
                      buf.write_string(type_name)
                      buf.write_string("<")
                      buf.write_string(normalized_args.join(", "))
                      buf.write_string(">")
                    }
                  None => {
                    push_unique_string(state.named_imports, type_name)
                    buf.write_string(type_name)
                    buf.write_string("<")
                    buf.write_string(normalized_args.join(", "))
                    buf.write_string(">")
                  }
                }
            }
          }
          i = end_
          continue
        }
        None => ()
      }
    }
    match find_generic_alias_expansion(rules, type_name) {
      Some((type_params, rhs)) if type_params.length() == 0 =>
        buf.write_string(expand_known_alias_refs(rhs, rules))
      _ =>
        match find_interface_expansion(rules, type_name) {
          Some(expansion) if expansion.type_params.length() == 0 =>
            buf.write_string(
              expand_interface_expansion_body(expansion, [], rules),
            )
          _ =>
            match primitive_alias_replacement(rules, type_name) {
              Some(replacement) => buf.write_string(replacement)
              None => {
                push_unique_string(state.named_imports, type_name)
                buf.write_string(type_name)
              }
            }
        }
    }
    i = after_name
  }
  buf.to_string()
}

///|
fn rebuild_moonbit_imports(
  source : String,
  ns_alias : String,
  module_spec : String,
  named_imports : Array[String],
) -> String {
  let rebuilt : Array[String] = []
  let replacement_line = if named_imports.length() == 0 {
    None
  } else {
    Some(
      "import type { " +
      named_imports.join(", ") +
      " } from \"" +
      module_spec +
      "\";",
    )
  }
  for line_view in source.split("\n") {
    let line = line_view.to_owned()
    match parse_moonbit_namespace_import_line(line) {
      Some((line_alias, _)) if line_alias == ns_alias =>
        match replacement_line {
          Some(import_line) => rebuilt.push(import_line)
          None => ()
        }
      _ => rebuilt.push(line)
    }
  }
  let mut first_non_empty = 0
  while first_non_empty < rebuilt.length() &&
        rebuilt[first_non_empty].trim() == "" {
    first_non_empty += 1
  }
  let mut last_non_empty = rebuilt.length()
  while last_non_empty > first_non_empty &&
        rebuilt[last_non_empty - 1].trim() == "" {
    last_non_empty -= 1
  }
  let final_lines : Array[String] = []
  for index = first_non_empty; index < last_non_empty; index = index + 1 {
    final_lines.push(rebuilt[index])
  }
  final_lines.join("\n")
}

///|
fn merge_named_type_imports(source : String) -> String {
  let rebuilt : Array[String] = []
  let module_order : Array[String] = []
  let module_names : Array[Array[String]] = []
  let module_positions : Array[Int] = []
  for line_view in source.split("\n") {
    let line = line_view.to_owned()
    match parse_named_type_import_line(line) {
      Some((names, module_spec)) => {
        let mut found_idx = None
        for idx = 0; idx < module_order.length(); idx = idx + 1 {
          if module_order[idx] == module_spec {
            found_idx = Some(idx)
            break
          }
        }
        match found_idx {
          Some(idx) =>
            for name in names {
              push_unique_string(module_names[idx], name)
            }
          None => {
            module_order.push(module_spec)
            module_names.push(names)
            module_positions.push(rebuilt.length())
            rebuilt.push("")
          }
        }
      }
      None => rebuilt.push(line)
    }
  }
  for idx = 0; idx < module_order.length(); idx = idx + 1 {
    rebuilt[module_positions[idx]] = "import type { " +
      module_names[idx].join(", ") +
      " } from \"" +
      module_order[idx] +
      "\";"
  }
  rebuilt.join("\n")
}

///|
fn normalize_moonbit_generated_typescript_decl_text(
  source : String,
  import_rules : Array[TypeScriptDeclImportRules],
) -> String {
  let mut normalized = source
  for import_rule in import_rules {
    let state = { named_imports: [] }
    normalized = replace_prefixed_type_refs(
      normalized,
      import_rule.ns_alias,
      import_rule.rules,
      state,
    )
    normalized = rebuild_moonbit_imports(
      normalized,
      import_rule.ns_alias,
      import_rule.module_spec,
      state.named_imports,
    )
  }
  merge_named_type_imports(normalized)
}

///|
pub async fn normalize_moonbit_generated_typescript_decl_from_entry_path(
  entry_path : String,
) -> String raise ModuleGraphError {
  let content = @fs.read_file(entry_path).text() catch {
    e =>
      raise ReadError(
        "Failed to read TypeScript declaration entry '\{entry_path}': \{e}",
      )
  }
  let import_rules : Array[TypeScriptDeclImportRules] = []
  for parsed in collect_moonbit_namespace_imports(content) {
    let (ns_alias, module_spec) = parsed
    let rules = match resolve_imported_decl_path(entry_path, module_spec) {
      Some(moonbit_decl_path) =>
        parse_normalization_rules_from_moonbit_decl(
          @fs.read_file(moonbit_decl_path).text() catch {
            _ => ""
          },
        )
      None => default_normalization_rules()
    }
    import_rules.push({ ns_alias, module_spec, rules })
  }
  let normalized = normalize_moonbit_generated_typescript_decl_text(
    content, import_rules,
  )
  let parser = @parser.Parser::from_source(normalized)
  let _ = parser.parse_module() catch {
    @parser.ParseError(msg) =>
      raise ParseError(
        "Failed to parse normalized declarations in '\{entry_path}': \{msg}",
      )
  }
  normalized
}
