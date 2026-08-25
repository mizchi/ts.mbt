// Tests for inferred-purity DCE: dropping a call whose callee the
// purity pass *proved* effect-free, rather than one the author
// annotated with `/* @__PURE__ */`.
//
// The safety argument has two halves, and both are tested here. A call
// only goes away when the proof clears it (first group), and the proof
// only clears a call when nothing in its transitive reach can be
// observed (second group). The second group is the load-bearing one:
// the purity table it exercises used to be per-namespace, which made
// every `Object.*` and `Array.*` member pure — harmless while the
// result only fed a diagnostic, a miscompile once it deletes code.

///|
fn dce_vfs(entries : Array[(String, String)]) -> Map[String, String] {
  let m : Map[String, String] = {}
  for entry in entries {
    m[entry.0] = entry.1
  }
  m
}

///|
fn dce_bundle(source : String) -> String raise {
  let files = dce_vfs([("entry.ts", source)])
  let opts = BundleOptions::default().with_treeshake(true)
  match bundle_modules(files, "entry.ts", opts) {
    Ok(out) => out.js
    Err(e) => {
      fail("bundle error: \{e}")
      ""
    }
  }
}

// ---------------------------------------------------------------------
// The proof lets a call go
// ---------------------------------------------------------------------

///|
test "pure-dce: an unused call to a proven-pure function is dropped" {
  let js = dce_bundle(
    (
      #|function scale(n: number): number { return n * 2; }
      #|const droppable = scale(21);
      #|export const total = scale(4);
      #|
    ),
  )
  assert_false(js.contains("droppable"))
  // The callee itself survives, because the exported binding needs it.
  assert_true(js.contains("scale"))
}

///|
test "pure-dce: an unused effect-free host static is dropped" {
  let js = dce_bundle(
    (
      #|const cfg = { a: 1 };
      #|const droppableKeys = Object.keys(cfg);
      #|const droppableMax = Math.max(1, 2);
      #|export const total = cfg.a;
      #|
    ),
  )
  assert_false(js.contains("droppableKeys"))
  assert_false(js.contains("droppableMax"))
}

///|
test "pure-dce: an impure argument keeps the call" {
  // The callee being harmless says nothing about the arguments: the
  // `console.log` inside `noisy()` has to fire when the program runs.
  let js = dce_bundle(
    (
      #|function scale(n: number): number { return n * 2; }
      #|function noisy(): number { console.log("effect"); return 1; }
      #|const kept = scale(noisy());
      #|export const total = scale(4);
      #|
    ),
  )
  assert_true(js.contains("noisy()"))
}

///|
test "pure-dce: a call into an impure function is kept" {
  let js = dce_bundle(
    (
      #|function announce(msg: string): string { console.log(msg); return msg; }
      #|const kept = announce("hi");
      #|export const total = 1;
      #|
    ),
  )
  assert_true(js.contains("announce(\"hi\")"))
}

// ---------------------------------------------------------------------
// The proof refuses the calls it must refuse
// ---------------------------------------------------------------------

///|
test "pure-dce: Object.assign is a writer, not a pure static" {
  // `Object.assign(target, …)` mutates `target`. Dropping the call
  // loses the write.
  let js = dce_bundle(
    (
      #|const registry: { hits?: number } = {};
      #|const unused = Object.assign(registry, { hits: 1 });
      #|export const out = registry.hits === undefined ? 0 : registry.hits;
      #|
    ),
  )
  assert_true(js.contains("Object.assign"))
}

///|
test "pure-dce: a mutator inside a function makes the function impure" {
  // The case that turns the table's imprecision into a wrong answer:
  // classifying `Object.assign` as pure makes `record` pure, which
  // deletes `record(7)` and compiles `out` to 0 instead of 7.
  let js = dce_bundle(
    (
      #|const registry: { hits?: number } = {};
      #|function record(n: number): number {
      #|  Object.assign(registry, { hits: n });
      #|  return n;
      #|}
      #|const unused = record(7);
      #|export const out = registry.hits === undefined ? 0 : registry.hits;
      #|
    ),
  )
  assert_true(js.contains("record(7)"))
}

///|
test "pure-dce: Object.freeze is a writer too" {
  let js = dce_bundle(
    (
      #|const cfg = { a: 1 };
      #|const unused = Object.freeze(cfg);
      #|export const out = cfg.a;
      #|
    ),
  )
  assert_true(js.contains("Object.freeze"))
}

///|
test "pure-dce: Array.from with a mapper invokes it" {
  // Arity is the whole distinction: `Array.from(xs)` allocates,
  // `Array.from(xs, fn)` runs `fn`.
  let js = dce_bundle(
    (
      #|const seen: number[] = [];
      #|const unused = Array.from([1, 2], (n) => { seen.push(n); return n; });
      #|export const out = seen.length;
      #|
    ),
  )
  assert_true(js.contains("Array.from"))
}

///|
test "pure-dce: Array.from without a mapper is droppable" {
  let js = dce_bundle(
    (
      #|const droppable = Array.from([1, 2]);
      #|export const out = 1;
      #|
    ),
  )
  assert_false(js.contains("droppable"))
}

///|
test "pure-dce: an unused Promise.reject keeps its unhandled rejection" {
  // Dropping it would remove an observable crash.
  let js = dce_bundle(
    (
      #|const unused = Promise.reject(new Error("boom"));
      #|export const out = 1;
      #|
    ),
  )
  assert_true(js.contains("Promise.reject"))
}

///|
test "pure-dce: treeshake without a purity proof keeps every call" {
  // `treeshake_block`'s `pure_calls` defaults to empty, which is the
  // behaviour every caller had before the proof was wired in: a call
  // is a side-effect root unless syntax alone says otherwise.
  let block = @parser.parse_block_from_source(
    (
      #|function scale(n) { return n * 2; }
      #|const droppable = scale(21);
      #|sideEffect(1);
      #|
    ),
  )
  let shaken = treeshake_block(block)
  let mut found = false
  for s in shaken.stmts {
    match s {
      @ast.TsStmt::Const(@ast.TsBinding::Ident("droppable"), _, _) =>
        found = true
      _ => ()
    }
  }
  assert_true(found)
}

///|
test "pure-dce: an explicit pure_calls set drops the same call" {
  // Same input, same pass, one extra fact.
  let block = @parser.parse_block_from_source(
    (
      #|function scale(n) { return n * 2; }
      #|const droppable = scale(21);
      #|sideEffect(1);
      #|
    ),
  )
  let shaken = treeshake_block(block, pure_calls={ "scale": true })
  for s in shaken.stmts {
    match s {
      @ast.TsStmt::Const(@ast.TsBinding::Ident("droppable"), _, _) =>
        fail("`droppable` survived a purity-cleared call")
      _ => ()
    }
  }
}
