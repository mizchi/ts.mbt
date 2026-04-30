///|
fn cli_command_failed() -> Unit {
  println("tsmbt command failed")
  cli_exit(1)
}

///|
#cfg(target="native")
extern "C" fn cli_exit(code : Int) = "exit"

///|
#cfg(not(target="native"))
fn cli_exit(code : Int) -> Unit {
  let _ = code
  abort("tsmbt command failed")
}

///|
async fn main_async() -> Unit {
  let args = @env.args()
  if args.length() < 2 {
    print_usage()
    return
  }
  if args[1].has_prefix("--") {
    if !run_unified_tsmbt_cli(args, 1) {
      cli_command_failed()
    }
    return
  }
  let command = args[1]
  match command {
    "generate" | "scaffold" =>
      if !run_unified_tsmbt_cli(args, 2) {
        cli_command_failed()
      }
    "run" => {
      if args.length() < 3 {
        println("Error: no file specified")
        return
      }
      let file_path = args[2]
      run_ts_file(file_path)
    }
    "experimental-emit-gc" => {
      if args.length() < 3 {
        println("Error: no file specified")
        return
      }
      let file_path = args[2]
      let output_path = if args.length() >= 4 { args[3] } else { "out.wasm" }
      experimental_emit_wasm_gc(file_path, output_path)
    }
    "test262" => {
      if args.length() < 3 {
        println("Error: no test directory or file specified")
        return
      }
      let test_path = args[2]
      run_test262(test_path)
    }
    "experimental-analyze" | "experimental-aot-check" => {
      if args.length() < 3 {
        println("Error: no file specified")
        return
      }
      let file_path = args[2]
      experimental_analyze_aot(file_path)
    }
    "emit-moonbit-decl" => {
      if args.length() < 3 {
        println("Error: no file specified")
        return
      }
      let file_path = args[2]
      let output_path = if args.length() >= 4 { Some(args[3]) } else { None }
      emit_moonbit_decl(file_path, output_path)
    }
    "normalize-moonbit-dts" => {
      if args.length() < 3 {
        println("Error: no file specified")
        return
      }
      let file_path = args[2]
      let output_path = if args.length() >= 4 { Some(args[3]) } else { None }
      emit_typescript_decl(file_path, output_path)
    }
    "emit-typescript-from-mbti" => {
      if args.length() < 3 {
        println("Error: no file specified")
        return
      }
      let file_path = args[2]
      let output_path = if args.length() >= 4 { Some(args[3]) } else { None }
      emit_typescript_decl_from_mbti(file_path, output_path)
    }
    "emit-js-link-config-from-mbti" => {
      if args.length() < 3 {
        println("Error: no file specified")
        return
      }
      let file_path = args[2]
      let output_path = if args.length() >= 4 { Some(args[3]) } else { None }
      emit_js_link_config_from_mbti(file_path, output_path)
    }
    "emit-typescript-package-from-mbti" => {
      if args.length() < 4 {
        println("Error: expected <file> <out-dir>")
        return
      }
      let file_path = args[2]
      let output_dir = args[3]
      let import_rewrite_path = if args.length() >= 5 {
        Some(args[4])
      } else {
        None
      }
      emit_typescript_package_from_mbti(
        file_path, output_dir, import_rewrite_path,
      )
    }
    "emit-typescript-scaffold-from-mbti" => {
      if args.length() < 4 {
        println("Error: expected <file> <out-dir>")
        return
      }
      let file_path = args[2]
      let output_dir = args[3]
      let import_rewrite_path = if args.length() >= 5 {
        Some(args[4])
      } else {
        None
      }
      if !emit_typescript_scaffold_from_mbti(
          file_path, output_dir, import_rewrite_path,
        ) {
        cli_command_failed()
      }
    }
    "emit-typescript-facade-scaffold-from-mbti" => {
      if args.length() < 4 {
        println("Error: expected <file> <out-dir>")
        return
      }
      let file_path = args[2]
      let output_dir = args[3]
      let import_rewrite_path = if args.length() >= 5 {
        Some(args[4])
      } else {
        None
      }
      if !emit_typescript_facade_scaffold_from_mbti(
          file_path, output_dir, import_rewrite_path,
        ) {
        cli_command_failed()
      }
    }
    "emit-moonbit-js-ffi" => {
      if args.length() < 4 {
        println("Error: expected <entry> <module-spec>")
        return
      }
      let file_path = args[2]
      let module_spec = args[3]
      let ffi_output_path = if args.length() >= 5 {
        Some(args[4])
      } else {
        None
      }
      let bridge_output_path = if args.length() >= 6 {
        Some(args[5])
      } else {
        None
      }
      emit_moonbit_js_ffi(
        file_path, module_spec, ffi_output_path, bridge_output_path,
      )
    }
    "emit-moonbit-bridge" => {
      if args.length() < 4 {
        println("Error: expected <ts-entry> <module-spec>")
        return
      }
      let file_path = args[2]
      let module_spec = args[3]
      let decl_output_path = if args.length() >= 5 {
        Some(args[4])
      } else {
        None
      }
      let ffi_output_path = if args.length() >= 6 {
        Some(args[5])
      } else {
        None
      }
      let bridge_output_path = if args.length() >= 7 {
        Some(args[6])
      } else {
        None
      }
      emit_moonbit_bridge(
        file_path, module_spec, decl_output_path, ffi_output_path, bridge_output_path,
      )
    }
    "emit-moonbit-bridge-package" => {
      if args.length() < 5 {
        println("Error: expected <ts-entry> <module-spec> <out-dir>")
        return
      }
      let file_path = args[2]
      let module_spec = args[3]
      let output_dir = args[4]
      emit_moonbit_bridge_package(file_path, module_spec, output_dir)
    }
    "emit-moonbit-scaffold-from-ts" => {
      if args.length() < 5 {
        println("Error: expected <ts-entry> <module-spec> <out-dir>")
        return
      }
      let file_path = args[2]
      let module_spec = args[3]
      let output_dir = args[4]
      emit_moonbit_scaffold_from_ts(file_path, module_spec, output_dir)
    }
    "benchmark-project" => {
      if args.length() < 3 {
        println("Error: expected <root>")
        return
      }
      let root = args[2]
      let limit = if args.length() >= 4 {
        match parse_project_benchmark_limit(args[3]) {
          Some(limit) => limit
          None => {
            println(
              "Error: invalid limit '\{args[3]}', expected non-negative integer",
            )
            return
          }
        }
      } else {
        benchmark_project_default_limit()
      }
      run_project_benchmark(root, limit)
    }
    "benchmark-corpora" => {
      let limit = if args.length() >= 3 {
        match parse_project_benchmark_limit(args[2]) {
          Some(limit) => limit
          None => {
            println(
              "Error: invalid limit '\{args[2]}', expected non-negative integer",
            )
            return
          }
        }
      } else {
        benchmark_project_default_limit()
      }
      run_benchmark_corpora(limit)
    }
    _ => {
      println("Unknown command: \{command}")
      print_usage()
    }
  }
}

///|
fn main {
  @async.run_async_main(main_async)
}

///|
fn print_usage() -> Unit {
  println(
    "Usage: tsmbt [--input <pkg-or-entry> --out <dir>] [command] [args...]",
  )
  println("")
  println("Commands:")
  for line in command_help_lines() {
    println(line)
  }
}

///|
fn command_help_lines() -> Array[String] {
  [
    "  run <file>           Run a TypeScript/JavaScript file", "  experimental-emit-gc <file> [out] Emit experimental wasm-gc binary (default: out.wasm)",
    "  test262 <path>       Run test262 tests (file or directory)", "  experimental-analyze <file> Analyze experimental AOT compilability of functions",
    "  experimental-aot-check <file> Alias for experimental-analyze", "  emit-moonbit-decl <file> [out] Emit MoonBit declare stubs from a TypeScript entrypoint",
    "  normalize-moonbit-dts <file> [out] Normalize MoonBit-generated TypeScript declarations into clearer .d.ts output",
    "  emit-typescript-from-mbti <file> [out] Emit TypeScript declarations directly from a MoonBit .mbti interface",
    "  emit-js-link-config-from-mbti <file> [out] Emit MoonBit link.js.exports config from a .mbti interface",
    "  emit-typescript-package-from-mbti <file> <out-dir> [import-rewrite-json] Emit a recursive TypeScript declaration package from a root .mbti interface",
    "  emit-typescript-scaffold-from-mbti <file> <out-dir> [import-rewrite-json] Emit build-backed JS/TypeScript scaffold from a MoonBit package interface",
    "  emit-typescript-facade-scaffold-from-mbti <file> <out-dir> [import-rewrite-json] Emit build-backed JS/TypeScript scaffold plus facade wrappers for omitted local methods",
    "  --input <pkg-or-entry> --out <dir> [--direction auto|mbt-to-ts|ts-to-mbt] [--module-spec <specifier>] [--diagnostics <path>] [--strict] Generate a complete build-backed bridge scaffold in either direction",
    "  emit-moonbit-js-ffi <file> <module-spec> [ffi-out] [bridge-out] Emit MoonBit JS FFI stubs and ESM bridge from a TypeScript entrypoint",
    "  emit-moonbit-bridge <file> <module-spec> [decl-out] [ffi-out] [bridge-out] Emit a full MoonBit bridge bundle from a TS entrypoint",
    "  emit-moonbit-bridge-package <file> <module-spec> <out-dir> Emit a generated MoonBit bridge package directory",
    "  emit-moonbit-scaffold-from-ts <file> <module-spec> <out-dir> Emit a MoonBit bridge scaffold from a TS entrypoint",
    "  benchmark-project <root> [limit] Benchmark local TS/.d.ts corpus coverage",
    "  benchmark-corpora [limit] Benchmark built-in local and optional real-world corpora",
  ]
}

