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
test "tagged union: mixed primitive + string literal lowers" {
  // magic-string `hires: boolean | "boundary"` style. Boolean and a string
  // literal share no overlapping primitive type, so the literal becomes a
  // dedicated no-payload enum case.
  let members : Array[@ast.TsType] = [
    @ast.TsType::Boolean,
    @ast.TsType::Literal("boundary"),
  ]
  match tagged_union_cases(members) {
    Some(cases) => {
      assert_eq(cases.length(), 2)
      assert_eq(cases[0].0, "BoolValue")
      assert_eq(cases[1].0, "Boundary")
    }
    None => fail("expected boolean | \"boundary\" to lower")
  }
}

///|
test "tagged union: pure literal-only union still rejected" {
  // Pure literal unions defer to enum_lowering, even with mixed acceptance.
  let members : Array[@ast.TsType] = [
    @ast.TsType::Literal("a"),
    @ast.TsType::Literal("b"),
  ]
  match tagged_union_cases(members) {
    Some(_) => fail("pure literals must still go to enum_lowering")
    None => ()
  }
}

///|
test "tagged union: literal sharing primitive type with non-literal is rejected" {
  // `string | "x"` has overlapping discriminators (both pass typeof === "string").
  let members : Array[@ast.TsType] = [
    @ast.TsType::String_,
    @ast.TsType::Literal("x"),
  ]
  match tagged_union_cases(members) {
    Some(_) =>
      fail("literal whose primitive overlaps a non-literal must be rejected")
    None => ()
  }
}

///|
test "tagged union: literal case discriminator uses strict equality" {
  match tagged_union_case_discriminator(@ast.TsType::Literal("boundary")) {
    Some(StrictEqualsString(value)) => assert_eq(value, "boundary")
    _ => fail("expected StrictEqualsString discriminator")
  }
}

///|
test "tagged union: literal case is no-payload" {
  assert_true(tagged_union_case_is_no_payload(@ast.TsType::Literal("boundary")))
  assert_true(tagged_union_case_is_no_payload(@ast.TsType::NumberLiteral("42")))
  assert_true(
    tagged_union_case_is_no_payload(@ast.TsType::BooleanLiteral(true)),
  )
  assert_false(tagged_union_case_is_no_payload(@ast.TsType::Boolean))
}

///|
test "tagged union decl: mixed primitive + literal renders no-payload case" {
  let decl : BridgeTaggedUnionDecl = {
    name: "Hires",
    cases: [
      ("BoolValue", @ast.TsType::Boolean),
      ("Boundary", @ast.TsType::Literal("boundary")),
    ],
  }
  match tagged_union_decl_to_moonbit_section(decl) {
    Some(section) => {
      assert_true(section.contains("BoolValue(Bool)"))
      // No-payload literal case must omit parentheses.
      assert_true(section.contains("\n  Boundary\n"))
    }
    None => fail("decl section should render with no-payload literal case")
  }
}

///|
test "tagged union to-js: literal case emits literal value" {
  let decl : BridgeTaggedUnionDecl = {
    name: "Hires",
    cases: [
      ("BoolValue", @ast.TsType::Boolean),
      ("Boundary", @ast.TsType::Literal("boundary")),
    ],
  }
  let snippet = tagged_union_to_js_expression(decl, "x")
  assert_true(snippet.contains("\"boundary\""))
  // Literal case payload must NOT read `_0`; only the boolean case does.
  assert_true(snippet.contains("x.$tag === 1"))
}

