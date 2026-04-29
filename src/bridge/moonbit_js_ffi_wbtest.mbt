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
  assert_true(bundle.ffi_mbt.contains("pub struct PublicPoint"))
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
  assert_true(bundle.ffi_mbt.contains("#external\ntype Shapes"))
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
  assert_true(bundle.ffi_mbt.contains("#external\ntype Counter"))
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn new_counter(initial : Double) -> Counter = \"__ts_mbt_new_counter\"",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn Counter::counter_inc(self : Counter, delta : Double) -> Double =\n  #| (self, delta) => self.inc(delta)",
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
  assert_true(bundle.ffi_mbt.contains("#external\ntype Shape"))
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn Shape::shape_area(self : Shape) -> Double =\n  #| (self) => self.area()",
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
  assert_true(bundle.ffi_mbt.contains("#external\ntype PkgTypesValue"))
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
  assert_true(bundle.ffi_mbt.contains("pub struct FeatureOptions"))
  assert_true(bundle.ffi_mbt.contains("pub struct FeatureResult"))
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
  assert_true(bundle.ffi_mbt.contains("pub struct BarrelOptions"))
  assert_true(bundle.ffi_mbt.contains("pub struct BarrelResult"))
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
  assert_true(bundle.ffi_mbt.contains("pub struct RuntimeConfig"))
  assert_true(bundle.ffi_mbt.contains("#external\ntype NodeJS_ProcessEnv"))
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
  assert_eq(
    count_occurrences_in_ffi_output(
      bundle.ffi_mbt,
      "pub extern \"js\" fn Counter::counter_value(",
    ),
    1,
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
      "export const __ts_mbt_counter_value =",
    ),
    0,
  )
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
  assert_true(bundle.ffi_mbt.contains("pub struct RuntimePoint"))
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
  assert_true(bundle.ffi_mbt.contains("pub struct BadgeProps"))
  assert_true(bundle.ffi_mbt.contains("#external\ntype JSX_Element"))
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
  assert_true(bundle.ffi_mbt.contains("pub struct RuntimeArrowPoint"))
  assert_true(
    bundle.ffi_mbt.contains(
      "#module(\"/runtime/runtime-arrow.js\")\npub extern \"js\" fn scale_arrow_point(point : RuntimeArrowPoint, factor : Double) -> RuntimeArrowPoint = \"scaleArrowPoint\"",
    ),
  )
  assert_false(bundle.bridge_js.contains("__ts_mbt_scale_arrow_point"))
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
  assert_true(bundle.ffi_mbt.contains("#external\ntype RuntimeState"))
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
  assert_true(bundle.ffi_mbt.contains("#external\ntype RuntimeState"))
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn new_runtime_state() -> RuntimeState = \"__ts_mbt_new_runtime_state\"",
    ),
  )
  assert_true(
    bundle.bridge_js.contains(
      "import { CounterState } from \"pkg-class-property\";",
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
  assert_true(bundle.ffi_mbt.contains("#external\ntype RuntimeCounter"))
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
  assert_true(bundle.ffi_mbt.contains("#external\ntype RuntimeState"))
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
      "import { CounterState } from \"pkg-class-subpath/state\";",
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
  assert_true(bundle.ffi_mbt.contains("pub struct RestMeta"))
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
  assert_true(bundle.ffi_mbt.contains("pub struct RestMeta"))
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
  assert_true(bundle.ffi_mbt.contains("pub struct RestMeta"))
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
  assert_true(bundle.ffi_mbt.contains("pub struct RestMeta"))
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
  assert_true(bundle.ffi_mbt.contains("pub struct RestMeta"))
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
  assert_true(bundle.ffi_mbt.contains("pub struct RestMeta"))
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
  assert_true(bundle.ffi_mbt.contains("pub struct RestMeta"))
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
  assert_true(bundle.ffi_mbt.contains("pub struct RestMeta"))
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
  assert_true(bundle.ffi_mbt.contains("pub struct RestMeta"))
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
  assert_true(bundle.ffi_mbt.contains("pub struct RestMeta"))
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
  assert_true(bundle.ffi_mbt.contains("pub struct RestMeta"))
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
  assert_true(bundle.ffi_mbt.contains("pub struct RestMeta"))
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
  assert_true(bundle.ffi_mbt.contains("pub struct RestMeta"))
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
  assert_true(bundle.ffi_mbt.contains("pub struct RestMeta"))
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
  assert_true(bundle.ffi_mbt.contains("pub struct RestMeta"))
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
  assert_true(bundle.ffi_mbt.contains("pub struct RestMeta"))
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
  assert_true(bundle.ffi_mbt.contains("pub struct RestMeta"))
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
  assert_true(bundle.ffi_mbt.contains("pub struct RestMeta"))
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
  assert_true(bundle.ffi_mbt.contains("pub struct RestMeta"))
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
  assert_true(bundle.ffi_mbt.contains("pub struct RestMeta"))
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
  assert_true(bundle.ffi_mbt.contains("pub struct RestMeta"))
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
  assert_true(bundle.ffi_mbt.contains("pub struct RestMeta"))
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
  assert_true(bundle.ffi_mbt.contains("pub struct RestMeta"))
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
  assert_true(bundle.ffi_mbt.contains("pub struct RestMeta"))
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
  assert_true(bundle.ffi_mbt.contains("pub struct RestMeta"))
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
  assert_false(bundle.ffi_mbt.contains("pub struct RestMeta"))
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn get_runtime_version() -> @js.Any = \"__ts_mbt_get_runtime_version\"",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn get_build() -> @js.Any = \"__ts_mbt_get_build\"",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn get_rest_meta() -> @js.Any = \"__ts_mbt_get_rest_meta\"",
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
  assert_false(bundle.ffi_mbt.contains("pub struct RestMeta"))
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn get_runtime_version() -> @js.Any = \"__ts_mbt_get_runtime_version\"",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn get_build() -> @js.Any = \"__ts_mbt_get_build\"",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn get_rest_meta() -> @js.Any = \"__ts_mbt_get_rest_meta\"",
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
  assert_false(bundle.ffi_mbt.contains("pub struct RestMeta"))
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn get_runtime_version() -> @js.Any = \"__ts_mbt_get_runtime_version\"",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn get_build() -> @js.Any = \"__ts_mbt_get_build\"",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn get_rest_meta() -> @js.Any = \"__ts_mbt_get_rest_meta\"",
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
  assert_true(bundle.ffi_mbt.contains("pub struct RestMeta"))
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
  assert_true(bundle.ffi_mbt.contains("pub struct RestMeta"))
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
  assert_true(bundle.ffi_mbt.contains("pub struct RestMeta"))
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
  assert_true(bundle.ffi_mbt.contains("pub struct RestMeta"))
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
  assert_true(bundle.ffi_mbt.contains("pub struct RestMeta"))
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
  assert_false(bundle.ffi_mbt.contains("pub struct RestMeta"))
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn get_runtime_version() -> @js.Any = \"__ts_mbt_get_runtime_version\"",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn get_build() -> @js.Any = \"__ts_mbt_get_build\"",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn get_rest_meta() -> @js.Any = \"__ts_mbt_get_rest_meta\"",
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
  assert_true(bundle.ffi_mbt.contains("#external\ntype Default"))
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn new_default(initial : Double) -> Default = \"__ts_mbt_new_default\"",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn Default::default_inc(self : Default, delta : Double) -> Double =\n  #| (self, delta) => self.inc(delta)",
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
  assert_true(bundle.ffi_mbt.contains("#external\ntype Default"))
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn new_default(initial : Double) -> Default = \"__ts_mbt_new_default\"",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn Default::default_inc(self : Default, delta : Double) -> Double =\n  #| (self, delta) => self.inc(delta)",
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
  assert_true(bundle.ffi_mbt.contains("#external\ntype Default"))
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
      "import default_, { version } from \"../../runtime/runtime-default-class-mixed.js\";",
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
  assert_true(bundle.ffi_mbt.contains("#external\ntype RuntimeCounter"))
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
      "import default_, { version } from \"../../runtime/runtime-default-class-mixed.js\";",
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
      "pub extern \"js\" fn get_default() -> @js.Any = \"__ts_mbt_get_default\"",
    ),
  )
  assert_true(
    bundle.bridge_js.contains(
      "export function __ts_mbt_get_default() { return default_; }",
    ),
  )
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
      "pub extern \"js\" fn create_context(defaultValue : T) -> Context = \"__ts_mbt_create_context\"",
    ),
  )
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
  assert_true(bundle.ffi_mbt.contains("pub struct UseStateResult"))
  assert_true(bundle.ffi_mbt.contains("  state : S"))
  assert_true(bundle.ffi_mbt.contains("  setState : Dispatch"))
  assert_true(bundle.ffi_mbt.contains("pub struct UseReducerResult"))
  assert_true(bundle.ffi_mbt.contains("  state : S"))
  assert_true(bundle.ffi_mbt.contains("  dispatch : ActionDispatch"))
  assert_true(bundle.ffi_mbt.contains("pub struct UseTransitionResult"))
  assert_true(bundle.ffi_mbt.contains("  isPending : Bool"))
  assert_true(bundle.ffi_mbt.contains("  startTransition : TransitionFunction"))
  assert_true(bundle.ffi_mbt.contains("pub struct UseOptimisticResult"))
  assert_true(bundle.ffi_mbt.contains("  state : State"))
  assert_true(bundle.ffi_mbt.contains("  dispatch : @js.Any"))
  assert_true(bundle.ffi_mbt.contains("pub struct UseActionStateResult"))
  assert_true(bundle.ffi_mbt.contains("  state : State"))
  assert_true(bundle.ffi_mbt.contains("  dispatch : @js.Any"))
  assert_true(bundle.ffi_mbt.contains("  isPending : Bool"))
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn use_state(initialState : S) -> UseStateResult = \"__ts_mbt_use_state\"",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn use_reducer(reducer : @js.Any, initialState : S) -> UseReducerResult = \"__ts_mbt_use_reducer\"",
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
      "pub extern \"js\" fn use_action_state(action : @js.Any, initialState : State, permalink : String?) -> UseActionStateResult = \"__ts_mbt_use_action_state\"",
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
      "export function __ts_mbt_use_action_state(action, initialState, permalink) { const tuple_ = default_.useActionState(action, initialState, permalink); return { state: tuple_[0], dispatch: tuple_[1], isPending: tuple_[2] }; }",
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
  assert_true(bundle.ffi_mbt.contains("pub struct JsxElement"))
  assert_true(bundle.ffi_mbt.contains("  kind : String"))
  assert_true(bundle.ffi_mbt.contains("pub struct JsxIntrinsicElements"))
  assert_true(bundle.ffi_mbt.contains("  badge : BadgeProps"))
  assert_true(bundle.ffi_mbt.contains("pub struct JsxLibraryManagedAttributes"))
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
  assert_true(bundle.ffi_mbt.contains("pub struct JsxElement"))
  assert_true(bundle.ffi_mbt.contains("pub struct JsxIntrinsicElements"))
  assert_true(bundle.ffi_mbt.contains("pub struct JsxLibraryManagedAttributes"))
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
  assert_true(bundle.ffi_mbt.contains("pub struct BadgePropsWithChildren"))
  assert_true(bundle.ffi_mbt.contains("  label : String"))
  assert_true(bundle.ffi_mbt.contains("  children : @js.Any"))
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
  assert_true(bundle.ffi_mbt.contains("pub struct BadgeProps"))
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
  assert_true(bundle.ffi_mbt.contains("pub struct BadgeProps"))
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
  assert_true(bundle.ffi_mbt.contains("pub struct BadgePropsWithRef"))
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
  assert_true(bundle.ffi_mbt.contains("pub struct BadgePropsWithChildren"))
  assert_true(bundle.ffi_mbt.contains("  label : String"))
  assert_true(bundle.ffi_mbt.contains("  children : @js.Any"))
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
  assert_true(bundle.ffi_mbt.contains("pub struct BadgeProps"))
  assert_true(bundle.ffi_mbt.contains("pub struct BadgePropsWithChildren"))
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
  assert_true(bundle.ffi_mbt.contains("pub struct BadgeProps"))
  assert_true(bundle.ffi_mbt.contains("  label : String?"))
  assert_true(bundle.ffi_mbt.contains("  children : @js.Any?"))
  assert_true(bundle.ffi_mbt.contains("  ref_ : Ref?"))
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn render_badge(props : BadgeProps) -> BadgeProps = \"__ts_mbt_render_badge\"",
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
  assert_true(bundle.ffi_mbt.contains("pub struct JSXSource"))
  assert_true(bundle.ffi_mbt.contains("  fileName : String?"))
  assert_true(bundle.ffi_mbt.contains("  lineNumber : Double?"))
  assert_true(bundle.ffi_mbt.contains("  columnNumber : Double?"))
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn jsx_dev(type_ : ElementType, props : @js.Any, key : Key?, isStatic : Bool, source : JSXSource?, self : @js.Any?) -> ReactElement = \"jsxDEV\"",
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
  assert_true(bundle.ffi_mbt.contains("pub struct LabelCountPropsWithChildren"))
  assert_true(bundle.ffi_mbt.contains("  label : String"))
  assert_true(bundle.ffi_mbt.contains("  count : Double"))
  assert_true(bundle.ffi_mbt.contains("  children : @js.Any"))
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
  assert_true(bundle.ffi_mbt.contains("pub struct Props"))
  assert_true(bundle.ffi_mbt.contains("  type_ : String"))
  assert_true(bundle.ffi_mbt.contains("  ref_ : String"))
  assert_true(bundle.ffi_mbt.contains("pub struct ReactElement"))
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn jsx(type_ : String, props : Props) -> ReactElement = \"__ts_mbt_jsx\"",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn use_(promise : Promise) -> String = \"__ts_mbt_use\"",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn forward_ref(component : @js.Any) -> @js.Any = \"__ts_mbt_forward_ref\"",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn use_action_state(fn_ : @js.Any, initialState : String, permalink : String) -> String = \"__ts_mbt_use_action_state\"",
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
  assert_true(bundle.ffi_mbt.contains("pub struct HonoOptions"))
  assert_true(bundle.ffi_mbt.contains("  strict : Bool?"))
  assert_true(bundle.ffi_mbt.contains("  bindings : E?"))
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn new_hono(options : HonoOptions?) -> Hono = \"__ts_mbt_new_hono\"",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn create_app(options : HonoOptions) -> Hono = \"__ts_mbt_create_app\"",
    ),
  )
}

