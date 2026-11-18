// @strict: true
// @target: esnext

// `map` and `flatMap` take their result from what the callback RETURNS,
// whether the callback is written inline or passed by name; and `filter`
// narrows through a type-predicate callback only when the predicate's target
// fits the element type, falling back to the element type otherwise.

declare const numbers: number[];
declare const toLabel: (n: number) => string;
declare const toLabels: (n: number) => string[];
export const okMapNamedCallback: string[] = numbers.map(toLabel);
export const okMapNamedCallbackThisArg: string[] = numbers.map(toLabel, {});
export const okFlatMapNamedCallback: string[] = numbers.flatMap(toLabels);
export const badMapNamedCallback: number[] = numbers.map(toLabel);
export const badFlatMapNamedCallback: number[] = numbers.flatMap(toLabels);

declare const mixed: (string | number)[];
export const okFilterFittingPredicate: number[] = mixed.filter((x: unknown): x is number => typeof x === "number");
export const okFilterUnrelatedPredicate: number[] = numbers.filter((x: unknown): x is string => typeof x === "string");
export const badFilterUnrelatedPredicate: string[] = numbers.filter((x: unknown): x is string => typeof x === "string");
