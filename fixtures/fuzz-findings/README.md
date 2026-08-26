# Findings from `just fuzz-mangle` that are not fixed yet

Fixed and removed from this list:

- **`prop-write-into-observed-object.ts`** — `obj['q'] = { ...bag }` with
  `obj` reaching a sink. There was no flow edge from a written value into
  the target's binding at all, so an observed object kept its own keys
  and lost everything written into it. Fixed by `sg_record_write_into`
  (the edge) plus `Symbol::written_values` / `collect_literal_keys` (the
  keys a written literal introduces, which name nothing else in the
  bundle). Regression case: `fixtures/mangle-safety/case39-write-into-observed`.

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
