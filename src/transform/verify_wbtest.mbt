// The verifier's own self-check.
//
// `verify_emitted_bundle` is fail-quiet by design: a construct it does
// not model is a MISSED violation, not a false alarm. That is the right
// direction and a real cost, so the coverage has to be asserted rather
// than assumed — the same reason the mangle-safety corpus carries a
// mutation self-check. Every construct the JS-validity check claims to
// detect gets fed to it here, in a nested position, and every clean
// bundle gets fed to it to prove it stays quiet.

///|
fn violation_kinds(js : String) -> Array[String] {
  let out : Array[String] = []
  for v in verify_emitted_bundle(js) {
    out.push(v.kind)
  }
  out
}

///|
fn has_not_javascript(js : String) -> Bool {
  for v in verify_emitted_bundle(js) {
    if v.kind == "not-javascript" {
      return true
    }
  }
  false
}

///|
test "verify: a clean bundle reports nothing" {
  let js =
    #|const a = 1;
    #|function f(x) { return x + a; }
    #|export { f };
  @test.assert_eq(violation_kinds(js).length(), 0)
}

///|
test "verify: a free variable is reported" {
  // The check this file exists for has to keep working.
  let js = "function f(x) { return x + missingBinding; }\nexport { f };"
  assert_true(violation_kinds(js).contains("free-variable"))
}

///|
test "verify: JSX left in the output is not JavaScript" {
  // The case that motivated the check. Un-lowered JSX survived the whole
  // corpus because this verifier re-parses with the TypeScript parser,
  // which accepts it.
  assert_true(has_not_javascript("const a = <div>x</div>;"))
  // The tag rides along, so a violation on a large bundle points at the
  // construct rather than at the whole file.
  let vs = verify_emitted_bundle("const a = <div>x</div>;")
  assert_true(vs.iter().any(fn(v) { v.name.contains("<div>") }))
}

///|
test "verify: JSX is found in every nested position" {
  // A walker with a catch-all hides violations, so each position the
  // walk claims to descend into is checked. A failure here means the
  // walk lost an arm, which is exactly the bug family this whole file
  // is about.
  let cases = [
    "const a = cond && <div>x</div>;", "const a = cond ? <div>x</div> : 0;", "const a = [<div>x</div>];",
    "const a = { k: <div>x</div> };", "const a = f(<div>x</div>);", "const a = obj.m(<div>x</div>);",
    "const a = new C(<div>x</div>);", "const a = () => <div>x</div>;", "const a = () => { return <div>x</div>; };",
    "function f() { return <div>x</div>; }", "const a = `t${<div>x</div>}`;", "const a = await <div>x</div>;",
    "if (c) { const a = <div>x</div>; }", "for (const x of xs) { const a = <div>x</div>; }",
    "while (c) { const a = <div>x</div>; }", "try { const a = <div>x</div>; } catch (e) {}",
    "switch (k) { case 1: { const a = <div>x</div>; } }", "const a = <div attr={<span>y</span>}>x</div>;",
    "const a = <div>{<span>y</span>}</div>;", "class C { m() { return <div>x</div>; } }",
  ]
  for src in cases {
    assert_true(
      has_not_javascript(src),
      msg="the walk did not reach the JSX in: \{src}",
    )
  }
}

///|
test "verify: an `as` / `satisfies` / `!` left in the output is not JavaScript" {
  assert_true(has_not_javascript("const a = x as number;"))
  assert_true(has_not_javascript("const a = x satisfies number;"))
  assert_true(has_not_javascript("const a = x!;"))
  // And nested, for the same reason as above.
  assert_true(has_not_javascript("const a = f(x as number);"))
  assert_true(has_not_javascript("const a = [x!];"))
}

///|
test "verify: a `type` import specifier is not JavaScript" {
  // `import { type Point } from "…"` is the case
  // `record_external_import` documented as one this verifier could not
  // catch. It can now — the check reads the parsed import metadata,
  // which is exact rather than a walk.
  assert_true(
    has_not_javascript(
      "import { type Point, add } from \"lib\";\nexport const a = add(1);",
    ),
  )
  assert_true(
    has_not_javascript(
      "import type { Point } from \"lib\";\nexport const a = 1;",
    ),
  )
  // A plain value import must stay quiet.
  assert_false(
    has_not_javascript("import { add } from \"lib\";\nexport const a = add(1);"),
  )
}

///|
test "verify: TypeArgs is deliberately not reported" {
  // `f<T>(x)` is TypeScript, but `a < b > (c)` is valid JavaScript that
  // this parser may resolve the same way. A verifier that reports valid
  // output gets turned off, so this one stays quiet here on purpose.
  assert_false(has_not_javascript("const a = f < b > (c);"))
}

///|
test "verify: an unparsable bundle is a violation" {
  assert_true(violation_kinds("const = = =;").contains("unparsable"))
}
