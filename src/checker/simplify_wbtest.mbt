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

///|
test "simplify_type: keyof Struct -> Union of literal field names" {
  let s : @ast.TsType = Struct("Foo", [
    ("a", Number),
    ("b", String_),
    ("c", Boolean),
  ])
  assert_eq(
    simplify_type(Keyof(s)),
    Union([Literal("a"), Literal("b"), Literal("c")]),
  )
}

///|
test "simplify_type: keyof Object with literal keys -> Union of literals" {
  let o : @ast.TsType = Object([(Literal("x"), Number), (Literal("y"), String_)])
  assert_eq(simplify_type(Keyof(o)), Union([Literal("x"), Literal("y")]))
}

///|
test "simplify_type: keyof single-field Struct collapses to the literal" {
  let s : @ast.TsType = Struct("Foo", [("only", Number)])
  assert_eq(simplify_type(Keyof(s)), Literal("only"))
}

///|
test "simplify_type: keyof preserved when operand is opaque Named" {
  // Without a resolver we can't see through `Foo`; the keyof must stay so
  // a later pass with substitution can retry.
  let t : @ast.TsType = Keyof(Named("Foo"))
  assert_eq(simplify_type(t), t)
}

///|
test "simplify_type: keyof empty struct -> Never" {
  let s : @ast.TsType = Struct("Empty", [])
  assert_eq(simplify_type(Keyof(s)), Never)
}

///|
test "simplify_type: mapped over literal union substitutes binder" {
  // `{ [K in 'a' | 'b']: K }` ⇒ `{ a: 'a', b: 'b' }`
  let t : @ast.TsType = MappedType(
    "K",
    Union([Literal("a"), Literal("b")]),
    Named("K"),
    false,
  )
  assert_eq(
    simplify_type(t),
    Object([(Literal("a"), Literal("a")), (Literal("b"), Literal("b"))]),
  )
}

///|
test "simplify_type: mapped over keyof Struct produces full Object" {
  // `{ [K in keyof Foo]: number }` for `Foo = { a, b, c }` ⇒ object with
  // those three literal keys, all numeric.
  let foo : @ast.TsType = Struct("Foo", [
    ("a", Number),
    ("b", String_),
    ("c", Boolean),
  ])
  let t : @ast.TsType = MappedType("K", Keyof(foo), Number, false)
  assert_eq(
    simplify_type(t),
    Object([
      (Literal("a"), Number),
      (Literal("b"), Number),
      (Literal("c"), Number),
    ]),
  )
}

///|
test "simplify_type: mapped optional wraps each value with undefined" {
  // `{ [K in 'x']?: number }` ⇒ `{ x: number | undefined }`
  let t : @ast.TsType = MappedType("K", Literal("x"), Number, true)
  assert_eq(
    simplify_type(t),
    Object([(Literal("x"), Union([Number, Undefined]))]),
  )
}

///|
test "simplify_type: mapped preserved when source is opaque" {
  // `{ [K in keyof T]: K }` with `T` opaque — keep the mapped shape so a
  // later substitution can resolve `T`.
  let t : @ast.TsType = MappedType("K", Keyof(Named("T")), Named("K"), false)
  assert_eq(simplify_type(t), t)
}

///|
test "simplify_type: mapped `-?` strips undefined from value" {
  // `{ [K in 'a' | 'b']-?: number | undefined }` ⇒
  //   `{ a: number, b: number }`.
  let t : @ast.TsType = MappedType(
    "K",
    Union([Literal("a"), Literal("b")]),
    Applied("__tsmbt_strip_undef", [Union([Number, Undefined])]),
    false,
  )
  assert_eq(
    simplify_type(t),
    Object([(Literal("a"), Number), (Literal("b"), Number)]),
  )
}

