// @strict: true
// @target: esnext

// An unannotated callback parameter takes its type from the contextual
// list, with the rest position read: a rest parameter collects the formals
// from its position on (the rest array, or a tuple of fixed formals), and a
// plain parameter on the contextual rest takes its element. A variadic
// tuple pattern binds every position from its rest on to the rest's element.

declare function takeRest(cb: (...xs: number[]) => void): void;
declare function takePair(cb: (x: string, y: number) => void): void;

export function okRestFromRest() { takeRest((...a) => { const v: number[] = a; return v; }); }
export function badRestFromRest() { takeRest((...a) => { const v: string[] = a; return v; }); }
export function okPlainFromRest() { takeRest((a, b) => { const n: number = a + b; return n; }); }
export function badPlainFromRest() { takeRest((a) => { const s: string = a; return s; }); }
export function okRestFromPair() { takePair((...a) => { const v: [string, number] = a; return v; }); }
export function badRestFromPair() { takePair((...a) => { const v: [number, number] = a; return v; }); }
export function okTupleRest([a, b]: [number, ...string[]]) { const s: string = b; return [a, s]; }
export function badTupleRest([a, b]: [number, ...string[]]) { const n: number = b; return [a, n]; }
export function okTupleRestTail([a, b, c]: [number, ...string[]]) { const s: string = c; return [a, b, s]; }
declare function f5<T extends any[], U>(f: (...args: T) => U): (...args: T) => U;
export const okAnnotatedOnGenericRest = f5((x: number, y) => 42);
export function okAnnotatedOnRest() { takeRest((a: number, b: number) => {}); }
export function badAnnotatedOnRest() { takeRest((a: string) => {}); }
