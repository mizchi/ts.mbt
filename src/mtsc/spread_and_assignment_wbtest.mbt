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
  assert_eq(issue_lines(src), [
    "top-level > binding `badOverride` init: expected `\"a\" (string)` but got `\"z\" (string) | \"z\" (string)`",
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
    #|interface I { m(x: string): number; m(x: "a"): string }
    #|declare const i: I;
    #|export const okMethod: string = i.m("a");
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
  ])
}
