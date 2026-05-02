// Smoke tests that exercise the `mizchi/ts/checker` API on real parsed
// fixtures. These run after the parser, so any false positive here would
// reflect a real gap in the checker's resolution logic.

///|
test "checker: bridge_smoke double-entry has no unresolved type references" {
  let src = "export declare function double(input: number): number;"
  let module_ = @parser.parse_module_from_source_with_const_values(src, {}) catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  let unresolved = @checker.unresolved_type_references(module_)
  if unresolved.length() != 0 {
    fail("Unexpected unresolved references: \{unresolved}")
  }
}

///|
test "checker: enum decl shadows references to its own name" {
  let src =
    #|export declare enum Mode {
    #|  Read = "read",
    #|  Write = "write",
    #|}
    #|export declare function recordMode(mode: Mode): string;
    #|export declare function nextMode(mode: Mode): Mode;
  let module_ = @parser.parse_module_from_source_with_const_values(src, {}) catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  let unresolved = @checker.unresolved_type_references(module_)
  if unresolved.length() != 0 {
    fail("Unexpected unresolved references: \{unresolved}")
  }
}

///|
test "checker: detects truly missing type references" {
  let src =
    #|export declare function take(box: Inner): void;
  let module_ = @parser.parse_module_from_source_with_const_values(src, {}) catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  let unresolved = @checker.unresolved_type_references(module_)
  // Either Inner is reported, or the parser preemptively widens it to
  // something well-known. Whichever happens, the test surfaces it.
  if unresolved.length() != 1 {
    fail("Expected exactly one unresolved name, got: \{unresolved}")
  }
  if unresolved[0] != "Inner" {
    fail("Expected unresolved name to be Inner, got: \{unresolved[0]}")
  }
}

///|
test "checker: nested generic params in interfaces are recognised in scope" {
  let src =
    #|export interface Box<T> {
    #|  value: T;
    #|  inner: Wrap<T>;
    #|}
    #|export interface Wrap<U> {
    #|  raw: U;
    #|}
  let module_ = @parser.parse_module_from_source_with_const_values(src, {}) catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  let unresolved = @checker.unresolved_type_references(module_)
  if unresolved.length() != 0 {
    fail("Unexpected unresolved references: \{unresolved}")
  }
}

///|
test "checker: ambient class declarations satisfy unresolved-reference check" {
  let src =
    #|export declare class CounterState {
    #|  readonly current: number;
    #|  label: string;
    #|  static readonly version: string;
    #|  static step: number;
    #|}
    #|export declare function bump(state: CounterState): CounterState;
  let module_ = @parser.parse_module_from_source_with_const_values(src, {}) catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  let unresolved = @checker.unresolved_type_references(module_)
  if unresolved.length() != 0 {
    fail("Unexpected unresolved references: \{unresolved}")
  }
}

///|
test "checker: type alias chains parse cleanly" {
  let src =
    #|export type FeatureFlag = true | false;
    #|export type AlwaysOn = true | undefined;
    #|export declare function flipFlag(flag: FeatureFlag): FeatureFlag;
  let module_ = @parser.parse_module_from_source_with_const_values(src, {}) catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  let unresolved = @checker.unresolved_type_references(module_)
  if unresolved.length() != 0 {
    fail("Unexpected unresolved references: \{unresolved}")
  }
}

///|
test "checker: generic substitution works on parser-produced bindings" {
  // Parse `type Maybe<X> = X | undefined;` then verify a generic application
  // through is_assignable_to_with_generics.
  let src = "export type Maybe<X> = X | undefined;"
  let module_ = @parser.parse_module_from_source_with_const_values(src, {}) catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  let table : Map[String, @checker.AliasBinding] = {}
  for ta in module_.type_aliases {
    table[ta.name] = { type_params: ta.type_params, body: ta.type_ }
  }
  let resolve = fn(name) { table.get(name) }
  // string flows into Maybe<string>
  if !@checker.is_assignable_to_with_generics(
      String_,
      Applied("Maybe", [String_]),
      resolve,
    ) {
    fail("string should be assignable to Maybe<string>")
  }
  // number does NOT flow into Maybe<string>
  if @checker.is_assignable_to_with_generics(
      Number,
      Applied("Maybe", [String_]),
      resolve,
    ) {
    fail("number should not be assignable to Maybe<string>")
  }
  // Maybe<string> accepts undefined
  if !@checker.is_assignable_to_with_generics(
      Undefined,
      Applied("Maybe", [String_]),
      resolve,
    ) {
    fail("undefined should be assignable to Maybe<string>")
  }
}

