// `fixtures/tsc-extra` — TypeScript test cases that the upstream suite
// (microsoft/TypeScript `tsc/testdata/tests/cases/{compiler,conformance}`)
// does not contain, written while probing tsc for this checker and kept in
// the upstream harness format so they can be contributed back.
//
// Three questions, in this order, because each one is only meaningful once
// the one before it holds:
//
//   1. BASELINE. Does TypeScript 7 (`node_modules/typescript`) still say what
//      the committed `baselines/<case>.errors.txt` says? The baseline is
//      written in the upstream `.errors.txt` shape, computed the way the
//      harness computes it: `// @option:` header lines are stripped before
//      the file is compiled, so line numbers are relative to what is left.
//      A case tsc accepts has NO baseline file, as upstream. A drift here is
//      a finding about TypeScript, not about mtsc, and is reported as such.
//
//   2. SELF-CONSISTENCY. A top-level declaration named `ok…` is a claim that
//      tsc accepts it and one named `bad…` a claim that tsc reports inside
//      it. The claims are checked against tsc's own spans, so a fixture
//      cannot say "legal" about a line tsc rejects — the "a test pinning a
//      gap" failure this repo has recorded sixteen times.
//
//   3. MTSC. `mtsc check` over the same file. An `ok…` declaration mtsc
//      reports on is a FALSE POSITIVE and fails the run; so does any report
//      in a file tsc accepts outright, and a parse failure on one. A `bad…`
//      declaration mtsc is silent on is a MISS, which fails only when it is
//      not declared in `fixtures/tsc-extra/mtsc-misses.txt` — and a declared
//      miss that no longer misses fails as STALE, which is what keeps that
//      file from becoming a suppression list. mtsc diagnostics carry no
//      offsets, so they are attributed to a declaration by their path
//      (`function okF > …`, `function okC.m > …`, `top-level > binding
//      \`okX\` …`).
//
// Usage:
//   node scripts/verify_tsc_extra.mjs [--update] [--no-mtsc] [--only SUBSTR]
//                                     [--mtsc PATH] [--upstream DIR] [--root DIR]
//                                     [--permissive]
//
//   --update      rewrite baselines from the current compiler (and delete
//                 the baseline of a case tsc now accepts)
//   --upstream    a checkout of the upstream `tsc/testdata/tests/cases`;
//                 every case basename is checked against it as well as
//                 against the vendored conformance name list, since a case
//                 that collides with an upstream name cannot be contributed
import fs from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { ts, directives, optionsJson, probeContent, unhonoured } from "./lib/tsc-probe.mjs";

const ROOT = path.resolve(path.dirname(new URL(import.meta.url).pathname), "..");
const argv = process.argv.slice(2);
const flag = (f) => argv.includes(f);
const value = (f) => {
  const i = argv.indexOf(f);
  return i >= 0 ? argv[i + 1] : undefined;
};
// `--root` points the harness at another fixture tree with the same layout,
// which is how candidates are triaged before they are moved in.
const FIX = path.resolve(value("--root") ?? path.join(ROOT, "fixtures", "tsc-extra"));
const CASES = path.join(FIX, "cases");
const BASELINES = path.join(FIX, "baselines");
const MISSES = path.join(FIX, "mtsc-misses.txt");
const update = flag("--update");
const useMtsc = !flag("--no-mtsc");
const only = value("--only");
const upstreamDir = value("--upstream");

// ---------------------------------------------------------------- cases

function walk(dir) {
  const out = [];
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, e.name);
    if (e.isDirectory()) out.push(...walk(p));
    else if (/\.tsx?$/.test(e.name) && !e.name.endsWith(".d.ts")) out.push(p);
  }
  return out.sort();
}

// The upstream harness's option regex: a line that STARTS with `//`, then
// `@name:`. Matched lines are removed from the compiled content entirely.
const OPTION_LINE = /^\/\/\s*@(\w+)\s*:\s*([^\r\n]*)\r?$/;

