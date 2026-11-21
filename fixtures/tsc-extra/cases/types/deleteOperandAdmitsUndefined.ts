// @strict: true
// @target: esnext

// `delete` needs an operand whose type admits `undefined` (TS2790). An alias
// counts by what it expands to, and `unknown` and `any` admit it. A union
// with only `null` or `void` beside the value does not.

type Nullable<T> = T | null | undefined | void;
type Maybe<T> = T | undefined;
type OnlyNull<T> = T | null;
type V<T> = T | void;
interface I {
  a: Nullable<number>;
  b: Maybe<number>;
  c: OnlyNull<number>;
  d: V<number>;
  e: number | void;
  f: unknown;
  g: any;
}
declare const o: I;
export function okNullableAlias() { delete o.a; }
export function okMaybeAlias() { delete o.b; }
export function badOnlyNullAlias() { delete o.c; }
export function badVoidAlias() { delete o.d; }
export function badVoidUnion() { delete o.e; }
export function okUnknown() { delete o.f; }
export function okAny() { delete o.g; }

export class OkNullableField {
  private _f: Nullable<(x?: number) => void>;
  dispose() { delete this._f; }
}
export class BadNullField {
  private _g: ((x?: number) => void) | null = null;
  dispose() { delete this._g; }
}

// An alias of `unknown` or `any` admits `undefined` as the type does.
type Unk = unknown;
type An = any;
interface J { u: Unk; a: An }
declare const j: J;
export function okUnknownAlias() { delete j.u; }
export function okAnyAlias() { delete j.a; }

// A union with an `unknown` member is `unknown`, written out or aliased.
type UnkAlias = unknown;
interface K { u: UnkAlias | number; w: unknown | number }
declare const k: K;
export function okUnknownUnionAlias() { delete k.u; }
export function okUnknownUnion() { delete k.w; }
