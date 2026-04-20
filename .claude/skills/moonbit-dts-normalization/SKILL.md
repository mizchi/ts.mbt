---
name: moonbit-dts-normalization
description: Use when modifying normalize-moonbit-dts, src/analysis/typescript_decl.mbt, or the experimental normalizedDts integration in vite-plugin-moonbit.
---

# MoonBit DTS Normalization

Use this skill when changing how MoonBit-generated `.d.ts` files are rewritten into clearer TypeScript declarations.

## Scope

This is intentionally narrow.

- It targets MoonBit-generated `.d.ts`.
- It mainly rewrites the `import type * as MoonBit from "./moonbit.d.ts"` alias layer.
- It is a readability pass, not a general-purpose `.d.ts` pretty-printer.

## Start here

Read these files first:

- `src/analysis/typescript_decl.mbt`
- `src/analysis/typescript_decl_wbtest.mbt`
- `src/main.mbt`
- `src/main_wbtest.mbt`

If the companion plugin repo exists, also read:

- `/tmp/vite-plugin-moonbit-worktree/src/index.ts`
- `/tmp/vite-plugin-moonbit-worktree/test/normalized-dts.test.mjs`
- `/tmp/vite-plugin-moonbit-worktree/README.md`

## UX rules

- `normalizedDts` is experimental. Keep that explicit in docs and logs.
- If the plugin skips normalization, it should say why.
- If the plugin reuses `tsBridge.generatorRoot`, that should stay visible to the user.
- Document the manual fallback command for workflows that call `moon build` directly.

## Validation

In this repo:

```bash
moon test --target native src/analysis/typescript_decl_wbtest.mbt
moon test --target native src/main_wbtest.mbt
moon check --target native
moon fmt
```

In the companion plugin repo when present:

```bash
pnpm exec tsc --noEmit
pnpm test
```

