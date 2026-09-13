# What the checker does NOT flag

Every entry below was MINIMIZED and run through both `tscheck` and the real
compiler (`node scripts/tsc_probe.mjs`), so each one is a measured gap and
not a guess. Where `tscheck` reports something *different* from tsc, that is
stated — a file can be flagged for the wrong reason, and the conformance
oracle counts the file either way.

Measured at **TP 2637 / MISS in scope 78 / OUT OF SCOPE 19 / FP 0 /
PFLEGAL 0** (`just verify-checker-soundness`). The MISS number moves with
every batch; the SHAPES here move much more slowly, which is why this file
is organized by machinery rather than by error code.

Batch EF's file is not in any section below, and the reason is worth a
line here: nothing was missing. `YieldExpression10_es6` needed no
machinery at all — an object-literal method shorthand's name was being
treated as a BINDING by three separate consumers, so a bare reference to
that spelling resolved anywhere in the module. A MISS can be a rule the
checker already has, defeated by a fact the parser recorded with the
wrong meaning; that kind never appears in a machinery classification.

Batch EI's nineteen files are the strongest version of that observation
so far, and not one of them is in a section below. Thirteen were pure
grammar or declaration shape — a `const enum` initializer that evaluates
to `Infinity`, a `yield` in a generator's parameter list, a decorated
`this` parameter, `super` with type arguments, an assignment to a class or
enum or function, an `infer` outside an extends clause. Four were the
applied-in-some-places family: `<import-eq-root>` was recorded for the
DOTTED `import X = A.B` and not the single-segment spelling; a private
member reached by DESTRUCTURING had no check where the dotted access has
had one for years; `reaches_alias` treated a mapped type's SOURCE as a
structural barrier when computing its key set needs the alias resolved;
and TS2411's index-value arm required a CLASS where the corpus file
augments an INTERFACE. And two were an optionality PROXY still live at
two sites after batch EH fixed the third — `type_accepts_undefined`
standing in for "is this member optional", which answers yes for `any`,
so `class Bar { x }` accepted every source. The lesson this file exists
for holds: **a machinery classification cannot see a rule the checker
already has, applied in some of the places that produce it.**

Batch EG's six files are the same story four more times over, and none of
them is in a section below either. TS2488 existed and was wired into the
`for-of` source and not into `yield*`; TS18014 asked its question one
lexical level deep when a `#name` resolves outward through every
enclosing class body; TS1064's named half was an abstention whose own
header named the fix; and the decorator signature checks compared ARITY
and never a TYPE. The only genuinely absent machinery the batch found is
filed with its measured blocker rather than shipped — TS2490 needs to
tell `next() { return "" }` from `next(): any { return "" }`, and
`TsClassMethodDecl` keeps no annotation-presence field, the
absent-versus-`: any` gap this file records in section G.

Batch EH built that channel and took TS2490 with it, along with eight more
rules — and its more useful output is the **five false positives** it
fixed, none of which this file could have listed, because a false positive
is not a gap in what the checker knows. Two of them were CANCELLING: the
optional-chain result type added `| undefined` unconditionally, which made
a member lookup fail, which meant the array-predicate callback whose
declared return type was also wrong was never judged — so
`optionalChainingInArrow` scored as a correct TN with both bugs present.
The lesson generalizes past this file's subject: **what the checker gets
WRONG can be hidden by what it does not reach**, so the shapes worth
minimizing here are not only the silent ones.

Sections B, C, E and F were taken in batch EB — **+8 files at FP 0** — and
each keeps its entry with what shipped and what is still missing, because
the residue is the useful part. Batch EC then took two of section G's five
rows for **+3 files at FP 0**, and both had a blocker that a previous batch
had already removed without noticing.

## How to read this, and the one mistake to avoid

**Check WHERE tsc put the diagnostic before believing it is about this
file.** `scripts/lib/tsc-probe.mjs` used to call
`getSemanticDiagnostics()` with no argument, which returns every file's
diagnostics — so a 33-line test that augments `interface Object` under
`@skipDefaultLibCheck: false` was ranked by errors tsc raised inside
`lib.es5.d.ts`. It splits them now and `tsc_probe.mjs` prints the others
on their own line; exactly one MISS file turned out to have nothing in
scope at all.

