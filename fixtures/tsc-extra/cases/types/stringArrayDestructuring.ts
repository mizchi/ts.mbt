// @strict: true

// A string destructures as its characters: each element is a `string`,
// and a rest element is a `string[]`.

declare const hex: string;

export function okStringDestructure() {
  const [, r, g] = hex;
  return Number.parseInt(r + g, 16);
}
export function okStringDestructureRest() {
  const [first, ...rest] = hex;
  const s: string = first;
  const t: string[] = rest;
  return s + t.join("");
}
export function okLiteralDestructure() {
  const [c] = "ab";
  const s: string = c;
  return s;
}
export function badStringDestructure() {
  const [a] = hex;
  const n: number = a;
  return n;
}
export function badStringRest() {
  const [, ...rest] = hex;
  const n: number[] = rest;
  return n;
}
