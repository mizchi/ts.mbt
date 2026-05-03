# TypeScript -> MoonBit @types/react Pattern

This pattern uses the real `@types/react` declaration entrypoint as input and
binds the generated MoonBit package to the real `react` runtime module.

```bash
moon run src/cmd/ts2mbt -- \
  --input node_modules/@types/react/index.d.ts \
  --out _build/examples/typescript-to-moonbit-react-types/dist \
  --module-spec react
```

The smoke program in `smoke/main.mbt` exercises generated bindings for
`createElement`, `cloneElement`, `isValidElement`, `memo`, `forwardRef`,
`startTransition`, and the default export getter. Hooks such as `useState` are
generated, but this smoke does not call them directly because React requires a
renderer dispatcher for hook execution.
