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
  // concatenated module block. `--with-sourcemap` is now compatible
  // with this path: each combined statement's origin (source-id +
  // byte offset within that source) is encoded into the position
  // array, the mangle / treeshake / inline passes preserve it
  // verbatim, and the emit decodes it for the source-map writer.
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
pub fn BundleOptions::with_minify(
  self : BundleOptions,
  m : Bool,
) -> BundleOptions {
  { ..self, minify: m }
}

///|
pub fn BundleOptions::with_fold(
  self : BundleOptions,
  f : Bool,
) -> BundleOptions {
  { ..self, fold: f }
}

///|
pub fn BundleOptions::with_mangle(
  self : BundleOptions,
  m : Bool,
) -> BundleOptions {
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
  // Named exports surfaced by this module, used by the linker to
  // resolve `import { X as Y } from "./this"` references in other
  // modules back to this module's renamed local binding.
  export_specs : Array[@ast.TsExportSpec]
  // `export { X } from "./a"` / `export * from "./a"` re-exports.
  // The linker walks the chain so an `import { Hono } from "./hono"`
  // can resolve through `index.js` (which re-exports from
  // `./hono.js`) all the way to the actual declaration.
  reexport_specs : Array[@ast.TsReExportSpec]
  // Names this module declared with a `@__PURE__` /
  // `@__NO_SIDE_EFFECTS__` JSDoc tag. Union across modules
  // becomes the assumed-pure set fed into purity analysis.
  pure_declarations : Map[String, Bool]
  // Type aliases declared in this module (`type T = …`). The
  // tag-rewrite / dts-emit / future cross-module type-driven
  // passes consult these.
  type_aliases : Array[@ast.TsTypeAlias]
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
      files,
      entry,
      modules,
      external_imports,
      external_seen,
      opts.aliases,
    ) {
    Ok(_) => ()
    Err(e) => return Err(e)
  }
  let order = topological_order(modules, entry)
  // Run the cross-module linker before any pass that operates on
  // the combined block. Phase 1 gives each module's top-level
  // bindings a globally-unique name when they collide; phase 2
  // rewrites imported references to point at the renamed export.
  // Without this, two modules each declaring `var Hono` collapse
  // into one binding and `import { HonoBase } from "./hono-base"`
  // (which re-exports `Hono as HonoBase`) leaves `HonoBase` as a
  // free variable in the consumer.
  let link_renames = link_module_graph(modules, order, external_imports)
  let mut mangle_export_renames : Map[String, String] = {}
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
    // Union the per-module JSDoc-asserted pure set so the
    // analysis trusts the user's `@__NO_SIDE_EFFECTS__` /
    // `@__PURE__` annotations across the whole bundle.
    let assumed_pure : Map[String, Bool] = {}
    for path in order {
      let m = match modules.get(path) {
        Some(node) => node
        None => continue
      }
      for s in m.block.stmts {
        combined_for_analysis.push(s)
      }
      for n in m.pure_declarations.keys() {
        assumed_pure[n] = true
      }
    }
    let report = analyze_purity_with(
      { stmts: combined_for_analysis, stmt_positions: [] },
      assumed_pure,
    )
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
    let combined_type_aliases : Array[@ast.TsTypeAlias] = []
    // Track each combined-statement's origin so the source-map can
    // map it back to its module after mangle / treeshake / fold
    // restructure the AST. Encoding: high 24 bits = source-id (the
    // module's slot in `sources`), low 8 bits = "" — actually we
    // pack byte_offset in the high bits and source_id in the low 8
    // so the existing position-as-int representation survives 1:1
    // transforms verbatim. `combined_source_count` is the next free
    // source-id slot.
    let combined_positions : Array[Int] = []
    let combined_line_indices : Array[LineIndex] = []
    let mut combined_source_count = 0
    for path in order {
      let m = match modules.get(path) {
        Some(node) => node
        None => continue
      }
      module_paths.push(path)
      // Allocate a source-id for this module and populate the
      // top-level sources / sources_content / line-index tables.
      let source_id = combined_source_count
      combined_source_count = combined_source_count + 1
      sources.push(path)
      sources_content.push(m.source)
      combined_line_indices.push(LineIndex::new(m.source))
      let has_positions = m.block.stmt_positions.length() ==
        m.block.stmts.length()
      for j, s in m.block.stmts {
        combined_stmts.push(s)
        if has_positions {
          combined_positions.push(
            encode_combined_position(m.block.stmt_positions[j], source_id),
          )
        } else {
          combined_positions.push(encode_combined_position(0, source_id))
        }
      }
      for ta in m.type_aliases {
        combined_type_aliases.push(ta)
      }
    }
    let mut combined : @ast.TsBlock = {
      stmts: combined_stmts,
      stmt_positions: combined_positions,
    }
    // Type-predicate inline.
    {
      let predicates = build_predicate_table(combined)
      if not(predicates.entries.is_empty()) {
        combined = inline_predicates(combined, predicates)
      }
    }
    // Literal-union switch folding. Specializes `dispatch("x", n)`
    // when `dispatch` is a `switch (k) { case ...: return ... }`
    // function whose first param is a closed string-literal union.
    {
      let sw = build_switch_fold_table(combined)
      if not(sw.entries.is_empty()) {
        combined = switch_fold(combined, sw)
      }
    }
    // `as const` (and equivalent) array/object inline at use sites.
    // Replaces `NAME[i]` / `NAME.k` with the underlying literal value
    // when NAME is a top-level `const` of all-literal-element shape
    // and every reference is a safe static read.
    combined = as_const_inline_block(combined)
    // Discriminant-tag string -> number rewrite. Gated on
    // a bundle-wide no-escape-sink scan; for each closed
    // string-literal discriminated union whose `K` property is
    // never observed outside switch heads and `===`/`!==`
    // comparisons, swap the string tags for small integers.
    combined = tag_rewrite_block(combined, combined_type_aliases)
    // Lift the IIFE-lowered class shape back to native
    // `class Name { … }` syntax. Smaller emit, plus
    // `class_method_dce_block` then operates on the structured
    // form (NativeClassStmt) instead of pattern-matching the
    // prototype-assignment chain.
    combined = iife_class_lift_block(combined)
    // Class-method DCE: drop methods on native class declarations
    // that nothing in the bundle accesses by name. Gated on the
    // absence of reflection / dynamic-key access in the bundle.
    combined = class_method_dce_block(combined)
    // Type-aware constant folding: `typeof x === "string"` /
    // `x === null` etc. when the bound `x` carries a primitive
    // type annotation. Runs BEFORE the regular fold so the
    // resulting `BoolLit(true/false)` feeds into dead-branch
    // elimination.
    combined = type_fold_block(combined)
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
      let effective_mangle_props = opts.mangle_properties
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
          // User-declared property names can't be safely renamed
          // (dynamic `obj[runtime_key]` access reaches arbitrary
          // names). But mtsc-synthesized internal markers — the
          // `__private_brand__N__X` rewrite the parser uses for
          // `#X` private fields — are unreachable from user code
          // by definition. Switch to "mangle internals only":
          // every property name COLLECTED from the bundle goes
          // into the reserved set except those matching the
          // internal-marker prefix. The mangle pass then renames
          // just the markers.
          let collected : Map[String, Bool] = {}
          collect_property_names(combined, collected)
          for n in collected.keys() {
            if not(is_internal_marker_property(n)) {
              extra_reserved.push(n)
            }
          }
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
      // External `import` headers (`import os from "os"`, etc.)
      // sit OUTSIDE `combined` and are emitted by the linker around
      // the merged block. The mangler never sees them, so without
      // this reservation it can hand the short name `os` to a
      // renamed CJS helper inside the bundle and produce
      // `SyntaxError: Identifier 'os' has already been declared`.
      let external_reserved : Array[String] = []
      for n in external_import_bindings(external_imports).keys() {
        external_reserved.push(n)
      }
      let mangler_cfg = ManglerConfig::default()
        .with_mangle_properties(effective_mangle_props)
        .with_reserved_properties(extra_reserved)
        .with_reserved(external_reserved)
        // The bundle has no public ABI of its own — every binding
        // becomes internal once we glue modules together, so the
        // top-level can be renamed freely.
        .with_preserve_top_level(false)
      let (mangled_block, mangle_renames) = mangle_block_with_renames(
        combined, mangler_cfg,
      )
      combined = mangled_block
      // Carry the mangle pass's rename map forward so the
      // entry-export emit at the bottom can write the right short
      // name for `export default app` even after `app` was
      // renamed to e.g. `aq`.
      mangle_export_renames = mangle_renames
    }
    if opts.minify {
      // Inline runs before peephole so `const X = expr; return X`
      // shapes collapse before the peephole pass sees them. Gated
      // on `minify` since the inlining produces deeply nested
      // expressions that are unpleasant in pretty mode.
      combined = inline_block(combined)
      combined = peephole_block(combined)
    }
    let has_combined_positions = combined.stmt_positions.length() ==
      combined.stmts.length()
    for i, s in combined.stmts {
      // When source-maps are on, decode the per-stmt origin and
      // switch the emitter's line index to the source the stmt
      // came from before recording the mapping. Stmts whose origin
      // was lost (synthesized by a transform) have an out-of-range
      // source-id and are simply skipped.
      if opts.with_sourcemap && has_combined_positions {
        let (offset, source_id) = decode_combined_position(
          combined.stmt_positions[i],
        )
        if source_id < combined_line_indices.length() {
          e.line_index = combined_line_indices[source_id]
          match e.smap {
            Some(b) => b.set_current_source(source_id)
            None => ()
          }
          let src_pos = e.line_index.position(offset)
          e.mark(src_pos)
        }
      }
      emit_stmt(e, s)
      e.nl()
    }
    // After the combined emit, surface the entry module's exports
    // so the bundle is consumable as an ES module. The mangle path
    // doesn't track its own short-name renames here, so the
    // entry export's `local_name` falls back through link_renames
    // — bindings the mangle pass renamed end up referenced by
    // their pre-mangle (post-link) name and the mangle pass takes
    // care of substituting them since the export ref counts as a
    // use.
    match modules.get(entry) {
      Some(em) =>
        if em.export_specs.length() > 0 {
          // Chain link-renames then mangle-renames: link first
          // (`app` -> `app`) then mangle (`app` -> `aq`). The
          // bundle output's `export default <name>` must use the
          // POST-mangle short form because that's what survives in
          // the body.
          let entry_renames = compose_renames(
            link_renames.get(entry).unwrap_or({}),
            mangle_export_renames,
          )
          emit_entry_exports(e, em, entry_renames)
        }
      None => ()
    }
  } else {
    for i, path in order {
      let m = match modules.get(path) {
        Some(node) => node
        None => continue
      }
      // Skip the module banner entirely in minify mode: `e.nl()` is
      // a no-op there and the `//` comment would swallow every
      // following statement until the next real newline (typically
      // dozens of KB later, inside the first multi-line template
      // literal) — turning the rest of the module's parse into
      // dead text.
      if not(opts.minify) {
        e.write("// ===== ")
        e.write(path)
        e.write(" =====")
        e.nl()
      }
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
      // Per-module emit path: surface the entry module's exports
      // at the tail (mirror of the combined-emit branch above).
      if path == entry {
        if m.export_specs.length() > 0 {
          let entry_renames = link_renames.get(entry).unwrap_or({})
          emit_entry_exports(e, m, entry_renames)
        }
      }
    }
  }
  let sm_json : String? = match e.smap {
    Some(b) =>
      Some(b.to_json_multi(sources, sources_content, output_path="bundle.js"))
    None => None
  }
  Ok({ js: e.to_string(), sourcemap: sm_json, modules: module_paths, warnings })
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
    // Inline ALL enum member accesses (`E.Member`) — const enums
    // erase entirely, regular enums also fold the access while
    // keeping their runtime table for `E[reverseValue]` lookups.
    let table = build_enum_inline_table(mb.enums, include_non_const=true)
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
    pure_declarations: mb.pure_declarations,
    type_aliases: mb.type_aliases,
    export_specs: mb.exports,
    reexport_specs: mb.reexports,
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
                files, dep_path, modules, external_imports, external_seen, aliases,
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
                  files, dep_path, modules, external_imports, external_seen, aliases,
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
  // Re-exports (`export { X } from "./a"`, `export * from "./a"`)
  // also pull `./a` into the bundle. The graph loader previously
  // walked only `mb.imports`, so re-exported dependencies fell out
  // of the graph entirely. Mirror the loop above for each re-export
  // whose specifier is relative; bare-specifier re-exports become
  // external imports just like bare imports.
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
            files, dep_path, modules, external_imports, external_seen, aliases,
          ) {
          Ok(_) => ()
          Err(e) => return Err(e)
        }
      }
      None =>
        match aliases.get(re.module_spec) {
          Some(dep_path) => {
            resolved[re.module_spec] = dep_path
            match
              load_module_graph(
                files, dep_path, modules, external_imports, external_seen, aliases,
              ) {
              Ok(_) => ()
              Err(e) => return Err(e)
            }
          }
          None =>
            if files.contains(re.module_spec) {
              let dep_path = resolve_with_extensions(files, re.module_spec)
              resolved[re.module_spec] = dep_path
              match
                load_module_graph(
                  files, dep_path, modules, external_imports, external_seen, aliases,
                ) {
                Ok(_) => ()
                Err(e) => return Err(e)
              }
            }
          // Bare re-export targets aren't tracked as external —
          // the consumer's runtime won't see them unless they
          // also become a direct import. v0 limitation.
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
    pure_declarations: mb.pure_declarations,
    type_aliases: mb.type_aliases,
    export_specs: mb.exports,
    reexport_specs: mb.reexports,
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

///|
/// Encode a (byte_offset, source_id) pair into a single Int so the
/// combined-block `stmt_positions` array can carry per-stmt origin
/// info through every transform pass. Low 8 bits are the source-id
/// (max 256 distinct sources per bundle); high bits are the byte
/// offset within that source.
///
/// 256 sources is plenty for the synthetic / real-world bundles
/// the bench drives; when a project hits that wall we can switch
/// to a wider encoding, but a parallel side-array would be the
/// cleaner answer at that point.
fn encode_combined_position(offset : Int, source_id : Int) -> Int {
  offset * 256 + source_id % 256
}

///|
fn decode_combined_position(encoded : Int) -> (Int, Int) {
  let source_id = encoded % 256
  let offset = encoded / 256
  (offset, source_id)
}

///|
/// Emit the entry module's `export …` statements at the tail of
/// the bundle so a consumer that imports the result can find
/// the symbols the source declared as public. The linker's
/// per-module rename map turns each `local_name` into its final
/// post-link form.
fn emit_entry_exports(
  e : Emitter,
  m : ModuleNode,
  renames : Map[String, String],
) -> Unit {
  // Group default vs named.
  let default_local : String? = {
    let mut found : String? = None
    for spec in m.export_specs {
      if spec.export_name == "default" {
        found = Some(renames.get(spec.local_name).unwrap_or(spec.local_name))
        break
      }
    }
    found
  }
  let named : Array[(String, String)] = []
  for spec in m.export_specs {
    if spec.export_name == "default" {
      continue
    }
    let local = renames.get(spec.local_name).unwrap_or(spec.local_name)
    named.push((local, spec.export_name))
  }
  match default_local {
    Some(local) => {
      e.write("export default ")
      e.write(local)
      e.semi()
      e.nl()
    }
    None => ()
  }
  if named.length() > 0 {
    e.write("export ")
    e.write("{ ")
    for i, pair in named {
      if i > 0 {
        e.write(", ")
      }
      if pair.0 == pair.1 {
        e.write(pair.0)
      } else {
        e.write(pair.0)
        e.write(" as ")
        e.write(pair.1)
      }
    }
    e.write(" }")
    e.semi()
    e.nl()
  }
}

///|
/// Chain two rename maps: `first` is applied to the original name,
/// then `second` is applied to the result. Output is a fresh map
/// where each key from `first` (or that survives the chain) maps
/// to the final name post-`second`.
fn compose_renames(
  first : Map[String, String],
  second : Map[String, String],
) -> Map[String, String] {
  let out : Map[String, String] = {}
  // Walk every input that either map touched.
  let seen : Map[String, Bool] = {}
  for k in first.keys() {
    seen[k] = true
  }
  for k in second.keys() {
    seen[k] = true
  }
  for k in seen.keys() {
    let after_first = first.get(k).unwrap_or(k)
    let after_second = second.get(after_first).unwrap_or(after_first)
    if after_second != k {
      out[k] = after_second
    }
  }
  out
}

///|
/// True when `name` is one of mtsc's internal property markers that
/// user code can never reach (they're synthesized by the parser).
/// Used by the wildcard-mangle-property fallback: even when a
/// `obj[runtime_key]` access disables property mangling for safety,
/// these still mangle because their access surface is entirely
/// mtsc-controlled.
fn is_internal_marker_property(name : String) -> Bool {
  // Keep this in lockstep with `is_class_metadata_key` in
  // `iife_class_lift.mbt`: every metadata name the parser
  // synthesizes on the IIFE-lowered class shape (`__super_proto`,
  // `__brand__`, `__private_brand__N__X`) is private to mtsc — no
  // user code can reach it, so it stays safe to rename even in the
  // wildcard / dynamic-access fallback. Without this, prettier's
  // bundle keeps 236+ raw `__super_proto` strings because the IIFE
  // form survives whenever lift declines.
  name == "__super_proto" ||
  name == "__brand__" ||
  name.has_prefix("__private_brand__")
}
