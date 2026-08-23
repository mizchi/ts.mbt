// Tests for discriminant renumbering.
//
// Assertions go through `plan_discriminant_ints` where the question is
// "did the analysis allow it?", and through the emitted bundle where the
// question is "did the literal actually go away?". String literals
// survive identifier and property mangling, so grepping for them is
// meaningful in a way grepping for identifiers is not.

///|
fn disc_plan(
  source : String,
  reserved : Array[String],
) -> DiscriminantPlan raise {
  let block = @parser.parse_block_from_source(source)
  let r : Map[String, Bool] = {}
  for n in reserved {
    r[n] = true
  }
  plan_discriminant_ints(block, r)
}

///|
fn disc_bundle(source : String) -> String raise {
  let files : Map[String, String] = { "entry.ts": source }
  let opts = BundleOptions::default().with_mangle_properties(true)
  match bundle_modules(files, "entry.ts", opts) {
    Ok(out) => out.js
    Err(e) => {
      fail("bundle error: \{e}")
      ""
    }
  }
}

// ---------------------------------------------------------------------
// It fires
// ---------------------------------------------------------------------

///|
test "discriminant: a switch on a closed tag set is renumbered" {
  let js = disc_bundle(
    (
      #|type Shape = { kind: "circle"; r: number } | { kind: "square"; s: number };
      #|function area(x: Shape): number {
      #|  switch (x.kind) {
      #|    case "circle": return x.r * x.r * 3;
      #|    case "square": return x.s * x.s;
      #|    default: return 0;
      #|  }
      #|}
      #|const shapes: Shape[] = [{ kind: "circle", r: 2 }, { kind: "square", s: 3 }];
      #|export const out = area(shapes[0]) + area(shapes[1]);
      #|
    ),
  )
  assert_false(js.contains("circle"))
  assert_false(js.contains("square"))
}

///|
test "discriminant: an equality comparison is renumbered" {
  let plan = disc_plan(
    (
      #|const a = { tag: "one" };
      #|const b = { tag: "two" };
      #|sink(a.tag === "one" ? 1 : 0);
      #|sink(b.tag !== "two" ? 1 : 0);
      #|
    ),
    [],
  )
  @test.assert_eq(plan.maps.get("tag").is_empty(), false)
}

// ---------------------------------------------------------------------
// It declines
// ---------------------------------------------------------------------

///|
test "discriminant: a reserved name is left alone" {
  // Anything that can see the whole object — serialization, enumeration,
  // an `in` probe, a foreign call, the export surface — puts the name in
  // the escape set.
  let plan = disc_plan(
    (
      #|const a = { tag: "one" };
      #|sink(a.tag === "one" ? 1 : 0);
      #|
    ),
    ["tag"],
  )
  assert_false(plan.maps.contains("tag"))
}

///|
test "discriminant: a wildcard escape disables the pass" {
  let plan = disc_plan(
    (
      #|const a = { tag: "one" };
      #|sink(a.tag === "one" ? 1 : 0);
      #|
    ),
    ["*"],
  )
  assert_true(plan.maps.is_empty())
}

///|
test "discriminant: a bare read blocks the name" {
  // `return x.tag` hands the VALUE out while the NAME stays hidden —
  // the case the reserved set alone would miss.
  let plan = disc_plan(
    (
      #|const a = { tag: "one" };
      #|function readIt() { return a.tag; }
      #|sink(readIt());
      #|
    ),
    [],
  )
  assert_false(plan.maps.contains("tag"))
}

///|
test "discriminant: interpolation blocks the name" {
  let plan = disc_plan(
    (
      #|const a = { tag: "one" };
      #|sink(`${a.tag}`);
      #|
    ),
    [],
  )
  assert_false(plan.maps.contains("tag"))
}

///|
test "discriminant: a truthiness test blocks the name" {
  // `"one"` is truthy and `0` is not, so renumbering would flip the test.
  let plan = disc_plan(
    (
      #|const a = { tag: "one" };
      #|sink(a.tag ? 1 : 0);
      #|
    ),
    [],
  )
  assert_false(plan.maps.contains("tag"))
}

///|
test "discriminant: a relational comparison blocks the name" {
  let plan = disc_plan(
    (
      #|const a = { tag: "one" };
      #|sink(a.tag < "two" ? 1 : 0);
      #|
    ),
    [],
  )
  assert_false(plan.maps.contains("tag"))
}

///|
test "discriminant: a non-literal write blocks the name" {
  let plan = disc_plan(
    (
      #|const a = { tag: String(1) };
      #|sink(a.tag === "1" ? 1 : 0);
      #|
    ),
    [],
  )
  assert_false(plan.maps.contains("tag"))
}

///|
test "discriminant: comparing against an unwritten literal blocks it" {
  // The comparison is always false today. Renumbering would have to
  // invent a number to keep it false.
  let plan = disc_plan(
    (
      #|const a = { tag: "one" };
      #|sink(a.tag === "never-written" ? 1 : 0);
      #|
    ),
    [],
  )
  assert_false(plan.maps.contains("tag"))
}

///|
test "discriminant: a computed read blocks the name" {
  let plan = disc_plan(
    (
      #|const a = { tag: "one" };
      #|sink(a["tag"] === "one" ? 1 : 0);
      #|
    ),
    [],
  )
  assert_false(plan.maps.contains("tag"))
}

///|
test "discriminant: a switch with a non-literal case blocks the name" {
  let plan = disc_plan(
    (
      #|const a = { tag: "one" };
      #|switch (a.tag) {
      #|  case other: sink(1); break;
      #|  default: sink(0);
      #|}
      #|
    ),
    [],
  )
  assert_false(plan.maps.contains("tag"))
}

///|
test "discriminant: a written-but-never-read tag is left to dead-props" {
  let plan = disc_plan("const a = { tag: \"one\" };\nsink(a);\n", [])
  assert_false(plan.maps.contains("tag"))
}
