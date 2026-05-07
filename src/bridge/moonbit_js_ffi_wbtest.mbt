///|
fn count_occurrences_in_ffi_output(haystack : String, needle : String) -> Int {
  let mut count = 0
  for _ in haystack.split(needle) {
    count += 1
  }
  count - 1
}

///|
async test "bridge: emit MoonBit JS FFI bundle for function reexports" {
  let bundle = emit_moonbit_js_ffi_bundle_from_entry_path(
    "fixtures/resolver/project/types/entry.d.ts", "/runtime/mod.js",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(
    bundle.ffi_mbt.contains("#warnings(\"-9\")\npub(all) struct PublicPoint"),
  )
  assert_true(bundle.ffi_mbt.contains("pub(all) struct PublicPoint"))
  assert_true(
    bundle.ffi_mbt.contains(
      "#module(\"/runtime/mod.js\")\npub extern \"js\" fn render(point : PublicPoint) -> PublicPoint = \"draw\"",
    ),
  )
  assert_false(bundle.bridge_js.contains("__ts_mbt_render"))
}

///|
async test "bridge: emit MoonBit JS FFI bundle for namespace exports" {
  let bundle = emit_moonbit_js_ffi_bundle_from_entry_path(
    "fixtures/resolver/project/types/ns-entry.d.ts", "./runtime/ns.js",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(bundle.ffi_mbt.contains("#external\npub type Shapes"))
  assert_eq(count_occurrences_in_ffi_output(bundle.ffi_mbt, "type Shapes"), 1)
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn get_shapes() -> Shapes = \"__ts_mbt_get_shapes\"",
    ),
  )
  assert_true(
    bundle.bridge_js.contains(
      "export function __ts_mbt_get_shapes() { return shapes; }",
    ),
  )
}

///|
async test "bridge: emit MoonBit JS FFI bundle from ambient external module" {
  let bundle = emit_moonbit_js_ffi_bundle_from_entry_path(
    "fixtures/resolver/project/types/ambient-node-sqlite-entry.d.ts", "node:sqlite",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(bundle.ffi_mbt.contains("#external\npub type DatabaseSync"))
  assert_true(bundle.ffi_mbt.contains("#external\npub type StatementSync"))
  assert_true(bundle.ffi_mbt.contains("pub(all) struct DatabaseSyncOptions"))
  assert_true(bundle.ffi_mbt.contains("  open : Bool?"))
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn new_database_sync(path : String, options : DatabaseSyncOptions?) -> DatabaseSync",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn DatabaseSync::exec(self : DatabaseSync, sql : String) -> Unit",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn DatabaseSync::prepare(self : DatabaseSync, sql : String) -> StatementSync",
    ),
  )
  assert_true(bundle.ffi_mbt.contains("#external\npub type SQLInputValue"))
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn sqlinput_value_null() -> SQLInputValue = \"__ts_mbt_sqlinput_value_null\"",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn sqlinput_value_from_string(value : String) -> SQLInputValue = \"__ts_mbt_sqlinput_value_from_string\"",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn sqlinput_value_from_double(value : Double) -> SQLInputValue = \"__ts_mbt_sqlinput_value_from_double\"",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn sqlinput_value_from_int64(value : Int64) -> SQLInputValue = \"__ts_mbt_sqlinput_value_from_int64\"",
    ),
  )
  assert_true(
    bundle.bridge_js.contains(
      "export function __ts_mbt_sqlinput_value_from_string(value) { return value; }",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn get_sqlite_ok() -> Double = \"__ts_mbt_get_sqlite_ok\"",
    ),
  )
  assert_true(bundle.bridge_js.contains("from \"node:sqlite\";"))
  assert_true(bundle.bridge_js.contains("DatabaseSync"))
  assert_true(
    bundle.bridge_js.contains("function __ts_mbt_unwrap_bool_option(value)"),
  )
  assert_true(
    bundle.bridge_js.contains(
      "function __ts_mbt_to_js_database_sync_options(value)",
    ),
  )
  assert_true(
    bundle.bridge_js.contains(
      "field = __ts_mbt_unwrap_bool_option(field);\n  if (field !== undefined) result[\"open\"] = field;",
    ),
  )
  assert_true(
    bundle.bridge_js.contains(
      "return new DatabaseSync(path, __ts_mbt_to_js_database_sync_options(options));",
    ),
  )
  assert_true(bundle.bridge_js.contains("SQLITE_OK"))
}

///|
async test "bridge: emit MoonBit JS FFI bundle keeps ambiguous exports as comments" {
  let bundle = emit_moonbit_js_ffi_bundle_from_entry_path(
    "fixtures/resolver/project/types/ambiguous-entry.d.ts", "./runtime/ambiguous.js",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(
    bundle.ffi_mbt.contains(
      "Unsupported export Shared: ambiguous re-export surface cannot be bound safely",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains("fixtures/resolver/project/types/ambiguous-a.d.ts"),
  )
  assert_true(
    bundle.ffi_mbt.contains("fixtures/resolver/project/types/ambiguous-b.d.ts"),
  )
  assert_true(
    bundle.bridge_js.contains(
      "Unsupported export Shared: ambiguous re-export surface cannot be bound safely",
    ),
  )
  assert_true(
    bundle.bridge_js.contains(
      "fixtures/resolver/project/types/ambiguous-a.d.ts",
    ),
  )
  assert_true(
    bundle.bridge_js.contains(
      "fixtures/resolver/project/types/ambiguous-b.d.ts",
    ),
  )
}

///|
async test "bridge: emit MoonBit JS FFI bundle comments unsupported enum-like exports" {
  let bundle = emit_moonbit_js_ffi_bundle_from_entry_path(
    "fixtures/resolver/project/types/unsupported-enum-like-entry.d.ts", "./runtime/unsupported-enum-like.js",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(
    bundle.ffi_mbt.contains(
      "Unsupported export MixedMode: mixed string/number enum cannot be lowered safely.",
    ),
  )
  assert_true(
    bundle.bridge_js.contains(
      "Unsupported export ComputedKind: enum member Dynamic has a non-literal computed value.",
    ),
  )
  assert_false(bundle.ffi_mbt.contains("pub(all) enum MixedMode"))
  assert_false(bundle.ffi_mbt.contains("pub(all) enum ComputedKind"))
}

///|
async test "bridge: emit MoonBit JS FFI bundle for typed value exports" {
  let bundle = emit_moonbit_js_ffi_bundle_from_entry_path(
    "fixtures/resolver/project/types/value-entry.d.ts", "./runtime/value.js",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn get_version() -> String = \"__ts_mbt_get_version\"",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn get_build_number() -> Double = \"__ts_mbt_get_build_number\"",
    ),
  )
  assert_true(
    bundle.bridge_js.contains(
      "export function __ts_mbt_get_version() { return version; }",
    ),
  )
  assert_true(
    bundle.bridge_js.contains(
      "export function __ts_mbt_get_build_number() { return buildNumber; }",
    ),
  )
}

///|
async test "bridge: emit MoonBit JS FFI bundle infers literal runtime value exports" {
  let bundle = emit_moonbit_js_ffi_bundle_from_entry_path(
    "fixtures/resolver/project/types/runtime-value-entry.ts", "./runtime/value.js",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn get_ready() -> Bool = \"__ts_mbt_get_ready\"",
    ),
  )
  assert_true(
    bundle.bridge_js.contains(
      "export function __ts_mbt_get_ready() { return ready; }",
    ),
  )
}

///|
async test "bridge: emit MoonBit JS FFI bundle for exported classes" {
  let bundle = emit_moonbit_js_ffi_bundle_from_entry_path(
    "fixtures/resolver/project/types/class-entry.d.ts", "./runtime/class.js",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(bundle.ffi_mbt.contains("#external\npub type Counter"))
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn new_counter(initial : Double) -> Counter = \"__ts_mbt_new_counter\"",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn Counter::inc(self : Counter, delta : Double) -> Double =\n  #| (self, delta) => self.inc(delta)",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn counter_from(seed : Double) -> Counter = \"__ts_mbt_counter_from\"",
    ),
  )
  assert_true(
    bundle.bridge_js.contains(
      "export function __ts_mbt_new_counter(initial) { return new Counter(initial); }",
    ),
  )
  assert_false(bundle.bridge_js.contains("__ts_mbt_counter_inc"))
  assert_true(
    bundle.bridge_js.contains(
      "export function __ts_mbt_counter_from(seed) { return Counter.from(seed); }",
    ),
  )
}

///|
async test "bridge: emit MoonBit JS FFI bundle for abstract classes without constructor" {
  let bundle = emit_moonbit_js_ffi_bundle_from_entry_path(
    "fixtures/resolver/project/types/abstract-class-entry.d.ts", "./runtime/shape.js",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(bundle.ffi_mbt.contains("#external\npub type Shape"))
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn Shape::area(self : Shape) -> Double =\n  #| (self) => self.area()",
    ),
  )
  assert_false(bundle.ffi_mbt.contains("pub extern \"js\" fn new_shape("))
  assert_false(bundle.bridge_js.contains("__ts_mbt_shape_area"))
}

///|
async test "bridge: emit MoonBit JS FFI bundle for exported class properties" {
  let bundle = emit_moonbit_js_ffi_bundle_from_entry_path(
    "fixtures/resolver/project/types/class-property-entry.d.ts", "./runtime/class-property.js",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn CounterState::get_counter_state_current(self : CounterState) -> Double =\n  #| (self) => self.current",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn CounterState::get_counter_state_label(self : CounterState) -> String =\n  #| (self) => self.label",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn CounterState::set_counter_state_label(self : CounterState, value : String) -> Unit =\n  #| (self, value) => (self.label = value)",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn get_counter_state_version() -> String = \"__ts_mbt_get_counter_state_version\"",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn set_counter_state_step(value : Double) -> Unit = \"__ts_mbt_set_counter_state_step\"",
    ),
  )
  assert_false(bundle.ffi_mbt.contains("set_counter_state_current"))
  assert_false(bundle.ffi_mbt.contains("set_counter_state_version"))
  assert_false(bundle.bridge_js.contains("__ts_mbt_get_counter_state_current"))
  assert_false(bundle.bridge_js.contains("__ts_mbt_set_counter_state_label"))
  assert_true(
    bundle.bridge_js.contains(
      "export function __ts_mbt_get_counter_state_version() { return CounterState.version; }",
    ),
  )
  assert_true(
    bundle.bridge_js.contains(
      "export function __ts_mbt_set_counter_state_step(value) { return (CounterState.step = value); }",
    ),
  )
}

///|
async test "bridge: emit MoonBit JS FFI bundle expands inherited callable class properties" {
  let bundle = emit_moonbit_js_ffi_bundle_from_entry_path(
    "fixtures/resolver/project/types/class-callable-property-alias-entry.d.ts", "./runtime/app.js",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(bundle.ffi_mbt.contains("#external\npub type App"))
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn App::get(self : App, arg0 : String, arg1 : Handler) -> Router",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn App::request(self : App, input : String) -> Response",
    ),
  )
}

