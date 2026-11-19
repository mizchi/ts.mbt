// @strict: true
// @target: esnext

// TS2872 / TS2873 read the left operand of `&&` and `||` syntactically, with
// the same exemptions a condition has: `0`, `1`, `true` and `false` are
// accepted, by numeric value, so `1.0` and `0x0` are too. A negative number
// and a template with a substitution can be either. An empty template is
// falsy like `""`, and a ternary is decided when both branches agree.

declare const s: string;
declare const a: any;

export function okFalseAnd() { return false && s; }
export function okTrueOr() { return true || s; }
export function okZeroAnd() { return 0 && s; }
export function okOneAnd() { return 1 && s; }
export function okOnePointZero() { return 1.0 && s; }
export function okHexZero() { return 0x0 && s; }
export function okNegative() { return -5 && s; }
export function okTemplateWithSubstitution() { return `${a}` || s; }
export function okTernaryWithExemptBranch() { return (a ? 0 : 2) && s; }
export function badTwo() { return 2 && s; }
export function badHalf() { return 0.5 && s; }
export function badNonEmptyString() { return "a" && s; }
export function badEmptyString() { return "" || s; }
export function badEmptyTemplate() { return `` || s; }
export function badNull() { return null || s; }
export function badVoid() { return void 0 || s; }
export function badArrayLiteral() { return [] && s; }
export function badArrow() { return (() => 1) && s; }
export function badTernaryBothFalsy() { return (a ? null : "") || s; }
export function badTernaryBothTruthy() { return (a ? {} : []) && s; }
