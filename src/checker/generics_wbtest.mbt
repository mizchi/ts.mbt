///|
fn make_generic_resolver(
  table : Map[String, AliasBinding],
) -> (String) -> AliasBinding? {
  fn(name) { table.get(name) }
}

///|
test "is_assignable_to_with_generics: substitutes type params on Applied" {
  // type Maybe<X> = X | undefined;
  let table : Map[String, AliasBinding] = {
    "Maybe": { type_params: ["X"], body: Union([Named("X"), Undefined]) },
  }
  let resolve = make_generic_resolver(table)
  // String is assignable to Maybe<string>
  assert_true(
    is_assignable_to_with_generics(
      String_,
      Applied("Maybe", [String_]),
      resolve,
    ),
  )
  // Undefined is assignable to Maybe<string>
  assert_true(
    is_assignable_to_with_generics(
      Undefined,
      Applied("Maybe", [String_]),
      resolve,
    ),
  )
  // Number is NOT assignable to Maybe<string>
  assert_false(
    is_assignable_to_with_generics(Number, Applied("Maybe", [String_]), resolve),
  )
}

///|
test "is_assignable_to_with_generics: chain through generic alias" {
  // type Wrap<X> = Box<X>;
  // type Box<Y> = { value: Y };
  let table : Map[String, AliasBinding] = {
    "Wrap": { type_params: ["X"], body: Applied("Box", [Named("X")]) },
    "Box": {
      type_params: ["Y"],
      body: Object([(Literal("value"), Named("Y"))]),
    },
  }
  let resolve = make_generic_resolver(table)
  // Wrap<string> ⇒ Box<string> ⇒ { value: string }
  assert_true(
    is_assignable_to_with_generics(
      Object([(Literal("value"), String_)]),
      Applied("Wrap", [String_]),
      resolve,
    ),
  )
}

///|
test "is_assignable_to_with_generics: Named without params resolves like type alias" {
  // type ID = string;
  let table : Map[String, AliasBinding] = {
    "ID": { type_params: [], body: String_ },
  }
  let resolve = make_generic_resolver(table)
  assert_true(is_assignable_to_with_generics(Named("ID"), String_, resolve))
}

///|
test "is_assignable_to_with_generics: arity mismatch leaves Applied opaque" {
  // type Maybe<X> = X | undefined; — but caller passes Applied("Maybe", []).
  let table : Map[String, AliasBinding] = {
    "Maybe": { type_params: ["X"], body: Union([Named("X"), Undefined]) },
  }
  let resolve = make_generic_resolver(table)
  // 0 args — substitution cannot proceed; falls back to nominal Applied match.
  assert_false(
    is_assignable_to_with_generics(String_, Applied("Maybe", []), resolve),
  )
}

///|
test "module_alias_resolver: combines parsed aliases with stdlib utilities" {
  let m : @ast.TsModule = {
    funcs: [],
    interfaces: [],
    type_aliases: [
      {
        name: "Maybe",
        type_params: ["X"],
        type_param_bounds: [],
        type_: Union([Named("X"), Undefined]),
      },
    ],
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
    top_level_stmts: [],
  }
  let resolve = module_alias_resolver(m)
  // Module-defined alias resolves.
  assert_true(
    is_assignable_to_with_generics(
      String_,
      Applied("Maybe", [String_]),
      resolve,
    ),
  )
  // Standard library alias also resolves (NonNullable strips null/undefined).
  assert_true(
    is_assignable_to_with_generics(
      String_,
      Applied("NonNullable", [Union([String_, Null])]),
      resolve,
    ),
  )
}

///|
test "module_alias_resolver: include_standard=false omits stdlib" {
  let m : @ast.TsModule = {
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
    top_level_stmts: [],
  }
  let resolve = module_alias_resolver(m, include_standard=false)
  // NonNullable not in scope → stays nominal Applied. Number is not assignable
  // to the opaque Applied form.
  assert_false(
    is_assignable_to_with_generics(
      Number,
      Applied("NonNullable", [Number]),
      resolve,
    ),
  )
}

