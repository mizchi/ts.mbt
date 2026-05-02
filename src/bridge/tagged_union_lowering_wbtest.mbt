///|
test "tagged union: primitive plus named class is a candidate" {
  let members : Array[@ast.TsType] = [
    @ast.TsType::Number,
    @ast.TsType::String_,
    @ast.TsType::Named("Date"),
  ]
  match tagged_union_cases(members) {
    Some(cases) => {
      assert_eq(cases.length(), 3)
      assert_eq(cases[0].0, "NumberValue")
      assert_eq(cases[1].0, "StringValue")
      assert_eq(cases[2].0, "DateValue")
    }
    None => fail("expected number | string | Date to lower")
  }
}

///|
test "tagged union: string literal members reject candidate" {
  let members : Array[@ast.TsType] = [
    @ast.TsType::Boolean,
    @ast.TsType::Literal("boundary"),
  ]
  match tagged_union_cases(members) {
    Some(_) => fail("literal members must defer to literal-union path")
    None => ()
  }
}

///|
test "tagged union: duplicate inner names are rejected" {
  let members : Array[@ast.TsType] = [
    @ast.TsType::Number,
    @ast.TsType::Number,
  ]
  match tagged_union_cases(members) {
    Some(_) => fail("duplicate primitive members are ambiguous")
    None => ()
  }
}

///|
test "tagged union: array of primitive plus primitive lowers to enum cases" {
  let members : Array[@ast.TsType] = [
    @ast.TsType::String_,
    @ast.TsType::Array(@ast.TsType::String_),
  ]
  match tagged_union_cases(members) {
    Some(cases) => {
      assert_eq(cases.length(), 2)
      assert_eq(cases[0].0, "StringValue")
      assert_eq(cases[1].0, "StringArray")
    }
    None => fail("expected string | string[] to lower")
  }
}

///|
test "tagged union: single member is rejected" {
  let members : Array[@ast.TsType] = [@ast.TsType::Number]
  match tagged_union_cases(members) {
    Some(_) => fail("single-member unions are not unions")
    None => ()
  }
}

///|
test "tagged union: lowercase named member is rejected" {
  let members : Array[@ast.TsType] = [
    @ast.TsType::Number,
    @ast.TsType::Named("foo"),
  ]
  match tagged_union_cases(members) {
    Some(_) => fail("non-PascalCase named members must be rejected")
    None => ()
  }
}
