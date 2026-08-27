// Does the module-graph walk stay linear in the graph?
//
// It did not. The walk deduplicates on the SPECIFIER a module wrote, and
// for the two spellings that resolve to one file that is not the same
// question:
//
//   './util'      -> util.ts   resolution APPENDED an extension, so the
//                              loader also keys the extension-less form,
//                              and the second visit is caught.
//   './util.js'   -> util.ts   resolution REPLACED one. No alias is
//                              written, nothing dedupes, and the repeat
//                              visit re-reads the file, re-parses it,
//                              and re-pushes its own imports — which
//                              repeat in turn.
//
// On a diamond-shaped graph that is 2^depth. The second spelling is what
// TypeScript-with-NodeNext sources use, so this is not an exotic shape:
// zod writes `from "../core/util.js"` 65 times across 133 files and had
// not finished PARSING after eighteen minutes, while hono and valibot —
// extension-less — were always fine. Nothing in the suite would have
// noticed, because every fixture is small enough that 2^depth is small.
//
// So this generates the shape directly. Each level of the chain has two
// modules and each imports BOTH modules of the next level, which is the
// cheapest way to make repeat visits multiply. The assertion is on the
// GROWTH RATIO between two depths, not on absolute milliseconds: a
// linear walk adds a few files per level and barely moves, an
// exponential one quadruples every two levels, and no threshold in
// between is sensitive to how fast the machine is.
//
//   node scripts/verify_graph_walk.mjs
//   node scripts/verify_graph_walk.mjs --verbose

import { spawnSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const WORK = path.join(ROOT, "_build", "graph-walk");

const MTSC_CANDIDATES = [
  path.join(ROOT, "_build", "native", "release", "build", "cmd", "mtsc", "mtsc.exe"),
  path.join(ROOT, "_build", "native", "debug", "build", "cmd", "mtsc", "mtsc.exe"),
];

function findMtsc() {
  for (const c of MTSC_CANDIDATES) if (fs.existsSync(c)) return c;
  console.error("mtsc binary not found. Run `moon build --target native --release` first.");
  process.exit(2);
}

const args = process.argv.slice(2);
let verbose = false;
for (const a of args) {
  if (a === "--verbose" || a === "-v") verbose = true;
  else {
    console.error(`unknown argument: ${a}`);
    process.exit(2);
  }
}

const MTSC = findMtsc();

// A chain of `depth` levels, two modules per level, each importing both
// modules of the level below. `ext` is the suffix the import specifiers
// carry — "" for the extension-less style, ".js" for the NodeNext style.
function generate(depth, ext, tag) {
  const dir = path.join(WORK, `d${depth}${tag}`);
  fs.rmSync(dir, { recursive: true, force: true });
  fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(path.join(dir, `l${depth}a.ts`), "export const v = 1;\n");
  fs.writeFileSync(path.join(dir, `l${depth}b.ts`), "export const v = 2;\n");
  for (let i = depth - 1; i >= 0; i--) {
    for (const side of ["a", "b"]) {
      fs.writeFileSync(
        path.join(dir, `l${i}${side}.ts`),
        `import { v as x } from './l${i + 1}a${ext}';\n` +
          `import { v as y } from './l${i + 1}b${ext}';\n` +
          `export const v = x + y + ${i};\n`,
      );
    }
  }
  fs.writeFileSync(
    path.join(dir, "index.ts"),
    `import { v } from './l0a${ext}';\nconsole.log(v);\n`,
  );
  return dir;
}

function compile(dir) {
  const out = path.join(dir, "out.mjs");
  const started = process.hrtime.bigint();
  const r = spawnSync(MTSC, [path.join(dir, "index.ts"), "--bundle", "--no-check", "--out", out], {
    encoding: "utf8",
    maxBuffer: 1 << 26,
    timeout: 120_000,
    killSignal: "SIGKILL",
  });
  const ms = Number(process.hrtime.bigint() - started) / 1e6;
  if (r.signal === "SIGKILL") return { ok: false, ms, why: "no completion in 120s" };
  if (r.status !== 0 || !fs.existsSync(out)) {
    return { ok: false, ms, why: `exit ${r.status}` };
  }
  // The bundle also has to be right. An exponential walk that happened
  // to produce correct output is still a bug, but a linear walk that
  // dropped a module is a worse one, and this is where the dedup guard
  // could break it.
  const run = spawnSync("node", [out], { encoding: "utf8", timeout: 60_000 });
  return { ok: true, ms, stdout: (run.stdout || "").trim(), exit: run.status };
}

// Same graph, so both styles must produce the same value.
function expectedValue(depth) {
  let a = 1;
  let b = 2;
  for (let i = depth - 1; i >= 0; i--) {
    const v = a + b + i;
    a = v;
    b = v;
  }
  return a;
}

const STYLES = [
  { tag: "noext", ext: "", label: "extension-less" },
  { tag: "js", ext: ".js", label: "`.js` specifier" },
];
const LOW = 6;
const HIGH = 12;
// Six levels of a doubling walk is 2^6 = 64x. A linear walk over the
// same span adds twelve files. Eight is far above the first and far
// below the second, which is what makes it robust on a slow machine.
const MAX_RATIO = 8;

console.log("\nmodule-graph walk scaling");
console.log(`  diamond chain, depth ${LOW} vs ${HIGH}, both specifier styles\n`);

let failed = 0;
for (const style of STYLES) {
  const results = [];
  for (const depth of [LOW, HIGH]) {
    const dir = generate(depth, style.ext, style.tag);
    const r = compile(dir);
    results.push({ depth, ...r });
    if (!r.ok) {
      console.error(`  [FAIL] ${style.label} depth ${depth}: ${r.why}`);
      failed++;
      continue;
    }
    const want = String(expectedValue(depth));
    if (r.stdout !== want) {
      console.error(
        `  [FAIL] ${style.label} depth ${depth}: bundle printed ${JSON.stringify(r.stdout)}, expected ${want}`,
      );
      failed++;
    }
    fs.rmSync(dir, { recursive: true, force: true });
  }
  const [lo, hi] = results;
  if (!lo.ok || !hi.ok) continue;
  // A floor on the denominator: at these sizes both compiles are a few
  // milliseconds, and dividing by process startup noise invents ratios.
  const ratio = hi.ms / Math.max(lo.ms, 5);
  const verdict = ratio > MAX_RATIO ? "FAIL" : "ok";
  if (verdict === "FAIL") failed++;
  console.log(
    `  [${verdict === "ok" ? "ok  " : "FAIL"}] ${style.label.padEnd(16)} ` +
      `${lo.ms.toFixed(0).padStart(5)}ms -> ${hi.ms.toFixed(0).padStart(6)}ms   ` +
      `${ratio.toFixed(1)}x (limit ${MAX_RATIO}x)`,
  );
  if (verbose) {
    console.log(`         depth ${lo.depth}: ${lo.ms.toFixed(1)}ms, depth ${hi.depth}: ${hi.ms.toFixed(1)}ms`);
  }
}

fs.rmSync(WORK, { recursive: true, force: true });

if (failed) {
  console.error(
    `\n  ${failed} failure(s). A ratio over ${MAX_RATIO}x means the walk is` +
      ` re-visiting modules — check the dedup guard in` +
      ` mtsc_load_bundle_files (src/cmd/mtsc/main.mbt).\n`,
  );
  process.exit(1);
}
console.log("\n  both specifier styles walk the graph linearly\n");