///|
async test "bridge: emit MoonBit JS FFI bundle narrows literal unions to primitives" {
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
  assert_false(bundle.ffi_mbt.contains("pub type JSValue = @js.Any"))
  assert_true(bundle.ffi_mbt.contains("  variant : String?"))
  assert_true(bundle.ffi_mbt.contains("  disabled : Bool?"))
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn render_button(variant : String, options : ButtonOptions?) -> String = \"__ts_mbt_render_button\"",
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
  assert_true(bundle.ffi_mbt.contains("#external\ntype FunctionComponent"))
  assert_true(bundle.ffi_mbt.contains("#external\ntype NamedExoticComponent"))
  assert_true(
    bundle.ffi_mbt.contains("#external\ntype ForwardRefExoticComponent"),
  )
  assert_true(bundle.ffi_mbt.contains("#external\ntype MemoExoticComponent"))
  assert_false(bundle.ffi_mbt.contains("pub struct FunctionComponent"))
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn create_element(type_ : String, props : DOMAttributes?, children : Array[@js.Any]) -> ReactElement = \"__ts_mbt_create_element\"",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn clone_element(element : ReactElement, props : DOMAttributes?, children : Array[@js.Any]) -> ReactElement = \"__ts_mbt_clone_element\"",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn forward_ref(render : @js.Any) -> ForwardRefExoticComponent = \"__ts_mbt_forward_ref\"",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn memo(component : FunctionComponent, propsAreEqual : @js.Any?) -> MemoExoticComponent = \"__ts_mbt_memo\"",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn normalize_props(props : ButtonHTMLAttributes) -> ButtonHTMLAttributes = \"__ts_mbt_normalize_props\"",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn use_component_ref(ref_ : Ref) -> Ref = \"__ts_mbt_use_component_ref\"",
    ),
  )
  assert_false(bundle.ffi_mbt.contains("props : @js.Any?"))
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
  assert_true(bundle.ffi_mbt.contains("pub struct JsxElement"))
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn jsx(type_ : String, props : ButtonHTMLAttributes, key : Key?) -> ReactElement = \"jsx\"",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn jsxs(type_ : String, props : ButtonHTMLAttributes, key : Key?) -> ReactElement = \"jsxs\"",
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
  assert_true(bundle.ffi_mbt.contains("pub struct JsxElement"))
  assert_true(bundle.ffi_mbt.contains("pub struct ButtonAttributes"))
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn jsx(tag : String, props : ButtonAttributes) -> JsxElement = \"jsx\"",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "pub extern \"js\" fn memo(component : @js.Any) -> @js.Any = \"memo\"",
    ),
  )
}

