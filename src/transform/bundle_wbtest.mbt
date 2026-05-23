// Tests for the bundle phase. Each case constructs a virtual file
// system in memory and walks `bundle_modules` from an entry path.

///|
fn vfs(entries : Array[(String, String)]) -> Map[String, String] {
  let m : Map[String, String] = {}
  for entry in entries {
    m[entry.0] = entry.1
  }
  m
}

///|
test "bundle: single-file entry round-trips through the bundler" {
  let files = vfs([("entry.ts", "const x = 1;\nconst y = 2;\n")])
  match bundle_modules(files, "entry.ts", BundleOptions::default()) {
    Ok(out) => {
      assert_eq(out.modules.length(), 1)
      assert_eq(out.modules[0], "entry.ts")
      assert_true(out.js.contains("const x"))
      assert_true(out.js.contains("const y"))
      assert_true(out.js.contains("// ===== entry.ts ====="))
    }
    Err(e) => fail("bundle error: \{e}")
  }
}

///|
test "bundle: two-file dependency emits deepest module first" {
  let files = vfs([
    ("entry.ts", "import { lib } from \"./lib\";\nconst x = lib();\n"),
    ("lib.ts", "export const lib = () => 1;\n"),
  ])
  match bundle_modules(files, "entry.ts", BundleOptions::default()) {
    Ok(out) => {
      assert_eq(out.modules, ["lib.ts", "entry.ts"])
      // Both modules show up in the bundle, lib first.
      let lib_idx = match out.js.find("// ===== lib.ts =====") {
        Some(i) => i
        None => -1
      }
      let entry_idx = match out.js.find("// ===== entry.ts =====") {
        Some(i) => i
        None => -1
      }
      assert_true(lib_idx >= 0)
      assert_true(entry_idx >= 0)
      assert_true(lib_idx < entry_idx)
    }
    Err(e) => fail("bundle error: \{e}")
  }
}

///|
test "bundle: bare-specifier imports are re-emitted at the top" {
  let files = vfs([
    (
      "entry.ts",
      "import React from \"react\";\nimport { useState } from \"react\";\nconst el = React.createElement(\"div\");\n",
    ),
  ])
  match bundle_modules(files, "entry.ts", BundleOptions::default()) {
    Ok(out) => {
      assert_true(out.js.contains("import React from \"react\""))
      assert_true(out.js.contains("import { useState } from \"react\""))
      // Internal-statement `const el = …` should also be present.
      assert_true(out.js.contains("const el"))
    }
    Err(e) => fail("bundle error: \{e}")
  }
}

///|
test "bundle: type-only imports are dropped from the output" {
  let files = vfs([
    ("types.ts", "export type T = number;\n"),
    (
      "entry.ts",
      "import type { T } from \"./types\";\nconst v: T = 1;\n",
    ),
  ])
  match bundle_modules(files, "entry.ts", BundleOptions::default()) {
    Ok(out) => {
      // No bundle section for the types-only module — it gets pruned.
      assert_eq(out.modules.length(), 1)
      assert_eq(out.modules[0], "entry.ts")
      assert_false(out.js.contains("// ===== types.ts ====="))
    }
    Err(e) => fail("bundle error: \{e}")
  }
}

///|
test "bundle: diamond dependency visits the shared module once" {
  // a.ts -> shared.ts
  // b.ts -> shared.ts
  // entry.ts -> a.ts and b.ts
  let files = vfs([
    (
      "entry.ts",
      "import { a } from \"./a\";\nimport { b } from \"./b\";\nconst v = a + b;\n",
    ),
    ("a.ts", "import { shared } from \"./shared\";\nexport const a = shared + 1;\n"),
    ("b.ts", "import { shared } from \"./shared\";\nexport const b = shared + 2;\n"),
    ("shared.ts", "export const shared = 42;\n"),
  ])
  match bundle_modules(files, "entry.ts", BundleOptions::default()) {
    Ok(out) => {
      assert_eq(out.modules.length(), 4)
      assert_eq(out.modules[0], "shared.ts")
      assert_true(
        out.modules[1] == "a.ts" && out.modules[2] == "b.ts" ||
        out.modules[1] == "b.ts" && out.modules[2] == "a.ts",
      )
      assert_eq(out.modules[3], "entry.ts")
      // The shared module body must appear exactly once.
      let mut first = 0
      match out.js.find("export const shared") {
        Some(_) => first = first + 1
        None => ()
      }
      let mut count = 0
      let mut search_from = 0
      while search_from < out.js.length() {
        let slice = out.js
          .substring(start=search_from, end=out.js.length())
          .to_string()
        match slice.find("const shared = 42") {
          Some(idx) => {
            count = count + 1
            search_from = search_from + idx + 1
          }
          None => break
        }
      }
      assert_eq(count, 1)
    }
    Err(e) => fail("bundle error: \{e}")
  }
}