///|
test "module_alias_resolver: module aliases shadow stdlib on name clash" {
  let m : @ast.TsModule = {
    funcs: [],
    interfaces: [],
    // Override `NonNullable` to mean `string` for this module — a contrived
    // example, but pins the shadowing rule.
    type_aliases: [
      {
        name: "NonNullable",
        type_params: ["T"],
        type_param_bounds: [],
        type_: String_,
      },
    ],
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
    top_level_stmts: [],
  }
  let resolve = module_alias_resolver(m)
  // Per the override, NonNullable<anything> ≡ string.
  assert_true(
    is_assignable_to_with_generics(
      String_,
      Applied("NonNullable", [Number]),
      resolve,
    ),
  )
}

///|
test "is_assignable_to_with_generics: distributes conditional over union arg" {
  // type ToArray<T> = T extends any ? T[] : never;
  // ToArray<string | number> should produce string[] | number[].
  let table : Map[String, AliasBinding] = {
    "ToArray": {
      type_params: ["T"],
      body: Conditional(Named("T"), Any, Array(Named("T")), Never),
    },
  }
  let resolve = make_generic_resolver(table)
  // Array(string) is one branch; should be assignable to the distributed result.
  assert_true(
    is_assignable_to_with_generics(
      Array(String_),
      Applied("ToArray", [Union([String_, Number])]),
      resolve,
    ),
  )
  assert_true(
    is_assignable_to_with_generics(
      Array(Number),
      Applied("ToArray", [Union([String_, Number])]),
      resolve,
    ),
  )
  // Array(boolean) is NOT in the distributed union.
  assert_false(
    is_assignable_to_with_generics(
      Array(Boolean),
      Applied("ToArray", [Union([String_, Number])]),
      resolve,
    ),
  )
}

///|
test "is_assignable_to_with_generics: distribution diverges per branch" {
  // type Wrap<T> = T extends string ? Array<T> : Set<T>;
  // Wrap<string | number> with distribution ⇒ Array<string> | Set<number>
  // Without distribution: extends fails (number isn't string), pick Set<...>.
  let table : Map[String, AliasBinding] = {
    "Wrap": {
      type_params: ["T"],
      body: Conditional(
        Named("T"),
        String_,
        Applied("Array", [Named("T")]),
        Applied("Set", [Named("T")]),
      ),
    },
  }
  let resolve = make_generic_resolver(table)
  // With distribution, Array<string> is one of the branches.
  assert_true(
    is_assignable_to_with_generics(
      Applied("Array", [String_]),
      Applied("Wrap", [Union([String_, Number])]),
      resolve,
    ),
  )
  // And Set<number> is the other.
  assert_true(
    is_assignable_to_with_generics(
      Applied("Set", [Number]),
      Applied("Wrap", [Union([String_, Number])]),
      resolve,
    ),
  )
}

///|
test "is_assignable_to_with_generics: distribution preserves single-arg behavior" {
  // ToArray<string> should still produce string[] (not distribute over a non-union).
  let table : Map[String, AliasBinding] = {
    "ToArray": {
      type_params: ["T"],
      body: Conditional(Named("T"), Any, Array(Named("T")), Never),
    },
  }
  let resolve = make_generic_resolver(table)
  assert_true(
    is_assignable_to_with_generics(
      Array(String_),
      Applied("ToArray", [String_]),
      resolve,
    ),
  )
  assert_false(
    is_assignable_to_with_generics(
      Array(Number),
      Applied("ToArray", [String_]),
      resolve,
    ),
  )
}

///|
test "is_assignable_to_with_generics: cycle through generics is safe" {
  // type Loop<X> = Loop<X>;
  let table : Map[String, AliasBinding] = {
    "Loop": { type_params: ["X"], body: Applied("Loop", [Named("X")]) },
  }
  let resolve = make_generic_resolver(table)
  // After cycle detection the body collapses to Any — flows freely.
  assert_true(
    is_assignable_to_with_generics(Applied("Loop", [String_]), String_, resolve),
  )
}
