///|
fn standard_resolver() -> (String) -> AliasBinding? {
  let table = standard_utility_types()
  fn(name) { table.get(name) }
}

///|
test "standard_utility_types: Exclude removes matching union members" {
  let resolve = standard_resolver()
  // Exclude<"a" | "b" | "c", "a"> ⇨ "b" | "c"
  let target : @ast.TsType = Applied("Exclude", [
    Union([Literal("a"), Literal("b"), Literal("c")]),
    Literal("a"),
  ])
  // "b" should be assignable to the result.
  assert_true(is_assignable_to_with_generics(Literal("b"), target, resolve))
  assert_true(is_assignable_to_with_generics(Literal("c"), target, resolve))
  // "a" should NOT be assignable.
  assert_false(is_assignable_to_with_generics(Literal("a"), target, resolve))
}

///|
test "standard_utility_types: Extract picks matching union members" {
  let resolve = standard_resolver()
  // Extract<"a" | "b" | "c", "a" | "b"> ⇨ "a" | "b"
  let target : @ast.TsType = Applied("Extract", [
    Union([Literal("a"), Literal("b"), Literal("c")]),
    Union([Literal("a"), Literal("b")]),
  ])
  assert_true(is_assignable_to_with_generics(Literal("a"), target, resolve))
  assert_true(is_assignable_to_with_generics(Literal("b"), target, resolve))
  assert_false(is_assignable_to_with_generics(Literal("c"), target, resolve))
}

///|
test "standard_utility_types: NonNullable strips null and undefined" {
  let resolve = standard_resolver()
  // NonNullable<string | null | undefined> ⇨ string
  let target : @ast.TsType = Applied("NonNullable", [
    Union([String_, Null, Undefined]),
  ])
  assert_true(is_assignable_to_with_generics(String_, target, resolve))
  assert_false(is_assignable_to_with_generics(Null, target, resolve))
  assert_false(is_assignable_to_with_generics(Undefined, target, resolve))
}

///|
test "standard_utility_types: ReturnType extracts function return" {
  let resolve = standard_resolver()
  // ReturnType<(x: string) => number> ⇨ number
  let target : @ast.TsType = Applied("ReturnType", [Func([String_], Number)])
  assert_true(is_assignable_to_with_generics(Number, target, resolve))
  assert_false(is_assignable_to_with_generics(String_, target, resolve))
}

///|
test "standard_utility_types: ReturnType handles zero-param functions" {
  let resolve = standard_resolver()
  let target : @ast.TsType = Applied("ReturnType", [Func([], String_)])
  assert_true(is_assignable_to_with_generics(String_, target, resolve))
}

///|
test "standard_utility_types: Parameters captures the param tuple" {
  let resolve = standard_resolver()
  // Parameters<(x: string, y: number) => void> ⇨ [string, number]
  let target : @ast.TsType = Applied("Parameters", [
    Func([String_, Number], Void),
  ])
  assert_true(
    is_assignable_to_with_generics(Tuple([String_, Number]), target, resolve),
  )
  assert_false(
    is_assignable_to_with_generics(Tuple([Number, String_]), target, resolve),
  )
}

///|
test "standard_utility_types: Awaited unwraps Promise once" {
  let resolve = standard_resolver()
  // Awaited<Promise<string>> ⇨ string
  let target : @ast.TsType = Applied("Awaited", [Applied("Promise", [String_])])
  assert_true(is_assignable_to_with_generics(String_, target, resolve))
  assert_false(is_assignable_to_with_generics(Number, target, resolve))
}

///|
test "standard_utility_types: Awaited passes non-promise through" {
  let resolve = standard_resolver()
  // Awaited<string> ⇨ string  (TS spec: identity when not thenable)
  let target : @ast.TsType = Applied("Awaited", [String_])
  assert_true(is_assignable_to_with_generics(String_, target, resolve))
}
