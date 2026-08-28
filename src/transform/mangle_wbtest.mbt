// Mangler tests. Each case parses TS source into a `TsBlock`, runs
// the mangle pass, and emits the result back to JS to check the
// rename outcome.

///|
fn mangle_to_js(src : String, cfg : ManglerConfig) -> Result[String, String] {
  let block = try @parser.parse_block_from_source(src) catch {
    e => return Err("parse error: \{e}")
  } noraise {
    b => b
  }
  let mangled = mangle_block(block, cfg)
  let e = Emitter::new()
  for s in mangled.stmts {
    emit_stmt(e, s)
    e.nl()
  }
  Ok(e.to_string())
}

///|
fn assert_mangled_contains(
  label : String,
  src : String,
  cfg : ManglerConfig,
  needles : Array[String],
) -> Unit raise {
  match mangle_to_js(src, cfg) {
    Ok(js) =>
      for needle in needles {
        if !js.contains(needle) {
          println("FAIL [\{label}] missing \"\{needle}\" in:")
          println(js)
          fail("missing fragment: \{needle}")
        }
      }
    Err(e) => fail("[\{label}] error: \{e}")
  }
}

///|
test "mangle: top-level bindings are preserved by default" {
  // `userScore` is at the top level and `preserve_top_level=true`
  // protects it; the call site must keep calling it by name.
  let cfg = ManglerConfig::default()
  assert_mangled_contains(
    "top-level preserve",
    "const userScore = 42;\nconsole.log(userScore);",
    cfg,
    ["const userScore", "userScore"],
  )
}

///|
test "mangle: function-local bindings get renamed to short names" {
  // `items` / `aggregate` / `value` are inside the function and
  // should compress to short names (the order is deterministic
  // from declaration order). The top-level fn name stays put.
  let cfg = ManglerConfig::default()
  let src =
    #|function sum(items) {
    #|  let aggregate = 0;
    #|  for (const value of items) {
    #|    aggregate = aggregate + value;
    #|  }
    #|  return aggregate;
    #|}
  match mangle_to_js(src, cfg) {
    Ok(js) => {
      assert_true(js.contains("function sum"))
      // None of the long original names should survive.
      assert_false(js.contains("items"))
      assert_false(js.contains("aggregate"))
      // for-of value binding got renamed too.
      assert_false(js.contains("const value"))
    }
    Err(e) => fail("\{e}")
  }
}

///|
test "mangle: function params are renamed and references follow" {
  // The body must still reference the parameter through its
  // renamed identifier.
  let cfg = ManglerConfig::default()
  let src =
    #|function add(left, right) {
    #|  return left + right;
    #|}
  match mangle_to_js(src, cfg) {
    Ok(js) => {
      // Names get compressed to single letters but the addition
      // expression must still type-check with both renamed sides.
      assert_true(js.contains("function add"))
      // No more `left` or `right` in the body.
      assert_false(js.contains("left"))
      assert_false(js.contains("right"))
      // The two parameters should appear in the body as references
      // — search for `a + b` as the renamed shape.
      let mut has_renamed_add = false
      for left in ["a", "b", "c"] {
        for right in ["a", "b", "c"] {
          if left != right && js.contains(left + " + " + right) {
            has_renamed_add = true
          }
        }
      }
      assert_true(has_renamed_add)
    }
    Err(e) => fail("\{e}")
  }
}

///|
test "mangle: builtins like console / window are preserved" {
  let cfg = ManglerConfig::default()
  let src =
    #|function greet(name) {
    #|  const msg = "hi " + name;
    #|  console.log(msg);
    #|  return msg;
    #|}
  match mangle_to_js(src, cfg) {
    Ok(js) => {
      // `console` is a built-in reserved name.
      assert_true(js.contains("console.log"))
      // The original `msg` / `name` should be gone.
      assert_false(js.contains("const msg"))
      assert_false(js.contains("\"hi \" + name"))
    }
    Err(e) => fail("\{e}")
  }
}

///|
test "mangle: nested function bodies get their own scope" {
  // Inner `count` should pick its own short name independent of
  // the outer scope. Both bindings happen to be local so both
  // get renamed; the outer name is shadowed inside the inner
  // function.
  let cfg = ManglerConfig::default()
  let src =
    #|function outer() {
    #|  function inner(count) {
    #|    return count + 1;
    #|  }
    #|  return inner;
    #|}
  match mangle_to_js(src, cfg) {
    Ok(js) => {
      // Top-level `outer` is preserved (default mangler config).
      assert_true(js.contains("function outer"))
      // Inner `inner` is a local declaration in `outer`'s scope —
      // the mangler renames it. After emit-time function-decl
      // lowering, the outer-binding rename IS the function name.
      assert_false(js.contains("inner"))
      // Parameter `count` was renamed too.
      assert_false(js.contains("count + 1"))
    }
    Err(e) => fail("\{e}")
  }
}

