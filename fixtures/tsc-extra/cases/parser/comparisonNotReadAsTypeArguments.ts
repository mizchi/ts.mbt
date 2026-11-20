// @strict: true
// @target: esnext

// `a < (b - 1) || a > (c + 1)` is two comparisons, not a call with type
// arguments: a type argument list cannot contain `-`, `||` or any other
// operator no type has, so tsc's speculative parse of `<(b - 1) || a>` fails
// and the `<` is a comparison. A negative literal and a mapped-type modifier
// are the two places `-` does appear inside type arguments, and real type
// arguments still apply. The comparisons are still type-checked.

const CACHE = 1;
declare function lit<T extends number>(): T;
declare function g<T>(x: T): T;

export function okParenthesizedSubtraction(row: number, a: number, b: number) { return row < (a - CACHE) || row > (b + CACHE); }
export function okParenthesizedOperands(row: number, a: number, b: number) { return row < (a) && row > (b); }
export function okNegativeLiteralArgument() { const n: -1 = lit<-1>(); return n; }
export function okSpacedNegativeLiteralInTypeofQuery() { type R = typeof lit<- 1>; const f: R = lit; return f; }
export function okMappedTypeArgument(o: { readonly a?: number }) { return g<{ -readonly [K in keyof typeof o]-?: number }>({ a: 1 }).a; }
export function badComparisonStillChecked(row: number, s: string) { return row < (s) || row > (1); }
export function badTypeArgumentStillApplies() { return g<string>(1); }