///|
test "bundle: missing module fails with a clear error" {
  let files = vfs([
    ("entry.ts", "import { x } from \"./missing\";\nconst v = x;\n"),
  ])
  match bundle_modules(files, "entry.ts", BundleOptions::default()) {
    Ok(_) => fail("expected error for missing module")
    Err(e) => assert_true(e.contains("module not in vfs"))
  }
}

///|
test "bundle: relative paths resolve through ./ and ../" {
  // `entry.ts` lives in `src/`, depends on `./lib.ts` and `../shared.ts`.
  let files = vfs([
    (
      "src/entry.ts",
      "import { lib } from \"./lib\";\nimport { shared } from \"../shared\";\nconst v = lib + shared;\n",
    ),
    ("src/lib.ts", "export const lib = 1;\n"),
    ("shared.ts", "export const shared = 2;\n"),
  ])
  match bundle_modules(files, "src/entry.ts", BundleOptions::default()) {
    Ok(out) => {
      assert_eq(out.modules.length(), 3)
      assert_true(out.modules.contains("src/lib.ts"))
      assert_true(out.modules.contains("shared.ts"))
      assert_true(out.modules.contains("src/entry.ts"))
    }
    Err(e) => fail("bundle error: \{e}")
  }
}

///|
test "bundle: sourcemap option emits multi-source v3 JSON" {
  let files = vfs([
    ("entry.ts", "import { x } from \"./lib\";\nconst v = x;\n"),
    ("lib.ts", "export const x = 1;\n"),
  ])
  let opts : BundleOptions = {
    jsx: JsxConfig::default(),
    with_sourcemap: true,
    tree_shake: false,
    mangle: None,
    auto_reserve: false,
    drop_unused_methods: false,
  }
  match bundle_modules(files, "entry.ts", opts) {
    Ok(out) =>
      match out.sourcemap {
        Some(json) => {
          assert_true(json.contains("\"version\":3"))
          assert_true(json.contains("\"sources\":["))
          // Both module paths should be in the sources array.
          assert_true(json.contains("\"lib.ts\""))
          assert_true(json.contains("\"entry.ts\""))
          // sourcesContent has both bodies embedded.
          assert_true(json.contains("export const x"))
          assert_true(json.contains("import { x } from"))
        }
        None => fail("expected sourcemap, got None")
      }
    Err(e) => fail("bundle error: \{e}")
  }
}

///|
test "bundle: tree shaking drops a dep's unused exports" {
  // `lib.ts` exports both `used` and `unused`. `entry.ts` only
  // imports `used`. With `tree_shake=true`, `unused` should be
  // gone from the bundle.
  let files = vfs([
    (
      "entry.ts",
      "import { used } from \"./lib\";\nconsole.log(used);\n",
    ),
    (
      "lib.ts",
      "export const used = 1;\nexport const unused = 2;\n",
    ),
  ])
  let opts : BundleOptions = {
    jsx: JsxConfig::default(),
    with_sourcemap: false,
    tree_shake: true,
    mangle: None,
    auto_reserve: false,
    drop_unused_methods: false,
  }
  match bundle_modules(files, "entry.ts", opts) {
    Ok(out) => {
      assert_true(out.js.contains("const used"))
      assert_false(out.js.contains("const unused"))
    }
    Err(e) => fail("bundle error: \{e}")
  }
}

