///|
/// `Array` at the `extern "js"` boundary is deprecated on the JS backend
/// (warning 0020) ahead of a change to `Array`'s runtime layout: today an
/// `Array[T]` and a `FixedArray[T]` are both a plain JS array, and once
/// they are not, an extern typed `Array[T]` stops lining up with the
/// arrays JavaScript hands over. `FixedArray` is the representation FFI
/// code is asked to use.
///
/// This pass rewrites the generated `.mbt` text once, at the point it
/// leaves the generator, instead of at each of the ~60 sites that render
/// an extern — a rule written per site is a rule applied at some of them.
/// An extern whose parameter or return carries `Array` keeps its JS body
/// unchanged and becomes PRIVATE with a `FixedArray` signature under a
/// minted `__ts_mbt_ffi_` name; a wrapper with the ORIGINAL name,
/// visibility and signature converts at the boundary. So no generated
/// public signature changes and no caller changes.
///
/// Covered positions are the ones a value conversion can reach: a bare
/// `Array[T]`, an optional `Array[T]?` (which crosses as `undefined` or a
/// plain array either way, probed) and `Array` nested in those
/// (`Array[Array[T]]`). An `Array` inside another type constructor
/// (`Promise[Array[T]]`, a callback's parameter, a struct field) has no
/// boundary at which a wrapper could convert it and is left as it is.
///
/// Fail direction: any extern whose shape this pass does not recognise —
/// an attribute other than `#module(...)`, a header that does not parse,
/// a labelled parameter — is left untouched, which keeps the deprecation
/// warning rather than inventing a wrong signature.
pub fn migrate_js_ffi_array_boundaries(mbt : String) -> String {
  if !mbt.contains("Array[") {
    return mbt
  }
  let lines : Array[String] = mbt.split("\n").map(fn(l) { l.to_owned() }).collect()
  let out : Array[String] = []
  let mut i = 0
  while i < lines.length() {
    let line = lines[i]
    if !js_ffi_is_extern_header(line) {
      out.push(line)
      i += 1
      continue
    }
    // The body: a `= "name"` on the header itself, or the `#|` lines
    // that follow it.
    let mut end = i + 1
    if line.has_suffix(" =") {
      while end < lines.length() && lines[end].trim_start().has_prefix("#|") {
        end += 1
      }
    }
    let body = lines[i + 1:end].to_owned()
    // Attribute lines directly above the header belong to the extern.
    let mut attr_start = out.length()
    while attr_start > 0 && out[attr_start - 1].has_prefix("#") {
      attr_start -= 1
    }
    let attrs = out[attr_start:].to_owned()
    match js_ffi_migrate_extern(line, body, attrs) {
      Some(rewritten) => {
        while out.length() > attr_start {
          let _ = out.pop()
        }
        for l in rewritten {
          out.push(l)
        }
      }
      None => {
        out.push(line)
        for l in body {
          out.push(l)
        }
      }
    }
    i = end
  }
  out.join("\n")
}

///|
fn js_ffi_is_extern_header(line : String) -> Bool {
  (line.has_prefix("extern \"js\" fn") ||
  line.has_prefix("pub extern \"js\" fn")) &&
  line.contains(") -> ") &&
  (line.has_suffix(" =") || line.has_suffix("\""))
}

///|
/// A parameter / return type as this pass sees it: an `Array`, an optional
/// `Array`, or anything else (left as written).
priv enum JsFfiArrayType {
  Leaf(String)
  Arr(JsFfiArrayType)
  Opt(JsFfiArrayType)
}

///|
fn js_ffi_parse_type(t : String) -> JsFfiArrayType {
  let t = t.trim().to_owned()
  if t.has_suffix("?") {
    let inner = js_ffi_parse_type(t[:t.length() - 1].to_owned())
    match inner {
      Arr(_) => return Opt(inner)
      _ => return Leaf(t)
    }
  }
  if t.has_prefix("Array[") && t.has_suffix("]") &&
    js_ffi_bracket_close(t, 5) == Some(t.length() - 1) {
    return Arr(js_ffi_parse_type(t["Array[".length():t.length() - 1].to_owned()))
  }
  Leaf(t)
}

///|
/// Index of the bracket that closes the one opening at `open`.
fn js_ffi_bracket_close(t : String, open : Int) -> Int? {
  let mut depth = 0
  for i in open..<t.length() {
    let c = t[i]
    if c == '[' || c == '(' {
      depth += 1
    } else if c == ']' || c == ')' {
      depth -= 1
      if depth == 0 {
        return Some(i)
      }
    }
  }
  None
}

///|
fn js_ffi_needs(t : JsFfiArrayType) -> Bool {
  match t {
    Leaf(_) => false
    Arr(_) | Opt(_) => true
  }
}

///|
fn js_ffi_render(t : JsFfiArrayType) -> String {
  match t {
    Leaf(s) => s
    Arr(e) => "FixedArray[\{js_ffi_render(e)}]"
    Opt(a) => "\{js_ffi_render(a)}?"
  }
}

