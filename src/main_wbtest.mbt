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
      "  emit-moonbit-js-ffi <file> <module-spec> [ffi-out] [bridge-out] Emit MoonBit JS FFI stubs and ESM bridge from a TypeScript entrypoint",
    ),
  )
  assert_true(
    lines.contains(
      "  emit-moonbit-bridge <file> <module-spec> [decl-out] [ffi-out] [bridge-out] Emit a full MoonBit bridge bundle from a TS entrypoint",
    ),
  )
  assert_true(
    lines.contains(
      "  emit-moonbit-bridge-package <file> <module-spec> <out-dir> Emit a generated MoonBit bridge package directory",
    ),
  )
  assert_true(
    lines.contains(
      "  emit-moonbit-scaffold-from-ts <file> <module-spec> <out-dir> Emit a MoonBit bridge scaffold from a TS entrypoint",
    ),
  )
  assert_true(
    lines.contains(
      "  normalize-moonbit-dts <file> [out] Normalize MoonBit-generated TypeScript declarations into clearer .d.ts output",
    ),
  )
  assert_true(
    lines.contains(
      "  emit-typescript-from-mbti <file> [out] Emit TypeScript declarations directly from a MoonBit .mbti interface",
    ),
  )
  assert_true(
    lines.contains(
      "  emit-js-link-config-from-mbti <file> [out] Emit MoonBit link.js.exports config from a .mbti interface",
    ),
  )
  assert_true(
    lines.contains(
      "  emit-typescript-package-from-mbti <file> <out-dir> [import-rewrite-json] Emit a recursive TypeScript declaration package from a root .mbti interface",
    ),
  )
  assert_true(
    lines.contains(
      "  emit-typescript-scaffold-from-mbti <file> <out-dir> [import-rewrite-json] Emit MoonBit autolink config and recursive TypeScript declarations together",
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
async test "emit_typescript_decl_from_mbti_text emits TypeScript declarations from mbti" {
  let actual = emit_typescript_decl_from_mbti_text(
    "fixtures/mbti_typescript/basic.pkg.generated.mbti",
  ) catch {
    @analysis.MbtiTypescriptDeclError::ReadError(msg)
    | @analysis.MbtiTypescriptDeclError::ParseError(msg) =>
      fail("Emit error: \{msg}")
  }
  assert_true(actual.contains("export function identity<T>(arg0: T): T;"))
  assert_true(
    actual.contains(
      "export function debug_identity<T extends debug.Debug>(arg0: T): T;",
    ),
  )
  assert_true(
    actual.contains("import type * as json from \"moonbitlang/core/json\";"),
  )
  assert_true(actual.contains("export interface Show {"))
  assert_true(actual.contains("export interface Eq<T> {"))
  assert_true(actual.contains("export interface Hash {"))
  assert_true(actual.contains("export interface Comparable<T0> {"))
  assert_true(
    actual.contains(
      "export interface Box<T> extends Show, Eq<Box<T>>, Hash, Comparable<Box<T>> {",
    ),
  )
  assert_true(actual.contains("unwrap(): T;"))
  assert_true(actual.contains("map<U>(arg0: (arg0: T) => U): Box<U>;"))
  assert_true(actual.contains("show_value(): string;"))
  assert_true(actual.contains("function new_<T>(arg0: T): Box<T>;"))
  assert_true(actual.contains("export type Result<T, E> ="))
  assert_true(actual.contains("export interface ResultMethods<T, E> {"))
  assert_true(actual.contains("module: ast.TsModule;"))
  assert_true(actual.contains("export type InternalThing<T> ="))
  assert_true(actual.contains("Eq<ParseError>"))
  assert_true(actual.contains("Eq<InternalThing<T>> & Hash"))
  assert_true(actual.contains("export interface MaybeStringMethods {"))
  assert_true(
    actual.contains(
      "export type MaybeString = (string | undefined) & MaybeStringMethods & Show & Hash & json.ToJson;",
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
    @analysis.MbtiJsLinkConfigError::ReadError(msg)
    | @analysis.MbtiJsLinkConfigError::ParseError(msg) =>
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
  emit_typescript_package_from_mbti(
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
async test "emit_typescript_scaffold_from_mbti writes moon.pkg.json and declaration bundle" {
  let root = wbtest_tmp_project_benchmark_root(
    "mbti_typescript_scaffold_bundle",
  )
  let _ = try? @fs.rmdir(root, recursive=true)
  @fs.mkdir(root, permission=0o755)
  emit_typescript_scaffold_from_mbti(
    "fixtures/mbti_typescript_package/pkg.generated.mbti",
    root,
    None,
  )
  let moon_pkg_json = @fs.read_file(wbtest_join_path(root, "moon.pkg.json")).text() catch {
    e => fail("failed to read moon.pkg.json: \{e}")
  }
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
  assert_true(moon_pkg_json.contains("\"make\""))
  assert_true(moon_pkg_json.contains("\"render\""))
  assert_true(package_json.contains("\"name\": \"@demo/pkg\""))
  assert_true(
    package_json.contains("\"./child\": { \"types\": \"./child/index.d.ts\" }"),
  )
  assert_true(diagnostics_md.contains("Item::new"))
  assert_true(root_decl.contains("import type * as child from \"./child\";"))
}

///|
async test "emit_typescript_package_from_mbti rewrites external imports from json map" {
  let root = wbtest_tmp_project_benchmark_root(
    "mbti_typescript_package_bundle_rewrites",
  )
  let _ = try? @fs.rmdir(root, recursive=true)
  @fs.mkdir(root, permission=0o755)
  emit_typescript_package_from_mbti(
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
async test "emit_typescript_scaffold_from_mbti rewrites external imports from json map" {
  let root = wbtest_tmp_project_benchmark_root(
    "mbti_typescript_scaffold_bundle_rewrites",
  )
  let _ = try? @fs.rmdir(root, recursive=true)
  @fs.mkdir(root, permission=0o755)
  emit_typescript_scaffold_from_mbti(
    "fixtures/mbti_typescript_package/pkg.generated.mbti",
    root,
    Some("fixtures/mbti_typescript_package/import-rewrites.json"),
  )
  let package_json = @fs.read_file(wbtest_join_path(root, "package.json")).text() catch {
    e => fail("failed to read rewritten scaffold package.json: \{e}")
  }
  let diagnostics_md = @fs.read_file(
    wbtest_join_path(root, "AUTOLINK_DIAGNOSTICS.md"),
  ).text() catch {
    e => fail("failed to read rewritten scaffold AUTOLINK_DIAGNOSTICS.md: \{e}")
  }
  let root_decl = @fs.read_file(wbtest_join_path(root, "index.d.ts")).text() catch {
    e => fail("failed to read rewritten scaffold index.d.ts: \{e}")
  }
  assert_true(package_json.contains("\"name\": \"@demo/pkg\""))
  assert_true(diagnostics_md.contains("Item::new"))
  assert_true(root_decl.contains("import type * as debug from \"demo-debug\";"))
  assert_false(root_decl.contains("\"moonbitlang/core/debug\""))
}

///|
async test "emit_typescript_decl_from_mbti_text keeps real analysis package output readable" {
  let actual = emit_typescript_decl_from_mbti_text(
    "src/analysis/pkg.generated.mbti",
  ) catch {
    @analysis.MbtiTypescriptDeclError::ReadError(msg)
    | @analysis.MbtiTypescriptDeclError::ParseError(msg) =>
      fail("Emit error: \{msg}")
  }
  assert_true(actual.contains("export type AnalysisResult<T> ="))
  assert_true(actual.contains("export interface AnalysisResultMethods<T> {"))
  assert_true(actual.contains("Eq<AnalysisErrorKind>"))
  assert_false(actual.contains("debug.Debug"))
  assert_true(actual.contains("& Show;"))
  assert_true(
    actual.contains(
      "export function analyze_null_guard(arg0: ast.TsExpr): [string, boolean] | undefined;",
    ),
  )
  assert_true(
    actual.contains(
      "export function analyze_typeof_guard(arg0: ast.TsExpr): [string, string] | undefined;",
    ),
  )
  assert_false(actual.contains("(String, Bool)?"))
  assert_false(actual.contains("Self["))
}

///|
async test "emit_typescript_decl_text normalizes MoonBit generated d.ts" {
  let actual = emit_typescript_decl_text(
    "fixtures/typescript_decl/moonbit_generated/app.d.ts",
  ) catch {
    @analysis.ReadError(msg)
    | @analysis.ParseError(msg)
    | @analysis.ResolveError(msg) => fail("Emit error: \{msg}")
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
    @analysis.ReadError(msg)
    | @analysis.ParseError(msg)
    | @analysis.ResolveError(msg) => fail("Emit error: \{msg}")
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
    @analysis.ReadError(msg)
    | @analysis.ParseError(msg)
    | @analysis.ResolveError(msg) => fail("Emit error: \{msg}")
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
    @analysis.ReadError(msg)
    | @analysis.ParseError(msg)
    | @analysis.ResolveError(msg) => fail("Emit error: \{msg}")
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
    @analysis.ReadError(msg)
    | @analysis.ParseError(msg)
    | @analysis.ResolveError(msg) => fail("Emit error: \{msg}")
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
    @analysis.ReadError(msg)
    | @analysis.ParseError(msg)
    | @analysis.ResolveError(msg) => fail("Emit error: \{msg}")
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
    @analysis.ReadError(msg)
    | @analysis.ParseError(msg)
    | @analysis.ResolveError(msg) => fail("Emit error: \{msg}")
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
    @analysis.ReadError(msg)
    | @analysis.ParseError(msg)
    | @analysis.ResolveError(msg) => fail("Emit error: \{msg}")
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
    @analysis.ReadError(msg)
    | @analysis.ParseError(msg)
    | @analysis.ResolveError(msg) => fail("Emit error: \{msg}")
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
    @analysis.ReadError(msg)
    | @analysis.ParseError(msg)
    | @analysis.ResolveError(msg) => fail("Emit error: \{msg}")
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
    @analysis.ReadError(msg)
    | @analysis.ParseError(msg)
    | @analysis.ResolveError(msg) => fail("Emit error: \{msg}")
  }
  assert_true(
    actual.contains(
      "export function conflicting_optional_payload_result(): { name?: string } & { name: string } & { ok: boolean };",
    ),
  )
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
    "fixtures/resolver/project/types/entry.d.ts", "/runtime/mod.js",
  ) catch {
    @analysis.ReadError(msg)
    | @analysis.ParseError(msg)
    | @analysis.ResolveError(msg) => {
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
    @analysis.ReadError(msg)
    | @analysis.ParseError(msg)
    | @analysis.ResolveError(msg) => {
      fail("Emit error: \{msg}")
      return
    }
  }
  assert_eq(
    bundle.entry_path,
    "fixtures/resolver/project/types/runtime-function-entry.ts",
  )
  assert_eq(bundle.module_spec, "/runtime/runtime-function.js")
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
    @analysis.ReadError(msg)
    | @analysis.ParseError(msg)
    | @analysis.ResolveError(msg) => {
      fail("Emit error: \{msg}")
      return
    }
  }
  assert_true(bundle.moon_pkg_json.contains("\"path\": \"mizchi/js/core\""))
  assert_true(bundle.bridge_mbti.contains("declare pub fn get_default()"))
  assert_true(bundle.bridge_mbt.contains("pub extern \"js\" fn get_default()"))
  assert_true(bundle.bridge_js.contains("export function __ts_mbt_get_default"))
}

///|
async test "emit_moonbit_bridge_package writes package files to output dir" {
  let root = wbtest_tmp_project_benchmark_root("bridge_package")
  let _ = try? @fs.rmdir(root, recursive=true)
  emit_moonbit_bridge_package(
    "fixtures/resolver/project/types/runtime-function-entry.ts", "/runtime/runtime-function.js",
    root,
  )
  let pkg_json = @fs.read_file(wbtest_join_path(root, "moon.pkg.json")).text() catch {
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
  assert_eq(pkg_json, "{}")
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
  let _ = try? @fs.rmdir(root, recursive=true)
}

///|
async test "emit_moonbit_bridge_package rewrites relative runtime bridge to self-contained module path" {
  let root = wbtest_tmp_project_benchmark_root("bridge_package_relative")
  let _ = try? @fs.rmdir(root, recursive=true)
  emit_moonbit_bridge_package(
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
  let bridge_js_path = @fs.realpath(wbtest_join_path(root, "bridge.js")) catch {
    _ => wbtest_join_path(root, "bridge.js")
  }
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
  emit_moonbit_bridge_package(
    "fixtures/resolver/project/types/class-property-entry.d.ts", "./runtime/class-property.js",
    root,
  )
  let bridge_mbt = @fs.read_file(wbtest_join_path(root, "bridge.mbt")).text() catch {
    e => {
      fail("Read error: \{e}")
      return
    }
  }
  let bridge_js_path = @fs.realpath(wbtest_join_path(root, "bridge.js")) catch {
    _ => wbtest_join_path(root, "bridge.js")
  }
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
  emit_moonbit_bridge_package(
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
  let bridge_js_path = @fs.realpath(wbtest_join_path(root, "bridge.js")) catch {
    _ => wbtest_join_path(root, "bridge.js")
  }
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
  emit_moonbit_bridge_package(
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
  let bridge_js_path = @fs.realpath(wbtest_join_path(root, "bridge.js")) catch {
    _ => wbtest_join_path(root, "bridge.js")
  }
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
    bridge_js.contains("import { CounterState } from \"pkg-class-property\";"),
  )
  assert_true(
    bridge_js.contains(
      "export function __ts_mbt_new_runtime_state() { return new CounterState(); }",
    ),
  )
  let _ = try? @fs.rmdir(root, recursive=true)
}

///|
async test "emit_moonbit_bridge_package preserves js import metadata for relative widened exports" {
  let root = wbtest_tmp_project_benchmark_root("bridge_package_export_equals")
  let _ = try? @fs.rmdir(root, recursive=true)
  emit_moonbit_bridge_package(
    "fixtures/resolver/project/types/export-equals-entry.d.ts", "./runtime/export-equals.js",
    root,
  )
  let pkg_json = @fs.read_file(wbtest_join_path(root, "moon.pkg.json")).text() catch {
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
  let bridge_js_path = @fs.realpath(wbtest_join_path(root, "bridge.js")) catch {
    _ => wbtest_join_path(root, "bridge.js")
  }
  assert_true(pkg_json.contains("\"path\": \"mizchi/js/core\""))
  assert_true(pkg_json.contains("\"alias\": \"js\""))
  assert_true(
    bridge_mbt.contains(
      "#module(\"\{bridge_js_path}\")\npub extern \"js\" fn get_default() -> @js.Any = \"__ts_mbt_get_default\"",
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
  emit_moonbit_bridge_package(
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
  let bridge_js_path = @fs.realpath(wbtest_join_path(pkg_root, "bridge.js")) catch {
    _ => wbtest_join_path(pkg_root, "bridge.js")
  }
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
  emit_moonbit_bridge_package(
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
  let bridge_js_path = @fs.realpath(wbtest_join_path(root, "bridge.js")) catch {
    _ => wbtest_join_path(root, "bridge.js")
  }
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
  emit_moonbit_bridge_package(
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
  let bridge_js_path = @fs.realpath(wbtest_join_path(root, "bridge.js")) catch {
    _ => wbtest_join_path(root, "bridge.js")
  }
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
      "import { CounterState } from \"pkg-class-subpath/state\";",
    ),
  )
  let _ = try? @fs.rmdir(root, recursive=true)
}

///|
async test "emit_moonbit_bridge_package rewrites relative default class helpers to bridge.js" {
  let root = wbtest_tmp_project_benchmark_root("bridge_package_default_class")
  let _ = try? @fs.rmdir(root, recursive=true)
  emit_moonbit_bridge_package(
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
  let bridge_js_path = @fs.realpath(wbtest_join_path(root, "bridge.js")) catch {
    _ => wbtest_join_path(root, "bridge.js")
  }
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
      "pub extern \"js\" fn Default::default_inc(self : Default, delta : Double) -> Double =",
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
  emit_moonbit_bridge_package(
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
  let bridge_js_path = @fs.realpath(wbtest_join_path(pkg_root, "bridge.js")) catch {
    _ => wbtest_join_path(pkg_root, "bridge.js")
  }
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
  emit_moonbit_bridge_package(
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
  let bridge_js_path = @fs.realpath(wbtest_join_path(pkg_root, "bridge.js")) catch {
    _ => wbtest_join_path(pkg_root, "bridge.js")
  }
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
async test "emit_moonbit_decl_text handles runtime ts exported untyped const arrow functions" {
  let actual = emit_moonbit_decl_text(
    "fixtures/resolver/project/types/runtime-untyped-arrow-entry.ts",
  ) catch {
    @analysis.ReadError(msg)
    | @analysis.ParseError(msg)
    | @analysis.ResolveError(msg) => {
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
    @analysis.ReadError(msg)
    | @analysis.ParseError(msg)
    | @analysis.ResolveError(msg) => {
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
async test "emit_moonbit_decl_text handles runtime ts destructured value exports" {
  let actual = emit_moonbit_decl_text(
    "fixtures/resolver/project/types/runtime-destructured-value-entry.ts",
  ) catch {
    @analysis.ReadError(msg)
    | @analysis.ParseError(msg)
    | @analysis.ResolveError(msg) => {
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
    @analysis.ReadError(msg)
    | @analysis.ParseError(msg)
    | @analysis.ResolveError(msg) => {
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
    @analysis.ReadError(msg)
    | @analysis.ParseError(msg)
    | @analysis.ResolveError(msg) => {
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
    @analysis.ReadError(msg)
    | @analysis.ParseError(msg)
    | @analysis.ResolveError(msg) => {
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
    @analysis.ReadError(msg)
    | @analysis.ParseError(msg)
    | @analysis.ResolveError(msg) => {
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
    @analysis.ReadError(msg)
    | @analysis.ParseError(msg)
    | @analysis.ResolveError(msg) => {
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
    @analysis.ReadError(msg)
    | @analysis.ParseError(msg)
    | @analysis.ResolveError(msg) => {
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
    @analysis.ReadError(msg)
    | @analysis.ParseError(msg)
    | @analysis.ResolveError(msg) => {
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
    @analysis.ReadError(msg)
    | @analysis.ParseError(msg)
    | @analysis.ResolveError(msg) => {
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
    @analysis.ReadError(msg)
    | @analysis.ParseError(msg)
    | @analysis.ResolveError(msg) => {
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
    @analysis.ReadError(msg)
    | @analysis.ParseError(msg)
    | @analysis.ResolveError(msg) => {
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
    @analysis.ReadError(msg)
    | @analysis.ParseError(msg)
    | @analysis.ResolveError(msg) => {
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
    @analysis.ReadError(msg)
    | @analysis.ParseError(msg)
    | @analysis.ResolveError(msg) => {
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
    @analysis.ReadError(msg)
    | @analysis.ParseError(msg)
    | @analysis.ResolveError(msg) => {
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
    @analysis.ReadError(msg)
    | @analysis.ParseError(msg)
    | @analysis.ResolveError(msg) => {
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
    @analysis.ReadError(msg)
    | @analysis.ParseError(msg)
    | @analysis.ResolveError(msg) => {
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
    @analysis.ReadError(msg)
    | @analysis.ParseError(msg)
    | @analysis.ResolveError(msg) => {
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
    @analysis.ReadError(msg)
    | @analysis.ParseError(msg)
    | @analysis.ResolveError(msg) => {
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
    @analysis.ReadError(msg)
    | @analysis.ParseError(msg)
    | @analysis.ResolveError(msg) => {
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
    @analysis.ReadError(msg)
    | @analysis.ParseError(msg)
    | @analysis.ResolveError(msg) => {
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
    @analysis.ReadError(msg)
    | @analysis.ParseError(msg)
    | @analysis.ResolveError(msg) => {
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
    @analysis.ReadError(msg)
    | @analysis.ParseError(msg)
    | @analysis.ResolveError(msg) => {
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
    @analysis.ReadError(msg)
    | @analysis.ParseError(msg)
    | @analysis.ResolveError(msg) => {
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
    @analysis.ReadError(msg)
    | @analysis.ParseError(msg)
    | @analysis.ResolveError(msg) => {
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
    @analysis.ReadError(msg)
    | @analysis.ParseError(msg)
    | @analysis.ResolveError(msg) => {
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
    @analysis.ReadError(msg)
    | @analysis.ParseError(msg)
    | @analysis.ResolveError(msg) => {
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
    @analysis.ReadError(msg)
    | @analysis.ParseError(msg)
    | @analysis.ResolveError(msg) => {
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
    @analysis.ReadError(msg)
    | @analysis.ParseError(msg)
    | @analysis.ResolveError(msg) => {
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
    @analysis.ReadError(msg)
    | @analysis.ParseError(msg)
    | @analysis.ResolveError(msg) => {
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
    @analysis.ReadError(msg)
    | @analysis.ParseError(msg)
    | @analysis.ResolveError(msg) => {
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
    @analysis.ReadError(msg)
    | @analysis.ParseError(msg)
    | @analysis.ResolveError(msg) => {
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
    @analysis.ReadError(msg)
    | @analysis.ParseError(msg)
    | @analysis.ResolveError(msg) => {
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
    @analysis.ReadError(msg)
    | @analysis.ParseError(msg)
    | @analysis.ResolveError(msg) => {
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
    @analysis.ReadError(msg)
    | @analysis.ParseError(msg)
    | @analysis.ResolveError(msg) => {
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
    @analysis.ReadError(msg)
    | @analysis.ParseError(msg)
    | @analysis.ResolveError(msg) => {
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
    @analysis.ReadError(msg)
    | @analysis.ParseError(msg)
    | @analysis.ResolveError(msg) => {
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
    @analysis.ReadError(msg)
    | @analysis.ParseError(msg)
    | @analysis.ResolveError(msg) => {
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
  emit_moonbit_scaffold_from_ts(
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
    @analysis.ReadError(msg)
    | @analysis.ParseError(msg)
    | @analysis.ResolveError(msg) => {
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
  emit_moonbit_bridge_package(
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
  let bridge_js_path = @fs.realpath(wbtest_join_path(root, "bridge.js")) catch {
    _ => wbtest_join_path(root, "bridge.js")
  }
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
  emit_moonbit_bridge_package(
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
  let bridge_js_path = @fs.realpath(wbtest_join_path(root, "bridge.js")) catch {
    _ => wbtest_join_path(root, "bridge.js")
  }
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
  emit_moonbit_bridge_package(
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
  let bridge_js_path = @fs.realpath(wbtest_join_path(root, "bridge.js")) catch {
    _ => wbtest_join_path(root, "bridge.js")
  }
  assert_true(bridge_mbt.contains("pub struct RestMeta"))
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
  emit_moonbit_bridge_package(
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
  let bridge_js_path = @fs.realpath(wbtest_join_path(root, "bridge.js")) catch {
    _ => wbtest_join_path(root, "bridge.js")
  }
  assert_true(bridge_mbt.contains("pub struct RestMeta"))
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
  emit_moonbit_bridge_package(
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
  let bridge_js_path = @fs.realpath(wbtest_join_path(root, "bridge.js")) catch {
    _ => wbtest_join_path(root, "bridge.js")
  }
  assert_true(bridge_mbt.contains("pub struct RestMeta"))
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
  emit_moonbit_bridge_package(
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
  let bridge_js_path = @fs.realpath(wbtest_join_path(root, "bridge.js")) catch {
    _ => wbtest_join_path(root, "bridge.js")
  }
  assert_true(bridge_mbt.contains("pub struct RestMeta"))
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
  emit_moonbit_bridge_package(
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
  let bridge_js_path = @fs.realpath(wbtest_join_path(root, "bridge.js")) catch {
    _ => wbtest_join_path(root, "bridge.js")
  }
  assert_true(bridge_mbt.contains("pub struct RestMeta"))
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
  emit_moonbit_bridge_package(
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
  let bridge_js_path = @fs.realpath(wbtest_join_path(root, "bridge.js")) catch {
    _ => wbtest_join_path(root, "bridge.js")
  }
  assert_true(bridge_mbt.contains("pub struct RestMeta"))
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
  emit_moonbit_bridge_package(
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
  let bridge_js_path = @fs.realpath(wbtest_join_path(root, "bridge.js")) catch {
    _ => wbtest_join_path(root, "bridge.js")
  }
  assert_true(bridge_mbt.contains("pub struct RestMeta"))
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
  emit_moonbit_bridge_package(
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
  let bridge_js_path = @fs.realpath(wbtest_join_path(root, "bridge.js")) catch {
    _ => wbtest_join_path(root, "bridge.js")
  }
  assert_true(bridge_mbt.contains("pub struct RestMeta"))
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
  emit_moonbit_bridge_package(
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
  let bridge_js_path = @fs.realpath(wbtest_join_path(root, "bridge.js")) catch {
    _ => wbtest_join_path(root, "bridge.js")
  }
  assert_true(bridge_mbt.contains("pub struct RestMeta"))
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
  emit_moonbit_bridge_package(
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
  let bridge_js_path = @fs.realpath(wbtest_join_path(root, "bridge.js")) catch {
    _ => wbtest_join_path(root, "bridge.js")
  }
  assert_true(bridge_mbt.contains("pub struct RestMeta"))
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
  emit_moonbit_bridge_package(
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
  let bridge_js_path = @fs.realpath(wbtest_join_path(root, "bridge.js")) catch {
    _ => wbtest_join_path(root, "bridge.js")
  }
  assert_true(bridge_mbt.contains("pub struct RestMeta"))
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
  emit_moonbit_bridge_package(
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
  let bridge_js_path = @fs.realpath(wbtest_join_path(root, "bridge.js")) catch {
    _ => wbtest_join_path(root, "bridge.js")
  }
  assert_true(bridge_mbt.contains("pub struct RestMeta"))
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
  emit_moonbit_bridge_package(
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
  let bridge_js_path = @fs.realpath(wbtest_join_path(root, "bridge.js")) catch {
    _ => wbtest_join_path(root, "bridge.js")
  }
  assert_true(bridge_mbt.contains("pub struct RestMeta"))
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
  emit_moonbit_bridge_package(
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
  let bridge_js_path = @fs.realpath(wbtest_join_path(root, "bridge.js")) catch {
    _ => wbtest_join_path(root, "bridge.js")
  }
  assert_true(bridge_mbt.contains("pub struct RestMeta"))
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
  emit_moonbit_bridge_package(
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
  let bridge_js_path = @fs.realpath(wbtest_join_path(root, "bridge.js")) catch {
    _ => wbtest_join_path(root, "bridge.js")
  }
  assert_true(bridge_mbt.contains("pub struct RestMeta"))
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
  emit_moonbit_bridge_package(
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
  let bridge_js_path = @fs.realpath(wbtest_join_path(root, "bridge.js")) catch {
    _ => wbtest_join_path(root, "bridge.js")
  }
  assert_true(bridge_mbt.contains("pub struct RestMeta"))
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
  emit_moonbit_bridge_package(
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
  let bridge_js_path = @fs.realpath(wbtest_join_path(root, "bridge.js")) catch {
    _ => wbtest_join_path(root, "bridge.js")
  }
  assert_true(bridge_mbt.contains("pub struct RestMeta"))
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
  emit_moonbit_bridge_package(
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
  let bridge_js_path = @fs.realpath(wbtest_join_path(root, "bridge.js")) catch {
    _ => wbtest_join_path(root, "bridge.js")
  }
  assert_true(bridge_mbt.contains("pub struct RestMeta"))
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
  emit_moonbit_bridge_package(
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
  let bridge_js_path = @fs.realpath(wbtest_join_path(root, "bridge.js")) catch {
    _ => wbtest_join_path(root, "bridge.js")
  }
  assert_true(bridge_mbt.contains("pub struct RestMeta"))
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
  emit_moonbit_bridge_package(
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
  let bridge_js_path = @fs.realpath(wbtest_join_path(root, "bridge.js")) catch {
    _ => wbtest_join_path(root, "bridge.js")
  }
  assert_true(bridge_mbt.contains("pub struct RestMeta"))
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
  emit_moonbit_bridge_package(
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
  let bridge_js_path = @fs.realpath(wbtest_join_path(root, "bridge.js")) catch {
    _ => wbtest_join_path(root, "bridge.js")
  }
  assert_true(bridge_mbt.contains("pub struct RestMeta"))
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
  emit_moonbit_bridge_package(
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
  let bridge_js_path = @fs.realpath(wbtest_join_path(root, "bridge.js")) catch {
    _ => wbtest_join_path(root, "bridge.js")
  }
  assert_true(bridge_mbt.contains("pub struct RestMeta"))
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
  emit_moonbit_bridge_package(
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
  let bridge_js_path = @fs.realpath(wbtest_join_path(root, "bridge.js")) catch {
    _ => wbtest_join_path(root, "bridge.js")
  }
  assert_true(bridge_mbt.contains("pub struct RestMeta"))
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
  emit_moonbit_bridge_package(
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
  let bridge_js_path = @fs.realpath(wbtest_join_path(root, "bridge.js")) catch {
    _ => wbtest_join_path(root, "bridge.js")
  }
  assert_true(bridge_mbt.contains("pub struct RestMeta"))
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
  emit_moonbit_bridge_package(
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
  let bridge_js_path = @fs.realpath(wbtest_join_path(root, "bridge.js")) catch {
    _ => wbtest_join_path(root, "bridge.js")
  }
  assert_true(bridge_mbt.contains("pub struct RestMeta"))
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
  emit_moonbit_bridge_package(
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
  let bridge_js_path = @fs.realpath(wbtest_join_path(root, "bridge.js")) catch {
    _ => wbtest_join_path(root, "bridge.js")
  }
  assert_false(bridge_mbt.contains("pub struct RestMeta"))
  assert_true(
    bridge_mbt.contains(
      "#module(\"\{bridge_js_path}\")\npub extern \"js\" fn get_runtime_version() -> @js.Any = \"__ts_mbt_get_runtime_version\"",
    ),
  )
  assert_true(
    bridge_mbt.contains(
      "#module(\"\{bridge_js_path}\")\npub extern \"js\" fn get_build() -> @js.Any = \"__ts_mbt_get_build\"",
    ),
  )
  assert_true(
    bridge_mbt.contains(
      "#module(\"\{bridge_js_path}\")\npub extern \"js\" fn get_rest_meta() -> @js.Any = \"__ts_mbt_get_rest_meta\"",
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
  emit_moonbit_bridge_package(
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
  let bridge_js_path = @fs.realpath(wbtest_join_path(root, "bridge.js")) catch {
    _ => wbtest_join_path(root, "bridge.js")
  }
  assert_false(bridge_mbt.contains("pub struct RestMeta"))
  assert_true(
    bridge_mbt.contains(
      "#module(\"\{bridge_js_path}\")\npub extern \"js\" fn get_runtime_version() -> @js.Any = \"__ts_mbt_get_runtime_version\"",
    ),
  )
  assert_true(
    bridge_mbt.contains(
      "#module(\"\{bridge_js_path}\")\npub extern \"js\" fn get_build() -> @js.Any = \"__ts_mbt_get_build\"",
    ),
  )
  assert_true(
    bridge_mbt.contains(
      "#module(\"\{bridge_js_path}\")\npub extern \"js\" fn get_rest_meta() -> @js.Any = \"__ts_mbt_get_rest_meta\"",
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
  emit_moonbit_bridge_package(
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
  let bridge_js_path = @fs.realpath(wbtest_join_path(root, "bridge.js")) catch {
    _ => wbtest_join_path(root, "bridge.js")
  }
  assert_false(bridge_mbt.contains("pub struct RestMeta"))
  assert_true(
    bridge_mbt.contains(
      "#module(\"\{bridge_js_path}\")\npub extern \"js\" fn get_runtime_version() -> @js.Any = \"__ts_mbt_get_runtime_version\"",
    ),
  )
  assert_true(
    bridge_mbt.contains(
      "#module(\"\{bridge_js_path}\")\npub extern \"js\" fn get_build() -> @js.Any = \"__ts_mbt_get_build\"",
    ),
  )
  assert_true(
    bridge_mbt.contains(
      "#module(\"\{bridge_js_path}\")\npub extern \"js\" fn get_rest_meta() -> @js.Any = \"__ts_mbt_get_rest_meta\"",
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
  emit_moonbit_bridge_package(
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
  let bridge_js_path = @fs.realpath(wbtest_join_path(root, "bridge.js")) catch {
    _ => wbtest_join_path(root, "bridge.js")
  }
  assert_true(bridge_mbt.contains("pub struct RestMeta"))
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
  emit_moonbit_bridge_package(
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
  let bridge_js_path = @fs.realpath(wbtest_join_path(root, "bridge.js")) catch {
    _ => wbtest_join_path(root, "bridge.js")
  }
  assert_true(bridge_mbt.contains("pub struct RestMeta"))
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
  emit_moonbit_bridge_package(
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
  let bridge_js_path = @fs.realpath(wbtest_join_path(root, "bridge.js")) catch {
    _ => wbtest_join_path(root, "bridge.js")
  }
  assert_true(bridge_mbt.contains("pub struct RestMeta"))
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
  emit_moonbit_bridge_package(
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
  let bridge_js_path = @fs.realpath(wbtest_join_path(root, "bridge.js")) catch {
    _ => wbtest_join_path(root, "bridge.js")
  }
  assert_true(bridge_mbt.contains("pub struct RestMeta"))
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
  emit_moonbit_bridge_package(
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
  let bridge_js_path = @fs.realpath(wbtest_join_path(root, "bridge.js")) catch {
    _ => wbtest_join_path(root, "bridge.js")
  }
  assert_true(bridge_mbt.contains("pub struct RestMeta"))
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
  emit_moonbit_bridge_package(
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
  let bridge_js_path = @fs.realpath(wbtest_join_path(root, "bridge.js")) catch {
    _ => wbtest_join_path(root, "bridge.js")
  }
  assert_false(bridge_mbt.contains("pub struct RestMeta"))
  assert_true(
    bridge_mbt.contains(
      "#module(\"\{bridge_js_path}\")\npub extern \"js\" fn get_runtime_version() -> @js.Any = \"__ts_mbt_get_runtime_version\"",
    ),
  )
  assert_true(
    bridge_mbt.contains(
      "#module(\"\{bridge_js_path}\")\npub extern \"js\" fn get_build() -> @js.Any = \"__ts_mbt_get_build\"",
    ),
  )
  assert_true(
    bridge_mbt.contains(
      "#module(\"\{bridge_js_path}\")\npub extern \"js\" fn get_rest_meta() -> @js.Any = \"__ts_mbt_get_rest_meta\"",
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
    @analysis.ReadError(msg)
    | @analysis.ParseError(msg)
    | @analysis.ResolveError(msg) => {
      fail("Emit error: \{msg}")
      return
    }
  }
  assert_true(
    bundle.ffi_mbt.contains(
      "#module(\"/runtime/runtime-component.js\")\npub extern \"js\" fn render_badge(props : BadgeProps) -> JsxElement = \"renderBadge\"",
    ),
  )
  assert_false(bundle.bridge_js.contains("__ts_mbt_render_badge"))
}

///|
async test "emit_moonbit_js_ffi_texts handles runtime ts exported const arrow functions" {
  let bundle = emit_moonbit_js_ffi_texts(
    "fixtures/resolver/project/types/runtime-arrow-entry.ts", "/runtime/runtime-arrow.js",
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
    @analysis.ReadError(msg)
    | @analysis.ParseError(msg)
    | @analysis.ResolveError(msg) => {
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
    @analysis.ReadError(msg)
    | @analysis.ParseError(msg)
    | @analysis.ResolveError(msg) => {
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
    "fixtures/resolver/project/types/runtime-default-class-entry.ts", "/runtime/runtime-default-class.js",
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
    @analysis.ReadError(msg)
    | @analysis.ParseError(msg)
    | @analysis.ResolveError(msg) => {
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
    @analysis.ReadError(msg)
    | @analysis.ParseError(msg)
    | @analysis.ResolveError(msg) => {
      fail("Emit error: \{msg}")
      return
    }
  }
  assert_true(bundle.ffi_mbt.contains("pub extern \"js\" fn get_default()"))
  assert_true(bundle.bridge_js.contains("export function __ts_mbt_get_default"))
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
      entry_path, "/runtime/neverthrow-like.js",
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
    emit_moonbit_scaffold_from_ts(
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
async test "ensure_moonbit_ts_scaffoldable allows namespace export surfaces" {
  ensure_moonbit_ts_scaffoldable(
    "fixtures/resolver/project/types/ns-entry.d.ts",
  ) catch {
    @analysis.ReadError(msg)
    | @analysis.ParseError(msg)
    | @analysis.ResolveError(msg) => {
      fail("Unexpected error: \{msg}")
      return
    }
  }
}

///|
async test "ensure_moonbit_ts_scaffoldable rejects ambiguous export surfaces" {
  ensure_moonbit_ts_scaffoldable(
    "fixtures/resolver/project/types/ambiguous-entry.d.ts",
  ) catch {
    @analysis.ResolveError(msg) => {
      assert_true(msg.contains("ambiguous re-export"))
      assert_true(msg.contains("Shared"))
      assert_true(
        msg.contains("fixtures/resolver/project/types/ambiguous-a.d.ts"),
      )
      assert_true(
        msg.contains("fixtures/resolver/project/types/ambiguous-b.d.ts"),
      )
      return
    }
    @analysis.ReadError(msg) | @analysis.ParseError(msg) => {
      fail("Unexpected error: \{msg}")
      return
    }
  }
  fail("Expected ambiguous scaffoldability check to fail")
}

///|
async test "emit_moonbit_scaffold_from_ts handles namespace export surfaces" {
  let root = wbtest_tmp_project_benchmark_root("bridge_scaffold_namespace")
  let _ = try? @fs.rmdir(root, recursive=true)
  emit_moonbit_scaffold_from_ts(
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
async test "emit_moonbit_decl_text handles package exports wildcard subpath entry" {
  let actual = emit_moonbit_decl_text(
    "fixtures/resolver/project/types/pattern-package-entry.d.ts",
  ) catch {
    @analysis.ReadError(msg)
    | @analysis.ParseError(msg)
    | @analysis.ResolveError(msg) => {
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
    @analysis.ReadError(msg)
    | @analysis.ParseError(msg)
    | @analysis.ResolveError(msg) => {
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
    @analysis.ReadError(msg)
    | @analysis.ParseError(msg)
    | @analysis.ResolveError(msg) => {
      fail("Emit error: \{msg}")
      return
    }
  }
  assert_true(bundle.ffi_mbt.contains("#external\ntype NodeJsProcessEnv"))
  assert_false(bundle.bridge_js.contains("__ts_mbt_has_env"))
}
