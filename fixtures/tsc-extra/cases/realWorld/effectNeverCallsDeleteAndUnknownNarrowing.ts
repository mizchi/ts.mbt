// @strict: true
// @target: esnext

// effect control flow: a call returning `never` ends a path in `catch`,
// `delete` on an index-signature member vs a required one, and `unknown`
// narrowed by truthiness and `=== null` before `typeof x === "object"`.

interface S { _tag: "S" } interface N { _tag: "N" }
function okEmptyLabels(a: S | N): boolean {
  switch (a._tag) {
    case "S":
    case "N":
      return true
    default:
      return false
  }
}
function fail(e: unknown): never { throw e }
function noop(e: unknown): void { }
function okNeverCall(f: () => number): number {
  try { return f() } catch (e) { fail(e) }
}
function badVoidCall(f: () => number): number {
  try { return f() } catch (e) { noop(e) }
}
interface J { [x: string]: unknown; req: number }
function okDeleteIndexed(j: J) { delete j.extra }
function badDeleteRequired(j: J) { delete j.req }
declare function obj(x: object): void
function okUnknownTruthy(x: unknown) {
  if (!x) { return }
  if (typeof x === "object") { obj(x) }
}
function okUnknownNotNull(x: unknown) {
  if (x === null) { return }
  if (typeof x === "object") { obj(x) }
}
function badUnknownTypeof(x: unknown) {
  if (typeof x === "object") { obj(x) }
}
