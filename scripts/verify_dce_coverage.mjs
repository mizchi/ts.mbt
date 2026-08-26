// What dead code does mtsc still leave behind?
//
// The fuzzer (`scripts/fuzz_mangle.mjs`) attacks one direction: code we
// delete that we should have kept. This attacks the other: code we keep
// that we could have deleted. Both are needed, and only the first one
// makes tests fail on its own — a missed opportunity is silent, it just
// costs bytes forever.
//
// So the table below is a set of failing tests, written first. Each case
// is a small program containing exactly one kind of dead code, and it
// asserts three things:
//
//   absent    a marker that must NOT survive into the bundle. This is
//             the opportunity. A case where it survives is RED.
//   present   markers that MUST survive. Without these an over-eager
//             pass could turn every case green by deleting the program.
//   stdout    what Node prints running the ORIGINAL TypeScript. The
//             bundle has to print the same thing. A case that removes
//             the dead code and changes the output is not a win.
//
// The `present` and `stdout` checks are what make this safe to act on:
// they turn "make the byte count smaller" into "make the byte count
// smaller without changing what the program does".
//
// Usage:
//   node scripts/verify_dce_coverage.mjs [--only <name>] [--verbose]
//                                        [--expected <file>]
//
// Exit status is non-zero when a case regresses against
// `fixtures/dce-coverage/expected.json` — a MISS that was previously a
// PASS, or a BROKEN case. New MISSes on a case already recorded as
// missing do not fail, so the table can carry known gaps.

import { spawnSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const EXPECTED = path.join(ROOT, "fixtures", "dce-coverage", "expected.json");

const MTSC_CANDIDATES = [
  path.join(ROOT, "_build", "native", "release", "build", "cmd", "mtsc", "mtsc.exe"),
  path.join(ROOT, "_build", "native", "debug", "build", "cmd", "mtsc", "mtsc.exe"),
];

function findMtsc() {
  for (const candidate of MTSC_CANDIDATES) if (fs.existsSync(candidate)) return candidate;
  console.error("verify_dce_coverage: mtsc binary not found. Run `moon build --target native`.");
  process.exit(2);
}

// Two profiles, because some elimination is deliberately gated. The
// dead-class-field and trailing-parameter passes only run once the
// property-mangling safety analysis has cleared the bundle — they depend
// on the same proof. A case that survives `base` but not `mangle` is
// therefore GATED, not missing, and reporting it as a gap would be
// wrong.
const BASE_FLAGS = ["--bundle", "--treeshake", "--fold", "--minify", "--no-check"];
const MANGLE_FLAGS = [
  ...BASE_FLAGS,
  "--mangle",
  "--mangle-properties",
  "--reserve-entry-exports",
];

// ---------------------------------------------------------------
// The table
// ---------------------------------------------------------------
//
// Every case keeps one live `console.log` so the behaviour comparison
// has something to compare, and puts the dead thing somewhere that
// cannot be reached. `DEADMARK` names are deliberately long and unique
// so the absence check cannot match something else by accident.

const CASES = [
  // --- bindings and declarations ---------------------------------
  {
    name: "unused-const-literal",
    source: `const deadmark_a = 1;
console.log("live");`,
    absent: ["deadmark_a"],
    present: ["live"],
  },
  {
    name: "unused-function-decl",
    source: `function deadmark_fn(x: number) { return x * 2; }
console.log("live");`,
    absent: ["deadmark_fn"],
    present: ["live"],
  },
  {
    name: "unused-class-decl",
    source: `class Deadmark_Cls { m() { return 1; } }
console.log("live");`,
    absent: ["Deadmark_Cls"],
    present: ["live"],
  },
  {
    name: "unused-arrow-const",
    source: `const deadmark_arrow = (x: number) => x + 1;
console.log("live");`,
    absent: ["deadmark_arrow"],
    present: ["live"],
  },
  {
    name: "type-only-decls-erased",
    source: `interface Deadmark_Iface { p: number }
type Deadmark_Alias = string | number;
console.log("live");`,
    absent: ["Deadmark_Iface", "Deadmark_Alias"],
    present: ["live"],
  },
  {
    name: "unused-chain-of-decls",
    // A dead binding whose initializer references another dead binding.
    // One round of elimination leaves the second alive.
    source: `const deadmark_one = 1;
const deadmark_two = deadmark_one + 1;
const deadmark_three = deadmark_two + 1;
console.log("live");`,
    absent: ["deadmark_one", "deadmark_two", "deadmark_three"],
    present: ["live"],
  },

  // --- unreachable statements ------------------------------------
  {
    name: "after-return",
    source: `function f() {
  return 1;
  const deadmark_after = 2;
  console.log("deadmark_unreach");
}
console.log(f());`,
    absent: ["deadmark_after", "deadmark_unreach"],
    present: ["return 1", "console.log"],
  },
  {
    name: "after-throw",
    source: `function f() {
  try { throw new Error("x"); console.log("deadmark_unreach"); } catch { return 2; }
}
console.log(f());`,
    absent: ["deadmark_unreach"],
    present: [],
  },
  {
    name: "after-break",
    source: `for (let i = 0; i < 1; i++) {
  break;
  console.log("deadmark_unreach");
}
console.log("live");`,
    absent: ["deadmark_unreach"],
    present: ["live"],
  },
  {
    name: "after-continue",
    source: `for (let i = 0; i < 1; i++) {
  continue;
  console.log("deadmark_unreach");
}
console.log("live");`,
    absent: ["deadmark_unreach"],
    present: ["live"],
  },

  // --- constant conditions --------------------------------------
  {
    name: "if-false",
    source: `if (false) { console.log("deadmark_branch"); }
console.log("live");`,
    absent: ["deadmark_branch"],
    present: ["live"],
  },
  {
    name: "if-true-else",
    source: `if (true) { console.log("live"); } else { console.log("deadmark_branch"); }
`,
    absent: ["deadmark_branch"],
    present: ["live"],
  },
  {
    name: "while-false",
    source: `while (false) { console.log("deadmark_loop"); }
console.log("live");`,
    absent: ["deadmark_loop"],
    present: ["live"],
  },
  {
    name: "cond-const-test",
    source: `const flag = false;
if (flag) { console.log("deadmark_branch"); }
console.log("live");`,
    absent: ["deadmark_branch"],
    present: ["live"],
  },
  {
    name: "logical-and-false",
    source: `false && console.log("deadmark_short");
console.log("live");`,
    absent: ["deadmark_short"],
    present: ["live"],
  },
  {
    name: "ternary-const",
    source: `console.log(true ? "live" : "deadmark_arm");`,
    absent: ["deadmark_arm"],
    present: ["live"],
  },
  {
    name: "switch-literal-discriminant",
    source: `switch (1) {
  case 0: console.log("deadmark_case0"); break;
  case 1: console.log("live"); break;
  default: console.log("deadmark_default");
}`,
    absent: ["deadmark_case0", "deadmark_default"],
    present: ["live"],
  },

  // --- dead stores ----------------------------------------------
  {
    name: "dead-store-overwritten",
    source: `let v = 1;
v = 2;
console.log(v);`,
    // The first value is never read. Terser/esbuild both drop it.
    absent: ["v=1", "v = 1"],
    present: [],
  },
  {
    name: "dead-store-never-read",
    // The binding name has to be distinctive: `absent: ["v"]` matched
    // the `v` inside the surviving `"live"` string and reported a
    // working elimination as a miss.
    source: `let deadmark_store = 1;
deadmark_store = 2;
console.log("live");`,
    absent: ["deadmark_store"],
    present: ["live"],
  },
  {
    name: "self-assignment",
    source: `let v = 1;
v = v;
console.log(v);`,
    absent: ["v=v", "v = v"],
    present: [],
  },

  // --- class members --------------------------------------------
  {
    name: "unused-class-method",
    source: `class C {
  live() { return 1; }
  deadmark_method() { return 2; }
}
console.log(new C().live());`,
    absent: ["deadmark_method"],
    present: ["live"],
  },
  {
    name: "unused-class-field",
    source: `class C {
  liveField = 1;
  deadmark_field = 2;
  get() { return this.liveField; }
}
console.log(new C().get());`,
    absent: ["deadmark_field"],
    present: [],
  },
  {
    name: "unused-static-method",
    source: `class C {
  static live() { return 1; }
  static deadmark_static() { return 2; }
}
console.log(C.live());`,
    absent: ["deadmark_static"],
    present: [],
  },
  {
    name: "unused-getter",
    source: `class C {
  get live() { return 1; }
  get deadmark_getter() { return 2; }
}
console.log(new C().live);`,
    absent: ["deadmark_getter"],
    present: [],
  },

  // --- object / parameter surface -------------------------------
  {
    name: "unread-object-property",
    source: `const o = { live: 1, deadmark_prop: 2 };
console.log(o.live);`,
    absent: ["deadmark_prop"],
    present: [],
  },
  {
    name: "unused-trailing-param",
    source: `function f(a: number, deadmark_param: number) { return a; }
console.log(f(1, 2));`,
    absent: ["deadmark_param"],
    present: [],
  },
  {
    name: "unused-catch-binding",
    source: `try { throw 1; } catch (deadmark_err) { console.log("live"); }`,
    absent: ["deadmark_err"],
    present: ["live"],
  },

  // --- structural noise -----------------------------------------
  {
    name: "empty-statements",
    source: `;;;
console.log("live");
;;;`,
    absent: [";;"],
    present: ["live"],
  },
  {
    name: "empty-block",
    source: `{ }
console.log("live");`,
    absent: ["{}"],
    present: ["live"],
  },
  {
    name: "empty-else",
    source: `if (Math.random() < 2) { console.log("live"); } else { }`,
    absent: ["else"],
    present: ["live"],
  },
  {
    name: "unused-label",
    source: `deadmark_label: for (let i = 0; i < 1; i++) { console.log("live"); }`,
    absent: ["deadmark_label"],
    present: ["live"],
  },
  {
    name: "pure-iife-unused",
    source: `(function () { return 1; })();
console.log("live");`,
    absent: ["function"],
    present: ["live"],
  },
  {
    name: "redundant-trailing-return",
    source: `function f() { console.log("live"); return undefined; }
f();`,
    absent: ["undefined"],
    present: ["live"],
  },
  {
    name: "double-negation-of-boolean",
    source: `const b = true;
console.log(!!b);`,
    absent: ["!!"],
    present: [],
  },
];

// ---------------------------------------------------------------
// Runner
// ---------------------------------------------------------------

const args = process.argv.slice(2);
let only = null;
let verbose = false;
let expectedPath = EXPECTED;
let update = false;
for (let i = 0; i < args.length; i++) {
  if (args[i] === "--only") only = args[++i];
  else if (args[i] === "--verbose") verbose = true;
  else if (args[i] === "--expected") expectedPath = path.resolve(args[++i]);
  else if (args[i] === "--update") update = true;
  else {
    console.error(`verify_dce_coverage: unknown argument ${args[i]}`);
    process.exit(2);
  }
}

const MTSC = findMtsc();
const WORK = fs.mkdtempSync(path.join(os.tmpdir(), "dce-coverage-"));

function run(command, argv, options = {}) {
  return spawnSync(command, argv, { encoding: "utf8", maxBuffer: 32 * 1024 * 1024, ...options });
}

function checkCase(testCase) {
  const sourcePath = path.join(WORK, `${testCase.name}.ts`);
  fs.writeFileSync(sourcePath, testCase.source);

  // What the original does, per Node's own type stripping. No compiler
  // of ours involved, so this is the behavioural baseline.
  const reference = run(process.execPath, [sourcePath]);
  if (reference.status !== 0) {
    return { verdict: "BADCASE", detail: firstLine(reference.stderr) };
  }

  const base = checkProfile(testCase, sourcePath, reference, "base", BASE_FLAGS);
  if (base.verdict !== "MISS") return base;
  // It survived the plain pipeline. Does the mangle-gated half of the
  // pipeline get it? Then the opportunity exists and is merely gated.
  const mangled = checkProfile(testCase, sourcePath, reference, "mangle", MANGLE_FLAGS);
  if (mangled.verdict === "PASS") {
    return { verdict: "GATED", detail: "eliminated only with --mangle-properties", code: mangled.code };
  }
  if (mangled.verdict === "BROKEN") return mangled;
  return base;
}

function checkProfile(testCase, sourcePath, reference, profile, flags) {
  const outPath = path.join(WORK, `${testCase.name}.${profile}.mjs`);
  const compile = run(MTSC, [sourcePath, ...flags, "--out", outPath]);
  if (compile.status !== 0 || !fs.existsSync(outPath)) {
    return { verdict: "BROKEN", detail: `compile failed: ${firstLine(compile.stdout, compile.stderr)}` };
  }
  const code = fs.readFileSync(outPath, "utf8");

  const actual = run(process.execPath, [outPath]);
  if (actual.status !== 0) {
    return { verdict: "BROKEN", detail: `bundle threw: ${firstLine(actual.stderr)}`, code };
  }
  if (actual.stdout !== reference.stdout) {
    return {
      verdict: "BROKEN",
      detail: `output differs: original ${JSON.stringify(reference.stdout)} vs bundle ${JSON.stringify(actual.stdout)}`,
      code,
    };
  }

  // Over-deletion guard: a pass that removed the live part too would
  // otherwise look like a win.
  const missingLive = (testCase.present ?? []).filter((needle) => !code.includes(needle));
  if (missingLive.length > 0) {
    return { verdict: "BROKEN", detail: `live marker(s) gone: ${missingLive.join(", ")}`, code };
  }

  const survived = testCase.absent.filter((needle) => code.includes(needle));
  if (survived.length > 0) {
    return { verdict: "MISS", detail: `still present: ${survived.join(", ")}`, code };
  }
  return { verdict: "PASS", code };
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

const expected = fs.existsSync(expectedPath)
  ? JSON.parse(fs.readFileSync(expectedPath, "utf8"))
  : {};

console.log("dead-code elimination coverage\n");

const results = {};
let regressions = 0;
let fixed = 0;
const counts = { PASS: 0, GATED: 0, MISS: 0, BROKEN: 0, BADCASE: 0 };

for (const testCase of CASES) {
  if (only && only !== testCase.name) continue;
  const result = checkCase(testCase);
  results[testCase.name] = result.verdict;
  counts[result.verdict] = (counts[result.verdict] ?? 0) + 1;

  const was = expected[testCase.name];
  let tag = "     ";
  if (was && was !== result.verdict) {
    if (result.verdict === "PASS") {
      tag = " NEW ";
      fixed += 1;
    } else if (was === "PASS" || result.verdict === "BROKEN") {
      tag = "REGR!";
      regressions += 1;
    }
  }

  const mark = {
    PASS: "ok  ",
    GATED: "gate",
    MISS: "miss",
    BROKEN: "FAIL",
    BADCASE: "??  ",
  }[result.verdict];
  console.log(
    `  [${mark}]${tag} ${testCase.name.padEnd(30)} ${result.verdict === "PASS" ? "" : result.detail}`,
  );
  if (verbose && result.code) console.log(`         ${result.code.replace(/\n/g, "\n         ")}`);
}

console.log("");
console.log(
  `  ${counts.PASS} eliminated, ${counts.GATED} gated behind --mangle-properties, ` +
    `${counts.MISS} missed, ${counts.BROKEN} broken, ${counts.BADCASE} bad case(s)`,
);
if (fixed > 0) console.log(`  ${fixed} case(s) newly eliminated — update the expectations`);

if (update) {
  fs.mkdirSync(path.dirname(expectedPath), { recursive: true });
  fs.writeFileSync(expectedPath, `${JSON.stringify(results, null, 2)}\n`);
  console.log(`  wrote ${path.relative(ROOT, expectedPath)}`);
}

fs.rmSync(WORK, { recursive: true, force: true });

if (counts.BADCASE > 0) {
  console.error("\n  a case's own source does not run — fix the case, not the compiler");
  process.exit(2);
}
if (regressions > 0) {
  console.error(`\n  ${regressions} regression(s) against ${path.relative(ROOT, expectedPath)}`);
  process.exit(1);
}
