// Shapes from effect (4.x) that this checker either failed to PARSE, ran
// out of time / memory on, or reported on lines tsc accepts. Every `ok*`
// function is accepted by tsc and every `bad*` is an error there (probed).

///|
fn eff_parses(src : String) -> Bool {
  let _ = @parser.parse_module_from_source_with_const_values(src, {}) catch {
    _ => return false
  }
  true
}

///|
fn eff_issues(src : String) -> Array[ExprIssue] {
  check_module_function_bodies(parse_module_or_empty(src))
}

///|
fn eff_has(issues : Array[ExprIssue], fname : String) -> Bool {
  issues
  .iter()
  .any(fn(i) {
    i.path.contains("function \{fname} ") || i.path == "function \{fname}"
  })
}

///|
test "effect: parser shapes that used to fail the whole module" {
  // Newline-separated generic call signatures: `<B>` on the next line is a
  // new member, not type arguments of the previous return type.
  assert_true(
    eff_parses(
      "export const dual: {\n  <A>(x: A): A\n  <B>(y: B): B\n} = null as any\n",
    ),
  )
  // A heritage clause is a call with trailing type arguments.
  assert_true(
    eff_parses(
      "declare function TaggedError(t: string): new <A>(a: A) => A\nexport class E extends TaggedError(\"E\")<{\n  message: string\n}> {}\n",
    ),
  )
  // A lower-case instantiation expression followed by `,`.
  assert_true(
    eff_parses(
      "declare const fx: <A>(a: A) => A\ndeclare function g(a: unknown, b: unknown): void\ng(fx<string>, 1)\n",
    ),
  )
  // A contextual keyword as an interface name.
  assert_true(eff_parses("export interface declare<T> { a: T }\n"))
  // A type parameter and a namespace of one name: `P.Encoded` is the
  // namespace member.
  assert_true(
    eff_parses(
      "declare namespace P { type Encoded = string }\ninterface D<P extends string> {\n  readonly f?: ((p: P.Encoded) => number) | undefined\n}\n",
    ),
  )
}

///|
test "effect: TS1099 and TS2689 take over what the parse failures caught" {
  let issues = eff_issues(
    "declare function fx<T>(x: T): T;\nfunction bad1(): unknown { return fx<>; }\nfunction ok1(): unknown { return fx<string>; }\n",
  )
  assert_true(
    issues.iter().any(fn(i) { i.message.contains("cannot be empty") }),
  )
  let issues2 = eff_issues(
    "interface Base<T> { x: T }\nclass D0 extends Base<string> {}\ninterface X { a: number }\ndeclare var X: { new (): X };\nclass D1 extends X {}\nclass D2 extends Error {}\n",
  )
  let n = issues2
    .filter(fn(i) { i.message.contains("cannot extend an interface") })
    .length()
  @test.assert_eq(n, 1)
}

///|
test "effect: lib values on globalThis, augmented lib interfaces, local class shadow" {
  let src =
    #|export const Arr = globalThis.Array;
    #|declare global { interface Error { readonly code?: number } }
    #|abstract class Class {}
    #|interface Box { v: number }
    #|function ok1(e: Error): unknown { return [e.message, e.stack, e.code]; }
    #|function ok2(C: new (v: number) => Box): number { return new C(1).v; }
    #|function ok3(a: unknown, b: unknown): boolean { return a === b; }
  let issues = eff_issues(src)
  for f in ["ok1", "ok2", "ok3"] {
    assert_false(eff_has(issues, f), msg=f)
  }
  assert_false(issues.iter().any(fn(i) { i.path.contains("globalThis") }))
}

///|
test "effect: an inherited generic overload set is not judged by its first member" {
  let src =
    #|interface Pipeable {
    #|  pipe<A>(this: A): A
    #|  pipe<A, B = never>(this: A, ab: (_: A) => B): B
    #|}
    #|interface Eff<A> extends Pipeable { readonly a: A }
    #|interface One { m(x: number): number }
    #|declare const e: Eff<number>;
    #|declare const o: One;
    #|function ok(): unknown { return e.pipe((x) => x); }
    #|function bad(): unknown { return o.m(1, 2); }
  let issues = eff_issues(src)
  assert_false(eff_has(issues, "ok"))
  assert_true(eff_has(issues, "bad"))
}

