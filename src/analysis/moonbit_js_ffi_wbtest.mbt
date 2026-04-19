///|
fn count_occurrences_in_ffi_output(haystack : String, needle : String) -> Int {
  let mut count = 0
  for _ in haystack.split(needle) {
    count += 1
  }
  count - 1
}

///|
async test "analysis: emit MoonBit JS FFI bundle for function reexports" {
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
  assert_true(bundle.ffi_mbt.contains("pub struct PublicPoint"))
  assert_true(
    bundle.ffi_mbt.contains(
      "#module(\"/runtime/mod.js\")\npub extern \"js\" fn render(point : PublicPoint) -> PublicPoint = \"render\"",
    ),
  )
  assert_false(bundle.bridge_js.contains("__ts_mbt_render"))
}

///|
async test "analysis: emit MoonBit JS FFI bundle for namespace exports" {
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
  assert_true(bundle.ffi_mbt.contains("#external\ntype Shapes"))
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn get_shapes() -> Shapes = \"__ts_mbt_get_shapes\"",
    ),
  )
  assert_true(
    bundle.bridge_js.contains(
      "export const __ts_mbt_get_shapes = () => __ts_mbt_import_shapes;",
    ),
  )
}

///|
async test "analysis: emit MoonBit JS FFI bundle keeps ambiguous exports as comments" {
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
      "Unsupported export Shared: ambiguous re-export surface cannot be bound safely.",
    ),
  )
  assert_true(
    bundle.bridge_js.contains(
      "Unsupported export Shared: ambiguous re-export surface cannot be bound safely.",
    ),
  )
}

///|
async test "analysis: emit MoonBit JS FFI bundle for typed value exports" {
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
      "export const __ts_mbt_get_version = () => __ts_mbt_import_version;",
    ),
  )
  assert_true(
    bundle.bridge_js.contains(
      "export const __ts_mbt_get_build_number = () => __ts_mbt_import_build_number;",
    ),
  )
}

///|
async test "analysis: emit MoonBit JS FFI bundle falls back to Any getter for unresolved value exports" {
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
      "pub extern \"js\" fn get_ready() -> @js.Any = \"__ts_mbt_get_ready\"",
    ),
  )
  assert_true(
    bundle.bridge_js.contains(
      "export const __ts_mbt_get_ready = () => __ts_mbt_import_ready;",
    ),
  )
}

///|
async test "analysis: emit MoonBit JS FFI bundle for exported classes" {
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
  assert_true(bundle.ffi_mbt.contains("#external\ntype Counter"))
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn new_counter(initial : Double) -> Counter = \"__ts_mbt_new_counter\"",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn counter_inc(self : Counter, delta : Double) -> Double =\n  #| (self, delta) => self.inc(delta)",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn counter_from(seed : Double) -> Counter = \"__ts_mbt_counter_from\"",
    ),
  )
  assert_true(
    bundle.bridge_js.contains(
      "export const __ts_mbt_new_counter = (initial) => new __ts_mbt_import_counter(initial);",
    ),
  )
  assert_false(bundle.bridge_js.contains("__ts_mbt_counter_inc"))
  assert_true(
    bundle.bridge_js.contains(
      "export const __ts_mbt_counter_from = (seed) => __ts_mbt_import_counter.from(seed);",
    ),
  )
}

///|
async test "analysis: emit MoonBit JS FFI bundle for abstract classes without constructor" {
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
  assert_true(bundle.ffi_mbt.contains("#external\ntype Shape"))
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn shape_area(self : Shape) -> Double =\n  #| (self) => self.area()",
    ),
  )
  assert_false(bundle.ffi_mbt.contains("pub extern \"js\" fn new_shape("))
  assert_false(bundle.bridge_js.contains("__ts_mbt_shape_area"))
}

///|
async test "analysis: emit MoonBit JS FFI bundle for exported class properties" {
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
      "pub extern \"js\" fn get_counter_state_current(self : CounterState) -> Double =\n  #| (self) => self.current",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn get_counter_state_label(self : CounterState) -> String =\n  #| (self) => self.label",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn set_counter_state_label(self : CounterState, value : String) -> Unit =\n  #| (self, value) => (self.label = value)",
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
      "export const __ts_mbt_get_counter_state_version = () => __ts_mbt_import_counter_state.version;",
    ),
  )
  assert_true(
    bundle.bridge_js.contains(
      "export const __ts_mbt_set_counter_state_step = (value) => (__ts_mbt_import_counter_state.step = value);",
    ),
  )
}

