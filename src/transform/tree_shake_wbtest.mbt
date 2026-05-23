// Tests for the dead-declaration elimination pass.
//
// Each case parses a TS snippet into a runtime statement block, runs
// `tree_shake_block` with a hand-picked root set, and emits the
// survivors back to JS to verify what got dropped.

///|
fn tree_shake_to_js(
  src : String,
  roots : Array[String],
) -> Result[String, String] {
  let block = match (try? @parser.parse_block_from_source(src)) {
    Ok(b) => b
    Err(e) => return Err("parse error: \{e}")
  }
  let pruned = tree_shake_block(block, roots)
  let e = Emitter::new()
  for s in pruned.stmts {
    emit_stmt(e, s)
    e.nl()
  }
  Ok(e.to_string())
}

///|
test "tree-shake: dead decl with no consumer gets dropped" {
  let src =
    #|const used = 1;
    #|const dead = 2;
    #|console.log(used);
  match tree_shake_to_js(src, ["used"]) {
    Ok(js) => {
      assert_true(js.contains("const used"))
      assert_false(js.contains("const dead"))
      assert_true(js.contains("console.log(used)"))
    }
    Err(e) => fail("\{e}")
  }
}

///|
test "tree-shake: transitively referenced decl is kept" {
  // `helper` is not in roots, but `entry` (a root) references it.
  let src =
    #|const helper = 1;
    #|const entry = helper + 2;
    #|const noise = 99;
  match tree_shake_to_js(src, ["entry"]) {
    Ok(js) => {
      assert_true(js.contains("const helper"))
      assert_true(js.contains("const entry"))
      assert_false(js.contains("const noise"))
    }
    Err(e) => fail("\{e}")
  }
}

///|
test "tree-shake: side-effect stmts are always retained" {
  // Top-level `console.log(...)` is not a binding declaration, so the
  // pass can't tell if it's safe to drop. It stays.
  let src =
    #|console.log("hello");
    #|const dead = 1;
  match tree_shake_to_js(src, []) {
    Ok(js) => {
      assert_true(js.contains("console.log(\"hello\")"))
      assert_false(js.contains("const dead"))
    }
    Err(e) => fail("\{e}")
  }
}

///|
test "tree-shake: cycle between two live names keeps both" {
  // `a` references `b` and vice versa. Only `a` is a root — `b` rides
  // along because `a` keeps it live, which keeps `a` live, etc.
  let src =
    #|function a() { return b(); }
    #|function b() { return a(); }
    #|function unused() { return 42; }
  match tree_shake_to_js(src, ["a"]) {
    Ok(js) => {
      assert_true(js.contains("function a"))
      assert_true(js.contains("function b"))
      assert_false(js.contains("function unused"))
    }
    Err(e) => fail("\{e}")
  }
}

///|
test "tree-shake: refs from a side-effect stmt mark decls live" {
  // The top-level `format(x)` call is a keeper. It mentions `format`
  // and `x` — both must survive.
  let src =
    #|const x = 1;
    #|function format(n) { return String(n); }
    #|const dead = 99;
    #|format(x);
  match tree_shake_to_js(src, []) {
    Ok(js) => {
      assert_true(js.contains("const x"))
      assert_true(js.contains("function format"))
      assert_false(js.contains("const dead"))
      assert_true(js.contains("format(x)"))
    }
    Err(e) => fail("\{e}")
  }
}

///|
test "tree-shake: empty root set + no side effects empties the block" {
  let src =
    #|const a = 1;
    #|const b = 2;
    #|function c() { return a + b; }
  match tree_shake_to_js(src, []) {
    Ok(js) => {
      assert_false(js.contains("const a"))
      assert_false(js.contains("const b"))
      assert_false(js.contains("function c"))
    }
    Err(e) => fail("\{e}")
  }
}

///|
test "tree-shake: arrow-function root reaches nested references" {
  // The arrow body references `helper` — must be kept even though
  // `helper` is a separate top-level binding.
  let src =
    #|const helper = (n) => n * 2;
    #|const compute = (x) => helper(x) + 1;
    #|const orphan = 0;
  match tree_shake_to_js(src, ["compute"]) {
    Ok(js) => {
      assert_true(js.contains("const compute"))
      assert_true(js.contains("const helper"))
      assert_false(js.contains("const orphan"))
    }
    Err(e) => fail("\{e}")
  }
}

///|
test "tree-shake: destructuring pattern decl is kept (can't safely drop)" {
  // `const { x } = obj;` doesn't bind a single Ident — the pass
  // preserves it conservatively even when nothing references `x`.
  let src =
    #|const obj = { x: 1, y: 2 };
    #|const { x } = obj;
  match tree_shake_to_js(src, ["obj"]) {
    Ok(js) => {
      assert_true(js.contains("const obj"))
      // Pattern decl is in the "always-kept" bucket.
      assert_true(js.contains("{") && js.contains("} ="))
    }
    Err(e) => fail("\{e}")
  }
}
