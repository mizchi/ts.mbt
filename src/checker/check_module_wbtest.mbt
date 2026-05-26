///|
fn empty_module_for_check() -> @ast.TsModule {
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
  }
}

///|
fn iface_for_check(
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
  }
}

///|
fn alias_for_check(
  name : String,
  type_params : Array[String],
  body : @ast.TsType,
) -> @ast.TsTypeAlias {
  { name, type_params, type_param_bounds: [], type_: body }
}

///|
test "TypeCheckReport: is_clean / of_kind / count_of_kind" {
  let m = empty_module_for_check()
  m.interfaces.push(iface_for_check("Foo", [("x", Named("Bar"))]))
  m.type_aliases.push(alias_for_check("Loop", [], Named("Loop")))
  let report = check_module(m)
  assert_false(report.is_clean())
  assert_eq(report.count_of_kind(UnresolvedReference), 1)
  assert_eq(report.count_of_kind(CircularTypeAlias), 1)
  assert_eq(report.count_of_kind(DuplicateDeclaration), 0)
  assert_eq(report.of_kind(UnresolvedReference)[0].name, "Bar")
  assert_eq(report.of_kind(CircularTypeAlias)[0].name, "Loop")
}

///|
test "TypeCheckReport: is_clean on empty report" {
  let m = empty_module_for_check()
  let report = check_module(m)
  assert_true(report.is_clean())
}

///|
test "check_module: clean module produces empty report" {
  let m = empty_module_for_check()
  m.interfaces.push(iface_for_check("Foo", [("x", String_)]))
  let report = check_module(m)
  assert_eq(report.issues.length(), 0)
}

///|
test "check_module: surfaces unresolved references" {
  let m = empty_module_for_check()
  m.interfaces.push(iface_for_check("Foo", [("x", Named("Bar"))]))
  let report = check_module(m)
  assert_eq(report.issues.length(), 1)
  let i = report.issues[0]
  assert_true(i.kind == UnresolvedReference)
  assert_eq(i.name, "Bar")
}

///|
test "check_module: surfaces duplicate declarations across kinds" {
  let m = empty_module_for_check()
  m.interfaces.push(iface_for_check("Foo", []))
  m.type_aliases.push(alias_for_check("Foo", [], String_))
  let report = check_module(m)
  assert_eq(report.issues.length(), 1)
  let i = report.issues[0]
  assert_true(i.kind == DuplicateDeclaration)
  assert_eq(i.name, "Foo")
}

///|
test "check_module: detects self-referential type alias cycle" {
  let m = empty_module_for_check()
  // type Loop = Loop;
  m.type_aliases.push(alias_for_check("Loop", [], Named("Loop")))
  let report = check_module(m)
  assert_eq(report.issues.length(), 1)
  let i = report.issues[0]
  assert_true(i.kind == CircularTypeAlias)
  assert_eq(i.name, "Loop")
}

///|
test "check_module: detects multi-step alias cycle" {
  let m = empty_module_for_check()
  // type A = B; type B = A;
  m.type_aliases.push(alias_for_check("A", [], Named("B")))
  m.type_aliases.push(alias_for_check("B", [], Named("A")))
  let report = check_module(m)
  // Both names are part of the cycle; expect two reports.
  let cycles = report.issues.filter(fn(i) { i.kind == CircularTypeAlias })
  assert_eq(cycles.length(), 2)
}

///|
test "check_module: alias chain that terminates is fine" {
  let m = empty_module_for_check()
  // type A = B; type B = string;
  m.type_aliases.push(alias_for_check("A", [], Named("B")))
  m.type_aliases.push(alias_for_check("B", [], String_))
  let report = check_module(m)
  assert_eq(report.issues.length(), 0)
}

///|
test "check_module: detects duplicate class instance properties" {
  let m = empty_module_for_check()
  m.classes.push({
    name: "Counter",
    type_params: [],
    base_names: [],
    base_expr: None,
    static_field_inits: [],
    constructor_params: None,
    properties: [
      { name: "value", type_: Number, is_static: false, is_readonly: false, is_accessor: false },
      { name: "value", type_: String_, is_static: false, is_readonly: false, is_accessor: false },
    ],
    methods: [],
    is_abstract: false,
    is_constructible: true,
    index_signatures: [],
    decorators: [],
  })
  let report = check_module(m)
  let dups = report.issues.filter(fn(i) { i.kind == ClassPropertyDuplicate })
  assert_eq(dups.length(), 1)
  assert_eq(dups[0].name, "Counter.value")
}

///|
test "check_module: instance and static with same name is OK" {
  let m = empty_module_for_check()
  m.classes.push({
    name: "Counter",
    type_params: [],
    base_names: [],
    base_expr: None,
    static_field_inits: [],
    constructor_params: None,
    properties: [
      { name: "value", type_: Number, is_static: false, is_readonly: false, is_accessor: false },
      { name: "value", type_: Number, is_static: true, is_readonly: false, is_accessor: false },
    ],
    methods: [],
    is_abstract: false,
    is_constructible: true,
    index_signatures: [],
    decorators: [],
  })
  let report = check_module(m)
  let dups = report.issues.filter(fn(i) { i.kind == ClassPropertyDuplicate })
  assert_eq(dups.length(), 0)
}

