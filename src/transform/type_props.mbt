// Type-declared property name extraction.
//
// Walks the TsModule for each parsed file and pulls out every
// property name that appears in an interface, type alias, class,
// or inline object type. These names are part of the bundle's
// public type surface — they describe the shape consumers see —
// so they must NOT be renamed even when `--mangle-properties` is
// on.
//
// Used by `bundle_modules`'s safety analysis to extend the
// reserved-properties set with the union of every type-declared
// property name across the bundle. Internal-only ObjectLits with
// keys that never appear in any type declaration (and are never
// read elsewhere) become eligible for the dead-property pass.

///|
/// Extract every type-declared property name from a module.
/// Recursively descends into nested namespaces and inline object
/// types appearing in field / parameter / return positions.
pub fn type_declared_property_names(module_ : @ast.TsModule) -> Array[String] {
  let out : Map[String, Bool] = {}
  collect_property_names_from_module(module_, out)
  let names : Array[String] = []
  for k in out.keys() {
    names.push(k)
  }
  names
}

///|
fn collect_property_names_from_module(
  module_ : @ast.TsModule,
  out : Map[String, Bool],
) -> Unit {
  for itf in module_.interfaces {
    for field in itf.fields {
      out[field.0] = true
      collect_property_names_from_type(field.1, out)
    }
  }
  for alias in module_.type_aliases {
    collect_property_names_from_type(alias.type_, out)
  }
  for cls in module_.classes {
    for prop in cls.properties {
      out[prop.name] = true
      collect_property_names_from_type(prop.type_, out)
    }
    for m in cls.methods {
      out[m.name] = true
      for p in m.params {
        collect_property_names_from_type(p.1, out)
      }
      collect_property_names_from_type(m.return_type, out)
    }
  }
  for func in module_.funcs {
    for p in func.params {
      collect_property_names_from_type(p.type_, out)
    }
    collect_property_names_from_type(func.return_type, out)
  }
  for v in module_.values {
    collect_property_names_from_type(v.type_, out)
  }
  // Recurse through namespaces — their declarations contribute to
  // the same name surface.
  for ns in module_.namespaces {
    collect_property_names_from_module(ns.module_, out)
  }
  // Module augmentations carry the same shape as TsModule.
  for aug in module_.module_augmentations {
    collect_property_names_from_module(aug.1, out)
  }
}

///|
/// Walk a `TsType` collecting every named property. Object types
/// (`{ foo: string, bar: number }`) contribute their keys; type
/// references (`Foo<T>`) contribute nothing directly — the named
/// interface / alias is what gets walked separately.
fn collect_property_names_from_type(
  ty : @ast.TsType,
  out : Map[String, Bool],
) -> Unit {
  match ty {
    Object(fields) =>
      for f in fields {
        // Object type key is a TsType (usually `Literal(name)`).
        match f.0 {
          Literal(name) => out[name] = true
          _ => ()
        }
        collect_property_names_from_type(f.1, out)
      }
    Struct(_, fields) =>
      for f in fields {
        out[f.0] = true
        collect_property_names_from_type(f.1, out)
      }
    Func(params, ret) => {
      for p in params {
        collect_property_names_from_type(p, out)
      }
      collect_property_names_from_type(ret, out)
    }
    Constructor(params, ret, _) => {
      for p in params {
        collect_property_names_from_type(p, out)
      }
      collect_property_names_from_type(ret, out)
    }
    Array(inner) => collect_property_names_from_type(inner, out)
    Tuple(items) =>
      for it in items {
        collect_property_names_from_type(it, out)
      }
    Rest(inner) => collect_property_names_from_type(inner, out)
    Union(items) | Intersection(items) =>
      for it in items {
        collect_property_names_from_type(it, out)
      }
    Applied(_, args) =>
      for a in args {
        collect_property_names_from_type(a, out)
      }
    IndexedAccess(obj, idx) => {
      collect_property_names_from_type(obj, out)
      collect_property_names_from_type(idx, out)
    }
    Conditional(check, ext, t, f) => {
      collect_property_names_from_type(check, out)
      collect_property_names_from_type(ext, out)
      collect_property_names_from_type(t, out)
      collect_property_names_from_type(f, out)
    }
    Keyof(inner) => collect_property_names_from_type(inner, out)
    MappedType(_, source, value, _) => {
      collect_property_names_from_type(source, out)
      collect_property_names_from_type(value, out)
    }
    MappedTypeRemap(_, source, remap, value, _) => {
      collect_property_names_from_type(source, out)
      collect_property_names_from_type(remap, out)
      collect_property_names_from_type(value, out)
    }
    TemplateLiteralType(_, args) =>
      for a in args {
        collect_property_names_from_type(a, out)
      }
    TypePredicate(_, inner) => collect_property_names_from_type(inner, out)
    AssertsPredicate(_, Some(inner)) => collect_property_names_from_type(inner, out)
    _ => ()
  }
}
