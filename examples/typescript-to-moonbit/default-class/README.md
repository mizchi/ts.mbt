# TypeScript -> MoonBit Default Class Pattern

This pattern starts from a default-exported TypeScript class with a constructor,
field, instance method, and static factory method.

```bash
moon run src -- \
  --input examples/typescript-to-moonbit/default-class/src/index.ts \
  --out examples/typescript-to-moonbit/default-class/dist \
  --direction ts-to-mbt \
  --module-spec ../runtime/counter.js
```

The generated package exposes constructor, field accessors, instance method,
and static method bindings backed by `runtime/counter.js`.
