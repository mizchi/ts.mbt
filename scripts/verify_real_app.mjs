// `fixtures/real-app` — an application that imports real npm packages,
// checked by `mtsc -p … --noEmit` the way a user's CI would check it.
//
// Every other checker gate measures mtsc against single-file conformance
// cases or against a package's OWN sources, reached through relative
// imports. None of them imports a package the way an application does, so
// none of them could see that `mtsc --noEmit` read no package types at all:
// every npm import was `any`, eleven deliberate errors were reported by
// tsc and by mtsc not once, and the run exited 0. This is the gate that
// would have caught it.
//
// Two projects share one `node_modules` (the repo's own devDependencies):
//
//   bad/  one deliberate error per file, each in a package's main API.
//   ok/   ordinary legal use of the same packages.
//
// Questions, in this order, because each is only meaningful once the one
// before it holds:
//
//   1. BASELINE. tsc (`node_modules/typescript`) reports exactly one error
//      in every `bad/` file and nothing in `ok/`. A drift here is a finding
//      about TypeScript or about an upgraded package, not about mtsc.
//
//   2. FALSE POSITIVES. mtsc reports nothing anywhere in `ok/`, and nothing
//      in a `bad/` file outside the file's own planted error. Either fails
//      the run: this is the direction the repo's FP budget is zero for.
//
//   3. MISSES. mtsc reports in every `bad/` file. A silent one fails unless
//      it is declared in `mtsc-misses.txt` with its reason; a declared miss
//      that no longer misses fails as STALE, which is what keeps that file
//      from turning into a suppression list.
//
// Usage:
//   node scripts/verify_real_app.mjs [--mtsc PATH] [--no-tsc] [--verbose]
import fs from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";

const ROOT = path.resolve(path.dirname(new URL(import.meta.url).pathname), "..");
const FIX = path.join(ROOT, "fixtures", "real-app");
const argv = process.argv.slice(2);
const flag = (f) => argv.includes(f);
const value = (f) => {
  const i = argv.indexOf(f);
  return i >= 0 ? argv[i + 1] : undefined;
};
const verbose = flag("--verbose");

const MTSC = path.resolve(
  value("--mtsc") ?? path.join(ROOT, "_build", "native", "release", "build", "cmd", "mtsc", "mtsc.exe"),
);
const TSC = path.join(ROOT, "node_modules", "typescript", "bin", "tsc");
// mtsc's async runtime blocks SIGTERM, so a bound on it has to be SIGKILL.
const TIMEOUT_MS = 600_000;

const failures = [];
const fail = (msg) => failures.push(msg);

/** The `.ts` / `.tsx` files of one project, relative to the project dir. */
function projectFiles(dir) {
  return fs
    .readdirSync(path.join(dir, "src"))
    .filter((f) => /\.tsx?$/.test(f))
    .map((f) => `src/${f}`)
    .sort();
}

/** Count of diagnostics per file, from `file(l,c): error TSn: …` lines. */
function runTsc(dir) {
  const r = spawnSync(process.execPath, [TSC, "-p", "tsconfig.json", "--pretty", "false"], {
    cwd: dir,
    encoding: "utf8",
    timeout: TIMEOUT_MS,
    killSignal: "SIGKILL",
  });
  if (r.error) throw r.error;
  const out = new Map();
  for (const line of `${r.stdout}\n${r.stderr}`.split("\n")) {
    const m = /^(.+?)\(\d+,\d+\): error (TS\d+):/.exec(line.trim());
    if (!m) continue;
    const file = m[1].replaceAll("\\", "/");
    if (!out.has(file)) out.set(file, []);
    out.get(file).push(`${m[2]} ${line.trim()}`);
  }
  return out;
}