/** `{ content, options, problems }` for one case file. */
function readCase(file) {
  // A byte-order mark would hide the first option line from the regex; the
  // harness reads past it, and so does the compiler.
  const src = fs.readFileSync(file, "utf8").replace(/^\uFEFF/, "");
  const lines = src.split("\n");
  const kept = [];
  const problems = [];
  let header = true;
  for (const line of lines) {
    if (OPTION_LINE.test(line)) {
      if (!header) {
        // Upstream strips these wherever they are, `directives()` reads only
        // the header; a fixture must not depend on which reading wins.
        problems.push(`option line outside the header: ${line}`);
      }
      if (/^\/\/\s*@filename\s*:/i.test(line)) {
        problems.push("multi-file (`@filename`) cases are not supported here");
      }
      continue;
    }
    // The harness drops the blank lines between the option header and the
    // first line of content, so line numbers count from that line.
    if (header && line.trim() === "") continue;
    if (line.trim() !== "") header = false;
    kept.push(line);
  }
  for (const k of unhonoured(src)) {
    problems.push(`header option @${k} is not passed to tsc — add it to HONOURED in scripts/lib/tsc-probe.mjs`);
  }
  // The upstream harness never truncates a type in a message; the compiler's
  // default does, past a length a long union reaches (measured on
  // `conditionalTypes2`, whose baseline prints all 41 members).
  const options = { noErrorTruncation: true, ...optionsJson(directives(src)) };
  return { src, content: kept.join("\n"), options, problems };
}

// ------------------------------------------------------- errors.txt baseline

function lineStarts(text) {
  const starts = [0];
  for (let i = 0; i < text.length; i++) if (text[i] === "\n") starts.push(i + 1);
  return starts;
}

function lineOf(starts, pos) {
  let lo = 0;
  let hi = starts.length - 1;
  while (lo < hi) {
    const mid = (lo + hi + 1) >> 1;
    if (starts[mid] <= pos) lo = mid;
    else hi = mid - 1;
  }
  return lo;
}

const CATEGORY = ["warning", "error", "suggestion", "message"];

/** The message with its chain, each level indented two spaces, as `flattenDiagnosticMessageText(_, "\n")`. */
function messageLines(d) {
  const out = [d.text];
  const visit = (chain, depth) => {
    for (const c of chain ?? []) {
      out.push("  ".repeat(depth) + c.text);
      visit(c.messageChain, depth + 1);
    }
  };
  visit(d.chain, 1);
  return out;
}

/**
 * The upstream `.errors.txt` text for one file, following the harness's
 * `iterateErrorBaseline`: a header line per diagnostic, then the source
 * with squiggles under every span that touches a line and the messages of
 * the spans that END on it. Checked against the vendored TS7 baselines:
 * a single-file upstream case run through this function reproduces its
 * committed baseline byte for byte (modulo CRLF).
 */
function errorsTxt(name, content, diags) {
  const starts = lineStarts(content);
  // `\r\n` is one line break, as `computeLineStarts` counts it.
  const lines = content.split("\n").map((l) => l.replace(/\r$/, ""));
  const sorted = [...diags].sort(
    (a, b) =>
      (a.pos ?? -1) - (b.pos ?? -1) ||
      (a.end ?? 0) - (a.pos ?? 0) - ((b.end ?? 0) - (b.pos ?? 0)) ||
      a.code - b.code ||
      (a.text < b.text ? -1 : a.text > b.text ? 1 : 0),
  );
  const cat = (d) => CATEGORY[d.category] ?? "error";
  const header = [];
  for (const d of sorted) {
    const msg = messageLines(d).join("\n");
    if (d.pos === undefined) {
      header.push(`${cat(d)} TS${d.code}: ${msg}`);
    } else {
      const l = lineOf(starts, d.pos);
      header.push(`${name}(${l + 1},${d.pos - starts[l] + 1}): ${cat(d)} TS${d.code}: ${msg}`);
    }
  }
  // A related span in a lib file prints `--:--`, which keeps upstream
  // baselines stable across lib edits.
  const where = (r) => (/^lib\..*\.d\.ts$/.test(r.file) ? "--:--" : `${r.line}:${r.col}`);
  const bang = (d) => [
    ...messageLines(d).map((m) => `!!! ${cat(d)} TS${d.code}: ${m}`),
    ...(d.related ?? []).map((r) =>
      r.file ? `!!! related TS${r.code} ${r.file}:${where(r)}: ${r.text}` : `!!! related TS${r.code}: ${r.text}`,
    ),
  ];
  const body = [];
  for (const d of sorted) if (d.pos === undefined) body.push(...bang(d));
  const located = sorted.filter((d) => d.pos !== undefined);
  body.push(`==== ${name} (${located.length} errors) ====`);
  lines.forEach((line, i) => {
    body.push(`    ${line}`);
    const thisLineStart = starts[i];
    const nextLineStart = i + 1 < starts.length ? starts[i + 1] : content.length + 1;
    const last = i === lines.length - 1;
    for (const d of located) {
      const end = d.end;
      if (!(end >= thisLineStart && (d.pos < nextLineStart || last))) continue;
      const relativeOffset = d.pos - thisLineStart;
      const length = end - d.pos - Math.max(0, thisLineStart - d.pos);
      const squiggleStart = Math.max(0, relativeOffset);
      const width = Math.max(0, Math.min(length, line.length - squiggleStart));
      body.push(`    ${line.slice(0, squiggleStart).replace(/[^\s]/g, " ")}${"~".repeat(width)}`);
      if (last || nextLineStart > end) body.push(...bang(d));
    }
  });
  // Upstream baselines end at the last source line, with no final newline.
  return `${header.join("\n")}\n\n\n${body.join("\n")}`;
}

