///|
fn empty_module() -> @ast.TsModule {
  {
    funcs: [],
    interfaces: [],
    type_aliases: [],
    imports: [],
    values: [],
    classes: [],
    namespaces: [],
    enums: [],
    module_augmentations: [],
    strict_property_initialization: true,
    strict_null_checks: true,
    use_define_for_class_fields: false,
    deprecated_compiler_options: [],
    parameter_property_misuses: [],
    param_optional_initializer_misuses: [],
    class_dup_diagnostics: [],
    top_level_stmts: [],
  }
}

///|
fn iface(
  name : String,
  fields : Array[(String, @ast.TsType)],
) -> @ast.TsInterface {
  {
    name,
    type_params: [],
    extends_names: [],
    extends_args: [],
    fields,
    readonly_fields: [],
    index_signatures: [],
    type_param_bounds: [],
    method_type_params: [],
  }
}

///|
fn ta_(name : String, body : @ast.TsType) -> @ast.TsTypeAlias {
  { name, type_params: [], type_param_bounds: [], type_: body }
}

///|
test "validate_module: clean module has no unresolved references" {
  let mod = empty_module()
  mod.interfaces.push(iface("User", [("id", String_), ("age", Number)]))
  let unresolved = unresolved_type_references(mod)
  assert_eq(unresolved.length(), 0)
}

///|
test "validate_module: surfaces references to undeclared names" {
  let mod = empty_module()
  // interface Box { value: Inner }  but `Inner` is never declared.
  mod.interfaces.push(iface("Box", [("value", Named("Inner"))]))
  let unresolved = unresolved_type_references(mod)
  assert_eq(unresolved.length(), 1)
  assert_eq(unresolved[0], "Inner")
}

///|
test "validate_module: ignores names declared as type aliases or interfaces" {
  let mod = empty_module()
  mod.interfaces.push(iface("Box", [("value", Named("Inner"))]))
  mod.type_aliases.push(ta_("Inner", String_))
  let unresolved = unresolved_type_references(mod)
  assert_eq(unresolved.length(), 0)
}

///|
test "validate_module: ignores enum and class names" {
  let mod = empty_module()
  mod.interfaces.push(iface("Holder", [("c", Named("Color"))]))
  mod.enums.push({
    name: "Color",
    is_const: false,
    is_declare: false,
    members: [],
  })
  let unresolved = unresolved_type_references(mod)
  assert_eq(unresolved.length(), 0)
}

///|
test "validate_module: ignores well-known builtins" {
  let mod = empty_module()
  mod.interfaces.push(
    iface("Holder", [
      ("p", Applied("Promise", [String_])),
      ("rec", Applied("Record", [String_, Number])),
      ("err", Named("Error")),
    ]),
  )
  let unresolved = unresolved_type_references(mod)
  assert_eq(unresolved.length(), 0)
}

///|
test "validate_module: ignores generic parameters in scope" {
  let mod = empty_module()
  mod.interfaces.push({
    name: "Box",
    type_params: ["T"],
    extends_names: [],
    extends_args: [],
    fields: [("value", Named("T"))],
    readonly_fields: [],
    index_signatures: [],
    type_param_bounds: [],
    method_type_params: [],
  })
  let unresolved = unresolved_type_references(mod)
  assert_eq(unresolved.length(), 0)
}

///|
test "validate_module: ignores generic parameters of declared functions" {
  let mod = empty_module()
  // declare function identity<T>(x: T): T -- `T` is in scope, not unresolved.
  mod.imports.push({
    name: "identity",
    module_: "m",
    type_params: ["T"],
    params: [("x", Named("T"))],
    param_is_rest: [],
    return_type: Named("T"),
  })
  let unresolved = unresolved_type_references(mod)
  assert_eq(unresolved.length(), 0)
}

///|
test "validate_module: still surfaces genuinely undeclared function refs" {
  let mod = empty_module()
  // declare function f<T>(x: T): Missing -- `T` resolves, `Missing` does not.
  mod.imports.push({
    name: "f",
    module_: "m",
    type_params: ["T"],
    params: [("x", Named("T"))],
    param_is_rest: [],
    return_type: Named("Missing"),
  })
  let unresolved = unresolved_type_references(mod)
  assert_eq(unresolved.length(), 1)
  assert_eq(unresolved[0], "Missing")
}
