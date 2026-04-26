///|
struct ProjectBenchmarkFailure {
  phase : String
  path : String
  detail : String
} derive(Debug)

///|
struct ProjectBenchmarkCorpus {
  name : String
  root : String
  description : String
  optional : Bool
} derive(Debug)

///|
struct ProjectBenchmarkCorpusRun {
  corpus : ProjectBenchmarkCorpus
  result : ProjectBenchmarkResult
} derive(Debug)

///|
struct ProjectBenchmarkResult {
  root : String
  limit : Int
  mut truncated : Bool
  mut total_files : Int
  mut module_source_files : Int
  mut declaration_files : Int
  mut module_parse_ok : Int
  mut module_parse_failed : Int
  mut decl_parse_ok : Int
  mut decl_parse_failed : Int
  mut decl_emit_ok : Int
  mut decl_emit_failed : Int
  mut decl_js_ffi_ok : Int
  mut decl_js_ffi_failed : Int
  started_at_ms : UInt64
  mut finished_at_ms : UInt64
  failures : Array[ProjectBenchmarkFailure]
} derive(Debug)

///|
fn benchmark_project_default_limit() -> Int {
  200
}

///|
fn known_project_benchmark_corpora() -> Array[ProjectBenchmarkCorpus] {
  [
    {
      name: "fixture-types",
      root: "fixtures/resolver/project/types",
      description: "repo-local declaration and resolver fixtures",
      optional: false,
    },
    {
      name: "fixture-jsx-tsx",
      root: "fixtures/corpus/jsx-tsx",
      description: "repo-local JSX/TSX real-world snippets",
      optional: false,
    },
    {
      name: "mbts-js",
      root: "/Users/mz/ghq/github.com/mizchi/mbts/js",
      description: "optional local mbts JS/TS sources",
      optional: true,
    },
    {
      name: "hono-jsx",
      root: "/Users/mz/ghq/github.com/honojs/hono/src/jsx",
      description: "optional local Hono JSX corpus",
      optional: true,
    },
    {
      name: "hono-jsx-benchmarks",
      root: "/Users/mz/ghq/github.com/honojs/hono/benchmarks/jsx/src",
      description: "optional local Hono JSX benchmark pages",
      optional: true,
    },
    {
      name: "ink-components",
      root: "/Users/mz/ghq/github.com/vadimdemedes/ink/src/components",
      description: "optional local Ink TSX component corpus",
      optional: true,
    },
    {
      name: "vscode-copilot-tsx",
      root: "/tmp/vscode-benchmark/extensions/copilot/test/simulation/workbench/components",
      description: "optional local VSCode Copilot TSX corpus",
      optional: true,
    },
    {
      name: "vscode-copilot-workbench",
      root: "/tmp/vscode-benchmark/extensions/copilot/test/simulation/workbench",
      description: "optional local VSCode Copilot workbench corpus",
      optional: true,
    },
    {
      name: "vscode-copilot-tools",
      root: "/tmp/vscode-benchmark/extensions/copilot/src/extension/tools",
      description: "optional local VSCode Copilot tools corpus",
      optional: true,
    },
    {
      name: "vscode-chat-browser",
      root: "/tmp/vscode-benchmark/src/vs/workbench/contrib/chat/browser",
      description: "optional local VSCode chat browser corpus",
      optional: true,
    },
    {
      name: "vscode-base-browser-ui",
      root: "/tmp/vscode-benchmark/src/vs/base/browser/ui",
      description: "optional local VSCode base browser UI corpus",
      optional: true,
    },
  ]
}

///|
async fn project_benchmark_root_exists(root : String) -> Bool {
  let kind = @fs.kind(root, follow_symlink=false) catch { _ => return false }
  match kind {
    @fs.FileKind::Unknown => false
    _ => true
  }
}

///|
fn project_benchmark_is_declaration_file(path : String) -> Bool {
  path.has_suffix(".d.ts") ||
  path.has_suffix(".d.mts") ||
  path.has_suffix(".d.cts")
}

