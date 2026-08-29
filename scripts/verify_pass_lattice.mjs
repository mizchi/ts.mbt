// Every combination of optimization passes, on the biggest real input
// we have.
//
// `verify_real_world_minify.mjs` runs ONE flag set per target. That is
// the shipping configuration, and it is the right thing to check — but
// when it fails, "the pipeline is broken" is all you learn. Running the
// whole lattice instead tells you which pass, because the pattern of
// which combinations fail is the answer:
//
//   minify              ok
//   fold                ok
//   fold+minify         FAIL      <- an interaction, not one pass
//
// That is how the binder bug was found: `minify` alone left
// `let symbol = declareSymbolAndAddToSymbolTable(...)` where it was,
// and `fold` rewrote the statement after it into a shape that made the
// single-use inliner move the call into a `?:` branch that is not taken.
//
// The target is `lib/typescript.js`, 9 MB of published UMD bundle, run
// as a compiler afterwards: it compiles a TypeScript file and the
// diagnostics, the transpiled output, the resolved types and the shape
// of the public API all have to match the pristine copy. A minifier
// that gets 16 of these right and one wrong has a bug that a corpus
// will not find.
//
// Usage:
//   node scripts/verify_pass_lattice.mjs [--only <name>] [--reuse]

import { spawn, spawnSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";

const ROOT = "/home/user/ts.mbt";
const MTSC = path.join(ROOT, "_build/native/release/build/cmd/mtsc/mtsc.exe");
const LIB = path.join(ROOT, "_build/real-world/typescript/node_modules/typescript/lib");
const APP = path.join(ROOT, "_build/real-world/typescript/tsapp.cjs");
const OUTDIR = path.join(ROOT, "_build/tsbisect");

const VARIANTS = [
// A gap worth knowing about, because this harness looks like it should
// have caught the private-field leak and did not.
//
// `lower_private_fields` ran only in the merged pipeline, so bare
// `--bundle` — the FIRST combination below — emitted mtsc's internal
// `__private_brand__N__x` verbatim, and a brand is an ordinary own
// enumerable property, visible to `JSON.stringify` / `Object.keys` /
// spread / `for-in`. This lattice ran that combination on every run and
// reported "behave identically" every time, for two independent reasons:
//
//   1. The target is a PUBLISHED `.js` bundle. `typescript.js` has no
//      `#private` fields, no enums, no namespaces, no parameter
//      properties — so no TypeScript-only lowering is exercised at all,
//      and there was nothing to leak.
//   2. Even with such a field present, the only observation is whether
//      `tsc`'s stdout matches. An extra enumerable property on an
//      internal object does not reach stdout, so the question could not
//      see the answer.
//
// The reference leg is genuinely independent (the baseline is the
// ORIGINAL `typescript.js`), which makes this a coverage gap rather than
// a self-comparison. Closing it wants a second target compiled from
// TypeScript SOURCE — the `_build/type-aware` clones are already on disk
// — and an observation that inspects the values, not just stdout.
  { name: "bundle", flags: ["--bundle"] },
  { name: "treeshake", flags: ["--bundle", "--treeshake"] },
  { name: "fold", flags: ["--bundle", "--fold"] },
  { name: "minify", flags: ["--bundle", "--minify"] },
  { name: "mangle", flags: ["--bundle", "--mangle"] },
  { name: "minify+mangle", flags: ["--bundle", "--minify", "--mangle"] },
  { name: "fold+minify", flags: ["--bundle", "--fold", "--minify"] },
  { name: "fold+mangle", flags: ["--bundle", "--fold", "--mangle"] },
  { name: "treeshake+minify", flags: ["--bundle", "--treeshake", "--minify"] },
  { name: "treeshake+mangle", flags: ["--bundle", "--treeshake", "--mangle"] },
  { name: "fold+minify+mangle", flags: ["--bundle", "--fold", "--minify", "--mangle"] },
  { name: "treeshake+minify+mangle", flags: ["--bundle", "--treeshake", "--minify", "--mangle"] },
  { name: "treeshake+fold+minify", flags: ["--bundle", "--treeshake", "--fold", "--minify"] },
  { name: "treeshake+fold+mangle", flags: ["--bundle", "--treeshake", "--fold", "--mangle"] },
  { name: "all", flags: ["--bundle", "--treeshake", "--fold", "--minify", "--mangle"] },
];

const only = process.argv.includes("--only")
  ? process.argv[process.argv.indexOf("--only") + 1]
  : null;
const reuse = process.argv.includes("--reuse");
const keep = process.argv.includes("--keep");

function compile(v) {
  // Output must live in the package's lib/ so TypeScript finds lib.*.d.ts.
  const out = path.join(LIB, `bisect-${v.name}.js`);
  if (reuse && fs.existsSync(out) && fs.statSync(out).size > 0) {
    return Promise.resolve({ v, out, ok: true, seconds: 0, cached: true });
  }
  const started = Date.now();
  return new Promise((resolve) => {
    const p = spawn(MTSC, [path.join(LIB, "typescript.js"), "--no-check", ...v.flags, "--out", out], {
      stdio: ["ignore", "ignore", "pipe"],
    });
    let err = "";
    p.stderr.on("data", (d) => (err += d));
    p.on("close", (code) => {
      const seconds = (Date.now() - started) / 1000;
      const ok = code === 0 && fs.existsSync(out) && fs.statSync(out).size > 0;
      resolve({ v, out, ok, seconds, why: ok ? null : `exit ${code} ${err.slice(0, 200)}` });
    });
  });
}

function shortError(stderr) {
  const lines = stderr.split("\n").filter((l) => l.length > 0 && l.length < 300);
  const err = lines.find((l) => /Error[:\s]/.test(l));
  const at = lines.find((l) => /^\s+at /.test(l));
  const tail = lines.slice(-3).join(" | ");
  return [err, at].filter(Boolean).join("  ") || tail;
}

const baseline = spawnSync("node", [APP, path.join(LIB, "typescript.js")], {
  cwd: path.dirname(APP),
  encoding: "utf8",
  maxBuffer: 1 << 28,
});
if (baseline.status !== 0) {
  console.error("pristine run failed");
  process.exit(2);
}

const chosen = only ? VARIANTS.filter((v) => v.name === only) : VARIANTS;
const built = [];
// Two at a time: the compile is memory-hungry on a 9 MB input.
for (let i = 0; i < chosen.length; i += 2) {
  built.push(...(await Promise.all(chosen.slice(i, i + 2).map(compile))));
}

let failures = 0;
for (const b of built) {
  if (!b.ok) {
    console.log(`  [FAIL] ${b.v.name.padEnd(24)} compile failed: ${b.why}`);
    failures += 1;
    continue;
  }
  const check = spawnSync("node", ["--check", b.out], { encoding: "utf8" });
  if (check.status !== 0) {
    console.log(
      `  [FAIL] ${b.v.name.padEnd(24)} unparseable: ${(check.stderr || "").match(/SyntaxError.*/)?.[0]}`,
    );
    failures += 1;
    continue;
  }
  const got = spawnSync("node", [APP, b.out], {
    cwd: path.dirname(APP),
    encoding: "utf8",
    maxBuffer: 1 << 28,
  });
  const bytes = fs.statSync(b.out).size;
  const tag = `${String(bytes).padStart(9)} bytes ${b.cached ? "(cached)" : `${b.seconds.toFixed(0)}s`}`;
  if (got.status !== 0) {
    console.log(`  [FAIL] ${b.v.name.padEnd(24)} ${tag}  ${shortError(got.stderr || "")}`);
    failures += 1;
  } else if (got.stdout !== baseline.stdout) {
    console.log(`  [DIFF] ${b.v.name.padEnd(24)} ${tag}  runs but diagnostics differ`);
    failures += 1;
  } else {
    console.log(`  [ok  ] ${b.v.name.padEnd(24)} ${tag}  compiles TypeScript identically`);
  }
}

console.log(`\n  ${built.length - failures}/${built.length} pass-combinations behave identically`);

if (!keep) {
  for (const b of built) fs.rmSync(b.out, { force: true });
}

if (failures > 0) {
  console.error(
    `\n  ${failures} combination(s) miscompile the TypeScript compiler.\n` +
      "  The pattern names the pass: a combination that fails while each of\n" +
      "  its parts passes is an interaction between them.",
  );
  process.exit(1);
}
