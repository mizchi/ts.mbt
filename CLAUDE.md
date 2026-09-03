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
  Its correctness gate is a differential against **TypeScript 7**:
  `just verify-checker-soundness` runs every single-file conformance case
  through `tscheck` and compares against vendored tsgo baseline manifests,
  with the budget that matters set to zero — a file TS7 ACCEPTS that we flag
  is a soundness bug, and there are none (TP 2468 / MISS 266 / FP 0 /
  PFLEGAL 0 / TN 1750). That gate compares against vendored TS7 name
  lists, so it says nothing about WHAT a rejected file's error was, and
  nothing at all about a hand-written legal neighbour. A real compiler
  answers both: `node_modules/typescript` is 6.0.3, and
  `scripts/tsc_probe.mjs` runs it over a file the way the harness would
  (reading the `// @option:` header). Batch CL diagnosed three wrong
  rules with it and left one alone because of it — `symbolProperty37` is
  in the TS7 error set and 6.0.3 accepts it, so
  `member_name_duplicates`'s claim that duplicate well-known-symbol
  interface members merge legally still holds and the code was not
  touched. 6.0.3 is not tsgo, so a disagreement is information rather
  than a verdict. The asymmetry is deliberate: we model a subset of
  TS, so a MISS is expected and an FP never is.
  That gate says how many we miss and nothing about WHICH, so "MISS 388"
  could rank no work at all — a baseline NAME list says that TS7 errored,
  not what it said. `just checker-miss-buckets` reads the codes out of the
  submodule baselines and buckets the misses by them, cross-checking its
  totals against the gate because a miner that disagrees with the gate is a
  broken miner. Its first run retired a strategy document:
  `docs/checker-priority.md` concluded that incremental sound recall wins
  were exhausted and that only large type-machinery features remained, and
  that was measured against the **TS6** oracle — under TS7, **128 of the
  388 missing files are flippable by a pure-grammar (TS1xxx) rule** and 91
  of them need no type judgement anywhere. Seventeen batches have taken
  **+131 TP at FP 0** so far, and most of their items were BUGS rather than
  missing features — one of them a rule the repo had already written and
  applied to every declaration kind except namespaces. The first:
  `eval`/`arguments` as an assignment target was checked at two of the four
  spellings JavaScript has for writing a binding (`=`, `+=`, `++x`, `x++`),
  so `"use strict"; eval++` parsed clean — tenth instance in this repo of
  one rule written in several places and applied in some. Two harness
  defects came with it, both of the kind this file keeps recording: the
  oracle silently preferred a stale RELEASE binary while
  `verify-checker-soundness` builds DEBUG, so six target files "did not
  change" because the run was measuring code from before the change (it
  picks the newer build now, and prints which); and `moon check
  --deny-warn` cannot gate anything here, since the tree carries 450+
  pre-existing warnings — plain `moon check` reporting `0 errors` is the
  check.
  Two lessons repeat across the batches and are worth stating once. First,
  a rule's LEGAL neighbour is the thing to test: "fires on the corpus file"
  and "stays silent on the legal spelling" are separate claims, and only
  the second keeps the gate at zero — `f(a = 1, b)` (legal) next to
  `f(a?, b)` (TS1016), `set F(v,)` (legal) next to `set F(a = 1)`
  (TS1052), a type ALIAS to `Promise<void>` (legal) next to a `Promise`
  SUBCLASS (TS1064), `type K = string` as an index key (legal) next to
  `RegExp` (TS1268). Where a legal and an illegal form are the SAME node at
  parse time, the check abstains and takes the MISS. Second, an error CODE
  is not a difficulty class: the ~15-file decorator cluster looks like
  cheap TS1xxx grammar and is mostly decorator-signature ASSIGNABILITY
  (TS1240/1241/1270/1329), so the bucket ranking had to be read by opening
  the files — the same "a label stood in for the objective" mistake this
  file records for `computed_props`, `loops`, `typeofs` and `sequences`.
  Batch BY made the ranking itself the object of study, and every step
  contradicted the step before it. The bucket table counts (file, code)
  pairs where the thing that flips is a FILE, so a file with five codes
  inflates all five; `solo` (this code is the only lever) is the honest
  yield, and the best twelve rules cover 33% of the misses. The four
  biggest buckets — TS2322 / TS2345 / TS2339 / TS2304, also the four
  errors real TypeScript users see most — turn out not to need machinery
  at all: `const x: string = 1`, `f(1)` against `f(a: string)`, `o.b` on
  `{a: 1}` and a bare `nonexistent;` are ALL already flagged, so the
  strategy doc is wrong a second way and something specific defeats an
  existing check in those files. And a CODE-keyed cover cannot see a
  FEATURE cluster: `symbolProperty*` spans seven codes and is one
  feature. Grouping by conformance directory shows `parser/ecmascript5`
  at 49 files, the largest and cheapest cluster — and the wrong one to
  take, because its files are `parserErrorRecovery_ParameterList6`-style
  broken syntax nobody writes. Corpus count is not real-world frequency;
  treating it as one is the same substitution. What that batch's rules
  actually cost is recorded in TODO.md, including four REJECTED with
  evidence — among them `override` on a computed name, which is FP 0 on
  the corpus and unsound on legal code, because a `const` string key is
  late-bindable and `class D extends B { override [prop]() {} }` is
  legal when `B` declares it. "FP 0 on the corpus" is not soundness.
  Two of the batch's findings were predicted by this file in writing.
  `TypeArgs` hid `super<T>(0)` from a walker that saw `super(0)` — the
  third wrapper-node fail-open soundness bug, exactly the third the
  `PureCall` entry below says to expect. And the family count is at
  fifteen: TS2335 existed with its helper, message and FP argument and
  read only `constructor_body` of the eight places a class body holds
  code (13th); the modifier-order rule exists for class members and
  `skip_param_modifiers` silently discards `override` (14th); and five
  parser diagnostic channels were dead inside every namespace because
  `if outer_modules.length() == 0` is correct for exactly ONE of the
  seven things it wrapped — a compiler-option file header — and was
  inherited by the rest (15th, and a variation: not one rule written
  twice, but one item's condition applied to six that do not share it).
  TS2466 turned out to be keeping a SECOND hand-written `super` walker
  that was a strict subset of the first, missing ten node kinds
  including `Call(_, args)`, so `[f(super.m())]` walked past it; it was
  deleted and delegated rather than patched arm by arm, since patching
  arms is what produces a pair. The expected yield of the namespace fix
  was large and the measured yield is ONE file, because most earlier
  rules route through `grammar_misuses`, which a workaround already
  re-drained — the value there is the bug class, not the count.
  Batch BZ then took `check_class_implements`, which checks the TYPE of
  an interface member the class declares and never checked that the
  class declares it at all — `interface I { a: number }
  class C implements I { }` was silent. That is NOT the
  applied-in-some-places family, and the correction matters: the doc
  comment stated the abstention and its blocker in writing ("it may be
  inherited from a base class we don't fully thread here"), so the work
  was removing the blocker, and the walk to remove it already existed
  inside `check_override_modifiers` and was extracted rather than
  copied. The batch is worth exactly **+1** corpus file against an
  estimate of 5, and the gap is the same lesson as the decorator
  cluster with the axis swapped: an error CODE is not a yield class
  either. Four of the five TS2420 MISSes raise that code for unrelated
  reasons — private incompatibility through interface merging, overload
  assignability, a numeric indexer — and only opening the files showed
  it. The reason to ship it is what the corpus cannot show: forgetting
  to implement a member you just added to an interface is what a person
  does, and a conformance suite written to exercise the type system
  contains almost none of it. Its whole cost was the legal-neighbour
  surface, and SCANNING the accepted corpus beat imagining cases —
  exactly 9 TS7-accepted files carry `class … implements`, and two of
  their shapes (a well-known-symbol key, a namespace-scoped parameter
  property) were missing from the case list written from first
  principles. A third route came from re-reading rather than probing:
  class/interface declaration merging, where `interface C { a: number }`
  beside `class C implements I {}` supplies the member — the shape every
  `.d.ts` uses, so missing it would have false-flagged the bridge's own
  primary input.
  Batch CA is the sixteenth instance and buys **zero** corpus files on
  purpose. `let x; let x`, `const x = 1; const x = 2`,
  `let x = 1; var x = 2` and `class C {} class C {}` were ALL silent while
  `let x = 1; function x() {}` was flagged — from the same loop, over the
  same statement list, in `check_function_var_duplicates`, which compared
  each top-level binding's name against `module_.funcs` and never against
  the other bindings. Its own comment is where the omission shows: it
  justifies excluding `var`+`var` (a merge) and function overloads (which
  legally repeat a name) and then excludes `let`+`let`, which is neither.
  No scope walk was added — only the flat `Ident` forms of
  `top_level_stmts` are read, so a nested block, a destructuring pattern
  and a `for` head all fall through, each losing a finding rather than
  inventing one. The four files in the bucket are outside that stated
  scope (a duplicate inside one destructuring pattern, an array pattern in
  a `for` head, class auto-accessors, local TYPE declarations), which is
  why the count is 0; the reason to ship is that `mtsc` type-checking
  accepted `let x; let x`, a program tsc rejects. The standard applied is
  the repo's own: the rejections recorded above were changes measurement
  showed did NOT achieve their purpose, and this one does — 7 firing
  spellings against 11 silent legal neighbours. TS2393 and TS2394 are
  blocked on one mechanical fact and say so: `TsFunc.body` is not
  optional, so an overload SIGNATURE and an implementation cannot be told
  apart, which is also why `check_overload_void_return` has to guess that
  the last declaration is the implementation.
  Batches CF and CG are ten more grammar rules for **+19 files**, and they
  are where the BY ranking INVERTS — under "MISS <= 250" the corpus COUNT
  is the objective, so `parser/ecmascript5`, which BY correctly rejected
  as broken syntax nobody writes, becomes the largest and cheapest
  cluster. The family count reached 22 (`parse_binding_ident` reserved
  `let` and `yield` in strict mode and not the other seven, so
  `class C { constructor(static) {} }` parsed clean in an automatically
  strict body) and 23 (`await using` has THREE declaration sites — a
  statement, a block-statement, a for-head — and the pre-existing TS2854
  marker was at one, so `{ await using d = null }` inside a block, which
  is how every `awaitUsingDeclarations` test is written, could never reach
  it; one helper is now called from all three). Where a per-call-site fix
  would have meant threading a new field through fourteen save / clear /
  restore sites, the fact went into the DATA instead: TS1115 needs to know
  whether a label is on an iteration statement, and the kind is encoded in
  the label-stack entry so it rides along through an opaque copy.
  **Three of the ten were corpus FALSE POSITIVES first**, and all three
  are the legal-neighbour lesson again. TS1106 is a LOOKAHEAD restriction
  rather than a semantic one — it exists so `for (async of …)` cannot be
  read as the start of `for await (… of …)` — so `for await (async of x)`
  and `for ((async) of x)` are both legal, and the AST cannot tell the
  parenthesized form from the bare one because the binding parser strips
  parens, so the TOKEN is what gets checked. And `export type R = number`
  makes a file a module: the module-syntax evidence set had been built
  from the export shapes that bind a VALUE, so
  `usingDeclarationsDeclarationEmit.2` — TS7-ACCEPTED, two `export type`
  aliases and nothing else — read as a script and its top-level
  `await using` was flagged. The marker now sits at the `export` KEYWORD
  in all three export parsers rather than on the forms that happen to need
  it, because a marker written at the form is a marker written at one of
  them.
  Batch CH is +7 and contains the one rule here a working TypeScript
  programmer hits regularly: `module`, `require`, `process`, `__dirname`
  and six siblings are NOT in the default `lib` set — they come from
  `@types/node` — and all nine sat in the generated lib-global allowlist,
  so a `.ts` file using CommonJS with those types missing was accepted in
  silence (TS2591). The allowlist itself is unchanged, because its seven
  other consumers ask "could the platform have provided this name" and for
  those the conservative answer is still yes; only `check_undefined_name`
  splits the two questions, and only after every declaration lookup has
  run. It also half-retires a blocker this file records: `TsFunc.body`
  being non-optional really does block TS2393 / TS2394, but
  `last_function_bodiless` already carries the fact at PARSE time, so
  TS2391's pairing question was always answerable there. The way to get it
  wrong is recorded too, because it cost a false positive: a pending run
  of signature names carried across statements gets flushed by
  `parse_stmt`'s view of "the next statement is not a function", which
  includes the statements inside a nested function BODY — so a legal
  three-signature set inside another function was reported the moment the
  implementation's own `return null;` was parsed. A lookahead from the
  signature needs no scope model, where a scope-saved field would have had
  to be threaded through every save/restore site around a function body.
  The same round produced the clearest case yet for pairing a rule with
  its legal neighbour in a TEST rather than trusting the corpus: batch
  CD's TS1117 had shipped a false positive, because `{ … }` in expression
  position is a COVER GRAMMAR — an object literal only until an `=`
  follows, at which point it was an object destructuring PATTERN and
  duplicate names in it are legal. The oracle reported FP 0 with the bug
  present, since `destructuringSameNames` contains illegal spellings too
  and was a TP whichever half fired; the unit suite caught it, because an
  earlier batch had written those three legal shapes down as cases.
  Batch CI is +5 off one rule and one design decision. `++this`,
  `++await 42`, `++1` and the `++(++y)` that ASI makes of
  `x \n ++ \n ++ \n y` are all rejected by tsc and none was flagged; the
  check rides on `record_assign_target_strict_misuse`, the function batch
  BU built for the four write spellings, so there is no fifth place to
  forget. It is a DENYLIST rather than the complementary allowlist on
  purpose: "anything that is not `Var` / `PropAccess` / `IndexAccess`" is
  the correct rule and the wrong implementation, because a target can
  arrive wrapped in nodes that say nothing about writability (`TypeArgs`,
  `As`, `Satisfies`, `PureCall`) and this file already records three
  soundness bugs paid for a wrapper node whose default arm failed open. A
  denylist fails the other way, costing a MISS rather than a false
  positive.
  Batch CJ is +6 and entirely in the LEXER: six rules that were each a
  missing case in a loop which already had an exit for the well-formed
  shape — end of file inside a block comment (TS1010), a radix prefix
  with no digits at all (TS1125, three arms and the rule in none of them,
  because `invalid_radix_digit_count` answers the different question "a
  digit outside this radix"), a keyword spelled with a unicode escape
  (TS1260 — the escape decodes to a legal identifier, so `\u0076ar x = 1`
  scanned as the `var` KEYWORD), a regex crossing a line (TS1161, without
  which `/ b;` scanned to EOF and swallowed the file), and unbalanced
  regex groups (TS1005). The sixth has the only judgement in it: `¬`
  (U+00AC) parsed clean because non-ASCII goes to the identifier scanner,
  which over-approximates ID_Continue as "any code unit >= 0x80" so that
  `変数` and `π` scan as one token. That approximation is right, and
  without a Unicode table "not an identifier character" is what cannot be
  decided in general — so TS1127 covers the one block where the answer is
  knowable (U+00A1..U+00BF plus `×` and `÷`) and excludes the three code
  points in it that ARE ID_Start (`ª`, `µ`, `º`) plus the non-breaking
  space and soft hyphen. Everything from U+00C0 up keeps the permissive
  treatment, so `café` still scans as an identifier.
  Batch CK is +3 and its mistake is worth more than its files. `await` /
  `yield` in an ENUM member initializer needed its own rule because the
  corpus file puts the enum inside an `async function*`, where both
  operators are legal — an enum initializer is a constant-expression
  position, so nothing that suspends belongs in one whatever the
  enclosing function is. The other rule, a legacy decorator on a
  `#private` member, cost TWO corpus false positives first:
  `autoAccessorExperimentalDecorators` combines `accessor` and
  `#private`, gating on `accessor` looked equally plausible, and it
  flagged `@dec accessor prop` and `static accessor y = 1`, both
  TS7-ACCEPTED. The baseline errors on exactly the two PRIVATE members,
  so the private name was doing all the work and the auto-accessor none
  of it — the same substitution as the `computed_props` label and the
  decorator-bucket ranking, reading a two-feature file's error as
  belonging to whichever feature caught the eye first.
  Batch CL is +11 and its most durable output is the ORACLE rather than
  any rule, because it settled two questions the gate cannot reach. The
  first was strategic and had been guesswork: running the whole corpus
  with the permissive filter entirely OFF flags **8 of the 277 MISS
  files** at a cost of 49 false positives, so the suppression was never
  the thing holding recall back — five of those eight are suppressed for
  good reasons and the other 269 files are ones where the checker
  computes nothing at all. The second was per-rule: every
  legal-neighbour claim in this file had been an argument, and
  `scripts/tsc_probe.mjs` makes it a measurement by running the real
  6.0.3 compiler in `node_modules` over a probe file under its own
  `// @option:` header. It earned itself back three times over — `const
  prop = "foo"` versus `let prop = "foo"` is exactly where TS4127's line
  falls (so batch BY's rejection was right, and the rule is now filed
  with its condition rather than its verdict); `namespace M { var Symbol
  … }` is TS2454 while the same line at script top level is not; and
  `symbolProperty37` is in the TS7 error set yet 6.0.3 ACCEPTS it, which
  is why `member_name_duplicates` was left exactly as it was.
  The rules themselves are three more instances of the same two
  families. TS2348 for a class called without `new` needs no inference
  (a class's static side cannot carry a call signature, and neither
  declaration-merging route can add one), and carving it out of the
  "not callable" suppression exposed what that filter had been hiding
  for however long: `is_definitely_not_callable` had an unconditional
  `Object(_) => true` arm, so `declare var q: { (): number }; q()` — an
  object type whose entire purpose is a call signature — was "not
  callable", invisibly, because the family was dropped wholesale. That
  fix has to be asserted through the STRICT entry point, since in
  permissive mode the wrong answer and the right one both look silent.
  `check_static_uses_class_type_params` read a static member's return
  type and parameters, which is where a SIGNATURE carries types and not
  where code does — a static method's BODY and its computed KEY are two
  more positions, and the body is the one real code uses. And
  `record_objlit_duplicate_keys`'s doc comment recorded
  `symbolProperty36` as a deliberate MISS with a blocker (only the class
  key path resolves a well-known symbol to a stable `@@<name>`, and
  renaming the object-literal key would move keys the mangler reads) —
  true of the approach it considered and beside the point, since the
  parser already wraps a computed entry's VALUE as
  `ComputedProp(key_expr, value)` and the key expression was in hand.
  Second time after batch BZ that a stated abstention's own comment
  named the thing to remove.
  Two of the batch's rules were WRONG in their first form and the corpus
  caught both, which is the legal-neighbour lesson twice more. TS2466
  exists for CLASS member keys, so extending it to OBJECT-LITERAL keys
  reads like the applied-in-some-places family and is not: an
  object-literal computed key may legally mention `super`, three
  TS7-ACCEPTED files say so, and it cost 6 false positives for 2 true
  ones. `computedPropertyNames28` is `30` with the object literal
  directly in the constructor instead of inside an arrow, and tsc
  accepts it — modelling a distinction ONE file draws is fitting the
  corpus, so `30` stays a MISS and the reason lives at the site. And IIFE
  arity is one-DIRECTIONAL: a literal callee's parameter list is right
  there in the source, which looked like the same exact fact a function
  declaration gives, and checking both directions cost 4 false positives
  for 1 true one because an IIFE's parameters are contextually typed —
  passing FEWER arguments than parameters is legal and they come out
  `undefined`, which `contextuallyTypedIife` states in a section headed
  "missing arguments". Too many is still TS2554.
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
  yet closed. The design problem looked like the bundle-wide wildcard
  itself — one `Reflect.ownKeys` anywhere keeps every method of every
  class — so the filed next step was per-receiver suppression, the same
  reasoning `class_members_reachable_off_bundle` applies at the bundle
  boundary. That is CLOSED now, and by measuring its ceiling before
  writing any of it, which took one command: the report's
  `unused class methods` section already says how many methods a
  suppression COST, and that is the exact upper bound on any narrowing.
  Eight of the ten targets never reach the suppression at all — the
  early exit added below says `nothing to do — every declared method is
  read somewhere static or is on the export surface` — so the sentence
  above, "it said the same thing on all ten targets", is no longer
  true. The whole corpus-wide ceiling is **14 methods**: excalidraw 5,
  hono 18 declarations of 9 distinct names, zero everywhere else. And
  hono's nine are not headroom, which is the finding that matters:
  `HonoRequest.param` / `parseBody` / `valid` / `queries` / `blob` /
  `bytes` / `matchedRoutes` / `routePath` / `addValidatedData` are the
  public API an application spells as `c.req.param("id")`. Reading them
  as unreachable was an export-surface HOLE, so opening the gate would
  have shipped the bug and the wildcard was the only thing stopping it.
  Four holes, all in one walk, each one enough to make
  `mtsc entry.ts --bundle` — no optimization flag — delete a method a
  consumer goes on to call. `index_prop_assigns`'s doc comment says it
  indexes `NAME.prop = value`, and that one spelling was all it
  indexed: a compound assignment through a property
  (`NAME.prop ??= v`, `||=`, `&&=`) had no arm, and that is how real
  code writes a lazily-created member — hono memoizes `#req`,
  `#matchResult` and `#path` exactly that way, and a consumer got
  `TypeError: c.req.param is not a function`. Nor did
  `NAME["prop"] = v`, which is the same write spelled differently. A
  key we cannot spell (`NAME[k] = v`) can reserve no name but its value
  still leaves inside the object, and goes under the `@@computed:`
  sentinel `is_opaque_object_key` already existed for. Third,
  `surface_lookup_member` resolved `bag.prop` against the object
  literal's own entry — `undefined` — and STOPPED, treating a necessary
  source as a sufficient one; `return bag` was always fine, because
  widening to the whole object routes through the `prop_assigns` loop,
  and that is what made the hole look like working code. Fourth,
  `surface_escape_class` put the value escape INSIDE the
  `is_internal_marker_prop` filter, so a `#private` field's value never
  escaped while the identical PUBLIC field's did — ninth time one rule
  was written in two places and applied in one, and the top-level
  `prop_assigns` loop sixty lines above had it right. None of the four
  is reachable by a self-comparison: the deletion happens in every mtsc
  leg, so two mtsc outputs agree, and `--verify` sees nothing because
  every name still resolves.
  Fixing the READ half then introduced a NON-TERMINATION, and the memo
  that stops it was already twenty lines away in the same file: a
  recorded write can read the key it writes, which is what an increment
  is, so `const ledger = { n: 0 }` with
  `ledger.n = ledger.n + 1` escaped the write, whose left operand is
  `ledger.n` again. Five lines, 10 ms with `= 1` and never with
  `= ledger.n + 1`; `case36-annotated-boundary` has exactly that
  increment and wedged the corpus, which was misread as CPU contention
  for twenty minutes until `ps` showed three mtsc processes on one
  fixture. `surface_should_walk`'s own doc comment describes this
  failure mode ("did not finish in seven minutes"), and the fix is to
  key it on `(receiver, key)` as well. One ordering matters: `resolved`
  is set from the entry scan BEFORE the memo can decline, or a second
  arrival falls through to the widening and the cycle becomes an
  over-reservation instead of a hang. Two unit tests, and the second is
  the point — a memo keyed on the KEY alone misses the mutual form
  (`a.toB = b; b.toA = a`), where neither write mentions its own key.
  `fixtures/mangle-safety/case60-property-write-spellings` exports each
  holder and calls the method only from `driver.mjs`, outside the
  bundle, so nothing in the bundle names it and the export surface is
  the only thing that can keep it; the comparison is against Node
  running the same TypeScript. Its first draft handed the inner object
  to an `--external` module instead and FAILED — correctly, and the
  reason is worth keeping: an external call routes through off-bundle
  reachability, a different analysis, which attributes the escaping
  value to the HOLDER and not to the class held inside it. The case
  reproduced the bug while proving nothing about the fix, because it
  never exercised the export surface at all. What the case cannot do is
  the other direction — a value comparison cannot observe an absence,
  since the reference leg has the method — and `verify-dce-coverage`
  plus the corpus byte deltas cover that. The cost of widening the
  analysis is ZERO bytes on all ten targets, byte-for-byte, and since a
  zero can also mean "the pass never fires on real code" the confirmation
  is a separate observation: hono's report went from `SUPPRESSED` plus
  `would have dropped 18 unreached method(s)` naming
  `HonoRequest.param` and eight siblings, to `nothing to do — every
  declared method is read somewhere static or is on the export surface`.
  Those nine public methods are on the surface now, which is direct
  evidence the walk follows hono's real `#req ??= new HonoRequest(…)`,
  and the corpus-wide #73 ceiling drops from 14 methods to 5
  (excalidraw alone). The bytes not moving is the same conclusion this
  document reaches from four other directions: the reserved set is not
  large, it is EXHAUSTIVE, so adding a reservation route changes
  nothing. `verify-dce-coverage` is unchanged at 31 eliminated /
  0 broken, which is the check that the widening did not over-reserve.
  What DOES ship from that investigation is a warning, because
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
  the other term of that subtraction, and counting it ends the line of
  work: a census in the report says how many distinct property names a
  bundle has and how many survive to be candidates, and the answer is
  ZERO candidates on typebox (0 of 418), excalidraw (0 of 909), valibot
  (0 of 147), immer (0 of 115), remeda (0 of 96), ts-pattern (0 of 83)
  and superstruct (0 of 54); neverthrow has one and hono six. The
  reserved set is not large, it is EXHAUSTIVE — which is exactly why
  narrowing any single route measures zero, since a name reserved by six
  routes needs all six removed. And the reservations are RIGHT: typebox's
  property names are the JSON-Schema wire format (`type`, `properties`,
  `items`, `$ref`, `allOf`, `pattern`), excalidraw's are the elements it
  serializes to `.excalidraw` files, remeda's belong to the caller's own
  data. Nothing there may be renamed, so the pass being inert is the
  correct answer and not a defect.
  Which leaves hono's -2107 bytes (-9.4%), the number that justified
  putting `--mangle-properties` into the measured flag set. Its six
  candidates are ALL `__private_brand__0__*` — mtsc's own synthesized
  private-field brands, about 24 characters each, 77 occurrences,
  77 x ~27 = the whole delta. Not one USER-DECLARED property name has
  ever been renamed on any measured target; the pass's entire measured
  value is cleaning up after `private_fields.mbt`, which failed to lower
  hono's real `#path` / `#routes` / `#notFoundHandler` back to native
  private syntax. Emitting `#path` is shorter than any mangled name and
  correct by construction, so #79 is the actual fix and the -9.4%
  belongs in the lowering's column, not the mangler's.
  And that turned out to be a leak, not just an attribution error.
  `lower_private_fields` ran ONLY in the merged pipeline, which is gated
  on `--mangle`/`--treeshake`/`--fold`, so plain `mtsc entry.ts --bundle`
  emitted the brand verbatim — and a brand is an ordinary own ENUMERABLE
  property, so `class C { #secret = 7 }` printed
  `{"__private_brand__0__secret":7}` through `JSON.stringify` and showed
  up in `Object.keys`, object spread and `for…in`, where Node gives `{}`
  and `[]`. Adding any optimization flag fixed it, which is exactly why
  nothing noticed: every harness that exercises the per-module emit path
  exercises it WITH flags. Third time a pass has been missing from that
  path; `class_method_dce_block` was the first two. Two of the tests
  pinning the old output ASSERTED the leak — one required
  `__private_brand__` to be present and `#count` absent — because they
  were written against the shape plain `--bundle` happened to produce.
  The second half was the lowering's own guard, which required a brand to
  be mentioned by exactly one top-level statement. That also refuses TWO
  classes each declaring the same private name: the parser numbers brands
  per module, so hono's `Context.#path` and `Hono.#path` are both
  `__private_brand__0__path`, and after linking that brand appears in two
  statements — both of them class nodes that declare it. Each `#x` is
  scoped to its own class body, so renaming both is right, and the count
  refused; five of hono's six surviving brands were this rather than the
  accessor. The guard now asks the precise question — every statement
  mentioning the brand must be a class node that DECLARES it — which
  still refuses the real hazard, a computed-key accessor
  (`get [GET_MATCH_RESULT]()`) that the class lowering hoists out to
  `Object.defineProperty(C.prototype, KEY, { get() { … this.#x } })`.
  hono's `--mangle` bundle without property mangling went 22,317 ->
  21,177 bytes, five of six brands now native, and the leak closed in
  the configuration that had it. With `--mangle-properties` it goes the
  other way, 20,210 -> 20,817: the old smaller number was the mangler
  renaming 24-character brands to one character, and `#notFoundHandler`
  is 16 characters that the mangler declines to touch. Which is itself
  a missed opportunity rather than a cost — a `#private` name is
  class-scoped and cannot be anybody's ABI, so it is the one property
  class that needs no proof to rename — done, and it is worth
  -1,876 bytes on hono by itself (`--mangle-properties` there goes
  20,721 -> 18,845, and against plain `--mangle`'s 20,951 the pass is
  now -2,106, -10.1%). The old skip gave two reasons and only the second
  was real: there is "nothing to hide" (true, and beside the point —
  `#notFoundHandler` is 16 characters and `#a` is two), and renaming
  would "drop the `#`, turning a private field back into an ordinary
  visible property" (true of a bare mint, so the mint keeps the prefix).
  The candidate check runs BEFORE the reserved set, because that set
  answers "can something outside see this name" and for a `#` name the
  answer is no whatever the escape analysis concluded — six of the ten
  measured targets reserve the wildcard, so leaving privates behind the
  check would keep them un-mangled exactly where the pass is otherwise
  inert. Two classes each declaring `#path` both become `#a`, which is
  correct: they are different members, each resolving in its own class
  body. This is also the first crack in "candidate 0 on every library" —
  there is now one candidate class that needs no escape analysis at all.
  `fixtures/mangle-safety/case58-private-name-mangling` is a SAFETY case
  rather than an optimization pin: mutating the rename back off leaves it
  passing, correctly, since declining to rename breaks nothing, while
  dropping the `#` from the mint fails it on all four ways a private must
  stay invisible (`Object.keys`, `JSON.stringify`, spread, `for…in`).
  Writing it turned up two CHECKER holes, both unrelated and both filed
  rather than fixed: `#x in obj` — the ergonomic brand check, and the
  idiomatic class type guard — fails with `cannot find name
  __private_brand__0__path` because the `in` operand is lowered to the
  brand name the checker has no entry for; and `Array.prototype.sort()`
  with no comparator is rejected as `expected 1 argument(s), got 0`.
  Neither is reachable from the corpus because every fixture that would
  hit them was written around them, which is how they survived.
  `just verify-pass-lattice` is the harness that exists to find exactly
  this — a pass present in some flag combinations and not others — and it
  ran the guilty combination (bare `--bundle` is the first entry in its
  table) on every run and reported "15/15 behave identically". Two
  independent reasons, both worth knowing: its target is a PUBLISHED
  `.js` bundle, and `typescript.js` has no `#private` fields, no enums,
  no namespaces and no parameter properties, so NO TypeScript-only
  lowering is exercised by that harness at all; and even with such a
  field present, its only observation is whether `tsc`'s stdout matches,
  which an extra own enumerable property on an internal object never
  reaches. Its reference leg is genuinely independent — the baseline is
  the original `typescript.js` — so this is a coverage gap rather than a
  self-comparison, and the same lesson as the getter cases that passed
  while the bug was present: a harness that runs the right input and
  asks a question the answer cannot reach proves nothing. CLOSED by a
  second table: `fixtures/pass-lattice/lowerings.ts` runs the same
  fifteen combinations over one of every TypeScript-only lowering —
  `#private` fields instance and static, parameter properties,
  accessors, `enum`, `const enum`, nested `namespace`,
  abstract/override — and observes VALUES rather than stdout (own keys,
  `JSON.stringify`, object spread, `for…in`), with Node running the
  TypeScript directly as the baseline, so the reference is the language
  and not another mtsc output. Deliberately NOT a real library: the 9 MB
  target covers the shape nobody thought of, and what was missing was
  the lowerings plus a question the answer can reach — one cheap
  purpose-built compile covers every lowering where a library covers
  whichever ones it happens to use. Re-introducing the historical bug
  fails it and names the leaked brands (`counterJson: "{}" ->
  "{__private_brand__0__count:2,…}"`); the diff names the moved fields,
  because with fifteen combinations and twenty-five observations
  "differs" is not something anyone can act on.
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
  Every one of those rows compiles a library's PACKAGE entry, which is
  structurally unfair to two of the questions: a barrel's exports are
  all live, so tree-shaking has nothing to remove, and a library's
  object shapes ARE its wire format, so the mangler is right to reserve
  every name. `--app` compiles an APPLICATION that consumes each
  library instead, with the usage copied from that library's own README
  rather than chosen — an entry written by the person measuring is an
  entry written to make the passes fire. The answer is that the entry
  does not matter: tree-shaking moves enormously (remeda 28,533 ->
  3,402, valibot 86,982 -> 8,056, excalidraw 279,800 -> 121,114) and
  the six type-reading phases move 54 bytes across the whole corpus,
  975 -> 1,029. Two rows shift and both are small — typebox's
  `predicate-inline` 0 -> 288 (a package entry's guards all leave
  through a namespace object, so inlining never deletes the
  declaration) and excalidraw's `as-const-inline` 920 -> 715 (fewer
  sites in a 57%-smaller bundle, a higher rate). The property-name
  census settles the other half flatly: the candidate count is
  IDENTICAL on all nine targets, and excalidraw sheds 400 property
  names (909 -> 509) without gaining one candidate. Reading
  `--explain-mangle` says why — the reservations were never the export
  surface. ts-pattern's are its own `export * as P` namespace keys
  (x27), its untyped internal `pattern` / `value` / `key` bindings, and
  literal keys handed to sinks: library internals, which an
  application's entry cannot change. Same conclusion this document
  reaches from four other directions — the reserved set is not large,
  it is exhaustive, and it is right. What the exercise DID buy was a
  bug, in the plainest path there is: `mtsc app.ts --bundle` with no
  optimization flag returned the WRONG BINDING for a default-exported
  namespace object. typebox's `src/index.ts` does `import * as Type
  from './typebox.ts'; export default Type`, another module declares a
  top-level `const Type`, phase 1 renamed the namespace object to
  `Type$185` — into `namespace_local_renames` — and `resolve_export`'s
  fallback read only `rename_per_module`, which has no entry for a
  namespace local, so the consumer's import stayed spelled `Type` and
  bound to the unrelated arrow. `Type.Number is not a function`. Eighth
  time a fact written in one place was re-derived incompletely by a
  second consumer, and `--verify` detects none of this class: every
  name resolves, it just resolves to the wrong thing. The package entry
  cannot reach it, because nothing imports a barrel's own default.
  Every harness above measures mtsc against ITSELF or against a
  case somebody wrote. `just compare-terser-bundles` measures it
  against terser on real bundles, same input, and that number was very
  different: `compare-terser` stood at 32 win / 0 loss on 34
  hand-written cases while mtsc was **+51.6% behind terser on typebox**.
  Both true — a case corpus covers the rules somebody thought of. Raw
  bytes now say mtsc is smaller on 5 of 9; GZIPPED it is smaller on 1 of
  9, and gzip is what ships. remeda is −388 raw and **+152 gzipped**,
  which means the bytes removed were bytes gzip would have removed
  anyway, so a harness counting raw bytes scores the wrong thing.
  typebox's +51.6% was ONE `.name` read in a 5,000-line bundle:
  `IsEqual(proto.constructor.name, "Object")`. `observed_names.mbt`
  reserves every callable when a `.name` read's receiver cannot be
  narrowed to a class hierarchy, `proto.constructor` cannot be, and the
  fail-closed answer is the wildcard — 119,933 -> 90,042 with the read
  deleted, 842 top-level functions going from fully spelled out to one
  or two characters. Two changes recover it, both reusing trusted
  machinery. `call_inline` required every ARGUMENT to be pure, which
  since the getter fix excludes every property read, so a one-line
  `IsEqual` helper was never inlined at any call site reading a
  property; that requirement exists to stop duplicating, dropping or
  reordering an argument's effects, and all three are questions about
  the BODY — when it reads every parameter exactly once, in argument
  order, unconditionally, substitution reproduces the call's evaluation
  exactly (`params_read_in_argument_order`, an allowlist so a new node
  declines rather than assuming an order nobody checked). And
  `collect_read_property_names_expr` now recognises
  `<expr>.constructor.name === "lit"` and records the LITERAL instead of
  the reserve-everything sentinel. Recognising it inside the TRUSTED
  walker is what makes the narrowing complete by construction: a read in
  any other position still falls through and still reserves everything,
  so a missed shape costs bytes rather than correctness — the opposite
  fail direction from the sentinel channel itself. Reserving the literal
  does both jobs, because a reserved name is also withheld from the
  generated pool: a class already called that keeps its name, and no
  class can be renamed TO it. typebox 119,933 -> 90,056, +51.3% ->
  +13.8%, gzip +27.1% -> +17.4%, and the other eight targets
  byte-identical.
  The next attribution of that gap said "414 single-call functions mtsc
  keeps against terser's 113, worth ~5,000 bytes if inlined", and the
  experiment says the mechanism is wrong twice over. Only 4 of the 371
  such functions are called in STATEMENT position — the 1% the plan
  proposed starting from — and 313 already have the `return <expr>`
  shape `call_inline` structurally accepts, so a statement body was
  never the blocker. The real blocker was the body-purity REQUIREMENT
  (586 of ~1,000 functions examined on typebox, against 35 accepted),
  which is not needed for safety: the body runs once at the call site
  either way, so what it needs is pure arguments and a size argument,
  not purity. Relaxing it is -26 bytes on typebox and 0 on the other
  eight; relaxing the blanket nested-function refusal (394 more
  candidates, because a one-line TS helper is routinely
  `return xs.map(x => …)`) is 0, because those then stop at the size
  gate; and removing the size gate — the ceiling for any cost model on
  multi-site inlining — is +1,896 on typebox, +1,009 excalidraw, +363
  superstruct, +306 ts-pattern, +208 hono. A node-count cost model was
  swept and has no positive region (K=4 already loses 208 on hono). All
  of it reverted.
  What DID pay came from measuring the output a different way:
  `compare-terser-bundles --names` counts identifier lengths in
  VARIABLE positions, and 5,165 of typebox's 11,228-byte gap was
  identifier CHARACTERS — with 828 four-character variable identifiers
  against terser's four, in a bundle where neither has exhausted length
  3. A mangled-name distribution cannot look like that, so those were
  names the mangler declined to rename, and they were one name: `type`,
  824 times, as in `function a6(type, a = {})`. Cause:
  `mangler_builtin_reserved` is consulted by `ScopeFrame::bind` for two
  different questions at once — which names the pool may not GENERATE
  (its purpose: globals and reserved words) and which existing bindings
  may not be RENAMED. `type`, `namespace`, `declare`, `abstract` and
  `readonly` are TypeScript CONTEXTUAL keywords and legal JavaScript
  variable names, in strict mode too, so listing them only ever cost
  bytes; `interface` / `implements` / `private` / `protected` /
  `public` / `static` / `enum` are reserved in strict mode and a module
  is strict, so they stay. Dropping the five: `typescript.js` -13,613,
  typebox -2,440, react -1,939, excalidraw -236, valibot -99, immer
  -45, superstruct -8, nothing larger — about -18.4 KB, and typebox's
  gap +14.2% -> +11.1% with mtsc now smaller on 6 of 9 raw.
  `fixtures/mangle-safety/case56-contextual-keyword-bindings` covers
  the safety side under Node: each of the five declared, read, closed
  over, shadowed by a parameter, shadowed again in a nested function,
  exported, alongside object KEYS of the same spelling that must not
  move. The first version of that identifier count was itself the trap
  this file keeps recording — every `Identifier` node in the TypeScript
  AST includes property names, so typebox's JSON-Schema `type` key
  showed up 856 times and the column was mostly not identifiers at all.
  The remaining 2,701 characters are 421 fewer one-character names,
  1,499 more two-character ones, and 1,091 more identifier occurrences,
  and that is a PASS-ORDER question rather than a missing pass: terser
  inlines and then mangles, so every deleted declaration frees a
  one-character slot, while mtsc has spent its names before `inline`
  runs.
  Writing the case for that found a WORSE bug underneath, and it was
  pre-existing: `try_inline_trivial_call` substituted parameters ONE AT
  A TIME, so a later parameter's substitution rewrote a name an earlier
  one had just introduced. `const add = (a, b) => a + b` with a
  top-level `let b = 3` compiled `add(b, 1)` to `b + b` and then
  `1 + 1` — three call sites returning 2 / 200 / 14 where the answers
  are 4 / 103 / 10, under the shipping flag set, with no crash and no
  free variable, so `--verify` cannot see it. Both arguments are pure,
  so it had nothing to do with the relaxation above. What makes it the
  normal case rather than an exotic one is the pass ORDER: the mangler
  runs BEFORE inlining, so parameters are named `a`, `b`, `c` and so are
  the top-level bindings the arguments mention. Fixed by substituting
  simultaneously, as two phases through the existing one-name
  substitution via a `@@inline-arg:<i>` placeholder no identifier can
  equal. It is pinned by a UNIT test rather than a corpus case, and that
  was decided by measurement: the fixture written first still PASSED
  with the fix mutated out, because end to end the collision needs the
  mangler to hand a top-level binding the same short name as a later
  parameter, and there it did not. A case that cannot fail while the bug
  is present is coverage-shaped, so it was deleted rather than shipped.
  `--rules` then asks TERSER to price its own compress rules — run it
  once per rule with that rule off — which is the ceiling for porting
  each one, known before writing any of it. It corrected a ranking made
  by COUNTING: mtsc emits 9x fewer comma-fused statements than terser
  (valibot 322 vs 36), so `sequences` looked like the biggest gap;
  priced across nine targets it is +1,500 bytes and sixth of eight,
  while `join_vars` is +15,522 (+1,875 gzipped) and `conditionals`
  +8,774. Same failure mode as `computed_props`, `loops` and `typeofs`
  before it — a label or a count standing in for the objective — except
  this time it was caught before the work.
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
  All five of those are about the table's KEY, and there is a SECOND
  half that nothing asked for a long time: dropping the entry whose key
  a scope re-binds says nothing about the names the substituted VALUE
  reads, and those get re-resolved wherever the value lands.
  `const base = Number(process.argv.length); const f = () => base;
  function g() { const other = 99; return f() + other * 0 }` printed 99
  where the answer is 2, under the full shipping flag set. The mangler
  runs BEFORE the inline phase and gave `base` and `other` the same
  short name `a` — legitimately, since at mangle time `g`'s body does
  not mention `base`, so shadowing it is free — and then the inliner
  spliced a body whose `a` is the outer one into a scope where `a` is
  99. No crash and no free variable, so `--verify` cannot see it, and
  the better the mangler does its job the more often it fires. Four
  tables substitute a value that can carry free variables and none
  checked: `call_inline`, `as_const_inline` (both halves),
  `predicate_inline`, `switch_fold`; `const_enum_inline` and
  `type_fold` substitute literals and are safe by construction. The
  fix is in the shared helper, and the obligation is a TRAIT rather
  than an optional predicate — a table whose value type cannot answer
  does not compile, where a defaulted "mentions nothing" would fail
  open and the next table added would be the fifth. Free names come
  from `collect_var_refs_expr`, the mangler's own walker, which has no
  fail-open catch-all because the mangler's correctness depends on its
  completeness. Two of the four could be demonstrated end to end;
  `as_const_inline` and `predicate_inline` run BEFORE the mangler, so
  the mangler cleans up after them and no witness could be produced —
  they are covered by construction and by a unit test at the pass
  boundary, and are NOT claimed to be broken.
  `fixtures/mangle-safety/case55-inlined-value-free-variable` pins it
  under Node and fails when the value half is mutated off.
  The SEVENTH instance is in the LINKER, and it is the last place the
  question had not been asked. Phase 2 records
  `subs[local_alias] = resolved` and phase 3 rewrites `Var(local_alias)`
  to `Var(resolved)` inside the importing module; the walker tracks
  shadowing of the name it REPLACES and cannot track shadowing of the
  name it SUBSTITUTES, because that name is not in the map it narrows.
  `@sprawlens/viz`'s `App.tsx` has
  `import { parentFileOf as contractParentFileOf }` and, in the same
  component body, a local `const parentFileOf` — correct as written,
  two different names. `contractParentFileOf` appears ZERO times in the
  bundle: every use became `parentFileOf`, which there is the local
  `const`, and `ReferenceError: Cannot access 'parentFileOf' before
  initialization` under plain `mtsc --bundle` with no optimization flag.
  A 265-file preact application bundled and could not run. The other
  half of the same capture is silent — when the shadowing declaration
  has already initialized there is no TDZ, just the local function's
  answer instead of the import's, which `--verify` cannot see either.
  The fix is NOT a scope walk at the rewrite site: a walk has to model
  every binder form and the cost of missing one is this bug returning
  quietly. Instead, phase 2 already computes `resolved != local_alias`,
  which IS the hazard condition, so a phase 1.5 forces the exporting
  binding to a MINTED name whenever it holds — `name$N` is not a name
  source code declares, so no scope can shadow it and no analysis is
  needed to know that. Only bindings imported under a different alias
  move, and with `--mangle` the names are replaced anyway, so the
  corpus is byte-identical.
  `fixtures/mangle-safety/case57-aliased-import-shadowed-target` runs
  four shapes under Node — the TDZ form, the silent wrong-value form, a
  PARAMETER named after the target (no block declares it, the same trap
  as `case43`), and an unshadowed control that must still reach the
  import so the fix cannot be "stop substituting" — and fails under
  mutation. `@sprawlens/viz` now goes 875,544 -> 357,712 bytes (59%)
  and renders an identical DOM optimized and not.
  It is the corpus's tenth target and its first real APPLICATION —
  `packages/viz/src/main.tsx` mounts a preact app, exports NOTHING, and
  spans 162 TypeScript sources across four workspace packages — and it
  answers the question the other nine could not. The type-reading phases
  are worth +10,419 bytes (2.81%), +2,491 gzipped there, against
  typebox's +216 and zero on six of the nine libraries: the whole
  library side of the corpus adds up to under twelve bytes. Feeding
  `.ts` is what buys it — the erased leg is 380,833 against the typed
  leg's 370,414 — which is exactly the difference `verify-real-world`
  cannot see, because published `.js` makes the answer zero by
  construction. For the property mangler the answer is still NO (743
  distinct property names, 0 candidates, the same suppression), and the
  REASON is the finding: on a library `--explain-mangle` names the
  export surface and the wire format, which are correct and unfixable,
  while here every cause reads "binding X crosses the bundle boundary
  and carries no closed type annotation" — `readSearch`, `parsers`,
  `url`, `onPopState`, `node`, `cell`, `edge`, `id`. An application's
  boundary is not its exports; it is the DOM and framework APIs it hands
  objects to, which is a boundary a type annotation can narrow.
  Getting it to run cost four bugs, none of them reachable by a
  library-shaped target: tsconfig `jsx` / `jsxImportSource` /
  `jsxFactory` were never read; `BundleOptions.jsx` was ignored by
  `load_module_graph`, so `--jsx-import-source` was dead in the bundle
  path and a preact app compiled to `react/jsx-runtime`; the linker
  capture above; and `for (var u; …)` — a declaration with no
  initializer, in ordinary JavaScript out of preact's own source — came
  out as `for (var u = __ts_no_init__; …)`, which throws a
  `ReferenceError` the moment the loop runs. `omit_declaration_init`
  says in its own doc comment that the marker "has to be dropped in
  every mode", and the block-statement emit, the declarator-group emit
  and the multi-decl for-head emit all call it; the single-declaration
  for-head arm wrote `= <init>` unconditionally. Eighth time one rule
  was written in several places and applied in one, so the three kinds
  now share one path.
  Two harness defects came with it. `countSources` counted only `*.ts`,
  which is every library in the corpus and 26 of viz's 126 files. And
  `--only X --update` REPLACED `expected.json` with a single row,
  silently deleting the nine recorded baselines — a regression check
  whose baseline a convenience flag can erase is not a regression check.
  `--update` merges now and reports how many rows it carried over.
  The linker fix itself costs
  nothing: `typescript.js` byte-identical, the nine type-aware targets
  −76 bytes net (typebox +327 and excalidraw +150 against ts-pattern
  −345, immer −192, hono −16, because fewer inlines leave the
  single-use binding inliner and treeshake a better shape), and the
  `inline` phase 397 -> 351 ms.
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
  The four export-surface holes above are the newest entry in the same
  ledger, and the reason they survived thousands of seeds is three gaps
  in the grammar: `mutableTarget()` has no `this.<field>` arm, so
  `this.slot ??= new Payload()` — hono's real `#req ??=`, and the way
  ordinary code writes a lazily-created member — was ungeneratable; its
  index arm targets `arr` with a NUMERIC literal, never `obj["p"]`; and a
  class instance was never written into a property whose holder is then
  observed, so the export-surface route was never taken. `lazyHolderGroup`
  emits a payload class whose ONLY route to a consumer is one property
  write, rotating over `??=`, `||=`, `this["slot"] =`, a read-through
  object (carrying the self-referential increment that made the fixed
  walk hang), and plain `=` as the control — without which "fixed" and
  "switched off" look alike from outside. It needed NO runner change:
  `encode` already walks an exported instance's own fields and reports the
  inner object's prototype members, and the payload is deliberately NOT
  exported, since exporting it would put its members on the surface
  directly and the write would stop being the only route. Detection comes
  from the REFERENCE leg, the deletion being present in every mtsc leg.
  Proven the only way that counts — against the compiler with the fix
  reverted it reports at SEED 0, shrunk 107 nodes to 6 and correctly
  attributed as a lowering rather than a mangling bug — and 700 seeds are
  clean with the fix in. The `#private` spelling is deliberately absent:
  `Object.keys` cannot see a private field, so this observation cannot
  reach it whatever the compiler does, and `case61` covers it.
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
  Re-profiling after all of that found the same shape once more, and
  this time the largest item was pure waste. On the 9 MB TypeScript
  compiler under the shipping flags, `class-method-dce` plus its
  reachability phase were 27.8% of a 7,679 ms compile — and
  `--disable-phase class-method-dce` produced BYTE-IDENTICAL output,
  because the pass is SUPPRESSED there by one `all[name]` read in 5,000
  lines and its own report says "nothing would have been dropped
  anyway". Two fixes, both about asking the cheap question first.
  `class_members_reachable_off_bundle` is a full observability analysis
  and ran unconditionally BEFORE the suppression was known, so
  `off_bundle` is a thunk now: `None` still means "the caller cannot
  answer", so the fail-closed property is unchanged — the presence check
  is up front and only the work moved. And sub-phase timing inside the
  pass showed the cost split as symbol graph 485 ms, numeric inference
  226 ms, static accesses 31 ms, container facts 18 ms: the two
  expensive halves exist only to decide whether a computed key COULD
  name a method, which is a question about whether a drop is safe, and
  there is no point asking it when there is nothing to drop. Whether
  there is anything to drop needs only the static-access set and the
  export surface, both SUBSETS of the real accessed set, so "nothing
  unreached" cannot become "something unreached" once the expensive
  analysis adds names. The pass left the table entirely. Then the
  biggest number was `bundle: link + escape + emit`, which is a
  RESIDUAL — the whole bundle call minus the instrumented phases — so
  the largest cost in the compile was being reported as unattributed;
  splitting out `escape analysis` (2,165 ms) also exposed that
  `--explain-mangle` was computing `escape_breakdown` TWICE, once for
  the per-reason report and once through
  `collect_externally_visible_props`, so the merge is a separate
  `merge_escape_breakdown` now. `--mangle` 7,760 -> 5,190 ms (-33%),
  with `--mangle-properties` 11,800 -> 8,230 ms (-30%), excalidraw
  2,400 -> 2,050 ms, output byte-identical in every configuration.
  excalidraw keeps 106 ms of `class-method-dce` — there the early exit
  does NOT fire, which is what selective looks like — and
  `bundle_wbtest.mbt` pins both sides of that boundary. The two
  residuals left after that round are now phases, and a residual is a
  subtraction rather than a measurement, so both were worth the phase.
  One was a real waste: `cli: module graph walk` was not a walk at all
  but the sibling ambient `.d.ts` scan, which next to
  `node_modules/typescript/lib/typescript.js` reads AND fully parses 98
  files and 3.2 MB — where the parse only fills `type_props` and only
  `--reserve-typed-props` reads that. The main loop had exactly that
  gate on its own second parse and the ambient scan never got it; fourth
  time a condition was written in one place and not in the second
  consumer. The other was MY OWN instrumentation: `cli: import edge
  walk` read 358 ms and looked like the largest item on a 95-file
  target, but it was a plain wall-clock bracket while the resolution
  sub-spans accumulated INSIDE it — the spans OVERLAPPED, so module
  resolution was counted twice. An overlapping span is not a small
  error, it is a wrong number that reads like a finding, and it sent the
  investigation at the wrong function; the right answer was already
  written in `main.mbt` ("module resolution, not parsing, was the
  largest phase on every multi-file target"). Made disjoint, the edge
  walk is 7 ms and the largest row is `cli: resolve module paths` at
  331 ms — 53 ms of relative path arithmetic against 272 ms of bare
  specifiers, and `module_resolver.mbt` had no cache of any kind. The
  first fix bought exactly ZERO: memoizing the ANSWER, keyed on (mode,
  importing file, specifier), because the key HAS to include the
  importer (a nested `node_modules` can resolve one specifier two ways)
  and 68 importers of `clsx` are 68 distinct keys that share nothing.
  The repeats were real and the memo could not see them: what repeats
  across importers is the WORK, not the question. Memoizing the work —
  `@fs.kind`, file text reads, `@fs.realpath` — is what paid, and the
  text read is where it was: `resolve_tsconfig_specifier` runs per bare
  specifier per importer and re-read every config from disk each time,
  twice per level (once for `paths`, once for `extends`), over a
  two-level `extends` chain. 272 -> 71 ms, excalidraw 1,536 -> 1,405 ms
  (-8.5%), byte-identical. Splitting `bundle: link` (51 ms),
  `bundle: emit` (231 ms) and `observed-names` (48 ms) out of the other
  residual takes it from 1,744 ms / 20.1% to 247 ms / 5.1% — sixth row
  rather than first, and what is left is statement concatenation and
  inter-phase bookkeeping, which is now known to be cheap rather than
  unmeasured. The profile that comes out the far side says the
  optimizer is no longer the question: `mangle` and `peephole` are
  30.4% of a 4.8 s compile and both are real work, while reading,
  tokenizing and parsing are 27.6% between them. See
  [`docs/real-world-minify.md`](./docs/real-world-minify.md).
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