///|
test "mangle: nested call to outer binding is not shadowed by inner local" {
  // Regression: a nested function that *calls* an outer binding
  // (`init(...)`) must reserve that binding's short name so an
  // inner local can't reuse it. The callee of `Call(name, args)`
  // is stored as a bare string, so the free-variable collector
  // used to miss it — letting `inst` and `init` collapse onto the
  // same short name and turning `init(inst)` into `inst(inst)`.
  let cfg = ManglerConfig::default()
  let src =
    #|function make() {
    #|  function init(x) { return x; }
    #|  function build(arg) {
    #|    const inst = arg;
    #|    return init(inst);
    #|  }
    #|  return build;
    #|}
  match mangle_to_js(src, cfg) {
    Ok(js) => {
      // `build`'s local `inst` is renamed to `c`; the call to the
      // captured outer `init` (renamed `a`) must stay `a(c)`. The
      // buggy collapse produced `c(c)` (calling the local instead).
      assert_true(js.contains("a(c)"))
      assert_false(js.contains("c(c)"))
    }
    Err(e) => fail("\{e}")
  }
}

///|
test "mangle: explicit reserved set overrides default" {
  // `keepMe` should NOT be mangled because the caller asked for it
  // to be reserved.
  let cfg = ManglerConfig::default().with_reserved(["keepMe"])
  let src =
    #|function f() {
    #|  let keepMe = 1;
    #|  let alsoLocal = 2;
    #|  return keepMe + alsoLocal;
    #|}
  match mangle_to_js(src, cfg) {
    Ok(js) => {
      assert_true(js.contains("keepMe"))
      // `alsoLocal` was not reserved → got mangled.
      assert_false(js.contains("alsoLocal"))
    }
    Err(e) => fail("\{e}")
  }
}

///|
test "mangle: top-level mangling when preserve_top_level=false" {
  let cfg = ManglerConfig::default().with_preserve_top_level(false)
  let src =
    #|const longLocalName = 1;
    #|const anotherLong = longLocalName + 2;
  match mangle_to_js(src, cfg) {
    Ok(js) => {
      assert_false(js.contains("longLocalName"))
      assert_false(js.contains("anotherLong"))
      assert_true(js.contains("const a"))
      assert_true(js.contains("const b"))
    }
    Err(e) => fail("\{e}")
  }
}

///|
test "mangle: property keys are NOT renamed (v0 boundary)" {
  // The mangler treats `recv.prop` as receiver-only-rename. The
  // `prop` name must survive untouched until the type-aware
  // property-mangling pass lands.
  let cfg = ManglerConfig::default().with_preserve_top_level(false)
  let src =
    #|const longName = obj.prop.subProp;
  match mangle_to_js(src, cfg) {
    Ok(js) => {
      // Receiver `obj` is a free variable → resolved as-is.
      assert_true(js.contains("obj.prop.subProp"))
      // The binding `longName` was renamed.
      assert_false(js.contains("longName"))
    }
    Err(e) => fail("\{e}")
  }
}

///|
test "mangle: properties stay untouched by default (mangle_properties=false)" {
  // The default config keeps property keys exactly as-is.
  let cfg = ManglerConfig::default()
  let src =
    #|function f(obj) {
    #|  obj.userName = "alice";
    #|  return obj.userName.length;
    #|}
  match mangle_to_js(src, cfg) {
    Ok(js) => {
      assert_true(js.contains(".userName"))
      assert_true(js.contains(".length"))
    }
    Err(e) => fail("\{e}")
  }
}

///|
// EXPERIMENTAL shape-coloring rename: properties that never co-occur
// on the same shape may share a short name. Two distinct objects
// with disjoint key sets should collapse into a single short-name
// pool — packelyze-style.
test "mangle: shape-coloring rename shares short names across disjoint shapes" {
  let cfg = ManglerConfig::default()
    .with_mangle_properties(true)
    .with_mangle_properties_shape_color(true)
  let src =
    #|const point = { xCoord: 1, yCoord: 2 };
    #|const event = { msgType: "click", msgPayload: null };
    #|sink(point.xCoord, point.yCoord, event.msgType, event.msgPayload);
  match mangle_to_js(src, cfg) {
    Ok(js) => {
      // The four original names disappear...
      assert_false(js.contains("xCoord"))
      assert_false(js.contains("yCoord"))
      assert_false(js.contains("msgType"))
      assert_false(js.contains("msgPayload"))
      // ...and the rename pool reuses short names across the two
      // disjoint shapes: only TWO distinct short names suffice.
      // (Default global-cohort rename would have needed four.)
      let single_char_names : Map[String, Bool] = {}
      for c in "abcdefghijklmnopqrstuvwxyz" {
        let probe = "." + c.to_string()
        if js.contains(probe) {
          single_char_names[c.to_string()] = true
        }
      }
      // Strict expectation: <= 2 short names emitted for the four
      // properties, because { xCoord, yCoord } and { msgType,
      // msgPayload } are disjoint cliques.
      assert_true(single_char_names.length() <= 2)
    }
    Err(e) => fail("\{e}")
  }
}