///|
async fn experimental_analyze_aot(file_path : String) -> Unit {
  let content = @fs.read_file(file_path).text() catch {
    e => {
      println("Error reading file: \{e}")
      return
    }
  }
  let parser = @parser.Parser::from_source(content)
  let ts_module = parser.parse_module() catch {
    e => {
      println("Parse error: \{e}")
      return
    }
  }
  println("=== AOT Compilability Analysis ===")
  println("File: \{file_path}")
  println("")
  let mut compilable_count = 0
  let mut not_compilable_count = 0
  let compilable_funcs : Array[String] = []
  let not_compilable_funcs : Array[(String, String)] = []
  for func in ts_module.funcs {
    match @analysis.can_compile_to_wasm(func) {
      @analysis.CompilabilityResult::Compilable => {
        compilable_count += 1
        compilable_funcs.push(func.name)
      }
      @analysis.CompilabilityResult::NotCompilable(reason) => {
        not_compilable_count += 1
        not_compilable_funcs.push((func.name, reason))
      }
    }
  }
  let total = compilable_count + not_compilable_count
  let pct = if total > 0 { compilable_count * 100 / total } else { 0 }
  println("Total functions: \{total}")
  println("AOT compilable:  \{compilable_count} (\{pct}%)")
  println("Not compilable:  \{not_compilable_count}")
  println("")
  if compilable_funcs.length() > 0 {
    println("✓ Compilable functions:")
    for name in compilable_funcs {
      println("  - \{name}")
    }
    println("")
  }
  if not_compilable_funcs.length() > 0 {
    println("✗ Not compilable functions:")
    for item in not_compilable_funcs {
      let (name, reason) = item
      println("  - \{name}: \{reason}")
    }
  }
}

///|
async fn emit_moonbit_decl(file_path : String, output_path : String?) -> Unit {
  let emitted = emit_moonbit_decl_text(file_path) catch {
    @bridge.ModuleGraphError::ReadError(msg)
    | @bridge.ModuleGraphError::ParseError(msg)
    | @bridge.ModuleGraphError::ResolveError(msg) => {
      println("Emit error: \{msg}")
      return
    }
  }
  match output_path {
    Some(path) => {
      let _ = @fs.write_file(path, string_to_bytes(emitted), create=0o644) catch {
        e => {
          println("Write error: \{e}")
          return
        }
      }
      println("Wrote MoonBit declarations to \{path}")
    }
    None => println(emitted)
  }
}

///|
async fn emit_moonbit_decl_text(
  file_path : String,
) -> String raise @bridge.ModuleGraphError {
  @bridge.emit_moonbit_decl_from_entry_path(file_path)
}

///|
async fn emit_typescript_decl(
  file_path : String,
  output_path : String?,
) -> Unit {
  let emitted = emit_typescript_decl_text(file_path) catch {
    @bridge.ModuleGraphError::ReadError(msg)
    | @bridge.ModuleGraphError::ParseError(msg)
    | @bridge.ModuleGraphError::ResolveError(msg) => {
      println("Emit error: \{msg}")
      return
    }
  }
  match output_path {
    Some(path) => {
      let _ = @fs.write_file(path, string_to_bytes(emitted), create=0o644) catch {
        e => {
          println("Write error: \{e}")
          return
        }
      }
      println("Wrote normalized TypeScript declarations to \{path}")
    }
    None => println(emitted)
  }
}

///|
async fn emit_typescript_decl_text(
  file_path : String,
) -> String raise @bridge.ModuleGraphError {
  @bridge.normalize_moonbit_generated_typescript_decl_from_entry_path(file_path)
}

///|
async fn emit_typescript_decl_from_mbti(
  file_path : String,
  output_path : String?,
) -> Unit {
  let emitted = emit_typescript_decl_from_mbti_text(file_path) catch {
    @bridge.MbtiTypescriptDeclError::ReadError(msg)
    | @bridge.MbtiTypescriptDeclError::ParseError(msg) => {
      println("Emit error: \{msg}")
      return
    }
  }
  match output_path {
    Some(path) => {
      let _ = @fs.write_file(path, string_to_bytes(emitted), create=0o644) catch {
        e => {
          println("Write error: \{e}")
          return
        }
      }
      println("Wrote TypeScript declarations to \{path}")
    }
    None => println(emitted)
  }
}

///|
async fn emit_typescript_decl_from_mbti_text(
  file_path : String,
) -> String raise @bridge.MbtiTypescriptDeclError {
  @bridge.emit_typescript_decl_from_mbti_path(file_path)
}

///|
async fn emit_js_link_config_from_mbti(
  file_path : String,
  output_path : String?,
) -> Unit {
  let emitted = emit_js_link_config_from_mbti_text(file_path) catch {
    @bridge.MbtiJsLinkConfigError::ReadError(msg)
    | @bridge.MbtiJsLinkConfigError::ParseError(msg) => {
      println("Emit error: \{msg}")
      return
    }
  }
  match output_path {
    Some(path) => {
      let _ = @fs.write_file(path, string_to_bytes(emitted), create=0o644) catch {
        e => {
          println("Write error: \{e}")
          return
        }
      }
      println("Wrote MoonBit JS link config to \{path}")
    }
    None => println(emitted)
  }
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
async fn emit_typescript_package_from_mbti(
  file_path : String,
  output_dir : String,
  import_rewrite_path : String?,
) -> Unit {
  let import_rewrites = match
    load_typescript_import_rewrite_map(import_rewrite_path) {
    Some(rewrites) => rewrites
    None => return
  }
  let files = @bridge.emit_typescript_package_bundle_from_mbti_path_with_import_rewrites(
    file_path, import_rewrites,
  ) catch {
    @bridge.MbtiTypescriptDeclError::ReadError(msg)
    | @bridge.MbtiTypescriptDeclError::ParseError(msg) => {
      println("Emit error: \{msg}")
      return
    }
  }
  let _ = ensure_dir_tree(output_dir) catch {
    e => {
      println("Write error: \{e}")
      return
    }
  }
  for file in files {
    let output_path = main_join_path(output_dir, file.relative_path)
    let parent_dir = main_dirname(output_path)
    let _ = ensure_dir_tree(parent_dir) catch {
      e => {
        println("Write error: \{e}")
        return
      }
    }
    let _ = @fs.write_file(
      output_path,
      string_to_bytes(file.content),
      create=0o644,
    ) catch {
      e => {
        println("Write error: \{e}")
        return
      }
    }
  }
  println("Wrote TypeScript declaration package to \{output_dir}")
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
async fn emit_typescript_scaffold_from_mbti(
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
      println("Emit error: \{msg}")
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
async fn emit_typescript_facade_scaffold_from_mbti(
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
      println("Emit error: \{msg}")
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
async fn emit_moonbit_js_ffi(
  file_path : String,
  module_spec : String,
  ffi_output_path : String?,
  bridge_output_path : String?,
) -> Unit {
  let bundle = emit_moonbit_js_ffi_texts(file_path, module_spec) catch {
    @bridge.ModuleGraphError::ReadError(msg)
    | @bridge.ModuleGraphError::ParseError(msg)
    | @bridge.ModuleGraphError::ResolveError(msg) => {
      println("Emit error: \{msg}")
      return
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
          return
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
          return
        }
      }
      println("Wrote JS bridge to \{path}")
    }
    None => {
      println("=== bridge.js ===")
      println(bundle.bridge_js)
    }
  }
}

///|
async fn emit_moonbit_bridge(
  file_path : String,
  module_spec : String,
  decl_output_path : String?,
  ffi_output_path : String?,
  bridge_output_path : String?,
) -> Unit {
  let bundle = emit_moonbit_bridge_texts(file_path, module_spec) catch {
    @bridge.ModuleGraphError::ReadError(msg)
    | @bridge.ModuleGraphError::ParseError(msg)
    | @bridge.ModuleGraphError::ResolveError(msg) => {
      println("Emit error: \{msg}")
      return
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
          return
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
          return
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
          return
        }
      }
      println("Wrote JS bridge to \{path}")
    }
    None => {
      println("=== bridge.js ===")
      println(bundle.bridge_js)
    }
  }
}

