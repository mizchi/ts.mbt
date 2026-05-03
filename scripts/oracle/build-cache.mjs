// Build oracle resolution caches for one or more packages by:
//   1. scanning the bridge.mbti for `Unresolved type reference <Name>`
//      notes (so the request list mirrors what the in-house lowering
//      actually failed on),
//   2. asking the tsc-backed oracle (`resolve-types.mjs`) to resolve
//      each name against the package's entry .d.ts, and
//   3. dropping resolutions that are not actionable — anything that
//      came back as the same `Named(name)` (no expansion) or as an
//      `unknown_shape` (the JS oracle declined to serialise).
//
// Output: `_build/oracle-cache/<pkg>.json`, in the same wire format the
// MoonBit reader (`src/bridge/oracle.mbt`) expects.
//
// Usage:
//   node scripts/oracle/build-cache.mjs --pkg <name> --entry <.d.ts> --bridge-mbti <path>
//   node scripts/oracle/build-cache.mjs --all   (read scripts/oracle/packages.json)

import fs from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(__dirname, "..", "..");
const oracleScript = path.join(__dirname, "resolve-types.mjs");

function parseArgs(argv) {
  const opts = { all: false };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === "--all") opts.all = true;
    else if (a === "--pkg") opts.pkg = argv[++i];
    else if (a === "--entry") opts.entry = argv[++i];
    else if (a === "--bridge-mbti") opts.bridgeMbti = argv[++i];
    else if (a === "--out-dir") opts.outDir = argv[++i];
  }
  return opts;
}

function readUnresolvedNames(mbtiPath) {
  if (!fs.existsSync(mbtiPath)) return [];
  const text = fs.readFileSync(mbtiPath, "utf8");
  const names = new Set();
  const re = /Unresolved type reference ([A-Za-z_][A-Za-z0-9_]*)/g;
  let m;
  while ((m = re.exec(text))) names.add(m[1]);
  return [...names].sort();
}

function isUseful(resolution) {
  if (!resolution.ok || !resolution.type) return false;
  const t = resolution.type;
  if (t.kind === "unknown_shape") return false;
  // A `Named(<same name>)` is what tsc returns for an interface / class
  // looked up by name — no new information for the bridge.
  if (t.kind === "named" && t.name === resolution.key) return false;
  // Plain primitive widening (`any` / `unknown`) is rarely an upgrade —
  // the in-house lowering would have done the same thing. Keep them
  // out of the cache so we don't churn the bridge output for nothing.
  if (t.kind === "any" || t.kind === "void" || t.kind === "never") return false;
  return true;
}

function runOracle(entries, requests) {
  const reqJson = JSON.stringify({ entries, requests });
  const tmp = path.join(repoRoot, "_build", "oracle-cache", `_request_${process.pid}.json`);
  fs.mkdirSync(path.dirname(tmp), { recursive: true });
  fs.writeFileSync(tmp, reqJson);
  try {
    const r = spawnSync("node", [oracleScript, tmp, "-"], {
      stdio: ["ignore", "pipe", "inherit"],
      maxBuffer: 64 * 1024 * 1024,
    });
    if (r.status !== 0) {
      throw new Error(`oracle script exited with status ${r.status}`);
    }
    return JSON.parse(r.stdout.toString("utf8"));
  } finally {
    try { fs.unlinkSync(tmp); } catch {}
  }
}

function buildCache(pkg, entryPath, bridgeMbtiPath, outDir) {
  const names = readUnresolvedNames(bridgeMbtiPath);
  if (names.length === 0) {
    process.stderr.write(`[${pkg}] no unresolved names — skipping\n`);
    return { kept: 0, total: 0 };
  }
  const requests = names.map((n) => ({ key: n, alias_name: n }));
  const result = runOracle([entryPath], requests);
  const kept = result.resolutions.filter(isUseful);
  fs.mkdirSync(outDir, { recursive: true });
  const outPath = path.join(outDir, `${pkg}.json`);
  fs.writeFileSync(outPath, JSON.stringify({ resolutions: kept }, null, 2));
  process.stderr.write(
    `[${pkg}] requested=${names.length} kept=${kept.length} -> ${outPath}\n`
  );
  return { kept: kept.length, total: names.length };
}

function main() {
  const opts = parseArgs(process.argv.slice(2));
  const outDir = opts.outDir
    ? path.resolve(opts.outDir)
    : path.join(repoRoot, "_build", "oracle-cache");

  if (opts.all) {
    const config = JSON.parse(
      fs.readFileSync(path.join(__dirname, "packages.json"), "utf8")
    );
    let totalKept = 0;
    let totalRequested = 0;
    for (const entry of config.packages) {
      const r = buildCache(
        entry.pkg,
        entry.entry,
        path.resolve(repoRoot, entry.bridge_mbti),
        outDir
      );
      totalKept += r.kept;
      totalRequested += r.total;
    }
    process.stderr.write(
      `total: kept=${totalKept} / requested=${totalRequested}\n`
    );
    return;
  }

  if (!opts.pkg || !opts.entry || !opts.bridgeMbti) {
    process.stderr.write(
      "usage: node build-cache.mjs --pkg <name> --entry <.d.ts> --bridge-mbti <path> [--out-dir <dir>]\n" +
        "       node build-cache.mjs --all\n"
    );
    process.exit(2);
  }

  buildCache(opts.pkg, path.resolve(opts.entry), path.resolve(opts.bridgeMbti), outDir);
}

main();
