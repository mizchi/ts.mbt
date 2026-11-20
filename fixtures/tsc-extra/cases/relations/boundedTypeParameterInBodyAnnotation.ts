// @strict: true
// @target: esnext

// Inside a generic function, a value read off a parameter typed with a
// bounded type parameter `P` has the type `P`, so it fits a body annotation
// that says `P` again: copying `points: readonly P[]` into `const copy: P[]`
// or passing it to a local `(pts: P[]) => …` is legal. A value of the bound
// alone does not fit `P` (it could be a narrower instantiation), and neither
// does a template-literal form over `P`. An array indexed by a type
// parameter bounded by `number` is its element type.

type A = [number, number] & { _a: 1 };
type B = [number, number] & { _b: 1 };

export function okSpreadOfParam<P extends A | B>(points: readonly P[]): P[] {
  const sorted = [...points];
  const half = (pts: P[]) => pts;
  return half(sorted);
}
export function okDirectParam<P extends A | B>(points: P[]): P[] {
  const half = (pts: P[]) => pts;
  return half(points);
}
export function okLocalAnnotated<P extends A | B>(points: readonly P[]): P[] {
  const copy: P[] = [...points];
  return copy;
}
export function okArrayIndexedByNumericParam<K extends number>() {
  let x: Array<string>[K] = "abc";
  return x;
}
export function badBoundIntoTemplate<T extends "a" | "b">(x: T) {
  const t: T = "" as `${T}`;
  return [x, t];
}
export function badBoundIntoParam<P extends A | B>(a: A): P[] {
  const half = (pts: P[]) => pts;
  return half([a]);
}
export function badLiteralIntoNumericParam<K extends number>() { const k: K = 1; return k; }
export function badLiteralArrayIntoNumericParam<K extends number>() { const ks: K[] = [1]; return ks; }
export function badBoundMemberIntoParamArray<P extends A | B>(as: A[]) { const ps: P[] = as; return ps; }
export function badBoundMemberIntoParam<P extends A | B>(a: A) { const p: P = a; return p; }