///|
test "effect: predicates through an overloaded const and `in` on object" {
  let src =
    #|declare const hasProperty: {
    #|  <P extends PropertyKey>(property: P): (self: unknown) => self is { [K in P]: unknown }
    #|  <P extends PropertyKey>(self: unknown, property: P): self is { [K in P]: unknown }
    #|}
    #|function ok1(u: unknown): unknown { if (hasProperty(u, "then")) { return u.then } return 0 }
    #|function ok2(u: object): unknown { if ("then" in u) { return u.then } return 0 }
    #|function bad(u: object): unknown { return u.then }
  let issues = eff_issues(src)
  assert_false(eff_has(issues, "ok1"))
  assert_false(eff_has(issues, "ok2"))
  assert_true(eff_has(issues, "bad"))
}

///|
test "effect: nested callbacks are checked in polynomial time" {
  // 3^depth before the contextual-walk record: depth 14 took ~15 s.
  let mut body = "1"
  for _ in 0..<40 {
    body = "f(() => " + body + ")"
  }
  let src = "declare function f<A>(g: () => A): A;\nfunction t(): unknown { return " +
    body +
    " }\n"
  let _ = eff_issues(src)
}

///|
test "effect: arrow-const guards narrow, generic guards narrow" {
  let src =
    #|interface Success<A, E> { readonly _tag: "Success"; readonly success: A }
    #|interface Failure<A, E> { readonly _tag: "Failure"; readonly failure: E }
    #|type Result<A, E> = Success<A, E> | Failure<A, E>
    #|const isResult = (input: unknown): input is Result<unknown, unknown> => typeof input === "object"
    #|const isSuccess = <A, E>(result: Result<A, E>): result is Success<A, E> => result._tag === "Success"
    #|interface S { readonly success: number }
    #|interface F { readonly failure: string }
    #|type R = S | F
    #|const isS = (r: R): r is S => "success" in r
    #|function okChain(that: unknown) { return isResult(that) && isSuccess(that) && that.success }
    #|function okIf(that: unknown) { if (isResult(that) && isSuccess(that)) { return that.success } return 0 }
    #|function okGeneric(that: Result<number, string>) { return isSuccess(that) && that.success }
    #|function badNarrowed(r: R) { if (isS(r)) { const n: string = r.success } }
    #|function badElse(r: R) { if (!isS(r)) { return r.success } return 0 }
  let issues = eff_issues(src)
  assert_false(eff_has(issues, "okChain"))
  assert_false(eff_has(issues, "okIf"))
  assert_false(eff_has(issues, "okGeneric"))
  assert_true(eff_has(issues, "badNarrowed"))
  assert_true(eff_has(issues, "badElse"))
}

///|
test "effect: destructuring an any or a ReadonlyMap entry" {
  let src =
    #|declare const m: ReadonlyMap<string, any>
    #|function okAny(x: any): void { for (const [key, value] of x) { m.has(key) } }
    #|function okMap(r: ReadonlyMap<string, number>) { for (const [k, v] of r) { const s: string = k; const n: number = v } }
    #|function badMap(r: ReadonlyMap<string, number>) { for (const [k, v] of r) { const s: number = k } }
  let issues = eff_issues(src)
  assert_false(eff_has(issues, "okAny"))
  assert_false(eff_has(issues, "okMap"))
  assert_true(eff_has(issues, "badMap"))
}

///|
test "effect: || then-branch, conditional branches, alias index keys, bigint" {
  let src =
    #|interface O { readonly a?: string | undefined; readonly b?: string | undefined }
    #|function okOr(o?: O) { if (o?.a !== undefined || o?.b !== undefined) { return o.a ?? o.b } return "" }
    #|function badOr(o: O | undefined, n: string | number) { if (typeof n === "string" || o === undefined) { return o.a } return "" }
    #|function okCond(capacity: number | { readonly capacity: number; readonly replay?: number | undefined }) {
    #|  const options = typeof capacity === "number" ? { capacity } : capacity
    #|  return options.capacity
    #|}
    #|function okIndex(x: { [k: PropertyKey]: unknown }) { return x.anything }
    #|function okBig(num: bigint, b: boolean) { num = b ? -num : num; const q: bigint = num / num; return q }
    #|function okBigCtor() { const d = BigInt(1024); const q: bigint = d ** BigInt(2); return q }
    #|function badBig() { const s: string = BigInt(1); return s }
  let issues = eff_issues(src)
  assert_false(eff_has(issues, "okOr"))
  assert_true(eff_has(issues, "badOr"))
  assert_false(eff_has(issues, "okCond"))
  assert_false(eff_has(issues, "okIndex"))
  assert_false(eff_has(issues, "okBig"))
  assert_false(eff_has(issues, "okBigCtor"))
  assert_true(eff_has(issues, "badBig"))
}

