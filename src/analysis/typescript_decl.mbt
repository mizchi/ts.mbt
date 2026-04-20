///|
priv struct TypeScriptDeclNormalizationState {
  named_imports : Array[String]
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
fn moonbit_primitive_alias_replacement(name : String) -> String? {
  match name {
    "Unit" => Some("undefined")
    "Bool" => Some("boolean")
    "Int" | "UInt" | "Char" | "Byte" | "Float" | "Double" => Some("number")
    "String" => Some("string")
    "Bytes" => Some("Uint8Array")
    _ => None
  }
}

///|
fn parse_moonbit_namespace_import_line(line : String) -> (String, String)? {
  let prefix = "import type * as "
  if !line.has_prefix(prefix) {
    return None
  }
  let part_list : Array[String] = []
  for part in line.split(" from ") {
    part_list.push(part.to_string())
  }
  if part_list.length() != 2 {
    return None
  }
  let ns_alias = part_list[0][prefix.length():].trim().to_string()
  if ns_alias == "" {
    return None
  }
  let mut module_spec = part_list[1].trim().to_string()
  if module_spec.has_suffix(";") {
    module_spec = module_spec[:module_spec.length() - 1].to_string()
  }
  if module_spec.length() >= 2 &&
    (
      (module_spec.has_prefix("\"") && module_spec.has_suffix("\"")) ||
      (module_spec.has_prefix("'") && module_spec.has_suffix("'"))
    ) {
    module_spec = module_spec[1:module_spec.length() - 1].to_string()
  }
  if module_spec == "" {
    return None
  }
  Some((ns_alias, module_spec))
}

///|
fn take_identifier_prefix(segment : String) -> String {
  let mut result = ""
  for c in segment {
    if result == "" {
      if !is_ascii_letter(c) && c != '_' && c != '$' {
        return ""
      }
    } else if !is_ident_char(c) {
      return result
    }
    result += c.to_string()
  }
  result
}

///|
fn replace_prefixed_type_refs(
  source : String,
  ns_alias : String,
  state : TypeScriptDeclNormalizationState,
) -> String {
  let prefix = ns_alias + "."
  let mut rebuilt = ""
  let mut first = true
  for part_view in source.split(prefix) {
    let segment = part_view.to_string()
    if first {
      rebuilt += segment
      first = false
      continue
    }
    let type_name = take_identifier_prefix(segment)
    if type_name == "" {
      rebuilt += prefix + segment
      continue
    }
    match moonbit_primitive_alias_replacement(type_name) {
      Some(replacement) =>
        rebuilt += replacement + segment[type_name.length():].to_string()
      None => {
        push_unique_string(state.named_imports, type_name)
        rebuilt += type_name + segment[type_name.length():].to_string()
      }
    }
  }
  rebuilt
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
    let line = line_view.to_string()
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
fn normalize_moonbit_generated_typescript_decl_text(source : String) -> String {
  let mut import_alias : (String, String)? = None
  for line_view in source.split("\n") {
    let line = line_view.to_string()
    match parse_moonbit_namespace_import_line(line) {
      Some(parsed) => {
        import_alias = Some(parsed)
        break
      }
      None => ()
    }
  }
  match import_alias {
    Some((ns_alias, module_spec)) => {
      let state = { named_imports: [] }
      let normalized = replace_prefixed_type_refs(source, ns_alias, state)
      rebuild_moonbit_imports(
        normalized,
        ns_alias,
        module_spec,
        state.named_imports,
      )
    }
    None => source
  }
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
  let normalized = normalize_moonbit_generated_typescript_decl_text(content)
  let parser = @parser.Parser::from_source(normalized)
  let _ = parser.parse_module() catch {
    @parser.ParseError(msg) =>
      raise ParseError(
        "Failed to parse normalized declarations in '\{entry_path}': \{msg}",
      )
  }
  normalized
}
