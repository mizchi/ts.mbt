# What the checker supports, what it will not, and why

Status on 2026-09-18 (`just verify-checker-soundness`):

```
TP  err+flag  : 2670   (of which via parse rejection: 390)
MISS in scope : 45     (the backlog — this one can reach zero)
OUT OF SCOPE  : 19     (declared in scripts/checker_out_of_scope.txt)
FP  ok +flag  : 0      (soundness bugs — TS7 accepts these)
PFLEGAL       : 0      (parser rejects TS7-legal files — parser bugs)
TN  ok +quiet : 1750
```

This document is the STRATEGY half: what the gate reports and why it is
two numbers, which tier each remaining family sits in, how often each
feature appears in real code, and what is declared out of scope.
`src/checker/UNSUPPORTED.md` is the other half — every remaining MISS
file with tsc's own diagnostic, a capability probe of the common shape of
each feature, and the declared abstentions with their legal neighbour.
`docs/checker-priority.md` is the TS6-era document whose conclusion
("incremental recall wins are exhausted") was refuted by measurement and
is kept only as history.

## 1. Why the gate reports two MISS numbers

A single `MISS` figure summed work worth doing now with files nobody
should ever fix, so it could answer neither "are we done?" nor "what
next?". The oracle therefore splits the bucket:

1. `scripts/checker_out_of_scope.txt` holds the declared remainder, one
   path per line with a kind and a reason. Every entry was decided by
   OPENING the file, not by its directory or its name — the first pass
   keyed on both and came out twice too large.
2. Only the MISS branch consults that file. A listed file can still be a
   TP, an FP or a PFLEGAL, so being out of scope withholds a rule and
   never excuses a wrong answer. The FP budget is untouched at 0.
3. The oracle reports a **STALE** entry the moment a listed path stops
   being a MISS, which is what keeps the file from becoming a
   suppression list.
4. `--max-miss` gates the in-scope number. That closes a direction nothing
   used to watch: a rule that stops firing moves a file from TP to MISS
   and every other number absorbs it silently. The budget is lowered
   whenever a batch improves it and never raised — it caught two accidental
   TPs on its first real use (batch DO).

The asymmetry is deliberate. A MISS is expected because we model a subset
of TypeScript; an FP never is.

## 2. The 45 in-scope MISS files, by machinery

From `node scripts/checker_miss_rank.mjs` over the oracle's `--miss-list`
— every file run through the local compiler under its own `// @option:`
header and grouped by what a rule would need. Grouped by MACHINERY and not
by error code, because a code is not a difficulty class: TS2322 is the
largest bucket at 16 files and is fourteen unrelated causes, and 27 codes
have exactly one file each.

| family | files | tier | the one-line reason |
|---|---|---|---|
| generic inference and generic assignability | 12 | 3 | type arguments inferred from arguments, then checked against the rest of the call; generic signatures compared with each other |
| object literals, contextual typing, widening | 9 | 3 | union normalization on widening, spread of a union, `(x \|\| {}).a`, tagged-template substitutions, return-type inference from a body |
| classes, `this`, mixins | 7 | 3 | mixin over an intersection or type-variable base, `typeof this.x` in a type position, `this` in an object-literal `function` property |
| type-level machinery | 6 | 3 | variadic tuples, template-literal placeholders, TS2536 key checks, a conditional left unresolved inside `&` |
| narrowing and control flow | 4 | 3 | aliased guards (fail direction is an FP), `typeof x === "object"` to `object \| null`, narrowing to `never`, definite assignment |
| lib and host shapes | 4 | 3 | `Intl` members by lib version, the `Promise` constructor's callback parameter, structural `Generator` comparison |
| name resolution and declarations | 3 | 3 / declared | all three are recorded rejections or abstentions with a probe |

Every row is Tier 3, and that is the honest reading of MISS 45: **there is
no Tier 1 or Tier 2 left.** Tier 1 (conditional through a generic alias,
the utility-type table, overload selection, computed `unique symbol` keys
as a cluster) was taken in batches DI–DM and EB, or opened and found to be
eleven unrelated codes rather than a feature. Tier 2 (the grammar and
declaration rules, the implicit-any family, the strict-null bucket) was
taken in batches DN through ET. The thirty-four files between MISS 80 and
MISS 45 took twelve batches and roughly one rule per file, which is the
rate this tier now has — and six of those batches (EU–EZ) also bought
four CAPABILITIES the corpus cannot score at all, fixed three false
positives on legal code, and found a segfault.

