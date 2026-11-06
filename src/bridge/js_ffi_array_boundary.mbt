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
/// (`Array[Array[T]]`), inside a `Promise` (through the generated
/// `Promise::map`), and inside a CALLBACK's parameters or result. A struct
/// field holds its JS array itself and is typed `FixedArray` by the struct
/// renderer instead.
///
/// A callback is converted by handing the other side a wrapper closure,
/// and JS observes function identity: `off(event, cb)` and
/// `removeEventListener` find a listener by it. So a wrapper is made once
/// per original function and reused (`__ts_mbt_cb_memo`, a pair of
/// `WeakMap`s on `globalThis` that every generated package shares), and
/// wrapping a wrapper returns its original — `set_x(get_x())` hands JS
/// back the very function it handed out.
///
/// Fail direction: any extern whose shape this pass does not recognise —
/// an attribute other than `#module(...)`, a header that does not parse,
/// a labelled parameter — is left untouched, which keeps the deprecation
/// warning rather than inventing a wrong signature.
///
/// The READ-direction struct pass (`migrate_js_ffi_struct_reads`) runs on
/// the result, so every caller of this pass gets both and no call site can
/// apply one and forget the other.
pub fn migrate_js_ffi_array_boundaries(mbt : String) -> String {
  migrate_js_ffi_struct_reads(js_ffi_migrate_array_boundaries_only(mbt))
}

