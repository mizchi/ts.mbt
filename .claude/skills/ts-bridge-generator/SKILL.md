---
name: ts-bridge-generator
description: Use when modifying the TypeScript-to-MoonBit bridge generator in this repo — `src/bridge/`, the `mtsc bridge` CLI namespace (generate / vendor / scaffold / package / all / ffi / decl, formerly the `ts2mbt` binary), `bridge.mbti` / `bridge.mbt` / `bridge.js` synthesis, or the companion vite-plugin-moonbit integration.
---

# TS Bridge Generator

Use this skill when changing how `.ts` / `.tsx` / `.d.ts` entrypoints
become MoonBit bridge packages, or when extending the consumer-facing
`mtsc bridge` CLI namespace.

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
- `src/vendor.mbt` — `mtsc bridge generate` / `mtsc bridge vendor` workflow
- `src/bridge_cli.mbt` — dispatcher + per-verb flag parsing for both
  `mtsc bridge` and `mtsc pkg`
- `src/cmd/mtsc/driver.mbt` — the verb dispatch that reaches it
- `src/main_wbtest.mbt` — end-to-end fixture coverage

If the local companion plugin repo exists, also read:

- `/tmp/vite-plugin-moonbit-worktree/src/index.ts`
- `/tmp/vite-plugin-moonbit-worktree/test/ts-bridge-tree-shake.test.mjs`
- `/tmp/vite-plugin-moonbit-worktree/examples/ts_bridge_project/README.md`

## Current contract

CLI surface (TypeScript -> MoonBit only; `mtsc pkg` is the reverse
direction and shares `src/bridge_cli.mbt`):

- `mtsc bridge --input <ts-entry> --out <dir> [--module-spec <spec>]
  [--diagnostics <path>] [--strict]` — high-level unified flow
- `mtsc bridge vendor <pkg> [--module-spec <spec>] [--out <dir>]` —
  resolve a single npm package via `node_modules` and emit a sub-package
  under `<moon source>/internal/generated/<safe>/`
- `mtsc bridge generate [--package-json <path>] [--out <dir>]` — generate every
  dependency / devDependency listed in `package.json`
- `mtsc bridge scaffold <ts-entry> <module-spec> <out-dir>` — low-level
  package writer (always emits `SCAFFOLD_DIAGNOSTICS.md`)
- `mtsc bridge package <ts-entry> <module-spec> <out-dir>` — package
  writer without the diagnostics file
- `mtsc bridge all / ffi / decl` — individual generation stages. `all`
  was spelled `bridge` when this was its own binary, which under the
  namespace read as `mtsc bridge bridge`; the old spelling is still an
  accepted alias.

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
  through `cli_fail("mtsc")` so CI sees a non-zero exit.
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
moon run src/cmd/mtsc -- bridge generate --out /tmp/vendor_smoke
```

In the companion plugin repo when present:

```bash
pnpm exec tsc --noEmit
pnpm test
```
