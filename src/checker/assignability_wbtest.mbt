///|
test "is_assignable_to: identical primitives are assignable" {
  assert_true(is_assignable_to(String_, String_))
  assert_true(is_assignable_to(Number, Number))
  assert_true(is_assignable_to(Boolean, Boolean))
  assert_true(is_assignable_to(BigInt, BigInt))
  assert_true(is_assignable_to(Void, Void))
}

///|
test "is_assignable_to: distinct primitives are not assignable" {
  assert_false(is_assignable_to(String_, Number))
  assert_false(is_assignable_to(Number, String_))
  assert_false(is_assignable_to(Boolean, Number))
}

///|
test "is_assignable_to: any flows in both directions" {
  assert_true(is_assignable_to(Any, String_))
  assert_true(is_assignable_to(String_, Any))
  assert_true(is_assignable_to(Any, Any))
}

///|
test "is_assignable_to: never is assignable to anything but only never accepts never" {
  assert_true(is_assignable_to(Never, String_))
  assert_true(is_assignable_to(Never, Number))
  assert_true(is_assignable_to(Never, Never))
  assert_false(is_assignable_to(String_, Never))
}

///|
test "is_assignable_to: literals widen to their primitives" {
  assert_true(is_assignable_to(Literal("hello"), String_))
  assert_true(is_assignable_to(NumberLiteral("42"), Number))
  assert_true(is_assignable_to(BooleanLiteral(true), Boolean))
  assert_true(is_assignable_to(BigIntLiteral("9"), BigInt))
}

///|
test "is_assignable_to: literals are not implicitly compatible across primitives" {
  assert_false(is_assignable_to(Literal("hello"), Number))
  assert_false(is_assignable_to(NumberLiteral("42"), String_))
}

///|
test "is_assignable_to: identical literals are assignable, distinct literals are not" {
  assert_true(is_assignable_to(Literal("foo"), Literal("foo")))
  assert_false(is_assignable_to(Literal("foo"), Literal("bar")))
  assert_false(is_assignable_to(String_, Literal("foo")))
}

///|
test "is_assignable_to: source union requires every member to be assignable" {
  assert_true(
    is_assignable_to(Union([Literal("a"), Literal("b")]), String_),
  )
  assert_false(is_assignable_to(Union([String_, Number]), String_))
}

///|
test "is_assignable_to: target union accepts a member match" {
  assert_true(is_assignable_to(String_, Union([String_, Number])))
  assert_true(
    is_assignable_to(Literal("foo"), Union([Literal("foo"), Literal("bar")])),
  )
  assert_false(is_assignable_to(Boolean, Union([String_, Number])))
}

///|
test "is_assignable_to: optional T is modelled as T | undefined" {
  assert_true(is_assignable_to(String_, Union([String_, Undefined])))
  assert_true(is_assignable_to(Undefined, Union([String_, Undefined])))
  assert_false(is_assignable_to(Number, Union([String_, Undefined])))
}

///|
test "is_assignable_to: target intersection requires every member to accept" {
  assert_true(is_assignable_to(Number, Intersection([Number, Number])))
  assert_false(is_assignable_to(Number, Intersection([Number, String_])))
}

///|
test "is_assignable_to: arrays are covariant" {
  assert_true(is_assignable_to(Array(String_), Array(String_)))
  assert_true(is_assignable_to(Array(Literal("foo")), Array(String_)))
  assert_false(is_assignable_to(Array(String_), Array(Number)))
}

///|
test "is_assignable_to: tuples require matching length and assignable elements" {
  assert_true(
    is_assignable_to(Tuple([String_, Number]), Tuple([String_, Number])),
  )
  assert_true(
    is_assignable_to(Tuple([Literal("a"), NumberLiteral("1")]), Tuple([
      String_,
      Number,
    ])),
  )
  assert_false(
    is_assignable_to(Tuple([String_]), Tuple([String_, Number])),
  )
  assert_false(is_assignable_to(Tuple([String_, Number]), Tuple([String_])))
}

///|
test "is_assignable_to: functions are contravariant in params, covariant in return" {
  // (x: any) => string is assignable to (x: string) => string
  // because any → string flows in (param contravariance: target's string narrower than source's any)
  assert_true(is_assignable_to(Func([Any], String_), Func([String_], String_)))
  // (x: string) => string is assignable to (x: string) => any (return covariance)
  assert_true(is_assignable_to(Func([String_], String_), Func([String_], Any)))
  // arity mismatch
  assert_false(
    is_assignable_to(Func([String_, Number], String_), Func([String_], String_)),
  )
  // return mismatch
  assert_false(
    is_assignable_to(Func([String_], String_), Func([String_], Number)),
  )
}

///|
test "is_assignable_to: structural object subtyping" {
  let a : @ast.TsType = Object([(Literal("x"), Number), (Literal("y"), Number)])
  let b : @ast.TsType = Object([(Literal("x"), Number)])
  // {x:number, y:number} is assignable to {x:number}
  assert_true(is_assignable_to(a, b))
  // {x:number} is NOT assignable to {x:number, y:number}
  assert_false(is_assignable_to(b, a))
  // Field type mismatch
  let c : @ast.TsType = Object([(Literal("x"), String_)])
  assert_false(is_assignable_to(a, c))
}

///|
test "is_assignable_to: named references match by name" {
  assert_true(is_assignable_to(Named("Foo"), Named("Foo")))
  assert_false(is_assignable_to(Named("Foo"), Named("Bar")))
}