///|
test "tagged union from-js: literal case uses strict equality" {
  let decl : BridgeTaggedUnionDecl = {
    name: "Hires",
    cases: [
      ("BoolValue", @ast.TsType::Boolean),
      ("Boundary", @ast.TsType::Literal("boundary")),
    ],
  }
  match tagged_union_from_js_expression(decl, "v") {
    Some(snippet) => {
      assert_true(snippet.contains("typeof v === \"boolean\""))
      assert_true(snippet.contains("v === \"boundary\""))
      // No-payload literal case must produce { "$tag": i } without `_0`.
      assert_true(snippet.contains("{ \"$tag\": 1 }"))
    }
    None => fail("from_js should produce predicates for mixed boolean+literal")
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
test "tagged union diagnostic: primitive overlap with literal" {
  let type_alias : @ast.TsTypeAlias = {
    name: "Bad",
    type_params: [],
    type_param_bounds: [],
    type_: @ast.TsType::Union([@ast.TsType::String_, @ast.TsType::Literal("x")]),
  }
  match tagged_union_widen_reason_for_alias(type_alias) {
    Some(reason) => assert_true(reason.contains("overlap"))
    None => fail("expected diagnostic for primitive-overlap rejection")
  }
}

///|
test "tagged union diagnostic: duplicate constructor names" {
  let type_alias : @ast.TsTypeAlias = {
    name: "DupNames",
    type_params: [],
    type_param_bounds: [],
    type_: @ast.TsType::Union([@ast.TsType::Number, @ast.TsType::Number]),
  }
  match tagged_union_widen_reason_for_alias(type_alias) {
    Some(reason) => assert_true(reason.contains("duplicate"))
    None => fail("expected diagnostic for duplicate-name rejection")
  }
}

///|
test "tagged union diagnostic: non-PascalCase member" {
  let type_alias : @ast.TsTypeAlias = {
    name: "Mixed",
    type_params: [],
    type_param_bounds: [],
    type_: @ast.TsType::Union([
      @ast.TsType::Number,
      @ast.TsType::Named("camelCaseType"),
    ]),
  }
  match tagged_union_widen_reason_for_alias(type_alias) {
    Some(reason) => assert_true(reason.contains("runtime-discriminable"))
    None => fail("expected diagnostic for non-discriminable member")
  }
}

///|
test "tagged union diagnostic: pure literal returns no reason (handled by enum_lowering)" {
  let type_alias : @ast.TsTypeAlias = {
    name: "Pure",
    type_params: [],
    type_param_bounds: [],
    type_: @ast.TsType::Union([
      @ast.TsType::Literal("a"),
      @ast.TsType::Literal("b"),
    ]),
  }
  match tagged_union_widen_reason_for_alias(type_alias) {
    Some(_) => fail("pure-literal alias must defer silently to enum_lowering")
    None => ()
  }
}

///|
test "tagged union diagnostic: accepted alias returns no reason" {
  let type_alias : @ast.TsTypeAlias = {
    name: "OK",
    type_params: [],
    type_param_bounds: [],
    type_: @ast.TsType::Union([
      @ast.TsType::Number,
      @ast.TsType::String_,
      @ast.TsType::Named("Date"),
    ]),
  }
  match tagged_union_widen_reason_for_alias(type_alias) {
    Some(_) => fail("accepted alias must not produce a widen reason")
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
test "tagged union alias: type Hires = boolean | \"boundary\" lowers" {
  // magic-string `hires` style alias: a primitive plus a string literal that
  // does not overlap any non-literal sibling.
  let type_alias : @ast.TsTypeAlias = {
    name: "Hires",
    type_params: [],
    type_param_bounds: [],
    type_: @ast.TsType::Union([
      @ast.TsType::Boolean,
      @ast.TsType::Literal("boundary"),
    ]),
  }
  match tagged_union_type_alias_decl(type_alias) {
    Some(decl) => {
      assert_eq(decl.name, "Hires")
      assert_eq(decl.cases.length(), 2)
      assert_eq(decl.cases[0].0, "BoolValue")
      assert_eq(decl.cases[1].0, "Boundary")
    }
    None => fail("expected boolean | \"boundary\" alias to lower")
  }
}

///|
test "tagged union alias: numeric literal mixed with string lowers" {
  // `string | 0` keeps the numeric literal as a no-payload case while the
  // string side discriminates by typeof.
  let type_alias : @ast.TsTypeAlias = {
    name: "PathOrZero",
    type_params: [],
    type_param_bounds: [],
    type_: @ast.TsType::Union([
      @ast.TsType::String_,
      @ast.TsType::NumberLiteral("0"),
    ]),
  }
  match tagged_union_type_alias_decl(type_alias) {
    Some(decl) => {
      assert_eq(decl.cases.length(), 2)
      assert_eq(decl.cases[1].0, "Lit0")
    }
    None => fail("expected string | 0 alias to lower")
  }
}

///|
test "tagged union: bridge.js converter pair works for mixed primitive + literal" {
  let decl : BridgeTaggedUnionDecl = {
    name: "Hires",
    cases: [
      ("BoolValue", @ast.TsType::Boolean),
      ("Boundary", @ast.TsType::Literal("boundary")),
    ],
  }
  match tagged_union_bridge_js_converter_decls(decl) {
    Some(snippet) => {
      assert_true(snippet.contains("__ts_mbt_tagged_union_hires_to_js"))
      assert_true(snippet.contains("__ts_mbt_tagged_union_hires_from_js"))
      assert_true(snippet.contains("\"boundary\""))
      assert_true(snippet.contains("typeof value === \"boolean\""))
    }
    None =>
      fail("converter pair should be available for mixed boolean+literal alias")
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
