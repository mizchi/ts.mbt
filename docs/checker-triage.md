# What the checker supports, what it will not, and why

`MISS 176` is not a backlog. It mixes three unrelated things — work worth
doing, work that needs machinery we have not built, and files nobody
should ever fix — so the number cannot rank anything and cannot tell you
when you are done. `docs/checker-priority.md` was retired for exactly
this reason: it concluded that incremental recall wins were exhausted,
having measured against the wrong oracle.

So this document classifies all 176 remaining MISSes by the **machinery a
rule would need**, prices each family against **how often the feature
appears in real code**, and assigns each one to a tier: SUPPORT NOW,
SUPPORT, DEFER, or WON'T SUPPORT. Everything below is measured. Where a
number is a judgement rather than a measurement, it says so.

The headline recommendation is at the bottom and it is not a rule: it is
to **stop reporting one MISS number**, because a single figure that mixes
declared-out-of-scope with real backlog is the thing that made this
document necessary. It is implemented — the gate reports `MISS in scope`
beside `OUT OF SCOPE` and gates the first — and §5 records what
that cost, including the two places this document's own family classifier
was wrong about which files belong in the second column.

## 1. The 176, by machinery

From `node scripts/checker_miss_rank.mjs` — every remaining MISS file run
through the locally installed compiler under its own `// @option:` header,
then grouped by what a rule for it would need. Grouped by **machinery**
and not by error code, because CLAUDE.md records twice that a code is not
a difficulty class (`symbolProperty*` spans seven codes and is one
feature; the decorator cluster looks like cheap grammar and is mostly
assignability).

| family | files | share |
|---|---|---|
| assignability-core | 48 | 27.3% |
| symbol + computed key | 16 | 9.1% |
| other (singletons) | 16 | 9.1% |
| legacy / broken syntax | 15 | 8.5% |
| mapped / conditional / template | 13 | 7.4% |
| generic inference | 11 | 6.3% |
| iterator protocol | 11 | 6.3% |
| implicit-any / strict | 10 | 5.7% |
| strict-null / narrowing | 8 | 4.5% |
| `this` typing | 7 | 4.0% |
| decorator signature | 7 | 4.0% |
| locally accepted | 6 | 3.4% |
| resource management (`using`) | 6 | 3.4% |
| overload resolution | 2 | 1.1% |

The largest bucket is the least useful one. Opening all 48
`assignability-core` files shows about ten unrelated causes — variadic
tuples, intersections, contextual typing, `globalThis`, index-signature
subtyping, spread types, enum indexers — so "TS2322 is the biggest
bucket" ranks no work at all. That is the same substitution this repo has
made four times before (`computed_props`, `loops`, `typeofs`,
`sequences`): a label standing in for the objective.

## 2. How often each feature appears in real code

A corpus count is not real-world frequency —
`parser/ecmascript5/parserErrorRecovery_ParameterList6` is broken syntax
nobody writes. So the second axis is measured against real input instead:
3,000 `.d.ts` files from `node_modules` (what the bridge consumes) and
2,697 `.ts` sources from the type-aware corpus (what `mtsc` consumes).

| feature | real `.d.ts` | real `.ts` app |
|---|---|---|
| conditional type | **345** | 24 |
| `keyof` | 194 | — |
| `unique symbol` | 183 | — |
| `infer` | 156 | — |
| mapped type | 143 | 31 |
| `this` return type | 115 | — |
| index signature | 102 | — |
| computed `[Symbol.x]` key | 72 | — |
| template-literal type | 57 | 151 |
| variadic tuple | 20 | — |
| `satisfies` | — | 238 |
| optional chaining | — | 144 |
| `as const` | — | 108 |
| **`using` / `await using`** | **0** | **0** |
| **decorator** | **1** | **0** |

Two rows decide two tiers on their own. `using` declarations occur in
**zero** of 5,697 real files, and they are 6 of our MISSes. Decorators
occur in one `.d.ts` and no application source — though that is a
property of *this* corpus, which contains no Angular, NestJS or TypeORM,
so the decorator row is a caveat rather than a verdict.

## 3. What the checker can already do — probed, not assumed

The classification above says what a file *needs*. It does not say what we
already have, and guessing at that was wrong twice while writing this
document. So each family's **common shape** was probed directly against
`tscheck --strict`.

The first probe run reported every family BLIND, which was a harness
error, not a finding: `check_module_function_bodies` checks function
bodies, and the probes put the error at top level where nothing visits it.
Re-probed inside a function:

| common shape | verdict |
|---|---|
| basic assignability (`const n: number = "s"`) | CAUGHT |
| argument count | CAUGHT |
| property missing on object literal | CAUGHT |
| mapped type, via a generic alias | CAUGHT |
| `keyof` | CAUGHT |
| strictNullChecks (`o.a` where `a?:`) | CAUGHT |
| `this` return type | CAUGHT |
| index signature value type | CAUGHT |
| variadic tuple | CAUGHT |
| generic function inference | CAUGHT |
| **conditional type via a generic alias** | **BLIND** |
| **utility types** (`Exclude`/`NonNullable`/`ReturnType`/`Awaited`) | **BLIND** |
| **template-literal type with a placeholder** | **BLIND** |
| **computed `unique symbol` key** | **BLIND** |
| **overload resolution** | **BLIND** |