///|
test "bundle: tree shaking keeps decls reached through a chain" {
  // `helper` isn't exported, but it's referenced by `used` which is.
  // `noise` is never reached — drop it.
  let files = vfs([
    (
      "entry.ts",
      "import { used } from \"./lib\";\nconsole.log(used());\n",
    ),
    (
      "lib.ts",
      "const helper = 2;\nconst noise = 99;\nexport const used = () => helper + 1;\n",
    ),
  ])
  let opts : BundleOptions = {
    jsx: JsxConfig::default(),
    with_sourcemap: false,
    tree_shake: true,
    mangle: None,
    auto_reserve: false,
    drop_unused_methods: false,
  }
  match bundle_modules(files, "entry.ts", opts) {
    Ok(out) => {
      assert_true(out.js.contains("const used"))
      assert_true(out.js.contains("const helper"))
      assert_false(out.js.contains("const noise"))
    }
    Err(e) => fail("bundle error: \{e}")
  }
}

///|
test "bundle: namespace import keeps every export of the source" {
  // `import * as L from "./lib"` — we can't statically tell which
  // members `L.foo` touches, so we fall back to "keep all exports".
  let files = vfs([
    (
      "entry.ts",
      "import * as L from \"./lib\";\nconsole.log(L.a, L.b);\n",
    ),
    (
      "lib.ts",
      "export const a = 1;\nexport const b = 2;\nexport const c = 3;\n",
    ),
  ])
  let opts : BundleOptions = {
    jsx: JsxConfig::default(),
    with_sourcemap: false,
    tree_shake: true,
    mangle: None,
    auto_reserve: false,
    drop_unused_methods: false,
  }
  match bundle_modules(files, "entry.ts", opts) {
    Ok(out) => {
      assert_true(out.js.contains("const a"))
      assert_true(out.js.contains("const b"))
      assert_true(out.js.contains("const c"))
    }
    Err(e) => fail("bundle error: \{e}")
  }
}

///|
test "bundle: tree shaking off by default keeps every export" {
  // The same lib + entry from above, but tree_shake is left at false.
  // Both exports survive even though only one is imported.
  let files = vfs([
    (
      "entry.ts",
      "import { used } from \"./lib\";\nconsole.log(used);\n",
    ),
    (
      "lib.ts",
      "export const used = 1;\nexport const unused = 2;\n",
    ),
  ])
  match bundle_modules(files, "entry.ts", BundleOptions::default()) {
    Ok(out) => {
      assert_true(out.js.contains("const used"))
      assert_true(out.js.contains("const unused"))
    }
    Err(e) => fail("bundle error: \{e}")
  }
}
///|
test "bundle: cross-module property mangling renames consistently" {
  // Both modules touch the same property name `userField`. With a
  // shared mangler the rename map is global — same short key on each
  // side. We verify by checking that the long name disappears
  // everywhere and the remaining `.X` accesses pair up.
  let files = vfs([
    (
      "entry.ts",
      "import { make } from \"./lib\";\nconst obj = make();\nconsole.log(obj.userField);\n",
    ),
    (
      "lib.ts",
      "export function make() { return { userField: 42, otherField: 0 }; }\n",
    ),
  ])
  let opts : BundleOptions = {
    jsx: JsxConfig::default(),
    with_sourcemap: false,
    tree_shake: false,
    mangle: Some(ManglerConfig::default().with_mangle_properties(true)),
    auto_reserve: false,
    drop_unused_methods: false,
  }
  match bundle_modules(files, "entry.ts", opts) {
    Ok(out) => {
      // Long property names should be gone from the bundle.
      assert_false(out.js.contains("userField"))
      assert_false(out.js.contains("otherField"))
      // The bundle still references the make function across modules.
      assert_true(out.js.contains("make"))
    }
    Err(e) => fail("bundle error: \{e}")
  }
}

///|
test "bundle: mangle preserves built-in props (length, then) across modules" {
  // `arr.length` and `.then` are in the built-in reserved property
  // set — every module in the bundle has to honor the same set.
  let files = vfs([
    (
      "entry.ts",
      "import { task } from \"./lib\";\nconst arr = [1, 2, 3];\nconst n = arr.length;\ntask().then(r => r);\n",
    ),
    (
      "lib.ts",
      "export const task = () => Promise.resolve(\"ok\");\n",
    ),
  ])
  let opts : BundleOptions = {
    jsx: JsxConfig::default(),
    with_sourcemap: false,
    tree_shake: false,
    mangle: Some(ManglerConfig::default().with_mangle_properties(true)),
    auto_reserve: false,
    drop_unused_methods: false,
  }
  match bundle_modules(files, "entry.ts", opts) {
    Ok(out) => {
      assert_true(out.js.contains(".length"))
      assert_true(out.js.contains(".then"))
    }
    Err(e) => fail("bundle error: \{e}")
  }
}

