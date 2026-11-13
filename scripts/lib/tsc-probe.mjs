// Shared core for running the locally installed TypeScript compiler over a
// conformance case the way the TS test harness would.
//
// Two consumers: `scripts/tsc_probe.mjs` (print one file's diagnostics, and
// point it at a hand-written legal neighbour) and
// `scripts/checker_miss_rank.mjs` (probe every MISS file and rank the codes).
// The header-reading rules below are subtle enough — a miscased key is
// TS5025, a boolean handed a string is TS5024, `lib` is an array — that a
// second copy of them would be a second set of phantom findings, which is
// the failure mode this repo keeps recording.
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { createRequire } from "node:module";
import { spawnSync } from "node:child_process";
import { API } from "typescript/sync";

const require_ = createRequire(import.meta.url);
// TypeScript 7 (the Go port). Its main entry exports only the version; the
// compiler is reached through the `typescript/sync` API, which drives a native
// `tsgo` process over JSON-RPC and works on PROJECTS rather than on an
// in-process `createProgram`. This is the same compiler the conformance
// oracle's vendored baselines come from, where the 6.0.3 this used to run
// was a stand-in for it.
export const ts = require_("typescript");

// Harness header directives. Only the ones that change what is an error
// are honoured; emit-shape options are irrelevant here.
// Lower-cased directive name -> the option's canonical spelling. The
// harness accepts `// @noImplicitAny` in any case; `convertCompilerOptions`
// does not, and rejects a miscased key with TS5025, which reads like a
// finding about the FILE and is a bug in the probe.
const HONOURED = new Map(
  [
    "target", "lib", "module", "strict", "strictNullChecks", "noImplicitAny",
    "experimentalDecorators", "emitDecoratorMetadata", "useDefineForClassFields",
    "exactOptionalPropertyTypes", "noUncheckedIndexedAccess", "allowJs",
    "checkJs", "jsx", "moduleResolution", "noImplicitThis", "isolatedModules",
    "verbatimModuleSyntax", "noPropertyAccessFromIndexSignature", "importHelpers",
    "noUnusedLocals", "noUnusedParameters", "downlevelIteration",
    "strictFunctionTypes", "strictPropertyInitialization", "strictBindCallApply",
  ].map((k) => [k.toLowerCase(), k]),
);

/** Honoured `// @option: value` directives from a case file's header. */
export function directives(src) {
  const out = {};
  for (const line of src.split("\n")) {
    const m = line.match(/^\s*\/\/\s*@(\w+)\s*:\s*(.*?)\s*$/);
    if (!m) {
      // Directives only appear in the header; stop at the first
      // non-comment, non-blank line so a `// @ts-ignore` deeper in the
      // file is never read as one.
      if (line.trim() !== "" && !line.trim().startsWith("//")) break;
      continue;
    }
    const key = HONOURED.get(m[1].toLowerCase());
    if (key) out[key] = m[2];
  }
  return out;
}

/** Directives as a compiler-options JSON object. */
export function optionsJson(dirs) {
  const opts = {};
  for (const [k, v] of Object.entries(dirs)) {
    // A multi-valued `@target: es5, es2015` runs the harness twice; take
    // the first so the probe is deterministic.
    const first = v.split(",")[0].trim();
    // A boolean option handed a STRING is rejected with TS5024, which
    // reads like a finding and is not one — the header spells them
    // `@strict: false`.
    opts[k] =
      k === "lib"
        // `lib` is an array option, and the harness spells it
        // `// @lib: esnext,dom`. Passing the raw string is TS5024; the
        // JSON form wants the bare names, not `lib.esnext.d.ts` file
        // names (that spelling is TS6046).
        ? v.split(",").map((x) => x.trim())
        : first === "true"
          ? true
          : first === "false"
            ? false
            : first;
  }
  return opts;
}

// One API process for the whole run: `checker_miss_rank.mjs` probes
// hundreds of files, and spawning `tsgo` per file is the cost to avoid.
// Each probe opens its own throwaway project and closes it again, so a
// project's options never leak into the next file's.
let api = null;
function getApi() {
  if (!api) {
    api = new API({ cwd: process.cwd() });
    // By `exit` the `tsgo` child is already being torn down, so `close()`
    // can only report that; the hook is tidiness, never a failure.
    process.once("exit", () => {
      try {
        api.close();
      } catch {}
    });
  }
  return api;
}

function lineCol(text, pos) {
  let line = 1;
  let col = 1;
  for (let i = 0; i < pos && i < text.length; i++) {
    if (text[i] === "\n") {
      line += 1;
      col = 1;
    } else {
      col += 1;
    }
  }
  return { line, col };
}

/** A diagnostic's message with its chain flattened, as `flattenDiagnosticMessageText` did. */
function flatten(d) {
  const parts = [d.text];
  const walk = (chain) => {
    for (const c of chain ?? []) {
      parts.push(c.text);
      walk(c.messageChain);
    }
  };
  walk(d.messageChain);
  return parts.join(" ");
}

