// @strict: true
// @target: esnext

// An index inside an optional chain is evaluated only when the chain did not
// short-circuit, so the receivers its `?.` guarded are non-nullish there,
// as they are inside a call's arguments. The same read outside the chain
// still reports.

declare const stack: string[] | null;
declare const p: { a: number[] } | undefined;
export function okOptionalLength() { return stack?.[stack?.length - 1]; }
export function okPlainLength() { return stack?.[stack.length - 1]; }
export function okNestedChain() { return p?.a[p.a.length - 1]; }
export function badOutsideChain() { return stack?.length - 1; }
