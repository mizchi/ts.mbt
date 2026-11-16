/**
 * A `ts.LanguageService`-shaped facade over the MoonBit type checker.
 *
 * The names mirror TypeScript's so an integration written against
 * `ts.LanguageService` reads the same here. The surface is a subset, and
 * the missing part is not arbitrary: completions, quick info,
 * definitions, rename and formatting all need a position, and this
 * checker reports messages without offsets — see `Diagnostic` below.
 */

/** The compiler options this checker honours. */
export interface CompilerOptions {
  /**
   * Parse JSX in files whose extension does not already imply it.
   * `.tsx` and `.jsx` always allow JSX regardless, the way `tsc`
   * decides it from the extension.
   */
  jsx?: boolean;
  /**
   * Report nothing inside declaration files that are not roots. A
   * dependency's `.d.ts` under `node_modules` is read for its
   * declarations and never reported on either way.
   */
  skipLibCheck?: boolean;
}

/** A snapshot of a file's text, as `ts.IScriptSnapshot`. */
export interface ScriptSnapshot {
  getText(start: number, end: number): string;
  getLength(): number;
}

/**
 * The IO the checker needs, supplied by you.
 *
 * Structurally a subset of `ts.LanguageServiceHost`, so an existing one
 * can be passed straight in. Either `readFile` or `getScriptSnapshot`
 * must be present; `readFile` wins when both are.
 */
export interface LanguageServiceHost {
  /**
   * The program's root files. Everything they import is discovered from
   * them, so list entry points rather than the whole tree.
   */
  getScriptFileNames(): string[];
  /**
   * The text at `fileName`, or `undefined` when there is nothing there.
   *
   * This doubles as the existence check the module resolver uses, so it
   * is called for candidate paths that will not exist — returning
   * `undefined` (rather than throwing) is the expected answer for those.
   */
  readFile?(fileName: string): string | undefined;
  /** Used when `readFile` is absent. */
  getScriptSnapshot?(fileName: string): ScriptSnapshot | undefined;
  /** Base for resolving a relative root name. Defaults to `"."`. */
  getCurrentDirectory?(): string;
  getCompilationSettings?(): CompilerOptions;
  /**
   * Whether `directoryName` is a directory. Asked before a package
   * directory's manifest is read; absent means "yes", and the file probes
   * decide, as in TypeScript.
   */
  directoryExists?(directoryName: string): boolean;
  /**
   * `path` with symlinks resolved. Absent means `path`. With it, one pnpm
   * package reached through several links enters the program once.
   */
  realpath?(path: string): string;
  /**
   * The host's own resolution, asked before the built-in one — the
   * `ts.LanguageServiceHost` hook of the same name. Called with one name
   * at a time. For each name, `undefined` means "use the built-in
   * resolution" (so a host that maps only its own aliases need not
   * reimplement `node_modules`), and `null` means "do not follow this
   * import", which reports nothing for it.
   */
  resolveModuleNames?(
    moduleNames: string[],
    containingFile: string,
  ): ({ resolvedFileName: string } | undefined | null)[];
}

/**
 * Which phase produced a diagnostic.
 *
 * `import` covers an unresolvable module specifier and a missing export.
 * It is grouped with the semantic set by `getSemanticDiagnostics`,
 * because the file parses — the same way TypeScript classifies it.
 */
export type DiagnosticSource = "syntactic" | "semantic" | "import";

/**
 * One diagnostic.
 *
 * Note what is missing: there is no `start` and no `length`. The checker
 * is declaration-level and its diagnostics carry a message and a
 * breadcrumb, not a text offset, so there is no span to report and
 * inventing one would put a marker under the wrong code. `ts.Diagnostic`
 * declares both as optional for exactly this case, so a consumer that
 * checks before using them keeps working.
 *
 * `context` is what stands in for a span: the checker's dotted path to
 * the point of failure, e.g. `function foo > return`.
 */