///|
test "effect: a nested union read off a union receiver is flattened" {
  let src =
    #|export interface Context { readonly isOptional: boolean }
    #|interface ASTNode { readonly context: Context | undefined; readonly _tag: string }
    #|class A implements ASTNode { readonly _tag = "A"; readonly context: Context | undefined = undefined }
    #|class B implements ASTNode { readonly _tag = "B"; readonly context: Context | undefined = undefined }
    #|type AST = A | B
    #|function okNested(ast: AST): boolean { return ast.context?.isOptional ?? false }
  let issues = eff_issues(src)
  assert_false(eff_has(issues, "okNested"))
}

///|
test "effect: batch FS control flow — loops, try/finally, fall-through, joins" {
  let src =
    #|function okFinally(): number { try { return 1 } finally { console.log(1) } }
    #|function okLoop(x: number): number { outer: while (true) { if (x > 1) { continue outer } return 1 } }
    #|function badLoop(x: number): number { while (true) { if (x) break } }
    #|function badCatch(): number { try { return 1 } catch { console.log(1) } }
    #|interface Ref { readonly _tag: "Ref"; readonly $ref: string }
    #|interface Str { readonly _tag: "Str"; readonly checks: Array<number> }
    #|interface Num { readonly _tag: "Num"; readonly checks: Array<number> }
    #|type Rep = Ref | Str | Num
    #|function okJoin(part: Rep): string {
    #|  let exact = true
    #|  if (part._tag !== "Ref" && part.checks.length > 0) exact = false
    #|  switch (part._tag) { case "Ref": return part.$ref }
    #|  return String(exact)
    #|}
    #|function okFall(part: Rep): boolean {
    #|  switch (part._tag) {
    #|    case "Str":
    #|    case "Num": { return part._tag === "Str" || part.checks.length > 0 }
    #|  }
    #|  return false
    #|}
    #|interface F { _parent: F | undefined; n: number }
    #|function okForUpdate(f0: F) { for (let cur = f0 as F | undefined; cur; cur = cur._parent) { cur.n } }
    #|function okNullishAssign() { let keys: Array<string>; return (e: string) => { keys ??= ["a"]; return keys.includes(e) } }
    #|function badUnassigned() { let q: number; return () => q }
  let issues = eff_issues(src)
  assert_false(eff_has(issues, "okFinally"))
  assert_false(eff_has(issues, "okLoop"))
  assert_true(eff_has(issues, "badLoop"))
  assert_true(eff_has(issues, "badCatch"))
  assert_false(eff_has(issues, "okJoin"))
  assert_false(eff_has(issues, "okFall"))
  assert_false(eff_has(issues, "okForUpdate"))
  assert_false(eff_has(issues, "okNullishAssign"))
  assert_true(eff_has(issues, "badUnassigned"))
}

///|
test "effect: batch FS shapes — predicates, open records, nullable tuples, typeof" {
  let src =
    #|function okPred(u: unknown): u is string { return typeof u === "string" }
    #|const okPredValue: (u: unknown) => boolean = okPred
    #|function badPred(u: unknown): u is string { return 1 }
    #|interface JsonSchema { [x: string]: unknown }
    #|function okOpen(): JsonSchema { const schema = { allOf: [1].map((x) => x) }; return schema }
    #|type CR = readonly [minimum: bigint | undefined, maximum: bigint | undefined]
    #|declare const m: bigint | undefined
    #|function okTuple(): CR | undefined { return [m, m] }
    #|function badTuple(): CR | undefined { return ["a", 1n] }
    #|declare const proc: { stdout?: { isTTY?: boolean } } | undefined
    #|function okTypeofChain() { return typeof proc?.stdout === "object" && proc.stdout.isTTY === true }
    #|function okTypeofFn(o: ((n: number) => string) | string): string { return typeof o === "function" ? o(1) : o }
    #|function badTypeofFn(o: ((n: number) => string) | string): string { return typeof o === "function" ? o("x") : o }
    #|declare const xs: Array<string>
    #|function okNested(r: string) {
    #|  const path = r.startsWith("#") ? (xs.length > 0 ? xs : undefined) : undefined
    #|  return path !== undefined ? path.slice(1) : []
    #|}
  let issues = eff_issues(src)
  assert_false(eff_has(issues, "okPred"))
  assert_true(eff_has(issues, "badPred"))
  assert_false(eff_has(issues, "okOpen"))
  assert_false(eff_has(issues, "okTuple"))
  assert_true(eff_has(issues, "badTuple"))
  assert_false(eff_has(issues, "okTypeofChain"))
  assert_false(eff_has(issues, "okTypeofFn"))
  assert_true(eff_has(issues, "badTypeofFn"))
  assert_false(eff_has(issues, "okNested"))
}

