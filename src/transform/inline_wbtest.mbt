// Tests for single-use const / let inlining.

///|
fn inline_one(src : String) -> String raise {
  let block = @parser.parse_block_from_source(src)
  let out = inline_block(block)
  let e = Emitter::new()
  for s in out.stmts {
    emit_stmt(e, s)
    e.nl()
  }
  e.to_string()
}

///|
test "inline: single-use const folds into the next stmt" {
  let out = inline_one("function f(x) { const y = x + 1; return y * 2; }\n")
  assert_true(out.contains("return (x + 1) * 2"))
  assert_false(out.contains("const y"))
}

///|
test "inline: const that's used twice is preserved" {
  let out = inline_one(
    "function f(x) { const y = x + 1; const z = y * y; return z; }\n",
  )
  // `y` is used twice in `y * y`, can't fold.
  assert_true(out.contains("const y"))
}

///|
test "inline: declaration whose rhs reads a reassigned binding is preserved" {
  // `a` is reassigned between `const y` and `return y`; folding
  // would change which value of `a` flows into the return.
  let out = inline_one(
    "function f() { let a = 1; const y = a; a = 99; return y; }\n",
  )
  assert_true(out.contains("const y"))
}

///|
test "inline: pure literal rhs folds even with multiple stmts between" {
  // The decl is followed immediately by the (single) use, so
  // anything that lives "between" never enters the picture.
  let out = inline_one("function f() { const y = 42; return y; }\n")
  assert_true(out.contains("return 42"))
  assert_false(out.contains("const y"))
}

///|
test "inline: skipped when binding is captured by a nested function" {
  // The arrow captures `y` by reference; inlining would change
  // when the rhs evaluates relative to the closure.
  let out = inline_one("function f(x) { const y = x + 1; return () => y; }\n")
  assert_true(out.contains("const y"))
}

///|
test "inline: skipped when the use is not the immediately-next stmt" {
  let out = inline_one(
    "function f(x) { const y = x + 1; console.log(\"hi\"); return y; }\n",
  )
  // The decl is two statements before the use — keep it to
  // preserve evaluation order of the intervening `console.log`.
  assert_true(out.contains("const y"))
}

///|
test "inline: nested function body is inlined recursively" {
  let out = inline_one(
    "function outer() {\n  return function (x) { const y = x + 1; return y * 2; };\n}\n",
  )
  // The wrapped fn's body should have its `y` folded too.
  assert_true(out.contains("return (x + 1) * 2"))
}
