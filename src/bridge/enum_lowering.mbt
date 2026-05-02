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
fn enum_lowering_literal_union_core_with_optionals(
  type_ : @ast.TsType,
) -> (@ast.TsType, Array[@ast.TsType])? {
  match type_ {
    @ast.TsType::Union(items) => {
      let concrete_items : Array[@ast.TsType] = []
      let optional_items : Array[@ast.TsType] = []
      for item in items {
        match item {
          @ast.TsType::Undefined | @ast.TsType::Null =>
            optional_items.push(item)
          @ast.TsType::Literal(_)
          | @ast.TsType::NumberLiteral(_)
          | @ast.TsType::BigIntLiteral(_)
          | @ast.TsType::BooleanLiteral(_) => concrete_items.push(item)
          _ => return None
        }
      }
      if concrete_items.length() == 0 {
        return None
      }
      let core = if concrete_items.length() == 1 {
        concrete_items[0]
      } else {
        @ast.TsType::Union(concrete_items)
      }
      Some((core, optional_items))
    }
    @ast.TsType::Literal(_)
    | @ast.TsType::NumberLiteral(_)
    | @ast.TsType::BigIntLiteral(_)
    | @ast.TsType::BooleanLiteral(_) => Some((type_, []))
    _ => None
  }
}

///|
fn enum_lowering_anonymous_literal_enum_decl(
  name : String,
  type_ : @ast.TsType,
) -> (@ast.TsEnumDecl, @ast.TsType)? {
  match enum_lowering_literal_union_core_with_optionals(type_) {
    Some((core, optional_items)) => {
      let enum_decl = match
        enum_lowering_anonymous_string_literal_enum_decl(name, core) {
        Some(enum_) => Some(enum_)
        None => {
          let type_alias : @ast.TsTypeAlias = {
            name,
            type_params: [],
            type_param_bounds: [],
            type_: core,
          }
          enum_lowering_type_alias_enum_decl(type_alias)
        }
      }
      match enum_decl {
        Some(enum_) => {
          let named = @ast.TsType::Named(name)
          let rewritten = if optional_items.length() == 0 {
            named
          } else {
            let items : Array[@ast.TsType] = [named]
            for item in optional_items {
              items.push(item)
            }
            @ast.TsType::Union(items)
          }
          Some((enum_, rewritten))
        }
        None => None
      }
    }
    None => None
  }
}

