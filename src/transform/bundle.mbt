// In-memory bundler. Resolves ES-module imports between a set of
// source files keyed by virtual path and emits a single JS bundle.
//
// This is the v0 of the bundle phase. Scope:
//
//   - Bare ES `import` / `export` syntax (named, default,
//     namespace, re-export, side-effect).
//   - Virtual file system: callers pass `Map[String, String]`
//     (path → source). Path resolution is `path/posix`-style;
//     relative specifiers (`./foo`, `../bar`) resolve against the
//     importer's directory.
//   - Topological ordering of modules so each `import` sees its
//     dependency already inlined.
//   - Per-module identifier renaming so two modules can define the
//     same `name` without colliding in the bundle (`name$<n>`
//     suffix when needed).
//   - Source maps that thread through every module: each module's
//     mappings keep pointing to the right source file via the v3
//     `sources` array.
//
// What's intentionally *out* of scope here:
//
//   - Tree-shaking / dead-import pruning (comes later via the
//     type-aware mangler).
//   - CommonJS / dynamic `import()` resolution (only static
//     `import …` lines are followed).
//   - Asset (non-JS) loaders.
//
// Public entrypoint:
//
//   `bundle_modules(files, entry, opts) -> Result[BundleOutput, String]`

///|
pub(all) struct BundleOptions {
  // Base JSX config for every module; per-file `@jsxImportSource`
  // pragmas overlay on top of this as the per-module transform runs.
  jsx : JsxConfig
  // When `true`, the result includes a v3 source map covering every
  // module in the bundle.
  with_sourcemap : Bool
  // When `true`, run tree shaking on every module before emit. Roots
  // are computed cross-module: each module starts from the named
  // bindings other live modules import from it (plus the entry's own
  // top-level keepers / non-decl stmts).
  tree_shake : Bool
  // Optional mangler config. When set, every module's block runs
  // through the mangler before emit, and the property-rename map is
  // built from the *union* of every module's property keys so a
  // shared `obj.foo` collapses to the same short name everywhere.
  mangle : ManglerConfig?
  // When `true` *and* `mangle` is set, parse each module a second
  // time to gather the declaration tables and feed them through
  // `auto_reserve_from_bundle`. The resulting reserved-set / reserved-
  // properties additions layer on top of the user's `mangle` config
  // before the mangler runs. Costs a second per-module parse.
  auto_reserve : Bool
  // When `true`, drop class methods (and instance accessors) whose
  // name is never referenced anywhere in the bundle. Runs after
  // tree shaking and before mangling so the mangler doesn't waste a
  // short name on a method that's about to be deleted.
  drop_unused_methods : Bool
}

///|
pub fn BundleOptions::default() -> BundleOptions {
  {
    jsx: JsxConfig::default(),
    with_sourcemap: false,
    tree_shake: false,
    mangle: None,
    auto_reserve: false,
    drop_unused_methods: false,
  }
}

///|
pub(all) struct BundleOutput {
  // The concatenated JavaScript output.
  js : String
  // Optional v3 source-map JSON document, when
  // `BundleOptions.with_sourcemap` was `true`.
  sourcemap : String?
  // Modules included in the bundle, in dependency order. First entry
  // is the deepest dependency; last is the entry.
  modules : Array[String]
}

// ---------------------------------------------------------------------------
// Module graph
// ---------------------------------------------------------------------------

///|
priv struct ModuleNode {
  // Virtual path of the module.
  path : String
  // Original source text (kept for sourcesContent).
  source : String
  // Parsed module body — runtime stmts after JSX lowering.
  mut block : @ast.TsBlock
  // Import specifiers from this module, mapped to the *absolute*
  // resolved path (`Map[specifier, resolved_path]`).
  resolved_imports : Map[String, String]
  // Bare ESM import metadata (for the dependency graph): list of
  // (specifier, default_binding?, named_bindings, namespace_binding?,
  // type_only).
  import_decls : Array[@ast.TsImportDecl]
  // Top-level export specs (`export { x, y as z }`, `export const x = …`).
  // Drives tree shaking: every `local_name` here is a root for the
  // module's own pass.
  exports : Array[@ast.TsExportSpec]
  // Module-level declaration tables — `interface` / `class` /
  // `type` / function-signature metadata that the auto-reserve
  // pass walks. Only populated when `BundleOptions.auto_reserve`
  // is on; the second parse is a measurable cost.
  module_decls : @ast.TsModule?
  // The original parsed `TsModuleBlock`. Needed for the auto-reserve
  // walk so we can pass the *entry*'s block (with its post-JSX-lower
  // reexports list intact) into `auto_reserve_from_bundle`.
  module_block : @ast.TsModuleBlock?
}

