///|
async test "bridge: emit MoonBit TS bridge bundle from runtime entry" {
  let bundle = emit_moonbit_ts_bridge_bundle_from_entry_path(
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
  @test.assert_eq(
    bundle.entry_path,
    "fixtures/resolver/project/types/runtime-function-entry.ts",
  )
  @test.assert_eq(bundle.module_spec, "/runtime/runtime-function.js")
  assert_true(
    bundle.decl_mbt.contains(
      "declare pub fn scalePoint(point : RuntimePoint, factor : Double) -> RuntimePoint",
    ),
  )
  assert_true(
    bundle.ffi_mbt.contains(
      "#module(\"/runtime/runtime-function.js\")\npub extern \"js\" fn scale_point(point : RuntimePoint, factor : Double) -> RuntimePoint = \"scalePoint\"",
    ),
  )
  assert_false(bundle.bridge_js.contains("__ts_mbt_scale_point"))
}

///|
async test "bridge: emit MoonBit TS bridge package bundle has no mizchi/js dependency for widened exports" {
  let bundle = emit_moonbit_ts_bridge_package_bundle_from_entry_path(
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
  // The generated bridge now ships its own `JSValue` / `Promise[X]`
  // `#external` types, so the package descriptor must not pull in
  // `mizchi/js`.
  assert_false(bundle.moon_pkg.contains("mizchi/js"))
  assert_true(bundle.bridge_mbt.contains("#external\npub type JSValue"))
  assert_true(bundle.bridge_mbti.contains("declare pub fn get_default()"))
  assert_true(bundle.bridge_mbt.contains("pub extern \"js\" fn get_default()"))
  assert_true(bundle.bridge_js.contains("export function __ts_mbt_get_default"))
}

///|
async test "bridge: emit MoonBit TS bridge package bundle exposes primitive union alias constructors" {
  let bundle = emit_moonbit_ts_bridge_package_bundle_from_entry_path(
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
  assert_true(
    bundle.bridge_mbti.contains(
      "declare pub fn sqlinput_value_from_string(value : String) -> SQLInputValue",
    ),
  )
  assert_true(
    bundle.bridge_mbti.contains(
      "declare pub fn sqlinput_value_from_double(value : Double) -> SQLInputValue",
    ),
  )
  assert_true(
    bundle.bridge_mbti.contains(
      "declare pub fn sqlinput_value_from_int64(value : Int64) -> SQLInputValue",
    ),
  )
  assert_true(
    bundle.bridge_mbt.contains(
      "pub extern \"js\" fn sqlinput_value_from_string(value : String) -> SQLInputValue = \"__ts_mbt_sqlinput_value_from_string\"",
    ),
  )
}

///|
async test "bridge: emit MoonBit TS bridge package bundle wraps camelCase exports" {
  let bundle = emit_moonbit_ts_bridge_package_bundle_from_entry_path(
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
  assert_true(
    bundle.bridge_mbti.contains(
      "declare pub fn scalePoint(point : RuntimePoint, factor : Double) -> RuntimePoint",
    ),
  )
  assert_true(
    bundle.bridge_mbt.contains(
      "#warnings(\"-9\")\npub(all) struct RuntimePoint",
    ),
  )
  assert_true(
    bundle.bridge_mbt.contains(
      "#module(\"/runtime/runtime-function.js\")\nextern \"js\" fn scale_point(point : RuntimePoint, factor : Double) -> RuntimePoint = \"scalePoint\"",
    ),
  )
  assert_true(
    bundle.bridge_mbt.contains(
      "pub fn scalePoint(point : RuntimePoint, factor : Double) -> RuntimePoint {\n  scale_point(point, factor)\n}",
    ),
  )
}

///|
async test "bridge: emit MoonBit TS bridge package bundle exposes interface structs in mbti" {
  let bundle = emit_moonbit_ts_bridge_package_bundle_from_entry_path(
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
  assert_true(bundle.bridge_mbti.contains("pub(all) struct RuntimePoint {"))
  assert_true(bundle.bridge_mbti.contains("  x : Double"))
  assert_true(bundle.bridge_mbti.contains("  y : Double"))
  assert_false(bundle.bridge_mbti.contains("declare pub type RuntimePoint"))
}

///|
async test "bridge: emit MoonBit TS bridge package bundle exposes object type aliases as structs in mbti" {
  let bundle = emit_moonbit_ts_bridge_package_bundle_from_entry_path(
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
  assert_true(bundle.bridge_mbti.contains("pub(all) struct HonoOptions[E] {"))
  assert_true(bundle.bridge_mbti.contains("  strict : Bool?"))
  assert_true(bundle.bridge_mbti.contains("  bindings : E?"))
  assert_false(bundle.bridge_mbti.contains("declare pub type HonoOptions"))
}

///|
async test "bridge: emit MoonBit TS bridge package bundle mirrors simple typealiases" {
  let bundle = emit_moonbit_ts_bridge_package_bundle_from_entry_path(
    "fixtures/resolver/project/types/utility-alias-passthrough-entry.d.ts", "./runtime/utility-alias.js",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(bundle.bridge_mbti.contains("pub type NonNullName = String"))
  assert_true(bundle.bridge_mbt.contains("pub type NonNullName = String"))
  assert_true(bundle.bridge_mbti.contains("pub type WidgetInstance = Widget"))
  assert_true(bundle.bridge_mbt.contains("pub type WidgetInstance = Widget"))
}

///|
async test "bridge: emit MoonBit TS bridge package bundle mirrors aliases to lowered enums once" {
  let bundle = emit_moonbit_ts_bridge_package_bundle_from_entry_path(
    "fixtures/resolver/project/types/enum-alias-passthrough-entry.d.ts", "./runtime/enum-alias.js",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(bundle.bridge_mbti.contains("pub(all) enum ModifierName"))
  assert_true(bundle.bridge_mbti.contains("pub type Modifiers = ModifierName"))
  assert_true(bundle.bridge_mbt.contains("pub type Modifiers = ModifierName"))
  assert_false(bundle.bridge_mbt.contains("pub type Modifiers = String"))
}

///|
async test "bridge: emit MoonBit TS bridge package bundle preserves real-world literal option fields" {
  let bundle = emit_moonbit_ts_bridge_package_bundle_from_entry_path(
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
  assert_true(bundle.bridge_mbti.contains("pub(all) enum NodeEncoding"))
  assert_true(bundle.bridge_mbti.contains("pub(all) enum NodeFlag"))
  assert_true(bundle.bridge_mbti.contains("pub(all) enum ReactButtonType"))
  assert_true(bundle.bridge_mbti.contains("pub(all) enum HonoMode"))
  assert_true(bundle.bridge_mbti.contains("  encoding : NodeEncoding?"))
  assert_true(bundle.bridge_mbti.contains("  flag : NodeFlag?"))
  assert_true(bundle.bridge_mbti.contains("  type_ : ReactButtonType?"))
  assert_true(bundle.bridge_mbti.contains("  mode : HonoMode?"))
  assert_true(
    bundle.bridge_mbt.contains("  encoding : NodeEncoding?") &&
    bundle.bridge_mbt.contains("  flag : NodeFlag?"),
  )
  assert_true(
    bundle.bridge_js.contains("function __ts_mbt_bridge_node_encoding_to_js"),
  )
  assert_true(
    bundle.bridge_js.contains("function __ts_mbt_bridge_node_flag_to_js"),
  )
  assert_true(
    bundle.bridge_js.contains(
      "function __ts_mbt_bridge_react_button_type_to_js",
    ),
  )
  assert_true(
    bundle.bridge_js.contains("function __ts_mbt_bridge_hono_mode_to_js"),
  )
}

///|
async test "bridge: emit MoonBit TS bridge package bundle keeps stable enum constructor names" {
  let bundle = emit_moonbit_ts_bridge_package_bundle_from_entry_path(
    "fixtures/bridge_smoke/stable-constructor-entry.d.ts", "./runtime/stable-constructor.js",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(bundle.bridge_mbti.contains("pub(all) enum StableName {"))
  assert_true(bundle.bridge_mbti.contains("  A_b"))
  assert_true(bundle.bridge_mbti.contains("  A_b2"))
  assert_true(bundle.bridge_mbti.contains("  String_"))
  assert_true(bundle.bridge_mbti.contains("  UnderscorePrivate"))
  assert_true(bundle.bridge_mbti.contains("  Member"))
  assert_true(bundle.bridge_mbt.contains("    A_b => \"a-b\""))
  assert_true(bundle.bridge_mbt.contains("    A_b2 => \"a_b\""))
  assert_true(bundle.bridge_mbt.contains("    String_ => \"String\""))
  assert_true(
    bundle.bridge_mbt.contains("    UnderscorePrivate => \"_private\""),
  )
  assert_true(bundle.bridge_mbt.contains("    Member => \"\""))
}

///|
async test "bridge: emit MoonBit TS bridge package bundle exposes ambient enums" {
  let bundle = emit_moonbit_ts_bridge_package_bundle_from_entry_path(
    "fixtures/resolver/project/types/enum-entry.d.ts", "./runtime/enum.js",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(bundle.bridge_mbti.contains("pub(all) enum Mode {"))
  assert_true(bundle.bridge_mbti.contains("  Read"))
  assert_true(bundle.bridge_mbti.contains("  Write"))
  assert_true(bundle.bridge_mbt.contains("pub(all) enum Mode {"))
  assert_true(
    bundle.bridge_mbti.contains("declare pub fn setMode(mode : Mode) -> Mode"),
  )
  assert_false(
    bundle.bridge_mbt.contains(
      "pub extern \"js\" fn set_mode(mode : Mode) -> Mode",
    ),
  )
  assert_true(
    bundle.bridge_mbt.contains(
      "extern \"js\" fn set_mode(mode : String) -> String",
    ),
  )
  assert_true(
    bundle.bridge_mbt.contains("fn __ts_mbt_mode_to_js(value : Mode) -> String"),
  )
  assert_true(bundle.bridge_mbt.contains("Read => \"read\""))
  assert_true(
    bundle.bridge_mbt.contains(
      "fn __ts_mbt_mode_from_js(value : String) -> Mode",
    ),
  )
  assert_true(
    bundle.bridge_mbt.contains(
      "_ => abort(\"unexpected Mode value: \" + value)",
    ),
  )
  assert_true(
    bundle.bridge_mbt.contains(
      "pub fn setMode(mode : Mode) -> Mode {\n  __ts_mbt_mode_from_js(set_mode(__ts_mbt_mode_to_js(mode)))\n}",
    ),
  )
  assert_true(
    bundle.bridge_mbti.contains(
      "declare pub fn maybeMode(mode : Mode?) -> Mode?",
    ),
  )
  assert_true(
    bundle.bridge_mbt.contains(
      "extern \"js\" fn maybe_mode(mode : String?) -> String?",
    ),
  )
  assert_true(
    bundle.bridge_mbt.contains(
      "fn __ts_mbt_mode_to_js_optional(value : Mode?) -> String?",
    ),
  )
  assert_true(
    bundle.bridge_mbt.contains(
      "fn __ts_mbt_mode_from_js_optional(value : String?) -> Mode?",
    ),
  )
  assert_true(
    bundle.bridge_mbt.contains(
      "pub fn maybeMode(mode : Mode?) -> Mode? {\n  __ts_mbt_mode_from_js_optional(maybe_mode(__ts_mbt_mode_to_js_optional(mode)))\n}",
    ),
  )
  assert_false(bundle.bridge_mbt.contains("get_mode() -> JSValue"))
  assert_false(bundle.bridge_js.contains("import { Mode }"))
}

///|
async test "bridge: emit MoonBit TS bridge package bundle exposes runtime ts enums" {
  let bundle = emit_moonbit_ts_bridge_package_bundle_from_entry_path(
    "fixtures/resolver/project/types/runtime-enum-entry.ts", "/runtime/runtime-enum.js",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(bundle.bridge_mbti.contains("pub(all) enum RuntimeMode {"))
  assert_true(bundle.bridge_mbti.contains("  Read"))
  assert_true(bundle.bridge_mbti.contains("  Write"))
  assert_true(
    bundle.bridge_mbti.contains(
      "declare pub fn flipMode(mode : RuntimeMode) -> RuntimeMode",
    ),
  )
  assert_true(
    bundle.bridge_mbt.contains(
      "extern \"js\" fn flip_mode(mode : String) -> String",
    ),
  )
  assert_true(
    bundle.bridge_mbt.contains(
      "pub fn flipMode(mode : RuntimeMode) -> RuntimeMode {\n  __ts_mbt_runtime_mode_from_js(flip_mode(__ts_mbt_runtime_mode_to_js(mode)))\n}",
    ),
  )
  assert_false(bundle.bridge_js.contains("import { RuntimeMode }"))
}

///|
async test "bridge: emit MoonBit TS bridge package bundle exposes numeric ambient enums" {
  let bundle = emit_moonbit_ts_bridge_package_bundle_from_entry_path(
    "fixtures/resolver/project/types/numeric-enum-entry.d.ts", "./runtime/numeric-enum.js",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(bundle.bridge_mbti.contains("pub(all) enum SyntaxKind {"))
  assert_true(bundle.bridge_mbti.contains("  Unknown"))
  assert_true(bundle.bridge_mbti.contains("  Identifier"))
  assert_true(bundle.bridge_mbti.contains("  PrivateIdentifier"))
  assert_true(
    bundle.bridge_mbti.contains(
      "declare pub fn nextKind(kind : SyntaxKind) -> SyntaxKind",
    ),
  )
  assert_true(
    bundle.bridge_mbt.contains("extern \"js\" fn next_kind(kind : Int) -> Int"),
  )
  assert_true(
    bundle.bridge_mbt.contains(
      "fn __ts_mbt_syntax_kind_to_js(value : SyntaxKind) -> Int",
    ),
  )
  assert_true(bundle.bridge_mbt.contains("Identifier => 80"))
  assert_true(bundle.bridge_mbt.contains("PrivateIdentifier => 81"))
  assert_true(
    bundle.bridge_mbt.contains(
      "fn __ts_mbt_syntax_kind_from_js(value : Int) -> SyntaxKind",
    ),
  )
  assert_true(
    bundle.bridge_mbt.contains(
      "abort(\"unexpected SyntaxKind value: \" + value.to_string())",
    ),
  )
  assert_true(
    bundle.bridge_mbt.contains(
      "pub fn nextKind(kind : SyntaxKind) -> SyntaxKind {\n  __ts_mbt_syntax_kind_from_js(next_kind(__ts_mbt_syntax_kind_to_js(kind)))\n}",
    ),
  )
  assert_true(
    bundle.bridge_mbt.contains(
      "extern \"js\" fn maybe_kind(kind : Int?) -> Int?",
    ),
  )
  assert_true(
    bundle.bridge_mbt.contains(
      "fn __ts_mbt_syntax_kind_to_js_optional(value : SyntaxKind?) -> Int?",
    ),
  )
  assert_true(
    bundle.bridge_mbt.contains(
      "fn __ts_mbt_syntax_kind_from_js_optional(value : Int?) -> SyntaxKind?",
    ),
  )
  assert_true(
    bundle.bridge_mbt.contains(
      "pub fn maybeKind(kind : SyntaxKind?) -> SyntaxKind? {\n  __ts_mbt_syntax_kind_from_js_optional(maybe_kind(__ts_mbt_syntax_kind_to_js_optional(kind)))\n}",
    ),
  )
  assert_false(bundle.bridge_js.contains("import { SyntaxKind }"))
}

///|
async test "bridge: emit MoonBit TS bridge package bundle widens int-min numeric enums to double raw values" {
  let bundle = emit_moonbit_ts_bridge_package_bundle_from_entry_path(
    "fixtures/resolver/project/types/large-numeric-enum-entry.d.ts", "./runtime/large-numeric-enum.js",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(bundle.bridge_mbti.contains("pub(all) enum EmitFlags {"))
  assert_true(
    bundle.bridge_mbti.contains(
      "declare pub fn setEmitFlag(flag : EmitFlags) -> EmitFlags",
    ),
  )
  assert_true(
    bundle.bridge_mbt.contains(
      "extern \"js\" fn set_emit_flag(flag : Double) -> Double",
    ),
  )
  assert_true(
    bundle.bridge_mbt.contains(
      "fn __ts_mbt_emit_flags_to_js(value : EmitFlags) -> Double",
    ),
  )
  assert_true(
    bundle.bridge_mbt.contains(
      "ExcludeJSDocTypeAssertion => (-536870912.0 * 4.0)",
    ),
  )
  assert_true(
    bundle.bridge_mbt.contains(
      "else if value == (-536870912.0 * 4.0) {\n    ExcludeJSDocTypeAssertion\n  }",
    ),
  )
  assert_true(
    bundle.bridge_mbt.contains(
      "pub fn setEmitFlag(flag : EmitFlags) -> EmitFlags {\n  __ts_mbt_emit_flags_from_js(set_emit_flag(__ts_mbt_emit_flags_to_js(flag)))\n}",
    ),
  )
}

///|
async test "bridge: emit MoonBit TS bridge package bundle exposes heterogeneous unions as tagged enums" {
  // magic-string `hires: boolean | "boundary"` style alias. The bundle should
  // emit a public tagged enum, primitive externs, public wrappers, and the
  // bridge.js converter pair.
  let bundle = emit_moonbit_ts_bridge_package_bundle_from_entry_path(
    "fixtures/resolver/project/types/heterogeneous-union-alias-entry.d.ts", "./runtime/heterogeneous-union-alias.js",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  // Public tagged-union enum decl — Boundary is no-payload.
  assert_true(bundle.bridge_mbti.contains("pub(all) enum Hires {"))
  assert_true(bundle.bridge_mbti.contains("BoolValue(Bool)"))
  assert_true(bundle.bridge_mbt.contains("\n  Boundary\n"))
  // The bridge.js converter pair for `Hires` must be present.
  assert_true(bundle.bridge_js.contains("__ts_mbt_tagged_union_hires_to_js"))
  assert_true(bundle.bridge_js.contains("__ts_mbt_tagged_union_hires_from_js"))
  assert_true(bundle.bridge_js.contains("\"boundary\""))
  // Public wrapper: `setHires(value : Hires) -> Hires`.
  assert_true(
    bundle.bridge_mbti.contains(
      "declare pub fn setHires(value : Hires) -> Hires",
    ),
  )
}

///|
async test "bridge: emit MoonBit TS bridge package bundle exposes string literal aliases as enums" {
  let bundle = emit_moonbit_ts_bridge_package_bundle_from_entry_path(
    "fixtures/resolver/project/types/literal-union-alias-entry.d.ts", "./runtime/literal-union-alias.js",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(bundle.bridge_mbti.contains("pub(all) enum ButtonVariant {"))
  assert_true(bundle.bridge_mbti.contains("  Solid"))
  assert_true(bundle.bridge_mbti.contains("  Ghost"))
  assert_true(
    bundle.bridge_mbti.contains(
      "declare pub fn renderButton(variant : ButtonVariant) -> ButtonVariant",
    ),
  )
  assert_true(
    bundle.bridge_mbt.contains(
      "extern \"js\" fn render_button(variant : String) -> String",
    ),
  )
  assert_true(
    bundle.bridge_mbt.contains(
      "pub fn renderButton(variant : ButtonVariant) -> ButtonVariant {\n  __ts_mbt_button_variant_from_js(render_button(__ts_mbt_button_variant_to_js(variant)))\n}",
    ),
  )
  assert_true(
    bundle.bridge_mbti.contains(
      "declare pub fn maybeVariant(variant : ButtonVariant?) -> ButtonVariant?",
    ),
  )
  assert_true(
    bundle.bridge_mbt.contains(
      "pub fn maybeVariant(variant : ButtonVariant?) -> ButtonVariant? {\n  __ts_mbt_button_variant_from_js_optional(maybe_variant(__ts_mbt_button_variant_to_js_optional(variant)))\n}",
    ),
  )
}

///|
async test "bridge: emit MoonBit TS bridge package bundle exposes numeric literal aliases as enums" {
  let bundle = emit_moonbit_ts_bridge_package_bundle_from_entry_path(
    "fixtures/resolver/project/types/numeric-literal-union-entry.d.ts", "./runtime/numeric-literal-union.js",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(bundle.bridge_mbti.contains("pub(all) enum StatusCode {"))
  assert_true(bundle.bridge_mbti.contains("  N200"))
  assert_true(bundle.bridge_mbti.contains("  N404"))
  assert_true(
    bundle.bridge_mbti.contains(
      "declare pub fn nextStatus(code : StatusCode) -> StatusCode",
    ),
  )
  assert_true(
    bundle.bridge_mbt.contains(
      "extern \"js\" fn next_status(code : Int) -> Int",
    ),
  )
  assert_true(
    bundle.bridge_mbt.contains(
      "fn __ts_mbt_status_code_to_js(value : StatusCode) -> Int",
    ),
  )
  assert_true(bundle.bridge_mbt.contains("N200 => 200"))
  assert_true(bundle.bridge_mbt.contains("N404 => 404"))
  assert_true(
    bundle.bridge_mbt.contains(
      "pub fn nextStatus(code : StatusCode) -> StatusCode {\n  __ts_mbt_status_code_from_js(next_status(__ts_mbt_status_code_to_js(code)))\n}",
    ),
  )
  assert_true(
    bundle.bridge_mbt.contains(
      "pub fn maybeStatus(code : StatusCode?) -> StatusCode? {\n  __ts_mbt_status_code_from_js_optional(maybe_status(__ts_mbt_status_code_to_js_optional(code)))\n}",
    ),
  )
}

///|
async test "bridge: emit MoonBit TS bridge package bundle names anonymous literal unions" {
  let bundle = emit_moonbit_ts_bridge_package_bundle_from_entry_path(
    "fixtures/resolver/project/types/anonymous-literal-union-entry.d.ts", "./runtime/anonymous-literal-union.js",
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
    bundle.bridge_mbti.contains("pub(all) enum ButtonOptionsVariant {"),
  )
  assert_true(
    bundle.bridge_mbti.contains("pub(all) enum RenderButtonVariant {"),
  )
  assert_true(bundle.bridge_mbti.contains("pub(all) enum RenderButtonReturn {"))
  assert_true(bundle.bridge_mbti.contains("  variant : ButtonOptionsVariant"))
  assert_true(
    bundle.bridge_mbti.contains(
      "declare pub fn renderButton(variant : RenderButtonVariant) -> RenderButtonReturn",
    ),
  )
  assert_true(
    bundle.bridge_mbt.contains(
      "extern \"js\" fn render_button(variant : String) -> String",
    ),
  )
  assert_true(
    bundle.bridge_mbt.contains(
      "pub fn renderButton(variant : RenderButtonVariant) -> RenderButtonReturn {\n  __ts_mbt_render_button_return_from_js(render_button(__ts_mbt_render_button_variant_to_js(variant)))\n}",
    ),
  )
  assert_true(
    bundle.bridge_js.contains(
      "function __ts_mbt_bridge_button_options_variant_to_js",
    ),
  )
  assert_false(
    bundle.bridge_mbti.contains("anonymous literal union in public surface"),
  )
}

///|
async test "bridge: emit MoonBit TS bridge package bundle names anonymous numeric literal unions" {
  let bundle = emit_moonbit_ts_bridge_package_bundle_from_entry_path(
    "fixtures/resolver/project/types/anonymous-numeric-literal-union-entry.d.ts",
    "./runtime/anonymous-numeric-literal-union.js",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(bundle.bridge_mbti.contains("pub(all) enum NextStatusCode {"))
  assert_true(bundle.bridge_mbti.contains("pub(all) enum NextStatusReturn {"))
  assert_true(
    bundle.bridge_mbti.contains(
      "declare pub fn nextStatus(code : NextStatusCode) -> NextStatusReturn",
    ),
  )
  assert_true(
    bundle.bridge_mbt.contains(
      "extern \"js\" fn next_status(code : Int) -> Int",
    ),
  )
  assert_true(
    bundle.bridge_mbt.contains(
      "pub fn nextStatus(code : NextStatusCode) -> NextStatusReturn {\n  __ts_mbt_next_status_return_from_js(next_status(__ts_mbt_next_status_code_to_js(code)))\n}",
    ),
  )
}

///|
async test "bridge: emit MoonBit TS bridge package bundle partial-evaluates keyof / mapped / template literal" {
  let bundle = emit_moonbit_ts_bridge_package_bundle_from_entry_path(
    "fixtures/resolver/project/types/keyof-mapped-templit-entry.d.ts", "./runtime/keyof-mapped-templit.js",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  // Template-literal cartesian over inline literal unions lands as a
  // four-member string enum.
  assert_true(bundle.bridge_mbti.contains("pub(all) enum DirectBanner"))
  assert_true(bundle.bridge_mbti.contains("Info_small"))
  assert_true(bundle.bridge_mbti.contains("Info_large"))
  assert_true(bundle.bridge_mbti.contains("Warn_small"))
  assert_true(bundle.bridge_mbti.contains("Warn_large"))
  // `Capitalize<"world">` reduces to a single literal at the alias
  // surface.
  assert_true(bundle.bridge_mbti.contains("pub(all) enum Greeting"))
  // Mapped type over a finite literal-union source materializes a struct
  // with concrete keys.
  assert_true(bundle.bridge_mbti.contains("pub(all) struct FooFlags"))
  assert_true(bundle.bridge_mbti.contains("a : Bool"))
  assert_true(bundle.bridge_mbti.contains("b : Bool"))
  assert_true(bundle.bridge_mbti.contains("c : Bool"))
  // `keyof Foo` at a parameter position widens to `String` rather than
  // leaking a `Keyof(...)` shape into the bridge surface.
  assert_true(bundle.bridge_mbti.contains("pickFooKey"))
  assert_false(bundle.bridge_mbti.contains("Keyof("))
}

///|
async test "bridge: emit MoonBit TS bridge package bundle expands alias-indirected template literal" {
  let bundle = emit_moonbit_ts_bridge_package_bundle_from_entry_path(
    "fixtures/resolver/project/types/banner-alias-templit-entry.d.ts", "./runtime/banner.js",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  // Channel / Variant remain available as enums.
  assert_true(bundle.bridge_mbti.contains("pub(all) enum Channel"))
  assert_true(bundle.bridge_mbti.contains("pub(all) enum Variant"))
  // Banner = `${Channel}-${Variant}` should land as a four-member string
  // enum after alias indirections are inlined and the cartesian product
  // expanded.
  assert_true(bundle.bridge_mbti.contains("pub(all) enum Banner"))
  assert_true(bundle.bridge_mbti.contains("Info_small"))
  assert_true(bundle.bridge_mbti.contains("Info_large"))
  assert_true(bundle.bridge_mbti.contains("Warn_small"))
  assert_true(bundle.bridge_mbti.contains("Warn_large"))
  assert_false(bundle.bridge_mbti.contains("declare pub type Banner"))
  // No "Unresolved type reference Banner" diagnostic should leak into
  // the generated mbti as a comment.
  assert_false(bundle.bridge_mbti.contains("Unresolved type reference Banner"))
}

///|
async test "bridge: emit MoonBit TS bridge package bundle expands real-world zod HashFormat alias" {
  // Verbatim from zod/v4/core/util.d.ts. 5 algorithms × 3 encodings ⇒
  // a 15-member string enum.
  let bundle = emit_moonbit_ts_bridge_package_bundle_from_entry_path(
    "fixtures/resolver/project/types/zod-hash-format-entry.d.ts", "./runtime/zod-hash-format.js",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(bundle.bridge_mbti.contains("pub(all) enum HashFormat"))
  assert_true(bundle.bridge_mbti.contains("Md5_hex"))
  assert_true(bundle.bridge_mbti.contains("Sha512_base64url"))
  assert_false(bundle.bridge_mbti.contains("declare pub type HashFormat"))
}

///|
async test "bridge: emit MoonBit TS bridge package bundle resolves cross-file qualified template literal" {
  // `import * as util from "./..."` exposes the sub-module under a
  // namespace alias; the template literal `${util.HashAlgorithm}_${util.HashEncoding}`
  // must walk that namespace edge to inline the literal-union aliases
  // declared in the imported module before the cartesian expansion.
  let bundle = emit_moonbit_ts_bridge_package_bundle_from_entry_path(
    "fixtures/resolver/project/types/qualified-templit-entry.d.ts", "./runtime/qualified-templit.js",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(bundle.bridge_mbti.contains("pub(all) enum HashFormat"))
  assert_true(bundle.bridge_mbti.contains("Md5_hex"))
  assert_true(bundle.bridge_mbti.contains("Sha256_base64"))
  assert_false(bundle.bridge_mbti.contains("declare pub type HashFormat"))
  assert_false(bundle.bridge_mbti.contains("Unresolved type reference util."))
}

///|
async test "bridge: emit MoonBit TS bridge package bundle expands consumer keyof + prefixed templit" {
  // Consumer-style: concrete `Schema` interface drives `keyof Schema`
  // and `\`prefix_\${SchemaKeys}\``. Both should partial-evaluate to
  // string enums end-to-end without alias indirection blocking the
  // chain.
  let bundle = emit_moonbit_ts_bridge_package_bundle_from_entry_path(
    "fixtures/resolver/project/types/consumer-instantiation-entry.d.ts", "./runtime/consumer-instantiation.js",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  // `keyof Schema` reaches the alias surface as a 3-member enum.
  assert_true(bundle.bridge_mbti.contains("pub(all) enum SchemaKeys"))
  assert_true(bundle.bridge_mbti.contains("Id"))
  assert_true(bundle.bridge_mbti.contains("Name"))
  assert_true(bundle.bridge_mbti.contains("Age"))
  // `\`prefix_\${SchemaKeys}\`` chains through the simplifier and lands
  // as a 3-member enum (`Prefix_id`, `Prefix_name`, `Prefix_age`).
  assert_true(bundle.bridge_mbti.contains("pub(all) enum SchemaPrefixed"))
  assert_true(bundle.bridge_mbti.contains("Prefix_id"))
  assert_true(bundle.bridge_mbti.contains("Prefix_name"))
  assert_true(bundle.bridge_mbti.contains("Prefix_age"))
  assert_false(bundle.bridge_mbti.contains("declare pub type SchemaPrefixed"))
  // `{ [K in keyof Schema]: boolean }` partial-evaluates to a concrete
  // object literal, which the bridge then surfaces as a synthetic
  // interface emitted as `pub(all) struct SchemaFlags`.
  assert_true(bundle.bridge_mbti.contains("pub(all) struct SchemaFlags"))
  assert_true(bundle.bridge_mbti.contains("id : Bool"))
  assert_true(bundle.bridge_mbti.contains("name : Bool"))
  assert_true(bundle.bridge_mbti.contains("age : Bool"))
  assert_false(bundle.bridge_mbti.contains("declare pub type SchemaFlags"))
}

///|
async test "bridge: emit MoonBit TS bridge package bundle expands consumer Pick / Omit / Partial / Readonly aliases" {
  let bundle = emit_moonbit_ts_bridge_package_bundle_from_entry_path(
    "fixtures/resolver/project/types/utility-instantiation-entry.d.ts", "./runtime/utility-instantiation.js",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  // `Pick<Schema, "id">` → struct with just `id`.
  assert_true(bundle.bridge_mbti.contains("pub(all) struct IdOnly"))
  // `Pick<Schema, "id" | "name">` → struct with both.
  assert_true(bundle.bridge_mbti.contains("pub(all) struct IdAndName"))
  // `Omit<Schema, "age">` → struct without `age`.
  assert_true(bundle.bridge_mbti.contains("pub(all) struct WithoutAge"))
  assert_false(
    bundle.bridge_mbti.contains(
      "struct WithoutAge {\n  id : Double\n  name : String\n  age",
    ),
  )
  // `Partial<Schema>` → every field becomes optional.
  assert_true(bundle.bridge_mbti.contains("pub(all) struct SchemaPartial"))
  assert_true(bundle.bridge_mbti.contains("id : Double?"))
  assert_true(bundle.bridge_mbti.contains("name : String?"))
  // `Readonly<Schema>` → struct (the readonly marker is dropped at the
  // MoonBit-side surface).
  assert_true(bundle.bridge_mbti.contains("pub(all) struct SchemaReadonly"))
  // None of the aliases should leak as `declare pub type X`.
  assert_false(bundle.bridge_mbti.contains("declare pub type IdOnly"))
  assert_false(bundle.bridge_mbti.contains("declare pub type IdAndName"))
  assert_false(bundle.bridge_mbti.contains("declare pub type WithoutAge"))
  assert_false(bundle.bridge_mbti.contains("declare pub type SchemaPartial"))
  assert_false(bundle.bridge_mbti.contains("declare pub type SchemaReadonly"))
  // Chained utility instantiation: `Required<SchemaPartial>` walks the
  // alias chain to `Partial<Schema>` → `Schema`, then strips the
  // optional, recovering the original required fields.
  assert_true(bundle.bridge_mbti.contains("pub(all) struct SchemaRequired"))
  assert_false(bundle.bridge_mbti.contains("declare pub type SchemaRequired"))
  // Re-projecting an already-projected alias.
  assert_true(bundle.bridge_mbti.contains("pub(all) struct IdRePick"))
  assert_false(bundle.bridge_mbti.contains("declare pub type IdRePick"))
  // `Record<"ok" | "error", number>` lands as a struct with literal-key
  // fields.
  assert_true(bundle.bridge_mbti.contains("pub(all) struct StatusMap"))
  assert_true(bundle.bridge_mbti.contains("ok : Double"))
  assert_true(bundle.bridge_mbti.contains("error : Double"))
  assert_false(bundle.bridge_mbti.contains("declare pub type StatusMap"))
}

///|
async test "bridge: emit MoonBit TS bridge package bundle expands cross-file Omit utility" {
  // Mirrors the puppeteer pattern:
  //   import * as bidi from "./...";
  //   type CallFunctionOptions = Omit<bidi.CallFunctionParameters, ...>;
  // Bridge must walk the namespace alias before the `Omit` projection.
  let bundle = emit_moonbit_ts_bridge_package_bundle_from_entry_path(
    "fixtures/resolver/project/types/cross-file-utility-entry.d.ts", "./runtime/cross-file-utility.js",
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
    bundle.bridge_mbti.contains("pub(all) struct CallFunctionOptions"),
  )
  assert_true(bundle.bridge_mbti.contains("arguments : Array[String]"))
  assert_true(bundle.bridge_mbti.contains("thisArgument : String"))
  // Excluded keys must be gone from the projected struct.
  assert_false(bundle.bridge_mbti.contains("functionDeclaration : String"))
  assert_false(bundle.bridge_mbti.contains("awaitPromise : Bool"))
  assert_false(
    bundle.bridge_mbti.contains("declare pub type CallFunctionOptions"),
  )
}

///|
async test "bridge: emit MoonBit TS bridge package bundle lowers boolean literal aliases to bool" {
  let bundle = emit_moonbit_ts_bridge_package_bundle_from_entry_path(
    "fixtures/resolver/project/types/boolean-literal-union-entry.d.ts", "./runtime/boolean-literal-union.js",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_false(bundle.bridge_mbti.contains("enum FeatureFlag"))
  assert_false(bundle.bridge_mbti.contains("enum AlwaysOn"))
  assert_true(
    bundle.bridge_mbti.contains("declare pub fn flipFlag(flag : Bool) -> Bool"),
  )
  assert_true(
    bundle.bridge_mbti.contains(
      "declare pub fn maybeAlways(flag : Bool?) -> Bool?",
    ),
  )
  assert_true(
    bundle.bridge_mbt.contains(
      "extern \"js\" fn flip_flag(flag : Bool) -> Bool",
    ),
  )
  assert_true(
    bundle.bridge_mbt.contains(
      "extern \"js\" fn maybe_always(flag : Bool?) -> Bool?",
    ),
  )
}

///|
async test "bridge: emit MoonBit TS bridge package bundle exposes namespace exports as opaque getters" {
  let bundle = emit_moonbit_ts_bridge_package_bundle_from_entry_path(
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
  assert_true(bundle.bridge_mbti.contains("declare pub type Shapes"))
  assert_true(
    bundle.bridge_mbti.contains("declare pub fn get_shapes() -> Shapes"),
  )
  assert_true(bundle.bridge_mbt.contains("pub extern \"js\" fn get_shapes()"))
  // No `mizchi/js` dependency: the bridge declares `JSValue` itself.
  assert_false(bundle.moon_pkg.contains("mizchi/js"))
  assert_true(
    bundle.bridge_js.contains("export function __ts_mbt_get_shapes()"),
  )
}

///|
async test "bridge: emit MoonBit TS bridge package bundle adds ergonomic cast and guard helpers" {
  let bundle = emit_moonbit_ts_bridge_package_bundle_from_entry_path(
    "fixtures/resolver/project/types/type-guard-entry.d.ts", "/runtime/type-guard.js",
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
    bundle.bridge_mbti.contains(
      "declare pub fn[A, B] unsafeCast(value : A) -> B",
    ),
  )
  assert_true(
    bundle.bridge_mbt.contains(
      "pub fn[A, B] unsafeCast(value : A) -> B = \"%identity\"",
    ),
  )
  assert_true(
    bundle.bridge_mbti.contains(
      "declare pub fn asIdentifier(self : Node) -> Identifier?",
    ),
  )
  assert_true(
    bundle.bridge_mbt.contains(
      "pub fn Node::asIdentifier(self : Node) -> Identifier? {",
    ),
  )
  assert_true(bundle.bridge_mbt.contains("if isIdentifier(self) {"))
  assert_true(bundle.bridge_mbt.contains("Some(unsafeCast(self))"))
}

///|
test "bridge: bridge public wrapper skips reserved public names" {
  let decl : BridgeTopLevelFnDecl = {
    public_name: "enum",
    params_src: "value : String",
    arg_names: ["value"],
    return_type: "String",
  }
  match
    render_bridge_public_wrapper_with_converters(
      decl,
      [],
      bridge_value_fn_name(decl.public_name),
    ) {
    Some(_) => fail("reserved public names should not generate wrappers")
    None => ()
  }
}

///|
test "bridge: bridge top-level fn parser keeps function-typed parameters intact" {
  let line = "declare pub fn forEachLeadingCommentRange(text : String, pos : Double, cb : (Double, Double, CommentKind, Bool) -> U) -> U?"
  match parse_bridge_top_level_fn_decl_line(line) {
    Some(decl) => {
      @test.assert_eq(decl.public_name, "forEachLeadingCommentRange")
      @test.assert_eq(decl.arg_names, ["text", "pos", "cb"])
      @test.assert_eq(
        decl.params_src,
        "text : String, pos : Double, cb : (Double, Double, CommentKind, Bool) -> U",
      )
      match
        render_bridge_public_wrapper_with_converters(
          decl,
          [],
          bridge_value_fn_name(decl.public_name),
        ) {
        Some(wrapper) =>
          assert_true(
            wrapper.contains("for_each_leading_comment_range(text, pos, cb)"),
          )
        None => fail("expected wrapper for camelCase function")
      }
    }
    None => fail("expected function declaration to parse")
  }
}

///|
test "bridge mbti: index-signature accessors are exposed in the interface" {
  // `.mbt` carries the struct plus its `op_get` / `op_set` externs; the
  // `.mbti` only had a `declare pub type` placeholder. The exposer must
  // surface the public accessor signatures so the generated contract shows
  // that the record supports `dict[key]` indexing.
  let bridge_mbt =
    #|#warnings("-9")
    #|pub(all) struct Dict {
    #|}
    #|
    #|pub extern "js" fn Dict::op_get(self : Dict, key : String) -> Double? =
    #|  #| (self, key) => { const v = self[key]; return v === undefined ? null : v; }
    #|
    #|pub extern "js" fn Dict::op_set(self : Dict, key : String, value : Double) -> Unit =
    #|  #| (self, key, value) => { self[key] = value; }
  let bridge_mbti =
    #|///|
    #|/// TS interface Dict
    #|declare pub type Dict
  let exposed = expose_bridge_struct_decls_in_mbti(bridge_mbti, bridge_mbt)
  assert_true(exposed.contains("pub(all) struct Dict {"))
  assert_true(
    exposed.contains(
      "pub fn Dict::op_get(self : Dict, key : String) -> Double?",
    ),
  )
  assert_true(
    exposed.contains(
      "pub fn Dict::op_set(self : Dict, key : String, value : Double) -> Unit",
    ),
  )
  // The JS body and the `extern "js"` keyword must not leak into the
  // interface form.
  assert_false(exposed.contains("extern"))
  assert_false(exposed.contains("self[key]"))
}

///|
test "bridge: boxed optional returns get a MoonBit-side Option wrapper" {
  // `Option[T]` is only unboxed for String/Int/struct/enum payloads on
  // the JS backend; opaque handles, JSValue, Double and arrays use the
  // `{$tag, _0}` box, so raw `value | undefined` extern returns must be
  // rebuilt via `__ts_mbt_wrap_option_return`.
  let opaque : Array[String] = ["SQL", "JSValue"]
  assert_true(bridge_optional_return_needs_wrap(opaque, "SQL[JSValue]?"))
  assert_true(bridge_optional_return_needs_wrap(opaque, "JSValue?"))
  assert_true(bridge_optional_return_needs_wrap(opaque, "Double?"))
  assert_true(bridge_optional_return_needs_wrap(opaque, "Array[String]?"))
  assert_true(
    bridge_optional_return_needs_wrap(opaque, "((String) -> JSValue)?"),
  )
  // Unboxed payloads keep the raw passthrough.
  assert_false(bridge_optional_return_needs_wrap(opaque, "String?"))
  assert_false(bridge_optional_return_needs_wrap(opaque, "Bool?"))
  // The trailing `?` of a function-typed return binds to the function's
  // result, not the whole type.
  assert_false(
    bridge_optional_return_needs_wrap(
      opaque, "() -> ((PropsForRenderer) -> JSValue)?",
    ),
  )
  assert_false(bridge_optional_return_needs_wrap(opaque, "SQL[JSValue]"))
}

///|
test "bridge: top-level optional extern demotes to raw plus Option wrapper" {
  let bridge_mbti =
    #|declare pub type JSValue
    #|declare pub type SQL[T]
    #|declare pub fn and_(conditions : Array[SQLWrapper?]) -> SQL[JSValue]?
  let bridge_mbt =
    #|#external
    #|pub type JSValue
    #|
    #|pub extern "js" fn and_(conditions : Array[SQLWrapper?]) -> SQL[JSValue]? = "__ts_mbt_and"
  let rewritten = add_bridge_public_wrappers(bridge_mbti, bridge_mbt)
  assert_true(rewritten.contains("extern \"js\" fn and__raw("))
  assert_true(
    rewritten.contains(
      "pub fn and_(conditions : Array[SQLWrapper?]) -> SQL[JSValue]? {\n  __ts_mbt_wrap_option_return(unsafeCast(and__raw(conditions)))\n}",
    ),
  )
  assert_true(rewritten.contains("fn[T] __ts_mbt_wrap_option_return"))
}
