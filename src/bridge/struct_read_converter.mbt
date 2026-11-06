///|
/// The READ direction of a generated struct: a JS object handed to MoonBit
/// as a struct (a return, an element of a returned array, a promise's
/// value) was used RAW, while the WRITE direction has had a per-struct
/// `__ts_mbt_to_js_<snake>` converter for a long time. Raw is wrong for
/// exactly the reasons that converter exists — a field MoonBit renamed
/// (`type` -> `type_`), an optional MoonBit boxes (`Double?` is
/// `{ $tag, _0 }`, `Bool?` uses a `-1` sentinel), a literal-union enum
/// (a case index), and a payload union (`{ $tag, _0 }`) — so
/// `Diagnostic.messageText` reached a `match` as a bare string.
///
/// This builds the mirror: a `bridge.js` `__ts_mbt_read_struct_<snake>`
/// per struct that needs it, and the post-pass
/// `migrate_js_ffi_struct_reads` routes every extern return through it.
///
/// Scope, as decided: PLAIN DATA only. A struct qualifies when JS can return
/// it (`read_reachable_struct_names`), it has a write converter (so the two
/// directions stay symmetric and a converted field goes back to JS
/// converted), none of its fields is a function, and at least one field
/// actually needs converting. At runtime the converter also returns a
/// value whose prototype is not `Object.prototype` untouched — a class
/// instance (a TypeScript AST node, hono's `Router`) carries getters,
/// methods and cyclic links a copy would lose — which is today's behaviour
/// for those, stated rather than fixed.
priv struct FfiStructReadPlan {
  fields : Map[String, Array[(String, @ast.TsType)]]
  memo : Map[String, Bool]
  enums_used : Map[String, @ast.TsEnumDecl]
}

///|
fn ffi_struct_read_plan(
  fields : Map[String, Array[(String, @ast.TsType)]],
) -> FfiStructReadPlan {
  { fields, memo: Map([]), enums_used: Map([]), }
}

///|
fn ffi_struct_read_converter_js_name(type_name : String) -> String {
  "__ts_mbt_read_struct_" + ffi_to_snake_case(type_name)
}

///|
fn ffi_bridge_enum_from_js_name(type_name : String) -> String {
  "__ts_mbt_bridge_" + ffi_to_snake_case(type_name) + "_from_js"
}

///|
fn ffi_type_is_function_like(type_ : @ast.TsType) -> Bool {
  match @checker.classify_optional_like_union(type_) {
    Some((collapsed, _)) => return ffi_type_is_function_like(collapsed)
    None => ()
  }
  match type_ {
    Func(_, _) | CallableMeta(_, _) | GenericFunc(_, _, _) => true
    Constructor(_, _, _) => true
    _ => false
  }
}

///|
/// Whether `type_name` gets a read converter. Memoized; a struct still being
/// decided reads as `false`, so a cycle loses a conversion rather than
/// looping — the affordable direction, since `false` is today's behaviour.
fn ffi_read_struct_converts(
  state : MoonBitJsFfiState,
  plan : FfiStructReadPlan,
  type_name : String,
) -> Bool {
  match plan.memo.get(type_name) {
    Some(answer) => return answer
    None => ()
  }
  plan.memo[type_name] = false
  if !state.read_reachable_struct_names.contains(type_name) ||
    !state.struct_type_names.contains(type_name) {
    return false
  }
  guard plan.fields.get(type_name) is Some(fields) else { return false }
  for field in fields {
    if ffi_type_is_function_like(field.1) {
      return false
    }
  }
  let mut needs = false
  for field in fields {
    let (field_name, field_type) = field
    if ffi_sanitize_identifier(field_name, "field") != field_name ||
      ffi_type_js_read_expr(state, plan, field_type, "field") != "field" {
      needs = true
    }
  }
  plan.memo[type_name] = needs
  needs
}