///|
async fn emit_moonbit_bridge_package(
  file_path : String,
  module_spec : String,
  output_dir : String,
) -> Unit {
  let bundle = emit_moonbit_bridge_package_texts(file_path, module_spec) catch {
    @bridge.ModuleGraphError::ReadError(msg)
    | @bridge.ModuleGraphError::ParseError(msg)
    | @bridge.ModuleGraphError::ResolveError(msg) => {
      println("Emit error: \{msg}")
      return
    }
  }
  if !@fs.exists(output_dir) {
    let _ = ensure_dir_tree(output_dir) catch {
      e => {
        println("Write error: \{e}")
        return
      }
    }
  }
  let output_dir_realpath = @fs.realpath(output_dir) catch { _ => output_dir }
  let bridge_js_output_path = join_output_path(output_dir_realpath, "bridge.js")
  let bridge_mbt = rewrite_bridge_package_module_path(
    bundle.bridge_mbt,
    bridge_js_output_path,
  )
  let files = [
    ("moon.pkg.json", bundle.moon_pkg_json),
    ("bridge.mbti", bundle.bridge_mbti),
    ("bridge.mbt", bridge_mbt),
    ("bridge.js", bundle.bridge_js),
  ]
  for file in files {
    let (name, content) = file
    let path = join_output_path(output_dir, name)
    let _ = @fs.write_file(path, string_to_bytes(content), create=0o644) catch {
      e => {
        println("Write error: \{e}")
        return
      }
    }
  }
  println("Wrote MoonBit bridge package to \{output_dir}")
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
async fn emit_moonbit_scaffold_from_ts(
  file_path : String,
  module_spec : String,
  output_dir : String,
) -> Unit {
  let unsupported_exports = collect_moonbit_ts_scaffold_unsupported_exports(
    file_path,
  ) catch {
    @bridge.ModuleGraphError::ReadError(msg)
    | @bridge.ModuleGraphError::ParseError(msg)
    | @bridge.ModuleGraphError::ResolveError(msg) => {
      println("Emit error: \{msg}")
      return
    }
  }
  emit_moonbit_bridge_package(file_path, module_spec, output_dir)
  if unsupported_exports.length() > 0 {
    let diagnostics_path = join_output_path(
      output_dir, "SCAFFOLD_DIAGNOSTICS.md",
    )
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
        return
      }
    }
    println("Wrote scaffold diagnostics to \{diagnostics_path}")
  }
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

///|
async fn experimental_emit_wasm_gc(
  file_path : String,
  output_path : String,
) -> Unit {
  let content = @fs.read_file(file_path).text() catch {
    e => {
      println("Error reading file: \{e}")
      return
    }
  }
  let parser = @parser.Parser::from_source(content)
  let ts_module = parser.parse_module() catch {
    e => {
      println("Parse error: \{e}")
      return
    }
  }
  let wasm_module = @codegen.experimental_compile_module_gc(ts_module) catch {
    e => {
      println("CodeGen error: \{e}")
      return
    }
  }
  let wasm_bytes = @encode.encode(wasm_module) catch {
    e => {
      println("Encode error: \{e}")
      return
    }
  }
  let _ = @fs.write_file(output_path, wasm_bytes, create=0o644) catch {
    e => {
      println("Write error: \{e}")
      return
    }
  }
  println("Wrote \{wasm_bytes.length()} bytes to \{output_path}")
}

///|
async fn run_ts_file(file_path : String) -> Unit {
  let content = @fs.read_file(file_path).text() catch {
    e => {
      println("Error reading file: \{e}")
      return
    }
  }
  let interp = @runtime.JSInterpreter::new()
  if has_module_syntax(content) {
    let module_cache : Array[(String, @runtime.JSValue)] = []
    let result = eval_module(interp, file_path, module_cache, source=content) catch {
      e => {
        println("Error: \{e}")
        return
      }
    }
    if is_error_value(result) {
      let error_msg = @runtime.js_get_prop(result, "error")
      println("Error: \{error_msg.to_js_string()}")
    }
  } else {
    // Wrap source in function main() for non-module code
    let wrapped = "function main() {\n" + content + "\n}"
    let result = interp.run(wrapped) catch {
      e => {
        println("Error: \{e}")
        return
      }
    }
    println(result.to_js_string())
  }
}

///|
priv struct Test262Meta {
  includes : Array[String]
  flags : Array[String]
  negative : Bool
  negative_phase : String?
  negative_type : String?
}

///|
fn join_path(base : String, name : String) -> String {
  if base.has_suffix("/") {
    base + name
  } else {
    base + "/" + name
  }
}

///|
fn is_fixture_path(path : String) -> Bool {
  path.contains("_FIXTURE.js")
}

///|
fn has_module_syntax(content : String) -> Bool {
  for line in content.split("\n") {
    let trimmed = line.trim().to_string()
    if trimmed.has_prefix("import ") || trimmed.has_prefix("export ") {
      return true
    }
  }
  false
}

///|
fn module_cache_get(
  cache : Array[(String, @runtime.JSValue)],
  path : String,
) -> @runtime.JSValue? {
  for item in cache {
    let (key, value) = item
    if key == path {
      return Some(value)
    }
  }
  None
}

///|
fn module_cache_set(
  cache : Array[(String, @runtime.JSValue)],
  path : String,
  exports : @runtime.JSValue,
) -> Unit {
  if module_cache_get(cache, path) is None {
    cache.push((path, exports))
  }
}

///|
async fn resolve_module_path(
  base_path : String,
  spec : String,
) -> String raise @parser.ParseError {
  let resolved = @parser.resolve_runtime_module_specifier(base_path, spec) catch {
    _ => None
  }
  match resolved {
    Some(path) => path
    None =>
      raise @parser.ParseError::ParseError(
        "Failed to resolve module specifier '\{spec}' from '\{base_path}'",
      )
  }
}

///|
fn is_error_value(value : @runtime.JSValue) -> Bool {
  match value {
    @runtime.JSValue::Object(_) =>
      match @runtime.js_get_prop(value, "error") {
        @runtime.JSValue::String(_) => true
        _ => false
      }
    _ => false
  }
}

///|
fn make_export_getter(
  interp : @runtime.JSInterpreter,
  module_env : @runtime.JSEnv,
  name : String,
  module_exports? : @runtime.JSValue? = None,
) -> @runtime.JSValue {
  let getter = @runtime.js_new_native_function_with_env(
    "__export_get__",
    module_env,
    Some(interp.function_proto),
  )
  let _ = @runtime.js_set_prop(
    getter,
    "__export_name",
    @runtime.js_string(name),
  )
  match module_exports {
    Some(exports) => {
      let _ = @runtime.js_set_prop(getter, "__export_module", exports)
    }
    None => ()
  }
  getter
}

///|
fn define_export_accessors(
  interp : @runtime.JSInterpreter,
  exports : @runtime.JSValue,
  module_env : @runtime.JSEnv,
  specs : Array[@ast.TsExportSpec],
) -> Unit {
  for spec in specs {
    let getter = make_export_getter(interp, module_env, spec.local_name)
    let _ = @runtime.js_define_accessor_prop(
      exports,
      spec.export_name,
      Some(getter),
      None,
      true,
      true,
    )
  }
}

///|
fn define_reexport_accessor(
  interp : @runtime.JSInterpreter,
  exports : @runtime.JSValue,
  module_env : @runtime.JSEnv,
  dep_exports : @runtime.JSValue,
  imported : String,
  export_name : String,
) -> Unit {
  let getter = make_export_getter(
    interp,
    module_env,
    imported,
    module_exports=Some(dep_exports),
  )
  let _ = @runtime.js_define_accessor_prop(
    exports,
    export_name,
    Some(getter),
    None,
    true,
    true,
  )
}

///|
fn export_all_accessors(
  interp : @runtime.JSInterpreter,
  exports : @runtime.JSValue,
  module_env : @runtime.JSEnv,
  dep_exports : @runtime.JSValue,
) -> Unit {
  match dep_exports {
    @runtime.JSValue::Object(map) =>
      for prop in map.props {
        if prop.key != "default" {
          define_reexport_accessor(
            interp,
            exports,
            module_env,
            dep_exports,
            prop.key,
            prop.key,
          )
        }
      }
    @runtime.JSValue::Function(closure) =>
      for prop in closure.props {
        if prop.key != "default" {
          define_reexport_accessor(
            interp,
            exports,
            module_env,
            dep_exports,
            prop.key,
            prop.key,
          )
        }
      }
    _ => ()
  }
}

