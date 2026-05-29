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

///|
test "peephole: return undefined collapses to bare return" {
  let out = peep_one("function f() { return undefined; }\n")
  assert_false(out.contains("undefined"))
  assert_true(out.contains("return"))
}

///|
test "peephole: return void 0 collapses to bare return" {
  let out = peep_one("function f() { return void 0; }\n")
  assert_false(out.contains("void 0"))
  assert_true(out.contains("return"))
}

///|
test "peephole: x += 1 becomes x++" {
  let out = peep_one("x += 1;\n")
  assert_true(out.contains("x++"))
  assert_false(out.contains("+="))
}

///|
test "peephole: x = x + 1 folds to x++ in one pass" {
  let out = peep_one("x = x + 1;\n")
  assert_true(out.contains("x++"))
  assert_false(out.contains("x = x + 1"))
  assert_false(out.contains("+="))
}

///|
test "peephole: x = x - 1 folds to x-- in one pass" {
  let out = peep_one("x = x - 1;\n")
  assert_true(out.contains("x--"))
  assert_false(out.contains("x = x - 1"))
  assert_false(out.contains("-="))
}

///|
test "peephole: x -= 1 becomes x--" {
  let out = peep_one("x -= 1;\n")
  assert_true(out.contains("x--"))
  assert_false(out.contains("-="))
}

///|
test "minify emit: single-ident arrow param skips parens" {
  let out = minify_one("const f = x => x + 1;\n")
  assert_true(out.contains("x=>"))
  assert_false(out.contains("(x)=>"))
}

///|
test "minify emit: multi-param arrow keeps parens" {
  let out = minify_one("const f = (x, y) => x + y;\n")
  assert_true(out.contains("(x,y)=>") || out.contains("(x, y)=>"))
}

///|
test "minify emit: rest-param arrow keeps parens" {
  let out = minify_one("const f = (...args) => args;\n")
  assert_true(out.contains("(...args)=>"))
}

///|
test "minify emit: while(true) → for(;;)" {
  let out = minify_one("while (true) { doWork(); }\n")
  assert_true(out.contains("for(;;)"))
  assert_false(out.contains("while"))
}

///|
test "minify emit: typeof string literal abuts without space" {
  let out = minify_one("const t = typeof \"hello\";\n")
  assert_true(out.contains("typeof\"hello\""))
}

///|
test "minify emit: object shorthand {x:x} → {x}" {
  let out = minify_one("const o = { x: x, y: y };\n")
  // In minify mode, {x: x, y: y} → {x, y} (saves 2 bytes per key-value pair).
  assert_true(out.contains("{x,y}") || out.contains("{x, y}"))
  assert_false(out.contains("x: x"))
  assert_false(out.contains("y: y"))
}

///|
test "minify emit: async arrow with parens drops space before `(`" {
  let out = minify_one("const f = async (x) => x + 1;\n")
  assert_true(out.contains("async(x)=>"))
  assert_false(out.contains("async (x)=>"))
}

///|
test "minify emit: async arrow with bare param keeps space before ident" {
  let out = minify_one("const f = async x => x + 1;\n")
  // bare identifier param: `async x=>` (space required before ident)
  assert_true(out.contains("async x=>"))
}

///|
test "minify emit: for-of array literal drops space after `of`" {
  let out = minify_one("for (const x of [1, 2, 3]) { use(x); }\n")
  assert_true(out.contains("of["))
  assert_false(out.contains("of ["))
}

///|
test "minify emit: for-of identifier keeps space after `of`" {
  let out = minify_one("for (const x of arr) { use(x); }\n")
  assert_true(out.contains(" of arr"))
}

///|
test "minify emit: large integer with trailing zeros uses scientific notation" {
  let out = minify_one("const x = 1000000;\n")
  assert_true(out.contains("1e6"))
  assert_false(out.contains("1000000"))
}

///|
test "minify emit: CompoundAssignExpr += 1 becomes ++" {
  let out = minify_one("function f(obj) { obj.count += 1; }\n")
  assert_true(out.contains("obj.count++") || out.contains("++"))
  assert_false(out.contains("+="))
}

///|
test "minify emit: try drops space before `{`" {
  let out = minify_one("try { risky(); } catch (e) { handle(e); }\n")
  assert_true(out.contains("try{"))
  assert_false(out.contains("try {"))
}

///|
test "minify emit: catch drops space before `(`" {
  let out = minify_one("try { risky(); } catch (e) { handle(e); }\n")
  assert_true(out.contains("catch(e)"))
  assert_false(out.contains("catch (e)"))
}

///|
test "minify emit: for-of with destructuring binding drops space after `let`" {
  let out = minify_one("for (const [k, v] of entries) { use(k, v); }\n")
  // In minify mode, `let[k,v]` — no space between `let` and `[`.
  assert_true(out.contains("let["))
  assert_false(out.contains("let ["))
}

///|
test "minify emit: for-of with ident binding keeps space after `let`" {
  let out = minify_one("for (const x of arr) { use(x); }\n")
  assert_true(out.contains("let x"))
}

///|
test "peephole: trailing break in last switch case is dropped" {
  let out = peep_one(
    "switch (x) { case \"a\": doA(); break; case \"b\": doB(); break; }\n",
  )
  // The trailing `break` in the last case (`"b"`) should be removed.
  // The first case's `break` must be retained.
  assert_true(out.contains("doA()"))
  assert_true(out.contains("doB()"))
  // Last break is gone but first break stays to prevent fallthrough.
  let break_count = out.split("break").length() - 1
  assert_true(break_count == 1)
}

