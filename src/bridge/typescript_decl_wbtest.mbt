///|
async test "bridge: normalize MoonBit generated TypeScript declarations inlines primitive aliases" {
  let actual = normalize_moonbit_generated_typescript_decl_from_entry_path(
    "fixtures/typescript_decl/moonbit_generated/app.d.ts",
  ) catch {
    ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
      fail("Normalize error: \{msg}")
  }
  let expected =
    #|export function describe_scaled_point(
    #|  x: number,
    #|  y: number,
    #|  factor: number,
    #|): string;
  assert_eq(actual, expected)
}

///|
async test "bridge: normalize MoonBit generated TypeScript declarations expands multiline aliases from moonbit.d.ts" {
  let actual = normalize_moonbit_generated_typescript_decl_from_entry_path(
    "fixtures/typescript_decl/moonbit_generated/result.d.ts",
  ) catch {
    ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
      fail("Normalize error: \{msg}")
  }
  let expected =
    #|export function parse_user(
    #|  input: string,
    #|): { $tag: 1; _0: string } | { $tag: 0; _0: number };
    #|
    #|export const EMPTY_BYTES: Uint8Array;
  assert_eq(actual, expected)
}

///|
async test "bridge: normalize MoonBit generated TypeScript declarations expands common MoonBit container aliases" {
  let actual = normalize_moonbit_generated_typescript_decl_from_entry_path(
    "fixtures/typescript_decl/moonbit_generated/advanced.d.ts",
  ) catch {
    ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
      fail("Normalize error: \{msg}")
  }
  let expected =
    #|export type UserId = bigint;
    #|export type Scores = Array<number>;
    #|export type MaybeName = string | undefined;
    #|
    #|export function collect_scores(
    #|  values: Array<number>,
    #|): bigint | undefined;
    #|
    #|export function parse_result(
    #|  input: string,
    #|): { $tag: 1; _0: string | undefined } | { $tag: 0; _0: bigint };
  assert_eq(actual, expected)
}

///|
async test "bridge: normalize MoonBit generated TypeScript declarations expands nested generic aliases from moonbit.d.ts" {
  let actual = normalize_moonbit_generated_typescript_decl_from_entry_path(
    "fixtures/typescript_decl/moonbit_generated/nested_alias.d.ts",
  ) catch {
    ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
      fail("Normalize error: \{msg}")
  }
  let expected =
    #|export function wrap_result(
    #|  input: string,
    #|): { value: { $tag: 1; _0: string } | { $tag: 0; _0: number } };
  assert_eq(actual, expected)
}

///|
async test "bridge: normalize MoonBit generated TypeScript declarations expands interface-based generic aliases from moonbit.d.ts" {
  let actual = normalize_moonbit_generated_typescript_decl_from_entry_path(
    "fixtures/typescript_decl/moonbit_generated/interface_alias.d.ts",
  ) catch {
    ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
      fail("Normalize error: \{msg}")
  }
  let expected =
    #|export function payload_result(
    #|  input: string,
    #|): { value: { $tag: 1; _0: string } | { $tag: 0; _0: number }; ok: boolean };
  assert_eq(actual, expected)
}

///|
async test "bridge: normalize MoonBit generated TypeScript declarations flattens interface extends chains from moonbit.d.ts" {
  let actual = normalize_moonbit_generated_typescript_decl_from_entry_path(
    "fixtures/typescript_decl/moonbit_generated/interface_extends_alias.d.ts",
  ) catch {
    ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
      fail("Normalize error: \{msg}")
  }
  let expected =
    #|export function rich_payload_result(
    #|  input: string,
    #|): { value: { $tag: 1; _0: string } | { $tag: 0; _0: number }; kind: string; ok: boolean };
  assert_eq(actual, expected)
}

///|
async test "bridge: normalize MoonBit generated TypeScript declarations preserves conflicting extends as intersections" {
  let actual = normalize_moonbit_generated_typescript_decl_from_entry_path(
    "fixtures/typescript_decl/moonbit_generated/interface_extends_conflict_alias.d.ts",
  ) catch {
    ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
      fail("Normalize error: \{msg}")
  }
  let expected =
    #|export function conflicting_payload_result(): { value: string } & { value: number } & { ok: boolean };
  assert_eq(actual, expected)
}

///|
async test "bridge: normalize MoonBit generated TypeScript declarations keeps identical inherited members flattened" {
  let actual = normalize_moonbit_generated_typescript_decl_from_entry_path(
    "fixtures/typescript_decl/moonbit_generated/interface_extends_shared_member_alias.d.ts",
  ) catch {
    ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
      fail("Normalize error: \{msg}")
  }
  let expected =
    #|export function shared_tagged_payload_result(): { kind: string; ok: boolean };
  assert_eq(actual, expected)
}

