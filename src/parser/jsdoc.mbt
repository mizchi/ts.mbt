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
#derive(Debug)
pub(all) struct JsdocBlock {
  description : String
  tags : Array[JsdocTag]
}

///|
#deprecated
pub extend JsdocBlock with @debug.Debug::{to_repr}

///|
#derive(Eq, Debug)
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
}

///|
#deprecated
pub extend JsdocTag with Eq::{not_equal, equal}

///|
#deprecated
pub extend JsdocTag with @debug.Debug::{to_repr}

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
  let description = StringBuilder()
  let mut description_started = false
  let tags : Array[JsdocTag] = []
  let mut current_tag_name = ""
  let tag_content = StringBuilder()
  let mut in_description = true
  fn flush_tag() {
    tags.push(
      interpret_tag(
        current_tag_name,
        jsdoc_trim_end(tag_content.to_string()).to_owned(),
      ),
    )
  }

  // Lines by index rather than `split("\n")`, whose iterator was a tenth of
  // the cost of a doc block. Same lines: a trailing `\n` still yields a
  // final empty line, and an empty body yields one empty line.
  let body_len = body.length()
  let mut line_start = 0
  for k in 0..=body_len {
    if k < body_len && body[k] != '\n' {
      continue
    }
    let line = body[line_start:k]
    line_start = k + 1
    // Strip the leading `*` (with optional space) that the JSDoc
    // convention puts on every continuation line; lines without the
    // marker keep their original indentation.
    let star_trimmed = jsdoc_trim_start(line)
    let cleaned = if star_trimmed.has_prefix("* ") {
      star_trimmed[2:]
    } else if star_trimmed.has_prefix("*") {
      star_trimmed[1:]
    } else {
      line
    }
    let trimmed = jsdoc_trim_start(cleaned)
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
    description: jsdoc_trim(description.to_string()).to_owned(),
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
  let rest = jsdoc_trim_start(s[i:])
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
  let trimmed = jsdoc_trim_start(s)
  if trimmed.length() == 0 || trimmed[0] != '{' {
    return (None, trimmed.to_owned())
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
        let inner = jsdoc_trim(trimmed[1:i]).to_owned()
        let rest = jsdoc_trim_start(trimmed[i + 1:]).to_owned()
        return (Some(inner), rest)
      }
    }
    i = i + 1
  }
  (None, trimmed.to_owned())
}

///|
/// Split off the first whitespace-delimited word — useful for
/// `@param TYPE NAME description` shapes.
fn split_first_word(s : String) -> (String, String) {
  let trimmed = jsdoc_trim_start(s)
  let mut i = 0
  while i < trimmed.length() {
    let c = trimmed[i]
    if c == ' ' || c == '\t' || c == '\n' || c == '-' {
      break
    }
    i = i + 1
  }
  if i == 0 {
    return ("", trimmed.to_owned())
  }
  let head = trimmed[0:i].to_owned()
  let mut rest = jsdoc_trim_start(trimmed[i:])
  // The convention `@param name - description` uses a leading `-`
  // between the name and the description — strip it so the
  // description doesn't end up with a stray dash.
  if rest.has_prefix("-") {
    rest = jsdoc_trim_start(rest[1:])
  }
  (head, rest.to_owned())
}

///|
/// `StringView::trim_start()` with its default set (`"\t\n\r "`), spelled
/// out. The library version builds a character set from its `chars`
/// argument on every call, which made trimming most of the cost of
/// parsing a doc block; every doc comment in a `.d.ts` is parsed eagerly.
fn jsdoc_trim_start(v : StringView) -> StringView {
  let mut i = 0
  while i < v.length() {
    let c = v[i]
    if c == ' ' || c == '\t' || c == '\n' || c == '\r' {
      i = i + 1
    } else {
      break
    }
  }
  v[i:]
}

///|
/// `StringView::trim_end()` with its default set; see `jsdoc_trim_start`.
fn jsdoc_trim_end(v : StringView) -> StringView {
  let mut j = v.length()
  while j > 0 {
    let c = v[j - 1]
    if c == ' ' || c == '\t' || c == '\n' || c == '\r' {
      j = j - 1
    } else {
      break
    }
  }
  v[:j]
}

