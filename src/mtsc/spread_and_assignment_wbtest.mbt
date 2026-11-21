// Two false-positive families excalidraw's `restoreElement` and its test
// suites exposed. Every `ok…` line is accepted by the TypeScript nightly
// and every reported line is one it reports, probed per case.

///|
/// A spread of a union distributes (`{ ...u }` with `u: A | B` is
/// `{ ...A } | { ...B }`), a later key replaces a spread one, a nullish
/// member contributes an alternative that adds nothing, and a conditional
/// over two object shapes is decided by a disjoint literal member
/// (`Exclude` / `Extract` over a discriminated union of interfaces).
test "a spread of a union distributes and Exclude decides by a discriminant" {
  let src =
    #|interface A { type: "a"; x: number; font?: string }
    #|interface B { type: "b"; y: string }
    #|interface C { type: "c" }
    #|type E = A | B | C;
    #|declare const u: A | B;
    #|declare const un: A | B | undefined;
    #|const o1 = { ...u, type: "z" as const };
    #|export const okOverride: "z" = o1.type;
    #|export const okNullishSpread = { ...un };
    #|declare const ext: Extract<E, { type: "a" }>;
    #|export const okExtract: number = ext.x;
    #|type IsA<T> = T extends { type: "a" } ? 1 : 2;
    #|declare const isB: IsA<B>;
    #|export const okIsB: 2 = isB;
    #|declare const isA: IsA<A>;
    #|export const okIsA: 1 = isA;
    #|type K = { type: "a" | "b" } extends { type: "a" } ? 1 : 2;
    #|declare const kk: K;
    #|export const okK: 2 = kk;
    #|export function okRestore(element: Exclude<E, C>): number {
    #|  element = { ...element };
    #|  switch (element.type) {
    #|    case "a":
    #|      if ("font" in element) { element.x; }
    #|      return element.x;
    #|    case "b":
    #|      return element.y.length;
    #|  }
    #|}
    #|export function okSpreadUnion(element: E): number {
    #|  element = { ...element };
    #|  switch (element.type) { case "a": return element.x; default: return 0; }
    #|}
    #|export const badOverride: "a" = o1.type;
    #|export const badExtract: string = ext.x;
    #|export const badIsB: 1 = isB;
    #|declare const ex: Exclude<E, C>;
    #|export const badExclude: number = ex.type;
  // `got string` is how the same override reads over a single spread
  // (`{ ...a, type: "z" as const }`), on main too; tsc says `"z"`. The
  // union spelling printed `"z" | "z"` until #332's review deduplicated
  // the members, which made the two spellings agree.
  assert_eq(issue_lines(src), [
    "top-level > binding `badOverride` init: expected `\"a\" (string)` but got `string`",
    "top-level > binding `badExtract` init: expected `string` but got `number`",
    "top-level > binding `badIsB` init: expected `1` but got `number`", "top-level > binding `badExclude` init: expected `number` but got `\"a\" (string) | \"b\" (string)`",
  ])
}

///|
/// TS2454 for a read inside a CLOSURE of an outer `let x: T;` fires only
/// when `x` is never DEFINITELY assigned anywhere — `=`, a logical
/// assignment, a destructuring or a loop head. `+=` and `++` read first
/// and do not count, and a read outside any closure keeps the ordinary
/// flow rule.
test "an outer variable assigned anywhere is initialized inside a closure" {
  let src =
    #|declare function run(f: () => void): void;
    #|declare const xs: number[];
    #|interface Api { go(): void }
    #|declare function mk(): Api;
    #|export function okBeforeEach() { let api: Api; run(() => { api = mk(); }); run(() => { api.go(); }); }
    #|export function okLater() { let k: number; run(() => { k.toFixed(); }); k = 2; }
    #|export function okCoalesce() { let q: number; run(() => { q ??= 1; }); run(() => { q.toFixed(); }); }
    #|export function okDestructure() { let c: number; run(() => { [c] = [1]; }); run(() => { c.toFixed(); }); }
    #|export function okForOf() { let e: number; run(() => { for (e of xs) {} }); run(() => { e.toFixed(); }); }
    #|export function badNever() { let n: Api; run(() => { n.go(); }); }
    #|export function badCompound() { let a: number; run(() => { a += 1; }); run(() => { a.toFixed(); }); }
    #|export function badDirect() { let h: number; h.toFixed(); h = 1; }
  assert_eq(issue_lines(src), [
    "function badNever > use `n`: variable `n` is used before being assigned", "function badCompound > use `a`: variable `a` is used before being assigned",
    "function badDirect > use `h`: variable `h` is used before being assigned",
  ])
}

