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
const DEFAULT_RUNGS = [500, 1000, 2000, 4000];

// Per-axis rung override, for an axis whose top rung costs minutes.
// The header promises the whole run stays near a minute, and an axis is
// only required to span 4x between its endpoints to separate linear from
// quadratic — so an axis that is itself quadratic must climb a cheaper
// ladder or it alone dominates the run. `namespaces` at 4,000 is ~90 s
// per iteration (it is the quadratic below), which took the default run
// from ~1 minute to ~15; at 1,000 the same axis fits the same exponent
// in 2 s. `--rungs` still overrides everything.
const AXIS_RUNGS = {
  namespaces: [125, 250, 500, 1000],
  // Quadratic, so it climbs a cheaper ladder for the same reason
  // `namespaces` does: 4x between the endpoints separates linear from
  // quadratic, and at 4,000 this axis alone would dominate the run. It
  // fits 2.14 here in 2 s against 2.20 on the default rungs.
  "nested-closures": [250, 500, 1000, 2000],
  "block-scopes": [250, 500, 1000, 2000],
  // A chain this long is already far past anything real (the deepest
  // `extends` chain in this repo's own node_modules is single digits), and
  // 50..400 spans the 8x that separates linear from quadratic.
  "class-chain-depth": [50, 100, 200, 400],
};

