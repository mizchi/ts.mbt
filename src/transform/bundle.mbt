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
  // When `true` (and `mangle_properties == true`), use the
  // shape-coloring property-rename strategy: distinct names that
  // never co-occur on the same shape share short slots. Opt-in
  // because soundness in the face of cross-Symbol value flow without
  // expression-level type propagation isn't yet established.
  mangle_properties_shape_color : Bool
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
  // When `true`, collect a human-readable account of every minify
  // decision into `BundleOutput.explain` instead of only acting on it.
  // `--explain-mangle` is the reason the analyses keep their reasons
  // rather than just their answers.
  explain : Bool
  // Keep a relative import the vfs cannot resolve as an external
  // import instead of failing. Set by the CLI, which has already
  // asked the real filesystem; in-memory callers stay strict.
  allow_unresolved_imports : Bool
  // Phases the caller switched off, by the name `timer.phase` records.
  // See `with_disabled_phases`.
  disabled_phases : Map[String, Bool]
  // Measure wall time per pipeline phase into `BundleOutput.timings`.
  // Off by default: with it off `PhaseTimer` records nothing and the
  // instrumentation is one branch per phase.
  timing : Bool
  // Already-parsed module blocks, keyed exactly like `files`. A caller
  // that had to parse each file to find its imports (mtsc's loader
  // walks the graph off disk before the bundler ever sees it) can hand
  // the results over instead of paying for a second parse of the same
  // source. Parsing is 78-94% of a bundle's wall time and it was
  // happening twice; on 9 MB of `typescript.js` the bundler's own pass
  // was 850 ms of 5.0 s. Empty map = parse everything here.
  parsed_blocks : Map[String, @ast.TsModuleBlock]
}

///|
pub fn BundleOptions::default() -> BundleOptions {
  {
    jsx: JsxConfig::default(),
    with_sourcemap: false,
    mangle: false,
    mangle_properties: false,
    mangle_properties_shape_color: false,
    treeshake: false,
    minify: false,
    fold: false,
    aliases: {},
    extra_reserved_props: [],
    explain: false,
    allow_unresolved_imports: false,
    disabled_phases: {},
    timing: false,
    parsed_blocks: {},
  }
}

///|
pub fn BundleOptions::with_parsed_blocks(
  self : BundleOptions,
  parsed : Map[String, @ast.TsModuleBlock],
) -> BundleOptions {
  { ..self, parsed_blocks: parsed }
}

///|
pub fn BundleOptions::with_timing(
  self : BundleOptions,
  t : Bool,
) -> BundleOptions {
  { ..self, timing: t }
}

///|
/// Turn a named pipeline phase off, for attribution.
///
/// `--timing` says how long each phase takes; nothing said how many
/// BYTES each one is responsible for, and "the mechanism is
/// unidentified" sat in the known-unfixed table for two rows because of
/// it. A twenty-pass pipeline gives a guess nothing to stand on: the
/// only way to attribute a size delta to a phase is to run without it.
///
/// Names are the ones `timer.phase` already uses, so `--timing` output
/// doubles as the list of what can be switched off.
pub fn BundleOptions::with_disabled_phases(
  self : BundleOptions,
  names : Map[String, Bool],
) -> BundleOptions {
  { ..self, disabled_phases: names }
}

///|
/// Is this phase enabled? Every gated call site asks by the same name
/// `timer.phase` records it under.
pub fn BundleOptions::phase_enabled(
  self : BundleOptions,
  name : String,
) -> Bool {
  !self.disabled_phases.contains(name)
}

///|
pub fn BundleOptions::with_allow_unresolved_imports(
  self : BundleOptions,
  v : Bool,
) -> BundleOptions {
  { ..self, allow_unresolved_imports: v }
}