///|
/// The shapes reaching real code exposed once the spreads above resolved,
/// and the two #306 review items that were reports on legal code: a
/// destructuring callback parameter's RETURN inference, `?.` over a union
/// of declared shapes and over a nullable receiver, the other side of a
/// `x?.tag === K` comparison, an instance type with only `private static`
/// members, a `switch` label falling into `default`, and a callable
/// object's overloads tried in declaration order.
test "patterns, optional chains and overloads the field data exposed" {
  let src =
    #|type LocalPoint = [number, number] & { _brand: "local" };
    #|declare const points: readonly LocalPoint[];
    #|export const okXs: number[] = points.map(([x]) => x);
    #|export const badXs: string[] = points.map(([x]) => x);
    #|export const okObj: number[] = [{ a: 1 }].map(({ a }) => a);
    #|interface A { type: "a"; frameId: string | null }
    #|interface B { type: "b"; frameId: string | null }
    #|declare const one: A | B;
    #|export const okChain: string | null = one?.frameId;
    #|export const badChain: string = one?.frameId;
    #|declare const maybe: A | undefined;
    #|export const okMaybe: string | null | undefined = maybe?.frameId;
    #|export const okCmp = maybe?.frameId === null;
    #|export const badMaybe: string | null = maybe?.frameId;
    #|enum K { A, B }
    #|interface Ba { type: K.A }
    #|interface Se { type: K.B; selections?: number[] }
    #|declare const item: Ba | Se | undefined;
    #|export function chainElse() {
    #|  const sel = item?.type === K.A ? undefined : item;
    #|  return [sel && sel.selections, sel && sel.nope];
    #|}
    #|export class Ks { public readonly a: number = 1; private static helper(): number { return 1 } static use() { return Ks.helper() } }
    #|export const okStatic: Ks = { a: 2 };
    #|export class Kp { public readonly a: number = 1; private secret = 2 }
    #|export const badPrivate: Kp = { a: 2, secret: 3 };
    #|type Kind = { kind: "a"; a: number } | { kind: "b"; b: string };
    #|export function okFall(x: Kind) {
    #|  switch (x.kind) { case "a": break; case "b": default: return x.kind; }
    #|  return "";
    #|}
    #|export function badExhausted(x: Kind) {
    #|  switch (x.kind) { case "a": return 1; case "b": return 2; default: return x.kind; }
    #|}
    #|declare const f: { <T>(x: T): number; (x: string): string };
    #|declare const s: string;
    #|export const okOrder: number = f(s);
    #|export const badOrder: string = f(s);
  assert_eq(issue_lines(src), [
    "function chainElse > PropAccess `.nope`: property `nope` does not exist on `Se`",
    "function badExhausted > PropAccess `.kind`: property `kind` does not exist on `never`",
    "top-level > binding `badXs` init: expected `string[]` but got `number[]`", "top-level > binding `badChain` init: type `string | null` is not assignable to type `string`",
    "top-level > binding `badMaybe` init: type `string | null | undefined` is not assignable to type `string | null`",
    "top-level > binding `badPrivate` init: expected `Kp` but got `{ a: number; secret: number }`",
    "top-level > binding `badOrder` init: expected `string` but got `number`",
  ])
}

///|
/// excalidraw's element union, reduced: an `Exclude` over a union that
/// lists a union alias, members sharing an intersected base (which
/// `simplify_type` collapses to the base alone), a receiver union of
/// intersections under `?.`, a chain compared with a non-literal value,
/// a static generic method beside a program `class T`, explicit type
/// arguments on an overload set, and a `@ts-ignore`d legacy case label.
test "excalidraw's element union and the shapes around it" {
  let src =
    #|type Base = Readonly<{ id: string; x: number; frameId: string | null }>;
    #|type SelEl = Base & { type: "selection" };
    #|type RectEl = Base & { type: "rectangle" };
    #|type Generic = SelEl | RectEl;
    #|type TextEl = Base & Readonly<{ type: "text"; fontSize: number }>;
    #|type El = Generic | TextEl;
    #|export function okRestore(element: Exclude<El, SelEl>): number {
    #|  element = { ...element };
    #|  switch (element.type) {
    #|    case "text": return element.fontSize;
    #|    case "rectangle": return element.x;
    #|  }
    #|}
    #|type T1 = RectEl extends SelEl ? "yes" : "no";
    #|declare const t1: T1;
    #|export const okNo: "no" = t1;
    #|declare const els: readonly El[];
    #|declare const i: number;
    #|export const okFrame: string | null = els[i]?.frameId;
    #|interface IBullet { listType: string; listId: string }
    #|declare const b: IBullet | undefined;
    #|declare const lt: string;
    #|export const okChainVar = b?.listType === lt ? b.listId : "x";
    #|export class T { t = 1 }
    #|class Tools { static deepClone<T = unknown>(value: T): T { return value } }
    #|export const okClone = Tools.deepClone(b);
    #|type GP = [number, number] & { _brand: "g" };
    #|type LP = [number, number] & { _brand: "l" };
    #|export function pointFrom<P extends GP | LP>(x: number, y: number): P;
    #|export function pointFrom<P extends GP | LP>(c: { x: number; y: number }): P;
    #|export function pointFrom<P extends GP | LP>(a: number | { x: number; y: number }, y?: number): P {
    #|  return (typeof a === "object" ? [a.x, a.y] : [a, y]) as P;
    #|}
    #|export const okPoints: GP[] = ([[1, 2]] as [number, number][]).map(([x, y]) => pointFrom<GP>(x, y));
    #|declare function df<P extends GP | LP>(x: number, y: number): P;
    #|declare function df<P extends GP | LP>(c: [number, number]): P;
    #|export const okDeclared = df<GP>(1, 2);
    #|export const badRect: number = t1;
  assert_eq(issue_lines(src), [
    "top-level > binding `badRect` init: expected `number` but got `string`",
  ])
}

///|
/// A `@ts-ignore`d label is one tsc reports and the comment silences, so
/// TS2678 abstains in a file carrying the comment; the same label in a
/// file without one is reported.
test "TS2678 abstains in a file carrying a suppression comment" {
  let ignored =
    #|type K = "a" | "b";
    #|export function f(k: K) {
    #|  switch (k) {
    #|    case "a": return 1;
    #|    // @ts-ignore legacy value
    #|    case "c": return 2;
    #|  }
    #|  return 0;
    #|}
  let plain =
    #|type K = "a" | "b";
    #|export function f(k: K) {
    #|  switch (k) {
    #|    case "a": return 1;
    #|    case "c": return 2;
    #|  }
    #|  return 0;
    #|}
  assert_eq(issue_lines(ignored), [])
  assert_eq(issue_lines(plain), [
    "function f > switch case: case value `\"c\" (string)` can never match scrutinee `\"a\" (string) | \"b\" (string)`",
  ])
}

///|
/// univer's own shapes: `a?.x ?? a?.y` narrowed by `!= null`, a compound
/// assignment judged on the narrowed target, and a class whose base an
/// augmentation in the same file names (graph mode, below).
test "a flat ?? and a compound write on the narrowed target" {
  let src =
    #|declare const o: { a?: number; b?: number } | undefined;
    #|declare const d: number;
    #|export function okGuarded() {
    #|  let p = o?.a ?? o?.b;
    #|  if (p != null) { const q: number = p; p -= d; return q; }
    #|  return 0;
    #|}
    #|export function badUnguarded(x?: number) {
    #|  let r: number | undefined = x;
    #|  r -= d;
    #|  return r;
    #|}
  assert_eq(issue_lines(src), [
    "function badUnguarded > compound-assign `r`: compound arithmetic op requires a number target, got `number | undefined`",
  ])
}

