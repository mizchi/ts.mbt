// mtsc against terser on REAL bundles.
//
// `compare_terser.mjs` compares them rule by rule, on 34 hand-written
// cases. That answers "is the rule we thought of missing?" and it stood
// at 32 win / 0 loss while mtsc was 51% behind terser on a real library.
// Both statements were true: the corpus covers the rules somebody wrote
// a case for, and says nothing about the rest.
//
// So this asks the blunt question instead. Same input for both — each
// type-aware target's `mtsc --bundle` output, which is plain JavaScript
// with no optimization — and then:
//
//   terser   compress (2 passes) + mangle, its defaults otherwise.
//            `mangle.properties` stays OFF, which is terser's own
//            default and what its documentation recommends without a
//            hand-maintained reserved list.
//   mtsc     --treeshake --fold --minify --mangle, and separately with
//            --mangle-properties, since that has no terser counterpart
//            at default settings.
//
// GZIP IS REPORTED and it is the number to look at. Nobody ships
// unzipped JavaScript, and the two metrics disagree: mtsc has been
// smaller in raw bytes while LARGER gzipped on the same target (remeda
// -382 raw, +152 gzipped), which means the bytes it removed were bytes
// gzip would have removed anyway. A harness that only counts raw bytes
// scores the wrong thing.
//
// ---------------------------------------------------------------------
// `--rules`: what is each unported rule worth?
// ---------------------------------------------------------------------
//
// A gap total says nothing about what to do next. This mode asks TERSER
// to price its own rules: run it once normally, then once per rule with
// that rule disabled, and report the difference. That is the ceiling for
// porting the rule, measured before writing any of it.
//
// It corrected a ranking that had been made by COUNTING instead. mtsc
// emitted 9x fewer comma-fused statements than terser, so `sequences`
// looked like the biggest gap; priced, it is worth ~1,500 bytes across
// the corpus while `join_vars` is worth ~15,500. The count and the bytes
// point at different rules, and only one of them is the objective.
//
// READ THE SECOND TABLE. A rule's price to TERSER is not mtsc's
// headroom, and the difference is not subtle: `join_vars` is the most
// expensive rule in the first table (+15,522) and worth approximately
// NOTHING here, because much of what it cleans up is separate
// declarations terser's own `collapse_vars` / `reduce_vars` produced.
// On excalidraw mtsc emits 1,645 declaration keywords against terser's
// 1,714 — it already joins as much or more. The ceiling measures the
// rule inside terser's pipeline; whether mtsc needs it is a different
// question, and the structural counts below are the cheap proxy for it.
// A rule is worth porting only when BOTH say so.
//
// `--names` asks the third question, and on typebox it was the one that
// paid. Bytes alone say "+11,228" and the structural counts say "more
// functions"; the identifier-length distribution says 5,165 of those
// bytes are identifier CHARACTERS, and that 828 of mtsc's variable
// identifiers are four characters long against terser's four — in a
// bundle where neither has exhausted length 3. A mangled-name
// distribution cannot look like that, so those are names the mangler
// declined to rename, and naming them took a 2,440-byte fix.
//
// It counts identifiers in VARIABLE positions only. The first version
// counted every `Identifier` node, which in the TypeScript AST includes
// property names and object-literal keys — so typebox's JSON-Schema
// `type` key appeared 856 times and the "length-4 identifiers" column
// was mostly not identifiers at all. Mixing the mangler's name pool
// with the wire format answers a different question than the one asked.
//
//   node scripts/compare_terser_bundles.mjs
//   node scripts/compare_terser_bundles.mjs --rules
//   node scripts/compare_terser_bundles.mjs --names
//   node scripts/compare_terser_bundles.mjs --only typebox

import { spawnSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import zlib from "node:zlib";
import { minify } from "terser";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const WORK = path.join(ROOT, "_build", "terser-bundles");

const MTSC_CANDIDATES = [
  path.join(ROOT, "_build", "native", "release", "build", "cmd", "mtsc", "mtsc.exe"),
  path.join(ROOT, "_build", "native", "debug", "build", "cmd", "mtsc", "mtsc.exe"),
];
function findMtsc() {
  for (const c of MTSC_CANDIDATES) if (fs.existsSync(c)) return c;
  console.error("mtsc binary not found. Run `moon build --target native --release` first.");
  process.exit(2);
}
const MTSC = findMtsc();

// The unoptimized bundles `measure_type_aware.mjs` already produces.
// Running that harness first is what populates them; a missing one is
// reported rather than regenerated, because regenerating means cloning
// nine packages.
const TARGETS = [
  "hono",
  "valibot",
  "typebox",
  "immer",
  "neverthrow",
  "ts-pattern",
  "superstruct",
  "remeda",
  "excalidraw",
].map((name) => ({ name, input: path.join(ROOT, "_build", "type-aware", name, "unopt.mjs") }));

const MTSC_FLAGS = ["--bundle", "--treeshake", "--fold", "--minify", "--mangle", "--no-check"];
const MTSC_PROP_FLAGS = [...MTSC_FLAGS, "--mangle-properties"];

// One rule per row. Priced individually so each number is that rule's
// own contribution rather than a bundle of them.
const RULES = [
  "join_vars",
  "collapse_vars",
  "sequences",
  "reduce_funcs",
  "inline",
  "arrows",
  "conditionals",
  "comparisons",
];

const args = process.argv.slice(2);
let only = null;
let rules = false;
let names = false;
for (let i = 0; i < args.length; i++) {
  if (args[i] === "--only") only = args[++i];
  else if (args[i] === "--rules") rules = true;
  else if (args[i] === "--names") names = true;
  else {
    console.error(`unknown argument: ${args[i]}`);
    process.exit(2);
  }
}

const count = (s, re) => (s.match(re) ?? []).length;
const gz = (s) => zlib.gzipSync(Buffer.from(s, "utf8"), { level: 9 }).length;
const n = (v) => (v == null ? "—" : v.toLocaleString("en-US"));
const sgn = (v) => (v == null ? "—" : (v > 0 ? "+" : "") + n(v));
const pad = (s, w) => String(s).padEnd(w);
const padl = (s, w) => String(s).padStart(w);

fs.mkdirSync(WORK, { recursive: true });

function runMtsc(input, out, flags) {
  const r = spawnSync(MTSC, [input, ...flags, "--out", out], {
    encoding: "utf8",
    maxBuffer: 1 << 28,
    timeout: 900_000,
    killSignal: "SIGKILL",
  });
  if (r.status !== 0 || !fs.existsSync(out) || fs.statSync(out).size === 0) return null;
  return fs.readFileSync(out, "utf8");
}

async function runTerser(src, compressOverride = {}) {
  const res = await minify(src, {
    module: true,
    compress: { passes: 2, ...compressOverride },
    mangle: true,
    format: { comments: false },
  });
  return res.code;
}

const missing = [];
const rows = [];
for (const t of TARGETS) {
  if (only && t.name !== only) continue;
  if (!fs.existsSync(t.input)) {
    missing.push(t.name);
    continue;
  }
  const src = fs.readFileSync(t.input, "utf8");
  let terser = null;
  let terserErr = null;
  try {
    terser = await runTerser(src);
  } catch (e) {
    terserErr = String(e.message).slice(0, 100);
  }
  const mtsc = runMtsc(t.input, path.join(WORK, `${t.name}.mtsc.mjs`), MTSC_FLAGS);
  const mtscProps = runMtsc(
    t.input,
    path.join(WORK, `${t.name}.mtsc-props.mjs`),
    MTSC_PROP_FLAGS,
  );
  rows.push({ name: t.name, src, unopt: src.length, terser, terserErr, mtsc, mtscProps });
}

if (missing.length) {
  console.log(
    `\n  no unoptimized bundle for: ${missing.join(", ")}` +
      `\n  run \`just measure-type-aware\` first — it clones the packages and writes` +
      `\n  _build/type-aware/<name>/unopt.mjs, which is the shared input here.\n`,
  );
}

// ---------------------------------------------------------------------
// `--rules`: terser's own price for each rule
// ---------------------------------------------------------------------

if (rules) {
  console.log("\nterser's own price for each compress rule");
  console.log("  bytes the rule SAVES — the ceiling for porting it\n");
  console.log(`  ${pad("target", 12)} ${padl("terser", 9)} ` + RULES.map((r) => padl(r, 14)).join(""));
  const totals = Object.fromEntries(RULES.map((r) => [r, 0]));
  const gzTotals = Object.fromEntries(RULES.map((r) => [r, 0]));
  for (const row of rows) {
    if (!row.terser) continue;
    const raw = [];
    const zipped = [];
    for (const rule of RULES) {
      let off = null;
      try {
        off = await runTerser(row.src, { [rule]: false });
      } catch {
        raw.push(padl("—", 14));
        zipped.push(padl("—", 14));
        continue;
      }
      const d = off.length - row.terser.length;
      const dz = gz(off) - gz(row.terser);
      totals[rule] += d;
      gzTotals[rule] += dz;
      raw.push(padl(sgn(d), 14));
      zipped.push(padl(sgn(dz), 14));
    }
    console.log(`  ${pad(row.name, 12)} ${padl(n(row.terser.length), 9)} ` + raw.join(""));
    console.log(`  ${pad("", 12)} ${padl("(gzip)", 9)} ` + zipped.join(""));
  }
  console.log(
    `\n  ${pad("TOTAL", 12)} ${padl("", 9)} ` + RULES.map((r) => padl(sgn(totals[r]), 14)).join(""),
  );
  console.log(
    `  ${pad("", 12)} ${padl("(gzip)", 9)} ` + RULES.map((r) => padl(sgn(gzTotals[r]), 14)).join(""),
  );

  // Does mtsc already do it?
  //
  // The table above is terser pricing its rule inside terser's own
  // pipeline. Some of those rules exist to clean up after terser's
  // other rules, so a large number there can be a large number of
  // bytes mtsc never had to spend. `join_vars` is the case in point.
  //
  // Each probe is a crude structural count that the rule LOWERS, taken
  // on both optimizers' output for the same input. mtsc higher than
  // terser means headroom; mtsc at or below means the rule is already
  // covered and the price above is not a target. A proxy is not a
  // measurement — it says which rules are worth measuring properly.
  const PROBES = {
    join_vars: ["declaration keywords", (s) => count(s, /\b(?:let|const|var) /g)],
    sequences: ["statement separators", (s) => count(s, /;/g)],
    "arrows / reduce_funcs": ["`function` keywords", (s) => count(s, /\bfunction\b/g)],
    conditionals: ["`if (` statements", (s) => count(s, /\bif\s*\(/g)],
    comparisons: ["strict comparisons", (s) => count(s, /[=!]==/g)],
  };
  console.log("\n  does mtsc already do it? (structural proxies, lower = more optimized)\n");
  const names = Object.keys(PROBES);
  console.log(`  ${pad("target", 12)} ` + names.map((k) => padl(k.slice(0, 13), 15)).join(""));
  for (const row of rows) {
    if (!row.terser || !row.mtsc) continue;
    const cells = names.map((k) => {
      const [, probe] = PROBES[k];
      const t = probe(row.terser);
      const m = probe(row.mtsc);
      return padl(`${m}/${t}`, 15);
    });
    console.log(`  ${pad(row.name, 12)} ` + cells.join(""));
  }
  console.log(`\n  cells are mtsc/terser. ` + names.map((k) => `${k}: ${PROBES[k][0]}`).join("; ") + "\n");
  process.exit(0);
}

// ---------------------------------------------------------------------
// Head to head
// ---------------------------------------------------------------------

console.log("\nmtsc vs terser on real bundles");
console.log("  same input: `mtsc --bundle` output, no optimization\n");
console.log(
  `  ${pad("target", 12)} ${padl("unopt", 10)} ${padl("terser", 9)} ${padl("mtsc", 9)} ${padl("diff", 8)} ${padl("%", 7)}` +
    ` │ ${padl("gz terser", 9)} ${padl("gz mtsc", 9)} ${padl("diff", 8)} ${padl("%", 7)}`,
);
let rawWins = 0;
let gzWins = 0;
let counted = 0;
for (const row of rows) {
  if (!row.terser) {
    console.log(`  ${pad(row.name, 12)}  terser failed: ${row.terserErr}`);
    continue;
  }
  if (!row.mtsc) {
    console.log(`  ${pad(row.name, 12)}  mtsc failed`);
    continue;
  }
  counted++;
  const d = row.mtsc.length - row.terser.length;
  const gt = gz(row.terser);
  const gm = gz(row.mtsc);
  const dz = gm - gt;
  if (d < 0) rawWins++;
  if (dz < 0) gzWins++;
  console.log(
    `  ${pad(row.name, 12)} ${padl(n(row.unopt), 10)} ${padl(n(row.terser.length), 9)} ${padl(n(row.mtsc.length), 9)} ` +
      `${padl(sgn(d), 8)} ${padl(((d * 100) / row.terser.length).toFixed(1) + "%", 7)} │ ` +
      `${padl(n(gt), 9)} ${padl(n(gm), 9)} ${padl(sgn(dz), 8)} ${padl(((dz * 100) / gt).toFixed(1) + "%", 7)}`,
  );
}
console.log(
  `\n  mtsc smaller on ${rawWins}/${counted} raw, ${gzWins}/${counted} gzipped` +
    ` — gzipped is the one that ships\n`,
);

// `--mangle-properties` has no terser counterpart at default settings,
// so it is reported separately rather than folded into the comparison.
const propRows = rows.filter((r) => r.mtsc && r.mtscProps && r.mtscProps.length !== r.mtsc.length);
if (propRows.length) {
  console.log("  --mangle-properties, against mtsc's own output without it:\n");
  for (const row of propRows) {
    console.log(
      `    ${pad(row.name, 12)} ${padl(n(row.mtsc.length), 9)} -> ${padl(n(row.mtscProps.length), 9)}` +
        ` ${padl(sgn(row.mtscProps.length - row.mtsc.length), 8)}`,
    );
  }
  console.log("");
}

// --------------------------------------------------------------------
// `--names`: the identifier-length distribution.
// --------------------------------------------------------------------
//
// Only VARIABLE positions — see the header. A property name is not a
// candidate for the identifier mangler, and counting one makes the
// column unreadable.
if (names) {
  const ts = await import("typescript");
  const isVarPosition = (nd) => {
    const p = nd.parent;
    if (!p) return true;
    if (ts.isPropertyAccessExpression(p) && p.name === nd) return false;
    if (ts.isQualifiedName(p) && p.right === nd) return false;
    if (ts.isPropertyAssignment(p) && p.name === nd) return false;
    if (ts.isShorthandPropertyAssignment(p) && p.name === nd) return false;
    if (ts.isMethodDeclaration(p) && p.name === nd) return false;
    if (ts.isPropertyDeclaration(p) && p.name === nd) return false;
    if ((ts.isGetAccessor(p) || ts.isSetAccessor(p)) && p.name === nd) return false;
    if (ts.isImportSpecifier(p) || ts.isExportSpecifier(p)) return false;
    if (ts.isBindingElement(p) && p.propertyName === nd) return false;
    return true;
  };
  const measure = (code) => {
    const sf = ts.createSourceFile("x.mjs", code, ts.ScriptTarget.ESNext, true, ts.ScriptKind.JS);
    const byLen = new Map();
    const worst = new Map();
    let total = 0;
    let chars = 0;
    const visit = (nd) => {
      if (ts.isIdentifier(nd) && isVarPosition(nd)) {
        const L = nd.text.length;
        byLen.set(L, (byLen.get(L) ?? 0) + 1);
        if (L >= 4) worst.set(nd.text, (worst.get(nd.text) ?? 0) + 1);
        total++;
        chars += L;
      }
      nd.forEachChild(visit);
    };
    sf.forEachChild(visit);
    return { byLen, worst, total, chars };
  };

  console.log("  identifier lengths, VARIABLE positions only\n");
  const header =
    `  ${pad("target", 12)} ${pad("side", 7)} ${padl("idents", 8)} ${padl("chars", 9)}` +
    [1, 2, 3, 4, 5].map((l) => padl(`len${l}`, 7)).join("");
  console.log(header);
  for (const row of rows) {
    if (!row.mtsc || !row.terser) continue;
    for (const [side, code] of [["terser", row.terser], ["mtsc", row.mtsc]]) {
      const m = measure(code);
      console.log(
        `  ${pad(side === "terser" ? row.name : "", 12)} ${pad(side, 7)} ${padl(n(m.total), 8)} ${padl(n(m.chars), 9)}` +
          [1, 2, 3, 4, 5].map((l) => padl(n(m.byLen.get(l) ?? 0), 7)).join(""),
      );
    }
  }
  // A long name in mtsc's output and not in terser's is a name one
  // mangler renamed and the other did not — which is the actionable
  // half, so name them rather than only counting them.
  console.log("\n  mtsc's length>=4 variable identifiers that terser renamed away:\n");
  for (const row of rows) {
    if (!row.mtsc || !row.terser) continue;
    const mine = measure(row.mtsc).worst;
    const theirs = measure(row.terser).worst;
    const only4 = [...mine].filter(([k]) => !theirs.has(k)).sort((a, b) => b[1] - a[1]).slice(0, 5);
    if (!only4.length) continue;
    console.log(`    ${pad(row.name, 12)} ${only4.map(([k, v]) => `${k} x${v}`).join(", ")}`);
  }
  console.log("");
}
