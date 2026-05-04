# MoonBit -> TypeScript Example

This example starts from a small MoonBit module. The checked-in
`pkg.generated.mbti` files are the public API summary produced by `moon info`,
and the generator uses the real MoonBit source package to build JavaScript.

```bash
moon run src/cmd/mbt2ts -- --input examples/moonbit-to-typescript/counter --out examples/moonbit-to-typescript/dist
```

`mbt2ts` is the MoonBit -> TypeScript binary. The unified `--input/--out`
flow resolves `examples/moonbit-to-typescript/counter` to
`counter/pkg.generated.mbti`, creates a temporary glue package inside this
MoonBit module, runs `moon build --target js`, and emits a TypeScript
package backed by the built JavaScript output.

Generated files:

- `index.js`
- `index.js.map`
- `package.json`
- `AUTOLINK_DIAGNOSTICS.md`
- `index.d.ts`
- `child/index.d.ts`
