# TypeScript -> MoonBit React Pattern

This pattern starts from a React-like `export =` declaration with a nested
`JSX` namespace and `keyof JSX.IntrinsicElements` parameter.

```bash
moon run src -- \
  --input examples/typescript-to-moonbit/react/src/index.d.ts \
  --out examples/typescript-to-moonbit/react/dist \
  --direction ts-to-mbt \
  --module-spec ../runtime/react-like.js
```

The generated package exposes `createElement` and an opaque `get_default`
binding backed by `runtime/react-like.js`.
