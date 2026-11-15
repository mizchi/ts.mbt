// @strict: true
// @target: esnext

// effect control flow: `try`/`finally` and `while (true)` as exits, an
// `if` join over a discriminated union, `switch` fall-through, a `for`
// update under the condition's narrowing, and `??=` before a read.

function okFinally(): number { try { return 1 } finally { console.log(1) } }
function okLoop(x: number): number { outer: while (true) { if (x > 1) { continue outer } return 1 } }
function badLoop(x: number): number { while (true) { if (x) break } }
function badCatch(): number { try { return 1 } catch { console.log(1) } }
interface Ref { readonly _tag: "Ref"; readonly $ref: string }
interface Str { readonly _tag: "Str"; readonly checks: Array<number> }
interface Num { readonly _tag: "Num"; readonly checks: Array<number> }
type Rep = Ref | Str | Num
function okJoin(part: Rep): string {
  let exact = true
  if (part._tag !== "Ref" && part.checks.length > 0) exact = false
  switch (part._tag) { case "Ref": return part.$ref }
  return String(exact)
}
function okFall(part: Rep): boolean {
  switch (part._tag) {
    case "Str":
    case "Num": { return part._tag === "Str" || part.checks.length > 0 }
  }
  return false
}
interface F { _parent: F | undefined; n: number }
function okForUpdate(f0: F) { for (let cur = f0 as F | undefined; cur; cur = cur._parent) { cur.n } }
function okNullishAssign() { let keys: Array<string>; return (e: string) => { keys ??= ["a"]; return keys.includes(e) } }
function badUnassigned() { let q: number; return () => q }
