///|
test "equivalent: identical types are equivalent" {
  assert_true(equivalent(String_, String_))
  assert_true(equivalent(Union([String_, Number]), Union([String_, Number])))
}

///|
test "equivalent: order-insensitive on unions and intersections" {
  assert_true(equivalent(Union([String_, Number]), Union([Number, String_])))
  assert_true(
    equivalent(
      Intersection([Named("A"), Named("B")]),
      Intersection([Named("B"), Named("A")]),
    ),
  )
}

///|
test "equivalent: distinguishes literals from primitives" {
  assert_false(equivalent(Literal("foo"), String_))
  assert_false(equivalent(NumberLiteral("1"), Number))
}

///|
test "simplify_union: removes duplicate members" {
  let raw : Array[@ast.TsType] = [String_, String_, Number]
  let simplified = simplify_union(raw)
  assert_eq(simplified.length(), 2)
  assert_true(simplified.contains(String_))
  assert_true(simplified.contains(Number))
}

///|
test "simplify_union: removes literals subsumed by their primitive companion" {
  let raw : Array[@ast.TsType] = [String_, Literal("foo"), Literal("bar")]
  let simplified = simplify_union(raw)
  assert_eq(simplified.length(), 1)
  assert_true(simplified.contains(String_))
}

///|
test "simplify_union: keeps disjoint members" {
  let raw : Array[@ast.TsType] = [Literal("foo"), Number]
  let simplified = simplify_union(raw)
  assert_eq(simplified.length(), 2)
}

///|
test "simplify_union: collapses any-pull through" {
  // Any subsumes anything ⇒ a union containing Any reduces to just Any.
  let raw : Array[@ast.TsType] = [Any, String_, Number]
  let simplified = simplify_union(raw)
  assert_eq(simplified.length(), 1)
  assert_eq(simplified[0], Any)
}

///|
test "collect_referenced_names: walks compound types" {
  let t : @ast.TsType = Func(
    [Applied("Box", [Named("T")])],
    Union([Named("Foo"), Named("Bar")]),
  )
  let refs = collect_referenced_names(t)
  assert_true(refs.contains("Box"))
  assert_true(refs.contains("T"))
  assert_true(refs.contains("Foo"))
  assert_true(refs.contains("Bar"))
}

///|
test "collect_referenced_names: deduplicates" {
  let t : @ast.TsType = Union([Named("A"), Named("A"), Named("B")])
  let refs = collect_referenced_names(t)
  assert_eq(refs.length(), 2)
}