///|
test "simplify_type: mapped remap via Capitalize prefixes each key" {
  // `{ [K in 'a' | 'b' as `get${Capitalize<K>}`]: number }`
  //   ⇒ `{ getA: number, getB: number }`
  let t : @ast.TsType = MappedTypeRemap(
    "K",
    Union([Literal("a"), Literal("b")]),
    TemplateLiteralType(["get", ""], [Applied("Capitalize", [Named("K")])]),
    Number,
    false,
  )
  assert_eq(
    simplify_type(t),
    Object([(Literal("getA"), Number), (Literal("getB"), Number)]),
  )
}

///|
test "simplify_type: mapped remap to Never filters key out" {
  // `{ [K in 'a' | 'b' | 'c' as K extends 'b' ? never : K]: number }`
  //   ⇒ `{ a: number, c: number }`. The remap is encoded as a
  // `Conditional` and reduced per key.
  let t : @ast.TsType = MappedTypeRemap(
    "K",
    Union([Literal("a"), Literal("b"), Literal("c")]),
    Conditional(Named("K"), Literal("b"), Never, Named("K")),
    Number,
    false,
  )
  assert_eq(
    simplify_type(t),
    Object([(Literal("a"), Number), (Literal("c"), Number)]),
  )
}

///|
test "simplify_type: mapped remap rewrites value with K binding" {
  // `{ [K in keyof Foo as Uppercase<K & string>]: Foo[K] }` for
  // `Foo = { a: number, b: string }` ⇒
  //   `{ A: number, B: string }`. Here Foo[K] resolves via the
  // generic IndexedAccess + substitution path.
  let foo : @ast.TsType = Struct("Foo", [("a", Number), ("b", String_)])
  let t : @ast.TsType = MappedTypeRemap(
    "K",
    Keyof(foo),
    Applied("Uppercase", [Named("K")]),
    IndexedAccess(foo, Named("K")),
    false,
  )
  assert_eq(
    simplify_type(t),
    Object([(Literal("A"), Number), (Literal("B"), String_)]),
  )
}

///|
test "simplify_type: mapped remap preserved when source is opaque" {
  // `{ [K in keyof T as Uppercase<K & string>]: T[K] }` with `T` opaque —
  // keep the variant so a later substitution can resolve `T`.
  let t : @ast.TsType = MappedTypeRemap(
    "K",
    Keyof(Named("T")),
    Applied("Uppercase", [Named("K")]),
    IndexedAccess(Named("T"), Named("K")),
    false,
  )
  assert_eq(simplify_type(t), t)
}

///|
test "simplify_type: template literal substitutes single literal" {
  // `` `prefix-${'foo'}` `` ⇒ `'prefix-foo'`
  let t : @ast.TsType = TemplateLiteralType(["prefix-", ""], [Literal("foo")])
  assert_eq(simplify_type(t), Literal("prefix-foo"))
}

///|
test "simplify_type: template literal cartesian over a literal union" {
  // `` `${'a' | 'b'}-${'1' | '2'}` `` ⇒
  //   `'a-1' | 'a-2' | 'b-1' | 'b-2'`
  let t : @ast.TsType = TemplateLiteralType(["", "-", ""], [
    Union([Literal("a"), Literal("b")]),
    Union([Literal("1"), Literal("2")]),
  ])
  assert_eq(
    simplify_type(t),
    Union([Literal("a-1"), Literal("a-2"), Literal("b-1"), Literal("b-2")]),
  )
}

///|
test "simplify_type: template literal applies Capitalize intrinsic" {
  // `` `bg${Capitalize<'red'>}` `` ⇒ `'bgRed'`
  let t : @ast.TsType = TemplateLiteralType(["bg", ""], [
    Applied("Capitalize", [Literal("red")]),
  ])
  assert_eq(simplify_type(t), Literal("bgRed"))
}

///|
test "simplify_type: template literal preserved when arg is opaque" {
  // `` `prefix-${T}` `` for opaque `T` — keep the template so later
  // substitution can resolve it.
  let t : @ast.TsType = TemplateLiteralType(["prefix-", ""], [Named("T")])
  assert_eq(simplify_type(t), t)
}