///|
async test "bridge: emit MoonBit JS FFI bundle with unresolved external library types as opaque types" {
  let bundle = emit_moonbit_js_ffi_bundle_from_entry_path(
    "fixtures/resolver/project/types/external-lib-entry.d.ts", "/runtime/external-lib.js",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(bundle.ffi_mbt.contains("pub(all) struct User"))
  assert_true(bundle.ffi_mbt.contains("#external\npub type Result"))
  assert_true(bundle.ffi_mbt.contains("#external\npub type ResultAsync"))
  assert_true(
    bundle.ffi_mbt.contains(
      "#module(\"/runtime/external-lib.js\")\npub extern \"js\" fn parse_user(input : String) -> Result = \"parseUser\"",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "#module(\"/runtime/external-lib.js\")\npub extern \"js\" fn fetch_user(id : String) -> ResultAsync = \"fetchUser\"",
    ),
  )
  assert_false(bundle.bridge_js.contains("__ts_mbt_parse_user"))
}

///|
async test "bridge: emit MoonBit JS FFI bundle with resolved bare-package types as opaque types" {
  let bundle = emit_moonbit_js_ffi_bundle_from_entry_path(
    "fixtures/resolver/project/types/resolved-lib-entry.d.ts", "/runtime/resolved-lib.js",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(bundle.ffi_mbt.contains("pub(all) struct User"))
  assert_true(bundle.ffi_mbt.contains("#external\npub type PkgTypesValue"))
  assert_true(
    bundle.ffi_mbt.contains(
      "#module(\"/runtime/resolved-lib.js\")\npub extern \"js\" fn parse_user(input : String) -> PkgTypesValue = \"parseUser\"",
    ),
  )
  assert_false(bundle.bridge_js.contains("__ts_mbt_parse_user"))
}

///|
async test "bridge: emit MoonBit JS FFI bundle with minimal opaque bare-package imports" {
  let bundle = emit_moonbit_js_ffi_bundle_from_entry_path(
    "fixtures/resolver/project/types/opaque-package-entry.d.ts", "/runtime/opaque-package.js",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(bundle.ffi_mbt.contains("#external\npub type PkgTypesValue"))
  assert_true(
    bundle.ffi_mbt.contains(
      "#module(\"/runtime/opaque-package.js\")\npub extern \"js\" fn parse_value(input : String) -> PkgTypesValue = \"parseValue\"",
    ),
  )
  assert_false(bundle.bridge_js.contains("__ts_mbt_parse_value"))
}

///|
async test "bridge: emit MoonBit JS FFI bundle with resolved mixed imports as opaque types" {
  let bundle = emit_moonbit_js_ffi_bundle_from_entry_path(
    "fixtures/resolver/project/types/resolved-mixed-lib-entry.d.ts", "/runtime/resolved-mixed-lib.js",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(bundle.ffi_mbt.contains("pub(all) struct User"))
  assert_true(bundle.ffi_mbt.contains("#external\npub type PkgResult"))
  assert_true(bundle.ffi_mbt.contains("#external\npub type PkgResultAsync"))
  assert_true(
    bundle.ffi_mbt.contains(
      "#module(\"/runtime/resolved-mixed-lib.js\")\npub extern \"js\" fn parse_user(input : String) -> PkgResult = \"parseUser\"",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "#module(\"/runtime/resolved-mixed-lib.js\")\npub extern \"js\" fn fetch_user(id : String) -> PkgResultAsync = \"fetchUser\"",
    ),
  )
  assert_false(bundle.bridge_js.contains("__ts_mbt_parse_user"))
}

///|
test "bridge: FFI type name treats generic intersections with empty object as opaque" {
  let state : MoonBitJsFfiState = {
    declared_type_names: [],
    struct_type_names: [],
    generic_type_params_by_name: {},
    enums: [],
    external_type_names: [],
    local_type_param_names: [],
    function_field_method_wrapper_limit: ffi_function_field_method_wrapper_limit,
    tagged_union_decls_by_name: {},
    synthesized_inline_unions: {},
    needs_js_any: false,
    needs_promise: false,
  }
  let actual = ffi_type_name(
    state,
    @ast.TsType::Intersection([
      @ast.TsType::Applied("DateArg", [@ast.TsType::Named("Date")]),
      @ast.TsType::Object([]),
    ]),
  )
  assert_eq(actual, "DateArg")
  assert_false(state.needs_js_any)
  assert_true(state.external_type_names.contains("DateArg"))
}

///|
test "bridge: FFI type name collapses named option intersections" {
  let state : MoonBitJsFfiState = {
    declared_type_names: [],
    struct_type_names: [],
    generic_type_params_by_name: {},
    enums: [],
    external_type_names: [],
    local_type_param_names: [],
    function_field_method_wrapper_limit: ffi_function_field_method_wrapper_limit,
    tagged_union_decls_by_name: {},
    synthesized_inline_unions: {},
    needs_js_any: false,
    needs_promise: false,
  }
  let actual = ffi_type_name(
    state,
    @ast.TsType::Union([
      @ast.TsType::Intersection([
        @ast.TsType::Named("StatOptions"),
        @ast.TsType::Struct("Inline", [("bigint", @ast.TsType::Boolean)]),
      ]),
      @ast.TsType::Undefined,
    ]),
  )
  assert_eq(actual, "StatOptions?")
  assert_false(state.needs_js_any)
  assert_true(state.external_type_names.contains("StatOptions"))
}

///|
test "bridge: FFI type name preserves optional complex unions when widened" {
  let state : MoonBitJsFfiState = {
    declared_type_names: [],
    struct_type_names: [],
    generic_type_params_by_name: {},
    enums: [],
    external_type_names: [],
    local_type_param_names: [],
    function_field_method_wrapper_limit: ffi_function_field_method_wrapper_limit,
    tagged_union_decls_by_name: {},
    synthesized_inline_unions: {},
    needs_js_any: false,
    needs_promise: false,
  }
  let actual = ffi_type_name(
    state,
    @ast.TsType::Union([
      @ast.TsType::String_,
      @ast.TsType::Named("StringParams"),
      @ast.TsType::Undefined,
    ]),
  )
  // `string | StringParams | undefined`: the optional marker no longer
  // forces the inner `string | StringParams` to widen — the auto inline
  // union synthesiser kicks in and produces a tagged-enum alias.
  assert_eq(actual, "Auto_StringValue_or_StringParamsValue?")
  assert_false(state.needs_js_any)
}

///|
test "bridge: FFI type name renders declared generic applications" {
  let state : MoonBitJsFfiState = {
    declared_type_names: ["StatsBase"],
    struct_type_names: [],
    generic_type_params_by_name: { "StatsBase": ["T"] },
    enums: [],
    external_type_names: [],
    local_type_param_names: [],
    function_field_method_wrapper_limit: ffi_function_field_method_wrapper_limit,
    tagged_union_decls_by_name: {},
    synthesized_inline_unions: {},
    needs_js_any: false,
    needs_promise: false,
  }
  let actual = ffi_type_name(
    state,
    @ast.TsType::Applied("StatsBase", [@ast.TsType::Named("Int64")]),
  )
  assert_eq(actual, "StatsBase[Int64]")
  assert_false(state.needs_js_any)
}

///|
test "bridge: FFI type name lowers bigint primitive" {
  let state : MoonBitJsFfiState = {
    declared_type_names: [],
    struct_type_names: [],
    generic_type_params_by_name: {},
    enums: [],
    external_type_names: [],
    local_type_param_names: [],
    function_field_method_wrapper_limit: ffi_function_field_method_wrapper_limit,
    tagged_union_decls_by_name: {},
    synthesized_inline_unions: {},
    needs_js_any: false,
    needs_promise: false,
  }
  assert_eq(ffi_type_name(state, @ast.TsType::BigInt), "Int64")
  assert_false(state.needs_js_any)
}

///|
test "bridge: FFI type name lowers tuple payloads to arrays" {
  let state : MoonBitJsFfiState = {
    declared_type_names: ["Error"],
    struct_type_names: [],
    generic_type_params_by_name: {},
    enums: [],
    external_type_names: [],
    local_type_param_names: [],
    function_field_method_wrapper_limit: ffi_function_field_method_wrapper_limit,
    tagged_union_decls_by_name: {},
    synthesized_inline_unions: {},
    needs_js_any: false,
    needs_promise: false,
  }
  assert_eq(ffi_type_name(state, @ast.TsType::Tuple([])), "Array[Unit]")
  assert_eq(
    ffi_type_name(state, @ast.TsType::Tuple([@ast.TsType::Number])),
    "Array[Double]",
  )
  assert_eq(
    ffi_type_name(state, @ast.TsType::Tuple([@ast.TsType::Named("Error")])),
    "Array[Error_]",
  )
  assert_false(state.needs_js_any)
}

///|
test "bridge: FFI type name lowers function types" {
  let state : MoonBitJsFfiState = {
    declared_type_names: ["Node"],
    struct_type_names: [],
    generic_type_params_by_name: {},
    enums: [],
    external_type_names: [],
    local_type_param_names: [],
    function_field_method_wrapper_limit: ffi_function_field_method_wrapper_limit,
    tagged_union_decls_by_name: {},
    synthesized_inline_unions: {},
    needs_js_any: false,
    needs_promise: false,
  }
  assert_eq(
    ffi_type_name(
      state,
      @ast.TsType::Func(
        [@ast.TsType::Named("Node")],
        @ast.TsType::Named("Node"),
      ),
    ),
    "(Node) -> Node",
  )
  assert_false(state.needs_js_any)
}

///|
test "bridge: FFI struct field type parenthesizes optional function types" {
  let state : MoonBitJsFfiState = {
    declared_type_names: ["Node"],
    struct_type_names: [],
    generic_type_params_by_name: {},
    enums: [],
    external_type_names: [],
    local_type_param_names: [],
    function_field_method_wrapper_limit: ffi_function_field_method_wrapper_limit,
    tagged_union_decls_by_name: {},
    synthesized_inline_unions: {},
    needs_js_any: false,
    needs_promise: false,
  }
  assert_eq(
    ffi_struct_field_type_name(
      state,
      @ast.TsType::Union([
        @ast.TsType::Func(
          [@ast.TsType::Named("Node")],
          @ast.TsType::Named("Node"),
        ),
        @ast.TsType::Undefined,
      ]),
    ),
    "((Node) -> Node)?",
  )
  assert_false(state.needs_js_any)
}

///|
async test "bridge: emit MoonBit JS FFI bundle names inline object promise results" {
  let bundle = emit_moonbit_js_ffi_bundle_from_entry_path(
    "fixtures/resolver/project/types/inline-object-promise-entry.d.ts", "./runtime/inline-object-promise.js",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(bundle.ffi_mbt.contains("pub(all) struct ReadPromisifyResult"))
  assert_true(bundle.ffi_mbt.contains("bytesRead : Double"))
  assert_true(bundle.ffi_mbt.contains("buffer : NodeJS_ArrayBufferView"))
  assert_true(
    bundle.ffi_mbt.contains(
      "extern \"js\" fn read_promisify(fd : Double, buffer : NodeJS_ArrayBufferView) -> Promise[ReadPromisifyResult] =",
    ),
  )
  assert_false(bundle.ffi_mbt.contains("Promise[JSValue]"))
}

///|
test "bridge: FFI type name widens likely generic placeholders" {
  let state : MoonBitJsFfiState = {
    declared_type_names: [],
    struct_type_names: [],
    generic_type_params_by_name: {},
    enums: [],
    external_type_names: [],
    local_type_param_names: [],
    function_field_method_wrapper_limit: ffi_function_field_method_wrapper_limit,
    tagged_union_decls_by_name: {},
    synthesized_inline_unions: {},
    needs_js_any: false,
    needs_promise: false,
  }
  assert_eq(ffi_type_name(state, @ast.TsType::Named("T")), "JSValue")
  assert_eq(ffi_type_name(state, @ast.TsType::Named("K")), "JSValue")
  assert_true(state.needs_js_any)
  assert_false(state.external_type_names.contains("T"))
  assert_false(state.external_type_names.contains("K"))
}

///|
async test "bridge: emit MoonBit JS FFI bundle with resolved generic library imports" {
  let bundle = emit_moonbit_js_ffi_bundle_from_entry_path(
    "fixtures/resolver/project/types/resolved-generic-lib-entry.d.ts", "/runtime/resolved-generic-lib.js",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(bundle.ffi_mbt.contains("pub(all) struct User"))
  assert_true(bundle.ffi_mbt.contains("#external\npub type PkgResult"))
  assert_true(bundle.ffi_mbt.contains("#external\npub type PkgResultAsync"))
  assert_true(
    bundle.ffi_mbt.contains(
      "#module(\"/runtime/resolved-generic-lib.js\")\npub extern \"js\" fn parse_user(input : String) -> PkgResult = \"parseUser\"",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "#module(\"/runtime/resolved-generic-lib.js\")\npub extern \"js\" fn fetch_user(id : String) -> PkgResultAsync = \"fetchUser\"",
    ),
  )
}

///|
async test "bridge: emit MoonBit JS FFI bundle with resolved symlinked library imports" {
  let bundle = emit_moonbit_js_ffi_bundle_from_entry_path(
    "fixtures/resolver/project/types/resolved-symlink-lib-entry.d.ts", "/runtime/resolved-symlink-lib.js",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(bundle.ffi_mbt.contains("pub(all) struct User"))
  assert_true(bundle.ffi_mbt.contains("#external\npub type PkgSymlinkResult"))
  assert_true(
    bundle.ffi_mbt.contains("#external\npub type PkgSymlinkResultAsync"),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "#module(\"/runtime/resolved-symlink-lib.js\")\npub extern \"js\" fn parse_user(input : String) -> PkgSymlinkResult = \"parseUser\"",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "#module(\"/runtime/resolved-symlink-lib.js\")\npub extern \"js\" fn fetch_user(id : String) -> PkgSymlinkResultAsync = \"fetchUser\"",
    ),
  )
}

///|
async test "bridge: emit MoonBit JS FFI bundle with neverthrow-like package imports" {
  let bundle = emit_moonbit_js_ffi_bundle_from_entry_path(
    "fixtures/resolver/project/types/neverthrow-like-entry.d.ts", "/runtime/neverthrow-like.js",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(bundle.ffi_mbt.contains("pub(all) struct User"))
  assert_true(bundle.ffi_mbt.contains("#external\npub type Result"))
  assert_true(bundle.ffi_mbt.contains("#external\npub type ResultAsync"))
  assert_true(
    bundle.ffi_mbt.contains(
      "#module(\"/runtime/neverthrow-like.js\")\npub extern \"js\" fn parse_user(input : String) -> Result = \"parseUser\"",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "#module(\"/runtime/neverthrow-like.js\")\npub extern \"js\" fn fetch_user(id : String) -> ResultAsync = \"fetchUser\"",
    ),
  )
}

///|
async test "bridge: emit MoonBit JS FFI bundle through package exports subpath" {
  let bundle = emit_moonbit_js_ffi_bundle_from_entry_path(
    "fixtures/resolver/project/types/subpath-package-entry.d.ts", "/runtime/subpath-package.js",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(bundle.ffi_mbt.contains("pub(all) struct FeatureOptions"))
  assert_true(bundle.ffi_mbt.contains("pub(all) struct FeatureResult"))
  assert_true(
    bundle.ffi_mbt.contains(
      "#module(\"/runtime/subpath-package.js\")\npub extern \"js\" fn execute_feature(options : FeatureOptions) -> FeatureResult = \"runFeature\"",
    ),
  )
}

///|
async test "bridge: emit MoonBit JS FFI bundle through package barrel reexports" {
  let bundle = emit_moonbit_js_ffi_bundle_from_entry_path(
    "fixtures/resolver/project/types/barrel-package-entry.d.ts", "/runtime/barrel-package.js",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(bundle.ffi_mbt.contains("pub(all) struct BarrelOptions"))
  assert_true(bundle.ffi_mbt.contains("pub(all) struct BarrelResult"))
  assert_true(
    bundle.ffi_mbt.contains(
      "#module(\"/runtime/barrel-package.js\")\npub extern \"js\" fn create_barrel(options : BarrelOptions) -> BarrelResult = \"buildBarrel\"",
    ),
  )
}

///|
async test "bridge: emit MoonBit JS FFI bundle with node-like ambient qualified types" {
  let bundle = emit_moonbit_js_ffi_bundle_from_entry_path(
    "fixtures/resolver/project/types/node-like-entry.d.ts", "/runtime/node-like.js",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(bundle.ffi_mbt.contains("pub(all) struct RuntimeConfig"))
  assert_true(bundle.ffi_mbt.contains("#external\npub type NodeJS_ProcessEnv"))
  assert_true(
    bundle.ffi_mbt.contains(
      "#module(\"/runtime/node-like.js\")\npub extern \"js\" fn has_env(env : NodeJS_ProcessEnv, key : String) -> Bool = \"hasEnv\"",
    ),
  )
}

///|
async test "bridge: emit MoonBit JS FFI bundle collapse overloads by generated binding name" {
  let bundle = emit_moonbit_js_ffi_bundle_from_entry_path(
    "fixtures/resolver/project/types/overload-entry.d.ts", "./runtime/overload.js",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_eq(
    count_occurrences_in_ffi_output(
      bundle.ffi_mbt,
      "pub extern \"js\" fn make_counter(",
    ),
    1,
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn make_counter_number(value : Double) -> Counter = \"__ts_mbt_make_counter_number\"",
    ),
  )
  assert_eq(
    count_occurrences_in_ffi_output(
      bundle.ffi_mbt,
      "pub extern \"js\" fn Counter::value(",
    ),
    1,
  )
  assert_eq(
    count_occurrences_in_ffi_output(
      bundle.ffi_mbt,
      "pub extern \"js\" fn choose_concrete(",
    ),
    1,
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn choose_concrete(value : String) -> Double = \"__ts_mbt_choose_concrete\"",
    ),
  )
  assert_eq(
    count_occurrences_in_ffi_output(
      bundle.bridge_js,
      "export { makeCounter as __ts_mbt_make_counter } from \"./runtime/overload.js\";",
    ),
    1,
  )
  assert_eq(
    count_occurrences_in_ffi_output(
      bundle.bridge_js,
      "export { makeCounter as __ts_mbt_make_counter_number } from \"./runtime/overload.js\";",
    ),
    1,
  )
  assert_eq(
    count_occurrences_in_ffi_output(
      bundle.bridge_js,
      "export const __ts_mbt_counter_value =",
    ),
    0,
  )
}

///|
async test "bridge: emit MoonBit JS FFI bundle keeps bare package overload variants bound to source names" {
  let bundle = emit_moonbit_js_ffi_bundle_from_entry_path(
    "fixtures/resolver/project/types/overload-entry.d.ts", "overload-pkg",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(
    bundle.ffi_mbt.contains(
      "#module(\"overload-pkg\")\npub extern \"js\" fn make_counter_number(value : Double) -> Counter = \"makeCounter\"",
    ),
  )
  assert_false(bundle.ffi_mbt.contains("makeCounterNumber"))
}

///|
async test "bridge: emit MoonBit JS FFI bundle from runtime ts exported functions" {
  let bundle = emit_moonbit_js_ffi_bundle_from_entry_path(
    "fixtures/resolver/project/types/runtime-function-entry.ts", "/runtime/runtime-function.js",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(bundle.ffi_mbt.contains("pub(all) struct RuntimePoint"))
  assert_true(
    bundle.ffi_mbt.contains(
      "#module(\"/runtime/runtime-function.js\")\npub extern \"js\" fn scale_point(point : RuntimePoint, factor : Double) -> RuntimePoint = \"scalePoint\"",
    ),
  )
  assert_false(bundle.bridge_js.contains("__ts_mbt_scale_point"))
}

///|
async test "bridge: emit MoonBit JS FFI bundle uses adapter reexport for relative runtime functions" {
  let bundle = emit_moonbit_js_ffi_bundle_from_entry_path(
    "fixtures/resolver/project/types/runtime-function-entry.ts", "./runtime/runtime-function.js",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn scale_point(point : RuntimePoint, factor : Double) -> RuntimePoint = \"__ts_mbt_scale_point\"",
    ),
  )
  assert_true(
    bundle.bridge_js.contains(
      "export { scalePoint as __ts_mbt_scale_point } from \"./runtime/runtime-function.js\";",
    ),
  )
}

///|
async test "bridge: emit MoonBit JS FFI bundle from runtime tsx exported functions" {
  let bundle = emit_moonbit_js_ffi_bundle_from_entry_path(
    "fixtures/resolver/project/types/runtime-component-entry.tsx", "/runtime/runtime-component.js",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(bundle.ffi_mbt.contains("pub(all) struct BadgeProps"))
  assert_true(bundle.ffi_mbt.contains("#external\npub type JSX_Element"))
  assert_true(
    bundle.ffi_mbt.contains(
      "#module(\"/runtime/runtime-component.js\")\npub extern \"js\" fn render_badge(props : BadgeProps) -> JSX_Element = \"renderBadge\"",
    ),
  )
  assert_false(bundle.bridge_js.contains("__ts_mbt_render_badge"))
}

///|
async test "bridge: emit MoonBit JS FFI bundle from runtime ts exported const arrow functions" {
  let bundle = emit_moonbit_js_ffi_bundle_from_entry_path(
    "fixtures/resolver/project/types/runtime-arrow-entry.ts", "/runtime/runtime-arrow.js",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(bundle.ffi_mbt.contains("pub(all) struct RuntimeArrowPoint"))
  assert_true(
    bundle.ffi_mbt.contains(
      "#module(\"/runtime/runtime-arrow.js\")\npub extern \"js\" fn scale_arrow_point(point : RuntimeArrowPoint, factor : Double) -> RuntimeArrowPoint = \"scaleArrowPoint\"",
    ),
  )
  assert_false(bundle.bridge_js.contains("__ts_mbt_scale_arrow_point"))
}

///|
async test "bridge: emit callable wrappers for natural function-valued const exports" {
  let bundle = emit_moonbit_js_ffi_bundle_from_entry_path(
    "fixtures/resolver/project/types/function-value-string-array-entry.d.ts", "glob-like",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(bundle.ffi_mbt.contains("pub(all) struct GlobOptions"))
  assert_true(
    bundle.ffi_mbt.contains("pub extern \"js\" fn get_has_magic() ->"),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn has_magic(arg0 : String, arg1 : GlobOptions) -> Bool = \"__ts_mbt_has_magic\"",
    ),
  )
  // The full `hasMagic` wrapper now routes the `string | string[]`
  // first arg through the synthesised tagged-union to-JS converter so
  // MoonBit-side `StringValue("foo")` / `StringArrayValue(["..."])`
  // values arrive at drizzle's runtime as raw strings / arrays. The
  // string-subset variant (asserted below as `has_magic(arg0 : String,
  // ...)`) keeps the direct-extern path because plain `String` doesn't
  // need any conversion.
  assert_true(bundle.bridge_js.contains("export function __ts_mbt_has_magic("))
  assert_true(
    bundle.bridge_js.contains("__ts_mbt_module.hasMagic(") &&
    bundle.bridge_js.contains("\"$tag\" in arg0") &&
    bundle.bridge_js.contains("__ts_mbt_to_js_glob_options(arg1)"),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn escape(arg0 : String, arg1 : GlobOptions) -> String = \"__ts_mbt_escape\"",
    ),
  )
  assert_true(
    bundle.bridge_js.contains(
      "export function __ts_mbt_escape(arg0, arg1) { return __ts_mbt_module.escape(arg0, __ts_mbt_to_js_glob_options(arg1)); }",
    ),
  )
}

///|
async test "bridge: emit string subset wrappers for function params with string array unions" {
  let bundle = emit_moonbit_js_ffi_bundle_from_entry_path(
    "fixtures/resolver/project/types/function-string-array-entry.d.ts", "node:util",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(bundle.ffi_mbt.contains("pub(all) struct DiffEntry"))
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn diff(actual : Auto_StringArray_or_StringValue, expected : Auto_StringArray_or_StringValue) -> Array[DiffEntry] = \"diff\"",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn diff_string(actual : String, expected : String) -> Array[DiffEntry] = \"diff\"",
    ),
  )
  assert_false(bundle.bridge_js.contains("__ts_mbt_diff_string"))
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn is_array_string_array(value : Array[String]) -> Bool = \"__ts_mbt_is_array_string_array\"",
    ),
  )
  assert_true(
    bundle.bridge_js.contains(
      "export function __ts_mbt_is_array_string_array(value) { return isArray(value); }",
    ),
  )
}

///|
async test "bridge: emit primitive node assert wrappers without widening values to JSValue" {
  let bundle = emit_moonbit_js_ffi_bundle_from_entry_path(
    "fixtures/resolver/project/types/node-assert-primitive-entry.d.ts", "node:assert",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn ok_bool(value : Bool, message : String?) -> Unit = \"__ts_mbt_ok_bool\"",
    ),
  )
  assert_true(
    bundle.bridge_js.contains(
      "export function __ts_mbt_ok_bool(value, message) { return ok(value, __ts_mbt_unwrap_option(message)); }",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn equal_double(actual : Double, expected : Double, message : String?) -> Unit = \"__ts_mbt_equal_double\"",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn strict_equal_string(actual : String, expected : String, message : String?) -> Unit = \"__ts_mbt_strict_equal_string\"",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn not_equal_double(actual : Double, expected : Double, message : String?) -> Unit = \"__ts_mbt_not_equal_double\"",
    ),
  )
  assert_true(
    bundle.bridge_js.contains(
      "export function __ts_mbt_not_equal_double(actual, expected, message) { return notEqual(actual, expected, __ts_mbt_unwrap_option(message)); }",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn not_strict_equal_string(actual : String, expected : String, message : String?) -> Unit = \"__ts_mbt_not_strict_equal_string\"",
    ),
  )
  assert_true(
    bundle.bridge_js.contains(
      "export function __ts_mbt_not_strict_equal_string(actual, expected, message) { return notStrictEqual(actual, expected, __ts_mbt_unwrap_option(message)); }",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn ok(value : JSValue, message : String?) -> JSValue = \"__ts_mbt_ok\"",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn equal(actual : JSValue, expected : JSValue, message : String?) -> Unit = \"__ts_mbt_equal\"",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn not_equal(actual : JSValue, expected : JSValue, message : String?) -> Unit = \"__ts_mbt_not_equal\"",
    ),
  )
}

///|
async test "bridge: emit React Router params helpers for generatePath" {
  let bundle = emit_moonbit_js_ffi_bundle_from_entry_path(
    "fixtures/resolver/project/types/react-router-params-entry.d.ts", "react-router",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(bundle.ffi_mbt.contains("#external\npub type Params"))
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn params_from_pairs(keys : Array[String], values : Array[String]) -> Params = \"__ts_mbt_params_from_pairs\"",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn generate_path_params(originalPath : String, params : Params) -> String = \"__ts_mbt_generate_path_params\"",
    ),
  )
  assert_true(
    bundle.bridge_js.contains(
      "export function __ts_mbt_params_from_pairs(keys, values) { const out = {}; for (let i = 0; i < keys.length; i++) out[keys[i]] = values[i]; return out; }",
    ),
  )
  assert_true(
    bundle.bridge_js.contains(
      "export function __ts_mbt_generate_path_params(originalPath, params) { return generatePath(originalPath, params); }",
    ),
  )
}

///|
async test "bridge: emit JOSE issued-at number helpers" {
  let bundle = emit_moonbit_js_ffi_bundle_from_entry_path(
    "fixtures/resolver/project/types/jose-issued-at-entry.d.ts", "jose",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn unsecured_jwt_set_issued_at_double(jwt : UnsecuredJWT, input : Double) -> UnsecuredJWT = \"__ts_mbt_unsecured_jwt_set_issued_at_double\"",
    ),
  )
  assert_true(
    bundle.bridge_js.contains(
      "export function __ts_mbt_unsecured_jwt_set_issued_at_double(jwt, input) { return jwt.setIssuedAt(input); }",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn sign_jwt_set_issued_at_double(signer : SignJWT, input : Double) -> SignJWT = \"__ts_mbt_sign_jwt_set_issued_at_double\"",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn unsecured_jwt_set_not_before_double(jwt : UnsecuredJWT, input : Double) -> UnsecuredJWT = \"__ts_mbt_unsecured_jwt_set_not_before_double\"",
    ),
  )
  assert_true(
    bundle.bridge_js.contains(
      "export function __ts_mbt_unsecured_jwt_set_not_before_double(jwt, input) { return jwt.setNotBefore(input); }",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn sign_jwt_set_not_before_double(signer : SignJWT, input : Double) -> SignJWT = \"__ts_mbt_sign_jwt_set_not_before_double\"",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn unsecured_jwt_set_expiration_time_double(jwt : UnsecuredJWT, input : Double) -> UnsecuredJWT = \"__ts_mbt_unsecured_jwt_set_expiration_time_double\"",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn sign_jwt_set_expiration_time_double(signer : SignJWT, input : Double) -> SignJWT = \"__ts_mbt_sign_jwt_set_expiration_time_double\"",
    ),
  )
}

///|
async test "bridge: emit MoonBit JS FFI bundle from runtime ts exported untyped const arrow functions" {
  let bundle = emit_moonbit_js_ffi_bundle_from_entry_path(
    "fixtures/resolver/project/types/runtime-untyped-arrow-entry.ts", "/runtime/runtime-untyped-arrow.js",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(
    bundle.ffi_mbt.contains(
      "#module(\"/runtime/runtime-untyped-arrow.js\")\npub extern \"js\" fn double_value(value : Double) -> Double = \"doubleValue\"",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "#module(\"/runtime/runtime-untyped-arrow.js\")\npub extern \"js\" fn greet_value(name : String) -> String = \"greetValue\"",
    ),
  )
}

///|
async test "bridge: emit MoonBit JS FFI bundle from runtime ts function reexports" {
  let bundle = emit_moonbit_js_ffi_bundle_from_entry_path(
    "fixtures/resolver/project/types/runtime-function-reexport-entry.ts", "/runtime/runtime-function-reexport.js",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(bundle.ffi_mbt.contains("pub extern \"js\" fn scale_point("))
  assert_false(bundle.bridge_js.contains("__ts_mbt_scale_point"))
}

///|
async test "bridge: emit MoonBit JS FFI bundle keeps direct class-property reexports bound to original runtime class" {
  let bundle = emit_moonbit_js_ffi_bundle_from_entry_path(
    "fixtures/resolver/project/types/class-property-reexport-entry.d.ts", "/runtime/class-property.js",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(bundle.ffi_mbt.contains("#external\npub type RuntimeState"))
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn new_runtime_state() -> RuntimeState = \"__ts_mbt_new_runtime_state\"",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn get_runtime_state_version() -> String = \"__ts_mbt_get_runtime_state_version\"",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn set_runtime_state_step(value : Double) -> Unit = \"__ts_mbt_set_runtime_state_step\"",
    ),
  )
  assert_true(
    bundle.bridge_js.contains(
      "export function __ts_mbt_new_runtime_state() { return new CounterState(); }",
    ),
  )
  assert_true(
    bundle.bridge_js.contains(
      "export function __ts_mbt_get_runtime_state_version() { return CounterState.version; }",
    ),
  )
  assert_true(
    bundle.bridge_js.contains(
      "export function __ts_mbt_set_runtime_state_step(value) { return (CounterState.step = value); }",
    ),
  )
}

///|
async test "bridge: emit MoonBit JS FFI bundle keeps bare class-property reexports bound to package class" {
  let bundle = emit_moonbit_js_ffi_bundle_from_entry_path(
    "fixtures/resolver/project/types/bare-class-property-entry.d.ts", "pkg-class-property",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(bundle.ffi_mbt.contains("#external\npub type RuntimeState"))
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn new_runtime_state() -> RuntimeState = \"__ts_mbt_new_runtime_state\"",
    ),
  )
  assert_true(
    bundle.bridge_js.contains(
      "import * as __ts_mbt_module from \"pkg-class-property\";",
    ),
  )
  assert_true(
    bundle.bridge_js.contains(
      "const CounterState = __ts_mbt_module.CounterState;",
    ),
  )
  assert_true(
    bundle.bridge_js.contains(
      "export function __ts_mbt_new_runtime_state() { return new CounterState(); }",
    ),
  )
  assert_true(
    bundle.bridge_js.contains(
      "export function __ts_mbt_get_runtime_state_version() { return CounterState.version; }",
    ),
  )
}

///|
async test "bridge: emit MoonBit JS FFI bundle keeps bare default class reexports bound to package default export" {
  let bundle = emit_moonbit_js_ffi_bundle_from_entry_path(
    "fixtures/resolver/project/types/bare-default-class-entry.d.ts", "pkg-default-class",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(bundle.ffi_mbt.contains("#external\npub type RuntimeCounter"))
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn new_runtime_counter(initial : Double) -> RuntimeCounter = \"__ts_mbt_new_runtime_counter\"",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn runtime_counter_from(seed : Double) -> RuntimeCounter = \"__ts_mbt_runtime_counter_from\"",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn get_runtime_counter_version() -> String = \"__ts_mbt_get_runtime_counter_version\"",
    ),
  )
  assert_true(
    bundle.bridge_js.contains("import default_ from \"pkg-default-class\";"),
  )
  assert_true(
    bundle.bridge_js.contains(
      "export function __ts_mbt_new_runtime_counter(initial) { return new default_(initial); }",
    ),
  )
  assert_true(
    bundle.bridge_js.contains(
      "export function __ts_mbt_runtime_counter_from(seed) { return default_.from(seed); }",
    ),
  )
  assert_true(
    bundle.bridge_js.contains(
      "export function __ts_mbt_get_runtime_counter_version() { return default_.version; }",
    ),
  )
}

///|
async test "bridge: emit MoonBit JS FFI bundle keeps subpath class reexports bound to package export" {
  let bundle = emit_moonbit_js_ffi_bundle_from_entry_path(
    "fixtures/resolver/project/types/subpath-class-entry.d.ts", "pkg-class-subpath/state",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(bundle.ffi_mbt.contains("#external\npub type RuntimeState"))
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn new_runtime_state() -> RuntimeState = \"__ts_mbt_new_runtime_state\"",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn get_runtime_state_version() -> String = \"__ts_mbt_get_runtime_state_version\"",
    ),
  )
  assert_true(
    bundle.bridge_js.contains(
      "import * as __ts_mbt_module from \"pkg-class-subpath/state\";",
    ),
  )
  assert_true(
    bundle.bridge_js.contains(
      "const CounterState = __ts_mbt_module.CounterState;",
    ),
  )
  assert_true(
    bundle.bridge_js.contains(
      "export function __ts_mbt_new_runtime_state() { return new CounterState(); }",
    ),
  )
}

///|
async test "bridge: emit MoonBit JS FFI bundle handles runtime ts destructured value exports" {
  let bundle = emit_moonbit_js_ffi_bundle_from_entry_path(
    "fixtures/resolver/project/types/runtime-destructured-value-entry.ts", "/runtime/runtime-destructured-value.js",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn get_runtime_version() -> String = \"__ts_mbt_get_runtime_version\"",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn get_build() -> Double = \"__ts_mbt_get_build\"",
    ),
  )
  assert_true(
    bundle.bridge_js.contains(
      "import { build, runtimeVersion } from \"/runtime/runtime-destructured-value.js\";",
    ),
  )
  assert_true(
    bundle.bridge_js.contains(
      "export function __ts_mbt_get_runtime_version() { return runtimeVersion; }",
    ),
  )
  assert_true(
    bundle.bridge_js.contains(
      "export function __ts_mbt_get_build() { return build; }",
    ),
  )
}

///|
async test "bridge: emit MoonBit JS FFI bundle handles nested and array-rest destructured value exports" {
  let bundle = emit_moonbit_js_ffi_bundle_from_entry_path(
    "fixtures/resolver/project/types/runtime-destructured-nested-rest-value-entry.ts",
    "/runtime/runtime-destructured-nested-rest-value.js",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn get_runtime_version() -> String = \"__ts_mbt_get_runtime_version\"",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn get_build() -> Double = \"__ts_mbt_get_build\"",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn get_head() -> Double = \"__ts_mbt_get_head\"",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn get_tail() -> Array[Double] = \"__ts_mbt_get_tail\"",
    ),
  )
  assert_true(
    bundle.bridge_js.contains(
      "import { head, tail, build, runtimeVersion } from \"/runtime/runtime-destructured-nested-rest-value.js\";",
    ),
  )
  assert_true(
    bundle.bridge_js.contains(
      "export function __ts_mbt_get_tail() { return tail; }",
    ),
  )
}

///|
async test "bridge: emit MoonBit JS FFI bundle handles object-rest destructured value exports" {
  let bundle = emit_moonbit_js_ffi_bundle_from_entry_path(
    "fixtures/resolver/project/types/runtime-object-rest-value-entry.ts", "/runtime/runtime-object-rest-value.js",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(bundle.ffi_mbt.contains("pub(all) struct RestMeta"))
  assert_true(bundle.ffi_mbt.contains("  build : Double"))
  assert_true(bundle.ffi_mbt.contains("  enabled : Bool"))
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn get_version() -> String = \"__ts_mbt_get_version\"",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn get_rest_meta() -> RestMeta = \"__ts_mbt_get_rest_meta\"",
    ),
  )
  assert_true(
    bundle.bridge_js.contains(
      "import { version, restMeta } from \"/runtime/runtime-object-rest-value.js\";",
    ),
  )
  assert_true(
    bundle.bridge_js.contains(
      "export function __ts_mbt_get_rest_meta() { return restMeta; }",
    ),
  )
}

