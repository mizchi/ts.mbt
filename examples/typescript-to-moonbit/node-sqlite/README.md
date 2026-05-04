# TypeScript -> MoonBit Node SQLite Pattern

This pattern uses the real `@types/node/sqlite.d.ts` ambient module declaration
as the TypeScript input and binds it to the Node built-in `node:sqlite` module.

```bash
ts2mbt \
  --input "$TSMBT_NODE_SQLITE_TYPES" \
  --out _build/examples/node-sqlite/dist \
  --module-spec node:sqlite
```

If `TSMBT_NODE_SQLITE_TYPES` is not set, `scripts/verify_realworld_typescript.sh`
looks for `@types/node/sqlite.d.ts` under its configured node_modules root.

The smoke program in `smoke/main.mbt` opens an in-memory database, executes SQL,
reads a row through `DatabaseSync::prepare()` and `StatementSync::get()`, then
closes the database. Node 24 currently requires `--experimental-sqlite` when
running the generated JavaScript.
