// More aggressive TypeScript API tests.
import "typescript";
declare const ts: any;

let ok = 0, fail = 0;
function check(name: string, cond: boolean, extra?: any) {
  if (cond) ok++;
  else { fail++; console.log(`FAIL ${name}: ${JSON.stringify(extra).slice(0, 200)}`); }
}

// 1. Type checker — full compiler program
{
  const src = `
    function add(a: number, b: number): number { return a + b; }
    const r = add(1, 2);
    export { r };
  `;
  const fileName = "test.ts";
  const sourceFile = ts.createSourceFile(fileName, src, ts.ScriptTarget.ES2020);
  // Create a virtual host
  const host: any = {
    getSourceFile: (name: string) => name === fileName ? sourceFile : undefined,
    writeFile: () => {},
    getCurrentDirectory: () => "",
    getDirectories: () => [],
    fileExists: (name: string) => name === fileName,
    readFile: () => "",
    getCanonicalFileName: (n: string) => n,
    useCaseSensitiveFileNames: () => true,
    getNewLine: () => "\n",
    getDefaultLibFileName: () => "lib.d.ts",
  };
  const program = ts.createProgram([fileName], { noLib: true, target: ts.ScriptTarget.ES2020 }, host);
  check("createProgram", typeof program === "object" && program !== null, typeof program);
  const checker = program.getTypeChecker();
  check("getTypeChecker", typeof checker === "object", typeof checker);
}

// 2. Factory API — synthesize a node
{
  const f = ts.factory;
  const id = f.createIdentifier("foo");
  check("factory.createIdentifier", id.escapedText === "foo", id.escapedText);

  const num = f.createNumericLiteral(42);
  check("factory.createNumericLiteral", num.text === "42", num.text);

  const stmt = f.createVariableStatement(
    undefined,
    f.createVariableDeclarationList(
      [f.createVariableDeclaration(id, undefined, undefined, num)],
      ts.NodeFlags.Const
    )
  );
  check("factory.createVariableStatement", stmt.kind === ts.SyntaxKind.VariableStatement, stmt.kind);
}

// 3. Printer — round-trip
{
  const sf = ts.createSourceFile("t.ts",
    "function greet(name: string): string {\n    return `Hello, ${name}!`;\n}",
    ts.ScriptTarget.ES2020);
  const printer = ts.createPrinter({ newLine: ts.NewLineKind.LineFeed });
  const out = printer.printFile(sf);
  check("createPrinter.printFile",
    out.includes("function greet") && out.includes("Hello"),
    out.slice(0, 80));
}

// 4. transformer — strip type annotations using transpileModule
{
  const r = ts.transpileModule(`type T = { x: number; }; const t: T = { x: 1 };`, {
    compilerOptions: { module: ts.ModuleKind.ESNext, target: ts.ScriptTarget.ES2020 },
  });
  check("transpile.strip_types",
    !r.outputText.includes("type T") && r.outputText.includes("const t"),
    r.outputText);
}

// 5. Enum decay
{
  const r = ts.transpileModule(`enum E { A = 1, B = 2 } const x = E.A;`, {
    compilerOptions: { module: ts.ModuleKind.ESNext, target: ts.ScriptTarget.ES2020 },
  });
  check("transpile.enum",
    r.outputText.includes("E[\"A\"] = 1") || r.outputText.includes("E[E.A = 1] = \"A\"") || r.outputText.includes('E["A"]'),
    r.outputText.slice(0, 200));
}

// 6. Decorators
{
  const r = ts.transpileModule(`
    function dec(t: any) {}
    @dec
    class C {}
  `, {
    compilerOptions: {
      module: ts.ModuleKind.ESNext, target: ts.ScriptTarget.ES2020,
      experimentalDecorators: true, emitDecoratorMetadata: false,
    },
  });
  check("transpile.decorator",
    r.outputText.includes("__decorate") || r.outputText.includes("dec("),
    r.outputText.slice(0, 200));
}

// 7. Optional chaining / nullish
{
  const r = ts.transpileModule(`const a: any = {}; const b = a?.b ?? "default";`, {
    compilerOptions: { module: ts.ModuleKind.ESNext, target: ts.ScriptTarget.ES2020 },
  });
  check("transpile.optional_chain", r.outputText.includes("?.") || r.outputText.includes("=== null"), r.outputText);
}

// 8. Async/await
{
  const r = ts.transpileModule(`
    async function f() { const x = await Promise.resolve(1); return x; }
  `, {
    compilerOptions: { module: ts.ModuleKind.ESNext, target: ts.ScriptTarget.ES2020 },
  });
  check("transpile.async_await",
    r.outputText.includes("async") && r.outputText.includes("await"),
    r.outputText);
}

// 9. Generics
{
  const r = ts.transpileModule(`
    function id<T>(x: T): T { return x; }
    const a = id<number>(1);
    const b = id<string>("hi");
  `, {
    compilerOptions: { module: ts.ModuleKind.ESNext, target: ts.ScriptTarget.ES2020 },
  });
  check("transpile.generics",
    r.outputText.includes("function id") &&
      r.outputText.includes("id(1)") &&
      r.outputText.includes('id("hi")'),
    r.outputText);
}

// 10. Re-emit with sourcemap
{
  const r = ts.transpileModule(`const x = 1;`, {
    compilerOptions: {
      module: ts.ModuleKind.ESNext, target: ts.ScriptTarget.ES2020,
      sourceMap: true,
    },
  });
  check("transpile.sourcemap",
    typeof r.sourceMapText === "string" && r.sourceMapText.includes("mappings"),
    r.sourceMapText?.slice(0, 100));
}

console.log(`typescript deep: ${ok} passed, ${fail} failed`);