///|
async test "bridge: emit MoonBit JS FFI bundle handles computed-key destructured value exports" {
  let bundle = emit_moonbit_js_ffi_bundle_from_entry_path(
    "fixtures/resolver/project/types/runtime-computed-destructured-value-entry.ts",
    "/runtime/runtime-computed-destructured-value.js",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(bundle.ffi_mbt.contains("pub(all) struct RestMeta"))
  assert_true(bundle.ffi_mbt.contains("  enabled : Bool"))
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn get_runtime_version() -> String = \"__ts_mbt_get_runtime_version\"",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn get_build() -> Double = \"__ts_mbt_get_build\"",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn get_rest_meta() -> RestMeta = \"__ts_mbt_get_rest_meta\"",
    ),
  )
  assert_true(
    bundle.bridge_js.contains(
      "import { build, restMeta, runtimeVersion } from \"/runtime/runtime-computed-destructured-value.js\";",
    ),
  )
  assert_true(
    bundle.bridge_js.contains(
      "export function __ts_mbt_get_rest_meta() { return restMeta; }",
    ),
  )
}

///|
async test "bridge: emit MoonBit JS FFI bundle handles template-literal computed-key destructured value exports" {
  let bundle = emit_moonbit_js_ffi_bundle_from_entry_path(
    "fixtures/resolver/project/types/runtime-template-computed-destructured-value-entry.ts",
    "/runtime/runtime-template-computed-destructured-value.js",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(bundle.ffi_mbt.contains("pub(all) struct RestMeta"))
  assert_true(bundle.ffi_mbt.contains("  enabled : Bool"))
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn get_runtime_version() -> String = \"__ts_mbt_get_runtime_version\"",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn get_build() -> Double = \"__ts_mbt_get_build\"",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn get_rest_meta() -> RestMeta = \"__ts_mbt_get_rest_meta\"",
    ),
  )
  assert_true(
    bundle.bridge_js.contains(
      "import { build, restMeta, runtimeVersion } from \"/runtime/runtime-template-computed-destructured-value.js\";",
    ),
  )
  assert_true(
    bundle.bridge_js.contains(
      "export function __ts_mbt_get_rest_meta() { return restMeta; }",
    ),
  )
}

///|
async test "bridge: emit MoonBit JS FFI bundle handles concatenated computed-key destructured value exports" {
  let bundle = emit_moonbit_js_ffi_bundle_from_entry_path(
    "fixtures/resolver/project/types/runtime-concat-computed-destructured-value-entry.ts",
    "/runtime/runtime-concat-computed-destructured-value.js",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(bundle.ffi_mbt.contains("pub(all) struct RestMeta"))
  assert_true(bundle.ffi_mbt.contains("  enabled : Bool"))
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn get_runtime_version() -> String = \"__ts_mbt_get_runtime_version\"",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn get_build() -> Double = \"__ts_mbt_get_build\"",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn get_rest_meta() -> RestMeta = \"__ts_mbt_get_rest_meta\"",
    ),
  )
  assert_true(
    bundle.bridge_js.contains(
      "import { build, restMeta, runtimeVersion } from \"/runtime/runtime-concat-computed-destructured-value.js\";",
    ),
  )
  assert_true(
    bundle.bridge_js.contains(
      "export function __ts_mbt_get_rest_meta() { return restMeta; }",
    ),
  )
}

///|
async test "bridge: emit MoonBit JS FFI bundle handles primitive-literal computed-key destructured value exports" {
  let bundle = emit_moonbit_js_ffi_bundle_from_entry_path(
    "fixtures/resolver/project/types/runtime-primitive-computed-destructured-value-entry.ts",
    "/runtime/runtime-primitive-computed-destructured-value.js",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(bundle.ffi_mbt.contains("pub(all) struct RestMeta"))
  assert_true(bundle.ffi_mbt.contains("  enabled : Bool"))
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn get_truthy() -> String = \"__ts_mbt_get_truthy\"",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn get_nil_value() -> Double = \"__ts_mbt_get_nil_value\"",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn get_negative() -> Bool = \"__ts_mbt_get_negative\"",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn get_bigint_value() -> String = \"__ts_mbt_get_bigint_value\"",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn get_rest_meta() -> RestMeta = \"__ts_mbt_get_rest_meta\"",
    ),
  )
  assert_true(
    bundle.bridge_js.contains(
      "import { truthy, negative, nilValue, restMeta, bigintValue } from \"/runtime/runtime-primitive-computed-destructured-value.js\";",
    ),
  )
  assert_true(
    bundle.bridge_js.contains(
      "export function __ts_mbt_get_rest_meta() { return restMeta; }",
    ),
  )
}

///|
async test "bridge: emit MoonBit JS FFI bundle handles void-and-negative-bigint computed-key destructured value exports" {
  let bundle = emit_moonbit_js_ffi_bundle_from_entry_path(
    "fixtures/resolver/project/types/runtime-void-bigint-computed-destructured-value-entry.ts",
    "/runtime/runtime-void-bigint-computed-destructured-value.js",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(bundle.ffi_mbt.contains("pub(all) struct RestMeta"))
  assert_true(bundle.ffi_mbt.contains("  enabled : Bool"))
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn get_undefined_value() -> String = \"__ts_mbt_get_undefined_value\"",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn get_negative_bigint() -> Double = \"__ts_mbt_get_negative_bigint\"",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn get_rest_meta() -> RestMeta = \"__ts_mbt_get_rest_meta\"",
    ),
  )
  assert_true(
    bundle.bridge_js.contains(
      "import { restMeta, negativeBigint, undefinedValue } from \"/runtime/runtime-void-bigint-computed-destructured-value.js\";",
    ),
  )
  assert_true(
    bundle.bridge_js.contains(
      "export function __ts_mbt_get_rest_meta() { return restMeta; }",
    ),
  )
}

///|
async test "bridge: emit MoonBit JS FFI bundle handles const-reference computed-key destructured value exports" {
  let bundle = emit_moonbit_js_ffi_bundle_from_entry_path(
    "fixtures/resolver/project/types/runtime-const-ref-computed-destructured-value-entry.ts",
    "/runtime/runtime-const-ref-computed-destructured-value.js",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(bundle.ffi_mbt.contains("pub(all) struct RestMeta"))
  assert_true(bundle.ffi_mbt.contains("  enabled : Bool"))
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn get_runtime_version() -> String = \"__ts_mbt_get_runtime_version\"",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn get_build() -> Double = \"__ts_mbt_get_build\"",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn get_rest_meta() -> RestMeta = \"__ts_mbt_get_rest_meta\"",
    ),
  )
  assert_true(
    bundle.bridge_js.contains(
      "import { build, restMeta, runtimeVersion } from \"/runtime/runtime-const-ref-computed-destructured-value.js\";",
    ),
  )
  assert_true(
    bundle.bridge_js.contains(
      "export function __ts_mbt_get_rest_meta() { return restMeta; }",
    ),
  )
}

///|
async test "bridge: emit MoonBit JS FFI bundle handles destructured-const-reference computed-key value exports" {
  let bundle = emit_moonbit_js_ffi_bundle_from_entry_path(
    "fixtures/resolver/project/types/runtime-destructured-const-ref-computed-destructured-value-entry.ts",
    "/runtime/runtime-destructured-const-ref-computed-destructured-value.js",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(bundle.ffi_mbt.contains("pub(all) struct RestMeta"))
  assert_true(bundle.ffi_mbt.contains("  enabled : Bool"))
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn get_runtime_version() -> String = \"__ts_mbt_get_runtime_version\"",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn get_build() -> Double = \"__ts_mbt_get_build\"",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn get_rest_meta() -> RestMeta = \"__ts_mbt_get_rest_meta\"",
    ),
  )
  assert_true(
    bundle.bridge_js.contains(
      "import { build, restMeta, runtimeVersion } from \"/runtime/runtime-destructured-const-ref-computed-destructured-value.js\";",
    ),
  )
  assert_true(
    bundle.bridge_js.contains(
      "export function __ts_mbt_get_rest_meta() { return restMeta; }",
    ),
  )
}

