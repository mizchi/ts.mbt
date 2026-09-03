// Rank the checker's remaining conformance MISSes by what the REAL
// compiler says about each file.
//
// The gate (`checker_conformance_oracle.sh`) reports how many files TS7
// errors on while we stay quiet, and nothing about which or why. Its
// `--miss-list` writes the paths; this reads them, runs each file through
// the locally installed compiler under its own harness header, and groups.
//
// Two things this exists to avoid, both recorded as mistakes in CLAUDE.md:
//
//   - `checker_miss_buckets.mjs` reads the submodule's TS6-era
//     `.errors.txt` baselines. That is an approximation of TS7 and, for a
//     file with no baseline, no answer at all. A real compiler answers
//     both.
//   - A count of (file, code) PAIRS inflates every code in a file that
//     raises five of them, and the thing that flips is a FILE. So the
//     ranking is by `solo` — files where this code is the ONLY one
//     reported, i.e. the honest yield of a rule for it — with the pair
//     count kept beside it, and a `first` column of the code with the
//     lowest number in each file, which is what a grammar rule usually
//     keys on.
//
// Usage:
//   node scripts/checker_miss_rank.mjs <miss-list.txt> [--code TS1234]
//                                      [--dir cluster] [--json out.json]
//
// With --code, list the files reporting that code instead of the table.
// With --dir, restrict to miss paths containing that substring.
import fs from "node:fs";
import path from "node:path";
import { probe } from "./lib/tsc-probe.mjs";

const argv = process.argv.slice(2);
function flag(name) {
  const i = argv.indexOf(name);
  return i >= 0 ? argv[i + 1] : null;
}
const listFile = argv.find((a) => !a.startsWith("--") && !isFlagValue(a));
function isFlagValue(a) {
  const i = argv.indexOf(a);
  return i > 0 && argv[i - 1].startsWith("--");
}
if (!listFile) {
  console.error("usage: node scripts/checker_miss_rank.mjs <miss-list.txt>");
  process.exit(2);
}
const onlyCode = flag("--code");
const onlyDir = flag("--dir");
const jsonOut = flag("--json");

let files = fs
  .readFileSync(listFile, "utf8")
  .split("\n")
  .map((l) => l.trim())
  .filter(Boolean);
if (onlyDir) files = files.filter((f) => f.includes(onlyDir));

const rows = [];
for (const f of files) {
  let diags;
  try {
    ({ diags } = probe(f));
  } catch (e) {
    rows.push({ file: f, codes: [], error: String(e.message || e) });
    continue;
  }
  // A file the local compiler ACCEPTS is a disagreement with TS7, not a
  // rankable miss — reported separately rather than silently dropped,
  // because it is the one thing here worth knowing on its own.
  const codes = [...new Set(diags.map((d) => d.code))].sort((a, b) => a - b);
  rows.push({
    file: f,
    codes,
    msgs: diags.slice(0, 3).map((d) => `TS${d.code}: ${d.msg}`),
  });
}

if (jsonOut) fs.writeFileSync(jsonOut, JSON.stringify(rows, null, 2));

if (onlyCode) {
  const want = Number(onlyCode.replace(/^TS/i, ""));
  for (const r of rows) {
    if (!r.codes.includes(want)) continue;
    const solo = r.codes.length === 1 ? " [solo]" : ` [+${r.codes.length - 1}]`;
    console.log(`${r.file}${solo}`);
    for (const m of r.msgs) console.log(`    ${m}`);
  }
  process.exit(0);
}

const accepted = rows.filter((r) => !r.error && r.codes.length === 0);
const failed = rows.filter((r) => r.error);
const stats = new Map(); // code -> { pairs, solo, first }
for (const r of rows) {
  if (r.codes.length === 0) continue;
  const first = r.codes[0];
  for (const c of r.codes) {
    const s = stats.get(c) ?? { pairs: 0, solo: 0, first: 0 };
    s.pairs += 1;
    if (r.codes.length === 1) s.solo += 1;
    if (c === first) s.first += 1;
    stats.set(c, s);
  }
}

// A FEATURE cluster can span many codes (symbolProperty* spans seven and is
// one feature), and a code-keyed table cannot see it, so group by the
// conformance directory too. Corpus COUNT is not real-world frequency —
// `parser/ecmascript5` is the largest cluster and is broken syntax nobody
// writes — so both views are printed and neither is called the answer.
const byDir = new Map();
for (const r of rows) {
  if (r.codes.length === 0) continue;
  const d = path.dirname(r.file).split("conformance/")[1] ?? "?";
  byDir.set(d, (byDir.get(d) ?? 0) + 1);
}

console.log(`miss files probed : ${rows.length}`);
console.log(`  rankable        : ${rows.length - accepted.length - failed.length}`);
console.log(`  locally accepted: ${accepted.length}   (this compiler disagrees with TS7)`);
if (failed.length) console.log(`  probe failed    : ${failed.length}`);
console.log("");
console.log("code      solo  pairs  first   (solo = this code is the only lever)");
for (const [c, s] of [...stats.entries()].sort(
  (a, b) => b[1].solo - a[1].solo || b[1].pairs - a[1].pairs,
)) {
  if (s.pairs < 2 && s.solo === 0) continue;
  console.log(
    `TS${String(c).padEnd(8)}${String(s.solo).padStart(4)}${String(s.pairs).padStart(7)}${String(s.first).padStart(7)}`,
  );
}
const oneOff = [...stats.values()].filter((s) => s.pairs === 1).length;
console.log(`\n(${oneOff} codes with exactly one miss file each, not listed)`);
console.log("\nfiles per conformance directory:");
for (const [d, n] of [...byDir.entries()].sort((a, b) => b[1] - a[1]).slice(0, 20)) {
  console.log(`  ${String(n).padStart(4)}  ${d}`);
}
if (accepted.length) {
  console.log("\nlocally accepted (TS7 errors, this compiler does not):");
  for (const r of accepted.slice(0, 40)) console.log(`  ${r.file}`);
}
