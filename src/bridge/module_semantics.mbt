///|
pub(all) suberror ModuleGraphError {
  ReadError(String)
  ParseError(String)
  ResolveError(String)
} derive(Debug)

///|
struct ResolvedImportEdge {
  specifier : String
  resolved_path : String
  type_only : Bool
  side_effect_only : Bool
} derive(Debug)

///|
struct ResolvedReExportEdge {
  specifier : String
  resolved_path : String
  kind : @ast.TsReExportKind
  type_only : Bool
} derive(Debug)

///|
struct ResolvedModuleRecord {
  path : String
  module_block : @ast.TsModuleBlock
  imports : Array[ResolvedImportEdge]
  reexports : Array[ResolvedReExportEdge]
} derive(Debug)

///|
struct ModuleGraph {
  entry_path : String
  modules : Array[ResolvedModuleRecord]
} derive(Debug)

///|
enum ResolvedExportKind {
  Local
  NamedReExport
  StarReExport
  Namespace
  Ambiguous
} derive(Eq, Debug)

///|
struct ResolvedExport {
  export_name : String
  source_export_name : String
  source_path : String
  local_name : String?
  kind : ResolvedExportKind
  via_path : String?
  ambiguous_source_paths : Array[String]
  type_only : Bool
} derive(Debug)

///|
fn resolved_export_source_paths(export_ : ResolvedExport) -> Array[String] {
  let paths : Array[String] = []
  if export_.ambiguous_source_paths.length() > 0 {
    for path in export_.ambiguous_source_paths {
      if !paths.contains(path) {
        paths.push(path)
      }
    }
  } else if export_.source_path != "" {
    paths.push(export_.source_path)
  }
  paths.sort()
  paths
}

///|
fn make_ambiguous_export(
  existing : ResolvedExport,
  incoming : ResolvedExport,
) -> ResolvedExport {
  let ambiguous_source_paths = resolved_export_source_paths(existing)
  for path in resolved_export_source_paths(incoming) {
    if !ambiguous_source_paths.contains(path) {
      ambiguous_source_paths.push(path)
    }
  }
  ambiguous_source_paths.sort()
  {
    export_name: existing.export_name,
    source_export_name: existing.source_export_name,
    source_path: existing.source_path,
    local_name: None,
    kind: Ambiguous,
    via_path: None,
    ambiguous_source_paths,
    type_only: existing.type_only && incoming.type_only,
  }
}

