// Type-aware auto-reserved set for the mangler.
//
// The packelyze-style mangle pass needs to know which identifiers
// and which property keys "escape" — i.e. are visible to external
// code through an exported type, function, or value. Renaming those
// would silently break consumers; everything else is fair game.
//
// `auto_reserve_from_module` walks the type graph backward from
// every name in `TsModuleBlock.exports`, marking each transitively
// reachable interface / class / type alias as "external". The
// property names on those types end up in the property reserved
// set; the type names themselves end up in the identifier reserved
// set.
//
// Inputs: the parsed `TsModuleBlock` (for the export markers) plus
// the surface `TsModule` it folds into (for the declaration table).
// Output: a `ManglerConfig` whose `reserved` / `reserved_properties`
// arrays are pre-populated. The caller can layer on additional names
// with `with_reserved` / `with_reserved_properties`.

///|
/// Run the type-graph walk and return a `ManglerConfig` augmented with
/// the auto-derived reserved sets. Pass `base` to thread in the
/// caller's other settings (`preserve_top_level`, `mangle_properties`,
/// custom keep-lists).
pub fn auto_reserve_from_module(
  block : @ast.TsModuleBlock,
  module_ : @ast.TsModule,
  base : ManglerConfig,
) -> ManglerConfig {
  let reachable : Map[String, Bool] = {}
  let reserved_props : Map[String, Bool] = {}
  let exported_names : Map[String, Bool] = {}
  for spec in block.exports {
    exported_names[spec.local_name] = true
    exported_names[spec.export_name] = true
    walk_exported_name(spec.local_name, module_, reachable, reserved_props)
  }
  // Re-exports of named bindings (`export { Foo } from "./bar"`)
  // also keep `Foo` visible — its members count as external.
  for re in block.reexports {
    match re.kind {
      Named(specs) =>
        for s in specs {
          let (local_name, exported_name) = s
          exported_names[local_name] = true
          exported_names[exported_name] = true
        }
      _ => ()
    }
  }
  // `export = X` and `export default X` aren't in `exports` (they
  // live in the runtime stmts). For now we also reserve every
  // declaration the module surfaces at the top level — that gives a
  // safe-by-default baseline; downstream tooling can opt to mangle
  // those by passing `preserve_top_level=false`.
  // Combine results into the config.
  let reserved_names_arr : Array[String] = []
  for entry in exported_names {
    reserved_names_arr.push(entry.0)
  }
  for entry in reachable {
    reserved_names_arr.push(entry.0)
  }
  // Top-level `import` bindings name the same slot in the module
  // scope that the mangler is about to allocate short names from.
  // Without this guard the mangler can hand the short name `os`
  // to a renamed CJS helper while `import os from "os"` already
  // owns that slot, producing `SyntaxError: Identifier 'os' has
  // already been declared`.
  for imp in block.imports {
    match imp.default_binding {
      Some(n) => reserved_names_arr.push(n)
      None => ()
    }
    match imp.namespace_binding {
      Some(n) => reserved_names_arr.push(n)
      None => ()
    }
    for nb in imp.named_bindings {
      reserved_names_arr.push(nb.1)
    }
  }
  let reserved_props_arr : Array[String] = []
  for entry in reserved_props {
    reserved_props_arr.push(entry.0)
  }
  base
  .with_reserved(reserved_names_arr)
  .with_reserved_properties(reserved_props_arr)
}

// ---------------------------------------------------------------------------
// Graph walk
// ---------------------------------------------------------------------------

