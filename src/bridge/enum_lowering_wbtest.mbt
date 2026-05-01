///|
test "bridge: enum lowering builds enum declarations from literal aliases" {
  let string_alias : @ast.TsTypeAlias = {
    name: "ButtonVariant",
    type_params: [],
    type_: @ast.TsType::Union([
      @ast.TsType::Literal("primary"),
      @ast.TsType::Literal("secondary"),
    ]),
  }
  match enum_lowering_type_alias_enum_decl(string_alias) {
    Some(enum_) => {
      assert_eq(enum_.name, "ButtonVariant")
      assert_eq(enum_.members.length(), 2)
      assert_eq(
        enum_.members[0].value,
        Some(@ast.TsEnumMemberValue::String("primary")),
      )
    }
    None => fail("expected string literal alias to lower to enum")
  }
  let number_alias : @ast.TsTypeAlias = {
    name: "StatusCode",
    type_params: [],
    type_: @ast.TsType::Union([
      @ast.TsType::NumberLiteral("200"),
      @ast.TsType::NumberLiteral("404"),
    ]),
  }
  match enum_lowering_type_alias_enum_decl(number_alias) {
    Some(enum_) => {
      assert_eq(enum_.name, "StatusCode")
      assert_eq(enum_.members[0].name, "N200")
      assert_eq(
        enum_.members[1].value,
        Some(@ast.TsEnumMemberValue::Number("404")),
      )
    }
    None => fail("expected numeric literal alias to lower to enum")
  }
}
