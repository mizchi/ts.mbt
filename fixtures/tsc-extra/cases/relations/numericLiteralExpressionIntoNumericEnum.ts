// @strict: true
// @target: esnext

// A numeric literal written where a numeric enum is expected fits only
// when a member holds its value (TypeScript 5.0), in every position: a
// binding, a property write, an object-literal member, an argument, and a
// union holding the enum, including one spelled through an alias such as
// `Nullable<E> | undefined`. Members are auto-numbered, a member after an
// explicit value continues from it, and a mixed enum holds its numeric
// members' values. `number` itself and a computed member accept any. In
// `x || 9`, the fallback relates only when `x` can be falsy.

type Nullable<T> = T | null | undefined | void;
enum H { U, L, C }
enum F { A = 10, B }
enum G { A = "x".length, B = 2 }
enum M { A = 1, S = "s" }
interface Style { a?: H | null; b?: Nullable<H>; e: H }
declare function take(h: H): void;

export function okBare() { const e: H = 2; return e; }
export function okAliasUnion(s: Style) { s.b = 2; }
export function okContinued() { const f: F = 11; return f; }
export function okComputed() { const g: G = 99; return g; }
export function okMixed() { const m: M = 1; return m; }
export function okNumberMember() { const x: H | number = 9; return x; }
export function okArg() { take(2); }
export function badBare() { const e: H = 9; return e; }
export function badNegative() { const e: H = -1; return e; }
export function badUnion(s: Style) { s.a = 9; }
export function badAliasUnion(s: Style) { s.b = 9; }
export function badField(s: Style) { s.e = 9; }
export function badObjectMember() { const o: { e: H } = { e: 9 }; return o; }
export function badContinued() { const f: F = 12; return f; }
export function badMixed() { const m: M = 2; return m; }
export function badArg() { take(7); }
export function okTruthyLeftDecides(x: 1) { const e: H = x || 9; return e; }
export function badFalsyLeftReachesFallback(x: 0 | 1) { const e: H = x || 9; return e; }
