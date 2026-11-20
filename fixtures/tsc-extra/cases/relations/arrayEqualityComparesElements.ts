// @strict: true
// @target: esnext

// Two arrays are comparable with `===` when their element types are, and two
// tuples when they have the same length and are comparable position by
// position. So comparing two references to the same element type (React's
// `prevProps.elements !== nextProps.elements`) is legal, and only element
// types with no overlap make it TS2367. An optional tuple element may be
// absent, so `[number, string?]` and `[number]` overlap.
//
// A tuple meets an array as an array of the UNION of its elements, and a
// union is comparable when any member is: `[string, number]` overlaps
// `number[]` and `[string]` does not, and the empty tuple overlaps any
// array. A tuple that is nothing but `[...T[]]` is the array `T[]`. A
// readonly tuple is not comparable with a mutable array of a type it does
// not share a value with either way.

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
export function okSomeTupleElementOverlaps(a: [string, number], b: number[]) { return a === b; }
export function okEmptyTupleAndArray(a: [], b: number[]) { return a === b; }
export function okRestInTheMiddle(a: [number, ...string[], boolean], b: boolean[]) { return a === b; }
export function okPrefixThenRest(a: [string, ...number[]], b: [string, number]) { return a === b; }
export function badNoTupleElementOverlaps(a: [string], b: number[]) { return a === b; }
export function badRestOnlyTuple(a: [...number[]], b: boolean[]) { return a === b; }
export function badRestOnlyAgainstTuple(a: [...number[]], b: [string]) { return a === b; }
export function badRestOnlyOnTheRight(a: [string], b: [...number[]]) { return a === b; }
export function badReadonlyTupleAndArray(a: readonly [string, number], b: number[]) { return a === b; }
