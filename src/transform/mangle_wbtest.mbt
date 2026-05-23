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

