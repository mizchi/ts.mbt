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

///|
/// `any | undefined` is `any`, as a source as well as a target: an optional
/// `any` parameter is spelled that way, and univer's
/// `Tools.isStringNumber(value?: any)` passes it to `Number.parseFloat`.
test "an optional any parameter does not leak undefined" {
  let src =
    #|export class T1 {
    #|  static okStatic(value?: any): boolean { return !isNaN(Number.parseFloat(value)) && isFinite(value); }
    #|}
    #|export function okBinding(v?: any) { const s: string = v; return s; }
    #|export function badNumber(v?: number) { const s: string = v; return s; }
  assert_eq(issue_lines(src), [
    "function badNumber > binding `s` init: type `number | undefined` is not assignable to type `string`",
  ])
}

///|
/// A write to an accessor is checked against the SETTER's parameter type,
/// which since TS 4.3 may be wider than the getter's (univer's
/// `BaseObject.resize`).
test "an accessor write takes the setter's type" {
  let src =
    #|export class B1 {
    #|  private _width: number = 0;
    #|  get width(): number { return this._width; }
    #|  protected set width(num: number | string) { this._width = typeof num === "string" ? 1 : num; }
    #|  okResize(width?: number | string) { if (width !== undefined) { this.width = width; } return this; }
    #|}
    #|export class B2 {
    #|  private _w: number = 0;
    #|  get w(): number { return this._w; }
    #|  set w(num: number | string) { this._w = 1; }
    #|}
    #|export function okWrite(b: B2, v: number | string) { b.w = v; }
    #|export function badWrite(b: B2) { b.w = true; }
    #|export function badRead(b: B2) { const s: string = b.w; return s; }
  assert_eq(issue_lines(src), [
    "function badWrite > assign `.w`: expected `number | string` but got `boolean`",
    "function badRead > binding `s` init: expected `string` but got `number`",
  ])
}

///|
/// Classes are structural, so a subclass that declares nothing of its own
/// takes an instance of its base (univer's `UniverRenderingContext extends
/// UniverRenderingContext2D { }`), while one that adds a member does not.
test "a base instance is assignable to a memberless subclass" {
  let src =
    #|export class Ctx2D { private _sys = 1; fill(): void {} }
    #|export class Ctx extends Ctx2D { }
    #|export class CtxPlus extends Ctx2D { extra = 1; }
    #|declare function draw(c: Ctx): void;
    #|declare function drawPlus(c: CtxPlus): void;
    #|export function okEmptySubclass(c: Ctx2D) { draw(c); }
    #|export function badAddedMember(c: Ctx2D) { drawPlus(c); }
  assert_eq(issue_lines(src), [
    "function badAddedMember > call `drawPlus` arg[0]: expected `CtxPlus` but got `Ctx2D`",
  ])
}

///|
/// A function's parameters are compared through the interface chain: a
/// handler taking the BASE event fits a slot typed by the derived one
/// (univer's `InputManager.dispose`), while an unrelated parameter type and
/// a mismatched return still report.
test "function parameters are compared through the interface chain" {
  let src =
    #|interface A0 { a: number }
    #|interface B0 extends A0 { b: number }
    #|interface C0 { c: number }
    #|export class IM3 {
    #|  okDispose() { this._h = null as unknown as (e: A0) => void; }
    #|  _h(e: B0) { e.b; }
    #|}
    #|export function okArrow() { let f: (e: B0) => void = (e: A0) => {}; return f; }
    #|export function badArrow() { let f: (e: B0) => void = (e: C0) => {}; return f; }
    #|export function badReturn(g: (e: A0) => string) { let f: (e: B0) => number = g; return f; }
  assert_eq(issue_lines(src), [
    "function badArrow > binding `f` init param `e`: expected `B0` but got `C0`",
    "function badReturn > binding `f` init: expected `(B0) => number` but got `(A0) => string`",
  ])
}

