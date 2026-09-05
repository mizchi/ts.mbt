// Is any checker rule superlinear in the size of a module-wide list?
//
// Every other checker harness in this repo asks whether the answer is
// RIGHT. The conformance oracle runs 4,484 conformance files, and each of
// them is a few dozen lines — so a rule that is quadratic in the number
// of interfaces, classes or exports in one file is invisible to all of
// them, and stays invisible until somebody compiles a real `.d.ts`.
//
// Two have already shipped. Batch CP's TS5076 read the token span that
// `parse_or` had consumed, once per expression per precedence level, and
// took a 9 MB file from seconds to over 180 — the checker binary sat at
// 100% CPU for 36 minutes before anyone ran `ps`. Then batches CY-DB
// added three nested scans over module-wide lists at once
// (`check_merged_interface_member_conflicts` compared every pair of
// interfaces in the module to find same-NAMED pairs;
// `check_merged_export_modifiers` rescanned both declaration lists per
// exported name; both joined member lists as fields x fields), and at
// 4,000 interfaces the checker was 6.5x slower than it had been one
// batch earlier. Nothing failed. The oracle stayed at FP 0, the 2,965
// tests stayed green, and the regression was found only because somebody
// asked.
//
// So this is the missing question, asked the way a cost model has to be
// asked — by GROWTH, not by absolute time. It generates a size ladder
// along each axis a checker rule loops over, times the binary at each
// rung, and fits an exponent: linear work doubles when the input
// doubles (exponent ~1.0), quadratic work quadruples (~2.0). An
// exponent over the threshold fails the run and names the axis, which
// is the part a stopwatch reading cannot tell you.
//
// It says nothing about which RULE, only which axis — that is what the
// axis is for. `interfaces` points at the interface loops the way
// `exports` points at the export ones, and from there it is a grep.
//
// Deliberately synthetic. A real library exercises whichever shapes it
// happens to use, and what is needed here is a controlled count of one
// declaration kind at a time: `same-bytes` below is the control that
// separates "grows with the LIST" from "grows with the FILE", and it is
// what proved the interface regression was about the count rather than
// the 527 KB.
//
//   node scripts/verify_checker_scaling.mjs
//   node scripts/verify_checker_scaling.mjs --axis interfaces
//   node scripts/verify_checker_scaling.mjs --max-exponent 1.4
//   node scripts/verify_checker_scaling.mjs --baseline path/to/tscheck.exe

import { spawnSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const WORK = path.join(ROOT, "_build", "checker-scaling");

const CANDIDATES = [
  path.join(ROOT, "_build/native/release/build/cmd/tscheck/tscheck.exe"),
  path.join(ROOT, "_build/native/debug/build/cmd/tscheck/tscheck.exe"),
];

// The rungs. 4x between the first and last is enough to separate linear
// from quadratic (4x versus 16x) while keeping the whole run near a
// minute; going wider mostly buys precision on an answer that is already
// unambiguous.
const RUNGS = [500, 1000, 2000, 4000];

// One generator per axis. Each emits N declarations of ONE kind, so a
// failing axis names the list the offending loop walks. The bodies carry
// a few members because several checks join member lists — a
// zero-member declaration would hide exactly the fields x fields shape
// that regressed.
const AXES = {
  // Interface count, with extends clauses and exports: the shape the
  // merged-conflict, conflicting-bases and export-modifier rules read.
  interfaces: (n) => {
    const out = [];
    for (let i = 0; i < n; i++) {
      out.push(`export interface I${i} { a${i}: number; b${i}: string; c${i}: boolean }`);
      if (i > 1) out.push(`export interface J${i} extends I${i - 1}, I${i - 2} { d${i}: number }`);
    }
    return out.join("\n") + "\n";
  },
  // Interfaces that all share ONE name, so every merge-related rule sees
  // a single group of N declarations. A rule that indexes by name is
  // linear here; a rule that pairs within a group is quadratic, and that
  // is a real cost a real `.d.ts` can pay (`interface Window` is
  // declared in many halves).
  "merged-interfaces": (n) => {
    const out = [];
    for (let i = 0; i < n; i++) out.push(`interface M { m${i}: number; shared: string }`);
    return out.join("\n") + "\n";
  },
  classes: (n) => {
    const out = [];
    for (let i = 0; i < n; i++) {
      out.push(
        `export class C${i} { private p${i}: number = 0; protected q${i} = ""; m${i}(): void {} get g${i}(): number { return 1 } }`,
      );
    }
    return out.join("\n") + "\n";
  },
  // Export clauses and declared names: the `<export-local>` /
  // `<export-type>` marker channels, plus the imported-binding lookup.
  exports: (n) => {
    const out = [];
    for (let i = 0; i < n; i++) out.push(`const e${i} = ${i};`);
    for (let i = 0; i < n; i++) out.push(`export { e${i} };`);
    return out.join("\n") + "\n";
  },
  "type-aliases": (n) => {
    const out = [];
    for (let i = 0; i < n; i++) out.push(`export type T${i} = { a${i}: number; b${i}: string };`);
    return out.join("\n") + "\n";
  },
  enums: (n) => {
    const out = [];
    for (let i = 0; i < n; i++) out.push(`export enum E${i} { A${i}, B${i} = 2, C${i} = "s" }`);
    return out.join("\n") + "\n";
  },
  vars: (n) => {
    const out = [];
    for (let i = 0; i < n; i++) out.push(`declare var v${i}: number;`);
    for (let i = 0; i < n; i++) out.push(`v${i};`);
    return out.join("\n") + "\n";
  },
  // THE CONTROL. Byte count grows with the rung and the declaration
  // count does not (12 interfaces throughout), so this axis stays flat
  // for a list-quadratic rule and grows for a genuinely byte-quadratic
  // one. Without it, "the big file is slow" cannot be told from "the
  // long list is slow" — and that distinction is the whole diagnosis.
  "same-bytes": (n) => {
    const out = [];
    const per = Math.max(1, Math.round((n * 3) / 12));
    for (let k = 0; k < 12; k++) {
      out.push(`export interface Big${k} {`);
      for (let i = 0; i < per; i++) out.push(`  m${k}_${i}: number;`);
      out.push(`}`);
    }
    return out.join("\n") + "\n";
  },
};

function parseArgs(argv) {
  const opts = { axis: null, maxExponent: 1.5, baseline: null, keep: false };
  for (let i = 2; i < argv.length; i++) {
    const a = argv[i];
    if (a === "--axis") opts.axis = argv[++i];
    else if (a === "--max-exponent") opts.maxExponent = Number(argv[++i]);
    else if (a === "--baseline") opts.baseline = argv[++i];
    else if (a === "--keep") opts.keep = true;
    else if (a === "--help" || a === "-h") opts.help = true;
    else {
      console.error(`unknown argument: ${a}`);
      process.exit(2);
    }
  }
  return opts;
}

function findBinary(explicit) {
  if (explicit) {
    if (!fs.existsSync(explicit)) {
      console.error(`binary not found: ${explicit}`);
      process.exit(2);
    }
    return explicit;
  }
  // Prefer whichever build is NEWER rather than whichever is listed
  // first: this repo has already lost a measurement round to an oracle
  // silently reading a stale RELEASE binary while the change under test
  // was in the DEBUG one.
  const found = CANDIDATES.filter((p) => fs.existsSync(p));
  if (found.length === 0) {
    console.error("no tscheck binary — run `moon build --target native --release` first");
    process.exit(2);
  }
  found.sort((a, b) => fs.statSync(b).mtimeMs - fs.statSync(a).mtimeMs);
  return found[0];
}

// Wall time for one file, in ms, as the MINIMUM over repeats. A minimum
// is the right statistic for "how much work is there": noise only ever
// adds time, so the floor is the closest estimate of the work itself,
// and a mean would let one scheduler hiccup masquerade as an exponent.
function timeFile(bin, file, iters, repeats) {
  let best = Infinity;
  for (let r = 0; r < repeats; r++) {
    const t0 = process.hrtime.bigint();
    const res = spawnSync(bin, ["--iters", String(iters), file], { stdio: "ignore" });
    const t1 = process.hrtime.bigint();
    if (res.status !== 0 && res.status !== null) {
      return { ms: NaN, error: `exit ${res.status}` };
    }
    const ms = Number(t1 - t0) / 1e6 / iters;
    if (ms < best) best = ms;
  }
  return { ms: best };
}

// Fit an exponent k such that t ~ n^k, from the first and last rung.
// Using the endpoints rather than a least-squares fit is deliberate:
// the endpoints are where a quadratic term is largest and smallest, so
// they give the strongest signal, and a mid-ladder wobble cannot dilute
// a real n^2 into a passing average.
function exponent(rungs, times) {
  const first = rungs[0];
  const last = rungs[rungs.length - 1];
  const tf = times[0];
  const tl = times[times.length - 1];
  if (!(tf > 0) || !(tl > 0)) return NaN;
  return Math.log(tl / tf) / Math.log(last / first);
}

function main() {
  const opts = parseArgs(process.argv);
  if (opts.help) {
    console.log(
      "usage: verify_checker_scaling.mjs [--axis NAME] [--max-exponent K] [--baseline BIN] [--keep]",
    );
    console.log(`axes: ${Object.keys(AXES).join(", ")}`);
    return;
  }

  const bin = findBinary(opts.baseline);
  fs.mkdirSync(WORK, { recursive: true });

  const axes = opts.axis ? [opts.axis] : Object.keys(AXES);
  for (const a of axes) {
    if (!AXES[a]) {
      console.error(`unknown axis: ${a} (have: ${Object.keys(AXES).join(", ")})`);
      process.exit(2);
    }
  }

  console.log("=== Checker scaling ===");
  console.log(`Binary        : ${path.relative(ROOT, bin)}`);
  console.log(`Rungs         : ${RUNGS.join(", ")} declarations`);
  console.log(`Max exponent  : ${opts.maxExponent.toFixed(2)}  (linear 1.0, quadratic 2.0)`);
  console.log("");

  const header = ["axis", ...RUNGS.map((n) => `n=${n}`), "exp", "verdict"];
  const rows = [];
  const failures = [];

  for (const axis of axes) {
    const times = [];
    let broke = null;
    for (const n of RUNGS) {
      const file = path.join(WORK, `${axis}-${n}.ts`);
      fs.writeFileSync(file, AXES[axis](n));
      // Small inputs finish fast enough that process startup dominates,
      // so iterate in-process at the low rungs and once at the high
      // ones, where the work itself is the whole measurement.
      const iters = n <= 1000 ? 5 : 2;
      const { ms, error } = timeFile(bin, file, iters, 3);
      if (error) {
        broke = error;
        break;
      }
      times.push(ms);
      if (!opts.keep) fs.rmSync(file, { force: true });
    }
    if (broke) {
      rows.push([axis, ...RUNGS.map(() => "-"), "-", `ERROR ${broke}`]);
      failures.push(`${axis}: ${broke}`);
      continue;
    }
    const k = exponent(RUNGS, times);
    // `same-bytes` is a control, not a budget: its declaration count is
    // constant, so its growth is whatever per-byte cost the checker has
    // and it is not asserted on. It is printed because a run where it
    // ALSO grew quadratically means the cost is in the bytes and the
    // per-axis numbers below are all reading the same thing.
    const asserted = axis !== "same-bytes";
    const bad = asserted && (Number.isNaN(k) || k > opts.maxExponent);
    if (bad) failures.push(`${axis}: exponent ${k.toFixed(2)} > ${opts.maxExponent.toFixed(2)}`);
    rows.push([
      axis,
      ...times.map((t) => `${t.toFixed(1)}ms`),
      Number.isNaN(k) ? "?" : k.toFixed(2),
      asserted ? (bad ? "SUPERLINEAR" : "ok") : "(control)",
    ]);
  }

  const widths = header.map((h, i) => Math.max(h.length, ...rows.map((r) => String(r[i]).length)));
  const fmt = (cells) =>
    cells.map((c, i) => (i === 0 ? String(c).padEnd(widths[i]) : String(c).padStart(widths[i]))).join("  ");
  console.log(fmt(header));
  console.log(widths.map((w) => "-".repeat(w)).join("  "));
  for (const r of rows) console.log(fmt(r));
  console.log("");

  if (failures.length > 0) {
    console.log("FAIL — a checker rule grows superlinearly in one of these lists:");
    for (const f of failures) console.log(`  ${f}`);
    console.log("");
    console.log("The axis names the list, not the rule. Grep the checks that loop");
    console.log("over it and look for a nested scan where an index belongs: the");
    console.log("three found this way were a pair loop over every declaration in");
    console.log("the module to find same-NAMED pairs, a rescan of two declaration");
    console.log("lists per exported name, and two member lists joined as a nested");
    console.log("scan instead of one indexed pass.");
    process.exit(1);
  }

  console.log(`OK — all ${axes.filter((a) => a !== "same-bytes").length} asserted axes are within budget.`);
}

main();
