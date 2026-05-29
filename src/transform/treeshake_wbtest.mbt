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

///|
test "treeshake: template-literal initializer is pure and can be dropped" {
  let files = ts_vfs([
    (
      "entry.ts",
      (
        #|const prefix = "hello";
        #|const unused_msg = `${prefix}, world!`;
        #|console.log(prefix);
      ),
    ),
  ])
  let opts = BundleOptions::default().with_treeshake(true)
  match bundle_modules(files, "entry.ts", opts) {
    Ok(out) => {
      // `unused_msg` binding should be dropped since it's never referenced.
      assert_false(out.js.contains("unused_msg"))
      assert_true(out.js.contains("hello"))
    }
    Err(e) => fail("bundle error: \{e}")
  }
}

///|
test "treeshake: dead NativeClassStmt is dropped" {
  // An unreferenced native class should be dropped when its initializer
  // is pure (no side-effecting static fields or base constructor calls).
  let src = (
    #|class Dead { greet() { return "bye"; } }
    #|console.log("hello");
  )
  let block = @parser.parse_block_from_source(src)
  let out = treeshake_block(block)
  let names : Map[String, Bool] = {}
  for s in out.stmts {
    match s {
      @ast.TsStmt::NativeClassStmt(decl, _) => names[decl.name] = true
      _ => ()
    }
  }
  assert_false(names.contains("Dead"))
}

///|
test "treeshake: live NativeClassStmt is retained" {
  // A named class that is instantiated must survive treeshaking.
  // Before the fix, NativeClassStmt name was extracted as "" in pass 4,
  // so even live classes were incorrectly dropped.
  let src = (
    #|class Alive { greet() { return "hi"; } }
    #|const unused = 42;
    #|const obj = new Alive();
    #|console.log(obj.greet());
  )
  let block = @parser.parse_block_from_source(src)
  // Lift IIFE-lowered classes to NativeClassStmt before treeshaking so the
  // treeshaker sees the structured form and can reason about the class name.
  let lifted = iife_class_lift_block(block)
  let out = treeshake_block(lifted)
  let names : Map[String, Bool] = {}
  for s in out.stmts {
    match s {
      @ast.TsStmt::NativeClassStmt(decl, _) => names[decl.name] = true
      _ => ()
    }
  }
  assert_true(names.contains("Alive"))
}
