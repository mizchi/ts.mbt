# `tsc-extra` — TypeScript test cases the upstream suite does not contain

These cases came out of probing the real compiler while building this repo's
checker. Each one shows how tsc behaves (which spellings are legal, which
are errors) in a place where the upstream TypeScript suite has no test. They
are kept in the upstream harness format so they can be contributed back to
`microsoft/TypeScript`.

The five cases under `feedback/` are different from the rest. Each shows a
TypeScript 7 behaviour that looks inconsistent, with the spelling that
compares against it in the same file. They are the reports to file. Every
other case is coverage: tsc's answer looks right and nothing upstream pins
it.

## Layout

```
cases/<area>/<name>.ts      one upstream-format case (`// @option: value` header)
baselines/<name>.errors.txt TypeScript 7's diagnostics, in the upstream format;
                            absent when tsc accepts the file, as upstream
mtsc-misses.txt             `bad…` declarations mtsc does not report (declared)
issue-drafts/<name>.md      a bug-report draft for a `feedback/` case with no
                            upstream duplicate (upstream template headings)
```

Upstream baselines are flat, so case basenames are unique across areas.
Every name is checked against the upstream test names (see below).

## Conventions

- **Header.** `// @strict: true` and `// @target: esnext` unless the case is
  about another setting. As in the upstream harness, the header lines and
  the blank lines after them are stripped before the file is compiled. Line
  numbers in a baseline count from the first line of content.
- **`ok…` / `bad…`.** A top-level function, `const` or class named `ok…`
  (`Ok…` for a class) claims that tsc reports nothing inside it. One named
  `bad…` (`Bad…`) claims that tsc reports something there. The harness
  checks every claim against tsc's own spans, so no case can call a line
  legal when tsc rejects it. Declarations with other names make no claim.
- **Modules.** A case that augments `declare global` or shadows a lib name
  has `export {};`. In a script the same declaration means something else,
  and the case would pin the wrong thing. `moduleLocalNonNullableShadowsLibUtility`
  documents this: in a script, its alias is TS2300 against the lib.

## Verifying

```bash
just verify-tsc-extra
```

