// @strict: true
// @target: esnext

// A function may end without a value (a bare `return;`, or by falling off the
// end) when its return type admits `undefined` or `void`. That holds through
// an alias: univer's `Nullable<T> = T | null | undefined | void` and a plain
// `T | undefined` alias both allow it, exactly as the inline union does. An
// alias that admits only `null` does not, and neither does a plain type.

type Nullable<T> = T | null | undefined | void;
type MaybeU<T> = T | undefined;
type OnlyNull<T> = T | null;

export function okBareReturnNullable(d: number | null): Nullable<string> { if (d == null) return; return "x"; }
export function okBareReturnUndefinedAlias(d: number | null): MaybeU<string> { if (d == null) return; return "x"; }
export function okBareReturnInlineVoid(d: number | null): string | void { if (d == null) return; return "x"; }
export function okFallOffNullable(d: number | null): Nullable<string> { if (d != null) return "x"; }
export function okFallOffUndefinedAlias(d: number | null): MaybeU<string> { if (d != null) return "x"; }
export async function okAsyncBareReturn(d: number | null): Promise<Nullable<string>> { if (d == null) return; return "x"; }
export class OkMethod { m(d: number | null): Nullable<boolean> { if (d == null) return; return true; } }
export function okArrow() { const f = (d: number | null): Nullable<string> => { if (d == null) return; return "x"; }; return f; }

export function badBareReturnNullOnly(d: number | null): OnlyNull<string> { if (d == null) return; return "x"; }
export function badBareReturnPlain(d: number | null): string { if (d == null) return; return "x"; }
export function badFallOffNullOnly(d: number | null): OnlyNull<string> { if (d != null) return "x"; }
