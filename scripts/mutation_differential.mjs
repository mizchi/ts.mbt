// Mutation differential: plant one small edit at a time in code tsc
// accepts, ask tsc whether the edit is an error, and ask mtsc whether it
// noticed.
//
// Every other checker gate here is a list somebody wrote: the conformance
// corpus, `fixtures/tsc-extra`, the planted errors of `fixtures/real-app`.
// A list covers the shapes its author thought of. A mutation is not chosen
// by anyone — it is applied at every site a rule matches — so it reaches
// the call, the member access and the object literal that real code
// writes, against real package types, and TypeScript decides what each
// one means. That makes it two measurements at once:
//
//   CAUGHT  tsc reports something new in the mutated file, and so does mtsc.
//   MISS    tsc reports something new, mtsc is silent. A recall gap.
//   FP      tsc reports NOTHING new, and mtsc does. A false positive on
//           legal code — the one direction the repo's budget is zero for.
//   TN      neither reports anything new.
//
// "New" is a multiset difference against the unmutated run, per file and
// without line numbers (an edit can move lines; it cannot rename a
// message), so a project that already carries reports — a field target
// like univer — still yields a clean answer for each edit.
//
// The idea is tsrs's (`tools/mutate`, which diffs tsgo against tsrs by
// file, line, column and code). This is a separate implementation with its
// own mutators, and it scores by file because mtsc reports carry no span.
//
// Usage:
//   node scripts/mutation_differential.mjs [options]
//     --project DIR    project directory (default fixtures/real-app/ok)
//     --tsconfig F     tsconfig path, relative to DIR (default tsconfig.json)
//     --files GLOB     only mutate files whose project-relative path
//                      contains this substring (default: every file the
//                      project's `src/` holds)
//     --mutators A,B   only these mutators
//     --count N        sample N mutants (seeded) instead of all of them
//     --seed N         sampling seed, any safe integer (default 1)
//     --mtsc PATH      mtsc binary (default the release build)
//     --tsc PATH       tsc entry (default node_modules/typescript/bin/tsc)
//     --max-fp N       exit 1 when more than N UNDECLARED mutants are false
//                      positives (see --declared)
//     --declared F     false positives already known, one per line as
//                      `FILE:LINE:COL MUTATOR  reason`; default
//                      `fixtures/real-app/mutation-fps.txt` for the default
//                      project. A declared entry that ran and was NOT a
//                      false positive fails as STALE, which is what keeps
//                      the file from becoming a suppression list.
//     --json PATH      write every mutant's outcome
//     --verbose        print every mutant, not only MISS / FP
//     --list           list the mutants and run nothing
import fs from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { createRequire } from "node:module";

const ROOT = path.resolve(path.dirname(new URL(import.meta.url).pathname), "..");
const require = createRequire(import.meta.url);
// The classic in-process API, for finding mutation sites only. Which edit
// is an error is decided by the compiler under test below, never here.
const ts = require(path.join(ROOT, "node_modules", "typescript-6"));

const argv = process.argv.slice(2);
const flag = (f) => argv.includes(f);
const die = (msg) => {
  console.error(`mutation_differential: ${msg}`);
  process.exit(2);
};
/** An option's operand; a missing one, or another option in its place, is an error. */
const value = (f) => {
  const i = argv.indexOf(f);
  if (i < 0) return undefined;
  const v = argv[i + 1];
  if (v === undefined || v.startsWith("--")) die(`${f} needs a value`);
  return v;
};
/**
 * An integer operand no smaller than `min`, or `undefined` when the option is
 * absent. It must be a safe integer (|n| <= 2^53 - 1): a longer run of digits
 * converts to `Infinity`, which would switch the `--max-fp` budget off.
 */
