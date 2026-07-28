///|
fn wbtest_join_path(base : String, child : String) -> String {
  if base.has_suffix("/") {
    base + child
  } else {
    base + "/" + child
  }
}

///|
fn wbtest_basename(path : String) -> String {
  match path.rev_find("/") {
    Some(idx) => path[idx + 1:path.length()].to_owned()
    None => path
  }
}

///|
test "types package hint rewrites scoped package names" {
  assert_eq(types_package_hint("@scope/no-types"), "@types/scope__no-types")
  assert_eq(types_package_hint("no-types"), "@types/no-types")
}

///|
fn wbtest_tmp_neverthrow_like_root(name : String) -> String {
  "/tmp/ts_mbt_neverthrow_like_" + name
}

///|
fn wbtest_tmp_project_benchmark_root(name : String) -> String {
  "/tmp/ts_mbt_project_benchmark_" + name
}

///|
async test "mtsc JavaScript module exposes only the Vite graph checker ABI" {
  let manifest = @fs.read_file("src/mtsc/moon.pkg").text() catch {
    e => fail("failed to read mtsc package manifest: \{e}")
  }
  assert_true(manifest.contains("\"check_module_graph:checkModuleGraph\""))
  assert_false(manifest.contains("check_source:checkSource"))
  assert_false(manifest.contains("check_module_sources:checkModuleSources"))
}

///|
async test "write_text_file preserves UTF-8 text in generated outputs" {
  let root = wbtest_tmp_project_benchmark_root("write_text_file_utf8")
  let _ = try? @fs.rmdir(root, recursive=true)
  ensure_dir_tree(root)
  let path = wbtest_join_path(root, "unicode.txt")
  let expected = "MoonBit — 日本語 😀\n"
  assert_true(write_text_file(path, expected))
  let actual = @fs.read_file(path).text() catch {
    e => fail("generated text was not valid UTF-8: \{e}")
  }
  assert_eq(actual, expected)
}

///|
async fn wbtest_collect_relative_files(
  root : String,
  relative_dir : String,
  out : Array[String],
) -> Unit {
  let dir = if relative_dir == "" {
    root
  } else {
    wbtest_join_path(root, relative_dir)
  }
  let entries = @fs.readdir(
    dir,
    include_hidden=false,
    include_special=false,
    sort=true,
  ) catch {
    _ => return
  }
  for name in entries {
    let relative_path = if relative_dir == "" {
      name
    } else {
      relative_dir + "/" + name
    }
    let path = wbtest_join_path(root, relative_path)
    let kind = @fs.kind(path, follow_symlink=false) catch {
      _ => @fs.FileKind::Unknown
    }
    match kind {
      @fs.FileKind::Directory =>
        wbtest_collect_relative_files(root, relative_path, out)
      @fs.FileKind::Regular => out.push(relative_path)
      _ => ()
    }
  }
}

///|
async fn wbtest_relative_file_snapshot(root : String) -> String {
  let files : Array[String] = []
  wbtest_collect_relative_files(root, "", files)
  files.sort()
  files.join("\n")
}

///|
fn wbtest_find_file_content(
  files : Array[(String, String)],
  name : String,
) -> String {
  for file in files {
    let (file_name, content) = file
    if file_name == name {
      return content
    }
  }
  abort("expected generated file: \{name}")
}

///|
async fn wbtest_prepare_tmp_neverthrow_like_fixture(
  root : String,
) -> String raise Error {
  let _ = try? @fs.rmdir(root, recursive=true)
  let dirs = [
    root,
    wbtest_join_path(root, "dist"),
    wbtest_join_path(root, "node_modules"),
    wbtest_join_path(root, "node_modules/.pnpm"),
    wbtest_join_path(root, "node_modules/.pnpm/neverthrow-like@1.0.0"),
    wbtest_join_path(
      root, "node_modules/.pnpm/neverthrow-like@1.0.0/node_modules",
    ),
    wbtest_join_path(
      root, "node_modules/.pnpm/neverthrow-like@1.0.0/node_modules/neverthrow-like",
    ),
    wbtest_join_path(
      root, "node_modules/.pnpm/neverthrow-like@1.0.0/node_modules/neverthrow-like/dist",
    ),
  ]
  for dir in dirs {
    if !@fs.exists(dir) {
      @fs.mkdir(dir, permission=0o755)
    }
  }
  let pkg_root = wbtest_join_path(
    root, "node_modules/.pnpm/neverthrow-like@1.0.0/node_modules/neverthrow-like",
  )
  let package_json =
    #|{
    #|  "name": "neverthrow-like",
    #|  "version": "1.0.0",
    #|  "main": "dist/index.cjs.js",
    #|  "module": "dist/index.es.js",
    #|  "types": "dist/index.d.ts"
    #|}
  let dts_source =
    #|export interface Result<T, E> {
    #|  readonly value: T;
    #|  isOk(): boolean;
    #|}
    #|
    #|export interface ResultAsync<T, E> {
    #|  readonly promiseValue: T;
    #|  isOk(): boolean;
    #|}
  let entry_source =
    #|import { ResultAsync, type Result } from "neverthrow-like";
    #|
    #|export interface User {
    #|  id: string;
    #|  name: string;
    #|}
    #|
    #|export declare function parseUser(input: string): Result<User, Error>;
    #|export declare function fetchUser(id: string): ResultAsync<User, Error>;
  @fs.write_file(
    wbtest_join_path(pkg_root, "package.json"),
    package_json,
    create=0o644,
  )
  @fs.write_file(
    wbtest_join_path(pkg_root, "dist/index.d.ts"),
    dts_source,
    create=0o644,
  )
  @fs.write_file(
    wbtest_join_path(pkg_root, "dist/index.es.js"),
    "export const __neverthrowLike = true;\n",
    create=0o644,
  )
  @fs.write_file(
    wbtest_join_path(pkg_root, "dist/index.cjs.js"),
    "exports.__neverthrowLike = true;\n",
    create=0o644,
  )
  @fs.symlink(
    wbtest_join_path(root, "node_modules/neverthrow-like"),
    target=".pnpm/neverthrow-like@1.0.0/node_modules/neverthrow-like",
  )
  let entry_path = wbtest_join_path(root, "dist/neverthrow-like-entry.d.ts")
  @fs.write_file(entry_path, entry_source, create=0o644)
  entry_path
}

///|
test "parse_unified_tsmbt_options accepts input out and direction flags" {
  let args = [
    "tsmbt", "--input", "mizchi/foo", "--out", "dist", "--direction", "mbt-to-ts",
    "--import-rewrites", "rewrites.json", "--diagnostics", "dist/diagnostics.md",
    "--strict", "--no-facade",
  ]
  match parse_unified_tsmbt_options(args, 1) {
    (Some(options), None) => {
      @test.assert_eq(options.input, Some("mizchi/foo"))
      @test.assert_eq(options.out, Some("dist"))
      assert_true(options.direction is TsmbtDirection::MbtToTs)
      @test.assert_eq(options.import_rewrite_path, Some("rewrites.json"))
      @test.assert_eq(options.diagnostics_path, Some("dist/diagnostics.md"))
      assert_true(options.strict)
      assert_false(options.facade)
    }
    (_, Some(message)) => fail(message)
    _ => fail("expected options")
  }
}

///|
test "parse_unified_tsmbt_options accepts positional generate args and equals flags" {
  let args = [
    "tsmbt", "generate", "neverthrow", "dist/generated", "--direction=ts", "--module-spec=/runtime/neverthrow.js",
    "--import-rewrite=rewrites.json", "--diagnostics=dist/diagnostics.md",
  ]
  match parse_unified_tsmbt_options(args, 2) {
    (Some(options), None) => {
      @test.assert_eq(options.input, Some("neverthrow"))
      @test.assert_eq(options.out, Some("dist/generated"))
      assert_true(options.direction is TsmbtDirection::TsToMbt)
      @test.assert_eq(options.module_spec, Some("/runtime/neverthrow.js"))
      @test.assert_eq(options.import_rewrite_path, Some("rewrites.json"))
      @test.assert_eq(options.diagnostics_path, Some("dist/diagnostics.md"))
      assert_false(options.strict)
      assert_true(options.facade)
    }
    (_, Some(message)) => fail(message)
    _ => fail("expected options")
  }
}

///|
async test "run_ts_to_mbt_unified_cli reports invalid unified args" {
  let mut help_called = false
  assert_false(
    run_ts_to_mbt_unified_cli(["ts2mbt", "--input", "missing"], 1, print_help=fn() {
      help_called = true
    }),
  )
  assert_true(help_called)
}

///|
async test "run_mbt_to_ts_unified_cli rejects --direction mismatch" {
  let mut help_called = false
  assert_false(
    run_mbt_to_ts_unified_cli(
      ["mbt2ts", "--input", "foo", "--out", "dist", "--direction", "ts-to-mbt"],
      1,
      print_help=fn() { help_called = true },
    ),
  )
  // Help is not invoked for the direction conflict message, only for usage errors.
  assert_false(help_called)
}

///|
async test "resolve_unified_mbt_input_path finds package name in generated mbti files" {
  match resolve_unified_mbt_input_path("examples/counter") {
    Some(path) =>
      @test.assert_eq(
        path, "examples/moonbit-to-typescript/counter/pkg.generated.mbti",
      )
    None => fail("expected examples/counter pkg.generated.mbti")
  }
}

///|
async test "resolve_unified_mbt_input_path_from_roots finds ghq-style package names" {
  let root = wbtest_tmp_project_benchmark_root("unified_fake_ghq")
  let github_root = wbtest_join_path(root, "github.com")
  let pkg_dir = wbtest_join_path(github_root, "mizchi/ripple/src")
  let _ = try? @fs.rmdir(root, recursive=true)
  @fs.mkdir(root, permission=0o755)
  @fs.mkdir(wbtest_join_path(root, "github.com"), permission=0o755)
  @fs.mkdir(wbtest_join_path(github_root, "mizchi"), permission=0o755)
  @fs.mkdir(wbtest_join_path(github_root, "mizchi/ripple"), permission=0o755)
  @fs.mkdir(pkg_dir, permission=0o755)
  let mbti_path = wbtest_join_path(pkg_dir, "pkg.generated.mbti")
  let mbti_source =
    #|// Generated using `moon info`, DON'T EDIT IT
    #|package "mizchi/ripple"
    #|
    #|// Values
    #|pub fn version() -> String
  @fs.write_file(mbti_path, mbti_source, create=0o644)
  match
    resolve_unified_mbt_input_path_from_roots("mizchi/ripple", [
      ".", github_root,
    ]) {
    Some(path) => assert_eq(path, mbti_path)
    None => fail("expected mizchi/ripple to resolve from fake ghq root")
  }
}

///|
async test "resolve_unified_mbt_input_path_from_roots finds package names from ghq moon.mod metadata" {
  let root = wbtest_tmp_project_benchmark_root("unified_fake_ghq_module_name")
  let github_root = wbtest_join_path(root, "github.com")
  let repo_dir = wbtest_join_path(github_root, "mizchi/moonbit_jsonschema")
  let pkg_dir = wbtest_join_path(repo_dir, "src")
  let _ = try? @fs.rmdir(root, recursive=true)
  ensure_dir_tree(pkg_dir)
  @fs.write_file(
    wbtest_join_path(repo_dir, "moon.mod.json"),
    (
      #|{
      #|  "name": "mizchi/jsonschema",
      #|  "version": "0.1.0",
      #|  "source": "src",
      #|  "preferred-target": "js"
      #|}
    ),
    create=0o644,
  )
  let mbti_path = wbtest_join_path(pkg_dir, "pkg.generated.mbti")
  let mbti_source =
    #|// Generated using `moon info`, DON'T EDIT IT
    #|package "mizchi/jsonschema"
    #|
    #|// Values
    #|pub fn emit_schema() -> String
  @fs.write_file(mbti_path, mbti_source, create=0o644)
  match
    resolve_unified_mbt_input_path_from_roots("mizchi/jsonschema", [
      github_root, ".",
    ]) {
    Some(path) => assert_eq(path, mbti_path)
    None => fail("expected mizchi/jsonschema to resolve from moon.mod name")
  }
}

///|
async test "infer_unified_tsmbt_direction detects package names and TypeScript entries" {
  match infer_unified_tsmbt_direction("examples/counter") {
    Some(TsmbtDirection::MbtToTs) => ()
    _ => fail("expected examples/counter to infer mbt-to-ts")
  }
  match
    infer_unified_tsmbt_direction(
      "fixtures/resolver/project/types/neverthrow-like-entry.d.ts",
    ) {
    Some(TsmbtDirection::TsToMbt) => ()
    _ => fail("expected .d.ts entry to infer ts-to-mbt")
  }
}

///|
async test "resolve_unified_mbt_input_path_from_roots prefers ghq package checkout over local fixture" {
  let root = wbtest_tmp_project_benchmark_root("resolve_mbt_ghq_precedence")
  let _ = try? @fs.rmdir(root, recursive=true)
  let local_root = wbtest_join_path(root, "local")
  let ghq_root = wbtest_join_path(root, "github.com")
  let fixture_path = wbtest_join_path(
    local_root, "fixtures/mbti_typescript/realworld_jsonschema.pkg.generated.mbti",
  )
  let checkout_pkg = wbtest_join_path(
    ghq_root, "mizchi/moonbit_jsonschema/src/pkg.generated.mbti",
  )
  assert_true(
    write_text_file(
      fixture_path, "// Generated using `moon info`, DON'T EDIT IT\npackage \"mizchi/jsonschema\"\n",
    ),
  )
  assert_true(
    write_text_file(
      wbtest_join_path(ghq_root, "mizchi/moonbit_jsonschema/moon.mod.json"),
      "{\"name\":\"mizchi/jsonschema\",\"source\":\"src\"}",
    ),
  )
  assert_true(
    write_text_file(
      checkout_pkg, "// Generated using `moon info`, DON'T EDIT IT\npackage \"mizchi/jsonschema\"\n",
    ),
  )
  match
    resolve_unified_mbt_input_path_from_roots("mizchi/jsonschema", [
      local_root, ghq_root,
    ]) {
    Some(path) => assert_eq(path, checkout_pkg)
    None => fail("expected mizchi/jsonschema to resolve to ghq checkout")
  }
}

///|
test "rewrite_moonbit_js_runtime_text patches identity externs" {
  let source = "const cast = %identity;\nconst cast2 = %identity;\n//# sourceMappingURL=glue.js.map\n"
  let actual = rewrite_moonbit_js_runtime_text(
    source, "glue.js.map", "index.js.map",
  )
  @test.assert_eq(
    actual, "const cast = (x) => x;\nconst cast2 = (x) => x;\n//# sourceMappingURL=index.js.map\n",
  )
}

///|
test "rewrite_moonbit_js_runtime_text injects require shim for esm output" {
  let source = "const text = require(\"node:fs\").readFileSync(path, \"utf8\");\n//# sourceMappingURL=glue.js.map\n"
  let actual = rewrite_moonbit_js_runtime_text(
    source, "glue.js.map", "index.js.map",
  )
  assert_true(
    actual.has_prefix(
      "import { createRequire as __tsmbtCreateRequire } from \"node:module\";\nconst require = __tsmbtCreateRequire(import.meta.url);\n",
    ),
  )
  assert_true(actual.contains("require(\"node:fs\")"))
  assert_true(actual.contains("//# sourceMappingURL=index.js.map"))
}

///|
async test "emit_unified_tsmbt_scaffold emits MoonBit to TypeScript scaffold from package name" {
  let root = wbtest_tmp_project_benchmark_root("unified_mbt_to_ts")
  let _ = try? @fs.rmdir(root, recursive=true)
  assert_true(
    emit_unified_tsmbt_scaffold(
      "examples/counter",
      root,
      direction=TsmbtDirection::MbtToTs,
      module_spec=None,
      import_rewrite_path=None,
      facade=true,
    ),
  )
  let root_decl = @fs.read_file(wbtest_join_path(root, "index.d.ts")).text() catch {
    e => fail("failed to read unified index.d.ts: \{e}")
  }
  let root_js = @fs.read_file(wbtest_join_path(root, "index.js")).text() catch {
    e => fail("failed to read unified index.js: \{e}")
  }
  let package_json = @fs.read_file(wbtest_join_path(root, "package.json")).text() catch {
    e => fail("failed to read unified package.json: \{e}")
  }
  @test.assert_eq(
    wbtest_relative_file_snapshot(root),
    [
      "index.js", "index.d.ts", "index.js.map", "package.json", "child/index.js",
      "child/index.d.ts", "child/grand/index.js", "child/grand/index.d.ts", "AUTOLINK_DIAGNOSTICS.md",
    ].join("\n"),
  )
  assert_true(root_decl.contains("import type * as child from \"./child\";"))
  assert_true(root_js.contains("function __tsmbt_public_return(value)"))
  assert_true(root_js.contains("export function create(...args)"))
  assert_true(package_json.contains("\"name\": \"@examples/counter\""))
  assert_true(package_json.contains("\"type\": \"module\""))
  assert_true(
    package_json.contains(
      "\"./child/grand\": { \"types\": \"./child/grand/index.d.ts\", \"import\": \"./child/grand/index.js\" }",
    ),
  )
}

///|
async test "emit_unified_tsmbt_scaffold emits TypeScript to MoonBit scaffold" {
  let root = wbtest_tmp_project_benchmark_root("unified_ts_to_mbt")
  let _ = try? @fs.rmdir(root, recursive=true)
  assert_true(
    emit_unified_tsmbt_scaffold(
      "fixtures/resolver/project/types/neverthrow-like-entry.d.ts",
      root,
      direction=TsmbtDirection::TsToMbt,
      module_spec=Some("/runtime/neverthrow-like.js"),
      import_rewrite_path=None,
      facade=true,
    ),
  )
  let moon_pkg = @fs.read_file(wbtest_join_path(root, "moon.pkg")).text() catch {
    e => fail("failed to read unified TS moon.pkg: \{e}")
  }
  let bridge_mbt = @fs.read_file(wbtest_join_path(root, "bridge.mbt")).text() catch {
    e => fail("failed to read unified TS bridge.mbt: \{e}")
  }
  let diagnostics = @fs.read_file(
    wbtest_join_path(root, "SCAFFOLD_DIAGNOSTICS.md"),
  ).text() catch {
    e => fail("failed to read unified TS diagnostics: \{e}")
  }
  @test.assert_eq(
    wbtest_relative_file_snapshot(root),
    [
      "moon.pkg", "bridge.js", "bridge.mbt", "bridge.mbti", "package.json", "SCAFFOLD_DIAGNOSTICS.md",
    ].join("\n"),
  )
  @test.assert_eq(moon_pkg, "")
  // The neverthrow-like fixture has directly-callable runtime exports,
  // so the bridge.mbt extern lines pull from `/runtime/neverthrow-like.js`
  // rather than going through a `__ts_mbt_*` helper indirection.
  assert_true(bridge_mbt.contains("#module(\"/runtime/neverthrow-like.js\")"))
  assert_true(diagnostics.contains("No unsupported exports were detected."))
}

///|
async test "emit_unified_tsmbt_scaffold writes requested TypeScript diagnostics" {
  let root = wbtest_tmp_project_benchmark_root("unified_ts_to_mbt_diagnostics")
  let diagnostics_path = wbtest_join_path(root, "reports/scaffold.md")
  let _ = try? @fs.rmdir(root, recursive=true)
  assert_true(
    emit_unified_tsmbt_scaffold(
      "fixtures/resolver/project/types/export-equals-entry.d.ts",
      wbtest_join_path(root, "generated"),
      direction=TsmbtDirection::TsToMbt,
      module_spec=Some("./runtime/export-equals.js"),
      import_rewrite_path=None,
      diagnostics_path=Some(diagnostics_path),
      strict=false,
      facade=true,
    ),
  )
  let diagnostics = @fs.read_file(diagnostics_path).text() catch {
    e => fail("failed to read requested unified diagnostics: \{e}")
  }
  assert_false(diagnostics.contains("No unsupported exports were detected."))
  assert_true(
    diagnostics.contains("No structural unsupported exports were detected"),
  )
  assert_true(diagnostics.contains("## Fallback Policy"))
  assert_true(
    diagnostics.contains("| `./runtime/export-equals.js` | unclassified |"),
  )
  assert_true(diagnostics.contains("## JSValue Fallbacks"))
  assert_true(diagnostics.contains("bridge.mbti"))
}

///|
test "unified JSValue diagnostics ignore shared declarations" {
  let out : Array[String] = []
  collect_unified_jsvalue_fallbacks_from_source(
    "bridge.mbti",
    [
      "/// Complex or unsupported TypeScript types are widened to JSValue.", "declare pub type JSValue",
      "declare pub fn parse(input : String) -> JSValue",
    ].join("\n"),
    out,
  )
  collect_unified_jsvalue_fallbacks_from_source(
    "bridge.mbt",
    [
      "#external\npub type JSValue", "pub extern \"js\" fn parse(input : String) -> JSValue = \"parse\"",
    ].join("\n"),
    out,
  )
  @test.assert_eq(
    "[" + out.join(", ") + "]",
    "[bridge.mbti:3: declare pub fn parse(input : String) -> JSValue, bridge.mbt:3: pub extern \"js\" fn parse(input : String) -> JSValue = \"parse\"]",
  )
}

///|
test "unified TS diagnostics include fallback policy classification" {
  let diagnostics = render_unified_ts_scaffold_diagnostics_md(
    "node:assert",
    [],
    ["bridge.mbti:10: declare pub fn assertOk(value : JSValue) -> JSValue"],
  )
  assert_true(diagnostics.contains("## Fallback Policy"))
  assert_true(
    diagnostics.contains(
      "| `node:assert` | naturalize-target | Shrink remaining Node built-in overload/unknown fallbacks toward zero for the common API surface. |",
    ),
  )
  assert_true(diagnostics.contains("## JSValue Fallbacks"))
}

///|
async test "emit_unified_tsmbt_scaffold strict mode rejects JSValue fallbacks" {
  let root = wbtest_tmp_project_benchmark_root(
    "unified_ts_to_mbt_strict_jsvalue",
  )
  let diagnostics_path = wbtest_join_path(root, "strict.md")
  let _ = try? @fs.rmdir(root, recursive=true)
  assert_false(
    emit_unified_tsmbt_scaffold(
      "fixtures/resolver/project/types/export-equals-entry.d.ts",
      wbtest_join_path(root, "generated"),
      direction=TsmbtDirection::TsToMbt,
      module_spec=Some("./runtime/export-equals.js"),
      import_rewrite_path=None,
      diagnostics_path=Some(diagnostics_path),
      strict=true,
      facade=true,
    ),
  )
  let diagnostics = @fs.read_file(diagnostics_path).text() catch {
    e => fail("failed to read strict JSValue diagnostics: \{e}")
  }
  assert_true(diagnostics.contains("## JSValue Fallbacks"))
  assert_true(diagnostics.contains("bridge.mbti"))
}

///|
async test "emit_unified_tsmbt_scaffold strict mode rejects unsupported exports" {
  let root = wbtest_tmp_project_benchmark_root(
    "unified_ts_to_mbt_strict_unsupported",
  )
  let diagnostics_path = wbtest_join_path(root, "strict.md")
  let _ = try? @fs.rmdir(root, recursive=true)
  assert_false(
    emit_unified_tsmbt_scaffold(
      "fixtures/resolver/project/types/ambiguous-entry.d.ts",
      wbtest_join_path(root, "generated"),
      direction=TsmbtDirection::TsToMbt,
      module_spec=Some("./runtime/ambiguous.js"),
      import_rewrite_path=None,
      diagnostics_path=Some(diagnostics_path),
      strict=true,
      facade=true,
    ),
  )
  let diagnostics = @fs.read_file(diagnostics_path).text() catch {
    e => fail("failed to read strict unsupported diagnostics: \{e}")
  }
  assert_true(diagnostics.contains("Shared (ambiguous re-export:"))
  assert_true(
    diagnostics.contains("| `Shared` | widened | ambiguous re-export surface |"),
  )
}

///|
async test "emit_unified_tsmbt_scaffold strict mode rejects enum-like unsupported exports" {
  let root = wbtest_tmp_project_benchmark_root(
    "unified_ts_to_mbt_strict_enum_like_unsupported",
  )
  let diagnostics_path = wbtest_join_path(root, "strict.md")
  let _ = try? @fs.rmdir(root, recursive=true)
  assert_false(
    emit_unified_tsmbt_scaffold(
      "fixtures/resolver/project/types/unsupported-enum-like-entry.d.ts",
      wbtest_join_path(root, "generated"),
      direction=TsmbtDirection::TsToMbt,
      module_spec=Some("./runtime/unsupported-enum-like.js"),
      import_rewrite_path=None,
      diagnostics_path=Some(diagnostics_path),
      strict=true,
      facade=true,
    ),
  )
  let diagnostics = @fs.read_file(diagnostics_path).text() catch {
    e => fail("failed to read strict enum-like diagnostics: \{e}")
  }
  assert_true(
    diagnostics.contains(
      "MixedMode (mixed string/number enum cannot be lowered safely.)",
    ),
  )
  assert_true(
    diagnostics.contains(
      "| `MixedMode` | omitted | unsupported export surface |",
    ),
  )
}

///|
async test "emit_unified_tsmbt_scaffold creates nested TypeScript to MoonBit output dirs" {
  let root = wbtest_tmp_project_benchmark_root("unified_ts_to_mbt_nested")
  let out_dir = wbtest_join_path(root, "dist/generated")
  let _ = try? @fs.rmdir(root, recursive=true)
  assert_true(
    emit_unified_tsmbt_scaffold(
      "fixtures/resolver/project/types/neverthrow-like-entry.d.ts",
      out_dir,
      direction=TsmbtDirection::TsToMbt,
      module_spec=Some("/runtime/neverthrow-like.js"),
      import_rewrite_path=None,
      facade=true,
    ),
  )
  let bridge_mbt = @fs.read_file(wbtest_join_path(out_dir, "bridge.mbt")).text() catch {
    e => fail("failed to read nested unified TS bridge.mbt: \{e}")
  }
  assert_true(bridge_mbt.contains("pub fn parseUser"))
}

///|
async test "emit_typescript_decl_from_mbti_text emits TypeScript declarations from mbti" {
  let actual = emit_typescript_decl_from_mbti_text(
    "fixtures/mbti_typescript/basic.pkg.generated.mbti",
  ) catch {
    @bridge.MbtiTypescriptDeclError::ReadError(msg)
    | @bridge.MbtiTypescriptDeclError::ParseError(msg) =>
      fail("Emit error: \{msg}")
  }
  assert_true(actual.contains("export function identity<T>(value: T): T;"))
  assert_true(
    actual.contains(
      "export function debug_identity<T extends debug.Debug>(value: T): T;",
    ),
  )
  assert_true(
    actual.contains("import type * as json from \"moonbitlang/core/json\";"),
  )
  assert_true(actual.contains("export interface Show {"))
  assert_true(actual.contains("export interface Eq<T> {"))
  assert_true(actual.contains("export interface Hash {"))
  assert_true(actual.contains("export interface Comparable<T> {"))
  assert_true(
    actual.contains(
      "export interface Box<T> extends Show, Eq<Box<T>>, Hash, Comparable<Box<T>> {",
    ),
  )
  assert_true(
    actual.contains("export function Box_unwrap<T>(self : Box<T>): T;"),
  )
  assert_true(
    actual.contains(
      "export function Box_map<T, U>(self : Box<T>, fn_: (value: T) => U): Box<U>;",
    ),
  )
  assert_true(
    actual.contains("export function Box_show_value<T>(self : Box<T>): string;"),
  )
  assert_true(
    actual.contains("export function Box_create<T>(value: T): Box<T>;"),
  )
  assert_true(actual.contains("export type Result<T, E> ="))
  assert_true(
    actual.contains(
      "export function Result_is_ok<T, E>(self : Result<T, E>): boolean;",
    ),
  )
  assert_true(actual.contains("module: ast.TsModule;"))
  assert_true(actual.contains("export type InternalThing<T> ="))
  assert_true(actual.contains("Eq<ParseError>"))
  assert_true(actual.contains("Eq<InternalThing<T>> & Hash"))
  assert_true(
    actual.contains(
      "export function MaybeString_is_empty(self : MaybeString): boolean;",
    ),
  )
  assert_true(
    actual.contains(
      "export type MaybeString = (string | undefined) & Show & Hash & json.ToJson;",
    ),
  )
  assert_true(actual.contains("json.ToJson"))
  assert_true(
    actual.contains(
      "export type DerivedStatus = ({ $tag: \"Ready\" }) & Eq<DerivedStatus>;",
    ),
  )
}

///|
async test "emit_js_link_config_from_mbti_text emits MoonBit JS link config from mbti" {
  let actual = emit_js_link_config_from_mbti_text(
    "fixtures/mbti_typescript/basic.pkg.generated.mbti",
  ) catch {
    @bridge.MbtiJsLinkConfigError::ReadError(msg)
    | @bridge.MbtiJsLinkConfigError::ParseError(msg) =>
      fail("Emit error: \{msg}")
  }
  assert_true(actual.contains("\"identity\""))
  assert_true(actual.contains("\"debug_identity\""))
  assert_true(actual.contains("\"wrap_pair\""))
  assert_false(actual.contains("Box::unwrap"))
  assert_true(actual.contains("\"format\": \"esm\""))
}

///|
async test "emit_typescript_package_from_mbti writes recursive declaration bundle" {
  let root = wbtest_tmp_project_benchmark_root("mbti_typescript_package_bundle")
  let _ = try? @fs.rmdir(root, recursive=true)
  @fs.mkdir(root, permission=0o755)
  let _ = emit_typescript_package_from_mbti(
    "fixtures/mbti_typescript_package/pkg.generated.mbti",
    root,
    None,
  )
  let root_decl = @fs.read_file(wbtest_join_path(root, "index.d.ts")).text() catch {
    e => fail("failed to read root index.d.ts: \{e}")
  }
  let child_decl = @fs.read_file(wbtest_join_path(root, "child/index.d.ts")).text() catch {
    e => fail("failed to read child index.d.ts: \{e}")
  }
  assert_true(root_decl.contains("import type * as child from \"./child\";"))
  assert_true(root_decl.contains("item: child.Item;"))
  assert_true(child_decl.contains("export interface Item {"))
}

///|
async test "emit_typescript_scaffold_from_mbti writes declaration package metadata" {
  let root = wbtest_tmp_project_benchmark_root(
    "mbti_typescript_scaffold_bundle",
  )
  let _ = try? @fs.rmdir(root, recursive=true)
  @fs.mkdir(root, permission=0o755)
  assert_true(
    emit_typescript_scaffold_from_mbti(
      "examples/moonbit-to-typescript/counter/pkg.generated.mbti",
      root,
      None,
    ),
  )
  let package_json = @fs.read_file(wbtest_join_path(root, "package.json")).text() catch {
    e => fail("failed to read package.json: \{e}")
  }
  let diagnostics_md = @fs.read_file(
    wbtest_join_path(root, "AUTOLINK_DIAGNOSTICS.md"),
  ).text() catch {
    e => fail("failed to read AUTOLINK_DIAGNOSTICS.md: \{e}")
  }
  let root_decl = @fs.read_file(wbtest_join_path(root, "index.d.ts")).text() catch {
    e => fail("failed to read root index.d.ts: \{e}")
  }
  let root_js = @fs.read_file(wbtest_join_path(root, "index.js")).text() catch {
    e => fail("failed to read root index.js: \{e}")
  }
  assert_true(package_json.contains("\"name\": \"@examples/counter\""))
  assert_true(package_json.contains("\"import\": \"./index.js\""))
  assert_true(
    package_json.contains(
      "\"./child\": { \"types\": \"./child/index.d.ts\", \"import\": \"./child/index.js\" }",
    ),
  )
  assert_true(diagnostics_md.contains("Counter::label"))
  assert_true(root_decl.contains("import type * as child from \"./child\";"))
  assert_false(root_decl.contains("counter_label"))
  assert_true(root_js.contains("function __tsmbt_public_return(value)"))
  assert_true(root_js.contains("export function create(...args)"))
}

