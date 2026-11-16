// The language service on the wasm-gc build of the checker.
//
// The same API as `language-service.mjs`, for a runtime that loads a
// `.wasm` rather than a `.js`: a browser, a worker, an edge runtime. It
// imports no Node module, so it runs anywhere with Wasm GC and the
// `js-string` builtins (Node 22, current Chromium and Firefox).
//
// The host is the same `LanguageServiceHost`-shaped object. A wasm
// module's imports are fixed when it is instantiated, so the host cannot
// be an argument at the boundary; instead the `mtsc_host` imports read a
// "current host" that each call sets for its own duration. Calls are
// synchronous, so one instance serves any number of hosts. Each call also
// gets a fresh read cache: the boundary asks `fileExists` and then
// `readFile` for the same path, and a host backed by real IO should not
// pay for both.

import {
  createMemoryHost,
  formatDiagnostic,
  formatDiagnostics,
} from "./hosts.mjs";

export { createMemoryHost, formatDiagnostic, formatDiagnostics };

/** `host.readFile(path)`, falling back to `getScriptSnapshot`. */
function readThroughHost(host, path) {
  try {
    if (typeof host.readFile === "function") {
      const text = host.readFile(path);
      return text === undefined || text === null ? undefined : String(text);
    }
    if (typeof host.getScriptSnapshot === "function") {
      const snapshot = host.getScriptSnapshot(path);
      if (snapshot === undefined || snapshot === null) return undefined;
      return snapshot.getText(0, snapshot.getLength());
    }
  } catch {
    // Resolution probes many paths that do not exist, and a host wired to
    // `fs.readFileSync` throws ENOENT for them: an ordinary answer.
  }
  return undefined;
}

/**
 * Compile the checker module.
 *
 * The `js-string` builtins are requested here, at compile time, which is
 * where the JS String Builtins proposal puts them; an engine that ignores
 * the option fails at instantiation instead, with the message below.
 */
async function compileChecker(source) {
  if (source instanceof WebAssembly.Module) return source;
  let bytes = source;
  if (bytes && typeof bytes.then === "function") bytes = await bytes;
  // A `Response` from `fetch`, or anything shaped like one.
  if (bytes && typeof bytes.arrayBuffer === "function") {
    bytes = await bytes.arrayBuffer();
  }
  return WebAssembly.compile(bytes, { builtins: ["js-string"] });
}

/**
 * Load the wasm-gc checker and return a factory for language services.
 *
 * @param {BufferSource | WebAssembly.Module | Response | PromiseLike<Response>} source
 *   The `mtsc.wasm` bytes (or a `fetch` of them). A precompiled
 *   `WebAssembly.Module` must have been compiled with
 *   `{ builtins: ["js-string"] }`.
 */
