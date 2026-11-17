// @strict: true
// @target: esnext

// `Array.isArray(x)` narrows a union to its array members on the true side and
// to the rest on the false side, and a class or interface that does not extend
// `Array` is "the rest". univer's formula helpers return
// `number[] | ErrorValueObject` and write `if (!Array.isArray(values)) return
// values;` before using `values` as `number[]`. A class that DOES extend
// `Array` stays on the array side.

class ErrorValue { readonly code = 1; }
interface Failure { reason: string }
class NumberList extends Array<number> {}
declare function values(): number[] | ErrorValue;
declare function valuesOrFailure(): string[] | Failure;
declare function useNumbers(xs: number[]): number;
declare function useStrings(xs: string[]): number;

export function okEarlyReturn() { const v = values(); if (!Array.isArray(v)) { return 0; } return useNumbers(v); }
export function okThenBranch() { const v = values(); if (Array.isArray(v)) { return useNumbers(v); } return 0; }
export function okFalseSideIsTheClass() { const v = values(); if (!Array.isArray(v)) { return v.code; } return 0; }
export function okInterfaceMember() { const v = valuesOrFailure(); if (Array.isArray(v)) { return useStrings(v); } return v.reason.length; }
export function okArraySubclass(v: NumberList | ErrorValue) { if (Array.isArray(v)) { return v.length; } return v.code; }

export function badNoGuard() { const v = values(); return useNumbers(v); }
export function badWrongSide() { const v = values(); if (Array.isArray(v)) { return v.code; } return 0; }
