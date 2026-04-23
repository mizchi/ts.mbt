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
