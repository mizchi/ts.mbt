// Reading a whole `tsconfig.json` rather than one string option out of
// it.
//
// `tsconfig_compiler_option` has been here for a while and answers
// exactly one question: what is the STRING value of this
// `compilerOptions` entry, following `extends`. `mtsc -p` needs three
// more — the file sets (`files` / `include` / `exclude`), the BOOLEAN
// options (`declaration`, `noEmit`, `sourceMap`), and the directory
// those relative paths resolve against.
//
// It lives in this package, next to the scanner it reuses, because the
// alternative was a second JSONC reader in the CLI. tsconfig is JSONC —
// comments and trailing commas — which is why there is a hand-rolled
// scanner here instead of `@json`; a second one would be the "one rule
// written in several places" defect this repo keeps paying for, and the
// two copies would disagree about a comment before anything else.
//
// The FILE-SYSTEM half is deliberately not here. This package answers
// "what does this config say"; expanding `include` into paths is a
// directory walk and belongs to the caller that already has one.

///|
/// What a `tsconfig.json` says about the files in its program.
///
/// `root_dir` is the directory of the config that supplied `files` /
/// `include` / `exclude`, which is not always the config that was
/// loaded: TypeScript resolves those relative paths against the file
/// that DECLARED them, so a config inheriting its `include` from a base
/// one level up resolves it against the base's directory.
pub(all) struct TsconfigProject {
  /// The config that was loaded.
  config_path : String
  /// Directory the path sets below resolve against.
  root_dir : String
  /// `files`: exact paths, no globbing.
  files : Array[String]
  /// `include`: glob patterns. Empty means the caller applies
  /// TypeScript's default of `**/*`.
  include_ : Array[String]
  /// `exclude`: glob patterns. Empty means the caller applies
  /// TypeScript's defaults (`node_modules`, `bower_components`,
  /// `jspm_packages`, and the configured `outDir`).
  exclude : Array[String]
  /// True when the config named `files` or `include` explicitly, so the
  /// caller can tell "no `include`, use the default" from `"include": []`,
  /// which TypeScript treats as an empty program.
  has_file_set : Bool
}

///|
/// Load `config_path`, following `extends` for whichever of the three
/// path sets the nearest config does not declare.
///
/// `None` when the file cannot be read. A config that reads but declares
/// none of the three comes back with `has_file_set: false`, which is the
/// common case for a config that only sets `compilerOptions`.
pub async fn load_tsconfig_project(config_path : String) -> TsconfigProject? {
  load_tsconfig_project_in(normalize_path(config_path), 0)
}

///|
async fn load_tsconfig_project_in(
  config_path : String,
  depth : Int32,
) -> TsconfigProject? {
  // Same bound as `tsconfig_compiler_option_in`, for the same reason: a
  // config that extends itself.
  if depth > 8 {
    return None
  }
  let src = match read_text_file(config_path) {
    Some(t) => t
    None => return None
  }
  let dir = dirname(config_path)
  let files = tsconfig_top_level_string_array(src, "files")
  let include_ = tsconfig_top_level_string_array(src, "include")
  let exclude = tsconfig_top_level_string_array(src, "exclude")
  // `files` and `include` together decide whether this config has a
  // program of its own. `exclude` alone does not — it only narrows one.
  if files is Some(_) || include_ is Some(_) {
    return Some({
      config_path,
      root_dir: dir,
      files: files.unwrap_or([]),
      include_: include_.unwrap_or([]),
      exclude: exclude.unwrap_or([]),
      has_file_set: true,
    })
  }
  // Nothing here; inherit the whole set from the base, INCLUDING its
  // `root_dir`, so the base's relative patterns keep resolving against
  // the base.
  match tsconfig_extends_target(src, dir) {
    Some(parent) =>
      match load_tsconfig_project_in(parent, depth + 1) {
        Some(inherited) =>
          // The loaded config is still the one the caller named; only
          // the path set and its root come from the base.
          Some({ ..inherited, config_path, })
        None =>
          Some({
            config_path,
            root_dir: dir,
            files: [],
            include_: [],
            exclude: exclude.unwrap_or([]),
            has_file_set: false,
          })
      }
    None =>
      Some({
        config_path,
        root_dir: dir,
        files: [],
        include_: [],
        exclude: exclude.unwrap_or([]),
        has_file_set: false,
      })
  }
}

///|
/// A top-level string array (`files`, `include`, `exclude`).
///
/// `None` when the field is absent, `Some([])` when it is present and
/// empty — TypeScript treats `"include": []` as an empty program, so the
/// two cannot be collapsed.
fn tsconfig_top_level_string_array(
  src : String,
  name : String,
) -> Array[String]? {
  match find_object_field_value_range(src, 0, src.length(), name) {
    Some((start_, end_)) =>
      if char_at(src, start_) == '[' {
        Some(parse_json_string_array_at(src, start_, end_))
      } else {
        None
      }
    None => None
  }
}

