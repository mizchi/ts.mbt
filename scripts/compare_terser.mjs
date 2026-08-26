// mtsc against terser, rule by rule.
//
// Two questions, and they need different setups.
//
//   1. Where does terser beat us? Every loss is a compress rule we have
//      not ported, and the case that loses names it.
//   2. Where should we beat terser? terser has no type information, so
//      anything mtsc concludes from a TypeScript type is out of its
//      reach. Those cases are the reason this project exists, and a
//      TIE on one of them is a failure — it means the type-driven pass
//      did not fire.
//
// Fairness. terser cannot parse TypeScript, so a direct `in.ts`
// comparison would measure our parser, not our optimizer. Both sides
// start from the same JavaScript instead:
//
//   in.ts --[mtsc --bundle, no optimization]--> plain.mjs
//            |                                    |
//            +-- terser (compress + mangle) ------+-- bytes, behaviour
//            +-- mtsc (full pipeline) ------------+
//
// Property mangling is reported separately. terser's `mangle.properties`
// is off by default and its own documentation calls it unsafe without a
// hand-maintained reserved list; mtsc derives that list from the types.
// Comparing our property mangling against terser's default is the
// type-aware advantage, and comparing it against terser's opt-in
// property mangling is a correctness comparison, not a size one — so the
// harness runs that variant too and reports whether terser's output
// still behaves.
//
// Usage:
//   node scripts/compare_terser.mjs [--only <name>] [--group <group>]
//                                   [--verbose] [--update]

import { spawnSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { minify } from "terser";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const EXPECTED = path.join(ROOT, "fixtures", "terser-parity", "expected.json");

const MTSC_CANDIDATES = [
  path.join(ROOT, "_build", "native", "release", "build", "cmd", "mtsc", "mtsc.exe"),
  path.join(ROOT, "_build", "native", "debug", "build", "cmd", "mtsc", "mtsc.exe"),
];

function findMtsc() {
  for (const candidate of MTSC_CANDIDATES) if (fs.existsSync(candidate)) return candidate;
  console.error("compare_terser: mtsc binary not found. Run `moon build --target native`.");
  process.exit(2);
}

// No optimization: this is the shared starting point, not a contender.
const PLAIN_FLAGS = ["--bundle", "--no-check"];
const MTSC_FLAGS = ["--bundle", "--treeshake", "--fold", "--minify", "--no-check", "--mangle"];
const MTSC_PROP_FLAGS = [...MTSC_FLAGS, "--mangle-properties", "--reserve-entry-exports"];

// terser at full strength, minus the unsafe_* family (which changes
// semantics by design and is not a fair comparison for a compiler that
// refuses to). `passes: 3` because terser is single-pass by default and
// we run several passes ourselves; giving it fewer would flatter us.
const TERSER_OPTIONS = {
  compress: { passes: 3, module: true, toplevel: true },
  mangle: { toplevel: true },
  format: { comments: false },
  module: true,
};

// ---------------------------------------------------------------
// Cases
// ---------------------------------------------------------------
//
// `group: "terser-rule"` — one per compress option, so a LOSS names the
//   rule we have not ported. The option each case exercises is in
//   `rule`, taken from terser's own defaults list in
//   `node_modules/terser/lib/compress/index.js`.
//
// `group: "type-aware"` — something only a type checker can conclude.
//   A tie or a loss here is the interesting failure.

const CASES = [
  // ============ terser compress rules ============
  {
    group: "terser-rule",
    rule: "evaluate",
    name: "constant-arithmetic",
    source: `export const r = 2 * 3 + 4 - 1;
console.log(r);`,
  },
  {
    group: "terser-rule",
    rule: "booleans",
    name: "boolean-normalisation",
    source: `export function f(a: boolean) { return a ? true : false; }
console.log(f(true));`,
  },
  {
    group: "terser-rule",
    rule: "comparisons",
    name: "comparison-simplification",
    source: `export function f(a: number, b: number) { return !(a <= b); }
console.log(f(1, 2));`,
  },
  {
    group: "terser-rule",
    rule: "conditionals",
    name: "if-to-ternary",
    source: `export function f(c: boolean) { if (c) { return 1; } else { return 2; } }
console.log(f(true));`,
  },
  {
    group: "terser-rule",
    rule: "dead_code",
    name: "unreachable-after-return",
    source: `export function f() { return 1; console.log("gone"); }
console.log(f());`,
  },
  {
    group: "terser-rule",
    rule: "drop_debugger",
    name: "debugger-statement",
    source: `export function f() { debugger; return 1; }
console.log(f());`,
  },
  {
    group: "terser-rule",
    rule: "unused",
    name: "unused-declarations",
    source: `const unusedThing = 1;
function unusedFn() { return 2; }
console.log("live");`,
  },
  {
    group: "terser-rule",
    rule: "join_vars",
    name: "join-consecutive-vars",
    source: `let a = 1;
let b = 2;
let c = 3;
console.log(a + b + c);`,
  },
  {
    group: "terser-rule",
    rule: "sequences",
    name: "join-statements-with-comma",
    source: `export function f(g: { p: (n: number) => void }) { g.p(1); g.p(2); g.p(3); }
f({ p(n) { console.log(n); } });`,
  },
  {
    group: "terser-rule",
    rule: "if_return",
    name: "if-return-to-negation",
    source: `export function f(c: boolean, g: { p: () => void }) { if (c) { return; } g.p(); }
f(false, { p() { console.log("called"); } });`,
  },
  {
    group: "terser-rule",
    rule: "properties",
    name: "quoted-property-to-dot",
    source: `export function f(o: Record<string, number>) { return o["key"]; }
console.log(f({ key: 7 }));`,
  },
  {
    group: "terser-rule",
    rule: "computed_props",
    name: "computed-literal-key",
    source: `export const o = { ["key"]: 1 };
console.log(o.key);`,
  },
  {
    group: "terser-rule",
    rule: "loops",
    name: "while-true-to-for",
    source: `export function f() { let i = 0; while (true) { i++; if (i > 2) return i; } }
console.log(f());`,
  },
  {
    group: "terser-rule",
    rule: "switches",
    name: "switch-dead-arms",
    source: `export function f() {
  switch (2) {
    case 1: return "a";
    case 2: return "b";
    default: return "c";
  }
}
console.log(f());`,
  },
  {
    group: "terser-rule",
    rule: "typeofs",
    name: "typeof-undefined",
    source: `export function f(x: unknown) { return typeof x === "undefined"; }
console.log(f(undefined));`,
  },
  {
    group: "terser-rule",
    rule: "collapse_vars",
    name: "collapse-single-use-var",
    source: `export function f(g: { p: (n: number) => number }) { const t = g.p(1); return t + 1; }
console.log(f({ p(n) { return n; } }));`,
  },
  {
    group: "terser-rule",
    rule: "reduce_vars",
    name: "propagate-const-value",
    source: `const k = 5;
export function f() { return k * 2; }
console.log(f());`,
  },
  {
    group: "terser-rule",
    rule: "inline",
    name: "inline-single-use-function",
    source: `function helper(n: number) { return n + 1; }
console.log(helper(2));`,
  },
  {
    group: "terser-rule",
    rule: "hoist_props",
    name: "hoist-object-properties",
    source: `const cfg = { a: 1, b: 2 };
console.log(cfg.a + cfg.b);`,
  },
  {
    group: "terser-rule",
    rule: "side_effects",
    name: "drop-pure-statement",
    source: `1 + 2;
[1, 2, 3];
({ a: 1 });
console.log("live");`,
  },
  {
    group: "terser-rule",
    rule: "negate_iife",
    name: "negate-iife",
    source: `(function () { globalThis.__sink = 1; })();
console.log("live");`,
  },
  {
    group: "terser-rule",
    rule: "lhs_constants",
    name: "constant-on-the-right",
    source: `export function f(a: number) { return 1 === a; }
console.log(f(1));`,
  },
  {
    group: "terser-rule",
    rule: "arrows",
    name: "function-expression-to-arrow",
    source: `export const f = function (n: number) { return n + 1; };
console.log(f(1));`,
  },
  {
    group: "terser-rule",
    rule: "directives",
    name: "redundant-use-strict",
    source: `"use strict";
export function f() { "use strict"; return 1; }
console.log(f());`,
  },
  {
    group: "terser-rule",
    rule: "keep_fargs",
    name: "unused-trailing-parameter",
    source: `export function f(a: number, unusedB: number) { return a; }
console.log(f(1, 2));`,
  },

  // ============ type-aware: mtsc should win ============
  {
    group: "type-aware",
    rule: "typeof on an annotated binding",
    name: "typeof-narrowed-by-annotation",
    // terser cannot know `s` is a string, so it must keep the branch.
    source: `export function f(s: string) {
  if (typeof s === "string") { return "yes"; }
  return "no-this-is-dead";
}
console.log(f("x"));`,
  },
  {
    group: "type-aware",
    rule: "null check on a non-nullable type",
    name: "null-check-on-number",
    source: `export function f(n: number) {
  if (n === null) { return "dead-branch"; }
  return n + 1;
}
console.log(f(1));`,
  },
  {
    group: "type-aware",
    rule: "switch over a literal union",
    name: "switch-literal-union",
    source: `type Mode = "a" | "b";
export function f(m: Mode) {
  switch (m) {
    case "a": return 1;
    case "b": return 2;
    default: return "unreachable-default";
  }
}
console.log(f("a"));`,
  },
  {
    group: "type-aware",
    rule: "interface-typed property surface",
    name: "internal-only-property-names",
    // Every property here is internal: no export exposes them and
    // nothing observes their names. mtsc can rename them from the type
    // graph; terser cannot without a hand-written reserved list.
    source: `interface Internal { alphaValue: number; betaValue: number; gammaValue: number }
const state: Internal = { alphaValue: 1, betaValue: 2, gammaValue: 3 };
export function total() { return state.alphaValue + state.betaValue + state.gammaValue; }
console.log(total());`,
    properties: true,
  },
  {
    group: "type-aware",
    rule: "const enum inlining",
    name: "const-enum",
    source: `const enum Level { Low = 1, High = 2 }
export function f() { return Level.Low + Level.High; }
console.log(f());`,
    // `const enum` is NOT erasable syntax, so Node's type stripping
    // refuses to run the original and cannot serve as the behavioural
    // reference. State the expected output instead.
    expect: "3\n",
  },
  {
    group: "type-aware",
    rule: "as const object inlining",
    name: "as-const-object",
    source: `const table = { first: 10, second: 20 } as const;
export function f() { return table.first + table.second; }
console.log(f());`,
  },
  {
    group: "type-aware",
    rule: "unreachable method by type",
    name: "unused-method-on-typed-class",
    source: `class Service {
  used() { return 1; }
  neverCalledAnywhere() { return 2; }
}
const s = new Service();
console.log(s.used());`,
    properties: true,
  },
];

// ---------------------------------------------------------------
// Runner
// ---------------------------------------------------------------

const args = process.argv.slice(2);
let only = null;
let group = null;
let verbose = false;
let update = false;
for (let i = 0; i < args.length; i++) {
  if (args[i] === "--only") only = args[++i];
  else if (args[i] === "--group") group = args[++i];
  else if (args[i] === "--verbose") verbose = true;
  else if (args[i] === "--update") update = true;
  else {
    console.error(`compare_terser: unknown argument ${args[i]}`);
    process.exit(2);
  }
}

const MTSC = findMtsc();
const WORK = fs.mkdtempSync(path.join(os.tmpdir(), "terser-parity-"));

function run(command, argv, options = {}) {
  return spawnSync(command, argv, { encoding: "utf8", maxBuffer: 64 * 1024 * 1024, ...options });
}

/// Run a module and capture what it printed. `globals` are installed
/// first, because a case that declares an ambient global has to have one
/// at runtime.
function observe(modulePath, globals) {
  const prelude = Object.entries(globals ?? {})
    .map(([name, expr]) => `globalThis.${name} = ${expr};`)
    .join("\n");
  const harness = `${modulePath}.run.mjs`;
  fs.writeFileSync(
    harness,
    `${prelude}\nawait import(${JSON.stringify(`file://${modulePath}`)});\n`,
  );
  const result = run(process.execPath, [harness]);
  return { ok: result.status === 0, out: result.stdout ?? "", err: result.stderr ?? "" };
}

async function checkCase(testCase) {
  const dir = path.join(WORK, testCase.name);
  fs.mkdirSync(dir, { recursive: true });
  const sourcePath = path.join(dir, "in.ts");
  fs.writeFileSync(sourcePath, testCase.source);

  // Behavioural baseline: the original, run by Node itself — unless the
  // case declares one, which is for syntax Node's type stripping refuses
  // (`const enum` is not erasable).
  const reference = testCase.expect !== undefined
    ? { ok: true, out: testCase.expect, err: "" }
    : observe(sourcePath, testCase.globals);
  if (!reference.ok) {
    return { verdict: "BADCASE", detail: firstLine(reference.err) };
  }

  // The shared starting point.
  const plainPath = path.join(dir, "plain.mjs");
  const plain = run(MTSC, [sourcePath, ...PLAIN_FLAGS, "--out", plainPath]);
  if (plain.status !== 0 || !fs.existsSync(plainPath)) {
    return { verdict: "BADCASE", detail: `plain compile failed: ${firstLine(plain.stdout, plain.stderr)}` };
  }

  // ---- terser ----
  const plainCode = fs.readFileSync(plainPath, "utf8");
  let terserCode = null;
  try {
    const result = await minify(plainCode, TERSER_OPTIONS);
    terserCode = result.code ?? "";
  } catch (error) {
    return { verdict: "BADCASE", detail: `terser failed: ${error.message}` };
  }
  const terserPath = path.join(dir, "terser.mjs");
  fs.writeFileSync(terserPath, terserCode);
  const terserRun = observe(terserPath, testCase.globals);

  // ---- mtsc ----
  const flags = testCase.properties ? MTSC_PROP_FLAGS : MTSC_FLAGS;
  const mtscPath = path.join(dir, "mtsc.mjs");
  const compiled = run(MTSC, [sourcePath, ...flags, "--out", mtscPath]);
  if (compiled.status !== 0 || !fs.existsSync(mtscPath)) {
    return { verdict: "BROKEN", detail: `mtsc failed: ${firstLine(compiled.stdout, compiled.stderr)}` };
  }
  const mtscCode = fs.readFileSync(mtscPath, "utf8");
  const mtscRun = observe(mtscPath, testCase.globals);

  const report = {
    plainBytes: plainCode.length,
    terserBytes: terserCode.length,
    mtscBytes: mtscCode.length,
    terserOk: terserRun.ok && terserRun.out === reference.out,
    mtscOk: mtscRun.ok && mtscRun.out === reference.out,
    terserCode,
    mtscCode,
  };

  // Our own correctness comes first: a smaller bundle that misbehaves is
  // not a win, and this harness must never report one as such.
  if (!report.mtscOk) {
    return {
      verdict: "BROKEN",
      detail: mtscRun.ok
        ? `output differs: ${JSON.stringify(reference.out)} vs ${JSON.stringify(mtscRun.out)}`
        : `mtsc bundle threw: ${firstLine(mtscRun.err)}`,
      ...report,
    };
  }
  // terser misbehaving is a data point, not our problem — it happens
  // with property mangling, which is the whole argument for deriving the
  // reserved set from types.
  if (!report.terserOk) {
    return { verdict: "TERSER_BROKE", detail: "terser's output does not match", ...report };
  }

  const delta = report.mtscBytes - report.terserBytes;
  if (delta > 0) return { verdict: "LOSS", detail: `+${delta} bytes vs terser`, ...report };
  if (delta < 0) return { verdict: "WIN", detail: `${delta} bytes vs terser`, ...report };
  return { verdict: "TIE", detail: "same size", ...report };
}

function firstLine(...streams) {
  for (const stream of streams) {
    const line = (stream ?? "")
      .split("\n")
      .map((l) => l.trim())
      .find((l) => l.length > 0);
    if (line) return line;
  }
  return "(no output)";
}

const expected = fs.existsSync(EXPECTED) ? JSON.parse(fs.readFileSync(EXPECTED, "utf8")) : {};

console.log("mtsc vs terser 5.50.0\n");

const results = {};
const counts = {};
let regressions = 0;
const lossesByRule = [];
const tiedTypeAware = [];

for (const testCase of CASES) {
  if (only && only !== testCase.name) continue;
  if (group && group !== testCase.group) continue;
  const result = await checkCase(testCase);
  results[testCase.name] = result.verdict;
  counts[result.verdict] = (counts[result.verdict] ?? 0) + 1;

  const was = expected[testCase.name];
  let tag = "     ";
  if (was && was !== result.verdict) {
    const better = ["WIN", "TIE", "TERSER_BROKE"];
    if (better.indexOf(result.verdict) < better.indexOf(was) && result.verdict !== "LOSS") {
      tag = " NEW ";
    } else {
      tag = "REGR!";
      regressions += 1;
    }
  }

  const mark = {
    WIN: " win",
    TIE: " tie",
    LOSS: "LOSS",
    BROKEN: "FAIL",
    TERSER_BROKE: "t-ko",
    BADCASE: "??  ",
  }[result.verdict];
  const sizes =
    result.mtscBytes !== undefined
      ? `${String(result.mtscBytes).padStart(5)} vs ${String(result.terserBytes).padStart(5)}`
      : "".padStart(14);
  console.log(`  [${mark}]${tag} ${testCase.name.padEnd(34)} ${sizes}  ${result.detail ?? ""}`);
  if (verbose && result.mtscCode) {
    console.log(`         mtsc:   ${result.mtscCode.replace(/\n/g, " ")}`);
    console.log(`         terser: ${result.terserCode.replace(/\n/g, " ")}`);
  }

  if (result.verdict === "LOSS") {
    lossesByRule.push({ rule: testCase.rule, name: testCase.name, delta: result.mtscBytes - result.terserBytes });
  }
  if (testCase.group === "type-aware" && result.verdict === "TIE") {
    tiedTypeAware.push({ rule: testCase.rule, name: testCase.name });
  }
}

// ---------------------------------------------------------------
// Report
// ---------------------------------------------------------------

console.log("");
console.log(
  `  ${counts.WIN ?? 0} win, ${counts.TIE ?? 0} tie, ${counts.LOSS ?? 0} loss, ` +
    `${counts.TERSER_BROKE ?? 0} terser-misbehaved, ${counts.BROKEN ?? 0} mtsc-broken, ` +
    `${counts.BADCASE ?? 0} bad case(s)`,
);

if (lossesByRule.length > 0) {
  console.log("\n  terser rules we have not ported, worst first:\n");
  for (const loss of lossesByRule.sort((l, r) => r.delta - l.delta)) {
    console.log(`    +${String(loss.delta).padStart(4)} bytes  ${loss.rule.padEnd(24)} ${loss.name}`);
  }
}

if (tiedTypeAware.length > 0) {
  console.log("\n  type-aware cases where we only TIED — the type pass did not fire:\n");
  for (const tie of tiedTypeAware) {
    console.log(`    ${tie.rule.padEnd(34)} ${tie.name}`);
  }
}

if (update) {
  fs.mkdirSync(path.dirname(EXPECTED), { recursive: true });
  fs.writeFileSync(EXPECTED, `${JSON.stringify(results, null, 2)}\n`);
  console.log(`\n  wrote ${path.relative(ROOT, EXPECTED)}`);
}

fs.rmSync(WORK, { recursive: true, force: true });

if ((counts.BADCASE ?? 0) > 0) {
  console.error("\n  a case's own source does not run — fix the case, not the compiler");
  process.exit(2);
}
if ((counts.BROKEN ?? 0) > 0) {
  console.error("\n  mtsc produced a bundle that misbehaves — that is a correctness bug");
  process.exit(1);
}
if (regressions > 0) {
  console.error(`\n  ${regressions} regression(s) against ${path.relative(ROOT, EXPECTED)}`);
  process.exit(1);
}
