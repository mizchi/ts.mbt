///|
pub async fn emit_moonbit_decl(
  file_path : String,
  output_path : String?,
) -> Bool {
  let emitted = emit_moonbit_decl_text(file_path) catch {
    @bridge.ModuleGraphError::ReadError(msg)
    | @bridge.ModuleGraphError::ParseError(msg)
    | @bridge.ModuleGraphError::ResolveError(msg) => {
      println("Emit error: \{cli_clean_error(msg)}")
      return false
    }
  }
  match output_path {
    Some(path) => {
      let _ = @fs.write_file(path, string_to_bytes(emitted), create=0o644) catch {
        e => {
          println("Write error: \{e}")
          return false
        }
      }
      println("Wrote MoonBit declarations to \{path}")
    }
    None => println(emitted)
  }
  true
}

///|
async fn emit_moonbit_decl_text(
  file_path : String,
) -> String raise @bridge.ModuleGraphError {
  @bridge.emit_moonbit_decl_from_entry_path(file_path)
}

///|
pub async fn emit_typescript_decl(
  file_path : String,
  output_path : String?,
) -> Bool {
  let emitted = emit_typescript_decl_text(file_path) catch {
    @bridge.ModuleGraphError::ReadError(msg)
    | @bridge.ModuleGraphError::ParseError(msg)
    | @bridge.ModuleGraphError::ResolveError(msg) => {
      println("Emit error: \{cli_clean_error(msg)}")
      return false
    }
  }
  match output_path {
    Some(path) => {
      let _ = @fs.write_file(path, string_to_bytes(emitted), create=0o644) catch {
        e => {
          println("Write error: \{e}")
          return false
        }
      }
      println("Wrote normalized TypeScript declarations to \{path}")
    }
    None => println(emitted)
  }
  true
}

///|
async fn emit_typescript_decl_text(
  file_path : String,
) -> String raise @bridge.ModuleGraphError {
  @bridge.normalize_moonbit_generated_typescript_decl_from_entry_path(file_path)
}

///|
pub async fn emit_typescript_decl_from_mbti(
  file_path : String,
  output_path : String?,
) -> Bool {
  let emitted = emit_typescript_decl_from_mbti_text(file_path) catch {
    @bridge.MbtiTypescriptDeclError::ReadError(msg)
    | @bridge.MbtiTypescriptDeclError::ParseError(msg) => {
      println("Emit error: \{cli_clean_error(msg)}")
      return false
    }
  }
  match output_path {
    Some(path) => {
      let _ = @fs.write_file(path, string_to_bytes(emitted), create=0o644) catch {
        e => {
          println("Write error: \{e}")
          return false
        }
      }
      println("Wrote TypeScript declarations to \{path}")
    }
    None => println(emitted)
  }
  true
}

///|
async fn emit_typescript_decl_from_mbti_text(
  file_path : String,
) -> String raise @bridge.MbtiTypescriptDeclError {
  @bridge.emit_typescript_decl_from_mbti_path(file_path)
}

///|
pub async fn emit_js_link_config_from_mbti(
  file_path : String,
  output_path : String?,
) -> Bool {
  let emitted = emit_js_link_config_from_mbti_text(file_path) catch {
    @bridge.MbtiJsLinkConfigError::ReadError(msg)
    | @bridge.MbtiJsLinkConfigError::ParseError(msg) => {
      println("Emit error: \{cli_clean_error(msg)}")
      return false
    }
  }
  match output_path {
    Some(path) => {
      let _ = @fs.write_file(path, string_to_bytes(emitted), create=0o644) catch {
        e => {
          println("Write error: \{e}")
          return false
        }
      }
      println("Wrote MoonBit JS link config to \{path}")
    }
    None => println(emitted)
  }
  true
}

///|
async fn emit_js_link_config_from_mbti_text(
  file_path : String,
) -> String raise @bridge.MbtiJsLinkConfigError {
  @bridge.emit_moonbit_js_link_config_from_mbti_path(file_path)
}

///|
async fn load_typescript_import_rewrite_map(
  import_rewrite_path : String?,
) -> Map[String, String]? {
  match import_rewrite_path {
    Some(path) => {
      let source = @fs.read_file(path).text() catch {
        e => {
          println(
            "Emit error: failed to read import rewrite map '\{path}': \{e}",
          )
          return None
        }
      }
      match @bridge.parse_typescript_import_rewrite_map_source(source) {
        Some(rewrites) => Some(rewrites)
        None => {
          println(
            "Emit error: invalid import rewrite map '\{path}', expected a JSON object of string-to-string entries",
          )
          None
        }
      }
    }
    None => Some({})
  }
}

///|
fn main_dirname(path : String) -> String {
  match path.rev_find("/") {
    Some(0) => "/"
    Some(idx) => path[:idx].to_string()
    None => "."
  }
}

///|
fn main_join_path(base : String, child : String) -> String {
  if base == "." || base == "" {
    child
  } else if base.has_suffix("/") {
    base + child
  } else {
    base + "/" + child
  }
}

///|
async fn ensure_dir_tree(path : String) -> Unit raise Error {
  if path == "." || path == "" || @fs.exists(path) {
    return
  }
  let parent = main_dirname(path)
  if parent != path {
    ensure_dir_tree(parent)
  }
  if !@fs.exists(path) {
    @fs.mkdir(path, permission=0o755)
  }
}

