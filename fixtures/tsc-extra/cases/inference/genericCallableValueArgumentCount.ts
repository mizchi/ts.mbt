// @strict: true
// @target: esnext

// A value typed by a GENERIC call signature takes the number of arguments
// the signature says, exactly as a generic function declaration does. The
// count needs no type parameter solved: a binder occurs only in parameter
// types, never in how many parameters there are. Optional, rest and `void`
// parameters may be omitted; a parameter typed by a bare binder may not,
// even when the call writes `void` as its type argument.

declare const two: <T>(x: T, n: number) => T;
declare const opt: <T>(x: T, n?: number) => T;
declare const rest: <T>(x: T, ...more: number[]) => T;
declare const tup: <T extends unknown[]>(...args: T) => T;
declare const vparam: <T>(x: T, v: void) => T;
declare const bare: <T>(x: T) => T;
declare const o: { m<T>(x: T, n: number): T };

export function okTwo() { return two(1, 2); }
export function badTwoTooFew() { return two(1); }
export function badTwoTooMany() { return two(1, 2, 3); }
export function okOptOmitted() { return opt(1); }
export function badOptTooMany() { return opt(1, 2, 3); }
export function okRestEmpty() { return rest(1); }
export function okRestMany() { return rest(1, 2, 3, 4); }
export function badRestMissingFirst() { return rest(); }
export function okTupEmpty() { return tup(); }
export function okTupMixed() { return tup(1, "a"); }
export function okVoidOmitted() { return vparam(1); }
export function badBareEmpty() { return bare(); }
export function badBareExplicitVoid() { return bare<void>(); }
export function okMethod() { return o.m(1, 2); }
export function badMethodTooFew() { return o.m(1); }
