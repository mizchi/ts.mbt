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
test "simplify_type_with: resolves alias before simplifying" {
  // type Box = { value: number; extra: number };
  // Then IndexedAccess(Named("Box"), Literal("value")) should reduce to number.
  let table : Map[String, @ast.TsType] = {
    "Box": Object([(Literal("value"), Number), (Literal("extra"), Number)]),
  }
  let resolve = fn(name) { table.get(name) }
  let t : @ast.TsType = IndexedAccess(Named("Box"), Literal("value"))
  assert_eq(simplify_type_with(t, resolve), Number)
}

///|
test "simplify_type_with_generics: resolves Applied before simplifying" {
  // type Box<T> = { value: T };
  // IndexedAccess(Box<string>, "value") ⇒ string after substitution + simplify.
  let table : Map[String, AliasBinding] = {
    "Box": {
      type_params: ["T"],
      body: Object([(Literal("value"), Named("T"))]),
    },
  }
  let resolve = fn(name) { table.get(name) }
  let t : @ast.TsType = IndexedAccess(
    Applied("Box", [String_]),
    Literal("value"),
  )
  assert_eq(simplify_type_with_generics(t, resolve), String_)
}

///|
test "simplify_type: idempotent" {
  let t : @ast.TsType = Union([String_, String_, Number, Literal("foo")])
  let once = simplify_type(t)
  let twice = simplify_type(once)
  assert_eq(once, twice)
}

///|
test "simplify_type: collapses concrete conditional via direct decision" {
  // `string extends string ? "y" : "n"` -> `"y"`.
  let t : @ast.TsType = Conditional(
    String_,
    String_,
    Literal("y"),
    Literal("n"),
  )
  assert_eq(simplify_type(t), Literal("y"))
}

///|
test "simplify_type: distributes conditional over a union check" {
  // `(string | number) extends string ? "y" : "n"`
  // -> `("y") | ("n")` after distribution.
  let t : @ast.TsType = Conditional(
    Union([String_, Number]),
    String_,
    Literal("y"),
    Literal("n"),
  )
  // Both branches reduce, so we get a 2-member union.
  assert_eq(simplify_type(t), Union([Literal("y"), Literal("n")]))
}

///|
test "simplify_type: distributes and collapses when all branches agree" {
  // `(string | number) extends string | number ? "y" : "n"` -> `"y"`.
  let t : @ast.TsType = Conditional(
    Union([String_, Number]),
    Union([String_, Number]),
    Literal("y"),
    Literal("n"),
  )
  assert_eq(simplify_type(t), Literal("y"))
}

///|
test "simplify_type: leaves conditional unresolved when decision is undecidable" {
  // `Foo extends Bar ? "y" : "n"` — both Named, no resolver — undecidable.
  let t : @ast.TsType = Conditional(
    Named("Foo"),
    Named("Bar"),
    Literal("y"),
    Literal("n"),
  )
  assert_eq(simplify_type(t), t)
}