// ---------------------------------------------------------------------------
// Path resolution (posix-style)
// ---------------------------------------------------------------------------

///|
/// Resolve `specifier` relative to `from_path`. Only `./` / `../` /
/// rooted (`/`) specifiers are handled here; bare specifiers (e.g.
/// `react`) fall through to the caller's external resolver.
fn resolve_relative(from_path : String, specifier : String) -> String? {
  if specifier.has_prefix("/") {
    return Some(normalize_path(specifier))
  }
  if !specifier.has_prefix("./") && !specifier.has_prefix("../") {
    return None
  }
  let dir = dirname(from_path)
  let combined = if dir == "" { specifier } else { dir + "/" + specifier }
  Some(normalize_path(combined))
}

///|
fn dirname(path : String) -> String {
  match path.rev_find("/") {
    Some(idx) => path.substring(start=0, end=idx).to_string()
    None => ""
  }
}

///|
/// Try the literal path, then `.ts`, `.tsx`, `.js`, `.mjs`, then
/// `<path>/index.ts(x)`. Returns the first hit, or the original
/// path when nothing matched (caller will then surface the
/// "module not in vfs" error with the user's spec preserved).
fn resolve_with_extensions(
  files : Map[String, String],
  base : String,
) -> String {
  if files.contains(base) {
    return base
  }
  let exts = [".ts", ".tsx", ".js", ".mjs", ".jsx"]
  for ext in exts {
    let cand = base + ext
    if files.contains(cand) {
      return cand
    }
  }
  for ext in exts {
    let cand = base + "/index" + ext
    if files.contains(cand) {
      return cand
    }
  }
  base
}

///|
fn normalize_path(path : String) -> String {
  let parts : Array[String] = []
  for part in path.split("/") {
    let p = part.to_string()
    if p == "" || p == "." {
      continue
    }
    if p == ".." {
      if parts.length() > 0 && parts[parts.length() - 1] != ".." {
        let _ = parts.pop()
      } else {
        parts.push("..")
      }
      continue
    }
    parts.push(p)
  }
  let leading = if path.has_prefix("/") { "/" } else { "" }
  leading + parts.join("/")
}

// ---------------------------------------------------------------------------
// Bundle entrypoint
// ---------------------------------------------------------------------------