///|
/// Look up `name` in the module's declaration tables and walk any
/// types it references. Idempotent on visited names (the recursion
/// terminates because `walk_type_ref` caches in `reachable`).
fn walk_exported_name(
  name : String,
  module_ : @ast.TsModule,
  reachable : Map[String, Bool],
  reserved_props : Map[String, Bool],
) -> Unit {
  // Treat the name itself as a possible type reference — picks up
  // exported interfaces / classes / type aliases automatically.
  walk_type_ref(name, module_, reachable, reserved_props)
  // Also walk function / value / class signatures that share the
  // exported name. A name might match more than one declaration kind
  // (e.g. `function fetch(...)` + `interface fetch`), so walk every
  // matching slot.
  for f in module_.funcs {
    if f.name == name {
      walk_func_signature(f, module_, reachable, reserved_props)
    }
  }
  for imp in module_.imports {
    if imp.name == name {
      walk_import_signature(imp, module_, reachable, reserved_props)
    }
  }
  for v in module_.values {
    if v.name == name {
      walk_type(v.type_, module_, reachable, reserved_props)
    }
  }
}

///|
fn walk_func_signature(
  f : @ast.TsFunc,
  module_ : @ast.TsModule,
  reachable : Map[String, Bool],
  reserved_props : Map[String, Bool],
) -> Unit {
  for p in f.params {
    walk_type(p.type_, module_, reachable, reserved_props)
  }
  walk_type(f.return_type, module_, reachable, reserved_props)
}

///|
fn walk_import_signature(
  imp : @ast.TsImport,
  module_ : @ast.TsModule,
  reachable : Map[String, Bool],
  reserved_props : Map[String, Bool],
) -> Unit {
  for p in imp.params {
    walk_type(p.1, module_, reachable, reserved_props)
  }
  walk_type(imp.return_type, module_, reachable, reserved_props)
}

///|
/// Resolve a named type reference and mark every transitively-
/// reachable interface / class / type alias as visited. Idempotent
/// on already-seen names.
fn walk_type_ref(
  name : String,
  module_ : @ast.TsModule,
  reachable : Map[String, Bool],
  reserved_props : Map[String, Bool],
) -> Unit {
  if reachable.contains(name) {
    return
  }
  // Mark seen *before* recursing so cycles (e.g. a self-referential
  // linked-list interface) terminate.
  reachable[name] = true
  for iface in module_.interfaces {
    if iface.name == name {
      for f in iface.fields {
        reserved_props[f.0] = true
        walk_type(f.1, module_, reachable, reserved_props)
      }
      for ext_name in iface.extends_names {
        walk_type_ref(ext_name, module_, reachable, reserved_props)
      }
      for ext_args in iface.extends_args {
        for a in ext_args {
          walk_type(a, module_, reachable, reserved_props)
        }
      }
      for sig in iface.index_signatures {
        walk_type(sig.0, module_, reachable, reserved_props)
        walk_type(sig.1, module_, reachable, reserved_props)
      }
    }
  }
  for cls in module_.classes {
    if cls.name == name {
      for p in cls.properties {
        reserved_props[p.name] = true
        walk_type(p.type_, module_, reachable, reserved_props)
      }
      for m in cls.methods {
        reserved_props[m.name] = true
        for param in m.params {
          walk_type(param.1, module_, reachable, reserved_props)
        }
        walk_type(m.return_type, module_, reachable, reserved_props)
      }
      // Constructor parameters often reference user types too.
      match cls.constructor_params {
        Some(params) =>
          for p in params {
            walk_type(p.1, module_, reachable, reserved_props)
          }
        None => ()
      }
      for base_name in cls.base_names {
        walk_type_ref(base_name, module_, reachable, reserved_props)
      }
      for sig in cls.index_signatures {
        walk_type(sig.0, module_, reachable, reserved_props)
        walk_type(sig.1, module_, reachable, reserved_props)
      }
    }
  }
  for ta in module_.type_aliases {
    if ta.name == name {
      walk_type(ta.type_, module_, reachable, reserved_props)
    }
  }
}

