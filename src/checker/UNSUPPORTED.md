# What the checker does NOT flag

Measured on 2026-09-16 at HEAD (`99f8c08`):

```
TP  err+flag  : 2665   (of which via parse rejection: 390)
MISS in scope : 50     (the backlog — this one can reach zero)
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

## Regenerating this file

```sh
moon build --target native --release
bash scripts/checker_conformance_oracle.sh --miss-list /tmp/miss.txt   # the numbers + the 50 paths
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

## 1. The 50 in-scope MISS files, by machinery

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

### 1b. Type-level machinery — 7 files

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
| `types/mapped/mappedTypeWithAny` | TS2322, TS2339, TS2740 | a homomorphic mapped type over `any` yields `any`, not a shape — so `Objectish<any>` must not satisfy `any[]` |
| `types/conditional/conditionalTypesExcessProperties` | TS2322 | a conditional left UNRESOLVED inside an intersection cannot be projected to a field shape, so the excess-property check has no target. Batches DI–DM made a conditional resolve through a generic alias; the composition with `&` still abstains |
| `types/conditional/inferTypesInvalidExtendsDeclaration` | TS2304 | **REJECTED after instrumenting** (batch EI): the type parser REDUCES `T extends infer A extends B ? …` when it can decide the relation, so the checker receives the bare `Number` and neither `A` nor its bound `B` survives to be resolved |

### 1c. Object literals, contextual typing, widening — 10 files

| file | tsc | what is needed |
|---|---|---|
| `expressions/objectLiterals/objectLiteralNormalization` | TS2322 | normalize `{a} \| {a, b} \| {a, b, c}` on widening so `{ b: "x" }` is rejected against it |
| `expressions/contextualTyping/objectLiteralContextualTyping` | TS2403 | the inferred type of `bar({})` with `bar<T>(param: { x?: T }): T` must be `unknown`, and a redeclaration `var b: {}` must conflict with it |
| `types/spread/spreadUnion2` | TS2403 | spreading a UNION produces a union of object types, not one object with optional members |
| `expressions/propertyAccess/propertyAccessWidening` | TS2339, TS7053 | `(options \|\| {}).a` widens to `{ a: string } \| {}` and the access must fail on the `{}` member |
| `types/union/unionTypeWithIndexSignature` | TS2339, TS2540, TS7053 | member resolution on a union where one member is an index signature (`{ foo: number } \| { [s: string]: string }`) |
| `expressions/contextualTyping/taggedTemplateContextualTyping2` | TS2345 | a tagged template's substitutions checked against the tag function's parameter types |
| `expressions/contextualTyping/superCallParameterContextualTyping2` | TS2349 | the parameter of an arrow passed to `super(...)` typed contextually from the base constructor, so `new Number()` inside it is not callable |
| `expressions/optionalChaining/callChain/callChain.3` | TS2322 | an optional CALL chain (`a?.m?.(…)`) whose receiver is nullable yields `T \| undefined`. Batch EH removed the unconditional `\| undefined` on a non-nullable receiver; the nullable-receiver call form is what remains |
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

### 1e. Classes, `this`, mixins — 8 files

| file | tsc | what is needed |
|---|---|---|
| `classes/mixinAbstractClasses.2` | TS2797, TS2515, TS2511 | a class extending a TYPE VARIABLE with an abstract construct signature (`T & typeof AbstractBase`) must itself be `abstract`; needs the intersection base's construct signatures |
| `classes/mixinAccessors3` | TS2611 | TS2611 through a mixin intersection base (`Mixin & BaseClass`); the direct-base spelling is already flagged |
| `override/override19` | TS4113, TS4117 | `override` against an INTERSECTION base `A & { context: Context }`; the class-base version ships, gated on "the base chain declares NOTHING" (see §3) |
| `expressions/thisKeyword/typeOfThisGeneral` | TS2403 | the polymorphic `this` type of a `var t = this` inside a method, so a redeclaration `var t: MyTestClass` conflicts |
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

