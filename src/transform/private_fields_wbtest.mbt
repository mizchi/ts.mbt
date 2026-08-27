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
test "private fields: a static private becomes `static #x`" {
  // `static #x = init` reaches emit as a `static_field_inits` entry, and
  // `static #x = init;` in a class body declares the member itself — so
  // the read has something to resolve against and the brand can go.
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
  assert_false(out.contains("__private_brand__"), msg="left the brand: \{out}")
  assert_true(out.contains("#stat = 3"), msg="no static field: \{out}")
  assert_true(out.contains("C.#stat"), msg="no static read: \{out}")
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

///|
test "private fields: a nested class reading an outer private keeps the brand" {
  // The parser brands a `#x` reference with the class whose BODY encloses
  // it. JS resolves `#x` to the nearest enclosing class that DECLARES it,
  // so a class nested inside a method carries its own brand on a read of
  // the outer field, and the read comes back `undefined`.
  //
  // Renaming that reference to `#secret` would fix this program and break
  // the shadowing one below, and the two are indistinguishable from the
  // property names alone. So the brand stays and the read stays wrong —
  // a wrong value rather than a crash. `lower_private_fields` carries the
  // argument in full.
  let out = private_bundle(
    (
      #|class Outer {
      #|  #secret = 7;
      #|  nest() {
      #|    const Inner = class {
      #|      peek(o) { return o.#secret; }
      #|    };
      #|    return new Inner().peek(this);
      #|  }
      #|}
      #|export const c = new Outer();
      #|
    ),
  )
  assert_true(
    out.contains("__private_brand__"),
    msg="renamed a reference the declaring class does not own: \{out}",
  )
}

///|
test "private fields: a nested class shadowing an outer private still runs" {
  // The case the remap above would have broken. `Inner` declares its own
  // `#x`, so the program is correct as written — but by the time it is
  // emitted the IIFE lift has turned `Inner` into a plain `function`, and
  // a `#x` there binds to Outer's declaration with a non-Outer `this`:
  // "Cannot write private member #x to an object whose class did not
  // declare it". A wrong value would have become a crash.
  let out = private_bundle(
    (
      #|class Outer {
      #|  #x = 1;
      #|  read() {
      #|    const Inner = class {
      #|      #x = 2;
      #|      get() { return this.#x; }
      #|    };
      #|    return [this.#x, new Inner().get()];
      #|  }
      #|}
      #|export const c = new Outer();
      #|
    ),
  )
  // Outer's own field lowers; Inner's stays a plain property, which is
  // what it already was.
  assert_true(out.contains("this.#x = 1"), msg="no outer declaration: \{out}")
  assert_true(
    out.contains("__private_brand__"),
    msg="merged a shadowing field into the outer one: \{out}",
  )
}