///|
async test "analysis: emit MoonBit JS FFI bundle with unresolved external library types as opaque types" {
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
  assert_true(bundle.ffi_mbt.contains("pub struct User"))
  assert_true(bundle.ffi_mbt.contains("#external\ntype Result"))
  assert_true(bundle.ffi_mbt.contains("#external\ntype ResultAsync"))
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
async test "analysis: emit MoonBit JS FFI bundle with resolved bare-package types as opaque types" {
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
  assert_true(bundle.ffi_mbt.contains("pub struct User"))
  assert_true(bundle.ffi_mbt.contains("#external\ntype PkgTypesValue"))
  assert_true(
    bundle.ffi_mbt.contains(
      "#module(\"/runtime/resolved-lib.js\")\npub extern \"js\" fn parse_user(input : String) -> PkgTypesValue = \"parseUser\"",
    ),
  )
  assert_false(bundle.bridge_js.contains("__ts_mbt_parse_user"))
}

///|
async test "analysis: emit MoonBit JS FFI bundle with minimal opaque bare-package imports" {
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
  assert_true(bundle.ffi_mbt.contains("#external\ntype PkgTypesValue"))
  assert_true(
    bundle.ffi_mbt.contains(
      "#module(\"/runtime/opaque-package.js\")\npub extern \"js\" fn parse_value(input : String) -> PkgTypesValue = \"parseValue\"",
    ),
  )
  assert_false(bundle.bridge_js.contains("__ts_mbt_parse_value"))
}

///|
async test "analysis: emit MoonBit JS FFI bundle with resolved mixed imports as opaque types" {
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
  assert_true(bundle.ffi_mbt.contains("pub struct User"))
  assert_true(bundle.ffi_mbt.contains("#external\ntype PkgResult"))
  assert_true(bundle.ffi_mbt.contains("#external\ntype PkgResultAsync"))
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
async test "analysis: emit MoonBit JS FFI bundle with resolved generic library imports" {
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
  assert_true(bundle.ffi_mbt.contains("pub struct User"))
  assert_true(bundle.ffi_mbt.contains("#external\ntype PkgResult"))
  assert_true(bundle.ffi_mbt.contains("#external\ntype PkgResultAsync"))
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
async test "analysis: emit MoonBit JS FFI bundle with resolved symlinked library imports" {
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
  assert_true(bundle.ffi_mbt.contains("pub struct User"))
  assert_true(bundle.ffi_mbt.contains("#external\ntype PkgSymlinkResult"))
  assert_true(bundle.ffi_mbt.contains("#external\ntype PkgSymlinkResultAsync"))
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
async test "analysis: emit MoonBit JS FFI bundle with neverthrow-like package imports" {
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
  assert_true(bundle.ffi_mbt.contains("pub struct User"))
  assert_true(bundle.ffi_mbt.contains("#external\ntype Result"))
  assert_true(bundle.ffi_mbt.contains("#external\ntype ResultAsync"))
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
async test "analysis: emit MoonBit JS FFI bundle through package exports subpath" {
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
  assert_true(bundle.ffi_mbt.contains("pub struct FeatureOptions"))
  assert_true(bundle.ffi_mbt.contains("pub struct FeatureResult"))
  assert_true(
    bundle.ffi_mbt.contains(
      "#module(\"/runtime/subpath-package.js\")\npub extern \"js\" fn execute_feature(options : FeatureOptions) -> FeatureResult = \"executeFeature\"",
    ),
  )
}

///|
async test "analysis: emit MoonBit JS FFI bundle through package barrel reexports" {
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
  assert_true(bundle.ffi_mbt.contains("pub struct BarrelOptions"))
  assert_true(bundle.ffi_mbt.contains("pub struct BarrelResult"))
  assert_true(
    bundle.ffi_mbt.contains(
      "#module(\"/runtime/barrel-package.js\")\npub extern \"js\" fn create_barrel(options : BarrelOptions) -> BarrelResult = \"createBarrel\"",
    ),
  )
}

///|
async test "analysis: emit MoonBit JS FFI bundle with node-like ambient qualified types" {
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
  assert_true(bundle.ffi_mbt.contains("pub struct RuntimeConfig"))
  assert_true(bundle.ffi_mbt.contains("#external\ntype NodeJsProcessEnv"))
  assert_true(
    bundle.ffi_mbt.contains(
      "#module(\"/runtime/node-like.js\")\npub extern \"js\" fn has_env(env : NodeJsProcessEnv, key : String) -> Bool = \"hasEnv\"",
    ),
  )
}

///|
async test "analysis: emit MoonBit JS FFI bundle collapse overloads by generated binding name" {
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
  assert_eq(
    count_occurrences_in_ffi_output(
      bundle.ffi_mbt,
      "pub extern \"js\" fn counter_value(",
    ),
    1,
  )
  assert_eq(
    count_occurrences_in_ffi_output(
      bundle.bridge_js,
      "export const __ts_mbt_make_counter =",
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
async test "analysis: emit MoonBit JS FFI bundle from runtime ts exported functions" {
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
  assert_true(bundle.ffi_mbt.contains("pub struct RuntimePoint"))
  assert_true(
    bundle.ffi_mbt.contains(
      "#module(\"/runtime/runtime-function.js\")\npub extern \"js\" fn scale_point(point : RuntimePoint, factor : Double) -> RuntimePoint = \"scalePoint\"",
    ),
  )
  assert_false(bundle.bridge_js.contains("__ts_mbt_scale_point"))
}

///|
async test "analysis: emit MoonBit JS FFI bundle from runtime tsx exported functions" {
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
  assert_true(bundle.ffi_mbt.contains("pub struct BadgeProps"))
  assert_true(bundle.ffi_mbt.contains("#external\ntype JsxElement"))
  assert_true(
    bundle.ffi_mbt.contains(
      "#module(\"/runtime/runtime-component.js\")\npub extern \"js\" fn render_badge(props : BadgeProps) -> JsxElement = \"renderBadge\"",
    ),
  )
  assert_false(bundle.bridge_js.contains("__ts_mbt_render_badge"))
}

///|
async test "analysis: emit MoonBit JS FFI bundle from runtime ts exported const arrow functions" {
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
  assert_true(bundle.ffi_mbt.contains("pub struct RuntimeArrowPoint"))
  assert_true(
    bundle.ffi_mbt.contains(
      "#module(\"/runtime/runtime-arrow.js\")\npub extern \"js\" fn scale_arrow_point(point : RuntimeArrowPoint, factor : Double) -> RuntimeArrowPoint = \"scaleArrowPoint\"",
    ),
  )
  assert_false(bundle.bridge_js.contains("__ts_mbt_scale_arrow_point"))
}

///|
async test "analysis: emit MoonBit JS FFI bundle from runtime ts exported untyped const arrow functions" {
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
async test "analysis: emit MoonBit JS FFI bundle from runtime ts function reexports" {
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
async test "analysis: emit MoonBit JS FFI bundle from runtime default exported functions" {
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
async test "analysis: emit MoonBit JS FFI bundle from runtime default exported classes" {
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
  assert_true(bundle.ffi_mbt.contains("#external\ntype Default"))
  assert_true(
    bundle.ffi_mbt.contains(
      "#module(\"/runtime/runtime-default-class.js\")\nextern \"js\" fn Default::new(initial : Double) -> Default = \"default\"",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub fn new_default(initial : Double) -> Default {\n  Default::new(initial)\n}",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn default_inc(self : Default, delta : Double) -> Double =\n  #| (self, delta) => self.inc(delta)",
    ),
  )
  assert_false(bundle.bridge_js.contains("__ts_mbt_new_default"))
  assert_false(bundle.bridge_js.contains("__ts_mbt_default_inc"))
}

///|
async test "analysis: emit MoonBit JS FFI bundle from namespace export assignment" {
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
      "pub extern \"js\" fn get_default() -> @js.Any = \"__ts_mbt_get_default\"",
    ),
  )
  assert_true(
    bundle.bridge_js.contains(
      "export const __ts_mbt_get_default = () => __ts_mbt_import_default;",
    ),
  )
}
