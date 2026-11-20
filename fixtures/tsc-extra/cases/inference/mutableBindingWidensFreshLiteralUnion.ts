// @strict: true
// @target: esnext

// A `let` widens each FRESH literal its initializer can evaluate to, and
// `"a" | string` is `string`. So a conditional of two string literals is a
// `string` binding and takes any string later. A `const` keeps the union.
// An operand's literal counts only when the operator's result can be that
// operand: the right of `||` when the left can be falsy, the right of `??`
// when the left can be nullish. A declared literal on the left of either
// keeps the binding that literal, and the right operand is not in its
// type at all. An always-falsy left operand is never the result.

declare const nx: "x" | undefined;
declare const mx: "x";

export function okCondLet(c: boolean) { let r = c ? "a" : "b"; r = "z"; return r; }
export function okCondNum(c: boolean) { let r = c ? 1 : 2; r = 3; return r; }
export function okOrLet(s: string) { let r = s || "a"; r = "z"; return r; }
export function okOrLeftDeclared() { let a: "foo" = "foo"; let b = a || "foo"; let c2: "foo" = b; return c2; }
export function okCoalesceNullable() { let b = nx ?? "y"; b = "z"; return b; }
export function badConst(c: boolean) { const r = c ? "a" : "b"; const z: "c" = r; return z; }
export function badLetToLiteral(c: boolean) { let r = c ? "a" : "b"; const z: "a" | "b" = r; return z; }
export function badCoalesceNonNullable() { let b = mx ?? "y"; b = "y"; return b; }
export function badOrNonFalsy() { let b = mx || "y"; b = "y"; return b; }
declare const tag: "a" | "b";
export function badAlwaysFalsyLeft() { const empty = ""; let value = empty || tag; value = "x"; return value; }
