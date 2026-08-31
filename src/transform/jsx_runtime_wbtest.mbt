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
  assert_emit_contains("auto-single", "const el = <Foo bar={1} />;", cfg, [
    "import { jsx } from \"react/jsx-runtime\";", "jsx(Foo,", "bar:", "1",
  ])
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
      "import { jsx, jsxs }", "jsxs(\"ul\",", "children:", "[",
    ],
  )
}

///|
test "jsx: automatic runtime — fragment uses imported `Fragment`" {
  let cfg = JsxConfig::default()
  assert_emit_contains("auto-fragment", "const el = <>{x}{y}</>;", cfg, [
    "Fragment", "from \"react/jsx-runtime\"", "jsxs(Fragment,",
  ])
}

///|
test "jsx: automatic runtime — `key` is positional, not a prop" {
  let cfg = JsxConfig::default()
  assert_emit_contains(
    "auto-key",
    (
      #|const el = <Foo key="k" value={1} />;
    ),
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
    (
      #|/** @jsxImportSource preact */
      #|const el = <Foo />;
    ),
    cfg,
    ["from \"preact/jsx-runtime\"", "jsx(Foo,"],
  )
}

///|
test "jsx: automatic runtime respects `@jsxRuntime classic`" {
  // Pragma flips to the classic factory. The default `pragma_jsx`
  // is `React.createElement`.
  let cfg = JsxConfig::default()
  assert_emit_contains(
    "pragma classic",
    (
      #|/** @jsxRuntime classic */
      #|const el = <Foo bar={1} />;
    ),
    cfg,
    ["React.createElement(Foo,", "bar:", "1"],
  )
  // No jsx-runtime import in classic mode.
  assert_emit_lacks(
    "pragma classic — no import",
    (
      #|/** @jsxRuntime classic */
      #|const el = <Foo />;
    ),
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
    (
      #|/** @jsxRuntime classic */
      #|/** @jsx h */
      #|/** @jsxFrag Fragment */
      #|const el = <Foo>hello</Foo>;
    ),
    cfg,
    ["h(Foo,", "hello"],
  )
  assert_emit_contains(
    "classic frag",
    (
      #|/** @jsxRuntime classic */
      #|/** @jsx h */
      #|/** @jsxFrag Fragment */
      #|const el = <>a</>;
    ),
    cfg,
    ["h(Fragment,", "a"],
  )
}

///|
test "jsx: dev runtime uses `jsxDEV` / `jsxsDEV`" {
  let cfg = JsxConfig::default().with_dev(true)
  assert_emit_contains("dev-single", "const el = <Foo />;", cfg, [
    "import { jsxDEV", "jsxDEV(Foo,",
  ])
  assert_emit_contains("dev-multi", "const el = <ul><li/><li/></ul>;", cfg, [
    "jsxsDEV", "import { jsxDEV, jsxsDEV }",
  ])
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
  assert_emit_contains("member tag", "const el = <Foo.Bar prop={1} />;", cfg, [
    "jsx(Foo.Bar,", "prop:",
  ])
}

///|
test "jsx: lowering walks nested JSX (children get lowered too)" {
  let cfg = JsxConfig::default()
  assert_emit_contains(
    "nested",
    "const el = <Outer><Inner x={1}/></Outer>;",
    cfg,
    ["jsx(Outer,", "jsx(Inner,", "x:", "1"],
  )
  // Inner JSX should NOT leak through as source-form `<Inner …`.
  assert_emit_lacks(
    "nested source-form removed",
    "const el = <Outer><Inner x={1}/></Outer>;",
    cfg,
    ["<Inner"],
  )
}

///|
test "jsx: JSX inside an expression child is lowered" {
  // Children went through a helper that handled a child which was itself
  // a `JsxElement` and returned everything else unchanged. A child is
  // usually an EXPRESSION — `{cond && <>…</>}`, `{c ? <p/> : d}` — so
  // the JSX inside one survived into the output, and the output was then
  // not JavaScript at all: Node cannot parse it. `verify.mbt` cannot
  // catch this class either, because it re-parses with the TypeScript
  // parser, which accepts JSX.
  let src =
    #|const A = <div>{cond && <><span>x</span></>}</div>;
    #|const B = <div>{flag ? <p a={v} /> : v}</div>;
    #|const C = <div>{items.map((n) => <li>{n}</li>)}</div>;
  let block = @parser.parse_block_from_source(src)
  let lowered = lower_jsx_in_block(JsxConfig::default(), block)
  let e = Emitter::new()
  emit_block(e, lowered)
  let out = e.to_string()
  assert_false(
    out.contains("<span>") || out.contains("<p ") || out.contains("<li>"),
    msg="raw JSX survived the lowering: \{out}",
  )
  assert_true(out.contains("jsx(Fragment"), msg="got: \{out}")
  assert_true(out.contains("jsx(\"p\""), msg="got: \{out}")
  assert_true(out.contains("jsx(\"li\""), msg="got: \{out}")
}