/** mtsc's reports per file, from `mtsc: type error in FILE [PATH]: MSG`. */
function runMtsc(dir) {
  const started = Date.now();
  const r = spawnSync(MTSC, ["-p", "tsconfig.json", "--noEmit"], {
    cwd: dir,
    encoding: "utf8",
    timeout: TIMEOUT_MS,
    killSignal: "SIGKILL",
  });
  if (r.error) throw r.error;
  if (r.signal) throw new Error(`mtsc was killed (${r.signal}) in ${dir}`);
  const out = new Map();
  const other = [];
  for (const raw of `${r.stdout}\n${r.stderr}`.split("\n")) {
    const line = raw.trim();
    if (!line) continue;
    const m = /^mtsc: [a-z ]*error in (\S+?)(?: \[|:)/.exec(line);
    if (m) {
      const file = path.relative(dir, path.resolve(dir, m[1])).replaceAll("\\", "/");
      if (!out.has(file)) out.set(file, []);
      out.get(file).push(line);
    } else if (/error/i.test(line)) {
      // A report this harness cannot attribute is still a report: in `ok/`
      // it is a false positive like any other.
      other.push(line);
    }
  }
  return { byFile: out, other, status: r.status, ms: Date.now() - started };
}

/** `bad/src/x.ts  reason…` lines; `#` starts a comment. */
function readMisses() {
  const p = path.join(FIX, "mtsc-misses.txt");
  const out = new Map();
  if (!fs.existsSync(p)) return out;
  for (const raw of fs.readFileSync(p, "utf8").split("\n")) {
    const line = raw.replace(/#.*/, "").trim();
    if (!line) continue;
    const [file, ...reason] = line.split(/\s+/);
    if (reason.length === 0) fail(`mtsc-misses.txt: \`${file}\` has no reason`);
    out.set(file, reason.join(" "));
  }
  return out;
}

const badDir = path.join(FIX, "bad");
const okDir = path.join(FIX, "ok");
const badFiles = projectFiles(badDir);
const okFiles = projectFiles(okDir);

// 1. BASELINE
if (!flag("--no-tsc")) {
  const badTsc = runTsc(badDir);
  for (const f of badFiles) {
    const n = badTsc.get(f)?.length ?? 0;
    if (n !== 1) fail(`baseline: tsc reports ${n} error(s) in bad/${f}, expected exactly 1${n ? `:\n    ${badTsc.get(f).join("\n    ")}` : ""}`);
  }
  for (const [f, diags] of badTsc) {
    if (!badFiles.includes(f)) fail(`baseline: tsc reports outside the planted files: ${diags.join("; ")}`);
  }
  const okTsc = runTsc(okDir);
  for (const [, diags] of okTsc) fail(`baseline: tsc reports in ok/: ${diags.join("; ")}`);
}

// 2 + 3. MTSC
const misses = readMisses();
const bad = runMtsc(badDir);
const ok = runMtsc(okDir);

for (const [f, lines] of ok.byFile) fail(`false positive in ok/${f}:\n    ${lines.join("\n    ")}`);
for (const line of ok.other) fail(`false positive in ok/: ${line}`);
for (const line of bad.other) fail(`unattributed report in bad/: ${line}`);
for (const [f, lines] of bad.byFile) {
  if (!badFiles.includes(f)) fail(`false positive in bad/${f} (no error is planted there):\n    ${lines.join("\n    ")}`);
}

let caught = 0;
let declared = 0;
for (const f of badFiles) {
  const key = `bad/${f}`;
  const reported = bad.byFile.has(f);
  if (reported) caught++;
  if (misses.has(key)) {
    declared++;
    if (reported) fail(`STALE: ${key} is declared a miss in mtsc-misses.txt and mtsc now reports it — remove the entry`);
  } else if (!reported) {
    fail(`undeclared miss: mtsc is silent on ${key}`);
  }
  if (verbose) console.log(`${reported ? "caught " : "missed "} ${key}${reported ? `: ${bad.byFile.get(f)[0]}` : ""}`);
}
for (const key of misses.keys()) {
  if (!badFiles.includes(key.replace(/^bad\//, ""))) fail(`mtsc-misses.txt names ${key}, which is not a planted file`);
}

console.log(
  `real app: ${badFiles.length} planted error(s), mtsc reports ${caught} (${declared} declared miss(es)); ` +
    `${okFiles.length} legal file(s), mtsc false positives ${ok.byFile.size + ok.other.length}; ` +
    `mtsc ${bad.ms} ms + ${ok.ms} ms`,
);
if (failures.length) {
  for (const f of failures) console.error(`FAIL ${f}`);
  process.exit(1);
}
