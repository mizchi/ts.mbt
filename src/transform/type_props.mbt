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
  for alias_ in module_.type_aliases {
    collect_property_names_from_type(alias_.type_, out)
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
    AssertsPredicate(_, Some(inner)) =>
      collect_property_names_from_type(inner, out)
    _ => ()
  }
}

///|
/// Extract the property-name surface that's reachable from the
/// entry module's exported declarations. Used by mtsc's
/// `--reserve-entry-exports` flag: every name in the result must
/// stay verbatim in the bundle so the published `.d.ts` keeps
/// the original member names, while every OTHER type-declared
/// property is free to mangle.
///
/// `exported_local_names` is the list of `TsExportSpec.local_name`
/// values from the entry module's `TsModuleBlock` — i.e. the
/// in-module names of the exports.
pub fn entry_export_property_names(
  module_ : @ast.TsModule,
  exported_local_names : Array[String],
) -> Array[String] {
  // Build name-> declaration lookups so we can follow `Named(X)`
  // references through aliases / interfaces / classes without
  // walking the whole module on each step.
  let interfaces : Map[String, @ast.TsInterface] = {}
  for i in module_.interfaces {
    interfaces[i.name] = i
  }
  let aliases : Map[String, @ast.TsTypeAlias] = {}
  for a in module_.type_aliases {
    aliases[a.name] = a
  }
  let classes : Map[String, @ast.TsClassDecl] = {}
  for c in module_.classes {
    classes[c.name] = c
  }
  // Build a set of exported names for quick lookup.
  let exported : Map[String, Bool] = {}
  for n in exported_local_names {
    exported[n] = true
  }
  let out : Map[String, Bool] = {}
  // `visited_names` short-circuits cycles in type references
  // (`interface A { x: B }` + `interface B { y: A }`).
  let visited_names : Map[String, Bool] = {}
  // Seed the walk with every reachable declaration that's exported.
  for f in module_.funcs {
    if exported.contains(f.name) {
      walk_func_for_props(f, out, interfaces, aliases, classes, visited_names)
    }
  }
  for c in module_.classes {
    if exported.contains(c.name) {
      walk_class_for_props(c, out, interfaces, aliases, classes, visited_names)
    }
  }
  for i in module_.interfaces {
    if exported.contains(i.name) {
      walk_interface_for_props(
        i, out, interfaces, aliases, classes, visited_names,
      )
    }
  }
  for a in module_.type_aliases {
    if exported.contains(a.name) {
      walk_type_for_props(
        a.type_,
        out,
        interfaces,
        aliases,
        classes,
        visited_names,
      )
    }
  }
  for v in module_.values {
    if exported.contains(v.name) {
      walk_type_for_props(
        v.type_,
        out,
        interfaces,
        aliases,
        classes,
        visited_names,
      )
    }
  }
  let result : Array[String] = []
  for k in out.keys() {
    result.push(k)
  }
  result
}

///|
fn walk_func_for_props(
  f : @ast.TsFunc,
  out : Map[String, Bool],
  interfaces : Map[String, @ast.TsInterface],
  aliases : Map[String, @ast.TsTypeAlias],
  classes : Map[String, @ast.TsClassDecl],
  visited : Map[String, Bool],
) -> Unit {
  for p in f.params {
    walk_type_for_props(p.type_, out, interfaces, aliases, classes, visited)
  }
  walk_type_for_props(f.return_type, out, interfaces, aliases, classes, visited)
}

///|
fn walk_class_for_props(
  c : @ast.TsClassDecl,
  out : Map[String, Bool],
  interfaces : Map[String, @ast.TsInterface],
  aliases : Map[String, @ast.TsTypeAlias],
  classes : Map[String, @ast.TsClassDecl],
  visited : Map[String, Bool],
) -> Unit {
  for prop in c.properties {
    out[prop.name] = true
    walk_type_for_props(prop.type_, out, interfaces, aliases, classes, visited)
  }
  for m in c.methods {
    out[m.name] = true
    for p in m.params {
      walk_type_for_props(p.1, out, interfaces, aliases, classes, visited)
    }
    walk_type_for_props(
      m.return_type,
      out,
      interfaces,
      aliases,
      classes,
      visited,
    )
  }
  match c.constructor_params {
    Some(params) =>
      for p in params {
        walk_type_for_props(p.1, out, interfaces, aliases, classes, visited)
      }
    None => ()
  }
  // Follow inheritance — `class Foo extends Bar` makes Bar's
  // surface part of Foo's, since consumers can call Bar's methods
  // on a Foo.
  for base_name in c.base_names {
    visit_named_type_for_props(
      base_name, out, interfaces, aliases, classes, visited,
    )
  }
}

