// Tests for immutability analysis + inline expansion.

///|
fn analyze_one_src(src : String) -> ImmutabilityReport raise {
  let block = match (try? @parser.parse_block_from_source(src)) {
    Ok(b) => b
    Err(e) => fail("parse error: \{e}")
  }
  analyze_immutable_consts([block])
}

///|
fn inline_one_src(src : String) -> Result[String, String] {
  let block = match (try? @parser.parse_block_from_source(src)) {
    Ok(b) => b
    Err(e) => return Err("parse error: \{e}")
  }
  let report = analyze_immutable_consts([block])
  let inlined = inline_immutable_property_reads([block], report)[0]
  let e = Emitter::new()
  for s in inlined.stmts {
    emit_stmt(e, s)
    e.nl()
  }
  Ok(e.to_string())
}

///|
test "immutable: plain `const X = { … }` with read-only refs is immutable" {
  let src =
    #|const cfg = { mode: "prod", debug: false, version: 1 };
    #|console.log(cfg.mode, cfg.debug, cfg.version);
  let r = analyze_one_src(src)
  assert_true(r.is_immutable("cfg"))
  match r.lookup("cfg", "mode") {
    Some(StringLit(s)) => assert_eq(s, "prod")
    _ => fail("expected StringLit prod")
  }
  match r.lookup("cfg", "debug") {
    Some(BoolLit(b)) => assert_eq(b, false)
    _ => fail("expected BoolLit false")
  }
}

///|
test "immutable: write-through `cfg.X = …` disqualifies the binding" {
  let src =
    #|const cfg = { mode: "prod" };
    #|cfg.mode = "dev";
    #|console.log(cfg.mode);
  let r = analyze_one_src(src)
  assert_false(r.is_immutable("cfg"))
}

///|
test "immutable: passing `cfg` as a function arg disqualifies it" {
  // `Object.assign(cfg, …)` could mutate. So can `mutate(cfg)`.
  let src =
    #|const cfg = { mode: "prod" };
    #|console.log(cfg);
  let r = analyze_one_src(src)
  assert_false(r.is_immutable("cfg"))
}

///|
test "immutable: `cfg.method()` call disqualifies (might mutate)" {
  let src =
    #|const cfg = { mode: "prod" };
    #|cfg.toUpperCase();
  let r = analyze_one_src(src)
  assert_false(r.is_immutable("cfg"))
}

///|
test "immutable: nested-object property is omitted from the inline table" {
  // The outer object can still be immutable, but `cfg.nested` won't
  // be a candidate for inlining (the value isn't a primitive).
  let src =
    #|const cfg = { mode: "prod", nested: { foo: 1 } };
    #|console.log(cfg.mode);
  let r = analyze_one_src(src)
  assert_true(r.is_immutable("cfg"))
  assert_true(r.lookup("cfg", "mode") is Some(_))
  assert_true(r.lookup("cfg", "nested") is None)
}

///|
test "immutable inline: PropAccess gets replaced with the literal" {
  let src =
    #|const cfg = { mode: "prod" };
    #|console.log(cfg.mode);
  match inline_one_src(src) {
    Ok(js) => {
      // The string literal substituted for `cfg.mode`.
      assert_true(js.contains("\"prod\""))
      // The original access form is gone from the call.
      assert_false(js.contains("cfg.mode"))
    }
    Err(e) => fail("\{e}")
  }
}

///|
test "immutable inline: bracket access with string lit also inlines" {
  let src =
    #|const cfg = { count: 42 };
    #|console.log(cfg["count"]);
  match inline_one_src(src) {
    Ok(js) => {
      assert_true(js.contains("42"))
      assert_false(js.contains("cfg[\"count\"]"))
    }
    Err(e) => fail("\{e}")
  }
}

///|
test "immutable inline: BinOp arms get rewritten in place" {
  // After inline, the `===` comparison is between two literals —
  // a follow-up const folder could simplify it, but the inlining
  // step alone is what we're validating here.
  let src =
    #|const cfg = { mode: "prod" };
    #|if (cfg.mode === "dev") {
    #|  console.log("dev branch");
    #|}
  match inline_one_src(src) {
    Ok(js) => {
      assert_true(js.contains("\"prod\" === \"dev\""))
      assert_false(js.contains("cfg.mode === \"dev\""))
    }
    Err(e) => fail("\{e}")
  }
}

