// @strict: true
// @target: esnext

// A `const` destructured discriminant narrows the object it came from.
// `controlFlowAliasing` pins the plain, renamed and `switch` spellings;
// these are the cells next to them: an `else if` chain over three members,
// a truthiness test, a property-path source, a `switch` fall-through
// group, and the two spellings that do NOT narrow the source (a `let`
// binding and a defaulted one). The direct `item.ok` truthiness test on a
// boolean discriminant is beside them.

interface A { type: "a"; x: number; ok: true }
interface B { type: "b"; y: string; ok: false }
interface C { type: "c"; z: boolean; ok: false }
type U = A | B | C;

function okChain(item: U) {
  const { type } = item;
  if (type === "a") { const n: number = item.x; }
  else if (type === "b") { const s: string = item.y; }
  else { const b: boolean = item.z; }
}
function okTruthy(item: U) {
  const { ok } = item;
  if (ok) { const n: number = item.x; }
}
function okPropertyPath(props: { item: U }) {
  const { type } = props.item;
  if (type === "a") { const n: number = props.item.x; }
}
function okDirectTruthy(item: A | B) {
  if (item.ok) { const n: number = item.x; } else { const s: string = item.y; }
}
interface R1 { done: true; v: number }
interface R2 { done?: false; e: string }
function okOptionalFalse(r: R1 | R2) {
  if (r.done) { const n: number = r.v; }
}
function badLet(item: U) {
  let { type } = item;
  if (type === "a") { const n: number = item.x; }
}
function badDefault(item: U) {
  const { type = "a" } = item;
  if (type === "a") { const n: number = item.x; }
}
function badGroup(item: U) {
  const { type } = item;
  switch (type) { case "a": case "b": { const n: number = item.x; } }
}
