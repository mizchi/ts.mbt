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
test "immutable: nested-object property stays in the table for drilling" {
  // The outer object is immutable. `cfg.nested` is now recorded
  // on the report so multi-level access (`cfg.nested.foo`) can
  // resolve through it; the inline pass guards on
  // `is_simple_literal` when deciding whether to substitute.
  let src =
    #|const cfg = { mode: "prod", nested: { foo: 1 } };
    #|console.log(cfg.mode);
  let r = analyze_one_src(src)
  assert_true(r.is_immutable("cfg"))
  assert_true(r.lookup("cfg", "mode") is Some(_))
  assert_true(r.lookup("cfg", "nested") is Some(_))
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
test "as-const: array literal under `as const` becomes immutable" {
  // The parser strips `as const`, so the AST shape is just a plain
  // `const TAGS = ArrayLit([...])` — same as the bare form. The
  // analyzer picks both up.
  let src =
    #|const TAGS = ["alpha", "beta", "gamma"] as const;
    #|console.log(TAGS[0], TAGS[2]);
  match inline_one_src(src) {
    Ok(js) => {
      assert_true(js.contains("\"alpha\""))
      assert_true(js.contains("\"gamma\""))
      // The original index accesses must be gone.
      assert_false(js.contains("TAGS[0]"))
      assert_false(js.contains("TAGS[2]"))
    }
    Err(e) => fail("\{e}")
  }
}

///|
test "as-const: array `.length` is foldable" {
  // `length` was synthesized into the report at array length.
  let src =
    #|const TAGS = ["a", "b", "c", "d"];
    #|console.log(TAGS.length);
  match inline_one_src(src) {
    Ok(js) => {
      assert_true(js.contains("4"))
      assert_false(js.contains("TAGS.length"))
    }
    Err(e) => fail("\{e}")
  }
}

///|
test "as-const: out-of-bounds index leaves the access alone" {
  // No entry for `"10"` in the report — fall back to original AST.
  let src =
    #|const TAGS = ["a"];
    #|console.log(TAGS[10]);
  match inline_one_src(src) {
    Ok(js) => assert_true(js.contains("TAGS[10]"))
    Err(e) => fail("\{e}")
  }
}

///|
test "as-const: write through `TAGS[0] = …` disqualifies" {
  let src =
    #|const TAGS = ["a", "b"];
    #|TAGS[0] = "z";
    #|console.log(TAGS[0]);
  let r = analyze_one_src(src)
  assert_false(r.is_immutable("TAGS"))
}

///|
test "as-const: array with non-literal elements is partially inlineable" {
  // `TAGS[0]` is a function call, so it's not a simple-literal value
  // → omitted from the inline table. `TAGS[1]` is "b" and gets inlined.
  // The const itself stays alive because `TAGS[0]` still references it.
  let src =
    #|const TAGS = [load(), "b"];
    #|console.log(TAGS[0], TAGS[1]);
  match inline_one_src(src) {
    Ok(js) => {
      // "b" got inlined.
      assert_true(js.contains("\"b\""))
      // `TAGS[0]` survives because the value isn't a primitive.
      assert_true(js.contains("TAGS[0]"))
    }
    Err(e) => fail("\{e}")
  }
}

///|
test "function-local: const inside an arrow body gets analyzed and inlined" {
  // `mode` is local to `pick`, never escapes, only read via property.
  // The inline pass substitutes "prod" into the return expr.
  let src =
    #|const pick = () => {
    #|  const cfg = { mode: "prod" };
    #|  return cfg.mode;
    #|};
    #|console.log(pick());
  match inline_one_src(src) {
    Ok(js) => {
      // `"prod"` appears in the inlined return — the const itself
      // may stay because the orphan-cleanup only runs top-level.
      assert_true(js.contains("\"prod\""))
      assert_false(js.contains("cfg.mode"))
    }
    Err(e) => fail("\{e}")
  }
}

///|
test "function-local: const inside a function declaration body" {
  let src =
    #|function compute() {
    #|  const limits = { min: 1, max: 100 };
    #|  if (limits.max > limits.min) {
    #|    return limits.max;
    #|  }
    #|  return limits.min;
    #|}
    #|console.log(compute());
  match inline_one_src(src) {
    Ok(js) => {
      // All three `limits.X` accesses substituted with their literal.
      assert_false(js.contains("limits.max"))
      assert_false(js.contains("limits.min"))
      // The literal values appear in the body.
      assert_true(js.contains("100"))
      assert_true(js.contains("1"))
    }
    Err(e) => fail("\{e}")
  }
}

///|
test "nested const inline: `cfg.db.host` resolves through two layers" {
  let src =
    #|const cfg = { db: { host: "localhost", port: 5432 } };
    #|console.log(cfg.db.host, cfg.db.port);
  match inline_one_src(src) {
    Ok(js) => {
      assert_true(js.contains("\"localhost\""))
      assert_true(js.contains("5432"))
      // Both nested accesses must be gone.
      assert_false(js.contains("cfg.db.host"))
      assert_false(js.contains("cfg.db.port"))
    }
    Err(e) => fail("\{e}")
  }
}

///|
test "nested const inline: array inside object — `cfg.tags[1]`" {
  let src =
    #|const cfg = { tags: ["alpha", "beta", "gamma"] };
    #|console.log(cfg.tags[1]);
  match inline_one_src(src) {
    Ok(js) => {
      assert_true(js.contains("\"beta\""))
      assert_false(js.contains("cfg.tags["))
    }
    Err(e) => fail("\{e}")
  }
}

///|
test "nested const inline: `cfg.tags.length` resolves" {
  let src =
    #|const cfg = { tags: ["a", "b", "c", "d"] };
    #|console.log(cfg.tags.length);
  match inline_one_src(src) {
    Ok(js) => {
      assert_true(js.contains("4"))
      assert_false(js.contains("cfg.tags.length"))
    }
    Err(e) => fail("\{e}")
  }
}

///|
test "fixpoint: nested const + branch elim resolves multi-step" {
  // After one inline round, the comparison still has the runtime
  // `cfg.mode === "dev"`. After fold, the if collapses. After a
  // second inline round (now via the bundle fixed-point loop) the
  // nested `outer.inner.value` resolves all the way to the literal,
  // and a follow-up fold uses that literal in the branch test.
  let files : Map[String, String] = {}
  files["entry.ts"] =
    #|const outer = { inner: { value: 42 } };
    #|const cfg = { mode: "prod" };
    #|if (cfg.mode === "dev") {
    #|  console.log("dev");
    #|} else {
    #|  console.log(outer.inner.value);
    #|}
    #|
  match
    bundle_modules(files, "entry.ts", {
      ..BundleOptions::default(),
      tree_shake: true,
      inline_immutable: true,
      fold_constants: true,
    }) {
    Ok(out) => {
      // `cfg.mode === "dev"` folded to `false` → if collapsed →
      // else branch survives → `outer.inner.value` resolved to `42`.
      assert_true(out.js.contains("42"))
      // The dev branch is dropped entirely.
      assert_false(out.js.contains("\"dev\""))
      // Source consts are orphan-cleaned.
      assert_false(out.js.contains("const cfg"))
      assert_false(out.js.contains("const outer"))
    }
    Err(e) => fail("bundle: \{e}")
  }
}

///|
test "readonly: passing const to `ReadonlyArray<T>` param doesn't disqualify" {
  // Without the signature, passing `TAGS` to `consume` would
  // disqualify it (escape). With the `ReadonlyArray<T>` annotation
  // the analyzer trusts the function's promise.
  let src =
    #|const TAGS = ["alpha", "beta"] as const;
    #|function consume(items: ReadonlyArray<string>): number { return items.length; }
    #|consume(TAGS);
    #|console.log(TAGS[0]);
  let parser = @parser.Parser::from_source(src)
  let block = match (try? parser.parse_module_block()) {
    Ok(mb) => mb.block
    Err(e) => fail("parse block: \{e}")
  }
  let parser2 = @parser.Parser::from_source(src)
  let module_ = match (try? parser2.parse_module()) {
    Ok(m) => m
    Err(e) => fail("parse module: \{e}")
  }
  // Without sigs: TAGS gets disqualified because of the `consume(TAGS)` call.
  let r_no_sigs = analyze_immutable_consts([block])
  assert_false(r_no_sigs.is_immutable("TAGS"))
  // With sigs: the analyzer reads `consume`'s `ReadonlyArray<string>`
  // annotation and trusts it.
  let r_with_sigs = analyze_immutable_consts_with_sigs([block], module_.funcs)
  assert_true(r_with_sigs.is_immutable("TAGS"))
}

///|
test "readonly: `Readonly<T>` parameter type relaxes the disqualification too" {
  let src =
    #|const cfg = { mode: "prod" };
    #|function readCfg(c: Readonly<{ mode: string }>): string { return c.mode; }
    #|readCfg(cfg);
  let parser = @parser.Parser::from_source(src)
  let block = match (try? parser.parse_module_block()) {
    Ok(mb) => mb.block
    Err(e) => fail("parse: \{e}")
  }
  let parser2 = @parser.Parser::from_source(src)
  let module_ = match (try? parser2.parse_module()) {
    Ok(m) => m
    Err(e) => fail("parse: \{e}")
  }
  let r = analyze_immutable_consts_with_sigs([block], module_.funcs)
  assert_true(r.is_immutable("cfg"))
}

///|
test "readonly: a non-readonly param still disqualifies" {
  // Sanity: when the param has no readonly annotation, the const
  // is still disqualified — we can't trust the function not to
  // mutate.
  let src =
    #|const TAGS = ["a", "b"];
    #|function consume(items: Array<string>): number { return items.length; }
    #|consume(TAGS);
  let parser = @parser.Parser::from_source(src)
  let block = match (try? parser.parse_module_block()) {
    Ok(mb) => mb.block
    Err(e) => fail("parse: \{e}")
  }
  let parser2 = @parser.Parser::from_source(src)
  let module_ = match (try? parser2.parse_module()) {
    Ok(m) => m
    Err(e) => fail("parse: \{e}")
  }
  let r = analyze_immutable_consts_with_sigs([block], module_.funcs)
  assert_false(r.is_immutable("TAGS"))
}

///|
test "as-const: marker survives parse round-trip" {
  // Sanity check that the parser produces `As(_, ConstAssertion)`
  // and the peel helper unwraps it.
  let src = "const cfg = { mode: \"prod\" } as const;\n"
  let block = match (try? @parser.parse_block_from_source(src)) {
    Ok(b) => b
    Err(e) => fail("parse: \{e}")
  }
  match block.stmts[0] {
    Const(_, _, init) =>
      match init {
        As(inner, @ast.TsType::ConstAssertion) =>
          match inner {
            ObjectLit(_) => ()
            _ => fail("expected ObjectLit inner")
          }
        _ => fail("expected As(..., ConstAssertion) wrapping")
      }
    _ => fail("expected Const stmt")
  }
}

///|
test "as-const: full pipeline drops orphan array decl too" {
  let src =
    #|const ENV = ["production", "default"] as const;
    #|if (ENV[0] === "development") {
    #|  expensive();
    #|}
    #|console.log("done", ENV[1]);
  let block = match (try? @parser.parse_block_from_source(src)) {
    Ok(b) => b
    Err(e) => fail("parse: \{e}")
  }
  let report = analyze_immutable_consts([block])
  assert_true(report.is_immutable("ENV"))
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
  assert_false(js.contains("expensive"))
  assert_false(js.contains("const ENV"))
  assert_true(js.contains("\"default\""))
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
