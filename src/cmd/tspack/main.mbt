// tspack — TypeScript → JS bundler CLI.
//
// Reads a TS entrypoint and every relative-path import it
// transitively reaches, runs the transform pipeline at the
// chosen optimization profile, and writes a single JS bundle.
//
// Usage:
//   tspack <entry.ts>                       # bundle to stdout
//   tspack <entry.ts> -o <out.js>           # write to file
//   tspack <entry.ts> --profile full         # full optimizations
//   tspack <entry.ts> --sourcemap            # also write <out>.map
//   tspack --help

///|
fn tspack_print_usage() -> Unit {
  println("Usage: tspack <entry.ts> [options]")
  println("")
  println("Bundle a TypeScript entrypoint and its relative-path imports.")
  println("")
  println("Options:")
  println("  -o, --out <path>             Write JS to <path> (default: stdout)")
  println("  --profile <dev|prod|full>    Optimization profile (default: dev)")
  println("                                 dev  = no optimization")
  println("                                 prod = tree-shake + method DCE (safe)")
  println("                                 full = tree-shake + mangle + inline + fold")
  println("  --sourcemap                  Emit `<out>.map` alongside the JS")
  println("  --minify                     Strip whitespace + section comments")
  println("  --inline-sourcemap           Embed the source map as a data URI")
  println("                                 (`//# sourceMappingURL=data:…`)")
  println("                                 — requires --sourcemap")
  println("  --root <dir>                 Resolve relative imports against <dir>")
  println("                                 (default: directory of <entry.ts>)")
  println("  --help                       Print this message and exit")
}

///|
fn parse_profile(s : String) -> @ts.BundleProfile? {
  match s {
    "dev" | "development" => Some(Development)
    "prod" | "production" => Some(Production)
    "full" => Some(Full)
    _ => None
  }
}

///|
fn directory_of(path : String) -> String {
  match path.rev_find("/") {
    Some(idx) => path.substring(start=0, end=idx).to_string()
    None => "."
  }
}

