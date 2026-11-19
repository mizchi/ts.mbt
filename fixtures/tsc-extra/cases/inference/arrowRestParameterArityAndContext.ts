// @strict: true
// @target: esnext

// An arrow's or a function expression's rest parameter takes any number of
// arguments, through the value as well as by name. Against a contextual
// parameter list, the rest parameter's ELEMENT type is compared with each
// formal from its position on; two rest lists compare their arrays.

const concat = (...bufs: Uint8Array[]): number => bufs.length;
const joined = function (...xs: string[]) { return xs.join(); };
const head = (a: string, ...xs: number[]) => xs.length + a.length;
const take: (f: (...a: number[]) => number) => number = (f) => f(1, 2);
type Pair = (a: number, b: number) => number;
const regex = { and: (...rs: RegExp[]) => rs.length };

export function okTwoBuffers() { return concat(new Uint8Array(1), new Uint8Array(2)); }
export function okNoBuffers() { return concat(); }
export function okTwoStrings() { return joined("a", "b"); }
export function okRestThroughObject() { return regex.and(/a/, /b/); }
export function okHeadAndRest() { return head("a", 1, 2); }
export function okRestForRest() { return take((...xs: number[]) => xs.length); }
export function okRestForFixed() { const f: Pair = (...a: number[]) => a[0]; return f; }
export function badRestElement() { return concat(new Uint8Array(1), "x"); }
export function badMissingHead() { return head(); }
export function badRestForRest() { return take((...xs: string[]) => xs.length); }
export function badRestForFixed() { const f: Pair = (...a: string[]) => 1; return f; }
