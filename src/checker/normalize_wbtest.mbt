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

///|
test "simplify_union: flattens nested unions before deduplication" {
  let raw : Array[@ast.TsType] = [
    String_,
    Union([String_, Number]),
    Number,
  ]
  let simplified = simplify_union(raw)
  assert_eq(simplified.length(), 2)
  assert_true(simplified.contains(String_))
  assert_true(simplified.contains(Number))
}

///|
test "type_is_named: matches Named and Applied head" {
  assert_true(type_is_named(Named("Foo"), ["Foo", "Bar"]))
  assert_true(type_is_named(Applied("Foo", [String_]), ["Foo"]))
  assert_false(type_is_named(Named("Baz"), ["Foo", "Bar"]))
  assert_false(type_is_named(String_, ["Foo"]))
}

///|
test "type_contains_string: matches String_ and Literal" {
  assert_true(type_contains_string(String_))
  assert_true(type_contains_string(Literal("hi")))
  assert_true(type_contains_string(Union([Number, String_])))
  assert_false(type_contains_string(Number))
}

///|
test "type_contains_boolean: traverses Promise/Array/Union/Intersection" {
  assert_true(type_contains_boolean(Boolean))
  assert_true(type_contains_boolean(BooleanLiteral(true)))
  assert_true(type_contains_boolean(Union([String_, Boolean])))
  assert_true(
    type_contains_boolean(Applied("Promise", [Boolean])),
  )
  assert_true(type_contains_boolean(Array(Boolean)))
  assert_false(type_contains_boolean(Union([String_, Number])))
}

///|
test "type_contains_string_array: matches Array(string-like) variants" {
  assert_true(type_contains_string_array(Array(String_)))
  assert_true(type_contains_string_array(Applied("Array", [String_])))
  assert_true(type_contains_string_array(Applied("ReadonlyArray", [String_])))
  assert_true(type_contains_string_array(Union([Number, Array(String_)])))
  assert_false(type_contains_string_array(Array(Number)))
}

///|
test "type_contains_named: looks through union members only" {
  assert_true(type_contains_named(Named("Foo"), ["Foo"]))
  assert_true(
    type_contains_named(Union([String_, Named("Foo")]), ["Foo"]),
  )
  // Does NOT recurse into Array/Tuple/Object — by design.
  assert_false(type_contains_named(Array(Named("Foo")), ["Foo"]))
}

///|
test "simplify_union: deeply nested unions are flattened" {
  let raw : Array[@ast.TsType] = [
    Union([Union([String_, Number]), Boolean]),
    Number,
  ]
  let simplified = simplify_union(raw)
  assert_eq(simplified.length(), 3)
  assert_true(simplified.contains(String_))
  assert_true(simplified.contains(Number))
  assert_true(simplified.contains(Boolean))
}
