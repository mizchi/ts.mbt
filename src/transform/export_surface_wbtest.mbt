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
/// Same, but with the class lift applied first, as the real pipeline
/// does: `bundle.mbt` runs `iife-class-lift` before `export-surface`, so
/// a `class C { … }` reaches this pass as a `NativeClassStmt`. Parsed
/// straight from source it is still the IIFE-and-prototype-assignment
/// form, where `w.classes` is empty and every class test would pass
/// vacuously.
fn surface_props_of_classes(
  source : String,
  exported : Array[String],
) -> Array[String] {
  let block = @parser.Parser::from_source(source).parse_module_block() catch {
    e => abort("parse error: \{e}")
  }
  let locals : Map[String, Bool] = {}
  for n in exported {
    locals[n] = true
  }
  exported_surface_props(iife_class_lift_block(block.block), locals)
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

///|
test "export surface: a class reached from many sites is still fully reserved" {
  // The memo in `surface_should_walk` exists because a class reached
  // from N `new C(…)` sites was escaped N times, and each escape walked
  // every method's returns, which reach more `new` — exponential in the
  // call graph's branching. neverthrow is 33 KB in five files and did
  // not finish in seven minutes.
  //
  // The risk in memoizing is the opposite failure: walk the class once,
  // miss part of its surface, rename a name a consumer reads. So this
  // pins the surface of a class reached three separate ways — directly
  // from an export, through a factory function, and from a method of
  // another class — and every member has to survive.
  let names = surface_props_of_classes(
    (
      #|class Inner {
      #|  constructor() { this.innerField = 1; }
      #|  innerMethod() { return { innerKey: 2 }; }
      #|}
      #|class Outer {
      #|  constructor() { this.outerField = new Inner(); }
      #|  outerMethod() { return new Inner(); }
      #|}
      #|function make() { return new Inner(); }
      #|const entry = { first: new Outer(), second: make(), third: new Inner() };
    ),
    ["entry"],
  )
  assert_names(names, [
    "first", "second", "third", "outerField", "outerMethod", "innerField", "innerMethod",
    "innerKey",
  ])
}

///|
test "export surface: a write that reads the key it writes terminates" {
  // `ledger.n = ledger.n + 1` — an increment, and the plainest
  // self-referential property write there is.
  //
  // Escaping a property READ has to escape the recorded WRITES into that
  // key as well: resolving `bag.p` against the object literal's own
  // entry and stopping was how `mtsc --bundle` came to delete the methods
  // of a class that only reaches a consumer through such a field. But the
  // write can mention the key it writes, and walking it then re-enters
  // the same question one level deeper. Five lines of TypeScript did not
  // terminate, and `fixtures/mangle-safety/case36-annotated-boundary`
  // (which has exactly this increment) hung the whole corpus.
  //
  // The memo that stops it is keyed on `(receiver, key)` and lives beside
  // the one for named bodies, whose doc comment describes this same
  // failure mode — it was already in this file, and the fix above simply
  // did not use it.
  // The increment is what threatens termination; `box` is what makes the
  // test able to fail for the RIGHT reason. Reading `ledger.box` publishes
  // the value stored at that key, and the literal's own entry for it is
  // `null` — so `inner` is on the surface only if the recorded WRITE is
  // followed, which is the fix under test. Asserting on the increment's
  // own key instead would have asserted nothing: the first draft of this
  // test expected `pendingCount` to be reserved and got `[]`, correctly,
  // because reading a key publishes its VALUE and not its name.
  let names = surface_props_of(
    (
      #|const ledger = { counter: 0, box: null };
      #|function bump(v) {
      #|  ledger.counter = ledger.counter + 1;
      #|  ledger.box = { inner: v };
      #|  return ledger.box;
      #|}
    ),
    ["bump"],
  )
  assert_names(names, ["inner"])
}

///|
test "export surface: a two-object write cycle terminates" {
  // The mutual form of the same hazard: neither write mentions its own
  // key, so a memo keyed on the KEY alone would not catch it — `a.toB`
  // escapes `b`, whose `b.toA` escapes `a`, back to `a.toB`.
  let names = surface_props_of(
    (
      #|const a = { toB: null, aOwn: 1 };
      #|const b = { toA: null, bOwn: 2 };
      #|a.toB = b;
      #|b.toA = a;
      #|function reach() { return a.toB; }
    ),
    ["reach"],
  )
  assert_names(names, ["toB", "aOwn", "toA", "bOwn"])
}
