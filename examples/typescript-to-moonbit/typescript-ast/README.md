# TypeScript -> MoonBit TypeScript AST Pattern

This pattern uses the real `typescript/lib/typescript.d.ts` declaration file as
input and binds the generated MoonBit package to the `typescript` npm module.

```bash
moon run src -- \
  --input node_modules/typescript/lib/typescript.d.ts \
  --out _build/examples/typescript-to-moonbit-typescript-ast/dist \
  --direction ts-to-mbt \
  --module-spec typescript
```

The smoke program in `smoke/main.mbt` creates a TypeScript `SourceFile`, builds a
`TransformerFactory` in MoonBit, traverses children through the generated
`visitEachChild` bridge, renames `Identifier` nodes, then prints the transformed
file through the TypeScript printer.

The runtime adapter in `runtime/ast-transformer.js` only supplies small JS
helpers for TypeScript enum values, printer/factory conveniences, and identity
casts around TypeScript's generic visitor APIs.
