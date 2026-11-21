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

///|
/// A block-local declaration that shadows an outer binding gives the
/// outer one its declaration back when the block ends: `{ let x = 5 }`
/// then `x = "a"` on a `let x: string | null` is legal (probed), and so
/// are the `if`-branch and `for`-head spellings. Inside the block the
/// inner declaration still decides.
test "a shadowing block declaration gives the outer binding its declaration back" {
  let src =
    #|declare const c: boolean;
    #|export function s2() { let x: string | null = null; if (c) { let x = 5; x = 6; } else { x = "a"; } return x; }
    #|export function s3() { let x: string | null = null; { let x = 5; x = 6; } x = "a"; return x; }
    #|export function s4() { let x: string | null = null; if (c) { let x = 5; } x = "a"; return x; }
    #|export function s5() { let x: string | null = null; for (let x = 0; x < 3; x++) { } x = "a"; return x; }
    #|export function inner() { let x: string | null = null; { let x = 5; x = "a"; } return x; }
  assert_eq(issue_lines(src), [
    "function inner > assign `x`: expected `number` but got `string`",
  ])
}

///|
/// TS 4.4 aliased conditions through `&&` / `||`: `const ok = hit && n < 3`
/// narrows `hit` wherever `ok` is known truthy, `if (ok)` and the exit of
/// `if (!ok) return` alike, and `const bad = !hit || …` the same way round.
/// The falsy side of an `&&` (and the truthy side of an `||`) proves
/// nothing, and an assignment between the alias and its use cancels it.
test "an and-or initializer is an aliased condition" {
  let src =
    #|interface El { id: string }
    #|declare function get(): El | null;
    #|declare const n: number;
    #|export function a1(): string { const hit = get(); const ok = hit && n < 3; if (!ok) { return ""; } return hit.id; }
    #|export function a4(): string { const hit = get(); const ok = hit && n < 3; if (ok) { return hit.id; } return ""; }
    #|export function b2(): string { const hit = get(); const bad = !hit || n > 3; if (bad) { return ""; } return hit.id; }
    #|export function c1(): string { const hit = get(); const ok = hit && n < 3; if (!ok) { return hit.id; } return ""; }
    #|export function c2(): string { const hit = get(); const ok = n < 3 || hit; if (!ok) { return ""; } return hit.id; }
    #|export function c3(): string { let hit = get(); const ok = hit && n < 3; hit = get(); if (!ok) { return ""; } return hit.id; }
  assert_eq(issue_lines(src), [
    "function c1 > PropAccess `.id`: object is possibly `null`", "function c2 > PropAccess `.id`: object is possibly `null`",
    "function c3 > PropAccess `.id`: object is possibly `null`",
  ])
}

///|
/// A binding DECLARED `any` (here the auto-typed `let data = null`) takes
/// a value this cannot type as `any`, which is what tsc gives it: after
/// `data = JSON.parse(raw)` the `if (!data) return` guard leaves `any`, not
/// `never`. A written union keeps its declaration, so the read is still
/// judged there (`x` is possibly `undefined` in tsc too).
test "an any-declared binding takes an uninferable value as any" {
  let src =
    #|declare const raw: string;
    #|declare const c: boolean;
    #|export function u1() { let data = null; data = JSON.parse(raw); if (!data) { return; } return data.info; }
    #|export function u2() { let data = null; if (c) { data = JSON.parse(raw); } if (!data) { return; } return data.info; }
    #|export function v1() { let x: string | undefined = undefined; x = JSON.parse(raw); return x.length; }
  assert_eq(issue_lines(src), [
    "function v1 > PropAccess `.length`: object is possibly `undefined`",
  ])
}

///|
/// What a bare block or a `try` assigns to an outer binding reaches the
/// code after it. After `try`/`catch` the binding is the join of the two
/// exits, so a catch that leaves it `null` keeps the report, a catch that
/// returns does not, and a `try` that always returns leaves the catch's
/// state. A declaration inside the block is its own binding.
test "an assignment in a block or a try reaches the code after it" {
  let src =
    #|declare const raw: string;
    #|declare function risky(): void;
    #|export function w1() { let x = null; { x = JSON.parse(raw); } if (!x) { return; } return x.info; }
    #|export function w2() { let x = null; try { x = JSON.parse(raw); } catch {} if (!x) { return; } return x.info; }
    #|export function n1() { let x: { info: number } | null = null; try { x = { info: 1 }; } catch {} return x.info; }
    #|export function n2() { let x: { info: number } | null = null; try { x = { info: 1 }; } catch { return 0; } return x.info; }
    #|export function n4() { let x: string | null = null; { x = "a"; } return x.length; }
    #|export function n5() { let x: string | null = null; { let x = "a"; x.length; } return x.length; }
    #|export function n6() { let x: string | null = null; try { risky(); } catch { x = "a"; } return x.length; }
    #|export function n7() { let x: string | null = null; try { return 0; } catch { x = "a"; } return x.length; }
    #|export function n8() { let x: string | null = null; try { x = "a"; } finally { risky(); } return x.length; }
  assert_eq(issue_lines(src), [
    "function n1 > PropAccess `.info`: object is possibly `null`", "function n5 > PropAccess `.length`: object is possibly `null`",
    "function n6 > PropAccess `.length`: object is possibly `null`",
  ])
}

///|
/// The falsy part of a `boolean` left operand of `&&` is `false`, so
/// `flag && obj` is `false | Obj` and `if (p)` on it leaves `Obj`
/// (excalidraw's `insertAtParentCenter && this.snap(…)`). An `any` right
/// operand makes the whole expression `any`. `boolean[]`'s `x => !!x`
/// still infers no `x is true`, as in tsc.
test "a boolean and an object joined by and narrow to the object" {
  let src =
    #|declare const flag: boolean;
    #|declare const av: any;
    #|interface P { ex: number }
    #|declare function snap(x: number): P | undefined;
    #|declare const bools: boolean[];
    #|export function run(x: number) { const p = flag && snap(x); if (p) { return p.ex; } return 0; }
    #|export function anyRight() { const p = flag && av; const n: string = p; return n; }
    #|export function falsePart(x: number) { const p = flag && snap(x); const q: P = p; return q; }
    #|export const kept: true[] = bools.filter((x) => !!x);
  assert_eq(issue_lines(src), [
    "function falsePart > binding `q` init: type `false | P | undefined` is not assignable to type `P`",
    "top-level > binding `kept` init: expected `true[]` but got `boolean[]`",
  ])
}

///|
/// A NAMED Promise handler contributes what it returns, not itself
/// (#312's review): `p.then(ok)` is a promise of `ok`'s return, and
/// `p.then(undefined, recover)` of the fulfilled value or `recover`'s.
test "a named promise handler contributes its return" {
  let src =
    #|declare const p: Promise<string>;
    #|function recover(e: unknown): string { return "x"; }
    #|function ok(s: string): number { return s.length; }
    #|export async function pa() { const r = await p.then(undefined, recover); const s: string = r; return s; }
    #|export async function pb() { const r = await p.then(ok); const n: number = r; return n; }
    #|export async function pe() { const r = await p.then(ok); const s: string = r; return s; }
  assert_eq(issue_lines(src), [
    "function pe > binding `s` init: expected `string` but got `number`",
  ])
}

///|
/// The catch and finally blocks are entered from a state the try block may
/// have left at any statement (#312's review): a write before a `throw`, a
/// write a later statement overwrites, and a write before a `return` (for
/// `finally`) all reach them. A try block that writes nothing leaves the
/// pre-try state.
test "catch and finally see what the try block wrote before leaving" {
  let src =
    #|declare function risky(): void;
    #|export function c1() { let x: string | null = "ok"; try { x = null; throw 0; } catch {} return x.length; }
    #|export function c2() { let x: string | null = "ok"; try { x = null; risky(); x = "a"; } catch { return x.length; } return 0; }
    #|export function f1() { let x: string | null = "ok"; try { x = null; return; } finally { x.length; } }
    #|export function okc() { let x: string | null = "ok"; try { risky(); } catch { return x.length; } return 0; }
    #|export function okf() { let x: string | null = "ok"; try { risky(); } finally { x.length; } return 0; }
  assert_eq(issue_lines(src), [
    "function c1 > PropAccess `.length`: object is possibly `null`", "function c2 > PropAccess `.length`: object is possibly `null`",
    "function f1 > PropAccess `.length`: object is possibly `null`",
  ])
}

///|
/// A catch binding is the catch block's own, and a nested block's
/// declaration has gone out of scope by the time the enclosing block goes
/// on, so neither hides the try block's write to the outer name (#312's
/// review). An assignment inside a block cancels an aliased condition on
/// the name it assigns.
test "catch bindings, nested blocks and alias cancellation across a block" {
  let src =
    #|export function s1() { let x: string | null = "ok"; try { x = null; } catch (x) {} return x.length; }
    #|export function n1() { let x: string | null = "ok"; try { { let x = 1; } x = null; } finally {} return x.length; }
    #|export function a1(y: string | null) { let x: string | null = y; const ok = x !== null; { x = y; } if (ok) { return x.length; } return 0; }
    #|export function a2(y: string | null) { let x: string | null = y; const ok = x !== null; { y = null; } if (ok) { return x.length; } return 0; }
  assert_eq(issue_lines(src), [
    "function s1 > PropAccess `.length`: object is possibly `null`", "function n1 > PropAccess `.length`: cannot access `.length` — receiver may be null or undefined",
    "function a1 > PropAccess `.length`: object is possibly `null`",
  ])
}

///|
/// A static method's unannotated return is recorded apart from the
/// instance methods, so a quoted instance method spelled `"static:make"`
/// keeps its written `: any` (#312's review).
test "a static unannotated return does not collide with a quoted instance name" {
  let src =
    #|interface I { "static:make"(): number }
    #|export class C implements I {
    #|  static make() { return 0; }
    #|  "static:make"(): any { return ""; }
    #|}
  assert_eq(issue_lines(src), [])
}

///|
/// An always-falsy left operand of `&&` is the result even beside an
/// `any` right operand (#312's review): `undefined && anyValue` is
/// `undefined`, not `any`.
test "an always-falsy left operand of and is the result" {
  let src =
    #|declare const anyv: any;
    #|export function n2() { const r = undefined && anyv; const s: string = r; return s; }
  assert_eq(issue_lines(src), [
    "function n2 > binding `s` init: expected `string` but got `undefined`",
  ])
}

///|
/// Round two of #312's review, each cell probed against the nightly: a
/// write to a nested block's OWN binding does not widen the outer one for
/// `catch` / `finally`; what `finally` writes reaches the code after the
/// statement, and a `finally`-local binding does not; and a static
/// factory's return is read with its parameters in scope.
test "finally writes, nested-block bindings and static factory parameters" {
  let src =
    #|declare function risky(): void;
    #|export function A3() { let x: string | null = "s"; try { { let x: string | null = "a"; x = null; } risky(); } catch { return x.length; } return 0; }
    #|export function A4() { let x: string | null = "s"; try { { let x: string | null = "a"; x = null; } risky(); } finally { x.length; } return 0; }
    #|export function A5() { let x: string | null = "s"; try { { x = null; } risky(); } catch { return x.length; } return 0; }
    #|export function B1() { let x: string | null = "ok"; try { x = null; } finally { x = "ok"; } return x.length; }
    #|export function B2() { let x: string | null = "ok"; try { x = "a"; } finally { x = null; } return x.length; }
    #|export function B3() { let x: string | null = "ok"; try { x = null; } finally { let x = 1; x = 2; } return x.length; }
    #|class Factory { static create(value: string | null) { return value; } }
    #|declare const value: string;
    #|export function C1() { let result: string | null = null; result = Factory.create(null); return result.length; }
  assert_eq(issue_lines(src), [
    "function A5 > PropAccess `.length`: object is possibly `null`", "function B2 > PropAccess `.length`: cannot access `.length` — receiver may be null or undefined",
    "function B3 > PropAccess `.length`: cannot access `.length` — receiver may be null or undefined",
    "function C1 > PropAccess `.length`: object is possibly `null`",
  ])
}

///|
/// A join with an `any` side is `any`, as a union with `any` is in tsc.
/// The try/catch join kept `any | { appState }`, so excalidraw's
/// `initializeScene` reported `initialData?.elements`; main reported the
/// same sites as "does not exist on `null`", and the `if` form too.
/// Probed against the nightly: the `string` neighbours are TS2339.
test "a join with an any side is any" {
  let src =
    #|declare const anyv: any;
    #|declare const c: boolean;
    #|declare function g(): any;
    #|export async function okTry() { let d = null; try { d = (await g()) || null; } catch (e: any) { d = { appState: { m: e.message } }; } return d?.elements; }
    #|export function okIf() { let d = null; if (c) { d = anyv; } else { d = { a: 1 }; } return d?.b; }
    #|export function badIf() { let d = null; if (c) { d = "s"; } else { d = { a: 1 }; } return d.b; }
    #|export function badTry() { let d = null; try { d = "s"; } catch { d = { a: 1 }; } return d.b; }
  assert_eq(issue_lines(src), [
    "function badIf > PropAccess `.b`: property `b` does not exist on `\"s\" (string) | { a: number }`",
    "function badTry > PropAccess `.b`: property `b` does not exist on `\"s\" (string) | { a: number }`",
  ])
}

///|
/// Batch HB, each cell probed against the nightly. A `switch` over an
/// `any` scrutinee with grouped labels narrows to `any`, not `any | any`. A
/// `RegExp` or `Date` instance keeps its lib type, so `regex.exec(t)` is
/// `RegExpExecArray | null` and an assignment loop narrows it. An auto-typed
/// binding takes a back-edge value this cannot type as `any`. `await` on `T
/// | Promise<T>` awaits each member.
test "grouped any labels, lib instances, auto-typed back edges and awaited unions" {
  let src =
    #|declare const els: any[];
    #|export function sw() { for (const element of els) { switch (element.type) { case "rectangle": case "ellipse": return element?.label?.text; } } return 0; }
    #|export function re(t: string) { const regex = /a/g; let match = null; while ((match = regex.exec(t)) !== null) { return match.index; } return -1; }
    #|export function dateBad() { const d = new Date(); const n: string = d.getTime(); return n; }
    #|export function reBad(t: string) { const r = new RegExp("a"); const n: number = r.test(t); return n; }
    #|declare const gs: { content: string }[];
    #|export function inLoop() { let prev = null; for (const g of gs) { if (prev && prev.content === "x") return 1; const cur = g; prev = cur; } return 0; }
    #|type MaybePromise<T> = T | Promise<T>;
    #|declare function gen(): MaybePromise<{ html: string }>;
    #|export async function aw() { const { html } = await gen(); return html.trim(); }
    #|export async function awBad() { const { html } = await gen(); const n: number = html; return n; }
  assert_eq(issue_lines(src), [
    "function dateBad > binding `n` init: expected `string` but got `number`", "function reBad > binding `n` init: expected `number` but got `boolean`",
    "function awBad > binding `n` init: expected `number` but got `string`",
  ])
}

///|
/// A `const` arrow guard narrows a parameter typed by an indexed access and
/// a property path, as a declared guard does. `x === false` on a union with
/// a `boolean` leaves `true`. And `&&` / `||` narrow on both sides in both
/// senses: the else branch of `!a?.x && !a?.y` has `a` defined, and the then
/// branch of `!(x === null || y === null)` has both non-null, where it had
/// read `x` as `null`.
test "const guards on indexed types and paths, boolean literals, logical sides" {
  let src =
    #|type UIConfig = { enabled: { zoom?: boolean } } | { disabled: { minimap?: boolean } };
    #|type AppProps = { ui?: boolean | UIConfig };
    #|const isUIConfig = (ui: AppProps["ui"]): ui is UIConfig => typeof ui === "object" && ui !== null;
    #|export function g1(props: AppProps) { if (isUIConfig(props.ui)) { return "enabled" in props.ui ? props.ui.enabled.zoom : props.ui.disabled.minimap; } return undefined; }
    #|export function g2(ui: AppProps["ui"]) { if (isUIConfig(ui)) { const x: UIConfig = ui; return x; } return null; }
    #|export function g3(props: AppProps) { if (!isUIConfig(props.ui)) { const c: UIConfig = props.ui; return c; } return null; }
    #|export function b1(o: boolean | number | undefined): number { if (o === false) return 0; if (o === true || o == null) return 1; return Math.max(o, 0); }
    #|export function b2(o: boolean | number): number { if (o === false) return 0; return o; }
    #|type Lock = { scroll?: boolean; zoom?: boolean; overscroll?: number };
    #|export function l1(lock?: Lock) { if (!lock?.scroll && !lock?.zoom) return 0; return lock.overscroll; }
    #|export function l2(lock?: Lock) { if (!lock?.scroll || !lock?.zoom) return lock.overscroll; return 0; }
    #|export function n1(x: string | null, y: string | null) { if (!(x === null || y === null)) { return x.length + y.length; } return 0; }
    #|export function n2(x: string | null, y: string | null) { if (!(x === null || y === null)) { return 0; } return x.length; }
  assert_eq(issue_lines(src), [
    "function g3 > binding `c` init: type `boolean | undefined` is not assignable to type `{ enabled: { zoom: boolean | undefined } } | { disabled: { minimap: boolean | undefined } }`",
    "function b2 > return: expected `number` but got `true | number`", "function l2 > PropAccess `.overscroll`: object is possibly `undefined`",
    "function n2 > PropAccess `.length`: object is possibly `null`",
  ])
}

///|
/// An object rest over a union is a union of the members' rests, as tsc
/// distributes it, so the rest keeps each member's discriminant and narrows
/// by it (probed). It had been the fields common to every member, with the
/// first member's discriminant.
test "an object rest over a union keeps each member" {
  let src =
    #|type Base = { size?: string; hidden?: boolean };
    #|type P = (Base & { type: "button"; onClick?(): void }) | (Base & { type: "toggle"; checked: boolean });
    #|export function f({ size = "m", ...props }: P) { if (props.type === "button") return props.onClick; return props.checked; }
    #|type Q = { type: "a"; x: number; k: string } | { type: "b"; y: string; k: string };
    #|export function t1({ k, ...rest }: Q) { const z: "z" = rest.type; return z; }
    #|export function t2({ k, ...rest }: Q) { if (rest.type === "a") { const s: string = rest.x; return s; } return ""; }
  assert_eq(issue_lines(src), [
    "function t1 > binding `z` init: expected `\"z\" (string)` but got `\"a\" (string) | \"b\" (string)`",
    "function t2 > binding `s` init: expected `string` but got `number`",
  ])
}

///|
/// A DOM interface the lib tables do not carry may declare any member, so
/// a union holding one abstains on member existence whether it is written
/// out or reached through an alias, and a field destructured from it is
/// `any` rather than `T | undefined` (probed: the nightly accepts both).
test "an opaque lib member of a union abstains through an alias and a pattern" {
  let src =
    #|type MC = OffscreenCanvas | HTMLCanvasElement;
    #|export function h(c: MC) { return c.width; }
    #|export function k(c: HTMLCanvasElement | OffscreenCanvas) { return c.width; }
    #|interface RPE { clientX: number; button: number }
    #|export function f(event: RPE | MouseEvent) { let { clientX: lastX } = event; return lastX - 1; }
    #|interface A { a: number; t: "a" }
    #|interface B { b: string; t: "b"; a?: number }
    #|export function g(v: A | B) { const { a } = v; const n: number = a; return n; }
  assert_eq(issue_lines(src), [
    "function g > binding `n` init: type `number | undefined` is not assignable to type `number`",
  ])
}

///|
/// An object literal against an interface intersected with an object type
/// is checked field by field, the interface's inherited members included,
/// as the plain interface target is. It had fallen to the whole-object
/// relation, which reads an enum member as `number` (probed).
test "an object literal against an interface intersection is checked by field" {
  let src =
    #|enum E { A, B }
    #|interface I1 { type: E }
    #|interface J extends I1 { name: string }
    #|declare function n1(v: I1 & { event: string }): void;
    #|declare function nj(v: J & { event: string }): void;
    #|export function ok1() { n1({ type: E.B, event: "x" }); }
    #|export function ok2() { nj({ type: E.A, name: "n", event: "x" }); }
    #|export function a() { n1({ type: E.B, event: "x", extra: 1 }); }
    #|export function b() { n1({ event: "x" }); }
    #|export function d() { nj({ name: "n", event: "x" }); }
    #|class C { m(): void {} x = 1 }
    #|declare function nc(v: C & { tag: number }): void;
    #|export function okClassMethod() { nc({ m() {}, x: 1, tag: 1 }); }
  assert_eq(issue_lines(src), [
    "function a > call `n1` arg[0].extra: property `extra` does not exist on target type",
    "function b > call `n1` arg[0].type: property `type` is required by `{ type: E; event: string }`",
    "function d > call `nj` arg[0].type: property `type` is required by `{ name: string; type: E; event: string }`",
  ])
}

///|
/// Round three of #312's review, each cell probed against the nightly. A
/// nested scope's declaration only shields the writes made inside the
/// statement that holds it: `{ let x = 0 } x = null` still writes the outer
/// `x` before the throw. An assignment-form or `var` loop head writes the
/// outer binding; only a `let` / `const` head declares one of its own. A
/// `finally` write followed by a `throw` or a `return` does not reach the
/// code after the statement.
test "a nested declaration shields only its own statement's writes" {
  let src =
    #|export function e1() { let x: string | null = "ok"; try { { let x = 0; x = 1; } x = null; throw 0; } catch { x.length; } }
    #|export function e2() { let x: string | null = "ok"; try { for (x of [null]) { throw 0; } } catch { x.length; } }
    #|export function e3() { let x: string | null = "ok"; try { for (const y of [1]) { x = null; } throw 0; } catch { x.length; } }
    #|export function ok1() { let x: string | null = "ok"; try { { let x: string | null = "a"; x = null; } throw 0; } catch { x.length; } }
    #|export function ok2() { let x: string | null = "ok"; try { for (let x of [null]) { throw 0; } } catch { x.length; } }
    #|declare const flag: boolean;
    #|export function f1() { let x: string | null = "ok"; try { } finally { if (flag) { x = null; throw 0; } } return x.length; }
    #|export function f2() { let x: string | null = "ok"; try { } finally { if (flag) { x = null; } } return x.length; }
    #|export function f3() { let x: string | null = "ok"; try { } finally { if (flag) { x = null; return 0; } } return x.length; }
  assert_eq(issue_lines(src), [
    "function e1 > PropAccess `.length`: object is possibly `null`", "function e2 > PropAccess `.length`: object is possibly `null`",
    "function e3 > PropAccess `.length`: object is possibly `null`", "function f2 > PropAccess `.length`: object is possibly `null`",
  ])
}