///|
fn js_ffi_migrate_array_boundaries_only(mbt : String) -> String {
  if !mbt.contains("Array[") {
    return mbt
  }
  // `Promise[T]` is converted through the generated `Promise::map`, so only
  // in a package that defines it.
  let promise_map = mbt.contains("fn[T, U] Promise::map(")
  let lines : Array[String] = mbt
    .split("\n")
    .map(fn(l) { l.to_owned() })
    .collect()
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
    match js_ffi_migrate_extern(promise_map, line, body, attrs) {
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
  let result = out.join("\n")
  // The callback conversion calls two helpers; emit them once, and only in
  // a package that uses them.
  if result.contains("__ts_mbt_cb_memo(") &&
    !result.contains("fn __ts_mbt_cb_memo(") {
    result + "\n\n" + js_ffi_callback_helpers
  } else {
    result
  }
}

///|
/// The helpers a converted callback calls. `__ts_mbt_cb_memo(f, make)`
/// returns the wrapper for `f`, building it with `make` the first time;
/// if `f` is itself a wrapper it returns the original instead. The maps
/// are WEAK, so neither a callback nor its wrapper is kept alive by them.
let js_ffi_callback_helpers : String =
  #|///|
  #|fn[A, B] __ts_mbt_cb_cast(value : A) -> B = "%identity"
  #|
  #|///|
  #|#external
  #|priv type TsMbtCallbackRef
  #|
  #|///|
  #|extern "js" fn __ts_mbt_cb_memo(f : TsMbtCallbackRef, make : () -> TsMbtCallbackRef) -> TsMbtCallbackRef =
  #|  #| (f, make) => { const s = (globalThis.__ts_mbt_callbacks ??= { wrap: new WeakMap(), orig: new WeakMap() }); const o = s.orig.get(f); if (o !== undefined) return o; let w = s.wrap.get(f); if (w === undefined) { w = make(); s.wrap.set(f, w); s.orig.set(w, f); } return w; }

///|
fn js_ffi_is_extern_header(line : String) -> Bool {
  (
    line.has_prefix("extern \"js\" fn") ||
    line.has_prefix("pub extern \"js\" fn")
  ) &&
  line.contains(") -> ") &&
  (line.has_suffix(" =") || line.has_suffix("\""))
}

///|
/// A parameter / return type as this pass sees it: an `Array`, an optional,
/// a `Promise`, or anything else (left as written).
priv enum JsFfiArrayType {
  Leaf(String)
  Arr(JsFfiArrayType)
  Opt(JsFfiArrayType)
  /// `Promise[T]`, converted through the generated `Promise::map`; only
  /// parsed when that method is in the same package (`promise_map`).
  Prom(JsFfiArrayType)
  /// A callback `(P, ..) -> R`.
  Func(Array[JsFfiArrayType], JsFfiArrayType)
}

///|
fn js_ffi_parse_type(t : String, promise_map : Bool) -> JsFfiArrayType {
  let t = t.trim().to_owned()
  // A function type is recognised first, because `(A) -> B?` is a function
  // RETURNING `B?` and the `?` suffix test below must not see it.
  if t.has_prefix("(") {
    guard js_ffi_bracket_close(t, 0) is Some(close) else { return Leaf(t) }
    if t[close + 1:].has_prefix(" -> ") {
      let ret_src = t[close + 1 + " -> ".length():].to_owned()
      // A wrapper would have to restate an effect, and none occurs.
      if ret_src.contains("raise") || t.has_prefix("async") {
        return Leaf(t)
      }
      let params = js_ffi_split_top(t[1:close].to_owned()).map(fn(p) {
        js_ffi_parse_type(p, promise_map)
      })
      let parsed = Func(params, js_ffi_parse_type(ret_src, promise_map))
      return if js_ffi_needs(parsed) { parsed } else { Leaf(t) }
    }
    // A parenthesised type, `((A) -> B)`; a tuple `(A, B)` stays a leaf.
    if close == t.length() - 1 {
      let inner = t[1:close].to_owned()
      if js_ffi_split_top(inner).length() == 1 {
        let parsed = js_ffi_parse_type(inner, promise_map)
        if js_ffi_needs(parsed) {
          return parsed
        }
      }
      return Leaf(t)
    }
  }
  if t.has_suffix("?") {
    let inner = js_ffi_parse_type(t[:t.length() - 1].to_owned(), promise_map)
    if js_ffi_needs(inner) {
      return Opt(inner)
    }
    return Leaf(t)
  }
  if t.has_prefix("Array[") &&
    t.has_suffix("]") &&
    js_ffi_bracket_close(t, 5) == Some(t.length() - 1) {
    return Arr(
      js_ffi_parse_type(
        t["Array[".length():t.length() - 1].to_owned(),
        promise_map,
      ),
    )
  }
  if promise_map &&
    t.has_prefix("Promise[") &&
    t.has_suffix("]") &&
    js_ffi_bracket_close(t, 7) == Some(t.length() - 1) {
    let inner = js_ffi_parse_type(
      t["Promise[".length():t.length() - 1].to_owned(),
      promise_map,
    )
    if js_ffi_needs(inner) {
      return Prom(inner)
    }
  }
  Leaf(t)
}

///|
/// Index of the bracket that closes the one opening at `open`.
fn js_ffi_bracket_close(t : String, open : Int32) -> Int32? {
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
    Arr(_) => true
    Opt(a) | Prom(a) => js_ffi_needs(a)
    Func(ps, r) => js_ffi_needs(r) || ps.iter().any(js_ffi_needs)
  }
}

///|
/// The type at the boundary (`fixed`) or as the wrapper promises it.
fn js_ffi_type_text(t : JsFfiArrayType, fixed : Bool) -> String {
  match t {
    Leaf(s) => s
    Arr(e) => {
      let head = if fixed { "FixedArray" } else { "Array" }
      "\{head}[\{js_ffi_type_text(e, fixed)}]"
    }
    Opt(Func(_, _) as f) => "(\{js_ffi_type_text(f, fixed)})?"
    Opt(a) => "\{js_ffi_type_text(a, fixed)}?"
    Prom(a) => "Promise[\{js_ffi_type_text(a, fixed)}]"
    Func(ps, r) => {
      let params = ps.map(fn(p) { js_ffi_type_text(p, fixed) }).join(", ")
      "(\{params}) -> \{js_ffi_type_text(r, fixed)}"
    }
  }
}

///|
fn js_ffi_render(t : JsFfiArrayType) -> String {
  js_ffi_type_text(t, true)
}

///|
fn js_ffi_original(t : JsFfiArrayType) -> String {
  js_ffi_type_text(t, false)
}