///|
test "a class whose base a module augmentation names abstains on members" {
  assert_eq(
    graph_messages(
      [
        (
          "/p/facade/index.ts", "export class FUniver {\n  constructor(protected readonly _injector: { get(): number }) {}\n  static extend(_m: unknown): void {}\n}\n",
        ),
        (
          "/p/ui.ts", "import { FUniver } from \"./facade\";\nexport interface IFUniverUIMixin { copy(): number }\nexport class FUniverUIMixin extends FUniver implements IFUniverUIMixin {\n  copy(): number { return this._injector.get(); }\n}\nFUniver.extend(FUniverUIMixin);\ndeclare module \"./facade\" {\n  interface FUniver extends IFUniverUIMixin { }\n}\n",
        ),
      ],
      [("/p/ui.ts", "./facade", "/p/facade/index.ts")],
    ),
    [],
  )
}

///|
/// univer's `rich-text-builder.ts` and `text-x-utils.ts`. An enum-typed
/// value is a definite value for a `?.` equality, and a union of lib
/// arrays is not judged by the union-callee arity rule, whose `?`
/// information the lib member tables do not carry. A union of DECLARED
/// methods keeps that rule (TS2554 in tsc).
test "an enum operand narrows a chain and a lib array union keeps its arity" {
  let src =
    #|enum PLT { A = "a", B = "b" }
    #|interface IBullet { listType: PLT | string; listId: string }
    #|interface IP { startIndex: number }
    #|interface A { m(x: string): void }
    #|interface B { m(x: string, y: string): void }
    #|export function okEnum(b: IBullet | undefined, o: { type?: PLT }) {
    #|  const listType = o.type ?? PLT.A;
    #|  return b?.listType === listType ? b.listId : "x";
    #|}
    #|export function badMaybeEnum(b: IBullet | undefined, t: PLT | undefined) {
    #|  return b?.listType === t ? b.listId : "x";
    #|}
    #|export function okLibUnion(xs: IP[] | number[], body: { ps?: IP[] }) {
    #|  const { ps = [] } = body;
    #|  return [xs?.find((p) => true), ps?.find((p) => p.startIndex > 0)];
    #|}
    #|export function badDeclaredUnion(u: A | B) {
    #|  u?.m("a");
    #|}
  // The ternary's branch is checked twice, so its report appears twice; that
  // predates this test and is the same on main.
  assert_eq(issue_lines(src), [
    "function badMaybeEnum > PropAccess `.listId`: object is possibly `undefined`",
    "function badMaybeEnum > PropAccess `.listId`: object is possibly `undefined`",
    "function badDeclaredUnion > call: expected at least 2 argument(s), got 1",
  ])
}

///|
/// univer's `getReverseDirection`: a `switch` naming every member of an
/// enum, numeric or string, needs no ending return. tsc reports TS2366 when
/// one member is missing.
test "a switch naming every enum member ends every path" {
  let src =
    #|export enum D { UP, DOWN }
    #|export enum S { A = "a", B = "b" }
    #|export function okNumeric(d: D): D {
    #|  switch (d) { case D.UP: return D.DOWN; case D.DOWN: return D.UP; }
    #|}
    #|export function okString(s: S): number {
    #|  switch (s) { case S.A: return 1; case S.B: return 2; }
    #|}
    #|export function badMissing(d: D): D {
    #|  switch (d) { case D.UP: return D.DOWN; }
    #|}
  assert_eq(issue_lines(src), [
    "function badMissing: not all paths return a `D`",
  ])
}

///|
/// #307's review, each cell probed against the nightly: an overload with a
/// literal-typed parameter is tried first, an interface's own member
/// overrides the inherited one in an object conditional, a member the
/// source lacks decides nothing, and a local shadowing an enum does not
/// cover its members.
test "literal overloads first, effective members, absent members, shadowed enums" {
  let src =
    #|declare const f: { (x: string): number; (x: "a"): string };
    #|export const okLit: string = f("a");
    #|export const badLit: number = f("a");
    #|declare function g(x: string): number;
    #|declare function g(x: "a"): string;
    #|export const okDecl: string = g("a");
    #|export const badDecl: number = g("a");
    #|interface I { m(x: string): number; m(x: "a"): string }
    #|declare const i: I;
    #|export const okMethod: string = i.m("a");
    #|export const badMethod: number = i.m("a");
    #|interface Base { kind: "a" | "b"; n: number }
    #|interface A extends Base { kind: "a" }
    #|type R4 = A extends { kind: "a" } ? 1 : 2;
    #|export const okOwn: R4 = 1;
    #|type R5 = { a: true } extends { a: true; b: string | undefined } ? 1 : 2;
    #|export const okAbsent: R5 = 2;
    #|export enum E { A, B }
    #|export function badShadow(x: E): number {
    #|  const E = { A: 0 as const, B: 0 as const };
    #|  switch (x) { case E.A: return 1; case E.B: return 2; }
    #|}
  assert_eq(issue_lines(src), [
    "function badShadow: not all paths return a `number`", "top-level > binding `badLit` init: expected `number` but got `string`",
    "top-level > binding `badDecl` init: expected `number` but got `string`", "top-level > binding `badMethod` init: expected `number` but got `string`",
  ])
}

///|
/// #307's second review round: a literal ARGUMENT selects a literal-typed
/// overload on every call path (a number literal is widened by inference),
/// an explicit `x: "a" | undefined` is not a literal-typed parameter, a
/// source member that may be optional does not prove presence, and any
/// local binding of an enum's name shadows it.
test "literal arguments, explicit undefined unions, optional sources, shadowing params" {
  let src =
    #|declare const f: { (x: number): string; (x: 1): number };
    #|export const okNum: number = f(1);
    #|export const badNum: string = f(1);
    #|declare const h: { (x: string): number; (x: "a" | undefined): string };
    #|export const okUnion: number = h("a");
    #|type R3 = { a: true; b?: string } extends { b: string | undefined } ? 1 : 2;
    #|export const okR3: R3 = 2;
    #|interface Item { a: number }
    #|export class S {
    #|  private _m = new Map<string, Item[]>();
    #|  protected get(id: string): Item[] | null;
    #|  protected get(id: string, create: true): Item[];
    #|  protected get(id: string, create = false): Item[] | null {
    #|    let s = this._m.get(id);
    #|    if (!s && create) { s = []; this._m.set(id, s); }
    #|    return s || null;
    #|  }
    #|  ok(): Item[] { return this.get("x", true); }
    #|  bad(): Item[] { return this.get("x"); }
    #|}
    #|export enum E { A, B }
    #|interface Labels { A: E; B: E }
    #|export function badParam(x: E, E: Labels): number {
    #|  switch (x) { case E.A: return 1; case E.B: return 2; }
    #|}
  assert_eq(issue_lines(src), [
    "function badParam: not all paths return a `number`", "function S.bad > return: type `Item[] | null` is not assignable to type `Item[]`",
    "top-level > binding `badNum` init: expected `string` but got `number`",
  ])
}

