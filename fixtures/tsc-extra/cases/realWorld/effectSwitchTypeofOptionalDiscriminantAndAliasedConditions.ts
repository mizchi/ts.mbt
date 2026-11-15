// @strict: true
// @target: esnext

// effect narrowing: `switch (typeof x)`, an optional-chain discriminant
// (`e?._tag === "Chr"`), a guard to a subtype of the declared interface, and
// an aliased `Array.isArray` condition.

interface Constraint { readonly mut: string }
interface declare<T> extends Constraint { readonly t: T }
interface Rec extends declare<number> { readonly r: number }
function okDeclareBase(r: Rec): string { return r.mut }
const one = BigInt(1)
function okBigUnion(m: bigint | undefined, b: bigint): bigint {
  const d = m === undefined ? -one : one
  return b * d
}
function okSwitchTypeof(x: number | bigint | string): string {
  switch (typeof x) {
    case "number": return x.toFixed(1)
    case "bigint": return x.toString()
    default: return x.toUpperCase()
  }
}
function badSwitchTypeof(x: number | string): boolean {
  switch (typeof x) {
    case "number": { const b: boolean = x; return b }
  }
  return false
}
interface Lit { readonly _tag: "Lit"; readonly value: string }
interface Chr { readonly _tag: "Chr"; readonly intervals: number[] }
declare function esc(): Lit | Chr | undefined
function okOptDisc(): number[] | undefined {
  const e = esc()
  return e?._tag === "Chr" ? e.intervals : undefined
}
function badOptDisc(): string | undefined {
  const e = esc()
  return e?._tag === "Chr" ? e.value : undefined
}
interface Eq { eq(that: Eq): boolean }
interface V4 extends Eq { readonly _tag: "V4"; toJSON(): unknown }
interface V6 extends Eq { readonly _tag: "V6"; words(): number[] }
declare function isV4(u: unknown): u is V4
declare function v4(a: V4): number
declare function v6(a: V6): number
function okSubtypeGuard(that: Eq) { if (isV4(that)) { v4(that) } }
function badSubtypeGuard(that: Eq) { if (isV4(that)) { v6(that) } }
function okAlias(value: object) {
  const isArr = Array.isArray(value)
  return isArr ? value.length : 0
}
function badAlias(value: object) {
  const isArr = Array.isArray(value)
  if (!isArr) { return value.length }
  return 0
}
