// @strict: true

// A target ending in a rest parameter accepts a source of any length, for
// a function type and a constructor type alike: each source parameter past
// the target's fixed ones takes the rest's element type.

class U { u = 1 }
type UnitCtor = new (...args: any[]) => U;
declare function take(ctor: UnitCtor): void;

declare const c0: new () => U;
export const okCtorNone: UnitCtor = c0;
export function okCtorArg() { take(c0); }
declare const c2: new (a: number, b: string) => U;
export const okCtorTwo: UnitCtor = c2;
declare const f2: (a: number, b: string) => U;
export const okFnRest: (...args: any[]) => U = f2;
declare const f1: (a: number) => U;
export const okRestElem: (...args: number[]) => U = f1;

declare const cx: new () => number;
export const badCtorReturn: UnitCtor = cx;
export const badRestFixed: (x: string, ...rest: any[]) => U = f1;
export const badRestElem: (...args: number[]) => U = f2;

// Two rest parameters relate element to element, so a constructor with a
// rest parameter is its own type with a narrower return.
declare const cr: new (...args: number[]) => { a: number; b: number };
export const okCtorBothRest: new (...args: number[]) => { a: number } = cr;
declare const cs: new (...args: string[]) => { a: number };
export const badCtorBothRest: new (...args: number[]) => { a: number } = cs;
