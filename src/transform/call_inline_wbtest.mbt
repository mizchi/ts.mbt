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
test "call_inline: an impure argument keeps the call" {
  let out = call_inline_one(
    "const addOne = (n) => n + 1;\nconsole.log(addOne(effect()));\n",
  )
  // The argument must still be evaluated exactly once, so the body is
  // not moved out to the call site.
  assert_false(out.contains("effect() + 1"))
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
