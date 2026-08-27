// Tests for the `.name` reservation.
//
// The invariant: if the bundle can observe a class's `.name`, `--mangle`
// must not rename that class. The corpus caught the violation on
// superstruct, whose error base does
// `this.name = this.constructor.name`.

///|
fn mangled_js(src : String) -> String raise {
  let files : Map[String, String] = { "entry.ts": src }
  let opts = BundleOptions::default()
    .with_treeshake(true)
    .with_fold(true)
    .with_minify(true)
    .with_mangle(true)
  match bundle_modules(files, "entry.ts", opts) {
    Ok(out) => out.js
    Err(e) => fail("bundle error: \{e}")
  }
}

///|
test "observed names: a class whose `.name` is read keeps its name" {
  let out = mangled_js(
    (
      #|class Keeper {
      #|  go() { return 1; }
      #|}
      #|class Renamable {
      #|  go() { return 2; }
      #|}
      #|export const both = [Keeper.name, new Renamable().go()];
      #|
    ),
  )
  assert_true(out.contains("Keeper"), msg="renamed an observed class: \{out}")
  // The other one has nothing observing it, so it still pays no bytes.
  assert_false(
    out.contains("Renamable"),
    msg="reserved a class nothing observes: \{out}",
  )
}

///|
test "observed names: `C[\"name\"]` counts as reading it" {
  let out = mangled_js(
    (
      #|class Keeper { go() { return 1; } }
      #|export const n = Keeper["name"];
      #|
    ),
  )
  assert_true(out.contains("Keeper"), msg="renamed an observed class: \{out}")
}

///|
test "observed names: `this.constructor.name` reserves every top-level name" {
  // The superstruct shape. A base class reading `this.constructor.name`
  // sees it through every subclass, and nothing in the syntax says
  // which, so no top-level binding may be renamed.
  let out = mangled_js(
    (
      #|class Base {
      #|  constructor() { this.tag = this.constructor.name; }
      #|}
      #|class Derived extends Base {}
      #|export const d = new Derived();
      #|
    ),
  )
  assert_true(
    out.contains("Derived"),
    msg="renamed a class reachable through `this.constructor.name`: \{out}",
  )
  assert_true(out.contains("Base"), msg="renamed the base class: \{out}")
}

///|
test "observed names: an ordinary `.name` read reserves nothing" {
  // `.name` on a plain object is the common case by far. If this
  // reserved the top level, almost every bundle would stop mangling.
  let out = mangled_js(
    (
      #|class Renamable { go() { return 1; } }
      #|const person = { name: "ada" };
      #|export const both = [person.name, new Renamable().go()];
      #|
    ),
  )
  assert_false(
    out.contains("Renamable"),
    msg="an ordinary `.name` read reserved the top level: \{out}",
  )
}

///|
test "observed names: `this.constructor.name` spares unrelated classes" {
  // The narrowing that makes this affordable. `this.constructor` inside a
  // method of `Base` is `Base` or a subclass, never `Unrelated`, so
  // `Unrelated` still mangles.
  //
  // Without the hierarchy, the only sound answer is "reserve every
  // callable", and the corpus priced that at typebox +70%, zod +40%,
  // superstruct +31%.
  let out = mangled_js(
    (
      #|class Base {
      #|  constructor() { this.tag = this.constructor.name; }
      #|}
      #|class Derived extends Base {}
      #|class Unrelated { go() { return 7; } }
      #|export const all = [new Derived(), new Unrelated().go()];
      #|
    ),
  )
  assert_true(out.contains("Base"), msg="renamed the observing class: \{out}")
  assert_true(
    out.contains("Derived"),
    msg="renamed a subclass of the observing class: \{out}",
  )
  assert_false(
    out.contains("Unrelated"),
    msg="reserved a class the hierarchy rules out: \{out}",
  )
}

///|
test "observed names: a free function reading `.constructor.name` falls back" {
  // `this` is unconstrained outside a class body, so the hierarchy says
  // nothing and every callable has to keep its name. Expensive, and the
  // only sound answer for this shape.
  let out = mangled_js(
    (
      #|class Anything { go() { return 1; } }
      #|function label(x) { return x.constructor.name; }
      #|export const both = [label(new Anything()), new Anything().go()];
      #|
    ),
  )
  assert_true(
    out.contains("Anything"),
    msg="mangled a class reachable from an unconstrained `.constructor.name`: \{out}",
  )
}
