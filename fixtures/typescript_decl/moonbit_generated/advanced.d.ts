import type * as MoonBit from "./moonbit.d.ts";

export type UserId = MoonBit.UInt64;
export type Scores = MoonBit.FixedArray<MoonBit.Double>;
export type MaybeName = MoonBit.UnboxedOption<MoonBit.String>;

export function collect_scores(
  values: MoonBit.FixedArray<MoonBit.Double>,
): MoonBit.UnboxedOption<MoonBit.UInt64>;

export function parse_result(
  input: MoonBit.String,
): MoonBit.Result<MoonBit.UnboxedOption<MoonBit.String>, MoonBit.Int64>;
