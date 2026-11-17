// @strict: true
// @target: esnext

// A function value takes its parameter types from the type it is assigned
// to, wherever that type comes from: a variable annotation, an object
// literal's member, an array element, a `return` against the function's
// annotation, or a function expression. A type guard inside the body then
// narrows that contextual type, so after `isObject(color)` on
// `string | Color` the parameter is `Color`, and `"r" in color` gives `IRgb`.
//
// The trap for an implementation is to also check the body with the
// parameters as `any`. A guard narrows `any` to its target (`object` here),
// and `"r" in object` is `{ r: unknown }`, which has no `g`. A call argument
// is the position least likely to show it, because the contextual check
// usually runs there first.

interface IRgb { r: number; g: number }
interface IHsl { h: number; l: number }
type Color = IRgb | IHsl;
const isObject = (value: unknown): value is object => typeof value === "object" && value !== null;
type ToNumber = (color: string | Color) => number;
declare function take(f: ToNumber): void;

export function okAnnotatedArrow() { const f: ToNumber = (color) => { if (isObject(color)) { if ("r" in color) { return color.g; } } return 0; }; return f; }
export function okObjectMember() { const o: { f: ToNumber } = { f: (color) => { if (isObject(color)) { if ("r" in color) { return color.g; } } return 0; } }; return o; }
export function okArrayElement() { const a: ToNumber[] = [(color) => { if (isObject(color)) { if ("r" in color) { return color.g; } } return 0; }]; return a; }
export function okReturned(): ToNumber { return (color) => { if (isObject(color)) { if ("r" in color) { return color.g; } } return 0; }; }
export function okFunctionExpression() { const f: ToNumber = function (color) { if (isObject(color)) { if ("r" in color) { return color.g; } } return 0; }; return f; }
export function okCallArgument() { take((color) => { if (isObject(color)) { if ("r" in color) { return color.g; } } return 0; }); }

export function badAnnotatedArrow() { const f: ToNumber = (color) => { if (isObject(color)) { if ("r" in color) { return color.h; } } return 0; }; return f; }
export function badObjectMember() { const o: { f: ToNumber } = { f: (color) => { if (isObject(color)) { return color.r; } return 0; } }; return o; }
export function badArrayElement() { const a: ToNumber[] = [(color) => { if (isObject(color)) { if ("h" in color) { return color.g; } } return 0; }]; return a; }
export function badReturned(): ToNumber { return (color) => { if (isObject(color)) { if ("r" in color) { return color.l; } } return 0; }; }
export function badFunctionExpression() { const f: ToNumber = function (color) { if (!isObject(color)) { return color.g; } return 0; }; return f; }
