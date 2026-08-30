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
// a self-comparison.
//
// CLOSED by a second phase below: `fixtures/pass-lattice/lowerings.ts`
// runs the same fifteen combinations over a file that contains one of
// each TypeScript-only lowering — `#private` fields (instance and
// static), parameter properties, accessors, `enum`, `const enum`,
// `namespace`, abstract/override — and observes VALUES rather than
// stdout: own keys, `JSON.stringify`, object spread and `for…in`, which
// is what a leaked brand or a dropped field actually changes. Its
// baseline is Node running the TypeScript directly through
// `--experimental-transform-types`, so the reference is the language and
// not another mtsc output.
//
// It is deliberately NOT a real library. The 9 MB target covers "a shape
// nobody thought of"; what was missing was the lowerings and a question
// the answer can reach, and a purpose-built file covers every lowering
// in one cheap compile instead of whichever ones a given library
// happens to use.
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

// ---------------------------------------------------------------------
// Phase 2: the TypeScript-only lowerings, observed by value.
// ---------------------------------------------------------------------
//
// See the header. Same fifteen combinations, a different input and a
// different question.
const LOWERINGS = path.join(ROOT, "fixtures/pass-lattice/lowerings.ts");
const LOWDIR = path.join(OUTDIR, "lowerings");

function observeReport(mod) {
  // The driver is written to disk next to the bundle so a relative
  // import resolves; printing a stable JSON of `report` is the whole
  // observation.
  const drv = path.join(path.dirname(mod), `drive-${path.basename(mod)}`);
  fs.writeFileSync(
    drv,
    `const m = await import("./${path.basename(mod)}");\n` +
      `console.log(JSON.stringify(m.report, Object.keys(m.report).sort()));\n`,
  );
  const r = spawnSync("node", [drv], { encoding: "utf8", maxBuffer: 1 << 26 });
  fs.rmSync(drv, { force: true });
  if (r.status !== 0) return { ok: false, why: shortError(r.stderr || "") };
  return { ok: true, out: r.stdout };
}

console.log("\n  TypeScript-only lowerings, observed by value\n");
fs.mkdirSync(LOWDIR, { recursive: true });

// The baseline is the LANGUAGE: Node running the TypeScript directly.
const refDrv = path.join(LOWDIR, "reference.mjs");
fs.writeFileSync(
  refDrv,
  `const m = await import(${JSON.stringify(LOWERINGS)});\n` +
    `console.log(JSON.stringify(m.report, Object.keys(m.report).sort()));\n`,
);
const refRun = spawnSync("node", ["--experimental-transform-types", refDrv], {
  encoding: "utf8",
  maxBuffer: 1 << 26,
});
fs.rmSync(refDrv, { force: true });
if (refRun.status !== 0) {
  console.error(`  reference leg failed: ${shortError(refRun.stderr || "")}`);
  process.exit(2);
}
const refOut = refRun.stdout;

let lowFailures = 0;
for (const v of chosen) {
  const out = path.join(LOWDIR, `${v.name}.mjs`);
  const c = spawnSync(MTSC, [LOWERINGS, "--no-check", ...v.flags, "--out", out], {
    encoding: "utf8",
    timeout: 300_000,
  });
  if (c.status !== 0 || !fs.existsSync(out) || fs.statSync(out).size === 0) {
    console.log(`  [FAIL] ${v.name.padEnd(24)} compile failed: exit ${c.status}`);
    lowFailures += 1;
    continue;
  }
  const bytes = fs.statSync(out).size;
  const tag = `${String(bytes).padStart(6)} bytes`;
  const got = observeReport(out);
  if (!got.ok) {
    console.log(`  [FAIL] ${v.name.padEnd(24)} ${tag}  ${got.why}`);
    lowFailures += 1;
  } else if (got.out !== refOut) {
    // Name the fields that moved: with fifteen combinations and
    // twenty-five observations, "differs" is not enough to act on.
    let detail = "observations differ";
    try {
      const a = JSON.parse(refOut);
      const b2 = JSON.parse(got.out);
      const moved = Object.keys(a).filter(
        (k) => JSON.stringify(a[k]) !== JSON.stringify(b2[k]),
      );
      if (moved.length) {
        detail =
          moved
            .slice(0, 3)
            .map((k) => `${k}: ${JSON.stringify(a[k])} -> ${JSON.stringify(b2[k])}`)
            .join("; ") + (moved.length > 3 ? ` (+${moved.length - 3} more)` : "");
      }
    } catch {
      /* keep the generic message */
    }
    console.log(`  [DIFF] ${v.name.padEnd(24)} ${tag}  ${detail}`);
    lowFailures += 1;
  } else {
    console.log(`  [ok  ] ${v.name.padEnd(24)} ${tag}  every lowering observed identically`);
  }
  if (!keep) fs.rmSync(out, { force: true });
}

console.log(
  `\n  ${chosen.length - lowFailures}/${chosen.length} pass-combinations lower TypeScript identically`,
);
failures += lowFailures;

if (failures > 0) {
  console.error(
    `\n  ${failures} combination(s) failed.\n` +
      "  The pattern names the pass: a combination that fails while each of\n" +
      "  its parts passes is an interaction between them. A failure in the\n" +
      "  first table miscompiles the TypeScript compiler; one in the second\n" +
      "  gets a TypeScript-only lowering wrong, and the named fields say\n" +
      "  which — a `__private_brand__` in `counterKeys` is the brand leak,\n" +
      "  a changed `levelObjectKeys` is the enum, and so on.",
  );
  process.exit(1);
}
