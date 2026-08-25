// Where does the compile time go?
//
// The first question anyone asks about a slow compiler is "which pass",
// and until `mtsc --timing` existed the answer here was a guess. The
// guess was wrong: the first measurement of `checker.ts` put 731 ms of a
// 31.6 s compile inside the twenty-pass transform pipeline. The other
// 30.9 s was the type checker, running under `--no-check` purely to
// print diagnostics the caller had already said must not stop the emit.
//
// So this script exists to keep the answer measured. It runs a size
// ladder through `--timing`, prints each target's phase table, and
// derives throughput so a superlinear pass shows up as a falling
// bytes/second as the input grows.
//
// The ladder spans ~300 lines to 9 MB deliberately: a pass that is
// quadratic in the symbol count is invisible at the small end and
// dominant at the large end, which is exactly what happened to the
// numeric / container fixed points (5.5 s of a 10.9 s compile, from
// scanning every symbol per lookup).
//
// Inputs come from the same cache `verify_real_world_minify.mjs` fills,
// so run that first if a target reports as missing. No network here.
//
//   node scripts/bench_pipeline.mjs                 # every cached target
//   node scripts/bench_pipeline.mjs --only hono
//   node scripts/bench_pipeline.mjs --top 5         # phases per target

import { spawnSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const WORK = path.join(ROOT, "_build", "real-world");
const OUT = path.join(ROOT, "_build", "bench-pipeline");

const MTSC_CANDIDATES = [
  path.join(ROOT, "_build", "native", "release", "build", "cmd", "mtsc", "mtsc.exe"),
  path.join(ROOT, "_build", "native", "debug", "build", "cmd", "mtsc", "mtsc.exe"),
];

function findMtsc() {
  for (const c of MTSC_CANDIDATES) if (fs.existsSync(c)) return c;
  console.error("bench_pipeline: no mtsc binary. Run `moon build --target native --release`.");
  process.exit(1);
}

const args = process.argv.slice(2);
let only = null;
let top = 8;
for (let i = 0; i < args.length; i++) {
  if (args[i] === "--only") only = args[++i];
  else if (args[i] === "--top") top = Number(args[++i]);
  else {
    console.error(`bench_pipeline: unknown argument ${args[i]}`);
    process.exit(1);
  }
}

const MTSC = findMtsc();

// The flag set is what the real-world harness uses for each target, so
// these numbers describe the configuration that is actually validated.
const TARGETS = [
  {
    name: "minify-app",
    entry: path.join(ROOT, "examples", "minify-app", "src", "main.ts"),
    flags: ["--bundle", "--minify", "--mangle", "--mangle-properties", "--treeshake", "--fold"],
  },
  {
    name: "hono",
    entry: path.join(WORK, "hono", "hono", "src", "index.ts"),
    flags: ["--bundle", "--minify", "--mangle", "--mangle-properties", "--treeshake", "--fold"],
  },
  {
    name: "valibot",
    entry: path.join(WORK, "valibot", "valibot", "library", "src", "index.ts"),
    flags: ["--bundle", "--minify", "--mangle", "--mangle-properties", "--treeshake", "--fold"],
  },
  {
    name: "checker.ts",
    entry: path.join(WORK, "checker", "checker.ts"),
    flags: ["--minify", "--fold"],
  },
  {
    name: "typescript.js",
    entry: path.join(WORK, "typescript", "node_modules", "typescript", "lib", "typescript.js"),
    flags: ["--bundle", "--minify", "--mangle", "--treeshake"],
  },
];

// Total bytes of every file the compile actually read. `--timing` does
// not report it, so walk the entry's directory for the bundled targets
// and take the file size for the single-file ones. Approximate on
// purpose: it only has to be proportional for throughput to mean
// something.
function inputBytes(target) {
  if (!target.flags.includes("--bundle")) {
    return fs.statSync(target.entry).size;
  }
  const root = path.dirname(target.entry);
  let total = 0;
  const walk = (dir) => {
    for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
      if (e.name === "node_modules" || e.name.startsWith(".")) continue;
      const p = path.join(dir, e.name);
      if (e.isDirectory()) walk(p);
      else if (/\.(ts|tsx|js|mjs)$/.test(e.name) && !/\.test\.|\.spec\./.test(e.name)) {
        total += fs.statSync(p).size;
      }
    }
  };
  walk(root);
  return total;
}

