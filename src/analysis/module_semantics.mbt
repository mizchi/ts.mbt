///|
pub(all) suberror ModuleGraphError {
  ReadError(String)
  ParseError(String)
  ResolveError(String)
} derive(Debug)

///|
priv enum ModuleGraphMode {
  Types
  Runtime
}

///|
pub struct ResolvedImportEdge {
  specifier : String
  resolved_path : String
  type_only : Bool
  side_effect_only : Bool
} derive(Debug)

///|
pub struct ResolvedReExportEdge {
  specifier : String
  resolved_path : String
  kind : @ast.TsReExportKind
} derive(Debug)

///|
pub struct ResolvedModuleRecord {
  path : String
  module_block : @ast.TsModuleBlock
  imports : Array[ResolvedImportEdge]
  reexports : Array[ResolvedReExportEdge]
} derive(Debug)

///|
pub struct ModuleGraph {
  entry_path : String
  modules : Array[ResolvedModuleRecord]
} derive(Debug)

///|
pub enum ResolvedExportKind {
  Local
  NamedReExport
  StarReExport
  Namespace
  Ambiguous
} derive(Eq, Debug)

///|
pub struct ResolvedExport {
  export_name : String
  source_path : String
  local_name : String?
  kind : ResolvedExportKind
  via_path : String?
} derive(Debug)

///|
async fn resolve_module_specifier_with_mode(
  base_path : String,
  specifier : String,
  mode : ModuleGraphMode,
) -> String? {
  match mode {
    Types =>
      @parser.resolve_type_module_specifier(base_path, specifier) catch {
        _ => None
      }
    Runtime =>
      @parser.resolve_runtime_module_specifier(base_path, specifier) catch {
        _ => None
      }
  }
}

///|
fn import_binding_is_exported(
  module_block : @ast.TsModuleBlock,
  import_decl : @ast.TsImportDecl,
) -> Bool {
  let exported_locals : Array[String] = []
  for export_ in module_block.exports {
    exported_locals.push(export_.local_name)
  }
  for binding in import_decl.named_bindings {
    let (_, local_name) = binding
    if exported_locals.contains(local_name) {
      return true
    }
  }
  match import_decl.default_binding {
    Some(local_name) if exported_locals.contains(local_name) => return true
    _ => ()
  }
  match import_decl.namespace_binding {
    Some(local_name) if exported_locals.contains(local_name) => return true
    _ => ()
  }
  false
}

///|
fn module_specifier_is_path_like(specifier : String) -> Bool {
  specifier.has_prefix("./") ||
  specifier.has_prefix("../") ||
  specifier.has_prefix("/")
}

///|
async fn load_module_record(
  path : String,
  mode : ModuleGraphMode,
  loaded : Map[String, ResolvedModuleRecord],
  visiting : Array[String],
) -> Unit raise ModuleGraphError {
  if loaded.contains(path) || visiting.contains(path) {
    return
  }
  visiting.push(path)
  let content = @fs.read_file(path).text() catch {
    e => raise ReadError("Failed to read module '\{path}': \{e}")
  }
  let module_block = @parser.parse_module_block_from_source(content) catch {
    @parser.ParseError(msg) =>
      raise ParseError("Failed to parse module '\{path}': \{msg}")
  }
  let imports : Array[ResolvedImportEdge] = []
  for decl in module_block.imports {
    let should_resolve_import = import_binding_is_exported(module_block, decl) ||
      module_specifier_is_path_like(decl.module_spec)
    if !should_resolve_import {
      imports.push({
        specifier: decl.module_spec,
        resolved_path: "",
        type_only: decl.type_only,
        side_effect_only: decl.side_effect_only,
      })
      continue
    }
    let resolved_path = resolve_module_specifier_with_mode(
      path,
      decl.module_spec,
      mode,
    ) catch {
      _ => None
    }
    match resolved_path {
      Some(dep_path) => {
        imports.push({
          specifier: decl.module_spec,
          resolved_path: dep_path,
          type_only: decl.type_only,
          side_effect_only: decl.side_effect_only,
        })
        load_module_record(dep_path, mode, loaded, visiting) catch {
          ReadError(_) | ParseError(_) | ResolveError(_) => ()
        }
      }
      None =>
        imports.push({
          specifier: decl.module_spec,
          resolved_path: "",
          type_only: decl.type_only,
          side_effect_only: decl.side_effect_only,
        })
    }
  }
  let reexports : Array[ResolvedReExportEdge] = []
  for reexport in module_block.reexports {
    let resolved_path = resolve_module_specifier_with_mode(
      path,
      reexport.module_spec,
      mode,
    ) catch {
      _ => None
    }
    match resolved_path {
      Some(dep_path) => {
        reexports.push({
          specifier: reexport.module_spec,
          resolved_path: dep_path,
          kind: reexport.kind,
        })
        load_module_record(dep_path, mode, loaded, visiting)
      }
      None =>
        if module_specifier_is_path_like(reexport.module_spec) {
          raise ResolveError(
            "Failed to resolve reexport '\{reexport.module_spec}' from '\{path}'",
          )
        } else {
          ()
        }
    }
  }
  loaded[path] = { path, module_block, imports, reexports }
  let _ = visiting.pop()
}

