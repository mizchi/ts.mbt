///| Minimal object-shape merge helpers for `normalize-moonbit-dts`.

///|

///| This is intentionally not a general TypeScript checker.

///| Its job is only to answer:

///| - can several object-like interface expansions be flattened into one `{ ... }`

///| - or should normalization keep them as intersections `A & B & ...`

///|

///| Keep the scope narrow unless a separate "real checker" goal is chosen.

///|
fn object_shape_char_at(s : String, idx : Int) -> Char {
  s[idx].to_int().unsafe_to_char()
}

///|
fn object_shape_is_ascii_letter(c : Char) -> Bool {
  (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
}

///|
fn object_shape_is_ascii_digit(c : Char) -> Bool {
  c >= '0' && c <= '9'
}

///|
fn object_shape_is_ident_char(c : Char) -> Bool {
  object_shape_is_ascii_letter(c) ||
  object_shape_is_ascii_digit(c) ||
  c == '_' ||
  c == '$'
}

///|
fn object_shape_take_identifier_at(
  source : String,
  start : Int,
) -> (String, Int) {
  let mut i = start
  let mut result = ""
  while i < source.length() {
    let c = object_shape_char_at(source, i)
    if result == "" {
      if !object_shape_is_ascii_letter(c) && c != '_' && c != '$' {
        return ("", start)
      }
    } else if !object_shape_is_ident_char(c) {
      return (result, i)
    }
    result += c.to_string()
    i += 1
  }
  (result, i)
}

///|
fn object_shape_compact_ascii_space(source : String) -> String {
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
fn object_shape_next_non_space_index(source : String, start : Int) -> Int {
  let mut i = start
  while i < source.length() {
    let c = object_shape_char_at(source, i)
    if c != ' ' && c != '\n' && c != '\r' && c != '\t' {
      return i
    }
    i += 1
  }
  source.length()
}

///|
fn object_shape_split_top_level_by_char(
  source : String,
  delimiter : Char,
) -> Array[String] {
  let parts : Array[String] = []
  let mut start = 0
  let mut angle = 0
  let mut paren = 0
  let mut bracket = 0
  let mut brace = 0
  for i = 0; i < source.length(); i = i + 1 {
    let c = object_shape_char_at(source, i)
    match c {
      '<' => angle += 1
      '>' =>
        if i == 0 || object_shape_char_at(source, i - 1) != '=' {
          angle -= 1
        }
      '(' => paren += 1
      ')' => paren -= 1
      '[' => bracket += 1
      ']' => bracket -= 1
      '{' => brace += 1
      '}' => brace -= 1
      _ => ()
    }
    if c == delimiter && angle == 0 && paren == 0 && bracket == 0 && brace == 0 {
      parts.push(source[start:i].trim().to_owned())
      start = i + 1
    }
  }
  parts.push(source[start:source.length()].trim().to_owned())
  parts
}

///|
fn object_shape_trim_object_type_body(source : String) -> String {
  let trimmed = source.trim().to_owned()
  if trimmed.has_prefix("{") && trimmed.has_suffix("}") && trimmed.length() >= 2 {
    trimmed[1:trimmed.length() - 1].trim().to_owned()
  } else {
    trimmed
  }
}

///|
fn object_shape_strip_trailing_semicolon(source : String) -> String {
  let trimmed = source.trim().to_owned()
  if trimmed.has_suffix(";") {
    trimmed[:trimmed.length() - 1].trim().to_owned()
  } else {
    trimmed
  }
}

///|
fn object_shape_skip_leading_member_modifiers_from(
  source : String,
  idx : Int,
) -> Int {
  let start = object_shape_next_non_space_index(source, idx)
  if start >= source.length() {
    return start
  }
  let (ident, end_) = object_shape_take_identifier_at(source, start)
  if ident == "readonly" {
    object_shape_skip_leading_member_modifiers_from(source, end_)
  } else {
    start
  }
}

///|
fn object_shape_skip_leading_member_modifiers(source : String) -> Int {
  object_shape_skip_leading_member_modifiers_from(source, 0)
}

///|
fn object_shape_member_info(member_src : String) -> (String, Bool)? {
  let trimmed = member_src.trim().to_owned()
  if trimmed == "" {
    return None
  }
  let start = object_shape_skip_leading_member_modifiers(trimmed)
  let (name, end_) = object_shape_take_identifier_at(trimmed, start)
  if name == "" {
    return None
  }
  let mut next = end_
  if next < trimmed.length() && object_shape_char_at(trimmed, next) == '?' {
    next += 1
  }
  if next >= trimmed.length() {
    return None
  }
  let next_char = object_shape_char_at(trimmed, next)
  if next_char == ':' {
    Some((name, true))
  } else if next_char == '(' || next_char == '<' {
    Some((name, false))
  } else {
    None
  }
}

///|
fn object_shape_canonicalize_member(member_src : String) -> String {
  object_shape_compact_ascii_space(
    object_shape_strip_trailing_semicolon(member_src),
  )
}

///|
fn can_merge_object_shapes(bodies : Array[String]) -> Bool {
  let seen_keys : Array[String] = []
  let seen_members : Array[String] = []
  let seen_property_members : Array[Bool] = []
  for body in bodies {
    let trimmed = body.trim().to_owned()
    if !trimmed.has_prefix("{") || !trimmed.has_suffix("}") {
      return false
    }
    let inner = object_shape_trim_object_type_body(trimmed)
    for member_src in object_shape_split_top_level_by_char(inner, ';') {
      let normalized_member = member_src.trim().to_owned()
      if normalized_member == "" {
        continue
      }
      match object_shape_member_info(normalized_member) {
        Some((key, is_property_member)) => {
          let mut found_idx = None
          for idx = 0; idx < seen_keys.length(); idx = idx + 1 {
            if seen_keys[idx] == key {
              found_idx = Some(idx)
              break
            }
          }
          match found_idx {
            Some(idx) =>
              if seen_members[idx] !=
                object_shape_canonicalize_member(member_src) ||
                !is_property_member ||
                !seen_property_members[idx] {
                return false
              }
            None => {
              seen_keys.push(key)
              seen_members.push(object_shape_canonicalize_member(member_src))
              seen_property_members.push(is_property_member)
            }
          }
        }
        None => return false
      }
    }
  }
  true
}

///|
fn merge_object_shapes(bodies : Array[String]) -> String {
  let merged_members : Array[String] = []
  let seen_members : Array[String] = []
  for body in bodies {
    let inner = object_shape_strip_trailing_semicolon(
      object_shape_trim_object_type_body(body),
    )
    if inner != "" {
      for member_src in object_shape_split_top_level_by_char(inner, ';') {
        let trimmed = object_shape_strip_trailing_semicolon(member_src)
          .trim()
          .to_string()
        if trimmed == "" {
          continue
        }
        let canonical = object_shape_canonicalize_member(trimmed)
        if !seen_members.contains(canonical) {
          seen_members.push(canonical)
          merged_members.push(trimmed)
        }
      }
    }
  }
  if merged_members.length() == 0 {
    "{}"
  } else {
    "{ " + merged_members.join("; ") + " }"
  }
}
