///|
async test "analysis: normalize MoonBit generated TypeScript declarations inlines primitive aliases" {
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
async test "analysis: normalize MoonBit generated TypeScript declarations keeps named imports for non-primitive aliases" {
  let actual = normalize_moonbit_generated_typescript_decl_from_entry_path(
    "fixtures/typescript_decl/moonbit_generated/result.d.ts",
  ) catch {
    ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
      fail("Normalize error: \{msg}")
  }
  let expected =
    #|import type { Result } from "./moonbit.d.ts";
    #|
    #|export function parse_user(
    #|  input: string,
    #|): Result<string, number>;
    #|
    #|export const EMPTY_BYTES: Uint8Array;
  assert_eq(actual, expected)
}
