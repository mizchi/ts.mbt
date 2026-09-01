// Bucket the conformance MISSes by TypeScript error code.
//
// `checker_conformance_oracle.sh` answers "how many" and gates on FP, which
// is what CI needs. It deliberately says nothing about WHICH errors we miss,
// because its ground truth is a pair of baseline NAME lists — a name tells
// you that TS7 errored, not what it said. So the counts it prints cannot
// rank any work: "MISS 399" is not something anyone can act on.
//
// This adds the missing half. For every MISS it reads the error CODES out of
// the TypeScript submodule's own `.errors.txt` baseline and groups by code,
// so the output is a ranked list of buckets with example files.
//
// One caveat, stated because it changes how the numbers should be read: the
// verdict (errors / accepts) comes from the vendored **TS7** manifests, while
// the error CODES come from the submodule's TS6-era baselines. TS7 is a
// port and agrees with TS6 on the overwhelming majority of diagnostics, but
// a bucket label is an approximation — the verdict is not. A MISS with no
// baseline file at all is reported under `NOBASE` rather than dropped, since
// silently discarding it would understate the total.
//
// The per-file classification is cached as a TSV, because running the
// checker over 5,695 files is minutes and re-bucketing is milliseconds.
// `--refresh` recomputes it.
//
// Usage:
//   node scripts/checker_miss_buckets.mjs [--refresh] [--dir types]
//                                        [--code TS2322] [--limit 20]
import fs from "node:fs";
import path from "node:path";
import { spawn, spawnSync } from "node:child_process";
import os from "node:os";

const ROOT = path.resolve(import.meta.dirname, "..");
const CONFORMANCE = path.join(ROOT, "typescript/tests/cases/conformance");
const BASELINES = path.join(ROOT, "typescript/tests/baselines/reference");
const RAN = path.join(ROOT, "scripts/ts7_baselines/tsgo_ran_set.txt");
const ERRS = path.join(ROOT, "scripts/ts7_baselines/tsgo_errors_set.txt");
const CACHE = path.join(ROOT, "_build/checker-miss/results.tsv");

const argv = process.argv.slice(2);
const flag = (name) => argv.includes(name);
const opt = (name, dflt) => {
  const i = argv.indexOf(name);
  return i >= 0 && argv[i + 1] ? argv[i + 1] : dflt;
};

function tscheckBin() {
  for (const mode of ["release", "debug"]) {
    const p = path.join(ROOT, `_build/native/${mode}/build/cmd/tscheck/tscheck.exe`);
    if (fs.existsSync(p)) return p;
  }
  console.error("tscheck binary not found — run `moon build --target native`");
  process.exit(1);
}

function readSet(file) {
  return new Set(fs.readFileSync(file, "utf8").split("\n").filter(Boolean));
}

function conformanceFiles(subdir) {
  const base = subdir ? path.join(CONFORMANCE, subdir) : CONFORMANCE;
  const out = [];
  const walk = (d) => {
    for (const e of fs.readdirSync(d, { withFileTypes: true })) {
      const p = path.join(d, e.name);
      if (e.isDirectory()) walk(p);
      else if (e.name.endsWith(".ts")) out.push(p);
    }
  };
  walk(base);
  return out.sort();
}

// Run the checker over every candidate file, `-P nproc` at a time. The
// classification is exactly the oracle's, and the totals are compared
// against it below — a miner that disagrees with the gate is a broken
// miner, and that has to be visible rather than assumed.
async function classify(files, ran, errs) {
  const bin = tscheckBin();
  const rows = [];
  const workers = Math.max(1, os.cpus().length);
  let next = 0;
  const runOne = (file) =>
    new Promise((resolve) => {
      const child = spawn(bin, [file], { encoding: "utf8" });
      let buf = "";
      child.stdout.on("data", (d) => (buf += d));
      child.stderr.on("data", (d) => (buf += d));
      child.on("error", () => resolve("spawnfail"));
      child.on("close", () => {
        const last = buf.trimEnd().split("\n").pop() ?? "";
        if (/error:/.test(last)) return resolve("parsefail");
        const m = last.match(/(\d+) issues/);
        resolve(m ? m[1] : "0");
      });
    });
  const pump = async () => {
    for (;;) {
      const i = next++;
      if (i >= files.length) return;
      const file = files[i];
      const base = path.basename(file, ".ts");
      rows[i] = [base, path.relative(ROOT, file), errs.has(base) ? "1" : "0", await runOne(file)];
      if (rows.filter(Boolean).length % 500 === 0) {
        process.stderr.write(`  ${rows.filter(Boolean).length}/${files.length}\r`);
      }
    }
  };
  await Promise.all(Array.from({ length: workers }, pump));
  process.stderr.write("\n");
  return rows.filter(Boolean);
}