///|
test "checker: check_module on parsed fixtures stays clean" {
  // Collect a few real fixture-shaped declarations and assert they pass every
  // check_module diagnostic. If a future synthesis change introduces e.g.
  // duplicate fields or alias arity mismatches, this regression test surfaces it.
  let cases : Array[String] = [
    "export declare function double(input: number): number;",
    #|export declare enum Mode {
    #|  Read = "read",
    #|  Write = "write",
    #|}
    #|export declare function next(m: Mode): Mode;
    ,
    #|export type ID = string;
    #|export type UserId = ID;
    #|export interface User { id: UserId; name: string; }
    #|export declare function getUser(id: UserId): User;
    ,
    // NOTE: declare-function generic params are not preserved on TsFunc in
    // the current AST, so we keep the smoke test to interfaces with their
    // own type params (which TsInterface does carry).
    "export interface Box<T> { value: T; }",
  ]
  for src in cases {
    let module_ = @parser.parse_module_from_source_with_const_values(src, {}) catch {
      e => {
        fail("Parse error on src: \{e}")
        return
      }
    }
    let report = @checker.check_module(module_)
    if report.issues.length() != 0 {
      let names = report.issues.map(fn(i) { i.name })
      fail(
        "check_module surfaced unexpected issues for fixture: \{names}",
      )
    }
  }
}

///|
test "checker: standard utility types resolve through real-parsed input" {
  // Parse a function that uses a standard utility type as its return.
  // Then build a resolver that combines parsed aliases with the bundled
  // standard library and verify the checker resolves correctly.
  let src =
    #|export type Maybe<X> = X | undefined;
    #|export declare function unwrap<T>(value: T | null | undefined): T;
  let module_ = @parser.parse_module_from_source_with_const_values(src, {}) catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  let table = @checker.standard_utility_types()
  for ta in module_.type_aliases {
    table[ta.name] = { type_params: ta.type_params, body: ta.type_ }
  }
  let resolve = fn(name) { table.get(name) }
  // NonNullable<string | null> ⇨ string
  let nn : @ast.TsType = Applied("NonNullable", [Union([String_, Null])])
  if !@checker.is_assignable_to_with_generics(String_, nn, resolve) {
    fail("string should be assignable to NonNullable<string | null>")
  }
  if @checker.is_assignable_to_with_generics(Null, nn, resolve) {
    fail("null should not be assignable to NonNullable<string | null>")
  }
  // Exclude<"a" | "b", "a"> ⇨ "b"
  let ex : @ast.TsType = Applied("Exclude", [
    Union([Literal("a"), Literal("b")]),
    Literal("a"),
  ])
  if !@checker.is_assignable_to_with_generics(Literal("b"), ex, resolve) {
    fail("\"b\" should remain after Exclude")
  }
  if @checker.is_assignable_to_with_generics(Literal("a"), ex, resolve) {
    fail("\"a\" should be excluded")
  }
}

///|
test "checker: simplify_union flattens redundant alias substitution result" {
  // type Pair<T> = T | string;
  // const x : Pair<string> = "hello"
  // After substitution Pair<string> ⇒ string | string ⇒ should collapse.
  let after_substitution : Array[@ast.TsType] = [String_, String_, Number]
  let simplified = @checker.simplify_union(after_substitution)
  assert_eq(simplified.length(), 2)
  assert_true(simplified.contains(String_))
  assert_true(simplified.contains(Number))
}

///|
test "checker: assignability roundtrips on parsed type aliases" {
  // Parse a couple of aliases, build a resolver from them, and check
  // assignability across the chain.
  let src =
    #|export type ID = string;
    #|export type UserId = ID;
  let module_ = @parser.parse_module_from_source_with_const_values(src, {}) catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  let table : Map[String, @ast.TsType] = {}
  for ta in module_.type_aliases {
    table[ta.name] = ta.type_
  }
  let resolve = fn(name) { table.get(name) }
  // UserId should be assignable to string after resolver expansion.
  if !@checker.is_assignable_to_with(Named("UserId"), String_, resolve) {
    fail("UserId should resolve to string")
  }
  if @checker.is_assignable_to_with(Named("UserId"), Number, resolve) {
    fail("UserId is string, not number")
  }
}