///|
/// MoonBit value -> the extern's argument.
fn js_ffi_to_ffi(expr : String, t : JsFfiArrayType, depth : Int) -> String {
  let v = "v\{depth}"
  match t {
    Leaf(_) => expr
    Arr(e) =>
      if js_ffi_needs(e) {
        "FixedArray::from_array(\{expr}.map(fn(\{v}) { \{js_ffi_to_ffi(v, e, depth + 1)} }))"
      } else {
        "FixedArray::from_array(\{expr})"
      }
    Opt(a) => "\{expr}.map(fn(\{v}) { \{js_ffi_to_ffi(v, a, depth + 1)} })"
  }
}

///|
/// The extern's result -> the MoonBit value the wrapper promises.
fn js_ffi_from_ffi(expr : String, t : JsFfiArrayType, depth : Int) -> String {
  let v = "v\{depth}"
  match t {
    Leaf(_) => expr
    Arr(e) =>
      if js_ffi_needs(e) {
        "Array::from_fixed_array(\{expr}).map(fn(\{v}) { \{js_ffi_from_ffi(v, e, depth + 1)} })"
      } else {
        "Array::from_fixed_array(\{expr})"
      }
    Opt(a) => "\{expr}.map(fn(\{v}) { \{js_ffi_from_ffi(v, a, depth + 1)} })"
  }
}

///|
/// Split at top-level commas.
fn js_ffi_split_top(s : String) -> Array[String] {
  let parts : Array[String] = []
  let mut depth = 0
  let mut start = 0
  for i in 0..<s.length() {
    let c = s[i]
    if c == '[' || c == '(' {
      depth += 1
    } else if c == ']' || c == ')' {
      depth -= 1
    } else if c == ',' && depth == 0 {
      parts.push(s[start:i].to_owned())
      start = i + 1
    }
  }
  let last = s[start:].to_owned()
  if last.trim() != "" {
    parts.push(last)
  }
  parts
}

///|
fn js_ffi_migrate_extern(
  header : String,
  body : Array[String],
  attrs : Array[String],
) -> Array[String]? {
  for a in attrs {
    if !a.has_prefix("#module(") {
      return None
    }
  }
  let is_pub = header.has_prefix("pub ")
  let after_fn = header[header.find("fn").unwrap() + 2:].to_owned()
  // Optional generics: `fn[T] name(...)`.
  let (generics, rest) = if after_fn.has_prefix("[") {
    guard js_ffi_bracket_close(after_fn, 0) is Some(close) else { return None }
    (after_fn[:close + 1].to_owned(), after_fn[close + 1:].to_owned())
  } else {
    ("", after_fn)
  }
  let rest = rest.trim_start().to_owned()
  guard rest.find("(") is Some(open) else { return None }
  let name = rest[:open].to_owned()
  if name == "" || name.contains(" ") {
    return None
  }
  guard js_ffi_bracket_close(rest, open) is Some(close) else { return None }
  let params_src = rest[open + 1:close].to_owned()
  let tail = rest[close + 1:].to_owned()
  guard tail.has_prefix(" -> ") else { return None }
  // The return type runs to the ` =` that introduces the body.
  guard tail.rev_find(" =") is Some(eq) else { return None }
  let ret_src = tail[" -> ".length():eq].to_owned()
  let body_tail = tail[eq:].to_owned()
  let params : Array[(String, JsFfiArrayType)] = []
  for p in js_ffi_split_top(params_src) {
    guard p.find(" : ") is Some(sep) else { return None }
    let pname = p[:sep].to_owned().trim().to_owned()
    if pname == "" || pname.contains("~") || pname.contains("?") {
      return None
    }
    params.push((pname, js_ffi_parse_type(p[sep + 3:].to_owned())))
  }
  let ret = js_ffi_parse_type(ret_src)
  if !js_ffi_needs(ret) && !params.iter().any(fn(p) { js_ffi_needs(p.1) }) {
    return None
  }
  let ffi_name = "__ts_mbt_ffi_" + name.replace_all(old="::", new="__")
  // The private extern is a FREE function, where a first parameter named
  // `self` is the deprecated `fn meth(self : Type)` method syntax
  // (warning 0027). The JS body binds its arguments by position, so the
  // extern's MoonBit parameter names are free to differ from the body's.
  let ffi_params = params
    .map(fn(p) {
      let pname = if p.0 == "self" { "receiver" } else { p.0 }
      "\{pname} : \{js_ffi_render(p.1)}"
    })
    .join(", ")
  let orig_params = params
    .map(fn(p) { "\{p.0} : \{js_ffi_original(p.1)}" })
    .join(", ")
  let args = params.map(fn(p) { js_ffi_to_ffi(p.0, p.1, 0) }).join(", ")
  let call = js_ffi_from_ffi("\{ffi_name}(\{args})", ret, 0)
  let out : Array[String] = []
  for a in attrs {
    out.push(a)
  }
  out.push(
    "extern \"js\" fn\{generics} \{ffi_name}(\{ffi_params}) -> \{js_ffi_render(ret)}\{body_tail}",
  )
  for l in body {
    out.push(l)
  }
  out.push("")
  let vis = if is_pub { "pub " } else { "" }
  out.push(
    "\{vis}fn\{generics} \{name}(\{orig_params}) -> \{js_ffi_original(ret)} {",
  )
  out.push("  \{call}")
  out.push("}")
  Some(out)
}

///|
fn js_ffi_original(t : JsFfiArrayType) -> String {
  match t {
    Leaf(s) => s
    Arr(e) => "Array[\{js_ffi_original(e)}]"
    Opt(a) => "\{js_ffi_original(a)}?"
  }
}
