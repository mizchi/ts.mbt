import type * as Missing from "./missing.d.ts";

export type UserId = Missing.UInt64;

export function wrap(
  input: Missing.Box<Missing.String>,
): Missing.Result<Missing.UInt64, Missing.String>;
