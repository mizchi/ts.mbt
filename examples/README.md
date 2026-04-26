# Bridge Scaffold Examples

These examples show the two high-level bridge generation paths.

## MoonBit -> TypeScript

Input:

- `moonbit-to-typescript/counter/counter.mbt`
- `moonbit-to-typescript/counter/child/item.mbt`
- generated interface snapshots under `moonbit-to-typescript/counter/**/pkg.generated.mbti`

Generate a TypeScript package backed by `moon build --target js`:

```bash
moon run src -- --input examples/counter --out examples/moonbit-to-typescript/dist
```

The generated output includes `index.js`, `index.d.ts`, `child/index.d.ts`,
`package.json`, and autolink diagnostics. The MoonBit glue package is temporary
and is removed after `moon build --target js` succeeds.

## TypeScript -> MoonBit

Input:

- `typescript-to-moonbit/src/index.d.ts`
- `typescript-to-moonbit/runtime/greetings.js`

Generate a MoonBit bridge package:

```bash
moon run src -- \
  --input examples/typescript-to-moonbit/src/index.d.ts \
  --out examples/typescript-to-moonbit/dist \
  --direction ts-to-mbt \
  --module-spec ../runtime/greetings.js
```

The generated output includes `bridge.mbti`, `bridge.mbt`, `bridge.js`, and
`moon.pkg.json`.

Run `just verify-examples` from the repository root to verify both examples
without writing generated files into `examples/**/dist`.
