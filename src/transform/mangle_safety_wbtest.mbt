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
    ("entry.ts", "const a = { x: 1 };\nconsole.log(a.x);\n"),
  ])
  let opts = BundleOptions::default()
    .with_mangle(true)
    .with_mangle_properties(true)
    .with_minify(true)
  match bundle_modules(files, "entry.ts", opts) {
    Ok(out) =>
      // `console.log` survives — global. Internal `.x` is fair
      // game.
      assert_true(out.js.contains("console.log"))
    Err(e) => fail("bundle error: \{e}")
  }
}

///|
test "safety: JSON.stringify on a Var triggers wildcard, suppresses property mangling" {
  let files = safety_vfs([
    (
      "entry.ts", "const cfg = { foo: 1, bar: 2 };\nconsole.log(JSON.stringify(cfg));\n",
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
      "entry.ts", "import * as React from \"react\";\nReact.useState(0);\nconst a = { x: 1 };\nconsole.log(a.x);\n",
    ),
  ])
  let opts = BundleOptions::default()
    .with_mangle(true)
    .with_mangle_properties(true)
    .with_minify(true)
  match bundle_modules(files, "entry.ts", opts) {
    Ok(out) => assert_true(out.js.contains("useState"))
    Err(e) => fail("bundle error: \{e}")
  }
}

///|
test "safety: internal-only property is still mangled" {
  // No JSON, no external prop accesses — internal `x` and `y` are
  // safe to rename to short slots.
  let files = safety_vfs([
    (
      "entry.ts", "const point = { x: 1, y: 2 };\nconsole.log(point.x + point.y);\n",
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
      "entry.ts", "const cfg = { foo: 1, bar: 2 };\nfor (const k in cfg) { console.log(k); }\n",
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

///|
test "phase3: local object literal handed to Object.keys reserves only its own keys" {
  let block = @parser.parse_block_from_source(
    (
      #|const obj = {foo: 1, bar: 2};
      #|Object.keys(obj);
      #|
    ),
  )
  let result = collect_externally_visible_props(block, {})
  // `foo` / `bar` survive; nothing else is reserved (no wildcard).
  assert_true(result.contains("foo"))
  assert_true(result.contains("bar"))
  assert_false(result.contains("*"))
}

///|
test "phase3: parameter handed to Object.keys does NOT reserve outside literal" {
  // `f(obj)` — `obj` is a parameter, no def. Without flow info
  // we can't see the literal `{a: 1}` reaching it, so the
  // binding has no observable props recorded. This is the false-
  // negative case Phase 4 will fix.
  let block = @parser.parse_block_from_source(
    (
      #|function f(obj) { return Object.keys(obj); }
      #|f({a: 1});
      #|
    ),
  )
  let result = collect_externally_visible_props(block, {})
  // No wildcard fallback for the param case; `a` is currently
  // NOT preserved (call-site argument flow lands in Phase 4).
  assert_false(result.contains("*"))
}