///|
test "check_module: detects duplicate enum members" {
  let m = empty_module_for_check()
  m.enums.push({
    name: "Mode",
    is_const: false,
    is_declare: false,
    members: [
      { name: "Read", value: None, is_computed: false },
      { name: "Write", value: None, is_computed: false },
      { name: "Read", value: None, is_computed: false },
    ],
  })
  let report = check_module(m)
  let dups = report.issues.filter(fn(i) { i.kind == EnumMemberDuplicate })
  assert_eq(dups.length(), 1)
  assert_eq(dups[0].name, "Mode.Read")
}

///|
test "check_module: detects interface extends cycle" {
  let m = empty_module_for_check()
  m.interfaces.push({
    name: "A",
    type_params: [],
    extends_names: ["B"],
    extends_args: [[]],
    fields: [],
    readonly_fields: [],
    index_signatures: [],
  })
  m.interfaces.push({
    name: "B",
    type_params: [],
    extends_names: ["A"],
    extends_args: [[]],
    fields: [],
    readonly_fields: [],
    index_signatures: [],
  })
  let report = check_module(m)
  let cycles = report.issues.filter(fn(i) { i.kind == InterfaceExtendsCycle })
  assert_eq(cycles.length(), 2)
}

///|
test "check_module: terminating extends chain is fine" {
  let m = empty_module_for_check()
  m.interfaces.push({
    name: "Animal",
    type_params: [],
    extends_names: [],
    extends_args: [],
    fields: [],
    readonly_fields: [],
    index_signatures: [],
  })
  m.interfaces.push({
    name: "Dog",
    type_params: [],
    extends_names: ["Animal"],
    extends_args: [[]],
    fields: [],
    readonly_fields: [],
    index_signatures: [],
  })
  let report = check_module(m)
  let cycles = report.issues.filter(fn(i) { i.kind == InterfaceExtendsCycle })
  assert_eq(cycles.length(), 0)
}

///|
test "check_module: detects duplicate interface fields" {
  let m = empty_module_for_check()
  m.interfaces.push(
    iface_for_check("User", [("id", String_), ("name", String_), ("id", Number)]),
  )
  let report = check_module(m)
  let dup_fields = report.issues.filter(fn(i) {
    i.kind == InterfaceFieldDuplicate
  })
  assert_eq(dup_fields.length(), 1)
  assert_eq(dup_fields[0].name, "User.id")
}

///|
test "check_module: distinct interface fields produce no duplicate report" {
  let m = empty_module_for_check()
  m.interfaces.push(
    iface_for_check("User", [("id", String_), ("name", String_)]),
  )
  let report = check_module(m)
  let dup_fields = report.issues.filter(fn(i) {
    i.kind == InterfaceFieldDuplicate
  })
  assert_eq(dup_fields.length(), 0)
}

///|
test "check_module: detects type alias arity mismatch" {
  let m = empty_module_for_check()
  // type Box<T> = { value: T };
  m.type_aliases.push(
    alias_for_check("Box", ["T"], Object([(Literal("value"), Named("T"))])),
  )
  // interface User { box: Box<string, number>; }  // wrong arity
  m.interfaces.push(
    iface_for_check("User", [("box", Applied("Box", [String_, Number]))]),
  )
  let report = check_module(m)
  let arity_issues = report.issues.filter(fn(i) {
    i.kind == TypeAliasArityMismatch
  })
  assert_eq(arity_issues.length(), 1)
  assert_eq(arity_issues[0].name, "Box")
}

///|
test "check_module: matching arity does not surface arity issue" {
  let m = empty_module_for_check()
  m.type_aliases.push(
    alias_for_check("Box", ["T"], Object([(Literal("value"), Named("T"))])),
  )
  m.interfaces.push(
    iface_for_check("User", [("box", Applied("Box", [String_]))]),
  )
  let report = check_module(m)
  let arity_issues = report.issues.filter(fn(i) {
    i.kind == TypeAliasArityMismatch
  })
  assert_eq(arity_issues.length(), 0)
}

///|
test "check_module: arity check ignores generic params in scope" {
  let m = empty_module_for_check()
  // type Wrap<T> = T  // 1-arity
  m.type_aliases.push(alias_for_check("Wrap", ["T"], Named("T")))
  // interface Box<U> { value: Wrap<U>; }  // U is in scope; Wrap<U> is fine.
  m.interfaces.push({
    name: "Box",
    type_params: ["U"],
    extends_names: [],
    extends_args: [],
    fields: [("value", Applied("Wrap", [Named("U")]))],
    readonly_fields: [],
    index_signatures: [],
  })
  let report = check_module(m)
  let arity_issues = report.issues.filter(fn(i) {
    i.kind == TypeAliasArityMismatch
  })
  assert_eq(arity_issues.length(), 0)
}

///|
test "check_module: alias body containing union of named is not a cycle if all terminate" {
  let m = empty_module_for_check()
  // type Maybe<T> = T | undefined;  — generic body referencing param
  m.type_aliases.push(
    alias_for_check("Maybe", ["T"], Union([Named("T"), Undefined])),
  )
  let report = check_module(m)
  assert_eq(report.issues.length(), 0)
}
