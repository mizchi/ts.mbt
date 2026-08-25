// mtsc — minimal TypeScript → JavaScript compiler driver.
//
// Wraps `@transform.transform_source_full` so a TS / TSX file can be
// lowered to plain JavaScript on the command line. The pipeline is:
//
//   parse → JSX-runtime lowering → (optional) identifier mangling →
//   emit
//
// Usage:
//
//   mtsc <input.ts> [--out <file.js>] [--mangle]
//                   [--mangle-properties] [--sourcemap]
//                   [--jsx-runtime automatic|classic]
//                   [--jsx-import-source <pkg>]
//                   [--jsx-dev]
//
// When `--out` is omitted the JS is written to stdout. With
// `--sourcemap`, a v3 map is also written next to the output file
// (`<out>.map`); a `//# sourceMappingURL=` footer is appended to the
// JS so loaders can pick it up. Mangling and source-maps are
// mutually exclusive for now — the source position table doesn't
// survive the rename pass yet.

// Every input is type-checked before it is transformed. `mtsc` uses the
// checker’s strict entry point so diagnostics match `tscheck --strict`, and
// never writes JavaScript when the checker finds an issue.

///|
priv struct MtscOptions {
  mut input : String?
  mut out : String?
  mut bundle : Bool
  mut treeshake : Bool
  mut fold : Bool
  mut minify : Bool
  // Library-mode opt-in. When `true`, every property name that
  // appears in an interface / type alias / class declaration is
  // added to the mangler's reserved set so downstream consumers
  // can still type-check against the emitted bundle. Off by
  // default because plain `--bundle` is self-contained.
  mut reserve_typed_props : Bool
  // Selective library mode: reserve only the property names
  // reachable from the ENTRY module's `export` declarations.
  // Internal helper types declared in the entry (or elsewhere)
  // are still fair game to mangle. External IO surface
  // (`console`, `fetch`, `JSON`, etc.) stays reserved via the
  // built-in globals list in `mangle_safety.mbt`. Off by default;
  // takes precedence over `--reserve-typed-props` when both are set.
  mut reserve_entry_exports : Bool
  // Emit a companion `.d.ts` next to the JS output. Contains only
  // the entry module's exported type surface — internal helper
  // types are omitted. Requires `--bundle`.
  mut dts : Bool
  // Print a warning when a getter's body contains a direct side
  // effect (assignment, call to an impure function, `++` / `--`,
  // etc). Getters in JS are conventionally pure; an impure one
  // is almost always a bug. Off by default to keep output quiet.
  mut warn_impure_getters : Bool
  // Bare specifiers the user wants left as `import … from "<spec>"`
  // in the emitted bundle. Anything not on this list is resolved
  // through node_modules / tsconfig paths and inlined when found.
  externals : Map[String, Bool]
  mut mangle : Bool
  mut mangle_properties : Bool
  // `--explain-mangle`: print why each minify decision went the way it
  // did instead of only doing it. Implies the mangle passes, since a
  // decision has to be made before it can be explained.
  mut explain_mangle : Bool
  mut mangle_properties_shape_color : Bool
  // `--no-check`: skip type-checking. The gate exists because a type
  // error usually means the program is wrong, but it also makes the
  // whole pipeline unreachable for input that is not TypeScript in the
  // first place — a published `.js` bundle, where an object literal
  // grows properties at runtime and every such site reads as an error.
  //
  // It SKIPS rather than demotes. The checker is ~95% of a large
  // compile (29.4 s of 30.6 s on `checker.ts`), and once the caller has
  // said diagnostics must not stop the emit, running it buys output
  // nobody acts on. `tscheck` is the way to see diagnostics without an
  // abort.
  mut no_check : Bool
  // `--timing`: report wall time per pipeline phase. The compile is
  // superlinear in input size and a twenty-pass pipeline gives a guess
  // nothing to stand on, so the passes report instead.
  mut timing : Bool
  mut sourcemap : Bool
  mut jsx_runtime : String?
  mut jsx_import_source : String?
  mut jsx_dev : Bool
  mut help : Bool
}

///|
fn mtsc_options_new() -> MtscOptions {
  {
    input: None,
    out: None,
    bundle: false,
    treeshake: false,
    fold: false,
    minify: false,
    reserve_typed_props: false,
    reserve_entry_exports: false,
    dts: false,
    warn_impure_getters: false,
    externals: {},
    mangle: false,
    mangle_properties: false,
    explain_mangle: false,
    mangle_properties_shape_color: false,
    no_check: false,
    timing: false,
    sourcemap: false,
    jsx_runtime: None,
    jsx_import_source: None,
    jsx_dev: false,
    help: false,
  }
}