// Codes out of the submodule baseline. The format is
// `file.ts(3,5): error TS2322: ...`, and a file can repeat a code.
function baselineCodes(base) {
  for (const cand of [`${base}.errors.txt`, `${base}(target=esnext).errors.txt`]) {
    const p = path.join(BASELINES, cand);
    if (!fs.existsSync(p)) continue;
    const codes = new Set();
    for (const m of fs.readFileSync(p, "utf8").matchAll(/error (TS\d+):/g)) codes.add(m[1]);
    if (codes.size) return [...codes];
  }
  // Variant baselines (`name(strict=true).errors.txt` etc.) — take any.
  let hits = null;
  try {
    hits = fs.readdirSync(BASELINES).filter((f) => f.startsWith(base + "(") && f.endsWith(".errors.txt"));
  } catch { hits = []; }
  for (const h of hits) {
    const codes = new Set();
    for (const m of fs.readFileSync(path.join(BASELINES, h), "utf8").matchAll(/error (TS\d+):/g)) codes.add(m[1]);
    if (codes.size) return [...codes];
  }
  return [];
}

const subdir = opt("--dir", "");
const ran = readSet(RAN);
const errs = readSet(ERRS);

let rows;
if (!flag("--refresh") && fs.existsSync(CACHE) && !subdir) {
  rows = fs.readFileSync(CACHE, "utf8").split("\n").filter(Boolean).map((l) => l.split("\t"));
} else {
  const all = conformanceFiles(subdir);
  const candidates = all.filter((f) => {
    // Multi-file cases need a project graph the single-file CLI lacks.
    // `@filename` is case-insensitive in the TS harness.
    const src = fs.readFileSync(f, "utf8");
    if (/@filename/i.test(src)) return false;
    return ran.has(path.basename(f, ".ts"));
  });
  console.error(`classifying ${candidates.length} single-file cases (${all.length} found)…`);
  rows = await classify(candidates, ran, errs);
  if (!subdir) {
    fs.mkdirSync(path.dirname(CACHE), { recursive: true });
    fs.writeFileSync(CACHE, rows.map((r) => r.join("\t")).join("\n") + "\n");
  }
}

let tp = 0, tpParse = 0, miss = 0, fp = 0, tn = 0, pflegal = 0;
const missRows = [];
for (const [base, rel, has, ours] of rows) {
  const errored = has === "1";
  if (ours === "parsefail" || ours === "spawnfail") {
    if (errored) { tp++; tpParse++; } else { pflegal++; }
    continue;
  }
  const flagged = Number(ours) > 0;
  if (errored && flagged) tp++;
  else if (errored) { miss++; missRows.push([base, rel]); }
  else if (flagged) fp++;
  else tn++;
}

console.log("=== Checker vs TypeScript 7 — MISS buckets ===");
console.log(`TP ${tp} (parse-reject ${tpParse})  MISS ${miss}  FP ${fp}  PFLEGAL ${pflegal}  TN ${tn}`);
console.log("(cross-check these against scripts/checker_conformance_oracle.sh)");

const buckets = new Map();
for (const [base, rel] of missRows) {
  const codes = baselineCodes(base);
  const keys = codes.length ? codes : ["NOBASE"];
  for (const k of keys) {
    if (!buckets.has(k)) buckets.set(k, []);
    buckets.get(k).push(rel);
  }
}

const only = opt("--code", "");
if (only) {
  const files = buckets.get(only) ?? [];
  console.log(`\n--- ${only}: ${files.length} MISS files ---`);
  for (const f of files) console.log(`  ${f}`);
} else {
  const limit = Number(opt("--limit", "25"));
  const ranked = [...buckets.entries()].sort((a, b) => b[1].length - a[1].length);
  console.log(`\n--- top ${limit} buckets (a file with N codes counts in N) ---`);
  console.log("count  code      example");
  for (const [code, files] of ranked.slice(0, limit)) {
    console.log(`${String(files.length).padStart(5)}  ${code.padEnd(9)} ${path.basename(files[0])}`);
  }
  const tail = ranked.slice(limit).reduce((n, [, f]) => n + f.length, 0);
  if (tail) console.log(`${String(tail).padStart(5)}  (${ranked.length - limit} more codes)`);
}