///|
async test "bridge: emit MoonBit JS FFI bundle handles const-object-access computed-key value exports" {
  let bundle = emit_moonbit_js_ffi_bundle_from_entry_path(
    "fixtures/resolver/project/types/runtime-const-object-access-computed-destructured-value-entry.ts",
    "/runtime/runtime-const-object-access-computed-destructured-value.js",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(bundle.ffi_mbt.contains("pub(all) struct RestMeta"))
  assert_true(bundle.ffi_mbt.contains("  enabled : Bool"))
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn get_runtime_version() -> String = \"__ts_mbt_get_runtime_version\"",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn get_build() -> Double = \"__ts_mbt_get_build\"",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn get_rest_meta() -> RestMeta = \"__ts_mbt_get_rest_meta\"",
    ),
  )
  assert_true(
    bundle.bridge_js.contains(
      "import { build, restMeta, runtimeVersion } from \"/runtime/runtime-const-object-access-computed-destructured-value.js\";",
    ),
  )
  assert_true(
    bundle.bridge_js.contains(
      "export function __ts_mbt_get_rest_meta() { return restMeta; }",
    ),
  )
}

///|
async test "bridge: emit MoonBit JS FFI bundle handles nested-const-object-access computed-key value exports" {
  let bundle = emit_moonbit_js_ffi_bundle_from_entry_path(
    "fixtures/resolver/project/types/runtime-nested-const-object-access-computed-destructured-value-entry.ts",
    "/runtime/runtime-nested-const-object-access-computed-destructured-value.js",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(bundle.ffi_mbt.contains("pub(all) struct RestMeta"))
  assert_true(bundle.ffi_mbt.contains("  enabled : Bool"))
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn get_runtime_version() -> String = \"__ts_mbt_get_runtime_version\"",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn get_build() -> Double = \"__ts_mbt_get_build\"",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn get_rest_meta() -> RestMeta = \"__ts_mbt_get_rest_meta\"",
    ),
  )
  assert_true(
    bundle.bridge_js.contains(
      "import { build, restMeta, runtimeVersion } from \"/runtime/runtime-nested-const-object-access-computed-destructured-value.js\";",
    ),
  )
  assert_true(
    bundle.bridge_js.contains(
      "export function __ts_mbt_get_rest_meta() { return restMeta; }",
    ),
  )
}

///|
async test "bridge: emit MoonBit JS FFI bundle handles const-array-access computed-key value exports" {
  let bundle = emit_moonbit_js_ffi_bundle_from_entry_path(
    "fixtures/resolver/project/types/runtime-const-array-access-computed-destructured-value-entry.ts",
    "/runtime/runtime-const-array-access-computed-destructured-value.js",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(bundle.ffi_mbt.contains("pub(all) struct RestMeta"))
  assert_true(bundle.ffi_mbt.contains("  enabled : Bool"))
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn get_runtime_version() -> String = \"__ts_mbt_get_runtime_version\"",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn get_build() -> Double = \"__ts_mbt_get_build\"",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn get_rest_meta() -> RestMeta = \"__ts_mbt_get_rest_meta\"",
    ),
  )
  assert_true(
    bundle.bridge_js.contains(
      "import { build, restMeta, runtimeVersion } from \"/runtime/runtime-const-array-access-computed-destructured-value.js\";",
    ),
  )
  assert_true(
    bundle.bridge_js.contains(
      "export function __ts_mbt_get_rest_meta() { return restMeta; }",
    ),
  )
}

///|
async test "bridge: emit MoonBit JS FFI bundle handles nested-const-array-access computed-key value exports" {
  let bundle = emit_moonbit_js_ffi_bundle_from_entry_path(
    "fixtures/resolver/project/types/runtime-nested-const-array-access-computed-destructured-value-entry.ts",
    "/runtime/runtime-nested-const-array-access-computed-destructured-value.js",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(bundle.ffi_mbt.contains("pub(all) struct RestMeta"))
  assert_true(bundle.ffi_mbt.contains("  enabled : Bool"))
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn get_runtime_version() -> String = \"__ts_mbt_get_runtime_version\"",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn get_build() -> Double = \"__ts_mbt_get_build\"",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn get_rest_meta() -> RestMeta = \"__ts_mbt_get_rest_meta\"",
    ),
  )
  assert_true(
    bundle.bridge_js.contains(
      "import { build, restMeta, runtimeVersion } from \"/runtime/runtime-nested-const-array-access-computed-destructured-value.js\";",
    ),
  )
  assert_true(
    bundle.bridge_js.contains(
      "export function __ts_mbt_get_rest_meta() { return restMeta; }",
    ),
  )
}

///|
async test "bridge: emit MoonBit JS FFI bundle handles const-index-alias computed-key value exports" {
  let bundle = emit_moonbit_js_ffi_bundle_from_entry_path(
    "fixtures/resolver/project/types/runtime-const-index-alias-computed-destructured-value-entry.ts",
    "/runtime/runtime-const-index-alias-computed-destructured-value.js",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(bundle.ffi_mbt.contains("pub(all) struct RestMeta"))
  assert_true(bundle.ffi_mbt.contains("  enabled : Bool"))
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn get_runtime_version() -> String = \"__ts_mbt_get_runtime_version\"",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn get_build() -> Double = \"__ts_mbt_get_build\"",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn get_rest_meta() -> RestMeta = \"__ts_mbt_get_rest_meta\"",
    ),
  )
  assert_true(
    bundle.bridge_js.contains(
      "import { build, restMeta, runtimeVersion } from \"/runtime/runtime-const-index-alias-computed-destructured-value.js\";",
    ),
  )
  assert_true(
    bundle.bridge_js.contains(
      "export function __ts_mbt_get_rest_meta() { return restMeta; }",
    ),
  )
}

///|
async test "bridge: emit MoonBit JS FFI bundle handles const-index-table computed-key value exports" {
  let bundle = emit_moonbit_js_ffi_bundle_from_entry_path(
    "fixtures/resolver/project/types/runtime-const-index-table-computed-destructured-value-entry.ts",
    "/runtime/runtime-const-index-table-computed-destructured-value.js",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(bundle.ffi_mbt.contains("pub(all) struct RestMeta"))
  assert_true(bundle.ffi_mbt.contains("  enabled : Bool"))
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn get_runtime_version() -> String = \"__ts_mbt_get_runtime_version\"",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn get_build() -> Double = \"__ts_mbt_get_build\"",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn get_rest_meta() -> RestMeta = \"__ts_mbt_get_rest_meta\"",
    ),
  )
  assert_true(
    bundle.bridge_js.contains(
      "import { build, restMeta, runtimeVersion } from \"/runtime/runtime-const-index-table-computed-destructured-value.js\";",
    ),
  )
  assert_true(
    bundle.bridge_js.contains(
      "export function __ts_mbt_get_rest_meta() { return restMeta; }",
    ),
  )
}

///|
async test "bridge: emit MoonBit JS FFI bundle handles nested-index-table computed-key value exports" {
  let bundle = emit_moonbit_js_ffi_bundle_from_entry_path(
    "fixtures/resolver/project/types/runtime-nested-index-table-computed-destructured-value-entry.ts",
    "/runtime/runtime-nested-index-table-computed-destructured-value.js",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(bundle.ffi_mbt.contains("pub(all) struct RestMeta"))
  assert_true(bundle.ffi_mbt.contains("  enabled : Bool"))
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn get_runtime_version() -> String = \"__ts_mbt_get_runtime_version\"",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn get_build() -> Double = \"__ts_mbt_get_build\"",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn get_rest_meta() -> RestMeta = \"__ts_mbt_get_rest_meta\"",
    ),
  )
  assert_true(
    bundle.bridge_js.contains(
      "import { build, restMeta, runtimeVersion } from \"/runtime/runtime-nested-index-table-computed-destructured-value.js\";",
    ),
  )
  assert_true(
    bundle.bridge_js.contains(
      "export function __ts_mbt_get_rest_meta() { return restMeta; }",
    ),
  )
}

///|
async test "bridge: emit MoonBit JS FFI bundle handles imported const-table computed-key value exports" {
  let bundle = emit_moonbit_js_ffi_bundle_from_entry_path(
    "fixtures/resolver/project/types/runtime-imported-const-table-entry.ts", "/runtime/runtime-imported-const-table-entry.js",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(bundle.ffi_mbt.contains("pub(all) struct RestMeta"))
  assert_true(bundle.ffi_mbt.contains("  enabled : Bool"))
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn get_runtime_version() -> String = \"__ts_mbt_get_runtime_version\"",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn get_build() -> Double = \"__ts_mbt_get_build\"",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn get_rest_meta() -> RestMeta = \"__ts_mbt_get_rest_meta\"",
    ),
  )
  assert_true(
    bundle.bridge_js.contains(
      "import { build, restMeta, runtimeVersion } from \"/runtime/runtime-imported-const-table-entry.js\";",
    ),
  )
  assert_true(
    bundle.bridge_js.contains(
      "export function __ts_mbt_get_rest_meta() { return restMeta; }",
    ),
  )
}

///|
async test "bridge: emit MoonBit JS FFI bundle handles imported namespace const-table computed-key value exports" {
  let bundle = emit_moonbit_js_ffi_bundle_from_entry_path(
    "fixtures/resolver/project/types/runtime-imported-namespace-const-table-entry.ts",
    "/runtime/runtime-imported-namespace-const-table-entry.js",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(bundle.ffi_mbt.contains("pub(all) struct RestMeta"))
  assert_true(bundle.ffi_mbt.contains("  enabled : Bool"))
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn get_runtime_version() -> String = \"__ts_mbt_get_runtime_version\"",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn get_build() -> Double = \"__ts_mbt_get_build\"",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn get_rest_meta() -> RestMeta = \"__ts_mbt_get_rest_meta\"",
    ),
  )
  assert_true(
    bundle.bridge_js.contains(
      "import { build, restMeta, runtimeVersion } from \"/runtime/runtime-imported-namespace-const-table-entry.js\";",
    ),
  )
  assert_true(
    bundle.bridge_js.contains(
      "export function __ts_mbt_get_rest_meta() { return restMeta; }",
    ),
  )
}

///|
async test "bridge: emit MoonBit JS FFI bundle handles imported default const-table computed-key value exports" {
  let bundle = emit_moonbit_js_ffi_bundle_from_entry_path(
    "fixtures/resolver/project/types/runtime-imported-default-const-table-entry.ts",
    "/runtime/runtime-imported-default-const-table-entry.js",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(bundle.ffi_mbt.contains("pub(all) struct RestMeta"))
  assert_true(bundle.ffi_mbt.contains("  enabled : Bool"))
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn get_runtime_version() -> String = \"__ts_mbt_get_runtime_version\"",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn get_build() -> Double = \"__ts_mbt_get_build\"",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn get_rest_meta() -> RestMeta = \"__ts_mbt_get_rest_meta\"",
    ),
  )
  assert_true(
    bundle.bridge_js.contains(
      "import { build, restMeta, runtimeVersion } from \"/runtime/runtime-imported-default-const-table-entry.js\";",
    ),
  )
  assert_true(
    bundle.bridge_js.contains(
      "export function __ts_mbt_get_rest_meta() { return restMeta; }",
    ),
  )
}

///|
async test "bridge: emit MoonBit JS FFI bundle handles imported inline default const-table computed-key value exports" {
  let bundle = emit_moonbit_js_ffi_bundle_from_entry_path(
    "fixtures/resolver/project/types/runtime-imported-inline-default-const-table-entry.ts",
    "/runtime/runtime-imported-inline-default-const-table-entry.js",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(bundle.ffi_mbt.contains("pub(all) struct RestMeta"))
  assert_true(bundle.ffi_mbt.contains("  enabled : Bool"))
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn get_runtime_version() -> String = \"__ts_mbt_get_runtime_version\"",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn get_build() -> Double = \"__ts_mbt_get_build\"",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn get_rest_meta() -> RestMeta = \"__ts_mbt_get_rest_meta\"",
    ),
  )
  assert_true(
    bundle.bridge_js.contains(
      "import { build, restMeta, runtimeVersion } from \"/runtime/runtime-imported-inline-default-const-table-entry.js\";",
    ),
  )
  assert_true(
    bundle.bridge_js.contains(
      "export function __ts_mbt_get_rest_meta() { return restMeta; }",
    ),
  )
}

///|
async test "bridge: emit MoonBit JS FFI bundle handles imported inline default const-table as const computed-key value exports" {
  let bundle = emit_moonbit_js_ffi_bundle_from_entry_path(
    "fixtures/resolver/project/types/runtime-imported-inline-default-const-table-as-const-entry.ts",
    "/runtime/runtime-imported-inline-default-const-table-as-const-entry.js",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(bundle.ffi_mbt.contains("pub(all) struct RestMeta"))
  assert_true(bundle.ffi_mbt.contains("  enabled : Bool"))
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn get_runtime_version() -> String = \"__ts_mbt_get_runtime_version\"",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn get_build() -> Double = \"__ts_mbt_get_build\"",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn get_rest_meta() -> RestMeta = \"__ts_mbt_get_rest_meta\"",
    ),
  )
  assert_true(
    bundle.bridge_js.contains(
      "import { build, restMeta, runtimeVersion } from \"/runtime/runtime-imported-inline-default-const-table-as-const-entry.js\";",
    ),
  )
  assert_true(
    bundle.bridge_js.contains(
      "export function __ts_mbt_get_rest_meta() { return restMeta; }",
    ),
  )
}

///|
async test "bridge: emit MoonBit JS FFI bundle handles imported iife default const-table computed-key value exports" {
  let bundle = emit_moonbit_js_ffi_bundle_from_entry_path(
    "fixtures/resolver/project/types/runtime-imported-iife-default-const-table-entry.ts",
    "/runtime/runtime-imported-iife-default-const-table-entry.js",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(bundle.ffi_mbt.contains("pub(all) struct RestMeta"))
  assert_true(bundle.ffi_mbt.contains("  enabled : Bool"))
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn get_runtime_version() -> String = \"__ts_mbt_get_runtime_version\"",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn get_build() -> Double = \"__ts_mbt_get_build\"",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn get_rest_meta() -> RestMeta = \"__ts_mbt_get_rest_meta\"",
    ),
  )
  assert_true(
    bundle.bridge_js.contains(
      "import { build, restMeta, runtimeVersion } from \"/runtime/runtime-imported-iife-default-const-table-entry.js\";",
    ),
  )
  assert_true(
    bundle.bridge_js.contains(
      "export function __ts_mbt_get_rest_meta() { return restMeta; }",
    ),
  )
}

///|
async test "bridge: emit MoonBit JS FFI bundle handles imported iife local const-table computed-key value exports" {
  let bundle = emit_moonbit_js_ffi_bundle_from_entry_path(
    "fixtures/resolver/project/types/runtime-imported-iife-local-const-table-entry.ts",
    "/runtime/runtime-imported-iife-local-const-table-entry.js",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(bundle.ffi_mbt.contains("pub(all) struct RestMeta"))
  assert_true(bundle.ffi_mbt.contains("  enabled : Bool"))
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn get_runtime_version() -> String = \"__ts_mbt_get_runtime_version\"",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn get_build() -> Double = \"__ts_mbt_get_build\"",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn get_rest_meta() -> RestMeta = \"__ts_mbt_get_rest_meta\"",
    ),
  )
  assert_true(
    bundle.bridge_js.contains(
      "import { build, restMeta, runtimeVersion } from \"/runtime/runtime-imported-iife-local-const-table-entry.js\";",
    ),
  )
  assert_true(
    bundle.bridge_js.contains(
      "export function __ts_mbt_get_rest_meta() { return restMeta; }",
    ),
  )
}

///|
async test "bridge: emit MoonBit JS FFI bundle handles imported function iife local const-table computed-key value exports" {
  let bundle = emit_moonbit_js_ffi_bundle_from_entry_path(
    "fixtures/resolver/project/types/runtime-imported-function-iife-local-const-table-entry.ts",
    "/runtime/runtime-imported-function-iife-local-const-table-entry.js",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(bundle.ffi_mbt.contains("pub(all) struct RestMeta"))
  assert_true(bundle.ffi_mbt.contains("  enabled : Bool"))
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn get_runtime_version() -> String = \"__ts_mbt_get_runtime_version\"",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn get_build() -> Double = \"__ts_mbt_get_build\"",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn get_rest_meta() -> RestMeta = \"__ts_mbt_get_rest_meta\"",
    ),
  )
  assert_true(
    bundle.bridge_js.contains(
      "import { build, restMeta, runtimeVersion } from \"/runtime/runtime-imported-function-iife-local-const-table-entry.js\";",
    ),
  )
  assert_true(
    bundle.bridge_js.contains(
      "export function __ts_mbt_get_rest_meta() { return restMeta; }",
    ),
  )
}

///|
async test "bridge: emit MoonBit JS FFI bundle handles imported iife local let-table computed-key value exports" {
  let bundle = emit_moonbit_js_ffi_bundle_from_entry_path(
    "fixtures/resolver/project/types/runtime-imported-iife-local-let-table-entry.ts",
    "/runtime/runtime-imported-iife-local-let-table-entry.js",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(bundle.ffi_mbt.contains("pub(all) struct RestMeta"))
  assert_true(bundle.ffi_mbt.contains("  enabled : Bool"))
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn get_runtime_version() -> String = \"__ts_mbt_get_runtime_version\"",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn get_build() -> Double = \"__ts_mbt_get_build\"",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn get_rest_meta() -> RestMeta = \"__ts_mbt_get_rest_meta\"",
    ),
  )
  assert_true(
    bundle.bridge_js.contains(
      "import { build, restMeta, runtimeVersion } from \"/runtime/runtime-imported-iife-local-let-table-entry.js\";",
    ),
  )
  assert_true(
    bundle.bridge_js.contains(
      "export function __ts_mbt_get_rest_meta() { return restMeta; }",
    ),
  )
}

///|
async test "bridge: emit MoonBit JS FFI bundle handles imported function iife local let-table computed-key value exports" {
  let bundle = emit_moonbit_js_ffi_bundle_from_entry_path(
    "fixtures/resolver/project/types/runtime-imported-function-iife-local-let-table-entry.ts",
    "/runtime/runtime-imported-function-iife-local-let-table-entry.js",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(bundle.ffi_mbt.contains("pub(all) struct RestMeta"))
  assert_true(bundle.ffi_mbt.contains("  enabled : Bool"))
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn get_runtime_version() -> String = \"__ts_mbt_get_runtime_version\"",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn get_build() -> Double = \"__ts_mbt_get_build\"",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn get_rest_meta() -> RestMeta = \"__ts_mbt_get_rest_meta\"",
    ),
  )
  assert_true(
    bundle.bridge_js.contains(
      "import { build, restMeta, runtimeVersion } from \"/runtime/runtime-imported-function-iife-local-let-table-entry.js\";",
    ),
  )
  assert_true(
    bundle.bridge_js.contains(
      "export function __ts_mbt_get_rest_meta() { return restMeta; }",
    ),
  )
}

