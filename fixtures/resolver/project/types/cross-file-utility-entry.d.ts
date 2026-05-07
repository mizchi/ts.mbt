// Mirrors the puppeteer pattern:
//
//   export type CallFunctionOptions =
//     Omit<Bidi.Script.CallFunctionParameters,
//          'functionDeclaration' | 'awaitPromise' | 'target'>;
//
// `bidi` is a namespace alias for the sibling module that owns the
// concrete parameters interface; the bridge must walk the namespace
// import edge before the Omit projection runs so the resulting alias
// surfaces as a real struct.
import * as bidi from "./cross-file-utility-source";

export type CallFunctionOptions = Omit<
  bidi.CallFunctionParameters,
  "functionDeclaration" | "awaitPromise" | "target"
>;

export declare function call(opts: CallFunctionOptions): void;
