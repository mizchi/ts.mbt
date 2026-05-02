///|
fn make_generic_resolver(
  table : Map[String, AliasBinding],
) -> (String) -> AliasBinding? {
  fn(name) {
    table.get(name)
  }
}

///|
test "is_assignable_to_with_generics: substitutes type params on Applied" {
  // type Maybe<X> = X | undefined;
  let table : Map[String, AliasBinding] = {
    "Maybe": { type_params: ["X"], body: Union([Named("X"), Undefined]) },
  }
  let resolve = make_generic_resolver(table)
  // String is assignable to Maybe<string>
  assert_true(
    is_assignable_to_with_generics(
      String_,
      Applied("Maybe", [String_]),
      resolve,
    ),
  )
  // Undefined is assignable to Maybe<string>
  assert_true(
    is_assignable_to_with_generics(
      Undefined,
      Applied("Maybe", [String_]),
      resolve,
    ),
  )
  // Number is NOT assignable to Maybe<string>
  assert_false(
    is_assignable_to_with_generics(
      Number,
      Applied("Maybe", [String_]),
      resolve,
    ),
  )
}

///|
test "is_assignable_to_with_generics: chain through generic alias" {
  // type Wrap<X> = Box<X>;
  // type Box<Y> = { value: Y };
  let table : Map[String, AliasBinding] = {
    "Wrap": { type_params: ["X"], body: Applied("Box", [Named("X")]) },
    "Box": {
      type_params: ["Y"],
      body: Object([(Literal("value"), Named("Y"))]),
    },
  }
  let resolve = make_generic_resolver(table)
  // Wrap<string> ⇒ Box<string> ⇒ { value: string }
  assert_true(
    is_assignable_to_with_generics(
      Object([(Literal("value"), String_)]),
      Applied("Wrap", [String_]),
      resolve,
    ),
  )
}

///|
test "is_assignable_to_with_generics: Named without params resolves like type alias" {
  // type ID = string;
  let table : Map[String, AliasBinding] = {
    "ID": { type_params: [], body: String_ },
  }
  let resolve = make_generic_resolver(table)
  assert_true(is_assignable_to_with_generics(Named("ID"), String_, resolve))
}

///|
test "is_assignable_to_with_generics: arity mismatch leaves Applied opaque" {
  // type Maybe<X> = X | undefined; — but caller passes Applied("Maybe", []).
  let table : Map[String, AliasBinding] = {
    "Maybe": { type_params: ["X"], body: Union([Named("X"), Undefined]) },
  }
  let resolve = make_generic_resolver(table)
  // 0 args — substitution cannot proceed; falls back to nominal Applied match.
  assert_false(
    is_assignable_to_with_generics(
      String_,
      Applied("Maybe", []),
      resolve,
    ),
  )
}

///|
test "is_assignable_to_with_generics: cycle through generics is safe" {
  // type Loop<X> = Loop<X>;
  let table : Map[String, AliasBinding] = {
    "Loop": { type_params: ["X"], body: Applied("Loop", [Named("X")]) },
  }
  let resolve = make_generic_resolver(table)
  // After cycle detection the body collapses to Any — flows freely.
  assert_true(
    is_assignable_to_with_generics(
      Applied("Loop", [String_]),
      String_,
      resolve,
    ),
  )
}