///|
fn project_benchmark_is_ts_family_file(path : String) -> Bool {
  project_benchmark_is_declaration_file(path) ||
  path.has_suffix(".ts") ||
  path.has_suffix(".tsx") ||
  path.has_suffix(".mts") ||
  path.has_suffix(".cts")
}

///|
fn project_benchmark_should_skip_dir(name : String) -> Bool {
  name == ".git" ||
  name == ".moon" ||
  name == ".mooncakes" ||
  name == "_build" ||
  name == "target" ||
  name == "node_modules" ||
  name == "dist" ||
  name == "out"
}

///|
async fn collect_project_benchmark_files(
  path : String,
  out : Array[String],
  limit : Int,
) -> Unit {
  if limit > 0 && out.length() >= limit {
    return
  }
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
        if project_benchmark_should_skip_dir(name) {
          continue
        }
        let child = join_path(path, name)
        collect_project_benchmark_files(child, out, limit)
        if limit > 0 && out.length() >= limit {
          return
        }
      }
    }
    @fs.FileKind::Regular =>
      if project_benchmark_is_ts_family_file(path) {
        out.push(path)
      }
    _ => ()
  }
}

///|
fn benchmark_result_new(
  root : String,
  limit : Int,
  started_at_ms : UInt64,
) -> ProjectBenchmarkResult {
  {
    root,
    limit,
    truncated: false,
    total_files: 0,
    module_source_files: 0,
    declaration_files: 0,
    module_parse_ok: 0,
    module_parse_failed: 0,
    decl_parse_ok: 0,
    decl_parse_failed: 0,
    decl_emit_ok: 0,
    decl_emit_failed: 0,
    decl_js_ffi_ok: 0,
    decl_js_ffi_failed: 0,
    started_at_ms,
    finished_at_ms: started_at_ms,
    failures: [],
  }
}

///|
fn benchmark_push_failure(
  result : ProjectBenchmarkResult,
  phase : String,
  path : String,
  detail : String,
) -> Unit {
  result.failures.push({ phase, path, detail })
}

///|
fn benchmark_source_line_col(source : String, pos : Int) -> (Int, Int) {
  let limit = if pos < 0 {
    0
  } else if pos > source.length() {
    source.length()
  } else {
    pos
  }
  let mut line = 1
  let mut col = 1
  for i in 0..<limit {
    let ch = source[i].to_int().unsafe_to_char()
    if ch == '\n' {
      line += 1
      col = 1
    } else {
      col += 1
    }
  }
  (line, col)
}

///|
fn benchmark_format_parse_detail(
  source : String,
  message : String,
  pos : Int,
) -> String {
  let (line, col) = benchmark_source_line_col(source, pos)
  "\{message} @\{line}:\{col}"
}

///|
async fn benchmark_read_file(path : String) -> String? {
  Some(@fs.read_file(path).text() catch { _ => return None })
}

///|
fn benchmark_ffi_module_spec(path : String, root : String) -> String {
  let relative = if root != "" && path.has_prefix(root) {
    let offset = root.length()
    if path.length() > offset && path[offset].unsafe_to_char() == '/' {
      path[offset + 1:].to_string()
    } else {
      path[offset:].to_string()
    }
  } else {
    path
  }
  let mut spec = "./" + relative
  if spec.has_suffix(".d.ts") {
    spec = spec.replace(old=".d.ts", new=".js")
  } else if spec.has_suffix(".d.mts") {
    spec = spec.replace(old=".d.mts", new=".mjs")
  } else if spec.has_suffix(".d.cts") {
    spec = spec.replace(old=".d.cts", new=".cjs")
  }
  spec
}

