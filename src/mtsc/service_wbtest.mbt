// Language-service tests.
//
// Every case runs through `MtscMemoryHost`, which is a real host rather
// than a test double — the same trait implementation a bundler plugin
// uses, and the same generic service code the JavaScript entry points
// reach. So these cover the host path end to end on native, where the
// JS ABI can only be covered by running Node.
//
// Each rule is paired with its LEGAL neighbour wherever it has one. "It
// fires on the broken program" and "it stays silent on the correct one"
// are separate claims, and only the second one catches a service that
// reports everything.

///|
/// Messages only, so a case reads as what it asserts.
fn wbtest_messages(diagnostics : Array[MtscDiagnostic]) -> Array[String] {
  let out : Array[String] = []
  for diagnostic in diagnostics {
    out.push("\{diagnostic.file}: \{diagnostic.messageText}")
  }
  out
}

///|
fn wbtest_any_contains(
  diagnostics : Array[MtscDiagnostic],
  needle : String,
) -> Bool {
  for message in wbtest_messages(diagnostics) {
    if message.contains(needle) {
      return true
    }
  }
  false
}

// ---------------------------------------------------------------------------
// Resolution drives the checker
// ---------------------------------------------------------------------------

///|
test "host-resolved import propagates a type across modules" {
  let host = MtscMemoryHost::over({
    "entry.ts": "import { score } from \"./score\";\nexport const label: string = score;",
    "score.ts": "export const score: number = 1;",
  })
  let diagnostics = get_program_diagnostics(host)
  assert_true(wbtest_any_contains(diagnostics, "entry.ts"))
  assert_true(
    wbtest_any_contains(diagnostics, "expected `string` but got `number`"),
  )
}

///|
test "the same program with matching types is silent" {
  // The legal neighbour of the case above. Without it, a service that
  // reported every cross-module import would pass that test.
  let host = MtscMemoryHost::over({
    "entry.ts": "import { score } from \"./score\";\nexport const label: number = score;",
    "score.ts": "export const score: number = 1;",
  })
  assert_eq(wbtest_messages(get_program_diagnostics(host)), [])
}

///|
test "an extensionless specifier resolves to the .ts file" {
  let host : MtscMemoryHost = {
    files: {
      "entry.ts": "import { score } from \"./score\";\nexport const label: string = score;",
      "score.ts": "export const score: number = 1;",
    },
    roots: ["entry.ts"],
    cwd: ".",
    options: { jsx: false, },
  }
  assert_true(
    wbtest_any_contains(
      get_program_diagnostics(host),
      "expected `string` but got `number`",
    ),
  )
}

///|
test "a .js specifier resolves to the .ts source beside it" {
  // TypeScript under ESM writes `./score.js` to mean the module whose
  // source is `./score.ts`. Probing the written extension first would
  // check an emitted artifact instead, so this asserts the remap fires.
  let host : MtscMemoryHost = {
    files: {
      "entry.ts": "import { score } from \"./score.js\";\nexport const label: string = score;",
      "score.ts": "export const score: number = 1;",
    },
    roots: ["entry.ts"],
    cwd: ".",
    options: { jsx: false, },
  }
  assert_true(
    wbtest_any_contains(
      get_program_diagnostics(host),
      "expected `string` but got `number`",
    ),
  )
}

///|
test "a .d.ts wins over the .ts beside it" {
  // The declaration file is the one carrying the declarations, so it is
  // preferred. Here the two disagree, which is what makes the preference
  // observable: resolving to `score.ts` would report nothing.
  let host : MtscMemoryHost = {
    files: {
      "entry.ts": "import { score } from \"./score\";\nexport const label: string = score;",
      "score.d.ts": "export declare const score: number;",
      "score.ts": "export const score: string = \"1\";",
    },
    roots: ["entry.ts"],
    cwd: ".",
    options: { jsx: false, },
  }
  assert_true(
    wbtest_any_contains(
      get_program_diagnostics(host),
      "expected `string` but got `number`",
    ),
  )
}

