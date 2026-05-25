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
  // When `true`, run the identifier-mangling pass on the final
  // concatenated module block. Source-map positions are skipped in
  // this mode because the rename pass doesn't carry positions yet.
  mangle : Bool
  // When `true` (and `mangle == true`), also rename non-reserved
  // property keys via the opt-in property-mangling path.
  mangle_properties : Bool
  // When `true`, drop top-level declarations that nothing reachable
  // from a side-effect statement references. Requires the merged-
  // block emit path, so the bundler forces single-scope folding
  // whenever this is set (just like `mangle` does).
  treeshake : Bool
  // When `true`, suppress indentation, newlines, and most optional
  // whitespace in the emitted JS. Mutually exclusive with
  // `with_sourcemap` because line / column tracking degenerates.
  minify : Bool
  // When `true`, run the lightweight constant-folder before the
  // treeshake / mangle passes. Folds identity-element arithmetic,
  // dead `if (true/false)` branches, boolean short-circuits, etc.
  fold : Bool
  // Pre-built (bare-specifier -> disk-path) map. Lets callers (mtsc
  // `--bundle`) resolve `import "react"` via `node_modules` before
  // handing the VFS to the bundler. Empty map = no aliases (every
  // bare specifier is treated as external).
  aliases : Map[String, String]
  // Caller-supplied additional reserved-property names. Used by
  // mtsc's `--bundle` loader to feed in every property name
  // declared in an `interface` / `type alias` / `class` across
  // the input modules — those names are part of the bundle's
  // public type surface and can't be renamed even when
  // `--mangle-properties` is otherwise safe.
  extra_reserved_props : Array[String]
}

///|
pub fn BundleOptions::default() -> BundleOptions {
  {
    jsx: JsxConfig::default(),
    with_sourcemap: false,
    mangle: false,
    mangle_properties: false,
    treeshake: false,
    minify: false,
    fold: false,
    aliases: {},
    extra_reserved_props: [],
  }
}

///|
pub fn BundleOptions::with_extra_reserved_props(
  self : BundleOptions,
  props : Array[String],
) -> BundleOptions {
  { ..self, extra_reserved_props: props }
}

///|
pub fn BundleOptions::with_aliases(
  self : BundleOptions,
  a : Map[String, String],
) -> BundleOptions {
  { ..self, aliases: a }
}

///|
pub fn BundleOptions::with_minify(self : BundleOptions, m : Bool) -> BundleOptions {
  { ..self, minify: m }
}

///|
pub fn BundleOptions::with_fold(self : BundleOptions, f : Bool) -> BundleOptions {
  { ..self, fold: f }
}

///|
pub fn BundleOptions::with_mangle(self : BundleOptions, m : Bool) -> BundleOptions {
  { ..self, mangle: m }
}

///|
pub fn BundleOptions::with_mangle_properties(
  self : BundleOptions,
  m : Bool,
) -> BundleOptions {
  { ..self, mangle_properties: m, mangle: self.mangle || m }
}

///|
pub fn BundleOptions::with_sourcemap(
  self : BundleOptions,
  s : Bool,
) -> BundleOptions {
  { ..self, with_sourcemap: s }
}