///|
fn define_import_bindings(
  interp : @runtime.JSInterpreter,
  module_env : @runtime.JSEnv,
  imports : Array[(@ast.TsImportDecl, @runtime.JSValue)],
) -> Unit {
  for item in imports {
    let (decl, dep_exports) = item
    if decl.side_effect_only || decl.type_only {
      continue
    }
    match decl.default_binding {
      Some(name) => {
        let value = interp.get_prop_value(dep_exports, "default")
        module_env.define_const(name, value)
      }
      None => ()
    }
    match decl.namespace_binding {
      Some(name) => module_env.define_const(name, dep_exports)
      None => ()
    }
    for item in decl.named_bindings {
      let (imported, local_name) = item
      let value = interp.get_prop_value(dep_exports, imported)
      module_env.define_const(local_name, value)
    }
  }
}

///|
fn refresh_import_bindings(
  interp : @runtime.JSInterpreter,
  module_env : @runtime.JSEnv,
  imports : Array[(@ast.TsImportDecl, @runtime.JSValue)],
) -> Unit {
  for item in imports {
    let (decl, dep_exports) = item
    if decl.side_effect_only || decl.type_only {
      continue
    }
    match decl.default_binding {
      Some(name) => {
        let value = interp.get_prop_value(dep_exports, "default")
        let _ = module_env.force_set(name, value)
      }
      None => ()
    }
    match decl.namespace_binding {
      Some(name) => {
        let _ = module_env.force_set(name, dep_exports)
      }
      None => ()
    }
    for item in decl.named_bindings {
      let (imported, local_name) = item
      let value = interp.get_prop_value(dep_exports, imported)
      let _ = module_env.force_set(local_name, value)
    }
  }
}

///|
async fn eval_module(
  interp : @runtime.JSInterpreter,
  path : String,
  cache : Array[(String, @runtime.JSValue)],
  source? : String,
) -> @runtime.JSValue raise @parser.ParseError {
  match module_cache_get(cache, path) {
    Some(exports) => return exports
    None => ()
  }
  let exports = @runtime.js_new_object()
  module_cache_set(cache, path, exports)
  let content = match source {
    Some(src) => src
    None =>
      @fs.read_file(path).text() catch {
        e => raise @parser.ParseError::ParseError("Failed to read module: \{e}")
      }
  }
  let module_block = @parser.parse_module_block_from_source(content)
  let module_env = @runtime.js_new_env(Some(interp.global_env))
  let undefined_value = interp.global_env.get("undefined")
  module_env.define_const("this", undefined_value)
  module_env.define_const("__strict__", undefined_value)
  let resolved_imports : Array[(@ast.TsImportDecl, @runtime.JSValue)] = []
  for decl in module_block.imports {
    let dep_path = resolve_module_path(path, decl.module_spec)
    let dep_exports = eval_module(interp, dep_path, cache)
    if is_error_value(dep_exports) {
      return dep_exports
    }
    resolved_imports.push((decl, dep_exports))
  }
  let resolved_reexports : Array[(@ast.TsReExportSpec, @runtime.JSValue)] = []
  for reexport in module_block.reexports {
    let dep_path = resolve_module_path(path, reexport.module_spec)
    let dep_exports = eval_module(interp, dep_path, cache)
    if is_error_value(dep_exports) {
      return dep_exports
    }
    resolved_reexports.push((reexport, dep_exports))
  }
  define_export_accessors(interp, exports, module_env, module_block.exports)
  for item in resolved_reexports {
    let (reexport, dep_exports) = item
    match reexport.kind {
      @ast.TsReExportKind::Named(items) =>
        for spec in items {
          let (imported, export_name) = spec
          define_reexport_accessor(
            interp, exports, module_env, dep_exports, imported, export_name,
          )
        }
      @ast.TsReExportKind::All =>
        export_all_accessors(interp, exports, module_env, dep_exports)
      @ast.TsReExportKind::Namespace(name) => {
        let _ = @runtime.js_set_prop(exports, name, dep_exports)
      }
    }
  }
  define_import_bindings(interp, module_env, resolved_imports)
  interp.hoist_block(module_block.block, module_env)
  refresh_import_bindings(interp, module_env, resolved_imports)
  for stmt in module_block.block.stmts {
    refresh_import_bindings(interp, module_env, resolved_imports)
    match interp.exec_stmt(stmt, module_env) {
      Some(val) => {
        if is_error_value(val) {
          return val
        }
        return val
      }
      None => ()
    }
  }
  interp.drain_microtasks()
  exports
}

///|
fn parse_bracket_list(line : String) -> Array[String] {
  let start = line.find("[")
  let end_ = line.rev_find("]")
  match (start, end_) {
    (Some(s), Some(e)) => if e <= s { return [] }
    _ => return []
  }
  let inner = match (start, end_) {
    (Some(s), Some(e)) => line[s + 1:e].to_string()
    _ => ""
  }
  let items = inner.split(",")
  let result : Array[String] = []
  for item in items {
    let trimmed = item.trim().to_string()
    if trimmed.length() == 0 {
      continue
    }
    let stripped = if trimmed.length() >= 2 &&
      trimmed.has_prefix("\"") &&
      trimmed.has_suffix("\"") {
      trimmed[1:trimmed.length() - 1].to_string()
    } else {
      trimmed
    }
    result.push(stripped)
  }
  result
}

///|
fn parse_test262_meta(content : String) -> Test262Meta {
  let includes : Array[String] = []
  let flags : Array[String] = []
  let mut negative = false
  let mut negative_phase : String? = None
  let mut negative_type : String? = None
  let mut meta_block = ""
  match content.find("/*---") {
    Some(start) => {
      let rest = content[start + 5:].to_string()
      match rest.find("---*/") {
        Some(end_) => meta_block = rest[:end_].to_string()
        None => ()
      }
    }
    None => ()
  }
  let lines : Array[String] = []
  if meta_block.length() > 0 {
    for line in meta_block.split("\n") {
      lines.push(line.to_string())
    }
  } else {
    for line in content.split("\n") {
      let trimmed = line.trim().to_string()
      if trimmed.length() == 0 {
        continue
      }
      if !trimmed.has_prefix("//") {
        break
      }
      let body = trimmed[2:].trim().to_string()
      lines.push(body)
    }
  }
  for raw in lines {
    let line = raw.trim().to_string()
    let body = if line.has_prefix("*") {
      line[1:].trim().to_string()
    } else {
      line
    }
    if body.has_prefix("includes:") {
      for item in parse_bracket_list(body) {
        includes.push(item)
      }
    } else if body.has_prefix("flags:") {
      for item in parse_bracket_list(body) {
        flags.push(item)
      }
    } else if body.has_prefix("negative:") {
      negative = true
    } else if body.has_prefix("phase:") {
      let value = body[6:].trim().to_string()
      if value.length() > 0 {
        negative_phase = Some(value)
      }
    } else if body.has_prefix("type:") {
      let value = body[5:].trim().to_string()
      if value.length() > 0 {
        negative_type = Some(value)
      }
    }
  }
  { includes, flags, negative, negative_phase, negative_type }
}

///|
fn contains(xs : Array[String], value : String) -> Bool {
  for item in xs {
    if item == value {
      return true
    }
  }
  false
}

