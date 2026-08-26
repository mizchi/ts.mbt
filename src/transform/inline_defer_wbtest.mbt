// Tests for where an impure initializer may be moved to.
//
// The reduced case is the shape from TypeScript's own binder, which the
// single-use inliner miscompiled: a call whose only job is a side effect,
// read by a `?:` branch that is not taken.

///|
fn inline_defer_one(src : String) -> String raise {
  let block = @parser.parse_block_from_source(src)
  let out = inline_block(block)
  let e = Emitter::new(pretty=false)
  for s in out.stmts {
    emit_stmt(e, s)
    e.nl()
  }
  e.to_string()
}

///|
test "inline: an impure init is not moved into a ternary branch" {
  let out = inline_defer_one(
    (
      #|let sym = declareSymbol(node);
      #|out.push(pattern && !isString(pattern) ? { pattern, sym } : void 0);
      #|
    ),
  )
  // Moving the call inside the `?` branch means it never runs when the
  // condition is false — the module never gets its symbol.
  assert_true(out.contains("let sym=declareSymbol(node)"), msg="moved: \{out}")
}

///|
test "inline: an impure init is not moved behind a short circuit" {
  let out = inline_defer_one(
    (
      #|let sym = declareSymbol(node);
      #|out.push(ready && sym);
      #|
    ),
  )
  assert_true(out.contains("let sym=declareSymbol(node)"), msg="moved: \{out}")
}

///|
test "inline: an impure init is not moved into an if branch" {
  let out = inline_defer_one(
    (
      #|let sym = declareSymbol(node);
      #|if (ready) { out.push(sym); }
      #|
    ),
  )
  assert_true(out.contains("let sym=declareSymbol(node)"), msg="moved: \{out}")
}

///|
test "inline: an impure init is not moved past another effect" {
  let out = inline_defer_one(
    (
      #|let sym = first();
      #|out.push(second(), sym);
      #|
    ),
  )
  // Substituting would evaluate `second()` before `first()`.
  assert_true(out.contains("let sym=first()"), msg="reordered: \{out}")
}

///|
test "inline: an impure init is not moved into a loop condition" {
  let out = inline_defer_one(
    (
      #|let sym = declareSymbol(node);
      #|while (sym) { step(); }
      #|
    ),
  )
  assert_true(out.contains("let sym=declareSymbol(node)"), msg="moved: \{out}")
}

///|
test "inline: an impure init still moves to an unconditional first use" {
  // The rule has to stay a rule, not a blanket refusal: this is
  // terser's `collapse_vars`, and it is the whole point of the pass.
  let out = inline_defer_one(
    (
      #|const t = g.p(1);
      #|out.push(t + 1);
      #|
    ),
  )
  assert_false(out.contains("const t"), msg="not inlined: \{out}")
  assert_true(out.contains("g.p(1)+1"), msg="not inlined: \{out}")
}

///|
test "inline: a pure init still moves into a ternary branch" {
  // Nothing is lost by not evaluating a value, so the restriction
  // applies only to initializers with effects.
  let out = inline_defer_one(
    (
      #|const n = a + 1;
      #|out.push(ready ? n : 0);
      #|
    ),
  )
  assert_false(out.contains("const n"), msg="not inlined: \{out}")
}