///|
pub async fn emit_typescript_package_from_mbti(
  file_path : String,
  output_dir : String,
  import_rewrite_path : String?,
) -> Bool {
  let import_rewrites = match
    load_typescript_import_rewrite_map(import_rewrite_path) {
    Some(rewrites) => rewrites
    None => return false
  }
  let files = @bridge.emit_typescript_package_bundle_from_mbti_path_with_import_rewrites(
    file_path, import_rewrites,
  ) catch {
    @bridge.MbtiTypescriptDeclError::ReadError(msg)
    | @bridge.MbtiTypescriptDeclError::ParseError(msg) => {
      println("Emit error: \{cli_clean_error(msg)}")
      return false
    }
  }
  let _ = ensure_dir_tree(output_dir) catch {
    e => {
      println("Write error: \{e}")
      return false
    }
  }
  for file in files {
    let output_path = main_join_path(output_dir, file.relative_path)
    let parent_dir = main_dirname(output_path)
    let _ = ensure_dir_tree(parent_dir) catch {
      e => {
        println("Write error: \{e}")
        return false
      }
    }
    let _ = @fs.write_file(
      output_path,
      string_to_bytes(file.content),
      create=0o644,
    ) catch {
      e => {
        println("Write error: \{e}")
        return false
      }
    }
  }
  println("Wrote TypeScript declaration package to \{output_dir}")
  true
}

///|
priv struct MoonbitJsBuildContext {
  module_root : String
  glue_dir_name : String
  glue_dir_path : String
  build_arg : String
  build_output_dir : String
}

///|
fn parse_moon_mod_string_field(source : String, field_name : String) -> String? {
  let json = @json.parse(source) catch { _ => return None }
  guard json is Object(members) else { return None }
  for pair in members {
    let (name, value) = pair
    if name == field_name {
      guard value is String(text) else { return None }
      return Some(text)
    }
  }
  None
}

///|
fn sanitize_glue_dir_part(source : String) -> String {
  let mut rendered = ""
  for c in source {
    if (c >= 'a' && c <= 'z') ||
      (c >= 'A' && c <= 'Z') ||
      (c >= '0' && c <= '9') {
      rendered += c.to_string()
    } else if !rendered.has_suffix("_") {
      rendered += "_"
    }
  }
  let trimmed = rendered.trim(chars="_").to_string()
  if trimmed == "" {
    "package"
  } else {
    trimmed
  }
}

///|
fn hash_glue_dir_part(source : String) -> String {
  let mut hash = 5381
  for c in source {
    hash = (hash * 33 + c.to_int()) % 1000003
  }
  hash.to_string()
}

///|
async fn find_nearest_moon_mod_dir(start_dir : String) -> String? {
  let mut current = start_dir
  while true {
    let moon_mod = main_join_path(current, "moon.mod.json")
    if @fs.exists(moon_mod) {
      return Some(current)
    }
    let parent = main_dirname(current)
    if parent == current {
      return None
    }
    current = parent
  }
  None
}

///|
fn strip_dir_prefix(root : String, path : String) -> String? {
  if path == root {
    return Some("")
  }
  let prefix = if root.has_suffix("/") { root } else { root + "/" }
  if path.has_prefix(prefix) {
    Some(path[prefix.length():path.length()].to_string())
  } else {
    None
  }
}

///|
async fn resolve_moonbit_js_build_context(
  mbti_path : String,
  output_dir : String,
) -> MoonbitJsBuildContext? {
  let source = @fs.read_file(mbti_path).text() catch { _ => return None }
  let package_name = match parse_mbti_package_name_from_source(source) {
    Some(name) => name
    None => return None
  }
  let mbti_realpath = @fs.realpath(mbti_path) catch { _ => mbti_path }
  let package_dir = main_dirname(mbti_realpath)
  let module_root = match find_nearest_moon_mod_dir(package_dir) {
    Some(root) => @fs.realpath(root) catch { _ => root }
    None => return None
  }
  let moon_mod_path = main_join_path(module_root, "moon.mod.json")
  let moon_mod_source = @fs.read_file(moon_mod_path).text() catch {
    _ => return None
  }
  let source_root_rel = match
    parse_moon_mod_string_field(moon_mod_source, "source") {
    Some(source) => source
    None => "."
  }
  let source_root = if source_root_rel == "." || source_root_rel == "" {
    module_root
  } else {
    main_join_path(module_root, source_root_rel)
  }
  let source_root_realpath = @fs.realpath(source_root) catch {
    _ => source_root
  }
  match strip_dir_prefix(source_root_realpath, package_dir) {
    Some(_) => ()
    None => return None
  }
  let glue_dir_name = "__tsmbt_glue__" +
    sanitize_glue_dir_part(package_name) +
    "__" +
    hash_glue_dir_part(output_dir)
  let glue_dir_path = main_join_path(source_root_realpath, glue_dir_name)
  let build_arg = if source_root_rel == "." || source_root_rel == "" {
    glue_dir_name
  } else {
    main_join_path(source_root_rel, glue_dir_name)
  }
  let build_output_dir = main_join_path(
    main_join_path(
      main_join_path(
        main_join_path(main_join_path(module_root, "_build"), "js"),
        "debug",
      ),
      "build",
    ),
    glue_dir_name,
  )
  Some({
    module_root,
    glue_dir_name,
    glue_dir_path,
    build_arg,
    build_output_dir,
  })
}

///|
async fn write_text_file(path : String, content : String) -> Bool {
  let parent = main_dirname(path)
  let _ = ensure_dir_tree(parent) catch {
    e => {
      println("Write error: \{e}")
      return false
    }
  }
  let _ = @fs.write_file(path, string_to_bytes(content), create=0o644) catch {
    e => {
      println("Write error: \{e}")
      return false
    }
  }
  true
}

///|
async fn copy_text_file_with_rewrite(
  from : String,
  to : String,
  old_text : String,
  new_text : String,
) -> Bool {
  let source = @fs.read_file(from).text() catch {
    e => {
      println("Build output error: failed to read \{from}: \{e}")
      return false
    }
  }
  write_text_file(
    to,
    rewrite_moonbit_js_runtime_text(source, old_text, new_text),
  )
}

///|
fn rewrite_moonbit_js_runtime_text(
  source : String,
  old_map_name : String,
  new_map_name : String,
) -> String {
  let with_map_name = source.replace_all(old=old_map_name, new=new_map_name)
  let rewritten = with_map_name.replace_all(
    old="= %identity;",
    new="= (x) => x;",
  )
  if rewritten.contains("require(") &&
    !rewritten.contains("__tsmbtCreateRequire") {
    "import { createRequire as __tsmbtCreateRequire } from \"node:module\";\nconst require = __tsmbtCreateRequire(import.meta.url);\n" +
    rewritten
  } else {
    rewritten
  }
}

