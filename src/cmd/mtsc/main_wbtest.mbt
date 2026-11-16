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
    false,
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

///|
/// One bare specifier can name two different packages: a nested
/// `node_modules` shadows the outer one for the files under it, and each
/// importer's edge has to point at ITS resolution — the bundler's
/// specifier-keyed alias is not enough.
async test "mtsc loader: a nested node_modules gives its importers their own target" {
  let root = "/tmp/ts_mbt_mtsc_nested_versions"
  @fs.rmdir(root, recursive=true) catch {
    _ => ()
  }
  for dir in [root + "/node_modules/lib", root + "/nested/node_modules/lib"] {
    @fs.mkdir(dir, permission=0o755, recursive=true)
    @fs.write_file(
      dir + "/package.json",
      "{\"name\":\"lib\",\"main\":\"./index.ts\"}\n",
      create=0o644,
    )
    @fs.write_file(dir + "/index.ts", "export const v = 1;\n", create=0o644)
  }
  @fs.write_file(
    root + "/a.ts",
    "import { v } from \"lib\";\nexport const a = v;\n",
    create=0o644,
  )
  @fs.write_file(
    root + "/nested/b.ts",
    "import { v } from \"lib\";\nexport const b = v;\n",
    create=0o644,
  )
  @fs.write_file(
    root + "/entry.ts",
    "import { a } from \"./a\";\nimport { b } from \"./nested/b\";\nexport const s = a + b;\n",
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
    false,
  )
  assert_true(loaded is Ok(_))
  let target_of = fn(importer_suffix : String) -> String? {
    for edge in edges {
      if edge.importerPath.has_suffix(importer_suffix) &&
        edge.moduleSpecifier == "lib" {
        return Some(edge.targetPath)
      }
    }
    None
  }
  assert_true(
    target_of("/a.ts")
    .unwrap_or("")
    .has_suffix("ts_mbt_mtsc_nested_versions/node_modules/lib/index.ts"),
  )
  assert_true(
    target_of("/nested/b.ts")
    .unwrap_or("")
    .has_suffix("nested/node_modules/lib/index.ts"),
  )
}

///|
/// `-p` reads the checker's options through the WHOLE `extends` chain, and
/// a package specifier (`"extends": "@scope/cfg/tsconfigs/base"`) is
/// resolved through `node_modules` — univer's packages all extend one that
/// way, and joining it onto the package directory named nothing.
async test "mtsc -p: checker options come through a package extends" {
  let root = "/tmp/ts_mbt_mtsc_extends_pkg"
  @fs.rmdir(root, recursive=true) catch {
    _ => ()
  }
  @fs.mkdir(
    root + "/node_modules/@scope/cfg/tsconfigs",
    permission=0o755,
    recursive=true,
  )
  @fs.write_file(
    root + "/node_modules/@scope/cfg/tsconfigs/base.json",
    "{\n  // JSONC\n  \"compilerOptions\": { \"strict\": true, \"strictPropertyInitialization\": false, \"experimentalDecorators\": true, \"lib\": [\"ESNext\", \"DOM\"] }\n}\n",
    create=0o644,
  )
  @fs.write_file(
    root + "/tsconfig.json",
    "{ \"extends\": \"@scope/cfg/tsconfigs/base\", \"compilerOptions\": { \"noImplicitOverride\": true } }\n",
    create=0o644,
  )
  let opts = mtsc_options_new()
  mtsc_apply_project_compiler_options(opts, root + "/tsconfig.json")
  let got : Map[String, String] = Map([])
  for entry in opts.checker_options {
    got[entry.0] = entry.1
  }
  assert_eq(got.get("strict"), Some("true"))
  assert_eq(got.get("strictPropertyInitialization"), Some("false"))
  assert_eq(got.get("experimentalDecorators"), Some("true"))
  assert_eq(got.get("noImplicitOverride"), Some("true"))
  assert_eq(got.get("lib"), Some("ESNext,DOM"))
  assert_eq(got.get("noImplicitAny"), None)
}

