///|
test "extends_decision: distinct unique-symbol tags are disjoint" {
  // Two different occurrences of `unique symbol` should not extend
  // each other.
  let a : @ast.TsType = UniqueSymbol("__tsmbt_us_1")
  let b : @ast.TsType = UniqueSymbol("__tsmbt_us_2")
  @test.assert_eq(extends_decision(a, b), Some(false))
  @test.assert_eq(extends_decision(a, a), Some(true))
  // Either still widens to bare `Symbol`.
  @test.assert_eq(extends_decision(a, @ast.TsType::Symbol), Some(true))
}

///|
test "extends_decision: identity is true" {
  @test.assert_eq(extends_decision(String_, String_), Some(true))
  @test.assert_eq(extends_decision(Number, Number), Some(true))
}

///|
test "extends_decision: any target accepts anything as true" {
  @test.assert_eq(extends_decision(String_, Any), Some(true))
  @test.assert_eq(extends_decision(Never, Any), Some(true))
}

///|
test "extends_decision: never source extends anything" {
  @test.assert_eq(extends_decision(Never, String_), Some(true))
  @test.assert_eq(extends_decision(Never, Number), Some(true))
}

///|
test "extends_decision: int extends number" {
  @test.assert_eq(extends_decision(Int, Number), Some(true))
}

///|
test "extends_decision: distinct primitives report false definitively" {
  @test.assert_eq(extends_decision(String_, Number), Some(false))
  @test.assert_eq(extends_decision(Boolean, String_), Some(false))
}

///|
test "extends_decision: unknown for non-primitive nominal types without info" {
  @test.assert_eq(extends_decision(Named("Foo"), Named("Bar")), None)
  @test.assert_eq(
    extends_decision(Applied("Box", [String_]), Named("Foo")),
    None,
  )
}

///|
test "extends_decision: target union — short-circuit on a confirmed match" {
  @test.assert_eq(
    extends_decision(String_, Union([String_, Number])),
    Some(true),
  )
}

///|
test "extends_decision: target union — all branches definitely false" {
  @test.assert_eq(
    extends_decision(Boolean, Union([String_, Number])),
    Some(false),
  )
}

///|
test "extends_decision: target union — propagates unknown" {
  // Boolean vs Named("Foo") is unknown ⇒ overall is unknown.
  @test.assert_eq(
    extends_decision(Boolean, Union([String_, Named("Foo")])),
    None,
  )
}

///|
test "extends_decision: source union — every branch must extend" {
  @test.assert_eq(
    extends_decision(Union([Literal("a"), Literal("b")]), String_),
    Some(true),
  )
  @test.assert_eq(
    extends_decision(Union([String_, Number]), String_),
    Some(false),
  )
}

///|
test "extends_decision: source union — propagates unknown" {
  @test.assert_eq(
    extends_decision(Union([String_, Named("Foo")]), String_),
    None,
  )
}

///|
test "extends_decision_with: resolves names then decides" {
  // type ID = string;  ID extends string ⇒ true.
  let table : Map[String, @ast.TsType] = { "ID": String_ }
  let resolve = fn(name) { table.get(name) }
  @test.assert_eq(
    extends_decision_with(Named("ID"), String_, resolve),
    Some(true),
  )
  @test.assert_eq(
    extends_decision_with(Named("ID"), Number, resolve),
    Some(false),
  )
}

///|
test "extends_decision_with_generics: resolves Applied bindings" {
  // type Maybe<T> = T | undefined; Maybe<string> extends string | undefined?
  let table : Map[String, AliasBinding] = {
    "Maybe": { type_params: ["T"], body: Union([Named("T"), Undefined]) },
  }
  let resolve = fn(name) { table.get(name) }
  @test.assert_eq(
    extends_decision_with_generics(
      Applied("Maybe", [String_]),
      Union([String_, Undefined]),
      resolve,
    ),
    Some(true),
  )
}

///|
test "extends_decision_with_generics: 3-valued unknown survives expansion" {
  let table : Map[String, AliasBinding] = {}
  let resolve = fn(name) { table.get(name) }
  // Two unrelated nominal types stay unknown.
  @test.assert_eq(
    extends_decision_with_generics(Named("Foo"), Named("Bar"), resolve),
    None,
  )
}

///|
test "extends_decision: plain-return fn never extends a predicate-return fn" {
  // tsc: `((x: any) => boolean) extends ((x: any) => x is string)` is false
  // — a source signature "must be a type predicate".
  @test.assert_eq(
    extends_decision(
      Func([Any], Boolean),
      Func([Any], TypePredicate("x", String_)),
    ),
    Some(false),
  )
  // zod's refine shape: callback returning `unknown | Promise<unknown>`.
  @test.assert_eq(
    extends_decision(
      Func([Named("Out")], Union([Named("unknown"), Applied("Promise", [Any])])),
      Func([Any], TypePredicate("arg", Named("R"))),
    ),
    Some(false),
  )
  // A predicate-return source stays undecided here (it MAY extend).
  @test.assert_eq(
    extends_decision(
      Func([Any], TypePredicate("x", String_)),
      Func([Any], TypePredicate("x", Named("R"))),
    ),
    None,
  )
  // `any`-returning sources stay undecided out of caution.
  @test.assert_eq(
    extends_decision(Func([Any], Any), Func([Any], TypePredicate("x", String_))),
    None,
  )
}
