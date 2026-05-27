// Tests for the SymbolGraph construction (Phase 1 of the
// observability analysis). The goal here is just to confirm that
// every binding the parser produces shows up in the graph, that
// references resolve through the JS scoping rules, and that
// closure capture / reassignment are detected.

///|
fn build_graph(src : String) -> SymbolGraph raise {
  let block = @parser.parse_block_from_source(src)
  build_symbol_graph(block, {})
}

///|
fn build_graph_with_external(
  src : String,
  externals : Array[String],
) -> SymbolGraph raise {
  let block = @parser.parse_block_from_source(src)
  let map : Map[String, Bool] = {}
  for n in externals {
    map[n] = true
  }
  build_symbol_graph(block, map)
}

///|
fn symbol_by_name(g : SymbolGraph, scope : ScopeId, name : String) -> Symbol? {
  match g.by_name.get(scope.to_string() + ":" + name) {
    Some(id) => Some(g.symbols[id])
    None => None
  }
}

///|
test "symbol_graph: top-level let declares a binding in the module scope" {
  let g = build_graph("let x = 1; x + 2;")
  assert_eq(g.scopes.length(), 1) // module only
  assert_eq(g.scopes[0].kind, Module)
  let x = symbol_by_name(g, 0, "x").unwrap()
  assert_eq(x.kind, Let)
  // Two appearances: the `x + 2` reads `x`.
  assert_eq(x.uses.length(), 1)
}

///|
test "symbol_graph: var hoists into the enclosing function scope" {
  // Inner block's `var inner` should land in the function frame,
  // not the if-block frame, so a reference after the if still
  // resolves.
  let g = build_graph(
    #|function f() {
    #|  if (true) { var inner = 1; }
    #|  return inner;
    #|}
    #|
    ,
  )
  // function `f` introduces a Function scope; `var inner` hoists
  // there and `return inner` resolves to the same symbol.
  let f = symbol_by_name(g, 0, "f").unwrap()
  // Use the function's scope (the immediate child of module).
  let func_scope = g.scopes.iter().find_first(s => s.kind is Function).unwrap()
  let inner = symbol_by_name(g, func_scope.id, "inner").unwrap()
  assert_eq(inner.kind, Var)
  // The `return inner` is a Read use.
  assert_true(inner.uses.length() >= 1)
  let _ = f

}

///|
test "symbol_graph: let stays block-scoped" {
  let g = build_graph(
    #|{ let a = 1; }
    #|
    ,
  )
  // `a` lives in the inner Block scope, NOT module.
  assert_true(symbol_by_name(g, 0, "a") is None)
  let block_scope = g.scopes.iter().find_first(s => s.kind is Block).unwrap()
  assert_true(symbol_by_name(g, block_scope.id, "a") is Some(_))
}

///|
test "symbol_graph: reassignment marks the binding" {
  let g = build_graph("let x = 1; x = 2;")
  let x = symbol_by_name(g, 0, "x").unwrap()
  assert_true(x.reassigned)
}

///|
test "symbol_graph: closure capture flags cross-function refs" {
  let g = build_graph(
    #|function outer() {
    #|  let captured = 1;
    #|  return function() { return captured; };
    #|}
    #|
    ,
  )
  // Find `captured` in the outer function scope.
  let mut found : Symbol? = None
  for s in g.symbols {
    if s.name == "captured" { found = Some(s) }
  }
  let captured = found.unwrap()
  assert_true(captured.captured_by_closure)
}

///|
test "symbol_graph: external imports go in external_bindings" {
  let g = build_graph_with_external(
    "let x = 1; x + 2;",
    ["format", "babelPlugin"],
  )
  // The names aren't actually declared in the snippet above, but
  // the helper just tracks the set — declaring `let format = …`
  // would mark `format` as external.
  let _ = g
  let g2 = build_graph_with_external(
    "let format = 1; format();",
    ["format"],
  )
  let fmt = symbol_by_name(g2, 0, "format").unwrap()
  assert_true(g2.external_bindings.contains(fmt.id))
}

///|
test "symbol_graph: PropReceiver use context records the property name" {
  let g = build_graph("let obj = {a: 1, b: 2}; obj.foo; obj.bar;")
  let obj = symbol_by_name(g, 0, "obj").unwrap()
  // Two PropReceiver uses: obj.foo and obj.bar.
  let props : Array[String] = []
  for u in obj.uses {
    match u.context {
      PropReceiver(p) => props.push(p)
      _ => ()
    }
  }
  assert_eq(props.length(), 2)
  assert_true(props.contains("foo"))
  assert_true(props.contains("bar"))
}

///|
test "symbol_graph: IndexReceiver / IndexKey separate the two roles" {
  let g = build_graph("let arr = [1,2]; let i = 0; arr[i];")
  let arr = symbol_by_name(g, 0, "arr").unwrap()
  let i = symbol_by_name(g, 0, "i").unwrap()
  let mut arr_idx_recv = false
  let mut i_idx_key = false
  for u in arr.uses {
    if u.context is IndexReceiver { arr_idx_recv = true }
  }
  for u in i.uses {
    if u.context is IndexKey { i_idx_key = true }
  }
  assert_true(arr_idx_recv)
  assert_true(i_idx_key)
}

///|
test "symbol_graph: CallArg flow edge from arg expr to callee param slot" {
  let g = build_graph(
    #|function f(p) { return p; }
    #|let x = 1;
    #|f(x);
    #|
    ,
  )
  let f = symbol_by_name(g, 0, "f").unwrap()
  let x = symbol_by_name(g, 0, "x").unwrap()
  // Expect an edge SymVal(x) -> FuncArg(f, 0).
  let mut hit = false
  for e in g.flow_edges {
    if e.from is SymVal(xid) && xid == x.id {
      if e.to is FuncArg(fid, 0) && fid == f.id {
        hit = true
      }
    }
  }
  assert_true(hit)
}

///|
test "symbol_graph: return statement adds a FuncReturn edge" {
  let g = build_graph(
    #|function f() { let r = 42; return r; }
    #|
    ,
  )
  let f = symbol_by_name(g, 0, "f").unwrap()
  // Find r in the function frame.
  let mut r : Symbol? = None
  for s in g.symbols {
    if s.name == "r" { r = Some(s) }
  }
  let rsym = r.unwrap()
  let mut hit = false
  for e in g.flow_edges {
    if e.from is SymVal(rid) && rid == rsym.id {
      if e.to is FuncReturn(fid) && fid == f.id {
        hit = true
      }
    }
  }
  assert_true(hit)
}

///|
test "symbol_graph: multi-declarator wrapper Block doesn't open a new scope" {
  // `let a = 1, b = 2;` parses as Block({Let(a), Let(b)}). The
  // bindings leak to the parent scope, so we shouldn't see an
  // extra Block scope around them.
  let g = build_graph("function f() { let a = 1, b = 2; return a + b; }")
  let func_scope = g.scopes.iter().find_first(s => s.kind is Function).unwrap()
  // Both bindings live directly in the function frame.
  assert_true(symbol_by_name(g, func_scope.id, "a") is Some(_))
  assert_true(symbol_by_name(g, func_scope.id, "b") is Some(_))
  // No extra Block scope between function and body for this stmt.
  let mut block_scopes_in_func = 0
  for s in g.scopes {
    if s.kind is Block && s.parent is Some(p) && p == func_scope.id {
      block_scopes_in_func = block_scopes_in_func + 1
    }
  }
  assert_eq(block_scopes_in_func, 0)
}
