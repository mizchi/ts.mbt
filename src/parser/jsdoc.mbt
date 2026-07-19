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
  parse_jsdoc_block_view(text[:])
}

///|
/// View-based implementation of `parse_jsdoc_block`. Runs once per
/// `/**` comment during lexing, so it stays single-pass and slices the
/// comment span in place — building per-line owned strings here used to
/// dominate whole-file parse profiles on comment-heavy inputs like
/// es5.d.ts.
fn parse_jsdoc_block_view(text : StringView) -> JsdocBlock? {
  if !text.has_prefix("/**") {
    return None
  }
  let body_end = if text.has_suffix("*/") {
    text.length() - 2
  } else {
    text.length()
  }
  if body_end <= 3 {
    return None
  }
  let body = text[3:body_end]
  // Accumulators. The description and each tag's content are built by
  // appending cleaned line views separated by '\n', matching the old
  // join("\n") shape exactly.
  let description = StringBuilder::new()
  let mut description_started = false
  let tags : Array[JsdocTag] = []
  let mut current_tag_name = ""
  let tag_content = StringBuilder::new()
  let mut in_description = true
  fn flush_tag() {
    tags.push(
      interpret_tag(
        current_tag_name,
        tag_content.to_string().trim_end().to_owned(),
      ),
    )
  }

  for line in body.split("\n") {
    // Strip the leading `*` (with optional space) that the JSDoc
    // convention puts on every continuation line; lines without the
    // marker keep their original indentation.
    let star_trimmed = line.trim_start()
    let cleaned = if star_trimmed.has_prefix("* ") {
      star_trimmed[2:]
    } else if star_trimmed.has_prefix("*") {
      star_trimmed[1:]
    } else {
      line
    }
    let trimmed = cleaned.trim_start()
    if trimmed.has_prefix("@") {
      // Flush whatever we were collecting.
      if !in_description {
        flush_tag()
        tag_content.reset()
      }
      in_description = false
      // Split into tag name + rest. Tag name is `[a-zA-Z0-9_]+` or
      // the special `__PURE__` / `__NO_SIDE_EFFECTS__` marker.
      let (name, body_view) = split_tag_head(trimmed[1:])
      current_tag_name = name
      tag_content.write_view(body_view)
    } else if in_description {
      if description_started {
        description.write_char('\n')
      }
      description.write_view(cleaned)
      description_started = description_started || cleaned.length() > 0
    } else {
      tag_content.write_char('\n')
      tag_content.write_view(cleaned)
    }
  }
  // Flush the trailing tag.
  if !in_description {
    flush_tag()
  }
  let block : JsdocBlock = {
    description: description.to_string().trim().to_owned(),
    tags,
  }
  if block.is_empty() {
    None
  } else {
    Some(block)
  }
}

///|
/// Split a tag line (post-`@`) into `(tag_name, rest)`.
/// `paramName description` → `("paramName", "description")`.
fn split_tag_head(s : StringView) -> (String, StringView) {
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
  let name = s[0:i].to_owned()
  let rest = s[i:].trim_start()
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
  let trimmed = s.trim_start().to_owned()
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
        let inner = trimmed[1:i].to_owned().trim().to_owned()
        let rest = trimmed[i + 1:].to_owned().trim_start().to_owned()
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
  let trimmed = s.trim_start().to_owned()
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
  let head = trimmed[0:i].to_owned()
  let mut rest = trimmed[i:].to_owned().trim_start().to_owned()
  // The convention `@param name - description` uses a leading `-`
  // between the name and the description — strip it so the
  // description doesn't end up with a stray dash.
  if rest.has_prefix("-") {
    rest = rest[1:].to_owned().trim_start().to_owned()
  }
  (head, rest)
}