///|
fn include_prelude(name : String) -> String? {
  match name {
    "assert.js" =>
      Some(
        (
          #|assert._isSameValue = function (a, b) {
          #|  if (a === b) {
          #|    return a !== 0 || 1 / a === 1 / b;
          #|  }
          #|  return a !== a && b !== b;
          #|};
          #|assert._toString = function (value) {
          #|  if (value === null) return "null";
          #|  if (typeof value === "undefined") return "undefined";
          #|  if (typeof value === "bigint") return value.toString() + "n";
          #|  if (typeof value === "symbol") return value.toString();
          #|  try { return String(value); } catch (e) { return Object.prototype.toString.call(value); }
          #|};
          #|function isPrimitive(value) {
          #|  return !value || (typeof value !== "object" && typeof value !== "function");
          #|}
          #|function compareArray(a, b) {
          #|  if (b.length !== a.length) return false;
          #|  for (var i = 0; i < a.length; i++) {
          #|    if (!assert._isSameValue(b[i], a[i])) return false;
          #|  }
          #|  return true;
          #|}
          #|compareArray.format = function (arrayLike) {
          #|  return "[" + Array.prototype.map.call(arrayLike, String).join(", ") + "]";
          #|};
          #|assert.compareArray = function (actual, expected, message) {
          #|  message = message === undefined ? "" : message;
          #|  if (isPrimitive(actual)) {
          #|    assert(false, "Actual argument [" + actual + "] shouldn't be primitive. " + message);
          #|  } else if (isPrimitive(expected)) {
          #|    assert(false, "Expected argument [" + expected + "] shouldn't be primitive. " + message);
          #|  }
          #|  var result = compareArray(actual, expected);
          #|  if (result) return;
          #|  var format = compareArray.format;
          #|  assert(false, "Actual " + format(actual) + " and expected " + format(expected) + " should have the same contents. " + message);
          #|};
        ),
      )
    "sta.js" => Some("")
    "compareArray.js" => Some("")
    "nans.js" =>
      Some(
        (
          #|let NaNs = [0/0];
        ),
      )
    "propertyHelper.js" =>
      Some(
        (
          #|var __isArray = Array.isArray;
          #|var __defineProperty = Object.defineProperty;
          #|var __getOwnPropertyDescriptor = Object.getOwnPropertyDescriptor;
          #|var __getOwnPropertyNames = Object.getOwnPropertyNames;
          #|var __join = Function.prototype.call.bind(Array.prototype.join);
          #|var __push = Function.prototype.call.bind(Array.prototype.push);
          #|var __hasOwnProperty = Function.prototype.call.bind(Object.prototype.hasOwnProperty);
          #|var __propertyIsEnumerable = Function.prototype.call.bind(Object.prototype.propertyIsEnumerable);
          #|var nonIndexNumericPropertyName = Math.pow(2, 32) - 1;
          #|function isSameValue(a, b) {
          #|  if (a === 0 && b === 0) return 1 / a === 1 / b;
          #|  if (a !== a && b !== b) return true;
          #|  return a === b;
          #|}
          #|function isConfigurable(obj, name) {
          #|  try { delete obj[name]; } catch (e) {
          #|    if (!(e instanceof TypeError)) throw new Test262Error("Expected TypeError, got " + e);
          #|  }
          #|  return !__hasOwnProperty(obj, name);
          #|}
          #|function isEnumerable(obj, name) {
          #|  var stringCheck = false;
          #|  if (typeof name === "string") {
          #|    for (var x in obj) { if (x === name) { stringCheck = true; break; } }
          #|  } else { stringCheck = true; }
          #|  return stringCheck && __hasOwnProperty(obj, name) && __propertyIsEnumerable(obj, name);
          #|}
          #|function isWritable(obj, name, verifyProp, value) {
          #|  var unlikelyValue = __isArray(obj) && name === "length" ? nonIndexNumericPropertyName : "unlikelyValue";
          #|  var newValue = value || unlikelyValue;
          #|  var hadValue = __hasOwnProperty(obj, name);
          #|  var oldValue = obj[name];
          #|  var writeSucceeded;
          #|  if (arguments.length < 4 && newValue === oldValue) { newValue = newValue + "2"; }
          #|  try { obj[name] = newValue; } catch (e) {
          #|    if (!(e instanceof TypeError)) throw new Test262Error("Expected TypeError, got " + e);
          #|  }
          #|  writeSucceeded = isSameValue(obj[verifyProp || name], newValue);
          #|  if (writeSucceeded) {
          #|    if (hadValue) { obj[name] = oldValue; } else { delete obj[name]; }
          #|  }
          #|  return writeSucceeded;
          #|}
          #|function verifyProperty(obj, name, desc, options) {
          #|  if (arguments.length < 3) { assert(false, 'verifyProperty should receive at least 3 arguments'); return false; }
          #|  var originalDesc = __getOwnPropertyDescriptor(obj, name);
          #|  var nameStr = String(name);
          #|  if (desc === undefined) {
          #|    assert.sameValue(originalDesc, undefined, "obj['" + nameStr + "'] descriptor should be undefined");
          #|    return true;
          #|  }
          #|  assert(__hasOwnProperty(obj, name), "obj should have an own property " + nameStr);
          #|  assert.notSameValue(desc, null, "The desc argument should be an object or undefined, null");
          #|  assert.sameValue(typeof desc, "object", "The desc argument should be an object or undefined, " + String(desc));
          #|  var names = __getOwnPropertyNames(desc);
          #|  for (var i = 0; i < names.length; i++) {
          #|    assert(names[i] === "value" || names[i] === "writable" || names[i] === "enumerable" || names[i] === "configurable" || names[i] === "get" || names[i] === "set", "Invalid descriptor field: " + names[i]);
          #|  }
          #|  var failures = [];
          #|  if (__hasOwnProperty(desc, 'value')) {
          #|    if (!isSameValue(desc.value, originalDesc.value)) { __push(failures, "obj['" + nameStr + "'] descriptor value should be " + desc.value); }
          #|    if (!isSameValue(desc.value, obj[name])) { __push(failures, "obj['" + nameStr + "'] value should be " + desc.value); }
          #|  }
          #|  if (__hasOwnProperty(desc, 'enumerable') && desc.enumerable !== undefined) {
          #|    if (desc.enumerable !== originalDesc.enumerable || desc.enumerable !== isEnumerable(obj, name)) {
          #|      __push(failures, "obj['" + nameStr + "'] descriptor should " + (desc.enumerable ? '' : 'not ') + "be enumerable");
          #|    }
          #|  }
          #|  if (__hasOwnProperty(desc, 'writable') && desc.writable !== undefined) {
          #|    if (desc.writable !== originalDesc.writable || desc.writable !== isWritable(obj, name)) {
          #|      __push(failures, "obj['" + nameStr + "'] descriptor should " + (desc.writable ? '' : 'not ') + "be writable");
          #|    }
          #|  }
          #|  if (__hasOwnProperty(desc, 'configurable') && desc.configurable !== undefined) {
          #|    if (desc.configurable !== originalDesc.configurable || desc.configurable !== isConfigurable(obj, name)) {
          #|      __push(failures, "obj['" + nameStr + "'] descriptor should " + (desc.configurable ? '' : 'not ') + "be configurable");
          #|    }
          #|  }
          #|  if (failures.length) { assert(false, __join(failures, '; ')); }
          #|  if (options && options.restore) { __defineProperty(obj, name, originalDesc); }
          #|  return true;
          #|}
          #|function verifyCallableProperty(obj, name, functionName, functionLength, desc, options) {
          #|  var value = obj[name];
          #|  assert.sameValue(typeof value, "function", "obj['" + String(name) + "'] descriptor should be a function");
          #|  if (desc === undefined) { desc = { writable: true, enumerable: false, configurable: true, value: value }; }
          #|  else if (!__hasOwnProperty(desc, "value") && !__hasOwnProperty(desc, "get")) { desc.value = value; }
          #|  verifyProperty(obj, name, desc, options);
          #|  if (functionName === undefined) {
          #|    if (typeof name === "symbol") { functionName = "[" + name.description + "]"; } else { functionName = name; }
          #|  }
          #|  verifyProperty(value, "name", { value: functionName, writable: false, enumerable: false, configurable: desc.configurable }, options);
          #|  verifyProperty(value, "length", { value: functionLength, writable: false, enumerable: false, configurable: desc.configurable }, options);
          #|}
          #|function verifyEqualTo(obj, name, value) { if (!isSameValue(obj[name], value)) throw new Test262Error("Expected obj[" + String(name) + "] to equal " + value + ", actually " + obj[name]); }
          #|function verifyWritable(obj, name, verifyProp, value) {
          #|  if (!verifyProp) { assert(__getOwnPropertyDescriptor(obj, name).writable, "Expected obj[" + String(name) + "] to have writable:true."); }
          #|  if (!isWritable(obj, name, verifyProp, value)) throw new Test262Error("Expected obj[" + String(name) + "] to be writable, but was not.");
          #|}
          #|function verifyNotWritable(obj, name, verifyProp, value) {
          #|  if (!verifyProp) { assert(!__getOwnPropertyDescriptor(obj, name).writable, "Expected obj[" + String(name) + "] to have writable:false."); }
          #|  if (isWritable(obj, name, verifyProp)) throw new Test262Error("Expected obj[" + String(name) + "] NOT to be writable, but was.");
          #|}
          #|function verifyEnumerable(obj, name) {
          #|  assert(__getOwnPropertyDescriptor(obj, name).enumerable, "Expected obj[" + String(name) + "] to have enumerable:true.");
          #|  if (!isEnumerable(obj, name)) throw new Test262Error("Expected obj[" + String(name) + "] to be enumerable, but was not.");
          #|}
          #|function verifyNotEnumerable(obj, name) {
          #|  assert(!__getOwnPropertyDescriptor(obj, name).enumerable, "Expected obj[" + String(name) + "] to have enumerable:false.");
          #|  if (isEnumerable(obj, name)) throw new Test262Error("Expected obj[" + String(name) + "] NOT to be enumerable, but was.");
          #|}
          #|function verifyConfigurable(obj, name) {
          #|  assert(__getOwnPropertyDescriptor(obj, name).configurable, "Expected obj[" + String(name) + "] to have configurable:true.");
          #|  if (!isConfigurable(obj, name)) throw new Test262Error("Expected obj[" + String(name) + "] to be configurable, but was not.");
          #|}
          #|function verifyNotConfigurable(obj, name) {
          #|  assert(!__getOwnPropertyDescriptor(obj, name).configurable, "Expected obj[" + String(name) + "] to have configurable:false.");
          #|  if (isConfigurable(obj, name)) throw new Test262Error("Expected obj[" + String(name) + "] NOT to be configurable, but was.");
          #|}
          #|var verifyPrimordialProperty = verifyProperty;
          #|var verifyPrimordialCallableProperty = verifyCallableProperty;
        ),
      )
    "fnGlobalObject.js" =>
      Some(
        (
          #|var __globalObject = Function("return this;")();
          #|function fnGlobalObject() { return __globalObject; }
        ),
      )
    "isConstructor.js" =>
      Some(
        (
          #|function isConstructor(f) {
          #|  if (typeof f !== "function") { throw new Test262Error("isConstructor invoked with a non-function value"); }
          #|  try { Reflect.construct(function(){}, [], f); } catch (e) { return false; }
          #|  return true;
          #|}
        ),
      )
    "deepEqual.js" =>
      Some(
        (
          #|function deepEqual(a, b) {
          #|  if (a === b) return true;
          #|  if (typeof a !== typeof b) return false;
          #|  if (typeof a !== "object" || a === null || b === null) return false;
          #|  var keysA = Object.keys(a), keysB = Object.keys(b);
          #|  if (keysA.length !== keysB.length) return false;
          #|  for (var i = 0; i < keysA.length; i++) {
          #|    if (!deepEqual(a[keysA[i]], b[keysA[i]])) return false;
          #|  }
          #|  return true;
          #|}
          #|assert.deepEqual = function(actual, expected, message) {
          #|  if (!deepEqual(actual, expected)) {
          #|    throw new Test262Error(message || "deepEqual assertion failed");
          #|  }
          #|};
        ),
      )
    "decimalToHexString.js" =>
      Some(
        (
          #|function decimalToHexString(n) {
          #|  var hex = "0123456789ABCDEF";
          #|  n >>>= 0;
          #|  var s = "";
          #|  while (n) { s = hex[n & 0xf] + s; n >>>= 4; }
          #|  while (s.length < 4) { s = "0" + s; }
          #|  return s;
          #|}
          #|function decimalToPercentHexString(n) {
          #|  var hex = "0123456789ABCDEF";
          #|  return "%" + hex[(n >> 4) & 0xf] + hex[n & 0xf];
          #|}
        ),
      )
    "proxyTrapsHelper.js" =>
      Some(
        (
          #|function allowProxyTraps(overrides) {
          #|  function throwTest262Error(msg) { return function () { throw new Test262Error(msg); }; }
          #|  if (!overrides) { overrides = {}; }
          #|  return {
          #|    getPrototypeOf: overrides.getPrototypeOf || throwTest262Error('[[GetPrototypeOf]] trap called'),
          #|    setPrototypeOf: overrides.setPrototypeOf || throwTest262Error('[[SetPrototypeOf]] trap called'),
          #|    isExtensible: overrides.isExtensible || throwTest262Error('[[IsExtensible]] trap called'),
          #|    preventExtensions: overrides.preventExtensions || throwTest262Error('[[PreventExtensions]] trap called'),
          #|    getOwnPropertyDescriptor: overrides.getOwnPropertyDescriptor || throwTest262Error('[[GetOwnProperty]] trap called'),
          #|    has: overrides.has || throwTest262Error('[[HasProperty]] trap called'),
          #|    get: overrides.get || throwTest262Error('[[Get]] trap called'),
          #|    set: overrides.set || throwTest262Error('[[Set]] trap called'),
          #|    deleteProperty: overrides.deleteProperty || throwTest262Error('[[Delete]] trap called'),
          #|    defineProperty: overrides.defineProperty || throwTest262Error('[[DefineOwnProperty]] trap called'),
          #|    enumerate: throwTest262Error('[[Enumerate]] trap called: this trap has been removed'),
          #|    ownKeys: overrides.ownKeys || throwTest262Error('[[OwnPropertyKeys]] trap called'),
          #|    apply: overrides.apply || throwTest262Error('[[Call]] trap called'),
          #|    construct: overrides.construct || throwTest262Error('[[Construct]] trap called')
          #|  };
          #|}
        ),
      )
    "asyncHelpers.js" =>
      Some(
        (
          #|function asyncTest(testFunc) {
          #|  if (!Object.prototype.hasOwnProperty.call(globalThis, "$DONE")) {
          #|    throw new Test262Error("asyncTest called without async flag");
          #|  }
          #|  if (typeof testFunc !== "function") {
          #|    $DONE(new Test262Error("asyncTest called with non-function argument"));
          #|    return;
          #|  }
          #|  try {
          #|    testFunc().then(function () { $DONE(); }, function (error) { $DONE(error); });
          #|  } catch (syncError) { $DONE(syncError); }
          #|}
          #|assert.throwsAsync = function (expectedErrorConstructor, func, message) {
          #|  return new Promise(function (resolve) {
          #|    var fail = function (detail) {
          #|      if (message === undefined) { throw new Test262Error(detail); }
          #|      throw new Test262Error(message + " " + detail);
          #|    };
          #|    if (typeof expectedErrorConstructor !== "function") {
          #|      fail("assert.throwsAsync called with an argument that is not an error constructor");
          #|    }
          #|    if (typeof func !== "function") {
          #|      fail("assert.throwsAsync called with an argument that is not a function");
          #|    }
          #|    var expectedName = expectedErrorConstructor.name;
          #|    var expectation = "Expected a " + expectedName + " to be thrown asynchronously";
          #|    var res;
          #|    try { res = func(); } catch (thrown) { fail(expectation + " but the function threw synchronously"); }
          #|    if (res === null || typeof res !== "object" || typeof res.then !== "function") {
          #|      fail(expectation + " but result was not a thenable");
          #|    }
          #|    var onResFulfilled, onResRejected;
          #|    var resSettlementP = new Promise(function (onFulfilled, onRejected) {
          #|      onResFulfilled = onFulfilled;
          #|      onResRejected = onRejected;
          #|    });
          #|    try { res.then(onResFulfilled, onResRejected); } catch (thrown) {
          #|      fail(expectation + " but .then threw synchronously");
          #|    }
          #|    resolve(resSettlementP.then(
          #|      function () { fail(expectation + " but no exception was thrown at all"); },
          #|      function (thrown) {
          #|        var actualName;
          #|        if (thrown === null || typeof thrown !== "object") {
          #|          fail(expectation + " but thrown value was not an object");
          #|        } else if (thrown.constructor !== expectedErrorConstructor) {
          #|          actualName = thrown.constructor.name;
          #|          if (expectedName === actualName) {
          #|            fail(expectation + " but got a different error constructor with the same name");
          #|          }
          #|          fail(expectation + " but got a " + actualName);
          #|        }
          #|      }
          #|    ));
          #|  });
          #|};
        ),
      )
    "promiseHelper.js" =>
      Some(
        (
          #|function checkSequence(arr, message) {
          #|  arr.forEach(function(e, i) {
          #|    if (e !== (i+1)) {
          #|      throw new Test262Error((message ? message : "Steps in unexpected sequence:") +
          #|             " '" + arr.join(',') + "'");
          #|    }
          #|  });
          #|  return true;
          #|}
          #|function checkSettledPromises(settleds, expected, message) {
          #|  var prefix = message ? message + ": " : "";
          #|  assert.sameValue(Array.isArray(settleds), true, prefix + "Settled values is an array");
          #|  assert.sameValue(settleds.length, expected.length,
          #|    prefix + "The settled values has a different length than expected");
          #|  settleds.forEach(function(settled, i) {
          #|    assert.sameValue(Object.prototype.hasOwnProperty.call(settled, "status"), true,
          #|      prefix + "The settled value has a property status");
          #|    assert.sameValue(settled.status, expected[i].status, prefix + "status for item " + i);
          #|    if (settled.status === "fulfilled") {
          #|      assert.sameValue(Object.prototype.hasOwnProperty.call(settled, "value"), true,
          #|        prefix + "The fulfilled promise has a property named value");
          #|      assert.sameValue(Object.prototype.hasOwnProperty.call(settled, "reason"), false,
          #|        prefix + "The fulfilled promise has no property named reason");
          #|      assert.sameValue(settled.value, expected[i].value, prefix + "value for item " + i);
          #|    } else {
          #|      assert.sameValue(settled.status, "rejected",
          #|        prefix + "Valid statuses are only fulfilled or rejected");
          #|      assert.sameValue(Object.prototype.hasOwnProperty.call(settled, "value"), false,
          #|        prefix + "The rejected promise has no property named value");
          #|      assert.sameValue(Object.prototype.hasOwnProperty.call(settled, "reason"), true,
          #|        prefix + "The rejected promise has a property named reason");
          #|      assert.sameValue(settled.reason, expected[i].reason, prefix + "Reason value for item " + i);
          #|    }
          #|  });
          #|}
        ),
      )
    "compareIterator.js" =>
      Some(
        (
          #|assert.compareIterator = function(iter, validators, message) {
          #|  message = message || "";
          #|  var i, result;
          #|  for (i = 0; i < validators.length; i++) {
          #|    result = iter.next();
          #|    assert(!result.done, "Expected " + i + " values(s). Instead iterator only produced " + (i - 1) + " value(s). " + message);
          #|    validators[i](result.value);
          #|  }
          #|  result = iter.next();
          #|  assert(result.done, "Expected only " + i + " values(s). Instead iterator produced more. " + message);
          #|  assert.sameValue(result.value, undefined, "Expected value of `undefined` when iterator completes. " + message);
          #|};
        ),
      )
    "testTypedArray.js" =>
      Some(
        (
          #|var floatArrayConstructors = [Float64Array, Float32Array];
          #|var nonClampedIntArrayConstructors = [Int32Array, Int16Array, Int8Array, Uint32Array, Uint16Array, Uint8Array];
          #|var intArrayConstructors = nonClampedIntArrayConstructors.concat([Uint8ClampedArray]);
          #|var typedArrayConstructors = floatArrayConstructors.concat(intArrayConstructors);
          #|var TypedArray = Object.getPrototypeOf(Int8Array);
          #|function testWithTypedArrayConstructors(f, selected) {
          #|  var constructors = selected || typedArrayConstructors;
          #|  for (var i = 0; i < constructors.length; ++i) {
          #|    var constructor = constructors[i];
          #|    try {
          #|      f(constructor);
          #|    } catch (e) {
          #|      e.message += " (Testing with " + constructor.name + ".)";
          #|      throw e;
          #|    }
          #|  }
          #|}
          #|var nonAtomicsFriendlyTypedArrayConstructors = floatArrayConstructors.concat([Uint8ClampedArray]);
          #|function testWithNonAtomicsFriendlyTypedArrayConstructors(f) {
          #|  testWithTypedArrayConstructors(f, nonAtomicsFriendlyTypedArrayConstructors);
          #|}
          #|function testWithAtomicsFriendlyTypedArrayConstructors(f) {
          #|  testWithTypedArrayConstructors(f, [Int32Array, Int16Array, Int8Array, Uint32Array, Uint16Array, Uint8Array]);
          #|}
          #|function testTypedArrayConversions(byteConversionValues, fn) {
          #|  var values = byteConversionValues.values;
          #|  var expected = byteConversionValues.expected;
          #|  testWithTypedArrayConstructors(function(TA) {
          #|    var name = TA.name.replace("Array", "");
          #|    var exp = expected[name];
          #|    if (!exp) return;
          #|    for (var i = 0; i < values.length; ++i) {
          #|      fn(TA, values[i], exp[i], i);
          #|    }
          #|  });
          #|}
        ),
      )
    "detachArrayBuffer.js" =>
      Some(
        (
          #|function $DETACHBUFFER(buffer) {
          #|  if (!$262 || typeof $262.detachArrayBuffer !== "function") {
          #|    throw new Test262Error("No method available to detach an ArrayBuffer");
          #|  }
          #|  $262.detachArrayBuffer(buffer);
          #|}
        ),
      )
    "testBigIntTypedArray.js" =>
      Some(
        (
          #|function testWithBigIntTypedArrayConstructors(f, selected) {
          #|  var constructors = selected || [BigInt64Array, BigUint64Array];
          #|  for (var i = 0; i < constructors.length; ++i) {
          #|    var constructor = constructors[i];
          #|    try {
          #|      f(constructor);
          #|    } catch (e) {
          #|      e.message += " (Testing with " + constructor.name + ".)";
          #|      throw e;
          #|    }
          #|  }
          #|}
        ),
      )
    _ => None
  }
}