///|
/// The struct a NAMED reference names, when it is one the read side converts.
fn ffi_read_struct_ref(
  state : MoonBitJsFfiState,
  plan : FfiStructReadPlan,
  type_ : @ast.TsType,
) -> String? {
  let name = match type_ {
    Named(n) | Applied(n, _) => ffi_type_identifier(n, "OpaqueType")
    _ => return None
  }
  if ffi_read_struct_converts(state, plan, name) {
    Some(name)
  } else {
    None
  }
}

///|
/// The JS that turns a raw JS field value `expr` into what MoonBit reads for
/// a field declared `type_`. `expr` unchanged means no conversion. Every
/// optional representation was PROBED on the `js` backend (moonc v0.10.20)
/// rather than assumed: `Double?` and an `#external` type (`JSValue`) are
/// boxed `{ $tag, _0 }`, `Bool?` is the `-1` sentinel, and a `String`, an
/// `Int`, a record, an enum and a `FixedArray` cross as the value itself
/// with `undefined` for `None`. An optional this does not classify is left
/// raw, which is what it was.
fn ffi_type_js_read_expr(
  state : MoonBitJsFfiState,
  plan : FfiStructReadPlan,
  type_ : @ast.TsType,
  expr : String,
) -> String {
  match @checker.classify_optional_like_union(type_) {
    Some((collapsed, false)) =>
      return ffi_type_js_read_expr(state, plan, collapsed, expr)
    Some((collapsed, true)) => {
      match collapsed {
        Boolean => return "__ts_mbt_wrap_bool_option(\{expr})"
        Number | Any | Unknown =>
          return "(\{expr} == null ? { $tag: 0 } : { $tag: 1, _0: \{expr} })"
        String_ => return expr
        _ => ()
      }
      let inner = ffi_type_js_read_expr(state, plan, collapsed, expr)
      return if inner == expr {
        expr
      } else {
        "(\{expr} == null ? undefined : \{inner})"
      }
    }
    None => ()
  }
  match @checker.classify_transparent_intersection(type_) {
    Some(inner) => return ffi_type_js_read_expr(state, plan, inner, expr)
    None => ()
  }
  // A payload union, before the shape arms: a `Union` reaches none of them.
  match ffi_wrappable_union_alias_name(state, type_) {
    Some(name) => return "\{tagged_union_from_js_function_name(name)}(\{expr})"
    None => ()
  }
  match type_ {
    Named(name) | Applied(name, _) if ffi_named_type_is_primitive_enum_in(
        state.enums,
        name,
      ) =>
      match ffi_find_enum_decl_in(state.enums, name) {
        Some(enum_) if ffi_enum_bridge_js_from_js_decl(enum_) is Some(_) => {
          let type_name = ffi_type_identifier(enum_.name, "GeneratedEnum")
          plan.enums_used[type_name] = enum_
          "\{ffi_bridge_enum_from_js_name(type_name)}(\{expr})"
        }
        _ => expr
      }
    Array(inner)
    | Applied("Array", [inner])
    | Applied("ReadonlyArray", [inner]) => {
      let item = ffi_type_js_read_expr(state, plan, inner, "item")
      if item == "item" {
        expr
      } else {
        "(Array.isArray(\{expr}) ? \{expr}.map((item) => \{item}) : \{expr})"
      }
    }
    _ =>
      match ffi_read_struct_ref(state, plan, type_) {
        Some(name) =>
          "\{ffi_struct_read_converter_js_name(name)}(\{expr}, seen)"
        None => expr
      }
  }
}

