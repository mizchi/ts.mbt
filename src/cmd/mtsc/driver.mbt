// `main` and the run loop around `mtsc_compile_entry`.
//
// Split out of `main.mbt` because that file is the compile pipeline and
// this is the command line: the dispatch between the tsc-compatible
// compiler and the four verbs, resolving entries from `-p` or the
// argument list, running one entry per input, and the `--watch` loop
// over all of them.

///|
/// Name every file in the program, once each.
///
/// The loader keys `files` by BOTH the resolved path and the
/// extension-less form a specifier spelled (`./sub` -> `/dir/sub`), so
/// an unfiltered dump names most modules twice. `mtsc_is_module_path`
/// is the same filter the graph type-check applies for the same reason.
fn mtsc_list_program_files(files : Map[String, String]) -> Unit {
  let names : Array[String] = []
  for path in files.keys() {
    if mtsc_is_module_path(path) || path.has_suffix(".d.ts") {
      names.push(path)
    }
  }
  names.sort()
  for name in names {
    println(name)
  }
}

///|
/// Replace a source extension with `.js`.
fn mtsc_js_output_name(path : String) -> String {
  for ext in [".tsx", ".ts", ".mts", ".cts", ".jsx", ".mjs", ".cjs"] {
    if path.has_suffix(ext) {
      return path[0:path.length() - ext.length()].to_owned() + ".js"
    }
  }
  path + ".js"
}

///|
/// Where one entry's JavaScript goes.
///
/// `None` means stdout, which is mtsc's existing default and the one
/// `tsc` does not have. `--outDir` mirrors the input's basename under
/// the directory; the full `rootDir`-relative tree `tsc` reproduces
/// needs a `rootDir` model, and flattening is the honest subset — which
/// is why `--rootDir` is in the accepted-no-effect tier rather than
/// looking supported.
fn mtsc_entry_output_path(opts : MtscOptions, input_path : String) -> String? {
  match opts.out_dir {
    Some(dir) =>
      Some(
        mtsc_normalize(
          mtsc_join_path(dir, mtsc_js_output_name(mtsc_basename(input_path))),
        ),
      )
    None => opts.out
  }
}

///|
/// Compile every entry. Returns the number that failed.
///
/// All of them are attempted even after one fails, because `tsc` reports
/// every file's diagnostics rather than stopping at the first, and a
/// caller fixing a build wants the whole list.
async fn mtsc_compile_all(opts : MtscOptions, entries : Array[String]) -> Int {
  let mut failed = 0
  for entry in entries {
    // `--out` names ONE file, so it cannot serve several entries. Using
    // it for each in turn would leave only the last, silently.
    let out_override = if entries.length() > 1 && opts.out_dir is None {
      match opts.out {
        Some(_) => {
          println(
            "mtsc: --out names one file but \{entries.length()} inputs were given; use --outDir",
          )
          return entries.length()
        }
        None => None
      }
    } else {
      mtsc_entry_output_path(opts, entry)
    }
    if !mtsc_compile_entry(opts, entry, out_override) {
      failed = failed + 1
    }
  }
  failed
}

///|
/// Resolve the entries for this run: the command line's inputs, or the
/// project a `-p` (or a bare invocation) points at.
///
/// Returns `None` when there is nothing to compile and the reason has
/// already been reported.
async fn mtsc_resolve_entries(opts : MtscOptions) -> (Array[String], String?)? {
  // Explicit inputs win over a project, matching `tsc`: naming files on
  // the command line ignores `tsconfig.json` entirely.
  if opts.inputs.length() > 0 {
    if opts.project is Some(_) {
      println(
        "mtsc: -p is ignored when input files are named (tsc does the same)",
      )
    }
    return Some((opts.inputs, None))
  }
  let config_path = match mtsc_resolve_project_config(opts.project) {
    Some(p) => p
    None =>
      match opts.project {
        Some(p) => {
          println("mtsc: cannot find a tsconfig.json at \{p}")
          return None
        }
        None => {
          println(
            "mtsc: no input files, and no tsconfig.json in this directory",
          )
          return None
        }
      }
  }
  let project = match @parser.load_tsconfig_project(config_path) {
    Some(p) => p
    None => {
      println("mtsc: cannot read \{config_path}")
      return None
    }
  }
  mtsc_apply_project_compiler_options(opts, config_path)
  let entries = mtsc_project_entries(project, opts.out_dir)
  if entries.length() == 0 {
    println(
      "mtsc: \{config_path} matched no input files (check its `files` / `include`)",
    )
    return None
  }
  Some((entries, Some(config_path)))
}

