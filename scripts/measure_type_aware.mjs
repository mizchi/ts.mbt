// What does the type information actually buy?
//
// `verify_real_world_minify.mjs` asks whether real packages still behave
// after minification. This asks a different question, and it is the one
// the type-aware passes exist to answer: on real code, how many bytes
// does knowing the types save?
//
// The measurement has to start from SOURCE. Six phases in
// `bundle.mbt` — predicate-inline, switch-fold, as-const-inline,
// tag-rewrite, class-method-dce and type-fold — read
// `combined_type_aliases` / `combined_interfaces` / `combined_class_fields`,
// which the bundler fills from the parsed TypeScript modules. Hand them
// a published `.js` and every one of those tables is empty, so not one
// of the six can fire. A published bundle therefore cannot measure them
// even in principle: the answer would be zero by construction.
//
// So each target is optimized twice, with IDENTICAL flags, differing
// only in the form of the input:
//
//   unopt   mtsc <entry.ts> --bundle
//           TypeScript in, plain JS out, no optimization. The size
//           denominator, and the behavioural reference.
//   aware   mtsc <entry.ts> --bundle --treeshake --fold --minify --mangle
//           the annotations are present, so the six phases can fire.
//   blind   mtsc <unopt.mjs> --bundle --treeshake --fold --minify --mangle
//           the same code with the types erased. Every type table is
//           empty. This is the published-.js situation.
//
//   delta = blind - aware      positive means type information paid.
//
// `--no-check` is on for every leg. It only skips DIAGNOSTICS: a real
// library does not type-check clean under a subset checker, and the type
// tables the six phases read come from the parse, not from the check. So
// the legs differ in exactly one variable.
//
// One artifact has to be controlled for. `blind`'s input has already
// been through one emit, so `blind` gets a second optimization pass that
// `aware` does not, and a second pass finds things the first missed —
// nothing to do with types. The `aware2` leg re-optimizes `aware`'s own
// output to price that in; the report subtracts it, and `--verbose`
// shows both numbers.
//
// A target is only trusted when all three legs produce identical
// observations against its driver. A target whose bundle does not run at
// all is reported `size-only` with the reason, because a byte count
// nobody can execute is not evidence.
//
//   node scripts/measure_type_aware.mjs
//   node scripts/measure_type_aware.mjs --only hono --verbose
//   node scripts/measure_type_aware.mjs --update      # re-record expected.json
//   node scripts/measure_type_aware.mjs --keep        # keep the leg outputs

import { spawnSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const WORK = path.join(ROOT, "_build", "type-aware");
const FIXTURES = path.join(ROOT, "fixtures", "type-aware-corpus");
const EXPECTED = path.join(FIXTURES, "expected.json");

// Flags shared by `aware` and `blind`. Deliberately WITHOUT
// `--mangle-properties`: on every library measured here the property
// mangler is inert (the fail-closed callee-provenance scan finds calls
// it cannot prove bundle-internal, so it reserves everything), which
// means adding it changes no byte on either leg and only lengthens the
// run. `docs/type-aware-measurement.md` records that result.
const OPT_FLAGS = ["--treeshake", "--fold", "--minify", "--mangle"];

// The corpus. `entry` is relative to the checkout root.
//
// `reuse` lets a target adopt a checkout `verify_real_world_minify.mjs`
// already made, so the two harnesses share one clone instead of two.
//
// A `blocked` target is one this pipeline cannot consume today. It stays
// in the table on purpose: the reason is the finding, and the entry
// becomes a measurement the day the reason goes away.
const CORPUS = [
  {
    name: "hono",
    repo: "https://github.com/honojs/hono",
    entry: "src/index.ts",
    reuse: ["_build/real-world/hono/hono"],
    driver: "hono.driver.mjs",
  },
  {
    name: "valibot",
    repo: "https://github.com/fabian-hiller/valibot",
    entry: "library/src/index.ts",
    reuse: ["_build/real-world/valibot/valibot"],
    driver: "valibot.driver.mjs",
  },
  {
    name: "typebox",
    repo: "https://github.com/sinclairzx81/typebox",
    entry: "src/index.ts",
    // The `TTypeArray is not defined` failure this row used to carry was
    // the type-only namespace entry, and it is fixed. typebox now gets
    // further and stops on a different bug: `Cannot access 'IntegerKey'
    // before initialization` — a `const` used by a later top-level
    // statement that the linker ordered ahead of its declaration. A TDZ
    // ordering problem, unrelated to types, and its own fix.
    //
    // Sizes stay comparable (both legs carry the same defect), but
    // nothing executes them, so the row is size-only.
    driver: null,
    sizeOnlyWhy: "bundle throws on load: TDZ, `IntegerKey` used before its declaration is ordered",
  },
  {
    name: "immer",
    repo: "https://github.com/immerjs/immer",
    entry: "src/immer.ts",
    // Same shape of problem, different cause: `export const enum
    // ArchType` is referenced across module boundaries but never
    // emitted or inlined, so the bundle throws `ArchType is not
    // defined`.
    driver: null,
    sizeOnlyWhy: "bundle throws on load: cross-module `const enum ArchType` neither emitted nor inlined",
  },
  // These two were BLOCKED by the export-surface blowup that
  // `surface_should_walk` in `export_surface.mbt` now bounds:
  // neverthrow went from not finishing in 420s to under a second.
  // `ts-pattern` is the corpus's only exhaustive-match-over-a-
  // discriminated-union target, which is the shape `tag-rewrite` and
  // `switch-fold` are built for, so it is the most interesting row here.
  {
    name: "neverthrow",
    repo: "https://github.com/supermacro/neverthrow",
    entry: "src/index.ts",
    driver: "neverthrow.driver.mjs",
  },
  {
    name: "ts-pattern",
    repo: "https://github.com/gvergnaud/ts-pattern",
    entry: "src/index.ts",
    driver: "ts-pattern.driver.mjs",
  },
  {
    name: "superstruct",
    repo: "https://github.com/ianstormtaylor/superstruct",
    entry: "src/index.ts",
    // Reports BROKEN, and the row is left red on purpose: it is the
    // first real-world behavioural difference this corpus has found.
    // `error.ts:44` does `this.name = this.constructor.name`, `--mangle`
    // renames the class, and `e.name` comes back `"a"` instead of
    // `"StructError"`. Two classes reproduce it:
    //
    //   class MyError extends TypeError {}
    //   [MyError.name, new MyError().constructor.name]
    //     -> ["MyError","MyError"] plain, ["a","a"] mangled
    //
    // Whether that is a BUG is a policy call rather than a fact.
    // `Function.prototype.name` is observable, so by this repo's own
    // standard — any observable difference is a violation — it is one.
    // But terser and esbuild both rename class names by default
    // (`keep_classnames: false`) and expect a library that reads `.name`
    // to opt out, so matching them is defensible too. A type-aware
    // minifier could do better than either: a `.name` read on a class,
    // or a `this.constructor.name`, is visible in the source and could
    // reserve just that one name.
    driver: "superstruct.driver.mjs",
  },
  // zod and superstruct were both BLOCKED, and both were blamed on the
  // wrong thing twice: first on the export-surface blowup, then — after
  // one gdb sample landed in `parse_conditional_type_tail` — on a parser
  // blowup over recursive conditional types. Neither was it. Both write
  // `.js`-suffixed relative specifiers, which the module-graph walk
  // failed to recognise as already-loaded, so it re-read and re-parsed
  // every repeat visit and re-pushed its imports: 2^depth on a diamond
  // graph. The sample landed in the parser because the parser was being
  // re-entered exponentially. With the dedup guard in
  // `mtsc_load_bundle_files`, zod went from not finishing in eighteen
  // minutes to 227 ms and superstruct to 15 ms. `just verify-graph-walk`
  // is the gate.
  {
    name: "zod",
    repo: "https://github.com/colinhacks/zod",
    entry: "packages/zod/src/index.ts",
    // Took four fixes to get here from BLOCKED, and it found every one:
    // the module-graph dedup (18 min -> 230 ms), the arrow body's parens
    // through an erased `as`, the type-only namespace entries, and the
    // merged interface-and-function case.
    driver: "zod.driver.mjs",
  },
  {
    name: "remeda",
    repo: "https://github.com/remeda/remeda",
    entry: "packages/remeda/src/index.ts",
    blocked: 'parse error in setPath.ts: Expected Semicolon, got Extends',
  },
];

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
let only = null;
let verbose = false;
let keep = false;
let update = false;
let legTimeout = 600_000;
for (let i = 0; i < args.length; i++) {
  const a = args[i];
  if (a === "--only") only = args[++i];
  else if (a === "--verbose" || a === "-v") verbose = true;
  else if (a === "--keep") keep = true;
  else if (a === "--update") update = true;
  else if (a === "--timeout") legTimeout = Number(args[++i]) * 1000;
  else {
    console.error(`unknown argument: ${a}`);
    process.exit(2);
  }
}

const MTSC = findMtsc();
fs.mkdirSync(WORK, { recursive: true });

function bytes(n) {
  return n.toLocaleString("en-US");
}

function pct(part, whole) {
  if (!whole) return "0.00%";
  return `${((part * 100) / whole).toFixed(2)}%`;
}

// One optimization leg. A timeout is a result, not a crash: the
// blocked targets are blocked precisely because they never come back,
// and the report has to be able to say so.
function compile(input, output, flags, cwd) {
  const started = process.hrtime.bigint();
  const r = spawnSync(MTSC, [input, "--no-check", ...flags, "--out", output], {
    encoding: "utf8",
    maxBuffer: 1 << 28,
    timeout: legTimeout,
    killSignal: "SIGKILL",
    cwd,
  });
  const seconds = Number(process.hrtime.bigint() - started) / 1e9;
  if (r.signal === "SIGKILL" || r.error?.code === "ETIMEDOUT") {
    return { ok: false, seconds, why: `no completion in ${Math.round(legTimeout / 1000)}s` };
  }
  if (r.status !== 0 || !fs.existsSync(output) || fs.statSync(output).size === 0) {
    const line = (r.stdout || "").split("\n").find((l) => /parse error|error/i.test(l));
    return { ok: false, seconds, why: (line || `exit ${r.status}`).trim().slice(0, 120) };
  }
  return { ok: true, seconds, size: fs.statSync(output).size };
}

// Run one leg's output through the target's driver and return its
// stdout, or null with a reason.
//
// The driver is copied next to the bundle rather than run from
// `fixtures/`: it imports `./target.mjs`, and a bare specifier resolves
// against the importing FILE, not the working directory.
function observe(dir, driverSrc, leg) {
  const driver = path.join(dir, "driver.mjs");
  fs.copyFileSync(driverSrc, driver);
  fs.copyFileSync(path.join(dir, `${leg}.mjs`), path.join(dir, "target.mjs"));
  const r = spawnSync("node", [driver], {
    encoding: "utf8",
    maxBuffer: 1 << 28,
    timeout: 180_000,
    cwd: dir,
  });
  if (r.status !== 0) {
    return { ok: false, why: (r.stderr || "").split("\n").find((l) => l.trim()) || `exit ${r.status}` };
  }
  return { ok: true, out: r.stdout };
}

function resolveCheckout(t) {
  for (const cand of t.reuse ?? []) {
    const p = path.join(ROOT, cand);
    if (fs.existsSync(path.join(p, t.entry))) return { dir: p, cloned: false };
  }
  const dir = path.join(WORK, t.name, t.name);
  if (fs.existsSync(path.join(dir, t.entry))) return { dir, cloned: false };
  fs.mkdirSync(path.dirname(dir), { recursive: true });
  const r = spawnSync("git", ["clone", "--depth", "1", "--quiet", t.repo, dir], {
    encoding: "utf8",
    timeout: 900_000,
  });
  if (r.status !== 0) return { dir: null, why: "git clone failed (needs network)" };
  if (!fs.existsSync(path.join(dir, t.entry))) {
    return { dir: null, why: `entry ${t.entry} not found in the checkout` };
  }
  return { dir, cloned: true };
}

function countSources(checkout, entry) {
  const srcRoot = path.join(checkout, path.dirname(entry));
  const r = spawnSync(
    "bash",
    ["-c", `find ${JSON.stringify(srcRoot)} -name '*.ts' ! -name '*.test.ts' ! -name '*.spec.ts' | wc -l`],
    { encoding: "utf8", timeout: 60_000 },
  );
  return Number((r.stdout || "0").trim()) || 0;
}

const results = [];

function measure(t) {
  if (t.blocked) {
    results.push({ name: t.name, status: "blocked", why: t.blocked });
    return;
  }
  const { dir: checkout, why } = resolveCheckout(t);
  if (!checkout) {
    results.push({ name: t.name, status: "skip", why });
    return;
  }
  const dir = path.join(WORK, t.name);
  fs.mkdirSync(dir, { recursive: true });
  const entry = path.join(checkout, t.entry);
  const files = countSources(checkout, t.entry);

  const unopt = compile(entry, path.join(dir, "unopt.mjs"), ["--bundle"], dir);
  if (!unopt.ok) {
    results.push({ name: t.name, status: "blocked", why: `unopt leg: ${unopt.why}` });
    return;
  }
  const aware = compile(entry, path.join(dir, "aware.mjs"), ["--bundle", ...OPT_FLAGS], dir);
  if (!aware.ok) {
    results.push({ name: t.name, status: "blocked", why: `aware leg: ${aware.why}` });
    return;
  }
  const blind = compile(path.join(dir, "unopt.mjs"), path.join(dir, "blind.mjs"), ["--bundle", ...OPT_FLAGS], dir);
  if (!blind.ok) {
    results.push({ name: t.name, status: "blocked", why: `blind leg: ${blind.why}` });
    return;
  }
  // The double-pass control: what a second optimization of `aware`'s own
  // output finds, which `blind` gets for free and types have nothing to
  // do with.
  const aware2 = compile(path.join(dir, "aware.mjs"), path.join(dir, "aware2.mjs"), ["--bundle", ...OPT_FLAGS], dir);

  const delta = blind.size - aware.size;
  const secondPass = aware2.ok ? aware.size - aware2.size : null;
  // The part of the gap that is not explained by the extra pass.
  const adjusted = secondPass === null ? null : delta + secondPass;

  const row = {
    name: t.name,
    status: t.driver ? "measured" : "size-only",
    why: t.sizeOnlyWhy,
    files,
    unopt: unopt.size,
    aware: aware.size,
    blind: blind.size,
    delta,
    secondPass,
    adjusted,
    seconds: aware.seconds,
  };

  if (t.driver) {
    const driverSrc = path.join(FIXTURES, t.driver);
    const ref = observe(dir, driverSrc, "unopt");
    if (!ref.ok) {
      row.status = "size-only";
      row.why = `unoptimized bundle does not run: ${ref.why}`;
    } else {
      for (const leg of ["aware", "blind"]) {
        const got = observe(dir, driverSrc, leg);
        if (!got.ok) {
          row.status = "broken";
          row.why = `${leg} does not run: ${got.why}`;
          break;
        }
        if (got.out !== ref.out) {
          fs.writeFileSync(path.join(dir, `${leg}.observed`), got.out);
          fs.writeFileSync(path.join(dir, "reference.observed"), ref.out);
          row.status = "broken";
          row.why = `${leg} observations differ (see _build/type-aware/${t.name}/{reference,${leg}}.observed)`;
          break;
        }
      }
    }
    fs.rmSync(path.join(dir, "target.mjs"), { force: true });
    fs.rmSync(path.join(dir, "driver.mjs"), { force: true });
  }

  results.push(row);
  if (!keep) {
    for (const f of ["aware2.mjs"]) fs.rmSync(path.join(dir, f), { force: true });
  }
}

for (const t of CORPUS) {
  if (only && t.name !== only) continue;
  measure(t);
}

// ---------------------------------------------------------------------
// Report
// ---------------------------------------------------------------------

function verdictOf(row) {
  if (row.status === "blocked" || row.status === "skip") return "-";
  if (row.status === "broken") return "BROKEN";
  // A win has to clear noise: a handful of bytes on a 90 KB bundle is
  // not a result, it is whitespace luck.
  const floor = Math.max(64, Math.round(row.aware * 0.001));
  if (row.delta > floor) return "WIN";
  if (row.delta < -floor) return "LOSS";
  return "NEUTRAL";
}

console.log("\ntype-aware minify measurement");
console.log("  optimizing TypeScript SOURCE vs the same code with types erased\n");

const pad = (s, n) => String(s).padEnd(n);
const padl = (s, n) => String(s).padStart(n);

console.log(
  `  ${pad("target", 12)} ${padl("files", 5)} ${padl("unopt", 10)} ${padl("aware", 9)} ${padl("blind", 9)} ${padl("delta", 8)} ${padl("of aware", 9)}  verdict`,
);
for (const row of results) {
  if (row.status === "blocked" || row.status === "skip") {
    console.log(`  ${pad(row.name, 12)} ${padl("-", 5)} ${padl("-", 10)} ${padl("-", 9)} ${padl("-", 9)} ${padl("-", 8)} ${padl("-", 9)}  ${row.status === "skip" ? "SKIP" : "BLOCKED"}`);
    continue;
  }
  console.log(
    `  ${pad(row.name, 12)} ${padl(row.files, 5)} ${padl(bytes(row.unopt), 10)} ${padl(bytes(row.aware), 9)} ${padl(bytes(row.blind), 9)} ` +
      `${padl((row.delta > 0 ? "+" : "") + bytes(row.delta), 8)} ${padl(pct(row.delta, row.aware), 9)}  ${verdictOf(row)}`,
  );
}

for (const row of results) {
  if (row.status === "blocked") console.log(`\n  ${row.name}: BLOCKED — ${row.why}`);
  else if (row.status === "skip") console.log(`\n  ${row.name}: skipped — ${row.why}`);
  else if (row.status === "broken") console.log(`\n  ${row.name}: BROKEN — ${row.why}`);
  else if (row.status === "size-only") console.log(`\n  ${row.name}: size-only — ${row.why}`);
}

if (verbose) {
  console.log("\n  double-pass control (how much of the gap is just the extra pass):\n");
  for (const row of results) {
    if (row.secondPass == null) continue;
    console.log(
      `    ${pad(row.name, 12)} second pass on aware: ${padl(bytes(row.secondPass), 7)} bytes  ` +
        `→ type-attributable delta ${padl((row.adjusted > 0 ? "+" : "") + bytes(row.adjusted), 8)}`,
    );
  }
}

const measured = results.filter((r) => r.status === "measured" || r.status === "size-only");
const wins = measured.filter((r) => verdictOf(r) === "WIN");
const losses = measured.filter((r) => verdictOf(r) === "LOSS");
const neutral = measured.filter((r) => verdictOf(r) === "NEUTRAL");
const broken = results.filter((r) => r.status === "broken");
const blocked = results.filter((r) => r.status === "blocked");

console.log(
  `\n  ${measured.length} measured: ${wins.length} win, ${neutral.length} neutral, ${losses.length} loss` +
    `; ${broken.length} broken, ${blocked.length} blocked\n`,
);

// ---------------------------------------------------------------------
// Regression gate
// ---------------------------------------------------------------------
//
// The absolute byte counts move with every change to the emitter, so
// pinning them would fail on every commit. What is pinned is the
// VERDICT per target plus the delta, with a tolerance: a target may not
// silently go from WIN to NEUTRAL, and a win may not quietly erode.

const snapshot = {};
for (const row of results) {
  snapshot[row.name] =
    row.status === "blocked" || row.status === "skip"
      ? { status: row.status }
      : { status: row.status, verdict: verdictOf(row), delta: row.delta, aware: row.aware };
}

if (update) {
  fs.mkdirSync(FIXTURES, { recursive: true });
  fs.writeFileSync(EXPECTED, JSON.stringify(snapshot, null, 2) + "\n");
  console.log(`  recorded ${path.relative(ROOT, EXPECTED)}\n`);
  process.exit(0);
}

if (!fs.existsSync(EXPECTED)) {
  console.log(`  no ${path.relative(ROOT, EXPECTED)} yet — run with --update to record one\n`);
  process.exit(broken.length ? 1 : 0);
}

const want = JSON.parse(fs.readFileSync(EXPECTED, "utf8"));
const regressions = [];
for (const [name, exp] of Object.entries(want)) {
  if (only && name !== only) continue;
  const got = snapshot[name];
  if (!got) {
    regressions.push(`${name}: expected but not measured`);
    continue;
  }
  if (exp.status !== got.status) {
    regressions.push(`${name}: status ${exp.status} -> ${got.status}`);
    continue;
  }
  if (exp.verdict === undefined) continue;
  if (exp.verdict !== got.verdict) {
    regressions.push(`${name}: verdict ${exp.verdict} -> ${got.verdict}`);
    continue;
  }
  const tolerance = Math.max(64, Math.round((exp.aware ?? 0) * 0.005));
  if (got.delta < exp.delta - tolerance) {
    regressions.push(
      `${name}: type-aware delta eroded ${bytes(exp.delta)} -> ${bytes(got.delta)} bytes (tolerance ${tolerance})`,
    );
  }
}

if (broken.length) {
  for (const r of broken) console.error(`  BROKEN ${r.name}: ${r.why}`);
}
if (regressions.length) {
  console.error("  regressions against fixtures/type-aware-corpus/expected.json:");
  for (const r of regressions) console.error(`    ${r}`);
}
if (broken.length || regressions.length) {
  console.error("");
  process.exit(1);
}
console.log("  no regression against the recorded measurement\n");
