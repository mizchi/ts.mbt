# typescript.mbt

A bridge-generation toolchain between TypeScript and MoonBit, written in MoonBit.

## Current Goals

This project focuses on three goals:

1. Parse a usable subset of TypeScript declaration files in MoonBit.
2. Make TypeScript -> MoonBit bridge types safe and ergonomic, primarily for `vite-plugin-moonbit`.
3. Improve the TypeScript declarations emitted for MoonBit-generated code.

The wasm interpreter / codegen / AOT path that originally lived in this repo
has been removed. Bridge generation and `.d.ts` normalization are the only
product surfaces now.

## Purpose Notes

- `src/parser` is the foundation for parsing TypeScript / JavaScript and
  resolving module structure (npm `exports`, `typesVersions`, `node:*`,
  `@types/*`, etc.).
- `src/checker` is the TypeScript type-system layer: structural classification
  (`classify_optional_like_union`, `classify_transparent_intersection`),
  assignability (`is_assignable_to` and resolver / generic / bivariant /
  diagnostic variants), three-valued `extends_decision`, infer pattern matching,
  distributive conditional reduction, generic substitution, alias-name
  predicates, `simplify_type` / `simplify_union`, the standard TS utility-type
  table (`Exclude` / `Extract` / `NonNullable` / `Awaited` / `ReturnType` /
  `Parameters`), and module-level validation
  (`unresolved_type_references`, `check_module`).
