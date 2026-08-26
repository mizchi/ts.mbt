// Tests for `#private` field emission.
//
// The parser rewrites `#secret` to `__private_brand__N__secret`, which
// is an ordinary own enumerable property when emitted — visible to
// `JSON.stringify`, `Object.keys`, `for...in` and object spread, where a
// real private field is not.

///|
fn private_bundle(src : String) -> String raise {
  let files : Map[String, String] = { "entry.ts": src }
  let opts = BundleOptions::default().with_treeshake(true)
  match bundle_modules(files, "entry.ts", opts) {
    Ok(out) => out.js
    Err(e) => fail("bundle error: \{e}")
  }
}

///|
test "private fields: a field with an initializer becomes `#x`" {
  let out = private_bundle(
    (
      #|class C {
      #|  pub = 1;
      #|  #secret = 7;
      #|  read() { return this.#secret; }
      #|}
      #|export const c = new C();
      #|
    ),
  )
  assert_false(out.contains("__private_brand__"), msg="left the brand: \{out}")
  // The declaration has to be there or `this.#secret = 7` is a
  // SyntaxError.
  assert_true(out.contains("#secret;"), msg="no declaration: \{out}")
  assert_true(out.contains("this.#secret = 7"), msg="no assignment: \{out}")
}

///|
test "private fields: a private method becomes `#m()` with no declaration" {
  let out = private_bundle(
    (
      #|class C {
      #|  #hidden() { return 1; }
      #|  read() { return this.#hidden(); }
      #|}
      #|export const c = new C();
      #|
    ),
  )
  assert_false(out.contains("__private_brand__"), msg="left the brand: \{out}")
  assert_true(out.contains("#hidden()"), msg="no method: \{out}")
  // A method declares itself; a bare `#hidden;` next to it would be a
  // duplicate declaration.
  assert_false(out.contains("#hidden;"), msg="declared a method: \{out}")
}

///|
test "private fields: a static private keeps the brand" {
  // The class lowering drops `static #x = 3` outright, initializer and
  // all, so `C.#x` already reads `undefined`. Renaming the read with no
  // declaration to point at would turn that into a parse error, so the
  // brand stays.
  let out = private_bundle(
    (
      #|class C {
      #|  static #stat = 3;
      #|  read() { return C.#stat; }
      #|}
      #|export const c = new C();
      #|
    ),
  )
  assert_true(
    out.contains("__private_brand__"),
    msg="renamed an undeclarable brand: \{out}",
  )
}

///|
test "private fields: a brand mentioned outside its class keeps the brand" {
  // `#x` is scoped to the class body, so a reference from another
  // top-level statement cannot be spelled `#x`. mtsc produces exactly
  // that when it lowers an accessor to
  // `Object.defineProperty(C.prototype, …, { get() { return this.#x } })`
  // beside the class — hono's `Context` does, and renaming there stopped
  // the whole bundle from loading.
  let out = private_bundle(
    (
      #|class C {
      #|  #secret = 7;
      #|  read() { return this.#secret; }
      #|}
      #|Object.defineProperty(C.prototype, "alias", {
      #|  get: function () { return this.#secret; },
      #|});
      #|export const c = new C();
      #|
    ),
  )
  assert_true(
    out.contains("__private_brand__"),
    msg="renamed a brand that escapes its class: \{out}",
  )
}
