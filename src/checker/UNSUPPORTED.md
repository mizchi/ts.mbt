# What the checker does NOT flag

Measured on 2026-09-20, after batches EU–FC:

```
TP  err+flag  : 2670   (of which via parse rejection: 390)
MISS in scope : 45     (the backlog — this one can reach zero)
OUT OF SCOPE  : 19     (declared in scripts/checker_out_of_scope.txt)
FP  ok +flag  : 0      (soundness bugs — TS7 accepts these)
PFLEGAL       : 0      (parser rejects TS7-legal files — parser bugs)
TN  ok +quiet : 1750
```

Every snippet below was minimized and run through both `tscheck` and the
real compiler (`node scripts/tsc_probe.mjs`, TypeScript 6.0.3), so each
entry is a measured gap and not a guess. `docs/checker-triage.md` is the
strategy half (tiers, real-code frequency, what the gate reports); this
file is the code a user would write and what happens to it.

One thing this file CANNOT rank, and batch FB is the instance: the
numbers above come from 4,484 single files of a few dozen lines each, so
a false positive reachable only from real code is invisible to them.
That batch is corpus-NEUTRAL on every metric above and removes six
reports on legal lines, five of them in zod's own sources. When a row here moves off
BLIND, run the change over real packages too — `mtsc --noEmit --bundle
node_modules/<pkg>/src/index.ts`, and a sweep of `mtsc check` over
`node_modules`'s `.d.ts` files, diffed against the baseline binary.

Batch FC is the sharper version of the same point and the reason to run
the BIGGEST real input rather than many small ones: `typescript.d.ts` is
accepted by tsc outright, so all **88** diagnostics `mtsc --noEmit`
reported on it were false positives and **80 were one rule** (TS2430).
88 -> 15, at TP / MISS / FP unchanged. It also corrected its own first
ranking — grouping the sweep by message shape put a different family on
top at 1,192 occurrences, which is the SWEEP's unit (one line per file
per diagnostic, over 3,723 mostly tiny hand-written shims) and not the
user's: on `mtsc --noEmit` that family is 8 against TS2430's 80.

## Regenerating this file

```sh
moon build --target native --release
bash scripts/checker_conformance_oracle.sh --miss-list /tmp/miss.txt   # the numbers + the 45 paths
node scripts/checker_miss_rank.mjs /tmp/miss.txt --json /tmp/rank.json # tsc's codes per file
node scripts/tsc_probe.mjs some-probe.ts                                # the legal neighbour
```

Two rules for reading the output, both learned the hard way:

- **An error CODE is not a difficulty class and a bucket LABEL is not a
  work item.** TS2322 is the largest bucket (16 files) and it is fourteen
  unrelated causes. Open the file before taking anything.
- **Check WHERE tsc put the diagnostic.** `tsc_probe.mjs` prints
  diagnostics raised in other files (`lib.es5.d.ts`) on their own line;
  one former MISS turned out to have nothing in scope at all.

---

## 1. The 45 in-scope MISS files, by machinery

Paths are relative to `typescript/tests/cases/conformance/`. The code is
what the local compiler reports on the file; where a rule was already
tried and rejected, the rejection is named.

### 1a. Generic inference and generic assignability — 12 files

Type arguments inferred from arguments and then checked against the rest
of the call, and generic signatures compared against each other.

