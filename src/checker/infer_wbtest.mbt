///|
fn infer_marker(name : String) -> @ast.TsType {
  Applied("__tsmbt_infer", [Named(name)])
}

///|
test "match_infer_pattern: identical types match without bindings" {
  let bindings : Map[String, @ast.TsType] = {}
  assert_true(match_infer_pattern(String_, String_, bindings))
  assert_eq(bindings.length(), 0)
}

///|
test "match_infer_pattern: bare infer captures source" {
  let bindings : Map[String, @ast.TsType] = {}
  assert_true(match_infer_pattern(String_, infer_marker("U"), bindings))
  assert_eq(bindings.get("U"), Some(String_))
}

///|
test "match_infer_pattern: Promise<infer U> binds U to inner" {
  let bindings : Map[String, @ast.TsType] = {}
  let pattern : @ast.TsType = Applied("Promise", [infer_marker("U")])
  let source : @ast.TsType = Applied("Promise", [String_])
  assert_true(match_infer_pattern(source, pattern, bindings))
  assert_eq(bindings.get("U"), Some(String_))
}

///|
test "match_infer_pattern: array element infer" {
  let bindings : Map[String, @ast.TsType] = {}
  let pattern : @ast.TsType = Array(infer_marker("E"))
  let source : @ast.TsType = Array(Number)
  assert_true(match_infer_pattern(source, pattern, bindings))
  assert_eq(bindings.get("E"), Some(Number))
}

///|
test "match_infer_pattern: function param/return infer" {
  let bindings : Map[String, @ast.TsType] = {}
  // (arg: infer A) => infer R  vs  (arg: string) => number
  let pattern : @ast.TsType = Func([infer_marker("A")], infer_marker("R"))
  let source : @ast.TsType = Func([String_], Number)
  assert_true(match_infer_pattern(source, pattern, bindings))
  assert_eq(bindings.get("A"), Some(String_))
  assert_eq(bindings.get("R"), Some(Number))
}

///|
test "match_infer_pattern: structural mismatch fails" {
  let bindings : Map[String, @ast.TsType] = {}
  let pattern : @ast.TsType = Applied("Promise", [infer_marker("U")])
  let source : @ast.TsType = Array(String_)
  assert_false(match_infer_pattern(source, pattern, bindings))
}

///|
test "match_infer_pattern: conflicting binding fails" {
  let bindings : Map[String, @ast.TsType] = {}
  // [infer X, infer X] vs [string, number] — second binding conflicts.
  let pattern : @ast.TsType = Tuple([infer_marker("X"), infer_marker("X")])
  let source : @ast.TsType = Tuple([String_, Number])
  assert_false(match_infer_pattern(source, pattern, bindings))
}

///|
test "match_infer_pattern: union pattern picks the matching branch" {
  let bindings : Map[String, @ast.TsType] = {}
  // Promise<infer U> | Array<infer U>  vs  Promise<string>
  let pattern : @ast.TsType = Union([
    Applied("Promise", [infer_marker("U")]),
    Applied("Array", [infer_marker("U")]),
  ])
  let source : @ast.TsType = Applied("Promise", [String_])
  assert_true(match_infer_pattern(source, pattern, bindings))
  assert_eq(bindings.get("U"), Some(String_))
}

///|
test "substitute_inferred_type: replaces Named with binding" {
  let bindings : Map[String, @ast.TsType] = { "U": Number }
  let body : @ast.TsType = Array(Named("U"))
  let result = substitute_inferred_type(body, bindings)
  assert_eq(result, Array(Number))
}

///|
test "substitute_inferred_type: leaves non-bound names alone" {
  let bindings : Map[String, @ast.TsType] = { "U": Number }
  let body : @ast.TsType = Named("V")
  let result = substitute_inferred_type(body, bindings)
  assert_eq(result, Named("V"))
}
