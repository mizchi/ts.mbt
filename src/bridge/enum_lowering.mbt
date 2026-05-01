///|
fn enum_lowering_case_names(
  enum_ : @ast.TsEnumDecl,
) -> Array[(String, @ast.TsEnumMember)] {
  let cases : Array[(String, @ast.TsEnumMember)] = []
  let seen_cases : Array[String] = []
  for i, enum_member in enum_.members {
    let base_name = ffi_type_identifier(enum_member.name, "Member")
    let mut case_name = base_name
    let mut suffix = 2
    while seen_cases.contains(case_name) {
      case_name = base_name + suffix.to_string()
      suffix += 1
    }
    if case_name == "" {
      case_name = "Member" + i.to_string()
    }
    seen_cases.push(case_name)
    cases.push((case_name, enum_member))
  }
  cases
}

///|
fn enum_lowering_string_cases(
  enum_ : @ast.TsEnumDecl,
) -> Array[(String, String)]? {
  let cases : Array[(String, String)] = []
  let seen_values : Array[String] = []
  for item in enum_lowering_case_names(enum_) {
    let (case_name, enum_member) = item
    if enum_member.is_computed {
      return None
    }
    match enum_member.value {
      Some(@ast.TsEnumMemberValue::String(value)) => {
        if seen_values.contains(value) {
          return None
        }
        seen_values.push(value)
        cases.push((case_name, value))
      }
      _ => return None
    }
  }
  if cases.length() == 0 {
    None
  } else {
    Some(cases)
  }
}

///|
fn enum_lowering_int_cases(enum_ : @ast.TsEnumDecl) -> Array[(String, Int)]? {
  let cases : Array[(String, Int)] = []
  let seen_values : Array[Int] = []
  let mut next_value = 0
  for item in enum_lowering_case_names(enum_) {
    let (case_name, enum_member) = item
    if enum_member.is_computed {
      return None
    }
    let value = match enum_member.value {
      Some(@ast.TsEnumMemberValue::Number(raw)) => {
        let parsed = @string.parse_int(raw) catch { _ => return None }
        parsed
      }
      None => next_value
      _ => return None
    }
    if seen_values.contains(value) {
      return None
    }
    seen_values.push(value)
    cases.push((case_name, value))
    next_value = value + 1
  }
  if cases.length() == 0 {
    None
  } else {
    Some(cases)
  }
}

///|
fn enum_lowering_literal_alias_value_looks_numeric(value : String) -> Bool {
  if value == "" {
    return false
  }
  let first = value[0].unsafe_to_char()
  if first >= '0' && first <= '9' {
    return true
  }
  if first == '-' && value.length() > 1 {
    let next = value[1].unsafe_to_char()
    return next >= '0' && next <= '9'
  }
  false
}

///|
fn enum_lowering_literal_alias_is_safe_string_value(value : String) -> Bool {
  match value {
    "true" | "false" => false
    _ => !enum_lowering_literal_alias_value_looks_numeric(value)
  }
}

///|
fn enum_lowering_type_alias_string_enum_members(
  type_ : @ast.TsType,
) -> Array[@ast.TsEnumMember]? {
  let items = match type_ {
    @ast.TsType::Union(items) => items
    @ast.TsType::Literal(_) => [type_]
    _ => return None
  }
  if items.length() == 0 {
    return None
  }
  let members : Array[@ast.TsEnumMember] = []
  let seen_values : Array[String] = []
  for item in items {
    match item {
      @ast.TsType::Literal(value) => {
        if !enum_lowering_literal_alias_is_safe_string_value(value) ||
          seen_values.contains(value) {
          return None
        }
        seen_values.push(value)
        members.push({
          name: value,
          value: Some(@ast.TsEnumMemberValue::String(value)),
          is_computed: false,
        })
      }
      _ => return None
    }
  }
  Some(members)
}

///|
fn enum_lowering_type_alias_string_enum_decl(
  type_alias : @ast.TsTypeAlias,
) -> @ast.TsEnumDecl? {
  if type_alias.type_params.length() > 0 {
    return None
  }
  match enum_lowering_type_alias_string_enum_members(type_alias.type_) {
    Some(members) =>
      Some({ name: type_alias.name, members, is_const: false, is_declare: true })
    None => None
  }
}

///|
fn enum_lowering_type_alias_number_enum_member_name(value : Int) -> String {
  if value < 0 {
    "Negative" + (0 - value).to_string()
  } else {
    "N" + value.to_string()
  }
}

///|
fn enum_lowering_type_alias_number_enum_members(
  type_ : @ast.TsType,
) -> Array[@ast.TsEnumMember]? {
  let items = match type_ {
    @ast.TsType::Union(items) => items
    @ast.TsType::NumberLiteral(_) => [type_]
    _ => return None
  }
  if items.length() == 0 {
    return None
  }
  let members : Array[@ast.TsEnumMember] = []
  let seen_values : Array[Int] = []
  for item in items {
    match item {
      @ast.TsType::NumberLiteral(raw) => {
        let value = @string.parse_int(raw) catch { _ => return None }
        if seen_values.contains(value) {
          return None
        }
        seen_values.push(value)
        members.push({
          name: enum_lowering_type_alias_number_enum_member_name(value),
          value: Some(@ast.TsEnumMemberValue::Number(value.to_string())),
          is_computed: false,
        })
      }
      _ => return None
    }
  }
  Some(members)
}

