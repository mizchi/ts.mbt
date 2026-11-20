// @strict: true
// @target: esnext

// A write `obj[k] = v` through a key whose TYPE is a string literal is the
// write of that property, the same as `obj["a"] = v`. Through a key typed
// as a union of literals the value must fit every property the key can
// name, because the write could land on any of them.

declare const obj: { a: number; b: 0 | 1; c: string };

export function okLiteralKeyParam(k0: "a") { obj[k0] = 2; }
export function okUnionKey(k1: "a" | "b") { obj[k1] = 1; }
export function badLiteralKeyParam(k0: "a") { obj[k0] = "x"; }
export function badBracketLiteral() { obj["a"] = "x"; }
export function badLiteralKeyConst() { const k = "a"; obj[k] = "x"; }
export function badUnionKey(k1: "a" | "b") { obj[k1] = 2; }
export function badUnionKeyThreeMembers(k2: "a" | "b" | "c") { obj[k2] = 1; }
