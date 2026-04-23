import type * as MoonBit from "./moonbit.d.ts";
import type * as Extra from "./extra.d.ts";

export type UserId = MoonBit.UInt64;

export function make_payload(
  input: Extra.NameBox,
): Extra.Payload<MoonBit.String>;
