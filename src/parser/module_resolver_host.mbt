// Module resolution over an INJECTED filesystem.
//
// `module_resolver.mbt` resolves against the real filesystem and is
// `async` throughout, because `moonbitlang/async/fs` is. That is the right
// shape for the CLI and the wrong one for everything that has no real
// filesystem: a browser, a wasm-gc embedding, a bundler's virtual module
// graph, an editor's in-memory buffers. Those hosts answer synchronously —
// TypeScript's own `ModuleResolutionHost` is synchronous by design — so
// they need the same algorithm with the IO behind a trait instead of
// behind `@fs`.
//
// This file is that algorithm, and it is the SAME algorithm: every pure
// step (the JSON scans, `exports` condition selection, `typesVersions`
// mapping, `@types` naming, the candidate-extension ordering) is the
// helper `module_resolver.mbt` already uses, called from here rather than
// copied. What is restated is only the walk that interleaves those steps
// with filesystem questions, because a sync walk cannot call the async
// one. Two walks can drift, so they are pinned against each other: the
// whitebox test `resolver_host_wbtest.mbt` runs both over every fixture
// specifier the async resolver's own tests use and requires the same
// answer.
//
// Only the TYPES mode is exposed. That is the question a type checker
// asks; the runtime mode exists for the bundler, which has a real
// filesystem.

///|
/// The filesystem a resolution runs against, supplied by the caller.
///
/// TypeScript's `ModuleResolutionHost`, minus what this algorithm does not
/// ask. All four are required: MoonBit gives a trait no defaults, so a new
/// host cannot inherit a guess. A host with no notion of directories
/// answers `directory_exists` with `true` and lets the file probes decide,
/// which is what TypeScript does when `directoryExists` is absent; a host
/// with no symlinks answers `realpath` with its argument.
pub(open) trait ModuleResolutionHost {
  /// Whether `path` names a readable file.
  fn file_exists(Self, String) -> Bool
  /// Whether `path` names a directory.
  fn directory_exists(Self, String) -> Bool
  /// The text of `path`, or `None`.
  fn read_file(Self, String) -> String?
  /// The canonical spelling of `path` (symlinks resolved), or `path`.
  fn realpath(Self, String) -> String
}

///|
/// Where a TypeScript import of `specifier` from the file `base_path`
/// resolves for TYPE checking, asking `host` for every filesystem fact.
///
/// The counterpart of `resolve_type_module_specifier`, in the same order:
/// relative and absolute paths, package `imports` (`#x`), `node:`
/// builtins through `@types/node`, tsconfig `paths` / `baseUrl`, then
/// `node_modules` (`exports` with the `types` condition, `types` /
/// `typings`, `typesVersions`, `index.d.ts`, `@types/<name>`) from the
/// importer's directory up, and the same walk again from the importer's
/// real path when the first finds nothing.
pub fn[H : ModuleResolutionHost] resolve_type_module_specifier_with(
  host : H,
  base_path : String,
  specifier : String,
) -> String? {
  host_resolve_module_specifier(
    host,
    base_path,
    specifier,
    ModuleResolutionMode::Types,
  )
}

///|
fn[H : ModuleResolutionHost] host_resolve_as_file(
  host : H,
  candidate : String,
  mode : ModuleResolutionMode,
) -> String? {
  let candidates : Array[String] = []
  append_resolution_candidates(candidates, normalize_path(candidate), mode)
  for item in candidates {
    if host.file_exists(item) {
      return Some(item)
    }
  }
  None
}