///|
/// Resolve every import in `files` starting from `entry`, parse each
/// reachable module, transform JSX, and emit a single JS bundle in
/// dependency order. Returns the bundled JS and an optional v3 source
/// map when `opts.with_sourcemap` is set.
///
/// `files` is a virtual filesystem keyed by absolute-ish path. The
/// path scheme is purely textual — `bundle_modules` doesn't touch the
/// real filesystem. Relative imports (`./foo`, `../bar`) resolve
/// against the importer's directory via posix-style joining.
pub fn bundle_modules(
  files : Map[String, String],
  entry : String,
  opts : BundleOptions,
) -> Result[BundleOutput, String] {
  let modules : Map[String, ModuleNode] = {}
  // External (bare specifier) imports we want to re-emit at the top
  // of the bundle so the consumer's loader / browser handles them.
  let external_imports : Array[@ast.TsImportDecl] = []
  let external_seen : Map[String, Bool] = {}
  let need_decls = opts.auto_reserve && opts.mangle is Some(_)
  match
    load_module_graph(
      files, entry, modules, external_imports, external_seen, need_decls,
    ) {
    Ok(_) => ()
    Err(e) => return Err(e)
  }
  let order = topological_order(modules, entry)
  if opts.tree_shake {
    tree_shake_bundle(modules, entry)
  }
  if opts.drop_unused_methods {
    drop_unused_methods_bundle(modules, order, opts.mangle)
  }
  match opts.mangle {
    Some(cfg) => {
      let final_cfg = if opts.auto_reserve {
        compute_auto_reserve(modules, entry, cfg)
      } else {
        cfg
      }
      mangle_bundle(modules, order, final_cfg)
    }
    None => ()
  }
  let e = Emitter::new()
  if opts.with_sourcemap {
    e.smap = Some(SourceMapBuilder::new())
  }
  // Top-of-bundle: re-emit external imports verbatim in source
  // order. Internal imports are dropped because their bindings will
  // be in scope after concatenation.
  for ext in external_imports {
    emit_import_decl(e, ext)
    e.nl()
  }
  // Inline every internal module as its own `// === <path> ===`
  // section so debugging the bundle stays manageable.
  let sources : Array[String] = []
  let sources_content : Array[String] = []
  let module_paths : Array[String] = []
  for i, path in order {
    let m = match modules.get(path) {
      Some(node) => node
      None => continue
    }
    e.write("// ===== ")
    e.write(path)
    e.write(" =====")
    e.nl()
    let _ = i
    sources.push(path)
    sources_content.push(m.source)
    module_paths.push(path)
    // Per-module sourcemap: set the line index + map source id to
    // the module's slot in `sources`.
    if opts.with_sourcemap {
      e.line_index = LineIndex::new(m.source)
      match e.smap {
        Some(b) => b.set_current_source(sources.length() - 1)
        None => ()
      }
    }
    for j, stmt in m.block.stmts {
      if opts.with_sourcemap && j < m.block.stmt_positions.length() {
        let src_pos = e.line_index.position(m.block.stmt_positions[j])
        e.mark(src_pos)
      }
      emit_stmt(e, stmt)
      e.nl()
    }
  }
  let sm_json : String? = match e.smap {
    Some(b) =>
      Some(b.to_json_multi(sources, sources_content, output_path="bundle.js"))
    None => None
  }
  Ok({ js: e.to_string(), sourcemap: sm_json, modules: module_paths })
}

///|
fn load_module_graph(
  files : Map[String, String],
  path : String,
  modules : Map[String, ModuleNode],
  external_imports : Array[@ast.TsImportDecl],
  external_seen : Map[String, Bool],
  need_decls : Bool,
) -> Result[Unit, String] {
  if modules.contains(path) {
    return Ok(())
  }
  let source = match files.get(path) {
    Some(s) => s
    None => return Err("module not in vfs: \{path}")
  }
  // Parse as a module block so we get imports + the runtime stmt
  // stream. JSX lowering happens here too so the per-module pragma
  // / config gets resolved against the right source text.
  let parser = @parser.Parser::from_source(source)
  let mb = match (try? parser.parse_module_block()) {
    Ok(b) => b
    Err(e) => return Err("parse \{path}: \{e}")
  }
  // When auto-reserve is on, also parse the lower-level `TsModule`
  // to surface declaration tables (`interfaces`, `classes`, etc.).
  // The two parses are independent; the parser keeps no global
  // state between calls.
  let module_decls : @ast.TsModule? = if need_decls {
    let parser2 = @parser.Parser::from_source(source)
    match (try? parser2.parse_module()) {
      Ok(m) => Some(m)
      Err(e) => return Err("parse decls \{path}: \{e}")
    }
  } else {
    None
  }
  // Reuse the per-file JSX pragma extractor so each module honors
  // its own `/** @jsxImportSource ... */` etc.
  let jsx_cfg = extract_jsx_pragmas(source, JsxConfig::default())
  let (lowered, _refs) = lower_block_with_runtime_imports(jsx_cfg, mb.block)
  // Walk imports, recurse into relative paths, accumulate bare ones.
  let resolved : Map[String, String] = {}
  for imp in mb.imports {
    if imp.type_only {
      // type-only imports don't survive into JS — leave them out.
      continue
    }
    match resolve_relative(path, imp.module_spec) {
      Some(base_dep) => {
        // Probe extensions in order until the vfs has the file.
        let dep_path = resolve_with_extensions(files, base_dep)
        resolved[imp.module_spec] = dep_path
        match
          load_module_graph(
            files,
            dep_path,
            modules,
            external_imports,
            external_seen,
            need_decls,
          ) {
          Ok(_) => ()
          Err(e) => return Err(e)
        }
      }
      None => {
        // Bare specifier — emit verbatim at the bundle top.
        let key = imp.module_spec +
          ":" +
          (match imp.default_binding {
            Some(s) => s
            None => ""
          })
        if !external_seen.contains(key) {
          external_seen[key] = true
          external_imports.push(imp)
        }
      }
    }
  }
  modules[path] = {
    path,
    source,
    block: lowered,
    resolved_imports: resolved,
    import_decls: mb.imports,
    exports: mb.exports,
    module_decls,
    module_block: Some(mb),
  }
  Ok(())
}

