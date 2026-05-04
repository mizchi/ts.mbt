---
name: ts-bridge-generator
description: Use when modifying the TypeScript-to-MoonBit bridge generator in this repo — `src/bridge/`, the `ts2mbt` CLI (vendor / sync / scaffold / package / bridge / ffi / decl), `bridge.mbti` / `bridge.mbt` / `bridge.js` synthesis, or the companion vite-plugin-moonbit integration.
---

# TS Bridge Generator

Use this skill when changing how `.ts` / `.tsx` / `.d.ts` entrypoints
become MoonBit bridge packages, or when extending the consumer-facing
`ts2mbt` CLI.

## Start here

Read these files first:

- `src/bridge/moonbit_bridge.mbt` — package-level bundle (`bridge.mbti`,
  `bridge.mbt`, `bridge.js`, `moon.pkg.json` composition)
- `src/bridge/moonbit_js_ffi.mbt` — extern signature emission, struct
  converters, tagged-union lowering, opaque-type pubicness
- `src/bridge/moonbit_decl.mbt` — declaration emission + checker-driven
  diagnostics injection
- `src/bridge/tagged_union_lowering.mbt` — `_to_js` / `_from_js` IIFE
  shapes and the inline pass-through fallback
- `src/main.mbt` — CLI emit_* entry helpers (return `Bool`, route exit
  through cmd dispatchers)
- `src/vendor.mbt` — `ts2mbt vendor` / `ts2mbt sync` workflow
- `src/cmd/ts2mbt/main.mbt` — dispatcher + per-subcommand flag parsing
- `src/main_wbtest.mbt` — end-to-end fixture coverage

If the local companion plugin repo exists, also read:

- `/tmp/vite-plugin-moonbit-worktree/src/index.ts`
- `/tmp/vite-plugin-moonbit-worktree/test/ts-bridge-tree-shake.test.mjs`
- `/tmp/vite-plugin-moonbit-worktree/examples/ts_bridge_project/README.md`

## Current contract

CLI surface (TypeScript -> MoonBit only; `mbt2ts` is the reverse
direction and lives in `src/cmd/mbt2ts/main.mbt`):

- `ts2mbt --input <ts-entry> --out <dir> [--module-spec <spec>]
  [--diagnostics <path>] [--strict]` — high-level unified flow
- `ts2mbt vendor <pkg> [--module-spec <spec>] [--out <dir>]` —
  resolve a single npm package via `node_modules` and emit a sub-package
  under `<moon source>/internal/generated/<safe>/`
- `ts2mbt sync [--package-json <path>] [--out <dir>]` — vendor every
  dependency / devDependency listed in `package.json`
- `ts2mbt scaffold <ts-entry> <module-spec> <out-dir>` — low-level
  package writer (always emits `SCAFFOLD_DIAGNOSTICS.md`)
- `ts2mbt package <ts-entry> <module-spec> <out-dir>` — package
  writer without the diagnostics file
- `ts2mbt bridge / ffi / decl` — individual generation stages

Generated package layout:

- `moon.pkg.json` (defaults to `{}`)
- `bridge.mbti`
- `bridge.mbt` (split into `types.mbt` / `converters.mbt` /
  `externs.mbt` / `guards.mbt` for large packages)
- `bridge.js`
- `SCAFFOLD_DIAGNOSTICS.md`

Vendor naming:

- Directory slug strips leading `@`, replaces `/` with `__`, and maps
  remaining non-`[A-Za-z0-9]` characters to `_`. So `@types/react` ->
  `types__react`, `@scope/foo-bar` -> `scope__foo_bar`.
- `@types/<name>` packages default the runtime module spec to the
  unscoped name (`react`, `express`, ...) since the runtime ships in
  the non-types package.

## Constraints to preserve

- `#module(...)` only accepts absolute paths — relative is rejected by
  MoonBit's JS extern. The bridge bakes the absolute scaffold path; this
  is documented in `src/main.mbt` near `rewrite_bridge_package_module_path`.
  Don't try to relativise without changing the upstream extern model.
- Self-contained `pub type JSValue` and `pub type Promise[X]` are
  injected into the bridge package (no `mizchi/js` dep).
- Opaque external types are emitted as `#external\npub type X` so the
  matching `declare pub type X` in `.mbti` actually resolves.
- Tagged-union `_to_js` IIFEs are inlined into consumer extern lambdas
  (the bridge.js function isn't auto-imported into inline JS bodies).
  Keep the leading "if not a tagged value, pass through" guard so
  `unsafeCast`-style call sites work.
- Every `emit_*` entry returns `Bool`; cmd dispatchers route failures
  through `@ts.cli_fail("ts2mbt")` so CI sees a non-zero exit.
- Tree-shake behaviour matters. If adapter exports change, update the
  companion plugin binding parser and tree-shake test.

## Validation

In this repo:

```bash
moon check --deny-warn
moon test --target native
just verify-mbti-dts
just verify-scaffolds
just verify-generated-fixtures
just verify-realworld-typescript        # optional, requires npm corpus
```

Smoke the vendor flow when changing `src/vendor.mbt`:

```bash
moon run src/cmd/ts2mbt -- sync --out /tmp/vendor_smoke
```

In the companion plugin repo when present:

```bash
pnpm exec tsc --noEmit
pnpm test
```
