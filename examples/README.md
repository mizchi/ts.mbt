# Bridge Scaffold Examples

These examples show the two high-level bridge generation paths.

## MoonBit -> TypeScript

Input:

- `moonbit-to-typescript/counter/counter.mbt`
- `moonbit-to-typescript/counter/child/item.mbt`
- generated interface snapshots under `moonbit-to-typescript/counter/**/pkg.generated.mbti`

Generate a TypeScript package backed by `moon build --target js`:

```bash
moon run src/cmd/mbt2ts -- --input examples/counter --out examples/moonbit-to-typescript/dist
```

The generated output includes `index.js`, `index.d.ts`, `child/index.js`,
`child/index.d.ts`, `package.json`, and autolink diagnostics. The MoonBit glue
package is temporary and is removed after `moon build --target js` succeeds.

## TypeScript -> MoonBit

Input:

- `typescript-to-moonbit/src/index.d.ts`
- `typescript-to-moonbit/runtime/greetings.js`
- `typescript-to-moonbit/hono/src/index.d.ts`
- `typescript-to-moonbit/hono/runtime/hono.js`
- `node_modules/hono/dist/types/index.d.ts`
- `typescript-to-moonbit/hono-real/smoke/main.mbt`
- `typescript-to-moonbit/react/src/index.d.ts`
- `typescript-to-moonbit/react/runtime/react-like.js`
- `node_modules/@types/react/index.d.ts`
- `typescript-to-moonbit/react-types/smoke/main.mbt`
- `node_modules/vitest/dist/index.d.ts`
- `typescript-to-moonbit/vitest/smoke/main.mbt`
- `typescript-to-moonbit/result/src/index.d.ts`
- `typescript-to-moonbit/result/runtime/result.js`
- `typescript-to-moonbit/default-class/src/index.ts`
- `typescript-to-moonbit/default-class/runtime/counter.js`
- `typescript-to-moonbit/const-table/src/index.ts`
- `typescript-to-moonbit/const-table/runtime/index.js`
- `typescript-to-moonbit/node-sqlite/smoke/main.mbt`
- `typescript-to-moonbit/node-fs/smoke/main.mbt`
- `typescript-to-moonbit/typescript-ast/smoke/main.mbt`

Generate a MoonBit bridge package:

```bash
moon run src/cmd/ts2mbt -- \
  --input examples/typescript-to-moonbit/src/index.d.ts \
  --out examples/typescript-to-moonbit/dist \
  --module-spec ../runtime/greetings.js
```

The generated output includes `bridge.mbti`, `bridge.mbt`, `bridge.js`, and
`moon.pkg.json`.

Additional patterns:

```bash
moon run src/cmd/ts2mbt -- \
  --input examples/typescript-to-moonbit/hono/src/index.d.ts \
  --out examples/typescript-to-moonbit/hono/dist \
  --module-spec ../runtime/hono.js

moon run src/cmd/ts2mbt -- \
  --input node_modules/hono/dist/types/index.d.ts \
  --out _build/examples/typescript-to-moonbit-hono-real/dist \
  --module-spec hono

moon run src/cmd/ts2mbt -- \
  --input examples/typescript-to-moonbit/react/src/index.d.ts \
  --out examples/typescript-to-moonbit/react/dist \
  --module-spec ../runtime/react-like.js

moon run src/cmd/ts2mbt -- \
  --input node_modules/@types/react/index.d.ts \
  --out _build/examples/typescript-to-moonbit-react-types/dist \
  --module-spec react

moon run src/cmd/ts2mbt -- \
  --input node_modules/vitest/dist/index.d.ts \
  --out _build/examples/typescript-to-moonbit-vitest/dist \
  --module-spec vitest

moon run src/cmd/ts2mbt -- \
  --input examples/typescript-to-moonbit/result/src/index.d.ts \
  --out examples/typescript-to-moonbit/result/dist \
  --module-spec ../runtime/result.js

moon run src/cmd/ts2mbt -- \
  --input examples/typescript-to-moonbit/default-class/src/index.ts \
  --out examples/typescript-to-moonbit/default-class/dist \
  --module-spec ../runtime/counter.js

moon run src/cmd/ts2mbt -- \
  --input examples/typescript-to-moonbit/const-table/src/index.ts \
  --out examples/typescript-to-moonbit/const-table/dist \
  --module-spec ../runtime/index.js

moon run src/cmd/ts2mbt -- \
  --input "$TSMBT_NODE_SQLITE_TYPES" \
  --out _build/examples/node-sqlite/dist \
  --module-spec node:sqlite

moon run src/cmd/ts2mbt -- \
  --input "$TSMBT_NODE_FS_TYPES" \
  --out _build/examples/node-fs/dist \
  --module-spec node:fs

moon run src/cmd/ts2mbt -- \
  --input node_modules/typescript/lib/typescript.d.ts \
  --out _build/examples/typescript-to-moonbit-typescript-ast/dist \
  --module-spec typescript
```

Run `just verify-examples` from the repository root to verify these examples
without writing generated files into `examples/**/dist`.