///|
/// Compute per-module root sets and shake each module in place.
///
/// Root computation:
///   - Entry module: every `local_name` from its `exports`. Stmts
///     without a single-Ident binding (side effects, control flow,
///     etc.) survive `tree_shake_block` unconditionally.
///   - Non-entry modules: every `imported` name that any other
///     module pulls in via `import { x } from "./this"`. Default and
///     namespace imports drag in everything (we can't tell which
///     bindings they touch without full resolution), so we fall back
///     to "keep every export" when those forms are seen.
fn tree_shake_bundle(
  modules : Map[String, ModuleNode],
  entry : String,
) -> Unit {
  // Map: target module path -> set of root names to preserve there.
  let roots_per_module : Map[String, Map[String, Bool]] = {}
  fn root_for(path : String) -> Map[String, Bool] {
    match roots_per_module.get(path) {
      Some(m) => m
      None => {
        let m : Map[String, Bool] = {}
        roots_per_module[path] = m
        m
      }
    }
  }

  // Seed the entry's roots with its own exports.
  match modules.get(entry) {
    Some(entry_node) => {
      let r = root_for(entry)
      for spec in entry_node.exports {
        r[spec.local_name] = true
      }
    }
    None => ()
  }
  // Walk every module's imports → propagate roots into the source
  // module. We treat default / namespace imports as "keep everything"
  // since we don't track which members get touched.
  for kv in modules {
    let (_, node) = kv
    for imp in node.import_decls {
      if imp.type_only {
        continue
      }
      let dep_path = match node.resolved_imports.get(imp.module_spec) {
        Some(p) => p
        None => continue
      }
      let dep_node = match modules.get(dep_path) {
        Some(d) => d
        None => continue
      }
      let dep_roots = root_for(dep_path)
      let keep_all = imp.default_binding is Some(_) ||
        imp.namespace_binding is Some(_)
      if keep_all {
        for spec in dep_node.exports {
          dep_roots[spec.local_name] = true
        }
      } else {
        for nb in imp.named_bindings {
          // nb.0 is the imported name as it appears in the source
          // module — that's the root we want to keep alive there.
          dep_roots[nb.0] = true
        }
      }
    }
  }
  // Shake each module's block in place against its root set.
  for kv in modules {
    let (path, node) = kv
    let roots_arr : Array[String] = []
    match roots_per_module.get(path) {
      Some(m) =>
        for r in m {
          roots_arr.push(r.0)
        }
      None => ()
    }
    node.block = tree_shake_block(node.block, roots_arr)
  }
}

///|
/// Run `auto_reserve_from_bundle` against the parsed declaration
/// tables of every loaded module, anchored on the entry module's
/// `TsModuleBlock`. Returns the user-supplied config augmented with
/// the derived reserved names / properties. If anything required
/// (entry block / decls) is missing, returns `base` unchanged so
/// the caller still gets a sensible default.
fn compute_auto_reserve(
  modules : Map[String, ModuleNode],
  entry : String,
  base : ManglerConfig,
) -> ManglerConfig {
  let entry_node = match modules.get(entry) {
    Some(n) => n
    None => return base
  }
  let entry_block = match entry_node.module_block {
    Some(b) => b
    None => return base
  }
  let all_decls : Array[@ast.TsModule] = []
  for kv in modules {
    let (_, n) = kv
    match n.module_decls {
      Some(m) => all_decls.push(m)
      None => ()
    }
  }
  if all_decls.length() == 0 {
    return base
  }
  auto_reserve_from_bundle(entry_block, all_decls, base)
}

