import { transpileModule, ModuleKind, ScriptTarget } from "typescript";

const source = `const x: number = 42; export { x };`;
const result = transpileModule(source, {
  compilerOptions: { module: ModuleKind.ESNext, target: ScriptTarget.ES2020 },
});

if (result.outputText.includes("const x = 42") && result.outputText.includes("export { x }")) {
  console.log("typescript ok:", result.outputText.length, "bytes");
} else {
  console.log("typescript fail:", result.outputText.slice(0, 100));
}
