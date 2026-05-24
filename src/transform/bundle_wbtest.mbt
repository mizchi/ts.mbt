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
  let opts : BundleOptions = BundleOptions::default().with_sourcemap(true)
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
test "bundle: mangle folds modules into one scope and renames everything" {
  // Two modules — the bundle should expose `b.compute` as the entry
  // through the same renamed slot used inside `a`. With
  // `--mangle`, the per-module separator comments are dropped and
  // every binding gets a short name.
  let files = vfs([
    (
      "entry.ts",
      "import { compute } from \"./lib\";\nconst out = compute(7);\nconsole.log(out);\n",
    ),
    (
      "lib.ts",
      "export function compute(seed: number): number {\n  const offset = 3;\n  return seed + offset;\n}\n",
    ),
  ])
  let opts = BundleOptions::default().with_mangle(true)
  match bundle_modules(files, "entry.ts", opts) {
    Ok(out) => {
      // Parameter / local names should be gone.
      assert_false(out.js.contains("offset"))
      assert_false(out.js.contains("seed"))
      // Per-module separator banners are skipped in mangle mode.
      assert_false(out.js.contains("// ===== "))
      // `console` stays put — it's in the built-in reserved set.
      assert_true(out.js.contains("console.log"))
      assert_eq(out.modules.length(), 2)
    }
    Err(e) => fail("bundle error: \{e}")
  }
}

///|
test "bundle: mangle keeps the shared call site consistent across modules" {
  // `helper` is defined in `lib.ts`, called from `entry.ts`. The
  // mangle pass folds both into one block so the bundle's call
  // site must refer to the same renamed identifier as the
  // declaration's outer binding.
  let files = vfs([
    (
      "entry.ts",
      "import { helper } from \"./lib\";\nconst v = helper(2);\nconsole.log(v);\n",
    ),
    (
      "lib.ts", "export function helper(n: number): number {\n  return n * 2;\n}\n",
    ),
  ])
  let opts = BundleOptions::default().with_mangle(true)
  match bundle_modules(files, "entry.ts", opts) {
    Ok(out) => {
      // Emit-time function-decl lowering converts
      // `Let(Ident(X), _, FuncExpr({name: X|orig, …}))` into a
      // plain `function X(…) {…}`. The FuncExpr internal name is
      // dropped; rename consistency between declaration and call
      // site is preserved by the mangler walking `Var`/`Call`
      // references in the body.
      let mut found = false
      for candidate in ["a", "b", "c", "d", "e"] {
        if out.js.contains("function " + candidate + "(") &&
          out.js.contains("= " + candidate + "(") {
          found = true
        }
      }
      if !found {
        fail("expected matched declaration / call rename in: \{out.js}")
      }
    }
    Err(e) => fail("bundle error: \{e}")
  }
}