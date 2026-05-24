// Tests for the public `mizchi/ts` bundle API.
//
// Each case calls the user-facing wrapper rather than reaching
// directly into `@transform.bundle_modules`. The wrappers are
// thin, but the test makes sure the documented `BundleProfile`
// presets line up with their stated semantics.

///|
test "transform_api: bundle_source on a self-contained snippet" {
  let src = "const x = 1;\nconsole.log(x + 2);\n"
  match bundle_source(src) {
    Ok(js) => {
      assert_true(js.contains("const x"))
      assert_true(js.contains("console.log"))
    }
    Err(e) => fail(e)
  }
}

///|
test "transform_api: bundle_source with `Full` profile drops dead code" {
  let src = "const used = 1;\nconst dead = 2;\nconsole.log(used);\n"
  match bundle_source(src, profile=Full) {
    Ok(js) => {
      // Tree-shake should have removed the unused `dead`.
      assert_false(js.contains("const dead"))
      assert_false(js.contains("dead = 2"))
    }
    Err(e) => fail(e)
  }
}

///|
test "transform_api: bundle_files threads through a VFS" {
  let files : Map[String, String] = {}
  files["lib.ts"] = "export function greet(name: string) { return \"hi, \" + name; }\n"
  files["entry.ts"] =
    "import { greet } from \"./lib\";\nconsole.log(greet(\"alice\"));\n"
  match bundle_files(files, "entry.ts") {
    Ok(out) => {
      assert_eq(out.modules.length(), 2)
      assert_true(out.js.contains("function greet"))
      assert_true(out.js.contains("greet(\"alice\")"))
    }
    Err(e) => fail(e)
  }
}

///|
test "transform_api: `Production` profile tree-shakes but keeps names" {
  let files : Map[String, String] = {}
  files["lib.ts"] =
    "export function used() { return 1; }\nexport function unused() { return 2; }\n"
  files["entry.ts"] =
    "import { used } from \"./lib\";\nconsole.log(used());\n"
  match bundle_files(files, "entry.ts", profile=Production) {
    Ok(out) => {
      // Tree shake gone.
      assert_false(out.js.contains("function unused"))
      // Identifier mangling NOT applied — `used` stays readable.
      assert_true(out.js.contains("function used"))
    }
    Err(e) => fail(e)
  }
}

///|
test "transform_api: `Full` profile mangles property keys too" {
  let files : Map[String, String] = {}
  files["entry.ts"] =
    "function read(o: any) { return o.userField; }\nconsole.log(read({ userField: 42 }));\n"
  match bundle_files(files, "entry.ts", profile=Full) {
    Ok(out) => {
      // `userField` should be renamed when no other reference
      // protects it from the mangler.
      assert_false(out.js.contains("userField"))
    }
    Err(e) => fail(e)
  }
}

///|
test "transform_api: `with_sourcemap` emits the v3 mapping JSON" {
  let files : Map[String, String] = {}
  files["lib.ts"] = "export const x = 1;\n"
  files["entry.ts"] =
    "import { x } from \"./lib\";\nconsole.log(x);\n"
  match bundle_files(files, "entry.ts", with_sourcemap=true) {
    Ok(out) =>
      match out.sourcemap {
        Some(json) => {
          assert_true(json.contains("\"version\":3"))
          assert_true(json.contains("\"sources\":["))
        }
        None => fail("expected sourcemap, got None")
      }
    Err(e) => fail(e)
  }
}

///|
test "transform_api: bundle_files_with takes raw BundleOptions" {
  let files : Map[String, String] = {}
  files["entry.ts"] = "const a = 1;\nconst b = 2;\nconsole.log(a + b);\n"
  // Mix of opts that aren't covered by any preset: tree-shake on,
  // but property mangling off — useful when the caller knows the
  // bundle is consumed via reflection.
  let opts : @transform.BundleOptions = {
    ..@transform.BundleOptions::default(),
    tree_shake: true,
    mangle: Some(@transform.ManglerConfig::default()),
  }
  match bundle_files_with(files, "entry.ts", opts) {
    Ok(out) => assert_true(out.js.length() > 0)
    Err(e) => fail(e)
  }
}

///|
test "transform_api: BundleProfile renders cleanly via Show" {
  assert_eq(Development.to_string(), "Development")
  assert_eq(Production.to_string(), "Production")
  assert_eq(Full.to_string(), "Full")
}
