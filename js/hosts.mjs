// Hosts and formatting that need nothing but JavaScript.
//
// Shared by `language-service.mjs` (the JS build, Node) and
// `language-service-wasm.mjs` (the wasm-gc build, any runtime with Wasm
// GC — a browser included), which is why nothing here imports a Node
// module.

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
    // A directory exists when some file lives under it; answering `true`
    // everywhere would make every package probe read a manifest that is
    // not there.
    directoryExists: (directoryName) => {
      const prefix = directoryName.endsWith("/") ? directoryName : directoryName + "/";
      return Object.keys(files).some((f) => f.startsWith(prefix));
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

