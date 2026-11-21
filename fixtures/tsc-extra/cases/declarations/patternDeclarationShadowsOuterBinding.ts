// @strict: true
// @target: esnext

// A `let` / `const` destructuring pattern or loop head declares new
// bindings, so a name that shadows an outer binding has its own declared
// type: assignments to it inside the block are judged against that type,
// and the outer binding is untouched after the block.

declare const flag: boolean;
export function okObjectPattern() {
  let a = "s";
  if (flag) { let { a } = { a: 1 }; a = 2; }
  return a.length;
}
export function okArrayPattern() {
  let a = "s";
  if (flag) { let [a] = [1]; a = 2; }
  return a.length;
}
export function okForInHead(o: object) {
  let k = 1;
  for (let k in o) { k = "x"; }
  return k + 1;
}
export function okForOfHead(xs: number[]) {
  let k = "outer";
  for (let k of xs) { k = k + 1; }
  return k.length;
}
export function okForOfPatternHead(xs: [number][]) {
  let k = "outer";
  for (let [k] of xs) { k = k + 1; }
  return k.length;
}
export function badInnerStillChecked(xs: number[]) {
  for (let k of xs) { k = "s"; }
}