///|
/// `StringView::trim()` with its default set; see `jsdoc_trim_start`.
fn jsdoc_trim(v : StringView) -> StringView {
  jsdoc_trim_end(jsdoc_trim_start(v))
}

///|
/// A JSDoc block as MoonBit doc-comment lines, without the `/// ` prefix:
/// the description, then one line per documentation tag. Tags that are
/// instructions to a tool rather than documentation (`@internal`,
/// `@__PURE__`, visibility markers, `@template`, `@typedef`) are left out,
/// and so is a block that ends up with nothing to say.
pub fn jsdoc_doc_lines(jb : JsdocBlock) -> Array[String] {
  let out : Array[String] = []
  for line in jb.description.trim().split("\n") {
    out.push(line.trim_end().to_owned())
  }
  if out.length() == 1 && out[0] == "" {
    let _ = out.pop()
  }
  let tags : Array[String] = []
  for t in jb.tags {
    match t {
      Param(name, _, desc) => tags.push("- `\{name}`: \{desc.trim()}")
      Returns(_, desc) if desc.trim() != "" =>
        tags.push("Returns: \{desc.trim()}")
      Throws(_, desc) if desc.trim() != "" =>
        tags.push("Throws: \{desc.trim()}")
      Deprecated(msg) =>
        tags.push(
          if msg.trim() == "" {
            "Deprecated."
          } else {
            "Deprecated: \{msg.trim()}"
          },
        )
      See(target) => tags.push("See: \{target.trim()}")
      // Doc comments are Markdown, and an `@example` is code.
      Example(code) => {
        tags.push("Example:")
        tags.push("```")
        for line in code.trim().split("\n") {
          tags.push(line.trim_end().to_owned())
        }
        tags.push("```")
      }
      _ => ()
    }
  }
  if out.length() > 0 && tags.length() > 0 {
    out.push("")
  }
  for t in tags {
    out.push(t)
  }
  // Every entry is ONE line: a tag's text can span several (vitest's
  // `@param` lists do), and a doc-comment consumer prefixes each entry
  // with `///` — a continuation line left inside an entry would come out
  // as bare source text.
  let flat : Array[String] = []
  for entry in out {
    for line in entry.split("\n") {
      flat.push(jsdoc_inline_links(line.trim_end().to_owned()))
    }
  }
  flat
}

///|
/// JSDoc inline links as Markdown (doc comments are Markdown):
/// `{@link Name}` -> `` `Name` ``, `{@link https://u}` -> `<https://u>`,
/// `{@link https://u text}` -> `[text](https://u)`, and
/// `{@link Name text}` / `{@link Name|text}` -> ``text (`Name`)``.
/// `@linkcode` and `@linkplain` are read the same way. An unterminated
/// tag is left as written.
fn jsdoc_inline_links(line : String) -> String {
  if !line.contains("{@link") {
    return line
  }
  let out = StringBuilder()
  let mut rest = line
  while true {
    guard rest.find("{@link") is Some(start) else { break }
    guard rest[start:].find("}") is Some(len) else { break }
    out.write_string(rest[:start].to_owned())
    let inner = rest[start + 1:start + len].to_owned()
    // Drop the tag name (`@link`, `@linkcode`, `@linkplain`).
    let body = match inner.find(" ") {
      Some(i) => inner[i + 1:].trim().to_owned()
      None => ""
    }
    out.write_string(jsdoc_link_markdown(body))
    rest = rest[start + len + 1:].to_owned()
  }
  out.write_string(rest)
  out.to_string()
}

///|
fn jsdoc_link_markdown(body : String) -> String {
  let (target, text) = match body.find("|") {
    Some(i) => (body[:i].trim().to_owned(), body[i + 1:].trim().to_owned())
    None =>
      match body.find(" ") {
        Some(i) => (body[:i].to_owned(), body[i + 1:].trim().to_owned())
        None => (body, "")
      }
  }
  if target == "" {
    return text
  }
  let is_url = target.has_prefix("http://") || target.has_prefix("https://")
  match (is_url, text == "") {
    (true, true) => "<\{target}>"
    (true, false) => "[\{text}](\{target})"
    (false, true) => "`\{target}`"
    (false, false) => "\{text} (`\{target}`)"
  }
}
