// Narrowing and widening through the spellings real code uses, each cell
// probed against the TypeScript nightly: every `ok…` line is accepted and
// every reported line is one tsc reports.

///|
/// TS 4.4: a `const` destructured discriminant narrows the object it came
/// from (univer's `DropdownMenu`: `const { className, type } = item; if
/// (type === "separator") … else if (type === "custom") { item.children }`).
/// A `let` binding and a defaulted one do not, and a `switch` group keeps
/// the union of its labels.
test "a destructured discriminant narrows its source" {
  let src =
    #|interface A { type: "a"; x: number; ok: true }
    #|interface B { type: "b"; y: string; ok: false }
    #|interface C { type: "c"; z: boolean; ok: false }
    #|type U = A | B | C;
    #|export function okChain(item: U) {
    #|  const { type } = item;
    #|  if (type === "a") { const n: number = item.x; }
    #|  else if (type === "b") { const s: string = item.y; }
    #|  else { const b: boolean = item.z; }
    #|}
    #|export function okForms(item: U, props: { item: U }) {
    #|  const { type: t } = item;
    #|  if ("a" === t) { const n: number = item.x; }
    #|  if (t == "b") { const s: string = item.y; }
    #|  if (t !== "a" && t !== "b") { const b: boolean = item.z; }
    #|  const { ok } = item;
    #|  if (ok) { const n2: number = item.x; }
    #|  const { type: pt } = props.item;
    #|  if (pt === "a") { const n3: number = props.item.x; }
    #|  if (t === "a") { const g = () => { const n4: number = item.x; }; }
    #|}
    #|export function okEarly(item: U) {
    #|  const { type } = item;
    #|  if (type !== "a") { return; }
    #|  const n: number = item.x;
    #|}
    #|export function okSwitch(item: U) {
    #|  const { type } = item;
    #|  switch (type) {
    #|    case "a": { const n: number = item.x; break; }
    #|    case "b": { const s: string = item.y; break; }
    #|    default: { const b: boolean = item.z; }
    #|  }
    #|}
    #|export function badLet(item: U) {
    #|  let { type } = item;
    #|  if (type === "a") { const n: number = item.x; }
    #|}
    #|export function badDefault(item: U) {
    #|  const { type = "a" } = item;
    #|  if (type === "a") { const n: number = item.x; }
    #|}
    #|export function badGroup(item: U) {
    #|  const { type } = item;
    #|  switch (type) { case "a": case "b": { const n: number = item.x; } }
    #|}
    #|export function badNarrowed(item: U) {
    #|  const { type } = item;
    #|  if (type === "a") { const s: string = item.x; }
    #|}
  assert_eq(issue_lines(src), [
    "function badLet > PropAccess `.x`: property `x` does not exist on `U`", "function badDefault > PropAccess `.x`: property `x` does not exist on `U`",
    "function badGroup > PropAccess `.x`: property `x` does not exist on `B | A`",
    "function badNarrowed > binding `s` init: expected `string` but got `number`",
  ])
}

///|
/// A truthiness test of a boolean discriminant narrows the receiver, on
/// both sides, and an optional `done?: false` is falsy.
test "a truthy discriminant narrows its receiver" {
  let src =
    #|interface A { type: "a"; x: number; ok: true }
    #|interface B { type: "b"; y: string; ok: false }
    #|type U = A | B;
    #|export function okBoth(item: U) {
    #|  if (item.ok) { const n: number = item.x; } else { const s: string = item.y; }
    #|}
    #|export function okNot(item: U) { if (!item.ok) { return; } const n: number = item.x; }
    #|interface R1 { done: true; v: number }
    #|interface R2 { done?: false; e: string }
    #|export function okOptional(r: R1 | R2) { if (r.done) { const n: number = r.v; } }
    #|export function badSide(item: U) { if (item.ok) { const s: string = item.y; } }
  assert_eq(issue_lines(src), [
    "function badSide > PropAccess `.y`: property `y` does not exist on `A`",
  ])
}

///|
/// A union member that is itself an alias to a union is expanded before a
/// nullish test removes members: univer's `Nullable<T> = T | null |
/// undefined | void`, reached through `x ??= f()` and through `cond ? field
/// : null`, kept its `null | undefined | void` behind `!= null`.
test "a nullable alias inside a union loses its nullish members" {
  let src =
    #|type Nullable<T> = T | null | undefined | void;
    #|interface TB { n: number }
    #|interface St { pending: Nullable<TB>; other: Nullable<TB> }
    #|declare function start(): Nullable<TB>;
    #|declare function step(b: TB): boolean;
    #|export function okProp(state: St) {
    #|  state.pending ??= start();
    #|  if (state.pending != null && !step(state.pending)) { return; }
    #|}
    #|export function okBinding(p: Nullable<TB>) {
    #|  p ??= start();
    #|  if (p != null && !step(p)) { return; }
    #|}
    #|export function okConditional(state: St, c: boolean) {
    #|  const q = c ? state.other : null;
    #|  if (q != null) { step(q); }
    #|}
    #|export function badUnguarded(state: St) {
    #|  state.pending ??= start();
    #|  step(state.pending);
    #|}
  assert_eq(issue_lines(src), [
    "function badUnguarded > call `step` arg[0]: type `TB | void | TB | null | undefined | void` is not assignable to type `TB`",
  ])
}

