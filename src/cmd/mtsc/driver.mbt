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
async fn mtsc_compile_all(opts : MtscOptions, entries : Array[String]) -> Int32 {
  // Several entries that only need CHECKING are one program, the way
  // `tsc -p` checks one: each file once, every diagnostic once. Compiling
  // them one at a time re-checks every shared import per entry — a univer
  // package's `include` is a few hundred files over one shared core — and
  // reports a diagnostic in a shared file once per entry that reaches it.
  if entries.length() > 1 &&
    opts.no_emit &&
    !opts.no_check &&
    !opts.bundle &&
    !opts.list_files {
    match mtsc_typecheck_entries(opts, entries) {
      Some(ok) => return if ok { 0 } else { 1 }
      None => ()
    }
  }
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
/// The sources the GRAPH check takes part in: TypeScript, not JavaScript a
/// dependency ships (`tsc` does not check that without `allowJs`). Narrower
/// than `mtsc_is_program_source`, which also admits `.cts` — the graph
/// checker does not handle that yet. A `.d.cts` takes part: it holds
/// declarations only (see `mtsc_type_graph_reads`).
fn mtsc_graph_checks_source(path : String) -> Bool {
  path.has_suffix(".ts") ||
  path.has_suffix(".tsx") ||
  path.has_suffix(".mts") ||
  path.has_suffix(".d.cts")
}

///|
/// Type-check `entries` as ONE program: every graph they reach, loaded
/// into one module map and checked once.
///
/// `None` when the graph cannot be loaded (a resolution the bundler would
/// refuse) or holds no TypeScript, and the caller falls back to compiling
/// entry by entry, which is what this run did before.
async fn mtsc_typecheck_entries(
  opts : MtscOptions,
  entries : Array[String],
) -> Bool? {
  // An entry the graph check would filter out (a `.cts`, a `.js`) must not
  // vanish because its siblings are checkable: the caller then skips its
  // own per-entry check, so the file would be checked by nothing. Any
  // such entry sends the whole run back to the per-entry path.
  for entry in entries {
    if !mtsc_graph_checks_source(entry) {
      return None
    }
  }
  let files : Map[String, String] = Map([])
  let edges : Array[@mtsc_core.MtscModuleEdge] = []
  // Shared across entries: `aliases` remembers a bare specifier's
  // resolution, and the loader skips a file already in `files`, so a
  // module two entries import is read and parsed once.
  let aliases : Map[String, String] = Map([])
  for entry in entries {
    let loaded = mtsc_load_bundle_files(
      entry,
      files,
      aliases,
      opts.externals,
      Map([]),
      false,
      [],
      Map([]),
      edges,
      true,
    )
    guard loaded is Ok(_) else { return None }
  }
  // The files the program holds without any import naming them: the
  // project's type directives, and every `/// <reference path|types>` in a
  // file already loaded — which can reference more, so this runs to a
  // fixpoint. Each is loaded the way an import is, so its own imports come
  // too. A referenced file that cannot be loaded is left out rather than
  // taking the program with it.
  let scanned : Map[String, Unit] = Map([])
  let pending = mtsc_type_directive_roots(opts)
  while true {
    let sources : Array[(String, String)] = []
    for path, source in files {
      if !scanned.contains(path) && mtsc_graph_checks_source(path) {
        sources.push((path, source))
      }
    }
    for entry in sources {
      let (path, source) = entry
      scanned[path] = ()
      for reference in @parser.triple_slash_references(source) {
        let target = match reference.0 {
          "path" =>
            Some(
              mtsc_resolve_existing_for_types(
                mtsc_normalize(mtsc_join_path(mtsc_dirname(path), reference.1)),
              ),
            )
          _ => mtsc_resolve_type_directive(opts, path, reference.1)
        }
        match target {
          Some(t) => if !files.contains(t) { pending.push(t) }
          None => ()
        }
      }
    }
    if pending.length() == 0 {
      break
    }
    for target in pending {
      if files.contains(target) || !mtsc_file_exists(target) {
        continue
      }
      let _ = mtsc_load_bundle_files(
        target,
        files,
        aliases,
        opts.externals,
        Map([]),
        false,
        [],
        Map([]),
        edges,
        true,
      )
    }
    pending.clear()
  }
  let ts_files : Map[String, String] = Map([])
  for path, source in files {
    if mtsc_graph_checks_source(path) {
      ts_files[path] = source
    }
  }
  if ts_files.length() == 0 {
    return None
  }
  Some(
    mtsc_typecheck_graph(
      ts_files,
      edges,
      compiler_options=opts.checker_options,
      context_only=mtsc_context_only_modules(
        ts_files,
        entries,
        opts.skip_lib_check.unwrap_or(false),
      ),
    ),
  )
}

///|
/// The type roots: `typeRoots` as configured, or every `node_modules/@types`
/// from the project's directory up, which is TypeScript's default
/// (`getDefaultTypeRoots`).
async fn mtsc_type_roots(opts : MtscOptions, cwd? : String) -> Array[String] {
  match opts.type_roots {
    Some(roots) => return roots
    None => ()
  }
  let out : Array[String] = []
  let mut dir = match opts.config_dir {
    Some(d) => d
    None => return out
  }
  // `-p packages/app` leaves the directory relative, and a relative walk
  // stops at its own first segment: `packages` has the parent `""`, so the
  // workspace root's `node_modules/@types` — where a monorepo hoists
  // `@types/node` — was never asked. TypeScript walks the ABSOLUTE
  // directory, so this does too.
  if !dir.has_prefix("/") {
    let base = match cwd {
      Some(c) => c
      None => @parser.canonical_file_path(".")
    }
    dir = mtsc_normalize(mtsc_join_path(base, dir))
  }
  while true {
    let candidate = mtsc_normalize(mtsc_join_path(dir, "node_modules/@types"))
    let is_dir = (@fs.kind(candidate) catch { _ => @fs.FileKind::Unknown })
      is @fs.FileKind::Directory
    if is_dir {
      out.push(candidate)
    }
    let parent = mtsc_dirname(dir)
    if parent == dir || parent == "" || parent == "." {
      break
    }
    dir = parent
  }
  out
}

///|
/// Where the type directive `name` (`types: ["node"]`,
/// `/// <reference types="node" />`) resolves from `containing_file`:
/// `name/` in a type root, read as a package directory, and otherwise the
/// `node_modules` walk the types resolver does for an import of `name`.
/// That is TypeScript's primary and secondary lookup.
async fn mtsc_resolve_type_directive(
  opts : MtscOptions,
  containing_file : String,
  name : String,
) -> String? {
  for root in mtsc_type_roots(opts) {
    // A trailing `/` makes the relative specifier a DIRECTORY only.
    match
      @parser.resolve_type_module_specifier(
        mtsc_join_path(root, "__type_root__.ts"),
        "./" + name + "/",
      ) {
      Some(path) => return Some(path)
      None => ()
    }
  }
  @parser.resolve_type_module_specifier(containing_file, name)
}

///|
/// The type directives a PROJECT loads by itself: `types` when the config
/// names them, and otherwise every package directory in every type root
/// (TypeScript's automatic type inclusion).
///
/// Project mode only, which is a stated departure: `tsc file.ts` with no
/// config still includes the `@types` it can see from the working
/// directory. Doing that here would load React's and Express's types into
/// every no-config check in a repository that merely has them installed,
/// and the no-config path is how this repo measures real packages.
async fn mtsc_type_directive_roots(opts : MtscOptions) -> Array[String] {
  let out : Array[String] = []
  let config_dir = match opts.config_dir {
    Some(d) => d
    None => return out
  }
  let containing = mtsc_join_path(config_dir, "__inferred type names__.ts")
  let names = match opts.types {
    Some(names) => names
    None => {
      let found : Array[String] = []
      for root in mtsc_type_roots(opts) {
        for entry in (fs_readdir(root, sort=true) catch { _ => [] }) {
          if entry.has_prefix(".") {
            continue
          }
          // A scoped directory (`@types/@scope`) holds packages one level
          // down, as `@scope/pkg`.
          if entry.has_prefix("@") {
            for
              sub in (fs_readdir(mtsc_join_path(root, entry), sort=true) catch {
                _ => []
              }) {
              found.push(entry + "/" + sub)
            }
          } else {
            found.push(entry)
          }
        }
      }
      found
    }
  }
  for name in names {
    match mtsc_resolve_type_directive(opts, containing, name) {
      Some(path) => out.push(path)
      None => ()
    }
  }
  out
}

///|
/// A declaration file: what `skipLibCheck` skips.
fn mtsc_is_declaration_path(path : String) -> Bool {
  path.has_suffix(".d.ts") ||
  path.has_suffix(".d.mts") ||
  path.has_suffix(".d.cts")
}

///|
/// The modules the check reads for their declarations and does not
/// report on: every declaration file under `skipLibCheck`, and a
/// DEPENDENCY's declaration files always.
///
/// The second half is a deliberate departure from `tsc`, which checks a
/// package's `.d.ts` when `skipLibCheck` is off. A published declaration
/// file `tsc` accepts is the overwhelmingly common case, so a report there
/// is far more likely to be this checker's gap than the package's error,
/// and the user cannot act on it either way; the cost is a MISS on a
/// genuinely broken dependency, which is the affordable direction. A
/// `.ts` SOURCE file reached through `node_modules` (a workspace package
/// whose `types` is its `src/index.ts`) is still checked, as `tsc` checks
/// it.
///
/// A declaration file NAMED as an entry is not a dependency, wherever it
/// lives: `mtsc node_modules/preact/src/index.d.ts --noEmit` asks for that
/// file to be checked, and only `skipLibCheck` exempts it.
fn mtsc_context_only_modules(
  ts_files : Map[String, String],
  entries : Array[String],
  skip_lib_check : Bool,
) -> Map[String, Unit] {
  let named : Map[String, Unit] = Map([])
  for entry in entries {
    named[mtsc_normalize(entry)] = ()
  }
  let out : Map[String, Unit] = Map([])
  for path in ts_files.keys() {
    if !mtsc_is_declaration_path(path) {
      continue
    }
    if skip_lib_check {
      out[path] = ()
    } else if mtsc_is_dependency_path(path) &&
      !named.contains(mtsc_normalize(path)) {
      out[path] = ()
    }
  }
  out
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
  let argv = mtsc_argv()
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
