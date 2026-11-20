// @strict: true
// @target: esnext

// `Object.entries` and `Object.values` are generic only through their first
// overload, `entries<T>(o: { [s: string]: T } | ArrayLike<T>)`. A `Record`,
// a declared index signature (string or number) and an array give `T` its
// value type. An interface with no index signature has no implicit one, so
// it falls to `entries(o: {}): [string, any][]`, and so does a `Map`. A type
// literal does have an implicit index signature, so its values are the union
// of its property types. The key is always `string`.

interface I { a: number; b: string }
type L = { a: number; b: string };
interface D { x: number }

export function badRecordValue(r: Record<string, number>) { for (const [, v] of Object.entries(r)) { const s: string = v; } }
export function badRecordLiteralKeys(r: Record<"a" | "b", number>) { for (const [, v] of Object.entries(r)) { const s: string = v; } }
export function badIndexSignature(r: { [k: string]: number }) { for (const [, v] of Object.entries(r)) { const s: string = v; } }
export function badNumberIndexSignature(r: { [k: number]: number }) { for (const [, v] of Object.entries(r)) { const s: string = v; } }
export function badArrayValue(r: number[]) { for (const [, v] of Object.entries(r)) { const s: string = v; } }
export function okInterfaceIsAny(i: I) { for (const [, v] of Object.entries(i)) { const s: boolean = v; } }
export function okMapIsAny(m: Map<string, number>) { for (const [, v] of Object.entries(m)) { const s: string = v; } }
export function badTypeLiteralUnion(l: L) { for (const [, v] of Object.entries(l)) { const s: boolean = v; } }
export function badKeyIsString(r: Record<string, number>) { for (const [k] of Object.entries(r)) { const n: number = k; } }
export function badValuesRecord(r: Record<string, number>) { const xs: string[] = Object.values(r); }
export function okValuesInterface(i: I) { const xs: boolean[] = Object.values(i); }
export function badValuesTypeLiteral(l: L) { const xs: string[] = Object.values(l); }

// Excalidraw's shape: the value narrows a declared `D | null` by assignment,
// which an `any` value does not.
export function okValueNarrowsDeclaredNullable(r: Record<string, D>) {
  for (const [, d] of Object.entries(r)) {
    let latest: D | null = null;
    latest = d;
    console.log(latest.x);
  }
}