///|
/// A template literal type is a set of strings, so it is comparable to
/// `string` and to a string literal (univer's `r.name === hook.pluginName`
/// with a `${Biz}_${string}_PLUGIN` name), and not to a number.
test "a template literal type is comparable to a string" {
  let src =
    #|type Biz = "A" | "B";
    #|type RName = `${Biz}_${string}_PLUGIN`;
    #|declare const n: string;
    #|declare const r: RName;
    #|export const okString = n === r;
    #|export const okLiteral = [{ name: "x" }].find((x) => x.name === r);
    #|declare const num: number;
    #|export const badNumber = num === r;
  assert_eq(issue_lines(src), [
    "top-level > strict equality: comparing `number` and `type` with === will always be false",
  ])
}

///|
/// An enum member widens to its enum in a mutable binding (univer's
/// `let prevCharType = LinkCharType.Other`, reassigned in a loop), and stays
/// the member in a `const`.
test "an enum member widens to its enum in a let" {
  let src =
    #|enum K { A = "A", B = "B" }
    #|declare function of(c: string): K;
    #|export function okLoop(s: string) {
    #|  let prev = K.A;
    #|  for (let i = 0; i < s.length; i++) {
    #|    const t = of(s[i]);
    #|    if (i > 0 && prev !== K.B && t !== prev) { prev = t; }
    #|  }
    #|}
    #|export function okWiden() { let p = K.A; p = K.B; return p; }
    #|export function badConst() { const p = K.A; return p === K.B; }
  assert_eq(issue_lines(src), [
    "function badConst > strict equality: comparing `\"A\" (string)` and `\"B\" (string)` with === will always be false",
  ])
}

///|
/// A rest parameter whose type mentions an unsolved binder keeps its
/// element list, with the binder read as `any` (#310's review):
/// `...values: [number, T]` still checks its first argument against
/// `number` when `tag` is `any`.
test "a rest tuple keeps its known elements beside an unsolved binder" {
  let src =
    #|export class C { m<T extends string>(tag: T, ...values: [number, T]) {} }
    #|declare const tag: any;
    #|declare const c: C;
    #|c.m(tag, 42, "ok");
    #|c.m(tag, "wrong", "x");
  assert_eq(issue_lines(src), [
    "top-level > call `m` rest arg[0]: expected `number` but got `string`",
  ])
}

///|
/// Written type arguments decide a bounded generic's return, not the
/// argument (#310's review): `id<"a" | "b">("a")` is `"a" | "b"`, so a
/// `let` holding it takes `"b"`. With `id<"a">` it does not.
test "written type arguments decide a bounded generic's return" {
  let src =
    #|function id<T extends string>(x: T): T { return x; }
    #|const r = id<"a" | "b">("a");
    #|export const okR: "a" | "b" = r;
    #|let s = r;
    #|s = "b";
    #|const r2 = id<"a">("a");
    #|let s2 = r2;
    #|s2 = "b";
    #|declare function pair<T extends string, U extends number>(x: T, y: U): [T, U];
    #|export const okP: ["a" | "b", 1 | 2] = pair<"a" | "b", 1 | 2>("a", 1);
  assert_eq(issue_lines(src), [
    "top-level > assign `s2`: expected `\"a\" (string)` but got `\"b\" (string)`",
  ])
}

///|
/// `||=` drops a falsy member by what it resolves to, so `type Off =
/// false` goes like a written `false` (#310's review).
test "or-assignment drops an aliased falsy member" {
  let src =
    #|type Off = false;
    #|declare let x: Off | { n: number };
    #|const y = (x ||= { n: 1 });
    #|export const okY: { n: number } = y;
    #|declare let z: Off | { n: number };
    #|const w = (z ||= { n: 1 });
    #|export const badW: string = w;
  assert_eq(issue_lines(src), [
    "top-level > binding `badW` init: expected `string` but got `{ n: number }`",
  ])
}

///|
/// A `string` compared EQUAL to a literal is that literal, and a member
/// that cannot equal a string is gone (tsc's `replacePrimitivesWithLiterals`):
/// univer's `getSeparator` returns `token.value === '-' || token.value ===
/// '/' ? token.value : null` as `'-' | '/' | null`. The other side keeps
/// `string`.
test "a string compared equal to a literal is the literal" {
  let src =
    #|export function okPath(t: { value?: string | string[] }): "-" | "/" | null {
    #|  return t.value === "-" || t.value === "/" ? t.value : null;
    #|}
    #|export function okVar(v: string | undefined): "-" | null { if (v === "-") { return v; } return null; }
    #|export function okElse(v: string) { if (v !== "-") { const x: string = v; return x; } const y: "-" = v; return y; }
    #|export function badElse(v: string) { if (v !== "-") { const x: "-" = v; return x; } return null; }
    #|export function badArray(v: string | string[]) { if (v === "-") { const s: string[] = v; return s; } return null; }
  assert_eq(issue_lines(src), [
    "function badElse > binding `x` init: expected `\"-\" (string)` but got `string`",
    "function badArray > binding `s` init: expected `string[]` but got `string`",
  ])
}