///|
/// #307's third review round. An overload member's tuple rest is expanded
/// before its arity is judged, so `(x: 1, ...rest: [string])` needs two
/// arguments. A member that takes a call only if a parameter it omits is
/// optional, when the member cannot say (a bare `Func` spells `y?: T` and
/// `y: T | undefined` alike), answers unless a later member takes the call
/// too; then the call is `any`. A recorded `?` (`CallableMeta`) and an
/// interface member with none are exact. A qualified enum label is shadowed
/// through its root.
test "tuple-rest and omittable-parameter overload arity, qualified enum shadows" {
  let src =
    #|declare const f: { (x: 1, ...rest: [string]): string; (x: number): number };
    #|export const okRest: number = f(1);
    #|export const badRest: string = f(1);
    #|declare const g: { (x: 1, y: string | undefined): string; (x: number): number };
    #|export const okReq: number = g(1);
    #|declare const h: { (x: 1, y?: string): string; (x: number): number };
    #|export const badOpt: number = h(1);
    #|interface I { m(x: 1, y: string | undefined): string; m(x: number): number }
    #|declare const i: I;
    #|export const okM: number = i.m(1);
    #|export const badM: string = i.m(1);
    #|declare function df(x: 1, y: string | undefined): string;
    #|declare function df(x: number): number;
    #|export const okD: number = df(1);
    #|export namespace N { export enum E { A, B } }
    #|export function badShadowQ(N: { E: { A: number; B: number } }, d: N.E): number {
    #|  switch (d) { case N.E.A: return 1; case N.E.B: return 2; }
    #|}
    #|export function okQ(d: N.E): number {
    #|  switch (d) { case N.E.A: return 1; case N.E.B: return 2; }
    #|}
    #|declare const hu: { (x: string): number; (x: "a" | undefined): string };
    #|export const badUnion: string = hu("a");
    #|interface Base { kind: "a" | "b"; n: number }
    #|interface A extends Base { kind: "a" }
    #|type R4 = A extends { kind: "a" } ? 1 : 2;
    #|export const badOwn: R4 = 2;
  assert_eq(issue_lines(src), [
    "function badShadowQ: not all paths return a `number`", "top-level > binding `badRest` init: expected `string` but got `number`",
    "top-level > binding `badOpt` init: expected `number` but got `string`", "top-level > binding `badM` init: expected `string` but got `number`",
    "top-level > binding `badUnion` init: expected `string` but got `number`", "top-level > binding `badOwn` init: expected `R4` but got `2`",
  ])
}

///|
/// #307's fourth review round, all against the TS7 nightly. A spread of a
/// fixed tuple is its elements for selection; a parameter whose type
/// accepts `void` is omittable; an interface method with a `?` is a
/// candidate with its recorded flags; members that agree on the return keep
/// it; a generic member's arity uses its recorded `?`s; a rest parameter's
/// tuple ALIAS is expanded; and the "no overload matches" proof reads a
/// literal argument as its literal type (`lit(1)` against `(x: 1)` was
/// TS2769 on main). The supplied-argument cases of `g` and `f` pin the
/// members' own arity.
test "tuple spreads, void, recorded optionals, agreeing returns, tuple aliases" {
  let src =
    #|declare const f2: { (x: 1, ...rest: [string]): string; (x: number, value: [string]): number };
    #|declare const xs: [string];
    #|export const okSpread: string = f2(1, ...xs);
    #|export const badSpread: number = f2(1, ...xs);
    #|export const okNoSpread: number = f2(1, xs);
    #|declare const v: { (x: 1, y: string | void | undefined): string; (x: number): number };
    #|export const okVoid: string = v(1);
    #|export const badVoid: number = v(1);
    #|interface M3 { m(x: 1, y?: string): string; m(x: number): number; m(x: boolean): boolean }
    #|declare const m3: M3;
    #|export const okM3: string = m3.m(1);
    #|export const badM3: number = m3.m(1);
    #|declare class C2 { m(x: string, y?: string): number; m(x: string): number }
    #|declare const c2: C2;
    #|export const badSame: string = c2.m("a");
    #|declare const gg: { <T>(x: T, y: string | undefined, z?: boolean): string; (x: number): number };
    #|export const okGen: number = gg(1);
    #|export const badGen: string = gg(1);
    #|export const okGen2: string = gg(1, undefined);
    #|export const badGen2: number = gg(1, undefined);
    #|type Tail = [string];
    #|declare const ta: { (x: 1, ...rest: Tail): string; (x: number): number };
    #|export const okTail: number = ta(1);
    #|export const okTail2: string = ta(1, "ok");
    #|export const badTail: string = ta(1);
    #|declare const lit: { (x: 1): string; (x: string): number };
    #|export const okLit: string = lit(1);
    #|declare const g: { (x: 1, y: string | undefined): string; (x: number): number };
    #|export const okReq2: string = g(1, undefined);
    #|export const badReq2: number = g(1, undefined);
    #|declare const f: { (x: 1, ...rest: [string]): string; (x: number): number };
    #|export const okRest2: string = f(1, "ok");
    #|export const badRest2: number = f(1, "ok");
  assert_eq(issue_lines(src), [
    "top-level > binding `badSpread` init: expected `number` but got `string`", "top-level > binding `badVoid` init: expected `number` but got `string`",
    "top-level > binding `badM3` init: expected `number` but got `string`", "top-level > binding `badSame` init: expected `string` but got `number`",
    "top-level > binding `badGen` init: expected `string` but got `number`", "top-level > binding `badGen2` init: expected `number` but got `string`",
    "top-level > binding `badTail` init: expected `string` but got `number`", "top-level > binding `badReq2` init: expected `number` but got `string`",
    "top-level > binding `badRest2` init: expected `number` but got `string`",
  ])
}

