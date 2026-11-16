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

import {
  mkdtempSync,
  mkdirSync,
  readFileSync,
  realpathSync,
  rmSync,
  symlinkSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join, dirname } from "node:path";

import { createMemoryHost, formatDiagnostics } from "../js/hosts.mjs";
import { createNodeHost } from "../js/node-host.mjs";

const VERBOSE = process.argv.includes("--verbose");

// `--wasm` runs every case against the wasm-gc build through
// `js/language-service-wasm.mjs` instead of the JS build: the same host
// contract, a different backend and a different boundary. The string ABI
// (`checkModuleGraph`) is JS-build only, so those cases are skipped there.
const WASM = process.argv.includes("--wasm");
const WASM_PATH = new URL("../_build/wasm-gc/release/build/mtsc/mtsc.wasm", import.meta.url);

const { createLanguageService, checkModuleGraph } = WASM
  ? {
      createLanguageService: (
        await (await import("../js/language-service-wasm.mjs")).loadLanguageService(
          readFileSync(WASM_PATH),
        )
      ).createLanguageService,
      checkModuleGraph: null,
    }
  : await import("../js/language-service.mjs");

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

check("a bare specifier nothing resolves is left alone rather than reported", () => {
  // There is no `node_modules` here, so nothing resolves `react`, and
  // calling that a failure would send a caller looking for a file that
  // was never meant to exist — the CLI's rule as well.
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
// Package resolution, through the host
// ---------------------------------------------------------------------------

// A package whose `exports` names its declarations under the `types`
// condition and its code under `default`: the check must read the
// declarations, and every byte of it arrives through `readFile`.
const PACKAGE_FILES = {
  "/p/node_modules/lib/package.json":
    '{"name":"lib","exports":{".":{"types":"./dist/i.d.ts","default":"./dist/i.js"}}}',
  "/p/node_modules/lib/dist/i.d.ts": "export declare function score(): number;",
  "/p/node_modules/lib/dist/i.js": "export function score() { return 1 }",
};

check("memory host: a package import is checked against its declarations", () => {
  const service = createLanguageService(
    createMemoryHost(
      {
        ...PACKAGE_FILES,
        "/p/entry.ts": 'import { score } from "lib";\nexport const s: string = score();',
      },
      { rootNames: ["/p/entry.ts"] },
    ),
  );
  assert(
    hasMessage(service.getProgramDiagnostics(), "expected `string` but got `number`"),
    `no package diagnostic: ${JSON.stringify(messages(service.getProgramDiagnostics()))}`,
  );
  assertEqual(
    service.resolveModuleName("/p/entry.ts", "lib"),
    { resolvedFileName: "/p/node_modules/lib/dist/i.d.ts", isExternal: false },
    "the types condition, not the code",
  );
});

check("memory host: the legal use of the package is silent", () => {
  const service = createLanguageService(
    createMemoryHost(
      {
        ...PACKAGE_FILES,
        "/p/entry.ts": 'import { score } from "lib";\nexport const n: number = score();',
      },
      { rootNames: ["/p/entry.ts"] },
    ),
  );
  assertEqual(messages(service.getProgramDiagnostics()), [], "expected silence");
});

check("a dependency's declarations are read but not reported on", () => {
  // `lib` has a broken declaration of its own. Reporting it would be the
  // checker's gap far more often than the package's error, which is the
  // CLI's rule; naming it as a root, or not, is what decides.
  const files = {
    "/p/node_modules/lib/package.json": '{"name":"lib","types":"i.d.ts"}',
    // TS2717: two declarations of one interface property with different
    // types, which tsc reports in a declaration file too.
    "/p/node_modules/lib/i.d.ts":
      "export declare const n: number;\n" +
      "export interface I { a: number }\nexport interface I { a: string }",
    "/p/entry.ts": 'import { n } from "lib";\nexport const m: number = n;',
  };
  const quiet = createLanguageService(createMemoryHost(files, { rootNames: ["/p/entry.ts"] }));
  assertEqual(messages(quiet.getProgramDiagnostics()), [], "a dependency is context only");
  const named = createLanguageService(
    createMemoryHost(files, { rootNames: ["/p/entry.ts", "/p/node_modules/lib/i.d.ts"] }),
  );
  assert(
    named.getProgramDiagnostics().some((d) => d.file === "/p/node_modules/lib/i.d.ts"),
    "a declaration file named as a root is checked",
  );
  const skipped = createLanguageService(
    createMemoryHost(files, {
      rootNames: ["/p/entry.ts", "/p/node_modules/lib/i.d.ts"],
      compilerOptions: { skipLibCheck: true },
    }),
  );
  assertEqual(messages(skipped.getProgramDiagnostics()), [], "skipLibCheck exempts it");
});

check("resolveModuleNames answers first; undefined defers, null skips", () => {
  const files = {
    "/v/cfg.d.ts": "export declare const port: number;",
    "/p/entry.ts":
      'import { port } from "virtual:cfg";\n' +
      'import { x } from "cdn:thing";\n' +
      'import { score } from "./score";\n' +
      "export const p: string = port;",
    "/p/score.ts": "export const score: number = 1;",
  };
  const calls = [];
  const host = {
    ...createMemoryHost(files, { rootNames: ["/p/entry.ts"] }),
    resolveModuleNames(names, containingFile) {
      calls.push(`${containingFile}:${names.join(",")}`);
      return names.map((name) =>
        name === "virtual:cfg"
          ? { resolvedFileName: "/v/cfg.d.ts" }
          : name === "cdn:thing"
            ? null
            : undefined,
      );
    },
  };
  const service = createLanguageService(host);
  const diagnostics = service.getProgramDiagnostics();
  assert(
    hasMessage(diagnostics, "expected `string` but got `number`"),
    `the mapped module was not checked: ${JSON.stringify(messages(diagnostics))}`,
  );
  assertEqual(
    diagnostics.filter((d) => d.source === "import").map((d) => d.messageText),
    [],
    "a skipped import is not a diagnostic",
  );
  assertEqual(
    service.getProgramFileNames().sort(),
    ["/p/entry.ts", "/p/score.ts", "/v/cfg.d.ts"],
    "the mapped file is in the program, the skipped one is not, `./score` defaulted",
  );
  assertEqual(
    service.resolveModuleName("/p/entry.ts", "cdn:thing"),
    { resolvedFileName: "", isExternal: true },
    "null is external",
  );
  assert(calls.length > 0, "the hook was never called");
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

  check("node host: a pnpm-linked package resolves through node_modules, once", () => {
    // Two importers reach one package through two symlinks, the layout
    // pnpm writes. With `realpath` on the host the package's declaration
    // enters the program once, under its real path.
    write(
      "pkg/.store/lib@1/node_modules/lib/package.json",
      '{"name":"lib","types":"index.d.ts"}',
    );
    write(
      "pkg/.store/lib@1/node_modules/lib/index.d.ts",
      "export declare const n: number;",
    );
    mkdirSync(join(root, "pkg/a/node_modules"), { recursive: true });
    mkdirSync(join(root, "pkg/b/node_modules"), { recursive: true });
    symlinkSync("../../.store/lib@1/node_modules/lib", join(root, "pkg/a/node_modules/lib"));
    symlinkSync("../../.store/lib@1/node_modules/lib", join(root, "pkg/b/node_modules/lib"));
    const a = write("pkg/a/main.ts", 'import { n } from "lib";\nexport const s: string = n;');
    const b = write("pkg/b/main.ts", 'import { n } from "lib";\nexport const m: number = n;');
    const service = createLanguageService(createNodeHost([a, b], { currentDirectory: root }));
    const diagnostics = service.getProgramDiagnostics();
    assertEqual(
      messages(diagnostics).filter((m) => m.includes("expected")).length,
      1,
      `expected exactly the one type error: ${JSON.stringify(messages(diagnostics))}`,
    );
    const real = realpathSync(join(root, "pkg/.store/lib@1/node_modules/lib/index.d.ts"));
    const files = service.getProgramFileNames();
    assertEqual(
      files.filter((f) => f.endsWith("/lib/index.d.ts")),
      [real],
      "the package loads once, under its real path",
    );
  });

  (WASM ? () => {} : check)("checkModuleGraph still answers as it did", () => {
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

  (WASM ? () => {} : check)("checkModuleGraph returns an empty string for a clean graph", () => {
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
  `\nlanguage service (${WASM ? "wasm-gc" : "js"}): ${passed} passed, ${failures.length} failed`,
);
if (failures.length > 0) {
  process.exit(1);
}