///|
async fn copy_binary_file(from : String, to : String) -> Bool {
  let bytes = @fs.read_file(from) catch {
    e => {
      println("Build output error: failed to read \{from}: \{e}")
      return false
    }
  }
  let parent = main_dirname(to)
  let _ = ensure_dir_tree(parent) catch {
    e => {
      println("Write error: \{e}")
      return false
    }
  }
  let _ = @fs.write_file(to, bytes, create=0o644) catch {
    e => {
      println("Write error: \{e}")
      return false
    }
  }
  true
}

///|
async fn remove_moonbit_js_glue_dir(path : String) -> Unit {
  let _ = @fs.rmdir(path, recursive=true) catch { _ => () }
}

///|
fn collect_async_js_export_modes_from_glue(
  glue_mbt : String,
) -> Map[String, Bool] {
  let modes : Map[String, Bool] = {}
  for line_view in glue_mbt.split("\n") {
    let trimmed = line_view.trim().to_string()
    if !trimmed.has_prefix("pub async fn ") {
      continue
    }
    let rest = trimmed["pub async fn ".length():trimmed.length()]
      .trim()
      .to_string()
    match rest.find("(") {
      Some(open_idx) => {
        let name = rest[:open_idx].trim().to_string()
        if name != "" {
          modes[name] = trimmed.contains(" raise")
        }
      }
      None => ()
    }
  }
  modes
}

///|
fn render_async_js_export_wrappers(
  async_exports : Array[(String, String, Bool)],
) -> Array[String] {
  if async_exports.length() == 0 {
    return []
  }
  let lines : Array[String] = []
  lines.push(
    "function __tsmbt_async_finish(value, resolve, reject, preserveResult) {",
  )
  lines.push(
    "  if (!preserveResult && value && typeof value === \"object\" && \"$tag\" in value && \"_0\" in value) {",
  )
  lines.push(
    "    if (value.$tag === 1) { resolve(value._0); } else { reject(value._0); }",
  )
  lines.push("  } else {")
  lines.push("    resolve(value);")
  lines.push("  }")
  lines.push("}")
  lines.push(
    "function __tsmbt_async_result_to_promise(start, preserveResult) {",
  )
  lines.push("  return new Promise((resolve, reject) => {")
  lines.push("    let settled = false;")
  lines.push(
    "    const ok = (value) => { if (!settled) { settled = true; __tsmbt_async_finish(value, resolve, reject, preserveResult); } };",
  )
  lines.push(
    "    const err = (error) => { if (!settled) { settled = true; reject(error); } };",
  )
  lines.push("    try {")
  lines.push("      const value = start(ok, err);")
  lines.push("      if (value !== undefined) { ok(value); }")
  lines.push("    } catch (error) {")
  lines.push("      err(error);")
  lines.push("    }")
  lines.push("  });")
  lines.push("}")
  for item in async_exports {
    let (local_name, export_name, preserve_result) = item
    let preserve_result_js = if preserve_result { "true" } else { "false" }
    lines.push(
      "export function \{export_name}(...args) { const callArgs = args.slice(); while (callArgs.length < \{local_name}.length - 2) { callArgs.push(undefined); } return __tsmbt_async_result_to_promise((ok, err) => \{local_name}(...callArgs, ok, err), \{preserve_result_js}); }",
    )
  }
  lines
}

///|
fn rewrite_async_js_exports(
  source : String,
  async_modes : Map[String, Bool],
) -> String {
  if async_modes.length() == 0 {
    return source
  }
  let output_lines : Array[String] = []
  let async_exports : Array[(String, String, Bool)] = []
  let mut inserted_wrappers = false
  for line_view in source.split("\n") {
    let line = line_view.to_string()
    let trimmed = line.trim().to_string()
    if trimmed.has_prefix("export {") && trimmed.contains(" as ") {
      match (line.find("{"), line.rev_find("}")) {
        (Some(open_idx), Some(close_idx)) if close_idx > open_idx => {
          let inner = line[open_idx + 1:close_idx].to_string()
          let kept_specs : Array[String] = []
          for raw_spec in inner.split(",") {
            let spec = raw_spec.trim().to_string()
            if spec == "" {
              continue
            }
            match spec.find(" as ") {
              Some(as_idx) => {
                let local_name = spec[:as_idx].trim().to_string()
                let export_name = spec[as_idx + " as ".length():spec.length()]
                  .trim()
                  .to_string()
                match async_modes.get(export_name) {
                  Some(preserve_result) =>
                    async_exports.push(
                      (local_name, export_name, preserve_result),
                    )
                  None => kept_specs.push(spec)
                }
              }
              None => kept_specs.push(spec)
            }
          }
          if kept_specs.length() > 0 {
            output_lines.push("export { " + kept_specs.join(", ") + " }")
          }
          continue
        }
        _ => ()
      }
    }
    if !inserted_wrappers && trimmed.has_prefix("//# sourceMappingURL=") {
      for wrapper_line in render_async_js_export_wrappers(async_exports) {
        output_lines.push(wrapper_line)
      }
      inserted_wrappers = true
    }
    output_lines.push(line)
  }
  if !inserted_wrappers {
    for wrapper_line in render_async_js_export_wrappers(async_exports) {
      output_lines.push(wrapper_line)
    }
  }
  output_lines.join("\n")
}

///|
async fn rewrite_async_js_exports_file(
  path : String,
  async_modes : Map[String, Bool],
) -> Bool {
  if async_modes.length() == 0 {
    return true
  }
  let source = @fs.read_file(path).text() catch {
    e => {
      println("Read error: \{e}")
      return false
    }
  }
  write_text_file(path, rewrite_async_js_exports(source, async_modes))
}

