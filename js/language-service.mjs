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

import { existsSync, readFileSync, statSync } from "node:fs";
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
     * Resolve one specifier as the loader would.
     *
     * `isExternal` separates "no such file" from "not this resolver's
     * job": a bare specifier like `react` needs package resolution,
     * which this service does not do.
     */
    resolveModuleName: (containingFile, moduleName) =>
      bindings.resolveModuleName(host, containingFile, moduleName),
    getHost: () => host,
  };
}

/**
 * A host over an object of `{ [fileName]: sourceText }`.
 *
 * Every file is a root unless `rootNames` says otherwise, which is the
 * common meaning of "check all of this" — a root set that drifts from
 * the file set is a quiet way to check nothing.
 *
 * @param {Record<string, string>} files
 * @param {{ rootNames?: string[], currentDirectory?: string, compilerOptions?: CompilerOptions }} [options]
 * @returns {LanguageServiceHost}
 */
export function createMemoryHost(files, options = {}) {
  const roots = options.rootNames ?? Object.keys(files);
  const cwd = options.currentDirectory ?? ".";
  const compilerOptions = options.compilerOptions ?? {};
  return {
    getScriptFileNames: () => roots,
    getCurrentDirectory: () => cwd,
    getCompilationSettings: () => compilerOptions,
    readFile: (fileName) =>
      Object.prototype.hasOwnProperty.call(files, fileName)
        ? files[fileName]
        : undefined,
  };
}

/**
 * A host that reads the real filesystem.
 *
 * Ten lines, and that is the argument for the abstraction: the checker
 * has no filesystem in it, so this is all it takes to give it one.
 *
 * @param {string[]} rootNames
 * @param {{ currentDirectory?: string, compilerOptions?: CompilerOptions }} [options]
 * @returns {LanguageServiceHost}
 */
export function createNodeHost(rootNames, options = {}) {
  const cwd = options.currentDirectory ?? process.cwd();
  const compilerOptions = options.compilerOptions ?? {};
  return {
    getScriptFileNames: () => rootNames,
    getCurrentDirectory: () => cwd,
    getCompilationSettings: () => compilerOptions,
    readFile: (fileName) => {
      try {
        // A directory is readable but is not a source file, and
        // resolution probes paths that may be either.
        if (!statSync(fileName).isFile()) return undefined;
        return readFileSync(fileName, "utf8");
      } catch {
        // ENOENT is the ordinary answer while probing candidates, not a
        // fault; anything else (EACCES, EISDIR) is equally "no source
        // here" from the checker's point of view.
        return undefined;
      }
    },
  };
}

/**
 * One diagnostic as a line, in `tsc`'s `file: message` shape.
 *
 * The breadcrumb is appended in parentheses because there is no line and
 * column to print: the checker reports where in a declaration the
 * problem is, not where in the text.
 *
 * @param {Diagnostic} diagnostic
 */
export function formatDiagnostic(diagnostic) {
  const where = diagnostic.context ? ` (${diagnostic.context})` : "";
  return `${diagnostic.file}: ${diagnostic.category}: ${diagnostic.messageText}${where}`;
}

/**
 * @param {Diagnostic[]} diagnostics
 */
export function formatDiagnostics(diagnostics) {
  return diagnostics.map(formatDiagnostic).join("\n");
}

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