///|
fn enum_lowering_type_alias_number_enum_decl(
  type_alias : @ast.TsTypeAlias,
) -> @ast.TsEnumDecl? {
  if type_alias.type_params.length() > 0 {
    return None
  }
  match enum_lowering_type_alias_number_enum_members(type_alias.type_) {
    Some(members) =>
      Some({ name: type_alias.name, members, is_const: false, is_declare: true })
    None => None
  }
}

///|
fn enum_lowering_type_alias_enum_decl(
  type_alias : @ast.TsTypeAlias,
) -> @ast.TsEnumDecl? {
  match enum_lowering_type_alias_string_enum_decl(type_alias) {
    Some(enum_) => Some(enum_)
    None => enum_lowering_type_alias_number_enum_decl(type_alias)
  }
}

///|
fn enum_lowering_type_alias_boolean_literal_primitive_type(
  type_alias : @ast.TsTypeAlias,
) -> @ast.TsType? {
  if type_alias.type_params.length() > 0 {
    return None
  }
  let items = match type_alias.type_ {
    @ast.TsType::Union(items) => items
    @ast.TsType::BooleanLiteral(_) => [type_alias.type_]
    _ => return None
  }
  if items.length() == 0 {
    return None
  }
  let mut has_boolean_literal = false
  for item in items {
    match item {
      @ast.TsType::BooleanLiteral(_) => has_boolean_literal = true
      @ast.TsType::Undefined | @ast.TsType::Null => ()
      _ => return None
    }
  }
  if has_boolean_literal {
    Some(type_alias.type_)
  } else {
    None
  }
}

///|
fn enum_lowering_type_alias_enum_like_unsupported_reason(
  type_alias : @ast.TsTypeAlias,
) -> String? {
  if type_alias.type_params.length() > 0 {
    return None
  }
  if enum_lowering_type_alias_enum_decl(type_alias) is Some(_) ||
    enum_lowering_type_alias_boolean_literal_primitive_type(type_alias)
    is Some(_) {
    return None
  }
  let items = match type_alias.type_ {
    @ast.TsType::Union(items) => items
    @ast.TsType::Literal(_)
    | @ast.TsType::NumberLiteral(_)
    | @ast.TsType::BigIntLiteral(_)
    | @ast.TsType::BooleanLiteral(_) => [type_alias.type_]
    _ => return None
  }
  let mut has_string = false
  let mut has_number = false
  let mut has_bigint = false
  let mut has_bool = false
  let seen_string_values : Array[String] = []
  let seen_number_values : Array[Int] = []
  for item in items {
    match item {
      @ast.TsType::Literal(value) => {
        has_string = true
        if seen_string_values.contains(value) {
          return Some(
            "duplicate literal union values cannot be converted back safely.",
          )
        }
        seen_string_values.push(value)
      }
      @ast.TsType::NumberLiteral(raw) => {
        has_number = true
        let value = @string.parse_int(raw) catch {
          _ =>
            return Some("numeric literal union contains a non-integer literal.")
        }
        if seen_number_values.contains(value) {
          return Some(
            "duplicate literal union values cannot be converted back safely.",
          )
        }
        seen_number_values.push(value)
      }
      @ast.TsType::BigIntLiteral(_) => has_bigint = true
      @ast.TsType::BooleanLiteral(_) => has_bool = true
      @ast.TsType::Undefined | @ast.TsType::Null => ()
      _ => return None
    }
  }
  if has_bigint {
    return Some("bigint literal union cannot be lowered safely.")
  }
  if has_string && has_number {
    return Some("mixed string/number literal union cannot be lowered safely.")
  }
  if has_bool && (has_string || has_number) {
    return Some(
      "mixed boolean/string/number literal union cannot be lowered safely.",
    )
  }
  None
}

///|
fn enum_lowering_unsupported_reason(enum_ : @ast.TsEnumDecl) -> String? {
  if enum_lowering_string_cases(enum_) is Some(_) ||
    enum_lowering_int_cases(enum_) is Some(_) {
    return None
  }
  let seen_string_values : Array[String] = []
  let seen_number_values : Array[Int] = []
  let mut has_string = false
  let mut has_number = false
  let mut has_bigint = false
  let mut has_bool = false
  let mut has_implicit = false
  for enum_member in enum_.members {
    if enum_member.is_computed {
      return Some(
        "enum member \{enum_member.name} has a non-literal computed value.",
      )
    }
    match enum_member.value {
      Some(@ast.TsEnumMemberValue::String(value)) => {
        has_string = true
        if seen_string_values.contains(value) {
          return Some(
            "duplicate enum literal values cannot be converted back safely.",
          )
        }
        seen_string_values.push(value)
      }
      Some(@ast.TsEnumMemberValue::Number(raw)) => {
        has_number = true
        let value = @string.parse_int(raw) catch {
          _ => return Some("numeric enum contains a non-integer literal.")
        }
        if seen_number_values.contains(value) {
          return Some(
            "duplicate enum literal values cannot be converted back safely.",
          )
        }
        seen_number_values.push(value)
      }
      Some(@ast.TsEnumMemberValue::BigInt(_)) => has_bigint = true
      Some(@ast.TsEnumMemberValue::Bool(_)) => has_bool = true
      None => has_implicit = true
    }
  }
  if has_string && has_number {
    return Some("mixed string/number enum cannot be lowered safely.")
  }
  if has_string && has_implicit {
    return Some(
      "string enum contains an implicit member without a literal value.",
    )
  }
  if has_bigint || has_bool {
    return Some("enum initializer kind is not supported for bridge lowering.")
  }
  Some("enum cannot be lowered safely.")
}