///|
/// A compound statement every way through which exits is an exit, so a
/// write before it reaches neither the code after a `finally` nor a loop's
/// back edge (#312's review, probed): an `if` / `else` that throws on both
/// sides, and a `break` / `return` pair in a loop body.
test "an if whose branches all exit is an exit" {
  let src =
    #|export function f(flag: boolean, other: boolean) { let x: string | null = "ok"; try {} finally { if (flag) { x = null; if (other) throw 0; else throw 1; } } return x.length; }
    #|export function g(flag: boolean, other: boolean) { let x: string | null = "ok"; try {} finally { if (flag) { x = null; if (other) throw 0; } } return x.length; }
    #|export function w(c: boolean, d: boolean) { let x: string | null = "ok"; while (c) { const n = x.length; x = null; if (d) { break; } else { return n; } } return 0; }
    #|export function w2(c: boolean, d: boolean) { let x: string | null = "ok"; while (c) { const n = x.length; x = null; if (d) { break; } } return 0; }
  assert_eq(issue_lines(src), [
    "function g > PropAccess `.length`: object is possibly `null`", "function w2 > PropAccess `.length`: object is possibly `null`",
  ])
}

///|
/// Every declarator of `const a = 1, b = "x"` binds in the enclosing scope.
/// The parser lowers the list to a block marked `DECL_GROUP_POSITION`, and
/// the checker read only an all-`var` block as a group, so every later read
/// of a `let` or `const` declarator was unchecked (probed: all four `bad`
/// lines are TS2322). A real block's own declarations still go out of scope.
test "a multi-declarator let or const binds every name in its scope" {
  let src =
    #|export {};
    #|const a = 1, b = "x";
    #|const badA: string = a;
    #|export function g() { const h = 1, i = "x"; const badH: string = h; const okI: string = i; let j = 1, k = 2; { let j = "s"; const okJ: string = j; } const okJ2: number = j; return [badH, okI, k, okJ2]; }
    #|export function g2(o: { x: number }) { const { x } = o, y = 2; const badX: string = x; const okY: number = y; return [badX, okY]; }
    #|export function g3() { const t1 = 1, t2 = "t"; return () => { const badT: string = t1; return [badT, t2]; }; }
  assert_eq(issue_lines(src), [
    "function g > binding `badH` init: expected `string` but got `number`", "function g2 > binding `badX` init: expected `string` but got `number`",
    "function g3 > binding `badT` init: expected `string` but got `number`", "top-level > binding `badA` init: expected `string` but got `number`",
  ])
}

///|
/// A constructor's pattern parameter binds every name it declares, as a
/// method's does. The class kept one `(name, type)` pair per parameter, the
/// pattern's first name, so `a` was bound to the whole parameter type and
/// `b` was "cannot find name" (excalidraw's `FileManager` and
/// `RequestError`, probed: tsc reports only `bad`).
test "a constructor's pattern parameter binds every name" {
  let src =
    #|export class A {
    #|  x: number; y: string; z: string[];
    #|  constructor({ a, b }: { a: number; b: string }, [c, ...d]: string[]) { this.x = a; this.y = b; this.z = d; const s: string = c; }
    #|}
    #|export class B {
    #|  constructor({ a, b }: { a: number; b: string } = { a: 1, b: "" }) { const bad: string = a; const ok: string = b; }
    #|}
  assert_eq(issue_lines(src), [
    "function B.constructor > binding `bad` init: expected `string` but got `number`",
  ])
}

///|
/// The false side of `"k" in x` removes only a member that DECLARES `k`
/// (tsc's `isTypePresencePossible`, probed). A member that answers for the
/// key through an index signature may still lack it, so it stays, where it
/// was removed and `c.hasOwnProperty(v)` read off `never` (excalidraw's
/// `isMemberOf`). A member that declares the key beside an index signature
/// is still removed.
test "the false side of in keeps a member that only has an index signature" {
  let src =
    #|type A = { x: number } | { y: string };
    #|export function okRemovesDeclarer(v: A) { if (!("x" in v)) { return v.y; } return 0; }
    #|export function badElseOfDeclarer(v: A) { if ("x" in v) { return 0; } return v.x; }
    #|export function okIndexKept(c: readonly string[] | Record<string, number>, v: string) { return "includes" in c ? 1 : c.hasOwnProperty(v); }
    #|export function badDeclaredWithIndex(c: readonly string[] | { [k: string]: number; includes: number }) { return "includes" in c ? 1 : c.foo; }
    #|interface Dict { [k: string]: string }
    #|export function okInterfaceIndexKept(c: string[] | Dict) { return "map" in c ? 1 : c.anything.length; }
  assert_eq(issue_lines(src), [
    "function badElseOfDeclarer > PropAccess `.x`: property `x` does not exist on `{ y: string }`",
    "function badDeclaredWithIndex > PropAccess `.foo`: property `foo` does not exist on `never`",
    "function badDeclaredWithIndex > PropAccess `.foo`: property `foo` does not exist on `never`",
  ])
}

///|
/// An arrow's or a function expression's rest parameter is `Rest(_)` in its
/// type, as a method's is, so a call through the VALUE takes any count:
/// `const concat = (...b: B[]) => …` took exactly one argument on the graph
/// path (excalidraw's `concatBuffers(a, b)`). A rest parameter against a
/// contextual list compares its element with each formal, and two rest
/// lists compare their arrays (probed: tsc reports only the `bad` lines).
test "an arrow's rest parameter takes any count and compares its element" {
  let src =
    #|const c1 = (...xs: number[]) => xs.length;
    #|export const bad1 = c1("a");
    #|export const ok1 = c1();
    #|const c3 = function (...xs: string[]) { return xs.join(); };
    #|export const ok3 = c3("a", "b");
    #|const take: (f: (...a: number[]) => number) => number = (f) => f(1, 2);
    #|export const ok4 = take(c1);
    #|export const bad4 = take((...xs: string[]) => 1);
    #|type Fn = (a: number, b: number) => number;
    #|export const ok6: Fn = (...a: number[]) => a[0];
    #|export const bad6: Fn = (...a: string[]) => 1;
  assert_eq(issue_lines(src), [
    "top-level > call `c1` arg[0]: expected `number` but got `string`", "top-level > call `take` arg[0] param `xs`: expected `number` but got `string`",
    "top-level > binding `bad6` init param `a`: expected `number` but got `string`",
  ])
}

///|
/// The "generic indexed access" rule (a primitive into `T[P]` over a type
/// parameter) took any `keyof` key as generic, so `typeof KEYS[keyof
/// typeof KEYS]` over an `as const` object, which is a concrete union of
/// its values, rejected `has(KEYS.A)` (excalidraw's `EditorLocalStorage`,
/// probed: tsc accepts it). A `keyof` over an in-scope type parameter is
/// still the generic access.
test "a keyof key over a concrete object is not a generic indexed access" {
  let src =
    #|const LOCAL = { A: "a-key", B: "b-key" } as const;
    #|class S { static has(key: typeof LOCAL[keyof typeof LOCAL]) { return !!key; } }
    #|export const ok = S.has(LOCAL.B);
    #|export function g<T>(o: T, s: string) { const y: T[keyof T] = s; return [o, y]; }
  assert_eq(issue_lines(src), [
    "function g > binding `y` init: `string` is not assignable to the generic indexed access `T[keyof T]`",
  ])
}

///|
/// An unannotated callback parameter takes its type from the contextual
/// list with the rest position read: a rest parameter collects the formals
/// from its position on, and a plain one on the contextual rest takes its
/// element. A variadic tuple pattern binds its rest positions to the rest's
/// element. Each had bound the raw `Rest(_)` marker (#314's review, probed:
/// tsc reports exactly the four `bad` lines; main reported the four `ok`
/// ones too).
test "a contextual rest parameter and a variadic tuple pattern bind element types" {
  let src =
    #|declare function takeRest(cb: (...xs: number[]) => void): void;
    #|declare function takePair(cb: (x: string, y: number) => void): void;
    #|export function okRestFromRest() { takeRest((...a) => { const v: number[] = a; return v; }); }
    #|export function badRestFromRest() { takeRest((...a) => { const v: string[] = a; return v; }); }
    #|export function okPlainFromRest() { takeRest((a, b) => { const n: number = a + b; return n; }); }
    #|export function badPlainFromRest() { takeRest((a) => { const s: string = a; return s; }); }
    #|export function okRestFromPair() { takePair((...a) => { const v: [string, number] = a; return v; }); }
    #|export function badRestFromPair() { takePair((...a) => { const v: [number, number] = a; return v; }); }
    #|export function okTupleRest([a, b]: [number, ...string[]]) { const s: string = b; return [a, s]; }
    #|export function badTupleRest([a, b]: [number, ...string[]]) { const n: number = b; return [a, n]; }
    #|export function okTupleRestTail([a, b, c]: [number, ...string[]]) { const s: string = c; return [a, b, s]; }
    #|declare function f5<T extends any[], U>(f: (...args: T) => U): (...args: T) => U;
    #|export const okAnnotatedOnGenericRest = f5((x: number, y) => 42);
    #|export function okAnnotatedOnRest() { takeRest((a: number, b: number) => {}); }
    #|export function badAnnotatedOnRest() { takeRest((a: string) => {}); }
  assert_eq(issue_lines(src), [
    "function badRestFromRest > binding `v` init: expected `string[]` but got `number[]`",
    "function badPlainFromRest > binding `s` init: expected `string` but got `number`",
    "function badRestFromPair > binding `v` init: expected `[number, number]` but got `[string, number]`",
    "function badTupleRest > binding `n` init: expected `number` but got `string`",
    "function badAnnotatedOnRest > call `takeRest` arg[0] param `a`: expected `number` but got `string`",
  ])
}

///|
/// An unannotated static factory narrows an assignment by its whole body,
/// not only by a single `return new N(v)`: `const instance = new N(v); …;
/// return instance` is an `N` (univer's `NumberValueObject.create`, behind
/// `if (v == null || v.isNull()) { v = NumberValueObject.create(0) }`). A
/// factory that may return `undefined`, or fall off its end, still leaves
/// the binding possibly `undefined` (probed: tsc reports exactly `h` and `k`).
test "a static factory that returns a local narrows an assignment" {
  let src =
    #|type Nullable<T> = T | null | undefined | void;
    #|class Base { isNull() { return false; } isBoolean() { return false; } }
    #|class N extends Base { static create(v: number, p: string = "") { const i = new N(v); if (p) { i.p = p; } return i; } p = ""; constructor(public v: number) { super(); } }
    #|class M extends Base { static mk(v: number) { const i = v > 0 ? new M() : undefined; return i; } static mk2(v: number) { if (v > 0) { return new M(); } } }
    #|export function f(x: Nullable<Base>) { let o = x; if (o == null || o.isNull()) { o = N.create(0); } return o.isBoolean(); }
    #|export function h(x: Nullable<Base>) { let o = x; if (o == null) { o = M.mk(0); } return o.isBoolean(); }
    #|export function k(x: Nullable<Base>) { let o = x; if (o == null) { o = M.mk2(0); } return o.isBoolean(); }
  assert_eq(issue_lines(src), [
    "function h > call `isBoolean`: object is possibly `undefined`", "function k > call `isBoolean`: object is possibly `undefined`",
  ])
}

///|
/// The rest element of an array pattern over a variadic tuple takes tsc's
/// slice: the tail as written from at or before the tuple's rest, an array
/// of the element types from the rest on past it. Slicing the stored items
/// past the rest left `[]`, so `[h, f, ...t]` then `const [n] = t` read `n`
/// as `undefined` (#314's review, probed on the nightly).
test "a variadic tuple pattern's rest element keeps the tuple's slice" {
  let src =
    #|export function okTwoHead([h, f, ...t]: [number, ...string[]]) { const x: string[] = t; const [n] = t; const v: string = n; return [h, f, x, v]; }
    #|export function badTwoHead([h, f, ...t]: [number, ...string[]]) { const x: number[] = t; return [h, f, x]; }
    #|export function badElementOfRemainder([h, f, ...t]: [number, ...string[]]) { const [n] = t; const v: number = n; return [h, f, v]; }
    #|export function okOneHead([h, ...t]: [number, ...string[]]) { const x: string[] = t; return [h, x]; }
    #|export function okWhole([...t]: [number, ...string[]]) { const x: [number, ...string[]] = t; return x; }
    #|export function okPastTail([a, b, c, ...t]: [number, ...string[], boolean]) { const x: (string | boolean)[] = t; return [a, b, c, x]; }
    #|export function badPastTail([a, b, c, ...t]: [number, ...string[], boolean]) { const x: string[] = t; return [a, b, c, x]; }
    #|export function okBeforeTail([a, ...t]: [number, ...string[], boolean]) { const x: [...string[], boolean] = t; return [a, x]; }
    #|export function okCallback() { const cb: (...xs: [number, ...string[]]) => void = (...[head, first, ...tail]) => { const [next] = tail; const v: string = next; void [head, first, v]; }; return cb; }
    #|export function badCallback() { const cb: (...xs: [number, ...string[]]) => void = (...[head, first, ...tail]) => { const x: number[] = tail; void [head, first, x]; }; return cb; }
  assert_eq(issue_lines(src), [
    "function badTwoHead > binding `x` init: expected `number[]` but got `string[]`",
    "function badElementOfRemainder > binding `v` init: expected `number` but got `string`",
    "function badPastTail > binding `x` init: expected `string[]` but got `(string | boolean)[]`",
    "function badCallback > binding `x` init: expected `number[]` but got `string[]`",
  ])
}

///|
/// Assigning a never-nullish value to a property path removes the nullish
/// members of the field's declared type, also when that type is an alias:
/// `Nullable<number>` read as admitting no nullish value, so
/// `this._next = 3` narrowed nothing (univer's
/// `DocumentSkeleton._externalLayoutProgress`).
/// And an unannotated instance method is read from its body for that
/// question, at the path and at a binding, as a static factory already was
/// (probed: tsc reports exactly the four `bad` lines).
test "an assignment narrows a nullable-alias path, and reads an unannotated method's body" {
  let src =
    #|type Nullable<T> = T | null | undefined | void;
    #|function mapClass(c: number) { return c + 1; }
    #|export class L {
    #|  private _next: Nullable<number> = null;
    #|  private _nextChar() { const k = 1; return mapClass(k); }
    #|  private _maybe() { if (Math.random() > 0.5) { return 1; } return undefined; }
    #|  private _anyRet(): any { return 1; }
    #|  private _empty() { }
    #|  okPath() { this._next = this._nextChar(); return mapClass(this._next); }
    #|  okBinding() { let o: Nullable<number> = null; o = this._nextChar(); return mapClass(o); }
    #|  okLiteralOnAlias() { this._next = 3; return mapClass(this._next); }
    #|  badPathMaybe() { this._next = this._maybe(); return mapClass(this._next); }
    #|  badAnyRet() { this._next = this._anyRet(); return mapClass(this._next); }
    #|  badEmpty() { this._next = this._empty(); return mapClass(this._next); }
    #|  badUnassigned() { return mapClass(this._next); }
    #|}
  assert_eq(issue_lines(src), [
    "function L.badPathMaybe > call `mapClass` arg[0]: type `number | null | undefined | void` is not assignable to type `number`",
    "function L.badAnyRet > call `mapClass` arg[0]: type `number | null | undefined | void` is not assignable to type `number`",
    "function L.badEmpty > call `mapClass` arg[0]: type `number | null | undefined | void` is not assignable to type `number`",
    "function L.badUnassigned > call `mapClass` arg[0]: type `number | null | undefined | void` is not assignable to type `number`",
  ])
}

///|
/// An enum member is assignable where its enum, or the member itself, is expected: it
/// read as its folded value, which an object literal's member and a property
/// write widened to `string` / `number` (univer's `DateSystem`, `Direction`;
/// probed: tsc reports exactly the three `bad` lines).
test "an enum member fits a target that expects its enum or the member (strenum)" {
  let src =
    #|export enum DateSystem { AUTO = "auto", D1900 = "1900" }
    #|export interface Cfg { dateSystem?: DateSystem }
    #|export const ok1: Cfg = { dateSystem: DateSystem.AUTO };
    #|export function ok2(c: Cfg) { c.dateSystem = DateSystem.D1900; return c; }
    #|export function ok3(f: (d?: DateSystem) => void) { f(DateSystem.AUTO); }
    #|export function ok4(): Cfg { return { dateSystem: DateSystem.AUTO }; }
    #|export enum Direction { UP, DOWN, LEFT, RIGHT }
    #|export interface Ins { direction: Direction.LEFT | Direction.RIGHT }
    #|export const ok5: Ins = { direction: Direction.LEFT };
  assert_eq(issue_lines(src), [])
}

///|
/// An enum member is assignable where its enum, or the member itself, is expected: it
/// read as its folded value, which an object literal's member and a property
/// write widened to `string` / `number` (univer's `DateSystem`, `Direction`;
/// probed: tsc reports exactly the three `bad` lines).
test "an enum member fits a target that expects its enum or the member (strenum2)" {
  let src =
    #|export enum DateSystem { AUTO = "auto", D1900 = "1900" }
    #|export enum Other { AUTO = "auto" }
    #|export interface Cfg { dateSystem?: DateSystem }
    #|export enum Direction { UP, DOWN, LEFT, RIGHT }
    #|export interface Ins { direction: Direction.LEFT | Direction.RIGHT }
    #|export const badOtherEnum: Cfg = { dateSystem: Other.AUTO };
    #|export const badMemberOutsideUnion: Ins = { direction: Direction.UP };
    #|export const badPlainLiteral: Cfg = { dateSystem: "auto" };
    #|export function okShadowedName(DateSystem: { AUTO: DateSystem }) { const c: Cfg = { dateSystem: DateSystem.AUTO }; return c; }
  assert_eq(issue_lines(src), [
    "top-level > binding `badOtherEnum` init.dateSystem: expected `DateSystem | undefined` but got `string`",
    "top-level > binding `badMemberOutsideUnion` init.direction: expected `Direction.LEFT | Direction.RIGHT` but got `number`",
    "top-level > binding `badPlainLiteral` init.dateSystem: expected `DateSystem | undefined` but got `string`",
  ])
}

///|
/// A numeric enum accepts any `number` as the member of an object value that
/// is not a literal, as it already did at the top level (univer's
/// `Rectangle.union`; probed: tsc reports exactly the `bad` lines).
test "a numeric enum member of an object value accepts a number (numenum)" {
  let src =
    #|export enum E { A, B }
    #|declare const n: number;
    #|export const ok1: E = n;
    #|export const ok2: { r?: E } = { r: n };
    #|const x = { r: n };
    #|export const ok3: { r?: E } = x;
    #|const y = { r: n };
    #|export const ok4: { r: E } = y;
    #|export interface I { r?: E }
    #|const z = { r: E.B };
    #|export const ok5: I = z;
    #|export const ok6: I = { r: E.A };
  assert_eq(issue_lines(src), [])
}

///|
/// A numeric enum accepts any `number` as the member of an object value that
/// is not a literal, as it already did at the top level (univer's
/// `Rectangle.union`; probed: tsc reports exactly the `bad` lines).
test "a numeric enum member of an object value accepts a number (numenum2)" {
  let src =
    #|export enum E { A, B }
    #|export enum S { X = "x", Y = "y" }
    #|declare const n: number;
    #|const sv = { r: "x" };
    #|export const badStringIntoNumericEnum: { r?: E } = sv;
    #|const nv = { k: n };
    #|export const badNumberIntoStringEnum: { k?: S } = nv;
    #|const bv = { r: true };
    #|export const badBooleanIntoNumericEnum: { r?: E } = bv;
    #|const okv = { r: n };
    #|export const okNumberIntoNumericEnum: { r?: E } = okv;
  assert_eq(issue_lines(src), [
    "top-level > binding `badStringIntoNumericEnum` init: expected `{ r: E | undefined }` but got `{ r: string }`",
    "top-level > binding `badNumberIntoStringEnum` init: expected `{ k: S | undefined }` but got `{ k: number }`",
    "top-level > binding `badBooleanIntoNumericEnum` init: expected `{ r: E | undefined }` but got `{ r: boolean }`",
  ])
}

///|
/// A numeric enum accepts any `number` as the member of an object value that
/// is not a literal, as it already did at the top level (univer's
/// `Rectangle.union`; probed: tsc reports exactly the `bad` lines).
test "a numeric enum member of an object value accepts a number (reduceenum)" {
  let src =
    #|export enum RANGE_TYPE { NORMAL, ROW, COLUMN }
    #|export interface IRange { startRow: number; endRow: number; rangeType?: RANGE_TYPE }
    #|export function okUnion(...ranges: IRange[]): IRange {
    #|  return ranges.reduce((acc, current) => ({ startRow: Math.min(acc.startRow, current.startRow), endRow: Math.max(acc.endRow, current.endRow), rangeType: RANGE_TYPE.NORMAL }), ranges[0]);
    #|}
    #|export function okDirect(): IRange { return { startRow: 1, endRow: 2, rangeType: RANGE_TYPE.ROW }; }
    #|const lit = { startRow: 1, endRow: 2, rangeType: RANGE_TYPE.ROW };
    #|export const okWidened: IRange = lit;
    #|export enum S { A = "a", B = "b" }
    #|export interface IS { k?: S }
    #|export const badStr: IS = { k: "a" as string };
  assert_eq(issue_lines(src), [
    "top-level > binding `badStr` init.k: expected `S | undefined` but got `string`",
  ])
}

///|
/// An unannotated field, a `let` and an assignment given an enum member hold
/// the enum, not the member's folded value (univer's `BaseReferenceObject`,
/// `AutoFillService`; probed: tsc reports exactly `badField` and `badMaybe`;
/// `badField` is a MISS, since an enum-typed value abstains).
test "an enum member gives a field, a let and an assigned binding its enum (fieldenum)" {
  let src =
    #|export enum DS { D1900 = "1900", D1904 = "1904" }
    #|export enum N { A, B }
    #|export class C {
    #|  private _d = DS.D1900;
    #|  private _n = N.A;
    #|  take(d?: DS) { return d; }
    #|  takeN(n: N) { return n; }
    #|  okField() { return this.take(this._d); }
    #|  okFieldN() { return this.takeN(this._n); }
    #|  okReassign() { this._d = DS.D1904; this._n = N.B; }
    #|  badField(): number { return this._d; }
    #|}
  assert_eq(issue_lines(src), [])
}

///|
/// An unannotated field, a `let` and an assignment given an enum member hold
/// the enum, not the member's folded value (univer's `BaseReferenceObject`,
/// `AutoFillService`; probed: tsc reports exactly `badField` and `badMaybe`;
/// `badField` is a MISS, since an enum-typed value abstains).
test "an enum member gives a field, a let and an assigned binding its enum (dirnarrow2)" {
  let src =
    #|type Nullable<T> = T | null | undefined | void;
    #|export enum Direction { UP, DOWN }
    #|declare function take(d: Direction): void;
    #|export function okOne() { let d: Nullable<Direction> = null; d = Direction.UP; take(d); }
    #|export function okBranches(a: number) { let d: Nullable<Direction> = null; if (a < 0) { d = Direction.UP; } else { d = Direction.DOWN; } take(d); }
    #|export function okPlainUnion(a: number) { let d: Direction | null = null; if (a < 0) { d = Direction.UP; } else { d = Direction.DOWN; } take(d); }
    #|export function okReturnElse(a: number) { let d: Direction | null = null; if (a < 0) { d = Direction.UP; } else { return; } take(d); }
  assert_eq(issue_lines(src), [])
}

