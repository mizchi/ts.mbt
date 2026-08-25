// Tests for the export-surface escape analysis and the mangle-safety
// behaviour it guarantees end to end.
//
// The invariant under test: a property name is renamable only when no
// outside observer can reach it. The corpus under
// `fixtures/mangle-safety/` proves that empirically by running the
// bundles; these tests pin the individual rules.

///|
fn surface_vfs(entries : Array[(String, String)]) -> Map[String, String] {
  let m : Map[String, String] = {}
  for entry in entries {
    m[entry.0] = entry.1
  }
  m
}

///|
fn surface_props_of(source : String, exported : Array[String]) -> Array[String] {
  let block = @parser.Parser::from_source(source).parse_module_block() catch {
    e => abort("parse error: \{e}")
  }
  let locals : Map[String, Bool] = {}
  for n in exported {
    locals[n] = true
  }
  exported_surface_props(block.block, locals)
}

///|
/// Compare a reserved-name set against an expected list. The pass
/// collects into a `Map`, whose iteration order is unspecified, so
/// compare as sets rather than as sequences.
fn assert_names(actual : Array[String], expected : Array[String]) -> Unit raise {
  for want in expected {
    if !actual.contains(want) {
      fail("expected `\{want}` to be reserved, got \{actual}")
    }
  }
  for got in actual {
    if !expected.contains(got) {
      fail("`\{got}` was reserved unexpectedly, got \{actual}")
    }
  }
}

///|
test "export surface: object literal keys reaching an export are reserved, nested included" {
  let names = surface_props_of(
    (
      #|const shape = { outer: { inner: 1 } };
      #|const hidden = { nope: 2 };
    ),
    ["shape"],
  )
  assert_names(names, ["outer", "inner"])
}

///|
test "export surface: an exported function publishes its return shape" {
  let names = surface_props_of(
    (
      #|function run() {
      #|  return { first: 1, rest: [2] };
      #|}
    ),
    ["run"],
  )
  assert_names(names, ["first", "rest"])
}

///|
test "export surface: properties read off an exported function's parameter are ABI" {
  // The caller has to build `{ input }`, so the name is part of the
  // signature even though no type declaration mentions it here.
  let names = surface_props_of(
    (
      #|function myfn(arg) {
      #|  return arg.input + 1;
      #|}
    ),
    ["myfn"],
  )
  assert_names(names, ["input"])
}

///|
test "export surface: a destructured parameter names its own keys" {
  let names = surface_props_of(
    (
      #|function component({ prop1, prop2 }) {
      #|  return prop1 + prop2;
      #|}
    ),
    ["component"],
  )
  assert_names(names, ["prop1", "prop2"])
}

///|
test "export surface: an expression-bodied arrow publishes its parameter shape" {
  let names = surface_props_of("const read = (o) => o.field;\n", ["read"])
  assert_names(names, ["field"])
}

///|
test "export surface: a callback's return shape escapes through the call it feeds" {
  // `[…].map(x => ({ www: … }))` — the element shape of the exported
  // array is produced inside the arrow.
  let names = surface_props_of(
    (
      #|const results = [1, 2].map((x) => {
      #|  return { www: x * 2 };
      #|});
    ),
    ["results"],
  )
  assert_true(names.contains("www"))
}

///|
test "export surface: nothing reachable from a non-exported binding is reserved" {
  let names = surface_props_of(
    (
      #|const internal = { secret: 1 };
      #|const alsoInternal = { other: internal.secret };
    ),
    [],
  )
  assert_names(names, [])
}

///|
test "export surface: a cycle through two bindings terminates" {
  let names = surface_props_of(
    (
      #|const a = { toB: b };
      #|const b = { toA: a };
    ),
    ["a"],
  )
  assert_names(names, ["toA", "toB"])
}

///|
test "mangle safety: keys of an exported value survive --mangle-properties" {
  // Regression for the dead-property pass deleting keys nothing inside
  // the bundle reads: a consumer reads them.
  let files = surface_vfs([
    ("entry.ts", "export const additional = { addition: true };\n"),
  ])
  let opts = BundleOptions::default()
    .with_mangle(true)
    .with_mangle_properties(true)
    .with_minify(true)
  match bundle_modules(files, "entry.ts", opts) {
    Ok(out) => assert_true(out.js.contains("addition"))
    Err(e) => fail("bundle error: \{e}")
  }
}

