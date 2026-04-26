///|
async test "analysis: emit TypeScript declarations directly from mbti" {
  let actual = emit_typescript_decl_from_mbti_path(
    "fixtures/mbti_typescript/basic.pkg.generated.mbti",
  ) catch {
    MbtiTypescriptDeclError::ReadError(msg)
    | MbtiTypescriptDeclError::ParseError(msg) =>
      fail("MBTI emit error: \{msg}")
  }
  let expected =
    #|import type * as ast from "mizchi/ts/ast";
    #|import type * as json from "moonbitlang/core/json";
    #|import type * as debug from "moonbitlang/core/debug";
    #|
    #|export interface Show {
    #|  toString(): string;
    #|}
    #|
    #|export interface Eq<T> {
    #|  equals(other: T): boolean;
    #|}
    #|
    #|export interface Hash {
    #|}
    #|
    #|export interface Comparable<T0> {
    #|}
    #|
    #|export function identity<T>(arg0: T): T;
    #|
    #|export function debug_identity<T extends debug.Debug>(arg0: T): T;
    #|
    #|export function wrap_pair(arg0: string, arg1: number): [string, number];
    #|
    #|export type ParseError = ({ $tag: "InvalidFormat"; _0: string } | { $tag: "Overflow"; _0: number; _1: string }) & Show & Eq<ParseError>;
    #|
    #|export interface Box<T> extends Show, Eq<Box<T>>, Hash, Comparable<Box<T>> {
    #|  value: T;
    #|  unwrap(): T;
    #|  map<U>(arg0: (arg0: T) => U): Box<U>;
    #|  show_value(): string;
    #|}
    #|
    #|export namespace Box {
    #|  function new_<T>(arg0: T): Box<T>;
    #|}
    #|
    #|export interface ResultMethods<T, E> {
    #|  is_ok(): boolean;
    #|}
    #|
    #|export type Result<T, E> = ({ $tag: "Ok"; _0: T } | { $tag: "Err"; _0: E }) & ResultMethods<T, E>;
    #|
    #|export interface TypedModuleHolder {
    #|  module: ast.TsModule;
    #|}
    #|
    #|export type InternalThing<T> = ({ $tag: "Hidden"; _0: T }) & Eq<InternalThing<T>> & Hash;
    #|
    #|export type Identity<T> = T;
    #|
    #|export interface MaybeStringMethods {
    #|  is_empty(): boolean;
    #|}
    #|
    #|export type MaybeString = (string | undefined) & MaybeStringMethods & Show & Hash & json.ToJson;
    #|
    #|export type DerivedStatus = ({ $tag: "Ready" }) & Eq<DerivedStatus>;
  assert_eq(actual, expected)
}

///|
async test "analysis: emit TypeScript declarations keeps pub(all) types used by public api and normalizes optional tuples" {
  let actual = emit_typescript_decl_from_mbti_path(
    "fixtures/mbti_typescript/pub_all.pkg.generated.mbti",
  ) catch {
    MbtiTypescriptDeclError::ReadError(msg)
    | MbtiTypescriptDeclError::ParseError(msg) =>
      fail("MBTI emit error: \{msg}")
  }
  let expected =
    #|export function analyze_truthiness_guard(arg0: string): [string, boolean] | undefined;
    #|
    #|export interface AnalysisResultMethods<T> {
    #|  is_ok(): boolean;
    #|}
    #|
    #|export type AnalysisResult<T> = ({ $tag: "Ok"; _0: T; _1: Array<string> } | { $tag: "Err"; _0: Array<string> }) & AnalysisResultMethods<T>;
    #|
    #|export type AnalysisErrorKind = { $tag: "SyntaxError" } | { $tag: "ReferenceError" };
  assert_eq(actual, expected)
}