///|
fn mtsc_print_usage() -> Unit {
  println("Usage: mtsc <input.ts> [options]")
  println("")
  println("Compile a single TypeScript / TSX entrypoint to JavaScript.")
  println("Type errors are reported and prevent JavaScript output.")
  println("")
  println("Options:")
  println("  --out, -o <file>          Write JS to <file> (default: stdout)")
  println(
    "  --bundle                  Follow relative imports from <input.ts> and emit one bundle",
  )
  println(
    "  --treeshake               Drop top-level declarations unreached from any live stmt (implies --bundle)",
  )
  println(
    "  --minify                  Suppress indentation / newlines / optional whitespace",
  )
  println(
    "  --fold                    Constant-fold identity arithmetic and dead branches (implies --bundle)",
  )
  println(
    "  --external <spec>         Keep this bare-specifier import external (repeatable; comma-separated also OK)",
  )
  println(
    "  --reserve-typed-props     Reserve every property declared in an interface / type alias / class (library mode)",
  )
  println(
    "  --reserve-entry-exports   Reserve only property names reachable from the entry's exports (library mode, selective)",
  )
  println(
    "  --dts                     Emit a companion <out>.d.ts with the entry's exported type surface",
  )
  println(
    "  --warn-impure-getters     Warn when a class getter body has a direct side effect (assign, call, mutation)",
  )
  println("  --mangle                  Rename non-exported local identifiers")
  println(
    "  --mangle-properties       Also rename non-reserved property keys (implies --bundle)",
  )
  println(
    "  --explain-mangle          Report why each minify decision went the way it did",
  )
  println(
    "  --mangle-properties-shape-color  Use shape-coloring property rename (opt-in, experimental)",
  )
  println(
    "  --no-check                Skip type-checking entirely (non-TypeScript input; the check is ~95% of a large compile)",
  )
  println(
    "  --timing                  Report wall time per pipeline phase (implies --bundle)",
  )
  println("  --sourcemap               Emit <out>.map alongside the JS output")
  println("  --jsx-runtime <mode>      `automatic` (default) or `classic`")
  println("  --jsx-import-source <pkg> Override the jsx-runtime import source")
  println("  --jsx-dev                 Use the development JSX runtime")
  println("  --help, -h                Show this help")
}

///|
fn mtsc_parse_args(argv : Array[String]) -> Result[MtscOptions, String] {
  let opts = mtsc_options_new()
  let mut i = 1
  while i < argv.length() {
    let arg = argv[i]
    match arg {
      "--help" | "-h" => {
        opts.help = true
        return Ok(opts)
      }
      "--out" | "-o" => {
        if i + 1 >= argv.length() {
          return Err("missing value for \{arg}")
        }
        opts.out = Some(argv[i + 1])
        i = i + 2
        continue
      }
      "--bundle" => opts.bundle = true
      "--treeshake" => {
        opts.treeshake = true
        opts.bundle = true
      }
      "--minify" => opts.minify = true
      "--fold" => {
        opts.fold = true
        opts.bundle = true
      }
      "--reserve-typed-props" => opts.reserve_typed_props = true
      "--reserve-entry-exports" => opts.reserve_entry_exports = true
      "--dts" => {
        opts.dts = true
        opts.bundle = true
      }
      "--warn-impure-getters" => opts.warn_impure_getters = true
      "--external" => {
        if i + 1 >= argv.length() {
          return Err("missing value for --external")
        }
        for raw in argv[i + 1].split(",") {
          let spec = raw.to_owned().trim().to_owned()
          if spec != "" {
            opts.externals[spec] = true
          }
        }
        i = i + 2
        continue
      }
      "--mangle" => opts.mangle = true
      // Property mangling implies `--bundle`, the way `--treeshake` and
      // `--fold` already do — and for a stronger reason than they have.
      // The escape analysis (both doors, the wildcard, the whole safety
      // story) lives in `bundle_modules`. The single-file path has none
      // of it, so `--mangle-properties` there renamed whatever it liked,
      // including a CJS module's `exports.foo` and the keys of an
      // exported object. A flag whose only safe form is one path should
      // select that path rather than trust the user to.
      "--mangle-properties" => {
        opts.mangle = true
        opts.mangle_properties = true
        opts.bundle = true
      }
      "--explain-mangle" => {
        opts.mangle = true
        opts.mangle_properties = true
        opts.explain_mangle = true
        opts.bundle = true
      }
      "--no-check" => opts.no_check = true
      "--timing" => {
        opts.timing = true
        opts.bundle = true
      }
      "--mangle-properties-shape-color" => {
        opts.mangle = true
        opts.mangle_properties = true
        opts.mangle_properties_shape_color = true
        opts.bundle = true
      }
      "--sourcemap" => opts.sourcemap = true
      "--jsx-runtime" => {
        if i + 1 >= argv.length() {
          return Err("missing value for --jsx-runtime")
        }
        opts.jsx_runtime = Some(argv[i + 1])
        i = i + 2
        continue
      }
      "--jsx-import-source" => {
        if i + 1 >= argv.length() {
          return Err("missing value for --jsx-import-source")
        }
        opts.jsx_import_source = Some(argv[i + 1])
        i = i + 2
        continue
      }
      "--jsx-dev" => opts.jsx_dev = true
      _ =>
        if arg.has_prefix("--") {
          return Err("unknown option: \{arg}")
        } else {
          match opts.input {
            None => opts.input = Some(arg)
            Some(prev) =>
              return Err(
                "unexpected extra positional argument: \{arg} (already have \{prev})",
              )
          }
        }
    }
    i = i + 1
  }
  Ok(opts)
}

