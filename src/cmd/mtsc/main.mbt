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
  // Bare specifiers the user wants left as `import … from "<spec>"`
  // in the emitted bundle. Anything not on this list is resolved
  // through node_modules / tsconfig paths and inlined when found.
  externals : Map[String, Bool]
  mut mangle : Bool
  mut mangle_properties : Bool
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
    externals: {},
    mangle: false,
    mangle_properties: false,
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
  println("  --mangle                  Rename non-exported local identifiers")
  println(
    "  --mangle-properties       Also rename non-reserved property keys",
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
      "--external" => {
        if i + 1 >= argv.length() {
          return Err("missing value for --external")
        }
        for raw in argv[i + 1].split(",") {
          let spec = raw.to_string().trim().to_string()
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
  let arr : Array[Byte] = []
  for i = 0; i < s.length(); i = i + 1 {
    arr.push((s[i].to_int() & 0xFF).to_byte())
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
    Some(i) => path.substring(start=0, end=i).to_string()
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
    if disk_path != resolved && not(files.contains(disk_path)) {
      files[disk_path] = source
    }
    let mb = @parser.Parser::from_source(source).parse_module_block() catch {
      e => return Err("parse \{resolved}: \{e}")
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
    match mtsc_load_bundle_files(input_path, files, aliases, opts.externals) {
      Ok(_) => ()
      Err(e) => {
        println("mtsc: \{e}")
        return
      }
    }
    let bundle_opts = @transform.BundleOptions::default()
      .with_mangle(opts.mangle)
      .with_mangle_properties(opts.mangle_properties)
      .with_sourcemap(opts.sourcemap)
      .with_treeshake(opts.treeshake)
      .with_minify(opts.minify)
      .with_fold(opts.fold)
      .with_aliases(aliases)
    let bundle_opts = { ..bundle_opts, jsx: jsx_cfg }
    let result = @transform.bundle_modules(files, input_path, bundle_opts)
    let out = match result {
      Ok(o) => o
      Err(e) => {
        println("mtsc: \{e}")
        return
      }
    }
    match opts.out {
      Some(path) => {
        let js = match out.sourcemap {
          Some(_) => {
            let base = match path.rev_find("/") {
              Some(i) => path[i + 1:path.length()].to_string()
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
        Some(i) => p[i + 1:p.length()].to_string()
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