///|
async test "analysis: emit TypeScript declarations from real pkg.generated.mbti keeps public helper types readable" {
  let actual = emit_typescript_decl_from_mbti_path(
    "src/analysis/pkg.generated.mbti",
  ) catch {
    MbtiTypescriptDeclError::ReadError(msg)
    | MbtiTypescriptDeclError::ParseError(msg) =>
      fail("MBTI emit error: \{msg}")
  }
  assert_true(actual.contains("export type AnalysisResult<T> ="))
  assert_true(actual.contains("export interface AnalysisResultMethods<T> {"))
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
  assert_true(actual.contains("Eq<AnalysisErrorKind>"))
  assert_false(actual.contains("debug.Debug"))
  assert_false(actual.contains("(String, Bool)?"))
  assert_false(actual.contains("Self["))
}

///|
async test "analysis: emit TypeScript declarations sanitizes imported namespace aliases" {
  let actual = emit_typescript_decl_from_mbti_path(
    "fixtures/mbti_typescript/import_keyword_alias.pkg.generated.mbti",
  ) catch {
    MbtiTypescriptDeclError::ReadError(msg)
    | MbtiTypescriptDeclError::ParseError(msg) =>
      fail("MBTI emit error: \{msg}")
  }
  let expected =
    #|import type * as with_ from "demo/with";
    #|import type * as class_ from "demo/class";
    #|
    #|export function consume(arg0: class_.Value, arg1: with_.Handler): class_.Result<with_.Handler>;
  assert_eq(actual, expected)
}

///|
async test "analysis: emit TypeScript declarations unwraps grouped optional function types" {
  let actual = emit_typescript_decl_from_mbti_path(
    "fixtures/mbti_typescript/grouped_function_option.pkg.generated.mbti",
  ) catch {
    MbtiTypescriptDeclError::ReadError(msg)
    | MbtiTypescriptDeclError::ParseError(msg) =>
      fail("MBTI emit error: \{msg}")
  }
  let expected =
    #|export type Signal = { $tag: "Continue" };
    #|
    #|export interface Holder {
    #|  cont: ((arg0: string) => Signal) | undefined;
    #|}
  assert_eq(actual, expected)
}

///|
async test "analysis: emit TypeScript declarations keeps real runtime function fields valid" {
  let actual = emit_typescript_decl_from_mbti_path(
    "src/runtime/pkg.generated.mbti",
  ) catch {
    MbtiTypescriptDeclError::ReadError(msg)
    | MbtiTypescriptDeclError::ParseError(msg) =>
      fail("MBTI emit error: \{msg}")
  }
  assert_true(
    actual.contains("cont: ((arg0: JSValue) => GenSignal) | undefined;"),
  )
  assert_false(actual.contains("->"))
}

///|
async test "analysis: emit TypeScript declarations supports explicit import aliases in mbti fixtures" {
  let actual = emit_typescript_decl_from_mbti_path(
    "fixtures/mbti_typescript/import_explicit_alias.pkg.generated.mbti",
  ) catch {
    MbtiTypescriptDeclError::ReadError(msg)
    | MbtiTypescriptDeclError::ParseError(msg) =>
      fail("MBTI emit error: \{msg}")
  }
  let expected =
    #|import type * as wasm_runtime from "demo/runtime";
    #|
    #|export interface RuntimeHolder {
    #|  runtime: wasm_runtime.Runtime;
    #|}
  assert_eq(actual, expected)
}

///|
async test "analysis: emit MoonBit JS link config from mbti keeps only top-level free functions" {
  let actual = emit_moonbit_js_link_config_from_mbti_path(
    "fixtures/mbti_typescript/basic.pkg.generated.mbti",
  ) catch {
    MbtiJsLinkConfigError::ReadError(msg)
    | MbtiJsLinkConfigError::ParseError(msg) =>
      fail("MBTI JS link emit error: \{msg}")
  }
  let expected =
    #|{
    #|  "link": {
    #|    "js": {
    #|      "exports": [
    #|        "identity",
    #|        "debug_identity",
    #|        "wrap_pair"
    #|      ],
    #|      "format": "esm"
    #|    }
    #|  }
    #|}
  assert_eq(actual, expected)
}

