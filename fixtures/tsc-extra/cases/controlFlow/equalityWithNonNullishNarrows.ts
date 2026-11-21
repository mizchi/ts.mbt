// @strict: true

// `x === y` narrows `x` when `y` cannot be nullish: on the equal side `x`
// is not nullish either. The not-equal side learns nothing, a nullable `y`
// narrows nothing, and loose `==` against a `y` that may be `undefined`
// leaves `x` possibly `null` or `undefined`.

interface C { w(): number }
interface P { canvas: C; ok: boolean }
declare const prev: P | undefined;

export function okAfterGuard(canvas: C | undefined) {
  if (!(prev?.ok && canvas === prev.canvas && canvas.w() === 1)) return undefined;
  return canvas.w();
}
export function okInConjunction(canvas: C | undefined, p: P) {
  return canvas === p.canvas && canvas.w();
}
export function okIf(canvas: C | undefined, p: P) {
  if (canvas === p.canvas) { return canvas.w(); }
  return 0;
}
export function okNotEqual(canvas: C | undefined, p: P) {
  if (canvas !== p.canvas) { return 0; }
  return canvas.w();
}
export function okReversed(canvas: C | undefined, p: P) {
  if (p.canvas == canvas) { return canvas.w(); }
  return 0;
}
export function badElse(canvas: C | undefined, p: P) {
  if (canvas === p.canvas) { return 0; }
  return canvas.w();
}
export function badNullableOther(canvas: C | undefined, q: C | undefined) {
  if (canvas === q) { return canvas.w(); }
  return 0;
}
export function badLoose(canvas: C | null | undefined, q: C | undefined) {
  if (canvas == q) { return canvas.w(); }
  return 0;
}