///|
async test "emit_typescript_package_from_mbti rewrites external imports from json map" {
  let root = wbtest_tmp_project_benchmark_root(
    "mbti_typescript_package_bundle_rewrites",
  )
  let _ = try? @fs.rmdir(root, recursive=true)
  @fs.mkdir(root, permission=0o755)
  let _ = emit_typescript_package_from_mbti(
    "fixtures/mbti_typescript_package/pkg.generated.mbti",
    root,
    Some("fixtures/mbti_typescript_package/import-rewrites.json"),
  )
  let root_decl = @fs.read_file(wbtest_join_path(root, "index.d.ts")).text() catch {
    e => fail("failed to read rewritten root index.d.ts: \{e}")
  }
  assert_true(root_decl.contains("import type * as debug from \"demo-debug\";"))
  assert_false(root_decl.contains("\"moonbitlang/core/debug\""))
}

///|
async test "emit_typescript_scaffold_from_mbti rejects mbti fixtures without source package" {
  let root = wbtest_tmp_project_benchmark_root(
    "mbti_typescript_scaffold_bundle_fixture_rejected",
  )
  let _ = try? @fs.rmdir(root, recursive=true)
  @fs.mkdir(root, permission=0o755)
  assert_false(
    emit_typescript_scaffold_from_mbti(
      "fixtures/mbti_typescript_package/pkg.generated.mbti",
      root,
      None,
    ),
  )
  assert_false(@fs.exists(wbtest_join_path(root, "package.json")))
  assert_false(@fs.exists(wbtest_join_path(root, "index.d.ts")))
  assert_false(@fs.exists(wbtest_join_path(root, "index.js")))
}

///|
async test "emit_typescript_scaffold_from_mbti handles moon.mod source subdir" {
  let root = wbtest_tmp_project_benchmark_root(
    "mbti_typescript_scaffold_source_subdir",
  )
  let _ = try? @fs.rmdir(root, recursive=true)
  let pkg_dir = wbtest_join_path(root, "src/pkg")
  ensure_dir_tree(pkg_dir)
  @fs.write_file(
    wbtest_join_path(root, "moon.mod.json"),
    (
      #|{
      #|  "name": "fixture/source-subdir",
      #|  "version": "0.1.0",
      #|  "source": "src",
      #|  "preferred-target": "js"
      #|}
    ),
    create=0o644,
  )
  @fs.write_file(wbtest_join_path(pkg_dir, "moon.pkg"), "", create=0o644)
  @fs.write_file(
    wbtest_join_path(pkg_dir, "pkg.mbt"),
    (
      #|///|
      #|pub struct Cell {
      #|  value : String
      #|}
      #|
      #|///|
      #|pub fn make(value : String) -> Cell {
      #|  { value }
      #|}
      #|
      #|///|
      #|pub fn render(cell : Cell) -> String {
      #|  cell.value
      #|}
    ),
    create=0o644,
  )
  let (info_exit, info_output) = @process.collect_output_merged(
    "moon",
    ["-C", root, "info"],
    cwd=".",
  )
  if info_exit != 0 {
    fail("moon info failed: \{info_output.text()}")
  }
  let out = wbtest_join_path(root, "dist")
  assert_true(
    emit_typescript_scaffold_from_mbti(
      wbtest_join_path(pkg_dir, "pkg.generated.mbti"),
      out,
      None,
    ),
  )
  let package_json = @fs.read_file(wbtest_join_path(out, "package.json")).text() catch {
    e => fail("failed to read source-subdir package.json: \{e}")
  }
  let root_decl = @fs.read_file(wbtest_join_path(out, "index.d.ts")).text() catch {
    e => fail("failed to read source-subdir index.d.ts: \{e}")
  }
  let root_js = @fs.read_file(wbtest_join_path(out, "index.js")).text() catch {
    e => fail("failed to read source-subdir index.js: \{e}")
  }
  assert_true(package_json.contains("\"name\": \"@fixture/source-subdir-pkg\""))
  assert_true(root_decl.contains("export function make(s: string): Cell;"))
  assert_true(root_js.contains("function __tsmbt_public_return(value)"))
  assert_true(root_js.contains("export function make(...args)"))
}

///|
async test "emit_typescript_scaffold_from_mbti handles DSL moon.mod source subdir" {
  let root = wbtest_tmp_project_benchmark_root(
    "mbti_typescript_scaffold_dsl_source_subdir",
  )
  let _ = try? @fs.rmdir(root, recursive=true)
  let pkg_dir = wbtest_join_path(root, "src/pkg")
  ensure_dir_tree(pkg_dir)
  @fs.write_file(
    wbtest_join_path(root, "moon.mod"),
    (
      #|name = "fixture/dsl-source-subdir"
      #|version = "0.1.0"
      #|source = "src"
    ),
    create=0o644,
  )
  @fs.write_file(wbtest_join_path(pkg_dir, "moon.pkg"), "", create=0o644)
  @fs.write_file(
    wbtest_join_path(pkg_dir, "pkg.mbt"),
    (
      #|///|
      #|pub struct Cell {
      #|  value : String
      #|}
      #|
      #|///|
      #|pub fn make(value : String) -> Cell {
      #|  { value }
      #|}
    ),
    create=0o644,
  )
  let (info_exit, info_output) = @process.collect_output_merged(
    "moon",
    ["-C", root, "info"],
    cwd=".",
  )
  if info_exit != 0 {
    fail("moon info failed: \{info_output.text()}")
  }
  let out = wbtest_join_path(root, "dist")
  assert_true(
    emit_typescript_scaffold_from_mbti(
      wbtest_join_path(pkg_dir, "pkg.generated.mbti"),
      out,
      None,
    ),
  )
  let package_json = @fs.read_file(wbtest_join_path(out, "package.json")).text() catch {
    e => fail("failed to read DSL source-subdir package.json: \{e}")
  }
  let root_js = @fs.read_file(wbtest_join_path(out, "index.js")).text() catch {
    e => fail("failed to read DSL source-subdir index.js: \{e}")
  }
  assert_true(
    package_json.contains("\"name\": \"@fixture/dsl-source-subdir-pkg\""),
  )
  assert_true(root_js.contains("function __tsmbt_public_return(value)"))
  assert_true(root_js.contains("export function make(...args)"))
}

///|
async test "emit_typescript_npm_package_from_project creates a publishable npm directory" {
  let root = wbtest_tmp_project_benchmark_root("mbt2ts_pkg_publishable")
  let _ = try? @fs.rmdir(root, recursive=true)
  let source_root = wbtest_join_path(root, "src")
  ensure_dir_tree(source_root)
  @fs.write_file(
    wbtest_join_path(root, "moon.mod.json"),
    (
      #|{
      #|  "name": "fixture/npm-ready",
      #|  "version": "1.2.3",
      #|  "description": "A publishable MoonBit fixture",
      #|  "license": "Apache-2.0",
      #|  "repository": "https://github.com/fixture/npm-ready",
      #|  "source": "src",
      #|  "preferred-target": "js"
      #|}
    ),
    create=0o644,
  )
  @fs.write_file(wbtest_join_path(source_root, "moon.pkg"), "", create=0o644)
  @fs.write_file(
    wbtest_join_path(source_root, "lib.mbt"),
    (
      #|///|
      #|pub fn greet(name : String) -> String {
      #|  "Hello, " + name
      #|}
    ),
    create=0o644,
  )
  @fs.write_file(
    wbtest_join_path(root, "README.md"),
    "# fixture npm package\n",
    create=0o644,
  )
  @fs.write_file(
    wbtest_join_path(root, "LICENSE"),
    "Apache-2.0\n",
    create=0o644,
  )

  assert_true(
    emit_typescript_npm_package_from_project(root, None, None, false, true),
  )

  let npm_dir = wbtest_join_path(root, "npm")
  let package_json = @fs.read_file(wbtest_join_path(npm_dir, "package.json")).text() catch {
    e => fail("failed to read generated npm package.json: \{e}")
  }
  assert_true(package_json.contains("\"name\": \"@fixture/npm-ready\""))
  assert_true(package_json.contains("\"version\": \"1.2.3\""))
  assert_true(
    package_json.contains("\"description\": \"A publishable MoonBit fixture\""),
  )
  assert_true(package_json.contains("\"license\": \"Apache-2.0\""))
  assert_true(
    package_json.contains(
      "\"repository\": { \"type\": \"git\", \"url\": \"git+https://github.com/fixture/npm-ready.git\" }",
    ),
  )
  assert_true(package_json.contains("\"files\": ["))
  assert_true(package_json.contains("\"index.d.ts\""))
  assert_true(package_json.contains("\"index.js\""))
  assert_false(package_json.contains("**/*.d.ts"))
  assert_true(@fs.exists(wbtest_join_path(npm_dir, "index.js")))
  assert_true(@fs.exists(wbtest_join_path(npm_dir, "index.d.ts")))
  assert_true(@fs.exists(wbtest_join_path(npm_dir, "README.md")))
  assert_true(@fs.exists(wbtest_join_path(npm_dir, "LICENSE")))
  let (pack_exit, pack_output) = @process.collect_output_merged(
    "npm",
    ["pack", "--dry-run"],
    cwd=npm_dir,
  )
  if pack_exit != 0 {
    fail("npm pack --dry-run failed: \{pack_output.text()}")
  }
}

///|
async test "emit_typescript_npm_package_from_project exports unreferenced source submodules" {
  let root = wbtest_tmp_project_benchmark_root("mbt2ts_pkg_submodule_exports")
  let _ = try? @fs.rmdir(root, recursive=true)
  let source_root = wbtest_join_path(root, "src")
  let mtsc_root = wbtest_join_path(source_root, "mtsc")
  let command_root = wbtest_join_path(source_root, "cmd/checker")
  let ignored_command_root = wbtest_join_path(source_root, "cmd/ignored")
  ensure_dir_tree(mtsc_root)
  ensure_dir_tree(command_root)
  ensure_dir_tree(ignored_command_root)
  @fs.write_file(
    wbtest_join_path(root, "moon.mod.json"),
    (
      #|{
      #|  "name": "fixture/npm-submodule-exports",
      #|  "version": "1.2.3",
      #|  "source": "src",
      #|  "preferred-target": "js",
      #|  "options": { "exclude": ["src/cmd/ignored"] }
      #|}
    ),
    create=0o644,
  )
  @fs.write_file(
    wbtest_join_path(source_root, "moon.pkg"),
    "pkgtype(kind: \"executable\")\n",
    create=0o644,
  )
  @fs.write_file(
    wbtest_join_path(source_root, "root.mbt"),
    "pub fn root_value() -> String { \"root\" }\n",
    create=0o644,
  )
  @fs.write_file(
    wbtest_join_path(source_root, "main.mbt"),
    "pub fn main_helper() -> String { \"helper\" }\nfn main { println(\"root command\") }\n",
    create=0o644,
  )
  @fs.write_file(wbtest_join_path(mtsc_root, "moon.pkg"), "", create=0o644)
  @fs.write_file(
    wbtest_join_path(mtsc_root, "checker.mbt"),
    "pub fn check_source(source : String) -> String { if source == \"bad\" { \"type error\" } else { \"\" } }\n",
    create=0o644,
  )
  @fs.write_file(
    wbtest_join_path(command_root, "moon.pkg"),
    "pkgtype(kind: \"executable\")\n",
    create=0o644,
  )
  @fs.write_file(
    wbtest_join_path(command_root, "main.mbt"),
    "fn main { println(\"checker command\") }\n",
    create=0o644,
  )
  @fs.write_file(
    wbtest_join_path(ignored_command_root, "moon.pkg"),
    "pkgtype(kind: \"executable\")\n",
    create=0o644,
  )
  @fs.write_file(
    wbtest_join_path(ignored_command_root, "main.mbt"),
    "fn main { println(\"ignored command\") }\n",
    create=0o644,
  )

  assert_true(
    emit_typescript_npm_package_from_project(root, None, None, false, true),
  )

  let npm_dir = wbtest_join_path(root, "npm")
  let package_json = @fs.read_file(wbtest_join_path(npm_dir, "package.json")).text() catch {
    e => fail("failed to read generated submodule package.json: \{e}")
  }
  let mtsc_decl = @fs.read_file(wbtest_join_path(npm_dir, "mtsc/index.d.ts")).text() catch {
    e => fail("failed to read generated mtsc declaration: \{e}")
  }
  assert_true(
    package_json.contains(
      "\"./mtsc\": { \"types\": \"./mtsc/index.d.ts\", \"import\": \"./mtsc/index.js\" }",
    ),
  )
  assert_true(@fs.exists(wbtest_join_path(npm_dir, "mtsc/index.js")))
  assert_true(mtsc_decl.contains("export function check_source"))
  assert_true(package_json.contains("\"bin\": {"))
  assert_true(package_json.contains("\"checker\": \"./bin/checker.js\""))
  let command_bin = @fs.read_file(wbtest_join_path(npm_dir, "bin/checker.js")).text() catch {
    e => fail("failed to read generated command bin: \{e}")
  }
  assert_true(command_bin.has_prefix("#!/usr/bin/env node\n"))
  assert_false(package_json.contains("\"./cmd/checker\""))
  assert_true(
    package_json.contains(
      "\"npm-submodule-exports\": \"./bin/npm-submodule-exports.js\"",
    ),
  )
  let root_command_bin = @fs.read_file(
    wbtest_join_path(npm_dir, "bin/npm-submodule-exports.js"),
  ).text() catch {
    e => fail("failed to read generated root command bin: \{e}")
  }
  assert_true(root_command_bin.has_prefix("#!/usr/bin/env node\n"))
  assert_false(package_json.contains("\"ignored\": \"./bin/ignored.js\""))
  assert_false(@fs.exists(wbtest_join_path(npm_dir, "bin/ignored.js")))
}

///|
async test "emit_typescript_facade_scaffold_from_mbti writes facade declarations" {
  let root = wbtest_tmp_project_benchmark_root(
    "mbti_typescript_facade_scaffold",
  )
  let _ = try? @fs.rmdir(root, recursive=true)
  @fs.mkdir(root, permission=0o755)
  assert_true(
    emit_typescript_facade_scaffold_from_mbti(
      "examples/moonbit-to-typescript/counter/pkg.generated.mbti",
      root,
      None,
    ),
  )
  let root_decl = @fs.read_file(wbtest_join_path(root, "index.d.ts")).text() catch {
    e => fail("failed to read facade index.d.ts: \{e}")
  }
  let root_js = @fs.read_file(wbtest_join_path(root, "index.js")).text() catch {
    e => fail("failed to read facade index.js: \{e}")
  }
  assert_true(
    root_decl.contains("export function counter_label(self: Counter): string;"),
  )
  assert_true(root_js.contains("counter__label"))
}

///|
async test "emit_typescript_facade_scaffold_from_mbti keeps root imports in facade declarations" {
  let root = wbtest_tmp_project_benchmark_root(
    "mbti_typescript_facade_scaffold_imports",
  )
  let _ = try? @fs.rmdir(root, recursive=true)
  @fs.mkdir(root, permission=0o755)
  assert_true(
    emit_typescript_facade_scaffold_from_mbti(
      "examples/moonbit-to-typescript/counter/pkg.generated.mbti",
      root,
      None,
    ),
  )
  let root_decl = @fs.read_file(wbtest_join_path(root, "index.d.ts")).text() catch {
    e => fail("failed to read imported facade index.d.ts: \{e}")
  }
  assert_true(root_decl.contains("import type * as child from \"./child\";"))
  assert_true(root_decl.contains("item: child.Item;"))
  assert_true(
    root_decl.contains("export function counter_label(self: Counter): string;"),
  )
}

///|
async test "emit_typescript_decl_text normalizes MoonBit generated d.ts" {
  let actual = emit_typescript_decl_text(
    "fixtures/typescript_decl/moonbit_generated/app.d.ts",
  ) catch {
    @bridge.ModuleGraphError::ReadError(msg)
    | @bridge.ModuleGraphError::ParseError(msg)
    | @bridge.ModuleGraphError::ResolveError(msg) => fail("Emit error: \{msg}")
  }
  assert_true(actual.contains("x: number"))
  assert_true(actual.contains("): string;"))
  assert_false(actual.contains("MoonBit.Double"))
}

///|
async test "emit_typescript_decl_text expands common MoonBit aliases from moonbit.d.ts" {
  let actual = emit_typescript_decl_text(
    "fixtures/typescript_decl/moonbit_generated/advanced.d.ts",
  ) catch {
    @bridge.ModuleGraphError::ReadError(msg)
    | @bridge.ModuleGraphError::ParseError(msg)
    | @bridge.ModuleGraphError::ResolveError(msg) => fail("Emit error: \{msg}")
  }
  assert_true(actual.contains("export type UserId = bigint;"))
  assert_true(actual.contains("export type Scores = Array<number>;"))
  assert_true(actual.contains("export type MaybeName = string | undefined;"))
  assert_true(
    actual.contains(
      "): { $tag: 1; _0: string | undefined } | { $tag: 0; _0: bigint };",
    ),
  )
}

///|
async test "emit_typescript_decl_text expands nested MoonBit generic aliases" {
  let actual = emit_typescript_decl_text(
    "fixtures/typescript_decl/moonbit_generated/nested_alias.d.ts",
  ) catch {
    @bridge.ModuleGraphError::ReadError(msg)
    | @bridge.ModuleGraphError::ParseError(msg)
    | @bridge.ModuleGraphError::ResolveError(msg) => fail("Emit error: \{msg}")
  }
  assert_true(
    actual.contains(
      "): { value: { $tag: 1; _0: string } | { $tag: 0; _0: number } };",
    ),
  )
}

///|
async test "emit_typescript_decl_text expands interface-based MoonBit aliases" {
  let actual = emit_typescript_decl_text(
    "fixtures/typescript_decl/moonbit_generated/interface_alias.d.ts",
  ) catch {
    @bridge.ModuleGraphError::ReadError(msg)
    | @bridge.ModuleGraphError::ParseError(msg)
    | @bridge.ModuleGraphError::ResolveError(msg) => fail("Emit error: \{msg}")
  }
  assert_true(
    actual.contains(
      "): { value: { $tag: 1; _0: string } | { $tag: 0; _0: number }; ok: boolean };",
    ),
  )
}

///|
async test "emit_typescript_decl_text flattens interface extends aliases" {
  let actual = emit_typescript_decl_text(
    "fixtures/typescript_decl/moonbit_generated/interface_extends_alias.d.ts",
  ) catch {
    @bridge.ModuleGraphError::ReadError(msg)
    | @bridge.ModuleGraphError::ParseError(msg)
    | @bridge.ModuleGraphError::ResolveError(msg) => fail("Emit error: \{msg}")
  }
  assert_true(
    actual.contains(
      "): { value: { $tag: 1; _0: string } | { $tag: 0; _0: number }; kind: string; ok: boolean };",
    ),
  )
}

///|
async test "emit_typescript_decl_text keeps conflicting interface extends as intersections" {
  let actual = emit_typescript_decl_text(
    "fixtures/typescript_decl/moonbit_generated/interface_extends_conflict_alias.d.ts",
  ) catch {
    @bridge.ModuleGraphError::ReadError(msg)
    | @bridge.ModuleGraphError::ParseError(msg)
    | @bridge.ModuleGraphError::ResolveError(msg) => fail("Emit error: \{msg}")
  }
  assert_true(
    actual.contains(
      "export function conflicting_payload_result(): { value: string } & { value: number } & { ok: boolean };",
    ),
  )
}

///|
async test "emit_typescript_decl_text keeps identical inherited members flattened" {
  let actual = emit_typescript_decl_text(
    "fixtures/typescript_decl/moonbit_generated/interface_extends_shared_member_alias.d.ts",
  ) catch {
    @bridge.ModuleGraphError::ReadError(msg)
    | @bridge.ModuleGraphError::ParseError(msg)
    | @bridge.ModuleGraphError::ResolveError(msg) => fail("Emit error: \{msg}")
  }
  assert_true(
    actual.contains(
      "export function shared_tagged_payload_result(): { kind: string; ok: boolean };",
    ),
  )
}

///|
async test "emit_typescript_decl_text keeps identical readonly inherited members flattened" {
  let actual = emit_typescript_decl_text(
    "fixtures/typescript_decl/moonbit_generated/interface_extends_shared_readonly_alias.d.ts",
  ) catch {
    @bridge.ModuleGraphError::ReadError(msg)
    | @bridge.ModuleGraphError::ParseError(msg)
    | @bridge.ModuleGraphError::ResolveError(msg) => fail("Emit error: \{msg}")
  }
  assert_true(
    actual.contains(
      "export function shared_readonly_payload_result(): { readonly count: number; ok: boolean };",
    ),
  )
}

///|
async test "emit_typescript_decl_text keeps conflicting readonly members as intersections" {
  let actual = emit_typescript_decl_text(
    "fixtures/typescript_decl/moonbit_generated/interface_extends_conflicting_readonly_alias.d.ts",
  ) catch {
    @bridge.ModuleGraphError::ReadError(msg)
    | @bridge.ModuleGraphError::ParseError(msg)
    | @bridge.ModuleGraphError::ResolveError(msg) => fail("Emit error: \{msg}")
  }
  assert_true(
    actual.contains(
      "export function conflicting_readonly_payload_result(): { readonly count: number } & { count: number } & { ok: boolean };",
    ),
  )
}

///|
async test "emit_typescript_decl_text keeps identical optional members flattened" {
  let actual = emit_typescript_decl_text(
    "fixtures/typescript_decl/moonbit_generated/interface_extends_shared_optional_alias.d.ts",
  ) catch {
    @bridge.ModuleGraphError::ReadError(msg)
    | @bridge.ModuleGraphError::ParseError(msg)
    | @bridge.ModuleGraphError::ResolveError(msg) => fail("Emit error: \{msg}")
  }
  assert_true(
    actual.contains(
      "export function shared_optional_payload_result(): { name?: string; ok: boolean };",
    ),
  )
}

///|
async test "emit_typescript_decl_text keeps conflicting optional members as intersections" {
  let actual = emit_typescript_decl_text(
    "fixtures/typescript_decl/moonbit_generated/interface_extends_conflicting_optional_alias.d.ts",
  ) catch {
    @bridge.ModuleGraphError::ReadError(msg)
    | @bridge.ModuleGraphError::ParseError(msg)
    | @bridge.ModuleGraphError::ResolveError(msg) => fail("Emit error: \{msg}")
  }
  assert_true(
    actual.contains(
      "export function conflicting_optional_payload_result(): { name?: string } & { name: string } & { ok: boolean };",
    ),
  )
}

///|
async test "emit_moonbit_decl_text resolves type reexports from entry file" {
  let actual = emit_moonbit_decl_text(
    "fixtures/resolver/project/types/entry.d.ts",
  ) catch {
    @bridge.ModuleGraphError::ReadError(msg)
    | @bridge.ModuleGraphError::ParseError(msg)
    | @bridge.ModuleGraphError::ResolveError(msg) => {
      fail("Emit error: \{msg}")
      return
    }
  }
  assert_true(actual.contains("declare pub type PublicPoint"))
  assert_true(
    actual.contains("declare pub fn render(point : PublicPoint) -> PublicPoint"),
  )
  assert_false(actual.contains("declare pub fn hidden"))
}

///|
async test "emit_moonbit_js_ffi_texts generates ffi and bridge snippets" {
  let bundle = emit_moonbit_js_ffi_texts(
    "fixtures/resolver/project/types/entry.d.ts", "/runtime/mod.js",
  ) catch {
    @bridge.ModuleGraphError::ReadError(msg)
    | @bridge.ModuleGraphError::ParseError(msg)
    | @bridge.ModuleGraphError::ResolveError(msg) => {
      fail("Emit error: \{msg}")
      return
    }
  }
  assert_true(bundle.ffi_mbt.contains("pub extern \"js\" fn render("))
  assert_false(bundle.bridge_js.contains("__ts_mbt_render"))
}

///|
async test "emit_moonbit_bridge_texts generates decl, ffi, and bridge snippets" {
  let bundle = emit_moonbit_bridge_texts(
    "fixtures/resolver/project/types/runtime-function-entry.ts", "/runtime/runtime-function.js",
  ) catch {
    @bridge.ModuleGraphError::ReadError(msg)
    | @bridge.ModuleGraphError::ParseError(msg)
    | @bridge.ModuleGraphError::ResolveError(msg) => {
      fail("Emit error: \{msg}")
      return
    }
  }
  @test.assert_eq(
    bundle.entry_path,
    "fixtures/resolver/project/types/runtime-function-entry.ts",
  )
  @test.assert_eq(bundle.module_spec, "/runtime/runtime-function.js")
  assert_true(
    bundle.decl_mbt.contains(
      "declare pub fn scalePoint(point : RuntimePoint, factor : Double) -> RuntimePoint",
    ),
  )
  assert_true(bundle.ffi_mbt.contains("pub extern \"js\" fn scale_point("))
  assert_false(bundle.bridge_js.contains("__ts_mbt_scale_point"))
}

///|
async test "emit_moonbit_bridge_package_texts generates a compileable package bundle" {
  let bundle = emit_moonbit_bridge_package_texts(
    "fixtures/resolver/project/types/export-equals-entry.d.ts", "./runtime/export-equals.js",
  ) catch {
    @bridge.ModuleGraphError::ReadError(msg)
    | @bridge.ModuleGraphError::ParseError(msg)
    | @bridge.ModuleGraphError::ResolveError(msg) => {
      fail("Emit error: \{msg}")
      return
    }
  }
  // Generated bridge packages are now self-contained — no `mizchi/js`
  // dependency since `JSValue` and `Promise[X]` are emitted as
  // `#external` types directly in the package.
  assert_false(bundle.moon_pkg.contains("mizchi/js"))
  assert_true(bundle.bridge_mbt.contains("#external\npub type JSValue"))
  assert_true(bundle.bridge_mbti.contains("declare pub fn get_default()"))
  assert_true(bundle.bridge_mbt.contains("pub extern \"js\" fn get_default()"))
  assert_true(bundle.bridge_js.contains("export function __ts_mbt_get_default"))
}

///|
test "emit_moonbit_bridge_package splits large generated source into review files" {
  let bridge_mbt =
    #|#external
    #|pub type JSValue
    #|
    #|#external
    #|pub type RuntimePoint
    #|
    #|fn __ts_mbt_mode_to_js(value : Mode) -> String {
    #|  match value {
    #|    Read => "read"
    #|  }
    #|}
    #|
    #|#module("/runtime/bridge.js")
    #|extern "js" fn __ts_mbt_mode_from_js(value : String) -> Mode = "__ts_mbt_mode_from_js"
    #|
    #|#module("/runtime/bridge.js")
    #|pub extern "js" fn parse(input : String) -> JSValue = "__ts_mbt_parse"
    #|
    #|pub fn[A, B] unsafeCast(value : A) -> B = "%identity"
    #|
    #|pub fn Node::asIdentifier(self : Node) -> Identifier? {
    #|  if isIdentifier(self) {
    #|    Some(unsafeCast(self))
    #|  } else {
    #|    None
    #|  }
    #|}
    #|
    #|pub fn scalePoint(point : RuntimePoint, factor : Double) -> RuntimePoint {
    #|  scale_point(point, factor)
    #|}
  let files = bridge_package_mbt_files(bridge_mbt, force_split=true)
  let types_mbt = wbtest_find_file_content(files, "types.mbt")
  let converters_mbt = wbtest_find_file_content(files, "converters.mbt")
  let externs_mbt = wbtest_find_file_content(files, "externs.mbt")
  let guards_mbt = wbtest_find_file_content(files, "guards.mbt")
  let bridge_mbt = wbtest_find_file_content(files, "bridge.mbt")
  assert_true(types_mbt.contains("#external\npub type JSValue"))
  assert_true(types_mbt.contains("#external\npub type RuntimePoint"))
  assert_true(converters_mbt.contains("fn __ts_mbt_mode_to_js"))
  assert_true(converters_mbt.contains("__ts_mbt_mode_from_js"))
  assert_true(externs_mbt.contains("pub extern \"js\" fn parse"))
  assert_true(guards_mbt.contains("unsafeCast"))
  assert_true(guards_mbt.contains("Node::asIdentifier"))
  assert_true(bridge_mbt.contains("pub fn scalePoint"))
}

///|
async test "emit_moonbit_bridge_package writes package files to output dir" {
  let root = wbtest_tmp_project_benchmark_root("bridge_package")
  let _ = try? @fs.rmdir(root, recursive=true)
  let _ = emit_moonbit_bridge_package(
    "fixtures/resolver/project/types/runtime-function-entry.ts", "/runtime/runtime-function.js",
    root,
  )
  let legacy_manifest = wbtest_join_path(root, "moon.pkg.json")
  let _ = @fs.write_file(legacy_manifest, string_to_bytes("{}\n"))
  let user_file = wbtest_join_path(root, "user-authored.mbt")
  let _ = @fs.write_file(user_file, string_to_bytes("// keep\n"))
  let _ = emit_moonbit_bridge_package(
    "fixtures/resolver/project/types/runtime-function-entry.ts", "/runtime/runtime-function.js",
    root,
  )
  let pkg_json = @fs.read_file(wbtest_join_path(root, "moon.pkg")).text() catch {
    e => {
      fail("Read error: \{e}")
      return
    }
  }
  let bridge_mbti = @fs.read_file(wbtest_join_path(root, "bridge.mbti")).text() catch {
    e => {
      fail("Read error: \{e}")
      return
    }
  }
  let bridge_mbt = @fs.read_file(wbtest_join_path(root, "bridge.mbt")).text() catch {
    e => {
      fail("Read error: \{e}")
      return
    }
  }
  let bridge_js = @fs.read_file(wbtest_join_path(root, "bridge.js")).text() catch {
    e => {
      fail("Read error: \{e}")
      return
    }
  }
  @test.assert_eq(pkg_json, "")
  assert_false(@fs.exists(legacy_manifest))
  assert_true(@fs.exists(user_file))
  assert_false(@fs.exists(wbtest_join_path(root, ".tsmbt-next-bridge.mbt")))
  assert_true(bridge_mbti.contains("declare pub fn scalePoint("))
  assert_true(
    bridge_mbt.contains(
      "#module(\"/runtime/runtime-function.js\")\nextern \"js\" fn scale_point(",
    ),
  )
  assert_true(
    bridge_mbt.contains(
      "pub fn scalePoint(point : RuntimePoint, factor : Double) -> RuntimePoint {\n  scale_point(point, factor)\n}",
    ),
  )
  assert_false(bridge_js.contains("__ts_mbt_scale_point"))
  assert_false(bridge_mbt.contains("unsafeCast"))
  let _ = try? @fs.rmdir(root, recursive=true)
}