///|
/// The config path an `extends` field points at, resolved against `dir`.
///
/// Only the single-string form is read. TypeScript 5.0 also allows an
/// ARRAY of bases, and that is a declared gap rather than an oversight:
/// merging several bases needs a precedence rule per field, and every
/// config in this repo and its corpus uses the string form.
async fn tsconfig_extends_target(src : String, dir : String) -> String? {
  match find_object_field_value_range(src, 0, src.length(), "extends") {
    Some((start_, _)) =>
      match parse_json_string_at(src, start_) {
        Some(parent) => resolve_tsconfig_extends(parent, dir)
        None => None
      }
    None => None
  }
}

///|
/// Where `"extends": spec` points, from a config in `dir`.
///
/// A relative or absolute spec is a path, `.json` appended when missing. A
/// BARE spec is a package, resolved the way TypeScript resolves it: the
/// nearest `node_modules/<spec>` up from `dir`, tried as written when it
/// already ends in `.json`, else with `.json` appended and then as a
/// directory holding `tsconfig.json`. (A package's `tsconfig` field in
/// `package.json` is not read.) univer's packages
/// all write `"extends": "@univerjs-infra/shared/tsconfigs/base"`, and
/// joining that onto the package directory named a file that does not
/// exist, so every option the base sets — `strict`,
/// `experimentalDecorators` — read as absent.
pub async fn resolve_tsconfig_extends(spec : String, dir : String) -> String? {
  if spec.has_prefix(".") || spec.has_prefix("/") {
    // An absolute spec names the file itself; joining it onto `dir` read
    // `/work/app//shared/base.json` as `/work/app/shared/base.json`.
    let joined = if spec.has_prefix("/") {
      normalize_path(spec)
    } else {
      normalize_path(join_path(dir, spec))
    }
    return Some(
      if joined.has_suffix(".json") {
        joined
      } else {
        joined + ".json"
      },
    )
  }
  let mut current = normalize_path(dir)
  while true {
    let base = normalize_path(join_path(current, "node_modules/" + spec))
    let candidates = if base.has_suffix(".json") {
      [base]
    } else {
      [base + ".json", join_path(base, "tsconfig.json")]
    }
    for candidate in candidates {
      if read_text_file(candidate) is Some(_) {
        return Some(candidate)
      }
    }
    let parent = dirname(current)
    if parent == current {
      break
    }
    current = parent
  }
  None
}

///|
/// A BOOLEAN `compilerOptions` entry from the nearest `tsconfig.json` to
/// `base_path`, following `extends` when the nearest config does not set
/// it.
///
/// The sibling `tsconfig_compiler_option` reads string values through
/// `parse_json_string_at`, which returns `None` for `true` — so before
/// this existed, `"declaration": true` and an absent `declaration` were
/// the same answer, and every boolean in a tsconfig was invisible.
pub async fn tsconfig_compiler_option_bool(
  base_path : String,
  name : String,
) -> Bool? {
  match find_nearest_ancestor_file(normalize_path(base_path), "tsconfig.json") {
    Some(tsconfig_path) =>
      tsconfig_compiler_option_bool_in(tsconfig_path, name, 0)
    None => None
  }
}

///|
/// As `tsconfig_compiler_option_bool`, for a config path that is already
/// known. `mtsc -p` names the config directly rather than searching up
/// from a source file.
pub async fn tsconfig_compiler_option_bool_at(
  config_path : String,
  name : String,
) -> Bool? {
  tsconfig_compiler_option_bool_in(normalize_path(config_path), name, 0)
}

///|
/// As `tsconfig_compiler_option`, for a config path that is already
/// known.
pub async fn tsconfig_compiler_option_at(
  config_path : String,
  name : String,
) -> String? {
  tsconfig_compiler_option_in(normalize_path(config_path), name, 0)
}

///|
async fn tsconfig_compiler_option_bool_in(
  config_path : String,
  name : String,
  depth : Int32,
) -> Bool? {
  if depth > 8 {
    return None
  }
  let src = match read_text_file(config_path) {
    Some(t) => t
    None => return None
  }
  match find_named_object_range(src, "compilerOptions") {
    Some((start_, end_)) =>
      match find_object_field_value_range(src, start_, end_, name) {
        Some((vstart, vend)) =>
          match tsconfig_parse_bool_at(src, vstart, vend) {
            Some(v) => return Some(v)
            None => ()
          }
        None => ()
      }
    None => ()
  }
  match tsconfig_extends_target(src, dirname(config_path)) {
    Some(parent) => tsconfig_compiler_option_bool_in(parent, name, depth + 1)
    None => None
  }
}

///|
/// A STRING-ARRAY `compilerOptions` entry (`lib`) of the config at
/// `config_path`, following `extends` when that config does not set it.
pub async fn tsconfig_compiler_option_string_array_at(
  config_path : String,
  name : String,
) -> Array[String]? {
  tsconfig_compiler_option_string_array_in(normalize_path(config_path), name, 0)
}