///|
fn build_includes(includes : Array[String]) -> (String, Array[String]) {
  let mut prelude = ""
  let missing : Array[String] = []
  for inc in includes {
    match include_prelude(inc) {
      Some(code) => if code.length() > 0 { prelude = prelude + code + "\n" }
      None => missing.push(inc)
    }
  }
  (prelude, missing)
}

///|
fn should_skip_test(meta : Test262Meta, content : String) -> String? {
  // async tests are now supported - no longer skipping
  let is_module = contains(meta.flags, "module")
  for line in content.split("\n") {
    let trimmed = line.trim().to_string()
    if !is_module &&
      (trimmed.has_prefix("import ") || trimmed.has_prefix("export ")) {
      return Some("module syntax")
    }
    if trimmed.has_prefix("with ") || trimmed.has_prefix("with(") {
      return Some("with statement not supported")
    }
  }
  None
}

///|
fn normalize_negative_phase(phase : String?) -> String? {
  match phase {
    Some(value) => if value == "early" { Some("parse") } else { Some(value) }
    None => None
  }
}

///|
fn negative_phase_matches(
  expected_phase : String?,
  actual_phase : String,
) -> Bool {
  match normalize_negative_phase(expected_phase) {
    Some(value) => value == actual_phase
    None => true
  }
}

