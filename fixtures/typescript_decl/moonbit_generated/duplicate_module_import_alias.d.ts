import type * as Left from "./missing.d.ts";
import type * as Right from "./missing.d.ts";

export function pair(
  left: Left.Box<Left.String>,
  right: Right.Result<Right.UInt64, Right.String>,
): Right.Result<Left.Box<Left.String>, Right.String>;