const intValue = (f, min) => {
  const v = value(f);
  if (v === undefined) return undefined;
  const n = Number(v);
  if (!/^-?\d+$/.test(v) || !Number.isSafeInteger(n) || n < min) {
    die(`${f} needs a safe integer >= ${min}, got \`${v}\``);
  }
  return n;
};
const PROJECT = path.resolve(value("--project") ?? path.join(ROOT, "fixtures", "real-app", "ok"));
const TSCONFIG = value("--tsconfig") ?? "tsconfig.json";
const FILES = value("--files");
const ONLY = value("--mutators")?.split(",");
const COUNT = intValue("--count", 1);
const SEED = intValue("--seed", Number.MIN_SAFE_INTEGER) ?? 1;
const MAX_FP = intValue("--max-fp", 0);
const DECLARED_PATH = value("--declared") ??
  (value("--project") ? undefined : path.join(ROOT, "fixtures", "real-app", "mutation-fps.txt"));
const JSON_OUT = value("--json");
const VERBOSE = flag("--verbose");
const MTSC = path.resolve(
  value("--mtsc") ?? path.join(ROOT, "_build", "native", "release", "build", "cmd", "mtsc", "mtsc.exe"),
);
const TSC = path.resolve(value("--tsc") ?? path.join(ROOT, "node_modules", "typescript", "bin", "tsc"));
// `node_modules/typescript/bin/tsc` is a node script; a native tsc is run
// directly. A script starts with `#!` or is a `.js` / `.mjs` file.
const TSC_IS_SCRIPT = /\.[cm]?js$/.test(TSC) || fs.readFileSync(TSC).subarray(0, 2).toString() === "#!";
// mtsc's async runtime blocks SIGTERM, so a bound on it has to be SIGKILL.
const TIMEOUT_MS = 600_000;

// ------------------------------------------------------------- checkers

function spawn(cmd, args) {
  const r = spawnSync(cmd, args, {
    cwd: PROJECT,
    encoding: "utf8",
    timeout: TIMEOUT_MS,
    killSignal: "SIGKILL",
    maxBuffer: 256 * 1024 * 1024,
  });
  if (r.error) throw r.error;
  if (r.signal) throw new Error(`${path.basename(cmd)} was killed (${r.signal})`);
  return `${r.stdout}\n${r.stderr}`;
}

const rel = (f) => path.relative(PROJECT, path.resolve(PROJECT, f)).replaceAll("\\", "/");

// Only the file this run has mutated is ever restored, and only when it
// still holds the mutation: an edit somebody made to it meanwhile is left
// alone and reported rather than overwritten.
//
// A SIGKILL runs no handler, and a container restart is one, so the edit in
// flight is also written to a journal before it is applied. A run that
// finds a journal puts that file back first, under the same rule.
//
// A source file is replaced whole (a complete temporary file renamed over
// it, with its mode kept), so a kill cannot leave it truncated; and the
// journal is removed only once the file provably holds the original again,
// so a file that matches neither saved version keeps its journal.
const JOURNAL = path.join(PROJECT, ".mutation-differential.journal.json");
let active = null;
const writeWhole = (p, text) => {
  const tmp = `${p}.mutation-tmp`;
  fs.writeFileSync(tmp, text);
  fs.chmodSync(tmp, fs.statSync(p).mode);
  fs.renameSync(tmp, p);
};
/** Puts the original back; true when the file holds the original afterwards. */
const putBack = ({ p, original, mutated }) => {
  const now = fs.readFileSync(p, "utf8");
  if (now === mutated) writeWhole(p, original);
  else if (now !== original) {
    console.error(`mutation_differential: ${rel(p)} matches neither the original nor the mutation; left as it is, with ${rel(JOURNAL)}`);
    return false;
  }
  return true;
};
const restore = () => {
  if (!active) return;
  const a = active;
  active = null;
  if (putBack(a)) fs.rmSync(JOURNAL, { force: true });
  // A file somebody changed mid-run is left as it is, and the run stops:
  // every later mutant of it would be measured against the wrong text.
  else process.exit(2);
};
const alive = (pid) => {
  try {
    process.kill(pid, 0);
    return true;
  } catch (e) {
    return e.code === "EPERM";
  }
};
if (fs.existsSync(JOURNAL)) {
  const left = JSON.parse(fs.readFileSync(JOURNAL, "utf8"));
  // A journal whose run is still going is that run's edit in flight.
  if (left.pid !== process.pid && alive(left.pid)) {
    die(`another run (pid ${left.pid}) has an edit in flight in ${rel(left.p)}; not touching it`);
  }
  console.error(`mutation_differential: an earlier run was killed mid-edit; restoring ${rel(left.p)}`);
  if (!putBack(left)) process.exit(2);
  fs.rmSync(JOURNAL, { force: true });
}

