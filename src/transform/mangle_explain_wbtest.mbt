// Tests for the explain layer — `--explain-mangle`.
//
// Two obligations, and the first matters more than the second. An
// explanation that disagrees with the decision is worse than no
// explanation, so the first block of tests checks that the pieces
// `escape_breakdown` hands out merge to exactly the set the mangler
// reserves. The rest check attribution: that a name landed in the
// section that actually reserved it, and that the wildcard message
// names the binding or the expression responsible rather than
// announcing that something, somewhere, went wrong.

///|
/// The breakdown, computed the way the bundler would compute it.
fn breakdown_of(source : String) -> EscapeBreakdown raise {
  let block = @parser.parse_block_from_source(source)
  let externals : Map[String, Bool] = {}
  for n in undeclared_referenced_names(block).keys() {
    externals[n] = true
  }
  escape_breakdown(block, externals)
}

///|
/// A block shaped the way the pipeline feeds the later passes: classes
/// already lowered to `NativeClassStmt`, since `bundle.mbt` explains
/// over the lifted form and not over the parse tree.
fn lifted_block(source : String) -> @ast.TsBlock raise {
  iife_class_lift_block(@parser.parse_block_from_source(source))
}

///|
/// Every name the breakdown reserves, in any section, sorted.
fn breakdown_names(b : EscapeBreakdown) -> Array[String] {
  let seen : Map[String, Bool] = {}
  for
    group in [
      b.external_chain,
      b.sink_observability,
      b.sink_literal,
      b.host_shaped,
      b.value_tree,
      b.in_probe,
    ] {
    for n in group {
      seen[n] = true
    }
  }
  let out : Array[String] = []
  for k in seen.keys() {
    out.push(k)
  }
  out.sort()
  out
}

///|
fn joined(names : Array[String]) -> String {
  let mut s = ""
  for n in names {
    s = s + n + " "
  }
  s
}

// ---------------------------------------------------------------------
// The explanation describes the decision it is explaining
// ---------------------------------------------------------------------

///|
test "explain: the breakdown merges to exactly what the mangler reserves" {
  // One source per section, so a section that stopped feeding the merge
  // (or started feeding it something the merge drops) shows up here
  // rather than as a silently over-mangled bundle.
  let sources = [
    // nothing escapes
    "const a = { hidden: 1 };\nconst b = a.hidden + 1;\n",
    // external chain
     "bridge.publish(1);\n",
    // literal handed to a sink
     "console.log({ stage: 1, phase: 2 });\n",
    // observability through a stringify
     "const cfg = { foo: 1, bar: 2 };\nconsole.log(JSON.stringify(cfg));\n",
    // host-shaped value
     "const parsed = JSON.parse(raw);\nconst n = parsed.count;\nconsole.log(n);\n",
    // value tree from a recursive root
     "const inner = { deep: 1 };\nconst outer = { inner };\nconsole.log(outer);\n",
    // `in` probe
     "const o = { probed: 1 };\nconst has = \"probed\" in o;\n",
    // a foreign callee taking a whole binding
     "const rec = { a: 1 };\nHostBridge.channel.post(rec);\n",
  ]
  for src in sources {
    let block = @parser.parse_block_from_source(src)
    let externals : Map[String, Bool] = {}
    for n in undeclared_referenced_names(block).keys() {
      externals[n] = true
    }
    let merged = collect_externally_visible_props(block, externals)
    merged.sort()
    let pieces = breakdown_names(escape_breakdown(block, externals))
    assert_eq(joined(pieces), joined(merged))
  }
}

// ---------------------------------------------------------------------
// Wildcard attribution
// ---------------------------------------------------------------------

///|
test "explain: the wildcard names the binding that crossed the boundary" {
  let b = breakdown_of(
    (
      #|const cfg = { retries: 3, timeoutMs: 50 };
      #|HostBridge.channel.post(cfg);
      #|
    ),
  )
  // The decision itself: suppressed.
  assert_true(b.sink_observability.contains("*"))
  // The explanation: which binding, and what would change it.
  assert_true(b.wildcard_reasons.length() > 0)
  let mut names_the_binding = false
  let mut suggests_an_annotation = false
  for r in b.wildcard_reasons {
    if r.contains("`cfg`") {
      names_the_binding = true
      if r.contains("annotat") {
        suggests_an_annotation = true
      }
    }
  }
  assert_true(names_the_binding)
  assert_true(suggests_an_annotation)
}