This is the most useful table in the document, and it reorders everything.
Four of the five blind rows are features that appear in *hundreds* of real
`.d.ts` files, and they are blind at the shape real code actually writes —
not at a corner.

### The conditional-type finding is narrower than it looks

Worth stating precisely, because the cost estimate depends on it:

```
const x: (string extends string ? number : boolean) = true;  // CAUGHT
type E = string extends string ? number : boolean;           // CAUGHT
type E<T> = T extends string ? number : boolean; E<string>   // BLIND
```

The conditional evaluator **works** on concrete types, and
`substitute_params` (`generics.mbt:63`) and `substitute_named`
(`simplify.mbt:57`) both already have a `Conditional` arm. Generic alias
instantiation also works — object, array, union, passthrough and
interface bodies all resolve correctly, as does the same shape written as
an interface. It is only the composition of the two that abstains.

So this is a **wiring or reduction-order gap, not a missing feature** —
one investigation, not one implementation. And it is the single
highest-value item on the list, because every utility type in the standard
table is a generic alias over a conditional body, which means
`ReturnType`, `Exclude`, `NonNullable`, `Parameters` and `Awaited` are all
inert in the body-checking path today.

One control matters for interpreting all of this: `Bogus<number>`, an
*unresolved* generic name, is also silent. Some of these blind rows may be
one abstention path rather than five, which is the first thing to check
and would make the fix cheaper still.

## 4. The proposed triage

### Tier 1 — SUPPORT NOW (~31 files, and the real prize is not the files)

| item | why | MISS files |
|---|---|---|
| conditional through a generic alias + the utility-type table | 345 real `.d.ts` files; a wiring gap, not a feature; unblocks `ReturnType`/`Exclude`/`Awaited`/`Parameters` wholesale | 13 |
| computed `unique symbol` keys | 183 `.d.ts` declare `unique symbol`, 72 use `[Symbol.x]` keys; blind at the common shape | 16 |
| overload resolution (select the right signature) | overloads are the reason `.d.ts` files exist; blind | 2 |

Take these for the capability, not the count. The conformance yield is
modest; the difference is that a `.d.ts` using `ReturnType<typeof f>`
currently type-checks by *abstaining*, which is a silent hole in the
bridge's primary input.

### Tier 2 — SUPPORT (~25 files, cheap and mechanical)

- **Remaining grammar / declaration rules.** TS2371 (default parameter on
  a bodiless overload), TS2394 (overload incompatible with its
  implementation), TS2386, TS2448, TS1308, TS2842, TS2708, TS1166, TS2300.
  These are the batch-DI shape: `has_body_block` at
  `parser_class.mbt:2936` already separates a signature from an
  implementation, and that site's own comment states the abstention.
  TS2371 and TS2394's arity half went in as batch DN, TS2386 and
  TS2394's parameter-type half as batch DS. Both TS2394 halves are
  ONE-DIRECTIONAL and the message says nothing about which direction, so
  the table had to be probed cell by cell — a SHORTER implementation is
  legal, an incompatible parameter type is not.