///|
async test "bridge: normalize MoonBit generated TypeScript declarations keeps identical readonly inherited members flattened" {
  let actual = normalize_moonbit_generated_typescript_decl_from_entry_path(
    "fixtures/typescript_decl/moonbit_generated/interface_extends_shared_readonly_alias.d.ts",
  ) catch {
    ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
      fail("Normalize error: \{msg}")
  }
  let expected =
    #|export function shared_readonly_payload_result(): { readonly count: number; ok: boolean };
  assert_eq(actual, expected)
}

///|
async test "bridge: normalize MoonBit generated TypeScript declarations keeps conflicting readonly members as intersections" {
  let actual = normalize_moonbit_generated_typescript_decl_from_entry_path(
    "fixtures/typescript_decl/moonbit_generated/interface_extends_conflicting_readonly_alias.d.ts",
  ) catch {
    ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
      fail("Normalize error: \{msg}")
  }
  let expected =
    #|export function conflicting_readonly_payload_result(): { readonly count: number } & { count: number } & { ok: boolean };
  assert_eq(actual, expected)
}

///|
async test "bridge: normalize MoonBit generated TypeScript declarations keeps identical optional members flattened" {
  let actual = normalize_moonbit_generated_typescript_decl_from_entry_path(
    "fixtures/typescript_decl/moonbit_generated/interface_extends_shared_optional_alias.d.ts",
  ) catch {
    ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
      fail("Normalize error: \{msg}")
  }
  let expected =
    #|export function shared_optional_payload_result(): { name?: string; ok: boolean };
  assert_eq(actual, expected)
}

///|
async test "bridge: normalize MoonBit generated TypeScript declarations keeps conflicting optional members as intersections" {
  let actual = normalize_moonbit_generated_typescript_decl_from_entry_path(
    "fixtures/typescript_decl/moonbit_generated/interface_extends_conflicting_optional_alias.d.ts",
  ) catch {
    ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
      fail("Normalize error: \{msg}")
  }
  let expected =
    #|export function conflicting_optional_payload_result(): { name?: string } & { name: string } & { ok: boolean };
  assert_eq(actual, expected)
}

///|
async test "bridge: normalize MoonBit generated TypeScript declarations preserves call signature inheritance as intersections" {
  let actual = normalize_moonbit_generated_typescript_decl_from_entry_path(
    "fixtures/typescript_decl/moonbit_generated/interface_extends_call_signature_alias.d.ts",
  ) catch {
    ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
      fail("Normalize error: \{msg}")
  }
  let expected =
    #|export function shared_formatter_result(): { (value: string): string } & { (value: number): string } & { ok: boolean };
  assert_eq(actual, expected)
}

///|
async test "bridge: normalize MoonBit generated TypeScript declarations expands multiple namespace imports" {
  let actual = normalize_moonbit_generated_typescript_decl_from_entry_path(
    "fixtures/typescript_decl/moonbit_generated/multi_import_alias.d.ts",
  ) catch {
    ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
      fail("Normalize error: \{msg}")
  }
  let expected =
    #|export type UserId = bigint;
    #|
    #|export function make_payload(
    #|  input: { name: string },
    #|): { payload: string };
  assert_eq(actual, expected)
}

///|
async test "bridge: normalize MoonBit generated TypeScript declarations falls back to named imports when relative rules are missing" {
  let actual = normalize_moonbit_generated_typescript_decl_from_entry_path(
    "fixtures/typescript_decl/moonbit_generated/missing_import_alias.d.ts",
  ) catch {
    ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
      fail("Normalize error: \{msg}")
  }
  let expected =
    #|import type { Box, Result } from "./missing.d.ts";
    #|
    #|export type UserId = bigint;
    #|
    #|export function wrap(
    #|  input: Box<string>,
    #|): Result<bigint, string>;
  assert_eq(actual, expected)
}

///|
async test "bridge: normalize MoonBit generated TypeScript declarations rewrites external namespace imports to named imports" {
  let actual = normalize_moonbit_generated_typescript_decl_from_entry_path(
    "fixtures/typescript_decl/moonbit_generated/external_import_alias.d.ts",
  ) catch {
    ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
      fail("Normalize error: \{msg}")
  }
  let expected =
    #|import type { ToJson } from "moonbitlang/core/json";
    #|
    #|export function encode(value: ToJson): ToJson;
  assert_eq(actual, expected)
}

///|
async test "bridge: normalize MoonBit generated TypeScript declarations merges named imports for the same module" {
  let actual = normalize_moonbit_generated_typescript_decl_from_entry_path(
    "fixtures/typescript_decl/moonbit_generated/duplicate_module_import_alias.d.ts",
  ) catch {
    ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
      fail("Normalize error: \{msg}")
  }
  let expected =
    #|import type { Box, Result } from "./missing.d.ts";
    #|
    #|export function pair(
    #|  left: Box<string>,
    #|  right: Result<bigint, string>,
    #|): Result<Box<string>, string>;
  assert_eq(actual, expected)
}