///|
test "TS 7.1: ES2026 lib static guards and augmented lib interfaces" {
  let src =
    #|declare const v: unknown;
    #|function okIsError() { if (Error.isError(v)) { const m: string = v.message; return m } return "" }
    #|function badIsError() { if (Error.isError(v)) { const n: number = v.message; return n } return 0 }
    #|declare global { interface RawJSON { f?(): string } }
    #|function okRaw(x: RawJSON): string { return x.rawJSON }
    #|interface Mine { a: number }
    #|function badMine(m: Mine) { return m.nope }
  let issues = eff_issues(src)
  assert_false(eff_has(issues, "okIsError"))
  assert_true(eff_has(issues, "badIsError"))
  assert_false(eff_has(issues, "okRaw"))
  assert_true(eff_has(issues, "badMine"))
}

///|
test "effect: batch FU narrowing — switch typeof, optional discriminant, guards" {
  let src =
    #|interface Constraint { readonly mut: string }
    #|interface declare<T> extends Constraint { readonly t: T }
    #|interface Rec extends declare<number> { readonly r: number }
    #|function okDeclareBase(r: Rec): string { return r.mut }
    #|const one = BigInt(1)
    #|function okBigUnion(m: bigint | undefined, b: bigint): bigint {
    #|  const d = m === undefined ? -one : one
    #|  return b * d
    #|}
    #|function okSwitchTypeof(x: number | bigint | string): string {
    #|  switch (typeof x) {
    #|    case "number": return x.toFixed(1)
    #|    case "bigint": return x.toString()
    #|    default: return x.toUpperCase()
    #|  }
    #|}
    #|function badSwitchTypeof(x: number | string): boolean {
    #|  switch (typeof x) {
    #|    case "number": { const b: boolean = x; return b }
    #|  }
    #|  return false
    #|}
    #|interface Lit { readonly _tag: "Lit"; readonly value: string }
    #|interface Chr { readonly _tag: "Chr"; readonly intervals: number[] }
    #|declare function esc(): Lit | Chr | undefined
    #|function okOptDisc(): number[] | undefined {
    #|  const e = esc()
    #|  return e?._tag === "Chr" ? e.intervals : undefined
    #|}
    #|function badOptDisc(): string | undefined {
    #|  const e = esc()
    #|  return e?._tag === "Chr" ? e.value : undefined
    #|}
    #|interface Eq { eq(that: Eq): boolean }
    #|interface V4 extends Eq { readonly _tag: "V4"; toJSON(): unknown }
    #|interface V6 extends Eq { readonly _tag: "V6"; words(): number[] }
    #|declare function isV4(u: unknown): u is V4
    #|declare function v4(a: V4): number
    #|declare function v6(a: V6): number
    #|function okSubtypeGuard(that: Eq) { if (isV4(that)) { v4(that) } }
    #|function badSubtypeGuard(that: Eq) { if (isV4(that)) { v6(that) } }
    #|function okAlias(value: object) {
    #|  const isArr = Array.isArray(value)
    #|  return isArr ? value.length : 0
    #|}
    #|function badAlias(value: object) {
    #|  const isArr = Array.isArray(value)
    #|  if (!isArr) { return value.length }
    #|  return 0
    #|}
  let issues = eff_issues(src)
  assert_false(eff_has(issues, "okDeclareBase"))
  assert_false(eff_has(issues, "okBigUnion"))
  assert_false(eff_has(issues, "okSwitchTypeof"))
  assert_true(eff_has(issues, "badSwitchTypeof"))
  assert_false(eff_has(issues, "okOptDisc"))
  assert_true(eff_has(issues, "badOptDisc"))
  assert_false(eff_has(issues, "okSubtypeGuard"))
  assert_true(eff_has(issues, "badSubtypeGuard"))
  assert_false(eff_has(issues, "okAlias"))
  assert_true(eff_has(issues, "badAlias"))
}