///|
async test "analysis: emit MoonBit JS link config from mbti includes top-level async functions and excludes methods" {
  let actual = emit_moonbit_js_link_config_from_mbti_path(
    "fixtures/mbti_typescript/link_config_async.pkg.generated.mbti",
  ) catch {
    MbtiJsLinkConfigError::ReadError(msg)
    | MbtiJsLinkConfigError::ParseError(msg) =>
      fail("MBTI JS link emit error: \{msg}")
  }
  let expected =
    #|{
    #|  "link": {
    #|    "js": {
    #|      "exports": [
    #|        "fetch_value",
    #|        "transform"
    #|      ],
    #|      "format": "esm"
    #|    }
    #|  }
    #|}
  assert_eq(actual, expected)
}

///|
async test "analysis: emit TypeScript package bundle from mbti rewrites local imports to sibling declarations" {
  let files = emit_typescript_package_bundle_from_mbti_path(
    "fixtures/mbti_typescript_package/pkg.generated.mbti",
  ) catch {
    MbtiTypescriptDeclError::ReadError(msg)
    | MbtiTypescriptDeclError::ParseError(msg) =>
      fail("MBTI package bundle emit error: \{msg}")
  }
  assert_eq(files.length(), 2)
  let mut root_content = ""
  let mut child_content = ""
  for file in files {
    if file.relative_path == "index.d.ts" {
      root_content = file.content
    } else if file.relative_path == "child/index.d.ts" {
      child_content = file.content
    }
  }
  assert_true(root_content != "")
  assert_true(child_content != "")
  assert_true(root_content.contains("import type * as child from \"./child\";"))
  assert_true(
    root_content.contains(
      "import type * as debug from \"moonbitlang/core/debug\";",
    ),
  )
  assert_true(root_content.contains("item: child.Item;"))
  assert_true(child_content.contains("export interface Item {"))
  assert_false(root_content.contains("\"demo/pkg/child\""))
}

///|
test "analysis: parse TypeScript import rewrite map source accepts string-object json" {
  let rewrites = parse_typescript_import_rewrite_map_source(
    "{\"moonbitlang/core/debug\":\"demo-debug\"}",
  )
  match rewrites {
    Some(rewrites) => {
      assert_eq(rewrites.length(), 1)
      assert_eq(rewrites["moonbitlang/core/debug"], "demo-debug")
    }
    None => fail("Expected import rewrite map to parse")
  }
}

///|
async test "analysis: emit TypeScript package bundle from mbti rewrites external imports through configured map" {
  let import_rewrites : Map[String, String] = {}
  import_rewrites["moonbitlang/core/debug"] = "demo-debug"
  let files = emit_typescript_package_bundle_from_mbti_path_with_import_rewrites(
    "fixtures/mbti_typescript_package/pkg.generated.mbti", import_rewrites,
  ) catch {
    MbtiTypescriptDeclError::ReadError(msg)
    | MbtiTypescriptDeclError::ParseError(msg) =>
      fail("MBTI package bundle emit error: \{msg}")
  }
  let mut root_content = ""
  for file in files {
    if file.relative_path == "index.d.ts" {
      root_content = file.content
    }
  }
  assert_true(
    root_content.contains("import type * as debug from \"demo-debug\";"),
  )
  assert_false(root_content.contains("\"moonbitlang/core/debug\""))
}

///|
async test "analysis: emit TypeScript scaffold bundle from mbti combines autolink config and declaration files" {
  let bundle = emit_typescript_scaffold_bundle_from_mbti_path(
    "fixtures/mbti_typescript_package/pkg.generated.mbti",
  ) catch {
    MbtiTypescriptDeclError::ReadError(msg)
    | MbtiTypescriptDeclError::ParseError(msg) =>
      fail("MBTI scaffold bundle emit error: \{msg}")
  }
  assert_true(bundle.moon_pkg_json.contains("\"make\""))
  assert_true(bundle.moon_pkg_json.contains("\"render\""))
  assert_false(bundle.moon_pkg_json.contains("Holder::"))
  assert_true(bundle.package_json.contains("\"name\": \"@demo/pkg\""))
  assert_true(bundle.package_json.contains("\"types\": \"./index.d.ts\""))
  assert_true(
    bundle.package_json.contains("\".\": { \"types\": \"./index.d.ts\" }"),
  )
  assert_true(
    bundle.package_json.contains(
      "\"./child\": { \"types\": \"./child/index.d.ts\" }",
    ),
  )
  assert_true(
    bundle.autolink_diagnostics_md.contains(
      "Public members omitted from link.js.exports",
    ),
  )
  assert_true(bundle.autolink_diagnostics_md.contains("demo/pkg/child"))
  assert_true(bundle.autolink_diagnostics_md.contains("Item::new"))
  assert_eq(bundle.files.length(), 2)
}

