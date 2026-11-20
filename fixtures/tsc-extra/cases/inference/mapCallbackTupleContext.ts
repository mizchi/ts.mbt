// @strict: true
// @target: esnext

// `xs.map(cb)` assigned to an array of tuples: the callback's return is
// typed by the tuple element, so a returned array literal is a tuple, in an
// expression body, a block body, or both branches of a conditional. A
// literal of the wrong length, or with an element of the wrong type, still
// does not fit.

interface R { a: number; b: number }
declare const rs: R[];
declare const flag: boolean;

export const okMapTuple: [number, number][] = rs.map((r) => [r.a, r.b]);
export const okMapTupleCond: [number, number][] = rs.map((r) => (flag ? [r.a, r.b] : [r.b, r.a]));
export const okMapTupleBlock: [number, number][] = rs.map((r) => { return [r.a, r.b]; });
export const badMapTupleArity: [number, number][] = rs.map((r) => [r.a]);
export const badMapTupleType: [number, string][] = rs.map((r) => [r.a, r.b]);
