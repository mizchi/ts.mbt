// @strict: true
// @target: esnext

// TS2454 ("used before being assigned") is not reported for a binding whose
// declared type admits `undefined`, through an alias too. An alias that
// admits only `null` still reports.

type Nullable<T> = T | null | undefined | void;
type Maybe<T> = T | undefined;
type OnlyNull<T> = T | null;
export function okNullableAlias(): number { let e: Nullable<number>; return e as number; }
export function okMaybeAlias(): number { let e: Maybe<number>; return e as number; }
export function okWrittenOut(): number { let e: number | undefined; return e as number; }
export function badOnlyNull(): number { let e: OnlyNull<number>; return e as number; }
