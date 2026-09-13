// Is the type CHECK superlinear in the module GRAPH?
//
// This repo has four harnesses that could have asked, and each one asks a
// question whose answer cannot reach this cost:
//
//   verify_checker_scaling.mjs  13 axes, every one of them `tscheck` over
//                               ONE file -- twelve grow a module-wide
//                               list, one grows an `extends` chain. No
//                               module graph exists in any of them.
//   verify_graph_walk.mjs       grows a module graph, and runs
//                               `--bundle --no-check`. Correct for its
//                               own question (the loader's 2^depth
//                               re-parse), and it switches off exactly
//                               the phase measured here.
//   verify_real_world_minify /  real multi-file targets, but published
//   bench_pipeline.mjs          `.js` -- where there are no type
//                               declarations to ingest, so the check is
//                               ~0.4 s of a 6 s compile. And `--timing`
//                               prints NOTHING when the check fails,
//                               which is every real `.ts` input in this
//                               repo's own submodule, because the CLI
//                               returns before the report.
//   the conformance oracle      4,484 single files, a few dozen lines each.
//
// So the gap was at their intersection: a module graph WITH the check on.
// Measured there, `Resolver::ingest_type_module` was 71.0% of a callgrind
// profile of a 162-module compile and the whole check was 87% of the wall
// clock (57.4 s against 7.5 s under `--no-check`) -- on an entry file of
// 3,255 bytes, because it imports a barrel.
//
// THE SHAPE IS THE WHOLE POINT. Three graph shapes were measured before
// this one and all three came back linear:
//
//   star / shared   entry imports N leaves; each leaf's transitive
//                   closure is one tiny module. 0.70 / 0.76.
//   chain           module i reaches i modules -- real closures, but
//                   70-byte modules. 0.91.
//
// The predicted cost is M x (bytes of the transitive closure), and each
// of those ladders grows ONE factor while holding the other at a value
// that makes the product small. A BARREL grows both at once: every
// module imports it and it re-exports every module, so every module's
// closure is the entire corpus -- which is what `./_namespaces/ts.js` is
// in the TypeScript compiler's own sources, and what an `index.ts`
// re-export barrel is in most real packages.
//
// And the fit only shows it once the ladder is long enough: over
// 10..80 modules this same axis reads 1.15 and looks linear; over
// 40..320 it reads 1.81. That is the `private-members` lesson in
// CLAUDE.md a second time -- a fit is only a fit over the range it was
// taken on.
//
// Asserts on the GROWTH EXPONENT, not on milliseconds, so the threshold
// does not depend on the machine.
//
//   node scripts/verify_graph_check_scaling.mjs
//   node scripts/verify_graph_check_scaling.mjs --verbose
//   node scripts/verify_graph_check_scaling.mjs --rungs 40,80,160,320
//   node scripts/verify_graph_check_scaling.mjs --max-exponent 1.4

import { spawnSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const WORK = path.join(ROOT, "_build", "graph-check-scaling");

const MTSC_CANDIDATES = [
  path.join(ROOT, "_build/native/release/build/cmd/mtsc/mtsc.exe"),
  path.join(ROOT, "_build/native/debug/build/cmd/mtsc/mtsc.exe"),
];

function findMtsc() {
  const found = MTSC_CANDIDATES.filter((c) => fs.existsSync(c));
  if (found.length === 0) {
    console.error("mtsc binary not found. Run `moon build --target native --release` first.");
    process.exit(2);
  }
  // Prefer whichever is NEWER, not whichever is listed first: the oracle
  // learned this the hard way, silently measuring a stale RELEASE binary
  // while the run under test had built DEBUG.
  found.sort((a, b) => fs.statSync(b).mtimeMs - fs.statSync(a).mtimeMs);
  return found[0];
}

// 4x between the endpoints separates linear from quadratic (4x vs 16x).
// 40..320 rather than 10..80 because the curve has not turned over at
// the low end -- see the header.
const DEFAULT_RUNGS = [40, 80, 160, 320];

// Gated at the measured value, with the reason, because the exponent is
// NOT fixed -- only reduced, 1.81 -> 1.57.
//
// And the honest caveat, measured after this file was written: REAL CODE
// DOES NOT HIT THIS. The barrel quadratic needs many SMALL modules, and
// at a fixed 7 MB of real TypeScript the exponent across 8 -> 38 modules
// is -0.15; the same 7 MB is 36.4 s as ONE module, 32.7 s as 8 and 31.6 s
// as 38. The 1.81 this harness found is an artifact of 350-byte generated
// modules, where an 18-entry constant table is comparable in size to a
// whole module. What it is worth keeping for is the duplicate-ingest
// regression it genuinely catches: `graph_type_modules` pushed a target
// once per EDGE, which was 2 x 161^2 ingests for a 162-module graph and a
// latent interface corruption (`merge_interfaces` is not idempotent over
// four append-only lists). The exponent assertion is the weaker half.
//
// The cost that DOES dominate real input is in
// `verify_checker_scaling.mjs`'s `nested-closures` axis, which is a
// single-file dimension and has nothing to do with the graph.
const MAX_EXPONENT = 1.65;

const DECLS_PER_MODULE = 12;

function buildBarrel(dir, n) {
  fs.rmSync(dir, { recursive: true, force: true });
  fs.mkdirSync(dir, { recursive: true });
  let barrel = "";
  for (let i = 1; i <= n; i++) barrel += `export * from "./m${i}.ts";\n`;
  fs.writeFileSync(path.join(dir, "barrel.ts"), barrel);
  for (let i = 1; i <= n; i++) {
    // Importing the barrel is what makes this module's transitive closure
    // the whole corpus. The imported name is a SIBLING's export, so the
    // edge is real and the checker has to resolve it.
    let s = `import { g${i === 1 ? n : i - 1} } from "./barrel.ts";\n`;
    for (let k = 0; k < DECLS_PER_MODULE; k++) {
      s += `export interface I${i}_${k} { a${k}: number; b${k}: string }\n`;
    }
    s += `export function g${i}(o: I${i}_0): number { return o.a0 + o.b0.length }\n`;
    fs.writeFileSync(path.join(dir, `m${i}.ts`), s);
  }
  fs.writeFileSync(
    path.join(dir, "entry.ts"),
    `import { g1 } from "./barrel.ts";\nexport const out: number = g1({ a0: 1, b0: "x" });\n`,
  );
  return path.join(dir, "entry.ts");
}

const argv = process.argv.slice(2);
let rungs = DEFAULT_RUNGS;
let maxExponent = MAX_EXPONENT;
let verbose = false;
for (let i = 0; i < argv.length; i++) {
  if (argv[i] === "--rungs") rungs = argv[++i].split(",").map(Number);
  else if (argv[i] === "--max-exponent") maxExponent = Number(argv[++i]);
  else if (argv[i] === "--verbose") verbose = true;
  else {
    console.error(`verify_graph_check_scaling: unknown argument ${argv[i]}`);
    process.exit(2);
  }
}

const MTSC = findMtsc();
console.log(`binary: ${path.relative(ROOT, MTSC)}`);
console.log(`barrel graph, ${DECLS_PER_MODULE} interfaces per module, check ON\n`);

const rows = [];
for (const n of rungs) {
  const dir = path.join(WORK, `n${n}`);
  const entry = buildBarrel(dir, n);
  const out = path.join(dir, "out.js");
  const t0 = process.hrtime.bigint();
  const r = spawnSync(MTSC, [entry, "--bundle", "-o", out], { encoding: "utf8" });
  const ms = Number(process.hrtime.bigint() - t0) / 1e6;
  // A generated graph that fails to type-check would be measuring the
  // early-return path instead of the check, so this is an assertion and
  // not a diagnostic.
  const errs = (r.stdout || "").split("\n").filter((l) => l.includes("type error"));
  if (errs.length > 0) {
    console.error(`FAIL: the generated ${n}-module graph does not type-check, so the`);
    console.error(`      measurement is of the early-return path rather than the check:`);
    for (const e of errs.slice(0, 3)) console.error(`      ${e}`);
    process.exit(1);
  }
  const bytes = fs
    .readdirSync(dir)
    .filter((f) => f.endsWith(".ts"))
    .reduce((a, f) => a + fs.statSync(path.join(dir, f)).size, 0);
  rows.push({ n, ms, bytes });
  if (verbose) console.log(`  n=${n}  ${ms.toFixed(0)} ms  corpus ${(bytes / 1024).toFixed(0)} KB`);
}

const lo = rows[0];
const hi = rows[rows.length - 1];
const exponent = Math.log(hi.ms / lo.ms) / Math.log(hi.n / lo.n);

console.log(
  `modules ${rows.map((r) => r.n).join(" / ")}` +
    `   ${rows.map((r) => r.ms.toFixed(0) + "ms").join(" / ")}`,
);
console.log(`exponent vs module count: ${exponent.toFixed(2)}  (budget ${maxExponent.toFixed(2)})`);

if (!(exponent <= maxExponent)) {
  console.error(
    `\nFAIL: the check is superlinear in the module count (${exponent.toFixed(2)} > ${maxExponent.toFixed(2)}).`,
  );
  console.error(
    `      A barrel graph gives every module a transitive closure of the whole`,
  );
  console.error(
    `      corpus, so anything run once per (module x reachable module) shows up`,
  );
  console.error(
    `      here. The cost this gate was written for was`,
  );
  console.error(
    `      \`Resolver::ingest_type_module\` allocating a full scratch \`Resolver\``,
  );
  console.error(
    `      -- including the 18-entry standard utility-type table -- per call.`,
  );
  process.exit(1);
}
console.log("\nok");
