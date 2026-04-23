///|
test "checker: merges identical property members" {
  assert_true(
    can_merge_object_shapes([
      "{ kind: string }", "{ kind: string }", "{ ok: boolean }",
    ]),
  )
  assert_eq(
    merge_object_shapes([
      "{ kind: string }", "{ kind: string }", "{ ok: boolean }",
    ]),
    "{ kind: string; ok: boolean }",
  )
}

///|
test "checker: rejects conflicting property members" {
  assert_false(
    can_merge_object_shapes([
      "{ value: string }", "{ value: number }", "{ ok: boolean }",
    ]),
  )
}

///|
test "checker: merges identical readonly property members" {
  assert_true(
    can_merge_object_shapes([
      "{ readonly count: number }", "{ readonly count: number }", "{ ok: boolean }",
    ]),
  )
  assert_eq(
    merge_object_shapes([
      "{ readonly count: number }", "{ readonly count: number }", "{ ok: boolean }",
    ]),
    "{ readonly count: number; ok: boolean }",
  )
}

///|
test "checker: rejects readonly and mutable conflicts" {
  assert_false(
    can_merge_object_shapes([
      "{ readonly count: number }", "{ count: number }", "{ ok: boolean }",
    ]),
  )
}

///|
test "checker: rejects duplicate methods to avoid overload merging" {
  assert_false(
    can_merge_object_shapes([
      "{ format(value: number): string }", "{ format(value: number): string }", "{ ok: boolean }",
    ]),
  )
}

///|
test "checker: rejects call signatures to stay conservative" {
  assert_false(
    can_merge_object_shapes(["{ (value: string): string }", "{ ok: boolean }"]),
  )
}

///|
test "checker: rejects index signatures to stay conservative" {
  assert_false(
    can_merge_object_shapes(["{ [key: string]: string }", "{ ok: boolean }"]),
  )
}

///|
test "checker: merges identical optional property members" {
  assert_true(
    can_merge_object_shapes([
      "{ name?: string }", "{ name?: string }", "{ ok: boolean }",
    ]),
  )
  assert_eq(
    merge_object_shapes([
      "{ name?: string }", "{ name?: string }", "{ ok: boolean }",
    ]),
    "{ name?: string; ok: boolean }",
  )
}

///|
test "checker: rejects optional and required conflicts" {
  assert_false(
    can_merge_object_shapes([
      "{ name?: string }", "{ name: string }", "{ ok: boolean }",
    ]),
  )
}
