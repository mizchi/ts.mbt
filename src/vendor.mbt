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
  let module_root = match find_nearest_moon_mod_dir(".") {
    Some(root) => root
    None => "."
  }
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
  let bare_specifier = "@tsmbt-bridge/\{safe_dir}"
  println(
    "vendor: \{pkg_spec} -> \{output_dir} (#module \"\{bare_specifier}\")",
  )
  if !emit_moonbit_scaffold_from_ts(
      entry_path,
      runtime_spec,
      output_dir,
      bare_module_specifier=Some(bare_specifier),
    ) {
    return false
  }
  // Drop a `package.json` so node treats the bridge directory as an npm
  // package, then symlink it under `<module>/node_modules/@tsmbt-bridge/`
  // so MoonBit's `#module("@tsmbt-bridge/<safe>")` resolves with no
  // absolute path baked in. `moon check --target js` validates the link
  // because the compiled `require(...)` will fail if the symlink is
  // broken.
  if !write_vendor_package_json(output_dir, bare_specifier) {
    return false
  }
  if !ensure_vendor_node_modules_link(module_root, safe_dir, output_dir) {
    return false
  }
  true
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
/// Drop a `package.json` next to the generated bridge so node treats
/// the directory as an npm package. The package's `name` is the bare
/// module specifier baked into `bridge.mbt` via `#module(...)`; `main`
/// points at the generated `bridge.js`.
async fn write_vendor_package_json(
  output_dir : String,
  bare_specifier : String,
) -> Bool {
  let body = "{\n  \"name\": \"" +
    bare_specifier +
    "\",\n  \"version\": \"0.0.0\",\n  \"type\": \"module\",\n  \"main\": \"bridge.js\",\n  \"private\": true\n}\n"
  let path = main_join_path(output_dir, "package.json")
  let _ = @fs.write_file(path, string_to_bytes(body), create=0o644) catch {
    e => {
      println("vendor: failed to write package.json at \{path}: \{e}")
      return false
    }
  }
  true
}

///|
/// Create / refresh the `<module>/node_modules/@tsmbt-bridge/<safe>`
/// symlink that points at the generated package directory. node's
/// resolver follows the symlink and finds `bridge.js` via the
/// generated `package.json#main`, so the moon-emitted `require(...)`
/// works from any compile output location without absolute paths.
async fn ensure_vendor_node_modules_link(
  module_root : String,
  safe_dir : String,
  output_dir : String,
) -> Bool {
  let scope_dir = main_join_path(
    main_join_path(module_root, "node_modules"),
    "@tsmbt-bridge",
  )
  let _ = ensure_dir_tree(scope_dir) catch {
    e => {
      println("vendor: failed to create \{scope_dir}: \{e}")
      return false
    }
  }
  let link_path = main_join_path(scope_dir, safe_dir)
  // `@fs.remove` only takes regular files; symlink replacement needs the
  // raw `unlink`. The symlink may already exist if the user re-vendors,
  // and Node's resolver dereferences it lazily so a stale link is fine
  // until the build, but we still refresh to keep the manifest tidy.
  let _ = @fs.remove(link_path) catch { _ => () }
  let target = if output_dir.has_prefix("/") {
    output_dir
  } else {
    @fs.realpath(output_dir) catch {
      _ => output_dir
    }
  }
  let _ = @fs.symlink(link_path, target~) catch {
    e => {
      println("vendor: failed to symlink \{link_path} -> \{target}: \{e}")
      return false
    }
  }
  true
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