///|
async fn build_moonbit_js_runtime_from_mbti(
  mbti_path : String,
  output_dir : String,
  bundle : @bridge.MbtiTypescriptScaffoldBundle,
) -> Bool {
  if bundle.autolink_glue_mbt == "" {
    println("Build error: no MoonBit JS glue exports were generated")
    return false
  }
  let context = match resolve_moonbit_js_build_context(mbti_path, output_dir) {
    Some(context) => context
    None => {
      println(
        "Build error: could not locate a MoonBit source package for \{mbti_path}; pass a package with real source, not only a pkg.generated.mbti fixture.",
      )
      return false
    }
  }
  remove_moonbit_js_glue_dir(context.glue_dir_path)
  let _ = ensure_dir_tree(context.glue_dir_path) catch {
    e => {
      println("Write error: \{e}")
      remove_moonbit_js_glue_dir(context.glue_dir_path)
      return false
    }
  }
  if !write_text_file(
      main_join_path(context.glue_dir_path, "moon.pkg.json"),
      bundle.moon_pkg_json,
    ) {
    remove_moonbit_js_glue_dir(context.glue_dir_path)
    return false
  }
  if !write_text_file(
      main_join_path(context.glue_dir_path, "glue.mbt"),
      bundle.autolink_glue_mbt,
    ) {
    remove_moonbit_js_glue_dir(context.glue_dir_path)
    return false
  }
  let (exit_code, output) = @process.collect_output_merged(
    "moon",
    ["build", "--target", "js", context.build_arg],
    cwd=context.module_root,
  )
  if exit_code != 0 {
    println("Build error: moon build --target js failed")
    println(output.text())
    remove_moonbit_js_glue_dir(context.glue_dir_path)
    return false
  }
  let built_js_name = context.glue_dir_name + ".js"
  let built_js_path = main_join_path(context.build_output_dir, built_js_name)
  let built_map_path = built_js_path + ".map"
  let output_js_path = main_join_path(output_dir, "index.js")
  let output_map_path = main_join_path(output_dir, "index.js.map")
  if !copy_text_file_with_rewrite(
      built_js_path,
      output_js_path,
      built_js_name + ".map",
      "index.js.map",
    ) {
    remove_moonbit_js_glue_dir(context.glue_dir_path)
    return false
  }
  if !rewrite_async_js_exports_file(
      output_js_path,
      collect_async_js_export_modes_from_glue(bundle.autolink_glue_mbt),
    ) {
    remove_moonbit_js_glue_dir(context.glue_dir_path)
    return false
  }
  if @fs.exists(built_map_path) {
    if !copy_binary_file(built_map_path, output_map_path) {
      remove_moonbit_js_glue_dir(context.glue_dir_path)
      return false
    }
  }
  remove_moonbit_js_glue_dir(context.glue_dir_path)
  true
}

///|
async fn write_typescript_scaffold_bundle_files(
  output_dir : String,
  bundle : @bridge.MbtiTypescriptScaffoldBundle,
) -> Bool {
  let _ = ensure_dir_tree(output_dir) catch {
    e => {
      println("Write error: \{e}")
      return false
    }
  }
  if !write_text_file(
      main_join_path(output_dir, "package.json"),
      bundle.package_json,
    ) {
    return false
  }
  if !write_text_file(
      main_join_path(output_dir, "AUTOLINK_DIAGNOSTICS.md"),
      bundle.autolink_diagnostics_md,
    ) {
    return false
  }
  for file in bundle.files {
    if !write_text_file(
        main_join_path(output_dir, file.relative_path),
        file.content,
      ) {
      return false
    }
  }
  true
}

///|
pub async fn emit_typescript_scaffold_from_mbti(
  file_path : String,
  output_dir : String,
  import_rewrite_path : String?,
) -> Bool {
  let import_rewrites = match
    load_typescript_import_rewrite_map(import_rewrite_path) {
    Some(rewrites) => rewrites
    None => return false
  }
  let bundle = @bridge.emit_typescript_scaffold_bundle_from_mbti_path_with_import_rewrites(
    file_path, import_rewrites,
  ) catch {
    @bridge.MbtiTypescriptDeclError::ReadError(msg)
    | @bridge.MbtiTypescriptDeclError::ParseError(msg) => {
      println("Emit error: \{cli_clean_error(msg)}")
      return false
    }
  }
  if !build_moonbit_js_runtime_from_mbti(file_path, output_dir, bundle) {
    return false
  }
  if !write_typescript_scaffold_bundle_files(output_dir, bundle) {
    return false
  }
  println("Wrote TypeScript scaffold to \{output_dir}")
  true
}

///|
pub async fn emit_typescript_facade_scaffold_from_mbti(
  file_path : String,
  output_dir : String,
  import_rewrite_path : String?,
) -> Bool {
  let import_rewrites = match
    load_typescript_import_rewrite_map(import_rewrite_path) {
    Some(rewrites) => rewrites
    None => return false
  }
  let bundle = @bridge.emit_typescript_facade_scaffold_bundle_from_mbti_path_with_import_rewrites(
    file_path, import_rewrites,
  ) catch {
    @bridge.MbtiTypescriptDeclError::ReadError(msg)
    | @bridge.MbtiTypescriptDeclError::ParseError(msg) => {
      println("Emit error: \{cli_clean_error(msg)}")
      return false
    }
  }
  if !build_moonbit_js_runtime_from_mbti(file_path, output_dir, bundle) {
    return false
  }
  if !write_typescript_scaffold_bundle_files(output_dir, bundle) {
    return false
  }
  println("Wrote TypeScript facade scaffold to \{output_dir}")
  true
}

