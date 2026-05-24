// Tests for the minified emit + inline source-map output modes.
//
// Minified mode strips newlines / indent + the per-module
// section comments. Inline source-map mode appends a
// `//# sourceMappingURL=data:…;base64,…` comment so the JS bundle
// is self-contained for browser dev tools.

///|
fn minify_opts() -> BundleOptions {
  { ..BundleOptions::default(), minify: true }
}

///|
fn full_opt_minify_opts() -> BundleOptions {
  {
    ..full_opt_bundle_options(),
    minify: true,
  }
}

///|
test "minify: removes newlines, indent, and section comments" {
  let files : Map[String, String] = {}
  files["entry.ts"] = "const x = 1;\nconsole.log(x);\n"
  match bundle_modules(files, "entry.ts", minify_opts()) {
    Ok(out) => {
      assert_false(out.js.contains("// ===== entry.ts ====="))
      assert_false(out.js.contains("\n  "))
      // Minified output drops spaces around binary operators and
      // collapses everything onto one line.
      assert_true(out.js.contains("const x=1"))
      assert_true(out.js.contains("console.log(x)"))
    }
    Err(e) => fail("\{e}")
  }
}

///|
test "minify: full opt + minify produces the smallest output" {
  let files : Map[String, String] = {}
  files["entry.ts"] =
    "const used = 1;\nconst dead = 2;\nfunction f(longName: number) { return longName * 2; }\nconsole.log(f(used));\n"
  let baseline_out = match
    bundle_modules(files, "entry.ts", BundleOptions::default()) {
    Ok(o) => o
    Err(e) => fail("\{e}")
  }
  let mini_out = match bundle_modules(files, "entry.ts", minify_opts()) {
    Ok(o) => o
    Err(e) => fail("\{e}")
  }
  let full_out = match
    bundle_modules(files, "entry.ts", full_opt_bundle_options()) {
    Ok(o) => o
    Err(e) => fail("\{e}")
  }
  let full_mini_out = match
    bundle_modules(files, "entry.ts", full_opt_minify_opts()) {
    Ok(o) => o
    Err(e) => fail("\{e}")
  }
  // Each layer must produce a smaller output than the previous.
  assert_true(mini_out.js.length() < baseline_out.js.length())
  assert_true(full_mini_out.js.length() < full_out.js.length())
  assert_true(full_mini_out.js.length() < mini_out.js.length())
}

///|
test "inline sourcemap: appends data URI comment" {
  let files : Map[String, String] = {}
  files["entry.ts"] = "const x = 1;\nconsole.log(x);\n"
  let opts : BundleOptions = {
    ..BundleOptions::default(),
    with_sourcemap: true,
    inline_sourcemap: true,
  }
  match bundle_modules(files, "entry.ts", opts) {
    Ok(out) => {
      assert_true(
        out.js.contains("//# sourceMappingURL=data:application/json;base64,"),
      )
      // The standalone `sourcemap` field is still populated so
      // callers that want the raw JSON can read it.
      match out.sourcemap {
        Some(json) => assert_true(json.contains("\"version\":3"))
        None => fail("expected sourcemap JSON alongside the inline copy")
      }
    }
    Err(e) => fail("\{e}")
  }
}

///|
test "inline sourcemap: no-op when with_sourcemap is off" {
  let files : Map[String, String] = {}
  files["entry.ts"] = "const x = 1;\n"
  let opts : BundleOptions = { ..BundleOptions::default(), inline_sourcemap: true }
  match bundle_modules(files, "entry.ts", opts) {
    Ok(out) =>
      assert_false(out.js.contains("//# sourceMappingURL=data:"))
    Err(e) => fail("\{e}")
  }
}

///|
async test "minify: differential parity under node — small fixture" {
  let files : Map[String, String] = {}
  files["lib.ts"] = "export function greet(name: string) { return \"hi, \" + name; }\n"
  files["entry.ts"] =
    "import { greet } from \"./lib\";\nfor (let i = 0; i < 3; i = i + 1) {\n  console.log(greet(\"alice\" + i));\n}\n"
  let baseline = match
    bundle_modules(files, "entry.ts", BundleOptions::default()) {
    Ok(o) => o
    Err(e) => fail("\{e}")
  }
  let mini = match bundle_modules(files, "entry.ts", full_opt_minify_opts()) {
    Ok(o) => o
    Err(e) => fail("\{e}")
  }
  // Write both, execute, assert stdout matches.
  @fs.write_file("/tmp/ts-mbt-minify-base.js", baseline.js, create=0o644)
  @fs.write_file("/tmp/ts-mbt-minify-opt.js", mini.js, create=0o644)
  let (b_exit, b_out) = @process.collect_output_merged("node", [
    "/tmp/ts-mbt-minify-base.js",
  ])
  let (o_exit, o_out) = @process.collect_output_merged("node", [
    "/tmp/ts-mbt-minify-opt.js",
  ])
  if b_exit != 0 {
    fail("baseline exec failed: \{b_out.text()}")
  }
  if o_exit != 0 {
    fail("minified exec failed: \{o_out.text()}")
  }
  assert_eq(b_out.text(), o_out.text())
}
