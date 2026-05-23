// Tests for constant folding + dead-branch elimination.

///|
fn fold_to_js(src : String) -> Result[String, String] {
  let block = match (try? @parser.parse_block_from_source(src)) {
    Ok(b) => b
    Err(e) => return Err("parse error: \{e}")
  }
  let folded = fold_constants_in_block(block)
  let e = Emitter::new()
  for s in folded.stmts {
    emit_stmt(e, s)
    e.nl()
  }
  Ok(e.to_string())
}

///|
test "fold: numeric arithmetic on literals" {
  match fold_to_js("const a = 1 + 2;\nconst b = 3 * 4;\nconst c = 10 - 7;") {
    Ok(js) => {
      assert_true(js.contains("const a = 3"))
      assert_true(js.contains("const b = 12"))
      assert_true(js.contains("const c = 3"))
    }
    Err(e) => fail("\{e}")
  }
}

///|
test "fold: string concat with `+`" {
  match fold_to_js("const s = \"hello, \" + \"world\";") {
    Ok(js) => assert_true(js.contains("\"hello, world\""))
    Err(e) => fail("\{e}")
  }
}

///|
test "fold: mixed string + number" {
  match fold_to_js("const s = \"v\" + 1;") {
    Ok(js) => assert_true(js.contains("\"v1\""))
    Err(e) => fail("\{e}")
  }
}

///|
test "fold: strict equality on same-typed literals" {
  match fold_to_js("const a = \"prod\" === \"dev\";\nconst b = 1 === 1;") {
    Ok(js) => {
      assert_true(js.contains("const a = false"))
      assert_true(js.contains("const b = true"))
    }
    Err(e) => fail("\{e}")
  }
}

///|
test "fold: strict equality across different primitive types -> false" {
  match fold_to_js("const a = 1 === \"1\";\nconst b = true === 1;") {
    Ok(js) => {
      assert_true(js.contains("const a = false"))
      assert_true(js.contains("const b = false"))
    }
    Err(e) => fail("\{e}")
  }
}

///|
test "fold: numeric comparison" {
  match fold_to_js("const a = 1 < 2;\nconst b = 5 < 1;\nconst c = 3 >= 3;") {
    Ok(js) => {
      assert_true(js.contains("const a = true"))
      assert_true(js.contains("const b = false"))
      assert_true(js.contains("const c = true"))
    }
    Err(e) => fail("\{e}")
  }
}

///|
test "fold: `!` on a literal" {
  match fold_to_js("const a = !true;\nconst b = !0;\nconst c = !\"\";") {
    Ok(js) => {
      assert_true(js.contains("const a = false"))
      assert_true(js.contains("const b = true"))
      assert_true(js.contains("const c = true"))
    }
    Err(e) => fail("\{e}")
  }
}

///|
test "fold: `typeof` on literals" {
  match fold_to_js("const a = typeof 1;\nconst b = typeof \"x\";\nconst c = typeof true;") {
    Ok(js) => {
      assert_true(js.contains("const a = \"number\""))
      assert_true(js.contains("const b = \"string\""))
      assert_true(js.contains("const c = \"boolean\""))
    }
    Err(e) => fail("\{e}")
  }
}

///|
test "fold: short-circuit `&&` collapses on falsy LHS" {
  match fold_to_js("const a = false && expensive();\nconst b = true && 1;") {
    Ok(js) => {
      assert_true(js.contains("const a = false"))
      assert_true(js.contains("const b = 1"))
      // `expensive()` must NOT survive — the && short-circuited.
      assert_false(js.contains("expensive"))
    }
    Err(e) => fail("\{e}")
  }
}

///|
test "fold: short-circuit `||` collapses on truthy LHS" {
  match fold_to_js("const a = \"x\" || expensive();\nconst b = false || 5;") {
    Ok(js) => {
      assert_true(js.contains("const a = \"x\""))
      assert_true(js.contains("const b = 5"))
      assert_false(js.contains("expensive"))
    }
    Err(e) => fail("\{e}")
  }
}