///|
pub async fn emit_moonbit_js_ffi(
  file_path : String,
  module_spec : String,
  ffi_output_path : String?,
  bridge_output_path : String?,
) -> Bool {
  let bundle = emit_moonbit_js_ffi_texts(file_path, module_spec) catch {
    @bridge.ModuleGraphError::ReadError(msg)
    | @bridge.ModuleGraphError::ParseError(msg)
    | @bridge.ModuleGraphError::ResolveError(msg) => {
      println("Emit error: \{cli_clean_error(msg)}")
      return false
    }
  }
  match ffi_output_path {
    Some(path) => {
      let _ = @fs.write_file(
        path,
        string_to_bytes(bundle.ffi_mbt),
        create=0o644,
      ) catch {
        e => {
          println("Write error: \{e}")
          return false
        }
      }
      println("Wrote MoonBit JS FFI stubs to \{path}")
    }
    None => {
      println("=== ffi.mbt ===")
      println(bundle.ffi_mbt)
    }
  }
  match bridge_output_path {
    Some(path) => {
      let _ = @fs.write_file(
        path,
        string_to_bytes(bundle.bridge_js),
        create=0o644,
      ) catch {
        e => {
          println("Write error: \{e}")
          return false
        }
      }
      println("Wrote JS bridge to \{path}")
    }
    None => {
      println("=== bridge.js ===")
      println(bundle.bridge_js)
    }
  }
  true
}

///|
pub async fn emit_moonbit_bridge(
  file_path : String,
  module_spec : String,
  decl_output_path : String?,
  ffi_output_path : String?,
  bridge_output_path : String?,
) -> Bool {
  let bundle = emit_moonbit_bridge_texts(file_path, module_spec) catch {
    @bridge.ModuleGraphError::ReadError(msg)
    | @bridge.ModuleGraphError::ParseError(msg)
    | @bridge.ModuleGraphError::ResolveError(msg) => {
      println("Emit error: \{cli_clean_error(msg)}")
      return false
    }
  }
  match decl_output_path {
    Some(path) => {
      let _ = @fs.write_file(
        path,
        string_to_bytes(bundle.decl_mbt),
        create=0o644,
      ) catch {
        e => {
          println("Write error: \{e}")
          return false
        }
      }
      println("Wrote MoonBit declarations to \{path}")
    }
    None => {
      println("=== bridge.mbti ===")
      println(bundle.decl_mbt)
    }
  }
  match ffi_output_path {
    Some(path) => {
      let _ = @fs.write_file(
        path,
        string_to_bytes(bundle.ffi_mbt),
        create=0o644,
      ) catch {
        e => {
          println("Write error: \{e}")
          return false
        }
      }
      println("Wrote MoonBit JS FFI stubs to \{path}")
    }
    None => {
      println("=== bridge.mbt ===")
      println(bundle.ffi_mbt)
    }
  }
  match bridge_output_path {
    Some(path) => {
      let _ = @fs.write_file(
        path,
        string_to_bytes(bundle.bridge_js),
        create=0o644,
      ) catch {
        e => {
          println("Write error: \{e}")
          return false
        }
      }
      println("Wrote JS bridge to \{path}")
    }
    None => {
      println("=== bridge.js ===")
      println(bundle.bridge_js)
    }
  }
  true
}

///|
pub async fn emit_moonbit_bridge_package(
  file_path : String,
  module_spec : String,
  output_dir : String,
  bare_module_specifier? : String? = None,
) -> Bool {
  let bundle = emit_moonbit_bridge_package_texts(file_path, module_spec) catch {
    @bridge.ModuleGraphError::ReadError(msg)
    | @bridge.ModuleGraphError::ParseError(msg)
    | @bridge.ModuleGraphError::ResolveError(msg) => {
      println("Emit error: \{cli_clean_error(msg)}")
      return false
    }
  }
  if !@fs.exists(output_dir) {
    let _ = ensure_dir_tree(output_dir) catch {
      e => {
        println("Write error: \{e}")
        return false
      }
    }
  }
  // `#module(...)` only accepts npm-style bare specifiers — no relative
  // or absolute filesystem paths. The generated bridge therefore always
  // references its sibling `bridge.js` through a bare specifier under
  // the `@tsmbt-bridge/` scope. Callers can override the slug; the
  // default derives it from the output directory name.
  let resolved_specifier = match bare_module_specifier {
    Some(name) => name
    None => default_bridge_bare_specifier(output_dir)
  }
  let bridge_mbt = rewrite_bridge_package_module_path(
    bundle.bridge_mbt,
    resolved_specifier,
  )
  let package_json = render_bridge_package_json(resolved_specifier)
  let files : Array[(String, String)] = [
    ("moon.pkg.json", bundle.moon_pkg_json),
    ("bridge.mbti", bundle.bridge_mbti),
    ("package.json", package_json),
  ]
  for file in bridge_package_mbt_files(bridge_mbt, force_split=false) {
    files.push(file)
  }
  files.push(("bridge.js", bundle.bridge_js))
  // Scope-style specifiers resolve via npm node_modules layout; refresh
  // the sibling symlink so `require("@tsmbt-bridge/<safe>")` from
  // generated test code lands at the bridge dir. `#`-prefix specifiers
  // resolve via package.json imports field instead; nothing to symlink.
  if !ensure_bridge_node_modules_link(output_dir, resolved_specifier) {
    return false
  }
  for file in files {
    let (name, content) = file
    let path = join_output_path(output_dir, name)
    let _ = @fs.write_file(path, string_to_bytes(content), create=0o644) catch {
      e => {
        println("Write error: \{e}")
        return false
      }
    }
  }
  println("Wrote MoonBit bridge package to \{output_dir}")
  true
}

///|
fn scaffold_diagnostic_export_name(item : String) -> String {
  match item.find(" (") {
    Some(idx) => item[:idx].to_string()
    None => item
  }
}

///|
fn scaffold_diagnostic_reason(item : String) -> String {
  if item.contains("ambiguous re-export") {
    "ambiguous re-export surface"
  } else {
    "unsupported export surface"
  }
}

///|
fn scaffold_diagnostic_decision(item : String) -> String {
  if item.contains("ambiguous re-export") {
    "widened"
  } else {
    "omitted"
  }
}

