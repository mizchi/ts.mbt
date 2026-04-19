///|
fn count_occurrences_in_decl_output(haystack : String, needle : String) -> Int {
  let mut count = 0
  for _ in haystack.split(needle) {
    count += 1
  }
  count - 1
}

///|
async test "analysis: emit MoonBit declarations from type export surface" {
  let actual = emit_moonbit_decl_from_entry_path(
    "fixtures/resolver/project/types/entry.d.ts",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  let expected =
    #|///|
    #|/// Generated from TypeScript declarations by mizchi/ts/parser.
    #|/// Complex or unsupported TypeScript types are widened to JSValue.
    #|
    #|///|
    #|/// TS interface PublicPoint
    #|/// x : Double
    #|/// y : Double
    #|declare pub type PublicPoint
    #|
    #|///|
    #|declare pub fn render(point : PublicPoint) -> PublicPoint
  assert_eq(actual, expected)
}

///|
async test "analysis: emit MoonBit declarations resolves local import reexports" {
  let actual = emit_moonbit_decl_from_entry_path(
    "fixtures/resolver/project/types/import-reexport-entry.d.ts",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(actual.contains("declare pub type PublicPoint"))
  assert_true(
    actual.contains("declare pub fn render(point : PublicPoint) -> PublicPoint"),
  )
}

///|
async test "analysis: emit MoonBit declarations keeps namespace exports as JSValue notes" {
  let actual = emit_moonbit_decl_from_entry_path(
    "fixtures/resolver/project/types/ns-entry.d.ts",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(actual.contains("declare pub type JSValue"))
  assert_true(
    actual.contains(
      "Unsupported export shapes: namespace export is widened to JSValue.",
    ),
  )
}

///|
async test "analysis: emit MoonBit declarations keeps ambiguous exports as JSValue notes" {
  let actual = emit_moonbit_decl_from_entry_path(
    "fixtures/resolver/project/types/ambiguous-entry.d.ts",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(actual.contains("declare pub type JSValue"))
  assert_true(
    actual.contains(
      "Unsupported export Shared: ambiguous re-export surface is widened to JSValue.",
    ),
  )
}

///|
async test "analysis: emit MoonBit declarations for exported classes" {
  let actual = emit_moonbit_decl_from_entry_path(
    "fixtures/resolver/project/types/class-entry.d.ts",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(actual.contains("declare pub type Counter"))
  assert_true(
    actual.contains("declare pub fn new_counter(initial : Double) -> Counter"),
  )
  assert_true(
    actual.contains(
      "declare pub fn counter_inc(self : Counter, delta : Double) -> Double",
    ),
  )
  assert_true(
    actual.contains("declare pub fn counter_from(seed : Double) -> Counter"),
  )
}

///|
async test "analysis: emit MoonBit declarations for abstract exported classes without constructor" {
  let actual = emit_moonbit_decl_from_entry_path(
    "fixtures/resolver/project/types/abstract-class-entry.d.ts",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(actual.contains("declare pub type Shape"))
  assert_true(
    actual.contains("declare pub fn shape_area(self : Shape) -> Double"),
  )
  assert_false(actual.contains("declare pub fn new_shape("))
}

///|
async test "analysis: emit MoonBit declarations for exported class properties" {
  let actual = emit_moonbit_decl_from_entry_path(
    "fixtures/resolver/project/types/class-property-entry.d.ts",
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
    actual.contains(
      "declare pub fn get_counter_state_current(self : CounterState) -> Double",
    ),
  )
  assert_true(
    actual.contains(
      "declare pub fn get_counter_state_label(self : CounterState) -> String",
    ),
  )
  assert_true(
    actual.contains(
      "declare pub fn set_counter_state_label(self : CounterState, value : String) -> Unit",
    ),
  )
  assert_true(
    actual.contains("declare pub fn get_counter_state_version() -> String"),
  )
  assert_true(
    actual.contains("declare pub fn get_counter_state_step() -> Double"),
  )
  assert_true(
    actual.contains(
      "declare pub fn set_counter_state_step(value : Double) -> Unit",
    ),
  )
  assert_false(actual.contains("set_counter_state_current"))
  assert_false(actual.contains("set_counter_state_version"))
}

///|
async test "analysis: emit MoonBit declarations with unresolved external library types as opaque types" {
  let actual = emit_moonbit_decl_from_entry_path(
    "fixtures/resolver/project/types/external-lib-entry.d.ts",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(actual.contains("declare pub type User"))
  assert_true(actual.contains("declare pub type Result"))
  assert_true(actual.contains("declare pub type ResultAsync"))
  assert_true(
    actual.contains("declare pub fn parseUser(input : String) -> Result"),
  )
  assert_true(
    actual.contains("declare pub fn fetchUser(id : String) -> ResultAsync"),
  )
}

///|
async test "analysis: emit MoonBit declarations with resolved bare-package types as opaque types" {
  let actual = emit_moonbit_decl_from_entry_path(
    "fixtures/resolver/project/types/resolved-lib-entry.d.ts",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(actual.contains("declare pub type User"))
  assert_true(actual.contains("declare pub type PkgTypesValue"))
  assert_true(
    actual.contains("declare pub fn parseUser(input : String) -> PkgTypesValue"),
  )
}

///|
async test "analysis: emit MoonBit declarations with minimal opaque bare-package imports" {
  let actual = emit_moonbit_decl_from_entry_path(
    "fixtures/resolver/project/types/opaque-package-entry.d.ts",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(actual.contains("declare pub type PkgTypesValue"))
  assert_true(
    actual.contains(
      "declare pub fn parseValue(input : String) -> PkgTypesValue",
    ),
  )
}

///|
async test "analysis: emit MoonBit declarations with resolved mixed imports as opaque types" {
  let actual = emit_moonbit_decl_from_entry_path(
    "fixtures/resolver/project/types/resolved-mixed-lib-entry.d.ts",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(actual.contains("declare pub type User"))
  assert_true(actual.contains("declare pub type PkgResult"))
  assert_true(actual.contains("declare pub type PkgResultAsync"))
  assert_true(
    actual.contains("declare pub fn parseUser(input : String) -> PkgResult"),
  )
  assert_true(
    actual.contains("declare pub fn fetchUser(id : String) -> PkgResultAsync"),
  )
}

///|
async test "analysis: emit MoonBit declarations with resolved generic library imports" {
  let actual = emit_moonbit_decl_from_entry_path(
    "fixtures/resolver/project/types/resolved-generic-lib-entry.d.ts",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(actual.contains("declare pub type User"))
  assert_true(actual.contains("declare pub type PkgResult"))
  assert_true(actual.contains("declare pub type PkgResultAsync"))
  assert_true(
    actual.contains("declare pub fn parseUser(input : String) -> PkgResult"),
  )
  assert_true(
    actual.contains("declare pub fn fetchUser(id : String) -> PkgResultAsync"),
  )
}

///|
async test "analysis: emit MoonBit declarations with resolved symlinked library imports" {
  let actual = emit_moonbit_decl_from_entry_path(
    "fixtures/resolver/project/types/resolved-symlink-lib-entry.d.ts",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(actual.contains("declare pub type User"))
  assert_true(actual.contains("declare pub type PkgSymlinkResult"))
  assert_true(actual.contains("declare pub type PkgSymlinkResultAsync"))
  assert_true(
    actual.contains(
      "declare pub fn parseUser(input : String) -> PkgSymlinkResult",
    ),
  )
  assert_true(
    actual.contains(
      "declare pub fn fetchUser(id : String) -> PkgSymlinkResultAsync",
    ),
  )
}

///|
async test "analysis: emit MoonBit declarations with neverthrow-like package imports" {
  let actual = emit_moonbit_decl_from_entry_path(
    "fixtures/resolver/project/types/neverthrow-like-entry.d.ts",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(actual.contains("declare pub type User"))
  assert_true(actual.contains("declare pub type Result"))
  assert_true(actual.contains("declare pub type ResultAsync"))
  assert_true(
    actual.contains("declare pub fn parseUser(input : String) -> Result"),
  )
  assert_true(
    actual.contains("declare pub fn fetchUser(id : String) -> ResultAsync"),
  )
}

///|
async test "analysis: emit MoonBit declarations through package exports subpath" {
  let actual = emit_moonbit_decl_from_entry_path(
    "fixtures/resolver/project/types/subpath-package-entry.d.ts",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(actual.contains("declare pub type FeatureOptions"))
  assert_true(actual.contains("declare pub type FeatureResult"))
  assert_true(
    actual.contains(
      "declare pub fn executeFeature(options : FeatureOptions) -> FeatureResult",
    ),
  )
}

///|
async test "analysis: emit MoonBit declarations through package barrel reexports" {
  let actual = emit_moonbit_decl_from_entry_path(
    "fixtures/resolver/project/types/barrel-package-entry.d.ts",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(actual.contains("declare pub type BarrelOptions"))
  assert_true(actual.contains("declare pub type BarrelResult"))
  assert_true(
    actual.contains(
      "declare pub fn createBarrel(options : BarrelOptions) -> BarrelResult",
    ),
  )
}

///|
async test "analysis: emit MoonBit declarations with node-like ambient qualified types" {
  let actual = emit_moonbit_decl_from_entry_path(
    "fixtures/resolver/project/types/node-like-entry.d.ts",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(actual.contains("declare pub type RuntimeConfig"))
  assert_true(actual.contains("declare pub type NodeRunner"))
  assert_true(actual.contains("declare pub type NodeJS_ProcessEnv"))
  assert_true(
    actual.contains(
      "declare pub fn hasEnv(env : NodeJS_ProcessEnv, key : String) -> Bool",
    ),
  )
}

///|
async test "analysis: emit MoonBit declarations collapse overloads by generated binding name" {
  let actual = emit_moonbit_decl_from_entry_path(
    "fixtures/resolver/project/types/overload-entry.d.ts",
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
    count_occurrences_in_decl_output(actual, "declare pub fn makeCounter"),
    1,
  )
  assert_eq(
    count_occurrences_in_decl_output(actual, "declare pub fn counter_value"),
    1,
  )
}

///|
async test "analysis: emit MoonBit declarations ignore unresolved bare-package reexports" {
  let actual = emit_moonbit_decl_from_entry_path(
    "fixtures/resolver/project/types/unresolved-bare-reexport-entry.d.ts",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(actual.contains("declare pub type LocalOptions"))
  assert_true(
    actual.contains(
      "declare pub fn createOptions(value : String) -> LocalOptions",
    ),
  )
}

///|
async test "analysis: emit MoonBit declarations tolerate transitive ts implementation modules" {
  let actual = emit_moonbit_decl_from_entry_path(
    "fixtures/resolver/project/types/transitive-impl-entry.d.ts",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(actual.contains("declare pub type PublicStyle"))
  assert_true(actual.contains("declare pub type WebviewConfig"))
  assert_true(
    actual.contains("declare pub fn createStyle(id : String) -> PublicStyle"),
  )
}

///|
async test "analysis: emit MoonBit declarations from runtime ts exported functions" {
  let actual = emit_moonbit_decl_from_entry_path(
    "fixtures/resolver/project/types/runtime-function-entry.ts",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(actual.contains("declare pub type RuntimePoint"))
  assert_true(
    actual.contains(
      "declare pub fn scalePoint(point : RuntimePoint, factor : Double) -> RuntimePoint",
    ),
  )
}

///|
async test "analysis: emit MoonBit declarations from runtime tsx exported functions" {
  let actual = emit_moonbit_decl_from_entry_path(
    "fixtures/resolver/project/types/runtime-component-entry.tsx",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(actual.contains("declare pub type BadgeProps"))
  assert_true(actual.contains("declare pub type JSX_Element"))
  assert_true(
    actual.contains(
      "declare pub fn renderBadge(props : BadgeProps) -> JSX_Element",
    ),
  )
}

///|
async test "analysis: emit MoonBit declarations from runtime ts exported const arrow functions" {
  let actual = emit_moonbit_decl_from_entry_path(
    "fixtures/resolver/project/types/runtime-arrow-entry.ts",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(actual.contains("declare pub type RuntimeArrowPoint"))
  assert_true(
    actual.contains(
      "declare pub fn scaleArrowPoint(point : RuntimeArrowPoint, factor : Double) -> RuntimeArrowPoint",
    ),
  )
}

///|
async test "analysis: emit MoonBit declarations from runtime default exported functions" {
  let actual = emit_moonbit_decl_from_entry_path(
    "fixtures/resolver/project/types/runtime-default-function-entry.ts",
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
    actual.contains("declare pub fn default(label : String) -> String"),
  )
}

///|
async test "analysis: emit MoonBit declarations from runtime default exported classes" {
  let actual = emit_moonbit_decl_from_entry_path(
    "fixtures/resolver/project/types/runtime-default-class-entry.ts",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(actual.contains("declare pub type Default"))
  assert_true(
    actual.contains("declare pub fn new_default(initial : Double) -> Default"),
  )
  assert_true(
    actual.contains(
      "declare pub fn default_inc(self : Default, delta : Double) -> Double",
    ),
  )
  assert_true(
    actual.contains("declare pub fn default_from(seed : Double) -> Default"),
  )
}