| file | tsc | what is needed |
|---|---|---|
| `expressions/functionCalls/typeArgumentInferenceConstructSignatures` | TS2345 | infer `T` through `new C<T>(…)`, then check the remaining arguments against it |
| `expressions/functionCalls/typeArgumentInferenceWithObjectLiteral` | TS2345 | infer `T` from an object-literal argument, then reject a second argument of a different enum |
| `types/typeParameters/typeArgumentLists/wrappedAndRecursiveConstraints4` | TS2345 | instantiate a recursive constraint (`T extends Wrapper<T>`) before checking the argument |
| `types/typeRelationships/instanceOf/narrowingGenericTypeFromInstanceof01` | TS2345 | `B<T>` against `A<unknown>` after an `instanceof` narrowing of a generic |
| `types/typeRelationships/typeInference/genericCallToOverloadedMethodWithOverloadedArguments` | TS2345, TS2769 | pass an OVERLOADED function as a callback and pick the member that fits the parameter type |
| `types/typeRelationships/typeInference/intraExpressionInferences` | TS2322, TS2339 | intra-expression inference: a later property's callback parameter typed from an earlier property |
| `types/typeRelationships/typeInference/indexSignatureTypeInference` | TS2345, TS2403 | infer `T` from an index signature's value type (`NumberMap<Function>` against `StringMap<T>`) |
| `types/typeRelationships/assignmentCompatibility/assignmentCompatWithGenericCallSignatures4` | TS2322 | assignability between two GENERIC call signatures with recursive constraints |
| `types/typeRelationships/assignmentCompatibility/enumAssignabilityInInheritance` | TS2403 | the type of a `var` inferred through OVERLOAD resolution (`var r4: E` vs the overload's `Object`); the annotated shape `var r: E; var r: Object` is already flagged |
| `types/conditional/conditionalTypes2` | TS2322, TS2345 | variance of a conditional-type alias (`Covariant<A>` against `Covariant<B>`) |
| `classes/mixinWithBaseDependingOnSelfNoCrash1` | TS2345 | `typeof BaseItem` against the mixin constraint `new (...args: any[]) => any` when the base's constructor is not so typed |
| `decorators/decoratorCallGeneric` | TS1238 | a class decorator whose parameter is a generic interface `I<C>` instantiated with the decorated class |

### 1b. Type-level machinery — 6 files

```ts
function f<T extends any[], P extends any[]>(): [...T, ...P] {
  let x: [any, any] = [null, null];
  return x;   // tsc: TS2322 — no match for variadic element at position 0
}
```

```ts
interface NMap { 1: "A"; 2: "B" }
declare const g: <T extends 1 | 2>(x: `${T}`) => NMap[T];
type G = <T extends 1 | 2 | 3>(x: `${T}`) => NMap[T];
const g2: G = g;   // tsc: TS2322 — "3" is not assignable to "1" | "2"
```

```ts
type Something<T> = { test: string } & (T extends object ? { arg: T } : { arg?: undefined });
function f<A extends object>(a: A, sa: Something<A>) {
  sa = { test: "bye", arg: a, arr: a };   // tsc: TS2322 — arr is excess
}
```

| file | tsc | what is needed |
|---|---|---|
| `types/tuple/variadicTuples3` | TS2322 | spread-element matching against `[...T, ...P]`; assignability compares `Tuple` element by element and abstains. Probed: `[...T]` as a parameter and `[string, ...number[]]` are equally blind, a concrete `[string, number]` is caught |
| `types/literal/templateLiteralTypes4` | TS2345 | `` `${T}` `` distributed over `T`'s constraint to produce a literal union — the parser carries `TemplateLiteralType` and nothing evaluates it against a type parameter |
| `types/literal/templateLiteralTypes7` | TS2322 | same machinery, at the assignability of two generic signatures |
| `types/mapped/mappedTypeErrors2` | TS2322, TS2536 | TS2536 "cannot be used to index": a key type parameter checked against the indexed type's key set |
| `types/conditional/conditionalTypesExcessProperties` | TS2322 | a conditional left UNRESOLVED inside an intersection cannot be projected to a field shape, so the excess-property check has no target. Batches DI–DM made a conditional resolve through a generic alias; the composition with `&` still abstains |
| `types/conditional/inferTypesInvalidExtendsDeclaration` | TS2304 | **REJECTED after instrumenting** (batch EI): the type parser REDUCES `T extends infer A extends B ? …` when it can decide the relation, so the checker receives the bare `Number` and neither `A` nor its bound `B` survives to be resolved |

### 1c. Object literals, contextual typing, widening — 9 files

| file | tsc | what is needed |
|---|---|---|
| `expressions/objectLiterals/objectLiteralNormalization` | TS2322 | normalize `{a} \| {a, b} \| {a, b, c}` on widening so `{ b: "x" }` is rejected against it |
| `expressions/contextualTyping/objectLiteralContextualTyping` | TS2403 | the inferred type of `bar({})` with `bar<T>(param: { x?: T }): T` must be `unknown`, and a redeclaration `var b: {}` must conflict with it |
| `types/spread/spreadUnion2` | TS2403 | spreading a UNION produces a union of object types, not one object with optional members |
| `expressions/propertyAccess/propertyAccessWidening` | TS2339, TS7053 | `(options \|\| {}).a` widens to `{ a: string } \| {}` and the access must fail on the `{}` member |
| `types/union/unionTypeWithIndexSignature` | TS2339, TS2540, TS7053 | member resolution on a union where one member is an index signature (`{ foo: number } \| { [s: string]: string }`) |
| `expressions/contextualTyping/taggedTemplateContextualTyping2` | TS2345 | a tagged template's substitutions checked against the tag function's parameter types |
| `expressions/contextualTyping/superCallParameterContextualTyping2` | TS2349 | the parameter of an arrow passed to `super(...)` typed contextually from the base constructor, so `new Number()` inside it is not callable |
| `statements/for-ofStatements/ES5For-of8` | TS2322 | return-type inference from a function BODY: `function foo() { return { x: 0 } }` has no resolved return type here at all (`const bad: string = foo().x` is silent too) |
| `types/tuple/wideningTuples7` | TS7010 | TS7010 on a function EXPRESSION at a `var` initializer; the same shape reports for a function DECLARATION |

### 1d. Narrowing and control flow — 4 files

```ts
try { } catch (e) {
  const isString = typeof e === "string";
  e = 1;
  if (isString) { e.length; }   // tsc: TS18046 — the alias was invalidated
}
```

| file | tsc | what is needed |
|---|---|---|
| `controlFlow/controlFlowAliasingCatchVariables` | TS18046 | following an ALIASED guard and invalidating it on assignment needs a flow graph. The fail direction is a false positive (claiming un-narrowed where it is narrowed), which is why this is deliberately last. Batch CS's TS18046 withdraws correctly on a same-block `typeof e` guard |
| `controlFlow/controlFlowTypeofObject` | TS2345 | `typeof x === "object"` narrows `unknown` to `object \| null`, and an earlier `if (!x) return` must have removed the `null` |
| `expressions/typeGuards/typeGuardsInRightOperandOfOrOrOperator` | TS2339 | narrowing to `never` in the right operand of `\|\|` after a guard chain exhausts the union. The common shape (`typeof x !== "string" \|\| x.length`) is already handled |
| `statements/for-ofStatements/ES5For-of7` | TS2403, TS2454 | `[]` inferring `never[]` so two `var x` declarations conflict, plus definite-assignment analysis for TS2454 |

### 1e. Classes, `this`, mixins — 7 files

| file | tsc | what is needed |
|---|---|---|
| `classes/mixinAbstractClasses.2` | TS2797, TS2515, TS2511 | a class extending a TYPE VARIABLE with an abstract construct signature (`T & typeof AbstractBase`) must itself be `abstract`; needs the intersection base's construct signatures |
| `classes/mixinAccessors3` | TS2611 | TS2611 through a mixin intersection base (`Mixin & BaseClass`); the direct-base spelling is already flagged |
| `override/override19` | TS4113, TS4117 | `override` against an INTERSECTION base `A & { context: Context }`; the class-base version ships, gated on "the base chain declares NOTHING" (see §3) |
| `types/specifyingTypes/typeQueries/typeofThis` | TS2331, TS2683, TS18048 | `typeof this.no` in a TYPE position: `parse_typeof_type_query` has no `This` arm, `skip_typeof_operand` eats it, and the annotation collapses to `Any`. The VALUE-position TS2331 shipped in batch EC |
| `types/thisType/looseThisTypeInFunctions` | TS2322, TS2339, TS2684 | a `(this: C, …) => …` value against a `(this: void, …) => …` type, and `this.n.length` where `n: number` inside such a function |
| `async/es2017/await_incorrectThisType` | TS2684, TS1320 | **REJECTED with a probe** (batch ET): `class C<E, A> { m1(this: C<never, A>) {} }` with a `C<number, string>` receiver is ACCEPTED by tsc because `E` is a phantom parameter and the comparison is structural; `applied_generic_mismatch` is nominal and false-positives on five hand-written cells |
| `types/typeRelationships/subtypesAndSuperTypes/stringLiteralTypeIsSubtypeOfString` | TS2420 | `class C implements String {}` needs the MERGED lib member list (the file declares 20+ members and misses the es2015 additions). **REJECTED** in its blunt form: 173 lib interfaces are declared EMPTY, so `class C implements WebGLProgram {}` is legal and a "declares nothing" shortcut is unsound |

### 1f. Lib and host shapes — 4 files

| file | tsc | what is needed |
|---|---|---|
| `es2023/intlNumberFormatES5UseGrouping` | TS2322 | `Intl.NumberFormatOptions.useGrouping` at `lib: es5` is `boolean \| undefined`; the lib-version-dependent member type |
| `es2020/es2020IntlAPIs` | TS2345, TS2554 | arity of `Intl` API calls (`Intl.RelativeTimeFormat`, `formatToParts`) from the es2020 lib |
| `async/es5/asyncAwaitNestedClasses_es5` | TS2345 | `new Promise<void>(resolve => resolve(null))` under `strictNullChecks`: the `resolve` callback's parameter type from the lib `PromiseConstructor` |
| `es6/yieldExpressions/generatorTypeCheck8` | TS2322 | structural comparison of `Generator<string, any, any>` against a hand-written `BadGenerator` through the lib iterator interfaces (`IteratorResult<T>`) |

### 1g. Name resolution and declarations — 3 files

| file | tsc | what is needed |
|---|---|---|
| `types/localTypes/localTypes4` | TS2304, TS2300 | a block-local `interface T` declared in two different functions. **Deliberately unregistered** (batch ET): the block-local type merge must not pick a winner among several declarations of one name — its first draft made the empty `interface T { }` in one function answer for the other and the gate scored that as a TP because the file errors for unrelated reasons |
| `es6/Symbols/symbolProperty3` | TS2464 | **REJECTED with evidence**: `var s = Symbol; ({ [s]: 0 })` — `s` infers as `Any`, and catching it needs the `Symbol` CONSTRUCTOR modelled as a value type. Nobody writes that |
| `decorators/class/decoratorChecksFunctionBodies` | TS2345 | the BODY of an arrow written inline as a member decorator (`@((x, p, d) => { func(3) })`). Member decorator expressions never reach the AST (`skip_param_decorators` / the class-body decorator skip); batches EE and EG read what they need off the skipped TOKENS, which cannot type-check a body |

---

## 2. Capability probe — the common shape of each feature

The classification above says what a FILE needs. This says what the
checker HAS, probed at the shape real code writes (inside a function
body, `--strict` where the rule needs it). Re-probed on 2026-09-18,
one file per row; every row is a real tsc error, so a BLIND row is a
measured gap.

| common shape | verdict |
|---|---|
| basic assignability, argument count, missing property | CAUGHT |
| conditional type through a generic alias (`E<string>`) | CAUGHT (batches DI–DM) |
| utility types (`ReturnType` / `NonNullable` / `Exclude` / `Awaited` / …) | CAUGHT (batches DI–DM) |
| overload selection by argument type (`o(1)` picking `(n: number) => number`) | CAUGHT (batch EB) |
| mapped type through a generic alias, `keyof` | CAUGHT |
| generic function inference (`id(1)` against `string`) | CAUGHT |
| `this` return type | CAUGHT |
| concrete tuple (`[string, number] = ["a", "b"]`) | CAUGHT |
| strictNullChecks on a bare binding or an aliased one (`a.b` with `a: T \| undefined`; `const x = o.a; x.b`) | CAUGHT |
| an object literal against an index signature (`{ x: "s" }` against `{ [k: string]: number }`) | CAUGHT (batch EM) |
| index-signature read through an INTERFACE (`interface M { [k: string]: number }`, `o["x"]` / `o.x` against `string`) | CAUGHT |
| index-signature read through an ANONYMOUS object type (`o["x"]` / `o[0]` on `{ [k: string]: number }`) | CAUGHT (batch EW) |
| index-signature write of the wrong type (`o["x"] = "s"` on `{ [k: string]: number }`) | CAUGHT — this row read BLIND until it was re-probed, and it was already handled in all four spellings |
| mapped type over an INFINITE key set (`{ [P in string]: D }`, `{ [P in keyof any]: D }`) | CAUGHT (batch EX) |
| generic METHOD call (`i.m(12)` where `m<T>(x: T): T`, on an interface / class / object type / function-type property) | CAUGHT (batch EV) |
| INTERSECTION source against an index signature (`{a: string} & {b: number}` into `{ [k: string]: string }`) | CAUGHT (batch EY) |
| `var` redeclared with a different type inside a FUNCTION scope, and the polymorphic `this` | CAUGHT (batch EU) |
| optional chain PAST the guarded link (`g?.p.q`, `b?.m(1)`, `u?.a[0]` against a non-nullable annotation) | CAUGHT (batch EZ) |
| optional METHOD, called and optional-called (`a.m?.(1)` / `e.m({…})` where `m?(…)`; `m?<T>(…)` did not PARSE) | CAUGHT (batch EZ) |
| an INTERFACE's overload set (`interface O { m(x: string): number; m(x: number): string }`, `p.m(1)`) | CAUGHT (batch EZ) — it reported the wrong return AND a false argument error before |
| a member keyed by a string-literal `const` (`const kk = "hello"`, `interface I { [kk]: number }`, `i.hello`) | **ABSTAINS — deliberate (batch FA)**: neither member parser can evaluate a key that depends on another declaration, and reading the undecidable name as "no member called `hello`" reported a line tsc ACCEPTS. A well-known key is decided statically and keeps its existence check |
| `satisfies` (excess property, a member of the wrong type, and the narrowed type surviving the read) | CAUGHT — probed 2026-09-18, all three cells |
| `infer` through a conditional alias (`type El<T> = T extends Array<infer U> ? U : never`) | CAUGHT |
| **a `string` source against a LITERAL or literal-union target** (`declare const s: string; const a: "other" = s`, `const b: "a" \| "b" = s`, `f(s)` against `(x: "a" \| "b")`, `const c: Mode = s`) | CAUGHT (batch FB) at all five spellings — the binding, the assignment, the union, the named alias and the call argument. A file carrying an ERASED `as const` abstains wholesale, since the parser drops the assertion and the object literal's property really does widen to `string` here |
| the same with a NUMERIC / BOOLEAN / BIGINT source (`declare const n: number; const a: 1 = n`, `const q = 789; const b: 1 = q`) | **BLIND — deliberate (batch FB)**: `infer_expr` erases those literals at the source (`NumberLit(_) => Number`), so a `const` really is widened here and reporting would be about OUR widening. The string arm survives because `Literal(s)` does not get erased |
| `as const` (`"hello" as const`, a tuple index, a DECLARED literal member) | CAUGHT at the verdict; the message names `string` where tsc names `"hello"`. Since batch FB a file carrying one also turns OFF the literal-target rule, because the parser erases the assertion — see §3 |
| **strictNullChecks on a member-chain receiver** (`o.a.b` with `a?:`) | **BLIND — deliberate**: the check is gated to a bare `Var` receiver because those are the bindings the narrowing engine rewrites precisely (batch DO) |
| **variadic tuple** (`[...T]`, `[string, ...number[]]`) | **BLIND** |
| computed `unique symbol` key (`interface I { [k]: number }` / `{ [k]: number }`, `i[k]` against `string`) | CAUGHT (batch FA) — the ANONYMOUS spelling did not PARSE at all, so every member of such a type was lost |
| **`this` inside an object-literal `function` property** (`{ n: 101, f: function () { this.n.length } }`) | **BLIND — measured and not taken**, see §3 |
| template-literal type with a placeholder (`` `${T}-x` `` against `"c-x"`) | CAUGHT at the error shape, and the type it computes is `string` rather than the evaluated literal — the legal neighbours (`"c-x"`, `string`) are silent, measured |

The two index-signature rows are the argument for keeping this table at
all: neither is in any conformance file, both were found only by this
probe, and batch EW closed the read for ZERO conformance files. The
write row is the other half of the lesson — it read BLIND for two
revisions and was already handled in all four spellings, so a table
nobody re-measures is a table that ranks the wrong work. The three
batch-EZ rows are the third half of it: optional chaining is 144
occurrences in real application source against ONE conformance file, and
the interface-overload row was a false positive on legal code —
`p.m(1)` against `m(x: string): number; m(x: number): string` reported
`expected string but got number`, measured against the pre-batch binary.
Batch FA is the fourth half: `unique symbol` was the top BLIND row at
**183 occurrences across 3,000 real `.d.ts` files**, and opening it found
three defects and two more false positives on legal code, for ZERO
conformance files. FP 0 and MISS 45 are statements about 4,484 files and
not about real code (batch EO measured zod at 272 diagnostics with tsc
accepting all of them; 187 remain after the shadowing fix).

---

## 3. Declared abstentions — rule known, deliberately silent

Each entry names the LEGAL neighbour that decides it. None is a bug.

| shape | tsc | why we stay silent |
|---|---|---|
| `declare const n: number; const a: 1 = n` — the NUMERIC / BOOLEAN / BIGINT half | TS2322 / TS2345 | The STRING half shipped in batch FB and this half did not, for a reason that is about our own inference rather than about the rule: `infer_expr` erases a numeric, boolean and bigint literal to its primitive at the source (`NumberLit(_) => Number`, `BoolLit(_) => Boolean`) and keeps a STRING one (`StringLit(s) => Literal(s)`). So `const q = 789` genuinely is `number` here where tsc says `789`, and reporting `number` against `1` would be a report on OUR widening. Undoing the erasure is a change at every consumer of a numeric literal's type, not a gate |
| a read off an erased `as const`, in a file that carries one | TS2322 | `parse_asserted_relational` drops the `as const` wrapper, with its reason at the site (the transform passes want the raw expression), so `{ k: "a" } as const` reaches the checker as the plain object literal whose property really does widen to `string`. Measured across fifteen spellings, this is the ONLY place our string widening diverges from tsc's — every other shape tsc keeps narrow (a template literal, an `as` assertion, a call returning a literal, a narrowed union member, a string enum member, an annotated `const`) we keep narrow too. So the parser records a file-level `<const-assertion>` marker and the literal-target rule abstains wholesale in such a file: a MISS there, never a report. Propagating const-ness through reads and re-bindings would be a new channel at every hop |
| `type T = { m(): this }` | TS2526 | The rule is writable, but `src/bridge` runs `check_module` over real `.d.ts` input, where a false positive costs GENERATION rather than a conformance file. No corpus file needs it; class-side and constructor-parameter positions ARE reported (batch EA) |
| `type F = ({ a: b = 1 }) => void` | TS2842 | The function-TYPE half reads TOKENS and must stop at the `=`, or an object literal inside a default (`{ a: b = { c: d } }`) reads as a pattern. The interface / object-type / class-member sites have a real `TsBinding` and DO report |
| `class D extends B { override [prop]() {} }` | TS4113 | A `const` string key is late-bindable, so `override [prop]()` is LEGAL when the base declares what `prop` resolves to. Only a base chain declaring NOTHING is decidable, and that ships; `override19`'s intersection base is §1e |
| `computedPropertyNames28` — `super()` in an object-literal computed key DIRECTLY in the constructor | TS2466 | tsc itself ACCEPTS the direct form and reports it only once an arrow or function expression intervenes; batch ET ships exactly that boundary (`30` is a TP now), and `28` is the cell tsc accepts |
| `class C<E, A> { m(this: C<never, A>) {} }` called on a `C<number, string>` | TS2684 | ACCEPTED by tsc: `E` is a phantom type parameter and TypeScript is structural. The plain-call and union-receiver forms of TS2684 DO report (batch ET) |
| `class C implements String {}` | TS2420 | Needs the merged lib member list; 173 lib interfaces are declared empty, so any "declares nothing" shortcut is unsound |
| `interface T {}` in two different function bodies | TS2300 | The block-local type merge registers a name only when it is declared ONCE across block scopes; guessing costs wrong member answers, abstaining costs a MISS |
| `using` / `await using` declarations | TS2850 / TS2851 and the for-of binding grammar | **Zero** of 5,697 real `.d.ts` / `.ts` files use them. Five files declared out of scope; the sixth (`usingDeclarationsWithObjectLiterals2`) was TS7018 on `value: null` and is a TP since batch EC |
| `switch (12) { case 5: }` on a `const` scrutinee | TS2678 | `infer_expr` widens a numeric literal to `number`; the literal-vs-literal syntactic form is reported (batch CW), a `const` scrutinee is not |
| `o.b` through an index signature only (`delete o["b"]` on `{ [k: string]: string }`) | — | LEGAL and silent for the stated reason: a member reached only through an index signature is not a declared property |
| `this` inside an object-literal `function` property | TS2339 | **MEASURED AND NOT TAKEN.** `this` there is the LITERAL's type, and binding it around the entries works — instrumented, the binding arrives as `{ n: number; f: () => any }` — but `check_funcexpr_with_context` then rebinds `this` to `Any`, deliberately and with its reason stated at the site (a parser-lowered nested class becomes a prototype-assigned function expression whose `this` is the inner instance). Undoing that needs the type threaded past it AND a `noImplicitThis` flag the checker does not carry: probed, `{ n: 101, f: function () { this.n.length } }` is TS2339 with the flag and ACCEPTED without it. Three pieces of plumbing for one conformance file (`looseThisTypeInFunctions`) |
| `{ [P in string]: P }` — a mapped type whose VALUE mentions the binder | — | The infinite-key reduction (batch EX) requires the value to be independent of the key, because a HOMOMORPHIC mapped type over `any` yields `any` and not a shape. Reporting it cost two TS7-accepted files before the guard existed |
| `A & B` assigned to `A` | — | LEGAL, and the reason the intersection-source rule (batch EY) is restricted to an index-signature target: `is_assignable_to` is resolver-free and cannot expand a `Named` target structurally, so the unrestricted version reported four legal shapes at the same +1 conformance file |
| a CONSTRUCT / CALL signature's own type parameters in an object type | — | Not carried. Wrapping them in `GenericFunc` cost a true positive outright (`genericCallWithOverloadedConstructorTypedArguments2`, all `new <T>(…)` members) and nothing reads them; the named-method binders that batch EV does carry are read at the call site |

## 4. Out of scope — 19 files

`scripts/checker_out_of_scope.txt` holds them, one path per line with a
kind (`removed-feature`, `malformed`, `lexer-adversarial`,
`resource-mgmt`, `no-local-oracle`, `lib-diagnostic`) and a reason. The
oracle reports a STALE entry the moment a listed file stops being a MISS,
which is the one mechanism that keeps the file from decaying into a
suppression list. Out of scope means "we will not add a rule for this
file", never "we may flag it wrongly": an FP on a listed file still counts
against the zero FP budget.

---

## 5. What this file used to list, and where it went

The previous revision (measured at MISS 80) had eight sections. Six are
closed and the residue of each is in §1 above; the ledger is here so the
history is not re-derived from TODO.md.

| former section | status |
|---|---|
| A. Type-level machinery (variadic, template literal, conditional-in-intersection, contextual typing from a union of signatures) | Three still open (§1b). **A-4 is CAUGHT** since batch EL: a function value against a UNION of call signatures with identical parameter lists gets the union of the returns as its contextual return type — `functionExpressionContextualTyping2` is a TP |
| B. Overload resolution | B-1 (TS2464 through a generic overload member) DONE in batch EB. **B-2 `neverIntersectionNotCallable` is a TP**: an intersection whose constituents give one property conflicting types reduces to `never` and is reported as not callable |
| C. Host / lib shapes | C-1 `globalThis` DONE in batch EB, including the ambient-module key in TYPE position (`globalThisAmbientModules` is a TP). C-2 (`interface Object` augmentation): `objectTypeHidingMembersOfExtendedObject` is a TP through the index-value rule (`data: A` against `[x: string]: Object`); its sibling is out of scope as `lib-diagnostic` |
| D. Narrowing and control flow | Still open (§1d) |
| E. Intersection comparability (TS2367) | DONE in batch EB |
| F. Enum member initializers (TS18033) | DONE: the destructured-binding source in batch EB, the block-scoped shadow (`enumShadowedInfinityNaN`) in batch ET, decided in the PARSER because the checker's env cannot see the block |
| G. "Blocked on a mechanical fact" (TS7031/7018, TS1308, TS2331, TS2708 `typeof`, TS2393) | All five DONE in batches EC and EE. Not one recorded blocker survived being probed: two had been dissolved by later unrelated work, one named only one of two routes to the fact, one was true of an approach nobody had to take, and TS2393's consumer had simply thrown the count away. The `import a = A` half of TS2708 is still open (§1g) |
| H. Declared abstentions | §3, with three rows retired (the `super`-in-computed-key row is now the exact tsc boundary, the aliased `this` and the class-method TS2684 rows are new) |

Batches EU–EZ then took five more files (MISS 50 -> 45) and none of them
was a machinery gap the classification could see, which is §6.3 once
more: an `import a = A` alias's TS2708 (the recorded blocker was true of
what the target MEANS and false of what it SPELLS), TS2403 inside a
FUNCTION scope plus the polymorphic `this`, a mapped type over an
infinite key set, an intersection against an index signature — the last
being exactly what batch EN measured as unreachable and recorded as
"finding what abstains first is the actual work" — and `callChain.3`.
Three of the six batches bought ZERO conformance files and are in §2
instead, and the round also fixed a SEGFAULT
(`types_definitely_differ` recursed with no depth bound; a
self-referential `typeof` ended the process, at HEAD, from the module
level) and three false positives on legal code the gate cannot see.

