// @strict: true
// @target: esnext

// Two arrays are comparable with `===` when their element types are, a tuple
// and an array when every element of the tuple is comparable with the
// array's element, and two tuples when they have the same length and are
// comparable position by position. So comparing two references to the same
// element type (React's `prevProps.elements !== nextProps.elements`) is legal,
// and only element types with no overlap make it TS2367. An optional tuple
// element may be absent, so `[number, string?]` and `[number]` overlap.

type El = { id: string };
export function okSameElement(a: number[], b: number[]) { return a === b; }
export function okReadonly(a: readonly El[], b: readonly El[]) { return a !== b; }
export function okTupleAndArray(a: [number, number], b: number[]) { return a === b; }
export function okTupleAndTuple(a: [number], b: [number]) { return a === b; }
export function okSubtypeElement(a: El[], b: { id: string; x: 1 }[]) { return a === b; }
export function okUnionElement(a: (string | number)[], b: string[]) { return a === b; }
export function okOptionalElement(a: [number, string?], b: [number]) { return a === b; }
export function badDisjointElements(a: number[], b: string[]) { return a === b; }
export function badDisjointTuples(a: [number], b: [string]) { return a === b; }
export function badTupleLengths(a: [number], b: [number, number]) { return a === b; }
export function badArrayAndString(a: number[]) { return a === "s"; }