///|
/// An unannotated field, a `let` and an assignment given an enum member hold
/// the enum, not the member's folded value (univer's `BaseReferenceObject`,
/// `AutoFillService`; probed: tsc reports exactly `badField` and `badMaybe`;
/// `badField` is a MISS, since an enum-typed value abstains).
test "an enum member gives a field, a let and an assigned binding its enum (dirnarrow)" {
  let src =
    #|type Nullable<T> = T | null | undefined | void;
    #|export enum Direction { UP, DOWN, LEFT, RIGHT }
    #|export class Svc {
    #|  private _d: Direction = Direction.DOWN;
    #|  set direction(d: Direction) { this._d = d; }
    #|  get direction() { return this._d; }
    #|  okNarrow(a: number) {
    #|    let direction: Nullable<Direction> = null;
    #|    if (a < 0) { direction = Direction.UP; } else if (a > 0) { direction = Direction.DOWN; } else { return false; }
    #|    this.direction = direction;
    #|    return true;
    #|  }
    #|  badMaybe(a: number) {
    #|    let direction: Nullable<Direction> = null;
    #|    if (a < 0) { direction = Direction.UP; }
    #|    this.direction = direction;
    #|  }
    #|}
  assert_eq(issue_lines(src), [
    "function Svc.badMaybe > assign `.direction`: type `Direction | null | undefined | void` is not assignable to type `Direction`",
  ])
}

///|
/// When one branch of an `if` always exits, the other branch's assignments
/// reach the code after the `if`, and a tuple-alias binding keeps its alias
/// (excalidraw's `calculateBounds`; probed: tsc reports exactly the `bad`
/// lines).
test "an if whose sibling branch exits carries the other branch's assignments (ifjoin)" {
  let src =
    #|declare function takeS(s: string): void;
    #|export function okString(a: number) { let s: string | null = null; if (a < 0) { s = "x"; } else { return; } takeS(s); }
    #|export function okStringElseIf(a: number) { let s: string | null = null; if (a < 0) { s = "x"; } else if (a > 0) { s = "y"; } else { return; } takeS(s); }
    #|export enum Direction { UP, DOWN }
    #|declare function take(d: Direction): void;
    #|export function okEnumVar(a: number, v: Direction) { let d: Direction | null = null; if (a < 0) { d = v; } else { return; } take(d); }
    #|export function okEnumMember(a: number) { let d: Direction | null = null; if (a < 0) { d = Direction.UP; } else { return; } take(d); }
  assert_eq(issue_lines(src), [])
}

///|
/// When one branch of an `if` always exits, the other branch's assignments
/// reach the code after the `if`, and a tuple-alias binding keeps its alias
/// (excalidraw's `calculateBounds`; probed: tsc reports exactly the `bad`
/// lines).
test "an if whose sibling branch exits carries the other branch's assignments (ifjoin2)" {
  let src =
    #|declare function takeS(s: string): void;
    #|export function okThenAssigns(a: number) { let s: string | null = null; if (a < 0) { s = "x"; } else { return; } takeS(s); }
    #|export function okElseAssigns(a: number) { let s: string | null = null; if (a < 0) { return; } else { s = "y"; } takeS(s); }
    #|export function okElseIfChain(a: number) { let s: string | null = null; if (a < 0) { s = "x"; } else if (a > 0) { s = "y"; } else { return; } takeS(s); }
    #|export function badAssignsNull(a: number) { let s: string | null = "z"; if (a < 0) { s = null; } else { return; } takeS(s); }
    #|export function badNestedMaybe(a: number, b: boolean) { let s: string | null = null; if (a < 0) { if (b) { s = "x"; } } else { return; } takeS(s); }
    #|export function badShadowInBranch(a: number) { let s: string | null = null; if (a < 0) { let s = "inner"; takeS(s); } else { return; } takeS(s); }
    #|export function okExitsThrow(a: number) { let s: string | null = null; if (a < 0) { s = "x"; } else { throw new Error("e"); } takeS(s); }
  assert_eq(issue_lines(src), [
    "function badAssignsNull > call `takeS` arg[0]: expected `string` but got `null`",
    "function badNestedMaybe > call `takeS` arg[0]: type `\"x\" (string) | string | null` is not assignable to type `string`",
    "function badShadowInBranch > call `takeS` arg[0]: type `string | null` is not assignable to type `string`",
  ])
}

///|
/// When one branch of an `if` always exits, the other branch's assignments
/// reach the code after the `if`, and a tuple-alias binding keeps its alias
/// (excalidraw's `calculateBounds`; probed: tsc reports exactly the `bad`
/// lines).
test "an if whose sibling branch exits carries the other branch's assignments (tuplealias)" {
  let src =
    #|type Bounds = [number, number, number, number];
    #|export function okBoth(c: boolean): Bounds { let b: Bounds; if (c) { b = [1, 2, 3, 4]; } else { b = [5, 6, 7, 8]; } return b; }
    #|export function okExitFirst(c: number): Bounds { let b: Bounds; if (c < 0) { return [0, 0, 0, 0]; } else if (c > 0) { b = [1, 2, 3, 4]; } else { b = [5, 6, 7, 8]; } return b; }
    #|export function okDirectTuple(c: boolean): [number, number] { let b: [number, number]; if (c) { b = [1, 2]; } else { b = [3, 4]; } return b; }
    #|export function badWrongLength(c: boolean): Bounds { let b: Bounds; if (c) { b = [1, 2, 3]; } else { b = [5, 6, 7, 8]; } return b; }
  assert_eq(issue_lines(src), [
    "function badWrongLength > assign `b`: expected tuple of 4 element(s), got 3",
  ])
}

///|
/// An alias to a lib interface this checker has no member table for abstains
/// on member existence, as the bare name does (excalidraw's
/// `event.nativeEvent`, through `@types/react`'s `NativeKeyboardEvent`).
test "an alias to an untabulated lib interface abstains like the bare name (libalias)" {
  let src =
    #|type NativeKE = KeyboardEvent;
    #|declare const e: NativeKE;
    #|export function ok() { e.stopImmediatePropagation(); return e.isComposing; }
    #|declare const d: KeyboardEvent;
    #|export function okDirect() { d.stopImmediatePropagation(); return d.isComposing; }
  assert_eq(issue_lines(src), [])
}

///|
/// An alias to a lib interface this checker has no member table for abstains
/// on member existence, as the bare name does (excalidraw's
/// `event.nativeEvent`, through `@types/react`'s `NativeKeyboardEvent`).
test "an alias to an untabulated lib interface abstains like the bare name (nsshadow3)" {
  let src =
    #|type NativeKE = KeyboardEvent;
    #|declare namespace R { interface KeyboardEvent { key: string; nativeEvent: NativeKE } }
    #|declare const k: KeyboardEvent;
    #|export function ok() { k.stopImmediatePropagation(); return k.isComposing; }
    #|export function okKey(e: R.KeyboardEvent) { return e.key; }
  assert_eq(issue_lines(src), [])
}

///|
/// An enum member written in an object literal has the enum-LITERAL type
/// `E.M`, so a callback's `({ tag: S.X })` fits a target that names the
/// member, a union of members, or a union discriminated by it (probed: tsc
/// accepts every `ok` line and reports exactly the `bad` ones). It used to
/// read as the member's VALUE, `"x"` or `number`, which is neither.
test "an enum member in a written object literal is its enum-literal type (enumlit)" {
  let src =
    #|enum E { A, B }
    #|enum S { X = "x", Y = "y" }
    #|interface I { kind: E; n: number }
    #|interface J { tag: S; n: number }
    #|interface IA { kind: E.A }
    #|interface JX { tag: S.X }
    #|interface Cx { tag: S.X; a: number }
    #|interface Cy { tag: S.Y; b: number }
    #|declare const xs: number[];
    #|export const ok1: I[] = xs.map((n) => ({ kind: E.A, n }));
    #|export const ok2: J[] = xs.map((n) => ({ tag: S.X, n }));
    #|export const ok4: J[] = xs.map((n) => { if (n) { return { tag: S.X, n }; } return { tag: S.Y, n }; });
    #|export const ok5: IA[] = xs.map(() => ({ kind: E.A }));
    #|export const ok6: JX[] = xs.map(() => ({ tag: S.X }));
    #|export const okUnion: { tag: S.X | S.Y }[] = xs.map(() => ({ tag: S.X }));
    #|export const okDu: (Cx | Cy)[] = xs.map(() => ({ tag: S.X, a: 1 }));
    #|export const badOther: { tag: S.Y }[] = xs.map(() => ({ tag: S.X }));
  assert_eq(issue_lines(src), [
    "top-level > binding `badOther` init: expected `{ tag: S.Y }[]` but got `{ tag: S.X }[]`",
  ])
}

///|
/// An enum and an enum-literal type are assignable to what their VALUES
/// are: `S` to `string`, `S.X` to `"x"`, `E.A` to `0` (auto-numbered) and
/// to `number` (tsc's `isSimpleTypeRelatedTo`; probed). Once a binding
/// widened `S.X` to `S`, `{ tag: S }` against `{ tag: string }` was
/// reported.
test "an enum relates to the values its members hold (enumvalue)" {
  let src =
    #|enum E { A, B }
    #|enum S { X = "x", Y = "y" }
    #|declare const xs: number[];
    #|const o1 = { kind: E.A };
    #|export const okNum: { kind: number } = o1;
    #|const o2 = { tag: S.X };
    #|export const okStr: { tag: string } = o2;
    #|export const okStrU: { tag: string | number } = o2;
    #|export const okCbNum: { kind: number }[] = xs.map(() => ({ kind: E.A }));
    #|export const okCbStr: { tag: string }[] = xs.map(() => ({ tag: S.X }));
    #|export const okCbZero: { kind: 0 }[] = xs.map(() => ({ kind: E.A }));
    #|export const okCbLitX: { tag: "x" }[] = xs.map(() => ({ tag: S.X }));
    #|export const badCbOne: { kind: 1 }[] = xs.map(() => ({ kind: E.A }));
    #|export const badCbLitY: { tag: "y" }[] = xs.map(() => ({ tag: S.X }));
  assert_eq(issue_lines(src), [
    "top-level > binding `badCbOne` init: expected `{ kind: 1 }[]` but got `{ kind: E.A }[]`",
    "top-level > binding `badCbLitY` init: expected `{ tag: \"y\" (string) }[]` but got `{ tag: S.X }[]`",
  ])
}

///|
/// A binding widens an enum member to its enum only where the member was
/// WRITTEN: an object or array literal, a call taking an inline callback,
/// or an unannotated function's inferred return. A parameter `t: T.A | T.B`
/// held in `{ t }` and a declared `k(): { tag: S.X }` keep the declared
/// type (probed: tsc accepts every `ok` line and reports `bad`).
test "an enum member widens only where it was written (freshenum)" {
  let src =
    #|enum S { X = "x", Y = "y" }
    #|declare const xs: number[];
    #|const arr = xs.map(() => ({ tag: S.X, n: 1 }));
    #|arr.push({ tag: S.Y, n: 2 });
    #|export function okMutate() { arr[0].tag = S.Y; }
    #|export function okRet() { return { tag: S.X }; }
    #|export function okRetMutate() { const r = okRet(); r.tag = S.Y; }
    #|const nested = { inner: xs.map(() => ({ tag: S.X })) };
    #|nested.inner.push({ tag: S.Y });
    #|export function okParam(t: S.X) { const x = { t }; const y: { t: S.X } = x; return y; }
    #|declare function h(): { tag: S.X }[];
    #|const b = h();
    #|export const okDeclaredArr: { tag: S.X }[] = b;
    #|declare function k(): { tag: S.X };
    #|const c = k();
    #|export const okDeclaredObj: { tag: S.X } = c;
    #|const arr8 = xs.map(() => ({ tag: S.X }));
    #|export const badWidened: { tag: S.X }[] = arr8;
    #|const r9 = okRet();
    #|export const badInferredReturnWidened: { tag: S.X } = r9;
    #|export const badInferredReturnCall: { tag: S.X } = okRet();
  assert_eq(issue_lines(src), [
    "top-level > binding `badWidened` init: expected `{ tag: S.X }[]` but got `{ tag: S }[]`",
    "top-level > binding `badInferredReturnWidened` init: expected `{ tag: S.X }` but got `{ tag: S }`",
    "top-level > binding `badInferredReturnCall` init: expected `{ tag: S.X }` but got `{ tag: S }`",
  ])
}

///|
/// tsc relates an object to a discriminated union by splitting a
/// discriminant of union or enum type into its members (TS 3.5): `{ t: T;
/// len: number }` fits `Retain | Insert | Del` when each member of `T` in
/// place of `t` fits some arm — so `{ t: T.RETAIN, len: 1 }` alone does
/// NOT, the `T.INSERT` arm requiring `body` (univer's text-x actions;
/// probed: tsc accepts the `ok` lines and reports the `bad` ones).
test "an enum discriminant splits over a discriminated union (split)" {
  let src =
    #|export enum T { RETAIN = "r", INSERT = "i", DELETE = "d" }
    #|interface Retain { t: T.RETAIN; len: number }
    #|interface Insert { t: T.INSERT; len: number; body: { dataStream: string } }
    #|interface Del { t: T.DELETE; len: number }
    #|type Action = Retain | Insert | Del;
    #|type Small = Retain | Del;
    #|declare function apply(a: Action[]): void;
    #|declare function small(x: Small): void;
    #|export function okArrayWithBody() { const actions = [{ t: T.INSERT, len: 1, body: { dataStream: "h" } }]; apply(actions); }
    #|export function badArrayMissesInsertBody() { const actions = [{ t: T.RETAIN, len: 1 }]; apply(actions); }
    #|export function okUnionTyped(t: T.RETAIN | T.DELETE) { const x = { t, len: 1 }; small(x); }
    #|export function badTooWide(t: T) { const x = { t, len: 1 }; small(x); }
    #|export function badLetEnum() { let a = { t: T.RETAIN, len: 1 }; small(a); }
    #|export function badWrongLen() { const actions = [{ t: T.RETAIN, len: "1" }]; apply(actions); }
    #|export enum K { A, B }
    #|export interface KA { k: K.A; a: number }
    #|export interface KB { k: K.B; a: number }
    #|declare function kk(x: KA | KB): void;
    #|export function okNumeric() { const x = { k: K.A, a: 1 }; kk(x); }
  assert_eq(issue_lines(src), [
    "function badArrayMissesInsertBody > call `apply` arg[0]: expected `Action[]` but got `{ t: T; len: number }[]`",
    "function badTooWide > call `small` arg[0]: expected `Small` but got `{ t: T; len: number }`",
    "function badLetEnum > call `small` arg[0]: expected `Small` but got `{ t: T; len: number }`",
    "function badWrongLen > call `apply` arg[0]: expected `Action[]` but got `{ t: T; len: string }[]`",
  ])
}

///|
/// An array member relates element-wise inside an object: `const f = { xs:
/// [{ a: 1 }] }` assigned to `{ xs: A[] }`, `A` an interface, was reported
/// because nothing in the member relation asked about arrays (univer's
/// `IPermissionPoint.actions`; probed: tsc accepts all but `bad`).
test "an array member of an object relates element-wise (nestedarr)" {
  let src =
    #|interface A { a: number }
    #|type TA = { a: number }
    #|interface K { action?: number | undefined; allowed?: boolean | undefined }
    #|interface H { xs: A[] }
    #|const f = { xs: [{ a: 1 }] };
    #|export const okIface: { xs: A[] } = f;
    #|export const okAlias: { xs: TA[] } = f;
    #|export const okNamed: H = f;
    #|const e5: { action: number; allowed: boolean }[] = [];
    #|const b5 = { actions: e5 };
    #|export const okOptional: { actions: K[] } = b5;
    #|const g = { xs: [{ a: "1" }] };
    #|export const badElem: { xs: A[] } = g;
  assert_eq(issue_lines(src), [
    "top-level > binding `badElem` init: expected `{ xs: A[] }` but got `{ xs: { a: string }[] }`",
  ])
}

///|
/// A numeric literal is assignable to a numeric enum only when a member
/// holds that value (TS 5.0); `number` itself, and an enum with a member
/// whose value is not known statically, accept any (#315's review; probed:
/// tsc reports only `bad`).
test "a numeric literal fits a numeric enum only when a member holds it (enumlit2)" {
  let src =
    #|enum E { A = 0, B = 1 }
    #|enum C { A = 0, B = f() }
    #|declare function f(): number;
    #|declare const o1: { r: 123 };
    #|export const badLiteralNoMember: { r: E } = o1;
    #|declare const o2: { r: 1 };
    #|export const okLiteralMember: { r: E } = o2;
    #|declare const o3: { r: number };
    #|export const okBroadNumber: { r: E } = o3;
    #|declare const o4: { r: 7 };
    #|export const okComputedMemberMayHold: { r: C } = o4;
  assert_eq(issue_lines(src), [
    "top-level > binding `badLiteralNoMember` init: expected `{ r: E }` but got `{ r: 123 }`",
  ])
}

///|
/// After an `if` whose other branch exits, a binding takes the continuing
/// branch's exit type even when it equals the one before the `if` — the
/// condition's narrowing is still installed — and a property path that
/// branch narrowed reaches the code after it (#315's review; probed: tsc
/// reports the two `bad` lines and accepts `okPathCarried`).
test "an exiting sibling carries the continuing branch's exit state (ifjoin3)" {
  let src =
    #|declare function takeS(s: string): void;
    #|export function badParams(x: string | null, y: string | null) { if (x !== null) { x = y; } else { return; } takeS(x); }
    #|export function badParamsTruthy(x: string | null, y: string | null) { if (x) { x = y; } else { return; } takeS(x); }
    #|export function okPathCarried(flag: boolean) { const o: { p: string | null } = { p: null }; if (flag) { o.p = ""; } else { return; } takeS(o.p); }
  assert_eq(issue_lines(src), [
    "function badParams > call `takeS` arg[0]: type `string | null` is not assignable to type `string`",
    "function badParamsTruthy > call `takeS` arg[0]: type `string | null` is not assignable to type `string`",
  ])
}

///|
/// A return inside a nested scope that re-declares a name is not read
/// through the outer binding of that name: a static factory whose nested
/// `const value = null; return value` shadows the parameter keeps `null`,
/// so a field it is assigned to stays nullable (#315's review; probed: tsc
/// reports `H.set`).
test "a shadowing nested declaration declines a factory's inferred return (shadowret)" {
  let src =
    #|declare function takeS(s: string): void;
    #|export class K { static make(value: string, flag: boolean) { if (flag) { const value = null; return value; } return value; } }
    #|export class H { p: string | null = null; set(v: string) { this.p = K.make(v, true); takeS(this.p); } }
    #|export class K2 { static make(value: string) { if (value) { const other = 1; return value + other; } return value; } }
    #|export class H2 { p: string | null = null; set(v: string) { this.p = K2.make(v); takeS(this.p); } }
  assert_eq(issue_lines(src), [
    "function H.set > call `takeS` arg[0]: type `string | null` is not assignable to type `string`",
  ])
}

///|
/// A binding widens only the enum members its initializer WROTE: a call
/// to a declared `load(cb): { tag: E.A }[]` keeps `E.A` although it takes
/// a callback, while what an inline `map` callback returns widens (#315's
/// review; probed: tsc accepts both `ok` lines).
test "a declared enum member in a call result keeps its member type (enumfresh2)" {
  let src =
    #|enum E { A = "a", B = "b" }
    #|declare function load(cb: () => void): { tag: E.A }[];
    #|const rows = load(() => {});
    #|export const okDeclaredKept: { tag: E.A }[] = rows;
    #|declare const xs: number[];
    #|const mapped = xs.map(() => ({ tag: E.A }));
    #|export function okPushOther() { mapped.push({ tag: E.B }); }
    #|export function okReturnedLoad() { return load(() => {}); }
    #|export const okReturnedKept: { tag: E.A }[] = okReturnedLoad();
    #|declare function load2(cb: () => { tag: E }): { tag: E.A }[];
    #|const rows2 = load2(() => ({ tag: E.B }));
    #|export const okDeclaredKeptBesideAWrite: { tag: E.A }[] = rows2;
  assert_eq(issue_lines(src), [])
}

///|
/// An array literal's key follows each item's FINAL writer: a spread after
/// an enum write replaces it and keeps the declared type, an enum write
/// after a spread widens to the enum (#315's review; probed: tsc reports
/// the duplicate key on line 3 and `badEnumWinsWidened` only).
test "an array literal's enum key follows the item's final writer (enumspread)" {
  let src =
    #|enum E { A = "a", B = "b" }
    #|declare const raw: { tag: "raw" };
    #|const xs = [{ tag: E.A, ...raw }];
    #|export const okSpreadWins: { tag: "raw" }[] = xs;
    #|const ys = [{ ...raw, tag: E.A }];
    #|export const badEnumWinsWidened: { tag: E.A }[] = ys;
  assert_eq(issue_lines(src), [
    "top-level > object literal `tag`: `tag` is specified more than once, so this usage will be overwritten by the spread",
    "top-level > binding `badEnumWinsWidened` init: expected `{ tag: E.A }[]` but got `{ tag: E }[]`",
  ])
}

///|
/// A condition narrowing on a property path is not restored after an `if`
/// whose continuing branch forgot it: `o = replacement` drops `o.p`. A
/// branch that only reads the path keeps it (#315's review; probed: tsc
/// reports `badDropped` only).
test "an exiting sibling does not restore a path the branch forgot (ifjoin4)" {
  let src =
    #|declare function takeString(s: string): void;
    #|interface O { p: string | null }
    #|export function badDropped(o: O, replacement: O) { if (o.p !== null) { o = replacement; } else { return; } takeString(o.p); }
    #|export function okRead(o: O) { if (o.p !== null) { const q = o.p; } else { return; } takeString(o.p); }
  assert_eq(issue_lines(src), [
    "function badDropped > call `takeString` arg[0]: type `string | null` is not assignable to type `string`",
  ])
}

///|
/// Only a discriminant of the target splits: five fields of a two-member
/// enum where only `tag` tells the arms apart split one field, which keeps
/// the combinations under the limit (#315's review; probed: tsc accepts).
test "only a target discriminant splits (splitdisc)" {
  let src =
    #|enum E { A, B }
    #|interface X { tag: E.A; a: E; b: E; c: E; d: E }
    #|interface Y { tag: E.B; a: E; b: E; c: E; d: E }
    #|declare function f(v: X | Y): void;
    #|declare const t: E;
    #|declare const v: E;
    #|export function okOnlyTagSplits() { const o = { tag: t, a: v, b: v, c: v, d: v }; f(o); }
    #|interface P { tag: E.A; a: E.A }
    #|interface Q { tag: E.B; a: E.B }
    #|declare function g(v: P | Q): void;
    #|export function badBothSplitMismatch() { const o = { tag: t, a: v }; g(o); }
  assert_eq(issue_lines(src), [
    "function badBothSplitMismatch > call `g` arg[0]: expected `P | Q` but got `{ tag: E; a: E }`",
  ])
}

