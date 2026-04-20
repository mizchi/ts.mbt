---
name: ts-bridge-generator
description: Use when modifying the TypeScript-to-MoonBit bridge generator in this repo, including emit-moonbit-bridge-package, moonbit_js_ffi, bridge.mbt/bridge.js generation, or the companion vite-plugin-moonbit integration.
---

# TS Bridge Generator

Use this skill when changing how `.ts/.tsx/.d.ts` entrypoints become MoonBit bridge packages.

## Start here

Read these files first:

- `src/analysis/moonbit_bridge.mbt`
- `src/analysis/moonbit_js_ffi.mbt`
- `src/main.mbt`
- `src/main_wbtest.mbt`

If the local companion plugin repo exists, also read:

- `/tmp/vite-plugin-moonbit-worktree/src/index.ts`
- `/tmp/vite-plugin-moonbit-worktree/test/ts-bridge-tree-shake.test.mjs`
- `/tmp/vite-plugin-moonbit-worktree/examples/ts_bridge_project/README.md`

## Current contract

- `emit-moonbit-bridge-package` is the public package-level entrypoint.
- Generated package layout is:
  - `moon.pkg.json`
  - `bridge.mbti`
  - `bridge.mbt`
  - `bridge.js`
- Prefer direct MoonBit `#module("...")` imports when possible.
- Keep `bridge.js` as a flat ESM adapter, not a global binding shim.

## Constraints to preserve

- Non-relative `moduleSpec` is preferred. Relative specs force more wrapper code.
- Static members, value exports, and namespace-like exports may still require adapter wrappers.
- Do not reintroduce `globalThis.__ts_mbt_*`.
- Tree-shake behavior matters. If adapter exports change, update the companion plugin binding parser and tree-shake test.

## Validation

In this repo:

```bash
moon test --target native src/analysis/moonbit_js_ffi_wbtest.mbt
moon test --target native src/analysis/moonbit_bridge_wbtest.mbt
moon test --target native src/main_wbtest.mbt
moon check --target native
moon fmt
```

In the companion plugin repo when present:

```bash
pnpm exec tsc --noEmit
pnpm test
```

