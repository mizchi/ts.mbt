// @strict: true
// @target: esnext

// effect shapes: a type predicate as a `boolean` value, an object into an
// open `[x: string]: unknown` record, an array literal against a nullable
// tuple, `typeof x?.y === "object"`, `typeof f === "function"` keeping
// the callable member.

function okPred(u: unknown): u is string { return typeof u === "string" }
const okPredValue: (u: unknown) => boolean = okPred
function badPred(u: unknown): u is string { return 1 }
interface JsonSchema { [x: string]: unknown }
function okOpen(): JsonSchema { const schema = { allOf: [1].map((x) => x) }; return schema }
type CR = readonly [minimum: bigint | undefined, maximum: bigint | undefined]
declare const m: bigint | undefined
function okTuple(): CR | undefined { return [m, m] }
function badTuple(): CR | undefined { return ["a", 1n] }
declare const proc: { stdout?: { isTTY?: boolean } } | undefined
function okTypeofChain() { return typeof proc?.stdout === "object" && proc.stdout.isTTY === true }
function okTypeofFn(o: ((n: number) => string) | string): string { return typeof o === "function" ? o(1) : o }
function badTypeofFn(o: ((n: number) => string) | string): string { return typeof o === "function" ? o("x") : o }
declare const xs: Array<string>
function okNested(r: string) {
  const path = r.startsWith("#") ? (xs.length > 0 ? xs : undefined) : undefined
  return path !== undefined ? path.slice(1) : []
}
