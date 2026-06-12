///|
test "is_assignable_to: boxed wrappers are not assignable to primitives" {
  // `var s: string = new String("")` is a TS error: the wrapper object is
  // not assignable to the primitive. The reverse (primitive widening to the
  // wrapper interface) is fine and handled structurally elsewhere.
  assert_false(is_assignable_to(Named("String"), String_))
  assert_false(is_assignable_to(Named("Number"), Number))
  assert_false(is_assignable_to(Named("Number"), Int))
  assert_false(is_assignable_to(Named("Boolean"), Boolean))
  assert_false(is_assignable_to(Named("BigInt"), BigInt))
  assert_false(is_assignable_to(Named("Symbol"), Symbol))
}

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
// `unknown` is the safe top type — every source flows in but it only
// flows out to itself (and `any`). This is what distinguishes it from
// `any` semantically.
test "is_assignable_to: unknown accepts everything but flows out only to unknown/any" {
  assert_true(is_assignable_to(String_, Unknown))
  assert_true(is_assignable_to(Number, Unknown))
  assert_true(is_assignable_to(Object([(Literal("x"), Number)]), Unknown))
  assert_true(is_assignable_to(Unknown, Unknown))
  assert_true(is_assignable_to(Unknown, Any))
  // `unknown` does not flow into a concrete type without narrowing.
  assert_false(is_assignable_to(Unknown, String_))
  assert_false(is_assignable_to(Unknown, Object([(Literal("x"), Number)])))
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
  assert_true(is_assignable_to(Union([Literal("a"), Literal("b")]), String_))
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
    is_assignable_to(
      Tuple([Literal("a"), NumberLiteral("1")]),
      Tuple([String_, Number]),
    ),
  )
  assert_false(is_assignable_to(Tuple([String_]), Tuple([String_, Number])))
  assert_false(is_assignable_to(Tuple([String_, Number]), Tuple([String_])))
}

///|
// TS: `[string, number, number]` is assignable to `[string, ...number[]]`
// and `[string]` is assignable to `[string, ...number[]]` (rest may be
// empty). Fixed-length sources flow into variadic targets when prefix /
// suffix shapes line up and middle elements fit the rest's element type.
test "is_assignable_to: fixed tuple flows into variadic target" {
  // Prefix only.
  assert_true(
    is_assignable_to(
      Tuple([String_, Number, Number]),
      Tuple([String_, Rest(Array(Number))]),
    ),
  )
  // Empty rest is allowed.
  assert_true(
    is_assignable_to(Tuple([String_]), Tuple([String_, Rest(Array(Number))])),
  )
  // Prefix + suffix with middle elements flowing into rest.
  assert_true(
    is_assignable_to(
      Tuple([String_, Number, Number, Boolean]),
      Tuple([String_, Rest(Array(Number)), Boolean]),
    ),
  )
  // Source too short for the fixed prefix/suffix.
  assert_false(
    is_assignable_to(
      Tuple([String_]),
      Tuple([String_, Rest(Array(Number)), Boolean]),
    ),
  )
  // Middle element type mismatch.
  assert_false(
    is_assignable_to(
      Tuple([String_, Boolean, Boolean]),
      Tuple([String_, Rest(Array(Number))]),
    ),
  )
}

///|
// Variadic-to-variadic: same prefix/suffix and matching rest position
// reduces to the existing pointwise rule, so `Rest(Array(T))` matches
// `Rest(Array(T))` directly.
test "is_assignable_to: same-shape variadic tuples are assignable" {
  assert_true(
    is_assignable_to(
      Tuple([String_, Rest(Array(Number))]),
      Tuple([String_, Rest(Array(Number))]),
    ),
  )
  // Differing rest positions: not handled (would require alignment).
  assert_false(
    is_assignable_to(
      Tuple([String_, Rest(Array(Number))]),
      Tuple([Rest(Array(Number)), String_]),
    ),
  )
}

///|
// Variadic source flowing into a fixed-length target: source could have
// any number of elements at the type level, so this is rejected.
test "is_assignable_to: variadic source does not flow into fixed target" {
  assert_false(
    is_assignable_to(
      Tuple([String_, Rest(Array(Number))]),
      Tuple([String_, Number]),
    ),
  )
}