///|
/// A nested declaration shadows a name only inside its own scope: a
/// top-level `return value` after `if (flag) { const value = null }` reads
/// the parameter, so the factory still returns `string` (#315's review;
/// probed: tsc accepts `H2.set`).
test "a nested declaration shadows only inside its scope (shadowret2)" {
  let src =
    #|declare function takeS(s: string): void;
    #|export class K { static make(value: string, flag: boolean) { if (flag) { const value = null; } return value; } }
    #|export class H2 { p: string | null = null; set(v: string) { this.p = K.make(v, true); takeS(this.p); } }
    #|export class K3 { static make(value: string) { for (const value of [null]) { return value; } return value; } }
    #|export class H3 { p: string | null = null; set(v: string) { this.p = K3.make(v); takeS(this.p); } }
  assert_eq(issue_lines(src), [
    "function H3.set > call `takeS` arg[0]: type `string | null` is not assignable to type `string`",
  ])
}

///|
/// An array literal widens an enum member only in the key whose own value
/// wrote it: `fixed` holds a declared `E.A` and keeps it beside a `written:
/// E.A` that widens (#315's review; probed: tsc accepts the `ok` lines).
test "an array key widens only the members its own values wrote (enumkeys2)" {
  let src =
    #|enum E { A = "a", B = "b" }
    #|declare const fixed: E.A;
    #|const rows = [{ written: E.A, fixed }];
    #|export const okFixedKeepsMember: { written: E; fixed: E.A }[] = rows;
    #|export function okWriteWritten() { rows[0].written = E.B; }
    #|const nested = [{ fixed, inner: { t: E.A } }];
    #|export const okNestedWriteLeavesFixed: { fixed: E.A; inner: { t: E } }[] = nested;
  assert_eq(issue_lines(src), [])
}

///|
/// A property value that reads a declared binding keeps its declared
/// literal type, and only a key whose type differs across the target's
/// arms is a discriminant: `{ tag, a: v, … }` with `tag: "a" | "b"` and
/// four `"x" | "y"` fields fits a union discriminated by `tag` (#315's
/// review; probed: tsc reports only `badUncoveredTag`).
test "a declared literal union stays a discriminant in an object literal (litdisc)" {
  let src =
    #|type XY = "x" | "y";
    #|type T = { tag: "a"; a: XY; b: XY; c: XY; d: XY } | { tag: "b"; a: XY; b: XY; c: XY; d: XY };
    #|declare function f(v: T): void;
    #|export function okOnlyTagDiscriminates(tag: "a" | "b", v: XY) { const o = { tag, a: v, b: v, c: v, d: v }; f(o); }
    #|export function badUncoveredTag(tag: "a" | "c", v: XY) { const o = { tag, a: v, b: v, c: v, d: v }; f(o); }
    #|interface Box { kind: "a" | "b" }
    #|declare const box: Box;
    #|export function okPropertyReadKept() { const o = { kind: box.kind }; const k: "a" | "b" = o.kind; return k; }
    #|export function okConstLiteralWidens() { const c = "a"; const o = { c }; o.c = "z"; return o; }
  assert_eq(issue_lines(src), [
    "function badUncoveredTag > call `f` arg[0]: expected `T` but got `{ tag: \"a\" (string) | \"c\" (string); a: XY; b: XY; c: XY; d: XY }`",
  ])
}

///|
/// A `var` in a nested block is function-scoped, so a top-level return
/// reads it rather than an outer binding of the name; a nested `let` is
/// not (#315's review; probed: tsc reports `BadVarHoisted.set` only).
test "a nested var is in scope at every return (shadowvar)" {
  let src =
    #|declare function takeS(s: string): void;
    #|declare const value: string;
    #|export class K { static make() { { var value: string | null = null; } return value; } }
    #|export class BadVarHoisted { p: string | null = null; set() { this.p = K.make(); takeS(this.p); } }
    #|export class K2 { static make() { { let value: string | null = null; } return value; } }
    #|export class OkLetBlockScoped { p: string | null = null; set() { this.p = K2.make(); takeS(this.p); } }
  assert_eq(issue_lines(src), [
    "function BadVarHoisted.set > call `takeS` arg[0]: type `string | null` is not assignable to type `string`",
  ])
}

///|
/// A path narrowing survives a branch that rebinds only a SHADOWING local
/// of its root; rebinding the outer root still drops it (#315's review;
/// probed: tsc reports `badOuterRebound` only).
test "a shadowing local's rebinding leaves the outer path narrowed (ifjoin5)" {
  let src =
    #|interface O { p: string | null }
    #|export function okShadowRebound(o: O, replacement: O) { if (o.p !== null) { let o = replacement; o = replacement; } else { return; } const s: string = o.p; return s; }
    #|export function badOuterRebound(o: O, replacement: O) { if (o.p !== null) { o = replacement; } else { return; } const s: string = o.p; return s; }
  assert_eq(issue_lines(src), [
    "function badOuterRebound > binding `s` init: type `string | null` is not assignable to type `string`",
  ])
}

///|
/// `a ?? b` is `a`'s type alone when `a` cannot be nullish, and `a || b`
/// when `a` cannot be falsy, so `b` is not related to the expected type
/// (univer's `__getSplitWidthNoAngle(…, tableSource.dist ?? {})`). An empty
/// object type admits `""` and `0`, so it is not always truthy, and a
/// string left operand can be `""`. The deciding left operand IS the result,
/// so it is what relates to the target (#316's review). A bigint zero is
/// falsy in both spellings, `0n` and `-0n` (#317's review; probed: tsc
/// reports the bad cells only).
test "a left operand that decides `??` / `||` skips the right (coalesce)" {
  let src =
    #|interface D { a: number; b: number }
    #|declare function f(d: D): void;
    #|declare function g(x: string): void;
    #|class K { m() {} }
    #|declare function fk(x: K): void;
    #|export function okNonNullish(d: D) { f(d ?? {}); }
    #|export function okOrObject(d: D) { f(d || {}); }
    #|export function okOrMethodsOnly(k: K) { fk(k || 1); }
    #|export function okStrCoalesce(s: string) { g(s ?? 1); }
    #|export function badNullable(u: D | undefined) { f(u ?? {}); }
    #|export function badOrStr(s: string) { g(s || 1); }
    #|export function badLeftDecidesCoalesce(s: string): number { return s ?? false; }
    #|export function badLeftDecidesOr(d: D): string { return d || "z"; }
    #|export function okBigOneLeft(x: 1n) { const y: bigint = x || "bad"; return y; }
    #|export function badBigZeroLeft(x: 0n) { const y: bigint = x || "bad"; return y; }
    #|export function badBigNegZeroLeft(x: -0n) { const y: bigint = x || "bad"; return y; }
  assert_eq(issue_lines(src), [
    "function badNullable > call `f` arg[0] (logical).a: property `a` is required by `D`",
    "function badNullable > call `f` arg[0] (logical).b: property `b` is required by `D`",
    "function badOrStr > call `g` arg[0] (logical): expected `string` but got `number`",
    "function badLeftDecidesCoalesce > return (logical): expected `number` but got `string`",
    "function badLeftDecidesOr > return (logical): expected `string` but got `D`",
    "function badBigZeroLeft > binding `y` init (logical): expected `bigint` but got `string`",
    "function badBigNegZeroLeft > binding `y` init (logical): expected `bigint` but got `string`",
  ])
}

///|
/// The falsy part of `n && x` is `0` for a `number`, `""` for a `string`
/// and `0n` for a `bigint` (tsc's `extractDefinitelyFalsyTypes`), and a
/// truthy test removes them, so `t.value && t.value.stack` guarded by
/// `if (!s) return` is the array (univer's `regexp-check.ts`). A mutable
/// binding widens the fresh `"a"`, which absorbs the `""`. Without the
/// truthy test, `0` and `""` stay, and tsc's TS2488 names the same type
/// (probed: tsc reports `badNoGuard` only). `const q: "a" = s && "a"` is
/// TS2322 in tsc and still a MISS here: the literal-union mismatch is
/// suppressed as flow-narrowing residue.
test "`&&` keeps the falsy literal of a primitive operand (andfalsy)" {
  let src =
    #|interface T { stack?: T[]; value?: number | string | T }
    #|export function okNarrow(t: T) { const s = t.stack || (t.value && (t.value as T).stack); if (!s) return; for (const x of s) { x.stack; } }
    #|export function okLet(s: string) { let r = s && "a"; r = "b"; return r; }
    #|export function badNoGuard(t: T) { const s = t.value && (t.value as T).stack; if (s === undefined) return; for (const x of s) { x.stack; } }
  assert_eq(issue_lines(src), [
    "function badNoGuard > for-of iterable: type `0 | \"\" (string) | T[]` must have a `[Symbol.iterator]()` method that returns an iterator",
  ])
}

///|
/// A mutable binding widens every FRESH literal in a union, so
/// `let r = c ? "a" : "b"` is `string` and takes `"z"` later (a false
/// positive on main too). A `const` keeps the union. An operand's fresh
/// literal counts only when it reaches the result: the right of `||` when
/// the left can be falsy, of `??` when the left can be nullish, so a
/// declared `"x"` on the left keeps the binding `"x"`, and the right
/// operand is not in its type at all (#316's review; probed: tsc reports
/// the three bad cells, the last two at the reassignment of `"y"`).
test "a mutable binding widens a union of fresh literals (letwiden)" {
  let src =
    #|declare const nx: "x" | undefined;
    #|declare const mx: "x";
    #|export function okCondLet(c: boolean) { let r = c ? "a" : "b"; r = "z"; return r; }
    #|export function okCondNum(c: boolean) { let r = c ? 1 : 2; r = 3; return r; }
    #|export function okOrLeftDeclared() { let a: "foo" = "foo"; let b = a || "foo"; let c2: "foo" = b; return c2; }
    #|export function okOrString(s: string) { let b = s || "foo"; b = "z"; return b; }
    #|export function okCoalesceNullable() { let b = nx ?? "y"; b = "z"; return b; }
    #|export function badConst(c: boolean) { const r = c ? "a" : "b"; const z: "c" = r; return z; }
    #|export function badCoalesceNonNullable() { let b = mx ?? "y"; b = "y"; return b; }
    #|export function badOrNonFalsy() { let b = mx || "y"; b = "y"; return b; }
    #|declare const tag: "a" | "b";
    #|export function badAlwaysFalsyLeft() { const empty = ""; let value = empty || tag; value = "x"; return value; }
  assert_eq(issue_lines(src), [
    "function badConst > binding `z` init: expected `\"c\" (string)` but got `\"a\" (string) | \"b\" (string)`",
    "function badCoalesceNonNullable > assign `b`: expected `\"x\" (string)` but got `\"y\" (string)`",
    "function badOrNonFalsy > assign `b`: expected `\"x\" (string)` but got `\"y\" (string)`",
    "function badAlwaysFalsyLeft > assign `value`: expected `\"a\" (string) | \"b\" (string)` but got `\"x\" (string)`",
  ])
}

///|
/// In a STATIC method `this` is the class, so a singleton factory's
/// `return this._instance` reads the static field's declared type and the
/// assignment after `if (cell == null)` is never nullish (univer's
/// `NullValueObject.create`). A static field that admits `undefined` keeps
/// the assignment nullable (probed: tsc reports `badMaybe` only).
test "a static factory body reads `this` as its class (staticthis)" {
  let src =
    #|type Nullable<T> = T | null | undefined | void;
    #|class Base { k = 1 }
    #|class NullV extends Base {
    #|  private static _instance: NullV;
    #|  private static _maybe: NullV | undefined;
    #|  static create() { this._instance = this._instance || new NullV(); return this._instance; }
    #|  static maybe() { const m = this._maybe; return m; }
    #|}
    #|export function okSingleton(def: Nullable<Base>) { const out: Base[] = []; let cell = def; if (cell == null) { cell = NullV.create(); } out[0] = cell; }
    #|export function badMaybe(def: Nullable<Base>) { const out: Base[] = []; let cell = def; if (cell == null) { cell = NullV.maybe(); } out[0] = cell; }
  assert_eq(issue_lines(src), [
    "function badMaybe > assign array element: type `null | undefined | void | Base` is not assignable to type `Base`",
  ])
}

///|
/// TS 4.4 inlines an unannotated `const` used as a condition, so
/// `const column = line?.parent; if (!column) return` narrows `line`
/// through the chain (univer's `findPositionByGlyph`). Narrowing a
/// different binding does not (probed: tsc reports `bad` only).
test "an optional-chain const narrows its receiver as a condition (chainalias)" {
  let src =
    #|interface Col { lines: Line[] }
    #|interface Line { divides: Div[]; parent?: Col }
    #|interface Div { parent?: Line }
    #|interface Glyph { parent?: Div }
    #|export function ok(glyph: Glyph) { const divide = glyph.parent; const line = divide?.parent; const column = line?.parent; if (!divide || !column) return; const i: number = line.divides.indexOf(divide); return i + column.lines.indexOf(line); }
    #|export function bad(glyph: Glyph) { const divide = glyph.parent; const line = divide?.parent; if (!divide) return; return line.divides; }
  assert_eq(issue_lines(src), [
    "function bad > PropAccess `.divides`: object is possibly `undefined`",
  ])
}

///|
/// An explicit type argument instantiates a defaulted or optional parameter
/// as `T | undefined`, so `new M<string>(m)` with `m: P<string> | undefined`
/// is legal against `constructor(matrix: P<T> = {})` (univer's
/// `formula-data.model.ts`), while a wrong element is still reported
/// (probed: tsc reports the two bad cells only).
test "an explicit type argument keeps a default's undefined (typeargdefault)" {
  let src =
    #|interface P<T> { [row: number]: { [col: number]: T } }
    #|export class M<T> { constructor(matrix: P<T> = {}) { } }
    #|declare const m: P<string> | undefined;
    #|export const okExplicitTypeArg = new M<string>(m);
    #|export class K<T> { constructor(x: T[] = []) { } }
    #|declare const ks: number[] | undefined;
    #|export const okArrayDefault = new K<number>(ks);
    #|export const badArrayWrong = new K<number>(["s"]);
    #|export function g<T>(x: T[] = []): T | undefined { return x[0]; }
    #|declare const arr: number[] | undefined;
    #|export const okCallDefault = g<number>(arr);
    #|export const badCallWrong = g<number>(["s"]);
  assert_eq(issue_lines(src), [
    "top-level > new `K` arg[0][0]: expected `number` but got `string`", "top-level > call `g` arg[0][0]: expected `number` but got `string`",
  ])
}

///|
/// A numeric literal written against a numeric enum fits only when a member
/// holds its value (TS 5.0). `infer_expr` erases `9` to `number`, which
/// every numeric enum accepts, so the literal is read off the expression.
/// A union holding the enum is read flattened, so `b?: Nullable<H>`
/// (`Nullable<H> | undefined`) takes `2`, which main reported for any
/// literal (univer's `styleList.ht = 1`; probed: tsc reports the bad cells
/// only).
test "a numeric literal fits a numeric enum only through a member (enumliteral)" {
  let src =
    #|type Nullable<T> = T | null | undefined | void;
    #|enum H { U, L, C }
    #|enum F { A = 10, B }
    #|interface Style { b?: Nullable<H>; e: H }
    #|export function okBare() { const e: H = 2; return e; }
    #|export function okAliasUnion(s: Style) { s.b = 2; }
    #|export function okContinued() { const f: F = 11; return f; }
    #|export function okNumberMember() { const x: H | number = 9; return x; }
    #|export function badBare() { const e: H = 9; return e; }
    #|export function badAliasUnion(s: Style) { s.b = 9; }
    #|export function badObjectMember() { const o: { e: H } = { e: 9 }; return o; }
    #|export function badContinued() { const f: F = 12; return f; }
    #|export function okTruthyLeft(x: 1) { const e: H = x || 9; return e; }
    #|export function badFalsyLeft(x: 0 | 1) { const e: H = x || 9; return e; }
  assert_eq(issue_lines(src), [
    "function badBare > binding `e` init: expected `H` but got `9`", "function badAliasUnion > assign `.b`: expected `Nullable<H> | undefined` but got `9`",
    "function badObjectMember > binding `o` init.e: expected `H` but got `9`", "function badContinued > binding `f` init: expected `F` but got `12`",
    "function badFalsyLeft > binding `e` init (logical): expected `H` but got `9`",
  ])
}

///|
/// A written `: any` return is `any`, and only an absent one is read from
/// the body: both are `Any` in `TsFunc.return_type`, so the parser records
/// `<written-any-return:NAME>`. A nested `return` the top-level shortcut
/// cannot see may be `any`, which makes the whole return `any` (#317's
/// review; probed: tsc reports `badInferred` only).
test "a written any return is not inferred from the body (writtenany)" {
  let src =
    #|function written(): any { return 1; }
    #|function inferred() { return 1; }
    #|declare const opaque: any;
    #|function nested(flag: boolean) { if (flag) return opaque; return 1; }
    #|export const okWrittenAny: string = written();
    #|export const okNestedAny: string = nested(true);
    #|export const badInferred: string = inferred();
  assert_eq(issue_lines(src), [
    "top-level > binding `badInferred` init: expected `string` but got `number`",
  ])
}

///|
/// A `var` in a branch is the enclosing function's binding, so writing it
/// there drops the outer path's narrowing at the join as any write does,
/// while a `let` is the branch's own (#316's review; probed: tsc reports
/// `badVarRedeclare` only).
test "a var in a branch is not a shadow at the join (varjoin)" {
  let src =
    #|interface O { p: string | undefined }
    #|export function okLetShadow(c: boolean, o: O, other: O) { o.p = ""; if (c) { let o = other; o = other; } const s: string = o.p; return s; }
    #|export function badVarRedeclare(c: boolean, o: O, other: O) { o.p = ""; if (c) { var o: O; o = other; } const s: string = o.p; return s; }
  assert_eq(issue_lines(src), [
    "function badVarRedeclare > binding `s` init: type `string | undefined` is not assignable to type `string`",
  ])
}

///|
/// `Object.entries` / `Object.values` take `T` from the lib's generic
/// overload: a `Record`, a declared index signature or an array gives the
/// value type, and an interface with no index signature or a `Map` falls to
/// the `{}` overload, which is `any`. The value narrows a declared
/// `D | null` by assignment, where `any` keeps the `null` (excalidraw's
/// `applyLatestChanges`; probed: tsc reports the bad cells only).
test "Object.entries reads the value type of an indexable source (entries)" {
  let src =
    #|interface I { a: number; b: string }
    #|interface D { x: number }
    #|export function badRecord(r: Record<string, number>) { for (const [, v] of Object.entries(r)) { const s: string = v; } }
    #|export function badIndex(r: { [k: number]: number }) { for (const [, v] of Object.entries(r)) { const s: string = v; } }
    #|export function badArray(r: number[]) { const xs: string[] = Object.values(r); }
    #|export function okInterface(i: I) { for (const [, v] of Object.entries(i)) { const s: boolean = v; } }
    #|export function okMap(m: Map<string, number>) { for (const [, v] of Object.entries(m)) { const s: string = v; } }
    #|export function okNarrows(r: Record<string, D>) { for (const [, d] of Object.entries(r)) { let l: D | null = null; l = d; console.log(l.x); } }
  assert_eq(issue_lines(src), [
    "function badRecord > binding `s` init: expected `string` but got `number`",
    "function badIndex > binding `s` init: expected `string` but got `number`", "function badArray > binding `xs` init: expected `string[]` but got `number[]`",
  ])
}

///|
/// A GENERIC static factory narrows an assignment when its result is an
/// instance of a class, whatever the class's type arguments: it was skipped
/// for any method with type parameters, and a body that builds the result
/// from `const` locals was skipped again because those arguments carry the
/// method's own `T`. A factory returning a bare type parameter still
/// abstains, since an argument can make it nullish (excalidraw's
/// `Delta.create`; probed: tsc reports `badBareTypeParam` only).
test "a generic static factory narrows an assignment (genericfactory)" {
  let src =
    #|class Delta<T> {
    #|  private constructor(public readonly deleted: Partial<T>) {}
    #|  static create<T>(d: Partial<T>) { return new Delta(d); }
    #|  static viaLocal<T>(d: Partial<T>, m?: (x: Partial<T>) => Partial<T>) { const md = m ? m(d) : d; return new Delta(md); }
    #|  static pick<T>(x: T) { return x; }
    #|}
    #|type EP = { a: number };
    #|export function okGeneric(c: boolean, d: Delta<EP>) { let l: Delta<EP> | null = null; if (c) { l = Delta.create<EP>({}); } else { l = d; } return l.deleted; }
    #|export function okViaLocal(c: boolean, d: Delta<EP>) { let l: Delta<EP> | null = null; if (c) { l = Delta.viaLocal(d.deleted); } else { l = d; } return l.deleted; }
    #|export function badBareTypeParam(c: boolean, n: string | null) { let v: string | null = null; if (c) { v = Delta.pick(n); } else { v = "x"; } return v.length; }
  assert_eq(issue_lines(src), [
    "function badBareTypeParam > PropAccess `.length`: object is possibly `null`",
  ])
}

///|
/// An object rest over an intersection holding ONE union part distributes
/// over that union, as it does over a bare union: `{ tab, ...rest }` of
/// `{ tab: string } & (A | B)` is `A | B` minus `tab`, which an `in` test
/// then narrows (excalidraw's `TTDDialog`; probed: tsc reports
/// `badRestMissing` only).
test "an object rest distributes over an intersection's union part (restinter)" {
  let src =
    #|type A = { onSubmit(x: number): void; label?: string };
    #|type B = { __fallback: true };
    #|export const okRestOfIntersectionUnion = ({ tab, ...rest }: { tab: string } & (A | B)) => {
    #|  if (!("__fallback" in rest)) { rest.onSubmit(1); return rest.label; }
    #|  return tab;
    #|};
    #|export const okRestOfIntersection = ({ tab, ...rest }: { tab: string } & A) => { rest.onSubmit(1); return tab; };
    #|export const badRestMissing = ({ tab, ...rest }: { tab: string } & A) => { rest.nope; return tab; };
  assert_eq(issue_lines(src), [
    "top-level > PropAccess `.nope`: property `nope` does not exist on `{ onSubmit: (number) => void; label: string | undefined }`",
  ])
}

///|
/// A type argument the use omits is the parameter's DEFAULT, and a default
/// may name an earlier parameter, which then reads that parameter's
/// argument. A bare generic alias takes every default (probed: tsc reports
/// the bad cells only).
test "an omitted alias argument takes its default (aliasdefault)" {
  let src =
    #|type I<Q = string, C = number> = { c: C; q: Q };
    #|type P<A, B = A[]> = { a: A; b: B };
    #|type U<T = number> = { v: T };
    #|declare const i: I<boolean>;
    #|declare const p: P<number>;
    #|declare const u: U;
    #|export function okRefersEarlier() { const xs: number[] = p.b; return xs; }
    #|export function okBareAlias() { const n: number = u.v; return n; }
    #|export function badDefault() { const s: string = i.c; return s; }
    #|export function badRefersEarlier() { const xs: string[] = p.b; return xs; }
    #|export function badBareAlias() { const s: string = u.v; return s; }
    #|export function badBareWhole() { const s: string = u; return s; }
  assert_eq(issue_lines(src), [
    "function badDefault > binding `s` init: expected `string` but got `number`",
    "function badRefersEarlier > binding `xs` init: expected `string[]` but got `number[]`",
    "function badBareAlias > binding `s` init: expected `string` but got `number`",
    "function badBareWhole > binding `s` init: expected `string` but got `{ v: number }`",
  ])
}

