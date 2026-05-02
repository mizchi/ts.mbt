///|
fn make_resolver(
  table : Map[String, @ast.TsType],
) -> (String) -> @ast.TsType? {
  fn(name) {
    table.get(name)
  }
}

///|
test "is_assignable_to_with: resolves named alias on the source side" {
  // type ID = string; check `ID` is assignable to `string`.
  let table : Map[String, @ast.TsType] = { "ID": String_ }
  let resolve = make_resolver(table)
  assert_true(is_assignable_to_with(Named("ID"), String_, resolve))
  assert_false(is_assignable_to_with(Named("ID"), Number, resolve))
}

///|
test "is_assignable_to_with: resolves named alias on the target side" {
  let table : Map[String, @ast.TsType] = { "Email": String_ }
  let resolve = make_resolver(table)
  assert_true(is_assignable_to_with(String_, Named("Email"), resolve))
}

///|
test "is_assignable_to_with: resolves chain of aliases" {
  // type A = B; type B = string;
  let table : Map[String, @ast.TsType] = { "A": Named("B"), "B": String_ }
  let resolve = make_resolver(table)
  assert_true(is_assignable_to_with(Named("A"), String_, resolve))
}

///|
test "is_assignable_to_with: stops on alias cycle without looping" {
  // type Loop = Loop; — pathological, but the resolver must not recurse forever.
  let table : Map[String, @ast.TsType] = { "Loop": Named("Loop") }
  let resolve = make_resolver(table)
  // After cycle detection the source becomes Any and flows to anything.
  assert_true(is_assignable_to_with(Named("Loop"), String_, resolve))
}

///|
test "is_assignable_to_with: unresolved name falls back to nominal match" {
  let table : Map[String, @ast.TsType] = {}
  let resolve = make_resolver(table)
  // Unknown names are treated as nominal — only equal names match.
  assert_true(is_assignable_to_with(Named("Foo"), Named("Foo"), resolve))
  assert_false(is_assignable_to_with(Named("Foo"), Named("Bar"), resolve))
}

///|
test "is_assignable_to_with: applied alias is treated as opaque (best effort)" {
  // A resolver currently only resolves Named. Applied references stay nominal
  // because we do not perform generic substitution.
  let table : Map[String, @ast.TsType] = {
    "Box": Applied("Box", [String_]),
  }
  let resolve = make_resolver(table)
  assert_true(
    is_assignable_to_with(
      Applied("Box", [String_]),
      Applied("Box", [String_]),
      resolve,
    ),
  )
  assert_false(
    is_assignable_to_with(
      Applied("Box", [String_]),
      Applied("Box", [Number]),
      resolve,
    ),
  )
}

///|
test "is_assignable_to_with: resolves through union aliases" {
  // type Maybe<X> would need substitution; keep it simple with a non-generic
  // alias `MaybeString = string | undefined`.
  let table = {
    "MaybeString": (Union([String_, Undefined]) : @ast.TsType),
  }
  let resolve = make_resolver(table)
  assert_true(is_assignable_to_with(String_, Named("MaybeString"), resolve))
  assert_true(
    is_assignable_to_with(Undefined, Named("MaybeString"), resolve),
  )
  assert_false(is_assignable_to_with(Number, Named("MaybeString"), resolve))
}
