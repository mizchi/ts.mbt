///|
test "check_assignable: identical types report no issues" {
  let issues = check_assignable(String_, String_)
  assert_eq(issues.length(), 0)
}

///|
test "check_assignable: any flows freely with no issues" {
  let issues = check_assignable(Any, Number)
  assert_eq(issues.length(), 0)
  let issues2 = check_assignable(Number, Any)
  assert_eq(issues2.length(), 0)
}

///|
test "check_assignable: primitive mismatch reports root path" {
  let issues = check_assignable(String_, Number)
  assert_eq(issues.length(), 1)
  let issue = issues[0]
  assert_eq(issue.path, "")
}

///|
test "check_assignable: object field mismatch reports field path" {
  let s : @ast.TsType = Object([(Literal("x"), Number)])
  let t : @ast.TsType = Object([(Literal("x"), String_)])
  let issues = check_assignable(s, t)
  assert_eq(issues.length(), 1)
  assert_eq(issues[0].path, ".x")
}

///|
test "check_assignable: missing required field reports the field name" {
  let s : @ast.TsType = Object([(Literal("x"), Number)])
  let t : @ast.TsType = Object([
    (Literal("x"), Number),
    (Literal("y"), Number),
  ])
  let issues = check_assignable(s, t)
  assert_eq(issues.length(), 1)
  assert_eq(issues[0].path, ".y")
  assert_true(issues[0].message.contains("missing"))
}

///|
test "check_assignable: tuple element mismatch reports indexed path" {
  let s : @ast.TsType = Tuple([String_, Number])
  let t : @ast.TsType = Tuple([String_, String_])
  let issues = check_assignable(s, t)
  assert_eq(issues.length(), 1)
  assert_eq(issues[0].path, "[1]")
}

///|
test "check_assignable: tuple length mismatch reports root path" {
  let s : @ast.TsType = Tuple([String_])
  let t : @ast.TsType = Tuple([String_, Number])
  let issues = check_assignable(s, t)
  assert_eq(issues.length(), 1)
  assert_eq(issues[0].path, "")
  assert_true(issues[0].message.contains("length"))
}

///|
test "check_assignable: function arg mismatch uses param path" {
  // (x: number) => void  ⇍  (x: string) => void
  // Param contravariance: target's String must flow into source's Number — fails.
  let s : @ast.TsType = Func([Number], Void)
  let t : @ast.TsType = Func([String_], Void)
  let issues = check_assignable(s, t)
  assert_eq(issues.length(), 1)
  assert_true(issues[0].path.contains("param[0]"))
}

///|
test "check_assignable: function return mismatch uses return path" {
  let s : @ast.TsType = Func([], String_)
  let t : @ast.TsType = Func([], Number)
  let issues = check_assignable(s, t)
  assert_eq(issues.length(), 1)
  assert_eq(issues[0].path, ".return")
}

///|
test "check_assignable: nested object reports composite path" {
  let s : @ast.TsType = Object([
    (Literal("a"), Object([(Literal("b"), Number)])),
  ])
  let t : @ast.TsType = Object([
    (Literal("a"), Object([(Literal("b"), String_)])),
  ])
  let issues = check_assignable(s, t)
  assert_eq(issues.length(), 1)
  assert_eq(issues[0].path, ".a.b")
}