///|
test "jsx: a nested element's attribute values are lowered" {
  // The mirror image of the same hole: the caller lowered attributes
  // before descending, and the recursive path did not — so a NESTED
  // element's attribute values were skipped.
  let src = "const D = <div><Foo x={<span>attr</span>} /></div>;"
  let block = @parser.parse_block_from_source(src)
  let lowered = lower_jsx_in_block(JsxConfig::default(), block)
  let e = Emitter::new()
  emit_block(e, lowered)
  let out = e.to_string()
  assert_false(
    out.contains("<span>"),
    msg="a nested attribute kept its JSX: \{out}",
  )
  assert_true(out.contains("x: jsx(\"span\""), msg="got: \{out}")
}

///|
test "jsx: a function-expression body is JSX-lowered" {
  // The arm here used to read
  // `FuncExpr(_) => expr // function-expression bodies are not JSX-walked yet`,
  // and what that meant in practice is that the JSX reached the output —
  // so the bundle was not JavaScript and Node rejected it at parse time.
  // Nothing in the repo was asking that question until the verifier
  // learned to.
  let src =
    #|const A = function () { return <div>x</div>; };
    #|const B = { m: function () { return <>frag</>; } };
    #|const C = (function () { return <span>iife</span>; })();
  let block = @parser.parse_block_from_source(src)
  let lowered = lower_jsx_in_block(JsxConfig::default(), block)
  let e = Emitter::new()
  emit_block(e, lowered)
  let out = e.to_string()
  assert_false(
    out.contains("<div>") || out.contains("<span>") || out.contains("<>"),
    msg="raw JSX survived a function expression: \{out}",
  )
}

///|
test "jsx: the runtime import covers helpers used inside a function expression" {
  // The ref collector had the SAME blind spot as the lowering, plus a
  // dozen more (`New`, `IndexAccess`, `As`, …) — it was a bespoke walk
  // with arms for about a third of the expression forms. Each gap was a
  // latent free `jsx`. It now shares `collect_var_refs_in_block`, the
  // walk treeshaking relies on for the same question.
  let src = "const A = function () { return <div>x</div>; };"
  let block = @parser.parse_block_from_source(src)
  let (_, needed) = lower_block_with_runtime_imports(
    JsxConfig::default(),
    block,
  )
  assert_true(needed.contains("jsx"), msg="needed = \{needed}")
}

///|
test "jsx: the runtime import list stays empty without JSX" {
  let block = @parser.parse_block_from_source("const a = 1 + 2;")
  let (_, needed) = lower_block_with_runtime_imports(
    JsxConfig::default(),
    block,
  )
  @test.assert_eq(needed.length(), 0)
}

///|
test "jsx: a plain-JS file with a local Fragment gets no runtime import" {
  // The regression that made the second attempt at this fail. Deriving
  // the needed helpers by walking the lowered block for their NAMES
  // cannot distinguish a synthesized reference from a name that was
  // already in the source, and `Fragment` / `jsx` are ordinary local
  // names in React's own code. `react-dom.development.js` — no JSX at
  // all — got `import { Fragment } from "react/jsx-runtime"` prepended
  // and stopped parsing.
  let src =
    #|const Fragment = Symbol("frag");
    #|const jsx = (a) => a;
    #|const use = () => jsx(Fragment);
  let block = @parser.parse_block_from_source(src)
  let cfg = JsxConfig::default()
  let (_, needed) = lower_block_with_runtime_imports(cfg, block)
  @test.assert_eq(needed.length(), 0)
}

///|
test "jsx: the helper set is per call, not cumulative" {
  // A config reused across modules must report each module's own
  // helpers. `lower_block_with_runtime_imports` clears the channel
  // first, so a second block does not inherit the first's.
  let cfg = JsxConfig::default()
  let with_jsx = @parser.parse_block_from_source("const a = <div>x</div>;")
  let (_, first) = lower_block_with_runtime_imports(cfg, with_jsx)
  assert_true(first.contains("jsx"))
  let without = @parser.parse_block_from_source("const b = 1;")
  let (_, second) = lower_block_with_runtime_imports(cfg, without)
  @test.assert_eq(second.length(), 0)
}
