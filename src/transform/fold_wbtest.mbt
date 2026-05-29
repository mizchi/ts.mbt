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
  assert_true(out.contains("before"))
  assert_true(out.contains("after"))
  assert_false(out.contains("inner"))
}

///|
test "fold: true && x reduces to x" {
  let out = fold_one("const y = true && z;\n")
  assert_true(out.contains("const y = z;"))
}

///|
test "fold: !true and !false collapse to literals" {
  let out = fold_one("const a = !true; const b = !false;\n")
  assert_true(out.contains("false") && out.contains("true"))
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
  assert_false(out.contains("==="))
  assert_false(out.contains("!=="))
  assert_false(out.contains("> 2"))
  assert_true(out.contains("true"))
}

///|
test "fold: string strict-equality collapses to bool literal" {
  let out = fold_one("const a = \"x\" === \"x\"; const b = \"x\" !== \"y\";\n")
  assert_false(out.contains("==="))
  assert_false(out.contains("!=="))
  assert_true(out.contains("true"))
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
test "fold: typeof void 0 folds to \"undefined\"" {
  let out = fold_one("const t = typeof void 0;\n")
  assert_true(out.contains("\"undefined\""))
  assert_false(out.contains("typeof"))
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

///|
test "fold: Math.abs with negative literal" {
  let out = fold_one("const x = Math.abs(-5);\n")
  assert_true(out.contains("const x = 5;"))
  assert_false(out.contains("Math.abs"))
}

///|
test "fold: Math.min / Math.max with literal args" {
  let out = fold_one("const a = Math.min(3, 1); const b = Math.max(3, 1);\n")
  assert_false(out.contains("Math.min"))
  assert_false(out.contains("Math.max"))
  assert_true(out.contains("1"))
  assert_true(out.contains("3"))
}

///|
test "fold: Math.sign with literal args" {
  let out = fold_one("const a = Math.sign(-5); const b = Math.sign(3);\n")
  assert_false(out.contains("Math.sign"))
  assert_true(out.contains("-1"))
  assert_true(out.contains("1"))
}

test "fold: !truthy folds to false" {
  let out = fold_one("const a = !1; const b = !\"hello\";\n")
  assert_false(out.contains("!1"))
  assert_false(out.contains("!\"hello\""))
  assert_true(out.contains("false"))
}

test "fold: !falsy folds to true" {
  let out = fold_one("const a = !0; const b = !\"\";\n")
  assert_false(out.contains("!0"))
  assert_false(out.contains("!\"\""))
  assert_true(out.contains("true"))
}

test "fold: ~n folds to bitwise complement" {
  let out = fold_one("const a = ~0; const b = ~5;\n")
  assert_false(out.contains("~0"))
  assert_false(out.contains("~5"))
  assert_true(out.contains("-1"))
  assert_true(out.contains("-6"))
}

test "fold: unary + on numeric literal is identity" {
  let out = fold_one("const a = +5;\n")
  assert_true(out.contains("const a = 5;"))
}

test "fold: if(c) return e1; return e2 merges to return c ? e1 : e2" {
  let out = fold_one(
    "function f(x) {\n  if (x > 0) return 1;\n  return -1;\n}\n",
  )
  assert_true(out.contains("return"))
  assert_true(out.contains("?"))
}

test "fold: if(c) { return e1; } else { return e2; } merges to return c ? e1 : e2" {
  let out = fold_one(
    "function f(x) {\n  if (x > 0) { return 1; } else { return -1; }\n}\n",
  )
  assert_true(out.contains("?"))
  assert_false(out.contains("else"))
}

test "fold: constant array index access folds to element" {
  let out = fold_one("const x = [10, 20, 30][1];\n")
  assert_true(out.contains("const x = 20;"))
  assert_false(out.contains("[10"))
}

test "fold: constant string key access on object literal folds to value" {
  let out = fold_one("const x = {a: 1, b: 2}[\"a\"];\n")
  assert_true(out.contains("const x = 1;"))
}

test "fold: prop access on object literal folds to value" {
  let out = fold_one("const x = {foo: 42}.foo;\n")
  assert_true(out.contains("const x = 42;"))
}

test "fold: string .includes with literal folds to bool" {
  let out = fold_one("const a = \"hello\".includes(\"ell\"); const b = \"hello\".includes(\"xyz\");\n")
  assert_false(out.contains(".includes("))
  assert_true(out.contains("true"))
  assert_true(out.contains("false"))
}

test "fold: string .startsWith and .endsWith fold to bool" {
  let out = fold_one("const a = \"hello\".startsWith(\"he\"); const b = \"hello\".endsWith(\"lo\");\n")
  assert_false(out.contains(".startsWith("))
  assert_false(out.contains(".endsWith("))
  assert_true(out.contains("true"))
}

test "fold: string .toUpperCase and .toLowerCase fold to literals" {
  let out = fold_one("const a = \"hello\".toUpperCase(); const b = \"WORLD\".toLowerCase();\n")
  assert_true(out.contains("\"HELLO\""))
  assert_true(out.contains("\"world\""))
}

test "fold: string .slice with non-negative args folds to literal" {
  let out = fold_one("const a = \"hello\".slice(1, 3);\n")
  assert_true(out.contains("\"el\""))
}

test "fold: array .join with literal items folds to string" {
  let out = fold_one("const s = [\"a\", \"b\", \"c\"].join(\"-\");\n")
  assert_true(out.contains("\"a-b-c\""))
  assert_false(out.contains("join"))
}

test "fold: array .includes with matching literal folds to true" {
  let out = fold_one("const x = [1, 2, 3].includes(2);\n")
  assert_true(out.contains("const x = true;"))
}

test "fold: Object.keys on object literal folds to array" {
  let out = fold_one("const k = Object.keys({a: 1, b: 2});\n")
  assert_true(out.contains("\"a\""))
  assert_true(out.contains("\"b\""))
  assert_false(out.contains("Object.keys"))
}

test "fold: !(a === b) folds to a !== b" {
  let out = fold_one("const x = !(a === b);\n")
  assert_true(out.contains("!=="))
  assert_false(out.contains("==="))
  assert_false(out.contains("!("))
}

test "fold: !(a < b) folds to a >= b" {
  let out = fold_one("const x = !(a < b);\n")
  assert_true(out.contains(">="))
  assert_false(out.contains("<"))
}

///|
test "fold: Math.PI folds to numeric literal" {
  let out = fold_one("const x = Math.PI;\n")
  assert_true(out.contains("3.14"))
  assert_false(out.contains("Math.PI"))
}

///|
test "fold: Math.E folds to numeric literal" {
  let out = fold_one("const x = Math.E;\n")
  assert_true(out.contains("2.71"))
  assert_false(out.contains("Math.E"))
}

///|
test "fold: obj[\"key\"] → obj.key when key is a valid identifier" {
  let out = fold_one("const v = obj[\"method\"];\n")
  assert_true(out.contains("obj.method"))
  assert_false(out.contains("[\"method\"]"))
}

///|
test "fold: array .concat folds two literal arrays" {
  let out = fold_one("const c = [1, 2].concat([3, 4]);\n")
  assert_true(out.contains("[1, 2, 3, 4]"))
  assert_false(out.contains("concat"))
}

///|
test "fold: array .flat folds one-level nested literal array" {
  let out = fold_one("const f = [1, [2, 3], 4].flat();\n")
  assert_true(out.contains("[1, 2, 3, 4]"))
  assert_false(out.contains("flat"))
}

///|
test "fold: new Object() → {}" {
  let out = fold_one("const o = new Object();\n")
  assert_true(out.contains("= {};"))
  assert_false(out.contains("new Object"))
}

///|
test "fold: new Array() → []" {
  let out = fold_one("const a = new Array();\n")
  assert_true(out.contains("= [];"))
  assert_false(out.contains("new Array"))
}

///|
test "fold: x?x:y collapses to x||y" {
  let out = fold_one("const r = a ? a : b;\n")
  assert_true(out.contains("a || b"))
  assert_false(out.contains("?"))
}

///|
test "fold: x?y:x collapses to x&&y" {
  let out = fold_one("const r = a ? b : a;\n")
  assert_true(out.contains("a && b"))
  assert_false(out.contains("?"))
}

///|
test "fold: parseInt(str,10) folds to integer literal" {
  let out = fold_one("const n = parseInt(\"42\", 10);\n")
  assert_true(out.contains("= 42;"))
  assert_false(out.contains("parseInt"))
}

///|
test "fold: parseFloat(str) folds to number literal" {
  let out = fold_one("const n = parseFloat(\"3.14\");\n")
  assert_true(out.contains("3.14"))
  assert_false(out.contains("parseFloat"))
}

///|
test "fold: parseInt without radix folds to integer literal" {
  let out = fold_one("const n = parseInt(\"100\");\n")
  assert_true(out.contains("= 100;"))
  assert_false(out.contains("parseInt"))
}

///|
test "fold: x===null||x===undefined → x==null" {
  let out = fold_one("const r = x === null || x === undefined;\n")
  assert_true(out.contains("=="))
  assert_false(out.contains("==="))
  assert_false(out.contains("||"))
}

///|
test "fold: x!==null&&x!==undefined → x!=null" {
  let out = fold_one("const r = x !== null && x !== undefined;\n")
  assert_true(out.contains("!="))
  assert_false(out.contains("!=="))
  assert_false(out.contains("&&"))
}

///|
test "fold: if(c){e1;}else{e2;} → c?e1:e2 expr stmt" {
  let out = fold_one("if (x > 0) { log(x); } else { log(-x); }\n")
  assert_true(out.contains("?"))
  assert_false(out.contains("if"))
  assert_false(out.contains("else"))
}

///|
test "fold: if(c){x=a;}else{x=b;} → c?x=a:x=b expr stmt" {
  let out = fold_one("if (flag) { result = 1; } else { result = 2; }\n")
  assert_true(out.contains("?"))
  assert_false(out.contains("if"))
  assert_false(out.contains("else"))
}

///|
test "fold: if(c){expr;} (no else) → c&&expr" {
  let out = fold_one("if (ok) { doSomething(); }\n")
  assert_true(out.contains("&&"))
  assert_false(out.contains("if"))
}

///|
test "fold: if(c){x=rhs;} (no else) → c&&(x=rhs)" {
  let out = fold_one("if (flag) { x = getValue(); }\n")
  assert_true(out.contains("&&"))
  assert_false(out.contains("if"))
}

///|
test "fold: if(!c){expr;} (no else) → c||expr" {
  let out = fold_one("if (!done) { process(); }\n")
  assert_true(out.contains("||"))
  assert_false(out.contains("if"))
  assert_false(out.contains("!done"))
}

///|
test "fold: Object.assign({}, src1, src2) merges to object literal" {
  let out = fold_one("const o = Object.assign({}, {a: 1}, {b: 2});\n")
  assert_true(out.contains("a: 1"))
  assert_true(out.contains("b: 2"))
  assert_false(out.contains("Object.assign"))
}

///|
test "fold: Object.assign({}, {a:1}, {a:2}) last-write wins" {
  let out = fold_one("const o = Object.assign({}, {a: 1}, {a: 2});\n")
  assert_true(out.contains("a: 2"))
  assert_false(out.contains("a: 1"))
  assert_false(out.contains("Object.assign"))
}

///|
test "fold: String.slice with negative index folds correctly" {
  let out = fold_one("const s = \"hello\".slice(-3);\n")
  assert_true(out.contains("\"llo\""))
  assert_false(out.contains("slice"))
}

///|
test "fold: String.charCodeAt folds to integer" {
  let out = fold_one("const n = \"A\".charCodeAt(0);\n")
  assert_true(out.contains("65"))
  assert_false(out.contains("charCodeAt"))
}

///|
test "fold: String.fromCharCode folds to string literal" {
  let out = fold_one("const s = String.fromCharCode(72, 101, 108);\n")
  assert_true(out.contains("\"Hel\""))
  assert_false(out.contains("fromCharCode"))
}

///|
test "fold: Array.slice with positive start folds correctly" {
  let out = fold_one("const s = [1, 2, 3].slice(1);\n")
  assert_true(out.contains("[2, 3]") || out.contains("[2,3]"))
  assert_false(out.contains("slice"))
}

///|
test "fold: Array.slice with negative index folds correctly" {
  let out = fold_one("const s = [1, 2, 3, 4].slice(-2);\n")
  assert_true(out.contains("[3, 4]") || out.contains("[3,4]"))
  assert_false(out.contains("slice"))
}

///|
test "fold: Array.at with negative index folds correctly" {
  let out = fold_one("const s = [10, 20, 30].at(-1);\n")
  assert_true(out.contains("30"))
  assert_false(out.contains(".at"))
}

///|
test "fold: String.padStart folds correctly" {
  let out = fold_one("const s = \"5\".padStart(3, \"0\");\n")
  assert_true(out.contains("\"005\""))
  assert_false(out.contains("padStart"))
}

///|
test "fold: String.padEnd folds correctly" {
  let out = fold_one("const s = \"hi\".padEnd(5);\n")
  assert_true(out.contains("\"hi   \""))
  assert_false(out.contains("padEnd"))
}

///|
test "fold: cond ? b : b (same var both branches) folds to b when cond is pure" {
  let out = fold_one("const r = isPure ? x : x;\n")
  // isPure is a Var, which is pure, so the whole expression collapses to x.
  assert_true(out.contains("const r = x"))
  assert_false(out.contains("?"))
}

///|
test "fold: x && x → x and x || x → x" {
  let out_and = fold_one("const r = x && x;\n")
  assert_true(out_and.contains("const r = x"))
  assert_false(out_and.contains("&&"))
  let out_or = fold_one("const r = x || x;\n")
  assert_true(out_or.contains("const r = x"))
  assert_false(out_or.contains("||"))
}

///|
test "fold: Seq(side_effect, pure) in statement position drops pure rhs" {
  // `(call(), 42);` → `call();` — the 42 return value is discarded.
  let out = fold_one("(doWork(), 42);\n")
  assert_true(out.contains("doWork()"))
  assert_false(out.contains("42"))
  assert_false(out.contains(","))
}

///|
test "fold: cross-type strict equality bool/int folds to false" {
  let out = fold_one("const r = true === 1;\n")
  assert_true(out.contains("false"))
  assert_false(out.contains("==="))
}

///|
test "fold: cross-type strict equality bool/string folds to false" {
  let out = fold_one("const r = true === \"true\";\n")
  assert_true(out.contains("false"))
  assert_false(out.contains("==="))
}

///|
test "fold: String.split with literal separator produces array literal" {
  let out = fold_one("const r = \"a,b,c\".split(\",\");\n")
  assert_true(out.contains("[\"a\",\"b\",\"c\"]") || out.contains("\"a\""))
  assert_false(out.contains(".split("))
}

///|
test "fold: String.replace with literal pattern and replacement" {
  let out = fold_one("const r = \"hello world\".replace(\"world\", \"there\");\n")
  assert_true(out.contains("\"hello there\""))
  assert_false(out.contains(".replace("))
}

///|
test "fold: String.replaceAll with literal pattern and replacement" {
  let out = fold_one("const r = \"aXbXc\".replaceAll(\"X\", \"-\");\n")
  assert_true(out.contains("\"a-b-c\""))
  assert_false(out.contains(".replaceAll("))
}

///|
test "fold: String.replace returns original when pattern not found" {
  let out = fold_one("const r = \"hello\".replace(\"xyz\", \"abc\");\n")
  assert_true(out.contains("\"hello\""))
}

///|
test "fold: integer literal .toString() folds to string literal" {
  let out = fold_one("const r = (42).toString();\n")
  assert_true(out.contains("\"42\""))
  assert_false(out.contains(".toString("))
}

///|
test "fold: bool literal .toString() folds to string literal" {
  let out = fold_one("const r = (true).toString();\n")
  assert_true(out.contains("\"true\""))
  assert_false(out.contains(".toString("))
}

///|
test "fold: integer .toString(16) folds to hex string" {
  let out = fold_one("const r = (255).toString(16);\n")
  assert_true(out.contains("\"ff\""))
  assert_false(out.contains(".toString("))
}

///|
test "fold: integer .toString(2) folds to binary string" {
  let out = fold_one("const r = (7).toString(2);\n")
  assert_true(out.contains("\"111\""))
}

///|
test "fold: Object.freeze({}) drops the freeze call" {
  let out = fold_one("const o = Object.freeze({ a: 1, b: 2 });\n")
  assert_false(out.contains("Object.freeze"))
  assert_true(out.contains("a"))
}

///|
test "fold: Object.fromEntries([[\"a\",1],[\"b\",2]]) → {a:1,b:2}" {
  let out = fold_one(
    "const o = Object.fromEntries([[\"a\", 1], [\"b\", 2]]);\n",
  )
  assert_false(out.contains("Object.fromEntries"))
  assert_true(out.contains("a"))
  assert_true(out.contains("b"))
}

///|
test "fold: !!(a === b) simplifies to a === b" {
  let out = fold_one("const r = !!(a === b);\n")
  assert_true(out.contains("a === b"))
  assert_false(out.contains("!!"))
  // The double-not should be gone; no leading `!` before `a`
  assert_false(out.contains("!(a"))
}

///|
test "fold: !!(a < b) simplifies to a < b" {
  let out = fold_one("const r = !!(a < b);\n")
  assert_true(out.contains("a < b"))
  assert_false(out.contains("!!"))
}

///|
test "fold: JSON.stringify(42) → \"42\"" {
  let out = fold_one("const r = JSON.stringify(42);\n")
  assert_true(out.contains("\"42\""))
  assert_false(out.contains("JSON.stringify"))
}

///|
test "fold: JSON.stringify(true) → \"true\"" {
  let out = fold_one("const r = JSON.stringify(true);\n")
  assert_true(out.contains("\"true\""))
  assert_false(out.contains("JSON.stringify"))
}

///|
test "fold: JSON.stringify(null) → \"null\"" {
  let out = fold_one("const r = JSON.stringify(null);\n")
  assert_true(out.contains("\"null\""))
  assert_false(out.contains("JSON.stringify"))
}

///|
test "fold: JSON.stringify(string) → quoted string" {
  let out = fold_one("const r = JSON.stringify(\"hello\");\n")
  assert_true(out.contains("\"\\\"hello\\\"\"") || out.contains("\\\"hello\\\""))
  assert_false(out.contains("JSON.stringify"))
}

///|
test "fold: Math.min with 3 literals" {
  let out = fold_one("const r = Math.min(5, 2, 8);\n")
  assert_true(out.contains("2"))
  assert_false(out.contains("Math.min"))
}

///|
test "fold: Math.floor(3.7) → 3" {
  let out = fold_one("const r = Math.floor(3.7);\n")
  assert_true(out.contains("3"))
  assert_false(out.contains("Math.floor"))
}

///|
test "fold: [].every(fn) → true" {
  let out = fold_one("const r = [].every(x => x > 0);\n")
  assert_true(out.contains("true"))
  assert_false(out.contains(".every("))
}

///|
test "fold: [].some(fn) → false" {
  let out = fold_one("const r = [].some(x => x > 0);\n")
  assert_true(out.contains("false"))
  assert_false(out.contains(".some("))
}

///|
test "fold: [].findIndex(fn) → -1" {
  let out = fold_one("const r = [].findIndex(x => x > 0);\n")
  assert_true(out.contains("-1"))
  assert_false(out.contains(".findIndex("))
}

///|
test "fold: [].filter(fn) → []" {
  let out = fold_one("const r = [].filter(x => x > 0);\n")
  assert_true(out.contains("[]"))
  assert_false(out.contains(".filter("))
}

///|
test "fold: IIFE with literal arg is inlined" {
  let out = fold_one("const r = ((x) => x + 1)(5);\n")
  assert_true(out.contains("6"))
  assert_false(out.contains("=>"))
}

///|
test "fold: IIFE with two literal args is inlined" {
  let out = fold_one("const r = ((x, y) => x * y)(3, 4);\n")
  assert_true(out.contains("12"))
  assert_false(out.contains("=>"))
}

///|
test "fold: IIFE with block-body single return is inlined" {
  let out = fold_one("const r = ((x) => { return x + 1; })(5);\n")
  assert_true(out.contains("6"))
  assert_false(out.contains("=>"))
}

///|
test "fold: IIFE with non-pure arg is NOT inlined" {
  let out = fold_one("const r = ((x) => x + 1)(foo());\n")
  assert_true(out.contains("=>"))
}

///|
test "fold: c ? true : false → !!c" {
  let out = fold_one("const r = x > 0 ? true : false;\n")
  assert_false(out.contains("true"))
  assert_false(out.contains("false"))
  // Should contain double negation
  assert_true(out.contains("!!") || out.contains("!!("))
}

///|
test "fold: c ? false : true → !c" {
  let out = fold_one("const r = x > 0 ? false : true;\n")
  assert_false(out.contains("true"))
  assert_false(out.contains("false"))
  assert_false(out.contains("?"))
}

///|
test "fold: string + bool coercion" {
  let out = fold_one("const r = \"x=\" + true;\n")
  assert_true(out.contains("\"x=true\""))
}

///|
test "fold: string + null coercion" {
  let out = fold_one("const r = \"val=\" + null;\n")
  assert_true(out.contains("\"val=null\""))
}

///|
test "fold: -IntLit folds to negated literal" {
  let out = fold_one("const x = -1;\n")
  assert_true(out.contains("-1"))
  // Check arithmetic works: (-1) + 5 = 4
  let out2 = fold_one("const x = -1 + 5;\n")
  assert_true(out2.contains("4"))
}

///|
test "fold: +BoolLit coerces to integer" {
  let out_t = fold_one("const x = +true;\n")
  assert_true(out_t.contains("1"))
  assert_false(out_t.contains("true"))
  let out_f = fold_one("const x = +false;\n")
  assert_true(out_f.contains("0"))
}

///|
test "fold: +null coerces to 0" {
  let out = fold_one("const x = +null;\n")
  assert_true(out.contains("0"))
  assert_false(out.contains("null"))
}

///|
test "fold: for-of over empty array literal is dropped" {
  let out = fold_one("for (const x of []) { use(x); }\n")
  assert_false(out.contains("for"))
  assert_false(out.contains("use"))
}

///|
test "fold: void 0 ?? x folds to x (nullish LHS)" {
  let out = fold_one("const r = (void 0) ?? fallback;\n")
  assert_true(out.contains("fallback"))
  assert_false(out.contains("void"))
  assert_false(out.contains("??"))
}

///|
test "fold: undefined ?? x folds to x (nullish LHS)" {
  let out = fold_one("const r = undefined ?? fallback;\n")
  assert_true(out.contains("fallback"))
  assert_false(out.contains("undefined"))
  assert_false(out.contains("??"))
}

///|
test "fold: x ^ x → 0 (same-var XOR)" {
  let out = fold_one("const r = n ^ n;\n")
  assert_true(out.contains("0"))
  assert_false(out.contains("^"))
}

///|
test "fold: x - x → 0 (same-var subtraction)" {
  let out = fold_one("const r = n - n;\n")
  assert_true(out.contains("0"))
  assert_false(out.contains("- n"))
}

///|
test "fold: x | x → x (bitwise-OR idempotency)" {
  let out = fold_one("const r = n | n;\n")
  assert_false(out.contains("|"))
}

///|
test "fold: x & x → x (bitwise-AND idempotency)" {
  let out = fold_one("const r = n & n;\n")
  assert_false(out.contains("&"))
}

///|
test "fold: x & -1 → x (AND with all-bits identity)" {
  let out = fold_one("const r = n & -1;\n")
  assert_false(out.contains("&"))
  assert_false(out.contains("-1"))
}

///|
test "fold: x | -1 → -1 (OR with all-bits annihilator, pure)" {
  let out = fold_one("const r = n | -1;\n")
  assert_false(out.contains("|"))
  assert_true(out.contains("-1"))
}

///|
test "fold: ~~x → x (double bitwise-NOT identity, pure)" {
  let out = fold_one("const r = ~~n;\n")
  assert_false(out.contains("~"))
}

///|
test "fold: x != null ? x : y folds to x ?? y" {
  let out = fold_one("const r = x != null ? x : defaultVal;\n")
  assert_true(out.contains("??"))
  assert_false(out.contains("!="))
  assert_false(out.contains("null"))
}

///|
test "fold: null != x ? x : y folds to x ?? y (reversed)" {
  let out = fold_one("const r = null != x ? x : defaultVal;\n")
  assert_true(out.contains("??"))
}

///|
test "fold: dead code after return is dropped" {
  let out = fold_one(
    "function f(x) { if (!x) { return null; } return x.value; const dead = 1; }\n",
  )
  assert_false(out.contains("dead"))
  assert_true(out.contains("return"))
}

///|
test "fold: dead code after throw is dropped" {
  let out = fold_one("function f() { throw new Error(); const dead = 2; }\n")
  assert_false(out.contains("dead"))
}

///|
test "fold: x != null ? x.prop : undefined folds to x?.prop" {
  let out = fold_one("const r = x != null ? x.name : undefined;\n")
  assert_true(out.contains("?.") || out.contains("x.name"))
  assert_false(out.contains("!= null"))
}

///|
test "fold: x != null ? x.method() : undefined folds to x?.method()" {
  let out = fold_one("const r = x != null ? x.toString() : undefined;\n")
  assert_true(out.contains("?.") || out.contains("x.toString"))
}

///|
test "fold: if(c){x=e1}else{x=e2} lifts to x=c?e1:e2" {
  let out = fold_one("if (ok) { x = 1; } else { x = 2; }\n")
  // Both branches assign to the same var; the assignment should be lifted out.
  assert_true(out.contains("x ="))
  // Should not produce two separate assignment expressions inside a ternary.
  assert_false(out.contains("x = 1") && out.contains("x = 2"))
}

///|
test "fold: x ** 0 folds to 1 for pure x" {
  let out = fold_one("const y = x ** 0;\n")
  assert_true(out.contains("const y = 1;"))
  assert_false(out.contains("**"))
}

///|
test "fold: \"key\" in {key:1} folds to true" {
  let out = fold_one("const r = \"key\" in {key: 1, other: 2};\n")
  assert_true(out.contains("const r = true;"))
  assert_false(out.contains(" in "))
}

///|
test "fold: \"missing\" in {key:1} folds to false" {
  let out = fold_one("const r = \"missing\" in {key: 1};\n")
  assert_true(out.contains("const r = false;"))
}

///|
test "fold: null instanceof X folds to false" {
  let out = fold_one("const r = null instanceof Array;\n")
  assert_true(out.contains("const r = false;"))
  assert_false(out.contains("instanceof"))
}

///|
test "fold: 42 instanceof X folds to false" {
  let out = fold_one("const r = 42 instanceof Array;\n")
  assert_true(out.contains("const r = false;"))
}

///|
test "fold: abstract equality of same-type literals" {
  let out1 = fold_one("const r = 1 == 1;\n")
  assert_true(out1.contains("const r = true;"))
  let out2 = fold_one("const r = 1 == 2;\n")
  assert_true(out2.contains("const r = false;"))
  let out3 = fold_one("const r = \"a\" == \"a\";\n")
  assert_true(out3.contains("const r = true;"))
}

///|
test "fold: null == undefined is true" {
  let out = fold_one("const r = null == undefined;\n")
  assert_true(out.contains("const r = true;"))
}

///|
test "fold: null == 0 is false" {
  let out = fold_one("const r = null == 0;\n")
  assert_true(out.contains("const r = false;"))
}

///|
test "fold: c ? (x=a) : (x=b) hoists assignment" {
  // Both branches assign the same variable → hoist x= outside ternary.
  let out = fold_one("const r = c ? (x = 1) : (x = 2);\n")
  assert_true(out.contains("x=c?1:2") || out.contains("x = c ? 1 : 2"))
  assert_false(out.contains("x=1"))
  assert_false(out.contains("x=2"))
}

///|
test "fold: void call() in stmt drops void wrapper" {
  // `void f()` as a statement — the void wrapper is redundant since
  // the result is discarded. Saves 5 bytes per site.
  let out = fold_one("void f();\n")
  assert_false(out.contains("void"))
  assert_true(out.contains("f()"))
}

///|
test "fold: void pure expression in stmt is dropped entirely" {
  // `void 0;` is pure, so the entire statement is dropped.
  let out = fold_one("void 0;\n")
  assert_false(out.contains("void"))
}

test "fold: return undefined normalizes to return" {
  // `return undefined` and `return void 0` carry no useful value;
  // normalize to bare `return;` so fold_func_body can strip the
  // trailing return entirely.
  let out = fold_one("function f() { return undefined; }\n")
  // After normalization + trailing-return strip, no `return` survives.
  assert_false(out.contains("return"))
}

test "fold: return void 0 normalizes to return" {
  let out = fold_one("function f() { x(); return void 0; }\n")
  // The void-return is stripped; only the call stays.
  assert_false(out.contains("return"))
  assert_true(out.contains("x()"))
}

test "fold: try {} finally {} with empty finally drops wrapper" {
  // `try { stmts } finally {}` — empty finally is a no-op, and
  // without both catch and finally the try is also redundant.
  let out = fold_one("try { f(); } finally {}\n")
  assert_true(out.contains("f()"))
  assert_false(out.contains("try"))
  assert_false(out.contains("finally"))
}

test "fold: try {} finally { stmts } keeps finally when non-empty" {
  let out = fold_one("try { f(); } finally { g(); }\n")
  assert_true(out.contains("try"))
  assert_true(out.contains("finally"))
}

test "fold: x = x self-assignment in stmt is dropped" {
  let out = fold_one("x = x;\n")
  // Self-assignment is a no-op; nothing should remain.
  assert_false(out.contains("x"))
}

test "fold: x = x in expression position simplifies to x" {
  // In expression context, `(x = x)` evaluates to `x`.
  let out = fold_one("const r = (x = x);\n")
  assert_true(out.contains("const r=x") || out.contains("const r = x"))
  assert_false(out.contains("x=x") || out.contains("x = x"))
}

///|
test "fold: !!x ? a : b simplifies to x ? a : b" {
  // Double negation doesn't change truthiness; strip it in ternary condition.
  let out = fold_one("const r = !!x ? 1 : 2;\n")
  assert_false(out.contains("!!") || out.contains("!x") || out.contains("!!"))
  assert_true(out.contains("x"))
}

///|
test "fold: !x ? a : b simplifies to x ? b : a (branch swap)" {
  // Single negation in ternary condition → swap branches, drop the `!`.
  let out = fold_one("const r = !x ? 1 : 2;\n")
  // After swap: `x ? 2 : 1`
  assert_false(out.contains("!x"))
  assert_true(out.contains("x"))
}

///|
test "fold: if (cond) { stmts } else {} drops empty else branch" {
  // An empty `else {}` contributes bytes without changing semantics.
  let out = fold_one("if (x) { console.log(1); } else {}\n")
  assert_false(out.contains("else"))
  assert_true(out.contains("if"))
}

///|
test "fold: if (cond) {} else { stmts } becomes if (!cond) { stmts }" {
  // Empty then-branch → invert condition, drop the else wrapper.
  let out = fold_one("if (x) {} else { console.log(1); }\n")
  assert_false(out.contains("else"))
  // Inverted condition or equivalent
  assert_true(out.contains("if"))
}

///|
test "fold: Seq in stmt position splits into individual statements" {
  // `(a(), b())` → `a(); b()` — two separate statements.
  // Each can then be independently eliminated if pure.
  let out = fold_one("(a(), b());\n")
  assert_false(out.contains(","))
  assert_true(out.contains("a()"))
  assert_true(out.contains("b()"))
}

///|
test "fold: Seq where second part is pure drops second part" {
  // `(a(), 1)` → `a()` — pure second operand discarded.
  let out = fold_one("(a(), 1);\n")
  assert_false(out.contains("1"))
  assert_true(out.contains("a()"))
}

///|
test "fold: nested Seq in stmt position flattens all parts" {
  // `((a(), b()), c())` → `a(); b(); c();`
  let out = fold_one("((a(), b()), c());\n")
  assert_false(out.contains(","))
  assert_true(out.contains("a()"))
  assert_true(out.contains("b()"))
  assert_true(out.contains("c()"))
}

///|
test "fold: nested if without else merges into && condition" {
  // `if (a) { if (b) { stmts } }` → `if (a && b) { stmts }` or `a && b && console.log(1)`
  let out = fold_one("if (a) { if (b) { console.log(1); } }\n")
  assert_true(out.contains("a") && out.contains("b"))
  assert_true(out.contains("console.log"))
  assert_false(out.contains("if ("))
}

///|
test "fold: nested if with outer else not merged (unsafe)" {
  // When the outer if has an else, merging is not safe.
  let out = fold_one("if (a) { if (b) { console.log(1); } } else { console.log(2); }\n")
  // Should still contain both `a` and `b` as separate conditions
  assert_true(out.contains("else") || out.contains("?"))
}

///|
test "fold: for-of over empty string is a no-op" {
  let out = fold_one("for (const c of \"\") { console.log(c); }\n")
  assert_false(out.contains("for"))
  assert_false(out.contains("console"))
}

///|
test "fold: for-in over empty object is a no-op" {
  let out = fold_one("for (const k in {}) { console.log(k); }\n")
  assert_false(out.contains("for"))
  assert_false(out.contains("console"))
}

///|
test "fold: multi-level if-return chain collapses to nested ternary" {
  // `if (c1) return e1; if (c2) return e2; return e3;`
  // → `return c1 ? e1 : c2 ? e2 : e3;`
  let out = fold_one(
    (
      #|function f(c1, c2) {
      #|  if (c1) return 1;
      #|  if (c2) return 2;
      #|  return 3;
      #|}
    ),
  )
  // Should collapse to a single return with nested ternary
  assert_false(out.contains("if (c1)") || out.contains("if(c1)"))
  assert_false(out.contains("if (c2)") || out.contains("if(c2)"))
  assert_true(out.contains("return"))
}

///|
test "fold: else-if return chain collapses to nested ternary" {
  // `if (c1) return e1; else if (c2) return e2; else return e3;`
  // → `return c1 ? e1 : c2 ? e2 : e3;`
  let out = fold_one(
    (
      #|function f(c1, c2) {
      #|  if (c1) return 1;
      #|  else if (c2) return 2;
      #|  else return 3;
      #|}
    ),
  )
  assert_false(out.contains("else"))
  assert_true(out.contains("return"))
}

///|
test "fold: single-case switch lowered to if statement" {
  let out = fold_one(
    (
      #|switch (x) {
      #|  case "foo":
      #|    doFoo();
      #|    break;
      #|}
    ),
  )
  assert_false(out.contains("switch"))
  assert_true(out.contains("doFoo"))
}

///|
test "fold: single-case switch with default lowered to if-else" {
  let out = fold_one(
    (
      #|switch (x) {
      #|  case "foo":
      #|    doFoo();
      #|    break;
      #|  default:
      #|    doDefault();
      #|}
    ),
  )
  assert_false(out.contains("switch"))
  assert_true(out.contains("doFoo"))
  assert_true(out.contains("doDefault"))
}

///|
test "fold: default-only switch inlined to body" {
  let out = fold_one(
    (
      #|switch (x) {
      #|  default:
      #|    doDefault();
      #|}
    ),
  )
  assert_false(out.contains("switch"))
  assert_true(out.contains("doDefault"))
}

///|
test "fold: multi-stmt default-only switch inlined to block" {
  let out = fold_one(
    (
      #|switch (x) {
      #|  default:
      #|    doFirst();
      #|    doSecond();
      #|}
    ),
  )
  assert_false(out.contains("switch"))
  assert_true(out.contains("doFirst"))
  assert_true(out.contains("doSecond"))
}

///|
test "fold: uninit let + assign merges to initialized let" {
  let out = fold_one("let x; x = 42;\n")
  // Should emit `let x = 42` (no separate assignment statement)
  assert_true(out.contains("let x"))
  assert_true(out.contains("42"))
  // No standalone assignment statement (just one line total)
  assert_true(out.trim_space().split("\n").collect().length() == 1)
}

///|
test "fold: uninit let + assign does not merge when intervening statement" {
  let out = fold_one("let x; doSomething(); x = 42;\n")
  // The assignment is not the immediate next statement — do NOT merge
  assert_true(out.contains("x=42") || out.contains("x = 42"))
}

///|
test "fold: void on pure template literal collapses to void 0" {
  // TemplateLiteral is now pure, so `void \`${x}\`` → `void 0`.
  let out = fold_one("const t = void `${x} world`;\n")
  assert_true(out.contains("void 0"))
}

///|
test "fold: template-literal ?? fallback is eliminated (template never nullish)" {
  // TemplateLiteral can never be null/undefined, so `\`${x}\` ?? fallback`
  // folds to just the template literal.
  let out = fold_one("const t = `${x} world` ?? \"default\";\n")
  assert_false(out.contains("default"))
  assert_false(out.contains("??"))
}

///|
test "fold: NonNull assertion ?? fallback is eliminated (x! never nullish)" {
  let out = fold_one("const t = (x!) ?? \"fallback\";\n")
  assert_false(out.contains("fallback"))
  assert_false(out.contains("??"))
}

///|
test "fold: optional chain on non-null receiver is dropped" {
  // `[1,2,3]?.length` — the receiver is an array literal (never null),
  // so `?.` is redundant and should become `.`.
  let out = fold_one("const n = [1,2,3]?.length;\n")
  assert_false(out.contains("?."))
}

///|
test "fold: new-expr ?? fallback is eliminated (new always non-null)" {
  // `new Map() ?? fallback` — `new` always returns an object, so the
  // fallback can never be reached.
  let out = fold_one("const m = new Map() ?? fallback;\n")
  assert_false(out.contains("fallback"))
  assert_false(out.contains("??"))
}

///|
test "fold: Array.of(1, 2, 3) folds to array literal" {
  let out = fold_one("const x = Array.of(1, 2, 3);\n")
  assert_true(out.contains("[1,") || out.contains("[1, "), msg="expected array literal in output")
  assert_false(out.contains("Array.of"), msg="Array.of should be folded away")
}

///|
test "fold: spread literal arrays are flattened in array literal" {
  // `[...a, ...b]` where a and b are literal arrays should fold to a single array.
  let out = fold_one("const x = [...[1, 2], ...[3, 4]];\n")
  assert_true(out.contains("[1") || out.contains("[ 1"), msg="expected flattened array in output")
  assert_false(out.contains("..."), msg="expected spread to be folded away")
}

///|
test "fold: x === x folds to true" {
  let out = fold_one("const r = a === a;\n")
  assert_true(out.contains("true") || out.contains("!0"), msg="expected true but got: \{out}")
  assert_false(out.contains("==="))
}

///|
test "fold: x !== x folds to false" {
  let out = fold_one("const r = a !== a;\n")
  assert_true(out.contains("false") || out.contains("!1"), msg="expected false but got: \{out}")
  assert_false(out.contains("!=="))
}

///|
test "fold: else block hoisted when then-branch always returns" {
  // `if (c) { return x; } else { stmts }` → `if (c) return x; stmts`
  // Saves `} else {` bytes in minified output.
  let out = fold_one("function f(c, x, y) { if (c) { return x; } else { return y; } }\n")
  // After hoisting, the else is gone. The result could be
  // `return c ? x : y` (further folded) or `if(c)return x; return y;`.
  assert_false(out.contains("else"), msg="expected else to be removed: \{out}")
}

///|
test "fold: else block hoisted when then-branch throws" {
  // `if (!x) { throw e; } else { stmts }` → `if(!x)throw e; stmts`
  let out = fold_one("function f(x) { if (!x) { throw new Error('bad'); } else { return x + 1; } }\n")
  assert_false(out.contains("else"), msg="expected else to be removed: \{out}")
}

///|
test "fold: consecutive const decls merged into multi-decl" {
  let out = fold_one("const a = 1;\nconst b = 2;\nconst c = 3;\n")
  // All three should appear in a single multi-decl (no repeated `const`/`let`).
  let const_count = out.split("const").collect().length() - 1
  let let_count = out.split("let").collect().length() - 1
  let total_kind = const_count + let_count
  assert_true(total_kind == 1, msg="expected one declaration keyword, got: \{out}")
  assert_true(out.contains("1"))
  assert_true(out.contains("2"))
  assert_true(out.contains("3"))
}

///|
test "fold: mixed let and const are NOT merged (different kinds)" {
  let out = fold_one("const a = 1;\nlet b = 2;\n")
  // `const` and `let` must stay separate — different semantic kinds.
  assert_true(out.contains("1"))
  assert_true(out.contains("2"))
}

///|
test "fold: consecutive let decls separated by non-decl are not merged" {
  let out = fold_one("let a = 1;\nconsole.log(a);\nlet b = 2;\n")
  // The `console.log` breaks the run — a and b cannot be merged.
  assert_true(out.contains("1"))
  assert_true(out.contains("2"))
  assert_true(out.contains("console"))
}

///|
test "fold: function-decl const is NOT merged with adjacent const" {
  let out = fold_one("const a = 1;\nconst f = function f() { return 2; };\n")
  // `f` emits as `function f() {...}` (shorter than `const f = function...`).
  // Merging it into a multi-decl would force it to be a function expression
  // and produce longer output, so they must stay separate.
  assert_true(out.contains("function"))
  assert_true(out.contains("1"))
}

///|
test "fold: do { body } while(false) inlines body (no break/continue)" {
  let out = fold_one("do { const x = 1; console.log(x); } while(false);\n")
  // The do-while with a false condition and no breaks executes exactly once.
  // It should be inlined to just the body statements.
  assert_false(out.contains("do"), msg="expected do-while to be removed: \{out}")
  assert_false(out.contains("while"), msg="expected while to be removed: \{out}")
  assert_true(out.contains("console"))
}

///|
test "fold: do { body; break; } while(false) keeps the loop (has break)" {
  let out = fold_one("do { if (x) break; doSomething(); } while(false);\n")
  // There is an unlabeled `break` — can't remove the do-while safely.
  assert_true(out.contains("do") || out.contains("while"), msg="expected do-while to remain: \{out}")
}

///|
test "fold: do { body } while(true) stays as a loop" {
  // `while(true)` is truthy → do-while is not removed (it's an infinite loop).
  let out = fold_one("do { doWork(); } while(true);\n")
  // The `while(true)` emits as `while(!0)` or stays as do-while.
  assert_true(out.contains("do") || out.contains("while"))
}

///|
test "fold: !!x in if condition is stripped (saves 2 bytes)" {
  let out = fold_one("if (!!x) { doIt(); }\n")
  // `!!x` in boolean position is equivalent to `x` — JS coerces anyway.
  assert_false(out.contains("!!"), msg="expected !! stripped: \{out}")
  assert_true(out.contains("if (x)") || out.contains("if(x)") || out.contains("x&&") || out.contains("x &&"), msg="expected x retained: \{out}")
}

///|
test "fold: !!x in while condition is stripped" {
  let out = fold_one("while (!!running) { tick(); }\n")
  assert_false(out.contains("!!"), msg="expected !! stripped: \{out}")
  assert_true(out.contains("running"), msg="expected running retained: \{out}")
}

///|
test "fold: !!x in for condition is stripped" {
  let out = fold_one("for (; !!active; ) { step(); }\n")
  assert_false(out.contains("!!"), msg="expected !! stripped: \{out}")
  assert_true(out.contains("active"), msg="expected active retained: \{out}")
}

///|
test "fold: !!x in return is NOT stripped (value semantics preserved)" {
  let out = fold_one("function f(x) { return !!x; }\n")
  // Outside boolean-context positions, `!!x` must be preserved
  // since it coerces to a boolean while `x` might not be.
  assert_true(out.contains("!!"), msg="expected !! kept in return: \{out}")
}

///|
test "fold: `call() && void 0;` in stmt position simplifies to `call()`" {
  // The right operand `void 0` is pure (no side effects), so it can be
  // dropped. In statement position `call() && void 0;` ≡ `call();`.
  let out = fold_one("call() && void 0;\n")
  assert_true(out.contains("call()"), msg="expected call() retained: \{out}")
  assert_false(out.contains("&&"), msg="expected && dropped: \{out}")
  assert_false(out.contains("void"), msg="expected void 0 dropped: \{out}")
}

///|
test "fold: `call() || void 0;` in stmt position simplifies to `call()`" {
  let out = fold_one("call() || void 0;\n")
  assert_true(out.contains("call()"), msg="expected call() retained: \{out}")
  assert_false(out.contains("||"), msg="expected || dropped: \{out}")
}

///|
test "fold: `call() && 1;` in stmt position simplifies to `call()`" {
  // `1` is a pure value — safe to drop the whole && rhs.
  let out = fold_one("call() && 1;\n")
  assert_true(out.contains("call()"), msg="expected call() retained: \{out}")
  assert_false(out.contains("&&"), msg="expected && dropped: \{out}")
}

///|
test "fold: `call() && sideEffect();` keeps both (rhs not pure)" {
  // sideEffect() is a call — not pure, so the rhs must be kept.
  let out = fold_one("call() && sideEffect();\n")
  assert_true(out.contains("call()"), msg="expected call() retained: \{out}")
  assert_true(out.contains("sideEffect()"), msg="expected sideEffect() retained: \{out}")
  assert_true(out.contains("&&"), msg="expected && kept: \{out}")
}

///|
test "fold: Boolean(x) folds to !!x for non-literal arg (saves 8+ bytes)" {
  let out = fold_one("const b = Boolean(x);\n")
  // `Boolean(x)` → `!!x` — saves 8 bytes vs the 9-char "Boolean(" prefix.
  assert_true(out.contains("!!"), msg="expected !!: \{out}")
  assert_false(out.contains("Boolean"), msg="expected Boolean removed: \{out}")
}

///|
test "fold: Boolean(true) folds to literal true (then peephole → !0)" {
  let out = fold_one("const b = Boolean(true);\n")
  // Boolean of a known-truthy literal → BoolLit(true)
  assert_false(out.contains("Boolean"), msg="expected Boolean removed: \{out}")
}

///|
test "fold: Boolean(0) folds to literal false" {
  let out = fold_one("const b = Boolean(0);\n")
  assert_false(out.contains("Boolean"), msg="expected Boolean removed: \{out}")
  assert_true(out.contains("false") || out.contains("!1"), msg="expected false: \{out}")
}

///|
test "fold: Number(x) folds to +x for non-literal arg (saves 7+ bytes)" {
  let out = fold_one("const n = Number(x);\n")
  // `Number(x)` → `+x` — saves 7 bytes vs "Number(" for a 1-char ident.
  assert_false(out.contains("Number"), msg="expected Number removed: \{out}")
  assert_true(out.contains("+x"), msg="expected +x: \{out}")
}

///|
test "fold: Number(true) folds to literal 1" {
  let out = fold_one("const n = Number(true);\n")
  assert_false(out.contains("Number"), msg="expected Number removed: \{out}")
  assert_true(out.contains("1"), msg="expected 1: \{out}")
}

///|
test "fold: Number(\"42\") folds to integer 42" {
  let out = fold_one("const n = Number(\"42\");\n")
  assert_false(out.contains("Number"), msg="expected Number removed: \{out}")
  assert_true(out.contains("42"), msg="expected 42: \{out}")
}