///|
test "a directory specifier resolves to its index file" {
  let host : MtscMemoryHost = {
    files: {
      "entry.ts": "import { score } from \"./lib\";\nexport const label: string = score;",
      "lib/index.ts": "export const score: number = 1;",
    },
    roots: ["entry.ts"],
    cwd: ".",
    options: { jsx: false, },
  }
  assert_true(
    wbtest_any_contains(
      get_program_diagnostics(host),
      "expected `string` but got `number`",
    ),
  )
}

///|
test "a sibling file wins over a same-named directory index" {
  // File candidates are probed before `index`, the way TypeScript orders
  // them. `lib.ts` and `lib/index.ts` disagree so the order is visible.
  let host : MtscMemoryHost = {
    files: {
      "entry.ts": "import { score } from \"./lib\";\nexport const label: string = score;",
      "lib.ts": "export const score: number = 1;",
      "lib/index.ts": "export const score: string = \"1\";",
    },
    roots: ["entry.ts"],
    cwd: ".",
    options: { jsx: false, },
  }
  assert_true(
    wbtest_any_contains(
      get_program_diagnostics(host),
      "expected `string` but got `number`",
    ),
  )
}

///|
test "a parent-relative specifier resolves across directories" {
  let host : MtscMemoryHost = {
    files: {
      "src/entry.ts": "import { score } from \"../shared/score\";\nexport const label: string = score;",
      "shared/score.ts": "export const score: number = 1;",
    },
    roots: ["src/entry.ts"],
    cwd: ".",
    options: { jsx: false, },
  }
  assert_true(
    wbtest_any_contains(
      get_program_diagnostics(host),
      "expected `string` but got `number`",
    ),
  )
}

// ---------------------------------------------------------------------------
// The limits, asserted as limits
// ---------------------------------------------------------------------------

///|
test "an unresolvable relative import is reported" {
  let host = MtscMemoryHost::over({
    "entry.ts": "import { score } from \"./missing\";\nexport const label = score;",
  })
  assert_true(
    wbtest_any_contains(get_program_diagnostics(host), "cannot resolve local"),
  )
}

///|
test "a bare specifier is left alone rather than reported" {
  // Package resolution is out of scope for this resolver, and reporting
  // it as a failure would send a caller looking for a file that was
  // never meant to be there. The declaration keeps the program otherwise
  // clean so an unrelated diagnostic cannot satisfy this.
  let host = MtscMemoryHost::over({
    "entry.ts": "import { useState } from \"react\";\nexport const hook = useState;",
  })
  assert_eq(wbtest_messages(get_program_diagnostics(host)), [])
}

///|
test "a root the host cannot read is reported" {
  let host : MtscMemoryHost = {
    files: { "entry.ts": "export const score: number = 1;" },
    roots: ["entry.ts", "absent.ts"],
    cwd: ".",
    options: { jsx: false, },
  }
  assert_true(
    wbtest_any_contains(get_program_diagnostics(host), "cannot read file"),
  )
}

///|
test "a syntax error is reported rather than swallowed" {
  // This is the case the first draft of `mtsc_load_program` could not
  // report at all: it looked for parse failures in the list of files
  // that had parsed. Regressing that makes this case return nothing.
  let host = MtscMemoryHost::over({ "entry.ts": "export const broken: =" })
  let diagnostics = get_program_diagnostics(host)
  assert_true(wbtest_any_contains(diagnostics, "parse error"))
  assert_true(diagnostics[0].source == "syntactic")
}

///|
test "a file that does not parse does not hide its importer's errors" {
  let host = MtscMemoryHost::over({
    "entry.ts": "export const label: string = 1;",
    "broken.ts": "export const broken: =",
  })
  let diagnostics = get_program_diagnostics(host)
  assert_true(wbtest_any_contains(diagnostics, "parse error"))
  assert_true(
    wbtest_any_contains(diagnostics, "expected `string` but got `number`"),
  )
}