///|
test "is_assignable_to: functions are contravariant in params, covariant in return" {
  // (x: any) => string is assignable to (x: string) => string
  // because any → string flows in (param contravariance: target's string narrower than source's any)
  assert_true(is_assignable_to(Func([Any], String_), Func([String_], String_)))
  // (x: string) => string is assignable to (x: string) => any (return covariance)
  assert_true(is_assignable_to(Func([String_], String_), Func([String_], Any)))
  // Source declares more params than target: rejected because the
  // target's caller won't supply enough arguments.
  assert_false(
    is_assignable_to(Func([String_, Number], String_), Func([String_], String_)),
  )
  // return mismatch
  assert_false(
    is_assignable_to(Func([String_], String_), Func([String_], Number)),
  )
}

///|
// TS allows source to declare fewer parameters than target — the source
// implementation simply ignores trailing arguments. This is a common
// pattern for callbacks like `arr.map(x => x * 2)` where the predicate
// ignores the `(_, index, array)` extras.
test "is_assignable_to: source with fewer params flows into wider target" {
  assert_true(
    is_assignable_to(Func([String_], String_), Func([String_, Number], String_)),
  )
  // Zero-param source flows into any-arity target.
  assert_true(is_assignable_to(Func([], Void), Func([String_, Number], Void)))
  // Param at the shared position still has to be contravariant: target's
  // `string` can't flow into source's `number`.
  assert_false(
    is_assignable_to(Func([Number], Void), Func([String_, Number], Void)),
  )
}

///|
// Function source with a trailing `Rest(...)` parameter can absorb any
// number of trailing target args ≥ its fixed prefix.
test "is_assignable_to: source rest param absorbs target tail" {
  assert_true(
    is_assignable_to(
      Func([String_, Rest(Array(Number))], Void),
      Func([String_, Number, Number, Number], Void),
    ),
  )
  // Target tail element fails contravariance against rest's element type.
  assert_false(
    is_assignable_to(
      Func([String_, Rest(Array(Number))], Void),
      Func([String_, Boolean], Void),
    ),
  )
  // Empty tail is fine — rest can be empty.
  assert_true(
    is_assignable_to(
      Func([String_, Rest(Array(Number))], Void),
      Func([String_], Void),
    ),
  )
}

///|
// Template literal type membership: a string literal source flows into a
// template target when prefix/suffix line up and each placeholder accepts
// the gap. Mirrors TS:
//   const x: `pre_${string}` = "pre_xyz"        // OK
//   const y: `${number}px` = "10px"             // OK
//   const z: `${number}px` = "abcpx"            // error
test "is_assignable_to: literal source flows into template pattern" {
  // Prefix + open string placeholder.
  assert_true(
    is_assignable_to(
      Literal("pre_xyz"),
      TemplateLiteralType(["pre_", ""], [String_]),
    ),
  )
  // Numeric placeholder accepts a numeric substring.
  assert_true(
    is_assignable_to(Literal("10px"), TemplateLiteralType(["", "px"], [Number])),
  )
  // Numeric placeholder rejects a non-numeric substring.
  assert_false(
    is_assignable_to(
      Literal("abcpx"),
      TemplateLiteralType(["", "px"], [Number]),
    ),
  )
  // Prefix mismatch.
  assert_false(
    is_assignable_to(
      Literal("post_xyz"),
      TemplateLiteralType(["pre_", ""], [String_]),
    ),
  )
}

