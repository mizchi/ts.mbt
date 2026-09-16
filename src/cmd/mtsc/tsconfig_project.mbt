// `mtsc -p` — compiling a project rather than a named file.
//
// Two behaviours come from `tsc` and had no spelling in mtsc at all:
// `mtsc` with no file arguments looks for `tsconfig.json` in the working
// directory, and `-p` / `--project` takes either a directory holding one
// or the config path itself.
//
// `@parser.load_tsconfig_project` answers what the config SAYS. This
// file turns that into a list of entry paths, which is a directory walk
// and a glob matcher — deliberately on this side of the boundary,
// because the loader in `main.mbt` already owns the filesystem and its
// caches.
//
// The glob support is `tsc`'s three forms and nothing else: `*` (any
// characters within one path segment), `?` (one character within a
// segment) and `**/` (any number of segments). That is the whole of what
// `include` / `exclude` accept, so there is no fourth form to get wrong.

///|
/// Where a `-p` value, or a bare invocation, finds its config.
///
/// `tsc -p x` accepts both `x/tsconfig.json` and `x` naming a directory,
/// and distinguishing them needs the filesystem rather than the string —
/// a path with no `.json` suffix can still be a file.
async fn mtsc_resolve_project_config(project : String?) -> String? {
  match project {
    None => {
      let cand = "tsconfig.json"
      if mtsc_file_exists(cand) {
        Some(cand)
      } else {
        None
      }
    }
    Some(p) => {
      if mtsc_file_exists(p) {
        return Some(p)
      }
      let joined = mtsc_normalize(mtsc_join_path(p, "tsconfig.json"))
      if mtsc_file_exists(joined) {
        return Some(joined)
      }
      None
    }
  }
}

///|
/// Does `name` match glob `pattern` within a single path segment?
///
/// `*` and `?` only; `**` is handled a level up, by the segment walk,
/// because it is about the number of SEGMENTS rather than about
/// characters. Backtracking is the straightforward recursive form: a
/// pattern here is a handful of characters, so there is nothing to gain
/// from a table.
fn mtsc_glob_segment_matches(pattern : String, name : String) -> Bool {
  fn go(pi : Int, ni : Int) -> Bool {
    if pi >= pattern.length() {
      return ni >= name.length()
    }
    // A `String` indexes UTF-16 code units, so the character comes back
    // through `to_int()`. Comparison stays unit-by-unit on both sides,
    // which is equality for every path a filesystem can hand back.
    match pattern[pi].to_int().unsafe_to_char() {
      '*' => {
        // Try every split, shortest first.
        let mut skip = ni
        while skip <= name.length() {
          if go(pi + 1, skip) {
            return true
          }
          skip = skip + 1
        }
        false
      }
      '?' => ni < name.length() && go(pi + 1, ni + 1)
      _ =>
        ni < name.length() &&
        name[ni].to_int() == pattern[pi].to_int() &&
        go(pi + 1, ni + 1)
    }
  }

  go(0, 0)
}

///|
/// Does the path `segments` match the glob `pattern_segments`?
///
/// A `**` segment matches any number of segments, including none, which
/// is why this is a segment-level recursion rather than one pass.
fn mtsc_glob_path_matches(
  pattern_segments : Array[String],
  segments : Array[String],
) -> Bool {
  fn go(pi : Int, si : Int) -> Bool {
    if pi >= pattern_segments.length() {
      return si >= segments.length()
    }
    if pattern_segments[pi] == "**" {
      let mut skip = si
      while skip <= segments.length() {
        if go(pi + 1, skip) {
          return true
        }
        skip = skip + 1
      }
      return false
    }
    if si >= segments.length() {
      return false
    }
    if !mtsc_glob_segment_matches(pattern_segments[pi], segments[si]) {
      return false
    }
    go(pi + 1, si + 1)
  }

  go(0, 0)
}

///|
/// Split a path into its non-empty segments.
fn mtsc_path_segments(path : String) -> Array[String] {
  let out : Array[String] = []
  for part in path.split("/") {
    let p = part.to_owned()
    if p != "" && p != "." {
      out.push(p)
    }
  }
  out
}

///|
/// Expand one `include` pattern the way `tsc` does before matching it.
///
/// A pattern with no extension and no wildcard names a DIRECTORY, and
/// `tsc` reads it as "everything under it" — `"include": ["src"]` is
/// `src/**/*`. Getting this wrong is silent: the pattern matches the
/// directory itself, nothing under it, and the program comes out empty.
fn mtsc_expand_include_pattern(pattern : String) -> String {
  if pattern.contains("*") || pattern.contains("?") {
    return pattern
  }
  for
    ext in [
      ".ts", ".tsx", ".mts", ".cts", ".d.ts", ".js", ".jsx", ".mjs", ".cjs",
    ] {
    if pattern.has_suffix(ext) {
      return pattern
    }
  }
  if pattern.has_suffix("/") {
    pattern + "**/*"
  } else {
    pattern + "/**/*"
  }
}