### Tier 3 — DEFER: real but expensive

All 45. Every one is a genuine TypeScript behaviour and none is reachable
without machinery we would have to build — real generic inference,
contextual typing, spread-type computation, a flow graph, lib interface
merging. Do not take these for the MISS count. Take an individual file
only when a real bridge input or `mtsc` target demands it, and record
which one did; the measured rate here is about one file per investigation.

Five of the 45 carry a **recorded rejection or abstention with a probe**,
so they should not be re-attacked as written (details in
`UNSUPPORTED.md` §1 and §3): `inferTypesInvalidExtendsDeclaration` (the
parser reduces the conditional before the checker sees it),
`await_incorrectThisType` (structural assignability of a phantom type
parameter makes the naive rule unsound), `stringLiteralTypeIsSubtypeOfString`
(173 lib interfaces are declared empty), `symbolProperty3` (needs the
`Symbol` constructor as a value type, for a spelling nobody writes),
and `localTypes4` (a block-local type declared twice is deliberately left
unregistered). `intersectionWithIndexSignatures` was the sixth and is a
TP since batch EY: batch EN had measured the deciding arm as unreachable
for an intersection-typed VALUE and written that finding what abstains
first "is the actual work" — it was an explicit
`(Intersection(_), _) => return` in `check_expr_against`, under a comment
saying the modelling was too coarse. A recorded abstention is a lead and
its REASON has a date on it; that is §6.1 of `UNSUPPORTED.md` and this is
its sixth instance.

### Tier 4 — WON'T SUPPORT: 19 files, declared out of scope

Checked in as `scripts/checker_out_of_scope.txt` under six kinds:

- **removed-feature** (4): `import x = module("m")`, and three files whose
  only error is TS6053 on a `///<reference path>` — program construction,
  which the checker has no notion of. Two of those were TPs by ACCIDENT
  until batch DO fixed the `+=` string-building false positive that had
  been flagging them.
- **malformed** (3): the parser's error-recovery corpus (`x: break`,
  `x: public`, `[public a]`). Taking this cluster for its size is fitting
  the corpus.
- **lexer-adversarial** (1): `/**// asdf /`, written to defeat
  regex-versus-comment disambiguation.
- **resource-mgmt** (5): `using` / `await using`, measured at ZERO
  occurrences across 5,697 real files (§3). Only files whose DIAGNOSTIC
  needs the feature are here — `usingDeclarationsWithObjectLiterals2` is
  named for `using` and errors on `value: null`, and is a TP since batch EC.
- **no-local-oracle** (5): TS7 errors and the local compiler 6.0.3
  accepts, so there is no compiler to probe a legal neighbour against.
  A HARNESS limit, not a judgement about the language — revisit when the
  local compiler moves.
- **lib-diagnostic** (1): every error is inside `lib.es5.d.ts`, reached
  through an `interface Object` augmentation under
  `@skipDefaultLibCheck: false`. Found because the probe used to attribute
  OTHER files' diagnostics to the probed file.

## 3. How often each feature appears in real code

A corpus count is not real-world frequency. The second axis is measured
against real input: 3,000 `.d.ts` files from `node_modules` (what the
bridge consumes) and 2,697 `.ts` sources from the type-aware corpus (what
`mtsc` consumes). Measured once for the first version of this document;
the corpus has not changed since.

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
zero real files and are five of the out-of-scope entries. Decorators occur
in one `.d.ts` and no application source — a property of THIS corpus,
which contains no Angular, NestJS or TypeORM, so that row is a caveat and
not a verdict; the decorator rules that did ship (batches CU, EG) were
taken because they were the applied-in-some-places family, not for this
row.

