// Compile `js/language-service-wasm.d.ts` the way a consumer would, with
// no DOM or WebAssembly lib, which is the reason its source type is
// structural. Run by `just verify-language-service-types`.

import {
  createMemoryHost,
  formatDiagnostics,
  loadLanguageService,
  type CheckerSource,
  type Diagnostic,
  type LanguageService,
  type LanguageServiceFactory,
  type ResponseLike,
} from "../../js/language-service-wasm.js";

declare const bytes: ArrayBuffer;
declare const fetched: PromiseLike<ResponseLike>;

const sources: CheckerSource[] = [bytes, new Uint8Array(bytes), fetched];

async function use(): Promise<string> {
  const factory: LanguageServiceFactory = await loadLanguageService(bytes);
  const service: LanguageService = factory.createLanguageService(
    createMemoryHost({ "/a.ts": "export const a: number = 1;" }),
  );
  const all: Diagnostic[] = service.getProgramDiagnostics();
  return formatDiagnostics(all);
}

export const surface = { sources, use };