///|
// Within the same object literal, every key pair conflicts — the
// shape-coloring pass MUST keep them distinct.
test "mangle: shape-coloring keeps co-occurring keys distinct" {
  let cfg = ManglerConfig::default()
    .with_mangle_properties(true)
    .with_mangle_properties_shape_color(true)
  let src =
    #|const p = { xCoord: 1, yCoord: 2 };
    #|sink(p.xCoord + p.yCoord);
  match mangle_to_js(src, cfg) {
    Ok(js) => {
      assert_false(js.contains("xCoord"))
      assert_false(js.contains("yCoord"))
      // The shortened keys must still be distinct — fishing them
      // out: the object literal must carry TWO entries.
      let single_char_names : Map[String, Bool] = {}
      for c in "abcdefghijklmnopqrstuvwxyz" {
        let probe = "." + c.to_string()
        if js.contains(probe) {
          single_char_names[c.to_string()] = true
        }
      }
      assert_true(single_char_names.length() >= 2)
    }
    Err(e) => fail("\{e}")
  }
}

///|
// When a Symbol's PropReceiver uses both keys (`obj.foo; obj.bar`)
// the conflict graph adds them even without a containing object
// literal — the type information that bound `obj` carries the
// shape.
// Class instance fields and methods all live on the same shape: a
// field's name and a method's name MUST NOT share a short slot, or
// `instance.method()` resolves to a number / vice versa. The parser
// lowers class syntax to an IIFE-of-prototype-assignments form; we
// run `iife_class_lift_block` first so the AST is in the same
// `NativeClassStmt` shape the production pipeline feeds to the
// mangler.
test "mangle: shape-coloring keeps class fields and methods distinct" {
  let cfg = ManglerConfig::default()
    .with_mangle_properties(true)
    .with_mangle_properties_shape_color(true)
  let src =
    #|class Widget {
    #|  constructor() {
    #|    this.alphaCount = 1;
    #|    this.alphaCache = 2;
    #|  }
    #|  bump() { this.alphaCount = this.alphaCount + 1; return this.alphaCount - this.alphaCache; }
    #|}
    #|const w = new Widget();
    #|sink(w.bump());
  let block = try @parser.parse_block_from_source(src) catch {
    e => {
      fail("parse error: \{e}")
      return
    }
  } noraise {
    b => b
  }
  let lifted = iife_class_lift_block(block)
  let mangled = mangle_block(lifted, cfg)
  let e = Emitter::new()
  for s in mangled.stmts {
    emit_stmt(e, s)
    e.nl()
  }
  let js = e.to_string()
  assert_false(js.contains("alphaCount"))
  assert_false(js.contains("alphaCache"))
  assert_false(js.contains("bump"))
  let shorts : Map[String, Bool] = {}
  for c in "abcdefghijklmnopqrstuvwxyz" {
    let probe = "." + c.to_string()
    if js.contains(probe) {
      shorts[c.to_string()] = true
    }
  }
  // `.prototype` of any global pushes `.p` into shorts artificially;
  // strip it so the assertion measures the class clique itself.
  let _ = shorts.remove("p")
  assert_true(
    shorts.length() >= 3,
    msg="expected >= 3 short names, got \{shorts.length()} — js: \{js}",
  )
}

///|

