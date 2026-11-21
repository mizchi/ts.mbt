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

// A block body's locals are typed before the tuple is, and a `return`
// inside a loop is a return like any other: here it returns `undefined`.
declare const ns: number[];
export const okLocalConst: [number, number][] = ns.map((n) => { const m = n + 1; return [n, m]; });
export const badLocalConst: [number, number][] = ns.map((n) => { const text = "bad"; return [n, text]; });
export const badLoopReturn: [number, number][] = ns.map((n) => { while (n < 0) { return; } return [n, n]; });

// A declarator group (`const a = n, b = n`) is local `const`s like any
// other: each declarator is typed before the tuple is. A `let` is typed the
// same way, with its initializer widened, so `let s = "x"` is a `string`.
export const okGroup: [number, number][] = ns.map((n) => { const a = n, b = n + 1; return [a, b]; });
export const badGroup: [number, number][] = ns.map((n) => { const a = n, b = "x"; return [a, b]; });
export const okLet: [number, number][] = ns.map((n) => { let a = n; return [a, a]; });
export const okLetGroup: [number, number][] = ns.map((n) => { let a = n, b = n; return [a, b]; });
export const badLetWidened: [number, "x"][] = ns.map((n) => { let s = "x"; return [n, s]; });