///|
test "bridge runtime validation emits public validators without exposing unsafeCast" {
  let bridge_mbti =
    #|/// TS interface RuntimePoint
    #|pub(all) struct RuntimePoint {
    #|  x : Double
    #|  label : String
    #|}
  let bridge_mbt =
    #|/// TS interface RuntimePoint
    #|pub(all) struct RuntimePoint {
    #|  x : Double
    #|  label : String
    #|}
  let (mbti, mbt) = add_bridge_runtime_validation(bridge_mbti, bridge_mbt)
  assert_true(
    mbti.contains(
      "declare pub fn validateRuntimePoint(value : JSValue) -> RuntimePoint?",
    ),
  )
  assert_true(
    mbt.contains("fn __ts_mbt_validate_RuntimePoint(value : JSValue) -> Bool"),
  )
  assert_true(mbt.contains("typeof value[\"x\"] === \"number\""))
  assert_true(mbt.contains("typeof value[\"label\"] === \"string\""))
  assert_true(mbt.contains("fn[A, B] unsafeCast(value : A) -> B"))
  assert_false(mbti.contains("unsafeCast"))
}

///|
test "bridge runtime validation permits absent optional primitive fields" {
  let bridge_mbt =
    #|pub(all) struct OptionalProfile {
    #|  name : String
    #|  age : Double?
    #|}
  let (_, mbt) = add_bridge_runtime_validation("", bridge_mbt)
  assert_true(
    mbt.contains(
      "(value[\"age\"] === undefined || typeof value[\"age\"] === \"number\")",
    ),
  )
  assert_false(mbt.contains("\"age\" in value"))
}

///|
async test "emit_moonbit_bridge_package rewrites relative runtime bridge to self-contained module path" {
  let root = wbtest_tmp_project_benchmark_root("bridge_package_relative")
  let _ = try? @fs.rmdir(root, recursive=true)
  let _ = emit_moonbit_bridge_package(
    "fixtures/resolver/project/types/runtime-function-entry.ts", "./runtime/runtime-function.js",
    root,
  )
  let bridge_mbt = @fs.read_file(wbtest_join_path(root, "bridge.mbt")).text() catch {
    e => {
      fail("Read error: \{e}")
      return
    }
  }
  let bridge_js = @fs.read_file(wbtest_join_path(root, "bridge.js")).text() catch {
    e => {
      fail("Read error: \{e}")
      return
    }
  }
  let bridge_js_path = "@tsmbt-bridge/" + wbtest_basename(root)
  assert_true(
    bridge_mbt.contains(
      "#module(\"\{bridge_js_path}\")\nextern \"js\" fn scale_point(point : RuntimePoint, factor : Double) -> RuntimePoint = \"__ts_mbt_scale_point\"",
    ),
  )
  assert_true(
    bridge_mbt.contains(
      "pub fn scalePoint(point : RuntimePoint, factor : Double) -> RuntimePoint {\n  scale_point(point, factor)\n}",
    ),
  )
  assert_true(
    bridge_js.contains(
      "export { scalePoint as __ts_mbt_scale_point } from \"./runtime/runtime-function.js\";",
    ),
  )
  let _ = try? @fs.rmdir(root, recursive=true)
}

///|
async test "emit_moonbit_bridge_package rewrites multiple relative generated bindings to bridge.js" {
  let root = wbtest_tmp_project_benchmark_root("bridge_package_class_property")
  let _ = try? @fs.rmdir(root, recursive=true)
  let _ = emit_moonbit_bridge_package(
    "fixtures/resolver/project/types/class-property-entry.d.ts", "./runtime/class-property.js",
    root,
  )
  let bridge_mbt = @fs.read_file(wbtest_join_path(root, "bridge.mbt")).text() catch {
    e => {
      fail("Read error: \{e}")
      return
    }
  }
  let bridge_js_path = "@tsmbt-bridge/" + wbtest_basename(root)
  assert_true(
    bridge_mbt.contains(
      "#module(\"\{bridge_js_path}\")\npub extern \"js\" fn new_counter_state()",
    ),
  )
  assert_true(
    bridge_mbt.contains(
      "#module(\"\{bridge_js_path}\")\npub extern \"js\" fn get_counter_state_version()",
    ),
  )
  assert_true(
    bridge_mbt.contains(
      "#module(\"\{bridge_js_path}\")\npub extern \"js\" fn set_counter_state_step(value : Double) -> Unit = \"__ts_mbt_set_counter_state_step\"",
    ),
  )
  assert_true(
    bridge_mbt.contains(
      "pub extern \"js\" fn CounterState::get_counter_state_label(self : CounterState) -> String =",
    ),
  )
  let _ = try? @fs.rmdir(root, recursive=true)
}

///|
async test "emit_moonbit_bridge_package rewrites rooted class-property alias reexport generated bindings to bridge.js" {
  let root = wbtest_tmp_project_benchmark_root(
    "bridge_package_class_property_reexport_rooted",
  )
  let _ = try? @fs.rmdir(root, recursive=true)
  @fs.mkdir(root, permission=0o755)
  let runtime_js_path = @fs.realpath(
    "fixtures/bridge_smoke/runtime/class-property.js",
  ) catch {
    _ => "fixtures/bridge_smoke/runtime/class-property.js"
  }
  let _ = emit_moonbit_bridge_package(
    "fixtures/bridge_smoke/class-property-reexport-entry.d.ts", runtime_js_path,
    root,
  )
  let bridge_mbt = @fs.read_file(wbtest_join_path(root, "bridge.mbt")).text() catch {
    e => {
      fail("Read error: \{e}")
      return
    }
  }
  let bridge_js = @fs.read_file(wbtest_join_path(root, "bridge.js")).text() catch {
    e => {
      fail("Read error: \{e}")
      return
    }
  }
  let bridge_js_path = "@tsmbt-bridge/" + wbtest_basename(root)
  assert_true(
    bridge_mbt.contains(
      "#module(\"\{bridge_js_path}\")\npub extern \"js\" fn new_runtime_state() -> RuntimeState = \"__ts_mbt_new_runtime_state\"",
    ),
  )
  assert_true(
    bridge_mbt.contains(
      "#module(\"\{bridge_js_path}\")\npub extern \"js\" fn get_runtime_state_version() -> String = \"__ts_mbt_get_runtime_state_version\"",
    ),
  )
  assert_true(
    bridge_mbt.contains(
      "#module(\"\{bridge_js_path}\")\npub extern \"js\" fn set_runtime_state_step(value : Double) -> Unit = \"__ts_mbt_set_runtime_state_step\"",
    ),
  )
  assert_true(
    bridge_js.contains("import { CounterState } from \"\{runtime_js_path}\";"),
  )
  assert_true(
    bridge_js.contains(
      "export function __ts_mbt_new_runtime_state() { return new CounterState(); }",
    ),
  )
  assert_true(
    bridge_js.contains(
      "export function __ts_mbt_get_runtime_state_version() { return CounterState.version; }",
    ),
  )
  let _ = try? @fs.rmdir(root, recursive=true)
}

///|
async test "emit_moonbit_bridge_package rewrites bare class-property alias reexport generated bindings to bridge.js" {
  let root = wbtest_tmp_project_benchmark_root(
    "bridge_package_class_property_reexport_bare",
  )
  let _ = try? @fs.rmdir(root, recursive=true)
  @fs.mkdir(root, permission=0o755)
  let _ = emit_moonbit_bridge_package(
    "fixtures/resolver/project/types/bare-class-property-entry.d.ts", "pkg-class-property",
    root,
  )
  let bridge_mbt = @fs.read_file(wbtest_join_path(root, "bridge.mbt")).text() catch {
    e => {
      fail("Read error: \{e}")
      return
    }
  }
  let bridge_js = @fs.read_file(wbtest_join_path(root, "bridge.js")).text() catch {
    e => {
      fail("Read error: \{e}")
      return
    }
  }
  let bridge_js_path = "@tsmbt-bridge/" + wbtest_basename(root)
  assert_true(
    bridge_mbt.contains(
      "#module(\"\{bridge_js_path}\")\npub extern \"js\" fn new_runtime_state() -> RuntimeState = \"__ts_mbt_new_runtime_state\"",
    ),
  )
  assert_true(
    bridge_mbt.contains(
      "#module(\"\{bridge_js_path}\")\npub extern \"js\" fn get_runtime_state_version() -> String = \"__ts_mbt_get_runtime_state_version\"",
    ),
  )
  assert_true(
    bridge_js.contains(
      "import * as __ts_mbt_module from \"pkg-class-property\";",
    ),
  )
  assert_true(
    bridge_js.contains("const CounterState = __ts_mbt_module.CounterState;"),
  )
  assert_true(
    bridge_js.contains(
      "export function __ts_mbt_new_runtime_state() { return new CounterState(); }",
    ),
  )
  let _ = try? @fs.rmdir(root, recursive=true)
}

///|
async test "emit_moonbit_bridge_package emits self-contained widened exports without mizchi/js" {
  let root = wbtest_tmp_project_benchmark_root("bridge_package_export_equals")
  let _ = try? @fs.rmdir(root, recursive=true)
  let _ = emit_moonbit_bridge_package(
    "fixtures/resolver/project/types/export-equals-entry.d.ts", "./runtime/export-equals.js",
    root,
  )
  let pkg_json = @fs.read_file(wbtest_join_path(root, "moon.pkg")).text() catch {
    e => {
      fail("Read error: \{e}")
      return
    }
  }
  let bridge_mbt = @fs.read_file(wbtest_join_path(root, "bridge.mbt")).text() catch {
    e => {
      fail("Read error: \{e}")
      return
    }
  }
  let bridge_js_path = "@tsmbt-bridge/" + wbtest_basename(root)
  // Self-contained bridge: no `mizchi/js` import in the package
  // descriptor; `JSValue` is declared inline.
  assert_false(pkg_json.contains("mizchi/js"))
  assert_true(bridge_mbt.contains("#external\npub type JSValue"))
  assert_true(
    bridge_mbt.contains(
      "#module(\"\{bridge_js_path}\")\npub extern \"js\" fn get_default() -> JSValue = \"__ts_mbt_get_default\"",
    ),
  )
  let _ = try? @fs.rmdir(root, recursive=true)
}

///|
async test "emit_moonbit_bridge_package rewrites parent-relative default function bridge to self-contained module path" {
  let root = wbtest_tmp_project_benchmark_root("bridge_package_parent_relative")
  let _ = try? @fs.rmdir(root, recursive=true)
  @fs.mkdir(root, permission=0o755)
  let pkg_root = wbtest_join_path(root, "pkg")
  let _ = emit_moonbit_bridge_package(
    "fixtures/bridge_smoke/default-function-entry.ts", "../runtime/default-function.js",
    pkg_root,
  )
  let bridge_mbt = @fs.read_file(wbtest_join_path(pkg_root, "bridge.mbt")).text() catch {
    e => {
      fail("Read error: \{e}")
      return
    }
  }
  let bridge_js = @fs.read_file(wbtest_join_path(pkg_root, "bridge.js")).text() catch {
    e => {
      fail("Read error: \{e}")
      return
    }
  }
  let bridge_js_path = "@tsmbt-bridge/" + wbtest_basename(pkg_root)
  assert_true(
    bridge_mbt.contains(
      "#module(\"\{bridge_js_path}\")\npub extern \"js\" fn default(label : String) -> String = \"__ts_mbt_default\"",
    ),
  )
  assert_true(
    bridge_js.contains(
      "export { default as __ts_mbt_default } from \"../runtime/default-function.js\";",
    ),
  )
  let _ = try? @fs.rmdir(root, recursive=true)
}

///|
async test "emit_moonbit_bridge_package rewrites bare default class alias reexport generated bindings to bridge.js" {
  let root = wbtest_tmp_project_benchmark_root(
    "bridge_package_default_class_reexport_bare",
  )
  let _ = try? @fs.rmdir(root, recursive=true)
  @fs.mkdir(root, permission=0o755)
  let _ = emit_moonbit_bridge_package(
    "fixtures/resolver/project/types/bare-default-class-entry.d.ts", "pkg-default-class",
    root,
  )
  let bridge_mbt = @fs.read_file(wbtest_join_path(root, "bridge.mbt")).text() catch {
    e => {
      fail("Read error: \{e}")
      return
    }
  }
  let bridge_js = @fs.read_file(wbtest_join_path(root, "bridge.js")).text() catch {
    e => {
      fail("Read error: \{e}")
      return
    }
  }
  let bridge_js_path = "@tsmbt-bridge/" + wbtest_basename(root)
  assert_true(
    bridge_mbt.contains(
      "#module(\"\{bridge_js_path}\")\npub extern \"js\" fn new_runtime_counter(initial : Double) -> RuntimeCounter = \"__ts_mbt_new_runtime_counter\"",
    ),
  )
  assert_true(
    bridge_mbt.contains(
      "#module(\"\{bridge_js_path}\")\npub extern \"js\" fn runtime_counter_from(seed : Double) -> RuntimeCounter = \"__ts_mbt_runtime_counter_from\"",
    ),
  )
  assert_true(bridge_js.contains("import default_ from \"pkg-default-class\";"))
  assert_true(
    bridge_js.contains(
      "export function __ts_mbt_new_runtime_counter(initial) { return new default_(initial); }",
    ),
  )
  let _ = try? @fs.rmdir(root, recursive=true)
}

///|
async test "emit_moonbit_bridge_package rewrites subpath class alias reexport generated bindings to bridge.js" {
  let root = wbtest_tmp_project_benchmark_root(
    "bridge_package_class_property_reexport_subpath",
  )
  let _ = try? @fs.rmdir(root, recursive=true)
  @fs.mkdir(root, permission=0o755)
  let _ = emit_moonbit_bridge_package(
    "fixtures/resolver/project/types/subpath-class-entry.d.ts", "pkg-class-subpath/state",
    root,
  )
  let bridge_mbt = @fs.read_file(wbtest_join_path(root, "bridge.mbt")).text() catch {
    e => {
      fail("Read error: \{e}")
      return
    }
  }
  let bridge_js = @fs.read_file(wbtest_join_path(root, "bridge.js")).text() catch {
    e => {
      fail("Read error: \{e}")
      return
    }
  }
  let bridge_js_path = "@tsmbt-bridge/" + wbtest_basename(root)
  assert_true(
    bridge_mbt.contains(
      "#module(\"\{bridge_js_path}\")\npub extern \"js\" fn new_runtime_state() -> RuntimeState = \"__ts_mbt_new_runtime_state\"",
    ),
  )
  assert_true(
    bridge_mbt.contains(
      "#module(\"\{bridge_js_path}\")\npub extern \"js\" fn get_runtime_state_version() -> String = \"__ts_mbt_get_runtime_state_version\"",
    ),
  )
  assert_true(
    bridge_js.contains(
      "import * as __ts_mbt_module from \"pkg-class-subpath/state\";",
    ),
  )
  assert_true(
    bridge_js.contains("const CounterState = __ts_mbt_module.CounterState;"),
  )
  let _ = try? @fs.rmdir(root, recursive=true)
}

///|
async test "emit_moonbit_bridge_package rewrites relative default class helpers to bridge.js" {
  let root = wbtest_tmp_project_benchmark_root("bridge_package_default_class")
  let _ = try? @fs.rmdir(root, recursive=true)
  let _ = emit_moonbit_bridge_package(
    "fixtures/bridge_smoke/default-class-entry.ts", "./runtime/default-class.js",
    root,
  )
  let bridge_mbt = @fs.read_file(wbtest_join_path(root, "bridge.mbt")).text() catch {
    e => {
      fail("Read error: \{e}")
      return
    }
  }
  let bridge_js = @fs.read_file(wbtest_join_path(root, "bridge.js")).text() catch {
    e => {
      fail("Read error: \{e}")
      return
    }
  }
  let bridge_js_path = "@tsmbt-bridge/" + wbtest_basename(root)
  assert_true(
    bridge_mbt.contains(
      "#module(\"\{bridge_js_path}\")\npub extern \"js\" fn new_default(initial : Double) -> Default = \"__ts_mbt_new_default\"",
    ),
  )
  assert_true(
    bridge_mbt.contains(
      "#module(\"\{bridge_js_path}\")\npub extern \"js\" fn default_from(seed : Double) -> Default = \"__ts_mbt_default_from\"",
    ),
  )
  assert_true(
    bridge_mbt.contains(
      "pub extern \"js\" fn Default::inc(self : Default, delta : Double) -> Double =",
    ),
  )
  assert_true(
    bridge_js.contains(
      "export function __ts_mbt_new_default(initial) { return new default_(initial); }",
    ),
  )
  assert_true(
    bridge_js.contains(
      "export function __ts_mbt_default_from(seed) { return default_.from(seed); }",
    ),
  )
  let _ = try? @fs.rmdir(root, recursive=true)
}

///|
async test "emit_moonbit_bridge_package rewrites deep parent-relative mixed default class bridge to self-contained module path" {
  let root = wbtest_tmp_project_benchmark_root(
    "bridge_package_default_class_mixed",
  )
  let _ = try? @fs.rmdir(root, recursive=true)
  @fs.mkdir(root, permission=0o755)
  let nested = wbtest_join_path(root, "nested")
  @fs.mkdir(nested, permission=0o755)
  let pkg_root = wbtest_join_path(nested, "pkg")
  let _ = emit_moonbit_bridge_package(
    "fixtures/bridge_smoke/default-class-mixed-entry.ts", "../../runtime/default-class-mixed.js",
    pkg_root,
  )
  let bridge_mbt = @fs.read_file(wbtest_join_path(pkg_root, "bridge.mbt")).text() catch {
    e => {
      fail("Read error: \{e}")
      return
    }
  }
  let bridge_js = @fs.read_file(wbtest_join_path(pkg_root, "bridge.js")).text() catch {
    e => {
      fail("Read error: \{e}")
      return
    }
  }
  let bridge_js_path = "@tsmbt-bridge/" + wbtest_basename(pkg_root)
  assert_true(
    bridge_mbt.contains(
      "#module(\"\{bridge_js_path}\")\npub extern \"js\" fn new_default(initial : Double) -> Default = \"__ts_mbt_new_default\"",
    ),
  )
  assert_true(
    bridge_mbt.contains(
      "#module(\"\{bridge_js_path}\")\npub extern \"js\" fn surround(label : String, prefix : String) -> String = \"__ts_mbt_surround\"",
    ),
  )
  assert_true(
    bridge_mbt.contains(
      "#module(\"\{bridge_js_path}\")\npub extern \"js\" fn get_version() -> String = \"__ts_mbt_get_version\"",
    ),
  )
  assert_true(
    bridge_js.contains(
      "import default_, { version } from \"../../runtime/default-class-mixed.js\";",
    ),
  )
  assert_true(
    bridge_js.contains(
      "export { surround as __ts_mbt_surround } from \"../../runtime/default-class-mixed.js\";",
    ),
  )
  let _ = try? @fs.rmdir(root, recursive=true)
}

///|
async test "emit_moonbit_bridge_package keeps aliased default reexports bound to original runtime exports" {
  let root = wbtest_tmp_project_benchmark_root(
    "bridge_package_default_class_mixed_reexport",
  )
  let _ = try? @fs.rmdir(root, recursive=true)
  @fs.mkdir(root, permission=0o755)
  let nested = wbtest_join_path(root, "nested")
  @fs.mkdir(nested, permission=0o755)
  let pkg_root = wbtest_join_path(nested, "pkg")
  let _ = emit_moonbit_bridge_package(
    "fixtures/bridge_smoke/default-class-mixed-reexport-entry.ts", "../../runtime/default-class-mixed.js",
    pkg_root,
  )
  let bridge_mbt = @fs.read_file(wbtest_join_path(pkg_root, "bridge.mbt")).text() catch {
    e => {
      fail("Read error: \{e}")
      return
    }
  }
  let bridge_js = @fs.read_file(wbtest_join_path(pkg_root, "bridge.js")).text() catch {
    e => {
      fail("Read error: \{e}")
      return
    }
  }
  let bridge_js_path = "@tsmbt-bridge/" + wbtest_basename(pkg_root)
  assert_true(
    bridge_mbt.contains(
      "#module(\"\{bridge_js_path}\")\npub extern \"js\" fn new_runtime_counter(initial : Double) -> RuntimeCounter = \"__ts_mbt_new_runtime_counter\"",
    ),
  )
  assert_true(
    bridge_mbt.contains(
      "#module(\"\{bridge_js_path}\")\npub extern \"js\" fn decorate(label : String, prefix : String) -> String = \"__ts_mbt_decorate\"",
    ),
  )
  assert_true(
    bridge_mbt.contains(
      "#module(\"\{bridge_js_path}\")\npub extern \"js\" fn get_runtime_version() -> String = \"__ts_mbt_get_runtime_version\"",
    ),
  )
  assert_true(
    bridge_js.contains(
      "import default_, { version } from \"../../runtime/default-class-mixed.js\";",
    ),
  )
  assert_true(
    bridge_js.contains(
      "export { surround as __ts_mbt_decorate } from \"../../runtime/default-class-mixed.js\";",
    ),
  )
  let _ = try? @fs.rmdir(root, recursive=true)
}

///|
async test "emit_moonbit_decl_text handles neverthrow-like package entry" {
  let actual = emit_moonbit_decl_text(
    "fixtures/resolver/project/types/neverthrow-like-entry.d.ts",
  ) catch {
    @bridge.ModuleGraphError::ReadError(msg)
    | @bridge.ModuleGraphError::ParseError(msg)
    | @bridge.ModuleGraphError::ResolveError(msg) => {
      fail("Emit error: \{msg}")
      return
    }
  }
  assert_true(actual.contains("declare pub type Result"))
  assert_true(actual.contains("declare pub type ResultAsync"))
  assert_true(
    actual.contains("declare pub fn parseUser(input : String) -> Result"),
  )
}

///|
async test "emit_moonbit_decl_text handles minimal opaque package entry" {
  let actual = emit_moonbit_decl_text(
    "fixtures/resolver/project/types/opaque-package-entry.d.ts",
  ) catch {
    @bridge.ModuleGraphError::ReadError(msg)
    | @bridge.ModuleGraphError::ParseError(msg)
    | @bridge.ModuleGraphError::ResolveError(msg) => {
      fail("Emit error: \{msg}")
      return
    }
  }
  assert_true(actual.contains("declare pub type PkgTypesValue"))
  assert_true(
    actual.contains(
      "declare pub fn parseValue(input : String) -> PkgTypesValue",
    ),
  )
}

///|
async test "emit_moonbit_decl_text handles runtime ts exported functions" {
  let actual = emit_moonbit_decl_text(
    "fixtures/resolver/project/types/runtime-function-entry.ts",
  ) catch {
    @bridge.ModuleGraphError::ReadError(msg)
    | @bridge.ModuleGraphError::ParseError(msg)
    | @bridge.ModuleGraphError::ResolveError(msg) => {
      fail("Emit error: \{msg}")
      return
    }
  }
  assert_true(actual.contains("declare pub type RuntimePoint"))
  assert_true(
    actual.contains(
      "declare pub fn scalePoint(point : RuntimePoint, factor : Double) -> RuntimePoint",
    ),
  )
}

///|
async test "emit_moonbit_decl_text handles runtime tsx exported functions" {
  let actual = emit_moonbit_decl_text(
    "fixtures/resolver/project/types/runtime-component-entry.tsx",
  ) catch {
    @bridge.ModuleGraphError::ReadError(msg)
    | @bridge.ModuleGraphError::ParseError(msg)
    | @bridge.ModuleGraphError::ResolveError(msg) => {
      fail("Emit error: \{msg}")
      return
    }
  }
  assert_true(actual.contains("declare pub type BadgeProps"))
  assert_true(
    actual.contains(
      "declare pub fn renderBadge(props : BadgeProps) -> JSX_Element",
    ),
  )
}

///|
async test "emit_moonbit_decl_text handles runtime ts exported const arrow functions" {
  let actual = emit_moonbit_decl_text(
    "fixtures/resolver/project/types/runtime-arrow-entry.ts",
  ) catch {
    @bridge.ModuleGraphError::ReadError(msg)
    | @bridge.ModuleGraphError::ParseError(msg)
    | @bridge.ModuleGraphError::ResolveError(msg) => {
      fail("Emit error: \{msg}")
      return
    }
  }
  assert_true(actual.contains("declare pub type RuntimeArrowPoint"))
  assert_true(
    actual.contains(
      "declare pub fn scaleArrowPoint(point : RuntimeArrowPoint, factor : Double) -> RuntimeArrowPoint",
    ),
  )
}

///|
async test "emit_moonbit_decl_text handles runtime ts exported untyped const arrow functions" {
  let actual = emit_moonbit_decl_text(
    "fixtures/resolver/project/types/runtime-untyped-arrow-entry.ts",
  ) catch {
    @bridge.ModuleGraphError::ReadError(msg)
    | @bridge.ModuleGraphError::ParseError(msg)
    | @bridge.ModuleGraphError::ResolveError(msg) => {
      fail("Emit error: \{msg}")
      return
    }
  }
  assert_true(
    actual.contains("declare pub fn doubleValue(value : Double) -> Double"),
  )
  assert_true(
    actual.contains("declare pub fn greetValue(name : String) -> String"),
  )
}

///|
async test "emit_moonbit_decl_text handles runtime ts function reexports" {
  let actual = emit_moonbit_decl_text(
    "fixtures/resolver/project/types/runtime-function-reexport-entry.ts",
  ) catch {
    @bridge.ModuleGraphError::ReadError(msg)
    | @bridge.ModuleGraphError::ParseError(msg)
    | @bridge.ModuleGraphError::ResolveError(msg) => {
      fail("Emit error: \{msg}")
      return
    }
  }
  assert_true(
    actual.contains(
      "declare pub fn scalePoint(point : RuntimePoint, factor : Double) -> RuntimePoint",
    ),
  )
}

///|
async test "emit_moonbit_decl_text handles runtime ts imported class exports" {
  let actual = emit_moonbit_decl_text(
    "fixtures/resolver/project/types/runtime-import-reexport-class-entry.ts",
  ) catch {
    @bridge.ModuleGraphError::ReadError(msg)
    | @bridge.ModuleGraphError::ParseError(msg)
    | @bridge.ModuleGraphError::ResolveError(msg) => {
      fail("Emit error: \{msg}")
      return
    }
  }
  assert_true(actual.contains("declare pub type RuntimeImported"))
  assert_true(
    actual.contains(
      "declare pub fn new_runtime_imported(_options : RuntimeImportedOptions) -> RuntimeImported",
    ),
  )
}

///|
async test "emit_moonbit_scaffold_from_ts handles runtime ts imported class exports" {
  let root = wbtest_tmp_project_benchmark_root(
    "bridge_scaffold_runtime_import_reexport_class",
  )
  let _ = try? @fs.rmdir(root, recursive=true)
  @fs.mkdir(root, permission=0o755)
  let _ = emit_moonbit_scaffold_from_ts(
    "fixtures/resolver/project/types/runtime-import-reexport-class-entry.ts", "./runtime/runtime-import-reexport-class.js",
    root,
  )
  let bridge_mbti = @fs.read_file(wbtest_join_path(root, "bridge.mbti")).text() catch {
    e => fail("failed to read runtime-import-reexport-class bridge.mbti: \{e}")
  }
  assert_true(bridge_mbti.contains("declare pub type RuntimeImported"))
  assert_true(
    bridge_mbti.contains(
      "declare pub fn new_runtime_imported(_options : RuntimeImportedOptions) -> RuntimeImported",
    ),
  )
}

///|
async test "emit_moonbit_decl_text handles runtime ts imported class barrel exports" {
  let actual = emit_moonbit_decl_text(
    "fixtures/resolver/project/types/runtime-import-reexport-class-barrel-entry.ts",
  ) catch {
    @bridge.ModuleGraphError::ReadError(msg)
    | @bridge.ModuleGraphError::ParseError(msg)
    | @bridge.ModuleGraphError::ResolveError(msg) => {
      fail("Emit error: \{msg}")
      return
    }
  }
  assert_true(actual.contains("declare pub type RuntimeImported"))
  assert_true(
    actual.contains(
      "declare pub fn new_runtime_imported(_options : RuntimeImportedOptions) -> RuntimeImported",
    ),
  )
}

///|
async test "emit_moonbit_scaffold_from_ts handles semicolonless runtime ts imported class barrel exports" {
  let root = wbtest_tmp_project_benchmark_root(
    "bridge_scaffold_runtime_import_reexport_class_barrel",
  )
  let _ = try? @fs.rmdir(root, recursive=true)
  @fs.mkdir(root, permission=0o755)
  let _ = emit_moonbit_scaffold_from_ts(
    "fixtures/resolver/project/types/runtime-import-reexport-class-barrel-entry.ts",
    "./runtime/runtime-import-reexport-class.js", root,
  )
  let bridge_mbti = @fs.read_file(wbtest_join_path(root, "bridge.mbti")).text() catch {
    e =>
      fail(
        "failed to read semicolonless runtime-import-reexport-class bridge.mbti: \{e}",
      )
  }
  assert_true(bridge_mbti.contains("declare pub type RuntimeImported"))
  assert_true(
    bridge_mbti.contains(
      "declare pub fn new_runtime_imported(_options : RuntimeImportedOptions) -> RuntimeImported",
    ),
  )
}

///|
async test "emit_moonbit_decl_text handles semicolonless runtime export type alias entry" {
  let actual = emit_moonbit_decl_text(
    "fixtures/resolver/project/types/runtime-semicolonless-export-type-alias-entry.ts",
  ) catch {
    @bridge.ModuleGraphError::ReadError(msg)
    | @bridge.ModuleGraphError::ParseError(msg)
    | @bridge.ModuleGraphError::ResolveError(msg) => {
      fail("Emit error: \{msg}")
      return
    }
  }
  assert_true(actual.contains("declare pub fn greet(name : Name) -> Name"))
}

///|
async test "emit_moonbit_scaffold_from_ts handles semicolonless runtime export type alias entry" {
  let root = wbtest_tmp_project_benchmark_root(
    "bridge_scaffold_runtime_semicolonless_export_type_alias",
  )
  let _ = try? @fs.rmdir(root, recursive=true)
  @fs.mkdir(root, permission=0o755)
  let _ = emit_moonbit_scaffold_from_ts(
    "fixtures/resolver/project/types/runtime-semicolonless-export-type-alias-entry.ts",
    "./runtime/runtime-semicolonless-export-type-alias.js", root,
  )
  let bridge_mbti = @fs.read_file(wbtest_join_path(root, "bridge.mbti")).text() catch {
    e =>
      fail(
        "failed to read runtime-semicolonless-export-type-alias bridge.mbti: \{e}",
      )
  }
  assert_true(bridge_mbti.contains("declare pub fn greet(name : Name) -> Name"))
}