///|
test "bridge: FFI struct generation deduplicates sanitized field names" {
  let state : MoonBitJsFfiState = {
    declared_type_names: [],
    external_type_names: [],
    needs_js_any: false,
  }
  let iface : @ast.TsInterface = {
    name: "GenericDateConstructor",
    fields: [
      ("<new>", @ast.TsType::Named("DateType")),
      ("<new>", @ast.TsType::Named("DateType")),
      ("<new>", @ast.TsType::Named("DateType")),
    ],
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
  assert_eq(ffi_sanitize_identifier("override", "field"), "override_")
  assert_eq(ffi_sanitize_identifier("method", "field"), "method_")
  assert_eq(ffi_sanitize_identifier("constructor", "field"), "constructor_")
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
    external_type_names: [],
    needs_js_any: false,
  }
  let iface : @ast.TsInterface = {
    name: "Scope",
    fields: [
      ("declare", @ast.TsType::Named("DeclarationParser")),
      ("import", @ast.TsType::Named("Module")),
      ("and", @ast.TsType::Named("NaryIntersectionParser")),
      ("with", @ast.TsType::Named("Scheduler")),
      ("override", @ast.TsType::Boolean),
      ("method", @ast.TsType::String_),
      ("_", @ast.TsType::Named("_")),
      (
        "references",
        @ast.TsType::Applied("Array", [@ast.TsType::Named("BaseNode")]),
      ),
    ],
  }
  let actual = ffi_struct_decl_to_moonbit(state, iface)
  assert_true(actual.contains("  declare_ : DeclarationParser"))
  assert_true(actual.contains("  import_ : Module"))
  assert_true(actual.contains("  and_ : NaryIntersectionParser"))
  assert_true(actual.contains("  with_ : Scheduler"))
  assert_true(actual.contains("  override_ : Bool"))
  assert_true(actual.contains("  method_ : String"))
  assert_true(actual.contains("  field : OpaqueType"))
  assert_true(actual.contains("  references : Array[BaseNode]"))
  assert_false(actual.contains("  _ : Scope"))
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
  assert_true(bundle.ffi_mbt.contains("pub struct Location"))
  assert_eq(count_occurrences_in_ffi_output(bundle.ffi_mbt, "type Location"), 0)
}