`callChain.3` is worth reading as a unit, because ONE conformance file
carried FOUR independent defects and the classification saw none of
them — it is filed under "object literals, contextual typing, widening",
which is not what any of the four is. The optional chain short-circuits
for the WHOLE chain and the parser puts only the guarded link inside the
`OptionalChain` node, so `g?.p.q`'s outer `.q` pruned the nullish
receiver and handed back a bare `number`. `m?<T>(x)` did not PARSE at
either member parser, because both read the type parameters before the
`?` where the grammar (`PropertyName ?opt CallSignature`) has it the
other way round — and the object-type parser's failure was total, so the
whole literal fell back to `Any` and every member of it became
unknowable. An OPTIONAL method is stored as `Union([callable,
Undefined])`, which every consumer matching the callable SHAPE read as
opaque. And `unwrap` PEELS a `GenericFunc` — it says so at the site —
so a generic member of a union callee reached `infer_call` with its
binders already gone. Each was found by probing the NEXT thing the
previous fix exposed, and only the four together move the file.

---

## 6. Keeping this file honest

1. **Probe the reason, not just the rule.** Batches DT, DU, DV, DW, EA,
   EC, EE, EK and EN each targeted a recorded abstention. In DT, DU, DV,
   EA, EC, EE and EK the stated reason turned out false or to name only
   one of two routes to the fact; DW and EN are the two whose reason
   probing CONFIRMED, with a number where there had been an argument. A
   comment declining a rule is a lead; its REASON is a claim with a date
   on it — and a blocker can be removed by a LATER batch that was not
   aiming at it, which is what happened to both of batch EC's rows.