export interface Diagnostic {
  /** The file, as the host spelled it. */
  file: string;
  /** Always `"error"`; the checker has no warning tier. */
  category: "error";
  source: DiagnosticSource;
  messageText: string;
  /** Dotted breadcrumb, or `""` when there is none. */
  context: string;
}

/** Where a specifier resolved. */
export interface ResolvedModule {
  /** The resolved path, or `""` when nothing resolved. */
  resolvedFileName: string;
  /**
   * `true` when the import is not followed: a bare specifier nothing
   * resolved, or one the host's `resolveModuleNames` answered `null` for.
   *
   * This separates "no such file" (a relative import with nothing there,
   * which is reported) from "not followed" (which is not). Package
   * resolution — npm `exports` with the `types` condition, `types`,
   * `typesVersions`, `@types/*`, `node:*` through `@types/node`, tsconfig
   * `paths`, package `imports` — is done here, every file read through
   * the host.
   */
  isExternal: boolean;
}

export interface LanguageService {
  /**
   * Every diagnostic in the program, in one pass.
   *
   * This is what "check everything" should call — see the cost note on
   * `getSemanticDiagnostics`.
   */
  getProgramDiagnostics(): Diagnostic[];
  /**
   * Type errors for one file.
   *
   * The whole program is loaded to answer this, and has to be: the
   * file's types depend on the declarations its imports supply. That
   * makes it a real cost — **one call is one whole-program load, so a
   * loop over every file is quadratic in the program.** Use
   * `getProgramDiagnostics()` for that and filter by `file`.
   *
   * There is no per-file cache, deliberately: invalidating one needs a
   * version channel on the host (TypeScript's `getScriptVersion`), this
   * host has none, and a cache with no invalidation is worse than a
   * documented cost.
   */
  getSemanticDiagnostics(fileName: string): Diagnostic[];
  /** Parse errors for one file. Same cost as the above. */
  getSyntacticDiagnostics(fileName: string): Diagnostic[];
  /** Roots plus every file reachable from them. */
  getProgramFileNames(): string[];
  resolveModuleName(containingFile: string, moduleName: string): ResolvedModule;
  getHost(): LanguageServiceHost;
}

/**
 * A language service bound to `host`.
 *
 * Throws if the host cannot name roots or cannot read files — an empty
 * program answers every query with nothing, which is indistinguishable
 * from a clean one.
 */
export function createLanguageService(host: LanguageServiceHost): LanguageService;

/** A host over an object of file name to source text. */
export function createMemoryHost(
  files: Record<string, string>,
  options?: {
    /** Defaults to every key of `files`. */
    rootNames?: string[];
    currentDirectory?: string;
    compilerOptions?: CompilerOptions;
  },
): LanguageServiceHost;

/** A host that reads the real filesystem through `node:fs`. */
export function createNodeHost(
  rootNames: string[],
  options?: {
    currentDirectory?: string;
    compilerOptions?: CompilerOptions;
  },
): LanguageServiceHost;

/** One diagnostic as a `file: message` line. */
export function formatDiagnostic(diagnostic: Diagnostic): string;

/** `formatDiagnostic` over a list, newline-joined. */
export function formatDiagnostics(diagnostics: Diagnostic[]): string;

/** A caller-resolved module, for `checkModuleGraph`. */
export interface ModuleSource {
  path: string;
  source: string;
  allowJsx: boolean;
}

/** A caller-resolved import edge, for `checkModuleGraph`. */
export interface ModuleEdge {
  importerPath: string;
  moduleSpecifier: string;
  targetPath: string;
}

/**
 * The original ABI: check a graph the caller has already resolved.
 *
 * Returns one diagnostic per line as `<path>: <message>`, or `""` when
 * the program is clean. Kept unchanged because it has consumers; prefer
 * `createLanguageService`, which resolves for you and returns structured
 * diagnostics.
 */
export function checkModuleGraph(graph: {
  modules: ModuleSource[];
  edges: ModuleEdge[];
}): string;

/** The raw MoonBit exports, for an entry point the facade does not wrap. */
export const raw: Record<string, unknown>;
