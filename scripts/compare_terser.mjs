// Size comparison against terser, on the same real files.
//
// `verify_real_world_minify.mjs` answers "is the output still correct".
// This answers "how much smaller is it, next to the tool everyone
// actually uses". Both matter, and neither substitutes for the other: a
// minifier that wins on bytes by breaking the program has not won.
//
// So every column here is measured on output that ran. For React the
// harness re-runs the same render under each variant and reports whether
// the observations still match; a variant that changes behaviour is
// labelled BROKEN and its bytes stop being a result.
//
// Variants:
//   mtsc            --minify --bundle --mangle
//   mtsc +props     --minify --bundle --mangle --mangle-properties
//                   (the type-driven safe property rename — the thing
//                   this repo exists to do)
//   terser          --compress --mangle
//                   terser's default-safe setting; property mangling is
//                   off because terser cannot prove it safe.
//   terser +props   --compress --mangle --mangle-props
//                   terser's unsafe property rename, for reference. It
//                   renames every property it sees and leaves
//                   correctness to the user's test suite.
//
// Gzipped sizes are reported too, since that is what ships.
//
//   node scripts/compare_terser.mjs
//   node scripts/compare_terser.mjs --only react

import { spawnSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import zlib from "node:zlib";
import { fileURLToPath } from "node:url";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const WORK = path.join(ROOT, "_build", "real-world");
const TERSER_DIR = path.join(WORK, "terser");
const TERSER = path.join(TERSER_DIR, "node_modules", ".bin", "terser");

const MTSC_CANDIDATES = [
  path.join(ROOT, "_build", "native", "release", "build", "cmd", "mtsc", "mtsc.exe"),
  path.join(ROOT, "_build", "native", "debug", "build", "cmd", "mtsc", "mtsc.exe"),
];
const MTSC = MTSC_CANDIDATES.find((c) => fs.existsSync(c));
if (!MTSC) {
  console.error("mtsc binary not found. Run `moon build --target native` first.");
  process.exit(2);
}

const args = process.argv.slice(2);
let only = null;
for (let i = 0; i < args.length; i++) {
  if (args[i] === "--only") only = args[++i];
  else {
    console.error(`unknown argument: ${args[i]}`);
    process.exit(2);
  }
}

function run(cmd, argv, opts = {}) {
  return spawnSync(cmd, argv, {
    encoding: "utf8",
    maxBuffer: 1 << 28,
    timeout: opts.timeout ?? 3_600_000,
    cwd: opts.cwd ?? WORK,
  });
}

function ensureTerser() {
  if (fs.existsSync(TERSER)) return true;
  fs.mkdirSync(TERSER_DIR, { recursive: true });
  const pkg = path.join(TERSER_DIR, "package.json");
  if (!fs.existsSync(pkg)) {
    fs.writeFileSync(pkg, JSON.stringify({ name: "t", private: true, type: "commonjs" }) + "\n");
  }
  const r = run("npm", ["install", "--no-audit", "--no-fund", "terser"], { cwd: TERSER_DIR });
  if (r.status !== 0) {
    console.error("  npm install terser failed (needs network)");
    return false;
  }
  return true;
}

const gz = (file) => zlib.gzipSync(fs.readFileSync(file), { level: 9 }).length;
const num = (n) => n.toLocaleString("en-US");
const kb = (n) => (n / 1024).toFixed(1);

// One variant. Returns {bytes, gzip, seconds} or {failed}.
function build(variant, input, output) {
  const started = process.hrtime.bigint();
  let r;
  if (variant.tool === "mtsc") {
    // `--no-check` is for published `.js` input that was never
    // TypeScript. A TypeScript entry is expected to type-check, so it
    // does not get the flag and a diagnostic is a real failure.
    const noCheck = input.endsWith(".ts") || input.endsWith(".tsx") ? [] : ["--no-check"];
    r = run(MTSC, [input, ...noCheck, ...variant.flags, "--out", output]);
  } else {
    r = run(TERSER, [input, ...variant.flags, "-o", output]);
  }
  const seconds = Number(process.hrtime.bigint() - started) / 1e9;
  if (r.status !== 0 || !fs.existsSync(output) || fs.statSync(output).size === 0) {
    return { failed: (r.stderr || r.stdout || "").split("\n").filter(Boolean).slice(-1)[0] || `exit ${r.status}` };
  }
  const parse = run("node", ["--check", output]);
  if (parse.status !== 0) {
    return { failed: "output does not parse" };
  }
  return { bytes: fs.statSync(output).size, gzip: gz(output), seconds };
}

const VARIANTS = [
  { key: "mtsc", tool: "mtsc", flags: ["--minify", "--bundle", "--mangle"] },
  {
    key: "mtsc +props",
    tool: "mtsc",
    flags: ["--minify", "--bundle", "--mangle", "--mangle-properties"],
  },
  { key: "terser", tool: "terser", flags: ["--compress", "--mangle"] },
  {
    key: "terser +props",
    tool: "terser",
    flags: ["--compress", "--mangle", "--mangle-props"],
  },
];

const REACT_FILES = [
  "node_modules/react/cjs/react.development.js",
  "node_modules/react-dom/cjs/react-dom-server-legacy.node.development.js",
  "node_modules/react-dom/cjs/react-dom-server.node.development.js",
  "node_modules/react-dom/cjs/react-dom.development.js",
  "node_modules/scheduler/cjs/scheduler.development.js",
];

function table(rows, headers) {
  const widths = headers.map((h, i) =>
    Math.max(h.length, ...rows.map((r) => String(r[i]).length)),
  );
  const line = (cells) =>
    "  " + cells.map((c, i) => String(c).padStart(i === 0 ? -widths[i] : widths[i])).join("  ");
  const pad = (cells) =>
    "  " +
    cells
      .map((c, i) => (i === 0 ? String(c).padEnd(widths[i]) : String(c).padStart(widths[i])))
      .join("  ");
  console.log(pad(headers));
  console.log("  " + widths.map((w) => "-".repeat(w)).join("  "));
  for (const r of rows) console.log(pad(r));
  void line;
}

// ---------------------------------------------------------------------
// React: minify all five runtime files per variant, then re-run the same
// render so a byte count is never reported for output that misbehaves.
// ---------------------------------------------------------------------

function compareReact() {
  const dir = path.join(WORK, "react");
  const app = path.join(dir, "app.cjs");
  if (!fs.existsSync(app)) {
    console.log("  react: run verify_real_world_minify.mjs first (sets up the workspace)");
    return;
  }
  const files = REACT_FILES.map((rel) => ({
    rel,
    abs: path.join(dir, rel),
    orig: path.join(dir, `orig-${path.basename(rel)}`),
  })).filter((f) => fs.existsSync(f.orig) || fs.existsSync(f.abs));
  for (const f of files) if (!fs.existsSync(f.orig)) fs.copyFileSync(f.abs, f.orig);

  const baseline = run("node", [app], { cwd: dir });
  const before = files.reduce((n, f) => n + fs.statSync(f.orig).size, 0);
  const beforeGz = files.reduce((n, f) => n + gz(f.orig), 0);

  const rows = [["original", num(before), kb(beforeGz), "—", "—", "baseline"]];
  for (const v of VARIANTS) {
    let bytes = 0;
    let gzip = 0;
    let seconds = 0;
    let failed = null;
    const outs = [];
    for (const f of files) {
      const out = path.join(dir, `cmp-${v.key.replace(/[^a-z]/g, "")}-${path.basename(f.rel)}`);
      const r = build(v, f.orig, out);
      if (r.failed) {
        failed = `${path.basename(f.rel)}: ${r.failed}`;
        break;
      }
      bytes += r.bytes;
      gzip += r.gzip;
      seconds += r.seconds;
      outs.push({ f, out });
    }
    if (failed) {
      rows.push([v.key, "—", "—", "—", "—", `FAILED (${failed})`]);
      continue;
    }
    for (const o of outs) fs.copyFileSync(o.out, o.f.abs);
    const got = run("node", [app], { cwd: dir });
    for (const f of files) fs.copyFileSync(f.orig, f.abs);
    const ok = got.status === 0 && got.stdout === baseline.stdout;
    rows.push([
      v.key,
      num(bytes),
      kb(gzip),
      `${100 - Math.round((bytes * 100) / before)}%`,
      `${seconds.toFixed(1)}s`,
      ok ? "same observations" : got.status !== 0 ? "BROKEN (throws)" : "BROKEN (differs)",
    ]);
    for (const o of outs) fs.rmSync(o.out, { force: true });
  }
  console.log("\nreact + react-dom + scheduler (5 files)\n");
  table(rows, ["variant", "bytes", "gzip KiB", "smaller", "time", "behaviour"]);
}

// ---------------------------------------------------------------------
// The example application: no exports, so door 1 is empty. This is the
// shape the property rename was designed for, and the one a library can
// never have.
// ---------------------------------------------------------------------

function compareMinifyApp() {
  const entry = path.join(ROOT, "examples", "minify-app", "src", "main.ts");
  if (!fs.existsSync(entry)) {
    console.log("  minify-app: examples/minify-app is missing");
    return;
  }
  const dir = path.join(WORK, "minify-app");
  fs.mkdirSync(dir, { recursive: true });
  // The baseline is the unminified bundle, so terser and mtsc minify the
  // same input and the comparison is between minifiers rather than
  // between bundlers.
  const bundled = path.join(dir, "bundle.mjs");
  const b = run(MTSC, [entry, "--bundle", "--out", bundled]);
  if (b.status !== 0) {
    console.log(`  minify-app: bundle failed: ${(b.stdout || "").split("\n")[0]}`);
    return;
  }
  const want = run("node", [bundled], { cwd: dir });
  const before = fs.statSync(bundled).size;
  const rows = [["bundle (no minify)", num(before), kb(gz(bundled)), "\u2014", "baseline"]];
  const variants = [
    { key: "mtsc", tool: "mtsc", input: entry, flags: ["--bundle", "--minify", "--mangle"] },
    {
      key: "mtsc +props",
      tool: "mtsc",
      input: entry,
      flags: ["--bundle", "--minify", "--mangle", "--mangle-properties"],
    },
    { key: "terser", tool: "terser", input: bundled, flags: ["--module", "--compress", "--mangle"] },
    {
      key: "terser +props",
      tool: "terser",
      input: bundled,
      flags: ["--module", "--compress", "--mangle", "--mangle-props"],
    },
  ];
  for (const v of variants) {
    const out = path.join(dir, `${v.key.replace(/[^a-z]/g, "")}.mjs`);
    const r = build(v, v.input, out);
    if (r.failed) {
      rows.push([v.key, "\u2014", "\u2014", "\u2014", `FAILED (${r.failed})`]);
      continue;
    }
    const got = run("node", [out], { cwd: dir });
    const ok = got.status === 0 && got.stdout === want.stdout;
    rows.push([
      v.key,
      num(r.bytes),
      kb(r.gzip),
      `${100 - Math.round((r.bytes * 100) / before)}%`,
      ok ? "same output" : got.status !== 0 ? "BROKEN (throws)" : "BROKEN (wrong output)",
    ]);
  }
  console.log("\nexamples/minify-app (an application: no exports)\n");
  table(rows, ["variant", "bytes", "gzip KiB", "smaller", "behaviour"]);
}

// ---------------------------------------------------------------------
// The TypeScript compiler: one 9 MB file, and the behaviour check is
// "does it still compile TypeScript the same way".
// ---------------------------------------------------------------------

function compareTypescript() {
  const dir = path.join(WORK, "typescript");
  const lib = path.join(dir, "node_modules", "typescript", "lib", "typescript.js");
  const app = path.join(dir, "tsapp.cjs");
  if (!fs.existsSync(lib) || !fs.existsSync(app)) {
    console.log("  typescript: run verify_real_world_minify.mjs first (sets up the workspace)");
    return;
  }
  const baseline = run("node", [app, lib], { cwd: dir });
  const before = fs.statSync(lib).size;
  const rows = [["original", num(before), kb(gz(lib)), "—", "—", "baseline"]];
  for (const v of VARIANTS) {
    // The compiler resolves its default lib files relative to its own
    // path, so every variant has to run from inside `lib/`.
    const out = path.join(
      dir,
      "node_modules",
      "typescript",
      "lib",
      `cmp-${v.key.replace(/[^a-z]/g, "")}.js`,
    );
    const r = build(v, lib, out);
    if (r.failed) {
      rows.push([v.key, "—", "—", "—", "—", `FAILED (${r.failed})`]);
      continue;
    }
    const got = run("node", [app, out], { cwd: dir });
    const ok = got.status === 0 && got.stdout === baseline.stdout;
    rows.push([
      v.key,
      num(r.bytes),
      kb(r.gzip),
      `${100 - Math.round((r.bytes * 100) / before)}%`,
      `${r.seconds.toFixed(0)}s`,
      ok
        ? "same diagnostics"
        : got.status !== 0
          ? "BROKEN (throws)"
          : "BROKEN (wrong diagnostics)",
    ]);
    fs.rmSync(out, { force: true });
  }
  console.log("\ntypescript.js (the compiler, 9 MB)\n");
  table(rows, ["variant", "bytes", "gzip KiB", "smaller", "time", "behaviour"]);
}

console.log("size comparison against terser");
if (!ensureTerser()) process.exit(2);
const targets = {
  "minify-app": compareMinifyApp,
  react: compareReact,
  typescript: compareTypescript,
};
for (const [name, fn] of Object.entries(targets)) {
  if (only && only !== name) continue;
  fn();
}
console.log(
  "\n  terser does not read TypeScript, so `checker.ts` has no comparable column.",
);