///|
async test "emit_moonbit_decl_text handles runtime ts destructured value exports" {
  let actual = emit_moonbit_decl_text(
    "fixtures/resolver/project/types/runtime-destructured-value-entry.ts",
  ) catch {
    @bridge.ModuleGraphError::ReadError(msg)
    | @bridge.ModuleGraphError::ParseError(msg)
    | @bridge.ModuleGraphError::ResolveError(msg) => {
      fail("Emit error: \{msg}")
      return
    }
  }
  assert_true(actual.contains("declare pub fn get_runtime_version() -> String"))
  assert_true(actual.contains("declare pub fn get_build() -> Double"))
}

///|
async test "emit_moonbit_decl_text handles nested and array-rest destructured value exports" {
  let actual = emit_moonbit_decl_text(
    "fixtures/resolver/project/types/runtime-destructured-nested-rest-value-entry.ts",
  ) catch {
    @bridge.ModuleGraphError::ReadError(msg)
    | @bridge.ModuleGraphError::ParseError(msg)
    | @bridge.ModuleGraphError::ResolveError(msg) => {
      fail("Emit error: \{msg}")
      return
    }
  }
  assert_true(actual.contains("declare pub fn get_runtime_version() -> String"))
  assert_true(actual.contains("declare pub fn get_build() -> Double"))
  assert_true(actual.contains("declare pub fn get_head() -> Double"))
  assert_true(actual.contains("declare pub fn get_tail() -> Array[Double]"))
}

///|
async test "emit_moonbit_decl_text handles object-rest destructured value exports" {
  let actual = emit_moonbit_decl_text(
    "fixtures/resolver/project/types/runtime-object-rest-value-entry.ts",
  ) catch {
    @bridge.ModuleGraphError::ReadError(msg)
    | @bridge.ModuleGraphError::ParseError(msg)
    | @bridge.ModuleGraphError::ResolveError(msg) => {
      fail("Emit error: \{msg}")
      return
    }
  }
  assert_true(actual.contains("declare pub type RestMeta"))
  assert_true(actual.contains("declare pub fn get_version() -> String"))
  assert_true(actual.contains("declare pub fn get_rest_meta() -> RestMeta"))
}

///|
async test "emit_moonbit_decl_text handles computed-key destructured value exports" {
  let actual = emit_moonbit_decl_text(
    "fixtures/resolver/project/types/runtime-computed-destructured-value-entry.ts",
  ) catch {
    @bridge.ModuleGraphError::ReadError(msg)
    | @bridge.ModuleGraphError::ParseError(msg)
    | @bridge.ModuleGraphError::ResolveError(msg) => {
      fail("Emit error: \{msg}")
      return
    }
  }
  assert_true(actual.contains("declare pub type RestMeta"))
  assert_true(actual.contains("declare pub fn get_runtime_version() -> String"))
  assert_true(actual.contains("declare pub fn get_build() -> Double"))
  assert_true(actual.contains("declare pub fn get_rest_meta() -> RestMeta"))
}

///|
async test "emit_moonbit_decl_text handles template-literal computed-key destructured value exports" {
  let actual = emit_moonbit_decl_text(
    "fixtures/resolver/project/types/runtime-template-computed-destructured-value-entry.ts",
  ) catch {
    @bridge.ModuleGraphError::ReadError(msg)
    | @bridge.ModuleGraphError::ParseError(msg)
    | @bridge.ModuleGraphError::ResolveError(msg) => {
      fail("Emit error: \{msg}")
      return
    }
  }
  assert_true(actual.contains("declare pub type RestMeta"))
  assert_true(actual.contains("declare pub fn get_runtime_version() -> String"))
  assert_true(actual.contains("declare pub fn get_build() -> Double"))
  assert_true(actual.contains("declare pub fn get_rest_meta() -> RestMeta"))
}

///|
async test "emit_moonbit_decl_text handles concatenated computed-key destructured value exports" {
  let actual = emit_moonbit_decl_text(
    "fixtures/resolver/project/types/runtime-concat-computed-destructured-value-entry.ts",
  ) catch {
    @bridge.ModuleGraphError::ReadError(msg)
    | @bridge.ModuleGraphError::ParseError(msg)
    | @bridge.ModuleGraphError::ResolveError(msg) => {
      fail("Emit error: \{msg}")
      return
    }
  }
  assert_true(actual.contains("declare pub type RestMeta"))
  assert_true(actual.contains("declare pub fn get_runtime_version() -> String"))
  assert_true(actual.contains("declare pub fn get_build() -> Double"))
  assert_true(actual.contains("declare pub fn get_rest_meta() -> RestMeta"))
}

///|
async test "emit_moonbit_decl_text handles primitive-literal computed-key destructured value exports" {
  let actual = emit_moonbit_decl_text(
    "fixtures/resolver/project/types/runtime-primitive-computed-destructured-value-entry.ts",
  ) catch {
    @bridge.ModuleGraphError::ReadError(msg)
    | @bridge.ModuleGraphError::ParseError(msg)
    | @bridge.ModuleGraphError::ResolveError(msg) => {
      fail("Emit error: \{msg}")
      return
    }
  }
  assert_true(actual.contains("declare pub type RestMeta"))
  assert_true(actual.contains("declare pub fn get_truthy() -> String"))
  assert_true(actual.contains("declare pub fn get_nil_value() -> Double"))
  assert_true(actual.contains("declare pub fn get_negative() -> Bool"))
  assert_true(actual.contains("declare pub fn get_bigint_value() -> String"))
  assert_true(actual.contains("declare pub fn get_rest_meta() -> RestMeta"))
}

///|
async test "emit_moonbit_decl_text handles void-and-negative-bigint computed-key destructured value exports" {
  let actual = emit_moonbit_decl_text(
    "fixtures/resolver/project/types/runtime-void-bigint-computed-destructured-value-entry.ts",
  ) catch {
    @bridge.ModuleGraphError::ReadError(msg)
    | @bridge.ModuleGraphError::ParseError(msg)
    | @bridge.ModuleGraphError::ResolveError(msg) => {
      fail("Emit error: \{msg}")
      return
    }
  }
  assert_true(actual.contains("declare pub type RestMeta"))
  assert_true(actual.contains("declare pub fn get_undefined_value() -> String"))
  assert_true(actual.contains("declare pub fn get_negative_bigint() -> Double"))
  assert_true(actual.contains("declare pub fn get_rest_meta() -> RestMeta"))
}

///|
async test "emit_moonbit_decl_text handles const-reference computed-key destructured value exports" {
  let actual = emit_moonbit_decl_text(
    "fixtures/resolver/project/types/runtime-const-ref-computed-destructured-value-entry.ts",
  ) catch {
    @bridge.ModuleGraphError::ReadError(msg)
    | @bridge.ModuleGraphError::ParseError(msg)
    | @bridge.ModuleGraphError::ResolveError(msg) => {
      fail("Emit error: \{msg}")
      return
    }
  }
  assert_true(actual.contains("declare pub type RestMeta"))
  assert_true(actual.contains("declare pub fn get_runtime_version() -> String"))
  assert_true(actual.contains("declare pub fn get_build() -> Double"))
  assert_true(actual.contains("declare pub fn get_rest_meta() -> RestMeta"))
}

///|
async test "emit_moonbit_decl_text handles destructured-const-reference computed-key value exports" {
  let actual = emit_moonbit_decl_text(
    "fixtures/resolver/project/types/runtime-destructured-const-ref-computed-destructured-value-entry.ts",
  ) catch {
    @bridge.ModuleGraphError::ReadError(msg)
    | @bridge.ModuleGraphError::ParseError(msg)
    | @bridge.ModuleGraphError::ResolveError(msg) => {
      fail("Emit error: \{msg}")
      return
    }
  }
  assert_true(actual.contains("declare pub type RestMeta"))
  assert_true(actual.contains("declare pub fn get_runtime_version() -> String"))
  assert_true(actual.contains("declare pub fn get_build() -> Double"))
  assert_true(actual.contains("declare pub fn get_rest_meta() -> RestMeta"))
}

///|
async test "emit_moonbit_decl_text handles const-object-access computed-key value exports" {
  let actual = emit_moonbit_decl_text(
    "fixtures/resolver/project/types/runtime-const-object-access-computed-destructured-value-entry.ts",
  ) catch {
    @bridge.ModuleGraphError::ReadError(msg)
    | @bridge.ModuleGraphError::ParseError(msg)
    | @bridge.ModuleGraphError::ResolveError(msg) => {
      fail("Emit error: \{msg}")
      return
    }
  }
  assert_true(actual.contains("declare pub type RestMeta"))
  assert_true(actual.contains("declare pub fn get_runtime_version() -> String"))
  assert_true(actual.contains("declare pub fn get_build() -> Double"))
  assert_true(actual.contains("declare pub fn get_rest_meta() -> RestMeta"))
}

///|
async test "emit_moonbit_decl_text handles nested-const-object-access computed-key value exports" {
  let actual = emit_moonbit_decl_text(
    "fixtures/resolver/project/types/runtime-nested-const-object-access-computed-destructured-value-entry.ts",
  ) catch {
    @bridge.ModuleGraphError::ReadError(msg)
    | @bridge.ModuleGraphError::ParseError(msg)
    | @bridge.ModuleGraphError::ResolveError(msg) => {
      fail("Emit error: \{msg}")
      return
    }
  }
  assert_true(actual.contains("declare pub type RestMeta"))
  assert_true(actual.contains("declare pub fn get_runtime_version() -> String"))
  assert_true(actual.contains("declare pub fn get_build() -> Double"))
  assert_true(actual.contains("declare pub fn get_rest_meta() -> RestMeta"))
}

///|
async test "emit_moonbit_decl_text handles const-array-access computed-key value exports" {
  let actual = emit_moonbit_decl_text(
    "fixtures/resolver/project/types/runtime-const-array-access-computed-destructured-value-entry.ts",
  ) catch {
    @bridge.ModuleGraphError::ReadError(msg)
    | @bridge.ModuleGraphError::ParseError(msg)
    | @bridge.ModuleGraphError::ResolveError(msg) => {
      fail("Emit error: \{msg}")
      return
    }
  }
  assert_true(actual.contains("declare pub type RestMeta"))
  assert_true(actual.contains("declare pub fn get_runtime_version() -> String"))
  assert_true(actual.contains("declare pub fn get_build() -> Double"))
  assert_true(actual.contains("declare pub fn get_rest_meta() -> RestMeta"))
}

///|
async test "emit_moonbit_decl_text handles nested-const-array-access computed-key value exports" {
  let actual = emit_moonbit_decl_text(
    "fixtures/resolver/project/types/runtime-nested-const-array-access-computed-destructured-value-entry.ts",
  ) catch {
    @bridge.ModuleGraphError::ReadError(msg)
    | @bridge.ModuleGraphError::ParseError(msg)
    | @bridge.ModuleGraphError::ResolveError(msg) => {
      fail("Emit error: \{msg}")
      return
    }
  }
  assert_true(actual.contains("declare pub type RestMeta"))
  assert_true(actual.contains("declare pub fn get_runtime_version() -> String"))
  assert_true(actual.contains("declare pub fn get_build() -> Double"))
  assert_true(actual.contains("declare pub fn get_rest_meta() -> RestMeta"))
}

///|
async test "emit_moonbit_decl_text handles const-index-alias computed-key value exports" {
  let actual = emit_moonbit_decl_text(
    "fixtures/resolver/project/types/runtime-const-index-alias-computed-destructured-value-entry.ts",
  ) catch {
    @bridge.ModuleGraphError::ReadError(msg)
    | @bridge.ModuleGraphError::ParseError(msg)
    | @bridge.ModuleGraphError::ResolveError(msg) => {
      fail("Emit error: \{msg}")
      return
    }
  }
  assert_true(actual.contains("declare pub type RestMeta"))
  assert_true(actual.contains("declare pub fn get_runtime_version() -> String"))
  assert_true(actual.contains("declare pub fn get_build() -> Double"))
  assert_true(actual.contains("declare pub fn get_rest_meta() -> RestMeta"))
}

///|
async test "emit_moonbit_decl_text handles const-index-table computed-key value exports" {
  let actual = emit_moonbit_decl_text(
    "fixtures/resolver/project/types/runtime-const-index-table-computed-destructured-value-entry.ts",
  ) catch {
    @bridge.ModuleGraphError::ReadError(msg)
    | @bridge.ModuleGraphError::ParseError(msg)
    | @bridge.ModuleGraphError::ResolveError(msg) => {
      fail("Emit error: \{msg}")
      return
    }
  }
  assert_true(actual.contains("declare pub type RestMeta"))
  assert_true(actual.contains("declare pub fn get_runtime_version() -> String"))
  assert_true(actual.contains("declare pub fn get_build() -> Double"))
  assert_true(actual.contains("declare pub fn get_rest_meta() -> RestMeta"))
}

///|
async test "emit_moonbit_decl_text handles nested-index-table computed-key value exports" {
  let actual = emit_moonbit_decl_text(
    "fixtures/resolver/project/types/runtime-nested-index-table-computed-destructured-value-entry.ts",
  ) catch {
    @bridge.ModuleGraphError::ReadError(msg)
    | @bridge.ModuleGraphError::ParseError(msg)
    | @bridge.ModuleGraphError::ResolveError(msg) => {
      fail("Emit error: \{msg}")
      return
    }
  }
  assert_true(actual.contains("declare pub type RestMeta"))
  assert_true(actual.contains("declare pub fn get_runtime_version() -> String"))
  assert_true(actual.contains("declare pub fn get_build() -> Double"))
  assert_true(actual.contains("declare pub fn get_rest_meta() -> RestMeta"))
}

///|
async test "emit_moonbit_decl_text handles imported const-table computed-key value exports" {
  let actual = emit_moonbit_decl_text(
    "fixtures/resolver/project/types/runtime-imported-const-table-entry.ts",
  ) catch {
    @bridge.ModuleGraphError::ReadError(msg)
    | @bridge.ModuleGraphError::ParseError(msg)
    | @bridge.ModuleGraphError::ResolveError(msg) => {
      fail("Emit error: \{msg}")
      return
    }
  }
  assert_true(actual.contains("declare pub type RestMeta"))
  assert_true(actual.contains("declare pub fn get_runtime_version() -> String"))
  assert_true(actual.contains("declare pub fn get_build() -> Double"))
  assert_true(actual.contains("declare pub fn get_rest_meta() -> RestMeta"))
}

///|
async test "emit_moonbit_decl_text handles imported namespace const-table computed-key value exports" {
  let actual = emit_moonbit_decl_text(
    "fixtures/resolver/project/types/runtime-imported-namespace-const-table-entry.ts",
  ) catch {
    @bridge.ModuleGraphError::ReadError(msg)
    | @bridge.ModuleGraphError::ParseError(msg)
    | @bridge.ModuleGraphError::ResolveError(msg) => {
      fail("Emit error: \{msg}")
      return
    }
  }
  assert_true(actual.contains("declare pub type RestMeta"))
  assert_true(actual.contains("declare pub fn get_runtime_version() -> String"))
  assert_true(actual.contains("declare pub fn get_build() -> Double"))
  assert_true(actual.contains("declare pub fn get_rest_meta() -> RestMeta"))
}

///|
async test "emit_moonbit_decl_text handles imported default const-table computed-key value exports" {
  let actual = emit_moonbit_decl_text(
    "fixtures/resolver/project/types/runtime-imported-default-const-table-entry.ts",
  ) catch {
    @bridge.ModuleGraphError::ReadError(msg)
    | @bridge.ModuleGraphError::ParseError(msg)
    | @bridge.ModuleGraphError::ResolveError(msg) => {
      fail("Emit error: \{msg}")
      return
    }
  }
  assert_true(actual.contains("declare pub type RestMeta"))
  assert_true(actual.contains("declare pub fn get_runtime_version() -> String"))
  assert_true(actual.contains("declare pub fn get_build() -> Double"))
  assert_true(actual.contains("declare pub fn get_rest_meta() -> RestMeta"))
}

///|
async test "emit_moonbit_decl_text handles imported inline default const-table computed-key value exports" {
  let actual = emit_moonbit_decl_text(
    "fixtures/resolver/project/types/runtime-imported-inline-default-const-table-entry.ts",
  ) catch {
    @bridge.ModuleGraphError::ReadError(msg)
    | @bridge.ModuleGraphError::ParseError(msg)
    | @bridge.ModuleGraphError::ResolveError(msg) => {
      fail("Emit error: \{msg}")
      return
    }
  }
  assert_true(actual.contains("declare pub type RestMeta"))
  assert_true(actual.contains("declare pub fn get_runtime_version() -> String"))
  assert_true(actual.contains("declare pub fn get_build() -> Double"))
  assert_true(actual.contains("declare pub fn get_rest_meta() -> RestMeta"))
}

///|
async test "emit_moonbit_decl_text handles imported inline default const-table as const computed-key value exports" {
  let actual = emit_moonbit_decl_text(
    "fixtures/resolver/project/types/runtime-imported-inline-default-const-table-as-const-entry.ts",
  ) catch {
    @bridge.ModuleGraphError::ReadError(msg)
    | @bridge.ModuleGraphError::ParseError(msg)
    | @bridge.ModuleGraphError::ResolveError(msg) => {
      fail("Emit error: \{msg}")
      return
    }
  }
  assert_true(actual.contains("declare pub type RestMeta"))
  assert_true(actual.contains("declare pub fn get_runtime_version() -> String"))
  assert_true(actual.contains("declare pub fn get_build() -> Double"))
  assert_true(actual.contains("declare pub fn get_rest_meta() -> RestMeta"))
}

///|
async test "emit_moonbit_decl_text handles imported iife default const-table computed-key value exports" {
  let actual = emit_moonbit_decl_text(
    "fixtures/resolver/project/types/runtime-imported-iife-default-const-table-entry.ts",
  ) catch {
    @bridge.ModuleGraphError::ReadError(msg)
    | @bridge.ModuleGraphError::ParseError(msg)
    | @bridge.ModuleGraphError::ResolveError(msg) => {
      fail("Emit error: \{msg}")
      return
    }
  }
  assert_true(actual.contains("declare pub type RestMeta"))
  assert_true(actual.contains("declare pub fn get_runtime_version() -> String"))
  assert_true(actual.contains("declare pub fn get_build() -> Double"))
  assert_true(actual.contains("declare pub fn get_rest_meta() -> RestMeta"))
}

///|
async test "emit_moonbit_decl_text handles imported iife local const-table computed-key value exports" {
  let actual = emit_moonbit_decl_text(
    "fixtures/resolver/project/types/runtime-imported-iife-local-const-table-entry.ts",
  ) catch {
    @bridge.ModuleGraphError::ReadError(msg)
    | @bridge.ModuleGraphError::ParseError(msg)
    | @bridge.ModuleGraphError::ResolveError(msg) => {
      fail("Emit error: \{msg}")
      return
    }
  }
  assert_true(actual.contains("declare pub type RestMeta"))
  assert_true(actual.contains("declare pub fn get_runtime_version() -> String"))
  assert_true(actual.contains("declare pub fn get_build() -> Double"))
  assert_true(actual.contains("declare pub fn get_rest_meta() -> RestMeta"))
}

///|
async test "emit_moonbit_decl_text handles imported function iife local const-table computed-key value exports" {
  let actual = emit_moonbit_decl_text(
    "fixtures/resolver/project/types/runtime-imported-function-iife-local-const-table-entry.ts",
  ) catch {
    @bridge.ModuleGraphError::ReadError(msg)
    | @bridge.ModuleGraphError::ParseError(msg)
    | @bridge.ModuleGraphError::ResolveError(msg) => {
      fail("Emit error: \{msg}")
      return
    }
  }
  assert_true(actual.contains("declare pub type RestMeta"))
  assert_true(actual.contains("declare pub fn get_runtime_version() -> String"))
  assert_true(actual.contains("declare pub fn get_build() -> Double"))
  assert_true(actual.contains("declare pub fn get_rest_meta() -> RestMeta"))
}

///|
async test "emit_moonbit_decl_text handles imported iife local let-table computed-key value exports" {
  let actual = emit_moonbit_decl_text(
    "fixtures/resolver/project/types/runtime-imported-iife-local-let-table-entry.ts",
  ) catch {
    @bridge.ModuleGraphError::ReadError(msg)
    | @bridge.ModuleGraphError::ParseError(msg)
    | @bridge.ModuleGraphError::ResolveError(msg) => {
      fail("Emit error: \{msg}")
      return
    }
  }
  assert_true(actual.contains("declare pub type RestMeta"))
  assert_true(actual.contains("declare pub fn get_runtime_version() -> String"))
  assert_true(actual.contains("declare pub fn get_build() -> Double"))
  assert_true(actual.contains("declare pub fn get_rest_meta() -> RestMeta"))
}

///|
async test "emit_moonbit_decl_text handles imported function iife local let-table computed-key value exports" {
  let actual = emit_moonbit_decl_text(
    "fixtures/resolver/project/types/runtime-imported-function-iife-local-let-table-entry.ts",
  ) catch {
    @bridge.ModuleGraphError::ReadError(msg)
    | @bridge.ModuleGraphError::ParseError(msg)
    | @bridge.ModuleGraphError::ResolveError(msg) => {
      fail("Emit error: \{msg}")
      return
    }
  }
  assert_true(actual.contains("declare pub type RestMeta"))
  assert_true(actual.contains("declare pub fn get_runtime_version() -> String"))
  assert_true(actual.contains("declare pub fn get_build() -> Double"))
  assert_true(actual.contains("declare pub fn get_rest_meta() -> RestMeta"))
}

///|
async test "emit_moonbit_decl_text widens imported reassigned local let-table computed-key value exports" {
  let actual = emit_moonbit_decl_text(
    "fixtures/resolver/project/types/runtime-imported-iife-reassigned-let-table-entry.ts",
  ) catch {
    @bridge.ModuleGraphError::ReadError(msg)
    | @bridge.ModuleGraphError::ParseError(msg)
    | @bridge.ModuleGraphError::ResolveError(msg) => {
      fail("Emit error: \{msg}")
      return
    }
  }
  assert_false(actual.contains("declare pub type RestMeta"))
  assert_true(
    actual.contains("declare pub fn get_runtime_version() -> JSValue"),
  )
  assert_true(actual.contains("declare pub fn get_build() -> JSValue"))
  assert_true(actual.contains("declare pub fn get_rest_meta() -> JSValue"))
}

///|
async test "emit_moonbit_decl_text widens imported prop-mutated local let-table computed-key value exports" {
  let actual = emit_moonbit_decl_text(
    "fixtures/resolver/project/types/runtime-imported-iife-prop-mutated-let-table-entry.ts",
  ) catch {
    @bridge.ModuleGraphError::ReadError(msg)
    | @bridge.ModuleGraphError::ParseError(msg)
    | @bridge.ModuleGraphError::ResolveError(msg) => {
      fail("Emit error: \{msg}")
      return
    }
  }
  assert_false(actual.contains("declare pub type RestMeta"))
  assert_true(
    actual.contains("declare pub fn get_runtime_version() -> JSValue"),
  )
  assert_true(actual.contains("declare pub fn get_build() -> JSValue"))
  assert_true(actual.contains("declare pub fn get_rest_meta() -> JSValue"))
}

///|
async test "emit_moonbit_decl_text widens imported index-mutated local let-table computed-key value exports" {
  let actual = emit_moonbit_decl_text(
    "fixtures/resolver/project/types/runtime-imported-function-iife-index-mutated-let-table-entry.ts",
  ) catch {
    @bridge.ModuleGraphError::ReadError(msg)
    | @bridge.ModuleGraphError::ParseError(msg)
    | @bridge.ModuleGraphError::ResolveError(msg) => {
      fail("Emit error: \{msg}")
      return
    }
  }
  assert_false(actual.contains("declare pub type RestMeta"))
  assert_true(
    actual.contains("declare pub fn get_runtime_version() -> JSValue"),
  )
  assert_true(actual.contains("declare pub fn get_build() -> JSValue"))
  assert_true(actual.contains("declare pub fn get_rest_meta() -> JSValue"))
}

///|
async test "emit_moonbit_decl_text handles imported reexported const-table computed-key value exports" {
  let actual = emit_moonbit_decl_text(
    "fixtures/resolver/project/types/runtime-imported-reexported-const-table-entry.ts",
  ) catch {
    @bridge.ModuleGraphError::ReadError(msg)
    | @bridge.ModuleGraphError::ParseError(msg)
    | @bridge.ModuleGraphError::ResolveError(msg) => {
      fail("Emit error: \{msg}")
      return
    }
  }
  assert_true(actual.contains("declare pub type RestMeta"))
  assert_true(actual.contains("declare pub fn get_runtime_version() -> String"))
  assert_true(actual.contains("declare pub fn get_build() -> Double"))
  assert_true(actual.contains("declare pub fn get_rest_meta() -> RestMeta"))
}

///|
async test "emit_moonbit_decl_text handles imported chained const-table computed-key value exports" {
  let actual = emit_moonbit_decl_text(
    "fixtures/resolver/project/types/runtime-imported-chained-const-table-entry.ts",
  ) catch {
    @bridge.ModuleGraphError::ReadError(msg)
    | @bridge.ModuleGraphError::ParseError(msg)
    | @bridge.ModuleGraphError::ResolveError(msg) => {
      fail("Emit error: \{msg}")
      return
    }
  }
  assert_true(actual.contains("declare pub type RestMeta"))
  assert_true(actual.contains("declare pub fn get_runtime_version() -> String"))
  assert_true(actual.contains("declare pub fn get_build() -> Double"))
  assert_true(actual.contains("declare pub fn get_rest_meta() -> RestMeta"))
}

///|
async test "emit_moonbit_decl_text handles imported star const-table computed-key value exports" {
  let actual = emit_moonbit_decl_text(
    "fixtures/resolver/project/types/runtime-imported-star-const-table-entry.ts",
  ) catch {
    @bridge.ModuleGraphError::ReadError(msg)
    | @bridge.ModuleGraphError::ParseError(msg)
    | @bridge.ModuleGraphError::ResolveError(msg) => {
      fail("Emit error: \{msg}")
      return
    }
  }
  assert_true(actual.contains("declare pub type RestMeta"))
  assert_true(actual.contains("declare pub fn get_runtime_version() -> String"))
  assert_true(actual.contains("declare pub fn get_build() -> Double"))
  assert_true(actual.contains("declare pub fn get_rest_meta() -> RestMeta"))
}

///|
async test "emit_moonbit_decl_text handles imported deep star const-table computed-key value exports" {
  let actual = emit_moonbit_decl_text(
    "fixtures/resolver/project/types/runtime-imported-deep-star-const-table-entry.ts",
  ) catch {
    @bridge.ModuleGraphError::ReadError(msg)
    | @bridge.ModuleGraphError::ParseError(msg)
    | @bridge.ModuleGraphError::ResolveError(msg) => {
      fail("Emit error: \{msg}")
      return
    }
  }
  assert_true(actual.contains("declare pub type RestMeta"))
  assert_true(actual.contains("declare pub fn get_runtime_version() -> String"))
  assert_true(actual.contains("declare pub fn get_build() -> Double"))
  assert_true(actual.contains("declare pub fn get_rest_meta() -> RestMeta"))
}

///|
async test "emit_moonbit_decl_text handles imported mixed barrel const-table computed-key value exports" {
  let actual = emit_moonbit_decl_text(
    "fixtures/resolver/project/types/runtime-imported-mixed-barrel-const-table-entry.ts",
  ) catch {
    @bridge.ModuleGraphError::ReadError(msg)
    | @bridge.ModuleGraphError::ParseError(msg)
    | @bridge.ModuleGraphError::ResolveError(msg) => {
      fail("Emit error: \{msg}")
      return
    }
  }
  assert_true(actual.contains("declare pub type RestMeta"))
  assert_true(actual.contains("declare pub fn get_runtime_version() -> String"))
  assert_true(actual.contains("declare pub fn get_build() -> Double"))
  assert_true(actual.contains("declare pub fn get_rest_meta() -> RestMeta"))
}

///|
async test "emit_moonbit_decl_text widens conflicting star const-table computed-key value exports" {
  let actual = emit_moonbit_decl_text(
    "fixtures/resolver/project/types/runtime-imported-conflicting-star-const-table-entry.ts",
  ) catch {
    @bridge.ModuleGraphError::ReadError(msg)
    | @bridge.ModuleGraphError::ParseError(msg)
    | @bridge.ModuleGraphError::ResolveError(msg) => {
      fail("Emit error: \{msg}")
      return
    }
  }
  assert_false(actual.contains("declare pub type RestMeta"))
  assert_true(
    actual.contains("declare pub fn get_runtime_version() -> JSValue"),
  )
  assert_true(actual.contains("declare pub fn get_build() -> JSValue"))
  assert_true(actual.contains("declare pub fn get_rest_meta() -> JSValue"))
}

///|
async test "emit_moonbit_js_ffi_texts handles neverthrow-like package entry" {
  let bundle = emit_moonbit_js_ffi_texts(
    "fixtures/resolver/project/types/neverthrow-like-entry.d.ts", "/runtime/neverthrow-like.js",
  ) catch {
    @bridge.ModuleGraphError::ReadError(msg)
    | @bridge.ModuleGraphError::ParseError(msg)
    | @bridge.ModuleGraphError::ResolveError(msg) => {
      fail("Emit error: \{msg}")
      return
    }
  }
  assert_true(bundle.ffi_mbt.contains("pub extern \"js\" fn parse_user("))
  assert_false(bundle.bridge_js.contains("__ts_mbt_parse_user"))
}

///|
async test "emit_moonbit_scaffold_from_ts handles neverthrow-like package entry" {
  let root = wbtest_tmp_project_benchmark_root(
    "bridge_package_neverthrow_like_fixture",
  )
  let _ = try? @fs.rmdir(root, recursive=true)
  @fs.mkdir(root, permission=0o755)
  let _ = emit_moonbit_scaffold_from_ts(
    "fixtures/resolver/project/types/neverthrow-like-entry.d.ts", "/runtime/neverthrow-like.js",
    root,
  )
  let bridge_mbti = @fs.read_file(wbtest_join_path(root, "bridge.mbti")).text() catch {
    e => {
      fail("Read error: \{e}")
      return
    }
  }
  let bridge_mbt = @fs.read_file(wbtest_join_path(root, "bridge.mbt")).text() catch {
    e => {
      fail("Read error: \{e}")
      return
    }
  }
  assert_true(bridge_mbti.contains("declare pub type Result"))
  assert_true(bridge_mbti.contains("declare pub type ResultAsync"))
  assert_true(
    bridge_mbti.contains("declare pub fn parseUser(input : String) -> Result"),
  )
  assert_true(bridge_mbt.contains("extern \"js\" fn parse_user("))
  assert_true(bridge_mbt.contains("extern \"js\" fn fetch_user("))
  assert_true(
    bridge_mbt.contains(
      "pub fn parseUser(input : String) -> Result {\n  parse_user(input)\n}",
    ),
  )
  assert_true(
    bridge_mbt.contains(
      "pub fn fetchUser(id : String) -> ResultAsync {\n  fetch_user(id)\n}",
    ),
  )
  let _ = try? @fs.rmdir(root, recursive=true)
}

