# type-aware measurement corpus

Drivers and the recorded baseline for `just measure-type-aware`. The
harness is `scripts/measure_type_aware.mjs`; the reasoning and the
current numbers are in
[`docs/type-aware-measurement.md`](../../docs/type-aware-measurement.md).

The packages themselves are not checked in — each target is cloned from
git on the first run, into `_build/type-aware/` (or adopted from
`_build/real-world/` when `verify-real-world` already cloned it).

## `*.driver.mjs`

One per behaviour-checked target. A driver imports `./target.mjs` and
prints a deterministic JSON observation; the harness copies each leg's
bundle to `target.mjs` in turn and requires all of them to print the
same thing. Without that, a size number is just a number — a smaller
bundle that behaves differently is not a win.

A driver should exercise the surfaces a property mangler would most like
to rename: object literals whose keys cross the API boundary, error and
issue shapes, anything read back by name. `valibot.driver.mjs` checks the
issue `kind` / `type` / `path` surface for exactly that reason.

A driver must print only values that are a FUNCTION OF ITS INPUT.
`excalidraw.driver.mjs` pins every element's `seed` for that reason: the
seed is drawn from a PRNG seeded with `Date.now()` and roughjs feeds it
into the path generator, so even a line's computed bounds move from run
to run — and a value that changes per run cannot witness a mangling bug,
it can only produce a false BROKEN.

Assert class identity with `instanceof`, never `constructor.name`.
`--mangle` renames a class whose name the bundle itself never reads back
(the same default terser and esbuild ship, narrowed here by
`observed_names.mbt`), so a `.name` assertion pins that limitation rather
than testing behaviour.

To add a target: append an entry to `CORPUS` in the harness, write
`<name>.driver.mjs`, then `just measure-type-aware --update`.

## Per-target fields for awkward targets

Four fields exist for targets that are not a single self-contained
package. `excalidraw` uses all of them; see the harness comments for why
each one was needed.

| field | what |
| --- | --- |
| `sourceRoots` | the directories to count as "files". A monorepo's entry directory undercounts: Excalidraw's element package is 52 files and the bundle reaches 95 across six packages |
| `deps` | npm packages the bundle leaves external, installed into `<leg-dir>/exec/`. NOT into the leg directory itself — that is the checkout's parent, and mtsc walks up looking for `node_modules`, so it would start inlining them |
| `shims` | module specifiers Node cannot resolve but a bundler can, mapped to files in `<name>.shims/`. Rewritten in the copy that is EXECUTED, identically for every leg; the byte counts come from the untouched leg outputs |
| `execReplace` | literal string substitutions on the executed copy, for build-time globals a bundler would have replaced (`import.meta.env`) |

## `expected.json`

The regression gate. Absolute byte counts move with every emitter
change, so what is pinned per target is the **verdict** (WIN / NEUTRAL /
LOSS) plus the delta with a tolerance of `max(64, 0.5% of aware)`. A
target may not silently go from WIN to NEUTRAL, and a win may not
quietly erode; the byte counts themselves are free to drift.

`status` is pinned too, which is how a `blocked` target announces
itself the day it starts working: the status changes, and the gate
fails until the baseline is re-recorded with the new measurement.
