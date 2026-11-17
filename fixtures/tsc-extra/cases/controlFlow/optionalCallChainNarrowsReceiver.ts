// @strict: true
// @target: esnext

// An optional chain that ends in a CALL narrows its receivers exactly as a
// property chain does. `x?.ok()` is `undefined` whenever `x` is nullish, so a
// truthy `x?.ok()`, or one compared with a value other than `undefined`,
// proves `x` non-nullish. That holds in an `if`, a `while`, either operand of
// `&&`, both operands of `||` when each one proves it, and through a nested
// `x?.a.b()`. The falsy branch proves nothing, and neither does an `||`
// whose other operand says nothing about `x`.

interface N { getParent(): N | undefined; ok(): boolean; num(): boolean; v: number; inner: { has(): boolean } }
type Nullable<T> = T | null | undefined | void;

export function okIf(x: N | undefined) { if (x?.ok()) { return x.v; } return 0; }
export function okWhile(node: N) { let p: Nullable<N> = node; while (p?.getParent()) { p = p.getParent(); } return p; }
export function okAnd(x: N | undefined) { return x?.ok() && x.v; }
export function okOrOfChains(x: N | undefined) { if (x?.ok() || x?.num()) { return x.v; } return 0; }
export function okCompared(x: N | undefined) { if (x?.ok() !== undefined) { return x.v; } return 0; }
export function okNested(x: N | undefined) { if (x?.inner.has()) { return x.v; } return 0; }

export function badFalsyBranch(x: N | undefined) { if (!x?.ok()) { return x.v; } return 0; }
export function badOrWithPlain(x: N | undefined, b: boolean) { if (x?.ok() || b) { return x.v; } return 0; }
export function badAfterWhile(node: N) { let p: Nullable<N> = node; while (p?.getParent()) { p = p.getParent(); } return p.v; }
export function badComparedUndefined(x: N | undefined) { if (x?.ok() === undefined) { return x.v; } return 0; }