///|
// Arrow functions capture `this` from the enclosing scope. A field
// that's only touched inside an arrow inside a class method is still
// part of the surrounding class's shape — skipping the arrow body
// would let shape-coloring collapse it onto a sibling field.
test "mangle: shape-coloring walks arrows for captured this" {
  let cfg = ManglerConfig::default()
    .with_mangle_properties(true)
    .with_mangle_properties_shape_color(true)
  let src =
    #|class Widget {
    #|  constructor() {
    #|    this.beta = 2;
    #|  }
    #|  init() { (() => { this.alpha = 1; })(); }
    #|}
    #|const w = new Widget();
    #|w.init();
    #|sink(w.beta);
  let block = try @parser.parse_block_from_source(src) catch {
    e => {
      fail("parse error: \{e}")
      return
    }
  } noraise {
    b => b
  }
  let lifted = iife_class_lift_block(block)
  let mangled = mangle_block(lifted, cfg)
  let e = Emitter::new()
  for s in mangled.stmts {
    emit_stmt(e, s)
    e.nl()
  }
  let js = e.to_string()
  assert_false(js.contains("alpha"))
  assert_false(js.contains("beta"))
  let shorts : Map[String, Bool] = {}
  for c in "abcdefghijklmnopqrstuvwxyz" {
    let probe = "." + c.to_string()
    if js.contains(probe) {
      shorts[c.to_string()] = true
    }
  }
  let _ = shorts.remove("p")
  // alpha (arrow-captured) + beta (direct) + init (method) must use
  // three distinct short names.
  assert_true(
    shorts.length() >= 3,
    msg="expected >= 3 short names, got \{shorts.length()} — js: \{js}",
  )
}

///|
test "mangle: shape-coloring catches Symbol PropReceiver conflicts" {
  let cfg = ManglerConfig::default()
    .with_mangle_properties(true)
    .with_mangle_properties_shape_color(true)
  let src =
    #|function go(o) { return sink(o.alpha, o.beta); }
  match mangle_to_js(src, cfg) {
    Ok(js) => {
      assert_false(js.contains("alpha"))
      assert_false(js.contains("beta"))
      // `alpha` and `beta` are on the same `o`; they must NOT
      // share a short name.
      let shorts : Map[String, Bool] = {}
      for c in "abcdefghijklmnopqrstuvwxyz" {
        let probe = "." + c.to_string()
        if js.contains(probe) {
          shorts[c.to_string()] = true
        }
      }
      assert_true(shorts.length() >= 2)
    }
    Err(e) => fail("\{e}")
  }
}

///|
test "mangle: opt-in property mangling renames non-reserved keys" {
  // With `with_mangle_properties(true)`, every property key that's
  // not in the reserved set gets renamed. Built-ins like `length` /
  // `toString` MUST stay; user-defined `userName` / `getValue` get
  // compressed.
  let cfg = ManglerConfig::default().with_mangle_properties(true)
  let src =
    #|function f(obj) {
    #|  obj.userName = "alice";
    #|  obj.userScore = 42;
    #|  return obj.userName.length + obj.getValue();
    #|}
  match mangle_to_js(src, cfg) {
    Ok(js) => {
      // Long property names should be gone.
      assert_false(js.contains("userName"))
      assert_false(js.contains("userScore"))
      assert_false(js.contains("getValue"))
      // But `length` is reserved (Array / String prototype) — it
      // stays put even when callers see it on a user object.
      assert_true(js.contains(".length"))
    }
    Err(e) => fail("\{e}")
  }
}

///|
test "mangle: object-literal keys get the same rename as the access" {
  // Both `{ userName: "x" }` and `obj.userName` use the same key
  // — the property mangler renames them in lockstep.
  let cfg = ManglerConfig::default().with_mangle_properties(true)
  let src =
    #|function make() {
    #|  return { userName: "alice", userScore: 42 };
    #|}
    #|function read(o) {
    #|  return o.userName;
    #|}
  match mangle_to_js(src, cfg) {
    Ok(js) => {
      // Find the rename of `userName` — it should appear identically
      // in the literal and the access.
      // The mapping is deterministic (sorted alphabetically), so
      // `userName` precedes `userScore`. Both get short names.
      assert_false(js.contains("userName"))
      assert_false(js.contains("userScore"))
      // Both should appear as `something:` in the object literal
      // and `.something` in the access — same key on each side.
      assert_true(js.contains(": \"alice\""))
    }
    Err(e) => fail("\{e}")
  }
}

///|
test "mangle: destructure shorthand `{ key }` expands to `{ mangled: key }`" {
  // Without explicit `as`, `const { userName } = obj` reads the
  // `userName` property and binds it locally as `userName`. After
  // mangling the property key, the JS must keep the original local
  // name to preserve any references.
  let cfg = ManglerConfig::default().with_mangle_properties(true)
  let src =
    #|function read(obj) {
    #|  const { userName } = obj;
    #|  return userName;
    #|}
  match mangle_to_js(src, cfg) {
    Ok(js) => {
      // No bare `{userName}` in the output — the key was renamed.
      assert_false(js.contains("{userName}"))
      assert_false(js.contains("{ userName }"))
      // But the local binding `userName` either keeps its name OR
      // gets a short rename (it's a function-local, so it gets
      // mangled too). The key:local separator `:` must appear.
      assert_true(js.contains(":"))
    }
    Err(e) => fail("\{e}")
  }
}

