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
  let source = @fs.read_file(input_path).text() catch {
    e => {
      println("mtsc: read error \{input_path}: \{e}")
      return
    }
  }
  let jsx_cfg = mtsc_build_jsx_config(opts)
  let output_path = match opts.out {
    Some(p) => p
    None => "output.js"
  }
  let result = @transform.transform_source_full(
    source,
    jsx_cfg,
    with_sourcemap=opts.sourcemap,
    source_path=input_path,
    output_path~,
    mangle=opts.mangle,
    mangle_properties=opts.mangle_properties,
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
