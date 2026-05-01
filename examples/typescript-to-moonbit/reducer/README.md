# TypeScript -> MoonBit Reducer Tagged Union Pattern

This pattern starts from a TypeScript reducer API with a discriminated union
action type and verifies MoonBit can construct each tagged variant, lift it to
the union alias, and call the reducer through generated bridge code.

```bash
moon run src -- \
  --input examples/typescript-to-moonbit/reducer/src/index.d.ts \
  --out _build/examples/typescript-to-moonbit-reducer/dist \
  --direction ts-to-mbt \
  --module-spec ../runtime/reducer.js
```
