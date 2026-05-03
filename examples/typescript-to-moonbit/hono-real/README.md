# TypeScript -> MoonBit Hono Runtime Pattern

This pattern uses the real `hono` declaration entrypoint as input and binds the
generated MoonBit package to the real `hono` runtime module.

```bash
moon run src/cmd/ts2mbt -- \
  --input node_modules/hono/dist/types/index.d.ts \
  --out _build/examples/typescript-to-moonbit-hono-real/dist \
  --module-spec hono
```

The smoke program in `smoke/main.mbt` constructs a real `Hono` instance through
the generated `new_hono` bridge, registers a route, dispatches a request, and
checks the runtime response metadata.