- `src/transform` is the JS-side pipeline behind `mtsc`: bundling, folding,
  tree-shaking, and the property mangler. Its safety story is type-driven and
  has two halves — `export_surface.mbt` (names reachable from the entry's
  exports) and `mangle_safety.mbt` + `flow_analysis.mbt` (names that reach a
  side-effect sink). The sink half is fail-closed: `callee_provenance.mbt`
  treats a call whose callee it can't prove bundle-internal as a hand-off
  across the boundary, and `pure_builtins.mbt` is the allowlist that keeps
  ordinary built-in calls from poisoning everything that flows through them.
  Both halves feed the reserved set that gates
  `--mangle-properties` and the dead-property pass. The DCE side has its
  own proof obligation instead: `purity.mbt` decides which internal
  functions and host statics are effect-free, and `treeshake.mbt`
  deletes a call only once that proof clears it. Every pass and what it
  has to prove is catalogued in
  [`docs/minify-patterns.md`](./docs/minify-patterns.md); see also
  [`docs/mangle-safety.md`](./docs/mangle-safety.md) and the
  `fixtures/mangle-safety` corpus (`just verify-mangle-safety`), which
  compiles each case with and without mangling, runs both bundles under Node,
  and treats any observable difference as a safety violation. Every case
  has an independent oracle — the original TypeScript run by Node — with
  exactly one declared exception (`case09b-decorator`, where transform
  mode cannot compile a TypeScript-legacy decorator, and which says so).
  Three cases had silently lost theirs and the harness had been printing
  "reference run unavailable" on every run: a value-form import of a type
  (`import { T }`, which TypeScript accepts and transform mode does not),
  the legacy `module X {}` keyword, and that decorator. Each was one
  fixture line, and each left its case comparing mtsc against mtsc, which
  is consistency and not correctness — the exact failure mode that let
  five scope-narrowing bugs survive thousands of fuzz seeds, sitting
  inside the corpus everything else leans on. The two compilation
  questions moved to unit tests, where they belong. A corpus only
  covers situations somebody thought of, so `just verify-real-world`
  minifies real published packages (React, the TypeScript compiler) and
  diffs their behaviour — see [`docs/real-world-minify.md`](./docs/real-world-minify.md).
  That runs each target under the one shipping flag set, which says
  *whether* the pipeline is broken but not *which pass*, so
  `just verify-pass-lattice` runs all sixteen combinations of
  `{treeshake, fold, minify, mangle}` over the 9 MB compiler: a
  combination that fails while each of its parts passes is an
  interaction between them, and that is how the single-use inliner's
  conditional-move bug was located. None of that reaches the case nobody
  imagined, so `just fuzz-mangle`
  generates programs from seeds, compiles each with and without mangling,
  and compares what they observed; a failing program is shrunk to its
  minimum automatically rather than reported as a seed number — see
  [`docs/mangle-fuzzing.md`](./docs/mangle-fuzzing.md). That comparison
  is a self-comparison, and for a long time it was the whole oracle:
  two mtsc outputs agreeing is consistency, not correctness, so a pass
  wrong BEFORE mangling is wrong identically in both legs and every
  seed reports "equivalent". That is not a hypothetical — it is how the
  five scope-narrowing bugs below survived thousands of seeds and were
  found by reading source instead. The original program, run by Node,
  is now the oracle for every generated program rather than only for
  the ones where the two legs already disagreed, and the generator
  emits the shapes those passes key on (`const enum`, a type guard, a
  literal-union dispatcher, an `as const` table) each read once
  normally and once through a scope that re-binds its name. Reverting
  either fix reproduces the bug as a two-node artifact. Node's default
  strip-only type stripping refuses `enum`, which made the reference
  leg silently unavailable on exactly the shape that is wrong with no
  optimization flag — `--experimental-transform-types` is what the leg
  needs, in this harness and in the corpus one. Transform mode brings a
  hole of its own, whose diagnostic points nowhere near the cause: Node
  22.22's SWC drops the parens around a comma expression whose first
  operand is an object literal, so
  `(({ ...obj, g: 1 } ? 1 : 2), (a--))` re-prints with `{` at statement
  start, the block that opens swallows the `...obj` as a rest
  parameter, and 23 of 6019 seeds lost their oracle to "Rest parameter
  must be last formal parameter" on a program that is valid as written
  and that mtsc compiles correctly. A leading `0,` does not rescue it —
  SWC drops a constant first operand of a discarded comma too — but
  `void` does, being an operator rather than a discardable operand.
  Its first 400 seeds
  with the new oracle found two bugs nothing else had: `as_const_inline`
  descended into a `delete` operand and read `obj['q']` there as a safe
  keyed read, so `delete obj['q']` compiled to `delete 1` and every
  later read folded to the stale value; and seven fold sites treated
  `is_js_truthy` / `is_js_falsy` as a licence to DISCARD the condition,
  which it is not for an object or array literal (truthy whatever is
  inside it, and the inside still runs) or for `void EXPR` (falsy
  whatever `EXPR` is). A program covering all seven lost seven of its
  eight calls under `--bundle --fold`. The one that survived was the
  `if` statement — which already had the guard, and a comment crediting
  the fuzzer's effect trace for it. Seventh time in this pipeline that
  one rule was written in several places and fixed in one. mtsc's own
  checker rejects a literal in condition, logical-operand and unary
  position, so that class is reachable only with checking off — the
  published-`.js` path — and lives in `fold_wbtest.mbt` rather than the
  corpus, which type-checks its sources. Sites eight and nine of the
  same rule turned up later, both spelled `return void EXPR` — one in
  `fold.mbt`, one in `peephole.mbt` — where a recursive
  `return void f0(a, z)` lost its recursion, the call-budget counter
  never ran down, and every call returned `undefined` where the source
  eventually returned `0`. And the pattern is not confined to that one
  rule: `x += 1` -> `x++` was written out at four sites in `peep_expr`,
  and every one was the wrong operator — `x += 1` evaluates to the NEW
  value, `x++` to the old, so `(arr[0] += 1) ? a : b` with `arr[0]` at 0
  took the wrong branch. `++x` is the same three bytes, so nothing was
  ever traded for it. A later 1200-seed export-shape campaign found the
  same coercion-vs-purity family once more, in the UNARY operators, and
  this time a TEST was pinning the bug in place. `-(-x)` -> `x` and
  `~(~x)` -> `x` were both gated on `is_pure_value`, which says nothing
  about the ToNumeric each operator applies: `-(-"alpha")` is `NaN` and
  the rewrite handed back `"alpha"`, `~~1.5` is `1`, `~~"alpha"` is `0`.
  `fold_wbtest.mbt` asserted that `~~n` folds to `n` for an unannotated
  `n` — directly below the `x | -1` test that gets the same question
  right, because the earlier bitwise round fixed the BINARY operators and
  stopped at the unary ones. A third rule in the cluster,
  `-(a - b)` -> `b - a`, was DELETED rather than gated: the two differ at
  zero (`-(1 - 1)` is `-0`), nothing there can prove `a - b != 0`, and
  the same file explains why `-0` matters twenty lines above, for
  `(Neg, IntLit(n))`. The sign of zero needs checking at every arithmetic
  rewrite, not once. The rule-equivalence harness had no case for any of
  the four unary forms — including the one that is CORRECT, `!!x` in a
  condition, which has a case now so nobody "fixes" it — and its domain
  held no non-integer at all, so any rule that TRUNCATES rather than
  preserves could pass on integers alone; `1.5` and `-1.5` are in it now.
  All three hunt
  code we delete and should not; `just verify-dce-coverage` hunts the
  opposite — code we keep and could drop — as a table of small programs
  that each assert a marker is gone, the live markers survive, and stdout
  still matches Node running the original. Orthogonal to all of them,
  `just verify-rule-equivalence` asks the narrow question about each
  rewrite on its own: every peephole/fold rule becomes a function body
  with holes, evaluated across a cross product of counterexample values
  (`undefined`, `-0`, `NaN`, a Symbol, a BigInt, an object with a
  poisoned `valueOf`, an array-like with a negative `length`) and
  compared against Node running the source directly. It found nine
  rewrites that assumed a type and checked nothing, and later six more:
  the harness covers the rules somebody wrote a case for and reports
  nothing about the rules that have none, so `Array.from(x)` -> `[...x]`
  shipped for months three lines below a comment explaining why the same
  rewrite on `Array.prototype.slice.call` had been removed. Every rewrite
  whose validity depends on the receiver's type now has a case; the
  built-in-method family is the whole of that subset, and gating it cost
  ~700 bytes across four corpus targets. A third round found the same
  shape once more, in the array-literal folds: a `Spread` element was
  counted as one position, so `[...array].reverse()` — a one-element
  literal, and reversing one element is a no-op — compiled to
  `[...array]` and remeda's `reverse` became a shallow copy. Each of
  those folds already had an `is_pure_value` guard that could not help,
  because a spread of a variable is perfectly pure; position was the
  question, not purity. The `.length` fold had been given a spread guard
  by the fuzzer and the lesson stopped at that one call site. A fourth
  round found the family with NO case at all: not one bitwise rule was
  covered, and six of them were wrong. `x & -1` -> `x` reasoned that
  AND with all-bits-set is the identity — true of the AND, but the
  operator also COERCES and the rewrite hands back the uncoerced
  operand, so `"alpha" & -1` is `0` and compiled to `"alpha"`. The
  fuzzer found it through `switch ("alpha" & -1)`, which selects
  `case 0` and ran the `default` instead. Same shape in `x | x` -> `x`,
  `x - x` -> `0`, `x ^ x` -> `0`, `x & 0` -> `0`, `x | -1` -> `-1` and
  `x ** 0` -> `1` (the last four swallow a BigInt/Symbol TypeError
  rather than a value). And `is_number_valued` — the numeric gate the
  `Add`/`Sub`/`Mul`/`Div` identities ALREADY had — delegated to
  `cmp_kind`, which calls a BigInt literal `CmpNum`: right for
  relational comparison, the one place the spec lets BigInt and Number
  mix, and backwards for arithmetic, where `5n - 0` throws. One
  definition fixed, not seven call sites. The four self-operand rules
  were deleted rather than gated: once the gate is right a bare `Var`
  can never satisfy it and nothing that can is a bare `Var`, so the
  pattern would be dead code that reads like live code. A fifth round
  found the domain itself incomplete: it had carried an object with a
  poisoned `valueOf` — the COERCION hazard — from the start, and never a
  getter, the READ hazard. `is_pure_value(PropAccess(recv, _))` was
  `is_pure_value(recv)`: pure whenever the RECEIVER was, which is a
  statement about evaluating `recv` and not about reading a property off
  it. Four rules therefore dropped a getter's body under
  `--bundle --treeshake --fold` — a bare `h.p;`, `void h.p;`, the left of
  a discarded comma, and the array-literal `.length` fold — so a getter
  that counts, memoizes, logs or lazily initializes stopped running.
  The sound answer costs +845 bytes on TypeScript's 3.5 MB output
  (0.02%), 255 FEWER on checker.ts, and nothing on hono, valibot or the
  terser corpus, which is far too little to justify a type-driven "this
  receiver's declared shape has no accessor" exception. Two lessons
  about the harnesses came with it. First, a case has to land the
  assertion in the COMPARED VALUE: two of the four new cases returned
  `[n, a.hits]` and passed while the optimized body visibly read
  `[2, a.hits]` instead of running the getter — coverage-shaped and
  proving nothing until they returned a scalar. Second, the fuzzer had
  emitted getters for months and could not reach the bug, because it
  spelled the read as `new C().g` (whose receiver is impure, so the read
  never was) and never in a value-discarded position; binding an
  instance to a `const` and emitting the discarded position directly
  took it from 0 findings in 600 comparisons to 21 in 209. See
  [`docs/rule-equivalence.md`](./docs/rule-equivalence.md). And
  `just compare-terser` asks the
  competitive version of that question: both optimizers start from the
  same unoptimized JS, and a LOSS names a terser compress rule we have
  not ported, while a LOSS *or a tie* on a `type-aware` case means the
  type-driven pass did not fire — see
  [`docs/terser-parity.md`](./docs/terser-parity.md). It stands at
  32 win / 0 loss, and getting there is a caution about reading a
  harness's own labels: of the seven rules it named, only one was
  missing as named. The last loss was labelled `computed_props`, and
  that rule was ported and firing — the real two bytes were the
  mangler renaming an exported `o` to `a`, the same length, saving
  nothing and paying five for `export{a as o}`. Renaming an
  export-clause name costs `len(new) + 4` and saves
  `(len(orig) - len(new))` per site, and only the single-character case
  needs no cost model: the saving is exactly zero, so it loses for any
  reference count and any name the mangler picks. That case is ported
  (zod -78 bytes, everything else byte-identical). The GENERAL rule was
  implemented, measured, and dropped: the optimistic bound
  `(len - 1) * sites < 5` gave -54/-40/-63/-231/-36/-3 on six targets
  against +291 on remeda and +267 on typebox, a net loss of about 168
  bytes. Reserving a name also withholds it from the generated pool, so
  the most-used identifier can lose its one-character slot, and that
  dominates the alias it saves — the arithmetic is a bound, not a
  model. `typeofs` was already implemented and simply
  never ran, because peephole is what BUILDS `void 0 === void 0` and
  the fold that collapses it sits in `fold-2`, one phase earlier.
  `negate_iife` was not about negation at all but about splicing a
  side-effect wrapper's body out. `loops` was `sequences`, where the
  comma is free and the two braces it lets you drop are the entire
  win. And 3 of `if_return`'s 11 bytes were a regression of our own:
  a method shorthand is stored as `("p", FuncExpr { name: "p" })`, so
  the mangler's "drop the name of any function expression that does
  not reference itself" turned `p(){…}` into `p:()=>{…}` on every
  object literal with a method. Restoring the name unconditionally
  then cost 7 bytes elsewhere, because a single-`return` body really
  is shorter as `p:a=>a` — the rule has to compare the two spellings,
  not prefer one.
  Every harness above asks whether a pass is *correct*; `just
  measure-type-aware` asks whether the type-driven half is *worth
  anything*. It cannot use published `.js`: the six type-reading phases
  (`predicate-inline`, `switch-fold`, `as-const-inline`, `tag-rewrite`,
  `class-method-dce`, `type-fold`) fill their tables from parsed
  TypeScript, so on erased JS the answer is zero by construction. So each
  target is a package cloned from git and optimized twice with identical
  flags — once from the TypeScript source, once from the same code with
  its types erased — with all three legs required to observe the same
  thing. The answer so far is uncomfortable and worth knowing: across
  NINE measured targets — every one behaviour-checked, no `size-only` and
  no `BLOCKED` rows left — there is **one win**: typebox at +247 bytes
  (0.21%), seven neutral, and one loss inside a byte of the noise floor
  (-0.11% on Excalidraw). zod was the tenth and is out: its bundle makes
  eight `Reflect.ownKeys` calls plus four `Object.getOwnPropertyDescriptor(s)`
  ones, which enumerate NON-enumerable properties — exactly what a class
  prototype method is — so class-method DCE is suppressed there by
  construction and no amount of type information changes the answer. Be
  precise about what that costs, because it is easy to overstate: zod's
  own report also says "nothing would have been dropped anyway", so the
  reflection is not what made zod NEUTRAL. It was a permanent zero for a
  permanent reason at the price of the corpus's slowest run, and the four
  bugs it found are covered elsewhere (`verify-graph-walk` for the module
  walk; fixtures for the erased-`as` arrow parens, the type-only
  namespace entries and the merged interface-and-function case). Both of the numbers that moved came from
  attributing them per pass rather than arguing about them:
  `--disable-phase` prices each type-reading phase on its own, and it
  said `predicate-inline` was costing typebox 261 bytes — which was
  typebox's entire LOSS. The pass's `removable` flag asked "is this name
  in the entry's export list?" and called that "can the declaration be
  deleted?"; typebox's guards leave through a linker-synthesized
  namespace object, so every one of them read as removable, every body
  got copied, and not one declaration was deleted (836 functions before,
  836 after). Counting non-call references instead — a call is the only
  mention inlining rewrites, so the declaration dies only when calls are
  the only mentions — took the phase to 0 and flipped typebox to the
  corpus's first WIN, while leaving the two targets the pass does pay off
  on (superstruct +29, remeda +26) untouched. Four of the six
  type-reading phases moved zero bytes on all ten targets, and "zero"
  is two different findings wearing one number — the shape is absent
  (nothing to fix) or the shape is there and a gate refused it (the
  reason names the fix). The byte count cannot tell them apart, so
  `tag-rewrite` now says which: `--explain-mangle` reports the alias
  count, the multi-variant-union count, and the SHAPE of each rejected
  variant. The first answer was "gate too closed", and by a wide
  margin: `object_string_literal_fields` returned `None` for anything
  but an inline `Object(fields)`, so `type Shape = Circle | Square` —
  how real code declares a union — was rejected before any safety gate
  ran, and every union in all ten targets died there (typebox: 51
  named-reference variants, immer: 19, ts-pattern: 9). Resolving a
  named reference through the interface table, `extends` included,
  produces candidates at last: typebox `keyword` (31 tags) and
  `~kind`, zod `code` and `type`, excalidraw `type` and `status`,
  ts-pattern `type`. Generic arguments need no substitution — a
  discriminant is always `Literal(_)` and a type parameter is
  `Named(T)`, so `Circle<Meters>` and `Circle<Feet>` agree on
  `kind: "circle"` for free. The bytes are still zero on all ten, and
  that is now a fact about those libraries rather than about the pass:
  typebox's `keyword` reaches a sink and its `~kind` leaves through
  `TDeferred`'s exported signature. Opening the gate first meant
  fixing what opening it would have spread. `tag_rewrite` did not look
  at exports AT ALL — `grep export tag_rewrite.mbt` was empty — and it
  rewrites a property's VALUE, so `export const c: Shape = { kind:
  "circle" }` compiled to `{ kind: 0 }` under plain
  `mtsc --bundle --fold` and a consumer's `c.kind === "circle"` was
  false, demonstrated with a separate consumer module. The bundle's own
  escape-sink scan cannot see that; the comparison is outside it. The
  mirrored direction is as real: with only
  `export function area(s: Shape)` crossing, the CONSUMER builds
  `{ kind: "circle" }` and the bundle compares it against `0`. Gating
  on `exported_surface_props` was tried and was wrong — that set
  answers the mangler's "may this NAME be renamed", follows a called
  function's body, and reserves `kind` for
  `export const out = area(shapes[0])` where the consumer only ever
  sees a number; it broke a legitimate test, which was the correct
  signal. A value rewrite needs the narrow fact: an exported
  declaration's own value (a function's RETURNS, not the closure —
  `expr_mentions_k` taints every closure, so passing the initializer
  kills the pass for any bundle exporting a function) plus the type
  names in its signature, which is the only way to see the direction
  where the consumer constructs the value. Third time this exact split
  was needed, after `class_method_dce` against
  `collect_externally_visible_props`. Both facts arrive as one
  REQUIRED positional `TagRewriteBoundary?`, the way
  `class_method_dce_block` takes its `off_bundle`: a labelled default
  would fail open here, since an empty `externals` means fewer SINKS
  rather than fewer candidates.
  `fixtures/mangle-safety/case49-tag-rewrite-export-boundary` runs both
  directions under Node, and its first draft had ZERO detection power:
  it observed `unitCircle.kind === "circle"` computed inside the
  bundle, and a comparison rewritten alongside its literal stays true,
  while a plain `.kind` read elsewhere closed the prop-uses gate so the
  pass declined for an unrelated reason. Every observation is an
  exported OBJECT now, and with the gate mutated off the case reports
  `{"kind":0,"r":1}` against the baseline's `{"kind":"circle","r":1}`.
  The other three inert phases got the same treatment, and the answer
  was different for each — which is the argument for asking per pass
  rather than reasoning about "the type-driven half". `switch-fold` is
  SHAPE ABSENT: seven of the nine targets contain not one function whose
  first parameter is a closed string-literal union, and the three
  candidates in the other two are false positives of that entry test —
  the report names them now, because a count never says what to look at.
  typebox's `LiteralBooleanMapping` / `WithBooleanMapping` have no
  `switch` at all (`return T.Literal(Guard.IsEqual(input, 'true'))`) and
  both call sites pass `_0 as 'true' | 'false'`, a runtime value, so
  widening the BODY gate cannot help: the call-site gate needs a
  `StringLit`. excalidraw's is a class `constructor`, which no widening
  can replace with an arm expression. Deleting the pass is equally wrong
  — it is the only thing that wins the terser-parity
  `switch-literal-union` case, a `type-aware` case where a TIE already
  counts as a failure — and its one historical bug, the name-keyed table
  taking the outer dispatcher's arm for a call to a shadowing parameter,
  is covered under Node by `case43-table-shadowing`. So: kept unchanged,
  with the measured reach and both reasons written into its header, so
  the question is not re-litigated. `type-fold` is the
  opposite and the more interesting one — 578 candidate sites across
  the corpus (zod 181, excalidraw 163, remeda 128) and ZERO decided.
  That is not a lookup failing; it is a TAUTOLOGY. A programmer writes
  `typeof x === "string"` or `x === null` exactly when the annotation
  does not settle it: zod's sites are `typeof val === "string"` on
  `unknown`, excalidraw's are `insertionIndex === null` on
  `number | null`, remeda's are `param === undefined` on
  `T | undefined`. Flow-sensitive narrowing would not help, because
  the check IS the narrowing. The report breaks the total down by
  shape for exactly this reason: "0 of 578" is only actionable once
  you can see that 320 of them are `typeof` on a union.
  `class-method-dce` already had a report, and it said the same thing
  on all ten targets — SUPPRESSED by a computed member read that is
  "neither provably numeric nor an entry of a keyed container",
  `points[i]` / `elements[index]` / `value[index]`. Probing the
  spellings one at a time found exactly ONE that fails, and it is the
  commonest array idiom in JavaScript: a CALLBACK parameter carries no
  annotation, so `arr.map((v, index) => arr[index])` leaves `index`
  unprovable, and since the suppression is a bundle-wide wildcard, one
  such read keeps every method of every class. A `for` counter, a
  `while` counter, a `for…of` binding, a parameter annotated `number`
  and a `readonly number[]` receiver are all already proven. The fix
  needs the receiver proven to be an array before it can claim the
  second parameter is an index — `Map.prototype.forEach` is
  `(value, key, map)`, `Set`'s is `(value, value, set)`, and an
  imported receiver could be either — and a false "numeric" claim
  breaks property-mangle correctness.
  That diagnosis was WRONG, and the way it was wrong is the lesson:
  the failing shape and the failing PROOF were different things. What
  actually fails in `arr.map((v, i) => arr[i])` is the RECEIVER, not
  the index — `numeric_vars` and `container_vars` both skip any
  binding marked `captured_by_closure`, so the arrow's mere mention of
  `arr` kept it from being proven a keyed container, and either proof
  alone would have opened the gate. The guard's stated premise is a
  WRITE from a frame the pass does not follow, and no frame may write
  a `const`: modules are strict, so an assignment throws rather than
  landing a non-numeric value, and the values the binding can hold are
  exactly its defs, which the walk already checks. Exempting `const`
  clears every spelling; the `for`/`while`/`for…of`/annotated-parameter
  spellings had always worked because they were never captured, and
  the shape of the index was never the variable.
  `fixtures/mangle-safety/case50-const-captured-by-callback` pins it
  under Node, and putting `area` in its `expectKeep` failed the
  corpus's own mutation self-check — correctly: a method called only
  from inside the bundle may be renamed, so "it still runs" is the
  behavioural comparison's job, not `expectKeep`'s.
  It still buys ZERO bytes on all ten targets, and a census in the
  report says why in numbers — `(bindings of this name that are
  provably numeric / all bindings of it)`. Three kinds of blocker:
  `key`-style string keys correctly refused (excalidraw 0 of 34,
  typebox 0 of 53); `i`-style numeric keys defeated by
  `numeric_name_set`'s NAME-level all-or-nothing projection
  (excalidraw's `i` is 64 of 90, so 26 unprovable bindings disqualify
  every `arr[i]` in a 95-file bundle); and real reflection —
  `Reflect.ownKeys` x8 and `Object.getOwnPropertyDescriptors` x2 in
  zod, which can never be proven away. Adding `ObjectLit` to
  `is_expr_container` clears zod's top blocker
  (`TypeDictionary[issue.expected]`, 53 occurrences) and was
  implemented, measured and REVERTED: zero bytes, because the
  suppression is all-or-nothing and 53 of 80 blockers is the same as
  none, against a `__proto__` / `Object.setPrototypeOf` exposure not
  yet closed. The design problem is the bundle-wide wildcard itself —
  one `Reflect.ownKeys` anywhere keeps every method of every class —
  and the fix that would pay is per-receiver suppression, the same
  reasoning `class_members_reachable_off_bundle` applies at the bundle
  boundary. Filed, with the numbers, rather than started at the tail of
  a session. What DOES ship from that investigation is a warning, because
  reflection is the one blocker the author rather than the compiler has to
  act on: `mtsc` now says so by default rather than behind
  `--explain-mangle`. It is deliberately narrow in three ways. It fires
  only for the reflection tier — an unprovable computed key is the
  compiler's problem to improve and blaming the author for it would be
  wrong. It fires only when the suppression actually COST a method:
  reflection in a bundle whose every method is reachable anyway lost
  nothing, and a warning naming a loss that did not happen is a warning
  people learn to ignore — zod is exactly that case, eight
  `Reflect.ownKeys` calls and "nothing would have been dropped anyway".
  And it is silent when the JS itself is going to stdout, where the line
  would land inside the program; `--warn-reflection` forces it on there,
  `--no-warn-reflection` off anywhere. `unreached_class_methods` is one
  function read by both the report and the warning, because a cost
  computed separately from the report is a cost that can disagree with
  it. The property
  mangler was reported inert on
  every library measured, and that turned out to be one bug rather than
  a limit: a `const f = (…) => …` had no entry in the graph's function
  table, so a call to one was treated as opaque and marked `External` —
  which IS the wildcard, so a single arrow suppressed property mangling
  for a whole bundle. Giving an arrow its declared name as an identity
  moves real bytes (hono -9.4%, neverthrow -2.6%) and removed one of the
  three LOSSes. It is still SUPPRESSED by the wildcard on six of the nine
  targets — typebox, immer, ts-pattern, superstruct, remeda, excalidraw,
  every large one — and the obvious next move was to narrow that
  wildcard: every reason reported on typebox came from ONE site
  (`External` observability with no closed type annotation), the
  reservation's blast radius is plainly too wide (an unknown-typed
  binding means the names on THAT binding are unknown, not that every
  name in the bundle is reachable), and each hazard it was covering has
  its own separate wildcard already. Implemented, measured on both
  binaries directly, and REVERTED: typebox 119,686 either way,
  excalidraw 279,800, remeda 28,533. Zero bytes, in exchange for
  loosening the riskiest pass in the repo. The premise was wrong and the
  evidence had been on screen the whole time — the reserved-set
  breakdown prints BELOW the `SUPPRESSED` notice, and a `grep -A 12` had
  been cutting it off. It reads: external 54, host-shaped 39, and
  **`reaches a side-effect sink` 340**. That last set already covers what
  the wildcard covered, which is why removing it changes nothing. Nor is
  `SUPPRESSED` the same as inert: `--mangle-properties` still saves 247
  bytes on typebox under the wildcard, because the notice means "no
  USER-DECLARED property name is renamed", and the dead-property pass and
  the discriminant renumbering are neither.
  The 340-name sink set was the next suspect, and it is not the blocker
  either. Every reserved name now carries the FACT that reserved it,
  grouped and ranked, and the section labelled "reaches a side-effect
  sink" turns out to name its smallest contributor: 293 of the 333 names
  are the keys of linker-synthesized namespace objects
  (`export * as ns from …` becomes `const ns = { exp1: resolved1, … }`).
  Those were identified by SHAPE — "a `const` initialized to an object
  literal of bare `Var`s" — which also matches every
  `const handlers = { onClick, onBlur }` and every dispatch table a
  library writes; the linker knows which bindings it created, so
  `LinkRenames` carries `synthesized_namespaces` now and the analysis
  uses the fact, with the guess kept only as the no-information fallback
  because it over-reserves. The guess was over-reaching by 7 names on
  typebox, not by 293 — much less than a first reading of the report
  suggested. And the ceiling settles it: with the pre-pass reserving
  NOTHING, typebox is 119,686, excalidraw 279,800, remeda 28,533,
  byte-for-byte identical, so the whole 293-name reservation costs zero
  because those names are reserved by another route anyway. Two plausible
  narrowings of the reserved side, implemented and measured, both zero:
  the reserved sets are not the constraint. What the mangler CONSIDERS is
  the other term of that subtraction and the next question — 247 bytes on
  typebox is a couple of dozen short names against a 120 KB bundle.
  hono (+500 bytes) and zod (+788) *were* wins until the `TypeArgs` fix
  below, which is the point: `f<T>(x)` parses as a wrapper node, nineteen
  passes never peeled it, and the references inside were invisible to
  liveness — so the type-aware leg had been deleting code it should have
  kept, and the wrapper does not exist in erased JS, so the unsoundness
  was exclusive to the type-aware path. Excalidraw, the corpus's only UI
  application and only monorepo, is what found it, along with five holes
  that stopped it bundling at all (`.json` and `.scss` imports parsed as
  TypeScript, a `.woff2` decoded as UTF-8 because the asset check ran
  after the read, tsconfig `paths` not followed through `"extends"`, and
  `from "."` not recognised as relative) and one fixture that had been
  passing by accident — `case08-typeargs`, where an object literal handed
  to an identity function lost its nested keys because only callback
  arguments escaped through a call (`surface_escape_returned_args`).
  Chasing Excalidraw's remaining -1.7% then found the worst bug of the
  three, and it was in the plainest path there is: `mtsc entry.ts
  --bundle`, with no optimization flag at all, deleted every method of a
  class whose call sites are in another module. `class_method_dce_block`
  asks bundle-wide questions and the per-module emit path handed it one
  module, so "bundle" quietly became "this module"; it now takes a
  `scope` (analyse the graph, rewrite the module). That bundle was the
  corpus's *reference* leg, so the -1.7% was mostly a reference that had
  already lost 8 KB of methods — the real number is -0.11%. All three
  legs had agreed with each other the whole time, which is the lesson
  worth keeping: leg agreement is consistency, not correctness. It
  also found the
  reason four popular packages could not be measured at all, and it took
  four separate fixes to clear them: an unmemoized `export_surface.mbt`
  walk that re-escaped a class once per `new` site
  (`surface_should_walk`), a module-graph walk that deduplicated on the
  import SPECIFIER so `./x.js` -> `x.ts` was re-parsed on every visit —
  2^depth on a diamond graph, and why zod could not finish parsing 133
  files in eighteen minutes (`just verify-graph-walk` gates it now), an
  arrow body losing its parens through an erased `as`, and type-only
  exports landing in a synthesized namespace object. zod went from
  BLOCKED to a behaviour-checked win. It also found the one real
  behavioural difference so far — `--mangle` renaming a class whose
  `.name` the bundle reads back — and `observed_names.mbt` reserves just
  the observed names, narrowed by the class hierarchy because
  `this.constructor` in a method of `C` is `C` or a subclass: six of
  eight targets pay 25 bytes or less where reserving every callable cost
  up to +70%. See
  [`docs/type-aware-measurement.md`](./docs/type-aware-measurement.md).
  Every harness above is a differential: it needs a second thing to
  compare against, so it only covers inputs somebody arranged.
  `verify.mbt` (`mtsc --verify`) is the one total check — it re-parses the
  emitted bundle and asks whether every name it reads resolves to
  something, sharing no code with the passes that made the deletions. It
  is deliberately fail-quiet, because a verifier that cries wolf gets
  turned off. Its first run on the corpus turned four silent liveness
  bugs into named free variables, and fixing them found a fifth: plain
  `mtsc --mangle`, no flags, renamed a multi-declarator group while
  leaving a reference that preceded it spelled the old way. Two of the
  four were the same missing `PureCall` arm surfacing as two unrelated
  symptoms — with `TypeArgs` before them, that is twice that a wrapper
  node's fail-open default has cost a soundness bug, and the reason to
  expect a third. See
  [`docs/type-aware-dce.md`](./docs/type-aware-dce.md).
  What none of these harnesses caught is the worst bug in this list, and
  the way it surfaced says why: porting the terser rules meant reading
  `as_const_inline.mbt`'s walker, and it had no scope narrowing at all.
  It resolves a name against one top-level table, so

      const S = ["ok", "warn"];
      function f() { const S = ["x", "y"]; return S[0]; }
      function h(S) { return S[0]; }

  compiled both `f()` and `h(["param"])` to `"ok"` — a wrong VALUE, not
  a free variable or a crash, under plain `--bundle --fold`, and for a
  parameter as readily as for an inner declaration. `call_inline.mbt`
  had solved exactly this and written it up at the top of the file
  ("the table is keyed by name and carried into every scope"); the
  second pass to need it never got it. The narrowing helpers are now
  generic and shared, and the tables the walker carries live in one
  struct so a scope boundary cannot narrow one and forget the other.
  `--verify` cannot see this class of bug — every name still resolves —
  which is the argument for the execution-differential harnesses, and
  the argument against believing the corpus covers a pass just because
  the pass has tests. Finding one was the reason to audit every pass
  that resolves a name against a table, and **four more had it**:
  `const_enum_inline` (wrong under `--bundle` alone, with no
  optimization flag), `predicate_inline`, `switch_fold`, and
  `type_fold`. All five produce a wrong value, none produces a crash
  or a free variable, and `--verify` detects none of them.
  `const_enum_inline`'s keys are dotted paths (`"E.M"`), so its
  narrowing matches the first segment; `type_fold` already had a
  layered `TypeScope` with a `hide` its parameter path called and its
  declaration path did not, so an inner `const` with no useful type
  left the outer annotation visible. `fixtures/mangle-safety/case43-table-shadowing`
  runs all five against Node, pairing each shadowed read with an
  unshadowed one so the fix cannot be "switch the pass off".
  A 3400-seed campaign then found the escape analysis missing two of
  the six ways JS spells an assignment. `sg_record_write_into` was
  called from the four that go through a member expression and from
  neither `Assign`/`AssignExpr` nor any `CompoundAssign*`, so
  `let v: any = 1; v = { ...obj, g14: 100 }; console.log([v])` dropped
  `g14` and emptied `obj`, while the identical program spelled
  `bag.beta = { ...obj, g14: 100 }` kept both — the difference was not
  a judgement about escape but which arm of the walker the statement
  landed in. `--explain-mangle` said it in one line: "reaches a
  side-effect sink" was EMPTY. The same campaign found the parser
  committing to a generic call inside a bracket it had not closed:
  `try_skip_type_args` aborts on a closer it never opened but never
  required its brace/paren/bracket counts to be ZERO where `depth`
  reached 0, so `a < (b > (c))` consumed `< ( b >`, saw the following
  `(`, and left a stray `)` behind as "Expected RParen, got RParen".
  Its last finding is the one place a rewrite duplicated its input:
  a switch whose every case ends in a terminator is lowered to an
  if-else chain, and the chain tests the SCRUTINEE once per named case
  where the switch evaluates it once — so
  `switch ((trace.push(2), obj?.gamma))` pushed `2` twice. That now
  requires a pure scrutinee, which also rules out a value that could
  change between reads. Its last finding was the deepest:
  `class C { m() {} } console.log(new C())` deleted `m` under plain
  `mtsc --bundle`, because `class_method_dce`'s `keep` was the export
  surface and nothing else — the pass had no notion of a class value
  crossing the bundle boundary, so a library bundle was protected and an
  application bundle not at all. The real-world form is the protocol
  methods a library never calls itself: `JSON.stringify` calls
  `toJSON`, `String(x)` calls `toString`, `await` calls `then`. Feeding
  the pass `collect_externally_visible_props` was tried and reverted:
  that set answers the property mangler's question ("may this NAME be
  renamed") and is right to be broader, since a rename must be
  consistent everywhere a name occurs, so it marks a class observed when
  an instance merely appears in an escaping subtree —
  `console.log(new C().live())` reserved everything and three
  dce-coverage cases regressed. Deletion is the stronger claim and needs
  the narrower fact: `class_members_reachable_off_bundle` pins on
  `External` observability alone (every level below it is a KNOWN sink,
  and a known sink invokes nothing arbitrary) plus the fixed
  `sink_invoked_protocol_methods` list, and `class_method_dce_block`
  takes it with NO default, so a caller that cannot answer gets a pass
  that declines rather than one that deletes. Two things turned up
  underneath. `collect_immediate_sources` answered `Unknown` for
  `new C()`, so `const w = new Widget(); register(w)` stopped
  propagating at `w` and never reached `Widget`, while the inline
  `register(new Widget())` did — one program, two spellings, two
  answers, and the spelling that lost is the one real code uses. And
  `analyze_observability`'s worklist scanned every flow edge per popped
  symbol, O(symbols x edges); it already built a reverse index for
  `FuncArg` and none for `SymVal`. That was 40 of the 43 seconds
  `--bundle --mangle` spent on the 9 MB TypeScript bundle, invisible
  while `--mangle-properties` was the only consumer. Indexed:
  43.8s -> 4.7s, and 85.3s -> 7.0s with property mangling on, output
  byte-identical and the type-aware corpus unchanged on all ten
  targets. Seed 1261 itself was a false positive of the harness —
  `console.log`, `util.inspect`, `JSON.stringify`, `String(x)` and
  `Object.keys` all print `C {}` whether or not `C.prototype.m` exists,
  so `fuzz-runner.mjs` reflecting on a prototype at a `console.log` was
  reaching past the program's own sinks. It no longer does in the sink
  shape and still does in the export shape, where a library consumer
  really can call anything; the hazard the sink shape cannot reach
  (`console.log` being its only sink) lives in
  `fixtures/mangle-safety/case45-class-escapes-external`, where a real
  external import receives the instance and calls the method back.
  That protocol list then turned out to stop one step short of the
  ITERATION protocol, and its own comment is where it stopped: it said
  a spread obtains an iterator through `Symbol.iterator`, a computed key
  nothing could drop, without noticing that the object that returns has
  a `next` which is a plain identifier the pass could and did drop. So
  `class C { [Symbol.iterator]() { return this } next() {…} }` with
  `[...new C()]` as its only consumer compiled to a class with no `next`
  and the spread threw. `mangle.mbt`'s built-in reserved list had
  `next`/`return`/`throw`/`done`/`value` under a `// Iterator protocol`
  comment the whole time — renaming was never at risk, only deletion,
  because `class_method_dce` reads a different set. A unit test now
  checks the containment so the two cannot drift again, and
  `fixtures/mangle-safety/case47-iteration-protocol` runs a spread, a
  `for…of` that breaks (so `return` fires) and a generator under Node.
  The same probe-by-hand pass then found the clearest possible case for
  the mangler's reserved list missing from it: `Object.defineProperty`
  hands the runtime an object it reads BY NAME, and three of a
  descriptor's six keys were absent. `get`, `set` and `value` were
  present only incidentally — under Map/Set and the iterator protocol —
  so nothing had ever named the descriptor, and the three flags nobody
  else needed were not there. The breakage was the DEAD-PROPERTY pass
  rather than a rename: `{ value: 1, enumerable: true }` became
  `{ value: 1 }`, and since every `defineProperty` default is `false`,
  dropping a `true` flag inverts it — `Object.keys` silently stopped
  seeing the property, `writable: true` made a later assignment throw in
  the module's strict mode, and `configurable: true` made `delete`
  throw. Dropping a `false` flag is harmless, which is exactly why two
  of the first three probes passed and the shape looked safe.
  `Object.defineProperties`, `Object.create(proto, descriptors)` and an
  accessor pair were all correct already.
  Three constructs the generator had never emitted were probed by hand
  first. Inheritance came back CLEAN across seventeen shapes — override
  dispatch, `super.m()`, a three-level chain, a getter override,
  inherited fields through `JSON.stringify` and `Object.keys`, static
  inheritance, cross-module `extends`, `instanceof`,
  `this.constructor.name` — the one apparent difference being
  `console.log(new Sub())` printing a mangled name, which is
  `observed_names.mbt`'s stated position (it reserves `.name` reads IN
  THE SOURCE; `util.inspect` printing a constructor name is not one, and
  `fuzz-runner`'s `encode` excludes `name` for the same reason). It is
  in the generator now to KEEP it clean, not because it broke. Async is
  deliberately absent: the observation is synchronous, so an `async`
  function's effects land after it and both legs would agree on an empty
  trace — coverage-shaped and proving nothing. Eight await shapes were
  checked by hand instead.
- `src/bridge` consumes `src/checker` for every type-shape decision and runs
  `@checker.check_module` on the synthesized output as a sanity gate. It also
  keeps domain-specific specialization for Node FS / React / Hono / crypto /
  class-shape generation, plus `.mbti` -> `.d.ts` emission for MoonBit-generated
  packages.

## Project Structure

```
typescript.mbt/
├── moon.mod.json
└── src/
    ├── ast/                 # Shared AST types
    ├── parser/              # TypeScript / JavaScript parser + module resolver
    ├── checker/             # Declaration-level TS type system
    ├── transform/           # mtsc pipeline: bundle / fold / treeshake / mangle
    ├── mtsc/                # Checker entry points for the mtsc CLI + JS ABI
    ├── bridge/              # Bridge code generation (both directions)
    ├── main.mbt             # `mizchi/ts` library: bridge entry helpers
    ├── unified_cli.mbt      # `--input ... --out ...` unified driver
    └── cmd/
        ├── ts2mbt/main.mbt  # CLI binary: TypeScript -> MoonBit
        ├── mbt2ts/main.mbt  # CLI binary: MoonBit -> TypeScript
        └── mtsc/main.mbt    # CLI binary: TypeScript -> JavaScript
```

## Dependencies

- `moonbitlang/async` - async file I/O for the CLI.

## Commands

```bash
# Check for errors
moon check --deny-warn

# Run tests
moon test --target native

# Run parser microbenchmarks
moon bench --target native

# Format code
moon fmt

# Generate type definitions
moon info

# Validate `--mangle-properties` against the mangle-safety corpus
just verify-mangle-safety
```

## Notes

- Target: `native`.
- The repo no longer ships a JS interpreter or wasm codegen; entry-point
  parsing is read-only and produces declarations / bridge code only.
