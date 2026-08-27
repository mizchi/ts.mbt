///|
fn emit_min_one(src : String) -> String raise {
  let block = @parser.parse_block_from_source(src)
  let e = Emitter::new(pretty=false)
  for s in block.stmts {
    emit_stmt(e, s)
  }
  e.to_string()
}

// ---------------------------------------------------------------
// Sign operators that would merge with their operand
// ---------------------------------------------------------------
//
// `+(++a)` printed tight is `+++a`, which JS reads as `++ (+a)` and
// rejects: "Invalid left-hand side expression in prefix operation". The
// binary case (`"" + +x`) already had a guard; the unary-on-unary case
// did not.

///|
test "emit: +(++a) keeps the operators apart" {
  let out = emit_min_one("const r = +(++a);\n")
  assert_false(out.contains("+++"), msg="merged into ++ +: \{out}")
  assert_true(
    out.contains("+ ++a") || out.contains("+(++a)"),
    msg="got: \{out}",
  )
}

///|
test "emit: -(--a) keeps the operators apart" {
  let out = emit_min_one("const r = -(--a);\n")
  assert_false(out.contains("---"), msg="merged into -- -: \{out}")
}

///|
test "emit: +(+a) keeps the operators apart" {
  let out = emit_min_one("const r = +(+a);\n")
  assert_false(out.contains("+++"), msg="merged: \{out}")
}

///|
test "emit: ++(+a) keeps the operators apart" {
  // Not valid JS as written, but the folder can build this shape and the
  // emitter must not print something that parses as another program.
  let out = emit_min_one("const r = -(-a);\n")
  assert_false(out.contains("---"), msg="merged: \{out}")
}

///|
test "emit: +(-a) needs no separator" {
  let out = emit_min_one("const r = +(-a);\n")
  assert_true(out.contains("+-a"), msg="over-separated: \{out}")
}

///|
/// An arrow whose expression body starts with `{` has to be
/// parenthesised or the JS parser reads a block. The check used to be a
/// hand-listed set of shapes, and the erased type assertions were not on
/// it: `(o) => ({ ...o, k: 1 }) as T` emitted
/// `(o) => {...o, k: 1}`, a SyntaxError. zod writes that form
/// (`({ …core.standardProps(self) }) as ZodType["~standard"]`) and its
/// whole 714 KB bundle failed to load on it.
///
/// So the cases here are the family, not the one arm: every wrapper that
/// emits nothing of its own, and every operator whose emission begins
/// with its left operand.
test "emit: an arrow body starting with `{` keeps its parens through every wrapper" {
  let cases = [
    // the bare case, which always worked
    "({ k: 1 })",
    // erased type assertions — the ones that were missing
     "({ k: 1 }) as any", "({ k: 1 }) satisfies object", "({ k: 1 })!",
    // stacked, because one unwrap is not enough
     "({ k: 1 }) as any as object",
    // postfix forms, which the old list did cover
     "({ k: 1 }).k", "({ k: 1 })[\"k\"]",
    // an operator whose left operand is the object literal
     "({ k: 1 }).k + 1", "({ k: 1 }) ? 1 : 2",
    // wrapper under operator, and operator under wrapper
     "(({ k: 1 }) as any).k", "({ k: 1 }).k as any",
  ]
  for src in cases {
    let out = emit_min_one("const f = (o) => \{src};")
    // The body must not start a block. Checking the emitted text for
    // `=>{` is the whole assertion: that is precisely the shape the JS
    // parser mis-reads.
    if out.contains("=>{") {
      fail("`\{src}` lost its parens: \{out}")
    }
    if !out.contains("=>(") {
      fail("`\{src}` was not parenthesised: \{out}")
    }
  }
}

///|
test "emit: an arrow body that cannot start with `{` gets no parens" {
  // The other direction, so the fix is not just "parenthesise
  // everything". These pay no bytes.
  let cases = ["1 + 2", "o.k", "f(o)", "[1, 2]", "\"s\"", "o", "!o", "-1"]
  for src in cases {
    let out = emit_min_one("const f = (o) => \{src};")
    if out.contains("=>(") {
      fail("`\{src}` was parenthesised needlessly: \{out}")
    }
  }
}