///|
fn enum_lowering_anonymous_string_literal_enum_decl(
  name : String,
  type_ : @ast.TsType,
) -> @ast.TsEnumDecl? {
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
        if seen_values.contains(value) {
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
  Some({ name, members, is_const: false, is_declare: true })
}

///|
fn enum_lowering_used_type_key(name : String) -> String {
  ffi_to_snake_case(ffi_type_identifier(name, "GeneratedEnum"))
}

///|
fn enum_lowering_synthetic_enum_name(
  parts : Array[String],
  used_type_names : Array[String],
) -> String {
  let normalized_parts : Array[String] = []
  for part in parts {
    normalized_parts.push(ffi_type_identifier(part, "Value"))
  }
  let base = if normalized_parts.length() == 0 {
    "GeneratedEnum"
  } else {
    normalized_parts.join("")
  }
  let mut candidate = base
  let mut suffix = 2
  while used_type_names.contains(enum_lowering_used_type_key(candidate)) {
    candidate = base + suffix.to_string()
    suffix += 1
  }
  used_type_names.push(enum_lowering_used_type_key(candidate))
  candidate
}

///|
fn enum_lowering_rewrite_direct_anonymous_enum_type(
  type_ : @ast.TsType,
  name_parts : Array[String],
  enums : Array[@ast.TsEnumDecl],
  used_type_names : Array[String],
) -> @ast.TsType {
  let enum_name = enum_lowering_synthetic_enum_name(name_parts, used_type_names)
  match enum_lowering_anonymous_literal_enum_decl(enum_name, type_) {
    Some((enum_, rewritten)) => {
      enums.push(enum_)
      rewritten
    }
    None => {
      let _ = used_type_names.pop()
      type_
    }
  }
}

///|
fn enum_lowering_rewrite_anonymous_enum_type(
  type_ : @ast.TsType,
  name_parts : Array[String],
  enums : Array[@ast.TsEnumDecl],
  used_type_names : Array[String],
) -> @ast.TsType {
  let direct = enum_lowering_rewrite_direct_anonymous_enum_type(
    type_, name_parts, enums, used_type_names,
  )
  if direct != type_ {
    return direct
  }
  match type_ {
    @ast.TsType::Array(inner) =>
      @ast.TsType::Array(
        enum_lowering_rewrite_anonymous_enum_type(
          inner,
          name_parts + ["Item"],
          enums,
          used_type_names,
        ),
      )
    @ast.TsType::Tuple(items) => {
      let rewritten : Array[@ast.TsType] = []
      for i, item in items {
        rewritten.push(
          enum_lowering_rewrite_anonymous_enum_type(
            item,
            name_parts + ["Item" + i.to_string()],
            enums,
            used_type_names,
          ),
        )
      }
      @ast.TsType::Tuple(rewritten)
    }
    @ast.TsType::Union(items) => {
      let rewritten : Array[@ast.TsType] = []
      for i, item in items {
        rewritten.push(
          enum_lowering_rewrite_anonymous_enum_type(
            item,
            name_parts + ["Member" + i.to_string()],
            enums,
            used_type_names,
          ),
        )
      }
      @ast.TsType::Union(rewritten)
    }
    @ast.TsType::Intersection(items) => {
      let rewritten : Array[@ast.TsType] = []
      for i, item in items {
        rewritten.push(
          enum_lowering_rewrite_anonymous_enum_type(
            item,
            name_parts + ["Part" + i.to_string()],
            enums,
            used_type_names,
          ),
        )
      }
      @ast.TsType::Intersection(rewritten)
    }
    @ast.TsType::Object(fields) => {
      let rewritten : Array[(@ast.TsType, @ast.TsType)] = []
      for i, field in fields {
        let (key_type, value_type) = field
        let field_part = match key_type {
          @ast.TsType::Literal(name) => name
          _ => "Field" + i.to_string()
        }
        rewritten.push(
          (
            key_type,
            enum_lowering_rewrite_anonymous_enum_type(
              value_type,
              name_parts + [field_part],
              enums,
              used_type_names,
            ),
          ),
        )
      }
      @ast.TsType::Object(rewritten)
    }
    @ast.TsType::Struct(name, fields) => {
      let rewritten : Array[(String, @ast.TsType)] = []
      for field in fields {
        let (field_name, field_type) = field
        rewritten.push(
          (
            field_name,
            enum_lowering_rewrite_anonymous_enum_type(
              field_type,
              name_parts + [field_name],
              enums,
              used_type_names,
            ),
          ),
        )
      }
      @ast.TsType::Struct(name, rewritten)
    }
    @ast.TsType::Func(params, return_type) => {
      let rewritten_params : Array[@ast.TsType] = []
      for i, param in params {
        rewritten_params.push(
          enum_lowering_rewrite_anonymous_enum_type(
            param,
            name_parts + ["Arg" + i.to_string()],
            enums,
            used_type_names,
          ),
        )
      }
      let rewritten_return = enum_lowering_rewrite_anonymous_enum_type(
        return_type,
        name_parts + ["Return"],
        enums,
        used_type_names,
      )
      @ast.TsType::Func(rewritten_params, rewritten_return)
    }
    @ast.TsType::Applied(name, args) => {
      let rewritten_args : Array[@ast.TsType] = []
      for i, arg in args {
        rewritten_args.push(
          enum_lowering_rewrite_anonymous_enum_type(
            arg,
            name_parts + ["Arg" + i.to_string()],
            enums,
            used_type_names,
          ),
        )
      }
      @ast.TsType::Applied(name, rewritten_args)
    }
    @ast.TsType::Conditional(source, target, true_type, false_type) =>
      @ast.TsType::Conditional(
        enum_lowering_rewrite_anonymous_enum_type(
          source,
          name_parts + ["Source"],
          enums,
          used_type_names,
        ),
        enum_lowering_rewrite_anonymous_enum_type(
          target,
          name_parts + ["Target"],
          enums,
          used_type_names,
        ),
        enum_lowering_rewrite_anonymous_enum_type(
          true_type,
          name_parts + ["True"],
          enums,
          used_type_names,
        ),
        enum_lowering_rewrite_anonymous_enum_type(
          false_type,
          name_parts + ["False"],
          enums,
          used_type_names,
        ),
      )
    _ => type_
  }
}

///|
fn enum_lowering_seed_used_type_names(
  enums : Array[@ast.TsEnumDecl],
  interfaces : Array[@ast.TsInterface],
  classes : Array[@ast.TsClassDecl],
) -> Array[String] {
  let used_type_names : Array[String] = []
  for enum_ in enums {
    used_type_names.push(enum_lowering_used_type_key(enum_.name))
  }
  for iface in interfaces {
    used_type_names.push(enum_lowering_used_type_key(iface.name))
  }
  for class_ in classes {
    used_type_names.push(enum_lowering_used_type_key(class_.name))
  }
  used_type_names
}

///|
fn enum_lowering_rewrite_anonymous_enum_surfaces(
  enums : Array[@ast.TsEnumDecl],
  interfaces : Array[@ast.TsInterface],
  imports : Array[@ast.TsImport],
  funcs : Array[@ast.TsFunc],
  values : Array[@ast.TsValueDecl],
  classes : Array[@ast.TsClassDecl],
) -> Unit {
  let used_type_names = enum_lowering_seed_used_type_names(
    enums, interfaces, classes,
  )
  for i, iface in interfaces {
    let fields : Array[(String, @ast.TsType)] = []
    for field in iface.fields {
      let (field_name, field_type) = field
      fields.push(
        (
          field_name,
          enum_lowering_rewrite_anonymous_enum_type(
            field_type,
            [iface.name, field_name],
            enums,
            used_type_names,
          ),
        ),
      )
    }
    interfaces[i] = { ..iface, fields, }
  }
  for i, import_ in imports {
    let params : Array[(String, @ast.TsType)] = []
    for param_index, param in import_.params {
      let (param_name, param_type) = param
      let name_part = if param_name == "" {
        "arg" + param_index.to_string()
      } else {
        param_name
      }
      params.push(
        (
          param_name,
          enum_lowering_rewrite_anonymous_enum_type(
            param_type,
            [import_.name, name_part],
            enums,
            used_type_names,
          ),
        ),
      )
    }
    let return_type = enum_lowering_rewrite_anonymous_enum_type(
      import_.return_type,
      [import_.name, "Return"],
      enums,
      used_type_names,
    )
    imports[i] = { ..import_, params, return_type }
  }
  for i, func in funcs {
    let params : Array[@ast.TsParam] = []
    for param_index, param in func.params {
      let name_part = if param.name == "" {
        "arg" + param_index.to_string()
      } else {
        param.name
      }
      params.push({
        ..param,
        type_: enum_lowering_rewrite_anonymous_enum_type(
          param.type_,
          [func.name, name_part],
          enums,
          used_type_names,
        ),
      })
    }
    let return_type = enum_lowering_rewrite_anonymous_enum_type(
      func.return_type,
      [func.name, "Return"],
      enums,
      used_type_names,
    )
    funcs[i] = { ..func, params, return_type }
  }
  for i, value in values {
    values[i] = {
      ..value,
      type_: enum_lowering_rewrite_anonymous_enum_type(
        value.type_,
        [value.name, "Value"],
        enums,
        used_type_names,
      ),
    }
  }
  for i, class_ in classes {
    let constructor_params = match class_.constructor_params {
      Some(params) => {
        let next_params : Array[(String, @ast.TsType)] = []
        for param_index, param in params {
          let (param_name, param_type) = param
          let name_part = if param_name == "" {
            "arg" + param_index.to_string()
          } else {
            param_name
          }
          next_params.push(
            (
              param_name,
              enum_lowering_rewrite_anonymous_enum_type(
                param_type,
                [class_.name, "constructor", name_part],
                enums,
                used_type_names,
              ),
            ),
          )
        }
        Some(next_params)
      }
      None => None
    }
    let properties : Array[@ast.TsClassPropertyDecl] = []
    for property in class_.properties {
      properties.push({
        ..property,
        type_: enum_lowering_rewrite_anonymous_enum_type(
          property.type_,
          [class_.name, property.name],
          enums,
          used_type_names,
        ),
      })
    }
    let methods : Array[@ast.TsClassMethodDecl] = []
    for class_method in class_.methods {
      let params : Array[(String, @ast.TsType)] = []
      for param_index, param in class_method.params {
        let (param_name, param_type) = param
        let name_part = if param_name == "" {
          "arg" + param_index.to_string()
        } else {
          param_name
        }
        params.push(
          (
            param_name,
            enum_lowering_rewrite_anonymous_enum_type(
              param_type,
              [class_.name, class_method.name, name_part],
              enums,
              used_type_names,
            ),
          ),
        )
      }
      let return_type = enum_lowering_rewrite_anonymous_enum_type(
        class_method.return_type,
        [class_.name, class_method.name, "Return"],
        enums,
        used_type_names,
      )
      methods.push({ ..class_method, params, return_type })
    }
    classes[i] = { ..class_, constructor_params, properties, methods }
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
