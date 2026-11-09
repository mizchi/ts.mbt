// What a member inherited from a GENERIC base class reads as in a subclass,
// and three neighbouring false positives the same zod v3 shape exposed. Every
// "silent" case below is ACCEPTED by tsc and every "reports" case is an error
// there; each was probed rather than reasoned.

///|
fn generic_base_issues(src : String) -> Array[ExprIssue] {
  check_module_function_bodies(parse_module_or_empty(src))
}

///|
fn generic_base_reports(src : String, needle : String) -> Bool {
  generic_base_issues(src).iter().any(fn(i) { i.message.contains(needle) })
}

///|
test "generic base: an inherited member reads at the extends clause's arguments" {
  // zod v3's whole schema hierarchy: `_def: Def` on the base, and every
  // subclass reads `this._def.<its own def's field>`.
  let src =
    #|interface BaseDef { typeName: string }
    #|interface StrDef extends BaseDef { checks: number[] }
    #|abstract class Base<Out, Def extends BaseDef = BaseDef> {
    #|  readonly _def: Def;
    #|  constructor(def: Def) { this._def = def; }
    #|}
    #|class Str extends Base<string, StrDef> {
    #|  count(): number { return this._def.checks.length; }
    #|  static make(): Str { return new Str({ typeName: "s", checks: [] }); }
    #|}
  assert_eq(generic_base_issues(src).length(), 0)
}

///|
test "generic base: the substituted member is still checked" {
  // The fix must make the member PRECISE, not opaque: a field the
  // argument's type does not have is still reported, against that type.
  let src =
    #|interface BaseDef { typeName: string }
    #|interface StrDef extends BaseDef { checks: number[] }
    #|abstract class Base<Def extends BaseDef = BaseDef> {
    #|  readonly _def: Def;
    #|  constructor(def: Def) { this._def = def; }
    #|}
    #|class Str extends Base<StrDef> {
    #|  m(): number { return this._def.nope; }
    #|  n(): number { const c: string = this._def.checks; return 0; }
    #|}
  assert_true(generic_base_reports(src, "`nope` does not exist on `StrDef`"))
  assert_true(generic_base_reports(src, "expected `string` but got `number[]`"))
}

///|
test "generic base: the inherited constructor takes the argument's type" {
  let src =
    #|interface BaseDef { typeName: string }
    #|interface StrDef extends BaseDef { checks: number[] }
    #|abstract class Base<Def extends BaseDef = BaseDef> {
    #|  readonly _def: Def;
    #|  constructor(def: Def) { this._def = def; }
    #|}
    #|class Str extends Base<StrDef> {}
    #|class Mid<D extends BaseDef> extends Base<D> {}
    #|class Leaf extends Mid<StrDef> {}
    #|function f(): void {
    #|  const a = new Str({ typeName: "s", checks: [] });
    #|  const b = new Leaf({ typeName: "s", checks: [] });
    #|  const c = new Str({ typeName: "s", checks: [], extra: 1 });
    #|}
  let issues = generic_base_issues(src)
  // Substitution composes through `Mid<D>` -> `Base<D>`.
  assert_false(issues.iter().any(fn(i) { i.path.contains("new `Leaf`") }))
  assert_false(
    issues.iter().any(fn(i) { i.path.contains("new `Str` arg[0].checks") }),
  )
  // ...and an excess property against `StrDef` is still an excess property.
  assert_true(
    issues.iter().any(fn(i) { i.path.contains("new `Str` arg[0].extra") }),
  )
}

///|
test "readonly: writable in the declaring class's constructor only" {
  let src =
    #|class A {
    #|  readonly x: number;
    #|  constructor(v: number) { if (v) { this.x = v; } else { this.x = 0; } }
    #|}
    #|class C {
    #|  readonly y: number = 1;
    #|  m(): void { if (1) { this.y = 3; } }
    #|}
  let issues = generic_base_issues(src)
  assert_false(issues.iter().any(fn(i) { i.path.contains("A.constructor") }))
  assert_true(
    issues
    .iter()
    .any(fn(i) {
      i.path.contains("C.m") &&
      i.message.contains("`y` because it is read-only")
    }),
  )
}

///|
test "object literal: an own getter provides its property" {
  // zod's `ZodCatch` hands `catchValue` exactly this object.
  let src =
    #|declare const f: (ctx: { error: Error; input: unknown }) => void;
    #|function g(): void {
    #|  f({ get error() { return new Error("x"); }, input: 1 });
    #|  f({ input: 1 });
    #|}
  let issues = generic_base_issues(src)
  let missing = issues.filter(fn(i) {
    i.message.contains("`error` is required")
  })
  // Only the second call, which really omits `error`.
  assert_eq(missing.length(), 1)
}