///|
pub fn BundleOptions::with_explain(
  self : BundleOptions,
  e : Bool,
) -> BundleOptions {
  { ..self, explain: e }
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
pub fn BundleOptions::with_mangle_properties_shape_color(
  self : BundleOptions,
  m : Bool,
) -> BundleOptions {
  // Implies property mangling: shape-color is a property-rename
  // strategy, not a separate pass.
  {
    ..self,
    mangle_properties_shape_color: m,
    mangle_properties: self.mangle_properties || m,
    mangle: self.mangle || m,
  }
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
/// Collapse repeats, keeping first-seen order. The per-module emit path
/// runs the class-method scan once per file over one bundle-wide scope,
/// so a single `Reflect.ownKeys` call is reported once per module.
fn dedup_reflection_warnings(lines : Array[String]) -> Array[String] {
  let seen : Map[String, Bool] = {}
  let out : Array[String] = []
  for l in lines {
    if !seen.contains(l) {
      seen[l] = true
      out.push(l)
    }
  }
  out
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
  // Reflection in the input that no optimization can see through:
  // `Reflect.ownKeys` and friends enumerate NON-enumerable properties,
  // which is exactly what a class prototype method is, so one call
  // anywhere keeps every method of every class in the bundle. Kept
  // separate from `warnings` because it is not a lint: it is the
  // compiler reporting that the author's own code, not a missing
  // analysis, is what stopped an optimization. Empty when the bundle
  // contains none.
  reflection_warnings : Array[String]
  // `--explain-mangle` output: why each minify decision went the way it
  // did. Empty unless `BundleOptions.explain` was set.
  explain : Array[String]
  // `(phase label, microseconds)` in execution order. Empty unless
  // `BundleOptions.timing` was set.
  timings : Array[(String, Double)]
}

// ---------------------------------------------------------------------------
// Module graph
// ---------------------------------------------------------------------------

///|
priv struct ModuleNode {
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
  // Interfaces declared in this module. Same role as `type_aliases`:
  // the escape analysis resolves an annotation that names one of these
  // to decide whether its key set is closed.
  interfaces : Array[@ast.TsInterface]
  // `(field name, declared type)` for this module's runtime classes.
  // The class lowering drops the annotation, so a whole-program pass
  // needs it carried alongside. See `TsModuleBlock.class_fields`.
  class_fields : Array[(String, @ast.TsType)]
  // Specifiers this module requests at runtime, in source order —
  // imports and re-exports interleaved as they appear. See
  // `TsModuleBlock.module_request_order` and `topological_order`.
  module_request_order : Array[String]
  // Names this module exports with `export type { X }` — no runtime
  // value. See `TsModuleBlock.type_only_exports`.
  type_only_exports : Map[String, Bool]
  // `const enum` declarations this module made. A const enum produces
  // NO runtime binding — every `E.Member` is meant to become a literal —
  // so a consumer in another module has nothing to link against and the
  // reference has to be substituted instead. `load_module_graph` can
  // only substitute the uses it can see, which are this module's; the
  // cross-module half needs the declarations carried on the node. See
  // `inline_imported_const_enums`.
  const_enums : Array[@ast.TsEnumDecl]
  // For CJS-wrapped modules (esbuild-style `((module)=>{...})({get exports(){return X;}, ...})`),
  // the top-level variable that holds the module's exports after the wrapper runs.
  // Named imports from such a module that can't be resolved via export_specs fall
  // back to property accesses on this variable: `transpileModule` → `X.transpileModule`.
  cjs_exports_var : String?
}

// ---------------------------------------------------------------------------
// Path resolution (posix-style)
// ---------------------------------------------------------------------------

///|
/// Does this specifier name a file relative to the importer, rather than
/// a package?
///
/// The obvious spelling of this test is `has_prefix("./") ||
/// has_prefix("../")`, and it is wrong for two specifiers that are as
/// relative as any: `"."` and `".."`. Both are FALSE under that test, so
/// they fall through to bare-specifier handling and the directory they
/// name is left external.
///
/// `import { x } from "."` is how a package's own modules reach their
/// barrel — Excalidraw's element package writes it, and Node then failed
/// the bundle with `ERR_UNSUPPORTED_DIR_IMPORT` because the import
/// survived verbatim into the output.
///
/// A shared predicate rather than the test inlined at each site, because
/// the loader tests this four times (import / re-export, each with a
/// type-only guard and a resolve branch) and the two loops are mirror
/// images. Every bug this pass has had in that shape came from one copy
/// being updated and its mirror not.
pub fn is_relative_specifier(specifier : String) -> Bool {
  specifier == "." ||
  specifier == ".." ||
  specifier.has_prefix("./") ||
  specifier.has_prefix("../")
}

///|
/// Resolve `specifier` relative to `from_path`. Only relative and
/// rooted (`/`) specifiers are handled here; bare specifiers (e.g.
/// `react`) fall through to the caller's external resolver.
fn resolve_relative(from_path : String, specifier : String) -> String? {
  if specifier.has_prefix("/") {
    return Some(normalize_path(specifier))
  }
  if !is_relative_specifier(specifier) {
    return None
  }
  let dir = dirname(from_path)
  let combined = if dir == "" { specifier } else { dir + "/" + specifier }
  Some(normalize_path(combined))
}

///|
fn dirname(path : String) -> String {
  match path.rev_find("/") {
    Some(idx) => path[0:idx].to_owned()
    None => ""
  }
}

///|
/// The TypeScript files a JS-spelled specifier may actually name.
/// Empty for anything that does not end in a JS extension.
fn ts_equivalents_of(base : String) -> Array[String] {
  for
    pair in [
      (".js", [".ts", ".tsx", ".d.ts"]),
      (".mjs", [".mts"]),
      (".cjs", [".cts"]),
    ] {
    if base.has_suffix(pair.0) {
      let stem = base[0:base.length() - pair.0.length()].to_owned()
      let out : Array[String] = []
      for ext in pair.1 {
        out.push(stem + ext)
      }
      return out
    }
  }
  []
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
  // `./x.js` may name `x.ts`: TypeScript's `node16` / `nodenext` /
  // `bundler` resolution says the specifier keeps the emitted
  // extension, so TS sources import each other that way.
  for cand in ts_equivalents_of(base) {
    if files.contains(cand) {
      return cand
    }
  }
  let exts = [".ts", ".tsx", ".js", ".mjs", ".jsx"]
  for ext in exts {
    let cand = base + ext
    if files.contains(cand) {
      return cand
    }
  }
  for ext in exts {
    // `base` is empty when a flat VFS resolves `from "."` — the
    // importer has no directory component, so the directory the
    // specifier names is the root itself. `"/index.ts"` is not it.
    let cand = if base == "" { "index" + ext } else { base + "/index" + ext }
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
    let p = part.to_owned()
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
  let timer = if opts.timing {
    PhaseTimer::new()
  } else {
    PhaseTimer::disabled()
  }
  let modules : Map[String, ModuleNode] = {}
  // External (bare specifier) imports we want to re-emit at the top
  // of the bundle so the consumer's loader / browser handles them.
  let external_imports : Array[@ast.TsImportDecl] = []
  let external_seen : Map[String, Bool] = {}
  let graph_started = @bench.monotonic_clock_start()
  match
    load_module_graph(
      files,
      entry,
      modules,
      external_imports,
      external_seen,
      opts.aliases,
      opts.allow_unresolved_imports,
      opts.parsed_blocks,
    ) {
    Ok(_) => ()
    Err(e) => return Err(e)
  }
  // Parsing every module and lowering its JSX happens inside the graph
  // load, so this row usually dominates on a large input — the point of
  // measuring it is to know when it does NOT.
  timer.record(
    "module-graph (parse)",
    @bench.monotonic_clock_end(graph_started),
  )
  let order = topological_order(modules, entry)
  // Substitute the const-enum members each module reads through its
  // IMPORTS. `load_module_graph` already inlined each module's own
  // enums, which had been taken for the whole job — but a const enum
  // emits no runtime binding, so a cross-module read has nothing for the
  // linker to point at and had never been substituted either. It just
  // survived into the bundle as a free variable.
  //
  // This runs before the linker for that reason: by the time the linker
  // is rewriting imported references, `ArchType.Array` should already be
  // `1` and there should be no `ArchType` left to resolve.
  for path in order {
    let m = match modules.get(path) {
      Some(node) => node
      None => continue
    }
    if m.import_decls.length() == 0 {
      continue
    }
    let table = imported_const_enum_table(
      m.import_decls,
      m.resolved_imports,
      p => modules.get(p).map(n => n.const_enums),
      p => modules.get(p).map(n => n.export_specs),
      p => modules.get(p).map(n => n.reexport_specs),
      (from, spec) => modules.get(from).bind(n => n.resolved_imports.get(spec)),
    )
    if table.size() > 0 {
      modules[path] = { ..m, block: inline_const_enums(m.block, table) }
    }
  }
  // Lift IIFE-lowered classes to native `class Name { … }` syntax on
  // each module individually BEFORE the linker pass. The parser emits
  // computed-key temp vars (`let __class_key_0 = expr`) inside the
  // IIFE body; the lift hoists them to module-top-level. Running the
  // lift here lets the linker see those names and rename duplicates
  // (multiple modules each starting their counter at 0 would otherwise
  // produce identical `let __class_key_0` at the bundle top-level).
  for path in order {
    let m = match modules.get(path) {
      Some(node) => node
      None => continue
    }
    let lifted = iife_class_lift_block(m.block)
    modules[path] = { ..m, block: lifted }
  }
  // Run the cross-module linker before any pass that operates on
  // the combined block. Phase 1 gives each module's top-level
  // bindings a globally-unique name when they collide; phase 2
  // rewrites imported references to point at the renamed export.
  // Without this, two modules each declaring `var Hono` collapse
  // into one binding and `import { HonoBase } from "./hono-base"`
  // (which re-exports `Hono as HonoBase`) leaves `HonoBase` as a
  // free variable in the consumer.
  let link_renames = link_module_graph(modules, order, external_imports)
  // Names the bundle will export. Used three times below: as the members
  // class-method DCE must keep (a consumer calls them even when nothing
  // inside the bundle does), as treeshake roots (nothing inside the
  // bundle has to reference an exported binding), and as the starting
  // point for the property mangler's escape analysis.
  let entry_exports = entry_export_bindings(modules, link_renames, entry)
  let export_roots : Map[String, Bool] = {}
  for ex in entry_exports {
    if ex.from_external is None {
      export_roots[ex.local_name] = true
    }
  }
  let mut mangle_export_renames : Map[String, String] = {}
  let e = Emitter::new(pretty=!opts.minify)
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
  // Reflection the passes met, for `BundleOutput.reflection_warnings`.
  let reflection_warnings : Array[String] = []
  // `--explain-mangle` output, gathered per section and concatenated in
  // a fixed reading order at the end. The passes run in pipeline order,
  // which is not the order a person wants to read the answer in: the
  // escape analysis is what everything else depends on, so it goes
  // first even though parameter trimming happens earlier.
  let explain : Array[String] = []
  let explain_escape : Array[String] = []
  let explain_params : Array[String] = []
  let explain_fields : Array[String] = []
  let explain_tags : Array[String] = []
  // `tag-rewrite`, the type-driven tag renumbering, is a different pass
  // from `discriminant_ints` above: it reads declared unions, runs early,
  // and does not need `--mangle-properties`. Its section is separate for
  // the same reason — one of them saying "nothing declined" tells you
  // nothing about the other.
  let explain_type_tags : Array[String] = []
  let explain_dispatchers : Array[String] = []
  let explain_type_checks : Array[String] = []
  let explain_methods : Array[String] = []
  // Set when the escape analysis reserved the wildcard. Every later
  // section then declines everything, and saying so once beats
  // repeating "it's reserved" for each name.
  let mut explain_wildcard = false
  // `@__PURE__` / `@__NO_SIDE_EFFECTS__` annotations, keyed by the name
  // each declaration carries in the MERGED block. Filled alongside the
  // diagnostic run below and consumed by the second purity run, the
  // one whose result is allowed to delete code.
  let linked_assumed_pure : Map[String, Bool] = {}
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
    // Carry the per-module annotations forward under their POST-link
    // names: the treeshake pass runs on the merged block, where
    // `helper` from two modules has become `helper` and `helper$0`.
    for path in order {
      let m = match modules.get(path) {
        Some(node) => node
        None => continue
      }
      let renames = link_renames.locals.get(path).unwrap_or({})
      for n in m.pure_declarations.keys() {
        linked_assumed_pure[renames.get(n).unwrap_or(n)] = true
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
    let combined_interfaces : Array[@ast.TsInterface] = []
    let combined_class_fields : Array[(String, @ast.TsType)] = []
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
      // Only the `with_sourcemap` emit path reads this table, and
      // building an entry scans the module's whole source for line
      // breaks — 3 MB of it for `checker.ts`, for a map nobody asked
      // for. Keep the slot so `source_id` still indexes it.
      combined_line_indices.push(
        if opts.with_sourcemap {
          LineIndex::new(m.source)
        } else {
          LineIndex::new("")
        },
      )
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
      for i in m.interfaces {
        combined_interfaces.push(i)
      }
      for f in m.class_fields {
        combined_class_fields.push(f)
      }
    }
    let mut combined : @ast.TsBlock = {
      stmts: combined_stmts,
      stmt_positions: combined_positions,
    }
    // Type-predicate inline.
    if opts.phase_enabled("predicate-inline") {
      timer.phase("predicate-inline", () => {
        let predicates = build_predicate_table(combined, exported=export_roots)
        if !predicates.entries.is_empty() {
          combined = inline_predicates(combined, predicates)
        }
      })
    }
    // Literal-union switch folding. Specializes `dispatch("x", n)`
    // when `dispatch` is a `switch (k) { case ...: return ... }`
    // function whose first param is a closed string-literal union.
    let switch_fold_declines : Array[String] = []
    if opts.phase_enabled("switch-fold") {
      timer.phase("switch-fold", () => {
        let sw = build_switch_fold_table(
          combined,
          explain=if opts.explain { Some(switch_fold_declines) } else { None },
        )
        if !sw.entries.is_empty() {
          combined = switch_fold(combined, sw)
        }
      })
    }
    if opts.explain {
      explain_dispatchers.push("")
      explain_dispatchers.push(
        "literal-union dispatchers: why a call was not specialized",
      )
      explain_dispatchers.push("")
      if switch_fold_declines.length() == 0 {
        explain_dispatchers.push("  nothing declined.")
      }
      for line in switch_fold_declines {
        explain_dispatchers.push("  * " + line)
      }
    }
    // `as const` (and equivalent) array/object inline at use sites.
    // Replaces `NAME[i]` / `NAME.k` with the underlying literal value
    // when NAME is a top-level `const` of all-literal-element shape
    // and every reference is a safe static read.
    combined = if opts.phase_enabled("as-const-inline") {
      timer.phase("as-const-inline", () => as_const_inline_block(combined))
    } else {
      combined
    }
    // Scalar `const` propagation (terser's `reduce_vars`). Shares
    // `as_const_inline`'s walker but is its own phase: different
    // candidates, a different disqualification rule, and `--phases`
    // can only price a phase that corresponds to one rule. Runs before
    // `fold` because the point is to put a literal where `fold` can
    // reach it — `K * 2` folds to nothing, `5 * 2` folds to `10`.
    combined = if opts.phase_enabled("const-scalar-inline") {
      timer.phase("const-scalar-inline", () => {
        const_scalar_inline_block(combined)
      })
    } else {
      combined
    }
    // Discriminant-tag string -> number rewrite. Gated on
    // a bundle-wide no-escape-sink scan; for each closed
    // string-literal discriminated union whose `K` property is
    // never observed outside switch heads and `===`/`!==`
    // comparisons, swap the string tags for small integers.
    //
    // It also needs both escape routes that leave no trace in the
    // bundle's own statements: the export surface (a consumer holding an
    // exported value, or building one for an exported signature, can
    // compare its tag against the original string) and a hand-off
    // through an imported callee.
    let tag_rewrite_declines : Array[String] = []
    combined = if opts.phase_enabled("tag-rewrite") {
      timer.phase("tag-rewrite", () => {
        tag_rewrite_block(
          combined,
          combined_type_aliases,
          Some({
            exported: export_roots,
            externals: imported_bindings(external_imports),
          }),
          interfaces=combined_interfaces,
          explain=if opts.explain { Some(tag_rewrite_declines) } else { None },
        )
      })
    } else {
      combined
    }
    if opts.explain {
      explain_type_tags.push("")
      explain_type_tags.push(
        "typed discriminant tags: why a union kept its strings",
      )
      explain_type_tags.push("")
      if tag_rewrite_declines.length() == 0 {
        explain_type_tags.push("  nothing declined.")
      }
      for line in tag_rewrite_declines {
        explain_type_tags.push("  * " + line)
      }
    }
    // Lift the IIFE-lowered class shape back to native
    // `class Name { … }` syntax. Smaller emit, plus
    // `class_method_dce_block` then operates on the structured
    // form (NativeClassStmt) instead of pattern-matching the
    // prototype-assignment chain.
    combined = timer.phase("iife-class-lift", () => {
      iife_class_lift_block(combined)
    })
    // Strip __super_proto metadata assignments from IIFE bodies that
    // couldn't be lifted to native class syntax. These are pure mtsc
    // internals with no runtime effect once the lift pass has run.
    combined = timer.phase("strip-super-proto", () => {
      strip_super_proto_stmts(combined)
    })
    // `__private_brand__N__x` -> `#x`. Runs AFTER the IIFE lift so the
    // classes that made it to native syntax get real private syntax,
    // and BEFORE everything that reasons about property names — the
    // export surface, class-method DCE and the mangler all need to see
    // `#x`, which is unreachable from outside its class body by
    // construction. See `private_fields.mbt`.
    combined = timer.phase("private-fields", () => {
      lower_private_fields(combined)
    })
    let export_surface : Map[String, Bool] = {}
    timer.phase("export-surface", () => {
      for n in exported_surface_props(combined, export_roots) {
        export_surface[n] = true
      }
    })
    // Class-method DCE: drop methods on native class declarations
    // that nothing in the bundle accesses by name — except the ones
    // the export surface reaches, which the consumer calls, and the
    // ones something OFF the bundle can invoke. Gated on the absence
    // of reflection / dynamic-key access in the bundle.
    //
    // The off-bundle set is computed whether or not property mangling
    // is on: this pass DELETES on the strength of it, so the analysis
    // is a correctness prerequisite rather than an optimization's.
    // `mtsc entry.ts --bundle` with no other flag ran this pass and
    // deleted every method of a class it had handed to `console.log`.
    let method_dce_reasons : Array[String] = []
    combined = if opts.phase_enabled("class-method-dce") {
      let off_bundle = timer.phase("class-method-dce-reach", () => {
        class_members_reachable_off_bundle(
          combined,
          external_import_bindings(external_imports),
        )
      })
      timer.phase("class-method-dce", () => {
        class_method_dce_block(
          combined,
          Some(off_bundle),
          keep=export_surface,
          class_fields=combined_class_fields,
          type_aliases=combined_type_aliases,
          explain=if opts.explain { Some(method_dce_reasons) } else { None },
          reflection=Some(reflection_warnings),
        )
      })
    } else {
      combined
    }
    if opts.explain {
      explain_methods.push("")
      explain_methods.push("unused class methods: what was dropped and why not")
      explain_methods.push("")
      for line in method_dce_reasons {
        explain_methods.push("  " + line)
      }
    }
    // Type-aware constant folding: `typeof x === "string"` /
    // `x === null` etc. when the bound `x` carries a primitive
    // type annotation. Runs BEFORE the regular fold so the
    // resulting `BoolLit(true/false)` feeds into dead-branch
    // elimination.
    let type_fold_sites_before = if opts.explain &&
      opts.phase_enabled("type-fold") {
      count_type_fold_sites(combined)
    } else {
      0
    }
    combined = if opts.phase_enabled("type-fold") {
      timer.phase("type-fold", () => {
        type_fold_block(combined, type_aliases=combined_type_aliases)
      })
    } else {
      combined
    }
    if opts.explain {
      explain_type_checks.push("")
      explain_type_checks.push(
        "type-driven checks: how many the annotations decided",
      )
      explain_type_checks.push("")
      if !opts.phase_enabled("type-fold") {
        explain_type_checks.push("  the phase is disabled.")
      } else if type_fold_sites_before == 0 {
        explain_type_checks.push(
          "  no candidate at all: the bundle contains no `typeof x === \"…\"`, `x === null`, `x === undefined` or `x + \"\"` on a bare binding. The shape this phase decides is absent.",
        )
      } else {
        // Counted, not re-derived: the pass reports how many of its own
        // candidate shapes survived it, so a "0 folded" answer cannot be
        // an artifact of a second implementation of the decision.
        let after = count_type_fold_sites(combined)
        let folded = type_fold_sites_before - after
        explain_type_checks.push(
          "  \{type_fold_sites_before} candidate check(s); \{folded} decided by an annotation in scope.",
        )
        // Which shapes they were. A total made mostly of `x === null`
        // is a pass with nothing to do rather than a lookup that
        // fails: that check is decidable only when the annotation
        // EXCLUDES null, and code writes it exactly when it does not.
        let by_kind = count_type_fold_sites_by_kind(combined)
        let kinds = by_kind.keys().to_array()
        kinds.sort()
        let parts : Array[String] = []
        for k in kinds {
          parts.push("\{k} x\{by_kind.get(k).unwrap_or(0)}")
        }
        if parts.length() > 0 {
          explain_type_checks.push("  still standing: \{parts.join(", ")}.")
        }
        if folded == 0 {
          explain_type_checks.push(
            "  every one was left alone: the binding had no type in scope, or the type it had does not settle the check.",
          )
        }
      }
    }
    // Order: fold -> treeshake -> mangle -> inline -> peephole.
    // Fold turns dead `if (false)` branches into nothing and
    // identity arithmetic into a single operand; treeshake then
    // drops declarations the now-smaller graph never reaches;
    // mangle renames whatever survived; inline collapses single-
    // use bindings into their unique reference; peephole finally
    // compacts the result with `x += y` and `void 0` rewrites.
    if opts.fold {
      combined = timer.phase("fold", () => fold_block(combined))
    }
    // Purity, re-derived on the MERGED block so its names match what
    // treeshake sees. The early run above answers a different question
    // (diagnostics, unconditionally, on the pre-link AST); this one is
    // load-bearing, and a call it clears gets deleted. Anything the
    // proof can't reach stays put — a name absent from this set is
    // simply treated as a side-effect root, exactly as before.
    let proven_pure = if opts.treeshake {
      timer.phase("purity", () => {
        analyze_purity_with(combined, linked_assumed_pure).pure_functions
      })
    } else {
      {}
    }
    if opts.treeshake {
      combined = timer.phase("treeshake", () => {
        treeshake_block(combined, roots=export_roots, pure_calls=proven_pure)
      })
    }
    if opts.mangle {
      // Trailing-parameter trimming. Needs the export roots: an exported
      // function's arity is part of the package ABI, and everything else
      // the proof needs (is `f` ever used as a VALUE rather than called?)
      // is decided from the merged block itself.
      let param_declines : Array[String] = []
      combined = drop_unused_params_block(
        combined,
        plan_unused_params(combined, keep=export_roots, declines=param_declines),
      )
      if opts.explain {
        explain_params.push("")
        explain_params.push(
          "trailing-parameter trimming: why a function kept its arity",
        )
        explain_params.push("")
        if param_declines.length() == 0 {
          explain_params.push("  nothing declined.")
        }
        for line in param_declines {
          explain_params.push("  * " + line)
        }
      }
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
        // Door 1: the bundle's own export surface. Every property
        // name reachable from a value the entry exports is part of
        // the package ABI, whether or not any type declaration
        // mentions it — an exported function returning an inferred
        // `{ first, rest }` publishes those two names as surely as a
        // declared interface would. `type_props.mbt` only sees
        // declared shapes and only in the entry module, so without
        // this walk the dead-property pass happily deleted keys the
        // consumer reads.
        for n in export_surface.keys() {
          extra_reserved.push(n)
        }
        // Recompute on the post-fold block as well: folding can turn a
        // reference into the literal it names, which surfaces keys the
        // first walk could not see through.
        for n in exported_surface_props(combined, export_roots) {
          extra_reserved.push(n)
        }
        // Door 2: values that leave through a sink.
        let externals = external_import_bindings(external_imports)
        // A name the bundle never declares is provided by the host — an
        // ambient global out of a `.d.ts`, or a runtime built-in. Reading
        // a property off one is reading somebody else's ABI, so treat
        // those bindings as external too.
        for n in undeclared_referenced_names(combined).keys() {
          externals[n] = true
        }
        // A `const cfg: Cfg = …` that crosses the boundary reserves only
        // `Cfg`'s keys instead of the wildcard — but only if the analysis
        // can resolve `Cfg`. Without this the narrowing worked for an
        // inline object type and silently didn't for the interface an
        // actual codebase writes.
        let type_env = build_type_env(
          combined_interfaces, combined_type_aliases,
        )
        // The linker's own record of which bindings it synthesized as
        // namespace objects, instead of the structural guess the escape
        // analysis falls back on. The guess — "a `const` initialized to
        // an object literal of bare `Var`s" — also matches every
        // `const handlers = { onClick, onBlur }` and every dispatch
        // table a library writes: on typebox it reserved 300 of the 340
        // names in one section of the report, for two real namespaces.
        let synthesized_namespaces = Some(link_renames.synthesized_namespaces)
        if opts.explain {
          for
            line in format_escape_explanation(
              escape_breakdown(
                combined,
                externals,
                type_env~,
                synthesized_namespaces~,
              ),
            ) {
            explain_escape.push(line)
          }
        }
        let escapes = collect_externally_visible_props(
          combined,
          externals,
          type_env~,
          synthesized_namespaces~,
        )
        let mut wildcard = false
        for n in escapes {
          if n == "*" {
            wildcard = true
          } else {
            extra_reserved.push(n)
          }
        }
        explain_wildcard = wildcard
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
            if !is_internal_marker_property(n) {
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
        // Discriminant tags: a property whose values are a closed set of
        // string literals, read only by equality comparison, and not in
        // the escape set, can be renumbered. Property mangling renames
        // keys, never values, so without this the tag strings survive
        // minification in full even though nothing outside ever sees
        // them.
        if opts.explain {
          explain_fields.push("")
          explain_fields.push("dead class fields: why a write survived")
          explain_fields.push("")
          if explain_wildcard {
            explain_fields.push(
              "  the wildcard above forced every property name in the bundle",
            )
            explain_fields.push(
              "  into the reserved set, so nothing here can proceed.",
            )
          }
          let field_reasons = explain_dead_fields(combined, reserved_set)
          if field_reasons.length() == 0 {
            explain_fields.push("  nothing declined.")
          }
          for line in field_reasons {
            explain_fields.push("  * " + line)
          }
        }
        let tag_declines : Array[String] = []
        combined = apply_discriminant_ints(
          combined,
          plan_discriminant_ints(combined, reserved_set, declines=tag_declines),
        )
        if opts.explain {
          explain_tags.push("")
          explain_tags.push("discriminant tags: why a tag kept its strings")
          explain_tags.push("")
          if explain_wildcard {
            explain_tags.push(
              "  the wildcard above forced every property name in the bundle",
            )
            explain_tags.push(
              "  into the reserved set, so nothing here can proceed.",
            )
          }
          if tag_declines.length() == 0 {
            explain_tags.push("  nothing declined.")
          }
          for line in tag_declines {
            explain_tags.push("  * " + line)
          }
        }
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
      // Names the bundle reads back as `Function.prototype.name`.
      // Renaming a class changes `C.name` and `this.constructor.name`,
      // and superstruct's error base assigns the latter to `this.name`,
      // so `err.name` came back `"a"`. terser renames class names
      // regardless and expects the library to opt out; the read is
      // visible in the source, so pay for the ones actually observed and
      // mangle the rest. See `observed_names.mbt`, including what it
      // does NOT catch.
      let (observed_names, observed_all_ctors) = observed_class_names(combined)
      // Only names that are CONSTRUCTORS. `observed_class_names` reports
      // the identifier on the left of a `.name` read without judging
      // what it holds, and the first version reserved all of them on the
      // theory that a plain object's `.name` costs a few bytes. On the
      // 9 MB TypeScript compiler it cost 282 KB — 7.9%. That bundle
      // never writes `constructor.name`; what it writes is `node.name`,
      // `symbol.name`, `declaration.name` several thousand times, and
      // reserving `node` / `symbol` / `declaration` stops the most common
      // locals in the program from mangling at all.
      //
      // So intersect with the declarations that actually have a
      // meaningful `.name`. A `.name` read on anything else observes an
      // ordinary property and constrains nothing.
      if observed_names.length() > 0 {
        let ctors : Map[String, Bool] = {}
        constructor_like_top_level(combined, ctors)
        for n in observed_names {
          if ctors.contains(n) {
            external_reserved.push(n)
          }
        }
      }
      if observed_all_ctors {
        // `<expr>.constructor.name` names no class syntactically, but
        // `this.constructor` inside a method of `C` is `C` or a subclass
        // — never an unrelated class. So reserve the classes whose own
        // bodies read it, closed over their subclasses, and let the rest
        // of the bundle mangle.
        //
        // The blunt versions were both measured. Reserving every
        // top-level binding: typebox +70%, zod +40%, superstruct +31%.
        // Narrowing to "classes and functions" changed not one byte,
        // because in a library written out of top-level callables that is
        // the same set. The hierarchy is what actually narrows it.
        let (observing, unconstrained) = classes_observing_own_name(combined)
        if unconstrained {
          // The read is outside any top-level class body, so `this` is
          // unconstrained and the hierarchy says nothing. Fall back to
          // every callable — expensive, and the only sound answer here.
          let ctors : Map[String, Bool] = {}
          constructor_like_top_level(combined, ctors)
          for n in ctors.keys() {
            external_reserved.push(n)
          }
        } else {
          for n in observing.keys() {
            external_reserved.push(n)
          }
        }
      }
      // Renaming a binding the bundle EXPORTS BY NAME is not free: the
      // export clause then needs an alias. `export{o}` becomes
      // `export{a as o}`, so the rename costs `len(new) + 4` there and
      // saves `len(orig) - len(new)` at each site. Nobody had priced
      // it, and `compare-terser`'s one remaining LOSS was exactly this:
      //
      //   mtsc:   let a={key:1};console.log(a.key);export{a as o}   47
      //   terser: const o={key:1};console.log(o.key);export{o};     45
      //
      // `o` became `a` — the same length, saving nothing — and paid
      // five bytes for the alias. (The loss was reported under the
      // `computed_props` label, and that rule is ported and firing;
      // the harness names the case, not the cause.)
      //
      // Scoped to the case that needs no cost model at all: a
      // SINGLE-CHARACTER export name. The shortest name the mangler can
      // produce is one character, so renaming such a binding saves
      // exactly nothing at every site and still pays `len(new) + 4` for
      // the alias. It is a loss for any bundle, any reference count, any
      // name the mangler picks.
      //
      // The general rule was implemented and measured and does NOT hold
      // up, so it is not here. `(len(orig) - 1) * sites < 5` — the
      // optimistic bound, taking `len(new) == 1` on both sides, with
      // `sites` from `count_name_references` plus the declaration — gave
      // valibot -54, immer -40, zod -63, excalidraw -231, superstruct
      // -36 and ts-pattern -3, against remeda +291, typebox +267 and
      // neverthrow +37: a net LOSS of about 168 bytes across the ten
      // targets. Break-even (`<=`) was worse still, costing hono 8
      // bytes where the strict form left it identical. Something the
      // arithmetic does not model dominates on the targets that
      // regressed — the reserved names are also withheld from the
      // generated pool, and `count_name_references` can only undercount
      // — and a byte optimization that measures worse overall is not
      // one. The numbers are in the task note so the next attempt
      // starts from them rather than from the formula.
      for name in export_roots.keys() {
        if name.length() == 1 {
          external_reserved.push(name)
        }
      }
      let prop_census : Array[String] = []
      let mangler_cfg = ManglerConfig::default()
        .with_census(if opts.explain { Some(prop_census) } else { None })
        .with_mangle_properties(effective_mangle_props)
        .with_mangle_properties_shape_color(opts.mangle_properties_shape_color)
        .with_reserved_properties(extra_reserved)
        .with_reserved(external_reserved)
        // The bundle has no public ABI of its own — every binding
        // becomes internal once we glue modules together, so the
        // top-level can be renamed freely.
        .with_preserve_top_level(false)
      let (mangled_block, mangle_renames) = timer.phase("mangle", () => {
        mangle_block_with_renames(combined, mangler_cfg)
      })
      combined = mangled_block
      if opts.explain && prop_census.length() > 0 {
        explain_escape.push("")
        explain_escape.push(
          "property mangling: what the mangler had to work with",
        )
        explain_escape.push("")
        for line in prop_census {
          explain_escape.push("  " + line)
        }
      }
      // Carry the mangle pass's rename map forward so the
      // entry-export emit at the bottom can write the right short
      // name for `export default app` even after `app` was
      // renamed to e.g. `aq`.
      mangle_export_renames = mangle_renames
    }
    if opts.minify {
      // The export surface, under whatever names it goes by HERE. The
      // mangler has already run at this point and renames the top level
      // freely, so `export_roots` (what the source called them) matches
      // nothing — the same trap the treeshake call below documents.
      let live_roots : Map[String, Bool] = {}
      for name in export_roots.keys() {
        live_roots[mangle_export_renames.get(name).unwrap_or(name)] = true
      }
      // Inline runs before peephole so `const X = expr; return X`
      // shapes collapse before the peephole pass sees them. Gated
      // on `minify` since the inlining produces deeply nested
      // expressions that are unpleasant in pretty mode.
      //
      // `keep` is the export surface: inlining a single-use binding
      // deletes its declaration, and for an exported name that leaves
      // `export { r }` naming nothing, which is a SyntaxError.
      combined = timer.phase("inline", () => {
        inline_block(combined, keep=live_roots)
      })
      // Second fold pass: inlining can expose new constant-foldable
      // expressions (e.g. `const N = 3; arr[N]` → `arr[3]` → element
      // access on a literal array). Run fold again before peephole so
      // those collapse before the terminal compaction step.
      if opts.fold {
        combined = timer.phase("fold-2", () => fold_block(combined))
        // Second treeshake: the second fold may produce new dead
        // `if (false) { … }` branches whose declarations are now
        // unreachable. A lightweight treeshake pass removes them
        // before the final peephole compaction.
        //
        // The roots have to be the POST-MANGLE names. `export_roots`
        // holds what the source called them, and the mangler renames
        // the top level freely (`preserve_top_level: false`), so the
        // pre-mangle names match nothing here: every root reads as
        // dead and the pass deletes the entire export surface. On hono
        // that turned 18 KB into 4 KB with no `export` clause left —
        // and only with `--mangle --treeshake --fold` together, which
        // is why nothing simpler caught it.
        if opts.treeshake {
          combined = timer.phase("treeshake-2", () => {
            treeshake_block(combined, roots=live_roots, pure_calls=proven_pure)
          })
        }
      }
      combined = timer.phase("peephole", () => peephole_block(combined))
    }
    let has_combined_positions = combined.stmt_positions.length() ==
      combined.stmts.length()
    // In minify mode without source-maps, use the merged-decl emitter so
    // `let a=1;let b=2;` collapses to `let a=1,b=2;` at the top level.
    if opts.minify && !opts.with_sourcemap {
      emit_stmts_merged(e, combined.stmts)
    } else {
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
    }
    // After the combined emit, surface the entry module's exports
    // so the bundle is consumable as an ES module. The mangle path
    // doesn't track its own short-name renames here, so the
    // entry export's `local_name` falls back through link_renames
    // — bindings the mangle pass renamed end up referenced by
    // their pre-mangle (post-link) name and the mangle pass takes
    // care of substituting them since the export ref counts as a
    // use.
    // `entry_export_bindings` already resolved each name through
    // the link renames, so only the mangle pass's renames are
    // left to apply here (`app` -> `aq`). The bundle output's
    // `export default <name>` must use the POST-mangle short form
    // because that's what survives in the body.
    if entry_exports.length() > 0 {
      let declared : Map[String, Bool] = {}
      for n in collect_top_level_decl_names(combined) {
        declared[n] = true
      }
      emit_entry_exports(e, entry_exports, mangle_export_renames, declared)
    }
  } else {
    // The per-module emit keeps each module's statements separate, but
    // the export surface spans the whole graph — an exported class can
    // live in any module. Concatenate a read-only view to analyse.
    let all_stmts : Array[@ast.TsStmt] = []
    for path in order {
      match modules.get(path) {
        Some(node) =>
          for st in node.block.stmts {
            all_stmts.push(st)
          }
        None => ()
      }
    }
    let export_surface : Map[String, Bool] = {}
    for
      n in exported_surface_props(
        { stmts: all_stmts, stmt_positions: [] },
        export_roots,
      ) {
      export_surface[n] = true
    }
    // The same concatenation, lifted, for `class_method_dce_block` to
    // ANALYSE while it rewrites one module at a time.
    //
    // Every question that pass asks is bundle-wide — "which member
    // names does anything access", "does anything read a member under a
    // computed key" — and handing it one module answered both about
    // that module. A class in Excalidraw's `state.ts` lost `addPoint`,
    // `close` and `getStrokeOutline` because the calls are in
    // `shape.ts`, and the bundle then called `laserPointer.addPoint(…)`
    // on an object without one. It reproduces in five lines and one
    // flag: `mtsc entry.ts --bundle` on a class whose methods are
    // called from the importing module deleted EVERY method.
    //
    // Lifted, because the pass matches on `NativeClassStmt`: the
    // unlifted concatenation would look like a bundle with no classes
    // and no accesses. Costs one extra lift of the graph per compile.
    let dce_scope = iife_class_lift_block({
      stmts: all_stmts,
      stmt_positions: [],
    })
    // Over the same bundle-wide scope, and hoisted out of the loop: it
    // is loop-invariant, and computing it per module would be one full
    // escape analysis per file.
    let dce_off_bundle = class_members_reachable_off_bundle(
      dce_scope,
      external_import_bindings(external_imports),
    )
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
      if !opts.minify {
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
      // Per-module emit path. The field annotations and aliases come
      // from the whole graph, not just this module: a computed read
      // here can name a member of a class declared anywhere, so the
      // proofs that clear it have to be assembled the same way.
      let all_class_fields : Array[(String, @ast.TsType)] = []
      let all_type_aliases : Array[@ast.TsTypeAlias] = []
      for other in order {
        match modules.get(other) {
          Some(node) => {
            for f in node.class_fields {
              all_class_fields.push(f)
            }
            for ta in node.type_aliases {
              all_type_aliases.push(ta)
            }
          }
          None => ()
        }
      }
      // `__private_brand__N__x` -> `#x`, on this path too.
      //
      // It only ran in the merged path, which is gated on
      // `--mangle`/`--treeshake`/`--fold`, so plain `mtsc entry.ts
      // --bundle` emitted the brand verbatim — and a brand is an
      // ordinary own ENUMERABLE property, so
      // `class C { #secret = 7 }` printed
      // `{"__private_brand__0__secret":7}` through `JSON.stringify`
      // and showed up in `Object.keys`, where Node gives `{}` and
      // `[]`. Adding any optimization flag fixed it, which is what
      // kept it hidden: every harness that runs this path runs it with
      // flags. Third time a pass has been missing from the per-module
      // emit path — `class_method_dce_block` was the first two.
      //
      // Per-module scope is the right scope: a `#x` reference is legal
      // only inside the class body that declares it, and the one other
      // place mtsc emits one (an accessor lowered out to
      // `Object.defineProperty(C.prototype, KEY, …)`) sits next to that
      // class in the same module. `lower_private_fields`'s own
      // statement-count guard sees both.
      let lifted_block = class_method_dce_block(
        lower_private_fields(iife_class_lift_block(m.block)),
        Some(dce_off_bundle),
        keep=export_surface,
        scope=Some(dce_scope),
        class_fields=all_class_fields,
        type_aliases=all_type_aliases,
        // This path runs the pass once per MODULE over the same
        // bundle-wide scope, so the same reflection call is met once per
        // file. `dedup_reflection_warnings` collapses that at the end.
        reflection=Some(reflection_warnings),
      )
      for j, stmt in lifted_block.stmts {
        if opts.with_sourcemap && j < lifted_block.stmt_positions.length() {
          let src_pos = e.line_index.position(lifted_block.stmt_positions[j])
          e.mark(src_pos)
        }
        emit_stmt(e, stmt)
        e.nl()
      }
      // Per-module emit path: surface the entry module's exports
      // at the tail (mirror of the combined-emit branch above).
      if path == entry {
        let entry_exports = entry_export_bindings(modules, link_renames, entry)
        if entry_exports.length() > 0 {
          // Per-module emit keeps each module's stmts separate, so
          // the "does a binding exist" check spans every module.
          let declared : Map[String, Bool] = {}
          for other in order {
            match modules.get(other) {
              Some(node) =>
                for n in collect_top_level_decl_names(node.block) {
                  declared[n] = true
                }
              None => ()
            }
          }
          emit_entry_exports(e, entry_exports, {}, declared)
        }
      }
    }
  }
  let sm_json : String? = match e.smap {
    Some(b) =>
      Some(b.to_json_multi(sources, sources_content, output_path="bundle.js"))
    None => None
  }
  if opts.explain {
    explain.push("mtsc --explain-mangle")
    for
      section in [
        explain_escape, explain_params, explain_methods, explain_fields, explain_dispatchers,
        explain_type_checks, explain_type_tags, explain_tags,
      ] {
      for line in section {
        explain.push(line)
      }
    }
  }
  Ok({
    js: e.to_string(),
    sourcemap: sm_json,
    modules: module_paths,
    warnings,
    reflection_warnings: dedup_reflection_warnings(reflection_warnings),
    explain,
    timings: timer.entries,
  })
}

// Detect the esbuild-style CJS-wrapper pattern:
//   `var X = {}; ((module) => { ... })(  {get exports(){return X;}, ...}  )`
// and return `X` (the top-level variable that holds the module's exports).

///|
fn detect_cjs_exports_var(block : @ast.TsBlock) -> String? {
  for stmt in block.stmts {
    let call_args = match stmt {
      @ast.TsStmt::Expr(@ast.TsExpr::CallExpr(_, args)) => args
      _ => continue
    }
    if call_args.length() != 1 {
      continue
    }
    let props = match call_args[0] {
      @ast.TsExpr::ObjectLit(p) => p
      _ => continue
    }
    for prop in props {
      let key = prop.0
      if key != "@@get:exports" {
        continue
      }
      let get_body = match prop.1 {
        @ast.TsExpr::FuncExpr(f) => f.body
        @ast.TsExpr::ArrowFunc(_, _, @ast.TsArrowBody::ArrowBlock(b), _) => b
        @ast.TsExpr::ArrowFunc(
          _,
          _,
          @ast.TsArrowBody::ArrowExpr(@ast.TsExpr::Var(v)),
          _
        ) => return Some(v)
        _ => continue
      }
      for s in get_body.stmts {
        match s {
          @ast.TsStmt::Return(Some(@ast.TsExpr::Var(v))) => return Some(v)
          _ => ()
        }
      }
    }
  }
  None
}

///|
/// Record an import the bundle keeps verbatim, deduplicated by BINDING
/// rather than by statement.
///
/// The dedup key used to be `module_spec + ":" + default_binding`, which
/// does not mention the named bindings at all. So the second statement
/// for a specifier was discarded whole:
///
///   // a.ts
///   import { pointsOnBezierCurves } from "points-on-curve";
///   // b.ts
///   import { simplify } from "points-on-curve";   // dropped entirely
///
/// and every call to `simplify` in the bundle became a free variable.
/// Excalidraw calls it from four places; `mtsc --verify` is what
/// reported it (`docs/type-aware-dce.md`, B1). This is the same shape as
/// the module-graph walk that deduplicated on the import SPECIFIER: a
/// key that answers a narrower question than the one being asked.
///
/// Emitting a second `import { simplify } from "points-on-curve"` next
/// to the first is valid ESM as long as the LOCAL names differ, which is
/// what the per-binding key guarantees. Merging into the earlier
/// statement would save a line and would have to rebuild it in place;
/// the risk is not worth the bytes, and `--minify` output has one import
/// clause per statement either way.
fn record_external_import(
  external_imports : Array[@ast.TsImportDecl],
  external_seen : Map[String, Bool],
  imp : @ast.TsImportDecl,
) -> Unit {
  // `import type { X } from "…"` contributes nothing at runtime.
  if imp.type_only {
    return
  }
  let binds_nothing = imp.default_binding is None &&
    imp.namespace_binding is None &&
    imp.named_bindings.length() == 0
  // `import "./x.css"` binds nothing, so one per specifier is right and
  // a second copy would duplicate a side effect.
  if imp.side_effect_only || binds_nothing {
    let key = "effect:" + imp.module_spec
    if not(external_seen.contains(key)) {
      external_seen[key] = true
      external_imports.push(imp)
    }
    return
  }
  fn claim(local : String) -> Bool {
    let key = imp.module_spec + ":bind:" + local
    if external_seen.contains(key) {
      false
    } else {
      external_seen[key] = true
      true
    }
  }

  let default_binding = match imp.default_binding {
    Some(n) => if claim("default:" + n) { Some(n) } else { None }
    None => None
  }
  let namespace_binding = match imp.namespace_binding {
    Some(n) => if claim("ns:" + n) { Some(n) } else { None }
    None => None
  }
  let named_bindings : Array[(String, String)] = []
  let named_type_only : Array[Bool] = []
  for i, pair in imp.named_bindings {
    // A `type` specifier introduces no runtime binding, and emitting one
    // is worse than dropping it: `import { type Point } from "…"` is
    // TypeScript syntax, so the bundle stops being JavaScript. Before
    // the per-binding key below, such specifiers were discarded by luck
    // — the statement carrying them lost the specifier-level dedup — and
    // fixing the dedup surfaced them in Excalidraw's output.
    //
    // Worth noting for `verify.mbt`: it re-parses with the TypeScript
    // parser, so it accepts `type` specifiers and CANNOT catch this
    // class. Node is the oracle that does.
    let is_type_only = i < imp.named_type_only.length() &&
      imp.named_type_only[i]
    if is_type_only {
      continue
    }
    if claim(pair.1) {
      named_bindings.push(pair)
      named_type_only.push(false)
    }
  }
  if default_binding is None &&
    namespace_binding is None &&
    named_bindings.length() == 0 {
    return
  }
  external_imports.push({
    ..imp,
    default_binding,
    namespace_binding,
    named_bindings,
    named_type_only,
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
  // When set, a relative import the vfs cannot resolve is kept
  // verbatim as an external import instead of failing the bundle.
  // Only the CLI sets this, and only because it has already asked the
  // real filesystem: in-memory callers keep the strict behaviour, so a
  // mistyped `./mising` is still an error and not a silent external.
  allow_unresolved : Bool,
  // Parses the caller already did, keyed like `files`. See
  // `BundleOptions.parsed_blocks`.
  parsed : Map[String, @ast.TsModuleBlock],
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
  let mb = match parsed.get(path) {
    Some(cached) => cached
    None =>
      try @parser.Parser::from_source(source).parse_module_block() catch {
        e => return Err("parse \{path}: \{e}")
      } noraise {
        b => b
      }
  }
  // Reuse the per-file JSX pragma extractor so each module honors
  // its own `/** @jsxImportSource ... */` etc.
  let jsx_cfg = extract_jsx_pragmas(source, JsxConfig::default())
  let (lowered_jsx, runtime_refs) = lower_block_with_runtime_imports(
    jsx_cfg,
    mb.block,
  )
  // The automatic runtime turns `<div/>` into a call to an IMPORTED
  // `jsx` / `jsxs` / `Fragment`, so the import has to be emitted or the
  // names resolve to nothing. The single-file path in `emit.mbt` writes
  // it; this one discarded the ref list, so every `.tsx` bundle came out
  // with `jsx`, `jsxs` and `Fragment` free — under plain `mtsc
  // entry.tsx --bundle`, no optimization flag involved. Excalidraw is
  // the target that surfaced it, through `--verify`.
  //
  // Routing it through `record_external_import` rather than emitting it
  // here is the point: that is where external imports are deduplicated
  // per binding and where `link_module_graph` learns which top-level
  // names come from outside the bundle. A hand-written emit would have
  // to reproduce both, and the mangler would rename `jsx` out from under
  // the import if it did not.
  if jsx_cfg.runtime == "automatic" && runtime_refs.length() > 0 {
    let named : Array[(String, String)] = []
    let named_type_only : Array[Bool] = []
    for name in runtime_refs {
      named.push((name, name))
      named_type_only.push(false)
    }
    record_external_import(external_imports, external_seen, {
      module_spec: jsx_cfg.import_source + "/jsx-runtime",
      default_binding: None,
      namespace_binding: None,
      named_bindings: named,
      named_type_only,
      side_effect_only: false,
      type_only: false,
      attributes: [],
    })
  }
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
    source,
    block: lowered,
    resolved_imports: {},
    import_decls: mb.imports,
    pure_declarations: mb.pure_declarations,
    type_aliases: mb.type_aliases,
    interfaces: mb.interfaces,
    class_fields: mb.class_fields,
    export_specs: mb.exports,
    reexport_specs: mb.reexports,
    const_enums: module_const_enums(mb.enums),
    module_request_order: mb.module_request_order,
    type_only_exports: mb.type_only_exports,
    cjs_exports_var: detect_cjs_exports_var(lowered),
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
        // Nothing in the vfs under any extension. That is what a
        // build-generated module looks like from a source checkout —
        // TypeScript's `checker.ts` imports
        // `./_namespaces/ts.performance.js`, which its build emits and
        // the repository does not carry. Treat it the way a bare
        // specifier is treated: keep the import verbatim rather than
        // failing the bundle over a module the caller never had.
        if allow_unresolved && !files.contains(dep_path) {
          record_external_import(external_imports, external_seen, imp)
          continue
        }
        resolved[imp.module_spec] = dep_path
        match
          load_module_graph(
            files, dep_path, modules, external_imports, external_seen, aliases, allow_unresolved,
            parsed,
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
            // A CommonJS module cannot be concatenated into an ES bundle
            // — see `module_is_commonjs`. Keep the import verbatim and
            // let the host resolve it.
            if dep_is_commonjs(files, dep_path, parsed) {
              record_external_import(external_imports, external_seen, imp)
              continue
            }
            resolved[imp.module_spec] = dep_path
            match
              load_module_graph(
                files, dep_path, modules, external_imports, external_seen, aliases,
                allow_unresolved, parsed,
              ) {
              Ok(_) => ()
              Err(e) => return Err(e)
            }
          }
          None =>
            if files.contains(imp.module_spec) {
              let dep_path = resolve_with_extensions(files, imp.module_spec)
              if dep_is_commonjs(files, dep_path, parsed) {
                record_external_import(external_imports, external_seen, imp)
                continue
              }
              resolved[imp.module_spec] = dep_path
              match
                load_module_graph(
                  files, dep_path, modules, external_imports, external_seen, aliases,
                  allow_unresolved, parsed,
                ) {
                Ok(_) => ()
                Err(e) => return Err(e)
              }
            } else {
              record_external_import(external_imports, external_seen, imp)
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
        // Same as the import loop: a relative target the vfs does not
        // have is a module the caller never had. A bare re-export
        // target isn't tracked as external either (see below), so
        // skipping matches the existing behaviour for that case.
        if allow_unresolved && !files.contains(dep_path) {
          continue
        }
        resolved[re.module_spec] = dep_path
        match
          load_module_graph(
            files, dep_path, modules, external_imports, external_seen, aliases, allow_unresolved,
            parsed,
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
                allow_unresolved, parsed,
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
                  allow_unresolved, parsed,
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
  let cjs_exports_var = detect_cjs_exports_var(lowered)
  modules[path] = {
    source,
    block: lowered,
    resolved_imports: resolved,
    import_decls: mb.imports,
    pure_declarations: mb.pure_declarations,
    type_aliases: mb.type_aliases,
    interfaces: mb.interfaces,
    class_fields: mb.class_fields,
    export_specs: mb.exports,
    reexport_specs: mb.reexports,
    const_enums: module_const_enums(mb.enums),
    module_request_order: mb.module_request_order,
    type_only_exports: mb.type_only_exports,
    cjs_exports_var,
  }
  Ok(())
}

///|
/// Build a depth-first dependency order for the entry module: deepest
/// dependency emits first, the entry emits last. Cycles short-circuit
/// at the first repeat to keep emit terminating.
/// The specifiers `node` requests at runtime, in source order.
///
/// The parser records this as one interleaved list because `import_decls`
/// and `reexport_specs` are two arrays and cannot: reading them in turn
/// says "every import, then every re-export", which is a different order
/// from the source whenever a file mixes the two. typebox's `src/index.ts`
/// is a barrel that does — five `export * from` above one `import * as` —
/// and the traversal went down the wrong subtree first.
///
/// Falls back to the two-array reading for a `ModuleNode` built from a
/// block that predates the field (a hand-constructed test fixture, an
/// injected module), so the order is never empty when requests exist.
fn module_request_specs(node : ModuleNode) -> Array[String] {
  if node.module_request_order.length() > 0 {
    return node.module_request_order
  }
  let out : Array[String] = []
  for imp in node.import_decls {
    if imp.type_only {
      continue
    }
    out.push(imp.module_spec)
  }
  for re in node.reexport_specs {
    if re.type_only {
      continue
    }
    out.push(re.module_spec)
  }
  out
}

///|
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
        // Visit dependencies in the SOURCE ORDER of this module's
        // module-request declarations, not in `resolved_imports` map
        // order. That map is keyed by specifier and its iteration order
        // is not the source's, which is invisible on an acyclic graph
        // and decides evaluation order on a cyclic one.
        //
        // ESM evaluates a cycle by depth-first post-order from the
        // entry, in declaration order, and a flat concatenated bundle
        // has exactly one chance to reproduce that. typebox has such a
        // cycle: `indexed/from_object.ts` reads `IntegerKey` from
        // `types/record.ts` in a TOP-LEVEL `new RegExp(IntegerKey)`.
        // Node puts `record.ts` at 204 and `from_object.ts` at 261; the
        // map walk emitted them at 328 and 217, and the bundle threw
        // `Cannot access 'IntegerKey' before initialization` at load.
        //
        // `type_only` imports are skipped for the same reason
        // `load_module_graph` skips them: after erasure there is no
        // module request, so visiting one would order a module that ESM
        // never evaluates at that point.
        for spec in module_request_specs(node) {
          match node.resolved_imports.get(spec) {
            Some(dep) => visit(dep)
            // A bare / external specifier, or one the caller allowed to
            // go unresolved. Nothing to order.
            None => ()
          }
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
        e.write(",")
        e.space()
      }
      e.write("* as ")
      e.write(name)
      wrote_something = true
    }
    None => ()
  }
  if decl.named_bindings.length() > 0 {
    if wrote_something {
      e.write(",")
      e.space()
    }
    e.write("{")
    e.space()
    for i, b in decl.named_bindings {
      if i > 0 {
        e.write(",")
        e.space()
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
    e.space()
    e.write("}")
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
  exports : Array[BundleExport],
  renames : Map[String, String],
  declared : Map[String, Bool],
) -> Unit {
  // Passthrough re-exports of external modules keep their `from`
  // clause: the binding lives in the other package, so there's
  // nothing in the bundle to name.
  for ex in exports {
    match ex.from_external {
      Some(spec) => {
        e.write("export")
        e.space()
        if ex.local_name == "*" && ex.export_name.has_prefix("*:") {
          e.write("*")
        } else if ex.local_name == "*" {
          e.write("* as ")
          e.write(ex.export_name)
        } else {
          e.write("{")
          e.space()
          e.write(ex.local_name)
          if ex.local_name != ex.export_name {
            e.write(" as ")
            e.write(ex.export_name)
          }
          e.space()
          e.write("}")
        }
        e.write(" from ")
        e.write("\"")
        e.write(spec)
        e.write("\"")
        e.semi()
        e.nl()
      }
      None => ()
    }
  }
  // Group default vs named. An export whose local has no top-level
  // binding in the bundle was a type (`export type { T }`, an
  // exported `interface`, …); TypeScript erases those, so emitting
  // them would produce a bundle that fails to load.
  let resolve = (name : String) => renames.get(name).unwrap_or(name)
  let keep = (local_ : String) => {
    declared.is_empty() || declared.contains(local_)
  }
  let default_local : String? = {
    let mut found : String? = None
    for ex in exports {
      if ex.from_external is None &&
        ex.export_name == "default" &&
        keep(resolve(ex.local_name)) {
        found = Some(resolve(ex.local_name))
        break
      }
    }
    found
  }
  let named : Array[(String, String)] = []
  for ex in exports {
    if ex.from_external is Some(_) || ex.export_name == "default" {
      continue
    }
    let local_ = resolve(ex.local_name)
    if !keep(local_) {
      continue
    }
    named.push((local_, ex.export_name))
  }
  match default_local {
    Some(local_) => {
      e.write("export default ")
      e.write(local_)
      e.semi()
      e.nl()
    }
    None => ()
  }
  if named.length() > 0 {
    e.write("export")
    e.space()
    e.write("{")
    e.space()
    for i, pair in named {
      if i > 0 {
        e.write(",")
        e.space()
      }
      if pair.0 == pair.1 {
        e.write(pair.0)
      } else {
        e.write(pair.0)
        e.write(" as ")
        e.write(pair.1)
      }
    }
    e.space()
    e.write("}")
    e.semi()
    e.nl()
  }
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

///|
/// Strip all `__super_proto` property-assignment statements from
/// the block (recursively).  After `iife_class_lift` runs, any
/// remaining `__super_proto` assignments belong to IIFE classes
/// that couldn't be lifted — they are pure mtsc metadata and have
/// no runtime effect.
fn strip_super_proto_stmts(block : @ast.TsBlock) -> @ast.TsBlock {
  let stmts : Array[@ast.TsStmt] = []
  for s in block.stmts {
    let stripped = strip_super_proto_stmt(s)
    match stripped {
      @ast.TsStmt::Empty => ()
      _ => stmts.push(stripped)
    }
  }
  { ..block, stmts, }
}

///|
fn strip_super_proto_stmt(s : @ast.TsStmt) -> @ast.TsStmt {
  match s {
    @ast.TsStmt::PropAssign(_, "__super_proto", _) => Empty
    @ast.TsStmt::Expr(@ast.TsExpr::PropAssignExpr(_, "__super_proto", _)) =>
      Empty
    @ast.TsStmt::Block(b) => Block(strip_super_proto_stmts(b))
    @ast.TsStmt::If(c, t, e) =>
      If(
        c,
        strip_super_proto_stmts(t),
        match e {
          Some(eb) => Some(strip_super_proto_stmts(eb))
          None => None
        },
      )
    @ast.TsStmt::Let(
      b,
      t,
      @ast.TsExpr::CallExpr(@ast.TsExpr::FuncExpr(f), args)
    ) =>
      Let(
        b,
        t,
        CallExpr(FuncExpr({ ..f, body: strip_super_proto_stmts(f.body) }), args),
      )
    @ast.TsStmt::Const(
      b,
      t,
      @ast.TsExpr::CallExpr(@ast.TsExpr::FuncExpr(f), args)
    ) =>
      Const(
        b,
        t,
        CallExpr(FuncExpr({ ..f, body: strip_super_proto_stmts(f.body) }), args),
      )
    @ast.TsStmt::Var(
      b,
      t,
      @ast.TsExpr::CallExpr(@ast.TsExpr::FuncExpr(f), args)
    ) =>
      Var(
        b,
        t,
        CallExpr(FuncExpr({ ..f, body: strip_super_proto_stmts(f.body) }), args),
      )
    _ => s
  }
}

///|
/// Is this module CommonJS (or a UMD wrapper), rather than something that
/// can be concatenated into an ESM bundle?
///
/// Inlining one produces a bundle that cannot load. `module.exports = …`
/// lands verbatim in an ES module, where `module` is not defined, so it
/// throws before anything else can go wrong; the importer's default
/// binding is left a free variable, because nothing declares it; and a
/// NAMED import resolves by luck when the CJS module happens to declare a
/// same-named internal function, which is worse than failing — rename the
/// export (`module.exports = { helper: internalName }`) and the reference
/// silently points at nothing. `import React, { useState } from "react"`
/// against a resolved `react/index.js` produced exactly this, and the
/// same hazard is already recorded for `es6-promise-pool`'s UMD build.
///
/// The test: ESM syntax settles it — a file with `import` / `export` is a
/// module, and the two systems cannot be mixed. Otherwise, a file that
/// references `module`, `exports` or `require` as a VALUE is CommonJS.
/// That reads through a UMD wrapper, where the marker sits inside the
/// factory rather than at the top level, and it uses
/// `collect_var_refs_in_block` — the walk treeshaking relies on — rather
/// than a fresh partial one.
///
/// A false positive costs an inline, not a miscompile: the import is kept
/// verbatim and the host resolves it, which is what a bundler does with
/// any external. So the check is allowed to be blunt.
fn module_is_commonjs(mb : @ast.TsModuleBlock) -> Bool {
  if mb.imports.length() > 0 ||
    mb.exports.length() > 0 ||
    mb.reexports.length() > 0 {
    return false
  }
  let refs : Map[String, Bool] = {}
  collect_var_refs_in_block(mb.block, refs)
  refs.contains("module") ||
  refs.contains("exports") ||
  refs.contains("require")
}

///|
/// Parse `dep_path` once, cache it in `parsed` so the recursive load
/// reuses it, and answer whether it is CommonJS. A parse failure is not
/// this function's business — answer "not CommonJS" and let the recursion
/// report it.
fn dep_is_commonjs(
  files : Map[String, String],
  dep_path : String,
  parsed : Map[String, @ast.TsModuleBlock],
) -> Bool {
  match parsed.get(dep_path) {
    Some(mb) => return module_is_commonjs(mb)
    None => ()
  }
  let source = match files.get(dep_path) {
    Some(s) => s
    None => return false
  }
  let mb = try @parser.Parser::from_source(source).parse_module_block() catch {
    _ => return false
  } noraise {
    b => b
  }
  parsed[dep_path] = mb
  module_is_commonjs(mb)
}