///|
/// A conversion that is the identity is written as no conversion at all.
fn js_ffi_convert(
  expr : String,
  t : JsFfiArrayType,
  depth : Int32,
  to_ffi : Bool,
) -> String {
  if !js_ffi_needs(t) {
    return expr
  }
  let v = "v\{depth}"
  match t {
    Leaf(_) => expr
    Arr(e) =>
      if to_ffi {
        if js_ffi_needs(e) {
          "FixedArray::from_array(\{expr}.map(fn(\{v}) { \{js_ffi_convert(v, e, depth + 1, true)} }))"
        } else {
          "FixedArray::from_array(\{expr})"
        }
      } else if js_ffi_needs(e) {
        "Array::from_fixed_array(\{expr}).map(fn(\{v}) { \{js_ffi_convert(v, e, depth + 1, false)} })"
      } else {
        "Array::from_fixed_array(\{expr})"
      }
    // `Option::map` and the generated `Promise::map` alike.
    Opt(a) | Prom(a) =>
      "\{expr}.map(fn(\{v}) { \{js_ffi_convert(v, a, depth + 1, to_ffi)} })"
    Func(ps, r) => {
      // The wrapper is CALLED by the side it is handed to: its parameters
      // arrive from there, so they convert the opposite way, and its result
      // goes back. Its types are that side's (`to_ffi`: the FixedArray ones).
      let f = "f\{depth}"
      let names = ps.mapi(fn(i, _) { "a\{depth}_\{i}" })
      let typed = ps
        .mapi(fn(i, p) { "\{names[i]} : \{js_ffi_type_text(p, to_ffi)}" })
        .join(", ")
      let args = ps
        .mapi(fn(i, p) { js_ffi_convert(names[i], p, depth + 1, !to_ffi) })
        .join(", ")
      let call = js_ffi_convert("\{f}(\{args})", r, depth + 1, to_ffi)
      let ret = js_ffi_type_text(r, to_ffi)
      // Bound once: `expr` may be a call (an extern's result).
      "{ let \{f} = \{expr}; __ts_mbt_cb_cast(__ts_mbt_cb_memo(__ts_mbt_cb_cast(\{f}), fn() { __ts_mbt_cb_cast(fn(\{typed}) -> \{ret} { \{call} }) })) }"
    }
  }
}

///|
/// MoonBit value -> the extern's argument.
fn js_ffi_to_ffi(expr : String, t : JsFfiArrayType, depth : Int32) -> String {
  js_ffi_convert(expr, t, depth, true)
}