///|
/// `typeof x === "object"` splits a union into its object members (`null`
/// included) and the rest, on both sides (univer's
/// `RichTextBuilder.insertParagraph`, `start?: number | ParagraphStyleBuilder`).
test "typeof object splits a union into objects and the rest" {
  let src =
    #|class PSB { ff = "a"; }
    #|interface Opt { a: number }
    #|export function okElse(start?: number | PSB) { let i: number; if (typeof start === "object") { i = 0; } else { i = start!; } return i; }
    #|export function okThen(start?: number | PSB) { if (typeof start === "object") { const p: PSB = start; return p.ff; } return ""; }
    #|export function okIface(x: string | Opt) { if (typeof x === "object") { return x.a; } const s: string = x; return s; }
    #|export function okNull(x: string | null) { if (typeof x === "object") { const n: null = x; return n; } const s: string = x; return s; }
    #|export function okArr(x: string | number[]) { if (typeof x !== "object") { const s: string = x; return s; } return x.length; }
    #|export function badThen(start?: number | PSB) { if (typeof start === "object") { const n: number = start; return n; } return 0; }
  assert_eq(issue_lines(src), [
    "function badThen > binding `n` init: expected `number` but got `PSB`",
  ])
}

///|
/// An object type has an implicit index signature, so it is assignable to
/// an interface of string index signatures when every member fits (univer's
/// `IDateTrie`, filled with `branch = {}`); a member that does not fit
/// still reports.
test "an object type meets an index-signature interface" {
  let src =
    #|interface IDateTrie { [token: string]: IDateTrie | number | undefined; }
    #|interface Idx { [k: string]: number }
    #|const e = {};
    #|export const okEmpty: IDateTrie = e;
    #|const f = { a: 1 };
    #|export const okMember: Idx = f;
    #|export const okUnion: IDateTrie | number = e;
    #|export function okPack(node: IDateTrie, char: string) {
    #|  let branch = node[char];
    #|  if (typeof branch !== "object") { branch = {}; node[char] = branch; }
    #|  return branch;
    #|}
    #|const g = { a: "s" };
    #|export const badMember: Idx = g;
  assert_eq(issue_lines(src), [
    "top-level > binding `badMember` init: expected `Idx` but got `{ a: string }`",
  ])
}

///|
/// With strictNullChecks off an unannotated getter returning `null` or
/// `undefined` is `any`, so its unannotated setter takes anything
/// (classPropertyIsPublicByDefault). With it on, the getter's `null`
/// stands.
test "a nullish getter widens to any without strictNullChecks" {
  let loose =
    #|// @strict: false
    #|class C {
    #|  get y() { return null; }
    #|  set y(x) { }
    #|  get u() { return undefined; }
    #|  set u(x) { }
    #|  get n() { return 1; }
    #|  set n(x) { }
    #|}
    #|declare var c: C;
    #|c.y = 1;
    #|c.u = "s";
    #|c.n = "bad";
  assert_eq(issue_lines(loose), [
    "top-level > assign `.n`: expected `number` but got `string`",
  ])
  let strict =
    #|class C {
    #|  get y() { return null; }
    #|  set y(x) { }
    #|}
    #|declare var c: C;
    #|c.y = 1;
  assert_eq(issue_lines(strict), [
    "top-level > assign `.y`: expected `null` but got `number`",
  ])
}

///|
/// `+` concatenates when either operand is made of strings, a union of
/// string literals included (univer's `nextToken`, where `token` is
/// narrowed to `"M" | "D"` and `path` is `data.path || ""`).
test "a union of strings is a string operand of plus" {
  let src =
    #|interface St { path: string }
    #|declare function next(d: St): void;
    #|export function f(data: St, token: string) {
    #|  const path = data.path || "";
    #|  if (token === "M" || token === "D") { next({ path: path + token }); }
    #|}
    #|export function bad(k: "a" | "b", n: number) { const m: number = k + n; return m; }
  assert_eq(issue_lines(src), [
    "function bad > binding `m` init: expected `number` but got `string`",
  ])
}

