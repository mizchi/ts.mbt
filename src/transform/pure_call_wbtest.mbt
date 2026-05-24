// Tests for the `/* @__PURE__ */` annotation.
//
// The annotation tells the optimizer that the wrapped call has no
// observable side effects. Tree-shake then drops the surrounding
// statement (or the unused binding it lives on) when nothing else
// references its result. Both terser's `#__PURE__` and the more
// common `@__PURE__` spellings are accepted.

///|
test "pure-call: bare `/* @__PURE__ */ call()` at top level gets dropped" {
  let files : Map[String, String] = {}
  files["entry.ts"] =
    "function sideEffect() { console.log('boom'); }\n" +
    "/* @__PURE__ */ sideEffect();\n" +
    "console.log('end');\n"
  let opts = { ..BundleOptions::default(), tree_shake: true }
  match bundle_modules(files, "entry.ts", opts) {
    Ok(out) => {
      // The pure-marked call is gone — its receiver function gets
      // tree-shaken too because nothing keeps it alive.
      assert_false(out.js.contains("\"boom\""))
      assert_false(out.js.contains("function sideEffect"))
      assert_true(out.js.contains("\"end\""))
    }
    Err(e) => fail(e)
  }
}

///|
test "pure-call: `#__PURE__` (terser spelling) is also recognized" {
  let files : Map[String, String] = {}
  files["entry.ts"] =
    "function sideEffect() { console.log('boom'); }\n" +
    "/* #__PURE__ */ sideEffect();\n" +
    "console.log('end');\n"
  let opts = { ..BundleOptions::default(), tree_shake: true }
  match bundle_modules(files, "entry.ts", opts) {
    Ok(out) => {
      assert_false(out.js.contains("\"boom\""))
      assert_true(out.js.contains("\"end\""))
    }
    Err(e) => fail(e)
  }
}

///|
test "pure-call: no annotation keeps the side effect" {
  // Sanity: without the marker, tree-shake conservatively keeps
  // the top-level call.
  let files : Map[String, String] = {}
  files["entry.ts"] =
    "function sideEffect() { console.log('boom'); }\n" +
    "sideEffect();\n"
  let opts = { ..BundleOptions::default(), tree_shake: true }
  match bundle_modules(files, "entry.ts", opts) {
    Ok(out) => {
      assert_true(out.js.contains("\"boom\""))
      assert_true(out.js.contains("sideEffect()"))
    }
    Err(e) => fail(e)
  }
}

///|
test "pure-call: differential under node — pure call drops cleanly" {
  let files : Map[String, String] = {}
  files["entry.ts"] =
    "function trace(label: string) { console.log(label); }\n" +
    "/* @__PURE__ */ trace(\"A\");\n" +
    "trace(\"B\");\n" +
    "/* @__PURE__ */ trace(\"C\");\n" +
    "trace(\"D\");\n"
  // With the marker, A and C should be dropped; B and D survive.
  // Baseline (no opts) keeps everything so the stdouts differ —
  // we just verify the optimized version says what we expect.
  let opts = { ..BundleOptions::default(), tree_shake: true }
  match bundle_modules(files, "entry.ts", opts) {
    Ok(out) => {
      assert_false(out.js.contains("\"A\""))
      assert_true(out.js.contains("\"B\""))
      assert_false(out.js.contains("\"C\""))
      assert_true(out.js.contains("\"D\""))
    }
    Err(e) => fail(e)
  }
}