///|
pub fn BundleOptions::with_treeshake(
  self : BundleOptions,
  t : Bool,
) -> BundleOptions {
  { ..self, treeshake: t }
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
  // Lint / diagnostic warnings the bundler picked up. Today
  // limited to impure-getter detection; future passes can append
  // here. Empty when nothing is amiss.
  warnings : Array[String]
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
  block : @ast.TsBlock
  // Import specifiers from this module, mapped to the *absolute*
  // resolved path (`Map[specifier, resolved_path]`).
  resolved_imports : Map[String, String]
  // Bare ESM import metadata (for the dependency graph): list of
  // (specifier, default_binding?, named_bindings, namespace_binding?,
  // type_only).
  import_decls : Array[@ast.TsImportDecl]
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
  match
    load_module_graph(
      files, entry, modules, external_imports, external_seen, opts.aliases,
    ) {
    Ok(_) => ()
    Err(e) => return Err(e)
  }
  let order = topological_order(modules, entry)
  let e = Emitter::new(pretty=not(opts.minify))
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
  let warnings : Array[String] = []
  // Run the purity / impure-getter diagnostic over a combined
  // view of every module's lowered stmts. Doing this once up
  // front, BEFORE the optimization passes restructure the AST,
  // keeps the analysis scope-aware and independent of whether
  // `--mangle` / `--minify` happen to be on.
  {
    let combined_for_analysis : Array[@ast.TsStmt] = []
    for path in order {
      let m = match modules.get(path) {
        Some(node) => node
        None => continue
      }
      for s in m.block.stmts {
        combined_for_analysis.push(s)
      }
    }
    let report = analyze_purity({
      stmts: combined_for_analysis,
      stmt_positions: [],
    })
    for g in report.impure_getters {
      warnings.push(
        "warning: getter `\{g.class_name}.\{g.getter_name}` " + g.reason,
      )
    }
  }
  // When mangling or tree-shaking, fold every module's stmts into a
  // single block so cross-module references resolve through one
  // shared scope. Per-module separator comments and source-map
  // mappings are dropped — both rely on a per-module emit pass that
  // doesn't survive the rename / DCE.
  if opts.mangle || opts.treeshake || opts.fold {
    let combined_stmts : Array[@ast.TsStmt] = []
    for path in order {
      let m = match modules.get(path) {
        Some(node) => node
        None => continue
      }
      module_paths.push(path)
      for s in m.block.stmts {
        combined_stmts.push(s)
      }
    }
    let mut combined : @ast.TsBlock = {
      stmts: combined_stmts,
      stmt_positions: [],
    }
    // Order: fold -> treeshake -> mangle -> inline -> peephole.
    // Fold turns dead `if (false)` branches into nothing and
    // identity arithmetic into a single operand; treeshake then
    // drops declarations the now-smaller graph never reaches;
    // mangle renames whatever survived; inline collapses single-
    // use bindings into their unique reference; peephole finally
    // compacts the result with `x += y` and `void 0` rewrites.
    if opts.fold {
      combined = fold_block(combined)
    }
    if opts.treeshake {
      combined = treeshake_block(combined)
    }
    if opts.mangle {
      // Type-driven safety for property mangling: walk the merged
      // block looking for property accesses on bindings that
      // escape the bundle (external imports) and reflection sinks
      // (`JSON.stringify`, `Object.keys`, `for-in`). The result
      // augments the mangler's reserved-properties list. If the
      // analysis hits a fully-dynamic case (`*`), we suppress
      // property mangling entirely — the bundle isn't provably
      // safe to rename. This is what upgrades `--mangle-properties`
      // from "heuristic best-effort" to "type-checked safe": you
      // never get a silently-broken bundle.
      let mut effective_mangle_props = opts.mangle_properties
      let extra_reserved : Array[String] = []
      // Caller-supplied type-declared property names (interfaces /
      // type aliases / classes). These are always part of the
      // bundle's public type surface and must stay reserved,
      // independent of the escape analysis.
      for n in opts.extra_reserved_props {
        extra_reserved.push(n)
      }
      if opts.mangle_properties {
        let externals = external_import_bindings(external_imports)
        let escapes = collect_externally_visible_props(combined, externals)
        let mut wildcard = false
        for n in escapes {
          if n == "*" {
            wildcard = true
          } else {
            extra_reserved.push(n)
          }
        }
        if wildcard {
          // Bail out on property mangling — we can't prove
          // safety. Identifier mangling still runs.
          effective_mangle_props = false
        }
      }
      // Dead-property elimination runs before mangling so the
      // mangler doesn't allocate name slots for keys we're about
      // to drop. Gated on the same "no wildcard" safety: when
      // property mangling is suppressed, dead-prop pruning is
      // suppressed too — both depend on the same proof that no
      // property name escapes via reflection.
      if effective_mangle_props {
        let reserved_set : Map[String, Bool] = {}
        for n in extra_reserved {
          reserved_set[n] = true
        }
        for n in mangler_builtin_reserved_properties {
          reserved_set[n] = true
        }
        combined = drop_dead_properties_block(combined, reserved_set)
      }
      let mangler_cfg = ManglerConfig::default()
        .with_mangle_properties(effective_mangle_props)
        .with_reserved_properties(extra_reserved)
        // The bundle has no public ABI of its own — every binding
        // becomes internal once we glue modules together, so the
        // top-level can be renamed freely.
        .with_preserve_top_level(false)
      combined = mangle_block(combined, mangler_cfg)
    }
    if opts.minify {
      // Inline runs before peephole so `const X = expr; return X`
      // shapes collapse before the peephole pass sees them. Gated
      // on `minify` since the inlining produces deeply nested
      // expressions that are unpleasant in pretty mode.
      combined = inline_block(combined)
      combined = peephole_block(combined)
    }
    for s in combined.stmts {
      emit_stmt(e, s)
      e.nl()
    }
  } else {
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
  }
  let sm_json : String? = match e.smap {
    Some(b) =>
      Some(b.to_json_multi(sources, sources_content, output_path="bundle.js"))
    None => None
  }
  Ok({
    js: e.to_string(),
    sourcemap: sm_json,
    modules: module_paths,
    warnings,
  })
}

