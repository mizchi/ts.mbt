///|
/// The scan `forget_paths_below` used to run over every key in the env,
/// kept here as the reference the index has to agree with.
fn reference_paths_below(env : ExprEnv, name : String) -> Array[String] {
  let out : Array[String] = []
  for k, _ in env.vars {
    if k.has_prefix(name + ".") || k.has_prefix(name + "[") {
      out.push(k)
    }
  }
  out.sort()
  out
}

///|
fn sorted_env_keys(env : ExprEnv) -> Array[String] {
  let out : Array[String] = []
  for k, _ in env.vars {
    out.push(k)
  }
  out.sort()
  out
}

///|
fn env_index_fixture() -> ExprEnv {
  let env = ExprEnv::new()
  for
    k in [
      "a", "a.b", "a.b[0].c", "a[1]", "a.bc", "ab", "ab.c", "b.a.c", "<alias-cond>q",
      "<fresh>a", "x[\"k.y\"]",
    ] {
    env.bind(k, @ast.TsType::Number)
  }
  env
}

///|
test "forget_paths_below through the index removes what the scan removed" {
  for name in ["a", "a.b", "a.b[0]", "ab", "b", "b.a", "x", "<fresh>a", "zz"] {
    let env = env_index_fixture()
    let expected = reference_paths_below(env, name)
    let before = sorted_env_keys(env)
    forget_paths_below(env, name)
    let after = sorted_env_keys(env)
    let removed = before.filter(fn(k) { !after.contains(k) })
    assert_eq(removed, expected)
  }
}

///|
test "a key a snapshot restores is still found by the index" {
  // `restore_from` writes keys back without going through `bind` /
  // `narrow`, so the index must keep a key it has already seen even after
  // the key left `vars`.
  let env = env_index_fixture()
  let snap = env.full_snapshot()
  forget_paths_below(env, "a")
  assert_false(env.vars.contains("a.b"))
  env.restore_from(snap)
  assert_true(env.vars.contains("a.b[0].c"))
  forget_paths_below(env, "a.b")
  assert_false(env.vars.contains("a.b[0].c"))
  assert_true(env.vars.contains("a.b"))
  // A key first written AFTER the index was built is indexed too.
  env.narrow("ab.d", @ast.TsType::String_)
  forget_paths_below(env, "ab")
  assert_false(env.vars.contains("ab.d"))
  assert_false(env.vars.contains("ab.c"))
  assert_true(env.vars.contains("ab"))
}

///|
test "an assignment still cancels aliases and forgets paths below it" {
  // tsc gives exactly the three `bad…` errors (TS2322 each).
  let issues = eff_issues(
    (
      #|function okStill(x: string | number) {
      #|  const isStr = typeof x === "string";
      #|  if (isStr) { const s: string = x; }
      #|}
      #|function badCancelled(x: string | number) {
      #|  const isStr = typeof x === "string";
      #|  x = 1;
      #|  if (isStr) { const s: string = x; }
      #|}
      #|function badSameTypeAssign(x: string | number, y: string | number) {
      #|  const isStr = typeof x === "string";
      #|  x = y;
      #|  if (isStr) { const s: string = x; }
      #|}
      #|function okPath(o: { a: { b: string | number } }) {
      #|  if (typeof o.a.b === "string") { const s: string = o.a.b; }
      #|}
      #|function badPathForgotten(o: { a: { b: string | number } }) {
      #|  if (typeof o.a.b === "string") { o.a = { b: 1 }; const s: string = o.a.b; }
      #|}
    ),
  )
  assert_false(eff_has(issues, "okStill"))
  assert_true(eff_has(issues, "badCancelled"))
  // The assignment leaves `x` the type it had at the alias, so only the
  // explicit cancellation (through `alias_cond_keys`) stops the alias.
  assert_true(eff_has(issues, "badSameTypeAssign"))
  assert_false(eff_has(issues, "okPath"))
  assert_true(eff_has(issues, "badPathForgotten"))
}