`docs/checker-triage.md` classifies the backlog by the machinery a rule
needs. This file is the other half: the code a user would write.

**An error CODE is not a difficulty class and a bucket LABEL is not a work
item.** That substitution has been made and measured wrong eleven times in
this repo (see CLAUDE.md). Two live examples:

- TS2403 looks like a gap because four MISS files raise it. `var x: number;
  var x: string;` is **already flagged**. Those four files fail for four
  unrelated reasons.
- TS2411 likewise: `interface I { bar: number; [x: string]: string }` is
  **already flagged**. What is missing is narrower — see C-2.

So: before taking anything here, open the corpus file. The counts are the
count of files raising that code, not the yield of a rule.

---

## A. Type-level machinery (most of the remainder)

The four largest buckets are TS2322 (14 solo), TS2345 (10), TS2339 (7) and
TS2403 (4), and they are not one feature — they are these four plus a long
tail. 85 of the 132 codes measured before batch EB had exactly one file
each, and the four bucket sizes above are from that same run.

### A-1. Variadic tuples — `types/tuple/variadicTuples3.ts`

```ts
function f<T extends any[], P extends any[]>(): [...T, ...P] {
  let x: [any, any] = [null, null];
  return x;   // tsc: TS2322 "Source provides no match for variadic element at position 0"
}
```

`[...T, ...P]` has an unknown length, so matching it against a concrete
tuple needs spread-element matching. Assignability compares `Tuple` element
by element and abstains here.

### A-2. Template-literal types with a placeholder — `types/literal/templateLiteralTypes4.ts`, `7.ts`

```ts
interface NMap { 1: "A"; 2: "B" }
declare const g: <T extends 1 | 2>(x: `${T}`) => NMap[T];
type G = <T extends 1 | 2 | 3>(x: `${T}`) => NMap[T];
const g2: G = g;   // tsc: TS2322 ("3" is not assignable to "1" | "2")
```

`` `${T}` `` has to distribute over `T`'s constraint and produce
`"1" | "2"`. `TemplateLiteralType` is parsed and carried, never evaluated
against a type parameter.

### A-3. Conditional type inside an intersection — `types/conditional/conditionalTypesExcessProperties.ts`

```ts
type Something<T> = { test: string } & (T extends object ? { arg: T } : { arg?: undefined });
function f<A extends object>(a: A, sa: Something<A>) {
  sa = { test: "bye", arg: a, arr: a };   // tsc: TS2322 (arr is excess)
}
```

Batches DI–DM made a conditional resolve through a generic alias; one left
unresolved *inside an intersection* still cannot be projected to a field
shape, so the excess-property check never gets a target.

### A-4. Contextual typing from a union of signatures — `expressions/contextualTyping/functionExpressionContextualTyping2.ts`

```ts
var a0: (n: number, s: string) => number;
var a1: typeof a0 | ((n: number, s: string) => string);
a1 = (foo, bar) => { return true; };   // tsc: TS2322 (boolean is not number)
```

The rule TypeScript applies is written in that file's own header: if every
member of the union has one non-generic call signature and they agree on
parameters, the contextual signature is those parameters with a union of
the return types. Not implemented, so `foo` / `bar` stay untyped and the
return is never compared.

---

## B. Overload resolution — PARTLY DONE (batch EB, +2)

`docs/checker-triage.md` Tier 1 lists this. What shipped is the piece
these two files needed; general overload resolution is still not a thing.

### B-1. A computed key from an overloaded call (TS2464) — DONE

```ts
function f(s: string): string;
function f(n: number): number;
function f<T>(x: T): T;
function f(x): any { }
var v = { [f(true)]: 0 };   // tsc: TS2464 (a computed key must be string | number | symbol | any)
```

Only the third signature accepts `true`, so the key is `boolean`.

