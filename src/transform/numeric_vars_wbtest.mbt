// Tests for numeric-variable inference (Phase 2 of the
// observability analysis). The check is: bindings whose every
// initializer / reassignment writes a JS number value are flagged
// as numeric, and later passes can treat `arr[idx]` with such an
// idx as "integer-keyed slot access" (i.e. no string property
// escapes).

///|
fn run_numeric_infer(src : String) -> (SymbolGraph, Map[SymbolId, Bool]) raise {
  let block = @parser.parse_block_from_source(src)
  let g = build_symbol_graph(block, {})
  let n = infer_numeric_symbols(g)
  (g, n)
}

///|
fn has_numeric(
  g : SymbolGraph,
  numeric : Map[SymbolId, Bool],
  name : String,
) -> Bool {
  for s in g.symbols {
    if s.name == name && numeric.contains(s.id) {
      return true
    }
  }
  false
}

///|
test "numeric_vars: literal numeric initializer is numeric" {
  let (g, n) = run_numeric_infer("let i = 0;")
  assert_true(has_numeric(g, n, "i"))
}

///|
test "numeric_vars: string initializer is NOT numeric" {
  let (g, n) = run_numeric_infer("let s = \"hello\";")
  assert_false(has_numeric(g, n, "s"))
}

///|
test "numeric_vars: arithmetic reassignment stays numeric" {
  let (g, n) = run_numeric_infer(
    #|let i = 0;
    #|i = i + 1;
    #|
    ,
  )
  assert_true(has_numeric(g, n, "i"))
}

///|
test "numeric_vars: postfix ++ keeps the binding numeric" {
  let (g, n) = run_numeric_infer(
    #|let i = 0;
    #|i++;
    #|
    ,
  )
  assert_true(has_numeric(g, n, "i"))
}

///|
test "numeric_vars: arr.length is treated as numeric" {
  let (g, n) = run_numeric_infer(
    #|let arr = [1, 2, 3];
    #|let len = arr.length;
    #|
    ,
  )
  assert_true(has_numeric(g, n, "len"))
}

///|
test "numeric_vars: chained numeric derivation" {
  let (g, n) = run_numeric_infer(
    #|let a = 1;
    #|let b = a + 2;
    #|let c = b * 3;
    #|
    ,
  )
  assert_true(has_numeric(g, n, "a"))
  assert_true(has_numeric(g, n, "b"))
  assert_true(has_numeric(g, n, "c"))
}

///|
test "numeric_vars: + with string operand falls back to non-numeric" {
  let (g, n) = run_numeric_infer(
    #|let i = 0;
    #|let s = i + "px";
    #|
    ,
  )
  assert_true(has_numeric(g, n, "i"))
  assert_false(has_numeric(g, n, "s"))
}

///|
test "numeric_vars: closure-captured binding is conservative (skipped)" {
  let (g, n) = run_numeric_infer(
    #|let i = 0;
    #|function f() { return i + 1; }
    #|
    ,
  )
  // `i` is captured by f's closure — we don't track cross-function
  // assignments, so stay conservative.
  assert_false(has_numeric(g, n, "i"))
}

///|
test "numeric_vars: reassignment from non-numeric breaks the flag" {
  let (g, n) = run_numeric_infer(
    #|let x = 0;
    #|x = "broken";
    #|
    ,
  )
  assert_false(has_numeric(g, n, "x"))
}

///|
test "numeric_vars: index expr uses graph-aware predicate" {
  // `parts[i]` where `i` was a `let i = 0;` — the graph version
  // resolves `Var("i")` and sees it as numeric.
  let (g, n) = run_numeric_infer(
    #|let parts = [];
    #|let i = 0;
    #|
    ,
  )
  // Build the index expression: just `Var("i")`. We synthesise it
  // here instead of parsing a `parts[i]` to keep the test focused
  // on the public predicate.
  let idx_expr : @ast.TsExpr = @ast.TsExpr::Var("i")
  assert_true(is_index_numeric_with_graph(idx_expr, g, n))
}

///|
test "numeric_vars: ternary numeric on both branches" {
  let (g, n) = run_numeric_infer(
    #|let i = 0;
    #|let arr = [1];
    #|let idx = i < 0 ? arr.length + i : i;
    #|
    ,
  )
  assert_true(has_numeric(g, n, "idx"))
}
