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
fn fold_minify_one(src : String) -> String raise {
  let block = @parser.parse_block_from_source(src)
  let folded = peephole_block(fold_block(block))
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
  // x = x + 1 → x += 1 → x++
  assert_true(out.contains("x++") || out.contains("x += 1"))
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
  // Use a body that can't be simplified to a concise arrow to test brace dropping.
  let out = minify_one("function f() { let x=1; return x+1; }\n")
  // The trailing `;` before `}` should be elided in minify mode. Arrow concise form
  // won't have braces at all, so check that either form is correct.
  assert_true(
    out.contains("return") && !out.contains("return x+1;}"),
    msg="expected trailing ; dropped before }, got: \{out}",
  )
}

///|
test "minify emit: 2-case all-return switch converts to if-else then ternary" {
  // Both cases end with `return`, so the switch → if/else chain → ternary.
  let out = minify_one(
    "function f(x) { switch (x) { case \"a\": return 1; case \"b\": return 2; } }\n",
  )
  // After conversion the output should have no switch/case keywords;
  // it folds to `return x==="a"?1:x==="b"?2:void 0` or similar.
  assert_false(out.contains("switch"), msg="expected no switch, got: \{out}")
  assert_true(out.contains("return"), msg="expected return, got: \{out}")
}

///|
test "minify emit: switch with fall-through stays as switch" {
  // Case "a" falls through to "b" — no terminator after case "a".
  let out = minify_one(
    "function f(x) { switch (x) { case \"a\": case \"b\": return 1; } }\n",
  )
  assert_true(
    out.contains("switch") || out.contains("case"),
    msg="expected switch/case, got: \{out}",
  )
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
  // Arrow concise body wraps objects in parens: `() => ({a:1})` — check for that too.
  let out = minify_one("function f() { return { a: 1 }; }\n")
  assert_true(
    out.contains("return{") || out.contains("({"),
    msg="expected return{ or ({ for object body, got: \{out}",
  )
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
test "minify emit: async arrow with single param skips parens" {
  // async (x) => ... and async x => ... both become async x=> in minify mode
  let out = minify_one("const f = async (x) => x + 1;\n")
  assert_false(out.contains("async (x)=>"))
  assert_true(out.contains("async"))
  assert_true(out.contains("x=>") || out.contains("x =>"))
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
  let break_count = out.split("break").collect().length() - 1
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
  assert_true(out.contains("!=="), msg="expected !== but got: \{out}")
  assert_false(out.contains("==="))
}

///|
test "peephole: !(a !== b) folds to a === b" {
  let out = peep_one("const r = !(a !== b);\n")
  assert_true(out.contains("==="), msg="expected === but got: \{out}")
  assert_false(out.contains("!=="))
}

///|
test "peephole: !(a < b) folds to a >= b when both sides are numbers" {
  // Written with bare names before, which is the unsound case: for
  // `a = undefined`, `!(a < b)` is true and `a >= b` is false, because
  // every NaN comparison is false. `.length` is a non-negative integer,
  // so this pair cannot go through NaN.
  let out = peep_one("const r = !(xs.length < ys.length);\n")
  assert_true(out.contains(">="), msg="expected >= but got: \{out}")
  assert_false(out.contains("<"))
}

///|
test "peephole: !(a < b) is kept when either side could be NaN" {
  let out = peep_one("const r = !(a < b);\n")
  assert_true(out.contains("!(a < b)"), msg="unsound rewrite: \{out}")
}

///|
test "peephole: !(a < b) is kept when the sides are a string and a number" {
  // `!("x" < 3)` is true; `"x" >= 3` is false.
  let out = peep_one("const r = !(\"x\" < n.length);\n")
  assert_false(out.contains(">="), msg="unsound rewrite: \{out}")
}

///|
test "peephole: !(a === b) still folds — equality never goes through NaN" {
  let out = peep_one("const r = !(a === b);\n")
  assert_true(out.contains("!=="), msg="expected !== but got: \{out}")
}

///|
test "minify emit: trailing semicolon stripped from bundle output" {
  // In minify mode the last statement should NOT end with `;` — it's
  // syntactically optional and saves 1 byte per bundle.
  let out = minify_one("const x = 1;\n")
  assert_false(
    out.has_suffix(";"),
    msg="expected no trailing semicolon, got: \{out}",
  )
}

///|
test "minify emit: string with double-quote uses single-quote wrapper" {
  // `x = "hello \"world\""` (with escapes) → `x='hello "world"'` (no escapes).
  // Single quotes are shorter when the string contains double quotes.
  let out = minify_one("const x = \"hello \\\"world\\\"\";\n")
  assert_true(
    out.contains("'hello \"world\"'"),
    msg="expected single-quoted string, got: \{out}",
  )
}

///|
test "minify emit: string with single-quote uses double-quote wrapper" {
  // `x = 'it\'s fine'` → `x="it's fine"` — double quotes are shorter.
  let out = minify_one("const x = \"it's fine\";\n")
  assert_true(
    out.contains("\"it's fine\""),
    msg="expected double-quoted string, got: \{out}",
  )
}

///|
test "minify emit: string with no quotes keeps double-quote wrapper" {
  let out = minify_one("const x = \"hello world\";\n")
  assert_true(
    out.contains("\"hello world\""),
    msg="expected double-quoted string, got: \{out}",
  )
}

///|
test "minify emit: Number.POSITIVE_INFINITY folds to 1/0" {
  // Number.POSITIVE_INFINITY is folded by the constant folder to a NumberLit,
  // which in minify mode emits as `1/0` (3 bytes vs 8 for `Infinity`).
  let out = fold_minify_one("const x = Number.POSITIVE_INFINITY;\n")
  assert_true(out.contains("1/0"), msg="expected 1/0, got: \{out}")
  assert_false(
    out.contains("Infinity"),
    msg="expected no Infinity, got: \{out}",
  )
}

///|
test "minify emit: Number.NEGATIVE_INFINITY folds to -1/0" {
  let out = fold_minify_one("const x = Number.NEGATIVE_INFINITY;\n")
  assert_true(out.contains("-1/0"), msg="expected -1/0, got: \{out}")
}

///|
test "minify emit: Number.NaN folds to 0/0" {
  let out = fold_minify_one("const x = Number.NaN;\n")
  assert_true(out.contains("0/0"), msg="expected 0/0, got: \{out}")
}

///|
test "peephole: x===null||x===undefined folds to x==null" {
  let out = peep_one("const r = x === null || x === undefined;\n")
  assert_true(out.contains("== null"), msg="expected x == null, got: \{out}")
  assert_false(
    out.contains("=== null"),
    msg="expected no === null, got: \{out}",
  )
  assert_false(
    out.contains("undefined"),
    msg="expected no undefined, got: \{out}",
  )
}

///|
test "peephole: x===undefined||x===null folds to x==null (reversed order)" {
  let out = peep_one("const r = x === undefined || x === null;\n")
  assert_true(out.contains("== null"), msg="expected x == null, got: \{out}")
}

///|
test "peephole: x!==null&&x!==undefined folds to x!=null" {
  let out = peep_one("const r = x !== null && x !== undefined;\n")
  assert_true(out.contains("!= null"), msg="expected x != null, got: \{out}")
  assert_false(
    out.contains("!== null"),
    msg="expected no !== null, got: \{out}",
  )
}

///|
test "peephole: null===x||undefined===x folds to x==null (LHS sentinels)" {
  let out = peep_one("const r = null === x || undefined === x;\n")
  assert_true(out.contains("== null"), msg="expected == null, got: \{out}")
}

///|
test "peephole: Number(x) folds to +x" {
  let out = peep_one("const r = Number(x);\n")
  assert_true(out.contains("+x"), msg="expected +x, got: \{out}")
  assert_false(out.contains("Number("), msg="expected no Number(, got: \{out}")
}

///|
test "peephole: Boolean(x) folds to !!x" {
  let out = peep_one("const r = Boolean(x);\n")
  assert_true(out.contains("!!x"), msg="expected !!x, got: \{out}")
  assert_false(
    out.contains("Boolean("),
    msg="expected no Boolean(, got: \{out}",
  )
}

///|
test "peephole: Number() with 0 args not folded" {
  let out = peep_one("const r = Number();\n")
  assert_true(out.contains("Number()"), msg="expected Number(), got: \{out}")
}

///|
test "peephole: !!(x===y) folds to x===y (double negation on comparison)" {
  let out = peep_one("const r = !!(x === y);\n")
  assert_true(out.contains("x === y"), msg="expected x === y, got: \{out}")
  assert_false(out.contains("!!"), msg="expected no !!, got: \{out}")
}

///|
test "peephole: Boolean(x===y) chain: Boolean→!! then !!→comparison" {
  // Boolean(x===y) → !!(x===y) → x===y
  let out = peep_one("const r = Boolean(x === y);\n")
  assert_true(out.contains("x === y"), msg="expected x === y, got: \{out}")
  assert_false(out.contains("Boolean"), msg="expected no Boolean, got: \{out}")
  assert_false(out.contains("!!"), msg="expected no !!, got: \{out}")
}

///|
test "minify emit: x[\"prop\"] emits as x.prop when key is valid ident" {
  let out = minify_one("const r = obj[\"hello\"];\n")
  assert_true(out.contains("obj.hello"), msg="expected obj.hello, got: \{out}")
  assert_false(
    out.contains("[\"hello\"]"),
    msg="expected no bracket form, got: \{out}",
  )
}

///|
test "minify emit: x[\"123\"] stays as bracket form (non-ident key)" {
  let out = minify_one("const r = obj[\"123\"];\n")
  assert_true(out.contains("["), msg="expected bracket form, got: \{out}")
}

///|
test "pretty emit: x[\"prop\"] stays as bracket form" {
  // In pretty mode, keep x["prop"] to avoid surprising users.
  let out = peep_one("const r = obj[\"hello\"];\n")
  assert_true(
    out.contains("[\"hello\"]"),
    msg="expected bracket form, got: \{out}",
  )
}

///|
test "peephole: arr.length === 0 keeps the comparison" {
  // Removed with its three siblings: `{ length: undefined }` makes
  // `=== 0` false while `!x.length` is true.
  let out = peep_one("const r = arr.length === 0;\n")
  assert_true(out.contains("=== 0"), msg="rewrote it: \{out}")
  let flipped = peep_one("const r = 0 === arr.length;\n")
  assert_true(flipped.contains("==="), msg="rewrote it: \{flipped}")
}

///|
test "minify emit: -0.5 emits as -.5 (drop leading zero in negative decimal)" {
  let out = minify_one("const x = -0.5;\n")
  assert_true(out.contains("-.5"), msg="expected -.5, got: \{out}")
  assert_false(out.contains("-0.5"), msg="expected no -0.5, got: \{out}")
}

///|
test "minify emit: x[\"prop\"] = v emits as x.prop = v" {
  let out = minify_one("obj[\"hello\"] = 42;\n")
  assert_true(
    out.contains("obj.hello=42"),
    msg="expected obj.hello=42, got: \{out}",
  )
}

///|
test "peephole: obj.prop===null||obj.prop===undefined folds to obj.prop==null" {
  let out = peep_one("const r = obj.prop === null || obj.prop === undefined;\n")
  assert_true(
    out.contains("obj.prop == null"),
    msg="expected obj.prop == null, got: \{out}",
  )
  assert_false(out.contains("==="), msg="expected no ===, got: \{out}")
}

///|
test "minify emit: trailing return; dropped from function body" {
  let e = Emitter::new(pretty=false)
  let block = @parser.parse_block_from_source(
    "function foo() { doSomething(); return; }\n",
  )
  for s in block.stmts {
    try_emit_function_decl(e, s) |> ignore
  }
  let out = e.to_string()
  assert_false(
    out.contains("return"),
    msg="expected no trailing return, got: \{out}",
  )
  assert_true(
    out.contains("doSomething()"),
    msg="expected doSomething(), got: \{out}",
  )
}

///|
test "peephole: if(c) return a; else return b; folds to return c?a:b" {
  let out = peep_one("function f(c,a,b){if(c){return a;}else{return b;}}")
  assert_true(out.contains("?"), msg="expected ternary, got: \{out}")
  assert_false(out.contains("if"), msg="expected no if, got: \{out}")
}

///|
test "peephole: if(c) expr; (no else) folds to c&&expr" {
  let out = peep_one("if(x){doSomething();}")
  assert_true(out.contains("&&"), msg="expected &&, got: \{out}")
  assert_false(out.contains("if"), msg="expected no if, got: \{out}")
}

///|
test "peephole: if(c) x=a; else x=b; folds to x=c?a:b" {
  let out = peep_one("if(c){x=a;}else{x=b;}")
  assert_true(out.contains("?"), msg="expected ternary, got: \{out}")
  assert_false(out.contains("if"), msg="expected no if, got: \{out}")
}

///|
test "peephole: if(c) expr_a; else expr_b; folds to c?expr_a:expr_b" {
  let out = peep_one("if(c){foo();}else{bar();}")
  assert_true(out.contains("?"), msg="expected ternary, got: \{out}")
  assert_false(out.contains("if"), msg="expected no if, got: \{out}")
}

///|
test "peephole: if(c) return a; return b; folds to return c?a:b (guard pattern)" {
  let out = peep_one("function f(c,a,b){if(c){return a;} return b;}")
  assert_true(out.contains("?"), msg="expected ternary, got: \{out}")
  assert_false(out.contains("if"), msg="expected no if, got: \{out}")
}

///|
test "peephole: dead code after return is eliminated" {
  let out = peep_one("function f(){return 1; x=2; y=3;}")
  assert_false(
    out.contains("x="),
    msg="expected dead code dropped, got: \{out}",
  )
  assert_false(
    out.contains("y="),
    msg="expected dead code dropped, got: \{out}",
  )
}

///|
test "peephole: c?!0:!1 folds to !!c (4 bytes saved)" {
  let out = minify_one("const r = x > 0 ? true : false;\n")
  assert_true(out.contains("!!("), msg="expected !!(x>0), got: \{out}")
  assert_false(out.contains("?"), msg="expected no ternary, got: \{out}")
}

///|
test "peephole: c?!1:!0 folds to !c" {
  let out = minify_one("const r = x > 0 ? false : true;\n")
  assert_true(out.contains("!("), msg="expected !(x>0), got: \{out}")
  assert_false(out.contains("?"), msg="expected no ternary, got: \{out}")
}

///|
test "peephole: (x>0)?true:false folds all the way to (x>0)" {
  let out = minify_one("const r = (x > 0) ? true : false;\n")
  // x>0 is already a bool, so !!(x>0) -> x>0
  assert_true(
    out.contains("x>0") || out.contains("0<x"),
    msg="expected simple comparison, got: \{out}",
  )
  assert_false(out.contains("?"), msg="expected no ternary, got: \{out}")
}

///|
test "peephole: arrow with block return folds to concise body" {
  let out = peep_one("const f = (x) => { return x + 1; };\n")
  assert_true(out.contains("=>"), msg="expected arrow, got: \{out}")
  assert_false(out.contains("return"), msg="expected no return, got: \{out}")
  assert_false(out.contains("{"), msg="expected no braces, got: \{out}")
}

///|
test "peephole: else after terminating if becomes sequential (removes else keyword)" {
  let out = peep_one("function f(){if(x){doA();return;}else{doB();}}")
  assert_false(out.contains("else"), msg="expected no else, got: \{out}")
  assert_true(
    out.contains("doA") && out.contains("doB"),
    msg="expected both branches, got: \{out}",
  )
}

///|
test "peephole: complex if chain optimization" {
  // if(a){doA();return x;} else { if(b){return y;} else {return z;}}
  // After else-removal: if(a){doA();return x;} if(b){return y;} return z;
  // Then guard-ternary: if(a){doA();return x;} return b?y:z;
  let out = peep_one(
    "function f(a,b,x,y,z){if(a){doA();return x;}else{if(b){return y;}else{return z;}}}",
  )
  assert_false(
    out.contains("else"),
    msg="expected no else keywords, got: \{out}",
  )
}

///|
test "peephole: if(c){} else {stmts} inverts to if(!c){stmts}" {
  let out = peep_one("if(x){}else{doSomething();}")
  assert_false(out.contains("else"), msg="expected no else, got: \{out}")
  assert_true(
    out.contains("!x") || out.contains("!"),
    msg="expected negation, got: \{out}",
  )
  assert_true(
    out.contains("doSomething"),
    msg="expected doSomething, got: \{out}",
  )
}

///|
test "peephole: x!=null?x:y folds to x??y (nullish coalescing)" {
  // After x!==null&&x!==undefined → x!=null (already done),
  // x!=null?x:y → x??y saves ~8 bytes
  let out = peep_one(
    "const r = x !== null && x !== undefined ? x : defaultVal;\n",
  )
  assert_true(out.contains("??"), msg="expected ??, got: \{out}")
  assert_false(out.contains("!=="), msg="expected no !==, got: \{out}")
}

///|
test "peephole: let x = expr; return x; folds to return expr;" {
  let out = peep_one("function f(a){let r=a+1;return r;}")
  // FuncExpr is converted to ArrowFunc, so the body may be a concise arrow (no return keyword).
  // Either `return a + 1` (in a block body) or `a + 1` (in a concise arrow body) is correct.
  assert_true(
    out.contains("a + 1") || out.contains("a+1"),
    msg="expected folded expression, got: \{out}",
  )
  assert_false(out.contains("let r"), msg="expected no temp var, got: \{out}")
}

///|
test "peephole: const x = expr; return x; folds to return expr;" {
  let out = peep_one("function f(a){const r=a*2;return r;}")
  assert_false(
    out.contains("let r") || out.contains("const r"),
    msg="expected no temp var, got: \{out}",
  )
}

///|
test "peephole: three-way if chain collapses to nested ternary" {
  let out = peep_one(
    "function f(x){if(x<0)return\"neg\";if(x===0)return\"zero\";return\"pos\";}",
  )
  assert_true(out.contains("?"), msg="expected ternary, got: \{out}")
  // Should not have any if statements remaining
  assert_false(out.contains("if"), msg="expected no if, got: \{out}")
}

///|
test "peephole: Math.pow(x, y) folds to x**y" {
  let out = peep_one("const r = Math.pow(x, 2);")
  assert_true(out.contains("**"), msg="expected **, got: \{out}")
  assert_false(
    out.contains("Math.pow"),
    msg="expected no Math.pow, got: \{out}",
  )
}

///|
test "peephole: this.prop = void 0; this.prop = val; → this.prop = val;" {
  let out = peep_one("function ctor(x){this.x=void 0;this.x=x}")
  assert_false(out.contains("void 0"), msg="expected no void 0, got: \{out}")
  // peep_one uses pretty mode, so assignment appears with spaces
  assert_true(
    out.contains("this.x"),
    msg="expected this.x assignment, got: \{out}",
  )
}

///|
test "peephole: multi-field class drops all void-0 field initializers" {
  let out = peep_one(
    "function Foo(x,y){this.x=void 0;this.y=void 0;this.x=x;this.y=y}",
  )
  assert_false(out.contains("void 0"), msg="expected no void 0, got: \{out}")
  assert_true(out.contains("this.x"), msg="expected this.x, got: \{out}")
  assert_true(out.contains("this.y"), msg="expected this.y, got: \{out}")
}

///|
test "peephole: x != null ? x.prop : void 0 → x?.prop" {
  // TypeScript emits this pattern when downleveling optional chaining.
  let out = minify_one("const r = x != null ? x.prop : void 0;")
  assert_true(out.contains("?."), msg="expected optional chain, got: \{out}")
  assert_false(out.contains("!="), msg="expected no != null check, got: \{out}")
}

///|
test "peephole: x != null ? x[key] : void 0 → x?.[key]" {
  let out = minify_one("const r = x != null ? x[key] : void 0;")
  assert_true(
    out.contains("?.["),
    msg="expected optional index chain, got: \{out}",
  )
}

///|
test "peephole: x == null ? fallback : x → x ?? fallback" {
  // Flipped form of nullish coalescing.
  let out = minify_one("const r = x == null ? 'default' : x;")
  assert_true(out.contains("??"), msg="expected ??, got: \{out}")
  assert_false(out.contains("=="), msg="expected no == null check, got: \{out}")
}

///|
test "peephole: Array.from(x) folds only when x is provably iterable" {
  // `Array.from` accepts an array-LIKE; a spread needs an ITERABLE.
  // `Array.from({ length: 256 })` is 256 `undefined`s and
  // `[...{ length: 256 }]` throws, which is how typebox's bundle died on
  // load. A bare `items` proves nothing, so the call stays.
  let kept = peep_one("const r = Array.from(items);")
  assert_true(
    kept.contains("Array.from"),
    msg="an unprovable receiver must keep the call, got: \{kept}",
  )
  // A string literal and a `new Set(…)` name their own type.
  let folded = peep_one("const r = Array.from(new Set(xs));")
  assert_true(
    folded.contains("[..."),
    msg="expected spread array, got: \{folded}",
  )
  assert_false(
    folded.contains("Array.from"),
    msg="expected no Array.from, got: \{folded}",
  )
}

///|
test "peephole: Object.assign({}, a) folds to {...a}" {
  let out = minify_one("const r = Object.assign({}, src);")
  assert_true(out.contains("{..."), msg="expected spread, got: \{out}")
  assert_false(
    out.contains("Object.assign"),
    msg="expected no Object.assign, got: \{out}",
  )
}

///|
test "peephole: Object.assign({}, a, b) folds to {...a,...b}" {
  let out = minify_one("const r = Object.assign({}, a, b);")
  assert_true(out.contains("{..."), msg="expected spread, got: \{out}")
  assert_false(
    out.contains("Object.assign"),
    msg="expected no Object.assign, got: \{out}",
  )
}

///|
test "peephole: c ? (x = a) : (x = b) → x = c ? a : b" {
  let out = minify_one("const r = cond ? (x = 1) : (x = 2);")
  // The assignment should be hoisted outside the ternary.
  assert_true(
    out.contains("x="),
    msg="expected hoisted assignment, got: \{out}",
  )
}

///|
test "peephole: x ? x : y → x || y" {
  let out = minify_one("const r = x ? x : fallback;")
  assert_true(out.contains("||"), msg="expected ||, got: \{out}")
  assert_false(out.contains("?"), msg="expected no ternary, got: \{out}")
}

///|
test "peephole: x ? y : x → x && y" {
  let out = minify_one("const r = x ? action : x;")
  assert_true(out.contains("&&"), msg="expected &&, got: \{out}")
  assert_false(out.contains("?"), msg="expected no ternary, got: \{out}")
}

///|
test "peephole: String(x) folds to \"\"+x only for a string or number" {
  // `String` calls ToString; `+` calls ToPrimitive with a DEFAULT hint.
  // `String(sym)` is "Symbol(s)" and `"" + sym` throws, and any object
  // with both `valueOf` and `toString` differs quietly.
  let known = minify_one("const s = String(n.length);")
  assert_true(known.contains("\"\""), msg="missed the saving: \{known}")
  let unknown = minify_one("const s = String(x);")
  assert_true(unknown.contains("String("), msg="unsound rewrite: \{unknown}")
}

///|
test "peephole: x.y != null ? x.y.z : void 0 → x.y?.z (chained optional)" {
  // Extended exprs_eq allows PropAccess chain comparison.
  let out = minify_one("const r = x.y != null ? x.y.z : void 0;")
  assert_true(out.contains("?."), msg="expected optional chain, got: \{out}")
}

///|
test "peephole: `${s}` folds to \"\"+s only when the hole is a string" {
  // Template interpolation is ToString; `+` is ToPrimitive with a
  // DEFAULT hint and so prefers `valueOf`. For an object with both they
  // disagree, and for a Symbol one throws. So the hole has to be a
  // string already.
  let known = minify_one("const s = `${\"a\" + b}`;")
  assert_false(known.contains("`"), msg="missed the saving: \{known}")
  let unknown = minify_one("const s = `${x}`;")
  assert_true(unknown.contains("`"), msg="unsound rewrite: \{unknown}")
}

///|
test "peephole: Array.prototype.slice.call(x) keeps the slice" {
  // `slice` accepts any array-LIKE; a spread needs an ITERABLE. So
  // `Array.prototype.slice.call(0, 0)` is `[]` where `[...0]` throws,
  // and the same holds for any `{ length, 0: … }` bag.
  let out = minify_one("const r = Array.prototype.slice.call(args);")
  assert_true(out.contains("slice"), msg="rewrote it: \{out}")
}

///|
test "peephole: new Array(0) folds to []" {
  let out = minify_one("const r = new Array(0);")
  assert_true(out.contains("=[]"), msg="expected [], got: \{out}")
  assert_false(out.contains("Array"), msg="expected no Array, got: \{out}")
}

///|
test "peephole: new Array() folds to []" {
  let out = minify_one("const r = new Array();")
  assert_true(out.contains("=[]"), msg="expected [], got: \{out}")
  assert_false(out.contains("Array"), msg="expected no Array, got: \{out}")
}

///|
test "peephole: new Object() folds to {}" {
  let out = minify_one("const r = new Object();")
  assert_true(out.contains("={}"), msg="expected {}, got: \{out}")
  assert_false(out.contains("Object"), msg="expected no Object, got: \{out}")
}

///|
test "peephole: [].concat(a, b) is left alone for non-literal arguments" {
  // `concat` APPENDS a non-array as a single element, so
  // `[].concat(undefined)` is `[undefined]` while `[...undefined]`
  // throws. Only array literals are provably spreadable.
  let out = minify_one("const r = [].concat(a, b);")
  assert_true(out.contains("concat"), msg="expected concat kept, got: \{out}")
}

///|
test "peephole: [].concat([1,2], [3,4]) flattens to [1,2,3,4]" {
  let out = minify_one("const r = [].concat([1, 2], [3, 4]);")
  assert_true(
    out.contains("1,2,3,4"),
    msg="expected flattened array, got: \{out}",
  )
  assert_false(out.contains("concat"), msg="expected no concat, got: \{out}")
}

///|
test "peephole: !!x ? a : b strips double negation in condition" {
  let out = minify_one("const r = !!x ? a : b;")
  assert_false(out.contains("!!"), msg="expected no !!, got: \{out}")
  assert_true(out.contains("?"), msg="expected ternary kept, got: \{out}")
}

///|
test "peephole: x && x.prop keeps && (not converted to x?.prop — falsy semantics differ)" {
  // `x && x.prop` short-circuits on ANY falsy value and returns x when falsy.
  // `x?.prop` short-circuits only on null/undefined and returns undefined.
  // Converting would break code that checks the return value against null.
  let out = minify_one("const r = x && x.prop;")
  assert_true(out.contains("&&"), msg="expected && kept, got: \{out}")
}

///|
test "peephole: x && x[key] keeps && (not converted to x?.[key])" {
  let out = minify_one("const r = x && x[key];")
  assert_true(out.contains("&&"), msg="expected && kept, got: \{out}")
}

///|
test "peephole: x && x.method(a) keeps && (not converted to x?.method(a))" {
  let out = minify_one("const r = x && x.method(a);")
  assert_true(out.contains("&&"), msg="expected && kept, got: \{out}")
}

///|
test "peephole: a.b.c === null || a.b.c === undefined → a.b.c == null" {
  let out = minify_one("const r = a.b.c === null || a.b.c === undefined;")
  assert_true(out.contains("==null"), msg="expected ==null, got: \{out}")
  assert_false(out.contains("==="), msg="expected no ===, got: \{out}")
}

///|
test "peephole: empty trailing default case is dropped from switch" {
  let out = minify_one("switch(x){ case 1: doA(); break; default: break; }")
  assert_false(out.contains("default"), msg="expected no default, got: \{out}")
}

///|
test "peephole: {...{a:1}} flattens object spread of literal" {
  let out = minify_one("const r = { ...{a: 1, b: 2} };")
  assert_false(out.contains("..."), msg="expected no spread, got: \{out}")
  assert_true(out.contains("a:"), msg="expected a: entry, got: \{out}")
}

///|
test "peephole: [...a, ...[1,2], ...b] flattens literal array spread" {
  let out = minify_one("const r = [...a, ...[1, 2], ...b];")
  // The ...[1,2] should be flattened to 1,2 inline.
  assert_true(out.contains("1,2"), msg="expected 1,2 inlined, got: \{out}")
  assert_false(out.contains("...["), msg="expected no ...[, got: \{out}")
}

///|
test "peephole: x == null ? void 0 : x.prop → x?.prop (flipped optional chain)" {
  let out = minify_one("const r = x == null ? void 0 : x.prop;")
  assert_true(out.contains("?."), msg="expected optional chain, got: \{out}")
  assert_false(out.contains("==null"), msg="expected no ==null, got: \{out}")
}

///|
test "peephole: x == null ? void 0 : x.method(a) keeps ternary (MethodCall emit wrong for optional access)" {
  // `OptionalChain(MethodCall)` emits `x.method?.(a)`, not `x?.method(a)`.
  // `x.method?.(a)` throws when x is undefined — not semantically equivalent.
  let out = minify_one("const r = x == null ? void 0 : x.method(a);")
  assert_true(out.contains("?"), msg="expected ? kept, got: \{out}")
}

///|
test "peephole: if (c) { stmts } else {} drops empty else" {
  let out = minify_one("if (x) { doA(); } else {}")
  assert_false(out.contains("else"), msg="expected no else, got: \{out}")
}

///|
test "peephole: length comparisons are NOT rewritten to truthiness" {
  // These four rewrites were removed. `.length` is only a non-negative
  // number when the receiver is an array or a string, and peephole has
  // no types: `(0).length` is `undefined`, so `undefined <= 0` is false
  // while `!undefined` is true, and `{ length: -1 }` makes `> 0` false
  // while `!!(-1)` is true. Found by
  // `scripts/verify_rule_equivalence.mjs`.
  let gt = minify_one("const r = arr.length > 0;")
  assert_true(gt.contains(">"), msg="rewrote length > 0: \{gt}")
  let le = minify_one("const r = arr.length <= 0;")
  assert_true(le.contains("<="), msg="rewrote length <= 0: \{le}")
  let ne = minify_one("const r = arr.length !== 0;")
  assert_true(ne.contains("!=="), msg="rewrote length !== 0: \{ne}")
  let eq = minify_one("const r = arr.size === 0;")
  assert_true(eq.contains("==="), msg="rewrote size === 0: \{eq}")
}

///|
test "peephole: x != null ? x() : void 0 → x?.() optional call" {
  let out = minify_one("const r = x != null ? x() : void 0;")
  assert_true(out.contains("?."), msg="expected optional chain, got: \{out}")
}

///|
test "peephole: new Error(msg) drops new keyword" {
  let out = minify_one("throw new Error('oops');")
  assert_false(out.contains("new"), msg="expected no new, got: \{out}")
  assert_true(out.contains("Error("), msg="expected Error(, got: \{out}")
}

///|
test "peephole: new TypeError(msg) drops new keyword" {
  let out = minify_one("throw new TypeError('bad');")
  assert_false(out.contains("new"), msg="expected no new, got: \{out}")
}

///|
test "peephole: fn.call(null, a, b) → fn(a, b) strips null-this call" {
  let out = minify_one("const r = fn.call(null, a, b);")
  assert_false(out.contains(".call("), msg="expected no .call, got: \{out}")
  assert_true(out.contains("fn("), msg="expected fn(, got: \{out}")
}

///|
test "peephole: fn.apply(null, args) needs a provably iterable args list" {
  // `apply` takes an array-LIKE, and also `null` / `undefined` meaning
  // "no arguments": `f.apply(null, undefined)` calls `f()` where
  // `f(...undefined)` throws. A bare `args` is not a proof.
  let kept = minify_one("const r = fn.apply(null, args);")
  assert_true(
    kept.contains(".apply("),
    msg="an unprovable args list must keep .apply, got: \{kept}",
  )
  let folded = minify_one("const r = fn.apply(null, [a, b]);")
  assert_false(
    folded.contains(".apply("),
    msg="expected no .apply, got: \{folded}",
  )
}

///|
test "peephole: !void 0 → !0 (saves 3 bytes)" {
  let out = minify_one("const r = !void 0;")
  assert_false(out.contains("void"), msg="expected no void, got: \{out}")
  assert_true(out.contains("!0"), msg="expected !0, got: \{out}")
}

///|
test "peephole: void f() as statement drops void" {
  let out = minify_one("void sideEffect();")
  assert_false(out.contains("void"), msg="expected no void, got: \{out}")
  assert_true(
    out.contains("sideEffect"),
    msg="expected sideEffect, got: \{out}",
  )
}

///|
test "peephole: typeof x === 'undefined' keeps typeof for bare Var (undeclared global guard)" {
  // Bare `typeof x` must NOT be converted: `x` might be an undeclared global
  // (e.g. `typeof window !== "undefined"` for feature detection).
  let out = minify_one(
    (
      #|const r = typeof x === "undefined";
    ),
  )
  assert_true(out.contains("typeof"), msg="expected typeof kept, got: \{out}")
}

///|
test "peephole: typeof x !== 'undefined' keeps typeof for bare Var (undeclared global guard)" {
  let out = minify_one(
    (
      #|const r = typeof x !== "undefined";
    ),
  )
  assert_true(out.contains("typeof"), msg="expected typeof kept, got: \{out}")
}

///|
test "peephole: 'undefined' === typeof x (swapped form) keeps typeof for bare Var" {
  let out = minify_one(
    (
      #|const r = "undefined" === typeof x;
    ),
  )
  assert_true(out.contains("typeof"), msg="expected typeof kept, got: \{out}")
}

///|
test "peephole: !x ? b : a → x ? a : b (flip branches)" {
  let out = minify_one("const r = !cond ? 1 : 2;")
  assert_false(
    out.contains("!cond"),
    msg="expected no negation in cond, got: \{out}",
  )
  assert_true(
    out.contains("cond?2:1") || out.contains("cond ? 2 : 1"),
    msg="expected flipped branches, got: \{out}",
  )
}

///|
test "peephole: template literal with no exprs → string literal" {
  let out = minify_one("const r = `hello world`;")
  assert_false(out.contains("`"), msg="expected no backticks, got: \{out}")
  assert_true(
    out.contains("\"hello world\"") || out.contains("'hello world'"),
    msg="expected string literal, got: \{out}",
  )
}

///|
test "peephole: Number.parseInt → parseInt" {
  let out = minify_one("const r = Number.parseInt(x, 10);")
  assert_false(
    out.contains("Number."),
    msg="expected no Number. prefix, got: \{out}",
  )
  assert_true(out.contains("parseInt"), msg="expected parseInt, got: \{out}")
}

///|
test "peephole: Number.parseFloat → parseFloat" {
  let out = minify_one("const r = Number.parseFloat(x);")
  assert_false(
    out.contains("Number."),
    msg="expected no Number. prefix, got: \{out}",
  )
  assert_true(
    out.contains("parseFloat"),
    msg="expected parseFloat, got: \{out}",
  )
}

///|
test "peephole: Array.prototype.slice.call(x, 0) keeps the slice" {
  let out = minify_one("const r = Array.prototype.slice.call(arr, 0);")
  assert_true(out.contains("slice"), msg="rewrote it: \{out}")
}

///|
test "peephole: {...x, ...{}} removes empty spread" {
  let out = minify_one("const r = {...x, ...{}};")
  // after flattening, the empty spread contributes nothing
  assert_false(out.contains("{}"), msg="expected no empty object, got: \{out}")
}

///|
test "peephole: Object.assign with non-empty literal target → spread" {
  let out = minify_one("const r = Object.assign({x:1}, a, b);")
  assert_false(
    out.contains("Object.assign"),
    msg="expected no Object.assign, got: \{out}",
  )
  assert_true(out.contains("x"), msg="expected x key, got: \{out}")
}

///|
test "peephole: single-case switch without default → if" {
  let out = minify_one("function f(){switch(x){case 'a':return 1;}}")
  assert_false(out.contains("switch"), msg="expected no switch, got: \{out}")
  assert_true(
    out.contains("if") || out.contains("==="),
    msg="expected if or ===, got: \{out}",
  )
}

///|
test "peephole: 2-case switch (case+default, return) → if/else then ternary" {
  let out = minify_one(
    "function f(){switch(x){case 'a':return 1;default:return 2;}}",
  )
  assert_false(out.contains("switch"), msg="expected no switch, got: \{out}")
  // After if+else folding: return x==='a'?1:2
  assert_true(out.contains("?"), msg="expected ternary, got: \{out}")
}

///|
test "emit: consecutive let declarations merged in minify mode" {
  // Use emit_block directly so the consecutive-merge logic fires.
  let block = @parser.parse_block_from_source(
    "let a = 1; let b = 2; let c = 3;",
  )
  let folded = peephole_block(block)
  let e = Emitter::new(pretty=false)
  emit_block(e, folded)
  let out = e.to_string()
  // Three separate `let` decls should become one `let a=1,b=2,c=3`
  // Verify only one `let` keyword appears (no second `let ` after comma separation)
  assert_false(
    out.contains("let a") && out.contains("let b"),
    msg="expected merged let, got: \{out}",
  )
  assert_true(
    out.contains("a") && out.contains("b") && out.contains("c"),
    msg="expected a,b,c, got: \{out}",
  )
}

///|
test "peephole: catch(e) where e unused → catch without binding" {
  let out = minify_one("try { x(); } catch (e) { fallback(); }")
  assert_false(
    out.contains("catch("),
    msg="expected no catch binding, got: \{out}",
  )
  assert_true(out.contains("catch"), msg="expected catch, got: \{out}")
  assert_true(out.contains("fallback"), msg="expected fallback, got: \{out}")
}

///|
test "peephole: catch(e) where e is used → binding kept" {
  let out = minify_one("try { x(); } catch (e) { console.log(e); }")
  assert_true(
    out.contains("catch("),
    msg="expected catch binding kept, got: \{out}",
  )
}

///|
test "peephole: prefixed template folds only when the hole is a string" {
  let known = minify_one("const r = `prefix${\"a\" + x}`;")
  assert_false(known.contains("`"), msg="missed the saving: \{known}")
  let unknown = minify_one("const r = `prefix${x}`;")
  assert_true(unknown.contains("`"), msg="unsound rewrite: \{unknown}")
}

///|
test "peephole: +new Date() → Date.now()" {
  let out = minify_one("const t = +new Date();")
  assert_false(
    out.contains("new Date"),
    msg="expected no new Date, got: \{out}",
  )
  assert_true(
    out.contains("Date.now()"),
    msg="expected Date.now(), got: \{out}",
  )
}

///|
test "peephole: arr.slice(0) is left alone" {
  // `slice` is a method on Array AND on String, and they return
  // different kinds of thing: `"ab".slice(0)` is `"ab"`, `[..."ab"]` is
  // `["a", "b"]`. Nothing here proves the receiver is an array.
  let out = minify_one("const r = arr.slice(0);")
  assert_true(out.contains("slice"), msg="expected .slice kept, got: \{out}")
}

///|
test "emit: consecutive const and let merged as let in minify mode" {
  let block = @parser.parse_block_from_source("const a = 1; let b = 2;")
  let folded = peephole_block(block)
  let e = Emitter::new(pretty=false)
  emit_block(e, folded)
  let out = e.to_string()
  // Both should be merged as `let a=1,b=2`
  assert_false(
    out.contains("const"),
    msg="expected no const in minify mode, got: \{out}",
  )
  assert_false(
    out.contains("let a") && out.contains("let b"),
    msg="expected merged, got: \{out}",
  )
}

///|
test "peephole: nested if(c){if(d){...}} → if(c&&d){...}" {
  let out = minify_one("if (a) { if (b) { doWork(); } }")
  // Should collapse to a single if with `a&&b` condition
  assert_true(
    out.contains("&&") || (out.contains("a") && out.contains("b")),
    msg="expected merged condition, got: \{out}",
  )
  // Should not have nested if structure
  let if_count = {
    let mut n = 0
    for i = 0; i < out.length() - 1; i = i + 1 {
      if out[i] == 'i' && out[i + 1] == 'f' {
        n = n + 1
      }
    }
    n
  }
  assert_true(if_count <= 1, msg="expected at most one if, got: \{out}")
}

///|
test "peephole: if(x==null){x=y} → x??=y" {
  let out = minify_one("if (x == null) { x = y; }")
  assert_true(out.contains("??="), msg="expected ??= operator, got: \{out}")
  assert_false(out.contains("if"), msg="expected no if, got: \{out}")
}

///|
test "peephole: b===true → b, b===false → !b for a boolean operand" {
  // These used to be written with a bare `x`, which is unsound: for
  // `x = 1`, `x === true` is false while `x` is truthy. The rewrite is
  // gated on the operand being provably boolean now, so the cases have
  // to supply one.
  let r1 = minify_one("if ((a < b) === true) y();")
  assert_false(r1.contains("==="), msg="expected no === after fold, got: \{r1}")
  assert_false(
    r1.contains("true") || r1.contains("!0"),
    msg="expected no bool lit, got: \{r1}",
  )
  let r2 = minify_one("if ((a < b) === false) y();")
  assert_false(
    r2.contains("==="),
    msg="expected no === in false-fold, got: \{r2}",
  )
  assert_true(
    r2.contains("!(a<b)"),
    msg="expected !(a<b) from ===false, got: \{r2}",
  )
}

///|
test "peephole: b!==true → !b, b!==false → b for a boolean operand" {
  let r1 = minify_one("if ((a < b) !== true) y();")
  assert_false(r1.contains("!=="), msg="expected no !== after fold, got: \{r1}")
  assert_true(
    r1.contains("!(a<b)"),
    msg="expected !(a<b) from !==true, got: \{r1}",
  )
  let r2 = minify_one("if ((a < b) !== false) y();")
  assert_false(r2.contains("!=="), msg="expected no !== after fold, got: \{r2}")
  assert_false(
    r2.contains("false") || r2.contains("!1"),
    msg="expected no bool lit, got: \{r2}",
  )
}

///|
test "peephole: Object.prototype.hasOwnProperty.call → Object.hasOwn" {
  let r1 = minify_one("Object.prototype.hasOwnProperty.call(obj, key);")
  assert_true(
    r1.contains("Object.hasOwn"),
    msg="expected Object.hasOwn, got: \{r1}",
  )
  assert_false(
    r1.contains("hasOwnProperty"),
    msg="expected no hasOwnProperty, got: \{r1}",
  )
  let r2 = minify_one("({}).hasOwnProperty.call(obj, key);")
  assert_true(
    r2.contains("Object.hasOwn"),
    msg="expected Object.hasOwn for {}.form, got: \{r2}",
  )
}

///|
test "peephole: x.hasOwnProperty(key) keeps the receiver's own method" {
  // The rewrite replaced whatever `obj.hasOwnProperty` resolves to with
  // the built-in, so an object that defines its own — a parsed JSON
  // payload, a config bag — stopped calling it. The
  // `Object.prototype.hasOwnProperty.call(obj, key)` form names the
  // built-in explicitly and is still folded.
  let r = minify_one("obj.hasOwnProperty(key);")
  assert_true(r.contains("obj.hasOwnProperty"), msg="rewrote it: \{r}")
  assert_false(r.contains("XXXnever"), msg="unused, got: \{r}")
}

///|
test "peephole: multi-case all-return switch → if-else chain" {
  let out = minify_one(
    "function f(x) { switch (x) { case 1: return \"a\"; case 2: return \"b\"; case 3: return \"c\"; default: return \"d\"; } }\n",
  )
  assert_false(out.contains("switch"), msg="expected no switch, got: \{out}")
  // After switch→if-chain→ternary + FuncExpr→ArrowFunc, the function has a concise
  // arrow body (no `return` keyword). Check for ternary `?` as the structural indicator.
  assert_true(out.contains("?"), msg="expected ternary in output, got: \{out}")
}

///|
test "peephole: string literal concatenation folding" {
  let out = peep_one("const s = \"hello\" + \" \" + \"world\";")
  // Both adjacent literals should collapse to a single string
  assert_false(
    out.contains("\" + \""),
    msg="expected no adjacent string lits, got: \{out}",
  )
  assert_true(
    out.contains("\"hello world\""),
    msg="expected folded string, got: \{out}",
  )
}

///|
test "peephole: additive identity 0 + x → x only for a safe number" {
  // `undefined + 0` is `NaN`, `"a" + 0` is `"a0"`, and `-0 + 0` is `0`
  // where `-0` is `-0`. A collection size is a non-negative integer and
  // so is safe.
  let known = minify_one("const a = 0 + n.length;")
  assert_false(known.contains("0+"), msg="missed the saving: \{known}")
  let unknown = peep_one("const a = 0 + n;\n")
  assert_true(unknown.contains("0 + n"), msg="unsound fold: \{unknown}")
}

///|
test "peephole: integer arithmetic constant folding" {
  let out = peep_one("const a = 2 + 3;")
  assert_true(out.contains("5"), msg="expected 5, got: \{out}")
  assert_false(out.contains("2 +"), msg="expected folded result, got: \{out}")
}

///|
test "peephole: double negation stripped from if condition" {
  let out = minify_one("if (!!x) y();")
  assert_false(
    out.contains("!!"),
    msg="expected no !! in condition, got: \{out}",
  )
  assert_true(out.contains("x&&"), msg="expected x&&, got: \{out}")
}

///|
test "peephole: x.toString() is kept" {
  // `undefined.toString()` throws where `"" + undefined` does not, `+`
  // prefers `valueOf` over `toString`, and a Symbol is the other way
  // round again.
  let out = minify_one("const s = x.toString();")
  assert_true(out.contains("toString"), msg="rewrote it: \{out}")
}

///|
test "peephole: (0, fn)(args) indirect call → fn(args)" {
  let out = minify_one("(0, myFn)(a, b);")
  assert_false(
    out.contains("(0,"),
    msg="expected no (0, indirect call, got: \{out}",
  )
  assert_true(out.contains("myFn("), msg="expected direct call, got: \{out}")
}

///|
test "peephole: Array.prototype.METHOD.call(x, …) is left alone" {
  // Two ways apart, and the rewrite was on the wrong side of both. The
  // `.call` form names the built-in explicitly and reaches strings,
  // `arguments` and `{ length: 2, 0: "a", 1: "b" }`, none of which have
  // the method; and where the receiver DOES have a same-named method,
  // the rewrite calls that one instead of the built-in. `slice` was
  // already excluded here — it was the one instance somebody had hit.
  let out = minify_one("Array.prototype.forEach.call(arr, fn);")
  assert_true(
    out.contains("Array.prototype"),
    msg="expected Array.prototype kept, got: \{out}",
  )
}

///|
test "peephole: c ? expr : void 0 keeps ternary (c && expr has different falsy semantics)" {
  // `null ? x : void 0` returns undefined, but `null && x` returns null.
  // Code that checks `=== null` after the expression would silently misbehave.
  let out = minify_one("const a = x > 0 ? doSomething(x) : undefined;")
  assert_true(out.contains("?"), msg="expected ternary kept, got: \{out}")
}

///|
/// A function declaration after a `return` is not unreachable — it
/// hoists, so the code before the return can call it and `return f;` can
/// hand it out. `typescript.js` is built that way, and dropping those
/// left `return f` pointing at nothing: loading the minified compiler
/// threw `ReferenceError: d is not defined`.
test "peephole: a hoisted function after a terminator survives" {
  let files : Map[String, String] = {
    "entry.js": (
      #|var pick = (() => {
      #|  var chosen;
      #|  return getDefault;
      #|  function getDefault(a, b) {
      #|    return a < b ? -1 : 1;
      #|  }
      #|})();
      #|export function run(a, b) {
      #|  return pick(a, b);
      #|}
      #|
    ),
  }
  // Only the combination broke: mangle renames the declaration, and the
  // peephole pass is what dropped it.
  for
    opts in [
      BundleOptions::default().with_minify(true).with_mangle(true),
      BundleOptions::default()
      .with_minify(true)
      .with_fold(true)
      .with_mangle(true),
      BundleOptions::default().with_minify(true),
      BundleOptions::default().with_mangle(true),
    ] {
    match bundle_modules(files, "entry.js", opts) {
      // The declaration has to survive in SOME form — kept as a
      // declaration, or inlined into the `return` when it is used once.
      // Its body is the only place `-1` appears, and unlike a name it
      // does not move under mangling.
      Ok(out) => assert_true(out.js.contains("-1"))
      Err(e) => fail("bundle error: \{e}")
    }
  }
}

///|
test "peephole: genuinely unreachable code after a terminator still goes" {
  let files : Map[String, String] = {
    "entry.js": (
      #|export function f(a) {
      #|  return a + 1;
      #|  console.log("never");
      #|}
      #|
    ),
  }
  // `--fold` is the pass that drops unreachable statements; the point
  // here is that keeping hoisted declarations did not turn that off.
  let opts = BundleOptions::default().with_minify(true).with_fold(true)
  match bundle_modules(files, "entry.js", opts) {
    Ok(out) => assert_false(out.js.contains("never"))
    Err(e) => fail("bundle error: \{e}")
  }
}

///|
/// `let x = expr; return x;` collapses to `return expr;` — but not when
/// `expr` refers to `x`. A self-referential initializer is ordinary
/// JavaScript as long as the reference is deferred into a closure, and
/// TypeScript's compiler host is built exactly that way:
///
///     const compilerHost = {
///       getSourceFile: withCache(f => compilerHost.readFile(f)),
///     };
///     return compilerHost;
///
/// Folding it left the closure pointing at a name that no longer
/// existed. After mangling it was worse than a `ReferenceError`: the
/// short name now belonged to a different function, so every lib file
/// read silently came back empty and the minified compiler reported
/// `Cannot find name 'Math'` on correct input.
test "peephole: a self-referential initializer is not folded into the return" {
  let files : Map[String, String] = {
    "entry.js": (
      #|function makeHost(read) {
      #|  const host = {
      #|    readFile: read,
      #|    getSourceFile: (name) => host.readFile(name),
      #|  };
      #|  return host;
      #|}
      #|export function run() {
      #|  return makeHost((n) => "content:" + n).getSourceFile("a.ts");
      #|}
      #|
    ),
  }
  for
    opts in [
      BundleOptions::default().with_minify(true).with_mangle(true),
      BundleOptions::default()
      .with_minify(true)
      .with_fold(true)
      .with_mangle(true),
      BundleOptions::default().with_minify(true),
    ] {
    match bundle_modules(files, "entry.js", opts) {
      Ok(out) =>
        // The binding has to stay: something inside its own initializer
        // needs a name to reach it by.
        assert_true(out.js.contains("return") && out.js.contains("readFile"))
      Err(e) => fail("bundle error: \{e}")
    }
  }
}

///|
test "peephole: an ordinary tail declaration still folds" {
  let files : Map[String, String] = {
    "entry.js": (
      #|export function f(a) {
      #|  const total = a + 1;
      #|  return total;
      #|}
      #|
    ),
  }
  // The fold is reached on the post-mangle block, so this is the
  // combination that exercises it.
  let opts = BundleOptions::default().with_minify(true).with_mangle(true)
  match bundle_modules(files, "entry.js", opts) {
    Ok(out) =>
      assert_true(
        out.js.contains("return b+1") || out.js.contains("return a+1"),
      )
    Err(e) => fail("bundle error: \{e}")
  }
}

// ---------------------------------------------------------------
// `this` hidden inside a binding pattern
// ---------------------------------------------------------------
//
// The `function` -> arrow conversion is only sound when the body cannot
// observe the callee's `this`. Three separate walkers answered that
// question by reading a declaration's INITIALIZER and never its binding
// pattern, so a `this` reachable only from a destructuring default was
// invisible. `TypeScript`'s own `Version.prototype.with` is written
// exactly that way, and the minified compiler threw
// `Cannot read properties of undefined (reading 'major')` on it.
//
// These go through `bundle_modules` rather than `peephole_block`,
// because the conversion is gated on `f.name == ""` and the parser
// names an anonymous function expression `<anon>`. Only the mangler
// clears that, so the rule fires exactly once per pipeline — on the
// post-mangle peephole pass — and a test that calls `peephole_block`
// on parsed source passes no matter which way the gate is wired.

///|
fn bundle_min_mangled(src : String) -> String raise {
  let files : Map[String, String] = { "entry.js": src }
  let opts = BundleOptions::default().with_minify(true).with_mangle(true)
  match bundle_modules(files, "entry.js", opts) {
    Ok(out) => out.js
    Err(e) => fail("bundle error: \{e}")
  }
}

///|
test "peephole: `this` in a destructuring default blocks the arrow conversion" {
  let out = bundle_min_mangled(
    (
      #|export const obj = {};
      #|obj.m = function (o) {
      #|  let { major: v = this.major } = o;
      #|  return v;
      #|};
      #|
    ),
  )
  assert_false(out.contains("=>"), msg="converted anyway: \{out}")
}

///|
test "peephole: `this` in a computed binding key blocks the arrow conversion" {
  let out = bundle_min_mangled(
    (
      #|export const obj = {};
      #|obj.m = function (o) {
      #|  let { [this.k]: v } = o;
      #|  return v;
      #|};
      #|
    ),
  )
  assert_false(out.contains("=>"), msg="converted anyway: \{out}")
}

///|
test "peephole: `this` in a parameter default blocks the arrow conversion" {
  let out = bundle_min_mangled(
    (
      #|export const obj = {};
      #|obj.m = function (x = this.y) {
      #|  return x;
      #|};
      #|
    ),
  )
  assert_false(out.contains("=>"), msg="converted anyway: \{out}")
}

///|
test "peephole: `this` in a for-of binding default blocks the arrow conversion" {
  let out = bundle_min_mangled(
    (
      #|export const obj = {};
      #|obj.m = function (rows) {
      #|  let n = 0;
      #|  for (const { v = this.base } of rows) n += v;
      #|  return n;
      #|};
      #|
    ),
  )
  assert_false(out.contains("=>"), msg="converted anyway: \{out}")
}

///|
test "peephole: a `this`-free destructuring body still becomes an arrow" {
  // The gate has to stay a gate, not a blanket refusal: nothing here
  // reads `this`, so the conversion should still happen. Without this
  // case the four above would also pass on a rule that never fires.
  let out = bundle_min_mangled(
    (
      #|export const obj = {};
      #|obj.m = function (o) {
      #|  let { major: v = 0 } = o;
      #|  return v;
      #|};
      #|
    ),
  )
  assert_true(out.contains("=>"), msg="no conversion at all: \{out}")
}

///|
test "peephole: a computed `__proto__` key is not folded to a plain one" {
  // `{ ["__proto__"]: v }` defines an own property; `{ __proto__: v }`
  // sets the prototype. The rewrite is a byte saving for every other
  // valid identifier and a semantic change for this one.
  let out = minify_one("const o = { [\"__proto__\"]: base, x: 1 };\n")
  assert_true(out.contains("[\"__proto__\"]"), msg="folded: \{out}")
}

///|
test "peephole: a computed string key that is an identifier is folded" {
  let out = minify_one("const o = { [\"count\"]: 1 };\n")
  assert_true(out.contains("count:1"), msg="not folded: \{out}")
  assert_false(out.contains("[\"count\"]"), msg="not folded: \{out}")
}

// ---------------------------------------------------------------
// Boolean comparison rewrites need a boolean
// ---------------------------------------------------------------
//
// `x === true` -> `x` and its three siblings are sound only when `x` is
// a boolean. Nothing checked that, and TypeScript's binder writes
// `symbol.constEnumOnlyModule !== false` on a field that is `undefined`
// most of the time — `undefined !== false` is `true`, but the rewrite
// left `undefined` behind.

///|
test "peephole: `x !== false` on a bare name is not dropped" {
  let out = minify_one("const r = obj.flag !== false;\n")
  assert_true(out.contains("!=="), msg="dropped the comparison: \{out}")
}

///|
test "peephole: `x === true` on a bare name is not dropped" {
  let out = minify_one("const r = obj.flag === true;\n")
  assert_true(out.contains("!0") || out.contains("true"), msg="dropped: \{out}")
}

///|
test "peephole: `x === false` on a bare name does not become `!x`" {
  // `0 === false` is false; `!0` is true.
  let out = minify_one("const r = n === false;\n")
  assert_false(out.contains("r=!n"), msg="rewrote to !x: \{out}")
}

///|
test "peephole: a comparison result compared to false still folds" {
  // `(a < b) !== false` IS `a < b` — the operand is provably boolean,
  // so the saving is still taken.
  let out = minify_one("const r = (a < b) !== false;\n")
  assert_false(out.contains("!=="), msg="missed the saving: \{out}")
  assert_true(out.contains("a<b"), msg="missed the saving: \{out}")
}

///|
test "peephole: a negation compared to true still folds" {
  let out = minify_one("const r = !flag === true;\n")
  assert_false(out.contains("==="), msg="missed the saving: \{out}")
}
