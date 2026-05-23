// Tests for JSX → `react/jsx-runtime` (and classic React.createElement)
// lowering. Each case feeds raw TSX through `transform_source_with`
// and asserts the emitted JS contains / lacks the expected fragments.

///|
fn assert_emit_contains(
  label : String,
  src : String,
  cfg : JsxConfig,
  needles : Array[String],
) -> Unit raise {
  match transform_source_with(src, cfg) {
    Ok(js) =>
      for needle in needles {
        if !js.contains(needle) {
          println("FAIL [\{label}] missing \"\{needle}\" in:")
          println(js)
          fail("missing fragment: \{needle}")
        }
      }
    Err(e) => fail("[\{label}] transform error: \{e}")
  }
}

///|
fn assert_emit_lacks(
  label : String,
  src : String,
  cfg : JsxConfig,
  needles : Array[String],
) -> Unit raise {
  match transform_source_with(src, cfg) {
    Ok(js) =>
      for needle in needles {
        if js.contains(needle) {
          println("FAIL [\{label}] forbidden \"\{needle}\" in:")
          println(js)
          fail("forbidden fragment: \{needle}")
        }
      }
    Err(e) => fail("[\{label}] transform error: \{e}")
  }
}

///|
test "jsx: automatic runtime — single component lowers to `jsx(...)`" {
  let cfg = JsxConfig::default()
  assert_emit_contains(
    "auto-single",
    "const el = <Foo bar={1} />;",
    cfg,
    [
      "import { jsx } from \"react/jsx-runtime\";",
      "jsx(Foo,",
      "bar:",
      "1",
    ],
  )
}

///|
test "jsx: automatic runtime — multiple children lower to `jsxs(...)`" {
  let cfg = JsxConfig::default()
  assert_emit_contains(
    "auto-multi",
    "const el = <ul><li>a</li><li>b</li></ul>;",
    cfg,
    [
      // Both helpers should be imported when both are used.
      "import { jsx, jsxs }",
      "jsxs(\"ul\",",
      "children:",
      "[",
    ],
  )
}

///|
test "jsx: automatic runtime — fragment uses imported `Fragment`" {
  let cfg = JsxConfig::default()
  assert_emit_contains(
    "auto-fragment",
    "const el = <>{x}{y}</>;",
    cfg,
    [
      "Fragment",
      "from \"react/jsx-runtime\"",
      "jsxs(Fragment,",
    ],
  )
}

///|
test "jsx: automatic runtime — `key` is positional, not a prop" {
  let cfg = JsxConfig::default()
  assert_emit_contains(
    "auto-key",
    #|const el = <Foo key="k" value={1} />;
    ,
    cfg,
    ["jsx(Foo,", "value:", "1", "}, \"k\")"],
  )
}

///|
test "jsx: automatic runtime respects `@jsxImportSource` pragma" {
  // Pragma must overlay onto the default `react` import source.
  let cfg = JsxConfig::default()
  assert_emit_contains(
    "pragma import-source",
    #|/** @jsxImportSource preact */
    #|const el = <Foo />;
    ,
    cfg,
    [
      "from \"preact/jsx-runtime\"",
      "jsx(Foo,",
    ],
  )
}

///|
test "jsx: automatic runtime respects `@jsxRuntime classic`" {
  // Pragma flips to the classic factory. The default `pragma_jsx`
  // is `React.createElement`.
  let cfg = JsxConfig::default()
  assert_emit_contains(
    "pragma classic",
    #|/** @jsxRuntime classic */
    #|const el = <Foo bar={1} />;
    ,
    cfg,
    ["React.createElement(Foo,", "bar:", "1"],
  )
  // No jsx-runtime import in classic mode.
  assert_emit_lacks(
    "pragma classic — no import",
    #|/** @jsxRuntime classic */
    #|const el = <Foo />;
    ,
    cfg,
    ["from \"react/jsx-runtime\""],
  )
}

///|
test "jsx: classic runtime with `@jsx h` / `@jsxFrag Fragment`" {
  // Custom factory + fragment binding — common for preact/h.
  let cfg = JsxConfig::default().with_runtime("classic")
  assert_emit_contains(
    "classic custom",
    #|/** @jsxRuntime classic */
    #|/** @jsx h */
    #|/** @jsxFrag Fragment */
    #|const el = <Foo>hello</Foo>;
    ,
    cfg,
    ["h(Foo,", "hello"],
  )
  assert_emit_contains(
    "classic frag",
    #|/** @jsxRuntime classic */
    #|/** @jsx h */
    #|/** @jsxFrag Fragment */
    #|const el = <>a</>;
    ,
    cfg,
    ["h(Fragment,", "a"],
  )
}

///|
test "jsx: dev runtime uses `jsxDEV` / `jsxsDEV`" {
  let cfg = JsxConfig::default().with_dev(true)
  assert_emit_contains(
    "dev-single",
    "const el = <Foo />;",
    cfg,
    ["import { jsxDEV", "jsxDEV(Foo,"],
  )
  assert_emit_contains(
    "dev-multi",
    "const el = <ul><li/><li/></ul>;",
    cfg,
    ["jsxsDEV", "import { jsxDEV, jsxsDEV }"],
  )
}

///|
test "jsx: spread attribute emits as `...spread`" {
  let cfg = JsxConfig::default()
  assert_emit_contains(
    "spread",
    "const el = <Foo {...rest} title=\"x\" />;",
    cfg,
    ["jsx(Foo,", "...rest", "title:"],
  )
}

///|
test "jsx: intrinsic (lowercase) tag passes through as a string" {
  let cfg = JsxConfig::default()
  assert_emit_contains(
    "intrinsic",
    "const el = <div className=\"x\">hi</div>;",
    cfg,
    ["jsx(\"div\",", "className:", "children:", "hi"],
  )
}

///|
test "jsx: dotted member tag like `<Foo.Bar/>` resolves to a member access" {
  let cfg = JsxConfig::default()
  assert_emit_contains(
    "member tag",
    "const el = <Foo.Bar prop={1} />;",
    cfg,
    ["jsx(Foo.Bar,", "prop:"],
  )
}

///|
test "jsx: lowering walks nested JSX (children get lowered too)" {
  let cfg = JsxConfig::default()
  assert_emit_contains(
    "nested",
    "const el = <Outer><Inner x={1}/></Outer>;",
    cfg,
    [
      "jsx(Outer,",
      "jsx(Inner,",
      "x:",
      "1",
    ],
  )
  // Inner JSX should NOT leak through as source-form `<Inner …`.
  assert_emit_lacks(
    "nested source-form removed",
    "const el = <Outer><Inner x={1}/></Outer>;",
    cfg,
    ["<Inner"],
  )
}