///|
fn walk_interface_for_props(
  i : @ast.TsInterface,
  out : Map[String, Bool],
  interfaces : Map[String, @ast.TsInterface],
  aliases : Map[String, @ast.TsTypeAlias],
  classes : Map[String, @ast.TsClassDecl],
  visited : Map[String, Bool],
) -> Unit {
  for f in i.fields {
    out[f.0] = true
    walk_type_for_props(f.1, out, interfaces, aliases, classes, visited)
  }
  for base_name in i.extends_names {
    visit_named_type_for_props(
      base_name, out, interfaces, aliases, classes, visited,
    )
  }
}

///|
fn walk_type_for_props(
  ty : @ast.TsType,
  out : Map[String, Bool],
  interfaces : Map[String, @ast.TsInterface],
  aliases : Map[String, @ast.TsTypeAlias],
  classes : Map[String, @ast.TsClassDecl],
  visited : Map[String, Bool],
) -> Unit {
  match ty {
    Object(fields) =>
      for f in fields {
        match f.0 {
          Literal(name) => out[name] = true
          _ => ()
        }
        walk_type_for_props(f.1, out, interfaces, aliases, classes, visited)
      }
    Struct(_, fields) =>
      for f in fields {
        out[f.0] = true
        walk_type_for_props(f.1, out, interfaces, aliases, classes, visited)
      }
    Named(name) =>
      visit_named_type_for_props(
        name, out, interfaces, aliases, classes, visited,
      )
    Applied(name, args) => {
      visit_named_type_for_props(
        name, out, interfaces, aliases, classes, visited,
      )
      for a in args {
        walk_type_for_props(a, out, interfaces, aliases, classes, visited)
      }
    }
    Array(inner) =>
      walk_type_for_props(inner, out, interfaces, aliases, classes, visited)
    Rest(inner) =>
      walk_type_for_props(inner, out, interfaces, aliases, classes, visited)
    Tuple(items) =>
      for it in items {
        walk_type_for_props(it, out, interfaces, aliases, classes, visited)
      }
    Union(items) | Intersection(items) =>
      for it in items {
        walk_type_for_props(it, out, interfaces, aliases, classes, visited)
      }
    Func(params, ret) => {
      for p in params {
        walk_type_for_props(p, out, interfaces, aliases, classes, visited)
      }
      walk_type_for_props(ret, out, interfaces, aliases, classes, visited)
    }
    Constructor(params, ret, _) => {
      for p in params {
        walk_type_for_props(p, out, interfaces, aliases, classes, visited)
      }
      walk_type_for_props(ret, out, interfaces, aliases, classes, visited)
    }
    IndexedAccess(obj, idx) => {
      walk_type_for_props(obj, out, interfaces, aliases, classes, visited)
      walk_type_for_props(idx, out, interfaces, aliases, classes, visited)
    }
    Conditional(check, ext, t, f) => {
      walk_type_for_props(check, out, interfaces, aliases, classes, visited)
      walk_type_for_props(ext, out, interfaces, aliases, classes, visited)
      walk_type_for_props(t, out, interfaces, aliases, classes, visited)
      walk_type_for_props(f, out, interfaces, aliases, classes, visited)
    }
    Keyof(inner) =>
      walk_type_for_props(inner, out, interfaces, aliases, classes, visited)
    MappedType(_, source, value, _) => {
      walk_type_for_props(source, out, interfaces, aliases, classes, visited)
      walk_type_for_props(value, out, interfaces, aliases, classes, visited)
    }
    MappedTypeRemap(_, source, remap, value, _) => {
      walk_type_for_props(source, out, interfaces, aliases, classes, visited)
      walk_type_for_props(remap, out, interfaces, aliases, classes, visited)
      walk_type_for_props(value, out, interfaces, aliases, classes, visited)
    }
    TemplateLiteralType(_, args) =>
      for a in args {
        walk_type_for_props(a, out, interfaces, aliases, classes, visited)
      }
    TypePredicate(_, inner) =>
      walk_type_for_props(inner, out, interfaces, aliases, classes, visited)
    AssertsPredicate(_, Some(inner)) =>
      walk_type_for_props(inner, out, interfaces, aliases, classes, visited)
    _ => ()
  }
}

///|
fn visit_named_type_for_props(
  name : String,
  out : Map[String, Bool],
  interfaces : Map[String, @ast.TsInterface],
  aliases : Map[String, @ast.TsTypeAlias],
  classes : Map[String, @ast.TsClassDecl],
  visited : Map[String, Bool],
) -> Unit {
  if visited.contains(name) {
    return
  }
  visited[name] = true
  match interfaces.get(name) {
    Some(i) =>
      walk_interface_for_props(i, out, interfaces, aliases, classes, visited)
    None => ()
  }
  match aliases.get(name) {
    Some(a) =>
      walk_type_for_props(a.type_, out, interfaces, aliases, classes, visited)
    None => ()
  }
  match classes.get(name) {
    Some(c) =>
      walk_class_for_props(c, out, interfaces, aliases, classes, visited)
    None => ()
  }
}
