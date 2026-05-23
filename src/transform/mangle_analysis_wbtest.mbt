// Tests for the type-aware auto-reserved set generator.
//
// `auto_reserve_from_module` walks the type graph from each export and
// produces a `ManglerConfig` pre-loaded with the names + property keys
// that escape to external code. These tests stage TS sources that mix
// exported and non-exported declarations, turn on property mangling,
// and verify the right keys survive the rename.

///|
fn auto_reserve_to_js(
  src : String,
  base : ManglerConfig,
) -> Result[String, String] {
  mangle_source_with_auto_reserve(src, base)
}

///|
test "auto-reserve: exported interface field names stay verbatim" {
  // `User.userName` is reachable via `export interface User` — its
  // field key must NOT be mangled even though property mangling is on.
  let base = ManglerConfig::default().with_mangle_properties(true)
  let src =
    #|export interface User { userName: string; userScore: number; }
    #|function read(u) { return u.userName; }
  match auto_reserve_to_js(src, base) {
    Ok(js) => {
      assert_true(js.contains("userName"))
      assert_true(js.contains(".userName"))
    }
    Err(e) => fail("\{e}")
  }
}

///|
test "auto-reserve: non-exported interface fields are mangleable" {
  // `Internal` is declared but never exported — its field keys are
  // free to rename. We confirm `internalField` disappears from the
  // emitted JS.
  let base = ManglerConfig::default().with_mangle_properties(true)
  let src =
    #|interface Internal { internalField: string; }
    #|function f(x) { return x.internalField; }
  match auto_reserve_to_js(src, base) {
    Ok(js) => assert_false(js.contains("internalField"))
    Err(e) => fail("\{e}")
  }
}

///|
test "auto-reserve: transitively reachable type fields stay reserved" {
  // `Outer` is exported and references `Inner` via a field type. The
  // walker must follow that reference and reserve `Inner`'s fields
  // too, even though `Inner` itself is not exported.
  let base = ManglerConfig::default().with_mangle_properties(true)
  let src =
    #|interface Inner { innerKey: number; }
    #|export interface Outer { outerKey: Inner; }
    #|function read(o) { return o.outerKey.innerKey; }
  match auto_reserve_to_js(src, base) {
    Ok(js) => {
      assert_true(js.contains("outerKey"))
      assert_true(js.contains("innerKey"))
    }
    Err(e) => fail("\{e}")
  }
}

///|
test "auto-reserve: exported function parameter types reach into the graph" {
  // `process` is exported. Its parameter type is `Config`, which is
  // not exported by name — but the walker should still mark its
  // fields as reserved because they're part of the public surface
  // any caller has to construct.
  let base = ManglerConfig::default().with_mangle_properties(true)
  let src =
    #|interface Config { apiKey: string; timeout: number; }
    #|export function process(cfg: Config) { return cfg.apiKey + "-" + cfg.timeout; }
  match auto_reserve_to_js(src, base) {
    Ok(js) => {
      assert_true(js.contains(".apiKey"))
      assert_true(js.contains(".timeout"))
    }
    Err(e) => fail("\{e}")
  }
}

///|
test "auto-reserve: type alias indirection preserves the target's fields" {
  // `Alias` aliases `Target` and is exported. Walking through the
  // alias must reach `Target` and reserve its fields.
  let base = ManglerConfig::default().with_mangle_properties(true)
  let src =
    #|interface Target { aliasedField: boolean; }
    #|export type Alias = Target;
    #|function take(x) { return x.aliasedField; }
  match auto_reserve_to_js(src, base) {
    Ok(js) => assert_true(js.contains("aliasedField"))
    Err(e) => fail("\{e}")
  }
}

///|
test "auto-reserve: exported class properties and methods are reserved" {
  // Class shapes are part of the public surface — both property
  // names and method names need to stay accessible to consumers.
  let base = ManglerConfig::default().with_mangle_properties(true)
  let src =
    #|export class Service { publicField: number = 0; computeValue(): number { return this.publicField; } }
    #|function go(s) { return s.computeValue(); }
  match auto_reserve_to_js(src, base) {
    Ok(js) => {
      assert_true(js.contains("publicField"))
      assert_true(js.contains("computeValue"))
    }
    Err(e) => fail("\{e}")
  }
}

///|
test "auto-reserve: exported names are themselves reserved (identifier side)" {
  // `greetUser` is an exported function. Even with property mangling
  // on, the binding name has to stay so external callers can find it.
  let base = ManglerConfig::default().with_mangle_properties(true)
  let src =
    #|export function greetUser(name: string) { return "hi " + name; }
  match auto_reserve_to_js(src, base) {
    Ok(js) => assert_true(js.contains("greetUser"))
    Err(e) => fail("\{e}")
  }
}

///|
test "auto-reserve: union members on an exported alias stay reserved" {
  // `Shape = Circle | Square` — both branches feed into the public
  // surface so their discriminant + payload fields must be reserved.
  let base = ManglerConfig::default().with_mangle_properties(true)
  let src =
    #|interface Circle { kind: "circle"; radius: number; }
    #|interface Square { kind: "square"; side: number; }
    #|export type Shape = Circle | Square;
    #|function area(s) { return s.kind === "circle" ? s.radius : s.side; }
  match auto_reserve_to_js(src, base) {
    Ok(js) => {
      assert_true(js.contains("kind"))
      assert_true(js.contains("radius"))
      assert_true(js.contains("side"))
    }
    Err(e) => fail("\{e}")
  }
}
