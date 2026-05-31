// Companion `.d.ts` emission for mtsc `--bundle` output.
//
// Given the entry module's `TsModule` + the list of exported
// names from its `TsModuleBlock`, this pass prints a TypeScript
// declaration file containing only the entry's public type
// surface. Internal helper interfaces / type aliases / classes
// are dropped — they're invisible to downstream consumers and
// would otherwise leak implementation details.
//
// The TsType printer covers the full surface the parser produces,
// including conditional types (`A extends B ? X : Y`), mapped
// types (`{ [K in S]: V }`), index access (`T[K]`), template
// literal types, `keyof`, `typeof`, type predicates, asserts, and
// the rest of the modern TS type vocabulary.

///|
/// Emit the `.d.ts` text for the entry module, restricted to the
/// names listed in `exported_local_names`. Internal helper types
/// are omitted; everything else is emitted with an `export`
/// keyword.
pub fn emit_entry_dts(
  module_ : @ast.TsModule,
  exported_local_names : Array[String],
  deprecations : Map[String, String],
) -> String {
  let buf = StringBuilder::new()
  let exported : Map[String, Bool] = {}
  for n in exported_local_names {
    exported[n] = true
  }
  for i in module_.interfaces {
    if exported.contains(i.name) {
      emit_deprecation_jsdoc(buf, deprecations, i.name)
      emit_interface_decl(buf, i)
    }
  }
  for a in module_.type_aliases {
    if exported.contains(a.name) {
      emit_deprecation_jsdoc(buf, deprecations, a.name)
      emit_type_alias_decl(buf, a)
    }
  }
  for e in module_.enums {
    if exported.contains(e.name) {
      emit_deprecation_jsdoc(buf, deprecations, e.name)
      emit_enum_decl(buf, e)
    }
  }
  for c in module_.classes {
    if exported.contains(c.name) {
      emit_deprecation_jsdoc(buf, deprecations, c.name)
      emit_class_decl(buf, c)
    }
  }
  for f in module_.funcs {
    if exported.contains(f.name) {
      emit_deprecation_jsdoc(buf, deprecations, f.name)
      emit_function_decl(buf, f)
    }
  }
  for v in module_.values {
    if exported.contains(v.name) {
      emit_deprecation_jsdoc(buf, deprecations, v.name)
      emit_value_decl(buf, v)
    }
  }
  buf.to_string()
}

///|
/// Write a `/** @deprecated <msg> */` JSDoc preamble when the
/// name carries a deprecation tag. Consumers' IDEs surface this
/// to anyone who imports the symbol.
fn emit_deprecation_jsdoc(
  buf : StringBuilder,
  deprecations : Map[String, String],
  name : String,
) -> Unit {
  match deprecations.get(name) {
    Some(msg) =>
      if msg == "" {
        buf.write_string("/** @deprecated */\n")
      } else {
        buf.write_string("/** @deprecated ")
        buf.write_string(msg)
        buf.write_string(" */\n")
      }
    None => ()
  }
}

///|
fn emit_interface_decl(buf : StringBuilder, i : @ast.TsInterface) -> Unit {
  buf.write_string("export interface ")
  buf.write_string(i.name)
  emit_type_params(buf, i.type_params)
  if i.extends_names.length() > 0 {
    buf.write_string(" extends ")
    for j, name in i.extends_names {
      if j > 0 {
        buf.write_string(", ")
      }
      buf.write_string(name)
      if j < i.extends_args.length() && i.extends_args[j].length() > 0 {
        buf.write_string("<")
        for k, arg in i.extends_args[j] {
          if k > 0 {
            buf.write_string(", ")
          }
          emit_type(buf, arg)
        }
        buf.write_string(">")
      }
    }
  }
  buf.write_string(" {\n")
  for field in i.fields {
    let is_readonly = i.readonly_fields.contains(field.0)
    buf.write_string("  ")
    if is_readonly {
      buf.write_string("readonly ")
    }
    buf.write_string(field.0)
    // The parser lowers `x?: T` to `x: T | undefined`. Detect that
    // pattern and round-trip back to `x?: T` for cleaner output.
    let (is_optional, ty) = unwrap_optional_field_type(field.1)
    if is_optional {
      buf.write_string("?")
    }
    buf.write_string(": ")
    emit_type(buf, ty)
    buf.write_string(";\n")
  }
  for idx_sig in i.index_signatures {
    buf.write_string("  [k: ")
    emit_type(buf, idx_sig.0)
    buf.write_string("]: ")
    emit_type(buf, idx_sig.1)
    buf.write_string(";\n")
  }
  buf.write_string("}\n")
}