///|
/// The extern's result -> the MoonBit value the wrapper promises.
fn js_ffi_from_ffi(expr : String, t : JsFfiArrayType, depth : Int32) -> String {
  js_ffi_convert(expr, t, depth, false)
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
  promise_map : Bool,
  header : String,
  body : Array[String],
  attrs : Array[String],
) -> Array[String]? {
  for a in attrs {
    if !a.has_prefix("#module(") {
      return None
    }
  }
  guard js_ffi_split_extern_header(header)
    is Some((is_pub, generics, name, raw_params, ret_src, body_tail)) else {
    return None
  }
  let params : Array[(String, JsFfiArrayType)] = []
  for p in raw_params {
    params.push((p.0, js_ffi_parse_type(p.1, promise_map)))
  }
  let ret = js_ffi_parse_type(ret_src, promise_map)
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
/// An `extern "js" fn` header split into what a rewriting pass needs:
/// visibility, the generics suffix (`[T]` or empty), the name, each
/// parameter as `(name, type source)`, the return type source and the body
/// tail starting at ` =`. `None` for a shape it does not recognise — a
/// labelled or optional parameter, a missing return — so a pass leaves that
/// extern alone. Shared by every pass over the generated externs, because a
/// second parser is a second answer to what a header says.
fn js_ffi_split_extern_header(
  header : String,
) -> (Bool, String, String, Array[(String, String)], String, String)? {
  let is_pub = header.has_prefix("pub ")
  guard header.find("fn") is Some(fn_at) else { return None }
  let after_fn = header[fn_at + 2:].to_owned()
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
  let params : Array[(String, String)] = []
  for p in js_ffi_split_top(params_src) {
    guard p.find(" : ") is Some(sep) else { return None }
    let pname = p[:sep].to_owned().trim().to_owned()
    if pname == "" || pname.contains("~") || pname.contains("?") {
      return None
    }
    params.push((pname, p[sep + 3:].to_owned()))
  }
  Some((is_pub, generics, name, params, ret_src, body_tail))
}

///|
/// `Array` -> `FixedArray` inside the TYPE ARGUMENTS of the generic types
/// this package declares (`Promise[ReadVResult[Array[T]]]` ->
/// `Promise[ReadVResult[FixedArray[T]]]`), at every occurrence.
///
/// A generated generic type mirrors JS data: its type arguments describe
/// the JS values it holds, and a JS array is a `FixedArray` — the reason
/// struct fields render as `FixedArray` (`ffi_struct_decl_field_type_name`).
/// node's `ReadVResult[T]` is the case: `T` is the TypeScript `TBuffers`,
/// its field `buffers` is already `FixedArray`, and an `Array` argument
/// would contradict it. Only STRUCTS declared in `decl_source` are touched,
/// so a builtin, an imported generic or an opaque `type` (the package's own
/// `Promise[T]`) keeps its argument, and the same
/// rewrite is applied to `.mbt` and `.mbti` so the two cannot disagree.
pub fn migrate_generic_type_arg_arrays(
  text : String,
  decl_source : String,
) -> String {
  let names = js_ffi_declared_generic_type_names(decl_source)
  if names.is_empty() || !text.contains("Array[") {
    return text
  }
  js_ffi_rewrite_generic_args(text, names)
}

///|
/// Indexes are UTF-16 code units throughout, matching `text[a:b]`: the
/// generated text carries JSDoc in any language, and a code-point index
/// would drift from the slice index after the first non-ASCII character.
fn js_ffi_rewrite_generic_args(text : String, names : Set[String]) -> String {
  let out = StringBuilder()
  let n = text.length()
  let mut copied = 0
  let mut i = 0
  while i < n {
    let at_boundary = i == 0 || !js_ffi_is_ident_unit(text[i - 1])
    if !(at_boundary && js_ffi_is_ident_start_unit(text[i])) {
      i += 1
      continue
    }
    let mut j = i
    while j < n && js_ffi_is_ident_unit(text[j]) {
      j += 1
    }
    if j < n && text[j] == '[' && names.contains(text[i:j].to_owned()) {
      match js_ffi_bracket_close(text, j) {
        Some(close) => {
          out.write_string(text[copied:j + 1].to_owned())
          // The arguments may hold further declared generics.
          let args = js_ffi_rewrite_generic_args(
            text[j + 1:close].to_owned(),
            names,
          )
          out.write_string(ffi_fixed_array_type_text(args))
          out.write_string("]")
          copied = close + 1
          i = close + 1
          continue
        }
        None => ()
      }
    }
    i = j
  }
  out.write_string(text[copied:].to_owned())
  out.to_string()
}

///|
fn js_ffi_is_ident_start_unit(c : UInt16) -> Bool {
  (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_'
}

///|
fn js_ffi_is_ident_unit(c : UInt16) -> Bool {
  js_ffi_is_ident_start_unit(c) || (c >= '0' && c <= '9')
}

///|
/// Generic structs declared in generated MoonBit: `struct Name[` at the
/// start of a line, with any of the generator's visibility prefixes.
fn js_ffi_declared_generic_type_names(mbt : String) -> Set[String] {
  let names : Set[String] = Set([])
  // Structs only: a struct's fields are what render as `FixedArray`.
  // A generic `type` such as the package's own `Promise[T]` is an opaque
  // handle, and the boundary pass keeps `Promise[Array[_]]` public on
  // purpose.
  let prefixes = [
    "pub(all) struct ", "pub struct ", "struct ", "declare pub(all) struct ",
  ]
  for line in mbt.split("\n") {
    for prefix in prefixes {
      if line.has_prefix(prefix) {
        let rest = line[prefix.length():].to_owned()
        match rest.find("[") {
          Some(open) => {
            let name = rest[:open].to_owned()
            if name != "" &&
              name
              .iter()
              .all(fn(c) {
                c.is_ascii_alphabetic() || c.is_ascii_digit() || c == '_'
              }) {
              names.add(name)
            }
          }
          None => ()
        }
        break
      }
    }
  }
  names
}
