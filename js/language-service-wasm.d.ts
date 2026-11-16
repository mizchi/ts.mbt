/**
 * The language service on the wasm-gc build of the checker.
 *
 * The same API as `language-service.d.ts`, loaded from a `.wasm`, for a
 * runtime with Wasm GC and the `js-string` builtins (a browser, a worker,
 * Node 22+). Nothing here imports a Node module.
 */

import type { LanguageService, LanguageServiceHost } from "./language-service.js";

export type {
  CompilerOptions,
  Diagnostic,
  DiagnosticSource,
  LanguageService,
  LanguageServiceHost,
  ResolvedModule,
  ScriptSnapshot,
} from "./language-service.js";
export {
  createMemoryHost,
  formatDiagnostic,
  formatDiagnostics,
} from "./language-service.js";

/** A `fetch` `Response`, or anything shaped like one. */
export interface ResponseLike {
  arrayBuffer(): Promise<ArrayBuffer>;
}

/**
 * The checker's bytes, a `fetch` of them, or a `WebAssembly.Module`
 * already compiled with `{ builtins: ["js-string"] }` (typed as `object`
 * so this file needs no DOM or WebAssembly lib).
 */
export type CheckerSource =
  | ArrayBuffer
  | ArrayBufferView
  | ResponseLike
  | PromiseLike<ResponseLike>
  | object;

/** What `loadLanguageService` returns: one instance, any number of hosts. */
export interface LanguageServiceFactory {
  /**
   * The same contract as `createLanguageService` in `language-service`,
   * with one addition: a root file name may not contain NUL. The roots
   * cross the wasm boundary NUL-separated, so the service throws a
   * `TypeError` for such a name rather than checking two files that do
   * not exist. No real path can contain one.
   */
  createLanguageService(host: LanguageServiceHost): LanguageService;
}

/**
 * Compile and instantiate the wasm-gc checker.
 *
 * Rejects with an explanatory error on an engine without the
 * `js-string` builtins.
 */
export function loadLanguageService(source: CheckerSource): Promise<LanguageServiceFactory>;
