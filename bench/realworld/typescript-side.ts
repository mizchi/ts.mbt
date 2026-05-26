// Side-effect import: typescript.js installs a `ts` runtime variable.
// `declare` lets the entry reference it without an explicit import binding.
import "typescript";
declare const ts: any;

const source = `const x: number = 42; export { x };`;
const result = ts.transpileModule(source, {
  compilerOptions: { module: ts.ModuleKind.ESNext, target: ts.ScriptTarget.ES2020 },
});

if (result.outputText.includes("const x = 42") && result.outputText.includes("export { x }")) {
  console.log("typescript ok:", result.outputText.length, "bytes");
} else {
  console.log("typescript fail:", result.outputText.slice(0, 100));
}