- **implicit-any / strict family** (10 files): TS7009/7010/7018/7022/7023/
  7031/7053, TS2564/2565/2729. This is what a real codebase hits the day
  it turns `strict` on, which makes it the highest *user-facing* value in
  Tier 2 even though the corpus count is small. TS7009 went in as batch
  DO, TS2565 (expando use-before-assign) as batch DS, and TS7010 (a
  bodiless member signature with no return annotation) plus TS7022 /
  TS2448 (a self-referential initializer) as batch DT; TS7031/TS7018 is
  REJECTED with a mechanical blocker recorded in TODO.md.

  **TS7023 and TS7053 do NOT belong in this tier**, and calling them
  "cheap and mechanical" was the label-for-objective substitution this
  document is written to warn about — measured by opening the files.
  TS7023 is three files (`for-of33` / `-34` / `-35`) that all need an
  inference CYCLE detector through a class method's un-annotated return
  type; the only cheap version would key on the exact corpus shape ("the
  iterated class's `next()` returns the loop variable"), which is fitting
  the corpus. TS7053 is two files needing union-of-index-signature member
  resolution (`{ foo: number } | { [s: string]: string }`) and
  assignment-target widening of `(options || {}).a` — both Tier 3
  assignability work, and both files also carry TS2339 / TS2322 for the
  same reason. Five files moved to Tier 3.
- **strict-null / narrowing** (8 files).

### Tier 3 — DEFER (~93 files, real but expensive)

`assignability-core` (48), `generic-inference` (11), `iterator-protocol`
(11), `this-typing` (7), `other` (16). Every one is a genuine TypeScript
behaviour and none is reachable without machinery we would have to build
— intersection reduction, contextual typing, `globalThis` modelling,
index-signature subtyping, the async-iterator protocol.

Do not take these for the MISS count. Take an individual file only when a
real bridge input or `mtsc` target demands it, and record which one did.
The measured rate here is 2–12 files per batch, so the count will not move
meaningfully and pretending otherwise is how `docs/checker-priority.md`
went wrong.

`decorator-signature` (7) sits here rather than in WON'T SUPPORT on a
caveat, not a measurement: this corpus samples no decorator-heavy
framework. Promote it if a bridge target uses Angular/NestJS/TypeORM.

### Tier 4 — WON'T SUPPORT (19 files, declared out of scope)

Checked in as `scripts/checker_out_of_scope.txt`, one path per line with
its reason, so none of it is re-litigated from memory.

**The estimate above this line said ~24 and the answer is 17**, because
the estimate came from the family classifier and the 17 came from opening
every file. Both corrections are the same mistake this document warns
about in §1 — a label standing in for the objective:

- **`legacy` / broken syntax — 6 of the 15, not 12.** The classifier keyed
  on the DIRECTORY, and `parser/ecmascript5/` holds ordinary current
  TypeScript as well as the error-recovery corpus.
  `parserErrorRecovery_ParameterList6` (`x: break`), `parser553699`
  (`x: public`), `parserIndexSignature2` (`[public a]`), `parser519458`
  (`import x = module("m")`), `parserRealSource3` (`///<reference>` path
  resolution) and `parseRegularExpressionMixedWithComments` are out.
  `parserExportAssignment6` is `declare module "M" { export = A }` — an
  undefined-name check — and `parserES5SymbolProperty4` is
  `[Symbol.isRegExp]`, a lib member lookup; both are ordinary backlog.
  `parserCastVersusArrowFunction1` and `parserConstructorAmbiguity3` have
  parse-ambiguity PURPOSES and ordinary DIAGNOSTICS (TS2403 on nine
  conflicting `var v`, TS2558 type-argument arity), which is not the same
  thing. **Three more are not legacy at all** — `parserParameterList16`/`17`
  and `parserClassDeclaration12` are the TS2371/TS2394 overload rules, and
  they belong in Tier 2.
- **`resource-mgmt` (`using`) — 5 of the 6.** Zero occurrences in 5,697
  real files, which is the strongest out-of-scope case on the list; revisit
  if a real dependency adopts explicit resource management. But a file
  NAMED for `using` can carry an error `using` has nothing to do with:
  `usingDeclarationsWithObjectLiterals2` is TS7018 on `value: null`, which
  a plain `const` reproduces under the same two flags (probed), so it is
  Tier 2's implicit-any family and stays in scope.
- **`locally-accepted` — 6.** TS7 errors on these and the local compiler
  6.0.3 accepts them, so there is no oracle to develop against and no way
  to write the legal-neighbour test this repo requires of every rule. This
  is the one out-of-scope reason that is a HARNESS limit rather than a
  judgement about the language — revisit when the local compiler moves.

## 5. The recommendation that is not a rule — DONE

**Stop reporting a single MISS number.** It summed Tier 1 (worth doing
now) with Tier 4 (declared never), so it could answer neither "are we
done?" nor "what next?" — and a metric that answers neither is what
produced a retired strategy document.

That is now what the gate does:

```
TP  err+flag  : 2577   (of which via parse rejection: 390)
MISS in scope : 138   (the backlog — this one can reach zero)
OUT OF SCOPE  : 19     (declared in scripts/checker_out_of_scope.txt)
FP  ok +flag  : 0     (soundness bugs — TS7 accepts these)
PFLEGAL       : 0     (parser rejects TS7-legal files — parser bugs)
```

1. `scripts/checker_out_of_scope.txt` holds the Tier 4 paths, one per line
   with its reason and its kind (`removed-feature`, `malformed`,
   `lexer-adversarial`, `resource-mgmt`, `no-local-oracle`).
2. `checker_conformance_oracle.sh` reads it and splits the MISS bucket.
   Nothing else consults it, so a listed file can still be a TP, an FP or
   a PFLEGAL exactly as before — being out of scope withholds a rule, it
   does not excuse a wrong answer. `--scope-file /dev/null` reproduces the
   old single number.
3. The FP budget is untouched at 0.
4. `just verify-checker-soundness` gates the in-scope number with
   `--max-miss`. That also closes a direction nothing watched: a rule
   that STOPS firing moves a file from TP to MISS, and every other number
   in the report absorbs that silently. Lower it whenever a batch improves
   it, the way the FP budget only ever tightened.

Two properties the scope file needs in order not to rot, both implemented
rather than asserted. Every entry was decided by opening the file, which
is what took the count from ~24 to 17. And the oracle reports **STALE**
entries — listed paths that are no longer a MISS, because a rule landed or
the file left the corpus — since an entry nobody re-checks is exactly how
a scope file turns into a suppression list.

The one thing preserved from the old regime is the asymmetry. A MISS is
expected because we model a subset of TypeScript; an FP never is.
