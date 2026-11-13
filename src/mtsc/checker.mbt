///|
/// A strict TypeScript diagnostic that can be consumed by command-line and
/// JavaScript-module callers alike.
pub(all) struct MtscTypeIssue {
  path : String
  message : String
}

///|
/// One caller-resolved TypeScript module for the JavaScript checker API.
/// Resolution intentionally belongs to the embedding build tool; the checker
/// only parses and validates the source texts it is given.
pub(all) struct MtscModuleSource {
  path : String
  source : String
  allowJsx : Bool
}

///|
/// A caller-resolved import edge. Module resolution belongs to the embedding
/// build tool, so aliases and virtual files never leak into the checker.
pub(all) struct MtscModuleEdge {
  importerPath : String
  moduleSpecifier : String
  targetPath : String
}

///|
/// A filesystem-free module graph consumed by `checkModuleGraph`.
pub(all) struct MtscModuleGraph {
  modules : Array[MtscModuleSource]
  edges : Array[MtscModuleEdge]
}

///|
priv struct ParsedMtscModule {
  source : MtscModuleSource
  module_ : @ast.TsModule
  module_block : @ast.TsModuleBlock
}

///|
fn is_unresolved_import_binding(
  issue : @checker.ExprIssue,
  imported_binding_names : Array[String],
) -> Bool {
  for name in imported_binding_names {
    if issue.message == "cannot find name `\{name}`" {
      return true
    }
  }
  false
}

///|
/// Parse source and run the strict checker. Imported bindings are checked in
/// their own modules, so their known single-file unresolved-name false
/// positives are omitted from this module's result.
fn collect_type_issues_from_module(
  module_ : @ast.TsModule,
  globals : Array[(String, @ast.TsType)],
  type_modules : Array[@ast.TsModule],
  namespace_type_aliases~ : Array[(String, String, String)] = [],
  type_module_keys~ : Array[String] = [],
) -> Result[Array[MtscTypeIssue], String] {
  let issues : Array[MtscTypeIssue] = []
  for
    issue in @checker.check_module_function_bodies_with_context(
      module_,
      globals,
      type_modules,
      namespace_type_aliases~,
      type_module_keys~,
    ) {
    if !is_unresolved_import_binding(issue, module_.imported_binding_names) {
      issues.push({ path: issue.path, message: issue.message, })
    }
  }
  Ok(issues)
}

///|
/// `declaration_file~` says the source is a `.d.ts`, which makes every
/// declaration in it ambient whether or not it writes `declare`. A
/// labelled argument with a default, because this is the JavaScript ABI
/// and every existing caller must keep compiling and answering exactly
/// as before — and because the fact lives in the PATH, which a caller
/// holding only `source` genuinely cannot supply. The parse flag is read
/// only to go SILENT, so `false` is today's behaviour.
pub fn collect_type_issues(
  source : String,
  allow_jsx : Bool,
  declaration_file~ : Bool = false,
) -> Result[Array[MtscTypeIssue], String] {
  let parser = @parser.Parser::from_source_with_jsx(source, allow_jsx)
  if declaration_file {
    parser.mark_declaration_file()
  }
  let module_ = parser.parse_module() catch { e => return Err("\{e}") }
  collect_type_issues_from_module(module_, [], [])
}

///|
/// JavaScript-facing strict checker API. Returns an empty string for valid
/// source; otherwise each diagnostic occupies one line as
/// `<path>: <message>`. This keeps the JS ABI plain while the MoonBit CLI can
/// still use `collect_type_issues` for structured diagnostics.
pub fn check_source(source : String, allow_jsx : Bool) -> String {
  match collect_type_issues(source, allow_jsx) {
    Err(e) => "parse error: \{e}"
    Ok(issues) =>
      issues.map(fn(issue) { "\{issue.path}: \{issue.message}" }).join("\n")
  }
}

