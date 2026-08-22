# `mangle-safety` corpus

A validation corpus for `mtsc --mangle-properties`: does the
type-tracking analysis rename *only* the properties that no outside
observer can see?

The cases are ported from
[packelyze](https://github.com/mizchi/packelyze)'s
`packages/transformer/fixtures` (`case00` … `case25`, minus the
duplicate `case07-missing`), which is the prior art this analysis
extends. The TypeScript sources are kept verbatim so the two
implementations can be compared case by case; `_expected.js` snapshots
are not copied — the expectations live in each case's `case.json`
instead, expressed as behaviour rather than as one particular
mangler's output.

Run it with:

```bash
just verify-mangle-safety            # all cases
just verify-mangle-safety --case case04-internal
```

## What each case asserts

`scripts/verify_mangle_safety.mjs` compiles every entry twice — once
with plain `--bundle`, once with
`--bundle --mangle-properties --reserve-entry-exports` — and then:

1. **Export surface.** Every name in `case.json`'s `exports` must be
   exported by both bundles. A dropped `export … from` is a failure
   even when both variants drop it.
2. **Observable behaviour.** Both bundles are imported under Node with
   `fetch` and `console.*` recorded, driven through the case's optional
   `driver.mjs`, and the observations are diffed. Renaming a property
   that an outside observer can reach shows up here as a concrete
   difference — a changed request body, a changed returned object, a
   `ReferenceError`.
3. **Name expectations.** `expectKeep` names must still appear in the
   mangled output (a hard failure when they don't — that is an ABI
   break). `expectMangle` names are the compression opportunities
   packelyze took; keeping one is reported as a missed opportunity,
   not a failure, because staying conservative is always sound.

## `case.json`

| field | meaning |
| --- | --- |
| `origin` | upstream packelyze fixture |
| `what` | what the case is about |
| `entry` | entry file (default `index.ts`) |
| `externals` | bare specifiers passed as `--external` |
| `stubs` | `{ specifier: moduleSource }` written into a local `node_modules` so the bundle can run |
| `globals` | host globals to define before running (`window`, …) |
| `fakeTimers` | run `setTimeout` callbacks on the microtask queue |
| `run` | set `false` to skip execution |
| `exports` | names the entry is expected to export |
| `expectKeep` | property names that must survive |
| `expectMangle` | property names that are provably private |
| `expectStatus` | recorded outcome: `pass`, `fail`, `blocked-compile`, `blocked-mangle` |

`expectStatus` is what keeps this CI-able while gaps remain: the
harness fails only when a case does *worse* than its recorded status.
When a fix makes a case do better, the harness says so and
`node scripts/verify_mangle_safety.mjs --update` re-records it.

All 25 cases currently record `pass`, so any regression — a compile
that stops working, a renamed property that turns out to be
observable — fails the run.
