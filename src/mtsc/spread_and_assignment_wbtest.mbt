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
