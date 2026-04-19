///|
fn wbtest_join_path(base : String, child : String) -> String {
  if base.has_suffix("/") {
    base + child
  } else {
    base + "/" + child
  }
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
test "command_help_lines hides unstable wasm commands behind experimental names" {
  let lines = command_help_lines()
  assert_true(
    lines.contains(
      "  experimental-emit-gc <file> [out] Emit experimental wasm-gc binary (default: out.wasm)",
    ),
  )
  assert_true(
    lines.contains(
      "  experimental-analyze <file> Analyze experimental AOT compilability of functions",
    ),
  )
  assert_true(
    lines.contains(
      "  experimental-aot-check <file> Alias for experimental-analyze",
    ),
  )
  assert_true(
    lines.contains(
      "  emit-moonbit-js-ffi <file> <module-spec> [ffi-out] [bridge-out] Emit MoonBit JS FFI stubs and ESM bridge",
    ),
  )
  assert_true(
    lines.contains(
      "  benchmark-project <root> [limit] Benchmark local TS/.d.ts corpus coverage",
    ),
  )
  assert_true(
    lines.contains(
      "  benchmark-corpora [limit] Benchmark built-in local and optional real-world corpora",
    ),
  )
  assert_false(
    lines.contains(
      "  emit-gc <file> [out] Emit wasm-gc binary (default: out.wasm)",
    ),
  )
  assert_false(
    lines.contains(
      "  analyze <file>       Analyze AOT compilability of functions",
    ),
  )
  assert_false(lines.contains("  aot-check <file>     Alias for analyze"))
}

///|
async test "benchmark_ts_project summarizes fixture corpus" {
  let result = benchmark_ts_project("fixtures/resolver/project/types", limit=64)
  assert_true(result.total_files > 0)
  assert_true(result.declaration_files > 0)
  assert_true(result.module_source_files > 0)
  assert_eq(result.module_parse_failed, 0)
  assert_eq(result.decl_parse_failed, 0)
  assert_eq(result.decl_emit_failed, 0)
  assert_eq(result.decl_js_ffi_failed, 0)
  let report = render_project_benchmark_report(result)
  assert_true(report.contains("=== Project Benchmark ==="))
  assert_true(report.contains("parse_module_block (.ts):"))
  assert_true(report.contains("emit_moonbit_decl (.d.ts):"))
  assert_true(report.contains("emit_moonbit_js_ffi (.d.ts):"))
}

///|
async test "benchmark_ts_project summarizes jsx tsx fixture corpus" {
  let result = benchmark_ts_project("fixtures/corpus/jsx-tsx", limit=64)
  assert_true(result.total_files > 0)
  assert_eq(result.declaration_files, 0)
  assert_true(result.module_source_files > 0)
  assert_eq(result.module_parse_failed, 0)
  let report = render_project_benchmark_report(result)
  assert_true(report.contains("fixtures/corpus/jsx-tsx"))
  assert_true(report.contains("parse_module_block (.ts):"))
}

///|
async test "benchmark_project_corpora skips missing optional roots" {
  let runs = benchmark_project_corpora(
    [
      {
        name: "fixture-jsx-tsx",
        root: "fixtures/corpus/jsx-tsx",
        description: "repo-local TSX corpus",
        optional: false,
      },
      {
        name: "missing-optional",
        root: "fixtures/corpus/__missing__",
        description: "missing corpus",
        optional: true,
      },
    ],
    limit=64,
  )
  assert_eq(runs.length(), 1)
  assert_eq(runs[0].corpus.name, "fixture-jsx-tsx")
  assert_eq(runs[0].result.module_parse_failed, 0)
  let report = render_project_benchmark_corpora_report(runs)
  assert_true(report.contains("=== Benchmark Corpora ==="))
  assert_true(report.contains("fixture-jsx-tsx"))
  assert_false(report.contains("missing-optional"))
}

///|
async test "benchmark_ts_project skips node_modules and reports parse failures" {
  let root = wbtest_tmp_project_benchmark_root("bad")
  @async.with_task_group(async fn(group) {
    group.add_defer(async fn() { let _ = try? @fs.rmdir(root, recursive=true) })
    let src_dir = wbtest_join_path(root, "src")
    let node_modules_dir = wbtest_join_path(root, "node_modules/pkg")
    let _ = try? @fs.rmdir(root, recursive=true)
    @fs.mkdir(root, permission=0o755)
    @fs.mkdir(src_dir, permission=0o755)
    @fs.mkdir(wbtest_join_path(root, "node_modules"), permission=0o755)
    @fs.mkdir(node_modules_dir, permission=0o755)
    @fs.write_file(
      wbtest_join_path(src_dir, "good.ts"),
      "export const good = 1;\n",
      create=0o644,
    )
    @fs.write_file(
      wbtest_join_path(src_dir, "bad.ts"),
      "export const = 1;\n",
      create=0o644,
    )
    @fs.write_file(
      wbtest_join_path(node_modules_dir, "ignored.ts"),
      "export const ignored = 1;\n",
      create=0o644,
    )
    let result = benchmark_ts_project(root, limit=16)
    assert_eq(result.total_files, 2)
    assert_eq(result.module_source_files, 2)
    assert_eq(result.module_parse_ok, 1)
    assert_eq(result.module_parse_failed, 1)
    assert_true(result.failures.length() > 0)
    let report = render_project_benchmark_report(result)
    assert_true(report.contains("bad.ts"))
    assert_false(report.contains("ignored.ts"))
  })
}

///|
async test "resolve_module_path uses parser node module resolver" {
  let resolved = resolve_module_path(
    "fixtures/resolver/project/src/nested/deep/app.ts", "pkg-exports",
  )
  assert_eq(
    resolved, "fixtures/resolver/project/node_modules/pkg-exports/dist/index.js",
  )
}

///|
async test "emit_moonbit_decl_text resolves type reexports from entry file" {
  let actual = emit_moonbit_decl_text(
    "fixtures/resolver/project/types/entry.d.ts",
  ) catch {
    @analysis.ReadError(msg)
    | @analysis.ParseError(msg)
    | @analysis.ResolveError(msg) => {
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
    "fixtures/resolver/project/types/entry.d.ts", "./runtime/mod.js",
  ) catch {
    @analysis.ReadError(msg)
    | @analysis.ParseError(msg)
    | @analysis.ResolveError(msg) => {
      fail("Emit error: \{msg}")
      return
    }
  }
  assert_true(bundle.ffi_mbt.contains("pub extern \"js\" fn render("))
  assert_true(bundle.bridge_js.contains("globalThis.__ts_mbt_render"))
}

///|
async test "emit_moonbit_decl_text handles neverthrow-like package entry" {
  let actual = emit_moonbit_decl_text(
    "fixtures/resolver/project/types/neverthrow-like-entry.d.ts",
  ) catch {
    @analysis.ReadError(msg)
    | @analysis.ParseError(msg)
    | @analysis.ResolveError(msg) => {
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
    @analysis.ReadError(msg)
    | @analysis.ParseError(msg)
    | @analysis.ResolveError(msg) => {
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
    @analysis.ReadError(msg)
    | @analysis.ParseError(msg)
    | @analysis.ResolveError(msg) => {
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
    @analysis.ReadError(msg)
    | @analysis.ParseError(msg)
    | @analysis.ResolveError(msg) => {
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
    @analysis.ReadError(msg)
    | @analysis.ParseError(msg)
    | @analysis.ResolveError(msg) => {
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
async test "emit_moonbit_js_ffi_texts handles neverthrow-like package entry" {
  let bundle = emit_moonbit_js_ffi_texts(
    "fixtures/resolver/project/types/neverthrow-like-entry.d.ts", "./runtime/neverthrow-like.js",
  ) catch {
    @analysis.ReadError(msg)
    | @analysis.ParseError(msg)
    | @analysis.ResolveError(msg) => {
      fail("Emit error: \{msg}")
      return
    }
  }
  assert_true(bundle.ffi_mbt.contains("pub extern \"js\" fn parse_user("))
  assert_true(bundle.bridge_js.contains("globalThis.__ts_mbt_parse_user"))
}

///|
async test "emit_moonbit_js_ffi_texts handles runtime ts exported functions" {
  let bundle = emit_moonbit_js_ffi_texts(
    "fixtures/resolver/project/types/runtime-function-entry.ts", "./runtime/runtime-function.js",
  ) catch {
    @analysis.ReadError(msg)
    | @analysis.ParseError(msg)
    | @analysis.ResolveError(msg) => {
      fail("Emit error: \{msg}")
      return
    }
  }
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn scale_point(point : RuntimePoint, factor : Double) -> RuntimePoint = \"__ts_mbt_scale_point\"",
    ),
  )
  assert_true(
    bundle.bridge_js.contains(
      "globalThis.__ts_mbt_scale_point = __ts_mbt_mod.scalePoint;",
    ),
  )
}

///|
async test "emit_moonbit_js_ffi_texts handles runtime tsx exported functions" {
  let bundle = emit_moonbit_js_ffi_texts(
    "fixtures/resolver/project/types/runtime-component-entry.tsx", "./runtime/runtime-component.js",
  ) catch {
    @analysis.ReadError(msg)
    | @analysis.ParseError(msg)
    | @analysis.ResolveError(msg) => {
      fail("Emit error: \{msg}")
      return
    }
  }
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn render_badge(props : BadgeProps) -> JsxElement = \"__ts_mbt_render_badge\"",
    ),
  )
  assert_true(
    bundle.bridge_js.contains(
      "globalThis.__ts_mbt_render_badge = __ts_mbt_mod.renderBadge;",
    ),
  )
}

///|
async test "emit_moonbit_js_ffi_texts handles runtime ts exported const arrow functions" {
  let bundle = emit_moonbit_js_ffi_texts(
    "fixtures/resolver/project/types/runtime-arrow-entry.ts", "./runtime/runtime-arrow.js",
  ) catch {
    @analysis.ReadError(msg)
    | @analysis.ParseError(msg)
    | @analysis.ResolveError(msg) => {
      fail("Emit error: \{msg}")
      return
    }
  }
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn scale_arrow_point(point : RuntimeArrowPoint, factor : Double) -> RuntimeArrowPoint = \"__ts_mbt_scale_arrow_point\"",
    ),
  )
  assert_true(
    bundle.bridge_js.contains(
      "globalThis.__ts_mbt_scale_arrow_point = __ts_mbt_mod.scaleArrowPoint;",
    ),
  )
}

///|
async test "emit_moonbit_decl_text handles runtime default exported classes" {
  let actual = emit_moonbit_decl_text(
    "fixtures/resolver/project/types/runtime-default-class-entry.ts",
  ) catch {
    @analysis.ReadError(msg)
    | @analysis.ParseError(msg)
    | @analysis.ResolveError(msg) => {
      fail("Emit error: \{msg}")
      return
    }
  }
  assert_true(actual.contains("declare pub type Default"))
  assert_true(actual.contains("declare pub fn new_default("))
  assert_true(actual.contains("declare pub fn default_inc("))
}

///|
async test "emit_moonbit_js_ffi_texts handles runtime default exported classes" {
  let bundle = emit_moonbit_js_ffi_texts(
    "fixtures/resolver/project/types/runtime-default-class-entry.ts", "./runtime/runtime-default-class.js",
  ) catch {
    @analysis.ReadError(msg)
    | @analysis.ParseError(msg)
    | @analysis.ResolveError(msg) => {
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
      "globalThis.__ts_mbt_new_default = (initial) => new __ts_mbt_mod.default(initial);",
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
      @analysis.ReadError(msg)
      | @analysis.ParseError(msg)
      | @analysis.ResolveError(msg) => {
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
      entry_path, "./runtime/neverthrow-like.js",
    ) catch {
      @analysis.ReadError(msg)
      | @analysis.ParseError(msg)
      | @analysis.ResolveError(msg) => {
        fail("Emit error: \{msg}")
        return
      }
    }
    assert_true(entry_path.has_prefix("/tmp/"))
    assert_true(bundle.ffi_mbt.contains("pub extern \"js\" fn parse_user("))
    assert_true(bundle.ffi_mbt.contains("#external\ntype Result"))
    assert_true(bundle.bridge_js.contains("globalThis.__ts_mbt_parse_user"))
  })
}

///|
async test "emit_moonbit_decl_text handles package exports subpath entry" {
  let actual = emit_moonbit_decl_text(
    "fixtures/resolver/project/types/subpath-package-entry.d.ts",
  ) catch {
    @analysis.ReadError(msg)
    | @analysis.ParseError(msg)
    | @analysis.ResolveError(msg) => {
      fail("Emit error: \{msg}")
      return
    }
  }
  assert_true(actual.contains("declare pub type FeatureOptions"))
  assert_true(actual.contains("declare pub fn executeFeature("))
}

///|
async test "emit_moonbit_js_ffi_texts handles node-like ambient entry" {
  let bundle = emit_moonbit_js_ffi_texts(
    "fixtures/resolver/project/types/node-like-entry.d.ts", "./runtime/node-like.js",
  ) catch {
    @analysis.ReadError(msg)
    | @analysis.ParseError(msg)
    | @analysis.ResolveError(msg) => {
      fail("Emit error: \{msg}")
      return
    }
  }
  assert_true(bundle.ffi_mbt.contains("#external\ntype NodeJsProcessEnv"))
  assert_true(bundle.bridge_js.contains("globalThis.__ts_mbt_has_env"))
}
