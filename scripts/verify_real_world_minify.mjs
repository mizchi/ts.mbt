// Minify real published packages and check the result still behaves.
//
// `verify_mangle_safety.mjs` asks "does this situation break?" over a
// corpus of situations somebody thought of. This asks the other
// question: take code nobody wrote for us, minify it, and see whether it
// still does the same thing. The two find different bugs — the parser
// failures and scope-hoist miscompiles that this script surfaced need a
// file large enough for a `<` and a later `> (` to line up, or for one
// switch block to hold two same-named `let`s, and no hand-written
// fixture is going to look like that.
//
// Targets:
//   react      react + react-dom + scheduler, rendered under Node and
//              diffed observation-by-observation against the pristine
//              install.
//   typescript the published 9 MB compiler bundle, minified and then
//              used to compile TypeScript — transpile output, real
//              checker diagnostics, and resolved types compared against
//              the original.
//   checker    src/compiler/checker.ts, 3 MB of real TypeScript source.
//              Not runnable on its own (it is one module of a graph), so
//              the assertion is that it compiles and that the output
//              parses.
//   hono       honojs/hono cloned from git and bundled from its 188
//              TypeScript source files — no npm, no prebuilt dist. Then
//              driven through routing, middleware, params, JSON and
//              error handling, with the responses diffed. This is the
//              target that exercises TS source directly, and the one
//              that found the linker exporting the wrong class.
//
// Needs network access on the first run: packages come from npm and
// checker.ts from the TypeScript repo, cached under _build/real-world.
// Not part of `just ci` for that reason.
//
//   node scripts/verify_real_world_minify.mjs              # all targets
//   node scripts/verify_real_world_minify.mjs --only react
//   node scripts/verify_real_world_minify.mjs --keep       # keep outputs

import { spawnSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const WORK = path.join(ROOT, "_build", "real-world");
const REACT_VERSION = "18.3.1";
const TS_VERSION = "5.7.3";

const MTSC_CANDIDATES = [
  path.join(ROOT, "_build", "native", "release", "build", "cmd", "mtsc", "mtsc.exe"),
  path.join(ROOT, "_build", "native", "debug", "build", "cmd", "mtsc", "mtsc.exe"),
];

function findMtsc() {
  for (const c of MTSC_CANDIDATES) if (fs.existsSync(c)) return c;
  console.error("mtsc binary not found. Run `moon build --target native` first.");
  process.exit(2);
}

const args = process.argv.slice(2);
let only = null;
let keep = false;
for (let i = 0; i < args.length; i++) {
  if (args[i] === "--only") only = args[++i];
  else if (args[i] === "--keep") keep = true;
  else {
    console.error(`unknown argument: ${args[i]}`);
    process.exit(2);
  }
}

const MTSC = findMtsc();
fs.mkdirSync(WORK, { recursive: true });

function run(cmd, argv, opts = {}) {
  return spawnSync(cmd, argv, {
    encoding: "utf8",
    maxBuffer: 1 << 28,
    timeout: opts.timeout ?? 3_600_000,
    cwd: opts.cwd ?? WORK,
    stdio: opts.inherit ? "inherit" : "pipe",
  });
}

function bytes(n) {
  return n.toLocaleString("en-US");
}

// One compile. Returns {ok, out, seconds} — a non-zero exit or a missing
// output file is a failure, and `--no-check` means type diagnostics are
// printed but never fatal (published .js is not TypeScript).
function minify(input, output, flags) {
  const started = process.hrtime.bigint();
  const r = run(MTSC, [input, "--no-check", ...flags, "--out", output]);
  const seconds = Number(process.hrtime.bigint() - started) / 1e9;
  const ok = r.status === 0 && fs.existsSync(output) && fs.statSync(output).size > 0;
  if (!ok) {
    const line = (r.stdout || "").split("\n").find((l) => l.includes("parse error"));
    return { ok: false, seconds, why: line || `exit ${r.status}` };
  }
  return { ok: true, seconds };
}

// A minifier that emits unparseable JavaScript is not a minifier, and
// nothing else in the suite checks this.
function parses(file) {
  const r = run("node", ["--check", file]);
  if (r.status === 0) return { ok: true };
  const m = (r.stderr || "").match(/SyntaxError.*/);
  return { ok: false, why: m ? m[0] : `exit ${r.status}` };
}

function npmInstall(dir, specs) {
  fs.mkdirSync(dir, { recursive: true });
  const pkg = path.join(dir, "package.json");
  if (!fs.existsSync(pkg)) {
    fs.writeFileSync(pkg, JSON.stringify({ name: "rw", private: true, type: "commonjs" }) + "\n");
  }
  const missing = specs.filter(
    (s) => !fs.existsSync(path.join(dir, "node_modules", s.split("@")[0])),
  );
  if (!missing.length) return true;
  const r = run("npm", ["install", "--no-audit", "--no-fund", ...missing], { cwd: dir });
  if (r.status !== 0) {
    console.error(`  npm install failed: ${(r.stderr || "").trim().split("\n").slice(-3).join(" ")}`);
    return false;
  }
  return true;
}

const results = [];
function record(target, pass, detail) {
  results.push({ target, pass, detail });
  console.log(`  ${pass ? "[ok  ]" : "[FAIL]"} ${target.padEnd(28)} ${detail}`);
}

// ---------------------------------------------------------------------
// The React stack: minify every runtime file at once, then re-run the
// same render and diff the observations.
// ---------------------------------------------------------------------

const REACT_FILES = [
  "node_modules/react/cjs/react.development.js",
  "node_modules/react-dom/cjs/react-dom-server-legacy.node.development.js",
  "node_modules/react-dom/cjs/react-dom-server.node.development.js",
  "node_modules/react-dom/cjs/react-dom.development.js",
  "node_modules/scheduler/cjs/scheduler.development.js",
];

const REACT_APP = `// Exercise enough of React that a bad rename shows up: hooks, context,
// memo, refs, an error boundary, fragments, keys, and server rendering.
const React = require("react");
const { renderToStaticMarkup, renderToString } = require("react-dom/server");
const Ctx = React.createContext("ctx-default");
function Counter({ start }) {
  const [n, setN] = React.useState(start);
  const doubled = React.useMemo(() => n * 2, [n]);
  const cb = React.useCallback(() => setN((v) => v + 1), []);
  const ref = React.useRef(null);
  React.useEffect(() => {}, []);
  const ctx = React.useContext(Ctx);
  return React.createElement("div", { className: "counter", "data-doubled": doubled, ref },
    React.createElement("span", null, \`n=\${n}\`),
    React.createElement("button", { onClick: cb }, "inc"),
    React.createElement("em", null, ctx));
}
const Memoized = React.memo(function Item({ label }) {
  return React.createElement("li", null, label);
});
class Boundary extends React.Component {
  constructor(props) { super(props); this.state = { failed: false }; }
  static getDerivedStateFromError() { return { failed: true }; }
  render() {
    return this.state.failed ? React.createElement("p", null, "caught") : this.props.children;
  }
}
const tree = React.createElement(Ctx.Provider, { value: "from-provider" },
  React.createElement(Boundary, null,
    React.createElement(React.Fragment, null,
      React.createElement(Counter, { start: 3 }),
      React.createElement("ul", null,
        ["a", "b", "c"].map((l) => React.createElement(Memoized, { key: l, label: l }))))));
process.stdout.write(JSON.stringify({
  version: React.version,
  staticMarkup: renderToStaticMarkup(tree),
  hydratableMarkup: renderToString(tree),
  isValidElement: React.isValidElement(tree),
  childCount: React.Children.count(React.createElement("i", null, "x", "y", "z").props.children),
  clonedProps: Object.keys(React.cloneElement(React.createElement("b", { a: 1 }), { c: 2 }).props).sort(),
  elementKeys: Object.keys(React.createElement("b", { a: 1 })).sort(),
  exportNames: Object.keys(React).sort(),
}, null, 2) + "\\n");
`;

function verifyReact() {
  const dir = path.join(WORK, "react");
  if (!npmInstall(dir, [`react@${REACT_VERSION}`, `react-dom@${REACT_VERSION}`])) {
    record("react", false, "npm install failed");
    return;
  }
  const app = path.join(dir, "app.cjs");
  fs.writeFileSync(app, REACT_APP);

  const baseline = run("node", [app], { cwd: dir });
  if (baseline.status !== 0) {
    record("react", false, `pristine run failed: ${(baseline.stderr || "").split("\n")[0]}`);
    return;
  }

  // Keep a pristine copy of each file, compile from it, swap the output
  // in, run, then restore. Compiling from the copy keeps a failed run
  // from leaving a minified file behind as the next run's input.
  const originals = [];
  for (const rel of REACT_FILES) {
    const abs = path.join(dir, rel);
    if (!fs.existsSync(abs)) continue;
    const orig = path.join(dir, `orig-${path.basename(rel)}`);
    if (!fs.existsSync(orig)) fs.copyFileSync(abs, orig);
    originals.push({ rel, abs, orig });
  }

  let before = 0;
  let after = 0;
  const problems = [];
  for (const f of originals) {
    const out = path.join(dir, `min-${path.basename(f.rel)}`);
    const m = minify(f.orig, out, ["--minify", "--bundle", "--mangle", "--mangle-properties"]);
    if (!m.ok) {
      problems.push(`${path.basename(f.rel)}: compile failed (${m.why})`);
      continue;
    }
    const p = parses(out);
    if (!p.ok) problems.push(`${path.basename(f.rel)}: ${p.why}`);
    before += fs.statSync(f.orig).size;
    after += fs.statSync(out).size;
    fs.copyFileSync(out, f.abs);
  }

  const got = run("node", [app], { cwd: dir });
  for (const f of originals) fs.copyFileSync(f.orig, f.abs);

  if (problems.length) {
    record("react", false, problems.join("; "));
    return;
  }
  if (got.status !== 0) {
    record("react", false, `minified run failed: ${(got.stderr || "").split("\n").slice(0, 2).join(" ")}`);
    return;
  }
  if (got.stdout !== baseline.stdout) {
    fs.writeFileSync(path.join(dir, "baseline.json"), baseline.stdout);
    fs.writeFileSync(path.join(dir, "got.json"), got.stdout);
    record("react", false, `observations differ (see ${path.relative(ROOT, dir)}/{baseline,got}.json)`);
    return;
  }
  const pct = 100 - Math.round((after * 100) / before);
  record(
    "react",
    true,
    `${originals.length} files ${bytes(before)} -> ${bytes(after)} bytes (${pct}% smaller), identical observations`,
  );
}

// ---------------------------------------------------------------------
// The TypeScript compiler: minify it, then compile with it.
// ---------------------------------------------------------------------

const TS_APP = `// Drive a TypeScript build through work that reaches the checker.
const path = require("node:path");
const ts = require(path.resolve(process.argv[2]));
const SRC = \`
interface Shape { kind: "circle" | "square"; size: number }
function area(s: Shape): number {
  switch (s.kind) {
    case "circle": return Math.PI * s.size ** 2;
    case "square": return s.size * s.size;
  }
}
const bad: string = area({ kind: "circle", size: 2 });
const good: number = area({ kind: "square", size: 3 });
export const answers = [bad, good] as const;
class Box<T> { constructor(readonly v: T) {} map<U>(f: (t: T) => U) { return new Box(f(this.v)); } }
export const boxed = new Box(1).map((n) => n.toFixed(2));
const missing = notDeclared + 1;
\`;
const transpiled = ts.transpileModule(SRC, {
  compilerOptions: { target: ts.ScriptTarget.ES2020, module: ts.ModuleKind.ESNext },
});
const host = ts.createCompilerHost({ strict: true });
const originalGet = host.getSourceFile.bind(host);
host.getSourceFile = (name, langVersion, ...rest) =>
  name === "in.ts"
    ? ts.createSourceFile(name, SRC, langVersion, true, ts.ScriptKind.TS)
    : originalGet(name, langVersion, ...rest);
host.writeFile = () => {};
const program = ts.createProgram(["in.ts"],
  { strict: true, noEmit: true, target: ts.ScriptTarget.ES2020 }, host);
const diags = ts.getPreEmitDiagnostics(program)
  .filter((d) => d.file && d.file.fileName === "in.ts")
  .map((d) => ({
    code: d.code,
    line: d.file.getLineAndCharacterOfPosition(d.start).line + 1,
    message: ts.flattenDiagnosticMessageText(d.messageText, " "),
  }))
  .sort((a, b) => a.line - b.line || a.code - b.code);
const checker = program.getTypeChecker();
const sf = program.getSourceFile("in.ts");
const typeOf = (name) => {
  let found = null;
  const walk = (n) => {
    if (ts.isVariableDeclaration(n) && n.name.getText(sf) === name) found = n;
    ts.forEachChild(n, walk);
  };
  walk(sf);
  return found ? checker.typeToString(checker.getTypeAtLocation(found.name)) : null;
};
process.stdout.write(JSON.stringify({
  version: ts.version,
  transpiledOutput: transpiled.outputText.trim(),
  diagnostics: diags,
  typeOfGood: typeOf("good"),
  typeOfBoxed: typeOf("boxed"),
  syntaxKindSample: [ts.SyntaxKind.CallExpression, ts.SyntaxKind[ts.SyntaxKind.CallExpression]],
  apiNames: ["createProgram", "createSourceFile", "transpileModule", "getPreEmitDiagnostics", "version"]
    .map((k) => [k, typeof ts[k]]),
}, null, 2) + "\\n");
`;

function verifyTypescript() {
  const dir = path.join(WORK, "typescript");
  if (!npmInstall(dir, [`typescript@${TS_VERSION}`])) {
    record("typescript", false, "npm install failed");
    return;
  }
  const lib = path.join(dir, "node_modules", "typescript", "lib", "typescript.js");
  const app = path.join(dir, "tsapp.cjs");
  fs.writeFileSync(app, TS_APP);

  const baseline = run("node", [app, lib], { cwd: dir });
  if (baseline.status !== 0) {
    record("typescript", false, `pristine run failed: ${(baseline.stderr || "").split("\n")[0]}`);
    return;
  }

  // The output has to live in the package's own `lib/` directory.
  // TypeScript resolves its default `lib.*.d.ts` files relative to the
  // executing file, so a compiler run from anywhere else silently
  // type-checks against no lib at all — `Math` becomes an unknown name.
  // A pristine copy placed outside `lib/` reproduces that exactly, which
  // is how this was ruled out as a minifier bug the first time it showed
  // up.
  const out = path.join(dir, "node_modules", "typescript", "lib", "typescript.min.js");
  const m = minify(lib, out, ["--minify", "--bundle", "--mangle"]);
  if (!m.ok) {
    record("typescript", false, `compile failed (${m.why})`);
    return;
  }
  const p = parses(out);
  if (!p.ok) {
    record("typescript", false, p.why);
    return;
  }
  const got = run("node", [app, out], { cwd: dir });
  if (got.status !== 0) {
    record("typescript", false, `minified compiler failed: ${(got.stderr || "").split("\n").slice(0, 2).join(" ")}`);
    return;
  }
  if (got.stdout !== baseline.stdout) {
    fs.writeFileSync(path.join(dir, "baseline.json"), baseline.stdout);
    fs.writeFileSync(path.join(dir, "got.json"), got.stdout);
    record("typescript", false, `diagnostics differ (see ${path.relative(ROOT, dir)}/{baseline,got}.json)`);
    return;
  }
  const b = fs.statSync(lib).size;
  const a = fs.statSync(out).size;
  record(
    "typescript",
    true,
    `${bytes(b)} -> ${bytes(a)} bytes (${100 - Math.round((a * 100) / b)}% smaller) in ${m.seconds.toFixed(0)}s, compiles TypeScript identically`,
  );
  if (!keep) fs.rmSync(out, { force: true });
  return;
}

// ---------------------------------------------------------------------
// hono: a TypeScript library, cloned and bundled from source. The point
// of this target is that nothing prebuilt is involved — mtsc does the
// TS -> JS -> bundle -> minify job that tsc + a bundler + terser would
// otherwise split between them.
// ---------------------------------------------------------------------

const HONO_APP = `// Exercise routing, middleware, params, query, JSON, headers, 404 and
// error handling — enough that a bad rename or a mis-linked export shows
// up as a changed response rather than as nothing at all.
import { Hono } from "./hono.mjs";
const app = new Hono();
app.use("*", async (c, next) => {
  await next();
  c.header("X-Trace", "on");
});
app.get("/", (c) => c.text("root"));
app.get("/users/:id", (c) => c.json({ id: c.req.param("id"), q: c.req.query("q") ?? null }));
app.post("/echo", async (c) => c.json({ got: await c.req.json() }));
app.get("/boom", () => {
  throw new Error("boom");
});
app.notFound((c) => c.text("nope", 404));
app.onError((e, c) => c.json({ error: e.message }, 500));
const calls = [
  ["GET", "http://x/"],
  ["GET", "http://x/users/42?q=hi"],
  ["POST", "http://x/echo", JSON.stringify({ a: 1, nested: { b: [1, 2] } })],
  ["GET", "http://x/boom"],
  ["GET", "http://x/missing"],
];
const out = [];
for (const [method, url, body] of calls) {
  const res = await app.fetch(
    new Request(url, {
      method,
      body: body ?? undefined,
      headers: body ? { "content-type": "application/json" } : {},
    }),
  );
  out.push({
    url,
    status: res.status,
    trace: res.headers.get("X-Trace"),
    contentType: res.headers.get("content-type"),
    body: await res.text(),
  });
}
console.log(JSON.stringify(out, null, 2));
`;

function verifyHono() {
  const dir = path.join(WORK, "hono");
  const checkout = path.join(dir, "hono");
  fs.mkdirSync(dir, { recursive: true });
  if (!fs.existsSync(path.join(checkout, "src", "index.ts"))) {
    const r = run("git", [
      "clone",
      "--depth",
      "1",
      "https://github.com/honojs/hono",
      checkout,
    ], { timeout: 900_000 });
    if (r.status !== 0) {
      record("hono", false, "git clone failed (needs network)");
      return;
    }
  }
  const entry = path.join(checkout, "src", "index.ts");
  const app = path.join(dir, "app.mjs");
  fs.writeFileSync(app, HONO_APP);

  // The unminified bundle is the reference: mtsc already did TS -> JS
  // there, so a later difference is the minifier's and not the
  // compiler's.
  const base = path.join(dir, "base.mjs");
  const b = minify(entry, base, ["--bundle"]);
  if (!b.ok) {
    record("hono", false, `bundle failed (${b.why})`);
    return;
  }
  fs.copyFileSync(base, path.join(dir, "hono.mjs"));
  const want = run("node", [app], { cwd: dir });
  if (want.status !== 0) {
    record("hono", false, `bundle does not run: ${(want.stderr || "").split("\n").slice(0, 2).join(" ")}`);
    return;
  }
  const out = path.join(dir, "min.mjs");
  const m = minify(entry, out, ["--bundle", "--minify", "--mangle", "--mangle-properties"]);
  if (!m.ok) {
    record("hono", false, `minify failed (${m.why})`);
    return;
  }
  const p = parses(out);
  if (!p.ok) {
    record("hono", false, p.why);
    return;
  }
  fs.copyFileSync(out, path.join(dir, "hono.mjs"));
  const got = run("node", [app], { cwd: dir });
  fs.copyFileSync(base, path.join(dir, "hono.mjs"));
  if (got.status !== 0) {
    record("hono", false, `minified run failed: ${(got.stderr || "").split("\n").slice(0, 2).join(" ")}`);
    return;
  }
  if (got.stdout !== want.stdout) {
    fs.writeFileSync(path.join(dir, "baseline.json"), want.stdout);
    fs.writeFileSync(path.join(dir, "got.json"), got.stdout);
    record("hono", false, `responses differ (see ${path.relative(ROOT, dir)}/{baseline,got}.json)`);
    return;
  }
  const srcFiles = run("bash", [
    "-c",
    `find ${JSON.stringify(path.join(checkout, "src"))} -name '*.ts' ! -name '*.test.ts' | wc -l`,
  ]);
  const before = fs.statSync(base).size;
  const after = fs.statSync(out).size;
  record(
    "hono",
    true,
    `${(srcFiles.stdout || "?").trim()} TS source files -> ${bytes(after)} bytes ` +
      `(${100 - Math.round((after * 100) / before)}% under the unminified bundle), identical responses`,
  );
  if (!keep) fs.rmSync(out, { force: true });
}

// ---------------------------------------------------------------------
// checker.ts: 3 MB of real TypeScript source. One module of a graph, so
// the bar is "compiles, and the output parses".
// ---------------------------------------------------------------------

function verifyCheckerSource() {
  const dir = path.join(WORK, "checker");
  fs.mkdirSync(dir, { recursive: true });
  const src = path.join(dir, "checker.ts");
  if (!fs.existsSync(src)) {
    const url = `https://raw.githubusercontent.com/microsoft/TypeScript/v${TS_VERSION}/src/compiler/checker.ts`;
    const r = run("curl", ["-sSL", "--max-time", "120", "-o", src, url]);
    if (r.status !== 0 || !fs.existsSync(src) || fs.statSync(src).size < 1_000_000) {
      record("checker.ts", false, "download failed (needs network)");
      return;
    }
  }
  const out = path.join(dir, "checker.min.js");
  const m = minify(src, out, ["--minify"]);
  if (!m.ok) {
    record("checker.ts", false, `compile failed (${m.why})`);
    return;
  }
  const p = parses(out);
  if (!p.ok) {
    record("checker.ts", false, p.why);
    return;
  }
  const b = fs.statSync(src).size;
  const a = fs.statSync(out).size;
  record(
    "checker.ts",
    true,
    `${bytes(b)} -> ${bytes(a)} bytes (${100 - Math.round((a * 100) / b)}% smaller) in ${m.seconds.toFixed(0)}s, output parses`,
  );
  if (!keep) fs.rmSync(out, { force: true });
}

console.log("real-world minify validation\n");
const targets = {
  hono: verifyHono,
  react: verifyReact,
  typescript: verifyTypescript,
  "checker.ts": verifyCheckerSource,
};
for (const [name, fn] of Object.entries(targets)) {
  if (only && only !== name) continue;
  fn();
}
const failed = results.filter((r) => !r.pass).length;
console.log(`\n  ${results.length} target(s): ${results.length - failed} pass, ${failed} fail`);
process.exit(failed ? 1 : 0);