2. **Pair every rule with its LEGAL neighbour.** "Fires on the corpus file"
   and "stays silent on the legal spelling" are separate claims, and only
   the second keeps FP at zero. `scripts/tsc_probe.mjs` answers the second
   one; the conformance oracle cannot, because no baseline covers a
   hand-written legal case. The twelve false positives fixed in batches
   EH, EM, EP–ET and EZ were all found this way or by a unit test, and
   none by the corpus. EZ's is the one to read: it was found while
   writing the legal neighbour for a DIFFERENT rule, and confirmed
   pre-existing by rebuilding the stashed tree rather than argued to be
   so.
3. **A rule can already exist.** Many of the 34 files that left this list
   between MISS 80 and MISS 45 needed no new machinery: a check wired into
   one of the places that produce a shape and not the others (`for-of`
   but not `yield*`; dotted access but not destructuring; the class base
   but not `declare class`; a `this` parameter dropped by four renderers
   and counted by two; TS2403 at module scope and in no function body).
   A machinery classification cannot see that kind, which is why §1 names
   the FILE and tsc's message rather than a feature.
4. **A capability is worth taking at zero files.** Three of batches
   EU–EY bought no conformance file each and are in §2: a generic METHOD
   call, an index-signature read through an anonymous object type, and
   the false positives fixed alongside them. The corpus cannot score
   them because it does not contain the shapes — which is the same
   sentence as §2's, and the reason both halves of this file exist.
