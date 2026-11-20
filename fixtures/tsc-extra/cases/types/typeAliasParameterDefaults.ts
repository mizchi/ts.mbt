// @strict: true
// @target: esnext

// A type argument the use omits is the parameter's default. A default may
// name an earlier parameter, and then reads the argument that parameter got
// (`B = A[]`). A generic alias written with no arguments at all takes every
// default. A default built from an intersection is the intersection. A
// default is written in the scope its alias is declared in, so a namespace
// alias's default reads the namespace's names, not the file's, including a
// name another body of the same namespace declares.

type I<Q = string, C = number> = { c: C; q: Q };
type P<A, B = A[]> = { a: A; b: B };
type U<T = number> = { v: T };
type D<T = { x: number }> = T & { y: string };
declare const i: I<boolean>;
declare const p: P<number>;
declare const u: U;
declare const d: D;
declare const d2: D<{ z: boolean }>;
type Item = number;
namespace N { export type Item = string; export type A<T = Item> = { v: T }; }
declare const na: N.A;
namespace P { export type Elem = string; }
namespace P { export type B<T = Elem> = { v: T }; }
declare const pb: P.B;

export function okRefersEarlier() { const xs: number[] = p.b; return xs; }
export function okBareAlias() { const n: number = u.v; return n; }
export function okIntersectionDefault() { return d.x + d.y.length; }
export function okExplicitOverridesDefault() { return d2.z; }
export function badDefault() { const s: string = i.c; return s; }
export function badRefersEarlier() { const xs: string[] = p.b; return xs; }
export function badBareAlias() { const s: string = u.v; return s; }
export function badIntersectionDefaultMember() { return d.nope; }
export function okNamespaceDefault() { const s: string = na.v; return s; }
export function badNamespaceDefault() { const n: number = na.v; return n; }
export function okCrossBodyDefault() { const s: string = pb.v; return s; }
export function badCrossBodyDefault() { const n: number = pb.v; return n; }
