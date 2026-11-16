// A `ts.LanguageService`-shaped facade over the MoonBit type checker.
//
// The MoonBit side (`src/mtsc`) exports free functions that each take a
// host, because a link export is one symbol and a generic function is
// one symbol per host type. This file is the ergonomic layer on top:
// `createLanguageService(host)` closes over the host the way
// `ts.createLanguageService` does, so calling code reads the same as it
// would against TypeScript.
//
// It also ships the two hosts most callers want. `createMemoryHost` is
// the bundler-plugin case (sources already in hand); `createNodeHost` is
// ten lines of `node:fs` and exists to demonstrate the point of the
// abstraction — the checker does real filesystem IO without containing
// any, because the host is injected.
//
// What is deliberately NOT here: completions, quick info, definitions,
// rename, formatting. All of them need a position, and the checker
// produces messages without offsets (see `MtscDiagnostic` in
// `src/mtsc/service.mbt`), so those methods would be a shape with
// nothing behind them.

import { existsSync } from "node:fs";
import { dirname, isAbsolute, resolve as resolvePath } from "node:path";
import { fileURLToPath } from "node:url";

/**
 * Where the compiled MoonBit module might be.
 *
 * `./mtsc.js` first: that is where a packaging step copies the artifact,
 * and it is what a published npm package would contain. The `_build`
 * paths are the in-repo development case, release before debug so a
 * `just`-driven build is measured rather than whatever a debug build
 * left behind — the same stale-artifact trap this repo records for
 * `moon build --target native` producing DEBUG.
 */
function bindingCandidates() {
  const override = process.env.MTSC_JS_BINDINGS;
  if (override) {
    return [isAbsolute(override) ? override : resolvePath(override)];
  }
  const here = dirname(fileURLToPath(import.meta.url));
  return [
    resolvePath(here, "mtsc.js"),
    resolvePath(here, "..", "_build", "js", "release", "build", "mtsc", "mtsc.js"),
    resolvePath(here, "..", "_build", "js", "debug", "build", "mtsc", "mtsc.js"),
  ];
}

/**
 * Load the compiled checker.
 *
 * A missing file is tried past; anything else is rethrown. Swallowing
 * every error would turn a genuine fault inside the module into the same
 * "could not find the build" message, which is the fail-open shape that
 * makes a real bug look like a configuration problem.
 */
async function loadBindings() {
  const candidates = bindingCandidates();
  for (const candidate of candidates) {
    if (!existsSync(candidate)) continue;
    return await import(candidate);
  }
  throw new Error(
    "mtsc: no compiled JavaScript checker found. Build it with " +
      "`moon build --target js` (or `just build-js`), or point " +
      "MTSC_JS_BINDINGS at the emitted mtsc.js. Looked in:\n  " +
      candidates.join("\n  "),
  );
}

// Top-level await, so every export below is synchronous and the API
// matches `ts.createLanguageService`, which is not async either.
const bindings = await loadBindings();

/**
 * @typedef {object} CompilerOptions
 * @property {boolean} [jsx] Parse JSX in files whose extension does not
 *   already imply it. `.tsx` / `.jsx` always allow it.
 * @property {boolean} [skipLibCheck] Report nothing inside declaration
 *   files that are not roots. A dependency's `.d.ts` under
 *   `node_modules` is never reported on either way.
 */