///|
/// #319's review. A default is written in the scope the ALIAS is declared
/// in, so a namespace alias's `T = Item` reads the namespace's `Item`, not a
/// file-level one: the namespace-local rename has to reach the defaults as
/// well as the body. So does the cross-body one, where `Elem` is declared
/// by ANOTHER body of the same namespace (probed: tsc reports the bad cells
/// only).
test "a namespace alias's default reads the namespace's names (nsdefault)" {
  let src =
    #|type Item = number;
    #|namespace N { export type Item = string; export type A<T = Item> = { v: T }; }
    #|declare const a: N.A;
    #|export function okNamespaceDefault() { const s: string = a.v; return s; }
    #|export function badNamespaceDefault() { const n: number = a.v; return n; }
    #|namespace P { export type Elem = string; }
    #|namespace P { export type B<T = Elem> = { v: T }; }
    #|declare const pb: P.B;
    #|export function okCrossBodyDefault() { const s: string = pb.v; return s; }
    #|export function badCrossBodyDefault() { const n: number = pb.v; return n; }
  assert_eq(issue_lines(src), [
    "function badNamespaceDefault > binding `n` init: expected `number` but got `string`",
    "function badCrossBodyDefault > binding `n` init: expected `number` but got `string`",
  ])
}

///|
/// A discriminant that is a union of literals is related one combination at
/// a time, STRUCTURALLY: the excess check has already run on the whole
/// literal, and with no single member picked it only asks whether some
/// member declares the property. zod's `{ status: status.value, value }`
/// fits `OK<any> | DIRTY<any> | INVALID` although `INVALID` lacks `value`
/// (probed: tsc reports the bad cells only).
test "a discriminant split relates each combination structurally (splitexcess)" {
  let src =
    #|type INVALID = { status: "aborted" };
    #|type DIRTY<T> = { status: "dirty"; value: T };
    #|type OK<T> = { status: "valid"; value: T };
    #|type SRT<T = any> = OK<T> | DIRTY<T> | INVALID;
    #|declare const st: { value: "aborted" | "dirty" | "valid" };
    #|export function okSplit(): SRT<any> { const arr: any[] = []; return { status: st.value, value: arr }; }
    #|export function badNoMemberHasIt(): SRT<any> { return { status: st.value, value: 1, extra: 1 }; }
    #|export function badSingleDiscriminantExcess(): SRT<any> { return { status: "aborted", value: 1 }; }
  assert_eq(issue_lines(src), [
    "function badNoMemberHasIt > return: type of the object literal is not assignable to type `OK<any> | DIRTY<any> | INVALID`",
    "function badSingleDiscriminantExcess > return: type of the object literal is not assignable to type `OK<any> | DIRTY<any> | INVALID`",
  ])
}

///|
/// #318's review. A generic CLASS's index signature substitutes the class's
/// arguments, so `Object.values` of `Dict<number>` is `number[]` even with a
/// module alias spelled like the parameter. An interface whose only index
/// signature is numeric reaches the generic overload only as an
/// `ArrayLike<T>`, with a numeric `length`. And a static factory's own
/// binder is recognised before any alias expands it, as written (`T` beside
/// `type T = string`) or through an alias (`Identity<T>`) (probed: tsc
/// reports the bad cells only).
test "Object.values class arguments and static factory binders (review318)" {
  let src =
    #|type V = string;
    #|class Dict<V> { [k: string]: V; }
    #|interface N { [k: number]: number; label: string }
    #|interface NL { [k: number]: number; length: number }
    #|interface NL1 { [k: number]: number; length: 1 }
    #|declare const nl1: NL1;
    #|export function badLiteralLength() { const xs: string[] = Object.values(nl1); return xs; }
    #|type T = string;
    #|type Identity<X> = X;
    #|class Box { b = 1 }
    #|class F {
    #|  static pick<T>(x: T): T { return x; }
    #|  static ident<T>(x: T): Identity<T> | Box { return x as Identity<T>; }
    #|}
    #|declare const d: Dict<number>;
    #|declare const n: N;
    #|declare const nl: NL;
    #|export function okClassArg() { const xs: number[] = Object.values(d); return xs; }
    #|export function okNumericIndexInterface() { const xs: string[] = Object.values(n); return xs; }
    #|export function badClassArg() { const xs: boolean[] = Object.values(d); return xs; }
    #|export function badArrayLikeInterface() { const xs: string[] = Object.values(nl); return xs; }
    #|export function badBinderShadowsAlias(c: boolean) { let v: string | null = null; if (c) { v = F.pick(null); } else { v = "x"; } return v.length; }
    #|export function badBinderThroughAlias(c: boolean) { let v: Box | null = null; if (c) { v = F.ident(null); } else { v = new Box(); } return v.b; }
  assert_eq(issue_lines(src), [
    "function badLiteralLength > binding `xs` init: expected `string[]` but got `number[]`",
    "function badClassArg > binding `xs` init: expected `boolean[]` but got `number[]`",
    "function badArrayLikeInterface > binding `xs` init: expected `string[]` but got `number[]`",
    "function badBinderShadowsAlias > PropAccess `.length`: object is possibly `null`",
    "function badBinderThroughAlias > PropAccess `.b`: object is possibly `null`",
  ])
}

///|
/// Arrays and tuples are comparable with `===` when their elements are.
/// `types_can_overlap` had no arm for either, so every pair fell to its
/// final `false` and `prevProps.elements !== nextProps.elements` read as
/// always true (excalidraw's canvases). An optional tuple element is stored
/// as `T | undefined`, so a longer tuple whose extra elements admit
/// `undefined` overlaps (probed: tsc reports the bad cells only).
test "arrays and tuples compare by their elements (arrayeq)" {
  let src =
    #|type El = { id: string };
    #|export function okSameElement(a: number[], b: number[]) { return a === b; }
    #|export function okReadonly(a: readonly El[], b: readonly El[]) { return a !== b; }
    #|export function okTupleAndArray(a: [number, number], b: number[]) { return a === b; }
    #|export function okOptionalElement(a: [number, string?], b: [number]) { return a === b; }
    #|export function badDisjointElements(a: number[], b: string[]) { return a === b; }
    #|export function badDisjointTuples(a: [number], b: [string]) { return a === b; }
    #|export function badTupleLengths(a: [number], b: [number, number]) { return a === b; }
  assert_eq(issue_lines(src), [
    "function badDisjointElements > strict equality: comparing `number[]` and `string[]` with === will always be false",
    "function badDisjointTuples > strict equality: comparing `[number]` and `[string]` with === will always be false",
    "function badTupleLengths > strict equality: comparing `[number]` and `[number, number]` with === will always be false",
  ])
}

///|
/// #320's review. A tuple meets an array as `Array<union of its elements>`,
/// and a union is comparable when ANY member is: `[string, number]` overlaps
/// `number[]`, `[string]` does not, and `[]` overlaps everything. A tuple
/// that is nothing but a rest slot is that array, so `[...number[]]` against
/// `boolean[]` or `[string]` is TS2367, and a rest of a TUPLE is its
/// elements, so `[...[string]]` is `[string]` (#321's review; probed cell by
/// cell).
test "a tuple meets an array through the union of its elements (review320)" {
  let src =
    #|export function okSomeElementOverlaps(a: [string, number], b: number[]) { return a === b; }
    #|export function okMiddleRest(a: [number, ...string[], boolean], b: boolean[]) { return a === b; }
    #|export function okEmptyTuple(a: [], b: number[]) { return a === b; }
    #|export function okPrefixThenRest(a: [string, ...number[]], b: number[]) { return a === b; }
    #|export function badNoElementOverlaps(a: [string], b: number[]) { return a === b; }
    #|export function badRestOnly(a: [...number[]], b: boolean[]) { return a === b; }
    #|export function badRestOnlyAgainstTuple(a: [...number[]], b: [string]) { return a === b; }
    #|export function badRestOnlyOnTheRight(a: [string], b: [...number[]]) { return a === b; }
    #|export function badPrefixAndRest(a: [string, ...boolean[]], b: number[]) { return a === b; }
    #|export function badTupleRest(a: [...[string]], b: number[]) { return a === b; }
    #|export function okTupleRest(a: [...[string, number]], b: number[]) { return a === b; }
    #|export function badTupleRestVsTuple(a: [...[string]], b: [number]) { return a === b; }
    #|export function okTupleRestVsTuple(a: [...[string]], b: [string]) { return a === b; }
  assert_eq(issue_lines(src), [
    "function badNoElementOverlaps > strict equality: comparing `[string]` and `number[]` with === will always be false",
    "function badRestOnly > strict equality: comparing `[type]` and `boolean[]` with === will always be false",
    "function badRestOnlyAgainstTuple > strict equality: comparing `[type]` and `[string]` with === will always be false",
    "function badRestOnlyOnTheRight > strict equality: comparing `[string]` and `[type]` with === will always be false",
    "function badPrefixAndRest > strict equality: comparing `[string, type]` and `number[]` with === will always be false",
    "function badTupleRest > strict equality: comparing `[type]` and `number[]` with === will always be false",
    "function badTupleRestVsTuple > strict equality: comparing `[type]` and `[number]` with === will always be false",
  ])
}

///|
/// A function declaration's bounded type parameter is inlined to its bound
/// in the signature and kept in the body, so a value read off a `P`-typed
/// parameter arrived as the bound against a body annotation still saying
/// `P` (excalidraw's `convexHull`). A source carrying the bound exactly
/// abstains; a literal, a template and a value of ONE member of the bound
/// still report, a conditional is judged branch by branch, and an array
/// indexed by a `number`-bounded parameter is its element type (#322's
/// review; probed: tsc reports the bad cells only).
test "a value read off a bounded parameter fits the body's own annotation (boundresidue)" {
  let src =
    #|type A = [number, number] & { _a: 1 };
    #|type B = [number, number] & { _b: 1 };
    #|export function okSpreadOfParam<P extends A | B>(points: readonly P[]): P[] {
    #|  const sorted = [...points];
    #|  const half = (pts: P[]) => pts;
    #|  return half(sorted);
    #|}
    #|export function okDirectParam<P extends A | B>(points: P[]): P[] {
    #|  const half = (pts: P[]) => pts;
    #|  return half(points);
    #|}
    #|export function okLocalAnnotated<P extends A | B>(points: readonly P[]): P[] {
    #|  const copy: P[] = [...points];
    #|  return copy;
    #|}
    #|export function okArrayIndexedByNumericParam<K extends number>() {
    #|  let x: Array<string>[K] = "abc";
    #|  return x;
    #|}
    #|export function okPrimitiveIntoObjectElement<K extends number>() {
    #|  let x: Array<{ length: number }>[K] = "abc";
    #|  return x;
    #|}
    #|export function badArrayIndexedByNumericParam<K extends number>() {
    #|  let x: Array<string>[K] = 123;
    #|  return x;
    #|}
    #|export function okCondOfParams<K extends number>(c: boolean, k: K, j: K) { const v: K = c ? k : j; return v; }
    #|export function badCondLiteralBranch<K extends number>(c: boolean, k: K) { const v: K = c ? k : 1; return v; }
    #|export function badBoundIntoTemplate<T extends "a" | "b">(x: T) {
    #|  const t: T = "" as `${T}`;
    #|  return [x, t];
    #|}
    #|export function badLiteralIntoNumericParam<K extends number>() { const k: K = 1; return k; }
    #|export function badLiteralArrayIntoNumericParam<K extends number>() { const ks: K[] = [1]; return ks; }
    #|export function badBoundMemberIntoParamArray<P extends A | B>(as: A[]) { const ps: P[] = as; return ps; }
  assert_eq(issue_lines(src), [
    "function badArrayIndexedByNumericParam > binding `x` init: expected `string` but got `number`",
    "function badCondLiteralBranch > binding `v` init (else): type `1` is not assignable to type parameter `K`",
    "function badBoundIntoTemplate > binding `t` init: the template-literal form `${T}` is not assignable to type `T`",
    "function badLiteralIntoNumericParam > binding `k` init: type `1` is not assignable to type parameter `K`",
    "function badLiteralArrayIntoNumericParam > binding `ks` init[0]: type `1` is not assignable to type parameter `K`",
    "function badBoundMemberIntoParamArray > binding `ps` init: expected `P[]` but got `([number, number] & { _a: 1 })[]`",
  ])
}

///|
/// A write `obj[k] = v` through a key TYPED as a literal, or a union of
/// them, must fit every property the key can name. `infer_index` answers
/// the read, which for such a key was nothing (a literal-typed variable)
/// or the union (a union key) (keyofAndIndexedAccess2's `f1`). A fresh
/// object literal is checked against the targets' intersection, whose
/// excess-property check is against the combined shape (#322's review;
/// probed: tsc reports the bad cells only, once each).
test "an element write through a literal-typed key is checked (keywrite)" {
  let src =
    #|declare const obj: { a: number; b: 0 | 1; c: string };
    #|export function badLiteralKeyParam(k0: "a") { obj[k0] = "x"; }
    #|export function okLiteralKeyParam(k0: "a") { obj[k0] = 2; }
    #|export function badBracketLiteral() { obj["a"] = "x"; }
    #|export function badLiteralKeyConst() { const k = "a"; obj[k] = "x"; }
    #|export function badUnionKey(k1: "a" | "b") { obj[k1] = 2; }
    #|export function okUnionKey(k1: "a" | "b") { obj[k1] = 1; }
    #|export function badUnionKeyOnce(k2: "a" | "b" | "c") { obj[k2] = "x"; }
    #|declare const o: { a: { x: number }; b: { y: number } };
    #|export function okLiteralFitsBoth(k: "a" | "b") { o[k] = { x: 1, y: 2 }; }
    #|export function okLiteralFitsBothNested(k: "a" | "b", c: boolean) { o[k] = c ? { x: 1, y: 2 } : { x: 2, y: 3 }; }
    #|export function badLiteralMissesOne(k: "a" | "b") { o[k] = { x: 1 }; }
    #|export function badLiteralExcess(k: "a" | "b") { o[k] = { x: 1, y: 2, z: 3 }; }
    #|export function badValueMissesOne(k: "a" | "b") { const v = { x: 1 }; o[k] = v; }
    #|declare const arrs: { a: { x: number }[]; b: { y: number }[] };
    #|export function okArrayOfLiteralsFitsBoth(k: "a" | "b") { arrs[k] = [{ x: 1, y: 2 }]; }
    #|export function badArrayOfLiteralsMissesOne(k: "a" | "b") { arrs[k] = [{ x: 1 }]; }
    #|declare const lens: { a: { length: number }[]; b: { length: number }[] };
    #|export function okPrimitiveBesideLiteral(k: "a" | "b") { lens[k] = ["abc", { length: 1 }]; }
  assert_eq(issue_lines(src), [
    "function badLiteralKeyParam > assign `[…]`: expected `number` but got `string`",
    "function badBracketLiteral > assign `[…]`: expected `number` but got `string`",
    "function badLiteralKeyConst > assign `[…]`: expected `number` but got `string`",
    "function badUnionKey > assign `[…]`: expected `0 | 1` but got `2`", "function badUnionKeyOnce > assign `[…]`: expected `number` but got `string`",
    "function badLiteralMissesOne > assign `[…]`.y: property `y` is required by `{ x: number; y: number }`",
    "function badLiteralExcess > assign `[…]`.z: property `z` does not exist on target type",
    "function badValueMissesOne > assign `[…]`: property `y` is missing in `{ x: number }` but required in `{ y: number }`",
    "function badArrayOfLiteralsMissesOne > assign `[…]`[0].y: property `y` is required by `{ x: number; y: number }`",
  ])
}

///|
/// An object with a COMPUTED key, held in a variable, against an interface
/// that declares nothing but string index signatures: the computed entry's
/// value is what must fit. It was read as `any` and then refused outright
/// (univer's `load(testLocales)` and `batchRemove(config)`), while the same
/// literal passed inline was accepted. A union index value is tried member
/// by member with the plain relation too, so `"a"` fits `string | …`. An
/// inline literal's string-typed computed key is judged against the string
/// signature, and a numeric one falls back to it (probed: tsc reports the
/// bad cells only).
test "a computed-key object fits a string index signature by its values (computedindex)" {
  let src =
    #|type LanguageValue = string | string[] | ILanguagePack | ILanguagePack[] | boolean;
    #|interface ILanguagePack { [key: string]: LanguageValue }
    #|interface ILocales { [key: string]: ILanguagePack }
    #|interface Lang { [key: string]: { greeting: string } }
    #|declare function load(l: Lang): void;
    #|declare function loadAll(l: ILocales): void;
    #|enum LocaleType { ZH = "zh", EN = "en" }
    #|export function okComputedVar() { const K = "zh"; const locales = { [K]: { greeting: "a" } }; load(locales); }
    #|export function okComputedInline() { const K = "zh"; load({ [K]: { greeting: "a" } }); }
    #|export function okComputedDeclared(k: string) { const locales = { [k]: { greeting: "a" } }; load(locales); }
    #|export function okNestedPack() { const locales = { [LocaleType.ZH]: { greeting: "a", nested: { welcome: "b" }, list: ["x"], on: true } }; loadAll(locales); }
    #|export function badComputedVar() { const K = "zh"; const locales = { [K]: { greeting: 1 } }; load(locales); }
    #|export function badNumberInPack() { const locales = { [LocaleType.ZH]: { greeting: 1 } }; loadAll(locales); }
    #|export function badComputedInline(k: string) { load({ [k]: { greeting: 1 } }); }
    #|export function okNumericKeyToStringSignature(n: number) { load({ [n]: { greeting: "a" } }); }
    #|export function badNumericKeyToStringSignature(n: number) { load({ [n]: { greeting: 1 } }); }
    #|const sym = Symbol("s");
    #|interface Strs { [k: string]: string }
    #|declare function take(s: Strs): void;
    #|export function okSymbolKeyInline() { take({ [sym]: 1 }); }
    #|export function okSymbolKeyBound() { const o = { [sym]: 1 }; take(o); }
    #|declare const usa: unique symbol;
    #|declare const usb: unique symbol;
    #|declare const unionKey: typeof usa | typeof usb;
    #|declare const mixedKey: typeof usa | string;
    #|export function okUnionSymbolKey() { take({ [unionKey]: 1 }); }
    #|export function badMixedSymbolKey() { take({ [mixedKey]: 1 }); }
  assert_eq(issue_lines(src), [
    "function badComputedVar > call `load` arg[0]: expected `Lang` but got `{ [computed]: { greeting: number } }`",
    "function badNumberInPack > call `loadAll` arg[0]: expected `ILocales` but got `{ [computed]: { greeting: number } }`",
    "function badComputedInline > call `load` arg[0][computed].greeting: expected `string` but got `number`",
    "function badNumericKeyToStringSignature > call `load` arg[0][computed].greeting: expected `string` but got `number`",
    "function badMixedSymbolKey > call `take` arg[0]: type `number` is not assignable to the `string` index type `string`",
  ])
}

///|
/// A spread argument's element relates to the rest parameter's element
/// through every alias the target union's members name. `unwrap` expanded
/// only the outer layer, so `[number, number]` against `Charset | Raw` met
/// the bare name `Raw` (univer's `new Charset(...next)`; probed: tsc
/// reports the bad cells only).
test "a spread argument relates through nested aliases (spreadalias)" {
  let src =
    #|type Unit = [number, number];
    #|type Raw = string | number | [string, string] | [number, number];
    #|class Charset { data: Unit[] = []; constructor(...inputs: Input[]) {} }
    #|type Input = Charset | Raw;
    #|declare function take(...inputs: Input[]): void;
    #|export function okSpreadCall(next: Unit[]) { take(...next); }
    #|export function okSpreadNew(next: Unit[]) { return new Charset(...next); }
    #|export function badSpreadTuple(next: [boolean, boolean][]) { take(...next); }
  assert_eq(issue_lines(src), [
    "function badSpreadTuple > call `take` spread arg: spread element type `[boolean, boolean]` is not assignable to `Input`",
  ])
}

///|
/// A primitive fits an object type through its own members, and so it fits
/// an intersection of object types when it fits every part: `string` and
/// `"abc"` into `{ length: number } & { x?: number }` are legal, and the
/// intersection-target check rejected any primitive against an object part
/// before asking. An index signature is a member too: a string's numeric
/// slots are `string`, and a primitive has no string index (#322's reviews;
/// probed: tsc reports the bad cells only).
test "a primitive fits an intersection of object types (intrinsicintersection)" {
  let src =
    #|declare const s: string;
    #|export const okStringIntoMixedIntersection: { length: number } & { x?: number } = s;
    #|export const okLiteralIntoMixedIntersection: { length: number } & { x?: number } = "abc";
    #|export const badNumberIntoMixedIntersection: { length: number } & { x?: number } = 5;
    #|export const okStringNumericSlots: { length: number; [n: number]: string } & { charAt: any } = "abc";
    #|export const badStringNumericSlots: { length: number; [n: number]: number } & { charAt: any } = "abc";
    #|export const badStringIndexOnPrimitive: { length: number; [k: string]: any } & { charAt: any } = s;
  assert_eq(issue_lines(src), [
    "top-level > binding `badNumberIntoMixedIntersection` init: expected `{ length: number } & { x: number | undefined }` but got `5`",
    "top-level > binding `badStringNumericSlots` init: expected `{ length: number; [x: number]: number } & { charAt: any }` but got `\"abc\" (string)`",
    "top-level > binding `badStringIndexOnPrimitive` init: expected `{ length: number; [x: string]: any } & { charAt: any }` but got `string`",
  ])
}

///|
/// An unannotated function's return type comes from its body. A `switch`
/// with a `default` clause and no `break` leaves only through its last
/// clause, so when that clause returns the function adds no `undefined`;
/// univer's `mapClass(c: number)` returned `any` instead, and every
/// `this._next = mapClass(…)` kept its declared `Nullable<number>`. A
/// module-level `const` holding a literal is that literal's base type once
/// returned, and a declarator group declares each of its names (probed: tsc
/// reports the bad cells only; `badNoDefault` is a MISS).
test "a switch and module literal consts give a function its return type (switchreturn)" {
  let src =
    #|const AL = 1;
    #|const NS = 2, AI = 3;
    #|const S1 = "s";
    #|declare function side(): void;
    #|function take(n: number) { return n; }
    #|function mapClass(c: number) { switch (c) { case AI: return AL; case 9: return NS; default: return c; } }
    #|function lastClauseFallsOff(c: number) { switch (c) { case 1: return AL; default: side(); } }
    #|function noDefault(c: number) { switch (c) { case 1: return 2; case 2: return 3; } }
    #|function withBreak(c: number) { switch (c) { case 1: break; default: return c; } return 7; }
    #|function breakFallsOut(c: number) { switch (c) { case 1: side(); break; default: return 2; } }
    #|function returnsGroupConst() { return NS; }
    #|function returnsStringConst() { return S1; }
    #|function shadowed() { const S1 = 5; return S1; }
    #|export function okSwitchReturnNarrows() { let n: number | undefined = undefined; n = mapClass(1); return take(n); }
    #|export function okGroupConstReturn() { let n: number | undefined = undefined; n = returnsGroupConst(); return take(n); }
    #|export function okBreakReturn() { const n: number = withBreak(1); return n; }
    #|export function okShadowedLocal() { const n: number = shadowed(); return n; }
    #|export function badSwitchReturnIsNumber() { const s: string = mapClass(1); return s; }
    #|export function badConstReturnWidens() { const lit: "s" = returnsStringConst(); return lit; }
    #|export function badLastClauseFallsOff() { const n: number = lastClauseFallsOff(1); return n; }
    #|export function badNoDefault() { const n: number = noDefault(1); return n; }
    #|export function badGroupConstRead() { const s: string = NS; return s; }
    #|export function badBreakFallsOut() { let n: number | undefined = undefined; n = breakFallsOut(1); return take(n); }
  assert_eq(issue_lines(src), [
    "function badSwitchReturnIsNumber > binding `s` init: expected `string` but got `number`",
    "function badConstReturnWidens > binding `lit` init: expected `\"s\" (string)` but got `string`",
    "function badLastClauseFallsOff > binding `n` init: type `number | undefined` is not assignable to type `number`",
    "function badGroupConstRead > binding `s` init: expected `string` but got `number`",
    "function badBreakFallsOut > call `take` arg[0]: type `number | undefined` is not assignable to type `number`",
  ])
}