///|
test "effect: batch FU control flow and unknown" {
  let src =
    #|interface S { _tag: "S" } interface N { _tag: "N" }
    #|function okEmptyLabels(a: S | N): boolean {
    #|  switch (a._tag) {
    #|    case "S":
    #|    case "N":
    #|      return true
    #|    default:
    #|      return false
    #|  }
    #|}
    #|function fail(e: unknown): never { throw e }
    #|function noop(e: unknown): void { }
    #|function okNeverCall(f: () => number): number {
    #|  try { return f() } catch (e) { fail(e) }
    #|}
    #|function badVoidCall(f: () => number): number {
    #|  try { return f() } catch (e) { noop(e) }
    #|}
    #|interface J { [x: string]: unknown; req: number }
    #|function okDeleteIndexed(j: J) { delete j.extra }
    #|function badDeleteRequired(j: J) { delete j.req }
    #|declare function obj(x: object): void
    #|function okUnknownTruthy(x: unknown) {
    #|  if (!x) { return }
    #|  if (typeof x === "object") { obj(x) }
    #|}
    #|function okUnknownNotNull(x: unknown) {
    #|  if (x === null) { return }
    #|  if (typeof x === "object") { obj(x) }
    #|}
    #|function badUnknownTypeof(x: unknown) {
    #|  if (typeof x === "object") { obj(x) }
    #|}
  let issues = eff_issues(src)
  assert_false(eff_has(issues, "okEmptyLabels"))
  assert_false(eff_has(issues, "okNeverCall"))
  assert_true(eff_has(issues, "badVoidCall"))
  assert_false(eff_has(issues, "okDeleteIndexed"))
  assert_true(eff_has(issues, "badDeleteRequired"))
  assert_false(eff_has(issues, "okUnknownTruthy"))
  assert_false(eff_has(issues, "okUnknownNotNull"))
  assert_true(eff_has(issues, "badUnknownTypeof"))
}

///|
test "batch FU: private-name clash, readonly literal fields, local classes" {
  let src =
    #|class E { static #a() {} #a() {} }
    #|class H { get #f() { return 0 } set #f(v: number) {} static #g = 1 }
    #|class D {
    #|  readonly noWiden = 1
    #|  readonly typed: number = 1
    #|  constructor() { this.noWiden = 5; this.typed = 7 }
    #|  m() { let y = this.noWiden; y = 2; return y }
    #|}
    #|function outer(tag: string) {
    #|  class Local { readonly t = tag; m() { return tag } }
    #|  return Local
    #|}
  let issues = eff_issues(src)
  let msgs = issues.map(fn(i) { i.path + ": " + i.message })
  assert_true(
    msgs.iter().any(fn(m) { m.contains("class E") && m.contains("#a") }),
  )
  assert_false(msgs.iter().any(fn(m) { m.contains("class H") }))
  assert_true(msgs.iter().any(fn(m) { m.contains(".noWiden") }))
  assert_false(msgs.iter().any(fn(m) { m.contains(".typed") }))
  assert_false(msgs.iter().any(fn(m) { m.contains("D.m") }))
  assert_false(msgs.iter().any(fn(m) { m.contains("cannot find name `tag`") }))
}

