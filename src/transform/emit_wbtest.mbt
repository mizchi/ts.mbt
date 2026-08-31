///|
fn emit_min_one(src : String) -> String raise {
  let block = @parser.parse_block_from_source(src)
  let e = Emitter::new(pretty=false)
  for s in block.stmts {
    emit_stmt(e, s)
  }
  e.to_string()
}

// ---------------------------------------------------------------
// Sign operators that would merge with their operand
// ---------------------------------------------------------------
//
// `+(++a)` printed tight is `+++a`, which JS reads as `++ (+a)` and
// rejects: "Invalid left-hand side expression in prefix operation". The
// binary case (`"" + +x`) already had a guard; the unary-on-unary case
// did not.

///|
test "emit: +(++a) keeps the operators apart" {
  let out = emit_min_one("const r = +(++a);\n")
  assert_false(out.contains("+++"), msg="merged into ++ +: \{out}")
  assert_true(
    out.contains("+ ++a") || out.contains("+(++a)"),
    msg="got: \{out}",
  )
}

///|
test "emit: -(--a) keeps the operators apart" {
  let out = emit_min_one("const r = -(--a);\n")
  assert_false(out.contains("---"), msg="merged into -- -: \{out}")
}

///|
test "emit: +(+a) keeps the operators apart" {
  let out = emit_min_one("const r = +(+a);\n")
  assert_false(out.contains("+++"), msg="merged: \{out}")
}

///|
test "emit: ++(+a) keeps the operators apart" {
  // Not valid JS as written, but the folder can build this shape and the
  // emitter must not print something that parses as another program.
  let out = emit_min_one("const r = -(-a);\n")
  assert_false(out.contains("---"), msg="merged: \{out}")
}

///|
test "emit: +(-a) needs no separator" {
  let out = emit_min_one("const r = +(-a);\n")
  assert_true(out.contains("+-a"), msg="over-separated: \{out}")
}

///|
/// An arrow whose expression body starts with `{` has to be
/// parenthesised or the JS parser reads a block. The check used to be a
/// hand-listed set of shapes, and the erased type assertions were not on
/// it: `(o) => ({ ...o, k: 1 }) as T` emitted
/// `(o) => {...o, k: 1}`, a SyntaxError. zod writes that form
/// (`({ …core.standardProps(self) }) as ZodType["~standard"]`) and its
/// whole 714 KB bundle failed to load on it.
///
/// So the cases here are the family, not the one arm: every wrapper that
/// emits nothing of its own, and every operator whose emission begins
/// with its left operand.
test "emit: an arrow body starting with `{` keeps its parens through every wrapper" {
  let cases = [
    // the bare case, which always worked
    "({ k: 1 })",
    // erased type assertions — the ones that were missing
     "({ k: 1 }) as any", "({ k: 1 }) satisfies object", "({ k: 1 })!",
    // stacked, because one unwrap is not enough
     "({ k: 1 }) as any as object",
    // postfix forms, which the old list did cover
     "({ k: 1 }).k", "({ k: 1 })[\"k\"]",
    // an operator whose left operand is the object literal
     "({ k: 1 }).k + 1", "({ k: 1 }) ? 1 : 2",
    // wrapper under operator, and operator under wrapper
     "(({ k: 1 }) as any).k", "({ k: 1 }).k as any",
  ]
  for src in cases {
    let out = emit_min_one("const f = (o) => \{src};")
    // The body must not start a block. Checking the emitted text for
    // `=>{` is the whole assertion: that is precisely the shape the JS
    // parser mis-reads.
    if out.contains("=>{") {
      fail("`\{src}` lost its parens: \{out}")
    }
    if !out.contains("=>(") {
      fail("`\{src}` was not parenthesised: \{out}")
    }
  }
}

///|
test "emit: an arrow body that cannot start with `{` gets no parens" {
  // The other direction, so the fix is not just "parenthesise
  // everything". These pay no bytes.
  let cases = ["1 + 2", "o.k", "f(o)", "[1, 2]", "\"s\"", "o", "!o", "-1"]
  for src in cases {
    let out = emit_min_one("const f = (o) => \{src};")
    if out.contains("=>(") {
      fail("`\{src}` was parenthesised needlessly: \{out}")
    }
  }
}

///|
test "emit: a binary operator never merges with its right operand's leader" {
  // Token adjacency, which is a SyntaxError rather than a wrong value.
  // Two ways this was broken, both found by `just fuzz-mangle` in
  // consecutive runs:
  //
  //   * `expr_leading_byte` answered `'0'` for a NEGATIVE numeric
  //     literal, so `x - -3` emitted `x--3` — a decrement. `--fold` is
  //     what makes it reachable: it turns `UnaryOp(Neg, IntLit(3))`,
  //     which was reported correctly, into `IntLit(-3)`.
  //   * consolidating the separator rule onto `expr_leading_byte`
  //     dropped the `PreInc` / `PreDec` rows the old duplicate table
  //     had, so `c + ++a` emitted `c+++a` — `c++ + a`.
  //
  // Every shape, so a third round has somewhere to fail.
  // The invariant is that the MERGED token never appears — not that a
  // particular spelling does. `c + +3` legitimately folds to `c+3`,
  // because unary `+` on a positive literal is identity and `c+3` is
  // fine; asserting a `+ +3` spelling would be over-specification that
  // fights the folder.
  let cases = [
    "c + ++a", "c - --a", "c + +a", "c - -a", "c - -3", "c + +3", "c - -0", "c - -1.5",
    "c - -a - -b",
  ]
  for expr in cases {
    let src = "const r = \{expr};"
    let block = @parser.parse_block_from_source(src)
    let folded = fold_block(block)
    let e = Emitter::new(pretty=false)
    emit_block(e, folded)
    let out = e.to_string()
    assert_false(out.contains("c++"), msg="`\{expr}` produced `c++`: \{out}")
    assert_false(out.contains("c--"), msg="`\{expr}` produced `c--`: \{out}")
    assert_false(out.contains("a++"), msg="`\{expr}` produced `a++`: \{out}")
    assert_false(out.contains("a--"), msg="`\{expr}` produced `a--`: \{out}")
  }
}

