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

To add a target: append an entry to `CORPUS` in the harness, write
`<name>.driver.mjs`, then `just measure-type-aware --update`.

## `expected.json`

The regression gate. Absolute byte counts move with every emitter
change, so what is pinned per target is the **verdict** (WIN / NEUTRAL /
LOSS) plus the delta with a tolerance of `max(64, 0.5% of aware)`. A
target may not silently go from WIN to NEUTRAL, and a win may not
quietly erode; the byte counts themselves are free to drift.

`status` is pinned too, which is how a `blocked` target announces
itself the day it starts working: the status changes, and the gate
fails until the baseline is re-recorded with the new measurement.