///|
fn get_error_name(value : @runtime.JSValue) -> String? {
  match value {
    @runtime.JSValue::Object(_) =>
      match @runtime.js_get_prop(value, "name") {
        @runtime.JSValue::String(name) => Some(name)
        _ => None
      }
    @runtime.JSValue::Function(_) =>
      match @runtime.js_get_prop(value, "name") {
        @runtime.JSValue::String(name) => Some(name)
        _ => None
      }
    _ => None
  }
}

///|
fn option_or_empty(value : String?) -> String {
  match value {
    Some(v) => v
    None => ""
  }
}

///|
fn negative_type_matches(
  expected_type : String?,
  actual_phase : String,
  error_value : @runtime.JSValue?,
) -> Bool {
  match expected_type {
    None => true
    Some(kind) =>
      if actual_phase == "parse" {
        kind == "SyntaxError"
      } else {
        match error_value {
          Some(value) =>
            match get_error_name(value) {
              Some(name) => name == kind
              None => false
            }
          None => false
        }
      }
  }
}

///|
async fn collect_test_files(path : String, out : Array[String]) -> Unit {
  let kind = @fs.kind(path, follow_symlink=false) catch {
    _ => @fs.FileKind::Unknown
  }
  match kind {
    @fs.FileKind::Directory => {
      let entries = @fs.readdir(
        path,
        include_hidden=false,
        include_special=false,
        sort=true,
      ) catch {
        _ => []
      }
      for name in entries {
        if name == "harness" {
          continue
        }
        let child = join_path(path, name)
        collect_test_files(child, out)
      }
    }
    @fs.FileKind::Regular => if path.has_suffix(".js") { out.push(path) }
    _ => ()
  }
}

///|
fn wrap_test_source(source : String) -> String {
  "function main() {\n" + source + "\n}"
}

///|
fn load_test_list(content : String) -> Array[String] {
  let result : Array[String] = []
  for line in content.split("\n") {
    let trimmed = line.trim().to_string()
    if trimmed.length() == 0 {
      continue
    }
    if trimmed.has_prefix("#") {
      continue
    }
    result.push(trimmed)
  }
  result
}

///|
fn has_glob_meta(pattern : String) -> Bool {
  for c in pattern {
    if c == '*' || c == '?' {
      return true
    }
  }
  false
}

///|
fn split_patterns(patterns : Array[String]) -> (Array[String], Array[String]) {
  let includes : Array[String] = []
  let excludes : Array[String] = []
  for pat in patterns {
    if pat.has_prefix("!") {
      let sub = pat[1:].to_string()
      if sub.length() > 0 {
        excludes.push(sub)
      }
    } else {
      includes.push(pat)
    }
  }
  (includes, excludes)
}