///|
/// JavaScript-facing strict checker API for a resolved module graph.
/// Resolution remains the caller's responsibility so this package stays
/// independent of filesystems and bundlers.
///
/// Returns an empty string when every supplied module is valid. Diagnostics
/// are prefixed with the caller-provided module path and preserve input order,
/// making the string ABI stable for build-tool integrations.
pub fn check_module_sources(modules : Array[MtscModuleSource]) -> String {
  let diagnostics : Array[String] = []
  for module_ in modules {
    match collect_type_issues(module_.source, module_.allowJsx) {
      Err(e) => diagnostics.push("\{module_.path}: parse error: \{e}")
      Ok(issues) =>
        for issue in issues {
          diagnostics.push("\{module_.path}: \{issue.message}")
        }
    }
  }
  diagnostics.join("\n")
}

///|
fn parse_graph_module(
  source : MtscModuleSource,
) -> Result[ParsedMtscModule, String] {
  // A declaration file makes every declaration in it ambient whether or
  // not it writes `declare`; the PATH is the only place that fact lives,
  // and the bodiless-declaration rules read it only to go silent.
  let is_dts = source.path.has_suffix(".d.ts")
  let p1 = @parser.Parser::from_source_with_jsx(source.source, source.allowJsx)
  if is_dts {
    p1.mark_declaration_file()
  }
  let module_ = p1.parse_module() catch { e => return Err("\{e}") }
  let p2 = @parser.Parser::from_source_with_jsx(source.source, source.allowJsx)
  if is_dts {
    p2.mark_declaration_file()
  }
  let module_block = p2.parse_module_block() catch { e => return Err("\{e}") }
  Ok({ source, module_, module_block, })
}

///|
fn function_value_type(func : @ast.TsFunc) -> @ast.TsType {
  let params : Array[@ast.TsType] = []
  for param in func.params {
    if param.is_rest {
      params.push(@ast.TsType::Rest(param.type_))
    } else {
      params.push(param.type_)
    }
  }
  @ast.TsType::Func(params, func.return_type)
}

///|
fn local_value_type(module_ : @ast.TsModule, name : String) -> @ast.TsType? {
  for value in module_.values {
    if value.name == name {
      match value.type_ {
        Any =>
          match arrow_const_predicate_type(module_, name) {
            Some(t) => return Some(t)
            None => ()
          }
        _ => ()
      }
      return Some(value.type_)
    }
  }
  match arrow_const_predicate_type(module_, name) {
    Some(t) => return Some(t)
    None => ()
  }
  // An OVERLOADED function is several declarations of one name, and the
  // first is only one of its signatures: effect's `pipe` / `flow` have
  // twenty, and handing an importer the first made every call with more
  // arguments "expected 1 argument(s)". A union of the declarations' types
  // is the overload-set shape the checker ingests a local one as.
  let sigs : Array[@ast.TsType] = []
  for func in module_.funcs {
    if func.name == name {
      sigs.push(function_value_type(func))
    }
  }
  match sigs.length() {
    0 => ()
    1 => return Some(sigs[0])
    _ => return Some(@ast.TsType::Union(sigs))
  }
  for import_ in module_.imports {
    if import_.name == name {
      let params : Array[@ast.TsType] = []
      for param in import_.params {
        params.push(param.1)
      }
      return Some(@ast.TsType::Func(params, import_.return_type))
    }
  }
  for enum_ in module_.enums {
    if enum_.name == name {
      return Some(@ast.TsType::Named(name))
    }
  }
  for class_ in module_.classes {
    if class_.name == name {
      return Some(@ast.TsType::Named(name))
    }
  }
  None
}

