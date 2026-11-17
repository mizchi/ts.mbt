// @strict: true
// @target: esnext

// A trailing parameter whose type accepts `void` may be omitted at a call, and
// that holds through an alias: univer's `Nullable<T> = T | null | undefined |
// void`. Only `void` makes it omissible. A `T | undefined` alias is still a
// required argument, and so is a void-accepting parameter followed by a
// required one.

type Nullable<T> = T | null | undefined | void;
type MaybeU<T> = T | undefined;
declare function fNullable(a: number, b: Nullable<number>): void;
declare function fTwoTrailing(a: number, b: Nullable<number>, c: void): void;
declare function fUndefAlias(a: number, b: MaybeU<number>): void;
declare function fMiddle(a: Nullable<number>, b: number): void;
class Matrix { slice(row: Nullable<number[]>, col: Nullable<number[]>) { return row ?? col; } }

export function okAliasTrailing() { fNullable(1); }
export function okTwoTrailing() { fTwoTrailing(1); }
export function okMethod() { new Matrix().slice([1]); }
export function okArrow() { const f = (a: number, b: Nullable<number>) => a + (b ?? 0); return f(1); }

export function badUndefinedAlias() { fUndefAlias(1); }
export function badVoidBeforeRequired() { fMiddle(1); }
export function badTooMany() { fNullable(1, 2, 3); }