///|
/// `__ts_mbt_bridge_<enum>_from_js`: a JS literal to the case index MoonBit
/// matches on. A value that is no case (a TypeScript flags enum combined
/// with `|`) passes through unchanged, which is what it did before; throwing
/// there would turn a value MoonBit could at least carry into a crash.
fn ffi_enum_bridge_js_from_js_decl(enum_ : @ast.TsEnumDecl) -> String? {
  let type_name = ffi_type_identifier(enum_.name, "GeneratedEnum")
  let case_count = ffi_enum_case_count(enum_)
  if case_count == 0 {
    return None
  }
  let lines : Array[String] = [
    "export function \{ffi_bridge_enum_from_js_name(type_name)}(value) {",
    "  switch (value) {",
  ]
  for i in 0..<case_count {
    match ffi_enum_js_raw_literal(enum_, i) {
      Some(raw) => lines.push("    case \{raw}: return \{i};")
      None => return None
    }
  }
  lines.push("    default: return value;")
  lines.push("  }")
  lines.push("}")
  Some(lines.join("\n"))
}

///|
fn ffi_struct_read_converter_js(
  state : MoonBitJsFfiState,
  plan : FfiStructReadPlan,
  type_name : String,
) -> String {
  let fields = match plan.fields.get(type_name) {
    Some(f) => f
    None => []
  }
  let name = ffi_struct_read_converter_js_name(type_name)
  let lines : Array[String] = [
    "export function \{name}(value, seen) {",
    "  if (value === null || typeof value !== \"object\") return value;",
    // A class instance keeps its prototype, getters and cyclic links only
    // if it is not copied; it is used raw, as before.
    "  const proto = Object.getPrototypeOf(value);",
    "  if (proto !== null && proto !== Object.prototype) return value;",
    "  if (seen === undefined) seen = new Map(); else if (seen.has(value)) return seen.get(value);",
    // The spread keeps every key the library put there; only the fields
    // MoonBit reads differently are written over.
    "  const result = { ...value };",
    "  seen.set(value, result);",
    "  let field;",
  ]
  for field in fields {
    let (field_name, field_type) = field
    let safe_name = ffi_sanitize_identifier(field_name, "field")
    let converted = ffi_type_js_read_expr(state, plan, field_type, "field")
    if safe_name == field_name && converted == "field" {
      continue
    }
    let source_key = json_escape_string(field_name)
    let target_key = json_escape_string(safe_name)
    lines.push("  field = value[\"\{source_key}\"];")
    let optional = @checker.classify_optional_like_union(field_type)
      is Some((_, true))
    if optional {
      // An absent optional still has to become MoonBit's `None`.
      lines.push("  result[\"\{target_key}\"] = \{converted};")
    } else {
      lines.push(
        "  if (field !== undefined) result[\"\{target_key}\"] = \{converted};",
      )
    }
  }
  lines.push("  return result;")
  lines.push("}")
  lines.join("\n")
}

///|
/// The marker line that hands the converted set to
/// `migrate_js_ffi_struct_reads`, which removes it.
let ffi_struct_reads_marker : String = "// __ts_mbt_read_structs:"

///|
/// Every struct the read side converts, with its `bridge.js` converters and
/// the enum converters they call. Returns the JS sections and the marker
/// line for the `.mbt`, or nothing when no struct qualifies.
fn ffi_struct_read_sections(
  state : MoonBitJsFfiState,
  fields : Map[String, Array[(String, @ast.TsType)]],
) -> (Array[String], String)? {
  let plan = ffi_struct_read_plan(fields)
  let names : Array[String] = []
  for entry in state.read_reachable_struct_names {
    let (name, _) = entry
    if ffi_read_struct_converts(state, plan, name) {
      names.push(name)
    }
  }
  if names.is_empty() {
    return None
  }
  names.sort()
  let js : Array[String] = []
  for name in names {
    js.push(ffi_struct_read_converter_js(state, plan, name))
  }
  let enum_names : Array[String] = []
  for entry in plan.enums_used {
    enum_names.push(entry.0)
  }
  enum_names.sort()
  for enum_name in enum_names {
    match plan.enums_used.get(enum_name) {
      Some(enum_) =>
        match ffi_enum_bridge_js_from_js_decl(enum_) {
          Some(decl) => js.push(decl)
          None => ()
        }
      None => ()
    }
  }
  Some((js, "\{ffi_struct_reads_marker} \{names.join(" ")}"))
}
