// @strict: true
// @target: esnext

// A type argument the use omits is the parameter's default. A default may
// name an earlier parameter, and then reads the argument that parameter got
// (`B = A[]`). A generic alias written with no arguments at all takes every
// default. A default built from an intersection is the intersection.

type I<Q = string, C = number> = { c: C; q: Q };
type P<A, B = A[]> = { a: A; b: B };
type U<T = number> = { v: T };
type D<T = { x: number }> = T & { y: string };
declare const i: I<boolean>;
declare const p: P<number>;
declare const u: U;
declare const d: D;
declare const d2: D<{ z: boolean }>;

export function okRefersEarlier() { const xs: number[] = p.b; return xs; }
export function okBareAlias() { const n: number = u.v; return n; }
export function okIntersectionDefault() { return d.x + d.y.length; }
export function okExplicitOverridesDefault() { return d2.z; }
export function badDefault() { const s: string = i.c; return s; }
export function badRefersEarlier() { const xs: string[] = p.b; return xs; }
export function badBareAlias() { const s: string = u.v; return s; }
export function badIntersectionDefaultMember() { return d.nope; }
