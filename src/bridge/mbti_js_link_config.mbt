///|
pub suberror MbtiJsLinkConfigError {
  ReadError(String)
  ParseError(String)
} derive(@debug.Debug)

///|
fn mbti_js_link_char_at(s : String, idx : Int) -> Char {
  s[idx].to_int().unsafe_to_char()
}

///|
fn mbti_js_link_find_matching(
  source : String,
  open_idx : Int,
  open_char : Char,
  close_char : Char,
) -> Int? {
  let mut depth = 0
  let mut idx = open_idx
  while idx < source.length() {
    let c = mbti_js_link_char_at(source, idx)
    if c == open_char {
      depth += 1
    } else if c == close_char {
      depth -= 1
      if depth == 0 {
        return Some(idx)
      }
    }
    idx += 1
  }
  None
}

///|
fn parse_mbti_public_function_name(
  line : String,
) -> String? raise MbtiJsLinkConfigError {
  let trimmed = line.trim().to_owned()
  let mut rest = match trimmed {
    _ if trimmed.has_prefix("pub async fn") =>
      trimmed["pub async fn".length():trimmed.length()].to_owned()
    _ if trimmed.has_prefix("pub fn") =>
      trimmed["pub fn".length():trimmed.length()].to_owned()
    _ => return None
  }
  if rest == "" {
    return None
  }
  if rest.has_prefix("[") {
    match mbti_js_link_find_matching(rest, 0, '[', ']') {
      Some(close_idx) => rest = rest[close_idx + 1:rest.length()].to_owned()
      None =>
        raise MbtiJsLinkConfigError::ParseError(
          "unclosed type parameter list in mbti function: \{trimmed}",
        )
    }
  }
  let mut name_start = 0
  while name_start < rest.length() &&
        mbti_js_link_char_at(rest, name_start) == ' ' {
    name_start += 1
  }
  match rest.find("(") {
    Some(open_idx) if open_idx >= name_start => {
      let raw_name = rest[name_start:open_idx].trim().to_owned()
      if raw_name == "" {
        raise MbtiJsLinkConfigError::ParseError(
          "missing function name in mbti declaration: \{trimmed}",
        )
      }
      if raw_name.contains("::") {
        None
      } else {
        Some(raw_name)
      }
    }
    _ =>
      raise MbtiJsLinkConfigError::ParseError(
        "missing parameter list in mbti function: \{trimmed}",
      )
  }
}

///|
fn collect_mbti_public_free_function_names(
  source : String,
) -> Array[String] raise MbtiJsLinkConfigError {
  let names : Array[String] = []
  for line in source.split("\n") {
    match parse_mbti_public_function_name(line.to_owned()) {
      Some(name) => if !names.contains(name) { names.push(name) }
      None => ()
    }
  }
  names
}

///|
/// Render a standalone `moon.pkg` text-format options block describing
/// the JS link config. Suitable for dropping in as the package's
/// `moon.pkg` (or merging into an existing `options(...)` block by hand).
fn render_moonbit_js_link_config(function_names : Array[String]) -> String {
  let export_lines : Array[String] = []
  for i = 0; i < function_names.length(); i = i + 1 {
    let suffix = if i + 1 < function_names.length() { "," } else { "" }
    export_lines.push("        \"\{function_names[i]}\"\{suffix}")
  }
  let lines = [
    "options(",
    "  link: {",
    "    \"js\": {",
    "      \"exports\": [",
    export_lines.join("\n"),
    "      ],",
    "      \"format\": \"esm\",",
    "    },",
    "  },",
    ")",
  ]
  lines.join("\n")
}

///|
pub fn emit_moonbit_js_link_config_from_mbti_source(
  source : String,
) -> String raise MbtiJsLinkConfigError {
  render_moonbit_js_link_config(collect_mbti_public_free_function_names(source))
}

///|
pub fn emit_moonbit_js_link_config_from_mbti_source_with_extra_exports(
  source : String,
  extra_export_names : Array[String],
) -> String raise MbtiJsLinkConfigError {
  let function_names = collect_mbti_public_free_function_names(source)
  for extra_name in extra_export_names {
    if !function_names.contains(extra_name) {
      function_names.push(extra_name)
    }
  }
  render_moonbit_js_link_config(function_names)
}

///|
pub async fn emit_moonbit_js_link_config_from_mbti_path(
  file_path : String,
) -> String raise MbtiJsLinkConfigError {
  let source = @fs.read_file(file_path).text() catch {
    e => raise MbtiJsLinkConfigError::ReadError("\{e}")
  }
  emit_moonbit_js_link_config_from_mbti_source(source)
}