///|
/// The four verbs, so the dispatch and the "is this a verb" test cannot
/// disagree about the set.
fn mtsc_is_verb(token : String) -> Bool {
  match token {
    "check" | "conformance" | "bridge" | "pkg" => true
    _ => false
  }
}

///|
async fn main {
  let argv = @env.args()
  if argv.length() < 2 {
    // A bare `mtsc` in a directory with a tsconfig.json is a compile,
    // the way a bare `tsc` is. With no config it is a help request,
    // which is what mtsc has always done with no arguments.
    if mtsc_resolve_project_config(None) is Some(_) {
      mtsc_run_compile(mtsc_options_new())
      return
    }
    mtsc_print_usage()
    return
  }
  // A verb wins over a same-named file. See the note at the top of
  // `main.mbt`: `mtsc ./check` still names the file.
  if mtsc_is_verb(argv[1]) {
    match argv[1] {
      "check" => mtsc_run_check(argv, 2)
      "conformance" => mtsc_run_conformance(argv, 2)
      "bridge" => @ts.run_bridge_cli(argv, 2)
      "pkg" => @ts.run_pkg_cli(argv, 2)
      _ => ()
    }
    return
  }
  let opts = match mtsc_parse_args(argv, 1) {
    Ok(o) => o
    Err(e) => {
      println("mtsc: \{e}")
      // `tsc` reports a bad command line as a diagnostic and exits
      // non-zero. mtsc used to print this and exit 0, so a typo in a
      // build script was invisible.
      mtsc_exit(MTSC_EXIT_DIAGNOSTICS)
      return
    }
  }
  if opts.help {
    mtsc_print_usage()
    return
  }
  if opts.version {
    println("Version \{@ts.CLI_VERSION} (mtsc, mizchi/ts)")
    return
  }
  if opts.init {
    let path = "tsconfig.json"
    if mtsc_file_exists(path) {
      println("mtsc: \{path} already exists")
      mtsc_exit(MTSC_EXIT_DIAGNOSTICS)
      return
    }
    if write_text(path, mtsc_init_tsconfig_text()) {
      println("Created a new tsconfig.json with the recommended settings")
    } else {
      mtsc_exit(MTSC_EXIT_DIAGNOSTICS)
    }
    return
  }
  mtsc_report_ignored(opts)
  mtsc_run_compile(opts)
}

///|
/// Resolve the entries and compile them, once or on every change.
async fn mtsc_run_compile(opts : MtscOptions) -> Unit {
  let (entries, config_path) = match mtsc_resolve_entries(opts) {
    Some(v) => v
    None => {
      mtsc_exit(MTSC_EXIT_DIAGNOSTICS)
      return
    }
  }
  if opts.show_config {
    mtsc_print_show_config(opts, config_path, entries)
    return
  }
  if opts.watch {
    mtsc_watch_loop(opts, entries)
    return
  }
  let failed = mtsc_compile_all(opts, entries)
  if failed > 0 {
    // Diagnostics were reported and nothing was written for the entries
    // that failed — `tsc`'s exit code 1. Its code 2 is the other case,
    // diagnostics WITH output, which this pipeline cannot reach: a
    // failing check stops the emit, and `--noCheck` produces no
    // diagnostics to report. Falling through is exit 0.
    mtsc_exit(MTSC_EXIT_DIAGNOSTICS)
  }
}
