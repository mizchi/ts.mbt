// Tests for the constant-folder.

///|
fn fold_one(src : String) -> String raise {
  let block = @parser.parse_block_from_source(src)
  let folded = fold_block(block)
  let e = Emitter::new()
  for s in folded.stmts {
    emit_stmt(e, s)
    e.nl()
  }
  e.to_string()
}

///|
test "fold: x + 0 collapses to x" {
  let out = fold_one("const y = x + 0;\n")
  assert_true(out.contains("const y = x;"))
  assert_false(out.contains("+ 0"))
}

///|
test "fold: x * 1 collapses to x" {
  let out = fold_one("const y = x * 1;\n")
  assert_true(out.contains("const y = x;"))
}

///|
test "fold: literal int arithmetic collapses to a single literal" {
  let out = fold_one("const y = 2 + 3 * 4;\n")
  // Folder is bottom-up: 3 * 4 -> 12, then 2 + 12 -> 14.
  assert_true(out.contains("const y = 14;"))
}

///|
test "fold: if (true) splices the then-branch" {
  let out = fold_one("if (true) { const y = 1; } else { const y = 2; }\n")
  assert_true(out.contains("const y = 1;"))
  assert_false(out.contains("const y = 2;"))
}

///|
test "fold: if (false) splices the else-branch" {
  let out = fold_one("if (false) { const y = 1; } else { const y = 2; }\n")
  assert_true(out.contains("const y = 2;"))
  assert_false(out.contains("const y = 1;"))
}

///|
test "fold: if (false) with no else drops the statement entirely" {
  let out = fold_one(
    "const before = 1; if (false) { const inner = 9; } const after = 2;\n",
  )
  assert_true(out.contains("const before"))
  assert_true(out.contains("const after"))
  assert_false(out.contains("const inner"))
}

///|
test "fold: true && x reduces to x" {
  let out = fold_one("const y = true && z;\n")
  assert_true(out.contains("const y = z;"))
}

///|
test "fold: !true and !false collapse to literals" {
  let out = fold_one("const a = !true; const b = !false;\n")
  assert_true(out.contains("const a = false;"))
  assert_true(out.contains("const b = true;"))
}

///|
test "fold: x * 0 stays put when x has a possible side effect" {
  // `f()` could observe state — annihilator isn't safe.
  let out = fold_one("const y = f() * 0;\n")
  assert_true(out.contains("f() * 0"))
}

///|
test "fold: x * 0 collapses to 0 when x is pure" {
  let out = fold_one("const y = z * 0;\n")
  assert_true(out.contains("const y = 0;"))
}

///|
test "fold: string literal concatenation collapses to single literal" {
  let out = fold_one("const s = \"hello\" + \" \" + \"world\";\n")
  assert_true(out.contains("\"hello world\""))
  assert_false(out.contains("+"))
}

///|
test "fold: integer comparison collapses to bool literal" {
  let out = fold_one("const a = 1 === 1; const b = 1 !== 2; const c = 3 > 2;\n")
  assert_true(out.contains("const a = true;"))
  assert_true(out.contains("const b = true;"))
  assert_true(out.contains("const c = true;"))
}

///|
test "fold: string strict-equality collapses to bool literal" {
  let out = fold_one("const a = \"x\" === \"x\"; const b = \"x\" !== \"y\";\n")
  assert_true(out.contains("const a = true;"))
  assert_true(out.contains("const b = true;"))
}

///|
test "fold: null ?? x collapses to x" {
  let out = fold_one("const a = null ?? 42;\n")
  assert_true(out.contains("const a = 42;"))
  assert_false(out.contains("null"))
}

///|
test "fold: non-nullish literal ?? x short-circuits to the literal" {
  let out = fold_one("const a = 42 ?? fallback;\n")
  assert_true(out.contains("const a = 42;"))
  assert_false(out.contains("fallback"))
}
