///|
async test "bridge: emit TypeScript declarations directly from mbti" {
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
async test "bridge: emit TypeScript declarations keeps pub(all) types used by public api and normalizes optional tuples" {
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
async test "bridge: emit TypeScript declarations from real pkg.generated.mbti keeps public helper types readable" {
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
async test "bridge: emit TypeScript declarations sanitizes imported namespace aliases" {
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
async test "bridge: emit TypeScript declarations unwraps grouped optional function types" {
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
async test "bridge: emit TypeScript declarations keeps real runtime function fields valid" {
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
test "bridge: emit TypeScript declarations supports opaque public types and tuple structs" {
  let source =
    #|// Generated by `moon info`
    #|package "demo/opaque"
    #|
    #|// Values
    #|pub fn read_id(InternId) -> Result[String, Error]
    #|
    #|// Errors
    #|
    #|// Types and methods
    #|pub type Any
    #|
    #|pub type Promise[T]
    #|
    #|pub(all) struct InternId(Int) derive(Eq)
    #|
    #|pub struct Revision(Int) derive(Compare, Eq, Hash)
    #|pub fn Revision::next(Self) -> Self
    #|
    #|// Type aliases
  let actual = parse_mbti_to_typescript(source) catch {
    MbtiTypescriptDeclError::ReadError(msg)
    | MbtiTypescriptDeclError::ParseError(msg) =>
      fail("MBTI emit error: \{msg}")
  }
  assert_true(
    actual.contains(
      "export type Result<T, E> = { $tag: \"Ok\"; _0: T } | { $tag: \"Err\"; _0: E };",
    ),
  )
  assert_true(
    actual.contains(
      "export function read_id(arg0: InternId): Result<string, Error>;",
    ),
  )
  assert_true(actual.contains("export interface Any {"))
  assert_true(actual.contains("export interface Promise<T> {"))
  assert_true(
    actual.contains("export interface InternId extends Eq<InternId> {"),
  )
  assert_true(actual.contains("  _0: number;"))
  assert_true(actual.contains("export interface Revision extends "))
  assert_true(actual.contains("Eq<Revision>"))
  assert_true(actual.contains("Compare"))
  assert_true(actual.contains("Hash"))
  assert_true(actual.contains("  next(): Revision;"))
}

///|
test "bridge: emit TypeScript declarations normalizes StringView" {
  let source =
    #|// Generated by `moon info`
    #|package "demo/string-view"
    #|
    #|// Values
    #|pub fn format(StringView) -> StringView
    #|pub fn parse(StringView) -> Result[StringView, Error]
    #|
    #|// Errors
    #|
    #|// Types and methods
    #|
    #|// Type aliases
  let actual = parse_mbti_to_typescript(source) catch {
    MbtiTypescriptDeclError::ReadError(msg)
    | MbtiTypescriptDeclError::ParseError(msg) =>
      fail("MBTI emit error: \{msg}")
  }
  assert_true(actual.contains("export function format(arg0: string): string;"))
  assert_true(
    actual.contains(
      "export function parse(arg0: string): Result<string, Error>;",
    ),
  )
  assert_false(actual.contains("StringView"))
}

///|
test "bridge: emit TypeScript declarations declares builtin StringBuilder" {
  let source =
    #|// Generated by `moon info`
    #|package "demo/string-builder"
    #|
    #|// Values
    #|pub fn write_to(StringBuilder) -> Unit
    #|
    #|// Errors
    #|
    #|// Types and methods
    #|
    #|// Type aliases
  let actual = parse_mbti_to_typescript(source) catch {
    MbtiTypescriptDeclError::ReadError(msg)
    | MbtiTypescriptDeclError::ParseError(msg) =>
      fail("MBTI emit error: \{msg}")
  }
  assert_true(actual.contains("export interface StringBuilder {\n}"))
  assert_true(
    actual.contains("export function write_to(arg0: StringBuilder): void;"),
  )
}

///|
test "bridge: emit TypeScript declarations keeps required params after optional params valid" {
  let source =
    #|// Generated by `moon info`
    #|package "demo/optional-before-required"
    #|
    #|// Values
    #|pub fn view(id? : String, gap? : Int, Array[String]) -> Unit
    #|pub fn run(callback : () -> Unit, mouse? : Bool) -> Unit
    #|
    #|// Errors
    #|
    #|// Types and methods
    #|
    #|// Type aliases
  let actual = parse_mbti_to_typescript(source) catch {
    MbtiTypescriptDeclError::ReadError(msg)
    | MbtiTypescriptDeclError::ParseError(msg) =>
      fail("MBTI emit error: \{msg}")
  }
  assert_true(
    actual.contains(
      "export function view(id: string | undefined, gap: number | undefined, arg2: Array<string>): void;",
    ),
  )
  assert_true(
    actual.contains(
      "export function run(callback: () => void, mouse?: boolean): void;",
    ),
  )
}

///|
test "bridge: emit TypeScript declarations normalizes async and raising function types" {
  let source =
    #|// Generated by `moon info`
    #|package "demo/async"
    #|
    #|// Values
    #|pub fn[E, A] async_(render~ : async () -> Node[E, A], fallback~ : () -> Node[E, A], on_error? : ((Error) -> Node[E, A])?) -> Node[E, A]
    #|pub async fn sleep(ms : Int) -> Unit noraise
    #|
    #|// Errors
    #|
    #|// Types and methods
    #|pub enum Node[E, A] {
    #|  Async(async () -> Node[Unit, String])
    #|}
    #|
    #|pub(all) struct Boundary[E, A] {
    #|  children : () -> Node[E, A] raise
    #|  fallback : (Error, () -> Unit) -> Node[E, A] raise
    #|  render : async () -> Node[E, A]
    #|}
    #|
    #|// Type aliases
  let actual = parse_mbti_to_typescript(source) catch {
    MbtiTypescriptDeclError::ReadError(msg)
    | MbtiTypescriptDeclError::ParseError(msg) =>
      fail("MBTI emit error: \{msg}")
  }
  assert_true(
    actual.contains(
      "export function async_<E, A>(render_: () => Promise<Node<E, A>>, fallback_: () => Node<E, A>, on_error?: ((arg0: Error) => Node<E, A>) | undefined): Node<E, A>;",
    ),
  )
  assert_true(
    actual.contains("export function sleep(ms: number): Promise<void>;"),
  )
  assert_true(
    actual.contains(
      "export type Node<E, A> = { $tag: \"Async\"; _0: () => Promise<Node<void, string>> };",
    ),
  )
  assert_true(actual.contains("  children: () => Node<E, A>;"))
  assert_true(
    actual.contains(
      "  fallback: (arg0: Error, arg1: () => void) => Node<E, A>;",
    ),
  )
  assert_true(actual.contains("  render: () => Promise<Node<E, A>>;"))
  assert_false(actual.contains("async ()"))
  assert_false(actual.contains(" raise"))
  assert_false(actual.contains(" noraise"))
  assert_false(actual.contains("->"))
}

///|
async test "bridge: emit TypeScript declarations covers reverse-direction edge type shapes" {
  let actual = emit_typescript_decl_from_mbti_path(
    "fixtures/mbti_typescript/reverse_edge.pkg.generated.mbti",
  ) catch {
    MbtiTypescriptDeclError::ReadError(msg)
    | MbtiTypescriptDeclError::ParseError(msg) =>
      fail("MBTI emit error: \{msg}")
  }
  assert_true(
    actual.contains(
      "export function consume_callbacks(handler: (arg0: string, arg1: number) => void, on_error: ((arg0: Error) => void) | undefined, required: Array<string>): void;",
    ),
  )
  assert_true(
    actual.contains(
      "export function load_all(keys: Array<string>): Promise<Result<Array<[string, number]>, Error>>;",
    ),
  )
  assert_true(
    actual.contains(
      "export function borrow_bytes(arg0: Uint8Array): Uint8Array;",
    ),
  )
  assert_true(
    actual.contains(
      "export function update_ref(state: { val: Array<bigint> }, next: ReadonlyArray<bigint>): Set<string>;",
    ),
  )
  assert_true(
    actual.contains(
      "export interface CallbackBox<T> {\n  current: T;\n  on_change: ((arg0: T) => void) | undefined;\n  meta: Map<string, Array<boolean>>;\n  map<U>(mapper: (arg0: T) => U): CallbackBox<U>;\n  tap(effect: (self: CallbackBox<T>) => void): CallbackBox<T>;\n}",
    ),
  )
  assert_true(
    actual.contains(
      "export type Result<T, E> = { $tag: \"Ok\"; _0: T } | { $tag: \"Err\"; _0: E };",
    ),
  )
  assert_true(
    actual.contains(
      "export type Status = { $tag: \"Ready\"; _0: number } | { $tag: \"Failed\"; _0: Error };",
    ),
  )
  assert_true(
    actual.contains("export type Task<T> = () => Promise<Result<T, Error>>;"),
  )
  assert_true(
    actual.contains(
      "export type MaybeHandler<T> = ((arg0: T) => void) | undefined;",
    ),
  )
  assert_false(actual.contains(" raise"))
  assert_false(actual.contains("->"))
  assert_false(actual.contains("&BytesView"))
}

///|
test "bridge: emit TypeScript declarations normalizes trait bounds and reserved function names" {
  let source =
    #|// Generated by `moon info`
    #|package "demo/js-core"
    #|
    #|// Values
    #|pub fn[E : Show + Error] export_sync(() -> Any) -> Any
    #|pub fn null() -> Any
    #|pub fn[T : Eq] watch(() -> T) -> Unit
    #|
    #|// Errors
    #|
    #|// Types and methods
    #|pub type Any
    #|
    #|// Type aliases
  let actual = parse_mbti_to_typescript(source) catch {
    MbtiTypescriptDeclError::ReadError(msg)
    | MbtiTypescriptDeclError::ParseError(msg) =>
      fail("MBTI emit error: \{msg}")
  }
  assert_true(
    actual.contains(
      "export function export_sync<E extends Show & Error>(arg0: () => Any): Any;",
    ),
  )
  assert_true(actual.contains("export interface Show {"))
  assert_true(actual.contains("export interface Eq {"))
  assert_true(actual.contains("export function null_(): Any;"))
  assert_true(actual.contains("export function watch<T extends Eq>"))
  assert_false(actual.contains("Show + Error"))
  assert_false(actual.contains("export function null():"))
}

///|
test "bridge: emit TypeScript declarations avoids field method and import alias name collisions" {
  let source =
    #|// Generated by `moon info`
    #|package "demo/collisions"
    #|
    #|import {
    #|  "demo/collisions/symbol" @symbol
    #|}
    #|
    #|// Values
    #|pub fn symbol(String) -> @symbol.Symbol
    #|
    #|// Errors
    #|
    #|// Types and methods
    #|pub(all) struct PromiseResolvers[T] {
    #|  resolve : (T) -> Unit
    #|  reject : (Error) -> Unit
    #|}
    #|pub fn PromiseResolvers::resolve(Self, T) -> Unit
    #|pub fn PromiseResolvers::reject(Self, Error) -> Unit
    #|
    #|// Type aliases
  let actual = parse_mbti_to_typescript(source) catch {
    MbtiTypescriptDeclError::ReadError(msg)
    | MbtiTypescriptDeclError::ParseError(msg) =>
      fail("MBTI emit error: \{msg}")
  }
  assert_true(actual.contains("import type * as symbol_ from"))
  assert_true(
    actual.contains("export function symbol(arg0: string): symbol_.Symbol;"),
  )
  assert_true(actual.contains("  resolve: (arg0: T) => void;"))
  assert_true(actual.contains("  resolve_(arg0: T): void;"))
  assert_true(actual.contains("  reject: (arg0: Error) => void;"))
  assert_true(actual.contains("  reject_(arg0: Error): void;"))
}

///|
test "bridge: emit TypeScript declarations keeps private local opaque types referenced by public api" {
  let source =
    #|// Generated by `moon info`
    #|package "demo/private"
    #|
    #|// Values
    #|pub fn use_runtime(Runtime) -> Iter[String]
    #|
    #|// Errors
    #|
    #|// Types and methods
    #|type Runtime
    #|
    #|type Memo[T]
    #|
    #|pub(all) struct Holder {
    #|  runtime : Runtime
    #|  memo : Memo[String]
    #|}
    #|
    #|// Type aliases
  let actual = parse_mbti_to_typescript(source) catch {
    MbtiTypescriptDeclError::ReadError(msg)
    | MbtiTypescriptDeclError::ParseError(msg) =>
      fail("MBTI emit error: \{msg}")
  }
  assert_true(actual.contains("interface Runtime {\n}"))
  assert_true(actual.contains("interface Memo<T> {\n}"))
  assert_true(
    actual.contains(
      "export function use_runtime(arg0: Runtime): Iterable<string>;",
    ),
  )
  assert_true(actual.contains("  runtime: Runtime;"))
  assert_true(actual.contains("  memo: Memo<string>;"))
  assert_false(actual.contains("export interface Runtime"))
}

///|
test "bridge: emit TypeScript declarations imports fully qualified external type paths" {
  let source =
    #|// Generated by `moon info`
    #|package "demo/full-path"
    #|
    #|// Values
    #|pub fn nodes(Array[@mizchi/luna/core.Node[Unit, String]]) -> @mizchi/luna/core.Node[Unit, String]
    #|
    #|// Errors
    #|
    #|// Types and methods
    #|
    #|// Type aliases
  let actual = parse_mbti_to_typescript(source) catch {
    MbtiTypescriptDeclError::ReadError(msg)
    | MbtiTypescriptDeclError::ParseError(msg) =>
      fail("MBTI emit error: \{msg}")
  }
  assert_true(
    actual.contains(
      "import type * as mizchi_luna_core from \"mizchi/luna/core\";",
    ),
  )
  assert_true(
    actual.contains(
      "export function nodes(arg0: Array<mizchi_luna_core.Node<void, string>>): mizchi_luna_core.Node<void, string>;",
    ),
  )
  let rewrites : Map[String, String] = {}
  rewrites["mizchi/luna/core"] = "./core"
  let rewritten = parse_mbti_to_typescript_with_import_rewrites(
    source, rewrites,
  ) catch {
    MbtiTypescriptDeclError::ReadError(msg)
    | MbtiTypescriptDeclError::ParseError(msg) =>
      fail("MBTI emit error: \{msg}")
  }
  assert_true(
    rewritten.contains("import type * as mizchi_luna_core from \"./core\";"),
  )
}

///|
test "bridge: emit TypeScript declarations unwraps borrowed types" {
  let source =
    #|// Generated by `moon info`
    #|package "demo/borrowed"
    #|
    #|import {
    #|  "moonbitlang/core/io" @io
    #|}
    #|
    #|// Values
    #|pub fn read(&@io.Reader, Array[&Node]) -> &Node
    #|
    #|// Errors
    #|
    #|// Types and methods
    #|pub type Node
    #|
    #|pub(all) struct Holder {
    #|  reader : &@io.Reader
    #|  node : &Node
    #|}
    #|
    #|// Type aliases
    #|pub type ReaderAlias = &@io.Reader
  let actual = parse_mbti_to_typescript(source) catch {
    MbtiTypescriptDeclError::ReadError(msg)
    | MbtiTypescriptDeclError::ParseError(msg) =>
      fail("MBTI emit error: \{msg}")
  }
  assert_true(
    actual.contains("import type * as io from \"moonbitlang/core/io\";"),
  )
  assert_true(
    actual.contains(
      "export function read(arg0: io.Reader, arg1: Array<Node>): Node;",
    ),
  )
  assert_true(actual.contains("  reader: io.Reader;"))
  assert_true(actual.contains("  node: Node;"))
  assert_true(actual.contains("export type ReaderAlias = io.Reader;"))
  assert_false(actual.contains("&@"))
  assert_false(actual.contains("&Node"))
}

///|
test "bridge: emit TypeScript declarations emits builtin Json when referenced" {
  let source =
    #|// Generated by `moon info`
    #|package "demo/json"
    #|
    #|// Values
    #|pub fn ok(Json) -> Result[Json, Error]
    #|
    #|// Errors
    #|
    #|// Types and methods
    #|
    #|// Type aliases
  let actual = parse_mbti_to_typescript(source) catch {
    MbtiTypescriptDeclError::ReadError(msg)
    | MbtiTypescriptDeclError::ParseError(msg) =>
      fail("MBTI emit error: \{msg}")
  }
  assert_true(actual.contains("export type Json ="))
  assert_true(
    actual.contains("export function ok(arg0: Json): Result<Json, Error>;"),
  )
}

///|
test "bridge: emit TypeScript declarations renders public trait blocks as interfaces" {
  let source =
    #|// Generated by `moon info`
    #|package "demo/traits"
    #|
    #|// Values
    #|
    #|// Errors
    #|
    #|// Types and methods
    #|pub(all) struct StatInfo {
    #|  size : Int
    #|} derive(Eq)
    #|pub impl FileStat for StatInfo
    #|
    #|// Type aliases
    #|
    #|// Traits
    #|pub(open) trait FileStat {
    #|  size(Self) -> Int
    #|}
    #|
    #|pub(open) trait FileSystem {
    #|  read_file_sync(Self, String) -> String raise
    #|  exists_sync(Self, String) -> Bool
    #|}
  let actual = parse_mbti_to_typescript(source) catch {
    MbtiTypescriptDeclError::ReadError(msg)
    | MbtiTypescriptDeclError::ParseError(msg) =>
      fail("MBTI emit error: \{msg}")
  }
  assert_true(actual.contains("export interface FileStat {"))
  assert_true(actual.contains("  size: number;"))
  assert_true(actual.contains("export interface FileSystem {"))
  assert_true(actual.contains("  read_file_sync(arg0: string): string;"))
  assert_true(actual.contains("  exists_sync(arg0: string): boolean;"))
  assert_true(
    actual.contains(
      "export interface StatInfo extends Eq<StatInfo>, FileStat {",
    ),
  )
}

///|
async test "bridge: emit TypeScript declarations supports explicit import aliases in mbti fixtures" {
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
async test "bridge: emit MoonBit JS link config from mbti keeps only top-level free functions" {
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
async test "bridge: emit MoonBit JS link config from mbti includes top-level async functions and excludes methods" {
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
async test "bridge: emit TypeScript package bundle from mbti rewrites local imports to sibling declarations" {
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
test "bridge: parse TypeScript import rewrite map source accepts string-object json" {
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
async test "bridge: emit TypeScript package bundle from mbti rewrites external imports through configured map" {
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
async test "bridge: emit TypeScript scaffold bundle from mbti combines autolink config and declaration files" {
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
    bundle.package_json.contains(
      "\".\": { \"types\": \"./index.d.ts\", \"import\": \"./index.js\" }",
    ),
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
async test "bridge: emit TypeScript scaffold bundle from mbti rewrites external imports through configured map" {
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
async test "bridge: emit TypeScript scaffold bundle keeps optional named params linkable" {
  let bundle = emit_typescript_scaffold_bundle_from_mbti_path(
    "fixtures/mbti_typescript/reverse_edge.pkg.generated.mbti",
  ) catch {
    MbtiTypescriptDeclError::ReadError(msg)
    | MbtiTypescriptDeclError::ParseError(msg) =>
      fail("MBTI scaffold bundle emit error: \{msg}")
  }
  assert_true(bundle.moon_pkg_json.contains("\"consume_callbacks\""))
  assert_true(
    bundle.autolink_glue_mbt.contains(
      "pub fn consume_callbacks(handler : (String, Int) -> Unit, on_error : ((Error) -> Unit)?, required : Array[String]) -> Unit {",
    ),
  )
  assert_true(
    bundle.autolink_glue_mbt.contains(
      "@tsmbt_source.consume_callbacks(handler, on_error?, required)",
    ),
  )
  assert_true(
    bundle.autolink_glue_mbt.contains(
      "pub fn borrow_bytes(arg0 : Bytes) -> Bytes {",
    ),
  )
  assert_true(
    bundle.autolink_glue_mbt.contains("@tsmbt_source.borrow_bytes(arg0.view())"),
  )
  assert_true(
    bundle.autolink_glue_mbt.contains(
      "pub fn update_ref(state : Ref[Array[Int64]], next : Array[UInt64]) -> Set[String] {",
    ),
  )
  assert_true(
    bundle.autolink_glue_mbt.contains(
      "@tsmbt_source.update_ref(state, next[:])",
    ),
  )
}

///|
async test "bridge: emit TypeScript facade scaffold bundle from mbti adds facade exports and wrapper source" {
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
    bundle.autolink_glue_mbt.contains(
      "pub fn loader_new(arg0 : String) -> @tsmbt_source.Loader {",
    ),
  )
  assert_true(
    bundle.autolink_glue_mbt.contains("@tsmbt_source.Loader::new(arg0)"),
  )
  assert_true(
    bundle.autolink_glue_mbt.contains(
      "pub fn loader_load(self_ : @tsmbt_source.Loader) -> String {",
    ),
  )
  assert_true(bundle.autolink_glue_mbt.contains("self_.load()"))
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
async test "bridge: emit TypeScript facade scaffold bundle keeps root imports in wrapper source" {
  let bundle = emit_typescript_facade_scaffold_bundle_from_mbti_path(
    "fixtures/mbti_typescript_facade_package/pkg.generated.mbti",
  ) catch {
    MbtiTypescriptDeclError::ReadError(msg)
    | MbtiTypescriptDeclError::ParseError(msg) =>
      fail("MBTI facade scaffold bundle emit error: \{msg}")
  }
  assert_true(
    bundle.autolink_glue_mbt.contains(
      "pub fn loader_new(arg0 : @child.Item) -> @tsmbt_source.Loader {",
    ),
  )
  assert_true(
    bundle.autolink_glue_mbt.contains(
      "pub fn loader_load(self_ : @tsmbt_source.Loader) -> @child.Item {",
    ),
  )
  assert_true(bundle.moon_pkg_json.contains("\"path\": \"demo/facade\""))
  assert_true(bundle.moon_pkg_json.contains("\"alias\": \"tsmbt_source\""))
  assert_true(bundle.moon_pkg_json.contains("\"path\": \"demo/facade/child\""))
}

///|
async test "bridge: emit TypeScript facade scaffold bundle skips private root types in wrapper source" {
  let bundle = emit_typescript_facade_scaffold_bundle_from_mbti_path(
    "fixtures/mbti_typescript/private_facade.pkg.generated.mbti",
  ) catch {
    MbtiTypescriptDeclError::ReadError(msg)
    | MbtiTypescriptDeclError::ParseError(msg) =>
      fail("MBTI facade scaffold bundle emit error: \{msg}")
  }
  assert_true(bundle.autolink_glue_mbt.contains("database_current_revision"))
  assert_false(bundle.autolink_glue_mbt.contains("database_runtime"))
  let mut root_content = ""
  for file in bundle.files {
    if file.relative_path == "index.d.ts" {
      root_content = file.content
    }
  }
  assert_true(
    root_content.contains(
      "export function database_current_revision(self: Database): number;",
    ),
  )
  assert_false(root_content.contains("export function database_runtime"))
}

///|
async test "bridge: emit TypeScript facade scaffold bundle preserves raise effects in wrapper source" {
  let bundle = emit_typescript_facade_scaffold_bundle_from_mbti_path(
    "fixtures/mbti_typescript/effect_facade.pkg.generated.mbti",
  ) catch {
    MbtiTypescriptDeclError::ReadError(msg)
    | MbtiTypescriptDeclError::ParseError(msg) =>
      fail("MBTI facade scaffold bundle emit error: \{msg}")
  }
  assert_true(
    bundle.autolink_glue_mbt.contains(
      "pub fn parse(arg0 : String) -> @tsmbt_source.SemVer raise @tsmbt_source.SemVerError {",
    ),
  )
  assert_true(
    bundle.autolink_glue_mbt.contains(
      "pub fn sem_ver_parse_next(self_ : @tsmbt_source.SemVer, arg1 : String) -> @tsmbt_source.SemVer raise @tsmbt_source.SemVerError {",
    ),
  )
}

///|
async test "bridge: emit TypeScript facade scaffold bundle qualifies root trait bounds in wrapper source" {
  let bundle = emit_typescript_facade_scaffold_bundle_from_mbti_path(
    "fixtures/mbti_typescript/trait_bound_facade.pkg.generated.mbti",
  ) catch {
    MbtiTypescriptDeclError::ReadError(msg)
    | MbtiTypescriptDeclError::ParseError(msg) =>
      fail("MBTI facade scaffold bundle emit error: \{msg}")
  }
  assert_true(
    bundle.autolink_glue_mbt.contains(
      "pub fn[T : @tsmbt_source.InputLen] eof(arg0 : T) -> Bool {",
    ),
  )
}
