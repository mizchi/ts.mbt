// Semantic fuzzer for `mtsc --mangle-properties`.
//
// Why this exists. The mangle-safety corpus (`fixtures/mangle-safety`,
// `scripts/verify_mangle_safety.mjs`) proves the analysis handles the
// situations somebody thought of, and the real-world harness
// (`scripts/verify_real_world_minify.mjs`) proves it handles five
// published packages. Neither can find the case nobody imagined. A
// property mangler that is wrong in a way no fixture covers fails
// SILENTLY: the bundle runs, the tests pass, and one `JSON.stringify`
// somewhere returns `{"a":1}` where it used to return `{"count":1}`.
//
// So: generate programs nobody wrote, compile each one twice — once with
// mangling and once without — run both, and compare what they observed.
// A difference is a mangler false positive, by construction: the two
// bundles came from the same source and differ only in whether names
// were renamed.
//
// The shape is Terser's `ufuzz` by way of
// https://github.com/oxc-project/oxc/pull/25594 — deterministic seeds,
// bounded loops, a shared call budget, tagged value encoding, batched
// execution in isolated contexts. Two things are different here:
//
//   * the generator emits a tree, not source text, and the campaign
//     SHRINKS a failing tree automatically (`scripts/lib/fuzz-shrink.mjs`).
//     The upstream fuzzer's artifact is a seed and a hundred-line
//     program; this one's is the smallest program it could still fail on.
//   * the grammar aims at the property mangler's proof obligations —
//     computed-key reads, spread, `Object.keys`, `for...in`,
//     `#private` fields, prototype methods — rather than at arithmetic
//     folding. Compression bugs are still reachable with `--no-mangle`.
//
// Usage:
//   node scripts/fuzz_mangle.mjs [--seed N] [--iterations N]
//                                [--shape sink|export|both]
//                                [--no-mangle] [--no-shrink]
//                                [--shrink-steps N] [--keep-going N]
//                                [--timeout-ms N] [--batch-size N]
//                                [--save-dir PATH] [--quiet]
//
// Exit status is non-zero on any mismatch, so it can gate CI once the
// campaign is quiet at a size worth committing to.

import { spawnSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

import { printProgram, size } from "./lib/fuzz-ir.mjs";
import { generate } from "./lib/fuzz-generate.mjs";
import { shrink } from "./lib/fuzz-shrink.mjs";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const RUNNER = path.join(ROOT, "scripts", "lib", "fuzz-runner.mjs");

const MTSC_CANDIDATES = [
  path.join(ROOT, "_build", "native", "release", "build", "cmd", "mtsc", "mtsc.exe"),
  path.join(ROOT, "_build", "native", "debug", "build", "cmd", "mtsc", "mtsc.exe"),
];

function findMtsc() {
  for (const candidate of MTSC_CANDIDATES) if (fs.existsSync(candidate)) return candidate;
  console.error("fuzz_mangle: mtsc binary not found. Run `moon build --target native` first.");
  process.exit(2);
}

// ---------------------------------------------------------------
// Options
// ---------------------------------------------------------------

const options = {
  startSeed: 0,
  iterations: 200,
  shape: "both",
  mangle: true,
  shrinkFailures: true,
  shrinkSteps: 400,
  keepGoing: 1,
  timeoutMs: 1000,
  batchSize: 40,
  saveDir: path.join(ROOT, "_build", "fuzz-mangle"),
  quiet: false,
};

const argv = process.argv.slice(2);
for (let i = 0; i < argv.length; i++) {
  const arg = argv[i];
  if (arg === "--seed") options.startSeed = Number(argv[++i]);
  else if (arg === "--iterations") options.iterations = Number(argv[++i]);
  else if (arg === "--shape") options.shape = argv[++i];
  else if (arg === "--no-mangle") options.mangle = false;
  else if (arg === "--no-shrink") options.shrinkFailures = false;
  else if (arg === "--shrink-steps") options.shrinkSteps = Number(argv[++i]);
  else if (arg === "--keep-going") options.keepGoing = Number(argv[++i]);
  else if (arg === "--timeout-ms") options.timeoutMs = Number(argv[++i]);
  else if (arg === "--batch-size") options.batchSize = Number(argv[++i]);
  else if (arg === "--save-dir") options.saveDir = path.resolve(argv[++i]);
  else if (arg === "--quiet") options.quiet = true;
  else if (arg === "--help" || arg === "-h") {
    printHelp();
    process.exit(0);
  } else {
    console.error(`fuzz_mangle: unknown argument ${arg}`);
    process.exit(2);
  }
}

// A campaign that compares nothing must not look like a pass. These are
// the settings that would silently arrange that.
function validateOptions() {
  const problems = [];
  if (!Number.isInteger(options.iterations) || options.iterations < 1) {
    problems.push("--iterations must be a positive integer");
  }
  if (!Number.isInteger(options.startSeed) || options.startSeed < 0) {
    problems.push("--seed must be a non-negative integer");
  }
  // Node's timeout has to be a positive integer. Outside that range
  // `runInNewContext` throws BEFORE evaluating the program, the oracle
  // records it as "the baseline threw", every seed is skipped, and the
  // campaign reports success having compared nothing.
  if (!Number.isInteger(options.timeoutMs) || options.timeoutMs < 1 || options.timeoutMs > 2 ** 31) {
    problems.push("--timeout-ms must be an integer between 1 and 2147483648");
  }
  if (!Number.isInteger(options.batchSize) || options.batchSize < 1) {
    problems.push("--batch-size must be a positive integer");
  }
  if (!["sink", "export", "both"].includes(options.shape)) {
    problems.push("--shape must be sink, export or both");
  }
  if (problems.length > 0) {
    for (const problem of problems) console.error(`fuzz_mangle: ${problem}`);
    process.exit(2);
  }
}

function printHelp() {
  console.log(`fuzz_mangle — semantic fuzzer for mtsc's property mangler

Generates deterministic TypeScript programs, compiles each with and
without mangling, runs both, and compares what they observed. A
difference is a mangler false positive. Failing programs are shrunk
automatically.

Options:
  --seed N            first seed (default 0)
  --iterations N      seeds to check (default 200)
  --shape S           sink | export | both (default both)
                        sink   nothing exported, observation via sinks
                        export module exports observed from outside
  --no-mangle         compare compression only, no renaming
  --no-shrink         report the failing program as generated
  --shrink-steps N    shrink test budget per failure (default 400)
  --keep-going N      collect N failures before stopping (default 1)
  --timeout-ms N      per-program execution timeout (default 1000)
  --batch-size N      programs per Node process (default 40)
  --save-dir PATH     artifacts (default _build/fuzz-mangle)
  --quiet             only print the summary
`);
}

validateOptions();

const MTSC = findMtsc();
const WORK = fs.mkdtempSync(path.join(os.tmpdir(), "fuzz-mangle-"));

// ---------------------------------------------------------------
// Compiling
// ---------------------------------------------------------------
//
// Both sides get the same compression pipeline; the candidate adds the
// two renaming passes. Holding compression constant is what makes a
// mismatch attributable: with `--fold` on one side only, a folding bug
// would be reported as a mangling bug.
//
// `--no-check` is deliberate. The checker has known false positives on
// generated code and its diagnostics are not what is under test here; a
// program the checker rejects would otherwise never reach the mangler.
const COMPRESSION_ARGS = ["--bundle", "--treeshake", "--fold", "--minify", "--no-check"];
const MANGLE_ARGS = ["--mangle", "--mangle-properties", "--reserve-entry-exports"];

function compile(sourcePath, outPath, extraArgs) {
  const result = spawnSync(MTSC, [sourcePath, ...COMPRESSION_ARGS, ...extraArgs, "--out", outPath], {
    encoding: "utf8",
    maxBuffer: 64 * 1024 * 1024,
  });
  if (result.status !== 0 || !fs.existsSync(outPath)) {
    return { ok: false, error: firstLine(result.stdout, result.stderr) };
  }
  return { ok: true, code: fs.readFileSync(outPath, "utf8") };
}

function firstLine(...streams) {
  for (const stream of streams) {
    const line = (stream ?? "")
      .split("\n")
      .map((l) => l.trim())
      .find((l) => l.length > 0);
    if (line) return line;
  }
  return "mtsc produced no output";
}

/// Compile one program both ways. Returns either the two bundles or the
/// compile error, which is reported as a HARNESS problem rather than a
/// mangler bug: a generated program mtsc cannot compile is a generator
/// defect or a parser bug, and either way it is not a false positive.
function compileBoth(program, id) {
  const source = printProgram(program);
  const sourcePath = path.join(WORK, `${id}.ts`);
  fs.writeFileSync(sourcePath, source);
  const baseline = compile(sourcePath, path.join(WORK, `${id}.base.mjs`), []);
  if (!baseline.ok) return { ok: false, stage: "baseline", error: baseline.error, source };
  const candidate = compile(
    sourcePath,
    path.join(WORK, `${id}.cand.mjs`),
    options.mangle ? MANGLE_ARGS : [],
  );
  if (!candidate.ok) return { ok: false, stage: "candidate", error: candidate.error, source };
  return {
    ok: true,
    source,
    sourcePath,
    baseline: baseline.code,
    candidate: candidate.code,
    baselinePath: path.join(WORK, `${id}.base.mjs`),
    candidatePath: path.join(WORK, `${id}.cand.mjs`),
  };
}

// ---------------------------------------------------------------
// Running
// ---------------------------------------------------------------

function runBatch(cases, shape) {
  const request = {
    shape: shape === "export" ? "module" : "script",
    timeoutMs: options.timeoutMs,
    cases: cases.map((entry) =>
      shape === "export"
        ? { baselinePath: entry.baselinePath, candidatePath: entry.candidatePath }
        : { baseline: entry.baseline, candidate: entry.candidate },
    ),
  };
  const result = spawnSync(process.execPath, [RUNNER], {
    input: JSON.stringify(request),
    encoding: "utf8",
    maxBuffer: 256 * 1024 * 1024,
  });
  if (result.status !== 0) {
    return cases.map(() => ({
      verdict: "harness",
      message: firstLine(result.stderr, result.stdout),
    }));
  }
  let outcomes;
  try {
    outcomes = JSON.parse(result.stdout);
  } catch {
    return cases.map(() => ({ verdict: "harness", message: "unparseable runner output" }));
  }
  if (!Array.isArray(outcomes) || outcomes.length !== cases.length) {
    return cases.map(() => ({
      verdict: "harness",
      message: `runner returned ${outcomes?.length} results for ${cases.length} cases`,
    }));
  }
  return outcomes.map(classify);
}

/// Run the original TypeScript through Node's own type stripping. No
/// compiler of ours is involved, so this is the arbiter for "was the
/// generated program ever going to work".
function runReference(sourcePath, kind) {
  const request = {
    shape: "reference",
    timeoutMs: options.timeoutMs,
    cases: [{ baselinePath: sourcePath, kind }],
  };
  const result = spawnSync(process.execPath, [RUNNER], {
    input: JSON.stringify(request),
    encoding: "utf8",
    maxBuffer: 64 * 1024 * 1024,
  });
  if (result.status !== 0) return { status: "threw", name: "HarnessError", message: firstLine(result.stderr) };
  try {
    return JSON.parse(result.stdout)[0].baseline;
  } catch {
    return { status: "threw", name: "HarnessError", message: "unparseable reference output" };
  }
}

/// A baseline that did not complete tells us nothing about mangling, so
/// the seed is skipped rather than counted. A campaign where everything
/// is skipped is a broken generator, and the summary says so.
function classify(pair) {
  if (pair.baseline.status !== "completed") {
    return { verdict: "skipped", baseline: pair.baseline, candidate: pair.candidate };
  }
  const same = JSON.stringify(pair.baseline) === JSON.stringify(pair.candidate);
  return {
    verdict: same ? "equivalent" : "mismatch",
    baseline: pair.baseline,
    candidate: pair.candidate,
  };
}

// ---------------------------------------------------------------
// Shrinking
// ---------------------------------------------------------------

let shrinkProbes = 0;

/// A failure's family. Shrinking is greedy and its acceptance test is
/// "still fails", so without a signature to hold on to, a reduction that
/// starts on a rare bug happily slides onto whichever common one the
/// smaller program happens to trip — and the rare one's repro is lost.
/// The campaign also uses this to avoid shrinking the same bug forty
/// times over.
function signatureOf(outcome, kind) {
  const candidate = outcome.candidate;
  if (candidate?.status !== "completed") {
    // For a broken bundle the throw itself names the bug. Generated
    // identifiers and numbers are stripped so `v4` and `v11` group.
    const message = String(candidate?.message ?? "")
      .replace(/\bv\d+\b/g, "vN")
      .replace(/\bbrake\d+\b/g, "brakeN")
      .replace(/\d+/g, "N");
    return `${kind}:${candidate?.status}:${candidate?.name}:${message}`;
  }
  return `${kind}:diff`;
}

/// Ask the relevant question of one built program.
///
/// For a mangling bug: do baseline and candidate still disagree? For a
/// compression bug: does the original still run where our baseline
/// bundle does not?
function probe(built, shape, kind) {
  if (kind === "compress") {
    const [compiled] = runBatch([built], shape);
    // The baseline completing means the breakage is gone.
    if (compiled.verdict !== "skipped") return { verdict: "equivalent" };
    const reference = runReference(built.sourcePath, shape === "export" ? "module" : "sink");
    if (reference.status !== "completed") return { verdict: "equivalent" };
    return { verdict: "mismatch", baseline: reference, candidate: compiled.baseline };
  }
  return runBatch([built], shape)[0];
}

/// The shrinker's oracle: does this candidate program still fail *the
/// same way*?
function makeStillFails(shape, kind, signature) {
  return (candidate) => {
    shrinkProbes += 1;
    const built = compileBoth(candidate, `shrink-${shrinkProbes}`);
    if (!built.ok) return "invalid";
    const outcome = probe(built, shape, kind);
    if (outcome.verdict === "mismatch") {
      return signatureOf(outcome, kind) === signature ? "fails" : "passes";
    }
    // A harness error is not evidence either way; treating it as
    // "invalid" keeps a flaky probe from ending the reduction.
    return outcome.verdict === "harness" ? "invalid" : "passes";
  };
}

// ---------------------------------------------------------------
// Artifacts
// ---------------------------------------------------------------

function saveFailure(failure) {
  fs.mkdirSync(options.saveDir, { recursive: true });
  const stem = `seed-${failure.seed}-${failure.shape}`;
  const written = [];
  const write = (suffix, content) => {
    const file = path.join(options.saveDir, `${stem}${suffix}`);
    fs.writeFileSync(file, content);
    written.push(file);
  };
  write(".ts", failure.source);
  write(".base.mjs", failure.baseline);
  write(".cand.mjs", failure.candidate);
  // The tree, so a regression test can be built from the reduced case
  // without depending on this generator version reproducing the seed.
  // `nodeCount` is recomputed: the field on the generated program
  // describes the program before shrinking, and this file is after.
  write(
    ".ir.json",
    JSON.stringify({ ...failure.program, nodeCount: size(failure.program) }, null, 2),
  );
  write(
    ".report.json",
    JSON.stringify(
      {
        seed: failure.seed,
        shape: failure.shape,
        mangle: options.mangle,
        compressionArgs: COMPRESSION_ARGS,
        mangleArgs: options.mangle ? MANGLE_ARGS : [],
        shrink: failure.shrink ?? null,
        baseline: failure.outcome.baseline,
        candidate: failure.outcome.candidate,
      },
      null,
      2,
    ),
  );
  return written;
}

/// Shrink a failure, save it, and report it.
///
/// Two kinds, because the harness can catch two different bugs and they
/// need different questions asked of a shrink candidate:
///
///   "mangle"    baseline and candidate differ. The candidate is the
///     only side that renamed anything, so the rename is the cause.
///   "compress"  the ORIGINAL runs under Node and our baseline bundle
///     does not, or observes something else. Mangling is not involved:
///     the shared compression pipeline broke the program.
function recordFailure({ kind, seed, shape, program, entry, outcome }) {
  const failure = {
    kind,
    seed,
    shape,
    program,
    source: entry.source,
    baseline: entry.baseline,
    candidate: entry.candidate,
    outcome,
    signature: signatureOf(outcome, kind),
  };
  // One repro per family is what a person can act on. Later seeds
  // hitting a family already reported are counted and dropped, so a long
  // campaign spends its time on new bugs instead of re-minimizing the
  // most common one.
  const seen = families.get(failure.signature);
  if (seen) {
    seen.count += 1;
    return;
  }
  families.set(failure.signature, { count: 1, seed, kind, shape });

  if (options.shrinkFailures) {
    const before = shrinkProbes;
    const reduced = shrink(program, makeStillFails(shape, kind, failure.signature), {
      maxSteps: options.shrinkSteps,
    });
    const rebuilt = compileBoth(reduced.program, `final-${seed}-${shape}`);
    if (rebuilt.ok) {
      const check = probe(rebuilt, shape, kind);
      if (check.verdict === "mismatch") {
        failure.program = reduced.program;
        failure.source = rebuilt.source;
        failure.baseline = rebuilt.baseline;
        failure.candidate = rebuilt.candidate;
        failure.outcome = check;
      }
    }
    failure.shrink = {
      fromNodes: reduced.from,
      toNodes: reduced.to,
      probes: shrinkProbes - before,
      ...reduced.stats,
    };
  }

  const paths = saveFailure(failure);
  failures.push(failure);
  const label = kind === "mangle" ? "MISMATCH" : "BROKEN BASELINE";
  console.log(`  [${label}] seed ${seed} (${shape})`);
  if (failure.shrink) {
    console.log(
      `      shrunk ${failure.shrink.fromNodes} -> ${failure.shrink.toNodes} nodes ` +
        `in ${failure.shrink.probes} probes ` +
        `(${failure.shrink.accepted} accepted, ${failure.shrink.invalid} uncompilable)`,
    );
  }
  console.log(`      ${describeDifference(failure.outcome, kind)}`);
  console.log(`      ${paths[0]}`);
}

/// The first observation index whose encoding differs, with both sides.
/// A mismatch is usually one entry of a long tuple, and printing the
/// whole tuple buries it.
function describeDifference(outcome, kind = "mangle") {
  const baseline = outcome.baseline?.logs;
  const candidate = outcome.candidate?.logs;
  if (outcome.candidate?.status !== "completed") {
    const side = kind === "compress" ? "our bundle" : "mangled bundle";
    return `original ran; ${side} ${outcome.candidate?.status}: ${outcome.candidate?.message ?? ""}`.trim();
  }
  if (!Array.isArray(baseline) || !Array.isArray(candidate)) return "structural difference";
  const flatBase = JSON.stringify(baseline);
  const flatCand = JSON.stringify(candidate);
  if (flatBase === flatCand) return "no textual difference (encoding mismatch)";
  const rows = Math.max(baseline.length, candidate.length);
  for (let i = 0; i < rows; i++) {
    const left = JSON.stringify(baseline[i]);
    const right = JSON.stringify(candidate[i]);
    if (left !== right) {
      return `observation ${i}:\n      baseline  ${truncate(left, 220)}\n      mangled   ${truncate(right, 220)}`;
    }
  }
  return "difference outside the observation list";
}

function truncate(text, limit) {
  const value = String(text ?? "");
  return value.length > limit ? `${value.slice(0, limit)}…` : value;
}

// ---------------------------------------------------------------
// Campaign
// ---------------------------------------------------------------

const shapes = options.shape === "both" ? ["sink", "export"] : [options.shape];
const summary = {
  checked: 0,
  skipped: 0,
  mismatched: 0,
  brokenBaseline: 0,
  uncompilable: 0,
  harness: 0,
};
// Why baselines did not complete, tallied. A campaign whose skip count
// is high is not testing what it claims to, and the reason is the only
// way to tell a deliberately-throwing program from a generator defect.
const skipReasons = new Map();
const failures = [];
const compileErrors = [];
// signature -> { count, seed, kind, shape }
const families = new Map();

if (!options.quiet) {
  console.log(
    `fuzz_mangle: seeds ${options.startSeed}..${options.startSeed + options.iterations - 1}, ` +
      `shape ${options.shape}, ${options.mangle ? "mangling on" : "compression only"}\n`,
  );
}

outer: for (const shape of shapes) {
  for (let start = 0; start < options.iterations; start += options.batchSize) {
    const batch = [];
    const end = Math.min(start + options.batchSize, options.iterations);
    for (let i = start; i < end; i++) {
      const seed = options.startSeed + i;
      const program = generate(seed, { shape });
      const built = compileBoth(program, `s${seed}-${shape}`);
      if (!built.ok) {
        summary.uncompilable += 1;
        if (compileErrors.length < 5) {
          compileErrors.push({ seed, shape, stage: built.stage, error: built.error });
        }
        continue;
      }
      batch.push({ ...built, seed, shape, program });
    }
    if (batch.length === 0) continue;

    const outcomes = runBatch(batch, shape);
    for (let i = 0; i < batch.length; i++) {
      const entry = batch[i];
      const outcome = outcomes[i];
      if (outcome.verdict === "equivalent") {
        summary.checked += 1;
        continue;
      }
      if (outcome.verdict === "skipped") {
        // Before writing this off, ask whether the ORIGINAL program
        // works. If Node runs the TypeScript fine and our own bundle
        // does not, the compression pipeline broke it — a finding, and
        // one this harness used to swallow as a skip. Eleven of the
        // first sixteen seeds were exactly that.
        const reference = runReference(entry.sourcePath, shape === "export" ? "module" : "sink");
        if (reference.status !== "completed") {
          // The ORIGINAL program does not run, so the seed was never
          // going to test anything. Report the reference's reason: the
          // baseline's error is downstream of the same cause, and
          // reporting that one sent me looking for compiler bugs in
          // programs that were broken to begin with.
          summary.skipped += 1;
          const reason =
            reference.status === "threw"
              ? `original threw ${reference.name}: ${truncate(reference.message, 80)}`
              : `original ${reference.status}`;
          skipReasons.set(reason, (skipReasons.get(reason) ?? 0) + 1);
          continue;
        }
        summary.brokenBaseline += 1;
        recordFailure({
          kind: "compress",
          seed: entry.seed,
          shape,
          program: entry.program,
          entry,
          outcome: { verdict: "mismatch", baseline: reference, candidate: outcome.baseline },
        });
        if (families.size >= options.keepGoing) break outer;
        continue;
      }
      if (outcome.verdict === "harness") {
        summary.harness += 1;
        if (!options.quiet) {
          console.log(`  [harness] seed ${entry.seed} ${shape}: ${outcome.message}`);
        }
        continue;
      }

      summary.mismatched += 1;
      recordFailure({
        kind: "mangle",
        seed: entry.seed,
        shape,
        program: entry.program,
        entry,
        outcome,
      });
      if (families.size >= options.keepGoing) break outer;
    }
  }
}

// ---------------------------------------------------------------
// Report
// ---------------------------------------------------------------

console.log("");
console.log(
  `  ${summary.checked} compared, ${summary.skipped} skipped, ` +
    `${summary.mismatched} mangling mismatch(es), ` +
    `${summary.brokenBaseline} broken baseline(s), ` +
    `${summary.uncompilable} did not compile` +
    (summary.harness > 0 ? `, ${summary.harness} harness errors` : ""),
);

if (families.size > 0) {
  console.log("\n  distinct failure families, most frequent first:\n");
  for (const [signature, info] of [...families].sort((l, r) => r[1].count - l[1].count)) {
    console.log(
      `    ${String(info.count).padStart(4)}x  ${info.kind.padEnd(8)} ` +
        `first at seed ${info.seed} (${info.shape})  ${signature.slice(0, 96)}`,
    );
  }
  console.log("");
}

// Ranked, because one dominant reason is usually one generator defect.
for (const [reason, count] of [...skipReasons].sort((l, r) => r[1] - l[1]).slice(0, 6)) {
  console.log(`  [skip] ${count}x ${reason}`);
}

for (const error of compileErrors) {
  console.log(`  [compile] seed ${error.seed} ${error.shape} (${error.stage}): ${error.error}`);
}

fs.rmSync(WORK, { recursive: true, force: true });

// A run that compared nothing is not a pass, however few mismatches it
// found. Both causes are real: a generator that only emits throwing
// programs, and an mtsc that rejects everything.
if (summary.checked === 0) {
  console.error("\n  fuzz_mangle: nothing was compared — every seed was skipped or uncompilable");
  process.exit(2);
}
if (failures.length > 0) {
  console.error(`\n  fuzz_mangle: ${failures.length} mismatch(es) — artifacts in ${options.saveDir}`);
  process.exit(1);
}
console.log("\n  no mismatch");