///|
async test "analysis: emit TypeScript scaffold bundle from mbti rewrites external imports through configured map" {
  let import_rewrites : Map[String, String] = {}
  import_rewrites["moonbitlang/core/debug"] = "demo-debug"
  let bundle = emit_typescript_scaffold_bundle_from_mbti_path_with_import_rewrites(
    "fixtures/mbti_typescript_package/pkg.generated.mbti", import_rewrites,
  ) catch {
    MbtiTypescriptDeclError::ReadError(msg)
    | MbtiTypescriptDeclError::ParseError(msg) =>
      fail("MBTI scaffold bundle emit error: \{msg}")
  }
  let mut root_content = ""
  for file in bundle.files {
    if file.relative_path == "index.d.ts" {
      root_content = file.content
    }
  }
  assert_true(bundle.package_json.contains("\"name\": \"@demo/pkg\""))
  assert_true(bundle.autolink_diagnostics_md.contains("Item::new"))
  assert_true(
    root_content.contains("import type * as debug from \"demo-debug\";"),
  )
  assert_false(root_content.contains("\"moonbitlang/core/debug\""))
}

///|
async test "analysis: emit TypeScript facade scaffold bundle from mbti adds facade exports and wrapper source" {
  let bundle = emit_typescript_facade_scaffold_bundle_from_mbti_path(
    "fixtures/mbti_typescript/link_config_async.pkg.generated.mbti",
  ) catch {
    MbtiTypescriptDeclError::ReadError(msg)
    | MbtiTypescriptDeclError::ParseError(msg) =>
      fail("MBTI facade scaffold bundle emit error: \{msg}")
  }
  assert_true(bundle.moon_pkg_json.contains("\"fetch_value\""))
  assert_true(bundle.moon_pkg_json.contains("\"transform\""))
  assert_true(bundle.moon_pkg_json.contains("\"loader_new\""))
  assert_true(bundle.moon_pkg_json.contains("\"loader_load\""))
  assert_true(
    bundle.autolink_facade_mbt.contains(
      "pub fn loader_new(arg0 : String) -> Loader {",
    ),
  )
  assert_true(bundle.autolink_facade_mbt.contains("Loader::new(arg0)"))
  assert_true(
    bundle.autolink_facade_mbt.contains(
      "pub fn loader_load(self : Loader) -> String {",
    ),
  )
  assert_true(bundle.autolink_facade_mbt.contains("self.load()"))
  let mut root_content = ""
  for file in bundle.files {
    if file.relative_path == "index.d.ts" {
      root_content = file.content
    }
  }
  assert_true(
    root_content.contains("export function loader_new(arg0: string): Loader;"),
  )
  assert_true(
    root_content.contains("export function loader_load(self: Loader): string;"),
  )
}

///|
async test "analysis: emit TypeScript facade scaffold bundle keeps root imports in wrapper source" {
  let bundle = emit_typescript_facade_scaffold_bundle_from_mbti_path(
    "fixtures/mbti_typescript_facade_package/pkg.generated.mbti",
  ) catch {
    MbtiTypescriptDeclError::ReadError(msg)
    | MbtiTypescriptDeclError::ParseError(msg) =>
      fail("MBTI facade scaffold bundle emit error: \{msg}")
  }
  assert_true(bundle.autolink_facade_mbt.contains("import {"))
  assert_true(bundle.autolink_facade_mbt.contains("\"demo/facade/child\","))
  assert_true(
    bundle.autolink_facade_mbt.contains(
      "pub fn loader_new(arg0 : @child.Item) -> Loader {",
    ),
  )
  assert_true(
    bundle.autolink_facade_mbt.contains(
      "pub fn loader_load(self : Loader) -> @child.Item {",
    ),
  )
}