Against that table, the capability probe in `UNSUPPORTED.md` §2 says
which features are still BLIND at the shape real code writes. After
batches EU–FA it was down to two — variadic tuples, and `this` inside an
object-literal `function` property (that one measured and not taken, with
its blocker) — and then probing the rows the table did not HAVE added a
third. `satisfies` (238) and `as const` (108) are the two commonest
features in the real-`.ts` column and neither had a row at all, nor did
`infer` (156 in `.d.ts`): a table with a stale row ranks the wrong work,
and a table with a MISSING row cannot rank it at all. Measured
2026-09-18: `satisfies` and `infer` are CAUGHT, and the probe turned up
the widest gap it has found — **a PRIMITIVE source against a LITERAL or
literal-union target is accepted**, at the binding, the assignment and
the call argument, for strings and numbers alike. `as const` was a red
herring for it and so were the next two causes guessed at, each refuted
by reading the code it named; INSTRUMENTING settled it in one run. Batch
FB then took the STRING half — all five spellings report now — and left
the numeric one, and the split is not where the first reading put it:
one abstention was blocking both, and its stated reason (our inference
widens a `const`'s literal where tsc keeps it) is TRUE for numbers,
booleans and bigints and FALSE for strings, because `infer_expr` erases
those three literals at the source and keeps `Literal(s)`. `as const`
was a red herring for the CAUSE and is the real residual: with the
assertion erased by the parser, a file carrying one abstains wholesale.
A strict-null member-chain receiver is a fourth BLIND row and is
deliberate.

That batch is also the clearest case here for measuring a checker change
on REAL packages rather than on the corpus, which batch EO argued for
and this is the first batch to need: it is **corpus-NEUTRAL** (TP 2670 /
MISS 45 / FP 0, identical), and on real code it both gains the
diagnostic and REMOVES five false positives — the relaxation exposed a
latent `let` widening bug (`let s = "a"` is `string` in tsc and stayed
`"a"` here), which is five reports on legal lines in zod's own locale
files. 118 -> 113 on zod, and byte-identical over a 4,085-file sweep of
every `.d.ts` in `node_modules` plus effect's 362 sources.
Conditional types, the utility table, mapped types, `keyof`, overload
selection, generic inference, generic METHOD calls, index-signature
reads through an anonymous object type, a mapped type over an infinite
key set, an intersection against an indexer, an optional chain's
`| undefined` past the guarded link, an optional METHOD, an INTERFACE's
overload set and a computed `unique symbol` key are all CAUGHT at the
common shape now.

The optional-chaining row is the argument for reading the two axes
TOGETHER rather than either alone. It is 144 occurrences in real
application source — the second commonest feature in that column — and
ONE conformance file, and what the probe found there was four separate
defects stacked on one shape, including a member spelling (`m?<T>()`)
that did not parse at all. Batch FA is the same read one row up:
`unique symbol` is 183 real `.d.ts` occurrences against ZERO conformance
files, and the anonymous spelling of ITS member key (`{ [k]: number }`)
did not parse either — which cost every member of such a type, not just
the computed one.

Two rows of that table were wrong in the direction that matters, and
both were found by re-measuring rather than by reading: the
index-signature WRITE read BLIND for two revisions and had been handled
in all four spellings the whole time, and the template-literal
placeholder row read BLIND while the error shape reports (the type it
computes is `string` rather than the evaluated literal, and both legal
neighbours are silent). A capability table nobody re-probes ranks the
wrong work, which is the same defect, one level up, that retired
`docs/checker-priority.md`.

## 4. What the conformance number cannot see

Three things, each with its own gate:

- **False positives on real code.** `FP 0` is a statement about 4,484
  conformance files. Batch EO measured `mtsc` on `zod@4.4.3` and found
  272 diagnostics with tsc accepting all of them; 85 were one missing
  shadowing test and 187 remain (`TODO.md`, batch EO). A real-package FP
  gate is filed and not yet built.
- **False positives on legal neighbours.** The corpus scores a file as a
  TP if we flag it AT ALL, so a wrong rule firing beside a right one is
  invisible. Batches EH, EM and EP–ET fixed eleven such false positives
  (five, two and four), every one found by probing a hand-written legal
  spelling or by a unit test and none by the corpus.
- **Cost.** A rule quadratic in a module-wide list is invisible to a
  corpus of few-dozen-line files; `just verify-checker-scaling` fits an
  exponent per axis and fails on growth.

## 5. Where the history is

Every batch from DZ onward is recorded in `TODO.md` under its own
heading with the before/after numbers, the rules shipped, the false
positives fixed and the rejections with their measurement. The
summarized lessons — the applied-in-some-places family, the
absent-versus-`: any` blocker, the label-for-objective substitution,
probing a recorded abstention's REASON — are in `CLAUDE.md`'s
`src/checker` section.
