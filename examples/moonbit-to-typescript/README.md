# MoonBit -> TypeScript Example

This example starts from a small MoonBit module. The checked-in
`pkg.generated.mbti` files are the public API summary produced by `moon info`,
and the generator uses the real MoonBit source package to build JavaScript.

```bash
moon run src -- --input examples/counter --out examples/moonbit-to-typescript/dist
```

`--direction` is omitted on purpose. The unified CLI resolves
`examples/counter` to `counter/pkg.generated.mbti`, creates a temporary glue
package inside this MoonBit module, runs `moon build --target js`, and emits a
TypeScript package backed by the built JavaScript output.

Generated files:

- `index.js`
- `index.js.map`
- `package.json`
- `AUTOLINK_DIAGNOSTICS.md`
- `index.d.ts`
- `child/index.d.ts`
