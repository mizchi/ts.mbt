# TypeScript -> MoonBit Vitest Runtime Pattern

This pattern uses the real `vitest` declaration entrypoint as input and binds
the generated MoonBit package to the real `vitest` runtime module.

```bash
moon run src -- \
  --input node_modules/vitest/dist/index.d.ts \
  --out _build/examples/typescript-to-moonbit-vitest/dist \
  --direction ts-to-mbt \
  --module-spec vitest
```

The smoke program in `smoke/main.mbt` reaches the real `expect`, `assert`, and
`vi` exports through generated getters, then exercises assertion and mock
function behavior at runtime. Some `vi` APIs require the Vitest worker state, so
the smoke uses the APIs that are valid from a plain Node process.

