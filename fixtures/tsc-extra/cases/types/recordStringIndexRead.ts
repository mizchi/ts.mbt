// @strict: true
// @target: esnext

// `Record<string, V>` is a string index signature of `V`, so reading it
// with a `string`-typed key gives `V`, as the dotted read and the
// `{ [k: string]: V }` spelling do. A `number` key reads a string signature
// too, and a `PropertyKey` key covers both. Typing the read needs TS 4.7's
// element-access narrowing alongside it: with a key that is a parameter or
// a `const` nobody reassigns, `obj[key]` is narrowed like a property, so a
// guarded read of an `unknown` value is legal.

enum Lang { A = "a", UNKNOWN = "unknown" }
const M: Record<string, Lang> = { a: Lang.A };
declare const t: string;
declare const n: number;
declare const R: Record<string, number>;
declare const P: Record<PropertyKey, number>;

export const okRead: number = R[t];
export const badRead: string = R[t];
export const okNumberKey: number = R[n];
export const badPropertyKey: string = P[n];

type RS = Record<string, number>;
export function badAlias(r: RS, k: string): string {
  return r[k];
}

export function okNarrowedByTypeof(obj: Record<string, unknown>, key: string) {
  if (typeof obj[key] === "string") {
    return obj[key].toUpperCase();
  }
  return "";
}

// `a ?? b` cannot be nullish when `b` cannot, so assigning it narrows a
// `V | undefined` binding to `V`.
export function okNarrowedByCoalesce(m: Map<string, Lang>, k: string): Lang {
  let lang = m.get(k);
  if (lang) { return lang; }
  lang = M[k] ?? Lang.UNKNOWN;
  m.set(k, lang);
  return lang;
}
export function okCoalesceLiteral(m: Map<string, string>, k: string): string {
  let v = m.get(k);
  v = v ?? "none";
  return v;
}
const S: Record<string, string> = {};
const O: Record<string, { a: number }> = {};
export function okRecordLiteral(m: Map<string, string>, k: string): string {
  let v = m.get(k);
  v = S[k] ?? "none";
  return v;
}
export function okRecordObject(m: Map<string, { a: number }>, k: string): { a: number } {
  let v = m.get(k);
  v = O[k] ?? { a: 1 };
  return v;
}
// An `any` left operand makes the whole `??` `any`, and assigning `any`
// leaves the declared `V | undefined`.
declare const anyValue: any;
export function badAnyCoalesce(m: Map<string, Lang>, k: string): Lang {
  let v = m.get(k);
  v = anyValue ?? Lang.UNKNOWN;
  return v;
}
export function badCoalesceNullable(m: Map<string, string>, k: string, d: string | undefined): string {
  let v = m.get(k);
  v = v ?? d;
  return v;
}
