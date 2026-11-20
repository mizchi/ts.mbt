// @strict: true
// @target: esnext

// `a ?? b` has `a`'s type alone when `a` cannot be nullish, and `a || b`
// when `a` cannot be falsy, so the right operand is never related to the
// expected type. Every object type except an empty one is never falsy,
// whatever its members' optionality, a class with only methods included.
// A `string` can be `""`, so `s || 1` still yields `string | 1`. The
// deciding left operand is the result, so it is what relates. A bigint
// zero is falsy in both spellings, `0n` and `-0n`.

interface D { a: number; b: number }
declare function f(d: D): void;
declare function g(x: string): void;
class K { m() {} }
declare function fk(x: K): void;
interface W { a?: number }
declare function fw(x: W): void;

export function okNonNullish(d: D) { f(d ?? {}); }
export function okOrObject(d: D) { f(d || {}); }
export function okOrMethodsOnly(k: K) { fk(k || 1); }
export function okOrWeakType(w: W) { fw(w || 1); }
export function okStrCoalesce(s: string) { g(s ?? 1); }
export function badNullable(u: D | undefined) { f(u ?? {}); }
export function badOrStr(s: string) { g(s || 1); }
export function badLeftDecidesCoalesce(s: string): number { return s ?? false; }
export function badLeftDecidesOr(d: D): string { return d || "z"; }
export function okBigOneLeft(x: 1n) { const y: bigint = x || "bad"; return y; }
export function badBigZeroLeft(x: 0n) { const y: bigint = x || "bad"; return y; }
export function badBigNegZeroLeft(x: -0n) { const y: bigint = x || "bad"; return y; }