///|
fn mtsc_build_jsx_config(opts : MtscOptions) -> @transform.JsxConfig {
  let mut cfg = @transform.JsxConfig::default()
  match opts.jsx_runtime {
    Some(r) => cfg = cfg.with_runtime(r)
    None => ()
  }
  match opts.jsx_import_source {
    Some(s) => cfg = cfg.with_import_source(s)
    None => ()
  }
  if opts.jsx_dev {
    cfg = cfg.with_dev(true)
  }
  cfg
}

///|
fn string_to_utf8_bytes(s : String) -> Bytes {
  // MoonBit's `String` is a sequence of UTF-16 code units. Real
  // UTF-8 encoding has to:
  //   * 1 byte for ASCII (< 0x80)
  //   * 2 bytes for U+0080..U+07FF
  //   * 3 bytes for U+0800..U+FFFF (BMP), excluding the surrogate
  //     range
  //   * 4 bytes for U+10000..U+10FFFF (built from a surrogate
  //     pair: high in U+D800..U+DBFF, low in U+DC00..U+DFFF)
  //
  // The previous implementation kept only the low byte of each
  // unit, which truncated everything ≥ U+0080 and produced
  // mojibake for non-ASCII strings ("regulární" -> "regul�rn�").
  let arr : Array[Byte] = []
  let mut i = 0
  while i < s.length() {
    let unit = s[i].to_int()
    if unit < 0x80 {
      arr.push(unit.to_byte())
      i = i + 1
    } else if unit < 0x800 {
      arr.push(((unit >> 6) | 0xC0).to_byte())
      arr.push(((unit & 0x3F) | 0x80).to_byte())
      i = i + 1
    } else if unit >= 0xD800 && unit < 0xDC00 {
      // High surrogate: combine with the next low surrogate.
      let mut done = false
      if i + 1 < s.length() {
        let lo = s[i + 1].to_int()
        if lo >= 0xDC00 && lo < 0xE000 {
          let cp = (((unit - 0xD800) << 10) | (lo - 0xDC00)) + 0x10000
          arr.push(((cp >> 18) | 0xF0).to_byte())
          arr.push((((cp >> 12) & 0x3F) | 0x80).to_byte())
          arr.push((((cp >> 6) & 0x3F) | 0x80).to_byte())
          arr.push(((cp & 0x3F) | 0x80).to_byte())
          i = i + 2
          done = true
        }
      }
      if !done {
        // Unpaired high surrogate → U+FFFD replacement (`EF BF BD`).
        arr.push((0xEF : Int).to_byte())
        arr.push((0xBF : Int).to_byte())
        arr.push((0xBD : Int).to_byte())
        i = i + 1
      }
    } else if unit >= 0xDC00 && unit < 0xE000 {
      // Stray low surrogate → U+FFFD.
      arr.push((0xEF : Int).to_byte())
      arr.push((0xBF : Int).to_byte())
      arr.push((0xBD : Int).to_byte())
      i = i + 1
    } else {
      arr.push(((unit >> 12) | 0xE0).to_byte())
      arr.push((((unit >> 6) & 0x3F) | 0x80).to_byte())
      arr.push(((unit & 0x3F) | 0x80).to_byte())
      i = i + 1
    }
  }
  Bytes::from_array(arr)
}

///|
async fn write_text(path : String, content : String) -> Bool {
  let _ = @fs.write_file(path, string_to_utf8_bytes(content), create=0o644) catch {
    e => {
      println("write error \{path}: \{e}")
      return false
    }
  }
  true
}

///|
fn mtsc_dirname(path : String) -> String {
  match path.rev_find("/") {
    Some(i) => path[0:i].to_owned()
    None => ""
  }
}

///|
fn mtsc_join_path(dir : String, child : String) -> String {
  if dir == "" {
    child
  } else if dir.has_suffix("/") {
    dir + child
  } else {
    dir + "/" + child
  }
}

