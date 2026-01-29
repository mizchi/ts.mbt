///|
async fn main_async() -> Unit {
  let args = @env.args()
  if args.length() < 2 {
    print_usage()
    return
  }

  let command = args[1]
  match command {
    "run" => {
      if args.length() < 3 {
        println("Error: no file specified")
        return
      }
      let file_path = args[2]
      run_ts_file(file_path)
    }
    "test262" => {
      if args.length() < 3 {
        println("Error: no test directory or file specified")
        return
      }
      let test_path = args[2]
      run_test262(test_path)
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
  println("Usage: wasm5-ts <command> [args...]")
  println("")
  println("Commands:")
  println("  run <file>         Run a TypeScript/JavaScript file")
  println("  test262 <path>     Run test262 tests (file or directory)")
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
  let result = interp.run(content) catch {
    e => {
      println("Error: \{e}")
      return
    }
  }
  println(result.to_js_string())
}

///|
priv struct Test262Meta {
  includes : Array[String]
  flags : Array[String]
  negative : Bool
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
fn normalize_path(path : String) -> String {
  let is_abs = path.has_prefix("/")
  let parts : Array[String] = []
  for part_view in path.split("/") {
    let part = part_view.to_string()
    if part == "" {
      if is_abs && parts.length() == 0 {
        parts.push("")
      }
      continue
    }
    if part == "." {
      continue
    }
    if part == ".." {
      if parts.length() > 0 {
        let last = parts[parts.length() - 1]
        if last != "" && last != ".." {
          let _ = parts.pop()
          continue
        }
      }
      parts.push("..")
    } else {
      parts.push(part)
    }
  }
  if parts.length() == 0 {
    return if is_abs { "/" } else { "." }
  }
  if parts.length() == 1 && parts[0] == "" {
    return "/"
  }
  let mut result = parts[0]
  if result == "" {
    result = "/"
  }
  for i in 1..<parts.length() {
    if result == "/" {
      result = result + parts[i]
    } else {
      result = result + "/" + parts[i]
    }
  }
  result
}

///|
fn dirname(path : String) -> String {
  match path.rev_find("/") {
    Some(idx) => try { path[:idx].to_string() } catch { _ => "." }
    None => "."
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
fn resolve_module_path(base_path : String, spec : String) -> String {
  let candidate =
    if spec.has_prefix("./") || spec.has_prefix("../") {
      join_path(dirname(base_path), spec)
    } else {
      spec
    }
  let normalized = normalize_path(candidate)
  if normalized.has_suffix(".js") || normalized.has_suffix(".mjs") {
    return normalized
  }
  normalized + ".js"
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
  let getter =
    @runtime.js_new_native_function_with_env(
      "__export_get__",
      module_env,
      Some(interp.function_proto),
    )
  let _ = @runtime.js_set_prop(getter, "__export_name", @runtime.js_string(name))
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
    let _ =
      @runtime.js_define_accessor_prop(
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
  let getter =
    make_export_getter(
      interp,
      module_env,
      imported,
      module_exports=Some(dep_exports),
    )
  let _ =
    @runtime.js_define_accessor_prop(
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
            interp,
            exports,
            module_env,
            dep_exports,
            imported,
            export_name,
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
    (Some(s), Some(e)) =>
      if e <= s {
        return []
      }
    _ => return []
  }
  let inner = try {
    match (start, end_) {
      (Some(s), Some(e)) => line[s + 1:e].to_string()
      _ => ""
    }
  } catch {
    _ => ""
  }
  let items = inner.split(",")
  let result : Array[String] = []
  for item in items {
    let trimmed = item.trim().to_string()
    if trimmed.length() == 0 {
      continue
    }
    let stripped =
      if trimmed.length() >= 2 && trimmed.has_prefix("\"") && trimmed.has_suffix("\"") {
        try { trimmed[1:trimmed.length() - 1].to_string() } catch { _ => trimmed }
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
  let mut meta_block = ""
  match content.find("/*---") {
    Some(start) => {
      let rest = try { content[start + 5:].to_string() } catch { _ => "" }
      match rest.find("---*/") {
        Some(end_) => {
          meta_block = try { rest[:end_].to_string() } catch { _ => "" }
        }
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
      if not(trimmed.has_prefix("//")) {
        break
      }
      let body = try { trimmed[2:].trim().to_string() } catch { _ => "" }
      lines.push(body)
    }
  }
  for raw in lines {
    let line = raw.trim().to_string()
    let body =
      if line.has_prefix("*") {
        try { line[1:].trim().to_string() } catch { _ => line }
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
    }
  }
  { includes, flags, negative }
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
    "assert.js" => Some("")
    "sta.js" => Some("")
    "compareArray.js" => Some("")
    "nans.js" =>
      Some(
        (
          #|let NaNs = [0/0];
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
      Some(code) => {
        if code.length() > 0 {
          prelude = prelude + code + "\n"
        }
      }
      None => missing.push(inc)
    }
  }
  (prelude, missing)
}

///|
fn should_skip_test(meta : Test262Meta, content : String) -> String? {
  if meta.negative {
    return Some("negative test")
  }
  if contains(meta.flags, "async") {
    return Some("async flag")
  }
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
async fn collect_test_files(path : String, out : Array[String]) -> Unit {
  let kind = @fs.kind(path, follow_symlink=false) catch { _ => @fs.FileKind::Unknown }
  match kind {
    @fs.FileKind::Directory => {
      let entries = @fs.readdir(
        path,
        include_hidden=false,
        include_special=false,
        sort=true,
      ) catch { _ => [] }
      for name in entries {
        if name == "harness" {
          continue
        }
        let child = join_path(path, name)
        collect_test_files(child, out)
      }
    }
    @fs.FileKind::Regular =>
      if path.has_suffix(".js") {
        out.push(path)
      }
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
      let sub = try { pat[1:].to_string() } catch { _ => "" }
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
  fn rec(pchars : Array[Char], schars : Array[Char], pi : Int, si : Int) -> Bool {
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
  fn rec(pparts : Array[String], sparts : Array[String], pi : Int, si : Int) -> Bool {
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
  let kind = @fs.kind(test_path, follow_symlink=false) catch { _ => @fs.FileKind::Unknown }
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
            if matches_any(includes, path) && not(matches_any(excludes, path)) {
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
    let _ =
      @fs.write_file(
        "test262.current.txt",
        @utf8.encode(path),
        create=0o644,
      ) catch { _ => () }
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
      println(
        "SKIP: \{path} (missing includes: \{missing_list})",
      )
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
    if is_module {
      if include_src.length() > 0 {
        let wrapped_inc = wrap_test_source(include_src)
        let _ = interp.run(wrapped_inc) catch {
          e => {
            failed += 1
            println("ERROR: \{path} - \{e}")
            has_error = true
            undefined_value
          }
        }
      }
      if not(has_error) {
        let module_cache : Array[(String, @runtime.JSValue)] = []
        result = eval_module(interp, path, module_cache, source=content) catch {
          e => {
            failed += 1
            println("ERROR: \{path} - \{e}")
            has_error = true
            undefined_value
          }
        }
      }
    } else {
      let mut source = include_src + content
      if contains(meta.flags, "onlyStrict") {
        source = "\"use strict\";\n" + source
      }
      let wrapped = wrap_test_source(source)
      result = interp.run(wrapped) catch {
        e => {
          failed += 1
          println("ERROR: \{path} - \{e}")
          has_error = true
          undefined_value
        }
      }
    }
    if has_error {
      continue
    }

    match result {
      Object(_) => {
        let err = @runtime.js_get_prop(result, "error")
        match err {
          @runtime.JSValue::String(msg) => {
            failed += 1
            println("FAIL: \{path} - \{msg}")
          }
          _ => passed += 1
        }
      }
      _ => passed += 1
    }
    let _ =
      @fs.write_file(
        "test262.last_done.txt",
        @utf8.encode(path),
        create=0o644,
      ) catch { _ => () }
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
