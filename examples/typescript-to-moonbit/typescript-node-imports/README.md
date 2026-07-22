# TypeScript compiler + `node:fs` from MoonBit

This is a complete MoonBit consumer package. It generates two bridge packages,
imports both from `src/main/moon.pkg`, prints a TypeScript source file with the
compiler API, then writes and reads that result through Node's `node:fs`.

## 1. Install the TypeScript inputs

```bash
pnpm install
moon install mizchi/ts/cmd/ts2mbt
```

`typescript` is a runtime dependency. `@types/node` is needed only to generate
the `node:fs` declarations.

## 2. Generate the bridges

Run these commands at this example's root (or use the same layout in your own
MoonBit module):

```bash
# Keep the runtime import as the `typescript` npm package.
ts2mbt \
  --input node_modules/typescript/lib/typescript.d.ts \
  --out src/internal/generated/typescript \
  --module-spec typescript

# Node built-ins are declared by @types/node. Keep the runtime import as node:fs.
ts2mbt \
  --input node_modules/@types/node/fs.d.ts \
  --out src/internal/generated/node_fs \
  --module-spec node:fs
```

Add both generated bridges as `file:` dependencies, so a later `pnpm install`
preserves their runtime links:

```json
{
  "dependencies": {
    "@tsmbt-bridge/typescript": "file:./src/internal/generated/typescript",
    "@tsmbt-bridge/node_fs": "file:./src/internal/generated/node_fs",
    "typescript": "^6.0.3"
  }
}
```

Then run `pnpm install` once more. Generated bridges are intentionally ignored;
regenerate them after changing the upstream package versions.

## 3. Import and run

`src/main/moon.pkg` imports the generated packages with ordinary MoonBit
aliases:

```moonbit
import {
  "examples/typescript_node_imports/internal/generated/node_fs" @fs,
  "examples/typescript_node_imports/internal/generated/typescript" @ts,
}
```

The `main.mbt` program calls `@ts.createSourceFile` and
`@ts.createPrinter(...).printFile`, then uses `@fs.writeFileSync` and
`@fs.readFileSync`. Run it with:

```bash
moon run src/main --target js
```

It prints `ok` after the TypeScript → file → MoonBit round trip succeeds.