///|
/// `const NAME = (x: T): x is U => …` — how effect writes a guard — is in
/// `values` as `Any` (no annotation), so an importer saw no predicate at
/// all. Only a predicate return is taken, and its PARAMETERS are `any`:
/// an arrow's own `<A>` is not in the AST, so the written parameter types
/// could carry unbound names into every argument check of every call.
fn arrow_const_predicate_type(
  module_ : @ast.TsModule,
  name : String,
) -> @ast.TsType? {
  for stmt in module_.top_level_stmts {
    match stmt {
      Const(Ident(n), Any, ArrowFunc(params, TypePredicate(p, t), _, _)) if n ==
        name => {
        let ps : Array[@ast.TsType] = []
        for _ in params {
          ps.push(Any)
        }
        return Some(Func(ps, TypePredicate(p, t)))
      }
      _ => ()
    }
  }
  None
}

///|
/// True when `module_` exports `name` as a function declared more than once.
fn exported_is_overload_set(module_ : ParsedMtscModule, name : String) -> Bool {
  let mut local = name
  for export_ in module_.module_block.exports {
    if export_.export_name == name {
      local = export_.local_name
      break
    }
  }
  let mut n = 0
  for f in module_.module_.funcs {
    if f.name == local {
      n = n + 1
    }
  }
  n > 1
}

///|
/// True when `ty` can narrow: a predicate-returning callable, generic or
/// not, or an object type whose call signatures include one.
fn is_predicate_value_type(ty : @ast.TsType) -> Bool {
  match ty {
    Func(_, TypePredicate(_, _)) => true
    GenericFunc(_, _, inner) => is_predicate_value_type(inner)
    Object(entries) =>
      entries.iter().any(fn(e) { is_predicate_value_type(e.1) })
    _ => false
  }
}

///|
fn exported_value_type(
  module_ : ParsedMtscModule,
  export_name : String,
  modules : Array[ParsedMtscModule],
  edges : Array[MtscModuleEdge],
  seen : Array[(String, String)],
) -> @ast.TsType? {
  for export_ in module_.module_block.exports {
    if export_.export_name == export_name {
      return local_value_type(module_.module_, export_.local_name)
    }
  }
  // `export { value } from "./module"` is the ordinary public-barrel style.
  // Follow only value reexports here; `export type` never introduces a
  // runtime binding for an importing module.
  for item in seen {
    if item.0 == module_.source.path && item.1 == export_name {
      return None
    }
  }
  let next_seen : Array[(String, String)] = []
  for item in seen {
    next_seen.push(item)
  }
  next_seen.push((module_.source.path, export_name))
  for reexport_ in module_.module_block.reexports {
    if reexport_.type_only {
      continue
    }
    let target_path = match
      find_graph_target(edges, module_.source.path, reexport_.module_spec) {
      Some(path) => path
      None => continue
    }
    let target = match find_graph_module(modules, target_path) {
      Some(target) => target
      None => continue
    }
    match reexport_.kind {
      @ast.TsReExportKind::Named(items) =>
        for item in items {
          let (imported_name, reexported_name) = item
          if reexported_name == export_name {
            match
              exported_value_type(
                target, imported_name, modules, edges, next_seen,
              ) {
              Some(type_) => return Some(type_)
              None => ()
            }
          }
        }
      @ast.TsReExportKind::All =>
        if export_name != "default" {
          match
            exported_value_type(target, export_name, modules, edges, next_seen) {
            Some(type_) => return Some(type_)
            None => ()
          }
        }
      // A namespace is an object-like value with members that the lightweight
      // checker cannot faithfully describe as one static function/value type.
      @ast.TsReExportKind::Namespace(_) => ()
    }
  }
  None
}

///|
fn find_graph_module(
  modules : Array[ParsedMtscModule],
  path : String,
) -> ParsedMtscModule? {
  for module_ in modules {
    if module_.source.path == path {
      return Some(module_)
    }
  }
  None
}

///|
fn find_graph_target(
  edges : Array[MtscModuleEdge],
  importer_path : String,
  module_specifier : String,
) -> String? {
  for edge in edges {
    if edge.importerPath == importer_path &&
      edge.moduleSpecifier == module_specifier {
      return Some(edge.targetPath)
    }
  }
  None
}