///|
async fn tsconfig_compiler_option_string_array_in(
  config_path : String,
  name : String,
  depth : Int32,
) -> Array[String]? {
  if depth > 8 {
    return None
  }
  let src = match read_text_file(config_path) {
    Some(t) => t
    None => return None
  }
  match find_named_object_range(src, "compilerOptions") {
    Some((start_, end_)) =>
      match find_object_field_value_range(src, start_, end_, name) {
        Some((vstart, vend)) =>
          if char_at(src, vstart) == '[' {
            return Some(parse_json_string_array_at(src, vstart, vend))
          }
        None => ()
      }
    None => ()
  }
  match tsconfig_extends_target(src, dirname(config_path)) {
    Some(parent) =>
      tsconfig_compiler_option_string_array_in(parent, name, depth + 1)
    None => None
  }
}

///|
/// `true` / `false` at `start_`. `None` for anything else, so a
/// `"declaration": "yes"` typo abstains rather than reading as true.
fn tsconfig_parse_bool_at(src : String, start_ : Int32, end_ : Int32) -> Bool? {
  let text = if start_ < end_ && end_ <= src.length() {
    src[start_:end_].to_owned().trim().to_owned()
  } else {
    ""
  }
  match text {
    "true" => Some(true)
    "false" => Some(false)
    _ => None
  }
}

///|
/// The `/// <reference path="…" />` and `/// <reference types="…" />`
/// directives at the top of `source`, as `(kind, value)` with `kind`
/// `"path"` or `"types"`.
///
/// A triple-slash directive counts only in the file's leading trivia: it may
/// follow other comments and other directives, and the first token of code
/// ends the region (TypeScript's `processReferenceComments`). So this reads
/// comments and whitespace and stops at anything else, which is also what
/// keeps a `///` line inside a function body from being read as one. `lib`
/// and `no-default-lib` directives are skipped: the lib set is chosen by
/// `--lib`, not per file.
pub fn triple_slash_references(source : String) -> Array[(String, String)] {
  let out : Array[(String, String)] = []
  let n = source.length()
  let mut i = 0
  while i < n {
    let c = source[i]
    if c == ' ' ||
      c == '\t' ||
      c == '\n' ||
      c == '\r' ||
      c == '\u{2028}' ||
      c == '\u{2029}' ||
      c == '\u{FEFF}' {
      i = i + 1
      continue
    }
    if c == '/' && i + 1 < n && source[i + 1] == '*' {
      let mut j = i + 2
      while j + 1 < n && !(source[j] == '*' && source[j + 1] == '/') {
        j = j + 1
      }
      i = j + 2
      continue
    }
    if c == '/' && i + 1 < n && source[i + 1] == '/' {
      // A line comment ends at any line terminator TypeScript's scanner
      // recognizes, not just LF: a CR-only file is one long line otherwise,
      // and the first comment swallows every directive after it.
      let mut j = i
      while j < n &&
            source[j] != '\n' &&
            source[j] != '\r' &&
            source[j] != '\u{2028}' &&
            source[j] != '\u{2029}' {
        j = j + 1
      }
      let line = source[i:j].to_owned()
      if line.has_prefix("///") {
        match triple_slash_reference(line) {
          Some(entry) => out.push(entry)
          None => ()
        }
      }
      i = j
      continue
    }
    break
  }
  out
}

///|
/// One `/// <reference … />` line, if it names a `path` or `types`.
fn triple_slash_reference(line : String) -> (String, String)? {
  let body = line[3:].trim().to_owned()
  guard body.has_prefix("<reference") else { return None }
  for kind in ["path", "types"] {
    match triple_slash_attribute(body, kind) {
      Some(value) => return Some((kind, value))
      None => ()
    }
  }
  None
}

///|
/// The quoted value of attribute `name` in a `<reference … />` tag, with
/// optional whitespace on either side of the `=` (`path = "x"` is accepted
/// by TypeScript as readily as `path="x"`). The name has to start an
/// attribute — preceded by whitespace — so `types` is not found inside
/// another attribute's name or value.
fn triple_slash_attribute(body : String, name : String) -> String? {
  let n = body.length()
  let is_space = fn(c : UInt16) { c == ' ' || c == '\t' }
  let mut from = 0
  while from < n {
    let at = match body[from:].find(name) {
      Some(off) => from + off
      None => return None
    }
    from = at + 1
    if at == 0 || !is_space(body[at - 1]) {
      continue
    }
    let mut j = at + name.length()
    while j < n && is_space(body[j]) {
      j = j + 1
    }
    if j >= n || body[j] != '=' {
      continue
    }
    j = j + 1
    while j < n && is_space(body[j]) {
      j = j + 1
    }
    if j >= n || (body[j] != '"' && body[j] != '\'') {
      continue
    }
    let quote = body[j]
    let start = j + 1
    let mut k = start
    while k < n && body[k] != quote {
      k = k + 1
    }
    if k < n {
      return Some(body[start:k].to_owned())
    }
    return None
  }
  None
}