export async function loadLanguageService(source) {
  const module = await compileChecker(source);
  // MoonBit's string constants are imported from the `_` namespace, each
  // named by its own text (`importedStringConstants`). Supplying them as
  // values works whether or not the engine implements that option, which
  // Node 22 does not.
  const constants = {};
  for (const entry of WebAssembly.Module.imports(module)) {
    if (entry.module === "_") constants[entry.name] = entry.name;
  }
  let current = null;
  let cache = null;
  const read = (path) => {
    if (cache.has(path)) return cache.get(path);
    const text = readThroughHost(current, path);
    cache.set(path, text);
    return text;
  };
  const settings = () => {
    if (typeof current.getCompilationSettings !== "function") return {};
    return current.getCompilationSettings() ?? {};
  };
  const imports = {
    _: constants,
    mtsc_host: {
      fileExists: (path) => read(path) !== undefined,
      readFile: (path) => read(path) ?? "",
      directoryExists: (path) => {
        if (typeof current.directoryExists !== "function") return true;
        try {
          return !!current.directoryExists(path);
        } catch {
          return false;
        }
      },
      realpath: (path) => {
        if (typeof current.realpath !== "function") return path;
        try {
          const real = current.realpath(path);
          return typeof real === "string" && real.length > 0 ? real : path;
        } catch {
          return path;
        }
      },
      // `""` = use the built-in resolution, `"\u0000"` = do not follow,
      // anything else = the path. See `service_wasm.mbt`.
      resolveModuleName: (specifier, containingFile) => {
        if (typeof current.resolveModuleNames !== "function") return "";
        let answer;
        try {
          const out = current.resolveModuleNames([specifier], containingFile);
          answer = Array.isArray(out) ? out[0] : undefined;
        } catch {
          return "";
        }
        if (answer === null) return "\u0000";
        if (answer && typeof answer.resolvedFileName === "string" && answer.resolvedFileName) {
          return answer.resolvedFileName;
        }
        return "";
      },
      // NUL-separated: the one character no path can contain, so a root
      // whose name holds a newline survives the crossing. A host's VIRTUAL
      // name could still hold one, and splitting it would silently check
      // two files that do not exist, so such a name is refused instead.
      getScriptFileNames: () => {
        const names = current.getScriptFileNames();
        if (!Array.isArray(names)) return "";
        const roots = names.map(String);
        for (const name of roots) {
          if (name.includes("\u0000")) {
            throw new TypeError(
              `root file name ${JSON.stringify(name)} contains NUL, which the wasm-gc build cannot pass across its boundary`,
            );
          }
        }
        return roots.join("\u0000");
      },
      getCurrentDirectory: () => {
        if (typeof current.getCurrentDirectory !== "function") return ".";
        const dir = current.getCurrentDirectory();
        return typeof dir === "string" && dir.length > 0 ? dir : ".";
      },
      jsx: () => !!settings().jsx,
      skipLibCheck: () => !!settings().skipLibCheck,
    },
  };
  let instance;
  try {
    instance = await WebAssembly.instantiate(module, imports);
  } catch (error) {
    if (WebAssembly.Module.imports(module).some((i) => i.module === "wasm:js-string")) {
      throw new Error(
        "mtsc: this engine does not provide the WebAssembly `js-string` " +
          "builtins the checker is compiled against (Wasm GC + JS String " +
          `Builtins). Underlying error: ${error.message}`,
      );
    }
    throw error;
  }
  const exports = instance.exports;

  const call = (host, fn) => {
    const previousHost = current;
    const previousCache = cache;
    current = host;
    cache = new Map();
    try {
      return fn();
    } finally {
      current = previousHost;
      cache = previousCache;
    }
  };

  /**
   * A language service bound to `host` — the same contract as
   * `createLanguageService` in `language-service.mjs`.
   */
  const createLanguageService = (host) => {
    if (host === null || typeof host !== "object") {
      throw new TypeError("createLanguageService: host must be an object");
    }
    if (typeof host.getScriptFileNames !== "function") {
      throw new TypeError(
        "createLanguageService: host.getScriptFileNames must be a function",
      );
    }
    if (typeof host.readFile !== "function" && typeof host.getScriptSnapshot !== "function") {
      throw new TypeError("createLanguageService: host needs readFile or getScriptSnapshot");
    }
    return {
      getProgramDiagnostics: () =>
        JSON.parse(call(host, () => exports.getProgramDiagnostics())),
      getSemanticDiagnostics: (fileName) =>
        JSON.parse(call(host, () => exports.getSemanticDiagnostics(fileName))),
      getSyntacticDiagnostics: (fileName) =>
        JSON.parse(call(host, () => exports.getSyntacticDiagnostics(fileName))),
      getProgramFileNames: () => JSON.parse(call(host, () => exports.getProgramFileNames())),
      resolveModuleName: (containingFile, moduleName) =>
        JSON.parse(call(host, () => exports.resolveModuleName(containingFile, moduleName))),
      getHost: () => host,
    };
  };

  return { createLanguageService };
}