///|
async fn load_module_graph_with_mode(
  entry_path : String,
  mode : ModuleGraphMode,
) -> ModuleGraph raise ModuleGraphError {
  let loaded : Map[String, ResolvedModuleRecord] = {}
  let visiting : Array[String] = []
  load_module_record(entry_path, mode, loaded, visiting)
  let paths : Array[String] = []
  for entry in loaded {
    paths.push(entry.0)
  }
  paths.sort()
  let modules : Array[ResolvedModuleRecord] = []
  for path in paths {
    match loaded.get(path) {
      Some(record) => modules.push(record)
      None => ()
    }
  }
  { entry_path, modules }
}

///|
pub async fn load_type_module_graph(
  entry_path : String,
) -> ModuleGraph raise ModuleGraphError {
  load_module_graph_with_mode(entry_path, ModuleGraphMode::Types)
}

///|
pub async fn load_runtime_module_graph(
  entry_path : String,
) -> ModuleGraph raise ModuleGraphError {
  load_module_graph_with_mode(entry_path, ModuleGraphMode::Runtime)
}

///|
fn graph_to_map(graph : ModuleGraph) -> Map[String, ResolvedModuleRecord] {
  let result : Map[String, ResolvedModuleRecord] = {}
  for module_ in graph.modules {
    result[module_.path] = module_
  }
  result
}

///|
fn find_export_index(
  exports : Array[ResolvedExport],
  export_name : String,
) -> Int? {
  for i, export_ in exports {
    if export_.export_name == export_name {
      return Some(i)
    }
  }
  None
}

///|
fn clone_export_with_name(
  export_ : ResolvedExport,
  export_name : String,
  kind : ResolvedExportKind,
  via_path : String?,
) -> ResolvedExport {
  {
    export_name,
    source_path: export_.source_path,
    local_name: export_.local_name,
    kind,
    via_path,
  }
}

///|
fn find_named_export(
  exports : Array[ResolvedExport],
  export_name : String,
) -> ResolvedExport? {
  for export_ in exports {
    if export_.export_name == export_name && export_.kind != Ambiguous {
      return Some(export_)
    }
  }
  None
}

///|
fn upsert_explicit_export(
  exports : Array[ResolvedExport],
  export_ : ResolvedExport,
) -> Unit {
  match find_export_index(exports, export_.export_name) {
    Some(idx) => {
      let existing = exports[idx]
      if existing.source_path == export_.source_path &&
        existing.local_name == export_.local_name {
        exports[idx] = export_
      } else {
        exports[idx] = {
          export_name: export_.export_name,
          source_path: existing.source_path,
          local_name: None,
          kind: Ambiguous,
          via_path: None,
        }
      }
    }
    None => exports.push(export_)
  }
}