// `--timing` prints "     253 ms   34.5%  label" rows and a
// "    731 ms  total" footer.
function parseTiming(stdout) {
  const rows = [];
  let total = null;
  for (const line of stdout.split("\n")) {
    const m = /^\s*(\d+) ms\s+([\d.]+)%\s+(.+?)\s*$/.exec(line);
    if (m) {
      rows.push({ ms: Number(m[1]), share: Number(m[2]), label: m[3] });
      continue;
    }
    const t = /^\s*(\d+) ms\s+total\s*$/.exec(line);
    if (t) total = Number(t[1]);
  }
  return { rows, total };
}

function human(n) {
  return n.toLocaleString("en-US");
}

fs.mkdirSync(OUT, { recursive: true });
console.log("mtsc pipeline benchmark\n");

const summary = [];
for (const target of TARGETS) {
  if (only && only !== target.name) continue;
  if (!fs.existsSync(target.entry)) {
    console.log(`  [skip] ${target.name.padEnd(14)} not cached — run scripts/verify_real_world_minify.mjs`);
    continue;
  }
  const out = path.join(OUT, `${target.name.replace(/[^\w.-]/g, "_")}.mjs`);
  const started = process.hrtime.bigint();
  const r = spawnSync(MTSC, [target.entry, "--no-check", ...target.flags, "--timing", "--out", out], {
    encoding: "utf8",
    maxBuffer: 256 * 1024 * 1024,
  });
  const wall = Number(process.hrtime.bigint() - started) / 1e6;
  if (r.status !== 0 || !fs.existsSync(out)) {
    console.log(`  [FAIL] ${target.name.padEnd(14)} exit ${r.status}`);
    continue;
  }
  const { rows, total } = parseTiming(r.stdout || "");
  const bytesIn = inputBytes(target);
  const bytesOut = fs.statSync(out).size;
  summary.push({ name: target.name, wall, total, bytesIn, bytesOut, rows });

  console.log(`  ${target.name}`);
  console.log(
    `    ${human(bytesIn)} bytes in -> ${human(bytesOut)} out, ${wall.toFixed(0)} ms wall` +
      `, ${(bytesIn / 1024 / (wall / 1000)).toFixed(0)} KiB/s`,
  );
  for (const row of rows.slice(0, top)) {
    console.log(
      `      ${String(row.ms).padStart(7)} ms  ${String(row.share).padStart(5)}%  ${row.label}`,
    );
  }
  if (rows.length > top) console.log(`      … ${rows.length - top} more phase(s)`);
  console.log("");
}

if (summary.length > 1) {
  // Throughput across the ladder. A pass that is superlinear in input
  // size shows up here and nowhere else: every target's own table looks
  // reasonable in isolation.
  console.log("  throughput across the ladder (higher is better)\n");
  console.log("    target          bytes in     wall ms     KiB/s");
  for (const s of summary) {
    const kibs = s.bytesIn / 1024 / (s.wall / 1000);
    console.log(
      `    ${s.name.padEnd(14)} ${human(s.bytesIn).padStart(10)} ${s.wall.toFixed(0).padStart(10)} ${kibs.toFixed(0).padStart(9)}`,
    );
  }
  console.log("");
  // Which phase dominates where — the same label can be 1% at one end
  // of the ladder and 50% at the other.
  const labels = new Set();
  for (const s of summary) for (const r of s.rows) labels.add(r.label);
  console.log("  phase share by target (%)\n");
  const header = summary.map((s) => s.name.slice(0, 12).padStart(13)).join("");
  console.log(`    ${"phase".padEnd(30)}${header}`);
  for (const label of labels) {
    const cells = summary
      .map((s) => {
        const row = s.rows.find((r) => r.label === label);
        return (row ? row.share.toFixed(1) : "-").padStart(13);
      })
      .join("");
    console.log(`    ${label.slice(0, 30).padEnd(30)}${cells}`);
  }
}
