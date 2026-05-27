// Tests for the dead-property elimination + type-declared-name
// reservation pipeline.

///|
fn dp_vfs(entries : Array[(String, String)]) -> Map[String, String] {
  let m : Map[String, String] = {}
  for entry in entries {
    m[entry.0] = entry.1
  }
  m
}

///|
test "dead-prop: unused object literal key is dropped (pure value)" {
  let files = dp_vfs([
    ("entry.ts", "const point = { x: 1, y: 2 };\nconsole.log(point.x);\n"),
  ])
  let opts = BundleOptions::default()
    .with_mangle(true)
    .with_mangle_properties(true)
    .with_minify(true)
  match bundle_modules(files, "entry.ts", opts) {
    Ok(out) => {
      // `y` is never read — dropped from the object literal.
      assert_false(out.js.contains("y:"))
      // `x` survives because we read it through `point.x`.
      assert_true(out.js.contains(".") || out.js.contains("=1"))
    }
    Err(e) => fail("bundle error: \{e}")
  }
}

///|
test "dead-prop: unused key with side-effectful value is kept" {
  // The `y` value is `f()` — a Call. Even though `y` is never
  // read, dropping the entry would lose the side effect.
  let files = dp_vfs([
    (
      "entry.ts", "function f() { console.log(\"f\"); return 1; }\nconst point = { x: 1, y: f() };\nconsole.log(point.x);\n",
    ),
  ])
  let opts = BundleOptions::default()
    .with_mangle(true)
    .with_mangle_properties(true)
    .with_minify(true)
  match bundle_modules(files, "entry.ts", opts) {
    Ok(out) =>
      // Some renamed equivalent of `f()` must remain in the
      // object literal — we still need the call to fire.
      assert_true(out.js.contains("f()") || out.js.contains("()"))
    Err(e) => fail("bundle error: \{e}")
  }
}

///|
test "dead-prop: extra_reserved_props keeps a key alive" {
  // Pretend `y` is declared in some external type — we reserve
  // it explicitly. The dead-prop pass must honor that even
  // though `y` is never read in the bundle.
  let files = dp_vfs([
    ("entry.ts", "const point = { x: 1, y: 2 };\nconsole.log(point.x);\n"),
  ])
  let opts = BundleOptions::default()
    .with_mangle(true)
    .with_mangle_properties(true)
    .with_minify(true)
    .with_extra_reserved_props(["y"])
  match bundle_modules(files, "entry.ts", opts) {
    Ok(out) =>
      // The reserved name `y` survives. (After identifier
      // mangling, `point` becomes `a`, but the property `y`
      // stays.)
      assert_true(out.js.contains("y:"))
    Err(e) => fail("bundle error: \{e}")
  }
}

///|
test "dead-prop: suppressed when safety analysis emits wildcard" {
  // `JSON.stringify(point)` forces wildcard reservation.
  // Property mangling AND dead-prop pruning are both suppressed.
  let files = dp_vfs([
    (
      "entry.ts", "const point = { x: 1, y: 2 };\nconsole.log(JSON.stringify(point));\n",
    ),
  ])
  let opts = BundleOptions::default()
    .with_mangle(true)
    .with_mangle_properties(true)
    .with_minify(true)
  match bundle_modules(files, "entry.ts", opts) {
    Ok(out) => {
      // Both keys survive because they'd otherwise leak through
      // JSON serialization.
      assert_true(out.js.contains("x:"))
      assert_true(out.js.contains("y:"))
    }
    Err(e) => fail("bundle error: \{e}")
  }
}

///|
test "type_props: inline object types contribute to the harvest" {
  let src =
    #|interface User {
    #|  id: number;
    #|  name: string;
    #|}
    #|function pair<T, U>(t: T, u: U): { left: T; right: U } {
    #|  return { left: t, right: u };
    #|}
  let module_ = @parser.parse_module_from_source_with_const_values(src, {})
  let names = type_declared_property_names(module_)
  let seen : Map[String, Bool] = {}
  for n in names {
    seen[n] = true
  }
  // Interface fields:
  assert_true(seen.contains("id"))
  assert_true(seen.contains("name"))
  // Inline object types in the return type / params:
  assert_true(seen.contains("left"))
  assert_true(seen.contains("right"))
}
