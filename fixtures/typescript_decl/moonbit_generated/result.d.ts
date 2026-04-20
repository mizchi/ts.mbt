import type * as MoonBit from "./moonbit.d.ts";

export function parse_user(
  input: MoonBit.String,
): MoonBit.Result<MoonBit.String, MoonBit.Int>;

export const EMPTY_BYTES: MoonBit.Bytes;
