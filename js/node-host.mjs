// The Node host: a `LanguageServiceHost` over the real filesystem.
//
// Its own module because it imports `node:fs`, which a browser cannot
// load; `language-service.mjs` re-exports it.

import { readFileSync, realpathSync, statSync } from "node:fs";

/**
 * A host that reads the real filesystem.
 *
 * A few lines, and that is the argument for the abstraction: the checker
 * has no filesystem in it, so this is all it takes to give it one —
 * `node_modules` resolution included, since that only ever asks the host.
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
    directoryExists: (directoryName) => {
      try {
        return statSync(directoryName).isDirectory();
      } catch {
        return false;
      }
    },
    realpath: (path) => {
      try {
        return realpathSync(path);
      } catch {
        return path;
      }
    },
  };
}