///|
test "mangle: built-in reserved properties stay (DOM / prototypes)" {
  // `addEventListener`, `length`, `then` are in the built-in
  // reserved set. Renaming them would break interop with the DOM
  // / Promises / arrays.
  let cfg = ManglerConfig::default().with_mangle_properties(true)
  let src =
    #|function setup(el) {
    #|  el.addEventListener("click", () => fetch("/").then(r => r.json()));
    #|  return el.children.length;
    #|}
  match mangle_to_js(src, cfg) {
    Ok(js) => {
      assert_true(js.contains(".addEventListener"))
      assert_true(js.contains(".then"))
      assert_true(js.contains(".length"))
      assert_true(js.contains(".children"))
      assert_true(js.contains(".json"))
    }
    Err(e) => fail("\{e}")
  }
}

///|
test "mangle: explicit reserved_properties extends the built-in list" {
  // The caller can add their own protected property names.
  let cfg = ManglerConfig::default()
    .with_mangle_properties(true)
    .with_reserved_properties(["userToken", "apiKey"])
  let src =
    #|function f(obj) {
    #|  obj.userToken = "abc";
    #|  obj.userScore = 100;
    #|  obj.apiKey = "key";
    #|  return obj.userToken + obj.apiKey;
    #|}
  match mangle_to_js(src, cfg) {
    Ok(js) => {
      assert_true(js.contains(".userToken"))
      assert_true(js.contains(".apiKey"))
      // Non-reserved `userScore` was mangled.
      assert_false(js.contains("userScore"))
    }
    Err(e) => fail("\{e}")
  }
}

///|
test "mangle: method calls follow the property rename" {
  // `obj.calculate(x)` is a MethodCall — the `calculate` method
  // name must rename in lockstep with any `obj.calculate` access.
  let cfg = ManglerConfig::default().with_mangle_properties(true)
  let src =
    #|function f(obj) {
    #|  return obj.calculate(1) + obj.calculate(2);
    #|}
  match mangle_to_js(src, cfg) {
    Ok(js) => {
      assert_false(js.contains("calculate"))
      // Both calls should still have the same renamed method.
      let mut occurrences = 0
      let mut from_idx = 0
      while from_idx < js.length() {
        let slice = js[from_idx:].to_owned()
        match slice.find(".") {
          Some(i) => {
            // Skip the `.` and look for `(` after a single char.
            if from_idx + i + 2 < js.length() &&
              js[from_idx + i + 2:from_idx + i + 3].to_owned() == "(" {
              occurrences = occurrences + 1
            }
            from_idx = from_idx + i + 1
          }
          None => break
        }
      }
      assert_true(occurrences >= 2)
    }
    Err(e) => fail("\{e}")
  }
}

///|

///|
test "mangle: block-scoped let in separate if arms can share short names" {
  // `firstName` lives only in the `then` branch; `lastName` lives only
  // in the `else` branch. With block-scope frames they should both
  // compress to the same short name (`a`) — the rename map is local
  // to each arm and the slot is reused once the arm exits.
  let cfg = ManglerConfig::default()
  let src =
    #|function pick(flag) {
    #|  if (flag) {
    #|    let firstName = "alice";
    #|    return firstName;
    #|  } else {
    #|    let lastName = "smith";
    #|    return lastName;
    #|  }
    #|}
  match mangle_to_js(src, cfg) {
    Ok(js) => {
      assert_false(js.contains("firstName"))
      assert_false(js.contains("lastName"))
      // The block frames are independent, so both arms collide on
      // the same short slot — count how many `let <single-letter>`
      // declarations end up with the same name across the two arms.
      let mut shared : String? = None
      for candidate in ["a", "b", "c"] {
        let needle = "let " + candidate + " ="
        let mut occurrences = 0
        let mut from_idx = 0
        while from_idx < js.length() {
          let slice = js[from_idx:].to_owned()
          match slice.find(needle) {
            Some(i) => {
              occurrences = occurrences + 1
              from_idx = from_idx + i + 1
            }
            None => break
          }
        }
        if occurrences >= 2 {
          shared = Some(candidate)
        }
      }
      match shared {
        Some(_) => ()
        None => fail("expected both if arms to reuse a short slot, got: \{js}")
      }
    }
    Err(e) => fail("\{e}")
  }
}