///|
test "mangle safety: an exported function's inferred return keys survive" {
  let files = surface_vfs([
    (
      "entry.ts",
      (
        #|export function run() {
        #|  const internal = { name: "n", age: 1 };
        #|  return { name: internal.name, age: internal.age };
        #|}
      ),
    ),
  ])
  let opts = BundleOptions::default()
    .with_mangle(true)
    .with_mangle_properties(true)
    .with_minify(true)
  match bundle_modules(files, "entry.ts", opts) {
    Ok(out) => {
      assert_true(out.js.contains("name"))
      assert_true(out.js.contains("age"))
    }
    Err(e) => fail("bundle error: \{e}")
  }
}

///|
test "mangle safety: object-literal keys handed to an external call survive" {
  // The foreign callee reads them by name; the literal has no free
  // variable for the flow analysis to seed from.
  let files = surface_vfs([
    (
      "entry.ts",
      (
        #|import { send } from "ext-a";
        #|send({ rrr: 123 });
      ),
    ),
  ])
  let opts = BundleOptions::default()
    .with_mangle(true)
    .with_mangle_properties(true)
    .with_minify(true)
  match bundle_modules(files, "entry.ts", opts) {
    Ok(out) => assert_true(out.js.contains("rrr"))
    Err(e) => fail("bundle error: \{e}")
  }
}

///|
test "mangle safety: nested keys under JSON.stringify survive" {
  let files = surface_vfs([
    (
      "entry.ts",
      (
        #|export function post(url) {
        #|  return fetch(url, { body: JSON.stringify({ outer: { inner: 1 } }) });
        #|}
      ),
    ),
  ])
  let opts = BundleOptions::default()
    .with_mangle(true)
    .with_mangle_properties(true)
    .with_minify(true)
  match bundle_modules(files, "entry.ts", opts) {
    Ok(out) => {
      assert_true(out.js.contains("outer"))
      assert_true(out.js.contains("inner"))
    }
    Err(e) => fail("bundle error: \{e}")
  }
}

///|
test "mangle safety: an internal-only shape is still mangled" {
  // The other half of the invariant: staying conservative everywhere
  // would be sound but useless.
  let files = surface_vfs([
    (
      "entry.ts",
      (
        #|function helper() {
        #|  const local = { internalOnly: 1 };
        #|  return local.internalOnly;
        #|}
        #|export const total = helper();
      ),
    ),
  ])
  let opts = BundleOptions::default()
    .with_mangle(true)
    .with_mangle_properties(true)
    .with_minify(true)
  match bundle_modules(files, "entry.ts", opts) {
    Ok(out) => assert_false(out.js.contains("internalOnly"))
    Err(e) => fail("bundle error: \{e}")
  }
}

///|
test "bundle exports: `export … from` re-exports reach the bundle's export clause" {
  let files = surface_vfs([
    ("sub.ts", "export function subFn() {\n  return 1;\n}\n"),
    ("entry.ts", "export { subFn } from \"./sub\";\n"),
  ])
  match bundle_modules(files, "entry.ts", BundleOptions::default()) {
    Ok(out) => assert_true(out.js.contains("subFn"))
    Err(e) => fail("bundle error: \{e}")
  }
}

///|
test "bundle exports: `export *` forwards every name" {
  let files = surface_vfs([
    (
      "sub.ts", "export const one = 1;\nexport function two() {\n  return 2;\n}\n",
    ),
    ("entry.ts", "export * from \"./sub\";\n"),
  ])
  match bundle_modules(files, "entry.ts", BundleOptions::default()) {
    Ok(out) => {
      assert_true(out.js.contains("one"))
      assert_true(out.js.contains("two"))
    }
    Err(e) => fail("bundle error: \{e}")
  }
}

///|
test "bundle exports: a type-only export is not emitted as a value" {
  // `export type { T }` has no runtime binding; emitting it produces a
  // bundle that fails to load.
  let files = surface_vfs([
    (
      "entry.ts",
      (
        #|type Shape = { v: number };
        #|export type { Shape };
        #|export const value = 1;
      ),
    ),
  ])
  match bundle_modules(files, "entry.ts", BundleOptions::default()) {
    Ok(out) => {
      assert_true(out.js.contains("value"))
      assert_false(out.js.contains("Shape"))
    }
    Err(e) => fail("bundle error: \{e}")
  }
}

///|
test "mangle: a call with explicit type arguments follows its renamed callee" {
  let source =
    #|function identity(v) {
    #|  return v;
    #|}
    #|export const value = identity<number>(1);
  let files = surface_vfs([("entry.ts", source)])
  let opts = BundleOptions::default().with_mangle(true).with_minify(true)
  match bundle_modules(files, "entry.ts", opts) {
    // The declaration was renamed, so the pre-mangle name must not
    // survive at the call site.
    Ok(out) => assert_false(out.js.contains("identity"))
    Err(e) => fail("bundle error: \{e}")
  }
}
