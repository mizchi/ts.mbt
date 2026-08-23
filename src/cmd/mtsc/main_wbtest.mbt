///|
test "mtsc typecheck detects a function return mismatch" {
  let issues = mtsc_collect_type_issues(
    "function formatScore(score: number): string { return score; }", false,
  ).unwrap()
  assert_true(issues.length() == 1)
  assert_true(issues[0].message.contains("expected `string` but got `number`"))
}

///|
test "mtsc typecheck accepts a valid function" {
  let issues = mtsc_collect_type_issues(
    "function formatScore(score: number): string { return \"score: \" + score; }",
    false,
  ).unwrap()
  assert_true(issues.length() == 0)
}

///|
test "mtsc typecheck accepts an imported binding" {
  let issues = mtsc_collect_type_issues(
    "import { formatScore } from \"./score\";\nconst result = formatScore(1);", false,
  ).unwrap()
  assert_true(issues.length() == 0)
}

///|
async test "mtsc known-gap corpus records current missed diagnostics" {
  let cases = [
    "fixtures/mtsc/known-gaps/no-implicit-any.ts", "fixtures/mtsc/known-gaps/primitive-member.ts",
    "fixtures/mtsc/known-gaps/aliased-discriminant.ts", "fixtures/mtsc/known-gaps/overload-resolution.ts",
  ]
  for path in cases {
    let source = @fs.read_file(path).text() catch {
      e => fail("failed to read known mtsc gap fixture \{path}: \{e}")
    }
    let issues = mtsc_collect_type_issues(source, false).unwrap()
    assert_eq(issues.length(), 0)
  }
}

///|
test "mtsc flags: --mangle-properties selects the analyzed path" {
  // The escape analysis lives in `bundle_modules`. Without `--bundle`
  // the single-file path renamed property keys with no analysis at all,
  // including a CJS module's `exports.foo`, so the flag has to bring
  // the path that can prove the rename safe.
  for
    flag in [
      "--mangle-properties", "--explain-mangle", "--mangle-properties-shape-color",
    ] {
    let opts = mtsc_parse_args(["in.ts", flag]).unwrap()
    assert_true(opts.mangle_properties)
    assert_true(opts.bundle)
  }
  // `--mangle` alone only renames locals, and the single-file path
  // reserves every top-level name, so it stays where it was.
  let plain = mtsc_parse_args(["in.ts", "--mangle"]).unwrap()
  assert_true(plain.mangle)
  assert_false(plain.mangle_properties)
  assert_false(plain.bundle)
}

///|
test "mtsc flags: --no-check is off unless asked for" {
  assert_false(mtsc_parse_args(["in.ts"]).unwrap().no_check)
  assert_true(mtsc_parse_args(["in.ts", "--no-check"]).unwrap().no_check)
}
