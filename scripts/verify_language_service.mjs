#!/usr/bin/env node
// Does the JavaScript language service actually work?
//
// `moon test` covers the service on native through `MtscMemoryHost`, and
// that is the bulk of the coverage — same generic code, same resolution,
// 35 cases. What it cannot cover is everything between MoonBit and
// JavaScript: the `extern "js"` host calls, `undefined` arriving as
// `None`, a JS array arriving as a `FixedArray`, a MoonBit struct
// leaving as a plain object, and the facade on top. Those only exist
// when Node runs the compiled module.
//
// Three host kinds are exercised deliberately:
//
//   memory  — the bundler-plugin case, sources already in hand
//   node    — a REAL filesystem under a temp directory, which is the
//             case that proves injected IO reaches actual disk rather
//             than a map that happens to look like one
//   ts-like — a host with `getScriptSnapshot` and no `readFile`, i.e.
//             the shape a genuine `ts.LanguageServiceHost` has, which is
//             the compatibility claim the API makes
//
// Every case that asserts a diagnostic is paired with the legal
// neighbour that must stay silent. "It reports the broken program" and
// "it does not report the correct one" are separate claims, and only the
// second catches a service that reports everything.
//
//   node scripts/verify_language_service.mjs
//   node scripts/verify_language_service.mjs --verbose

import { mkdtempSync, mkdirSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, dirname } from "node:path";

import {
  checkModuleGraph,
  createLanguageService,
  createMemoryHost,
  createNodeHost,
  formatDiagnostics,
} from "../js/language-service.mjs";

const VERBOSE = process.argv.includes("--verbose");

let passed = 0;
const failures = [];

function check(name, fn) {
  try {
    fn();
    passed += 1;
    if (VERBOSE) console.log(`  ok   ${name}`);
  } catch (error) {
    failures.push({ name, error });
    console.log(`  FAIL ${name}\n       ${error.message}`);
  }
}

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

function assertEqual(actual, expected, message) {
  const a = JSON.stringify(actual);
  const e = JSON.stringify(expected);
  if (a !== e) throw new Error(`${message}\n       expected ${e}\n       got      ${a}`);
}

/** Every message, so a failure prints something actionable. */
function messages(diagnostics) {
  return diagnostics.map((d) => `${d.file}: ${d.messageText}`);
}

function hasMessage(diagnostics, needle) {
  return messages(diagnostics).some((m) => m.includes(needle));
}

// ---------------------------------------------------------------------------
// Memory host
// ---------------------------------------------------------------------------

const BROKEN_PROGRAM = {
  "/p/entry.ts": 'import { score } from "./score";\nexport const label: string = score;',
  "/p/score.ts": "export const score: number = 1;",
};

// Identical but for the annotation, which is what makes the pair a
// measurement of the rule rather than of the plumbing.
const CLEAN_PROGRAM = {
  "/p/entry.ts": 'import { score } from "./score";\nexport const label: number = score;',
  "/p/score.ts": "export const score: number = 1;",
};

check("memory host: a type error across modules is reported", () => {
  const service = createLanguageService(createMemoryHost(BROKEN_PROGRAM));
  const diagnostics = service.getProgramDiagnostics();
  assert(
    hasMessage(diagnostics, "expected `string` but got `number`"),
    `no cross-module diagnostic: ${JSON.stringify(messages(diagnostics))}`,
  );
  assertEqual(diagnostics[0].source, "semantic", "wrong source");
  assertEqual(diagnostics[0].category, "error", "wrong category");
  assert(diagnostics[0].context.length > 0, "expected a breadcrumb");
});

check("memory host: the same program with matching types is silent", () => {
  const service = createLanguageService(createMemoryHost(CLEAN_PROGRAM));
  assertEqual(messages(service.getProgramDiagnostics()), [], "expected silence");
});

check("memory host: the program includes files reached only by import", () => {
  const service = createLanguageService(
    createMemoryHost(BROKEN_PROGRAM, { rootNames: ["/p/entry.ts"] }),
  );
  const files = service.getProgramFileNames();
  assertEqual(files.length, 2, `expected 2 files, got ${JSON.stringify(files)}`);
  assert(files.includes("/p/score.ts"), "transitive file missing from program");
});