///|
test "fold: nullish coalescing `??` on null LHS" {
  match fold_to_js("const a = null ?? \"default\";\nconst b = 0 ?? 999;") {
    Ok(js) => {
      assert_true(js.contains("const a = \"default\""))
      // `0 ?? x` is `0` — only `null`/`undefined` trigger fallback.
      assert_true(js.contains("const b = 0"))
    }
    Err(e) => fail("\{e}")
  }
}

///|
test "fold: ternary `cond ? a : b` with literal cond" {
  match fold_to_js("const a = true ? 1 : 2;\nconst b = 0 ? \"yes\" : \"no\";") {
    Ok(js) => {
      assert_true(js.contains("const a = 1"))
      assert_true(js.contains("const b = \"no\""))
    }
    Err(e) => fail("\{e}")
  }
}

///|
test "fold: `if (false)` drops the then-branch" {
  match fold_to_js("if (false) {\n  console.log(\"dead\");\n}\nconsole.log(\"alive\");") {
    Ok(js) => {
      assert_false(js.contains("dead"))
      assert_true(js.contains("alive"))
    }
    Err(e) => fail("\{e}")
  }
}

///|
test "fold: `if (true)` keeps the then-branch, drops else" {
  match fold_to_js("if (true) {\n  console.log(\"alive\");\n} else {\n  console.log(\"dead\");\n}") {
    Ok(js) => {
      assert_true(js.contains("alive"))
      assert_false(js.contains("dead"))
    }
    Err(e) => fail("\{e}")
  }
}

///|
test "fold: `if (false)` with else keeps the else-branch" {
  match fold_to_js("if (false) {\n  console.log(\"dead\");\n} else {\n  console.log(\"alive\");\n}") {
    Ok(js) => {
      assert_false(js.contains("dead"))
      assert_true(js.contains("alive"))
    }
    Err(e) => fail("\{e}")
  }
}

///|
test "fold: `while (false)` is dropped entirely" {
  match fold_to_js("while (false) {\n  console.log(\"loop\");\n}\nconsole.log(\"after\");") {
    Ok(js) => {
      assert_false(js.contains("\"loop\""))
      assert_true(js.contains("\"after\""))
    }
    Err(e) => fail("\{e}")
  }
}

///|
test "fold: template literal with all-literal interpolations collapses" {
  match fold_to_js("const s = `v=${1 + 2} mode=${\"prod\"}`;") {
    Ok(js) => assert_true(js.contains("\"v=3 mode=prod\""))
    Err(e) => fail("\{e}")
  }
}

///|
test "fold: paired with inline (the actual use case)" {
  // The expected pipeline for the immutable-inline use case:
  //   const cfg = { mode: "prod" };
  //   if (cfg.mode === "dev") expensive();
  // -> inline: `if ("prod" === "dev") expensive();`
  // -> fold:   `if (false) …` -> empty
  let src =
    #|const cfg = { mode: "prod" };
    #|if (cfg.mode === "dev") {
    #|  expensive();
    #|}
    #|console.log("done");
  let block = match (try? @parser.parse_block_from_source(src)) {
    Ok(b) => b
    Err(e) => fail("parse: \{e}")
  }
  let report = analyze_immutable_consts([block])
  let inlined = inline_immutable_property_reads([block], report)
  let cleaned = drop_orphan_immutable_decls(inlined, report)
  let folded = fold_constants_in_blocks(cleaned)
  let e = Emitter::new()
  for b in folded {
    for s in b.stmts {
      emit_stmt(e, s)
      e.nl()
    }
  }
  let js = e.to_string()
  // The dead `expensive()` call is gone.
  assert_false(js.contains("expensive"))
  // The const decl was orphaned and removed.
  assert_false(js.contains("const cfg"))
  // The live call survives.
  assert_true(js.contains("\"done\""))
}
