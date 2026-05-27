// Most aggressive test: full TypeScript Program with diagnostics.
import "typescript";
declare const ts: any;

const src = `
function add(a: number, b: number): number {
  return a + b;
}
const r1: number = add(1, 2);
const r2: string = add("a" as any, "b" as any);  // ok via 'as any'
const r3: number = "not a number";  // type error!
`;

const fileName = "test.ts";
const sourceFile = ts.createSourceFile(fileName, src, ts.ScriptTarget.ES2020);

// Minimal lib
const libContent = `
interface Boolean {}
interface Function {}
interface IArguments {}
interface Number { toString(): string; }
interface Object {}
interface RegExp {}
interface String { length: number; }
interface Array<T> { length: number; [n: number]: T; }
declare function isFinite(v: number): boolean;
`;
const libFile = "lib.d.ts";
const libSourceFile = ts.createSourceFile(libFile, libContent, ts.ScriptTarget.ES2020);

const host: any = {
  getSourceFile: (n: string) => n === fileName ? sourceFile : n === libFile ? libSourceFile : undefined,
  writeFile: () => {},
  getCurrentDirectory: () => "",
  getDirectories: () => [],
  fileExists: (n: string) => n === fileName || n === libFile,
  readFile: (n: string) => n === fileName ? src : n === libFile ? libContent : "",
  getCanonicalFileName: (n: string) => n,
  useCaseSensitiveFileNames: () => true,
  getNewLine: () => "\n",
  getDefaultLibFileName: () => libFile,
};

const program = ts.createProgram([fileName], { target: ts.ScriptTarget.ES2020, noLib: false }, host);
const diagnostics = ts.getPreEmitDiagnostics(program);

console.log("program ok: diagnostics =", diagnostics.length);
for (const d of diagnostics.slice(0, 5)) {
  const msg = ts.flattenDiagnosticMessageText(d.messageText, "\n");
  console.log("  diag:", msg.slice(0, 80));
}
