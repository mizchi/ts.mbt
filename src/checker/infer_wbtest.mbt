///|
fn infer_marker(name : String) -> @ast.TsType {
  Applied("__tsmbt_infer", [Named(name)])
}

///|
test "match_infer_pattern: identical types match without bindings" {
  let bindings : Map[String, @ast.TsType] = {}
  assert_true(match_infer_pattern(String_, String_, bindings))
  @test.assert_eq(bindings.length(), 0)
}

///|
test "match_infer_pattern: bare infer captures source" {
  let bindings : Map[String, @ast.TsType] = {}
  assert_true(match_infer_pattern(String_, infer_marker("U"), bindings))
  @test.assert_eq(bindings.get("U"), Some(String_))
}

///|
test "match_infer_pattern: Promise<infer U> binds U to inner" {
  let bindings : Map[String, @ast.TsType] = {}
  let pattern : @ast.TsType = Applied("Promise", [infer_marker("U")])
  let source : @ast.TsType = Applied("Promise", [String_])
  assert_true(match_infer_pattern(source, pattern, bindings))
  @test.assert_eq(bindings.get("U"), Some(String_))
}

///|
test "match_infer_pattern: array element infer" {
  let bindings : Map[String, @ast.TsType] = {}
  let pattern : @ast.TsType = Array(infer_marker("E"))
  let source : @ast.TsType = Array(Number)
  assert_true(match_infer_pattern(source, pattern, bindings))
  @test.assert_eq(bindings.get("E"), Some(Number))
}

///|
test "match_infer_pattern: function param/return infer" {
  let bindings : Map[String, @ast.TsType] = {}
  // (arg: infer A) => infer R  vs  (arg: string) => number
  let pattern : @ast.TsType = Func([infer_marker("A")], infer_marker("R"))
  let source : @ast.TsType = Func([String_], Number)
  assert_true(match_infer_pattern(source, pattern, bindings))
  @test.assert_eq(bindings.get("A"), Some(String_))
  @test.assert_eq(bindings.get("R"), Some(Number))
}

///|
test "match_infer_pattern: structural mismatch fails" {
  let bindings : Map[String, @ast.TsType] = {}
  let pattern : @ast.TsType = Applied("Promise", [infer_marker("U")])
  let source : @ast.TsType = Array(String_)
  assert_false(match_infer_pattern(source, pattern, bindings))
}

///|
test "match_infer_pattern: conflicting binding fails" {
  let bindings : Map[String, @ast.TsType] = {}
  // [infer X, infer X] vs [string, number] — second binding conflicts.
  let pattern : @ast.TsType = Tuple([infer_marker("X"), infer_marker("X")])
  let source : @ast.TsType = Tuple([String_, Number])
  assert_false(match_infer_pattern(source, pattern, bindings))
}

///|
fn infer_marker_with_bound(name : String, bound : @ast.TsType) -> @ast.TsType {
  Applied("__tsmbt_infer", [Named(name), bound])
}

///|
test "match_infer_pattern: `infer X extends Bound` rejects disjoint source" {
  // Pattern `infer T extends string` against source `number`: the
  // bound is definitively violated, so the conditional should pick its
  // false branch.
  let bindings : Map[String, @ast.TsType] = {}
  assert_false(
    match_infer_pattern(Number, infer_marker_with_bound("T", String_), bindings),
  )
  @test.assert_eq(bindings.length(), 0)
}

///|
test "match_infer_pattern: `infer X extends Bound` accepts matching source" {
  // Source `"a"` extends `string` — bind succeeds.
  let bindings : Map[String, @ast.TsType] = {}
  assert_true(
    match_infer_pattern(
      Literal("a"),
      infer_marker_with_bound("T", String_),
      bindings,
    ),
  )
  @test.assert_eq(bindings.get("T"), Some(Literal("a")))
}

///|
test "match_infer_pattern: variadic Parameters<F> captures rest-tail tuple" {
  // Source: `(a: string, ...rest: number[]) => void` lowered as
  // `Func([String, Rest(Array(Number))], Void)`. The Parameters<F>
  // pattern is `Func([Array(infer P)], Any)`. P should bind to
  // `Tuple([String, Rest(Array(Number))])`.
  let bindings : Map[String, @ast.TsType] = {}
  let source : @ast.TsType = Func([String_, Rest(Array(Number))], Void)
  let pattern : @ast.TsType = Func([Array(infer_marker("P"))], Any)
  assert_true(match_infer_pattern(source, pattern, bindings))
  @test.assert_eq(
    bindings.get("P"),
    Some(Tuple([String_, Rest(Array(Number))])),
  )
}

