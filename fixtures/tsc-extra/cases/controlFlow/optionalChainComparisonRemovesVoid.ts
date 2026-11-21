// @strict: true
// @target: esnext

// A comparison that rules out an optional chain's short-circuit makes its
// receiver non-nullish, and that removes `void` as well as `null` and
// `undefined`: a `void` receiver's only value is `undefined`, which
// short-circuits too. `!== null` does not rule out the short-circuit.

type Nullable<T> = T | null | undefined | void;
interface Cell { v?: number | null }
declare function use(c: Cell): void;
export function okEarlyReturn(c: Nullable<Cell>) { if (c?.v === undefined || c?.v === null) return; use(c); }
export function okNotUndefined(c: Nullable<Cell>) { if (c?.v !== undefined) use(c); }
export function okLooseNull(c: Nullable<Cell>) { if (c?.v != null) use(c); }
export function okValue(c: Nullable<Cell>) { if (c?.v === 1) use(c); }
export function badNotNull(c: Nullable<Cell>) { if (c?.v !== null) use(c); }