///|
async test "emit_moonbit_js_ffi_texts handles runtime ts exported functions" {
  let bundle = emit_moonbit_js_ffi_texts(
    "fixtures/resolver/project/types/runtime-function-entry.ts", "/runtime/runtime-function.js",
  ) catch {
    @bridge.ModuleGraphError::ReadError(msg)
    | @bridge.ModuleGraphError::ParseError(msg)
    | @bridge.ModuleGraphError::ResolveError(msg) => {
      fail("Emit error: \{msg}")
      return
    }
  }
  assert_true(
    bundle.ffi_mbt.contains(
      "#module(\"/runtime/runtime-function.js\")\npub extern \"js\" fn scale_point(point : RuntimePoint, factor : Double) -> RuntimePoint = \"scalePoint\"",
    ),
  )
  assert_false(bundle.bridge_js.contains("__ts_mbt_scale_point"))
}

///|
async test "emit_moonbit_bridge_package rewrites destructured value helpers to bridge.js" {
  let root = wbtest_tmp_project_benchmark_root(
    "bridge_package_destructured_value",
  )
  let _ = try? @fs.rmdir(root, recursive=true)
  @fs.mkdir(root, permission=0o755)
  let _ = emit_moonbit_bridge_package(
    "fixtures/bridge_smoke/destructured-value-entry.ts", "./runtime/destructured-value.js",
    root,
  )
  let bridge_mbt = @fs.read_file(wbtest_join_path(root, "bridge.mbt")).text() catch {
    e => {
      fail("Read error: \{e}")
      return
    }
  }
  let bridge_js = @fs.read_file(wbtest_join_path(root, "bridge.js")).text() catch {
    e => {
      fail("Read error: \{e}")
      return
    }
  }
  let bridge_js_path = "@tsmbt-bridge/" + wbtest_basename(root)
  assert_true(
    bridge_mbt.contains(
      "#module(\"\{bridge_js_path}\")\npub extern \"js\" fn get_runtime_version() -> String = \"__ts_mbt_get_runtime_version\"",
    ),
  )
  assert_true(
    bridge_mbt.contains(
      "#module(\"\{bridge_js_path}\")\npub extern \"js\" fn get_build() -> Double = \"__ts_mbt_get_build\"",
    ),
  )
  assert_true(
    bridge_js.contains(
      "import { build, runtimeVersion } from \"./runtime/destructured-value.js\";",
    ),
  )
  assert_true(
    bridge_js.contains(
      "export function __ts_mbt_get_runtime_version() { return runtimeVersion; }",
    ),
  )
  assert_true(
    bridge_js.contains("export function __ts_mbt_get_build() { return build; }"),
  )
  let _ = try? @fs.rmdir(root, recursive=true)
}

///|
async test "emit_moonbit_bridge_package rewrites nested and array-rest destructured value helpers to bridge.js" {
  let root = wbtest_tmp_project_benchmark_root(
    "bridge_package_destructured_nested_rest_value",
  )
  let _ = try? @fs.rmdir(root, recursive=true)
  @fs.mkdir(root, permission=0o755)
  let _ = emit_moonbit_bridge_package(
    "fixtures/bridge_smoke/destructured-nested-rest-value-entry.ts", "./runtime/destructured-nested-rest-value.js",
    root,
  )
  let bridge_mbt = @fs.read_file(wbtest_join_path(root, "bridge.mbt")).text() catch {
    e => {
      fail("Read error: \{e}")
      return
    }
  }
  let bridge_js = @fs.read_file(wbtest_join_path(root, "bridge.js")).text() catch {
    e => {
      fail("Read error: \{e}")
      return
    }
  }
  let bridge_js_path = "@tsmbt-bridge/" + wbtest_basename(root)
  assert_true(
    bridge_mbt.contains(
      "#module(\"\{bridge_js_path}\")\npub extern \"js\" fn get_runtime_version() -> String = \"__ts_mbt_get_runtime_version\"",
    ),
  )
  assert_true(
    bridge_mbt.contains(
      "#module(\"\{bridge_js_path}\")\npub extern \"js\" fn get_build() -> Double = \"__ts_mbt_get_build\"",
    ),
  )
  assert_true(
    bridge_mbt.contains(
      "#module(\"\{bridge_js_path}\")\npub extern \"js\" fn get_head() -> Double = \"__ts_mbt_get_head\"",
    ),
  )
  assert_true(
    bridge_mbt.contains(
      "#module(\"\{bridge_js_path}\")\npub extern \"js\" fn get_tail() -> Array[Double] = \"__ts_mbt_get_tail\"",
    ),
  )
  assert_true(
    bridge_js.contains(
      "import { head, tail, build, runtimeVersion } from \"./runtime/destructured-nested-rest-value.js\";",
    ),
  )
  assert_true(
    bridge_js.contains("export function __ts_mbt_get_tail() { return tail; }"),
  )
  let _ = try? @fs.rmdir(root, recursive=true)
}

///|
async test "emit_moonbit_bridge_package rewrites object-rest destructured value helpers to bridge.js" {
  let root = wbtest_tmp_project_benchmark_root(
    "bridge_package_object_rest_value",
  )
  let _ = try? @fs.rmdir(root, recursive=true)
  @fs.mkdir(root, permission=0o755)
  let _ = emit_moonbit_bridge_package(
    "fixtures/bridge_smoke/object-rest-value-entry.ts", "./runtime/object-rest-value.js",
    root,
  )
  let bridge_mbt = @fs.read_file(wbtest_join_path(root, "bridge.mbt")).text() catch {
    e => {
      fail("Read error: \{e}")
      return
    }
  }
  let bridge_js = @fs.read_file(wbtest_join_path(root, "bridge.js")).text() catch {
    e => {
      fail("Read error: \{e}")
      return
    }
  }
  let bridge_js_path = "@tsmbt-bridge/" + wbtest_basename(root)
  assert_true(bridge_mbt.contains("pub(all) struct RestMeta"))
  assert_true(
    bridge_mbt.contains(
      "#module(\"\{bridge_js_path}\")\npub extern \"js\" fn get_rest_meta() -> RestMeta = \"__ts_mbt_get_rest_meta\"",
    ),
  )
  assert_true(
    bridge_js.contains(
      "import { version, restMeta } from \"./runtime/object-rest-value.js\";",
    ),
  )
  assert_true(
    bridge_js.contains(
      "export function __ts_mbt_get_rest_meta() { return restMeta; }",
    ),
  )
  let _ = try? @fs.rmdir(root, recursive=true)
}

///|
async test "emit_moonbit_bridge_package rewrites computed-key destructured value helpers to bridge.js" {
  let root = wbtest_tmp_project_benchmark_root(
    "bridge_package_computed_destructured_value",
  )
  let _ = try? @fs.rmdir(root, recursive=true)
  @fs.mkdir(root, permission=0o755)
  let _ = emit_moonbit_bridge_package(
    "fixtures/bridge_smoke/computed-destructured-value-entry.ts", "./runtime/computed-destructured-value.js",
    root,
  )
  let bridge_mbt = @fs.read_file(wbtest_join_path(root, "bridge.mbt")).text() catch {
    e => {
      fail("Read error: \{e}")
      return
    }
  }
  let bridge_js = @fs.read_file(wbtest_join_path(root, "bridge.js")).text() catch {
    e => {
      fail("Read error: \{e}")
      return
    }
  }
  let bridge_js_path = "@tsmbt-bridge/" + wbtest_basename(root)
  assert_true(bridge_mbt.contains("pub(all) struct RestMeta"))
  assert_true(
    bridge_mbt.contains(
      "#module(\"\{bridge_js_path}\")\npub extern \"js\" fn get_runtime_version() -> String = \"__ts_mbt_get_runtime_version\"",
    ),
  )
  assert_true(
    bridge_mbt.contains(
      "#module(\"\{bridge_js_path}\")\npub extern \"js\" fn get_build() -> Double = \"__ts_mbt_get_build\"",
    ),
  )
  assert_true(
    bridge_mbt.contains(
      "#module(\"\{bridge_js_path}\")\npub extern \"js\" fn get_rest_meta() -> RestMeta = \"__ts_mbt_get_rest_meta\"",
    ),
  )
  assert_true(
    bridge_js.contains(
      "import { build, restMeta, runtimeVersion } from \"./runtime/computed-destructured-value.js\";",
    ),
  )
  assert_true(
    bridge_js.contains(
      "export function __ts_mbt_get_rest_meta() { return restMeta; }",
    ),
  )
  let _ = try? @fs.rmdir(root, recursive=true)
}

///|
async test "emit_moonbit_bridge_package rewrites template-literal computed-key destructured value helpers to bridge.js" {
  let root = wbtest_tmp_project_benchmark_root(
    "bridge_package_template_computed_destructured_value",
  )
  let _ = try? @fs.rmdir(root, recursive=true)
  @fs.mkdir(root, permission=0o755)
  let _ = emit_moonbit_bridge_package(
    "fixtures/bridge_smoke/template-computed-destructured-value-entry.ts", "./runtime/template-computed-destructured-value.js",
    root,
  )
  let bridge_mbt = @fs.read_file(wbtest_join_path(root, "bridge.mbt")).text() catch {
    e => {
      fail("Read error: \{e}")
      return
    }
  }
  let bridge_js = @fs.read_file(wbtest_join_path(root, "bridge.js")).text() catch {
    e => {
      fail("Read error: \{e}")
      return
    }
  }
  let bridge_js_path = "@tsmbt-bridge/" + wbtest_basename(root)
  assert_true(bridge_mbt.contains("pub(all) struct RestMeta"))
  assert_true(
    bridge_mbt.contains(
      "#module(\"\{bridge_js_path}\")\npub extern \"js\" fn get_runtime_version() -> String = \"__ts_mbt_get_runtime_version\"",
    ),
  )
  assert_true(
    bridge_mbt.contains(
      "#module(\"\{bridge_js_path}\")\npub extern \"js\" fn get_build() -> Double = \"__ts_mbt_get_build\"",
    ),
  )
  assert_true(
    bridge_mbt.contains(
      "#module(\"\{bridge_js_path}\")\npub extern \"js\" fn get_rest_meta() -> RestMeta = \"__ts_mbt_get_rest_meta\"",
    ),
  )
  assert_true(
    bridge_js.contains(
      "import { build, restMeta, runtimeVersion } from \"./runtime/template-computed-destructured-value.js\";",
    ),
  )
  assert_true(
    bridge_js.contains(
      "export function __ts_mbt_get_rest_meta() { return restMeta; }",
    ),
  )
  let _ = try? @fs.rmdir(root, recursive=true)
}

///|
async test "emit_moonbit_bridge_package rewrites concatenated computed-key destructured value helpers to bridge.js" {
  let root = wbtest_tmp_project_benchmark_root(
    "bridge_package_concat_computed_destructured_value",
  )
  let _ = try? @fs.rmdir(root, recursive=true)
  @fs.mkdir(root, permission=0o755)
  let _ = emit_moonbit_bridge_package(
    "fixtures/bridge_smoke/concat-computed-destructured-value-entry.ts", "./runtime/concat-computed-destructured-value.js",
    root,
  )
  let bridge_mbt = @fs.read_file(wbtest_join_path(root, "bridge.mbt")).text() catch {
    e => {
      fail("Read error: \{e}")
      return
    }
  }
  let bridge_js = @fs.read_file(wbtest_join_path(root, "bridge.js")).text() catch {
    e => {
      fail("Read error: \{e}")
      return
    }
  }
  let bridge_js_path = "@tsmbt-bridge/" + wbtest_basename(root)
  assert_true(bridge_mbt.contains("pub(all) struct RestMeta"))
  assert_true(
    bridge_mbt.contains(
      "#module(\"\{bridge_js_path}\")\npub extern \"js\" fn get_runtime_version() -> String = \"__ts_mbt_get_runtime_version\"",
    ),
  )
  assert_true(
    bridge_mbt.contains(
      "#module(\"\{bridge_js_path}\")\npub extern \"js\" fn get_build() -> Double = \"__ts_mbt_get_build\"",
    ),
  )
  assert_true(
    bridge_mbt.contains(
      "#module(\"\{bridge_js_path}\")\npub extern \"js\" fn get_rest_meta() -> RestMeta = \"__ts_mbt_get_rest_meta\"",
    ),
  )
  assert_true(
    bridge_js.contains(
      "import { build, restMeta, runtimeVersion } from \"./runtime/concat-computed-destructured-value.js\";",
    ),
  )
  assert_true(
    bridge_js.contains(
      "export function __ts_mbt_get_rest_meta() { return restMeta; }",
    ),
  )
  let _ = try? @fs.rmdir(root, recursive=true)
}

///|
async test "emit_moonbit_bridge_package rewrites primitive-literal computed-key destructured value helpers to bridge.js" {
  let root = wbtest_tmp_project_benchmark_root(
    "bridge_package_primitive_computed_destructured_value",
  )
  let _ = try? @fs.rmdir(root, recursive=true)
  @fs.mkdir(root, permission=0o755)
  let _ = emit_moonbit_bridge_package(
    "fixtures/bridge_smoke/primitive-computed-destructured-value-entry.ts", "./runtime/primitive-computed-destructured-value.js",
    root,
  )
  let bridge_mbt = @fs.read_file(wbtest_join_path(root, "bridge.mbt")).text() catch {
    e => {
      fail("Read error: \{e}")
      return
    }
  }
  let bridge_js = @fs.read_file(wbtest_join_path(root, "bridge.js")).text() catch {
    e => {
      fail("Read error: \{e}")
      return
    }
  }
  let bridge_js_path = "@tsmbt-bridge/" + wbtest_basename(root)
  assert_true(bridge_mbt.contains("pub(all) struct RestMeta"))
  assert_true(
    bridge_mbt.contains(
      "#module(\"\{bridge_js_path}\")\npub extern \"js\" fn get_truthy() -> String = \"__ts_mbt_get_truthy\"",
    ),
  )
  assert_true(
    bridge_mbt.contains(
      "#module(\"\{bridge_js_path}\")\npub extern \"js\" fn get_nil_value() -> Double = \"__ts_mbt_get_nil_value\"",
    ),
  )
  assert_true(
    bridge_mbt.contains(
      "#module(\"\{bridge_js_path}\")\npub extern \"js\" fn get_negative() -> Bool = \"__ts_mbt_get_negative\"",
    ),
  )
  assert_true(
    bridge_mbt.contains(
      "#module(\"\{bridge_js_path}\")\npub extern \"js\" fn get_bigint_value() -> String = \"__ts_mbt_get_bigint_value\"",
    ),
  )
  assert_true(
    bridge_mbt.contains(
      "#module(\"\{bridge_js_path}\")\npub extern \"js\" fn get_rest_meta() -> RestMeta = \"__ts_mbt_get_rest_meta\"",
    ),
  )
  assert_true(
    bridge_js.contains(
      "import { truthy, negative, nilValue, restMeta, bigintValue } from \"./runtime/primitive-computed-destructured-value.js\";",
    ),
  )
  assert_true(
    bridge_js.contains(
      "export function __ts_mbt_get_rest_meta() { return restMeta; }",
    ),
  )
  let _ = try? @fs.rmdir(root, recursive=true)
}

///|
async test "emit_moonbit_bridge_package rewrites void-and-negative-bigint computed-key destructured value helpers to bridge.js" {
  let root = wbtest_tmp_project_benchmark_root(
    "bridge_package_void_bigint_computed_destructured_value",
  )
  let _ = try? @fs.rmdir(root, recursive=true)
  @fs.mkdir(root, permission=0o755)
  let _ = emit_moonbit_bridge_package(
    "fixtures/bridge_smoke/void-bigint-computed-destructured-value-entry.ts", "./runtime/void-bigint-computed-destructured-value.js",
    root,
  )
  let bridge_mbt = @fs.read_file(wbtest_join_path(root, "bridge.mbt")).text() catch {
    e => {
      fail("Read error: \{e}")
      return
    }
  }
  let bridge_js = @fs.read_file(wbtest_join_path(root, "bridge.js")).text() catch {
    e => {
      fail("Read error: \{e}")
      return
    }
  }
  let bridge_js_path = "@tsmbt-bridge/" + wbtest_basename(root)
  assert_true(bridge_mbt.contains("pub(all) struct RestMeta"))
  assert_true(
    bridge_mbt.contains(
      "#module(\"\{bridge_js_path}\")\npub extern \"js\" fn get_undefined_value() -> String = \"__ts_mbt_get_undefined_value\"",
    ),
  )
  assert_true(
    bridge_mbt.contains(
      "#module(\"\{bridge_js_path}\")\npub extern \"js\" fn get_negative_bigint() -> Double = \"__ts_mbt_get_negative_bigint\"",
    ),
  )
  assert_true(
    bridge_mbt.contains(
      "#module(\"\{bridge_js_path}\")\npub extern \"js\" fn get_rest_meta() -> RestMeta = \"__ts_mbt_get_rest_meta\"",
    ),
  )
  assert_true(
    bridge_js.contains(
      "import { restMeta, negativeBigint, undefinedValue } from \"./runtime/void-bigint-computed-destructured-value.js\";",
    ),
  )
  assert_true(
    bridge_js.contains(
      "export function __ts_mbt_get_rest_meta() { return restMeta; }",
    ),
  )
  let _ = try? @fs.rmdir(root, recursive=true)
}

///|
async test "emit_moonbit_bridge_package rewrites const-reference computed-key destructured value helpers to bridge.js" {
  let root = wbtest_tmp_project_benchmark_root(
    "bridge_package_const_ref_computed_destructured_value",
  )
  let _ = try? @fs.rmdir(root, recursive=true)
  @fs.mkdir(root, permission=0o755)
  let _ = emit_moonbit_bridge_package(
    "fixtures/bridge_smoke/const-ref-computed-destructured-value-entry.ts", "./runtime/const-ref-computed-destructured-value.js",
    root,
  )
  let bridge_mbt = @fs.read_file(wbtest_join_path(root, "bridge.mbt")).text() catch {
    e => {
      fail("Read error: \{e}")
      return
    }
  }
  let bridge_js = @fs.read_file(wbtest_join_path(root, "bridge.js")).text() catch {
    e => {
      fail("Read error: \{e}")
      return
    }
  }
  let bridge_js_path = "@tsmbt-bridge/" + wbtest_basename(root)
  assert_true(bridge_mbt.contains("pub(all) struct RestMeta"))
  assert_true(
    bridge_mbt.contains(
      "#module(\"\{bridge_js_path}\")\npub extern \"js\" fn get_runtime_version() -> String = \"__ts_mbt_get_runtime_version\"",
    ),
  )
  assert_true(
    bridge_mbt.contains(
      "#module(\"\{bridge_js_path}\")\npub extern \"js\" fn get_build() -> Double = \"__ts_mbt_get_build\"",
    ),
  )
  assert_true(
    bridge_mbt.contains(
      "#module(\"\{bridge_js_path}\")\npub extern \"js\" fn get_rest_meta() -> RestMeta = \"__ts_mbt_get_rest_meta\"",
    ),
  )
  assert_true(
    bridge_js.contains(
      "import { build, restMeta, runtimeVersion } from \"./runtime/const-ref-computed-destructured-value.js\";",
    ),
  )
  assert_true(
    bridge_js.contains(
      "export function __ts_mbt_get_rest_meta() { return restMeta; }",
    ),
  )
  let _ = try? @fs.rmdir(root, recursive=true)
}

///|
async test "emit_moonbit_bridge_package rewrites destructured-const-reference computed-key value helpers to bridge.js" {
  let root = wbtest_tmp_project_benchmark_root(
    "bridge_package_destructured_const_ref_computed_destructured_value",
  )
  let _ = try? @fs.rmdir(root, recursive=true)
  @fs.mkdir(root, permission=0o755)
  let _ = emit_moonbit_bridge_package(
    "fixtures/bridge_smoke/destructured-const-ref-computed-destructured-value-entry.ts",
    "./runtime/destructured-const-ref-computed-destructured-value.js", root,
  )
  let bridge_mbt = @fs.read_file(wbtest_join_path(root, "bridge.mbt")).text() catch {
    e => {
      fail("Read error: \{e}")
      return
    }
  }
  let bridge_js = @fs.read_file(wbtest_join_path(root, "bridge.js")).text() catch {
    e => {
      fail("Read error: \{e}")
      return
    }
  }
  let bridge_js_path = "@tsmbt-bridge/" + wbtest_basename(root)
  assert_true(bridge_mbt.contains("pub(all) struct RestMeta"))
  assert_true(
    bridge_mbt.contains(
      "#module(\"\{bridge_js_path}\")\npub extern \"js\" fn get_runtime_version() -> String = \"__ts_mbt_get_runtime_version\"",
    ),
  )
  assert_true(
    bridge_mbt.contains(
      "#module(\"\{bridge_js_path}\")\npub extern \"js\" fn get_build() -> Double = \"__ts_mbt_get_build\"",
    ),
  )
  assert_true(
    bridge_mbt.contains(
      "#module(\"\{bridge_js_path}\")\npub extern \"js\" fn get_rest_meta() -> RestMeta = \"__ts_mbt_get_rest_meta\"",
    ),
  )
  assert_true(
    bridge_js.contains(
      "import { build, restMeta, runtimeVersion } from \"./runtime/destructured-const-ref-computed-destructured-value.js\";",
    ),
  )
  assert_true(
    bridge_js.contains(
      "export function __ts_mbt_get_rest_meta() { return restMeta; }",
    ),
  )
  let _ = try? @fs.rmdir(root, recursive=true)
}

///|
async test "emit_moonbit_bridge_package rewrites const-object-access computed-key value helpers to bridge.js" {
  let root = wbtest_tmp_project_benchmark_root(
    "bridge_package_const_object_access_computed_destructured_value",
  )
  let _ = try? @fs.rmdir(root, recursive=true)
  @fs.mkdir(root, permission=0o755)
  let _ = emit_moonbit_bridge_package(
    "fixtures/bridge_smoke/const-object-access-computed-destructured-value-entry.ts",
    "./runtime/const-object-access-computed-destructured-value.js", root,
  )
  let bridge_mbt = @fs.read_file(wbtest_join_path(root, "bridge.mbt")).text() catch {
    e => {
      fail("Read error: \{e}")
      return
    }
  }
  let bridge_js = @fs.read_file(wbtest_join_path(root, "bridge.js")).text() catch {
    e => {
      fail("Read error: \{e}")
      return
    }
  }
  let bridge_js_path = "@tsmbt-bridge/" + wbtest_basename(root)
  assert_true(bridge_mbt.contains("pub(all) struct RestMeta"))
  assert_true(
    bridge_mbt.contains(
      "#module(\"\{bridge_js_path}\")\npub extern \"js\" fn get_runtime_version() -> String = \"__ts_mbt_get_runtime_version\"",
    ),
  )
  assert_true(
    bridge_mbt.contains(
      "#module(\"\{bridge_js_path}\")\npub extern \"js\" fn get_build() -> Double = \"__ts_mbt_get_build\"",
    ),
  )
  assert_true(
    bridge_mbt.contains(
      "#module(\"\{bridge_js_path}\")\npub extern \"js\" fn get_rest_meta() -> RestMeta = \"__ts_mbt_get_rest_meta\"",
    ),
  )
  assert_true(
    bridge_js.contains(
      "import { build, restMeta, runtimeVersion } from \"./runtime/const-object-access-computed-destructured-value.js\";",
    ),
  )
  assert_true(
    bridge_js.contains(
      "export function __ts_mbt_get_rest_meta() { return restMeta; }",
    ),
  )
  let _ = try? @fs.rmdir(root, recursive=true)
}

///|
async test "emit_moonbit_bridge_package rewrites nested-const-object-access computed-key value helpers to bridge.js" {
  let root = wbtest_tmp_project_benchmark_root(
    "bridge_package_nested_const_object_access_computed_destructured_value",
  )
  let _ = try? @fs.rmdir(root, recursive=true)
  @fs.mkdir(root, permission=0o755)
  let _ = emit_moonbit_bridge_package(
    "fixtures/bridge_smoke/nested-const-object-access-computed-destructured-value-entry.ts",
    "./runtime/nested-const-object-access-computed-destructured-value.js", root,
  )
  let bridge_mbt = @fs.read_file(wbtest_join_path(root, "bridge.mbt")).text() catch {
    e => {
      fail("Read error: \{e}")
      return
    }
  }
  let bridge_js = @fs.read_file(wbtest_join_path(root, "bridge.js")).text() catch {
    e => {
      fail("Read error: \{e}")
      return
    }
  }
  let bridge_js_path = "@tsmbt-bridge/" + wbtest_basename(root)
  assert_true(bridge_mbt.contains("pub(all) struct RestMeta"))
  assert_true(
    bridge_mbt.contains(
      "#module(\"\{bridge_js_path}\")\npub extern \"js\" fn get_runtime_version() -> String = \"__ts_mbt_get_runtime_version\"",
    ),
  )
  assert_true(
    bridge_mbt.contains(
      "#module(\"\{bridge_js_path}\")\npub extern \"js\" fn get_build() -> Double = \"__ts_mbt_get_build\"",
    ),
  )
  assert_true(
    bridge_mbt.contains(
      "#module(\"\{bridge_js_path}\")\npub extern \"js\" fn get_rest_meta() -> RestMeta = \"__ts_mbt_get_rest_meta\"",
    ),
  )
  assert_true(
    bridge_js.contains(
      "import { build, restMeta, runtimeVersion } from \"./runtime/nested-const-object-access-computed-destructured-value.js\";",
    ),
  )
  assert_true(
    bridge_js.contains(
      "export function __ts_mbt_get_rest_meta() { return restMeta; }",
    ),
  )
  let _ = try? @fs.rmdir(root, recursive=true)
}

///|
async test "emit_moonbit_bridge_package rewrites const-array-access computed-key value helpers to bridge.js" {
  let root = wbtest_tmp_project_benchmark_root(
    "bridge_package_const_array_access_computed_destructured_value",
  )
  let _ = try? @fs.rmdir(root, recursive=true)
  @fs.mkdir(root, permission=0o755)
  let _ = emit_moonbit_bridge_package(
    "fixtures/bridge_smoke/const-array-access-computed-destructured-value-entry.ts",
    "./runtime/const-array-access-computed-destructured-value.js", root,
  )
  let bridge_mbt = @fs.read_file(wbtest_join_path(root, "bridge.mbt")).text() catch {
    e => {
      fail("Read error: \{e}")
      return
    }
  }
  let bridge_js = @fs.read_file(wbtest_join_path(root, "bridge.js")).text() catch {
    e => {
      fail("Read error: \{e}")
      return
    }
  }
  let bridge_js_path = "@tsmbt-bridge/" + wbtest_basename(root)
  assert_true(bridge_mbt.contains("pub(all) struct RestMeta"))
  assert_true(
    bridge_mbt.contains(
      "#module(\"\{bridge_js_path}\")\npub extern \"js\" fn get_runtime_version() -> String = \"__ts_mbt_get_runtime_version\"",
    ),
  )
  assert_true(
    bridge_mbt.contains(
      "#module(\"\{bridge_js_path}\")\npub extern \"js\" fn get_build() -> Double = \"__ts_mbt_get_build\"",
    ),
  )
  assert_true(
    bridge_mbt.contains(
      "#module(\"\{bridge_js_path}\")\npub extern \"js\" fn get_rest_meta() -> RestMeta = \"__ts_mbt_get_rest_meta\"",
    ),
  )
  assert_true(
    bridge_js.contains(
      "import { build, restMeta, runtimeVersion } from \"./runtime/const-array-access-computed-destructured-value.js\";",
    ),
  )
  assert_true(
    bridge_js.contains(
      "export function __ts_mbt_get_rest_meta() { return restMeta; }",
    ),
  )
  let _ = try? @fs.rmdir(root, recursive=true)
}

///|
async test "emit_moonbit_bridge_package rewrites nested-const-array-access computed-key value helpers to bridge.js" {
  let root = wbtest_tmp_project_benchmark_root(
    "bridge_package_nested_const_array_access_computed_destructured_value",
  )
  let _ = try? @fs.rmdir(root, recursive=true)
  @fs.mkdir(root, permission=0o755)
  let _ = emit_moonbit_bridge_package(
    "fixtures/bridge_smoke/nested-const-array-access-computed-destructured-value-entry.ts",
    "./runtime/nested-const-array-access-computed-destructured-value.js", root,
  )
  let bridge_mbt = @fs.read_file(wbtest_join_path(root, "bridge.mbt")).text() catch {
    e => {
      fail("Read error: \{e}")
      return
    }
  }
  let bridge_js = @fs.read_file(wbtest_join_path(root, "bridge.js")).text() catch {
    e => {
      fail("Read error: \{e}")
      return
    }
  }
  let bridge_js_path = "@tsmbt-bridge/" + wbtest_basename(root)
  assert_true(bridge_mbt.contains("pub(all) struct RestMeta"))
  assert_true(
    bridge_mbt.contains(
      "#module(\"\{bridge_js_path}\")\npub extern \"js\" fn get_runtime_version() -> String = \"__ts_mbt_get_runtime_version\"",
    ),
  )
  assert_true(
    bridge_mbt.contains(
      "#module(\"\{bridge_js_path}\")\npub extern \"js\" fn get_build() -> Double = \"__ts_mbt_get_build\"",
    ),
  )
  assert_true(
    bridge_mbt.contains(
      "#module(\"\{bridge_js_path}\")\npub extern \"js\" fn get_rest_meta() -> RestMeta = \"__ts_mbt_get_rest_meta\"",
    ),
  )
  assert_true(
    bridge_js.contains(
      "import { build, restMeta, runtimeVersion } from \"./runtime/nested-const-array-access-computed-destructured-value.js\";",
    ),
  )
  assert_true(
    bridge_js.contains(
      "export function __ts_mbt_get_rest_meta() { return restMeta; }",
    ),
  )
  let _ = try? @fs.rmdir(root, recursive=true)
}

///|
async test "emit_moonbit_bridge_package rewrites const-index-alias computed-key value helpers to bridge.js" {
  let root = wbtest_tmp_project_benchmark_root(
    "bridge_package_const_index_alias_computed_destructured_value",
  )
  let _ = try? @fs.rmdir(root, recursive=true)
  @fs.mkdir(root, permission=0o755)
  let _ = emit_moonbit_bridge_package(
    "fixtures/bridge_smoke/const-index-alias-computed-destructured-value-entry.ts",
    "./runtime/const-index-alias-computed-destructured-value.js", root,
  )
  let bridge_mbt = @fs.read_file(wbtest_join_path(root, "bridge.mbt")).text() catch {
    e => {
      fail("Read error: \{e}")
      return
    }
  }
  let bridge_js = @fs.read_file(wbtest_join_path(root, "bridge.js")).text() catch {
    e => {
      fail("Read error: \{e}")
      return
    }
  }
  let bridge_js_path = "@tsmbt-bridge/" + wbtest_basename(root)
  assert_true(bridge_mbt.contains("pub(all) struct RestMeta"))
  assert_true(
    bridge_mbt.contains(
      "#module(\"\{bridge_js_path}\")\npub extern \"js\" fn get_runtime_version() -> String = \"__ts_mbt_get_runtime_version\"",
    ),
  )
  assert_true(
    bridge_mbt.contains(
      "#module(\"\{bridge_js_path}\")\npub extern \"js\" fn get_build() -> Double = \"__ts_mbt_get_build\"",
    ),
  )
  assert_true(
    bridge_mbt.contains(
      "#module(\"\{bridge_js_path}\")\npub extern \"js\" fn get_rest_meta() -> RestMeta = \"__ts_mbt_get_rest_meta\"",
    ),
  )
  assert_true(
    bridge_js.contains(
      "import { build, restMeta, runtimeVersion } from \"./runtime/const-index-alias-computed-destructured-value.js\";",
    ),
  )
  assert_true(
    bridge_js.contains(
      "export function __ts_mbt_get_rest_meta() { return restMeta; }",
    ),
  )
  let _ = try? @fs.rmdir(root, recursive=true)
}