///|
test "logical or: a never-falsy left operand is the whole type" {
  let src =
    #|interface Eff { type: string }
    #|interface Def { effect: Eff; maybe: Eff | undefined }
    #|function f(d: Def): string {
    #|  const e = d.effect || null;
    #|  return e.type;
    #|}
    #|function g(d: Def): string {
    #|  const m = d.maybe || null;
    #|  return m.type;
    #|}
  let issues = generic_base_issues(src)
  assert_false(issues.iter().any(fn(i) { i.path.contains("function f") }))
  // A left operand that CAN be falsy still unions the right one in.
  assert_true(
    issues
    .iter()
    .any(fn(i) { i.path.contains("function g") && i.message.contains("null") }),
  )
}

///|
test "indexed access: a concrete key relates through the constraint" {
  // `T[number]` / `T["a"]` with a non-generic key are legal sinks for a
  // value the constraint indexed the same way accepts (zod's
  // `Set<T[number]>.has(s)`); a GENERIC key still admits nothing concrete.
  let src =
    #|function f1<T extends string[]>(s: string): T[number] { return s; }
    #|function f2<T extends [string, ...string[]]>(s: string): T[number] { return s; }
    #|function f3<T extends { a: string }>(s: string): T["a"] { return s; }
    #|function f7<T extends string[]>(s: Set<T[number]>, v: string): boolean { return s.has(v); }
    #|function g<T, P extends keyof T>(s: string): T[P] { return s; }
  let issues = generic_base_issues(src)
  for name in ["f1", "f2", "f3", "f7"] {
    assert_false(
      issues.iter().any(fn(i) { i.path.contains("function \{name} ") }),
    )
  }
  assert_true(
    issues
    .iter()
    .any(fn(i) {
      i.path.contains("function g ") &&
      i.message.contains("generic indexed access")
    }),
  )
}

///|
test "indexed access: an interface member by literal key resolves" {
  // `switch (k)` over `Def["type"]` judges each case against the member's
  // literal union: legal arms are silent and an impossible one reports.
  let src =
    #|interface Def { type: "a" | "b" | "c" }
    #|function h(k: Def["type"]): number {
    #|  switch (k) { case "a": return 1; case "b": return 2; }
    #|  return 0;
    #|}
    #|function bad(k: Def["type"]): number {
    #|  switch (k) { case "z": return 1; }
    #|  return 0;
    #|}
  let issues = generic_base_issues(src)
  assert_false(issues.iter().any(fn(i) { i.path.contains("function h") }))
  assert_true(
    issues
    .iter()
    .any(fn(i) {
      i.path.contains("function bad") && i.message.contains("can never match")
    }),
  )
}

///|
test "indexed access: an unresolvable base overlaps every case" {
  // zod casts to `$ZodTypeDef["type"]` with the interface imported from
  // another module; an indexed access nothing can reduce says nothing
  // about its values, so no arm may be called impossible.
  let src =
    #|function f(x: any): number {
    #|  const k = x.type as Missing["type"];
    #|  switch (k) { case "a": return 1; case "b": return 2; }
    #|  return 0;
    #|}
  let issues = generic_base_issues(src)
  assert_false(
    issues.iter().any(fn(i) { i.message.contains("can never match") }),
  )
}

///|
test "indexed access: a self-referential member terminates" {
  // `x: C1["x"]` hands the lookup back the same indexed access; this used
  // to loop forever (circularIndexedAccessErrors). Reaching the assertion
  // at all is the test.
  let src =
    #|type T1 = { x: T1["x"] };
    #|class C1 { x: C1["x"]; }
    #|function f(a: T1, c: C1): void { const p = a.x; const q = c.x; }
  let _ = generic_base_issues(src)
  assert_true(true)
}

///|
test "generic base member: a derived interface extending its instantiation" {
  // `_zod: LInternals` against `Internals<string>` where
  // `interface LInternals extends Internals<string>` — also through two
  // generic levels — is accepted; a derived member whose `check` takes the
  // wrong type through a NON-generic interface is still TS2430.
  let src =
    #|interface Internals<T> { issc?: Unresolved.Base; check(p: T): void; }
    #|interface Check<in T = never> { _zod: Internals<T> }
    #|interface LInternals extends Internals<string> { issc: Unresolved.Fmt }
    #|interface LCheck extends Check<string> { _zod: LInternals }
    #|interface MInternals<T> extends Internals<T> { issc: Unresolved.Fmt }
    #|interface MCheck<T> extends Check<T> { _zod: MInternals<T> }
  let issues = generic_base_issues(src)
  for name in ["LCheck", "MCheck"] {
    assert_false(
      issues
      .iter()
      .any(fn(i) {
        i.message.contains("interface `\{name}` incorrectly extends")
      }),
    )
  }
}