///|
fn is_local_module_specifier(module_specifier : String) -> Bool {
  // `.` and `..` are relative too — a package's own modules reach their
  // barrel with `from "."`. Missing them here makes the graph edge for
  // that import invisible to the checker, so every type the barrel
  // re-exports reads as unresolved.
  module_specifier == "." ||
  module_specifier == ".." ||
  module_specifier.has_prefix("./") ||
  module_specifier.has_prefix("../") ||
  module_specifier.has_prefix("/")
}

///|
/// The type names a module exposes, as `(exposed, bare)` pairs: its own
/// type declarations, plus whatever its re-exports expose — `export *`
/// unchanged, `export { A as B }` under the new name, and
/// `export * as ns` under `ns.`. `bare` is the key the resolver ingested
/// the declaration at (`graph_type_modules` ingests every reachable module
/// at bare names), so the pair is all `alias_namespace_import_types`
/// needs. Every declared type counts, exported or not: an unexported one
/// is already reachable at its bare name, so the qualified key adds no
/// declaration the resolver does not already hold.
fn graph_exposed_type_names(
  module_ : ParsedMtscModule,
  modules : Array[ParsedMtscModule],
  edges : Array[MtscModuleEdge],
  seen : Map[String, Unit],
  out : Array[(String, String, String)],
  prefix : String,
  depth : Int32,
) -> Unit {
  if depth > 8 || seen.contains(prefix + "|" + module_.source.path) {
    return
  }
  seen[prefix + "|" + module_.source.path] = ()
  let m = module_.module_
  for i in m.interfaces {
    out.push((prefix + i.name, i.name, module_.source.path))
  }
  for c in m.classes {
    out.push((prefix + c.name, c.name, module_.source.path))
  }
  for a in m.type_aliases {
    out.push((prefix + a.name, a.name, module_.source.path))
  }
  for e in m.enums {
    out.push((prefix + e.name, e.name, module_.source.path))
  }
  for re in module_.module_block.reexports {
    let target = match
      find_graph_target(edges, module_.source.path, re.module_spec) {
      Some(path) =>
        match find_graph_module(modules, path) {
          Some(t) => t
          None => continue
        }
      None => continue
    }
    match re.kind {
      @ast.TsReExportKind::All =>
        graph_exposed_type_names(
          target,
          modules,
          edges,
          seen,
          out,
          prefix,
          depth + 1,
        )
      @ast.TsReExportKind::Namespace(ns) =>
        graph_exposed_type_names(
          target,
          modules,
          edges,
          seen,
          out,
          prefix + ns + ".",
          depth + 1,
        )
      @ast.TsReExportKind::Named(items) => {
        let inner : Array[(String, String, String)] = []
        graph_exposed_type_names(
          target,
          modules,
          edges,
          {},
          inner,
          "",
          depth + 1,
        )
        for item in items {
          let (imported, exported) = item
          for pair in inner {
            if pair.0 == imported {
              out.push((prefix + exported, pair.1, pair.2))
            }
          }
        }
      }
    }
  }
}

///|
/// `(qualified, bare)` pairs for every NAMESPACE import of `module_`
/// (`import * as core from "./core"` exposes `core.X` for each type the
/// target exposes). See `alias_namespace_import_types` in the checker.
fn graph_namespace_type_aliases(
  module_ : ParsedMtscModule,
  modules : Array[ParsedMtscModule],
  edges : Array[MtscModuleEdge],
) -> Array[(String, String, String)] {
  let out : Array[(String, String, String)] = []
  for imp in module_.module_block.imports {
    let ns = match imp.namespace_binding {
      Some(ns) => ns
      None => continue
    }
    let target = match
      find_graph_target(edges, module_.source.path, imp.module_spec) {
      Some(path) =>
        match find_graph_module(modules, path) {
          Some(t) => t
          None => continue
        }
      None => continue
    }
    graph_exposed_type_names(target, modules, edges, {}, out, ns + ".", 0)
  }
  out
}

