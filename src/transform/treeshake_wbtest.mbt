// Tests for the bundle tree-shaking pass.

///|
fn ts_vfs(entries : Array[(String, String)]) -> Map[String, String] {
  let m : Map[String, String] = {}
  for entry in entries {
    m[entry.0] = entry.1
  }
  m
}

///|
test "treeshake: drops a never-referenced pure declaration" {
  let files = ts_vfs([
    ("entry.ts", "import { used } from \"./lib\";\nconsole.log(used(1));\n"),
    (
      "lib.ts", "export function used(n: number): number { return n + 1; }\nexport function unused(n: number): number { return n + 2; }\n",
    ),
  ])
  let opts = BundleOptions::default().with_treeshake(true)
  match bundle_modules(files, "entry.ts", opts) {
    Ok(out) => {
      assert_true(out.js.contains("used"))
      assert_false(out.js.contains("unused"))
    }
    Err(e) => fail("bundle error: \{e}")
  }
}

///|
test "treeshake: keeps an impure const even when nothing references it" {
  // `MethodCall` rhs isn't statically pure, so the declaration is
  // classified as a side-effect root and survives even without an
  // incoming reference. This is the conservative-by-design behavior.
  let files = ts_vfs([
    ("entry.ts", "import { used } from \"./lib\";\nconsole.log(used(1));\n"),
    (
      "lib.ts", "export function used(n: number): number { return n + 1; }\nexport const REGISTERED = \"x\".repeat(3);\n",
    ),
  ])
  let opts = BundleOptions::default().with_treeshake(true)
  match bundle_modules(files, "entry.ts", opts) {
    Ok(out) => assert_true(out.js.contains("REGISTERED"))
    Err(e) => fail("bundle error: \{e}")
  }
}

///|
test "treeshake: pulls in transitive declarations from a live function body" {
  let files = ts_vfs([
    ("entry.ts", "import { outer } from \"./lib\";\nconsole.log(outer(2));\n"),
    (
      "lib.ts", "function helper(n: number): number { return n + 1; }\nexport function outer(n: number): number { return helper(n) * 2; }\nfunction never_used(n: number): number { return n + 999; }\n",
    ),
  ])
  let opts = BundleOptions::default().with_treeshake(true)
  match bundle_modules(files, "entry.ts", opts) {
    Ok(out) => {
      assert_true(out.js.contains("outer"))
      assert_true(out.js.contains("helper"))
      assert_false(out.js.contains("never_used"))
    }
    Err(e) => fail("bundle error: \{e}")
  }
}

///|
test "treeshake + mangle compose into a smaller bundle than mangle alone" {
  let files = ts_vfs([
    ("entry.ts", "import { used } from \"./lib\";\nconsole.log(used(1));\n"),
    (
      "lib.ts", "export function used(n: number): number { return n + 1; }\nexport function dead_a(n: number): number { return n + 2; }\nexport function dead_b(n: number): number { return n + 3; }\nexport function dead_c(n: number): number { return n + 4; }\n",
    ),
  ])
  let mangle_only = BundleOptions::default().with_mangle(true)
  let mangle_ts = BundleOptions::default()
    .with_mangle(true)
    .with_treeshake(true)
  let a = match bundle_modules(files, "entry.ts", mangle_only) {
    Ok(o) => o
    Err(e) => {
      fail("bundle a error: \{e}")
      return
    }
  }
  let b = match bundle_modules(files, "entry.ts", mangle_ts) {
    Ok(o) => o
    Err(e) => {
      fail("bundle b error: \{e}")
      return
    }
  }
  // Tree-shake should remove the three dead declarations entirely.
  assert_true(b.js.length() < a.js.length())
}
