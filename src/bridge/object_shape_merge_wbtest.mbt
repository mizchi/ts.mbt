///|
test "bridge object shape merge: merges identical property members" {
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
test "bridge object shape merge: rejects conflicting property members" {
  assert_false(
    can_merge_object_shapes([
      "{ value: string }", "{ value: number }", "{ ok: boolean }",
    ]),
  )
}

///|
test "bridge object shape merge: merges identical readonly property members" {
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
test "bridge object shape merge: rejects readonly and mutable conflicts" {
  assert_false(
    can_merge_object_shapes([
      "{ readonly count: number }", "{ count: number }", "{ ok: boolean }",
    ]),
  )
}

///|
test "bridge object shape merge: rejects duplicate methods to avoid overload merging" {
  assert_false(
    can_merge_object_shapes([
      "{ format(value: number): string }", "{ format(value: number): string }", "{ ok: boolean }",
    ]),
  )
}

///|
test "bridge object shape merge: rejects call signatures to stay conservative" {
  assert_false(
    can_merge_object_shapes(["{ (value: string): string }", "{ ok: boolean }"]),
  )
}

///|
test "bridge object shape merge: rejects index signatures to stay conservative" {
  assert_false(
    can_merge_object_shapes(["{ [key: string]: string }", "{ ok: boolean }"]),
  )
}

///|
test "bridge object shape merge: merges identical optional property members" {
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
test "bridge object shape merge: rejects optional and required conflicts" {
  assert_false(
    can_merge_object_shapes([
      "{ name?: string }", "{ name: string }", "{ ok: boolean }",
    ]),
  )
}
