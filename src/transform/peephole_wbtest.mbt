// Tests for the peephole pass + the minify-specific emit rewrites.

///|
fn peep_one(src : String) -> String raise {
  let block = @parser.parse_block_from_source(src)
  let out = peephole_block(block)
  let e = Emitter::new()
  for s in out.stmts {
    emit_stmt(e, s)
    e.nl()
  }
  e.to_string()
}

///|
fn minify_one(src : String) -> String raise {
  let block = @parser.parse_block_from_source(src)
  let folded = peephole_block(block)
  let e = Emitter::new(pretty=false)
  for s in folded.stmts {
    emit_stmt(e, s)
    e.nl()
  }
  e.to_string()
}

///|
test "peephole: x = x + y collapses to x += y" {
  let out = peep_one("x = x + 1;\n")
  assert_true(out.contains("x += 1"))
  assert_false(out.contains("x = x +"))
}

///|
test "peephole: x = x * y collapses to x *= y" {
  let out = peep_one("x = x * (y + 1);\n")
  assert_true(out.contains("x *= "))
}

///|
test "peephole: x = y + x does NOT collapse (left side mismatch)" {
  let out = peep_one("x = y + x;\n")
  assert_true(out.contains("x = y + x"))
}

///|
test "peephole: undefined references rewrite to void 0" {
  let out = peep_one("const a = undefined;\nconst b = x === undefined;\n")
  assert_true(out.contains("void 0"))
  assert_false(out.contains("undefined"))
}

///|
test "peephole: undefined is preserved when shadowed by a binding" {
  let out = peep_one("const undefined = 1;\nconst a = undefined;\n")
  // The const-binding to `undefined` shadows the global, so we
  // can't rewrite either reference.
  assert_true(out.contains("undefined"))
  assert_false(out.contains("void 0"))
}

///|
test "minify emit: trailing ; before } is dropped" {
  let out = minify_one("function f() { return 1; }\n")
  // The trailing `;` before `}` should be elided in minify mode.
  assert_true(out.contains("return 1}"))
  assert_false(out.contains("return 1;}"))
}

///|
test "minify emit: case keyword abuts string literal" {
  let out = minify_one(
    "function f(x) { switch (x) { case \"a\": return 1; case \"b\": return 2; } }\n",
  )
  assert_true(out.contains("case\"a\""))
  assert_true(out.contains("case\"b\""))
}

///|
test "minify emit: const destructure has no separator" {
  // In minify mode the emitter downgrades `const` to `let` (two
  // bytes saved per decl; the source already proved no
  // reassignment). The "no separator" property still holds.
  let out = minify_one("const { a, b } = obj;\n")
  assert_true(out.contains("let{"))
  assert_false(out.contains("let {"))
}

///|
test "minify emit: single-statement if drops braces" {
  let out = minify_one("function f(x) { if (x) { return 1; } }\n")
  assert_true(out.contains("if(x)return 1"))
  assert_false(out.contains("if(x){"))
}

///|
test "minify emit: return followed by object literal has no space" {
  let out = minify_one("function f() { return { a: 1 }; }\n")
  assert_true(out.contains("return{"))
}

///|
test "peephole: `true` becomes `!0` and `false` becomes `!1`" {
  let out_true = peep_one("const x = true;\n")
  assert_true(out_true.contains("!0"))
  assert_false(out_true.contains("true"))
  let out_false = peep_one("const x = false;\n")
  assert_true(out_false.contains("!1"))
  assert_false(out_false.contains("false"))
}