**What was actually broken was narrower than "overload resolution".** The
overload members are ingested as a Union of `Func`s and `infer_call`
already picks the one whose parameters accept the arguments — but every
declaration's type parameters are recorded per NAME in
`func_type_params`, which is OVERWRITTEN per declaration, so for this set
it holds the IMPLEMENTATION's list and that is empty. The generic member
therefore reached the union arm as `Func([Named("T")], Named("T"))`,
matched nothing, and the call came back carrying an unresolved `T`.
`func_overload_type_params` (the union across a name's declarations) plus
`infer_generic_overload_call` instantiate it, tried only after every
non-generic member has failed — which is also TypeScript's order, so a
call a concrete overload accepts keeps the answer it already had.

### B-2. STILL MISSING: `never` from an intersection is not callable (TS2349) — `types/never/neverIntersectionNotCallable.ts`

Not the same machinery after all: it needs intersection REDUCTION to
`never`, which is section E's problem rather than this one's.

`es6/Symbols/symbolProperty3.ts` also raises TS2464 and is **REJECTED with
evidence** rather than waiting on this: it writes `var s = Symbol;
({ [s]: 0 })`, `s` infers as `Any`, and catching it needs the `Symbol`
constructor modelled as a value type. Nobody writes that.

---

## C. Host / lib shapes — PARTLY DONE (batch EB, +3)

### C-1. `globalThis` and the script-level `this` (TS2339) — DONE for `es2019/globalThisReadonlyProperties.ts` and `es6/arrowFunction/emitArrowFunctionThisCapturing{,ES6}.ts`

```ts
namespace namespaceModule { export type typ = 1 }
type Bad = (typeof globalThis)["namespaceModule"];   // tsc: TS2339
```

```ts
var x = 1
const y = 2
globalThis.x = 3   // legal — `var` creates a global property
globalThis.y = 4   // tsc: TS2339 — `const` does not
```

```ts
// @strict: false
var f1 = () => { this.age = 10 };   // ACCEPTED — a new global property may be created
var f2 = (x: string) => { this.name = x };   // tsc: TS2339 on `typeof globalThis`
```

`globalThis`'s member set is exactly the script's `var` / `function` /
`class` / `enum` / instantiated-namespace declarations plus the lib
globals — `let` / `const` and a type-only namespace are not members — and
at script top level `this` IS `typeof globalThis`, including inside an
arrow.

Three things shipped, and two of them are findings rather than features.
The READ form (`var r = globalThis.y`) was all the existing rule judged:
the WRITE form was missed at BOTH of its spellings, because
`globalThis.y = 4` at the top of a list is a `PropAssign` STATEMENT and
the same line inside a function is `Expr(PropAssignExpr(…))`, and both
arms walked the RECEIVER and the VALUE while the property NAME sat in the
node itself, tested by neither. A top-level `function f() { … }` body was
not reached at all, for the parser reason batch DS records. And `this`
gets its own region-scoped walk rather than a flag threaded through that
one, because the two questions have different regions: `globalThis.x`
means the same in any body, `this` means the global object only where
nothing has rebound it — an arrow keeps it, a `function` does not (tsc
reports TS2683 there instead).

`this.name` is an error and `this.zzz` is not, which reasoning gets
backwards: an undeclared property may be CREATED through `this` at script
scope, while `name` is `declare const name: void` in the DOM lib and a
block-scoped lib global is not a `globalThis` property either.
`is_lib_dom_blockscoped_value` is generated from the lib sources for that
— one name today — and is DOM-scoped rather than unioned because
`webworker.generated.d.ts` declares the same name with `var`; the rule
abstains when an explicit `@lib:` list leaves dom out.

**STILL MISSING** — `es2019/globalThisAmbientModules.ts`: the key is in a
TYPE position and is a quoted ambient-module name.

```ts
declare module "ambientModule" { export var val: number }
type Bad = (typeof globalThis)["\"ambientModule\""];   // tsc: TS2339
```

An `IndexedAccess` on `typeof globalThis` reaches no name check, and the
declared-globals set would have to be complete in TYPE position for firing
there to be sound.

### C-2. The members `Object` itself declares (TS2411) — `types/members/objectTypeWithStringIndexerHidingObjectIndexer.ts`, `types/members/objectTypeHidingMembersOfExtendedObject.ts`

```ts
interface Object { [x: string]: Object }
// tsc: TS2411 x4 — hasOwnProperty / isPrototypeOf / propertyIsEnumerable / toLocaleString
```

The index-signature conflict check works on an ordinary interface. What is
missing is enumerating what `lib.es5.d.ts` declares on `Object` when the
program AUGMENTS it.

---

## D. Narrowing and control flow

### D-1. Aliased control flow (TS18046) — `controlFlow/controlFlowAliasingCatchVariables.ts`

```ts
try { } catch (e) {
  const isString = typeof e === "string";
  e = 1;
  if (isString) { e.length; }   // tsc: TS18046 — the alias was invalidated
}
```

Batch CS's TS18046 correctly withdraws on a `typeof e === "string"`
narrowing in the same block. Following an ALIASED guard, and invalidating
it on assignment, needs a flow graph. The fail direction is a FALSE
POSITIVE (claiming un-narrowed where it is narrowed), which is the one the
budget forbids — so this is deliberately last.

`||`-right-operand narrowing (`typeGuardsInRightOperandOfOrOrOperator`) is
**already handled** at the common shape: `typeof x !== "string" ||
x.length` stays silent and `typeof x === "string" || x.length` fires.

---

## E. Intersection comparability — DONE (batch EB, +2)

### E-1. `===` between intersections with no overlap (TS2367) — DONE

```ts
interface I1 { p1: number }
interface I2 extends I1 { p2: number }
interface I3 { p3: number }
declare const y: I1 & I3;
declare const z: I2;
if (y === z) { }   // tsc: TS2367 — 'I1 & I3' and 'I2' have no overlap
```

```ts
function f<T>(x: T & number) {
  if (x === "abc") { }   // tsc: TS2367 — 'T & number' and 'string' have no overlap
}
```

Comparability is assignability in EITHER direction, and an intersection has
to be flattened to a member set (or to its primitive part) before either
can be decided. Both halves turned out to exist already, in the wrong
place:

- `cast_shape_fields` + "each side requires a property the other lacks" is
  the test the `as` path (TS2352) has used for
  `typeAssertionsWithIntersectionTypes01` all along; the equality arms
  never asked. It is `shapes_definitely_disjoint` now and both call it.
  `==` gets it too, restricted to object shapes: `==` coerces a primitive
  against an object (`{} == "[object Object]"` is true) but object against
  object is reference equality, where `===`'s answer holds.
- `equality_primitive_family` gained an `Intersection` arm, because every
  value of `T & number` is a number whatever `T` is. `Any` / `Unknown` /
  `Never` in a part abstains outright — `any & number` IS `any`, so
  answering "number" there would report a comparison tsc accepts.

---

## F. Enum member initializers — PARTLY DONE (batch EB, +1)

### F-1. The initializer's type is not numeric (TS18033) — DONE for `enums/enumErrorOnConstantBindingWithInitializer.ts`

```ts
type Thing = { value?: string | number };
declare const thing: Thing;
const { value = "123" } = thing;
enum E { test = value }   // tsc: TS18033 — 'string | number' is not assignable to 'number'
```

```ts
{
  let Infinity = {};
  enum En { X = Infinity }   // tsc: TS18033 — '{}' is not assignable to 'number'
}
```

Two different sources for one rule, and the first one's blocker was NOT
the type: the checker already infers `string | number` for that
destructuring and `{}` for the block-local — measured, not assumed. What
was missing is that the enum AST keeps folded literal values only, so the
initializer EXPRESSION never reaches the checker. A
`<enum-init-name:NAME>` marker carries the one shape worth deciding (a
bare identifier) and the checker looks the binding up in the top-level
env, which is where a DESTRUCTURED binding lives — `resolver.globals`
records only `Var(Ident(n), ty, _)` shapes.

The definitely-non-numeric set excludes LITERAL types, which is the cell
reasoning gets wrong: `declare const s: string` is TS18033 while
`const s = "a"` — type `"a"` — is **ACCEPTED**, because a string literal
initializer is how a string enum member is written. `Infinity` / `NaN` /
`any` / a sibling member all abstain by not resolving.

**STILL MISSING** — `enums/enumShadowedInfinityNaN.ts`, and the reason is
SCOPE rather than type: its `let Infinity = {}` sits in a block with the
enum, and an enum is hoisted into `module_.enums` with no record of the
block it came from, so the binding that shadows the lib global is not in
the top-level env. Reaching it needs the block's own env, which means
running during the statement walk — and an enum is not a statement.

---

## G. Blocked on a mechanical fact, not on the rule

Each of these has a probed, exact boundary and a named blocker.

**ALL FIVE are DONE — batch EC took two (+3 files) and batch EE the last
three (+2 files), both at FP 0 — and the lesson is about this table rather
than about any of the rules: a blocker written down here is a claim with a
date on it, and not one of the five survived being probed.** Two had
already been dissolved by earlier work that was not aiming at them, one
was mechanically true but named only one of two routes to the fact, one
was true of an approach nobody had to take, and one — TS2393's — was not a
blocker at all: the marker it needed was being pushed once per
implementation the whole time and the consumer built a SET, which threw
the count away. TS7031 / TS7018 needed a
`strict_null_checks` field on the Parser, which is nine lines, and the
annotation fact was already there as `last_var_decl_annotated` — read by
`parse_var_decl_item` before the initializer is parsed, for exactly this
reason. TS2331's blocker ("a new Parser field needs the save / clear /
restore discipline `self.labels` needs at fifteen function-body sites") was
true of the approach it considered and was dissolved by batch EB, which
built the region-scoped `this` walk for the `globalThis` rule one batch
earlier — an arrow is descended into, a `function` body and a class body
are not, which IS TS2331's region. The member-DECORATOR spelling needed a
different mechanism and got one that was also already there: a namespace
body is parsed by a fresh `Parser` that cannot know it is one, so the class
parser leaves a sentinel and `parse_namespace_decl_with_mode` converts it,
the same way TS1063 / TS1319 already work.

| Shape | tsc | Blocker |
|---|---|---|
| ~~`var [a, b] = [undefined, null]` / `const o = { value: null }`~~ | TS7031 / TS7018 | **DONE (batch EC).** The annotation fact was `last_var_decl_annotated`, already read at `parse_var_decl_item`; the Parser gained `strict_null_checks`, and both flags being required is what keeps the rule off real code — a directive-less file defaults to `strictNullChecks: true`, so no `.ts` / `.d.ts` the bridge parses can reach it. Still MISSes, each losing a finding: a REST element, a `satisfies`, `null!`, a computed key, and every non-declaration position (a `return`, a class field, a call argument — where the literal is CONTEXTUALLY typed and legal, which is why the rule is restricted to declarations). |
| ~~`function fn(v: Promise<number>) { class C { async m(@dec(await v) a: number) {} } }`~~ | TS1308 | **DONE (batch EE).** `skip_param_decorators` really does discard the expression, and a TOKEN sighting over the range that skip consumes needs no AST — every `await` must spell `await`, so the scan is complete by construction. The region is the ENCLOSING function's async-ness, not the method's: the same class body is TS1308 under `function fn`, `function* fn` and a plain arrow, and ACCEPTED under `async function` and an async arrow. `in_function` is required because module / script top level is TS1375 / TS1378, two codes this rule does not claim. |
| ~~`namespace M { const f = () => this }`~~ | TS2331 | **DONE (batch EC).** Batch EB's `this_region_walk_stmt` is the region, so the rule is a second `ThisRegionVisitor` over the same walk; a class DECORATOR came along (`module_.classes[].decorators`, never `local_classes` — a class in a function is decorated in that function's scope and tsc gives TS2683). The member-decorator spelling rides a parser sentinel because member decorator expressions never reach the AST. Still a MISS: `typeof this.no` in a TYPE position, which is what `typeofThis.ts` writes — `parse_typeof_type_query` has no `This` arm, so the operand is skipped and the annotation collapses to `Any`. |
| ~~`namespace C { var m: typeof A }`~~ (A type-only) | TS2708 | **PARTLY DONE (batch EE).** The `typeof` TYPE position is wired now — `var m: typeof A`, `type T = typeof A`, `var m: typeof A.P` (the base SEGMENT is what matters) and the namespace-nested form all report, while a namespace carrying a runtime `export var` is ACCEPTED. It needs no `env` guard, unlike the value path: the sweep reads only module- and namespace-level declaration types, never a function body, so a local shadow cannot reach it. `importStatementsInterfaces` is STILL a MISS and this is the honest half of the row: its `var m: typeof a` goes through an `import a = A` alias, and whether such an alias binds a value depends on the TARGET, which is not resolved at parse time. |
| ~~`function d(a: number) {…}` `function d(a: string) {…}`~~ | TS2393 | **DONE (batch EE).** There was no blocker: the `<fn-impl:NAME>` marker is pushed once per IMPLEMENTATION and the consumer built a `Map[String, Unit]`, so the COUNT the rule needs was thrown away at the point of use. Counting instead gives TS2393, reported BEFORE the overload rules and taking the name out of them — the two shapes are mutually exclusive, and "this overload signature is not compatible with its implementation signature" was the wrong sentence for a name with two implementations. The marker also had to be added at the FOUR export sites, which had none, so `export default function f() { }` twice — `multipleDefaultExports04` — recorded no implementation at all. |

