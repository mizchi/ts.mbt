# TypeScript -> MoonBit Result Pattern

This pattern starts from a small Result/ResultAsync declaration surface similar
to common functional TypeScript libraries.

```bash
moon run src/cmd/ts2mbt -- \
  --input examples/typescript-to-moonbit/result/src/index.d.ts \
  --out examples/typescript-to-moonbit/result/dist \
  --module-spec ../runtime/result.js
```

The generated package exposes `parseUser` and `fetchUser` bindings backed by
`runtime/result.js`.
