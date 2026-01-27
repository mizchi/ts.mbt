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
  if contains(meta.flags, "module") {
    return Some("module flag")
  }
  if contains(meta.flags, "async") {
    return Some("async flag")
  }
  for line in content.split("\n") {
    let trimmed = line.trim().to_string()
    if trimmed.has_prefix("import ") || trimmed.has_prefix("export ") {
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
  let per_test_step_limit = 200_000
  let mut passed = 0
  let mut failed = 0
  let mut skipped = 0

  for i, path in files {
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
    let mut source = include_src + content
    if contains(meta.flags, "onlyStrict") {
      source = "\"use strict\";\n" + source
    }
    let wrapped = wrap_test_source(source)
    let result = interp.run(wrapped) catch {
      e => {
        failed += 1
        println("ERROR: \{path} - \{e}")
        continue
      }
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