check("memory host: diagnostics carry no fabricated span", () => {
  // The API documents that `start` / `length` are absent because the
  // checker has no offsets. If they ever appear, either the checker
  // gained positions (good, update the docs) or something invented them.
  const service = createLanguageService(createMemoryHost(BROKEN_PROGRAM));
  const diagnostic = service.getProgramDiagnostics()[0];
  assert(!("start" in diagnostic), "unexpected `start` on a diagnostic");
  assert(!("length" in diagnostic), "unexpected `length` on a diagnostic");
  assertEqual(
    Object.keys(diagnostic).sort(),
    ["category", "context", "file", "messageText", "source"],
    "diagnostic shape changed",
  );
});

// ---------------------------------------------------------------------------
// Resolution limits, asserted as limits
// ---------------------------------------------------------------------------

check("an unresolvable relative import is reported", () => {
  const service = createLanguageService(
    createMemoryHost({
      "/p/entry.ts": 'import { x } from "./missing";\nexport const y = x;',
    }),
  );
  assert(
    hasMessage(service.getProgramDiagnostics(), "cannot resolve local"),
    "expected an unresolved-module diagnostic",
  );
});

check("a bare specifier is left alone rather than reported", () => {
  // Package resolution is out of scope, and calling that a failure would
  // send a caller looking for a file that was never meant to exist.
  const service = createLanguageService(
    createMemoryHost({
      "/p/entry.ts": 'import { useState } from "react";\nexport const h = useState;',
    }),
  );
  assertEqual(
    messages(service.getProgramDiagnostics()),
    [],
    "a bare import should not be a diagnostic",
  );
});

check("resolveModuleName separates a missing file from a package", () => {
  const service = createLanguageService(createMemoryHost(BROKEN_PROGRAM));
  assertEqual(
    service.resolveModuleName("/p/entry.ts", "./score"),
    { resolvedFileName: "/p/score.ts", isExternal: false },
    "relative resolution",
  );
  assertEqual(
    service.resolveModuleName("/p/entry.ts", "./nope"),
    { resolvedFileName: "", isExternal: false },
    "a missing relative module is a failure, not external",
  );
  assertEqual(
    service.resolveModuleName("/p/entry.ts", "react"),
    { resolvedFileName: "", isExternal: true },
    "a bare specifier is external",
  );
});

// ---------------------------------------------------------------------------
// Syntactic vs semantic
// ---------------------------------------------------------------------------

check("syntactic and semantic diagnostics are separated", () => {
  const service = createLanguageService(
    createMemoryHost({
      "/p/broken.ts": "export const broken: =",
      "/p/typed.ts": "export const typed: string = 1;",
    }),
  );
  assert(
    service.getSyntacticDiagnostics("/p/broken.ts").length > 0,
    "expected a parse error for broken.ts",
  );
  assertEqual(
    service.getSemanticDiagnostics("/p/broken.ts").length,
    0,
    "a parse error is not a semantic diagnostic",
  );
  assert(
    service.getSemanticDiagnostics("/p/typed.ts").length > 0,
    "expected a type error for typed.ts",
  );
  assertEqual(
    service.getSyntacticDiagnostics("/p/typed.ts").length,
    0,
    "a type error is not a syntactic diagnostic",
  );
});

check("a clean file returns nothing either way", () => {
  const service = createLanguageService(
    createMemoryHost({ "/p/ok.ts": "export const ok: number = 1;" }),
  );
  assertEqual(service.getSemanticDiagnostics("/p/ok.ts").length, 0, "semantic");
  assertEqual(service.getSyntacticDiagnostics("/p/ok.ts").length, 0, "syntactic");
});

// ---------------------------------------------------------------------------
// Node host: the real filesystem
// ---------------------------------------------------------------------------

const root = mkdtempSync(join(tmpdir(), "mtsc-ls-"));

function write(relative, contents) {
  const target = join(root, relative);
  mkdirSync(dirname(target), { recursive: true });
  writeFileSync(target, contents, "utf8");
  return target;
}