///|
/// Collect type declarations from the caller-resolved transitive dependency
/// graph. Runtime names are deliberately not injected from these modules;
/// `graph_import_globals` remains the only path for value bindings.
fn graph_type_modules(
  module_ : ParsedMtscModule,
  modules : Array[ParsedMtscModule],
  edges : Array[MtscModuleEdge],
  keys~ : Array[String] = [],
) -> Array[@ast.TsModule] {
  let type_modules : Array[@ast.TsModule] = []
  let visited_paths : Array[String] = []
  let pending_paths : Array[String] = [module_.source.path]
  let mut cursor = 0
  while cursor < pending_paths.length() {
    let importer_path = pending_paths[cursor]
    cursor = cursor + 1
    let mut already_visited = false
    for path in visited_paths {
      if path == importer_path {
        already_visited = true
        break
      }
    }
    if already_visited {
      continue
    }
    visited_paths.push(importer_path)
    for edge in edges {
      if edge.importerPath != importer_path {
        continue
      }
      let target = match find_graph_module(modules, edge.targetPath) {
        Some(target) => target
        None => continue
      }
      type_modules.push(target.module_)
      keys.push(target.source.path)
      pending_paths.push(target.source.path)
    }
  }
  type_modules
}

///|
fn graph_import_globals(
  module_ : ParsedMtscModule,
  modules : Array[ParsedMtscModule],
  edges : Array[MtscModuleEdge],
) -> (Array[(String, @ast.TsType)], Array[String]) {
  let globals : Array[(String, @ast.TsType)] = []
  let diagnostics : Array[String] = []
  for import_ in module_.module_block.imports {
    let target_path = match
      find_graph_target(edges, module_.source.path, import_.module_spec) {
      Some(path) => path
      None => {
        if is_local_module_specifier(import_.module_spec) {
          diagnostics.push(
            "cannot resolve local module `\{import_.module_spec}`",
          )
        }
        continue
      }
    }
    let target = match find_graph_module(modules, target_path) {
      Some(target) => target
      None => {
        diagnostics.push(
          "resolved module `\{import_.module_spec}` is absent at `\{target_path}`",
        )
        continue
      }
    }
    match import_.default_binding {
      Some(local_name) =>
        match exported_value_type(target, "default", modules, edges, []) {
          Some(type_) => globals.push((local_name, type_))
          None =>
            diagnostics.push(
              "module `\{import_.module_spec}` has no default value export",
            )
        }
      None => ()
    }
    // A NAMESPACE import (`import * as Predicate`) binds no value type, so
    // `Predicate.isObject(u)` narrowed nothing — effect calls nearly every
    // guard that way. Its PREDICATE exports alone are published under an
    // `@ns:` key only the narrowing reads, so no other `ns.member` access
    // changes meaning.
    match import_.namespace_binding {
      Some(ns) =>
        for export_ in target.module_block.exports {
          match local_value_type(target.module_, export_.local_name) {
            Some(t) if is_predicate_value_type(t) => {
              // The type is written in the TARGET's scope: its bare
              // `Success` means the target's own, which in the importer is
              // reached as `ns.Success`.
              let renames : Map[String, String] = Map([])
              for i in target.module_.interfaces {
                renames[i.name] = ns + "." + i.name
              }
              for a in target.module_.type_aliases {
                renames[a.name] = ns + "." + a.name
              }
              for c in target.module_.classes {
                renames[c.name] = ns + "." + c.name
              }
              globals.push(
                (
                  "@ns:" + ns + "." + export_.export_name,
                  @checker.rename_type_refs(t, renames),
                ),
              )
            }
            _ => ()
          }
        }
      None => ()
    }
    for index, binding in import_.named_bindings {
      let type_only = import_.type_only ||
        (
          index < import_.named_type_only.length() &&
          import_.named_type_only[index]
        )
      if type_only {
        continue
      }
      let (imported_name, local_name) = binding
      match exported_value_type(target, imported_name, modules, edges, []) {
        Some(type_) => {
          globals.push((local_name, type_))
          // An imported OVERLOAD set arrives as the same `Union` of
          // signatures a union-typed value is, and the two take opposite
          // arity rules (one overload must accept, against every member).
          // Locally that is told apart by the function declaration's entry
          // in `signatures`; across a module boundary this marker says it.
          if exported_is_overload_set(target, imported_name) {
            globals.push(("@overloads:" + local_name, Any))
          }
        }
        None =>
          diagnostics.push(
            "module `\{import_.module_spec}` has no value export `\{imported_name}`",
          )
      }
    }
  }
  (globals, diagnostics)
}

