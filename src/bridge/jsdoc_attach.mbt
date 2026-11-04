///|
/// Attach TypeScript JSDoc to the generated MoonBit as `///` doc comments
/// (mizchi/ts.mbt#250).
///
/// `docs` is keyed by declaration path (`TsModuleBlock.docs`): `Name` for
/// a top-level declaration, `Name.member` for an interface member. This
/// runs once over the final `.mbt` rather than inside each renderer — the
/// generator has dozens of them — and matches a generated item by NAME:
///
/// - a top-level `pub` item (`pub fn name`, `pub extern "js" fn name`,
///   `pub(all) struct Name`, `pub type Name`, …) takes `docs[name]`;
/// - a method `Type::member` takes `docs["Type.member"]`;
/// - a field inside a struct body takes `docs["Struct.field"]`.
///
/// A name the generator changed in a way this cannot undo (an overload
/// variant `readFileSync_path_…`, a getter `get_x`, a `snake_case`d value)
/// gets no doc. Losing a doc is the affordable direction: attaching the
/// wrong one would put a false sentence in front of a user. The one
/// rename that IS undone is the `_` suffix the generator adds to a
/// MoonBit keyword (`method_` -> `method`).
pub fn attach_jsdoc_to_bridge_mbt(
  mbt : String,
  docs : Map[String, Array[String]],
) -> String {
  if docs.is_empty() {
    return mbt
  }
  let lines : Array[String] = mbt
    .split("\n")
    .map(fn(l) { l.to_owned() })
    .collect()
  let out : Array[String] = []
  let mut current_struct : String? = None
  for line in lines {
    match current_struct {
      Some(struct_name) => {
        if line.has_prefix("}") {
          current_struct = None
        } else {
          match jsdoc_field_name(line) {
            Some(field) =>
              match jsdoc_lookup(docs, "\{struct_name}.\{field}") {
                Some(doc) =>
                  for d in doc {
                    out.push(jsdoc_comment_line("  ", d))
                  }
                None => ()
              }
            None => ()
          }
        }
        out.push(line)
        continue
      }
      None => ()
    }
    match jsdoc_item_key(line) {
      Some((key, is_struct)) => {
        match jsdoc_lookup(docs, key) {
          Some(doc) => {
            // Above the attributes that belong to the declaration
            // (`#module`, `#alias`, `#derive`), below a `///|` marker.
            let mut at = out.length()
            while at > 0 && out[at - 1].has_prefix("#") {
              at -= 1
            }
            let comment = doc.map(fn(d) { jsdoc_comment_line("", d) })
            for i, c in comment {
              out.insert(at + i, c)
            }
          }
          None => ()
        }
        if is_struct && line.has_suffix("{") {
          current_struct = Some(jsdoc_strip_generics(key))
        }
      }
      None => ()
    }
    out.push(line)
  }
  out.join("\n")
}

///|
fn jsdoc_comment_line(indent : String, text : String) -> String {
  if text == "" {
    "\{indent}///"
  } else {
    "\{indent}/// \{text}"
  }
}

///|
fn jsdoc_lookup(
  docs : Map[String, Array[String]],
  key : String,
) -> Array[String]? {
  match docs.get(key) {
    Some(doc) => Some(doc)
    // The generator suffixes a MoonBit keyword with `_` (`method_`).
    None if key.has_suffix("_") => docs.get(key[:key.length() - 1].to_owned())
    None => None
  }
}

///|
/// The doc key of a top-level `pub` item line, and whether it is a struct.
fn jsdoc_item_key(line : String) -> (String, Bool)? {
  let prefixes : Array[(String, Bool)] = [
    ("pub(all) struct ", true),
    ("pub struct ", true),
    ("pub(all) enum ", false),
    ("pub enum ", false),
    ("pub(all) type ", false),
    ("pub type ", false),
    ("pub extern \"js\" fn", false),
    ("pub async fn", false),
    ("pub fn", false),
  ]
  for p in prefixes {
    let (prefix, is_struct) = p
    if !line.has_prefix(prefix) {
      continue
    }
    let mut rest = line[prefix.length():].to_owned()
    // `pub fn[T] name(` — generic binders come before the name.
    if rest.has_prefix("[") {
      match rest.find("]") {
        Some(close) => rest = rest[close + 1:].to_owned()
        None => return None
      }
    }
    rest = rest.trim_start().to_owned()
    let mut end = 0
    while end < rest.length() {
      let c = rest[end]
      if c == '(' || c == ' ' || c == '[' || c == '{' || c == '=' {
        break
      }
      end += 1
    }
    let name = rest[:end].to_owned()
    if name == "" {
      return None
    }
    return Some((name.replace(old="::", new="."), is_struct))
  }
  None
}

///|
fn jsdoc_strip_generics(name : String) -> String {
  match name.find("[") {
    Some(i) => name[:i].to_owned()
    None => name
  }
}

///|
/// The field name of a struct-body line `  name : Type` (or `mut name`).
fn jsdoc_field_name(line : String) -> String? {
  if !line.has_prefix("  ") || line.has_prefix("   ") {
    return None
  }
  let body = line.trim_start().to_owned()
  let body = if body.has_prefix("mut ") {
    body["mut ".length():].to_owned()
  } else {
    body
  }
  match body.find(" : ") {
    Some(i) => {
      let name = body[:i].to_owned()
      if name == "" || name.contains(" ") || name.has_prefix("/") {
        None
      } else {
        Some(name)
      }
    }
    None => None
  }
}

///|
/// Extra doc keys for the names the generator gives class members, built
/// with the SAME spellings its renderers use (`ffi_to_snake_case`), so the
/// two cannot drift. For a doc keyed `Class.member`:
///
/// - the constructor becomes `new_<class>` (a free function);
/// - a property becomes `Class::get_<class>_<member>` and
///   `Class::set_<class>_<member>`;
/// - a static member becomes `<class>_<member>` (a free function).
///
/// A plain method is `Class::member` already and needs no alias. Every
/// alias is added only where no key of that name exists, so a declaration
/// actually named `client_create` keeps its own doc. An alias whose name
/// the generator never emits is simply never looked up.
pub fn jsdoc_add_member_aliases(docs : Map[String, Array[String]]) -> Unit {
  let aliases : Array[(String, Array[String])] = []
  for key, doc in docs {
    guard key.find(".") is Some(dot) else { continue }
    let owner = key[:dot].to_owned()
    let member_name = key[dot + 1:].to_owned()
    if owner == "" || member_name == "" || member_name.contains(".") {
      continue
    }
    let owner_snake = ffi_to_snake_case(owner)
    if member_name == "constructor" {
      aliases.push(("new_\{owner_snake}", doc))
      continue
    }
    let member_snake = ffi_to_snake_case(member_name)
    aliases.push(("\{owner}.get_\{owner_snake}_\{member_snake}", doc))
    aliases.push(("\{owner}.set_\{owner_snake}_\{member_snake}", doc))
    aliases.push(("\{owner_snake}_\{member_snake}", doc))
  }
  for entry in aliases {
    let (key, doc) = entry
    if !docs.contains(key) {
      docs[key] = doc
    }
  }
}