The script runs `scripts/verify_tsc_extra.mjs` against
`node_modules/typescript` (**TypeScript 7.1.0-dev.20261114.1**, the
nightly on `main` that the oracle's corpus is pinned to) and answers three
questions, in order:

1. **Baseline.** Does TypeScript 7 still produce the committed
   `.errors.txt`? A drift here is news about tsc, not about mtsc. Read the
   diff, then run `just verify-tsc-extra --update`.
2. **Claims.** Does every `ok…` / `bad…` name agree with tsc?
3. **mtsc.** `mtsc check --strict` runs the unfiltered checker. Any report
   on an `ok…` declaration fails as a false positive. So does any report in
   a file tsc accepts outright, or a parse failure on one. A `bad…`
   declaration mtsc stays silent on is a MISS. A MISS fails unless it is
   listed in `mtsc-misses.txt`, and a listed MISS that no longer misses
   fails as STALE.

The baseline generator ports the harness's `iterateErrorBaseline`: header
lines, squiggles, message chains, `!!! related` lines with `--:--` for lib
files, untruncated types, and no final newline. It was checked against the
vendored TS7 baselines. Over 500 sampled single-file upstream conformance
cases it reproduces the committed `.errors.txt` byte for byte (ignoring
CRLF) in 498. Neither of the two misses applies to a case here: one
references the harness's virtual `/.lib/react16.d.ts`, and the other is
where the harness places a removed-option error (TS5102). So a baseline
here is what upstream's own run would print, though upstream also
generates `.types` / `.symbols` / `.js` and this harness does not.

## How "not upstream" was established

- **Names.** No case basename matches an upstream test name. The check runs
  against `scripts/ts7_baselines/tsgo_ran_set.txt` every time. Pass
  `--upstream DIR` to also check every case under a checkout of
  `tsc/testdata/tests/cases` (compiler and conformance: 12,974 files at
  `v7.1-beta`, 13,053 at the `main` nightly `6bdcb54d`; checked at both).
- **Text.** For every case, the share of its non-trivial lines that appear
  verbatim in any single upstream case is **at most 0.33**. Most cases
  score 0, so none is a copy of an upstream test.
- **Meaning.** Text cannot show whether a case is covered in substance, so
  the nearest upstream test is named below wherever one exists. The case
  adds the cells that test lacks. Check the named test again before
  filing.

## Feedback candidates

Each was verified on TypeScript 7.1.0-beta and again on the nightly
`7.1.0-dev.20261114.1` (`main` at `6bdcb54d`), where all five reproduce
unchanged — so none was fixed between the beta and current `main`.

The upstream trackers (microsoft/TypeScript, and the archived
microsoft/typescript-go) were searched on 2026-11-15. Two cases are already
reported, and the other three have a draft in `issue-drafts/`. The drafts
are written to be filed by hand, after checking them against the
Playground nightly.

| Case | What looks wrong | Compare | Upstream |
| --- | --- | --- | --- |
| `feedback/nullishCoalescingVoidLeftOperand` | `void 0 ?? y` (and `(void 0)`, `void f()`) is **TS2869** "the left operand is never nullish". `void` always yields `undefined`, so the right operand is always reached. | `undefined ?? y` is TS2871 "always nullish" | **Duplicate of #60276** (`void 22 ?? true`), closed as Working as Intended: the rule "in the vast majority of cases, catches operator precedence bugs". Locked. Do not file. |
| `feedback/declareFieldReadInDerivedInitializer` | `declare b: number; d = this.b` in a subclass is **TS2729** "used before its initialization". The base's `b = 1` has already run, and `new Derived().d === 1`. | the same read without `declare b` is accepted, and so is the redeclaration under `useDefineForClassFields: false` | No report. A regression from #43194 (TS 4.3), the fix for #42319, whose own "Expected behavior" lists this case as allowed. 4.2.3 accepts it, and 4.3.5 through 7.1 report it. [Draft](issue-drafts/declareFieldReadInDerivedInitializer.md) |
| `feedback/expandoElementAccessAssignmentInBranch` | An expando property assigned only in one branch is TS2565 when the write is `fn.q = 1`. When the write is `fn["q"] = 1`, the same later read is **accepted**. Both READ spellings are checked. | `typeFromPropertyAssignment36` (dotted writes only) | No report. microsoft/typescript-go#4134 restored the dotted-write case in tsgo. The element-access write behaves the same from 4.9.5 through 7.1. [Draft](issue-drafts/expandoElementAccessAssignmentInBranch.md) |
| `feedback/superCallInObjectLiteralComputedKey` | `super()` in an object literal's computed key is accepted directly in a constructor and **TS2466** inside an arrow, where a bare `super()` gets **TS2337**. The arrow is what differs, so one of the two codes is the wrong one. | `computedPropertyNames28` / `30` | No report. Unchanged from 4.2.3 through 7.1. The lowest impact of the three, since only the diagnostic differs. [Draft](issue-drafts/superCallInObjectLiteralComputedKey.md) |
| `feedback/templateLiteralNumberWhitespace` | `" "`, `"\n"`, `" "`, `" 1"` and `"1 "` all satisfy `` `${number}` `` (`+" "` is `0`). Upstream pins `"0x1"`, `"1e21"`, … and rejects `""`. No test says whether whitespace is meant to pass. | `templateLiteralTypesPatterns` | **Covered by #46109** (open, Needs Investigation, assigned). @ahejlsberg wrote there that whitespace-only strings are accepted because JavaScript's conversion allows them, and that "it makes more sense to not permit any whitespace". Do not file. |

## Coverage cases

| Area | Case | What it pins | tsc | Nearest upstream |
| --- | --- | --- | --- | --- |
| classes | `accessorOverPropertyThroughMixinBase` | TS2611 through `mixin(B)`. A member several bases declare is an accessor only when every declaration is one of the same kind. | TS2611 | `mixinAccessors3` |
| classes | `classExtendsInterfaceMergedWithValue` | Extending a plain interface is TS2689. Extending an interface merged with a construct-signature `declare var` is not. | TS2689 | — |
| classes | `noImplicitOverrideThroughMixinBase` | TS4113 for a member the mixin intersection lacks. Under `noImplicitOverride`, TS4114 for one it has. | TS4113 TS4114 | `override19` (TS4113 only) |
| classes | `privateNameStaticClashAndReadonlyLiteralField` | `static #a` beside `#a`. An unannotated `readonly` field has a literal type: the constructor write is an error, a read into a `let` widens. | TS2322 TS2804 | — |
| controlFlow | `assignmentInConditionAndNormalizedArrayLiterals` | `while ((m = re.exec(s)))`, boolean truthiness to `true` / `false`, and the normalized union of differently-keyed literals | TS18047 TS2322 TS2339 | `objectLiteralNormalization` |
| controlFlow | `bindingPatternDefaultsWithConstTuplesAndComputedKeys` | An `as const` default, a computed key that assigns its variable, and their evaluation order | TS2322 | `controlFlowBindingPatternOrder` |
| controlFlow | `forOfDestructuringAnyAndReadonlyMap` | `for (const [k, v] of …)` over `any` and over a `ReadonlyMap` | TS2322 | — |
| controlFlow | `loopBackEdgeLiteralAssignmentWithEarlyExit` | A literal assigned at the end of a loop body reaches the next iteration, for every loop kind and every early exit | TS2367 | — |
| controlFlow | `loopBackEdgeWritesThatReachTheJoin` | Which writes reach the back edge: dependent, labelled, pattern, `for`-head, overwritten, `continue`, caught throw | TS2345 TS2367 | — |
| controlFlow | `loopConditionsNestedBindersAndComputedKeyOrder` | A loop condition under the back edge, a caught vs uncaught `throw`, and left-to-right computed keys | TS2322 TS2345 TS2367 | — |
| declarations | `moduleLocalNonNullableShadowsLibUtility` | A module's own `type NonNullable<T> = T` is not the lib utility | TS2322 | — |
| declarations | `namespaceLocalInterfaceShadowsLibPromise` | A namespace-local `interface Promise<T>` shadows the lib type | TS2345 | — |
| inference | `boundViolationsShadowingAndNumericTemplates` | Bound violations through array arguments, shadowing closure parameters, and `${bigint}` / `${number}` / `infer X extends number` on edge-case strings | TS2322 TS2353 | `templateLiteralTypes4` |
| inference | `freshLiteralWideningAndNonNullableIntersections` | Fresh-literal widening at a generic call (`useState("")`), `NonNullable<T>` vs `T & {}`, intersections, nested `Extract` | TS2322 TS2345 TS2353 | — |
| inference | `genericMethodReturningNestedGenericFunction` | A method's binding flows into the bound of the generic function it returns | TS2345 | `wrappedAndRecursiveConstraints4` |
| inference | `intraExpressionInferenceFromMethodReturn` | `setup()`'s return types a sibling method's parameter (reduced, with an illegal neighbour) | TS2339 | `intraExpressionInferences` |
| inference | `optionalCallbackContextAndGenericInterfaceMethods` | An optional method-typed property as a contextual type, generic interface methods, an overload taking `Object` | TS2322 TS2339 TS2345 | — |
| inference | `overloadSetAsCallbackAndMissingAwait` | An overload set as a callback, and `Promise<string>` where `string` is expected | TS2322 TS2345 | — |
| lib | `errorIsErrorAndAugmentedRawJSON` | ES2026 `Error.isError` narrows, and a `RawJSON` augmentation merges | TS2322 TS2339 | — |
| parser | `contextualKeywordDeclareAsInterfaceName` | `interface declare<T>` | accepted | — |
| parser | `emptyTypeArgumentListInInstantiationExpression` | `fx<>` is TS1099, `fx<string>` is legal | TS1099 | `instantiationExpressions` |
| parser | `heritageCallWithTypeArguments` | `extends TaggedError("E")<{ … }>` | accepted | — |
| parser | `lowercaseInstantiationExpressionArgument` | `g(fx<string>, 1)` | accepted | — |
| parser | `newlineSeparatedGenericCallSignatures` | `<B>` on a new line begins a new call signature | accepted | — |
| parser | `typeParameterAndNamespaceOfOneName` | `P.Encoded` names the namespace member when a type parameter is also `P` | accepted | — |
| realWorld | `effectArrowConstTypeGuards` | effect `Result` guards written as arrow `const`s, generic ones included | TS2322 TS2339 | — |
| realWorld | `effectControlFlowLoopsFinallyAndFallThrough` | effect control flow: `try`/`finally`, `while (true)`, `switch` fall-through, a `for` update, `??=` | TS2355 TS2366 TS2454 | — |
| realWorld | `effectGlobalThisLibValuesAndAugmentedError` | `globalThis.Array`, an `Error` augmentation, a parameter named like a class | accepted | — |
| realWorld | `effectNeverCallsDeleteAndUnknownNarrowing` | a `never` call ending a `catch`, `delete` on an index-signature member, `unknown` narrowing | TS2345 TS2366 TS2790 | `controlFlowTypeofObject` |
| realWorld | `effectOptionalChainOnUnionOfClasses` | `ast.context?.isOptional` over a union of classes | accepted | — |
| realWorld | `effectOrBranchesConditionalObjectsAndBigint` | `||` then-branch, conditional branches, `[k: PropertyKey]`, bigint arithmetic | TS18048 TS2322 | — |
| realWorld | `effectOverloadedConstPredicateAndInOnObject` | `Predicate.hasProperty` (a predicate from an overloaded `const`), `"k" in object` | TS2339 | — |
| realWorld | `effectPipeableInheritedGenericOverloads` | `Pipeable`'s inherited generic `this` overloads resolve as a set | TS2554 | — |
| realWorld | `effectPredicatesOpenRecordsAndNullableTuples` | predicates as `boolean` values, open records, nullable tuples, `typeof` on a chain and on a callable union | TS2322 TS2345 | — |
| realWorld | `effectSwitchTypeofOptionalDiscriminantAndAliasedConditions` | `switch (typeof x)`, `e?._tag === …`, a guard to a subtype, an aliased `Array.isArray` | TS2322 TS2339 TS2741 | `narrowingByTypeofInSwitch` |
| realWorld | `zodAndEffectNarrowingShapes` | zod / effect narrowing: non-nullish initializers, property paths, `??=`, getter keys, `never` methods, `asserts`, discriminant splits | TS18048 TS2322 TS2353 | — |
| relations | `genericSignaturesDifferingOnlyInConstraints` | Generic signatures equal up to their constraints, a recursive constraint included | TS2322 | `assignmentCompatWithGenericCallSignatures4` |
| types | `keyofTupleAndTemplateInferNumberIndex` | `keyof` a tuple, `infer N extends number` in a template (`"01"` is not canonical) | TS2322 TS2345 | `templateLiteralTypes4` |
| types | `templateInferPatternsInConditionals` | `infer` in a template with a fixed part or a bound, as a conditional's check type | TS2322 | `templateLiteralTypes4` |

The `realWorld` cases are reduced from `zod@4` and `effect@4` sources that
this checker once reported on and tsc accepts. Each `ok…` declaration is the
shape the library writes; each `bad…` is the nearest illegal neighbour.

## Submitting upstream

Copy a case to `tsc/testdata/tests/cases/compiler/<name>.ts` (or the
matching `conformance/<area>/` directory) and accept the baselines upstream's
own way, which also writes `.types` / `.symbols` / `.js`. The `.errors.txt`
here should come out identical. Cases are grouped by the probe they came
from, so several mix related cells. Splitting one into per-topic files
before filing is fine: every claim is a named declaration and carries over.

## What building this found

Two defects in `scripts/lib/tsc-probe.mjs`, the probe every recorded "tsc
accepts / reports" in this repo goes through. Both gave wrong answers
without any warning.

- **Header options were dropped.** The probe passed only a fixed list of
  options to the compiler. `noImplicitOverride` was not on it, so a file
  asking for it was checked with the flag off. The checker's "a mixin base
  is exempt from TS4114" came from such a probe. TS7 reports TS4114 through
  a mixin, so the exemption is removed and the unit test that pinned it
  now expects the report. Every header option the upstream corpus uses
  that can change a diagnostic is honoured now. Any other option prints a
  warning instead of disappearing.
- **Global diagnostics were missing.** TS2318 ("Cannot find global type")
  under `@lib` / `@noLib` comes from `getGlobalDiagnostics()`. The probe
  never called it, so it reported such a file as accepted.
