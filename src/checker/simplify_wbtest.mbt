///|
test "simplify_type: collapses redundant union" {
  let t : @ast.TsType = Union([String_, Literal("foo"), String_])
  assert_eq(simplify_type(t), String_)
}

///|
test "simplify_type: unwraps transparent intersection" {
  let t : @ast.TsType = Intersection([Named("Foo"), Object([])])
  assert_eq(simplify_type(t), Named("Foo"))
}

///|
test "simplify_type: resolves IndexedAccess against object" {
  let obj : @ast.TsType = Object([
    (Literal("x"), Number),
    (Literal("y"), String_),
  ])
  let t : @ast.TsType = IndexedAccess(obj, Literal("x"))
  assert_eq(simplify_type(t), Number)
}

///|
test "simplify_type: leaves unresolvable IndexedAccess as Any" {
  let t : @ast.TsType = IndexedAccess(Named("Opaque"), Literal("k"))
  assert_eq(simplify_type(t), Any)
}

///|
test "simplify_type: recurses into compound types" {
  // Array<Union(String_, String_)> ⇒ Array<String_>
  let t : @ast.TsType = Array(Union([String_, String_]))
  assert_eq(simplify_type(t), Array(String_))
  // Tuple with redundant union member
  let t2 : @ast.TsType = Tuple([Union([Number, Number]), String_])
  assert_eq(simplify_type(t2), Tuple([Number, String_]))
}

///|
test "simplify_type: unwraps single-member union after simplification" {
  // Union with literal subsumed by primitive collapses to the primitive.
  let t : @ast.TsType = Union([String_, Literal("foo")])
  assert_eq(simplify_type(t), String_)
}

///|
test "simplify_type: preserves multi-member union" {
  let t : @ast.TsType = Union([String_, Number])
  match simplify_type(t) {
    Union(members) => {
      assert_eq(members.length(), 2)
      assert_true(members.contains(String_))
      assert_true(members.contains(Number))
    }
    _ => fail("expected Union after simplify")
  }
}

///|
test "simplify_type: idempotent" {
  let t : @ast.TsType = Union([String_, String_, Number, Literal("foo")])
  let once = simplify_type(t)
  let twice = simplify_type(once)
  assert_eq(once, twice)
}