///|
test "mangle: var declared inside an if is hoisted to the function frame" {
  // `var counter` is function-scoped per JS spec — the reference
  // after the `if` must still resolve to the same renamed identifier.
  let cfg = ManglerConfig::default()
  let src =
    #|function run(flag) {
    #|  if (flag) {
    #|    var counter = 1;
    #|  }
    #|  return counter;
    #|}
  match mangle_to_js(src, cfg) {
    Ok(js) => {
      assert_false(js.contains("counter"))
      // The `var` declaration and the post-if `return` must end up
      // referring to the same renamed identifier. Look for both
      // `var <name>` and `return <name>` matching.
      let mut hoisted_to : String? = None
      for candidate in ["a", "b", "c", "d"] {
        if js.contains("var " + candidate + " =") &&
          js.contains("return " + candidate + ";") {
          hoisted_to = Some(candidate)
        }
      }
      match hoisted_to {
        Some(_) => ()
        None =>
          fail("expected var + return to share a renamed identifier in: \{js}")
      }
    }
    Err(e) => fail("\{e}")
  }
}

///|
test "mangle: nested while bodies open their own block frame" {
  // Two sibling `while` loops each introduce their own `let`. The
  // counter should reset between them so the second loop reuses the
  // first loop's short name.
  let cfg = ManglerConfig::default()
  let src =
    #|function loops() {
    #|  while (true) {
    #|    let cursor = 0;
    #|    cursor = cursor + 1;
    #|  }
    #|  while (true) {
    #|    let counter = 0;
    #|    counter = counter + 1;
    #|  }
    #|}
  match mangle_to_js(src, cfg) {
    Ok(js) => {
      assert_false(js.contains("cursor"))
      assert_false(js.contains("counter"))
      // Both inner `let` slots should land on the same short name
      // because the block frames are independent.
      let mut occurrences = 0
      let mut from_idx = 0
      while from_idx < js.length() {
        let slice = js[from_idx:].to_owned()
        match slice.find("let a") {
          Some(i) => {
            occurrences = occurrences + 1
            from_idx = from_idx + i + 1
          }
          None => break
        }
      }
      assert_true(occurrences >= 2)
    }
    Err(e) => fail("\{e}")
  }
}

///|
test "mangle: try / catch / finally each get an independent frame" {
  // Block-scoped `let` in `try`, the catch parameter, and a `let`
  // in `finally` should all be able to share the same short name —
  // their lifetimes don't overlap.
  let cfg = ManglerConfig::default()
  let src =
    #|function safe(work) {
    #|  try {
    #|    let attempt = work();
    #|    return attempt;
    #|  } catch (failure) {
    #|    return failure;
    #|  } finally {
    #|    let cleanup = 1;
    #|    return cleanup;
    #|  }
    #|}
  match mangle_to_js(src, cfg) {
    Ok(js) => {
      assert_false(js.contains("attempt"))
      assert_false(js.contains("failure"))
      assert_false(js.contains("cleanup"))
    }
    Err(e) => fail("\{e}")
  }
}

///|
test "mangle: bare block stmt opens its own frame" {
  // A `{ … }` block at function level is a lexical scope; the
  // `let` should not bleed into the surrounding function's frame.
  let cfg = ManglerConfig::default()
  let src =
    #|function nest() {
    #|  let outer = 1;
    #|  {
    #|    let middle = 2;
    #|    return outer + middle;
    #|  }
    #|}
  match mangle_to_js(src, cfg) {
    Ok(js) => {
      assert_false(js.contains("outer"))
      assert_false(js.contains("middle"))
    }
    Err(e) => fail("\{e}")
  }
}

///|
test "mangle: var inside nested blocks still hoists to the function" {
  // `var hoistMe` is wrapped in two nested blocks; the function-
  // level reference must still bind to the same rename.
  let cfg = ManglerConfig::default()
  let src =
    #|function f() {
    #|  while (true) {
    #|    if (true) {
    #|      var hoistMe = 1;
    #|    }
    #|  }
    #|  return hoistMe;
    #|}
  match mangle_to_js(src, cfg) {
    Ok(js) => {
      assert_false(js.contains("hoistMe"))
      // The `var` and the `return` must share a renamed identifier.
      let mut bound : String? = None
      for candidate in ["a", "b", "c", "d", "e"] {
        if js.contains("var " + candidate + " =") &&
          js.contains("return " + candidate + ";") {
          bound = Some(candidate)
        }
      }
      match bound {
        Some(_) => ()
        None => fail("expected var hoisting to bind across blocks in: \{js}")
      }
    }
    Err(e) => fail("\{e}")
  }
}

///|
test "mangle: PureCall wrapper does not hide identifier references" {
  // Regression: rename_expr must walk into `PureCall(inner)`,
  // otherwise references inside `/* @__PURE__ */ f(x)` keep the
  // original name while the binding gets renamed.
  let cfg = ManglerConfig::default().with_preserve_top_level(false)
  let src = "const original = (e) => e;\nconst wrapped = /* @__PURE__ */ original(123);"
  match mangle_to_js(src, cfg) {
    Ok(js) => {
      // Both binding and reference must rename together.
      assert_false(js.contains("original"))
      assert_false(js.contains("wrapped"))
    }
    Err(e) => fail("\{e}")
  }
}

