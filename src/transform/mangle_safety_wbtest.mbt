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
// End-to-end: a typed local flowing to an external import previously
// suppressed property mangling for the whole bundle (wildcard `*`).
// With type-driven External narrowing the typed local's keys stay
// reserved (consumer-visible) but unrelated internal properties
// shrink to short slots.
test "safety: external call arg with typed annotation unlocks unrelated mangling" {
  let files = safety_vfs([
    (
      "entry.ts",
      (
        #|import { sink } from "external-thing";
        #|const obj: { aaa: number; bbb: number } = { aaa: 1, bbb: 2 };
        #|sink(obj);
        #|const other = { internalProp: 3 };
        #|console.log(other.internalProp);
        #|
      ),
    ),
  ])
  let opts = BundleOptions::default()
    .with_mangle(true)
    .with_mangle_properties(true)
    .with_minify(true)
  match bundle_modules(files, "entry.ts", opts) {
    Ok(out) => {
      // Typed external arg's keys remain visible.
      assert_true(out.js.contains("aaa"))
      assert_true(out.js.contains("bbb"))
      // Internal-only `internalProp` is now manglable — the previous
      // unconditional `*` would have preserved it.
      assert_false(out.js.contains("internalProp"))
    }
    Err(e) => fail("bundle error: \{e}")
  }
}

///|
// Phase 4 narrowing of External observability via TypeScript annotation:
// when a typed local flows to an external callee, the wildcard fallback
// was previously unconditional — any annotation with a closed key set
// (interface / object literal type / union of those) now reserves
// exactly those keys, so unrelated internal properties remain
// mangle-eligible.
test "phase4: External call arg narrows via static type annotation" {
  let block = @parser.parse_block_from_source(
    (
      #|const obj: { aaa: number; bbb: number } = { aaa: 1, bbb: 2 };
      #|sink(obj);
      #|const other = { ccc: 3 };
      #|console.log(other);
      #|
    ),
  )
  let externals : Map[String, Bool] = {}
  externals["sink"] = true
  let result = collect_externally_visible_props(block, externals)
  // Type-driven keys are reserved.
  assert_true(result.contains("aaa"))
  assert_true(result.contains("bbb"))
  // No wildcard — unrelated `ccc` stays manglable.
  assert_false(result.contains("*"))
}

///|
// Without a TypeScript annotation we cannot statically bound the
// external-callee's observation, so the wildcard fallback still
// fires. This pins down the conservative path.
test "phase4: External call arg keeps wildcard when type is missing" {
  let block = @parser.parse_block_from_source(
    (
      #|const obj = { aaa: 1, bbb: 2 };
      #|sink(obj);
      #|
    ),
  )
  let externals : Map[String, Bool] = {}
  externals["sink"] = true
  let result = collect_externally_visible_props(block, externals)
  assert_true(result.contains("*"))
}

///|
// An index-signature-typed binding has an unbounded key set at the
// type level, so the wildcard fallback must remain in place even
// when the annotation is present.
test "phase4: External call arg keeps wildcard for index-signature type" {
  let block = @parser.parse_block_from_source(
    (
      #|const obj: { [k: string]: number } = { aaa: 1 };
      #|sink(obj);
      #|
    ),
  )
  let externals : Map[String, Bool] = {}
  externals["sink"] = true
  let result = collect_externally_visible_props(block, externals)
  assert_true(result.contains("*"))
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