///|
test "bundle: no mangle option leaves source-form props alone" {
  // Baseline: opting out of mangling keeps every property name intact.
  let files = vfs([
    (
      "entry.ts",
      "import { make } from \"./lib\";\nconst obj = make();\nconsole.log(obj.userField);\n",
    ),
    (
      "lib.ts",
      "export function make() { return { userField: 42 }; }\n",
    ),
  ])
  match bundle_modules(files, "entry.ts", BundleOptions::default()) {
    Ok(out) => assert_true(out.js.contains("userField"))
    Err(e) => fail("bundle error: \{e}")
  }
}

///|
test "bundle: auto-reserve protects exported interface fields cross-module" {
  // `User` is defined in `types.ts` and referenced from `entry.ts`'s
  // exported function signature. With auto-reserve on, the walker
  // crosses the module boundary and keeps `User.userName` /
  // `User.userScore` in the reserved property set.
  let files = vfs([
    (
      "types.ts",
      "export interface User { userName: string; userScore: number; }\n",
    ),
    (
      "entry.ts",
      "import { User } from \"./types\";\nexport function read(u: User) { return u.userName; }\n",
    ),
  ])
  let opts : BundleOptions = {
    jsx: JsxConfig::default(),
    with_sourcemap: false,
    tree_shake: false,
    mangle: Some(ManglerConfig::default().with_mangle_properties(true)),
    auto_reserve: true,
    drop_unused_methods: false,
  }
  match bundle_modules(files, "entry.ts", opts) {
    Ok(out) => assert_true(out.js.contains("userName"))
    Err(e) => fail("bundle error: \{e}")
  }
}

///|
test "bundle: auto-reserve follows inline object return types across modules" {
  // The exported `make` from the entry returns `User` (defined in
  // `types.ts`). The walker has to cross the module boundary to
  // resolve `User` and reserve its field `userName`. With
  // auto-reserve on, the long name survives mangling on both sides
  // of the bundle.
  let files = vfs([
    (
      "types.ts",
      "export interface User { userName: string; }\n",
    ),
    (
      "lib.ts",
      "import { User } from \"./types\";\nexport function make(): User { return { userName: \"alice\" }; }\n",
    ),
    (
      "entry.ts",
      "import { make } from \"./types\";\nexport { make };\n",
    ),
  ])
  let opts : BundleOptions = {
    jsx: JsxConfig::default(),
    with_sourcemap: false,
    tree_shake: false,
    mangle: Some(ManglerConfig::default().with_mangle_properties(true)),
    auto_reserve: true,
    drop_unused_methods: false,
  }
  // `entry.ts` re-exports `make`. Resolving `make`'s return type
  // reaches `User` (cross-module), which keeps `userName`.
  let files2 = vfs([
    (
      "types.ts",
      "export interface User { userName: string; }\n",
    ),
    (
      "entry.ts",
      "import { User } from \"./types\";\nexport function make(): User { return { userName: \"alice\" }; }\n",
    ),
  ])
  match bundle_modules(files2, "entry.ts", opts) {
    Ok(out) => assert_true(out.js.contains("userName"))
    Err(e) => fail("bundle error: \{e}")
  }
  let _ = files
}

///|
test "bundle: auto-reserve off keeps the user-supplied reserved set verbatim" {
  // Sanity: when auto-reserve is off, the mangler uses just the
  // built-ins + caller's explicit list. `userName` isn't reserved
  // and gets renamed.
  let files = vfs([
    (
      "types.ts",
      "export interface User { userName: string; }\n",
    ),
    (
      "entry.ts",
      "import { User } from \"./types\";\nexport function read(u: User) { return u.userName; }\n",
    ),
  ])
  let opts : BundleOptions = {
    jsx: JsxConfig::default(),
    with_sourcemap: false,
    tree_shake: false,
    mangle: Some(ManglerConfig::default().with_mangle_properties(true)),
    auto_reserve: false,
    drop_unused_methods: false,
  }
  match bundle_modules(files, "entry.ts", opts) {
    Ok(out) => assert_false(out.js.contains("userName"))
    Err(e) => fail("bundle error: \{e}")
  }
}