///|
/// An interface extending a lib interface this checker has no member table
/// for (`Event`) has that interface's members too, so member existence
/// abstains on it, as it already did on a class with an unresolved base:
/// univer's `IPointerEvent` read `timeStamp`, `type` and `preventDefault`
/// as missing (probed: tsc accepts them). A typo through such a chain is a
/// MISS; a chain of declared interfaces still reports one.
test "an interface extending an untabled lib interface has its members (libbase)" {
  let src =
    #|export interface IEvent extends Event { deviceType: number; }
    #|export interface IUIEvent extends IEvent, UIEvent {}
    #|export interface IMouseEvent extends IUIEvent, MouseEvent { altKey: boolean; }
    #|export interface IPointerEvent extends IMouseEvent { pointerId: number; }
    #|interface Base { a: number }
    #|interface Derived extends Base { b: number }
    #|export function okLibMember(e: IEvent) { return e.type; }
    #|export function okDeepLibMember(e: IPointerEvent) { return e.timeStamp; }
    #|export function okLibMethod(e: IPointerEvent) { e.preventDefault(); }
    #|export function badDeclaredChainTypo(d: Derived) { return d.nope; }
    #|type Shape = { a: number };
    #|interface OverAlias extends Shape { b: number }
    #|interface OverUtility extends Pick<Base, "a"> { c: number }
    #|export function badAliasBaseTypo(o: OverAlias) { return o.nope; }
    #|export function badUtilityBaseTypo(o: OverUtility) { return o.nope; }
  assert_eq(issue_lines(src), [
    "function badDeclaredChainTypo > PropAccess `.nope`: property `nope` does not exist on `Derived`",
    "function badAliasBaseTypo > PropAccess `.nope`: property `nope` does not exist on `OverAlias`",
    "function badUtilityBaseTypo > PropAccess `.nope`: property `nope` does not exist on `OverUtility`",
  ])
}

///|
/// Return inference binds the module's literal `const`s, and two shapes
/// must not reach it: a written `: any` is `any` (tsc gives `f` the return
/// type `any`), and a WRITTEN block of consts is block-scoped, so its
/// `VALUE` does not replace the module's. Probed: tsc accepts both `ok…`.
test "module literal consts skip a written any and a written block (moduleconsts)" {
  let src =
    #|const ANY_VALUE: any = 1;
    #|function returnsAny() { return ANY_VALUE; }
    #|export const okWrittenAny: string = returnsAny();
    #|const VALUE = 1;
    #|{ const VALUE = "inner"; const OTHER = 2; }
    #|function returnsOuter() { return VALUE; }
    #|export const okOuterConst: number = returnsOuter();
    #|export const badOuterConst: string = returnsOuter();
  assert_eq(issue_lines(src), [
    "top-level > binding `badOuterConst` init: expected `string` but got `number`",
  ])
}

///|
/// A `@ts-ignore` / `@ts-expect-error` comment directive suppresses what
/// tsc reports on the first line after it that is neither blank nor a
/// `//` comment. Our issues carry no line, so a statement STARTING there
/// drops what it reports itself, and a directive inside a simple statement
/// drops the whole statement (probed: tsc reports exactly the `bad…` cells,
/// and `badDirectiveAfterError`, whose error sits on the line BEFORE the
/// directive, is the price of that). univer writes `//@ts-ignore` with no
/// space before `this.x = null` in `dispose()`.
test "a comment directive suppresses the statement it covers (tsdirective)" {
  let src =
    #|declare const n: number;
    #|class C {
    #|  constructor(readonly w: number) {}
    #|  okNoSpace() {
    #|    //@ts-ignore
    #|    this.w = 1;
    #|  }
    #|  okExpectError() {
    #|    // @ts-expect-error
    #|    this.w = 2;
    #|  }
    #|  badNoDirective() {
    #|    this.w = 3;
    #|  }
    #|}
    #|// @ts-ignore
    #|const okTopLevel: string = n;
    #|// @ts-ignore
    #|
    #|const okBlankLine: string = n;
    #|// @ts-ignore
    #|// a comment line in between
    #|const okCommentLineBetween: string = n;
    #|const trailing = 1; // @ts-ignore
    #|const okAfterTrailing: string = n;
    #|/* @ts-ignore */
    #|const okBlockComment: string = n;
    #|/* @ts-ignore
    #| */
    #|const badBlockFirstLine: string = n;
    #|// @ts-ignore
    #|export const okAfterNestedBody: string = ((() => { return 1; })(), n);
    #|export function okLoopHeadAfterBody(c: number) {
    #|  let i = 0;
    #|  // @ts-ignore
    #|  while (c.nope && i < 3) {
    #|    i++;
    #|  }
    #|  // @ts-ignore
    #|  for (const v of [c.nope]) {
    #|    i += v;
    #|  }
    #|  return i;
    #|}
    #|export function badMissingReturnAfterCovered(c: boolean): number {
    #|  if (c) {
    #|    return 1;
    #|  }
    #|  // @ts-ignore
    #|  const z: string = n;
    #|}
    #|export function coveredLast() {
    #|  // @ts-ignore
    #|  const z: string = n;
    #|}
    #|export function badDefaultAfterCovered(x: string = n) {
    #|  return x;
    #|}
    #|export function okAfterNestedBodyInFunction() {
    #|  // @ts-ignore
    #|  const q: string = ((() => { return 1; })(), n);
    #|  return q;
    #|}
    #|/* @ts-ignore
    #|*/ export const badBlockEndsBeforeCode: string = n;
    #|export function okInsideSimple() {
    #|  const s: number = Math.max(
    #|    // @ts-ignore
    #|    "a",
    #|    1,
    #|  );
    #|  return s;
    #|}
    #|export function badDirectiveAfterError() {
    #|  const s: string =
    #|    // @ts-ignore
    #|    n;
    #|  return s;
    #|}
    #|export function badInsideCompound(c: boolean) {
    #|  // @ts-ignore
    #|  if (c) {
    #|    const inner: string = n;
    #|    return inner;
    #|  }
    #|  return "";
    #|}
    #|export function okCompoundHead(c: number) {
    #|  // @ts-ignore
    #|  if (c.nope) {
    #|    return 1;
    #|  }
    #|  return 0;
    #|}
    #|export { C, okTopLevel, okBlankLine, okCommentLineBetween, trailing, okAfterTrailing, okBlockComment, badBlockFirstLine };
  assert_eq(issue_lines(src), [
    "function badMissingReturnAfterCovered: not all paths return a `number`", "function badDefaultAfterCovered > param `x` default: expected `string` but got `number`",
    "function badInsideCompound > binding `inner` init: expected `string` but got `number`",
    "function C.badNoDirective > assign `.w`: cannot assign to `w` because it is read-only",
    "top-level > binding `badBlockFirstLine` init: expected `string` but got `number`",
    "top-level > binding `badBlockEndsBeforeCode` init: expected `string` but got `number`",
  ])
}

///|
/// The directive reaches statements a SUB-parser reads: an arrow body in
/// parentheses (a parser over the same tokens, which shares the table) and
/// a namespace body (a fresh parse of the body's own text). The arrow sits
/// in an `if` condition: inside a simple statement, the statement around
/// it would be covered whole and the inner one would not matter.
test "a comment directive covers statements in sub-parsed bodies (tsdirective)" {
  let src =
    #|declare const n: number;
    #|export function okParenArrowInCondition() {
    #|  if ((() => {
    #|    // @ts-ignore
    #|    const x: string = n;
    #|    return true;
    #|  })()) {
    #|    return 1;
    #|  }
    #|  return 0;
    #|}
    #|export const badParenArrow = (() => {
    #|  const x: string = n;
    #|  return x;
    #|})();
    #|namespace NS {
    #|  // @ts-ignore
    #|  export const okInNamespace: string = n;
    #|  export const badInNamespace: string = n;
    #|}
    #|export { NS };
  assert_eq(issue_lines(src), [
    "top-level > binding `x` init: expected `string` but got `number`", "namespace NS > top-level > binding `badInNamespace` init: expected `string` but got `number`",
  ])
}

///|
/// The places a directive's statement is read OUTSIDE `parse_stmt`, each
/// probed against the nightly, which reports exactly the `bad…` cells:
/// each declarator of `let a = 1, b = 2` (the checker visits them one by
/// one, and each used to clear the flag the group set), a C-style `for`'s
/// init and update, the `if` of an `else if`, a block-level `using` (the
/// rebuilt declaration and the disposal generated for it, whose
/// `cannot index` is the declaration's error seen from the `finally`),
/// a `for (using …)` head, an `as` type's duplicate member, and the arrow
/// bodies a template substitution's fresh sub-parser reads.
test "a comment directive covers declarator groups, loop heads and else-if (tsdirective)" {
  let src =
    #|declare const x: unknown;
    #|type D = { [Symbol.dispose](): void };
    #|declare const d: D;
    #|// @ts-ignore
    #|export const okAsDup = x as { a: string; a: string };
    #|export const badAsDup = x as { b: string; b: string };
    #|// @ts-ignore
    #|export let okGroupA: string = 1, okGroupB: string = 2;
    #|export let badGroupA: string = 1, okGroupC = 2;
    #|export let okGroupLaterA = 1,
    #|  // @ts-ignore
    #|  okGroupLaterB: string = 2;
    #|export let badGroupLaterA = 1,
    #|  badGroupLaterB: string = 2;
    #|export function okElseIf(c: boolean) {
    #|  if (c) {
    #|    return 0;
    #|  } else
    #|  // @ts-ignore
    #|  if (1 === "x") {
    #|    const badInElseIfBody: string = 1;
    #|    return badInElseIfBody;
    #|  }
    #|  return 2;
    #|}
    #|export function okForHead() {
    #|  // @ts-ignore
    #|  for (let a: string = 1, b: string = 2; ;) { break; }
    #|}
    #|export function badForBody() {
    #|  // @ts-ignore
    #|  for (let a: string = 1; ;) {
    #|    const badBodyLine: string = 2;
    #|    break;
    #|  }
    #|}
    #|export function okUsing() {
    #|  // @ts-ignore
    #|  using u: D = 1;
    #|}
    #|export function okUsingGroup() {
    #|  // @ts-ignore
    #|  using u1: D = d, u2: D = 2;
    #|}
    #|export function badUsing() {
    #|  using v: D = 3;
    #|}
    #|export function okForUsing() {
    #|  // @ts-ignore
    #|  for (using w: D = 4; ;) { break; }
    #|}
    #|declare function tag(s: TemplateStringsArray, ...v: unknown[]): string;
    #|export const okTemplate = `${(() => {
    #|  // @ts-ignore
    #|  const okInTemplate: string = 3;
    #|  const badInTemplate: string = 4;
    #|  return okInTemplate + badInTemplate;
    #|})()}`;
    #|export const okTagged = tag`${(() => {
    #|  // @ts-ignore
    #|  const okInTagged: string = 5;
    #|  const badInTagged: string = 6;
    #|  return okInTagged + badInTagged;
    #|})()}`;
  assert_eq(issue_lines(src), [
    "function okElseIf > binding `badInElseIfBody` init: expected `string` but got `number`",
    "function badForBody > binding `badBodyLine` init: expected `string` but got `number`",
    "function badUsing > binding `v` init: expected `D` but got `number`", "function badUsing > index access: cannot index into `number`",
    "top-level: duplicate identifier `b`", "top-level > binding `badGroupA` init: expected `string` but got `number`",
    "top-level > binding `badGroupLaterB` init: expected `string` but got `number`",
    "top-level > binding `badInTemplate` init: expected `string` but got `number`",
    "top-level > binding `badInTagged` init: expected `string` but got `number`",
  ])
}

///|
/// The same through a JSX payload, which a fresh sub-parser reads over the
/// payload's own text and line table.
test "a comment directive covers a statement in a JSX payload (tsdirective)" {
  let src =
    #|export const okJsx = <div>{(() => {
    #|  // @ts-ignore
    #|  const okInPayload: string = 1;
    #|  const badInPayload: string = 2;
    #|  return okInPayload + badInPayload;
    #|})()}</div>;
  assert_eq(
    check_source(src, true).split("\n").map(fn(l) { l.to_owned() }).collect(),
    [
      "top-level > binding `badInPayload` init: expected `string` but got `number`",
    ],
  )
}

///|
/// A line ends at LF, CR, LS or PS (probed: in each spelling the directive
/// covers the next line and only `…Real` reports), so a block comment's
/// last line is found after a CR too. A line holding only a no-break space,
/// or nothing but an LS or PS, is not blank to the pairing: the directive
/// covers nothing there, and both declarations report.
test "a comment directive pairs across every line terminator (tsdirective)" {
  let cells = [
    ("cr", "\r"),
    ("crlf", "\r\n"),
    ("ls", "\u{2028}"),
    ("ps", "\u{2029}"),
  ]
  for cell in cells {
    let (name, eol) = cell
    let src = "export const ok1 = 1;" +
      eol +
      "// @ts-ignore" +
      eol +
      "export const \{name}Bad: string = 1;" +
      eol +
      "export const \{name}Real: string = 2;" +
      eol
    assert_eq(issue_lines(src), [
      "top-level > binding `\{name}Real` init: expected `string` but got `number`",
    ])
  }
  let block = "export const ok1 = 1;\r/* a\r  @ts-ignore */\rexport const blBad: string = 1;\rexport const blReal: string = 2;\r"
  assert_eq(issue_lines(block), [
    "top-level > binding `blReal` init: expected `string` but got `number`",
  ])
  let block_ends = "export const ok1 = 1;\r/* @ts-ignore\r*/ export const badCrBlockEnds: string = 1;\r"
  assert_eq(issue_lines(block_ends), [
    "top-level > binding `badCrBlockEnds` init: expected `string` but got `number`",
  ])
  let nbsp = "// @ts-ignore\n\u{00A0}\nexport const nbspBad: string = 1;\n"
  assert_eq(issue_lines(nbsp), [
    "top-level > binding `nbspBad` init: expected `string` but got `number`",
  ])
  let ls_blank = "export const ok1 = 1;\u{2028}// @ts-ignore\u{2028}\u{2028}export const lsBlankBad: string = 1;\u{2028}export const lsReal: string = 2;\n"
  assert_eq(issue_lines(ls_blank), [
    "top-level > binding `lsBlankBad` init: expected `string` but got `number`",
    "top-level > binding `lsReal` init: expected `string` but got `number`",
  ])
}

///|
/// A run of directive lines pairs every one of them with the same code
/// line, found by one backward pass over the lines.
test "a run of comment directives covers the line after it (tsdirective)" {
  let src = "// @ts-ignore\n".repeat(50) +
    "export const okRun: string = 1;\nexport const badRun: string = 2;\n"
  assert_eq(issue_lines(src), [
    "top-level > binding `badRun` init: expected `string` but got `number`",
  ])
}

///|
/// A binder no argument gives a candidate for stays `any` after solving,
/// and a callback checked against a formal built from it read `s` as
/// `Sub<any>`, whose `next(value: any)` needs an argument. The written type
/// argument (`new Obs<void>`, `take<void>`) and the declared type the call
/// is assigned to (`const c: Obs<void>`) say `Sub<void>`, whose `next`
/// does not (probed: tsc accepts every `ok…`, univer's `new
/// Observable<void>((observer) => observer.next())`). The written type
/// arguments are still checked: `<number>` reports the missing argument.
/// With no type argument and no context tsc infers `unknown` and reports,
/// and so would a declared `Obs<number>`; both are MISSes here. Only the
/// formal's PARAMETERS are erased: the first version erased the whole
/// formal and lost the arity of `(x, y) => ""` against a call signature
/// that supplies one argument (`genericCallWithOverloadedFunctionTypedArguments2`).
test "a callback over an unsolved binder is not typed with any (unsolvedcallback)" {
  let src =
    #|declare class Sub<T> { next(value: T): void; }
    #|declare class Obs<T> { constructor(subscribe?: (s: Sub<T>) => void); }
    #|declare function take<T>(cb: (s: Sub<T>) => void): T;
    #|declare function takeWith<T>(x: T, cb: (s: Sub<T>) => void): T;
    #|export function okExplicitVoid() { return new Obs<void>((s) => { s.next(); }); }
    #|export function badExplicitNumber() { return new Obs<number>((s) => { s.next(); }); }
    #|export function okContextual() { const c: Obs<void> = new Obs((s) => { s.next(); }); return c; }
    #|export function okCallExplicitVoid() { return take<void>((s) => { s.next(); }); }
    #|export function badCallExplicitNumber() { return take<number>((s) => { s.next(); }); }
    #|export function badSolvedFromArgument() { return takeWith(1, (s) => { s.next(); }); }
    #|declare const av: any;
    #|export function badRealAny() { return takeWith(av, (s) => { s.next(); }); }
    #|declare function over<T>(cb: { (x: T): string; (x: T, y?: T): string }): T;
    #|export function badOverloadArity() { return over((x, y) => ""); }
    #|export function okOverloadArity() { return over((x) => ""); }
    #|declare function single<T>(cb: (x: T) => string): T;
    #|export function badSingleArity() { return single((x, y) => ""); }
    #|declare function takeOpt<T>(cb: (s: Sub<T>, extra?: number) => void): T;
    #|export function okMetaVoid() { return takeOpt<void>((s) => { s.next(); }); }
    #|export function badMetaNumber() { return takeOpt<number>((s) => { s.next(); }); }
    #|declare function accept<T>(cb: (...xs: T[]) => void): T;
    #|export function okRestCallback() { return accept((a, b) => {}); }
    #|declare function acceptFixed<T>(cb: (x: T, ...rest: T[]) => void): T;
    #|export function okFixedThenRest() { return acceptFixed((a, b, c) => {}); }
  assert_eq(issue_lines(src), [
    "function badExplicitNumber > call `next`: expected 1 argument(s), got 0", "function badCallExplicitNumber > call `next`: expected 1 argument(s), got 0",
    "function badSolvedFromArgument > call `next`: expected 1 argument(s), got 0",
    "function badRealAny > call `next`: expected 1 argument(s), got 0", "function badOverloadArity > call `over` arg[0]: expected `{ <call>: (any) => string; <call>: (any, any | undefined) => string }` but the function value requires 2 argument(s); a target call signature accepts only 1",
    "function badSingleArity > call `single` arg[0]: expected `(any) => string` but the function value requires 2 argument(s); a target call signature accepts only 1",
    "function badMetaNumber > call `next`: expected 1 argument(s), got 0",
  ])
}

///|
/// `xs.map(cb)` against an array of tuples: tsc types the callback's
/// returns by the tuple element, so `[r.a, r.b]` is `[number, number]`.
/// Inferred with no expected type it is `number[]`, and every univer
/// `const removed: [number, number][] = ranges.map((r) => [r.startRow,
/// r.endRow])` was reported. A literal of the wrong length or element type
/// still reports (probed: tsc gives TS2322 on exactly the `bad…` cells). A
/// block body's `const`s are typed first, and a block holding any other
/// statement (a loop may hide a `return;`) is left to the plain check.
test "a map callback's array literal is typed by the tuple it fills (maptuple)" {
  let src =
    #|interface R { a: number; b: number }
    #|declare const rs: R[];
    #|declare const flag: boolean;
    #|export const okMapTuple: [number, number][] = rs.map((r) => [r.a, r.b]);
    #|export const okMapTupleCond: [number, number][] = rs.map((r) => (flag ? [r.a, r.b] : [r.b, r.a]));
    #|export const okMapTupleBlock: [number, number][] = rs.map((r) => { return [r.a, r.b]; });
    #|export const badMapTupleArity: [number, number][] = rs.map((r) => [r.a]);
    #|export const badMapTupleType: [number, string][] = rs.map((r) => [r.a, r.b]);
    #|declare const ns: number[];
    #|export const okLocalConst: [number, number][] = ns.map((n) => { const m = n + 1; return [n, m]; });
    #|export const badLocalConst: [number, number][] = ns.map((n) => { const text = "bad"; return [n, text]; });
    #|export const badLoopReturn: [number, number][] = ns.map((n) => { while (n < 0) { return; } return [n, n]; });
    #|export const okGroup: [number, number][] = ns.map((n) => { const a = n, b = n + 1; return [a, b]; });
    #|export const badGroup: [number, number][] = ns.map((n) => { const a = n, b = "x"; return [a, b]; });
    #|export const okLet: [number, number][] = ns.map((n) => { let a = n; return [a, a]; });
    #|export const okLetGroup: [number, number][] = ns.map((n) => { let a = n, b = n; return [a, b]; });
    #|export const badLetWidened: [number, "x"][] = ns.map((n) => { let s = "x"; return [n, s]; });
  assert_eq(issue_lines(src), [
    "top-level > binding `badMapTupleArity` init: expected `[number, number][]` but got `number[][]`",
    "top-level > binding `badMapTupleType` init: expected `[number, string][]` but got `number[][]`",
    "top-level > binding `badLocalConst` init: expected `[number, number][]` but got `(number | \"bad\" (string))[][]`",
    "top-level > binding `badLoopReturn` init: expected `[number, number][]` but got `number[][]`",
    "top-level > binding `badGroup` init: expected `[number, number][]` but got `(number | \"x\" (string))[][]`",
    "top-level > binding `badLetWidened` init: expected `[number, \"x\" (string)][]` but got `(number | string)[][]`",
  ])
}

