# TypeScript -> MoonBit Node FS Pattern

This pattern uses the real `@types/node/fs.d.ts` ambient module declaration as
the TypeScript input and binds it to the Node built-in `node:fs` module.

```bash
moon run src/cmd/ts2mbt -- \
  --input "$TSMBT_NODE_FS_TYPES" \
  --out _build/examples/node-fs/dist \
  --module-spec node:fs
```

If `TSMBT_NODE_FS_TYPES` is not set, `scripts/verify_realworld_typescript.sh`
looks for `@types/node/fs.d.ts` under its configured node_modules root.

The smoke program in `smoke/main.mbt` writes a text file through
`writeFileSync`, reads it back through `readFileSync`, then removes it with
`unlinkSync`.