///|
fn normalize_posix(path : String) -> String {
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
fn join_paths(a : String, b : String) -> String {
  if a == "" {
    return b
  }
  if a.has_suffix("/") {
    a + b
  } else {
    a + "/" + b
  }
}

///|
/// Walk the dependency graph rooted at `entry_path`, reading every
/// reachable TS file from disk into a `Map[String, String]` VFS.
/// The bundler does its own re-resolution against the VFS, so we
/// don't need to be precise about extensions here — just slurp
/// each path the bundler would try.
async fn collect_files_into_vfs(
  entry_path : String,
  root_dir : String,
  files : Map[String, String],
) -> Bool {
  // Normalize the entry path relative to root.
  let rel_entry = if entry_path.has_prefix(root_dir + "/") {
    entry_path.substring(start=root_dir.length() + 1, end=entry_path.length()).to_string()
  } else {
    entry_path
  }
  collect_from_path(rel_entry, root_dir, files)
}

///|
async fn collect_from_path(
  rel_path : String,
  root_dir : String,
  files : Map[String, String],
) -> Bool {
  if files.contains(rel_path) {
    return true
  }
  // Try the exact path, then `.ts`, `.tsx`, `.js`, `.mjs`, then index.
  let probed = probe_extensions(rel_path, root_dir)
  let actual = match probed {
    Some(p) => p
    None => {
      println("tspack: module not found: " + rel_path)
      return false
    }
  }
  let abs = join_paths(root_dir, actual)
  let source = @fs.read_file(abs).text() catch {
    _ => {
      println("tspack: read error: " + abs)
      return false
    }
  }
  files[actual] = source
  // Crudely scan for `from "./..."` / `from '../..'` to discover
  // dependencies. We don't need full parsing here — the bundler
  // will re-resolve when it runs, this pre-load just makes sure
  // every reachable file is in the VFS.
  let dir = directory_of(actual)
  for spec in extract_relative_specifiers(source) {
    let combined = if dir == "" { spec } else { dir + "/" + spec }
    let dep_rel = normalize_posix(combined)
    if !collect_from_path(dep_rel, root_dir, files) {
      return false
    }
  }
  true
}

///|
async fn probe_extensions(rel_path : String, root_dir : String) -> String? {
  let candidates : Array[String] = [
    rel_path,
    rel_path + ".ts",
    rel_path + ".tsx",
    rel_path + ".js",
    rel_path + ".mjs",
    rel_path + ".jsx",
    rel_path + "/index.ts",
    rel_path + "/index.tsx",
    rel_path + "/index.js",
    rel_path + "/index.mjs",
  ]
  for c in candidates {
    let abs = join_paths(root_dir, c)
    if @fs.exists(abs) {
      return Some(c)
    }
  }
  None
}

///|
/// Crude regex-free scan for `from "./foo"` / `from '../bar'`
/// import / export specifiers. Skips bare specifiers (`from
/// "react"`) since those aren't local files.
fn extract_relative_specifiers(source : String) -> Array[String] {
  let out : Array[String] = []
  let mut i = 0
  let n = source.length()
  while i < n {
    // Look for `from`
    if i + 4 < n &&
      source[i] == 'f' &&
      source[i + 1] == 'r' &&
      source[i + 2] == 'o' &&
      source[i + 3] == 'm' &&
      (i == 0 ||
        source[i - 1] == ' ' ||
        source[i - 1] == '\t' ||
        source[i - 1] == '\n' ||
        source[i - 1] == '}' ||
        source[i - 1] == '*') {
      // Skip `from` + whitespace.
      let mut j = i + 4
      while j < n &&
        (source[j] == ' ' || source[j] == '\t' || source[j] == '\n') {
        j = j + 1
      }
      // Now at quote.
      if j < n && (source[j] == '"' || source[j] == '\'') {
        let quote = source[j]
        let start = j + 1
        let mut k = start
        while k < n && source[k] != quote {
          k = k + 1
        }
        if k < n && k > start {
          let spec = source.substring(start=start, end=k).to_string()
          if spec.has_prefix("./") || spec.has_prefix("../") || spec.has_prefix("/") {
            out.push(spec)
          }
        }
        i = k + 1
        continue
      }
    }
    i = i + 1
  }
  out
}

///|
async fn write_or_print(content : String, out : String?) -> Bool {
  match out {
    Some(path) => {
      @fs.write_file(path, content, create=0o644) catch {
        e => {
          println("tspack: write error \{path}: \{e}")
          return false
        }
      }
      println("tspack: wrote " + path)
      true
    }
    None => {
      println(content)
      true
    }
  }
}

///|
async fn main {
  let argv = @env.args()
  if argv.length() < 2 {
    tspack_print_usage()
    return
  }
  let mut entry : String? = None
  let mut out_path : String? = None
  let mut profile : @ts.BundleProfile = Development
  let mut want_sourcemap = false
  let mut want_minify = false
  let mut want_inline_sourcemap = false
  let mut root_dir : String? = None
  let mut i = 1
  while i < argv.length() {
    let arg = argv[i]
    if arg == "--help" || arg == "-h" {
      tspack_print_usage()
      return
    } else if (arg == "-o" || arg == "--out") && i + 1 < argv.length() {
      out_path = Some(argv[i + 1])
      i = i + 2
      continue
    } else if arg == "--profile" && i + 1 < argv.length() {
      match parse_profile(argv[i + 1]) {
        Some(p) => profile = p
        None => {
          println("tspack: unknown profile: " + argv[i + 1])
          return
        }
      }
      i = i + 2
      continue
    } else if arg == "--sourcemap" {
      want_sourcemap = true
    } else if arg == "--minify" {
      want_minify = true
    } else if arg == "--inline-sourcemap" {
      want_inline_sourcemap = true
      want_sourcemap = true
    } else if arg == "--root" && i + 1 < argv.length() {
      root_dir = Some(argv[i + 1])
      i = i + 2
      continue
    } else if !arg.has_prefix("-") && entry is None {
      entry = Some(arg)
    } else {
      println("tspack: unknown arg: " + arg)
      tspack_print_usage()
      return
    }
    i = i + 1
  }
  let entry_path = match entry {
    Some(e) => e
    None => {
      println("tspack: no entry file")
      tspack_print_usage()
      return
    }
  }
  let resolved_root = match root_dir {
    Some(r) => r
    None => directory_of(entry_path)
  }
  // Load every reachable TS file into a VFS map keyed by path
  // relative to `resolved_root`.
  let files : Map[String, String] = {}
  if !collect_files_into_vfs(entry_path, resolved_root, files) {
    return
  }
  let rel_entry = if entry_path.has_prefix(resolved_root + "/") {
    entry_path.substring(start=resolved_root.length() + 1, end=entry_path.length()).to_string()
  } else {
    entry_path
  }
  // Build options. We layer sourcemap on top of the profile
  // when --sourcemap is set.
  let mut opts = profile.to_options()
  if want_sourcemap {
    opts = { ..opts, with_sourcemap: true }
  }
  if want_minify {
    opts = { ..opts, minify: true }
  }
  if want_inline_sourcemap {
    opts = { ..opts, inline_sourcemap: true }
  }
  let result = @ts.bundle_files_with(files, rel_entry, opts)
  match result {
    Ok(out) => {
      if !write_or_print(out.js, out_path) {
        return
      }
      if want_sourcemap {
        match out.sourcemap {
          Some(json) => {
            let map_path : String = match out_path {
              Some(p) => p + ".map"
              None => "bundle.js.map"
            }
            @fs.write_file(map_path, json, create=0o644) catch {
              e => {
                println("tspack: write sourcemap error: \{e}")
                return
              }
            }
            println("tspack: wrote " + map_path)
          }
          None => ()
        }
      }
    }
    Err(e) => println("tspack: bundle error: " + e)
  }
}