///|
fn scaffold_diagnostic_runtime_safety(item : String) -> String {
  if item.contains("ambiguous re-export") {
    "runtime-unsafe; generated bridge stubs abort instead of guessing a runtime binding"
  } else {
    "runtime-safe; the unsupported export is not exposed"
  }
}

///|
fn render_moonbit_scaffold_diagnostics_md(
  unsupported_exports : Array[String],
) -> String {
  let lines = [
    "# Scaffold Diagnostics", "", "The generated MoonBit scaffold is buildable. Unsupported or ambiguous export surfaces are listed below with the decision taken by the generator.",
    "", "## Summary",
  ]
  if unsupported_exports.length() > 0 {
    lines.push("")
    lines.push("| export | decision | reason | runtime safety |")
    lines.push("| --- | --- | --- | --- |")
    for item in unsupported_exports {
      let export_name = scaffold_diagnostic_export_name(item)
      let decision = scaffold_diagnostic_decision(item)
      let reason = scaffold_diagnostic_reason(item)
      let runtime_safety = scaffold_diagnostic_runtime_safety(item)
      lines.push(
        "| `" +
        export_name +
        "` | " +
        decision +
        " | " +
        reason +
        " | " +
        runtime_safety +
        " |",
      )
    }
    lines.push("")
    lines.push("## Runtime Safety")
    lines.push("")
    lines.push(
      "Widened surfaces keep the scaffold buildable, but ambiguous runtime exports are not callable until the source export is made unambiguous.",
    )
    lines.push(
      "Omitted surfaces are intentionally absent from the generated MoonBit API. Bridge-wrapped surfaces are callable through generated `bridge.js` glue when the runtime binding can be resolved.",
    )
    lines.push("")
    lines.push("## Decision Vocabulary")
    lines.push("")
    lines.push(
      "- `widened`: emitted as `JSValue` so dependent code can still build",
    )
    lines.push("- `omitted`: not emitted")
    lines.push("- `bridge-wrapped`: emitted through generated `bridge.js` glue")
    lines.push("")
    lines.push("## Raw Entries")
    lines.push("")
    for item in unsupported_exports {
      lines.push("- " + item)
    }
  } else {
    lines.push("")
    lines.push("No unsupported exports were detected.")
  }
  lines.join("\n")
}

///|
async fn collect_moonbit_ts_scaffold_unsupported_exports(
  file_path : String,
) -> Array[String] raise @bridge.ModuleGraphError {
  @bridge.collect_moonbit_ts_scaffold_unsupported_exports(file_path)
}

///|
pub async fn emit_moonbit_scaffold_from_ts(
  file_path : String,
  module_spec : String,
  output_dir : String,
  write_diagnostics? : Bool = true,
  bare_module_specifier? : String? = None,
) -> Bool {
  let unsupported_exports = collect_moonbit_ts_scaffold_unsupported_exports(
    file_path,
  ) catch {
    @bridge.ModuleGraphError::ReadError(msg)
    | @bridge.ModuleGraphError::ParseError(msg)
    | @bridge.ModuleGraphError::ResolveError(msg) => {
      println("Emit error: \{cli_clean_error(msg)}")
      return false
    }
  }
  if !emit_moonbit_bridge_package(
      file_path,
      module_spec,
      output_dir,
      bare_module_specifier~,
    ) {
    return false
  }
  // The unified `--input/--out` driver emits a richer SCAFFOLD_DIAGNOSTICS.md
  // (with JSValue fallbacks). Skip the inner write when called from there
  // to avoid the duplicate "Wrote scaffold diagnostics" log line and a
  // shorter file getting overwritten by the unified renderer anyway.
  if !write_diagnostics {
    return true
  }
  // Always emit SCAFFOLD_DIAGNOSTICS.md so direct subcommand callers can
  // inspect even the happy-path "no unsupported exports" report.
  let diagnostics_path = join_output_path(output_dir, "SCAFFOLD_DIAGNOSTICS.md")
  let diagnostics_md = render_moonbit_scaffold_diagnostics_md(
    unsupported_exports,
  )
  let _ = @fs.write_file(
    diagnostics_path,
    string_to_bytes(diagnostics_md),
    create=0o644,
  ) catch {
    e => {
      println("Write error: \{e}")
      return false
    }
  }
  println("Wrote scaffold diagnostics to \{diagnostics_path}")
  true
}

///|
fn escape_moonbit_module_path(path : String) -> String {
  let mut escaped = ""
  for c in path {
    if c == '\\' {
      escaped += "\\\\"
    } else if c == '"' {
      escaped += "\\\""
    } else {
      escaped += c.to_string()
    }
  }
  escaped
}

///|
fn bridge_binding_needs_generated_module(line : String) -> Bool {
  line.contains("extern \"js\" fn ") && line.contains(" = \"__ts_mbt_")
}

///|
/// Strip the leading `@<scope>/` prefix from a bare specifier,
/// returning `(scope, name)`. Returns `None` when the input doesn't
/// look like an npm scope specifier (e.g. unscoped names or
/// `#`-prefix Node imports specifiers).
fn split_scoped_specifier(specifier : String) -> (String, String)? {
  if !specifier.has_prefix("@") {
    return None
  }
  match specifier.find("/") {
    None => None
    Some(idx) => {
      let scope = specifier[:idx].to_string()
      let name = specifier[idx + 1:specifier.length()].to_string()
      Some((scope, name))
    }
  }
}

///|
/// Resolve the consumer's moon module root by walking up from the
/// generated bridge directory. Returns `None` when the bridge isn't
/// inside any moon module.
async fn resolve_consumer_moon_module_root(
  bridge_output_dir : String,
) -> String? {
  let realpath = @fs.realpath(bridge_output_dir) catch {
    _ => bridge_output_dir
  }
  let parent = main_dirname(realpath)
  find_nearest_moon_mod_dir(parent)
}

