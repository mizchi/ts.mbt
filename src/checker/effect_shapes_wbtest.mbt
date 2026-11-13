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
  issues.iter().any(fn(i) { i.path.contains("function \{fname} ") })
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
