# TypeScript -> MoonBit Hono Pattern

This pattern starts from a small Hono-like declaration surface with a class,
generic options object, optional fields, and a constructor.

```bash
moon run src -- \
  --input examples/typescript-to-moonbit/hono/src/index.d.ts \
  --out examples/typescript-to-moonbit/hono/dist \
  --direction ts-to-mbt \
  --module-spec ../runtime/hono.js
```

The generated package exposes `new_hono` and `createApp` bindings backed by
`runtime/hono.js`.