///|
/// `x === y` with a `y` that cannot be nullish narrows `x` on the equal
/// side (probed: tsc reports exactly the `bad…` cells). univer's
/// `_getReusableScrollCacheState` guards `canvas.getPixelRatio()` with
/// `canvas === previous.canvas`.
test "equality with a non-nullish value narrows (eqnonnullish)" {
  let src =
    #|// @strict: true
    #|
    #|// `x === y` narrows `x` when `y` cannot be nullish: on the equal side `x`
    #|// is not nullish either. The not-equal side learns nothing, a nullable `y`
    #|// narrows nothing, and loose `==` against a `y` that may be `undefined`
    #|// leaves `x` possibly `null` or `undefined`.
    #|
    #|interface C { w(): number }
    #|interface P { canvas: C; ok: boolean }
    #|declare const prev: P | undefined;
    #|
    #|export function okAfterGuard(canvas: C | undefined) {
    #|  if (!(prev?.ok && canvas === prev.canvas && canvas.w() === 1)) return undefined;
    #|  return canvas.w();
    #|}
    #|export function okInConjunction(canvas: C | undefined, p: P) {
    #|  return canvas === p.canvas && canvas.w();
    #|}
    #|export function okIf(canvas: C | undefined, p: P) {
    #|  if (canvas === p.canvas) { return canvas.w(); }
    #|  return 0;
    #|}
    #|export function okNotEqual(canvas: C | undefined, p: P) {
    #|  if (canvas !== p.canvas) { return 0; }
    #|  return canvas.w();
    #|}
    #|export function okReversed(canvas: C | undefined, p: P) {
    #|  if (p.canvas == canvas) { return canvas.w(); }
    #|  return 0;
    #|}
    #|export function badElse(canvas: C | undefined, p: P) {
    #|  if (canvas === p.canvas) { return 0; }
    #|  return canvas.w();
    #|}
    #|export function badNullableOther(canvas: C | undefined, q: C | undefined) {
    #|  if (canvas === q) { return canvas.w(); }
    #|  return 0;
    #|}
    #|export function badLoose(canvas: C | null | undefined, q: C | undefined) {
    #|  if (canvas == q) { return canvas.w(); }
    #|  return 0;
    #|}
  assert_eq(issue_lines(src), [
    "function badElse > call `w`: object is possibly `undefined`", "function badNullableOther > call `w`: object is possibly `undefined`",
    "function badLoose > call `w`: object is possibly `undefined`",
  ])
}

///|
/// `"k" in x` with no union member declaring `k` is `x & Record<"k",
/// unknown>`; a member whose members are not all known (a lib DOM type)
/// keeps the union as it was (excalidraw's `"clipboardData" in event`).
test "in on a union that never declares the key adds it (inrecord)" {
  let src =
    #|// @strict: true
    #|
    #|// `"k" in x` when no member of `x`'s union declares `k` narrows `x` to
    #|// `x & Record<"k", unknown>` (TS 4.9), so `x.k` reads as `unknown`. A
    #|// member the check cannot rule out keeps the key: a lib DOM type, which
    #|// declares it, wins the usual filter instead.
    #|
    #|interface A { a: number }
    #|interface B { b: string }
    #|type AB = A | B;
    #|
    #|export function okInUndeclared(p: AB | undefined): boolean {
    #|  return !!p && "generated" in p && Boolean(p.generated);
    #|}
    #|export function okInUndeclaredSingle(p: A) {
    #|  if ("extra" in p) { return p.extra; }
    #|  return undefined;
    #|}
    #|export function okUnionElse(p: A | B) {
    #|  if (!("k" in p)) { return 0; }
    #|  return p.k;
    #|}
    #|export function okUnionKeepsOwn(p: A | B) {
    #|  if ("k" in p && "a" in p) { return p.a; }
    #|  return 0;
    #|}
    #|export function okLibUnion(event: ClipboardEvent | DragEvent) {
    #|  if ("clipboardData" in event && event.clipboardData) {
    #|    return event.clipboardData.getData("text");
    #|  }
    #|  return "";
    #|}
    #|export function badInUndeclaredElse(p: A) {
    #|  if ("extra" in p) { return 0; }
    #|  return p.extra;
    #|}
    #|export function badUnionUnknown(p: A | B): number {
    #|  if ("k" in p) { const n: number = p.k; return n; }
    #|  return 0;
    #|}
    #|export function badUnionOtherMember(p: A | B) {
    #|  if ("k" in p) { return p.a; }
    #|  return 0;
    #|}
  assert_eq(issue_lines(src), [
    "function badInUndeclaredElse > PropAccess `.extra`: property `extra` does not exist on `A`",
    "function badUnionUnknown > binding `n` init: expected `number` but got `unknown`",
  ])
}

///|
/// A string destructures as its characters (univer's `_colorWithOpacity`:
/// `const [, r, g, b] = hex`).
test "a string destructures as strings (stringdestructure)" {
  let src =
    #|// @strict: true
    #|
    #|// A string destructures as its characters: each element is a `string`,
    #|// and a rest element is a `string[]`.
    #|
    #|declare const hex: string;
    #|
    #|export function okStringDestructure() {
    #|  const [, r, g] = hex;
    #|  return Number.parseInt(r + g, 16);
    #|}
    #|export function okStringDestructureRest() {
    #|  const [first, ...rest] = hex;
    #|  const s: string = first;
    #|  const t: string[] = rest;
    #|  return s + t.join("");
    #|}
    #|export function okLiteralDestructure() {
    #|  const [c] = "ab";
    #|  const s: string = c;
    #|  return s;
    #|}
    #|export function badStringDestructure() {
    #|  const [a] = hex;
    #|  const n: number = a;
    #|  return n;
    #|}
    #|export function badStringRest() {
    #|  const [, ...rest] = hex;
    #|  const n: number[] = rest;
    #|  return n;
    #|}
  assert_eq(issue_lines(src), [
    "function badStringDestructure > binding `n` init: expected `number` but got `string`",
    "function badStringRest > binding `n` init: expected `number[]` but got `string[]`",
  ])
}

///|
/// An unannotated class field initialized by `new Map<K, V>()` (or a
/// `Set`) is that instance: univer's `private _scrollCacheStates = new
/// Map<string, IScrollCacheState | null>()` read as `any`, so the `canvas
/// === previous.canvas` guard after `const previous =
/// this._scrollCacheStates.get(key)` had nothing to narrow by. The
/// top-level cells are MISSes: typing every `new Map<K, V>()` exposed
/// relations this checker does not have yet.
test "new Map with written type arguments is typed (newcollection)" {
  let src =
    #|// @strict: true
    #|// @target: esnext
    #|
    #|// `new Map<K, V>()`, `new Set<T>()` and their weak variants are instances
    #|// of the written arguments, at top level and as an unannotated class
    #|// field's initializer; `get` adds `undefined`. A field holding a `Set`
    #|// or a `WeakMap` is the same instance as a `Map` field.
    #|
    #|interface St { ok: boolean }
    #|
    #|const q1 = new Map<string, number>();
    #|export const okMapGet: number | undefined = q1.get("k");
    #|export const badMapGet: string = q1.get("k");
    #|
    #|const q2 = new Set<string>();
    #|export const okSetHas: boolean = q2.has("a");
    #|export const badSetHas: string = q2.has("a");
    #|
    #|const w = new WeakMap<object, number>();
    #|export const okWeakGet: number | undefined = w.get({});
    #|export const badWeakGet: string | undefined = w.get({});
    #|
    #|export class Holder {
    #|  private _m = new Map<string, St | null>();
    #|  private _s = new Set<string>();
    #|  okField(k: string): St | null | undefined { return this._m.get(k); }
    #|  badField(k: string): number { return this._m.get(k); }
    #|  okSetField(k: string): boolean { return this._s.has(k); }
    #|  badSetField(k: string): string { return this._s.has(k); }
    #|}
    #|export class Guarded {
    #|  private _states = new Map<string, St | null>();
    #|  okEqualityAfterLookup(key: string, cur: St | undefined) {
    #|    const previous = this._states.get(key);
    #|    if (!(previous?.ok && cur === previous)) return false;
    #|    return cur.ok;
    #|  }
    #|}
  assert_eq(issue_lines(src), [
    "function Holder.badField > return: type `St | null | undefined` is not assignable to type `number`",
    "function Holder.badSetField > return: expected `string` but got `boolean`",
  ])
}

///|
/// A function declaration in a body is hoisted, at each of the places a
/// body is checked: a function, a function expression, a contextually
/// typed arrow, a bare block and a loop body, and an `if` branch. Unhoisted, `later(key)` was `any` and `s.body =
/// later(key)` kept `s.body`'s declared `Top | undefined` (effect's
/// `revivePersisted`).
test "function declarations hoist in bodies (hoistfn)" {
  let src =
    #|// @strict: true
    #|
    #|// A function declaration in a body is hoisted: a call made before it, or
    #|// from a function declared before it, sees its signature. After
    #|// `s.body = g(k)` with `g(k): Top`, `s.body` is a `Top`.
    #|
    #|interface Top { t: number }
    #|declare function make(k: string): Top;
    #|class Slot { body: Top | undefined; constructor(readonly key: string) {} }
    #|declare const slots: Slot[];
    #|
    #|export function okHoistedInNested(): Top {
    #|  const slots = new Map<string, Slot>();
    #|  function resolve(key: string): Top {
    #|    let slot = slots.get(key);
    #|    if (slot === undefined) { slot = new Slot(key); }
    #|    slot.body = later(key);
    #|    return slot.body;
    #|  }
    #|  function later(k: string): Top { return make(k); }
    #|  return resolve("a");
    #|}
    #|export function okHoistedSimple(s: Slot): Top {
    #|  s.body = later2("k");
    #|  return s.body;
    #|  function later2(k: string): Top { return make(k); }
    #|}
    #|export function okHoistedInArrow() {
    #|  const f = (s: Slot): Top => {
    #|    s.body = later3("k");
    #|    return s.body;
    #|    function later3(k: string): Top { return make(k); }
    #|  };
    #|  return f;
    #|}
    #|export const okHoistedInFunctionExpression = function (s: Slot): Top {
    #|  s.body = later5("k");
    #|  return s.body;
    #|  function later5(k: string): Top { return make(k); }
    #|};
    #|export function okHoistedInBlock(s: Slot, c: boolean): Top {
    #|  if (c) {
    #|    s.body = later6("k");
    #|    return s.body;
    #|    function later6(k: string): Top { return make(k); }
    #|  }
    #|  return make("x");
    #|}
    #|export const okHoistedInCallback: Top[] = slots.map((s) => {
    #|  s.body = later7("k");
    #|  const t: Top = s.body;
    #|  return t;
    #|  function later7(k: string): Top { return make(k); }
    #|});
    #|export function okHoistedInBareBlock(s: Slot): Top {
    #|  {
    #|    s.body = later8("k");
    #|    const t: Top = s.body;
    #|    return t;
    #|    function later8(k: string): Top { return make(k); }
    #|  }
    #|}
    #|export function okHoistedInLoop(s: Slot): Top {
    #|  while (true) {
    #|    s.body = later9("k");
    #|    const t: Top = s.body;
    #|    return t;
    #|    function later9(k: string): Top { return make(k); }
    #|  }
    #|}
    #|export function badHoistedReturnUsed(s: Slot): string {
    #|  s.body = later4("k");
    #|  return s.body;
    #|  function later4(k: string): Top { return make(k); }
    #|}
  assert_eq(issue_lines(src), [
    "function badHoistedReturnUsed > return: expected `string` but got `Top`",
  ])
}

///|
/// A function type's return is compared structurally, and `Map` / `Set`
/// are their readonly views: `() => { a: number }` against `() => A` was
/// reported on main, and effect's `makeHooks(() => ({ occurrences }), …)`
/// once `new Map<K, V>()` was typed.
test "a function type's return is structural (fnreturnstruct)" {
  let src =
    #|// @strict: true
    #|// @target: esnext
    #|
    #|// A function type's return is compared structurally: `() => { a: number }`
    #|// is a `() => A` for `interface A { a: number }`. A mutable `Map` or `Set`
    #|// is its readonly view, there and anywhere else.
    #|
    #|interface A { a: number }
    #|interface RO { readonly r: ReadonlyMap<string, number> }
    #|
    #|declare const g: () => { a: number };
    #|export const okPlain: () => A = g;
    #|declare const g2: () => { r: Map<string, number> };
    #|export const okMapReturn: () => RO = g2;
    #|declare const g3: () => Map<string, number>;
    #|export const okMapToReadonly: () => ReadonlyMap<string, number> = g3;
    #|declare const g4: () => Set<string>;
    #|export const okSetToReadonly: () => ReadonlySet<string> = g4;
    #|declare const g5: () => { a: string };
    #|export const badPlain: () => A = g5;
    #|
    #|interface Hooks<In, Out> { get: () => Out; update: (i: In) => void }
    #|declare function makeHooks<In, Out>(get: () => Out, update: (i: In) => void): Hooks<In, Out>;
    #|interface FS { readonly occurrences: ReadonlyMap<string, number> }
    #|export function okHooks(): Hooks<string, FS> {
    #|  const occurrences = new Map<string, number>();
    #|  return makeHooks(() => ({ occurrences }), (w: string) => { occurrences.set(w, 1); });
    #|}
    #|class Source { tag = 1; }
    #|class Target { tag = 1; required(): number { return 1; } }
    #|declare const gs: () => Source;
    #|export const badClassMethod: () => Target = gs;
    #|declare const gt: () => Target;
    #|export const okClassSubtype: () => Source = gt;
  assert_eq(issue_lines(src), [
    "top-level > binding `badPlain` init: expected `() => A` but got `() => { a: string }`",
    "top-level > binding `badClassMethod` init: expected `() => Target` but got `() => Source`",
  ])
}

///|
/// A get-or-create callback's return reads the reassigned `let` as
/// unknown rather than by its `get` initializer (effect's
/// `layerBackingMemory`).
test "a reassigned let does not type a callback's return (reassignedreturn)" {
  let src =
    #|// @strict: true
    #|
    #|// A local callback's return type comes from its body, and a `let` it
    #|// assigns again (get-or-create) is not read by its initializer: here the
    #|// `undefined` from `get` is gone by the `return`.
    #|
    #|declare function sync<A>(f: () => A): A;
    #|declare function later<A>(f: (n: number) => A): A;
    #|
    #|export const okGetOrCreate = sync(() => {
    #|  const stores = new Map<string, Map<string, number>>();
    #|  const getStore = (id: string) => {
    #|    let store = stores.get(id);
    #|    if (store === undefined) {
    #|      store = new Map<string, number>();
    #|      stores.set(id, store);
    #|    }
    #|    return store;
    #|  };
    #|  return {
    #|    make: (id: string) =>
    #|      later((n) => {
    #|        const map = getStore(id);
    #|        return { clear: () => map.clear(), n };
    #|      })
    #|  };
    #|});
  assert_eq(issue_lines(src), [])
}

///|
/// A target ending in a rest parameter accepts a source of any length, for
/// functions and constructors (univer's `UnitCtor = new (...args: any[])
/// => UnitModel`, which `new () => UnitModel` was reported against).
test "a rest-parameter target accepts any arity (resttarget)" {
  let src =
    #|// @strict: true
    #|
    #|// A target ending in a rest parameter accepts a source of any length, for
    #|// a function type and a constructor type alike: each source parameter past
    #|// the target's fixed ones takes the rest's element type.
    #|
    #|class U { u = 1 }
    #|type UnitCtor = new (...args: any[]) => U;
    #|declare function take(ctor: UnitCtor): void;
    #|
    #|declare const c0: new () => U;
    #|export const okCtorNone: UnitCtor = c0;
    #|export function okCtorArg() { take(c0); }
    #|declare const c2: new (a: number, b: string) => U;
    #|export const okCtorTwo: UnitCtor = c2;
    #|declare const f2: (a: number, b: string) => U;
    #|export const okFnRest: (...args: any[]) => U = f2;
    #|declare const f1: (a: number) => U;
    #|export const okRestElem: (...args: number[]) => U = f1;
    #|
    #|declare const cx: new () => number;
    #|export const badCtorReturn: UnitCtor = cx;
    #|export const badRestFixed: (x: string, ...rest: any[]) => U = f1;
    #|export const badRestElem: (...args: number[]) => U = f2;
    #|declare const cr: new (...args: number[]) => { a: number; b: number };
    #|export const okCtorBothRest: new (...args: number[]) => { a: number } = cr;
    #|declare const cs: new (...args: string[]) => { a: number };
    #|export const badCtorBothRest: new (...args: number[]) => { a: number } = cs;
  assert_eq(issue_lines(src), [
    "top-level > binding `badCtorReturn` init: expected `new (...) => U` but got `new (...) => number`",
    "top-level > binding `badRestFixed` init: expected `(string, type) => U` but got `(number) => U`",
    "top-level > binding `badRestElem` init: expected `(type) => U` but got `(number, string) => U`",
    "top-level > binding `badCtorBothRest` init: expected `new (...) => { a: number }` but got `new (...) => { a: number }`",
  ])
}

///|
/// `x = a ?? b` with a `b` that cannot be nullish narrows a `V | undefined`
/// binding to `V`, as tsc does (probed: it reports exactly the `bad…`
/// cell). univer's `LanguageDetector.detect` assigns
/// `LANG_MAP_TO_HYPHEN_LANG[francLang] ?? Lang.UNKNOWN` to a `Map.get`
/// result and returns it, and the left read is `any` here.
test "assigning a coalesce with a never-nullish right side narrows (coalesceassign)" {
  let src =
    #|// @strict: true
    #|enum Lang { A = "a", UNKNOWN = "unknown" }
    #|const M: Record<string, Lang> = { a: Lang.A };
    #|export function okNarrowedByCoalesce(m: Map<string, Lang>, k: string): Lang {
    #|  let lang = m.get(k);
    #|  if (lang) { return lang; }
    #|  lang = M[k] ?? Lang.UNKNOWN;
    #|  m.set(k, lang);
    #|  return lang;
    #|}
    #|export function okCoalesceLiteral(m: Map<string, string>, k: string): string {
    #|  let v = m.get(k);
    #|  v = v ?? "none";
    #|  return v;
    #|}
    #|export function okCoalesceObject(m: Map<string, { a: number }>, k: string): { a: number } {
    #|  let v = m.get(k);
    #|  v = v ?? { a: 1 };
    #|  return v;
    #|}
    #|const S: Record<string, string> = {};
    #|const O: Record<string, { a: number }> = {};
    #|export function okRecordLiteral(m: Map<string, string>, k: string): string {
    #|  let v = m.get(k);
    #|  v = S[k] ?? "none";
    #|  return v;
    #|}
    #|export function okRecordObject(m: Map<string, { a: number }>, k: string): { a: number } {
    #|  let v = m.get(k);
    #|  v = O[k] ?? { a: 1 };
    #|  return v;
    #|}
    #|export function badCoalesceNullable(m: Map<string, string>, k: string, d: string | undefined): string {
    #|  let v = m.get(k);
    #|  v = v ?? d;
    #|  return v;
    #|}
  assert_eq(issue_lines(src), [
    "function badCoalesceNullable > return: type `string | undefined` is not assignable to type `string`",
  ])
}

///|
/// `new Map<K, V>()` as a field's initializer is the lib `Map` only when
/// `Map` is not a value the module binds: with `const Map = CustomMap` it is
/// a `CustomMap` (probed: tsc accepts `this._m.hello()`).
test "a value named Map shadows the lib collection (newcollectionshadow)" {
  let src =
    #|// @strict: true
    #|class CustomMap<K, V> { hello(): string { return "hi"; } }
    #|const Map = CustomMap;
    #|export class Holder {
    #|  private _m = new Map<string, number>();
    #|  okUse(): string { return this._m.hello(); }
    #|}
  assert_eq(issue_lines(src), [])
}

///|
/// A closure's copy of a module-level binding has no declared slot of its
/// own, so an assignment inside the closure is judged against the
/// binding's DECLARED type rather than against what the enclosing body had
/// narrowed it to (probed: tsc accepts `dpi_cache = null` in the arrow
/// after `dpi_cache = i`, and still reports a `string`).
test "a closure assigns a module binding at its declared type (closuremoduleassign)" {
  let src =
    #|// @strict: true
    #|type Nullable<T> = T | null | undefined | void;
    #|let dpi_cache: Nullable<number>;
    #|export function okGetDPI(): number {
    #|  if (dpi_cache) { return dpi_cache; }
    #|  let i = 56;
    #|  dpi_cache = i;
    #|  setTimeout(() => { dpi_cache = null; }, 10);
    #|  return i;
    #|}
    #|let plain: number | null = null;
    #|export function okPlain(): number {
    #|  plain = 1;
    #|  setTimeout(() => { plain = null; }, 10);
    #|  return 1;
    #|}
    #|export function badClosure(): number {
    #|  plain = 1;
    #|  setTimeout(() => { plain = "x"; }, 10);
    #|  return 1;
    #|}
  assert_eq(issue_lines(src), [
    "function badClosure > assign `plain`: expected `number | null` but got `string`",
  ])
}

///|
/// TS2790: `delete` needs an operand whose type admits `undefined`. An
/// alias counts by what it expands to, and `unknown` and `any` admit it;
/// `null` and `void` do not (probed cell by cell).
test "delete through an alias that admits undefined (deletealias)" {
  let src =
    #|// @strict: true
    #|type Nullable<T> = T | null | undefined | void;
    #|type Maybe<T> = T | undefined;
    #|type OnlyNull<T> = T | null;
    #|type V<T> = T | void;
    #|interface I {
    #|  a: Nullable<number>;
    #|  b: Maybe<number>;
    #|  c: OnlyNull<number>;
    #|  d: V<number>;
    #|  e: number | void;
    #|  f: unknown;
    #|  g: any;
    #|}
    #|declare const o: I;
    #|export function okA() { delete o.a; }
    #|export function okB() { delete o.b; }
    #|export function badC() { delete o.c; }
    #|export function badD() { delete o.d; }
    #|export function badE() { delete o.e; }
    #|export function okF() { delete o.f; }
    #|export function okG() { delete o.g; }
    #|export class ScrollTimer {
    #|  private _f: Nullable<(x?: number) => void>;
    #|  okDispose() { delete this._f; }
    #|}
    #|type Unk = unknown;
    #|type An = any;
    #|interface J { u: Unk; a: An }
    #|declare const j: J;
    #|export function okUnknownAlias() { delete j.u; }
    #|export function okAnyAlias() { delete j.a; }
    #|type UnkAlias = unknown;
    #|interface K { u: UnkAlias | number; w: unknown | number }
    #|declare const k: K;
    #|export function okUnknownUnionAlias() { delete k.u; }
    #|export function okUnknownUnion() { delete k.w; }
  assert_eq(issue_lines(src), [
    "function badC > delete: the operand of a `delete` operator must be optional",
    "function badD > delete: the operand of a `delete` operator must be optional",
    "function badE > delete: the operand of a `delete` operator must be optional",
  ])
}

///|
/// TS2774 is not reported when the tested function is used inside the
/// guarded region: the `if` body, the ternary's true branch, or the right
/// of `&&` (tsc's `isSymbolUsedInConditionBody`).
test "a function tested and then used is not TS2774 (fnguardused)" {
  let src =
    #|// @strict: true
    #|declare function f(): number;
    #|declare const g: () => number;
    #|export function okUsedAnd() { return f && f(); }
    #|export function badUnusedAnd() { return f && 1; }
    #|export function okUsedIf() { if (f) { f(); } }
    #|export function okUsedTernary() { return f ? f() : 0; }
    #|export function badUnusedIf() { if (g) { return 1; } return 0; }
    #|export function okUsedLater() { if (g) { const h = g; return h; } return 0; }
    #|export function okUsedInAndOfIf() { if (g && g()) { return 1; } return 0; }
    #|declare const ready: boolean;
    #|export function okCompoundIf() { if (f && ready) { f(); } }
    #|export function okCompoundIfRight() { if (ready && f) { f(); } }
    #|export function badCompoundIfUnused() { if (f && ready) { return 1; } return 0; }
    #|export function badCompoundTernary() { return f && ready ? f() : 0; }
  assert_eq(issue_lines(src), [
    "function badUnusedAnd > condition: this condition will always return true since this function is always defined: did you mean to call it instead?",
    "function badUnusedIf > condition: this condition will always return true since this function is always defined: did you mean to call it instead?",
    "function badCompoundIfUnused > condition: this condition will always return true since this function is always defined: did you mean to call it instead?",
    "function badCompoundTernary > condition: this condition will always return true since this function is always defined: did you mean to call it instead?",
  ])
}

