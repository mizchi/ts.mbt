// @strict: true
// @target: esnext

// A function with no return annotation takes its return type from its
// body. A `switch` with a `default` clause, whose every clause returns,
// cannot fall off the end, so it adds no `undefined`; one whose last clause
// can, or one with no `default`, does. A module-level `const` holding a
// literal is that literal's base type once returned, as a literal is, and a
// declarator group (`const a = 1, b = 2`) declares each name the same way.

const AL = 1;
const NS = 2, AI = 3;
const S1 = "s";
declare function side(): void;
function take(n: number) { return n; }
function mapClass(c: number) {
  switch (c) {
    case AI: return AL;
    case 9: return NS;
    default: return c;
  }
}
function lastClauseFallsOff(c: number) { switch (c) { case 1: return AL; default: side(); } }
function noDefault(c: number) { switch (c) { case 1: return 2; case 2: return 3; } }
function returnsGroupConst() { return NS; }
function returnsStringConst() { return S1; }

export function okSwitchReturnNarrowsAssignment() {
  let n: number | undefined = undefined;
  n = mapClass(1);
  return take(n);
}
export function okGroupConstReturn() {
  let n: number | undefined = undefined;
  n = returnsGroupConst();
  return take(n);
}
export function okConstReturnIsBaseType() { let s = returnsStringConst(); s = "t"; return s; }
export function badSwitchReturnIsNumber() { const s: string = mapClass(1); return s; }
export function badConstReturnWidens() { const lit: "s" = returnsStringConst(); return lit; }
export function badLastClauseFallsOff() { const n: number = lastClauseFallsOff(1); return n; }
export function badNoDefault() { const n: number = noDefault(1); return n; }
export function badGroupConstRead() { const s: string = NS; return s; }
