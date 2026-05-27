// JSDoc block comment parser.
//
// JSDoc syntax: `/** description? @tag1 ... @tag2 ... */`. The
// lexer hands us the comment text verbatim (including the
// surrounding `/**` / `*/` markers); we strip the framing,
// normalize leading `* ` on continuation lines, then split on
// top-level `@` to recover the description + tag list.
//
// Tag-specific shapes we model:
//   @param {Type} name [- description]
//   @returns {Type} [description]
//   @throws {Type} [description]
//   @deprecated [message]
//   @internal
//   @public / @private / @protected / @readonly
//   @__PURE__
//   @__NO_SIDE_EFFECTS__
//   @see Reference
//   @example ...
//   @template T [- description]
//   @typedef {Type} Name
//
// Unknown tags survive as `Other(name, content)` so callers can
// build extensions without losing fidelity.

///|
pub(all) struct JsdocBlock {
  description : String
  tags : Array[JsdocTag]
} derive(Debug)

///|
pub(all) enum JsdocTag {
  Param(String, String?, String) // name, optional type, description
  Returns(String?, String) // optional type, description
  Throws(String?, String) // optional type, description
  Deprecated(String) // message (empty when none)
  Internal
  Public
  Private
  Protected
  Readonly
  Pure // `@__PURE__`
  NoSideEffects // `@__NO_SIDE_EFFECTS__`
  See(String)
  Example(String)
  Template(String, String) // name, description
  Typedef(String?, String) // type, name
  Other(String, String) // tag_name (without `@`), raw content
} derive(Eq, Debug)

///|
pub fn JsdocBlock::is_empty(self : JsdocBlock) -> Bool {
  self.description == "" && self.tags.length() == 0
}

///|
/// Parse a JSDoc block comment. `text` is the raw comment span
/// including `/**` … `*/` framing. Returns `None` when the
/// comment isn't a JSDoc block (`/* … */` without the double
/// asterisk) or is empty.
pub fn parse_jsdoc_block(text : String) -> JsdocBlock? {
  // Must start with `/**` and end with `*/`. Single-asterisk
  // `/* … */` comments aren't JSDoc; we still scan them for
  // inline `@__PURE__` markers separately.
  if not(text.has_prefix("/**")) {
    return None
  }
  let body_start = 3
  let body_end = if text.has_suffix("*/") {
    text.length() - 2
  } else {
    text.length()
  }
  if body_end <= body_start {
    return None
  }
  let raw = text.substring(start=body_start, end=body_end).to_string()
  // Strip the leading `*` (with optional space) on each line —
  // standard JSDoc convention puts a `*` at column 0 of every
  // continuation line. Without this we'd leak `*` chars into
  // descriptions.
  let cleaned = strip_jsdoc_line_prefixes(raw)
  // Split into description + tags. The first `@tag` at the start
  // of a line marks the boundary. Lines before the first tag
  // form the description.
  let mut description = ""
  let tags : Array[JsdocTag] = []
  let mut current_tag_name = ""
  let mut current_tag_content : Array[String] = []
  let mut in_description = true
  for line_view in cleaned.split("\n") {
    let line = line_view.to_string()
    let trimmed = line.trim_start()
    if trimmed.has_prefix("@") {
      // Flush whatever we were collecting.
      if not(in_description) {
        tags.push(
          interpret_tag(
            current_tag_name,
            current_tag_content.join("\n").trim_end().to_string(),
          ),
        )
      } else if description != "" {
        description = description.trim_end().to_string()
      }
      in_description = false
      // Split into tag name + rest. Tag name is `[a-zA-Z_]+` or
      // the special `__PURE__` / `__NO_SIDE_EFFECTS__` marker.
      let trimmed_str = trimmed.to_string()
      let rest = trimmed_str
        .substring(start=1, end=trimmed_str.length())
        .to_string()
      let (name, body) = split_tag_head(rest)
      current_tag_name = name
      current_tag_content = [body]
    } else if in_description {
      if description != "" {
        description = description + "\n"
      }
      description = description + line
    } else {
      current_tag_content.push(line)
    }
  }
  // Flush the trailing tag.
  if not(in_description) {
    tags.push(
      interpret_tag(
        current_tag_name,
        current_tag_content.join("\n").trim_end().to_string(),
      ),
    )
  }
  let block : JsdocBlock = { description: description.trim().to_string(), tags }
  if block.is_empty() {
    None
  } else {
    Some(block)
  }
}

