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
import path from "node:path";
import { createRequire } from "node:module";

const require_ = createRequire(import.meta.url);
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

/**
 * Check one file under its own header. Returns
 * `{ opts, diags: [{ code, line, col, msg }] }`.
 */
export function probe(file) {
  const src = fs.readFileSync(file, "utf8");
  const opts = optionsJson(directives(src));
  const { options, errors } = ts.convertCompilerOptionsFromJson(
    { ...opts, noEmit: true },
    process.cwd(),
  );
  const program = ts.createProgram([file], options);
  // `getSemanticDiagnostics()` with no argument returns EVERY file's
  // diagnostics, including the vendored `lib.*.d.ts` — and a test that
  // augments `interface Object` under `@skipDefaultLibCheck: false` makes
  // tsc type-check the lib itself, so its errors were being attributed to
  // the probed file at line numbers the file does not have. Split them:
  // `diags` is what this file is responsible for (a diagnostic with no
  // file, such as TS2318 "Cannot find global type", belongs here too),
  // and `otherFiles` keeps the rest so the information is reported rather
  // than lost.
  const abs = path.resolve(file);
  const split = (list) => list.filter((d) => !d.file || path.resolve(d.file.fileName) === abs);
  const shape = (d) => {
    let line = 0;
    let col = 0;
    if (d.file && d.start !== undefined) {
      const p = d.file.getLineAndCharacterOfPosition(d.start);
      line = p.line + 1;
      col = p.character + 1;
    }
    return {
      code: d.code,
      line,
      col,
      file: d.file ? path.basename(d.file.fileName) : null,
      msg: ts.flattenDiagnosticMessageText(d.messageText, " "),
    };
  };
  const all = [
    ...program.getSyntacticDiagnostics(),
    ...program.getSemanticDiagnostics(),
    ...program.getGlobalDiagnostics(),
    ...errors,
  ];
  const diags = split(all).map(shape);
  const otherFiles = all.filter((d) => !split([d]).length).map(shape);
  return { opts, diags, otherFiles };
}
