///|
/// An alias chain that fans out by four at every level: `L{i}` is the union
/// of four distinct aliases of `L{i - 1}`, and `L0` has four literals, so
/// `L{n}` expands to `4^(n + 1)` members.
fn fanout_alias_source(levels : Int32) -> String {
  let sb = StringBuilder()
  sb.write_string("type L0 = \"a\" | \"b\" | \"c\" | \"d\";\n")
  for i in 1..<=levels {
    for w in ["A", "B", "C", "D"] {
      sb.write_string("type \{w}\{i} = L\{i - 1};\n")
    }
    sb.write_string("type L\{i} = A\{i} | B\{i} | C\{i} | D\{i};\n")
  }
  sb.to_string()
}

///|
/// The depth bound alone let this grow as `4^(n + 1)`: 4,096 entries at five
/// levels and 262,144 at the depth limit. Past the budget the collection
/// reports failure, and both callers keep the type as written.
test "narrowing member expansion stops at its budget" {
  let r = Resolver::from_module(parse_module_or_empty(fanout_alias_source(5)))
  let out : Array[@ast.TsType] = []
  assert_false(collect_narrowing_members(r, Named("L5"), out, 0))
  assert_true(out.length() <= NARROWING_MEMBER_BUDGET)
  assert_true(predicate_narrowing_source(r, Named("L5")) is Named("L5"))
  assert_true(predicate_comparison_target(r, Named("L5")) is Named("L5"))
}

///|
/// Under the budget the expansion is unchanged: 256 members at three levels,
/// as a union for both the source and the target.
test "narrowing member expansion under its budget is unchanged" {
  let r = Resolver::from_module(parse_module_or_empty(fanout_alias_source(3)))
  let out : Array[@ast.TsType] = []
  assert_true(collect_narrowing_members(r, Named("L3"), out, 0))
  assert_eq(out.length(), 256)
  match predicate_narrowing_source(r, Named("L3")) {
    Union(parts) => assert_eq(parts.length(), 256)
    _ => fail("the source did not expand")
  }
  match predicate_comparison_target(r, Named("L3")) {
    Union(parts) => assert_eq(parts.length(), 256)
    _ => fail("the target did not expand")
  }
}
