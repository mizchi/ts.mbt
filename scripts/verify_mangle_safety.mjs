// Differential validation for `mtsc --mangle-properties`.
//
// The property mangler is only useful if it is *provably* safe: a
// renamed property must never be observable from outside the
// bundle. "Outside" has two doors:
//
//   1. The entry module's export surface — anything reachable from
//      an exported value's type is part of the package ABI.
//   2. Side-effect sinks — `fetch`, `console.*`, `JSON.stringify`,
//      external module calls. A property that reaches one of those
//      leaves the bundle by value, so its *name* leaks too.
//
// This harness checks both doors empirically. For every case in
// `fixtures/mangle-safety/` it:
//
//   - compiles the entry twice (plain `--bundle`, and again with
//     `--mangle-properties --reserve-entry-exports`),
//   - compares the emitted export surface against the entry's
//     declared exports (a dropped `export … from` is a bug even
//     when both variants drop it),
//   - runs both bundles under Node with `fetch` / `console.*`
//     recorded, driving the public API through the case's
//     `driver.mjs`, and diffs the observed behaviour.
//
// A behavioural difference between the two bundles is a mangler
// safety violation: the rename changed something an outside
// observer can see.
//
// Each case declares its expected outcome in `case.json`, so known
// gaps stay visible without failing CI, and a regression on a case
// that used to pass does fail.
//
// Usage:
//   node scripts/verify_mangle_safety.mjs [--case <name>] [--json <file>] [--update]

import { spawnSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const CORPUS = path.join(ROOT, "fixtures", "mangle-safety");
const OUT_ROOT = path.join(ROOT, "_build", "mangle-safety");

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
for (let i = 0; i < args.length; i++) {
  if (args[i] === "--case") onlyCase = args[++i];
  else if (args[i] === "--json") jsonOut = args[++i];
  else if (args[i] === "--update") update = true;
  else {
    console.error(`verify_mangle_safety: unknown argument ${args[i]}`);
    process.exit(2);
  }
}

const MTSC = findMtsc();

// ---------------------------------------------------------------
// Serialization: stable, total, and cycle-safe. Used to compare
// what the two bundles actually produced.
// ---------------------------------------------------------------

// Own enumerable members a function/class carries (statics, and the
// prototype's methods) — renaming one of those IS observable.
function functionMembers(fn) {
  const out = new Set();
  for (const key of Object.getOwnPropertyNames(fn)) {
    if (key !== "length" && key !== "name" && key !== "prototype") out.add(key);
  }
  const proto = fn.prototype;
  if (proto) {
    for (const key of Object.getOwnPropertyNames(proto)) {
      if (key !== "constructor") out.add(key);
    }
  }
  return [...out].sort();
}

function serialize(value, seen = new Set()) {
  if (value === undefined) return { $: "undefined" };
  if (value === null) return null;
  const t = typeof value;
  if (t === "number" || t === "string" || t === "boolean") return value;
  if (t === "bigint") return { $: "bigint", v: value.toString() };
  if (t === "symbol") return { $: "symbol", v: String(value) };
  // Deliberately NOT recording `value.name`: renaming a local binding
  // changes `Function.name`, and no minifier preserves it. What matters
  // is the export name (checked separately) and the members.
  if (t === "function") return { $: "function", members: functionMembers(value) };
  if (seen.has(value)) return { $: "cycle" };
  seen.add(value);
  try {
    if (Array.isArray(value)) return value.map((v) => serialize(v, seen));
    if (value instanceof Map) {
      return { $: "Map", v: [...value].map(([k, v]) => [serialize(k, seen), serialize(v, seen)]) };
    }
    if (value instanceof Set) return { $: "Set", v: [...value].map((v) => serialize(v, seen)) };
    if (value instanceof Error) return { $: "Error", message: value.message };
    if (value instanceof Date) return { $: "Date", v: value.toISOString() };
    // Plain-ish object: sort keys so property *order* changes (which
    // the mangler may legitimately introduce) don't read as a diff,
    // while property *names* still do.
    const out = {};
    for (const key of Object.keys(value).sort()) out[key] = serialize(value[key], seen);
    const proto = Object.getPrototypeOf(value);
    if (proto && proto !== Object.prototype) {
      // Class instances: also record the own+prototype method names,
      // since renaming a public method is exactly the failure mode
      // we're hunting.
      const members = new Set();
      let p = proto;
      while (p && p !== Object.prototype) {
        for (const key of Object.getOwnPropertyNames(p)) {
          if (key !== "constructor") members.add(key);
        }
        p = Object.getPrototypeOf(p);
      }
      out.$members = [...members].sort();
    }
    return out;
  } finally {
    seen.delete(value);
  }
}

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

// Export names an ESM bundle actually exposes, taken from the
// emitted `export { … }` clause plus `export default`.
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
// Running
// ---------------------------------------------------------------

function writeStubs(caseDir, outDir, stubs) {
  for (const [name, spec] of Object.entries(stubs ?? {})) {
    const pkgDir = path.join(outDir, "node_modules", ...name.split("/"));
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
}

async function runBundle(bundleFile, driverFile, options) {
  const sinks = [];
  const saved = {
    fetch: globalThis.fetch,
    log: console.log,
    warn: console.warn,
    error: console.error,
    info: console.info,
    setTimeout: globalThis.setTimeout,
  };
  globalThis.fetch = async (input, init) => {
    sinks.push({
      sink: "fetch",
      url: typeof input === "string" ? input : serialize(input),
      init: serialize(init),
    });
    return {
      ok: true,
      status: 200,
      text: async () => "stub-response",
      json: async () => ({}),
    };
  };
  for (const level of ["log", "warn", "error", "info"]) {
    console[level] = (...callArgs) => {
      sinks.push({ sink: `console.${level}`, args: callArgs.map((a) => serialize(a)) });
    };
  }
  if (options.fakeTimers) {
    globalThis.setTimeout = (fn, _ms, ...rest) => {
      // Run on the microtask queue instead of the real clock so a
      // case that sleeps stays testable.
      Promise.resolve().then(() => fn(...rest));
      return 0;
    };
  }
  // Host globals the case expects to exist (`window`, …). Node has
  // no DOM, so a case that augments one needs a stand-in.
  const definedGlobals = [];
  for (const name of options.globals ?? []) {
    if (!(name in globalThis)) {
      globalThis[name] = {};
      definedGlobals.push(name);
    }
  }
  try {
    const mod = await import(pathToFileURL(bundleFile).href);
    let result = null;
    if (driverFile) {
      const driver = await import(pathToFileURL(driverFile).href);
      result = await driver.default(mod);
    } else {
      result = Object.fromEntries(
        Object.keys(mod)
          .sort()
          .map((k) => [k, mod[k]]),
      );
    }
    // Let any floating promise the module kicked off settle, so a
    // sink reached asynchronously still lands in the recording.
    for (let i = 0; i < 8; i++) await new Promise((r) => setImmediate(r));
    return { ok: true, observed: { result: serialize(result), sinks } };
  } catch (err) {
    const error = `${err?.name ?? "Error"}: ${err?.message ?? String(err)}`;
    return { ok: false, error, observed: { error, sinks } };
  } finally {
    globalThis.fetch = saved.fetch;
    globalThis.setTimeout = saved.setTimeout;
    console.log = saved.log;
    console.warn = saved.warn;
    console.error = saved.error;
    console.info = saved.info;
    for (const name of definedGlobals) delete globalThis[name];
  }
}

// ---------------------------------------------------------------
// One case
// ---------------------------------------------------------------

async function runCase(name) {
  const caseDir = path.join(CORPUS, name);
  const meta = JSON.parse(fs.readFileSync(path.join(caseDir, "case.json"), "utf8"));
  const entry = path.join(caseDir, meta.entry ?? "index.ts");
  const outDir = path.join(OUT_ROOT, name);
  fs.rmSync(outDir, { recursive: true, force: true });
  fs.mkdirSync(outDir, { recursive: true });
  writeStubs(caseDir, outDir, meta.stubs);
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
    const driver = fs.existsSync(driverPath) ? driverPath : null;
    const options = { fakeTimers: meta.fakeTimers === true, globals: meta.globals ?? [] };
    const before = await runBundle(baselineFile, driver, options);
    const after = await runBundle(mangledFile, driver, options);
    if (!before.ok) {
      notes.push(`baseline bundle threw: ${before.error}`);
    }
    const a = JSON.stringify(before.observed);
    const b = JSON.stringify(after.observed);
    if (a !== b) {
      failures.push(
        `observable behaviour changed\n      baseline: ${truncate(a)}\n      mangled:  ${truncate(b)}`,
      );
    }
  }

  const status = failures.length > 0 ? "fail" : "pass";
  return { name, status, failures, notes };
}

function firstDiagnostic(res) {
  const text = `${res.stderr}${res.stdout}`.trim();
  return text.split("\n").find((l) => l.trim().length > 0) ?? "(no diagnostic)";
}

// A property name "appears" if it shows up as a member access, an
// object-literal key, a class member, or a quoted key. Bare
// substring matching would be fooled by a same-named local.
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

// ---------------------------------------------------------------
// Driver
// ---------------------------------------------------------------

const caseNames = fs
  .readdirSync(CORPUS, { withFileTypes: true })
  .filter((d) => d.isDirectory() && fs.existsSync(path.join(CORPUS, d.name, "case.json")))
  .map((d) => d.name)
  .sort()
  .filter((n) => onlyCase === null || n === onlyCase);

if (caseNames.length === 0) {
  console.error(`verify_mangle_safety: no cases matched${onlyCase ? ` \`${onlyCase}\`` : ""}`);
  process.exit(2);
}

const results = [];
for (const name of caseNames) {
  results.push(await runCase(name));
}

let regressions = 0;
let fixed = 0;
console.log("mangle-safety validation\n");
for (const res of results) {
  const meta = JSON.parse(fs.readFileSync(path.join(CORPUS, res.name, "case.json"), "utf8"));
  const expected = meta.expectStatus ?? "pass";
  const mark = res.status === expected ? "ok  " : res.status === "pass" ? "FIXD" : "REGR";
  if (mark === "REGR") regressions++;
  if (mark === "FIXD") fixed++;
  console.log(`  [${mark}] ${res.name.padEnd(24)} ${res.status}${res.status === expected ? "" : ` (expected ${expected})`}`);
  if (res.detail) console.log(`         ${res.detail}`);
  for (const f of res.failures) console.log(`         ✗ ${f}`);
  for (const n of res.notes) console.log(`         · ${n}`);
  if (update) {
    meta.expectStatus = res.status;
    fs.writeFileSync(
      path.join(CORPUS, res.name, "case.json"),
      `${JSON.stringify(meta, null, 2)}\n`,
    );
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