///|
test "explain: an annotated boundary crossing is not a wildcard, and says nothing" {
  // The other half of the previous test: once the binding carries a
  // closed type, the reservation narrows to that type's keys and there
  // is no wildcard left to explain.
  let b = breakdown_of(
    (
      #|const cfg: { retries: number, timeoutMs: number } = { retries: 3, timeoutMs: 50 };
      #|HostBridge.channel.post(cfg);
      #|
    ),
  )
  assert_false(b.sink_observability.contains("*"))
  assert_eq(b.wildcard_reasons.length(), 0)
  assert_true(b.sink_observability.contains("retries"))
}

///|
test "explain: a dynamic index on an external chain says which chain" {
  let b = breakdown_of(
    (
      #|function put(k: string, v: number) {
      #|  store.table[k] = v;
      #|}
      #|
    ),
  )
  assert_true(b.external_chain.contains("*"))
  let mut named = false
  for r in b.wildcard_reasons {
    if r.contains("`store`") && r.contains("dynamic") {
      named = true
    }
  }
  assert_true(named)
}

// ---------------------------------------------------------------------
// Section attribution
// ---------------------------------------------------------------------

///|
test "explain: a literal handed to a sink is attributed to the literal" {
  let b = breakdown_of("console.log({ stage: 1 });\n")
  assert_true(b.sink_literal.contains("stage"))
  // Not misfiled as something read off an import.
  assert_false(b.external_chain.contains("stage"))
}

///|
test "explain: a name read off an import is attributed to the chain" {
  let b = breakdown_of(
    (
      #|bridge.publish(1);
      #|
    ),
  )
  assert_true(b.external_chain.contains("publish"))
}

///|
test "explain: a nested name is attributed to the value tree" {
  let b = breakdown_of(
    (
      #|const inner = { deep: 1 };
      #|const outer = { inner };
      #|console.log(outer);
      #|
    ),
  )
  // `console.log` observes the whole tree, so `deep` is reserved one
  // level below the value that reached the sink — and the section says
  // so, which is the difference between "why is `deep` kept?" being
  // answerable and not.
  assert_true(b.value_tree.contains("deep"))
}

///|
test "explain: an `in` probe is attributed to the probe" {
  let b = breakdown_of(
    "const o = { probed: 1 };\nconst has = \"probed\" in o;\n",
  )
  assert_true(b.in_probe.contains("probed"))
}

///|
test "explain: a host-shaped read is attributed to the host" {
  let b = breakdown_of(
    (
      #|const parsed = JSON.parse(raw);
      #|const n = parsed.count;
      #|console.log(n);
      #|
    ),
  )
  assert_true(b.host_shaped.contains("count"))
}

// ---------------------------------------------------------------------
// Rendering
// ---------------------------------------------------------------------

///|
test "explain: the rendering leads with the verdict" {
  let suppressed = format_escape_explanation(
    breakdown_of("const cfg = { a: 1 };\nHostBridge.post(cfg);\n"),
  )
  let mut says_suppressed = false
  for line in suppressed {
    if line.contains("SUPPRESSED") {
      says_suppressed = true
    }
  }
  assert_true(says_suppressed)
  let clean = format_escape_explanation(
    breakdown_of("const a = { hidden: 1 };\nconst b = a.hidden + 1;\n"),
  )
  let mut says_enabled = false
  for line in clean {
    if line.contains("enabled") {
      says_enabled = true
    }
  }
  assert_true(says_enabled)
}

///|
test "explain: the rendering never prints the wildcard as a property name" {
  // `*` is not a name anybody wrote; it belongs in the verdict, not in
  // a list of names to go look at.
  let lines = format_escape_explanation(
    breakdown_of("const cfg = { a: 1 };\nHostBridge.post(cfg);\n"),
  )
  for line in lines {
    assert_false(line.contains(" * *"))
  }
}

// ---------------------------------------------------------------------
// The other three passes explain their declines
// ---------------------------------------------------------------------

///|
test "explain: a dead-field decline names the reason" {
  let block = lifted_block(
    (
      #|class Box {
      #|  total: number;
      #|  constructor() {
      #|    this.total = 1;
      #|  }
      #|}
      #|const box = new Box();
      #|console.log(box.total);
      #|
    ),
  )
  let reserved : Map[String, Bool] = { "total": true }
  let reasons = explain_dead_fields(block, reserved)
  let mut found = false
  for r in reasons {
    if r.contains("`total`") && r.contains("escape set") {
      found = true
    }
  }
  assert_true(found)
}