///|
test "batch FV: fresh literal widening, NonNullable<T>, intersection and Extract targets" {
  let src =
    #|declare function useState<S>(init: S): [S, (s: S) => void];
    #|declare function box<T>(x: T): { get(): T; set(v: T): void };
    #|declare function id<T>(x: T): T;
    #|declare function nest<T>(x: T[]): { v: T };
    #|function okUseState() { const [v, setV] = useState(""); setV("a"); }
    #|function okUseStateVar() { const initial = ""; const [v, setV] = useState(initial); setV("b"); }
    #|function okBox() { const b = box("a"); b.set("b"); }
    #|function okLetFromConst() { const a = "x"; let b = a; b = "y"; }
    #|function badIdKeepsLiteral() { const s: "q" = id("r"); }
    #|function okIdKeepsLiteral() { const s: "q" = id("q"); }
    #|function okNestNotFresh(arr: "z"[]) { const n: "z" = nest(arr).v; }
    #|function badNonNullable<T>(x: T, y: NonNullable<T>) { x = y; y = x; }
    #|function badEmptyIntersection<T>(x: T, y: T & {}) { y = x; }
    #|function okNonNullableBack<T>(x: T, y: NonNullable<T>) { x = y; }
    #|function okBothNonNullable<T>(x: NonNullable<T>, y: NonNullable<T>) { y = x; }
    #|type A = { a: number };
    #|type B = { b: string };
    #|function badExcess() { let ab: A & B = { a: 1, b: "x", c: 2 }; }
    #|function badMissing() { let ab: A & B = { a: 1 }; }
    #|function okExact() { let ab: A & B = { a: 1, b: "x" }; }
    #|function okOptional() { let ab: A & { b?: string } = { a: 1 }; }
    #|function okIndexPart() { let ab: A & { [k: string]: number } = { a: 1, zz: 2 }; }
    #|type Foo = { foo: string };
    #|type Bar = { bar: string };
    #|declare function fooBar(x: { foo: string, bar: string }): void;
    #|declare function fooBat(x: { foo: string, bat: string }): void;
    #|type Extract2<T, U, V> = T extends U ? T extends V ? T : never : never;
    #|function okExtract<T>(x: Extract<Extract<T, Foo>, Bar>, y: Extract<T, Foo & Bar>, z: Extract2<T, Foo, Bar>) { fooBar(x); fooBar(y); fooBar(z); }
    #|function badExtractNested<T>(x: Extract<Extract<T, Foo>, Bar>) { fooBat(x); }
    #|function badExtractIntersection<T>(y: Extract<T, Foo & Bar>) { fooBat(y); }
    #|function badExtractAlias<T>(z: Extract2<T, Foo, Bar>) { fooBat(z); }
  let issues = eff_issues(src)
  for ok in [
    "okUseState", "okUseStateVar", "okBox", "okLetFromConst", "okIdKeepsLiteral",
    "okNestNotFresh", "okNonNullableBack", "okBothNonNullable", "okExact", "okOptional",
    "okIndexPart", "okExtract",
  ] {
    assert_false(eff_has(issues, ok), msg=ok)
  }
  for bad in [
    "badIdKeepsLiteral", "badNonNullable", "badEmptyIntersection", "badExcess",
    "badMissing", "badExtractNested", "badExtractIntersection", "badExtractAlias",
  ] {
    assert_true(eff_has(issues, bad), msg=bad)
  }
}

///|
test "batch FV: optional callbacks, generic method arguments, overloads taking Object" {
  let src =
    #|interface Opts { map?: (i: { num: number }) => void }
    #|declare function use(o: Opts): void;
    #|function badOptionalCallback() { use({ map(i) { i.nonexistent; } }); }
    #|function okOptionalCallback() { use({ map: (i) => { i.num.toFixed(); } }); }
    #|interface Store<T> { get<K extends keyof T>(k: K): T[K]; put<K extends string>(k: K): void }
    #|function okStoreGet(st: Store<{ a: 1 }>) { st.get("a"); st.put("x"); }
    #|function badStoreGet(st: Store<{ a: 1 }>) { st.get("b"); }
    #|function badStorePut(st: Store<{ a: 1 }>) { st.put(1); }
    #|interface P<T> { then<U>(cb: (x: T) => P<U>): P<U> }
    #|declare function tfn(n: number): P<number>;
    #|declare function tstr(s: string): P<string>;
    #|function okThen(np: P<number>) { np.then(tfn); }
    #|function badThen(np: P<number>) { np.then(tstr); }
    #|declare function takesObject(x: Object): string;
    #|declare function takesObject(x: number): number;
    #|function badObjectOverload() { const r: number = takesObject(1); }
    #|function okObjectOverload() { const r: string = takesObject(1); }
  let issues = eff_issues(src)
  for ok in ["okOptionalCallback", "okStoreGet", "okThen", "okObjectOverload"] {
    assert_false(eff_has(issues, ok), msg=ok)
  }
  for bad in [
    "badOptionalCallback", "badStoreGet", "badStorePut", "badThen", "badObjectOverload",
  ] {
    assert_true(eff_has(issues, bad), msg=bad)
  }
}
