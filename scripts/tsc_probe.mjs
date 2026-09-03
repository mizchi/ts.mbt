// Run the locally installed TypeScript compiler over a file the way the
// conformance harness would, and print its diagnostics.
//
// Why this exists: the conformance gate's ground truth is a pair of TS7
// baseline NAME lists, so it says that TS7 errored on a file and nothing
// about WHAT it said. `checker_miss_buckets.mjs` fills that in from the
// submodule's TS6-era `.errors.txt` baselines, which is an approximation
// and, for a file with no baseline at all, no answer. This asks a real
// compiler instead — and, more importantly, it can be pointed at a
// hand-written LEGAL NEIGHBOUR, which no baseline can ever cover.
//
// The version here is whatever `node_modules/typescript` holds (print it
// with --version), not tsgo, so a disagreement with the TS7 verdict is
// possible and is itself worth knowing rather than assuming.
//
// `// @option: value` header lines are read the way the TS test harness
// reads them, so a case file is checked under its own settings.
//
// Usage:
//   node scripts/tsc_probe.mjs [--version] [--raw] <file.ts> [more.ts ...]
import fs from "node:fs";
import path from "node:path";
import { createRequire } from "node:module";

const require_ = createRequire(import.meta.url);
const ts = require_("typescript");
const argv = process.argv.slice(2);
if (argv.includes("--version")) {
  console.log(ts.version);
  process.exit(0);
}
const raw = argv.includes("--raw");
const files = argv.filter((a) => !a.startsWith("--"));
if (files.length === 0) {
  console.error("usage: node scripts/tsc_probe.mjs [--raw] <file.ts> ...");
  process.exit(2);
}

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

function directives(src) {
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

for (const file of files) {
  const src = fs.readFileSync(file, "utf8");
  const dirs = directives(src);
  // A multi-valued `@target: es5, es2015` runs the harness twice; take the
  // first so the probe is deterministic, and say so.
  const opts = {};
  for (const [k, v] of Object.entries(dirs)) {
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
  const { options, errors } = ts.convertCompilerOptionsFromJson(
    { ...opts, noEmit: true },
    process.cwd(),
  );
  const program = ts.createProgram([file], options);
  const diags = [
    ...program.getSyntacticDiagnostics(),
    ...program.getSemanticDiagnostics(),
    ...program.getGlobalDiagnostics(),
    ...errors,
  ];
  const header = `--- ${path.basename(file)}  [${Object.entries(opts).map(([k, v]) => `${k}=${v}`).join(" ") || "defaults"}]`;
  if (!raw) console.log(header);
  if (diags.length === 0) {
    console.log("  (accepted)");
    continue;
  }
  for (const d of diags) {
    const msg = ts.flattenDiagnosticMessageText(d.messageText, " ");
    let where = "";
    if (d.file && d.start !== undefined) {
      const { line, character } = d.file.getLineAndCharacterOfPosition(d.start);
      where = `(${line + 1},${character + 1})`;
    }
    console.log(`  TS${d.code}${where}: ${msg}`);
  }
}