///|
fn merge_star_export(
  exports : Array[ResolvedExport],
  export_ : ResolvedExport,
) -> Unit {
  match find_export_index(exports, export_.export_name) {
    Some(idx) => {
      let existing = exports[idx]
      match existing.kind {
        Local | NamedReExport | Namespace => ()
        Ambiguous => ()
        StarReExport =>
          if existing.source_path != export_.source_path ||
            existing.local_name != export_.local_name {
            exports[idx] = {
              export_name: export_.export_name,
              source_path: existing.source_path,
              local_name: None,
              kind: Ambiguous,
              via_path: None,
            }
          }
      }
    }
    None => exports.push(export_)
  }
}

///|
fn resolve_export_surface_from_map(
  path : String,
  records : Map[String, ResolvedModuleRecord],
  cache : Map[String, Array[ResolvedExport]],
  visiting : Array[String],
) -> Array[ResolvedExport] {
  match cache.get(path) {
    Some(exports) => return exports
    None => ()
  }
  if visiting.contains(path) {
    return []
  }
  let record = match records.get(path) {
    Some(record) => record
    None => return []
  }
  visiting.push(path)
  let exports : Array[ResolvedExport] = []
  for spec in record.module_block.exports {
    upsert_explicit_export(exports, {
      export_name: spec.export_name,
      source_path: path,
      local_name: Some(spec.local_name),
      kind: Local,
      via_path: None,
    })
  }
  let star_edges : Array[ResolvedReExportEdge] = []
  for reexport in record.reexports {
    match reexport.kind {
      @ast.TsReExportKind::Named(items) => {
        let dep_exports = resolve_export_surface_from_map(
          reexport.resolved_path,
          records,
          cache,
          visiting,
        )
        for item in items {
          let (imported_name, export_name) = item
          match find_named_export(dep_exports, imported_name) {
            Some(dep_export) =>
              upsert_explicit_export(
                exports,
                clone_export_with_name(
                  dep_export,
                  export_name,
                  NamedReExport,
                  Some(path),
                ),
              )
            None => ()
          }
        }
      }
      @ast.TsReExportKind::Namespace(name) =>
        upsert_explicit_export(exports, {
          export_name: name,
          source_path: reexport.resolved_path,
          local_name: None,
          kind: Namespace,
          via_path: Some(path),
        })
      @ast.TsReExportKind::All => star_edges.push(reexport)
    }
  }
  for reexport in star_edges {
    let dep_exports = resolve_export_surface_from_map(
      reexport.resolved_path,
      records,
      cache,
      visiting,
    )
    for dep_export in dep_exports {
      if dep_export.export_name == "default" {
        continue
      }
      merge_star_export(
        exports,
        clone_export_with_name(
          dep_export,
          dep_export.export_name,
          StarReExport,
          Some(path),
        ),
      )
    }
  }
  cache[path] = exports
  let _ = visiting.pop()
  exports
}

///|
pub fn resolve_export_surface(graph : ModuleGraph) -> Array[ResolvedExport] {
  let records = graph_to_map(graph)
  let cache : Map[String, Array[ResolvedExport]] = {}
  let visiting : Array[String] = []
  let exports = resolve_export_surface_from_map(
    graph.entry_path,
    records,
    cache,
    visiting,
  )
  let names : Array[String] = []
  for export_ in exports {
    names.push(export_.export_name)
  }
  names.sort()
  let ordered : Array[ResolvedExport] = []
  for name in names {
    match find_named_export(exports, name) {
      Some(export_) => ordered.push(export_)
      None =>
        match find_export_index(exports, name) {
          Some(idx) => ordered.push(exports[idx])
          None => ()
        }
    }
  }
  ordered
}

///|
pub async fn resolve_type_export_surface(
  entry_path : String,
) -> Array[ResolvedExport] raise ModuleGraphError {
  let graph = load_type_module_graph(entry_path)
  resolve_export_surface(graph)
}

///|
pub async fn resolve_runtime_export_surface(
  entry_path : String,
) -> Array[ResolvedExport] raise ModuleGraphError {
  let graph = load_runtime_module_graph(entry_path)
  resolve_export_surface(graph)
}
