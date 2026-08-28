// Differential validation for `mtsc --mangle-properties`.
//
// The property mangler is only useful if it is *provably* safe: a
// renamed property must never be observable from outside the bundle.
// "Outside" has two doors:
//
//   1. The entry module's export surface — anything reachable from an
//      exported value is part of the package ABI.
//   2. Side-effect sinks — `fetch`, `console.*`, `JSON.stringify`,
//      external module calls. A property that reaches one of those
//      leaves the bundle by value, so its *name* leaks too.
//
// For every case in `fixtures/mangle-safety/` this harness observes the
// same public API three times and compares:
//
//   reference  the case's ORIGINAL TypeScript, executed through Node's
//              type stripping — no compiler of ours involved
//   baseline   `mtsc --bundle`
//   mangled    `mtsc --bundle --mangle-properties --reserve-entry-exports`
//
// baseline vs mangled catches an unsafe rename. reference vs baseline
// catches the other half: a bug present in *both* our outputs.
// Class-method DCE deleting a public method was exactly that — the two
// mtsc variants agreed with each other and were both wrong.
//
// Then a mutation self-check runs: one name the analysis said it had to
// keep is deliberately renamed in the mangled bundle, and the run must
// notice. A case whose driver never observes its own `expectKeep` names
// offers a hollow guarantee, and this is what stops the corpus from
// going green on nothing.
//
// Each case records its expected outcome in `case.json`, so known gaps
// stay visible without failing CI, and a regression on a case that used
// to pass does fail.
//
// Usage:
//   node scripts/verify_mangle_safety.mjs [--case <name>] [--json <file>]
//                                         [--update] [--no-reference]
//                                         [--no-mutate]

import { spawnSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const CORPUS = path.join(ROOT, "fixtures", "mangle-safety");
const OUT_ROOT = path.join(ROOT, "_build", "mangle-safety");
const RUNNER = path.join(ROOT, "scripts", "lib", "observe-runner.mjs");
const HOOKS = path.join(ROOT, "scripts", "lib", "ts-reference-hooks.mjs");

const MTSC_CANDIDATES = [
  path.join(ROOT, "_build", "native", "release", "build", "cmd", "mtsc", "mtsc.exe"),
  path.join(ROOT, "_build", "native", "debug", "build", "cmd", "mtsc", "mtsc.exe"),
];

function findMtsc() {
  for (const candidate of MTSC_CANDIDATES) {
    if (fs.existsSync(candidate)) return candidate;
  }
  console.error(
    "verify_mangle_safety: mtsc binary not found. Run `moon build --target native` first.",
  );
  process.exit(2);
}

const args = process.argv.slice(2);
let onlyCase = null;
let jsonOut = null;
let update = false;
let useReference = true;
let useMutation = true;
for (let i = 0; i < args.length; i++) {
  if (args[i] === "--case") onlyCase = args[++i];
  else if (args[i] === "--json") jsonOut = args[++i];
  else if (args[i] === "--update") update = true;
  else if (args[i] === "--no-reference") useReference = false;
  else if (args[i] === "--no-mutate") useMutation = false;
  else {
    console.error(`verify_mangle_safety: unknown argument ${args[i]}`);
    process.exit(2);
  }
}

const MTSC = findMtsc();

// ---------------------------------------------------------------
// Compiling
// ---------------------------------------------------------------

function runMtsc(entry, outFile, extraArgs, externals) {
  const argv = [entry, "--bundle", "--out", outFile, ...extraArgs];
  for (const ext of externals) argv.push("--external", ext);
  const res = spawnSync(MTSC, argv, { encoding: "utf8", cwd: ROOT });
  return {
    ok: res.status === 0,
    stdout: res.stdout ?? "",
    stderr: res.stderr ?? "",
  };
}

// Export names an ESM bundle actually exposes, taken from the emitted
// `export { … }` clause plus `export default`.
function emittedExports(code) {
  const names = new Set();
  const clause = /export\s*\{([^}]*)\}/g;
  let m;
  while ((m = clause.exec(code)) !== null) {
    for (const part of m[1].split(",")) {
      const spec = part.trim();
      if (!spec) continue;
      const as = spec.split(/\s+as\s+/);
      names.add((as.length > 1 ? as[1] : as[0]).trim());
    }
  }
  if (/export\s+default\s/.test(code)) names.add("default");
  for (const decl of code.matchAll(
    /export\s+(?:async\s+)?(?:function\*?|class|const|let|var)\s+([A-Za-z_$][\w$]*)/g,
  )) {
    names.add(decl[1]);
  }
  return names;
}

// ---------------------------------------------------------------
// Observing
// ---------------------------------------------------------------