///|
fn[H : ModuleResolutionHost] host_find_nearest_ancestor_file(
  host : H,
  base_path : String,
  file_name : String,
) -> String? {
  let mut current = dirname(normalize_path(base_path))
  while true {
    let candidate = normalize_path(join_path(current, file_name))
    if host.file_exists(candidate) {
      return Some(candidate)
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
fn[H : ModuleResolutionHost] host_read_package_json(
  host : H,
  package_root : String,
) -> String? {
  let canonical_root = host.realpath(package_root)
  let path = normalize_path(join_path(canonical_root, "package.json"))
  if !host.file_exists(path) {
    return None
  }
  host.read_file(path)
}

///|
fn[H : ModuleResolutionHost] host_read_nearest_package_json(
  host : H,
  base_path : String,
) -> (String, String)? {
  match host_find_nearest_ancestor_file(host, base_path, "package.json") {
    Some(package_json_path) =>
      match host.read_file(package_json_path) {
        Some(t) => Some((dirname(package_json_path), t))
        None => None
      }
    None => None
  }
}

///|
/// `resolve_tsconfig_extends` over the host: a relative or absolute spec
/// names the file, a bare one is looked up through `node_modules`.
fn[H : ModuleResolutionHost] host_resolve_tsconfig_extends(
  host : H,
  spec : String,
  dir : String,
) -> String? {
  if spec.has_prefix(".") || spec.has_prefix("/") {
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
      if host.read_file(candidate) is Some(_) {
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
fn[H : ModuleResolutionHost] host_resolve_tsconfig_specifier(
  host : H,
  base_path : String,
  specifier : String,
  mode : ModuleResolutionMode,
) -> String? {
  match host_find_nearest_ancestor_file(host, base_path, "tsconfig.json") {
    Some(tsconfig_path) =>
      host_resolve_tsconfig_specifier_in(
        host, tsconfig_path, specifier, mode, 0,
      )
    None => None
  }
}

///|
fn[H : ModuleResolutionHost] host_resolve_tsconfig_specifier_in(
  host : H,
  tsconfig_path : String,
  specifier : String,
  mode : ModuleResolutionMode,
  depth : Int32,
) -> String? {
  if depth > 8 {
    return None
  }
  match
    host_resolve_tsconfig_specifier_here(host, tsconfig_path, specifier, mode) {
    Some(found) => return Some(found)
    None => ()
  }
  let src = match host.read_file(tsconfig_path) {
    Some(t) => t
    None => return None
  }
  match find_object_field_value_range(src, 0, src.length(), "extends") {
    Some((start, _)) =>
      match parse_json_string_at(src, start) {
        Some(parent) =>
          match
            host_resolve_tsconfig_extends(host, parent, dirname(tsconfig_path)) {
            Some(candidate) =>
              host_resolve_tsconfig_specifier_in(
                host,
                candidate,
                specifier,
                mode,
                depth + 1,
              )
            None => None
          }
        None => None
      }
    None => None
  }
}

///|
fn[H : ModuleResolutionHost] host_resolve_tsconfig_specifier_here(
  host : H,
  tsconfig_path : String,
  specifier : String,
  mode : ModuleResolutionMode,
) -> String? {
  let tsconfig_dir = dirname(tsconfig_path)
  let tsconfig_src = match host.read_file(tsconfig_path) {
    Some(t) => t
    None => return None
  }
  guard find_named_object_range(tsconfig_src, "compilerOptions")
    is Some((compiler_start, compiler_end)) else {
    return None
  }
  let mut base_dir = ""
  match
    find_object_field_value_range(
      tsconfig_src, compiler_start, compiler_end, "baseUrl",
    ) {
    Some((start, _)) =>
      match parse_json_string_at(tsconfig_src, start) {
        Some(base_url) =>
          base_dir = normalize_path(join_path(tsconfig_dir, base_url))
        None => ()
      }
    None => ()
  }
  match
    find_named_object_range_in_object(
      tsconfig_src, compiler_start, compiler_end, "paths",
    ) {
    Some((paths_start, paths_end)) =>
      for
        target in resolve_string_array_mapping_in_object(
          tsconfig_src, paths_start, paths_end, specifier,
        ) {
        let candidate = if base_dir == "" {
          normalize_path(join_path(tsconfig_dir, target))
        } else {
          normalize_path(join_path(base_dir, target))
        }
        match host_resolve_path_like(host, candidate, mode) {
          Some(path) => return Some(path)
          None => ()
        }
      }
    None => ()
  }
  if base_dir != "" {
    return host_resolve_path_like(
      host,
      normalize_path(join_path(base_dir, specifier)),
      mode,
    )
  }
  None
}

///|
fn[H : ModuleResolutionHost] host_resolve_package_imports_specifier(
  host : H,
  base_path : String,
  specifier : String,
  mode : ModuleResolutionMode,
  seen : Array[String],
) -> String? {
  if seen.contains(specifier) {
    return None
  }
  seen.push(specifier)
  guard host_read_nearest_package_json(host, base_path)
    is Some((package_root, package_json)) else {
    return None
  }
  guard find_json_field(package_json, "imports") is Some(Object(imports_obj)) else {
    return None
  }
  let package_base = normalize_path(join_path(package_root, "package.json"))
  for
    target in resolve_conditional_mapping_targets(imports_obj, specifier, mode) {
    let found = if target.has_prefix("./") || target.has_prefix("../") {
      host_resolve_package_target(host, package_root, target, mode)
    } else if target.has_prefix("/") {
      host_resolve_path_like(host, normalize_path(target), mode)
    } else if target.has_prefix("#") {
      host_resolve_package_imports_specifier(
        host, package_base, target, mode, seen,
      )
    } else {
      host_resolve_module_specifier(host, package_base, target, mode)
    }
    if found is Some(_) {
      return found
    }
  }
  None
}

///|
fn[H : ModuleResolutionHost] host_resolve_package_target(
  host : H,
  package_root : String,
  target : String,
  mode : ModuleResolutionMode,
) -> String? {
  let candidate = if target.has_prefix("./") {
    normalize_path(join_path(package_root, target))
  } else {
    normalize_path(join_path(package_root, "./" + target))
  }
  host_resolve_path_like(host, candidate, mode)
}

///|
/// `resolve_package_entry`, step for step: `exports`, then for the root
/// the `types` / `typings` / `main` / `module` fields with a `.js` answer
/// deferred behind `index.d.ts`, then for a subpath `typesVersions`, and
/// finally the subpath as a plain path inside the package.
fn[H : ModuleResolutionHost] host_resolve_package_entry(
  host : H,
  package_root : String,
  subpath : String,
  mode : ModuleResolutionMode,
) -> String? {
  match host_read_package_json(host, package_root) {
    Some(pkg) => {
      for target in resolve_exports_target(pkg, subpath, mode) {
        match host_resolve_package_target(host, package_root, target, mode) {
          Some(path) => return Some(path)
          None => ()
        }
      }
      if subpath == "" {
        let preferred_fields = match mode {
          Types => ["types", "typings", "main", "module"]
          Runtime => ["main", "module", "types", "typings"]
        }
        for field in preferred_fields {
          match find_json_field(pkg, field) {
            Some(String(target)) =>
              match
                host_resolve_package_target(host, package_root, target, mode) {
                Some(path) =>
                  if mode is Runtime || !resolved_path_is_scriptish(path) {
                    return Some(path)
                  }
                None => ()
              }
            _ => ()
          }
        }
        if mode is Types {
          for index_name in ["index.d.ts", "index.d.mts", "index.d.cts"] {
            let candidate = normalize_path(join_path(package_root, index_name))
            if host.file_exists(candidate) {
              return Some(candidate)
            }
          }
        }
        for field in preferred_fields {
          match find_json_field(pkg, field) {
            Some(String(target)) =>
              match
                host_resolve_package_target(host, package_root, target, mode) {
                Some(path) => return Some(path)
                None => ()
              }
            _ => ()
          }
        }
      } else if mode is Types {
        for target in resolve_types_versions_targets(pkg, subpath) {
          match host_resolve_package_target(host, package_root, target, mode) {
            Some(path) => return Some(path)
            None => ()
          }
        }
      }
    }
    // No manifest: the package root is `index` (see the async walk).
    None =>
      if subpath == "" {
        return host_resolve_as_file(
          host,
          join_path(package_root, "index"),
          mode,
        )
      }
  }
  if subpath != "" {
    return host_resolve_path_like(
      host,
      normalize_path(join_path(package_root, subpath)),
      mode,
    )
  }
  None
}

///|
fn[H : ModuleResolutionHost] host_resolve_as_directory(
  host : H,
  candidate : String,
  mode : ModuleResolutionMode,
) -> String? {
  let normalized = normalize_path(candidate)
  if !host.directory_exists(normalized) {
    return None
  }
  match host_resolve_package_entry(host, normalized, "", mode) {
    Some(path) => return Some(path)
    None => ()
  }
  host_resolve_as_file(
    host,
    normalize_path(join_path(normalized, "index")),
    mode,
  )
}

///|
fn[H : ModuleResolutionHost] host_resolve_path_like(
  host : H,
  candidate : String,
  mode : ModuleResolutionMode,
) -> String? {
  let normalized = normalize_path(candidate)
  match host_resolve_as_file(host, normalized, mode) {
    Some(path) => Some(path)
    None => host_resolve_as_directory(host, normalized, mode)
  }
}

///|
fn[H : ModuleResolutionHost] host_resolve_at_types_package_entry(
  host : H,
  node_modules_root : String,
  package_name : String,
  subpath : String,
) -> String? {
  guard types_package_name(package_name) is Some(types_name) else {
    return None
  }
  let types_root = normalize_path(join_path(node_modules_root, types_name))
  if !host.directory_exists(types_root) {
    return None
  }
  host_resolve_package_entry(
    host,
    types_root,
    subpath,
    ModuleResolutionMode::Types,
  )
}

///|
fn[H : ModuleResolutionHost] host_resolve_node_builtin_type_specifier(
  host : H,
  base_path : String,
  specifier : String,
) -> String? {
  let builtin_path = specifier["node:".length():].to_owned()
  if builtin_path == "" {
    return None
  }
  let mut current = dirname(base_path)
  while true {
    let types_node_root = normalize_path(
      join_path(join_path(current, "node_modules"), "@types/node"),
    )
    if host.directory_exists(types_node_root) {
      match
        host_resolve_path_like(
          host,
          normalize_path(join_path(types_node_root, builtin_path)),
          ModuleResolutionMode::Types,
        ) {
        Some(path) => return Some(path)
        None => ()
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
fn[H : ModuleResolutionHost] host_resolve_bare_specifier(
  host : H,
  base_path : String,
  specifier : String,
  mode : ModuleResolutionMode,
) -> String? {
  let (package_name, subpath) = split_package_specifier(specifier)
  let mut current = dirname(base_path)
  let mut js_fallback : String? = None
  while true {
    let node_modules_root = normalize_path(join_path(current, "node_modules"))
    let package_root = normalize_path(
      join_path(node_modules_root, package_name),
    )
    if host.directory_exists(package_root) {
      match host_resolve_package_entry(host, package_root, subpath, mode) {
        Some(path) =>
          match mode {
            Runtime => return Some(path)
            Types =>
              if is_runtime_js_path(path) {
                if js_fallback is None {
                  js_fallback = Some(path)
                }
              } else {
                return Some(path)
              }
          }
        None => ()
      }
    }
    if mode is Types {
      match
        host_resolve_at_types_package_entry(
          host, node_modules_root, package_name, subpath,
        ) {
        Some(path) => return Some(path)
        None => ()
      }
    }
    let parent = dirname(current)
    if parent == current {
      break
    }
    current = parent
  }
  match mode {
    Types => js_fallback
    Runtime => None
  }
}

///|
fn[H : ModuleResolutionHost] host_resolve_module_specifier(
  host : H,
  base_path : String,
  specifier : String,
  mode : ModuleResolutionMode,
) -> String? {
  let normalized_base = normalize_path(base_path)
  if specifier.has_prefix("./") || specifier.has_prefix("../") {
    return host_resolve_path_like(
      host,
      normalize_path(join_path(dirname(normalized_base), specifier)),
      mode,
    )
  }
  if specifier.has_prefix("/") {
    return host_resolve_path_like(host, normalize_path(specifier), mode)
  }
  if specifier.has_prefix("#") {
    return host_resolve_package_imports_specifier(
      host,
      normalized_base,
      specifier,
      mode,
      [],
    )
  }
  if specifier.has_prefix("node:") {
    return match mode {
      Types =>
        host_resolve_node_builtin_type_specifier(
          host, normalized_base, specifier,
        )
      Runtime => None
    }
  }
  match
    host_resolve_tsconfig_specifier(host, normalized_base, specifier, mode) {
    Some(path) => return Some(path)
    None => ()
  }
  match host_resolve_bare_specifier(host, normalized_base, specifier, mode) {
    Some(path) => Some(path)
    None => {
      let real_base = host.realpath(normalized_base)
      if real_base == normalized_base {
        None
      } else {
        host_resolve_bare_specifier(host, real_base, specifier, mode)
      }
    }
  }
}
