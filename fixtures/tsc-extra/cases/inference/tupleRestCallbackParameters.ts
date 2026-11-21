// @strict: true
// @target: esnext

// A callback parameter typed by a TUPLE rest takes one parameter per
// element: `(...xs: [string, number]) => void` gives a callback a `string`
// and a `number`, and refuses one that requires a third. The same holds
// when an element is a type parameter the call leaves unsolved.

declare function f(cb: (...xs: [string, number]) => void): void;
export function okTupleTwo() { f((a, b) => {}); }
export function badTupleThree() { f((a, b, c) => {}); }
export function badTupleElement() { f((a, b) => { const s: string = b; }); }

declare function g<T>(cb: (...xs: [T, number]) => void): void;
export function okGenericTwo() { g((a, b) => {}); }
export function badGenericThree() { g((a, b, c) => {}); }
export function badGenericElement() { g((a, b) => { const s: string = b; }); }