///|
async test "emit_moonbit_bridge_package rewrites const-index-table computed-key value helpers to bridge.js" {
  let root = wbtest_tmp_project_benchmark_root(
    "bridge_package_const_index_table_computed_destructured_value",
  )
  let _ = try? @fs.rmdir(root, recursive=true)
  @fs.mkdir(root, permission=0o755)
  let _ = emit_moonbit_bridge_package(
    "fixtures/bridge_smoke/const-index-table-computed-destructured-value-entry.ts",
    "./runtime/const-index-table-computed-destructured-value.js", root,
  )
  let bridge_mbt = @fs.read_file(wbtest_join_path(root, "bridge.mbt")).text() catch {
    e => {
      fail("Read error: \{e}")
      return
    }
  }
  let bridge_js = @fs.read_file(wbtest_join_path(root, "bridge.js")).text() catch {
    e => {
      fail("Read error: \{e}")
      return
    }
  }
  let bridge_js_path = "@tsmbt-bridge/" + wbtest_basename(root)
  assert_true(bridge_mbt.contains("pub(all) struct RestMeta"))
  assert_true(
    bridge_mbt.contains(
      "#module(\"\{bridge_js_path}\")\npub extern \"js\" fn get_runtime_version() -> String = \"__ts_mbt_get_runtime_version\"",
    ),
  )
  assert_true(
    bridge_mbt.contains(
      "#module(\"\{bridge_js_path}\")\npub extern \"js\" fn get_build() -> Double = \"__ts_mbt_get_build\"",
    ),
  )
  assert_true(
    bridge_mbt.contains(
      "#module(\"\{bridge_js_path}\")\npub extern \"js\" fn get_rest_meta() -> RestMeta = \"__ts_mbt_get_rest_meta\"",
    ),
  )
  assert_true(
    bridge_js.contains(
      "import { build, restMeta, runtimeVersion } from \"./runtime/const-index-table-computed-destructured-value.js\";",
    ),
  )
  assert_true(
    bridge_js.contains(
      "export function __ts_mbt_get_rest_meta() { return restMeta; }",
    ),
  )
  let _ = try? @fs.rmdir(root, recursive=true)
}

///|
async test "emit_moonbit_bridge_package rewrites nested-index-table computed-key value helpers to bridge.js" {
  let root = wbtest_tmp_project_benchmark_root(
    "bridge_package_nested_index_table_computed_destructured_value",
  )
  let _ = try? @fs.rmdir(root, recursive=true)
  @fs.mkdir(root, permission=0o755)
  let _ = emit_moonbit_bridge_package(
    "fixtures/bridge_smoke/nested-index-table-computed-destructured-value-entry.ts",
    "./runtime/nested-index-table-computed-destructured-value.js", root,
  )
  let bridge_mbt = @fs.read_file(wbtest_join_path(root, "bridge.mbt")).text() catch {
    e => {
      fail("Read error: \{e}")
      return
    }
  }
  let bridge_js = @fs.read_file(wbtest_join_path(root, "bridge.js")).text() catch {
    e => {
      fail("Read error: \{e}")
      return
    }
  }
  let bridge_js_path = "@tsmbt-bridge/" + wbtest_basename(root)
  assert_true(bridge_mbt.contains("pub(all) struct RestMeta"))
  assert_true(
    bridge_mbt.contains(
      "#module(\"\{bridge_js_path}\")\npub extern \"js\" fn get_runtime_version() -> String = \"__ts_mbt_get_runtime_version\"",
    ),
  )
  assert_true(
    bridge_mbt.contains(
      "#module(\"\{bridge_js_path}\")\npub extern \"js\" fn get_build() -> Double = \"__ts_mbt_get_build\"",
    ),
  )
  assert_true(
    bridge_mbt.contains(
      "#module(\"\{bridge_js_path}\")\npub extern \"js\" fn get_rest_meta() -> RestMeta = \"__ts_mbt_get_rest_meta\"",
    ),
  )
  assert_true(
    bridge_js.contains(
      "import { build, restMeta, runtimeVersion } from \"./runtime/nested-index-table-computed-destructured-value.js\";",
    ),
  )
  assert_true(
    bridge_js.contains(
      "export function __ts_mbt_get_rest_meta() { return restMeta; }",
    ),
  )
  let _ = try? @fs.rmdir(root, recursive=true)
}

///|
async test "emit_moonbit_bridge_package rewrites imported const-table computed-key value helpers to bridge.js" {
  let root = wbtest_tmp_project_benchmark_root(
    "bridge_package_imported_const_table_computed_destructured_value",
  )
  let _ = try? @fs.rmdir(root, recursive=true)
  @fs.mkdir(root, permission=0o755)
  let _ = emit_moonbit_bridge_package(
    "fixtures/bridge_smoke/imported-const-table-entry.ts", "./runtime/imported-const-table-entry.js",
    root,
  )
  let bridge_mbt = @fs.read_file(wbtest_join_path(root, "bridge.mbt")).text() catch {
    e => {
      fail("Read error: \{e}")
      return
    }
  }
  let bridge_js = @fs.read_file(wbtest_join_path(root, "bridge.js")).text() catch {
    e => {
      fail("Read error: \{e}")
      return
    }
  }
  let bridge_js_path = "@tsmbt-bridge/" + wbtest_basename(root)
  assert_true(bridge_mbt.contains("pub(all) struct RestMeta"))
  assert_true(
    bridge_mbt.contains(
      "#module(\"\{bridge_js_path}\")\npub extern \"js\" fn get_runtime_version() -> String = \"__ts_mbt_get_runtime_version\"",
    ),
  )
  assert_true(
    bridge_mbt.contains(
      "#module(\"\{bridge_js_path}\")\npub extern \"js\" fn get_build() -> Double = \"__ts_mbt_get_build\"",
    ),
  )
  assert_true(
    bridge_mbt.contains(
      "#module(\"\{bridge_js_path}\")\npub extern \"js\" fn get_rest_meta() -> RestMeta = \"__ts_mbt_get_rest_meta\"",
    ),
  )
  assert_true(
    bridge_js.contains(
      "import { build, restMeta, runtimeVersion } from \"./runtime/imported-const-table-entry.js\";",
    ),
  )
  assert_true(
    bridge_js.contains(
      "export function __ts_mbt_get_rest_meta() { return restMeta; }",
    ),
  )
  let _ = try? @fs.rmdir(root, recursive=true)
}

///|
async test "emit_moonbit_bridge_package rewrites imported namespace const-table computed-key value helpers to bridge.js" {
  let root = wbtest_tmp_project_benchmark_root(
    "bridge_package_imported_namespace_const_table_computed_destructured_value",
  )
  let _ = try? @fs.rmdir(root, recursive=true)
  @fs.mkdir(root, permission=0o755)
  let _ = emit_moonbit_bridge_package(
    "fixtures/bridge_smoke/imported-namespace-const-table-entry.ts", "./runtime/imported-namespace-const-table-entry.js",
    root,
  )
  let bridge_mbt = @fs.read_file(wbtest_join_path(root, "bridge.mbt")).text() catch {
    e => {
      fail("Read error: \{e}")
      return
    }
  }
  let bridge_js = @fs.read_file(wbtest_join_path(root, "bridge.js")).text() catch {
    e => {
      fail("Read error: \{e}")
      return
    }
  }
  let bridge_js_path = "@tsmbt-bridge/" + wbtest_basename(root)
  assert_true(bridge_mbt.contains("pub(all) struct RestMeta"))
  assert_true(
    bridge_mbt.contains(
      "#module(\"\{bridge_js_path}\")\npub extern \"js\" fn get_runtime_version() -> String = \"__ts_mbt_get_runtime_version\"",
    ),
  )
  assert_true(
    bridge_mbt.contains(
      "#module(\"\{bridge_js_path}\")\npub extern \"js\" fn get_build() -> Double = \"__ts_mbt_get_build\"",
    ),
  )
  assert_true(
    bridge_mbt.contains(
      "#module(\"\{bridge_js_path}\")\npub extern \"js\" fn get_rest_meta() -> RestMeta = \"__ts_mbt_get_rest_meta\"",
    ),
  )
  assert_true(
    bridge_js.contains(
      "import { build, restMeta, runtimeVersion } from \"./runtime/imported-namespace-const-table-entry.js\";",
    ),
  )
  assert_true(
    bridge_js.contains(
      "export function __ts_mbt_get_rest_meta() { return restMeta; }",
    ),
  )
  let _ = try? @fs.rmdir(root, recursive=true)
}

///|
async test "emit_moonbit_bridge_package rewrites imported default const-table computed-key value helpers to bridge.js" {
  let root = wbtest_tmp_project_benchmark_root(
    "bridge_package_imported_default_const_table_computed_destructured_value",
  )
  let _ = try? @fs.rmdir(root, recursive=true)
  @fs.mkdir(root, permission=0o755)
  let _ = emit_moonbit_bridge_package(
    "fixtures/bridge_smoke/imported-default-const-table-entry.ts", "./runtime/imported-default-const-table-entry.js",
    root,
  )
  let bridge_mbt = @fs.read_file(wbtest_join_path(root, "bridge.mbt")).text() catch {
    e => {
      fail("Read error: \{e}")
      return
    }
  }
  let bridge_js = @fs.read_file(wbtest_join_path(root, "bridge.js")).text() catch {
    e => {
      fail("Read error: \{e}")
      return
    }
  }
  let bridge_js_path = "@tsmbt-bridge/" + wbtest_basename(root)
  assert_true(bridge_mbt.contains("pub(all) struct RestMeta"))
  assert_true(
    bridge_mbt.contains(
      "#module(\"\{bridge_js_path}\")\npub extern \"js\" fn get_runtime_version() -> String = \"__ts_mbt_get_runtime_version\"",
    ),
  )
  assert_true(
    bridge_mbt.contains(
      "#module(\"\{bridge_js_path}\")\npub extern \"js\" fn get_build() -> Double = \"__ts_mbt_get_build\"",
    ),
  )
  assert_true(
    bridge_mbt.contains(
      "#module(\"\{bridge_js_path}\")\npub extern \"js\" fn get_rest_meta() -> RestMeta = \"__ts_mbt_get_rest_meta\"",
    ),
  )
  assert_true(
    bridge_js.contains(
      "import { build, restMeta, runtimeVersion } from \"./runtime/imported-default-const-table-entry.js\";",
    ),
  )
  assert_true(
    bridge_js.contains(
      "export function __ts_mbt_get_rest_meta() { return restMeta; }",
    ),
  )
  let _ = try? @fs.rmdir(root, recursive=true)
}

///|
async test "emit_moonbit_bridge_package rewrites imported inline default const-table computed-key value helpers to bridge.js" {
  let root = wbtest_tmp_project_benchmark_root(
    "bridge_package_imported_inline_default_const_table_computed_destructured_value",
  )
  let _ = try? @fs.rmdir(root, recursive=true)
  @fs.mkdir(root, permission=0o755)
  let _ = emit_moonbit_bridge_package(
    "fixtures/bridge_smoke/imported-inline-default-const-table-entry.ts", "./runtime/imported-inline-default-const-table-entry.js",
    root,
  )
  let bridge_mbt = @fs.read_file(wbtest_join_path(root, "bridge.mbt")).text() catch {
    e => {
      fail("Read error: \{e}")
      return
    }
  }
  let bridge_js = @fs.read_file(wbtest_join_path(root, "bridge.js")).text() catch {
    e => {
      fail("Read error: \{e}")
      return
    }
  }
  let bridge_js_path = "@tsmbt-bridge/" + wbtest_basename(root)
  assert_true(bridge_mbt.contains("pub(all) struct RestMeta"))
  assert_true(
    bridge_mbt.contains(
      "#module(\"\{bridge_js_path}\")\npub extern \"js\" fn get_runtime_version() -> String = \"__ts_mbt_get_runtime_version\"",
    ),
  )
  assert_true(
    bridge_mbt.contains(
      "#module(\"\{bridge_js_path}\")\npub extern \"js\" fn get_build() -> Double = \"__ts_mbt_get_build\"",
    ),
  )
  assert_true(
    bridge_mbt.contains(
      "#module(\"\{bridge_js_path}\")\npub extern \"js\" fn get_rest_meta() -> RestMeta = \"__ts_mbt_get_rest_meta\"",
    ),
  )
  assert_true(
    bridge_js.contains(
      "import { build, restMeta, runtimeVersion } from \"./runtime/imported-inline-default-const-table-entry.js\";",
    ),
  )
  assert_true(
    bridge_js.contains(
      "export function __ts_mbt_get_rest_meta() { return restMeta; }",
    ),
  )
  let _ = try? @fs.rmdir(root, recursive=true)
}

///|
async test "emit_moonbit_bridge_package rewrites imported inline default const-table as const computed-key value helpers to bridge.js" {
  let root = wbtest_tmp_project_benchmark_root(
    "bridge_package_imported_inline_default_const_table_as_const_computed_destructured_value",
  )
  let _ = try? @fs.rmdir(root, recursive=true)
  @fs.mkdir(root, permission=0o755)
  let _ = emit_moonbit_bridge_package(
    "fixtures/bridge_smoke/imported-inline-default-const-table-as-const-entry.ts",
    "./runtime/imported-inline-default-const-table-as-const-entry.js", root,
  )
  let bridge_mbt = @fs.read_file(wbtest_join_path(root, "bridge.mbt")).text() catch {
    e => {
      fail("Read error: \{e}")
      return
    }
  }
  let bridge_js = @fs.read_file(wbtest_join_path(root, "bridge.js")).text() catch {
    e => {
      fail("Read error: \{e}")
      return
    }
  }
  let bridge_js_path = "@tsmbt-bridge/" + wbtest_basename(root)
  assert_true(bridge_mbt.contains("pub(all) struct RestMeta"))
  assert_true(
    bridge_mbt.contains(
      "#module(\"\{bridge_js_path}\")\npub extern \"js\" fn get_runtime_version() -> String = \"__ts_mbt_get_runtime_version\"",
    ),
  )
  assert_true(
    bridge_mbt.contains(
      "#module(\"\{bridge_js_path}\")\npub extern \"js\" fn get_build() -> Double = \"__ts_mbt_get_build\"",
    ),
  )
  assert_true(
    bridge_mbt.contains(
      "#module(\"\{bridge_js_path}\")\npub extern \"js\" fn get_rest_meta() -> RestMeta = \"__ts_mbt_get_rest_meta\"",
    ),
  )
  assert_true(
    bridge_js.contains(
      "import { build, restMeta, runtimeVersion } from \"./runtime/imported-inline-default-const-table-as-const-entry.js\";",
    ),
  )
  assert_true(
    bridge_js.contains(
      "export function __ts_mbt_get_rest_meta() { return restMeta; }",
    ),
  )
  let _ = try? @fs.rmdir(root, recursive=true)
}

///|
async test "emit_moonbit_bridge_package rewrites imported iife default const-table computed-key value helpers to bridge.js" {
  let root = wbtest_tmp_project_benchmark_root(
    "bridge_package_imported_iife_default_const_table_computed_destructured_value",
  )
  let _ = try? @fs.rmdir(root, recursive=true)
  @fs.mkdir(root, permission=0o755)
  let _ = emit_moonbit_bridge_package(
    "fixtures/bridge_smoke/imported-iife-default-const-table-entry.ts", "./runtime/imported-iife-default-const-table-entry.js",
    root,
  )
  let bridge_mbt = @fs.read_file(wbtest_join_path(root, "bridge.mbt")).text() catch {
    e => {
      fail("Read error: \{e}")
      return
    }
  }
  let bridge_js = @fs.read_file(wbtest_join_path(root, "bridge.js")).text() catch {
    e => {
      fail("Read error: \{e}")
      return
    }
  }
  let bridge_js_path = "@tsmbt-bridge/" + wbtest_basename(root)
  assert_true(bridge_mbt.contains("pub(all) struct RestMeta"))
  assert_true(
    bridge_mbt.contains(
      "#module(\"\{bridge_js_path}\")\npub extern \"js\" fn get_runtime_version() -> String = \"__ts_mbt_get_runtime_version\"",
    ),
  )
  assert_true(
    bridge_mbt.contains(
      "#module(\"\{bridge_js_path}\")\npub extern \"js\" fn get_build() -> Double = \"__ts_mbt_get_build\"",
    ),
  )
  assert_true(
    bridge_mbt.contains(
      "#module(\"\{bridge_js_path}\")\npub extern \"js\" fn get_rest_meta() -> RestMeta = \"__ts_mbt_get_rest_meta\"",
    ),
  )
  assert_true(
    bridge_js.contains(
      "import { build, restMeta, runtimeVersion } from \"./runtime/imported-iife-default-const-table-entry.js\";",
    ),
  )
  assert_true(
    bridge_js.contains(
      "export function __ts_mbt_get_rest_meta() { return restMeta; }",
    ),
  )
  let _ = try? @fs.rmdir(root, recursive=true)
}

///|
async test "emit_moonbit_bridge_package rewrites imported iife local const-table computed-key value helpers to bridge.js" {
  let root = wbtest_tmp_project_benchmark_root(
    "bridge_package_imported_iife_local_const_table_computed_destructured_value",
  )
  let _ = try? @fs.rmdir(root, recursive=true)
  @fs.mkdir(root, permission=0o755)
  let _ = emit_moonbit_bridge_package(
    "fixtures/bridge_smoke/imported-iife-local-const-table-entry.ts", "./runtime/imported-iife-local-const-table-entry.js",
    root,
  )
  let bridge_mbt = @fs.read_file(wbtest_join_path(root, "bridge.mbt")).text() catch {
    e => {
      fail("Read error: \{e}")
      return
    }
  }
  let bridge_js = @fs.read_file(wbtest_join_path(root, "bridge.js")).text() catch {
    e => {
      fail("Read error: \{e}")
      return
    }
  }
  let bridge_js_path = "@tsmbt-bridge/" + wbtest_basename(root)
  assert_true(bridge_mbt.contains("pub(all) struct RestMeta"))
  assert_true(
    bridge_mbt.contains(
      "#module(\"\{bridge_js_path}\")\npub extern \"js\" fn get_runtime_version() -> String = \"__ts_mbt_get_runtime_version\"",
    ),
  )
  assert_true(
    bridge_mbt.contains(
      "#module(\"\{bridge_js_path}\")\npub extern \"js\" fn get_build() -> Double = \"__ts_mbt_get_build\"",
    ),
  )
  assert_true(
    bridge_mbt.contains(
      "#module(\"\{bridge_js_path}\")\npub extern \"js\" fn get_rest_meta() -> RestMeta = \"__ts_mbt_get_rest_meta\"",
    ),
  )
  assert_true(
    bridge_js.contains(
      "import { build, restMeta, runtimeVersion } from \"./runtime/imported-iife-local-const-table-entry.js\";",
    ),
  )
  assert_true(
    bridge_js.contains(
      "export function __ts_mbt_get_rest_meta() { return restMeta; }",
    ),
  )
  let _ = try? @fs.rmdir(root, recursive=true)
}

///|
async test "emit_moonbit_bridge_package rewrites imported function iife local const-table computed-key value helpers to bridge.js" {
  let root = wbtest_tmp_project_benchmark_root(
    "bridge_package_imported_function_iife_local_const_table_computed_destructured_value",
  )
  let _ = try? @fs.rmdir(root, recursive=true)
  @fs.mkdir(root, permission=0o755)
  let _ = emit_moonbit_bridge_package(
    "fixtures/bridge_smoke/imported-function-iife-local-const-table-entry.ts", "./runtime/imported-function-iife-local-const-table-entry.js",
    root,
  )
  let bridge_mbt = @fs.read_file(wbtest_join_path(root, "bridge.mbt")).text() catch {
    e => {
      fail("Read error: \{e}")
      return
    }
  }
  let bridge_js = @fs.read_file(wbtest_join_path(root, "bridge.js")).text() catch {
    e => {
      fail("Read error: \{e}")
      return
    }
  }
  let bridge_js_path = "@tsmbt-bridge/" + wbtest_basename(root)
  assert_true(bridge_mbt.contains("pub(all) struct RestMeta"))
  assert_true(
    bridge_mbt.contains(
      "#module(\"\{bridge_js_path}\")\npub extern \"js\" fn get_runtime_version() -> String = \"__ts_mbt_get_runtime_version\"",
    ),
  )
  assert_true(
    bridge_mbt.contains(
      "#module(\"\{bridge_js_path}\")\npub extern \"js\" fn get_build() -> Double = \"__ts_mbt_get_build\"",
    ),
  )
  assert_true(
    bridge_mbt.contains(
      "#module(\"\{bridge_js_path}\")\npub extern \"js\" fn get_rest_meta() -> RestMeta = \"__ts_mbt_get_rest_meta\"",
    ),
  )
  assert_true(
    bridge_js.contains(
      "import { build, restMeta, runtimeVersion } from \"./runtime/imported-function-iife-local-const-table-entry.js\";",
    ),
  )
  assert_true(
    bridge_js.contains(
      "export function __ts_mbt_get_rest_meta() { return restMeta; }",
    ),
  )
  let _ = try? @fs.rmdir(root, recursive=true)
}

///|
async test "emit_moonbit_bridge_package rewrites imported iife local let-table computed-key value helpers to bridge.js" {
  let root = wbtest_tmp_project_benchmark_root(
    "bridge_package_imported_iife_local_let_table_computed_destructured_value",
  )
  let _ = try? @fs.rmdir(root, recursive=true)
  @fs.mkdir(root, permission=0o755)
  let _ = emit_moonbit_bridge_package(
    "fixtures/bridge_smoke/imported-iife-local-let-table-entry.ts", "./runtime/imported-iife-local-let-table-entry.js",
    root,
  )
  let bridge_mbt = @fs.read_file(wbtest_join_path(root, "bridge.mbt")).text() catch {
    e => {
      fail("Read error: \{e}")
      return
    }
  }
  let bridge_js = @fs.read_file(wbtest_join_path(root, "bridge.js")).text() catch {
    e => {
      fail("Read error: \{e}")
      return
    }
  }
  let bridge_js_path = "@tsmbt-bridge/" + wbtest_basename(root)
  assert_true(bridge_mbt.contains("pub(all) struct RestMeta"))
  assert_true(
    bridge_mbt.contains(
      "#module(\"\{bridge_js_path}\")\npub extern \"js\" fn get_runtime_version() -> String = \"__ts_mbt_get_runtime_version\"",
    ),
  )
  assert_true(
    bridge_mbt.contains(
      "#module(\"\{bridge_js_path}\")\npub extern \"js\" fn get_build() -> Double = \"__ts_mbt_get_build\"",
    ),
  )
  assert_true(
    bridge_mbt.contains(
      "#module(\"\{bridge_js_path}\")\npub extern \"js\" fn get_rest_meta() -> RestMeta = \"__ts_mbt_get_rest_meta\"",
    ),
  )
  assert_true(
    bridge_js.contains(
      "import { build, restMeta, runtimeVersion } from \"./runtime/imported-iife-local-let-table-entry.js\";",
    ),
  )
  assert_true(
    bridge_js.contains(
      "export function __ts_mbt_get_rest_meta() { return restMeta; }",
    ),
  )
  let _ = try? @fs.rmdir(root, recursive=true)
}

///|
async test "emit_moonbit_bridge_package rewrites imported function iife local let-table computed-key value helpers to bridge.js" {
  let root = wbtest_tmp_project_benchmark_root(
    "bridge_package_imported_function_iife_local_let_table_computed_destructured_value",
  )
  let _ = try? @fs.rmdir(root, recursive=true)
  @fs.mkdir(root, permission=0o755)
  let _ = emit_moonbit_bridge_package(
    "fixtures/bridge_smoke/imported-function-iife-local-let-table-entry.ts", "./runtime/imported-function-iife-local-let-table-entry.js",
    root,
  )
  let bridge_mbt = @fs.read_file(wbtest_join_path(root, "bridge.mbt")).text() catch {
    e => {
      fail("Read error: \{e}")
      return
    }
  }
  let bridge_js = @fs.read_file(wbtest_join_path(root, "bridge.js")).text() catch {
    e => {
      fail("Read error: \{e}")
      return
    }
  }
  let bridge_js_path = "@tsmbt-bridge/" + wbtest_basename(root)
  assert_true(bridge_mbt.contains("pub(all) struct RestMeta"))
  assert_true(
    bridge_mbt.contains(
      "#module(\"\{bridge_js_path}\")\npub extern \"js\" fn get_runtime_version() -> String = \"__ts_mbt_get_runtime_version\"",
    ),
  )
  assert_true(
    bridge_mbt.contains(
      "#module(\"\{bridge_js_path}\")\npub extern \"js\" fn get_build() -> Double = \"__ts_mbt_get_build\"",
    ),
  )
  assert_true(
    bridge_mbt.contains(
      "#module(\"\{bridge_js_path}\")\npub extern \"js\" fn get_rest_meta() -> RestMeta = \"__ts_mbt_get_rest_meta\"",
    ),
  )
  assert_true(
    bridge_js.contains(
      "import { build, restMeta, runtimeVersion } from \"./runtime/imported-function-iife-local-let-table-entry.js\";",
    ),
  )
  assert_true(
    bridge_js.contains(
      "export function __ts_mbt_get_rest_meta() { return restMeta; }",
    ),
  )
  let _ = try? @fs.rmdir(root, recursive=true)
}

///|
async test "emit_moonbit_bridge_package widens imported reassigned local let-table computed-key value helpers to bridge.js" {
  let root = wbtest_tmp_project_benchmark_root(
    "bridge_package_imported_iife_reassigned_let_table_computed_destructured_value",
  )
  let _ = try? @fs.rmdir(root, recursive=true)
  @fs.mkdir(root, permission=0o755)
  let _ = emit_moonbit_bridge_package(
    "fixtures/bridge_smoke/imported-iife-reassigned-let-table-entry.ts", "./runtime/imported-iife-reassigned-let-table-entry.js",
    root,
  )
  let bridge_mbt = @fs.read_file(wbtest_join_path(root, "bridge.mbt")).text() catch {
    e => {
      fail("Read error: \{e}")
      return
    }
  }
  let bridge_js = @fs.read_file(wbtest_join_path(root, "bridge.js")).text() catch {
    e => {
      fail("Read error: \{e}")
      return
    }
  }
  let bridge_js_path = "@tsmbt-bridge/" + wbtest_basename(root)
  assert_false(bridge_mbt.contains("pub(all) struct RestMeta"))
  assert_true(
    bridge_mbt.contains(
      "#module(\"\{bridge_js_path}\")\npub extern \"js\" fn get_runtime_version() -> JSValue = \"__ts_mbt_get_runtime_version\"",
    ),
  )
  assert_true(
    bridge_mbt.contains(
      "#module(\"\{bridge_js_path}\")\npub extern \"js\" fn get_build() -> JSValue = \"__ts_mbt_get_build\"",
    ),
  )
  assert_true(
    bridge_mbt.contains(
      "#module(\"\{bridge_js_path}\")\npub extern \"js\" fn get_rest_meta() -> JSValue = \"__ts_mbt_get_rest_meta\"",
    ),
  )
  assert_true(
    bridge_js.contains(
      "import { build, restMeta, runtimeVersion } from \"./runtime/imported-iife-reassigned-let-table-entry.js\";",
    ),
  )
  let _ = try? @fs.rmdir(root, recursive=true)
}

///|
async test "emit_moonbit_bridge_package widens imported prop-mutated local let-table computed-key value helpers to bridge.js" {
  let root = wbtest_tmp_project_benchmark_root(
    "bridge_package_imported_iife_prop_mutated_let_table_computed_destructured_value",
  )
  let _ = try? @fs.rmdir(root, recursive=true)
  @fs.mkdir(root, permission=0o755)
  let _ = emit_moonbit_bridge_package(
    "fixtures/bridge_smoke/imported-iife-prop-mutated-let-table-entry.ts", "./runtime/imported-iife-prop-mutated-let-table-entry.js",
    root,
  )
  let bridge_mbt = @fs.read_file(wbtest_join_path(root, "bridge.mbt")).text() catch {
    e => {
      fail("Read error: \{e}")
      return
    }
  }
  let bridge_js = @fs.read_file(wbtest_join_path(root, "bridge.js")).text() catch {
    e => {
      fail("Read error: \{e}")
      return
    }
  }
  let bridge_js_path = "@tsmbt-bridge/" + wbtest_basename(root)
  assert_false(bridge_mbt.contains("pub(all) struct RestMeta"))
  assert_true(
    bridge_mbt.contains(
      "#module(\"\{bridge_js_path}\")\npub extern \"js\" fn get_runtime_version() -> JSValue = \"__ts_mbt_get_runtime_version\"",
    ),
  )
  assert_true(
    bridge_mbt.contains(
      "#module(\"\{bridge_js_path}\")\npub extern \"js\" fn get_build() -> JSValue = \"__ts_mbt_get_build\"",
    ),
  )
  assert_true(
    bridge_mbt.contains(
      "#module(\"\{bridge_js_path}\")\npub extern \"js\" fn get_rest_meta() -> JSValue = \"__ts_mbt_get_rest_meta\"",
    ),
  )
  assert_true(
    bridge_js.contains(
      "import { build, restMeta, runtimeVersion } from \"./runtime/imported-iife-prop-mutated-let-table-entry.js\";",
    ),
  )
  let _ = try? @fs.rmdir(root, recursive=true)
}

///|
async test "emit_moonbit_bridge_package widens imported index-mutated local let-table computed-key value helpers to bridge.js" {
  let root = wbtest_tmp_project_benchmark_root(
    "bridge_package_imported_function_iife_index_mutated_let_table_computed_destructured_value",
  )
  let _ = try? @fs.rmdir(root, recursive=true)
  @fs.mkdir(root, permission=0o755)
  let _ = emit_moonbit_bridge_package(
    "fixtures/bridge_smoke/imported-function-iife-index-mutated-let-table-entry.ts",
    "./runtime/imported-function-iife-index-mutated-let-table-entry.js", root,
  )
  let bridge_mbt = @fs.read_file(wbtest_join_path(root, "bridge.mbt")).text() catch {
    e => {
      fail("Read error: \{e}")
      return
    }
  }
  let bridge_js = @fs.read_file(wbtest_join_path(root, "bridge.js")).text() catch {
    e => {
      fail("Read error: \{e}")
      return
    }
  }
  let bridge_js_path = "@tsmbt-bridge/" + wbtest_basename(root)
  assert_false(bridge_mbt.contains("pub(all) struct RestMeta"))
  assert_true(
    bridge_mbt.contains(
      "#module(\"\{bridge_js_path}\")\npub extern \"js\" fn get_runtime_version() -> JSValue = \"__ts_mbt_get_runtime_version\"",
    ),
  )
  assert_true(
    bridge_mbt.contains(
      "#module(\"\{bridge_js_path}\")\npub extern \"js\" fn get_build() -> JSValue = \"__ts_mbt_get_build\"",
    ),
  )
  assert_true(
    bridge_mbt.contains(
      "#module(\"\{bridge_js_path}\")\npub extern \"js\" fn get_rest_meta() -> JSValue = \"__ts_mbt_get_rest_meta\"",
    ),
  )
  assert_true(
    bridge_js.contains(
      "import { build, restMeta, runtimeVersion } from \"./runtime/imported-function-iife-index-mutated-let-table-entry.js\";",
    ),
  )
  let _ = try? @fs.rmdir(root, recursive=true)
}

