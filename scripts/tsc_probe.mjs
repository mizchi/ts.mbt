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
// with --version). Since the TS7 migration that IS tsgo — the compiler the
// oracle's baselines come from — where it used to be 6.0.3, a stand-in
// that disagreed with TS7 at least once (TS1249 on an ambient bodiless
// member, which 6.0.3 reports and TS7 accepts). Notes written before the
// migration quote 6.0.3's answers; re-probe before relying on one.
// `node_modules/typescript-6` keeps 6.0.3 installed for the classic-API
// scripts, so the old answer is one import away if a comparison is wanted.
//
// One TS7 behaviour shows up on old corpus headers: `@target: es5` is
// TS5108 ("option has been removed") and `@target: es3` is TS6046. Both
// are reported, because the API's `parseConfigFile` silently drops a
// rejected option and the probe re-asks the CLI exactly when it does.
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
  const { opts, diags, otherFiles } = probe(file);
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
  // Diagnostics tsc reported in ANOTHER file — almost always a vendored
  // `lib.*.d.ts` type-checked against a global augmentation in this file
  // under `@skipDefaultLibCheck: false`. Shown separately because they are
  // not something a rule about this file could flag, and because they used
  // to be printed as if they belonged to it.
  if (!raw && otherFiles && otherFiles.length > 0) {
    const files = [...new Set(otherFiles.map((d) => d.file))].join(", ");
    console.log(`  (+ ${otherFiles.length} diagnostic(s) in ${files})`);
  }
}