///|
test "lib alias: PropertyKey is string | number | symbol" {
  let src =
    #|function f(k: PropertyKey): void {}
    #|function g(key: string, n: number, s: symbol, b: boolean): void {
    #|  f(key); f(n); f(s); f(b);
    #|}
  let issues = generic_base_issues(src)
  let reports = issues.filter(fn(i) { i.message.contains("PropertyKey") })
  // Only `boolean` is outside the alias (TS2345 in tsc).
  assert_eq(reports.length(), 1)
  assert_true(reports[0].message.contains("boolean"))
}

///|
test "unique symbol: a fresh Symbol() call declares one, another symbol does not" {
  let src =
    #|declare const s: symbol;
    #|function f(): void {
    #|  const a: unique symbol = Symbol("a");
    #|  const b: unique symbol = Symbol.for("b");
    #|  const c: unique symbol = s;
    #|}
  let issues = generic_base_issues(src)
  let reports = issues.filter(fn(i) { i.message.contains("unique symbol") })
  assert_eq(reports.length(), 1)
  assert_true(reports[0].path.contains("`c`"))
}

///|
test "typeof narrowing: an alias to a union is split before stripping" {
  let src =
    #|type PK = string | number | symbol;
    #|declare function take(s: string): void;
    #|function a(seg: PK): void {
    #|  if (typeof seg === "number") take("n");
    #|  else if (typeof seg === "symbol") take("s");
    #|  else take(seg);
    #|}
    #|function c(seg: PK): void {
    #|  if (typeof seg === "number") take("n");
    #|  else take(seg);
    #|}
  let issues = generic_base_issues(src)
  assert_false(issues.iter().any(fn(i) { i.path.contains("function a") }))
  // `string | symbol` is left on the else side of `c` — a real TS2345.
  assert_true(
    issues
    .iter()
    .any(fn(i) {
      i.path.contains("function c") && i.message.contains("string | symbol")
    }),
  )
}

///|
test "interface extends: same generic interface, covariant arguments" {
  // preact's `role?: Signalish<'link' | undefined>` against
  // `Signalish<AriaRole | undefined>`; the wrong-argument spellings are
  // still TS2430 (probed).
  let src =
    #|interface SignalLike<T> { value: T; peek(): T; }
    #|type Signalish<T> = T | SignalLike<T>;
    #|type A1 = 'a' | 'b';
    #|type A2 = 'c' | 'd';
    #|type Role = A1 | A2;
    #|interface Base { role?: Signalish<Role | undefined>; }
    #|interface D1 extends Base { role?: Signalish<'a' | 'c' | undefined>; }
    #|interface D4 extends Base { role?: SignalLike<'a'>; }
    #|interface D5 extends Base { role?: SignalLike<number>; }
    #|interface D6 extends Base { role?: Signalish<'z' | undefined>; }
  let issues = generic_base_issues(src)
  let flagged = fn(n : String) {
    issues
    .iter()
    .any(fn(i) { i.message.contains("interface `\{n}` incorrectly extends") })
  }
  assert_false(flagged("D1"))
  assert_false(flagged("D4"))
  assert_true(flagged("D5"))
  assert_true(flagged("D6"))
}

///|
test "interface extends: array and tuple members are covariant" {
  // vitest's artifact interfaces.
  let src =
    #|interface Att { path?: string; }
    #|interface VAtt extends Att { name: "a" | "b"; }
    #|interface Base { attachments?: Att[]; }
    #|interface V extends Base { attachments: VAtt[]; }
    #|interface F extends Base { attachments: [VAtt] | []; }
    #|interface W extends Base { attachments: number[]; }
    #|interface X extends Base { attachments: [number] | []; }
  let issues = generic_base_issues(src)
  let flagged = fn(n : String) {
    issues
    .iter()
    .any(fn(i) { i.message.contains("interface `\{n}` incorrectly extends") })
  }
  assert_false(flagged("V"))
  assert_false(flagged("F"))
  assert_true(flagged("W"))
  assert_true(flagged("X"))
}

///|
test "abstract: a pattern parameter is not an implementation" {
  // The destructuring prologue the parser synthesizes for `({ a })` gave
  // the bodiless member a `body`; only a real `{ … }` is TS1245.
  let ok = generic_base_issues(
    "abstract class A { abstract m({ a }: { a: number }): void; abstract o([p]: number[]): void; }",
  )
  assert_false(ok.iter().any(fn(i) { i.message.contains("implementation") }))
  let bad = generic_base_issues("abstract class B { abstract m(): void {} }")
  assert_true(bad.iter().any(fn(i) { i.message.contains("implementation") }))
}

///|
test "TS2842: an unused renaming is legal in a declaration file" {
  let src = "declare class K { m({ a: b }: { a: number }): void; }"
  let in_ts = generic_base_issues(src)
  assert_true(in_ts.iter().any(fn(i) { i.message.contains("unused renaming") }))
  let in_dts = check_module_function_bodies(
    parse_declaration_module_or_empty(src),
  )
  assert_false(
    in_dts.iter().any(fn(i) { i.message.contains("unused renaming") }),
  )
}
