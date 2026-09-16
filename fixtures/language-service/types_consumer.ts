// Compile `js/language-service.d.ts` the way a consumer would.
//
// A declaration file nobody compiles is a declaration file that drifts,
// so this imports it, uses every exported name, and lets `tsc --strict`
// prove the declarations are coherent. Run by
// `just verify-language-service-types`.
//
// It also pins the documented ABSENCE of `start` / `length` on a
// diagnostic, and the way it does that is worth reading, because the
// obvious spelling does not work. The first version was
//
//     // @ts-expect-error - diagnostics carry no span
//     const n: number = all[0]!.start;
//
// which passes whether or not `start` exists: add `start?: number` and
// the expression is `number | undefined`, which is still an error under
// `strict`, so the `@ts-expect-error` still has something to suppress.
// Measured — adding the field left `tsc` green. A test that cannot fail
// while the thing it checks is broken is coverage-shaped and proves
// nothing, so the assertion below is on `keyof` instead, which is
// exactly the claim being made.

import {
  checkModuleGraph,
  createLanguageService,
  createMemoryHost,
  createNodeHost,
  formatDiagnostic,
  formatDiagnostics,
  raw,
  type CompilerOptions,
  type Diagnostic,
  type DiagnosticSource,
  type LanguageService,
  type LanguageServiceHost,
  type ModuleEdge,
  type ModuleSource,
  type ResolvedModule,
  type ScriptSnapshot,
} from "../../js/language-service.js";

// --- The documented absence of a span --------------------------------------

/** `true` only if `K` is a key of `Diagnostic`. */
type HasKey<K extends string> = K extends keyof Diagnostic ? true : false;

// Both must be `false`. Adding `start` or `length` to `Diagnostic` makes
// the corresponding type `true` and fails this file — which is the point:
// if the checker ever gains real offsets, this is the line that says the
// documentation has to change with it.
const hasStart: HasKey<"start"> = false;
const hasLength: HasKey<"length"> = false;

// And the keys it does have, so a rename is caught rather than silently
// shipped to consumers.
const diagnosticKeys: Array<keyof Diagnostic> = [
  "file",
  "category",
  "source",
  "messageText",
  "context",
];

// --- Hosts ------------------------------------------------------------------

const memoryHost: LanguageServiceHost = createMemoryHost({
  "a.ts": "export const a: number = 1;",
});

const rootedHost: LanguageServiceHost = createMemoryHost(
  { "a.ts": "export const a = 1;", "b.ts": "export const b = 2;" },
  { rootNames: ["a.ts"], currentDirectory: "/work" },
);

const jsxOptions: CompilerOptions = { jsx: true };
const nodeHost: LanguageServiceHost = createNodeHost(["a.ts"], {
  compilerOptions: jsxOptions,
  currentDirectory: "/work",
});

// A `ts.LanguageServiceHost`-shaped host: `getScriptSnapshot`, no
// `readFile`. This is the compatibility claim the API makes, so the type
// has to admit it.
const snapshotHost: LanguageServiceHost = {
  getScriptFileNames: () => ["a.ts"],
  getCurrentDirectory: () => "/work",
  getCompilationSettings: () => ({}),
  getScriptSnapshot: (fileName: string): ScriptSnapshot | undefined =>
    fileName === "a.ts"
      ? { getText: (s: number, e: number) => "export const a = 1;".slice(s, e), getLength: () => 19 }
      : undefined,
};

// --- The service ------------------------------------------------------------

const service: LanguageService = createLanguageService(memoryHost);

const all: Diagnostic[] = service.getProgramDiagnostics();
const semantic: Diagnostic[] = service.getSemanticDiagnostics("a.ts");
const syntactic: Diagnostic[] = service.getSyntacticDiagnostics("a.ts");
const fileNames: string[] = service.getProgramFileNames();
const resolved: ResolvedModule = service.resolveModuleName("a.ts", "./b");
const boundHost: LanguageServiceHost = service.getHost();

// `source` has to narrow, or the union is decoration.
function describe(diagnostic: Diagnostic): string {
  const source: DiagnosticSource = diagnostic.source;
  switch (source) {
    case "syntactic":
      return `parse: ${diagnostic.messageText}`;
    case "semantic":
      return `type: ${diagnostic.messageText}`;
    case "import":
      return `module: ${diagnostic.messageText}`;
  }
}

const rendered: string = formatDiagnostic(all[0]!);
const renderedAll: string = formatDiagnostics(all);

// --- The original ABI -------------------------------------------------------

const modules: ModuleSource[] = [
  { path: "a.ts", source: "export const a: number = 1;", allowJsx: false },
];
const edges: ModuleEdge[] = [];
const legacy: string = checkModuleGraph({ modules, edges });

// --- Keep every binding used, so `noUnusedLocals` stays available ----------

export const surface = {
  hasStart,
  hasLength,
  diagnosticKeys,
  rootedHost,
  nodeHost,
  snapshotHost,
  boundHost,
  all,
  semantic,
  syntactic,
  fileNames,
  resolved,
  describe,
  rendered,
  renderedAll,
  legacy,
  raw,
};
