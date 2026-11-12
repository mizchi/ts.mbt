// Lib member arity, optional-chain narrowing and the `if` join. Every
// "silent" case is ACCEPTED by tsc and every "reports" case is an error
// there; each was probed against the real compiler.

///|
fn lf_issues(src : String) -> Array[ExprIssue] {
  check_module_function_bodies(parse_module_or_empty(src))
}

///|
fn lf_has(issues : Array[ExprIssue], fname : String) -> Bool {
  issues.iter().any(fn(i) { i.path.contains("function \{fname} ") })
}

///|
test "lib members: optional parameters are optional" {
  let src =
    #|function ok(n: number, d: Date, s: string, a: number[]): unknown[] {
    #|  return [n.toFixed(), n.toString(16), n.toLocaleString("en"), d.toLocaleDateString("en", {}),
    #|    s.slice(), s.slice(1), s.substring(1), s.split(",", 2), s.padStart(2), s.normalize(),
    #|    s.startsWith("a", 1), s.localeCompare("x", "en"), s.replace("a", (m) => m),
    #|    a.reduce((p, c) => p + c), JSON.stringify(a, null, 2), Promise.resolve()];
    #|}
    #|function bad1(n: number): string { return n.toFixed("x"); }
    #|function bad2(s: string): string { return s.charAt(); }
    #|function bad3(n: number): string { return n.toFixed(1, 2); }
    #|function bad4(s: string): string { return s.padStart(); }
  let issues = lf_issues(src)
  assert_false(lf_has(issues, "ok"))
  for f in ["bad1", "bad2", "bad3", "bad4"] {
    assert_true(lf_has(issues, f))
  }
}

///|
test "optional chain: a truthy or non-undefined chain narrows its receiver" {
  let src =
    #|interface P { a?: string; b: number; }
    #|function t1(p?: P): unknown { return p?.a && p.a.length; }
    #|function t2(p?: P): void { if (p?.a) { p.b.toFixed(); } }
    #|function t3(p?: P): void { if (p?.a !== undefined) { p.b.toFixed(); } }
    #|function t4(p?: P): void { if (p?.a != null) { p.b.toFixed(); } }
    #|function t5(p?: P): void { if (p?.b === 1) { p.b.toFixed(); } }
    #|function r1(p?: P): unknown { return p?.a || p.b; }
    #|function r2(p?: P): void { if (!p?.a) { p.b.toFixed(); } }
    #|function r3(p?: P): void { if (p?.a !== null) { p.b.toFixed(); } }
    #|function r4(p?: P): void { if (p?.a == null) { p.b.toFixed(); } }
  let issues = lf_issues(src)
  for f in ["t1", "t2", "t3", "t4", "t5"] {
    assert_false(lf_has(issues, f))
  }
  for f in ["r1", "r2", "r3", "r4"] {
    assert_true(lf_has(issues, f))
  }
}

///|
test "if join: a narrowing does not leak past an if with no else" {
  let src =
    #|interface P { b: number; }
    #|function g1(p?: P): number { if (p) { p.b; } return p.b; }
    #|function g2(p?: P): number { if (p) { } return p.b; }
    #|function g3(p?: P): number { if (!p) { return 0; } return p.b; }
  let issues = lf_issues(src)
  assert_true(lf_has(issues, "g1"))
  assert_true(lf_has(issues, "g2"))
  assert_false(lf_has(issues, "g3"))
}