///|
fn load_module_graph(
  files : Map[String, String],
  path : String,
  modules : Map[String, ModuleNode],
  external_imports : Array[@ast.TsImportDecl],
  external_seen : Map[String, Bool],
  aliases : Map[String, String],
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
  // Reuse the per-file JSX pragma extractor so each module honors
  // its own `/** @jsxImportSource ... */` etc.
  let jsx_cfg = extract_jsx_pragmas(source, JsxConfig::default())
  let (lowered_jsx, _refs) = lower_block_with_runtime_imports(jsx_cfg, mb.block)
  // Splice in the runtime form of every `enum` declaration. The
  // parser collects enums on a side list and leaves an `Empty`
  // placeholder in the runtime block — without this step, every
  // enum reference becomes `undefined` at runtime.
  let lowered_with_enums = if mb.enums.length() > 0 {
    let enum_stmts = lower_enums(mb.enums)
    let combined : Array[@ast.TsStmt] = []
    for s in enum_stmts {
      combined.push(s)
    }
    for s in lowered_jsx.stmts {
      combined.push(s)
    }
    @ast.TsBlock::{ stmts: combined, stmt_positions: [] }
  } else {
    lowered_jsx
  }
  // `const enum` inlining: replace `E.Member` use sites with the
  // member's literal value. The lowering above already skipped
  // runtime emission for `is_const` decls, so the var is absent;
  // this step makes sure no stale `E.Member` references remain.
  let lowered = if mb.enums.length() > 0 {
    let table = build_const_enum_table(mb.enums)
    inline_const_enums(lowered_with_enums, table)
  } else {
    lowered_with_enums
  }
  // Insert a placeholder BEFORE recursing into imports so cyclic
  // module references hit the early-return guard above and break
  // the recursion. We finalize `resolved_imports` / `import_decls`
  // at the bottom of the function with the real values; topological
  // sort and emit only need the path → ModuleNode mapping to exist
  // during walking.
  modules[path] = {
    path,
    source,
    block: lowered,
    resolved_imports: {},
    import_decls: mb.imports,
  }
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
            files, dep_path, modules, external_imports, external_seen, aliases,
          ) {
          Ok(_) => ()
          Err(e) => return Err(e)
        }
      }
      None =>
        // Bare specifier. Two pre-resolved sources, in priority
        // order: (a) the alias map (`react -> /abs/.../react/index.js`)
        // and (b) a direct hit in `files`. Either way we recurse
        // through the disk-path key so a follow-up `../utils/...`
        // relative import inside the package resolves correctly.
        match aliases.get(imp.module_spec) {
          Some(disk) => {
            let dep_path = resolve_with_extensions(files, disk)
            resolved[imp.module_spec] = dep_path
            match
              load_module_graph(
                files, dep_path, modules, external_imports, external_seen,
                aliases,
              ) {
              Ok(_) => ()
              Err(e) => return Err(e)
            }
          }
          None =>
            if files.contains(imp.module_spec) {
              let dep_path = resolve_with_extensions(files, imp.module_spec)
              resolved[imp.module_spec] = dep_path
              match
                load_module_graph(
                  files, dep_path, modules, external_imports, external_seen,
                  aliases,
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
  // Finalize the entry with the resolved-imports map populated.
  modules[path] = {
    path,
    source,
    block: lowered,
    resolved_imports: resolved,
    import_decls: mb.imports,
  }
  Ok(())
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