// Per-axis exponent budget. Every axis is held to `--max-exponent` (1.5)
// unless it is named here, and a named axis is still GATED — at its own
// measured number — so a regression past an accepted cost still fails.
// A budget without a written reason is a suppression; each entry carries
// the mechanism and what it costs on real input.
const AXIS_BUDGET = {
  // KNOWN QUADRATIC in the number of namespaces, and the reason is
  // structural rather than a nested scan: a namespace body is its own
  // `TsModule`, so `check_module_function_bodies_layered` runs once per
  // namespace and each run ingests the OUTER chain — and
  // `Resolver::ingest_module` recurses through the whole namespace tree,
  // registering every nested declaration under its prefix. N namespaces
  // therefore ingest the whole tree N times.
  //
  // Removing it needs a layered resolver (a parent consulted on miss, or
  // a journalled overlay that can be undone per sibling), which is ~200
  // read sites in `expr_check.mbt` and the wrong trade at the measured
  // stakes: the file with the most namespaces in this repo's own
  // node_modules is `@types/node/fs.d.ts` at 43, where the whole check
  // is 48 ms, and the ladder only separates from linear past a few
  // hundred. The root-wide name backstops WERE hoisted out of it (see
  // `RootNameBackstops`) — worth -22% at n=1000 and nothing measurable
  // on any real file.
  namespaces: 2.15,
  // KNOWN QUADRATIC in the number of `#private` members of ONE class, and
  // the mechanism is a nested scan rather than anything structural:
  // `private_brand_declared_on_receiver` answers "does the receiver class
  // declare this base name under a DIFFERENT brand" by looping the
  // receiver's `properties`, `methods` and `private_members` — per
  // ACCESS. A class whose N members each read one `#name` therefore pays
  // N x N. Found by this axis on its first full run after the rung cap
  // below: at 125..1000 it fits 1.17 and looks linear, and the 2000 ->
  // 4000 step is 111 -> 499 ms.
  //
  // The fix is an index (per class, base name -> the brands declaring
  // it, filled on first use), which is ~20 lines and is filed rather
  // than taken here because the reach is nil: the quadratic is in the
  // members of a SINGLE class, and a class with hundreds of `#private`
  // members does not occur — single digits is the norm, where N^2 is
  // dozens of operations. Gated at its measured number so a regression
  // past the accepted cost still fails.
  "private-members": 1.75,
  // Declared at its measured number, and unlike `private-members` the
  // reach here is NOT nil: this is the dominant cost on real input.
  // `typescript/src/compiler/checker.ts` is one ~50,000-line function
  // containing thousands of closures over a shared scope, and it alone is
  // 27.8 s of a 56 s compile of this repo's own submodule — 8.82 us/byte
  // against 0.27-0.38 for the ~0.5 MB sources beside it.
  //
  // It is gated rather than fixed because the fix is a refactor of the
  // checker's hottest data structure and wants its own change. The
  // save/restore pair is O(enclosing bindings) at 21 paired call sites;
  // replacing it with an undo JOURNAL (record each mutation's previous
  // value, unwind to a mark) makes it O(mutations in the scope) and there
  // are only 3 writes to `vars`, 2 removes and 4 `declared` mutations to
  // intercept. The PRECONDITION is what needs auditing first, and it is
  // why this is not a one-liner: a journal requires strict LIFO nesting,
  // while an array snapshot tolerates any order — several call sites
  // restore one snapshot twice (idempotent either way), but a pair that
  // restores an OUTER snapshot before an inner one would silently differ.
  "nested-closures": 2.25,
  // KNOWN QUADRATIC per `{ }` block, and the same root as
  // `nested-closures` seen from the other side: `check_block` snapshots
  // the whole env on entry and restores it on exit, so N blocks in a body
  // with N bindings pay N x N. Measured 1.86 isolated (35x at n=2000
  // against the unbraced control); gated here at its measured number on
  // the axis ladder. Fixed by the same undo journal, whose precondition
  // is audited and holds — see the axis comment.
  "block-scopes": 2.1,
};

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
  // Overload SETS, three declarations per name: the shape TS2371 /
  // TS2393 / TS2394 / TS7010 and `check_overload_void_return` read. The
  // list these walk is `module_.funcs`, which no other axis grows — and
  // the per-name grouping is what an implementation-pairing rule pairs
  // within, so a rule quadratic inside one name and a rule quadratic
  // across the module both show here.
  functions: (n) => {
    const out = [];
    for (let i = 0; i < n; i++) {
      out.push(`export function f${i}(a: number): void;`);
      out.push(`export function f${i}(a: string): void;`);
      out.push(`export function f${i}(a: number | string): void { }`);
    }
    return out.join("\n") + "\n";
  },
  // Namespaces, half of them type-only: `check_typeof_namespace_value_types`
  // sweeps every declaration's type for a `typeof` base and joins against
  // `namespace_instantiated`, and `check_namespace_body_this` walks each
  // body. Both lists are namespace-keyed, so neither is reachable from
  // any other axis.
  namespaces: (n) => {
    const out = [];
    for (let i = 0; i < n; i++) {
      out.push(`export namespace N${i} { export const x${i} = ${i}; }`);
      out.push(`declare var q${i}: typeof N${i};`);
    }
    return out.join("\n") + "\n";
  },
  // `#private` members, each declared and read. The private rules read
  // the class body's TOKEN SPAN rather than walking members — a span is
  // the idiom this repo reaches for when a walker would lose findings
  // silently, and batch CP's TS5076 is the reason a span needs its own
  // cost model. One class per rung keeps the span itself growing, which
  // is the shape that went quadratic there.
  // `extends` CHAIN DEPTH, with a static read through the deep end. The
  // one shape none of the other twelve axes can grow: every one of them
  // grows a module-wide LIST, so a walk that is quadratic in the length
  // of an inheritance chain is invisible to all of them.
  //
  // That is not hypothetical — it is why this axis exists. Batch EL's
  // `class_static_member_rec` passed `[name, ..seen]`, copying the
  // accumulated array once per level, and a hand ladder read
  // 54 / 153 / 457 / 1673 ms at depth 50 / 100 / 200 / 400 (exponent
  // 1.65) while the twelve axes all stayed green. The `classes` axis
  // grows the class COUNT and reads 1.06 on a FLAT hierarchy of the same
  // size, which is what separates the two diagnoses — the same job
  // `same-bytes` does for bytes versus declarations.
  //
  // The reads are what make the walk run; a chain alone is only parsed.
  "class-chain-depth": (n) => {
    const out = [];
    out.push(`class C0 { static s: number = 1 }`);
    for (let i = 1; i < n; i++) out.push(`class C${i} extends C${i - 1} { }`);
    out.push(`declare const c: typeof C${n - 1};`);
    out.push(`export function f(): number {`);
    for (let i = 0; i < 200; i++) out.push(`  const n${i}: number = c.s;`);
    out.push(`  return n0`);
    out.push(`}`);
    return out.join("\n") + "\n";
  },
  "private-members": (n) => {
    const out = [];
    out.push(`export class P {`);
    for (let i = 0; i < n; i++) out.push(`  #a${i} = ${i};`);
    for (let i = 0; i < n; i++) out.push(`  m${i}(): number { return this.#a${i} }`);
    out.push(`}`);
    return out.join("\n") + "\n";
  },
  // N functions each with a REAL BODY — the shape that dominates a large
  // compile, and the one no other axis grows. `functions` above is
  // bodiless overload signatures and `statements` below is one body with
  // N statements; neither grows the number of BODIES, and the body walk
  // is where inference, narrowing and every expression-level check run.
  // mtsc's own `--no-check` help puts the type check at ~95% of a large
  // compile, so this axis is the one whose exponent a 9 MB bundle pays.
  "function-bodies": (n) => {
    const out = [];
    for (let i = 0; i < n; i++) {
      out.push(`export function b${i}(a: number, s: string): string {`);
      out.push(`  const t = s + String(a + ${i});`);
      out.push(`  if (t.length > ${i % 7}) { return t.slice(0, ${i % 5}) }`);
      out.push(`  const parts = t.split("-").map((p) => p.trim());`);
      out.push(`  return parts.join(",") + b${i}Helper(a);`);
      out.push(`}`);
      out.push(`function b${i}Helper(x: number): string { return String(x * 2) }`);
    }
    return out.join("\n") + "\n";
  },
  // CLOSURES NESTED INSIDE ONE BODY — the dimension every other axis
  // misses, and the one that dominates a real compile.
  //
  // `function-bodies` above grows N SIBLING functions, each with its own
  // small scope, and reads 1.04. `statements` below grows N statements in
  // ONE body with no closures, and reads 0.75. Neither grows closures
  // nested in a large enclosing scope, and that is what a real large
  // function is: `typescript/src/compiler/checker.ts` is essentially one
  // 50,000-line `createTypeChecker` containing thousands of inner
  // functions over one shared scope.
  //
  // What that costs, measured: checker.ts alone is 27.8 s of `tscheck`
  // at 8.82 us/byte, where parser.ts / utilities.ts / types.ts at ~0.5 MB
  // each run at 0.27-0.38 us/byte. Truncating inside the giant function
  // (balancing braces so each probe still parses) gives 0.372 s at 245 KB,
  // 3.76 s at 1.15 MB, 9.14 s at 1.76 MB, 15.94 s at 2.32 MB, 28.14 s at
  // 3.10 MB — exponent 2.03 in the size of ONE function body.
  //
  // The mechanism is the env save/restore around each nested body.
  // `ExprEnv::full_snapshot` copies the whole `vars` map into an array and
  // `ExprEnv::restore_from` then makes three more full passes over it
  // (build a `kept` map from the snapshot, scan `vars` for names to drop,
  // rewrite every snapshot entry) — four O(enclosing bindings) passes with
  // string hashing, per closure. callgrind on a 20,000-line probe: 916
  // `check_funcexpr_with_context` calls, and 83% of self cost is String
  // hash (29.5%), Map[String, TsType] add/set/iter/push/rehash (24.4%) and
  // alloc + GC (29.1%).
  //
  // The isolated shape below fits 1.90, and its control — the same
  // bindings and closures split into N separate small functions, at 1.4x
  // the bytes — fits 0.77. At n=1600 the nested form is 18x slower on 30%
  // FEWER bytes, which is what makes this a scope-size effect rather than
  // a byte effect.
  "nested-closures": (n) => {
    const out = [];
    out.push(`export function outer(): number {`);
    for (let i = 0; i < n; i++) out.push(`  const v${i}: number = ${i};`);
    // Each closure reads one enclosing binding, so the scope it is
    // checked against is the whole outer body rather than a fresh one.
    for (let i = 0; i < n; i++) {
      out.push(`  const f${i} = (x: number): number => x + v${i};`);
    }
    out.push(`  return f0(1);`);
    out.push(`}`);
    return out.join("\n") + "\n";
  },
  // BLOCKS inside one body, which is the other half of `nested-closures`
  // and the commonest construct in any real function: every `if` body,
  // every loop body and every bare `{ }` goes through `check_block`, and
  // `check_block`'s first act is `env.full_snapshot()` with a
  // `restore_from` at the end — O(enclosing bindings) PER BLOCK.
  //
  // Isolated against its control, the same assignments with no braces:
  // 0.018 / 0.045 / 0.177 / 0.865 s braced (1.86) against
  // 0.008 / 0.010 / 0.015 / 0.025 s bare (0.55). At n=2000, wrapping
  // each assignment in `{ }` is 35x slower on 8% MORE bytes.
  //
  // `statements` below is the control that was already here and could
  // not see it: its statements are unbraced, so it fits 0.99. Narrowing
  // is NOT the trigger either — an `if (b)` with no type guard fits 2.10,
  // the same as `if (typeof p === "string")` at 2.04, because the block
  // pays the snapshot whether or not anything narrows.
  //
  // The fix is the undo JOURNAL filed in TODO.md, whose LIFO
  // precondition has been audited and HOLDS: all 17 save sites are
  // function-locals restored in the same function, the only multi-save
  // function has them in mutually exclusive match arms, and the two
  // double-restore sites are the ternary pattern (one mark unwound
  // twice, which a journal handles). Note that `full_snapshot` serves
  // three purposes and only these 17 are saves — 4 sites use it as an
  // ENUMERATOR to copy an outer env into a fresh child (the
  // `nested-closures` cost, which wants a layered env instead) and 2 as
  // a READ-OUT that genuinely needs every binding.
  "block-scopes": (n) => {
    const out = [];
    out.push(`export function blocks(): number {`);
    for (let i = 0; i < n; i++) out.push(`  const v${i}: number = ${i};`);
    out.push(`  let acc = 0;`);
    // A bare block, not an `if`: the snapshot is the block's, and using
    // `if` would leave "is it the narrowing?" open when it is not.
    for (let i = 0; i < n; i++) out.push(`  { acc = acc + v${i}; }`);
    out.push(`  return acc;`);
    out.push(`}`);
    return out.join("\n") + "\n";
  },
  // Statements inside ONE function body: the expando (TS2565) ordered
  // pass, the `this`-region walk and every body-level check. Distinct
  // from `vars`, whose statements are at module top level, where a
  // different set of sweeps runs.
  statements: (n) => {
    const out = [];
    out.push(`export function body(): number {`);
    out.push(`  let acc = 0;`);
    for (let i = 0; i < n; i++) out.push(`  const s${i} = acc + ${i}; acc = s${i};`);
    out.push(`  return acc;`);
    out.push(`}`);
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
  const opts = {
    axis: null,
    maxExponent: 1.5,
    baseline: null,
    keep: false,
    rungs: DEFAULT_RUNGS,
    rungsExplicit: false,
  };
  for (let i = 2; i < argv.length; i++) {
    const a = argv[i];
    if (a === "--axis") opts.axis = argv[++i];
    else if (a === "--max-exponent") opts.maxExponent = Number(argv[++i]);
    else if (a === "--baseline") opts.baseline = argv[++i];
    // A ladder whose top rung is too slow to reach is a ladder nobody
    // runs: an axis under investigation needs a cheaper one, and the
    // exponent only needs a 4x spread between its endpoints to separate
    // linear from quadratic.
    else if (a === "--rungs") {
      opts.rungsExplicit = true;
      opts.rungs = argv[++i]
        .split(",")
        .map((x) => Number(x.trim()))
        .filter((x) => Number.isFinite(x) && x > 0);
      if (opts.rungs.length < 2) {
        console.error("--rungs needs at least two sizes, e.g. --rungs 250,500,1000");
        process.exit(2);
      }
    }
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
  const RUNGS = opts.rungs;
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

  const header = ["axis", ...RUNGS.map((n) => `n=${n}`), "exp", "budget", "verdict"];
  const rows = [];
  const failures = [];

  for (const axis of axes) {
    const times = [];
    let broke = null;
    // An explicit `--rungs` wins; otherwise an axis may declare its own.
    const rungs = opts.rungsExplicit ? RUNGS : (AXIS_RUNGS[axis] ?? RUNGS);
    for (const n of rungs) {
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
      rows.push([axis, ...rungs.map(() => "-"), "-", "-", `ERROR ${broke}`]);
      failures.push(`${axis}: ${broke}`);
      continue;
    }
    const k = exponent(rungs, times);
    // `same-bytes` is a control, not a budget: its declaration count is
    // constant, so its growth is whatever per-byte cost the checker has
    // and it is not asserted on. It is printed because a run where it
    // ALSO grew quadratically means the cost is in the bytes and the
    // per-axis numbers below are all reading the same thing.
    const asserted = axis !== "same-bytes";
    const budget = AXIS_BUDGET[axis] ?? opts.maxExponent;
    const bad = asserted && (Number.isNaN(k) || k > budget);
    if (bad) failures.push(`${axis}: exponent ${k.toFixed(2)} > ${budget.toFixed(2)}`);
    rows.push([
      // A row on its own ladder says so, or its milliseconds read as
      // comparable with the others' and they are not.
      rungs === RUNGS ? axis : `${axis} (n=${rungs.join("/")})`,
      ...times.map((t) => `${t.toFixed(1)}ms`),
      Number.isNaN(k) ? "?" : k.toFixed(2),
      budget.toFixed(2),
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
