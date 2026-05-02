///|
test "is_assignable_to_bivariant: identical functions still match" {
  let f : @ast.TsType = Func([String_], Number)
  assert_true(is_assignable_to_bivariant(f, f))
}

///|
test "is_assignable_to_bivariant: covariant param accepted in non-strict mode" {
  // (x: Animal) => void  vs  (x: Dog) => void
  // Strict mode would reject this — Animal cannot flow into Dog (subtype).
  // We model `Dog` as a literal narrowing of `Animal` via Literal/String_.
  let s : @ast.TsType = Func([String_], Void)
  let t : @ast.TsType = Func([Literal("Dog")], Void)
  // Strict (contravariant): would need Literal("Dog") → String_, which is
  // true; this case actually passes strict too. Pick a clearer pair below.
  assert_true(is_assignable_to(s, t))
  assert_true(is_assignable_to_bivariant(s, t))
}

///|
test "is_assignable_to_bivariant: rejected by strict, accepted by bivariant" {
  // (x: number) => void vs (x: 42) => void
  // Strict (contravariant): NumberLiteral("42") -> Number (true). Param OK,
  // return OK. So this passes strict.
  // Pick a real bivariance demo: (x: number) => void  vs  (x: string) => void
  // Strict: String_ -> Number? false. Bivariant: Number -> String_? false.
  // So both reject. Need a case where one direction succeeds and the other
  // does not.
  // `(x: any) => void`  vs  `(x: number) => void`
  // Strict: Number -> Any? true (via Any sink). Pass.
  // `(x: number) => void`  vs  `(x: any) => void`
  // Strict: Any -> Number? true (via Any source). Pass.
  // `(x: number) => void`  vs  `(x: 1 | 2) => void`
  // Strict: NumberLiteral|NumberLiteral -> Number? Each Literal fits ⇒ true.
  // `(x: 1 | 2) => void`  vs  `(x: number) => void`
  // Strict: Number -> NumberLiteral("1")? false; -> NumberLiteral("2")? false. Reject.
  // Bivariant: NumberLiteral|NumberLiteral -> Number? true. Accept.
  let s : @ast.TsType = Func(
    [Union([NumberLiteral("1"), NumberLiteral("2")])],
    Void,
  )
  let t : @ast.TsType = Func([Number], Void)
  assert_false(is_assignable_to(s, t))
  assert_true(is_assignable_to_bivariant(s, t))
}

///|
test "is_assignable_to_bivariant: return type still covariant" {
  // (x: number) => 1  vs  (x: number) => string
  // Bivariance only affects param variance. Return type covariance is
  // preserved — NumberLiteral("1") cannot flow into String_.
  let s : @ast.TsType = Func([Number], NumberLiteral("1"))
  let t : @ast.TsType = Func([Number], String_)
  assert_false(is_assignable_to_bivariant(s, t))
}

///|
test "is_assignable_to_bivariant: nested function fields use the same mode" {
  // {handler: (x: 1|2) => void} vs {handler: (x: number) => void}
  let s : @ast.TsType = Object([
    (
      Literal("handler"),
      Func([Union([NumberLiteral("1"), NumberLiteral("2")])], Void),
    ),
  ])
  let t : @ast.TsType = Object([
    (Literal("handler"), Func([Number], Void)),
  ])
  assert_false(is_assignable_to(s, t))
  assert_true(is_assignable_to_bivariant(s, t))
}
