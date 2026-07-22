# TypeScript -> MoonBit Example

This example starts from a TypeScript declaration entrypoint and a small
runtime JavaScript module.

```bash
ts2mbt \
  --input examples/typescript-to-moonbit/src/index.d.ts \
  --out examples/typescript-to-moonbit/dist \
  --module-spec ../runtime/greetings.js
```

The generated MoonBit package binds the exported TypeScript surface in
`src/index.d.ts` to the JavaScript runtime module.

Generated files:

- `moon.pkg.json`
- `bridge.mbti`
- `bridge.mbt`
- `bridge.js`

Additional TypeScript -> MoonBit patterns are available under:

- `hono/`
- `hono-real/`
- `react/`
- `react-types/`
- `vitest/`
- `result/`
- `default-class/`
- `const-table/`
- `node-sqlite/`
- `node-fs/`
- `typescript-ast/`
- `typescript-node-imports/` (a complete consumer that imports both bridges)
