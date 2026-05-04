# TypeScript -> MoonBit TypeScript AST Pattern

This pattern uses the real `typescript/lib/typescript.d.ts` declaration file as
input and binds the generated MoonBit package to the `typescript` npm module.

```bash
ts2mbt \
  --input node_modules/typescript/lib/typescript.d.ts \
  --out _build/examples/typescript-to-moonbit-typescript-ast/dist \
  --module-spec typescript
```

The smoke program in `smoke/main.mbt` creates a TypeScript `SourceFile`, builds a
`TransformerFactory` in MoonBit, traverses children through the generated
`visitEachChild` bridge, narrows nodes with the generated `Node::asIdentifier`
helper, renames `Identifier` nodes, then prints the transformed file through the
TypeScript printer.

The smoke uses the generated bridge directly. Structural casts, Node type-guard
helpers, and function-field method wrappers for TypeScript objects are generated
into the MoonBit bridge package.
