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

///|
test "fold: 0 && x collapses to 0 when x is pure" {
  let out = fold_one("const y = 0 && z;\n")
  assert_true(out.contains("const y = 0;"))
  assert_false(out.contains("&&"))
}

///|
test "fold: 0 && f() collapses to 0 even when f() has side effects (short-circuit)" {
  // JS short-circuit: `0 && f()` never calls f(), so dropping f() is safe.
  let out = fold_one("const y = 0 && f();\n")
  assert_true(out.contains("const y = 0;"))
  assert_false(out.contains("&&"))
}

///|
test "fold: 1 && x reduces to x" {
  let out = fold_one("const y = 1 && z;\n")
  assert_true(out.contains("const y = z;"))
  assert_false(out.contains("&&"))
}

///|
test "fold: 1 || x collapses to 1 (short-circuit)" {
  let out = fold_one("const y = 1 || z;\n")
  assert_true(out.contains("const y = 1;"))
  assert_false(out.contains("||"))
}

///|
test "fold: empty string || x reduces to x" {
  let out = fold_one("const y = \"\" || z;\n")
  assert_true(out.contains("const y = z;"))
  assert_false(out.contains("||"))
}

///|
test "fold: if (1) branch folds to then-block" {
  let out = fold_one("if (1) { console.log(\"yes\"); } else { console.log(\"no\"); }\n")
  assert_true(out.contains("yes"))
  assert_false(out.contains("no"))
}

///|
test "fold: if (0) branch folds to else-block" {
  let out = fold_one("if (0) { console.log(\"yes\"); } else { console.log(\"no\"); }\n")
  assert_false(out.contains("yes"))
  assert_true(out.contains("no"))
}

///|
test "fold: ternary with truthy literal uses then arm" {
  let out = fold_one("const x = \"hello\" ? a : b;\n")
  assert_true(out.contains("const x = a;"))
}

///|
test "fold: ternary with falsy literal uses else arm" {
  let out = fold_one("const x = null ? a : b;\n")
  assert_true(out.contains("const x = b;"))
}

///|
test "fold: typeof integer literal folds to \"number\"" {
  let out = fold_one("const t = typeof 42;\n")
  assert_true(out.contains("\"number\""))
  assert_false(out.contains("typeof"))
}

///|
test "fold: typeof string literal folds to \"string\"" {
  let out = fold_one("const t = typeof \"hello\";\n")
  assert_true(out.contains("\"string\""))
  assert_false(out.contains("typeof"))
}

///|
test "fold: typeof null folds to \"object\"" {
  let out = fold_one("const t = typeof null;\n")
  assert_true(out.contains("\"object\""))
  assert_false(out.contains("typeof"))
}

///|
test "fold: typeof 5 === \"number\" chain folds to true" {
  let out = fold_one("const ok = typeof 5 === \"number\";\n")
  assert_true(out.contains("const ok = true;"))
}

///|
test "fold: comma-expression with pure left side drops the left" {
  let out = fold_one("const x = (1, z);\n")
  assert_true(out.contains("const x = z;"))
  assert_false(out.contains("1,"))
}

///|
test "fold: comma-expression with side-effecting left is preserved" {
  let out = fold_one("const x = (f(), z);\n")
  assert_true(out.contains("f()"))
}

///|
test "fold: trailing bare return in function body is stripped" {
  let out = fold_one("const f = function() { console.log(1); return; };\n")
  assert_false(out.contains("return"))
  assert_true(out.contains("console.log"))
}

///|
test "fold: return with value in function body is preserved" {
  let out = fold_one("const f = function() { return 42; };\n")
  assert_true(out.contains("return 42"))
}

///|
test "fold: pure expression statement is dropped" {
  let out = fold_one("1 + 2;\nconsole.log(3);\n")
  assert_false(out.contains("1 + 2"))
  assert_true(out.contains("console.log"))
}

///|
test "fold: impure expression statement is preserved" {
  let out = fold_one("f();\n")
  assert_true(out.contains("f()"))
}

///|
test "fold: arrow block with single return collapses to concise form" {
  let out = fold_one("const f = (x) => { return x + 1; };\n")
  assert_false(out.contains("return"))
  assert_false(out.contains("{"))
  assert_true(out.contains("=>"))
}

///|
test "fold: arrow block with multiple statements is preserved" {
  let out = fold_one("const f = (x) => { const y = x + 1; return y; };\n")
  assert_true(out.contains("return"))
}