///|
async test "emit_moonbit_bridge_package rewrites imported reexported const-table computed-key value helpers to bridge.js" {
  let root = wbtest_tmp_project_benchmark_root(
    "bridge_package_imported_reexported_const_table_computed_destructured_value",
  )
  let _ = try? @fs.rmdir(root, recursive=true)
  @fs.mkdir(root, permission=0o755)
  let _ = emit_moonbit_bridge_package(
    "fixtures/bridge_smoke/imported-reexported-const-table-entry.ts", "./runtime/imported-reexported-const-table-entry.js",
    root,
  )
  let bridge_mbt = @fs.read_file(wbtest_join_path(root, "bridge.mbt")).text() catch {
    e => {
      fail("Read error: \{e}")
      return
    }
  }
  let bridge_js = @fs.read_file(wbtest_join_path(root, "bridge.js")).text() catch {
    e => {
      fail("Read error: \{e}")
      return
    }
  }
  let bridge_js_path = "@tsmbt-bridge/" + wbtest_basename(root)
  assert_true(bridge_mbt.contains("pub(all) struct RestMeta"))
  assert_true(
    bridge_mbt.contains(
      "#module(\"\{bridge_js_path}\")\npub extern \"js\" fn get_runtime_version() -> String = \"__ts_mbt_get_runtime_version\"",
    ),
  )
  assert_true(
    bridge_mbt.contains(
      "#module(\"\{bridge_js_path}\")\npub extern \"js\" fn get_build() -> Double = \"__ts_mbt_get_build\"",
    ),
  )
  assert_true(
    bridge_mbt.contains(
      "#module(\"\{bridge_js_path}\")\npub extern \"js\" fn get_rest_meta() -> RestMeta = \"__ts_mbt_get_rest_meta\"",
    ),
  )
  assert_true(
    bridge_js.contains(
      "import { build, restMeta, runtimeVersion } from \"./runtime/imported-reexported-const-table-entry.js\";",
    ),
  )
  assert_true(
    bridge_js.contains(
      "export function __ts_mbt_get_rest_meta() { return restMeta; }",
    ),
  )
  let _ = try? @fs.rmdir(root, recursive=true)
}

///|
async test "emit_moonbit_bridge_package rewrites imported chained const-table computed-key value helpers to bridge.js" {
  let root = wbtest_tmp_project_benchmark_root(
    "bridge_package_imported_chained_const_table_computed_destructured_value",
  )
  let _ = try? @fs.rmdir(root, recursive=true)
  @fs.mkdir(root, permission=0o755)
  let _ = emit_moonbit_bridge_package(
    "fixtures/bridge_smoke/imported-chained-const-table-entry.ts", "./runtime/imported-chained-const-table-entry.js",
    root,
  )
  let bridge_mbt = @fs.read_file(wbtest_join_path(root, "bridge.mbt")).text() catch {
    e => {
      fail("Read error: \{e}")
      return
    }
  }
  let bridge_js = @fs.read_file(wbtest_join_path(root, "bridge.js")).text() catch {
    e => {
      fail("Read error: \{e}")
      return
    }
  }
  let bridge_js_path = "@tsmbt-bridge/" + wbtest_basename(root)
  assert_true(bridge_mbt.contains("pub(all) struct RestMeta"))
  assert_true(
    bridge_mbt.contains(
      "#module(\"\{bridge_js_path}\")\npub extern \"js\" fn get_runtime_version() -> String = \"__ts_mbt_get_runtime_version\"",
    ),
  )
  assert_true(
    bridge_mbt.contains(
      "#module(\"\{bridge_js_path}\")\npub extern \"js\" fn get_build() -> Double = \"__ts_mbt_get_build\"",
    ),
  )
  assert_true(
    bridge_mbt.contains(
      "#module(\"\{bridge_js_path}\")\npub extern \"js\" fn get_rest_meta() -> RestMeta = \"__ts_mbt_get_rest_meta\"",
    ),
  )
  assert_true(
    bridge_js.contains(
      "import { build, restMeta, runtimeVersion } from \"./runtime/imported-chained-const-table-entry.js\";",
    ),
  )
  assert_true(
    bridge_js.contains(
      "export function __ts_mbt_get_rest_meta() { return restMeta; }",
    ),
  )
  let _ = try? @fs.rmdir(root, recursive=true)
}

///|
async test "emit_moonbit_bridge_package rewrites imported star const-table computed-key value helpers to bridge.js" {
  let root = wbtest_tmp_project_benchmark_root(
    "bridge_package_imported_star_const_table_computed_destructured_value",
  )
  let _ = try? @fs.rmdir(root, recursive=true)
  @fs.mkdir(root, permission=0o755)
  let _ = emit_moonbit_bridge_package(
    "fixtures/bridge_smoke/imported-star-const-table-entry.ts", "./runtime/imported-star-const-table-entry.js",
    root,
  )
  let bridge_mbt = @fs.read_file(wbtest_join_path(root, "bridge.mbt")).text() catch {
    e => {
      fail("Read error: \{e}")
      return
    }
  }
  let bridge_js = @fs.read_file(wbtest_join_path(root, "bridge.js")).text() catch {
    e => {
      fail("Read error: \{e}")
      return
    }
  }
  let bridge_js_path = "@tsmbt-bridge/" + wbtest_basename(root)
  assert_true(bridge_mbt.contains("pub(all) struct RestMeta"))
  assert_true(
    bridge_mbt.contains(
      "#module(\"\{bridge_js_path}\")\npub extern \"js\" fn get_runtime_version() -> String = \"__ts_mbt_get_runtime_version\"",
    ),
  )
  assert_true(
    bridge_mbt.contains(
      "#module(\"\{bridge_js_path}\")\npub extern \"js\" fn get_build() -> Double = \"__ts_mbt_get_build\"",
    ),
  )
  assert_true(
    bridge_mbt.contains(
      "#module(\"\{bridge_js_path}\")\npub extern \"js\" fn get_rest_meta() -> RestMeta = \"__ts_mbt_get_rest_meta\"",
    ),
  )
  assert_true(
    bridge_js.contains(
      "import { build, restMeta, runtimeVersion } from \"./runtime/imported-star-const-table-entry.js\";",
    ),
  )
  assert_true(
    bridge_js.contains(
      "export function __ts_mbt_get_rest_meta() { return restMeta; }",
    ),
  )
  let _ = try? @fs.rmdir(root, recursive=true)
}

///|
async test "emit_moonbit_bridge_package rewrites imported deep star const-table computed-key value helpers to bridge.js" {
  let root = wbtest_tmp_project_benchmark_root(
    "bridge_package_imported_deep_star_const_table_computed_destructured_value",
  )
  let _ = try? @fs.rmdir(root, recursive=true)
  @fs.mkdir(root, permission=0o755)
  let _ = emit_moonbit_bridge_package(
    "fixtures/bridge_smoke/imported-deep-star-const-table-entry.ts", "./runtime/imported-deep-star-const-table-entry.js",
    root,
  )
  let bridge_mbt = @fs.read_file(wbtest_join_path(root, "bridge.mbt")).text() catch {
    e => {
      fail("Read error: \{e}")
      return
    }
  }
  let bridge_js = @fs.read_file(wbtest_join_path(root, "bridge.js")).text() catch {
    e => {
      fail("Read error: \{e}")
      return
    }
  }
  let bridge_js_path = "@tsmbt-bridge/" + wbtest_basename(root)
  assert_true(bridge_mbt.contains("pub(all) struct RestMeta"))
  assert_true(
    bridge_mbt.contains(
      "#module(\"\{bridge_js_path}\")\npub extern \"js\" fn get_runtime_version() -> String = \"__ts_mbt_get_runtime_version\"",
    ),
  )
  assert_true(
    bridge_mbt.contains(
      "#module(\"\{bridge_js_path}\")\npub extern \"js\" fn get_build() -> Double = \"__ts_mbt_get_build\"",
    ),
  )
  assert_true(
    bridge_mbt.contains(
      "#module(\"\{bridge_js_path}\")\npub extern \"js\" fn get_rest_meta() -> RestMeta = \"__ts_mbt_get_rest_meta\"",
    ),
  )
  assert_true(
    bridge_js.contains(
      "import { build, restMeta, runtimeVersion } from \"./runtime/imported-deep-star-const-table-entry.js\";",
    ),
  )
  assert_true(
    bridge_js.contains(
      "export function __ts_mbt_get_rest_meta() { return restMeta; }",
    ),
  )
  let _ = try? @fs.rmdir(root, recursive=true)
}

///|
async test "emit_moonbit_bridge_package rewrites imported mixed barrel const-table computed-key value helpers to bridge.js" {
  let root = wbtest_tmp_project_benchmark_root(
    "bridge_package_imported_mixed_barrel_const_table_computed_destructured_value",
  )
  let _ = try? @fs.rmdir(root, recursive=true)
  @fs.mkdir(root, permission=0o755)
  let _ = emit_moonbit_bridge_package(
    "fixtures/bridge_smoke/imported-mixed-barrel-const-table-entry.ts", "./runtime/imported-mixed-barrel-const-table-entry.js",
    root,
  )
  let bridge_mbt = @fs.read_file(wbtest_join_path(root, "bridge.mbt")).text() catch {
    e => {
      fail("Read error: \{e}")
      return
    }
  }
  let bridge_js = @fs.read_file(wbtest_join_path(root, "bridge.js")).text() catch {
    e => {
      fail("Read error: \{e}")
      return
    }
  }
  let bridge_js_path = "@tsmbt-bridge/" + wbtest_basename(root)
  assert_true(bridge_mbt.contains("pub(all) struct RestMeta"))
  assert_true(
    bridge_mbt.contains(
      "#module(\"\{bridge_js_path}\")\npub extern \"js\" fn get_runtime_version() -> String = \"__ts_mbt_get_runtime_version\"",
    ),
  )
  assert_true(
    bridge_mbt.contains(
      "#module(\"\{bridge_js_path}\")\npub extern \"js\" fn get_build() -> Double = \"__ts_mbt_get_build\"",
    ),
  )
  assert_true(
    bridge_mbt.contains(
      "#module(\"\{bridge_js_path}\")\npub extern \"js\" fn get_rest_meta() -> RestMeta = \"__ts_mbt_get_rest_meta\"",
    ),
  )
  assert_true(
    bridge_js.contains(
      "import { build, restMeta, runtimeVersion } from \"./runtime/imported-mixed-barrel-const-table-entry.js\";",
    ),
  )
  assert_true(
    bridge_js.contains(
      "export function __ts_mbt_get_rest_meta() { return restMeta; }",
    ),
  )
  let _ = try? @fs.rmdir(root, recursive=true)
}

///|
async test "emit_moonbit_bridge_package widens conflicting star const-table computed-key value helpers to bridge.js" {
  let root = wbtest_tmp_project_benchmark_root(
    "bridge_package_imported_conflicting_star_const_table_computed_destructured_value",
  )
  let _ = try? @fs.rmdir(root, recursive=true)
  @fs.mkdir(root, permission=0o755)
  let _ = emit_moonbit_bridge_package(
    "fixtures/bridge_smoke/imported-conflicting-star-const-table-entry.ts", "./runtime/imported-conflicting-star-const-table-entry.js",
    root,
  )
  let bridge_mbt = @fs.read_file(wbtest_join_path(root, "bridge.mbt")).text() catch {
    e => {
      fail("Read error: \{e}")
      return
    }
  }
  let bridge_js = @fs.read_file(wbtest_join_path(root, "bridge.js")).text() catch {
    e => {
      fail("Read error: \{e}")
      return
    }
  }
  let bridge_js_path = "@tsmbt-bridge/" + wbtest_basename(root)
  assert_false(bridge_mbt.contains("pub(all) struct RestMeta"))
  assert_true(
    bridge_mbt.contains(
      "#module(\"\{bridge_js_path}\")\npub extern \"js\" fn get_runtime_version() -> JSValue = \"__ts_mbt_get_runtime_version\"",
    ),
  )
  assert_true(
    bridge_mbt.contains(
      "#module(\"\{bridge_js_path}\")\npub extern \"js\" fn get_build() -> JSValue = \"__ts_mbt_get_build\"",
    ),
  )
  assert_true(
    bridge_mbt.contains(
      "#module(\"\{bridge_js_path}\")\npub extern \"js\" fn get_rest_meta() -> JSValue = \"__ts_mbt_get_rest_meta\"",
    ),
  )
  assert_true(
    bridge_js.contains(
      "import { build, restMeta, runtimeVersion } from \"./runtime/imported-conflicting-star-const-table-entry.js\";",
    ),
  )
  let _ = try? @fs.rmdir(root, recursive=true)
}

///|
async test "emit_moonbit_js_ffi_texts handles runtime tsx exported functions" {
  let bundle = emit_moonbit_js_ffi_texts(
    "fixtures/resolver/project/types/runtime-component-entry.tsx", "/runtime/runtime-component.js",
  ) catch {
    @bridge.ModuleGraphError::ReadError(msg)
    | @bridge.ModuleGraphError::ParseError(msg)
    | @bridge.ModuleGraphError::ResolveError(msg) => {
      fail("Emit error: \{msg}")
      return
    }
  }
  assert_true(
    bundle.ffi_mbt.contains(
      "#module(\"/runtime/runtime-component.js\")\npub extern \"js\" fn render_badge(props : BadgeProps) -> JSX_Element = \"renderBadge\"",
    ),
  )
  assert_false(bundle.bridge_js.contains("__ts_mbt_render_badge"))
}

///|
async test "emit_moonbit_js_ffi_texts handles runtime ts exported const arrow functions" {
  let bundle = emit_moonbit_js_ffi_texts(
    "fixtures/resolver/project/types/runtime-arrow-entry.ts", "/runtime/runtime-arrow.js",
  ) catch {
    @bridge.ModuleGraphError::ReadError(msg)
    | @bridge.ModuleGraphError::ParseError(msg)
    | @bridge.ModuleGraphError::ResolveError(msg) => {
      fail("Emit error: \{msg}")
      return
    }
  }
  assert_true(
    bundle.ffi_mbt.contains(
      "#module(\"/runtime/runtime-arrow.js\")\npub extern \"js\" fn scale_arrow_point(point : RuntimeArrowPoint, factor : Double) -> RuntimeArrowPoint = \"scaleArrowPoint\"",
    ),
  )
  assert_false(bundle.bridge_js.contains("__ts_mbt_scale_arrow_point"))
}

///|
async test "emit_moonbit_js_ffi_texts handles runtime ts exported untyped const arrow functions" {
  let bundle = emit_moonbit_js_ffi_texts(
    "fixtures/resolver/project/types/runtime-untyped-arrow-entry.ts", "/runtime/runtime-untyped-arrow.js",
  ) catch {
    @bridge.ModuleGraphError::ReadError(msg)
    | @bridge.ModuleGraphError::ParseError(msg)
    | @bridge.ModuleGraphError::ResolveError(msg) => {
      fail("Emit error: \{msg}")
      return
    }
  }
  assert_true(
    bundle.ffi_mbt.contains(
      "#module(\"/runtime/runtime-untyped-arrow.js\")\npub extern \"js\" fn double_value(value : Double) -> Double = \"doubleValue\"",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "#module(\"/runtime/runtime-untyped-arrow.js\")\npub extern \"js\" fn greet_value(name : String) -> String = \"greetValue\"",
    ),
  )
}

///|
async test "emit_moonbit_js_ffi_texts handles runtime ts function reexports" {
  let bundle = emit_moonbit_js_ffi_texts(
    "fixtures/resolver/project/types/runtime-function-reexport-entry.ts", "/runtime/runtime-function-reexport.js",
  ) catch {
    @bridge.ModuleGraphError::ReadError(msg)
    | @bridge.ModuleGraphError::ParseError(msg)
    | @bridge.ModuleGraphError::ResolveError(msg) => {
      fail("Emit error: \{msg}")
      return
    }
  }
  assert_true(bundle.ffi_mbt.contains("pub extern \"js\" fn scale_point("))
  assert_false(bundle.bridge_js.contains("__ts_mbt_scale_point"))
}

///|
async test "emit_moonbit_decl_text handles runtime default exported classes" {
  let actual = emit_moonbit_decl_text(
    "fixtures/resolver/project/types/runtime-default-class-entry.ts",
  ) catch {
    @bridge.ModuleGraphError::ReadError(msg)
    | @bridge.ModuleGraphError::ParseError(msg)
    | @bridge.ModuleGraphError::ResolveError(msg) => {
      fail("Emit error: \{msg}")
      return
    }
  }
  assert_true(actual.contains("declare pub type Default"))
  assert_true(actual.contains("declare pub fn new_default("))
  assert_true(actual.contains("declare pub fn Default::inc("))
}

///|
async test "emit_moonbit_js_ffi_texts handles runtime default exported classes" {
  let bundle = emit_moonbit_js_ffi_texts(
    "fixtures/resolver/project/types/runtime-default-class-entry.ts", "/runtime/runtime-default-class.js",
  ) catch {
    @bridge.ModuleGraphError::ReadError(msg)
    | @bridge.ModuleGraphError::ParseError(msg)
    | @bridge.ModuleGraphError::ResolveError(msg) => {
      fail("Emit error: \{msg}")
      return
    }
  }
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn new_default(initial : Double) -> Default = \"__ts_mbt_new_default\"",
    ),
  )
  assert_true(
    bundle.bridge_js.contains(
      "import default_ from \"/runtime/runtime-default-class.js\";",
    ),
  )
  assert_true(
    bundle.bridge_js.contains(
      "export function __ts_mbt_new_default(initial) { return new default_(initial); }",
    ),
  )
}

///|
async test "emit_moonbit_decl_text handles export assignment declarations" {
  let actual = emit_moonbit_decl_text(
    "fixtures/resolver/project/types/export-equals-entry.d.ts",
  ) catch {
    @bridge.ModuleGraphError::ReadError(msg)
    | @bridge.ModuleGraphError::ParseError(msg)
    | @bridge.ModuleGraphError::ResolveError(msg) => {
      fail("Emit error: \{msg}")
      return
    }
  }
  assert_true(actual.contains("declare pub fn get_default() -> JSValue"))
}

///|
async test "emit_moonbit_js_ffi_texts handles export assignment declarations" {
  let bundle = emit_moonbit_js_ffi_texts(
    "fixtures/resolver/project/types/export-equals-entry.d.ts", "./runtime/export-equals.js",
  ) catch {
    @bridge.ModuleGraphError::ReadError(msg)
    | @bridge.ModuleGraphError::ParseError(msg)
    | @bridge.ModuleGraphError::ResolveError(msg) => {
      fail("Emit error: \{msg}")
      return
    }
  }
  assert_true(bundle.ffi_mbt.contains("pub extern \"js\" fn get_default()"))
  assert_true(bundle.bridge_js.contains("export function __ts_mbt_get_default"))
}

///|
async test "emit_moonbit_scaffold_from_ts handles export as namespace declarations" {
  let root = wbtest_tmp_project_benchmark_root(
    "bridge_scaffold_export_as_namespace",
  )
  let _ = try? @fs.rmdir(root, recursive=true)
  @fs.mkdir(root, permission=0o755)
  let _ = emit_moonbit_scaffold_from_ts(
    "fixtures/resolver/project/types/export-as-namespace-entry.d.ts", "./runtime/react-like.js",
    root,
  )
  let bridge_mbti = @fs.read_file(wbtest_join_path(root, "bridge.mbti")).text() catch {
    e => fail("failed to read export-as-namespace bridge.mbti: \{e}")
  }
  let bridge_mbt = @fs.read_file(wbtest_join_path(root, "bridge.mbt")).text() catch {
    e => fail("failed to read export-as-namespace bridge.mbt: \{e}")
  }
  assert_true(bridge_mbti.contains("pub(all) struct Context[T] {"))
  assert_true(
    bridge_mbti.contains(
      "declare pub fn createContext(defaultValue : JSValue) -> Context[JSValue]",
    ),
  )
  assert_true(bridge_mbti.contains("declare pub fn get_default() -> JSValue"))
  assert_true(
    bridge_mbt.contains(
      "pub fn createContext(defaultValue : JSValue) -> Context[JSValue] {\n  create_context(defaultValue)\n}",
    ),
  )
  assert_true(@fs.exists(wbtest_join_path(root, "SCAFFOLD_DIAGNOSTICS.md")))
}

///|
async test "emit_moonbit_scaffold_from_ts handles export as namespace ambient members" {
  let root = wbtest_tmp_project_benchmark_root(
    "bridge_scaffold_export_as_namespace_ambient_members",
  )
  let _ = try? @fs.rmdir(root, recursive=true)
  @fs.mkdir(root, permission=0o755)
  let _ = emit_moonbit_scaffold_from_ts(
    "fixtures/resolver/project/types/export-as-namespace-ambient-members-entry.d.ts",
    "./runtime/react-like.js", root,
  )
  let bridge_mbti = @fs.read_file(wbtest_join_path(root, "bridge.mbti")).text() catch {
    e => fail("failed to read export-as-namespace ambient bridge.mbti: \{e}")
  }
  assert_true(bridge_mbti.contains("declare pub fn get_version() -> String"))
  assert_true(bridge_mbti.contains("declare pub type Component"))
  assert_true(
    bridge_mbti.contains(
      "declare pub fn useContext(context : Context[JSValue]) -> JSValue",
    ),
  )
  assert_true(@fs.exists(wbtest_join_path(root, "SCAFFOLD_DIAGNOSTICS.md")))
}

///|
async test "emit_moonbit_scaffold_from_ts handles export as namespace hook tuple members" {
  let root = wbtest_tmp_project_benchmark_root(
    "bridge_scaffold_export_as_namespace_hook_tuple",
  )
  let _ = try? @fs.rmdir(root, recursive=true)
  @fs.mkdir(root, permission=0o755)
  let _ = emit_moonbit_scaffold_from_ts(
    "fixtures/resolver/project/types/export-as-namespace-hook-tuple-entry.d.ts",
    "./runtime/react-like.js", root,
  )
  let bridge_mbti = @fs.read_file(wbtest_join_path(root, "bridge.mbti")).text() catch {
    e => fail("failed to read export-as-namespace hook tuple bridge.mbti: \{e}")
  }
  let bridge_mbt = @fs.read_file(wbtest_join_path(root, "bridge.mbt")).text() catch {
    e => fail("failed to read export-as-namespace hook tuple bridge.mbt: \{e}")
  }
  assert_true(bridge_mbti.contains("pub(all) struct UseStateResult"))
  assert_true(bridge_mbti.contains("/// state : JSValue"))
  assert_true(bridge_mbti.contains("/// setState : Dispatch"))
  assert_true(bridge_mbti.contains("pub(all) struct UseReducerResult"))
  assert_true(bridge_mbti.contains("/// dispatch : ActionDispatch"))
  assert_true(bridge_mbti.contains("pub(all) struct UseTransitionResult"))
  assert_true(bridge_mbti.contains("/// isPending : Bool"))
  assert_true(bridge_mbti.contains("/// startTransition : TransitionFunction"))
  assert_true(bridge_mbti.contains("pub(all) struct UseOptimisticResult"))
  assert_true(bridge_mbti.contains("pub(all) struct UseActionStateResult"))
  assert_true(
    bridge_mbti.contains(
      "declare pub fn useState(initialState : JSValue) -> UseStateResult",
    ),
  )
  assert_true(
    bridge_mbti.contains(
      "declare pub fn useReducer(reducer : UseReducerReducerCallback, initialState : JSValue) -> UseReducerResult",
    ),
  )
  assert_true(
    bridge_mbti.contains(
      "declare pub fn useTransition() -> UseTransitionResult",
    ),
  )
  assert_true(
    bridge_mbti.contains(
      "declare pub fn useOptimistic(passthrough : State) -> UseOptimisticResult",
    ),
  )
  assert_true(
    bridge_mbti.contains(
      "declare pub fn useActionState(action : async (State) -> State raise, initialState : State, permalink : String?) -> UseActionStateResult",
    ),
  )
  assert_true(
    bridge_mbt.contains(
      "pub fn useState(initialState : JSValue) -> UseStateResult {\n  use_state(initialState)\n}",
    ),
  )
  assert_true(
    bridge_mbt.contains(
      "pub fn useReducer(reducer : UseReducerReducerCallback, initialState : JSValue) -> UseReducerResult {\n  use_reducer(reducer, initialState)\n}",
    ),
  )
  assert_true(
    bridge_mbt.contains(
      "pub fn useTransition() -> UseTransitionResult {\n  use_transition()\n}",
    ),
  )
  assert_true(
    bridge_mbt.contains(
      "pub fn useOptimistic(passthrough : State) -> UseOptimisticResult {\n  use_optimistic(passthrough)\n}",
    ),
  )
  assert_true(
    bridge_mbt.contains(
      // The scaffold surface takes a MoonBit async fn directly: the
      // wrapper glues it back into a promise-returning JS callback.
      "pub fn useActionState(action : async (State) -> State raise, initialState : State, permalink : String?) -> UseActionStateResult {\n  use_action_state(fn(__ts_mbt_cb_a0) { Promise::from_async(async fn() raise { action(__ts_mbt_cb_a0) }) }, initialState, permalink)\n}",
    ),
  )
  assert_true(@fs.exists(wbtest_join_path(root, "SCAFFOLD_DIAGNOSTICS.md")))
}

///|
async test "emit_moonbit_scaffold_from_ts handles export as namespace JSX namespace members" {
  let root = wbtest_tmp_project_benchmark_root(
    "bridge_scaffold_export_as_namespace_jsx",
  )
  let _ = try? @fs.rmdir(root, recursive=true)
  @fs.mkdir(root, permission=0o755)
  let _ = emit_moonbit_scaffold_from_ts(
    "fixtures/resolver/project/types/export-as-namespace-jsx-entry.d.ts", "./runtime/react-like.js",
    root,
  )
  let bridge_mbti = @fs.read_file(wbtest_join_path(root, "bridge.mbti")).text() catch {
    e => fail("failed to read export-as-namespace jsx bridge.mbti: \{e}")
  }
  let bridge_mbt = @fs.read_file(wbtest_join_path(root, "bridge.mbt")).text() catch {
    e => fail("failed to read export-as-namespace jsx bridge.mbt: \{e}")
  }
  assert_true(bridge_mbti.contains("pub(all) struct JsxElement"))
  assert_true(bridge_mbti.contains("pub(all) struct JsxIntrinsicElements"))
  assert_true(
    bridge_mbti.contains(
      "declare pub fn createElement(tag : String) -> JsxElement",
    ),
  )
  assert_true(bridge_mbt.contains("pub(all) struct JsxElement {"))
  assert_true(
    bridge_mbt.contains(
      "pub fn createElement(tag : String) -> JsxElement {\n  create_element(tag)\n}",
    ),
  )
  assert_true(@fs.exists(wbtest_join_path(root, "SCAFFOLD_DIAGNOSTICS.md")))
}

///|
async test "emit_moonbit_scaffold_from_ts handles export as namespace JSX constructor signatures" {
  let root = wbtest_tmp_project_benchmark_root(
    "bridge_scaffold_export_as_namespace_jsx_constructor",
  )
  let _ = try? @fs.rmdir(root, recursive=true)
  @fs.mkdir(root, permission=0o755)
  let _ = emit_moonbit_scaffold_from_ts(
    "fixtures/resolver/project/types/export-as-namespace-jsx-constructor-entry.d.ts",
    "./runtime/react-like.js", root,
  )
  let bridge_mbti = @fs.read_file(wbtest_join_path(root, "bridge.mbti")).text() catch {
    e =>
      fail(
        "failed to read export-as-namespace jsx constructor bridge.mbti: \{e}",
      )
  }
  assert_true(bridge_mbti.contains("declare pub fn get_default() -> JSValue"))
  assert_true(@fs.exists(wbtest_join_path(root, "SCAFFOLD_DIAGNOSTICS.md")))
}

///|
async test "emit_moonbit_scaffold_from_ts handles export as namespace conditional utility signatures" {
  let root = wbtest_tmp_project_benchmark_root(
    "bridge_scaffold_export_as_namespace_conditional_utility",
  )
  let _ = try? @fs.rmdir(root, recursive=true)
  @fs.mkdir(root, permission=0o755)
  let _ = emit_moonbit_scaffold_from_ts(
    "fixtures/resolver/project/types/export-as-namespace-conditional-utility-entry.d.ts",
    "./runtime/react-like.js", root,
  )
  let bridge_mbti = @fs.read_file(wbtest_join_path(root, "bridge.mbti")).text() catch {
    e =>
      fail(
        "failed to read export-as-namespace conditional utility bridge.mbti: \{e}",
      )
  }
  assert_true(bridge_mbti.contains("declare pub fn get_default() -> JSValue"))
  assert_true(@fs.exists(wbtest_join_path(root, "SCAFFOLD_DIAGNOSTICS.md")))
}

///|
async test "emit_moonbit_scaffold_from_ts handles exported JSX namespace members" {
  let root = wbtest_tmp_project_benchmark_root(
    "bridge_scaffold_exported_jsx_namespace",
  )
  let _ = try? @fs.rmdir(root, recursive=true)
  @fs.mkdir(root, permission=0o755)
  let _ = emit_moonbit_scaffold_from_ts(
    "fixtures/resolver/project/types/exported-jsx-namespace-entry.d.ts", "react/jsx-runtime",
    root,
  )
  let bridge_mbti = @fs.read_file(wbtest_join_path(root, "bridge.mbti")).text() catch {
    e => fail("failed to read exported jsx namespace bridge.mbti: \{e}")
  }
  let bridge_mbt = @fs.read_file(wbtest_join_path(root, "bridge.mbt")).text() catch {
    e => fail("failed to read exported jsx namespace bridge.mbt: \{e}")
  }
  assert_true(bridge_mbti.contains("pub(all) struct JsxElement"))
  assert_true(bridge_mbti.contains("pub(all) struct JsxIntrinsicElements"))
  assert_true(
    bridge_mbti.contains(
      "declare pub fn jsx(tag : String, props : BadgeProps) -> JsxElement",
    ),
  )
  assert_false(bridge_mbti.contains("declare pub fn get_jsx()"))
  assert_true(
    bridge_mbt.contains(
      "#module(\"react/jsx-runtime\")\npub extern \"js\" fn jsx(tag : String, props : BadgeProps) -> JsxElement = \"jsx\"",
    ),
  )
  assert_true(@fs.exists(wbtest_join_path(root, "SCAFFOLD_DIAGNOSTICS.md")))
}