///|
/// A method implementing an interface method is compared bivariantly, and
/// an alias parameter by what it expands to: `unit: Unit` implements
/// `unit?: Unit`, a defaulted parameter implements an optional one, and a
/// callback parameter with fewer parameters implements a wider one. An
/// incompatible parameter or return still reports.
test "implements compares method parameters bivariantly (implementsbivariant)" {
  let src =
    #|// @strict: true
    #|type Unit = "day" | "millisecond";
    #|interface IK { add(value: number, unit?: Unit): IK; }
    #|export class OkDefault implements IK {
    #|  add(value: number, unit: Unit = "millisecond") { return this; }
    #|}
    #|export class OkRequired implements IK {
    #|  add(value: number, unit: Unit): IK { return this; }
    #|}
    #|interface Info { id: string }
    #|interface Opts { quiet?: boolean }
    #|type Listener = (info: Readonly<Info>, options?: Opts) => void;
    #|interface ISvc { on(listener: Listener): void; }
    #|export class OkFewerParams implements ISvc {
    #|  on(listener: (info: Info) => void): void {}
    #|}
    #|export function okAssign(a: OkRequired): IK { return a; }
    #|export class BadParam implements IK { add(value: number, unit: boolean): IK { return this as any; } }
    #|interface IN { add(value: number): number; }
    #|export class BadReturn implements IN { add(value: number): string { return ""; } }
    #|class Wrong { add(value: string): IK { return null as any; } }
    #|export function badAssign(w: Wrong): IK { return w; }
    #|interface IS { m(cb: number): void }
    #|export class BadCallableVsScalar implements IS { m(cb: () => void): void {} }
    #|interface IC { m(cb: () => void): void }
    #|export class BadScalarVsCallable implements IC { m(cb: number): void {} }
  assert_eq(issue_lines(src), [
    "function badAssign > return: expected `IK` but got `Wrong`", "class BadParam: incorrectly implements interface `IK`: method `add` of type `(number, boolean) => IK` is not assignable to `(number, Unit | undefined) => IK`",
    "class BadReturn: incorrectly implements interface `IN`: method `add` of type `(number) => string` is not assignable to `(number) => number`",
    "class BadCallableVsScalar: incorrectly implements interface `IS`: method `m` of type `(() => void) => void` is not assignable to `(number) => void`",
    "class BadScalarVsCallable: incorrectly implements interface `IC`: method `m` of type `(number) => void` is not assignable to `(() => void) => void`",
  ])
}

///|
/// The class-target method check in the function-return fallback skips an
/// OPTIONAL method, which the source may lack, and still requires a
/// required one, abstract or not (probed).
test "an optional target method is not required (optionaltargetmethod)" {
  let src =
    #|// @strict: true
    #|class Target { value = 0; optional?(): void; }
    #|class Source { value = 0; }
    #|declare const source: () => Source;
    #|export const okTarget: () => Target = source;
    #|abstract class Target2 { value = 0; optional?(): void; abstract req(): void; }
    #|export const badTarget: () => Target2 = source;
    #|class T3 { value = 0; m(): void {} }
    #|export const badT3: () => T3 = source;
  assert_eq(issue_lines(src), [
    "top-level > binding `badTarget` init: expected `() => Target2` but got `() => Source`",
    "top-level > binding `badT3` init: expected `() => T3` but got `() => Source`",
  ])
}

///|
/// Only a binding in scope at the field initializer shadows the lib
/// collection: a METHOD PARAMETER named `Map` does not, so the field keeps
/// the lib `Map` type, while a top-level `function Set() {}` does.
test "a parameter named Map does not shadow the lib collection (newcollectionparam)" {
  let src =
    #|// @strict: true
    #|export class C {
    #|  cache = new Map<string, number>();
    #|  unrelated(Map: unknown) {}
    #|  s = new Set<string>();
    #|  m(Set: number) { return Set; }
    #|}
    #|export function badCache(c: C) { const s: string = c.cache.get("a"); return s; }
    #|export function badSet(c: C) { const n: number = c.s.has("x"); return n; }
  assert_eq(issue_lines(src), [
    "function badCache > binding `s` init: type `number | undefined` is not assignable to type `string`",
    "function badSet > binding `n` init: expected `number` but got `boolean`",
  ])
  let shadowed =
    #|// @strict: true
    #|class CustomMap<K, V> { hello(): string { return "hi"; } }
    #|const Map = CustomMap;
    #|export class Holder { m = new Map<string, number>(); }
    #|export function okUse(h: Holder): string { return h.m.hello(); }
  assert_eq(issue_lines(shadowed), [])
}

///|
/// An inherited constructor's defaulted parameter is optional, as the
/// class's own one is: `new Sub()` against a base `constructor(d = DS.A)`
/// was "expected 1 argument(s), got 0" (univer's `NullValueObject`; probed:
/// tsc accepts it and reports two arguments as "0-1").
test "an inherited constructor's default makes its parameter optional (inheritedctordefault)" {
  let src =
    #|// @strict: true
    #|enum DS { A = 0, B = 1 }
    #|export class Base { private _d: DS; constructor(d: DS = DS.A) { this._d = d; } }
    #|export class Sub extends Base {}
    #|export const okBase = new Base();
    #|export const okSub = new Sub();
    #|export class Base3 { constructor(d: DS = DS.A) {} }
    #|export class Sub3 extends Base3 {}
    #|export const badSub3 = new Sub3(DS.A, 2);
  assert_eq(issue_lines(src), [
    "top-level > new `Sub3`: expected 0-1 argument(s), got 2",
  ])
}

///|
/// A declaration's initializer is asked the question an assignment asks: a
/// static factory or an unannotated method whose return cannot be nullish
/// removes the nullish members of the declared type (univer's
/// `let v: Nullable<BaseValueObject> = NullValueObject.create()`; probed).
/// `this` in an unannotated instance method is the instance.
test "a factory call initializer narrows a nullable declaration (factoryinit)" {
  let src =
    #|// @strict: true
    #|type Nullable<T> = T | null | undefined | void;
    #|export class B { isError(): boolean { return false; } }
    #|export class X extends B {
    #|  private static _instance: X;
    #|  static create() { this._instance = this._instance || new X(); return this._instance; }
    #|  static maybe(k: number) { return k > 0 ? new X() : undefined; }
    #|  static sure(): X { return new X(); }
    #|  find(k: number) { return k > 0 ? this : undefined; }
    #|  self() { return this; }
    #|}
    #|export function okSingleton() { let v: Nullable<B> = X.create(); return v.isError(); }
    #|export function okSure() { let v: Nullable<B> = X.sure(); return v.isError(); }
    #|export function okSelf(x: X) { let v: Nullable<B> = x.self(); return v.isError(); }
    #|export function badMaybe(k: number) { let v: Nullable<B> = X.maybe(k); return v.isError(); }
    #|export function badFind(x: X) { let v: Nullable<B> = x.find(1); return v.isError(); }
  assert_eq(issue_lines(src), [
    "function badMaybe > call `isError`: object is possibly `undefined`", "function badFind > call `isError`: object is possibly `undefined`",
  ])
}

///|
/// An unannotated method whose body is exactly `return this.FIELD` returns
/// the field's declared type at a call (univer's `getSkeletonData()`).
test "a plain getter method returns its field's type (plaingetter)" {
  let src =
    #|// @strict: true
    #|type Nullable<T> = T | null | undefined | void;
    #|interface Page { pageWidth: number }
    #|interface Data { pages: Page[] }
    #|export class Skel {
    #|  private _data: Nullable<Data>;
    #|  getData() { return this._data; }
    #|  okViaMethod(i: number) {
    #|    const data = this.getData();
    #|    if (data == null) { return; }
    #|    const { pages } = data;
    #|    let p: Nullable<Page> = null;
    #|    p = pages[i];
    #|    return p.pageWidth;
    #|  }
    #|  badDestructured() {
    #|    const data = this.getData();
    #|    if (data == null) { return; }
    #|    const { pages } = data;
    #|    const q: string = pages;
    #|    return q;
    #|  }
    #|}
    #|declare const s: Skel;
    #|export function badOutside() { const q: string = s.getData(); return q; }
  assert_eq(issue_lines(src), [
    "function badOutside > binding `q` init: type `Data | null | undefined | void` is not assignable to type `string`",
    "function Skel.badDestructured > binding `q` init: expected `string` but got `Page[]`",
  ])
}

///|
/// TS2454 is not reported for a binding whose declared type admits
/// `undefined` through an alias (`Nullable<T>`, `Maybe<T>`), as tsc does
/// not report it for the union written out; `OnlyNull<T>` still reports.
test "TS2454 reads an alias that admits undefined (unassignedalias)" {
  let src =
    #|// @strict: true
    #|type Nullable<T> = T | null | undefined | void;
    #|type Maybe<T> = T | undefined;
    #|type OnlyNull<T> = T | null;
    #|export function okNullableAlias(): number { let e: Nullable<number>; return e as number; }
    #|export function okMaybeAlias(): number { let e: Maybe<number>; return e as number; }
    #|export function badOnlyNull(): number { let e: OnlyNull<number>; return e as number; }
  assert_eq(issue_lines(src), [
    "function badOnlyNull > use `e`: variable `e` is used before being assigned",
  ])
}

///|
/// The code after a loop sees what the body assigned: `let r: number |
/// string | E = ""` narrowed to `string`, the body reassigned it, and
/// `r instanceof E` after the loop was TS2358 (univer's
/// `Improduct.calculate`; probed). A loop-head binding does not leak.
test "a loop's assignments reach the code after it (loopexitjoin)" {
  let src =
    #|// @strict: true
    #|export class EV { e = 1; }
    #|declare function handle(): number | string | EV;
    #|declare const flag: boolean;
    #|export function okWhile() {
    #|  let result: number | string | EV = '';
    #|  while (flag) { result = handle(); }
    #|  return result instanceof EV;
    #|}
    #|export function okFor(xs: number[]) {
    #|  let result: number | string | EV = '';
    #|  for (let i = 0; i < xs.length; i++) { if (flag) { } else { result = handle(); } }
    #|  return result instanceof EV;
    #|}
    #|export function okForOf(xs: number[]) {
    #|  let result: number | string | EV = '';
    #|  for (const x of xs) { result = handle(); }
    #|  return result instanceof EV;
    #|}
    #|export function okLoopVarScoped() {
    #|  for (let i = 0; i < 3; i++) { }
    #|  let i = "s";
    #|  return i.length;
    #|}
    #|export function badString() {
    #|  let s: number | string = '';
    #|  return s instanceof EV;
    #|}
  assert_eq(issue_lines(src), [
    "function badString > instanceof: the left-hand side of an `instanceof` expression must be of type `any`, an object type or a type parameter",
  ])
}

///|
/// A `let` / `const` pattern or loop head declares new bindings, so a name
/// that shadows an outer binding takes its own declared type: `a = 2` after
/// `let { a } = { a: 1 }` in a block beside an outer `let a = "s"` was
/// judged against `string` (probed: tsc accepts every cell here).
test "a pattern declaration shadows an outer binding's declared type (patternshadow)" {
  let src =
    #|// @strict: true
    #|declare const flag: boolean;
    #|export function okObject() {
    #|  let a = "s";
    #|  if (flag) { let { a } = { a: 1 }; a = 2; }
    #|  return a.length;
    #|}
    #|export function okArray() {
    #|  let a = "s";
    #|  if (flag) { let [a] = [1]; a = 2; }
    #|  return a.length;
    #|}
    #|export function okForIn(o: object) {
    #|  let k = 1;
    #|  for (let k in o) { k = "x"; }
    #|  return k + 1;
    #|}
    #|export function okForOf(xs: number[]) {
    #|  let k = "outer";
    #|  for (let k of xs) { k = k + 1; }
    #|  return k.length;
    #|}
    #|export function okForOfPattern(xs: [number][]) {
    #|  let k = "outer";
    #|  for (let [k] of xs) { k = k + 1; }
    #|  return k.length;
    #|}
    #|export function badStillChecked(xs: number[]) {
    #|  for (let k of xs) { k = "s"; }
    #|}
  assert_eq(issue_lines(src), [
    "function badStillChecked > assign `k`: expected `number` but got `string`",
  ])
}

///|
test "an array keeps literals that are not fresh (arraydeclaredliterals)" {
  let src =
    #|// @strict: true
    #|declare function getSep(i: number): '-' | '/' | null;
    #|declare const o: { kind: 'a' | 'b' };
    #|enum E { A, B }
    #|declare function id<T>(x: T): T;
    #|function take(s: '-' | '/'): string { return s; }
    #|declare const xs: number[];
    #|export function okMapped() {
    #|  const seps = xs.map((x) => getSep(x));
    #|  const sep = seps[0];
    #|  if (sep) take(sep);
    #|}
    #|export function okLiteral() {
    #|  const seps = [getSep(1)];
    #|  const sep = seps[0];
    #|  if (sep) take(sep);
    #|}
    #|export function okFreshWidens() {
    #|  const a = ["-"]; a.push("z");
    #|  const b = [E.A]; b.push(E.B);
    #|  const c = xs.map(() => "-"); c.push("z");
    #|  const d = [id("x")]; d.push("y");
    #|  const e = xs.map(() => { const k = "a"; return k; }); e.push("z");
    #|}
    #|export function badDeclaredKept() {
    #|  const f = [o.kind]; f.push("c");
    #|  const g = xs.map((x): "a" => "a"); g.push("z");
    #|}
  assert_eq(issue_lines(src), [
    "function badDeclaredKept > call `push` arg[0]: expected `\"a\" (string) | \"b\" (string)` but got `\"c\" (string)`",
    "function badDeclaredKept > call `push` arg[0]: expected `\"a\" (string)` but got `string`",
  ])
}

///|
test "a map callback's object literal widens member by member (mapobjectwiden)" {
  let src =
    #|// @strict: true
    #|interface C { start: number; require: 'a-or-b' | 'a-and-b' }
    #|declare const ranges: { s: number }[];
    #|export function okAsConst(): C[] {
    #|  return ranges.map((r) => {
    #|    const start = r.s + 1;
    #|    return { start, require: 'a-or-b' as const };
    #|  });
    #|}
    #|export function okBound(): C[] {
    #|  const cs = ranges.map((r) => {
    #|    const start = r.s + 1;
    #|    return { start, require: 'a-or-b' as const };
    #|  });
    #|  return cs;
    #|}
    #|export function badFresh(): C[] {
    #|  const cs = ranges.map((r) => ({ start: r.s, require: 'a-or-b' }));
    #|  return cs;
    #|}
  assert_eq(issue_lines(src), [
    "function badFresh > return: expected `C[]` but got `{ start: number; require: string }[]`",
  ])
}

///|
test "an index inside an optional chain sees its receiver non-nullish (chainindex)" {
  let src =
    #|// @strict: true
    #|declare const stack: string[] | null;
    #|declare const p: { a: number[] } | undefined;
    #|export const ok1 = stack?.[stack?.length - 1];
    #|export const ok2 = stack?.[stack.length - 1];
    #|export const ok3 = p?.a[p.a.length - 1];
    #|export const bad = stack?.length - 1;
  assert_eq(issue_lines(src), [
    "top-level > binary op: left operand `number | undefined` is not a valid number type",
  ])
}

///|
test "a numeric literal comparison rules out nullish (numericequality)" {
  let src =
    #|// @strict: true
    #|declare const cols: { [k: number]: { w?: number } | undefined };
    #|function takeN(n: number): number { return n; }
    #|export function ok(c: number, dflt: number) {
    #|  let result = cols[c]?.w;
    #|  if (!result && result !== 0) {
    #|    result = dflt;
    #|  }
    #|  return takeN(result);
    #|}
    #|export function okEqual(r: number | undefined) {
    #|  if (r === 0) return takeN(r);
    #|  if (r == -1) return takeN(r);
    #|  return 0;
    #|}
    #|export function badNotEqual(r: number | undefined) {
    #|  if (r !== 0) return takeN(r);
    #|  return 0;
    #|}
  assert_eq(issue_lines(src), [
    "function badNotEqual > call `takeN` arg[0]: type `number | undefined` is not assignable to type `number`",
  ])
}

///|
test "a class initializer narrows a declared union of classes (memberinit)" {
  let src =
    #|// @strict: true
    #|class A { a = 1; isErr() { return false; } }
    #|class B { b = 1; isErr() { return false; } }
    #|type AB = A | B;
    #|declare const arr: A;
    #|declare const bv: B;
    #|declare const flag: boolean;
    #|export function ok1(): A { let v: AB = flag ? (arr as A) : arr; if (v.isErr()) { return v; } return v; }
    #|export function ok2(): A { const v: AB = arr; return v; }
    #|export function badReassigned(): A { let v: AB = arr; v = bv; return v; }
    #|export function badOther(): A { let v: AB = bv; return v; }
  assert_eq(issue_lines(src), [
    "function badReassigned > return: expected `A` but got `B`", "function badOther > return: expected `A` but got `B`",
  ])
}

///|
test "a guard opens an alias of an alias (nestednullable)" {
  let src =
    #|// @strict: true
    #|type Nullable<T> = T | null | undefined | void;
    #|interface Cell { f?: string | null }
    #|declare function isF(v: unknown): boolean;
    #|export function okTruthy(x: Nullable<Nullable<Cell>> | undefined) { if (!x || isF(x.f)) { return; } }
    #|export function okEarly(x: Nullable<Nullable<Cell>> | undefined) { if (!x) { return; } isF(x.f); }
    #|export function badNullOnly(x: Nullable<Nullable<Cell>> | undefined) { if (x !== null) { return x.f; } }
  assert_eq(issue_lines(src), [
    "function badNullOnly > PropAccess `.f`: object is possibly `undefined`",
  ])
}

///|
test "a function type in a union is parenthesized (funcunionparens)" {
  let src =
    #|// @strict: true
    #|declare function get(): (() => void) | undefined;
    #|declare function use(f: () => void): void;
    #|export function bad() { use(get()); }
  assert_eq(issue_lines(src), [
    "function bad > call `use` arg[0]: type `(() => void) | undefined` is not assignable to type `() => void`",
  ])
}

///|
test "a for head's own binding does not narrow an outer one (forheadjoin)" {
  let src =
    #|// @strict: true
    #|declare const flag: boolean;
    #|export function okShadowed() {
    #|  let x: string = "outer";
    #|  for (let x: string | number = ""; flag;) { x = 1; }
    #|  const after: string = x;
    #|  return after;
    #|}
    #|export function badOuterAssigned() {
    #|  let y: string | number = "outer";
    #|  for (let i = 0; flag; i++) { y = 1; }
    #|  const after: string = y;
    #|  return after;
    #|}
  assert_eq(issue_lines(src), [
    "function badOuterAssigned > binding `after` init: expected `string` but got `\"outer\" (string) | 1`",
  ])
}

///|
test "a method with a declared this is not a plain getter (thisparamgetter)" {
  let src =
    #|// @strict: true
    #|class K {
    #|  value: number = 1;
    #|  read(this: { value: string }) { return this.value; }
    #|}
    #|declare const k: K;
    #|export const s: string = k.read();
  assert_eq(issue_lines(src), [])
}

///|
test "JSX type arguments skip quoted text (jsxtypeargquote)" {
  let src =
    #|declare function Box<T>(p: { children?: unknown }): any;
    #|export const a = <Box<() => "<">>08 px</Box>;
    #|export const b = <Box<'>' /* > */>>08 px</Box>;
    #|export const bad: string = 1;
  assert_eq(
    check_source(src, true).split("\n").map(fn(l) { l.to_owned() }).collect(),
    ["top-level > binding `bad` init: expected `string` but got `number`"],
  )
}

///|
test "a lib alias with no body abstains as a union member too (libaliasunion)" {
  let src =
    #|// @strict: true
    #|declare function u1(k: CanvasFontKerning): void;
    #|declare function u2(k?: CanvasFontKerning): void;
    #|declare function u3(k: CanvasTextAlign | null): void;
    #|enum E { A, B }
    #|declare function u4(e: E | undefined): void;
    #|export function ok() { u1('normal'); u2('normal'); u3('left'); }
    #|export function badEnum() { u4("x"); }
  assert_eq(issue_lines(src), [
    "function badEnum > call `u4` arg[0]: expected `E | undefined` but got `string`",
  ])
}

///|
test "an `||` whose right operand is never nullish narrows the assignment (orfallback)" {
  let src =
    #|// @strict: true
    #|class Viewport { x = 1; }
    #|class Scene {
    #|  private _all: Viewport[] = [];
    #|  private _main = new Viewport();
    #|  find(n: number) { return this._all.find((v) => v.x === n); }
    #|  getDefault() { return this._main; }
    #|  use(v: Viewport) { return v.x; }
    #|  okOrFallback(n: number, vp?: Viewport) { if (!vp) { vp = this.find(n) || this.getDefault(); } return this.use(vp); }
    #|  okOrNew(n: number, vp?: Viewport) { if (!vp) { vp = this.find(n) || new Viewport(); } return this.use(vp); }
    #|  badOrMaybe(n: number, vp?: Viewport) { if (!vp) { vp = this.find(n) || this.find(n + 1); } return this.use(vp); }
    #|}
  assert_eq(issue_lines(src), [
    "function Scene.badOrMaybe > call `use` arg[0]: type `Viewport | undefined` is not assignable to type `Viewport`",
  ])
}

///|
test "an optional-chain comparison removes void from the receiver (chainvoid)" {
  let src =
    #|// @strict: true
    #|type Nullable<T> = T | null | undefined | void;
    #|interface Cell { v?: number | null }
    #|declare function use(c: Cell): void;
    #|export function okEarlyReturn(c: Nullable<Cell>) { if (c?.v === undefined || c?.v === null) return; use(c); }
    #|export function okNotUndefined(c: Nullable<Cell>) { if (c?.v !== undefined) use(c); }
    #|export function okLooseNull(c: Nullable<Cell>) { if (c?.v != null) use(c); }
    #|export function okValue(c: Nullable<Cell>) { if (c?.v === 1) use(c); }
    #|export function badNotNull(c: Nullable<Cell>) { if (c?.v !== null) use(c); }
  assert_eq(issue_lines(src), [
    "function badNotNull > call `use` arg[0]: type `Cell | null | undefined | void` is not assignable to type `Cell`",
  ])
}

///|
test "a lib class in a union target keeps its check (libclassunion)" {
  let src =
    #|// @strict: true
    #|type DateArg<D extends Date> = D | number | string;
    #|declare function addDays<D extends Date>(d: DateArg<D>, n: number): D;
    #|export function bad() { return addDays(null, 1); }
  assert_eq(issue_lines(src), [
    "function bad > call `addDays` arg[0]: expected `DateArg<Date>` but got `null`",
  ])
}