///|
/// Walk a `TsType`, collecting transitively-reachable type names and
/// any inline object-literal property keys (those are part of the
/// public surface too — a function `(x: { name: string })` exposes
/// `name` externally).
fn walk_type(
  ty : @ast.TsType,
  module_ : @ast.TsModule,
  reachable : Map[String, Bool],
  reserved_props : Map[String, Bool],
) -> Unit {
  match ty {
    Named(name) => walk_type_ref(name, module_, reachable, reserved_props)
    Applied(name, args) => {
      walk_type_ref(name, module_, reachable, reserved_props)
      for a in args {
        walk_type(a, module_, reachable, reserved_props)
      }
    }
    Array(inner) | Keyof(inner) | Rest(inner) =>
      walk_type(inner, module_, reachable, reserved_props)
    Tuple(items) | Union(items) | Intersection(items) =>
      for it in items {
        walk_type(it, module_, reachable, reserved_props)
      }
    Object(fields) =>
      for f in fields {
        match f.0 {
          Literal(name) => reserved_props[name] = true
          _ => ()
        }
        walk_type(f.0, module_, reachable, reserved_props)
        walk_type(f.1, module_, reachable, reserved_props)
      }
    Struct(_, fields) =>
      for f in fields {
        reserved_props[f.0] = true
        walk_type(f.1, module_, reachable, reserved_props)
      }
    Func(params, ret) | Constructor(params, ret, _) => {
      for p in params {
        walk_type(p, module_, reachable, reserved_props)
      }
      walk_type(ret, module_, reachable, reserved_props)
    }
    Conditional(check, ext, t, f) => {
      walk_type(check, module_, reachable, reserved_props)
      walk_type(ext, module_, reachable, reserved_props)
      walk_type(t, module_, reachable, reserved_props)
      walk_type(f, module_, reachable, reserved_props)
    }
    IndexedAccess(base, key) => {
      walk_type(base, module_, reachable, reserved_props)
      walk_type(key, module_, reachable, reserved_props)
    }
    MappedType(_, source, value, _) => {
      walk_type(source, module_, reachable, reserved_props)
      walk_type(value, module_, reachable, reserved_props)
    }
    MappedTypeRemap(_, source, remap, value, _) => {
      walk_type(source, module_, reachable, reserved_props)
      walk_type(remap, module_, reachable, reserved_props)
      walk_type(value, module_, reachable, reserved_props)
    }
    TemplateLiteralType(_, args) =>
      for a in args {
        walk_type(a, module_, reachable, reserved_props)
      }
    TypePredicate(_, t) => walk_type(t, module_, reachable, reserved_props)
    AssertsPredicate(_, opt) =>
      match opt {
        Some(t) => walk_type(t, module_, reachable, reserved_props)
        None => ()
      }
    _ => ()
  }
}

// ---------------------------------------------------------------------------
// Convenience: full parse → auto-reserve → mangle in one call
// ---------------------------------------------------------------------------

///|
/// One-shot helper: parse `source` as a TS module, compute the auto-
/// reserved set from its exports, and run the mangle pass against
/// the runtime statement stream. Returns the JS source as a string.
///
/// `base` controls everything else (`mangle_properties`,
/// `preserve_top_level`, extra reserved entries). The auto-derived
/// reserved names are *added* on top — so a function the user
/// marked as private but is also exported by name still stays
/// renameable via base settings.
pub fn mangle_source_with_auto_reserve(
  source : String,
  base : ManglerConfig,
) -> Result[String, String] {
  let parser = @parser.Parser::from_source(source)
  let block = try parser.parse_module_block() catch {
    e => return Err("parse error: \{e}")
  } noraise {
    b => b
  }
  // Re-parse via the lower-level `parse_module` so we get the
  // declaration tables (`TsModule.interfaces` / `.classes` etc.)
  // alongside the runtime stmts. The two parses are independent;
  // the parser keeps no global state between calls.
  let parser2 = @parser.Parser::from_source(source)
  let module_ = try parser2.parse_module() catch {
    e => return Err("parse error: \{e}")
  } noraise {
    m => m
  }
  let cfg = auto_reserve_from_module(block, module_, base)
  let mangled = mangle_block(block.block, cfg)
  let e = Emitter::new()
  for s in mangled.stmts {
    emit_stmt(e, s)
    e.nl()
  }
  Ok(e.to_string())
}
