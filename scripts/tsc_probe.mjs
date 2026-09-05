// Run the locally installed TypeScript compiler over a file the way the
// conformance harness would, and print its diagnostics.
//
// Why this exists: the conformance gate's ground truth is a pair of TS7
// baseline NAME lists, so it says that TS7 errored on a file and nothing
// about WHAT it said. `checker_miss_buckets.mjs` fills that in from the
// submodule's TS6-era `.errors.txt` baselines, which is an approximation
// and, for a file with no baseline at all, no answer. This asks a real
// compiler instead — and, more importantly, it can be pointed at a
// hand-written LEGAL NEIGHBOUR, which no baseline can ever cover.
//
// The version here is whatever `node_modules/typescript` holds (print it
// with --version), not tsgo, so a disagreement with the TS7 verdict is
// possible and is itself worth knowing rather than assuming. There is at
// least one recorded instance: TS1249 on an ambient bodiless member, which
// this compiler reports and TS7 accepts, so following it there would have
// shipped a false positive.
//
// The header reading and program construction live in
// `scripts/lib/tsc-probe.mjs`, shared with `checker_miss_rank.mjs`.
//
// Usage:
//   node scripts/tsc_probe.mjs [--version] [--raw] <file.ts> [more.ts ...]
import path from "node:path";
import { ts, probe } from "./lib/tsc-probe.mjs";

const argv = process.argv.slice(2);
if (argv.includes("--version")) {
  console.log(ts.version);
  process.exit(0);
}
const raw = argv.includes("--raw");
const files = argv.filter((a) => !a.startsWith("--"));
if (files.length === 0) {
  console.error("usage: node scripts/tsc_probe.mjs [--raw] <file.ts> ...");
  process.exit(2);
}

for (const file of files) {
  const { opts, diags } = probe(file);
  const shown =
    Object.entries(opts)
      .map(([k, v]) => `${k}=${v}`)
      .join(" ") || "defaults";
  if (!raw) console.log(`--- ${path.basename(file)}  [${shown}]`);
  if (diags.length === 0) {
    console.log("  (accepted)");
    continue;
  }
  for (const d of diags) {
    const where = d.line ? `(${d.line},${d.col})` : "";
    console.log(`  TS${d.code}${where}: ${d.msg}`);
  }
}