///|
test "immutable inline: disqualified binding is left untouched" {
  let src =
    #|const cfg = { mode: "prod" };
    #|cfg.mode = "dev";
    #|console.log(cfg.mode);
  match inline_one_src(src) {
    Ok(js) => {
      // `cfg.mode` appears on both the access and the (still-present)
      // PropAssign — nothing got substituted.
      assert_true(js.contains("cfg.mode"))
    }
    Err(e) => fail("\{e}")
  }
}

///|
test "immutable analysis: ignores duplicate-named decls" {
  // Two `const cfg` at the same level — the analysis bails on `cfg`.
  let src =
    #|const cfg = { mode: "prod" };
    #|console.log(cfg.mode);
    #|const cfg = { mode: "dev" };
    #|console.log(cfg.mode);
  let r = analyze_one_src(src)
  assert_false(r.is_immutable("cfg"))
}

///|
test "immutable cleanup: inlined-then-orphaned const decl is dropped" {
  // After inline, `cfg` has no remaining references. The cleanup
  // pass drops the source decl too — final output should have
  // neither `cfg` nor `cfg.mode` in it.
  let src =
    #|const cfg = { mode: "prod" };
    #|console.log(cfg.mode);
  let block = match (try? @parser.parse_block_from_source(src)) {
    Ok(b) => b
    Err(e) => fail("parse: \{e}")
  }
  let blocks = [block]
  let report = analyze_immutable_consts(blocks)
  let inlined = inline_immutable_property_reads(blocks, report)
  let final = drop_orphan_immutable_decls(inlined, report)
  let e = Emitter::new()
  for b in final {
    for s in b.stmts {
      emit_stmt(e, s)
      e.nl()
    }
  }
  let js = e.to_string()
  assert_true(js.contains("\"prod\""))
  assert_false(js.contains("const cfg"))
}

///|
test "immutable cleanup: const with surviving references is NOT dropped" {
  // After inline, only the *primitive* properties got substituted.
  // `cfg.nested` (a nested object) wasn't inlinable, so `cfg` is
  // still referenced and must survive.
  let src =
    #|const cfg = { mode: "prod", nested: { x: 1 } };
    #|console.log(cfg.mode, cfg.nested);
  let block = match (try? @parser.parse_block_from_source(src)) {
    Ok(b) => b
    Err(e) => fail("parse: \{e}")
  }
  let blocks = [block]
  let report = analyze_immutable_consts(blocks)
  let inlined = inline_immutable_property_reads(blocks, report)
  let final = drop_orphan_immutable_decls(inlined, report)
  let e = Emitter::new()
  for b in final {
    for s in b.stmts {
      emit_stmt(e, s)
      e.nl()
    }
  }
  let js = e.to_string()
  assert_true(js.contains("\"prod\""))
  assert_true(js.contains("const cfg"))
  assert_true(js.contains("cfg.nested"))
}

///|
test "immutable inline: cross-block analysis ties modules together" {
  // The `cfg` binding lives in one block, the read in another. Both
  // blocks need to be in scope of `analyze_immutable_consts` for
  // the substitution to fire.
  let lib_src =
    #|const cfg = { mode: "prod", port: 8080 };
  let entry_src =
    #|console.log(cfg.mode, cfg.port);
  let lib_block = match (try? @parser.parse_block_from_source(lib_src)) {
    Ok(b) => b
    Err(e) => fail("parse: \{e}")
  }
  let entry_block = match (try? @parser.parse_block_from_source(entry_src)) {
    Ok(b) => b
    Err(e) => fail("parse: \{e}")
  }
  let blocks = [lib_block, entry_block]
  let report = analyze_immutable_consts(blocks)
  assert_true(report.is_immutable("cfg"))
  let inlined = inline_immutable_property_reads(blocks, report)
  let e = Emitter::new()
  for b in inlined {
    for s in b.stmts {
      emit_stmt(e, s)
      e.nl()
    }
  }
  let js = e.to_string()
  assert_true(js.contains("\"prod\""))
  assert_true(js.contains("8080"))
}