function writeStubs(caseDir, outDir, stubs) {
  const root = path.join(outDir, "node_modules");
  for (const [name, spec] of Object.entries(stubs ?? {})) {
    const pkgDir = path.join(root, ...name.split("/"));
    fs.mkdirSync(pkgDir, { recursive: true });
    const source =
      typeof spec === "string" && spec.startsWith("./")
        ? fs.readFileSync(path.join(caseDir, spec), "utf8")
        : spec;
    fs.writeFileSync(path.join(pkgDir, "index.mjs"), source);
    fs.writeFileSync(
      path.join(pkgDir, "package.json"),
      JSON.stringify({ name, type: "module", main: "index.mjs" }, null, 2),
    );
  }
  return root;
}

// Observe one module in a child process. All three variants go through
// the same runner, so a difference between them is a difference in the
// module and never in how it was watched.
//
// `stripTypes` runs the module as TypeScript through Node's own
// TypeScript support and installs the resolution hooks the original
// sources need (extensionless relative specifiers, stubbed bare
// specifiers).
//
// `--experimental-transform-types`, not `--experimental-strip-types`.
// Strip-only mode refuses every construct that is not pure annotation —
// `enum`, `namespace`, parameter properties — and refusing is not
// neutral here: the reference leg became UNAVAILABLE for those cases and
// the harness fell back to comparing our own two outputs against each
// other, which is the leg agreement this whole file exists to distrust.
// `case43-table-shadowing` is the case that showed it: its `const enum`
// group is a pass that is wrong under plain `--bundle`, and the note
// said "reference run unavailable" while the case reported pass.
//
// Transform mode is still Node's implementation, not ours, so the leg
// stays independent — it just does more than erase.
function observe(modulePath, options, { stripTypes = false, stubRoot = "" } = {}) {
  const argv = [];
  if (stripTypes) {
    argv.push("--experimental-transform-types", "--no-warnings");
    argv.push("--experimental-loader", pathToFileURL(HOOKS).href);
  }
  argv.push(RUNNER, modulePath, JSON.stringify(options));
  const res = spawnSync(process.execPath, argv, {
    encoding: "utf8",
    env: { ...process.env, MANGLE_SAFETY_STUB_ROOT: stubRoot },
    cwd: path.dirname(modulePath),
    maxBuffer: 32 * 1024 * 1024,
  });
  const stdout = (res.stdout ?? "").trim();
  if (!stdout) {
    return {
      ok: false,
      unavailable: true,
      error: firstLine(res.stderr ?? "") || `runner exited with ${res.status}`,
    };
  }
  try {
    return JSON.parse(stdout);
  } catch {
    return {
      ok: false,
      unavailable: true,
      error: `unparseable runner output: ${truncate(stdout, 200)}`,
    };
  }
}

function firstLine(text) {
  return (
    text
      .split("\n")
      .map((l) => l.trim())
      .find((l) => l.length > 0) ?? ""
  );
}

// ---------------------------------------------------------------
// Mutation self-check
// ---------------------------------------------------------------

// Rename one reserved property in the emitted bundle, the way an unsafe
// mangler would. Only member-access, object-key, and class-field
// positions are rewritten, so the result stays syntactically valid.
function mutateProperty(code, name) {
  const id = name.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const renamed = `${name}$mutated`;
  // Member access: `x.name`.
  let out = code.replace(new RegExp(`\\.(\\s*)${id}\\b`, "g"), `.$1${renamed}`);
  // Object-literal key: `name: value`.
  out = out.replace(new RegExp(`(^|[\\s{,(\\[])${id}(\\s*:)`, "gm"), `$1${renamed}$2`);
  // Class field: `static name = …` / `name = …`.
  out = out.replace(
    new RegExp(`(^|[\\s{;])(static\\s+)?${id}(\\s*=[^=])`, "gm"),
    (_match, p1, p2, p3) => `${p1}${p2 ?? ""}${renamed}${p3}`,
  );
  // Method / accessor declaration: `name() {`, `get name() {`,
  // `*name() {`, `async name() {`. Without this, mutating a method that
  // nothing inside the bundle calls rewrote no occurrence at all and the
  // self-check could not tell a hollow case from a safe one.
  out = out.replace(
    new RegExp(
      `(^|[\\s{;])((?:static\\s+)?(?:async\\s+)?(?:get\\s+|set\\s+)?\\*?\\s*)${id}(\\s*\\()`,
      "gm",
    ),
    (_match, p1, p2, p3) => `${p1}${p2}${renamed}${p3}`,
  );
  return out === code ? null : out;
}

// ---------------------------------------------------------------
// One case
// ---------------------------------------------------------------