/**
 * Diagnostics for header options TS7 REJECTED. The API's `parseConfigFile`
 * returns only the options it accepted, so a refused one (`@target: es5` —
 * TS7 dropped ES3 and ES5 — is TS6046 from the CLI) would otherwise vanish
 * without a word and the file be checked under the default instead. A key
 * the header set and the parse dropped is the signal; only then is the CLI
 * run on the same tsconfig, to report the compiler's own code and message.
 */
function rejectedOptionDiagnostics(client, tsconfig, opts) {
  const parsed = client.parseConfigFile(tsconfig).options ?? {};
  const dropped = Object.keys(opts).filter((k) => parsed[k] === undefined);
  if (dropped.length === 0) return [];
  const tsc = path.join(path.dirname(require_.resolve("typescript/package.json")), "bin", "tsc");
  const r = spawnSync(process.execPath, [tsc, "-p", tsconfig, "--pretty", "false", "--noEmit"], {
    encoding: "utf8",
  });
  const out = [];
  for (const line of `${r.stdout}\n${r.stderr}`.split("\n")) {
    const m = line.match(/^(?:.*tsconfig\.json\(\d+,\d+\): )?error TS(\d+): (.*)$/);
    if (m && line.includes("tsconfig.json")) {
      out.push({ code: Number(m[1]), text: m[2], pos: 0 });
    }
  }
  if (out.length === 0) {
    // The CLI said nothing we could attribute: still do not let the option
    // disappear silently.
    out.push({ code: 0, text: `TS7 did not accept option(s): ${dropped.join(", ")}`, pos: 0 });
  }
  return out;
}

/**
 * Check one file under its own header. Returns
 * `{ opts, diags: [{ code, line, col, msg }], otherFiles }`.
 */
export function probe(file) {
  const src = fs.readFileSync(file, "utf8");
  const opts = optionsJson(directives(src));
  const abs = path.resolve(file);
  // The project is a real tsconfig on disk: the TS7 API opens projects, not
  // option objects. Options it rejects come back as PROGRAM diagnostics,
  // which is where `convertCompilerOptionsFromJson`'s errors used to go.
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "tsc-probe-"));
  const tsconfig = path.join(dir, "tsconfig.json");
  fs.writeFileSync(
    tsconfig,
    JSON.stringify({ compilerOptions: { ...opts, noEmit: true }, files: [abs] }),
  );
  const client = getApi();
  let all;
  try {
    const configErrors = rejectedOptionDiagnostics(client, tsconfig, opts);
    // TS 7.1's sync API creates a fresh snapshot per request and requires it
    // to be disposed; 7.0's `updateSnapshot({ openProject })` /
    // `{ closeProjects }` pair is gone (`updateSnapshot` now derives from a
    // base snapshot).
    const snapshot = client.createSnapshot({ openProjects: [tsconfig] });
    try {
      const program = snapshot.getConfiguredProject(tsconfig).program;
      all = [
        ...configErrors,
        ...program.getProgramDiagnostics(),
        ...program.getSyntacticDiagnostics(),
        ...program.getSemanticDiagnostics(),
      ];
      // Projects are reference-counted per client, so the probe's throwaway
      // project is closed explicitly before its snapshots are released.
      snapshot.update({ closeProjects: [tsconfig] }).dispose();
    } finally {
      snapshot.dispose();
    }
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
  // `getSemanticDiagnostics()` with no argument returns EVERY file's
  // diagnostics, including the vendored `lib.*.d.ts` — and a test that
  // augments `interface Object` under `@skipDefaultLibCheck: false` makes
  // tsc type-check the lib itself, so its errors were being attributed to
  // the probed file at line numbers the file does not have. Split them:
  // `diags` is what this file is responsible for (a diagnostic with no
  // file, such as TS2318 "Cannot find global type", belongs here too),
  // and `otherFiles` keeps the rest so the information is reported rather
  // than lost.
  const mine = (d) =>
    !d.fileName || path.resolve(d.fileName) === abs || path.basename(d.fileName) === "tsconfig.json";
  const texts = new Map([[abs, src]]);
  const shape = (d) => {
    let line = 0;
    let col = 0;
    if (d.fileName) {
      const key = path.resolve(d.fileName);
      if (!texts.has(key)) {
        try {
          texts.set(key, fs.readFileSync(key, "utf8"));
        } catch {
          texts.set(key, "");
        }
      }
      ({ line, col } = lineCol(texts.get(key), d.pos));
    }
    return {
      code: d.code,
      line,
      col,
      file: d.fileName ? path.basename(d.fileName) : null,
      msg: flatten(d),
    };
  };
  const diags = all.filter(mine).map(shape);
  const otherFiles = all.filter((d) => !mine(d)).map(shape);
  return { opts, diags, otherFiles };
}