///|
/// #307's fifth review round, against the TS7 nightly. A generic member
/// binds from a fixed tuple spread's elements and is judged on the literal
/// argument types, as a concrete member is. Two members whose returns agree
/// only by spelling a binder (`T`) do not agree. A method set holding a
/// member the loop cannot take (a generic one) is left to the
/// first-declaration lookup instead of being resolved among the rest, and
/// the "no overload matches" proof reads a `void` alias as omittable.
test "generic tuple spreads and literals, binder returns, incomplete method sets" {
  let src =
    #|declare const sn: [string, number];
    #|declare const fc: { <T>(x: T, n: number): T; (x: string, n: number): boolean };
    #|export const okC: string = fc(...sn);
    #|export const badC: boolean = fc(...sn);
    #|declare const fd: { <T>(tag: 1, value: T): T; (tag: number, value: string): boolean };
    #|declare const s: string;
    #|export const okD: string = fd(1, s);
    #|export const badD: boolean = fd(1, s);
    #|export const okD2: boolean = fd(2, s);
    #|export const badD2: string = fd(2, s);
    #|declare const oe: { m<T>(x: T): number; m(x: string, flag?: boolean): boolean; m(x: number): string };
    #|export const okE: number = oe.m(s);
    #|export const badE: string = oe.m(s);
    #|type V = void;
    #|declare const ff: { (x: 1, y: string | V): string; (x: boolean): number };
    #|export const okF: string = ff(1);
    #|export const badF: number = ff(1);
    #|declare class CA { m<T>(x: T[], y: string | undefined): T; m<T>(x: T): T }
    #|declare const ca: CA;
    #|declare const nums: number[];
    #|export const okA: number[] = ca.m(nums);
    #|declare const f2: { (x: 1, ...rest: [string]): string; (x: number, value: [string]): number };
    #|declare const xs: [string];
    #|export const badNoSpread: string = f2(1, xs);
    #|type Tail = [string];
    #|declare const ta: { (x: 1, ...rest: Tail): string; (x: number): number };
    #|export const badTail2: number = ta(1, "ok");
  assert_eq(issue_lines(src), [
    "top-level > binding `badC` init: expected `boolean` but got `string`", "top-level > binding `badD` init: expected `boolean` but got `string`",
    "top-level > binding `badD2` init: expected `string` but got `boolean`", "top-level > binding `badE` init: expected `string` but got `number`",
    "top-level > binding `badF` init: expected `number` but got `string`", "top-level > binding `badNoSpread` init: expected `string` but got `number`",
    "top-level > binding `badTail2` init: expected `number` but got `string`",
  ])
}

///|
/// univer's `coverTextRuns`: a member a spread contributes keeps its
/// declared literal type when the literal is bound, while a member written
/// in the literal widens. `typeof x` for a local is the local's type there.
test "a bound spread keeps declared literals and typeof reads a local" {
  let src =
    #|interface T { h?: "a" | "b"; p?: { r: "m" | "i" } }
    #|interface I { a: number }
    #|export function okSpread(o: T | undefined, q: T, c: boolean) {
    #|  const r = { ...o };
    #|  const t1: T = r;
    #|  const r2 = { ...q, k: 1 };
    #|  const t2: T = r2;
    #|  const r3 = { p: c ? { ...q.p! } : { ...q.p! } };
    #|  const t3: T = r3;
    #|}
    #|export function badFresh() {
    #|  const lit = { h: "a" };
    #|  const t: T = lit;
    #|}
    #|export function okTypeof(name: I, k: unknown, keep: (i: I) => boolean) {
    #|  let xs = k as Array<typeof name>;
    #|  xs = xs.filter(keep);
    #|  return xs;
    #|}
    #|export function badTypeof(name: I, k: unknown) {
    #|  const xs = k as Array<typeof name>;
    #|  const s: string = xs;
    #|}
  assert_eq(issue_lines(src), [
    "function badFresh > binding `t` init: expected `T` but got `{ h: string }`",
    "function badTypeof > binding `s` init: type `Array<I>` is not assignable to type `string`",
  ])
}

///|
/// Which spread a member came from decides whether it widens, in source
/// order, each cell probed: a spread of a literal written in place is fresh
/// and widens (a conditional of literals too, and a fresh branch beside a
/// declared one), a later REQUIRED declared member keeps its declared type,
/// and a later OPTIONAL one leaves the earlier fresh member widened. An
/// asserted member (`as const`, `as "q"`) is not fresh and stays narrow.
test "a spread member widens by where it came from, in order" {
  let src =
    #|interface St { h?: "a" | "b"; n: number }
    #|interface Req { h: "a" | "b" }
    #|export function okFreshSpread() { let s = { ...{ h: "x" } }; s.h = "y"; return s; }
    #|export function okCondSpread(c: boolean) { let s = { ...(c ? { h: "a" } : { h: "b" }) }; s.h = "z"; return s; }
    #|export function okMixedCond(c: boolean, rq: Req) { let s = { ...(c ? rq : { h: "x" }) }; s.h = "y"; return s; }
    #|export function okOptionalAfter(st: St) { let s = { ...{ h: "x" }, ...st }; s.h = "y"; return s; }
    #|export function okFreshAfter(rq: Req) { let s = { ...rq, ...{ h: "x" } }; s.h = "y"; return s; }
    #|export function okDeclared(rq: Req) { const s = { ...rq }; const r: Req = s; return r; }
    #|export function badRequiredAfter(rq: Req) { let s = { ...{ h: "x" }, ...rq }; s.h = "y"; return s; }
    #|export function badWrittenThenRequired(rq: Req) { let s = { h: "x", ...rq }; s.h = "y"; return s; }
    #|export function badAsserted(rq: Req) {
    #|  let o = { ...rq, v: "q" as const, k: "q" as "q" };
    #|  o.v = "r";
    #|  o.k = "r";
    #|  return o;
    #|}
    #|export function badAssertedUnion(u: Req | St) {
    #|  let o = { ...u, h: "z" as const };
    #|  o.h = "y";
    #|  return o;
    #|}
  assert_eq(issue_lines(src), [
    "function badRequiredAfter > assign `.h`: expected `\"a\" (string) | \"b\" (string)` but got `\"y\" (string)`",
    "function badWrittenThenRequired > object literal `h`: `h` is specified more than once, so this usage will be overwritten by the spread",
    "function badWrittenThenRequired > assign `.h`: expected `\"a\" (string) | \"b\" (string)` but got `\"y\" (string)`",
    "function badAsserted > assign `.v`: expected `\"q\" (string)` but got `\"r\" (string)`",
    "function badAsserted > assign `.k`: expected `\"q\" (string)` but got `\"r\" (string)`",
    "function badAssertedUnion > assign `.h`: expected `\"z\" (string) | \"z\" (string)` but got `\"y\" (string)`",
  ])
}