/** tsc's diagnostics per file, as `TSn message` with the location dropped. */
function runTsc() {
  const out = new Map();
  const args = ["-p", TSCONFIG, "--noEmit", "--pretty", "false"];
  const text = TSC_IS_SCRIPT ? spawn(process.execPath, [TSC, ...args]) : spawn(TSC, args);
  for (const line of text.split("\n")) {
    // A diagnostic with no location is about the configuration, and a run
    // that could not read its configuration checked nothing.
    if (/^error TS\d+:/.test(line.trim())) die(`tsc rejected the project: ${line.trim()}`);
    const m = /^(.+?)\(\d+,\d+\): error (TS\d+): (.*)$/.exec(line.trim());
    if (!m) continue;
    const f = rel(m[1]);
    if (!out.has(f)) out.set(f, []);
    out.get(f).push(`${m[2]} ${m[3]}`);
  }
  return out;
}

/** mtsc's reports per file, from `mtsc: type error in FILE [PATH]: MSG`. */
function runMtsc() {
  const out = new Map();
  let crashed = null;
  const r = spawnSync(MTSC, ["-p", TSCONFIG, "--noEmit"], {
    cwd: PROJECT,
    encoding: "utf8",
    timeout: TIMEOUT_MS,
    killSignal: "SIGKILL",
    maxBuffer: 256 * 1024 * 1024,
  });
  if (r.error) throw r.error;
  if (r.signal) crashed = r.signal;
  for (const raw of `${r.stdout}\n${r.stderr}`.split("\n")) {
    const line = raw.trim();
    const m = /^mtsc: [a-z ]*error in (\S+?)((?: \[|:).*)$/.exec(line);
    if (!m) continue;
    const f = rel(m[1]);
    if (!out.has(f)) out.set(f, []);
    out.get(f).push(m[2].trim());
  }
  // A failing exit with no diagnostic means nothing was checked (a missing
  // tsconfig, a graph that did not load), and reading that as "no report"
  // would score every mutant as MISS or TN.
  if (!crashed && r.status !== 0 && out.size === 0) {
    const first = `${r.stdout}\n${r.stderr}`.split("\n").find((l) => l.trim()) ?? "";
    crashed = `exit ${r.status} with no diagnostic: ${first.trim()}`;
  }
  return { byFile: out, crashed };
}

/** Elements of `after` not matched by an element of `before` (multiset). */
function added(before = [], after = []) {
  const left = new Map();
  for (const x of before) left.set(x, (left.get(x) ?? 0) + 1);
  const out = [];
  for (const x of after) {
    const n = left.get(x) ?? 0;
    if (n > 0) left.set(x, n - 1);
    else out.push(x);
  }
  return out;
}

// ------------------------------------------------------------- mutators
//
// Each mutator lists edits `{ start, end, text }` for one source file. A
// mutator names what it EXPECTS (`error` or `legal`), but the expectation
// is only a label for the report: tsc's answer is what classifies a mutant.

const isArg = (n) =>
  n.parent && (ts.isCallExpression(n.parent) || ts.isNewExpression(n.parent)) &&
  (n.parent.arguments ?? []).includes(n);

const MUTATORS = [
  {
    name: "string-arg-to-number",
    expects: "error",
    visit: (n, sf, push) => {
      if ((ts.isStringLiteral(n) || ts.isNoSubstitutionTemplateLiteral(n)) && isArg(n)) {
        push(n.getStart(sf), n.end, "0");
      }
    },
  },
  {
    name: "number-arg-to-string",
    expects: "error",
    visit: (n, sf, push) => {
      if (ts.isNumericLiteral(n) && isArg(n)) push(n.getStart(sf), n.end, '"0"');
    },
  },
  {
    name: "bool-to-string",
    expects: "error",
    visit: (n, sf, push) => {
      if (n.kind === ts.SyntaxKind.TrueKeyword || n.kind === ts.SyntaxKind.FalseKeyword) {
        push(n.getStart(sf), n.end, '"x"');
      }
    },
  },
  {
    name: "drop-last-arg",
    expects: "error",
    visit: (n, sf, push) => {
      if ((ts.isCallExpression(n) || ts.isNewExpression(n)) && n.arguments?.length) {
        const args = n.arguments;
        const last = args[args.length - 1];
        const start = args.length > 1 ? args[args.length - 2].end : last.getStart(sf);
        push(start, last.end, "");
      }
    },
  },
  {
    name: "extra-arg",
    expects: "error",
    visit: (n, sf, push) => {
      if (ts.isCallExpression(n) && n.arguments) {
        const args = n.arguments;
        if (args.length === 0) push(args.pos, args.pos, "0");
        else push(args[args.length - 1].end, args[args.length - 1].end, ", 0");
      }
    },
  },
  {
    name: "null-arg",
    expects: "error",
    visit: (n, sf, push) => {
      if (isArg(n) && !ts.isSpreadElement(n) && n.kind !== ts.SyntaxKind.NullKeyword) {
        push(n.getStart(sf), n.end, "null");
      }
    },
  },
  {
    name: "member-typo",
    expects: "error",
    visit: (n, sf, push) => {
      if (ts.isPropertyAccessExpression(n) && ts.isIdentifier(n.name)) {
        push(n.name.getStart(sf), n.name.end, `${n.name.text}Mut`);
      }
    },
  },
  {
    name: "undeclared-name",
    expects: "error",
    visit: (n, sf, push) => {
      if (ts.isIdentifier(n) && isArg(n)) push(n.getStart(sf), n.end, "undeclaredMut");
    },
  },
  {
    name: "drop-object-member",
    expects: "error",
    visit: (n, sf, push) => {
      if (ts.isObjectLiteralExpression(n)) {
        const ps = n.properties;
        ps.forEach((p, i) => {
          const start = i > 0 ? ps[i - 1].end : p.getStart(sf);
          const end = i > 0 ? p.end : i + 1 < ps.length ? ps[i + 1].getStart(sf) : p.end;
          push(start, end, "");
        });
      }
    },
  },
  {
    name: "drop-await",
    expects: "error",
    visit: (n, sf, push) => {
      if (ts.isAwaitExpression(n)) push(n.getStart(sf), n.expression.getStart(sf), "");
    },
  },
  {
    name: "paren-wrap-arg",
    expects: "legal",
    visit: (n, sf, push) => {
      if (isArg(n) && !ts.isSpreadElement(n)) {
        push(n.getStart(sf), n.end, `(${n.getText(sf)})`);
      }
    },
  },
  {
    name: "satisfies-unknown",
    expects: "legal",
    visit: (n, sf, push) => {
      if (isArg(n) && !ts.isSpreadElement(n) && !ts.isArrowFunction(n) && !ts.isFunctionExpression(n)) {
        push(n.getStart(sf), n.end, `(${n.getText(sf)} satisfies unknown)`);
      }
    },
  },
];

function projectFiles() {
  const out = [];
  const walk = (dir) => {
    for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
      if (e.name === "node_modules" || e.name.startsWith(".")) continue;
      const p = path.join(dir, e.name);
      if (e.isDirectory()) walk(p);
      // Only a regular file is edited. Renaming a temporary file over a
      // symlink would replace the link with a copy of its target, so a
      // linked source is skipped rather than mutated.
      else if (e.isFile() && /\.(ts|tsx|mts|cts)$/.test(e.name) && !/\.d\.[mc]?ts$/.test(e.name)) out.push(rel(p));
    }
  };
  const src = path.join(PROJECT, "src");
  walk(fs.existsSync(src) && !FILES ? src : PROJECT);
  return out.filter((f) => !FILES || f.includes(FILES)).sort();
}