### 1g. Name resolution and declarations — 5 files

| file | tsc | what is needed |
|---|---|---|
| `types/localTypes/localTypes4` | TS2304, TS2300 | a block-local `interface T` declared in two different functions. **Deliberately unregistered** (batch ET): the block-local type merge must not pick a winner among several declarations of one name — its first draft made the empty `interface T { }` in one function answer for the other and the gate scored that as a TP because the file errors for unrelated reasons |
| `internalModules/codeGeneration/importStatementsInterfaces` | TS2708 | `var m: typeof a` through an `import a = A` alias: whether the alias binds a VALUE depends on the target, which the parser does not resolve. The direct `typeof A` type position shipped in batch EE |
| `es6/Symbols/symbolProperty3` | TS2464 | **REJECTED with evidence**: `var s = Symbol; ({ [s]: 0 })` — `s` infers as `Any`, and catching it needs the `Symbol` CONSTRUCTOR modelled as a value type. Nobody writes that |
| `types/intersection/intersectionWithIndexSignatures` | TS2322, TS2339 | an INTERSECTION source against an index-signature target. Batch EN measured that the arm which would decide it is never reached for an intersection-typed VALUE — something above it abstains first — so dropping the unsound "some component alone satisfies" fallback changed nothing and was reverted with the number |
| `decorators/class/decoratorChecksFunctionBodies` | TS2345 | the BODY of an arrow written inline as a member decorator (`@((x, p, d) => { func(3) })`). Member decorator expressions never reach the AST (`skip_param_decorators` / the class-body decorator skip); batches EE and EG read what they need off the skipped TOKENS, which cannot type-check a body |

---

## 2. Capability probe — the common shape of each feature

The classification above says what a FILE needs. This says what the
checker HAS, probed at the shape real code writes (inside a function
body, `--strict` where the rule needs it). Re-probed on 2026-09-16;
every row is a real tsc error, so a BLIND row is a measured gap.

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
| **strictNullChecks on a member-chain receiver** (`o.a.b` with `a?:`) | **BLIND — deliberate**: the check is gated to a bare `Var` receiver because those are the bindings the narrowing engine rewrites precisely (batch DO) |
| **index-signature read through an ANONYMOUS object type** (`o["x"]` / `o[0]` on `{ [k: string]: number }`) | **BLIND** — the write and the literal-assignment directions are caught; the read yields no type |
| **index-signature write of the wrong type** (`o["x"] = "s"` on `{ [k: string]: number }`) | **BLIND** |
| **variadic tuple** (`[...T]`, `[string, ...number[]]`) | **BLIND** |
| **template-literal type with a placeholder** (`` `${T}-x` `` against `"c-x"`) | **BLIND** |
| **computed `unique symbol` key** (`interface I { [k]: number }`, `i[k]` against `string`) | **BLIND** |

Two of the BLIND rows (the anonymous index-signature read and write) are
not in any conformance file and were found only by this probe — the same
lesson the false-positive rounds keep teaching: the corpus does not
contain the shapes, so FP 0 and MISS 50 are statements about 4,484 files
and not about real code (batch EO measured zod at 272 diagnostics with tsc
accepting all of them; 187 remain after the shadowing fix).

---

## 3. Declared abstentions — rule known, deliberately silent

Each entry names the LEGAL neighbour that decides it. None is a bug.

| shape | tsc | why we stay silent |
|---|---|---|
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
   hand-written legal case. The eleven false positives fixed in batches
   EH, EM and EP–ET were all found this way or by a unit test, and none
   by the corpus.
3. **A rule can already exist.** Many of the 30 files that left this list
   between MISS 80 and MISS 50 needed no new machinery: a check wired into
   one of the places that produce a shape and not the others (`for-of`
   but not `yield*`; dotted access but not destructuring; the class base
   but not `declare class`; a `this` parameter dropped by four renderers
   and counted by two). A machinery classification cannot see that kind,
   which is why §1 names the FILE and tsc's message rather than a feature.