///|
async fn benchmark_declaration_file(
  path : String,
  root : String,
  result : ProjectBenchmarkResult,
) -> Unit {
  result.declaration_files += 1
  let source = benchmark_read_file(path)
  match source {
    Some(source) => {
      let parser = @parser.Parser::from_source(source)
      let parsed = parser.parse_module() catch {
        @parser.ParseError(msg) => {
          result.decl_parse_failed += 1
          let error_pos = if parser.pos < parser.tokens.length() {
            parser.tokens[parser.pos].pos
          } else {
            source.length()
          }
          benchmark_push_failure(
            result,
            "parse_module",
            path,
            benchmark_format_parse_detail(source, msg, error_pos),
          )
          return
        }
      }
      let _ = parsed
      result.decl_parse_ok += 1
      let _ = @bridge.emit_moonbit_decl_from_entry_path(path) catch {
        @bridge.ModuleGraphError::ReadError(msg)
        | @bridge.ModuleGraphError::ParseError(msg)
        | @bridge.ModuleGraphError::ResolveError(msg) => {
          result.decl_emit_failed += 1
          benchmark_push_failure(result, "emit_moonbit_decl", path, msg)
          return
        }
      }
      result.decl_emit_ok += 1
      let module_spec = benchmark_ffi_module_spec(path, root)
      let _ = @bridge.emit_moonbit_js_ffi_bundle_from_entry_path(
        path, module_spec,
      ) catch {
        @bridge.ModuleGraphError::ReadError(msg)
        | @bridge.ModuleGraphError::ParseError(msg)
        | @bridge.ModuleGraphError::ResolveError(msg) => {
          result.decl_js_ffi_failed += 1
          benchmark_push_failure(result, "emit_moonbit_js_ffi", path, msg)
          return
        }
      }
      result.decl_js_ffi_ok += 1
    }
    None => {
      result.decl_parse_failed += 1
      benchmark_push_failure(result, "read_file", path, "Failed to read file")
    }
  }
}

///|
async fn benchmark_module_source_file(
  path : String,
  result : ProjectBenchmarkResult,
) -> Unit {
  result.module_source_files += 1
  let source = benchmark_read_file(path)
  match source {
    Some(source) => {
      let allow_jsx = path.has_suffix(".tsx")
      let parser = @parser.Parser::from_source_with_jsx(source, allow_jsx)
      let _ = parser.parse_module_block() catch {
        @parser.ParseError(msg) => {
          result.module_parse_failed += 1
          let error_pos = if parser.pos < parser.tokens.length() {
            parser.tokens[parser.pos].pos
          } else {
            source.length()
          }
          benchmark_push_failure(
            result,
            "parse_module_block",
            path,
            benchmark_format_parse_detail(source, msg, error_pos),
          )
          return
        }
      }
      result.module_parse_ok += 1
    }
    None => {
      result.module_parse_failed += 1
      benchmark_push_failure(result, "read_file", path, "Failed to read file")
    }
  }
}

///|
async fn benchmark_ts_project(
  root : String,
  limit? : Int = benchmark_project_default_limit(),
) -> ProjectBenchmarkResult {
  let started_at_ms = @env.now()
  let result = benchmark_result_new(root, limit, started_at_ms)
  let files : Array[String] = []
  collect_project_benchmark_files(root, files, limit)
  result.total_files = files.length()
  result.truncated = limit > 0 && files.length() >= limit
  if files.length() == 0 {
    let kind = @fs.kind(root, follow_symlink=false) catch {
      _ => @fs.FileKind::Unknown
    }
    if kind is @fs.FileKind::Unknown {
      benchmark_push_failure(
        result, "scan", root, "Path not found or not readable",
      )
    }
    result.finished_at_ms = @env.now()
    return result
  }
  for path in files {
    if project_benchmark_is_declaration_file(path) {
      benchmark_declaration_file(path, root, result)
    } else {
      benchmark_module_source_file(path, result)
    }
  }
  result.finished_at_ms = @env.now()
  result
}

