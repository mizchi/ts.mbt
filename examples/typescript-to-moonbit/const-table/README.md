# TypeScript -> MoonBit Const Table Pattern

This pattern starts from a runtime TypeScript module that destructures exported
values using keys imported from a const table.

```bash
moon run src -- \
  --input examples/typescript-to-moonbit/const-table/src/index.ts \
  --out examples/typescript-to-moonbit/const-table/dist \
  --direction ts-to-mbt \
  --module-spec ../runtime/index.js
```

The generated package exposes getters for the statically resolved destructured
exports backed by `runtime/index.js`.
