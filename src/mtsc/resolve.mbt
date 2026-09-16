// Module resolution, driven through the host.
//
// `src/parser/module_resolver.mbt` already resolves modules — npm
// `exports`, `typesVersions`, `node:*`, `@types/*`, tsconfig `paths` —
// and none of it is reachable from here, because every one of its 26
// entry points is `async` over a real filesystem. That resolver is what
// the CLI uses. This one answers the smaller question a
// `LanguageServiceHost` can answer synchronously: given an importer and
// a specifier, which path does the host hold the module at?
//
// What it covers is RELATIVE specifiers, which is the part a bundler
// plugin and an in-memory program actually need, with TypeScript's
// candidate ordering. What it does not cover is bare specifiers
// (`react`, `node:fs`, `@types/*`): resolving those means reading
// directories and package manifests, and a host that can do it can also
// resolve the specifier itself and say so through
// `MtscResolvedModule`. That limit is reported rather than guessed at —
// an unresolved relative import becomes a diagnostic, an unresolved bare
// one is left alone, which is the existing `graph_import_globals`
// behaviour and the reason this file adds no rule of its own for it.

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
/// The directory containing `path`.
fn mtsc_dirname(path : String) -> String {
  let normalized = mtsc_normalize_path(path)
  match normalized.rev_find("/") {
    Some(0) => "/"
    Some(index) => normalized[:index].to_owned()
    None => "."
  }
}

///|
/// `path` without its trailing `suffix`.
fn mtsc_strip_suffix(path : String, suffix : String) -> String {
  path[:path.length() - suffix.length()].to_owned()
}

///|
fn mtsc_push_unique(paths : Array[String], path : String) -> Unit {
  if !paths.contains(path) {
    paths.push(path)
  }
}

///|
/// Paths `specifier` could name, most-preferred first.
///
/// This is the TYPES ordering, which is the one a type checker wants: a
/// `.d.ts` beats the implementation it describes, because that is the
/// file carrying the declarations. The ordering mirrors
/// `append_resolution_candidates` in `src/parser/module_resolver.mbt`
/// for its `Types` mode; the runtime mode, which prefers the emitted
/// `.js`, has no consumer here.
///
/// The `.js` arm is the one worth naming: in TypeScript source under
/// ESM, `import "./util.js"` means the module whose source is
/// `./util.ts`. Probing the written extension first would resolve it to
/// an emitted artifact sitting next to the source, and check the wrong
/// file.
fn mtsc_resolution_candidates(specifier : String) -> Array[String] {
  let out : Array[String] = []
  if specifier.has_suffix(".js") {
    let stem = mtsc_strip_suffix(specifier, ".js")
    mtsc_push_unique(out, stem + ".d.ts")
    mtsc_push_unique(out, stem + ".ts")
    mtsc_push_unique(out, stem + ".tsx")
    mtsc_push_unique(out, specifier)
    return out
  }
  if specifier.has_suffix(".mjs") {
    let stem = mtsc_strip_suffix(specifier, ".mjs")
    mtsc_push_unique(out, stem + ".d.mts")
    mtsc_push_unique(out, stem + ".mts")
    mtsc_push_unique(out, specifier)
    return out
  }
  if specifier.has_suffix(".cjs") {
    let stem = mtsc_strip_suffix(specifier, ".cjs")
    mtsc_push_unique(out, stem + ".d.cts")
    mtsc_push_unique(out, stem + ".cts")
    mtsc_push_unique(out, specifier)
    return out
  }
  if specifier.has_suffix(".d.ts") ||
    specifier.has_suffix(".d.mts") ||
    specifier.has_suffix(".d.cts") ||
    specifier.has_suffix(".json") {
    mtsc_push_unique(out, specifier)
    return out
  }
  if specifier.has_suffix(".ts") {
    let stem = mtsc_strip_suffix(specifier, ".ts")
    mtsc_push_unique(out, stem + ".d.ts")
    mtsc_push_unique(out, specifier)
    return out
  }
  if specifier.has_suffix(".tsx") {
    mtsc_push_unique(out, mtsc_strip_suffix(specifier, ".tsx") + ".d.ts")
    mtsc_push_unique(out, specifier)
    return out
  }
  if specifier.has_suffix(".mts") {
    mtsc_push_unique(out, mtsc_strip_suffix(specifier, ".mts") + ".d.mts")
    mtsc_push_unique(out, specifier)
    return out
  }
  if specifier.has_suffix(".cts") {
    mtsc_push_unique(out, mtsc_strip_suffix(specifier, ".cts") + ".d.cts")
    mtsc_push_unique(out, specifier)
    return out
  }
  // No extension written: the specifier names a stem, and every
  // extension a declaration could live under is a candidate.
  mtsc_push_unique(out, specifier + ".d.ts")
  mtsc_push_unique(out, specifier + ".d.mts")
  mtsc_push_unique(out, specifier + ".d.cts")
  mtsc_push_unique(out, specifier + ".ts")
  mtsc_push_unique(out, specifier + ".tsx")
  mtsc_push_unique(out, specifier + ".mts")
  mtsc_push_unique(out, specifier + ".cts")
  mtsc_push_unique(out, specifier + ".js")
  mtsc_push_unique(out, specifier + ".jsx")
  mtsc_push_unique(out, specifier + ".mjs")
  mtsc_push_unique(out, specifier + ".cjs")
  out
}

///|
/// Where `specifier`, imported from `importer`, resolves — or `None`.
///
/// `None` covers both "no such file" and "not our job" (a bare
/// specifier), and the caller distinguishes them with
/// `mtsc_is_relative_specifier`. Merging them here would lose the
/// distinction that decides whether an unresolved import is a
/// diagnostic.
fn[H : MtscHost] mtsc_resolve_module(
  host : H,
  cache : MtscSourceCache,
  importer : String,
  specifier : String,
) -> String? {
  if !mtsc_is_relative_specifier(specifier) {
    return None
  }
  let joined = mtsc_normalize_path(
    mtsc_join_path(mtsc_dirname(importer), specifier),
  )
  for candidate in mtsc_resolution_candidates(joined) {
    if cache.read(host, candidate) is Some(_) {
      return Some(candidate)
    }
  }
  // `./dir` naming a directory holding `index.*`. Probed only after the
  // file candidates, so a sibling `dir.ts` wins over `dir/index.ts` the
  // way it does in TypeScript.
  for candidate in mtsc_resolution_candidates(mtsc_join_path(joined, "index")) {
    if cache.read(host, candidate) is Some(_) {
      return Some(candidate)
    }
  }
  None
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
