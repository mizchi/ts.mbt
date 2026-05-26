import "typescript";
declare const ts: any;
// createSourceFile is simpler — exercises the parser.
const sf = ts.createSourceFile("test.ts", "const x = 42;", ts.ScriptTarget.ES2020);
console.log("typescript ok:", sf.kind, sf.fileName, sf.statements?.length);
