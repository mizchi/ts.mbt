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
