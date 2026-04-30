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
  assert_eq(
    bundle.entry_path,
    "fixtures/resolver/project/types/runtime-function-entry.ts",
  )
  assert_eq(bundle.module_spec, "/runtime/runtime-function.js")
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
async test "bridge: emit MoonBit TS bridge package bundle adds js import when widened types require it" {
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
  assert_true(bundle.moon_pkg_json.contains("\"path\": \"mizchi/js/core\""))
  assert_true(bundle.moon_pkg_json.contains("\"alias\": \"js\""))
  assert_true(bundle.bridge_mbti.contains("declare pub fn get_default()"))
  assert_true(bundle.bridge_mbt.contains("pub extern \"js\" fn get_default()"))
  assert_true(bundle.bridge_js.contains("export function __ts_mbt_get_default"))
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
    bundle.bridge_mbt.contains("#warnings(\"-9\")\npub struct RuntimePoint"),
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
  assert_true(bundle.moon_pkg_json.contains("\"path\": \"mizchi/js/core\""))
  assert_true(bundle.moon_pkg_json.contains("\"alias\": \"js\""))
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
  match render_bridge_public_wrapper(decl) {
    Some(_) => fail("reserved public names should not generate wrappers")
    None => ()
  }
}

///|
test "bridge: bridge top-level fn parser keeps function-typed parameters intact" {
  let line = "declare pub fn forEachLeadingCommentRange(text : String, pos : Double, cb : (Double, Double, CommentKind, Bool) -> U) -> U?"
  match parse_bridge_top_level_fn_decl_line(line) {
    Some(decl) => {
      assert_eq(decl.public_name, "forEachLeadingCommentRange")
      assert_eq(decl.arg_names, ["text", "pos", "cb"])
      assert_eq(
        decl.params_src,
        "text : String, pos : Double, cb : (Double, Double, CommentKind, Bool) -> U",
      )
      match render_bridge_public_wrapper(decl) {
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
