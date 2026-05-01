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
