// @strict: true
// @target: esnext

// Under `noImplicitAny`, an unannotated `let` or `var` initialized with the
// `null` or `undefined` keyword is "auto-typed": its declared type is `any`
// and its flow type evolves with each assignment. So assigning any value
// later is legal, also from inside a callback, while a read before the first
// assignment still sees `null`. `void 0` is not auto-typed, and neither is a
// `const` or an annotated `let e: null`. (Without `noImplicitAny` the
// declared type really is `null`; that mode is not this file.)

interface V { a: number }
declare const v: V;

export function okLetNull() { let e = null; e = v; return e; }
export function okVarUndefined() { var e = undefined; e = v; return e; }
export function okAssignedInCallback(xs: V[]) { let e = null; xs.forEach((x) => { e = x; }); return e; }
export function okReadAfterAssign() { let e = null; e = v; return e.a; }

export function badReadBeforeAssign() { let e = null; return e.a; }
export function badVoidZero() { let e = void 0; e = v; return e; }
export function badConst() { const e = null; return e.a; }
export function badAnnotatedNull() { let e: null = null; e = v; return e; }
export function badPossiblyNullAfterBranch(c: boolean) { let e = null; if (c) { e = v; } return e.a; }
