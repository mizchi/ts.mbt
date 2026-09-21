# TODO

The wasm interpreter / codegen / AOT compiler that originally lived in this
repo has been removed. Items below are scoped to the bridge generator only.

### Batch FH (2026-09-20): back to the MISS axis — a declaration space nobody owned

`TP 2670 -> 2671 | MISS in scope 45 -> **44** | OUT OF SCOPE 19 | FP 0 |
PFLEGAL 0 | TN 1750`, and byte-identical on real code: `typescript.d.ts`,
preact, vitest and hono all stay at 0, zod stays at 108, and a 3,982-file
`mtsc check` sweep over every `.d.ts` under `node_modules` plus effect's
sources reports **16,635 on both binaries with no file differing**.

The first batch in this series aimed back at the CONFORMANCE backlog
rather than at real-package false positives, and the target was a filed
abstention with a stated scope rather than a ranking. Batch CA's
`let x; let x` rule named its four uncovered shapes in writing, and one of
them is "local TYPE declarations" — `localTypes4`, which is still a MISS.

**The rule.** A callable's TYPE PARAMETERS and the TYPE declarations at
the top level of its own body are one declaration space, so

    function f<T>() { interface T { } }

is TS2300 and tsc reports it on both. No type information anywhere: the
parser has the type-parameter list and the body's own declarations at the
same moment.

**Thirty-three cells were probed against 6.0.3 before anything was
written, and three of them decided the design.**

1. `enum T { }` is **TS2567** ("enum declarations can only merge with
   namespace or other enum declarations"), a different error this rule
   does not claim, so the enum arm is deliberately absent — `interface`,
   a `type` alias and a `class` are the three that participate. A
   `namespace` in a function body is TS1235 before the question is even
   reachable.

2. `class L<T> { m() { interface T { } } }` is **LEGAL**. A class's own
   type parameters do NOT share the space with a method body's local
   type, which is why only the METHOD's list is passed at that site. A
   rule written from "the enclosing generic declaration" would have been
   a false positive on every generic class with a local type in a method.

3. `function f<T>(cb = () => { interface T { } }) { }` is **LEGAL**, and
   it is the cell that rules out the cheap implementation. Setting a
   "pending type parameters" field inside
   `parse_type_param_names_bounds_and_const_flags` and consuming it in
   `parse_block` is one site instead of six — and a parameter DEFAULT can
   hold a body, which would have consumed the field and reported this.
   The fact is therefore read at the BODY site, immediately after that
   body's own `parse_block()`, in the shape `last_function_bodiless`
   already uses.

**Fail direction.** `parse_block` keeps one frame per block (beside the
`block_binding_nonnumeric` frame it already pushes and pops at the same
single exit) and stashes it into `last_block_local_type_names` on the way
out. A callable site that does not ask takes a MISS; there is no ambient
field to go stale, so a missed site cannot invent a finding. That is also
what makes every nested-scope neighbour legal by CONSTRUCTION rather than
by a condition: a nested block, a nested function's body, a `try`, a
`for`, a bare `{ }` each have their own frame, and a VALUE binding of the
same name (`let T`, `const T`, `var T`, `function T`, a parameter `T`) is
never recorded in one.

Six sites, and two of them DISCARD the list they need. A generic arrow's
`<T>` is in no AST node at all and an object-literal method's goes
through `skip_type_params`, so both read `type_param_names_ahead` — the
walk extracted from `record_type_param_names_ahead`, which batch EP wrote
for exactly these two positions. One walk with two consumers rather than
a second copy of it.

Not covered, and stated rather than left to be discovered: the file's
other error is TS2304 for a type declared in a body being referenced from
that same function's SIGNATURE (`function f(x: T): T { interface T { } }`).
That needs the name to be absent from every outer scope and from the lib,
which is `unresolved_type_references` — rejected three times in this
series with a measured cause. The file flips on the TS2300 half alone.

### Batch FG (2026-09-20): `typescript.d.ts` to ZERO

`TP 2670 | MISS in scope 45 | OUT OF SCOPE 19 | FP 0 | PFLEGAL 0 |
TN 1750` — corpus-NEUTRAL. The last diagnostic on the biggest declaration
file in the ecosystem, and **88 -> 0** across FC, FD, FF and FG.

Three more shapes the nominal reach could not express, and all three come
from ONE declaration — `type EndOfFileToken =
Token<SyntaxKind.EndOfFileToken> & JSDocContainer`, the eighteenth arm of
the 64-member `HasJSDoc` union that `JSDoc.parent` is typed as.

**How it was found matters more than the rule.** Four guesses at the
cause were each refuted by a probe that reproduced clean (a recursive
alias union, an alias-in-alias union, an optional member, a two-level
nest). BISECTING the real union settled it in seven runs: patch
`parent: HasJSDoc` to a subset of the arms in a copy of the 4 MB file,
halve, repeat.

1. **A CLASS in the union.** `named_iface_extends_reaches` read
   `resolver.interfaces` alone, and batch FC filed the class case as a
   MISS. It is a REPORT rather than a MISS, because the caller requires
   EVERY union member to be accepted, so one unprovable member keeps the
   whole diagnostic — a distinction worth recording, since "this costs a
   MISS" was written in good faith and was wrong about its own direction.
   Measured pre-existing on every binary back to before this batch
   series. A class reaches an interface through `implements` and another
   class through `extends`.

2. **An INTERSECTION member.** An intersection is a subtype of each of
   its components, so reaching the base through ANY one is enough — the
   opposite quantifier from the union, which is why it is not folded into
   the flattening batch FF added.

3. **An `Applied(n, _)` reaching an ancestor by NAME**, which is sound
   only when the base member is NON-GENERIC: `interface Token<K> extends
   Node` makes every instantiation a `Node` whatever `K` is, while
   `Token<A>` against `Token<B>` depends on the arguments. So the generic
   spelling is admitted on the DERIVED side only, and only against a bare
   name — the `Token<string>` / `Token<number>` pair still reports,
   probed.

Measured: **`typescript.d.ts` 1 -> 0**, the 4,085-file sweep unchanged at
16,647 with 0 added, zod unchanged at 108, the oracle identical, all 12
scaling axes within budget.

Ten cells probed and all ten agree with tsc. Accepted: a class in the
union; an intersection with one reaching component; a generic against a
bare base member; and the `EndOfFileToken` shape itself (a generic AND an
intersection at once). Rejected: an intersection none of whose components
reaches; a generic whose NAME does not reach; a GENERIC base member with
mismatched arguments; a class implementing nothing relevant.

### Batch FF (2026-09-20): the last two TS2430 shapes — `typescript.d.ts` to 1

`TP 2670 | MISS in scope 45 | OUT OF SCOPE 19 | FP 0 | PFLEGAL 0 |
TN 1750` — corpus-NEUTRAL. Two more causes behind the rule batch FC took,
found by opening the five `typescript.d.ts` had left.

**1. `parts` split ONE level and `unwrap_containers` expands in place.**
`HeritageClause.parent: InterfaceDeclaration | ClassLikeDeclaration`,
where `ClassLikeDeclaration` is itself a union alias, arrived as a union
whose second member is a UNION — opaque to every `Named` test, so no arm
of it could be matched against the base. A union of unions is the same
union; it is flattened now, bounded at 8 levels (running out keeps the
member unsplit, a MISS rather than an invented accept).

**2. The SIBLING TS2430 rule never got the nominal disjunct**, and the
walk it needed was already defined in its own function. That rule — the
one whose message reads "property `X` of type `T` is not assignable to
the base type `B`" — decides through `struct_assignable_named_rec`, which
cannot recover a relation where the base carries a BRAND the derived only
INHERITS: `SuperExpression extends PrimaryExpression extends
MemberExpression extends LeftHandSideExpression`, and only the last
declares `_leftHandSideExpressionBrand`. `typescript.d.ts` writes that
three times and tsc accepts the file.

`named_reaches` sits thirty lines above the comparison, and was consulted
only for the RETURN-type check. It is a **THIRD copy** of the same BFS —
batch FC hoisted one out of `tuple_covariant_by_extends` into
`named_iface_extends_reaches`, and this one is keyed on a local
`iface_by_name` rather than `resolver.interfaces`. Left as it is and
recorded rather than unified: the two maps may not hold the same thing,
and establishing that they answer the same question is its own
measurement. Using the copy that is already there changes nothing about
which table this rule reads.

Measured: **`typescript.d.ts` 7 -> 1** (88 -> 1 across FC, FD and FF —
the one left is `JSDoc.parent`), the 4,085-file sweep 16,648 -> 16,647
with 0 added, zod unchanged at 108, the oracle identical, all 12 scaling
axes within budget.

Nine cells probed and all nine agree with tsc. Accepted: a derived union
whose member is a union ALIAS; a base member's brand inherited three
levels up; the same through an optional member. Rejected: a nominally
unrelated pair; the chain walked the WRONG WAY; a scalar over an
object-shaped base member; a nested union none of whose members reaches
the base.

### Batch FE (2026-09-20): a namespace may re-export a file-level import, ZERO files

`TP 2670 | MISS in scope 45 | OUT OF SCOPE 19 | FP 0 | PFLEGAL 0 |
TN 1750` — corpus-NEUTRAL. The other family batch FC's re-ranking left on
the real path, and the smallest fix of the four.

```ts
import { A, B } from './chunks/browser.js';
declare namespace Experimental {
	export { A, B };          // TS2661 "only local declarations can be exported"
}
```

vitest's `index.d.ts` does that six times and tsc accepts the file. It is
the standard `.d.ts` grouping idiom.

`check_non_local_exports` ALREADY consults `imported_binding_names` — it
was written to, with a `Map` built for the scan cost — but a NAMESPACE
body is its own `TsModule` and the `import` sits at the FILE's top level,
so that list is empty one scope in. The outer chain was already threaded
down for other reasons (`next_outers`), so the fix is to read it.

What made the gap look like a working rule is the SIBLING case: a name
DECLARED at file level and re-exported from a namespace was always
silent, because the resolver's tables span the whole chain already. Only
the imported half was module-local, so the rule was right for three of
its four inputs.

Measured: **vitest 6 -> 0**, the 4,085-file sweep 16,688 -> **16,648**
with 0 added, the oracle identical, all 12 scaling axes within budget.
Three of the four real `.d.ts` entries now report ZERO
(`preact`, `vitest`, `hono`); `typescript.d.ts` is at 7, all of them
TS2430 shapes our assignability still cannot follow
(`SuperExpression` against `LeftHandSideExpression`, and
`JsonMinusNumericLiteral.operand`).

Eight cells probed. The accepts are the vitest shape at one level and
nested, a file-level declaration re-exported from a namespace, and a
default import; the rejects are a name neither imported nor declared, at
top level and inside a namespace, and a mixed clause where only one name
resolves. One difference from tsc is pre-existing and recorded rather
than fixed: it reports TS2304 ("Cannot find name") where we report
TS2661 — a different code for the same rejected program.

### Batch FD (2026-09-20): a declaration file is ambient — 1,193 false positives, ZERO files

`TP 2670 | MISS in scope 45 | OUT OF SCOPE 19 | FP 0 | PFLEGAL 0 |
TN 1750` — corpus-NEUTRAL again, which is the sanity check that matters
here: the conformance corpus has no `.d.ts` at all, so an unchanged
oracle says the exemption really is keyed on the FILE and not a weakened
rule.

The family batch FC ranked and filed. A declaration file makes every
declaration in it ambient whether or not it writes `declare`, and four
bodiless-declaration rules did not know that:

```ts
// a .d.ts — tsc accepts this outright
export class C {
  constructor(m: number);   // TS2390 "constructor implementation is missing"
  blen: number;             // TS2564 "has no initializer"
  get t(): string;          // TS2378 "a get accessor must return a value"
  m(x: number): void;       // TS2391 "function implementation is missing"
}
```

**The cause is that `in_ambient_module` is a WHOLE-PARSE mode nothing
sets for a FILE.** Only a `declare module "spec" { … }` body and
`global { … }` ever turn it on; `Parser::parse_module` — the entry every
`.d.ts` goes through — passes `false`. Five of its six gates name `.d.ts`
in their own comments and one says so literally ("Ambient mode (`.d.ts` /
ambient external module body) treats every `export var/let/const X;`
without initializer as type-only"). The ambient exemption each rule
already has is keyed on the `declare` KEYWORD, and a declaration FILE is
the other spelling of the same fact — so `export class C` there goes
through the RUNTIME class parser and sets every sentinel.

**A SECOND Parser field, not a flip of the existing one**, and that is
the whole design decision. Exactly one rule needs the old question alone:
TS1038 fires for `declare namespace M { declare function f(); }` and NOT
for a `.d.ts` file's own top-level `declare function f(): void` — which
is how every declaration file in existence is written. Probed against
6.0.3, and we already agreed with tsc on both cells. Flipping the
whole-parse flag would have false-positived on all of them.

Scope, stated rather than left to be discovered. The new field is read by
the four DIAGNOSTIC gates and nothing else. It is deliberately NOT read
by `is_ambient_export_value_decl`, which decides whether `export var X;`
emits a runtime binding: that is an AST question the bridge and the
transform passes consume, not a diagnostic, and widening it is a separate
change with its own measurement.

Three mechanical facts the implementation needed:

1. **A namespace body re-parses with a fresh `Parser`**, so the fact — a
   property of the SOURCE — has to be carried across, or the rules go
   back to reporting one level in. `typescript.d.ts` is where that shows:
   its remaining false positives were all on
   `namespace ts > namespace server > class Project`.
2. **The three CHECKER-side rules cannot see an extension.**
   `check_dts_top_level_modifiers` states that blocker in its own comment
   ("keyed off the file extension, which the general check pipeline can't
   see"), so the parse pushes a `<declaration-file>` marker, with a skip
   entry in the grammar-misuse loop — a marker without one IS a
   diagnostic, which TS4111's flag marker did once.
3. **`--noEmit` does not go through the graph loader for a single file.**
   It calls `mtsc_typecheck_source` -> `collect_type_issues`, which takes
   `(source, allow_jsx)` and no path. Found by INSTRUMENTING rather than
   reading: the first wiring touched `parse_graph_module`, and a `println`
   there produced NO output on the `--noEmit` path at all. The fact rides
   a labelled argument with a default, so the JavaScript ABI and every
   existing caller are unchanged.

Measured: **preact 4 -> 0** (all four of its diagnostics), `typescript.d.ts`
15 -> **7** (and 88 -> 7 across FC and FD), the 4,085-file `mtsc check`
sweep 17,881 -> **16,688** with **0 added**, zod unchanged at 108 (it is
`.ts` source), the oracle identical on every metric, and all 12 scaling
axes within budget.

Every source in the new test is asserted BOTH ways — 0 as a `.d.ts` and
`> 0` as a `.ts` — which is what proves the exemption is keyed on the
file, plus the TS1038 pair that keeps the two fields separate.

NOT wired, with the reason: `src/bridge`'s two parse sites
(`typescript_decl.mbt`, `moonbit_decl.mbt`). The bridge runs
`check_module` over real `.d.ts` input, so it would benefit, but a parser
change that moves what the GENERATOR sees needs its own measurement —
`verify-generated-fixtures` / `verify-scaffolds` / `verify-examples` are
all byte-identical under this batch precisely because those sites were
left alone.

### Batch FC (2026-09-20): TS2430 on a real `.d.ts` — 80 false positives, ZERO files

`TP 2670 | MISS in scope 45 | OUT OF SCOPE 19 | FP 0 | PFLEGAL 0 |
TN 1750` — corpus-NEUTRAL again. Found by pointing batch FB's real-package
axis at the LARGEST real input there is.

`node_modules/typescript/lib/typescript.d.ts` is the biggest declaration
file in the ecosystem and tsc accepts it outright, so every one of the **88
diagnostics `mtsc --noEmit` reported on it was a false positive** — and
**80 were one rule**, `check_interface_extends_member_compat` (TS2430).
Two independent causes, both of them this file's recurring shapes.

**1. `resolver.unwrap` where `unwrap_containers` was needed.**
`is_assignable_to` is the RESOLVER-FREE entry point and `unwrap` peels the
OUTERMOST type only, so a base member typed as an alias to a union
(`type U = A | B; interface P { name?: U }`) arrived as
`Union([Named("U"), Undefined])` — the union is outermost, `U` was never
resolved, and `Named("A")` against `Named("U")` is nominal. The guards
directly above had already proven both sides RESOLVABLE with
`type_contains_unresolved_named`; nothing resolved them.
`unwrap_containers` is the helper written for exactly this hazard and says
so in its own header ("the resolver-free `is_assignable_to` can't resolve
a `Named` it finds nested inside `Array` / `Tuple` / `Rest`"), with `Union`
in its fast-path list. Applied to both sides. 80 -> 29.

**2. A NOMINAL `extends` relation, which structure cannot recover.**
`interface Node { readonly parent: Node }` beside
`interface CaseBlock extends Node { readonly parent: SwitchStatement }` is
legal, and `SwitchStatement` reaches `Node` only through `Statement` — a
relation the structural comparison cannot follow when the whole hierarchy
is mutually recursive and `Node` is declaration-merged. The walk for that
question ALREADY EXISTED as a local `fn` inside
`tuple_covariant_by_extends`; it is HOISTED to
`named_iface_extends_reaches` and both callers share it, since a second
walk is how two answers to one question come to disagree. The new
disjunct is SUFFICIENT and never necessary — every member of the derived
type must be accepted by some member of the base's, so it can only ever
ACCEPT and a shape it cannot decide falls through to the report exactly as
before. 29 -> 7.

**3. The last cell needed batch EM's `Named` / `Struct` split.**
`unwrap_containers` expands an interface reference it CAN resolve into
`Struct(name, …)` and leaves one it cannot as `Named(name)`, so
`parent: N | Q` expanded its members while the bare `parent: N` did not —
a `Named`-only match worked for the bare pair and failed for the union.
Matching either spelling closes it.

Measured: `typescript.d.ts` **88 -> 15**, zod **113 -> 108** (five more
false positives, zero added), the 4,085-file `mtsc check` sweep
17,885 -> 17,881 with **0 added**, the oracle IDENTICAL on every metric,
and the `interfaces` axis still 1.00 — the new BFS sits behind three
failed checks, so it almost never runs.

Eight legal-neighbour cells probed against 6.0.3 and all eight agree: the
aliased-union subset, a one- and a three-level `extends` chain and
reaching one arm of a union base member are ACCEPTED, while a non-arm of
the aliased union, a nominally unrelated pair, the chain walked the WRONG
WAY (a base member may not be narrowed to its own supertype), a union
whose arms are all unreachable, and ordinary primitive / literal
incompatibility all still report.

**The batch's other output is a correction to its own first ranking**, the
eleventh instance here of a count standing in for the objective and the
first where the substituted count was a HARNESS's unit rather than a
label. Grouping batch FB's sweep by message shape put an "ambient
declaration file" family on top at **1,192** occurrences — `mtsc check`
reports TS2390 / TS2391 / TS2564 / TS2378 on a `.d.ts`, where every member
is bodiless by construction. That is real: `in_ambient_module` is a
WHOLE-PARSE mode that only `declare module "spec" { … }` and `global { … }`
bodies ever set, `Parser::parse_module` passes `false`, and five of its
six gates name `.d.ts` in their own comments (one says "Ambient mode
(`.d.ts` / ambient external module body)" literally). It is NOT the
ranking it looked like: the sweep's unit is (file, diagnostic) over 3,723
mostly tiny hand-written `.d.ts` shims, and on the path a user runs,
`typescript.d.ts` yields **8** of that family against 80 of TS2430.

Filed with what a fix needs, so it is not attempted as a one-line flag
flip. The sixth gate is TS1038, where flipping the whole-parse flag would
be WRONG and would false-positive on essentially every `.d.ts` in
existence: `declare function f(): void` at a declaration file's top level
is legal, only the NESTED spelling
(`declare namespace M { declare function inner(): void }`) is the error —
probed, and we already agree with tsc on both. So it needs a SECOND
Parser field ("this is a declaration FILE") beside the existing one
("we are inside a `declare X { }` body"), which are two different
questions; the five bodiless gates test the disjunction and TS1038 keeps
testing the original. The three checker-side rules (TS2390, TS2564,
TS2378) need the fact too, and `check_dts_top_level_modifiers` states that
blocker in its own comment: "keyed off the file extension, which the
general check pipeline can't see". A module-level marker pushed by the
parse is the channel; the parse entry has to learn the extension from its
caller, and 17 call sites construct a Parser.

### Batch FB (2026-09-20): a `string` source against a literal target, ZERO files

`TP 2670 | MISS in scope 45 | OUT OF SCOPE 19 | FP 0 | PFLEGAL 0 |
TN 1750` — corpus-NEUTRAL, identical to the batch before it. Measured on
REAL packages instead: **zod 118 -> 113 diagnostics** (five false
positives on legal code removed, none added), and byte-identical over a
4,085-file sweep of every `.d.ts` under `node_modules` plus effect's 362
`.ts` sources.

The gap was `UNSUPPORTED.md` §3's widest row: `declare const s: string;
const a: "other" = s` and four siblings were all silent, which is the
commonest real TS2322 / TS2345 there is — every options-string and
discriminated-union API produces it.

**1. The gate is ONE abstention and its stated reason had a date on it.**
`check_expr_against` suppresses any mismatch whose source is exactly the
primitive base of the target's literals, because "TypeScript keeps the
const literal narrow" where we widen. Probed one base at a time against
the shipping binary, that is true for NUMBER, BOOLEAN and BIGINT and
false for STRING: `infer_expr` erases the first three at the source
(`NumberLit(_) => Number`) and keeps `Literal(s)`. So `const c = "z";
const c2: "a" | "b" = c` already reported while the `string`-source form
never could. Fifteen string spellings were probed before the arm came
out — a template literal, an `as` assertion, a call returning a literal,
a narrowed union member, a string enum member, an annotated `const`, a
generic call — and every one that tsc keeps narrow, we keep narrow.

**2. The ONE divergence is an erased `as const`**, and the parser says so
in its own comment: `parse_asserted_relational` drops the wrapper because
the transform passes want the raw expression, so `{ k: "a" } as const`
arrives as the plain object literal whose property genuinely does widen
to `string` here. A file carrying one abstains wholesale, through a new
file-level `<const-assertion>` marker read in `Resolver::ingest_module`
(not beside the other directive flags at the check entry, which sees only
the ROOT module's markers — a namespace body re-parses with a fresh
Parser). That costs MISSes in such a file and invents nothing; the
alternative, propagating const-ness through reads and re-bindings, is a
new channel at every hop.

**3. The relaxation EXPOSED a latent false positive rather than creating
one, and that is the batch's most valuable half.** A mutable binding's
fresh literal initializer widens in tsc (`let s = "a"` is `string`,
`const s = "a"` is `"a"`) and did not here, because only the COMPOSITE
half of that rule had been written — an object / array / tuple literal's
contents widened and a scalar did not. Invisible while no `string` source
could be judged against a literal target, and five reports on legal lines
the moment one could: zod's `bg.ts` has `let invalid_adj = "Невалиден"`
reassigned five times. Fixed at the binding site through one helper both
binding paths call, with `Let` and `Const` split apart in the dispatch
(they shared an arm).

**4. The corpus caught the first version of that fix**, which is the
legal-neighbour lesson again. Widening every literal a mutable binding
holds is too wide: TypeScript widens only a FRESH literal type, so in
`let a: "foo" = "foo"; let b = a || "foo"; let c: "foo" = b` — a
conformance file — `a`'s literal came from an annotation, is not fresh,
and neither is the `||` over it, so tsc ACCEPTS `c`. The test is on the
INITIALIZER's syntax now, and an unclassified spelling keeps the narrow
type (a MISS, never a report). A TEST then caught the second version: a
template literal with a constant substitution folds to a literal here
(batch AU, for TS2367) while tsc calls it `string` outright, and a
pre-existing parity pin requires ``var x = `a${0}` `` to behave exactly
like `var x = "a0"` — so a template counts as fresh whether or not it carries
substitutions.

**5. One test was asserting the gap**, the fourteenth found doing that
here: `function f(x: "a" | "b") {} declare const s: string; f(s)`
asserted 0 under a comment calling it an over-widening guard, and the
real compiler gives TS2345 (probed).

**6. A sixth false positive came out of probing the same neighbours**,
and it was pre-existing and one line deep. `widen_literal_deep`'s union
arm mapped its members and did not DEDUP them, so `["a", "b"]`'s widened
element type was `string | string` — a message nobody can act on, and
not equal to the `base` the const-widening abstention tests, so
`const arr = ["a", "b"] as const; const y: "a" = arr[0]` reported on a
line tsc ACCEPTS even in an `as const` file. Measured against the
baseline binary before and after: corpus-neutral, sweep-neutral,
zod-neutral, and the non-`as const` neighbour (`const arr = ["x", "y"]`,
which tsc types `string[]`) still reports.

What did NOT ship, with the reason rather than a verdict: the numeric /
boolean / bigint half, which needs `infer_expr` to stop erasing those
literals at the source — a change at every consumer of a numeric
literal's type, not a gate.

### Batch FA (2026-09-18): a late-bound `unique symbol` member key, ZERO files

`TP 2670 | MISS in scope 45 | OUT OF SCOPE 19 | FP 0 | PFLEGAL 0 |
TN 1750` — corpus-NEUTRAL by design.

`unique symbol` is **183 occurrences across 3,000 real `.d.ts` files**,
the third commonest feature in `docs/checker-triage.md`'s real-code
column, and it was the top BLIND row of `UNSUPPORTED.md` §2 with no
conformance file anywhere. That ranking is the batch: the corpus count
alone puts it last. Three defects and two false positives on legal code.

**1. The ANONYMOUS spelling did not PARSE.**
`try_parse_object_type_with_members`'s bracket arm falls back for
anything that is not an index signature, so `{ [k]: number; plain:
number }` came out `Any` and EVERY member of it was lost — not just the
computed one. Same shape as batch EZ's `m?<T>`: one member spelling takes
the whole type literal down with it. The fall-back is LOAD-BEARING for a
mapped type (`[K in keyof T]` reaches the same arm and must reach its own
parser downstream), so the fix is a positive shape test — exactly
`[ Ident ]`, where a mapped type has an `in` follower and a dotted key a
`.` — rather than a widened fallback, which would have broken one feature
to fix another.

**2. The INTERFACE spelling named the member `<computed>`**, a name no
lookup can ever match, while the sibling WELL-KNOWN spelling twenty lines
above has had a stable `@@name` for a long time. One question, two
answers. Both now record `@@unique:<k>`.

**3. Nothing translated the index EXPRESSION back**, so `i[k]` was `Any`
even once the member had a name. `late_bound_index_member_name` is wired
at BOTH `infer_index` arms — the `Named`/`Applied` one and the anonymous
`Object` one — because writing it at one is exactly how the two spellings
came to disagree in the first place. It gates on the index's TYPE being a
`unique symbol`, so a plain `symbol`, a string key or any other binding
spelled `k` does not reach it.

**The false positives are pre-existing and were found by probing a legal
neighbour.** A computed key can also be a string-literal `const` —
`const kk = "hello"; interface I { [kk]: number }` — which tsc names
`hello` and which neither member parser can evaluate, the value living in
another declaration. Reading the undecidable name as "this shape has no
member called `hello`" reported `i.hello` on a line tsc ACCEPTS.
**Confirmed pre-existing by stashing the branch and rebuilding HEAD**:
the `<computed>` half predates the `@@unique:` name entirely. The
abstention goes in `member_recv_unmodeled`, beside the index-signature
one it already makes for the same reason — a member might be present
without being listed. A WELL-KNOWN key is excluded because it IS decided
statically, and that exclusion is measured rather than asserted: `w.nope`
on an `@@iterator`-carrying interface still reports, matching tsc. The
price is that a genuinely absent property of a late-bound-key interface
stops being reported, which is the affordable direction and cost no TP.

**The one approximation, stated rather than hidden.** tsc keys a
late-bound member by SYMBOL; this keys it by spelling, so two
`unique symbol` bindings sharing a name across scopes resolve to one
member. That costs a wrong member rather than a report on legal code,
since tsc calls the same program TS2339.

Declared MISSes, each probed: the CLASS spelling (`class C { [k]: number }`,
`c[k]`) is untouched — `class_key_name` has its own naming and a class
computed key may legally be an arbitrary expression; `i[s2]` over a plain
`symbol` and `i["k"]` are TS7053, a code this rule does not claim; and
`i.nope` on a late-bound-key interface is the cost of the abstention
above.

Gates: `moon fmt --check`, `moon check --deny-warn` (native and `js`),
`moon info`, every `*_wbtest.mbt` file individually (2,854 tests), the
oracle, `verify-checker-scaling` (12 axes in budget),
`verify-generated-fixtures`, `verify-scaffolds`, `verify-examples`,
`verify-bridge-runtime` (14,630 converter calls, 0 failures),
`verify-bridge-enum-returns`, `verify-mangle-safety` (186/186),
`verify-dce-coverage` (31 eliminated / 0 broken), `verify-graph-walk`,
`verify-language-service` (22/22), `verify-cli-node` (21/21).

### Batch EZ (2026-09-18): MISS in scope 46 -> 45 at FP 0

`TP 2669 -> 2670 | MISS in scope 46 -> 45 | OUT OF SCOPE 19 | FP 0 |
PFLEGAL 0 | TN 1750`

One conformance file (`callChain.3`) carrying FOUR independent defects,
plus a false positive on legal code the corpus structurally cannot see.
The file is filed in the triage under "object literals, contextual
typing, widening", which is not what any of the four is — a reminder that
the classification says what a file LOOKS like from its diagnostic, not
what it needs. Each defect was found by probing the next thing the
previous fix exposed, and only the four together move the file.

**1. An optional chain's result, one link past the guard.** The chain
short-circuits for the WHOLE chain, and the parser puts only the guarded
link inside the `OptionalChain` node — `g?.p.q` is
`PropAccess(OptionalChain(PropAccess(g, p)), q)` — so the outer `.q`
pruned the nullish receiver and handed back a bare `number` where tsc
says `number | undefined`. Propagated one level, off the chain node's own
RESULT (`type_has_undefined`) rather than by re-deciding its guard: that
arm has already made the decision, and a second copy of it is how the two
halves come to disagree. `is_nullable_type` is emphatically NOT the
predicate — it answers "is this type ENTIRELY nullish", so
`{ q: number } | undefined`, the exact shape a short-circuiting chain
produces, reads as false there and the first draft fired on nothing.
Gated on the receiver being SYNTACTICALLY the chain node, which keeps the
cost flat: one extra sub-inference at the one link per chain, where a
"does the spine contain a `?.`" walk would be O(d²) on a member chain,
the shape `verify-checker-scaling` exists to catch. Only ONE level —
`w?.p.q.r` loses it at `.r`, because reading a nullish TYPE as evidence
of a chain would widen every unguarded access too.

**2. `m?<T>(x)` did not PARSE.** The grammar is
`PropertyName ?opt CallSignature` and a CallSignature BEGINS with its
type parameter list, so the `?` comes first. Both member parsers read the
binders first, at two sites with one order — the applied-in-some-places
family with the axis being a token ORDER rather than a site. The
object-type parser's failure was TOTAL: the `<` was still the next token
when the method arm tested for `(`, nothing else matched, and the whole
literal fell back to `Any`, so every member of it became unknowable and
not just the generic one. `m<T>?(x)` is not TypeScript, so the swap loses
no spelling.

**3. An OPTIONAL method is `Union([callable, Undefined])`.** The parser
wraps `a?: T` into `T | undefined` and a method signature is no
different, so every consumer matching the callable SHAPE read the member
as opaque and `declare const a: { m?(n: number): number }; a.m?.(1)` came
back `Any`. `lookup_callable_field` removes the nullish wrapper for the
two callers that ask "what CALLABLE is this member"
(`lookup_method_sig`, `method_type_params_of`); every other consumer
keeps the union, since that is what makes `a.m` itself
possibly-undefined. It returns `None` unless exactly ONE non-nullish
member remains, so a genuine union of two callables — an overload set —
keeps going to the overload path rather than having an arm picked for it.

**4. `unwrap` PEELS a `GenericFunc`.** It says so at the site (the
wrapper "erases to its underlying callable for every value-shape
decision"), and that erasure also throws away the binders a call has to
SOLVE — so a generic member of a union callee reached `infer_call`'s
union loop as a bare `Func` and `c?.m({ x: 12 })` came back with `T`
unsolved, where the same member reached directly is solved by the
`GenericFunc` arm ten lines above. One question, two answers. Generic
members are set aside and instantiated only after every concrete one has
failed — TypeScript's own overload order, and the discipline batch EB's
`func_overload_type_params` already uses.

**The false positive: an INTERFACE's overload set was invisible.**
`method_overload_signatures` had arms for a class, an `Object` type
literal and a `Struct` — the three shapes that are NOT how a `.d.ts`
declares overloads. With no candidates, two things went wrong at once:
`resolve_method_overload` fell through to `lookup_method_sig`, whose own
comment says it surfaces only the FIRST declaration, so
`interface O { m(x: string): number; m(x: number): string }` with
`p.m(1)` came back `number`; and the argument check's abstention (batch
EL's, which exists for exactly this) is gated on `> 1` candidate, so it
judged the call against overload #1 and reported
`expected string but got number` on a line tsc ACCEPTS. **Confirmed
pre-existing by stashing the branch and rebuilding HEAD**, not argued to
be. Corpus-NEUTRAL when fixed — no TP lost, no FP gained — which is the
ideal shape for a real-code fix the gate cannot score. Consulted only
when the CLASS lookup found nothing, since a class and an interface of
one name are a declaration merge and double-counting is the one direction
that can turn a single signature into a fake overload set and silence the
argument check.

**One more, found the same way.** The IndexAccess arm passed its receiver
to `infer_index` raw, where the PropAccess arm has pruned a nullable
receiver and retried for a long time with its own comment saying why — so
`u?.a[0]` came back `Any` while `u?.a.length` resolved. Retried only when
the direct answer is `Any` and the receiver really is a union carrying a
nullish member, so nothing that already decides can change.

Two things NOT taken, with their reasons. `a.m(1)` on an optional method
is TS2722 in tsc ("cannot invoke an object which is possibly undefined")
and stays a MISS: a different code, and the call now types correctly.
`w?.p.q.r` loses the `| undefined` two links past the guard, per (1).

Gates: `moon fmt --check`, `moon check --deny-warn` (native and `js`),
`moon info`, every `*_wbtest.mbt` file individually (2,853 tests across
checker / parser / bridge / mtsc / transform), the oracle,
`verify-checker-scaling` (12 axes in budget), `verify-generated-fixtures`,
`verify-scaffolds`, `verify-examples`, `verify-mbti-dts`,
`verify-bridge-runtime` (14,630 converter calls, 0 failures),
`verify-bridge-enum-returns`, `verify-mangle-safety` (186/186),
`verify-dce-coverage` (31 eliminated / 0 broken), `verify-graph-walk`,
`verify-language-service` (22/22), `verify-cli-node` (21/21).
`--max-miss` lowered to 45.

### Batches EU-EY (2026-09-18): MISS in scope 50 -> 46 at FP 0

`TP 2665 -> 2669 | MISS in scope 50 -> 46 | OUT OF SCOPE 19 | FP 0 |
PFLEGAL 0 | TN 1750`

Four conformance files, three capabilities the corpus cannot score, two
false positives on legal code, and a SEGFAULT. Five batches; three of
them bought zero files each and were taken for the capability, which is
what this tier looks like.

**EU — TS2708 through an alias, TS2403 in a function scope, and a crash.**
The `import a = A` blocker was recorded as "whether the alias binds a
value depends on the TARGET, which is not resolved at parse time" — true
of what the target MEANS and false of what it SPELLS, and the spelling is
all the rule needs, since an alias binds a value exactly when its target
does. Its other half was `namespace_is_instantiated` counting a nested
namespace's own value entry, which `parse_namespace_decl_with_mode`
builds before it has parsed the body. **A test in the SILENT list said
in its own comment that tsc reports TS2708 there** — the fourteenth test
in this repo found asserting a gap rather than a behaviour.

TS2403 had run over `module_.top_level_stmts` and nowhere else, so
`function f() { var b: number; var b: string }` was silent, and so was
every class method, constructor, arrow and function expression. The
identity comparison is extracted and shared rather than copied; `var` is
function-scoped, so a nested block / `if` arm / `for` head / `switch`
case / `try` block are one group and a nested function is not.
Parameters participate as they do in tsc, a DESTRUCTURED one does not
(`p.name` is only the pattern's first name while `p.type_` is the whole
pattern's type). The polymorphic `this` then falls out of one more fact
and flips `typeOfThisGeneral`.

The crash is the batch's most useful output and predates it:
`types_definitely_differ` recurses on types `unwrap` has already
resolved, with no depth bound, so a self-referential `typeof` closes the
loop and `witness.ts` ended the process. **Measured by stashing the
branch, rebuilding HEAD and running the module-level spelling**, not
assumed.

**EV — generic METHOD inference (zero files).** A generic FUNCTION's type
arguments have been inferred at the call site for as long as
`infer_call` existed; a generic METHOD's never were. FOUR spellings were
involved and each lost the binder its own way: an interface and a class
record it on the declaration and no call site read it; a member written
as a function TYPE carries it on the `GenericFunc` wrapper that
`lookup_method_sig` had no arm for (eighth fail-open wrapper arm in the
ledger, and it made the member OPAQUE rather than merely
un-instantiated); `infer_call` had the same hole; and an inline object
type's method signature threw the binders away in the parser under a
comment saying so. A CONSTRUCT / CALL signature's binders are NOT
carried — wrapping them cost a true positive outright
(`genericCallWithOverloadedConstructorTypedArguments2`).

Its false positive was found by probing the legal neighbour of that
work: `x?.(args)` has no receiver — what the `?.` guards is the
CALLEE — so it took the "shape this cannot read" default and was widened
unconditionally, and `declare const c: (n: number) => number; const r:
number = c?.(1)` is ACCEPTED by tsc. Batch EH fixed the same false
positive at the three chain forms that DO have a receiver.

**EW — index-signature reads through an anonymous object type (zero
files).** `infer_index`'s `Named` / `Applied` arm has resolved the read
for a long time and the anonymous spelling had no arm at all; neither did
`collect_index_sigs`. One of the two BLIND rows the capability probe
found by asking the common shape rather than the corpus. The other one,
the WRITE, turns out **not to be blind at all** and had been handled in
all four spellings — a table nobody re-measures ranks the wrong work.

**EX — a mapped type over an infinite key set (+1).** `{ [P in string]:
V }` IS `{ [k: string]: V }`, and so is the `keyof any` spelling, but
neither evaluator could ENUMERATE that key set so the type stayed
unresolved and read as unmodelled. The guard cost TWO false positives
first: a HOMOMORPHIC mapped type over `any` yields `any` and not a
shape, and the first attempt to test "does the value depend on the key"
was defeated by a SHAPE rather than an argument — `type_references_any`
has no `IndexedAccess` arm, so `Box<T[P]>` reads through it as
independent of `P`.

**EY — an intersection against an index signature (+1).**
`check_expr_against` carried `(Intersection(_), _) => return` under a
comment saying the modelling was "too coarse", and the abstention was
TOTAL: an intersection-typed value was invisible in every assignment
against every target. **That is what batch EN went looking for and could
not find** — it measured the merge arm as unreachable and wrote that
finding what abstains first "is the actual work". Restricted to an
index-signature target, and the restriction is measured rather than
cautious: the unrestricted version is the same +1 file and FOUR false
positives on hand-written legal code (`A & B` into `A` among them),
because `is_assignable_to` is resolver-free and cannot expand a `Named`
target structurally — which is what "too coarse" actually meant.

REJECTED with its blockers: `this` inside an object-literal `function`
property (`looseThisTypeInFunctions`). Binding it around the entries
works and was instrumented — the binding arrives as `{ n: number; f: ()
=> any }` — but `check_funcexpr_with_context` then rebinds `this` to
`Any`, deliberately, with its reason at the site (a parser-lowered
nested class becomes a prototype-assigned function expression whose
`this` is the inner instance). Undoing it needs the type threaded past
that AND a `noImplicitThis` flag the checker does not carry: probed, the
shape is TS2339 with the flag and ACCEPTED without it.

Also rejected: `typeof x === "object"` narrowing `unknown` to
`object | null` (`controlFlowTypeofObject`).
`typeof_string_to_type` maps `"object"` to `Any`, and changing it is not
enough — the same file's legal neighbours need `if (!x) return` and
`if (x === null) return` to narrow `unknown` too, which our engine does
not do, so the narrow rule alone is two false positives in the file it
would flip.

The gate is tightened to `--max-miss 46`, and the four documents are
re-measured rather than edited: `UNSUPPORTED.md` §1 lists 46 by
machinery, §2 is re-probed one file per row, §3 gains four declared
abstentions with their numbers.

### Docs round (2026-09-16): the checker gap documents re-measured at MISS 50

No checker change. `TP 2665 / MISS in scope 50 / OUT OF SCOPE 19 / FP 0 /
PFLEGAL 0 / TN 1750`, re-run on a fresh checkout, and the four documents
describing the backlog were between one and thirty files behind it.

- `src/checker/UNSUPPORTED.md` was measured at MISS 80 and kept eight
  sections, six of them closed. Re-probing every snippet against
  `tscheck` and tsc 6.0.3 found four documented "still missing" shapes
  that are CAUGHT now and were never marked: contextual typing from a
  union of call signatures (batch EL), `never` from a conflicting
  intersection is not callable, the `globalThis` ambient-module key in a
  TYPE position, and TS18033 through a block-scoped shadow (batch ET).
  It now lists all 50 in-scope MISS files by machinery with tsc's own
  diagnostic, keeps the declared abstentions with their legal neighbour,
  and carries a one-table ledger of where the old sections went.
- The capability probe (formerly in the triage doc) was re-run at the
  common shape and moved beside the shapes it measures. Five rows were
  wrong in the old table: conditional-via-generic-alias, the utility
  table and overload selection read BLIND and are CAUGHT; "strictNullChecks
  (`o.a` where `a?:`)" and "index signature value type" read CAUGHT and are
  BLIND at the spelling written there — the strict-null check is gated to a
  bare `Var` receiver (batch DO, deliberate), and an index-signature READ
  through an ANONYMOUS object type yields no type at all while the
  interface spelling, the literal-assignment direction and the write are
  handled or measured. The two anonymous-index-signature rows are in no
  conformance file.
- `docs/checker-triage.md` still opened with "MISS 176" and a Tier 1 that
  batches DI–DM and EB had emptied. Every remaining family is Tier 3 now
  and the document says so, with the six files carrying a recorded
  rejection named so they are not re-attacked as written.
- `justfile`'s `--max-miss` was 80 against a measured 50; tightened, and
  the gate passes at 50. `README.md` and `docs/tsacc.md` linked the RETIRED
  `docs/checker-priority.md` as the place to read about priorities; both
  point at the two live documents now. `docs/mtsc.md`'s compatibility
  snapshot was the 2026-07-28 `tsacc` table (recall 719/815) — re-measured
  at 771/815 and placed under the TS7 oracle numbers, with the note that
  its "false positives" are against TS6 baselines and not the FP 0 the gate
  measures.

One toolchain observation, not acted on: `moon 0.1.20260915` (what the
installer hands out today) reports two `unused_package` warnings in
`src/cmd/tscheck/moon.pkg` (`moonbitlang/core/string`, `mizchi/ts/ast`)
during `moon build`, where CLAUDE.md records `moon check --deny-warn`
clean on `0.1.20260904` — so the gate is toolchain-version-sensitive and
the two imports are worth removing when the toolchain is next bumped.

### Batches EP-ET (2026-09-15): MISS in scope 58 -> 50, the target, at FP 0

`TP 2657 -> 2665 | MISS in scope 58 -> 50 | OUT OF SCOPE 19 | FP 0 |
PFLEGAL 0 | TN 1750`

Eight rules and **four false positives on legal code the conformance gate
structurally cannot see**, every one found by probing a legal neighbour.

**Rules that shipped**

| code | shape | note |
|---|---|---|
| TS2322 | a function value against an INDEX SIGNATURE | probed: `{}`, `Object`, `Function`, `{ call }`, `{ length }`, `{ name }` all ACCEPT a function; the general rule needs a complete `Function` member list, the indexer half needs nothing |
| TS2307 | an import TYPE's specifier past the declaration-bundle abstention | that abstention is about a bundle's import STATEMENTS; `import("fo")` beside `declare module "foo"` is a typo either way |
| TS2466 | `super()` in an OBJECT-LITERAL computed key, once a function boundary intervenes | `crossed` is a walk PARAMETER, not the Parser field the earlier note filed |
| TS2684 | the `this` CONTEXT of a call — a plain call, and a union receiver | two facts the type cannot carry, so a marker; eight cells probed |
| TS2362/2363 | a closure cannot rely on a narrowing a reassignment outlives | the filed fact ("assigned anywhere") was too wide |
| TS18033 | an enum initializer shadowed by a BLOCK binding | decided in the parser: the checker's env cannot see the block |
| TS2304 | an undeclared name in a type-ARGUMENT position | reverted once, then reverted four corpus FPs, before the abstention was complete |
| — | a uniquely-declared block-local `interface` resolves at all | the mirror of a merge `parse_module` had for type aliases only |

**False positives fixed (the corpus scores none of these)**

- A leading `this` parameter is not an argument. Four places in this repo
  already knew that and said so in their own comments;
  `callable_func_type_from_params` and `method_callable_param_types` were
  the two without the rule, so `i.p(1)` and `k.m(1)` were reported on
  files tsc accepts. Cost ONE true positive —
  `looseThisTypeInFunctions` was flagged only by the bogus arity report.
- The block-local type merge must not pick a winner among several
  declarations of one name. The ALIAS half had that bug already and it
  was reachable from ordinary code: two functions each declaring a local
  `type W` gave three false positives on a file tsc accepts.

**Rejected, with the measurement**

- TS2684 for a CLASS method's declared `this` type.
  `class C<E, A> { m1(this: C<never, A>, x: number) {} }` with a
  `C<number, string>` receiver is **ACCEPTED**: `E` appears in no member,
  TypeScript is structural, and a phantom type parameter makes every
  `C<X, A>` mutually assignable. `applied_generic_mismatch` compares type
  arguments nominally, so the naive rule false-positives on five
  hand-written cells.
- `class C implements String {}` (TS2420) needs the merged lib member
  list. The corpus file declares 20+ members and misses the es2015
  additions, so no "declares nothing" shortcut reaches it, and a crude
  scan finds 173 EMPTY lib interface declarations — `class C implements
  WebGLProgram {}` is legal — so the blunt version is unsound.

**Operational**: the branch's PR was merged by its author at the head of
batch EP while EQ onward were still local, so the follow-up was REBASED
onto the new default branch rather than stacked on merged history.

### Batch EO (2026-09-15): 85 false positives on zod for one shadowing test

TP 2657 / MISS in scope 58 / FP 0 — the conformance numbers do not move at
all, which is the point: **this batch is measured on a real package, not on
the corpus.**

`mtsc` does not type-check zod. The shipping flags produce **272
diagnostics** on `zod@4.4.3`, and since tsc accepts zod every one of them is
a false positive — so `FP 0` on 4,484 conformance files never meant FP 0 on
real code. The corpus simply does not contain the shapes.

**85 of the 272 — 31%, for one missing test.** zod's `v4/core/util.ts`
declares `export abstract class Class` at line 1058 and ALSO has helpers
taking a `Class: SchemaClass<…>` parameter (lines 764, 818), so every
`new Class({…})` inside them named the parameter and
`check_abstract_instantiation` resolved it against `ctx.resolver.classes`
with no shadowing test. That is the scope-narrowing family this repo records
for `as_const_inline`, `const_enum_inline`, `predicate_inline`,
`switch_fold` and `type_fold` — five passes, each fixed in turn — arriving in
the CHECKER, where nobody had asked the question.

The fact was available and used **four lines below one of the two call
sites**: the TS2350 `Symbol` / `BigInt` rule already reads
`env.lookup(class_name) is None` for exactly this reason. So the fix is
`env` threaded into the check and one early return, applied at both the
`New` and the `NewExpr` spelling rather than at the one that happened to
be noticed.

Measured: zod **272 -> 187** diagnostics, abstract-class family **0**, and
the oracle IDENTICAL on both binaries (TP 2657 / MISS in scope 58 / FP 0 /
PFLEGAL 0 / TN 1750) — so the 85 cost no true positive. The suppression is
keyed on the NAME, which the test pins in both directions: a parameter and
a `const` of the same name are silent, while the unshadowed `new Class()`
still reports at both spellings, and an unrelated local (`const Other = 1`)
leaves the class reference alone.

What the batch does NOT fix is the other 187, and they rank the next work
rather than this one. By cause: 40 `case value … can never match
scrutinee` (zod's `visit.ts` switches on an indexed access into a union of
`$ZodTypeDef["type"]`), 34 assignability mismatches, 28 `interface X
incorrectly extends Y` (all of them a derived interface narrowing a member
whose type is a named interface extending the base's generic instantiation —
`$ZodCheckRegexInternals extends $ZodCheckInternals<string>` — which our
structural assignability cannot follow through a generic base), 27 `object
is possibly undefined`, 18 member-existence, and a 40-item tail across
eight shapes. None is a single missing test; each is a modelling gap.

The operational finding is the gate that is missing. Every harness here
either compiles fixtures we wrote or scores a corpus whose FP budget is
already zero, so 272 false positives on a package in `_build/type-aware/`
were invisible — and zod is CLONED there, one command away, because the
type-aware corpus dropped it for an unrelated reason (it answers that
harness's question with a permanent zero). A real-package FP gate is filed:
it needs no new download, only a `--no-check`-free run over the targets the
corpus already checks out, with the count declared per package the way
`scripts/bridge_struct_enum_fields.txt` declares its budgets, so growth
fails and a drop follows the budget down.

### Batch EN (2026-09-15): four rules, one rejection with numbers, and an abstention confirmed twice

TP 2652 -> 2657, MISS in scope 63 -> 58, FP 0, PFLEGAL 0, TN 1750.

**The `in` guard now unwraps a type ALIAS to its union.** `narrow_keep` /
`narrow_remove` call `union_components` with no resolver, so a
`type M = A | B` receiver arrived as ONE opaque variant, `lookup_field`
answered for the whole alias, `then_ty` came out `Never`, nothing was
bound, and the guarded access was reported. The sibling
`narrow_by_discriminant` unwraps for exactly this reason and says so in
its own comment — twenty-third instance of a rule applied in some places
and not others, and the first where the fix's reason was already written
down four hundred lines away. Corpus-neutral at FP 0 (TP 2652 / MISS 63 /
TN 1750, identical to batch EM), which is the point: it is a narrowing
improvement the conformance corpus cannot score, carried by a unit test
that asserts both the guarded and the unguarded spelling so it cannot be
"switched off".

**REJECTED with numbers: enumerating `Object` type literals in
`enumerable_object_shape`.** This is the SECOND probe of that abstention
and the second time the answer has been "leave it". The note that used to
sit there cited `docs/checker-priority.md`, the strategy document CLAUDE.md
records as RETIRED, so the stated reason looked like a claim whose date had
passed — the lead this series has cashed five times. It was implemented
(declining only on an index-signature key) and measured: **ZERO corpus
files for THREE false positives**, all three discriminated unions whose
discriminant our narrowing cannot decide.
`discriminatedUnionTypes4` tags with a template-literal type
(`` `${AnimalType.cat}` `` compared against `AnimalType.cat`),
`discriminatedUnionTypes3` discriminates on `.err === undefined` against a
`` `${string} is wrong!` `` sibling, and `controlFlowWithTemplateLiterals`
narrows `{ test: string } | {}`. A NAMED interface or class union reaches
the arms below and is enumerated; an inline object union stays silent
until those three narrowing forms are modelled. The abstention is
CONFIRMED with a number where the old note only had an argument, which is
the third recorded abstention in this series probing has upheld.

**TS2763 / TS2764 / TS2766: an iterator whose `next()` declares a required
parameter the position cannot supply.** `Generator<number, void, string>`
says `next(v: string)`, and a `for-of`, an array spread and a destructuring
pattern all call `next()` with NO argument — so each sends `undefined`,
which is an error under `strictNullChecks`. `yield*` is the one position
that does not: it forwards whatever the CONTAINING generator is sent, which
that generator's own `Generator<Y, R, TNext>` annotation names, so the
`CheckCtx` gained a `yield_next_type` beside the `yield_type` extracted
from the same annotation ten lines away. Worth **+1** file
(`generatorAssignability`), and the cells that decide the rule's shape are
all probed: `Generator<number, void>` — TWO type arguments, `TNext` left at
its `unknown` default — is ACCEPTED, so all three must be WRITTEN;
`Iterator<Y, R, N>` is TS2488 instead, having no `[Symbol.iterator]()`;
the identical file with `strictNullChecks` off is ACCEPTED, because
`undefined` flows into `string` there; and an unannotated container makes
`yield*` abstain rather than read `Any` as a mismatch.

Two things about WHERE it lives. The generic `Spread(v) | Await(v)` arm of
`check_call_args_in_expr` is where BOTH spread spellings arrive — an
array-literal element and a call argument — so the rule lands at every
spread position from one place rather than at the one that happened to be
noticed. And `for await` is a SEPARATE arm from `for-of` that carries
NONE of the TS2488 apparatus either (`check_iterable_class_protocol` /
`check_forof_non_iterable` are at the `for-of` site and, since batch EG,
at `yield*`); the new check is wired into both, and that TS2488 gap is
filed rather than folded in unmeasured. Array DESTRUCTURING (TS2765) is a
declared MISS: the iterable's type is not in hand at that site. A bare
type parameter as `TNext` is another — tsc reports it, and the rule's
result filter is an ALLOWLIST of concrete scalars, so `any`, `unknown`, a
union carrying `undefined` and an unresolved name all abstain.

**A `[Symbol.<well-known>]` object-literal key resolves to the same
`@@name` the target already uses.** The asymmetry is what showed the gap:
`foo({})` against `interface I { [Symbol.unscopables]: boolean }` was
already reported MISSING the member, so the type parser had encoded the
interface side as `@@unscopables` all along — only the object literal's own
key stayed `@@computed:N` and matched nothing, which made both the
excess-property direction and the value-type direction silent. Rewriting
the key needs no evaluation: the name is in the source. Only the STANDARD
well-known symbols participate, the same set and the same reason as the
parser's `is_standard_well_known_symbol`.

Measuring that also retired a queued item with a number.
`symbolProperty21`'s callee is GENERIC, so batch DX's `callee_non_generic`
gate looked like the blocker, and the queued fix was to test the WRITTEN
target (`Applied`/`Named`) rather than `resolver.unwrap(target)`. Probed:
the excess-property check at a call argument ALREADY fires for a named
interface target with a generic callee. The computed key was the only
blocker, and the suppression refinement is not needed at all.

**An unannotated class field initialized with a class instance gets that
class's type.** `inferred_primitive_field_type` is the fallback every
unannotated-field read goes through — it infers the field's type from its
initializer, and its result filter admitted only
`number` / `string` / `boolean` / `bigint`. So `class C { c = new C() }`
left `c` as `Any` and `class D extends C { d = new D(); m() { this.d =
this.c } }` was silent (TS2739 — `C` is missing `D`'s members) while the
ANNOTATED spelling of the same two fields reported. Safe against an
annotation by construction, because every caller reaches the function only
when `lookup_field` came back non-checkable, which is what an unannotated
field reads as.

Widening the result filter alone measured NOTHING, and the second half is
the finding. `field_init` is indexed per DECLARING class, so for
`class D extends C` the lookup recovered `d` — D's own field — and not the
INHERITED `c`, whose initializer lives on `C`. That left the VALUE side
`Any`, and an `Any` value satisfies any target, so the assignment stayed
silent even with the target side recovered. One step up the base chain per
level, depth-bounded rather than cycle-tracked, since a heritage cycle is
itself an error and stopping short costs a MISS. The READ side had been
working from the filter alone (`class C { c = new D() }` then
`this.c.nope` reports), which is what separated the two halves: the filter
was necessary and not sufficient, and only measuring the ASSIGNMENT showed
which.

**A `[Symbol.<name>]` member key in a `declare class` body.**
`check_computed_key_type` has judged this shape for a runtime class body
and for an object literal for as long as it existed — a `Symbol.*` static
that is not a well-known symbol has a function / object type, so it is
neither a valid computed key nor a member of `SymbolConstructor` at all —
and this was the one member-key site that could not reach it, because
`parse_declare_class_member_name` brace-matches past the key and keeps no
expression. The name is spelled out in the tokens, which is what makes a
marker enough (the same argument batch EE's TS1308 makes for reading an
`await` out of a skipped decorator). The three gates are COPIED from that
function rather than re-derived, and that is also a declared MISS:
`declare var Symbol: any` abstains here, while tsc still reports, because
an ambient declaration MERGES with the lib's rather than replacing it.

**TS2430 for a bare, UNCONSTRAINED type parameter redeclaring a base
member.** `check_interface_extends_member_compat` abstains whenever either
side mentions one of the interface's own type parameters, which is right
for every composite shape and too coarse for a BARE one: an unconstrained
`T` is effectively `unknown`, so it is assignable to almost nothing — the
argument `type_param_bounds` already carries for the TS2322 assignment
rule. Probed cell by cell, because the boundary is narrower than it reads:
`foo: T` against `{ [k: string]: any }`, `string`, `{ a: number }`, `{}`,
`object` and `number | undefined` all report, while a CONSTRAINED `T`, a
base member typed `any` or `unknown`, and a composite `T[]` are all
ACCEPTED. `interface Base<U> { foo: U }` beside
`interface E1<T> extends Base<T> { foo: T }` is legal and falls out for
free: substitution makes the base type the bare `T` too, and a bare type
parameter is not concrete.

**REVERTED, provably vacuous: the intersection / index-signature
fallback.** `is_assignable_to_inner` merges `{a} & {b}` into one shape and
then, when the merged shape is NOT assignable, falls back to "some
component on its own is" — which really is unsound against an
index-signature target, since an indexer constrains every property the
source has (`{ a: string } & { b: number }` is TS2322 against
`{ [k: string]: string }` while its `{ a: string }` component alone is
fine). Dropping the fallback when the merge succeeds was implemented and
measured, and it changes NOTHING: `{ b: number } & { a: string }` against
that target is still silent while the identical single-object source
`{ a: string, b: number }` reports, so the arm is never reached for an
intersection-typed VALUE at all — something above it abstains first, and
finding what is the actual work. Reverted with the measurement at the
site, because a fix that provably changes nothing is dead code that reads
like live code.

The operational note is the same one batch EL recorded, one level up: a
killed `moon build` leaves its queued siblings waiting on `_build/.moon-lock`,
so three `moon check` runs stacked up behind one stale build and every log
read empty for minutes. The serial order is one script per measurement —
check, build, oracle — and `ps -o etime` is what tells a queue from a hang.

### Batch EM (2026-09-15): the index signature that threw its value away

TP 2649 -> 2652, MISS in scope 66 -> 63, FP 0, PFLEGAL 0, TN 1750.

**An object-type index signature's VALUE type is kept now.** The parser
consumed it and recorded `Any`, with the reason written at the site:
value-assignability checks driven off an anonymous index signature would
false-positive through our object-literal getter modelling (`get x()`
rendered as `() => T`). Measured rather than re-argued — keeping the value
is **+2 files at FP 0**, and the two are exactly the ones CLAUDE.md had
named as blocked on it, `arrayLiterals`'s TS2353 and
`optionalPropertyAssignableToStringIndexSignature`. An INTERFACE's index
signatures have always kept their value types, so this also stops the two
spellings of one declaration from disagreeing.

Three things had been leaning on the `Any`, and the gates caught all three
— none of them the getter hazard the comment named.

The first is a cell reasoning gets wrong. An OPTIONAL source property
satisfies a STRING index signature of its base type: `{ k1?: string }` is
assignable to `{ [k: string]: string }` while `{ k1: string | undefined }`
is TS2322 (both probed), and those are the SAME node here — the type
parser wraps `k1?: T` into `Union([T, Undefined])` always. The union is
tolerated and the explicit `| undefined` spelling is the MISS that buys
it, which is the same trade `is_object_assignable_inner`'s own
`target_field_optional` comment records twenty lines below. A NUMBER index
signature gets NO such exemption — `{ 1?: string }` against
`{ [k: number]: string }` really is TS2322 — so it is keyed on the
target's key kind rather than applied to both. Six cells, five agreeing
with tsc and one declared MISS.

The second is a pre-existing hole the change surfaced: **`Struct(n, …)`
and `Named(n)` had no arm in `is_assignable_to_inner`**. `Struct` is the
structural EXPANSION of `Named`, and the resolver produces one where it
could expand an interface reference and the other where it could not, so
the two spellings of one type meet whenever a comparison crosses that
boundary — they fell to the `_ => false` catch-all. `Bar[]` against
`{ [n: number]: Bar }` broke the moment the value type arrived while
`Array<Bar>` and `string[]` were both fine, which is the asymmetry that
exposed it. Found by INSTRUMENTING rather than reading: two rounds of
tracing the arm order got nowhere and one `println` in the arm printed
`elem=Struct("Bar", …)` against `val=Named("Bar")` on the first run.

The third is `delete o["b"]` on `{ [k: string]: string }`, which is LEGAL
(probed) and had been silent for the wrong reason: with the value widened
to `Any` both `is_checkable` and `type_has_undefined` said no. A member
reached ONLY through an index signature is not a declared property, so
`reached_only_through_index_signature` states the exemption — and it
defaults to `false` for every shape it cannot enumerate, so a rule gated
on it keeps whatever it did before rather than going quiet. Four cells
agree with tsc.

Both false positives were caught by UNIT TESTS, not by the corpus: the
conformance file
`optionalPropertyAssignableToStringIndexSignature` has real errors on
three of its lines, so the two `// ok` lines we were also reporting left
it scored as a TP either way. That is batch CS's lesson once more — a
conformance file counts as a TP if we flag it AT ALL.

**TS2559, the weak-type check.** A target whose every member is optional
accepts any shape structurally, which is what makes an options-object typo
silent, so TypeScript adds the separate requirement that the source share
at least one property name with it (`intersectionAsWeakTypeSource`). Both
sides go through `cast_shape_fields`, which declines for an index
signature, a generic interface, a class and anything it cannot
enumerate — every one of those is a shape where a property might be
present without being listed, the only direction that could invent a
finding. Eleven cells probed: an EMPTY source is accepted, a source with a
string index signature is accepted, `any` is accepted, a target with one
REQUIRED member gets TS2741 instead (a code this rule does not claim), and
a method counts as a property on both sides.

### Batch EL (2026-09-14): a suppression that was hiding a bug, and six more rules

TP 2642 -> 2649, MISS in scope 73 -> 66, FP 0, PFLEGAL 0, TN 1750.

**The widening suppression's stated reason was false about TypeScript, and
removing it exposed what it was hiding.** `is_widening_direction_mismatch`
suppressed every `expected "X" (string) but got string` mismatch, and its
header said "TS accepts these (the literal initializer collapses to the
wider type at the use site without narrowing)". TypeScript accepts no such
thing — `string` is never assignable to `"Hello"`. What is true is the
weaker statement that OUR inference sometimes widens where tsc keeps a
literal type, so a report there can be about our gap rather than the
program.

Removing the arm measured **+1 TP and +1 FP**, and the FP is the finding:
`typesWithSpecializedCallSignatures` is TS7-ACCEPTED and we reported
`c.foo('bye')` against `foo(x: 'hi')`, the FIRST of three overload
signatures. `lookup_method_sig` reads `lookup_field`, which surfaces only
the first declaration of a name, so the argument check judged every call
to an OVERLOADED method against overload #1 — while `infer_expr` has had
`resolve_method_overload` for the RETURN type all along. The candidate
collection was extracted (`method_overload_signatures`) so the argument
path asks the same question, and it ABSTAINS for an overload set: nothing
at that site can reconstruct which signature the arguments were written
for, so the trade is a MISS. A single-signature method is still judged,
since there is then nothing to choose. The numeric and boolean arms of the
suppression stay — nothing has measured them, and removing an arm whose
population nobody has looked at is exactly how the FP above got written.

Two tests were found asserting the gap rather than a behaviour, the
twelfth and thirteenth in this repo. `const c = "b"; let y: "a" = c;`
asserted 0 and is TS2322 (probed). And `declare var Symbol: any;` sat in a
whole-file "silent" list for TS2350's sake while being itself TS2403
against the lib declaration.

**TS2403 at the AMBIENT spelling.** `var Symbol: { iterator: symbol }` has
reported for a long time and `declare var Symbol: { iterator: symbol }` did
not — the module parser routes `declare var` through
`parse_declare_values` into `module_.values` and pushes nothing onto
`top_level_stmts`, which is the only list the check read. One rule, two
declaration channels, read from one (ES5SymbolProperty5); the ambient
spelling is the one every `.d.ts` uses.

**A function value against a UNION of call signatures.** TypeScript states
the rule and `functionExpressionContextualTyping2` quotes it in its own
header: if every member has one non-generic call signature and all of them
are identical IGNORING RETURN TYPES, the contextual signature is those
parameters with the UNION of the returns. Only the single-`Func` target
had an arm. Parameter lists that DIFFER mean no contextual signature
exists at all — the arrow's parameters are then implicitly `any` and its
body is unjudgeable — so that case abstains rather than picking a member.

**TS2339 for an expando property on a MUTABLE function binding.**
Attaching a property to a function value is a TypeScript affordance and it
requires `const`: a function DECLARATION gets it, `const f = function () {}`
and `const f = () => …` get it, and `var f = function () {}` / `let f = () =>
…` do NOT. `typeFromPropertyAssignment29` says so in its own comment
("Should not work in Typescript -- must be const"). The annotation is not
what saves it — `declare var f: (n: number) => number; f.p = 1` is TS2339
too — but an explicit `: any` IS legal, and an absent annotation and `: any`
are the same `Any` downstream, so the fact rides a `<mutable-fn-value:NAME>`
parser marker recorded where the annotation is still known. Twenty-first
instance of the absent-versus-`: any` blocker.

**TS2556 for a spread argument of union-of-tuples type.** The rule is that
a spread argument must have a TUPLE type and a union is not one — not a
claim about lengths, which is the cell reasoning gets wrong:
`[number, number] | [number, string]` reports even though every member has
the same arity, while a union of IDENTICAL tuples collapses to one tuple
and is ACCEPTED, so the members are deduplicated before the count is
decided. An OPEN tuple still abstains, which is why `callWithSpread5`'s
first line (TS2345 in tsc) is untouched.

**TS2749 for a value name in a type-ARGUMENT position.** This is the one
place the name resolution `unresolved_type_references` cannot do is
decidable, and for a structural reason rather than a lucky one: a type
argument in an EXPRESSION has no binders of its own — the blocker CLAUDE.md
records is that `check_type` carries one flat list and loses a type's own
`<U>` / `infer` / mapped key — and the environment at the call site is
exactly the scope the name resolves in. That is what makes
`function g() { var a, b, c; if (a<b, b>(c + 1)) { } }` reachable, since
`b` is a function-local `var` and `env.lookup` finds it. Positive evidence
on both sides: the name must resolve as a value AND not be spellable as a
type by any route (class, interface, enum, alias, in-scope type parameter,
lib global). A QUALIFIED name is TS2749 in tsc and is skipped, costing a
MISS.

**TS2362 / TS2363 on a UNION arithmetic operand.**
`is_definitely_not_arithmetic` abstained on every union, and its comment
says why: a numeric-literal union like `0 | 1 | 2` is arithmetic. True of
those, and `number | string` is not one of them — tsc requires the WHOLE
operand to be numeric, so one definitely-non-numeric member decides it.
Every member has to be CONCRETE (a `Named` / `Applied` member could be a
numeric enum or an alias to `any`, and an `any` member collapses the union
to `any`, which tsc accepts), and a union of numerics with no bad member
still abstains because `number | bigint` is TS2365 — a different code this
rule does not claim. Worth **zero** corpus files: `typeGuardsDefeat`'s
errors are inside a closure whose narrowing a later `x = "hello"` defeats,
which is a different mechanism (filed below). Shipped anyway because the
direct spelling `function b(x: number | string) { return x * x }` is what a
person writes.

**TS2339 for an unspellable `globalThis` index key.** The name of an
ambient EXTERNAL module INCLUDES its quotes, so
`(typeof globalThis)["\"ambientModule\""]` names no property of the global
object — the point `globalThisAmbientModules` makes next to the
`["valueModule"]` that IS legal. The test is on the KEY's characters rather
than on a name set, deliberately: a single file cannot see the globals
another script file declares, so a name-set test would false-positive on
any real multi-file program, while a quote can never appear in a global's
name whatever the rest of the program says.

**Filed, not built: narrowing must not survive an assignment seen by a
closure.** `typeGuardsDefeat` is the last file of the arithmetic pair and
needs a different fact. Probing settles what the rule is NOT: TypeScript
DOES preserve a parameter's narrowing inside a closure created in the
narrowed region — five hand-written cells are all ACCEPTED — so "reset
narrowing when entering a nested function" is wrong. What defeats it in
that file is the later `x = "hello"` in the enclosing function, which the
closure can observe, so the fact needed is "this binding is assigned
somewhere other than its initializer" and the reset applies only to those.
That is a real change to the narrowing engine with its own false-positive
surface, for one file.

**Operational finding: `moon build --target native` builds DEBUG.** The
justfile's `verify-checker-soundness` runs exactly that and then the
oracle, which works only because the oracle picks the NEWER of the two
binaries. Probing `_build/native/release/.../tscheck.exe` by hand after a
plain `moon build` measures whatever the last `--release` build contained —
which cost most of an hour here: a patch was verified absent from the
release binary by re-running it, the conclusion "the report must come from
another site" was drawn, and twenty-one call sites were instrumented with
unique markers before `ls -la` showed the binary was ten minutes older than
the source. Second instance in this file of a stale-binary measurement, and
the first where the instrument was a hand-run binary rather than a harness.

### Batch EK (2026-09-14): three abstentions, and the fifth whose stated reason was false

TP 2639 -> 2642, MISS in scope 76 -> 73, FP 0, PFLEGAL 0, TN 1750.

**TS2564 inside an `abstract class`.** `class A { x: number }` reported and
`abstract class A { x: number }` did not, and the exemption was written down
with a reason: "our parser drops the `abstract` modifier on properties, so
we can't distinguish a truly-unassigned concrete field from an abstract
one." `TsClassDecl.abstract_members` exists, and its own doc comment says it
holds `abstract x: number` as well as `abstract foo(): void`. Fifth
recorded abstention in this series whose reason turned out false, and the
second where the list that dissolves it was sitting in the same struct.

Skipping only the named fields rather than the whole class needed nothing
else: probed one cell at a time, an `abstract class`'s exemptions are
exactly a concrete class's — `abstract y`, `z = 1`, `w!`, `v?`, a
constructor-assigned field, a `static` field and every member of a
`declare abstract class` are all silent, and only the plain
`x: number` reports.

**TS2341 / TS2445 through `interface A extends C`.** An interface that
extends a class inherits its members, and a `private` one stays private to
the declaring CLASS: `class C { private p }` beside
`interface A extends C { }` makes `a.p` TS2341 and `a.q` (protected) TS2445.
Both were silent while the direct `c.p` spelling has reported for a long
time. The verdict function is already keyed on the declaring class — batch
BZ split it out so the destructuring spelling could share it — so the only
thing missing was resolving the receiver's interface name to that class.
Depth-bounded rather than cycle-tracked: an interface heritage cycle is
itself an error, and stopping short costs a MISS.

**TS2304 for `export = A` inside `declare module "M"`.** The parser records
the same `<export-eq>` marker there as at top level, and the consumer reads
only `module_.grammar_misuses` — a `declare module "spec"` body lands in
`module_augmentations`, which, unlike `namespaces`, the layered recursion
does not descend into, so every marker its body produced was dropped. The
top-level spelling reported and this one did not
(`parserExportAssignment6`). Scoped to that ONE marker rather than
surfacing the whole channel: the rest are decided against a module-wide
name set or a compiler-option header an augmentation body does not have,
and a blanket surface is how a marker becomes a diagnostic nobody checked
— which is exactly what TS4111's flag marker and `<module-commonjs>` each
did once. Resolution takes the augmentation body's own value names UNION
the outer module's, because an ambient `.d.ts` legitimately writes
`declare module "x" { export = Y }` with `Y` declared on either side.

**A harness lesson, paid for twice.** `verify-examples` and
`verify-generated-fixtures` invoke `moon run src/cmd/ts2mbt`, which
RECOMPILES from source — so running them while the tree is being edited
measures whatever half-finished state the files are in. The first
`verify-examples` failure of this batch was exactly that, and the traced
re-run proved it by failing on a `[4014]` type error I had introduced two
minutes earlier. A source-recompiling harness has to be run on a tree that
compiles and is not moving; the serial order is check, test, build, oracle,
then the recompiling harnesses.

### Batch EJ (2026-09-14): a parameter is not a module binding, and three rules for MISS 79 -> 76

TP 2635 -> 2639, MISS in scope 80 -> 76, FP 0, PFLEGAL 0, TN 1750.

**The backstop.** `Resolver::declared_value_names` is a hoisting /
forward-reference backstop for the TS2304 check, and it was declaring every
PARAMETER of every function, function expression and arrow anywhere in the
file as a module-level value name. So `function f(pname) { }` beside a bare
`pname;` at top level was silent, and so was
`const g = (pname) => pname; pname;`. A parameter is scoped to its own
callable; putting it in a module-wide set is not a hoisting allowance, it is
a hole. Removed from the three module-wide collection sites
(`collect_module_value_names`'s `module_.funcs` loop and
`collect_expr_value_names`'s `FuncExpr` / `ArrowFunc` arms) and kept at
`check_function_body`, which seeds ONE function's own parameters and is
where the fact belongs.

Removing it alone is +1 file and **2 false positives**, and the false
positives named the real bug rather than arguing for the backstop:
`objectRestParameter` / `objectRestParameterES5` reported `rest` and
`nested` as undeclared, because `Parser::parse_param` sets `p.name` to
`binding_first_name(binding)` — the FIRST name in the pattern — and keeps
the pattern in `p.binding`. `check_function_body` has walked the pattern
with `bind_pattern` for a function DECLARATION for a long time;
`check_arrow_with_context` and `check_funcexpr_with_context` had only the
`env.bind(p.name, ty)` line. So `({ a, ...rest }) => …` bound `a` and left
`rest` unbound, `([p, ...q]) => …` bound `p` and left `q`, and a pattern
parameter behaved differently depending on which of the three spellings the
callable used. `bind_callable_param` is one helper called from all three.
Nineteenth instance of one rule applied in some places and not others.

**TS2322, constructor-type accessibility on assignment.** A class value
carries its constructor's accessibility and a more restrictive constructor
type is not assignable to a less restrictive one. The message ("cannot
assign a 'protected' constructor type to a 'public' constructor type") reads
like a matching rule and is a one-directional RANK comparison; every cell
was probed against the local compiler. public 0 / protected 1 / private 2,
error iff src > tgt: with `let a = Pub` both `Prot` and `Priv` report, with
`let b = Prot` only `Priv` does, with `let c = Priv` nothing does. A
SUBCLASS is no exemption (`class ProtSub extends Pub` with a protected
constructor still reports) and two classes at the SAME rank get TS2419
instead — structural construct-signature incompatibility — so equal ranks
stay out. No inference is available: `let a = Foo` does not produce
`typeof Foo` in this checker at all (`a = 5` beside it is silent), so the
fact comes off the syntax.

Two things cost a draft each. The rule was SILENT on its own corpus file
while the `var a: typeof Pub = Prot` spelling reported, because a top-level
`a = Prot;` reaches the statement dispatcher as `Assign` only when
`parse_expr_until_top_level` stops before the `=`; otherwise the whole thing
is `Expr(AssignExpr(...))`. Both arms now, the same split TS2565 and the
`globalThis` rule already record for `PropAssign`. And the un-annotated
holder path needs a PARSER marker: `TsStmt::Let` carries `Any` for both an
absent annotation and an explicit `: any`, and only the first takes its type
from the initializer — `let d: any = Pub; d = Priv` is LEGAL (probed). The
`<classval-decl:NAME:SRC>` marker is pushed where `record_tuple_index_out_of_range`
and `record_nullish_inferred_declaration` already sit, behind the same
`if !annotated` guard, and gated on `!self.in_function` because the consumer
reads flat `top_level_stmts` with no scope model. The corpus never sees that
false positive; the unit test does. Twentieth absent-versus-`: any` blocker
in this repo, after TS7031, TS7022, TS2729, TS2448, TS2564 and TS2490.

**TS2322, a write through a namespace qualifier.** `namespace N { export
var p = 6 }` beside `N.p = false` was silent. This is what declaration
merging produces and what an expando author hits:
`typeFromPropertyAssignment31` merges `function ExpandoMerge(n: number)` with
a namespace exporting `p8` and `p9` and writes `false` to both. Probed cell
by cell: it reports for a `var` and a `let` member and for a namespace merged
with a function or a class as readily as a bare one, and stays SILENT for
`export var e;` (implicit `any`). A write to an undeclared member is TS2339
and to an `export const` is TS2540 — different codes this rule does not
claim, so `const` members are not collected. Both sides must be a definite
primitive, decided syntactically. Exportedness is not consulted because the
AST does not record it and it costs nothing: a member declared WITHOUT
`export` is not reachable as `N.x` at all, so such a write is an error either
way. Both declaration lists are read, since `export var p: number` with no
initializer lands in `values` rather than `top_level_stmts`.

**TS2352 between two function types.** `(v => v) as (x: number) => string`
was silent, and so was the fully annotated form. Two pieces: an ARROW in
`as` position is contextually typed by the asserted type's PARAMETERS (not
its return — taking that would make every such cast trivially fine), which
is what turns `(any) => any` into the `(number) => number` the rule can
judge; and identical parameter lists with returns from different primitive
families is the one shape where no bivariance can rescue the conversion.
Three cells read the other way from the message text and only probing
settled them: a `void` return OVERLAPS anything (`(() => {}) as () => string`
is ACCEPTED), so `equality_primitive_family` abstaining on `Void` / `Any` /
`Never` is exactly right; and a PARAMETER mismatch, a differing ARITY and an
`any` parameter on the target side are all TS2352 in tsc, where this rule
takes the MISS rather than model a bivariant comparability relation.

### Perf round, part 4 (2026-09-14): the filed mechanism was wrong, and the axis name is why

Task #133 filed "index `#private` base name -> brands per class" off the
`private-members` axis reading 1.67. **The index was built, measured, and
bought nothing** — 1.66 against a 1.52-1.68 baseline — because the
mechanism in the note was not the cost. The note was written by reading
the three private-brand queries and seeing three per-access scans over a
class's `properties` + `methods` + `private_members`. All three are real
scans. None of them runs: `private_brand_declared_on_receiver` is
reached only where a private lookup has already MISSED, which is the
error path, and a well-formed file never takes it. Restoring the
module-wide scan after the fact measures **0.14 s against 0.13 s** on the
same file. Reading a loop and asking "is this quadratic" is not the same
question as "does this execute", and only the second one predicts time.

What found the real mechanism, in the order that worked:

1. **Split parse from check.** `--parse` is linear (0.01/0.02/0.05 s at
   n=1000/2000/4000) and the full run is not (0.03/0.07/0.26). The
   quadratic is in the check.
2. **Bisect by input SHAPE, not by reading.** Four files at the same
   member counts: the axis (N `#private` fields + N methods reading
   them) 0.28 s; the same with bodies that read nothing **0.07 s**;
   the same with PUBLIC fields and `this.a{i}` reads **0.24 s**; private
   fields with no methods 0.04 s. The public spelling is as slow as the
   private one, which refutes "it is about private names" outright and
   says the cost is per member ACCESS.
3. **Sample the stacks.** No `perf` here, but `gdb -p <pid> -batch -ex
   "bt"` in a loop over a 16,000-member class is enough: **10 of 10
   samples** in two leaves, both inside `memcmp` —
   `Resolver::lookup_class_field` (7) and
   `inferred_primitive_field_type` (3).

Both resolve a member by NAME with a linear scan, per access:
`lookup_class_field` walks `properties` then `methods`, and
`inferred_primitive_field_type` walks `instance_field_inits`. N members
with N reads is N x N. `ClassIndex` indexes all three lists by name,
lazily, storing POSITIONS rather than types so a method's `Func` type is
still built only when asked for and `properties` still wins over
`methods`. `lookup_class_field` now takes the resolver's class KEY
instead of the decl, so the index (keyed the same way) and the member
lists cannot be handed over as a mismatched pair — and a bare
`TsClassDecl.name` would have folded two namespaces' `C` together.

Measured, same toolchain, baseline vs fix:

| | baseline | fix |
|---|---|---|
| 16,000-member class | 8.32 s | **0.98 s** (8.5x) |
| axis exponent | 1.63 | **1.21** (1.16-1.33 over 5 runs) |
| axis n=4000 | 277.0 ms | **105.8 ms** |
| `lib.dom.d.ts` | 0.21 s | **0.18 s** |
| `typescript.d.ts` | 0.11 s | 0.10 s |

The real-file numbers are the point: this is not a synthetic-only win,
because `lib.dom.d.ts` is full of many-membered declarations. Oracle is
byte-identical on both binaries (TP 2635 / MISS in scope 80 / OUT OF
SCOPE 19 / FP 0 / PFLEGAL 0 / TN 1750), which is what a pure lookup
refactor should be, and it was measured rather than assumed by swapping
the baseline binary into the release path and re-running.

**The `AXIS_BUDGET` entry is REMOVED, not retuned.** 1.21 is under the
default 1.50, so the special case is gone rather than left as slack a
regression could hide in.

Two labels to stop trusting. The axis is named `private-members` and
measures member ACCESS against a many-membered class; the name is what
made the private-brand code look like the suspect, and I wrote both the
name and the wrong note. Eleventh instance in this repo of a label
standing in for the objective, and the first where the label was mine.
And part 1 of this round called this axis "linear (1.17)" off a 125..1000
ladder — a fit is only a fit over the range it was taken on.

**REJECTED with its number**: the private-brand index, which is what the
task asked for. It costs 0.01 s of 0.13 s, i.e. nothing, for a struct
field, an invalidation path and three rewritten queries. Dropped; the
scans are back exactly as they were, with only the duplicated `brand_of`
factored out into `private_brand_key`.

Two process findings, both about the toolchain rather than the code.
**`main` did not build locally at all**: commit `344fd99` ("compile
warning-free on the latest MoonBit") uses `Array(capacity=)`, which needs
a newer moonc than the pinned 0.1.20260819, so `moon build` exited 255 —
and the scaling harness then measured a STALE release binary from before
`main` moved and reported a confident 1.52. That is the stale-binary trap
CLAUDE.md already records for the oracle, arriving at a second harness;
my own `moon ... | tail -5; echo "exit=$?"` made it worse by capturing
`tail`'s status instead of `moon`'s. Upgraded to 0.1.20260904 (moonc
v0.10.12), which is what `main` needs.
**Do not run repo-wide `moon fmt` after a toolchain bump**: the newer
formatter rewrote **64 unrelated files**. CI's fmt step is
`continue-on-error: true` and its comment explains exactly this — the two
formatters actively disagree and no state of the source satisfies both —
so the churn was reverted and the change re-applied to a pristine tree.
The tree is also warning-free now, which retires CLAUDE.md's "450+
pre-existing warnings" note.

### Batch EI (2026-09-13): MISS 99 -> 80, and an optionality PROXY at two more sites

**+19 files at FP 0** (TP 2616 -> 2635, MISS in scope 99 -> **80**,
PFLEGAL 0, TN 1750). Nineteen rules, thirteen of them pure grammar or
declaration shape, and the two findings worth more than any single file
are both about **one question answered in several places**: the `?` on a
member, and the `?` on a get/set pair.

- [x] **TS2477 / TS2478** (+1: `enumConstantMembers`). A `const enum`
  member initializer that EVALUATES to a non-finite value, or to `NaN`.
  The one rule in the enum family that needs the VALUE rather than the
  shape, and it is decidable because a const enum initializer is a
  constant expression by definition: `enum_const_double` folds the literal
  arithmetic and abstains on anything else, so an unfoldable initializer
  costs a MISS. `in_const_enum` is the whole rule — a PLAIN enum takes
  `1 / 0`, `NaN`, `Infinity` and `-Infinity` in silence (probed), while
  `declare const enum` reports and needs no code of its own.
- [x] **TS2501** (+1: `restPropertyWithBindingPattern`). An object-rest
  element whose target is a binding pattern (`({...{}} = {})`). Sibling of
  `record_rest_element_initializer`, in the same arm and for the same
  reason. Object rest ONLY, which is the asymmetry probing settled:
  `[...[a]] = [1]` is ACCEPTED. The parenthesized forms carry a second
  code (TS2701) this rule does not claim — the parser strips parens, so
  `{...{}}` and `{...({})}` are the same node here.
- [x] **TS2523** (+1: `FunctionDeclaration7_es6`). `yield` in a
  generator's own parameter initializer. `in_generator` is the gate, and
  it is why the rule can sit in ONE place rather than at each of the
  fifteen `parse_params()` sites: a `yield` in a parameter list becomes a
  Yield NODE only when the enclosing context is a generator, and there
  every spelling is an error. The three cells that decide the walk:
  `function* f(a = yield)` and `function* f(a = { b: yield })` report,
  `function* f(a = () => yield)` does NOT — an arrow's body is its own
  scope, so `expr_yields_outside_function` stops at every function
  boundary.
- [x] **TS2463** (+1: `optionalBindingParameters2`). An optional
  binding-pattern parameter in an IMPLEMENTATION. The exact MIRROR of
  `record_bodiless_param_initializers` — the same body-or-not question
  inverted — so it is called from the two places that have already decided
  it and nowhere else. Recording it in `parse_param` would be wrong at its
  own site: the `?` on a pattern parameter is LEGAL in every bodiless
  position (`declare function`, an interface member, a `declare class`
  member, a function TYPE — all four probed and accepted). The arrow and
  object-method spellings stay MISSes, which is what the two-call-site
  restriction buys.
- [x] **TS2661** (+1: `globalThisGlobalExportAsGlobal`). `globalThis` is
  carved out of `check_non_local_exports`' lib-global exclusion, and the
  reason is tsc's own message: it has a DEDICATED sentence for this name,
  so the verdict does not rest on the general "a lib declaration is not a
  local one" argument the exclusion hedges against. `globalThis` is not a
  declaration at all.
- [x] **TS1433 / TS2680** (+1: `decoratorOnClassMethodThisParameter`). A
  decorated or modified `this` parameter, and a `this` parameter that is
  not first. Both facts were already in hand at the two right places —
  `parse_param` has the decorator and modifier answers, `parse_params` is
  the one function that sees every parameter list in the language. One
  cell cost a false positive first: `visibility_param` defaults to
  `"public"` whether or not a keyword was written, so it answers "which
  accessibility applies" and not "was a modifier present";
  `is_param_property` is the second question.
- [x] **TS2754** (+1: `taggedTemplatesWithTypeArguments2`). `super` with
  type arguments, at the one place that sees the type-argument list.
  `super<number>(1)` and `super<number>.m()` both report;
  `super()` / `super.m()` are accepted.
- [x] **TS2629 / TS2628 / TS2630** (+1: `assignments`). One rule, three
  messages: an assignment whose target is a class, an enum or a function
  declaration. Restricted to TOP-LEVEL statements, and the restriction is
  what makes it sound — a nested scope can shadow any of these names
  (`class C {} function f(C) { C = null }` is legal) and the flat
  `top_level_stmts` list is the one place the name is unambiguously the
  module-level declaration. `let C = class {}; C = null` and
  `let f = function () {}; f = null` are both ACCEPTED, which is why
  `is_local` classes are skipped; an ambient `declare class` /
  `declare function` DOES report and needs no condition.
- [x] **TS1005** (+1: `privateNamesAndIndexedAccess`). A private name as
  an indexed-access type key (`C[#bar]`). Recorded as a grammar misuse
  rather than raised: the fall-through already recovers the type as `Any`,
  and a parse REJECTION here would risk a PFLEGAL on anything else
  reaching that arm.
- [x] **TS1338** (+2: `inferTypes1`, `templateLiteralTypes1`). An `infer`
  outside a conditional's extends clause. **The corpus caught the first
  version**, and the cell it caught is the whole rule: the three
  non-extends positions INHERIT the permission rather than clearing it,
  because the message means "inside SOME conditional's extends clause".
  `type X11<T> = T extends ((infer U) extends number ? 1 : 0) ? 1 : 0` is
  ACCEPTED — `inferTypesWithExtends1` says so in its own comment — while
  the identical inner conditional as a whole alias BODY is TS1338 three
  times, and not on the extends position.
- [x] **TS2838** (+1: `inferTypesWithExtends2`). One `infer` name declared
  twice with DIFFERENT constraints in the same extends clause. Only a
  WRITTEN bound participates, and that is the second cell the corpus
  caught: an unconstrained declaration beside a constrained one is
  ACCEPTED in either order, which `inferTypesWithExtends1` calls "same
  behavior as class/interface" — a missing constraint is inherited rather
  than contradicting.
- [x] **TS2488 / TS2504** (+1: `types.forAwait.es2018.2`). An OBJECT
  LITERAL as a `for-of` / `for await` source — the same mistake against
  the two protocols, which is why one function takes `is_await`. It reads
  the EXPRESSION rather than the inferred type, and that is what makes it
  complete by construction rather than a guess about the object model: an
  object literal is a full description of its own members. The two shapes
  that can hide a protocol method — a COMPUTED key (how
  `[Symbol.iterator]() {}` is written) and a SPREAD — abstain outright.
- [x] **TS2341 / TS2445** (+1:
  `privateProtectedMembersAreNotAccessibleDestructuring`). Destructuring
  reaches a member exactly as a property access does, and this spelling
  had no check at all: `let { priv } = k` was silent where `k.priv` has
  been reported for years. `check_member_accessibility`'s verdict is split
  into `check_class_member_accessibility` so the two callers share one
  rule rather than getting a second copy — the applied-in-some-places bug
  written into its own fix. The enclosing-class context comes from
  `ctx.path_prefix`, so the corpus file's legal cases (inside K's own
  method, and a protected member in a subclass) fall out with no condition.
- [x] **TS2855 / TS2340** (+1: `privateInstanceMemberAccessibility`). A
  `super` access reaching a base DATA FIELD. `super.x` looks the property
  up on the base PROTOTYPE and a class field is an own property of each
  instance, so there is nothing there to read WHATEVER its visibility —
  and that is the cell reasoning gets wrong. The corpus file is written as
  if it were an accessibility rule and its older message says "only public
  and protected METHODS"; `private`, `protected` and `public` base fields
  all report, and the local compiler gives TS2340 at `target: es5` and
  TS2855 from es2015 up, which is why one rule carries both numbers.
  Three neighbours are accepted and each needed its own exclusion: a
  METHOD and an ACCESSOR (both on the prototype, so a name also in
  `methods` abstains — which covers batch CV's ambient accessors, upserted
  into both lists), a PARAMETER PROPERTY, and **a STATIC base member of
  the same name**, which cost two false positives
  (`thisAndSuperInStaticMembers1`/`2`): in a static member `super` is the
  base CONSTRUCTOR, where a `static` field of that name really does live,
  and static and instance field initializers share one `CheckCtx` path so
  the context cannot be read there.
- [x] **TS2456** (+1: `recursiveMappedTypes`). A mapped type's SOURCE is
  not a structural barrier, and it was the one position `reaches_alias`
  was missing: `type Recurse = { [K in keyof Recurse]: Recurse[K] }` is
  circular because computing the key set needs `keyof Recurse`. The VALUE
  position deliberately has no arm — that IS a barrier, which is what
  keeps `type A = { x: A }` legal and what keeps `Circular<T>` and
  `Transform<T>`, both TS7-ACCEPTED in the same corpus file, silent: their
  source is `keyof T`, a type parameter.
- [x] **TS2503** (+1: `verbatimModuleSyntaxInternalImportEquals`). The
  `<import-eq-root>` recorder had the dot test inside its guard, so the
  rule was written for the DOTTED spelling and applied to one of the two:
  a single-segment target (`import f1 = NonExistent;`) never reached it.
  The root of a one-segment reference is the whole reference. Probed: a
  namespace and an enum target are legal, a CLASS or INTERFACE target is
  TS2702, a different code the consumer abstains on.
- [x] **The optionality PROXY, at two more sites** (+1:
  `iterableArrayPattern17`). Batch EH replaced
  `is_assignable_to(undefined, ty)` with the union test in
  `check_expr_against`; the same question was still being asked by the
  proxy in `object_fields_assignable` and in
  `struct_assignable_named_rec`. The second one is the live bug: it only
  ever PROVES assignability, so a permissive answer SUPPRESSES the
  diagnostic — and `class Bar { x }`, whose unannotated field becomes
  `any`, accepted every source. `any` / `unknown` / `undefined` / `void`
  are all REQUIRED members tsc reports missing (probed); the UNION case
  stays tolerated, because there `x?: T` and `x: T | undefined` really are
  the same node.
- [x] **TS2411 with an INTERFACE index value** (+1:
  `objectTypeHidingMembersOfExtendedObject`). The class-only arm could
  never reach `interface Object { data: A; [x: string]: Object }`, which
  augments the lib interface. Only the fields the module DECLARES for that
  name are required, so an interface whose real surface is larger
  under-requires — losing findings, never inventing them, which is also
  why an `extends` chain needs no guard on that side.

**The false positive the corpus structurally cannot see** — the fourth
batch in a row to find one by probing a legal neighbour. The get/set pair
rule required the getter's type to be assignable to the setter's parameter
type, and **TypeScript 4.3 made those types allowed to DIVERGE**:
`get p(): string { return "" }` beside `set p(x: number)` is ACCEPTED, and
the error, if any, lands where the value is READ. Only an UNANNOTATED
getter is an error, and there the getter's type comes contextually FROM
the setter, so what tsc reports is the `return` inside the body. The
annotation-presence fact is not in `TsClassMethodDecl` — the
absent-versus-`: any` blocker this repo records for TS7031, TS7022,
TS2729, TS2448 and TS2564 — so the pair is judged only for a member the
parser recorded in `unannotated_return_members`, the
`<unannotated-return:>` channel batch EH built for TS2490. One more cell
came with it: a COMPUTED key pairs the two accessors only when it is a
late-bound name of LITERAL type, so `[G.B]` and `["get1"]` pair and
`[1 << 6]` does not — its type is `number`, not the literal `64`, and our
parser folding the shift to the member name `64` is more precise than
tsc's own model. Ten cells now agree with tsc.

**Measured and NOT taken**, each with its blocker rather than a verdict:

- **TS2304 for an `infer X extends Bound` whose bound is undeclared**
  (`inferTypesInvalidExtendsDeclaration`). Written, wired, and REVERTED
  after instrumenting rather than re-reading: the type parser REDUCES a
  conditional whose extends relation it can decide, so
  `type Test<T> = T extends infer A extends B ? number : string` arrives
  as the bare `Number` and neither the marker nor its bound survives. The
  rule's own scaffolding (a per-position binder set threaded down the
  walk, which is what makes the general `unresolved_type_references`
  version unusable) is gone with it — dead code that reads like live code
  is a defect.
- **TS2797** (`mixinAbstractClasses.2`). Needs the link from a class
  declared inside a function to that function's PARAMETER types and type
  parameter bounds: the base is `baseClass`, a value parameter whose type
  is `TBaseClass extends abstract new (...args: any) => any`. Nothing
  connects a `local_classes` entry to its enclosing function.
- **TS2339 for `Symbol.<unknown member>`** (`parserES5SymbolProperty4`).
  The occurrence is a TYPE-position computed key in a `declare class`, and
  the verdict needs a file-level fact the member parser cannot have:
  whether the file augments `interface SymbolConstructor` (symbolProperty61
  does, legally). Routable through a sentinel; not worth a new channel at
  +19.
- **TS18046 through an ALIASED guard**
  (`controlFlowAliasingCatchVariables`). `const isString = typeof e ===
  'string'` followed by `e = 1` invalidates the alias, so the later
  `if (isString)` no longer narrows. Needs aliased control flow plus
  assignment invalidation; the existing token-scan withdrawal sees the
  `typeof e === 'string'` elsewhere in the block and abstains.

### Batch EH (2026-09-13): MISS under 100, and five false positives the corpus could not see

**+9 files at FP 0** (TP 2607 -> 2616, MISS in scope 108 -> **99**, PFLEGAL 0,
TN 1750). Nine rules, and the more useful half of the batch is the **five
false positives** it fixed — legal code tsc accepts that this checker
reported. Two of them were only reachable because a new rule stopped
another bug from hiding them, which is the finding worth keeping: **a
false positive can be held out of sight by a second bug, and the corpus
scores the pair as correct.**

- [x] **Union callee arity** (+1: `unionTypeCallSignatures4`).
  `check_union_callee_arity` computes `max_min` — the LARGEST minimum arity
  across the union's members, which is what tsc's `combineUnionParameters`
  encodes — and then OVERWROTE it with `min_min`, the smallest, whenever no
  member's parameter domain dominated the others'. `callable_params_narrower_than`
  returns `None` on a length mismatch, so nothing can dominate the moment
  the members differ in parameter COUNT, and the fallback ran: `A1 | A2`
  accepted one argument where tsc requires two. Probed across five shapes
  including two with a rest member, and `max_min` agrees with tsc on every
  cell (`(a) => void | (...r) => void` requires 1, not 0). The dominance
  reduction is kept for the case it was written for and can now only apply
  where every member has the same arity.
- [x] **TS2420 on the INDEX SIGNATURES** (+1: `subtypingWithNumericIndexer5`).
  `check_class_implements` excludes a class that declares an index signature
  from its missing-member arm, and nothing then asked whether the indexer it
  DOES declare is compatible with the interface's. The coverage rule is
  asymmetric and was probed one cell at a time: a STRING indexer satisfies a
  numeric one (every numeric key is a string key) and a numeric one does NOT
  satisfy a string one — tsc's own two wordings say so. Only the
  compatibility half ships; the "index signature for type 'number' is
  missing" half needs the base chain's index signatures, which
  `resolve_base_chain_members` does not carry.
- [x] **TS2416 on a class METHOD's TYPE** (+1: `symbolProperty24`). The check
  compared a data-PROPERTY's type and a member's PRESENCE; a method's type
  was compared by nothing, so `interface I { m(): number }` beside
  `class C implements I { m(): string { … } }` was silent, and so were the
  `m: () => number` property-of-function-type spelling and a PARAMETER-type
  mismatch. `member_override_incompatible` cannot answer it — a `Func` on
  both sides falls through its final `false` — so `method_override_incompatible`
  compares returns COVARIANTLY and parameters BIVARIANTLY, which is the cell
  reasoning gets wrong: `m(x: string)` against `m(x: any)` is LEGAL, so a
  contravariant comparison would report it.
- [x] **TS2490: an iterator's `next()` result** (+1: `for-of15`). Filed one
  batch ago with a blocker, and the blocker is what this batch removed. Five
  cells report (`next() { return "" }`, `next(): string`,
  `next() { return 1 }`, `next() { return { done: true } }`, `next() { }`)
  and three do not (an object carrying `value` annotated or returned, and
  `next(): any`). The `[Symbol.iterator]()`-returns-`this` gate is required
  rather than cosmetic: when it returns something else, THAT object's `next`
  is consulted and tsc accepts whatever this class's says.

  The channel both TS2416 and TS2490 needed is `<unannotated-return:NAME>`,
  a per-class sentinel in the shape `optional_member_names` already uses.
  `TsClassMethodDecl.return_type` is `Any` for a missing annotation and for
  an explicit `: any` alike — the blocker recorded for TS7031 / TS7022 /
  TS2729 / TS2448 — and both rules have to infer the return from the BODY,
  which is right for the first and a false positive for the second. The
  marker asserts two facts, and the second one matters: the body was a real
  `{ … }` block, which is the only way to read a `None` body as `void`,
  since `TsClassMethodDecl.body` is `None` for an EMPTY body as well as for
  a bodiless overload signature.
- [x] **TS2698: a spread of `T & undefined`** (+1: `spreadObjectOrFalsy`).
  The existing arm covered non-iterable primitives; an INTERSECTION with a
  nullish part is the shape the corpus file writes, and its four legal
  neighbours are all UNIONS that keep a non-nullish part. The bare
  `Undefined` / `Null` spellings tsc also reports are deliberately absent:
  our flow model narrows an `any`-typed binding to `Undefined` when its
  initializer is `undefined`, so an arm for it would report a type tsc calls
  `any`. An intersection with a nullish part cannot be produced by
  narrowing — it is only ever written.
- [x] **`Record<K, V>`'s keys, and the optionality PROXY** (+1:
  `assignmentCompatWithEnumIndexer`). Two independent gaps in one file.
  `collect_declared_fields` had arms for five projectable utilities and none
  for `Record`, the one whose fields come from its KEY argument rather than
  from a source shape. An ENUM key is the cell reasoning gets wrong and it
  was probed: `enum E { A }` makes `Record<E, any>` require the key `"0"` —
  the member's VALUE — so `{ 0: 1 }` satisfies it and `{ A: 1 }` is an
  EXCESS property. Auto-numbering is reproduced rather than guessed, because
  the AST keeps a folded value only for members that wrote one; a member
  after a non-numeric one abstains for the whole enum.

  Wiring that in still reported nothing, and the reason is the second gap:
  the missing-required check asked `is_assignable_to(undefined, ty)` as a
  proxy for "is this member optional". The `?` is not in the AST — the
  parser wraps `a?: T` into `T | undefined`, ALWAYS producing a union — so
  the union IS the encoding, and the proxy answered yes for five shapes the
  `?` can never produce. Probed one at a time: `a: any`, `a: unknown`,
  `a: string | undefined`, `a: undefined` and `a: void` are all required
  members tsc reports missing, and only `a?: any` is not. The union case
  stays suppressed, because there the two spellings really are the same
  node.
- [x] **A property write spelled with BRACKETS** (+1: `symbolProperty46`).
  `PropAssign` has checked `recv.prop = value` against the member's declared
  type for a long time and `recv["prop"] = value` reached nothing at all —
  the shape recorded for TS2790's `delete o["b"]`, and it needed BOTH the
  statement and the EXPRESSION arm, since `o["p"] = 1` at the top of a list
  is a statement and the identical line inside a function body is an
  expression. The key resolution is not re-derived: `infer_index` is what
  the READ side uses, so index signatures and literal keys answer here
  exactly as they do there.

  Two things had to come with it. `infer_index` had no arm mapping
  `Symbol.hasInstance` to the mangled member name `@@hasInstance`, so a
  well-known-symbol index was `Any` in both directions. And an ACCESSOR pair
  has to be resolved before `lookup_field`, which hands back the GETTER's
  SIGNATURE: the parser upserts a plainly-named `get p(): T` into
  `properties` as `p: T`, so the dotted path never needed it, while a
  COMPUTED key gets only the `methods` entry. Comparing an assigned value
  against a function type is a false positive on the legal write, and the
  corpus file has one of each on adjacent lines.
- [x] **TS2349: an intersection reduced to `never`** (+1:
  `neverIntersectionNotCallable`). Two constituents declaring the same
  member with definitely-conflicting types make the intersection
  uninhabitable, so it has no call signature either — tsc's message says
  exactly that. `types_definitely_differ` is the conflict test and abstains
  on everything it cannot prove, and the accumulation is one pass over the
  constituents rather than a pair loop, for the reason
  `check_merged_interface_member_conflicts` is one pass. It reports through
  `record_unfiltered`: the permissive filter drops the "not callable" family
  wholesale — the suppression batch CL had to carve TS2348 out of — and the
  reduction proof is exact.
- [x] **A spread does not copy `#private` members** (+1:
  `privateNameAndObjectRestSpread`). `({ ...other }).#prop` is TS2339
  because a private field is not an own enumerable property, and carrying it
  into the spread's inferred shape made the private-name existence check
  resolve a member that cannot be there. The diagnostic also had to be
  taught to print `#prop` rather than `__private_brand__0__prop` — the third
  time in this repo, after TS7008 and batch ED's duplicate-member check, so
  `member_display_name` is now one function the whole property-access family
  routes through.

**The five false positives, and why the corpus could not see them.**

1. **`?.` on a receiver that cannot be nullish.** The `OptionalChain` arm of
   `infer_expr` unioned `undefined` into the result unconditionally, so
   `declare const c: { p: number }; const n: number = c?.p` was reported.
   Writing `?.` on a non-nullable receiver is redundant, not wrong.
2. **The array predicates.** `filter` / `some` / `every` / `find` /
   `findIndex` / `findLast` / `findLastIndex` all declare their callback as
   returning `unknown` in `lib.es5.d.ts`, and the table said `boolean` — so
   `names.filter(x => x)`, the commonest spelling there is, was reported as
   "expected `boolean` but got `string`".

   These two were **cancelling**. `optionalChainingInArrow` is
   `names?.filter(x => x)`, and the optional-chain bug added `| undefined`
   to the receiver, so the member lookup failed and the callback was never
   judged: the corpus file scored as a TN with both bugs present, and fixing
   either one alone turns it into an FP. That is the reason to fix an FP
   even when the gate is already at zero.
3. **An ARRAY assigned to a numeric index signature.** `var v: { [n: number]:
   Bar } = arr` is ACCEPTED by tsc — every numeric key yields the element
   type — and reached `is_assignable_to`'s `_ => false`. Probed alongside
   the three shapes tsc really does reject there (a function, a `number`,
   and a STRING index signature), all of which still decline.
4. **An overloaded computed-key method.** `lookup_field` returns the FIRST
   declaration's signature, so the new symbol-index arm reported
   `c[Symbol.iterator](0)` against `[Symbol.iterator](x: string)` —
   `symbolProperty40`, TS7-ACCEPTED. Caught by the gate on the first
   measurement of that rule.
5. **A brand in a user-facing diagnostic.** Not a wrong verdict, a
   useless one.

**What was measured and NOT taken.** `arrayLiterals`'s TS2353 needs the
VALUE type of an object-type index signature, and
`try_parse_object_type_with_members` discards it by design — its own doc
comment says index signatures are "kept (keyed by the key type, with an
`Any` value) so the 'any key' meaning survives" — so the array-literal
element check has nothing to compare against. `wideningTuples7`'s TS7010
needs the body of a function EXPRESSION at a `var` initializer, which is
not walked at all (the same shape reports for a function DECLARATION).
`enumShadowedInfinityNaN`'s TS18033 needs the enum's own BLOCK scope, and
an enum is hoisted into `module_.enums` with no record of the block it came
from. And `computedPropertyNames30` was re-probed rather than re-argued:
the distinction CLAUDE.md called "modelling a distinction ONE file draws"
is reproducible — `super()` in an object-literal computed key is TS2466
when an ARROW or function expression lies between it and the constructor
and ACCEPTED directly in the constructor, confirmed across five hand-written
cells — but deciding it needs a "is there a function boundary between here
and the class body" fact, which is a new Parser field with the same
save / clear / restore discipline at fifteen sites that `self.labels`
needs. Filed with the measurement rather than the verdict.

Gates on this head: oracle TP 2616 / MISS in scope 99 / OUT OF SCOPE 19 /
FP 0 / PFLEGAL 0 / TN 1750; `moon check --deny-warn` clean; assertions
3,005 / 3,005; `verify-checker-scaling` 12 of 12 axes within budget
(`private-members` 1.59 against 1.75, `namespaces` 2.06 against 2.15);
mangle-safety 186/186; dce-coverage 31 eliminated / 0 broken;
rule-equivalence 80 equivalent / 0 unsound; graph-walk,
generated-fixtures, scaffolds, examples, mbti-dts, bridge-runtime (0
unbound, 14,630 converter calls at 0 failures) and bridge-enum-returns all
green.

### Batch EG (2026-09-12): four rules, and the one that had to stay ASYMMETRIC

**+6 files at FP 0** (TP 2601 -> 2607, MISS in scope 113 -> 108, PFLEGAL 0,
TN 1750), plus one file retired from `scripts/checker_out_of_scope.txt` as
STALE — `asyncQualifiedReturnType_es5` was declared `no-local-oracle` and
the TS1064 rule below makes it a TP, which the oracle's stale-entry report
named on the first run after the change.

The ranking came from re-running every remaining MISS file through the real
compiler (`checker_miss_rank.mjs`), and it says the tail is all there is:
**67 of 113 files carry exactly one error code and 84 codes have exactly one
file**, with the four largest buckets (TS2322 15 solo, TS2345 10, TS2339 5,
TS2403 4) being variadic tuples, template-literal types, conditional types
and contextual typing. So four small unrelated rules is what this tier looks
like, and three of the four are the applied-in-some-places family.

- [x] **TS2488 for `yield*`** (+1: `YieldExpression6_es6`). The whole TS2488
  apparatus existed and was wired into ONE position:
  `check_iterable_class_protocol` for a class instance and
  `check_forof_non_iterable` for a primitive / union / optional
  `@@iterator`, both called from the `ForOf` arm and from nowhere else.
  `yield*` delegates to an iterable and carries the same obligation, and
  its own arm could not reach it — the existing check there needs a
  declared element type (`ctx.yield_type`) and a generator without a return
  annotation has none, which is every corpus file and most real code. The
  rule also needed `Func` in `is_non_iterable_primitive`, which is the
  real-world shape: `yield* foo` instead of `yield* foo()`, forgetting to
  CALL the generator. Widening that predicate reaches the two `for-of`
  consumers as well and tsc reports both (`for (const v of f)`,
  `for (const [a, b] of [g1, g2])`). `void` / `null` / `undefined` are
  TS2488 too and are deliberately NOT in it: our flow model narrows an
  `any`-typed binding to `Undefined` when its initializer is `undefined`
  (the hazard batch CY's TS2532 records), so an arm for it would report a
  type tsc calls `any`. Eleven cells probed; `string`, an array, a tuple, a
  `Generator` and an interface declaring `[Symbol.iterator]` all stay
  legal.
- [x] **TS18014 one level further out** (+1: `privateNamesInNestedClasses-2`)
  — and this is the one worth reading. `private_brand_declared_on_receiver`
  asked whether the class HOLDING the reference declares the same `#name`,
  which is the one-level version of the question; a `#x` reference resolves
  OUTWARD through every enclosing class body and binds to the first that
  declares it, so the shadowing declaration can sit on a class BETWEEN the
  reference and the receiver. That is the corpus file exactly: `A.#x`
  written inside a `C` nested in a `B` that declares its own `#x`. The
  chain comes from a new `<private-parent:CHILD:PARENT>` sentinel beside
  the `<private-decl:BRAND:base>` one the rule already reads, pushed from
  both class paths through one helper, and `current_class_brand` not being
  reset by a function body is CORRECT here — a private name resolves
  lexically through one.

  **The first version was symmetric and measured +1 TP and −1**, which is
  the finding. Reading an owner match as PERMISSION (returning "suppress"
  when the lexical owner is the receiver's own class) short-circuits the
  staticness check downstream, and `privateNameStaticFieldAccess` and
  `privateNamesUnique-3` are exactly that: `static #foo` declared and
  `x.#foo` written on an instance resolves to precisely that declaration
  and is still an error. So the walk can only ever force a REPORT, never a
  suppression — purely additive, with the old heuristic left in charge of
  everything else. Seven cells now agree with tsc, including the two that
  make the asymmetry load-bearing and the one a symmetric version would
  also have got right (the owner IS the receiver, two levels out).
- [x] **TS1064's named half** (+2: `asyncQualifiedReturnType_es6`, and
  `_es5` out of the scope file). `Parser::record_async_return_type_misuse`
  states the abstention and names the fix in its own header — "the alias
  and the subclass are the SAME named-annotation node at parse time … a
  name declared in-file as a CLASS or INTERFACE cannot be an alias — and is
  filed rather than built". Built. It is the other half of one rule rather
  than a second rule: the parser keeps every non-named annotation and the
  checker, which has the declaration table, decides the named ones.

  Probed cell by cell, because the boundary is not what the message text
  suggests. EXTENDING `Promise` buys an interface or a class nothing —
  being a nominal declaration at all is the error, so `interface I {}` and
  `declare class D {}` report as readily as `class MyPromise<T> extends
  Promise<T>` — while a declaration-merged `interface Promise<T> { extra():
  void }` IS the global `Promise` and must stay silent, which is why the
  NAME is exempt by spelling. That exemption costs the shadowing case
  (`class Promise<T> {}` in-file is TS1064), one MISS for a hole nobody can
  close cheaply. A qualified name is `Named("X.MyPromise")` here, so the
  namespace prefix is reconstructed by recursing `module_.namespaces` — no
  resolver involvement at all. An alias to something other than `Promise`
  (`type P = number`, which tsc reports) is a declared MISS: deciding it
  means resolving the alias body, which is the abstention the parser
  already states.
- [x] **The decorator signature checks on the TYPES** (+2:
  `decoratorOnClassMethod10`, `decoratorOnClassConstructorParameter1`).
  Batch CU compared a member decorator's declared ARITY against the
  runtime's; "can this decorator resolve here" has a second half and it had
  nothing. Two facts, both probed one cell at a time:

  The TARGET. The runtime passes a member decorator the class's INSTANCE
  type for an instance member (`C.prototype`, typed `C`) and `typeof C` for
  a static one and for a CONSTRUCTOR parameter, so `target: Function` can
  never resolve on the first and always resolves on the other two. A
  denylist of exactly one spelling, for the reason
  `is_non_iterable_primitive` is one — `target: Object`, `target: any`,
  `target: C` and `target: Function | Object` are all legal, and "which
  named types does a class instance fail to satisfy" is the whole
  assignability question. Both ways it could be legal are excluded: a class
  with heritage can BE a function (`class A extends Function { @dec m() {}
  }` is ACCEPTED, probed — the guard is not caution), and a file
  redeclaring the NAME `Function` means something else by it. That second
  test is hoisted out of the marker loop, because asking it per marker is
  O(decorators x declarations) — the shape `verify-checker-scaling` exists
  to catch.

  The PROPERTY KEY. A constructor parameter's decorator is invoked as
  `(typeof C, undefined, index)` — there is no member name to pass — so a
  second parameter whose type does not admit `undefined` can never resolve.
  A METHOD parameter's decorator gets the method's name, so the identical
  signature is legal there, and the verdict ALSO depends on
  `strictNullChecks`: with it off tsc accepts, because `undefined` is then
  assignable to everything. Two flags rather than one fact, and both
  measured against the local compiler under explicit `@strictNullChecks:
  false` / `true`.

  Parameter decorators had no `<sig:>` marker at all, which is why both
  facts were unreachable at that position. `skip_param_decorators` SKIPS
  the expression — batch EE's TS1308 blocker — and the same answer applies:
  the head of a decorator must be spelled out, so reading `(called, dname)`
  off the tokens the skip already consumes is complete by construction. The
  owner (`ctor` / `static` / `instance`) rides a Parser field set around
  the ONE `parse_params()` call in `parse_class_body`, and cleared inside
  `parse_param` for everything after the decorator scan — a default value
  or a destructuring pattern can hold another parameter list, and those
  parameters belong to that callable. Clearing once in `parse_param` rather
  than at each nested parser is the point: the alternative is the
  save / clear / restore discipline `self.labels` needs at fifteen sites,
  which is how the applied-in-some-places bug gets written. A parameter
  decorator's runtime arity also turns out to be exactly 3 — probed: 1, 2
  and 4 all report — unlike a method decorator's 2-or-3 latitude.

**Filed rather than built: TS2490** (`for-of15`, +1). "The type returned by
the `next()` method of an iterator must have a `value` property", and the
boundary is fully probed: `next() { return "" }`, `next(): string`,
`next() { return 1 }`, `next() { return { done: true } }` and `next() { }`
all report, while an object literal carrying `value`, an annotation carrying
it, and `next(): any` are accepted — and a `[Symbol.iterator]()` returning
something OTHER than `this` is accepted whatever `next` says, so the
returns-`this` test `check_iterable_class_protocol` already computes is
required. The blocker is mechanical and CHECKED rather than assumed:
`TsClassMethodDecl` has no annotation-presence field, so `next() { return ""
}` (TS2490) and `next(): any { return "" }` (ACCEPTED) are the same node
downstream — the absent-versus-`: any` blocker this file records for TS7031,
TS7022, TS2729, TS2448 and TS2564. The route is equally concrete:
`parse_class_body` already has `had_return_annotation` in hand at exactly
the `next` / `@@iterator` site, because batch DV's TS7022 indirect rule keys
on it there, so the fact needs a Parser-level stack drained per class into a
`<unannotated-return:next>` sentinel — the `self.optional_member_names`
shape, three sites plus the ingestion. Not taken because the batch is
already at +6 and a new parse-time channel for one file is the wrong trade;
recorded with its condition rather than its verdict.

Gates on this head: oracle TP 2607 / MISS in scope 108 / OUT OF SCOPE 19 /
FP 0 / PFLEGAL 0 / TN 1750; `moon check --deny-warn` clean; assertions
3,004 / 3,004; `verify-checker-scaling` 12 of 12 axes within budget
(`private-members` 1.54 against 1.75 — the chain walk adds a constant factor
to an already-declared quadratic, not a new exponent); mangle-safety
186/186; dce-coverage 31 eliminated / 0 broken; rule-equivalence 80
equivalent / 0 unsound; graph-walk, generated-fixtures, scaffolds, examples,
mbti-dts, bridge-runtime (0 unbound, 0 runtime failures) and
bridge-enum-returns all green.

### Perf round (2026-09-11): nothing regressed, and the axis nobody measured is quadratic

Asked "what got slower", the differential says **nothing**, and that is the
first half of the answer. `tscheck` built at `c4fd605` (batch DH, the last
time the cost was measured) against HEAD, 50 commits and ~60 new checker
rules later:

- every one of the seven existing ladder axes is linear at HEAD
  (interfaces 1.08, merged-interfaces 0.96, classes 1.12, exports 0.97,
  type-aliases 1.06, enums 1.03, vars 1.00);
- on real `.d.ts` input HEAD is **0.89–1.02x** of the baseline —
  `typescript.d.ts` full check 198.9 -> 176.4 ms, `lib.dom.d.ts`
  263.7 -> 269.6 ms, parse-only 0.96–1.01x. Sixty rules cost nothing
  measurable, which is the shape a linear checker should have and what
  batch DH also found.

The second half is what the gate could not see. `verify-checker-scaling`
had seven axes, and the rules batches DN–EE added are keyed on lists none
of them grows — so four axes were added: `functions` (overload sets,
three declarations per name), `namespaces`, `private-members` (one class
body, N `#private` members — the span-reading idiom has no cost model of
its own) and `statements` (N statements in ONE function body, where
`vars` puts them at module top level). Two are linear (`functions` 0.87,
`statements` 0.75), `private-members` reads 1.17 on the ladder used here
and is NOT linear — see the correction below — and **`namespaces` is
quadratic: exponent 1.96, 43 ms at 125 namespaces and 2554 ms at 1000.**

It is NOT a regression — the baseline binary is 2.01 at 2557 ms, within
noise of HEAD — so this is long-standing and was invisible for exactly
one reason: no axis grew that list. Ninth instance in this file of an
instrument that could not reach the answer.

The mechanism is structural rather than a nested scan. A namespace body
is re-parsed into its own `TsModule`, so
`check_module_function_bodies_layered` runs once per namespace, and each
run rebuilds its resolver from the OUTER chain — where
`Resolver::ingest_module` recurses through the whole namespace tree
registering every nested declaration under its prefix, and
`collect_module_value_names` recurses through it again (that recursion is
its purpose: a reference inside one namespace may name a binding in a
sibling). N namespaces therefore walk the whole tree N times, twice.

**One half of that is fixed exactly.** The two root-wide backstops
(`declared_value_names`, `any_uninitialized_values`) are functions of the
OUTERMOST module alone, so every namespace was deriving the same answer:
both maps are keyed by name and only ever added to, and the only writer
besides the collectors is the `extra_globals` loop, which writes the same
keys for every sibling. `RootNameBackstops` computes them once at the top
level and hands the objects down. Worth **-22% at n=1000** (2554 ->
1988 ms) and **nothing measurable on real files** (0.94–1.02x), which is
a fact about real input rather than about the fix: the most
namespace-dense `.d.ts` in this repo's own `node_modules` is
`@types/node/fs.d.ts` at 43, where the whole check is 48 ms, and the
ladder does not separate from linear until a few hundred.

The other half — the per-sibling `ingest_module` over the outer chain —
is **declared, not fixed**, with its cost gated rather than suppressed.
Removing it needs a layered resolver: a parent consulted on miss (~200
direct field reads in `expr_check.mbt`) or a journalled overlay that can
be undone per sibling (which must reproduce `ingest_module`'s interface
merging and overload accumulation exactly, in a checker whose budget is
FP 0). Two cheaper things were considered and rejected with their
reasons: sharing one resolver across siblings leaks a sibling's
bare-name declarations into the next one, which can only invent
findings; and copying the outer resolver's maps per sibling is still
O(outer) per sibling, so the exponent does not move — it buys a constant
against a real correctness surface (`namespace_value_decls`'s values are
themselves maps, so a shallow copy shares them).

So the harness grew a per-axis budget: `AXIS_BUDGET` holds `namespaces`
at 2.15 with the mechanism and the real-world cost written at the entry,
and the axis is still GATED — a regression past the accepted cost fails
the run. A budget without a written reason is a suppression list, which
is the defect that retired `docs/checker-priority.md`. `--rungs` was
added at the same time, because an axis whose top rung takes 17 s per
iteration is one nobody investigates: the exponent only needs a 4x
spread between endpoints.

### Perf round, part 2 (2026-09-11): the cost is the CHECK, and it is quadratic in expression DEPTH

The ladder axes all grow a module-wide LIST, and the first round's answer
was that every one of them is linear. That is the wrong question for a
large compile, and mtsc's own help says why: `--no-check` is documented as
"the check is ~95% of a large compile". **Measured rather than quoted** —
on terser's published 1.1 MB bundle, `mtsc --bundle --mangle` is 0.392 s
with `--no-check` and 5.949 s without it, so the type check is **93.4%**
of that compile. Scaling is worse than linear: at 9.1 MB
(`typescript.js`) the same command had not finished after 150 s of CPU,
where linear from 1.1 MB would be ~46 s.

So the next question was which SHAPE is superlinear, and the list axes
cannot ask it. Three depth probes, each one shape real JS is full of:

| shape | 50 / 100 / 200 / 400 (or 250…2000) | exponent |
| --- | --- | --- |
| `o.p.p.…p` member chain | 10.9 / 40.1 / 285.1 / 2431.2 ms | **2.60** |
| `a + a + … + a` binary chain | 10.7 / 24.5 / 82.6 / 311.4 ms | **1.62** |
| nested ternaries | 6.8 / 13.1 / 38.5 / 136.3 ms | 1.44 |

Every module-wide axis is linear and DEPTH is quadratic-to-cubic. Tenth
instance in this file of an instrument that could not reach the answer,
and the sharpest: the harness header says its own axes name "the size of
a module-wide list", which is exactly the dimension that turned out not
to be the problem.

The mechanism is one line at the top of `infer_expr`'s `PropAccess` arm.
It looks the chain up by its synthesised dotted narrowing key first, and
`narrowing_key_for_expr` builds that key by walking the whole receiver
prefix — so a chain of depth d builds d strings whose lengths sum to
O(d²), then HASHES each one for an `env.lookup`, which is the second
O(d²). The `IndexAccess` arm does the same. Neither can succeed unless
flow narrowing actually bound a path key, and that is the cheap question
nobody asked.

**That gate was implemented, measured and REVERTED**, and the numbers are
the point. `ExprEnv::saw_dotted_binding` — a monotonic flag set by every
write into `vars` (`bind`, `narrow` and the snapshot restore, which is
all three sites), never cleared on scope exit, so a stale `true` only
forgoes the shortcut while a stale `false` would change an answer — takes
the member chain from **2492 ms to 78 ms at 400 levels, exponent 2.67 ->
1.30 (32x)**. On the input that matters it is a LOSS: the 1.1 MB real
bundle went 5533 -> 5985 ms, **+8%**, because maintaining the flag means
testing every bound name on the hottest path in the checker. Replacing
`contains(".") || contains("[")` with a hand-rolled scan recovered half
of it and no more — 5631 -> 5830 ms, **+3.5%** — so the shortcut costs
real code 3.5% to save a depth real code does not have. Reverted, with
the reproduction and the mechanism recorded at the site.

Two things that cost a measurement each, both worth keeping:

- **A stray probe was competing.** The first fix2 reading was taken while
  a `tscheck` from the killed 1000-level member probe was still burning
  a core — eight minutes of it. Killing it and re-measuring is what
  turned "+8% is contamination" into "+8% reproduces", and it is the same
  lesson as the overlapping timing spans recorded above: an unexplained
  number is a number to explain before it is a number to act on.
- **The cheap question has to be cheap.** `class-method-dce`'s
  `off_bundle` thunk works because asking costs a map lookup; here asking
  costs a string scan per binding, and there are millions of bindings.
  "Ask the cheap question first" is not a free move — it is a trade, and
  this one priced out.

What would pay is a version that sets the flag only where a path key is
CREATED (the narrowing engine), leaving `bind` / `narrow` untouched:
`env.narrow` / `env.bind` have 49 call sites, so it needs the creation
sites identified rather than the writes intercepted. Filed, not built.
The binary-chain (1.62) and ternary (1.44) exponents are a DIFFERENT
mechanism — the gate moved neither — and are unexplained.

### Perf round, part 3 (2026-09-11): the new axis broke the harness's own cost, and the cap is what found the second quadratic

Two defects, both mine, and the second was hidden by the first.

`namespaces` at the default top rung (4,000) is **~90 seconds per
iteration** — it is the quadratic part 1 records — so adding that axis
took the default run from ~1 minute to **~15**, against a header that
promises the whole run stays near a minute. A harness nobody will wait
for is a harness nobody runs, which is the same failure as one that
cannot reach the answer. An axis only needs a **4x spread between its
endpoints** to separate linear from quadratic, so a quadratic axis can
climb a cheaper ladder and fit the same exponent: `AXIS_RUNGS` gives
`namespaces` 125/250/500/1000, where it reads 1.98–2.00 in 2 s against
2.20 on the default rungs. `--rungs` still overrides everything, and the
row LABELS its own ladder (`namespaces (n=125/250/500/1000)`) or its
milliseconds read as comparable with the others' and they are not. The
full run is back to **1m5s**.

Capping it is what made the first full run finish, and that run reported
a SECOND quadratic — in the axis part 1 had called linear.
**`private-members` is 1.67**: 15.5 / 41.8 / 109.0 / 498.3 ms at
500/1000/2000/4000. Part 1 measured 1.17 and believed it, because the
probe that produced that number ran 125..1000, where the curve has not
turned over yet. A fit is only a fit over the range it was taken on, and
"linear" asserted from a cheap ladder is a claim about the cheap ladder.

The mechanism is a nested scan, not anything structural.
`private_brand_declared_on_receiver` answers "does the receiver class
declare this base name under a DIFFERENT brand" by looping the
receiver's `properties`, `methods` and `private_members` — **per
ACCESS** — so a class whose N members each read one `#name` pays N x N.
The fix is an index (per class, base name -> the brands declaring it,
filled on first use), ~20 lines, and it is FILED rather than taken
because the reach is nil: the quadratic is in the members of a SINGLE
class, and a class with hundreds of `#private` members does not occur —
single digits is the norm, where N^2 is dozens of operations. Declared
at a gated budget of 1.75, so a regression past the measured cost still
fails; that is the same treatment `namespaces` gets at 2.15 and the
reason a budget entry is not a suppression.

### CI on `main` (2026-09-11): the packaging ignore list, and a warning that WAS actionable

`main` was red before #239 and stayed red after it: run 590 at `3036d6f`
— #239's exact base — fails the `test` job at `just verify-scaffolds`, on
one line the toolchain prints and this repo can act on. `moon.mod`'s
`options(exclude: ...)` is deprecated in favour of `.gitignore` /
`.moonignore`, and `scripts/warning_guard.sh` treats any uncoded
`Warning:` as fatal, so the FIRST guarded `moon` call in the script died
— which is also why the three later guard-using steps
(`verify-generated-fixtures`, `verify-examples`, `verify-mangle-safety`)
never ran and say nothing about their own health under that toolchain.

The tempting fix is the wrong one. `warning_guard.sh` already allowlists
four warning codes, and its comment states the standard: those are
"bleeding-edge churn" the deprecation "isn't actionable from this repo".
This one is actionable — the warning names the replacement — so the fix
is to obey it, which also silences it for every harness at once instead
of the one whose allowlist gets edited.

**The semantics are the whole difficulty, and they are a REPLACEMENT, not
an addition**: `.moonignore` overrides `.gitignore` *in the same
directory*, so a root `.moonignore` carrying only the three
development-only paths takes the root `.gitignore` out of the packaging
walk entirely. Measured rather than reasoned about — the archive went
from 350 entries to 415, and all 65 additions were
`examples/moonbit-to-typescript/_build/**`, a tree only `.gitignore`'s
`_build/` had been keeping out. With the output patterns carried across
as well, `moon package --list` produces a file list **identical** to the
pre-change baseline, 350 entries, diff empty.

Two things were probed rather than assumed, one of them a hazard the old
key could not have had:

- **`.moonignore` does not hide a package from the BUILD.**
  `src/cmd/tscheck` is in it and `moon build --target native
  src/cmd/tscheck` still relinks the binary `verify-checker-soundness`
  needs. `options(exclude:)` was packaging-only; an ignore file plausibly
  is not, and that would have taken the soundness gate down.
- **The warning really is gone, on the toolchain that emits it.** Local
  moon is 0.1.20260819 and prints nothing here, so the fix was verified
  against `latest` (0.1.20260904) installed into an isolated `MOON_HOME`:
  with the old `moon.mod` the repo's own guard exits 1 naming the
  deprecation, with the fix it exits 0. A minimal probe module confirms
  the exclusion still happens under that toolchain — same archive
  contents with `.moonignore` as with `options(exclude:)`.

`verify-scaffolds`, `verify-generated-fixtures` and `verify-examples` all
pass locally after the change.

### Batch EE (2026-09-11): section G's last three rows — every blocker in it was wrong

+2 files at FP 0 (TP 2598 -> 2600, MISS in scope 116 -> 114, PFLEGAL 0).
With this, **all five of `UNSUPPORTED.md` section G is closed**, and the
finding is about the TABLE: a blocker written down is a claim with a date
on it, and not one of the five survived being probed. Two had been
dissolved by later work that was not aiming at them, one was true of an
approach nobody had to take, one named only one of two routes to the fact,
and TS2393's was not a blocker at all.

- [x] **TS1308: `await` inside a parameter decorator** (+1:
  `decoratorOnClassMethodParameter3`). The recorded blocker —
  `skip_param_decorators` discards the expression, so the `await` never
  reaches the AST — is TRUE, and beside the point: a TOKEN sighting over
  the range that skip already consumes needs no AST, because every `await`
  must spell `await`, which makes the scan complete by construction (the
  same argument the `#private` rules use for a class-body span). The
  region is the cell reasoning gets wrong: a parameter decorator is
  evaluated where the CLASS is defined, so the async context that matters
  is the ENCLOSING function's and the METHOD's own `async` is irrelevant —
  `function fn() { class C { async m(@dec(await v) a) {} } }` and the same
  with a plain `m` are both TS1308, while `async function fn` and
  `const fn = async () => …` are both ACCEPTED. `in_function` is required
  because at module / script top level tsc gives TS1375 / TS1378, two
  codes this rule does not claim. Eight cells probed, all agreeing.
- [x] **TS2393: duplicate function implementation** (+1:
  `multipleDefaultExports04`). There was no blocker: `<fn-impl:NAME>` is
  pushed once per IMPLEMENTATION and the consumer built a
  `Map[String, Unit]`, so the COUNT the rule needs was thrown away at the
  point of use. Counting instead gives it, reported BEFORE the overload
  rules and taking the name out of them — the two shapes are mutually
  exclusive, and `function d(a: number) { }` beside
  `function d(a: string) { }` used to get "this overload signature is not
  compatible with its implementation signature", the right file for the
  wrong reason. The marker also had to be added at the FOUR export sites,
  which had none: it sat at the two module-level sites that parse a bare
  `function` declaration, so `export default function f() { }` twice
  recorded no implementation at all. One of those four passes `false`
  rather than `last_function_bodiless` and says why — that arm parses
  through `parse_function_expr`, which does not set the flag, so reading
  it would read whatever the previous function left behind. Eight cells
  probed: four fire, and an overload set, an ambient pair, two SCOPES and
  two different names stay silent.
- [x] **TS2708 at a `typeof` TYPE position** (+0 files, and that is the
  honest half). `check_undefined_name` has judged the VALUE spelling
  (`var q = A`) for some time and a `typeof` type never reaches it, so
  `var m: typeof A` — the spelling a `.d.ts` uses — was silent.
  `var m: typeof A`, `type T = typeof A`, `var m: typeof A.P` (the base
  SEGMENT is what matters) and the namespace-nested form all report now,
  while a namespace carrying a runtime `export var v = 1` is ACCEPTED,
  which is the cell that keeps the rule off real `.d.ts` namespaces. It
  needs no `env` guard unlike the value path, and the reason is written at
  the site: the sweep reads only module- and namespace-level declaration
  types, never a function body, so a local shadow cannot reach it.
  `importStatementsInterfaces` is STILL a MISS, exactly as the row's other
  half predicted — its `var m: typeof a` goes through an `import a = A`
  alias, and whether such an alias binds a value depends on the TARGET,
  which is not resolved at parse time.

### Batch ED (2026-09-11): a modifier may not be followed by a newline, and two fields of one name

+1 file at FP 0 (TP 2597 -> 2598, MISS in scope 121 -> 117) plus one file
declared OUT OF SCOPE (117 -> 116, OUT OF SCOPE 19 -> 20). TWO independent
bugs that both had to be fixed to reach one corpus file, and each is worth
more than the file.

- [x] **A class-member modifier spelled as a CONTEXTUAL KEYWORD may not be
  followed by a line terminator.** The grammar writes
  `accessor [no LineTerminator here] ClassElementName`, so
  `class C { accessor` / `a }` declares TWO members — one named `accessor`,
  one named `a` — and eating the keyword as a modifier LOSES a field from
  the emitted class as much as from every checker rule that reads the
  member list. Which modifiers this covers was probed one at a time,
  because the answer is not "the TypeScript-only ones": `readonly`,
  `public`, `private`, `protected`, `abstract`, `override`, `async`,
  `accessor` and `get` / `set` all become a member name across the break,
  and **`static` — the one the ECMAScript grammar spells with a reserved
  word — does not**, so `static` / `accessor` / `c` on three lines is a
  STATIC field named `accessor` plus an instance field `c`. One test in
  `can_consume_class_modifier`, with the `static` site passing
  `allow_line_break=true`; the default is the RESTRICTIVE answer so a
  modifier added later inherits the rule. The `get` / `set` arm spells its
  conditions inline rather than calling that helper, which is why the rule
  had to be written at both — the applied-in-some-places family, found by
  grepping the helper's call sites and then noticing a twelfth spelling
  that does not use it.
  `declare` IS that twelfth spelling and is deliberately NOT fixed: it has
  its own TOKEN kind, so the modifier arm never sees it and the `Declare`
  arm advances with no guard of any kind. Gating it makes the member NAME
  a `Declare` token the field-key parser rejects, so the whole class stops
  parsing — a PFLEGAL, which is worse than the MISS. Measured, reverted,
  and the real fix (teach the key parser that token) is filed.
- [x] **`nf >= 2`: two DATA FIELDS of one name are a duplicate**
  (TS2300, +1: `autoAccessor11`). `class C { q = 1; q = 2 }` was SILENT,
  and the clause that decides it was already written twenty lines below —
  in the PRIVATE-name loop, with the reason in its own comment ("the only
  legal repeat is a getter + setter pair"). The public loop's condition
  was `(nf >= 1 && nf + ng + ns + nm > nf) || ng >= 2 || ns >= 2 ||
  ((ng >= 1 || ns >= 1) && nm >= 1)`, and every clause misses the case
  where the repeats are ALL fields. Fifteen cells probed and all now agree
  with tsc: two fields, two annotated fields, field + same-named method,
  two getters, field + `accessor` field and `#q` twice all fire, while
  instance + static (keyed apart as `name|s` / `name|i`), a get/set pair,
  an overload set, different names and different classes stay silent. A
  computed key abstains, which is a declared MISS (tsc reports the literal
  spelling). The `#private` diagnostic had to be taught to print `#q`
  rather than `__private_brand__0__q` — the same lesson TS7008 records,
  since a diagnostic naming a brand is one nobody can act on, and the
  private loop turns out to be dead for a runtime class because the
  lowering renames `#q` before the member list is built.
- [x] **The probe was attributing OTHER files' diagnostics to the probed
  file**, and that is what found the out-of-scope entry.
  `scripts/lib/tsc-probe.mjs` calls `getSemanticDiagnostics()` with no
  argument, which returns EVERY file's diagnostics — so
  `objectTypeWithStringIndexerHidingObjectIndexer`, a 33-line source, was
  ranked by `TS2411(123,5)`, a line it does not have. Its
  `interface Object { [x: string]: Object }` augmentation plus
  `@skipDefaultLibCheck: false` makes tsc type-check `lib.es5.d.ts`
  ITSELF, and every diagnostic lands there; the file's own source is
  error-free, so there is nothing a rule could flag. Declared out of scope
  under a new `lib-diagnostic` kind. `probe()` now splits `diags` (this
  file, plus file-less globals like TS2318) from `otherFiles`, which
  `tsc_probe.mjs` reports on its own line, and re-running the whole MISS
  list says this is the ONLY one of the 118 where nothing is in scope —
  its sibling `objectTypeHidingMembersOfExtendedObject` really does carry
  an in-file `TS2411(13,5)` and stays in the backlog. Ninth instance of
  the measuring instrument carrying the same substitution bug as the code.
- The re-ranking behind this batch is the honest answer to "what is left":
  **116 files, 70 of them with exactly ONE error code and 84 codes with
  exactly one file.** The four largest buckets are TS2322 (14 solo),
  TS2345 (10), TS2339 (5) and TS2403 (4), and opening TS2403's four says
  what the count cannot: one needs spread-type computation
  (`spreadUnion2`), one needs types inferred through OVERLOAD resolution
  (`enumAssignabilityInInheritance`, whose `var r4 = foo16(E.A)` has no
  annotation at all — the annotated shape `var r: E; var r: Object` is
  ALREADY flagged), one needs `this`-type resolution plus the rule inside
  a method BODY (`typeOfThisGeneral`), and one is contextual typing. Four
  files, four unrelated mechanisms.

### Batch EC (2026-09-11): the "unwired" rows of UNSUPPORTED.md section G

+3 files at FP 0 (TP 2594 -> 2597, MISS in scope 121 -> 118, PFLEGAL 0).
Section G is the table of rules blocked on a MECHANICAL fact rather than on
machinery, and the batch's reusable finding is about the table itself:
**a blocker written down is a claim with a date on it, and both of these
had been removed by earlier work that was not aiming at them.**

- [x] **TS7031 / TS7018: a nullish literal where a type must be inferred**
  (+2: `wideningTuples5`, `usingDeclarationsWithObjectLiterals2`). ONE rule
  with two spellings — with `strictNullChecks` off, `null` and `undefined`
  widen to `any`, so under `noImplicitAny` an inference from them is an
  error. Which CODE applies is decided by the BINDING, matching tsc:
  `var {a} = {a: null}` is TS7031 on `a` and NOT TS7018 on the property, so
  a pattern runs only the element half and an `Ident` binding only the
  object-literal half. It lives in the PARSER because the fact it needs is
  not in the AST (`TsStmt::Let` / `Const` / `Var` carries a `TsType` where
  an absent annotation and an explicit `: any` are the same `Any`, and
  `var [a, b]: any = [undefined, null]` is ACCEPTED) — and the recorded
  blocker was half wrong: `last_var_decl_annotated` already carries the
  annotation fact, read by `parse_var_decl_item` BEFORE the initializer is
  parsed so a nested declaration cannot make this one look annotated. Only
  `strict_null_checks` had to be added to the Parser, nine lines, and both
  flags being required is what keeps the rule off real code: a
  directive-less file defaults to `strictNullChecks: true`, which every
  `.ts` / `.d.ts` the bridge parses is, so it cannot fire there at all.
  Three boundary cells read the other way round from the message text and
  were probed one at a time: a DEFAULT supplies the type, so
  `var [a = 1] = [undefined]` and `var {a = 1} = {a: null}` are ACCEPTED —
  true even for `null`, which does not trigger a default at runtime;
  `var a = undefined` is legal and `var o = [null]` is TS7005 on the
  VARIABLE, so an array element is never reported; and a renamed property
  reports the LOCAL name while a hole keeps its position. The abstentions
  each lose a finding rather than invent one — a REST element, a
  `satisfies`, `null!`, a computed key, and every non-declaration position
  an object literal can sit in, where a call argument's literal is
  CONTEXTUALLY typed and legal and this site cannot tell the two apart.
  An unannotated declaration has no contextual type by construction, which
  is the whole reason the rule is sound where it is. It needed TWO sites,
  which is the applied-in-some-places family taken on the first pass
  instead of discovered a batch later: `using` at statement level routes
  through `parse_var_decl_item`, and the BLOCK-statement `using` path is
  its own parser — the one every `usingDeclarations` conformance test
  actually writes, so a recorder at the first alone reached neither
  corpus file.
- [x] **TS2331: `this` in a namespace body** (+1:
  `decoratorOnClassMethod11`). The recorded blocker was "a new Parser field
  needs the save / clear / restore discipline `self.labels` needs at
  fifteen function-body sites", which was true of the approach it
  considered and had been dissolved ONE BATCH EARLIER: batch EB built
  `this_region_walk_stmt` for the `globalThis` rule, and its region — an
  arrow is descended into, a `function` body and a class body are not — IS
  TS2331's region. So the rule is a second `ThisRegionVisitor` over the
  same walk rather than a walk of its own, and the visitor grew a `bare`
  callback beside `prop` because the two consumers ask different questions
  about the same node: `globalThis` wants the property read off `this`,
  TS2331 wants the `this` and never reaches the property. Twelve cells
  probed, all now agreeing with tsc: the arrow, `this.q`, `var x = this`,
  an arrow in an arrow and a NESTED namespace all report, while
  `function g() { return this }` and `const g = function () { … }` inside a
  namespace are TS2683 (a different diagnostic — descending would trade a
  MISS for a false positive), a class method and an object-literal method
  are ACCEPTED and fall out of the walk for free, and script top level is
  TS7041, which is why the caller gates on `outer_modules.length() > 0`.
  A class DECORATOR is the second position and came along, since a
  decorator expression is evaluated where the class is DEFINED — the same
  argument TS2660 already makes for `super` — reading `module_.classes`
  only and never `local_classes`, because a class declared inside a
  function is decorated in that function's scope and tsc gives TS2683
  (probed). The MEMBER-decorator spelling is the corpus file and needed a
  different mechanism, also already present: member decorator expressions
  never reach the AST, and a namespace body is parsed by a FRESH `Parser`
  that cannot know it is one, so the class parser leaves a
  `<this-in-decorator>` sentinel and `parse_namespace_decl_with_mode`
  converts it where the context is known — the mechanism TS1063 / TS1319
  already use, with an unconverted sentinel staying a `<`-prefixed marker
  the checker's grammar loop skips. `decorator_mentions_super` became
  `decorator_mentions_name(d, name)` rather than gaining a twin, since
  "does this decorator expression mention NAME" is one question and a
  second copy of those arms is the family this repo keeps finding.
- Three of section G's rows stay filed, each with its blocker re-verified:
  TS1308 (`skip_param_decorators` discards the expression), TS2708's
  `typeof` type position (two independent channels — a `typeof` TYPE
  position never reaches `check_undefined_name`, and `import a = A` needs
  the alias TARGET resolved before "is it instantiated" can be asked), and
  TS2393 (detected, reported with TS2394's message; 0 corpus files).
  TS2331's OTHER corpus file, `typeofThis.ts`, also stays a MISS and the
  reason is exact: its error is `typeof this.no` in a TYPE position, and
  `parse_typeof_type_query` has no `This` arm, so the operand is skipped
  by `skip_typeof_operand` and the annotation collapses to `Any` before
  any checker can see the `this`.

### Batch EB (2026-09-11): the four items `src/checker/UNSUPPORTED.md` asked for

+8 files at FP 0 (TP 2586 -> 2594, MISS in scope 129 -> 121, PFLEGAL 0).
`src/checker/UNSUPPORTED.md` is the new companion to
`docs/checker-triage.md`: the triage classifies the backlog by the
MACHINERY a rule needs, and that file shows the CODE a user would write,
every snippet minimized and run through both `tscheck` and the real
compiler so each entry is a measured gap. Writing it is what produced
this batch's targets — and it corrected itself twice while being written,
both times the label-for-objective substitution: **TS2403 and TS2411 read
as gaps because four and two MISS files raise them, and
`var x: number; var x: string;` and
`interface I { bar: number; [x: string]: string }` are ALREADY flagged.**

- [x] **B: a call to an overload set whose only accepting member is
  GENERIC** (TS2464, +2: `computedPropertyNames9_ES6` / `_ES5`). Filed as
  "overload resolution", a Tier 1 row — and what was broken is much
  narrower. The members are already ingested as a Union of `Func`s and
  `infer_call` already selects by argument assignability; the type
  parameters are recorded per NAME in `func_type_params`, which is
  OVERWRITTEN per declaration, so for `f(s: string); f(n: number);
  f<T>(x: T); f(x) {}` it holds the IMPLEMENTATION's empty list. The
  generic member reached the union arm as `Func([Named("T")],
  Named("T"))`, matched nothing, and the call came back carrying an
  unresolved `T` that every downstream check reads as unknowable.
  - `func_overload_type_params` is the union across a name's
    declarations, kept as its OWN map because `func_type_params`'
    existing consumers want the per-declaration answer.
  - Tried only after every non-generic member has failed, which is also
    TypeScript's order — so a call a concrete overload accepts keeps the
    answer it already had, and `f("a")` / `f(1)` are in the test as the
    controls.
- [x] **C: `globalThis` and the script-level `this`** (TS2339, +3:
  `globalThisReadonlyProperties`, `emitArrowFunctionThisCapturing{,ES6}`).
  Three findings, two of them about code already present.
  - The READ form (`var r = globalThis.y`) was all the rule judged. The
    WRITE form was missed at **both** of its spellings —
    `globalThis.y = 4` at the top of a list is a `PropAssign` STATEMENT
    and the same line inside a function is `Expr(PropAssignExpr(…))`, and
    both arms walked the RECEIVER and the VALUE while the property NAME
    sat in the node itself, tested by neither. The batch DS parser fact
    again, and the legal neighbour is four lines away in the corpus file:
    `globalThis.x = 3` beside a `var x` IS legal.
  - A top-level `function f() { globalThis.y = 4 }` body was not reached
    at all, because a top-level function is parsed into `module_.funcs`
    and not into `top_level_stmts`. Buys no corpus file.
  - `this` at script scope IS `typeof globalThis`, including inside an
    ARROW — which is where both arrow files put it. It gets its OWN
    region-scoped walk rather than a flag threaded through the
    `globalThis` one, because the two questions have different REGIONS:
    `globalThis.x` means the same in any body, `this` means the global
    object only where nothing has rebound it. An arrow keeps it, a
    `function` does not (tsc reports TS2683 there — a different
    diagnostic), so the walk stops at every `function` and class body and
    loses a finding rather than inventing one.
  - **`this.name` is an error and `this.zzz` is not**, which reasoning
    gets backwards: an undeclared property may be CREATED through `this`
    at script scope. `name` is `declare const name: void` in
    dom.generated.d.ts, and a block-scoped LIB global is not a
    `globalThis` property either. `is_lib_dom_blockscoped_value` is
    generated from the lib sources for that — one name in the whole set
    today — and is DOM-scoped rather than unioned because
    `webworker.generated.d.ts` declares the same name with `var`; the
    rule abstains when an explicit `@lib:` list leaves dom out, and a
    name the file declares itself wins.
  - My own MEASUREMENT was wrong once here and the pattern is this
    file's: grepping for `does not exist on` counted the EXISTING
    class-member check's report on `class C { m() { this.name = 1 } }`
    and read it as a false positive of the new rule. Grepping the path
    prefix instead shows the walk never enters a class body.
- [x] **E: intersection comparability** (TS2367, +2:
  `equalityWithIntersectionTypes01`, `intersectionNarrowing`). Both halves
  existed, in the wrong place.
  - `cast_shape_fields` plus "each side requires a property the other
    lacks" is the test the `as` path (TS2352) has used for
    `typeAssertionsWithIntersectionTypes01` all along, and the equality
    arms never asked. It is `shapes_definitely_disjoint` now and both
    call it. `==` gets it too, restricted to object shapes: `==` coerces
    a primitive against an object (`{} == "[object Object]"` is true)
    while object against object is reference equality, where `===`'s
    answer holds.
  - `equality_primitive_family` gained an `Intersection` arm, because
    every value of `T & number` is a number whatever `T` is — that is
    `intersectionNarrowing`'s `f5`, and it fires there and on none of
    f1-f4, which are legal narrowings. `Any` / `Unknown` / `Never` in a
    part abstains outright: `any & number` IS `any`, so answering
    "number" would report a comparison tsc accepts.
- [x] **F: a computed enum member's initializer type** (TS18033, +1:
  `enumErrorOnConstantBindingWithInitializer`). The blocker was NOT the
  type, which is what the triage assumed: the checker already infers
  `string | number` for `const { value = "123" } = thing` and `{}` for a
  block-local `let Infinity = {}` — measured before writing anything.
  What is missing is that the enum AST keeps FOLDED LITERAL values only,
  so the initializer expression never reaches the checker. A
  `<enum-init-name:NAME>` marker carries the one shape worth deciding (a
  bare identifier) and the checker resolves it in the top-level env,
  which is where a DESTRUCTURED binding lives — `resolver.globals`
  records only `Var(Ident(n), ty, _)`.
  - The definitely-non-numeric set excludes LITERAL types, and that is
    the cell reasoning gets wrong: `declare const s: string` is TS18033
    while `const s = "a"` — type `"a"` — is **ACCEPTED**, because a
    string literal initializer is how a string enum member is written.
    `Infinity` / `NaN` / `any` / a sibling member abstain by not
    resolving, all four probed.
  - Placing the check needed one more fix: the top-level statement walk
    is guarded on `top_level_stmts.length() > 0`, and a file of exactly
    `declare const s: string` plus an enum has none, so the whole block
    was skipped.
- [ ] **STILL MISSING in those four groups**, each with its blocker
  measured rather than guessed:
  - `(typeof globalThis)["\"ambientModule\""]` — an `IndexedAccess` on
    `typeof globalThis` in a TYPE position reaches no name check, and
    firing there needs the declared-globals set to be complete in type
    position.
  - `enumShadowedInfinityNaN` — SCOPE, not type: its `let Infinity = {}`
    is in a block with the enum, and an enum is hoisted into
    `module_.enums` with no record of the block, so the shadowing binding
    is not in the top-level env.
  - `neverIntersectionNotCallable` — needs intersection REDUCTION to
    `never`, which is E's machinery rather than B's.

### Batch EA (2026-09-11): three rules off the compiler-probed long tail

+3 files at FP 0 (TP 2583 -> 2586, MISS in scope 132 -> 129, PFLEGAL 0).
The ranking was re-made the way batch CM's was — every remaining MISS run
through the real compiler under its own harness header, grouped by the
codes it actually produced — and it says the same thing as last time, one
notch further along: **132 files, 85 codes with exactly one file each**,
and the four biggest buckets (TS2322 14 solo, TS2345 10, TS2339 7,
TS2403 4) are variadic tuples, template-literal types, conditional types
and contextual typing. Every 2-file cluster left is expensive — TS2411
needs `Object`'s own members modelled, TS2367 intersection assignability,
TS2464 and TS2349 overload resolution, TS18033 a destructured binding's
type, and TS2466's two are the pair batch CL rejected with evidence. So
the batch is three unrelated single-file rules, which is what this tier
looks like now.

- [x] **TS2526** — a `this` TYPE outside a non-static member
  (`thisTypeErrors2`). Purely a question about which declaration the type
  is written in, so it is a checker-side walk over
  `constructor_params` plus every static member's signature, with no
  parser change and no scope model. **Both cells reasoning gets wrong
  were probed one spelling at a time.** A constructor's PARAMETER LIST is
  an error and its BODY is not — `constructor() { let x: this = this }`
  is ACCEPTED — and NESTING does not open a new `this` context, so
  `constructor(a: { m(): this })`, `Array<this>`, `this[]` and
  `(x: this) => void` all report. Silent for every instance member and
  every interface member, a construct signature included
  (`interface I { new (a: this): void }` is ACCEPTED, which reads like it
  should not be).
  - `type_mentions_this_type` is written out rather than reusing
    `type_references_any(ty, ["this"])`, because that walk has no
    `CallableMeta` arm and `CallableMeta` is what the type parser wraps a
    callable with an OPTIONAL parameter in — the sixth time a wrapper
    node's missing arm would have cost something here, and the first
    where the cost was only a MISS.
  - Three positions tsc reports and this deliberately does not, each with
    the reason at the site: a type ALIAS body (`type T = { m(): this }`
    is TS2526, and the bridge generator runs `check_module` over real
    `.d.ts` input, where a false positive costs generation rather than a
    conformance file), a top-level `declare function f(a: this)`, and a
    nested function's return type inside a constructor. The last two need
    the `this`-rebinding scope fact TS2331 is deferred on.
- [x] **TS2767's second channel** — an iterator's `return` field
  initialized to something that cannot be a function (`for-of30`). Fifth
  batch in a row whose target was a recorded ABSTENTION, and the second
  where the stated blocker was real but named only one of two routes to
  the fact. The comment was right that the class parser records `Any` for
  an unannotated field and that firing on `Any` would flag
  `return = () => …`, the legal spelling of the same member — and the
  INITIALIZER was in `instance_field_inits` the whole time, where
  "definitely not callable" is decidable from the expression's shape.
  - An ALLOWLIST of literal forms, so an unclassified spelling is a MISS
    rather than a finding — which is the direction that matters, because
    `return = 0 as any` is `any` and tsc ACCEPTS it, so peeling `As`
    would have been a false positive. `null` / `undefined` are excluded
    for the same measured reason: with `strictNullChecks` off they widen
    to `any` and `return = null` is accepted.
  - **The batch-DF test had that exact source in its SILENT list** —
    eleventh test in this repo found asserting a gap rather than a
    behaviour. It fires in the new test; the three real legal neighbours
    (`() => …`, `function () {…}`, `null`) took its place.
- [x] **TS2842** — an unused renaming (`{ a: b }`) in a parameter list
  with no BODY (`destructuringInFunctionType`). A renaming binds a name
  and a bodiless signature has nowhere to read it, which is the whole
  rule and the reason it lives in the parser. Probed: a function TYPE, a
  constructor type, `declare function`, a `declare class` member, an
  interface method, an object-type member, a class overload signature, an
  `abstract` member and a function-typed `const` ALL report, while a real
  function, a method with a body and an arrow are ACCEPTED.
  - **The trap is that one of the legal spellings parses through the very
    same code as one of the illegal ones, and both are in the corpus
    file.** `type F3 = ([{ a: b }, { b: a }]) => void` is TS2842 twice;
    `type T3 = ([{ a: b }, { b: a }])` is a parenthesized TUPLE TYPE
    where `{ a: b }` is an object type whose member `a` has type `b`, and
    it is LEGAL. Both reach `parse_paren_or_function_type`'s parameter
    loop, so the renamings are held in a local and become findings only
    after the `=>` commits. `last_param_pattern_renamings` is the "last"
    slot that carries them out of `parse_declare_param_name`, the same
    idiom as `last_function_bodiless`.
  - Two detectors for one question, because the two parameter parsers
    keep different things: `parse_param` builds a real `TsBinding`, and
    `parse_declare_param_name` brace-matches past the pattern and keeps
    nothing at all. The message comes from one place. Six call sites, and
    they are the set TS2371 already uses — evidence that it is the right
    set rather than a guess.
  - The AST half is the more precise of the two: a DEFAULT lives in its
    own field there, so `{ a: b = 1 }` (which tsc reports) is a finding,
    while the token scan has to stop at the `=` or an object literal
    inside an initializer would read as a pattern. That is a declared
    MISS for the function-type spelling only.
- [ ] **TS2708 has a SECOND hole, independent of the alias one already
  recorded.** `var m: typeof A` for a non-instantiated namespace is
  silent while `var q = A` fires — measured, not assumed — so a `typeof`
  TYPE position never reaches `check_undefined_name` at all.
  `importStatementsInterfaces` needs BOTH that channel and the alias
  target lookup (`import a = A` lands in `type_aliases`, and whether the
  TARGET is instantiated is the second lookup the rule's own comment
  says it does not do), which is two new channels for one file. The
  `typeof` half is worth taking on its own terms: it is the position a
  `.d.ts` uses.
- [ ] **TS1308 in a decorator expression** (`decoratorOnClassMethodParameter3`)
  stays a MISS for a mechanical reason: a PARAMETER decorator's
  expression is discarded by `skip_param_decorators`, so the `await`
  inside it is never parsed. The boundary is probed and exact — the
  decorator runs in the scope OUTSIDE the class, so
  `async function fn() { class C { async m(@dec(await v) a: number) {} } }`
  is ACCEPTED and the same class inside a non-async `fn` is TS1308.

### Batch DZ (2026-09-08): the strict-null bucket, and what it really holds

- [x] **TS18030** — an optional chain cannot contain private identifiers.
  +1 file (TP 2582 -> 2583, MISS in scope 133 -> 132, FP 0, PFLEGAL 0).
  Purely syntactic, so it lives in `parse_postfix`'s chain loop: one
  chain-local `saw_optional_in_chain` flag, set where `?.` is consumed and
  tested at BOTH sites that read a chain property, so `this?.#b` and
  `this?.a.#b` are one condition rather than two. Chain-local (not a Parser
  field) is what makes the two subtle legal neighbours automatic —
  `this?.getA(o.#b)` and `(this?.c).#b` each parse their inner expression
  in a nested invocation of the same loop, so neither inherits the flag.
  - The probe earned itself back on `(this?.c).#b`: tsc reports TS2532
    there and NOT TS18030, so parenthesizing ends the chain. Both answers
    were plausible from the message text. All seven spellings now agree
    with tsc exactly (3 fire, 4 silent).
- [x] **The bucket label was wrong about every file in it.** "strict-null /
  narrowing" is 5 files and 5 unrelated kinds of work — see
  `docs/checker-triage.md` for each. Not one is fixed by a strict-null or
  narrowing rule. Eighth instance of a label standing in for the
  objective, and the first where the bucket was small enough that the
  count looked trustworthy.
- [ ] **TS2331** (`this` in a namespace body). Deferred on a measured
  cost, not on difficulty. The boundary is exact and probed: an arrow
  inside a namespace body fires at any nesting depth, a `function`
  declaration or expression inside one does not, a class method does not,
  script top level does not, and module top level does not. `in_function`
  cannot express it (true inside arrows), so it needs a new
  `this`-rebinding field with the save / clear / restore discipline
  `self.labels` needs at fifteen function-body sites — the shape that
  produces the applied-in-some-places bug, for +1 file. Take it together
  with a refactor that centralizes those fifteen sites.

## Bridge runtime: the generated JS was never executed (2026-09-07) — DONE

- [x] **`instanceof` against an erased TypeScript name.** A tagged-union
  case whose payload is `Named(N)` was discriminated with `value instanceof
  N` whether or not `N` exists at runtime.
  `tagged_union_named_constructor_name` asks whether a name is PascalCase
  and MoonBit-spellable — a NAMING test — and the discriminator read that as
  licence to emit the predicate, so an interface, a type alias, an enum and
  a type parameter all got one. **411 unbound sites over 197 distinct names
  across the generated corpus, against 14 globals and 4 bound; 2,126 of
  2,530 converter calls threw `ReferenceError`.** The names say it: `T` /
  `TResult` / `TDriverParam` are type parameters, `PathLike` / `Booleanish`
  are aliases, `ScriptTarget` / `ModifierFlags` are enums, `Expression` /
  `SourceFile` / `Identifier` are interfaces.
  - The rule ALREADY EXISTED. `moonbit_inline_union_runtime_named_ok` is the
    global-constructor allowlist and its own doc comment states this exact
    hazard; it was consulted at ONE site and there only when the union has a
    FUNCTION member, because the call sits inside `if func_members > 0` —
    a condition that is right for the check next to it (a second function
    case collides on `typeof === "function"`) and unrelated to whether a
    sibling's `instanceof` resolves. Same shape as the namespace
    `if outer_modules.length() == 0` case: one item's condition inherited by
    others that do not share it.
  - The two converter DIRECTIONS are now emitted independently, which is the
    part that makes declining cheap: `_to_js` reads `$tag` and needs no
    predicate, so parameters keep their types; only `_from_js` is withheld,
    with a note naming the case. Before the split a declined `_from_js` took
    the sound `_to_js` down with it.
  - Costs nothing measurable: the bridge quality report is identical on
    every metric (3 unsupported exports, 5409 declared functions, 2580
    declared types, 5673 JSValue refs), because `ffi_tagged_union_return_is_safe_to_wrap`
    already refused to CALL these converters. The 411 sites were dead
    broken code — which is also why no harness noticed.
- [x] **`scripts/verify_bridge_runtime.mjs`** (`just verify-bridge-runtime`,
  wired into `just ci`). Every other bridge harness asks whether a generated
  package COMPILES (`verify-scaffolds`, `verify-generated-fixtures`,
  `verify-examples`) or whether a REJECTED export is budgeted
  (`bridge_quality_report.sh`). **Nothing asked whether the code emitted for
  an ACCEPTED export runs.** Two checks, because neither alone is complete:
  static — every `instanceof X` must have `X` a JS global or a binding of
  that module, which sees a site whichever arm a probe value reaches;
  runtime — import each of the 86 generated bridge modules and call every
  exported `_from_js` over a value battery, which is what proves the static
  list is real rather than a grep artifact. 411 sites and 2,126 failures ->
  0, with 363 calls still exercised so the harness is not merely emptied.
  - The one fixture with live `_from_js` calls
    (`scaffold_ts_to_moonbit_heterogeneous_union`) is `boolean | "boundary"`
    — no `Named` member at all. That is why the bug survived: not one
    fixture in the corpus put a named type in a return position.
- [x] **A tagged-union RETURN type the wrapper never builds** — DONE, 4
  sites -> 1 (the residual is the pre-existing `.mbti` duplicate below).
  The reverted attempt measured as a no-op for TWO reasons, and neither
  was the predicate: `unbuildable("ServerType")` was TRUE all along, which
  a `println` settled in one run after two rounds of reasoning had got it
  wrong.
  - **The `CallableMeta` wrapper.** The walk had `Named` and `Func` arms
    and no `CallableMeta`, so a value whose type carries an OPTIONAL
    parameter fell through the catch-all untouched. That is why the
    sibling pair disagreed: `get_create_adaptor_server`'s `(Options) ->
    ServerType` widened and `get_serve`'s `(Options, ((AddressInfo) ->
    Unit)?) -> ServerType` did not. `ffi_type_name` peels the same wrapper
    on its own FIRST line — a walk that decides a type has to peel every
    wrapper the renderer peels, or it decides a different type from the
    one that gets printed. Fifth wrapper-node fail-open arm in this repo,
    exactly the third the `PureCall` note says to expect after the second.
  - **A renderer the substitution missed.** Ten sites were found by
    grepping the assignment `let return_type = ffi_type_name(state, …)`,
    and `ffi_callable_value_decl_to_moonbit` — the renderer for the direct
    call form of a callable value, which is what emits `serve(...)` —
    spells its local `return_type_src`. Writing a shared
    `ffi_output_type_name` helper specifically to avoid the
    applied-in-some-places family, then applying it by textual match on a
    variable NAME, is that family inside the fix for it. The census is by
    ARGUMENT now (`func.return_type` / `import_.return_type` /
    `value.type_` / `return_type`), which is what it should have keyed on.
  - **The predicate was also asking the wrong question**, found while
    writing the test rather than by the corpus.
    `ffi_tagged_union_return_is_safe_to_wrap` refuses ANY
    `InstanceOfNamed`, global constructors included, so `PathLike =
    string | Buffer | URL` is "unsafe to wrap" while its `_from_js` exists
    and works — widening on that gate would have widened node_fs's 12
    global-`Named` union returns too. The shipped predicate asks
    `tagged_union_from_js_expression(decl, "value") is None`, which is
    exactly the condition that withholds the `_from_js` half.
  - The three `*_should_emit_wrapper` predicates deliberately do NOT
    consult the widening: they refuse a wrapper whose rendered type uses
    `JSValue`, so routing them through it would DELETE `serve(...)` from
    the surface rather than widen it, leaving only `get_serve()`. Their
    question is whether the wrapper carries any type information, and the
    answer stays yes because the PARAMETERS are typed.
  - The three `server_type_from_*` CONSTRUCTORS correctly keep
    `-> ServerType`: they come from `ffi_type_alias_constructors`, a
    different path, and they DO build `{ "$tag": 0, "_0": value }`.
    Pinned by a unit test that fails under mutation of the `CallableMeta`
    arm with `"(Options) -> ServerType" != "(Options) -> JSValue"`.
- [x] **The `.mbti` carries declarations the `.mbt` does not** — DONE.
  Pre-existing, and only VISIBLE because the return-type widening above
  made two renderings of one declaration disagree.
  `add_bridge_ergonomic_helper_decls` derives a `declare pub fn` from
  every emitted extern and guarded on
  `if !next_bridge_mbti.contains(helper_decl)` — a substring test over
  the whole file using the full SIGNATURE, which asks "is this exact line
  present" where the question is "is this FUNCTION declared". MoonBit has
  no overloading, so a second `declare pub fn` of one name is always
  wrong; while the two layers rendered identical text the append was
  skipped and nothing was visible.
  - **The first measurement was WRONG, in the instrument**, and the
    correction is the finding worth keeping. The scan
    `^declare pub fn [A-Za-z_][A-Za-z0-9_]*` stops at `::`, so
    `BuilderProgram::getProgram` and six sibling METHODS collapsed onto
    `BuilderProgram`; the "52 duplicated names of 2,161 in the
    `typescript` package, 13 in vitest, 9 in node_fs" recorded one commit
    earlier is an artifact of that regex. Taking the name up to the `(`
    that must follow it immediately gives **4 duplicated names in 2
    packages** — and all 2,161 declare-lines in that package match the
    full-line form, so the refined scan is not under-counting either.
  - All four have NO impl counterpart: `get_serve`,
    `get_get_request_listener`, `get_create_adaptor_server` in
    hono__node_server, and `mkdir` in node_fs (one `pub extern "js" fn
    mkdir`, so not overloading). The stale line is the less precise one
    in three cases and precise-but-untrue in the fourth.
  - The derived declaration now REPLACES a same-named line in place, so
    the `.mbti` agrees with the `.mbt` by construction and the next
    disagreement cannot hide the same way. Keyed by name through one map
    lookup per line rather than a scan per name — 2,161 names over a
    10k-line file is the quadratic this repo keeps paying for.
  - Proven to change nothing else: regenerating the whole corpus before
    and after and diffing every declaration line order-independently
    leaves **85 of 87 packages byte-identical**, the 2 changed losing
    exactly those 4 lines. `MoonBit declared functions` 5410 -> 5406, so
    the report had been over-counting by exactly the redundant lines.
  - `bridge_quality_report.sh` gains `duplicate declared fn names`, which
    FAILS on any occurrence. Mutation-tested both directions, and
    verified NOT to fire on the `Type::method` forms that fooled the
    first measurement.
- [x] **`_from_js` exists but the wrapper still declines it** — DONE, and
  the estimate above was wrong twice. "node_fs's 12 such returns are
  mostly getters" was a guess; the widened probe says **4 sites, all in
  node_fs, all `PathLike`, two getters and two setters**. And the fix is
  in TWO places, not one: the gate, and the accessor paths that consult
  it.
  - **The gate contradicted its own doc comment for a full commit.**
    8d227ad rewrote `ffi_tagged_union_return_is_safe_to_wrap`'s header to
    say a global constructor "resolves and is kept … which is why
    `PathLike = string | Buffer | URL` gets a working wrapper", and left
    `Some(InstanceOfNamed(_)) => return false` in the body. So
    `PathLike`'s `_from_js` was emitted, exercised by
    `verify-bridge-runtime`, and never CALLED. Refusing an ERASED name is
    `tagged_union_case_runtime_discriminator`'s job and it already does it
    by returning `None`; the second, blunter copy of that judgement could
    only disagree with the first.
  - **Measured alone the gate change is a ZERO-diff no-op**, and that is
    not the same as pointless — it is consulted by
    `ffi_type_needs_js_return_conversion_with_state` and
    `ffi_type_js_return_expr`, and no top-level function in the corpus
    returns a global-`Named` union. It is LOAD-BEARING for the accessor
    fix below, proven by mutation: with the old arm restored the
    regenerated node_fs getter is `#| (self) => self.path` again.
  - **The four accessor paths never asked about tagged unions at all.**
    `ffi_class_property_getter_decl_to_moonbit` /
    `_setter_decl_to_moonbit` route through
    `ffi_rendered_generated_enum_info` and `ffi_enum_arg_expr`, which walk
    `state.enums` — the LITERAL-union enums, whose converters are MoonBit
    functions in `converters.mbt`. A tagged union's converters live in
    `bridge.js`, so the class METHOD path puts the argument direction in
    the JS BODY (`ffi_inline_js_arg_expr_with_state`) and the accessor
    path had neither direction. Two enum families, one of them asked
    about at these sites: the applied-in-some-places family with the axis
    being the FAMILY rather than the site.
  - The return direction needed a helper that did not exist —
    `ffi_inline_js_return_expr_with_state`, the mirror of the argument
    one — because an inline extern lambda cannot import the named
    `bridge.js` helper (`ffi_inline_js_tagged_union_to_js` states that in
    its own comment). It binds the value first: the from_js body repeats
    its argument once per case predicate, and the expression here is
    `self.path`, a property READ, where the named helper reads a
    parameter. Statics take the named helpers instead, their binding
    being a real `bridge.js` function.
  - **The setter fix turned out to cover a SECOND family, 26 sites of
    it.** `ffi_inline_js_arg_expr_with_state` also unwraps an OPTION box,
    so `Context::set_context_env(value : Bindings?)` had been assigning
    MoonBit's `{$tag: 1, _0: v}` straight into JS's `env` field — across
    hono, hono-real, drizzle, vitest and typescript. One missing call,
    two independent wrong values. Corpus totals: 33 emitted lines change,
    26 option-box unwraps, 2 tagged-union getters, 2 setters, 2 static
    struct converters, and every package's `.mbti` declaration count is
    unchanged, so the public surface is identical.
  - The probe was the precondition and it was widened as one: it now
    reads `fn[T]` and `Type::method` forms, and — the half that matters —
    scans INLINE EXTERN bodies as well as named `bridge.js` wrappers,
    since the two are where a declaration's implementation can land and
    only the second was ever checked. 47 named wrappers and 8 inline
    bodies cross a payload enum, 0 unconverted; wired into
    `bridge_quality_report.sh` as a `run_check`, called rather than
    reimplemented in shell. Mutation-tested by putting the raw
    passthrough back.
  - `verify-bridge-runtime`'s static half now scans those inline bodies
    too, under the STRICTER rule that only a JS global can resolve there
    (an inline lambda has no module scope). Its first version walked
    every `.mbt` under `_build` and reported three `instanceof` targets
    out of `moon fmt`'s copy of a checker whitebox test, whose `#|` lines
    are TypeScript source for a test case — widening the input set is not
    widening the question, so it is scoped to the directories holding a
    generated `bridge.js`. 1 source scanned, 0 unbound; fails when an
    erased name is injected into that body.
- [x] **Bind a module-exported class — MEASURED, ceiling is ONE return
  position, and measuring it found 18 live bugs next door.** The estimate
  above ("about ten", "worth doing for the `stat()` family specifically")
  is wrong in both halves, and the runtime says so: importing each
  generated package's own module and asking `typeof mod[name]` gives
  **2 bindable names of the 197 declined**, `Table` (drizzle-orm) and
  `Stats` (node:fs).
  - Every name the estimate listed is NOT bindable, for two reasons worth
    separating. hono__node_server's `Server` / `Http2Server` /
    `Http2SecureServer` / `IncomingMessage` / `ServerResponse` are
    **exported by a DIFFERENT module** — they are `node:http` / `node:http2`
    classes that the package re-exports as TYPES — so `__ts_mbt_module.Server`
    is `undefined` and binding them needs an import of another module, not
    the one-line threading this item described. `StatsFs` /
    `BigIntStatsFs` / `BigIntStats` are type-only on `node:fs`.
  - And the ceiling is a question about CONVERTERS, not names: `_from_js` is
    withheld unless EVERY case is discriminable, so `Stats` being bindable
    buys nothing while `BigIntStats` stays erased — which is exactly the
    `stat()` family this item called its main prize. Two converters are
    fully unblocked (`Auto_SQLValue_or_TableValue`,
    `Auto_ViewValue_or_TableValue`, both drizzle), and only ONE of them
    occurs in a return position: `aliasedTable`. The binding mechanism
    already exists — `bridge.js` emits `const Dir = __ts_mbt_module.Dir` —
    so what is missing is the call at the converter-emission point.
  - **The measurement's real output is 18 live wrong-value sites**, found
    because `aliasedTable` turned out to convert its ARGUMENT and hand its
    return back raw while declaring `-> Auto_ViewValue_or_TableValue`. The
    probe had been blind to them twice over: it matched
    `/_from_js|_to_js|\$tag/` over the whole body, so the `$tag` of the
    PARAMETER's conversion passed the return; and it read payload enums
    from `bridge.mbti` only, where the SYNTHESIZED `Auto_X_or_Y` unions are
    never declared — **212 of 231 payload enums live in `types.mbt`**. Both
    fixed: the directions are separate questions now (`"$tag":` /
    `_from_js(` BUILDS a MoonBit value, `.$tag ===` / `_to_js(` READS one),
    and the enum scan reads every `.mbt`.
  - The 18 are declared in `scripts/bridge_unconverted_enum_crossings.txt`
    with a kind and a reason each — 15 `erased-payload`, 2
    `optional-gate`, 1 `module-class`. Undeclared fails, stale fails, both
    mutation-tested.
- [x] **The unconverted-crossing backlog is EMPTY — all 18 fixed, and the
  gate's STALE half is what said so.** `bridge_unconverted_enum_crossings.txt`
  now declares nothing, the probe reports `0 / 0 / 0`, and every generated
  package still compiles and runs. What follows is the order the last 16
  fell in, because each step contradicted the step before it.
  - **The arm was missing, and then it was order-dependent.**
    `ffi_widen_unbuildable_union_outputs` never saw a SYNTHESIZED union: such
    a union keeps its `Union(parts)` shape in the AST while its signature
    already reads `Auto_X_or_Y`, exactly as
    `ffi_inline_js_tagged_union_to_js` states in its own comment sixty lines
    away — sixth fail-open shape arm here, and the first written INSIDE the
    fix for the fifth. The first version of the arm then asked whether the
    alias was already in `state.tagged_union_decls_by_name`, which is filled
    as a SIDE EFFECT of rendering, so the answer depended on whether an
    earlier declaration in the file happened to mention the same union:
    `Auto_IdentifierValue_or_PrivateIdentifierValue` is also a parameter of
    `idText` NINE LINES ABOVE and was registered;
    `Auto_VariableDeclarationValue_or_ParameterDeclarationValue` occurs
    exactly once and was not. One fixed, its neighbour silently not — the
    applied-in-some-places family with the sites chosen by declaration
    order. `ffi_output_union_decl` builds the decl on the spot instead; a
    synthesized decl is only `{ name, cases }`, and registration is the
    emission pass's business, not this decision's.
  - **Three renderings of one export, and only the ffi one moved.** The
    `.mbti` line comes from the DECL layer and the public wrapper is rendered
    FROM that line, so widening the extern alone gives `[4014] has type
    JSValue?, wanted Auto_…?`. `reconcile_bridge_widened_union_returns` makes
    the declaration agree with the extern that implements it, which is the
    principle `add_bridge_ergonomic_helper_decls` already states — the `.mbt`
    is what the package really is. It has to be SCOPED, and that is the whole
    difficulty: a declaration differing from its extern is the NORMAL case (a
    literal-union enum crosses as an `Int`, an opaque type arrives as
    `JSValue` and the wrapper wraps it in an option), so it fires only when
    the extern hands back `JSValue` at the SAME optionality and the declared
    type is one of the two things the widening can leave behind. Both halves
    are needed and one was written first: when the union is still mentioned
    elsewhere the enum survives and the symptom is `[4014]`; when the widened
    return was its LAST mention nothing synthesizes the enum any more and the
    same stale line is `[4032] the type Auto_… is undefined`, which is
    exactly how `walkUpBindingElementsAndPatterns` failed to compile while
    `getNameOfJSDocTypedef` came out right.
  - **The `.mbti` emitter was found by INSTRUMENTING, and the first run of
    that experiment was a false zero.** Markers in the three `declare pub fn`
    renderers of `parser_moonbit.mbt` attributed 0 of 11 lines — because the
    fixture used was a class-only `.d.ts`, which declares no top-level
    function, so `func_decl_to_moonbit` was never called at all. A zero from
    a probe whose shape is ABSENT is not an answer, and the previous note in
    this entry ("it is not any of the `declare pub fn` literals in
    `moonbit_bridge.mbt`, so the body comes from elsewhere") was drawn from
    that zero. It is `parser_moonbit.mbt:1426`, reached through
    `moonbit_decl.mbt:12526`.
  - **An index signature's two directions are two questions and were
    rendered with ONE type name.** `index_get` crosses JS -> MoonBit and
    widens; `index_set` crosses the other way, where `_to_js` reads `$tag`
    and needs no runtime predicate, so it keeps its type and converts in the
    body. `ffi_inline_js_arg_expr_with_state`'s tagged-union detection was
    also `Named`-only, which would have sent every synthesized union down the
    generic option unwrap and read `value._0` off a value MoonBit does not
    box.
  - **A METHOD's return needed the widening and `ffi_function_type_parts` is
    the wrong place for it, measured rather than reasoned.** A function type
    has no direction of its own: the same rendering types a method's return
    (JS -> MoonBit) and a CALLBACK parameter's return (MoonBit -> JS, where
    the enum works and widening throws away a working type). Putting it there
    broke `Matcher::_call_`, whose wrapper reads a struct FIELD rendered
    elsewhere — `has type ExpectationResult, wanted JSValue`. It belongs in
    the one branch of `ffi_function_field_method_decl` that binds straight to
    a JS call, guarded on the unwidened rendering still matching so the
    `This` / `This?` substitution above is not undone.
  - The `module-class` entry went with them: binding `drizzle-orm`'s real
    `Table` / `View` would have made `aliasedTable`'s `instanceof` resolve,
    and widening needed no new machinery. The measured ceiling for that
    binding was 2 bindable names of the 197 declined, which is why it was
    never worth taking on its own.
  - Gates: probe 0/0/0, `verify-bridge-runtime` 86 modules / 14,630 converter
    calls / 0 failures / 0 unbound `instanceof`, `bridge_quality_report.sh`
    `pass` with `duplicate declared fn names 0`, scaffolds + fixtures +
    examples all 0, `verify-mbti-dts` 0, `moon test` 2994/2994. Both halves
    mutation-proven by
    `fixtures/resolver/project/types/widened-union-output-entry.d.ts` and the
    test over it, which carries a NEGATIVE control (`string | URL`
    discriminates, so that union keeps its enum) so the fix cannot be
    "switch the lowering off".
- [x] **COUNTED the struct-field class, and the count retires the entry that
  filed it.** The previous note called this "a function-typed struct FIELD's
  return", estimated at 8, and said the first step was to teach
  `bridge_enum_return_probe.mjs` to count them. Section C of the probe does,
  and the label was standing in for the objective again — tenth instance in
  this repo, and the widest miss yet at **54x**. The class is ANY struct field
  carrying a payload enum, function-typed or not: **438**.
  - **What is actually wrong is bigger than the widening, and it is a missing
    DIRECTION rather than a missing arm.** Sections A and B ask about a
    function's return; a struct field is the third position an enum can
    occupy, and it is the one with no machinery at all. The corpus emits
    **259 `_to_js` struct converters and ZERO in the other direction**, so a
    JS object handed to MoonBit as a struct is used RAW —
    `Program::getSemanticDiagnostics` is
    `(self, a, b) => self.getSemanticDiagnostics(a, b)`, unwrapping its
    argument options and doing nothing to the returned `Array[Diagnostic]`.
    `diag.messageText` is therefore a raw JS string under
    `Auto_StringValue_or_DiagnosticMessageChainValue`, and 33 externs return
    `Diagnostic`. That MoonBit structs are name-keyed JS objects is not
    assumed: `__ts_mbt_to_js_diagnostic` reads one with
    `value["messageText"]`, so the generator's own output says so.
  - **READ-REACHABILITY is the filter that makes it tractable, and it changed
    the answer by 50x.** Only a struct that appears in a RETURN position can
    receive a JS value at all; one that only crosses MoonBit -> JS is served
    correctly by the `_to_js` converter that exists. 438 fields -> **151**
    read-reachable, of which **8 convertible** and **143 erased**. The
    alarming first reading — "247 React aria attributes would have to widen" —
    was measuring the wrong set: react_types is **5** under the filter.
  - **The ranking is two rows.** `typescript_ast` and `typescript` are the same
    `typescript.d.ts` generated twice, 68 reachable / 67 erased each, so the
    distinct work is 68 fields in ONE package plus 15 across six others.
  - **The instrument carried the same substitution bug as the code, twice, for
    the seventh time in this sequence.** `bridge.js` helper names are the
    generator's snake_case, which DOUBLES the underscore at a PascalCase
    boundary inside an already-underscored name (`Auto_BoolValue_or_X` ->
    `auto__bool_value_or__x`). A hand-written snake_case reported 8
    convertible / 430 erased; a too-loose match reported 260 / 178. Comparing
    with underscores stripped and reconstructing nothing gives 8 / 143.
  - Budgeted per PACKAGE in `scripts/bridge_struct_enum_fields.txt` rather
    than declared per occurrence: 438 declarations would rank no work, and
    eight rows rank it directly. Growth fails, an undeclared package fails, a
    drop is reported so the budget follows it down — all three
    mutation-proven.
- [x] **143 -> 133 and four of eight packages to zero, by making more unions
  CONVERTIBLE rather than by widening or by an accessor.** Both filed options
  were worse than the third, and one of them was wrong on its own terms:
  a converting accessor "keeps the type information" only where a converter
  EXISTS, and an erased enum has none, so that route never applied to the
  erased half at all.
  - **`tagged_union_from_js_expression` refused a union the moment ONE case
    lacked a runtime discriminator, and it only has to refuse at TWO.** The
    union is CLOSED: the value is declared to be one of its members, so
    failing every other case's test IS the remaining case and that one needs
    no predicate. `string | DiagnosticMessageChain` is exactly the shape —
    `typeof === "string"` decides the first, the second is the `else` — and
    that is `Diagnostic.messageText`, reached through
    `Program::getSemanticDiagnostics`, the most-used API the TypeScript
    compiler has. With two erased cases the else cannot choose
    (`CatchClause | VariableDeclarationList`) and the refusal stands, which
    is why the remaining 133 are the AST `parent` unions.
    What is given up is stated rather than glossed: the `throw` was the only
    thing that noticed a value the `.d.ts` mis-declared, and such a value is
    now tagged as the fallback case. The alternative it replaces is the
    caller receiving a raw JS value under a type claiming `{$tag, _0}` —
    wrong in the same direction and silent — so nothing that used to be
    caught stops being caught.
  - **Relaxing the builder immediately exposed a SECOND copy of its
    judgement**, which is the failure 8d227ad is already recorded for.
    `ffi_tagged_union_return_is_safe_to_wrap` had its own
    `None => return false` arm, so a `_from_js` now existed (the widening
    therefore stopped firing) while the gate still declined to CALL it, and
    five declarations promised the enum over a raw JS value again — the
    probe named them. It asks the builder now, and keeps only its OWN
    reason, a `TypeofFunction` payload the auto-wrap cannot model.
  - **Then three of the five were the SEVENTH fail-open shape arm**, and the
    third distinct site of the `Named`-only spelling in
    `moonbit_js_ffi.mbt`. `ffi_type_needs_js_return_conversion_with_state`
    and `ffi_type_js_return_expr` — a predicate and an emitter, each in an
    optional and a non-optional spelling — matched `Named` alone at all
    FOUR arms, so a synthesized union fell through every one and
    `mkdtempSync_string_encoding_option_optional` declared
    `Auto_StringValue_or_NonSharedBufferValue` over a raw `mkdtempSync(…)`.
    One `ffi_wrappable_union_alias_name`, four callers.
  - **The budget gate I shipped one commit earlier was wrong in the
    convertible direction** and said so out loud: `convertible` RISING is an
    improvement, and gating all three axes upward reported five packages as
    having GROWN when ten fields moved out of the unfixable half. Only
    `reachable` and `erased` are gated now; all four directions
    mutation-proven.
  - Measured: read-reachable 151 unchanged, **8 -> 18 convertible, 143 -> 133
    erased**, four packages (vitest, node_fs, hono_jsx, react_jsx_runtime) at
    zero erased. Converters 1,330 -> 1,377 and 15,147 exercised calls with
    **0 runtime failures** and 0 unbound `instanceof` — which is the check
    that matters, since every new fallback converter is executed there over a
    value battery. Probe 0/0/0, quality report `pass`, scaffolds + fixtures +
    examples pass, `moon test` 2994/2994.
  - One test had to be updated rather than fixed, and the distinction is
    worth keeping: it asserted a deliberate ABSTENTION (`from_js is None` for
    `PathLike | number`), not a bug. Its real concern — that
    `v instanceof PathLike` is never emitted — is still asserted, and the
    declining-note coverage moved to the two-erased-case union where the
    refusal now lives.
- [x] **The 133 that are left are `JSValue` now — erased 133 -> 0.** Every one
  was a union of two or more erased interfaces, so no converter could exist
  and no accessor could help: `VariableDeclaration.parent`
  (`CatchClause | VariableDeclarationList`), `VariableDeclarationList.parent`
  (four erased statement kinds), `JSDocTypedefTag.fullName`. The declared type
  is now the type the emitted JS actually hands over, which costs the type
  information on exactly the shapes a TS AST walker touches — a product
  decision rather than a bug fix, and the honest one: a `match` on the old
  declaration read `$tag` off a raw JS object that has none.
  - **The widening is DIRECTIONAL, and computing that direction is the whole
    change.** A struct that only ever crosses MoonBit -> JS keeps its enum
    and its working `_to_js` converter, so react_types' `aria_checked` still
    declares `Auto_BoolValue_or_...`. The fact comes from a pre-pass,
    `ffi_collect_read_reachable_struct_names`: seed every RETURN position in
    the module set (a function's return, a value's type, an interface
    method's return, an index signature's value, a class property or method
    return), then close over struct FIELDS — a struct reachable from a
    returned struct is itself a struct a JS value can arrive as. For a
    `Func` / `Constructor` field only the RETURN is followed, because a
    callback's PARAMETERS are written by MoonBit and read by JS, which is
    the opposite direction and exactly what broke `Matcher::_call_` when the
    widening went into `ffi_function_type_parts`.
  - **The fix measured NOTHING on its first run, and the reason is the family
    this file keeps recording — inside my own fix.** I patched
    `ffi_named_struct_decl_to_moonbit` and the count did not move, because an
    INTERFACE-derived struct is rendered by
    `ffi_struct_decl_to_moonbit`: two renderers of one decision, one of them
    patched. Both take the same `is_read` test now.
  - **The last five erased were the PROBE over-counting, not the generator
    under-widening**, and the generator's AST pre-pass is what disagreed.
    `HTMLAttributes::asAriaAttributes(self) -> AriaAttributes = "%identity"`
    is a MoonBit-side upcast of a value the CALLER built, not a JS boundary
    crossing, and section C was reading it as a return position. react_types
    goes 5 read-reachable -> 0. Eighth time in this sequence that the
    measuring instrument carried the same substitution bug as the code.
  - Measured: **erased 133 -> 0**, total fields carrying an enum 438 -> 304
    (134 widened), read-reachable 151 -> 17, synthesized enums declared
    227 -> 180 (47 that nothing references any more). Gates: probe 0/0/0 and
    `erased 0` on all eight packages, `verify-bridge-runtime` 86 modules /
    1,330 converters / 14,630 calls / 0 failures / 0 unbound `instanceof`,
    quality report `pass`, scaffolds + fixtures + examples 0,
    `verify-mbti-dts` 0, `moon check` 0 errors, `moon test` 2994/2994.
  - **What is left is 17 CONVERTIBLE fields, and widening them would be a
    regression** — the type information is real there.
    `Diagnostic.messageText` / `DiagnosticWithLocation.messageText`,
    `TypeChecker.getConstantValue`, `LanguageService.prepareCallHierarchy`,
    vitest's `diff` / `inspect` / `inspectBrk` and the two JSX `children`
    unions all have a working `_from_js` that nothing calls at a struct
    field. That is the separately filed `_from_js` struct converter, 259
    functions' worth of mirror.
  - The `ffi_func_type_name` direction blocker is UNCHANGED and still filed:
    it renders both an interface member's function type (return crosses
    JS -> MoonBit) and a callback parameter's (return crosses the other
    way). The read-reachability pre-pass answers "can a JS value arrive as
    this STRUCT", which is a different question from "which direction does
    this function TYPE cross", so it does not dissolve that item.
- [x] **Convert an OPTIONAL tagged-union crossing — DONE**, and both of the
  reasons the previous note gave for declining it were false, which is the
  part worth keeping.
  - "The MoonBit side could box a value that path already boxed" was
    CHECKABLE and unchecked: `ffi_option_return_inner_is_boxed` returns
    FALSE for a tagged-union alias, so `ffi_option_return_needs_wrap` never
    fires for one and there is no MoonBit-side wrap to collide with —
    `Some(v)` IS `v` and `None` IS `undefined` at the boundary. Confirmed
    against the emitted code, not the source: no `wrap_option_return`
    appears anywhere near `getConstantValue`.
  - "No generated accessor in the corpus has that shape" was also false;
    there are 2, both `TypeChecker::getConstantValue` returning
    `Auto_NumberValue_or_StringValue?` — `String | Double`, both
    primitives, so `typeof` discriminates.
  - The optional inner is a raw `Union(parts)`, so the fix needed
    `ffi_output_union_alias_name` back to resolve BOTH spellings (a `Named`
    alias, and an inline `A | B` whose signature reads `Auto_X_or_Y` while
    the AST keeps `Union`).
  - **And the site was a THIRD renderer.** `TypeChecker` is an INTERFACE, so
    `getConstantValue` never reached the class-method path; patching the
    class path, regenerating and finding the count unchanged is what found
    `ffi_function_field_method_decl`. Interface methods, class methods and
    the four accessor paths are three separate renderers of one decision, and
    the arguments were routed through the conversion at all of them while the
    RETURN was routed at none. Same family, one axis further out.
  - Both entries retired from the declared list, and the STALE report is
    what said so — the mechanism earning itself back on its first use.
    Declared backlog 18 -> 16.
- [ ] **Drop `ffi_synthesize_inline_union`'s `func_members > 0` gate.** Now
  that soundness lives centrally the gate is conservative rather than
  load-bearing: it refuses to synthesize an enum whose `_from_js` would be
  withheld, while the same union WITHOUT a function member is synthesized
  and keeps its `_to_js`. Dropping it types more parameter positions. Left
  alone here because it changes generated output broadly and deserves its
  own measurement.

## Bridge quality report: the heterogeneous-union budget (2026-09-07) — DONE

- [x] **A count could not rank the work, and had been failing silently.**
  `heterogeneous_union_unsupported_export_budget` was set to 0 in `14a2a6c`
  when the count was 0; the `typescript-node-imports` example landed later
  (`b84b7cb`, NOT an ancestor of `14a2a6c`) and reintroduced two, so the
  report has been exiting 1 ever since — verified pre-existing by re-running
  it at `a94e5c6`, which fails identically. A bare count cannot say whether
  an occurrence is an accepted limitation or a regression, which is the same
  defect that retired `docs/checker-priority.md`.
  `scripts/bridge_widened_unions.txt` declares each occurrence with a kind
  and a reason, an UNDECLARED occurrence fails, and a declared entry that no
  longer occurs is reported STALE — the mechanism
  `scripts/checker_out_of_scope.txt` uses, including the stale report that
  keeps it from decaying into a suppression list. **Both directions proven
  by mutation**: an empty declaration file reports 2 UNDECLARED and exits 1;
  a bogus entry is named as stale and exits 1. Report `Overall: pass` for
  the first time in this branch.
- [x] **The diagnostic named a cause that cannot occur.** "non-PascalCase
  named, function, or unsupported shape" — a function member IS accepted
  (as `FnValue`), and everything real fell into "unsupported shape", so the
  two occurrences (an anonymous object type; an object intersection) could
  not be told apart from a lowercase name by reading the message.
  `tagged_union_member_shape_description` names the member and what would
  have to be supported, which is what makes the declaration file legible.
- [ ] **Object-payload union members** (the one capability both declared
  entries need: a synthesized payload struct plus `typeof v === "object" &&
  v !== null && !Array.isArray(v)`, admissible only when the union has
  exactly one object-ish member). REJECTED for now with the reasons in the
  declaration file, and the honest summary is that neither corpus occurrence
  earns it: `BufferEncodingOption`'s `{ encoding: "buffer" }` is redundant
  with its `"buffer"` string member, which `buffer_encoding_option_from_string`
  already constructs; and `WriteFileOptions` needs a SECOND thing —
  its sibling `BufferEncoding` is a node global this package does not
  resolve, so even a successful lowering hands the user a case payload they
  cannot build. Take it when a target needs an options object that is not
  also spellable another way. `decl_synthesized_object_interfaces` is the
  registry to reuse; `decl_normalize_alias_union_body` is the hook.

## Interop Bridge Quality Roadmap: 60% -> 90%

Current assessment: the project is around 55-60% complete as a practical
`TypeScript <-> MoonBit` interoperability bridge. It is usable for selected
packages under supervision, but not yet reliable enough for arbitrary npm or
MoonBit packages without inspection.

Target: reach about 90% practical quality for the declared supported surface.
This does not mean "all TypeScript semantics"; it means generated bridges are
predictable, self-diagnosing, build-backed, and runnable for a broad real-world
corpus without manual edits.

### 90% Quality Gate

- [x] `just ci` passes with all fixture-backed bridge/scaffold checks.
- [x] `just verify-realworld-typescript` passes with a fixed corpus of at least
  20 npm / Node entrypoints.
- [x] `just verify-realworld-moonbit` passes with a fixed corpus of at least 15
  local MoonBit packages.
- [x] Every generated TS -> MoonBit package in the real-world corpus passes:
  `moon check --target js`, `moon test --target js`, `moon build --target js`,
  and a Node smoke run.
- [x] Every generated MoonBit -> TS package in the real-world corpus passes:
  `moon build --target js`, TypeScript declaration typecheck, and a Node import
  smoke run for root and subpath exports.
- [x] Unsupported exports are either 0 or limited to explicitly-budgeted
  ambiguous surfaces with actionable diagnostics.
  - `just bridge-quality` now fails on unbudgeted unsupported exports and
    budgets only the single fixture-backed ambiguous re-export surface with
    explicit candidate diagnostics.
  - `just verify-realworld-typescript` also budgets the single zod
    `ZodFirstPartyTypeKind` empty compatibility enum stub as an omitted,
    runtime-safe unsupported surface.
- [x] `JSValue` usage is classified by reason, and budgets are stable per
  package instead of being treated as an opaque quality number.
  - Real-world TypeScript metrics now split `JSValue` surface usage into
    unknown / any, overload, conditional / mapped, callback / function,
    tuple / array, and namespace / value buckets, with per-package budgets.
- [x] Generated packages require no manual glue edits for the supported corpus.
  - Real-world TypeScript verification hashes generated glue files immediately
    after CLI generation and fails if smoke setup or builds mutate them.
  - Real-world MoonBit verification hashes generated package artifacts and
    fails if typecheck, import smoke, or consumer smoke steps mutate them.
- [x] `README.md` documents the supported surface, unsupported surface, and
  diagnostic interpretation clearly enough for external users.
  - README now documents the supported MoonBit -> TypeScript and TypeScript ->
    MoonBit bridge surfaces, known fallbacks, diagnostics files, quality
    reports, and the no-arbitrary-package-conversion caveat.

### Generated Code Review Follow-up (2026-05-01)

Review status:

- `just verify-examples` passes, including JS build smokes.
- `just bridge-quality` passes with 0 unbudgeted unsupported exports.
- `just verify-realworld-typescript` passes with package-local `JSValue` cause
  budgets and warning-free MoonBit checks.
- A node:fs-only real-world probe builds and runs with 0 unsupported exports.
  Current metrics after callback/option-bag, generic, tuple, and function-type
  cleanup: 2239 bridge lines, 327 declared functions, 12 `JSValue` refs, 2
  `JSValue` functions, and 11 `JSValue` surface lines.

Next implementation tasks:

- [x] Fix callable interface conversion at the JS boundary.
  - Current symptom: React `forwardRef` receives an object converted from
    `ForwardRefRenderFunction` instead of a callable JS function, producing
    `forwardRef requires a render function but was given object.`
  - Target: generated converters for interfaces with a `<call>` / `_call_`
    signature should pass through existing JS functions and wrap MoonBit
    records as callable JS functions while preserving optional properties.
  - Done: `ffi_struct_js_converter_decl` now emits callable wrappers for
    `<call>` interfaces, and the React examples no longer emit the runtime
    `forwardRef` warning.
- [x] Remove package-global opaque generic placeholders such as `type T`,
  `type P`, and `type S` from generated public APIs.
  - Target: preserve representable generics as MoonBit type parameters; if a
    TypeScript generic cannot be represented safely, widen only that local
    boundary to `JSValue` with diagnostics.
  - Done: interface type parameters are preserved in the AST and local generic
    placeholders are widened at the specific boundary instead of emitted as
    package-global opaque types; generated Hono/React/TypeScript AST examples no
    longer leak `type T` / `type P` style placeholders.
- [x] Lower or explicitly budget remaining anonymous literal-union public
  surfaces.
  - Current unbudgeted examples include React `OlHTMLAttributes`, Vitest
    `Assertion` / `VitestUtils` / `SerializedConfig`, and TypeScript AST
    `UserPreferences` / encoded classification request args.
  - Target: create stable synthetic names when a public owner can be inferred,
    otherwise keep the fallback but require an explicit budget and diagnostic.
  - Done: anonymous string literal unions now get stable synthetic enum names
    even when literal values are unsafe as MoonBit case names or appear inside
    function/object/union surfaces. `just bridge-quality` now has 0 unbudgeted
    unsupported exports.
- [x] Reduce node:fs JSValue regressions.
  - Previous node:fs metrics: 2015 bridge lines, 312 declared functions,
    117 JSValue refs, 81 JSValue functions, 0 unsupported exports.
  - Priority: callback aliases, overload-selected sync/promisify wrappers, and
    common option bag aliases such as stat/read/write options.
  - Done: inline callback parameters now receive stable synthetic callback
    opaque types instead of `JSValue`, and named option intersections such as
    `StatOptions & { bigint?: false }` collapse back to the named option bag;
    `StatsBase<T>` / `StatsFsBase<T>` now preserve `T`, and event-map tuple
    payloads keep `Array[Unit]`, `Array[Double]`, or `Array[Error_]` where
    representable. Function types now lower to MoonBit function arrows instead
    of `JSValue`; inline `Promise<{ ... }>` results such as
    `read.__promisify__` / `write.__promisify__` now get named result structs,
    and class method generic bounds keep stream listener event names as
    `String`. Common `writeFile*` / `appendFile*` string data and `cp*` string
    paths now stay typed; `glob*` string patterns and `create*Stream` option
    bags are preserved; promisify file-data wrappers no longer widen string
    data to `JSValue`; stream `path` properties now use `PathLike`, and
    `StatSyncFn` callable options use `StatSyncOptions?`. Stream listener
    payloads now use generated payload opaque types, and redundant
    encoding-dependent overload wrappers with wider returns are skipped.
    `BigIntStats` nanosecond fields now lower to `Int64`, and
    `FSWatcherEventMap.change` uses an opaque payload type instead of
    `Array[JSValue]`; `WatchOptions.encoding` now lowers to `String?`.
    Overload wrapper pruning keeps narrow overloads per arity, so the broad
    `fstatSync` / `statfsSync` union-return wrappers no longer leak `JSValue`
    while bigint variants remain callable. `readFileSync` /
    `readFile.__promisify__` buffer options now use `ReadFileBufferOptions?`,
    `readFileSync` also exposes a `BufferEncoding -> String` wrapper, broad
    `globSync` union-return wrappers are skipped, and `_GlobOptions.cwd`,
    `_GlobOptions.exclude`, and `CopyOptions.filter` now keep concrete MoonBit
    types. Current node:fs budget is 11 `JSValue` surface lines and 2
    `JSValue` functions.
  - Remaining quality debt: event payloads with heterogeneous values still use
    opaque payload boundaries, and custom `fs` implementation hooks / watcher
    ignore predicates still require `JSValue`.
- [x] Split large generated MoonBit packages into reviewable files.
  - Target layout: `types.mbt`, `externs.mbt`, `converters.mbt`, and
    `guards.mbt` for large TS -> MoonBit scaffolds, while preserving generated
    `bridge.mbti` and package metadata.
  - Done: generated TS -> MoonBit packages over the review threshold now split
    MoonBit implementation code into `types.mbt`, `converters.mbt`,
    `externs.mbt`, `guards.mbt`, and `bridge.mbt`. Example/scaffold checks,
    real-world manifests, and bridge quality metrics now count the split source
    files instead of assuming all implementation code lives in `bridge.mbt`.
- [x] Add regression rails for generated-code ergonomics.
  - [x] React `forwardRef` warning should fail the smoke rail.
  - [x] TypeScript AST transformer smoke should reduce required `unsafeCast`
    usage around `ScriptTarget`, `transform`, visitors, and transformed arrays.
  - [x] node:fs budget regressions should fail with package-local diagnostics.

### Package-Specific Practical Coverage Pass (2026-05-01)

Implemented in the current real-world TypeScript probe order:

- [x] Small Node built-ins now target zero public `JSValue` fallback.
  - `node:path`, `node:os`, `node:url`, `node:querystring`, and `node:buffer`
    all generate with `JSValue surface = 0` in
    `_build/realworld-typescript/METRICS.md`.
  - The corresponding real-world budgets in
    `scripts/verify_realworld_typescript.sh` are fixed at 0 so regressions fail.
- [x] `node:crypto` focused pass.
  - Common option bags, AAD options, key-like parameters, WebCrypto algorithm
    parameters, `generateKeyPair` callbacks, and broad `generatePrimeSync`
    overloads are now specialized or pruned.
  - Current `node:crypto` metrics: `JSValue refs = 0`, `JSValue functions = 0`,
    `JSValue surface = 0`.
- [x] Hono practical route API smoke.
  - The real-world smoke now writes a route as
    `app.hono_get("/", realworld_hono_handler)`.
  - Route paths lower to `String`, handlers lower to `(Context) -> Response`,
    and common `Context` response helpers such as `text` return `Response`.
  - Current Hono budget is tightened to 55 `JSValue` surface lines and 36
    `JSValue` functions; remaining fallbacks are mostly generic context,
    router, and validation data surfaces.
- [x] Zod / Valibot / Preact fallback policy documented.
  - These packages remain buildable and smoke-tested, but their high-order
    schema, parser, JSX, and component generic surfaces are explicitly
    documented as budgeted `JSValue` fallback areas rather than natural MoonBit
    APIs.
- [x] Split real-world packages into explicit fallback policy classes.
  - `just verify-realworld-typescript` now appends a fallback policy table to
    `_build/realworld-typescript/METRICS.md` and fails if a new corpus package
    is not classified.
  - Active naturalization targets: Hono, React Router, JOSE, Glob, `date-fns`,
    `magic-string`, `source-map`, `node:sqlite`, `node:fs`, `node:assert`, and
    `node:util`.
  - Budgeted fallback probes: Zod, Valibot, Preact, and broad Playwright
    event/callback surfaces. These should stay buildable and smoke-tested, but
    are not currently claimed as naturally typed MoonBit APIs.
- [x] Add a first Glob naturalization for function-valued const exports.
  - `declare const hasMagic: (pattern: string | string[], options:
    GlobOptions) => boolean` now keeps the existing getter but also emits a
    MoonBit string-subset wrapper as `has_magic(pattern : String, options :
    GlobOptions) -> Bool`.
  - Function-valued const exports whose signatures do not widen to `@js.Any`
    also get direct callable wrappers, so `escape(pattern, options)` and
    `unescape(pattern, options)` no longer require `get_escape()` /
    `get_unescape()` first.
  - The real-world Glob smoke now calls `escape`, `unescape`, and
    `has_magic("src/*.mbt", options)` directly instead of manufacturing a
    `JSValue` pattern argument or calling getter-returned functions.
  - The Hono real-world example smoke now uses a typed MoonBit route handler
    `(Context) -> Response` directly with `app.get("/hello", handler)`.

### Phase 1: Measurement and Diagnostics (60% -> 65%)

- [x] Add a persistent quality score report for bridge generation.
  - Include generated lines, exported declarations, unsupported exports,
    `JSValue` refs, `JSValue` functions, runtime smoke coverage, and diagnostics.
  - Initial fixture-backed report is generated by `just bridge-quality` at
    `_build/bridge-quality/REPORT.md`.
- [x] Split `JSValue` metrics by cause:
  - unknown / any
  - overload fallback
  - conditional / mapped type fallback
  - callback / function type fallback
  - tuple / array fallback
  - namespace / value fallback
  - Initial breakdown is heuristic over generated `bridge.mbti` surface lines
    in `just bridge-quality`.
  - Real-world TypeScript verification uses the same buckets in
    `_build/realworld-typescript/METRICS.md` and fails on unbudgeted growth.
- [x] Make `SCAFFOLD_DIAGNOSTICS.md` explain what was widened, omitted, or
  bridge-wrapped, and whether each item is runtime-safe.
  - Diagnostics now include a summary table with decision, reason, runtime
    safety, and a decision vocabulary for widened / omitted / bridge-wrapped
    surfaces.
- [x] Add a `just bridge-quality` task that runs the fixture corpus and prints a
  single summary table.
- [x] Store real-world corpus package versions / paths in one config file so the
  score is reproducible across machines.
  - TypeScript real-world corpus entries now live in
    `corpus/realworld-typescript.tsv`; `scripts/verify_realworld_typescript.sh`
    records that path in `METRICS.md`.

### Phase 2: TypeScript -> MoonBit Surface Coverage (65% -> 72%)

- [x] Harden npm / Node type resolution:
  - [x] package `exports`
  - [x] `types` / `typings`
  - [x] subpath exports
  - [x] `typesVersions`
  - [x] `@types/*` fallback
  - [x] `node:*` built-in modules
  - Resolver tests now cover package fields, exports conditions, wildcard
    exports, subpaths, `typesVersions`, unscoped and scoped `@types` fallback,
    and `node:*` built-in declarations via `@types/node`.
- [x] Improve overload handling.
  - [x] Prefer overloads that can be represented with concrete MoonBit types.
    - Direct local overload resolution now uses the same widening score as the
      final generated binding collapse, so broad `unknown` / `any` signatures no
      longer hide later concrete signatures.
  - [x] Emit multiple safe wrappers when overloads are materially different and
    nameable.
    - Nameable non-preferred signatures now emit stable suffixed wrappers, e.g.
      `makeCounter_number`, while preserving the original runtime export name in
      generated JS FFI glue.
  - [x] Keep a stable fallback rule when overloads collapse to `JSValue`.
    - Equal-score overloads keep declaration order and still collapse to one
      generated binding.
- [x] Expand common utility type lowering:
  - [x] `Pick` over resolvable interfaces and literal keys.
  - [x] `Omit` over resolvable interfaces and literal keys.
  - [x] `Record` as a named opaque JS object boundary.
  - [x] `Exclude` over directly comparable union members.
  - [x] `Extract` over directly comparable union members.
  - [x] `NonNullable` over optional-like unions.
  - [x] simple `ReturnType` / `Parameters` for direct function types.
  - [x] simple alias-position passthrough for resolved concrete utility aliases.
  - [x] local `typeof Class` capture for `InstanceType` /
    `ConstructorParameters` bridge lowering.
- [x] Support the common mapped-type subset needed by real declaration files.
  - [x] Lower `Partial<T>`, `Required<T>`, and `Readonly<T>` over resolvable
    interfaces into named MoonBit option-bag structs.
  - [x] Parse and lower inline mapped object types with literal keys such as
    `{ [K in "a" | "b"]: T }`.
- [x] Support the common conditional-type subset used by React, Hono, Zod, and
  Node declarations.
  - [x] Lower statically decidable `A extends B ? X : Y` when both sides are
    direct primitive / union types.
  - [x] Lower `Awaited<Promise<T>>` / `Awaited<PromiseLike<T>>`.
  - [x] Cover standard conditional utilities already represented as direct
    utility forms: `NonNullable`, `Exclude`, `Extract`, direct `ReturnType`, and
    direct `Parameters`.
  - [x] Preserve or resolve infer-based conditional aliases instead of widening
    them to `JSValue`.
    - [x] Resolve concrete infer patterns such as
      `Promise<string> extends Promise<infer T> ? T : never`.
    - [x] Preserve generic infer aliases that still depend on type parameters.
      - Generic conditional aliases are retained in the AST and resolved when
        applied to concrete type arguments, e.g. `UnwrapPromise<Promise<string>>`.
- [x] Preserve optional and readonly field information where MoonBit can express
  it; otherwise emit diagnostics instead of silent widening.
  - Optional fields are preserved as optional-like MoonBit surface types.
  - Interface `readonly` fields are retained as metadata and emitted as
    declaration / FFI diagnostics because generated MoonBit structs do not
    enforce TypeScript readonly semantics.

### Phase 3: Runtime Bridge Correctness (72% -> 78%)

- [x] Make runtime namespace handling complete for declaration-merge patterns:
  `function x` + `namespace x`, `class X` + `namespace X`, and value namespaces.
  - Declaration-merged namespace fixtures now cover root function/class/value
    exports, runtime namespace member glue, and namespace-local type references
    such as `make.Options` lowering to `MakeOptions` without leaking
    unqualified helper types.
- [x] Strengthen CJS / ESM interop:
  - `export =`
  - `export default`
  - synthetic default imports
  - namespace imports
  - mixed named/default re-exports
  - Generated fixture smokes now cover `.cjs` `export = namespace`
    runtimes through synthetic default import, `node:path` namespace imports,
    relative/parent-relative default exports, bare CJS package default
    functions, and mixed default/named class re-exports.
- [x] Add runtime smokes for async and Promise-returning APIs.
  - `Promise<T>` / `PromiseLike<T>` now lower to `@js.Promise[T]` in
    declaration and FFI generation, and a generated JS-target fixture awaits
    Promise-returning APIs with `.wait()`.
- [x] Add runtime smokes for callback APIs where the callback can be represented
  safely.
  - Callback parameters are currently represented as `JSValue` / `@js.Any`;
    the generated fixture passes required and optional JS callbacks through
    MoonBit, verifies the runtime side effect on the JS target, and covers
    MoonBit `Option` unwrapping to JS `undefined` / raw callback values.
- [x] Add runtime smokes for object option bags with optional fields.
  - Generated fixture smoke now calls a declaration-merged namespace function
    with a runtime-created `MakeOptions` object containing an optional field,
    then checks the JS target bridge through `moon check` and
    `moon test --target js`.
- [x] Add runtime smokes for class instance properties, static properties, and
  static methods.
  - Existing generated fixtures exercise instance getters/setters, mutable
    static properties, readonly static properties, and static factory methods
    across direct and re-exported class bindings.
- [x] Ensure generated `bridge.js` never imports a missing runtime binding
  without a diagnostic.
  - `unique symbol` marker exports, such as `node:assert`'s internal
    `kOptions`, are now treated as non-runtime declarations and are omitted
    from generated JS glue instead of being imported.

### Phase 4: MoonBit -> TypeScript Package Quality (78% -> 84%)

- [x] Improve method / constructor facade generation beyond the current narrow
  safe subset.
  - Facade generation now includes non-generic async constructors and instance
    methods, emits Promise-returning TypeScript declarations, and post-processes
    generated JS so plain async exports return Promises while async+raise exports
    preserve the Result wrapper expected by the declaration contract.
- [x] Define the public rule for traits:
  - Public traits are represented as declaration-only structural TypeScript
    interfaces.
  - Local `impl Trait for Type` relationships are represented in `.d.ts` output
    as `extends Trait` or type intersections where possible.
  - Trait methods are not generated as runtime bridge exports or facade
    functions; omitted runtime members remain visible through autolink
    diagnostics.
- [x] Preserve MoonBit `raise` effects in TypeScript declarations as a documented
  error contract.
  - Top-level and trait method `raise` effects now render as
    `Result<Return, ErrorType>` in generated TypeScript declarations, matching
    the JS backend's result-wrapper runtime shape.
- [x] Improve child-package and subpath export coverage:
  - [x] root exports
  - [x] nested package exports
  - [x] generated `package.json` `exports`
  - [x] matching JS and `.d.ts` paths
  - The counter scaffold fixture now includes `./child/grand`, and
    `verify-scaffolds` imports the generated nested subpath through Node while
    checking matching package metadata and `.d.ts` declarations.
- [x] Add generated source map and package metadata checks to the verification
  rail.
  - `verify-scaffolds` checks generated `package.json` package names, subpath
    exports, runtime JS files, and source map files for the scaffold fixtures.
- [x] Make facade generation deterministic and diff-friendly for review.
  - Glue declarations, `link.js.exports`, generated package `exports`, and
    child-package runtime re-export files are sorted with an explicit ascending
    string comparator instead of relying on source or map iteration order.

### Phase 5: Real-World Corpus Expansion (84% -> 88%)

- [x] Lock a TypeScript corpus that covers different API shapes:
  - small function libraries: `clsx`, `date-fns`
  - class/value libraries: `chalk`, `dotenv`
  - schema libraries: `zod`
  - web libraries: `hono`, `preact`
  - Node built-ins: `node:fs`, `node:sqlite`, `node:path`, `node:crypto`,
    `node:os`, `node:url`, `node:querystring`, `node:assert`, `node:util`,
    `node:buffer`
  - callback-heavy APIs: `node:fs`, `node:util`
  - Promise-heavy APIs: `execa`
  - CJS / export-assignment style APIs: `source-map`, Node built-ins
  - Current locked probe entries: `clsx`, `chalk`, `dotenv`, `ignore`, `hono`,
    `zod`, `date-fns`, `colorette`, `magic-string`, `source-map`, `valibot`,
    `immer`, `execa`, `preact`, `node:sqlite`, `node:fs`, `node:path`,
    `node:crypto`, `node:os`, `node:url`, `node:querystring`, `node:assert`,
    `node:util`, `node:buffer`.
- [x] Lock a MoonBit corpus that covers:
  - root-only packages
  - child-package exports
  - effectful APIs
  - generic APIs
  - private root types
  - packages with external JS bindings
  - Current checked entries: `mizchi/ast_printer`, `mizchi/js`,
    `mizchi/jsonschema`, `mizchi/markdown`, `mizchi/nom`,
    `mizchi/pixelmatch`, `mizchi/ripple`, `mizchi/semver`, `mizchi/svg`,
    `mizchi/syntree`, `mizchi/tempfile`, `mizchi/threads`, `mizchi/vfs`,
    `mizchi/jwt.mbt`, `mizchi/zlib`.
- [x] Add per-package smoke programs that use meaningful APIs, not only compile
  the generated bridge.
  - The TypeScript real-world corpus now emits package-specific MoonBit smoke
    programs and runs the built JS with Node after `moon build --target js`.
  - The MoonBit real-world corpus now includes package-specific Node smokes for
    representative APIs, including `svg`, `threads`, and `zlib`.
- [x] Keep each real-world failure as a minimized fixture before fixing it.
  - The `node:assert` missing runtime binding failure is covered by
    `unique-symbol-runtime-export-entry.d.ts`.
- [x] Track corpus status in a generated markdown report checked by CI or an
  opt-in verification task.
  - `just verify-realworld-typescript` writes
    `_build/realworld-typescript/METRICS.md`.
  - `just verify-realworld-moonbit` writes
    `_build/realworld-moonbit/REPORT.md`.

### Phase 6: Productization and Safety (88% -> 90%)

- [x] Define the public CLI contract:
  - [x] `mbt2ts --input mizchi/foo --out dist`
  - [x] `ts2mbt --input npm-package --out dist`
  - [x] `--module-spec` (`ts2mbt` only)
  - [x] `--diagnostics`
  - [x] `--strict`
  - The `tsmbt` binary was split into per-direction `ts2mbt` / `mbt2ts`
    binaries; the `--direction` flag was retired since each binary picks
    its own direction. Unified CLI help, parser tests, and README now
    document the per-binary public contract.
- [x] Add strict mode that fails on any unsupported export or unbudgeted
  `JSValue` fallback.
  - TS -> MoonBit strict mode rejects ambiguous/unsupported export surfaces
    before generation and generated `JSValue` fallback occurrences after
    generation, while writing diagnostics.
  - MoonBit -> TypeScript strict mode rejects omitted autolink members reported
    in `AUTOLINK_DIAGNOSTICS.md`.
- [x] Add non-strict mode that always emits a buildable scaffold with diagnostics
  when possible.
  - Unified TS -> MoonBit now always writes `SCAFFOLD_DIAGNOSTICS.md` or the
    requested `--diagnostics` path after scaffold generation.
  - Unified MoonBit -> TypeScript continues to write `AUTOLINK_DIAGNOSTICS.md`
    and can mirror it to `--diagnostics`.
- [x] Add snapshot tests for generated file layout and package metadata.
  - Unified MoonBit -> TypeScript and TypeScript -> MoonBit tests now assert
    generated file layouts and package metadata for the public CLI path.
- [x] Document supported TypeScript and MoonBit subsets with examples.
  - README now includes supported subset examples for both bridge directions.
- [x] Add a release checklist:
  - [x] fixture CI
  - [x] real-world TypeScript probe
  - [x] real-world MoonBit probe
  - [x] generated docs update
  - [x] changelog entry

### Explicit Non-Goals Before 90%

- [ ] Do not attempt full TypeScript type-checker parity.
- [ ] Do not implement arbitrary TypeScript conditional/mapped type semantics
  unless a real-world target needs the subset.
- [ ] Do not promise arbitrary npm package conversion without diagnostics.
- [ ] Do not hide widened or omitted API surfaces; every fallback must be
  inspectable.

## Parser / Semantics Real-World Gaps

### Current bug
- [x] `emit-moonbit-decl` / `emit-moonbit-js-ffi` should not resolve non-exported opaque type imports.
  - Symptom: an entry like `import { ResultAsync, type Result } from "neverthrow"` crashed when the package actually existed under `/tmp/.../node_modules`.
  - Cause: `load_type_module_graph` eagerly resolved every import specifier even when the imported binding was never exported or re-exported from the entry surface.
  - Fix direction: keep re-exports / exported imports in the graph, but leave plain opaque imports unresolved.

### Remaining work
- [x] Add a stable end-to-end regression harness for the external `/tmp/tsmbt-realworld-check` repro instead of relying on ad-hoc local verification.
  - Covered by the `/tmp/ts_mbt_neverthrow_like_*` regression tests in `src/main_wbtest.mbt`, which exercise `emit_moonbit_decl_text` / `emit_moonbit_js_ffi_texts` against a pnpm-style temp project layout.
- [x] Minimize a fixture from the actual `neverthrow` package if more parser coverage is needed beyond the graph-resolution fix.
  - Covered by `fixtures/resolver/project/types/neverthrow-like-entry.d.ts` plus the pnpm-style `fixtures/resolver/project/node_modules/neverthrow-like` fixture, and exercised through decl / JS FFI / scaffold generation.

## MoonBit / TypeScript Package Bridge Plan

Generate TypeScript-consumable bridge artifacts from MoonBit package interfaces without hand-writing `link.js.exports`, and keep the reverse `TS -> MoonBit` path aligned around the same surface model.

### Batch 1: MBTI autolink bootstrap

- [x] Emit `link.js.exports` JSON config from `.mbti` top-level public free functions.
- [x] Exclude methods / constructors / trait methods from the generated JS export surface.
- [x] Add CLI coverage so the generated config can be written directly from `pkg.generated.mbti`.

### Next batches

- [x] Add a recursive `.mbti` resolver so generated `.d.ts` imports can be rewritten to generated sibling packages instead of raw MoonBit package specifiers.
- [x] Add a high-level `MoonBit -> TS package scaffold` command that generates temporary autolink glue, runs `moon build --target js`, and emits a JS-backed `.d.ts` package.
- [x] Align the reverse `TS -> MoonBit bridge package` flow on the same top-level export surface model and resolver assumptions.

## Bridge / Scaffold Operational Hardening

### P0

- [x] Harden unsupported export handling in `emit-moonbit-scaffold-from-ts`.
  - Namespace exports are supported as opaque getters, and ambiguous re-exports no longer block scaffold generation; they are widened/omitted consistently with the low-level emitters and reported in `SCAFFOLD_DIAGNOSTICS.md`.
- [x] Add `just verify-scaffolds` and wire it into `just ci`.
  - Acceptance: `emit-typescript-scaffold-from-mbti` produces build-backed `index.js`, is compiled with `tsc`, and is smoke-tested through Node import; `emit-moonbit-scaffold-from-ts` is compiled/tested with `moon check/test --target js`.
- [x] Add external import rewrite mapping for `emit-typescript-scaffold-from-mbti`.
  - `emit-typescript-package-from-mbti` / `emit-typescript-scaffold-from-mbti` now accept an optional JSON rewrite map and apply it before writing external `.d.ts` imports.

### P1

- [x] Generate publish-ready metadata for `MoonBit -> TS` scaffold output.
  - `emit-typescript-scaffold-from-mbti` now writes `package.json` with `name`, `type`, `types`, `import`, and per-subpath `exports.types` entries alongside build-backed `index.js` / `.d.ts` files. Temporary `moon.pkg.json` glue is created only inside the source module and removed after `moon build --target js`.
- [x] Decide how to handle methods / static members omitted from `link.js.exports`.
  - The default scaffold still emits `AUTOLINK_DIAGNOSTICS.md` so omissions are explicit, strips runtime-inaccessible method declarations from package `.d.ts`, and `emit-typescript-facade-scaffold-from-mbti` now provides an opt-in wrapper path for root-package local non-generic methods / constructors.

### P2

- [x] Minimize a stable real-world fixture from `neverthrow` if broader package-surface coverage is still needed.
  - `just verify-scaffolds` now exercises the stable `neverthrow-like` fixture end-to-end, including generated MoonBit scaffold compile/test under JS.

### P3

- [x] Revisit broader `namespace export` support after the scaffold path is stable.
  - `emit-moonbit-scaffold-from-ts` now accepts namespace exports and exposes them as opaque getter functions in the generated package. Ambiguous re-exports are emitted conservatively and surfaced in scaffold diagnostics instead of failing fast.

## TS Bridge Constraints

- [x] Prefer direct `#module("...")` imports when the runtime `moduleSpec` is non-relative.
  - Works for bare specifiers, `node:*`, and rooted specifiers like `/src/api/client.ts`.
  - This now covers top-level function exports, instance methods/properties, and class constructors.
  - Bare package `default` function exports are intentionally routed through
    `bridge.js`; this avoids MoonBit JS backend default binding mismatches for
    CJS packages such as `express`.
- [x] Keep `bridge.js` fallback for relative module specs like `./client.js` and `../client.js`.
  - MoonBit currently rejects relative paths in `#module("...")`.
- [x] Keep wrappers for static members / value exports / namespace exports for now.
  - `= "Counter.from"` / `= "Counter.version"` style dotted import names compile poorly in the current JS backend.
  - `#module(...)` combined with inline `#|` JS also does not lower correctly for imported module bindings in the current backend.

## TS Enum / Literal Union Design

Goal: represent the safe TypeScript enum-like subset as MoonBit `enum` without
lying at the JS boundary. The generated public MoonBit API should be pleasant to
use, while the generated bridge must still pass the exact primitive values that
TypeScript runtimes expect.

### Scope

- [x] Support named string literal unions as closed MoonBit enums:
  - `type Variant = "primary" | "secondary"` ->
    `pub(all) enum Variant { Primary; Secondary }`.
  - Optional unions preserve optionality:
    `"primary" | "secondary" | undefined` -> `Variant?`.
  - Direct anonymous literal unions on exported fields / params / returns now
    receive stable synthetic names such as `ButtonOptionsVariant` and
    `RenderButtonReturn`.
- [x] Support boolean literal unions only when they are not just `boolean`:
  - `true | false` remains `Bool`.
  - `true | undefined` remains `Bool?`.
  - Named boolean literal aliases now resolve through primitive `Bool` /
    `Bool?` bridge signatures instead of emitting enum wrappers.
- [x] Support numeric literal unions only when every member is an integer-like
  literal and the runtime bridge can convert losslessly.
  - [x] Named numeric literal union aliases lower to closed MoonBit enums and
    bridge through raw `Int` params / returns.
  - [x] Direct anonymous numeric literal unions use the same synthetic naming
    pass and bridge through raw `Int` params / returns.
- [x] Support ambient / declaration enum surfaces:
  - `declare enum Mode { Read = "read" }`
  - `declare const enum Mode { Read = "read" }`
  - implicit numeric members are allowed only when all previous values can be
    evaluated statically.
  - [x] Parser preserves `declare enum` / `declare const enum` in `TsModule`,
    including declared namespaces, and bridge package output now exposes those
    enums in both `bridge.mbt` and `bridge.mbti`.
  - [x] Raw extern wrappers keep string enums primitive and expose public
    MoonBit enum wrappers for params and returns.
  - [x] Optional string enum params / returns use `Variant?` conversion and
    keep JS `undefined` behavior.
  - [x] Raw extern wrappers keep statically evaluable numeric enums as `Int`
    and expose public MoonBit enum wrappers for params and returns, including
    optional `Variant?` conversion.
- [x] Defer heterogeneous enum unions and non-literal computed enum values to
  the existing primitive / `JSValue` fallback with diagnostics.

### Internal Model

- [x] Replace or extend the current `TsType::Literal(String)` representation.
  - Current parser stores string `"1"` and numeric `1` both as `Literal("1")`,
    which is not precise enough for bridge conversion.
  - Add a typed literal model, e.g. `TsLiteralValue::{String, Number, BigInt,
    Bool}`, and keep helper functions so existing `keyof` / object-key logic
    can continue treating string keys uniformly.
  - `TsType` now keeps string literal/object keys as `Literal(String)` while
    preserving non-string literal types as `NumberLiteral`, `BigIntLiteral`,
    and `BooleanLiteral`.
- [x] Add AST nodes for enum declarations:
  - `TsEnumDecl { name, members, is_const, is_declare }`
  - `TsEnumMember { name, value : TsLiteralValue? }`
  - Store them in `TsModule` and `TsModuleBlock`, parallel to interfaces and
    type aliases.
  - [x] Added `TsEnumDecl`, `TsEnumMember`, and `TsEnumMemberValue` to
    `TsModule`; module-block export collection now recognizes
    `export declare enum` for bridge export surfaces.
  - [x] `TsEnumMember.is_computed` now distinguishes implicit numeric enum
    members from non-literal computed initializers.
  - [x] `TsModuleBlock` still needs a first-class enum array if script-level
    enum declarations need to be preserved beyond export metadata.
- [x] Normalize type aliases that are pure string literal unions into an enum-lowering
  candidate before `emit_moonbit_decl` / `emit_moonbit_js_ffi` renders types.
  - Keep the original alias name as the MoonBit enum name.
  - If the alias is anonymous inside a parameter or field, keep the current
    primitive fallback until a stable synthetic naming rule is needed.

### MoonBit Surface

- [x] Emit public enum declarations in both `bridge.mbt` and `bridge.mbti`.
  - This must mirror the recent struct rule: generated implementation and
    interface files expose the same public shape.
  - [x] Ambient enum exports are emitted as `pub(all) enum` in both package
    implementation and interface output.
  - [x] Runtime TypeScript `export enum` declarations are preserved through
    `TsModuleBlock` export discovery and emitted in package bridge output.
- [x] Generate stable constructor names:
  - sanitize to PascalCase;
  - suffix MoonBit keywords;
  - disambiguate collisions deterministically;
  - preserve the original TS literal in generated conversion helpers.
- [x] Keep raw externs primitive and wrap them for string enums:
  - Params: public function accepts `Variant`, private/raw extern accepts
    `String`.
  - Returns: raw extern returns primitive, public wrapper converts to
    `Variant`.
  - Optional params / returns use `Variant?` wrappers and keep JS `undefined`
    behavior through generated optional conversion helpers.

Example target shape:

```moonbit
pub(all) enum ButtonVariant {
  Primary
  Secondary
} derive(Eq, Debug)

fn ButtonVariant::to_js(self : ButtonVariant) -> String {
  match self {
    Primary => "primary"
    Secondary => "secondary"
  }
}

fn button_variant_from_js(value : String) -> ButtonVariant {
  match value {
    "primary" => Primary
    "secondary" => Secondary
    _ => abort("unexpected ButtonVariant value")
  }
}

extern "js" fn render_button_raw(variant : String) -> Unit = "__ts_mbt_render_button"

pub fn renderButton(variant : ButtonVariant) -> Unit {
  render_button_raw(variant.to_js())
}
```

### JS Bridge Rules

- [x] Do not pass MoonBit enum runtime objects directly to JS APIs for string
  enums.
  - MoonBit JS backend enums are tagged values; TypeScript libraries expect the
    primitive literal value.
- [x] Prefer MoonBit-side conversion wrappers over JS-side enum construction.
  - JS bridge code cannot reliably construct MoonBit enum values unless those
    constructors are exported by the compiled MoonBit package.
  - Return conversion should therefore happen in generated MoonBit wrapper
    code from raw primitive externs.
- [x] Reuse the existing optional object-field converter only after enum values
  have been converted to primitives.

### Diagnostics and Safety

- [x] Add diagnostics for every enum-like surface that is not lowered:
  - [x] mixed string/number enum;
  - [x] computed enum member;
  - [x] duplicate literal values after sanitization;
  - [x] mixed / non-integer / bigint named literal-union aliases;
  - [x] anonymous literal union without a stable public name.
- [x] Keep strict mode behavior unchanged: unsupported enum lowering in a
  public surface must either fall back within budget or fail with an actionable
  diagnostic.
- [x] Add real-world probes after fixtures pass:
  - [x] Node string modes / flags;
  - [x] React string literal props;
  - [x] Hono option modes;
  - [x] TypeScript AST `SyntaxKind`-style numeric enum as an `Int` bridge
    stress case.

### TDD Order

- [x] Red: parser tests for string/numeric/const enum declarations and typed
  literal unions.
- [x] Green: AST + parser support without bridge lowering.
- [x] Red: declaration generation tests for named literal-union aliases.
- [x] Green: emit MoonBit enum declarations in `.mbt` / `.mbti`.
- [x] Red: JS-target smoke where a MoonBit enum argument reaches a TS function
  expecting a string literal.
  - `fixtures/bridge_smoke/enum-entry.d.ts` verifies generated code passes
    primitive string enum values through `moon check --target js` and
    `moon test --target js`.
- [x] Green: raw extern + public wrapper conversion for params.
- [x] Red: JS-target smoke where a TS function returns a literal union and
  MoonBit pattern matches the result.
  - Named string literal union aliases are covered by
    `fixtures/bridge_smoke/literal-union-alias-entry.d.ts`.
- [x] Green: primitive return conversion with an explicit unexpected-value
  abort path.
- [x] Refactor: share enum metadata between decl, FFI, and package bridge
  emitters so literal-union and `declare enum` use the same lowering path.
  - [x] Share ambient enum case/value/unsupported-reason lowering between
    declaration diagnostics and FFI generation.
  - [x] Share literal-union alias enum declaration lowering through
    `enum_lowering_type_alias_enum_decl`.

## Normalized DTS Shape-Merge Scope

- [x] Keep object-shape compatibility checks inside `src/bridge/object_shape_merge.mbt`.
  - The helper exists to support `normalize-moonbit-dts`, not to become a full TypeScript checker.
- [x] Keep the shape-merge scope narrow.
  - Current responsibility: decide whether object-like interface expansions can be flattened safely, or should fall back to intersections.
  - Current coverage: duplicate properties, `readonly`, optional-property keys, and "do not merge methods / overload-like members".
- [x] Avoid growing the bridge normalization helper into a full semantic checker unless a separate goal is explicitly chosen.
  - If future work needs real TS semantics, define that as a separate milestone instead of quietly expanding the normalization helper.

## Bridge Const-Table Batch Plan

Reduce the need to pick one edge case at a time by shipping the next `default export const table` batch together and keeping the smoke rail in sync.

### Batch scope

- [x] `import * as tables from "./x"` where `x` exports a const table.
- [x] `import tables from "./x"` where `x` re-exports a named `const TABLES`.
- [x] `import tables from "./x"` where `x` directly `export default { ... }`.
- [x] `import tables from "./x"` where `x` does `export default { ... } as const`.
- [x] `import tables from "./x"` where `x` does `export default (() => ({ ... }))()`.
- [x] `import tables from "./x"` where `x` does `export default (() => { const ...; return TABLES })()`.
- [x] `import tables from "./x"` where `x` does `export default (function() { const ...; return TABLES })()`.

### Acceptance rail

- [x] Add parser regression proving exported const-value collection for each new default-export shape.
- [x] Add decl / JS FFI / bridge-package regressions for each new shape.
- [x] Add bridge smoke fixtures so `just verify-generated-fixtures` and `just ci` execute the generated package under JS.

### Next batch: IIFE local let handling

- [x] `import tables from "./x"` where `x` does `export default (() => { let ...; return TABLES })()`.
- [x] `import tables from "./x"` where `x` does `export default (function() { let ...; return TABLES })()`.
- [x] Keep local `let` mutation conservative: if the returned table depends on reassigned locals, widen instead of resolving statically.
- [x] Add parser / decl / JS FFI / bridge-package regressions for the `let` cases.
- [x] Add bridge smoke fixtures for positive `let` cases and the conservative widened case.

### Next batch: IIFE local mutation conservative handling

- [x] `import tables from "./x"` where `x` mutates `KEYS.nested` before returning the table.
- [x] `import tables from "./x"` where `x` mutates `INDEXES[0]` before returning the table.
- [x] Keep local property/index mutation conservative even when the final runtime value is unchanged.
- [x] Add parser / decl / JS FFI / bridge-package regressions for the mutation cases.
- [x] Add bridge smoke fixtures for the conservative widened mutation cases.

## React / JSX Real-World Support

Keep pushing real package support through `.d.ts` surface parsing and scaffold generation before adding a full JSX expression parser.

### Current status

- [x] Accept `export as namespace ...` without crashing `emit-moonbit-scaffold-from-ts`.
- [x] Flatten `export = React; declare namespace React { ... }` style surfaces into top-level scaffold exports.
- [x] Surface nested `JSX` namespace types from `react`, `react/jsx-runtime`, and `react/jsx-dev-runtime`.
- [x] Normalize the first round of React utility types:
  - `PropsWithChildren<T>`
  - `ComponentProps<"tag">`
  - `ComponentPropsWithoutRef<"tag">`
  - `ComponentPropsWithRef<"tag">`
  - nested `PropsWithChildren<ComponentPropsWithoutRef<...>>`
- [x] Convert known React hook tuple returns into named synthetic result types.
- [x] Preserve optional React-style props/params as `T?` instead of widening everything to `JSValue`.
- [x] Make generated MoonBit identifiers safe for reserved words and dotted ambient names.

### Next work

- [x] Reduce widening around React overload-heavy APIs.
  - Priority targets: `createElement`, `cloneElement`, `forwardRef`, `memo`.
  - [x] Lower `keyof JSX.IntrinsicElements` parameters to `String` for `createElement` / JSX runtime entrypoints instead of `JSValue`.
- [x] Model exotic/callable component surfaces more explicitly.
  - Priority targets: `FunctionComponent`, `ForwardRefExoticComponent`, `MemoExoticComponent`, `NamedExoticComponent`.
  - Callable React component surfaces are emitted as opaque external JS callable types in FFI output instead of fake record structs with `<call>` fields.
- [x] Improve utility/conditional type lowering beyond the first pass.
  - Priority targets: `ReactNode`, `ComponentRef`, `ElementRef`, `LibraryManagedAttributes`, `RefAttributes`.
  - `Partial<T>` / `Readonly<T>` pass through to `T`; `LibraryManagedAttributes<C, P>` lowers to `P`; `ComponentRef<T>` / `ElementRef<T>` lower to `Ref`; `ReactNode` lowers to `JSValue` / `@js.Any` at the generated bridge boundary.
- [x] Add stable end-to-end verification for generated React scaffolds under `moon check/test --target js`.
  - `just verify-scaffolds` now checks React-like JSX, `react/jsx-runtime`, `react/jsx-dev-runtime`, and the Hono options fixture with generated packages under the JS target. The React cases use a local `mizchi/js/core` stub instead of depending on a separate checkout.
- [x] Add stable fixture coverage for `react`, `react/jsx-runtime`, `react/jsx-dev-runtime`, and `hono/jsx`.
  - Keep real-world probe findings as minimized fixtures instead of ad-hoc `/tmp` checks.
  - Minimized package fixtures live under `fixtures/resolver/project/node_modules/react` and `fixtures/resolver/project/node_modules/hono`; `just verify-scaffolds` now compiles/tests generated MoonBit packages against those package names.
- [x] Keep JSX parser work deferred until `.d.ts` type-surface parsing is no longer the blocker.
  - Re-evaluate only if React/Hono support hits syntax that cannot be represented from declaration files alone.

## Real-World MoonBit Package Probe

- [x] Support `tsmbt --input mizchi/foo --out dist/` style ghq package resolution for MoonBit packages.
- [x] Verify build-backed `MoonBit -> TypeScript` scaffold generation through `moon build --target js` for local `mizchi/ripple`, `mizchi/semver`, and `mizchi/tempfile` checkouts.
  - `just verify-realworld-moonbit` is optional and skipped package-by-package when those local ghq checkouts are absent.
- [x] Broaden the local real-world probe set to `mizchi/ast_printer`, `mizchi/js`, `mizchi/jsonschema`, `mizchi/markdown`, `mizchi/nom`, `mizchi/pixelmatch`, `mizchi/syntree`, `mizchi/tui`, `mizchi/vfs`, and `mizchi/jwt.mbt`.
- [x] Resolve ghq packages whose repository name differs from their MoonBit module name by reading `moon.mod.json` metadata.
- [x] Preserve MoonBit `raise` effects in temporary glue wrappers so effectful packages such as `mizchi/semver` build.
- [x] Skip facade wrappers that would expose private root types from the source package; the generated `.d.ts` can still document those opaque types, but glue packages cannot refer to private MoonBit symbols.
- [x] Qualify local root trait bounds in temporary glue wrappers so generic packages such as `mizchi/nom` build.
- [x] Emit child-package runtime re-export files and facade declarations so recursive MoonBit -> TypeScript packages expose matching `.d.ts` and JS subpaths.
- [x] Add stable real-world MBTI declaration snapshots for `mizchi/ast_printer` and `mizchi/jsonschema` to default fixture typechecking.
- [x] Re-run the local real-world MoonBit probe and confirm the current package set passes generated JS import and declaration typecheck.
- [x] Investigate packages that fail before or during source JS build for reasons outside the generated glue surface.
  - `mizchi/ast_printer` was fixed by updating its `moonbitlang/parser` dependency from `0.1.15` to `0.2.5` and adapting the printer to the current parser AST (`type P = Point` aliases, no removed top-level alias constructors, `TypeDesc::Record(fields~, ..)`).

## CI Notes

- Default `just ci` remains fixture-based and does not require local ghq checkouts.
- `just verify-realworld-moonbit` is intentionally outside default CI because it probes developer-local MoonBit repositories and writes temporary glue packages into those source modules during `moon build --target js`.
- `just verify-realworld-typescript` is intentionally outside default CI because it probes a developer-local npm package corpus via `TSMBT_REALWORLD_TYPESCRIPT_NODE_MODULES`.

## Beyond 90%: Bridge Quality Gaps for Tier 2 / Tier 3 Packages (2026-05-03)

After the 90% gate, the remaining `naturalize-target` and `budgeted-fallback`
JSValue surfaces are dominated by a small set of structural limitations rather
than ad-hoc fixes. The previous demand-driven plateau was reached at hono = 50,
date-fns = 22, jose = 84, react-router = 194, etc., where each remaining
fallback traces to one of the items below. Each item is a multi-commit
structural change, not a one-off lowering tweak.

Priority is by impact on real-world bridge JSValue surface, not by ease.

### 1. Heterogeneous union -> auto-enum (highest ROI, bridge-local)

Patterns: `number | string | Date` (jose setters), `(string | number)[]` (immer
Patch.path), `string | string[]`, `boolean | "boundary"` (magic-string hires),
`boolean | OverwriteOptions` (magic-string), schema-leaf branches in zod /
valibot.

- [x] Detect heterogeneous unions whose members can each be discriminated at
  runtime (`typeof` for primitives, `instanceof` for known classes, optional
  fallback for plain objects).
- [x] Lower the alias / synthetic-named union into a `pub(all) enum` with one
  case per member, where each case wraps the lowered MoonBit type (e.g.
  `Number(Double) | StringValue(String) | DateValue(Date)`).
- [x] Generate paired conversion helpers: MoonBit-side `to_js(self) -> JSValue`
  using primitive coercions, and JS-side discrimination wrappers in
  `bridge.js`.
- [x] Reuse the existing literal-union synthetic naming pass for anonymous
  heterogeneous unions on params / fields / return types.
  - Mixed primitive + string/number/bigint/boolean literal unions now lower
    too: literal cases become no-payload enum constructors (e.g. `Boundary`)
    discriminated via `=== "boundary"`. Pure literal unions still defer to
    `enum_lowering`, and a literal whose primitive type collides with a
    non-literal sibling stays on JSValue.
- [x] Auto-wrap return values to the MoonBit-side `<alias>_from_js`
  representation when the discriminator is purely typeof / isArray / strict
  equality. Tagged-union aliases that depend on `instanceof <NamedClass>`
  (e.g. `ServerType = Server | Http2Server | Http2SecureServer` from
  `node:net` / `node:http2`) are skipped because the named classes aren't
  reachable from `bridge.js`.
- [x] Emit diagnostics and stay on JSValue when discrimination is ambiguous
  (e.g. two struct members with overlapping shapes).
  - `tagged_union_widen_reason_for_alias` reports the rejection cause
    (overlapping primitive discriminator, non-PascalCase / non-discriminable
    member, or duplicate constructor name) and the resolution chain in
    `moonbit_decl.mbt` surfaces it as a `Unsupported export <Name>: ...`
    comment in the generated `bridge.mbti`. Pure-literal unions still
    defer silently to `enum_lowering`, and `null` / `undefined` markers
    are filtered out before evaluating discrimination so plain optional
    widening doesn't get diagnosed.
- [x] Add real-world budgets: jose, magic-string, immer, and zod / valibot
  schema leaves where applicable.
  - `just verify-realworld-typescript` is back to a green baseline across
    all 24 corpus entries; per-package `JSValue` cause budgets, function
    counts, and unsupported-export budgets now reflect the actual
    generated output, including the new heterogeneous-union diagnostics.
- [x] Drive the `heterogeneous-union-widened` budget back to 0 (done
  2026-07-15, same day it was added). Four lowerings landed:
  - qualified namespace refs resolve to their flattened export name
    before classification (`JSX.Element` -> `JsxElement`, hono `Child`);
  - function members discriminate via `typeof === "function"` and render
    as arrow payloads (`FnValue(() -> String)` — drizzle `NeonAuthToken`,
    react `ElementType`); inline `Auto_*` synthesis still excludes
    function members (the useState wrapper glue can't produce the enum);
  - branded-string intersections collapse to `string` and the
    LiteralUnion pattern collapses to a plain String alias
    (vitest `CancelReason = "a" | "b" | (string & Record<string, never>)`);
  - indexed access over an EMPTY registry interface reduces to `never`
    and drops from the union (vitest
    `TestArtifact = A | B | C | Registry[keyof Registry]`).

### 2. Method-level generics preserved through bridge

Patterns: `Hono<E,S,P>.get<Path extends string>(path: Path, handler):
Hono<E, S, P | Path>`, `Session.get<Key extends keyof Data>(key: Key)`,
`zod.object<T extends ZodRawShape>(shape: T)`.

- [x] Capture method-level type parameter lists (and bounds) on
  `TsClassMethodDecl`. (commit `eeb94a6`)
- Investigation result (2026-05-03): bound substitution at method
  boundaries is **already happening** in `parser_type.mbt:639`
  (`local_type_param_bound`), which short-circuits any `Ident(name)`
  to its registered bound during type parsing. Methods like
  `HonoRequest.valid<T extends keyof ValidationTargets>(target: T)`
  already render as `valid(target : String) -> ...` because `T` is
  substituted away before the AST escapes the parser.
- MoonBit JS backend rejects `pub extern "js" fn[T] ...`
  (`Error 4008: FFI function cannot have type parameters`), so a
  generic-preserving public signature would require a separate
  wrapper layer (`pub fn[T] Class::method(...) { Class::method_raw(...) }`).
  This only buys typing precision when the bound is itself
  representable as a MoonBit trait, which is rare for the
  string-literal / interface bounds used in real corpora.
- [x] Conclusion: keep the AST fields populated so a later
  wrapper-layer pass can use them, but do not generate a separate
  generic surface yet. The bound-substitute path covers the common
  cases. Revisit only when a real-world consumer needs a generic
  return type that is not represented by the substituted bound.

### 3. Mapped type partial evaluation + conditional reduction depth

Patterns: zod `output<T>` / `infer<T>` mapped types, valibot equivalent,
date-fns `EachDayOfIntervalResult<I, O>` (Array<conditional + infer + indexed
access>), jose key-typed builders.

- [x] Extend `simplify_type` so distributive conditional types reduce when each
  branch resolves to the same concrete shape after bound substitution and
  infer extraction. (Done via the `Union` source path in `simplify_type` —
  every leaf must resolve definitively; otherwise the conditional is
  preserved for a later retry.)
- [~] Branch-join over `Array<Conditional<...>>`: the simplifier reduces a
  union of conditionals when every branch decides, but doesn't yet
  collect leaf branches and accept the join when only the terminal-default
  shape matches. Low real-world ROI; left for later.
- [x] Lower mapped types with key remapping (`{ [K in keyof T as ...]: ... }`)
  for the common output-shape pattern used by zod / valibot. (Implemented
  via `MappedTypeRemap` + `simplify_mapped_type_remap`.)
- [x] Treat unresolvable infer patterns as their bound rather than `JSValue` so
  generic `infer DateType extends Date` collapses to `Date` at the bridge
  boundary. (`moonbit_decl.mbt` / `moonbit_js_ffi.mbt` consult
  `infer_marker_bound` at the surface boundary;
  `match_infer_pattern` now also rejects sources definitively disjoint
  from the bound at match time.)

### 4. Template literal types

Patterns: node:util `InspectColorBackground = bg${Capitalize<InspectColorForeground>}`,
react-router path patterns, zod template-literal validators.

- [x] Add AST nodes for template literal types (`TsType::TemplateLiteralType`)
  including `Capitalize` / `Lowercase` / `Uppercase` / `Uncapitalize` intrinsic
  string-mapping types.
- [x] Resolve template literal types to a string-literal union when the
  parameter is a finite string-literal union. (`simplify_template_literal`
  cartesian-products the part / arg pairs.)
- [x] Reuse the existing string-literal-union enum-lowering path for template
  literal types whose parameter union is small and safely PascalCase-able.
  (Bridge enum lowering walks the template result.)
- [x] Otherwise fall back to `String` rather than `JSValue` when the template
  shape is statically known to produce strings.
  (`TemplateLiteralType(_, _) => "String"` in both decl / FFI renderers.)

### 5. JSX / component layer

Patterns: preact / react-router component definitions, `FunctionComponent<P>`,
`ForwardRefExoticComponent`, JSX intrinsic elements.

- [~] Open design decision: a JSX-aware bridge layer ships as MoonBit-native
  types in the existing bridge. No separate generator output is planned.
- [x] Preserve `FunctionComponent<P>` as a callable opaque whose props are
  represented as the resolved `P` struct. (Done via the React-specific
  utility lowering pass; callable component surfaces are emitted as opaque
  external JS callable types.)
- [~] Lower `JSX.Element` to a JS-opaque type that round-trips through bridge
  glue without widening to `JSValue` for every render call. Current state
  collapses `JSX.Element` to `@js.Any` at the bridge boundary; a dedicated
  opaque type per JSX namespace is still open.
- [~] Re-evaluate preact / react-router naturalize budgets after JSX layer.
  Budgets updated as needed when the bridge realigns; no fresh pass is
  scheduled.

### 6. Class static-side / index signature / module augmentation

Patterns: jose builder pattern (`new SignJWT(payload).setIssuedAt()...`),
magic-string `MagicString` static helpers, hono `c.set()` per-context
augmentation, React `HTMLAttributes` index signatures.

- [x] Class static-side (`typeof Class`) merging: `PropAccess` on a class
  identifier consults `globals[Name.member]` (which catches namespace + class
  declaration merging) and the class's static methods / properties before
  falling back to instance-side lookup.
- [x] Lower `[key: string]: V` index signatures: `TsClassDecl.index_signatures`
  carries the parsed entries and `lookup_class_field` falls through to
  `index_signature_value` after exhausting named members. The
  `TsInterface` side already worked.
- [x] Module augmentation graph: `TsModule.module_augmentations :
  Array[(String, TsModule)]` records every `declare module "X" { ... }`
  block by specifier; declarations still flow into the surrounding scope
  for legacy consumers.

### 7. Modern syntax follow-ups (smaller)

- [x] `satisfies` operator at the expression level. (Parser retains
  `Satisfies(expr, ty)`; checker validates assignment in
  `check_call_args_in_expr`.)
- [x] Stage-3 decorators on classes. (`TsClassDecl.decorators` retains the
  parsed `@expr` chain.)
- [x] `using` / `await using` declarations including `export using` at the
  module export position.
- [x] Const generics (`<const T>`). Retained on `TsFunc.const_type_params`
  and consulted by the JSX generic-component inference path to skip
  literal widening when any of the component's type parameters carries
  the modifier.

### 8. Polymorphic `this` keeps fluent chains typed (done 2026-07-15)

Patterns: zod `ZodType.check(...): this` / `optional(): ZodOptional<this>`,
builder chains like jose `SignJWT.setIssuedAt(): this`, generic classes
with `merge(other: this): this`.

- [x] `this` in interface members and class methods now lowers to the
  owning declaration applied to its own type parameters
  (`Schema[Output, Input, Internals]`) instead of `Named(owner)` +
  the `JSValue` arity filler (`Schema[JSValue, JSValue, JSValue]`).
  The substitution is root-scoped: members merged in from `extends`
  expansion also resolve `this` to the derived struct, matching TS
  semantics and keeping every substituted param in scope.
  Implemented in `decl_this_owner_type` / `decl_replace_this_type`
  (now recursing through `Func` params and returns as well, so
  `apply((this) => R)`-style callback params stop leaking a raw
  `This` opaque type). zod: SCAFFOLD JSValue fallback entries
  748 -> 648; the whole fluent core (`check` / `clone` / `optional` /
  `nullable` / `describe` / ...) keeps `Schema[Output, Input, Internals]`.

### 9. Generic free functions export via monomorphized glue (done 2026-07-15)

Previously every `pub fn[T] ...` free function was omitted from
`link.js.exports` and listed in `AUTOLINK_DIAGNOSTICS.md`.

- [x] Unconstrained generic free functions now export through autolink
  glue: type parameters are instantiated at an opaque
  `#external pub type TsMbtGenericAny` (values cross the JS boundary
  unchanged, which is exactly parametric behavior), the glue wrapper is
  therefore non-generic and exportable, and the emitted `.d.ts` keeps the
  original generic signature (`export function identity<T>(value: T): T`).
- [x] Bare `T?` returns unwrap to `value | undefined` via a
  `tsmbt_generic_undefined()` extern, because `Option[TsMbtGenericAny]`
  crosses the boundary in the boxed `{_0}` representation.
- [x] Eligibility is decided by `mbti_generic_glue_return_plan` and shared
  by the glue emitter, the runtime-inaccessible screening, and the
  diagnostics list. Ineligible (stay omitted): trait bounds (`[T : Show]`),
  type params inside tuples (MoonBit tuples are not JS arrays), type params
  under `Option` anywhere except the bare top-level return, and optional
  params (`name? : T`).
- Runtime verified with a node smoke: `identity(obj) === obj`,
  `identity(undefined) === undefined`, `first([]) === undefined`,
  `first([10, 20]) === 10`; `tsc --strict` accepts a typed generic consumer
  of the emitted `.d.ts`.
- Next increments: generic methods on non-generic owners (same
  monomorphization through the facade path), then generic owners.

### 10. String-subset boundary for optional-message unions (done 2026-07-15)

Pattern: zod's check surface passes `params?: string | $ZodCheckMinLengthParams`
on nearly every validator (`min`, `max`, `length`, `regex`, ...). The
`$`-prefixed name cannot become a tagged-union constructor (names must start
`A-Z`), so the whole param degraded to `JSValue?`.

- [x] `ffi_string_subset_union_text`: a two-member union pairing `string`
  with a named `*Params` bag that is NOT a declared type on the bridge
  surface now types the boundary as `String`. The common string form is
  naturally typed; the structured object form stays reachable via
  `unsafeCast`. Guards: exactly two members, `Params` suffix required,
  abstains when the named type is declared / a generic param / a local type
  param — so option-bag unions with reachable declarations keep their
  tagged lowering and `string | URL` keeps the JSValue fallback.
- zod: SCAFFOLD JSValue fallback entries 648 -> 565
  (`min : (Double, String?) -> ZodMap[Key, Value]` etc.); the regenerated
  zod3 package passes `moon check --target js`.
- Note: per-package JSValue counts in the env-gated realworld METRICS
  corpus may drift downward next time it is regenerated — the budget file
  encodes upper bounds, so this is safe, but expect diffs there.

### 11. zod fallback batch 2: decl-path subset, hidden members, bounds, lib prelude, predicate folding (done 2026-07-15)

Five lowerings driven by the remaining zod JSValue-fallback clusters. zod
SCAFFOLD fallback entries: 565 -> 241 (and the entries that remain are
dominated by `data: unknown` params and `unknown | Promise<unknown>`
callback returns, where `JSValue` is the semantically correct type).

- [x] The string-subset policy now also covers the DECL emitter
  (`moonbit_type_name` in `parser_moonbit.mbt` mirrors the FFI rule) and
  accepts `Applied(*Params, ...)` shapes — qualified aliases like
  `core.$ZodEmailParams` resolve into applied generic aliases the decl
  layer cannot expand, and previously missed the `Named`-only match.
  Every classic factory (`email` / `uuid` / `cuid` / ... ~40 fns) and the
  `ZodString` format methods now take `String?`.
- [x] `@internal` members are omitted from bridge scaffolds entirely
  (tsc's stripInternal semantics); `@deprecated` members survive only
  while they type naturally — one that could only widen to `JSValue`
  (zod's `_def` / `_input` / `_output`) is dropped. Tags are parsed from
  member-level JSDoc (`TsInterface.internal_members` /
  `deprecated_members`), travel through `extends` flattening, and gate
  both the decl emitter and the FFI struct decl + its bridge.js converter.
- [x] Constrained generic METHOD type params substitute their bounds at
  the boundary (`TsInterface.method_type_param_bounds`, applied in
  `append_interface_origin_fields`): every argument for a
  `pipe<T extends $ZodType>(target: T)` slot satisfies the bound, so
  `pipe` / `or` / `and` / `apply` / `refine` keep natural signatures.
  `brand<T extends PropertyKey>` folds its conditional return to `this`
  through the same substitution.
- [x] lib.d.ts prelude: `scripts/gen_lib_globals.sh` missed
  `declare type` aliases — PropertyKey, PromiseConstructorLike, and the
  *Decorator aliases are now in the generated registry, and
  `is_well_known_type_name` delegates to it, so ambient lib types no
  longer surface as unresolved-reference notes.
- [x] `extends_decision`: a plain-return function never extends a
  predicate-return signature (tsc: source "must be a type predicate").
  Folds `Ch extends (arg: any) => arg is infer R ? ... : this` to its
  false branch — `refine` returns `Schema[Output, Input, Internals]`
  instead of `JSValue`.
- Note: per-package JSValue counts in the env-gated realworld METRICS
  corpus will drift down on regeneration (budgets are upper bounds).

### 12. Indexed access on constrained type params (done 2026-07-15)

zod: `def: Internals["def"]` / `type: Internals["def"]["type"]` with
`Internals extends core.$ZodTypeInternals<Output, Input>`.
Fallback entries 241 -> 225.

- [x] `decl_eval_bound_indexed_access`: a `P["key"]` access whose base is
  one of the owning interface's CONSTRAINED type parameters resolves by
  looking the key up in the bound's field surface — through the qualified
  namespace import (`core.`), the barrel `export * from "./schemas.js"`
  (new `decl_resolve_interface_origin_deep` walks
  `record.reexports`), and the bound's own `extends` chain. Chained
  accesses evaluate inside-out, tracking the module each intermediate
  name is relative to; resolved names map back to canonical export names
  where the surface has one. Generic targets substitute supplied type
  arguments; a field that still references the target's own params
  without matching arguments is rejected (capture risk) and keeps the
  old widening.
- zod: `def : UnderscoreZodTypeDef` (typed opaque handle instead of
  `JSValue`), `type_ : SchemaType` / `ZodTypeType` (enum of the schema
  kind literal union).

### 13. zod runs end-to-end from MoonBit (done 2026-07-16)

Runtime-verified (node, `moon test --target js` against the generated
package): construct -> chain -> `safeParse` -> read the result. The four
smoke cases: string schema accept/reject, `.email()` format
validation, `object()` schema over an extern-built shape, and `parse`
returning the output handle.

- [x] `decl_exclusive_union_alias_interface_spec`: an applied generic
  alias behind a namespace import / barrel whose body folds through the
  mutually-exclusive object-union idiom (`{success: true, data: T,
  error?: never} | {success: false, data?: never, error: E}`)
  synthesizes a named interface — `safeParse` now returns
  `pub(all) struct ZodSafeParseResult { success : Bool, data :
  Core_output, error : ZodError[Core_output] }`. Shared by the lowering
  and the utility-interface collection walk so the struct is both
  referenced and emitted. Blanket cross-module alias inlining was
  measured to REGRESS (225 -> 418 fallbacks) and is deliberately not
  done; the inline fires only when the fold succeeds.
- [x] Exclusive fields keep their RAW passthrough type (no Option
  wrapper): generic-owner method wrappers return the raw JS object
  without conversion glue, and MoonBit's tagged Option representation
  crashes on the raw `undefined` the absent branch carries.
- [x] realworld zod smoke upgraded from construct-only to
  safeParse success/failure + email format round-trips.
- Known ergonomic gaps (deliberate, documented): concrete schemas
  (ZodString...) need `unsafeCast` to `Schema[...]` to reach
  `parse` / `safeParse` (generic base expansion is future work);
  `object()`'s shape is built with a small extern (`Record<string, any>`
  aliases stay opaque — the StringRecordOf* synthetics are equally
  unconstructible today).

### 14. zod full-feature pillars 2-3: error issues + object shapes (done 2026-07-16)

Runtime-verified continuations of #13 (pillar 1, generic-base
flattening, landed separately):

- [x] Pillar 2 — union aliases whose members cannot be
  runtime-discriminated join to their nearest COMMON BASE interface
  (`decl_join_union_alias_to_common_base`): zod's
  `$ZodIssue = $ZodIssueInvalidType | ... (11 members)` — all
  `$`-prefixed, so tagged lowering rejects every constructor name — all
  extend `$ZodIssueBase`, and the reference now lands on
  `pub(all) struct UnderscoreZodIssueBase { code : String?, input :
  JSValue?, path : Array[PropertyKey], message : String }` instead of an
  opaque handle. Nested union-alias members
  (`$ZodIssueInvalidUnion = NoMatch | MultipleMatch`) recurse; tagged- /
  enum-lowerable unions never reach the join. Runtime:
  `issues[0].message` / `.code == "invalid_type"` read directly.
- [x] Pillar 3 — `loose_shape_from_pairs(keys, values) ->
  Core__ZodLooseShape` (zod module hook, same pattern as react-router's
  `params_from_pairs`): `object()` shapes are built from MoonBit without
  hand-written externs. Runtime: object schema accepts a matching user
  object and rejects a non-object.
- [x] GENERIC owners reach the parse surface via the `as_schema` identity
  upcast (zod module hook): `as_schema(object(Some(shape), None))
  .safeParse(...)` — runtime-verified. MoonBit's nominal structs cannot
  express the extends relation, so the upcast makes it callable; a
  full per-generic-owner facade (monomorphized method wrappers like the
  mbt2ts generic-method glue) remains the eventual principled shape.

### 15. hono runs end-to-end: async handlers + middleware (done 2026-07-16)

Runtime-verified (node, `app.fetch(new Request(...))` round-trips through
MoonBit handlers): sync route via the existing `Context::text` wrapper
(`c.text("...", None, None)` — the generic-owner method glue was ALREADY
emitted for Context's callable-interface properties; the earlier "mbti
declares it but it doesn't exist" reading was wrong, the decl is the
method form), an async route returning `Promise[Response]`, a middleware
that `c.set`s a variable before `next()` with the handler reading it via
`c.get`, and 404 fallback.

- [x] hono module hooks (same pattern as zod's `as_schema`):
  `Hono::get_async / post_async / put_async / delete_async(path,
  (Context) -> Promise[Response])` — the HandlerInterface overload the
  generator picks is sync-only, but hono awaits whatever the handler
  returns and MoonBit closures ARE JS functions on the js backend, so the
  hooks register the closure raw with a typed surface.
- [x] `Hono::use_middleware(path?, (Context, () -> Promise[Unit]) ->
  Promise[Unit])`: pre-processing middleware calls `next()` and returns
  its promise. Post-processing (sequencing AFTER next resolves) needs
  Promise combinators on the MoonBit side and stays raw-JS territory.
- [x] realworld hono smoke upgraded from register-only to the full
  fetch round-trip (sync + async + middleware + 404).
- Remaining hono gaps (documented, not blocking): `app.fetch` returns
  `JSValue` (Response | Promise union), route methods return `HonoBase`
  (chain loses generics), path-param TYPE inference (`/users/:id` ->
  `{id: string}`) is TS type-level computation — same fundamental limit
  as zod's `z.infer`.

### 16. valibot + drizzle run end-to-end; boundary conversion fixes (done 2026-07-16)

Runtime-verified with node against regenerated packages. valibot:
`parse` / `safeParse` accept/reject and `pipe(string(), [minLength(3)])`
length validation. drizzle-orm: the `sql` tagged template builds an SQL
object from MoonBit (template-strings array via a tiny extern) and
`and_()` combines wrappers.

Four GENERAL boundary fixes fell out (all bugs any handle-round-tripping
package would hit):

- [x] Enum `to_js` converters are idempotent: a raw library value cast
  into a struct type carries the JS literal already (valibot's
  `string()` result flowing back into `parse(schema, ...)` crashed on
  "unexpected BaseSchemaKind tag: schema").
- [x] Struct `to_js` converters pass CLASS instances through untouched
  (MoonBit structs compile to plain objects, so an instance is always a
  raw library handle — spreading severed drizzle `SQL`'s prototype) and
  spread plain objects instead of rebuilding from declared fields
  (rebuilding stripped valibot's `~run` internals). Optional fields
  delete their key when absent instead of leaving a tagged None.
- [x] REST parameters spread at the call site in all three glue paths
  (import / func / callable) — `pipe(schema, ...items)` received the
  MoonBit array as its first variadic item ("item.~run is not a
  function"). Imports use `TsImport.param_is_rest`; funcs use
  `TsParam.is_rest`. Rest-param imports also FORCE the bridge glue —
  a direct `= "sql"` binding can never spread.
- [x] The decl emitter's reserved-word list synced to the FFI's 74-name
  list (`and` / `or` / `not` / ...): drizzle's `and` was emitted as
  callable `and_` but the mbti/decl surface advertised the uncallable
  bare name.
- realworld valibot smoke upgraded from construct-only to
  safeParse + pipe round-trips.
- Known cross-cutting gap (same family as zod's raw-typed result
  fields): matching a `T?` EXTERN RETURN with MoonBit `match` can crash
  on the raw `value | undefined` repr when MoonBit expects the tagged
  box — optional extern returns need repr-aware boxing glue. Reads via
  a small extern accessor work today. **Fixed in §17.**

### 17. Optional extern returns construct `Option` on the MoonBit side (done 2026-07-17)

Follow-up to the §16 known gap. Empirical repr table for `Option[T]` on
the JS backend: `String` / `Int` / struct instances / enum instances are
unboxed (`Some` = raw value, `None` = `undefined`); `Bool` uses the `-1`
sentinel; everything else — `JSValue`, `Double`, arrays, opaque
`#external` handles, generics, function/tuple types — uses a `{$tag, _0}`
box. A raw `value | undefined` extern return against a boxed `Option` is
not just crash-prone: a real value silently matches as `None`.

- [x] `__ts_mbt_wrap_option_return[T](raw : JSValue) -> T?` helper pair
  (absence check treats `undefined` and `null` as `None`; `%identity`
  cast for `Some`) injected once per generated package, from either the
  FFI emission (`ffi_option_return_wrap_helper_decls`) or the top-level
  wrapper pass (`bridge_option_return_wrap_helper_decls`), `contains`
  checks dedup the two.
- [x] Top-level `pub extern` fns with boxed-optional returns are demoted
  to `<name>_raw` externs plus a public wrapper by
  `add_bridge_public_wrappers` (same mechanism as enum-converter
  wrappers). Covers drizzle `and_` / `or_`, zod `getErrorMap`.
- [x] Class-method / getter `preserve` wrapper bodies use the wrap helper
  instead of a bare `unsafeCast` when the return is boxed-optional
  (drizzle `SQL::if_`, `One::get_one_config`, hono `Context` getters).
- [x] Non-preserve method / getter / index-accessor / function-field
  externs with boxed-optional returns emit a private raw extern
  (`_*_opt_ret_js`, `self` renamed `this_`) plus a public wrapper via
  `ffi_option_return_extern_pair` (valibot `ObjectEntries::op_get`).
- [x] The trailing `?` of a function-typed return
  (`() -> ((Props) -> JSValue)?`) binds to the function's result — a
  depth-0 `->` scan (`ffi_rendered_return_type_optional_inner`) keeps
  those on the raw passthrough.
- Verified: drizzle `match and_([...])` sees `Some` for real values and
  `None` for `undefined` (previously silent-`None` / crash); zod,
  valibot, hono scaffold smokes stay green.
- Still open (pre-existing, unrelated to Option): non-optional generated
  ENUM returns cross as raw strings (`nextFlag -> NodeFlag`), relying on
  idempotent to_js converters for round-trips; matching them in MoonBit
  needs a return-side `_from_js` conversion. **Resolved in §18** — the
  note was partly stale: top-level enum returns were already converted
  by the wrapper pass; the real broken vectors were index-signature
  accessors and empty structs.

### 18. Enum-typed accessors + index-signature-only interfaces (done 2026-07-17)

Investigating the §17 "raw enum returns" note empirically:

- Top-level fn enum returns were ALREADY converted
  (`nextFlag -> NodeFlag` demotes to a `String` raw extern + a wrapper
  calling `__ts_mbt_node_flag_from_js`) — the note was wrong about them.
- Class/interface METHOD returns never render enum types (they degrade
  to `String` at the ffi surface), so they exchange raw strings
  correctly at runtime; zero real-package occurrences. The decl-layer
  `.mbti` still advertises the enum names there — a surface divergence,
  not a runtime bug.
- The genuinely broken vectors, both fixed:
  - [x] `op_get` on `[k: string]: "a" | "b"` returned the raw string
    typed as the enum (match misbehaved) and `op_set` wrote MoonBit tag
    ints into the JS object. Both now route through
    `ffi_converted_return_extern_pair` / a `_to_js` wrapper pair
    (`ffi_rendered_generated_enum_info` decides; composes with the §17
    Option wrap for the `Enum?` getter return).
  - [x] Index-signature-only interfaces lowered to ZERO-FIELD structs,
    which MoonBit's JS backend value-erases — the instance compiled to
    `undefined` and every accessor crashed. Zero-field interface
    lowering now emits `#external pub type X` (matching what the decl
    layer already advertised in `.mbti`).
- Verified at runtime via the extended `realworld-literal-options`
  fixture: a `FlagMachine` class (method / getter / optional-method
  returns) plus a `FlagTable` index-signature interface with
  `op_get` -> `Some(R)` / missing -> `None` / `op_set(A)` round-trip.
- Return-side enum conversion machinery
  (`ffi_wrapper_return_body_expr`) also covers the preserve-wrapper
  bodies and any future path that renders enum returns.

### 19. Realworld budget recalibration + version-skew-tolerant node builtins (done 2026-07-17)

The env-gated `verify_realworld_typescript.sh` had drifted red after the
generic-base-flattening batches (zod fallbacks 225 -> ~1869 by the old
counting). Rebuilt a complete corpus root (repo-pinned zod 4.4.3 /
valibot 1.4.2 / hono 4.12.16 etc. plus fresh installs for the rest;
exact versions now recorded in `corpus/realworld-typescript.tsv`) and
recalibrated all three budget tables from measured values — the gate now
runs end to end (30 packages generated, checked, runtime-smoked) with
budgets enforced.

Generator fix found by the run:

- [x] `@types/node` routinely declares APIs newer than the running Node
  (`mkdtempDisposableSync` on node 22), and both
  `export { x } from "node:fs"` re-exports and
  `import { x } from "node:fs"` glue imports hard-fail at load time for
  a missing name. `node:*` bridges now route named access through the
  shared `import * as __ts_mbt_module` namespace
  (`ffi_bridge_tolerant_reexport_line`,
  `ffi_module_spec_prefers_namespace_named_imports`), so a missing name
  stays `undefined` until actually called.

Script smoke updates for current surfaces: glob escape/unescape/hasMagic
take `Options?` (wrap in `Some`), node:sqlite options gained
`limits`, and `StatementSync::get` now returns a real `Option` (the
section-17 wrap) — the smoke matches on it instead of reading the raw
value through an extern.

### 20. decl/ffi method surfaces aligned; methods carry real enum types (done 2026-07-17)

`bridge.mbti` advertised `declare pub fn flag_machine_advance(self) -> NodeFlag`
while `bridge.mbt` implemented `FlagMachine::advance(self) -> String` —
both the name and the type diverged. Fixed from both sides:

- [x] FFI class methods / getters / setters render param and return
  types with the field-style resolver (`ffi_struct_field_type_name`),
  so literal-union aliases surface as their generated enums instead of
  degrading to `String`. Conversions ride the section-18 machinery:
  enum returns via `ffi_converted_return_extern_pair` /
  `ffi_wrapper_return_body_expr`, enum params via new
  `ffi_enum_arg_expr` / `ffi_enum_param_raw_type` (`force~` pairs when
  only params need conversion; preserve-path wrappers convert before
  the `unsafeCast`). Setters got the same treatment.
- [x] Decl layer emits instance members as `Type::method` /
  `Type::get_x` / `Type::set_x` (snake-cased, reserved-suffixed) to
  match the FFI's naming; statics stay top-level `<class>_<method>`.
- Verified: `.mbti` and `.mbt` now agree line-for-line on the
  `FlagMachine` fixture (`FlagMachine::advance(self) -> NodeFlag` in
  both), and the runtime fixture matches enum constructors directly on
  method returns (`match advance(m) { R => ... }`,
  `peek() -> NodeFlag?` composes enum from_js with the Option wrap).
- Full gates green including the env-gated realworld corpus (30
  packages) and the drizzle / valibot / hono / zod scaffold smokes.

### Non-Goals (still)

- [ ] Do not turn this list into a checklist for "all of TypeScript". Each item
  must justify itself by removing real-world JSValue surface from the locked
  corpus.
- [ ] Do not pursue `any` / `unknown` AST distinction unless a downstream
  consumer needs it; the JSValue count is unaffected.

## Seamlessness Round 1 (2026-07-19)

A fresh-user walkthrough (npm install -> ts2mbt -> moon build -> node,
done twice: zod standalone and a 4-dep nanoid/ms/date-fns/axios app)
graded end-to-end usability at ~70% and surfaced four gaps, fixed in
priority order and each re-verified end-to-end in the walkthrough apps:

1. Promise consumption API: `Promise[T]` was opaque — async results
   could only be consumed from hand-written JS externs. Every generated
   package whose surface mentions `Promise[` now ships
   `Promise::then(on_ok)` (rejections stay loud), `Promise::then_catch`
   and `Promise::map`, backed by three `__ts_mbt_promise_*` bridge.js
   bindings. `axios.all(...).map(...).then_catch(...)` chains in pure
   MoonBit. Emission forces the self-contained JSValue/Promise decls
   (`state.needs_js_any/needs_promise`) since a surface can mention
   Promise only in doc comments.
2. Returned-function option unwrap (bug found by the walkthrough):
   `customAlphabet(...)` returns `(size?) => id`; MoonBit `None` reached
   the raw JS closure as `null`, JS default parameters never fired, and
   the id came back empty. `ffi_type_js_return_expr` now wraps
   Func-typed returns so each call routes args through the same converters
   direct parameters get (`ffi_returned_func_needs_arg_wrap`).
3. `ts2mbt generate` / `vendor` wiring: the `@tsmbt-bridge/*` `file:`
   dependencies are now written into the consumer's `package.json` in
   place (line-oriented insertion preserves formatting; copy-paste
   fallback when the shape defeats it) instead of a hint that silently
   vanished without `moon.mod.json`; packages that ship no declarations
   (`ms` without `@types/ms`) get a WARNING naming the `@types/`
   package instead of a silent function-less bridge; the moon.pkg
   import hint derives from `--out` instead of hardcoding
   `internal/generated`; AGENTS.md text matches the real behavior.
4. Typed JSValue constructors: `JSValue::from_string/from_double/
   from_int/from_bool/from_array` (identity externs) and
   `JSValue::object_from_pairs` (heterogeneous object literals) replace
   bare `unsafeCast` at the input boundary, emitted wherever the
   package declares JSValue.

Gate coverage: the axios build smoke now chains
`all().map().then_catch()` and builds a heterogeneous object via
`object_from_pairs`; the nanoid build smoke checks the returned
function's default-size and explicit-size paths. Budgets recalibrated
(the Promise layer + constructors add lines/JSValue refs per package).

MoonBit-native async integration (follow-up, same day): the JS backend
compiles `async fn` to CPS (an async fn value crosses to JS as a
2-continuation function — probed empirically; a GENERIC
`%async.suspend` intrinsic ICEs moonc v0.10.4, so the intrinsic stays
monomorphic on JSValue and only the public wrapper is generic). Every
package with a Promise surface now also ships:

- `Promise::wait(self : Promise[T]) -> T` — suspends the enclosing
  `async fn` until the promise settles; `await` in all but name.
- `pub suberror JsRejection { JsRejection(JSValue) }` — a rejected
  promise raises it, so `.wait() catch { JsRejection(e) => ... }`
  handles JS failures as ordinary MoonBit errors.
- `run_async(f : async () -> Unit)` — kicks an async fn from a sync
  context (main / tests); unhandled async errors exit non-zero.

Verified end-to-end on real axios: `all(vals).wait()` resolves inside
an async fn, and a connection-refused `get` surfaces as a caught
`JsRejection`. The axios build smoke covers both paths via
`run_async(smoke_async)`. The signature surface stays `-> Promise[T]`
(non-breaking; fire-and-forget and combinator use keep the raw
promise) — `.wait()` is the conversion point into async MoonBit.

moonbitlang/async integration mode (follow-up): when the consumer
module (nearest manifest walking up from the OUTPUT dir; `_build/`
outputs excluded, same rationale as the package.json wiring guard)
depends on `moonbitlang/async`, the emitter swaps the self-contained
`Promise::wait` for a delegation to `moonbitlang/async/js_async` —
which 0.18+ ships exactly for this: an `#external Promise[X]` with a
coroutine-scheduled `wait(abort_controller?)`. The generated package
gains `Promise::std()` (identity cast to `@js_async.Promise`) and the
`moon.pkg` import; `run_async` / `then` / `then_catch` / `map` stay.
Consequences, all probe-verified E2E on real axios: `async fn main`
works directly (the compiler requires importing moonbitlang/async for
async main — this IS the seamless entry, no `run_async` needed),
`@async.with_timeout` composes over bridge promises, and cancellation
plumbs through the official `AbortController`. Adding the dep to
moon.mod + re-running `ts2mbt generate` is the whole upgrade. Both
section texts live side by side in moonbit_js_ffi.mbt so the modes
cannot drift. Probes also confirmed the raw-CPS self-contained `wait`
keeps working under the @async event loop, and that a typealias-based
deep integration (`pub typealias @js_async.Promise as Promise`)
compiles and runs — deferred because methods cannot be defined on a
foreign aliased type, which would fracture the then/map surface.

Cross-API validation (same day): a four-package showcase app
(moonbitlang/async consumer) runs `async fn main` over node:fs
promises (write -> read roundtrip), jose (generateSecret -> SignJWT
builder chain -> sign -> 3-segment JWT), hono (in-process
`app.request` roundtrip, status 200 + body), and axios.all — exit 0,
no run_async, no hand-written awaits. The walkthrough surfaced and
fixed two real generator/runtime gaps:

- `<fn>.__promisify__` declarations (@types/node's alias for "the
  promisified form of fn") lowered to a literal runtime member access
  that does not exist — a guaranteed TypeError on all 45 node:fs
  `*Promisify` surfaces. `ffi_js_member_access_or_promisify` now
  lowers them to `util.promisify(fn)` (honoring promisify.custom),
  with the `node:util` import injected only when used. The node:fs
  build smoke covers write/readFilePromisify + `.wait()` end-to-end
  via `run_async`.
- `@js_async.Promise::wait` calls `.then` on the raw value, but
  TS-declared Promise returns are sometimes plain values at runtime
  (hono's sync-handler `request` returns a bare Response). The
  integration-mode `wait` now normalizes through `Promise.resolve`
  first, matching JS `await` leniency (the self-contained wait was
  already lenient via its then_catch glue).

Remaining friction observed in the showcase (recorded, not blocking):
hono's `fetch` / `request` returns are JSValue-typed (one unsafeCast
to `Promise[...]` before waiting), union params take nested
constructors (`PathOrFileDescriptor::PathLikeValue(PathLike::
StringValue(...))` — flat convenience constructors like the existing
`path_like_from_string` hooks cover node:fs but not every package),
and web-platform types (Response.status / .text) still need one-line
externs until a lib.dom prelude exists.

Run-verification tests (2026-07-20): the arc is now pinned by tests
that RUN the converted code, not just inspect it. A wbtest keeps the
two Promise-layer section texts coherent (self-contained =
`%async.suspend` + JsRejection-raising rejections; integration =
`Promise::std` + AbortController + `Promise.resolve` leniency, no
suspend intrinsic; both share wait / run_async / JsRejection). The
realworld gate grew `verify_async_integration_app`: a fresh consumer
app depending on moonbitlang/async vendors axios + hono, asserts the
generated bridges actually switched to integration mode, then builds
warning-clean (under warning_guard) and executes `async fn main`
covering awaited `axios.all`, `@async.with_timeout` composition,
AbortController plumbing, and the bare-Response leniency on hono's
sync `request`. Fallout: integration-mode `JsRejection` is `pub(all)`
(nothing constructs it in that mode — rejections raise `@js_async`'s
error), and the node_fs smoke unlinks its sync scratch file instead
of leaving it at the repo root.

Async-callback lowering (2026-07-20): the REVERSE direction now works —
TS APIs that RECEIVE `(...) => Promise<T>` callbacks (React 19
`useActionState`-style actions, promise-returning handlers) accept a
MoonBit `async fn` directly. Top-level fn params rendered as
`(A, B) -> Promise[T]` lower to `async (A, B) -> T raise` on the
natural-name public wrapper (and in `bridge.mbti`), glued back through
a new `Promise::from_async` emitted in both promise layers. Design
facts, all probe-verified before landing:

- MoonBit JS CPS ABI: an async fn that completes WITHOUT suspending
  calls neither continuation — it returns `Result[Option[T], Error]`
  directly. A naive `new Promise((res, rej) => f(args, res, rej))`
  wrapper silently drops synchronous raises. The self-contained
  `Promise::from_async` therefore performs resolve/reject INSIDE a
  noraise Unit wrapper async fn, so the trampoline can ignore the
  sync-completion return value safely.
- Integration mode must spawn: a callback CPS-started raw from JS has
  no coroutine context and `@js_async.Promise::wait` panics.
  `@js_async.Promise::from_async` (which `@coroutine.spawn`s — its doc
  marks it "for exporting MoonBit code to JavaScript") is the delegate;
  the integration `run_async` now also spawns through it (the previous
  raw-CPS trampoline would panic on the first integration-mode wait).
- `run_async` accepts `async () -> Unit raise` in both modes and
  reports errors through an explicit catch (console.error + exit 1) —
  synchronous raises included.
- Not lowered (recorded friction): optional callbacks
  (`((...) -> Promise[T])?`), interface/struct-field callbacks, class
  method callback params, and union-typed handler slots
  (`V | Promise<V>`, axios interceptors).

Tests: bridge wbtest pins the lowering (wrapper + glue + `_raw`
demotion + mbti rewrite + non-promise/optional callbacks staying raw)
and the section coherence (`Promise::from_async` identical signature in
both layers, integration run_async spawning via @js_async). The
realworld gate grew `verify_async_callback_app` twice (self-contained +
integration): a `useStateAction`-shaped fixture package is vendored,
surface markers asserted, then the app RUNS a MoonBit async fn as the
action — awaited TS promise inside the callback, two dispatches folding
state, and a synchronous raise surfacing as a caught rejection.

Round 2 (same day) — remaining callback positions: the lowering moved
into a shared `@parser.moonbit_async_callback_lowering` helper (one
detector for the decl `.mbti` and ffi `bridge.mbt` renderings, so the
divergence gate keeps them identical) and now also covers:

- optional callbacks `((...) -> Promise[T])?` -> `(async (...) -> T
  raise)?` with `Option::map` glue (Some/None structure preserved);
- interface methods / function-field method wrappers, both receiver
  shapes: generic receivers via the `(self.field)(glue)` wrapper,
  non-generic receivers via a forced extern/wrapper pair whose extern
  keeps the raw promise-returning callback types;
- class methods (instance + static, preserve and extern-pair paths),
  reusing the enum-param pair mechanics.

Struct FIELD types deliberately stay raw: fields are identity views
over JS objects (a stored JS function is not CPS-callable), so the
conversion point is the method wrapper / `Promise::from_async` at
construction time. Budget note: one playwright promise-callback
signature moved from the tuple/array bucket into callback/function
(885->886 / 170->169, total unchanged) — recalibrated. The gate
fixture package grew `onCommit` (generic interface method), `Notifier`
(non-generic interface method), `TaskQueue` (class methods), and
`runWithFallback` (optional callback, Some + None) — all RUN in both
promise layers.

Round 3 (same day) — the last two recorded frictions:

- Union handler returns `V | Promise<V>` (axios-interceptor shape,
  React 19 `useActionState`): a new
  `@checker.classify_promise_like_union` /
  `normalize_promise_like_union_return` pair rewrites callback RETURN
  unions of exactly {T, Promise<T>/PromiseLike<T>} to `Promise[T]` in
  every Func-type renderer of both layers (ffi inline + alias, decl
  inline + method parts). Sound both ways because `Promise::wait` is
  resolve-lenient in both modes, and it lets the async-callback
  lowering fire on sync-or-async slots. React's `useActionState`
  scaffold surface is now literally `action : async (State) -> State
  raise` (three hook-tuple test expectations updated from the opaque
  `UseActionStateActionCallback` form).
- Short-owner opaque callback synthesis: `decl_rewrite_inline_callback_
  param_type` now SKIPS the `<Owner><Param>Callback` substitution when
  the callback returns promise-like, so `runAction`-style exports keep
  the structural form and lower like everything else.

Fallout fixed along the way: the round-2 property-get extern for
sanitized members deduped by snake_case and collided on playwright's
`$eval` / `$$eval` — the getter name now embeds the field name
verbatim (unique per struct). Corpus effect of the normalization is a
net naturalization win — zod JSValue fallback 1901 -> 1631 lines and
JSValue-typed functions 607 -> 525, with smaller wins in valibot /
axios / marked / commander / react-router — 13 budget rows
recalibrated from a nobudget collection run. Gate fixture grew
`Interceptor` (union-return `use` handler — also regression-covers the
sanitized-member getter) and `runAction`; both RUN in both promise
layers.

Round 4 (same day) — checker-driven JSValue concretization: the
member-level conditional case is CLOSED. `Applied(GenericIface, args)`
references whose members hide behind conditionals over the interface's
own type params now specialize into synthesized monomorphic interfaces
(`decl_conditional_member_interface_spec`, mirroring the
exclusive-union alias synthesis: shared by the lowering and the
collection walk, fires only when EVERY conditional member decides).
The decision is a decl-layer structural `extends` (name equality ->
true; a required target field missing from the source's
extends-chain-merged fields -> false; anything else undecided) — the
shared checker `extends_decision` is deliberately untouched since it
feeds the TS7 oracle. A resolved branch then rides the whole earlier
pipeline: alias inlining -> `| null` optional collapse -> union-return
normalization -> async-callback lowering. Net effect on real axios:

  interceptors.use : JSValue   (before)
  AxiosInterceptorManagerInternalAxiosRequestConfig::use_(
    self, (async (InternalAxiosRequestConfig[JSValue]) ->
    InternalAxiosRequestConfig[JSValue] raise)?, ...)   (after)

and the realworld axios smoke now registers a MoonBit async fn as a
REQUEST INTERCEPTOR on a real axios instance (axios awaits the
from_async promise; a marker count proves exactly one run; the
connection-refused rejection still catches). A recursion guard
(in-progress set + first-registration-only field walks) keeps
self-referential instantiations from looping — date-fns crashed the
first version. Fixture: `conditional-member-entry.d.ts` pins both
branch outcomes (Payload lacks Ack's required field -> async handler
slot; Ack extends itself -> sync callback).

Surveyed but NOT concretizable via the checker (recorded): zod's
remaining JSValue params are TS `unknown` (honest widening); playwright
residuals are anonymous OBJECT-LITERAL option params (needs synthesized
option structs, an emitter feature); overloaded members still widen
(`interceptors` property itself is an anonymous-object type — one typed
extern bridges to the specialized manager until then).

Round 5 (same day) — extends upcast helpers, closing the dominant
naturalness friction from the 3-package evaluation (an idiomatic
zod+axios+node:fs app needed 7 escape hatches, of which inheritance
casts were the largest class). Interfaces whose `extends` bases do NOT
flatten (generic roots over generic bases — ZodObject over its zod
core base — and class bases — `interface AxiosInstance extends Axios`)
now emit sound `%identity` upcast helpers named after the type-guard
convention: `instance.asAxios().get(...)` replaces
`(unsafeCast(instance) : Axios).get(...)`. Pieces:

- `decl_unflattened_interface_bases` records skipped bases on the
  cloned interfaces (both cloners), mirroring the flatten decision in
  `append_interface_origin_fields`;
- both emitters (ffi struct decl + decl interface decl) render the
  helper with the base reference clamped to the EMITTED arity (source
  `_ZodType<A,B,C>` vs emitted `UnderscoreZodType[Internals]`);
- a text-level `prune_mismatched_upcast_helpers` pass drops helpers
  whose base reference still cannot match the surviving declaration —
  zod's `$ZodType`/`_ZodType` SANITIZATION COLLISION (both become
  `UnderscoreZodType` with different arities) makes some mismatches
  undetectable earlier; the prune keeps mbt and mbti in lockstep.

Budget note: helpers whose base type args widen to JSValue count into
the fallback metrics (react +14 "JSValue functions" are all usable
`asComponent`-style helpers; valibot +68 surface lines likewise) — 10
rows recalibrated. Naturalness evaluation delta: the 3-package app's
escape hatches drop 7 -> 6 (asAxios), with ZodObject->Schema still
needing a cast because zod's base chain hides behind the sanitization
collision. Remaining hatches ranked: anonymous object-literal
properties/params, overloaded members, JSValue value slots, and the
zod name collision (needs collision-aware type identifiers).

Round 6 (same day) — anonymous object-literal synthesis, the top-ranked
remaining hatch. `Object(fields)` types in member positions now
synthesize named structs (`<Owner><Member>` for properties,
`<Owner><Method><Param>` / `<Owner><Member>Options` for params,
`...Result` for returns), registered through a per-emission registry
(populated during cloning, drained after interface AND class cloning in
both layers — the decl emitter runs first in a package bundle so the
ffi drain sees a superset, and the expose pass evens the surfaces).
Rewrite sites: interface fields (`append_lowered_interface_field`),
class properties (`clone_class_property_in_scope`), class method
params (`clone_class_method_in_scope`), and Func-typed member
params/returns. Guards: literal keys only, 1..24 fields, same-name
different-shape collisions stay widened.

Everything composes: axios's `interceptors` property becomes
`AxiosInterceptors { request : AxiosInterceptorManagerInternal
AxiosRequestConfig; ... }` — the round-4 conditional-member
specialization landing inside a round-6 synthesized struct — so the
fully generated chain
`instance.asAxios().get_axios_interceptors().request.use_(Some(async
fn(config) { ... }))` runs with ZERO hand externs. playwright options
params become real structs with their literal-union fields enum-ized
(`ElementHandle::click(self, ElementHandleClickOptions?)`, 255
synthesized option structs).

Corpus effect (28 budget rows recalibrated): playwright JSValue-typed
functions 411 -> 200 and JSValue surface 1336 -> 827; zod 526 -> 485;
node:crypto 24 -> 16; net -639 JSValue surface lines across changed
rows (small increases in valibot / pino / react-router / lodash are
the synthesized structs' own JSValue-typed fields — new usable
surface, not lost signal). Naturalness evaluation: the 3-package app
drops to 5 escape hatches (interceptors extern eliminated).

Round 7 (same day) — overloaded-member merging + collision-free type
identifiers, the two hatches picked from the round-6 ranking.

Overload merging (`src/bridge/moonbit_decl.mbt`): the canonical TS
overload pattern — same member re-declared with extra TRAILING params
and the same return type — previously kept only the first declaration
(rest silently dropped, callers lost the richer arity). Now
`decl_merge_overload_param_lists` merges into the LONGEST signature
with the extra params optionalized (`decl_optionalize_type` wraps in
`| undefined` unless already optional-like), applied in
`append_class_method_once` (guards: same key / static / return, no
method-level type params) and in `append_lowered_interface_field`
(which was restructured so lowering + inline-object rewrites compute
the final type BEFORE the merge attempt). `Store::get(key)` +
`get(key, fallback)` becomes `get(self, key : String, fallback :
String?)`. Fixture `member-overload-entry.d.ts` + wbtest cover the
interface and class forms; the mitt gate smoke needed `emit(ev,
Some(ev))` since `emit`'s second param is now merged-optional.

Collision-free identifiers: `$` in TS type names now sanitizes to a
distinct `Dollar` token in BOTH identifier paths (`ffi_type_identifier`
/ `moonbit_type_identifier`) instead of the generic `Underscore`
mangle, so zod's `$ZodType` (DollarZodType) no longer collides with
`_ZodType` (UnderscoreZodType). That collision was what forced the
round-5 prune to drop zod's upcast helpers; with distinct names the
helpers survive with precise type args and the fully generated chain
`user_schema.asUnderscoreZodType().asZodType().safeParse(input, None)`
runs end-to-end — the last hand `unsafeCast` in the eval app's zod
path is gone. The zod domain glue return type follows the rename
(`Core_DollarZodLooseShape`).

Gates: full suite 2532 green, all scaffold/fixture/example/realworld
gates green, budget recalibration ZERO drift (the merges and renames
net out). Naturalness evaluation: the 3-package app drops to 4 escape
hatches. Remaining ranked: mutating config headers inside interceptors
(AxiosHeaders methods), Buffer.toString, JSValue value slots (zod
shape values need per-value casts).

Round 8 (same day) — checker-driven JSValue concretization round 2:
`typeof` value queries. Mining the generated corpus surfaced one
dominant inferable cluster: `readonly reference: typeof someFunction`
members (valibot declares ~190, axios exposes `typeof Axios` /
`typeof isCancel` style statics, glob/yaml similar) all collapsed to
bare `JSValue` because `typeof` of a GENERIC or overloaded function
never resolved. Fixes, all in the decl lowering:

- `typeof_func_decl_to_func_type` substitutes each type parameter by
  its declared bound (`Any` when unbounded; bounds may reference
  earlier params, so they resolve left-to-right) before lowering, so
  a generic function's `typeof` still yields a concrete callable
  shape (`typeof ip` -> `() -> IpAction[String, JSValue]`).
- the resolver now collects sibling overloads (`find_func_decls`) and
  merges the round-7 trailing-param pattern into one signature before
  falling back to the least-widening pick.
- `typeof_value_type_is_stable` learned that `null` / `undefined` /
  `never` are CONCRETE types (an `Action<T, undefined>` type argument
  was destabilizing the whole reference), and gained an
  `allow_widened~` mode — used whenever the resolved shape is a
  callable — under which `any` / `unknown` / `object` slots are
  acceptable: they render as `JSValue` params while arity and
  callability stay real.
- `ReturnType<...>` / `Parameters<...>` lower their operand FIRST, so
  `ReturnType<typeof addPairToJSMap>` reduces through the resolved
  function type. This also kills a real leak: yaml's `Pair::toJSON`
  previously rendered `-> ReturnType` backed by a synthesized
  `declare pub type ReturnType` opaque extern.
- ambient classes (`declare class`) parse `static readonly X = "lit"`
  literal initializers into literal TYPES (parser_function.mbt was
  discarding the initializer expression) — string/bool/int literals
  only, mirroring tsc's own inference so the TS7 oracle is safe by
  construction; yaml's `Scalar.BLOCK_FOLDED` getters now return
  single-case enums instead of `JSValue`. A bridge-side
  `decl_infer_literal_property_type` covers runtime-class clones the
  same way via `static_field_inits`.

Fixture `typeof-inference-entry.d.ts` + wbtest pin all three
behaviors. Oracle: TP 2338 / FP 0 / PFLEGAL 0 / TN 1750 — byte-equal
to the recorded baseline. Corpus (5 budget rows recalibrated): axios
JSValue functions 61 -> 37 and surface 190 -> 166; yaml 67 -> 62 /
177 -> 172; valibot unknown/any 1166 -> 926 (-240) with surface
1738 -> 1858 — the resolved `reference` members now emit callable
method decls whose `IpAction[String, JSValue]` rendering the cause
heuristic files under tuple/array, i.e. the same widening now ships
usable callable surface instead of a bare `JSValue` slot.

Remaining inferable clusters recorded for later rounds: `expects:
null` literal members (~104 in valibot) still widen — typing them
needs an opaque null representation decision; value-or-function
unions (`ErrorMessage<T> = string | ((issue) => string)`, ~157
`message` members) need an untagged-union construction story.

Round 9 (same day) — both recorded clusters landed.

Instantiated generic union aliases: NON-generic `string | fn` union
aliases already lowered to tagged-union enums with constructors and JS
converter glue; the gap was the APPLIED generic form
(`ErrorMessage<Issue>`), which inlined to an anonymous union that the
inline synthesizer refuses (function members) and so widened to
JSValue. `decl_instantiated_union_alias_name` now names the
instantiation (`ErrorMessageOfIssue` via the utility suffix namer)
when the substituted+lowered body is a union WITH a function member
that `tagged_union_type_alias_decl` accepts, registering it in a
`decl_synthesized_union_aliases` registry (reset at decl-emit start;
drained by the decl emitter after all cloning and merged into the
FFI's exported tagged unions — decl runs first in a bundle, mirroring
the round-6 object-struct registry). Hooked into both the same-module
`applied_type_alias` inline path and the qualified/cross-module
`decl_inline_qualified_applied_alias`, plus the collection-walk
mirror so interfaces referenced ONLY from the enum's function-typed
case payloads still get their declarations (valibot's ArrayIssue /
VariantIssue / MapIssue / RecordIssue / SetIssue compiled only after
this). The case-payload dependency scan got a shared helper
(`tagged_union_case_named_refs`) that walks Func params/returns —
both the decl opaque-companion list and the FFI external-type marking
previously only saw bare `Named` / `Array(Named)` payloads.

`null` literal members: a member typed exactly `null` (valibot's
`readonly expects: null`, ~98 members) now references a shared opaque
`JSNull` companion instead of widening — referenced-but-undeclared
names already get their opaque decl emitted by both layers, so the
representation costs one `declare pub type JSNull` line; the name is
exempted from the emit-time unresolved-reference sanity note.

Fixture `union-alias-instantiation-entry.d.ts` + wbtest pin both.
valibot corpus effect (2 budget rows): JSValue surface 1858 -> 1437
(-421), unknown/any 926 -> 504; 140 ErrorMessageOf* enums, message
members now `ErrorMessageOfIpIssueOfTinput1?`-style typed enums with
`..._from_string` constructors and typeof-discriminated from_js glue.
zod/yaml rows unchanged (zod's message unions were already
string-subset-lowered; yaml's value-or-function members are anonymous
inline unions — still open, needs an inline construction story).

Round 10 (same day) — ANONYMOUS inline value-or-function unions, the
last recorded value-or-function gap. `ffi_synthesize_inline_union`
refused every union with a function member (a guard from the react
hooks era whose motivating case — `S | (() => S)` with S widened —
can't reach synthesis anyway: the widened arm has no runtime
discriminator). Lifting it needed two safety pieces:

- SHAPE-tagged constructor names: a structural alias name that spells
  every function case as bare `FnValue` would merge yaml's
  `uniqueKeys: boolean | ((a: ParsedNode, b: ParsedNode) => boolean)`
  and `sortMapEntries: boolean | ((a: Pair, b: Pair) => number)` into
  one `Auto_BoolValue_or_FnValue` with whichever payload registered
  first. `moonbit_inline_union_func_case_name` (parser package, shared
  by the decl renderer and the bridge FFI so both compute identical
  names) encodes params and return into the case name:
  `Auto_BoolValue_or_FnPairPairToDoubleValue` vs
  `Auto_BoolValue_or_FnParsedNodeParsedNodeToBoolValue`. All three FFI
  sites that derive the synthetic name now go through one
  `ffi_inline_union_shaped_cases` helper.
- at most ONE function member per union: every function case
  discriminates via `typeof === "function"`, so a second would be
  indistinguishable at the boundary — both sides refuse those.
- Named siblings must be RUNTIME-DISCRIMINABLE: a function-armed union
  only synthesizes when every Named member is a well-known JS global
  constructor (`moonbit_inline_union_runtime_named_ok`: RegExp / URL /
  URLPattern / Date / Buffer / typed arrays / ...) whose `instanceof`
  works in the generated converter. The first attempt (reject local
  type params) missed `useState(initialState: S | (() => S))` — its
  `S` isn't registered as a local param on that path — and the
  generated from_js tested `value instanceof S` against a name that
  doesn't exist in bridge.js. Interfaces / aliases / type params all
  fail the allowlist, so only truly discriminable unions synthesize.

The synthesized-inline emission loop also switched its payload
dependency scan to `tagged_union_case_named_refs` (playwright's
`(url: URL) => boolean` case needed the `URL` external companion that
the old bare-Named scan missed). Fixture `inline-fn-union-entry.d.ts`
+ wbtest pin the two-distinct-signatures case.

Corpus (net, after the runtime-named guard): playwright's
`page.route(...)` family now takes
`Auto_RegExpValue_or_StringValue_or_URLPatternValue_or_FnURLToBoolValue`
instead of JSValue (functions 200 -> 196, surface 827 -> 811); yaml
172 -> 168 with uniqueKeys/sortMapEntries typed; node:fs 34 -> 28;
lodash 1651 -> 1644; pino / zod / axios / node:util small drops;
react unchanged (its candidate unions all carry interface-typed value
arms that the guard correctly refuses).

Round 11 (same day) — event-map literal-overload specialization, the
top pick from the unlock survey. Interface members overloaded on a
literal first param followed by a listener
(`on(event: 'close', listener: (page) => void)` x56 event names on
playwright's Page alone) merge to nothing under the round-7
trailing-param rule, so only the first declaration survived with both
params widened. Each such family (>= 2 distinct literals — a lone
literal-first method is not an event map; and the second param must be
a function, so literal dispatch like react's `createElement('div')`
stays untouched) now synthesizes per-literal companion members:
`on_close((Browser) -> Unit) -> Browser`. Pieces:

- detection runs on the PRE-rewrite lowering in
  `append_lowered_interface_field` (the inline-callback naming pass
  would otherwise hide the `(Literal, Func)` shape behind a named
  opaque callback);
- `decl_event_member_families` records (literal, companion type) per
  owner+member so the FIRST overload's companion appears retroactively
  when the second literal arrives; companions re-push into every clone
  (the decl and FFI layers each clone the interface — the per-clone
  `seen_field_names` keeps it idempotent);
- `decl_event_member_specials` maps each companion to
  (JS member, literal); the FFI emits
  `#| (self, arg0) => self.on("close", arg0)` — and on
  generic-preserved receivers a BOUND-closure getter
  (`(o) => (...args) => o.on("close", ...args)`) so `this` survives;
- listener returns declared `any` / `unknown` normalize to `void` in
  the companion (`(page) => any` is fire-and-forget for the emitter) —
  without this every companion line carried a spurious `JSValue`
  return and playwright's metric tripled.

Runtime-verified: a generated `browser.on_close(fn(_b) { ... })`
registers through the real `.on("close", ...)` and fires (smoke in
scratch; fixture `event-map-entry.d.ts` + wbtest pin the shapes).
playwright gains 76 typed `on_* / once_*` methods; JSValue functions
196 -> 191 with surface 811 -> 842 (+31: companions whose payload
types still widen — new usable surface). Class-METHOD event maps
(ws / chokidar / node:fs watchers) are not yet specialized — the same
registry approach extends to `append_class_method_once` +
`ffi_class_method_decl_to_moonbit`; recorded as the next step.

Round 12 (same day) — nonempty-tuple normalization (#2 of the unlock
survey). `[T, ...T[]]` (valibot / zod `issues` fields) is a nonempty
ARRAY for the bridge surface; as a tuple it widened to
`Array[JSValue]` and lost the element type. `decl_nonempty_tuple_element`
recognizes a trailing rest whose element equals every fixed element
and the Tuple lowering arm rewrites to `Array(element)`; boundary
representation is unchanged (a JS array either way). Elements that
resolve concretely now surface (`issues : Array[BaseIssue[TInput_1]]?`);
the ~70 that remain `Array[JSValue]` carry `InferIssue<TSchema>`
conditional elements — honest widening. Zero budget drift. The
common-base ELEMENT join half of the survey item turned out to be
already covered: `Array(Named(alias))` lowers the alias through
`decl_join_union_alias_to_common_base` on the Named arm.

Round 13 (same day) — record-and-class intersections (#5 of the
survey: the axios eval-app's last interceptor hatch). axios's
`AxiosRequestHeaders = RawAxiosRequestHeaders & AxiosHeaders` widened
to an unresolved opaque name, so `config.headers` inside an
interceptor had NO usable surface even though the `AxiosHeaders`
CLASS (set / get / has / set_content_type / ...) was fully generated.
`decl_intersection_single_class` resolves an intersection to its
single declared-CLASS member when every sibling is record-ish (object
literals, `Partial<...>` / `Record<...>` applications, aliases that
resolve to neither class nor interface — an interface sibling
refuses, dropping its fields would lose surface). The alias now emits
`pub type AxiosRequestHeaders = AxiosHeaders` (transparent) and
`config.headers.set(Some("X-Trace"), Some(v), None)` type-checks —
compile-verified against the generated axios package. Fixture
`intersection-class-entry.d.ts` + wbtest pin the rule. Zero budget
drift.

Survey status: #1 event maps (interfaces) DONE round 11, #2 nonempty
tuples DONE round 12, #5 AxiosHeaders DONE round 13. Remaining: #3
schema value slots (zod `loose_shape_from_pairs` still takes
`Array[JSValue]`; a `$ZodType`-bounded value slot + upcast-at-call is
the sketch), #4 lodash chain generics (big, budgeted), and the
class-METHOD event maps follow-up from round 11 (ws / chokidar /
node:fs watchers).

Round 14 (same day) — #3 schema value slots + #4 method-level
generics, closing the survey.

#3: the zod module hook gains a TYPED shape builder alongside the raw
one — `loose_shape_of(keys, values : Array[Schema[JSValue, JSValue,
JSValue]])` accepts the same upper bound `as_schema` produces, so the
gate smoke's shape entry is now
`loose_shape_of(["name"], [as_schema(string(None))])` with no
per-value unsafeCast.

#4: `map<U>(fn: (item: T) => U): CollectionChain<U>` on a GENERIC
owner widened U to JSValue on every chain-style API. The member's own
binder now survives on the pure-MoonBit wrapper:
`fn[T, U] CollectionChain::map(self, (T) -> U) -> CollectionChain[U]`.
Pieces:
- both interface cloners now CARRY `method_type_params` (they emitted
  `[]`, so the renderers never saw the binder);
- both renderers thread the member's binder (interface methods carry
  it out-of-band in `iface.method_type_params`; inline object members
  as `GenericFunc`) — the decl side pushes it as local type params and
  emits a combined prefix, the FFI side routes through a monomorphic
  getter returning a BOUND closure and a `pub fn[T, U]` wrapper
  (generic externs are forbidden; a plain fn casting the fetched
  closure is not);
- binder names whose occurrences were widened away are FILTERED from
  the prefix (`*_rendered_mentions_param` token scan) — an unused fn
  type parameter is a hard error [4027] (zod's `register` / `brand`
  hit this immediately);
- while smoking this against a real prototype-method implementation,
  the PRE-EXISTING generic-receiver form `(self.first)()` turned out
  to lose `this` (extracts the prototype method, calls it unbound —
  TypeError on any class-based library). ALL generic-receiver members
  now fetch a bound closure (`(o) => (...args) => o.first(...args)`)
  through the getter; the gate's sanitized-member marker moved to the
  bound form.

Runtime-verified: `c.map(fn(x : Double) { x.to_string() })` returns a
usable `CollectionChain[String]` and `compact()/first()` no longer
throw on class-implemented chains. Fixture `chain-generics-entry.d.ts`
+ wbtest; the StatsBase wbtest moved to the bound-getter expectation.
Corpus (8 rows): playwright JSValue functions 191 -> 179, lodash
288 -> 286 with surface 1644 -> 1634, zod 1497 -> 1493, source-map
-1; pino +1 line (a preserved generic slot now renders — new usable
surface). Top-level generic FUNCTIONS (`chain<T>(items)`) still widen
— that path has no receiver to hang a getter on; recorded as open.

Round 15 (same day) — CLASS-method event maps, the round-11
follow-up. Detection had to run on the RAW method (the clone rewrites
the listener to a named opaque callback, hiding the `(Literal, Func)`
shape — the same trap the interface path hit); the companion is built
from the raw method (first param dropped, `any`/`unknown` listener
returns normalized to `void`) and THEN cloned through
`clone_class_method_in_scope`, with the same >= 2-distinct-literals
activation, per-clone re-push, and `decl_event_member_specials`
registration. The FFI class-method emitter consults the registry and
injects the literal at both instance js_call sites
(`(self, listener) => self.on("change", listener)`). ws gains 18
typed `on_*` companions (`WebSocket::on_message` etc.; surface +12 —
companions whose payload types still widen); chokidar's FSWatcher
declares no literal overloads of its own (EventEmitter inheritance)
so it is unaffected. Fixture `event-map-entry.d.ts` extended with the
Watcher class + wbtest.

Profiled with `moon bench --target native` + callgrind over the release
`tscheck` binary (`--parse` / full, `--iters N`; use
`--toggle-collect=<mangled check entry>` to isolate the check phase from
the parse). Five landed batches, all behavior-preserving (full suite
2523 green, oracle byte-identical TP 2338 / FP 0 / TN 1750 / MISS 396,
every gate green):

1. Parser whole-source rescans (`20ff7e7`): `from_source_with_jsx`
   lowered the FULL source 3x per parse (`@noImplicitThis` x2,
   `@filename:`); all whole-source markers now come from one
   `scan_source_directive_flags` pass over `@` positions. The ~10
   conformance-header detectors each sliced+lowered their own 1KB head
   -- multiplied by JSX speculation re-entering `from_source_with_jsx`
   on sub-sources (2k+ nested parses on parserharness.ts); the head is
   now computed once per parse and threaded through. `parse_jsdoc_block`
   rewritten single-pass over StringViews (was 3+ owned strings per
   comment line); the lexer passes the comment span without copying.
2. Checker structural scans (`58527b4`): `iface_extends_reaches` was
   O(ifaces^2 x chain) via per-step rescans of every interface decl
   (~7.5% of a dom.generated.d.ts run) -- now a prebuilt name->extends
   adjacency map + hash-set DFS. `is_lib_global_value`/`_type` (generated
   1k/2.2k-arm string matches, probed once per reference; 9.6% of a
   generic-heavy run) now memoize per name via gen_lib_globals.sh.
3. Bench coverage: `moon bench` gains JSDoc-heavy (300 documented
   decls) and old-style-cast-heavy (200 funcs, JSX speculation) parser
   fixtures so both optimized paths regress visibly.

Measured (release tscheck, per iteration):
- es5.d.ts parse 11.7ms -> 6.1ms (~19 -> ~36 MB/s); full check 15 -> 9.7ms
- dom.generated.d.ts parse 115 -> 60ms; full 170 -> ~100ms
- parserharness.ts parse 44 -> 30ms; full 60 -> 49ms
- generic-heavy check phase 26 -> 19ms
- moon bench parser fixtures -17%..-38%

4. Paren-JSX speculation gated on `allow_jsx` (batch 4): tscheck was
   already extension-driven (`.tsx` only), but THREE paren-path JSX
   attempts (`try_parse_parenthesized_jsx_expr` + the two
   `peek_at(1)==Lt` temp parses in `parse_parenthesized_expr` /
   `parse_primary`) ignored the flag, so every `(<any>x)` cast in a
   `.ts` file ran the full JSX source scan + nested embed sub-parses
   and threw the work away. All three now early-out in `.ts` mode --
   tsc-aligned (`(<T>x)` is a parenthesized type assertion there).
   parserharness.ts parse 30 -> 11ms (44ms pre-round; -75% total),
   full check 49 -> 35ms, byte-identical diagnostics and oracle
   results. `moon bench` cast fixture split into `.tsx`-mode (4.96ms,
   speculation still exercised) and `.ts`-mode (3.51ms) variants.

5. Module-pass allocation hoists (batch 5, check-phase Ir on
   dom.generated.d.ts 552M -> 473M, -14%): `check_structural_duplicates`
   and `walk_module_undeclared_tps` interpolated their diagnostic path
   string (`"interface \{name}"` etc.) once per FIELD/PARAM instead of
   per declaration — hoisted; `walk_module_undeclared_tps` also did a
   linear scan of `method_type_params` per field (quadratic on lib.dom
   interfaces) — now grouped once per interface;
   `check_interface_extends_compat` rebuilt the base interface's
   field/overload-count maps once per (derived, base) EDGE — popular DOM
   bases like `Event` are extended by hundreds of interfaces — now
   cached per base name, and the derived counts hoisted out of the
   bases loop.

Remaining known sinks (next round candidates): `.tsx`-mode JSX
speculation still re-lexes substrings per `<` attempt (only matters
for real `.tsx` sources now); refcount+alloc runtime overhead is
~29% of the remaining check-phase profile and ~25-30% of parse (only
fixable by allocating less); String-keyed Map probes are ~8% of the
check phase spread across all passes (an interned-name or ID-keyed
resolver would be a deep refactor); `Parser::peek/check` +
`TokenKind::equal` are ~30% of body-heavy `.ts` parses (each peek
copies a Token and refcounts its payload; a tag-int fast path would
need parser-wide changes).

## TS Checker Conformance (current state, 2026-09-03 — TypeScript 7)

State: whole-corpus **TP 2518 / MISS 216 / FP 0 / PFLEGAL 0 / TN 1750**
(classified 4484, NOTRUN 14) via
`scripts/checker_conformance_oracle.sh --max-fp 0 --max-legal-parsefail 0`.
Twenty-one batches: BU +9, BV +14, BW +13, BX +10, BY +7, BZ +1, CA +0,
CB +10, CC +6, CD +4, CE +6, CF/CG +19, CH +7, CI +5, CJ +6, CK +3,
CL +11, CM +11, CN +1, CO +4, CP/CQ +28, CR +3, CS +3, for
**+181 TP at FP 0**. MISS <= 250 was met at CO. The goal is now
MISS <= 150, which needs **66 more files** — see batch CS for why that
is not a rule-writing problem any more.

### Batch CS (2026-09-03): three negative results, and an invisible FP

+3 files (TP 2515 -> 2518, MISS 219 -> 216, FP 0, PFLEGAL 0),
checker whitebox 642/642.

**Three mechanisms tested and rejected, which is the useful part.**
Looking for something worth many files rather than one:

1. *Position coverage is not the bottleneck.* A matrix putting a known
   type error in each of 28 syntactic positions (variable declaration,
   call argument, return, property assignment, object-literal field,
   array element, default parameter, later assignment, for-of binding,
   ternary, class field, constructor argument, method return, arrow
   return, index write, spread, template, compound assignment, `as`,
   `satisfies`, `await`, `yield`, destructuring default, object-method
   return, nested object, union context, readonly write, optional call)
   finds **24 already checked**. Only 4 gaps, all small.
2. *A NAME is not a feature cluster.* The 21 `Symbol`-ish miss files
   need 21 unrelated things. Same mistake as the decorator bucket, one
   axis over.
3. *The lib model is largely present.* 8 of 13 common global return
   types infer correctly.

Conclusion: no single mechanism is worth ~66 files, and the measured
rate is ~1.7 rules per file gained.

**The systemic gap that WAS real:** `Symbol()` had no model in
`infer_expr`, so every rule keyed on a symbol operand was silent.
`iterator_class_element_type`'s own comment states it and works around
it locally — another stated abstention naming its own blocker.

**Rules:** TS2358 extended from a syntactic literal LHS to the inferred
type; TS2359 for the right operand; TS2407 for a `for...in` right-hand
side (where `unknown` IS an error, the opposite of the instanceof LHS —
both probed); TS2731 for a symbol in a template substitution (zero
corpus files, kept because `${sym}` throws at runtime); TS18046 for an
unnarrowed `catch (e)`, decided by a token scan where any of five
narrowing spellings withdraws the report for the block.

**The false positive.** `+`, `-` and `~` apply ToNumeric, so the only
type TypeScript refuses is `symbol` (TS2469). `~aString`, `-aString`,
`~aBoolean`, `-aBoolean` and `-anObject` are all legal and were all
reported. Only operator-by-operator probing finds this, because the
BINARY operators DO require a number (`s - 1` is TS2362) and so do
`++` / `--` (TS2356) — the wrong rule looked exactly like its
neighbours. Two tests asserted it by name, the 6th and 7th in this repo
found pinning a bug. And removing it COST a true positive:
`typeArgumentsWithStringLiteralTypes01` was flagged only for
`args[+randBool()]`, idiomatic bool-to-0/1 coercion, while its real
errors are five TS2345s elsewhere. **A conformance file counts as a TP
if we flag it at all, so +1 TP is not evidence that a rule is right.**

### Batch CR (2026-09-03): one fact, recorded at some of its sites

+3 files (TP 2512 -> 2515, MISS 222 -> 219, FP 0, PFLEGAL 0),
checker whitebox 641/641.

- **TS2307 through a re-export.** The check reads `import_module_specs`,
  filled by the IMPORT parsers only, so `export * as ns from './nope'`
  had nothing to report. Routing the eight `expect_from()` sites through
  one `expect_from_spec` fixed half of it — and
  `export { a } from './nope'` still did not report, because this parser
  consumes `from` in TWO ways: a mandatory `expect_from` and an optional
  `match_(From) || match_ident("from")` (since `export { a }` with no
  `from` is legal). Six more sites use the optional spelling. Both
  helpers record through a single `record_module_spec`.
- **An import TYPE's specifier**, a third route, which that arm consumed
  and discarded. Zero corpus files: `importTypeAmbientMissing`'s only
  top-level declaration is a `declare module`, so the whole check is
  suppressed by the ambient-module-bundle gate. Shipped anyway, proven
  in isolation, because a typo in `import("...")` is a real mistake.
- **TS6133 for an unused `#private`**, where a COUNTING argument
  replaces the walk an earlier note deferred on its fail direction. A
  private name is class-scoped, so every read spells `#name`; the number
  of `PrivateIdent` tokens carrying it is therefore an exact upper bound
  on declarations + reads, and not exceeding the recorded declaration
  count means nothing reads it. A missed read is impossible and an extra
  occurrence only silences. File-level on purpose:
  `privateNameUnused` declares `#unused` four times across three classes
  and reads it never, and a `#x in v` brand check is a read.

### Batch CQ (2026-09-03): four rules the compiler had to settle

Verified together with CP: **+28 files** for the pair (TP 2484 -> 2512,
MISS 250 -> 222, FP 0, PFLEGAL 0, TN 1750), checker whitebox 640/640.

- **TS1212** (`yield` / `let` as an identifier reference). The message
  names strict mode and tsc applies it regardless — `yield;`,
  `console.log(yield)`, `var yield = 1`, a parameter named `yield` and a
  bare `let` are all reported at **es5** in a sloppy script. So the rule
  is not gated on strictness or on the target, which is the opposite of
  what the message says and of what batch CF assumed when it reserved
  these names in `parse_binding_ident` for strict mode only. Recorded at
  the two identifier-REFERENCE arms; every property position
  (`{ yield: 1 }`, `o.let`, `interface I { let: string }`,
  `enum E { yield }`, `class C { yield() {} }`) is legal and each is
  parsed elsewhere, which is what keeps the rule off them.
- **TS7008** (a class member with no annotation and no initializer under
  `noImplicitAny`). Recorded in the parser because the annotation is the
  deciding fact and the AST cannot carry it — a missing annotation and an
  explicit `: any` are both `Any`. `q = 1` infers, `r: number` is TS2564
  instead, a `#private` and a `static` member error like a plain one, and
  an ambient class is exempt for free: `declare class` is parsed by
  `parse_declare_class` and never reaches `parse_class_body`.
- **TS2803** (assigning to a private method) and **TS2806** (reading a
  private accessor that has only a setter). Decided over the class body's
  TOKEN range rather than by walking member bodies: a body is an
  arbitrary expression tree, and every access to `#x` must spell `#x`, so
  a token scan is complete by construction where a walker missing one arm
  loses findings silently. A `.` before the `PrivateIdent` is what
  distinguishes an ACCESS from the member's own declaration and from a
  `#x in v` brand check; what follows decides the direction, and a
  compound assignment counts as both — which is why `this.#x += 2` is a
  READ of a setter-only accessor, the corpus shape. Probed: writing a
  set-only accessor is legal, writing a GET-only one is TS2540 (a
  different code, not raised), and writing a plain private field is fine.

### Batch CP (2026-09-03): thirteen rules, one rejection, one perf bug

CP alone was +19 (TP 2484 -> 2503, MISS 250 -> 231, FP 0). Its rules and
findings follow; the pair's combined numbers are above.

**Ranking.** `--miss-list` was added to the oracle so the MISS paths come
out of the same loop that classifies them — a second script deciding what
a MISS is can disagree with the gate — and `scripts/checker_miss_rank.mjs`
probes every one of them with the real compiler and groups by code. It
ranks by `solo` (files where a code is the only lever) rather than by
(file, code) pairs, since the thing that flips is a FILE.

The ranking's first result was a CORRECTION to this document. CLAUDE.md
recorded that TS2322 / TS2345 / TS2339 / TS2304 — the four biggest
buckets — "turn out not to need machinery at all", because their basic
forms are already flagged. Opening the files says the opposite: their
basic forms are already TPs, which is exactly why they are NOT in the
miss list, and what remains under those codes is `for (foo().x of ['a'])`
assigning a string into a property, a well-known-symbol accessor pair,
`Intl.NumberFormat` option types and union normalization. There is no
systemic lever at the top of the table; the work is the tail.

**Ten grammar / lexer / flag rules.** TS1489, TS17006, TS5076, TS1186
(two sites), TS1347, TS17013, TS1036, TS2354, TS18016, TS2390. Each is
described at its site with the probed boundary; the ones worth naming
here are the two that are the applied-in-some-places family (TS1186's two
parsers, TS2390's counter that only ever compared against 2) and TS1036,
which is the INVERSE — `Empty` looks like a missing arm and is a
deliberate abstention, because six legal lowerings produce it.

**Three structural rules.** TS2390, the computed half of TS4113, TS2493.

**TS4113: a recorded rejection, now with a condition.** Batch BY refused
`override` on a computed key as unsound and was right. This ships the
decidable part — a base chain that declares NOTHING cannot declare the
resolved key either — and getting that claim to be TRUE took two fixes:
`resolve_base_chain_members` consulted a merged interface only when no
class of the name existed (which is never, for a merge), and a computed
key in the BASE now sets `has_opaque` so the walk withdraws the claim
rather than reading an unnameable member as an absent one.

**REJECTED (again): wiring `unresolved_type_references` into the
conformance path.** Four causes batch CL named are real and are fixed
(the `__tsmbt_infer` marker read as a type; an `infer` name unresolved in
the branches; a forty-name hand list where the generated
`is_lib_global_type` registry exists; `imported_binding_names` ignored by
`module_declared_name_set` despite its own comment naming the consumer).
None is the blocker. An interface or object-type call / construct
signature's own type parameters are not preserved anywhere `check_type`
can read them, so `interface I { <U>(x: U): U }` reports `U` through arms
the walk has always had — the binder is lost by the PARSER. Adding scope
arms for `GenericFunc` and the mapped types made it worse: those nodes
were previously skipped, and walking them turned silent MISSes into
reports of their own parameters.

**The perf bug.** TS5076 reads the token range its `parse_or` frame
consumed, because parens are stripped. `parse_or` runs once per
expression at that level, nested, so an unconditional scan is O(n^2) in
tokens: a 9 MB file went from seconds to 180+, and the checker whitebox
binary sat at 100% CPU for 36 minutes. Gated on the frame having consumed
a `??`. The oracle's wall time (58 s over 4,484 files) is the check.

### Batch CO (2026-09-03): four one-file rules — MISS 250, the target

### Batch CO (2026-09-03): four one-file rules — MISS 250, the target

+4 files (TP 2480 -> 2484, MISS 254 -> 250, FP 0, PFLEGAL 0, TN 1750).
The goal set for this line of work — TypeScript compatibility at
MISS <= 250 — is met, on the line rather than under it.

All four came out of the long tail the compiler-probed ranking exposed:
67 error codes with exactly one MISS file each, mostly grammar. None
needed type machinery.

**TS4111** — dot access to an index-signature member under
`@noPropertyAccessFromIndexSignature`. Decided from the interface's
declaration: a string index signature, and `prop` not among its own
fields. Two exclusions, both probed: `Object.prototype` members
(`b.toString`) come from the prototype rather than the signature, and a
declared member alongside a signature (`c.foo` where `C` has both) is a
real property access. An interface with any `extends` abstains, since
only its own `fields` are read and a base's member would otherwise be
reported — a false-positive direction. Its first draft DID ship a false
positive, of a kind specific to this parser: the flag marker landed in
`grammar_misuses` and every non-marker entry there becomes a diagnostic
verbatim, so `<nopropertyaccessfromindexsignature-on>` was reported as
an error on every file carrying the option. Every marker needs an
explicit skip entry.

**TS1207** — decorators on both halves of one get/set pair. Two gates,
and the second is a limitation rather than a rule:

- LEGACY decorators only. Under standard ES decorators each accessor
  gets its own decorator application, so decorating both halves is
  legal — **seven corpus false positives** in `esDecorators/` said so.
  Every probe written for the rule had carried
  `@experimentalDecorators: true`, so not one of them could see it. Same
  gate direction as batch CK's TS1206.
- Class DECLARATIONS only. Inside a class EXPRESSION body the
  decorator-mode flag is not reliable: `(class E { @dec get x() {…} @dec
  set x(v) {…} })` with NO directive fires while the identical
  declaration stays silent, so some parser on that path carries
  `experimental_decorators`' `true` default instead of the
  header-derived value. That is a pre-existing inconsistency affecting
  every decorator-mode-gated rule, so the expression form is skipped
  rather than papered over. It costs nothing here —
  `decoratorOnClassAccessor7` is six class declarations. **Filed:** find
  which constructor supplies the default on that path and thread the
  header value through it.

**TS1249** — a decorator on a bodiless overload signature. Ambient
(`declare class`) and abstract members are excluded, and that exclusion
is where tsc 6.0.3 and the TS7 oracle DISAGREE: 6.0.3 reports TS1249 for
both, and `decoratorInAmbientContext` is TS7-ACCEPTED. Widening the rule
to match the local compiler would have shipped a false positive, so the
probe's answer was the wrong one to follow here — which is the caveat
`scripts/tsc_probe.mjs` states in its own header, now with an instance.

**TS2474** — a CALL in a `const enum` member initializer. A call result
is never a constant enum expression, whatever it returns. Everything else
abstains, and the boundary was entirely probed: legal in a `const enum`
are arithmetic on literals, a shift, a unary minus, a reference to
another member of the same enum (bare or dotted), and a reference to an
outer `const` — which is why a bare identifier and a property access
must not fire, and why `constEnum2`'s own `g = CONST` line is not among
tsc's two reports. `"x".length` IS TS2474 and stays a MISS: telling it
apart from `D.a` needs resolution this does not do. The same call in a
plain `enum` is legal, so the `const` is the whole difference.

### Batch CN (2026-09-03): one rule, and a check whose gate was wrong

+1 file (TP 2479 -> 2480, MISS 255 -> 254, FP 0, PFLEGAL 0). A small
batch, and the interesting part is what probing an EXISTING pair of
checks against the real compiler turned up.

**TS2500** — `class C implements A?.B {}` is not a qualified name. The
diagnostic went where `parse_implements_names` already resyncs, and its
own comment had named the shape it was skipping ("the `?.` of an invalid
`implements A?.B`") — only the report was missing. Note the asymmetry,
which is why nothing was added on the `extends` side:
`class C1 extends A?.B {}` is LEGAL, because an `extends` clause takes an
EXPRESSION, and `classExtendingOptionalChain` says so by accepting the
first half of its own file.

**The TS2610 / TS2611 pair had three problems, and finding them started
from writing a duplicate.** The intended rule — a derived class may not
change an inherited member's kind between a data property and an
accessor — turned out to exist already, so the new implementation was
deleted. Probing the existing one is what paid:

- **The two messages were SWAPPED** relative to their conditions: the
  loop that fires when the base has an ACCESSOR and the derived class a
  property said "defined as a property but overridden as an accessor",
  and vice versa. Detection was right, the text was not. Fixed.
- **The `useDefineForClassFields` gate was WRONG and is gone.** tsc
  reports both codes whatever that flag says — probed with it explicitly
  `false`, which still errors — because the flag changes how a field is
  EMITTED and not whether changing an inherited member's kind is legal.
  Removing it widens the population the pair judges, so it was measured
  on its own: TP 2480 / MISS 254 / FP 0, identical to keeping it. It buys
  nothing on the corpus and it is correct, so it is kept and the number
  is written down at the site. A UNIT TEST had pinned the wrong
  behaviour, with the confusion stated in its own comment ("the property
  flows through the setter -- allowed") — that is an emit fact, not a
  legality one. Third time a test has been found asserting the bug.
- **An AMBIENT class's accessors are invisible to the pair**, and that is
  recorded rather than fixed. The parser upserts a `declare class`'s
  `get x(): T` into `properties` without a `methods` entry carrying
  `accessor: "get"`, so `class_instance_accessor_names` cannot see it.
  That is simultaneously a MISS and a latent FALSE POSITIVE:
  `declare class A { get x(): string }` + `class B extends A { x = 1 }`
  is TS2610 and stays silent (`propertyOverridesAccessors4`), while
  `class B extends A { get x() { … } }` — legal, an accessor overriding
  an accessor — reads as an accessor over a FIELD and IS reported. The
  corpus contains no file of the second shape, which is exactly why
  FP 0 never caught it. The fix is in the parser and would move what the
  bridge generator and `.d.ts` emitter see, so it wants its own change
  rather than a corner of a grammar batch.

### Batch CM (2026-09-03): nine rules, and two things the parser hides

+11 files (TP 2468 -> 2479, MISS 266 -> 255, FP 0, PFLEGAL 0). Nine small
rules, and the two most useful findings are about the PARSER rather than
the checker.

**Where the ranking came from.** `checker_miss_buckets.mjs` reads codes
out of the submodule's TS6-era baselines, which is an approximation and no
answer at all for a file with no baseline. With `scripts/tsc_probe.mjs`
from batch CL there is a better source, so every remaining MISS file was
run through the real compiler under its own harness header and grouped by
the codes it actually produced. That ranking is what this batch worked
from, and it is the reason the rules are so small: the top of the list is
deep type machinery, and the long tail is 67 codes with exactly one file
each — mostly grammar.

**TS2583** (2 files) — `SharedArrayBuffer` and `Atomics` arrive with
`lib.es2017.sharedmemory`, so under an older `lib` they are not declared.
Same shape as batch CH's TS2591 for the `@types/node` names, same reason
for leaving the generated allowlist alone: `is_lib_global_value` answers
"could the platform have provided this", and only name resolution asks
"with THIS lib, did it".

**TS2350** (2 files) — the mirror of batch CL's TS2348. A
call-signature-only type has no construct signature, so `new` over it is
legal in exactly the case the message names, a signature returning
`void`. Provenance is the same argument: `Func` and the `<call>` sentinel
come from a written signature. The return type is what could be wrong, so
`Any` / `Unknown` / `Void` / a `Named` reference all abstain. A top-level
function DECLARATION is excluded by name rather than by inference,
because an old-style JavaScript constructor
(`function Point(x) { this.x = x }`) is exactly that shape and
`new Point(1)` is how such code is meant to be used. `new Symbol()` and
`new BigInt()` get their own arm: they are the two lib functions people
actually get wrong (both throw at runtime) and their types are not
modelled here.

**TS2708** (1 file) — a namespace whose body declares nothing that exists
at runtime is erased, so its name has no value meaning. Two things had to
be got right, and both were wrong first:

- The check has to sit ABOVE every resolution return in
  `check_undefined_name`, and the reason is a property of THIS parser:
  `parser_namespace_lower` lowers every namespace — instantiated or not —
  to `var N = N || {}`, so at script top level the module env and
  `globals` both bind the name whatever the body holds. The first draft
  fired only inside a function, which is where the env holds real locals.
  `ctx.script_top_level` (batch CL) is what tells the two apart.
- An `import a = A` alias COUNTS as a runtime declaration when the
  aliased namespace is instantiated. Missing that shipped a false
  positive on `exportImportAlias` (TS7-ACCEPTED), and the corpus caught
  it — see the parser finding below.

A type-only namespace NESTED in another is not covered, for the same
lowering reason: `export namespace inA { … }` records a value for `inA`.
`importStatementsInterfaces` stays a MISS.

**TS2448** (1 file) — a destructuring default may read a binding declared
EARLIER in the same pattern and not one at or after its own position.
Decided from declaration order alone: no types, no flow analysis. Written
for BOTH pattern kinds, because `const [a = b, b = 1] = xs` is TS2448
just as much as the object form — probed, and it was a MISS before the
generalization. The nested-closure form (`{ e = () => f, f = 1 }`) is
legal in tsc and silent here, so that abstention happens to be exactly
right rather than merely safe.

**TS18038 + TS1107** (2 files) — both class static blocks, and the second
is the label family again. `for await` inside a static block needs no
other condition: `classStaticBlock23` puts the same loop inside an
`async function` to show the enclosing function does not rescue it. And a
static block IS a function boundary, so a label declared outside it is
not a jump target inside it — batch CF's note says fourteen sites in
three files save / clear / restore `self.labels` around a function body,
and this fifteenth one did not, so
`label: while (v) { class C { static { break label } } }` found the outer
label. Clearing them makes the existing "Undefined label" parse rejection
fire, and the corpus file's second class (labels declared INSIDE the
block) is what checks the restore.

**TS1200** (1 file) — a line break before an expression arrow's `=>`. The
restriction is one-sided and was probed rather than assumed: a break
AFTER the arrow is fine, and a TYPE-position arrow may break before it,
which is why `parser_type`'s arrow sites are untouched. It went in as
`Parser::expect_arrow` because expression parsing consumes that token in
EIGHT places.

**TS1002** (1 file) — a string literal reaching a raw line terminator or
EOF. The scanner's catch-all arm consumed ANY character including `\n`,
so an unterminated string silently swallowed the rest of the file — the
same shape as batch CJ's unterminated regex, in the sibling scanner.

**TS2432** (1 file) — in a merged enum, only one declaration may omit the
initializer for its first element. Declaration shape only, and
`is_computed` is what distinguishes "no initializer at all" from "an
initializer we did not fully parse". The grouping key is the namespace
PATH plus the enum name, because the corpus case is three separate
`namespace M` blocks each holding `export enum E1`.

**The parser findings.** Two rules were recorded as values at ONE of the
two places their syntax can appear:

- `export import a = A` inside a namespace body records a type alias and
  no VALUE, while the plain `import a = A` spelling in
  `parse_module_block` records both. That asymmetry is what made TS2708
  false-positive, and the obvious repair — record the value here too —
  was tried, passed the conformance oracle, and was REVERTED by the full
  test suite. The bridge emitter reads `values` to decide what to import,
  and `export import JSX = JSXInternal` over an interface-only namespace
  is a type-only alias that must produce no import at all
  (`type-only-export-import-entry.d.ts`). Whether the alias binds a value
  depends on the TARGET, which is not resolved at parse time, so neither
  answer is right for both consumers: the parser stays as it was and
  `namespace_is_instantiated` takes the fact from `type_aliases`, where
  the export path already records it. That over-abstains for a namespace
  holding only real `export type` aliases — a MISS, not a false positive.
  Worth stating plainly: the corpus said yes and only the suite said no,
  which is the argument for running both.
- The label-stack clearing above is the same shape at the fifteenth of
  fifteen sites.

**REJECTED with measurement: wiring `unresolved_type_references` into the
conformance path.** It is the highest-yield-looking gap on the list —
`type T = Undeclared` and `type T<X> = X extends Undeclared ? … : …` are
both silent while `var q: Undeclared` fires, because an ambient VALUE
declaration reaches the expression checker by another route, and the
function is wired into `check_module` only. Wiring it in produced
FORTY-PLUS false positives, and their shape says why it has to stay
where it is: `check_type` carries one flat `local` list of
type-parameter names, which models a declaration's own parameters and NOT
the binders that appear inside a type — a call or construct signature's
own `<T>`, an `infer A`, a mapped type's key. So
`objectTypesIdentityWithGenericCallSignatures*`, `inferTypes*`,
`thisTypeIn*` and `mappedTypes*` all report their own bound parameters as
undeclared. The narrow version (report only when the type provably
contains no binder) was not attempted: the whole TS2304 solo set is four
files, two of them these type positions, and "provably no binder" is
another guess about the completeness of a list.

**Also measured and not taken:**

- **The permissive filter is not the blocker.** Running the whole corpus
  with it OFF flags 8 of the 277 MISS files at a cost of 49 false
  positives — recorded in batch CL and repeated here because it is the
  fact that decides where to look.
- **TS6133** (an unused `#private` member, 2 files) is deferred on the
  FAIL DIRECTION rather than the effort. Every formulation needs either a
  complete AST walker over the class body or a complete
  reference-recording channel in the parser, and a missed read makes the
  member look unused — that is a false positive, the one direction the
  budget does not allow. The reference mangling happens at four-plus
  sites and sub-parsers carry their own `grammar_misuses` array, so
  "complete" is not something the current shape can promise.
- **TS2403 for two CLASS types** (`var x: C; var x: D`) is silent because
  `structural_named_key` expands a class to its FIELDS and not its
  methods, so `C` and `D extends C { foo() {} }` produce the same key.
  Including methods would need a private/protected abstention (private
  members are nominal, so such a class is identical to no object type),
  and it is worth 1 of the 5 TS2403 files — the other four need `typeof`,
  spread and enum-assignability reasoning.

### Batch CL (2026-09-03): a real compiler as the legal-neighbour oracle

+11 files, and the batch's most durable output is not a rule. Every
"legal neighbour" claim in this repo has so far been an argument;
`node_modules/typescript` holds a real compiler (6.0.3), so
`scripts/tsc_probe.mjs` now runs it over a file the way the conformance
harness would — reading the `// @option:` header — and prints its
diagnostics. It replaces reasoning with a measurement for the two
questions the vendored baselines cannot answer: what TS7 actually SAID
about a file, and what it says about a hand-written neighbour that no
baseline covers. Three of the batch's rules were wrong on their first
draft and the probe is how each was diagnosed. Read its answers with one
caveat, stated in its header: 6.0.3 is not tsgo, so a disagreement with
the TS7 verdict is possible and is itself information — `symbolProperty37`
is in the TS7 error set and 6.0.3 accepts it, which is why
`member_name_duplicates` was left alone (its comment claims duplicate
well-known-symbol interface members merge legally, and against a real
compiler that claim still holds).

**First, the measurement that decided the strategy.** Running every
conformance case with the checker in STRICT mode — the permissive filter
entirely off — flags **8 of the 277 MISS files**, at a cost of 49 false
positives. So the suppression is not what is holding recall back: at most
8 files were behind it, five of them for good reasons (a lib signature's
optional arguments, `toFixed()` with no argument, a `using a = null`
diagnostic that is not the error TS reports). The other 269 files are ones
where the checker computes nothing at all, which is the same conclusion
`docs/checker-priority.md` reached, now with a number instead of an
impression.

**TS2348, three files, and a latent false positive underneath.** Calling
a class without `new` (`Tools.NullLogger()`) needs no inference at all —
a class's static side never carries a call signature, and neither
declaration-merging route can add one — so it is exempt from the
permissive "not callable" suppression for the same reason the
construct-signature-only case is. Carving that subset out exposed what
the filter had been hiding: `is_definitely_not_callable` had an
unconditional `Object(_) => true` arm, so `declare var q: { (): number };
q()` — an object type whose entire purpose is a call signature — was "not
callable". Nobody could see it, because the family was dropped wholesale.
The arm now asks for a `<call>` member. That fix is asserted through the
STRICT entry point, since in permissive mode the wrong answer and the
right one both look silent.

**TS2467 / TS2302, four files, and the same applied-in-some-places
family.** `check_static_uses_class_type_params` read a static member's
return type and parameters, which is where a signature carries types and
not where code does: `static bar() { var obj = { [foo<T>()]() {} } }` is
what real code looks like (computedPropertyNames34), and a static
member's computed KEY is a third position the signature scan cannot see.
Both now use the same predicate the two existing positions use, lifted
over statements. TS2467 is new and cheap because the offending set is the
class's OWN type parameters and nothing else — a type parameter of an
enclosing generic FUNCTION is legal in the same position, and that falls
out of reading `decl.type_params` instead of the ambient in-scope set.

**TS1117 on a well-known-symbol object-literal key, one file, and a
blocker that was written down and wrong.** `record_objlit_duplicate_keys`
skipped every `@@`-prefixed key, and its doc comment recorded
`symbolProperty36` as a deliberate MISS with a reason: only the CLASS key
path resolves a well-known symbol to a stable `@@<name>`, and renaming
the object-literal key would move keys the mangler and the dead-property
pass read. True of the approach it considered, and beside the point — the
parser wraps a computed entry's VALUE as `ComputedProp(key_expr, value)`,
so the key expression was already in hand and nothing had to be renamed.
Second time (after batch BZ) that a stated abstention's own comment named
the thing to remove.

**TS2449 in a class's own computed key, one file.** The class binding is
in its temporal dead zone while the body's computed keys are evaluated,
so a member key may not name its own class. TS2449 already existed for a
forward-referencing `extends`; this is the second position the same dead
zone covers. What keeps it narrow is the legal set, and all of it was
probed rather than reasoned: a static field INITIALIZER (`static q =
C.p`) runs after the binding is initialized, a method body later still,
and another class's name is not this class's dead zone.

**TS2454's lib-global exemption, one file, and a comment that was right
about a scope it did not check.** The exemption's own text says "a
TOP-LEVEL redeclaration of a runtime-provided lib global merges with the
platform value", and the code applied it at every scope. Inside a
namespace or a function, `var Symbol: SymbolConstructor` declares an
ordinary uninitialized local, and tsc reports TS2454 for all three of
`namespace M { … }`, `namespace M { var Object … }` and
`function f() { … }` — probed, not assumed. `CheckCtx` carries
`script_top_level` now, produced by the same `outer_modules.length() == 0`
root test the module-level checks already use.

**Two rules were WRONG in their first form, both caught by the corpus,
and both are the legal-neighbour lesson.**

- **TS2466 for object-literal computed keys is REJECTED**, with the
  measurement kept in the code so it is not re-attempted. The rule exists
  for CLASS member keys, so extending it to object-literal keys reads
  like the same family — and it is not: an object-literal computed key
  may legally mention `super`, and three TS7-ACCEPTED corpus files say so
  (`computedPropertyNames25` / `28` / `31`). It cost **6 false positives
  for 2 true ones**. What makes `computedPropertyNames30` an error is not
  a rule anything here can model: `28` is the same program with the
  object literal directly in the constructor instead of inside an arrow,
  and tsc accepts it. Modelling a distinction one file draws is fitting
  the corpus, so `30` stays a MISS.
- **IIFE arity is one-directional.** Checking a function literal's
  parameter count looked like the same kind of exact fact as a function
  declaration's — the parameter list is right there in the source — and
  checking BOTH directions cost **4 false positives for 1 true one**,
  because TypeScript has a rule that reasoning missed: an IIFE's
  parameters are contextually typed, so passing FEWER arguments than
  parameters is legal and they come out `undefined`.
  `contextuallyTypedIife` says so in a section headed "missing
  arguments" — `((x, y, z) => 42)()` is accepted. Too many is still
  TS2554, which is what `parserNoASIOnCallAfterFunctionExpression1`
  needs.

**Recorded, not attempted:**

- **TS7008** (a class member with no annotation and no initializer under
  `noImplicitAny`) is missing for PUBLIC members too, so it is not the
  usual family — it is simply absent. It stays absent because the parser
  cannot distinguish an implicit `any` from a written `: any` on a class
  property: `type_` is `Any` either way, and `class C { x: any }` is
  legal. `has_initializer` shows the shape of the fix (one more parser-set
  flag), and it touches every `TsClassPropertyDecl` construction site, so
  it is not worth one file.
- **Class EXPRESSIONS reach no class-level check at all.**
  `const C = class<T> { static x: T }` is silent where the declaration
  form fires. Ceiling measured before deciding: exactly **8** of the 266
  MISS files contain a class expression and one of those already flips
  via its declaration form, so it is ~7 files against giving every
  class-level rule a new population to be wrong about.
- **TS4127** (`override` on a dynamic name) is worth 2 files and batch BY
  rejected it as unsound. The probe now says exactly where the line is:
  `const prop = "foo"` keeps a literal type, so the key is late-bindable
  and `override [prop]()` is LEGAL (BY was right), while `let prop =
  "foo"` widens to `string` and is TS4127. A rule keyed on the
  declaration form of the key's binding would be sound; it is filed
  rather than guessed.

### Batch CK (2026-09-03): enum initializers, and one wrong attribution

+3 files, two rules, and a mistake worth more than the files.

**TS1308 / TS1163** — `await` / `yield` in an ENUM member initializer.
The generic await-outside-async check cannot catch these, and the corpus
file says why in its own shape: `enums/awaitAndYield` puts its enum
inside an `async function*`, so `in_async` and `in_generator` are both
true and both operators are legal *there*. An enum member initializer is
a constant-expression position evaluated at compile time, so nothing that
suspends may appear in one whatever the enclosing function is. It hooks
into `scan_skipped_enum_initializer`, which already speculatively parses
the initializer for the string-arithmetic rule and truncates every side
channel afterwards.

**TS1206** — a LEGACY decorator on a `#private` class member. Note the
gate direction: `#private` is rejected by legacy decorators and supported
by standard ES ones, so it points the OPPOSITE way from the `abstract` /
`declare` rule immediately above it.

**That rule cost two corpus false positives before it was right, and the
mistake is one already recorded here twice.** The file that suggested it,
`autoAccessorExperimentalDecorators`, combines TWO features — `accessor`
and `#private` — and gating on either looked equally plausible from the
error code alone. Gating on `accessor` flagged
`decoratorOnClassProperty13` (`@dec accessor prop`) and
`legacyDecorators-contextualTypes` (`static accessor y = 1`), both
TS7-ACCEPTED. The baseline settles it: the file errors on exactly lines
12 and 15, `accessor #a` and `static accessor #b`. The private name was
doing all the work and the auto-accessor none of it. Same substitution as
the `computed_props` terser label and the decorator-bucket ranking:
reading a two-feature file's error as belonging to the feature that
caught the eye first. Dropping the `accessor` half cost nothing — TP 2457
either way.

**TS1186 is left a MISS on purpose**, with the reason in the code rather
than re-derived later: `[...x = a] = a` never reaches the array-PATTERN
parser, because `parse_assignment_binding_pattern` tries
`parse_assignment_target_expr` first and for that source it SUCCEEDS —
the whole bracketed form parses as an expression. Two attempts at the
obvious sites (the rest arm of the pattern parser, and a scan of the
built pattern in `parse_assignment`) both stayed silent because neither
is where the shape lands. One corpus file, so it was not worth a third
guess at the AST shape.

### Batch CJ (2026-09-03): six scanner-level rules, +6 files

Every one of them was a missing case in a loop that already had an exit
for the well-formed shape, and the whole batch lives in `lexer.mbt` plus
five lines of wiring in `parser_core.mbt`, where the existing lexer
counters already become diagnostics.

- **TS1010** ("`*/` expected"): the block-comment skip's `None => break`
  was end-of-file INSIDE a comment and said nothing about it.
- **TS1125** ("Hexadecimal digit expected") for a radix prefix with no
  digits. Three arms — hex, binary, octal — each of which silently
  substituted 0, so the rule existed in none of them. The reason it fell
  through a check that looks like it covers it:
  `invalid_radix_digit_count` answers "a digit outside this radix"
  (`0b2`), which is a different question from "no digits at all" (`0b`).
- **TS1260** ("Keywords cannot contain escape characters"). Only the
  escape path of the identifier scanner can produce one, and the escape
  decodes to a perfectly legal identifier, so nothing downstream had a
  reason to object: `\u0076ar x = 1` scanned as the `var` KEYWORD and
  parsed clean. Keyed on what `classify_ident_or_keyword` returns rather
  than on a name list, so the two cannot drift apart.
- **TS1161** ("Unterminated regular expression literal"): a regex may not
  span a line, and the scanner had no line-terminator case, so `/ b;`
  scanned to end of file and swallowed the rest of it. The newline is
  deliberately not consumed, so the following statements still tokenize.
- **TS1005** ("`)` expected") for unbalanced groups in a regex, counted
  outside a character class only — `/[(]/` is a perfectly good regex.
- **TS1127** ("Invalid character"), narrowed to the Latin-1 symbols and
  punctuation.

The last one carries the only real judgement in the batch. Non-ASCII goes
to the identifier scanner, which over-approximates ID_Continue as "any
code unit >= 0x80" so that `変数` and `π` scan as ONE token — that is
correct, and it is why `¬` (U+00AC, category Sm) parsed clean
(`parserErrorRecovery_Block2`). Without a Unicode table, "not an
identifier character" is exactly what cannot be decided here in general,
so the rule covers the one block where the answer is knowable
(U+00A1..U+00BF plus `×` and `÷`) and excludes the code points in it that
ARE ID_Start — `ª` (U+00AA), `µ` (U+00B5) and `º` (U+00BA) — along with
the non-breaking space and the soft hyphen, which are not errors either.
Everything from U+00C0 up keeps the permissive treatment, so `café` and
`naïve` still scan as identifiers.

### Batch CI (2026-09-03): the operand of an update must be a reference

TS2357 / TS1109, +5 files off one rule. `++this`, `++await 42`,
`--await 42`, `++1` and the `++(++y)` that ASI produces from
`x \n ++ \n ++ \n y` (`parserS7.9_A5.7_T1`) are all rejected by tsc,
and none was flagged.

It rides on `record_assign_target_strict_misuse`, which is already called
at all four spellings JavaScript has for writing a binding (`=`, `+=`,
`++x`, `x++`) — the function batch BU built when `eval++` turned out to be
checked at two of the four. So there is no fifth place to forget.

It is a DENYLIST rather than the complementary allowlist, and that is the
one design decision worth recording. "Flag anything that is not `Var` /
`PropAccess` / `IndexAccess`" is the correct RULE and the wrong
implementation: a target can arrive wrapped in nodes that say nothing
about writability (`TypeArgs`, `As`, `Satisfies`, a `PureCall` marker),
and CLAUDE.md already records three soundness bugs paid for a wrapper
node whose default arm failed open. A denylist fails the other way — an
unlisted shape costs a MISS, not a false positive.

The neighbours that needed pinning are the ones a program actually
contains: `++(x)` (the parser strips the parens, so what reaches the check
is a bare `Var`), `this.x = 1` (a property access on `this` is a place,
unlike `this` itself), `o["k"]++`, `await x++` (the update is the operand
of `await`, not the reverse), and the read-only unary operators.

### Batch CH (2026-09-03): TS2591 and TS2391, +7 files

**TS2591** ("Cannot find name 'X'. Do you need to install type definitions
for node?") is the one rule in this whole run that a working TypeScript
programmer hits regularly. `module`, `require`, `exports`, `process`,
`Buffer`, `__dirname`, `__filename`, `setImmediate` and `clearImmediate`
are NOT part of the default `lib` set — they come from `@types/node` — and
all nine sat in the generated lib-global allowlist, so a `.ts` file using
CommonJS or a Node global with those types missing was accepted in silence.

The allowlist is deliberately left alone. Its seven other consumers ask
"could the platform have provided this name" (the TS2454
used-before-assigned exemption, among them), and for those the
conservative answer is still yes; only `check_undefined_name`
distinguishes the two questions, and it does so only after every
declaration lookup has had its say, so `declare var process`,
`namespace module { }`, an import or a local binding all still resolve.
`global` is excluded on purpose: `declare global { }` is standard
TypeScript and its identifier reaches enough walks that treating it as
undeclared is not worth one file.

**TS2391** ("Function implementation is missing or not immediately
following the declaration") is answered by LOOKAHEAD from the signature —
after a bodyless `function f`, the next declaration must be a function
named `f` — and NOT by carrying a pending run of signature names across
statements. That distinction cost a corpus false positive to learn. The
first version kept the run on the parser and flushed it whenever
`parse_stmt` saw a statement that was not a function declaration, which
includes the statements inside a nested function BODY, because
`parse_function` parses the body through the same funnel. So the legal
three-signature set inside `function other<T …>()` in
`recursiveTypesUsedAsFunctionParameters` — a TS7-ACCEPTED file — was
reported the moment the implementation's own `return null;` was parsed. A
scope-saved field would have had to be threaded through every save /
restore site around a function body; the lookahead needs no scope model at
all.

This also settles half of what this file records as blocked. `TsFunc.body`
being non-optional is a real blocker for anything DOWNSTREAM of the parse,
and TS2393 / TS2394 stay blocked on it — but `last_function_bodiless`
already carries the fact at parse time, so the PAIRING question was always
answerable there. Two declaration arms needed the hook and only one had it
at first: `parse_stmt`'s, and the module loop's own `if self.check(Function)`,
which is why `function data(): string; function next(): string;` stayed
silent while the same pair without return annotations was reported.

### Batches CF + CG (2026-09-02): ten grammar rules, +19 files

Under the goal "MISS <= 250" the ranking from batch BY INVERTS, and that is
worth stating rather than quietly reversing: BY concluded that
`parser/ecmascript5` was the wrong cluster to take, because its 49 files
are `parserErrorRecovery_ParameterList6`-shaped broken syntax nobody
writes. That judgement was correct under the earlier objective, which
weighted real-world encounter frequency. When the corpus COUNT is the
objective, corpus count is what to rank by, and that directory is the
largest and cheapest cluster in the MISS set. Both readings are recorded
here so neither looks like a mistake.

The rules, each one condition next to a rule that already existed:

- **TS1035 / TS1046** — a QUOTED module name declares an ambient external
  module, which only a `declare` context may do. The condition is exact
  rather than approximate: every declare-context caller tests
  `name == "module" && peek_at(1) is Str(_)` and routes that to
  `parse_ambient_external_module_decl*` BEFORE reaching
  `parse_namespace_decl_with_mode`, so a quoted name arriving there is by
  construction non-ambient.
- **TS1213** — a strict-mode reserved word as a binding identifier. The
  22nd instance of this repo's recurring family: the rule was already in
  `parse_binding_ident` for `let` and `yield`, at two of the nine
  spellings the language has, so `class C { constructor(static) {} }`
  parsed clean even though a class body is automatically strict.
- **TS1029** — an accessibility modifier must precede `override`. The rule
  exists for class MEMBERS; parameter properties never got it, because
  `skip_param_modifiers` consumed `override` only to discard it.
- **TS1031** — `declare` may modify a class FIELD and nothing else. Written
  for the constructor alone and stopped there.
- **TS1115** — `continue` needs a label on an ITERATION statement, and the
  existing check only asked whether the label EXISTS; its own comment said
  so ("should be an iteration label for continue"). The kind is encoded in
  the label-stack ENTRY rather than kept in a second array, because
  fourteen sites in three files save, clear and restore `self.labels`
  around a function body and a parallel field would have to be threaded
  through every one — which is the same shape as the family above. A
  prefix rides along through an opaque copy for free.
- **TS1106** — `for (async of x)`. See the false positives below.
- **TS1063 / TS1319** — `export =` and `export default` inside a namespace.
  A namespace body is parsed by a fresh `Parser` that cannot know it is a
  namespace body, so it leaves a sentinel and the enclosing parser decides.
- **TS1155** — a `using` in a C-style for head must be initialized. What is
  LEGAL here came from the baseline rather than from reasoning:
  `for (using of = null;;)` and `for (using of: null = null;;)` are both
  fine, and `usingDeclarationsInForOf.4` errors on its third line alone.
- **TS2852 / TS18054 / TS2853** — where an `await using` is allowed. There
  are THREE declaration sites (a statement, a block-statement, a for-head)
  and the pre-existing TS2854 marker was written at one of them, so
  `{ await using d = null }` inside a block — how every
  `awaitUsingDeclarations` test is written — could never reach it. One
  `record_await_using_context` helper is now called from all three. A class
  static block needed a new `in_static_block` flag because neither
  `in_function` nor `in_async` can say so: a top-level class's static block
  leaves `in_function` false, and a class inside an `async` function leaves
  `in_async` true.

**Three of the ten were corpus FALSE POSITIVES first, and all three are
about a rule's legal neighbour.** TS1106 is a LOOKAHEAD restriction, not a
semantic one — it exists so `for (async of …)` cannot be read as the start
of `for await (… of …)` — so `for await (async of x)` and
`for ((async) of x)` are both legal, and the AST cannot tell the second
from the first because the binding parser strips parens (the token is
checked instead). And `export type R = number` makes a file a module: the
module-syntax evidence set had been assembled from the export shapes that
bind a VALUE, so `usingDeclarationsDeclarationEmit.2` — TS7-ACCEPTED, two
`export type` aliases and nothing else — read as a script. The marker now
sits at the `export` keyword in all THREE export parsers rather than on
the forms that happen to need it, because a marker written at the form is
a marker written at one of them.

Two fixes came along that are not conformance rules. The statement-level
`async function` arm cleared `in_async` to `false` instead of restoring it,
so an enclosing async body went non-async the moment it declared a nested
`async function`; `parse_function` reads that flag to learn whether the
function it is parsing is async and saves/restores it around the body
itself, so the site only has to hand it the answer. And the RUNTIME export
parser recorded no `<export-default>` marker at all, so the TS2528
multiple-defaults count could not see a default export in a `.ts` file.

### Batch CE (2026-09-02): TS1048, TS1434, TS1196, TS1368

Six files, four rules, each of which was one missing condition:

- **TS1048** ("A rest parameter cannot have an initializer") — the 21st
  instance of the family and the closest yet: TS1047 ("a rest parameter
  cannot be optional") sits on the adjacent line and asks about `?` where
  this asks about `=`.
- **TS1434** ("Unexpected keyword or identifier") for a repeated `static`.
- **TS1196** — a catch clause annotation must be `any` or `unknown`. The
  annotation was already parsed here, and discarded; only the comparison
  was missing.
- **TS1368** ("Class constructor may not be a generator") — legal at every
  other member name, which is what the test pins.

### Batch CD (2026-09-02): TS2449, TS5061, TS1117

Four files, three rules, each self-contained:

- **TS2449** ("Class 'X' used before its declaration"): a class whose
  `extends` clause names a class declared LATER in the module. A class
  binding is block-scoped and its heritage clause runs at declaration time,
  so the later name is still in its temporal dead zone — unlike a function
  declaration, which hoists. An AMBIENT class on either side is exempt, and
  that exemption was found by probing rather than by reasoning:
  `class C1 extends C2 {} declare class C2 {}` is ordinary @types layout
  and fired before it was added, because a `declare class` emits nothing and
  asserts the binding exists from elsewhere — declaration order in a `.d.ts`
  carries no runtime meaning. An interface base is also exempt (a type, no
  runtime binding), and an out-of-module or expression base abstains because
  the order is not visible.
- **TS5061** ("Pattern 'X' can have at most one '*' character") for a quoted
  ambient module name. Counting is the whole rule: one `*` is the legal
  wildcard form, none is an ordinary specifier.
- **TS1117** ("An object literal cannot have multiple properties with the
  same name"), at the single site where the field list is complete. Three
  shapes are legal rather than abstained-from: a `get x` / `set x` PAIR
  (the parser keys them `@@get:x` / `@@set:x`, so comparing prefixed keys
  gives that for free), a SPREAD (which may legally supply a key another
  entry overrides — `{ ...o, a: 1 }`), and a computed key.

  A FOURTH was missing and shipped as a false positive: `{ … }` in
  expression position is a COVER GRAMMAR, an object literal only until an
  `=` follows, at which point it was an object destructuring PATTERN all
  along and duplicate names in it are legal. `({ foo, foo } = { foo: 2 })`
  was reported. Two things about how it was found are worth keeping. The
  ORACLE could not see it: `destructuringSameNames` contains illegal
  spellings too, so the file was a TP whichever half fired, and the run
  reported FP 0 with the bug present. The UNIT SUITE caught it, because an
  earlier batch had written those three legal shapes down as cases — which
  is the argument for pairing every rule with its legal neighbour in a
  test rather than trusting the corpus count. Gating on `not(self.check(Eq))`
  at the call site costs nothing: TP 2443 / MISS 291 / FP 0 before and
  after.

`symbolProperty36` (`{ [Symbol.isConcatSpreadable]: 0,
[Symbol.isConcatSpreadable]: 1 }`) is left a MISS on purpose and the reason
is written into the code: the object-literal parser stores a computed key as
`@@computed:<index>`, so two of them never compare equal, and only the CLASS
key path resolves a well-known symbol to a stable `@@<name>`. Giving object
literals the same naming would change keys the mangler and the
dead-property pass read — too much blast radius for one file.

**TS2403 was the biggest bucket (12 files) and is not worth 12.** Its
simple spelling already works (`var x: number; var x: string;`), so the
files were opened. `unionTypeEquivalence` needs TYPE IDENTITY rather than
assignability — `var x: C; var x: C | D;` errors even when `D extends C`,
and the same file's `var y: string|number; var y: number|string` and its
`typeof`-aliased `z1` pair must stay silent, so it needs order-insensitive
identity plus `typeof` resolution for ONE file. The other eleven need real
inference of an un-annotated second declarator (`var t: this; var t = …`,
`var x: never; var x = []`, spread inference, generic signature
comparison). Third time this session that a code count promised a batch and
delivered one file; the fix is the same as the first two — open the files.

### Batches CB / CC (2026-09-02): the goal changed, so the ranking did

Everything above was ranked by cost AND real-world frequency, and on that
basis `parser/ecmascript5` — the largest and cheapest cluster at 49 files —
was explicitly the WRONG one to take, because its files are
`parserErrorRecovery_ParameterList6`-style broken syntax nobody writes.
With the objective restated as a corpus number, corpus count IS the
objective and that judgement inverts. Both are recorded so neither reads as
a mistake: they answer different questions.

**CB (+10): the `using` declaration family, plus three one-site rules.**
`is_disallowed_lexical_stmt_start` rejects `let` / `const` / `class` /
`function` / `async function` in a single-statement position and had NO
`using` arm — which is TS1156 exactly ("'using' declarations can only be
declared inside a block"). Seventeenth instance; `using` reached the parser
after that check was written. Both spellings gate on the same look-ahead
the statement parser uses, so a plain identifier reference named `using`
(`if (c) using;`) is untouched. With it: TS1155 (must be initialized —
visible only because `parse_var_decl_list_from` substitutes the
`__ts_no_init__` sentinel, so `init` has no `None` case), TS1493/1494 (a
`using` head in `for…in`, keyed on `is_in` because `for (using x of …)` in
the same branch is legal) and TS1547/1548 (a `case` clause body, checked by
peeking at the statement about to be parsed rather than by carrying a flag —
a clause body is a statement LIST, so where we stand answers the
enclosing-block question, and `case 1: { using x = d; }` reaches
`parse_block` instead).

Three more, each an existing check that covered some of what it named:
`check_getter_returns_value` read `module_.classes` only, so TS2378 missed
`var v = { get Foo() { } }` — the object-literal spelling its own doc
comment names (`parserAccessors3`, `parserES3Accessors3`). Restricted to an
EMPTY body, which is why none of that check's abstentions (a `throw`, a
loop, a bare `return`) need repeating, and shared between the two
object-literal accessor parse paths because TS1054/TS1049 are written out
at both. The ten predefined-type names were written out for classes AND for
type aliases and not for interfaces (TS2427) — and the coverage LOOKED
partial for a reason that is not a rule: `number` / `boolean` / `string` /
`void` have dedicated lexer token kinds so `interface string {}` cannot be
parsed at all, while `any` / `unknown` / `never` / `bigint` / `symbol` /
`object` arrive as ordinary identifiers and sailed through. And TS2505 (a
`void`-annotated generator) went into the async return-type helper, which
already took `is_generator` as its exemption — same question, does the
declared return type contradict the function's KIND.

**CC (+6): duplicate names in one destructuring pattern, and two for-head
rules.** TS2451 for `let { foo, foo }` / `let [v, v]`, placed in
`parse_var_decl_item` so every declarator of a group passes it, plus the
for-of head. `destructuringSameNames.ts` is the legal-neighbour list
written by the TypeScript team and is asserted verbatim: `let { foo, foo:
bar }` binds two DISTINCT names, and every assignment-pattern repeat
(`({ foo, foo } = …)`, `[foo, foo] = …`) is legal because an assignment
target is not a declaration — those parse as expressions and never reach a
binding parser, so they are excluded structurally rather than by a test.
`var` merges, so the caller has to say which keyword it parsed and
`is_block_scoped` has no default. Also TS2481
(`for (let v of []) { var v }`, reading only the body's own flat `var`
statements so a nested block falls through) and TS7022 for the DIRECT
self-iterable (`for (var v of v)`), the indirect inference-cycle cases
(`for-of33`/`34`/`35`) abstaining.

**One false positive of my own, and it is the twentieth instance of the
family this document catalogues.** The TS7022 rule shipped without a
`no_implicit_any` gate and reported four TS7-ACCEPTED files:
`for (var of of of) { }` and `for (var of in of) { }`
(`parserForOfStatement18`/`19` and their ES5 twins) bind a variable named
`of` and iterate one named `of` — a genuine self-reference that tsc stays
silent about under `@strict: false`. Every other `<noimplicitany>` recorder
in the parser gates on that flag. Caught by the oracle, not by reasoning,
which is the argument for running it per batch rather than per round.

And the stale-binary trap landed a third time, in the opposite direction:
after the gate fix only the RELEASE binary was rebuilt, so a debug probe
reported the FP as still present and a test assertion written from that
probe was wrong. Rebuilt, all 26 assertions of the new test match the
checker. CA's zero is deliberate and explained in its own
section — the diagnostic it adds is one the conformance suite does not
exercise and real code hits constantly.

### Batch BY (2026-09-02): rank by MACHINERY, not by code

The ranking the miner shipped with was by error CODE, and a code is not a
difficulty class — this document already records that mistake for
`computed_props`, `loops`, `typeofs` and `sequences`. Two refinements, both
cheap, and each changed what the list said to work on.

**1. Rank by FILE, not by (file, code).** A file flips MISS -> TP as soon as
we flag ANY error in it, so the bucket table double-counts: a file carrying
five codes inflates all five. `checker_miss_buckets.mjs` now prints `solo`
(files where this code is the ONLY lever — the guaranteed yield) beside
`total`, plus a greedy cover answering the question a batch actually asks.
The head is TS2322 30 total / 15 solo, TS2345 20/10, TS2339 18/7,
TS2304 15/4, and the best twelve rules together reach only 33% of the
MISSes — the tail is genuinely long.

**2. Those four buckets are NOT missing machinery.** Probing the simplest
spelling of each settled it in one command: `const x: string = 1`,
`f(1)` against `f(a: string)`, `o.b` on `{a: 1}`, and a bare
`nonexistent;` are ALL already flagged, at six assignment sites, three call
sites and four property sites. So `docs/checker-priority.md`'s "only large
type-machinery features remain" is wrong a second way — the machinery
exists and something specific defeats it in those files.

**3. Re-bucketing by FEATURE beat re-bucketing by code.** `symbolProperty*`
spans TS2403 / TS2420 / TS2353 / TS2454 / TS2464 / TS2320 / TS2554 — seven
codes, one feature, invisible to a code-keyed cover. Grouping the 351 MISS
files by conformance directory gives `parser/ecmascript5` 49,
`statements/VariableStatements` 20, `classes/members` 16,
`decorators/class` 15, `es6/Symbols` 15, `es6/destructuring` 12,
`es6/for-ofStatements` 12.

**And the two axes conflict, which is worth stating rather than smoothing
over.** `parser/ecmascript5` is the biggest cluster AND the cheapest class
(grammar), but its files are `parserErrorRecovery_ParameterList6`-style
broken syntax nobody writes — high corpus count, near-zero real-world
frequency. Using the corpus count as a proxy for "what users hit" is the
same label-for-objective substitution recorded above. The batch was picked
from the intersection instead: declaration-level rules (no type inference)
over constructs real code contains.

The legal-neighbour probe ran BEFORE any implementation, mechanically,
against all 1750 TS7-accepted files. It rejected more than it approved:

| rule | TN files that TS7 ACCEPTS | verdict |
|---|---|---|
| decorator on `#private` | **7** (`esDecorators-*`) | REJECTED |
| private setter, no getter | 1 (`privateNameSetterExprReturnValue`) | REJECTED |
| decorator on a static block | 0 | implemented |
| decorator on `import X = …` | 0 | implemented |
| `override` + computed name | 0 | REJECTED anyway — see below |
| `super` with type arguments | 0 | implemented |

Landed (+7 TP, attributed by diffing the miner's per-file verdicts —
6 files flipped, 0 regressions, then +1 more after the `TypeArgs` fix):

- **TS2335 / TS2337 — `super` at every class body site (4 files).** The
  check EXISTED, with its helper, its message and its FP-safety argument,
  and read only `decl.constructor_body`. A class body holds code in eight
  places; `super.foo()` in an ordinary METHOD of a heritage-free class
  parsed clean. **Thirteenth instance** of one rule applied to some of the
  sites it names. Fixed as one function over the whole `TsClassDecl` that
  enumerates every body-bearing field, so a new field is a visible omission
  in one place. `implements` is deliberately not heritage here (it brings no
  base constructor), which is why the condition is `base_names` /
  `base_expr` and not the parser's `class_decl_no_heritage`. TS2337 reuses
  the same walker through a `SuperRefKind` parameter rather than a second
  copy — see the TS2466 entry for why that mattered.
- **TS1206 — decorator on a static block / on `import X = …` (2 files).**
- **`TypeArgs` hid `super<T>(0)` (1 file).** `parserSuperExpression2` did
  not flip with the rest, and the reason is the one CLAUDE.md predicted in
  writing: "twice that a wrapper node's fail-open default has cost a
  soundness bug, and the reason to expect a third." This is the third.
  `super(0)` fired, `super<T>(0)` reached `_ => false`. A sweep of every
  checker walker that peels a value-preserving wrapper found two more gaps
  (below) and no others.
- **Five parser diagnostic channels were dead inside a namespace.**
  `namespace N { eval = 1 }` and `namespace N { @dec var z }` recorded
  their diagnostic and had it dropped. Cause: `parameter_property_misuses`,
  `strict_mode_misuses`, `invalid_decorator_uses`,
  `param_optional_initializer_misuses` and
  `interface_member_modifier_misuses` sat inside an
  `if outer_modules.length() == 0` block. That guard is correct for exactly
  ONE thing it wrapped — `deprecated_compiler_options`, a file header — and
  was inherited by the rest; a later workaround re-drained
  `grammar_misuses` from namespaces instead of fixing it. Fifteenth
  instance, with a twist: not one rule written twice, but one item's
  correct condition applied to six that do not share it. Now one
  `parser_channel_issues(module_)` called for every module.

  **Correction to my own reasoning while doing this**: I expected a large
  yield, on the theory that every rule from batches BU–BX was disabled
  inside namespaces. Measured, it is **+1 file** on the corpus, because
  most of those rules route through `grammar_misuses`, which the workaround
  already covered. The value is the bug class, not the count — the same
  shape as BX's export-namespace finding, which the corpus also could
  barely see.
- **TS2466 had a SECOND hand-written `super` walker**, and it was a strict
  subset of the shared one: no arm for `Spread`, `PureCall`, `TypeArgs`,
  `Await`, `As`, `Satisfies`, `Cond`, any of the three assignment forms,
  `New`/`NewExpr`, or `Call(_, args)`. That last one is reachable —
  `[f(super.m())]`, `super` in an ordinary named call's argument. Deleted
  and delegated rather than patched arm by arm, since patching is what
  produces the pair.
- **`collect_expr_value_names` lost bindings under three wrappers.** It
  answers "which names are DECLARED", so a missing arm makes a later
  reference read as undeclared — the FALSE-POSITIVE direction, the one with
  a zero budget. `f<T>(function g() {…})` hid `g`.

REJECTED with evidence, not deferred for lack of time:

- **TS4127 (`override` on a computed name, 2 files).** Flagging every
  `override [k]()` is FP 0 on the corpus and UNSOUND on legal code.
  `overrideLateBindableName1`'s own baseline names only `Base3` — with
  `const prop = "foo"`, `class D extends B { override [prop]() {} }` is
  legal when `B` declares `[prop]`, because a `const` string is
  late-bindable. Our `class_key_name` folds only literal EXPRESSIONS, so
  `[prop]` and `[dynamicLet]` are the same `"<computed>"` node; separating
  them needs declaration resolution. "FP 0 on the corpus" is not soundness,
  which is the whole reason this is written down.
- **TS1029 on a parameter property (1 file).** The modifier-order rule
  already exists for class MEMBERS, including its `override` arm;
  `skip_param_modifiers` consumes `override` and discards it. Fourteenth
  instance — but the right fix is to unify the two, not to write the order
  out a third time, and unifying widens the member rule (it would newly
  reject `static declare`, `abstract` orderings) and so needs its own FP
  measurement. Filed rather than half-done.
- **TS1206 on a `#private` member (2 files).** Legal under standard ES
  decorators — 7 TS7-accepted files rely on it. The parser DOES know the
  mode (`experimental_decorators`), so a gated rule is ~5 lines, but it
  reads a corpus DIRECTIVE and real code sets the flag in tsconfig, which
  the parser does not read. Real-world value ≈ 0.
- **TS2806 (private accessor with no getter, 1 file).** Not a declaration
  rule at all: the error is at the USE, and `this.#x += 2` (reads) versus
  `this.#x = v` (does not) is the distinction. Same family as the
  `x += 1` -> `x++` bug recorded above.
- **`typeOfThisInStaticMembers9` stays a MISS by design.** Its errors are
  `function`-expression and class-expression boundaries inside a DERIVED
  class, where a sibling arrow on the same class is legal. The walker
  refuses to descend into either, which is what keeps the 11 TS7-accepted
  object-literal-`super` files clean; separating the boundaries needs a
  per-boundary rule rather than a mention test.

One tooling fix: `checker_miss_buckets.mjs` had the same stale-binary trap
`checker_conformance_oracle.sh` had last round — it preferred RELEASE
unconditionally while `moon build --target native` produces DEBUG. It picks
the newer build now and prints which, like the oracle.

### Batch BZ (2026-09-02): TS2420 never checked whether a member is PRESENT

TP 2390 -> 2391, MISS 344 -> 343, FP 0 / PFLEGAL 0 / TN 1750.

**Read that +1 before reading anything else, because the estimate was 5.**
The TS2420 bucket holds 5 MISS files and the batch was sized from that
number. Only ONE of them is the missing-member form (`symbolProperty25`);
the other four raise TS2420 for unrelated reasons — private-member
incompatibility through interface merging (`mergedInterfacesWithInherited
Privates`, `…2`), overload assignability
(`stringLiteralTypeIsSubtypeOfString`), a numeric indexer
(`subtypingWithNumericIndexer5`). This document already records "an error
CODE is not a difficulty class" for `computed_props` and the decorator
cluster; this is the same mistake made about YIELD instead of difficulty,
and the fix is the same — open the files.

The reason to ship it anyway is the reason the corpus cannot show: adding a
member to an interface and forgetting to implement it is what a person
actually does, and the conformance suite has almost no cases of it because
it was written to exercise the type system, not to reproduce everyday
mistakes. Same shape as batch BY's namespace-channel fix, which was also
worth one corpus file and a whole class of product-facing bug.

Found by applying batch BY's own method (probe the simplest spelling) to the
next two buckets down. `check_class_implements` checks the TYPE of members
that are there; it did not check that they are there at all:

| source | tscheck |
|---|---|
| `interface I { a: number } class C implements I { }` | **0 issues** |
| `interface I { a: number } class C implements I { a: string = "x" }` | 1 |
| `interface I { m(): void } class C implements I { }` | **0 issues** |
| `interface I { m(a: number): void } class C implements I { m() {} }` | **0 issues** |

This one is NOT the "rule applied to some of the sites it names" family, and
saying so corrects a characterisation made before the code was read. The doc
comment stated the abstention and its reason in writing: "a *missing* member
is deliberately not flagged (it may be inherited from a base class we don't
fully thread here)". A documented abstention with a stated blocker, not an
oversight. The work was to remove the blocker.

`resolve_base_chain_members` does that. The walk already existed inside
`check_override_modifiers` — generic base, expression base, multiple bases,
out-of-module base and a lowered-class interface that extends something all
set `resolvable = false` — so it was extracted rather than rewritten. Both
consumers ask a question whose wrong answer is a false positive ("no base
declares this `override`" / "no base supplies this interface member"), so
`resolvable == false` must abstain in both, and a second copy of such a walk
is the last thing this file needs: the two `super` walkers that had drifted
apart were fixed in the same session.

The legal-neighbour surface is where the work was, and scanning the accepted
corpus beat imagining cases. Exactly 9 TS7-ACCEPTED single-file cases carry
`class … implements`, and every one is accounted for:

| file | why it stays silent |
|---|---|
| `mixinAbstractClasses` | `abstract` class (and implements it anyway) |
| `mixinAbstractClassesReturnTypeInference` | same |
| `accessorsOverrideProperty9` | `abstract class MixedClass … implements` |
| `symbolProperty23` | well-known-symbol key, `@@toPrimitive` on both sides |
| `ExportClassWhichExtendsInterfaceWithInaccessibleType` | parameter properties, inside a namespace |
| `parserSyntaxWalker.generated` | `implements` only inside comments |
| `everyTypeWithInitializer` | member declared |
| `throwStatements` | member declared |
| `assignmentCompatWithObjectMembers3` | required present, other member optional |

Two of those shapes — the symbol key and the namespace-scoped parameter
property — were absent from the case list written from first principles, and
only the scan produced them. A third route was found by re-reading rather
than probing: **class / interface declaration merging**. `class C implements
I {}` beside `interface C { a: number }` is legal and the interface supplies
the member; `.d.ts` files pair a class with a same-named interface routinely,
and this pass runs on them, so missing it would have false-flagged correct
bridge input. `check_class_interface_merge_modifiers` in the same file shows
the repo already knew the shape.

Abstains, each because a member could arrive from somewhere not enumerated:
an `abstract` class (a subclass may supply it — and zero baselines in the
whole TypeScript corpus raise TS2420 on an abstract class), a class with an
instance index signature, an unresolvable base chain, an OPTIONAL interface
member (optionality arrives as `T | undefined`, so a required
`T | undefined` abstains too — the safe direction), and a computed name.
Inherited interface requirements (`interface I extends J`) are not
collected, which loses a finding and cannot invent one. A STATIC member does
not satisfy an instance requirement, and that fires.

`TS2430` (interface incorrectly extends, 6 files / 2 solo) was probed at the
same time and is FINE at the simple spellings — wrong property type, wrong
method type and optional-vs-required all fire. Its MISSes are elsewhere.

`TS2739` / `TS2740` ("Type X is missing the following properties") is the
same presence question asked of a VALUE, and needs NO work: it already
fires at all five sites probed — a variable initializer, a call argument, a
return, a type-literal target, and a fully-empty object literal — with the
optional-property and all-properties-present neighbours correctly silent.
Class-side presence was the only missing half.

### Batch CA (2026-09-02): the duplicate-declaration family was absent

**Zero corpus files, and the reason is stated below rather than discovered
afterwards.** TP / MISS / FP / TN all unchanged at 2391 / 343 / 0 / 1750.

Probing the next codes down found not a gap but a hole:

| source | before |
|---|---|
| `let x; let x` (TS2451) | **0 issues** |
| `const x = 1; const x = 2` | **0 issues** |
| `let x = 1; var x = 2` (either order) | **0 issues** |
| `class C {} class C {}` (TS2300) | **0 issues** |
| `let x = 1; function x() {}` | 1 issue |

Sixteenth instance of the family, and this one is visible in the check's own
doc comment. `check_function_var_duplicates` walks `module_.top_level_stmts`
matching `Var(Ident(n)) | Let(Ident(n)) | Const(Ident(n))` and compares the
name against `module_.funcs` AND NOTHING ELSE — the loop, the pattern and
the message were all already there, and the declarations were never compared
against each other. The comment says "only the function-vs-binding pair is
flagged" and gives two reasons: `var`+`var` merges, and function overloads
legally repeat a name. **Neither reason reaches `let`+`let`** — a second
`let` is not a merge and not an overload — so the comment justifies
excluding two shapes and then excludes a third silently.

Deliberately NO scope walk. Only the flat `Ident` forms of
`top_level_stmts` are read, so `{ let x } { let x }` never reaches the check
(an inner `let` sits inside a `Block` statement the match does not descend
into), a destructuring pattern falls through, and a `for` head is a
different statement; the layered walker already calls this per namespace
body. Every omission loses a finding and cannot invent one, which is the
right direction and the reason not to reach for the binder-form walk this
repo has paid for seven times.

The corpus yield is 0 because all four in-bucket files are outside that
stated scope, checked by opening them rather than assumed:
`destructuringSameNames` is `let { foo, foo: bar }` (a duplicate inside one
destructuring pattern), `for-of52` is `for (let [v, v] of [[]])` (an array
pattern in a `for` head), `autoAccessor11` is class auto-accessor members,
`localTypes4` is local TYPE declarations inside functions.

Shipped anyway, and the standard applied is the repo's own. #84 / #87 / #95
were rejected because measurement showed they did not achieve their stated
purpose. This one does — 7 firing spellings, 11 legal neighbours silent, all
probed against the real checker — and what the number says is that the
conformance suite does not contain the shape, exactly as with batch BX's
export-namespace false positive (corpus byte-identical, real product bug)
and batch BY's namespace channels (+1). Before this, `mtsc` type-checking
ACCEPTED `let x; let x`, a program tsc rejects.

TS2393 ("Duplicate function implementation") is NOT attempted, with a
mechanical reason: `TsFunc.body` is not optional, so an overload SIGNATURE
and an implementation are indistinguishable from `module_.funcs` — the
neighbouring `check_overload_void_return` has to guess "the last
declaration is the implementation" for the same reason. TS2394 ("overload
signature not compatible with its implementation") is absent entirely and
blocked on the same fact.

One instrumentation note, because it looks like a contradiction and is
not. `moon test` prints a SECOND accuracy line from
`parser_typescript_wbtest.mbt` — `precision=411/414
(false-positives=3)` — while the gate above says FP 0. Both are right:
that harness is a loose catastrophe net (20% cap) over a pinned 31-directory
subset, it decides "clean" from the presence of a **TS6-era**
`.errors.txt`, and unlike the gate it counts multi-file cases and files
tsgo never ran. The three are `assertionTypePredicates2` (multi-`@filename`,
which TS7 does error on) plus `classWithStaticFieldInParameter{Initializer,
BindingPattern}.3` (both NOTRUN under TS7), and all three are batch BE's
TS2373 parameter-scope diagnostic, not this round's. Checked rather than
assumed — the first explanation offered ("TS6/TS7 divergence") was measured
and came back ZERO files, which is why the real cause is written down here.

**The MISSes are ranked now, and the strategy doc was wrong.**
`scripts/checker_miss_buckets.mjs` (`just checker-miss-buckets`) classifies
every single-file case in parallel, caches the per-file verdict, and buckets
the MISSes by the error codes in the submodule's baselines. Its totals are
cross-checked against the oracle — a miner that disagrees with the gate is a
broken miner, and that had to be visible rather than assumed. The verdict
(errors / accepts) comes from the vendored TS7 manifests; only the bucket
LABEL comes from the TS6-era baselines, which is an approximation and is
documented as one. A MISS with no baseline file lands in `NOBASE` rather
than being dropped.

The answer contradicts `docs/checker-priority.md`, whose conclusion —
"増分的な sound recall win は枯渇" — was measured against the **TS6** oracle
in June:

- **128 of the 388 MISS files are flippable by a pure-grammar (TS1xxx)
  rule.** No assignability, no flow narrowing, no generic instantiation.
- **91 of them have baseline codes that are ALL TS1xxx**, i.e. not one type
  judgement is needed anywhere in the file.

Batch BX (2026-09-01): TP 2373 -> 2383, MISS 361 -> 351, FP / PFLEGAL 0.
Ten files, and one of them was a gap in a check that already existed.

- **TS1169 / TS1170** — a computed property name in an interface (1169) or
  a type literal (1170) must refer to a literal type or a `unique symbol`
  (7 files). A denylist of three token shapes at bracket depth 0: an
  assignment (`[a = 0]`), a binary operator (`["" + ""]`), and a call's `(`
  that is not the first token. That last condition is what separates
  `[foo<T>()]` from `[(e)]`, a parenthesised reference, which is legal.
  Every legal key was probed and none matches — a string or number
  literal, a bare identifier over a `unique symbol`, a dotted const-enum
  reference, a template literal, a well-known symbol. The rule is
  interface / type-literal ONLY: a CLASS computed key and an OBJECT
  LITERAL computed key both take an arbitrary expression
  (`class C { ["" + ""]() {} }` is clean tsc), so it is deliberately not
  recorded from the class member parser.
- **TS1046 for namespaces** (2 of 3 files). `check_dts_top_level_modifiers`
  already existed and already flagged functions, enums, classes, variables
  and executable statements — and skipped NAMESPACES, so
  `parserModuleDeclaration{2,4}.d` sat as MISSes against a check written
  for exactly them. Eleventh instance of a rule applied to some of the
  forms it names.

  Opening it exposed a TWELFTH instance in the same family, one layer
  down, and this one was a false positive aimed at the PRODUCT rather than
  a missing diagnostic: `export namespace X { }` recorded no
  `<export-value>` marker, while every other exported declaration kind
  (function, enum, class, variable) does. So an exported namespace read as
  un-exported and TS1046 flagged it — and `export namespace` is ordinary
  @types shape, which is the bridge's primary input. The conformance gate
  could not see it (the corpus has almost no `.d.ts` files); the UNIT TEST
  written for the new namespace arm did, on its second assertion. Fixed
  where the model says it belongs — an exported namespace IS an exported
  value — rather than with a namespace-only marker, and measured: the
  oracle is byte-identical at TP 2383 / FP 0, so widening that channel had
  no blast radius on the corpus.

  Two premises were checked rather than assumed while fixing it, because
  the comment written first asserted one of them. `module_.namespaces` does
  hold ONLY the top level (`namespace M { namespace M1 { } }` in a .d.ts
  reports one issue, not two), so an ambient outer namespace exempts its
  children for free. And the failing assertion was identified by RUNNING
  each form through the real `.d.ts` path — `declare` 0, `export` 1,
  bare 1, `declare global` 0 — not by counting characters in the failure
  span, which had pointed at the wrong line. `parserModuleDeclaration1.d` (`module "Foo" { }`) stays
  a MISS: a QUOTED specifier arrives through `module_augmentations`, which
  carries no `declare` flag, so telling `module "Foo" {}` from
  `declare module "Foo" {}` needs a new channel for one file.
- **TS1132** — an enum member is expected after a comma (1 file). A
  TRAILING comma is legal and cannot reach the check, because the
  separator after a parsed member is consumed at the bottom of the member
  loop and the next iteration sees `}`; a comma reaching the TOP of the
  loop never had a member before it. Only the comma: `enum E { A; B }` is
  TS1357, a different rule.

Measured while chasing a suspected regression in this batch, and worth
recording because it is NOT one: `tscheck` on
`typescript/src/compiler/checker.ts` (54,434 lines) splits **268 ms parse /
45,392 ms check** in a release build — the checker spends 170x the parser's
time on one file, and the full `moon test` sweep of `typescript/src` in a
DEBUG build is what makes the checker whitebox test run for tens of
minutes.

That it is not a regression from this round was settled by A/B rather than
by argument: the pre-batch commit built in a git worktree gives **45,327 ms
on checker.ts against 44,243 ms** for the current tree — identical within
noise. Two hypotheses were offered before that measurement and both were
wrong. A quadratic in `record_suppressible_grammar_misuse`, whose
`grammar_misuses.contains(…)` scan runs per recorded misuse: checker.ts
records ZERO grammar misuses. And the 64-token lookahead the computed-key
rule adds per bracket-headed member: `peek_at` is O(1) and the whole parse
half is 268 ms. The checker's own cost on large single files is unmeasured
beyond this data point and is a separate question from conformance recall.

DEFERRED from this batch, with the reason: **TS1063** (`export =` inside a
namespace, 1 file) needs a namespace-depth counter the parser does not
have. **TS1338** (`infer` outside an `extends` clause, 2 files) needs
conditional-type context tracking, and both target files are large and
dominated by TS2322 / TS2344 anyway.

Batch BW (2026-09-01): TP 2360 -> 2373, MISS 374 -> 361, FP / PFLEGAL 0.
Thirteen more files, and the batch's own boundary probes are the substance
of it — every rule below has its LEGAL neighbour recorded next to it,
because "fires on the corpus file" and "does not fire on the legal
spelling" are two different claims and only the second one is what keeps
the gate at zero.

- **TS1051 / TS1052 / TS1053 / TS1094 / TS1095** — the `set` accessor
  family (5 files): a parameter with an initializer, an optional
  parameter, a rest parameter, a return-type annotation, and (for BOTH
  accessor kinds) a type-parameter list. `set F(v: number)`,
  `get F(): number` and `set F(v,)` are the legal neighbours and stay
  silent.
- **TS1016 / TS1047** — parameter-list rules (3 files), recorded in
  `parse_params`, the ONE site every parameter list goes through, so a
  method, a plain function, a constructor and an arrow are covered by
  construction rather than by four copies. Two legal neighbours matter
  here and a naive reading gets both wrong: a DEFAULT does not make a
  parameter optional for TS1016 (`f(a = 1, b)` is legal tsc) and a REST
  after an optional is fine (`f(a?, ...b)`).
- **TS1064** — an `async` function's return annotation (2 of 4 files).
  The rule is nearly syntactic — tsc requires the GLOBAL `Promise<T>`, so
  even `PromiseLike<void>` and a `Promise` SUBCLASS are errors — but a
  type ALIAS to `Promise<void>` is legal, and the alias and the subclass
  are the same named-annotation node at parse time. Every named
  annotation therefore abstains, which costs the two
  `asyncQualifiedReturnType` files (`X.MyPromise<void>` stays a MISS) and
  is the right direction for a 0-FP gate. Deciding those two needs the
  declaration table (a name declared in-file as a class or interface
  cannot be an alias) and is filed, not built.
- **TS1013** — a rest element with a trailing comma (1 file), binding
  patterns only. The PARAMETER form is deliberately not implemented:
  `declare function f(...a,)` is ACCEPTED by tsc in an ambient
  declaration, and the parser cannot express that exemption (see the
  TS1212 note below for the same blocker). The binding-pattern form has
  no ambient spelling, so it needs no exemption.
- **TS1097** — an empty `extends` / `implements` list (2 files). Tested as
  "the body `{` opens immediately" rather than as "the collected name list
  came back empty", because an empty list is ALSO what the collector
  returns for a legal form it cannot spell (`interface I extends
  import("m").T`), and blaming the author for a gap in the collector is a
  false positive by construction.

The round's one false positive is the reason the async rule has an
`is_generator` parameter: `types.asyncGenerators.es2018.1.ts` is
TS7-ACCEPTED, an `async function*` returns `AsyncGenerator<Y, R, N>` rather
than a promise, and the rule does not apply to it at all. Caught by the
gate on the first run, before the batch landed.

Batch BV (2026-09-01): TP 2346 -> 2360, MISS 388 -> 374, FP / PFLEGAL 0.
Fourteen files, two clusters, and one instructive failure in the middle.

- **Constructor cluster** (6 files): `static` / `async` / `override` on a
  constructor is TS1089, a type-parameter list is TS1092 (an EMPTY one,
  `constructor<>()`, is additionally TS1098 — so the check has to ask
  whether a list was WRITTEN, not whether it produced names), and a
  return-type annotation is TS1093 for every annotation including `void`.
  Accessibility modifiers are deliberately absent from the list: tsc
  accepts `private constructor()`, the singleton idiom. `abstract` and
  `readonly` are errors too but under their own codes (TS1242 / TS1024)
  and are left alone — a check that reports the wrong rule is worse than
  no check.
- **Index-signature cluster** (8 files): TS1017 (rest parameter), TS1019
  (question mark), TS1021 (no value annotation), TS1096 (not exactly one
  parameter), TS1268 (parameter type not `string` / `number` / `symbol` /
  template literal).

The instructive part: the first draft wrote the index-signature rules
INLINE in the type-literal member parser and won **2 of the 8** files.
A type literal (`type R = { … }`) and an interface body are parsed by two
near-duplicate member loops in different files, so `{ [k: any]: V }` was
checked and the identical `interface I { [k: any]: V }` was not — the same
family this file has recorded ten times, caught here by the corpus rather
than by reading. The rules are three shared helpers now
(`record_index_signature_shape_misuse` /
`_key_misuse` / `_missing_annotation`) called from both loops, and the
unit test asserts every shape in BOTH spellings so a future edit cannot
regress one and still pass.

TS1268 is decided by a DENYLIST of the primitives tsc rejects rather than
by the complement of the four it accepts, and the reason is a genuine
ambiguity rather than caution: `type K = string; { [k: K]: V }` is LEGAL
and `{ [k: RegExp]: V }` is TS1268, and both are the same named-type node
here. Abstaining on every named type costs `RegExp` (a MISS) and keeps the
alias (no FP). Unions abstain too (`{ [k: string | number]: V }` is
legal), and a literal key is a different rule entirely (TS1337).

Batch BU (2026-09-01): TP 2337 -> 2346, MISS 397 -> 388, FP / PFLEGAL 0.
Nine files, three rules, and the first one was a BUG before it was a recall
item:

- **TS1100** (`eval` / `arguments` as an assignment target, 4 files).
  JavaScript spells that target four ways — `eval = 1`, `eval += 1`,
  `++eval`, `eval++` — and the rule had been written twice, at the two
  assignment spellings, with nothing at either update. `"use strict";
  eval++` parsed clean. Tenth instance in this repo of one rule written in
  several places and applied in some, so the fix is one helper
  (`record_assign_target_strict_misuse`) called from all four rather than a
  third and fourth copy. The strict gate came off as well: tsc reports
  TS1100 for `eval = 1` in a plain script with no prologue and no flag
  (probed), and the oracle errors on both `-negative` files, so the gate was
  silencing half the corpus cases on top of the missing spellings. Ambient
  declarations are the one exemption tsc makes
  (`declare function f(eval: number)` is clean) and are unreachable from an
  assignment position; BINDING positions keep their own gate.
- **TS1101** (`with` statement, 3 files — including
  `arrowFunctionContexts`, which the bucket labels could not name because it
  has no TS6 `.errors.txt`). Unconditional: TypeScript rejects `with` in
  every configuration.
- **TS1114** (duplicate label, 2 files). `self.labels` was already scoped
  exactly the way the rule is — pushed on entering the labelled statement,
  popped on leaving, and saved/cleared/restored at every function-body parse
  site — so the check is one `contains`. The two TS7-ACCEPTED neighbours
  prove it rather than merely not-contradict it: sequential labels
  (`duplicateLabel4`) and a re-use inside a nested function
  (`duplicateLabel3`) both stay clean.

The `with` rule found the one false positive in the round, and it is worth
recording because it is a general constraint on every grammar check added
from here: `topLevelVarHoistingCommonJS.ts` is TS7-ACCEPTED and its
`with (_)` is preceded by `// @ts-ignore`. Our issues carry no line
positions, so file granularity is the only FP-safe reading — the same choice
the TS2465 / TS1166 family already made — and both new statement-level rules
go through `record_suppressible_grammar_misuse`.

Two tooling defects came with the round, both of the "my own harness was
lying to me" kind this file keeps recording. The oracle preferred the
RELEASE binary unconditionally and printed nothing about its choice, while
`just verify-checker-soundness` builds DEBUG — so a release binary left from
an earlier session silently won, and six target files "did not change"
because the harness was running code from before the change. It picks the
newer build now and prints which. CI never saw it: a fresh checkout has
neither binary until the recipe builds one, which is exactly why it
survived. And `moon check --deny-warn` cannot be used as a gate here at all
(451+ pre-existing warnings); plain `moon check` with `0 errors` is the
check.

DEFERRED with the reason, not attempted: **TS1212 / TS1213** (reserved word
as a binding name). All nine strict-reserved words are TS1212 even in a
sloppy script (probed), and the existing gate at
`parse_binding_pattern` covers only three (`interface` / `let` / `yield`);
adding the other six would win 2 files (`parser642331`, `parser642331_1`).
It is NOT worth it yet, for a product reason rather than a corpus one:
`declare function f(static: number)` is clean in tsc and
`function f(static: number)` is TS1212, so the rule needs an ambient
exemption the parser cannot currently express (`in_ambient_module` is a
whole-parse mode; there is no per-declaration flag), and getting it wrong
false-flags npm `.d.ts` files — the bridge's primary input. Two files
against a new FP channel in the product is the wrong trade. The corpus
itself carries no counter-example: the one accepted file matching a
reserved-word binding (`parserSyntaxWalker.generated.ts`) has all its
matches inside comments.

Also deferred: **TS1115** (`continue` to a non-iteration label, 1 file).
Needs iteration-ness per label, which `self.labels` does not carry, and
adding a parallel stack means mirroring the save/clear/restore at 12+ parse
sites — the exact shape of the bug family above. The right implementation is
a post-parse AST walk over `Label(name, body)` / `Continue(Some(name))`,
which is ~40 lines for one file; worth doing after the cheaper buckets.

## TS Checker Conformance (2026-07-17 — TypeScript 7, superseded above)

react joined the real-world gate as the 21st package (2026-07-18):
`package|react|react|` resolves types through @types/react, the bridge
emits a 3,898-line surface (83 types / 58 functions / 117 structs), and
the smoke tests exercise createElement / isValidElement / createRef /
version end-to-end on react@19.2.4 (both the in-package test and the
build-smoke main). Budgets calibrated from measured metrics (JSValue
functions 30, cause split 129|43|8|24|34|14|6, unsupported exports 0);
policy budgeted-fallback alongside preact until a dedicated
JSX/component binding layer exists.

JSX/component layer v1 (2026-07-19): a MoonBit closure IS a React
function component at runtime, and the generated react bridge now ships
the glue to use it typed. When the module spec is exactly `react`, the
ffi emits `element_of_component[Props]((Props) -> JSValue, Props?,
Array[JSValue]) -> JSValue` (React.createElement over a MoonBit
closure) and `use_state_typed[S](S) -> (S, (S) -> Unit)` (useState as a
generically-typed value/setter pair; the setter re-enters React through
the captured dispatch). Proven end-to-end in the gate: a counter
component defined entirely in MoonBit -- `use_state_typed(41)` +
`createElement("div", ...)` -- mounts via `element_of_component` and
`react-dom/server`'s renderToString returns `<div>41</div>`. The
injected layer adds zero JSValue-metric regressions (react budgets
unchanged); react's fallback policy note now records the layer.
Remaining for v2: typed intrinsic-element props (attribute structs),
useEffect/useReducer typed wrappers, preact parity, and a react-dom
corpus entry. Oracle unchanged (TP 2338 / FP 0 / TN 1750).

Flagship-callable round (2026-07-19): three surface gaps closed and ws
joins the gate (42 packages + 10 node builtins = 52 entries). (a) ws
interop: cjs-module-lexer misses CJS alias re-exports, so the glue's
named class bindings now fall back through sibling aliases of the same
runtime entity -- statically-known siblings from the export surface
plus `const Y: typeof X` value aliases (`const Server =
__ts_mbt_module.Server ?? __ts_mbt_module.WebSocketServer`); a
noServer WebSocketServer constructs and closes from MoonBit. (b) Call
signatures on VALUE exports surface as callable module functions: the
richest `<call>` signature of a const's inline object type or Named
interface emits under the export's own name --
`minimatch("bar.foo", "*.foo", None) -> Bool` and chalk's
`default(...) -> String` now work directly. (c) Overload variants that
differ only in RETURN type survive wrapper emission: the base-signature
skip compares against the export's actual base (not `preferred[0]`),
the "wider" disqualifier only applies against same-return picks, and
`undefined`-typed parameter slots get a suffix -- uuid's `v4():
string` emits as `v4_version4_options_optional_undefined_number_optional`
and generates+validates a real v4 at smoke time. The broader
push_preferred collapse stays param-count-keyed (loosening it regressed
the React fixture's namespace-member naturalization). Budgets
recalibrated for uuid / valibot / immer / superstruct / lodash.
Oracle unchanged (TP 2338 / FP 0 / TN 1750); moon test 2523/2523.

Top-download expansion (2026-07-19): eight of npm's most-downloaded
packages verified end-to-end and added to the real-world gate (41
packages + 10 node builtins = 51 entries): axios (getUri asserted
against baseURL+url config), commander (option parse --debug ->
opts.debug), debug (enable/enabled/disable + logger factory), chokidar
(FSWatcher construct + close), pino (logger level from options),
lodash (camelCase / kebabCase / chunk -- 435 declared functions from
the fixed reference-following + value-interface surface), uuid
(validate / version after the glue fix), minimatch (filter matcher
after the segfault fix). ws deferred: cjs-module-lexer does not expose
its `Server` alias as an ESM named export, so the generated static
binding is undefined at runtime -- needs interop-tolerant class
bindings (same family as the node:* tolerance) before it can join.
rxjs / ajv / undici structurally healthy (method-surface heavy),
queued as budgeted-fallback candidates.

Default-export / export= naturalization (2026-07-18): the two
structural gaps behind the probe's weak surfaces are fixed and the
corpus grew to 33 packages. (a) Module resolver: a raw `.js` "main"
no longer shadows tsc's implicit package-root `index.d.ts` lookup in
Types mode (deepmerge ships index.d.ts with `"main": "dist/cjs.js"`
and no `types` field -- the whole declaration surface was erased);
resolution now retries declaration-ish results first, then root
index.d.ts, then the raw script as last resort. (b) Export semantics:
`TsModuleBlock.has_export_equals` records CJS `export =`, and
`resolve_imported_binding_export` forwards a namespace import binding
(`import X = require("./sub")` / `import * as X`) through the target's
`default` export when the target uses `export =` -- X IS the assigned
entity, so `export { X as valid }` re-export chains (@types/semver's 42
per-function files, @types/picomatch) now surface callable typed
functions instead of `get_*() -> JSValue` getters. Results: semver 97
callable externs (valid/clean/major smoke-tested), picomatch callable
`default(glob) -> Matcher` (match/non-match smoke), deepmerge callable
`default` merge (both-keys smoke) -- all three added to the gate with
calibrated budgets (33 packages + 10 builtins = 43 entries green).
Oracle unchanged (TP 2338 / FP 0 / TN 1750), moon test 2523/2523.

Corpus expansion round 2 (2026-07-18): nine more npm packages verified
end-to-end and added to the real-world gate (30 packages + 10 node
builtins now): ms, nanoid, dayjs, qs, yaml, superstruct, eventemitter3,
mitt, marked -- each with a runtime bridge smoke that calls a real API
and asserts the result (ms "1m", nanoid length, dayjs format, qs
parse/stringify, yaml roundtrip, superstruct assert/validate,
eventemitter3 on/listenerCount, mitt on/emit handler count, marked
"# hello" -> <h1>). Two real-package bugs found by the probe and fixed:
(a) parser -- `export default function mitt<T>(...): U;` (bodiless named
default in a .d.ts) crashed the module-block path at the missing `{`;
named defaults now route through the declaration parser like the
checker path already did; (b) bridge -- the .mbti fn-decl line parser
used `rev_find(")")` for the parameter-list close paren, which grabs the
RETURN type's paren when a value getter has a curried function type
(marked's `get_use_` emitted unparseable MoonBit); it now depth-scans to
the paren matching the open. Probe leftovers documented: semver / 
picomatch / deepmerge surface as JSValue-only or empty (default-export
function naturalization gap), tracked as a future bridge target. Oracle
unchanged (TP 2338 / FP 0 / TN 1750); corpus react pin moved to 19.2.7
(react-router peer floor).

Batch BX (2026-07-18): @types/react@19.2.17 audit — 13/13 files parse
clean and the declaration bodies check clean; the only reports were
TS2307 module-resolution complaints for imports that DO resolve on disk
(`csstype` is a declared dependency of @types/react, `./` is the
package-root self-import in jsx-runtime). tscheck now resolves module
specifiers against the filesystem for files living under node_modules
(relative specs probe the usual `.d.ts` / `index.d.ts` candidates; bare
specs walk up to `node_modules/<pkg>` / `node_modules/@types/<pkg>`)
and suppresses TS2307 when the import resolves. Conformance corpora
live outside node_modules, so the oracle is unchanged (TP 2338 / FP 0 /
TN 1750); truly-missing modules inside node_modules are still flagged
(verified by negative control). All three real-world declaration
surfaces are now fully clean: lib.d.ts 108/108, @types/node 88/88,
@types/react 13/13. `ts2mbt decl` emits a 3,135-line MoonBit surface
from @types/react (useState and the hook family included). The
rwcorpus package.json now pins every gate package (plus @types/react
and @types/express) so `npm install` no longer prunes them.

Batch BW (2026-07-17): lib.d.ts / @types/node checker issues driven to
ZERO — 108/108 lib files and 88/88 @types/node files check fully clean.
Fixes: (a) the type-param-arity check learned MINIMUM arity — the parser
records `<generic-min-arity>NAME=K` (leading params without a default)
at every generic declaration site, ambient `declare module` / `declare
global` sub-parses propagate the suppression-only sentinels to the outer
module (they were parsed by a fresh Parser and lost), and `check_arity`
flags under-application only below the minimum (`Iterable<T, TReturn =
any, TNext = any>` legally takes 1..3 args; TokenForOptions likewise) —
this replaced an unsound exact-arity rule that also cost 4 lucky TPs
(conditionalTypes1 / inferTypes1 / recursiveMappedTypes /
varianceAnnotations under-apply LEGALLY and were flagged for the wrong
reason; TP 2342 -> 2338, FP still 0); (b) interface accessor syntax
(TS 5.4 `get x(): T` in interfaces, lib.es2024/lib.dom) parses as a
readonly-property pair; (c) interface-extends member compat exempts
generic methods (CallableFunction.call), covariant Named returns via the
extends chain (getElementById), optional-over-required when the derived
member is `any` (BeforeUnloadEvent.returnValue), optional-method
overload duplicates (Process.send), and tuple members whose elements
narrow covariantly through the extends chain (http2
ClientHttp2SessionEventMap `stream`: ClientHttp2Stream extends
Http2Stream); (d) TS2307 abstains in `declare global` bundles
(fetch/streams/undici-types) and for node builtin subpaths
(`stream/web`); (e) arity check tolerates type-param defaults declared
only via merged declarations (min across duplicates).

Batch BV (2026-07-17): driving the BU-audit residuals down —
lib.d.ts 569 -> 14 issues (103/108 files clean), @types/node 41 -> 14
(80/88 clean); oracle unchanged (TP 2342 / FP 0 / TN 1750). Fixes:
(a) interface-extends member compat now skips OVERLOADED members —
tsc compares the whole overload set, and the pairwise entry comparison
misfired 464 times on lib.dom's `addEventListener` specialization
pattern alone; (b) `check_type_undeclared_tps` skips callable members
of object-literal types (the parser discards signature-level type
params there — Process.finalization's `register<T>`), and accumulates
method type params across ALL same-name overload entries instead of
letting the last overload win (lib.dom `querySelector<K>`/`<E>`);
(c) TS2307 abstains for `node:*` / classic Node builtin specifiers and
inside ambient-module declaration bundles. Remaining residuals (28
total): timers' `RefCounted` cross-scope refs, lib.dom accessor-pair
`get`/`set` duplicate-identifier misparse, type-param DEFAULTS in the
arity check (TokenForOptions), CallableFunction/Function member compat,
undici-types cross-package import.

Batch BU (2026-07-17): full-surface parse audit of `typescript@6.0.3`
`lib*.d.ts` (108 files) and `@types/node@26.1.1` (88 files): 196/196
parse clean (0 parse errors); `@types/node` emits substantive decl
surfaces (fs 459 / crypto 552 / util 106 MoonBit decls), `lib.*` files
are global ambient scripts with an intentionally empty export surface.
Checker false positives found by the audit and fixed (all
`declare module "spec" { ... }` body exemptions — the parser flattens
those bodies into the parent module without ambient flags): TS1046
top-level-modifier (197 hits in fs alone), TS2564 strict-property-init
(util's MIMEType), and the trailing-void overload heuristic (crypto's
randomInt / verify). After the fixes @types/node checks 69/88 files
fully clean (41 residual issues, mostly interface-generic `T` scoping
and cross-file globals); lib.d.ts residuals concentrate in lib.dom
(482 of 569, deep DOM hierarchy modeling limits). Oracle unchanged
(TP 2342 / FP 0).

Batch BT (2026-07-17): TP 2341 -> 2342, MISS 393 -> 392, FP / PFLEGAL
still 0. Class-expression member bodies no longer inherit control-flow
narrowing: the parser lowers `class { ... }` expressions to a `<class>`
IIFE, and `check_funcexpr_with_context` now rebinds captured variables at
their DECLARED types for that marker — class members execute after the
guard region, so tsc does not narrow into them (typeGuardInClass).

Batch BS (2026-07-17): TP 2338 -> 2341, MISS 396 -> 393, FP / PFLEGAL
still 0. Mining the TS2322 cluster (30 files, 17 single-code): (a) a
concrete primitive assigned to an opaque generic indexed access
(`tp: T[P]; tp = s`) is always TS2322 — matches both the raw
`IndexedAccess(Named(T), _)` annotation and the bound-substituted
`IndexedAccess(_, Keyof(...))` shape parameter registration produces
(nonPrimitiveConstraintOfIndexAccessType); (b) `x: T & U` with
union-of-primitive constraints is bounded by the member-set intersection
of the bounds — a target union missing one of the members rejects it
(intersectionWithUnionConstraint, plus one multi-code file). Assessment
of the remaining TS2322 files: functionExpressionContextualTyping2 /
contextuallyTypeCommaOperator02 / typeGuardInClass (class-expression
narrowing reset) / callChain.3 / objectLiteralNormalization /
typeFromPropertyAssignment31 look feasible next; generatorTypeCheck8
(iterator protocol compat), symbolProperty46 (symbol-keyed accessors),
conditionalTypesExcessProperties, templateLiteralTypes7 need deeper
machinery.

Batch BR (2026-07-17): TP 2333 -> 2338, MISS 401 -> 396, FP / PFLEGAL
still 0. Bodiless generator declarations (`declare namespace M {
function *g(): any }`, generator overload signatures, bodiless `*m()`
class methods) are always-error grammar misuses recorded at parse time
(generatorInAmbientContext2/4.d, generatorOverloads1/2/3);
`Constructor(...)` joined `is_definitely_not_callable` (a
construct-signature value called without `new` is TS2348 — inference
doesn't reach it for the remaining corpus cases yet, but the predicate
is sound). Remaining 396 MISS is a long tail (top cluster TS2322 at 30,
71 files with TS7-only baselines).

## TS Checker Conformance (current state, 2026-07-12, superseded above — TypeScript 7)

The oracle now correlates against **TypeScript 7** (typescript-go
v7.0.2). Truth comes from vendored name manifests
(`scripts/ts7_baselines/`, see its README); case files are the
`typescript` submodule at typescript-go's `_submodules/TypeScript` pin
(`4d4f005c`). TS7 removed the ES3/ES5 targets — every `target=es5/es3`
variant is NOTRUN, and the TS6-era deprecated-compiler-option
diagnostics (TS5107/TS5101) were removed from the checker accordingly.

State: whole-corpus **TP 2335 / FP 0 / PFLEGAL 0 / TN 1750 / MISS 399 /
NOTRUN 14** via `scripts/checker_conformance_oracle.sh --max-fp 0
--max-legal-parsefail 0`. Batch BR emptied the legal-parse-failure
budget (decoratorOnClass3, defaultExportWithOverloads01, parser768531)
and the gate now enforces 0.

Batch BE (TS7-only miss mining, +51 TP) worked the misses newly exposed
by the oracle switch:
- TS5102: `downlevelIteration` was REMOVED in TS7 — its presence-based
  recording now surfaces as an error (every ran conformance case
  carrying the directive errors under tsgo; none is accepted).
- TS2378: a class `get` accessor whose body contains NO return, throw,
  or loop must return a value (empty bodies parse as `body: None`;
  ambient / abstract accessors and any explicit `return;` abstain — a
  written `(): any` is indistinguishable from no annotation).
- TS1206: decorators on constructors flag in both modes; on `abstract` /
  `declare` members only under STANDARD decorators (legacy mode accepts
  them — decoratorInAmbientContext); parameter decorators flag only
  without `@experimentaldecorators` and only when the decorator chain's
  last follower is not `class` (a paren'd decorated class expression
  enters the arrow-params trial — esDecorators-classExpression-*).
- TS2373/TS2372: a parameter default (or binding-pattern computed key /
  element default, or class-expression heritage inside one) may not
  reference the parameter itself, a later parameter, or a body-declared
  name (`var` hoisted anywhere, `let`/`const` top-level). Nested
  callables defer evaluation and abstain. Covers module functions,
  class constructors/methods, top-level callable initializers, and
  IIFE arrows.
Sweep round-trip: the first BE sweep surfaced 10 FPs (bare-return
getters, legacy-mode ambient decorators, stacked decorators before
class expressions); all root-caused and fixed before landing.
Batch BF (+19 TP, TP 2222 / MISS 512) continued the mining:
- TS2465/TS1166: `this` in a class member's computed property name
  (direct refs only — nested callables rebind), and computed FIELD keys
  through a declared-`any` call (no literal type — autoAccessor5).
  Whole-file abstention when the source carries `@ts-ignore` /
  `@ts-expect-error` (the parser pushes a `<ts-suppression-present>`
  marker; our issues aren't line-anchored, so file granularity is the
  FP-safe choice — esDecorators-classDeclaration-outerThisReference).
- TS1125/TS1198: `\u{...}` escapes in STRING literals — missing /
  non-hex digits and values past 0x10FFFF (accumulator clamped against
  32-bit wrap). Template literals deliberately NOT counted: tagged
  templates accept invalid escapes (ES2018) and the lexer can't see
  taggedness.
- TS1121: legacy octal integer literals (`01`).
Batch BG (+11 TP, TP 2233 / MISS 501) closed the escape-sequence
remainder:
- Regex `\u{...}` under the `u` / `v` flags: `scan_regex` collects the
  body and `validate_regex_unicode_escapes` requires hex digits and a
  value within 0x0..0x10FFFF (accumulator clamped against 32-bit wrap).
  Without the flag, `\u{2}` is a quantified `u` and stays legal.
- Untagged-template invalid `\u` / `\x` escapes (incl. overflow): the
  lexer records each escape's source position in
  `template_invalid_escape_positions`; the parser counts entries inside
  the Template token's span at the UNTAGGED primary parse site only —
  tagged templates accept invalid escapes (ES2018) and parse through
  the postfix path. Escapes inside `${...}` interpolation sub-parses
  are lost (sub-parser array discarded) — a known miss, not an FP.
- Strings additionally validate `\x` (exactly two hex digits).
Batch BH (+9 TP, TP 2242 / MISS 492) implemented TS2683 —
implicit-any `this` — as a dedicated context-tracking walker
(`check_implicit_any_this` + `ts2683_walk_expr/stmts`):
- IMPLICIT contexts: plain function declarations/expressions without a
  `this` parameter (including ones nested in methods and static-field
  initializer function exprs), namespace top-level statements (a
  namespace body is an IIFE), and class-declaration decorators inside
  namespaces.
- TYPED/EXEMPT contexts: methods/accessors/constructors at their top
  level, arrows (inherit), object-literal FUNCTION values (contextual),
  function exprs in CALL-ARGUMENT position (callee may declare `this` —
  esDecorators-contextualTypes.2), property/index/compound-assignment
  RHS (`Element.prototype.remove ??= function () {…}` —
  thisPrototypeMethodCompoundAssignment), ANNOTATED binding
  initializers, `<class>`-named IIFE lowerings of class expressions,
  true top level (`globalThis`), and `this`-parameter functions.
- Opt-outs: `@noImplicitThis: false` (new `<noimplicitthis-off>`
  marker), `@strict: false`, and the `@ts-ignore` whole-file marker.
Permissive-path only. One stale wbtest pin (`this` in a method-nested
function expr expected 0) was updated to the TS7 verdict.
Batch BI (+24 TP, TP 2266 / MISS 468) took the small syntactic
clusters from the general miss pool:
- TS1049/TS1054: a `set` accessor takes exactly one parameter, a `get`
  accessor none — recorded at the parse sites for both object-literal
  accessors (both parse paths) and class accessors.
- TS1031: `export` / `declare` cannot modify class elements (incl.
  `declare constructor`). The `export` arm consumes the token only in
  MODIFIER position via `can_consume_class_modifier` — `class C {
  export; }` declares a field NAMED export
  (propertyNamesOfReservedWords went PFLEGAL until guarded).
- TS1124: a numeric exponent needs at least one digit (`1e`, `1e+`).
- TS2466: `super` cannot be referenced in a computed property name —
  member chains and `super()` inside comma chains
  (computedPropertyNames24/27). computedPropertyNames30 stays a MISS:
  strada raises TS2466 for `this` in an object-literal computed key
  inside a typed constructor arrow, which our typed-context model
  deliberately treats as legal.
Batch BJ (+12 TP, TP 2278 / MISS 456) took the TS2454/TS2488/TS2403
type clusters:
- ASI vs declaration heads: `namespace` / `module` head a declaration
  only when the NAME sits on the same line (`is_namespace_decl_start`
  rejects a newline-separated follower), and a statement-level `declare`
  with a line break after it is a plain identifier reference (TS's
  modifier ASI rule). `namespace\nn\n{}` is then three statements whose
  reads hit the existing TS2454 unassigned tracking
  (asiPreventsParsingAsNamespace01/02,
  asiPreventsParsingAsAmbientExternalModule01).
- TS2488 beyond class instances (`check_forof_non_iterable`): a for-of
  source that is a non-iterable primitive (`for (const v of 0)`), a
  union with a non-iterable primitive member (`string | number`), or an
  object type whose `[Symbol.iterator]` member is OPTIONAL; plus an
  array-destructuring pattern over a primitive element type
  (`for (var [a = 0] of [2, 3])`, syntactic array-literal sources only).
  The optional-iterator case rides a new parser encoding: STANDARD
  well-known `[Symbol.x]` keys in object-type literals parse as `@@x`
  members instead of degrading the whole literal to `any`
  (user-augmented `Symbol.foo` keys keep the legacy fallback —
  symbolProperty61 FP'd until restricted).
- TS2403 vs lib declarations (`check_lib_global_redeclaration`): a
  script-level initializer-less `var` redeclaring a runtime global
  (`var Symbol: any` / `{ iterator: string }`) must carry the matching
  `*Constructor` interface annotation; module files and `typeof`
  annotations abstain (ES5SymbolProperty3/4/7 vs ES5SymbolProperty1).
Batch BK (+11 TP, TP 2289 / MISS 445) mixed scoping, parser-recovery,
and call-modeling slices:
- Block scoping in the TS2304 hoisting backstop: a `let` / `const`
  for-of/for-in head is LOOP-scoped (only `var` heads hoist —
  for-of7), and an assign-form loop's body contributes only `var`s
  (`for (v of xs) { let v; }` cannot declare the head — for-of6).
  Closures inside the loop still see the head binding via the env walk.
- `new Date<A;`: type arguments are only consumed when a balanced `>`
  exists; otherwise the cursor restores and `<` parses as a comparison,
  so `A` surfaces through the normal undefined-name path
  (parserConstructorAmbiguity1/2/4).
- TS2345: `f.apply(x, arguments)` where `f` is a zero-parameter
  function — `IArguments` is never assignable to the empty tuple `[]`
  (asyncArrowFunctionCapturesArguments_es5/es6/es2017). Functions WITH
  parameters abstain.
- TS1005: reserved-word and literal object-binding shorthands need a
  `: alias` (`var { while } = …`, `var { "while" } = …` —
  objectBindingPatternKeywordIdentifiers01/03), and `void` cannot head
  a qualified type name (`var v: void.x` — parservoidInQualifiedName1).
Batch BL (+7 TP, TP 2296 / MISS 438) worked the TS2339 cluster:
- Object patterns over PRIMITIVE for-of elements flag their props
  (`for (var {x: a = 0} of [2, 3])` — ES5For-of27/29; prototype members
  like `toString` stay legal), mirroring BJ's array-pattern TS2488.
- An object sub-pattern under a REST element draws its keys from the
  array surface: non-numeric keys outside `array_prototype_member` (+ a
  small always-legal extra set) flag on Array/Tuple sources, in both
  declaration and assignment forms (restElementWithBindingPattern2,
  restElementWithAssignmentPattern2/4).
- The pattern-vs-object-literal key check (parser AND checker copies)
  now folds spreads of syntactic object literals recursively instead of
  abstaining (`const { g } = { ...{ ...{ c: 0 } } , f: 0 }` —
  destructuringSpread); getter/setter entries provide their names.
- `new SharedArrayBuffer(...)` keeps its Named type, the instance table
  gained the ES2024 members (`growable` / `maxByteLength` / `grow`, and
  ArrayBuffer's `resizable` / `detached` / `resize`), and the surface
  registers as fully modeled so member misses are definite
  (`sab.length` — useSharedArrayBuffer6).
Batch BM (+9 TP, TP 2305 / MISS 429) took lib-set directives,
decorator signatures, and generator interface returns:
- TS2318 via parser markers: `@noLib: true` removes every required
  global type (parser509698); an explicit `@lib:` list without a
  full-year ES2015+ lib / `es2015.iterable` lacks `IterableIterator`
  for generators (generatorReturnTypeFallback.2, types.forAwait); one
  without `esnext` lacks `Disposable` for `using` declarations
  (usingDeclarations.9 / awaitUsingDeclarations.9 — the block-scoped
  `using` lowering records the marker too).
- TS1238 (`check_class_decorator_signatures`): a CLASS used as a class
  decorator is not callable (constructableDecoratorOnClass01); a
  decorator or factory result whose REQUIRED arity exceeds the runtime
  invocation (1 arg legacy / 2 standard, `<experimental-decorators>`
  marker) can never resolve (decoratorOnClass8, esDecorators-arguments).
  Zero-parameter decorators also error in tsc but are deliberately
  skipped. The parser now captures class decorators BEFORE the body
  parse — member decorators share `pending_decorators` and previously
  either leaked onto the next declaration or (after the first fix)
  masqueraded as class decorators (decoratorOnClassAccessor1 FP'd, and
  the base-less IIFE route plus `parse_class_stub` never attached them
  at all).
- TS2741 (`check_generator_interface_returns`): a generator whose
  declared return type is an interface extending
  Iterator/IterableIterator/Generator with extra REQUIRED members can
  never satisfy it (generatorTypeCheck7); optional extras abstain.
Batch BN (+6 TP, TP 2311 / MISS 423) took index keys and lib-era
signatures:
- TS7053: a string-literal key indexing a fully-literal-keyed object
  shape that provably lacks it, gated on the module's `noImplicitAny`
  (threaded through a new `Resolver.no_implicit_any` flag). Numeric
  keys fold (`0b11010:` provides `26`), and since OUR lexer folds
  OVERFLOWING binary/octal literals through a 32-bit wrap while tsc
  folds to `Infinity`/exponent form, fold-shaped queries abstain when
  any >9-digit folded key exists — `"0b11010"` contains `b` (never a
  fold) and stays decidable (binaryIntegerLiteral/ES6,
  octalIntegerLiteral/ES6).
- TS2464: `Symbol.keyFor` is a FUNCTION on SymbolConstructor, never a
  computed property key (symbolProperty59; `Symbol.for` lexes as a
  keyword and can't reach the match arm).
- TS2554: `Date.UTC(year)` requires the month argument before es2015 —
  fires only under the `<lib-lacks-iterable>` (pre-ES2015 lib) marker
  (es5DateAPIs).
Deferred: genericRestArity/Strict need tuple-arity inference from the
handler parameter (`call<TS extends unknown[]>(handler: (...args: TS)
=> void, ...args: TS)` — expected count = 1 + handler params), which
requires threading callee type-params into the arity checker.
Batch BO (+12 TP, TP 2323 / MISS 411) continued the small clusters:
- TS2491: the left side of `for...in` is never a destructuring pattern,
  declaration or assignment form (for-inStatementsDestructuring/2/3/4,
  parserForInStatement8 — always-error, `record_unfiltered`).
- TS2854: a TOP-LEVEL `await using` requires target >= es2017 — new
  `<top-level-await-using>` and `<target-below-es2017>` parser markers
  (multi-target conformance directives list pre-es2017 variants —
  awaitUsingDeclarations.1; .2/.3 parse through other shapes and stay
  misses).
- TS2550: `Object.values` / `Object.entries` need the es2017 lib
  surface, `Atomics.waitAsync` needs es2024 — `<lib-lacks-es2017>` /
  `<lib-lacks-es2024>` markers (explicit `@lib:` lacking the year, or
  no `@lib:` with an explicit sub-es2017 `@target:`), threaded through
  new `Resolver.lib_lacks_es2017/es2024` flags to the MethodCall carve
  (useObjectValuesAndEntries2/3, es2024SharedMemory).
- TS2503: an entity-reference import alias (`import X = A.B`) whose
  ROOT is provably undeclared — `<import-eq-root>` marker, resolved
  with the same contract as `<export-eq>` (parserImportDeclaration1,
  scannerImportDeclaration1).
- TS1003-adjacent: a primitive-type keyword can never be a qualified
  type-name segment (`var v: x.void` — parservoidInQualifiedName2).
Batch BP (+6 TP, TP 2329 / MISS 405) took TS2322 subclusters and
primitive spreads:
- `SharedArrayBuffer` and `ArrayBuffer` are nominally distinct lib
  types: `var foo: ArrayBuffer = new SharedArrayBuffer(...)` flags when
  neither name has a user declaration
  (assignSharedArrayBufferToArrayBuffer).
- `new Array<T>(n)` keeps the explicit element type (`Array(T)`), so a
  mismatched declared annotation flags (parserObjectCreation1).
- TS2698: an object-literal spread of a provably non-object primitive
  (string / numeric / template-literal-typed operand) — named /
  generic / union operands abstain (spreadNonObject1,
  spreadTypeVariable as a bonus flip).
- A provably NUMERIC computed key in an object literal checks its
  value against the target interface's number index signature
  (`var o: I = { [+"foo"]: "" }` where `[s: number]: boolean` —
  computedPropertyNamesContextualType10_ES5/ES6).
Batch BQ (+6 TP, TP 2335 / MISS 399) took the TS7057 generator cluster
and the deferred genericRestArity tuple arity:
- TS7057: in a generator lacking a return-type annotation (under
  noImplicitAny), a `yield` whose RESULT is consumed with no contextual
  type — three syntactically decidable shapes: unannotated Ident
  binding (`const value = yield`), a generic call argument whose
  matching parameter is a bare type param with no explicit type args
  (`f(yield)`), and `yield yield`. Unused results, annotated bindings,
  destructuring targets, and `f<string>(yield)` abstain
  (generatorImplicitAny, generatorTypeCheck50,
  generatorReturnTypeInference + NonStrict).
- TS2554 generic-rest-tuple arity: `call<TS extends unknown[]>(handler:
  (...args: TS) => void, ...args: TS)` needs exactly 1 + handler-param
  count arguments. The parser substitutes the tuple param with its
  bound, so the carve keys on the substituted single-type-param shape
  (`(...args: unknown[]/any[]) => R` + same-bound rest) with a
  syntactic all-required arrow handler (genericRestArity,
  genericRestArityStrict). A non-generic `unknown[]`-rest signature
  abstains.
Documented dead ends from this round: YieldExpression10_es6 (an
object-literal method's name in the backstop is indistinguishable from
a legal self-referential named function expression property);
symbolProperty3/59 (need the `Symbol` VALUE modeled as
`SymbolConstructor`); computedPropertyNames9 (needs overload+generic
call inference to pick `boolean`); the TS2403 identity cluster
(spreadUnion2 / typeOfThisGeneral etc. need inferred-initializer
identity; unionTypeEquivalence needs non-reducing union identity over
subtype-related classes).
Remaining TS7-only clusters (documented, unattempted): nested
class-expression computed keys (the parser lowers class expressions to
IIFEs, erasing the member structure), TS2339 Corsa behavior changes. (Final TS6 state for reference: TP 2669 /
FP 0 / TN 1414 / MISS 414 — the TS7 renumbering reflects dropped es5
variants and Corsa behavior changes, not checker regressions; the
582 misses include ~170 new TS7-only opportunities.)

The switch surfaced and fixed four latent checker bugs that es5-variant
errors had masked (batch BD): lib-global redeclarations are never
TS2454-unassigned; parameter-property assigns follow a `super()` buried
in the using-lowering's try/finally; spreads provide properties under
getters (`@@get:` names); an EXPLICIT `: any` parameter annotation is
never TS7006 (tracked via the parser's `written_any_params` set —
`TsParam.type_` alone cannot distinguish it).

PFLEGAL budget is 3: parser768531 (fuzz), decoratorOnClass3 and
defaultExportWithOverloads01 (both TS7-accepted forms our parser
rejects — parser follow-ups).

State: whole-corpus **TP 2669 / FP 0 / PFLEGAL 1 / TN 1414** against the
TypeScript conformance baselines (`.errors.txt` = ground truth). Standing CI
gate: `scripts/checker_conformance_oracle.sh --max-fp 0
--max-legal-parsefail 1`. Session arc TP 1761 -> 2631 across PRs #191-#200.
2473 unit tests. Parse failures with an error baseline count as TP ("via
parse rejection", 397); the one budgeted legal parse failure is
parser768531 (regex/division ambiguity needs parser-fed lexer context).

### Design constraints / known dead ends (re-attempt only with design work)

- The parser ERASES constrained type params to their bounds
  (`TS extends unknown[]` -> `Array(Unknown)`) in signature positions,
  making generic and non-generic spellings indistinguishable at check time
  (genericRestArity's variadic-handler shape). Un-erasing would also unlock
  constraint-carrying inference (wrappedAndRecursiveConstraints4).
- `moon check --deny-warn` fails on ~226 PRE-EXISTING deprecated-API
  warnings from toolchain drift; `moon test --target native` is the gate.
- The `do-while` checker arm deliberately leaks body rebinds past the loop;
  back-edge widening is `while`-only for that reason.
- `block_has_value_return` counts `return undefined` as a value return —
  correct for its arrow-void consumer; generator-TReturn checks use the
  separate `generator_body_returns_value`.
- The permissive filter suppresses bare arity messages unless
  `arity_reliable` / `record_unfiltered`; new diagnostics should reuse the
  "expected `X` but got `Y`" family (reliability-classified) where possible.
- Top-level `a = b;` parses as `Expr(AssignExpr(...))`, NOT stmt-level
  `Assign` — assignment rules must be wired into BOTH arms.

### Next tasks (in order)

1. [x] symbolProperty9/10/12 — DONE (batch BC): well-known-symbol
   computed keys (`[Symbol.X]`) now parse as stable `@@X` member names in
   classes AND interfaces (types were already retained; only the name was
   erased), shorthand type members (`{ x; y }`) parse as `any`-typed named
   members instead of collapsing the annotation, and a dedicated
   `symbol_member_shape_blocks` rule compares `@@`-member OBJECT shapes
   (annotation-vs-annotation, so `any`-valued keys stay REQUIRED — the
   general member compare tolerates missing `any` fields as an
   unmodeled-inference guard and can't decide these). symbolProperty46
   (accessor: setter param inferred from paired getter return, then
   symbol-keyed INDEX-assignment lookup) remains — needs accessor pairing
   machinery.
2. [x] Object member hiding — DONE (batch BC): (a) a source member
   hiding an `Object.prototype` member with an incompatible signature
   (checked via the object_prototype_member table) blocks assignment to
   the lib `Object`; (b) bare `Object` never satisfies a callable /
   constructable target. Module-declared `Object` shadows abstain
   (pinned). All three fixtures match tsc's per-line counts.
3. [x] generatorTypeCheck31 — DONE (batch BC): an unannotated
   `function*` expression now infers its return as
   `Generator<any, any, any>` (calling a generator produces the
   generator OBJECT, not its return value), and a new rule (1b) flags a
   `Generator` / `IterableIterator` / `AsyncGenerator` source against a
   function-typed target (no call signatures). Abstains when the fixture
   declares its own `Generator` interface. Pinned legal: `.next()` on
   the synthesized return, generator IIFEs into `Iterable` slots and
   `for..of` heads. TP 2642 -> 2643, FP 0.
4. [x] mapped types with `as` clauses — DONE (batch BC), three slices:
   (a) `resolver_eval_mapped_remap` concretely evaluates a remapped
   mapped type whose source enumerates to literal keys (`keyof M` over
   an interface): per key, the remap conditional decides via
   `extends_decision`, `T[K]` resolves through `lookup_field` (NOT
   `unwrap` — `simplify_indexed_access` degrades a `Named`-based access
   to `any`, which would make every filter trivially true), `never`
   filters, literals rewrite. Wired into `unwrap`'s mapped arm; bails
   for alias-named sources (recursion guard —
   mappedTypeAsClauseRecursiveNoCrash1 stays crash-free). Unlocks
   mappedTypeAsClauses (`KeysExtendedBy<M, number>` -> `"b"`).
   (b) Rule (1c): bare `val: T` into a remapped mapped type over
   `keyof T` — pure filters (`cond ? P : never`, no `-?`) are legal,
   key RENAMES flag even under `+?`, `-?` flags always
   (mappedTypeAsClauseRelationships, all 4 sites).
   (c) Rule (1d): reading `obj[key]` through a RENAMING remap with a
   non-materializable source (type param, possibly bound-erased to
   `string`/template) can't be correlated to a checkable target
   (mappedTypeConstraints2, 4 of 5 sites; the 5th has an `any`-typed
   expected slot and abstains). Filter remaps abstain (f5/f7/validate).
   TP 2643 -> 2646, FP 0.
5. [x] Lib surface models — DONE (batch BC): the `Error` / `Date`
   prototype tables already existed in `lookup_field_core`; the gap was
   that both member-miss flag sites suppress unresolved `Named`
   receivers. Added `lib_member_surface_complete` (bare `Error` / `Date`
   only, abstaining when a module-declared interface/class merges or
   shadows) and carves at the PropAccess and MethodCall miss sites, plus
   `cause` in the Error table (lib.es2022). Unlocks
   narrowFromAnyWithInstanceof (TS2551 typo members via
   `instanceof`-narrowed `any`) and
   propertyAccessOnTypeParameterWithConstraints4. Note: NO current miss
   depends on primitive METHOD-CALL existence (checked the corpus), so
   the String/Number method-call half was dropped — the tables stay
   incomplete (deprecated HTML methods like `"x".anchor()` are legal
   tsc) and flagging there would be FP-prone for zero recall.
   TP 2646 -> 2648, FP 0.
6. [x] TS2411 computed-property cluster — DONE (batch BC):
   (a) parser: constant computed class keys fold to their literal name
   (`["get1"]` -> get1, `[""]` -> "", `[1 << 6]` -> 64 via a small
   const-int evaluator) instead of `<computed>`; TS18006 exempts the
   computed `["constructor"]` form via `computed_field_keys` (tsc-legal).
   (b) checker: `check_index_props` gained a `symbol` index-signature
   arm constraining `@@X` members (symbolProperty17/32);
   `violates_index_value` gained a bivariant Func-vs-Func arm and a
   Named-class arm that flags only a MISSING required value member
   (`any`-typed members count as required; `?`-optional ones don't —
   `is_structurally_assignable_named` can't disprove, it tolerates
   missing `any` members by design). (c) the class TS2411 walk now
   models accessors (getter return inferred from the body, setter param
   type), infers unannotated method returns, and walks base chains both
   ways: inherited sigs constrain own members (43/44), own sigs
   constrain inherited members (45, symbolProperty32); inherited
   members are NOT re-checked against inherited sigs (no duplicates).
   Unlocks computedPropertyNames36/38/39/40/42/43/44/45_ES6 +
   symbolProperty17/32. TP 2648 -> 2658, FP 0.
7. [~] Edge buckets — `using` declarations DONE (batch BC): TS1492
   ('using' declarations may not have binding patterns) recorded as
   grammar misuses at three parse sites — parse_var_like (labelled
   `using_kw` param), the block-level using lowering (later declarators
   of a multi-declarator `using` land inside the init COMMA CHAIN as
   `AssignPattern` operands — scanned recursively), and the for-of head.
   TS2850/2851 (initializer must be disposable) decided only for the
   provable slice: an UNANNOTATED object-literal initializer whose keys
   are all plain (no `@@`-symbol / computed / spread entries), which
   definitely lacks `[Symbol.dispose]()`. Annotated declarations
   (`using d: T = {...}`) abstain — tsc checks the literal against `T`
   instead. Unlocks usingDeclarations.5/.7/.14,
   awaitUsingDeclarations.5/.7/.12, and both InForOf.3 files.
   TP 2658 -> 2666, FP 0.
   Also DONE from the TS1005 bucket: invalid radix digits — the lexer
   counts a binary / octal literal running into an out-of-radix decimal
   digit (`0b1102110`, `0o13334823`) and the parser surfaces one grammar
   misuse per literal (binaryIntegerLiteralError,
   octalIntegerLiteralError, invalidBinaryIntegerLiteralAndOctal-
   IntegerLiteral). TP 2666 -> 2669, FP 0.
   Remaining (documented, not attempted): the rest of the TS1005
   parser-recovery baselines (heterogeneous, require reproducing tsc's
   error-recovery token stream — e.g. `var x = /fo(o/;` regex re-scan),
   the IteratorObject `using` fixtures (need lib-level
   `Iterator.prototype[Symbol.dispose]` type modeling), and NOBASE
   variant-baseline files (oracle artifacts, not checker gaps).

## Checker conformance triage (MISS 176 -> a declared scope)

Full analysis and the measurements behind it: `docs/checker-triage.md`.

`MISS 176` is not a backlog. It sums work worth doing now with files
nobody should ever fix, so it can rank nothing and can never reach zero.
That is the defect that retired `docs/checker-priority.md`.

All 176 classified by the MACHINERY a rule would need (not by error code
— a code is not a difficulty class):

| family | files | | family | files |
|---|---|---|---|---|
| assignability-core | 48 | | strict-null / narrowing | 8 |
| symbol + computed key | 16 | | `this` typing | 7 |
| other (singletons) | 16 | | decorator signature | 7 |
| legacy / broken syntax | 15 | | locally accepted | 6 |
| mapped / conditional / template | 13 | | resource mgmt (`using`) | 6 |
| generic inference | 11 | | overload resolution | 2 |
| iterator protocol | 11 | | implicit-any / strict | 10 |

The biggest bucket ranks no work: all 48 `assignability-core` files open
to ~10 unrelated causes (variadic tuples, intersections, contextual
typing, `globalThis`, index-signature subtyping, spread types).

Feature frequency, measured over 3,000 real `.d.ts` + 2,697 real `.ts`:
conditional type **345**, `unique symbol` 183, mapped 143, `this` return
115, index signature 102, `[Symbol.x]` key 72, template-literal 57/151,
variadic tuple 20, **`using` 0**, **decorator 1**.

CAPABILITY PROBE (the table that reorders everything — the classification
says what a file NEEDS, not what we HAVE, and guessing at that was wrong
twice). Common shape of each family, probed against `tscheck --strict`
inside a function body:

- CAUGHT: basic assignability, argument count, missing property, mapped
  type via generic alias, `keyof`, strictNullChecks, `this` return type,
  index signature, variadic tuple, generic function inference.
- BLIND: conditional-via-generic-alias, the whole utility-type table,
  template-literal with a placeholder, computed `unique symbol` key,
  overload resolution.

### Tier 1 — SUPPORT NOW

- [~] **Conditional through a generic alias + the utility-type table.**
  PARTLY DONE (batch DI). `Resolver::unwrap` now has a `Conditional`
  arm — it was the only computed-type form of six without one — so
  `type E<T> = T extends string ? … ; E<string>` reduces, and the
  resolver consults `standard_utility_types()`, which had been
  reachable ONLY through `module_alias_resolver`, a `pub fn` with no
  caller outside its own file and its tests. Live now in both
  directions: `Exclude`, `Extract`, `NonNullable`.
  DONE too (batch DJ): the `infer`-binding half. `simplify_type`
  decides through the three-valued `extends_decision`, which cannot
  bind an `infer`, so `ReturnType` / `Parameters` / `Awaited` still
  abstained even with the `Conditional` arm in place.
  `reduce_conditional` (assignability.mbt) is the reducer that CAN —
  it runs `match_infer_pattern` and substitutes the captures — and it
  was reachable from `is_assignable_to` and from three return-type
  sites, but not from alias resolution. It is now tried from the
  `Conditional` arm, and ONLY when the extends type carries a marker:
  its non-infer path is `is_assignable_to`, which is two-valued, so as
  a general fallback it would take the FALSE branch on an undecidable
  `extends` and answer confidently exactly where `extends_decision`
  correctly says "don't know". `ReturnType`, `Parameters`, `Awaited`
  now decide in both directions; **TP 2558 -> 2559, MISS 176 -> 175,
  FP 0**. The extends side is deliberately NOT resolved through the
  resolver when a marker is present — that would rewrite the shape the
  pattern exists to align with.
  DONE too (batch DK): `InstanceType` and `ConstructorParameters`.
  The obvious suspect was `typeof C` — `unwrap`'s `TypeOf` arm reads
  `globals` and a class lives in `classes`, so `typeof C` really does
  arrive unresolved — and that was NOT the cause.
  `InstanceType<new () => C>`, with no `typeof` anywhere, was equally
  silent, which is what found the real defect: `contains_infer_marker`
  descended into `Func` and had NO `Constructor` arm, so it answered
  "no markers here" and the infer path never ran.
  `match_infer_pattern` and `substitute_inferred_type` both already
  handled `Constructor` — two of the trio right, the GATE wrong. Both
  fixes are needed (`class_construct_signature` for the `typeof`
  spelling), and the inline case is what proves which one mattered.
  The construct signature is supplied for the conditional DECISION
  only: a class's constructor side also carries its statics, which the
  checker states it does not model, so resolving `typeof C` everywhere
  would turn every static access through such a binding into a missing
  property. A derived class with no constructor of its own abstains —
  it inherits the base's.
  Buys 0 corpus files again; the capability is the point.
  Two things measured rather than assumed, both worth keeping:
  the whole change bought **ZERO corpus files** (predicted — take it
  for the capability), and wiring the FULL table was wrong: the
  property-shape entries (`Partial`, `Required`, `Readonly`, `Pick`,
  `Record`, `Omit`) already have dedicated `lookup_field` arms and
  resolving them here moved the shape out from under those arms,
  failing three tests. The fallback is gated on the body being a
  `Conditional` — a shape test, not a name list, because a second copy
  of those names is the defect the batch exists to remove.
  And the conformance gate earned itself again: `ThisType<T>` is
  `interface ThisType<T> {}` in `lib.es5.d.ts`, an EMPTY marker, while
  the table encodes it as the identity for the contextual-`this`
  question. Taking that answer structurally made
  `PropDesc<U> & ThisType<T>` demand every member of `T` — one FP on
  `thisTypeInObjectLiterals2`, now resolved to `{}` ahead of the
  generic arm with the shared table left alone.
- [ ] (original entry, for reference)
  The single highest-value item. `(string extends string ? number :
  boolean)` inline is CAUGHT and `type E = string extends …` is CAUGHT,
  but `type E<T> = T extends string ? … ; E<string>` is BLIND — while
  generic alias instantiation itself works for object / array / union /
  passthrough / interface bodies, and `substitute_params`
  (`generics.mbt:63`) and `substitute_named` (`simplify.mbt:57`) both
  already have a `Conditional` arm. So this is a WIRING or
  reduction-order gap, one investigation rather than one implementation.
  It matters far beyond its 13 corpus files: every standard utility type
  is a generic alias over a conditional body, so `ReturnType`,
  `Exclude`, `NonNullable`, `Parameters` and `Awaited` are all inert in
  the body-checking path — a `.d.ts` using them type-checks by
  ABSTAINING, which is a silent hole in the bridge's primary input.
  Check first whether these blind rows are ONE abstention path: the
  control `Bogus<number>` (an unresolved generic name) is also silent.
- [x] **Computed `unique symbol` keys — REFRAMED, and the label was
  mine.** Opening all 16 files shows **11 distinct error codes**, so this
  was never one feature: the same "a NAME is not a feature cluster"
  mistake CLAUDE.md already records for the 21 `Symbol`-ish files. What
  the 16 actually are:
  - REJECTED already, with evidence: TS2466 x2 (batch CL measured 6 FPs
    for 2 TPs on object-literal computed keys, and
    `computedPropertyNames28` vs `30` is a distinction ONE file draws),
    and TS2464 `symbolProperty3` (`var s = Symbol` infers `Any`).
  - BLOCKED on overload resolution: TS2464 `computedPropertyNames9_*` x2
    (`[f(true)]` needs the right overload picked to see the key is
    `boolean`).
  - BLOCKED on lib interface merging: TS2411 x2
    (`objectType*HidingObjectIndexer`) augment the global `Object` and
    the error comes from the LIB's members conflicting with the user's
    index signature, under `skipDefaultLibCheck: false`.
  - BLOCKED on block-scope resolution: TS18033 x2 (`let Infinity = {}`
    shadowing the global inside a block, then `enum En { X = Infinity }`).
  - The rest (TS1166 x2, TS2322, TS2339, TS2353, TS2416, TS2403) are one
    unrelated thing each.
  DONE (batch DL) is the one genuinely cheap file, and it is not a symbol
  rule at all: TS2411 / TS2413 across MERGED interface declarations. The
  rule was complete and correct and read `module_.interfaces`, the
  per-DECLARATION list, so `interface A { [x: number]: string }` beside
  `interface A { [y: string]: {length: string} }` was silent while the
  identical members in ONE body were reported. **TP 2559 -> 2560, MISS
  175 -> 174.** Worth more than its one file: `interface Config {
  [k: string]: string; port: number }` is a mistake people actually make,
  and index signatures appear in 102 of 3,000 real `.d.ts` files.
- [x] **Overload resolution — DONE (batch DM), as TS2769.** The finding
  is bigger than the rule: an overloaded call had its arguments checked
  by NOTHING AT ALL. `g(true)` against `g(a: string)` / `g(a: number)`
  was silent, as were wrong arity and zero arguments, while the
  identical call to a single-signature `h(a: string)` was reported.
  Most of the standard library is overloaded, so the hole is wide on
  real input.
  Why it existed is worth keeping: overload sets ingest as a `Union` of
  call signatures, and `check_union_callee_arity` is DELIBERATELY not
  applied to them — its rule is that EVERY member must accept, right
  for a union-typed value and wrong for an overload set where one match
  is enough. That exclusion is correct and its comment says so; what
  was missing is that nothing took over.
  `check_overload_set_no_match` reports only when EVERY member is
  PROVEN unable to accept (arity, or a definite-primitive argument
  against a definite-primitive parameter it is not assignable to).
  That makes it sound for a union-typed VALUE too — if no constituent
  can accept, the call is wrong under either reading — so it is not
  gated on `resolver.signatures` and the two rules need not be told
  apart. Abstention is per-member with an early return: one member that
  merely MIGHT accept silences the call, which is what keeps a generic
  overload, an object-typed parameter, a rest parameter, a spread
  argument and an unreadable member silent.
  Cost one FALSE POSITIVE first, and the hazard was already written
  down: `check_union_callee_arity`'s comment records that "two callables
  can have identical widened parameter types while differing in whether
  that parameter was written with `?`", and a `declare function`
  overload arrives with its optionality widened into the type
  (`a?: string` becomes `string | undefined`) and an empty
  `optional_params` — so `t()` against `t(a?: string)` was reported. A
  parameter that ACCEPTS undefined is now treated as omittable, which
  over-counts optionals and therefore only ever weakens the proof
  (batch CU's decorator arity took the same trade).
  0 corpus files (the one TS2769 miss is a generic-inference case), but
  it CLOSES a known-gap fixture: `fixtures/mtsc/known-gaps/overload-resolution.ts`
  moves from "records what we miss" to a regression pin.
  KNOWN LIMIT, silence not a finding: an overload set declared as real
  `function` declarations WITH an implementation does not reach this
  check on the strict path — the `resolver.signatures` branch claims the
  callee first. It works on the permissive path (which is what the
  fixture exercises). Filed rather than fixed: the fix means touching
  the single-signature argument checker.

### Tier 2 — SUPPORT (cheap, mechanical, ~25 files)

- [x] **Batch DN: TS2371 + TS2394, +3 files at FP 0** (TP 2560 -> 2563,
  in-scope MISS 157 -> 154) — `parserParameterList16`/`17` and
  `parserClassDeclaration12`, the three files Tier 4 had mis-filed under
  legacy/broken-syntax.
  - TS2371 is the applied-in-some-places family in its strongest form:
    the rule was not similar to an existing one, it WAS one. It lived as
    a LOCAL function at the two bodiless exits of `parse_function_decl`,
    and inline through a different channel for interface members, and the
    CLASS path had nothing — `class C { foo(a = 4); foo(a, b) {} }` parsed
    clean. Hoisted to one `Parser::record_bodiless_param_initializers`.
    The rule is about the BODY and nothing else, so the test is
    `has_body_block` rather than the modifiers; every bodiless position
    was probed (overload signature, `abstract`, `declare class`,
    `interface`, object type, function TYPE, `declare function`) and all
    report. The legal neighbours are the two the message names plus an
    ARROW, whose body follows the `=>` — which is what a class field
    holding `(a = 1) => a` is.
  - TS2394's arity half is ONE-directional and the message text does not
    say which direction, so the table was probed cell by cell: an
    implementation requiring MORE than a signature can supply is the
    error, a SHORTER implementation is legal. Four of the eight silent
    test cases are what a rule written from the message alone would
    flag. A TYPE mismatch raises the same code and is abstained on.
- [ ] Remaining grammar / declaration rules: TS2386, TS2448, TS1308,
  TS2842, TS2708, TS1166, TS2300.
- [x] **Batch DO: TS7009 and `&&=`, +4 files at FP 0** (TP 2563 -> 2565,
  in-scope MISS 153 -> 150 after two accidental TPs moved to Tier 4).
  Three findings, and two of them are about code that was already there.
  - **TS7009** is TS2350's rule with its exclusion removed, and the FLAG
    decides which of the two applies — probed both ways. With
    `noImplicitAny` off, `new f()` errors iff `f`'s return is not `void`
    (TS2350); with it on there is no exemption at all, and tsc reports
    even `function Point(x) { this.x = x }; new Point(1)`. The old
    `resolver.signatures` early return excluded every top-level function
    DECLARATION by name, which was REDUNDANT for TS2350 (an old-style
    constructor's return is `void`, which the return-type predicate
    already abstains on) and was the only thing blocking TS7009. It also
    lost the commoner spelling with the flag off — a declared function
    with a non-void return annotation, excluded before any type was
    consulted.
    TS7009 needs POSITIVE evidence where TS2350 could lean on abstention,
    and the unit suite proved it: the unrestricted version was +2 corpus
    files and **5 false positives** (`localTypes2/3/5`,
    `classExpression4`, `privateNameMethodAsync`), because the parser
    lowers a class declared INSIDE a function to a function — so
    `function outer() { class A { x = 1 } return new A() }` arrives as a
    `Func` and is a legal `new`. Gated to a top-level function
    declaration or a WRITTEN call-signature object type: +1 at FP 0. The
    file it gave up was flagged for the unsound reason.
  - **`a &&= b`** is `a && (a = b)`, so when `a` is falsy the result is
    `a` and `b` never runs. `infer_expr`'s compound-assign arm returned
    the RIGHT-HAND SIDE for all fifteen operators — right for the twelve
    arithmetic and bitwise ones, wrong for this one — which is why
    `(results &&= []).push(100)` was silent while tsc reports TS2532.
    `||=` and `??=` do NOT widen: the operator has already removed the
    nullish part of the target, so unioning it back in would report the
    legal spellings (probed: `logicalAssignment6/7/8` error on their
    `&&=` function and nothing else). Needed a second change, and the
    abstention it relaxes states its own reason: the strictNullChecks
    member-access checks are gated to a bare `Var` receiver because
    those are the bindings the narrowing engine rewrites precisely. A
    `&&=` receiver qualifies for the OPPOSITE reason — there is no
    narrowing to get wrong, its type is computed from the operator's
    semantics, and the target is inferred through the same `env`.
    `nullish_checkable_receiver` is the one predicate both sites now ask.
  - **A pre-existing false positive**, found by probing a legal
    neighbour for the rule above rather than by any gate: `+=`'s
    string-concatenation exemption tested for `String_` EXACTLY, so
    `let t = ""` — whose type here is the literal `""`, since tsc widens
    it and we do not — demanded a numeric target and reported ordinary
    string building. Asking assignability widens the EXEMPTION, so it can
    only lose a finding. Removing it cost **two TPs**, and that is the
    batch's own lesson repeated from CS with the sign flipped:
    `parserRealSource1`/`2` were flagged for `result += "\\t"` and
    nothing else, while their real TS7 error is the TS6053 that already
    puts `parserRealSource3` in Tier 4. They are declared there now, and
    `--max-miss` — added one batch earlier — is what surfaced them.
- [x] **Batch DP: every checker class rule now sees a class declared
  inside a function** (+1 file, TP 2565 -> 2566, in-scope MISS 150 ->
  149, FP 0). The count is not the point: the rules were silent at every
  depth but zero.
  - `TsModule.classes` is filled by the module-level statement
    dispatcher, the only thing that took the parser's
    `last_runtime_class_decl` stash, so a class one scope in was recorded
    nowhere a rule could read. Probed before and after: TS2420
    (implements), TS2415/TS2417 (extends compatibility) and TS2564
    (definite assignment) all fired at top level and at no other depth,
    while batch DN's TS2394 fired in both because it lives in the parser.
    Now covered in a function body, a block, an `if` branch and an arrow
    body.
  - The parser collects them into `TsModule.local_classes` and the
    checker merges the two at ONE entry point, which is what makes all
    ~58 `module_.classes` loops see them without touching any of them.
    `check_module` is deliberately excluded: its first act is a
    duplicate-declaration scan across every top-level kind.
  - **The merge cost four false positives before it was right, and every
    one is the same mistake**: `module_.classes` does not mean "the
    classes", it means "the classes with no enclosing scope", and three
    rules depend on the second reading.
    * `localTypes2`/`3` — the resolver's NAME table must not learn a
      block-scoped name. A nested `class C` beside `let C = f(10)` made
      `new C(20)` resolve to the class and fail its constructor arity.
      `Resolver::ingest_module` skips `is_local`.
    * `classConstructorAccessibility4` — `new A()` inside a class nested
      in A's own method is legal. A's method body is already scanned with
      `enclosing = "A"`; scanning the nested class's body as if it were
      top level reported the same expression again.
    * `privateNameComputedPropertyName3` — `check_private_member_access`
      states its premise in its own doc comment ("nested class bodies are
      skipped — their accesses may legally reach an outer class's
      privates"), and the merge broke exactly that.
    So `TsClassDecl` carries `is_local`, the three position-dependent
    consumers test it, and the rest do not. Skipping a name already
    declared at top level (or repeated among the local classes) is what
    stops `function f() { class A {} } class A {}` reading as a duplicate.
  - Measured linear: a hand ladder of N classes-inside-functions is
    32/62/130/267 ms at 500/1000/2000/4000 (exponent 1.02), and the
    scaling gate's seven axes are unchanged.
  - Known remainder, deliberately not chased: a nested class whose BASE is
    also nested does not resolve its base chain, because the base is not
    in the resolver's name table either. That loses a finding rather than
    inventing one.
- [x] **Batch DQ: the same rules also see a class EXPRESSION** (+3 files,
  TP 2566 -> 2569, in-scope MISS 149 -> 146, FP 0). Probed first, which
  is what made the axis worth taking: TS2420 / TS2415 / TS2564 all fire
  on a class DECLARATION, on `declare class` AND on a namespace-scoped
  class, and on `const C = class …` not one of them did — while
  `const C = class {}` is how a mixin, a HOC and a decorated factory
  class are all written.
  - `parse_class_stub` records into `local_classes` from **both** of its
    exits, which is the whole finding: the native `NativeClassExpr` exit
    is taken only when there is an `extends` clause, and a base-less
    class expression falls through to the desugar below it. Recording at
    the first alone bought exactly the one rule that needs a base —
    TS2415 fired and the other two stayed silent — which is how the
    split was found rather than assumed.
  - An anonymous class expression gets a per-occurrence synthetic name.
    Per-occurrence and not one shared `<class expression>`, because the
    merge skips a repeated name and a file with several anonymous
    classes is the normal case; pinned by a test that asserts BOTH of
    two get checked.
  - One false positive, and it is the DP lesson on a fifth axis:
    TS2449 ("class used before its declaration") compares INDICES in
    `module_.classes`, which encode top-level source order — and a local
    class is APPENDED, so its index is not a position. Reading it as one
    made every top-level class whose base shares a name with a class
    expression look forward-referencing
    (`accessorsOverrideProperty8`: `const Base = classWithProperties(…,
    class Base {})` beside `class MyClass extends Base`). Exempting
    local classes on both sides costs the mirror MISS —
    `const D = class extends B {}; class B {}` IS TS2449 and stays
    quiet — which is the affordable half.
- [x] **Batch DR: the nullish operators, +3 files at FP 0** (TP 2569 ->
  2572, in-scope MISS 146 -> 143). Three rules, each with a boundary that
  had to be probed cell by cell because reasoning about it gives the
  wrong answer.
  - **TS2869** ("right operand of `??` is unreachable") is purely
    SYNTACTIC in tsc, which is the finding: `false ?? true`, `0 ?? 1`,
    `{} ?? y` and `(() => 1) ?? y` all report, while
    `const m = false; m ?? true` and `declare const s: string; s ?? "b"`
    are ACCEPTED — neither can be nullish either. A type-level version
    would have reported two shapes tsc allows. Sibling of the TS2872 /
    TS2873 literal-operand rules on `!` and `||`, and it reuses their
    literal classification. `null` / `undefined` are excluded (tsc gives
    them TS2871, a different code); `void 0` is a declared MISS — tsc
    reports TS2869 there but the right operand really IS reached, so
    following it would encode a compiler quirk as a rule.
  - **TS18048 / TS18049**: the right operand of `??` runs only when the
    left is nullish, so inside it the left BINDING is narrowed to its
    nullish part and a member access on it is always an error
    (`f ?? f.toFixed()`). It matches the right operand's SHAPE rather
    than walking it, and that is the soundness argument: an assignment
    anywhere inside the RHS makes the binding non-nullish again
    (`s ?? ((s = "x"), s.length)` is ACCEPTED, measured), and a walk that
    missed an assignment form would fail OPEN into a false positive.
    When the access IS the whole right operand nothing can hide in it.
  - **TS2790** ALREADY EXISTED for `delete o.b` and was blind to the two
    other spellings of the same property reference. `delete o?.b` arrives
    as `OptionalChain(PropAccess(…))` and the match saw the WRAPPER —
    the fourth time in this repo that a wrapper node's default arm has
    cost a silent miss, after `TypeArgs` and `PureCall` twice — and
    `delete o["b"]` had no arm at all. Inside an optional chain the
    receiver's nullish part is pruned, which is exactly what the `?.`
    guarantees.
- [ ] **REJECTED for now with the condition: TS7031 / TS7018** (a nullish
  literal where a type must be inferred, under `noImplicitAny` with
  `strictNullChecks` OFF — `var [a, b] = [undefined, null]` and
  `const o = { value: null }`). The rule is sound and the family is one
  rule with three codes (TS7005 for a plain `const v = null` too), but
  the blocker is mechanical and exact: **`var [a, b]: any = [undefined,
  null]` is ACCEPTED by tsc and the unannotated form is TS7031**, while
  `TsStmt::Let` / `Const` / `Var` carries a `TsType` in which an ABSENT
  annotation and an explicit `: any` are the same `Any`. The parser has
  that fact at parse time — `parse_param` records it in
  `written_any_params` via `had_annotation` — so the fix is a
  declaration-level equivalent of that channel plus a `strict_null_checks`
  field on the Parser (which has `no_implicit_any` and not this one).
  Two channels for two corpus files, only one of which
  (`{ value: null }` in a legacy migration) has real-world value.
- [x] **Batch DS: TS2386 / TS2394 / TS2565, +3 files at FP 0** (TP 2572 ->
  2575, in-scope MISS 143 -> 140). Three unrelated rules, and all three
  read WRONG from their message text alone.
  - **TS2386** ("overload signatures must all be optional or required")
    is purely about the `?`, so it needs no type and lives in the parser.
    It needed **four** sites — a runtime class body, an interface, an
    object type literal and `declare class` each have their own member
    parser — which is the applied-in-some-places family again, taken
    completely on the first pass rather than discovered later. In a
    runtime class the IMPLEMENTATION participates as REQUIRED: probing
    `m?(x); m?(s); m(v) { }` reports on BOTH signatures, so recording
    only the bodiless declarations would have accepted it. `declare
    class`'s member parser DISCARDED the `?` (`let _ =
    self.match_(Question)`), which is why that site was the one with
    nothing. Only METHOD signatures participate: two same-named
    PROPERTIES are a duplicate identifier (TS2300 / TS2717), a different
    error that already fires, so putting properties in would report one
    declaration twice. Accessors and `constructor` cannot carry `?` at
    all. Keyed by static-ness as well as name, since `static m` and `m`
    are two members and need not agree.
  - **TS2394's parameter half** is where the batch-DN blocker finally
    dissolved. `TsFunc.body` is not optional, so an overload SIGNATURE
    and an implementation are indistinguishable downstream — and
    `note_function_declaration` is called at every one of the four sites
    that pushes a function declaration, with exactly the `bodiless` fact,
    so a `<fn-impl:NAME>` marker makes "the last declaration is the
    implementation" a FACT instead of the guess the neighbouring
    `check_overload_void_return` had to make. The rule was added to that
    same function rather than beside it. Probed cell by cell, because the
    message ("not compatible with its implementation signature") does not
    say which direction: an incompatible parameter TYPE is the error
    (`f(x: "a"); f(x: number) { }`), an implementation with FEWER
    parameters is LEGAL (a shorter function is assignable to a longer
    one), and `any` accepts everything. Only a pair of
    definitely-concrete primitives incompatible in BOTH directions is
    judged; a type parameter, an object shape, a union or a missing
    annotation abstains.
  - **TS2565** ("property is used before being assigned") is expando
    flow: `function d() { }` then `d.e = 12`, and reading a property
    assigned only inside a conditional branch. One ordered pass per
    statement list tracking DEFINITE / POSSIBLE per `HOLDER.PROP`, and
    the `if` statement is the ONLY construct that produces `possible` —
    a write in anything this pass does not model counts as definite, so
    an unmodelled shape SILENCES the check instead of firing on it. That
    is what `switch (1) { default: d.q = 1 }` needs: the default arm
    always runs and tsc accepts the following read, so any
    reachability-aware formulation would have false-positived there. It
    costs the `while` case, which tsc DOES report, and that MISS is what
    buys FP 0.
    Three things had to be probed rather than reasoned. `d["q"] = 1` and
    `d.q = 1` are NOT the same rule: inside an `if` arm the bracket
    spelling makes the later `d.q` LEGAL and the dotted one does not, so
    the two spellings are collected separately and only the dotted one
    can be merely-possible. Passing the holder to a function does NOT
    assign the property (nor does `Object.assign`), so the report still
    stands there. And a read from ANOTHER scope is legal however the
    property was assigned — the corpus file says so in its own comment
    and `function later() { return d.q }` confirms it — so the read walk
    stops at a nested function body and at a nested block, while the
    WRITE walk descends into both (calling a write definite is the quiet
    direction).
    Two parser facts cost the first two drafts. `d.q = 1` at the top of a
    list is a `PropAssign` STATEMENT while the identical line inside a
    block is `Expr(PropAssignExpr(...))`, and reading only the first
    found NOTHING at all — the same two-spellings-one-rule shape as
    TS2386 above, in the AST instead of in the parsers. And a top-level
    `function d() { }` is parsed by the module loop into `module_.funcs`
    and is NOT pushed into `top_level_stmts`, so the outermost list has
    to be told about those holders by name and each such body scanned
    explicitly.
- [x] **Batch DT: TS7010 at the member signatures, TS7022 / TS2448 at
  both self-reference sites, +2 files at FP 0** (TP 2575 -> 2577,
  in-scope MISS 140 -> 138). Both rules are the applied-in-some-places
  family, and BOTH had a comment at the missing site stating an
  abstention whose stated reason turned out to be FALSE — which is the
  reusable finding: a recorded abstention is a lead, and its reason still
  has to be probed.
  - **TS7010** ("'X', which lacks return-type annotation, implicitly has
    an 'any' return type") existed for a bodiless `function` declaration
    and for `declare function` and for NOTHING else, so an interface
    method, an object-type method, a class overload signature, an
    `abstract` member and a `declare class` member were all silent. One
    recorder, four member parsers. The class site carried a comment
    declining it because "tsc does not flag an overload signature whose
    implementation carries the return annotation" — probed, `m();
    m(x: number); m(x?: number): void { }` reports on BOTH signatures,
    while `m(): void; m(x: number): void; m(x?: number) { }` (annotated
    signatures, unannotated implementation) is ACCEPTED. The exemption
    belongs to the BODY, not to the overload set, so the stated reason
    was the inverse of the truth. Accessors and bare properties are
    excluded because tsc gives them TS7033 and TS7008, two different
    rules. The test is on whether an annotation was WRITTEN, not on the
    resolved type: `foo(n: string): any` is accepted and the parsers
    default a missing annotation to `Void`/`Any`, so the two are
    indistinguishable afterwards.
  - **TS7022 / TS2448** (a binding whose own initializer evaluates a
    reference to it) existed for a `for…of` head whose iterable is a bare
    `Var` and was missing at the DECLARATION site, so `let x = x`,
    `const x = [x]` and `let x = typeof x` were all silent. The head
    rule's walk was two arms wide with a comment claiming that widening
    past them "would claim a cycle that is not one" for a name reached
    through a call or a property. Probed, the dividing line is not
    call-versus-property but whether the reference is EVALUATED before
    the binding initializes: `for (let v of [v])`, `[1, v]`, `g(v)` and
    `[...xs, v]` all report, while `o.v` does not (a property NAME is a
    `String` in this AST and can never be reached as a `Var`) and
    `[() => v]` does not (the body runs later). One shared walk now
    serves both sites. Two codes, one condition, each gated on the fact
    it needs: TS2448 applies to `let`/`const` whatever the annotation
    says (`let x: number = x` is still TS2448, the TDZ being about time),
    while TS7022 needs the annotation ABSENT and is all a `var` gets.
  - Threading `head_annotated` in from the parse site fixed a
    **pre-existing false positive** the head rule's own comment had
    promised not to have: it gated on `var_type is Any`, which cannot
    tell an absent annotation from an explicit `: any`, so
    `for (var v: any of v)` was reported. And the comment's claim that
    the spelling is "legal" is also wrong — tsc gives it TS2483 + TS2502,
    two codes this rule does not claim, so the old behaviour was the
    right file for the wrong reason and abstaining costs a MISS.
  - **Three pre-existing tests asserted the TS7010 gap by name** — the
    eighth, ninth and tenth in this repo found doing that. The
    TS2387/TS2388, TS2391 and class-expression tests all wrote
    `class C { foo(x: number); foo(x: any) {} }` and asserted 0, and
    `parse_module_or_empty` defaults `noImplicitAny` to TRUE, so every
    one of those sources is a file tsc rejects. Annotating the
    signatures makes each test measure the rule it is named for.
- [ ] **MOVED TO TIER 3 with evidence: TS7023 (3 files) and TS7053 (2).**
  The triage called the whole implicit-any family "cheap and
  mechanical"; opening the files says otherwise, and that is the
  label-for-objective substitution again. TS7023's three files
  (`for-of33` / `-34` / `-35`) need an inference CYCLE detector through
  a class method's un-annotated return type — the only cheap version
  keys on the exact corpus shape ("the iterated class's `next()` returns
  the loop variable"), which is fitting the corpus for three files
  nobody's real code resembles. TS7053's two need
  union-of-index-signature member resolution and assignment-target
  widening of `(options || {}).a`; both files also carry TS2339 /
  TS2322 for the same underlying reason, which is what says it is one
  Tier 3 capability rather than a grammar rule.
- [ ] **FILED: `for (let v of [() => v])` is a pre-existing false
  positive** — "cannot find name `v`" from the undefined-name walk, on a
  file tsc ACCEPTS. The for-of head binding is entered into `env` AFTER
  the iterable is inferred (correct for the TDZ), so an arrow body
  inside the iterable cannot see it, while the same arrow in the loop
  BODY resolves fine. Invisible to the conformance gate (no corpus file
  has the shape) and pre-existing, verified against the pre-batch
  binary. The fix has to bind the name for the undefined-name channel
  only, without giving `infer_expr` a type for it during the iterable's
  own inference.
- [x] **Batch DU: TS2729 for a field with NO initializer, +1 file at
  FP 0** (TP 2577 -> 2578, in-scope MISS 138 -> 137). Third batch in a
  row whose target was a recorded ABSTENTION, and the third whose stated
  reason was false — which makes "open the comment that declines the
  rule, then probe its reason" the highest-yield move left in this tier.
  `check_class_property_init_order` restricted its candidate set to
  init-bearing fields, saying a field declared without an initializer
  "has no initialization to be 'used before'". It has:
  `class C { b; d = this.b }` and `class C { b: number; d = this.b }`
  are both TS2729 in either declaration order, because a slot only
  written in the CONSTRUCTOR is still `undefined` while field
  initializers run — so such a field never enters the `inited` set and
  order does not matter for it.
  The real exemption is a MODIFIER, and probing one cell at a time gives
  exactly two: `!` and `?`. It is emphatically NOT "the declared type
  admits undefined" — `b: number | undefined`, `b: any`, `b: unknown`
  and `b: void` all report, and so does the whole thing under
  `strictNullChecks: false`, so a rule written from the type would have
  been wrong in four places. And since the parser wraps `x?: T` into
  exactly `T | undefined`, the `?` CANNOT be read off the type: it rides
  an `<optional-member:` sentinel through the class's duplicate-member
  channel, recorded before the wrap, the same shape as
  `<quoted-member:` (which exists because TS2564 needed a fact the type
  could not carry either).
  `scopeResolutionIdentifiers`, the false positive the old abstention
  was protecting against, is the `s!: Date; n = this.s;` form — so it
  was avoided for the wrong reason and is still avoided, for the right
  one.
  One declared MISS, stated at the site: `declare b: T` is TS2729 in
  tsc, and the parser folds `has_declare` into `has_definite_assertion`
  (correctly, for TS2564), so an ambient field reads as asserted here.
  That loses a finding and cannot invent one.
- [x] **Batch DV: TS7022's INDIRECT form through the iteration protocol,
  +3 files at FP 0** (TP 2578 -> 2581, in-scope MISS 137 -> 134). A
  `for (var v of new C)` head takes its element type from C's iteration
  protocol, so an un-annotated `next()` / `[Symbol.iterator]()` that
  RETURNS `v` is a genuine inference cycle.
  Batch DT declined exactly these three files one batch earlier, saying
  "the only cheap version would key on the exact corpus shape". That was
  too pessimistic, and the thing that settles it was in the corpus the
  whole time: **`for-of25` and `for-of26` are `for-of33` and `for-of34`
  with the returned name changed** from the loop variable `v` to an
  unrelated `var x: any`, and both are TS7-ACCEPTED. So the
  discriminator is the NAME — the actual semantic distinction, not a
  match on file contents — and the corpus supplies its own negative
  controls, twelve of them counting `for-of19`-`23`, `27`, `28`, `30`,
  `31` and `ES5For-ofTypeCheck10`. Fourth time in this series that a
  stated abstention's reason turned out weaker than claimed, and the
  first where the abstention was my own from the batch before.
  Implemented entirely in the PARSER, which is what keeps it small: the
  class body records the bare `Var` names its un-annotated protocol
  methods return, keyed by class name, and
  `record_for_head_binding_misuses` — where TS7022's DIRECT form already
  lives — joins against `new C`. The mention test is
  `collect_iterable_var_names`, the same walk the direct form uses,
  because "does this expression evaluate a reference to NAME" is the same
  question and a second walk would be the applied-in-some-places family
  in its purest form.
  Every gate was probed, and three of them are what keep it off legal
  code. Only the two PROTOCOL methods count — a `helper()` returning the
  loop variable is ACCEPTED, because nothing consults its return type.
  An annotated return breaks the cycle, so this needs
  `had_return_annotation` rather than `return_type is Any` (the AST
  cannot tell an absent annotation from an explicit `: any` — the same
  blocker recorded for TS7031 and TS2729). And a name the method itself
  BINDS is its own local: `next() { let v = { value: 1, done: false };
  return v }` beside `for (var v of new C)` is TS7-ACCEPTED, so firing
  there would be a false positive on legal code that no corpus file
  covers. The bound-name set is deliberately over-approximated (a
  nested block's `let`, a nested function's parameter), which loses
  findings rather than inventing them.
  Three declared MISSes, each stated at the site: a `let`/`const` head
  (the class body is outside the loop's block scope, so tsc gives
  TS2304 there and a different check already reports it), an
  annotation-typed iterable (`declare const c: C; for (var v of c)`,
  which needs the annotation resolved), and an IIFE inside the return
  (`return (() => v)()`, which tsc reports because the IIFE's return
  type feeds back).
  The other half of the indirect form — generic return-type inference
  from a callback (`let x = arr.map(v => x)`) — is NOT covered and is
  Tier 3: probing shows the reportable class needs the callee's
  signature and generic inference, since `let x = g(() => x)` with `g`
  declaring a return type is ACCEPTED while `arr.map` is not, and
  `let x = function () { return x }`, `[() => x]` and `{ m: () => x }`
  are all accepted too.
- [ ] **FILED: TS2393 for duplicate top-level function implementations.**
  Batch DS's `<fn-impl:NAME>` marker removes the blocker
  `check_function_var_duplicates`' comment used to name, and it is pushed
  once per implementation, so a COUNT is already available. What it does
  NOT do is distinguish two implementations from two SCOPES: the marker
  is restricted to the module / namespace body loop precisely because
  `grammar_misuses` is flat and scope-blind, so `function f() { }` at top
  level beside `function g() { function f() { } }` would otherwise read as
  two implementations of one name and two legal scopes. With that
  restriction in place the count is honest for the top level, and TS2393
  is a small step from here — it was left out of batch DS only because
  nothing in the corpus needed it. The class-member version already
  exists and needs no scope model, a class body being one.
- [x] strict-null / narrowing: 3 of 8 in batch DO (the `logicalAssignment`
  files). Five left.

- [x] **Batch DW: the excess-property check reaches a `Record<string, V>`
  target, +1 file at FP 0** (TP 2581 -> 2582, in-scope MISS 134 -> 133).
  Two sites held one decision and gave opposite answers.
  `check_expr_against`'s `(ObjectLit, Applied(name, _))` arm deliberately
  routes the six projectable utility types into
  `check_object_lit_against_target` — its own comment says so, "since
  `lookup_field` / `collect_declared_fields` know how to project their
  field shapes" — and that function threw them straight back out through
  TWO early returns, `member_recv_unmodeled` and
  `type_contains_unresolved_named`, both of which call any `Applied` to a
  non-class, non-interface name unresolvable. So
  `{ black: { r, g, d } } satisfies Record<string, Color>` reported
  nothing.
  The exemption is `Record` ONLY, and only with a bare `string` /
  `number` key. The wider version — every projectable utility, judged by
  all of its arguments — was implemented and MEASURED before being cut
  down: +1 TP and **+1 FP**, the false positive being
  `isomorphicMappedTypeInference`'s
  `f20<T, K extends keyof T>(obj: Pick<T, K>)`, which accepts any object
  literal because `T` is inferred FROM the argument. A type-parameter KEY
  is the same hazard (`f<K extends string>(o: Record<K, number>)`), which
  is why the key must be the concrete keyword. The missing-required half
  stays vacuous for `Record` by construction, since
  `collect_declared_fields` has no `Record` arm — which is right, as
  `Record<string, V>` requires no particular key.
- [x] **Batch DX: the excess-property check runs at a CALL argument when
  the callee is provably non-generic.** Corpus yield is **ZERO** by
  design and measured (TP 2582 -> 2582, FP 0) — the call position is
  where real code hits TS2353 and the conformance corpus does not test
  it, so the position matrix and the unit test ARE the measurement.
  The fact that lifts the suppression is `callee_non_generic`: a callee
  with no type parameters has no bound to inline, so an `Object(_)`
  parameter target must be a written inline object type. It defaults to
  `false` ("the caller cannot answer"), so every call site that does not
  thread it keeps the suppression and loses a finding rather than
  inventing one — and only two sites can prove it, a direct call to a
  resolved function declaration and `new` on a resolved class. An ABSENT
  entry in `func_type_params` is explicitly NOT proof (a
  call-signature-typed variable or a lib method has no entry either), so
  the direct-call site requires a resolver signature AND an empty
  type-parameter list.
  Recovered: a `declare function` argument, a `function` declaration
  argument, `new` on a non-generic class, and BOTH nested shapes under an
  argument (`f({ a: { x: 1, y: 2 } })` and `f({ a: { x: 1 }, b: 2 })`) —
  the nested target came from a `lookup_field` on a written parameter
  type, so the fact holds at depth. Still MISSes by design: a method call
  and a call through a function-typed binding, neither of which can prove
  the callee's genericity from its site.
  The four false positives the gate exists to avoid are in the test:
  `foo<U extends { length: number }>(x: U)`, its `function` form, a bare
  `foo<U>(x: U)`, and `bar<U extends { a: number }>(x: U[])` — all
  TS7-ACCEPTED.
- [ ] **SUPERSEDED by batch DX — kept for the measurement: the
  excess-property check at CALL ARGUMENTS.** A position matrix says the check covers the annotated
  declaration, `return`, an array element, `satisfies`, assignment and a
  nested property, and is missing at every CALL position — a
  `declare function` argument, a method call, an arrow-typed binding's
  call, and a `new` — which is the commonest place real code hits
  TS2353. The suppression is one line
  (`sub_path.contains("arg[") && target is Object(_)`) with a stated
  reason, and this is the FIRST of five recorded abstentions in this
  series whose reason probing CONFIRMED: removing it is **+0 TP and
  +3 FPs** on hand-written TS7-accepted code, because a constrained type
  parameter's bound really is inlined into the parameter position
  (`foo<U extends { length: number }>(x: U)` accepts
  `{ length: 1, extra: 2 }`) and the earlier early returns do not catch
  it. Corpus-wide the blunt removal is **+0 TP / +1 FP** — so the
  call-argument position is worth zero conformance files and the
  suppression is load-bearing.
  What would make it shippable is a gate on the CALLEE being
  non-generic: no type parameters means no bound can have been inlined,
  so an `Object(_)` parameter target must be a written inline object
  type. That is sound and loses only a generic function's inline-object
  parameters. It is not built here because it buys no corpus file and
  needs a fact threaded through `check_expr_against`, which has ~30
  callers; the real-world diagnostic is the only argument for it, and it
  is a good one.
- [ ] **FILED: `arrayLiterals.ts`** — the last excess-property MISS of
  the three needs an object literal checked against a target whose shape
  is a NUMERIC INDEX SIGNATURE (`{ [n: number]: { a: string; b: number } }`),
  where each element's value must be checked against the index value
  type. The `@@computed:` arm of `check_object_lit_against_target`
  already does exactly this lookup for one narrow case, so the machinery
  is there; the third file, `symbolProperty21`, is a computed
  `[Symbol.toPrimitive]` key, which that function skips by design.

- [x] **Batch DY: the assignment-form `for…of` target at all three
  spellings of the write.** The check fired for a bare `Var` and was
  blind to `o.x`, `foo().x` and `arr[0]`: the parser wraps a
  non-identifier assignment-form head as `TsBinding::Target(expr)`, and
  that fell through to the destructuring-pattern arm and was dropped
  there. One shared closure now holds the eight-condition guard chain so
  the spellings cannot diverge again.
  **Corpus yield is ZERO, and the reason is the finding.** `ES5For-of8`
  is `function foo() { return { x: 0 } }` with
  `for (foo().x of ['a','b','c'])`, and an UN-ANNOTATED function's return
  type does not resolve in this checker at all — `const bad: string =
  foo().x` is silent too. So that file needs return-type inference from a
  BODY, which is a Tier 3 capability, not this rule. Annotated receivers
  (`declare function foo(): { x: number }`) do fire, which is what the
  test pins.
- [ ] **FILED with both blockers: a DECORATOR expression's function body
  is never type-checked.** Probed: `@((x, p, d) => { var a = 3; func(a);
  return d; })` on a class member reports nothing while the identical
  arrow assigned to a `const` reports TS2345, and a decorator FACTORY's
  body (`@dec()` where `dec` is a declared function) also reports —
  because that function is a top-level declaration the walk already
  reaches. What is missing is an arrow / function written INLINE in the
  decorator position. The two halves have different blockers:
  - a CLASS decorator's expressions ARE retained
    (`TsClassDecl.decorators : Array[TsExpr]`) and nothing type-checks
    their bodies — `ts2683_walk_expr` walks them only for `this`. Cheap,
    and buys no corpus file.
  - a MEMBER decorator's expression is not in the AST at all:
    `parser_class.mbt` keeps only `member_decorated : Bool` for
    TS1249 / TS1207 and discards the expression. That half is what
    `decoratorChecksFunctionBodies` needs, and it requires the parser to
    retain the expression first.
- [ ] **The remaining assignability bucket is 35 files with ~35 causes**,
  confirmed by opening every one: variadic tuples, template-literal
  types, generic bivariance, `globalThis` modelling (3 files — the only
  visible mini-cluster), `SymbolConstructor` lib members, the generator
  protocol, contextual typing of function expressions, `never`
  narrowing, protected constructors, enum assignability, salsa/JS
  expando+namespace merging, optional-chaining nullability, `Intl` lib
  shapes. Four of the five cheapest-LOOKING (a plain
  `number`/`string` mismatch) were opened in batch DY and each needs
  something different: a well-known-symbol accessor pair's inferred type
  (`symbolProperty46`), object-literal union normalization on widening
  (`objectLiteralNormalization`), expando/namespace declaration merging
  (`typeFromPropertyAssignment31`), and return-type inference from a body
  (`ES5For-of8`, closed above as far as it can be). The measured rate
  here is ~1 file per investigation.

### Tier 3 — DEFER (~93 files, real but expensive)

`assignability-core` (48), `generic-inference` (11), `iterator-protocol`
(11), `this-typing` (7), `other` (16). Every one is genuine TS behaviour
needing machinery we have not built: intersection reduction, contextual
typing, `globalThis` modelling, index-signature subtyping, the
async-iterator protocol. Do NOT take these for the MISS count — the
measured rate is 2-12 files per batch. Take an individual file only when
a real bridge input or `mtsc` target demands it, and record which one did.

`decorator-signature` (7) sits here on a CAVEAT rather than a
measurement: this corpus samples no Angular / NestJS / TypeORM. Promote
if a bridge target uses them.

### Tier 4 — WON'T SUPPORT (17 files, declared out of scope) — DONE

- [x] `scripts/checker_out_of_scope.txt`, one path per line with its kind
  and reason. The estimate was ~24 and the answer is **17**, because the
  estimate came from the family classifier and the 17 came from OPENING
  every file. Both corrections are the label-standing-in-for-the-objective
  substitution CLAUDE.md records five times, and the file itself is the
  only defence:
  - **legacy / broken syntax, 6 of 15 — not 12.** The classifier keyed on
    the DIRECTORY, and `parser/ecmascript5/` holds ordinary current
    TypeScript beside the error-recovery corpus. OUT: `x: break`,
    `x: public`, `interface I { [public a] }`,
    `import x = module("m")`, `///<reference>` path resolution (TS6053 is
    program construction, and the checker has no notion of a program), and
    the regex-versus-comment torture file. IN: `parserExportAssignment6`
    is `declare module "M" { export = A }`, an undefined-name check;
    `parserES5SymbolProperty4` is `[Symbol.isRegExp]`, a lib member
    lookup; `parserCastVersusArrowFunction1` and
    `parserConstructorAmbiguity3` have parse-ambiguity PURPOSES and
    ordinary DIAGNOSTICS (TS2403 on nine conflicting `var v`, TS2558
    type-argument arity), which is not the same thing. Plus the three
    already known not to be legacy (`parserParameterList16`/`17`,
    `parserClassDeclaration12` — the TS2371/TS2394 overload rules, Tier 2).
  - **`using` declarations, 5 of 6.** ZERO occurrences in 5,697 real
    files, the strongest out-of-scope case here; revisit if a real
    dependency adopts explicit resource management. But a file NAMED for
    `using` can carry an error `using` has nothing to do with:
    `usingDeclarationsWithObjectLiterals2` is TS7018 on `value: null`,
    which a plain `const` reproduces under the same two flags (probed), so
    it is Tier 2's implicit-any family and stays in scope.
  - **locally accepted, 6.** TS7 errors and local tsc 6.0.3 accepts, so
    there is no oracle to develop against and no way to write the
    legal-neighbour test this repo requires of every rule. The only
    out-of-scope reason here that is a HARNESS limit rather than a
    judgement about the language — revisit when the local compiler moves.
  - The one thing that keeps this from rotting into a suppression list:
    the oracle reports **STALE** entries — a listed path that is no longer
    a MISS, because a rule landed or the file left the corpus. Proven by
    adding a bogus path and seeing it named.

### The recommendation that is not a rule — DONE

- [x] **Two MISS numbers.** `MISS in scope 143` (the backlog, which can
  reach zero) beside `OUT OF SCOPE 19` (declared). `--scope-file /dev/null`
  reproduces the old single 174 — verified, not asserted.
  Nothing but the MISS branch consults the scope file, so a listed file can
  still be a TP, an FP or a PFLEGAL exactly as before: being out of scope
  withholds a rule, it does not excuse a wrong answer. The FP budget is
  untouched at 0.
- [x] `just verify-checker-soundness` gains `--max-miss`, which closes
  a direction NOTHING watched: a rule that stops firing moves a file from
  TP to MISS, and every other number in the report absorbs that silently.
  Lower the budget whenever a batch improves it, the way the FP budget only
  ever tightened.
