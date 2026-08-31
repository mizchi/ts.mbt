// Tests for terser's `inline` rule: replacing a call to a trivial
// function with its body.

///|
fn call_inline_one(src : String) -> String raise {
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
test "call_inline: the table finds both shapes a top-level function takes" {
  let block = @parser.parse_block_from_source(
    "const arrowOne = (n) => n + 1;\nfunction declOne(n) { return n + 2; }\nconsole.log(arrowOne(1) + declOne(2));\n",
  )
  let table = collect_trivial_fns(block)
  let names : Array[String] = []
  for entry in table {
    names.push(entry.0)
  }
  names.sort()
  inspect(
    names,
    content=(
      #|[declOne, arrowOne]
    ),
  )
}

///|
test "call_inline: an arrow's body lands at the call site" {
  let out = call_inline_one(
    "const addOne = (n) => n + 1;\nconsole.log(addOne(2));\n",
  )
  assert_true(out.contains("2 + 1"))
}

///|
test "call_inline: a function declaration's body lands at the call site" {
  let out = call_inline_one(
    "function addOne(n) { return n + 1; }\nconsole.log(addOne(2));\n",
  )
  assert_true(out.contains("2 + 1"))
}

///|
/// Is `name` a function this pass would expand? Asserting on the
/// DECISION rather than on the emitted text matters: the pre-existing
/// single-use binding inliner rewrites `f(x)` into an IIFE for its own
/// reasons, so the call text changes either way and would make a
/// declined case look accepted.
fn call_inline_accepts(src : String, name : String) -> Bool raise {
  collect_trivial_fns(@parser.parse_block_from_source(src)).contains(name)
}

///|
test "call_inline: a parameter used twice is declined" {
  // Substituting would evaluate the argument twice.
  assert_false(
    call_inline_accepts("const sq = (n) => n * n;\nconsole.log(sq(2));\n", "sq"),
  )
}

///|
test "call_inline: an impure body is declined" {
  assert_false(
    call_inline_accepts(
      "const bad = (n) => effect(n);\nconsole.log(bad(1));\n", "bad",
    ),
  )
}

///|
test "call_inline: a recursive function is declined" {
  assert_false(
    call_inline_accepts(
      "const rec = (n) => n > 0 ? rec(n - 1) : 0;\nconsole.log(rec(3));\n", "rec",
    ),
  )
}

///|
test "call_inline: a parameter shadowing the function name is not recursion" {
  // What the mangler produces: the binding and its parameter share a
  // name. The `a` in the body is the parameter.
  assert_true(
    call_inline_accepts("const a = (a) => a + 1;\nconsole.log(a(2));\n", "a"),
  )
}

///|
test "call_inline: a body that is not a single return is declined" {
  assert_false(
    call_inline_accepts(
      "function two(n) { const t = n + 1; return t * 2; }\nconsole.log(two(2));\n",
      "two",
    ),
  )
}

///|
test "call_inline: an impure argument inlines only when the order is exact" {
  // This test used to assert the opposite, and it was pinning a
  // LIMITATION rather than a requirement. The purity requirement on
  // arguments exists to stop duplicating, dropping or reordering an
  // argument's effects — and `(n) => n + 1` reads its one parameter
  // once, first, and unconditionally, so `addOne(effect())` and
  // `effect() + 1` perform the same operations in the same order.
  // Declining it cost real bytes: `is_pure_value` calls every property
  // read impure, so one-line helpers were never inlined at any call
  // site that read a property.
  let exact = call_inline_one(
    "const addOne = (n) => n + 1;\nconsole.log(addOne(effect()));\n",
  )
  assert_true(exact.contains("effect() + 1"))
  // What must still NOT happen: the same argument moved into a position
  // that might not evaluate. Here the body reads its parameter behind
  // `||`, so a call that always evaluates `effect()` would become one
  // that sometimes does not.
  let guarded = call_inline_one(
    "const orOne = (n) => cond || n;\nconsole.log(orOne(effect()));\n",
  )
  assert_false(guarded.contains("cond || effect()"))
}

// ---------------------------------------------------------------
// Scope narrowing
// ---------------------------------------------------------------
//
// The table is keyed by NAME and carried into every nested scope, so a
// scope that re-binds the name must not resolve against it. This pass
// runs after the mangler, which hands out the same short names in every
// scope, so shadowing is the normal case rather than an edge one.

///|
test "call_inline: a call to a shadowing local is not the top-level function" {
  let out = call_inline_one(
    (
      #|const pick = (n) => n + 1;
      #|function outer(pick) {
      #|  return pick(2);
      #|}
      #|console.log(outer((x) => x * 10));
      #|
    ),
  )
  // Inside `outer`, `pick` is the PARAMETER. Substituting the top-level
  // body here would print 3 instead of 20.
  assert_false(out.contains("2 + 1"), msg="inlined across a shadow: \{out}")
}

///|
test "call_inline: a local declaration shadows the table too" {
  let out = call_inline_one(
    (
      #|const pick = (n) => n + 1;
      #|function outer(f) {
      #|  const pick = f;
      #|  return pick(2);
      #|}
      #|console.log(outer((x) => x * 10));
      #|
    ),
  )
  assert_false(out.contains("2 + 1"), msg="inlined across a shadow: \{out}")
}

///|
test "call_inline: a loop variable shadows the table" {
  let out = call_inline_one(
    (
      #|const pick = (n) => n + 1;
      #|function outer(fns) {
      #|  let total = 0;
      #|  for (const pick of fns) total += pick(2);
      #|  return total;
      #|}
      #|console.log(outer([(x) => x * 10]));
      #|
    ),
  )
  assert_false(out.contains("2 + 1"), msg="inlined across a shadow: \{out}")
}

///|
test "call_inline: a catch parameter shadows the table" {
  let out = call_inline_one(
    (
      #|const pick = (n) => n + 1;
      #|function outer(thrower) {
      #|  try {
      #|    thrower();
      #|    return 0;
      #|  } catch (pick) {
      #|    return pick(2);
      #|  }
      #|}
      #|console.log(outer(() => { throw (x) => x * 10; }));
      #|
    ),
  )
  assert_false(out.contains("2 + 1"), msg="inlined across a shadow: \{out}")
}

///|
test "call_inline: an unshadowed nested call still inlines" {
  // The narrowing has to stay narrow: a nested scope that does NOT
  // rebind the name still gets the body.
  let out = call_inline_one(
    (
      #|const pick = (n) => n + 1;
      #|function outer() {
      #|  return pick(2);
      #|}
      #|console.log(outer());
      #|
    ),
  )
  assert_true(out.contains("2 + 1"), msg="narrowed too far: \{out}")
}

///|
/// Parameters must be substituted SIMULTANEOUSLY.
///
/// Doing it one at a time lets a later parameter's substitution rewrite
/// a name an earlier one just introduced, which is a wrong VALUE with no
/// crash and no free variable. Both arguments here are pure, so this was
/// reachable long before impure arguments were allowed — and the pass
/// order makes it likely rather than exotic, because the mangler runs
/// first and names both parameters and top-level bindings `a`, `b`, `c`.
///
/// This is a unit test rather than a corpus case, and that was decided
/// by measurement rather than taste. A `case55-inline-substitution-
/// capture` fixture was written first, and with the fix mutated out it
/// still PASSED: end to end the collision needs the mangler to give a
/// top-level binding the same short name as a later parameter of the
/// helper, and on that fixture it gave them different ones. A case that
/// cannot fail when the bug is present is coverage-shaped and proves
/// nothing, so it was deleted rather than shipped. Here the names are
/// the ones written down, and mutating the fix fails this test.
///
/// The bug does reach the full pipeline — `const add = (a, b) => a + b;
/// let b = 3;` with three call sites compiled to 2 / 200 / 14 where the
/// answers are 4 / 103 / 10 under `--bundle --minify --fold --treeshake
/// --mangle`. `case54-inline-argument-order` happens to catch it too,
/// because its `tap` helper does collide after mangling; that is luck,
/// not coverage, which is exactly why this test exists.
test "call_inline: parameters substitute simultaneously, not in sequence" {
  // `a := b` then `b := 1` would give `b + b` -> `1 + 1`.
  let one = call_inline_one(
    "const add = (a, b) => a + b;\nlet b = 3;\nconsole.log(add(b, 1));\n",
  )
  assert_true(one.contains("b + 1"))
  assert_false(one.contains("1 + 1"))
  // Three parameters, the capture reaching across two positions.
  let two = call_inline_one(
    "const pick = (a, b, c) => a - b * c;\nlet b = 3;\nlet c = 5;\nconsole.log(pick(b, c, 9));\n",
  )
  assert_true(two.contains("b - c * 9"))
  // The argument's name matching an EARLIER parameter is harmless and
  // must still inline — the point is the direction, not any collision.
  let three = call_inline_one(
    "const sub = (a, b) => a - b;\nlet a = 7;\nconsole.log(sub(2, a));\n",
  )
  assert_true(three.contains("2 - a"))
}

///|
/// An impure argument may be substituted only when the body reads every
/// parameter exactly once, in argument order, unconditionally.
test "call_inline: impure arguments need the body's order to be exact" {
  // Exact: read once, in order, both operands always evaluated.
  let exact = call_inline_one(
    "const isEq = (l, r) => l === r;\nconsole.log(isEq(f().x, g().y));\n",
  )
  assert_true(exact.contains("f().x === g().y"))
  assert_false(exact.contains("isEq("))
  // Short-circuit: the call always evaluates both arguments, `l || r`
  // may not.
  //
  // Asserted as "the operands were not spliced into the operator"
  // rather than "the callee's NAME survives": the single-use binding
  // inliner substitutes the arrow as a value, so the name goes away
  // while the call stays a call, which is semantically fine.
  let short = call_inline_one(
    "const orFn = (l, r) => l || r;\nconsole.log(orFn(f(), g()));\n",
  )
  assert_false(short.contains("f() || g()"))
  // Out of order: substitution would swap two argument evaluations.
  let swapped = call_inline_one(
    "const swap = (l, r) => r + l;\nconsole.log(swap(f(), g()));\n",
  )
  assert_false(swapped.contains("g() + f()"))
  // A parameter the body never reads: its argument's effect would go.
  let dropped = call_inline_one(
    "const first = (l, r) => l;\nconsole.log(first(f(), g()));\n",
  )
  assert_false(dropped.contains("console.log(f())"))
  // Conditional positions are guarded too.
  let cond = call_inline_one(
    "const choose = (c, t, e) => c ? t : e;\nconsole.log(choose(f(), g(), h()));\n",
  )
  assert_false(cond.contains("f() ? g() : h()"))
  // PURE arguments still inline through all of those shapes — the
  // relaxation adds cases, it must not remove any.
  // `p` and `q` are reassigned so the single-use binding inliner does
  // not fold them to literals first, which would make the assertion
  // about constant folding instead of about this rule.
  let pureShort = call_inline_one(
    "const orFn = (l, r) => l || r;\nlet p = 1;\nlet q = 2;\np = p + 0;\nq = q + 0;\nconsole.log(orFn(p, q));\n",
  )
  assert_true(pureShort.contains("p || q"))
}

///|
/// The names the substituted BODY reads have to mean the same thing at
/// the call site. `case43` covers the table's KEY being shadowed; this is
/// the value's own free variables, which nothing checked.
///
/// Pinned as a unit test as well as `case55`, because two of the four
/// tables that share the narrowing (`as_const_inline`, `predicate_inline`)
/// run BEFORE the mangler, so the mangler cleans up after them and no
/// end-to-end witness could be produced for those two. A test at the
/// pass boundary does not depend on what the mangler happens to do.
test "call_inline: an inlined body is not captured by the destination scope" {
  // `k` in the body is the OUTER `k`. The call site re-binds it.
  let shadowed = call_inline_one(
    "let k = f();\nconst get = () => k;\nfunction g() { let k = 99; return get() + k; }\nconsole.log(g());\n",
  )
  // The body must not be spliced into a scope where `k` is 99. Assert on
  // the SPLICE, not on the callee's name surviving: the single-use
  // binding inliner may substitute the arrow as a value, which keeps the
  // call a call and is fine.
  assert_false(shadowed.contains("return k + k"))
  // A parameter is the spelling no block-level check can see.
  let param = call_inline_one(
    "let k = f();\nconst get = () => k;\nfunction g(k) { return get() + k; }\nconsole.log(g(1));\n",
  )
  assert_false(param.contains("return k + k"))
  // And the unshadowed call still inlines, so the fix is not "decline
  // everywhere". `m` folds to its literal on the way, which is why the
  // expected text is `k + 99` and not `k + m`.
  let plain = call_inline_one(
    "let k = f();\nconst get = () => k;\nfunction g() { let m = 99; return get() + m; }\nconsole.log(g());\n",
  )
  assert_true(plain.contains("return k + 99"))
  assert_false(plain.contains("get() + 99"))
}
