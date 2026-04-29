# TypeScript -> MoonBit Example

This example starts from a TypeScript declaration entrypoint and a small
runtime JavaScript module.

```bash
moon run src -- \
  --input examples/typescript-to-moonbit/src/index.d.ts \
  --out examples/typescript-to-moonbit/dist \
  --direction ts-to-mbt \
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
- `react/`
- `result/`
- `default-class/`
- `const-table/`
- `node-sqlite/`
- `node-fs/`
