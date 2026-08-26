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
