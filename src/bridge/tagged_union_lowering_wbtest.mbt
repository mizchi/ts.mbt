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
  let members : Array[@ast.TsType] = [@ast.TsType::Number, @ast.TsType::Number]
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

///|
test "tagged union alias: type Input = number | string | Date lowers" {
  let type_alias : @ast.TsTypeAlias = {
    name: "Input",
    type_params: [],
    type_param_bounds: [],
    type_: @ast.TsType::Union([
      @ast.TsType::Number,
      @ast.TsType::String_,
      @ast.TsType::Named("Date"),
    ]),
  }
  match tagged_union_type_alias_decl(type_alias) {
    Some(decl) => {
      assert_eq(decl.name, "Input")
      assert_eq(decl.cases.length(), 3)
      assert_eq(decl.cases[2].0, "DateValue")
    }
    None => fail("expected number | string | Date alias to lower")
  }
}

///|
test "tagged union alias: generic alias is rejected" {
  let type_alias : @ast.TsTypeAlias = {
    name: "Wrap",
    type_params: ["T"],
    type_param_bounds: [],
    type_: @ast.TsType::Union([@ast.TsType::Named("T"), @ast.TsType::String_]),
  }
  match tagged_union_type_alias_decl(type_alias) {
    Some(_) => fail("generic alias must defer to existing generic path")
    None => ()
  }
}

///|
test "tagged union alias: non-union body is rejected" {
  let type_alias : @ast.TsTypeAlias = {
    name: "JustString",
    type_params: [],
    type_param_bounds: [],
    type_: @ast.TsType::String_,
  }
  match tagged_union_type_alias_decl(type_alias) {
    Some(_) => fail("alias body must be a Union")
    None => ()
  }
}

///|
test "tagged union alias: literal-only union is rejected" {
  let type_alias : @ast.TsTypeAlias = {
    name: "Variant",
    type_params: [],
    type_param_bounds: [],
    type_: @ast.TsType::Union([
      @ast.TsType::Literal("a"),
      @ast.TsType::Literal("b"),
    ]),
  }
  match tagged_union_type_alias_decl(type_alias) {
    Some(_) => fail("literal-only unions must defer to enum_lowering")
    None => ()
  }
}

///|
test "tagged union: to-JS snippet reads $tag and _0" {
  let decl : BridgeTaggedUnionDecl = {
    name: "Mode",
    cases: [
      ("NumberValue", @ast.TsType::Number),
      ("StringValue", @ast.TsType::String_),
    ],
  }
  let snippet = tagged_union_to_js_expression(decl, "x")
  assert_true(snippet.contains("x.$tag === 0"))
  assert_true(snippet.contains("x.$tag === 1"))
  assert_true(snippet.contains("x._0"))
  assert_true(snippet.contains("unexpected Mode tag"))
}

///|
test "tagged union: from-JS snippet uses typeof predicates" {
  let decl : BridgeTaggedUnionDecl = {
    name: "Mode",
    cases: [
      ("NumberValue", @ast.TsType::Number),
      ("StringValue", @ast.TsType::String_),
    ],
  }
  match tagged_union_from_js_expression(decl, "v") {
    Some(snippet) => {
      assert_true(snippet.contains("typeof v === \"number\""))
      assert_true(snippet.contains("typeof v === \"string\""))
      assert_true(snippet.contains("\"$tag\": 0"))
      assert_true(snippet.contains("\"$tag\": 1"))
    }
    None => fail("number / string discrimination should succeed")
  }
}

///|
test "tagged union: from-JS snippet uses instanceof for Named" {
  let decl : BridgeTaggedUnionDecl = {
    name: "Input",
    cases: [
      ("DateValue", @ast.TsType::Named("Date")),
      ("StringValue", @ast.TsType::String_),
    ],
  }
  match tagged_union_from_js_expression(decl, "v") {
    Some(snippet) => {
      assert_true(snippet.contains("v instanceof Date"))
      assert_true(snippet.contains("typeof v === \"string\""))
    }
    None => fail("instanceof Date should be a valid discriminator")
  }
}

///|
test "tagged union: from-JS snippet uses Array.isArray for arrays" {
  let decl : BridgeTaggedUnionDecl = {
    name: "Path",
    cases: [
      ("StringArray", @ast.TsType::Array(@ast.TsType::String_)),
      ("StringValue", @ast.TsType::String_),
    ],
  }
  match tagged_union_from_js_expression(decl, "v") {
    Some(snippet) => assert_true(snippet.contains("Array.isArray(v)"))
    None => fail("Array.isArray should be a valid discriminator")
  }
}