///|
fn match_segment(pat : String, seg : String) -> Bool {
  let pchars : Array[Char] = []
  let schars : Array[Char] = []
  for c in pat {
    pchars.push(c)
  }
  for c in seg {
    schars.push(c)
  }
  fn rec(
    pchars : Array[Char],
    schars : Array[Char],
    pi : Int,
    si : Int,
  ) -> Bool {
    if pi >= pchars.length() {
      return si >= schars.length()
    }
    let pc = pchars[pi]
    if pc == '*' {
      let mut k = si
      while k <= schars.length() {
        if rec(pchars, schars, pi + 1, k) {
          return true
        }
        k += 1
      }
      return false
    }
    if pc == '?' {
      if si < schars.length() {
        return rec(pchars, schars, pi + 1, si + 1)
      }
      return false
    }
    if si < schars.length() && pc == schars[si] {
      return rec(pchars, schars, pi + 1, si + 1)
    }
    false
  }

  rec(pchars, schars, 0, 0)
}

///|
fn split_path_parts(path : String) -> Array[String] {
  let parts : Array[String] = []
  for part in path.split("/") {
    let s = part.to_string()
    parts.push(s)
  }
  parts
}

///|
fn glob_match(pattern : String, path : String) -> Bool {
  let pparts = split_path_parts(pattern)
  let sparts = split_path_parts(path)
  fn rec(
    pparts : Array[String],
    sparts : Array[String],
    pi : Int,
    si : Int,
  ) -> Bool {
    if pi >= pparts.length() {
      return si >= sparts.length()
    }
    let part = pparts[pi]
    if part == "**" {
      if pi + 1 >= pparts.length() {
        return true
      }
      let mut k = si
      while k <= sparts.length() {
        if rec(pparts, sparts, pi + 1, k) {
          return true
        }
        k += 1
      }
      return false
    }
    if si >= sparts.length() {
      return false
    }
    if match_segment(part, sparts[si]) {
      return rec(pparts, sparts, pi + 1, si + 1)
    }
    false
  }

  rec(pparts, sparts, 0, 0)
}

///|
fn matches_any(patterns : Array[String], path : String) -> Bool {
  for pat in patterns {
    if has_glob_meta(pat) {
      if glob_match(pat, path) {
        return true
      }
    } else if pat == path {
      return true
    }
  }
  false
}

///|
async fn run_test262(test_path : String) -> Unit {
  let files : Array[String] = []
  let kind = @fs.kind(test_path, follow_symlink=false) catch {
    _ => @fs.FileKind::Unknown
  }
  match kind {
    @fs.FileKind::Directory => collect_test_files(test_path, files)
    @fs.FileKind::Regular =>
      if test_path.has_suffix(".txt") {
        let list_content = @fs.read_file(test_path).text() catch {
          e => {
            println("Error reading test list: \{e}")
            return
          }
        }
        let patterns = load_test_list(list_content)
        let mut use_glob = false
        for pat in patterns {
          if pat.has_prefix("!") || has_glob_meta(pat) {
            use_glob = true
            break
          }
        }
        if use_glob {
          let (includes, excludes) = split_patterns(patterns)
          let candidates : Array[String] = []
          let base = "test262/test"
          collect_test_files(base, candidates)
          for path in candidates {
            if matches_any(includes, path) && !matches_any(excludes, path) {
              files.push(path)
            }
          }
        } else {
          for path in patterns {
            files.push(path)
          }
        }
      } else {
        files.push(test_path)
      }
    _ => {
      println("Error: test path not found: \{test_path}")
      return
    }
  }
  let total_files = files.length()
  let progress_interval = 200
  let per_test_step_limit = 10_000_000
  let mut passed = 0
  let mut failed = 0
  let mut skipped = 0
  for i, path in files {
    let _ = @fs.write_file(
      "test262.current.txt",
      @utf8.encode(path),
      create=0o644,
    ) catch {
      _ => ()
    }
    if is_fixture_path(path) {
      skipped += 1
      println("SKIP: \{path} (fixture)")
      continue
    }
    let content = @fs.read_file(path).text() catch {
      e => {
        failed += 1
        println("ERROR: \{path} - \{e}")
        continue
      }
    }
    let meta = parse_test262_meta(content)
    let (include_src, missing_includes) = build_includes(meta.includes)
    if missing_includes.length() > 0 {
      skipped += 1
      let missing_list = missing_includes.join(", ")
      println("SKIP: \{path} (missing includes: \{missing_list})")
      continue
    }
    match should_skip_test(meta, content) {
      Some(reason) => {
        skipped += 1
        println("SKIP: \{path} (\{reason})")
        continue
      }
      None => ()
    }
    let interp = @runtime.JSInterpreter::new()
    interp.set_step_limit(per_test_step_limit)
    let undefined_value = interp.global_env.get("undefined")
    let is_module = contains(meta.flags, "module") || has_module_syntax(content)
    let mut result = undefined_value
    let mut has_error = false
    let mut error_phase = ""
    let mut error_message = ""
    if is_module {
      if include_src.length() > 0 {
        let wrapped_inc = wrap_test_source(include_src)
        let _ = interp.run(wrapped_inc) catch {
          e => {
            has_error = true
            error_phase = "parse"
            error_message = "\{e}"
            undefined_value
          }
        }
      }
      if !has_error {
        let module_cache : Array[(String, @runtime.JSValue)] = []
        result = eval_module(interp, path, module_cache, source=content) catch {
          e => {
            has_error = true
            error_phase = "parse"
            error_message = "\{e}"
            undefined_value
          }
        }
      }
    } else {
      let mut source = include_src + content
      if contains(meta.flags, "onlyStrict") {
        source = "\"use strict\";\n" + source
      }
      // For negative parse tests, first try to parse the source directly
      // to catch SyntaxErrors that wouldn't be caught inside a function wrapper
      if meta.negative && option_or_empty(meta.negative_phase) == "parse" {
        let parser = @parser.Parser::from_source(source)
        try {
          let _ = parser.parse_module()
        } catch {
          e => {
            has_error = true
            error_phase = "parse"
            error_message = "\{e}"
          }
        }
      }
      if !has_error {
        let wrapped = wrap_test_source(source)
        result = interp.run(wrapped) catch {
          e => {
            has_error = true
            error_phase = "parse"
            error_message = "\{e}"
            undefined_value
          }
        }
      }
    }
    if has_error {
      if meta.negative {
        let phase_ok = negative_phase_matches(meta.negative_phase, error_phase)
        let type_ok = negative_type_matches(
          meta.negative_type,
          error_phase,
          None,
        )
        if phase_ok && type_ok {
          passed += 1
        } else {
          failed += 1
          let expected_phase = option_or_empty(meta.negative_phase)
          let expected_type = option_or_empty(meta.negative_type)
          println(
            "FAIL: \{path} - negative mismatch (phase=\{expected_phase}, type=\{expected_type}, got=\{error_phase})",
          )
        }
      } else {
        failed += 1
        println("ERROR: \{path} - \{error_message}")
      }
      continue
    }
    let mut runtime_error : @runtime.JSValue? = None
    if is_error_value(result) {
      runtime_error = Some(result)
    }
    // For async tests, also check last_error from $DONE(error)
    match runtime_error {
      Some(_) => ()
      None =>
        match interp.get_last_error() {
          Some(err) => runtime_error = Some(err)
          None => ()
        }
    }
    if meta.negative {
      match runtime_error {
        Some(err_value) => {
          let phase_ok = negative_phase_matches(meta.negative_phase, "runtime")
          let type_ok = negative_type_matches(
            meta.negative_type,
            "runtime",
            Some(err_value),
          )
          if phase_ok && type_ok {
            passed += 1
          } else {
            failed += 1
            let expected_phase = option_or_empty(meta.negative_phase)
            let expected_type = option_or_empty(meta.negative_type)
            let actual_name = option_or_empty(get_error_name(err_value))
            println(
              "FAIL: \{path} - negative mismatch (phase=\{expected_phase}, type=\{expected_type}, got=runtime/\{actual_name})",
            )
          }
        }
        None => {
          failed += 1
          println("FAIL: \{path} - negative test did not throw")
        }
      }
    } else {
      match runtime_error {
        Some(err_value) =>
          match @runtime.js_get_prop(err_value, "error") {
            @runtime.JSValue::String(msg) => {
              failed += 1
              println("FAIL: \{path} - \{msg}")
            }
            _ => {
              failed += 1
              println("FAIL: \{path} - runtime error")
            }
          }
        None => passed += 1
      }
    }
    let _ = @fs.write_file(
      "test262.last_done.txt",
      @utf8.encode(path),
      create=0o644,
    ) catch {
      _ => ()
    }
    let done = i + 1
    if done % progress_interval == 0 || done == total_files {
      println(
        "test262 progress: \{done}/\{total_files} (passed=\{passed}, failed=\{failed}, skipped=\{skipped})",
      )
    }
  }
  println(
    "test262 results: total=\{total_files}, passed=\{passed}, failed=\{failed}, skipped=\{skipped}",
  )
}
