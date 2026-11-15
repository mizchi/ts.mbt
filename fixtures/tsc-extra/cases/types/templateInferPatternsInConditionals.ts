// @strict: true
// @target: esnext

// `infer` in a template literal with a fixed part or a bound, decided as a
// conditional's check type.

type A = "x1" extends `x${infer U}` ? number : boolean;
type B = "12" extends `${infer U extends bigint}` ? number : boolean;
type C = "7" extends `${infer U extends number}` ? U : never;
function okFixedPart() { const a: A = 1; return a; }
function okBigintBound() { const b: B = 1; return b; }
function okSingleHole() { const c: C = 7; return c; }
declare function fo<T extends { a: string }>(xs: T[]): void;
function badPropertyType() { fo([{ a: 1 }]); }
function okPropertyType() { fo([{ a: "x" }]); }