///|
test "assignment narrowing: the block spelling and an untyped new" {
  // zod's `bucketFor`: `let b = m.get(k); if (!b) { b = new WeakMap(); }`.
  let src =
    #|interface Entry { v: number }
    #|declare const m: Map<string, WeakMap<object, Entry>>;
    #|function c1(k: string): WeakMap<object, Entry> { let b = m.get(k); if (!b) { b = new WeakMap(); m.set(k, b); } return b; }
    #|function c2(k: string): WeakMap<object, Entry> { let b = m.get(k); b = new WeakMap<object, Entry>(); return b; }
    #|function c3(): Entry { let b: Entry | undefined; if (!b) { b = { v: 1 }; } return b; }
    #|function c4(k: string): WeakMap<object, Entry> { let b = m.get(k); if (k) { b = new WeakMap(); } return b; }
  let issues = lf_issues(src)
  for f in ["c1", "c2", "c3"] {
    assert_false(lf_has(issues, f))
  }
  // Assigned on only one path: still possibly `undefined` after the join.
  assert_true(lf_has(issues, "c4"))
}

///|
test "unique symbol: a /*@__PURE__*/-annotated Symbol() declares one" {
  let src =
    #|declare const s: symbol;
    #|function f(): void {
    #|  const a: unique symbol = /*@__PURE__*/ Symbol("a");
    #|  const c: unique symbol = /*@__PURE__*/ (s);
    #|}
  let issues = lf_issues(src).filter(fn(i) {
    i.message.contains("unique symbol")
  })
  assert_eq(issues.length(), 1)
  assert_true(issues[0].path.contains("`c`"))
}

///|
test "overloads: a parameter typed with an object-type alias still selects" {
  // zod's `generateCheck`: the 4-argument call is the first overload's
  // `string`, not the union of every overload's return.
  let src =
    #|type S = { k: string };
    #|function g(schema: S, a: string): string;
    #|function g(schema: S, a: string, b: boolean): string | null;
    #|function g(schema: S, a: string, b = true): string | null { return b ? a : null; }
    #|function ok(schema: S, a: string): string { return g(schema, a); }
    #|function bad(schema: S, a: string): string { return g(schema, a, false); }
  let issues = lf_issues(src)
  assert_false(lf_has(issues, "ok"))
  assert_true(lf_has(issues, "bad"))
}

///|
test "distributive conditional over an alias-to-union argument" {
  // `Exclude<Formats, "regex">` must remove ONE member. Substituting the
  // alias first made the false branch the whole `Formats`, so it answered
  // for every member whatever it decided.
  let src =
    #|type Formats = "email" | "regex" | "url";
    #|type E2 = Exclude<Formats, "regex">;
    #|type X2 = Extract<Formats, "regex" | "nope">;
    #|declare const e2: E2;
    #|declare const x2: X2;
    #|function ok(): unknown { const a: "email" | "url" = e2; const b: "regex" = x2; return [a, b]; }
    #|function bad(): unknown { const c: "regex" = e2; return c; }
  let issues = lf_issues(src)
  assert_false(lf_has(issues, "ok"))
  assert_true(lf_has(issues, "bad"))
}

///|
test "discriminant narrowing with a union-of-literals member" {
  // zod's `$ZodIssueStringCommonFormats` declares its tag as
  // `Exclude<Formats, …>`; a variant whose tag is a UNION survives a
  // branch when some member of it could take that branch.
  let src =
    #|type Formats = "email" | "regex" | "starts_with" | "ends_with";
    #|interface Base { readonly format: Formats | (string & {}); }
    #|interface Common extends Base { format: Exclude<Formats, "regex" | "starts_with" | "ends_with"> }
    #|interface Multi extends Base { format: "regex" | "url"; pattern: string }
    #|interface SW extends Base { format: "starts_with"; prefix: string }
    #|interface EW extends Base { format: "ends_with"; suffix: string }
    #|type Issues = Common | SW | EW | Multi;
    #|function ok(i: Issues): string {
    #|  if (i.format === "starts_with") return i.prefix;
    #|  if (i.format === "regex") return i.pattern;
    #|  return "";
    #|}
    #|function bad(i: Issues): string {
    #|  if (i.format === "email") return i.prefix;
    #|  return "";
    #|}
  let issues = lf_issues(src)
  assert_false(lf_has(issues, "ok"))
  assert_true(lf_has(issues, "bad"))
}