///|
async fn resolve_type_module_specifier(
  base_path : String,
  specifier : String,
) -> String? {
  @parser.resolve_type_module_specifier(base_path, specifier) catch {
    _ => None
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
  let reexport_module_specs : Array[String] = []
  for reexport in module_block.reexports {
    if !reexport_module_specs.contains(reexport.module_spec) {
      reexport_module_specs.push(reexport.module_spec)
    }
  }
  let imports : Array[ResolvedImportEdge] = []
  for decl in module_block.imports {
    let should_resolve_import = import_binding_is_exported(module_block, decl) ||
      module_specifier_is_path_like(decl.module_spec) ||
      reexport_module_specs.contains(decl.module_spec)
    if !should_resolve_import {
      imports.push({
        specifier: decl.module_spec,
        resolved_path: "",
        type_only: decl.type_only,
        side_effect_only: decl.side_effect_only,
      })
      continue
    }
    let resolved_path = resolve_type_module_specifier(path, decl.module_spec) catch {
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
        load_module_record(dep_path, loaded, visiting) catch {
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
    let resolved_path = resolve_type_module_specifier(
      path,
      reexport.module_spec,
    ) catch {
      _ => None
    }
    match resolved_path {
      Some(dep_path) => {
        reexports.push({
          specifier: reexport.module_spec,
          resolved_path: dep_path,
          kind: reexport.kind,
          type_only: reexport.type_only,
        })
        load_module_record(dep_path, loaded, visiting)
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
async fn load_type_module_graph(
  entry_path : String,
) -> ModuleGraph raise ModuleGraphError {
  let loaded : Map[String, ResolvedModuleRecord] = {}
  let visiting : Array[String] = []
  load_module_record(entry_path, loaded, visiting)
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
  type_only : Bool,
) -> ResolvedExport {
  {
    export_name,
    source_export_name: export_.source_export_name,
    source_path: export_.source_path,
    local_name: export_.local_name,
    kind,
    via_path,
    ambiguous_source_paths: export_.ambiguous_source_paths,
    type_only: export_.type_only || type_only,
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
fn find_import_edge(
  record : ResolvedModuleRecord,
  specifier : String,
) -> ResolvedImportEdge? {
  for edge in record.imports {
    if edge.specifier == specifier {
      return Some(edge)
    }
  }
  None
}

///|
fn fallback_imported_binding_export(
  imported_name : String,
  source_path : String,
) -> ResolvedExport {
  {
    export_name: imported_name,
    source_export_name: imported_name,
    source_path,
    local_name: Some(imported_name),
    kind: NamedReExport,
    via_path: None,
    ambiguous_source_paths: [],
    type_only: false,
  }
}

///|
fn resolve_imported_binding_export(
  record : ResolvedModuleRecord,
  local_name : String,
  records : Map[String, ResolvedModuleRecord],
  cache : Map[String, Array[ResolvedExport]],
  visiting : Array[String],
) -> ResolvedExport? {
  for import_decl in record.module_block.imports {
    let edge = match find_import_edge(record, import_decl.module_spec) {
      Some(edge) if edge.resolved_path != "" => edge
      _ => continue
    }
    for binding in import_decl.named_bindings {
      let (imported_name, bound_local_name) = binding
      if bound_local_name != local_name {
        continue
      }
      let dep_exports = resolve_export_surface_from_map(
        edge.resolved_path,
        records,
        cache,
        visiting,
      )
      match find_named_export(dep_exports, imported_name) {
        Some(dep_export) => return Some(dep_export)
        None =>
          return Some(
            fallback_imported_binding_export(imported_name, edge.resolved_path),
          )
      }
    }
    match import_decl.default_binding {
      Some(bound_local_name) if bound_local_name == local_name => {
        let dep_exports = resolve_export_surface_from_map(
          edge.resolved_path,
          records,
          cache,
          visiting,
        )
        match find_named_export(dep_exports, "default") {
          Some(dep_export) => return Some(dep_export)
          None =>
            return Some(
              fallback_imported_binding_export("default", edge.resolved_path),
            )
        }
      }
      _ => ()
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
        exports[idx] = make_ambiguous_export(existing, export_)
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
        Ambiguous => exports[idx] = make_ambiguous_export(existing, export_)
        StarReExport =>
          if existing.source_path != export_.source_path ||
            existing.local_name != export_.local_name {
            exports[idx] = make_ambiguous_export(existing, export_)
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
    match
      resolve_imported_binding_export(
        record,
        spec.local_name,
        records,
        cache,
        visiting,
      ) {
      Some(imported_export) => {
        let kind = match imported_export.kind {
          Namespace => Namespace
          _ => NamedReExport
        }
        upsert_explicit_export(
          exports,
          clone_export_with_name(
            imported_export,
            spec.export_name,
            kind,
            Some(path),
            false,
          ),
        )
      }
      None =>
        upsert_explicit_export(exports, {
          export_name: spec.export_name,
          source_export_name: spec.export_name,
          source_path: path,
          local_name: Some(spec.local_name),
          kind: Local,
          via_path: None,
          ambiguous_source_paths: [],
          type_only: false,
        })
    }
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
                  reexport.type_only,
                ),
              )
            None => ()
          }
        }
      }
      @ast.TsReExportKind::Namespace(name) =>
        upsert_explicit_export(exports, {
          export_name: name,
          source_export_name: name,
          source_path: reexport.resolved_path,
          local_name: None,
          kind: Namespace,
          via_path: Some(path),
          ambiguous_source_paths: [],
          type_only: reexport.type_only,
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
          reexport.type_only,
        ),
      )
    }
  }
  cache[path] = exports
  let _ = visiting.pop()
  exports
}

///|
fn resolve_export_surface(graph : ModuleGraph) -> Array[ResolvedExport] {
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
fn scaffold_unsupported_export_text(export_ : ResolvedExport) -> String {
  let base = "\{export_.export_name} (ambiguous re-export"
  if export_.ambiguous_source_paths.length() == 0 {
    base + ")"
  } else {
    base + ": " + export_.ambiguous_source_paths.join(", ") + ")"
  }
}

///|
fn push_unique_scaffold_unsupported_export(
  unsupported_exports : Array[String],
  item : String,
) -> Unit {
  if !unsupported_exports.contains(item) {
    unsupported_exports.push(item)
  }
}

///|
fn scaffold_unsupported_decl_note_text(note : String) -> String? {
  let prefix = "///|\n/// Unsupported export "
  if !note.has_prefix(prefix) {
    return None
  }
  let body = note[prefix.length():].to_owned()
  if body.contains("ambiguous re-export") {
    return None
  }
  if body.contains("namespace export is widened to JSValue") ||
    body.contains("runtime members inside exported namespace are omitted") {
    return None
  }
  match body.find(": ") {
    Some(idx) => {
      let export_name = body[:idx].to_owned()
      let reason = body[idx + 2:].to_owned()
      Some("\{export_name} (\{reason})")
    }
    None => Some(body)
  }
}

///|
pub async fn collect_moonbit_ts_scaffold_unsupported_exports(
  entry_path : String,
) -> Array[String] raise ModuleGraphError {
  let graph = load_type_module_graph(entry_path)
  let export_surface = resolve_export_surface(graph)
  let unsupported_exports : Array[String] = []
  for export_ in export_surface {
    match export_.kind {
      Ambiguous =>
        push_unique_scaffold_unsupported_export(
          unsupported_exports,
          scaffold_unsupported_export_text(export_),
        )
      _ => ()
    }
  }
  let modules = build_decl_module_map(graph)
  let (_, _, _, _, _, _, _, _, notes) = collect_exported_decls(
    graph, export_surface, modules,
  )
  for note in notes {
    match scaffold_unsupported_decl_note_text(note) {
      Some(item) =>
        push_unique_scaffold_unsupported_export(unsupported_exports, item)
      None => ()
    }
  }
  unsupported_exports
}
