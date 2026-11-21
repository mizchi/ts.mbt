// @strict: true
// @target: esnext

// A declaration initialized with an object literal narrows a declared union
// of object shapes to the members the literal fits, as an assignment does:
// an enum-member or literal discriminant picks its member, so a property
// only that member declares is readable and has that member's type. A
// property the picked member lacks is an error.

enum K { Blank = "blank", S = "string", E = "error", N = "number" }
type RV = { type: K.Blank } | { type: K.S | K.E; value: string } | { type: K.N; value: number };
type LV = { type: "blank" } | { type: "s"; value: string } | { type: "n"; value: number };
export function okEnum() { const v: RV = { type: K.S, value: "x" }; const s: string = v.value; return s; }
export function okLiteral() { const v: LV = { type: "s", value: "x" }; const s: string = v.value; return s; }
export function okLet() { let v: LV = { type: "n", value: 1 }; const n: number = v.value; return n; }
export function badMember() { const v: LV = { type: "s", value: "x" }; const n: number = v.value; return n; }
export function badBlank() { const v: LV = { type: "blank" }; return v.value; }