///|
test "explain: a dead-field decline distinguishes a read from an escape" {
  let block = lifted_block(
    (
      #|class Box {
      #|  n: number;
      #|  constructor() {
      #|    this.n = 1;
      #|  }
      #|  get() {
      #|    return this.n;
      #|  }
      #|}
      #|const box = new Box();
      #|
    ),
  )
  let reasons = explain_dead_fields(block, {})
  let mut found = false
  for r in reasons {
    if r.contains("`n`") && r.contains("reads it") {
      found = true
    }
  }
  assert_true(found)
}

///|
test "explain: the wildcard decline cascades into the field and tag passes" {
  let block = lifted_block(
    (
      #|class Box {
      #|  n: number;
      #|  constructor() {
      #|    this.n = 1;
      #|  }
      #|}
      #|const box = new Box();
      #|
    ),
  )
  let wildcard : Map[String, Bool] = { "*": true }
  let field_reasons = explain_dead_fields(block, wildcard)
  let mut field_cascade = false
  for r in field_reasons {
    if r.contains("wildcard") {
      field_cascade = true
    }
  }
  assert_true(field_cascade)
  let tag_declines : Array[String] = []
  let _ = plan_discriminant_ints(block, wildcard, declines=tag_declines)
  let mut tag_cascade = false
  for r in tag_declines {
    if r.contains("wildcard") {
      tag_cascade = true
    }
  }
  assert_true(tag_cascade)
}

///|
test "explain: a tag decline names the read that blocked it" {
  let block = @parser.parse_block_from_source(
    (
      #|const ev = { kind: "start" };
      #|function describe() {
      #|  return `event: ${ev.kind}`;
      #|}
      #|
    ),
  )
  let declines : Array[String] = []
  let plan = plan_discriminant_ints(block, {}, declines~)
  assert_false(plan.maps.contains("kind"))
  let mut found = false
  for r in declines {
    if r.contains("`kind`") {
      found = true
    }
  }
  assert_true(found)
}

///|
test "explain: an arity decline names the condition that fired" {
  let block = @parser.parse_block_from_source(
    (
      #|function announce(a: number, b: number) {
      #|  return a + b;
      #|}
      #|const r = announce(1, 2);
      #|
    ),
  )
  let keep : Map[String, Bool] = {}
  let declines : Array[String] = []
  let _ = plan_unused_params(block, keep~, declines~)
  let mut found = false
  for r in declines {
    if r.contains("`announce`") && r.contains("read by the body") {
      found = true
    }
  }
  assert_true(found)
}

// ---------------------------------------------------------------------
// End to end, through the flag the user actually types
// ---------------------------------------------------------------------

///|
test "explain: --explain-mangle reports on all four passes" {
  let files : Map[String, String] = {
    "entry.ts": (
      #|import { log } from "ext";
      #|class Box {
      #|  total: number;
      #|  deadSlot: number;
      #|  constructor() {
      #|    this.total = 1;
      #|    this.deadSlot = 2;
      #|  }
      #|}
      #|const ev = { kind: "start" };
      #|export function announce(a: number, b: number) {
      #|  const box = new Box();
      #|  log.info({ stage: ev.kind });
      #|  return box.total + a + b;
      #|}
      #|
    ),
  }
  let opts = BundleOptions::default()
    .with_mangle(true)
    .with_mangle_properties(true)
    .with_explain(true)
  match bundle_modules(files, "entry.ts", opts) {
    Ok(out) => {
      let text = {
        let mut s = ""
        for line in out.explain {
          s = s + line + "\n"
        }
        s
      }
      // Reading order: why names are reserved first, because a wildcard
      // there is what suppresses the other three.
      assert_true(text.contains("property mangling: why names are reserved"))
      assert_true(text.contains("trailing-parameter trimming"))
      assert_true(text.contains("dead class fields"))
      assert_true(text.contains("discriminant tags"))
      let mut escape_at = -1
      let mut tags_at = -1
      for i, line in out.explain {
        if line.contains("property mangling: why names are reserved") &&
          escape_at < 0 {
          escape_at = i
        }
        if line.contains("discriminant tags") && tags_at < 0 {
          tags_at = i
        }
      }
      assert_true(escape_at >= 0 && escape_at < tags_at)
    }
    Err(e) => fail("bundle error: \{e}")
  }
}

///|
test "explain: the explanation is empty unless asked for" {
  let files : Map[String, String] = {
    "entry.ts": "const a = { x: 1 };\nexport const b = a.x;\n",
  }
  let opts = BundleOptions::default()
    .with_mangle(true)
    .with_mangle_properties(true)
  match bundle_modules(files, "entry.ts", opts) {
    Ok(out) => assert_eq(out.explain.length(), 0)
    Err(e) => fail("bundle error: \{e}")
  }
}
