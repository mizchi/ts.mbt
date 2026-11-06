///|
/// Route every extern RETURN that carries a read-converted struct through
/// its `bridge.js` converter (`struct_read_converter.mbt`).
///
/// The struct set arrives on one marker line the generator writes into the
/// `.mbt` (`ffi_struct_reads_marker`); this pass reads it and removes it.
/// Like the `FixedArray` pass it runs after, it rewrites the text once
/// rather than at each renderer: most struct-returning externs are INLINE
/// lambdas (`(self, a, b) => self.getSemanticDiagnostics(a, b)`), and an
/// inline lambda cannot import a `bridge.js` helper, so the conversion has
/// to happen on the MoonBit side of the boundary. An extern whose return
/// holds such a struct (bare, in a `FixedArray`, optional, or in a
/// `Promise` when the package defines `Promise::map`) becomes private under
/// a minted `__ts_mbt_rs_` name, and a wrapper with the original name,
/// visibility and signature converts. No public signature changes.
///
/// The converter is reached through a non-generic extern over an opaque
/// ref type and a `%identity` cast, so one helper serves a generic struct at
/// any instantiation, and the helper's ` = "__ts_mbt_..."` binding is the
/// shape that gets the `bridge.js` `#module` attached downstream. Helpers
/// are emitted only for structs some wrapper uses.
///
/// Fail direction: an extern this cannot parse, or one with an attribute
/// other than `#module(...)`, keeps returning the raw value, as before.
pub fn migrate_js_ffi_struct_reads(mbt : String) -> String {
  guard mbt.find(ffi_struct_reads_marker) is Some(_) else { return mbt }
  let lines : Array[String] = mbt
    .split("\n")
    .map(fn(l) { l.to_owned() })
    .collect()
  let structs : Set[String] = Set([])
  let kept : Array[String] = []
  for line in lines {
    if line.has_prefix(ffi_struct_reads_marker) {
      for name in line[ffi_struct_reads_marker.length():].split(" ") {
        let n = name.trim().to_owned()
        if n != "" {
          structs.add(n)
        }
      }
    } else {
      kept.push(line)
    }
  }
  if structs.is_empty() {
    return kept.join("\n")
  }
  let promise_map = mbt.contains("fn[T, U] Promise::map(")
  let used : Set[String] = Set([])
  let out : Array[String] = []
  let mut i = 0
  while i < kept.length() {
    let line = kept[i]
    if !js_ffi_is_extern_header(line) {
      out.push(line)
      i += 1
      continue
    }
    let mut end = i + 1
    if line.has_suffix(" =") {
      while end < kept.length() && kept[end].trim_start().has_prefix("#|") {
        end += 1
      }
    }
    let body = kept[i + 1:end].to_owned()
    let mut attr_start = out.length()
    while attr_start > 0 && out[attr_start - 1].has_prefix("#") {
      attr_start -= 1
    }
    let attrs = out[attr_start:].to_owned()
    match
      js_ffi_struct_read_extern(structs, promise_map, line, body, attrs, used) {
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
  if used.is_empty() {
    return out.join("\n")
  }
  let names : Array[String] = []
  for n in used {
    names.push(n)
  }
  names.sort()
  out.push("")
  out.push("///|")
  out.push("fn[A, B] __ts_mbt_read_cast(value : A) -> B = \"%identity\"")
  out.push("")
  out.push("///|")
  out.push("#external")
  out.push("priv type TsMbtStructRef")
  for n in names {
    out.push("")
    out.push("///|")
    out.push(
      "extern \"js\" fn \{js_ffi_read_helper_name(n)}(value : TsMbtStructRef) -> TsMbtStructRef = \"\{ffi_struct_read_converter_js_name(n)}\"",
    )
  }
  out.join("\n")
}

///|
fn js_ffi_read_helper_name(type_name : String) -> String {
  "__ts_mbt_read_struct__" + type_name
}

///|
/// A return type as this pass sees it.
priv enum JsFfiReadType {
  Leaf
  Struct(String)
  Fixed(JsFfiReadType)
  Opt(JsFfiReadType)
  Prom(JsFfiReadType)
}

///|
fn js_ffi_read_needs(t : JsFfiReadType) -> Bool {
  match t {
    Leaf => false
    Struct(_) => true
    Fixed(a) | Opt(a) | Prom(a) => js_ffi_read_needs(a)
  }
}

///|
fn js_ffi_parse_read_type(
  structs : Set[String],
  promise_map : Bool,
  t : String,
) -> JsFfiReadType {
  let t = t.trim().to_owned()
  // A function type returns, it does not hold, what follows its `->`.
  if t.has_prefix("(") {
    return Leaf
  }
  if t.has_suffix("?") {
    return Opt(
      js_ffi_parse_read_type(
        structs,
        promise_map,
        t[:t.length() - 1].to_owned(),
      ),
    )
  }
  if t.has_prefix("FixedArray[") &&
    t.has_suffix("]") &&
    js_ffi_bracket_close(t, "FixedArray".length()) == Some(t.length() - 1) {
    return Fixed(
      js_ffi_parse_read_type(
        structs,
        promise_map,
        t["FixedArray[".length():t.length() - 1].to_owned(),
      ),
    )
  }
  if promise_map &&
    t.has_prefix("Promise[") &&
    t.has_suffix("]") &&
    js_ffi_bracket_close(t, "Promise".length()) == Some(t.length() - 1) {
    return Prom(
      js_ffi_parse_read_type(
        structs,
        promise_map,
        t["Promise[".length():t.length() - 1].to_owned(),
      ),
    )
  }
  let base = match t.find("[") {
    Some(at) => t[:at].to_owned()
    None => t
  }
  if structs.contains(base) {
    Struct(base)
  } else {
    Leaf
  }
}

///|
fn js_ffi_read_convert(
  expr : String,
  t : JsFfiReadType,
  depth : Int32,
  used : Set[String],
) -> String {
  if !js_ffi_read_needs(t) {
    return expr
  }
  let v = "r\{depth}"
  match t {
    Leaf => expr
    Struct(name) => {
      used.add(name)
      "__ts_mbt_read_cast(\{js_ffi_read_helper_name(name)}(__ts_mbt_read_cast(\{expr})))"
    }
    // `FixedArray::map`, `Option::map` and the generated `Promise::map`.
    Fixed(a) | Opt(a) | Prom(a) =>
      "\{expr}.map(fn(\{v}) { \{js_ffi_read_convert(v, a, depth + 1, used)} })"
  }
}

///|
fn js_ffi_struct_read_extern(
  structs : Set[String],
  promise_map : Bool,
  header : String,
  body : Array[String],
  attrs : Array[String],
  used : Set[String],
) -> Array[String]? {
  for a in attrs {
    if !a.has_prefix("#module(") {
      return None
    }
  }
  guard js_ffi_split_extern_header(header)
    is Some((is_pub, generics, name, params, ret_src, body_tail)) else {
    return None
  }
  // The helper externs this pass emits, and the converters they bind.
  if name.has_prefix("__ts_mbt_read_struct") {
    return None
  }
  let ret = js_ffi_parse_read_type(structs, promise_map, ret_src)
  if !js_ffi_read_needs(ret) {
    return None
  }
  let rs_name = "__ts_mbt_rs_" + name.replace_all(old="::", new="__")
  // The private extern is a FREE function, where a first parameter named
  // `self` is the deprecated method syntax (warning 0027); the JS body binds
  // by position, so the MoonBit names are free to differ.
  let ffi_params = params
    .map(fn(p) {
      let pname = if p.0 == "self" { "receiver" } else { p.0 }
      "\{pname} : \{p.1}"
    })
    .join(", ")
  let orig_params = params.map(fn(p) { "\{p.0} : \{p.1}" }).join(", ")
  let args = params.map(fn(p) { p.0 }).join(", ")
  let call = js_ffi_read_convert("\{rs_name}(\{args})", ret, 0, used)
  let out : Array[String] = []
  for a in attrs {
    out.push(a)
  }
  out.push(
    "extern \"js\" fn\{generics} \{rs_name}(\{ffi_params}) -> \{ret_src}\{body_tail}",
  )
  for l in body {
    out.push(l)
  }
  out.push("")
  let vis = if is_pub { "pub " } else { "" }
  out.push("\{vis}fn\{generics} \{name}(\{orig_params}) -> \{ret_src} {")
  out.push("  \{call}")
  out.push("}")
  Some(out)
}