///|
test "mangle: a pattern default's outer reference is reserved in the scope" {
  // Regression. `collect_var_refs_stmt` discarded the binding pattern,
  // so `fallback` was not counted as a free reference of `pick`'s body
  // and the parameter allocator handed `xs` the same short name:
  //
  //   function b(a) { const [b = a] = a; return b; }
  //
  // `a` now names the parameter, so the default resolves to the empty
  // array instead of 9 — a wrong answer, not a crash.
  let cfg = ManglerConfig::default().with_preserve_top_level(false)
  let src = "const fallback = 9;\nfunction pick(xs) { const [first = fallback] = xs; return first; }\nconsole.log(pick([]));"
  match mangle_to_js(src, cfg) {
    Ok(js) => {
      // Whatever the parameter is called, the default must not name it.
      assert_false(js.contains("[b = a] = a"))
      assert_false(js.contains("[a = a] = a"))
    }
    Err(e) => fail("\{e}")
  }
}

///|
test "mangle: a computed destructuring key is renamed with its binding" {
  // Regression. `rename_binding_decl` carried
  // `TsObjectBindingProp.key_expr` through verbatim, so the pattern
  // kept `{ [k]: v }` in a function whose `k` had been renamed —
  // `ReferenceError: k is not defined` under plain `--mangle`.
  let cfg = ManglerConfig::default().with_preserve_top_level(false)
  let src = "function pick(k) { const { [k]: v } = { a: 1 }; return v; }\nconsole.log(pick(\"a\"));"
  match mangle_to_js(src, cfg) {
    Ok(js) => {
      assert_false(js.contains("[k]"))
      assert_false(js.contains("k)"))
    }
    Err(e) => fail("\{e}")
  }
}

///|
test "mangle: name short-name generator avoids reserved single-letter clashes" {
  // The mangler should skip `a` if it conflicts. Force the issue
  // by reserving `a`.
  let cfg = ManglerConfig::default()
    .with_preserve_top_level(false)
    .with_reserved(["a"])
  let src = "const longOne = 1;\nconst longTwo = 2;"
  match mangle_to_js(src, cfg) {
    Ok(js) => {
      assert_false(js.contains("longOne"))
      assert_false(js.contains("longTwo"))
      // Reserved `a` is still untouched, but we shouldn't see two
      // `const a =` lines either.
      let mut count = 0
      let mut from_idx = 0
      while from_idx < js.length() {
        let slice = js[from_idx:].to_owned()
        match slice.find("const a =") {
          Some(i) => {
            count = count + 1
            from_idx = from_idx + i + 1
          }
          None => break
        }
      }
      @test.assert_eq(count, 0)
    }
    Err(e) => fail("\{e}")
  }
}

///|
test "mangle: NativeClassStmt method names are collected and shortened (#mangle_properties)" {
  // Method names that appear ONLY inside a NativeClassStmt (never in a
  // PropAccess outside the class) were previously missing from the
  // property-rename candidates, so `mangle_properties` left them intact.
  let src =
    #|class Counter {
    #|  constructor() { this.internalValue = 0; }
    #|  incrementCount() { this.internalValue += 1; }
    #|  getCount() { return this.internalValue; }
    #|}
    #|const c = new Counter();
    #|c.incrementCount();
    #|console.log(c.getCount());
  let cfg = ManglerConfig::default()
    .with_mangle_properties(true)
    .with_preserve_top_level(false)
  match mangle_to_js(src, cfg) {
    Ok(js) => {
      // Long method names must be gone after mangling.
      assert_false(js.contains("incrementCount"))
      assert_false(js.contains("internalValue"))
    }
    Err(e) => fail("\{e}")
  }
}

///|
test "mangle: a destructured parameter's default is reserved in its scope" {
  // Regression. `function_child` collected free variables from the BODY
  // only, so `fallback` — referenced from the parameter list — was not
  // reserved and the pattern's own binder took its letter:
  //
  //   function b({n: a = a}) { return a; }
  //
  // `ReferenceError: Cannot access 'a' before initialization`, under
  // plain `--mangle` with no property mangling involved.
  let cfg = ManglerConfig::default().with_preserve_top_level(false)
  let src = "const fallback = 9;\nfunction pick({ n = fallback }) { return n; }\nconsole.log(pick({}));"
  match mangle_to_js(src, cfg) {
    Ok(js) => {
      assert_false(js.contains("a = a"))
      assert_false(js.contains("b = b"))
    }
    Err(e) => fail("\{e}")
  }
}