///|
/// An array literal used as a method RECEIVER has no contextual type, so
/// its literal elements widen (univer's `['__proto__', 'prototype',
/// 'constructor'].includes(key)`); the same array `as const` keeps them.
test "an array literal receiver widens its literal elements" {
  let src =
    #|declare const key: string;
    #|declare const v: unknown;
    #|export const okIncludes = ["__proto__", "prototype", "constructor"].includes(key);
    #|export const okTypeof = ["string", "number", "boolean"].includes(typeof v);
    #|export const badElement = ["a", "b"].includes(1);
  assert_eq(issue_lines(src), [
    "top-level > call `includes` arg[0]: expected `string` but got `number`",
  ])
}

///|
/// `any[K]` is `any` for every key. A non-literal key left it unreduced,
/// and the unreduced shape read as a receiver with no members (univer's
/// `ReturnType<DocumentViewModel["getChildren"]>[number]`, where the
/// unannotated method reads as `() => any` here).
test "an indexed access into any is any" {
  let src =
    #|class VM { private _c: { endIndex: number }[] = []; getChildren() { return this._c; } }
    #|declare const q: any;
    #|export function okUnannotated(s: ReturnType<VM["getChildren"]>[number]) { return s.endIndex; }
    #|export function okAnyIndex(s: (typeof q)[number]) { return s.foo; }
  assert_eq(issue_lines(src), [])
}

///|
/// The empty object type takes no excess-property check, and a binding
/// declared `{}` is not narrowed by an assignment, because tsc narrows by
/// assignment only a UNION declaration (univer's `handleBorder`, which
/// fills `let obj = {}` in an `if` chain and returns it as an all-optional
/// interface). A non-empty target still checks its excess keys.
test "an empty object type takes no excess check and no assignment narrowing" {
  let src =
    #|interface BD { t?: { s: number } | null; r?: { s: number } | null }
    #|export function okAssign(arr: string[]): BD {
    #|  let obj = {};
    #|  if (arr.length === 1) { obj = { t: arr[0], r: arr[0] }; }
    #|  return obj;
    #|}
    #|export function okDeclared() {
    #|  let o: {} = { a: 1 };
    #|  o = { b: 2 };
    #|  return o;
    #|}
    #|export function badRead(arr: string[]) {
    #|  let obj = {};
    #|  obj = { t: arr[0] };
    #|  return obj.t;
    #|}
    #|export function badExcess() {
    #|  let o: { a?: number } = {};
    #|  o = { a: 1, zz: 2 };
    #|  return o;
    #|}
  assert_eq(issue_lines(src), [
    "function badRead > PropAccess `.t`: property `t` does not exist on `{}`", "function badExcess > assign `o`.zz: property `zz` does not exist on target type",
  ])
}

///|
/// A binding declared as a tuple keeps the tuple through an assignment of
/// an array literal (univer's `dec2frac`).
test "a tuple declaration is not narrowed by an array literal assignment" {
  let src =
    #|export function okTuple(n: number, s: number): [number, number] {
    #|  let r: [number, number];
    #|  if (n % 1 === 0) { r = [n * s, 1]; } else { r = [s, 1e19]; }
    #|  return r;
    #|}
    #|export function badTuple(n: number): [string, number] {
    #|  let r: [number, number];
    #|  r = [n, 1];
    #|  return r;
    #|}
  assert_eq(issue_lines(src), [
    "function badTuple > return: expected `[string, number]` but got `[number, number]`",
  ])
}

///|
/// A union member that is an alias to a union is expanded before an
/// `instanceof` test removes members (univer's `OrInput = string | Or |
/// CharsetInput`), and a member two aliases share is kept once.
test "a nested union alias is split by instanceof" {
  let src =
    #|type Unit = [number, number];
    #|type RawInput = string | number | Unit;
    #|class Charset { x = 1 }
    #|type CharsetInput = Charset | RawInput;
    #|class Or { s = 1 }
    #|type OrInput = string | Or | CharsetInput;
    #|export function okOr(inputs: OrInput[]) {
    #|  const strings: string[] = [];
    #|  for (const input of inputs) {
    #|    if (input instanceof Or) { }
    #|    else if (input instanceof Charset || typeof input === "number" || Array.isArray(input)) { }
    #|    else { strings.push(input); }
    #|  }
    #|}
    #|export function badOr(inputs: OrInput[]) {
    #|  const nums: number[] = [];
    #|  for (const input of inputs) {
    #|    if (input instanceof Or || input instanceof Charset) { }
    #|    else if (!Array.isArray(input)) { nums.push(input); }
    #|  }
    #|}
  assert_eq(issue_lines(src), [
    "function badOr > call `push` arg[0]: expected `number` but got `string | number`",
  ])
}