///|
fn strip_jsdoc_line_prefixes(s : String) -> String {
  let out : Array[String] = []
  for line_view in s.split("\n") {
    let line = line_view.to_string()
    let trimmed = line.trim_start().to_string()
    let cleaned = if trimmed.has_prefix("* ") {
      trimmed.substring(start=2, end=trimmed.length()).to_string()
    } else if trimmed.has_prefix("*") {
      trimmed.substring(start=1, end=trimmed.length()).to_string()
    } else {
      line
    }
    out.push(cleaned)
  }
  out.join("\n")
}

///|
/// Split a tag line (post-`@`) into `(tag_name, rest)`.
/// `paramName description` → `("paramName", "description")`.
fn split_tag_head(s : String) -> (String, String) {
  let mut i = 0
  while i < s.length() {
    let c = s[i]
    if (c >= 'a' && c <= 'z') ||
      (c >= 'A' && c <= 'Z') ||
      (c >= '0' && c <= '9') ||
      c == '_' {
      i = i + 1
    } else {
      break
    }
  }
  if i == 0 {
    return ("", s)
  }
  let name = s.substring(start=0, end=i).to_string()
  let rest = s
    .substring(start=i, end=s.length())
    .to_string()
    .trim_start()
    .to_string()
  (name, rest)
}

///|
/// Build a `JsdocTag` from a tag name and content. Unknown tags
/// fall through to `Other(name, content)` so callers can still
/// see them.
fn interpret_tag(name : String, content : String) -> JsdocTag {
  match name {
    "param" | "arg" | "argument" => {
      let (ty, after_type) = extract_brace_type(content)
      let (param_name, description) = split_first_word(after_type)
      Param(param_name, ty, description)
    }
    "returns" | "return" => {
      let (ty, description) = extract_brace_type(content)
      Returns(ty, description)
    }
    "throws" | "exception" => {
      let (ty, description) = extract_brace_type(content)
      Throws(ty, description)
    }
    "deprecated" => Deprecated(content)
    "internal" => Internal
    "public" => Public
    "private" => Private
    "protected" => Protected
    "readonly" => Readonly
    "see" => See(content)
    "example" => Example(content)
    "template" | "typeparam" => {
      let (tparam_name, description) = split_first_word(content)
      Template(tparam_name, description)
    }
    "typedef" => {
      let (ty, after_type) = extract_brace_type(content)
      let (typedef_name, _) = split_first_word(after_type)
      Typedef(ty, typedef_name)
    }
    "__PURE__" => Pure
    "__NO_SIDE_EFFECTS__" => NoSideEffects
    _ => Other(name, content)
  }
}

///|
/// Pull a brace-delimited type from the head of `s`. Returns
/// `(Some(inner), rest)` when the input starts with `{…}`,
/// `(None, s)` otherwise. Nested braces are supported.
fn extract_brace_type(s : String) -> (String?, String) {
  let trimmed = s.trim_start().to_string()
  if trimmed.length() == 0 || trimmed[0] != '{' {
    return (None, trimmed)
  }
  let mut depth = 0
  let mut i = 0
  while i < trimmed.length() {
    let c = trimmed[i]
    if c == '{' {
      depth = depth + 1
    } else if c == '}' {
      depth = depth - 1
      if depth == 0 {
        let inner = trimmed
          .substring(start=1, end=i)
          .to_string()
          .trim()
          .to_string()
        let rest = trimmed
          .substring(start=i + 1, end=trimmed.length())
          .to_string()
          .trim_start()
          .to_string()
        return (Some(inner), rest)
      }
    }
    i = i + 1
  }
  (None, trimmed)
}

///|
/// Split off the first whitespace-delimited word — useful for
/// `@param TYPE NAME description` shapes.
fn split_first_word(s : String) -> (String, String) {
  let trimmed = s.trim_start().to_string()
  let mut i = 0
  while i < trimmed.length() {
    let c = trimmed[i]
    if c == ' ' || c == '\t' || c == '\n' || c == '-' {
      break
    }
    i = i + 1
  }
  if i == 0 {
    return ("", trimmed)
  }
  let head = trimmed.substring(start=0, end=i).to_string()
  let mut rest = trimmed
    .substring(start=i, end=trimmed.length())
    .to_string()
    .trim_start()
    .to_string()
  // The convention `@param name - description` uses a leading `-`
  // between the name and the description — strip it so the
  // description doesn't end up with a stray dash.
  if rest.has_prefix("-") {
    rest = rest
      .substring(start=1, end=rest.length())
      .to_string()
      .trim_start()
      .to_string()
  }
  (head, rest)
}