///|
async test "emit_moonbit_scaffold_from_ts handles export as namespace PropsWithChildren members" {
  let root = wbtest_tmp_project_benchmark_root(
    "bridge_scaffold_export_as_namespace_props_with_children",
  )
  let _ = try? @fs.rmdir(root, recursive=true)
  @fs.mkdir(root, permission=0o755)
  let _ = emit_moonbit_scaffold_from_ts(
    "fixtures/resolver/project/types/export-as-namespace-props-with-children-entry.d.ts",
    "./runtime/react-like.js", root,
  )
  let bridge_mbti = @fs.read_file(wbtest_join_path(root, "bridge.mbti")).text() catch {
    e =>
      fail(
        "failed to read export-as-namespace props-with-children bridge.mbti: \{e}",
      )
  }
  let bridge_mbt = @fs.read_file(wbtest_join_path(root, "bridge.mbt")).text() catch {
    e =>
      fail(
        "failed to read export-as-namespace props-with-children bridge.mbt: \{e}",
      )
  }
  assert_true(bridge_mbti.contains("pub(all) struct BadgePropsWithChildren"))
  assert_true(
    bridge_mbti.contains(
      "declare pub fn createBadge(props : BadgePropsWithChildren) -> BadgePropsWithChildren",
    ),
  )
  assert_false(bridge_mbti.contains("declare pub type PropsWithChildren"))
  assert_true(bridge_mbt.contains("pub(all) struct BadgePropsWithChildren {"))
  assert_true(
    bridge_mbt.contains(
      "pub fn createBadge(props : BadgePropsWithChildren) -> BadgePropsWithChildren {\n  create_badge(props)\n}",
    ),
  )
  assert_true(@fs.exists(wbtest_join_path(root, "SCAFFOLD_DIAGNOSTICS.md")))
}

///|
async test "emit_moonbit_scaffold_from_ts handles export as namespace ComponentProps members" {
  let root = wbtest_tmp_project_benchmark_root(
    "bridge_scaffold_export_as_namespace_component_props",
  )
  let _ = try? @fs.rmdir(root, recursive=true)
  @fs.mkdir(root, permission=0o755)
  let _ = emit_moonbit_scaffold_from_ts(
    "fixtures/resolver/project/types/export-as-namespace-component-props-entry.d.ts",
    "./runtime/react-like.js", root,
  )
  let bridge_mbti = @fs.read_file(wbtest_join_path(root, "bridge.mbti")).text() catch {
    e =>
      fail(
        "failed to read export-as-namespace component-props bridge.mbti: \{e}",
      )
  }
  let bridge_mbt = @fs.read_file(wbtest_join_path(root, "bridge.mbt")).text() catch {
    e =>
      fail(
        "failed to read export-as-namespace component-props bridge.mbt: \{e}",
      )
  }
  assert_true(bridge_mbti.contains("pub(all) struct BadgeProps"))
  assert_true(
    bridge_mbti.contains(
      "declare pub fn createBadge(props : BadgeProps) -> BadgeProps",
    ),
  )
  assert_false(bridge_mbti.contains("declare pub type ComponentProps"))
  assert_true(
    bridge_mbt.contains(
      "pub fn createBadge(props : BadgeProps) -> BadgeProps {\n  create_badge(props)\n}",
    ),
  )
  assert_true(@fs.exists(wbtest_join_path(root, "SCAFFOLD_DIAGNOSTICS.md")))
}

///|
async test "emit_moonbit_scaffold_from_ts handles export as namespace ComponentPropsWithoutRef members" {
  let root = wbtest_tmp_project_benchmark_root(
    "bridge_scaffold_export_as_namespace_component_props_without_ref",
  )
  let _ = try? @fs.rmdir(root, recursive=true)
  @fs.mkdir(root, permission=0o755)
  let _ = emit_moonbit_scaffold_from_ts(
    "fixtures/resolver/project/types/export-as-namespace-component-props-without-ref-entry.d.ts",
    "./runtime/react-like.js", root,
  )
  let bridge_mbti = @fs.read_file(wbtest_join_path(root, "bridge.mbti")).text() catch {
    e =>
      fail(
        "failed to read export-as-namespace component-props-without-ref bridge.mbti: \{e}",
      )
  }
  assert_true(bridge_mbti.contains("pub(all) struct BadgeProps"))
  assert_true(
    bridge_mbti.contains(
      "declare pub fn createBadge(props : BadgeProps) -> BadgeProps",
    ),
  )
  assert_false(
    bridge_mbti.contains("declare pub type ComponentPropsWithoutRef"),
  )
  assert_true(@fs.exists(wbtest_join_path(root, "SCAFFOLD_DIAGNOSTICS.md")))
}

///|
async test "emit_moonbit_scaffold_from_ts handles export as namespace ComponentPropsWithRef members" {
  let root = wbtest_tmp_project_benchmark_root(
    "bridge_scaffold_export_as_namespace_component_props_with_ref",
  )
  let _ = try? @fs.rmdir(root, recursive=true)
  @fs.mkdir(root, permission=0o755)
  let _ = emit_moonbit_scaffold_from_ts(
    "fixtures/resolver/project/types/export-as-namespace-component-props-with-ref-entry.d.ts",
    "./runtime/react-like.js", root,
  )
  let bridge_mbti = @fs.read_file(wbtest_join_path(root, "bridge.mbti")).text() catch {
    e =>
      fail(
        "failed to read export-as-namespace component-props-with-ref bridge.mbti: \{e}",
      )
  }
  let bridge_mbt = @fs.read_file(wbtest_join_path(root, "bridge.mbt")).text() catch {
    e =>
      fail(
        "failed to read export-as-namespace component-props-with-ref bridge.mbt: \{e}",
      )
  }
  assert_true(bridge_mbti.contains("pub(all) struct BadgePropsWithRef"))
  assert_true(bridge_mbti.contains("pub(all) struct Ref"))
  assert_true(
    bridge_mbti.contains(
      "declare pub fn createBadge(props : BadgePropsWithRef) -> BadgePropsWithRef",
    ),
  )
  assert_true(bridge_mbt.contains("pub(all) struct BadgePropsWithRef {"))
  assert_false(bridge_mbti.contains("declare pub type ComponentPropsWithRef"))
  assert_true(@fs.exists(wbtest_join_path(root, "SCAFFOLD_DIAGNOSTICS.md")))
}

///|
async test "emit_moonbit_scaffold_from_ts handles export as namespace nested PropsWithChildren members" {
  let root = wbtest_tmp_project_benchmark_root(
    "bridge_scaffold_export_as_namespace_nested_props_with_children",
  )
  let _ = try? @fs.rmdir(root, recursive=true)
  @fs.mkdir(root, permission=0o755)
  let _ = emit_moonbit_scaffold_from_ts(
    "fixtures/resolver/project/types/export-as-namespace-nested-props-with-children-entry.d.ts",
    "./runtime/react-like.js", root,
  )
  let bridge_mbti = @fs.read_file(wbtest_join_path(root, "bridge.mbti")).text() catch {
    e =>
      fail(
        "failed to read export-as-namespace nested props-with-children bridge.mbti: \{e}",
      )
  }
  let bridge_mbt = @fs.read_file(wbtest_join_path(root, "bridge.mbt")).text() catch {
    e =>
      fail(
        "failed to read export-as-namespace nested props-with-children bridge.mbt: \{e}",
      )
  }
  assert_true(bridge_mbti.contains("pub(all) struct BadgePropsWithChildren"))
  assert_true(
    bridge_mbti.contains(
      "declare pub fn createBadge(props : BadgePropsWithChildren) -> BadgePropsWithChildren",
    ),
  )
  assert_true(bridge_mbt.contains("pub(all) struct BadgePropsWithChildren {"))
  assert_false(bridge_mbti.contains("declare pub type PropsWithChildren"))
  assert_false(
    bridge_mbti.contains("declare pub type ComponentPropsWithoutRef"),
  )
  assert_true(@fs.exists(wbtest_join_path(root, "SCAFFOLD_DIAGNOSTICS.md")))
}

///|
async test "emit_moonbit_scaffold_from_ts handles export as namespace PropsWithoutRef and PropsWithRef members" {
  let root = wbtest_tmp_project_benchmark_root(
    "bridge_scaffold_export_as_namespace_props_ref_alias",
  )
  let _ = try? @fs.rmdir(root, recursive=true)
  @fs.mkdir(root, permission=0o755)
  let _ = emit_moonbit_scaffold_from_ts(
    "fixtures/resolver/project/types/export-as-namespace-props-ref-alias-entry.d.ts",
    "./runtime/react-like.js", root,
  )
  let bridge_mbti = @fs.read_file(wbtest_join_path(root, "bridge.mbti")).text() catch {
    e =>
      fail(
        "failed to read export-as-namespace props-ref-alias bridge.mbti: \{e}",
      )
  }
  assert_true(bridge_mbti.contains("pub(all) struct BadgeProps"))
  assert_true(bridge_mbti.contains("pub(all) struct BadgePropsWithChildren"))
  assert_true(
    bridge_mbti.contains(
      "declare pub fn stripRef(props : BadgeProps) -> BadgeProps",
    ),
  )
  assert_true(
    bridge_mbti.contains(
      "declare pub fn keepRef(props : BadgeProps) -> BadgeProps",
    ),
  )
  assert_true(
    bridge_mbti.contains(
      "declare pub fn nested(props : BadgePropsWithChildren) -> BadgePropsWithChildren",
    ),
  )
  assert_false(bridge_mbti.contains("declare pub type PropsWithoutRef"))
  assert_false(bridge_mbti.contains("declare pub type PropsWithRef"))
  assert_true(@fs.exists(wbtest_join_path(root, "SCAFFOLD_DIAGNOSTICS.md")))
}

///|
async test "emit_moonbit_scaffold_from_ts handles export as namespace optional React-like fields" {
  let root = wbtest_tmp_project_benchmark_root(
    "bridge_scaffold_export_as_namespace_optional_react_fields",
  )
  let _ = try? @fs.rmdir(root, recursive=true)
  @fs.mkdir(root, permission=0o755)
  let _ = emit_moonbit_scaffold_from_ts(
    "fixtures/resolver/project/types/export-as-namespace-optional-react-fields-entry.d.ts",
    "./runtime/react-like.js", root,
  )
  let bridge_mbti = @fs.read_file(wbtest_join_path(root, "bridge.mbti")).text() catch {
    e =>
      fail(
        "failed to read export-as-namespace optional-react-fields bridge.mbti: \{e}",
      )
  }
  assert_true(bridge_mbti.contains("pub(all) struct BadgeProps"))
  assert_true(bridge_mbti.contains("/// label : String?"))
  assert_true(bridge_mbti.contains("/// children : JSValue?"))
  assert_true(bridge_mbti.contains("/// ref : Ref[JSValue]?"))
  assert_true(
    bridge_mbti.contains(
      "declare pub fn renderBadge(props : BadgeProps) -> BadgeProps",
    ),
  )
  assert_true(@fs.exists(wbtest_join_path(root, "SCAFFOLD_DIAGNOSTICS.md")))
}

///|
async test "emit_moonbit_scaffold_from_ts handles exported jsx-dev-runtime signatures" {
  let root = wbtest_tmp_project_benchmark_root(
    "bridge_scaffold_exported_jsx_dev_runtime",
  )
  let _ = try? @fs.rmdir(root, recursive=true)
  @fs.mkdir(root, permission=0o755)
  let _ = emit_moonbit_scaffold_from_ts(
    "fixtures/resolver/project/types/exported-jsx-dev-runtime-entry.d.ts", "react/jsx-dev-runtime",
    root,
  )
  let bridge_mbti = @fs.read_file(wbtest_join_path(root, "bridge.mbti")).text() catch {
    e => fail("failed to read exported jsx-dev-runtime bridge.mbti: \{e}")
  }
  assert_true(bridge_mbti.contains("pub(all) struct JSXSource"))
  assert_true(bridge_mbti.contains("/// fileName : String?"))
  assert_true(
    bridge_mbti.contains(
      "declare pub fn jsxDEV(type_ : ElementType, props : JSValue, key : Key?, isStatic : Bool, source : JSXSource?, self : JSValue?) -> ReactElement",
    ),
  )
  assert_true(@fs.exists(wbtest_join_path(root, "SCAFFOLD_DIAGNOSTICS.md")))
}

///|
async test "emit_moonbit_scaffold_from_ts handles export as namespace inline PropsWithChildren members" {
  let root = wbtest_tmp_project_benchmark_root(
    "bridge_scaffold_export_as_namespace_inline_props_with_children",
  )
  let _ = try? @fs.rmdir(root, recursive=true)
  @fs.mkdir(root, permission=0o755)
  let _ = emit_moonbit_scaffold_from_ts(
    "fixtures/resolver/project/types/export-as-namespace-inline-props-with-children-entry.d.ts",
    "./runtime/react-like.js", root,
  )
  let bridge_mbti = @fs.read_file(wbtest_join_path(root, "bridge.mbti")).text() catch {
    e =>
      fail(
        "failed to read export-as-namespace inline props-with-children bridge.mbti: \{e}",
      )
  }
  let bridge_mbt = @fs.read_file(wbtest_join_path(root, "bridge.mbt")).text() catch {
    e =>
      fail(
        "failed to read export-as-namespace inline props-with-children bridge.mbt: \{e}",
      )
  }
  assert_true(
    bridge_mbti.contains("pub(all) struct LabelCountPropsWithChildren"),
  )
  assert_true(
    bridge_mbti.contains(
      "declare pub fn createBadge(props : LabelCountPropsWithChildren) -> LabelCountPropsWithChildren",
    ),
  )
  assert_true(
    bridge_mbt.contains("pub(all) struct LabelCountPropsWithChildren {"),
  )
  assert_false(bridge_mbti.contains("declare pub type PropsWithChildren"))
  assert_true(@fs.exists(wbtest_join_path(root, "SCAFFOLD_DIAGNOSTICS.md")))
}

///|
async test "emit_moonbit_scaffold_from_ts sanitizes reserved exported function and parameter names" {
  let root = wbtest_tmp_project_benchmark_root(
    "bridge_scaffold_export_as_namespace_sanitize",
  )
  let _ = try? @fs.rmdir(root, recursive=true)
  @fs.mkdir(root, permission=0o755)
  let _ = emit_moonbit_scaffold_from_ts(
    "fixtures/resolver/project/types/export-as-namespace-sanitize-entry.d.ts", "./runtime/react-like.js",
    root,
  )
  let bridge_mbti = @fs.read_file(wbtest_join_path(root, "bridge.mbti")).text() catch {
    e => fail("failed to read sanitize bridge.mbti: \{e}")
  }
  let bridge_mbt = @fs.read_file(wbtest_join_path(root, "bridge.mbt")).text() catch {
    e => fail("failed to read sanitize bridge.mbt: \{e}")
  }
  assert_true(
    bridge_mbti.contains(
      "declare pub fn jsx(type_ : String, props : Props) -> ReactElement",
    ),
  )
  assert_true(
    bridge_mbti.contains(
      "declare pub fn use_(promise : Promise[String]) -> String",
    ),
  )
  assert_true(
    bridge_mbti.contains(
      "declare pub fn fragment(children : String) -> ReactElement",
    ),
  )
  assert_true(
    bridge_mbti.contains(
      "declare pub fn strictMode(children : String) -> ReactElement",
    ),
  )
  assert_false(bridge_mbti.contains("declare pub fn Fragment("))
  assert_false(bridge_mbti.contains("declare pub fn use("))
  assert_true(bridge_mbt.contains("pub extern \"js\" fn use_("))
  assert_true(
    bridge_mbt.contains(
      "pub fn fragment(children : String) -> ReactElement {\n  fragment(children)\n}",
    ) ||
    bridge_mbt.contains("pub extern \"js\" fn fragment(children : String)"),
  )
  assert_false(bridge_mbt.contains("pub fn Fragment("))
  assert_false(bridge_mbt.contains("Component :"))
  assert_false(bridge_mbt.contains("fn :"))
}

///|
async test "emit_moonbit_scaffold_from_ts handles imported object type alias members" {
  let root = wbtest_tmp_project_benchmark_root(
    "bridge_scaffold_hono_options_alias",
  )
  let _ = try? @fs.rmdir(root, recursive=true)
  @fs.mkdir(root, permission=0o755)
  let _ = emit_moonbit_scaffold_from_ts(
    "fixtures/resolver/project/types/hono-options-entry.d.ts", "./runtime/hono.js",
    root,
  )
  let bridge_mbti = @fs.read_file(wbtest_join_path(root, "bridge.mbti")).text() catch {
    e => fail("failed to read hono-options bridge.mbti: \{e}")
  }
  let bridge_mbt = @fs.read_file(wbtest_join_path(root, "bridge.mbt")).text() catch {
    e => fail("failed to read hono-options bridge.mbt: \{e}")
  }
  assert_true(bridge_mbti.contains("pub(all) struct HonoOptions[E] {"))
  assert_true(bridge_mbti.contains("/// strict : Bool?"))
  assert_true(bridge_mbti.contains("/// bindings : E?"))
  assert_true(bridge_mbt.contains("pub(all) struct HonoOptions[E] {"))
  assert_true(bridge_mbt.contains("  strict : Bool?"))
  assert_true(bridge_mbt.contains("  bindings : E?"))
  assert_true(
    bridge_mbt.contains(
      "extern \"js\" fn _new_hono_extern_js(options : JSValue) -> JSValue = \"__ts_mbt_new_hono\"",
    ),
  )
  assert_true(
    bridge_mbt.contains(
      "pub fn[E] new_hono(options : HonoOptions[E]?) -> Hono[E] {",
    ),
  )
}

///|
async test "emit_moonbit_decl_text handles neverthrow-like package entry from tmp path" {
  let root = wbtest_tmp_neverthrow_like_root("decl")
  @async.with_task_group(async fn(group) {
    group.add_defer(async fn() { let _ = try? @fs.rmdir(root, recursive=true) })
    let entry_path = wbtest_prepare_tmp_neverthrow_like_fixture(root) catch {
      _ => {
        fail("Failed to prepare tmp fixture")
        return
      }
    }
    let actual = emit_moonbit_decl_text(entry_path) catch {
      @bridge.ModuleGraphError::ReadError(msg)
      | @bridge.ModuleGraphError::ParseError(msg)
      | @bridge.ModuleGraphError::ResolveError(msg) => {
        fail("Emit error: \{msg}")
        return
      }
    }
    assert_true(entry_path.has_prefix("/tmp/"))
    assert_true(actual.contains("declare pub type Result"))
    assert_true(actual.contains("declare pub type ResultAsync"))
    assert_true(
      actual.contains("declare pub fn parseUser(input : String) -> Result"),
    )
  })
}

///|
async test "emit_moonbit_js_ffi_texts handles neverthrow-like package entry from tmp path" {
  let root = wbtest_tmp_neverthrow_like_root("ffi")
  @async.with_task_group(async fn(group) {
    group.add_defer(async fn() { let _ = try? @fs.rmdir(root, recursive=true) })
    let entry_path = wbtest_prepare_tmp_neverthrow_like_fixture(root) catch {
      _ => {
        fail("Failed to prepare tmp fixture")
        return
      }
    }
    let bundle = emit_moonbit_js_ffi_texts(
      entry_path, "/runtime/neverthrow-like.js",
    ) catch {
      @bridge.ModuleGraphError::ReadError(msg)
      | @bridge.ModuleGraphError::ParseError(msg)
      | @bridge.ModuleGraphError::ResolveError(msg) => {
        fail("Emit error: \{msg}")
        return
      }
    }
    assert_true(entry_path.has_prefix("/tmp/"))
    assert_true(bundle.ffi_mbt.contains("pub extern \"js\" fn parse_user("))
    assert_true(bundle.ffi_mbt.contains("#external\npub type Result"))
    assert_false(bundle.bridge_js.contains("__ts_mbt_parse_user"))
  })
}

///|
async test "emit_moonbit_scaffold_from_ts handles neverthrow-like package entry from tmp path" {
  let root = wbtest_tmp_neverthrow_like_root("bridge_package")
  @async.with_task_group(async fn(group) {
    group.add_defer(async fn() { let _ = try? @fs.rmdir(root, recursive=true) })
    let entry_path = wbtest_prepare_tmp_neverthrow_like_fixture(root) catch {
      _ => {
        fail("Failed to prepare tmp fixture")
        return
      }
    }
    let out_dir = wbtest_join_path(root, "bridge_pkg")
    let _ = emit_moonbit_scaffold_from_ts(
      entry_path, "/runtime/neverthrow-like.js", out_dir,
    )
    let bridge_mbti = @fs.read_file(wbtest_join_path(out_dir, "bridge.mbti")).text() catch {
      e => {
        fail("Read error: \{e}")
        return
      }
    }
    let bridge_mbt = @fs.read_file(wbtest_join_path(out_dir, "bridge.mbt")).text() catch {
      e => {
        fail("Read error: \{e}")
        return
      }
    }
    assert_true(entry_path.has_prefix("/tmp/"))
    assert_true(bridge_mbti.contains("declare pub type Result"))
    assert_true(bridge_mbti.contains("declare pub type ResultAsync"))
    assert_true(
      bridge_mbti.contains("declare pub fn parseUser(input : String) -> Result"),
    )
    assert_true(bridge_mbt.contains("extern \"js\" fn parse_user("))
    assert_true(bridge_mbt.contains("extern \"js\" fn fetch_user("))
    assert_true(
      bridge_mbt.contains(
        "pub fn parseUser(input : String) -> Result {\n  parse_user(input)\n}",
      ),
    )
    assert_true(
      bridge_mbt.contains(
        "pub fn fetchUser(id : String) -> ResultAsync {\n  fetch_user(id)\n}",
      ),
    )
  })
}

///|
async test "collect_moonbit_ts_scaffold_unsupported_exports ignores namespace export surfaces" {
  let unsupported = collect_moonbit_ts_scaffold_unsupported_exports(
    "fixtures/resolver/project/types/ns-entry.d.ts",
  ) catch {
    @bridge.ModuleGraphError::ReadError(msg)
    | @bridge.ModuleGraphError::ParseError(msg)
    | @bridge.ModuleGraphError::ResolveError(msg) => {
      fail("Unexpected error: \{msg}")
      return
    }
  }
  @test.assert_eq(unsupported.length(), 0)
}

///|
async test "emit_moonbit_scaffold_from_ts keeps ambiguous export surfaces as diagnostics" {
  let root = wbtest_tmp_project_benchmark_root("bridge_scaffold_ambiguous")
  let _ = try? @fs.rmdir(root, recursive=true)
  @fs.mkdir(root, permission=0o755)
  let _ = emit_moonbit_scaffold_from_ts(
    "fixtures/resolver/project/types/ambiguous-entry.d.ts", "./runtime/ambiguous.js",
    root,
  )
  let diagnostics = @fs.read_file(
    wbtest_join_path(root, "SCAFFOLD_DIAGNOSTICS.md"),
  ).text() catch {
    e => fail("failed to read SCAFFOLD_DIAGNOSTICS.md: \{e}")
  }
  let bridge_mbti = @fs.read_file(wbtest_join_path(root, "bridge.mbti")).text() catch {
    e => fail("failed to read ambiguous bridge.mbti: \{e}")
  }
  let bridge_mbt = @fs.read_file(wbtest_join_path(root, "bridge.mbt")).text() catch {
    e => fail("failed to read ambiguous bridge.mbt: \{e}")
  }
  assert_true(diagnostics.contains("Shared (ambiguous re-export:"))
  assert_true(
    diagnostics.contains(
      "| `Shared` | widened | ambiguous re-export surface | runtime-unsafe; generated bridge stubs abort instead of guessing a runtime binding |",
    ),
  )
  assert_true(diagnostics.contains("## Runtime Safety"))
  assert_true(
    diagnostics.contains(
      "Widened surfaces keep the scaffold buildable, but ambiguous runtime exports are not callable until the source export is made unambiguous.",
    ),
  )
  assert_true(diagnostics.contains("## Decision Vocabulary"))
  assert_true(diagnostics.contains("- `widened`: emitted as `JSValue`"))
  assert_true(diagnostics.contains("- `omitted`: not emitted"))
  assert_true(
    diagnostics.contains(
      "- `bridge-wrapped`: emitted through generated `bridge.js` glue",
    ),
  )
  assert_true(
    diagnostics.contains("fixtures/resolver/project/types/ambiguous-a.d.ts"),
  )
  assert_true(
    diagnostics.contains("fixtures/resolver/project/types/ambiguous-b.d.ts"),
  )
  assert_true(
    bridge_mbti.contains(
      "Unsupported export Shared: ambiguous re-export surface is widened to JSValue",
    ),
  )
  assert_true(
    bridge_mbt.contains(
      "Unsupported export Shared: ambiguous re-export surface cannot be bound safely",
    ),
  )
}

///|
async test "emit_moonbit_scaffold_from_ts handles namespace export surfaces" {
  let root = wbtest_tmp_project_benchmark_root("bridge_scaffold_namespace")
  let _ = try? @fs.rmdir(root, recursive=true)
  let _ = emit_moonbit_scaffold_from_ts(
    "fixtures/resolver/project/types/ns-entry.d.ts", "./runtime/ns.js", root,
  )
  let bridge_mbti = @fs.read_file(wbtest_join_path(root, "bridge.mbti")).text() catch {
    e => {
      fail("Read error: \{e}")
      return
    }
  }
  let bridge_mbt = @fs.read_file(wbtest_join_path(root, "bridge.mbt")).text() catch {
    e => {
      fail("Read error: \{e}")
      return
    }
  }
  let bridge_js = @fs.read_file(wbtest_join_path(root, "bridge.js")).text() catch {
    e => {
      fail("Read error: \{e}")
      return
    }
  }
  assert_true(bridge_mbti.contains("declare pub type Shapes"))
  assert_true(bridge_mbti.contains("declare pub fn get_shapes() -> Shapes"))
  assert_true(bridge_mbt.contains("pub extern \"js\" fn get_shapes()"))
  assert_true(bridge_js.contains("export function __ts_mbt_get_shapes()"))
  let _ = try? @fs.rmdir(root, recursive=true)
}

///|
async test "emit_moonbit_decl_text handles package exports subpath entry" {
  let actual = emit_moonbit_decl_text(
    "fixtures/resolver/project/types/subpath-package-entry.d.ts",
  ) catch {
    @bridge.ModuleGraphError::ReadError(msg)
    | @bridge.ModuleGraphError::ParseError(msg)
    | @bridge.ModuleGraphError::ResolveError(msg) => {
      fail("Emit error: \{msg}")
      return
    }
  }
  assert_true(actual.contains("declare pub type FeatureOptions"))
  assert_true(actual.contains("declare pub fn executeFeature("))
}

///|
async test "emit_moonbit_decl_text handles package exports wildcard subpath entry" {
  let actual = emit_moonbit_decl_text(
    "fixtures/resolver/project/types/pattern-package-entry.d.ts",
  ) catch {
    @bridge.ModuleGraphError::ReadError(msg)
    | @bridge.ModuleGraphError::ParseError(msg)
    | @bridge.ModuleGraphError::ResolveError(msg) => {
      fail("Emit error: \{msg}")
      return
    }
  }
  assert_true(actual.contains("declare pub type PatternOptions"))
  assert_true(actual.contains("declare pub fn createPattern("))
}

///|
async test "emit_moonbit_decl_text handles package exports array fallback wildcard subpath entry" {
  let actual = emit_moonbit_decl_text(
    "fixtures/resolver/project/types/pattern-array-package-entry.d.ts",
  ) catch {
    @bridge.ModuleGraphError::ReadError(msg)
    | @bridge.ModuleGraphError::ParseError(msg)
    | @bridge.ModuleGraphError::ResolveError(msg) => {
      fail("Emit error: \{msg}")
      return
    }
  }
  assert_true(actual.contains("declare pub type ArrayPatternOptions"))
  assert_true(actual.contains("declare pub fn createArrayPattern("))
}

///|
async test "emit_moonbit_js_ffi_texts handles node-like ambient entry" {
  let bundle = emit_moonbit_js_ffi_texts(
    "fixtures/resolver/project/types/node-like-entry.d.ts", "/runtime/node-like.js",
  ) catch {
    @bridge.ModuleGraphError::ReadError(msg)
    | @bridge.ModuleGraphError::ParseError(msg)
    | @bridge.ModuleGraphError::ResolveError(msg) => {
      fail("Emit error: \{msg}")
      return
    }
  }
  assert_true(bundle.ffi_mbt.contains("#external\npub type NodeJS_ProcessEnv"))
  assert_false(bundle.bridge_js.contains("__ts_mbt_has_env"))
}

///|
test "compute_vendor_root: missing source field falls back to module root, not src/" {
  // moon.mod.json without a `source` field — MoonBit treats the module
  // root itself as the source directory, so the bridge has to land at
  // `<root>/internal/generated/...`. A `<root>/src/internal/generated/...`
  // fallback would be invisible to the consumer's `moon build`.
  let mod_json = "{ \"name\": \"acme/app\", \"version\": \"0.0.0\" }"
  @test.assert_eq(
    compute_vendor_root("/proj", mod_json),
    "/proj/internal/generated",
  )
}

///|
test "compute_vendor_root: explicit source=src nests under src/" {
  let mod_json = "{ \"name\": \"acme/app\", \"source\": \"src\" }"
  @test.assert_eq(
    compute_vendor_root("/proj", mod_json),
    "/proj/src/internal/generated",
  )
}

///|
test "compute_vendor_root: explicit source=. matches missing-source behavior" {
  let mod_json = "{ \"name\": \"acme/app\", \"source\": \".\" }"
  @test.assert_eq(
    compute_vendor_root("/proj", mod_json),
    "/proj/internal/generated",
  )
}

///|
test "compute_vendor_root: empty source string is treated as module root" {
  let mod_json = "{ \"name\": \"acme/app\", \"source\": \"\" }"
  @test.assert_eq(
    compute_vendor_root("/proj", mod_json),
    "/proj/internal/generated",
  )
}

///|
test "compute_vendor_root: nested source path stacks under module root" {
  let mod_json = "{ \"name\": \"acme/app\", \"source\": \"packages/lib\" }"
  @test.assert_eq(
    compute_vendor_root("/proj", mod_json),
    "/proj/packages/lib/internal/generated",
  )
}

///|
test "npm runtime boundary wraps generated MoonBit exports" {
  let source =
    #|const raw_parse = (value) => value;
    #|const untouched = 1;
    #|export { raw_parse as parse, untouched };
    #|//# sourceMappingURL=glue.js.map
  let modes : Map[String, Bool] = {}
  let rewritten = rewrite_runtime_boundary_js_exports(
    source,
    "function __tsmbt_public_return(value) { return value; }\nfunction __tsmbt_raw_argument(value) { return value; }",
    ["parse"],
    modes,
  )
  assert_true(rewritten.contains("export { untouched }"))
  assert_true(rewritten.contains("const __tsmbt_raw_export_parse = raw_parse;"))
  assert_true(
    rewritten.contains(
      "export function parse(...args) { return __tsmbt_public_return(__tsmbt_raw_export_parse(...args.map((arg) => __tsmbt_raw_argument(arg)))); }",
    ),
  )
}
