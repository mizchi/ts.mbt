# TypeScript -> MoonBit @types/react Pattern

This pattern uses the real `@types/react` declaration entrypoint as input and
binds the generated MoonBit package to a `react` runtime module.

```bash
moon run src -- \
  --input node_modules/@types/react/index.d.ts \
  --out _build/examples/typescript-to-moonbit-react-types/dist \
  --direction ts-to-mbt \
  --module-spec react
```

The smoke program in `smoke/main.mbt` exercises generated bindings for
`createElement`, `cloneElement`, `isValidElement`, `memo`, `useState`,
`useTransition`, `startTransition`, and the default export getter.