///|
/// #308's review, each cell probed against the nightly: an optional spread
/// after a written member widens the whole union, an asserted branch member
/// stays narrow through a conditional spread, a branch that omits a member
/// keeps the earlier fresh one, a member every union variant requires is
/// declared, and a union spread under a written key widens per alternative.
test "spread origins compose through conditionals, variants and nesting" {
  let src =
    #|declare const c: boolean;
    #|declare const d: { h?: number };
    #|declare const da: { h: "a" };
    #|declare const u: { h: "a" } | { h: "b" };
    #|export function m1() { let r = { h: c ? "a" : "b", ...d }; r.h = 1; r.h = "z"; return r; }
    #|export function m1bad() { let r = { h: c ? "a" : "b", ...d }; const s: string = r.h; return s; }
    #|export function n1() { const s = { ...(c ? { h: "a" as "a" } : { h: "b" as "b" }) }; const t: { h: "a" | "b" } = s; return t; }
    #|export function n2() { let r = { h: "seed", ...(c ? da : {}) }; r.h = "x"; return r; }
    #|export function n3() { const r = { h: "seed", ...u }; const t: { h: "a" | "b" } = r; return t; }
    #|export function n4() { const r = { nested: { ...u } }; const t: "a" | "b" = r.nested.h; return t; }
  assert_eq(issue_lines(src), [
    "function m1bad > binding `s` init: expected `string` but got `string | number`",
    "function n3 > object literal `h`: `h` is specified more than once, so this usage will be overwritten by the spread",
  ])
}

///|
/// Four univer shapes, each probed against the nightly: a union member's
/// inherited members survive a spread, a type parameter binds from a union
/// source once the shared `undefined` is out, `a ??= {}` is `a`'s declared
/// type, and an optional call's arguments see its receivers non-nullish
/// (an overloaded method judged as the plain spelling judges it).
test "union bases, union binding, logical assignment, optional-call arguments" {
  let src =
    #|interface Loc { unitId?: string }
    #|interface RowR extends Loc { startRow: number; endRow: number }
    #|interface IRange extends RowR { rangeType?: number }
    #|interface P1 { range: IRange; direction: 1 | 2 }
    #|interface P2 { range: IRange; direction: 3 | 4 }
    #|export function okUnionBases(params: P1 | P2) {
    #|  const { range } = params;
    #|  const r = { ...range };
    #|  r.startRow = 1;
    #|  return r;
    #|}
    #|interface Blk { startIndex: number; blockId: string }
    #|function collect<T extends { startIndex: number }>(prev: T[] | undefined, getId: (item: T) => string): string[] {
    #|  return (prev ?? []).map(getId);
    #|}
    #|export function okUnionBinding(a: Blk[] | undefined) { return collect(a, (item) => item.blockId); }
    #|export function badUnionBinding(a: Blk[] | undefined) { return collect(a, (item) => item.nope); }
    #|interface DS { title?: string }
    #|interface Data { ds?: DS }
    #|export function okCoalesce(d: Data) {
    #|  const s = d.ds ??= {};
    #|  s.title = "x";
    #|  let local: DS | undefined;
    #|  const l = local ||= { title: "y" };
    #|  return [s, l];
    #|}
    #|export function badCoalesce(d: Data) { const s = d.ds ??= {}; const n: number = s; return n; }
    #|interface R { width: number; m(o: { left: number }): void; n?: R }
    #|export function okOptionalCall(icon?: R) {
    #|  icon?.m({ left: icon.width / 2 });
    #|  icon?.n?.m({ left: icon.n.width });
    #|}
    #|export function badOptionalCall(icon?: R, other?: R) { other?.k({ left: icon?.width ?? 0 }); }
    #|interface Op<T, A> { (src: Obs<T>): Obs<A> }
    #|declare class Obs<T> {
    #|  pipe(): Obs<T>;
    #|  pipe<A>(op1: Op<T, A>): Obs<A>;
    #|}
    #|declare function thr<T>(n: number): Op<T, T>;
    #|export function okOptionalOverload(h?: Obs<number>) { return h?.pipe(thr(0)); }
  assert_eq(issue_lines(src), [
    "function badUnionBinding > PropAccess `.nope`: property `nope` does not exist on `Blk`",
    "function badCoalesce > binding `n` init: expected `number` but got `DS`", "function badOptionalCall > call `k`: method `k` does not exist on `R`",
  ])
}