///|
test "emit: a postfix operand needs no separator" {
  // The other direction — `x++` emits the OPERAND first, so its leading
  // byte is the operand's and no space is owed. Over-separating is only
  // bytes, but the rule should still say the right thing.
  for src in ["const r = c + a++;", "const r = c - a--;"] {
    let block = @parser.parse_block_from_source(src)
    let e = Emitter::new(pretty=false)
    emit_block(e, fold_block(block))
    let out = e.to_string()
    assert_false(out.contains("+ a++"), msg="expected no space, got: \{out}")
    assert_false(out.contains("- a--"), msg="expected no space, got: \{out}")
  }
}

// ---------------------------------------------------------------
// A `void` initializer whose operand does something
// ---------------------------------------------------------------
//
// `let x;` initialises to `undefined`, so `let x = void 0` may drop its
// initializer in minify mode. `void EXPR` is undefined whatever `EXPR`
// is — which makes the VALUE inert and says nothing about the operand.
// `let unused = void trace.push(1)` emitted as `let unused;` and the
// `push` never ran, under plain `--minify`.
//
// Three copies of the decision existed: `omit_declaration_init` and two
// inline duplicates in the merged-declarator paths. All three had the
// bug; fixing the helper alone left the merged paths wrong, which is
// what `--treeshake --minify` reached.

///|
test "emit: a void initializer with an effectful operand is kept" {
  let single = emit_min_one("let unused = void sink(1);\n")
  assert_true(single.contains("sink(1)"), msg="dropped the operand: \{single}")
  // The merged-declarator path is a different writer, and it had its
  // own copy. Two declarations in a row is what triggers the merge.
  let merged = emit_min_one("let a = void sink(1);\nlet b = void sink(2);\n")
  assert_true(
    merged.contains("sink(1)") && merged.contains("sink(2)"),
    msg="the merged writer dropped an operand: \{merged}",
  )
}

///|
test "emit: a void initializer with a pure operand is still dropped" {
  // The other half — the byte saving has to survive the fix.
  let single = emit_min_one("let a = void 0;\n")
  assert_false(single.contains("void"), msg="lost the saving: \{single}")
  let merged = emit_min_one("let a = void 0;\nlet b = void 0;\n")
  assert_false(merged.contains("void"), msg="lost the saving: \{merged}")
}

// ---------------------------------------------------------------
// The no-initializer marker must never reach the output
// ---------------------------------------------------------------
//
// `Var("__ts_no_init__")` is what the parser synthesises for `let x;` /
// `var x;` so the checker can tell "no initializer" from "assigned
// undefined". It is not an expression: nothing declares that name, so
// emitting it is a `ReferenceError` the moment the line runs.
//
// `omit_declaration_init` drops it, and every declaration emit calls
// that — except the one inside a `for` head, which wrote `= <init>`
// unconditionally. So `for (var u; l < n.length; l++)`, ordinary
// JavaScript out of preact's own source, came out as
// `for (var u = __ts_no_init__; …)` under plain `mtsc --bundle`, with no
// optimization flag and on input that never saw a type.

///|
test "emit: a for-head declaration with no initializer emits none" {
  let pretty = fn(src : String) -> String raise {
    let block = @parser.parse_block_from_source(src)
    let e = Emitter::new(pretty=true)
    for s in block.stmts {
      emit_stmt(e, s)
    }
    e.to_string()
  }
  for
    src in [
      "for (var u; u < n; u++) { f(u); }\n", "for (let k; k < n; k++) { f(k); }\n",
    ] {
    let min = emit_min_one(src)
    let pre = pretty(src)
    assert_false(min.contains("__ts_no_init__"))
    assert_false(pre.contains("__ts_no_init__"))
    // The binding still has to be there — the fix is dropping the
    // initializer, not the declaration.
    assert_true(min.contains("var u;") || min.contains("let k;"))
  }
  // A real initializer in a for head is untouched.
  let kept = emit_min_one("for (let i = 0; i < n; i++) { f(i); }\n")
  assert_true(kept.contains("let i=0"))
  // `= undefined` in a for head is the OPTIMIZATION half of the same
  // helper: dropped when minifying, kept when pretty-printing.
  let undef = emit_min_one("for (let i = undefined; i < n; i++) { f(i); }\n")
  assert_false(undef.contains("undefined"))
}
