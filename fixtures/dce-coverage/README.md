# Dead-code elimination coverage

`expected.json` is the recorded verdict for every case in
`scripts/verify_dce_coverage.mjs`. The harness fails when a case
regresses against it — a `PASS` that became a `MISS`, or anything that
became `BROKEN`. A case already recorded as `MISS` or `GATED` stays green,
so a known gap is carried explicitly instead of being rediscovered.

Verdicts:

| | meaning |
| --- | --- |
| `PASS` | the dead code is gone under the plain pipeline |
| `GATED` | gone only with `--mangle-properties`, which is by design: the pass depends on the same safety proof |
| `MISS` | the opportunity is real and not taken |
| `BROKEN` | the bundle misbehaves — a correctness bug, not a size one |

Update with `node scripts/verify_dce_coverage.mjs --update` after
deliberately changing what is eliminated, and say in the commit message
which line moved and why.

## The recorded MISS

`unused-class-field` is a deliberate trade, not an oversight:

```ts
class C { liveField = 1; deadmark_field = 2; read() { return this.liveField; } }
console.log(new C().read());
```

`deadmark_field` survives because `console.log(new C().read())` seeds
class `C` as observed, and an observed class reserves all of its member
names. That seeding is what fixes the false positive in
`console.log(new C())`, where the instance itself really is printed and
its fields really are visible.

The imprecision is the receiver position: here the sink observes the
method's RETURN, not the instance, so reserving C's members is more than
soundness requires. Distinguishing "the instance flows to the sink" from
"a member is read off the instance and THAT flows to the sink" means
tracking method return values, which the analysis does not do for
methods (it does for named functions, via `FuncInfo.returns`). Until it
does, the blunt answer is the safe one — losing a field's bytes beats
deleting a field somebody can see.
