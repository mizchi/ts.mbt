///|
/// Vendor a single TypeScript package's types into the consumer's
/// `<source>/internal/generated/<safe>/` sub-package.
///
/// `pkg_spec` is an npm-style specifier (`hono`, `@types/react`,
/// `@scope/foo`). The resolver walks the consumer's `node_modules` to
/// find the type entrypoint, generates a MoonBit bridge package, and
/// writes it under `<source>/internal/generated/<safe>/`.
///
/// `module_spec_override` overrides the runtime import the generated
/// `bridge.js` uses. Defaults to `pkg_spec` (or, for `@types/<name>`
/// inputs, the unscoped runtime name).
///
/// `vendor_root_override` overrides the output root. Defaults to
/// `<moon-mod source>/internal/generated`.
pub async fn ts2mbt_vendor_package(
  pkg_spec : String,
  module_spec_override? : String? = None,
  vendor_root_override? : String? = None,
) -> Bool {
  let vendor_root = match vendor_root_override {
    Some(root) => root
    None =>
      match resolve_default_vendor_root() {
        Some(root) => root
        None => {
          println(
            "vendor: could not resolve `<source>/internal/generated`; run inside a moon module or pass --out <dir>",
          )
          return false
        }
      }
  }
  let entry_path = match
    @parser.resolve_type_module_specifier("__tsmbt_entry__.ts", pkg_spec) {
    Some(path) => path
    None => {
      println(
        "vendor: could not resolve TypeScript types for '\{pkg_spec}'; check that it's installed in node_modules",
      )
      return false
    }
  }
  let runtime_spec = match module_spec_override {
    Some(spec) => spec
    None => default_runtime_module_spec(pkg_spec)
  }
  let safe_dir = vendor_safe_pkg_dir(pkg_spec)
  let output_dir = main_join_path(vendor_root, safe_dir)
  println("vendor: \{pkg_spec} -> \{output_dir}")
  emit_moonbit_scaffold_from_ts(entry_path, runtime_spec, output_dir)
}

///|
/// Vendor every dependency listed in a `package.json` (`dependencies` +
/// `devDependencies`). Emits a per-package summary at the end and
/// returns `true` only when every package generated successfully.
///
/// `package_json_path_override` defaults to `./package.json`.
pub async fn ts2mbt_sync_package_json(
  package_json_path_override? : String? = None,
  vendor_root_override? : String? = None,
) -> Bool {
  let package_json_path = match package_json_path_override {
    Some(path) => path
    None => "package.json"
  }
  let deps = read_package_json_dependency_names(package_json_path)
  if deps.length() == 0 {
    println(
      "sync: no dependencies / devDependencies found in '\{package_json_path}'",
    )
    return true
  }
  let succeeded : Array[String] = []
  let failed : Array[String] = []
  for pkg_spec in deps {
    if ts2mbt_vendor_package(pkg_spec, vendor_root_override~) {
      succeeded.push(pkg_spec)
    } else {
      failed.push(pkg_spec)
    }
  }
  println("")
  println(
    "sync summary: \{succeeded.length()} ok, \{failed.length()} failed (of \{deps.length()})",
  )
  if failed.length() > 0 {
    println("failed packages:")
    for pkg in failed {
      println("  - \{pkg}")
    }
  }
  failed.length() == 0
}

///|
/// Sanitize an npm package specifier into a directory-name-safe slug.
/// `@scope/foo-bar` -> `scope__foo_bar`; `react` -> `react`.
fn vendor_safe_pkg_dir(name : String) -> String {
  let mut result = ""
  for c in name {
    if c == '@' {
      // Strip leading scope marker
      ()
    } else if (c >= 'a' && c <= 'z') ||
      (c >= 'A' && c <= 'Z') ||
      (c >= '0' && c <= '9') {
      result += c.to_string()
    } else if c == '/' {
      result += "__"
    } else {
      result += "_"
    }
  }
  if result == "" {
    "package"
  } else {
    result
  }
}

///|
/// Default runtime module spec for a package vendored from node_modules.
/// `@types/react` -> `react`; everything else passes through.
fn default_runtime_module_spec(pkg_spec : String) -> String {
  let prefix = "@types/"
  if pkg_spec.has_prefix(prefix) {
    pkg_spec[prefix.length():pkg_spec.length()].to_string()
  } else {
    pkg_spec
  }
}

///|
/// Resolve `<moon.mod source>/internal/generated` from the cwd's
/// nearest `moon.mod.json`. Returns `None` if no module is found.
async fn resolve_default_vendor_root() -> String? {
  let module_root = match find_nearest_moon_mod_dir(".") {
    Some(root) => root
    None => return None
  }
  let moon_mod_path = main_join_path(module_root, "moon.mod.json")
  let source = @fs.read_file(moon_mod_path).text() catch { _ => return None }
  let source_dir_rel = match parse_moon_mod_string_field(source, "source") {
    Some(value) => value
    None => "src"
  }
  let source_dir = if source_dir_rel == "" || source_dir_rel == "." {
    module_root
  } else {
    main_join_path(module_root, source_dir_rel)
  }
  Some(main_join_path(source_dir, "internal/generated"))
}

///|
/// Read the names listed under `dependencies` and `devDependencies` in
/// the given `package.json`. Order: deps first, devDeps second, with
/// each block in the order JSON returned. Duplicates are de-duped.
async fn read_package_json_dependency_names(path : String) -> Array[String] {
  let result : Array[String] = []
  let source = @fs.read_file(path).text() catch {
    _ => {
      println("vendor: could not read '\{path}'")
      return result
    }
  }
  let json = @json.parse(source) catch {
    _ => {
      println("vendor: '\{path}' is not valid JSON")
      return result
    }
  }
  guard json is Object(members) else { return result }
  for field in ["dependencies", "devDependencies"] {
    for pair in members {
      let (name, value) = pair
      if name != field {
        continue
      }
      guard value is Object(deps) else { continue }
      for dep_pair in deps {
        let (dep_name, _) = dep_pair
        if !result.contains(dep_name) {
          result.push(dep_name)
        }
      }
    }
  }
  result
}
