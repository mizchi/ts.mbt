// @strict: true
// @target: esnext

// An unannotated rest parameter takes its contextual type from a declared
// function type wherever that type comes from: a type alias, `typeof` of a
// function declaration, and `typeof` of an arrow `const`, local or at
// module level. Its element type is then checked in the body.

type Orig = (...xs: number[]) => number;
function originalFn(...xs: number[]): number { return xs.length; }
const originalTop = (...xs: number[]): number => xs.length;

export function okAlias() { const copy: Orig = (...xs) => { const values: number[] = xs; return values.length; }; return copy; }
export function badAlias() { const copy: Orig = (...xs) => { const values: string[] = xs; return values.length; }; return copy; }
export function okTypeofFunction() { const copy: typeof originalFn = (...xs) => { const values: number[] = xs; return values.length; }; return copy; }
export function badTypeofFunction() { const copy: typeof originalFn = (...xs) => { const values: string[] = xs; return values.length; }; return copy; }
export function okTypeofLocalArrow() {
    const original = (...xs: number[]): number => xs.length;
    const copy: typeof original = (...xs) => { const values: number[] = xs; return values.length; };
    return copy;
}
export function badTypeofLocalArrow() {
    const original = (...xs: number[]): number => xs.length;
    const copy: typeof original = (...xs) => { const values: string[] = xs; return values.length; };
    return copy;
}
export const okTypeofTopArrow: typeof originalTop = (...xs) => { const values: number[] = xs; return values.length; };
export const badTypeofTopArrow: typeof originalTop = (...xs) => { const values: string[] = xs; return values.length; };
