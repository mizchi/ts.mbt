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
  // When `true`, run the immutability analysis: top-level
  // `const X = { … }` bindings whose name is only ever read as a
  // property receiver get their primitive-valued reads substituted
  // with the literal, and the source decl is dropped if no
  // references remain.
  inline_immutable : Bool
  // When `true`, run constant folding + dead-branch elimination
  // across every module. Pairs naturally with `inline_immutable`:
  // once `cfg.mode` becomes `"prod"`, `cfg.mode === "dev"` folds
  // to `false` and `if (false) …` collapses entirely.
  fold_constants : Bool
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
    inline_immutable: false,
    fold_constants: false,
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
  // module's own pass. The collision-resolver may rewrite the
  // `local_name` side when a top-level binding gets renamed to
  // avoid colliding with a same-named binding in another module.
  mut exports : Array[@ast.TsExportSpec]
  // Re-exports of bindings from other modules. Each entry carries
  // the source module specifier and the names bridged through.
  // Drives tree shaking on the source module: `export { foo }
  // from "./y"` must keep `foo` alive in `./y`.
  reexports : Array[@ast.TsReExportSpec]
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
  // Mid-load marker so circular imports don't recurse forever.
  // `modules[path] = …` only happens at the very end of
  // `load_module_graph`, so the standard "already in modules"
  // guard fires too late when `a → b → a` loops back into `a`
  // before `a`'s own load finishes.
  let visiting : Map[String, Bool] = {}
  // `auto_reserve` and the type-aware `inline_immutable` relaxation
  // (passing a const to a `ReadonlyArray<T>` / `Readonly<T>`
  // parameter) both require the second parse for declaration tables.
  let need_decls = (opts.auto_reserve && opts.mangle is Some(_)) ||
    opts.inline_immutable
  match
    load_module_graph(
      files, entry, modules, external_imports, external_seen, visiting, need_decls,
    ) {
    Ok(_) => ()
    Err(e) => return Err(e)
  }
  let order = topological_order(modules, entry)
  // Synthesize import-alias decls (`const local = __export_default__N;`
  // and similar) as the first stmts of each module's block. Without
  // this the aliases would only exist at emit-time, invisible to
  // tree-shake / inline / orphan-cleanup, and any side that depends
  // on tracking the alias's reference would silently drop the
  // backing binding.
  synthesize_import_aliases(modules, order)
  // Resolve top-level identifier collisions across modules. When
  // two modules each declare `function helper(...)` at top level,
  // concatenating their stmts into one global scope produces
  // `Identifier 'helper' has already been declared`. Rename the
  // later occurrence to `helper$1` (etc.) and rewrite every
  // reference within that module. Each module's `exports` table is
  // updated in lockstep so the import-alias emit stays correct.
  resolve_bundle_collisions(modules, order)
  if opts.tree_shake {
    tree_shake_bundle(modules, entry)
  }
  // Inline + fold form a natural fixed point: each fold round can
  // create new constant subtrees that the next inline / fold can
  // simplify further. Iterate until the size stops changing, with
  // a cap so a pathological case can't loop forever.
  if opts.inline_immutable || opts.fold_constants {
    let max_rounds = 4
    let mut prev_size = -1
    for _ in 0..<max_rounds {
      if opts.inline_immutable {
        inline_immutable_bundle(modules, order)
      }
      if opts.fold_constants {
        fold_constants_bundle(modules, order)
      }
      let size = bundle_block_size(modules, order)
      if size == prev_size {
        break
      }
      prev_size = size
    }
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
    // Import aliases are now synthesized into the module's block
    // as the first stmts (see `synthesize_import_aliases`), so the
    // emit loop just walks `m.block.stmts` and the aliases come
    // out in the right order.
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
  visiting : Map[String, Bool],
  need_decls : Bool,
) -> Result[Unit, String] {
  if modules.contains(path) || visiting.contains(path) {
    return Ok(())
  }
  visiting[path] = true
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
  // First strip / lower TS-only constructs (enums, overload
  // signatures) into the runtime stmt stream so the optimizer
  // doesn't see surprise sentinel decls.
  let desugared = ts_desugar_block(mb.block, mb.enums, mb.namespaces)
  let (lowered, jsx_refs) = lower_block_with_runtime_imports(jsx_cfg, desugared)
  // Synthesize the JSX-runtime import when lowering introduced
  // references to `jsx` / `jsxs` / `Fragment` / etc. The import
  // specifier is `<jsx_cfg.import_source>/jsx-runtime` (e.g.
  // `react/jsx-runtime` for stock React, `./shim/jsx-runtime` for
  // a vendored shim). After this synthesis the names flow through
  // the regular import-alias pipeline.
  let mut effective_imports = mb.imports
  if jsx_refs.length() > 0 {
    let named : Array[(String, String)] = []
    let type_only_flags : Array[Bool] = []
    for n in jsx_refs {
      named.push((n, n))
      type_only_flags.push(false)
    }
    let jsx_import : @ast.TsImportDecl = {
      module_spec: jsx_cfg.import_source + "/jsx-runtime",
      default_binding: None,
      namespace_binding: None,
      named_bindings: named,
      named_type_only: type_only_flags,
      side_effect_only: false,
      type_only: false,
      attributes: [],
    }
    let merged : Array[@ast.TsImportDecl] = [jsx_import]
    for imp in effective_imports {
      merged.push(imp)
    }
    effective_imports = merged
  }
  // Walk imports, recurse into relative paths, accumulate bare ones.
  let resolved : Map[String, String] = {}
  for imp in effective_imports {
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
            visiting,
            need_decls,
          ) {
          Ok(_) => ()
          Err(e) => return Err(e)
        }
      }
      None => {
        // Bare specifier (e.g. `react/jsx-runtime`). Two options:
        //   1. The VFS has a file at that path → treat as a
        //      vendored bare dep and bundle it.
        //   2. Otherwise → external peer dep, re-emit verbatim
        //      at the bundle top.
        let probed = resolve_with_extensions(files, imp.module_spec)
        if files.contains(probed) {
          resolved[imp.module_spec] = probed
          match
            load_module_graph(
              files,
              probed,
              modules,
              external_imports,
              external_seen,
              visiting,
              need_decls,
            ) {
            Ok(_) => ()
            Err(e) => return Err(e)
          }
        } else {
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
  }
  // `export { x } from "./y"` and `export * from "./y"` also pull
  // `./y` into the bundle — without this, a chain of re-exports
  // would silently drop the source modules and leave the
  // re-exported bindings dangling.
  for re in mb.reexports {
    if re.type_only {
      continue
    }
    match resolve_relative(path, re.module_spec) {
      Some(base_dep) => {
        let dep_path = resolve_with_extensions(files, base_dep)
        resolved[re.module_spec] = dep_path
        match
          load_module_graph(
            files,
            dep_path,
            modules,
            external_imports,
            external_seen,
            visiting,
            need_decls,
          ) {
          Ok(_) => ()
          Err(e) => return Err(e)
        }
      }
      None => ()
    }
  }
  modules[path] = {
    path,
    source,
    block: lowered,
    resolved_imports: resolved,
    import_decls: effective_imports,
    exports: mb.exports,
    reexports: mb.reexports,
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
  // Propagate re-exports as roots transitively. `c.ts` saying
  // `export { foo } from "./b"` means `foo` has to stay alive in
  // `./b`; if `./b` itself re-exports `foo` from `./a`, the next
  // round propagates `foo` into `./a`. Iterate until the root set
  // stops growing.
  let mut changed = true
  while changed {
    changed = false
    for kv in modules {
      let (path, node) = kv
      let my_roots = match roots_per_module.get(path) {
        Some(m) => m
        None => continue
      }
      for re in node.reexports {
        if re.type_only {
          continue
        }
        let dep_path = match node.resolved_imports.get(re.module_spec) {
          Some(p) => p
          None => continue
        }
        let dep_node = match modules.get(dep_path) {
          Some(d) => d
          None => continue
        }
        let dep_roots = root_for(dep_path)
        match re.kind {
          Named(specs) =>
            // Each entry is (local_in_source_exports, exported_name_here).
            // `local` is the *exported name* on the dep — e.g.
            // `default` for `export { default as mitt } from "./x"`.
            // Tree-shake's per-module roots match against actual
            // binding names, so we have to resolve `local` to the
            // dep's `local_name` slot in its exports table.
            for s in specs {
              let local = s.0
              let exported = s.1
              if !my_roots.contains(exported) {
                continue
              }
              // Resolve the dep's binding name for `local`.
              let mut dep_local : String? = None
              for ds in dep_node.exports {
                if ds.export_name == local {
                  dep_local = Some(ds.local_name)
                  break
                }
              }
              let target_name = match dep_local {
                Some(n) => n
                // Fallback: when the dep doesn't directly export
                // `local`, the chain probably continues through
                // another re-export. Add the raw name and let the
                // fixpoint pick it up via the next iteration when
                // the dep itself re-exports.
                None => local
              }
              if !dep_roots.contains(target_name) {
                dep_roots[target_name] = true
                changed = true
              }
            }
          All =>
            // `export * from "./y"` — every export of `./y` becomes
            // visible here. Mark every dep export as a root.
            for spec in dep_node.exports {
              if !dep_roots.contains(spec.local_name) {
                dep_roots[spec.local_name] = true
                changed = true
              }
            }
          Namespace(_) =>
            // `export * as ns from "./y"` — `ns` is opaque from the
            // outside, so we have to keep every export of `./y`.
            for spec in dep_node.exports {
              if !dep_roots.contains(spec.local_name) {
                dep_roots[spec.local_name] = true
                changed = true
              }
            }
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
/// Total number of top-level stmts across every module's block —
/// the cheap proxy the fixed-point loop uses to detect that
/// inline / fold rounds have converged. Subtree depth and per-stmt
/// shape don't matter; once the stmt count stops dropping there's
/// no more dead branch to eliminate.
fn bundle_block_size(
  modules : Map[String, ModuleNode],
  order : Array[String],
) -> Int {
  let mut total = 0
  for path in order {
    match modules.get(path) {
      Some(n) => total = total + n.block.stmts.length()
      None => ()
    }
  }
  total
}

///|
/// Resolve an exported name on a module to the local binding name
/// in whichever module *actually* declares it. Walks re-export
/// chains (`export { x as y } from "./z"`) through as many hops
/// as needed. Returns `None` if the name isn't exported at all or
/// the chain dead-ends at an unresolved external dep.
fn resolve_exported_local(
  modules : Map[String, ModuleNode],
  module_path : String,
  exported : String,
) -> String? {
  // Cycle guard — symmetric to the load-graph visiting set; a
  // self-referencing re-export chain shouldn't recurse forever.
  let visiting : Map[String, Bool] = {}
  resolve_exported_local_with_visit(modules, module_path, exported, visiting)
}

///|
fn resolve_exported_local_with_visit(
  modules : Map[String, ModuleNode],
  module_path : String,
  exported : String,
  visiting : Map[String, Bool],
) -> String? {
  if visiting.contains(module_path) {
    return None
  }
  visiting[module_path] = true
  let node = match modules.get(module_path) {
    Some(n) => n
    None => return None
  }
  for spec in node.exports {
    if spec.export_name == exported {
      return Some(spec.local_name)
    }
  }
  for re in node.reexports {
    if re.type_only {
      continue
    }
    let dep_path = match node.resolved_imports.get(re.module_spec) {
      Some(p) => p
      None => continue
    }
    match re.kind {
      Named(specs) =>
        for s in specs {
          let imported = s.0
          let renamed = s.1
          if renamed == exported {
            return resolve_exported_local_with_visit(
              modules, dep_path, imported, visiting,
            )
          }
        }
      All =>
        // `export * from "./x"` — every export of `./x` becomes
        // visible. Look up `exported` on the source.
        match
          resolve_exported_local_with_visit(
            modules, dep_path, exported, visiting,
          ) {
          Some(name) => return Some(name)
          None => ()
        }
      Namespace(_) => ()
    }
  }
  None
}

///|
/// Populate `out` with the (export_name, source_local_name) pairs
/// reachable from `module_path` — used by namespace imports
/// (`import * as ns from "./y"`) to know what to stuff into the
/// synthesized object literal. Resolves re-export chains.
fn collect_visible_exports(
  modules : Map[String, ModuleNode],
  module_path : String,
  out : Map[String, String],
) -> Unit {
  let visiting : Map[String, Bool] = {}
  collect_visible_exports_with_visit(modules, module_path, out, visiting)
}

///|
fn collect_visible_exports_with_visit(
  modules : Map[String, ModuleNode],
  module_path : String,
  out : Map[String, String],
  visiting : Map[String, Bool],
) -> Unit {
  if visiting.contains(module_path) {
    return
  }
  visiting[module_path] = true
  let node = match modules.get(module_path) {
    Some(n) => n
    None => return
  }
  for spec in node.exports {
    if !out.contains(spec.export_name) {
      out[spec.export_name] = spec.local_name
    }
  }
  for re in node.reexports {
    if re.type_only {
      continue
    }
    let dep_path = match node.resolved_imports.get(re.module_spec) {
      Some(p) => p
      None => continue
    }
    match re.kind {
      Named(specs) =>
        for s in specs {
          let imported = s.0
          let renamed = s.1
          match
            resolve_exported_local_with_visit(
              modules, dep_path, imported, {},
            ) {
            Some(source_local) =>
              if !out.contains(renamed) {
                out[renamed] = source_local
              }
            None => ()
          }
        }
      All =>
        collect_visible_exports_with_visit(modules, dep_path, out, visiting)
      Namespace(_) => ()
    }
  }
}

///|
/// Prepend each module's block with the alias decls that wire up
/// the importer's local names to the dep's exported bindings:
///
///   `import foo from "./y"`        → `const foo = __export_default__N;`
///   `import { x as y } from "./y"` → `const y = x;`
///   `import * as ns from "./y"`    → `const ns = { x: x, y: y, … };`
///
/// Without these decls in the AST, downstream passes
/// (tree-shake / inline-immutable / orphan-cleanup) can't see the
/// reference from the importer to the dep's bindings and would
/// silently drop them.
fn synthesize_import_aliases(
  modules : Map[String, ModuleNode],
  order : Array[String],
) -> Unit {
  for path in order {
    let m = match modules.get(path) {
      Some(n) => n
      None => continue
    }
    let aliases : Array[@ast.TsStmt] = []
    for imp in m.import_decls {
      if imp.type_only {
        continue
      }
      let dep_path = match m.resolved_imports.get(imp.module_spec) {
        Some(p) => p
        None => continue
      }
      let dep = match modules.get(dep_path) {
        Some(d) => d
        None => continue
      }
      // Default import alias — `import foo from "./y"` →
      // `const foo = <dep's default local>;`. The default export
      // local name was either declared directly in the dep
      // (`export default …` → `__export_default__N`) or re-exported
      // through a chain that the resolver follows.
      match imp.default_binding {
        Some(local) => {
          match resolve_exported_local(modules, dep_path, "default") {
            Some(dep_name) =>
              if dep_name != local {
                aliases.push(
                  @ast.TsStmt::Const(
                    @ast.TsBinding::Ident(local),
                    @ast.TsType::Any,
                    @ast.TsExpr::Var(dep_name),
                  ),
                )
              }
            None => ()
          }
        }
        None => ()
      }
      // Named import alias — `import { x as y } from "./y"` →
      // `const y = <whatever ./y exports as 'x'>`. Resolve through
      // re-export chains so a facade's rename re-export
      // (`export { internalName as publicName } from "./a"`)
      // ends up emitting `const publicName = internalName;`.
      for nb in imp.named_bindings {
        let imported = nb.0
        let local = nb.1
        // Special case: `export * as ns from "./a"` — the source
        // module exports the *name* `ns` as a freshly-built object
        // wrapping every export of `./a`. Detect by looking at
        // the dep's reexports.
        let mut namespace_target : String? = None
        for re in dep.reexports {
          if re.type_only {
            continue
          }
          match re.kind {
            Namespace(n) =>
              if n == imported && namespace_target is None {
                namespace_target = Some(re.module_spec)
              }
            _ => ()
          }
        }
        match namespace_target {
          Some(spec) => {
            let inner_dep_path = match dep.resolved_imports.get(spec) {
              Some(p) => p
              None => continue
            }
            let names : Map[String, String] = {}
            collect_visible_exports(modules, inner_dep_path, names)
            let entries : Array[(String, @ast.TsExpr)] = []
            for kv in names {
              entries.push((kv.0, @ast.TsExpr::Var(kv.1)))
            }
            aliases.push(
              @ast.TsStmt::Const(
                @ast.TsBinding::Ident(local),
                @ast.TsType::Any,
                @ast.TsExpr::ObjectLit(entries),
              ),
            )
          }
          None =>
            match resolve_exported_local(modules, dep_path, imported) {
              Some(dep_name) =>
                if dep_name != local {
                  aliases.push(
                    @ast.TsStmt::Const(
                      @ast.TsBinding::Ident(local),
                      @ast.TsType::Any,
                      @ast.TsExpr::Var(dep_name),
                    ),
                  )
                }
              // Couldn't resolve through re-exports — assume the
              // dep's local matches the imported name and only
              // emit an alias on rename.
              None =>
                if imported != local {
                  aliases.push(
                    @ast.TsStmt::Const(
                      @ast.TsBinding::Ident(local),
                      @ast.TsType::Any,
                      @ast.TsExpr::Var(imported),
                    ),
                  )
                }
            }
        }
      }
      // Namespace import: `const ns = { x: x, y: y, … };`. Names
      // include both the dep's direct exports AND anything reachable
      // via re-exports (so `import * as ns from "./facade"` gets the
      // members `./facade` re-exports too).
      match imp.namespace_binding {
        Some(local) => {
          let names : Map[String, String] = {}
          collect_visible_exports(modules, dep_path, names)
          let entries : Array[(String, @ast.TsExpr)] = []
          for kv in names {
            let export_name = kv.0
            let source_local = kv.1
            entries.push((export_name, @ast.TsExpr::Var(source_local)))
          }
          aliases.push(
            @ast.TsStmt::Const(
              @ast.TsBinding::Ident(local),
              @ast.TsType::Any,
              @ast.TsExpr::ObjectLit(entries),
            ),
          )
        }
        None => ()
      }
    }
    if aliases.length() == 0 {
      continue
    }
    let new_stmts : Array[@ast.TsStmt] = []
    for a in aliases {
      new_stmts.push(a)
    }
    for s in m.block.stmts {
      new_stmts.push(s)
    }
    // Position array can't be aligned for synthesized prefix stmts;
    // emit those without source-map markers.
    let new_positions : Array[Int] = []
    if m.block.stmt_positions.length() == m.block.stmts.length() {
      for _ in aliases {
        new_positions.push(0)
      }
      for p in m.block.stmt_positions {
        new_positions.push(p)
      }
    }
    m.block = { stmts: new_stmts, stmt_positions: new_positions }
  }
}

///|
/// Walk modules in topological order and rename any top-level
/// binding whose name was already claimed by an earlier module.
/// The block-level rename is shared with `collision.mbt`'s pass;
/// here we also mirror the rename into each module's `exports`
/// table so the bundle's import-alias emit lines up with the
/// renamed binding's new name.
fn resolve_bundle_collisions(
  modules : Map[String, ModuleNode],
  order : Array[String],
) -> Unit {
  let claimed : Map[String, Bool] = {}
  for path in order {
    let node = match modules.get(path) {
      Some(n) => n
      None => continue
    }
    let local_names : Array[String] = []
    for n in collect_top_level_names_in_block(node.block) {
      local_names.push(n)
    }
    let rename_map : Map[String, String] = {}
    for name in local_names {
      if claimed.contains(name) {
        let mut n = 1
        let mut candidate = name + "$" + n.to_string()
        while claimed.contains(candidate) || rename_map.contains(candidate) {
          n = n + 1
          candidate = name + "$" + n.to_string()
        }
        rename_map[name] = candidate
        claimed[candidate] = true
      } else {
        claimed[name] = true
      }
    }
    if rename_map.size() == 0 {
      continue
    }
    // Apply the rename to the module's stmt block.
    node.block = rename_block_with(node.block, rename_map)
    // Mirror onto `exports.local_name` — that's what `mangle_bundle`
    // and the import-alias emit read. `export_name` stays untouched
    // (the public name the consumer sees doesn't change).
    let new_exports : Array[@ast.TsExportSpec] = []
    for spec in node.exports {
      let new_local = match rename_map.get(spec.local_name) {
        Some(n) => n
        None => spec.local_name
      }
      new_exports.push({ local_name: new_local, export_name: spec.export_name })
    }
    node.exports = new_exports
  }
}

///|
/// Public wrapper around the in-module renamer for `collision.mbt`'s
/// existing API. Local helper alias so the bundler can call the
/// rename pass without re-implementing the walker.
fn rename_block_with(
  block : @ast.TsBlock,
  rename : Map[String, String],
) -> @ast.TsBlock {
  rename_block_top(block, rename)
}

///|
/// Same as the unexported helper in `collision.mbt` — we re-export
/// the name collection here so the bundle layer doesn't reach into
/// another module's internals.
fn collect_top_level_names_in_block(block : @ast.TsBlock) -> Array[String] {
  collect_top_level_names(block)
}

///|
/// Run the immutability analysis across every loaded module, inline
/// primitive property reads, then drop any source `const` decl
/// whose remaining references are zero. The order matters: inlining
/// first creates the orphan, the cleanup pass removes it.
fn inline_immutable_bundle(
  modules : Map[String, ModuleNode],
  order : Array[String],
) -> Unit {
  let blocks : Array[@ast.TsBlock] = []
  let paths : Array[String] = []
  let funcs : Array[@ast.TsFunc] = []
  for path in order {
    match modules.get(path) {
      Some(n) => {
        blocks.push(n.block)
        paths.push(path)
        // Gather function signatures from each module's declaration
        // tables (populated when `auto_reserve` is on). The analyzer
        // uses them to relax disqualification when a candidate is
        // passed to a `ReadonlyArray<T>` / `Readonly<T>` parameter.
        match n.module_decls {
          Some(m) =>
            for f in m.funcs {
              funcs.push(f)
            }
          None => ()
        }
      }
      None => ()
    }
  }
  let report = analyze_immutable_consts_with_sigs(blocks, funcs)
  if report.immutable_objects.size() == 0 {
    return
  }
  let inlined = inline_immutable_property_reads(blocks, report)
  let cleaned = drop_orphan_immutable_decls(inlined, report)
  for i, p in paths {
    match modules.get(p) {
      Some(n) => n.block = cleaned[i]
      None => ()
    }
  }
}

///|
/// Run constant folding + dead-branch elimination across every
/// module's block. Trivial wrapper that swaps in the folded blocks.
fn fold_constants_bundle(
  modules : Map[String, ModuleNode],
  order : Array[String],
) -> Unit {
  for path in order {
    match modules.get(path) {
      Some(n) => n.block = fold_constants_in_block(n.block)
      None => ()
    }
  }
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
  // Layer in the auto-reserved property names from the dynamic /
  // reflective sink scan. These cover patterns the static walker
  // can't see: `obj[runtimeKey]`, `for…in`, `JSON.stringify`,
  // `Object.keys / assign / fromEntries`, etc. Without this layer
  // a property accessed via a runtime string would get its source
  // mangled but the lookup string stays as written, and the lookup
  // misses at execution time.
  let sink_reservations = collect_dynamic_property_reservations(blocks)
  let augmented_cfg = if sink_reservations.length() > 0 {
    cfg.with_reserved_properties(sink_reservations)
  } else {
    cfg
  }
  let mangled = mangle_blocks_together(blocks, augmented_cfg)
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