// --------------------------------------------------- top-level declarations

const DECL = [
  /^(?:export\s+)?(?:declare\s+)?(?:async\s+)?function\s*\*?\s*([A-Za-z_$][\w$]*)/,
  /^(?:export\s+)?(?:declare\s+)?(?:const|let|var|using)\s+([A-Za-z_$][\w$]*)/,
  /^(?:export\s+)?(?:declare\s+)?(?:abstract\s+)?class\s+([A-Za-z_$][\w$]*)/,
];
// `okX` / `badX`, or `OkX` / `BadX` for a class.
const CLAIM = /^(ok|bad|Ok|Bad)(?:[A-Z0-9_$]|$)/;

/** `[{ name, kind: "ok"|"bad", from, to }]`, zero-based inclusive line ranges. */
function claims(content) {
  const lines = content.split("\n");
  const starts = [];
  lines.forEach((line, i) => {
    if (/^\s/.test(line) || line === "" || /^[}\])]/.test(line) || line.startsWith("//")) return;
    let name = null;
    for (const re of DECL) {
      const m = line.match(re);
      if (m) {
        name = m[1];
        break;
      }
    }
    starts.push({ i, name });
  });
  const out = [];
  starts.forEach((s, k) => {
    const m = s.name && s.name.match(CLAIM);
    if (!m) return;
    const to = k + 1 < starts.length ? starts[k + 1].i - 1 : lines.length - 1;
    out.push({ name: s.name, kind: m[1].toLowerCase(), from: s.i, to });
  });
  return out;
}

// ------------------------------------------------------------------- mtsc

function mtscBinary() {
  const explicit = value("--mtsc");
  if (explicit) return explicit;
  // The newer of the two builds, as `checker_conformance_oracle.sh` picks:
  // a stale release binary beside a fresh debug one measures old code.
  const rel = path.join(ROOT, "_build/native/release/build/cmd/mtsc/mtsc.exe");
  const dbg = path.join(ROOT, "_build/native/debug/build/cmd/mtsc/mtsc.exe");
  const ok = [rel, dbg].filter((p) => fs.existsSync(p));
  ok.sort((a, b) => fs.statSync(b).mtimeMs - fs.statSync(a).mtimeMs);
  return ok[0];
}

/** `{ parseError: string|null, issues: [{ path, message }] }`. */
function runMtsc(bin, file) {
  // `--strict` is the unfiltered checker the unit tests call
  // (`check_module_function_bodies`); the default is the permissive filter
  // the conformance oracle runs. Strict reports a superset, so FP 0 here
  // implies FP 0 there, and its MISS count is the checker's real recall.
  const args = ["check", "-v", ...(flag("--permissive") ? [] : ["--strict"]), file];
  const r = spawnSync(bin, args, { encoding: "utf8" });
  const issues = [];
  let parseError = null;
  for (const line of `${r.stdout}\n${r.stderr}`.split("\n")) {
    const m = line.match(/^\s*ISSUE \[(.*?)\]: (.*)$/);
    if (m) issues.push({ path: m[1], message: m[2] });
    const p = line.match(/^parse error: (.*)$/);
    if (p) parseError = p[1];
  }
  if (r.status !== 0 && parseError === null) parseError = `exit ${r.status}: ${r.stderr.trim()}`;
  return { parseError, issues };
}

/**
 * The top-level declaration an mtsc issue path belongs to: a name, `""` for
 * a placed issue that names no declaration (`top-level > …` outside one),
 * or `null` for one with no position at all (`grammar`, from the parser's
 * marker channel), which can be attributed to nothing.
 */
