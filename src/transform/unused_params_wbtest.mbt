// Tests for trailing-parameter trimming.
//
// The corpus checks the safety half by execution (baseline vs mangled
// must observe the same thing). These check the other half — that the
// optimization fires — and each of the conditions that must block it.
//
// Most assertions go through `plan_unused_params` rather than the
// emitted text: the pipeline also renames identifiers, so grepping the
// output for `unusedOpts` proves nothing either way.

///|
fn up_plan(source : String, exported : Array[String]) -> Map[String, Int] raise {
  let block = @parser.parse_block_from_source(source)
  let keep : Map[String, Bool] = {}
  for n in exported {
    keep[n] = true
  }
  plan_unused_params(block, keep~).keep_count
}

///|
fn up_bundle(source : String) -> String raise {
  let files : Map[String, String] = { "entry.ts": source }
  let opts = BundleOptions::default().with_mangle(true)
  match bundle_modules(files, "entry.ts", opts) {
    Ok(out) => out.js
    Err(e) => {
      fail("bundle error: \{e}")
      ""
    }
  }
}

// ---------------------------------------------------------------------
// It fires
// ---------------------------------------------------------------------

///|
test "unused-params: a trailing unused parameter and its arguments go" {
  // End-to-end through the pipeline. `pad` is a property name, which
  // `with_mangle` alone doesn't touch, so its absence means the whole
  // argument was dropped rather than renamed.
  let js = up_bundle(
    (
      #|function fmt(value, unusedOpts) { return String(value); }
      #|export const out = fmt(1, { pad: true }) + fmt(2, { pad: false });
      #|
    ),
  )
  assert_false(js.contains("pad"))
}

///|
test "unused-params: two trailing parameters at once" {
  let plan = up_plan(
    (
      #|function f(a, x, y) { return a; }
      #|f(1, 2, 3);
      #|
    ),
    [],
  )
  @test.assert_eq(plan.get("f"), Some(1))
}

///|
test "unused-params: surplus arguments beyond the arity go too" {
  // Three arguments to a two-parameter function: the dead parameter and
  // the surplus argument both drop, and both are pure.
  let plan = up_plan(
    (
      #|function f(a, unused) { return a; }
      #|f(1, 2, 3);
      #|
    ),
    [],
  )
  @test.assert_eq(plan.get("f"), Some(1))
}

///|
test "unused-params: an arrow function is a candidate too" {
  let plan = up_plan(
    (
      #|const f = (a, unused) => a;
      #|f(1, 2);
      #|
    ),
    [],
  )
  @test.assert_eq(plan.get("f"), Some(1))
}

// ---------------------------------------------------------------------
// It declines
// ---------------------------------------------------------------------

///|
test "unused-params: a read parameter stays" {
  let plan = up_plan(
    (
      #|function addUp(a, b) { return a + b; }
      #|addUp(1, 2);
      #|
    ),
    [],
  )
  assert_false(plan.contains("addUp"))
}

///|
test "unused-params: only the trailing run counts" {
  // `mid` is unused but `last` is read. Dropping `mid` alone would shift
  // `last` into its position, so nothing moves.
  let plan = up_plan(
    (
      #|function pick(first, mid, last) { return first + last; }
      #|pick(1, 2, 3);
      #|
    ),
    [],
  )
  assert_false(plan.contains("pick"))
}

///|
test "unused-params: an exported function keeps its arity" {
  let plan = up_plan(
    (
      #|function pub(a, unused) { return a; }
      #|pub(1, 2);
      #|
    ),
    ["pub"],
  )
  assert_false(plan.contains("pub"))
}

///|
test "unused-params: a function used as a value keeps its arity" {
  // Whoever holds `f` can call it with their own argument count.
  let plan = up_plan(
    (
      #|function f(a, unused) { return a; }
      #|const held = f;
      #|held(1, 2);
      #|
    ),
    [],
  )
  assert_false(plan.contains("f"))
}

///|
test "unused-params: a function handed to a call keeps its arity" {
  let plan = up_plan(
    (
      #|function f(a, unused) { return a; }
      #|register(f);
      #|
    ),
    [],
  )
  assert_false(plan.contains("f"))
}

///|
test "unused-params: reaching the function through a property keeps arity" {
  let plan = up_plan(
    (
      #|function f(a, unused) { return a; }
      #|f.call(null, 1, 2);
      #|
    ),
    [],
  )
  assert_false(plan.contains("f"))
}

///|
test "unused-params: used as a constructor keeps its arity" {
  let plan = up_plan(
    (
      #|function F(a, unused) { this.a = a; }
      #|new F(1, 2);
      #|
    ),
    [],
  )
  assert_false(plan.contains("F"))
}

///|
test "unused-params: an impure dropped argument keeps the parameter" {
  let plan = up_plan(
    (
      #|function f(a, unused) { return a; }
      #|f(1, bump());
      #|
    ),
    [],
  )
  assert_false(plan.contains("f"))
}

///|
test "unused-params: one impure call site blocks every site" {
  let plan = up_plan(
    (
      #|function f(a, unused) { return a; }
      #|f(1, 2);
      #|f(3, bump());
      #|
    ),
    [],
  )
  assert_false(plan.contains("f"))
}

///|
test "unused-params: a body reading `arguments` keeps its arity" {
  let plan = up_plan(
    (
      #|function f(a, unused) { return a + arguments.length; }
      #|f(1, 2);
      #|
    ),
    [],
  )
  assert_false(plan.contains("f"))
}

///|
test "unused-params: a default on the dropped parameter keeps it" {
  // Dropping the parameter would stop evaluating the default.
  let plan = up_plan(
    (
      #|function f(a, unused = bump()) { return a; }
      #|f(1);
      #|
    ),
    [],
  )
  assert_false(plan.contains("f"))
}

///|
test "unused-params: a spread argument keeps the arity" {
  let plan = up_plan(
    (
      #|function f(a, unused) { return a; }
      #|const args = [1, 2];
      #|f(...args);
      #|
    ),
    [],
  )
  assert_false(plan.contains("f"))
}

///|
test "unused-params: a rest parameter is left alone" {
  let plan = up_plan(
    (
      #|function f(a, ...rest) { return a; }
      #|f(1, 2, 3);
      #|
    ),
    [],
  )
  assert_false(plan.contains("f"))
}

///|
test "unused-params: a destructured parameter is left alone" {
  let plan = up_plan(
    (
      #|function f(a, { unused }) { return a; }
      #|f(1, { unused: 2 });
      #|
    ),
    [],
  )
  assert_false(plan.contains("f"))
}

///|
test "unused-params: a reassigned binding keeps its arity" {
  let plan = up_plan(
    (
      #|let f = function (a, unused) { return a; };
      #|f = other;
      #|f(1, 2);
      #|
    ),
    [],
  )
  assert_false(plan.contains("f"))
}

///|
test "unused-params: a parameter used only in a nested closure counts as read" {
  let plan = up_plan(
    (
      #|function f(a, cb) { return () => cb(a); }
      #|f(1, g);
      #|
    ),
    [],
  )
  assert_false(plan.contains("f"))
}
