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

///|
test "inline: chained single-use decls collapse in one call" {
  // Two consecutive single-use bindings: `a` inlines into `b`, then
  // `b` inlines into the return — both in a single `inline_block` call.
  let out = inline_one(
    "function f(x) { const a = x + 1; const b = a * 2; return b; }\n",
  )
  assert_false(out.contains("const a"))
  assert_false(out.contains("const b"))
  assert_true(out.contains("return (x + 1) * 2"))
}

// ---------------------------------------------------------------
// The declaration must not outlive its reference
// ---------------------------------------------------------------
//
// `count_var_uses_stmt` decides there is exactly one local use and
// `substitute_stmt` rewrites it. They walk the same tree, and every
// time one of them has been missing a statement kind the result was a
// dropped declaration with a live reference — "ReferenceError: f0 is
// not defined". `try` was one, then a bare block and a `switch` case
// body. The pass now checks its own work, so a future omission declines
// instead of miscompiling.
//
// These go through the full pipeline: the shape only arises after
// `fold` merges the surrounding declarations, which is why `--minify`
// alone kept the function and `--fold --minify` dropped it.

///|
fn pipeline_js(src : String) -> String raise {
  let files : Map[String, String] = { "entry.js": src }
  let opts = BundleOptions::default()
    .with_fold(true)
    .with_minify(true)
    .with_treeshake(true)
  match bundle_modules(files, "entry.js", opts) {
    Ok(out) => out.js
    Err(e) => fail("bundle error: \{e}")
  }
}

///|
/// Every name the bundle calls must be a name the bundle declares.
fn no_orphan_call(js : String, name : String) -> Bool {
  if !js.contains("\{name}(") {
    return true
  }
  js.contains("function \{name}(") || js.contains("\{name}=function")
}

///|
test "inline: a use inside a bare block keeps its declaration" {
  let out = pipeline_js(
    (
      #|let c = 0, b = 10;
      #|const trace = [];
      #|function f0(p0, p1) { trace.push(0); return 1; }
      #|{
      #|  let v3 = f0(10, undefined);
      #|  c = b === 20 && v3;
      #|}
      #|console.log([c, trace]);
      #|
    ),
  )
  assert_true(no_orphan_call(out, "f0"), msg="orphaned call: \{out}")
}

///|
test "inline: a use inside a switch case keeps its declaration" {
  let out = pipeline_js(
    (
      #|let c = 0, k = 1;
      #|const trace = [];
      #|function f0(p0) { trace.push(0); return 1; }
      #|switch (k) {
      #|  case 1: {
      #|    let v3 = f0(10);
      #|    c = v3;
      #|    break;
      #|  }
      #|}
      #|console.log([c, trace]);
      #|
    ),
  )
  assert_true(no_orphan_call(out, "f0"), msg="orphaned call: \{out}")
}

///|
test "inline: a use inside a try block keeps its declaration" {
  let out = pipeline_js(
    (
      #|let c = 0, b = 10;
      #|const trace = [];
      #|function f0(p0) { trace.push(0); return 1; }
      #|try {
      #|  let v3 = f0(10);
      #|  c = b === 20 && v3;
      #|} catch (e) {}
      #|console.log([c, trace]);
      #|
    ),
  )
  assert_true(no_orphan_call(out, "f0"), msg="orphaned call: \{out}")
}

///|
test "inline: a use inside a /*@__PURE__*/ call is counted" {
  // `count_var_uses_expr` had no `PureCall` arm, and its catch-all
  // returned the running totals unchanged — so an entire subtree under a
  // purity annotation was invisible to the use counter. A binding read
  // twice, once under the wrapper, looked single-use, and the single-use
  // inliner substituted it away and deleted the declaration, leaving the
  // wrapped read dangling.
  let inner : @ast.TsExpr = Call("wrap", [@ast.TsExpr::Var("target")])
  let (local_, nested) = count_var_uses_expr(
    PureCall(inner),
    "target",
    0,
    0,
    false,
  )
  assert_eq(local_, 1)
  assert_eq(nested, 0)
  // And the same expression without the wrapper must agree, which is the
  // property the missing arm broke.
  let (bare_local, bare_nested) = count_var_uses_expr(
    inner, "target", 0, 0, false,
  )
  assert_eq(local_, bare_local)
  assert_eq(nested, bare_nested)
}
