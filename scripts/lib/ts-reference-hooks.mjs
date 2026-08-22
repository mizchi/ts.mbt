// Module-resolution hooks for the reference run.
//
// The reference leg executes a case's ORIGINAL TypeScript through Node's
// type stripping, which needs two things Node won't do on its own:
//
//   * extensionless relative specifiers — TypeScript sources write
//     `from "./sub"`, Node wants `./sub.ts`;
//   * the bare specifiers a case declares as external — those resolve to
//     the stub the harness generated for the compiled runs, so all three
//     variants talk to the same fake package.
//
// The stub directory arrives through `MANGLE_SAFETY_STUB_ROOT`, since
// hooks get no arguments of their own.

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const STUB_ROOT = process.env.MANGLE_SAFETY_STUB_ROOT ?? "";

function firstExisting(candidates) {
  for (const candidate of candidates) {
    try {
      if (fs.statSync(candidate).isFile()) return candidate;
    } catch {
      // Not there; try the next shape.
    }
  }
  return null;
}

export function resolve(specifier, context, next) {
  if (specifier.startsWith("./") || specifier.startsWith("../")) {
    const parent = context.parentURL;
    if (parent && parent.startsWith("file:")) {
      const target = fileURLToPath(new URL(specifier, parent));
      const found = firstExisting([
        target,
        `${target}.ts`,
        `${target}.tsx`,
        path.join(target, "index.ts"),
        path.join(target, "index.tsx"),
      ]);
      if (found) return next(pathToFileURL(found).href, context);
    }
    return next(specifier, context);
  }
  // A bare specifier the case stubbed out.
  if (STUB_ROOT && !specifier.startsWith("node:")) {
    const pkgDir = path.join(STUB_ROOT, ...specifier.split("/"));
    const found = firstExisting([
      path.join(pkgDir, "index.mjs"),
      `${pkgDir}.mjs`,
    ]);
    if (found) return next(pathToFileURL(found).href, context);
  }
  return next(specifier, context);
}