///|
fn emit_type_alias_decl(buf : StringBuilder, a : @ast.TsTypeAlias) -> Unit {
  buf.write_string("export type ")
  buf.write_string(a.name)
  emit_type_params_with_bounds(buf, a.type_params, a.type_param_bounds)
  buf.write_string(" = ")
  emit_type(buf, a.type_)
  buf.write_string(";\n")
}

///|
fn emit_enum_decl(buf : StringBuilder, e : @ast.TsEnumDecl) -> Unit {
  buf.write_string("export ")
  if e.is_const {
    buf.write_string("const ")
  }
  buf.write_string("enum ")
  buf.write_string(e.name)
  buf.write_string(" {\n")
  for m in e.members {
    buf.write_string("  ")
    buf.write_string(m.name)
    match m.value {
      Some(@ast.TsEnumMemberValue::Number(s)) => {
        buf.write_string(" = ")
        buf.write_string(s)
      }
      Some(@ast.TsEnumMemberValue::String(s)) => {
        buf.write_string(" = \"")
        buf.write_string(s)
        buf.write_string("\"")
      }
      Some(@ast.TsEnumMemberValue::BigInt(s)) => {
        buf.write_string(" = ")
        buf.write_string(s)
        buf.write_string("n")
      }
      Some(@ast.TsEnumMemberValue::Bool(b)) => {
        buf.write_string(" = ")
        buf.write_string(if b { "true" } else { "false" })
      }
      None => ()
    }
    buf.write_string(",\n")
  }
  buf.write_string("}\n")
}

///|
fn emit_class_decl(buf : StringBuilder, c : @ast.TsClassDecl) -> Unit {
  buf.write_string("export ")
  if c.is_abstract {
    buf.write_string("abstract ")
  }
  buf.write_string("class ")
  buf.write_string(c.name)
  emit_type_params(buf, c.type_params)
  if c.base_names.length() > 0 {
    buf.write_string(" extends ")
    buf.write_string(c.base_names[0])
  }
  buf.write_string(" {\n")
  // Constructor signature, when the parser captured one.
  match c.constructor_params {
    Some(params) => {
      buf.write_string("  constructor(")
      for i, p in params {
        if i > 0 {
          buf.write_string(", ")
        }
        let (is_optional, ty) = unwrap_optional_field_type(p.1)
        buf.write_string(p.0)
        if is_optional {
          buf.write_string("?")
        }
        buf.write_string(": ")
        emit_type(buf, ty)
      }
      buf.write_string(");\n")
    }
    None => ()
  }
  for prop in c.properties {
    buf.write_string("  ")
    if prop.is_static {
      buf.write_string("static ")
    }
    if prop.is_readonly {
      buf.write_string("readonly ")
    }
    buf.write_string(prop.name)
    let (is_optional, ty) = unwrap_optional_field_type(prop.type_)
    if is_optional {
      buf.write_string("?")
    }
    buf.write_string(": ")
    emit_type(buf, ty)
    buf.write_string(";\n")
  }
  for m in c.methods {
    buf.write_string("  ")
    if m.is_static {
      buf.write_string("static ")
    }
    buf.write_string(m.name)
    emit_type_params_with_bounds(buf, m.type_params, m.type_param_bounds)
    buf.write_string("(")
    for i, p in m.params {
      if i > 0 {
        buf.write_string(", ")
      }
      let (is_optional, ty) = unwrap_optional_field_type(p.1)
      buf.write_string(p.0)
      if is_optional {
        buf.write_string("?")
      }
      buf.write_string(": ")
      emit_type(buf, ty)
    }
    buf.write_string("): ")
    emit_type(buf, m.return_type)
    buf.write_string(";\n")
  }
  for idx_sig in c.index_signatures {
    buf.write_string("  [k: ")
    emit_type(buf, idx_sig.0)
    buf.write_string("]: ")
    emit_type(buf, idx_sig.1)
    buf.write_string(";\n")
  }
  buf.write_string("}\n")
}

///|
fn emit_function_decl(buf : StringBuilder, f : @ast.TsFunc) -> Unit {
  buf.write_string("export declare function ")
  buf.write_string(f.name)
  emit_type_params(buf, f.type_params)
  buf.write_string("(")
  for i, p in f.params {
    if i > 0 {
      buf.write_string(", ")
    }
    if p.is_rest {
      buf.write_string("...")
    }
    let (is_optional, ty) = unwrap_optional_field_type(p.type_)
    buf.write_string(p.name)
    if is_optional && !p.is_rest {
      buf.write_string("?")
    }
    buf.write_string(": ")
    emit_type(buf, ty)
  }
  buf.write_string("): ")
  emit_type(buf, f.return_type)
  buf.write_string(";\n")
}

