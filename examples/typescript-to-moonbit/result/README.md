# TypeScript -> MoonBit Result Pattern

This pattern starts from a small Result/ResultAsync declaration surface similar
to common functional TypeScript libraries.

```bash
moon run src -- \
  --input examples/typescript-to-moonbit/result/src/index.d.ts \
  --out examples/typescript-to-moonbit/result/dist \
  --direction ts-to-mbt \
  --module-spec ../runtime/result.js
```

The generated package exposes `parseUser` and `fetchUser` bindings backed by
`runtime/result.js`.
