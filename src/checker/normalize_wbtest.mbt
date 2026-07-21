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
test "equivalent_with: resolves aliases on both sides" {
  // type ID = string;
  let table : Map[String, @ast.TsType] = { "ID": String_ }
  let resolve = fn(name) { table.get(name) }
  assert_true(equivalent_with(Named("ID"), String_, resolve))
  assert_true(equivalent_with(String_, Named("ID"), resolve))
  assert_false(equivalent_with(Named("ID"), Number, resolve))
}

///|
test "equivalent_with_generics: alias-aware bidirectional check" {
  // type Maybe<T> = T | undefined;
  let table : Map[String, AliasBinding] = {
    "Maybe": { type_params: ["T"], body: Union([Named("T"), Undefined]) },
  }
  let resolve = fn(name) { table.get(name) }
  // Maybe<string> ≡ string | undefined
  assert_true(
    equivalent_with_generics(
      Applied("Maybe", [String_]),
      Union([String_, Undefined]),
      resolve,
    ),
  )
  // Maybe<string> ≢ string (one direction fails)
  assert_false(
    equivalent_with_generics(Applied("Maybe", [String_]), String_, resolve),
  )
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
  let raw : Array[@ast.TsType] = [String_, Union([String_, Number]), Number]
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
  assert_true(type_contains_boolean(Applied("Promise", [Boolean])))
  assert_true(type_contains_boolean(Array(Boolean)))
  assert_false(type_contains_boolean(Union([String_, Number])))
}

///|
test "is_string_literal_union: matches single literal and uniform unions" {
  assert_true(is_string_literal_union(Literal("foo")))
  assert_true(is_string_literal_union(Union([Literal("a"), Literal("b")])))
  assert_false(is_string_literal_union(Union([])))
  assert_false(is_string_literal_union(Union([Literal("a"), Number])))
  assert_false(is_string_literal_union(String_))
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
  assert_true(type_contains_named(Union([String_, Named("Foo")]), ["Foo"]))
  // Does NOT recurse into Array/Tuple/Object — by design.
  assert_false(type_contains_named(Array(Named("Foo")), ["Foo"]))
}

///|
// TS normalizes `true | false` to `boolean`. The pair has no subsumption
// relation, so collapsing requires a dedicated pass before subsumption.
test "simplify_union: collapses true | false to boolean" {
  let raw : Array[@ast.TsType] = [BooleanLiteral(true), BooleanLiteral(false)]
  let simplified = simplify_union(raw)
  assert_eq(simplified.length(), 1)
  assert_eq(simplified[0], Boolean)
}

///|
test "simplify_union: true | false | string collapses to boolean | string" {
  let raw : Array[@ast.TsType] = [
    BooleanLiteral(true),
    String_,
    BooleanLiteral(false),
  ]
  let simplified = simplify_union(raw)
  assert_eq(simplified.length(), 2)
  assert_true(simplified.contains(Boolean))
  assert_true(simplified.contains(String_))
}

///|
test "simplify_union: boolean primitive already present absorbs both literals" {
  let raw : Array[@ast.TsType] = [
    BooleanLiteral(true),
    Boolean,
    BooleanLiteral(false),
  ]
  let simplified = simplify_union(raw)
  assert_eq(simplified.length(), 1)
  assert_eq(simplified[0], Boolean)
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

///|
test "classify_promise_like_union: T | Promise<T> shapes" {
  // The canonical sync-or-async handler return (axios interceptors,
  // middleware): payload surfaces, arm order does not matter, and
  // PromiseLike arms count as promise arms.
  assert_eq(
    classify_promise_like_union(
      Union([Named("V"), Applied("Promise", [Named("V")])]),
    ),
    Some(Named("V")),
  )
  assert_eq(
    classify_promise_like_union(Union([Applied("Promise", [String_]), String_])),
    Some(String_),
  )
  assert_eq(
    classify_promise_like_union(
      Union([
        Named("V"),
        Applied("Promise", [Named("V")]),
        Applied("PromiseLike", [Named("V")]),
      ]),
    ),
    Some(Named("V")),
  )
  // Rejected shapes: mismatched payloads, extra non-promise arms, no
  // promise arm at all, promise-only unions, non-unions.
  assert_eq(
    classify_promise_like_union(
      Union([Named("V"), Applied("Promise", [String_])]),
    ),
    None,
  )
  assert_eq(
    classify_promise_like_union(
      Union([Named("V"), String_, Applied("Promise", [Named("V")])]),
    ),
    None,
  )
  assert_eq(classify_promise_like_union(Union([Named("V"), String_])), None)
  assert_eq(
    classify_promise_like_union(Union([Applied("Promise", [Named("V")])])),
    None,
  )
  assert_eq(classify_promise_like_union(Applied("Promise", [Named("V")])), None)
  // The normalizer rewrites matches to Promise<T> and passes the rest
  // through untouched.
  assert_eq(
    normalize_promise_like_union_return(
      Union([Named("V"), Applied("Promise", [Named("V")])]),
    ),
    Applied("Promise", [Named("V")]),
  )
  assert_eq(
    normalize_promise_like_union_return(Union([Named("V"), String_])),
    Union([Named("V"), String_]),
  )
}