///|
/// When a field / parameter type is `T | undefined`, return
/// `(true, T)` so the emitter can render it as `x?: T` (the
/// idiomatic TypeScript shape). For anything else, return
/// `(false, ty)` unchanged.
fn unwrap_optional_field_type(ty : @ast.TsType) -> (Bool, @ast.TsType) {
  match ty {
    Union(parts) => {
      // Find an `Undefined` in the union and return the remainder.
      let mut has_undefined = false
      let rest : Array[@ast.TsType] = []
      for p in parts {
        match p {
          Undefined => has_undefined = true
          _ => rest.push(p)
        }
      }
      if !has_undefined || rest.length() == 0 {
        return (false, ty)
      }
      if rest.length() == 1 {
        (true, rest[0])
      } else {
        (true, Union(rest))
      }
    }
    _ => (false, ty)
  }
}

///|
/// Variant of `emit_type_params` that also writes per-parameter
/// `extends Bound` clauses when the binding list carries bounds.
/// Order in `bounds` mirrors `params`; missing entries mean no
/// bound was declared.
fn emit_type_params_with_bounds(
  buf : StringBuilder,
  params : Array[String],
  bounds : Array[(String, @ast.TsType)],
) -> Unit {
  if params.length() == 0 {
    return
  }
  let bound_map : Map[String, @ast.TsType] = {}
  for b in bounds {
    bound_map[b.0] = b.1
  }
  buf.write_string("<")
  for i, p in params {
    if i > 0 {
      buf.write_string(", ")
    }
    buf.write_string(p)
    match bound_map.get(p) {
      Some(b) => {
        buf.write_string(" extends ")
        emit_type(buf, b)
      }
      None => ()
    }
  }
  buf.write_string(">")
}

///|
fn emit_value_decl(buf : StringBuilder, v : @ast.TsValueDecl) -> Unit {
  buf.write_string("export declare const ")
  buf.write_string(v.name)
  buf.write_string(": ")
  emit_type(buf, v.type_)
  buf.write_string(";\n")
}

///|
fn emit_type_params(buf : StringBuilder, params : Array[String]) -> Unit {
  if params.length() == 0 {
    return
  }
  buf.write_string("<")
  for i, p in params {
    if i > 0 {
      buf.write_string(", ")
    }
    buf.write_string(p)
  }
  buf.write_string(">")
}