/**
 * @typedef {object} LanguageServiceHost
 * @property {() => string[]} getScriptFileNames The program's roots.
 * @property {(fileName: string) => string | undefined} [readFile]
 * @property {(fileName: string) => { getText(start: number, end: number): string, getLength(): number } | undefined} [getScriptSnapshot]
 *   Used when `readFile` is absent, so a real `ts.LanguageServiceHost`
 *   works unchanged.
 * @property {() => string} [getCurrentDirectory]
 * @property {() => CompilerOptions} [getCompilationSettings]
 * @property {(directoryName: string) => boolean} [directoryExists]
 *   Asked before a package directory's manifest is read. Absent means
 *   "yes", and the file probes decide, as in TypeScript.
 * @property {(path: string) => string} [realpath] Symlinks resolved, so
 *   one pnpm package reached through several links loads once. Applied to
 *   the built-in resolution's answer for a bare specifier only (as tsc
 *   realpaths a package file, not a relative one); a `resolveModuleNames`
 *   path is used as given, so a host canonicalizes its own answers.
 * @property {(moduleNames: string[], containingFile: string) => ({ resolvedFileName: string } | undefined | null)[]} [resolveModuleNames]
 *   The host's own resolution, asked first. `undefined` for a name means
 *   "use the built-in resolution"; `null` means "do not follow it".
 */

/**
 * @typedef {object} Diagnostic
 * @property {string} file
 * @property {"error"} category
 * @property {"syntactic" | "semantic" | "import"} source
 * @property {string} messageText
 * @property {string} context Dotted breadcrumb, or `""`.
 */

/**
 * A language service bound to `host`.
 *
 * @param {LanguageServiceHost} host
 */
export function createLanguageService(host) {
  if (host === null || typeof host !== "object") {
    throw new TypeError("createLanguageService: host must be an object");
  }
  if (typeof host.getScriptFileNames !== "function") {
    // Worth failing loudly on: without roots the program is empty, every
    // query returns nothing, and "no diagnostics" is indistinguishable
    // from "clean".
    throw new TypeError(
      "createLanguageService: host.getScriptFileNames must be a function",
    );
  }
  if (
    typeof host.readFile !== "function" &&
    typeof host.getScriptSnapshot !== "function"
  ) {
    throw new TypeError(
      "createLanguageService: host needs readFile or getScriptSnapshot",
    );
  }
  return {
    /** Every diagnostic in the program. @returns {Diagnostic[]} */
    getProgramDiagnostics: () => bindings.getProgramDiagnostics(host),
    /** Type errors for one file. @returns {Diagnostic[]} */
    getSemanticDiagnostics: (fileName) =>
      bindings.getSemanticDiagnostics(host, fileName),
    /** Parse errors for one file. @returns {Diagnostic[]} */
    getSyntacticDiagnostics: (fileName) =>
      bindings.getSyntacticDiagnostics(host, fileName),
    /** Roots plus everything they reach. @returns {string[]} */
    getProgramFileNames: () => bindings.getProgramFileNames(host),
    /**
     * Resolve one specifier as the loader would: the host's
     * `resolveModuleNames` first, then relative paths, `node_modules`
     * (`exports` with the `types` condition, `types`, `typesVersions`,
     * `@types`), `node:` builtins, tsconfig `paths` and package `imports`,
     * every file read through the host.
     *
     * `isExternal` separates "no such file" from "not followed": a bare
     * specifier nothing resolves, or one the host answered `null` for.
     */
    resolveModuleName: (containingFile, moduleName) =>
      bindings.resolveModuleName(host, containingFile, moduleName),
    getHost: () => host,
  };
}

// The hosts and the formatting live in their own modules so the wasm
// facade (`language-service-wasm.mjs`) can share them without importing
// `node:fs`, and are re-exported here so this module's API is unchanged.
export { createMemoryHost, formatDiagnostic, formatDiagnostics } from "./hosts.mjs";
export { createNodeHost } from "./node-host.mjs";

/**
 * The original pre-resolved-graph ABI, unchanged.
 *
 * Kept because it has consumers outside this repo. A caller who already
 * has a resolved module graph does not need a host; one who does not
 * should use `createLanguageService` and let resolution happen here.
 */
export const checkModuleGraph = bindings.checkModuleGraph;

/**
 * The raw MoonBit exports.
 *
 * An escape hatch, and a deliberate one: the facade is a subset, so a
 * caller who needs an entry point it does not wrap should not have to
 * reach into `_build` to get it.
 */
export const raw = bindings;