///|
/// The boolean options the checker reads are HONOURED on the command line
/// (they used to be reported as "accepted but not honoured"), keep their
/// optional `true` / `false` value off the input list, and win over a
/// tsconfig that sets the same name.
async test "mtsc: checker flags on the command line are honoured" {
  let opts = mtsc_parse_args(
    [
      "mtsc", "--strict", "false", "--experimentalDecorators", "--no-implicit-override=true",
      "--target", "es5", "a.ts",
    ],
    1,
  ).unwrap()
  assert_eq(opts.inputs, ["a.ts"])
  assert_eq(opts.checker_options, [
    ("strict", "false"),
    ("experimentalDecorators", "true"),
    ("noImplicitOverride", "true"),
  ])
  // `--target` still changes nothing about the output and says so.
  assert_eq(opts.ignored, ["--target"])
  // A checker boolean the no-effect table does not list is still an
  // option, not an unknown one.
  let catch_vars = mtsc_parse_args(
    ["mtsc", "--useUnknownInCatchVariables", "false", "a.ts"],
    1,
  ).unwrap()
  assert_eq(catch_vars.checker_options, [
    ("useUnknownInCatchVariables", "false"),
  ])
  assert_eq(catch_vars.inputs, ["a.ts"])
  let root = "/tmp/ts_mbt_mtsc_cli_beats_config"
  @fs.rmdir(root, recursive=true) catch {
    _ => ()
  }
  @fs.mkdir(root, permission=0o755, recursive=true)
  @fs.write_file(
    root + "/tsconfig.json",
    "{ \"compilerOptions\": { \"strict\": true, \"noImplicitAny\": true } }\n",
    create=0o644,
  )
  mtsc_apply_project_compiler_options(opts, root + "/tsconfig.json")
  let got : Map[String, String] = Map([])
  for entry in opts.checker_options {
    got[entry.0] = entry.1
  }
  assert_eq(got.get("strict"), Some("false"))
  assert_eq(got.get("noImplicitAny"), Some("true"))
}

///|
/// An ABSOLUTE `extends` names the file itself; joining it onto the
/// config's directory read some other path and lost every inherited
/// option.
async test "mtsc -p: an absolute extends path is read as written" {
  let root = "/tmp/ts_mbt_mtsc_extends_abs"
  @fs.rmdir(root, recursive=true) catch {
    _ => ()
  }
  @fs.mkdir(root + "/app", permission=0o755, recursive=true)
  @fs.mkdir(root + "/shared", permission=0o755, recursive=true)
  @fs.write_file(
    root + "/shared/base.json",
    "{ \"compilerOptions\": { \"experimentalDecorators\": true } }\n",
    create=0o644,
  )
  @fs.write_file(
    root + "/app/tsconfig.json",
    "{ \"extends\": \"" + root + "/shared/base.json\" }\n",
    create=0o644,
  )
  let opts = mtsc_options_new()
  mtsc_apply_project_compiler_options(opts, root + "/app/tsconfig.json")
  assert_eq(opts.checker_options, [("experimentalDecorators", "true")])
}

///|
/// Several `--noEmit` entries are one program only when the graph check
/// takes every one of them. A `.cts` it filters out must not vanish
/// because a sibling is checkable: the run falls back to entry by entry,
/// and the `.cts` error is still reported.
async test "mtsc: a --noEmit entry the graph check cannot take is still checked" {
  let root = "/tmp/ts_mbt_mtsc_cts_entry"
  @fs.rmdir(root, recursive=true) catch {
    _ => ()
  }
  @fs.mkdir(root, permission=0o755, recursive=true)
  @fs.write_file(root + "/a.ts", "export const a = 1;\n", create=0o644)
  @fs.write_file(
    root + "/b.cts",
    "export const n: number = \"bad\";\n",
    create=0o644,
  )
  let opts = mtsc_options_new()
  opts.no_emit = true
  let failed = mtsc_compile_all(opts, [root + "/a.ts", root + "/b.cts"])
  assert_true(failed > 0)
  // Two clean `.ts` entries still go through the combined check, cleanly.
  @fs.write_file(root + "/c.ts", "export const c = 2;\n", create=0o644)
  assert_eq(mtsc_compile_all(opts, [root + "/a.ts", root + "/c.ts"]), 0)
}