///|
async fn benchmark_project_corpora(
  corpora : Array[ProjectBenchmarkCorpus],
  limit? : Int = benchmark_project_default_limit(),
) -> Array[ProjectBenchmarkCorpusRun] {
  let runs : Array[ProjectBenchmarkCorpusRun] = []
  for corpus in corpora {
    if corpus.optional && !project_benchmark_root_exists(corpus.root) {
      continue
    }
    let result = benchmark_ts_project(corpus.root, limit~)
    runs.push({ corpus, result })
  }
  runs
}

///|
async fn benchmark_known_corpora(
  limit? : Int = benchmark_project_default_limit(),
) -> Array[ProjectBenchmarkCorpusRun] {
  benchmark_project_corpora(known_project_benchmark_corpora(), limit~)
}

///|
fn render_project_benchmark_report(result : ProjectBenchmarkResult) -> String {
  let sb = StringBuilder::new()
  let elapsed_ms = result.finished_at_ms - result.started_at_ms
  sb.write_string("=== Project Benchmark ===\n")
  sb.write_string("Root: ")
  sb.write_string(result.root)
  sb.write_string("\n")
  sb.write_string("Files scanned: ")
  sb.write_string(result.total_files.to_string())
  if result.limit > 0 {
    sb.write_string(" (limit ")
    sb.write_string(result.limit.to_string())
    if result.truncated {
      sb.write_string(", truncated")
    }
    sb.write_string(")")
  }
  sb.write_string("\n")
  sb.write_string("Module source files: ")
  sb.write_string(result.module_source_files.to_string())
  sb.write_string("\n")
  sb.write_string("Declaration files: ")
  sb.write_string(result.declaration_files.to_string())
  sb.write_string("\n")
  sb.write_string("parse_module_block (.ts): ")
  sb.write_string(result.module_parse_ok.to_string())
  sb.write_string(" ok / ")
  sb.write_string(result.module_parse_failed.to_string())
  sb.write_string(" failed\n")
  sb.write_string("parse_module (.d.ts): ")
  sb.write_string(result.decl_parse_ok.to_string())
  sb.write_string(" ok / ")
  sb.write_string(result.decl_parse_failed.to_string())
  sb.write_string(" failed\n")
  sb.write_string("emit_moonbit_decl (.d.ts): ")
  sb.write_string(result.decl_emit_ok.to_string())
  sb.write_string(" ok / ")
  sb.write_string(result.decl_emit_failed.to_string())
  sb.write_string(" failed\n")
  sb.write_string("emit_moonbit_js_ffi (.d.ts): ")
  sb.write_string(result.decl_js_ffi_ok.to_string())
  sb.write_string(" ok / ")
  sb.write_string(result.decl_js_ffi_failed.to_string())
  sb.write_string(" failed\n")
  sb.write_string("Elapsed: ")
  sb.write_string(elapsed_ms.to_string())
  sb.write_string(" ms\n")
  if result.failures.length() == 0 {
    sb.write_string("Failures: none\n")
    return sb.to_string()
  }
  sb.write_string("Failures:\n")
  let mut shown = 0
  for failure in result.failures {
    if shown >= 10 {
      break
    }
    sb.write_string("- [")
    sb.write_string(failure.phase)
    sb.write_string("] ")
    sb.write_string(failure.path)
    sb.write_string(": ")
    sb.write_string(failure.detail)
    sb.write_string("\n")
    shown += 1
  }
  if result.failures.length() > shown {
    sb.write_string("- ... ")
    sb.write_string((result.failures.length() - shown).to_string())
    sb.write_string(" more failures\n")
  }
  sb.to_string()
}