///|
/// Create / refresh `<consumer>/node_modules/@<scope>/<name>` pointing
/// at the bridge dir so node's `require()`/`import` for the bare
/// specifier resolves at build time. Skips silently for `#`-prefix
/// specifiers (they don't need node_modules at all) and for bridges
/// not under a moon module (we can't infer where to write).
///
/// The link target is computed relative to the consumer module root
/// so the bridge stays portable when the moon module is moved.
async fn ensure_bridge_node_modules_link(
  bridge_output_dir : String,
  bare_specifier : String,
) -> Bool {
  let (scope, name) = match split_scoped_specifier(bare_specifier) {
    Some(parts) => parts
    None => return true
  }
  let module_root = match resolve_consumer_moon_module_root(bridge_output_dir) {
    Some(root) => root
    None => return true
  }
  let scope_dir = main_join_path(
    main_join_path(module_root, "node_modules"),
    scope,
  )
  let _ = ensure_dir_tree(scope_dir) catch {
    e => {
      println("vendor: failed to create \{scope_dir}: \{e}")
      return false
    }
  }
  let link_path = main_join_path(scope_dir, name)
  let _ = @fs.remove(link_path) catch { _ => () }
  let bridge_real = @fs.realpath(bridge_output_dir) catch {
    _ => bridge_output_dir
  }
  let module_real = @fs.realpath(module_root) catch { _ => module_root }
  let bridge_rel_to_module = match strip_dir_prefix(module_real, bridge_real) {
    Some(rest) => rest
    None => bridge_real
  }
  let link_rel_to_module = "node_modules/" + scope + "/" + name
  let target = relative_path_between(link_rel_to_module, bridge_rel_to_module)
  let _ = @fs.symlink(link_path, target~) catch {
    e => {
      println("vendor: failed to symlink \{link_path} -> \{target}: \{e}")
      return false
    }
  }
  true
}

///|
/// POSIX relative path from `from_rel` to `to_rel` where both are
/// paths relative to the same anchor. Each `..` segment moves up
/// one directory in `from_rel`'s parents before descending into
/// `to_rel`. Used for portable symlink targets.
fn relative_path_between(from_rel : String, to_rel : String) -> String {
  let from_parts = split_path_segments(from_rel)
  let to_parts = split_path_segments(to_rel)
  let from_dir = from_parts[:from_parts.length() - 1].to_array()
  let mut common = 0
  let limit = if from_dir.length() < to_parts.length() {
    from_dir.length()
  } else {
    to_parts.length()
  }
  for i in 0..<limit {
    if from_dir[i] == to_parts[i] {
      common += 1
    } else {
      break
    }
  }
  let segments : Array[String] = []
  for _ in common..<from_dir.length() {
    segments.push("..")
  }
  for i in common..<to_parts.length() {
    segments.push(to_parts[i])
  }
  if segments.length() == 0 {
    "."
  } else {
    segments.join("/")
  }
}

///|
fn split_path_segments(path : String) -> Array[String] {
  let segments : Array[String] = []
  for chunk in path.split("/") {
    let s = chunk.to_string()
    if s != "" && s != "." {
      segments.push(s)
    }
  }
  segments
}

///|
/// Derive a default `@tsmbt-bridge/<slug>` bare specifier from the
/// output directory path. The basename is sanitized so it survives as
/// an npm package-name segment (`[a-z0-9_-]`).
///
/// Scaffold-style outputs (where consumer `.mbt` files and `bridge.js`
/// sit at the same moon module root) use this default and rely on a
/// sibling `node_modules/@tsmbt-bridge/<slug>` symlink for resolution.
/// Vendor-style outputs override with `#tsmbt-bridge/<slug>` and route
/// resolution through the consumer's `package.json#imports` map
/// instead — the symlink approach is incompatible with `pnpm install`
/// which wipes ad-hoc node_modules entries.
fn default_bridge_bare_specifier(output_dir : String) -> String {
  let basename = match output_dir.rev_find("/") {
    Some(idx) => output_dir[idx + 1:output_dir.length()].to_string()
    None => output_dir
  }
  let mut slug = ""
  for c in basename {
    if (c >= 'a' && c <= 'z') ||
      (c >= 'A' && c <= 'Z') ||
      (c >= '0' && c <= '9') ||
      c == '-' ||
      c == '_' {
      slug += c.to_string()
    } else {
      slug += "_"
    }
  }
  if slug == "" {
    slug = "bridge"
  }
  "@tsmbt-bridge/" + slug
}

///|
/// Render the `package.json` co-located with `bridge.{mbti,mbt,js}`.
/// Always declares `"type": "module"` so node treats `bridge.js` as
/// ESM regardless of the consumer's outer package.json.
///
/// For npm-scope specifiers (`@tsmbt-bridge/<slug>`) the file also
/// declares `name` so `node_modules/@<scope>/<name>` resolution lands
/// here. For Node imports-field specifiers (`#tsmbt-bridge/<slug>`)
/// the file declares the matching `imports` mapping so calling code
/// inside the same package boundary can resolve the specifier
/// directly; consumers outside this boundary still need a wildcard
/// `imports` entry in their own package.json — that is what
/// `print_vendor_package_json_imports_hint` walks the user through.
fn render_bridge_package_json(bare_specifier : String) -> String {
  if bare_specifier.has_prefix("#") {
    "{\n  \"type\": \"module\",\n  \"main\": \"bridge.js\",\n  \"imports\": {\n    \"" +
    ffi_escape_json_string(bare_specifier) +
    "\": \"./bridge.js\"\n  },\n  \"private\": true\n}\n"
  } else {
    "{\n  \"name\": \"" +
    ffi_escape_json_string(bare_specifier) +
    "\",\n  \"version\": \"0.0.0\",\n  \"type\": \"module\",\n  \"main\": \"bridge.js\",\n  \"private\": true\n}\n"
  }
}