///|
/// Run class-method DCE across the bundle's blocks. The reference
/// set is global (one method install is alive iff its name is read
/// anywhere across modules), so all blocks see the same surface.
/// Any `reserved_properties` the caller listed on `mangle` are
/// added to the global set so explicit keep-lists protect methods
/// even if no code reads them.
fn drop_unused_methods_bundle(
  modules : Map[String, ModuleNode],
  order : Array[String],
  mangle_cfg : ManglerConfig?,
) -> Unit {
  let blocks : Array[@ast.TsBlock] = []
  let paths : Array[String] = []
  for path in order {
    match modules.get(path) {
      Some(n) => {
        blocks.push(n.block)
        paths.push(path)
      }
      None => ()
    }
  }
  let extra : Array[String] = match mangle_cfg {
    Some(cfg) => cfg.reserved_properties
    None => []
  }
  let pruned = drop_unused_methods_in_blocks(blocks, extra)
  for i, p in paths {
    match modules.get(p) {
      Some(n) => n.block = pruned[i]
      None => ()
    }
  }
}

///|
/// Drive a single mangle pass over every module's block with a
/// shared property-rename map. Identifier renaming still happens
/// per-module — locals don't escape — but property keys collapse
/// consistently across the whole bundle.
fn mangle_bundle(
  modules : Map[String, ModuleNode],
  order : Array[String],
  cfg : ManglerConfig,
) -> Unit {
  // Collect blocks in topological order so the mangled output array
  // lines up with the order we'll write them back in.
  let blocks : Array[@ast.TsBlock] = []
  let paths : Array[String] = []
  for path in order {
    match modules.get(path) {
      Some(n) => {
        blocks.push(n.block)
        paths.push(path)
      }
      None => ()
    }
  }
  let mangled = mangle_blocks_together(blocks, cfg)
  for i, p in paths {
    match modules.get(p) {
      Some(n) => n.block = mangled[i]
      None => ()
    }
  }
}

///|
/// Build a depth-first dependency order for the entry module: deepest
/// dependency emits first, the entry emits last. Cycles short-circuit
/// at the first repeat to keep emit terminating.
fn topological_order(
  modules : Map[String, ModuleNode],
  entry : String,
) -> Array[String] {
  let order : Array[String] = []
  let visited : Map[String, Bool] = {}
  let stack : Map[String, Bool] = {}
  fn visit(path : String) -> Unit {
    if visited.contains(path) {
      return
    }
    if stack.contains(path) {
      // Cyclic — break here. The module won't appear twice.
      return
    }
    stack[path] = true
    match modules.get(path) {
      Some(node) =>
        for entry_ in node.resolved_imports {
          let (_, dep) = entry_
          visit(dep)
        }
      None => ()
    }
    let _ = stack.remove(path)
    visited[path] = true
    order.push(path)
  }

  visit(entry)
  order
}

// ---------------------------------------------------------------------------
// Import-decl emit (only used for the bundle-top external imports)
// ---------------------------------------------------------------------------

///|
fn emit_import_decl(e : Emitter, decl : @ast.TsImportDecl) -> Unit {
  e.write("import ")
  let mut wrote_something = false
  match decl.default_binding {
    Some(name) => {
      e.write(name)
      wrote_something = true
    }
    None => ()
  }
  match decl.namespace_binding {
    Some(name) => {
      if wrote_something {
        e.write(", ")
      }
      e.write("* as ")
      e.write(name)
      wrote_something = true
    }
    None => ()
  }
  if decl.named_bindings.length() > 0 {
    if wrote_something {
      e.write(", ")
    }
    e.write("{ ")
    for i, b in decl.named_bindings {
      if i > 0 {
        e.write(", ")
      }
      // Per-specifier type-only modifier — preserved on the way out
      // for tools that consume the bundle through `tsc --noEmit`.
      if i < decl.named_type_only.length() && decl.named_type_only[i] {
        e.write("type ")
      }
      if b.0 == b.1 {
        e.write(b.0)
      } else {
        e.write(b.0)
        e.write(" as ")
        e.write(b.1)
      }
    }
    e.write(" }")
    wrote_something = true
  }
  if !wrote_something && !decl.side_effect_only {
    // `import "x";` shape happens when the decl is purely a
    // side-effect import. Fall through to the from clause.
  }
  if wrote_something {
    e.write(" from ")
  }
  e.write("\"")
  e.write(decl.module_spec)
  e.write("\"")
  if decl.attributes.length() > 0 {
    e.write(" with { ")
    for i, attr in decl.attributes {
      if i > 0 {
        e.write(", ")
      }
      e.write(attr.0)
      e.write(": \"")
      e.write(attr.1)
      e.write("\"")
    }
    e.write(" }")
  }
  e.write(";")
}
