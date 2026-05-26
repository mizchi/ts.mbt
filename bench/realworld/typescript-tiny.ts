import "typescript";
declare const ts: any;
// Just check the API surface — don't actually compile.
console.log("typescript ok:", typeof ts.transpileModule, typeof ts.ModuleKind);