///|
/// Minimal JSON string escaper for the small subset of characters
/// that appear in a `bare_specifier` we generated ourselves
/// (`[#@a-zA-Z0-9-_/]`). Backslash and quote pass-through suffices;
/// we never embed control characters.
fn ffi_escape_json_string(s : String) -> String {
  let mut out = ""
  for c in s {
    if c == '"' {
      out += "\\\""
    } else if c == '\\' {
      out += "\\\\"
    } else {
      out += c.to_string()
    }
  }
  out
}

///|
fn rewrite_bridge_package_module_path(
  bridge_mbt : String,
  bridge_js_path : String,
) -> String {
  let rewritten : Array[String] = []
  let module_decl = "#module(\"" +
    escape_moonbit_module_path(bridge_js_path) +
    "\")"
  for line_view in bridge_mbt.split("\n") {
    let line = line_view.to_string()
    if bridge_binding_needs_generated_module(line) {
      rewritten.push(module_decl)
    }
    rewritten.push(line)
  }
  rewritten.join("\n")
}

///|
let bridge_package_split_line_threshold : Int = 2000

///|
fn bridge_package_mbt_line_count(source : String) -> Int {
  if source == "" {
    0
  } else {
    let mut count = 0
    for _ in source.split("\n") {
      count += 1
    }
    count
  }
}

///|
fn bridge_package_split_top_level_blocks(source : String) -> Array[String] {
  let blocks : Array[String] = []
  let mut current : Array[String] = []
  for line_view in source.split("\n") {
    let line = line_view.to_string()
    if line.trim() == "" {
      if current.length() > 0 {
        blocks.push(current.join("\n"))
        current = []
      }
    } else {
      current.push(line)
    }
  }
  if current.length() > 0 {
    blocks.push(current.join("\n"))
  }
  blocks
}

///|
fn bridge_package_is_type_block(block : String) -> Bool {
  let trimmed = block.trim()
  trimmed.has_prefix("pub type ") ||
  trimmed.contains("#external\ntype ") ||
  trimmed.contains("#external\npub type ") ||
  trimmed.contains("\npub(all) enum ") ||
  trimmed.has_prefix("pub(all) enum ") ||
  trimmed.contains("\npub(all) struct ") ||
  trimmed.has_prefix("pub(all) struct ") ||
  trimmed.contains("Unsupported export ")
}

///|
fn bridge_package_is_converter_block(block : String) -> Bool {
  let trimmed = block.trim()
  trimmed.has_prefix("fn __ts_mbt_") ||
  (
    trimmed.contains("extern \"js\" fn __ts_mbt_") &&
    (trimmed.contains("_to_js") || trimmed.contains("_from_js"))
  )
}

///|
fn bridge_package_is_guard_block(block : String) -> Bool {
  block.contains("unsafeCast") ||
  (block.contains("::as") && block.contains(" -> ") && block.contains("?"))
}

///|
fn bridge_package_review_file_content(
  section_name : String,
  blocks : Array[String],
) -> String {
  if blocks.length() == 0 {
    "///|\n/// Generated bridge \{section_name} section is empty."
  } else {
    blocks.join("\n\n")
  }
}

///|
fn bridge_package_mbt_files(
  bridge_mbt : String,
  force_split~ : Bool,
) -> Array[(String, String)] {
  if !force_split &&
    bridge_package_mbt_line_count(bridge_mbt) <=
    bridge_package_split_line_threshold {
    return [("bridge.mbt", bridge_mbt)]
  }
  let type_blocks : Array[String] = []
  let converter_blocks : Array[String] = []
  let extern_blocks : Array[String] = []
  let guard_blocks : Array[String] = []
  let bridge_blocks : Array[String] = []
  for block in bridge_package_split_top_level_blocks(bridge_mbt) {
    if bridge_package_is_type_block(block) {
      type_blocks.push(block)
    } else if bridge_package_is_converter_block(block) {
      converter_blocks.push(block)
    } else if bridge_package_is_guard_block(block) {
      guard_blocks.push(block)
    } else if block.contains("extern \"js\" fn ") {
      extern_blocks.push(block)
    } else {
      bridge_blocks.push(block)
    }
  }
  [
    ("types.mbt", bridge_package_review_file_content("types", type_blocks)),
    (
      "converters.mbt",
      bridge_package_review_file_content("converters", converter_blocks),
    ),
    (
      "externs.mbt",
      bridge_package_review_file_content("externs", extern_blocks),
    ),
    ("guards.mbt", bridge_package_review_file_content("guards", guard_blocks)),
    (
      "bridge.mbt",
      bridge_package_review_file_content("public wrappers", bridge_blocks),
    ),
  ]
}

///|
async fn emit_moonbit_js_ffi_texts(
  file_path : String,
  module_spec : String,
) -> @bridge.MoonBitJsFfiBundle raise @bridge.ModuleGraphError {
  @bridge.emit_moonbit_js_ffi_bundle_from_entry_path(file_path, module_spec)
}

///|
async fn emit_moonbit_bridge_texts(
  file_path : String,
  module_spec : String,
) -> @bridge.MoonBitTsBridgeBundle raise @bridge.ModuleGraphError {
  @bridge.emit_moonbit_ts_bridge_bundle_from_entry_path(file_path, module_spec)
}

///|
async fn emit_moonbit_bridge_package_texts(
  file_path : String,
  module_spec : String,
) -> @bridge.MoonBitTsBridgePackageBundle raise @bridge.ModuleGraphError {
  @bridge.emit_moonbit_ts_bridge_package_bundle_from_entry_path(
    file_path, module_spec,
  )
}

///|
fn join_output_path(base : String, child : String) -> String {
  if base.has_suffix("/") {
    base + child
  } else {
    base + "/" + child
  }
}

///|
fn string_to_bytes(s : String) -> Bytes {
  let arr : Array[Byte] = []
  for i = 0; i < s.length(); i = i + 1 {
    arr.push((s[i].to_int() & 0xFF).to_byte())
  }
  Bytes::from_array(arr)
}