///|
fn mtsc_normalize(path : String) -> String {
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

///|
/// An empty `TsModule`, for the paths that need a value but no
/// declarations — a type-side parse that failed, or one that was
/// skipped because nothing downstream reads it.
fn mtsc_empty_module() -> @ast.TsModule {
  {
    funcs: [],
    interfaces: [],
    type_aliases: [],
    imports: [],
    values: [],
    classes: [],
    namespaces: [],
    enums: [],
    module_augmentations: [],
    strict_property_initialization: true,
    no_implicit_any: true,
    strict_null_checks: true,
    use_define_for_class_fields: false,
    deprecated_compiler_options: [],
    parameter_property_misuses: [],
    strict_mode_misuses: [],
    invalid_decorator_uses: [],
    grammar_misuses: [],
    imported_binding_names: [],
    import_module_specs: [],
    class_base_type_args: [],
    param_optional_initializer_misuses: [],
    interface_member_modifier_misuses: [],
    class_dup_diagnostics: [],
    top_level_stmts: [],
  }
}

///|
/// Walk imports starting from `entry_path` and read every reachable
/// file from disk into `files`. Only relative imports (`./x`, `../y`)
/// and rooted paths are followed — bare specifiers (`react`, `@scope/x`)
/// are left to the bundler to emit verbatim.
async fn mtsc_load_bundle_files(
  entry_path : String,
  files : Map[String, String],
  aliases : Map[String, String],
  externals : Map[String, Bool],
  type_props : Map[String, Bool],
  // Whether anything downstream reads `type_props`. Only
  // `--reserve-typed-props` does, and harvesting it costs a full second
  // parse of every file in the graph — 0.9 s of the 2.1 s read+parse
  // phase on 9 MB of `typescript.js`. Skip it when nobody asked.
  want_type_props : Bool,
  // Import / re-export edges discovered along the way, in the shape the
  // graph checker wants: resolution is the CLI's job, and the checker
  // needs the edges to resolve a type declared in another module.
  edges : Array[@mtsc_core.MtscModuleEdge],
) -> Result[Unit, String] {
  // Sequential DFS over the import graph. moonbitlang/async runs on
  // a cooperative single-threaded scheduler, so spawning per-file
  // tasks adds task-group overhead without overlapping any real
  // work — the parser itself stays the dominant CPU cost.
  let queue : Array[String] = [entry_path]
  while queue.length() > 0 {
    let disk_path = queue[queue.length() - 1]
    let _ = queue.pop()
    if files.contains(disk_path) {
      continue
    }
    let resolved = mtsc_resolve_existing(disk_path)
    // A relative import that names no file on disk is not a reason to
    // fail the compile. It is what a build-generated module looks like
    // from a source checkout: TypeScript's own `checker.ts` imports
    // `./_namespaces/ts.performance.js`, which its build produces and
    // the repository does not carry. Treat it the way a bare specifier
    // is treated — leave the import verbatim and move on. The entry
    // file itself is exempt: nothing to compile if that is missing.
    if disk_path != entry_path && !mtsc_file_exists(resolved) {
      println(
        "mtsc: unresolved import \{disk_path} — left as an external import",
      )
      continue
    }
    let source = @fs.read_file(resolved).text() catch {
      e => return Err("read error \{resolved}: \{e}")
    }
    files[resolved] = source
    // The extension-less form is also keyed, so the bundler can look up
    // the specifier a module actually spelled (`./sub` -> `/dir/sub`).
    // But ONLY when resolution just appended an extension. When it went
    // through `<dir>/index.ts`, the alias names a DIRECTORY, and a
    // module keyed by a directory path resolves its own relative
    // imports one level too high: `src/router/trie-router` +
    // `./router` becomes `src/router/router`. Hono hits this on its
    // first router import.
    if disk_path != resolved &&
      resolved.has_prefix(disk_path + ".") &&
      !files.contains(disk_path) {
      files[disk_path] = source
    }
    let mb = @parser.Parser::from_source(source).parse_module_block() catch {
      e => return Err("parse \{resolved}: \{e}")
    }
    // Second-pass parse for the TYPE side. The block parser above
    // only sees runtime statements; interfaces / type aliases /
    // classes live on `TsModule`, so we run a second parse to
    // harvest the property names declared in those type
    // declarations. They get added to the bundler's reserved-prop
    // set so the property mangler never renames a name that's
    // part of any module's public type surface.
    let module_ = if want_type_props {
      @parser.Parser::from_source(source).parse_module() catch {
        _ => mtsc_empty_module()
      }
    } else {
      mtsc_empty_module()
    }
    if want_type_props {
      for n in @transform.type_declared_property_names(module_) {
        type_props[n] = true
      }
    }
    for imp in mb.imports {
      // A type-only import contributes no runtime code, so the bundler
      // skips it — but the CHECKER needs the module that declares the
      // type, or `import type { Loc } from "./types"` leaves `Loc`
      // unresolvable and identical shapes read as mismatches. Load and
      // edge relative type-only imports; a bare one would drag a whole
      // package's declarations in, so those stay skipped.
      let spec = imp.module_spec
      if imp.type_only &&
        !(spec.has_prefix("./") ||
        spec.has_prefix("../") ||
        spec.has_prefix("/")) {
        continue
      }
      if spec.has_prefix("./") || spec.has_prefix("../") || spec.has_prefix("/") {
        let combined = if spec.has_prefix("/") {
          mtsc_normalize(spec)
        } else {
          mtsc_normalize(mtsc_join_path(mtsc_dirname(resolved), spec))
        }
        edges.push({
          importerPath: resolved,
          moduleSpecifier: spec,
          targetPath: mtsc_resolve_existing(combined),
        })
        queue.push(combined)
        continue
      }
      if externals.contains(spec) {
        continue
      }
      if aliases.contains(spec) {
        continue
      }
      match @parser.resolve_runtime_module_specifier(resolved, spec) {
        Some(found) => {
          aliases[spec] = found
          edges.push({
            importerPath: resolved,
            moduleSpecifier: spec,
            targetPath: found,
          })
          queue.push(found)
        }
        None => ()
      }
    }
    // Re-exports (`export * from "./a"`, `export { X } from "./a"`)
    // also pull `./a` into the bundle. Mirror the import loop.
    for re in mb.reexports {
      // Same reasoning as the type-only import above.
      let spec = re.module_spec
      if re.type_only &&
        !(spec.has_prefix("./") ||
        spec.has_prefix("../") ||
        spec.has_prefix("/")) {
        continue
      }
      if spec.has_prefix("./") || spec.has_prefix("../") || spec.has_prefix("/") {
        let combined = if spec.has_prefix("/") {
          mtsc_normalize(spec)
        } else {
          mtsc_normalize(mtsc_join_path(mtsc_dirname(resolved), spec))
        }
        edges.push({
          importerPath: resolved,
          moduleSpecifier: spec,
          targetPath: mtsc_resolve_existing(combined),
        })
        queue.push(combined)
        continue
      }
      if externals.contains(spec) {
        continue
      }
      if aliases.contains(spec) {
        continue
      }
      match @parser.resolve_runtime_module_specifier(resolved, spec) {
        Some(found) => {
          aliases[spec] = found
          edges.push({
            importerPath: resolved,
            moduleSpecifier: spec,
            targetPath: found,
          })
          queue.push(found)
        }
        None => ()
      }
    }
  }
  // Ambient declaration files (`declare const MyGlobal: …`) belong to the
  // program even though nothing imports them — that is the whole point of
  // an ambient declaration. `tsc` picks them up through tsconfig's
  // `include`; with no tsconfig to read, take the `.d.ts` files sitting in
  // the entry's own directory, which is where the `env.d.ts` /
  // `globals.d.ts` convention puts them.
  for ambient in mtsc_sibling_declaration_files(entry_path) {
    if files.contains(ambient) {
      continue
    }
    let source = @fs.read_file(ambient).text() catch {
      // A directory read that fails is not fatal here: the file is
      // supplementary, not part of the module graph.
      _ => continue
    }
    files[ambient] = source
    let parsed = try @parser.Parser::from_source(source).parse_module() catch {
      e => Err(e)
    } noraise {
      m => Ok(m)
    }
    match parsed {
      Ok(module_) =>
        for n in @transform.type_declared_property_names(module_) {
          type_props[n] = true
        }
      Err(_) => ()
    }
  }
  Ok(())
}

///|
/// `.d.ts` files in the same directory as `entry_path`, sorted for a
/// deterministic program. Nested directories are not scanned: an ambient
/// file deeper in the tree belongs to whatever entry sits next to it.
async fn mtsc_sibling_declaration_files(entry_path : String) -> Array[String] {
  let dir = mtsc_dirname(entry_path)
  let names = @fs.readdir(dir, sort=true) catch { _ => return [] }
  let out : Array[String] = []
  for name in names {
    if name.has_suffix(".d.ts") {
      out.push(mtsc_normalize(mtsc_join_path(dir, name)))
    }
  }
  out
}

///|
/// The TypeScript files a JS-spelled specifier may actually name.
/// `./x.js` -> `./x.ts`, `./x.tsx`, `./x.d.ts`; `./x.mjs` -> `./x.mts`;
/// `./x.cjs` -> `./x.cts`. Empty when the path does not end in a JS
/// extension, so the ordinary extension search runs unchanged.
fn mtsc_ts_equivalents(base : String) -> Array[String] {
  for
    pair in [
      (".js", [".ts", ".tsx", ".d.ts"]),
      (".mjs", [".mts", ".d.mts"]),
      (".cjs", [".cts", ".d.cts"]),
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
async fn mtsc_resolve_existing(base : String) -> String {
  if mtsc_file_exists(base) {
    return base
  }
  // A specifier that spells `.js` may name a `.ts` file. That is not a
  // quirk — it is what TypeScript's `node16` / `nodenext` / `bundler`
  // resolution prescribes, so a modern TS codebase writes
  // `import … from "./external.js"` next to `external.ts`. Without this
  // rule the whole class of TypeScript-source targets is unreachable:
  // zod, and TypeScript's own compiler (`./_namespaces/ts.js`), both
  // fail on their first import.
  for cand in mtsc_ts_equivalents(base) {
    if mtsc_file_exists(cand) {
      return cand
    }
  }
  // `.d.ts` is in the list because a declaration-only module is a
  // legitimate target of `import type { X } from "./types"`.
  let exts = [".ts", ".tsx", ".d.ts", ".js", ".mjs", ".jsx"]
  for ext in exts {
    let cand = base + ext
    if mtsc_file_exists(cand) {
      return cand
    }
  }
  for ext in exts {
    let cand = base + "/index" + ext
    if mtsc_file_exists(cand) {
      return cand
    }
  }
  base
}

///|
async fn mtsc_path_exists(path : String) -> Bool {
  @fs.exists(path)
}

///|
/// A path that names a readable FILE. `@fs.exists` also answers `true`
/// for a directory, and a directory is not a module: `import "./client"`
/// next to a `client/` directory used to resolve to the directory
/// itself, and the read then failed with "Is a directory" instead of
/// falling through to `client/index.ts`.
async fn mtsc_file_exists(path : String) -> Bool {
  if !@fs.exists(path) {
    return false
  }
  (@fs.kind(path) catch { _ => return false }) is Regular
}

///|
/// Compatibility wrapper for the command's focused tests. The checker itself
/// lives in `mizchi/ts/mtsc` so the JavaScript module and CLI use one strict
/// implementation.
fn mtsc_collect_type_issues(
  source : String,
  allow_jsx : Bool,
) -> Result[Array[@mtsc_core.MtscTypeIssue], String] {
  @mtsc_core.collect_type_issues(source, allow_jsx)
}

///|
/// Print checker diagnostics for one input and return whether it is clean.
fn mtsc_typecheck_source(source : String, path : String) -> Bool {
  let issues = match mtsc_collect_type_issues(source, path.has_suffix(".tsx")) {
    Ok(issues) => issues
    Err(e) => {
      println("mtsc: parse error in \{path}: \{e}")
      return false
    }
  }
  if issues.length() == 0 {
    return true
  }
  for issue in issues {
    println("mtsc: type error in \{path} [\{issue.path}]: \{issue.message}")
  }
  false
}

///|
/// Print checker diagnostics for a whole resolved module graph and
/// return whether it is clean.
///
/// Only files that look like real modules are handed over: the loader
/// keys `files` by both the resolved path and the extension-less form a
/// specifier spelled (`./sub` -> `/dir/sub`), and passing the same
/// source twice would double every diagnostic.
fn mtsc_typecheck_graph(
  files : Map[String, String],
  edges : Array[@mtsc_core.MtscModuleEdge],
) -> Bool {
  let modules : Array[@mtsc_core.MtscModuleSource] = []
  for path in files.keys() {
    if !mtsc_is_module_path(path) {
      continue
    }
    match files.get(path) {
      Some(source) =>
        modules.push({
          path,
          source,
          allowJsx: path.has_suffix(".tsx") || path.has_suffix(".jsx"),
        })
      None => ()
    }
  }
  let reported : Array[@mtsc_core.MtscGraphIssue] = []
  for issue in @mtsc_core.collect_module_graph_issues({ modules, edges }) {
    // Import-resolution diagnostics are dropped here. They are part of
    // the stricter contract the Vite integration wants, but this CLI
    // cannot tell a type-only use of a value-form import
    // (`import { LocalObj } from "./types"` where `LocalObj` is a type
    // alias — legal TypeScript) from a genuinely missing export, and
    // reporting the first would reject valid programs.
    if issue.path == "import" {
      continue
    }
    reported.push(issue)
  }
  if reported.length() == 0 {
    return true
  }
  for issue in reported {
    println(
      "mtsc: type error in \{issue.modulePath} [\{issue.path}]: \{issue.message}",
    )
  }
  false
}

///|
/// True for a path that names a source file we should type-check.
fn mtsc_is_module_path(path : String) -> Bool {
  path.has_suffix(".ts") ||
  path.has_suffix(".tsx") ||
  path.has_suffix(".mts") ||
  path.has_suffix(".js") ||
  path.has_suffix(".mjs") ||
  path.has_suffix(".jsx")
}

///|
#cfg(any(target="native", target="llvm"))
extern "c" fn mtsc_native_exit(code : Int) = "exit"

///|
#cfg(target="js")
extern "js" fn mtsc_js_try_exit(code : Int) -> Bool =
  #| function(code) {
  #|   if (typeof process !== "undefined" && typeof process.exit === "function") {
  #|     process.exit(code);
  #|     return true;
  #|   }
  #|   return false;
  #| }

///|
#cfg(target="wasm")
fn mtsc_wasm_exit(code : Int) -> Unit = "wasi_snapshot_preview1" "proc_exit"

///|
#cfg(target="wasm-gc")
fn mtsc_wasm_gc_exit(code : Int) -> Unit = "__moonbit_sys_unstable" "exit"

///|
#cfg(any(target="native", target="llvm"))
fn mtsc_exit_type_error() -> Unit {
  mtsc_native_exit(1)
}

///|
#cfg(target="js")
fn mtsc_exit_type_error() -> Unit {
  if !mtsc_js_try_exit(1) {
    panic()
  }
}

///|
#cfg(target="wasm")
fn mtsc_exit_type_error() -> Unit {
  mtsc_wasm_exit(1)
}

///|
#cfg(target="wasm-gc")
fn mtsc_exit_type_error() -> Unit {
  mtsc_wasm_gc_exit(1)
}

///|
async fn main {
  let argv = @env.args()
  if argv.length() < 2 {
    mtsc_print_usage()
    return
  }
  let opts = match mtsc_parse_args(argv) {
    Ok(o) => o
    Err(e) => {
      println("mtsc: \{e}")
      mtsc_print_usage()
      return
    }
  }
  if opts.help {
    mtsc_print_usage()
    return
  }
  let input_path = match opts.input {
    Some(p) => p
    None => {
      println("mtsc: no input file")
      mtsc_print_usage()
      return
    }
  }
  if opts.mangle && opts.sourcemap {
    println(
      "mtsc: --mangle and --sourcemap can't be combined yet (source positions don't survive the rename pass)",
    )
    return
  }
  let jsx_cfg = mtsc_build_jsx_config(opts)
  let output_path = match opts.out {
    Some(p) => p
    None => "output.js"
  }
  if opts.bundle {
    let files : Map[String, String] = {}
    let edges : Array[@mtsc_core.MtscModuleEdge] = []
    let aliases : Map[String, String] = {}
    let type_props : Map[String, Bool] = {}
    // `--timing` covers the CLI's own work too. The transform pipeline
    // reports its own phases, but the first measurement of `checker.ts`
    // put 731 ms of 31.6 s inside them — everything that mattered was
    // out here.
    let cli_timer = if opts.timing {
      @transform.PhaseTimer::new()
    } else {
      @transform.PhaseTimer::disabled()
    }
    let load_started = @bench.monotonic_clock_start()
    match
      mtsc_load_bundle_files(
        input_path,
        files,
        aliases,
        opts.externals,
        type_props,
        opts.reserve_typed_props,
        edges,
      ) {
      Ok(_) => ()
      Err(e) => {
        println("mtsc: \{e}")
        return
      }
    }
    cli_timer.record(
      "cli: read + parse files",
      @bench.monotonic_clock_end(load_started),
    )
    // Type-check the whole graph in one go. Checking each file alone
    // leaves every imported type unresolvable, which both hides real
    // errors and invents fake ones — an identical shape compared against
    // an imported alias reads as a mismatch.
    if !opts.no_check {
      let check_started = @bench.monotonic_clock_start()
      let check_ok = mtsc_typecheck_graph(files, edges)
      cli_timer.record(
        "cli: typecheck",
        @bench.monotonic_clock_end(check_started),
      )
      if !check_ok {
        mtsc_exit_type_error()
        return
      }
    }
    // `type_props` collects every property name declared in an
    // interface / type alias / class across the input. We DON'T
    // feed it to the bundler by default: in bundle mode the type
    // contract is erased at runtime (the bundle is self-contained,
    // so no consumer can see the original property names through
    // TypeScript reflection). The harvested list lives behind
    // `--reserve-typed-props` for the library-emission scenario
    // where the bundle's types DO escape and would type-check
    // against a downstream consumer.
    let extra_reserved : Array[String] = []
    if opts.reserve_entry_exports {
      // Re-parse the entry to walk its `export` declarations + the
      // type signatures they reach. This is what the user is
      // actually publishing in the companion `.d.ts`, so everything
      // else (helper interfaces, internal type aliases) is fair
      // game for the property mangler.
      let entry_source = match files.get(input_path) {
        Some(s) => s
        None => ""
      }
      if entry_source != "" {
        let block = (try
          @parser.parse_module_block_from_source(entry_source)
        catch {
          e => Err(e)
        } noraise {
          v => Ok(v)
        }).or({
          block: { stmts: [], stmt_positions: [] },
          imports: [],
          exports: [],
          reexports: [],
          enums: [],
          internal_names: {},
          deprecations: {},
          pure_declarations: {},
          type_aliases: [],
          interfaces: [],
          class_fields: [],
          has_export_equals: false,
        })
        let module_ = (try
          @parser.parse_module_from_source_with_const_values(entry_source, {})
        catch {
          e => Err(e)
        } noraise {
          v => Ok(v)
        }).or(@ast.TsModule::{
          funcs: [],
          interfaces: [],
          type_aliases: [],
          imports: [],
          values: [],
          classes: [],
          namespaces: [],
          enums: [],
          module_augmentations: [],
          strict_property_initialization: true,
          no_implicit_any: true,
          strict_null_checks: true,
          use_define_for_class_fields: false,
          deprecated_compiler_options: [],
          parameter_property_misuses: [],
          strict_mode_misuses: [],
          invalid_decorator_uses: [],
          grammar_misuses: [],
          imported_binding_names: [],
          import_module_specs: [],
          class_base_type_args: [],
          param_optional_initializer_misuses: [],
          interface_member_modifier_misuses: [],
          class_dup_diagnostics: [],
          top_level_stmts: [],
        })
        let local_names : Array[String] = []
        for ex in block.exports {
          local_names.push(ex.local_name)
        }
        for n in @transform.entry_export_property_names(module_, local_names) {
          extra_reserved.push(n)
        }
      }
    } else if opts.reserve_typed_props {
      for n in type_props.keys() {
        extra_reserved.push(n)
      }
    }
    let bundle_opts = @transform.BundleOptions::default()
      .with_mangle(opts.mangle)
      .with_mangle_properties(opts.mangle_properties)
      .with_mangle_properties_shape_color(opts.mangle_properties_shape_color)
      .with_sourcemap(opts.sourcemap)
      .with_treeshake(opts.treeshake)
      .with_minify(opts.minify)
      .with_fold(opts.fold)
      .with_aliases(aliases)
      .with_extra_reserved_props(extra_reserved)
      .with_explain(opts.explain_mangle)
      // The loader above already asked the filesystem about every
      // relative import and printed a line for each one that is not
      // there, so the bundler doesn't need to fail over them a second
      // time — it keeps them verbatim.
      .with_allow_unresolved_imports(true)
      .with_timing(opts.timing)
    let bundle_opts = { ..bundle_opts, jsx: jsx_cfg }
    let bundle_started = @bench.monotonic_clock_start()
    let result = @transform.bundle_modules(files, input_path, bundle_opts)
    let bundle_micros = @bench.monotonic_clock_end(bundle_started)
    let out = match result {
      Ok(o) => o
      Err(e) => {
        println("mtsc: \{e}")
        return
      }
    }
    if opts.warn_impure_getters {
      for w in out.warnings {
        println("mtsc: " + w)
      }
    }
    for line in out.explain {
      println(line)
    }
    if opts.timing {
      // The bundle's own phases, then the difference — what
      // `bundle_modules` spent outside any instrumented pass (linking,
      // escape analysis, emit).
      let mut inner = 0.0
      for t in out.timings {
        cli_timer.record(t.0, t.1)
        inner = inner + t.1
      }
      let unattributed = bundle_micros - inner
      if unattributed > 0.0 {
        cli_timer.record("bundle: link + escape + emit", unattributed)
      }
      for line in cli_timer.report() {
        println(line)
      }
    }
    match opts.out {
      Some(path) => {
        let js = match out.sourcemap {
          Some(_) => {
            let base = match path.rev_find("/") {
              Some(i) => path[i + 1:path.length()].to_owned()
              None => path
            }
            out.js + "\n//# sourceMappingURL=" + base + ".map\n"
          }
          None => out.js
        }
        if !write_text(path, js) {
          return
        }
        match out.sourcemap {
          Some(map_json) => {
            let _ = write_text(path + ".map", map_json)
          }
          None => ()
        }
        if opts.dts {
          // Emit the companion `.d.ts`. Strip a trailing `.js`
          // from the output path (if present) before appending
          // `.d.ts` so `bundle.js` becomes `bundle.d.ts` rather
          // than `bundle.js.d.ts`.
          let dts_path = if path.has_suffix(".js") {
            path[0:path.length() - 3].to_owned() + ".d.ts"
          } else {
            path + ".d.ts"
          }
          let entry_source = match files.get(input_path) {
            Some(s) => s
            None => ""
          }
          let entry_block = (try
            @parser.parse_module_block_from_source(entry_source)
          catch {
            e => Err(e)
          } noraise {
            v => Ok(v)
          }).or({
            block: { stmts: [], stmt_positions: [] },
            imports: [],
            exports: [],
            reexports: [],
            enums: [],
            internal_names: {},
            deprecations: {},
            pure_declarations: {},
            type_aliases: [],
            interfaces: [],
            class_fields: [],
            has_export_equals: false,
          })
          let entry_module = (try
            @parser.parse_module_from_source_with_const_values(entry_source, {})
          catch {
            e => Err(e)
          } noraise {
            v => Ok(v)
          }).or(@ast.TsModule::{
            funcs: [],
            interfaces: [],
            type_aliases: [],
            imports: [],
            values: [],
            classes: [],
            namespaces: [],
            enums: [],
            module_augmentations: [],
            strict_property_initialization: true,
            no_implicit_any: true,
            strict_null_checks: true,
            use_define_for_class_fields: false,
            deprecated_compiler_options: [],
            parameter_property_misuses: [],
            strict_mode_misuses: [],
            invalid_decorator_uses: [],
            grammar_misuses: [],
            imported_binding_names: [],
            import_module_specs: [],
            class_base_type_args: [],
            param_optional_initializer_misuses: [],
            interface_member_modifier_misuses: [],
            class_dup_diagnostics: [],
            top_level_stmts: [],
          })
          // Filter exports through the entry's `@internal` set so
          // anything tagged `/** @internal */` is invisible to
          // downstream consumers' type-checks even when the JS
          // bundle still ships the runtime binding.
          let local_names : Array[String] = []
          for ex in entry_block.exports {
            if !entry_block.internal_names.contains(ex.local_name) {
              local_names.push(ex.local_name)
            }
          }
          let dts_text = @transform.emit_entry_dts(
            entry_module,
            local_names,
            entry_block.deprecations,
          )
          let _ = write_text(dts_path, dts_text)
        }
      }
      None => println(out.js)
    }
    return
  }
  let source = @fs.read_file(input_path).text() catch {
    e => {
      println("mtsc: read error \{input_path}: \{e}")
      return
    }
  }
  if !mtsc_typecheck_source(source, input_path) && !opts.no_check {
    mtsc_exit_type_error()
    return
  }
  let result = @transform.transform_source_full(
    source,
    jsx_cfg,
    with_sourcemap=opts.sourcemap,
    source_path=input_path,
    output_path~,
    mangle=opts.mangle,
    mangle_properties=opts.mangle_properties,
    minify=opts.minify,
  )
  let out = match result {
    Ok(o) => o
    Err(e) => {
      println("mtsc: \{e}")
      return
    }
  }
  let js = match (out.sourcemap, opts.out) {
    (Some(_), Some(p)) => {
      let base = match p.rev_find("/") {
        Some(i) => p[i + 1:p.length()].to_owned()
        None => p
      }
      out.js + "\n//# sourceMappingURL=" + base + ".map\n"
    }
    _ => out.js
  }
  match opts.out {
    Some(path) => {
      if !write_text(path, js) {
        return
      }
      match out.sourcemap {
        Some(map_json) => {
          let _ = write_text(path + ".map", map_json)
        }
        None => ()
      }
    }
    None => println(js)
  }
}
