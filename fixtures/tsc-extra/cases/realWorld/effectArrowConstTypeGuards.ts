// @strict: true
// @target: esnext

// effect `Result`: type guards written as arrow `const`s, generic ones
// included, narrow through `&&`, `if` and `!`.

interface Success<A, E> { readonly _tag: "Success"; readonly success: A }
interface Failure<A, E> { readonly _tag: "Failure"; readonly failure: E }
type Result<A, E> = Success<A, E> | Failure<A, E>
const isResult = (input: unknown): input is Result<unknown, unknown> => typeof input === "object"
const isSuccess = <A, E>(result: Result<A, E>): result is Success<A, E> => result._tag === "Success"
interface S { readonly success: number }
interface F { readonly failure: string }
type R = S | F
const isS = (r: R): r is S => "success" in r
function okChain(that: unknown) { return isResult(that) && isSuccess(that) && that.success }
function okIf(that: unknown) { if (isResult(that) && isSuccess(that)) { return that.success } return 0 }
function okGeneric(that: Result<number, string>) { return isSuccess(that) && that.success }
function badNarrowed(r: R) { if (isS(r)) { const n: string = r.success } }
function badElse(r: R) { if (!isS(r)) { return r.success } return 0 }