///|
/// #308's second review round, probed: a union spread that replaces a
/// fresh member in SOME alternatives keeps the declared type in those and
/// widens only the fresh part, and a union whose every member requires the
/// member overwrites the written one (TS2783).
test "a union spread widens per alternative and overwrites when every member requires" {
  let src =
    #|declare const c: boolean;
    #|declare const u: { h: "a"; kind: "a" } | { kind: "b" };
    #|declare const u2: { h: "a" } | { h: "b" };
    #|declare const d1: { h?: 1 };
    #|export function p1() { const r = { h: 0, ...u }; const t: "a" | number = r.h; return t; }
    #|export function p2() { const r = { h: "x", ...d1 }; const t: string | 1 = r.h; return t; }
    #|export function p3() { const r = { h: "seed", ...u2 }; return r; }
    #|export function p4() { let r = { h: 0, ...u }; r.h = 5; return r; }
    #|export function p5bad() { const r = { h: 0, ...u }; const t: "a" = r.h; return t; }
  assert_eq(issue_lines(src), [
    "function p3 > object literal `h`: `h` is specified more than once, so this usage will be overwritten by the spread",
    "function p5bad > binding `t` init: expected `\"a\" (string)` but got `\"a\" (string) | number`",
  ])
}

///|
/// univer's `findByStartIndex`: a bounded generic's return is instantiated
/// from its un-inlined signature, so `T | undefined` is the argument's
/// element type rather than the bound, a `ReadonlyArray<T>` parameter
/// binds from a mutable array, and a literal bound against a primitive
/// constraint stays a literal (probed).
test "a bounded generic returns its binding, not its bound" {
  let src =
    #|interface IS { startIndex: number }
    #|interface Tbl { startIndex: number; tableId: string }
    #|interface Body { tables?: Tbl[] }
    #|function findBy<T extends IS>(items: readonly T[], i: number): T | undefined { return items.find((x) => x.startIndex === i); }
    #|function findRo<T extends IS>(items: ReadonlyArray<T>): T | undefined { return items[0]; }
    #|function g<T extends string>(x: T): T | undefined { return x; }
    #|function k<T extends { kind: string }>(x: T): T[] { return [x]; }
    #|export function okRawReturn(b: Body | undefined, xs: Tbl[]) {
    #|  const t = findBy(b?.tables ?? [], 1);
    #|  const r = findRo(xs);
    #|  return [t?.tableId, r?.tableId];
    #|}
    #|export function okBoundedObject(o: { kind: string; n: number }) { const v = k(o); const w: number = v[0].n; return w; }
    #|export function badRawReturn(b: Body | undefined) { return findBy(b?.tables ?? [], 1)?.nope; }
    #|export function badLiteralKept() { let r = g("a"); r = "b"; return r; }
  assert_eq(issue_lines(src), [
    "function badRawReturn > PropAccess `?.nope`: property `nope` does not exist on `Tbl`",
    "function badLiteralKept > assign `r`: expected `\"a\" (string) | undefined` but got `string`",
  ])
}

///|
/// #309's review, probed: `||=` keeps only the left operand's truthy part,
/// and two branches that each contribute a fresh value widen both.
test "||= keeps the truthy part and conditional fresh parts merge" {
  let src =
    #|declare const c: boolean;
    #|declare const d: { h?: boolean };
    #|export function f(x: false | { p: number }) { return (x ||= { p: 1 }).p; }
    #|export function g(x: false | { n: number }): { n: number } { return x ||= { n: 1 }; }
    #|export function g2(x: "" | { n: number }): { n: number } { return x ||= { n: 1 }; }
    #|export function g3(x: boolean | { n: number }) { const r: true | { n: number } = (x ||= { n: 1 }); return r; }
    #|export function h() { let out = { ...(c ? { h: "x", ...d } : { h: 0, ...d }) }; out.h = 42; out.h = "s"; return out; }
    #|export function bad(x: false | { n: number }): { m: number } { return x ||= { n: 1 }; }
    #|export function badShape() { const out = { ...(c ? { h: "x", ...d } : { h: "y", ...d }) }; const t: number = out; return t; }
  assert_eq(issue_lines(src), [
    "function bad > return: property `m` is missing in `{ n: number }` but required in `{ m: number }`",
    "function badShape > binding `t` init: expected `number` but got `{ h: string | boolean }`",
  ])
}

///|
/// univer's `intercept<T extends IInterceptor>(name: T, interceptor: T)`: a
/// class method's arguments are checked against its un-inlined header, with
/// `T` solved from the declared argument and not from the literal, an
/// optional parameter kept optional, and an `any`-typed argument making the
/// parameters that mention its type parameter abstain (probed).
test "a bounded class method is checked against its raw header" {
  let src =
    #|interface IInterceptor<M, C> { id?: string; priority?: number; handler: (v: M, c: C) => M }
    #|interface ICellInterceptor<M, C> extends IInterceptor<M, C> { effect?: number }
    #|declare const CELL: ICellInterceptor<string, number>;
    #|declare const PLAIN: IInterceptor<string, number>;
    #|declare class Plugin { constructor(config?: { a: number }) }
    #|type PluginCtor<T extends Plugin> = new (...args: any[]) => T;
    #|class MyPlugin extends Plugin {}
    #|const ANY_CELL = CELL as ICellInterceptor<string, number>;
    #|export class Svc {
    #|  intercept<T extends IInterceptor<any, any>>(name: T, interceptor: T): void {}
    #|  registerPlugin<T extends PluginCtor<Plugin>>(plugin: T, config?: ConstructorParameters<T>[0]): void {}
    #|}
    #|export function ok(s: Svc) {
    #|  s.intercept(CELL, { priority: 1, effect: 2, handler: (v) => v });
    #|  s.intercept(ANY_CELL, { priority: 1, effect: 2, handler: (v) => v });
    #|  s.registerPlugin(MyPlugin);
    #|}
    #|export function bad(s: Svc) { s.intercept(PLAIN, { priority: 1, effect: 2, handler: (v) => v }); }
  assert_eq(issue_lines(src), [
    "function bad > call `intercept` arg[1].effect: property `effect` does not exist on target type",
  ])
}