///|
test "minify emit: let x = undefined drops initializer" {
  let out = minify_one("let x = undefined;\n")
  // Initializer should be absent — saves `= void 0` bytes.
  assert_false(out.contains("void"))
  assert_false(out.contains("undefined"))
  assert_true(out.contains("let x"))
}

///|
test "minify emit: let x = void 0 drops initializer" {
  let out = minify_one("let x = void 0;\n")
  assert_false(out.contains("void"))
  assert_true(out.contains("let x"))
}

///|
test "minify emit: const x = undefined drops initializer (const→let, no = void 0)" {
  let out = minify_one("const x = undefined;\n")
  // const is downgraded to let; undefined initializer is dropped.
  assert_false(out.contains("void"))
  assert_false(out.contains("undefined"))
  assert_true(out.contains("let x"))
}

///|
test "peephole: x.prop = x.prop + 1 folds to x.prop++" {
  let out = peep_one("x.count = x.count + 1;\n")
  assert_true(out.contains("x.count++") || out.contains("++"))
  assert_false(out.contains("= x.count + 1"))
}

///|
test "peephole: x.prop = x.prop - 1 folds to x.prop--" {
  let out = peep_one("x.count = x.count - 1;\n")
  assert_true(out.contains("x.count--") || out.contains("--"))
  assert_false(out.contains("= x.count - 1"))
}

///|
test "peephole: x.prop = x.prop + n collapses to x.prop += n" {
  let out = peep_one("x.count = x.count + 5;\n")
  assert_true(out.contains("x.count += 5") || out.contains("+="))
  assert_false(out.contains("= x.count + 5"))
}

///|
test "peephole: arr[i] = arr[i] + 1 folds to arr[i]++" {
  let out = peep_one("arr[i] = arr[i] + 1;\n")
  assert_true(out.contains("arr[i]++") || out.contains("++"))
  assert_false(out.contains("= arr[i] + 1"))
}

///|
test "peephole: arr[i] = arr[i] - 1 folds to arr[i]--" {
  let out = peep_one("arr[i] = arr[i] - 1;\n")
  assert_true(out.contains("arr[i]--") || out.contains("--"))
  assert_false(out.contains("= arr[i] - 1"))
}

///|
test "peephole: arr[i] = arr[i] + n collapses to arr[i] += n" {
  let out = peep_one("arr[i] = arr[i] + 5;\n")
  assert_true(out.contains("arr[i] += 5") || out.contains("+="))
  assert_false(out.contains("= arr[i] + 5"))
}

///|
test "peephole: !(a === b) folds to a !== b" {
  let out = peep_one("const r = !(a === b);\n")
  assert_true(out.contains("!=="), "expected !== but got: \{out}")
  assert_false(out.contains("==="))
}

///|
test "peephole: !(a !== b) folds to a === b" {
  let out = peep_one("const r = !(a !== b);\n")
  assert_true(out.contains("==="), "expected === but got: \{out}")
  assert_false(out.contains("!=="))
}

///|
test "peephole: !(a < b) folds to a >= b" {
  let out = peep_one("const r = !(a < b);\n")
  assert_true(out.contains(">="), "expected >= but got: \{out}")
  assert_false(out.contains("<"))
}

///|
test "minify emit: trailing semicolon stripped from bundle output" {
  // In minify mode the last statement should NOT end with `;` — it's
  // syntactically optional and saves 1 byte per bundle.
  let out = minify_one("const x = 1;\n")
  assert_false(out.has_suffix(";"), "expected no trailing semicolon, got: \{out}")
}

///|
test "minify emit: string with double-quote uses single-quote wrapper" {
  // `x = "hello \"world\""` (with escapes) → `x='hello "world"'` (no escapes).
  // Single quotes are shorter when the string contains double quotes.
  let out = minify_one("const x = \"hello \\\"world\\\"\";\n")
  assert_true(out.contains("'hello \"world\"'"), "expected single-quoted string, got: \{out}")
}

///|
test "minify emit: string with single-quote uses double-quote wrapper" {
  // `x = 'it\'s fine'` → `x="it's fine"` — double quotes are shorter.
  let out = minify_one("const x = \"it's fine\";\n")
  assert_true(out.contains("\"it's fine\""), "expected double-quoted string, got: \{out}")
}

///|
test "minify emit: string with no quotes keeps double-quote wrapper" {
  let out = minify_one("const x = \"hello world\";\n")
  assert_true(out.contains("\"hello world\""), "expected double-quoted string, got: \{out}")
}

///|
test "minify emit: Number.POSITIVE_INFINITY folds to 1/0" {
  // Number.POSITIVE_INFINITY is folded by the constant folder to a NumberLit,
  // which in minify mode emits as `1/0` (3 bytes vs 8 for `Infinity`).
  let out = minify_one("const x = Number.POSITIVE_INFINITY;\n")
  assert_true(out.contains("1/0"), "expected 1/0, got: \{out}")
  assert_false(out.contains("Infinity"), "expected no Infinity, got: \{out}")
}

///|
test "minify emit: Number.NEGATIVE_INFINITY folds to -1/0" {
  let out = minify_one("const x = Number.NEGATIVE_INFINITY;\n")
  assert_true(out.contains("-1/0"), "expected -1/0, got: \{out}")
}

///|
test "minify emit: Number.NaN folds to 0/0" {
  let out = minify_one("const x = Number.NaN;\n")
  assert_true(out.contains("0/0"), "expected 0/0, got: \{out}")
}

