# `mangle-safety` corpus

A validation corpus for `mtsc --mangle-properties`: does the
type-tracking analysis rename *only* the properties that no outside
observer can see?

`case00` … `case25` are ported from
[packelyze](https://github.com/mizchi/packelyze)'s
`packages/transformer/fixtures` (minus the duplicate `case07-missing`),
which is the prior art this analysis extends. The TypeScript sources are
kept verbatim so the two implementations can be compared case by case;
`_expected.js` snapshots are not copied — the expectations live in each
case's `case.json` instead, expressed as behaviour rather than as one
particular mangler's output.

`case26` onward are ts.mbt's own, added when the sink rule was inverted
from "enumerate the dangerous calls" to "a call escapes unless the
callee is provably internal". Three of them (`case26`, `case27`,
`case29`) were each confirmed to fail against the pre-inversion binary
before being recorded as `pass`; the other two guard the pure-builtin
allowlist from the opposite direction — that it doesn't launder a call
result's provenance (`case28`), and that it still keeps an ordinary
internal accumulator manglable (`case30`).

Run it with:

```bash
just verify-mangle-safety            # all cases
just verify-mangle-safety --case case04-internal
```

## What each case asserts

`scripts/verify_mangle_safety.mjs` observes the same public API three
times and compares:

| variant | what it is |
| --- | --- |
| `reference` | the case's original TypeScript, run through Node's type stripping — no compiler of ours involved |
| `baseline` | `mtsc --bundle` |
| `mangled` | `mtsc --bundle --mangle-properties --reserve-entry-exports` |

All three go through one child-process runner
(`scripts/lib/observe-runner.mjs`), so a difference between them is a
difference in the *module*, never in how it was watched.

`baseline` vs `mangled` catches an unsafe rename. `reference` vs
`baseline` catches the other half: a bug present in *both* our outputs —
class-method DCE deleting a public method was exactly that, the two mtsc
variants agreed with each other and were both wrong. Node's type
stripping only handles erasable syntax, so a case using a parameter
property, the `module` keyword, or a type imported in value form reports
the reference leg as unavailable rather than as a disagreement.

Then it:

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
4. **Mutation self-check.** One `expectKeep` name is deliberately
   renamed in the mangled bundle, and the run must notice. A case whose
   driver never exercises the names it claims to protect gives a hollow
   guarantee, and this is what stops the corpus from going green on
   nothing. It found two such cases on its first run.

## `case.json`

| field | meaning |
| --- | --- |
| `origin` | upstream packelyze fixture |
| `what` | what the case is about |
| `entry` | entry file (default `index.ts`) |
| `externals` | bare specifiers passed as `--external` |
| `stubs` | `{ specifier: moduleSource }` written into a local `node_modules` so the bundle can run |
| `globals` | host globals to define as empty objects before running (`window`, …) |
| `globalStubs` | `{ name: "<js expression>" }` — a host global with a real body, for when a name is only reachable through one |
| `reference` | set `false` to skip the reference leg for this case |
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

All 30 cases currently record `pass`, so any regression — a compile
that stops working, a renamed property that turns out to be
observable — fails the run.