///|
/// The equal side of `x == null` keeps the nullish members `x` has: over
/// `null | P[][]` it is `null`, and over `string | null | undefined` both
/// (univer's `_handleCustomResult`).
test "loose null equality keeps the declared nullish members" {
  let src =
    #|type P = string | boolean | number | null;
    #|type R = P | P[][];
    #|declare function create(v: string | number | boolean | null): void;
    #|export function f(x: R) { if (typeof x !== "object" || x == null) { create(x); } }
    #|export function a(x: string | null) { if (x == null) { const n: null = x; } }
    #|export function c(x: string | null | undefined) { if (x == null) { const n: null = x; } }
  assert_eq(issue_lines(src), [
    "function c > binding `n` init: expected `null` but got `null | undefined`",
  ])
}

///|
/// A declared ALIAS to a union loses its nullish members to a non-nullish
/// initializer, as a written union does: `const raw: Op = []` with `type Op
/// = null | OpList` (ot-json1's `JSONOp`, univer's `addDrawing`). A later
/// `null` assignment and a nullable initializer still report.
test "an alias to a nullable union is narrowed by its initializer" {
  let src =
    #|type L = (number | L)[];
    #|type Op = null | L;
    #|export function okConst() { const raw: Op = []; raw.push(1); return raw; }
    #|export function okLet() { let raw: Op = []; raw.push(1); return raw; }
    #|export function badReassigned(c: boolean) { let raw: Op = []; if (c) { raw = null; } raw.push(1); }
    #|declare const v: Op;
    #|export function badNullableInit() { const raw: Op = v; raw.push(1); }
    #|type MaybeStr = string | undefined;
    #|export function okStr() { const s: MaybeStr = "x"; return s.length; }
  assert_eq(issue_lines(src), [
    "function badReassigned > call `push`: object is possibly `null`", "function badNullableInit > call `push`: object is possibly `null`",
  ])
}

///|
/// Every Promise callback is optional, as in `lib.es5.d.ts`, and
/// `then(ok, ng)` is a promise of both returns: univer's
/// `Promise.all(pending).then(…, (error) => …)` was "expected 1
/// argument(s), got 2", and `p.finally()` "got 0".
test "promise callbacks are optional" {
  let src =
    #|declare const p: Promise<number>;
    #|export const a = p.then((v) => v + 1, (e) => 0);
    #|export const b = p.then(undefined, (e) => "x");
    #|export const c = p.then();
    #|export const d = p.catch();
    #|export const e = p.finally();
    #|export const okBoth: Promise<number | string> = p.then((v) => v, () => "e");
    #|export const okUnd: Promise<number | string> = p.then(undefined, () => "e");
    #|export const bad = p.then((v: string) => v);
    #|export const badArity = p.then(() => 1, () => 2, 3);
    #|export const okUnion = p.then(() => "a", () => 1).then((x) => { const n: number | string = x; return n; });
    #|export const badUnion = p.then(() => "a", () => 1).then((x) => { const n: number = x; return n; });
  assert_eq(issue_lines(src), [
    "top-level > call `then` arg[0] param `v`: expected `number` but got `string`",
    "top-level > call `then`: expected 0-2 argument(s), got 3", "top-level > binding `n` init: expected `number` but got `\"a\" (string) | number`",
  ])
}