///|
/// univer's `serializeDocumentSkeletonLine`: a spread this checker cannot
/// enumerate leaves the result open, and spreading that result again keeps
/// it open, as a fresh literal and as a bound one.
test "a spread of an open shape stays open" {
  let src =
    #|interface L { asc: number; parent?: object; divides: number[]; bullet?: { a: number } }
    #|interface LP extends Omit<L, "divides" | "parent"> { divides: string[] }
    #|declare function withoutParent<T extends { parent?: unknown }>(value: T): Omit<T, "parent">;
    #|export function okFresh(source: L): LP {
    #|  const line = { ...withoutParent(source), divides: source.divides.map(String) };
    #|  return source.bullet == null ? line : { ...line, bullet: { a: 1 } };
    #|}
    #|export function okBound(source: L): LP {
    #|  const line = { ...withoutParent(source), divides: source.divides.map(String) };
    #|  const again = { ...line };
    #|  return again;
    #|}
    #|export function badClosed(source: L): LP {
    #|  const line = { divides: source.divides.map(String) };
    #|  return { ...line, bullet: { a: 1 } };
    #|}
  assert_eq(issue_lines(src), [
    "function badClosed > return.asc: property `asc` is required by `LP`",
  ])
}

///|
/// univer's canvas code: a lib type ALIAS over string literals
/// (`CanvasLineCap`) is only a name here, so a literal assigned to it is
/// not judged, while a curated lib type keeps its primitive check.
test "a lib literal alias abstains and a curated lib type does not" {
  let src =
    #|declare function k(x: CanvasLineCap): void;
    #|export class Q { set cap(v: CanvasLineCap) {} get cap() { return "butt" as CanvasLineCap; } }
    #|export function okAlias(q: Q) {
    #|  k("butt");
    #|  let y: CanvasLineCap = "round";
    #|  q.cap = "butt";
    #|  return y;
    #|}
    #|export function badDate() { const d: Date = 5; return d; }
  assert_eq(issue_lines(src), [
    "function badDate > binding `d` init: expected `Date` but got `number`",
  ])
}

///|
/// The raw header of a class method travels with the class into another
/// module, so univer's controllers calling `this._svc.intercept(…)` on a
/// service declared elsewhere solve `T` as a same-module call does.
test "a bounded class method's raw header reaches another module" {
  let svc = "export interface IInterceptor<M, C> { priority?: number; handler: (v: M, c: C) => M }\nexport interface ICellInterceptor<M, C> extends IInterceptor<M, C> { effect?: number }\nexport declare const CELL: ICellInterceptor<string, number>;\nexport declare const PLAIN: IInterceptor<string, number>;\nexport class Svc {\n  intercept<T extends IInterceptor<any, any>>(name: T, interceptor: T): void {}\n}\n"
  let ok = MtscMemoryHost::over({
    "entry.ts": "import { Svc, CELL } from \"./svc\";\nexport function f(s: Svc) { s.intercept(CELL, { priority: 1, effect: 2, handler: (v) => v }); }\n",
    "svc.ts": svc,
  })
  assert_eq(wbtest_messages(get_program_diagnostics(ok)), [])
  let bad = MtscMemoryHost::over({
    "entry.ts": "import { Svc, PLAIN } from \"./svc\";\nexport function f(s: Svc) { s.intercept(PLAIN, { priority: 1, effect: 2, handler: (v) => v }); }\n",
    "svc.ts": svc,
  })
  assert_true(
    wbtest_any_contains(
      get_program_diagnostics(bad),
      "property `effect` does not exist",
    ),
  )
}

///|
/// Three shapes the raw headers mis-instantiated, each one found by a gate
/// rather than a probe. With strictNullChecks off a bounded generic's
/// binding of `[undefined]` is the widening kind tsc turns into `[any]`
/// (wideningTuples1). One generic at two argument counts leaves trailing
/// arguments to their defaults, which the AST does not keep, so the common
/// prefix decides (effect's `asSync(decodeUnknownEffect(…))`). And a rest
/// parameter in a class method's header is spelled by its declared type,
/// so the instantiation is re-wrapped as a rest (excalidraw's `emit`).
test "a raw header keeps rest parameters, defaulted arguments and nullish widening" {
  let loose =
    #|// @strict: false
    #|declare function foo<T extends [any]>(x: T): T;
    #|var y = foo([undefined]);
    #|y = [""];
  assert_eq(issue_lines(loose), [])
  let src =
    #|interface Effect<A, E = never, R = never> { a: A; e: E; r: R }
    #|declare function asSync<T, E>(p: (i: E) => Effect<T, string>): (i: E) => T;
    #|declare const p2: (i: unknown) => Effect<unknown, string, never>;
    #|export const okDefaulted = asSync(p2);
    #|declare const p4: (i: unknown) => Effect<unknown, number, never>;
    #|export const badPrefix = asSync(p4);
    #|type Map1 = Record<string, unknown[]>;
    #|class Bus<Events extends Map1> { emit<K extends keyof Events>(name: K, ...args: Events[K]) {} }
    #|type TE = { init: [number]; up: [string]; none: [] };
    #|const bus = new Bus<TE>();
    #|bus.emit("init", 42);
    #|bus.emit("up", "s");
    #|bus.emit("none");
    #|bus.emit("init", "bad");
  assert_eq(issue_lines(src), [
    "top-level > call `asSync` arg[0]: expected `(unknown) => Effect<any, string>` but got `(unknown) => Effect<unknown, number, never>`",
    "top-level > call `emit` rest arg[0]: expected `number` but got `string`",
  ])
}

///|
/// From #310's review: widening a fresh literal binding may not leave the
/// type parameter's bound (`box<T extends "a" | "b">(x: T): T[]` makes
/// `box("a")` an `"a"[]`, not `string[]`), and a conditional whose check
/// and extends types spell one generic at two argument counts is left
/// undecided rather than decided by the shared prefix.
test "a raw return keeps a binding inside its bound" {
  let src =
    #|function box<T extends "a" | "b">(x: T): T[] { return [x]; }
    #|export const okBox: ("a" | "b")[] = box("a");
    #|export const badBox: "z"[] = box("a");
    #|interface Box<A, B = string> { value: B; a: A }
    #|type IsBox<T> = T extends Box<number, number> ? string : boolean;
    #|declare const r: IsBox<Box<number>>;
    #|export const okR: boolean = r;
    #|function pair<U extends T, T extends "a" | "b">(u: U, t: T): [U[], T[]] { return [[u], [t]]; }
    #|export const okPair: [("a" | "b")[], ("a" | "b")[]] = pair("a", "a");
  assert_eq(issue_lines(src), [
    "top-level > binding `badBox` init: expected `\"z\" (string)[]` but got `string[]`",
  ])
}