///|
test "mangle: a catch pattern's default is reserved in its scope" {
  // Same gap on the other shape that writes a pattern outside a body:
  // `collect_var_refs_stmt`'s `Try` arm discarded the catch binding.
  let cfg = ManglerConfig::default().with_preserve_top_level(false)
  let src = "const label = \"fb\";\nfunction run() { try { throw {}; } catch ({ message = label }) { return message; } }\nconsole.log(run());"
  match mangle_to_js(src, cfg) {
    Ok(js) => {
      assert_false(js.contains("a = a"))
      assert_false(js.contains("b = b"))
    }
    Err(e) => fail("\{e}")
  }
}

///|
test "mangle: a multi-declarator group's names are pre-bound at the top level" {
  // `let a = 1, b = 2;` is a `Block` of `Let`s in this AST, not two
  // sibling statements. `rename_block_inline_in`'s prebind recursed into
  // that wrapper; `mangle_block_impl`'s top-level one did not — so the
  // group's names were invisible to a reference that PRECEDED the
  // declaration. That reference resolved to nothing and kept its
  // original spelling while the declaration was renamed underneath it,
  // which is a `ReferenceError` under plain `--mangle`.
  let cfg = ManglerConfig::default().with_preserve_top_level(false)
  let src = "function f(t) { return isArray(t); }\nlet isArray = Array.isArray, isMap = (t) => t instanceof Map;\nconsole.log(f([]), isMap(new Map()));"
  match mangle_to_js(src, cfg) {
    Ok(js) => {
      // Nothing may still be spelled `isArray` — neither the use nor
      // the declaration.
      assert_false(js.contains("isArray(") && js.contains("= Array.isArray"))
      assert_false(js.contains("isMap"))
    }
    Err(e) => fail("\{e}")
  }
}

///|
test "mangle: a real block of declarations still gets its own scope" {
  // The other half of the same predicate: a genuine `{ let x; let y; }`
  // has exactly the shape of a declarator group and must NOT be treated
  // as transparent, or the inner binders land in the enclosing scope and
  // the post-block references resolve to them.
  let cfg = ManglerConfig::default().with_preserve_top_level(false)
  let src = "let x = 1, y = 9;\n{ let x = 2; let y = 3; }\nconsole.log(x, y);"
  match mangle_to_js(src, cfg) {
    Ok(js) => {
      // Whatever the outer pair is named, the trailing `console.log`
      // must name the SAME two bindings as the first declaration — i.e.
      // the inner block introduced two fresh names.
      let first = js.contains("let a = 1, b = 9")
      assert_true(first)
      assert_true(js.contains("console.log(a, b)"))
    }
    Err(e) => fail("\{e}")
  }
}

///|
test "mangle: a destructuring declaration's names are pre-bound" {
  // The two prebind passes matched `Let(Ident(name), …)` only, so a
  // DESTRUCTURING declaration was invisible to them and a reference that
  // preceded it kept the old spelling while the declaration was renamed.
  // `useState` makes the shape ubiquitous: four of Excalidraw's
  // components hit it under plain `mtsc --mangle`.
  //
  // Same bug as the multi-declarator group, one binding form over.
  let cfg = ManglerConfig::default().with_preserve_top_level(false)
  let src = "function C() {\n  const bump = () => { setValue(1); };\n  const [value, setValue] = useState(0);\n  return value + (bump(), 0);\n}\nconsole.log(C());"
  match mangle_to_js(src, cfg) {
    Ok(js) => {
      // Nothing may still be spelled `setValue` — neither the use nor
      // the binder.
      assert_false(js.contains("setValue"), msg="got: \{js}")
      assert_false(js.contains("value"), msg="got: \{js}")
    }
    Err(e) => fail("\{e}")
  }
}

///|
test "mangle: an object-pattern declaration's names are pre-bound too" {
  let cfg = ManglerConfig::default().with_preserve_top_level(false)
  let src = "function C() {\n  const early = () => helper();\n  const { helper, ...restOfIt } = deps();\n  return early() + restOfIt;\n}\nconsole.log(C());"
  match mangle_to_js(src, cfg) {
    Ok(js) => {
      // The property KEY `helper:` stays — keys are only renamed under
      // `--mangle-properties`. What must be gone is the BINDING, and the
      // earlier `early` closure must call the renamed one.
      assert_false(js.contains("=> helper()"), msg="got: \{js}")
      assert_true(js.contains("helper: "), msg="the key should survive: \{js}")
      assert_false(js.contains("restOfIt"), msg="got: \{js}")
    }
    Err(e) => fail("\{e}")
  }
}