///|
/// An unannotated STATIC factory reads its return from the body when an
/// assignment narrows by it: univer's `v = NumberValueObject.create(0)`
/// inside `if (v == null)` left `v` possibly undefined after the `if`. An
/// explicit `: any` and a nullable body still report.
test "an unannotated static factory narrows an assignment" {
  let src =
    #|type Nullable<T> = T | null | undefined | void;
    #|class B { isBoolean() { return false; } }
    #|class N extends B {
    #|  static create(v: number) { return new N(); }
    #|  static loose(v: number): any { return new N(); }
    #|  static maybe(v: number) { return v > 0 ? new N() : undefined; }
    #|}
    #|export function ok(valueObject: Nullable<B>) { let v = valueObject; if (v == null) { v = N.create(0); } return v.isBoolean(); }
    #|export function badAny(valueObject: Nullable<B>) { let v = valueObject; if (v == null) { v = N.loose(0); } return v.isBoolean(); }
    #|export function badMaybe(valueObject: Nullable<B>) { let v = valueObject; if (v == null) { v = N.maybe(0); } return v.isBoolean(); }
  assert_eq(issue_lines(src), [
    "function badAny > call `isBoolean`: object is possibly `undefined`", "function badMaybe > call `isBoolean`: object is possibly `undefined`",
  ])
}

///|
/// A destructured discriminant belongs to its binding: an inner `const
/// kind` or a parameter named `kind` is a different binding and does not
/// narrow the source (#311's review). The direct use still does.
test "a shadowing binding does not reuse a destructured discriminant" {
  let src =
    #|type U = { kind: "a"; a: number } | { kind: "b"; b: string };
    #|export function shadowed(x: U) { const { kind } = x; { const kind = "b" as "a" | "b"; if (kind === "a") { const n: { kind: "a"; a: number } = x; return n; } } return 0; }
    #|export function direct(x: U) { const { kind } = x; if (kind === "a") { const n: { kind: "a"; a: number } = x; return n; } return 0; }
    #|export function param(x: U) { const { kind } = x; return (kind: "a" | "b") => { if (kind === "a") { const n: { kind: "a"; a: number } = x; return n; } return 0; }; }
  assert_eq(issue_lines(src), [
    "function shadowed > binding `n` init: expected `{ kind: \"a\" (string); a: number }` but got `{ kind: \"a\" (string); a: number } | { kind: \"b\" (string); b: string }`",
    "function param > binding `n` init: expected `{ kind: \"a\" (string); a: number }` but got `{ kind: \"a\" (string); a: number } | { kind: \"b\" (string); b: string }`",
  ])
}

///|
/// Two instantiations of one generic stay apart inside a union return of
/// a function type (#311's review): `() => Box<number> | undefined` is not
/// a `() => Box<string> | undefined`.
test "a function return union keeps generic arguments apart" {
  let src =
    #|interface Box<T> { value: T }
    #|declare let f1: () => Box<number> | undefined;
    #|declare let f2: () => Box<string> | undefined;
    #|f2 = f1;
    #|declare let g1: () => Box<number>;
    #|declare let g2: () => Box<string>;
    #|g2 = g1;
    #|declare let h1: () => Box<string> | undefined;
    #|f2 = h1;
  assert_eq(issue_lines(src), [
    "top-level > assign `f2`: expected `() => Box<string> | undefined` but got `() => Box<number> | undefined`",
    "top-level > assign `g2`: expected `() => Box<string>` but got `() => Box<number>`",
  ])
}

///|
/// A parameter named like an enum is that parameter: `E.A` reads its own
/// member and is not widened to the enum (#311's review).
test "a parameter shadowing an enum is read through its own type" {
  let src =
    #|enum E { A = "global" }
    #|export function local(E: { A: "local" }) { let value = E.A; value = "other"; return value; }
    #|export function wide(E: { A: string }) { let value = E.A; value = "other"; return value; }
    #|export function read(E: { A: string }) { const n: number = E.A; return n; }
  assert_eq(issue_lines(src), [
    "function local > assign `value`: expected `\"local\" (string)` but got `\"other\" (string)`",
    "function read > binding `n` init: expected `number` but got `string`",
  ])
}

///|
/// An `any`-typed parameter named like an enum shadows it too (#311's
/// review): `E.A` is then `any`. The enum itself, and an enum merged with
/// a namespace, still read the member.
test "an any-typed parameter shadowing an enum is any" {
  let src =
    #|enum E { A = "global" }
    #|export function shadow(E: any) { const n: number = E.A; return n; }
    #|export function real() { const s: number = E.A; return s; }
    #|enum M { A = "m" }
    #|namespace M { export const k = 1; }
    #|export const merged: number = M.A;
  assert_eq(issue_lines(src), [
    "function real > binding `s` init: expected `number` but got `string`", "top-level > binding `merged` init: expected `number` but got `string`",
  ])
}