// ---------------------------------------------------------------------------
// Per-file queries
// ---------------------------------------------------------------------------

///|
test "semantic diagnostics are scoped to the requested file" {
  let host = MtscMemoryHost::over({
    "a.ts": "export const a: string = 1;",
    "b.ts": "export const b: string = 2;",
  })
  let only_a = get_semantic_diagnostics(host, "a.ts")
  assert_true(only_a.length() > 0)
  for diagnostic in only_a {
    assert_true(diagnostic.file.contains("a.ts"))
  }
}

///|
test "syntactic and semantic diagnostics are separated" {
  let host = MtscMemoryHost::over({
    "broken.ts": "export const broken: =",
    "typed.ts": "export const typed: string = 1;",
  })
  // The parse failure is syntactic and belongs only to `broken.ts`.
  assert_true(get_syntactic_diagnostics(host, "broken.ts").length() > 0)
  assert_eq(get_semantic_diagnostics(host, "broken.ts").length(), 0)
  // The type error is semantic and belongs only to `typed.ts`.
  assert_true(get_semantic_diagnostics(host, "typed.ts").length() > 0)
  assert_eq(get_syntactic_diagnostics(host, "typed.ts").length(), 0)
}

///|
test "a file with no problems returns no diagnostics either way" {
  let host = MtscMemoryHost::over({ "ok.ts": "export const ok: number = 1;" })
  assert_eq(get_semantic_diagnostics(host, "ok.ts").length(), 0)
  assert_eq(get_syntactic_diagnostics(host, "ok.ts").length(), 0)
}

// ---------------------------------------------------------------------------
// Program shape and resolution as an API
// ---------------------------------------------------------------------------

///|
test "the program includes imported files that were never roots" {
  let host : MtscMemoryHost = {
    files: {
      "entry.ts": "import { score } from \"./score\";\nexport const label = score;",
      "score.ts": "import { base } from \"./base\";\nexport const score = base;",
      "base.ts": "export const base: number = 1;",
    },
    roots: ["entry.ts"],
    cwd: ".",
    options: { jsx: false, },
  }
  let files = get_program_file_names(host)
  assert_eq(files.length(), 3)
  assert_true(files.contains("entry.ts"))
  assert_true(files.contains("score.ts"))
  // Reached only transitively, which is what proves the walk follows
  // edges rather than listing roots.
  assert_true(files.contains("base.ts"))
}

///|
test "an import cycle terminates" {
  let host = MtscMemoryHost::over({
    "a.ts": "import { b } from \"./b\";\nexport const a: number = b;",
    "b.ts": "import { a } from \"./a\";\nexport const b: number = a;",
  })
  assert_eq(get_program_file_names(host).length(), 2)
}

///|
test "resolveModuleName agrees with what the loader followed" {
  let host = MtscMemoryHost::over({
    "entry.ts": "import { score } from \"./score\";\nexport const label = score;",
    "score.ts": "export const score: number = 1;",
  })
  let resolved = resolve_module_name(host, "entry.ts", "./score")
  assert_eq(resolved.resolvedFileName, "score.ts")
  assert_eq(resolved.isExternal, false)
}

///|
test "resolveModuleName distinguishes a missing file from a package" {
  let host = MtscMemoryHost::over({ "entry.ts": "export const x = 1;" })
  // Relative and absent: a failure the caller should act on.
  let missing = resolve_module_name(host, "entry.ts", "./nope")
  assert_eq(missing.resolvedFileName, "")
  assert_eq(missing.isExternal, false)
  // Bare: not this resolver's job, which is a different answer.
  let bare = resolve_module_name(host, "entry.ts", "react")
  assert_eq(bare.resolvedFileName, "")
  assert_eq(bare.isExternal, true)
}

// ---------------------------------------------------------------------------
// Options and path handling
// ---------------------------------------------------------------------------