function owner(issuePath) {
  let m = issuePath.match(/^function ([A-Za-z_$][\w$]*)(?:[.\s]|$)/);
  if (m) return m[1];
  m = issuePath.match(/^(?:class|top-level > class) ([A-Za-z_$][\w$]*)/);
  if (m) return m[1];
  m = issuePath.match(/^top-level > binding `([A-Za-z_$][\w$]*)`/);
  if (m) return m[1];
  if (issuePath.startsWith("top-level")) return "";
  return null;
}

function readMisses() {
  if (!fs.existsSync(MISSES)) return new Map();
  const out = new Map();
  for (const raw of fs.readFileSync(MISSES, "utf8").split("\n")) {
    const line = raw.replace(/#.*$/, "").trim();
    if (!line) continue;
    const [key, ...reason] = line.split(/\s+/);
    out.set(key, reason.join(" "));
  }
  return out;
}

// ------------------------------------------------------------------- names

function upstreamNames() {
  const names = new Set();
  const vendored = path.join(ROOT, "scripts/ts7_baselines/tsgo_ran_set.txt");
  if (fs.existsSync(vendored)) {
    for (const n of fs.readFileSync(vendored, "utf8").split("\n")) if (n) names.add(n.toLowerCase());
  }
  if (upstreamDir) {
    for (const f of walk(upstreamDir)) names.add(path.basename(f).replace(/\.tsx?$/, "").toLowerCase());
  }
  return names;
}

// -------------------------------------------------------------------- main

const files = walk(CASES).filter((f) => !only || f.includes(only));
const failures = [];
const notes = [];
const upstream = upstreamNames();
const seen = new Map();
const bin = useMtsc ? mtscBinary() : null;
if (useMtsc && !bin) {
  console.error("no mtsc binary: run `moon build --target native --release` (or pass --no-mtsc)");
  process.exit(2);
}
const declaredMisses = readMisses();
const observedMisses = new Set();
const counts = { cases: 0, accepted: 0, rejected: 0, ok: 0, bad: 0, fp: 0, miss: 0 };

for (const file of files) {
  const rel = path.relative(CASES, file);
  const base = path.basename(file);
  const stem = base.replace(/\.tsx?$/, "");
  counts.cases += 1;
  if (seen.has(stem.toLowerCase())) {
    failures.push(`${rel}: basename collides with ${seen.get(stem.toLowerCase())} (upstream baselines are flat)`);
  }
  seen.set(stem.toLowerCase(), rel);
  if (upstream.has(stem.toLowerCase())) {
    failures.push(`${rel}: an upstream test is already called ${stem}`);
  }
  const { content, options, problems } = readCase(file);
  for (const p of problems) failures.push(`${rel}: ${p}`);

  // 1. baseline
  const diags = probeContent(base, content, options);
  const baselineFile = path.join(BASELINES, `${stem}.errors.txt`);
  const want = diags.length > 0 ? errorsTxt(base, content, diags) : null;
  const have = fs.existsSync(baselineFile) ? fs.readFileSync(baselineFile, "utf8") : null;
  if (want === null) counts.accepted += 1;
  else counts.rejected += 1;
  if (update) {
    if (want === null) {
      if (have !== null) fs.rmSync(baselineFile);
    } else if (want !== have) {
      fs.mkdirSync(BASELINES, { recursive: true });
      fs.writeFileSync(baselineFile, want);
    }
  } else if (want !== have) {
    failures.push(
      `${rel}: TypeScript ${ts.version} no longer matches the committed baseline ` +
        `(${have === null ? "none" : "errors.txt"} -> ${want === null ? "accepted" : "errors"}); ` +
        "a change in tsc's answer — re-run with --update after reading the diff",
    );
  }

  // 2. self-consistency of ok…/bad… claims against tsc's spans
  const starts = lineStarts(content);
  const decls = claims(content);
  const tscLines = diags.filter((d) => d.pos !== undefined).map((d) => lineOf(starts, d.pos));
  const inside = (c) => tscLines.filter((l) => l >= c.from && l <= c.to).length;
  for (const c of decls) {
    const n = inside(c);
    if (c.kind === "ok" && n > 0) failures.push(`${rel}: \`${c.name}\` is named ok but tsc reports ${n} error(s) in it`);
    if (c.kind === "bad" && n === 0) failures.push(`${rel}: \`${c.name}\` is named bad but tsc accepts it`);
    counts[c.kind] += 1;
  }
  // tsc errors no declaration accounts for — including every file-level one
  // (TS2318 has no position), which no declaration can account for.
  const unclaimedTsc =
    tscLines.filter((l) => !decls.some((c) => l >= c.from && l <= c.to)).length +
    diags.filter((d) => d.pos === undefined).length;

  // 3. mtsc
  if (!useMtsc) continue;
  const m = runMtsc(bin, file);
  const fp = (why) => {
    counts.fp += 1;
    failures.push(`${rel}: mtsc FALSE POSITIVE — ${why}`);
  };
  const miss = (key, why) => {
    observedMisses.add(key);
    if (!declaredMisses.has(key)) {
      counts.miss += 1;
      failures.push(`${rel}: mtsc MISS not declared in mtsc-misses.txt — ${key}: ${why}`);
    }
  };
  if (m.parseError !== null) {
    if (diags.length === 0) fp(`parse failure on a file tsc accepts: ${m.parseError}`);
    else if (decls.length === 0) miss(`${stem}:*`, `parse failure (${m.parseError})`);
    for (const c of decls) {
      if (c.kind === "ok") fp(`parse failure takes \`${c.name}\` down with the file: ${m.parseError}`);
    }
    continue;
  }
  const byOwner = new Map();
  const unplaced = [];
  for (const i of m.issues) {
    const o = owner(i.path);
    if (o === null) {
      unplaced.push(i);
      continue;
    }
    const key = decls.some((c) => c.name === o) ? o : "";
    if (!byOwner.has(key)) byOwner.set(key, []);
    byOwner.get(key).push(i);
  }
  // A `bad…` declaration with no attributed report may be the one an
  // unplaced (`grammar`) report is about. Those are counted against the
  // silent `bad…` declarations in source order; the rest are MISSes.
  let spare = unplaced.length;
  for (const c of decls) {
    const got = byOwner.get(c.name) ?? [];
    if (c.kind === "ok" && got.length > 0) fp(`\`${c.name}\`: [${got[0].path}] ${got[0].message}`);
    if (c.kind === "bad" && got.length === 0) {
      if (spare > 0) spare -= 1;
      else miss(`${stem}:${c.name}`, "tsc reports, mtsc is silent");
    }
  }
  const loose = byOwner.get("") ?? [];
  if (diags.length === 0 && m.issues.length > 0) {
    fp(`tsc accepts the file: [${m.issues[0].path}] ${m.issues[0].message}`);
  } else if (decls.length > 0 && unclaimedTsc === 0 && loose.length > 0) {
    // Every tsc error sits inside a `bad…` declaration, so a placed report
    // that names none of them is about code tsc accepts.
    fp(`report outside every bad… declaration: [${loose[0].path}] ${loose[0].message}`);
  }
  if (decls.length === 0 && diags.length > 0 && m.issues.length === 0) {
    miss(`${stem}:*`, "tsc reports, mtsc is silent");
  }
}

for (const key of declaredMisses.keys()) {
  const stem = key.split(":")[0];
  const inScope = files.some((f) => path.basename(f).replace(/\.tsx?$/, "") === stem);
  if (useMtsc && inScope && !observedMisses.has(key)) {
    failures.push(`mtsc-misses.txt: STALE entry ${key} — mtsc no longer misses it; delete the line`);
  }
}
for (const b of fs.existsSync(BASELINES) ? fs.readdirSync(BASELINES) : []) {
  const stem = b.replace(/\.errors\.txt$/, "");
  if (!only && !seen.has(stem.toLowerCase())) {
    if (update) fs.rmSync(path.join(BASELINES, b));
    else failures.push(`baselines/${b}: no case of that name`);
  }
}

console.log(
  `tsc-extra: ${counts.cases} case(s) under TypeScript ${ts.version} — ` +
    `${counts.accepted} accepted, ${counts.rejected} with errors; ` +
    `${counts.ok} ok… / ${counts.bad} bad… declaration(s)` +
    (useMtsc
      ? `; mtsc (${path.relative(ROOT, bin)}): FP ${counts.fp}, undeclared MISS ${counts.miss}, ` +
        `declared MISS ${[...observedMisses].filter((k) => declaredMisses.has(k)).length}`
      : ""),
);
for (const n of notes) console.log(`  note: ${n}`);
if (failures.length > 0) {
  for (const f of failures) console.log(`  FAIL ${f}`);
  process.exit(1);
}