///|
/// Does this path name a file `tsc` would put in a program?
///
/// `.d.ts` is in, because a declaration file is part of the program even
/// though it emits nothing. `.json` is not: `resolveJsonModule` pulls one
/// in through an import, never through `include`.
fn mtsc_is_program_source(path : String) -> Bool {
  if path.has_suffix(".d.ts") {
    return true
  }
  for ext in [".ts", ".tsx", ".mts", ".cts"] {
    if path.has_suffix(ext) {
      return true
    }
  }
  false
}

///|
/// The default `exclude` set, which applies when the config names none.
///
/// `tsc` also excludes the configured `outDir`, which is why that is a
/// parameter rather than a constant here: compiling a project whose
/// previous output sits under `dist/` would otherwise read its own
/// emitted `.d.ts` files back in as sources.
fn mtsc_default_excludes(out_dir : String?) -> Array[String] {
  let out = [
    "**/node_modules/**", "**/bower_components/**", "**/jspm_packages/**",
  ]
  match out_dir {
    Some(d) => {
      let trimmed = if d.has_suffix("/") {
        d[0:d.length() - 1].to_owned()
      } else {
        d
      }
      if trimmed != "" && trimmed != "." {
        out.push(trimmed + "/**")
      }
    }
    None => ()
  }
  out
}

///|
/// Walk `dir` recursively, collecting every program source under it.
///
/// `node_modules` is pruned during the WALK rather than filtered after
/// it. The difference is not cosmetic: a project with dependencies
/// installed has more files under `node_modules` than in its own source
/// tree by two or three orders of magnitude, and an exclude applied
/// afterwards still pays for reading all of them.
async fn mtsc_collect_sources(dir : String, out : Array[String]) -> Unit {
  let names = @fs.readdir(dir, sort=true) catch { _ => return }
  for name in names {
    if name == "node_modules" ||
      name == "bower_components" ||
      name == "jspm_packages" ||
      name.has_prefix(".") {
      continue
    }
    let path = mtsc_normalize(mtsc_join_path(dir, name))
    let kind = @fs.kind(path) catch { _ => @fs.FileKind::Unknown }
    match kind {
      @fs.FileKind::Directory => mtsc_collect_sources(path, out)
      @fs.FileKind::Regular =>
        if mtsc_is_program_source(path) {
          out.push(path)
        }
      _ => ()
    }
  }
}

///|
/// The entry paths a project names, in a deterministic order.
///
/// `files` wins over `include` the way `tsc` orders them: an explicit
/// `files` list is the program, and `include` only adds to it. A config
/// that names neither gets TypeScript's default of everything under the
/// config's own directory.
async fn mtsc_project_entries(
  project : @parser.TsconfigProject,
  out_dir : String?,
) -> Array[String] {
  let root = if project.root_dir == "" { "." } else { project.root_dir }
  let selected : Array[String] = []
  let seen : Map[String, Bool] = Map([])
  fn add(path : String) -> Unit {
    let p = mtsc_normalize(path)
    if seen.contains(p) {
      return
    }
    seen[p] = true
    selected.push(p)
  }

  // `files` entries are exact paths and are NOT filtered by `exclude`
  // — `tsc` treats them as a deliberate listing.
  for f in project.files {
    add(mtsc_join_path(root, f))
  }
  let patterns : Array[String] = []
  for p in project.include_ {
    patterns.push(mtsc_expand_include_pattern(p))
  }
  // No `include` and no `files` means everything under the config's
  // directory. No `include` but a `files` list means exactly that list.
  if patterns.length() == 0 {
    if project.files.length() > 0 {
      return selected
    }
    patterns.push("**/*")
  }
  let excludes = if project.exclude.length() > 0 {
    let e : Array[String] = []
    for x in project.exclude {
      e.push(mtsc_expand_include_pattern(x))
    }
    e
  } else {
    mtsc_default_excludes(out_dir)
  }
  let candidates : Array[String] = []
  mtsc_collect_sources(root, candidates)
  let root_segments = mtsc_path_segments(root)
  for cand in candidates {
    // Match patterns against the path RELATIVE to the config's
    // directory, which is what `include` is written against.
    let all = mtsc_path_segments(cand)
    let rel : Array[String] = []
    let skip = if all.length() >= root_segments.length() {
      root_segments.length()
    } else {
      0
    }
    for i in skip..<all.length() {
      rel.push(all[i])
    }
    let mut included = false
    for pattern in patterns {
      if mtsc_glob_path_matches(mtsc_path_segments(pattern), rel) {
        included = true
        break
      }
    }
    if !included {
      continue
    }
    let mut excluded = false
    for pattern in excludes {
      if mtsc_glob_path_matches(mtsc_path_segments(pattern), rel) {
        excluded = true
        break
      }
    }
    if excluded {
      continue
    }
    add(cand)
  }
  selected
}