///|
/// JavaScript-facing graph checker. The caller supplies modules and resolved
/// import edges; this package then performs deterministic parsing, local
/// checking, and value-level import contract propagation without reading the
/// filesystem or knowing about a particular bundler.
pub(all) struct MtscGraphIssue {
  modulePath : String
  path : String
  message : String
}

///|
/// True for a `.d.ts` whose declarations are ambient — global to the
/// whole program. A declaration file that imports or exports anything is
/// a module in its own right, so its declarations stay local to it.
fn is_ambient_script_module(module_ : ParsedMtscModule) -> Bool {
  if !module_.source.path.has_suffix(".d.ts") {
    return false
  }
  module_.module_block.imports.is_empty() &&
  module_.module_block.exports.is_empty() &&
  module_.module_block.reexports.is_empty()
}

///|
/// Value-level bindings a module declares, in the (name, type) shape the
/// checker takes for globals.
fn module_value_bindings(
  module_ : @ast.TsModule,
) -> Array[(String, @ast.TsType)] {
  let out : Array[(String, @ast.TsType)] = []
  for value in module_.values {
    out.push((value.name, value.type_))
  }
  for func in module_.funcs {
    out.push((func.name, function_value_type(func)))
  }
  for class_ in module_.classes {
    out.push((class_.name, @ast.TsType::Named(class_.name)))
  }
  for enum_ in module_.enums {
    out.push((enum_.name, @ast.TsType::Named(enum_.name)))
  }
  out
}

///|
/// Type-check a resolved module graph and return the diagnostics.
///
/// This is what a multi-file CLI wants: checking each file in isolation
/// leaves every imported type unresolvable, and a checker that cannot
/// see `type Loc = { … }` from the module that declares it either stays
/// silent on real errors or reports a mismatch between two identical
/// shapes. Resolution stays the caller's job — hand over the module
/// sources plus the import edges between them.
///
/// `check_module_graph` flattens the same information into one string
/// for the JavaScript ABI; the CLI needs it structured so it can format
/// and count diagnostics itself.
pub fn collect_module_graph_issues(
  graph : MtscModuleGraph,
) -> Array[MtscGraphIssue] {
  let parsed_modules : Array[ParsedMtscModule] = []
  let issues : Array[MtscGraphIssue] = []
  for source in graph.modules {
    match parse_graph_module(source) {
      Ok(module_) => parsed_modules.push(module_)
      Err(e) =>
        issues.push({
          modulePath: source.path,
          path: "parse",
          message: "parse error: \{e}",
        })
    }
  }
  collect_parsed_graph_issues(parsed_modules, graph.edges, issues)
  issues
}