///|
fn render_project_benchmark_corpora_report(
  runs : Array[ProjectBenchmarkCorpusRun],
) -> String {
  let sb = StringBuilder::new()
  sb.write_string("=== Benchmark Corpora ===\n")
  if runs.length() == 0 {
    sb.write_string("Corpora: none\n")
    return sb.to_string()
  }
  let mut total_module_ok = 0
  let mut total_module_failed = 0
  let mut total_decl_ok = 0
  let mut total_decl_failed = 0
  let mut total_emit_ok = 0
  let mut total_emit_failed = 0
  let mut total_ffi_ok = 0
  let mut total_ffi_failed = 0
  let mut total_elapsed_ms : UInt64 = 0
  sb.write_string("Corpora:\n")
  for run in runs {
    let elapsed_ms = run.result.finished_at_ms - run.result.started_at_ms
    total_module_ok += run.result.module_parse_ok
    total_module_failed += run.result.module_parse_failed
    total_decl_ok += run.result.decl_parse_ok
    total_decl_failed += run.result.decl_parse_failed
    total_emit_ok += run.result.decl_emit_ok
    total_emit_failed += run.result.decl_emit_failed
    total_ffi_ok += run.result.decl_js_ffi_ok
    total_ffi_failed += run.result.decl_js_ffi_failed
    total_elapsed_ms += elapsed_ms
    sb.write_string("- ")
    sb.write_string(run.corpus.name)
    sb.write_string(": ")
    sb.write_string(run.corpus.root)
    sb.write_string("\n")
    sb.write_string("  parse_module_block (.ts): ")
    sb.write_string(run.result.module_parse_ok.to_string())
    sb.write_string(" ok / ")
    sb.write_string(run.result.module_parse_failed.to_string())
    sb.write_string(" failed\n")
    sb.write_string("  parse_module (.d.ts): ")
    sb.write_string(run.result.decl_parse_ok.to_string())
    sb.write_string(" ok / ")
    sb.write_string(run.result.decl_parse_failed.to_string())
    sb.write_string(" failed\n")
    sb.write_string("  emit_moonbit_decl (.d.ts): ")
    sb.write_string(run.result.decl_emit_ok.to_string())
    sb.write_string(" ok / ")
    sb.write_string(run.result.decl_emit_failed.to_string())
    sb.write_string(" failed\n")
    sb.write_string("  emit_moonbit_js_ffi (.d.ts): ")
    sb.write_string(run.result.decl_js_ffi_ok.to_string())
    sb.write_string(" ok / ")
    sb.write_string(run.result.decl_js_ffi_failed.to_string())
    sb.write_string(" failed\n")
    sb.write_string("  elapsed: ")
    sb.write_string(elapsed_ms.to_string())
    sb.write_string(" ms\n")
  }
  sb.write_string("Summary:\n")
  sb.write_string("- parse_module_block (.ts): ")
  sb.write_string(total_module_ok.to_string())
  sb.write_string(" ok / ")
  sb.write_string(total_module_failed.to_string())
  sb.write_string(" failed\n")
  sb.write_string("- parse_module (.d.ts): ")
  sb.write_string(total_decl_ok.to_string())
  sb.write_string(" ok / ")
  sb.write_string(total_decl_failed.to_string())
  sb.write_string(" failed\n")
  sb.write_string("- emit_moonbit_decl (.d.ts): ")
  sb.write_string(total_emit_ok.to_string())
  sb.write_string(" ok / ")
  sb.write_string(total_emit_failed.to_string())
  sb.write_string(" failed\n")
  sb.write_string("- emit_moonbit_js_ffi (.d.ts): ")
  sb.write_string(total_ffi_ok.to_string())
  sb.write_string(" ok / ")
  sb.write_string(total_ffi_failed.to_string())
  sb.write_string(" failed\n")
  sb.write_string("- elapsed: ")
  sb.write_string(total_elapsed_ms.to_string())
  sb.write_string(" ms\n")
  sb.to_string()
}

///|
fn parse_project_benchmark_limit(raw : String) -> Int? {
  let parsed = @string.parse_int(raw) catch { _ => return None }
  if parsed < 0 {
    None
  } else {
    Some(parsed)
  }
}

///|
async fn run_project_benchmark(root : String, limit : Int) -> Unit {
  let result = benchmark_ts_project(root, limit~)
  println(render_project_benchmark_report(result))
}

///|
async fn run_benchmark_corpora(limit : Int) -> Unit {
  let runs = benchmark_known_corpora(limit~)
  println(render_project_benchmark_corpora_report(runs))
}