///|
/// Read the `compilerOptions` a project sets and apply them UNDER the
/// command line.
///
/// Precedence is the one `tsc` uses and the one `mtsc_build_jsx_config`
/// already applies to the JSX settings: tsconfig first, the command line
/// over it. So each option is only taken from the config when the flag
/// left it at its default, which is why every arm tests the current
/// value first.
async fn mtsc_apply_project_compiler_options(
  opts : MtscOptions,
  config_path : String,
) -> Unit {
  match @parser.tsconfig_compiler_option_at(config_path, "outDir") {
    Some(d) =>
      if opts.out_dir is None && opts.out is None {
        opts.out_dir = Some(
          mtsc_normalize(mtsc_join_path(mtsc_dirname(config_path), d)),
        )
      }
    None => ()
  }
  match @parser.tsconfig_compiler_option_at(config_path, "outFile") {
    Some(f) =>
      if opts.out is None && opts.out_dir is None {
        opts.out = Some(
          mtsc_normalize(mtsc_join_path(mtsc_dirname(config_path), f)),
        )
      }
    None => ()
  }
  match @parser.tsconfig_compiler_option_bool_at(config_path, "noEmit") {
    Some(v) => if !opts.no_emit { opts.no_emit = v }
    None => ()
  }
  match @parser.tsconfig_compiler_option_bool_at(config_path, "declaration") {
    Some(v) =>
      if !opts.dts && v {
        opts.dts = true
        opts.bundle = true
      }
    None => ()
  }
  match
    @parser.tsconfig_compiler_option_bool_at(config_path, "emitDeclarationOnly") {
    Some(v) =>
      if v {
        opts.dts = true
        opts.dts_only = true
        opts.bundle = true
      }
    None => ()
  }
  match @parser.tsconfig_compiler_option_bool_at(config_path, "sourceMap") {
    Some(v) => if !opts.sourcemap { opts.sourcemap = v }
    None => ()
  }
  match @parser.tsconfig_compiler_option_bool_at(config_path, "noCheck") {
    Some(v) => if !opts.no_check { opts.no_check = v }
    None => ()
  }
  // The JSX settings are NOT read here. `mtsc_build_jsx_config` already
  // reads them per entry, searching up from the entry's own directory,
  // which is the more precise answer in a monorepo where a package's
  // config overrides the base it extends. Reading them twice would mean
  // two precedence orders that can disagree.
}

///|
/// `--showConfig`: print what the resolved configuration comes to.
///
/// `tsc --showConfig` prints the merged tsconfig as JSON. This prints
/// the same information in the same shape for the options mtsc acts on,
/// and does not invent entries for the ones it accepted without effect —
/// a config dump that lists `"strict": true` when nothing reads it would
/// be the silent-acceptance failure this CLI exists to avoid.
fn mtsc_print_show_config(
  opts : MtscOptions,
  config_path : String?,
  entries : Array[String],
) -> Unit {
  println("{")
  match config_path {
    Some(p) => println("  \"configFilePath\": \"\{p}\",")
    None => ()
  }
  println("  \"compilerOptions\": {")
  let rows : Array[String] = []
  match opts.out {
    Some(v) => rows.push("    \"outFile\": \"\{v}\"")
    None => ()
  }
  match opts.out_dir {
    Some(v) => rows.push("    \"outDir\": \"\{v}\"")
    None => ()
  }
  rows.push("    \"noEmit\": \{opts.no_emit}")
  rows.push("    \"noCheck\": \{opts.no_check}")
  rows.push("    \"declaration\": \{opts.dts}")
  rows.push("    \"emitDeclarationOnly\": \{opts.dts_only}")
  rows.push("    \"sourceMap\": \{opts.sourcemap}")
  match opts.jsx_runtime {
    Some(v) => rows.push("    \"jsx\": \"\{v}\"")
    None => ()
  }
  match opts.jsx_import_source {
    Some(v) => rows.push("    \"jsxImportSource\": \"\{v}\"")
    None => ()
  }
  println(rows.join(",\n"))
  println("  },")
  let quoted : Array[String] = []
  for e in entries {
    quoted.push("    \"\{e}\"")
  }
  println("  \"files\": [")
  println(quoted.join(",\n"))
  println("  ]")
  println("}")
}

///|
/// The starter `tsconfig.json` `--init` writes.
///
/// Deliberately short, and every entry in it is one mtsc honours. `tsc
/// --init` writes a long commented template covering its whole option
/// surface; reproducing that here would fill a new project's config with
/// options this compiler accepts and ignores.
fn mtsc_init_tsconfig_text() -> String {
  let lines = [
    "{", "  \"compilerOptions\": {", "    // mtsc always type-checks strictly and always emits",
    "    // current-syntax ESM, so `strict`, `target` and `module` are", "    // accepted for tsc compatibility and have no effect.",
    "    \"strict\": true,", "    \"target\": \"es2022\",", "    \"module\": \"esnext\",",
    "    \"moduleResolution\": \"bundler\",", "    // Honoured by mtsc:", "    \"outDir\": \"dist\",",
    "    \"declaration\": true,", "    \"sourceMap\": false,", "    \"jsx\": \"react-jsx\"",
    "  },", "  \"include\": [\"src\"],", "  \"exclude\": [\"node_modules\", \"dist\"]",
    "}", "",
  ]
  lines.join("\n")
}
