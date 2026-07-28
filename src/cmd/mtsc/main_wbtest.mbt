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
