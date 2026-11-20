// @strict: true
// @target: esnext

// A write `obj[k] = v` through a key whose TYPE is a string literal is the
// write of that property, the same as `obj["a"] = v`. Through a key typed
// as a union of literals the value must fit every property the key can
// name, because the write could land on any of them. A fresh object
// literal is related to all of them at once, their intersection, so its
// excess-property check is against the combined shape: a literal holding
// each property's members is legal, while one missing a member, or holding
// one no property declares, is not.

declare const obj: { a: number; b: 0 | 1; c: string };

export function okLiteralKeyParam(k0: "a") { obj[k0] = 2; }
export function okUnionKey(k1: "a" | "b") { obj[k1] = 1; }
export function badLiteralKeyParam(k0: "a") { obj[k0] = "x"; }
export function badBracketLiteral() { obj["a"] = "x"; }
export function badLiteralKeyConst() { const k = "a"; obj[k] = "x"; }
export function badUnionKey(k1: "a" | "b") { obj[k1] = 2; }
export function badUnionKeyThreeMembers(k2: "a" | "b" | "c") { obj[k2] = 1; }

declare const o: { a: { x: number }; b: { y: number } };
declare const arrs: { a: { x: number }[]; b: { y: number }[] };

export function okFreshLiteralFitsBoth(k: "a" | "b") { o[k] = { x: 1, y: 2 }; }
export function okFreshLiteralInBranches(k: "a" | "b", c: boolean) { o[k] = c ? { x: 1, y: 2 } : { x: 2, y: 3 }; }
export function okFreshLiteralInArray(k: "a" | "b") { arrs[k] = [{ x: 1, y: 2 }]; }
export function okPrimitiveBesideFreshLiteral(o2: { a: { length: number }[]; b: { length: number }[] }, k: "a" | "b") { o2[k] = ["abc", { length: 1 }]; }
export function badFreshLiteralMissesOne(k: "a" | "b") { o[k] = { x: 1 }; }
export function badFreshLiteralExcess(k: "a" | "b") { o[k] = { x: 1, y: 2, z: 3 }; }
export function badFreshLiteralInArrayMissesOne(k: "a" | "b") { arrs[k] = [{ x: 1 }]; }
