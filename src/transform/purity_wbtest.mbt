test "purity: pure helper detected" {
  let src = "function pureHelper(x) { return x * 2; }\nfunction impureLog(x) { console.log(x); }\nfunction callsPure(x) { return pureHelper(x) + 1; }\nfunction callsImpure(x) { impureLog(x); return x; }\n"
  let block = @parser.parse_block_from_source(src)
  let report = analyze_purity(block)
  assert_true(report.pure_functions.contains("pureHelper"))
  assert_false(report.pure_functions.contains("impureLog"))
  // `callsPure` is pure: its only call target (`pureHelper`) is pure.
  assert_true(report.pure_functions.contains("callsPure"))
  // `callsImpure` is impure: it calls `impureLog`.
  assert_false(report.pure_functions.contains("callsImpure"))
}

test "purity: impure getter warning lists class + getter" {
  let src = "class Counter {\n  count = 0;\n  get value() { this.count++; return this.count; }\n}\n"
  let block = @parser.parse_block_from_source(src)
  let report = analyze_purity(block)
  assert_eq(report.impure_getters.length(), 1)
  let g = report.impure_getters[0]
  assert_eq(g.class_name, "Counter")
  assert_eq(g.getter_name, "value")
}

test "purity: pure getter produces no warning" {
  let src = "class Box {\n  v = 42;\n  get value() { return this.v; }\n}\n"
  let block = @parser.parse_block_from_source(src)
  let report = analyze_purity(block)
  assert_eq(report.impure_getters.length(), 0)
}

test "purity: pure_global_methods recognized" {
  let src = "function compute(x) { return Math.floor(x * 0.5); }\n"
  let block = @parser.parse_block_from_source(src)
  let report = analyze_purity(block)
  // `Math.floor` is a known pure global method — `compute` stays pure.
  assert_true(report.pure_functions.contains("compute"))
}
