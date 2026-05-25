// Tests for the type-driven property-mangling safety analysis.

///|
fn safety_vfs(entries : Array[(String, String)]) -> Map[String, String] {
  let m : Map[String, String] = {}
  for entry in entries {
    m[entry.0] = entry.1
  }
  m
}

///|
test "safety: console.X is preserved under --mangle-properties" {
  let files = safety_vfs([
    (
      "entry.ts", "const a = { x: 1 };\nconsole.log(a.x);\n",
    ),
  ])
  let opts = BundleOptions::default()
    .with_mangle(true)
    .with_mangle_properties(true)
    .with_minify(true)
  match bundle_modules(files, "entry.ts", opts) {
    Ok(out) => {
      // `console.log` survives — global. Internal `.x` is fair
      // game.
      assert_true(out.js.contains("console.log"))
    }
    Err(e) => fail("bundle error: \{e}")
  }
}

///|
test "safety: JSON.stringify on a Var triggers wildcard, suppresses property mangling" {
  let files = safety_vfs([
    (
      "entry.ts",
      "const cfg = { foo: 1, bar: 2 };\nconsole.log(JSON.stringify(cfg));\n",
    ),
  ])
  let opts = BundleOptions::default()
    .with_mangle(true)
    .with_mangle_properties(true)
    .with_minify(true)
  match bundle_modules(files, "entry.ts", opts) {
    Ok(out) => {
      // `foo` / `bar` would survive in JSON output, so the type-
      // safety analysis bails out and property mangling is
      // suppressed.
      assert_true(out.js.contains("foo"))
      assert_true(out.js.contains("bar"))
    }
    Err(e) => fail("bundle error: \{e}")
  }
}

///|
test "safety: external import binding's props are reserved" {
  // `react.useState` — even with `--mangle-properties`, `useState`
  // must not be renamed because `react` is external.
  let files = safety_vfs([
    (
      "entry.ts",
      "import * as React from \"react\";\nReact.useState(0);\nconst a = { x: 1 };\nconsole.log(a.x);\n",
    ),
  ])
  let opts = BundleOptions::default()
    .with_mangle(true)
    .with_mangle_properties(true)
    .with_minify(true)
  match bundle_modules(files, "entry.ts", opts) {
    Ok(out) => {
      assert_true(out.js.contains("useState"))
    }
    Err(e) => fail("bundle error: \{e}")
  }
}

///|
test "safety: internal-only property is still mangled" {
  // No JSON, no external prop accesses — internal `x` and `y` are
  // safe to rename to short slots.
  let files = safety_vfs([
    (
      "entry.ts",
      "const point = { x: 1, y: 2 };\nconsole.log(point.x + point.y);\n",
    ),
  ])
  let opts = BundleOptions::default()
    .with_mangle(true)
    .with_mangle_properties(true)
    .with_minify(true)
  match bundle_modules(files, "entry.ts", opts) {
    Ok(out) => {
      // Both `x` and `y` should disappear from the bundle.
      assert_false(out.js.contains(".x"))
      assert_false(out.js.contains(".y"))
      // ... but `console.log` survives.
      assert_true(out.js.contains("console.log"))
    }
    Err(e) => fail("bundle error: \{e}")
  }
}

///|
test "safety: for-in iteration suppresses property mangling" {
  let files = safety_vfs([
    (
      "entry.ts",
      "const cfg = { foo: 1, bar: 2 };\nfor (const k in cfg) { console.log(k); }\n",
    ),
  ])
  let opts = BundleOptions::default()
    .with_mangle(true)
    .with_mangle_properties(true)
    .with_minify(true)
  match bundle_modules(files, "entry.ts", opts) {
    Ok(out) => {
      // `for-in` enumerates property names — they must survive.
      assert_true(out.js.contains("foo"))
      assert_true(out.js.contains("bar"))
    }
    Err(e) => fail("bundle error: \{e}")
  }
}