---

## H. Declared abstentions — not bugs

| Shape | tsc | Why we stay silent |
|---|---|---|
| `type T = { m(): this }` | TS2526 | The rule is writable, but `src/bridge` runs `check_module` over real `.d.ts` input, where a false positive costs code GENERATION rather than a conformance file. No corpus file needs it. |
| `type F = ({ a: b = 1 }) => void` | TS2842 | The function-TYPE half reads TOKENS and must stop at the `=`, or an object literal inside a default (`{ a: b = { c: d } }`) reads as a pattern. The interface / object-type / class-member sites have a real `TsBinding` and DO report this. |
| `class C { [prop]() {} }` with `override` | TS4113 | A `const` string key is late-bindable, so `override [prop]()` is LEGAL when the base declares what `prop` resolves to. Only a base chain declaring NOTHING is decidable, and that is what ships. |
| `computedPropertyNames28` / `30` (`super` in an object-literal computed key) | TS2466 | Modelling the distinction ONE corpus file draws is fitting the corpus: three TS7-ACCEPTED files say an object-literal computed key may legally mention `super`, and the earlier attempt cost 6 false positives for 2 true ones. |
| `using` / `await using` declarations | various | **Zero** of 5,697 real `.d.ts` / `.ts` files use them. Six MISS files; declared Tier 4. |
| `i[k]` where `interface I { [k]: number }` and `declare const k: unique symbol` | TS2322 | The KEY must resolve to the member the type declares, and the parser stores a user symbol key as `<computed>` — it has no stable identity. A NAME-keyed identity would claim two same-spelled bindings in different scopes are one member, which is a false positive. The WELL-KNOWN spelling (`i[Symbol.iterator]`) does resolve, because the parser gives it a stable `@@<name>`; batch EJ wired that half. |
| a template-literal type with a placeholder, against a literal | TS2322 | Still BLIND, the one row of `docs/checker-triage.md`'s capability table that no batch has closed (see A-2). Needs the placeholder matched against the source literal's text, which nothing models. |
| `Extract<1 \| "a", 1>` | TS2322 | `Exclude` / `Extract` decide over a literal union of ONE kind and abstain over a mixed one. Found by re-probing the capability table in batch EJ rather than by a corpus file, and narrower than the retired `utility types` BLIND row implied. |

`scripts/checker_out_of_scope.txt` holds the 19 paths declared out of
scope, each with a kind and a reason. That file reports STALE entries, so
it cannot decay into a suppression list.

---

## Keeping this file honest

Two rules, both learned the hard way:

1. **Probe the reason, not just the rule.** Seven batches in a row (DT,
   DU, DV, DW, EA, EC, EE) targeted a recorded abstention, and in six of
   them the stated reason turned out false or to name only one of two
   routes to the fact. Section G's five rows are the sharpest version:
   every one of them is closed now, and not one blocker survived contact. A comment declining a rule is a lead; its REASON is a claim to be
   measured — and a blocker can also be removed by a LATER batch that was
   not aiming at it, which is what happened to both of batch EC's rows.
2. **Pair every rule with its LEGAL neighbour.** "Fires on the corpus file"
   and "stays silent on the legal spelling" are separate claims, and only
   the second keeps FP at zero. `scripts/tsc_probe.mjs` answers the second
   one; the conformance oracle cannot, because no baseline covers a
   hand-written legal case.
