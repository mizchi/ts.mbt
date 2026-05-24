// Generate a synthetic multi-file TypeScript module tree under the
// given directory. The tree fans out as `mod-0.ts` … `mod-(N-1).ts`
// where each module imports a fan-in slice of the previous N/2
// modules so the bundler walks a non-trivial dependency graph.
//
//   node bench/gen_corpus.mjs <out-dir> [count=200]
//
// The generator is deterministic: the same `count` produces the
// same files, so hyperfine warm-ups don't get tainted by I/O
// reshuffling.

import { mkdir, writeFile, rm } from "node:fs/promises";
import { dirname } from "node:path";

const [, , outDir = "bench/corpus", countStr = "200"] = process.argv;
const count = Number.parseInt(countStr, 10);
if (!Number.isFinite(count) || count <= 0) {
  console.error(`bad count: ${countStr}`);
  process.exit(1);
}

await rm(outDir, { recursive: true, force: true });
await mkdir(outDir, { recursive: true });

function bodyFor(i) {
  // TS surface that lowers cleanly: generics, narrowing on string-
  // literal unions, destructuring, template literals, plain helpers.
  // Classes are intentionally skipped because the emitter's class
  // desugar uses some non-final placeholders.
  const generic = `export function pair${i}<T, U>(t: T, u: U): { left: T; right: U } {
  return { left: t, right: u };
}`;
  const dispatch = `export function dispatch${i}(kind: "x" | "y" | "z", value: number): number {
  switch (kind) {
    case "x": return value + ${i};
    case "y": return value * 2 + ${i};
    case "z": return value - ${i};
  }
  return value;
}`;
  const helper = `export function helper${i}(input: number[]): number {
  let total = 0;
  for (const n of input) {
    total = total + n;
  }
  return total + ${i};
}`;
  const consumeOption = `export function describe${i}(opts: { label: string; count?: number }): string {
  const { label, count } = opts;
  const tail = count === undefined ? "?" : count.toString();
  return \`${i}-\${label}-\${tail}\`;
}`;
  return [generic, dispatch, helper, consumeOption].join("\n\n");
}

for (let i = 0; i < count; i = i + 1) {
  // Each module imports a small slice of its predecessors so the
  // bundle graph has both fan-in (multiple importers per file) and
  // fan-out (each importer pulls several names).
  const importLines = [];
  const importedNames = [];
  for (let j = Math.max(0, i - 4); j < i; j = j + 1) {
    importLines.push(
      `import { helper${j}, dispatch${j}, pair${j} } from "./mod-${j}";`,
    );
    importedNames.push(`helper${j}`, `dispatch${j}`, `pair${j}`);
  }
  const consume = importedNames.length
    ? `\n\nexport function consume${i}(seed: number): number {
  let acc = seed;
  ${importedNames
    .map((n, k) =>
      n.startsWith("helper")
        ? `acc = ${n}([acc, ${k}]);`
        : n.startsWith("dispatch")
          ? `acc = ${n}("x", acc);`
          : `acc = ${n}(acc, ${k}).left;`,
    )
    .join("\n  ")}
  return acc;
}`
    : "";
  const src = `${importLines.join("\n")}\n\n${bodyFor(i)}${consume}\n`;
  const path = `${outDir}/mod-${i}.ts`;
  await mkdir(dirname(path), { recursive: true });
  await writeFile(path, src);
}

// `entry.ts` deliberately imports + calls a function from every
// generated module so a tree-shaking bundler (rolldown, esbuild)
// can't prune the corpus. Without this, the bundlers' bundles
// collapse to a handful of statements and the comparison becomes
// uninteresting.
const importLines = [];
const callLines = [];
for (let i = 0; i < count; i = i + 1) {
  importLines.push(
    `import { helper${i}, dispatch${i}, pair${i}, describe${i} } from "./mod-${i}";`,
  );
  callLines.push(
    `acc = helper${i}([acc]); ` +
      `acc = dispatch${i}("x", acc); ` +
      `acc = pair${i}(acc, "k").left; ` +
      `tag = describe${i}({ label: tag });`,
  );
}
const entry = `${importLines.join("\n")}

let acc = 1;
let tag = "seed";
${callLines.join("\n")}
console.log(acc, tag);
`;
await writeFile(`${outDir}/entry.ts`, entry);

console.log(`generated ${count} modules under ${outDir}/`);