///|
async test "bridge: emit MoonBit JS FFI bundle widens imported reassigned local let-table computed-key value exports" {
  let bundle = emit_moonbit_js_ffi_bundle_from_entry_path(
    "fixtures/resolver/project/types/runtime-imported-iife-reassigned-let-table-entry.ts",
    "/runtime/runtime-imported-iife-reassigned-let-table-entry.js",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_false(bundle.ffi_mbt.contains("pub(all) struct RestMeta"))
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn get_runtime_version() -> JSValue = \"__ts_mbt_get_runtime_version\"",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn get_build() -> JSValue = \"__ts_mbt_get_build\"",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn get_rest_meta() -> JSValue = \"__ts_mbt_get_rest_meta\"",
    ),
  )
  assert_true(
    bundle.bridge_js.contains(
      "import { build, restMeta, runtimeVersion } from \"/runtime/runtime-imported-iife-reassigned-let-table-entry.js\";",
    ),
  )
}

///|
async test "bridge: emit MoonBit JS FFI bundle widens imported prop-mutated local let-table computed-key value exports" {
  let bundle = emit_moonbit_js_ffi_bundle_from_entry_path(
    "fixtures/resolver/project/types/runtime-imported-iife-prop-mutated-let-table-entry.ts",
    "/runtime/runtime-imported-iife-prop-mutated-let-table-entry.js",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_false(bundle.ffi_mbt.contains("pub(all) struct RestMeta"))
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn get_runtime_version() -> JSValue = \"__ts_mbt_get_runtime_version\"",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn get_build() -> JSValue = \"__ts_mbt_get_build\"",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn get_rest_meta() -> JSValue = \"__ts_mbt_get_rest_meta\"",
    ),
  )
  assert_true(
    bundle.bridge_js.contains(
      "import { build, restMeta, runtimeVersion } from \"/runtime/runtime-imported-iife-prop-mutated-let-table-entry.js\";",
    ),
  )
}

///|
async test "bridge: emit MoonBit JS FFI bundle widens imported index-mutated local let-table computed-key value exports" {
  let bundle = emit_moonbit_js_ffi_bundle_from_entry_path(
    "fixtures/resolver/project/types/runtime-imported-function-iife-index-mutated-let-table-entry.ts",
    "/runtime/runtime-imported-function-iife-index-mutated-let-table-entry.js",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_false(bundle.ffi_mbt.contains("pub(all) struct RestMeta"))
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn get_runtime_version() -> JSValue = \"__ts_mbt_get_runtime_version\"",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn get_build() -> JSValue = \"__ts_mbt_get_build\"",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn get_rest_meta() -> JSValue = \"__ts_mbt_get_rest_meta\"",
    ),
  )
  assert_true(
    bundle.bridge_js.contains(
      "import { build, restMeta, runtimeVersion } from \"/runtime/runtime-imported-function-iife-index-mutated-let-table-entry.js\";",
    ),
  )
}

///|
async test "bridge: emit MoonBit JS FFI bundle handles imported reexported const-table computed-key value exports" {
  let bundle = emit_moonbit_js_ffi_bundle_from_entry_path(
    "fixtures/resolver/project/types/runtime-imported-reexported-const-table-entry.ts",
    "/runtime/runtime-imported-reexported-const-table-entry.js",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(bundle.ffi_mbt.contains("pub(all) struct RestMeta"))
  assert_true(bundle.ffi_mbt.contains("  enabled : Bool"))
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn get_runtime_version() -> String = \"__ts_mbt_get_runtime_version\"",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn get_build() -> Double = \"__ts_mbt_get_build\"",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn get_rest_meta() -> RestMeta = \"__ts_mbt_get_rest_meta\"",
    ),
  )
  assert_true(
    bundle.bridge_js.contains(
      "import { build, restMeta, runtimeVersion } from \"/runtime/runtime-imported-reexported-const-table-entry.js\";",
    ),
  )
  assert_true(
    bundle.bridge_js.contains(
      "export function __ts_mbt_get_rest_meta() { return restMeta; }",
    ),
  )
}

///|
async test "bridge: emit MoonBit JS FFI bundle handles imported chained const-table computed-key value exports" {
  let bundle = emit_moonbit_js_ffi_bundle_from_entry_path(
    "fixtures/resolver/project/types/runtime-imported-chained-const-table-entry.ts",
    "/runtime/runtime-imported-chained-const-table-entry.js",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(bundle.ffi_mbt.contains("pub(all) struct RestMeta"))
  assert_true(bundle.ffi_mbt.contains("  enabled : Bool"))
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn get_runtime_version() -> String = \"__ts_mbt_get_runtime_version\"",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn get_build() -> Double = \"__ts_mbt_get_build\"",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn get_rest_meta() -> RestMeta = \"__ts_mbt_get_rest_meta\"",
    ),
  )
  assert_true(
    bundle.bridge_js.contains(
      "import { build, restMeta, runtimeVersion } from \"/runtime/runtime-imported-chained-const-table-entry.js\";",
    ),
  )
  assert_true(
    bundle.bridge_js.contains(
      "export function __ts_mbt_get_rest_meta() { return restMeta; }",
    ),
  )
}

///|
async test "bridge: emit MoonBit JS FFI bundle handles imported star const-table computed-key value exports" {
  let bundle = emit_moonbit_js_ffi_bundle_from_entry_path(
    "fixtures/resolver/project/types/runtime-imported-star-const-table-entry.ts",
    "/runtime/runtime-imported-star-const-table-entry.js",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(bundle.ffi_mbt.contains("pub(all) struct RestMeta"))
  assert_true(bundle.ffi_mbt.contains("  enabled : Bool"))
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn get_runtime_version() -> String = \"__ts_mbt_get_runtime_version\"",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn get_build() -> Double = \"__ts_mbt_get_build\"",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn get_rest_meta() -> RestMeta = \"__ts_mbt_get_rest_meta\"",
    ),
  )
  assert_true(
    bundle.bridge_js.contains(
      "import { build, restMeta, runtimeVersion } from \"/runtime/runtime-imported-star-const-table-entry.js\";",
    ),
  )
  assert_true(
    bundle.bridge_js.contains(
      "export function __ts_mbt_get_rest_meta() { return restMeta; }",
    ),
  )
}

///|
async test "bridge: emit MoonBit JS FFI bundle handles imported deep star const-table computed-key value exports" {
  let bundle = emit_moonbit_js_ffi_bundle_from_entry_path(
    "fixtures/resolver/project/types/runtime-imported-deep-star-const-table-entry.ts",
    "/runtime/runtime-imported-deep-star-const-table-entry.js",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(bundle.ffi_mbt.contains("pub(all) struct RestMeta"))
  assert_true(bundle.ffi_mbt.contains("  enabled : Bool"))
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn get_runtime_version() -> String = \"__ts_mbt_get_runtime_version\"",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn get_build() -> Double = \"__ts_mbt_get_build\"",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn get_rest_meta() -> RestMeta = \"__ts_mbt_get_rest_meta\"",
    ),
  )
  assert_true(
    bundle.bridge_js.contains(
      "import { build, restMeta, runtimeVersion } from \"/runtime/runtime-imported-deep-star-const-table-entry.js\";",
    ),
  )
  assert_true(
    bundle.bridge_js.contains(
      "export function __ts_mbt_get_rest_meta() { return restMeta; }",
    ),
  )
}

///|
async test "bridge: emit MoonBit JS FFI bundle handles imported mixed barrel const-table computed-key value exports" {
  let bundle = emit_moonbit_js_ffi_bundle_from_entry_path(
    "fixtures/resolver/project/types/runtime-imported-mixed-barrel-const-table-entry.ts",
    "/runtime/runtime-imported-mixed-barrel-const-table-entry.js",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(bundle.ffi_mbt.contains("pub(all) struct RestMeta"))
  assert_true(bundle.ffi_mbt.contains("  enabled : Bool"))
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn get_runtime_version() -> String = \"__ts_mbt_get_runtime_version\"",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn get_build() -> Double = \"__ts_mbt_get_build\"",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn get_rest_meta() -> RestMeta = \"__ts_mbt_get_rest_meta\"",
    ),
  )
  assert_true(
    bundle.bridge_js.contains(
      "import { build, restMeta, runtimeVersion } from \"/runtime/runtime-imported-mixed-barrel-const-table-entry.js\";",
    ),
  )
  assert_true(
    bundle.bridge_js.contains(
      "export function __ts_mbt_get_rest_meta() { return restMeta; }",
    ),
  )
}

///|
async test "bridge: emit MoonBit JS FFI bundle widens conflicting star const-table computed-key value exports" {
  let bundle = emit_moonbit_js_ffi_bundle_from_entry_path(
    "fixtures/resolver/project/types/runtime-imported-conflicting-star-const-table-entry.ts",
    "/runtime/runtime-imported-conflicting-star-const-table-entry.js",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_false(bundle.ffi_mbt.contains("pub(all) struct RestMeta"))
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn get_runtime_version() -> JSValue = \"__ts_mbt_get_runtime_version\"",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn get_build() -> JSValue = \"__ts_mbt_get_build\"",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn get_rest_meta() -> JSValue = \"__ts_mbt_get_rest_meta\"",
    ),
  )
  assert_true(
    bundle.bridge_js.contains(
      "import { build, restMeta, runtimeVersion } from \"/runtime/runtime-imported-conflicting-star-const-table-entry.js\";",
    ),
  )
}

///|
async test "bridge: emit MoonBit JS FFI bundle from runtime default exported functions" {
  let bundle = emit_moonbit_js_ffi_bundle_from_entry_path(
    "fixtures/resolver/project/types/runtime-default-function-entry.ts", "/runtime/runtime-default-function.js",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(
    bundle.ffi_mbt.contains(
      "#module(\"/runtime/runtime-default-function.js\")\npub extern \"js\" fn default(label : String) -> String = \"default\"",
    ),
  )
  assert_false(bundle.bridge_js.contains("__ts_mbt_default"))
}

///|
async test "bridge: emit MoonBit JS FFI bundle uses adapter reexport for relative default functions" {
  let bundle = emit_moonbit_js_ffi_bundle_from_entry_path(
    "fixtures/resolver/project/types/runtime-default-function-entry.ts", "./runtime/runtime-default-function.js",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn default(label : String) -> String = \"__ts_mbt_default\"",
    ),
  )
  assert_true(
    bundle.bridge_js.contains(
      "export { default as __ts_mbt_default } from \"./runtime/runtime-default-function.js\";",
    ),
  )
}

///|
async test "bridge: emit MoonBit JS FFI bundle uses adapter reexport for bare default functions" {
  let bundle = emit_moonbit_js_ffi_bundle_from_entry_path(
    "fixtures/resolver/project/types/runtime-default-function-entry.ts", "pkg-default-fn",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn default(label : String) -> String = \"__ts_mbt_default\"",
    ),
  )
  assert_true(
    bundle.bridge_js.contains(
      "export { default as __ts_mbt_default } from \"pkg-default-fn\";",
    ),
  )
}

///|
async test "bridge: emit MoonBit JS FFI bundle uses adapter reexport for parent-relative default functions" {
  let bundle = emit_moonbit_js_ffi_bundle_from_entry_path(
    "fixtures/resolver/project/types/runtime-default-function-entry.ts", "../runtime/runtime-default-function.js",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn default(label : String) -> String = \"__ts_mbt_default\"",
    ),
  )
  assert_true(
    bundle.bridge_js.contains(
      "export { default as __ts_mbt_default } from \"../runtime/runtime-default-function.js\";",
    ),
  )
}

///|
async test "bridge: emit MoonBit JS FFI bundle from runtime default exported classes" {
  let bundle = emit_moonbit_js_ffi_bundle_from_entry_path(
    "fixtures/resolver/project/types/runtime-default-class-entry.ts", "/runtime/runtime-default-class.js",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(bundle.ffi_mbt.contains("#external\npub type Default"))
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn new_default(initial : Double) -> Default = \"__ts_mbt_new_default\"",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn Default::inc(self : Default, delta : Double) -> Double =\n  #| (self, delta) => self.inc(delta)",
    ),
  )
  assert_true(
    bundle.bridge_js.contains(
      "import default_ from \"/runtime/runtime-default-class.js\";",
    ),
  )
  assert_true(
    bundle.bridge_js.contains(
      "export function __ts_mbt_new_default(initial) { return new default_(initial); }",
    ),
  )
  assert_false(bundle.bridge_js.contains("__ts_mbt_default_inc"))
}

///|
async test "bridge: emit MoonBit JS FFI bundle uses adapter helpers for relative default exported classes" {
  let bundle = emit_moonbit_js_ffi_bundle_from_entry_path(
    "fixtures/resolver/project/types/runtime-default-class-entry.ts", "./runtime/runtime-default-class.js",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(bundle.ffi_mbt.contains("#external\npub type Default"))
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn new_default(initial : Double) -> Default = \"__ts_mbt_new_default\"",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn Default::inc(self : Default, delta : Double) -> Double =\n  #| (self, delta) => self.inc(delta)",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn default_from(seed : Double) -> Default = \"__ts_mbt_default_from\"",
    ),
  )
  assert_true(
    bundle.bridge_js.contains(
      "export function __ts_mbt_new_default(initial) { return new default_(initial); }",
    ),
  )
  assert_true(
    bundle.bridge_js.contains(
      "export function __ts_mbt_default_from(seed) { return default_.from(seed); }",
    ),
  )
}

///|
async test "bridge: emit MoonBit JS FFI bundle keeps mixed default class imports on one relative import line" {
  let bundle = emit_moonbit_js_ffi_bundle_from_entry_path(
    "fixtures/resolver/project/types/runtime-default-class-mixed-entry.ts", "../../runtime/runtime-default-class-mixed.js",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(bundle.ffi_mbt.contains("#external\npub type Default"))
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn new_default(initial : Double) -> Default = \"__ts_mbt_new_default\"",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn surround(label : String, prefix : String) -> String = \"__ts_mbt_surround\"",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn get_version() -> String = \"__ts_mbt_get_version\"",
    ),
  )
  assert_true(
    bundle.bridge_js.contains(
      "import default_, { version, surroundMaybe } from \"../../runtime/runtime-default-class-mixed.js\";",
    ),
  )
  assert_true(
    bundle.bridge_js.contains(
      "export { surround as __ts_mbt_surround } from \"../../runtime/runtime-default-class-mixed.js\";",
    ),
  )
  assert_true(
    bundle.bridge_js.contains(
      "export function __ts_mbt_new_default(initial) { return new default_(initial); }",
    ),
  )
  assert_true(
    bundle.bridge_js.contains(
      "export function __ts_mbt_get_version() { return version; }",
    ),
  )
}

///|
async test "bridge: emit MoonBit JS FFI bundle keeps aliased reexports bound to original runtime names" {
  let bundle = emit_moonbit_js_ffi_bundle_from_entry_path(
    "fixtures/resolver/project/types/runtime-default-class-mixed-reexport-entry.ts",
    "../../runtime/runtime-default-class-mixed.js",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(bundle.ffi_mbt.contains("#external\npub type RuntimeCounter"))
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn new_runtime_counter(initial : Double) -> RuntimeCounter = \"__ts_mbt_new_runtime_counter\"",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn decorate(label : String, prefix : String) -> String = \"__ts_mbt_decorate\"",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn get_runtime_version() -> String = \"__ts_mbt_get_runtime_version\"",
    ),
  )
  assert_true(
    bundle.bridge_js.contains(
      "import default_, { version, surroundMaybe } from \"../../runtime/runtime-default-class-mixed.js\";",
    ),
  )
  assert_true(
    bundle.bridge_js.contains(
      "export { surround as __ts_mbt_decorate } from \"../../runtime/runtime-default-class-mixed.js\";",
    ),
  )
  assert_true(
    bundle.bridge_js.contains(
      "export function __ts_mbt_new_runtime_counter(initial) { return new default_(initial); }",
    ),
  )
  assert_true(
    bundle.bridge_js.contains(
      "export function __ts_mbt_get_runtime_version() { return version; }",
    ),
  )
}

///|
async test "bridge: emit MoonBit JS FFI bundle binds bare package aliases to public names" {
  let bundle = emit_moonbit_js_ffi_bundle_from_entry_path(
    "fixtures/resolver/project/types/runtime-default-class-mixed-reexport-entry.ts",
    "pkg-alias",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(
    bundle.ffi_mbt.contains(
      "#module(\"pkg-alias\")\npub extern \"js\" fn decorate(label : String, prefix : String) -> String = \"decorate\"",
    ),
  )
  assert_true(
    bundle.bridge_js.contains(
      "export function __ts_mbt_decorate_maybe(label, prefix) { return decorateMaybe(label, __ts_mbt_unwrap_option(prefix)); }",
    ),
  )
  assert_false(bundle.bridge_js.contains("surround as __ts_mbt_decorate"))
  assert_false(bundle.bridge_js.contains("surroundMaybe"))
}

///|
async test "bridge: emit MoonBit JS FFI bundle does not import type-only aliases" {
  let bundle = emit_moonbit_js_ffi_bundle_from_entry_path(
    "fixtures/resolver/project/types/type-only-alias-value-entry.d.ts", "type-only-alias-value",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(bundle.ffi_mbt.contains("#external\npub type Color"))
  assert_true(
    bundle.bridge_js.contains(
      "import * as __ts_mbt_module from \"type-only-alias-value\";",
    ),
  )
  assert_true(
    bundle.bridge_js.contains(
      "export function __ts_mbt_get_red() { return __ts_mbt_module.red; }",
    ),
  )
  assert_false(bundle.bridge_js.contains("Color"))
}

///|
async test "bridge: emit MoonBit JS FFI bundle does not import export-import type aliases" {
  let bundle = emit_moonbit_js_ffi_bundle_from_entry_path(
    "fixtures/resolver/project/types/type-only-export-import-entry.d.ts", "preact-like",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(
    bundle.ffi_mbt.contains(
      "#module(\"preact-like\")\npub extern \"js\" fn h(type_ : String) -> String = \"h\"",
    ),
  )
  assert_false(bundle.bridge_js.contains("JSX"))
  assert_false(bundle.ffi_mbt.contains("get_jsx"))
}

///|
async test "bridge: emit MoonBit JS FFI bundle from namespace export assignment" {
  let bundle = emit_moonbit_js_ffi_bundle_from_entry_path(
    "fixtures/resolver/project/types/export-equals-entry.d.ts", "./runtime/export-equals.js",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn get_default() -> JSValue = \"__ts_mbt_get_default\"",
    ),
  )
  assert_true(
    bundle.bridge_js.contains(
      "export function __ts_mbt_get_default() { return default_; }",
    ),
  )
}

///|
async test "bridge: emit MoonBit JS FFI bundle imports export-equals namespace members as namespace" {
  let bundle = emit_moonbit_js_ffi_bundle_from_entry_path(
    "fixtures/resolver/project/types/export-equals-namespace-members-entry.d.ts",
    "node:path",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(bundle.bridge_js.contains("import * as path from \"node:path\";"))
  assert_false(bundle.bridge_js.contains("import { path } from \"node:path\";"))
  assert_true(
    bundle.bridge_js.contains("export const __ts_mbt_path_join = path.join;"),
  )
  assert_true(
    bundle.bridge_js.contains(
      "export function __ts_mbt_path_basename(path_, suffix) { return path.basename(path_, __ts_mbt_unwrap_option(suffix)); }",
    ),
  )
  assert_true(
    bundle.bridge_js.contains(
      "export function __ts_mbt_get_path_sep() { return path.sep; }",
    ),
  )
}

///|
async test "bridge: emit MoonBit JS FFI bundle from CJS export-equals namespace members" {
  let bundle = emit_moonbit_js_ffi_bundle_from_entry_path(
    "fixtures/resolver/project/types/cjs-export-equals-entry.d.ts", "./runtime/cjs-export-equals.cjs",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(
    bundle.bridge_js.contains(
      "import default_ from \"./runtime/cjs-export-equals.cjs\";",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn format(label : String) -> String = \"__ts_mbt_format\"",
    ),
  )
  assert_true(
    bundle.bridge_js.contains("export const __ts_mbt_format = default_.format;"),
  )
  assert_true(
    bundle.bridge_js.contains(
      "export function __ts_mbt_get_version() { return default_.version; }",
    ),
  )
}

///|
async test "bridge: omit unique symbol marker value exports from MoonBit JS FFI bundle" {
  let bundle = emit_moonbit_js_ffi_bundle_from_entry_path(
    "fixtures/resolver/project/types/unique-symbol-runtime-export-entry.d.ts", "node:assert",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn ok(value : Bool) -> Unit = \"ok\"",
    ),
  )
  assert_false(bundle.ffi_mbt.contains("kOptions"))
  assert_false(bundle.bridge_js.contains("kOptions"))
  assert_false(bundle.bridge_js.contains("k_options"))
}

///|
async test "bridge: emit MoonBit JS FFI bundle from export-as-namespace assignment" {
  let bundle = emit_moonbit_js_ffi_bundle_from_entry_path(
    "fixtures/resolver/project/types/export-as-namespace-entry.d.ts", "./runtime/react-like.js",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(
    bundle.ffi_mbt.contains(
      "extern \"js\" fn create_context(defaultValue : JSValue) -> Context[JSValue] = \"__ts_mbt_create_context\"",
    ),
  )
  assert_true(bundle.ffi_mbt.contains("pub(all) struct Context[T] {"))
  assert_true(
    bundle.bridge_js.contains(
      "import default_ from \"./runtime/react-like.js\";",
    ),
  )
  assert_true(
    bundle.bridge_js.contains(
      "export const __ts_mbt_create_context = default_.createContext;",
    ),
  )
}

///|
async test "bridge: emit MoonBit JS FFI bundle from exported runtime namespace members" {
  let bundle = emit_moonbit_js_ffi_bundle_from_entry_path(
    "fixtures/resolver/project/types/exported-runtime-namespace-entry.d.ts", "./runtime/runtime-namespace.js",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn task(input : String) -> String",
    ),
  )
  assert_true(bundle.ffi_mbt.contains("pub(all) struct TaskOptions"))
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn task_extra(input : String) -> String = \"__ts_mbt_task_extra\"",
    ),
  )
  assert_true(
    bundle.bridge_js.contains("export const __ts_mbt_task_extra = task.extra;"),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn get_constants_read() -> Double = \"__ts_mbt_get_constants_read\"",
    ),
  )
  assert_true(
    bundle.bridge_js.contains(
      "export function __ts_mbt_get_constants_read() { return constants.read; }",
    ),
  )
  assert_false(bundle.ffi_mbt.contains("Unsupported export task"))
  assert_false(bundle.ffi_mbt.contains("Unsupported export constants"))
}

