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
// Every row compiles a library's PACKAGE entry by default. `--app`
// compiles an APPLICATION that consumes the library instead, from
// `fixtures/type-aware-corpus/app-entries/`, and keeps its own
// `expected.app.json`. See the block above `stageAppEntry` for why the
// distinction matters and where the usage in each app entry comes from.
//
//   node scripts/measure_type_aware.mjs
//   node scripts/measure_type_aware.mjs --app
//   node scripts/measure_type_aware.mjs --only hono --verbose
//   node scripts/measure_type_aware.mjs --update      # re-record expected.json
//   node scripts/measure_type_aware.mjs --keep        # keep the leg outputs
//   node scripts/measure_type_aware.mjs --phases      # per-phase byte attribution

import { spawnSync } from "node:child_process";
import fs from "node:fs";
import zlib from "node:zlib";
import path from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const WORK = path.join(ROOT, "_build", "type-aware");
const FIXTURES = path.join(ROOT, "fixtures", "type-aware-corpus");
const APP_ENTRIES = path.join(FIXTURES, "app-entries");

// Flags shared by `aware` and `blind`.
//
// `--mangle-properties` was deliberately absent for a long time, because
// the property mangler was inert on every library here: the observability
// analysis reserved the WILDCARD, so no user-declared property name was
// renamed and the flag changed no byte on either leg.
//
// The cause turned out to be narrower than "the analysis is
// fail-closed". A `const f = (…) => …` had no entry in the graph's
// function table — arrows were indexed by a FuncExpr's internal name and
// have none — so a call to one was treated as opaque and marked
// `External`, which IS the wildcard. One such arrow poisons the whole
// bundle, and neverthrow's only cause was a single
// `export const createNeverThrowError`. With arrows given their
// declared name as an identity, the flag moves real bytes (hono
// -2107, -9.4%), so it belongs in the measured set.
const OPT_FLAGS = [
  "--treeshake",
  "--fold",
  "--minify",
  "--mangle",
  "--mangle-properties",
];

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
    appEntry: "hono.app.ts",
  },
  {
    name: "valibot",
    repo: "https://github.com/fabian-hiller/valibot",
    entry: "library/src/index.ts",
    reuse: ["_build/real-world/valibot/valibot"],
    driver: "valibot.driver.mjs",
    appEntry: "valibot.app.ts",
  },
  {
    name: "typebox",
    repo: "https://github.com/sinclairzx81/typebox",
    entry: "src/index.ts",
    // Was size-only through two separate unloadable-bundle bugs, and
    // both are worth the note because neither was about types:
    //
    //   * `Array.from({ length: 256 }).map(…)` in `system/hashing/hash.ts`
    //     compiled to `[...{ length: 256 }].map(…)`. `Array.from` takes
    //     an array-LIKE and a spread needs an ITERABLE — a rewrite that
    //     had never been asked the question, now in
    //     `scripts/verify_rule_equivalence.mjs` along with the rest of
    //     the built-in-method family.
    //   * `types/record.ts` was initialized AFTER
    //     `indexed/from_object.ts`, whose top level does
    //     `new RegExp(IntegerKey)`. The module order did not match ESM's
    //     because dependencies were walked imports-then-re-exports
    //     rather than in source order, and `src/index.ts` is a barrel
    //     that puts five `export * from` above one `import * as`.
    //
    // The driver reads `Record(Integer(), …)`'s emitted
    // `patternProperties` back out, because `IntegerKey` is a string:
    // an order that produced the wrong value instead of throwing would
    // still build a schema, just not the right one.
    driver: "typebox.driver.mjs",
    appEntry: "typebox.app.ts",
  },
  {
    name: "immer",
    repo: "https://github.com/immerjs/immer",
    entry: "src/immer.ts",
    // Was size-only, for a reason worth keeping in view: `export const
    // enum ArchType` is declared in one module and read from several
    // others, a const enum emits no runtime binding, and the
    // cross-module reads were neither linked nor substituted — so the
    // bundle threw `ArchType is not defined` at load. The per-module
    // inline had been taken for the whole job.
    //
    // The driver exercises all four `ArchType` dispatch paths on
    // purpose. `ArchType` picks which proxy implementation handles a
    // draft, so substituting a wrong literal would route an Array
    // through the object path and still load cleanly; the values have
    // to be observed, not just the absence of a throw.
    driver: "immer.driver.mjs",
    appEntry: "immer.app.ts",
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
    appEntry: "neverthrow.app.ts",
  },
  {
    name: "ts-pattern",
    repo: "https://github.com/gvergnaud/ts-pattern",
    entry: "src/index.ts",
    driver: "ts-pattern.driver.mjs",
    appEntry: "ts-pattern.app.ts",
  },
  {
    name: "superstruct",
    repo: "https://github.com/ianstormtaylor/superstruct",
    entry: "src/index.ts",
    // Was BROKEN: `error.ts:44` does
    // `this.name = this.constructor.name`, `--mangle` renamed the class,
    // and `e.name` came back `"a"` instead of `"StructError"`. Fixed by
    // `observed_names.mbt`, and the hierarchy narrowing is what made it
    // affordable — `this.constructor` in a method of `C` is `C` or a
    // subclass, so only `StructError` is reserved and the cost is
    // +25 bytes. Reserving every callable instead cost +31% here.
    driver: "superstruct.driver.mjs",
    appEntry: "superstruct.app.ts",
  },
  // superstruct was BLOCKED, and was blamed on the wrong thing twice:
  // first on the export-surface blowup, then — after one gdb sample
  // landed in `parse_conditional_type_tail` — on a parser blowup over
  // recursive conditional types. Neither was it. It writes
  // `.js`-suffixed relative specifiers, which the module-graph walk
  // failed to recognise as already-loaded, so it re-read and re-parsed
  // every repeat visit and re-pushed its own imports: 2^depth on a
  // diamond graph. The sample landed in the parser because the parser
  // was being re-entered exponentially. With the dedup guard in
  // `mtsc_load_bundle_files` superstruct went from not finishing to
  // 15 ms. `just verify-graph-walk` is the gate, and it generates the
  // diamond shape itself rather than relying on a cloned package.
  //
  // zod USED to be the loud case here — 133 files, `.js` specifiers 65
  // times, eighteen minutes without finishing a parse, then 227 ms —
  // and it is no longer in the corpus. It cannot answer the question
  // this harness asks. Its bundle contains eight `Reflect.ownKeys`
  // calls, two `Object.getOwnPropertyDescriptors` and two
  // `Object.getOwnPropertyDescriptor`, which enumerate non-enumerable
  // properties — exactly what a class prototype method is — so
  // class-method DCE is suppressed on zod by construction and no amount
  // of type information changes the answer. It is worth being precise
  // about what that costs, because it is easy to overstate: zod's
  // report also says "nothing would have been dropped anyway", so the
  // reflection is not what makes zod a NEUTRAL. Every declared method
  // is reachable. Keeping it measured a permanent zero for a permanent
  // reason, at the price of the slowest run in the corpus. The four
  // bugs it found are all covered elsewhere — `verify-graph-walk` for
  // the walk, and fixtures for the erased-`as` arrow parens, the
  // type-only namespace entries and the merged interface-and-function
  // case.
  // The corpus's only UI application, and its first monorepo: the
  // element package's imports reach five sibling workspace packages
  // through tsconfig `paths` declared in a config it only reaches by
  // `extends`. Five things had to be fixed before it bundled at all —
  // `.json` imports, `.scss` imports, the binary read that decoded a
  // `.woff2` as UTF-8, `extends`-inherited `paths`, and `from "."` —
  // and every one of them was a hole no library-shaped target had
  // exposed. `docs/type-aware-measurement.md` records them.
  {
    name: "excalidraw",
    repo: "https://github.com/excalidraw/excalidraw",
    entry: "packages/element/src/index.ts",
    // The bundle spans six workspace packages, reached through
    // tsconfig `paths`; the element package alone is 52 of the 95 files.
    sourceRoots: [
      "packages/element/src",
      "packages/common/src",
      "packages/math/src",
      "packages/utils/src",
      "packages/laser-pointer/src",
      "packages/fractional-indexing/src",
    ],
    driver: "excalidraw.driver.mjs",
    // The bundle keeps its npm dependencies external, so the driver
    // needs them on disk. Installed into the leg directory, NOT into
    // the checkout: a `node_modules` next to the sources would make
    // mtsc resolve and inline these packages instead of leaving them
    // external, which is a different measurement.
    deps: [
      "roughjs@4.6.6",
      "points-on-curve@1.0.1",
      "perfect-freehand@1.2.3",
      "nanoid@5.1.6",
      "tinycolor2@1.6.0",
      "lodash.throttle@4.1.1",
      "es6-promise-pool@2.5.0",
      "@braintree/sanitize-url@7.1.2",
    ],
    // Node cannot load `roughjs/bin/*` at all — extension-less ESM with
    // no `exports` map, which is to say a bundler-only build. The shims
    // hand back the real roughjs through the rollup bundle it publishes
    // as `module`; see `fixtures/type-aware-corpus/excalidraw.shims/`.
    shims: {
      "roughjs/bin/rough": "rough.mjs",
      "roughjs/bin/generator": "generator.mjs",
      "roughjs/bin/math": "math.mjs",
      "points-on-curve/lib/curve-to-bezier": "curve-to-bezier.mjs",
    },
    // `import.meta.env` is vite's build-time substitution. The driver
    // sets the global this maps it to.
    execReplace: [["import.meta.env", "globalThis.__EXCALIDRAW_ENV__"]],
    appEntry: "excalidraw.app.ts",
    // The one app entry with its own driver: the `import.meta.env`
    // global has to be set before the bundle is evaluated, which the
    // shared driver's static import cannot do.
    appDriver: "excalidraw.driver.mjs",
  },
  {
    name: "remeda",
    repo: "https://github.com/remeda/remeda",
    entry: "packages/remeda/src/index.ts",
    // Was BLOCKED, and not on a pass — on the PARSER. `setPath.ts`
    // writes a conditional type whose check type is a union laid out one
    // member per line, and the leading `|` took its own branch in
    // `parse_type` that built the union and returned, skipping the
    // `extends` tail. `T | string extends …` parsed fine; the bug needed
    // the decoration, not the union. One unparseable file blocked the
    // whole package.
    //
    // Worth measuring for the calling convention: nearly every function
    // has a data-first and a data-last form dispatched at runtime by
    // `purry` on `arguments.length`, which is an arity-sensitive
    // indirection through a shared helper — the shape an unused-parameter
    // pass or a single-use inliner can break with nothing looking wrong.
    // The driver also counts upstream calls through a lazy `take`, so a
    // fold that changed evaluation order shows up as call counts rather
    // than as a wrong answer.
    driver: "remeda.driver.mjs",
    appEntry: "remeda.app.ts",
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
let phases = false;
let appMode = false;
for (let i = 0; i < args.length; i++) {
  const a = args[i];
  if (a === "--only") only = args[++i];
  else if (a === "--verbose" || a === "-v") verbose = true;
  else if (a === "--keep") keep = true;
  else if (a === "--update") update = true;
  else if (a === "--timeout") legTimeout = Number(args[++i]) * 1000;
  else if (a === "--phases") phases = true;
  else if (a === "--app") appMode = true;
  else {
    console.error(`unknown argument: ${a}`);
    process.exit(2);
  }
}

const EXPECTED = path.join(FIXTURES, appMode ? "expected.app.json" : "expected.json");

const MTSC = findMtsc();
fs.mkdirSync(WORK, { recursive: true });

// The six phases that read type tables. `--phases` compiles the aware
// leg once per phase with that phase switched off and reports the
// difference, which answers "what is the type information worth" WITHOUT
// a control.
//
// It exists because the leg delta could not answer it. On Excalidraw the
// leg delta says the aware leg is 1,139 bytes BEHIND after the
// double-pass adjustment, and the per-phase table says the six phases
// SAVE 2,380 bytes there and cost nothing — four of the six are
// completely inert. Both are true: the residual is not a pass, it is the
// leg construction. `blind`'s input is not "the same code with types
// erased", it is the same code after a round-trip through mtsc's own
// emitter, and that round-trip is itself an optimization the aware leg
// never gets. The `aware2` control prices a SECOND pass on
// already-optimized output, which is a different thing — on Excalidraw
// it comes out negative (a second pass GROWS the bundle by 843 bytes),
// so subtracting it makes the gap look worse rather than fairer.
//
// So this is the number to trust for "does knowing the types pay": it is
// a direct measurement of the phases in question, on the same input, with
// nothing to adjust.
const TYPE_READING_PHASES = [
  "predicate-inline",
  "switch-fold",
  "as-const-inline",
  "tag-rewrite",
  "class-method-dce",
  "type-fold",
];

function bytes(n) {
  return n.toLocaleString("en-US");
}

// Gzipped size, because that is what ships.
//
// Added after `compare_terser_bundles.mjs` showed the two metrics
// DISAGREE: mtsc was smaller than terser in raw bytes on five of nine
// targets and on only one gzipped, and remeda was -388 raw / +152
// gzipped. A saving that gzip would have made anyway is not a saving,
// so a delta worth acting on has to survive compression.
function gzipBytes(file) {
  try {
    return zlib.gzipSync(fs.readFileSync(file), { level: 9 }).length;
  } catch {
    return null;
  }
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

// Where a leg's bundle is EXECUTED: a subdirectory of the leg
// directory, holding the copy of the bundle, the driver, the shims and
// the `node_modules` the driver needs.
//
// Its own subdirectory rather than the leg directory itself, and the
// reason is not tidiness. mtsc resolves a bare specifier by walking up
// from the importing file looking for `node_modules`, and the leg
// directory is the checkout's PARENT — so installing there put
// `es6-promise-pool` on mtsc's search path and it INLINED the UMD
// wrapper instead of leaving the import external. The measurement grew
// 88 KB and the bundle then threw `Cannot set properties of undefined
// (setting 'PromisePool')`, because a UMD factory assigned to a `root`
// that does not exist in ESM. `exec/` is not an ancestor of the
// checkout, so nothing mtsc does can see it.
const execDir = (dir) => path.join(dir, "exec");

// The npm packages a target's bundle leaves external, installed so the
// driver can resolve them.
function installDeps(dir, deps) {
  if (!deps?.length) return { ok: true };
  fs.mkdirSync(dir, { recursive: true });
  const marker = path.join(dir, "node_modules", ".type-aware-deps");
  const want = deps.slice().sort().join(" ");
  if (fs.existsSync(marker) && fs.readFileSync(marker, "utf8") === want) {
    return { ok: true };
  }
  fs.writeFileSync(
    path.join(dir, "package.json"),
    JSON.stringify({ name: "type-aware-leg", private: true, type: "module" }) + "\n",
  );
  const r = spawnSync("npm", ["install", "--no-save", "--no-audit", "--no-fund", "--silent", ...deps], {
    encoding: "utf8",
    timeout: 600_000,
    cwd: dir,
  });
  if (r.status !== 0) {
    return { ok: false, why: `npm install failed: ${(r.stderr || "").trim().split("\n")[0] || `exit ${r.status}`}` };
  }
  fs.writeFileSync(marker, want);
  return { ok: true };
}

// Turn the leg's output into something Node can load, WITHOUT touching
// the file the byte count came from.
//
// Both rewrites stand in for a step vite performs and Node has no
// equivalent of: filling in an extension-less deep subpath (which for
// roughjs also means routing around a `bin/` tree Node cannot load at
// all), and substituting `import.meta.env`. They are applied to every
// leg identically, so a difference between legs is still ours.
function prepareForExecution(dir, target, t) {
  let src = fs.readFileSync(target, "utf8");
  for (const [spec, file] of Object.entries(t.shims ?? {})) {
    const quoted = new RegExp(`(["'])${spec.replace(/[.*+?^${}()|[\]\\/]/g, "\\$&")}(\\.js)?\\1`, "g");
    src = src.replace(quoted, `"./shims/${file}"`);
  }
  for (const [find, replace] of t.execReplace ?? []) {
    src = src.split(find).join(replace);
  }
  fs.writeFileSync(target, src);
  if (t.shims) {
    fs.cpSync(path.join(FIXTURES, `${t.name}.shims`), path.join(dir, "shims"), {
      recursive: true,
    });
  }
}

// Run one leg's output through the target's driver and return its
// stdout, or null with a reason.
//
// The driver is copied next to the bundle rather than run from
// `fixtures/`: it imports `./target.mjs`, and a bare specifier resolves
// against the importing FILE, not the working directory.
function observe(dir, driverSrc, leg, t) {
  const exec = execDir(dir);
  fs.mkdirSync(exec, { recursive: true });
  const driver = path.join(exec, "driver.mjs");
  fs.copyFileSync(driverSrc, driver);
  const target = path.join(exec, "target.mjs");
  fs.copyFileSync(path.join(dir, `${leg}.mjs`), target);
  prepareForExecution(exec, target, t);
  const r = spawnSync("node", [driver], {
    encoding: "utf8",
    maxBuffer: 1 << 28,
    timeout: 180_000,
    cwd: exec,
  });
  if (r.status !== 0) {
    // Node prints a source-location banner before the message, so the
    // first non-empty line is `foo.mjs:123` and says nothing. Take the
    // first line that carries a diagnostic, and keep the whole stderr on
    // disk for the ones that need reading.
    const lines = (r.stderr || "").split("\n").filter((l) => l.trim());
    const msg =
      lines.find((l) => /^\s*(\w*Error|Uncaught|SyntaxError|TypeError)\b/.test(l.trim())) ||
      lines.find((l) => /error/i.test(l)) ||
      lines[0] ||
      `exit ${r.status}`;
    fs.writeFileSync(path.join(dir, `${leg}.stderr`), r.stderr || "");
    return { ok: false, why: msg.trim().slice(0, 200) };
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

// ---------------------------------------------------------------------
// App entries (`--app`)
// ---------------------------------------------------------------------
//
// Every row above compiles a library's PACKAGE entry — the barrel that
// exports its whole public API. That is the wrong shape for two of the
// questions this harness asks, and the difference is not small:
//
//   * Tree-shaking has nothing to remove. A barrel's exports are all
//     live by definition, so `--treeshake` can only drop what no export
//     reaches, which in a well-built library is almost nothing.
//   * Every property name is on the API boundary. A library's object
//     shapes ARE its wire format, so the mangler is right to reserve
//     them, and the reserved-set census on the package entries is
//     therefore uninformative about what the pass could do.
//
// An application is the other case: it consumes a slice of the library
// and its own object shapes are private. `--app` compiles one, per
// target, and the contrast is what the row is for.
//
// The usage in each `app-entries/*.app.ts` is copied from that library's
// OWN README (or, for immer, its docs site — its readme carries no
// TypeScript block). That constraint is the whole point: an entry I
// designed would be an entry designed to make the passes fire, and a
// harness that flatters the compiler is worse than no harness. Where the
// README's example throws or is async, it is wrapped, and nothing else
// is changed.
//
// The fixture is staged INTO the checkout, at the root, so its imports
// are relative paths into the library's own sources — `./src/index.ts`.
// Compiling it from `fixtures/` instead would resolve the library as a
// bare specifier through `node_modules`, which is the published `.js`,
// which is the measurement this harness exists to avoid.
function stageAppEntry(checkout, t) {
  if (!t.appEntry) return { ok: false, why: "no app entry for this target" };
  const fx = path.join(APP_ENTRIES, t.appEntry);
  if (!fs.existsSync(fx)) {
    return { ok: false, why: `app entry fixture ${t.appEntry} is missing` };
  }
  const rel = `mtsc-app-entry.${t.name}.ts`;
  fs.copyFileSync(fx, path.join(checkout, rel));
  return { ok: true, rel };
}

// The leg directory. `--app` gets its own so the two modes cannot
// overwrite each other's bundles — the `.observed` and `.stderr` files a
// failure leaves behind are the only record of it.
const legDir = (t) => path.join(WORK, appMode ? `${t.name}-app` : t.name);

// The driver.
//
// A package entry needs one written per target: it exports the whole
// API and there is no generic way to exercise that. An app entry has
// already done the exercising and exports scalars, so one shared driver
// prints what it computed. A target may still name its own with
// `appDriver` when the bundle needs something set up before it is
// evaluated.
function driverFor(t) {
  if (!appMode) return t.driver ? path.join(FIXTURES, t.driver) : null;
  return path.join(APP_ENTRIES, t.appDriver ?? "driver.mjs");
}

// Source files the target spans.
//
// The entry's own directory is the right answer for a single-package
// library, and wrong for a monorepo: Excalidraw's element package is 52
// files, but the bundle reaches 95 across six workspace packages, and
// reporting 52 next to a 780 KB bundle invites the wrong conclusion. A
// target that spans packages names its roots.
function countSources(checkout, t) {
  const roots = (t.sourceRoots ?? [path.dirname(t.entry)]).map((r) =>
    JSON.stringify(path.join(checkout, r)),
  );
  const r = spawnSync(
    "bash",
    [
      "-c",
      `find ${roots.join(" ")} -name '*.ts' ! -name '*.test.ts' ! -name '*.spec.ts' 2>/dev/null | wc -l`,
    ],
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
  if (appMode && !t.appEntry) {
    results.push({ name: t.name, status: "skip", why: "no app entry for this target" });
    return;
  }
  const { dir: checkout, why } = resolveCheckout(t);
  if (!checkout) {
    results.push({ name: t.name, status: "skip", why });
    return;
  }
  const dir = legDir(t);
  fs.mkdirSync(dir, { recursive: true });
  let entryRel = t.entry;
  if (appMode) {
    const staged = stageAppEntry(checkout, t);
    if (!staged.ok) {
      results.push({ name: t.name, status: "skip", why: staged.why });
      return;
    }
    entryRel = staged.rel;
  }
  const entry = path.join(checkout, entryRel);
  const files = countSources(checkout, t);

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

  const driverSrc = driverFor(t);
  const row = {
    name: t.name,
    status: driverSrc ? "measured" : "size-only",
    why: t.sizeOnlyWhy,
    files,
    unopt: unopt.size,
    aware: aware.size,
    blind: blind.size,
    delta,
    awareGz: gzipBytes(path.join(dir, "aware.mjs")),
    blindGz: gzipBytes(path.join(dir, "blind.mjs")),
    secondPass,
    adjusted,
    seconds: aware.seconds,
  };

  const installed = installDeps(execDir(dir), t.deps);
  if (driverSrc && !installed.ok) {
    row.status = "size-only";
    row.why = installed.why;
  } else if (driverSrc) {
    const ref = observe(dir, driverSrc, "unopt", t);
    if (!ref.ok) {
      row.status = "size-only";
      row.why = `unoptimized bundle does not run: ${ref.why}`;
    } else {
      for (const leg of ["aware", "blind"]) {
        const got = observe(dir, driverSrc, leg, t);
        if (!got.ok) {
          row.status = "broken";
          row.why = `${leg} does not run: ${got.why}`;
          break;
        }
        if (got.out !== ref.out) {
          fs.writeFileSync(path.join(dir, `${leg}.observed`), got.out);
          fs.writeFileSync(path.join(dir, "reference.observed"), ref.out);
          row.status = "broken";
          row.why = `${leg} observations differ (see ${
            path.relative(ROOT, dir)
          }/{reference,${leg}}.observed)`;
          break;
        }
      }
    }
    fs.rmSync(path.join(execDir(dir), "target.mjs"), { force: true });
    fs.rmSync(path.join(execDir(dir), "driver.mjs"), { force: true });
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
// Per-phase attribution (`--phases`)
// ---------------------------------------------------------------------

if (phases) {
  console.log("\n  what each type-reading phase is worth\n");
  console.log(
    "  a positive number is bytes SAVED by the phase (the bundle grows when it is off)\n",
  );
  const header = ["target".padEnd(12), ...TYPE_READING_PHASES.map((p) => p.padStart(17))];
  console.log("  " + header.join(""));
  for (const t of CORPUS) {
    if (only && t.name !== only) continue;
    const row = results.find((r) => r.name === t.name);
    if (!row || row.status === "blocked") continue;
    // `resolveCheckout` rather than `WORK/<name>/<name>`: a `reuse`
    // target lives under `_build/real-world/…`, and guessing the layout
    // silently skipped hono and valibot from this table.
    const { dir: checkout } = resolveCheckout(t);
    if (!checkout) continue;
    const dir = legDir(t);
    fs.mkdirSync(dir, { recursive: true });
    let entryRel = t.entry;
    if (appMode) {
      const staged = stageAppEntry(checkout, t);
      if (!staged.ok) continue;
      entryRel = staged.rel;
    }
    const entry = path.join(checkout, entryRel);
    if (!fs.existsSync(entry)) continue;
    const base = compile(entry, path.join(dir, "phase-base.mjs"), ["--bundle", ...OPT_FLAGS], dir);
    if (!base.ok) {
      console.log("  " + t.name.padEnd(12) + "  (baseline failed: " + base.why + ")");
      continue;
    }
    const cells = [];
    for (const ph of TYPE_READING_PHASES) {
      const off = compile(
        entry,
        path.join(dir, "phase-off.mjs"),
        ["--bundle", ...OPT_FLAGS, "--disable-phase", ph],
        dir,
      );
      cells.push(off.ok ? bytes(off.size - base.size).padStart(17) : "—".padStart(17));
    }
    console.log("  " + t.name.padEnd(12) + cells.join(""));
    if (!keep) {
      for (const f of ["phase-base.mjs", "phase-off.mjs"]) {
        fs.rmSync(path.join(dir, f), { force: true });
      }
    }
  }
  console.log("");
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
console.log("  optimizing TypeScript SOURCE vs the same code with types erased");
console.log(
  appMode
    ? "  entry: an APPLICATION that consumes each library (`--app`)\n"
    : "  entry: each library's PACKAGE entry — `--app` measures an application instead\n",
);

const pad = (s, n) => String(s).padEnd(n);
const padl = (s, n) => String(s).padStart(n);

console.log(
  `  ${pad("target", 12)} ${padl("files", 5)} ${padl("unopt", 10)} ${padl("aware", 9)} ${padl("blind", 9)} ${padl("delta", 8)} ${padl("of aware", 9)} ${padl("gz delta", 9)}  verdict`,
);
for (const row of results) {
  if (row.status === "blocked" || row.status === "skip") {
    console.log(`  ${pad(row.name, 12)} ${padl("-", 5)} ${padl("-", 10)} ${padl("-", 9)} ${padl("-", 9)} ${padl("-", 8)} ${padl("-", 9)} ${padl("-", 9)}  ${row.status === "skip" ? "SKIP" : "BLOCKED"}`);
    continue;
  }
  const gzDelta =
    row.awareGz != null && row.blindGz != null ? row.blindGz - row.awareGz : null;
  console.log(
    `  ${pad(row.name, 12)} ${padl(row.files, 5)} ${padl(bytes(row.unopt), 10)} ${padl(bytes(row.aware), 9)} ${padl(bytes(row.blind), 9)} ` +
      `${padl((row.delta > 0 ? "+" : "") + bytes(row.delta), 8)} ${padl(pct(row.delta, row.aware), 9)} ` +
      `${padl(gzDelta == null ? "-" : (gzDelta > 0 ? "+" : "") + bytes(gzDelta), 9)}  ${verdictOf(row)}`,
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