///|
/// Emit a `TsType` as TypeScript syntax. Handles every variant the
/// parser produces, including conditional / mapped / index-access
/// / template literal types — the modern type vocabulary.
fn emit_type(buf : StringBuilder, ty : @ast.TsType) -> Unit {
  match ty {
    Number => buf.write_string("number")
    Int => buf.write_string("number")
    Boolean => buf.write_string("boolean")
    String_ => buf.write_string("string")
    Void => buf.write_string("void")
    BigInt => buf.write_string("bigint")
    Symbol => buf.write_string("symbol")
    UniqueSymbol(_) => buf.write_string("unique symbol")
    Any => buf.write_string("any")
    Never => buf.write_string("never")
    Null => buf.write_string("null")
    Undefined => buf.write_string("undefined")
    Literal(s) => {
      buf.write_string("\"")
      buf.write_string(s)
      buf.write_string("\"")
    }
    NumberLiteral(s) => buf.write_string(s)
    BigIntLiteral(s) => {
      buf.write_string(s)
      buf.write_string("n")
    }
    BooleanLiteral(b) => buf.write_string(if b { "true" } else { "false" })
    Array(inner) => {
      emit_type_atom(buf, inner)
      buf.write_string("[]")
    }
    Tuple(items) => {
      buf.write_string("[")
      for i, it in items {
        if i > 0 {
          buf.write_string(", ")
        }
        emit_type(buf, it)
      }
      buf.write_string("]")
    }
    Rest(inner) => {
      buf.write_string("...")
      emit_type(buf, inner)
    }
    Object(fields) =>
      if fields.length() == 0 {
        buf.write_string("{}")
      } else {
        buf.write_string("{ ")
        for i, f in fields {
          if i > 0 {
            buf.write_string("; ")
          }
          // Track optional even for inline object literal types.
          let (is_optional, value_ty) = unwrap_optional_field_type(f.1)
          match f.0 {
            Literal(name) => {
              buf.write_string(name)
              if is_optional {
                buf.write_string("?")
              }
            }
            _ => {
              buf.write_string("[k: ")
              emit_type(buf, f.0)
              buf.write_string("]")
            }
          }
          buf.write_string(": ")
          emit_type(buf, value_ty)
        }
        buf.write_string(" }")
      }
    Struct(name, _) => buf.write_string(name)
    Func(params, ret) => {
      buf.write_string("(")
      for i, p in params {
        if i > 0 {
          buf.write_string(", ")
        }
        buf.write_string("arg")
        buf.write_string(i.to_string())
        buf.write_string(": ")
        emit_type(buf, p)
      }
      buf.write_string(") => ")
      emit_type(buf, ret)
    }
    Constructor(params, ret, is_abstract) => {
      if is_abstract {
        buf.write_string("abstract ")
      }
      buf.write_string("new (")
      for i, p in params {
        if i > 0 {
          buf.write_string(", ")
        }
        buf.write_string("arg")
        buf.write_string(i.to_string())
        buf.write_string(": ")
        emit_type(buf, p)
      }
      buf.write_string(") => ")
      emit_type(buf, ret)
    }
    Union(items) =>
      for i, it in items {
        if i > 0 {
          buf.write_string(" | ")
        }
        emit_type_atom(buf, it)
      }
    Intersection(items) =>
      for i, it in items {
        if i > 0 {
          buf.write_string(" & ")
        }
        emit_type_atom(buf, it)
      }
    Conditional(check, ext, t, f) => {
      emit_type_atom(buf, check)
      buf.write_string(" extends ")
      emit_type_atom(buf, ext)
      buf.write_string(" ? ")
      emit_type(buf, t)
      buf.write_string(" : ")
      emit_type(buf, f)
    }
    Named(name) => buf.write_string(name)
    Applied(name, args) => {
      // `infer T` and `infer T extends Bound` are stored as the
      // pseudo-applied form `__tsmbt_infer<…>` so the parser can
      // round-trip them. Render them with the proper TS keyword.
      if name == "__tsmbt_infer" && args.length() >= 1 {
        buf.write_string("infer ")
        emit_type(buf, args[0])
        if args.length() >= 2 {
          buf.write_string(" extends ")
          emit_type(buf, args[1])
        }
        return
      }
      buf.write_string(name)
      buf.write_string("<")
      for i, a in args {
        if i > 0 {
          buf.write_string(", ")
        }
        emit_type(buf, a)
      }
      buf.write_string(">")
    }
    TypeOf(expr) => {
      buf.write_string("typeof ")
      buf.write_string(expr)
    }
    IndexedAccess(obj, idx) => {
      emit_type_atom(buf, obj)
      buf.write_string("[")
      emit_type(buf, idx)
      buf.write_string("]")
    }
    TemplateLiteralType(parts, args) => {
      buf.write_string("`")
      let mut i = 0
      while i < parts.length() {
        buf.write_string(parts[i])
        if i < args.length() {
          buf.write_string("${")
          emit_type(buf, args[i])
          buf.write_string("}")
        }
        i = i + 1
      }
      buf.write_string("`")
    }
    Keyof(inner) => {
      buf.write_string("keyof ")
      emit_type_atom(buf, inner)
    }
    MappedType(key, source, value, optional) => {
      buf.write_string("{ [")
      buf.write_string(key)
      buf.write_string(" in ")
      emit_type(buf, source)
      buf.write_string("]")
      if optional {
        buf.write_string("?")
      }
      buf.write_string(": ")
      emit_type(buf, value)
      buf.write_string(" }")
    }
    MappedTypeRemap(key, source, remap, value, optional) => {
      buf.write_string("{ [")
      buf.write_string(key)
      buf.write_string(" in ")
      emit_type(buf, source)
      buf.write_string(" as ")
      emit_type(buf, remap)
      buf.write_string("]")
      if optional {
        buf.write_string("?")
      }
      buf.write_string(": ")
      emit_type(buf, value)
      buf.write_string(" }")
    }
    TypePredicate(name, target) => {
      buf.write_string(name)
      buf.write_string(" is ")
      emit_type(buf, target)
    }
    AssertsPredicate(name, opt_target) => {
      buf.write_string("asserts ")
      buf.write_string(name)
      match opt_target {
        Some(t) => {
          buf.write_string(" is ")
          emit_type(buf, t)
        }
        None => ()
      }
    }
  }
}

///|
/// Emit a TsType with parens when it's a binary type operator that
/// would otherwise re-bind in the surrounding context (e.g. inside
/// an `Array` element type or to the left of `extends` in a
/// conditional). Most callers can use plain `emit_type`; this is
/// the precedence-aware variant.
fn emit_type_atom(buf : StringBuilder, ty : @ast.TsType) -> Unit {
  match ty {
    Union(_)
    | Intersection(_)
    | Conditional(_, _, _, _)
    | Func(_, _)
    | Constructor(_, _, _) => {
      buf.write_string("(")
      emit_type(buf, ty)
      buf.write_string(")")
    }
    _ => emit_type(buf, ty)
  }
}
