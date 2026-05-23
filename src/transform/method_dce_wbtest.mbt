// Tests for class-method DCE.
//
// Each case feeds a TS source containing class declarations to the
// transform pipeline at the block level (no bundling), runs
// `drop_unused_methods_in_blocks` on the result, and verifies which
// method install sites survived.

///|
fn method_dce_to_js(src : String) -> Result[String, String] {
  let block = match (try? @parser.parse_block_from_source(src)) {
    Ok(b) => b
    Err(e) => return Err("parse error: \{e}")
  }
  let pruned = drop_unused_methods_in_blocks([block], [])[0]
  let e = Emitter::new()
  for s in pruned.stmts {
    emit_stmt(e, s)
    e.nl()
  }
  Ok(e.to_string())
}

///|
test "method-dce: unreferenced class method drops its install site" {
  // `unused` is declared but never called. `used` is called via
  // `c.used()` so its install must survive.
  let src =
    #|class C {
    #|  used() { return 1; }
    #|  unused() { return 2; }
    #|}
    #|const c = new C();
    #|console.log(c.used());
  match method_dce_to_js(src) {
    Ok(js) => {
      assert_true(js.contains("used"))
      assert_false(js.contains("unused"))
    }
    Err(e) => fail("\{e}")
  }
}

///|
test "method-dce: referenced method survives even via PropAccess only" {
  // The method is read but not called — that still counts as a
  // reference. A consumer might be storing the function reference.
  let src =
    #|class C {
    #|  callback() { return 1; }
    #|  dead() { return 2; }
    #|}
    #|const c = new C();
    #|const fn = c.callback;
    #|fn();
  match method_dce_to_js(src) {
    Ok(js) => {
      assert_true(js.contains("callback"))
      assert_false(js.contains("dead"))
    }
    Err(e) => fail("\{e}")
  }
}

///|
test "method-dce: string-index access counts as a reference" {
  // `obj["method"]` is an alternate spelling for `obj.method`. The
  // DCE must surface the string-literal key.
  let src =
    #|class C {
    #|  alive() { return 1; }
    #|  dead() { return 2; }
    #|}
    #|const c = new C();
    #|console.log(c["alive"]());
  match method_dce_to_js(src) {
    Ok(js) => {
      assert_true(js.contains("alive"))
      assert_false(js.contains("dead"))
    }
    Err(e) => fail("\{e}")
  }
}

///|
test "method-dce: static method DCE follows the same rule" {
  let src =
    #|class Math2 {
    #|  static keptStatic() { return 42; }
    #|  static droppedStatic() { return 0; }
    #|}
    #|console.log(Math2.keptStatic());
  match method_dce_to_js(src) {
    Ok(js) => {
      assert_true(js.contains("keptStatic"))
      assert_false(js.contains("droppedStatic"))
    }
    Err(e) => fail("\{e}")
  }
}

///|
test "method-dce: caller-supplied reserved list protects a name" {
  // Even when `init` isn't called anywhere in the source, the
  // extra-reserved list keeps it.
  let src =
    #|class C {
    #|  init() { return 1; }
    #|  reallyDead() { return 2; }
    #|}
  let block = match (try? @parser.parse_block_from_source(src)) {
    Ok(b) => b
    Err(e) => fail("parse error: \{e}")
  }
  let pruned = drop_unused_methods_in_blocks([block], ["init"])[0]
  let e = Emitter::new()
  for s in pruned.stmts {
    emit_stmt(e, s)
    e.nl()
  }
  let js = e.to_string()
  assert_true(js.contains("init"))
  assert_false(js.contains("reallyDead"))
}

///|
test "method-dce: object-literal method counts as a reference" {
  // `{ used: fn }` mentions `used` — every `@@define:used` install
  // anywhere in the bundle must therefore survive.
  let src =
    #|class C {
    #|  used() { return 1; }
    #|  dead() { return 2; }
    #|}
    #|const handlers = { used: () => 0 };
    #|console.log(handlers);
  match method_dce_to_js(src) {
    Ok(js) => {
      assert_true(js.contains("used"))
      assert_false(js.contains("dead"))
    }
    Err(e) => fail("\{e}")
  }
}

///|
test "method-dce: no calls anywhere drops every method" {
  let src =
    #|class C {
    #|  a() {}
    #|  b() {}
    #|  c() {}
    #|}
    #|const k = new C();
    #|console.log(k);
  match method_dce_to_js(src) {
    Ok(js) => {
      // The class binding itself is still emitted (it's a Let).
      // None of the method names should appear in the output.
      assert_false(js.contains(".a"))
      assert_false(js.contains(".b"))
      assert_false(js.contains(".c"))
    }
    Err(e) => fail("\{e}")
  }
}

///|
test "method-dce: cross-block bundle of two modules" {
  // The class lives in one block, the consumer in another. Both
  // get walked when building the global reference set, so the
  // call in module B keeps module A's method alive.
  let lib_src =
    #|class Service {
    #|  serveRequest() { return 1; }
    #|  internalShutdown() { return 0; }
    #|}
  let entry_src =
    #|const s = new Service();
    #|console.log(s.serveRequest());
  let lib_block = match (try? @parser.parse_block_from_source(lib_src)) {
    Ok(b) => b
    Err(e) => fail("parse error lib: \{e}")
  }
  let entry_block = match (try? @parser.parse_block_from_source(entry_src)) {
    Ok(b) => b
    Err(e) => fail("parse error entry: \{e}")
  }
  let pruned = drop_unused_methods_in_blocks(
    [lib_block, entry_block], [],
  )
  let e = Emitter::new()
  for s in pruned[0].stmts {
    emit_stmt(e, s)
    e.nl()
  }
  for s in pruned[1].stmts {
    emit_stmt(e, s)
    e.nl()
  }
  let js = e.to_string()
  assert_true(js.contains("serveRequest"))
  assert_false(js.contains("internalShutdown"))
}
