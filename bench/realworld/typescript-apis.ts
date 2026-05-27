// Stress various TypeScript API surfaces through the full minify pipeline.
import "typescript";
declare const ts: any;

let ok = 0, fail = 0;

function check(name: string, cond: boolean, extra?: any) {
  if (cond) { ok++; }
  else { fail++; console.log(`FAIL ${name}: ${JSON.stringify(extra)}`); }
}

// 1. transpileModule — basic
{
  const r = ts.transpileModule(`const x: number = 42; export { x };`, {
    compilerOptions: { module: ts.ModuleKind.ESNext, target: ts.ScriptTarget.ES2020 },
  });
  check("transpileModule.basic", r.outputText.includes("const x = 42"), r.outputText);
}

// 2. transpileModule with JSX
{
  const r = ts.transpileModule(`const e = <div>hi</div>; export { e };`, {
    compilerOptions: { module: ts.ModuleKind.ESNext, target: ts.ScriptTarget.ES2020, jsx: ts.JsxEmit.React },
    fileName: "test.tsx",
  });
  check("transpileModule.jsx", r.outputText.includes("React.createElement"), r.outputText);
}

// 3. transpileModule downlevel ES5
{
  const r = ts.transpileModule(`class C { m() { return 1; } }`, {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES5 },
  });
  check("transpileModule.es5", r.outputText.includes("function ") && r.outputText.includes("prototype"), r.outputText);
}

// 4. createSourceFile — parse a non-trivial file
{
  const src = `
    interface Foo { x: number; y: string; }
    function bar(f: Foo): number { return f.x; }
    const z: Foo = { x: 1, y: "hi" };
    bar(z);
  `;
  const sf = ts.createSourceFile("t.ts", src, ts.ScriptTarget.ES2020);
  check("createSourceFile.kind", sf.kind === 308, sf.kind);  // SourceFile = 308
  check("createSourceFile.statements", sf.statements.length === 4, sf.statements.length);
}

// 5. AST walk — count nodes by kind
{
  const src = `function add(a: number, b: number) { return a + b; } add(1, 2);`;
  const sf = ts.createSourceFile("t.ts", src, ts.ScriptTarget.ES2020);
  let count = 0;
  function walk(node: any) {
    count++;
    ts.forEachChild(node, walk);
  }
  walk(sf);
  check("forEachChild.walk", count > 10, count);
}

// 6. Diagnostics
{
  const r = ts.transpileModule(`const x: string = 42;`, {
    compilerOptions: { module: ts.ModuleKind.ESNext, target: ts.ScriptTarget.ES2020 },
    reportDiagnostics: true,
  });
  // transpileModule doesn't run typechecker, so we expect no diagnostics here
  check("transpileModule.no_typecheck", Array.isArray(r.diagnostics), r.diagnostics);
}

// 7. JsxEmit constants
{
  check("JsxEmit.Preserve", typeof ts.JsxEmit.Preserve === "number", ts.JsxEmit.Preserve);
  check("JsxEmit.React", typeof ts.JsxEmit.React === "number", ts.JsxEmit.React);
}

// 8. ModuleKind / ScriptTarget enums
{
  check("ModuleKind.ESNext", ts.ModuleKind.ESNext === 99, ts.ModuleKind.ESNext);
  check("ScriptTarget.ES2020", ts.ScriptTarget.ES2020 === 7, ts.ScriptTarget.ES2020);
}

// 9. SyntaxKind helpers
{
  const sf = ts.createSourceFile("t.ts", "const x = 1;", ts.ScriptTarget.ES2020);
  const stmt = sf.statements[0];
  check("syntaxKind.VariableStatement",
    ts.SyntaxKind[stmt.kind] === "VariableStatement" || stmt.kind === ts.SyntaxKind.VariableStatement,
    { kind: stmt.kind, name: ts.SyntaxKind[stmt.kind] });
}

// 10. transpileModule with arrow / async
{
  const r = ts.transpileModule(`
    const f = async (x: number) => x + 1;
    export { f };
  `, {
    compilerOptions: { module: ts.ModuleKind.ESNext, target: ts.ScriptTarget.ES2020 },
  });
  check("transpileModule.arrow_async",
    r.outputText.includes("async") && r.outputText.includes("=>"),
    r.outputText);
}

console.log(`typescript ok: ${ok} passed, ${fail} failed`);