///|
test "match_infer_pattern: `infer X extends Bound` allows undecidable source" {
  // Source is an opaque `Named("Foo")`; bound is `Date`. The relation
  // is undecidable, so we optimistically bind — the substitution path
  // can retry once `Foo` is resolved.
  let bindings : Map[String, @ast.TsType] = {}
  assert_true(
    match_infer_pattern(
      Named("Foo"),
      infer_marker_with_bound("T", Named("Date")),
      bindings,
    ),
  )
  @test.assert_eq(bindings.get("T"), Some(Named("Foo")))
}

///|
test "match_infer_pattern: union pattern picks the matching branch" {
  let bindings : Map[String, @ast.TsType] = {}
  // Promise<infer U> | Array<infer U>  vs  Promise<string>
  let pattern : @ast.TsType = Union([
    Applied("Promise", [infer_marker("U")]),
    Applied("Array", [infer_marker("U")]),
  ])
  let source : @ast.TsType = Applied("Promise", [String_])
  assert_true(match_infer_pattern(source, pattern, bindings))
  @test.assert_eq(bindings.get("U"), Some(String_))
}

///|
test "substitute_inferred_type: replaces Named with binding" {
  let bindings : Map[String, @ast.TsType] = { "U": Number }
  let body : @ast.TsType = Array(Named("U"))
  let result = substitute_inferred_type(body, bindings)
  @test.assert_eq(result, Array(Number))
}

///|
test "match_infer_pattern: rest pattern (...args: any[]) accepts any arity" {
  let bindings : Map[String, @ast.TsType] = {}
  let pattern : @ast.TsType = Func([Array(Any)], infer_marker("R"))
  let source : @ast.TsType = Func([String_, Number, Boolean], Named("Date"))
  assert_true(match_infer_pattern(source, pattern, bindings))
  @test.assert_eq(bindings.get("R"), Some(Named("Date")))
}

///|
test "match_infer_pattern: rest pattern captures params as Tuple" {
  let bindings : Map[String, @ast.TsType] = {}
  // (...args: infer P) => any  vs  (x: string, y: number) => void
  let pattern : @ast.TsType = Func([Array(infer_marker("P"))], Any)
  let source : @ast.TsType = Func([String_, Number], Void)
  assert_true(match_infer_pattern(source, pattern, bindings))
  @test.assert_eq(bindings.get("P"), Some(Tuple([String_, Number])))
}

///|
test "match_infer_pattern: rest pattern with no source params still matches" {
  let bindings : Map[String, @ast.TsType] = {}
  let pattern : @ast.TsType = Func([Array(Any)], infer_marker("R"))
  let source : @ast.TsType = Func([], String_)
  assert_true(match_infer_pattern(source, pattern, bindings))
  @test.assert_eq(bindings.get("R"), Some(String_))
}

///|
test "match_infer_pattern: object pattern { value: infer V }" {
  let bindings : Map[String, @ast.TsType] = {}
  let pattern : @ast.TsType = Object([(Literal("value"), infer_marker("V"))])
  let source : @ast.TsType = Object([
    (Literal("value"), Number),
    (Literal("extra"), String_),
  ])
  assert_true(match_infer_pattern(source, pattern, bindings))
  @test.assert_eq(bindings.get("V"), Some(Number))
}

///|
test "match_infer_pattern: object pattern requires every field to match" {
  let bindings : Map[String, @ast.TsType] = {}
  let pattern : @ast.TsType = Object([
    (Literal("value"), infer_marker("V")),
    (Literal("kind"), Literal("ok")),
  ])
  let source : @ast.TsType = Object([
    (Literal("value"), Number),
    (Literal("kind"), Literal("ok")),
  ])
  assert_true(match_infer_pattern(source, pattern, bindings))
  @test.assert_eq(bindings.get("V"), Some(Number))
}

///|
test "match_infer_pattern: object pattern fails on missing field" {
  let bindings : Map[String, @ast.TsType] = {}
  let pattern : @ast.TsType = Object([
    (Literal("value"), infer_marker("V")),
    (Literal("missing"), String_),
  ])
  let source : @ast.TsType = Object([(Literal("value"), Number)])
  assert_false(match_infer_pattern(source, pattern, bindings))
}

///|
test "match_infer_pattern: intersection pattern matches against intersection" {
  let bindings : Map[String, @ast.TsType] = {}
  // Pattern: A & B<infer X>;  Source: A & B<string>
  let pattern : @ast.TsType = Intersection([
    Named("A"),
    Applied("B", [infer_marker("X")]),
  ])
  let source : @ast.TsType = Intersection([Named("A"), Applied("B", [String_])])
  assert_true(match_infer_pattern(source, pattern, bindings))
  @test.assert_eq(bindings.get("X"), Some(String_))
}

///|
test "substitute_inferred_type: leaves non-bound names alone" {
  let bindings : Map[String, @ast.TsType] = { "U": Number }
  let body : @ast.TsType = Named("V")
  let result = substitute_inferred_type(body, bindings)
  @test.assert_eq(result, Named("V"))
}
