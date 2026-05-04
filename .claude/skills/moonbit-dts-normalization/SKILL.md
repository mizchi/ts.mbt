---
name: moonbit-dts-normalization
description: Use when modifying `mbt2ts normalize` (the MoonBit-generated `.d.ts` rewriter), `src/bridge/typescript_decl.mbt`, or the experimental normalizedDts integration in vite-plugin-moonbit.
---

# MoonBit DTS Normalization

Use this skill when changing how MoonBit-generated `.d.ts` files are
rewritten into clearer TypeScript declarations.

## Scope

This is intentionally narrow.

- It targets MoonBit-generated `.d.ts`.
- It mainly rewrites the `import type * as MoonBit from "./moonbit.d.ts"`
  alias layer.
- It is a readability pass, not a general-purpose `.d.ts`
  pretty-printer.
- Public CLI surface: `mbt2ts normalize <ts> [out]`. The library entry
  is `pub async fn emit_typescript_decl` in `src/main.mbt`.

## Start here

Read these files first:

- `src/bridge/typescript_decl.mbt` — the normalization rewriter
- `src/bridge/typescript_decl_wbtest.mbt` — fixture-based tests
- `src/main.mbt` — the `emit_typescript_decl` library entry
- `src/main_wbtest.mbt` — end-to-end "MoonBit-generated d.ts in,
  normalized d.ts out" tests
- `src/cmd/mbt2ts/main.mbt` — dispatcher arm for `normalize`

If the companion plugin repo exists, also read:

- `/tmp/vite-plugin-moonbit-worktree/src/index.ts`
- `/tmp/vite-plugin-moonbit-worktree/test/normalized-dts.test.mjs`
- `/tmp/vite-plugin-moonbit-worktree/README.md`

## UX rules

- `normalizedDts` is experimental. Keep that explicit in docs and logs.
- If the plugin skips normalization, it should say why.
- If the plugin reuses `tsBridge.generatorRoot`, that should stay
  visible to the user.
- Document the manual fallback command for workflows that call
  `moon build` directly.
- The CLI invocation is `moon run src/cmd/mbt2ts -- normalize <ts>` —
  not the old `normalize-moonbit-dts` verb.

## Validation

In this repo:

```bash
moon check --deny-warn
moon test --target native
moon test --target native -p mizchi/ts/bridge --filter typescript_decl
moon fmt
```

In the companion plugin repo when present:

```bash
pnpm exec tsc --noEmit
pnpm test
```