function propertyAppears(code, name) {
  const id = name.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const patterns = [
    new RegExp(`\\.\\s*${id}\\b`),
    new RegExp(`(^|[\\s{,(\\[])${id}\\s*:`, "m"),
    new RegExp(`(^|[\\s{;])${id}\\s*\\(`, "m"),
    new RegExp(`["'\`]${id}["'\`]`),
    new RegExp(`\\[\\s*["']${id}["']\\s*\\]`),
    // Class field declaration: `static sv = 1` / `count = 0`.
    new RegExp(`(^|[\\s{;])(static\\s+)?${id}\\s*=[^=]`, "m"),
  ];
  return patterns.some((p) => p.test(code));
}

function truncate(s, n = 400) {
  return s.length > n ? `${s.slice(0, n)}…` : s;
}

function runCase(name) {
  const caseDir = path.join(CORPUS, name);
  const meta = JSON.parse(fs.readFileSync(path.join(caseDir, "case.json"), "utf8"));
  const entry = path.join(caseDir, meta.entry ?? "index.ts");
  const outDir = path.join(OUT_ROOT, name);
  fs.rmSync(outDir, { recursive: true, force: true });
  fs.mkdirSync(outDir, { recursive: true });
  const stubRoot = writeStubs(caseDir, outDir, meta.stubs);
  fs.writeFileSync(path.join(outDir, "package.json"), JSON.stringify({ type: "module" }));

  const externals = meta.externals ?? [];
  const failures = [];
  const notes = [];

  const baselineFile = path.join(outDir, "baseline.mjs");
  const mangledFile = path.join(outDir, "mangled.mjs");
  const baseline = runMtsc(entry, baselineFile, [], externals);
  if (!baseline.ok) {
    return {
      name,
      status: "blocked-compile",
      detail: firstDiagnostic(baseline),
      failures,
      notes,
    };
  }
  const mangleArgs = ["--mangle-properties", "--reserve-entry-exports", ...(meta.mtscArgs ?? [])];
  const mangled = runMtsc(entry, mangledFile, mangleArgs, externals);
  if (!mangled.ok) {
    return { name, status: "blocked-mangle", detail: firstDiagnostic(mangled), failures, notes };
  }

  const baselineCode = fs.readFileSync(baselineFile, "utf8");
  const mangledCode = fs.readFileSync(mangledFile, "utf8");

  // --- Door 1: the export surface itself.
  const declared = new Set(meta.exports ?? []);
  const baseExports = emittedExports(baselineCode);
  const mangExports = emittedExports(mangledCode);
  for (const want of declared) {
    if (!baseExports.has(want)) failures.push(`export \`${want}\` missing from --bundle output`);
    else if (!mangExports.has(want)) failures.push(`export \`${want}\` missing from mangled output`);
  }
  for (const got of mangExports) {
    if (declared.size > 0 && !declared.has(got)) {
      failures.push(`mangled output exports \`${got}\`, which the entry does not export`);
    }
  }

  // --- Property-name expectations.
  for (const keep of meta.expectKeep ?? []) {
    if (!propertyAppears(mangledCode, keep)) {
      failures.push(`property \`${keep}\` is externally visible but was renamed or dropped`);
    }
  }
  for (const gone of meta.expectMangle ?? []) {
    if (propertyAppears(mangledCode, gone)) {
      notes.push(`missed opportunity: \`${gone}\` is internal-only but was kept`);
    }
  }

  // --- Door 2: observable behaviour.
  if (meta.run !== false) {
    const driverPath = path.join(caseDir, "driver.mjs");
    const options = {
      driver: fs.existsSync(driverPath) ? driverPath : null,
      globals: meta.globals ?? [],
      globalStubs: meta.globalStubs ?? {},
      fakeTimers: meta.fakeTimers === true,
    };
    const before = observe(baselineFile, options, { stubRoot });
    const after = observe(mangledFile, options, { stubRoot });
    if (before.unavailable) notes.push(`baseline runner failed: ${before.error}`);
    else if (!before.ok) notes.push(`baseline bundle threw: ${before.error}`);
    const a = JSON.stringify(before.observed);
    const b = JSON.stringify(after.observed);
    if (a !== b) {
      failures.push(
        `observable behaviour changed\n      baseline: ${truncate(a)}\n      mangled:  ${truncate(b)}`,
      );
    }

    // --- Reference: the original TypeScript, no compiler of ours.
    if (useReference && meta.reference !== false) {
      const ref = observe(entry, options, { stripTypes: true, stubRoot });
      // Node's type stripping only handles erasable syntax, and it links
      // the original sources as ESM. A parameter property, the `module`
      // keyword, or a type imported in value form all fail before the
      // module runs, as a SyntaxError — that is the reference leg being
      // unavailable, not a disagreement. Our own bundles are valid JS by
      // construction, so this never masks a real difference.
      const refUnavailable =
        ref.unavailable || (ref.observed?.error ?? "").startsWith("SyntaxError:");
      if (refUnavailable) {
        notes.push(
          `reference run unavailable: ${truncate(ref.error ?? ref.observed?.error ?? "", 160)}`,
        );
      } else {
        const r = JSON.stringify(ref.observed);
        if (r !== a) {
          failures.push(
            `compiled output disagrees with the original TypeScript\n      reference: ${truncate(r)}\n      baseline:  ${truncate(a)}`,
          );
        }
      }
    }

    // --- Mutation self-check: prove this case can detect a break.
    if (useMutation && failures.length === 0) {
      const target = (meta.expectKeep ?? []).find((n) => mutateProperty(mangledCode, n) !== null);
      if (target) {
        const mutantFile = path.join(outDir, "mutant.mjs");
        fs.writeFileSync(mutantFile, mutateProperty(mangledCode, target));
        const mutated = observe(mutantFile, options, { stubRoot });
        if (JSON.stringify(mutated.observed) === b) {
          failures.push(
            `mutation self-check: renaming \`${target}\` changed nothing observable, so this case cannot detect an unsafe rename of it`,
          );
        }
      } else if ((meta.expectKeep ?? []).length > 0) {
        notes.push("mutation self-check skipped: no expectKeep name is rewritable in the output");
      }
    }
  }

  const status = failures.length > 0 ? "fail" : "pass";
  return { name, status, failures, notes };
}

