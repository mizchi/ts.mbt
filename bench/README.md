# Bench

Benchmarks for the `mtsc` bundle + mangle pipeline against external
bundlers (currently `rolldown`).

## Running

```bash
# Build the release binary first.
moon build --target native --release

# 200-module corpus, 2 warmup runs, 10 measured runs (defaults).
bench/bundle_vs_rolldown.sh

# Custom knobs:
bench/bundle_vs_rolldown.sh 500 3 20
```

The script:

1. Generates a synthetic TypeScript corpus under `_build/bench/corpus/`.
   `bench/gen_corpus.mjs` emits N modules where each `mod-i.ts` exports
   four helpers (`pair`, `dispatch`, `helper`, `describe`) and the
   entrypoint chains every module's functions so a tree-shaking
   bundler can't drop anything.
2. Runs each tool once and verifies every output evaluates to the
   same stdout under Node (correctness smoke).
3. Runs `hyperfine` over six configurations:
   - `mtsc --bundle`
   - `mtsc --bundle --treeshake`
   - `mtsc --bundle --mangle`
   - `mtsc --bundle --treeshake --mangle`
   - `rolldown`
   - `rolldown --minify`

Reports land at `_build/bench/report.md` (timings) and
`_build/bench/sizes.md` (output bytes).

## Notes

- The corpus is synthetic on purpose. It exercises bundler
  performance under a wide-fan dependency graph without dragging in
  real npm dependencies, which keeps the workload reproducible and
  trims the warm-up window for `npm`/`node_modules` I/O.
- `rolldown` is invoked through `node_modules/.bin/rolldown`
  directly to avoid the `npx` shim's ~250 ms startup tax.
- `mtsc --bundle --treeshake` drops top-level declarations that
  aren't reachable from any side-effect statement. It only drops
  declarations whose initializer is statically pure (literals,
  function / arrow expressions, pure object / array literals).
  Anything else stays as a side-effect root.
