// @strict: true
// @target: esnext

// The candidate a union target's naked type parameter gets from the rest
// of an argument is one candidate among the call's, reduced with the
// others the way candidates of one priority are (`getCommonSupertype`):
// literals of one primitive are unioned, and otherwise the leftmost one
// stays unless it is a subtype of the next. And the argument's members a
// non-naked member matches identically or closely (`number[]` against
// `Array`) are taken out before the rest becomes that candidate.

declare function pick<T>(x: T | number[]): T;
declare function choose<T>(value: T | (() => T), values: T[]): T;
declare function hookP<S>(init: S | Promise<S>): [S];
declare function hookA<S>(init: S | Array<S>): [S];
declare function hookL<S>(init: S | PromiseLike<S>): [S];

export function okPickRemovesTheMatchedArray(input: string | number[]) {
  const r: string = pick(input);
  return r;
}
export function badPickRemovesTheMatchedArray(input: string | number[]) {
  const n: number = pick(input);
  return n;
}
export function okChooseLiteralThenItsPrimitive(ss: string[]) {
  let v = choose("a", ss);
  v = "b";
  return v;
}
export function okChoosePrimitiveThenItsLiteral(s: string, as_: "a"[]) {
  const v: string = choose(s, as_);
  return v;
}
export function okChooseTwoLiteralsUnion(bs: "b"[]) {
  const v: "a" | "b" = choose("a", bs);
  return v;
}
export function badChooseUnrelatedKeepsTheLeftmost(ns: number[]) {
  return choose("a", ns);
}
export function okHooksWidenThroughApplied() {
  const [p] = hookP("light");
  const [a] = hookA("light");
  const [l] = hookL("light");
  return [p === "dark", a === "dark", l === "dark"];
}
export function badHookWidenedState() {
  const [p] = hookP("light");
  const n: number = p;
  return n;
}

// Every such candidate takes part, an `any` candidate is the supertype of
// the rest, and an object argument can be a thenable that a `PromiseLike`
// member matches structurally, so it is not the naked member's.
declare function both<T>(a: T | undefined, b: T | undefined): T;
declare function unwrap<T>(x: T | PromiseLike<T>): T;
export function okBothLiteralsUnion() {
  const u: "a" | "b" = both("a", "b");
  return both("a", "b") === "b" ? u : u;
}
export function badBothUnrelatedKeepsTheLeftmost() {
  return both("a", 1);
}
export function okAnyCandidateWins(anys: any[]) {
  const n: number = choose("a", anys);
  return n;
}
export function okThenableIsNotTheNakedMember(p: { then(f?: (v: number) => any): any }) {
  const n: number = unwrap(p);
  return n;
}
export function badUnwrapPrimitive() {
  const s: string = unwrap(5);
  return s;
}
