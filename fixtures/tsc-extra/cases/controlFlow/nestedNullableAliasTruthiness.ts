// @strict: true
// @target: esnext

// A truthiness or `!= null` guard removes `null`, `undefined` and `void` at
// every level of an alias of an alias: `Nullable<Nullable<T>> | undefined`,
// what an optional call on a matrix of nullable cells returns, is `T` after
// `if (!x) return`. A guard that removes only `null` keeps `undefined`.

type Nullable<T> = T | null | undefined | void;
interface Cell { f?: string | null }
declare function isF(v: unknown): boolean;
export function okTruthy(x: Nullable<Nullable<Cell>> | undefined) { if (!x || isF(x.f)) { return; } }
export function okEarlyReturn(x: Nullable<Nullable<Cell>> | undefined) { if (!x) { return; } isF(x.f); }
export function okNotNullish(x: Nullable<Nullable<Cell>> | undefined) { if (x != null) { isF(x.f); } }
export function badUnguarded(x: Nullable<Nullable<Cell>> | undefined) { isF(x.f); }
export function badNullOnly(x: Nullable<Nullable<Cell>> | undefined) { if (x !== null) { isF(x.f); } }