///|
// Index signatures: `{ [k: string]: V }` on the target accepts any source
// named field whose type satisfies V; on the source it satisfies any
// target named field of the same value type. Numeric-literal keys flow
// into a `Number` index when the target has one.
test "is_assignable_to: index signatures accept named properties" {
  // `{ x: number, y: number }` → `{ [k: string]: number }`
  let any_string_to_number : @ast.TsType = Object([(String_, Number)])
  assert_true(
    is_assignable_to(
      Object([(Literal("x"), Number), (Literal("y"), Number)]),
      any_string_to_number,
    ),
  )
  // Mismatched value type is rejected.
  assert_false(
    is_assignable_to(Object([(Literal("x"), String_)]), any_string_to_number),
  )
  // Source index signature flows into target named property of same type.
  assert_true(
    is_assignable_to(any_string_to_number, Object([(Literal("x"), Number)])),
  )
  // Numeric-literal keys land in the number bucket.
  assert_true(
    is_assignable_to(
      Object([(Literal("0"), String_), (Literal("1"), String_)]),
      Object([(Number, String_)]),
    ),
  )
}

///|
// Readonly arrays: TS allows `T[] → ReadonlyArray<T>` but not the
// reverse. The Applied form of `Array<T>` is interchangeable with the
// `T[]` form.
test "is_assignable_to: readonly array variance" {
  // Mutable into readonly is fine.
  assert_true(
    is_assignable_to(Array(Number), Applied("ReadonlyArray", [Number])),
  )
  // Readonly into mutable is rejected.
  assert_false(
    is_assignable_to(Applied("ReadonlyArray", [Number]), Array(Number)),
  )
  // Readonly into Iterable is fine (covariant element).
  assert_true(
    is_assignable_to(
      Applied("ReadonlyArray", [Number]),
      Applied("Iterable", [Number]),
    ),
  )
  // `Array<T>` (Applied) flows into `T[]` (Array variant).
  assert_true(is_assignable_to(Applied("Array", [Number]), Array(Number)))
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

///|
test "is_assignable_to: optional target fields accept missing source fields" {
  // {x: number} is assignable to {x: number; y?: number}
  // because y is optional (number | undefined accepts the missing field).
  let source : @ast.TsType = Object([(Literal("x"), Number)])
  let target : @ast.TsType = Object([
    (Literal("x"), Number),
    (Literal("y"), Union([Number, Undefined])),
  ])
  assert_true(is_assignable_to(source, target))
}

///|
test "is_assignable_to: required target fields still require presence" {
  let source : @ast.TsType = Object([(Literal("x"), Number)])
  let target : @ast.TsType = Object([
    (Literal("x"), Number),
    (Literal("y"), Number),
  ])
  assert_false(is_assignable_to(source, target))
}

///|
test "is_assignable_to: optional encoded with null is also assignable" {
  // {x: number; y?: number | null}
  let source : @ast.TsType = Object([(Literal("x"), Number)])
  let target : @ast.TsType = Object([
    (Literal("x"), Number),
    (Literal("y"), Union([Number, Null, Undefined])),
  ])
  assert_true(is_assignable_to(source, target))
}

///|
test "is_assignable_to: indexed access resolves against object source" {
  // {x: number, y: string}["x"] ⇔ number
  let object_type : @ast.TsType = Object([
    (Literal("x"), Number),
    (Literal("y"), String_),
  ])
  let access : @ast.TsType = IndexedAccess(object_type, Literal("x"))
  assert_true(is_assignable_to(access, Number))
  assert_false(is_assignable_to(access, String_))
}

///|
test "is_assignable_to: indexed access on missing key is unresolvable" {
  // We cannot prove anything about T["unknown"], so it is treated as Any.
  let object_type : @ast.TsType = Object([(Literal("x"), Number)])
  let access : @ast.TsType = IndexedAccess(object_type, Literal("missing"))
  // Conservative: unresolvable indexed accesses fall back to Any.
  assert_true(is_assignable_to(access, Number))
  assert_true(is_assignable_to(access, String_))
}

///|
test "is_assignable_to: conditional picks branch when extends decidable" {
  // string extends string ? number : boolean
  // ⇒ number is the resolved type.
  let cond : @ast.TsType = Conditional(String_, String_, Number, Boolean)
  assert_true(is_assignable_to(cond, Number))
  assert_false(is_assignable_to(cond, Boolean))
}

///|
test "is_assignable_to: conditional picks false branch on non-extends" {
  // string extends number ? boolean : Number
  // ⇒ Number is the resolved type.
  let cond : @ast.TsType = Conditional(String_, Number, Boolean, Number)
  assert_true(is_assignable_to(cond, Number))
  assert_false(is_assignable_to(cond, Boolean))
}

///|
test "is_assignable_to: conditional with infer extracts inner type" {
  // (Promise<string>) extends Promise<infer U> ? U : never
  // Should reduce to string.
  let cond : @ast.TsType = Conditional(
    Applied("Promise", [String_]),
    Applied("Promise", [Applied("__tsmbt_infer", [Named("U")])]),
    Named("U"),
    Never,
  )
  assert_true(is_assignable_to(cond, String_))
  assert_false(is_assignable_to(cond, Number))
}

///|
test "is_assignable_to: conditional with infer falls through on mismatch" {
  // (Array<string>) extends Promise<infer U> ? U : number
  // Pattern doesn't match; should reduce to number.
  let cond : @ast.TsType = Conditional(
    Array(String_),
    Applied("Promise", [Applied("__tsmbt_infer", [Named("U")])]),
    Named("U"),
    Number,
  )
  assert_true(is_assignable_to(cond, Number))
  assert_false(is_assignable_to(cond, String_))
}

///|
test "is_assignable_to: applied generics match by name and argument assignability" {
  // Box<"a"> is assignable to Box<string> (covariant — best-effort).
  let s : @ast.TsType = Applied("Box", [Literal("a")])
  let t : @ast.TsType = Applied("Box", [String_])
  assert_true(is_assignable_to(s, t))
  // Box<string> is not assignable to Box<number>.
  assert_false(is_assignable_to(s, Applied("Box", [Number])))
}

///|
test "is_assignable_to: source object intersection merges into a combined shape" {
  // `{a: string} & {b: number}` is assignable to `{a: string, b: number}` —
  // TS merges the members, which the old per-component rule could not.
  let s : @ast.TsType = Intersection([
    Struct("A", [("a", String_)]),
    Struct("B", [("b", Number)]),
  ])
  let t : @ast.TsType = Struct("AB", [("a", String_), ("b", Number)])
  assert_true(is_assignable_to(s, t))
  // The merged shape also still satisfies either single member.
  assert_true(is_assignable_to(s, Struct("A", [("a", String_)])))
  // A field the merge does not provide is still rejected.
  assert_false(is_assignable_to(s, Struct("C", [("c", Boolean)])))
}

///|
test "is_assignable_to: object-literal intersection merges too" {
  let s : @ast.TsType = Intersection([
    Object([(Literal("x"), Number)]),
    Object([(Literal("y"), String_)]),
  ])
  let t : @ast.TsType = Object([(Literal("x"), Number), (Literal("y"), String_)])
  assert_true(is_assignable_to(s, t))
}

///|
test "is_assignable_to: intersection with a non-object member declines the merge" {
  // `{a: string} & number` is not an object bag; the per-component fallback
  // applies, so it flows into `number` but not into `{a: string, b: number}`.
  let s : @ast.TsType = Intersection([Struct("A", [("a", String_)]), Number])
  assert_true(is_assignable_to(s, Number))
  assert_false(
    is_assignable_to(s, Struct("AB", [("a", String_), ("b", Number)])),
  )
}

///|
test "is_assignable_to: symbol index signature accepts a symbol-keyed source" {
  // `{ [k: symbol]: number }` is satisfied by a source whose symbol
  // index signature carries a compatible value type.
  let target : @ast.TsType = Object([(Symbol, Number)])
  let ok : @ast.TsType = Object([(Symbol, NumberLiteral("1"))])
  assert_true(is_assignable_to(ok, target))
  // A symbol index signature whose value type does not fit is rejected.
  let bad : @ast.TsType = Object([(Symbol, String_)])
  assert_false(is_assignable_to(bad, target))
}

///|
test "is_assignable_to: a primitive flows into its boxed wrapper" {
  // `number` is assignable to `Number`, but not the reverse.
  assert_true(is_assignable_to(Number, Named("Number")))
  assert_true(is_assignable_to(String_, Named("String")))
  assert_true(is_assignable_to(Boolean, Named("Boolean")))
  assert_false(is_assignable_to(Named("Number"), Number))
}
