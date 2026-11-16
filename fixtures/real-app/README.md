# real-app

An application that imports real npm packages, checked with
`mtsc -p … --noEmit` the way a user's CI would check it. Run it with
`just verify-real-app` (`scripts/verify_real_app.mjs`).

The packages are this repo's own `devDependencies`, so the two projects
resolve them through the repo-root `node_modules`:

zod · effect · hono · preact · react (two cases) · express · date-fns ·
drizzle-orm · yjs · vitest

| Directory | Contents | tsc | mtsc |
| --- | --- | --- | --- |
| `bad/` | one deliberate error per file, in a package's main API | exactly one error per file | must report it, or the file is declared in `mtsc-misses.txt` |
| `ok/` | ordinary legal use of the same packages | nothing | nothing — any report is a false positive and fails |

## Why it exists

Every other checker gate is a single-file conformance case, a hand-written
`tsc-extra` case, or a package's OWN sources reached through relative
imports. None of them imports a package the way an application does, so
none of them could see that `mtsc --noEmit` read no package types at all:
every npm import was `any`, tsc reported all eleven planted errors here,
mtsc reported none of them, and the run exited 0.

## The three checks

1. **Baseline.** tsc (`node_modules/typescript`) reports exactly one error
   in every `bad/` file and nothing in `ok/`. A failure here is a finding
   about TypeScript or an upgraded package, not about mtsc. It is also what
   keeps `ok/` honest: the first draft of `ok/src/preact.tsx` was not legal
   (under `jsx: react-jsx` its children were checked against React's types),
   and it needs its `@jsxImportSource preact` pragma.
2. **False positives.** mtsc reports nothing in `ok/`, and nothing in a
   `bad/` file other than the planted error.
3. **Misses.** mtsc reports in every `bad/` file, or the file is declared in
   `mtsc-misses.txt` with the capability it needs. A declared miss that mtsc
   starts reporting fails as STALE, so the list can only shrink.

## Adding a case

Add a `bad/src/<pkg>.ts` with exactly one planted error, and legal use of
the same API to `ok/src/`. Run `just verify-real-app`. If mtsc misses the
planted error, probe the cause in a single-file reproduction before
declaring it, and write the shape that defeats the check as the reason.