try {
  // A layout that exercises the resolver's real cases: an extensionless
  // specifier, a `./x.js` that means `x.ts`, a directory index, and a
  // parent-relative hop.
  const entry = write(
    "src/entry.ts",
    [
      'import { score } from "./score";',
      'import { helper } from "./util.js";',
      'import { shared } from "../shared";',
      'import { deep } from "./nested";',
      "export const label: string = score;",
      "export const all = [helper, shared, deep];",
    ].join("\n"),
  );
  write("src/score.ts", "export const score: number = 1;");
  write("src/util.ts", "export const helper: number = 2;");
  write("src/nested/index.ts", "export const deep: number = 4;");
  write("shared.ts", "export const shared: number = 3;");

  check("node host: a real filesystem program is loaded and checked", () => {
    const service = createLanguageService(createNodeHost([entry]));
    const files = service.getProgramFileNames();
    assertEqual(
      files.length,
      5,
      `expected 5 files from disk, got ${JSON.stringify(files)}`,
    );
    const diagnostics = service.getProgramDiagnostics();
    assert(
      hasMessage(diagnostics, "expected `string` but got `number`"),
      `expected the annotation error: ${JSON.stringify(messages(diagnostics))}`,
    );
    // Exactly one problem: every other import above must have resolved,
    // or an unresolved-module diagnostic would be here too. That is what
    // makes this one assertion cover all four resolution shapes.
    assertEqual(
      diagnostics.length,
      1,
      `expected exactly one diagnostic, got ${JSON.stringify(messages(diagnostics))}`,
    );
  });

  check("node host: the legal neighbour on disk is silent", () => {
    write("src/entry-ok.ts", 'import { score } from "./score";\nexport const label: number = score;');
    const service = createLanguageService(
      createNodeHost([join(root, "src/entry-ok.ts")]),
    );
    assertEqual(
      messages(service.getProgramDiagnostics()),
      [],
      "a correct program read from disk should be silent",
    );
  });

  check("node host: a root that does not exist is reported", () => {
    // Otherwise a typo'd entry point checks nothing and looks clean,
    // which is the failure this assertion exists for.
    const service = createLanguageService(
      createNodeHost([join(root, "src/absent.ts")]),
    );
    assert(
      hasMessage(service.getProgramDiagnostics(), "cannot read file"),
      "a missing root should be reported",
    );
  });

  check("node host: a directory handed in as a root does not crash", () => {
    const service = createLanguageService(createNodeHost([join(root, "src")]));
    assert(
      hasMessage(service.getProgramDiagnostics(), "cannot read file"),
      "a directory is not a source file",
    );
  });

  // -------------------------------------------------------------------------
  // A `ts.LanguageServiceHost`-shaped host
  // -------------------------------------------------------------------------

  check("a host with getScriptSnapshot and no readFile works", () => {
    // This is the compatibility claim: a real `ts.LanguageServiceHost` is
    // required to have `getScriptSnapshot` and only optionally has
    // `readFile`, so the snapshot path has to work on its own.
    const sources = {
      "/p/entry.ts": 'import { score } from "./score";\nexport const label: string = score;',
      "/p/score.ts": "export const score: number = 1;",
    };
    const host = {
      getScriptFileNames: () => ["/p/entry.ts"],
      getCurrentDirectory: () => "/p",
      getCompilationSettings: () => ({}),
      getScriptSnapshot: (fileName) => {
        const text = sources[fileName];
        if (text === undefined) return undefined;
        return {
          getText: (start, end) => text.slice(start, end),
          getLength: () => text.length,
        };
      },
    };
    const service = createLanguageService(host);
    assertEqual(service.getProgramFileNames().length, 2, "snapshot host program");
    assert(
      hasMessage(service.getProgramDiagnostics(), "expected `string` but got `number`"),
      "snapshot host should reach the checker",
    );
  });

  check("a host whose readFile throws is treated as absent, not fatal", () => {
    // Resolution probes paths that do not exist, and a host wired to
    // `readFileSync` throws ENOENT for each. If that propagated, every
    // extensionless import would crash the service.
    const host = {
      getScriptFileNames: () => ["/p/entry.ts"],
      getCurrentDirectory: () => "/p",
      readFile: (fileName) => {
        if (fileName === "/p/entry.ts") return "export const label: string = 1;";
        throw new Error(`ENOENT: ${fileName}`);
      },
    };
    const service = createLanguageService(host);
    assert(
      hasMessage(service.getProgramDiagnostics(), "expected `string` but got `number`"),
      "a throwing readFile should not stop the check",
    );
  });

  // -------------------------------------------------------------------------
  // JSX
  // -------------------------------------------------------------------------

  check("a .tsx file parses as JSX without the option", () => {
    const service = createLanguageService(
      createMemoryHost({ "/p/view.tsx": "export const view = <div>hi</div>;" }),
    );
    assertEqual(messages(service.getProgramDiagnostics()), [], "tsx should parse");
  });

  check("the jsx option covers a .ts file, and its absence does not", () => {
    const files = { "/p/view.ts": "export const view = <div>hi</div>;" };
    const off = createLanguageService(createMemoryHost(files));
    const on = createLanguageService(
      createMemoryHost(files, { compilerOptions: { jsx: true } }),
    );
    // Both directions, so this measures the option and not the parser.
    assert(off.getProgramDiagnostics().length > 0, "jsx off should fail to parse");
    assertEqual(messages(on.getProgramDiagnostics()), [], "jsx on should parse");
  });

  // -------------------------------------------------------------------------
  // Facade contract
  // -------------------------------------------------------------------------

  check("a host that cannot name roots is rejected loudly", () => {
    // An empty program answers every query with nothing, which reads as
    // a clean program. Failing here is the only way a caller finds out.
    let threw = false;
    try {
      createLanguageService({ readFile: () => undefined });
    } catch {
      threw = true;
    }
    assert(threw, "expected a TypeError for a host with no getScriptFileNames");
  });

  check("a host that cannot read files is rejected loudly", () => {
    let threw = false;
    try {
      createLanguageService({ getScriptFileNames: () => [] });
    } catch {
      threw = true;
    }
    assert(threw, "expected a TypeError for a host with no reader");
  });

  check("formatDiagnostics renders file, message and breadcrumb", () => {
    const service = createLanguageService(createMemoryHost(BROKEN_PROGRAM));
    const text = formatDiagnostics(service.getProgramDiagnostics());
    assert(text.includes("/p/entry.ts"), `no file in ${text}`);
    assert(text.includes("expected `string` but got `number`"), `no message in ${text}`);
    assert(text.includes("("), `no breadcrumb in ${text}`);
  });

  // -------------------------------------------------------------------------
  // The original ABI must not have moved
  // -------------------------------------------------------------------------

  check("checkModuleGraph still answers as it did", () => {
    // It has consumers outside this repo, and it now shares
    // `collect_parsed_graph_issues` with the host path — so this is the
    // regression check on that extraction.
    const text = checkModuleGraph({
      modules: [
        {
          path: "/src/entry.ts",
          source: 'import { score } from "./score";\nexport const label: string = score;',
          allowJsx: false,
        },
        {
          path: "/src/score.ts",
          source: "export const score: number = 1;",
          allowJsx: false,
        },
      ],
      edges: [
        {
          importerPath: "/src/entry.ts",
          moduleSpecifier: "./score",
          targetPath: "/src/score.ts",
        },
      ],
    });
    assert(text.includes("/src/entry.ts:"), `expected the path prefix in: ${text}`);
    assert(
      text.includes("expected `string` but got `number`"),
      `expected the message in: ${text}`,
    );
  });

  check("checkModuleGraph returns an empty string for a clean graph", () => {
    const text = checkModuleGraph({
      modules: [
        { path: "/src/ok.ts", source: "export const ok: number = 1;", allowJsx: false },
      ],
      edges: [],
    });
    assertEqual(text, "", "a clean graph should be the empty string");
  });
} finally {
  rmSync(root, { recursive: true, force: true });
}

console.log(
  `\nlanguage service: ${passed} passed, ${failures.length} failed`,
);
if (failures.length > 0) {
  process.exit(1);
}
