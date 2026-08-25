# Findings from `just fuzz-mangle` that are not fixed yet

Each file is the smallest program the fuzzer could still fail on, as
`scripts/lib/fuzz-shrink.mjs` reduced it. They are kept here so an open
finding stays reproducible after the seed that found it drifts — the
generator changes, seeds do not survive it.

Reproduce one with:

```sh
mtsc <file> --bundle --treeshake --fold --minify --no-check --out /tmp/base.mjs
mtsc <file> --bundle --treeshake --fold --minify --no-check \
    --mangle --mangle-properties --reserve-entry-exports --out /tmp/mangled.mjs
node <file>; node /tmp/base.mjs; node /tmp/mangled.mjs
```

## `prop-write-into-observed-object.ts` — a mangle false positive

```ts
obj['q'] = { ...bag, g7: arr[2] };
console.log([obj]);
```

| | output |
| --- | --- |
| original (Node) | `{ p: 0, q: { alpha: 1, beta: 2, gamma: 3, g7: 2 }, r: 2 }` |
| `--bundle` | same |
| `+ --mangle-properties` | `{ p: 0, q: { a: 1 }, r: 2 }` |

`obj` reaches `console.log`, so it is observed recursively and its own
keys (`p`, `q`, `r`) stay reserved. What is WRITTEN into it does not:
`bag`'s names are spread into the value assigned to `obj.q`, and the
analysis never connects the two, so `beta` / `gamma` / `g7` are deleted
as dead and `alpha` is renamed.

The gap is in `symbol_graph.mbt`: `PropAssign(target, prop, val)` records
the target as a `PropReceiver` use and visits `val`, but adds no flow
edge from `val` into the target's symbol. Two things are needed, and the
second is why this is not a one-liner:

1. an edge `val -> SymVal(target)` for `PropAssign` / `IndexAssign` and
   their expression forms, so the backward pass carries the target's
   observability into the written value;
2. sources for the CONTENTS of an object / array literal.
   `collect_immediate_sources` currently answers `Literal(LitObject)`
   for one and stops, so a spread inside it is invisible. Widening that
   function would change what the numeric and container inferences see,
   so the observability walk needs its own source collector rather than
   a change to the shared one.

## `private-field-lowered-enumerable.ts` — a lowering bug

```ts
class C0 { #secret = 7; }
console.log([new C0()]);
```

| | output |
| --- | --- |
| original (Node) | `[ C0 {} ]` |
| `--bundle` | `[ C0 { __private_brand__0__secret: 7 } ]` |
| `+ --mangle-properties` | `[ c {} ]` |

Here the MANGLED output is the correct one. A real `#private` field is
not an own enumerable property, so `console.log`, `Object.keys` and
`JSON.stringify` cannot see it; mtsc lowers `#secret` to an ordinary
`this.__private_brand__0__secret` property, which all three do see. The
mangler is right to treat the brand as internal and drop the dead write.

This was the fuzzer's single largest family (104 of 300 seeds), and
until the reference leg was consulted on every mismatch it was
misreported as a mangler false positive — the unmangled bundle looked
authoritative because it was the unmangled one.

Fixing it means emitting real `#`-private syntax rather than a branded
property, which is a target-compatibility decision as much as a
correctness one.
