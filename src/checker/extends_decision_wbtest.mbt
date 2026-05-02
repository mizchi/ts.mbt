///|
test "extends_decision: identity is true" {
  assert_eq(extends_decision(String_, String_), Some(true))
  assert_eq(extends_decision(Number, Number), Some(true))
}

///|
test "extends_decision: any target accepts anything as true" {
  assert_eq(extends_decision(String_, Any), Some(true))
  assert_eq(extends_decision(Never, Any), Some(true))
}

///|
test "extends_decision: never source extends anything" {
  assert_eq(extends_decision(Never, String_), Some(true))
  assert_eq(extends_decision(Never, Number), Some(true))
}

///|
test "extends_decision: int extends number" {
  assert_eq(extends_decision(Int, Number), Some(true))
}

///|
test "extends_decision: distinct primitives report false definitively" {
  assert_eq(extends_decision(String_, Number), Some(false))
  assert_eq(extends_decision(Boolean, String_), Some(false))
}

///|
test "extends_decision: unknown for non-primitive nominal types without info" {
  assert_eq(extends_decision(Named("Foo"), Named("Bar")), None)
  assert_eq(extends_decision(Applied("Box", [String_]), Named("Foo")), None)
}

///|
test "extends_decision: target union — short-circuit on a confirmed match" {
  assert_eq(
    extends_decision(String_, Union([String_, Number])),
    Some(true),
  )
}

///|
test "extends_decision: target union — all branches definitely false" {
  assert_eq(
    extends_decision(Boolean, Union([String_, Number])),
    Some(false),
  )
}

///|
test "extends_decision: target union — propagates unknown" {
  // Boolean vs Named("Foo") is unknown ⇒ overall is unknown.
  assert_eq(
    extends_decision(Boolean, Union([String_, Named("Foo")])),
    None,
  )
}

///|
test "extends_decision: source union — every branch must extend" {
  assert_eq(
    extends_decision(Union([Literal("a"), Literal("b")]), String_),
    Some(true),
  )
  assert_eq(
    extends_decision(Union([String_, Number]), String_),
    Some(false),
  )
}

///|
test "extends_decision: source union — propagates unknown" {
  assert_eq(
    extends_decision(Union([String_, Named("Foo")]), String_),
    None,
  )
}
