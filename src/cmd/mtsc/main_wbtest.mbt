///|
test "mtsc typecheck detects a function return mismatch" {
  let issues = mtsc_collect_type_issues(
    "function formatScore(score: number): string { return score; }", false,
  ).unwrap()
  assert_true(issues.length() == 1)
  assert_true(issues[0].message.contains("expected `string` but got `number`"))
}

///|
test "mtsc typecheck accepts a valid function" {
  let issues = mtsc_collect_type_issues(
    "function formatScore(score: number): string { return \"score: \" + score; }",
    false,
  ).unwrap()
  assert_true(issues.length() == 0)
}

///|
test "mtsc typecheck accepts an imported binding" {
  let issues = mtsc_collect_type_issues(
    "import { formatScore } from \"./score\";\nconst result = formatScore(1);", false,
  ).unwrap()
  assert_true(issues.length() == 0)
}

///|
async test "mtsc known-gap corpus records current missed diagnostics" {
  let cases = [
    "fixtures/mtsc/known-gaps/no-implicit-any.ts", "fixtures/mtsc/known-gaps/primitive-member.ts",
    "fixtures/mtsc/known-gaps/aliased-discriminant.ts",
  ]
  for path in cases {
    let source = @fs.read_file(path).text() catch {
      e => fail("failed to read known mtsc gap fixture \{path}: \{e}")
    }
    let issues = mtsc_collect_type_issues(source, false).unwrap()
    assert_eq(issues.length(), 0)
  }
}

///|
/// `overload-resolution.ts` used to be one of the known gaps above and is
/// now CLOSED, so it moves from "records what we miss" to a regression
/// pin. Overload sets ingest as a union of call signatures, and
/// `check_union_callee_arity` is deliberately not applied to them (its
/// rule is that every member must accept, which is right for a
/// union-typed value and wrong for an overload set). Nothing took over,
/// so an overloaded call's arguments were checked by nothing at all —
/// `check_overload_set_no_match` reports when NO member can accept.
async test "mtsc reports TS2769 for a call matching no overload" {
  let path = "fixtures/mtsc/known-gaps/overload-resolution.ts"
  let source = @fs.read_file(path).text() catch {
    e => fail("failed to read \{path}: \{e}")
  }
  let issues = mtsc_collect_type_issues(source, false).unwrap()
  assert_true(issues.length() > 0)
  let mut found = false
  for i in issues {
    if i.message.contains("no overload matches this call") {
      found = true
    }
  }
  assert_true(found)
}

///|
test "mtsc flags: --mangle-properties selects the analyzed path" {
  // The escape analysis lives in `bundle_modules`. Without `--bundle`
  // the single-file path renamed property keys with no analysis at all,
  // including a CJS module's `exports.foo`, so the flag has to bring
  // the path that can prove the rename safe.
  for
    flag in [
      "--mangle-properties", "--explain-mangle", "--mangle-properties-shape-color",
    ] {
    let opts = mtsc_parse_args(["mtsc", "in.ts", flag], 1).unwrap()
    assert_true(opts.mangle_properties)
    assert_true(opts.bundle)
  }
  // `--mangle` alone only renames locals, and the single-file path
  // reserves every top-level name, so it stays where it was.
  let plain = mtsc_parse_args(["mtsc", "in.ts", "--mangle"], 1).unwrap()
  assert_true(plain.mangle)
  assert_false(plain.mangle_properties)
  assert_false(plain.bundle)
}

///|
test "mtsc flags: --no-check is off unless asked for" {
  assert_false(mtsc_parse_args(["mtsc", "in.ts"], 1).unwrap().no_check)
  assert_true(
    mtsc_parse_args(["mtsc", "in.ts", "--no-check"], 1).unwrap().no_check,
  )
}

///|
/// TypeScript's `node16` / `nodenext` / `bundler` resolution keeps the
/// EMITTED extension in the specifier, so a TS codebase writes
/// `import … from "./external.js"` next to `external.ts`. Without this
/// rule the whole class of TypeScript-source targets is unreachable —
/// zod and TypeScript's own compiler (`./_namespaces/ts.js`) both fail
/// on their first import.
test "mtsc resolve: a .js specifier may name a .ts file" {
  let cases = [
    ("./external.js", ["./external.ts", "./external.tsx", "./external.d.ts"]),
    ("a/b.mjs", ["a/b.mts", "a/b.d.mts"]),
    ("a/b.cjs", ["a/b.cts", "a/b.d.cts"]),
  ]
  for c in cases {
    let got = mtsc_ts_equivalents(c.0)
    assert_eq(got.length(), c.1.length())
    for i, want in c.1 {
      assert_eq(got[i], want)
    }
  }
  // A specifier that is not JS-spelled leaves the ordinary extension
  // search alone.
  assert_eq(mtsc_ts_equivalents("./external").length(), 0)
  assert_eq(mtsc_ts_equivalents("./external.ts").length(), 0)
  assert_eq(mtsc_ts_equivalents("./styles.css").length(), 0)
}

///|
/// The bundler resolves a bare specifier once, keyed by the specifier
/// alone, and the loader used to skip the EDGE for every later importer
/// of it. The checker reads one edge per importer, so whichever file the
/// queue happened to reach second lost its `@univerjs/core` import
/// outright — and with it the per-module key a named import needs when two
/// packages declare the same interface name.
async test "mtsc loader: every importer of a bare specifier gets its own edge" {
  let root = "/tmp/ts_mbt_mtsc_bare_edges"
  @fs.rmdir(root, recursive=true) catch {
    _ => ()
  }
  @fs.mkdir(root + "/node_modules/lib", permission=0o755, recursive=true)
  @fs.write_file(
    root + "/node_modules/lib/package.json",
    "{\"name\":\"lib\",\"main\":\"./index.ts\"}\n",
    create=0o644,
  )
  @fs.write_file(
    root + "/node_modules/lib/index.ts",
    "export const v = 1;\n",
    create=0o644,
  )
  @fs.write_file(
    root + "/a.ts",
    "import { v } from \"lib\";\nexport const a = v;\n",
    create=0o644,
  )
  @fs.write_file(
    root + "/b.ts",
    "import { v } from \"lib\";\nexport const b = v;\n",
    create=0o644,
  )
  @fs.write_file(
    root + "/entry.ts",
    "import { a } from \"./a\";\nimport { b } from \"./b\";\nexport const s = a + b;\n",
    create=0o644,
  )
  let edges : Array[@mtsc_core.MtscModuleEdge] = []
  let loaded = mtsc_load_bundle_files(
    root + "/entry.ts",
    {},
    {},
    {},
    {},
    false,
    [],
    {},
    edges,
  )
  assert_true(loaded is Ok(_))
  let importers : Array[String] = []
  for edge in edges {
    if edge.moduleSpecifier == "lib" {
      importers.push(edge.importerPath)
    }
  }
  importers.sort()
  assert_eq(importers, [root + "/a.ts", root + "/b.ts"])
}