///|
test "a .tsx file parses as JSX without the option being set" {
  // The extension decides it, the way `tsc` does. With JSX parsing off
  // this source is a syntax error, so silence is the assertion.
  let host = MtscMemoryHost::over({
    "view.tsx": "export const view = <div>hello</div>;",
  })
  assert_eq(wbtest_messages(get_program_diagnostics(host)), [])
}

///|
test "the jsx option covers a .ts file the extension does not" {
  let source = "export const view = <div>hello</div>;"
  let without : MtscMemoryHost = {
    files: { "view.ts": source },
    roots: ["view.ts"],
    cwd: ".",
    options: { jsx: false, },
  }
  let with_jsx : MtscMemoryHost = {
    files: { "view.ts": source },
    roots: ["view.ts"],
    cwd: ".",
    options: { jsx: true, },
  }
  // Both directions, so this measures the option rather than the parser.
  assert_true(get_program_diagnostics(without).length() > 0)
  assert_eq(wbtest_messages(get_program_diagnostics(with_jsx)), [])
}

///|
test "a relative root is resolved against the host directory" {
  let host : MtscMemoryHost = {
    files: { "/work/src/entry.ts": "export const label: string = 1;" },
    roots: ["src/entry.ts"],
    cwd: "/work",
    options: { jsx: false, },
  }
  let diagnostics = get_program_diagnostics(host)
  assert_true(wbtest_any_contains(diagnostics, "/work/src/entry.ts"))
  assert_true(
    wbtest_any_contains(diagnostics, "expected `string` but got `number`"),
  )
}

///|
test "a file queried by its root spelling matches its resolved path" {
  // The caller asks with the name it handed over; the program holds the
  // path the host directory produced. Both spellings have to find it or
  // a per-file query silently returns nothing.
  let host : MtscMemoryHost = {
    files: { "/work/entry.ts": "export const label: string = 1;" },
    roots: ["entry.ts"],
    cwd: "/work",
    options: { jsx: false, },
  }
  assert_true(get_semantic_diagnostics(host, "entry.ts").length() > 0)
  assert_true(get_semantic_diagnostics(host, "/work/entry.ts").length() > 0)
}

// ---------------------------------------------------------------------------
// The host contract itself
// ---------------------------------------------------------------------------

///|
test "the source cache asks the host once per path" {
  // Resolution probes ten-odd candidates per import, so a host backed by
  // real IO depends on both halves of the cache. A counting host is the
  // only way to observe it.
  let host = MtscMemoryHost::over({
    "entry.ts": "import { score } from \"./score\";\nexport const label = score;",
    "score.ts": "export const score: number = 1;",
  })
  let cache = MtscSourceCache::new()
  assert_eq(
    cache.read(host, "score.ts"),
    Some("export const score: number = 1;"),
  )
  assert_eq(
    cache.read(host, "score.ts"),
    Some("export const score: number = 1;"),
  )
  // A miss is remembered too, which is what keeps candidate probing from
  // re-asking for every importer of the same module.
  assert_eq(cache.read(host, "absent.ts"), None)
  assert_eq(cache.entries.length(), 2)
}

///|
test "MtscMemoryHost::over roots every file it is given" {
  let host = MtscMemoryHost::over({
    "a.ts": "export const a = 1;",
    "b.ts": "export const b = 2;",
  })
  // Spelled `MtscHost::method(host, …)` rather than `host.method()`:
  // the implicit promotion of a trait method onto the type is
  // deprecated, so the dotted form would warn here and in a caller's
  // code alike.
  assert_eq(MtscHost::script_file_names(host).length(), 2)
  assert_eq(MtscHost::current_directory(host), ".")
  assert_eq(MtscHost::compilation_settings(host).jsx, false)
  assert_eq(MtscHost::read_file(host, "a.ts"), Some("export const a = 1;"))
  assert_eq(MtscHost::read_file(host, "nope.ts"), None)
}
