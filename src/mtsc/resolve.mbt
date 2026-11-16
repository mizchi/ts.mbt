// Module resolution, driven through the host.
//
// The algorithm is the parser's: `@parser.resolve_type_module_specifier_with`
// is the same walk the CLI runs over the real filesystem — relative
// paths with TypeScript's TYPES candidate ordering, `node_modules`
// (`exports` with the `types` condition, `types` / `typings`,
// `typesVersions`, `index.d.ts`, `@types/<name>`), `node:` builtins
// through `@types/node`, tsconfig `paths` / `baseUrl` and package
// `imports` — with every filesystem question asked of the host. That is
// what lets a browser or a wasm-gc embedding check a program that
// imports npm packages: it supplies the files, and resolution is ours.
//
// This file used to carry its own candidate table for relative
// specifiers, "mirroring" the parser's. Two copies of one ordering are
// how a program comes to check differently in the CLI and in the
// library, so it calls the parser's instead.
//
// A host that maps specifiers itself answers first, through
// `MtscHost::resolve_module_name` — TypeScript's `resolveModuleNames`.

///|
/// True for a specifier that names a file rather than a package.
///
/// `.` and `..` count: a package's own modules reach their barrel with
/// `from "."`. Leaving them out makes that edge invisible, and then
/// every type the barrel re-exports reads as unresolved — the same note
/// `is_local_module_specifier` carries in `checker.mbt`, which is why
/// this is one function and not a second copy of the predicate.
fn mtsc_is_relative_specifier(specifier : String) -> Bool {
  is_local_module_specifier(specifier)
}

///|
/// `base` and `name` joined with a single separator.
fn mtsc_join_path(base : String, name : String) -> String {
  if base == "." || base == "" {
    return name
  }
  if base.has_suffix("/") {
    base + name
  } else {
    base + "/" + name
  }
}

///|
/// `path` with `.` and `..` segments resolved away.
///
/// A view into a `String` is not a `String` here, so each segment is
/// `to_owned()` — `s[a:b]` borrows where `String::substring` would copy.
fn mtsc_normalize_path(path : String) -> String {
  let is_abs = path.has_prefix("/")
  let parts : Array[String] = []
  for part_view in path.split("/") {
    let part = part_view.to_owned()
    if part == "" || part == "." {
      continue
    }
    if part == ".." {
      if parts.length() > 0 && parts[parts.length() - 1] != ".." {
        let _ = parts.pop()
        continue
      }
      parts.push("..")
    } else {
      parts.push(part)
    }
  }
  if parts.length() == 0 {
    return if is_abs { "/" } else { "." }
  }
  let mut result = if is_abs { "/" + parts[0] } else { parts[0] }
  for index in 1..<parts.length() {
    result = result + "/" + parts[index]
  }
  result
}

///|
fn mtsc_push_unique(paths : Array[String], path : String) -> Unit {
  if !paths.contains(path) {
    paths.push(path)
  }
}

///|
/// The host's filesystem, seen as a `@parser.ModuleResolutionHost`.
///
/// Every read goes through the operation's `MtscSourceCache`, so a
/// candidate probed by resolution and then loaded is read once, and a
/// miss is asked about once.
priv struct MtscResolutionFs[H] {
  host : H
  cache : MtscSourceCache
}

///|
impl[H : MtscHost] @parser.ModuleResolutionHost for MtscResolutionFs[H] with fn file_exists(
  self,
  path,
) {
  self.cache.read(self.host, path) is Some(_)
}

///|
impl[H : MtscHost] @parser.ModuleResolutionHost for MtscResolutionFs[H] with fn directory_exists(
  self,
  path,
) {
  self.host.directory_exists(path)
}

///|
impl[H : MtscHost] @parser.ModuleResolutionHost for MtscResolutionFs[H] with fn read_file(
  self,
  path,
) {
  self.cache.read(self.host, path)
}

///|
impl[H : MtscHost] @parser.ModuleResolutionHost for MtscResolutionFs[H] with fn realpath(
  self,
  path,
) {
  self.host.realpath(path)
}

///|
/// How one import resolved.
priv enum MtscResolved {
  /// The module is at this path.
  Found(String)
  /// The host said not to follow it.
  Skipped
  /// Nothing resolved it.
  NotFound
}

///|
/// Where `specifier`, imported from `importer`, resolves.
///
/// The host's own answer wins; otherwise the shared resolver runs. A
/// bare specifier's answer is canonicalized with `realpath`, as tsc does
/// for a package file, so one package reached through several pnpm links
/// enters the program once; a relative answer keeps its spelling, which
/// is already relative to a canonical importer.
fn[H : MtscHost] mtsc_resolve_import(
  host : H,
  cache : MtscSourceCache,
  importer : String,
  specifier : String,
) -> MtscResolved {
  match host.resolve_module_name(specifier, importer) {
    ResolvedTo(path) => return Found(mtsc_normalize_path(path))
    External => return Skipped
    UseDefault => ()
  }
  let fs : MtscResolutionFs[H] = { host, cache, }
  match @parser.resolve_type_module_specifier_with(fs, importer, specifier) {
    Some(path) =>
      Found(
        if mtsc_is_relative_specifier(specifier) {
          path
        } else {
          host.realpath(path)
        },
      )
    None => NotFound
  }
}

///|
/// A root file name made absolute-ish against the host's directory.
///
/// A root is allowed to be written relative (`"src/main.ts"`), and the
/// paths the resolver derives for its imports have to agree with it, or
/// one file arrives in the program under two spellings and its
/// declarations resolve from neither.
fn[H : MtscHost] mtsc_root_path(host : H, root : String) -> String {
  if root.has_prefix("/") {
    return mtsc_normalize_path(root)
  }
  mtsc_normalize_path(mtsc_join_path(host.current_directory(), root))
}

///|
/// Should this file be parsed with JSX syntax enabled?
///
/// The extension decides it where the extension says anything, which is
/// how `tsc` decides it; the host's `jsx` option covers the rest. A
/// `.ts` file cannot be parsed as JSX by `tsc` at all (`<T>x` is a type
/// assertion there), so honouring the option for `.ts` is a deliberate
/// widening for embedders who know better, not a claim about `tsc`.
fn mtsc_allow_jsx_for(path : String, options : MtscCompilerOptions) -> Bool {
  if path.has_suffix(".tsx") || path.has_suffix(".jsx") {
    return true
  }
  options.jsx
}