///|
async test "bridge: emit MoonBit JS FFI bundle keeps bare package namespace members on root imports" {
  let bundle = emit_moonbit_js_ffi_bundle_from_entry_path(
    "fixtures/resolver/project/types/exported-runtime-namespace-entry.d.ts", "runtime-namespace",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(
    bundle.bridge_js.contains(
      "import * as __ts_mbt_module from \"runtime-namespace\";",
    ),
  )
  assert_true(
    bundle.bridge_js.contains("const constants = __ts_mbt_module.constants;"),
  )
  assert_true(
    bundle.bridge_js.contains(
      "export function __ts_mbt_get_constants_read() { return constants.read; }",
    ),
  )
  assert_false(bundle.bridge_js.contains("constantsRead"))
}

///|
async test "bridge: emit MoonBit JS FFI bundle from declaration-merged namespaces" {
  let bundle = emit_moonbit_js_ffi_bundle_from_entry_path(
    "fixtures/resolver/project/types/declaration-merge-namespace-entry.d.ts", "./runtime/declaration-merge-namespace.js",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn make(input : String) -> String",
    ),
  )
  assert_true(bundle.ffi_mbt.contains("pub(all) struct MakeOptions"))
  assert_false(bundle.ffi_mbt.contains("pub(all) struct Options"))
  assert_true(
    bundle.bridge_js.contains(
      "export function __ts_mbt_get_make_version() { return make.version; }",
    ),
  )
  assert_true(
    bundle.bridge_js.contains(
      "export function __ts_mbt_make_with_options(input, options) { return make.withOptions(input, __ts_mbt_to_js_make_options(options)); }",
    ),
  )
  assert_true(bundle.ffi_mbt.contains("#external\npub type Tool"))
  assert_true(bundle.ffi_mbt.contains("pub(all) struct ToolConfig"))
  assert_true(
    bundle.bridge_js.contains(
      "export function __ts_mbt_get_tool_version() { return Tool.version; }",
    ),
  )
  assert_true(
    bundle.bridge_js.contains("export const __ts_mbt_tool_parse = Tool.parse;"),
  )
  assert_true(bundle.ffi_mbt.contains("pub(all) struct Settings"))
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn get_settings() -> Settings = \"__ts_mbt_get_settings\"",
    ),
  )
  assert_true(
    bundle.bridge_js.contains(
      "export function __ts_mbt_get_settings() { return settings; }",
    ),
  )
  assert_true(bundle.ffi_mbt.contains("pub(all) struct SettingsMeta"))
  assert_true(
    bundle.bridge_js.contains(
      "export function __ts_mbt_get_settings_default_mode() { return settings.defaultMode; }",
    ),
  )
  assert_true(
    bundle.bridge_js.contains(
      "export const __ts_mbt_settings_normalize = settings.normalize;",
    ),
  )
  assert_false(bundle.ffi_mbt.contains("Unsupported export make"))
  assert_false(bundle.ffi_mbt.contains("Unsupported export Tool"))
  assert_false(bundle.ffi_mbt.contains("Unsupported export settings"))
}

///|
async test "bridge: emit MoonBit JS FFI bundle from Promise-returning APIs" {
  let bundle = emit_moonbit_js_ffi_bundle_from_entry_path(
    "fixtures/resolver/project/types/promise-return-entry.d.ts", "./runtime/promise-return.js",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn fetch_label(id : String) -> Promise[String] = \"__ts_mbt_fetch_label\"",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn fetch_count() -> Promise[Double] = \"__ts_mbt_fetch_count\"",
    ),
  )
  assert_true(
    bundle.bridge_js.contains(
      "export { fetchLabel as __ts_mbt_fetch_label } from \"./runtime/promise-return.js\";",
    ),
  )
  assert_true(
    bundle.bridge_js.contains(
      "export { fetchCount as __ts_mbt_fetch_count } from \"./runtime/promise-return.js\";",
    ),
  )
  assert_false(
    bundle.ffi_mbt.contains("#warnings(\"-3\")\n#external\npub type Promise\n"),
  )
}

///|
async test "bridge: emit MoonBit JS FFI bundle from callback APIs with synthetic callback types" {
  let bundle = emit_moonbit_js_ffi_bundle_from_entry_path(
    "fixtures/resolver/project/types/callback-entry.d.ts", "./runtime/callback.js",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(
    bundle.ffi_mbt.contains("#external\npub type EmitEventListenerCallback"),
  )
  assert_true(
    bundle.ffi_mbt.contains("#external\npub type MaybeEmitListenerCallback"),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn emit_event(label : String, count : Double, listener : EmitEventListenerCallback) -> String = \"__ts_mbt_emit_event\"",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn maybe_emit(label : String, listener : MaybeEmitListenerCallback?) -> String = \"__ts_mbt_maybe_emit\"",
    ),
  )
  assert_true(bundle.bridge_js.contains("__ts_mbt_emit_event"))
  assert_true(bundle.bridge_js.contains("__ts_mbt_maybe_emit"))
  assert_true(
    bundle.bridge_js.contains(
      "function __ts_mbt_unwrap_option(value) { if (value == null) return undefined; if (typeof value === \"object\" && \"$tag\" in value) return value.$tag === 1 ? value._0 : undefined; return value; }",
    ),
  )
  assert_true(
    bundle.bridge_js.contains(
      "export function __ts_mbt_maybe_emit(label, listener) { return maybeEmit(label, __ts_mbt_unwrap_option(listener)); }",
    ),
  )
  assert_false(bundle.ffi_mbt.contains("Unsupported export emitEvent"))
  assert_false(bundle.ffi_mbt.contains("Unsupported export maybeEmit"))
}

///|
async test "bridge: emit MoonBit JS FFI bundle from export-as-namespace hook tuple members" {
  let bundle = emit_moonbit_js_ffi_bundle_from_entry_path(
    "fixtures/resolver/project/types/export-as-namespace-hook-tuple-entry.d.ts",
    "./runtime/react-like.js",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(bundle.ffi_mbt.contains("pub(all) struct UseStateResult"))
  assert_true(bundle.ffi_mbt.contains("  state : JSValue"))
  assert_true(bundle.ffi_mbt.contains("  setState : Dispatch"))
  assert_true(bundle.ffi_mbt.contains("pub(all) struct UseReducerResult"))
  assert_true(bundle.ffi_mbt.contains("  state : JSValue"))
  assert_true(bundle.ffi_mbt.contains("  dispatch : ActionDispatch"))
  assert_true(bundle.ffi_mbt.contains("pub(all) struct UseTransitionResult"))
  assert_true(bundle.ffi_mbt.contains("  isPending : Bool"))
  assert_true(bundle.ffi_mbt.contains("  startTransition : TransitionFunction"))
  assert_true(bundle.ffi_mbt.contains("pub(all) struct UseOptimisticResult"))
  assert_true(bundle.ffi_mbt.contains("  state : State"))
  assert_true(bundle.ffi_mbt.contains("  dispatch : (State) -> Unit"))
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn UseOptimisticResult::dispatch(self : UseOptimisticResult, arg0 : State) -> Unit =\n  #| (self, arg0) => self.dispatch(arg0)",
    ),
  )
  assert_true(bundle.ffi_mbt.contains("pub(all) struct UseActionStateResult"))
  assert_true(bundle.ffi_mbt.contains("  state : State"))
  assert_true(bundle.ffi_mbt.contains("  dispatch : () -> Unit"))
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn UseActionStateResult::dispatch(self : UseActionStateResult) -> Unit =\n  #| (self) => self.dispatch()",
    ),
  )
  assert_true(bundle.ffi_mbt.contains("  isPending : Bool"))
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn use_state(initialState : JSValue) -> UseStateResult = \"__ts_mbt_use_state\"",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn use_reducer(reducer : UseReducerReducerCallback, initialState : JSValue) -> UseReducerResult = \"__ts_mbt_use_reducer\"",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn use_transition() -> UseTransitionResult = \"__ts_mbt_use_transition\"",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn use_optimistic(passthrough : State) -> UseOptimisticResult = \"__ts_mbt_use_optimistic\"",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn use_action_state(action : UseActionStateActionCallback, initialState : State, permalink : String?) -> UseActionStateResult = \"__ts_mbt_use_action_state\"",
    ),
  )
  assert_true(
    bundle.bridge_js.contains(
      "export function __ts_mbt_use_state(initialState) { const tuple_ = default_.useState(initialState); return { state: tuple_[0], setState: tuple_[1] }; }",
    ),
  )
  assert_true(
    bundle.bridge_js.contains(
      "export function __ts_mbt_use_reducer(reducer, initialState) { const tuple_ = default_.useReducer(reducer, initialState); return { state: tuple_[0], dispatch: tuple_[1] }; }",
    ),
  )
  assert_true(
    bundle.bridge_js.contains(
      "export function __ts_mbt_use_transition() { const tuple_ = default_.useTransition(); return { isPending: tuple_[0], startTransition: tuple_[1] }; }",
    ),
  )
  assert_true(
    bundle.bridge_js.contains(
      "export function __ts_mbt_use_optimistic(passthrough) { const tuple_ = default_.useOptimistic(passthrough); return { state: tuple_[0], dispatch: tuple_[1] }; }",
    ),
  )
  assert_true(
    bundle.bridge_js.contains(
      "export function __ts_mbt_use_action_state(action, initialState, permalink) { const tuple_ = default_.useActionState(action, initialState, __ts_mbt_unwrap_option(permalink)); return { state: tuple_[0], dispatch: tuple_[1], isPending: tuple_[2] }; }",
    ),
  )
}

///|
async test "bridge: emit MoonBit JS FFI bundle from export-as-namespace JSX namespace members" {
  let bundle = emit_moonbit_js_ffi_bundle_from_entry_path(
    "fixtures/resolver/project/types/export-as-namespace-jsx-entry.d.ts", "./runtime/react-like.js",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(bundle.ffi_mbt.contains("pub(all) struct JsxElement"))
  assert_true(bundle.ffi_mbt.contains("  kind : String"))
  assert_true(bundle.ffi_mbt.contains("pub(all) struct JsxIntrinsicElements"))
  assert_true(bundle.ffi_mbt.contains("  badge : BadgeProps"))
  assert_true(
    bundle.ffi_mbt.contains("pub(all) struct JsxLibraryManagedAttributes"),
  )
  assert_true(
    bundle.ffi_mbt.contains("pub(all) struct JsxLibraryManagedAttributes[C, P]"),
  )
  assert_true(bundle.ffi_mbt.contains("  props : P"))
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn create_element(tag : String) -> JsxElement = \"__ts_mbt_create_element\"",
    ),
  )
  assert_true(
    bundle.bridge_js.contains(
      "export const __ts_mbt_create_element = default_.createElement;",
    ),
  )
}

///|
async test "bridge: emit MoonBit JS FFI bundle from exported JSX namespace members" {
  let bundle = emit_moonbit_js_ffi_bundle_from_entry_path(
    "fixtures/resolver/project/types/exported-jsx-namespace-entry.d.ts", "react/jsx-runtime",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(bundle.ffi_mbt.contains("pub(all) struct JsxElement"))
  assert_true(bundle.ffi_mbt.contains("pub(all) struct JsxIntrinsicElements"))
  assert_true(
    bundle.ffi_mbt.contains("pub(all) struct JsxLibraryManagedAttributes"),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn jsx(tag : String, props : BadgeProps) -> JsxElement = \"jsx\"",
    ),
  )
  assert_false(bundle.ffi_mbt.contains("fn get_jsx()"))
  assert_false(bundle.bridge_js.contains("__ts_mbt_get_jsx"))
}

///|
async test "bridge: emit MoonBit JS FFI bundle from export-as-namespace PropsWithChildren members" {
  let bundle = emit_moonbit_js_ffi_bundle_from_entry_path(
    "fixtures/resolver/project/types/export-as-namespace-props-with-children-entry.d.ts",
    "./runtime/react-like.js",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(bundle.ffi_mbt.contains("pub(all) struct BadgePropsWithChildren"))
  assert_true(bundle.ffi_mbt.contains("  label : String"))
  assert_true(bundle.ffi_mbt.contains("  children : JSValue"))
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn create_badge(props : BadgePropsWithChildren) -> BadgePropsWithChildren = \"__ts_mbt_create_badge\"",
    ),
  )
  assert_false(bundle.ffi_mbt.contains("pub type PropsWithChildren"))
  assert_true(
    bundle.bridge_js.contains(
      "export const __ts_mbt_create_badge = default_.createBadge;",
    ),
  )
}

///|
async test "bridge: emit MoonBit JS FFI bundle from export-as-namespace ComponentProps members" {
  let bundle = emit_moonbit_js_ffi_bundle_from_entry_path(
    "fixtures/resolver/project/types/export-as-namespace-component-props-entry.d.ts",
    "./runtime/react-like.js",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(bundle.ffi_mbt.contains("pub(all) struct BadgeProps"))
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn create_badge(props : BadgeProps) -> BadgeProps = \"__ts_mbt_create_badge\"",
    ),
  )
  assert_false(bundle.ffi_mbt.contains("pub type ComponentProps"))
  assert_true(
    bundle.bridge_js.contains(
      "export const __ts_mbt_create_badge = default_.createBadge;",
    ),
  )
}