function enumerateMutants(files) {
  const mutants = [];
  for (const file of files) {
    const text = fs.readFileSync(path.join(PROJECT, file), "utf8");
    const kind = file.endsWith("x") ? ts.ScriptKind.TSX : ts.ScriptKind.TS;
    const sf = ts.createSourceFile(file, text, ts.ScriptTarget.Latest, true, kind);
    for (const m of MUTATORS) {
      if (ONLY && !ONLY.includes(m.name)) continue;
      const seen = new Set();
      const visit = (n) => {
        m.visit(n, sf, (start, end, repl) => {
          const key = `${start}:${end}:${repl}`;
          if (seen.has(key)) return;
          seen.add(key);
          const lc = sf.getLineAndCharacterOfPosition(start);
          mutants.push({ file, mutator: m.name, expects: m.expects, start, end, repl,
            line: lc.line + 1, col: lc.character + 1, before: text.slice(start, end), text });
        });
        ts.forEachChild(n, visit);
      };
      visit(sf);
    }
  }
  return mutants;
}

/** mulberry32: a small seeded PRNG, so a sampled run can be repeated. */
function rng(seed) {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

/** `FILE:LINE:COL MUTATOR  reason` entries; `#` starts a comment. */
function readDeclared() {
  const out = new Map();
  if (!DECLARED_PATH || !fs.existsSync(DECLARED_PATH)) return out;
  for (const raw of fs.readFileSync(DECLARED_PATH, "utf8").split("\n")) {
    const line = raw.replace(/#.*/, "").trim();
    if (!line) continue;
    const [where, mutator, ...reason] = line.split(/\s+/);
    if (!mutator || reason.length === 0) {
      throw new Error(`${DECLARED_PATH}: \`${line}\` needs FILE:LINE:COL MUTATOR and a reason`);
    }
    out.set(`${where} ${mutator}`, reason.join(" "));
  }
  return out;
}

// ----------------------------------------------------------------- run

const files = projectFiles();
let mutants = enumerateMutants(files);
const total = mutants.length;
if (COUNT !== undefined && COUNT < mutants.length) {
  const r = rng(SEED);
  for (let i = mutants.length - 1; i > 0; i--) {
    const j = Math.floor(r() * (i + 1));
    [mutants[i], mutants[j]] = [mutants[j], mutants[i]];
  }
  mutants = mutants.slice(0, COUNT);
}

if (flag("--list")) {
  const per = new Map();
  for (const m of mutants) per.set(m.mutator, (per.get(m.mutator) ?? 0) + 1);
  for (const [k, n] of [...per].sort()) console.log(`${k.padEnd(22)} ${n}`);
  console.log(`total ${mutants.length} of ${total}`);
  if (VERBOSE) {
    for (const m of mutants) console.log(`${m.mutator} ${m.file}:${m.line} ${JSON.stringify(m.before)} -> ${JSON.stringify(m.repl)}`);
  }
  process.exit(0);
}

process.on("exit", restore);
for (const sig of ["SIGINT", "SIGTERM"]) process.on(sig, () => { restore(); process.exit(130); });

console.log(`Project  : ${path.relative(ROOT, PROJECT) || "."} (${files.length} file(s))`);
console.log(`Mutants  : ${mutants.length}${COUNT !== undefined ? ` sampled of ${total} (seed ${SEED})` : ""}`);
const baseTsc = runTsc();
const baseMtsc = runMtsc();
if (baseMtsc.crashed) throw new Error(`mtsc crashed on the unmutated project (${baseMtsc.crashed})`);

const results = [];
const counts = new Map();
const bump = (m, k) => {
  if (!counts.has(m)) counts.set(m, { CAUGHT: 0, MISS: 0, FP: 0, TN: 0, CRASH: 0 });
  counts.get(m)[k]++;
};
try {
  for (const [i, m] of mutants.entries()) {
    const p = path.join(PROJECT, m.file);
    if (fs.readFileSync(p, "utf8") !== m.text) die(`${m.file} changed since the mutants were listed; stopping`);
    const mutated = m.text.slice(0, m.start) + m.repl + m.text.slice(m.end);
    active = { p, original: m.text, mutated, pid: process.pid };
    fs.writeFileSync(JOURNAL, JSON.stringify(active));
    writeWhole(p, mutated);
    let tscNew;
    let mtsc;
    try {
      tscNew = added(baseTsc.get(m.file), runTsc().get(m.file));
      mtsc = runMtsc();
    } finally {
      restore();
    }
    const mtscNew = added(baseMtsc.byFile.get(m.file), mtsc.byFile.get(m.file));
    const outcome = mtsc.crashed
      ? "CRASH"
      : tscNew.length > 0
        ? mtscNew.length > 0 ? "CAUGHT" : "MISS"
        : mtscNew.length > 0 ? "FP" : "TN";
    bump(m.mutator, outcome);
    const rec = { file: m.file, line: m.line, col: m.col, mutator: m.mutator, expects: m.expects,
      before: m.before, after: m.repl, outcome, tsc: tscNew, mtsc: mtscNew };
    results.push(rec);
    if (VERBOSE || outcome === "MISS" || outcome === "FP" || outcome === "CRASH") {
      const edit = `${JSON.stringify(m.before)} -> ${JSON.stringify(m.repl)}`;
      console.log(`[${i + 1}/${mutants.length}] ${outcome.padEnd(6)} ${m.mutator} ${m.file}:${m.line}:${m.col} ${edit}`);
      for (const d of tscNew) console.log(`    tsc : ${d}`);
      for (const d of mtscNew) console.log(`    mtsc: ${d}`);
    }
  }
} finally {
  restore();
}

console.log("");
console.log(`${"mutator".padEnd(22)} ${"caught".padStart(6)} ${"miss".padStart(5)} ${"fp".padStart(4)} ${"tn".padStart(4)}  recall`);
const sum = { CAUGHT: 0, MISS: 0, FP: 0, TN: 0, CRASH: 0 };
for (const [name, c] of [...counts].sort()) {
  for (const k of Object.keys(sum)) sum[k] += c[k];
  const den = c.CAUGHT + c.MISS;
  console.log(`${name.padEnd(22)} ${String(c.CAUGHT).padStart(6)} ${String(c.MISS).padStart(5)} ${String(c.FP).padStart(4)} ${String(c.TN).padStart(4)}  ${den ? `${((100 * c.CAUGHT) / den).toFixed(0)}%` : "-"}`);
}
const den = sum.CAUGHT + sum.MISS;
console.log(`${"total".padEnd(22)} ${String(sum.CAUGHT).padStart(6)} ${String(sum.MISS).padStart(5)} ${String(sum.FP).padStart(4)} ${String(sum.TN).padStart(4)}  ${den ? `${((100 * sum.CAUGHT) / den).toFixed(0)}%` : "-"}${sum.CRASH ? `  (${sum.CRASH} crash)` : ""}`);
if (JSON_OUT) fs.writeFileSync(JSON_OUT, JSON.stringify(results, null, 1));
const declared = readDeclared();
const siteKey = (r) => `${r.file}:${r.line}:${r.col} ${r.mutator}`;
const ran = new Set(results.map(siteKey));
const fpKeys = new Set(results.filter((r) => r.outcome === "FP").map(siteKey));
const undeclared = results.filter((r) => r.outcome === "FP" && !declared.has(siteKey(r)));
const stale = [...declared.keys()].filter((k) => ran.has(k) && !fpKeys.has(k));
if (declared.size > 0) {
  const reproduced = [...declared.keys()].filter((k) => fpKeys.has(k)).length;
  console.log(`declared false positives: ${declared.size} (${reproduced} reproduced), undeclared: ${undeclared.length}`);
}
for (const k of stale) {
  console.log(`STALE: \`${k}\` is declared in ${path.relative(ROOT, DECLARED_PATH)} and is no longer a false positive — remove the entry`);
}
if (sum.CRASH > 0) {
  console.log(`FAIL: mtsc crashed on ${sum.CRASH} mutant(s)`);
  process.exit(1);
}
if (stale.length > 0) process.exit(1);
if (MAX_FP !== undefined && undeclared.length > MAX_FP) {
  console.log(`FAIL: ${undeclared.length} undeclared false positive(s), budget ${MAX_FP}`);
  process.exit(1);
}