function firstDiagnostic(res) {
  const text = `${res.stderr}${res.stdout}`.trim();
  return text.split("\n").find((l) => l.trim().length > 0) ?? "(no diagnostic)";
}

// ---------------------------------------------------------------
// Driver
// ---------------------------------------------------------------

// Cases live either directly under the corpus root (the hand-written
// ones) or one level down, so the machine-generated matrix can sit in
// its own directory without drowning the listing. A case is any
// directory holding a `case.json`; names keep their relative path, so
// `--case generated/literal-console-log` addresses one of them.
function collectCases(dir, prefix = "") {
  const out = [];
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    if (!entry.isDirectory()) continue;
    const rel = prefix ? `${prefix}/${entry.name}` : entry.name;
    if (fs.existsSync(path.join(dir, entry.name, "case.json"))) out.push(rel);
    else if (prefix === "") out.push(...collectCases(path.join(dir, entry.name), rel));
  }
  return out;
}

const caseNames = collectCases(CORPUS)
  .sort()
  .filter((n) => onlyCase === null || n === onlyCase);

if (caseNames.length === 0) {
  console.error(`verify_mangle_safety: no cases matched${onlyCase ? ` \`${onlyCase}\`` : ""}`);
  process.exit(2);
}

const results = caseNames.map(runCase);

let regressions = 0;
let fixed = 0;
console.log("mangle-safety validation\n");
for (const res of results) {
  const meta = JSON.parse(fs.readFileSync(path.join(CORPUS, res.name, "case.json"), "utf8"));
  const expected = meta.expectStatus ?? "pass";
  const mark = res.status === expected ? "ok  " : res.status === "pass" ? "FIXD" : "REGR";
  if (mark === "REGR") regressions++;
  if (mark === "FIXD") fixed++;
  console.log(
    `  [${mark}] ${res.name.padEnd(38)} ${res.status}${res.status === expected ? "" : ` (expected ${expected})`}`,
  );
  if (res.detail) console.log(`         ${res.detail}`);
  for (const f of res.failures) console.log(`         ✗ ${f}`);
  for (const n of res.notes) console.log(`         · ${n}`);
  if (update) {
    meta.expectStatus = res.status;
    fs.writeFileSync(path.join(CORPUS, res.name, "case.json"), `${JSON.stringify(meta, null, 2)}\n`);
  }
}

const counts = results.reduce((acc, r) => {
  acc[r.status] = (acc[r.status] ?? 0) + 1;
  return acc;
}, {});
console.log(
  `\n  ${results.length} cases: ${Object.entries(counts)
    .map(([k, v]) => `${v} ${k}`)
    .join(", ")}`,
);
if (fixed > 0) {
  console.log(`  ${fixed} case(s) now pass but are still recorded as gaps — rerun with --update.`);
}
if (regressions > 0) {
  console.log(`  ${regressions} regression(s).`);
}

if (jsonOut) {
  fs.writeFileSync(jsonOut, `${JSON.stringify(results, null, 2)}\n`);
}

process.exit(regressions > 0 ? 1 : 0);
