// @strict: true
// @target: esnext

// `a ?? b` and `a || b` remove `void` from the left operand's type along
// with `null` and `undefined`, also when the left operand's type is an alias
// that carries them (univer's `Nullable<T> = T | null | undefined | void`).
// A `const` bound to the result is the non-nullish part joined with the right
// operand's type, so it is a plain `number` here, and a right operand of
// another type still joins it.

type Nullable<T> = T | null | undefined | void;
declare class Cache { getValue(r: number, c: number): Nullable<number>; }
declare function names(): Nullable<string>;
declare const inline: number | void;
type V = void;
declare const throughVoidAlias: string | V;

export function okCoalesceAlias(c: Cache) { const a = c.getValue(1, 2) ?? 0; return Math.max(1, a); }
export function okCoalesceInline() { const a = inline ?? 0; const n: number = a; return n; }
export function okCoalesceVoidAlias() { const s = throughVoidAlias ?? "x"; const t: string = s; return t; }
export function okOrAlias(c: Cache) { const a = c.getValue(1, 2) || 0; const n: number = a; return n; }
export function okOrString() { const s = names() || "d"; const t: string = s; return t; }

export function badCoalesceJoinsRight(c: Cache) { const a = c.getValue(1, 2) ?? "s"; return Math.max(1, a); }
export function badOrJoinsRight(c: Cache) { const a = c.getValue(1, 2) || "s"; return Math.max(1, a); }
export function badCoalesceNullRight(c: Cache) { const a = c.getValue(1, 2) ?? null; const n: number = a; return n; }
