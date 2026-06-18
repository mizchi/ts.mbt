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
  mut mangle_properties_shape_color : Bool
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
    mangle_properties_shape_color: false,
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
  println("  --mangle-properties       Also rename non-reserved property keys")
  println(
    "  --mangle-properties-shape-color  Use shape-coloring property rename (opt-in, experimental)",
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
      "--mangle-properties" => {
        opts.mangle = true
        opts.mangle_properties = true
      }
      "--mangle-properties-shape-color" => {
        opts.mangle = true
        opts.mangle_properties = true
        opts.mangle_properties_shape_color = true
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
    let source = @fs.read_file(resolved).text() catch {
      e => return Err("read error \{resolved}: \{e}")
    }
    files[resolved] = source
    if disk_path != resolved && !files.contains(disk_path) {
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
    let module_ = @parser.Parser::from_source(source).parse_module() catch {
      _ =>
        @ast.TsModule::{
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
          use_define_for_class_fields: false,
          deprecated_compiler_options: [],
          parameter_property_misuses: [],
          top_level_stmts: [],
        }
    }
    for n in @transform.type_declared_property_names(module_) {
      type_props[n] = true
    }
    for imp in mb.imports {
      if imp.type_only {
        continue
      }
      let spec = imp.module_spec
      if spec.has_prefix("./") || spec.has_prefix("../") || spec.has_prefix("/") {
        let combined = if spec.has_prefix("/") {
          mtsc_normalize(spec)
        } else {
          mtsc_normalize(mtsc_join_path(mtsc_dirname(resolved), spec))
        }
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
          queue.push(found)
        }
        None => ()
      }
    }
    // Re-exports (`export * from "./a"`, `export { X } from "./a"`)
    // also pull `./a` into the bundle. Mirror the import loop.
    for re in mb.reexports {
      if re.type_only {
        continue
      }
      let spec = re.module_spec
      if spec.has_prefix("./") || spec.has_prefix("../") || spec.has_prefix("/") {
        let combined = if spec.has_prefix("/") {
          mtsc_normalize(spec)
        } else {
          mtsc_normalize(mtsc_join_path(mtsc_dirname(resolved), spec))
        }
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
          queue.push(found)
        }
        None => ()
      }
    }
  }
  Ok(())
}

///|
async fn mtsc_resolve_existing(base : String) -> String {
  if mtsc_path_exists(base) {
    return base
  }
  let exts = [".ts", ".tsx", ".js", ".mjs", ".jsx"]
  for ext in exts {
    let cand = base + ext
    if mtsc_path_exists(cand) {
      return cand
    }
  }
  for ext in exts {
    let cand = base + "/index" + ext
    if mtsc_path_exists(cand) {
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
    let aliases : Map[String, String] = {}
    let type_props : Map[String, Bool] = {}
    match
      mtsc_load_bundle_files(
        input_path,
        files,
        aliases,
        opts.externals,
        type_props,
      ) {
      Ok(_) => ()
      Err(e) => {
        println("mtsc: \{e}")
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
          use_define_for_class_fields: false,
          deprecated_compiler_options: [],
          parameter_property_misuses: [],
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
    let bundle_opts = { ..bundle_opts, jsx: jsx_cfg }
    let result = @transform.bundle_modules(files, input_path, bundle_opts)
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
            use_define_for_class_fields: false,
            deprecated_compiler_options: [],
            parameter_property_misuses: [],
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
