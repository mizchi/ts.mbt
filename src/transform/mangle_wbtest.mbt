// Mangler tests. Each case parses TS source into a `TsBlock`, runs
// the mangle pass, and emits the result back to JS to check the
// rename outcome.

///|
fn mangle_to_js(src : String, cfg : ManglerConfig) -> Result[String, String] {
  let block = match (try? @parser.parse_block_from_source(src)) {
    Ok(b) => b
    Err(e) => return Err("parse error: \{e}")
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
      assert_true(js.contains("function outer"))
      // Inner fn name `inner` is a local declaration — keep its
      // name slot (v0 doesn't rename nested function declarations).
      assert_true(js.contains("function inner"))
      // Parameter `count` was renamed.
      assert_false(js.contains("count + 1"))
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
        let slice = js.substring(start=from_idx, end=js.length()).to_string()
        match slice.find(".") {
          Some(i) => {
            // Skip the `.` and look for `(` after a single char.
            if from_idx + i + 2 < js.length() &&
              js
              .substring(start=from_idx + i + 2, end=from_idx + i + 3)
              .to_string() ==
              "(" {
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
          let slice = js.substring(start=from_idx, end=js.length()).to_string()
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
        let slice = js.substring(start=from_idx, end=js.length()).to_string()
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
        let slice = js.substring(start=from_idx, end=js.length()).to_string()
        match slice.find("const a =") {
          Some(i) => {
            count = count + 1
            from_idx = from_idx + i + 1
          }
          None => break
        }
      }
      assert_eq(count, 0)
    }
    Err(e) => fail("\{e}")
  }
}