///|
async test "bridge: emit MoonBit JS FFI bundle lowers Pick and Omit utility types" {
  let bundle = emit_moonbit_js_ffi_bundle_from_entry_path(
    "fixtures/resolver/project/types/utility-pick-omit-entry.d.ts", "./runtime/utility.js",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(bundle.ffi_mbt.contains("pub(all) struct UserPickIdName"))
  assert_true(bundle.ffi_mbt.contains("pub(all) struct InlineMapped"))
  assert_true(bundle.ffi_mbt.contains("  id : String?"))
  assert_true(bundle.ffi_mbt.contains("  name : String?"))
  assert_true(bundle.ffi_mbt.contains("pub(all) struct UserPickIdActive"))
  assert_true(bundle.ffi_mbt.contains("  active : Bool?"))
  assert_true(bundle.ffi_mbt.contains("pub(all) struct UserOmitAge"))
  assert_true(bundle.ffi_mbt.contains("pub(all) struct UserOmitActive"))
  assert_true(bundle.ffi_mbt.contains("pub(all) struct UserPartial"))
  assert_true(bundle.ffi_mbt.contains("  age : Double?"))
  assert_true(bundle.ffi_mbt.contains("pub(all) struct UserReadonly"))
  assert_true(
    bundle.ffi_mbt.contains(
      "  // readonly in TypeScript; not enforced by generated MoonBit struct",
    ),
  )
  assert_true(bundle.ffi_mbt.contains("pub(all) struct UserRequired"))
  assert_true(bundle.ffi_mbt.contains("  active : Bool"))
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn pick_user(user : UserPickIdName) -> UserPickIdActive = \"__ts_mbt_pick_user\"",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn omit_user(user : UserOmitAge) -> UserOmitActive = \"__ts_mbt_omit_user\"",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn patch_user(user : UserPartial) -> UserPartial = \"__ts_mbt_patch_user\"",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn readonly_user(user : UserReadonly) -> UserReadonly = \"__ts_mbt_readonly_user\"",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn required_user(user : UserRequired) -> UserRequired = \"__ts_mbt_required_user\"",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn require_user(id : String) -> User = \"__ts_mbt_require_user\"",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn extract_user(user : User) -> User = \"__ts_mbt_extract_user\"",
    ),
  )
  assert_true(bundle.ffi_mbt.contains("pub(all) struct GetArgsResult"))
  assert_true(bundle.ffi_mbt.contains("  _0 : String"))
  assert_true(bundle.ffi_mbt.contains("  _1 : Bool"))
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn get_count() -> Double = \"__ts_mbt_get_count\"",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn get_args() -> GetArgsResult = \"__ts_mbt_get_args\"",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn get_static_conditional_true() -> Double = \"__ts_mbt_get_static_conditional_true\"",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn get_static_conditional_false() -> Bool = \"__ts_mbt_get_static_conditional_false\"",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn get_awaited_name() -> String = \"__ts_mbt_get_awaited_name\"",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn get_inferred_promise_name() -> String = \"__ts_mbt_get_inferred_promise_name\"",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn get_generic_inferred_promise_name() -> String = \"__ts_mbt_get_generic_inferred_promise_name\"",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn get_inline_mapped() -> InlineMapped = \"__ts_mbt_get_inline_mapped\"",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains("#external\npub type StringRecordOfString"),
  )
  assert_true(
    bundle.ffi_mbt.contains("#external\npub type StringRecordOfStringOrDouble"),
  )
  assert_true(bundle.ffi_mbt.contains("#external\npub type StringRecordOfUser"))
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn get_labels() -> StringRecordOfString = \"__ts_mbt_get_labels\"",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn set_labels(labels : StringRecordOfStringOrDouble) -> Unit = \"__ts_mbt_set_labels\"",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn get_users_by_id() -> StringRecordOfUser = \"__ts_mbt_get_users_by_id\"",
    ),
  )
  assert_true(bundle.ffi_mbt.contains("#external\npub type UtilityError"))
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn new_utility_error(issues : Array[User]) -> UtilityError = \"__ts_mbt_new_utility_error\"",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn UtilityError::get_utility_error_issues(self : UtilityError) -> Array[User]",
    ),
  )
  assert_false(bundle.ffi_mbt.contains("JSValue"))
  assert_false(bundle.ffi_mbt.contains("#external\npub type Pick"))
  assert_false(bundle.ffi_mbt.contains("#external\npub type Omit"))
  assert_false(bundle.ffi_mbt.contains("#external\npub type Record"))
  assert_false(bundle.ffi_mbt.contains("#external\npub type NonNullable"))
  assert_false(bundle.ffi_mbt.contains("#external\npub type Extract"))
  assert_false(bundle.ffi_mbt.contains("#external\npub type Exclude"))
  assert_false(bundle.ffi_mbt.contains("#external\npub type ReturnType"))
  assert_false(bundle.ffi_mbt.contains("#external\npub type Parameters"))
  assert_false(bundle.ffi_mbt.contains("#external\npub type Partial"))
  assert_false(bundle.ffi_mbt.contains("#external\npub type Readonly"))
  assert_false(bundle.ffi_mbt.contains("#external\npub type Required"))
  assert_false(bundle.ffi_mbt.contains("#external\npub type Awaited"))
  assert_false(
    bundle.ffi_mbt.contains("#warnings(\"-3\")\n#external\npub type Promise\n"),
  )
  assert_false(bundle.ffi_mbt.contains("#external\npub type UnwrapPromise"))
}

///|
async test "bridge: emit MoonBit JS FFI bundle from export-as-namespace ComponentPropsWithoutRef members" {
  let bundle = emit_moonbit_js_ffi_bundle_from_entry_path(
    "fixtures/resolver/project/types/export-as-namespace-component-props-without-ref-entry.d.ts",
    "./runtime/react-like.js",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(bundle.ffi_mbt.contains("pub(all) struct BadgeProps"))
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn create_badge(props : BadgeProps) -> BadgeProps = \"__ts_mbt_create_badge\"",
    ),
  )
  assert_false(bundle.ffi_mbt.contains("pub type ComponentPropsWithoutRef"))
}

///|
async test "bridge: emit MoonBit JS FFI bundle from export-as-namespace ComponentPropsWithRef members" {
  let bundle = emit_moonbit_js_ffi_bundle_from_entry_path(
    "fixtures/resolver/project/types/export-as-namespace-component-props-with-ref-entry.d.ts",
    "./runtime/react-like.js",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(bundle.ffi_mbt.contains("pub(all) struct BadgePropsWithRef"))
  assert_true(bundle.ffi_mbt.contains("  label : String"))
  assert_true(bundle.ffi_mbt.contains("  ref_ : Ref"))
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn create_badge(props : BadgePropsWithRef) -> BadgePropsWithRef = \"__ts_mbt_create_badge\"",
    ),
  )
  assert_false(bundle.ffi_mbt.contains("pub type ComponentPropsWithRef"))
}

///|
async test "bridge: emit MoonBit JS FFI bundle from export-as-namespace nested PropsWithChildren members" {
  let bundle = emit_moonbit_js_ffi_bundle_from_entry_path(
    "fixtures/resolver/project/types/export-as-namespace-nested-props-with-children-entry.d.ts",
    "./runtime/react-like.js",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(bundle.ffi_mbt.contains("pub(all) struct BadgePropsWithChildren"))
  assert_true(bundle.ffi_mbt.contains("  label : String"))
  assert_true(bundle.ffi_mbt.contains("  children : JSValue"))
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn create_badge(props : BadgePropsWithChildren) -> BadgePropsWithChildren = \"__ts_mbt_create_badge\"",
    ),
  )
  assert_false(bundle.ffi_mbt.contains("pub type PropsWithChildren"))
  assert_false(bundle.ffi_mbt.contains("pub type ComponentPropsWithoutRef"))
}

///|
async test "bridge: emit MoonBit JS FFI bundle from export-as-namespace PropsWithoutRef and PropsWithRef members" {
  let bundle = emit_moonbit_js_ffi_bundle_from_entry_path(
    "fixtures/resolver/project/types/export-as-namespace-props-ref-alias-entry.d.ts",
    "./runtime/react-like.js",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(bundle.ffi_mbt.contains("pub(all) struct BadgeProps"))
  assert_true(bundle.ffi_mbt.contains("pub(all) struct BadgePropsWithChildren"))
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn strip_ref(props : BadgeProps) -> BadgeProps = \"__ts_mbt_strip_ref\"",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn keep_ref(props : BadgeProps) -> BadgeProps = \"__ts_mbt_keep_ref\"",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn nested() -> BadgePropsWithChildren = \"__ts_mbt_nested\"",
    ) ||
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn nested(props : BadgePropsWithChildren) -> BadgePropsWithChildren = \"__ts_mbt_nested\"",
    ),
  )
  assert_false(bundle.ffi_mbt.contains("pub type PropsWithoutRef"))
  assert_false(bundle.ffi_mbt.contains("pub type PropsWithRef"))
}

///|
async test "bridge: emit MoonBit JS FFI bundle from export-as-namespace optional React-like fields" {
  let bundle = emit_moonbit_js_ffi_bundle_from_entry_path(
    "fixtures/resolver/project/types/export-as-namespace-optional-react-fields-entry.d.ts",
    "./runtime/react-like.js",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(bundle.ffi_mbt.contains("pub(all) struct BadgeProps"))
  assert_true(bundle.ffi_mbt.contains("  label : String?"))
  assert_true(bundle.ffi_mbt.contains("  children : JSValue?"))
  assert_true(bundle.ffi_mbt.contains("  ref_ : Ref[JSValue]?"))
  assert_true(
    bundle.ffi_mbt.contains(
      "extern \"js\" fn render_badge(props : BadgeProps) -> BadgeProps = \"__ts_mbt_render_badge\"",
    ),
  )
}

///|
async test "bridge: emit MoonBit JS FFI bundle from exported jsx-dev-runtime signatures" {
  let bundle = emit_moonbit_js_ffi_bundle_from_entry_path(
    "fixtures/resolver/project/types/exported-jsx-dev-runtime-entry.d.ts", "react/jsx-dev-runtime",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(bundle.ffi_mbt.contains("pub(all) struct JSXSource"))
  assert_true(bundle.ffi_mbt.contains("  fileName : String?"))
  assert_true(bundle.ffi_mbt.contains("  lineNumber : Double?"))
  assert_true(bundle.ffi_mbt.contains("  columnNumber : Double?"))
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn jsx_dev(type_ : ElementType, props : JSValue, key : Key?, isStatic : Bool, source : JSXSource?, self : JSValue?) -> ReactElement = \"__ts_mbt_jsx_dev\"",
    ),
  )
  assert_true(
    bundle.bridge_js.contains(
      "export function __ts_mbt_jsx_dev(type_, props, key, isStatic, source, self) { return jsxDEV(type_, props, __ts_mbt_unwrap_option(key), isStatic, __ts_mbt_to_js_jsxsource(source), __ts_mbt_unwrap_option(self)); }",
    ),
  )
}

///|
async test "bridge: emit MoonBit JS FFI bundle from export-as-namespace inline PropsWithChildren members" {
  let bundle = emit_moonbit_js_ffi_bundle_from_entry_path(
    "fixtures/resolver/project/types/export-as-namespace-inline-props-with-children-entry.d.ts",
    "./runtime/react-like.js",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(
    bundle.ffi_mbt.contains("pub(all) struct LabelCountPropsWithChildren"),
  )
  assert_true(bundle.ffi_mbt.contains("  label : String"))
  assert_true(bundle.ffi_mbt.contains("  count : Double"))
  assert_true(bundle.ffi_mbt.contains("  children : JSValue"))
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn create_badge(props : LabelCountPropsWithChildren) -> LabelCountPropsWithChildren = \"__ts_mbt_create_badge\"",
    ),
  )
  assert_false(bundle.ffi_mbt.contains("pub type PropsWithChildren"))
}

///|
async test "bridge: emit MoonBit JS FFI bundle sanitizes reserved exported function and parameter names" {
  let bundle = emit_moonbit_js_ffi_bundle_from_entry_path(
    "fixtures/resolver/project/types/export-as-namespace-sanitize-entry.d.ts", "./runtime/react-like.js",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(bundle.ffi_mbt.contains("pub(all) struct Props"))
  assert_true(bundle.ffi_mbt.contains("  type_ : String"))
  assert_true(bundle.ffi_mbt.contains("  ref_ : String"))
  assert_true(bundle.ffi_mbt.contains("pub(all) struct ReactElement"))
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn jsx(type_ : String, props : Props) -> ReactElement = \"__ts_mbt_jsx\"",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn use_(promise : Promise[String]) -> String = \"__ts_mbt_use\"",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn forward_ref(component : JSValue) -> JSValue = \"__ts_mbt_forward_ref\"",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn use_action_state(fn_ : JSValue, initialState : String, permalink : String) -> String = \"__ts_mbt_use_action_state\"",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn fragment(children : String) -> ReactElement = \"__ts_mbt_fragment\"",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn strict_mode(children : String) -> ReactElement = \"__ts_mbt_strict_mode\"",
    ),
  )
  assert_false(bundle.ffi_mbt.contains("fn use("))
  assert_false(bundle.ffi_mbt.contains("Component :"))
  assert_false(bundle.ffi_mbt.contains("fn :"))
}

///|
async test "bridge: emit MoonBit JS FFI bundle from imported object type alias members" {
  let bundle = emit_moonbit_js_ffi_bundle_from_entry_path(
    "fixtures/resolver/project/types/hono-options-entry.d.ts", "./runtime/hono.js",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  // The bridge preserves `HonoOptions<E>`'s type param. With `E` widened
  // to `JSValue` at the function call site, `bindings : E?` becomes the
  // generic type parameter and the call site sees `HonoOptions[JSValue]`.
  assert_true(bundle.ffi_mbt.contains("pub(all) struct HonoOptions[E] {"))
  assert_true(bundle.ffi_mbt.contains("  strict : Bool?"))
  assert_true(bundle.ffi_mbt.contains("  bindings : E?"))
  // `class Hono<E>` is now generic-preserved on the FFI side, so
  // `new_hono` is emitted as a 2-decl shim: a JSValue-erased extern
  // `_new_hono_extern_js` plus a generic public wrapper that
  // `unsafeCast`s through it.
  assert_true(
    bundle.ffi_mbt.contains(
      "extern \"js\" fn _new_hono_extern_js(options : JSValue) -> JSValue = \"__ts_mbt_new_hono\"",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub fn[E] new_hono(options : HonoOptions[E]?) -> Hono[E] {",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "extern \"js\" fn create_app(options : HonoOptions[JSValue]) -> Hono[JSValue] = \"__ts_mbt_create_app\"",
    ),
  )
}

///|
async test "bridge: emit MoonBit JS FFI bundle converts literal option fields before JS calls" {
  let bundle = emit_moonbit_js_ffi_bundle_from_entry_path(
    "fixtures/bridge_smoke/realworld-literal-options-entry.d.ts", "./runtime/realworld-literal-options.js",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(bundle.ffi_mbt.contains("  encoding : NodeEncoding?"))
  assert_true(bundle.ffi_mbt.contains("  flag : NodeFlag?"))
  assert_true(bundle.ffi_mbt.contains("  type_ : ReactButtonType?"))
  assert_true(bundle.ffi_mbt.contains("  mode : HonoMode?"))
  assert_true(
    bundle.bridge_js.contains(
      "field = __ts_mbt_bridge_node_encoding_to_js_optional(field);",
    ),
  )
  assert_true(
    bundle.bridge_js.contains(
      "field = __ts_mbt_bridge_node_flag_to_js_optional(field);",
    ),
  )
  assert_true(
    bundle.bridge_js.contains(
      "field = __ts_mbt_bridge_react_button_type_to_js_optional(field);",
    ),
  )
  assert_true(
    bundle.bridge_js.contains(
      "field = __ts_mbt_bridge_hono_mode_to_js_optional(field);",
    ),
  )
}

///|
async test "bridge: emit MoonBit JS FFI bundle names anonymous literal unions" {
  let bundle = emit_moonbit_js_ffi_bundle_from_entry_path(
    "fixtures/resolver/project/types/literal-union-entry.d.ts", "./runtime/literal-union.js",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_false(bundle.ffi_mbt.contains("#external\npub type JSValue"))
  assert_true(bundle.ffi_mbt.contains("pub(all) enum ButtonOptionsVariant"))
  assert_true(bundle.ffi_mbt.contains("pub(all) enum RenderButtonVariant"))
  assert_true(bundle.ffi_mbt.contains("pub(all) enum RenderButtonReturn"))
  assert_true(bundle.ffi_mbt.contains("  variant : ButtonOptionsVariant?"))
  assert_true(bundle.ffi_mbt.contains("  disabled : Bool?"))
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn render_button(variant : String, options : ButtonOptions?) -> String = \"__ts_mbt_render_button\"",
    ),
  )
}

///|
async test "bridge: emit MoonBit JS FFI bundle names anonymous string literal unions with unsafe case names" {
  let bundle = emit_moonbit_js_ffi_bundle_from_entry_path(
    "fixtures/resolver/project/types/anonymous-string-literal-union-entry.d.ts",
    "./runtime/literal-union.js",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_false(bundle.ffi_mbt.contains("#external\npub type JSValue"))
  assert_true(bundle.ffi_mbt.contains("pub(all) enum OrderedListPropsType"))
  assert_true(
    bundle.ffi_mbt.contains("pub(all) enum OrderedListPropsSetModeArg0"),
  )
  assert_true(bundle.ffi_mbt.contains("pub(all) enum SetListTypeType"))
  assert_true(bundle.ffi_mbt.contains("pub(all) enum SetListTypeReturn"))
  assert_true(bundle.ffi_mbt.contains("  type_ : OrderedListPropsType?"))
  assert_true(bundle.ffi_mbt.contains("  setMode : (String) -> Unit"))
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn set_list_type(type_ : String) -> String = \"__ts_mbt_set_list_type\"",
    ),
  )
}

///|
async test "bridge: emit MoonBit JS FFI bundle from fixture React package surface" {
  let bundle = emit_moonbit_js_ffi_bundle_from_entry_path(
    "fixtures/resolver/project/node_modules/react/index.d.ts", "react",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(bundle.ffi_mbt.contains("#external\npub type FunctionComponent"))
  assert_true(
    bundle.ffi_mbt.contains("#external\npub type NamedExoticComponent"),
  )
  assert_true(
    bundle.ffi_mbt.contains("#external\npub type ForwardRefExoticComponent"),
  )
  assert_true(
    bundle.ffi_mbt.contains("#external\npub type MemoExoticComponent"),
  )
  assert_false(bundle.ffi_mbt.contains("pub(all) struct FunctionComponent"))
  assert_true(
    bundle.ffi_mbt.contains(
      "extern \"js\" fn create_element(type_ : String, props : DOMAttributes?, children : Array[JSValue]) -> ReactElement[DOMAttributes, String] = \"__ts_mbt_create_element\"",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "extern \"js\" fn clone_element(element : ReactElement[JSValue, JSValue], props : DOMAttributesPartial?, children : Array[JSValue]) -> ReactElement[JSValue, JSValue] = \"__ts_mbt_clone_element\"",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "extern \"js\" fn forward_ref(render : ForwardRefRenderCallback) -> ForwardRefExoticComponent[JSValue] = \"__ts_mbt_forward_ref\"",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn memo(component : FunctionComponent[JSValue], propsAreEqual : MemoPropsAreEqualCallback?) -> MemoExoticComponent[FunctionComponent[JSValue]] = \"__ts_mbt_memo\"",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "extern \"js\" fn normalize_props(props : ButtonHTMLAttributes) -> ButtonHTMLAttributes = \"__ts_mbt_normalize_props\"",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "extern \"js\" fn use_component_ref(ref_ : Ref[JSValue]) -> Ref[JSValue] = \"__ts_mbt_use_component_ref\"",
    ),
  )
  assert_false(bundle.ffi_mbt.contains("props : JSValue?"))
}

///|
async test "bridge: JS FFI keeps function-field enum interfaces pass-through" {
  let bundle = emit_moonbit_js_ffi_bundle_from_entry_path(
    "fixtures/resolver/project/types/function-field-enum-entry.d.ts", "./runtime/function-field-enum.js",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(bundle.ffi_mbt.contains("pub(all) struct Context"))
  assert_true(bundle.ffi_mbt.contains("handle : (Int) -> Unit"))
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn visit(context : Context) -> Unit = \"__ts_mbt_visit\"",
    ),
  )
  assert_false(bundle.bridge_js.contains("__ts_mbt_to_js_context"))
}

///|
async test "bridge: emit MoonBit JS FFI bundle expands callable interface inheritance" {
  let bundle = emit_moonbit_js_ffi_bundle_from_entry_path(
    "fixtures/resolver/project/types/callable-interface-reexport-entry.d.ts", "./runtime/expect.js",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(bundle.ffi_mbt.contains("pub(all) struct ExpectStatic"))
  assert_true(bundle.ffi_mbt.contains("pub(all) struct Assertion[T]"))
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn ExpectStatic::_call_(self : ExpectStatic",
    ),
  )
  // Generic-preserved receivers can't host `extern "js"` methods (MoonBit
  // forbids `extern "js" fn[T]`), so the FFI emits a pure-MoonBit wrapper
  // that calls the underlying function field directly.
  assert_true(
    bundle.ffi_mbt.contains("pub fn[T] Assertion::toBe(self : Assertion[T]"),
  )
  assert_true(
    bundle.ffi_mbt.contains("pub fn[T] Assertion::toEqual(self : Assertion[T]"),
  )
}

///|
async test "bridge: emit MoonBit JS FFI bundle from fixture React JSX runtime package subpath" {
  let bundle = emit_moonbit_js_ffi_bundle_from_entry_path(
    "fixtures/resolver/project/node_modules/react/jsx-runtime.d.ts", "react/jsx-runtime",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(bundle.ffi_mbt.contains("pub(all) struct JsxElement"))
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn jsx(type_ : String, props : ButtonHTMLAttributes, key : Key?) -> ReactElement = \"__ts_mbt_jsx\"",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn jsxs(type_ : String, props : ButtonHTMLAttributes, key : Key?) -> ReactElement = \"__ts_mbt_jsxs\"",
    ),
  )
  assert_true(
    bundle.bridge_js.contains(
      "export function __ts_mbt_jsx(type_, props, key) { return jsx(type_, __ts_mbt_to_js_button_htmlattributes(props), __ts_mbt_unwrap_option(key)); }",
    ),
  )
  assert_true(
    bundle.bridge_js.contains(
      "export function __ts_mbt_jsxs(type_, props, key) { return jsxs(type_, __ts_mbt_to_js_button_htmlattributes(props), __ts_mbt_unwrap_option(key)); }",
    ),
  )
}