///|
/// Check an already-parsed graph, appending to `issues`.
///
/// Split out of `collect_module_graph_issues` so the host-driven loader
/// in `service.mbt` can hand over modules it has ALREADY parsed. It has
/// to parse them to discover their imports at all, and re-parsing every
/// file to re-derive a graph the loader just built would be a third pass
/// over every source — `parse_graph_module` already costs two, one for
/// the module and one for its block.
///
/// Extraction only: the body below is what `collect_module_graph_issues`
/// ran, and that function still produces the same diagnostics in the
/// same order. `checker_wbtest.mbt` pins that, and so does the
/// `checkModuleGraph` string ABI built on top of it.
fn collect_parsed_graph_issues(
  parsed_modules : Array[ParsedMtscModule],
  edges : Array[MtscModuleEdge],
  issues : Array[MtscGraphIssue],
) -> Unit {
  // Ambient declaration files are part of every module's scope: that is
  // what makes `declare const MyGlobal: …` in an `env.d.ts` visible from
  // a source file that never imports it. Only script-shaped `.d.ts`
  // files count — one carrying its own imports / exports is a module,
  // and its declarations are private to it.
  // Every type-only ingestion below is cached per module path for the
  // duration of THIS check; a previous program's entries must not leak in.
  @checker.clear_type_module_cache()
  let ambient_globals : Array[(String, @ast.TsType)] = []
  let ambient_modules : Array[@ast.TsModule] = []
  for module_ in parsed_modules {
    if !is_ambient_script_module(module_) {
      continue
    }
    ambient_modules.push(module_.module_)
    for entry in module_value_bindings(module_.module_) {
      ambient_globals.push(entry)
    }
  }
  for module_ in parsed_modules {
    let (globals, import_diagnostics) = graph_import_globals(
      module_, parsed_modules, edges,
    )
    for entry in ambient_globals {
      globals.push(entry)
    }
    for diagnostic in import_diagnostics {
      issues.push({
        modulePath: module_.source.path,
        path: "import",
        message: diagnostic,
      })
    }
    let type_module_keys : Array[String] = []
    let type_modules = graph_type_modules(
      module_,
      parsed_modules,
      edges,
      keys=type_module_keys,
    )
    for ambient in ambient_modules {
      type_modules.push(ambient)
    }
    let namespace_type_aliases = graph_namespace_type_aliases(
      module_, parsed_modules, edges,
    )
    match
      collect_type_issues_from_module(
        module_.module_,
        globals,
        type_modules,
        namespace_type_aliases~,
        type_module_keys~,
      ) {
      Err(e) =>
        issues.push({
          modulePath: module_.source.path,
          path: "parse",
          message: "parse error: \{e}",
        })
      Ok(found) =>
        for issue in found {
          issues.push({
            modulePath: module_.source.path,
            path: issue.path,
            message: issue.message,
          })
        }
    }
  }
}

///|
pub fn check_module_graph(graph : MtscModuleGraph) -> String {
  let parsed_modules : Array[ParsedMtscModule] = []
  let diagnostics : Array[String] = []
  for source in graph.modules {
    match parse_graph_module(source) {
      Ok(module_) => parsed_modules.push(module_)
      Err(e) => diagnostics.push("\{source.path}: parse error: \{e}")
    }
  }
  for module_ in parsed_modules {
    let (globals, import_diagnostics) = graph_import_globals(
      module_,
      parsed_modules,
      graph.edges,
    )
    for diagnostic in import_diagnostics {
      diagnostics.push("\{module_.source.path}: \{diagnostic}")
    }
    let type_modules = graph_type_modules(module_, parsed_modules, graph.edges)
    let namespace_type_aliases = graph_namespace_type_aliases(
      module_,
      parsed_modules,
      graph.edges,
    )
    match
      collect_type_issues_from_module(
        module_.module_,
        globals,
        type_modules,
        namespace_type_aliases~,
      ) {
      Err(e) => diagnostics.push("\{module_.source.path}: parse error: \{e}")
      Ok(issues) =>
        for issue in issues {
          diagnostics.push("\{module_.source.path}: \{issue.message}")
        }
    }
  }
  diagnostics.join("\n")
}