///|
async test "bridge: emit MoonBit JS FFI bundle from fixture Hono JSX package subpath" {
  let bundle = emit_moonbit_js_ffi_bundle_from_entry_path(
    "fixtures/resolver/project/node_modules/hono/dist/types/jsx/index.d.ts", "hono/jsx",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(bundle.ffi_mbt.contains("pub(all) struct JsxElement"))
  assert_true(bundle.ffi_mbt.contains("pub(all) struct ButtonAttributes"))
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn jsx(tag : String, props : ButtonAttributes) -> JsxElement = \"__ts_mbt_jsx\"",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn memo(component : MemoComponentCallback) -> (JSValue) -> JsxElement = \"memo\"",
    ),
  )
}

///|
test "bridge: FFI struct generation deduplicates sanitized field names" {
  let state : MoonBitJsFfiState = {
    declared_type_names: [],
    struct_type_names: [],
    generic_type_params_by_name: {},
    enums: [],
    external_type_names: [],
    local_type_param_names: [],
    function_field_method_wrapper_limit: ffi_function_field_method_wrapper_limit,
    tagged_union_decls_by_name: {},
    synthesized_inline_unions: {},
    needs_js_any: false,
    needs_promise: false,
  }
  let iface : @ast.TsInterface = {
    name: "GenericDateConstructor",
    type_params: [],
    extends_names: [],
    fields: [
      ("<new>", @ast.TsType::Named("DateType")),
      ("<new>", @ast.TsType::Named("DateType")),
      ("<new>", @ast.TsType::Named("DateType")),
    ],
    readonly_fields: [],
    index_signatures: [],
  }
  let actual = ffi_struct_decl_to_moonbit(state, iface)
  assert_eq(count_occurrences_in_ffi_output(actual, "  _new_ : DateType"), 1)
}

///|
test "bridge: FFI value identifier sanitizes MoonBit keywords and discard names" {
  assert_eq(ffi_sanitize_identifier("declare", "field"), "declare_")
  assert_eq(ffi_sanitize_identifier("import", "field"), "import_")
  assert_eq(ffi_sanitize_identifier("and", "field"), "and_")
  assert_eq(ffi_sanitize_identifier("is", "field"), "is_")
  assert_eq(ffi_sanitize_identifier("with", "field"), "with_")
  assert_eq(ffi_sanitize_identifier("include", "field"), "include_")
  assert_eq(ffi_sanitize_identifier("override", "field"), "override_")
  assert_eq(ffi_sanitize_identifier("method", "field"), "method_")
  assert_eq(ffi_sanitize_identifier("move", "field"), "move_")
  assert_eq(ffi_sanitize_identifier("final", "field"), "final_")
  assert_eq(ffi_sanitize_identifier("constructor", "field"), "constructor_")
  assert_eq(ffi_sanitize_identifier("local", "field"), "local_")
  assert_eq(ffi_sanitize_identifier("priv", "field"), "priv_")
  assert_eq(ffi_sanitize_identifier("resume", "field"), "resume_")
  assert_eq(ffi_sanitize_identifier("_", "field"), "field")
  assert_eq(ffi_value_fn_name("enum"), "enum_")
}

///|
test "bridge: FFI type identifier avoids invalid and core type names" {
  assert_eq(ffi_type_identifier("_", "OpaqueType"), "OpaqueType")
  assert_eq(ffi_type_identifier("_ZodType", "OpaqueType"), "UnderscoreZodType")
  assert_eq(ffi_type_identifier("Array", "OpaqueType"), "Array_")
  assert_eq(ffi_type_identifier("Error", "OpaqueType"), "Error_")
}

///|
test "bridge: FFI struct generation sanitizes keyword and discard fields" {
  let state : MoonBitJsFfiState = {
    declared_type_names: [],
    struct_type_names: [],
    generic_type_params_by_name: {},
    enums: [],
    external_type_names: [],
    local_type_param_names: [],
    function_field_method_wrapper_limit: ffi_function_field_method_wrapper_limit,
    tagged_union_decls_by_name: {},
    synthesized_inline_unions: {},
    needs_js_any: false,
    needs_promise: false,
  }
  let iface : @ast.TsInterface = {
    name: "Scope",
    type_params: [],
    extends_names: [],
    fields: [
      ("declare", @ast.TsType::Named("DeclarationParser")),
      ("import", @ast.TsType::Named("Module")),
      ("and", @ast.TsType::Named("NaryIntersectionParser")),
      ("with", @ast.TsType::Named("Scheduler")),
      ("include", @ast.TsType::Array(@ast.TsType::String_)),
      ("override", @ast.TsType::Boolean),
      ("method", @ast.TsType::String_),
      ("priv", @ast.TsType::String_),
      ("_", @ast.TsType::Named("_")),
      (
        "references",
        @ast.TsType::Applied("Array", [@ast.TsType::Named("BaseNode")]),
      ),
    ],
    readonly_fields: [],
    index_signatures: [],
  }
  let actual = ffi_struct_decl_to_moonbit(state, iface)
  assert_true(actual.contains("  declare_ : DeclarationParser"))
  assert_true(actual.contains("  import_ : Module"))
  assert_true(actual.contains("  and_ : NaryIntersectionParser"))
  assert_true(actual.contains("  with_ : Scheduler"))
  assert_true(actual.contains("  include_ : Array[String]"))
  assert_true(actual.contains("  override_ : Bool"))
  assert_true(actual.contains("  method_ : String"))
  assert_true(actual.contains("  priv_ : String"))
  assert_true(actual.contains("  field : OpaqueType"))
  assert_true(actual.contains("  references : Array[BaseNode]"))
  assert_false(actual.contains("  _ : Scope"))
}

///|
test "bridge: FFI struct generation adds method wrappers for function fields" {
  let state : MoonBitJsFfiState = {
    declared_type_names: [],
    struct_type_names: [],
    generic_type_params_by_name: {},
    enums: [],
    external_type_names: [],
    local_type_param_names: [],
    function_field_method_wrapper_limit: ffi_function_field_method_wrapper_limit,
    tagged_union_decls_by_name: {},
    synthesized_inline_unions: {},
    needs_js_any: false,
    needs_promise: false,
  }
  let iface : @ast.TsInterface = {
    name: "NodeFactory",
    type_params: [],
    extends_names: [],
    fields: [
      (
        "createIdentifier",
        @ast.TsType::Func(
          [@ast.TsType::String_],
          @ast.TsType::Named("Identifier"),
        ),
      ),
    ],
    readonly_fields: [],
    index_signatures: [],
  }
  let actual = ffi_struct_decl_to_moonbit(state, iface)
  assert_true(actual.contains("  createIdentifier : (String) -> Identifier"))
  assert_true(
    actual.contains(
      "pub extern \"js\" fn NodeFactory::createIdentifier(self : NodeFactory, arg0 : String) -> Identifier =\n  #| (self, arg0) => self.createIdentifier(arg0)",
    ),
  )
}

///|
test "bridge: FFI struct method wrappers unwrap optional arguments" {
  let state : MoonBitJsFfiState = {
    declared_type_names: [],
    struct_type_names: [],
    generic_type_params_by_name: {},
    enums: [],
    external_type_names: [],
    local_type_param_names: [],
    function_field_method_wrapper_limit: ffi_function_field_method_wrapper_limit,
    tagged_union_decls_by_name: {},
    synthesized_inline_unions: {},
    needs_js_any: false,
    needs_promise: false,
  }
  let iface : @ast.TsInterface = {
    name: "SignJWT",
    type_params: [],
    extends_names: [],
    fields: [
      (
        "setIssuedAt",
        @ast.TsType::Func(
          [@ast.TsType::Union([@ast.TsType::Any, @ast.TsType::Undefined])],
          @ast.TsType::Named("This"),
        ),
      ),
    ],
    readonly_fields: [],
    index_signatures: [],
  }
  let actual = ffi_struct_decl_to_moonbit(state, iface)
  assert_true(
    actual.contains(
      "pub extern \"js\" fn SignJWT::setIssuedAt(self : SignJWT, arg0 : JSValue?) -> SignJWT =",
    ),
  )
  assert_true(actual.contains("self.setIssuedAt("))
  assert_true(actual.contains("arg0.$tag === 1 ? arg0._0 : undefined"))
}

///|
test "bridge: FFI class methods unwrap optional arguments" {
  let state : MoonBitJsFfiState = {
    declared_type_names: [],
    struct_type_names: [],
    generic_type_params_by_name: {},
    enums: [],
    external_type_names: [],
    local_type_param_names: [],
    function_field_method_wrapper_limit: ffi_function_field_method_wrapper_limit,
    tagged_union_decls_by_name: {},
    synthesized_inline_unions: {},
    needs_js_any: false,
    needs_promise: false,
  }
  let class_ : @ast.TsClassDecl = {
    name: "SignJWT",
    type_params: [],
    base_names: [],
    constructor_params: None,
    properties: [],
    methods: [],
    is_abstract: false,
    is_constructible: true,
  }
  let class_method : @ast.TsClassMethodDecl = {
    name: "setIssuedAt",
    type_params: [],
    type_param_bounds: [],
    params: [
      ("input", @ast.TsType::Union([@ast.TsType::Any, @ast.TsType::Undefined])),
    ],
    return_type: @ast.TsType::Named("This"),
    is_static: false,
  }
  let actual = ffi_class_method_decl_to_moonbit(state, class_, class_method)
  assert_true(
    actual.contains(
      "pub extern \"js\" fn SignJWT::set_issued_at(self : SignJWT, input : JSValue?) -> SignJWT =",
    ),
  )
  assert_true(actual.contains("#| (self, input) =>"))
  assert_true(actual.contains("self.setIssuedAt("))
  assert_true(actual.contains("input.$tag === 1 ? input._0 : undefined"))
}

///|
test "bridge: FFI struct generation keeps generic method wrappers non-extern" {
  let state : MoonBitJsFfiState = {
    declared_type_names: [],
    struct_type_names: [],
    generic_type_params_by_name: {},
    enums: [],
    external_type_names: [],
    local_type_param_names: [],
    function_field_method_wrapper_limit: ffi_function_field_method_wrapper_limit,
    tagged_union_decls_by_name: {},
    synthesized_inline_unions: {},
    needs_js_any: false,
    needs_promise: false,
  }
  let iface : @ast.TsInterface = {
    name: "StatsBase",
    type_params: ["T"],
    extends_names: [],
    // Include a T-referencing field so the bridge keeps T in the rendered
    // type parameter list — otherwise the unused-type-param filter strips it.
    fields: [
      ("dev", @ast.TsType::Named("T")),
      ("isFile", @ast.TsType::Func([], @ast.TsType::Boolean)),
    ],
    readonly_fields: [],
    index_signatures: [],
  }
  let actual = ffi_struct_decl_to_moonbit(state, iface)
  assert_true(
    actual.contains(
      "pub fn[T] StatsBase::isFile(self : StatsBase[T]) -> Bool {\n  (self.isFile)()\n}",
    ),
  )
  assert_false(actual.contains("pub extern \"js\" fn[T]"))
}

///|
test "bridge: FFI struct generation caps method wrappers but keeps function fields" {
  let state : MoonBitJsFfiState = {
    declared_type_names: [],
    struct_type_names: [],
    generic_type_params_by_name: {},
    enums: [],
    external_type_names: [],
    local_type_param_names: [],
    function_field_method_wrapper_limit: 2,
    tagged_union_decls_by_name: {},
    synthesized_inline_unions: {},
    needs_js_any: false,
    needs_promise: false,
  }
  let iface : @ast.TsInterface = {
    name: "LargeApi",
    type_params: [],
    extends_names: [],
    fields: [
      ("call0", @ast.TsType::Func([], @ast.TsType::Void)),
      ("call1", @ast.TsType::Func([], @ast.TsType::Void)),
      ("call2", @ast.TsType::Func([], @ast.TsType::Void)),
    ],
    readonly_fields: [],
    index_signatures: [],
  }
  let actual = ffi_struct_decl_to_moonbit(state, iface)
  assert_true(actual.contains("  call2 : () -> Unit"))
  assert_eq(
    count_occurrences_in_ffi_output(actual, "pub extern \"js\" fn LargeApi::"),
    2,
  )
  assert_false(actual.contains("pub extern \"js\" fn LargeApi::call2("))
}

///|
test "bridge: FFI struct generation keeps callable wrapper beyond cap" {
  let state : MoonBitJsFfiState = {
    declared_type_names: [],
    struct_type_names: [],
    generic_type_params_by_name: {},
    enums: [],
    external_type_names: [],
    local_type_param_names: [],
    function_field_method_wrapper_limit: 1,
    tagged_union_decls_by_name: {},
    synthesized_inline_unions: {},
    needs_js_any: false,
    needs_promise: false,
  }
  let iface : @ast.TsInterface = {
    name: "ExpectStatic",
    type_params: [],
    extends_names: [],
    fields: [
      ("helper0", @ast.TsType::Func([], @ast.TsType::Void)),
      ("helper1", @ast.TsType::Func([], @ast.TsType::Void)),
      (
        "_call_",
        @ast.TsType::Func(
          [@ast.TsType::String_],
          @ast.TsType::Named("Assertion"),
        ),
      ),
    ],
    readonly_fields: [],
    index_signatures: [],
  }
  let actual = ffi_struct_decl_to_moonbit(state, iface)
  assert_true(actual.contains("  _call_ : (String) -> Assertion"))
  assert_true(
    actual.contains(
      "pub extern \"js\" fn ExpectStatic::_call_(self : ExpectStatic, arg0 : String) -> Assertion =",
    ),
  )
  assert_false(actual.contains("pub fn ExpectStatic::helper1("))
}

///|
test "bridge: FFI struct JS converter emits callable wrappers for call signatures" {
  let state : MoonBitJsFfiState = {
    declared_type_names: [],
    struct_type_names: ["ForwardRefRenderFunction"],
    generic_type_params_by_name: {},
    enums: [],
    external_type_names: [],
    local_type_param_names: [],
    function_field_method_wrapper_limit: ffi_function_field_method_wrapper_limit,
    tagged_union_decls_by_name: {},
    synthesized_inline_unions: {},
    needs_js_any: false,
    needs_promise: false,
  }
  let actual = ffi_struct_js_converter_decl(state, "ForwardRefRenderFunction", [
    (
      "<call>",
      @ast.TsType::Func(
        [@ast.TsType::Named("Props"), @ast.TsType::Named("Ref")],
        @ast.TsType::Named("ReactNode"),
      ),
    ),
    (
      "displayName",
      @ast.TsType::Union([@ast.TsType::String_, @ast.TsType::Undefined]),
    ),
  ])
  assert_true(
    actual.contains("if (typeof value === \"function\") return value;"),
  )
  assert_true(
    actual.contains("const result = (...args) => value[\"_call_\"](...args);"),
  )
  assert_false(actual.contains("result[\"<call>\"]"))
  assert_true(actual.contains("result[\"displayName\"] = field;"))
}

///|
test "bridge: FFI struct preserves selected interface type parameters locally" {
  let state : MoonBitJsFfiState = {
    declared_type_names: [],
    struct_type_names: [],
    generic_type_params_by_name: {},
    enums: [],
    external_type_names: [],
    local_type_param_names: [],
    function_field_method_wrapper_limit: ffi_function_field_method_wrapper_limit,
    tagged_union_decls_by_name: {},
    synthesized_inline_unions: {},
    needs_js_any: false,
    needs_promise: false,
  }
  let iface : @ast.TsInterface = {
    name: "StatsBase",
    type_params: ["T"],
    extends_names: [],
    fields: [
      ("dev", @ast.TsType::Named("T")),
      ("isFile", @ast.TsType::Func([], @ast.TsType::Boolean)),
    ],
    readonly_fields: [],
    index_signatures: [],
  }
  let actual = ffi_struct_decl_to_moonbit(state, iface)
  assert_true(actual.contains("pub(all) struct StatsBase[T]"))
  assert_true(actual.contains("dev : T"))
  assert_true(actual.contains("isFile : () -> Bool"))
  assert_true(
    actual.contains("pub fn[T] StatsBase::isFile(self : StatsBase[T]) -> Bool"),
  )
  assert_false(actual.contains("type T"))
  assert_false(state.external_type_names.contains("T"))
}

///|
async test "bridge: emit MoonBit JS FFI bundle avoids duplicate class/interface type declarations" {
  let bundle = emit_moonbit_js_ffi_bundle_from_entry_path(
    "fixtures/resolver/project/types/class-interface-merge-entry.d.ts", "./runtime/class-interface-merge.js",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(bundle.ffi_mbt.contains("pub(all) struct Location"))
  assert_eq(count_occurrences_in_ffi_output(bundle.ffi_mbt, "type Location"), 0)
}

///|
test "ffi_classify_transparent_intersection: collapses uniform String primitive" {
  let t : @ast.TsType = Intersection([String_, String_])
  match @checker.classify_transparent_intersection(t) {
    Some(String_) => ()
    Some(other) => fail("expected String_, got \{other}")
    None => fail("expected Some(String_), got None")
  }
}

///|
test "ffi_classify_transparent_intersection: collapses uniform union with primitive" {
  // (keyof Data | keyof FlashData) & string ≈ Intersection([Union([String_, String_]), String_])
  let t : @ast.TsType = Intersection([Union([String_, String_]), String_])
  match @checker.classify_transparent_intersection(t) {
    Some(String_) => ()
    Some(other) => fail("expected String_, got \{other}")
    None => fail("expected Some(String_), got None")
  }
}

///|
test "ffi_classify_transparent_intersection: collapses uniform Number primitive" {
  let t : @ast.TsType = Intersection([Number, Number, Number])
  match @checker.classify_transparent_intersection(t) {
    Some(Number) => ()
    Some(other) => fail("expected Number, got \{other}")
    None => fail("expected Some(Number), got None")
  }
}
