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
  is a soundness bug, and there are none (TP 2669 / MISS in scope 46 /
  OUT OF SCOPE 19 / FP 0 / PFLEGAL 0 / TN 1750). That gate compares against vendored TS7 name
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
  of them need no type judgement anywhere. Twenty-four batches have taken
  **+181 TP at FP 0** so far, and most of their items were BUGS rather than
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
  --deny-warn` could not gate anything, since the tree carried 450+
  pre-existing warnings — plain `moon check` reporting `0 errors` was the
  check. **That is no longer true: `--deny-warn` is clean and IS the
  gate.** The cleanup is worth two notes. The count everyone quoted was
  wrong by 40%, because `src/checker/moon.pkg` carried
  `warnings = "-0020-0035-0082"` — suppressing exactly the three
  diagnostics the cleanup was about, in the largest package in the repo,
  under a comment saying the work would be "performed separately". 814
  became 1,376 the moment it came out; a suppression nobody can see past
  is the defect that retired `docs/checker-priority.md`, in a `moon.pkg`.
  And a spelling has to be PROBED before it is applied in bulk: `!` binds
  the whole postfix chain (asserted by VALUE, since `(!m).contains` is a
  type error on a `Map` and so proves nothing about precedence),
  `String::substring` returns an owned `String` where `s[a:b]` is a view
  (so every site is `s[a:b].to_owned()`), and `try?` is NOT mechanically
  `Ok`/`Err` — the compiler's own guidance says so, and 147 of the 148
  were one best-effort-cleanup idiom. The renames take this repo's own
  convention rather than inventing one: `module_`, `type_`, `class_` and
  `enum_` are spelled that way at 5,022 sites for exactly this reason.
  Two of the twelve leftovers were not warnings at all. `export_surface`
  matched `MethodCall(Var(n), meth, args)` BEFORE
  `MethodCall(Var("Object"), "defineProperty", args)`, and the generic
  pattern also matches the specific call — so every
  `Object.defineProperty(NAME, "prop", …)` write was invisible to
  `index_prop_assigns`, which its own doc comment says it indexes, and
  the compiler had been reporting it as unreachable code all along.
  `callable_arity_range` was dead because
  `check_member_decorator_signatures` computes its `(lo, hi)` INLINE —
  it needs `is_optional` and `default`, which a `TsType` cannot carry, as
  that function's own comment explains — so the helper could not serve
  the rule its own header names.
  The same family lives in the GENERATOR, where it reached the product:
  four functions answered "does this MoonBit value identifier need a `_`
  suffix", and the three answering it for a whole identifier had THREE
  different contents (74 / 74 / 65 words), the bridge copy missing nine
  the extern copy had — so one TypeScript name could come out `method_`
  in `externs.mbt` and `method` in `bridge.mbt`. Fourteen reserved words
  were missing from all of them, `extend` among them, which put six
  warnings in every user's build of the vitest example. The set was
  probed (273 candidates declared as bindings, keeping the ones that
  warn; two rounds were needed, so it may still be short a word nobody
  guessed). The FOURTH list is NOT the same rule, and unifying it is what
  `verify-examples` caught: `to_snake_case` feeds `sanitize_identifier`
  and its output is sometimes a whole identifier and sometimes a FRAGMENT
  that gets composed (`"get_" + to_snake_case(value.name)`), so a word
  that collides alone cannot collide inside `get_<word>` — the wider list
  renamed vitest's public `get_assert` to `get_assert_` for a collision
  that cannot happen. Its narrower list is restored with that reason at
  the site. What stays un-fixed in the generated output is stated rather
  than silently left: ~1,080 `Array`-in-JS-FFI deprecations and ~450
  phantom type parameters are a `FixedArray` migration and a generated-
  API question, not warning cleanup.
  `moon fmt` HAS now been run, and the drift it had accumulated was 73
  files / 828 insertions. Most of it is one rule — this formatter wants a
  trailing comma inside a single-line record literal, so
  `{ ..self, census: out }` becomes `{ ..self, census: out, }` — which is
  exactly the disagreement CI's fmt step used to document as
  unresolvable, resolved in the direction CI wanted because the tree was
  formatted with `latest` (moon 0.1.20260915 / moonc v0.10.13), the same
  formatter that step runs. Four things were checked before taking it,
  and the first is the one that mattered: **`fmt` touched not one `#|`
  line**, so the TypeScript sources embedded in the whitebox tests are
  byte-identical — a formatter that re-indented those would have changed
  what the tests assert, silently. It is IDEMPOTENT on its own output (a
  second pass diffs identically, measured rather than assumed), every
  change is under `src/` so no checked-in fixture moved, and all 36
  golden CLI cases are byte-identical across the reformat.
  `moon fmt --check` passes now and **IS a gate** — the step's
  `continue-on-error` is gone. What changed is the policy rather than the
  comma: `latest` is the reference formatter, which is what the two steps
  around it already track and what the tree is now formatted to, so a
  contributor's pinned toolchain is not a second reference to reconcile
  with. That is the condition a gate needs, because both ways the check
  can go red become actionable — the formatter moved, or somebody
  reformatted with an older pin, and the fix for either is to re-run
  `moon fmt` on `latest` rather than to hand-edit commas. The cost is
  stated at the step: the next `latest` formatter change reds every open
  pull request until someone does that, which the
  20260819 -> 20260915 gap suggests is months apart, and
  `continue-on-error: true` is a one-line revert if it is ever the wrong
  trade. Pinning CI's MoonBit is NOT the revert, since it trades away the
  early toolchain warning the surrounding steps exist for.
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
  run. That rule is also the one that broke a harness nobody thought to
  re-run, and the class of mistake generalizes: a new CHECKER rule is a
  new way for every harness that TYPE-CHECKS ITS OWN FIXTURES to start
  failing, and `verify-mangle-safety` compiles all 185 of its cases
  through `mtsc`. Two of them read `process.argv.length` — deliberately,
  because a literal would be folded away before the passes under test
  ran — so TS2591 turned both into `blocked-compile`, which the corpus
  counts as a REGRESSION. It sat in the branch for eight batches: the
  oracle and the 2,966 tests both stayed green, because neither compiles
  a fixture. The fix is what the diagnostic asks for rather than a
  workaround — `declare const process: { argv: string[] }`, which emits
  nothing, so the value stays Node's and stays opaque to every fold. The
  operational lesson is the checklist: after a rule that can reject a
  NAME, run the fixture-compiling harnesses (`verify-mangle-safety`,
  `verify-generated-fixtures`, `verify-scaffolds`, `verify-examples`,
  `verify-mbti-dts`), not just `moon test` and the oracle.
  It also half-retires a blocker this file records: `TsFunc.body`
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
  Batch CM is +11 across nine small rules, and its two most useful
  findings are about the PARSER. The ranking came from re-asking the
  question with the CL probe: every remaining MISS file run through the
  real compiler under its own harness header, grouped by the codes it
  actually produced. That is why the rules are small — the top of the
  list is deep type machinery and the long tail is 67 codes with exactly
  ONE file each, mostly grammar. TS2583 (`SharedArrayBuffer` / `Atomics`
  under a pre-es2017 `lib`) is batch CH's TS2591 with a different
  allowlist question; TS2350 is TS2348's mirror, with `Void` / `Any` /
  `Unknown` abstaining and a top-level function DECLARATION excluded by
  NAME rather than by inference, because an old-style JavaScript
  constructor is exactly the `Func` shape and `new Point(1)` is how such
  code is meant to be used; TS1002 is batch CJ's unterminated regex in
  the sibling scanner, where the catch-all arm consumed `\n` and a
  string silently swallowed the rest of the file; TS2432, TS2448 and
  TS18038 are declaration- or flag-shaped and needed no type
  information. TS1200 went in as `Parser::expect_arrow` because
  expression parsing consumes `=>` at EIGHT sites, and the restriction
  had to be probed rather than assumed: a break AFTER the arrow is
  legal, and so is one before a TYPE-position arrow, so `parser_type` is
  untouched. TS2448 was written for BOTH pattern kinds at once —
  `const [a = b, b = 1] = xs` is the same error and was a MISS before
  the generalization.
  The parser findings are two more of the same family, and the first one
  is where the CORPUS said yes and only the full SUITE said no.
  `export import a = A` inside a namespace body records a TYPE alias and
  no value, while the plain `import a = A` spelling records both, and
  that asymmetry is what made TS2708 false-positive on
  `exportImportAlias`. Recording the value there too passed the
  conformance oracle at FP 0 and broke the bridge: the emitter reads
  `values` to decide what to IMPORT, and `export import JSX =
  JSXInternal` over an interface-only namespace is a type-only alias that
  must produce no import at all. Whether the alias binds a value depends
  on the TARGET, which is not resolved at parse time, so neither answer
  serves both consumers — the parser stays as it was and
  `namespace_is_instantiated` reads the fact off `type_aliases`, which
  over-abstains for a namespace of real `export type` aliases and so
  costs a MISS rather than inventing a finding. And a class STATIC BLOCK is the
  fifteenth of fifteen sites that must save / clear / restore
  `self.labels` around a function body, and the only one that did not,
  so `label: while (v) { class C { static { break label } } }` found the
  outer label (TS1107).
  TS2708 also cost a false start worth recording, because it is a
  property of this parser rather than a judgement about TypeScript:
  `parser_namespace_lower` lowers EVERY namespace — instantiated or not
  — to `var N = N || {}`, so at script top level the module env and
  `globals` both bind the name whatever the body holds, and the first
  draft fired only inside a function, where the env holds real locals.
  `ctx.script_top_level` tells the two apart. The same artifact is why a
  type-only namespace NESTED in another is not covered:
  `export namespace inA { … }` records a value for `inA`.
  TS1002 shipped the batch's one PFLEGAL and the corpus named the file:
  U+2028 / U+2029 are line terminators for the grammar and were once
  illegal inside a string literal, but ES2019 made them legal —
  `allowUnescapedParagraphAndLineSeparatorsInStringLiteral` is
  TS7-ACCEPTED. They stay in `scan_regex`'s break, where a regex still
  may not cross one, and are out of `scan_string`'s.
  Two REJECTIONS carry more information than the rules. Wiring
  `unresolved_type_references` into the conformance path is the
  highest-yield-looking gap on the whole list — the function has existed
  for years and is wired into `check_module` ONLY, so `type T =
  Undeclared` is silent while `var q: Undeclared` fires — and it
  produces FORTY-PLUS false positives, because `check_type` carries one
  flat list of type-parameter names that models a declaration's own
  parameters and NOT the binders inside a type (a call signature's own
  `<T>`, an `infer A`, a mapped type's key). And TS6133 for an unused
  `#private` member is deferred on the FAIL DIRECTION rather than the
  effort: every formulation needs a complete walk over the class body or
  a complete reference-recording channel, and a missed read makes the
  member look unused, which is a false positive — the one direction the
  budget does not allow.
  Batch CN is +1 and is mostly about what the probe finds in code that
  is ALREADY there. Writing a TS2610 / TS2611 rule turned up an existing
  one, so the new implementation was deleted and the old one probed —
  which produced three findings. Its two MESSAGES were swapped relative
  to their conditions (the loop for "base accessor, derived property"
  said the opposite), so detection was right and the text was not. Its
  `useDefineForClassFields` gate was WRONG: tsc reports both codes with
  that flag explicitly `false`, because the flag changes how a field is
  EMITTED and not whether changing an inherited member's kind is legal.
  Removing the gate widens the judged population, so it was measured
  alone — TP 2480 / MISS 254 / FP 0, identical to keeping it — and a
  unit test had pinned the wrong behaviour with the confusion stated in
  its own comment ("the property flows through the setter -- allowed"),
  the third test in this repo found asserting the bug. And an AMBIENT
  class's accessors are invisible to the pair, because the parser
  upserts a `declare class`'s `get x(): T` into `properties` with no
  `methods` entry carrying `accessor: "get"` — one defect producing a
  MISS and a latent FALSE POSITIVE at once
  (`declare class A { get x(): string } class B extends A { x = 1 }` is
  TS2610 and silent; the legal accessor-over-accessor form IS reported),
  and the corpus has no file of the second shape, which is why FP 0
  never caught it. Recorded rather than fixed: the change is in the
  parser and moves what the bridge generator sees. The rule that DID
  ship, TS2500, was again a diagnostic the code had already located —
  `parse_implements_names`'s comment names "the `?.` of an invalid
  `implements A?.B`" as the thing it skips — with the asymmetry that
  keeps it sound: `extends A?.B` is legal, since an `extends` clause
  takes an expression.
  Batch CO is +4 and takes MISS to 250, the target. All four came from
  the long tail the compiler-probed ranking exposed — 67 codes with
  exactly ONE miss file each — and none needed type machinery: dot
  access to an index-signature member under
  `noPropertyAccessFromIndexSignature`, decorators on both halves of a
  get/set pair, a decorator on a bodiless overload, and a CALL in a
  `const enum` initializer. Three of the four cost a false positive
  first, and the three are different failure modes worth separating.
  TS4111's was specific to THIS parser: the flag marker went into
  `grammar_misuses`, where every non-marker entry becomes a diagnostic
  verbatim, so the option's own marker was reported as an error on every
  file carrying it — a marker needs an explicit skip entry or it IS a
  finding. TS1207's was the legal neighbour again, and at scale: seven
  corpus files in `esDecorators/` say that decorating both halves of a
  pair is legal under STANDARD ES decorators, and every probe written
  for the rule had carried `@experimentalDecorators: true`, so not one
  of them could see it. And TS1249's is the one place the new probe
  actively MISLEADS: tsc 6.0.3 reports it for an ambient or abstract
  bodiless member, `decoratorInAmbientContext` is TS7-ACCEPTED, and
  following the local compiler there would have shipped a false
  positive — the caveat `tsc_probe.mjs` states in its own header, now
  with an instance. TS1207 also turned up a pre-existing inconsistency
  it declines to paper over: inside a class EXPRESSION body the
  decorator-mode flag is not reliable, since
  `(class E { @dec get x() {…} @dec set x(v) {…} })` with NO directive
  fires while the identical declaration stays silent, so some parser on
  that path carries `experimental_decorators`' `true` default instead of
  the header value. Every decorator-mode-gated rule is wrong there; the
  expression form is skipped and the fix is filed.
  Batches CP and CQ are **+28** together for seventeen rules, and CP's two most useful outputs
  are a REJECTION with a measured cause and a performance bug I wrote
  myself. Ten of the rules are grammar or lexer or flag-shaped and needed
  no type information: TS1489 (a leading-zero literal an `8` or `9` makes
  decimal — the other exit of the branch that already recorded the legacy
  octal), TS17006 (a unary expression as the left operand of `**`, where
  `++t ** 2` is legal because an UpdateExpression is), TS5076 (`??` mixed
  with `||` or `&&`), TS1186 (a rest element with an initializer, at BOTH
  of its sites), TS1347 (a `"use strict"` prologue with a non-simple
  parameter list), TS17013 (`new.target` outside any function), TS1036 (a
  bare `;` in a `.d.ts`), TS2354 (`@importHelpers` with a `using`),
  TS18016 (a `#private` name with no enclosing class body) and TS2390
  (constructor signatures with no implementation). Three needed a
  structural fact instead.
  Four of them are the applied-in-some-places family again, and one is
  its inverse. TS1186's two spellings land in different parsers, and the
  abstention comment in `parse_assignment_binding_array` named the
  blocker in writing — `[...x = a] = a` parses as an EXPRESSION, so the
  array-literal arm of `parse_assignment` is where it had to go, while
  `var [...z = a] = a` really is the binding parser's. TS2390 is the
  mirror image of a rule that already existed: `ctor_impl_count` had
  counted constructor implementations for years and only ever been
  compared against 2, so two implementations were reported and ZERO were
  not. TS4113's recording sat inside `if method_name != "<computed>"`,
  a guard that is right for the three lists it wraps — accessibility and
  abstractness are looked up by NAME — and wrong for the fourth, which
  only asks whether a member carried `override`. And
  `resolve_base_chain_members` consulted a merged interface ONLY when no
  class of that name existed, which is never, since a merge has both
  halves. The inverse case is TS1036: `Empty` looked like a missing arm
  in the ambient-statement list and is a deliberate abstention, because
  an `interface`, a `type` alias, a bodiless `declare function` and a
  skipped namespace all lower to the same `Empty` — putting it in that
  list would fire on nearly every real `.d.ts`, so the parser marks the
  real `;` instead.
  TS4113 is also where a recorded REJECTION became a rule with a
  condition. Batch BY refused `override` on a computed name as unsound,
  and was right: a `const` string key is late-bindable, so
  `override [prop]()` is LEGAL when the base declares what `prop`
  resolves to. What IS decidable without resolving the key is a base
  chain that declares NOTHING AT ALL — and getting that claim to be true
  rather than merely unobserved took two fixes, the merged-interface fold
  above and a `has_opaque` flag, because a computed key in the BASE is a
  member the walk cannot name. The first draft fired on
  `interface M { m(): void }` beside `class M {}`, which tsc does report
  — and would have fired identically had M declared `foo`, where it is
  legal. "It agrees with tsc on this file" is not soundness either.
  The REJECTION is `unresolved_type_references`, which this file called
  the highest-yield-looking gap on the list, and the cause is now
  measured rather than guessed. Four of the things batch CL blamed are
  real and are FIXED: the `__tsmbt_infer` marker was reported as a type,
  an `infer` name was unresolved in the conditional's branches, `note`
  consulted a forty-name hand list where the GENERATED
  `is_lib_global_type` registry exists, and `module_declared_name_set`
  ignored `imported_binding_names` — whose own doc comment names
  unresolved-reference checks as its consumer. None of that is the
  blocker. An interface or object-type CALL / CONSTRUCT signature's own
  type parameters are not preserved anywhere `check_type` can read them,
  so `interface I { <U>(x: U): U }` reports `U` through the `Object` /
  `Func` arms the walk has always had: the binder is lost by the PARSER.
  Adding scope arms for `GenericFunc` and the mapped types was tried and
  made it worse — those nodes were previously SKIPPED, and walking them
  turned silent MISSes into reports of their own parameters, which is the
  general lesson: a walk arm added to a skipped node converts a MISS into
  a candidate false positive, the one direction the budget forbids.
  The performance bug is worth as much as any rule. TS5076 has to
  distinguish `(a && b) ?? c` from `a && b ?? c`, and the parser strips
  parens, so the check reads the TOKEN range the expression consumed —
  the same reasoning batch CF's TS1106 records. But `parse_or` runs once
  per expression at that precedence level, for every expression in the
  file, nested, so scanning unconditionally is O(n^2) in the token count.
  It took a 9 MB file from seconds to over 180, and the checker whitebox
  binary sat at 100% CPU for 36 minutes before anyone looked at `ps`.
  Gating the scan on the frame having actually consumed a `??` makes the
  cost proportional to the nullish expressions instead of to the file;
  the oracle's own wall time (58 s over 4,484 files) is the check that it
  is gone. A rule that reads a span is a rule with a cost model, and the
  span-reading idiom this file recommends does not come with one.
  Two more probe findings, both of which would have been wrong if
  reasoned about. `"use strict"` with a non-simple parameter list is an
  error only from **es2016** up — below that TypeScript downlevels the
  parameter, so the EMITTED list is simple — and a file with no
  `@target:` at all is left alone even though tsc 6.0.3 reports it,
  because that says what the local compiler's default target is and
  nothing about TS7's. And `abstract class C { constructor(); }` IS
  TS2390, which "abstract members have no bodies" suggests it should not
  be; only an ambient class is exempt, and the parser routes
  `declare class` through a different function entirely, so that
  exemption needs no code.
  Batch CQ is the other nine files, and three of its four rules were
  wrong in their first form for three different reasons. TS1212's message
  names strict mode and tsc applies it REGARDLESS — `yield;`,
  `console.log(yield)`, `var yield = 1`, a parameter named `yield` and a
  bare `let` are all reported at es5 in a sloppy script — so batch CF's
  assumption that these are strict-mode-only reservations was too narrow;
  the rule sits at the two identifier-REFERENCE arms, and every property
  position (`{ yield: 1 }`, `o.let`, `interface I { let: string }`,
  `enum E { yield }`, `class C { yield() {} }`) is legal and parsed
  elsewhere, which is what keeps it off them. TS2803 and TS2806 turned
  out to EXIST already, and probing them is what explained the two
  corpus MISSes: those checks read `module_.classes`, so they cannot see
  `const C = class { … }`, which is the shape both files use — so the new
  code is gated to the class EXPRESSION and a declaration is left
  entirely to the older rules rather than reported twice. Second time
  after batch CN that writing a rule turned up the rule already there,
  and the same resolution: probe the old one, do not keep a second.
  TS7008 shipped TWO false positives and the boundary is exact: a member
  with no annotation and no initializer takes its type from an assignment
  in the CONSTRUCTOR or a STATIC BLOCK, and NOT from one in a method
  body. `classStaticBlockUseBeforeDef1` is `static x;` plus
  `static { this.x = 1 }`. Telling those regions apart in a flat token
  scan needs brace tracking, so any `.name =` in the body withdraws the
  report — which loses `class B { q; m() { this.q = 1 } }` and is the
  MISS that buys FP 0. Its diagnostic also had to be taught to print
  `#u` rather than `__private_brand__4__u`: `class_key_name` returns the
  MANGLED name, and a diagnostic naming a brand is one nobody can act
  on. The private rules read the class body's TOKEN range rather than
  walking member bodies, for the reason the perf note above cuts both
  ways: a body is an arbitrary expression tree and a walker missing one
  arm loses findings silently, while every access to `#x` must spell
  `#x`, so a scan is complete by construction — and here the span is one
  class body, not one expression per frame, so it carries no quadratic
  term. And a fifth test was found asserting a gap: the TS1128 ASI case
  (`class C { var\n public }`) expected silence, and both of those are
  real TS7008s under a flag that defaults ON, so the assertion was
  measuring the implicit-any hole rather than the ASI behaviour it is
  named for.
  Batch CR is +3 and is the family in its purest form yet, twice over in
  one rule. TS2307 reads `import_module_specs`, and that list was filled
  by the IMPORT parsers only — so `export * as ns from './nonexistent'`
  reached the check with nothing to say even though the specifier was
  sitting right there. Routing the eight `expect_from()` sites through
  one `expect_from_spec` helper fixed half of them, and
  `export { a } from './nope'` STILL did not report: this parser consumes
  `from` in TWO ways, a mandatory `expect_from` and an optional
  `match_(From) || match_ident("from")` (because `export { a }` with no
  `from` is legal), and the first fix covered one of the two. Six more
  sites use the optional spelling; both helpers now record through a
  single `record_module_spec`, which is the only place that writes the
  list. An import TYPE's specifier was a third route — that arm consumed
  and discarded it — and buys no corpus file, because
  `importTypeAmbientMissing`'s only top-level declaration is a
  `declare module`, so the whole check is suppressed by the
  ambient-module-bundle gate; it ships anyway, proven in isolation,
  because a typo in `import("...")` is an error a person makes.
  TS6133 for an unused `#private` is the other rule, and it is the one
  place a COUNTING argument replaces a walk. An earlier note deferred it
  on the fail direction: every formulation needs a complete walk or a
  complete reference channel, and a missed read makes a used member look
  unused, which is a false positive. Counting inverts that. A private
  name is class-scoped, so every read must spell `#name`, which makes
  the number of `PrivateIdent` tokens carrying it an exact upper bound on
  declarations + reads; when that does not exceed the declaration count
  the class parsers recorded, nothing reads it. A read this misses is
  impossible, and an extra occurrence only makes it quieter. It is
  file-level rather than per-class deliberately —
  `privateNameUnused` declares `#unused` four times across three classes
  (a get/set pair being two declarations of one member) and reads it
  never, while its `#used` has the same four declarations plus three
  reads — and a `#x in v` brand check IS a read to tsc, which is exactly
  why `privateNameInInExpressionUnused` reports its `#unused` and not
  its `#brand`.
  Batch CS is +3 and its most valuable output is a FALSE POSITIVE the
  conformance gate structurally cannot see. Hunting for a mechanism worth
  many files, three plausible ones were tested and all three came back
  negative, which is worth as much as the rules: **position coverage is
  not the bottleneck** (a matrix of a known type error in each of 28
  syntactic positions — return, property assignment, array element,
  for-of head, default parameter, template, index write, satisfies, … —
  finds 24 already checked); a NAME is not a feature cluster (the 21
  `Symbol`-ish miss files need 21 unrelated things — instanceof operands,
  for-in operands, interface extends conflicts, `delete` on readonly,
  index types, the async-iterator protocol); and the lib model is
  largely present (8 of 13 common global return types infer correctly).
  So there is no single mechanism worth ~66 files, and the measured rate
  is about 1.7 rules per file gained.
  The one real systemic gap found was `Symbol()` having no model in
  `infer_expr` — `iterator_class_element_type`'s own comment says so and
  worked around it locally, another stated abstention naming its blocker
  — and giving it one is what makes every symbol-operand rule reachable.
  On top of that: TS2358 extended from a syntactic literal LHS to the
  inferred type, TS2359 for the right operand, TS2407 for a `for...in`
  right-hand side, TS2731 for a symbol in a template substitution (zero
  corpus files, kept because `${sym}` THROWS at runtime), and TS18046
  for an unnarrowed `catch (e)` — the single most common thing a
  codebase hits when it turns `strict` on, decided by a token scan of
  the catch block where any of five narrowing spellings withdraws the
  report.
  The false positive is the lesson. `+`, `-` and `~` all apply
  ToNumeric, so the ONLY type TypeScript refuses is `symbol` (TS2469) —
  `~aString`, `-aString`, `~aBoolean` and `-aBoolean` are legal and were
  all being reported, and an object coerces too. Probing operator by
  operator was the only way to find it, because the BINARY operators
  really do require a number (`s - 1` is TS2362) and `++` / `--` really
  do too (TS2356), so the wrong rule looked like its neighbours. Two
  TESTS asserted the bug by name ("unary minus on string is flagged",
  "unary minus still rejects a string operand") — the sixth and seventh
  in this repo found doing that. And the gate paid for the wrong rule
  with a right-looking number: removing it COST a true positive, because
  `typeArgumentsWithStringLiteralTypes01` was flagged only for
  `args[+randBool()]` — idiomatic bool-to-0/1 coercion — while its real
  errors are five TS2345s elsewhere. A conformance file counts as a TP
  if we flag it AT ALL, so +1 TP is not evidence that a rule is right.
  Batches CT-CZ are **+23 files** (MISS 250 -> 193) and the ranking
  behind them was made by running every remaining MISS file through the
  local compiler and grouping the codes it actually produced. That
  ranking is also the answer to "what would a big win look like": 132 of
  208 files have exactly ONE error code, 103 codes have exactly one file,
  and the four largest — TS2322 (14 solo), TS2345 (10), TS2339 (7),
  TS2403 (5) — are variadic tuples, template-literal types, conditional
  types and contextual typing, fourteen unrelated causes when the files
  are opened. There is no mechanism left worth many files; the rate is
  three to five files per probed batch.
  What DOES still pay is the applied-in-some-places family, and CU is the
  clearest instance yet because the rule was not merely similar to an
  existing one, it WAS one. `check_class_decorator_signatures` has
  compared a CLASS decorator's declared arity against the runtime's for
  years and the member positions had nothing, so `@dec prop` with a
  one-parameter `dec` was silent. Its arity table had to be PROBED,
  because "a signature with fewer parameters is assignable" is not what
  tsc does: a property decorator must ACCEPT exactly 2 arguments and a
  method or accessor decorator 2 or 3, where accept means N falls in the
  signature's `[min, max]` range. Two things nearly cost false
  positives. An `accessor` FIELD is decorated like a METHOD — its
  decorator gets a descriptor — so `decoratorOnClassProperty13` was
  reported until the stage-3 modifier reached the classification point,
  which is the OPPOSITE conclusion from batch CK, where gating on
  `accessor` was the wrong reading of a two-feature file. And
  `is_optional` is accurate for a `function` declaration and always
  FALSE for an ambient `declare function`, whose synthesized parameter
  list carries names and types only, so reading it alone made `@dec`
  with `(target, key?, desc?)` — how a universal decorator is written,
  and an existing test's assertion — report "expects 3". Consulting the
  parameter TYPE as well over-counts optionals and therefore only ever
  WIDENS the accepted range.
  CV is one parser defect with TWO faces, and the second is a false
  positive the gate structurally cannot see. `parse_declare_class`
  upserted a `declare class`'s `get x(): T` into `properties` and pushed
  no `methods` entry carrying the `get` tag, so every consumer asking
  "is this base member an accessor or a data property" got the wrong
  answer for an ambient base: `declare class A { get x(): string }`
  beside `class B extends A { x = 1 }` is TS2610 and was SILENT, while
  the LEGAL accessor-over-accessor form was reported TWICE. The corpus
  has no file of the second shape, which is why FP 0 never caught it —
  the fix is to mirror what the runtime class parser already does (both
  records, not one) so the two paths cannot disagree again.
  CW's TS2678 is the family with the two spellings inside one check.
  The switch case-comparability test has flagged
  `switch ("a") { case "b": }` for as long as it existed and
  `switch (12) { case 5: }` was silent, because `infer_expr` keeps
  `Literal("a")` for a string literal expression and WIDENS a numeric one
  to `number` and a boolean one to `boolean`. Reading the two literals
  off the SYNTAX needs no inference and cannot be defeated by widening;
  a `const` scrutinee stays a MISS, since its literal type is exactly
  what widening removes.
  CX's TS2415 / TS2417 is where probing earned itself back outright. The
  message says "different accessibility modifiers", which reads as "they
  must match", and the 3x3 table on both the static and instance sides
  says otherwise: widening `protected` to `public` is LEGAL, and an
  identical `private` redeclaration is an ERROR, because a base private
  member is nominal and nothing outside the declaring class can satisfy
  it. Those are the two cells a rule written from the message text gets
  wrong in opposite directions.
  CY is the family in the TREE rather than in a check, and it is the
  reason "record the fact in one place" is not by itself enough.
  `export { … }` is parsed at FOUR sites; a recorder deliberately written
  at three of them still left a top-level `export { x };` silent, because
  that site reached for `parse_import_specifiers` instead of
  `parse_named_exports` — two functions parsing one clause. Fixing it
  corrected something smaller underneath: that site pushed the clause's
  names into `imported_binding_names`, which is a list of LOCAL BINDINGS
  an import introduces, and `export { x }` introduces none. The
  mislabelling is what made the check quiet, since the undeclared name
  looked declared. CY's TS2532 also shipped a false positive first, and
  the trap was already written down: `Undefined` looked like it belonged
  in the arm next to `Void`, and our flow model narrows an `any`-typed
  binding to `Undefined` when its initializer is `undefined`, so
  `const q: any = undefined; const { y }: any = q` — which tsc ACCEPTS —
  was reported. `check_computed_key_type` documents that exact hazard
  twenty lines in, for the same reason, which is why one of them should
  have warned about the other. `Void` cannot be produced by narrowing.
  Two rules were REJECTED with their conditions recorded rather than
  their verdicts. TS2464 for a bare `Symbol` as a computed key is
  correct and buys zero corpus files, because `symbolProperty3` writes
  `var s = Symbol; ({ [s]: 0 })` and `s` infers as `Any` — catching it
  needs the constructor modelled as a value type, and neither spelling
  is code anyone writes. And TS2347's first form asked whether the
  callee's type comes out `Any`, which is true both for a genuine `any`
  and for every type this checker FAILED to compute: `const C = foo()`
  where `foo` returns a class expression is `Any` here and a generic
  class in tsc (`staticIndexSignature6`), so that version was +6 TP and
  1 FP, four of the six flagged for a reason that does not hold. What is
  decidable without inference is a declaration with no `=` initializer
  whose annotation is `any` or absent, which loses `const p =
  JSON.parse('{}'); p<number>(1)` — a real TS2347 — and that MISS is
  what buys FP 0.
  Every gate above asks whether the answer is RIGHT, and none of them can
  see a rule's COST: the oracle's 4,484 files are a few dozen lines each,
  so a rule quadratic in the number of interfaces or exports in ONE file
  is invisible to it and to the 2,966 tests alike. `just
  verify-checker-scaling` asks the missing question the only way a cost
  model can be asked — by GROWTH rather than by stopwatch. It runs a size
  ladder along each axis a check loops over (interfaces, merged
  interfaces, classes, exports, aliases, enums, vars) and fits an
  exponent from the endpoints: linear is ~1.0, quadratic ~2.0, and an
  axis over budget fails the run and NAMES the axis, which is the part a
  wall-clock reading cannot tell you. Its `same-bytes` control is what
  separates the two diagnoses: bytes grow with the rung and the
  declaration count does not, so "the big file is slow" and "the long
  list is slow" stop looking alike — and that is what proved the
  regression below was about the COUNT rather than the 527 KB.
  It was written because batches CY–DB were **6.5x slower at 4,000
  interfaces** than the batch before them, at FP 0, with every test
  green. Three nested scans over module-wide lists, all landing at once:
  `check_merged_interface_member_conflicts` compared every (i, j) pair of
  interfaces in the module to find the same-NAMED ones (72M iterations on
  a 12,000-interface file, for a rule that can only act on same-named
  pairs); `check_merged_export_modifiers` rescanned both declaration
  lists per exported name; and both joined member lists as fields x
  fields. Each is the same fix — an index where a nested scan was — and
  the ladder went from 998 ms to 166 ms at the top rung, back to 0.99x of
  the pre-batch code. Two of the batch's own doc comments had described
  these loops accurately; what neither said was what they cost.
  The harness then earned itself back on its FIRST run, twice. It found a
  quadratic the fix had missed — grouping by name killed the module-wide
  n² and left a pair loop INSIDE each group, which is exactly what an
  `interface Window` spread over many halves is (5.0 s at N=4,000).
  Accumulating the first-seen type per member is one pass, and it is also
  what tsc's message describes ("must be of type `T`", where `T` is the
  FIRST declaration's), so the faster rule is the more faithful one; it
  can only lose a finding where `types_definitely_differ` abstains on
  (first, later) but would have proven (later, later'), which is the
  affordable direction. And it found a SECOND quadratic that predated the
  whole batch series: `merge_interfaces` is pairwise and the upsert loop
  filling `r.interfaces` used it as a left FOLD, copying the accumulated
  arrays once per declaration. That one is worth recording for the
  measurement rather than the fix — the largest same-name group in
  `lib.dom.d.ts` is **2**, and 11 across the entire lib set concatenated,
  so it had never cost anything and never would. It was fixed anyway
  because it is the honest reason the axis reported a 2.0 exponent, and a
  known quadratic left in place is one the next person has to
  re-diagnose; `merge_interface_group` is a single pass whose equivalence
  to the fold is asserted field by field against the fold itself, on a
  four-declaration group carrying every shape that could tell them apart
  (a member redeclared by a later half, a member declared twice in one
  body, a dedup list and an append-only one). 5,053 ms -> 29.6 ms, and
  42x faster than the code that predates the batches.
  What the round did NOT find is worth as much: the parser is untouched
  by 40 batches of new markers (0.94–1.05x, including the 9 MB
  `typescript.js`), and the residual on real files is 0.92–1.02x — so
  fifty new rules cost nothing measurable on a real `.d.ts`. The per-axis
  differential says why there is nothing left to chase: interfaces +11%,
  aliases +20%, exports +5%, classes −5%, enums −8%, vars −1%. The cost
  is spread proportionately across fifty rules with no single one to
  attribute, which is the shape a linear checker should have, and the
  20% on a 3.8 MB concatenation of every lib file is the whole price.
  A later round asked the same question of HEAD against that same
  commit and the answer is again nothing — seven axes linear, real
  `.d.ts` 0.89–1.02x across 50 more commits and ~60 more rules — but it
  found what those axes CANNOT ask. Every one of them grows a
  module-wide LIST, and mtsc's own `--no-check` help says the check is
  ~95% of a large compile, measured here at **93.4%** (0.392 s versus
  5.949 s on terser's published 1.1 MB bundle). So five axes were added
  for the lists the recent rules key on — `functions` (overload sets),
  `namespaces`, `private-members`, `statements`, `function-bodies` —
  and, decisively, three DEPTH probes. Three of the lists are linear
  (`functions` 0.87, `statements` 0.75, `function-bodies` 1.04 and 1.10
  at 8,000 bodies) and `private-members` read 1.17 and is NOT — see
  below, since the probe that produced that number climbed a cheaper
  ladder than the gate does; **depth is
  not** either: `o.p.p…p` fits **2.60**, `a + a + … + a` **1.62**, nested
  ternaries **1.44**. `namespaces` is quadratic at **1.96** and is
  quadratic at the baseline too (2.01) — long-standing, and invisible
  only because no axis grew that list. Its mechanism is structural: a
  namespace body is its own `TsModule`, so the layered check runs once
  per namespace and each run re-ingests the OUTER chain, and
  `ingest_module` recurses the whole namespace tree. The root-wide name
  backstops were hoisted out of that loop (`RootNameBackstops`, exact:
  both maps are name-keyed, add-only, and identical at every sibling) —
  -22% at n=1000 and nothing measurable on real files, since the most
  namespace-dense `.d.ts` in this repo's `node_modules` is
  `@types/node/fs.d.ts` at 43. The rest is DECLARED rather than fixed,
  at a gated budget (`AXIS_BUDGET`, namespaces 2.15) so a regression
  past the accepted cost still fails; a budget without a written reason
  is a suppression list.
  The member-chain quadratic is `infer_expr`'s own first line: the
  `PropAccess` / `IndexAccess` arms look a chain up by its synthesised
  dotted narrowing key, and `narrowing_key_for_expr` rebuilds that key
  from the whole prefix at every level, then hashes it — two O(d²)
  terms. Gating it on "did narrowing ever bind a path key" is **32x** on
  that shape (2492 -> 78 ms at 400 levels, 2.67 -> 1.30) and was
  **REVERTED**: maintaining the flag means testing every bound name on
  the hottest path in the checker, which cost the 1.1 MB real bundle
  **+8%** with `contains` and **+3.5%** with a hand-rolled scan. So
  "ask the cheap question first" — the move that made
  `class-method-dce`'s `off_bundle` a thunk — is a TRADE, not a free
  win: there the question is a map lookup, here it is a string scan per
  binding. The version that would pay sets the flag only where a path
  key is CREATED, which needs the narrowing engine's creation sites
  rather than `env.narrow`'s 49 call sites, and is filed. One
  measurement lesson came with it: the first +8% reading was taken while
  a `tscheck` from a killed 400-level probe was still burning a core for
  eight minutes, so it had to be re-measured before it could be
  believed — the same shape as the overlapping timing spans above.
  Adding `namespaces` then broke the harness's OWN cost, and fixing
  that is what exposed a second quadratic. At the default top rung its
  ~90 s per iteration took the whole run from ~1 minute to ~15, against
  a header promising it stays near a minute — a harness nobody will
  wait for is as useless as one that cannot reach the answer. An axis
  only needs a **4x spread between its endpoints** to separate linear
  from quadratic, so a quadratic axis can climb a cheaper ladder and
  fit the same exponent: `AXIS_RUNGS` gives `namespaces`
  125/250/500/1000, where it reads 1.99 in 2 s against 2.20 on the
  default rungs, and the row LABELS its own ladder or its milliseconds
  read as comparable with the others'. The full run is back to 1m3s —
  and its first completion says **`private-members` is 1.67**, the axis
  the round above had called linear at 1.17. That 1.17 was fitted over
  125..1000, where the curve has not turned over; a fit is only a fit
  over the range it was taken on, so "linear" asserted from a cheap
  ladder is a claim about the cheap ladder.
  That entry then named the wrong MECHANISM, and part 4 is the
  correction — worth more than the fix, because the note was written the
  way this file keeps warning against. It blamed
  `private_brand_declared_on_receiver`, which really does loop the
  receiver's `properties`, `methods` and `private_members` per ACCESS;
  the index for it was built, measured and bought **nothing** (1.66
  against a 1.52–1.68 baseline), because that function is reached only
  where a private lookup has already MISSED and a well-formed file never
  takes that path. Restoring its module-wide scan afterwards costs
  0.14 s against 0.13 s. "Is this loop quadratic" and "does this loop
  RUN" are different questions and only the second predicts time.
  Three steps found the real one, and none of them was reading code.
  `--parse` is linear where the full run is not, so the cost is in the
  CHECK. Then four files at identical member counts: the axis 0.28 s,
  the same with bodies that read nothing **0.07 s**, the same with
  PUBLIC fields and `this.a{i}` reads **0.24 s** — which refutes "it is
  about private names" outright. Then sampling, with no `perf` in the
  image: `gdb -p <pid> -batch -ex bt` in a loop over a 16,000-member
  class puts **10 of 10** samples in two leaves, both in `memcmp` —
  `Resolver::lookup_class_field` (7) and
  `inferred_primitive_field_type` (3). Both resolve a member by NAME
  with a linear scan per access, over `properties` + `methods` and over
  `instance_field_inits`. `ClassIndex` indexes them lazily by name and
  stores POSITIONS rather than types, so a method's `Func` type is still
  built only when asked and `properties` still wins over `methods`;
  `lookup_class_field` takes the resolver's class KEY instead of the
  decl, so the index and the member lists cannot arrive as a mismatched
  pair, and a bare `TsClassDecl.name` would have folded two namespaces'
  `C` together. **8.32 s -> 0.98 s** on that class, the axis 1.63 ->
  1.21, and `lib.dom.d.ts` 0.21 -> 0.18 s — a real file, which is what
  makes it more than a synthetic win. The oracle is identical on both
  binaries (TP 2635 / MISS in scope 80 / FP 0 / PFLEGAL 0 / TN 1750),
  measured by swapping the baseline binary into the release path rather
  than assumed from "it is only a refactor". The `AXIS_BUDGET` entry is
  REMOVED rather than retuned, since 1.21 sits under the default 1.50
  and a budget above the measured number is slack a regression can hide
  in. The private-brand index is REJECTED with its number. And the axis
  NAME is the reason the wrong suspect looked right: `private-members`
  measures member ACCESS against a many-membered class, which is
  ordinary large-class code rather than a rare `#private` pile-up —
  eleventh instance here of a label standing in for the objective, and
  the first where the label was mine.
  Every number above ranks work by CORPUS COUNT, and
  `docs/checker-triage.md` is where that stops: `MISS 176` sums work
  worth doing now with files nobody should ever fix, so it can rank
  nothing and can never reach zero — the defect that retired
  `docs/checker-priority.md`. All 176 are classified there by the
  MACHINERY a rule needs, priced against how often the feature appears
  in 3,000 real `.d.ts` files and 2,697 real `.ts` sources, and assigned
  four tiers with the reason written down. Two measurements decide two
  tiers outright: `using` declarations occur in **zero** of 5,697 real
  files and are 6 of the misses, and the 48-file assignability bucket is
  ~10 unrelated causes, so the largest bucket ranks no work — the same
  label-for-objective substitution recorded four times above.
  Its most useful output is a CAPABILITY PROBE, because the
  classification says what a file NEEDS and not what we HAVE, and
  guessing at that was wrong twice in one session. Probed against
  `tscheck --strict`: mapped types, `keyof`, strictNullChecks,
  `this`-types, index signatures, variadic tuples, generic function
  inference and basic assignability are all CAUGHT at the common shape,
  while conditional-via-generic-alias, the whole utility-type table,
  template-literal types with a placeholder, computed `unique symbol`
  keys and overload resolution were BLIND at the shape real code writes.
  The first probe run reported every family blind and that was harness
  error, not a finding: these entry points check function BODIES and the
  probes put the error at top level, where nothing visits it.
  Batches DI–DM took the Tier 1 rows and every one was the
  applied-in-some-places family, four levels deep in the same feature.
  `Resolver::unwrap` reduces `Keyof`, `TypeOf`, `MappedType`,
  `IndexedAccess` and `TemplateLiteralType` and had **no `Conditional`
  arm**; the evaluator itself works, since an inline conditional and a
  non-generic alias for one both resolve — only the composition with a
  generic alias abstained. `standard_utility_types()` had been
  unit-tested for years behind `module_alias_resolver`, a `pub fn` with
  **no caller outside its own file and its tests**, so a `.d.ts` using
  `ReturnType<typeof f>` type-checked BY ABSTAINING. `simplify_type`
  decides through the three-valued `extends_decision`, which cannot bind
  an `infer`, and `reduce_conditional` — the reducer that can — was
  reachable from `is_assignable_to` and not from alias resolution. And
  `contains_infer_marker` descended into `Func` with no `Constructor`
  arm, so `new (...args) => infer R` never ran the infer path at all,
  while `match_infer_pattern` and `substitute_inferred_type` both
  handled `Constructor` already: two of the trio right, the GATE wrong.
  Three of those took a wrong diagnosis first, and the corrections are
  the reusable part. `typeof C` really does arrive unresolved (the
  `TypeOf` arm reads `globals`, a class lives in `classes`) and was NOT
  why `InstanceType` was inert — `InstanceType<new () => C>`, with no
  `typeof` anywhere, was equally silent, and that inline case is kept as
  a test precisely because it is what distinguishes the gate from the
  class lookup. Wiring the WHOLE utility table in was wrong: the
  property-shape entries (`Partial`, `Record`, `Pick`, …) already have
  dedicated `lookup_field` arms and resolving them here moved the shape
  out from under those arms — three real regressions, not tests pinning
  old behaviour. The fallback is gated on the body being a `Conditional`,
  a SHAPE test rather than a name list, because a second copy of those
  names is the defect the batch removes. And the conformance gate caught
  a false positive the moment the resolver read that table:
  `ThisType<T>` is `interface ThisType<T> {}` in `lib.es5.d.ts`, an
  EMPTY marker, while the table encodes it as the identity and says why
  in its own comment — that is the useful answer to "what is `this`
  here", a different question from "what members does this type have",
  and the identity answer used structurally makes
  `PropDesc<U> & ThisType<T>` demand every member of `T`.
  The ceiling is honest about itself: DI, DK and DM buy **zero** corpus
  files each and DJ and DL buy one apiece, which is what the triage
  predicted in writing ("take these for the capability, not the count").
  What they buy instead is that `Exclude` / `Extract` / `NonNullable` /
  `ReturnType` / `Parameters` / `Awaited` / `InstanceType` /
  `ConstructorParameters` now decide, an index signature constrains the
  MERGED interface rather than one declaration of it, and an overloaded
  call's arguments are checked at all — they were checked by NOTHING,
  because `check_union_callee_arity` is correctly excluded from overload
  sets (every member must accept, right for a union VALUE and wrong for
  an overload set) and nothing took over. Two of the five cost a false
  positive whose hazard was already written down twenty lines away, both
  about optionality widened into a parameter type.
  The one Tier 1 row that did not survive contact is the `unique symbol`
  cluster, and the label was mine: opening all 16 files gives ELEVEN
  distinct error codes. Two are already rejected with measured evidence,
  two need overload resolution, two need lib interface merging, two need
  block-scope resolution of a shadowed `Infinity`, and the rest are one
  unrelated thing each — so the one genuinely cheap file turned out not
  to be a symbol rule at all. Recorded in TODO.md so the 16 are not
  re-attacked as a group.
  The triage's own headline is now the gate rather than a
  recommendation, and implementing it corrected the triage twice.
  `scripts/checker_out_of_scope.txt` declares the Tier 4 paths with a
  kind and a reason each, the oracle splits the MISS bucket into
  **`MISS in scope` 157** (the backlog, which can reach zero) beside
  **`OUT OF SCOPE` 17** (declared), and `verify-checker-soundness` gates
  the first with `--max-miss` — which closes a direction NOTHING
  watched, since a rule that stops firing moves a file from TP to MISS
  and every other number in the report absorbs that silently. The FP
  budget is untouched: only the MISS branch consults the file, so a
  listed file can still be a TP, an FP or a PFLEGAL, and
  `--scope-file /dev/null` reproduces the old single 174 (verified, not
  asserted). The estimate was ~24 files and the answer is 17, because
  the estimate came from the family classifier and the 17 came from
  OPENING each file: `parser/ecmascript5/` holds ordinary current
  TypeScript beside the error-recovery corpus, so twelve "legacy" files
  are six (`parserExportAssignment6` is an undefined-name check inside
  `declare module`, `parserES5SymbolProperty4` is a lib member lookup,
  and two more have parse-ambiguity PURPOSES with ordinary
  DIAGNOSTICS — a distinction the directory cannot make); and a file
  NAMED for `using` can carry an error `using` has nothing to do with,
  since `usingDeclarationsWithObjectLiterals2` is TS7018 on
  `value: null`, which a plain `const` reproduces under the same two
  flags. Sixth and seventh instances of the label-for-objective
  substitution, this time in a document written to warn about it. The
  one mechanism that keeps a scope file from decaying into a suppression
  list is a report of STALE entries — a listed path that is no longer a
  MISS, proven by adding a bogus path and seeing it named.
  Batch DN takes the first three Tier 2 files — the three the scope
  review just moved OUT of Tier 4 — and its TS2371 is the
  applied-in-some-places family in its strongest form yet: the rule was
  not merely similar to an existing one, it WAS one, living as a LOCAL
  function at the two bodiless exits of `parse_function_decl` and
  inline through a second channel for interface members, with the CLASS
  path holding nothing — so `class C { foo(a = 4); foo(a, b) {} }`
  parsed clean. Hoisted to one recorder. The rule is about the BODY and
  nothing else, which is what makes it decidable in the parser, so the
  test is `has_body_block` and not the modifiers; every bodiless
  position was probed (overload signature, `abstract`, `declare class`,
  `interface`, object type, function TYPE, `declare function`) and all
  seven report, while the legal spellings are the two the message names
  plus an ARROW — whose body is what follows the `=>`, which is exactly
  what a class field holding `(a = 1) => a` is. TS2394's arity half is
  where probing earned itself back again: the rule is
  ONE-DIRECTIONAL and the message ("not compatible with its
  implementation signature") does not say which direction, so the table
  was probed cell by cell. An implementation that requires MORE
  arguments than a signature can supply is the error; a SHORTER
  implementation is LEGAL (`m(a); m() {}`, `m(a, b); m(a) {}`), because
  a function with fewer parameters is assignable to one with more. Four
  of the eight silent cases in the new test are what a rule written
  from the message text alone would have flagged — the same failure
  mode as TS2415/TS2417, where "different accessibility modifiers"
  reads as "they must match" and two cells go wrong in opposite
  directions.
  Batch DO is +4 for three findings, two of them about code already
  present, and its most useful output is what the FIRST version cost.
  TS7009 is TS2350's rule with one exclusion removed, and the FLAG
  decides which of the two applies: with `noImplicitAny` off `new f()`
  errors iff `f`'s return is not `void`, and with it on there is no
  exemption at all — tsc reports even `function Point(x) { this.x = x };
  new Point(1)`, which is the case CLAUDE.md had recorded as the reason
  for the exclusion. That `resolver.signatures` early return excluded
  every top-level function DECLARATION **by name, before any type was
  consulted**, which was REDUNDANT for TS2350 (an old-style
  constructor's return is `void`, which the return-type predicate
  abstains on anyway) and was the only thing blocking TS7009. Removed
  unrestricted it is +2 corpus files and **5 false positives**, because
  the parser lowers a class declared INSIDE a function to a function —
  so `function outer() { class A { x = 1 } return new A() }` arrives as
  a `Func` and is a legal `new`. TS7009 therefore needs POSITIVE
  evidence where TS2350 could lean on abstention (a top-level function
  declaration, or a WRITTEN call-signature object type), which is +1 at
  FP 0: the file given up was flagged for the unsound reason. Probing
  that also measured a defect this file had only assumed — every
  CHECKER-level class rule is blind to a class declared inside a
  function (TS2420, TS2415 and TS2564 all fire at top level and none
  nested), while batch DN's parser-level TS2394 fires in both, because
  `record_runtime_class_decl`'s stash is taken only by the module-level
  dispatcher.
  The second rule is one arm of `infer_expr` that answered for fifteen
  operators: a compound assignment's value is its RIGHT-HAND SIDE for
  the twelve arithmetic and bitwise ones and NOT for `&&=`, since
  `a &&= b` is `a && (a = b)` and the result is `a` when `a` is falsy.
  So `(results &&= []).push(100)` stays possibly `undefined` (TS2532)
  while the same line spelled `||=` or `??=` is legal — the operator has
  already removed the nullish part there, so widening those would report
  the legal spellings. It needed a second change, and the abstention it
  relaxes states its own reason: the strictNullChecks member-access
  checks are gated to a bare `Var` receiver because those are the
  bindings the narrowing engine rewrites precisely. A `&&=` receiver
  qualifies for the OPPOSITE reason — there is no narrowing to get
  wrong, and the target is inferred through the same `env`, so a guard
  that narrowed it is already in the union.
  The third finding came from probing a LEGAL neighbour for that rule
  and is a pre-existing false positive no gate could see: `+=`'s
  string-concatenation exemption tested for `String_` EXACTLY, so
  `let t = ""` — whose type here is the literal `""`, because tsc widens
  it and we do not — demanded a numeric target and reported ordinary
  string building. Asking assignability widens the EXEMPTION and can
  only lose a finding. Removing it COST two TPs, which is batch CS's
  lesson with the sign flipped: `parserRealSource1`/`2` were flagged for
  `result += "\t"` and nothing else, while their real TS7 error is the
  TS6053 that already put `parserRealSource3` out of scope. A conformance
  file counts as a TP if we flag it AT ALL, so −2 TP is not evidence a
  fix is wrong; they are declared out of scope now, and `--max-miss`,
  added one batch earlier, is what surfaced them — the gate earning
  itself back on its first real use.
  Batch DP closes the defect DO measured: `TsModule.classes` is filled
  by the module-level statement dispatcher, the only thing that took the
  parser's `last_runtime_class_decl` stash, so a class declared in a
  function body was recorded nowhere a rule could read and every
  CHECKER-level class rule was silent at every depth but zero. The
  parser collects those into `local_classes` and the checker merges the
  two at ONE entry point, which is what gives all ~58
  `module_.classes` loops the classes without touching any of them;
  `check_module` is excluded because its first act is a
  duplicate-declaration scan across every top-level kind. Worth +1
  corpus file and the capability at four nesting positions (function
  body, block, `if` branch, arrow body).
  **The merge cost four false positives before it was right, and all
  four are one mistake**: `module_.classes` does not mean "the classes",
  it means "the classes with no enclosing scope", and three rules depend
  on the second reading. The resolver's NAME table must not learn a
  block-scoped name — a nested `class C` beside `let C = f(10)` made
  `new C(20)` resolve to the class and fail its constructor arity
  (`localTypes2`/`3`). `new A()` inside a class nested in A's own method
  is legal, and A's method body is already scanned with
  `enclosing = "A"`, so scanning the nested class as top level reported
  the same expression twice (`classConstructorAccessibility4`). And
  `check_private_member_access` states its premise in its own doc
  comment — "nested class bodies are skipped, their accesses may legally
  reach an outer class's privates" — which the merge broke exactly
  (`privateNameComputedPropertyName3`). So `TsClassDecl` carries
  `is_local`, those three consumers test it and the other fifty-five do
  not; a name already declared at top level is skipped so
  `function f() { class A {} } class A {}` is not a duplicate. Linear:
  a hand ladder of N classes-inside-functions is 32/62/130/267 ms at
  500/1000/2000/4000, exponent 1.02. The remainder is stated rather than
  chased — a nested class whose BASE is also nested cannot resolve its
  base chain, which loses a finding rather than inventing one.
  Batch DQ is the same defect on a second axis, and probing is what
  made it worth taking: TS2420 / TS2415 / TS2564 all fire on a class
  DECLARATION, on `declare class` AND on a namespace-scoped class, and
  on `const C = class …` not one of them did — while a class expression
  is how a mixin, a HOC and a decorated factory class are all written.
  `parse_class_stub` records into `local_classes` from **both** of its
  exits, which is the finding rather than the fix: the native
  `NativeClassExpr` exit is taken ONLY when there is an `extends`
  clause, and a base-less class expression falls through to the desugar
  below it, so recording at the first alone bought exactly the one rule
  that needs a base — TS2415 fired, the other two stayed silent, and
  that asymmetry is what exposed the split. An anonymous class
  expression gets a PER-OCCURRENCE synthetic name, not one shared
  `<class expression>`: the merge skips a repeated name, so a shared one
  would check only the first anonymous class in a file and a file with
  several is the normal case. +3 corpus files.
  Its one false positive is DP's lesson on a fifth axis and the sharpest
  version of it: TS2449 ("class used before its declaration") compares
  INDICES in `module_.classes`, which encode top-level source ORDER —
  and a local class is appended, so its index is not a position at all.
  Read as one it made every top-level class whose base shares a name
  with a class expression look forward-referencing
  (`accessorsOverrideProperty8`, where `const Base =
  classWithProperties(…, class Base {})` sits beside `class MyClass
  extends Base`). Exempting local classes on both sides costs the mirror
  MISS — `const D = class extends B {}; class B {}` IS TS2449 and stays
  quiet — which is the affordable half. So `module_.classes` turns out
  to carry THREE meanings its consumers read separately: the set of
  classes, the set with no enclosing scope, and their source order.
  Batch DR is three rules on the nullish operators for +3 files, and
  each one's boundary had to be probed because reasoning gives the wrong
  answer. TS2869 ("right operand of `??` is unreachable") is purely
  SYNTACTIC in tsc: `false ?? true` and `{} ?? y` report while
  `const m = false; m ?? true` and `declare const s: string; s ?? "b"`
  are ACCEPTED — neither can be nullish either — so a type-level version
  would have reported two shapes tsc allows. `null` / `undefined` get a
  different code (TS2871) and `void 0` is a declared MISS, because tsc
  reports TS2869 there while the right operand really IS reached and
  following it would encode a compiler quirk. TS18048 / TS18049 is the
  other side of the same operator: the right operand runs only when the
  left is nullish, so inside it the left BINDING is narrowed to its
  nullish part and a member access on it is always an error
  (`f ?? f.toFixed()`). That rule matches the right operand's SHAPE
  instead of walking it, and the reason is soundness rather than
  economy — an assignment anywhere inside the RHS makes the binding
  non-nullish again (`s ?? ((s = "x"), s.length)` is ACCEPTED,
  measured), and a walk that missed an assignment form would fail OPEN
  into a false positive, while an access that IS the whole right operand
  can hide nothing. TS2790 is the applied-in-some-places family again
  and the FOURTH wrapper-node fail-open miss: `delete o.b` was checked,
  `delete o?.b` arrives as `OptionalChain(PropAccess(…))` and the match
  saw the WRAPPER, and `delete o["b"]` — the same property reference
  spelled with brackets — had no arm at all.
  Its REJECTION is worth as much as the rules, because the blocker is
  mechanical and exact. TS7031 / TS7018 (a nullish literal where a type
  must be inferred, under `noImplicitAny` with `strictNullChecks` off) is
  one sound rule covering three codes, and `var [a, b]: any = [undefined,
  null]` is ACCEPTED by tsc while the unannotated form is TS7031 — yet
  `TsStmt::Let` / `Const` / `Var` carries a `TsType` in which an ABSENT
  annotation and an explicit `: any` are the same `Any`. The parser has
  that fact at parse time (`parse_param` records it in
  `written_any_params` off `had_annotation`), so the fix is a
  declaration-level version of that channel plus a `strict_null_checks`
  field on the Parser, which has `no_implicit_any` and not this one.
  Batch DS is TS2386 / TS2394 / TS2565 for +3 files, and its lesson is
  that all three read WRONG from their message text. TS2386 ("overload
  signatures must all be optional or required") is purely about the `?`,
  so it needs no type and lives in the parser — and it needed FOUR sites,
  because a runtime class body, an interface, an object type literal and
  `declare class` each have their own member parser; the applied-in-some-
  places family taken completely on the first pass instead of discovered
  a batch later. In a runtime class the IMPLEMENTATION participates as
  REQUIRED, which is what makes `m?(x); m?(s); m(v) { }` an error tsc
  reports on both signatures, and `declare class` was the site with
  nothing because its member parser DISCARDED the `?`
  (`let _ = self.match_(Question)`). Only METHOD signatures participate:
  two same-named PROPERTIES are a duplicate identifier (TS2300 / TS2717),
  a different error that already fires, so putting properties in would
  report one declaration twice.
  TS2394's parameter half is where batch DN's recorded blocker finally
  dissolved. `TsFunc.body` is not optional, so an overload SIGNATURE and
  an implementation are indistinguishable downstream — and
  `note_function_declaration` is already called at every site that pushes
  a function declaration, with exactly the `bodiless` fact, so a
  `<fn-impl:NAME>` marker turns "the last declaration is the
  implementation" from the guess `check_overload_void_return` had to make
  into a FACT. The rule went into that same function rather than beside
  it. The marker is pushed ONLY from the module / namespace body loop,
  because `grammar_misuses` is a flat scope-blind channel and a nested
  `function f() { }` would otherwise claim an implementation for a name
  that exists in another body — the same restriction is why TS2393 is
  filed rather than shipped. Probed cell by cell, since the message does
  not say which direction: an incompatible parameter TYPE is the error,
  an implementation with FEWER parameters is LEGAL, and `any` accepts
  everything.
  TS2565 is expando flow — `function d() { }` then `d.e = 12`, and
  reading a property assigned only in a conditional branch — and its
  design decision is where the value is. One ordered pass per statement
  list tracks DEFINITE / POSSIBLE per `HOLDER.PROP`, and the `if`
  statement is the ONLY construct that can produce POSSIBLE: a write in
  anything the pass does not model counts as DEFINITE, so an unmodelled
  shape silences the check instead of firing on it. That is exactly what
  `switch (1) { default: d.q = 1 }` needs, since the default arm always
  runs and tsc accepts the read after it, so any reachability-aware
  formulation would have false-positived there. The price is the `while`
  case, which tsc does report, and that MISS is what buys FP 0. Three
  facts had to be probed rather than reasoned: `d["q"] = 1` and
  `d.q = 1` are NOT one rule (inside an `if` arm the bracket spelling
  makes the later `d.q` LEGAL and the dotted one does not, so the two
  spellings are collected separately); passing the holder to a function
  does not assign the property, and neither does `Object.assign`, so the
  report still stands; and a read from ANOTHER scope is legal however the
  property was assigned, which is why the READ walk stops at a nested
  function body and at a nested block while the WRITE walk descends into
  both. Two parser facts cost the first two drafts, and both are this
  file's recurring shape: `d.q = 1` at the top of a list is a
  `PropAssign` STATEMENT while the identical line inside a block is
  `Expr(PropAssignExpr(...))`, and reading only the first found NOTHING
  AT ALL; and a top-level `function d() { }` is parsed by the module loop
  into `module_.funcs` and is NOT pushed into `top_level_stmts`, so the
  outermost list has to be told about those holders by name.
  Batch DT is +2 files for two rules, and its reusable finding is about
  a KIND of lead rather than about either rule: both were the
  applied-in-some-places family, and at the missing site each carried a
  comment declining the rule with a stated reason that turned out to be
  FALSE. A recorded abstention is a lead — and its REASON still has to be
  probed. TS7010 ("lacks return-type annotation, implicitly has an `any`
  return type") existed for a bodiless `function` declaration and for
  `declare function` and for nothing else, so an interface method, an
  object-type method, a class overload signature, an `abstract` member
  and a `declare class` member were all silent; the class site's comment
  said "tsc does not flag an overload signature whose implementation
  carries the return annotation", and probing gives the inverse —
  `m(); m(x: number); m(x?: number): void { }` reports on BOTH
  signatures while annotated signatures with an unannotated
  implementation are ACCEPTED, because the exemption belongs to the BODY
  and not to the overload set. TS7022 / TS2448 (a binding whose own
  initializer evaluates a reference to it) existed for a `for…of` head
  and was missing at the DECLARATION site, so `let x = x` and
  `const x = [x]` were silent; the head rule's two-arm walk was
  justified by "a name reached through a call or a property is not the
  iterable itself, so widening this would claim a cycle that is not
  one", and the real line is not call-versus-property but whether the
  reference is EVALUATED before the binding initializes —
  `for (let v of [v])`, `[1, v]`, `g(v)` and `[...xs, v]` all report,
  `o.v` does not (a property name is a `String` in this AST and can
  never be reached as a `Var`), and `[() => v]` does not. Two codes, one
  condition, each gated on the fact it needs: TS2448 applies to
  `let`/`const` whatever the annotation says, since a TDZ is about time,
  while TS7022 needs the annotation ABSENT and is all a `var` gets.
  Threading the annotation fact in from the parse site also closed a
  pre-existing false positive the head rule's own comment had promised
  not to have — it gated on `var_type is Any`, which cannot tell an
  absent annotation from an explicit `: any` (the same blocker recorded
  for TS7031), so `for (var v: any of v)` was reported; and that
  spelling is not "legal" either, it is TS2483 + TS2502, two codes this
  rule does not claim, so the old behaviour was the right file for the
  wrong reason. Three pre-existing tests asserted the TS7010 gap BY
  NAME — the eighth, ninth and tenth in this repo found doing that —
  because `parse_module_or_empty` defaults `noImplicitAny` to true and
  all three wrote `class C { foo(x: number); foo(x: any) {} }` while
  asserting 0, so each was measuring the implicit-any hole rather than
  the overload rule it is named for.
  The batch also corrects the triage twice, both times the
  label-for-objective substitution: TS7023 and TS7053 were filed as
  "cheap and mechanical" implicit-any work and are neither. TS7023's
  three files all need an inference CYCLE detector through a class
  method's un-annotated return type, and the only cheap version keys on
  the exact corpus shape; TS7053's two need union-of-index-signature
  member resolution and assignment-target widening of
  `(options || {}).a`, which is why both files also carry TS2339 /
  TS2322. Five files moved to Tier 3.
  Batch DU is +1 and is the THIRD batch in a row whose target was a
  recorded abstention and the third whose stated reason was false, which
  promotes the move to a rule: open the comment that declines a rule,
  then probe its reason. `check_class_property_init_order` restricted
  TS2729's candidate set to init-bearing fields, saying a field declared
  without an initializer "has no initialization to be used before". It
  has — `class C { b; d = this.b }` and `class C { b: number; d = this.b
  }` are both TS2729 in EITHER declaration order, because a slot only
  written in the constructor is still `undefined` while field
  initializers run, so such a field never enters the `inited` set and
  order does not matter for it. The real exemption is a MODIFIER, and
  probing one cell at a time gives exactly two, `!` and `?`. It is
  emphatically not "the declared type admits undefined":
  `b: number | undefined`, `b: any`, `b: unknown` and `b: void` all
  report, and so does the whole thing under `strictNullChecks: false`, so
  a rule written from the type would have been wrong in four places. And
  since the parser wraps `x?: T` into exactly `T | undefined`, the `?`
  CANNOT be read off the type — it rides an `<optional-member:` sentinel
  recorded before the wrap, the same shape as `<quoted-member:`, which
  exists because TS2564 needed a fact the type could not carry either.
  `scopeResolutionIdentifiers`, the false positive the old abstention was
  protecting against, is the `s!: Date; n = this.s;` form, so it was
  avoided for the wrong reason and is still avoided for the right one.
  One declared MISS at the site: `declare b: T` is TS2729 in tsc, and the
  parser folds `has_declare` into `has_definite_assertion` — correctly,
  for TS2564 — so an ambient field reads as asserted here.
  Batch DV is +3 and is the batch that OVERTURNS one of these
  abstentions rather than an old one: batch DT had declined exactly these
  three files, saying "the only cheap version would key on the exact
  corpus shape", and the thing that settles it had been in the corpus the
  whole time. `for-of25` and `for-of26` are `for-of33` and `for-of34`
  with the returned name changed from the loop variable `v` to an
  unrelated `var x: any`, and both are TS7-ACCEPTED — so the
  discriminator is the NAME, which is the actual semantic distinction and
  not a match on file contents, and the corpus supplies twelve negative
  controls for free. Fourth time in this series that a stated
  abstention's reason turned out weaker than claimed, and the first where
  the abstention was written one batch earlier by the same pass. The rule
  is TS7022's INDIRECT form: a `for (var v of new C)` head takes its
  element type from C's iteration protocol, so an un-annotated `next()` /
  `[Symbol.iterator]()` that RETURNS `v` is a genuine inference cycle.
  It lives entirely in the PARSER, which is what keeps it small — the
  class body records the bare `Var` names its un-annotated protocol
  methods return, keyed by class name, and
  `record_for_head_binding_misuses`, where the DIRECT form already lives,
  joins against `new C`; the mention test is `collect_iterable_var_names`,
  the same walk, because "does this expression evaluate a reference to
  NAME" is the same question and a second walk would be the
  applied-in-some-places family in its purest form.
  Three gates keep it off legal code and all three were probed. Only the
  two PROTOCOL methods count — a `helper()` returning the loop variable
  is ACCEPTED, since nothing consults its return type. An annotated
  return breaks the cycle, so the rule needs `had_return_annotation`
  rather than `return_type is Any`, the same absent-versus-`: any`
  blocker recorded for TS7031 and TS2729. And a name the method itself
  BINDS is its own local: `next() { let v = { value: 1, done: false };
  return v }` beside `for (var v of new C)` is TS7-ACCEPTED, so firing
  there would be a false positive on legal code that NO corpus file
  covers — the bound-name set is over-approximated on purpose, losing
  findings rather than inventing them.
  The other half of the indirect form is NOT covered and is Tier 3, and
  probing is what drew the line: the reportable class is generic
  return-type inference from a CALLBACK, since `let x = arr.map(v => x)`
  reports while `let x = g(() => x)` with `g` declaring its return type
  is ACCEPTED, as are `let x = function () { return x }`, `[() => x]`
  and `{ m: () => x }`.
  Batch DW is +1 and is the first batch here whose target abstention
  probing CONFIRMED, which is worth as much as the four it refuted. The
  rule that shipped is a different bug: two sites held one decision and
  gave opposite answers. `check_expr_against`'s
  `(ObjectLit, Applied(name, _))` arm deliberately routes the six
  projectable utility types into `check_object_lit_against_target` — its
  own comment says so, "since `lookup_field` / `collect_declared_fields`
  know how to project their field shapes" — and that function threw them
  straight back out through TWO early returns, `member_recv_unmodeled`
  and `type_contains_unresolved_named`, both of which call any `Applied`
  to a non-class, non-interface name unresolvable. So
  `{ black: { r, g, d } } satisfies Record<string, Color>` reported
  nothing. The exemption is `Record` ONLY and only with a bare
  `string` / `number` key, and the wider version was implemented and
  MEASURED before being cut down: every projectable utility judged by all
  of its arguments is +1 TP and +1 FP, the false positive being
  `f20<T, K extends keyof T>(obj: Pick<T, K>)`, which accepts any object
  literal because `T` is inferred FROM the argument.
  The confirmed abstention is the excess-property check at CALL
  ARGUMENTS. A position matrix says the check covers the annotated
  declaration, `return`, an array element, `satisfies`, assignment and a
  nested property and is missing at every CALL position, which is the
  commonest place real code hits TS2353 — and the one-line suppression
  guarding it (`sub_path.contains("arg[") && target is Object(_)`) is
  load-bearing: removing it is +0 TP and +3 FPs on hand-written
  TS7-accepted code, because a constrained type parameter's bound really
  IS inlined into the parameter position, so
  `foo<U extends { length: number }>(x: U)` accepts
  `{ length: 1, extra: 2 }` and the earlier early returns do not catch
  it. Corpus-wide the blunt removal is +0 TP / +1 FP. The shippable
  version gates on the CALLEE being non-generic — no type parameters
  means no bound can have been inlined — and is filed rather than built,
  because it buys no conformance file and the real-world diagnostic is
  its only argument.
  Batches DX and DY are the first two in this series whose conformance
  yield is ZERO BY DESIGN, and they are the answer to a question the gate
  cannot ask. DX runs the excess-property check at a CALL argument — the
  commonest place real code hits TS2353, and a position the corpus does
  not test at all — behind the one fact that makes it decidable:
  `callee_non_generic`, proven only at a direct call to a resolved
  function declaration and at `new` on a resolved class, defaulting to
  `false` so any site that cannot answer keeps the suppression. An
  ABSENT entry in `func_type_params` is explicitly not proof, since a
  call-signature-typed variable and a lib method have no entry either.
  Both nested shapes under an argument come along, because a nested
  target came from a `lookup_field` on a written parameter type. A method
  call and a call through a function-typed binding stay MISSes, neither
  site being able to prove the callee's genericity.
  DY is the assignment-form `for…of` target at its other two spellings:
  the check fired for a bare `Var` and was blind to `o.x`, `foo().x` and
  `arr[0]`, because the parser wraps a non-identifier head as
  `TsBinding::Target(expr)` and that fell through to the
  destructuring-pattern arm. Its zero is more informative than the rule:
  `ES5For-of8` is `function foo() { return { x: 0 } }`, and an
  UN-ANNOTATED function's return type does not resolve here at all —
  `const bad: string = foo().x` is silent too — so the file needs
  return-type inference from a BODY and never needed this rule.
  The same round priced the rest of the assignability bucket by opening
  every file, and the answer settles the strategy: **35 files, ~35
  causes.** The four cheapest-LOOKING (a plain `number` / `string`
  mismatch, a shape this checker does flag) each need something
  different — a well-known-symbol accessor pair's inferred type,
  object-literal union normalization on widening, expando + namespace
  declaration merging, and the return-type inference above. `globalThis`
  at 3 files is the only mini-cluster. The measured rate is about one
  file per investigation, so the conformance number has stopped ranking
  work a second time, and what remains worth taking is what the corpus
  cannot score: 83 of the 134 misses carry exactly one error code and 25
  of the 39 solo codes have exactly one file.
  Batch DZ is +1 and its value is what it says about the TRIAGE's own
  family table rather than about the rule. The
  "strict-null / narrowing" bucket is five files, and the label is wrong
  about **all five**: opening each one, the cheapest lever is pure grammar
  (TS18030), a `this`-rebinding context (TS2331), name resolution in a
  type-argument position (TS2749), `[]`-to-`never[]` inference plus flow
  analysis (TS2403 / TS2454), and aliased control flow (TS18046) — five
  unrelated kinds of work, not one. Eighth instance of a label standing in
  for the objective, and the first in a bucket small enough that the count
  looked trustworthy; a bucket of five is not safer than a bucket of
  forty-eight, it is just faster to disprove.
  The rule that shipped is TS18030, an optional chain containing a
  private identifier, and it lives in the parser because the POSITION of
  the `?.` relative to the `#name` is the whole rule. One chain-local
  flag set where `?.` is consumed and tested at both sites that read a
  chain property, rather than a condition at each — `this?.#b` (directly
  after the `?.` that opens the chain) and `this?.a.#b` (later, through a
  plain `.`) are one fact. Chain-LOCAL is what makes two legal
  neighbours automatic instead of needing rules: a private access inside
  a call argument within the chain (`this?.getA(o.#b)`) is parsed by its
  own invocation of the postfix loop, and so is the inner expression of
  `(this?.c).#b` — and that second one is the case worth probing, because
  `(this?.c).#b` is TS2532 and NOT TS18030, so parenthesizing really does
  end the chain. Reasoning would have got it wrong either way; the probe
  settled it, and tscheck now agrees with tsc on all seven spellings.
  TS2331 is DEFERRED on a measured cost rather than on difficulty, which
  is worth recording because the rule looks free. Probed cell by cell: an
  arrow inside a namespace body fires at any depth, a `function`
  declaration OR expression inside one does not (it rebinds `this`), a
  class method does not, and neither script top level nor module top
  level does — so the fact needed is "inside a namespace body and not
  inside a `this`-rebinding function". `in_function` cannot serve,
  because it is true inside arrows too, and a new field needs the same
  save / clear / restore discipline `self.labels` already needs at
  fifteen function-body sites. That is precisely how the
  applied-in-some-places bug gets written, for +1 file.
  Batch EA is +3 off the compiler-probed long tail, and the ranking now
  says there is nothing but tail left: **132 files and 85 codes with
  exactly one file each**, with the four largest buckets (TS2322 14 solo,
  TS2345 10, TS2339 7, TS2403 4) being variadic tuples, template-literal
  types, conditional types and contextual typing, and every remaining
  2-file cluster expensive for its own unrelated reason — TS2411 needs
  `Object`'s own members modelled, TS2367 intersection assignability,
  TS2464 and TS2349 overload resolution, TS18033 a destructured binding's
  type. So three unrelated single-file rules is what this tier looks
  like, and two of the three are worth more for what probing settled than
  for the file.
  TS2526 ("a `this` type is available only in a non-static member") reads
  as a claim about MEMBERSHIP and is really about which declaration the
  type is written in, so every cell was probed rather than reasoned. A
  constructor's PARAMETER LIST is an error and its BODY is not —
  `constructor() { let self: this = this }` is ACCEPTED — which is the
  cell the message text gets wrong, and NESTING opens no new `this`
  context, so `constructor(a: { m(): this })`, `Array<this>`, `this[]`
  and `(x: this) => void` all report while every instance member and
  every interface member including a CONSTRUCT signature stays silent.
  Three positions tsc reports are declared MISSes with the reason at the
  site, and the first is a rule about this repo rather than about
  TypeScript: `type T = { m(): this }` is TS2526, and the bridge
  generator runs `check_module` over real `.d.ts` input, where a false
  positive costs generation rather than a conformance file. Its walker is
  written out instead of reusing `type_references_any(ty, ["this"])`
  because that one has no `CallableMeta` arm — the wrapper the type
  parser puts around a callable with an optional parameter, and the sixth
  fail-open wrapper arm in this file's ledger, this time costing only a
  MISS.
  TS2767 is the fifth batch in a row aimed at a recorded ABSTENTION and
  the second where the stated blocker was true but named one of two
  routes to the fact. Its comment said an unannotated `return = 0` leaves
  the class parser recording `Any`, and that firing on `Any` would flag
  `return = () => …` — the legal spelling of the same member — both
  correct, and the INITIALIZER was in `instance_field_inits` all along,
  where "this cannot be callable" is decidable from the expression's
  shape. An ALLOWLIST of literal forms, so an unclassified spelling is a
  MISS: `return = 0 as any` is `any` and tsc ACCEPTS it, so peeling `As`
  would have been a false positive, and `null` is excluded because with
  `strictNullChecks` off it widens to `any` and is accepted. The
  batch-DF test carried that exact source in its SILENT list — the
  eleventh test here found asserting a gap rather than a behaviour.
  TS2842 ("an unused renaming … did you intend to use it as a type
  annotation?") is a parser rule about bodiless-ness, and its trap is
  that one LEGAL spelling parses through the very same code as an illegal
  one and both are in the corpus file:
  `type F3 = ([{ a: b }, { b: a }]) => void` is the error twice, while
  `type T3 = ([{ a: b }, { b: a }])` is a parenthesized TUPLE TYPE whose
  `{ a: b }` is an object type with a member `a` of type `b`. Both reach
  `parse_paren_or_function_type`'s parameter loop, which re-parses when
  no `=>` follows, so the renamings ride a `last_param_pattern_renamings`
  slot and become findings only after the arrow COMMITS — recording at
  the point of the pattern would have flagged a legal line in the file
  the rule was written for. Two detectors for one question, because
  `parse_param` builds a real `TsBinding` and `parse_declare_param_name`
  brace-matches past the pattern and keeps nothing; the AST half is the
  more precise one, since a DEFAULT has its own field there, where the
  token scan must stop at the `=` or an object literal inside an
  initializer reads as a pattern. Six call sites, and they are the set
  TS2371 already uses.
  Two findings that are not rules. `var m: typeof A` for a
  non-instantiated namespace is SILENT while `var q = A` fires, so
  TS2708 has a second hole independent of the alias one its comment
  records: a `typeof` TYPE position never reaches `check_undefined_name`
  at all, and that is the position a `.d.ts` uses.
  `importStatementsInterfaces` needs both channels, which is why it is
  still a MISS. And TS1308 inside a decorator expression is blocked on
  `skip_param_decorators` discarding the expression, not on the rule: the
  boundary is exact and probed, since a parameter decorator runs in the
  scope OUTSIDE the class, so the same class body is TS1308 in a plain
  `function` and ACCEPTED in an `async` one.
  `src/checker/UNSUPPORTED.md` is the companion this section had been
  missing, and writing it is what produced the next batch. The triage
  classifies the backlog by the MACHINERY a rule needs; that file shows
  the CODE a user would write, every snippet minimized and run through
  both `tscheck` and the real compiler, so each entry is a measured gap
  rather than a guess — and where `tscheck` reports something DIFFERENT
  from tsc it says so, because a file can be flagged for the wrong reason
  and the oracle counts it either way. It corrected itself twice while
  being written, both times the label-for-objective substitution: TS2403
  and TS2411 read as gaps because four and two MISS files raise them, and
  `var x: number; var x: string;` and
  `interface I { bar: number; [x: string]: string }` are ALREADY flagged,
  so those files fail for unrelated reasons. Its own headline rule is to
  open the corpus file before taking anything.
  Batch EB took four of its sections for **+8 files at FP 0** (TP 2586 ->
  2594, MISS in scope 129 -> 121), and three of the four were narrower
  than the section that asked for them. "Overload resolution", a Tier 1
  row, turned out to be one missing instantiation: the members are
  already ingested as a Union of `Func`s and `infer_call` already selects
  by argument assignability, but type parameters are recorded per NAME in
  `func_type_params`, which is OVERWRITTEN per declaration — so for
  `f(s: string); f(n: number); f<T>(x: T); f(x) {}` it holds the
  IMPLEMENTATION's empty list, the generic member reached the union arm
  as `Func([Named("T")], Named("T"))`, matched nothing, and the call came
  back carrying an unresolved `T` that every downstream check reads as
  unknowable. `func_overload_type_params` (the union across a name's
  declarations, its own map because the existing consumers want the
  per-declaration answer) plus an instantiating pass tried only AFTER
  every non-generic member has failed — TypeScript's own order, so a call
  a concrete overload accepts keeps the answer it already had.
  TS18033's blocker was not the type either, which is what the triage
  assumed: the checker already infers `string | number` for
  `const { value = "123" } = thing` and `{}` for a block-local
  `let Infinity = {}`, measured before anything was written. The enum AST
  keeps FOLDED LITERAL values only, so the initializer expression never
  reaches the checker at all; a `<enum-init-name:NAME>` marker carries
  the one shape worth deciding and the checker resolves it in the
  top-level env, which is where a DESTRUCTURED binding lives. Its
  definitely-non-numeric set excludes LITERAL types, and that is the cell
  reasoning gets wrong: `declare const s: string` is TS18033 while
  `const s = "a"` — type `"a"` — is ACCEPTED, because a string literal
  initializer is how a string enum member is written.
  TS2367 on intersections had BOTH halves already, in the wrong place.
  `cast_shape_fields` plus "each side requires a property the other
  lacks" is the comparability test the `as` path has used for
  `typeAssertionsWithIntersectionTypes01` all along and the equality arms
  never asked; it is `shapes_definitely_disjoint` now and both call it,
  `==` included — restricted to object shapes, because `==` coerces a
  primitive against an object (`{} == "[object Object]"` is true) while
  object against object is reference equality. And
  `equality_primitive_family` gained an `Intersection` arm, since every
  value of `T & number` is a number whatever `T` is, with `Any` /
  `Unknown` / `Never` in a part abstaining outright: `any & number` IS
  `any`, so answering "number" there would report a comparison tsc
  accepts.
  `globalThis` is the one that was a real hole, and it was the
  applied-in-some-places family twice. The READ form
  (`var r = globalThis.y`) was all the rule judged; the WRITE form was
  missed at BOTH spellings, because `globalThis.y = 4` at the top of a
  list is a `PropAssign` STATEMENT and the same line inside a function is
  `Expr(PropAssignExpr(…))`, and both arms walked the RECEIVER and the
  VALUE while the property NAME sat in the node itself, tested by
  neither — with the legal neighbour four lines away in the corpus file,
  since `globalThis.x = 3` beside a `var x` IS legal. A top-level
  `function f() { … }` body was not reached at all, the batch DS parser
  fact again. `this` at script scope IS `typeof globalThis`, arrows
  included, and it gets its OWN region-scoped walk rather than a flag
  threaded through that one, because the two questions have different
  REGIONS: `globalThis.x` means the same in any body, `this` means the
  global object only where nothing has rebound it — an arrow keeps it, a
  `function` does not, and tsc reports TS2683 there instead. The cell
  reasoning gets backwards is that `this.zzz = 1` is ACCEPTED (a new
  global property may be created) while `this.name` is not, because
  `name` is `declare const name: void` in the DOM lib and a block-scoped
  LIB global is not a `globalThis` property either;
  `is_lib_dom_blockscoped_value` is generated from the lib sources for
  that — one name in the whole set — and is DOM-scoped rather than
  unioned because webworker declares the same name with `var`. My own
  measurement was wrong once here in this file's recurring way: grepping
  for `does not exist on` counted the EXISTING class-member check's
  report on `class C { m() { this.name = 1 } }` and read it as a false
  positive of the new rule, where grepping the path prefix shows the walk
  never enters a class body.
  Batch EC took the two "unwired" rows of `UNSUPPORTED.md` section G —
  the table of rules blocked on a MECHANICAL fact rather than on
  machinery — for **+3 files at FP 0** (TP 2597 / MISS in scope 118),
  and its reusable finding is about that table: **a blocker written down
  is a claim with a date on it, and both of these had been removed by
  earlier work that was not aiming at them.** TS7031 / TS7018 is one
  rule with two spellings (with `strictNullChecks` off, `null` and
  `undefined` widen to `any`, so under `noImplicitAny` an inference from
  them is an error), and which CODE applies is decided by the BINDING,
  matching tsc: `var {a} = {a: null}` is TS7031 on `a` and NOT TS7018 on
  the property, so a pattern runs only the element half and an `Ident`
  binding only the object-literal half. It belongs in the PARSER because
  the fact it needs is not in the AST — the same absent-versus-`: any`
  blocker recorded for TS7022, TS2729 and TS2448 — and HALF the recorded
  blocker was already gone: `last_var_decl_annotated` carries the
  annotation fact and `parse_var_decl_item` reads it BEFORE the
  initializer is parsed, so a nested declaration cannot make this one
  look annotated. Only `strict_null_checks` had to be added to the
  Parser, and needing BOTH flags is what keeps the rule off real code: a
  directive-less file defaults to `strictNullChecks: true`, which every
  `.ts` / `.d.ts` the bridge parses is, so it cannot fire there at all.
  Three cells read the other way round from the message text: a DEFAULT
  supplies the type, so `var [a = 1] = [undefined]` and
  `var {a = 1} = {a: null}` are ACCEPTED — true even for `null`, which
  does not trigger a default at runtime; `var a = undefined` is legal
  and `var o = [null]` is TS7005 on the VARIABLE, so an array element is
  never reported; and a renamed property reports the LOCAL name while a
  hole keeps its position. The abstentions lose a finding rather than
  invent one, and the one that matters is the reason the rule is sound
  where it sits: a call argument's object literal is CONTEXTUALLY typed
  and LEGAL, this site cannot tell it from an inferred one, and an
  unannotated declaration has no contextual type by construction. It
  needed TWO sites and got both on the first pass — statement-level
  `using` routes through `parse_var_decl_item` while the BLOCK-statement
  `using` is its own parser, and that is the one every
  `usingDeclarations` test actually writes, so a recorder at the first
  alone would have reached neither corpus file.
  TS2331's blocker was stated in writing as "a new Parser field needs
  the save / clear / restore discipline `self.labels` needs at fifteen
  function-body sites", and batch EB had dissolved it ONE BATCH EARLIER
  by building `this_region_walk_stmt` for the `globalThis` rule: its
  region — an arrow descended into, a `function` body and a class body
  not — IS TS2331's region. So the rule is a second `ThisRegionVisitor`
  over the same walk, and the visitor grew a `bare` callback beside
  `prop` because the two consumers ask different questions about the
  same node (the `globalThis` rule wants the property read off `this`;
  TS2331 wants the `this` and never reaches the property). Twelve cells
  probed and all now agree with tsc, including the two legal neighbours
  that fall out of the walk for FREE — a class lives in
  `module_.classes` rather than in `top_level_stmts`, and an
  object-literal method's value is a `FuncExpr` the walk has no arm for.
  A class DECORATOR came along on the argument TS2660 already makes for
  `super` (a decorator expression is evaluated where the class is
  DEFINED), reading `module_.classes` and never `local_classes`, since a
  class declared inside a function is decorated in that function's scope
  and tsc gives TS2683 there. The corpus file is the MEMBER-decorator
  spelling, which needed a different mechanism that was also already
  present: member decorator expressions never reach the AST and a
  namespace body is parsed by a FRESH `Parser` that cannot know it is
  one, so the class parser leaves a `<this-in-decorator>` sentinel and
  `parse_namespace_decl_with_mode` converts it where the context is
  known — exactly how TS1063 / TS1319 already work, with an unconverted
  sentinel staying a `<`-prefixed marker the grammar loop skips.
  `decorator_mentions_super` became `decorator_mentions_name(d, name)`
  rather than gaining a twin, because "does this decorator expression
  mention NAME" is one question. The file TS2331 does NOT buy is worth
  recording with its exact blocker: `typeofThis.ts`'s error is
  `typeof this.no` in a TYPE position, and `parse_typeof_type_query` has
  no `This` arm, so `skip_typeof_operand` eats the operand and the
  annotation collapses to `Any` before any checker sees the `this`.
  Batch ED is **+1 file** plus one declared OUT OF SCOPE (TP 2598 / MISS
  in scope 116 / OUT OF SCOPE 20), and all three of its findings are
  worth more than the file. First, a class-member modifier spelled as a
  CONTEXTUAL KEYWORD may not be followed by a line terminator — the
  grammar writes `accessor [no LineTerminator here] ClassElementName` —
  so `class C { accessor` / `a }` declares TWO members and eating the
  keyword as a modifier LOSES a field from the emitted class as much as
  from every rule that reads the member list. The covered set had to be
  probed one keyword at a time, because it is not "the TypeScript-only
  ones": `readonly`, `public`, `private`, `protected`, `abstract`,
  `override`, `async`, `accessor` and `get` / `set` all become a member
  NAME across the break, and `static` — the one the ECMAScript grammar
  spells with a reserved word — does not. One test in
  `can_consume_class_modifier` with `static` passing
  `allow_line_break=true`, the default being the RESTRICTIVE answer so a
  modifier added later inherits the rule; the `get` / `set` arm spells
  its conditions inline instead of calling that helper, which is why the
  rule needed writing at both. `declare` is a twelfth spelling
  deliberately left alone: it has its own TOKEN kind, so the modifier arm
  never sees it and the `Declare` arm advances with no guard at all, and
  gating it makes the member name a `Declare` token the field-key parser
  rejects — the class stops parsing, a PFLEGAL, which is worse than the
  MISS. Second, `class C { q = 1; q = 2 }` was SILENT, and the clause
  that decides it was already written twenty lines below in the
  PRIVATE-name loop with the reason in its own comment: the public
  duplicate counter's condition misses the case where the repeats are ALL
  fields, so `nf >= 2` was the whole fix. Fifteen cells now agree with
  tsc, including the legal repeats (instance + static, keyed apart as
  `name|s` / `name|i`; a get/set pair; an overload set), and the
  `#private` diagnostic had to be taught to print `#q` rather than
  `__private_brand__0__q` — the same lesson TS7008 records, and the
  private loop turns out to be dead for a runtime class because the
  lowering renames `#q` before the member list is built.
  Third, and the reason the out-of-scope entry exists: **the probe was
  attributing OTHER files' diagnostics to the probed file.**
  `scripts/lib/tsc-probe.mjs` calls `getSemanticDiagnostics()` with no
  argument, which returns EVERY file's diagnostics, so
  `objectTypeWithStringIndexerHidingObjectIndexer` — 33 lines — was
  ranked by `TS2411(123,5)`, a line it does not have: its
  `interface Object { [x: string]: Object }` augmentation under
  `@skipDefaultLibCheck: false` makes tsc type-check `lib.es5.d.ts`
  itself and every diagnostic lands THERE, while the test source is
  error-free. `probe()` splits `diags` from `otherFiles` now, and
  re-running the whole MISS list says this is the ONLY one of 118 where
  nothing is in scope — its sibling really does carry an in-file
  `TS2411(13,5)`. Ninth instance of the measuring instrument carrying the
  same substitution bug as the code, and the first where the bug was
  manufacturing a MISS rather than hiding one. What the re-ranking says
  about the remainder: **116 files, 70 with exactly ONE error code and 84
  codes with exactly one file**, and opening TS2403's four solo files
  gives four unrelated mechanisms — spread-type computation, types
  inferred through OVERLOAD resolution (the ANNOTATED shape
  `var r: E; var r: Object` is already flagged), `this`-type resolution
  plus the rule inside a method BODY, and contextual typing.
  Batch EE closes the last three rows of `UNSUPPORTED.md` section G for
  **+2 files** (TP 2600 / MISS in scope 114), and with it **all five of
  that table**, whose real finding is about the table itself: a blocker
  written down is a claim with a date on it, and **not one of the five
  survived being probed.** Two had been dissolved by later work that was
  not aiming at them, one was true of an approach nobody had to take, one
  named only one of two routes to the fact, and TS2393's was not a
  blocker at all. TS1308's recorded blocker — `skip_param_decorators`
  discards the decorator expression, so the `await` never reaches the
  AST — is TRUE and beside the point: a TOKEN sighting over the range
  that skip already consumes needs no AST, because every `await` must
  spell `await`, the same completeness-by-construction argument the
  `#private` rules make for a class-body span. Its region is the cell
  reasoning gets wrong — a parameter decorator is evaluated where the
  CLASS is defined, so the async context that matters is the ENCLOSING
  function's and the method's own `async` is irrelevant, with `function`,
  `function*` and a plain arrow all TS1308 and `async function` and an
  async arrow both ACCEPTED; `in_function` is required because top level
  is TS1375 / TS1378, codes this rule does not claim. TS2393 had no
  blocker: `<fn-impl:NAME>` is pushed once per IMPLEMENTATION and the
  consumer built a `Map[String, Unit]`, so the COUNT was thrown away at
  the point of USE — the marker was right and the reader was lossy.
  Counting gives the rule, reported BEFORE the overload rules and taking
  the name out of them, since a name with two implementations has no
  overload SET and "this overload signature is not compatible with its
  implementation signature" was the wrong sentence for it — the right
  file for the wrong reason. The marker also had to be added at the FOUR
  export sites, which had none, so `export default function f() { }`
  twice recorded no implementation at all; one of the four passes `false`
  rather than `last_function_bodiless` because that arm parses through
  `parse_function_expr`, which does not set the flag, and reading it
  there would read whatever the previous function left behind. TS2708's
  `typeof` TYPE position buys **zero** files and that is the honest half
  of the row: the position is wired (`var m: typeof A`,
  `type T = typeof A`, `var m: typeof A.P` where the base SEGMENT is what
  matters, and the namespace-nested form all report, while a namespace
  carrying a runtime `export var` is ACCEPTED), and it needs no `env`
  guard unlike the value path because the sweep reads only module- and
  namespace-level declaration types, never a function body — but
  `importStatementsInterfaces` still needs the OTHER channel the row
  named, an `import a = A` alias whose value-ness depends on a target the
  parser does not resolve.
  Batch EF is **+1** (TP 2601 / MISS in scope 113) and the conformance
  file is the smallest thing it found. The PARSER stored two different
  shapes identically — `{ foo() {} }`, where the name is the property
  KEY, and `{ foo: function foo() {} }`, where it IS a binding in the
  body — both as `("foo", FuncExpr { name: "foo" })`, and THREE consumers
  each guessed which one they had. The guess is not decidable from the
  data they had, which is why all three were wrong somewhere:
  `collect_expr_value_names` declared the name in the module-wide
  `declared_value_names` backstop, so `var v = { aaa() {} }` made a bare
  `aaa;` legal ANYWHERE in the file and let one method body see a SIBLING
  method's key — that, and not the recursion binding, is what hid
  `YieldExpression10_es6`'s TS2304; `check_funcexpr_with_context`
  surfaced the name for recursion, inventing a binding for a shorthand;
  and `emit` / `mangle` reconstructed the shorthand from `f.name == key`,
  which is equally true of a named function expression whose name matches
  its key. That last one is a live bug in the plainest path there is —
  `mtsc file.ts`, no optimization flag, where
  `{ fact: function fact(n) { … fact(n - 1) } }` prints 120 under Node on
  the source and throws `ReferenceError` on the output. It was broken
  TWICE, and the second break only appeared after fixing the first and
  re-measuring: with the discriminator corrected, `emit_function_expr`
  then dropped the name outright, because it drops any name the body
  references — a workaround that is CORRECT for a borrowed member key (a
  class method lowered to `C.prototype.m = function m() {}` must not
  shadow an outer `m`, the `toJSON` case its own comment names) and wrong
  for a real self-binding.
  The fix is one parse-time field, `TsFunc.name_is_member_key`, and its
  most useful property is that MoonBit requires every field of a record
  literal — so adding it made the census COMPILER-DRIVEN rather than a
  grep, naming all 32 construction sites and forcing each to be
  classified. This file records ten instances of a rule applied in some
  places and not others, every one found by reading; this is the first
  where the language enumerated the sites instead.
  The legal neighbour is what kills the cheap discriminator, and the
  probe for it was written BEFORE the fix:
  `{ foo: function foo() { return foo } }` is legal, has `f.name == key`,
  and must stay silent. Ten probes now agree with tsc — five that fire
  (the corpus shape, a sibling key, the module-wide leak, a getter key, a
  body reading its own key) and five that do not (a named function
  expression, one held in a property of the same spelling, a recursive
  one, a method reaching a real outer function, and `this.<key>`).
  `fixtures/mangle-safety/case62-named-funcexpr-self-binding` observes
  BOTH directions in one file, because a fix that merely stopped dropping
  names would pass the self-binding export and fail the other two.
  Two notes on the harnesses, both about this session rather than the
  rule. A formal mutation test was NOT run on that case, and what stands
  in its place is stronger for the emitter half: each half of the fix was
  shown necessary by measurement in sequence (no fix → throws via the
  shorthand collapse; discriminator only → throws via the name drop; both
  → 120). And checking the submodule out changes what `moon test` COSTS:
  the parser bench then chews the real 3.1 MB `checker.ts` where it
  previously printed "skip: typescript submodule files not found", so the
  suite stops being comparable to a count taken without it. The two
  `*_bench_wbtest.mbt` files are `it.bench` timing loops and assert
  nothing, so the assertion-bearing run is 3,002 where the full one is
  3,004 — the difference is exactly those two entries, not lost coverage.
  Batch EG is **+6** (TP 2601 -> 2607, MISS in scope 113 -> 108) plus one
  file retired from the scope file as STALE, and three of its four rules
  are the applied-in-some-places family again. The whole TS2488
  apparatus — `check_iterable_class_protocol` for a class instance,
  `check_forof_non_iterable` for a primitive / union / optional
  `@@iterator` — was wired into the `for-of` arm and nowhere else, so
  `yield*`, which delegates to an ITERABLE and carries the same
  obligation, had only a check needing a declared element type
  (`ctx.yield_type`) that a generator without a return annotation does
  not have. The shape that matters is `yield* foo` instead of
  `yield* foo()`: forgetting to CALL the generator, which needed `Func`
  in `is_non_iterable_primitive` and therefore reaches the two `for-of`
  consumers too (tsc reports both). `void` / `null` / `undefined` are
  TS2488 as well and are deliberately OUT, because our flow model
  narrows an `any`-typed binding to `Undefined` when its initializer is
  `undefined` — batch CY's TS2532 hazard, and an arm for it would report
  a type tsc calls `any`.
  TS18014 is the one worth reading, because the FIRST version measured
  +1 TP and **−1**. `private_brand_declared_on_receiver` asked whether
  the class HOLDING the reference declares the same `#name`, which is the
  one-level version of the question: a `#x` reference resolves OUTWARD
  through every enclosing class body and binds to the first that declares
  it, so the shadowing declaration can sit on a class BETWEEN the
  reference and the receiver — `A.#x` inside a `C` nested in a `B` that
  declares its own `#x`. The chain rides a new
  `<private-parent:CHILD:PARENT>` sentinel beside the
  `<private-decl:BRAND:base>` one the rule already reads, and
  `current_class_brand` not being reset by a function body is CORRECT
  there, since a private name resolves lexically through one. What the
  symmetric version got wrong is reading an owner MATCH as permission:
  returning "suppress" when the lexical owner is the receiver's own class
  short-circuits the staticness check downstream, and
  `privateNameStaticFieldAccess` / `privateNamesUnique-3` are exactly
  that — `static #foo` declared and `x.#foo` written on an instance
  resolves to precisely that declaration and is still an error. So the
  walk may only ever force a REPORT, never a suppression; the old
  heuristic stays in charge of everything else.
  TS1064's named half is the twelfth time a recorded abstention named its
  own fix in writing: `record_async_return_type_misuse`'s header says
  "the alias and the subclass are the SAME named-annotation node at parse
  time … a name declared in-file as a CLASS or INTERFACE cannot be an
  alias — and is filed rather than built". The boundary is not what the
  message text suggests — EXTENDING `Promise` buys an interface or class
  nothing, so `interface I {}` and `declare class D {}` report as readily
  as a `Promise` subclass, while a declaration-merged
  `interface Promise<T>` IS the global one and must stay silent, which is
  why the NAME is exempt by spelling (costing the `class Promise<T> {}`
  shadowing case as a MISS). A qualified annotation is
  `Named("X.MyPromise")` here, so the namespace prefix is reconstructed
  by recursing `module_.namespaces` with no resolver involvement at all.
  The decorator rules are batch CU's arity check's missing other half —
  "can this decorator resolve here" is also a question about TYPES — and
  every cell was probed. The runtime hands a member decorator the class
  INSTANCE type for an instance member and `typeof C` for a static one
  AND for a constructor parameter, so `target: Function` can never
  resolve on the first and always resolves on the other two; both ways it
  could be legal are excluded, since a class with heritage can BE a
  function (`class A extends Function { @dec m() {} }` is ACCEPTED — the
  guard is measurement, not caution) and a file redeclaring the NAME
  `Function` means something else by it. A constructor parameter's
  decorator is invoked as `(typeof C, undefined, index)`, so a second
  parameter that does not admit `undefined` cannot resolve — while a
  METHOD parameter's gets the method's name, making the identical
  signature legal there, and the verdict depends on `strictNullChecks`
  too, which is two flags rather than one fact. Parameter decorators had
  no `<sig:>` marker AT ALL, and `skip_param_decorators` skips the
  expression — batch EE's TS1308 blocker, with the same answer: a
  decorator's head must be spelled out, so reading `(called, dname)` off
  the tokens the skip already consumes is complete by construction. The
  owner (`ctor` / `static` / `instance`) rides a Parser field set around
  the ONE `parse_params()` call in `parse_class_body` and cleared inside
  `parse_param` for everything after the decorator scan, because a
  default value or a destructuring pattern can hold another parameter
  list whose parameters belong to that callable — clearing once there
  rather than at each nested parser is the point, the alternative being
  the save / clear / restore discipline `self.labels` needs at fifteen
  sites. Two measurement notes: a parameter decorator's runtime arity is
  exactly 3 (probed — 1, 2 and 4 all report) unlike a method decorator's
  2-or-3 latitude; and the "does this file redeclare `Function`" test is
  HOISTED out of the marker loop, since asking it per marker is
  O(decorators x declarations), the shape `verify-checker-scaling` exists
  to catch.
  TS2490 is filed rather than built, with a CHECKED blocker rather than
  an assumed one: `TsClassMethodDecl` has no annotation-presence field,
  so `next() { return "" }` (TS2490) and `next(): any { return "" }`
  (ACCEPTED) are the same node downstream — the absent-versus-`: any`
  blocker this file records for TS7031, TS7022, TS2729, TS2448 and
  TS2564 — and `parse_class_body` already holds `had_return_annotation`
  at exactly the `next` / `@@iterator` site, because batch DV's TS7022
  indirect rule keys on it there. The route is a Parser-level stack
  drained per class into a sentinel, the `self.optional_member_names`
  shape; not taken because a new parse-time channel for one file is the
  wrong trade at +6.
  Batch EH takes MISS in scope **under 100** — 108 -> 99, TP 2607 -> 2616,
  FP 0 — and its more useful half is the **five false positives** it
  fixed, because two of them were CANCELLING and the corpus scored the
  pair as correct. `infer_expr`'s `OptionalChain` arm unioned `undefined`
  into the result unconditionally, so `declare const c: { p: number };
  const n: number = c?.p` was reported (writing `?.` on a non-nullable
  receiver is redundant, not wrong); and the array-method table declared
  `filter` / `some` / `every` / `find`'s callback as returning `boolean`
  where `lib.es5.d.ts` says `unknown`, so `names.filter(x => x)` — the
  commonest spelling there is — was reported. `optionalChainingInArrow` is
  `names?.filter(x => x)`: the first bug added `| undefined` to the
  receiver, the member lookup failed, and the callback was never judged,
  so the file was a TN with BOTH bugs present and fixing either one alone
  turns it into an FP. That is the reason to fix a false positive even
  when the gate already reads zero. The other three: an ARRAY is
  assignable to a numeric index signature (`var v: { [n: number]: Bar } =
  arr` is ACCEPTED by tsc and reached `is_assignable_to`'s `_ => false`),
  `lookup_field` returns the FIRST declaration of an overloaded
  computed-key method so the new symbol-index arm reported a call against
  a later overload, and a private-name diagnostic printed
  `__private_brand__0__prop` — the third time, so `member_display_name` is
  now one function the whole property-access family routes through.
  Four of the nine rules are the applied-in-some-places family. TS2416's
  method half: the check compared a data-PROPERTY's type and a member's
  PRESENCE and judged a method's type by nothing, and
  `member_override_incompatible` could not answer it — a `Func` on both
  sides falls through its final `false` — so the comparison is returns
  COVARIANTLY, parameters BIVARIANTLY, which is the cell reasoning gets
  wrong (`m(x: string)` against `m(x: any)` is LEGAL). A property write
  spelled with BRACKETS reached nothing where the dotted spelling has
  been checked for a long time, at BOTH its statement and expression arms
  — the parser fact this file records for TS2565 and `globalThis`. TS2420
  never asked whether the index signature a class DOES declare is
  compatible with the interface's, and the coverage rule is asymmetric:
  a STRING indexer satisfies a numeric one and a numeric one does not
  satisfy a string one. And `collect_declared_fields` had arms for five
  projectable utilities and none for `Record`, the one whose fields come
  from its KEY argument rather than from a source shape.
  Two blockers dissolved, and both were written down. TS2490 was FILED one
  batch earlier with its exact blocker and route, and building the route —
  a `<unannotated-return:NAME>` per-class sentinel in the shape
  `optional_member_names` already uses — bought TS2490 and TS2416's
  unannotated case together. The marker asserts TWO facts and the second
  is the one that matters: the body was a real `{ … }` block, which is the
  only way to read a `None` body as `void`, since
  `TsClassMethodDecl.body` is `None` for an EMPTY body as well as for a
  bodiless overload signature. The other blocker was a PROXY rather than a
  channel: the missing-required check asked
  `is_assignable_to(undefined, ty)` for "is this member optional", and the
  `?` is not in the AST — the parser wraps `a?: T` into `T | undefined`,
  ALWAYS producing a union, so the union IS the encoding and the proxy
  answered yes for five shapes the `?` can never produce. `a: any`,
  `a: unknown`, `a: string | undefined`, `a: undefined` and `a: void` are
  all required members tsc reports missing and only `a?: any` is not; the
  union case stays suppressed because there the two spellings really are
  the same node.
  Three cells were probed rather than reasoned and all three read
  backwards. A union-typed VALUE's call requires the LARGEST minimum arity
  of its members (tsc's `combineUnionParameters`) and the code overwrote
  that with the SMALLEST whenever no member's parameter domain dominated —
  which is the moment the members differ in parameter COUNT, since
  `callable_params_narrower_than` returns `None` on a length mismatch.
  `Record<E, any>` with `enum E { A }` requires the key `"0"`, the
  member's VALUE, so `{ 0: 1 }` satisfies it and `{ A: 1 }` is an EXCESS
  property — and auto-numbering has to be REPRODUCED, because the AST
  keeps a folded value only for members that wrote one. And TS2698's
  intersection arm takes `T & undefined` while every UNION keeping a
  non-nullish part is legal; the bare `Undefined` / `Null` spellings tsc
  also reports are out, because our flow model narrows an `any`-typed
  binding to `Undefined` and an intersection with a nullish part can only
  ever be written.
  Four items were measured and NOT taken, each with the blocker rather
  than a verdict. `arrayLiterals`'s TS2353 needs the VALUE type of an
  object-type index signature, which `try_parse_object_type_with_members`
  discards BY DESIGN — its own comment says index signatures are "kept
  (keyed by the key type, with an `Any` value)". `wideningTuples7`'s
  TS7010 needs the body of a function EXPRESSION at a `var` initializer,
  which is not walked at all while the same shape reports for a function
  DECLARATION. `enumShadowedInfinityNaN`'s TS18033 needs the enum's own
  BLOCK scope, and an enum is hoisted into `module_.enums` with no record
  of the block it came from. And `computedPropertyNames30` was RE-PROBED
  rather than re-argued: the distinction this file called "modelling a
  distinction ONE file draws" is reproducible — `super()` in an
  object-literal computed key is TS2466 when an ARROW or a function
  expression lies between it and the constructor and ACCEPTED directly in
  the constructor, across five hand-written cells — but deciding it needs
  a "is there a function boundary between here and the class body" fact,
  which is a new Parser field with the save / clear / restore discipline
  `self.labels` needs at fifteen sites. A recorded abstention whose reason
  probing CONFIRMS is worth as much as one it refutes, and this is the
  second.
  Batch EI is **99 -> 80** (+19 files, TP 2616 -> 2635, FP 0), the largest
  single batch in this series, and the reason it is large is that thirteen
  of its nineteen rules needed no type information at all: a `const enum`
  initializer that EVALUATES to `Infinity` or `NaN` (TS2477 / TS2478 —
  gated on `in_const_enum`, which is the whole rule, since a plain enum
  takes the identical initializers in silence), an object-rest element
  whose target is a binding pattern, `yield` in a generator's own
  parameter initializer, an optional binding-pattern parameter in an
  IMPLEMENTATION, `export { globalThis }`, a decorated or modified `this`
  parameter and a `this` parameter that is not first, `super` with type
  arguments, an assignment to a class / enum / function declaration, a
  private name as an indexed-access key, `infer` outside an extends
  clause, and one `infer` name declared twice with different constraints.
  Four are the applied-in-some-places family, and one of the four is the
  purest instance yet: `<import-eq-root>` had the DOT test inside its
  guard, so TS2503 was written for `import X = A.B.C` and applied to one
  of the two spellings — a single-segment `import f = NonExistent` never
  reached the recorder, and the root of a one-segment reference is the
  whole reference. The other three: a private / protected member reached
  by DESTRUCTURING had no check at all where `k.priv` has been reported
  for years (the verdict is now one function both callers share, rather
  than a second copy of the rule — the family written into its own fix);
  `reaches_alias` treated a mapped type's SOURCE as a structural barrier
  when computing the key set is exactly what needs the alias resolved
  (`type Recurse = { [K in keyof Recurse]: Recurse[K] }`), while the VALUE
  position really is a barrier and must keep having no arm, which is what
  keeps `type A = { x: A }` and the generic `Circular<T>` / `Transform<T>`
  in the same corpus file silent; and TS2411's index-value arm required a
  CLASS on both sides where the corpus file augments an INTERFACE.
  **The optionality PROXY turned out to be live at two more sites**, and
  that is the recall finding of the batch. Batch EH replaced
  `is_assignable_to(undefined, ty)` with the union test in
  `check_expr_against`; `object_fields_assignable` and
  `struct_assignable_named_rec` were still asking `type_accepts_undefined`,
  which answers yes for `any` / `unknown` / `undefined` / `void` — none of
  which the `?` can produce. The second of those is the live bug rather
  than a MISS, because that function only ever PROVES assignability, so a
  permissive answer SUPPRESSES the diagnostic: `class Bar { x }`, whose
  unannotated field becomes `any`, accepted every source, which is the
  commonest spelling of a required member there is. The UNION case stays
  tolerated at all three sites, and that is not a shortcut — there
  `x?: T` and `x: T | undefined` really are the same node.
  TS1338 is the batch's clearest legal-neighbour lesson and **the corpus
  caught both halves of it**. The first version cleared the permission
  when it descended into a nested conditional's check / then / else
  positions, and the message means "inside SOME conditional's extends
  clause", not this one's: `type X11<T> = T extends ((infer U) extends
  number ? 1 : 0) ? 1 : 0` is ACCEPTED — `inferTypesWithExtends1` says so
  in its own comment — while the identical inner conditional as a whole
  alias BODY is TS1338 three times, and not on its extends position. The
  first TS2838 was wrong the same way: an unconstrained `infer U` beside a
  constrained one is ACCEPTED in either order, "same behavior as
  class/interface" in that file's words, because a missing constraint is
  INHERITED rather than contradicting — so only a WRITTEN bound
  participates.
  TS2855 / TS2340 is where reasoning gets a cell backwards in the way this
  file keeps recording. `super.x` reaching a base DATA FIELD is an error
  WHATEVER its visibility — the field is an own property of each instance
  and `super` looks on the prototype — yet the corpus file
  (`privateInstanceMemberAccessibility`) is written as if it were an
  accessibility rule, and the older message it carries says "only public
  and protected METHODS". Probed: `private`, `protected` and `public` base
  fields all report; the local compiler gives TS2340 at `target: es5` and
  TS2855 from es2015 up, which is why one rule carries both numbers. Three
  neighbours are accepted and each needed its own exclusion — a METHOD and
  an ACCESSOR (both on the prototype, so a name also present in `methods`
  abstains, which also covers batch CV's ambient accessors upserted into
  BOTH lists), a PARAMETER PROPERTY, and a STATIC base member of the same
  name, which cost two false positives
  (`thisAndSuperInStaticMembers1`/`2`): in a static member `super` is the
  base CONSTRUCTOR, where a `static` field of that name really does live,
  and static and instance field initializers share one `CheckCtx` path so
  the context cannot be read there at all.
  The false positive the corpus structurally cannot see is the fourth in
  four batches found by probing a legal neighbour, and it was a rule that
  had gone STALE against the language: the get/set pair check required the
  getter's type to be assignable to the setter's parameter type, and
  **TypeScript 4.3 made those types allowed to DIVERGE**.
  `get p(): string { return "" }` beside `set p(x: number)` is ACCEPTED,
  and so is every class-typed pair; the error, if any, lands where the
  value is READ. Only an UNANNOTATED getter is an error, and there the
  getter's type comes contextually FROM the setter, so what tsc reports is
  the `return` inside the body — the same verdict either way. The
  annotation-presence fact is not in `TsClassMethodDecl` (the
  absent-versus-`: any` blocker recorded here for TS7031, TS7022, TS2729,
  TS2448 and TS2564), so the pair is judged only for a member the parser
  put in `unannotated_return_members` — batch EH's `<unannotated-return:>`
  channel, built for TS2490 and now serving a second rule. One more cell
  came with it, and it is a case of OUR parser being more precise than
  tsc: a computed key pairs the two accessors only when it is a late-bound
  name of LITERAL type, so `[G.B]` and `["get1"]` pair while `[1 << 6]`
  does not — its type is `number`, not the literal `64` — and our parser
  folds the shift to the member name `64`. Ten cells now agree with tsc.
  Four items were measured and NOT taken. The one worth reading is TS2304
  for an undeclared `infer X extends Bound`, which was written, wired and
  **REVERTED after instrumenting rather than re-reading**: the type parser
  REDUCES a conditional whose extends relation it can decide, so
  `type Test<T> = T extends infer A extends B ? number : string` arrives
  at the checker as the bare `Number` and neither the marker nor its bound
  survives. Its scaffolding went with it — a per-position binder set
  threaded down the walk, which is the one thing that would make the
  general `unresolved_type_references` version usable, and dead code that
  reads like live code is a defect. The other three: TS2797 needs a link
  from a class declared inside a function to that function's PARAMETER
  types and type-parameter bounds, which nothing provides; TS2339 for
  `Symbol.<unknown member>` needs a file-level fact the member parser
  cannot have (whether the file augments `interface SymbolConstructor`,
  which `symbolProperty61` legally does); and TS18046 through an ALIASED
  guard needs assignment invalidation of the alias.
  Batch EJ is **80 -> 76** and its most useful finding is that a
  PARAMETER was a module-level value name. `declared_value_names` is the
  TS2304 hoisting backstop, and it declared every parameter of every
  function, function expression and arrow anywhere in the file — so
  `function f(pname) { }` beside a bare `pname;` at top level was silent,
  and so was the arrow spelling. Removing it from the three module-wide
  collection sites (and keeping `check_function_body`'s seeding of ONE
  function's own parameters, where the fact belongs) is +1 file and **2
  false positives**, and those false positives NAMED the real bug rather
  than arguing for the backstop: `Parser::parse_param` sets `p.name` to
  `binding_first_name(binding)` — the FIRST name in the pattern — so
  `({ a, ...rest }) => …` bound `a` and left `rest` unbound and
  `([p, ...q]) => …` bound `p` and left `q`. `check_function_body` has
  walked the pattern with `bind_pattern` for a function DECLARATION for a
  long time; `check_arrow_with_context` and `check_funcexpr_with_context`
  had only the `p.name` line, so a pattern parameter behaved differently
  depending on which of the three callable spellings was used.
  `bind_callable_param` is one helper called from all three — nineteenth
  instance of a rule applied in some places and not others.
  Two of the three rules read WRONG from their message text, which is this
  file's recurring lesson. TS2322's constructor-type accessibility
  ("cannot assign a 'protected' constructor type to a 'public' constructor
  type") is a one-DIRECTIONAL rank comparison: public 0 / protected 1 /
  private 2, error iff src > tgt, so `let b = Prot; b = Pub` and
  `let c = Priv; c = Prot` are both legal, a SUBCLASS is no exemption, and
  two classes at the SAME rank get TS2419 instead — structural
  construct-signature incompatibility — so equal ranks stay out. And
  TS2352 between two FUNCTION types needs three probed cells that reasoning
  gets backwards: a `void` return OVERLAPS anything
  (`(() => {}) as () => string` is ACCEPTED), while a PARAMETER mismatch, a
  differing ARITY and an `any` parameter on the target side are all TS2352
  in tsc — where the rule takes the MISS rather than model a bivariant
  comparability relation. The arrow in `as` position is contextually typed
  by the asserted type's PARAMETERS and not its return; taking the return
  too would make every such cast trivially fine.
  The constructor rule also cost two drafts for reasons already written
  down elsewhere in this file. It was SILENT on its own corpus file while
  the `var a: typeof Pub = Prot` spelling reported, because a top-level
  `a = Prot;` is `Assign` only when `parse_expr_until_top_level` stops
  before the `=` and is `Expr(AssignExpr(...))` otherwise — the same split
  TS2565 and the `globalThis` rule record for `PropAssign`. And the
  un-annotated holder path needs a PARSER marker, because `TsStmt::Let`
  carries `Any` for both an absent annotation and an explicit `: any` and
  only the first takes its type from the initializer: `let d: any = Pub;
  d = Priv` is LEGAL, probed, and the corpus cannot see that false
  positive at all. Twentieth instance of the absent-versus-`: any`
  blocker, after TS7031, TS7022, TS2729, TS2448, TS2564 and TS2490.
  The namespace rule is the one that needed no correction: `namespace N {
  export var p = 6 }` beside `N.p = false` was silent, which is the shape
  declaration merging produces and the one an expando author hits. Probed
  cell by cell — a `var` and a `let` member report, a namespace merged with
  a function or a class reports as readily as a bare one, and `export var
  e;` (implicit `any`) stays silent; an undeclared member is TS2339 and an
  `export const` is TS2540, different codes this rule does not claim.
  Exportedness is not consulted because the AST does not record it and it
  costs nothing: a member declared WITHOUT `export` is not reachable as
  `N.x` at all.
  Batch EK is three more recorded abstentions, and the first is the FIFTH
  in this series whose stated reason was false — the second where the thing
  that dissolves it sits in the same struct. TS2564 skipped an
  `abstract class` wholesale because "our parser drops the `abstract`
  modifier on properties, so we can't distinguish a truly-unassigned
  concrete field from an abstract one"; `TsClassDecl.abstract_members`
  exists and its own doc comment says it holds `abstract x: number` as well
  as `abstract foo(): void`. Skipping only the named fields needed nothing
  else, because an abstract class's exemptions are EXACTLY a concrete
  class's — probed one cell at a time, `abstract y`, `z = 1`, `w!`, `v?`, a
  constructor-assigned field, a `static` field and every member of a
  `declare abstract class` are all silent, and only the plain `x: number`
  reports.
  The second is `interface A extends C`: an interface that extends a class
  inherits its members, and a `private` one stays private to the declaring
  CLASS, so `a.p` is TS2341 and `a.q` TS2445 — both silent while the direct
  `c.p` spelling has reported for years. The verdict function was already
  keyed on the declaring class (batch BZ split it out so the destructuring
  spelling could share it), so the only missing piece was resolving the
  receiver's interface name to that class; the walk is depth-bounded rather
  than cycle-tracked, since an interface heritage cycle is itself an error
  and stopping short costs a MISS.
  The third is a CHANNEL rather than a rule: `export = A` inside
  `declare module "M"` records the same `<export-eq>` marker the top-level
  spelling does, and the consumer reads only `module_.grammar_misuses` — a
  `declare module "spec"` body lands in `module_augmentations`, which,
  unlike `namespaces`, the layered recursion does not descend into, so
  every marker its body produced was dropped. It is scoped to that ONE
  marker rather than surfacing the whole channel, because the rest are
  decided against a module-wide name set or a compiler-option header an
  augmentation body does not have, and a blanket surface is how a marker
  becomes a diagnostic nobody checked — which TS4111's flag marker and
  `<module-commonjs>` each did once.
  The batch's operational finding cost two wasted runs and generalizes:
  `verify-examples` and `verify-generated-fixtures` invoke
  `moon run src/cmd/mtsc` (spelled `src/cmd/ts2mbt` when this was
  written), which RECOMPILES from source, so running them
  while the tree is being edited measures whatever half-finished state the
  files are in. The first failure of this batch was exactly that, and the
  traced re-run proved it by failing on a `[4014]` type error introduced
  two minutes earlier. The serial order is check, test, build, oracle, then
  the recompiling harnesses — on a tree that is not moving.
  Batch EL is **+7** (MISS in scope 73 -> 66) and its first move was to
  remove a SUPPRESSION whose stated reason was false about TypeScript.
  `is_widening_direction_mismatch` dropped every `expected "X" (string) but
  got string` mismatch, saying "TS accepts these (the literal initializer
  collapses to the wider type at the use site without narrowing)" —
  TypeScript accepts no such thing, `string` is never assignable to
  `"Hello"`. The true, weaker statement is that OUR inference sometimes
  widens where tsc keeps a literal type, so a report there can be about our
  gap rather than the program. Removing the arm measured +1 TP and **+1
  FP**, and the false positive is the finding: `lookup_method_sig` reads
  `lookup_field`, which surfaces only the FIRST declaration of a name, so
  the argument check judged every call to an OVERLOADED method against
  overload #1 — `c.foo('bye')` against `foo(x: 'hi'); foo(x: 'bye');
  foo(x: string)` in `typesWithSpecializedCallSignatures`, a TS7-ACCEPTED
  file — while `infer_expr` has had `resolve_method_overload` for the RETURN
  type all along. The candidate collection was extracted so the argument
  path asks the same question, and it ABSTAINS for an overload set, since
  nothing at that site can reconstruct which signature the arguments were
  written for; a single-signature method is still judged. The numeric and
  boolean arms of the suppression STAY, and that is the reusable half:
  nothing has measured them, and removing an arm whose population nobody
  has opened is exactly how the false positive above got written. Two more
  tests were found asserting a gap rather than a behaviour, the twelfth and
  thirteenth here — `const c = "b"; let y: "a" = c;` asserted 0 and is
  TS2322, and `declare var Symbol: any;` sat in a whole-file "silent" list
  while being itself TS2403 against the lib declaration.
  Three of the other six rules are the applied-in-some-places family.
  TS2403 against the lib declaration fired for `var Symbol: { iterator:
  symbol }` and not for `declare var Symbol: …`, because the module parser
  routes `declare var` through `parse_declare_values` into `module_.values`
  and pushes nothing onto `top_level_stmts` — one rule, two declaration
  channels, and the ambient one is what every `.d.ts` writes. A function
  value against a UNION of call signatures had no arm at all, though
  TypeScript states the rule and `functionExpressionContextualTyping2`
  quotes it in its own header (identical parameters IGNORING RETURN TYPES
  give a contextual signature with the UNION of the returns); parameter
  lists that DIFFER mean no contextual signature exists, so the arrow's
  parameters are implicitly `any` and that case abstains rather than picking
  a member. And `is_definitely_not_arithmetic` abstained on every union with
  a reason in its own comment — a numeric-literal union like `0 | 1 | 2` IS
  arithmetic — which is true of those and not of `number | string`: tsc
  requires the WHOLE operand to be numeric, so one definitely-non-numeric
  member decides it, while every member must be CONCRETE (a `Named` member
  could be a numeric enum, and an `any` member collapses the union to `any`,
  which tsc accepts) and a union of numerics abstains because `number |
  bigint` is TS2365, a code this rule does not claim.
  The remaining three each turn on one probed cell. Expando properties on a
  function value are a TypeScript affordance requiring `const` — a function
  DECLARATION and `const f = () => …` get them, `var f = function () {}` and
  `let f = () => …` do not, and `typeFromPropertyAssignment29` says so in
  its own comment — and the annotation is NOT what saves it (`declare var f:
  (n: number) => number; f.p = 1` is TS2339) while an explicit `: any` IS,
  so the fact rides a parse-time marker: twenty-first instance of the
  absent-versus-`: any` blocker. TS2556 is about a spread argument having a
  TUPLE type and a union not being one, which is the cell reasoning gets
  wrong — `[number, number] | [number, string]` reports even though every
  member has the same arity, while a union of IDENTICAL tuples collapses to
  one tuple and is accepted, so the members are deduplicated before the
  count is decided. And TS2749 for a value name in a type-ARGUMENT position
  is the one place the name resolution `unresolved_type_references` cannot do
  IS decidable, for a structural reason: a type argument in an EXPRESSION has
  no binders of its own — the recorded blocker is that `check_type` loses a
  type's own `<U>` / `infer` / mapped key — and the call site's environment is
  the scope the name resolves in, which is what makes the function-local
  `var b` in `a<b, b>(c + 1)` reachable.
  Two notes that are not rules. The `globalThis` index-key rule tests the
  KEY's CHARACTERS rather than a name set, deliberately: an ambient external
  module's name includes its quotes so it can never be a global, and a single
  file cannot see the globals another script file declares, so a name-set
  test would false-positive on any real multi-file program. And
  `typeGuardsDefeat` is FILED with the rule it is not: probing says
  TypeScript DOES preserve a parameter's narrowing inside a closure created
  in the narrowed region (five cells, all accepted), so "reset narrowing on
  entering a nested function" is wrong — what defeats it there is the later
  `x = "hello"` the closure can observe, so the fact needed is "this binding
  is assigned somewhere other than its initializer".
  The batch's operational finding is the third stale-measurement instance in
  this file and the first where the instrument was a hand-run binary:
  **`moon build --target native` builds DEBUG.** The justfile's
  `verify-checker-soundness` runs exactly that and then the oracle, which
  works only because the oracle picks the NEWER of the two binaries. Probing
  `_build/native/release/.../mtsc.exe` by hand (`tscheck.exe` when this was
  written; it is `mtsc check` now) after a plain `moon build`
  measures whatever the last `--release` build contained — and it cost most
  of an hour here: a patch was "verified absent" by re-running that binary,
  the conclusion "the report must come from another site" was drawn from it,
  and twenty-one call sites were instrumented with unique markers before
  `ls -la` showed the binary was ten minutes older than the source. The
  build command for a hand probe is `moon build --target native --release`.
  Batch EM is **+3** (MISS in scope 66 -> 63) and is another recorded
  abstention whose stated reason was measured instead of re-argued. An
  object-type index signature's VALUE type was consumed and recorded as
  `Any`, the comment at the site naming the hazard: value-assignability
  checks driven off an anonymous index signature would false-positive
  through our object-literal getter modelling (`get x()` rendered as
  `() => T`). Keeping the value is **+2 files at FP 0**, and the two are
  exactly the ones this file had named as blocked on it —
  `arrayLiterals`'s TS2353 and
  `optionalPropertyAssignableToStringIndexSignature`. An INTERFACE's index
  signatures always kept their values, so the change also stops the two
  spellings of one declaration from disagreeing.
  Three things had been leaning on that `Any`, and NONE of them was the
  getter hazard the comment named. The first is a cell reasoning gets
  wrong: an OPTIONAL source property satisfies a STRING index signature of
  its base type (`{ k1?: string }` into `{ [k: string]: string }`) while
  `{ k1: string | undefined }` is TS2322, and those are the same node here
  — so the union is tolerated and the explicit spelling is the MISS that
  buys it, the same trade `is_object_assignable_inner`'s own
  `target_field_optional` comment records twenty lines below. A NUMBER
  index signature gets no such exemption, `{ 1?: string }` against
  `{ [k: number]: string }` being real TS2322, so it is keyed on the
  target's key KIND rather than applied to both. The second is a
  pre-existing hole: `Struct(n, …)` and `Named(n)` had NO arm in
  `is_assignable_to_inner` even though `Struct` is the structural
  expansion of `Named` — the resolver produces one where it could expand
  an interface reference and the other where it could not, so the two
  spellings of one type meet whenever a comparison crosses that boundary
  and fell to the `_ => false` catch-all. `Bar[]` against
  `{ [n: number]: Bar }` broke while `Array<Bar>` and `string[]` were
  fine, and that asymmetry is what exposed it — found by INSTRUMENTING
  rather than reading, after two rounds of tracing arm order got nowhere
  and one `println` printed `elem=Struct("Bar", …)` against
  `val=Named("Bar")` on its first run. The third is `delete o["b"]` on
  `{ [k: string]: string }`, LEGAL and silent for the wrong reason: a
  member reached ONLY through an index signature is not a declared
  property, which is now stated rather than implied by a widened type.
  **Both false positives were caught by UNIT TESTS and not by the
  corpus**, which is batch CS's lesson once more:
  `optionalPropertyAssignableToStringIndexSignature` has real errors on
  three lines, so the two `// ok` lines we were also reporting left it
  scored a TP either way. The batch's other rule is TS2559, the weak-type
  check — a target whose every member is optional accepts any shape
  structurally, which is what makes an options-object typo silent, so
  TypeScript adds the separate requirement that the source share one
  property name with it; both sides go through `cast_shape_fields`, which
  declines for an index signature, a generic interface, a class and
  anything it cannot enumerate, since each of those is a shape where a
  property might be present without being listed.
  Batch EN is **+5** (MISS in scope 63 -> 58) and its most useful outputs
  are two changes MEASUREMENT retired. The first is the SECOND probe of
  one abstention and the second time the answer was "leave it":
  `enumerable_object_shape` declines `Object` type literals, and the note
  that used to sit there cited `docs/checker-priority.md`, the strategy
  document this file records as RETIRED — so the stated reason looked like
  a claim whose date had passed, the lead this series has cashed five
  times. Enumerating them (declining only on an index-signature key) buys
  **ZERO** corpus files for **THREE** false positives, all three
  discriminated unions whose discriminant our narrowing cannot decide: a
  template-literal tag (`` `${AnimalType.cat}` `` against
  `AnimalType.cat`), an `.err === undefined` discriminant against a
  `` `${string} is wrong!` `` sibling, and `{ test: string } | {}`. A
  NAMED interface or class union is enumerated and an inline object union
  stays silent, so the abstention is now CONFIRMED with a number where the
  old note had an argument. The second is the intersection /
  index-signature fallback: `is_assignable_to_inner` merges `{a} & {b}`
  and then, when the merged shape fails, falls back to "some component
  alone satisfies the target" — genuinely unsound against an indexer,
  since `{ a: string } & { b: number }` is TS2322 against
  `{ [k: string]: string }` while its `{ a: string }` component is fine.
  Dropping the fallback changes NOTHING, and the proof is a pair:
  `{ b: number } & { a: string }` against that target is still silent
  while the identical single-object source `{ a: string, b: number }`
  reports, so the arm is never reached for an intersection-typed VALUE at
  all and something above it abstains first. Reverted with the
  measurement at the site, because a fix that provably changes nothing is
  dead code that reads like live code.
  Of the rules that did ship, two are the applied-in-some-places family
  and one is a result FILTER rather than a missing site. `narrow_keep` /
  `narrow_remove` call `union_components` with no resolver, so a
  `type M = A | B` receiver reached the `"a" in m` guard as ONE opaque
  variant, `lookup_field` answered for the whole alias, and the guarded
  access was reported — while the sibling `narrow_by_discriminant`
  unwraps for exactly this reason and says so in its own comment. It is
  corpus-NEUTRAL at FP 0, which is the point: a narrowing improvement the
  conformance corpus cannot score, and the change that proves the
  rejected enumeration above was worth zero rather than blocked on this.
  `check_computed_key_type` has judged a `[Symbol.<non-well-known>]` key
  for a runtime class body and an object literal for as long as it
  existed, and `parse_declare_class_member_name` brace-matches past the
  key and keeps no expression — so the name rides a marker, the same
  argument batch EE's TS1308 makes for reading an `await` out of a
  skipped decorator, with the three gates COPIED from that function
  rather than re-derived.
  The filter is `inferred_primitive_field_type`, the fallback every
  unannotated-field read goes through: it infers the field's type from
  its initializer and admitted only
  `number` / `string` / `boolean` / `bigint`, so `class C { c = new C() }`
  left `c` as `Any` while the ANNOTATED spelling reported. Widening it
  measured NOTHING, and the second half is the finding — `field_init` is
  indexed per DECLARING class, so `class D extends C` recovered `d` and
  not the INHERITED `c`, leaving the VALUE side `Any`, and an `Any` value
  satisfies any target. The READ side had been working from the filter
  alone (`this.c.nope` reports), which is what separated the two halves:
  the filter was necessary and not sufficient, and only measuring the
  ASSIGNMENT showed which.
  Two more rules and one retired plan. TS2763 / TS2764 / TS2766 is an
  iterator whose `next()` declares a required parameter the position
  cannot supply: a `for-of`, a `for await`, an array spread and a
  destructuring pattern all call `next()` with NO argument and so send
  `undefined`, while `yield*` forwards whatever the CONTAINING generator
  is sent — which needed a `yield_next_type` beside the `yield_type`
  extracted from the same annotation ten lines away. The generic
  `Spread(v) | Await(v)` arm is where BOTH spread spellings arrive, an
  array-literal element and a call argument, so the rule lands at every
  spread position from one place; `for await` turned out to be a separate
  arm carrying NONE of the TS2488 apparatus either, and that gap is filed
  rather than folded in unmeasured. Three cells decide its shape and all
  were probed: `Generator<number, void>` — two type arguments, `TNext`
  left at its `unknown` default — is ACCEPTED, `Iterator<Y, R, N>` is
  TS2488 instead, and the identical file with `strictNullChecks` off is
  accepted too. TS2430 for a bare UNCONSTRAINED type parameter
  redeclaring a base member is the same shape as the TS2322 rule
  `type_param_bounds` already carries, and its boundary is narrower than
  it reads — `foo: T` against `{ [k: string]: any }`, `string`,
  `{ a: number }`, `{}`, `object` and `number | undefined` all report,
  while a CONSTRAINED `T`, an `any` or `unknown` base member and a
  composite `T[]` are all ACCEPTED, and `interface Base<U> { foo: U }`
  beside `interface E1<T> extends Base<T> { foo: T }` is legal for free
  because substitution makes the base type the bare `T` too. The retired
  plan is batch DX's `callee_non_generic` gate: `symbolProperty21`'s
  callee IS generic, so the filed fix was to test the WRITTEN target
  rather than `resolver.unwrap(target)`, and probing says the
  excess-property check at a call argument ALREADY fires for a named
  interface target with a generic callee. The computed key was the whole
  blocker — a `[Symbol.<well-known>]` object-literal key stayed
  `@@computed:N` while the type parser had encoded the interface side as
  `@@unscopables` all along, which is why the MISSING-required direction
  already reported and the excess direction did not.
  The operational note is batch EL's one level up: a killed `moon build`
  leaves its queued siblings waiting on `_build/.moon-lock`, so three
  `moon check` runs stacked behind one stale build and every log read
  empty for minutes. One script per measurement — check, build, oracle —
  and `ps -o etime` is what tells a queue from a hang.
  Batch EO moves the conformance numbers by ZERO and is the most
  valuable checker change in this run, because it is measured on a real
  package. **`mtsc` does not type-check zod**: the shipping flags produce
  **272 diagnostics** on `zod@4.4.3`, and tsc accepts zod, so every one is
  a false positive — `FP 0` over 4,484 conformance files never meant FP 0
  on real code, and the corpus does not contain the shapes. Zod RUNS fine
  through the whole pipeline (bundle + treeshake + fold + mangle +
  property mangling, 0.5 s, 279 KB, correct object / union / array
  schemas, `.min()`, `safeParse`, issue codes and `.email()` under Node),
  so the split is exactly: the optimizer is sound on it and the CHECKER
  rejects it.
  **85 of the 272 — 31% — were one missing shadowing test.** zod's
  `v4/core/util.ts` declares `export abstract class Class` and ALSO has
  helpers taking a `Class:` PARAMETER, so every `new Class({…})` inside
  them named the parameter while `check_abstract_instantiation` resolved
  it against `ctx.resolver.classes`. That is the scope-narrowing family
  this file records for `as_const_inline`, `const_enum_inline`,
  `predicate_inline`, `switch_fold` and `type_fold` — five transform
  passes, each fixed in turn — arriving in the checker, where the
  question had never been asked. The fact was available and used **four
  lines below one of the two call sites**: the TS2350 `Symbol` / `BigInt`
  rule already reads `env.lookup(class_name) is None` for the same
  reason, which makes this the applied-in-some-places family as well.
  Measured: zod 272 -> 187, the abstract-class family to 0, and the
  oracle IDENTICAL on both binaries (TP 2657 / MISS in scope 58 / FP 0 /
  PFLEGAL 0 / TN 1750) — the 85 cost no true positive.
  The other 187 rank the next work and none is a single missing test: 40
  are a `switch` over an indexed access into a union
  (`$ZodTypeDef["type"]`), 28 are a derived interface narrowing a member
  whose type is a named interface extending the base's GENERIC
  instantiation (`$ZodCheckRegexInternals extends
  $ZodCheckInternals<string>`), which our structural assignability cannot
  follow through a generic base, and the rest are assignability,
  strict-null and member-existence modelling gaps. The operational
  finding is the missing GATE: every harness here either compiles
  fixtures we wrote or scores a corpus whose FP budget is already zero,
  so 272 false positives on a package sitting in `_build/type-aware/`
  were invisible — and zod is cloned there already, dropped from that
  corpus for an unrelated reason (it answers the type-aware question with
  a permanent zero). A real-package FP gate needs no new download, only a
  checked run over the targets the corpus checks out, with the count
  declared per package the way `scripts/bridge_struct_enum_fields.txt`
  declares its budgets so growth fails and a drop follows the budget
  down.
  Batches EP-ET take **MISS in scope 58 -> 50** (TP 2657 -> 2665, FP 0)
  and their more useful half is **four false positives on legal code the
  conformance gate structurally cannot see**, every one found by probing a
  legal neighbour rather than by the corpus.
  Two were the applied-in-some-places family around one fact: a leading
  `this` parameter types the RECEIVER and occupies no argument position.
  FOUR places in this repo already knew that and said so in their own
  comments — the two ambient signature parsers drop it, the function-TYPE
  parser never records it, and the `module_.imports` ingest skips it by
  name — while `callable_func_type_from_params` (interface and
  object-type members) and `method_callable_param_types` (class methods)
  were the two sites without the rule. So `interface I { p(this: I, n:
  number): void }` with `i.p(1)`, and `class K { m(this: K, n: number)
  {} }` with `k.m(1)`, reported "expected 2 argument(s), got 1" and
  "arg[0] expected K but got number" on files tsc ACCEPTS outright.
  Fixing it cost one TP, and that is batch CS's lesson with the sign
  flipped: `looseThisTypeInFunctions` was flagged ONLY by the bogus arity
  report while its real errors are three TS2339s on `this.n.length`, so
  -1 TP is not evidence a fix is wrong.
  The other two are the SAME first-wins bug in two loops ten lines apart.
  `parse_module` merges block-level type ALIASES into the module-wide
  pool — its own comment says why, "the checker needs them to resolve
  Named(T) references inside those bodies" — and did the same for
  INTERFACES nowhere, though `parse_stmt` collects both from adjacent
  arms. That asymmetry is what made a block-local `interface` invisible
  to the resolver (`q.nope` on one silent while the top-level spelling
  reports). But the merge must NOT pick a winner among SEVERAL
  block-local declarations of one name, and both halves did: the alias
  half's bug was pre-existing and reachable from ordinary code — two
  functions each declaring a local `type W` made the first one's shape
  answer for the second, THREE false positives on a file tsc accepts —
  and the interface half's first draft reproduced it on `localTypes4`,
  whose empty `interface T { }` in one function outvoted
  `interface T { x: number }` in another. The gate scored that as a TRUE
  POSITIVE, because the file errors for unrelated reasons. A name
  declared more than once across block scopes is left unregistered now:
  abstaining costs a MISS, guessing costs wrong member answers.
  Of the rules, three needed a fact the TYPE cannot carry and two of
  those are the same shape as the `this` parameter above — a leading
  `this` parameter is dropped from the callable type, so TS2684 needs a
  marker to know one was DECLARED and whether it is `void`. Every cell
  was probed and two read the other way round from the message text: a
  PLAIN call supplies `this: void`, so `{ (this: void, b?: number):
  void }` called plainly is ACCEPTED while `{ (this: number, …) }` is
  TS2684, and for a UNION one non-void member is enough (tsc's message
  there names the required `this` as `never`, the intersection of the
  members') while a union of the `void` one with a signature declaring no
  `this` at all is accepted. The METHOD half is the union receiver, and
  its first draft was SILENT on the file it was written for:
  `shapes_definitely_disjoint` is a property-PRESENCE test ("each side
  requires a property the other lacks"), and `Real` / `Fake` declare the
  same two member names and differ only in `data`'s TYPE. A shared member
  whose types definitely differ is the other half, and it is the one
  tsc's own message walks down to.
  TS18033 through a BLOCK-SCOPED shadow is the second, and the recorded
  blocker was exact and unfixable where it was stated: an enum is hoisted
  into `module_.enums` with no record of the block it came from, so the
  `let Infinity = {}` that shadows the numeric lib global is in no env
  the checker's half of that rule can read. The PARSER sees both, in
  order, in the same statement list, so the verdict is decided there over
  one frame per block and the marker IS the finding. An INNER numeric
  shadow masks an outer non-numeric one, which is the lookup order the
  language uses.
  The third is the closure-narrowing rule, and CLAUDE.md had filed it
  with the rule it is NOT. Probing had already refuted "reset narrowing
  on entering a nested function" (TypeScript preserves a parameter's
  narrowing in a closure created in the narrowed region) and the note
  concluded the fact needed was "this binding is assigned somewhere other
  than its initializer". That is still too wide: `x = 1` BEFORE a
  `typeof x === "number"` guard leaves the narrowing intact, while
  `x = "hi"` after it does not. What decides it is whether the assigned
  value can inhabit the narrowed type — position-free, and a LITERAL
  right-hand side answers it where an arbitrary expression does not. The
  fact rides the ENV rather than `CheckCtx`, as `<unstable-assign>NAME`
  entries written where a function body is entered: the env is what the
  closure-entry functions copy into the inner scope, so it travels with
  the bindings it is about and needs no ctx field with the save / clear /
  restore discipline `self.labels` needs at fifteen sites.
  `check_funcexpr_with_context` already had HALF of it — `reset_narrowing`
  resets every narrowing for a class-expression body, where the REGION
  decides; here the BINDING does.
  Two rules landed only because their FIRST version was reverted with a
  measured cause, which is the series' recurring shape. TS2304 for an
  undeclared name in a type-ARGUMENT position (`new Date<A>`) was written,
  built and REVERTED for a false positive on legal code, and the corpus
  then caught four more of its own — all the same missing fact, "is this
  spelling a type ANYWHERE in the file". A block-local interface declared
  twice, an OBJECT-LITERAL method's own `<A>` (which reaches no
  `in_scope_type_params`) and a generic ARROW's type parameters (not in
  the AST at all) are three ways to spell a type the rule could not see.
  All three go on the `<type-param-name>` channel
  `parse_type_param_names_bounds_and_const_flags` already fills for
  exactly this kind of abstention, and the two paths that DISCARD the
  names get a LOOKAHEAD recorder rather than a hook inside the skip loop,
  because only one of the two `<...>` forms in the expression grammar is a
  declaration: `skip_type_args` also runs for a type ARGUMENT list, where
  the identifiers are references, and recording those would make the rule
  abstain on its own subject.
  And a TS2684 for a CLASS method's declared `this` type was REJECTED with
  its probe: `class C<E, A> { m1(this: C<never, A>, x: number) {} }` with a
  `C<number, string>` receiver is ACCEPTED, because `E` appears in no
  member and TypeScript is structural — a phantom type parameter makes
  every `C<X, A>` mutually assignable. `applied_generic_mismatch` compares
  type arguments nominally, so the naive rule is a false positive on five
  hand-written cells and the general version needs real structural
  assignability of `Applied` types.
  One operational finding, and it is the merge-state rule this file had
  not had to state: the branch's PR was merged by its author at the head
  of batch EP while batches EQ onward were still local, so the follow-up
  work was REBASED onto the new default branch rather than stacked on
  merged history.
  Batches EU-EY take **MISS in scope 50 -> 46** (TP 2665 -> 2669, FP 0)
  and their more valuable half is what the corpus cannot score: three of
  the five batches buy ZERO files each, two false positives on legal code
  were fixed, and a SEGFAULT was found that predates them all.
  The crash is the one to read first, because the bug is in a function
  nobody had reason to suspect and the input came from a NEW RULE feeding
  it an old shape. `types_definitely_differ` recurses on types `unwrap`
  has ALREADY resolved — that is its whole design, it proves rather than
  normalizes — and it had no depth bound, so a self-referential `typeof`
  closes the loop: `function fnArg1(x: typeof fnArg1) { var x: (n: typeof
  fnArg1) => void }` unwraps both sides to `fnArg1`'s own signature,
  aligns them as `Func` pairs, and recurses on the parameter forever.
  `witness.ts` — a corpus file that had been a TP for as long as the
  oracle existed — ended the process the moment batch EU's function-scope
  TS2403 sweep handed it that pair. The module-level spelling could
  always reach it, and "pre-existing" is a claim this file requires to be
  MEASURED: the branch was stashed, HEAD rebuilt, and
  `var x: typeof fa; var x: (n: typeof fa) => void` segfaulted there too.
  Bounded at 16, matching `identity_key`; running out of depth abstains,
  which is that function's own fail direction. The general lesson is the
  one `verify-checker-scaling` exists for with the axis swapped: a rule
  that merely WIDENS the population a shared helper sees can expose an
  unbounded recursion the helper has carried for years, and no gate here
  watches for a crash — the oracle scored it as one lost TP.
  Three of the five batches are the applied-in-some-places family, and
  EU's is the purest instance of it yet at a SCOPE boundary rather than a
  site: TS2403's rule and its identity comparison ran over
  `module_.top_level_stmts` and nowhere else, so `function f() { var b:
  number; var b: string }` — the same mistake one scope in — was silent,
  and so was every class method, constructor, arrow and function
  expression. All four callable spellings were taken in one pass through
  a SHARED comparison rather than a copied one. What made it cheap is
  that `var` is FUNCTION-scoped, so the group is collectable by a
  STATEMENT walk that is complete by construction: only a declaration
  statement can introduce a `var`, and every boundary it must not cross
  (an arrow, a function expression, a class expression) is an
  EXPRESSION it never walks.
  EV is the same family across four spellings of one declaration, and the
  reason to record it is that each lost the fact a DIFFERENT way. A
  generic FUNCTION's type arguments have been solved at the call site for
  as long as `infer_call` existed and a generic METHOD's never were: an
  interface records its binders in `method_type_params` and a class
  method in `TsClassMethodDecl.type_params`, both present for years and
  read only by `scoped_bindings_for_method`, never at a call; a member
  written as a function TYPE carries them on the `GenericFunc` wrapper,
  which `lookup_method_sig` had no arm for — the EIGHTH fail-open
  wrapper-node arm in this file's ledger, and the costliest kind, since
  it made the whole member OPAQUE rather than merely un-instantiated;
  `infer_call` had the same hole for a generic callable arriving as a
  VALUE; and an inline object type's method signature threw the binders
  away in the PARSER, under a comment saying it did. A CONSTRUCT / CALL
  signature's binders are deliberately NOT carried and the reason is a
  number rather than an argument: wrapping them cost a true positive
  outright (`genericCallWithOverloadedConstructorTypedArguments2`, whose
  members are all `new <T>(…)`), because the wrapper is visible to every
  consumer that matches the member's shape.
  EY is the sixth time in this series that a recorded abstention's stated
  REASON was the work, and the first where an EARLIER batch had gone
  looking for it and missed. Batch EN measured
  `is_assignable_to_inner`'s source-intersection merge arm as unreachable
  for an intersection-typed VALUE, reverted a fix that "provably changes
  nothing", and wrote that finding what abstains first "is the actual
  work". It is an explicit `(Intersection(_), _) => return` in
  `check_expr_against`, under a comment saying the modelling was "still
  too coarse structurally" — and the abstention was TOTAL, not partial:
  an intersection-typed value was invisible in every assignment, against
  every target, a bare `string` included. The lesson is that a
  MEASUREMENT of an arm's unreachability names the arm and not the cause,
  so "something above abstains first" is a lead that still has to be
  followed with a probe rather than re-derived by reading.
  Three false positives on legal code came out of these batches and none
  was reachable from the corpus, which is the fourth, fifth and sixth
  consecutive round where the legal neighbour caught what the gate
  structurally cannot. `x?.(args)` has no receiver — what the `?.` guards
  is the CALLEE — so it took the "shape this cannot read" default and was
  widened unconditionally, and `declare const c: (n: number) => number;
  const r: number = c?.(1)` is ACCEPTED by tsc; batch EH had fixed
  exactly this at the three chain forms that DO have a receiver. And the
  unrestricted intersection rule is the same +1 conformance file with
  FOUR false positives (`A & B` into `A`, into `B`, an intersection
  carrying an index signature into `A`, a recursive alias into `A`),
  because `is_assignable_to` is the RESOLVER-FREE entry point and cannot
  expand a `Named` target structurally — which is what the old comment's
  "too coarse" actually meant, and the restriction to an index-signature
  target is what makes the merged shape the exact question.
  EX's guard is worth reading for HOW its first version was wrong.
  `{ [P in string]: V }` IS `{ [k: string]: V }`, and so is `keyof any`,
  but a HOMOMORPHIC mapped type over `any` yields `any` and NOT a shape —
  so the rule needs "the value does not depend on the key", and the first
  attempt to test that was defeated by a SHAPE rather than by an
  argument: `type_references_any` walks the structural variants and has
  no `IndexedAccess` arm, so `Box<T[P]>` reads through it as independent
  of `P` and two TS7-accepted files were reported. Answered by a separate
  predicate rather than by widening that walk, whose other consumers ask
  a different question. A second fact came with it: the substituted value
  has to be REDUCED before it is stored, because `unwrap` reduces
  `any[string]` to `any` at the top level and nothing reduced it inside a
  type ARGUMENT, so the shape came out `PropDesc<any[string]>`.
  Two rejections carry their blockers. `this` inside an object-literal
  `function` property is the commonest shape in this round's remainder
  and was INSTRUMENTED rather than argued about: binding it around the
  entries works and the binding arrives as `{ n: number; f: () => any }`,
  and `check_funcexpr_with_context` then rebinds `this` to `Any` —
  deliberately, with its reason at the site, because a parser-lowered
  nested class becomes a prototype-assigned function expression whose
  `this` is the inner instance. Undoing that needs the type threaded past
  it AND a `noImplicitThis` flag the checker does not carry (probed: the
  shape is TS2339 with the flag and ACCEPTED without it), which is three
  pieces of plumbing for one file. And `typeof x === "object"` narrowing
  `unknown` to `object | null` cannot be taken alone: the file it would
  flip needs `if (!x) return` and `if (x === null) return` to narrow
  `unknown` too, so the narrow rule by itself is two false positives in
  that same file.
  The capability table in `UNSUPPORTED.md` §2 was re-probed one file per
  row, and TWO of its rows were wrong in the direction that matters. The
  index-signature WRITE read BLIND for two revisions and had been handled
  in all four spellings the whole time; the template-literal placeholder
  read BLIND while the error shape reports. A capability table nobody
  re-measures ranks the wrong work — the same defect, one level up, that
  retired `docs/checker-priority.md`, and the argument for keeping §2
  beside §1 rather than folding them together.
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
  Its gates all asked one of two questions and neither was the important
  one. `verify-scaffolds` / `verify-generated-fixtures` /
  `verify-examples` ask whether a generated package COMPILES;
  `scripts/bridge_quality_report.sh` asks whether a REJECTED export is
  budgeted. **Nothing asked whether the code emitted for an ACCEPTED
  export RUNS**, and the answer was no. A tagged-union case whose payload
  is `Named(N)` was discriminated with `value instanceof N` whether or not
  `N` exists at runtime: `tagged_union_named_constructor_name` asks
  whether a name is PascalCase and MoonBit-spellable — a NAMING test —
  and the discriminator read that as licence to emit the predicate, so an
  interface, a type alias, an enum and a type parameter all got one. 411
  unbound sites over 197 distinct names, against 14 globals and 4 bound;
  **2,126 of 2,530 converter calls threw `ReferenceError`** under Node.
  The names are the diagnosis on their own — `T` / `TResult` /
  `TDriverParam` are type parameters, `PathLike` / `Booleanish` are
  aliases, `ScriptTarget` / `ModifierFlags` are enums, `Expression` /
  `SourceFile` / `Identifier` are TypeScript interfaces.
  The rule ALREADY EXISTED, which makes this the family this file keeps
  recording rather than a missing feature.
  `moonbit_inline_union_runtime_named_ok` is the global-constructor
  allowlist and its own doc comment states this exact hazard ("interfaces,
  type aliases, and type parameters have no runtime binding, so `value
  instanceof Name` would throw in the generated converter"); it was
  consulted at ONE site, and there only when the union has a FUNCTION
  member, because the call sits inside `if func_members > 0`. That
  condition is right for the check immediately above it — a second
  function case collides on `typeof === "function"` — and has nothing to
  do with whether a sibling's `instanceof` resolves, so it is the
  namespace `if outer_modules.length() == 0` shape again: one item's
  condition inherited by others that do not share it.
  What made declining cheap is splitting the two converter DIRECTIONS,
  which had been emitted as a pair: `_to_js` reads `$tag` and needs no
  runtime predicate at all, so parameter positions keep their types and
  only the return-side `_from_js` is withheld, with a note naming the
  case. Before the split a declined `_from_js` took the sound `_to_js`
  down with it. The whole fix costs ZERO product surface — the bridge
  quality report is identical on every metric — because
  `ffi_tagged_union_return_is_safe_to_wrap` already refused to CALL these
  converters, so the 411 sites were dead broken code. That is also why
  nothing noticed: `just verify-bridge-runtime`
  (`scripts/verify_bridge_runtime.mjs`) is the harness that was missing,
  and it needs BOTH of its halves — a static check that every
  `instanceof X` has `X` a JS global or a module binding (complete, since
  it sees a site whichever arm a probe value reaches) and a runtime check
  that imports all 86 generated bridge modules and calls every exported
  `_from_js` over a value battery (which is what proves the static list is
  real rather than a grep artifact). The reason the corpus could not reach
  it is the recurring one: the ONLY fixture with live `_from_js` calls is
  `boolean | "boundary"`, with no `Named` member anywhere, so not one
  fixture put a named type in a return position.
  The rejection side got the same treatment, and its lesson is the
  count-versus-item one. `heterogeneous_union_unsupported_export_budget`
  was set to 0 when the count was 0, an example added later
  reintroduced two, and the report had been exiting 1 ever since with no
  way to tell an accepted limitation from a regression — the defect that
  retired `docs/checker-priority.md`, in a shell script.
  `scripts/bridge_widened_unions.txt` declares each occurrence with a kind
  and a reason; an UNDECLARED occurrence fails, and a declared entry that
  no longer occurs is reported STALE, which is the one mechanism that
  keeps such a file from becoming a suppression list (both directions
  proven by mutation, not asserted). The diagnostic it declares had to be
  fixed first, because it named a cause that CANNOT OCCUR: "non-PascalCase
  named, function, or unsupported shape" lists a function member, which is
  accepted as `FnValue`, and put everything real under "unsupported
  shape" — so an anonymous object type and an object intersection, the two
  actual occurrences, could not be told apart from a lowercase name by
  reading the message. And the honest verdict on those two is that neither
  earns the object-payload feature they both want:
  `BufferEncodingOption`'s `{ encoding: "buffer" }` is redundant with its
  `"buffer"` string member, which the existing fallback already
  constructs, and `WriteFileOptions` needs a SECOND thing — its sibling
  `BufferEncoding` is a node global this package does not resolve, so even
  a successful lowering would hand the user a case payload they cannot
  build.
  The mirror-image defect is the DECLARED type promising a representation
  the emitted JS never builds, and `scripts/bridge_enum_return_probe.mjs`
  asks for it: `@hono/node-server` declared `serve(...) -> ServerType`
  while the wrapper returned the raw Node server object, and the
  representation is not a guess — the alias's own constructor emits
  `{ "$tag": 0, "_0": value }`, so a MoonBit `match` read `$tag` off an
  object that has none. Fixing it is worth recording mostly for HOW the
  first attempt failed: it measured as a NO-OP, and the predicate was
  never the reason. Two rounds of reading the code got the diagnosis
  wrong; one `println` settled it in a single run, and the lesson is to
  instrument a "this cannot be happening" gap rather than re-read it.
  Two causes, both this file's recurring shapes. The walk had `Named` and
  `Func` arms and no `CallableMeta`, which records source-level parameter
  OPTIONALITY — so `get_serve`'s `(Options, ((AddressInfo) -> Unit)?) ->
  ServerType` fell through the catch-all while the sibling
  `get_create_adaptor_server`'s `(Options) -> ServerType`, having no
  optional parameter and therefore no wrapper, widened correctly. That
  asymmetry between two adjacent declarations is what exposed it.
  `ffi_type_name` peels the same wrapper on its own FIRST line: a walk
  that DECIDES a type has to peel every wrapper the renderer peels, or it
  decides a different type from the one that gets printed. Fifth
  wrapper-node fail-open arm here. And the ten renderer sites were found
  by grepping the assignment `let return_type = ffi_type_name(state, …)`,
  which missed `ffi_callable_value_decl_to_moonbit` — the renderer for
  the direct call form, the one that emits `serve(...)` — because it
  spells its local `return_type_src`. Writing a shared
  `ffi_output_type_name` specifically to avoid the applied-in-some-places
  family and then applying it by textual match on a variable NAME is that
  family inside its own fix; the census is by ARGUMENT now.
  The predicate was wrong too, and the TEST found it rather than the
  corpus. `ffi_tagged_union_return_is_safe_to_wrap` refuses ANY
  `InstanceOfNamed`, global constructors included, so `PathLike = string
  | Buffer | URL` is "unsafe to wrap" while its `_from_js` exists and
  works — widening on that gate would have widened node_fs's twelve
  global-`Named` union returns as well. The right question is
  `tagged_union_from_js_expression(decl, "value") is None`, which is
  exactly what withholds the `_from_js` half. The three
  `*_should_emit_wrapper` predicates deliberately do NOT consult the
  widening: they refuse a wrapper whose rendered type uses `JSValue`, so
  routing them through it would DELETE `serve(...)` instead of widening
  it, and their real question — does this wrapper carry any type
  information — is still answered yes by the typed PARAMETERS.
  It also surfaced a pre-existing defect nothing could see while the two
  renderings agreed: the `.mbti` carries declarations the `.mbt` does
  not, because the decl layer and the ffi layer render the same value
  export independently and `add_bridge_ergonomic_helper_decls` guarded on
  `contains(helper_decl)` — a substring test using the full SIGNATURE,
  asking "is this exact line present" where the question is "is this
  FUNCTION declared". MoonBit has no overloading, so a second
  `declare pub fn` of one name is always wrong; while the two layers
  happened to render identical text the duplicate was skipped and the
  disagreement was invisible.
  **The first measurement of it was wrong, and the way it was wrong is
  this file's own recurring mistake in the instrument**: a pattern
  `^declare pub fn [A-Za-z_][A-Za-z0-9_]*` stops at `::`, so
  `BuilderProgram::getProgram` and six sibling METHODS collapsed onto
  `BuilderProgram` and read as a duplicated name — reported as "52
  duplicated names of 2,161 in the `typescript` package, 13 in vitest, 9
  in node_fs", which is an artifact of the regex and not a defect.
  Taking the name up to the `(` that must follow it immediately gives the
  real answer: **4 duplicated names in 2 packages**, all four with no
  impl counterpart at all — three `get_*` value getters in
  hono__node_server and node_fs's `mkdir` (one `pub extern "js" fn
  mkdir`, so not overloading either). In every case the stale line is the
  LESS precise one (`get_serve() -> JSValue` against the impl's
  `() -> (Options, cb?) -> JSValue`; `mkdir`'s `callback : JSValue`
  against its real callback type), except `get_create_adaptor_server`,
  whose stale line was more precise and simply untrue.
  The fix makes the `.mbti` AGREE with the `.mbt` by construction rather
  than accumulate beside it: the derived declaration REPLACES a
  same-named line in place, keyed by name through one map lookup per line
  (a scan per name over the `typescript` package's 2,161 declarations is
  the quadratic this file keeps paying for). Proven to touch nothing
  else — regenerating the whole corpus before and after and diffing every
  declaration line order-independently leaves **85 of 87 packages
  byte-identical**, with the 2 changed losing exactly those 4 lines. The
  report gains a `duplicate declared fn names` metric that FAILS on any
  occurrence, mutation-tested in both directions and verified not to fire
  on the `Type::method` forms that fooled the first measurement.
  The other half of that split is a gate that contradicted its own doc
  comment for a whole commit, and it is worth recording as its own
  failure mode: a comment describing intent, written in the same change
  that left the code doing the opposite. 8d227ad rewrote
  `ffi_tagged_union_return_is_safe_to_wrap`'s header to say that a global
  constructor "resolves and is kept … which is why `PathLike = string |
  Buffer | URL` gets a working wrapper", and left
  `Some(InstanceOfNamed(_)) => return false` in the body — so `PathLike`'s
  `_from_js` was emitted, exercised by `verify-bridge-runtime`, and never
  CALLED, and the declared enum came back holding a raw JS string.
  Refusing an ERASED name is `tagged_union_case_runtime_discriminator`'s
  job and it already does it by returning `None`; a second, blunter copy
  of that judgement could only disagree with the first, which is exactly
  what it did.
  Measured ALONE that gate change is a zero-diff no-op, because nothing
  else consults it for a global-`Named` union return — and it is
  load-bearing all the same, proven by mutation: with the old arm back the
  regenerated accessor is `#| (self) => self.path` again. A change whose
  own corpus delta is zero is not automatically the rejected kind this
  file records; the question is whether something downstream needs it.
  What needed it is FOUR accessor paths that never asked about tagged
  unions at all. `ffi_class_property_getter_decl_to_moonbit` and its
  setter twin route through `ffi_rendered_generated_enum_info` /
  `ffi_enum_arg_expr`, which walk `state.enums` — the LITERAL-union
  enums, whose converters are MoonBit functions in `converters.mbt`. A
  tagged union's converters live in `bridge.js`, so the class METHOD path
  puts the argument direction in the JS BODY
  (`ffi_inline_js_arg_expr_with_state`) and the accessor path had neither
  direction: node_fs's `ReadStream.path: PathLike` declared the enum both
  ways while moving the raw value, and no compile gate could see it
  because the declared type is identical either way. Same
  applied-in-some-places family with the axis swapped — not one rule
  written at several SITES, but one site asking about one of two FAMILIES.
  The return direction needed a helper that did not exist,
  `ffi_inline_js_return_expr_with_state`, because an inline extern lambda
  cannot import the named `bridge.js` helper —
  `ffi_inline_js_tagged_union_to_js` says so in its own comment. It binds
  the value before converting, since the from_js body repeats its argument
  once per case predicate and the expression here is `self.path`, a
  property READ, where the named helper reads a parameter. Statics keep
  the named helpers, their binding being a real `bridge.js` function.
  **The setter fix then covered a SECOND family nobody was looking for**,
  and it is 26 of the 33 changed lines: `ffi_inline_js_arg_expr_with_state`
  also unwraps an OPTION box, so `Context::set_context_env(value :
  Bindings?)` had been assigning MoonBit's `{$tag: 1, _0: v}` straight
  into JS's `env` field, across hono, hono-real, drizzle, vitest and
  typescript. One missing call, two independent wrong values; every
  package's `.mbti` declaration count is unchanged, so the public surface
  is identical.
  The probe was the stated precondition and widening it is where the
  lesson sits. `bridge_enum_return_probe.mjs` matched `declare pub fn
  NAME(`, so `fn[T]` and every `Type::method` form was skipped — but the
  half that mattered was not the regex: a declaration's implementation
  lands EITHER in a named `bridge.js` wrapper OR in an inline extern
  lambda, and only the first was ever read. It now reads both (47 named
  wrappers and 8 inline bodies cross a payload enum, 0 unconverted) and
  is wired into `bridge_quality_report.sh` as a `run_check` rather than
  reimplemented in shell. `verify-bridge-runtime` gets the same widening
  on its static half, under the STRICTER rule that only a JS global can
  resolve inside an inline lambda, which has no module scope at all. Its
  first version walked every `.mbt` under `_build` and reported three
  `instanceof` targets out of `moon fmt`'s copy of a checker whitebox
  test, whose `#|` lines are TypeScript SOURCE for a test case: widening
  the input set is not the same as widening the question, so it is scoped
  to the directories holding a generated `bridge.js`.
  Asked to take the next item — bind a module-exported class so its
  `instanceof` resolves — the measurement retired the item and found
  eighteen live bugs beside it. The filed ceiling was "about ten names,
  worth doing for the `stat()` family specifically", and importing each
  generated package's OWN module and asking `typeof mod[name]` gives **2
  bindable names of the 197 declined**. Every name the estimate listed
  fails, for two separable reasons: hono__node_server's `Server` /
  `Http2Server` / `IncomingMessage` / `ServerResponse` are exported by a
  DIFFERENT module — `node:http` classes the package re-exports as TYPES,
  so `__ts_mbt_module.Server` is `undefined` and binding needs another
  module's import rather than the one-line threading the item described —
  while `StatsFs` / `BigIntStats` / `BigIntStatsFs` are type-only. And the
  ceiling is a question about CONVERTERS, not names: `_from_js` is withheld
  unless EVERY case is discriminable, so `Stats` being a real class buys
  nothing while `BigIntStats` stays erased, which is precisely the `stat()`
  family the item called its prize. Two converters unblock, one of them in
  a return position. Ninth instance of a label standing in for the
  objective, and the first where the label was a NAME COUNT standing in for
  a conjunction over cases.
  What the measurement is actually worth is what it exposed. `aliasedTable`
  converts its ARGUMENT and hands its return back raw while declaring
  `-> Auto_ViewValue_or_TableValue` — the `ServerType` bug again — and the
  probe written one commit earlier to catch exactly that could not see it,
  for two independent reasons. It tested `/_from_js|_to_js|\$tag/` over the
  whole body, so the `$tag` belonging to the PARAMETER's conversion passed
  the return: "this body contains a conversion somewhere" is not "this body
  converts its return", and the two directions are separate questions with
  separate shapes (`"$tag":` / `_from_js(` BUILDS a MoonBit value,
  `.$tag ===` / `_to_js(` READS one). And it read payload enums from
  `bridge.mbti` alone, where a SYNTHESIZED `Auto_X_or_Y` is never
  declared — **212 of the 231 payload enums live in `types.mbt`**. Fixing
  both takes the probe from 0 findings to 18. Fifth time this session the
  measuring instrument carried the same substitution bug as the code it was
  hunting, after the payload filter, the `::` regex, the snake-case
  function and the input-set widening.
  All 18 were declared in `scripts/bridge_unconverted_enum_crossings.txt`
  with a kind and a reason each; undeclared fails, stale fails, both
  mutation-tested. Turning 18 invisible wrong values into 18 named ones
  with reasons was the deliverable — and the STALE half is what emptied the
  file, twice: it retired the `optional-gate` pair as soon as that was
  fixed, and then all 16 that were left. **The declared backlog is zero**,
  which is the state where a NEW unconverted crossing fails immediately.
  Those 16 were ONE decision made in three places plus two renderers that
  had never been asked, and every step contradicted the step before it.
  `ffi_widen_unbuildable_union_outputs` had no arm for a SYNTHESIZED union —
  such a union keeps its `Union(parts)` shape in the AST while its signature
  already reads `Auto_X_or_Y`, which `ffi_inline_js_tagged_union_to_js`
  states in its own comment sixty lines away, the sixth fail-open shape arm
  in this file's ledger and the first written INSIDE the fix for the fifth.
  The arm's FIRST version was then ORDER-DEPENDENT, which is the finding
  worth keeping: it asked whether the alias was already in
  `state.tagged_union_decls_by_name`, a map filled as a SIDE EFFECT of
  rendering, so the answer depended on whether an earlier declaration in the
  file happened to mention the same union.
  `Auto_IdentifierValue_or_PrivateIdentifierValue` is also a PARAMETER of
  `idText` nine lines above and was registered;
  `Auto_VariableDeclarationValue_or_ParameterDeclarationValue` occurs exactly
  once and was not — so one declaration was fixed and its neighbour silently
  was not, the applied-in-some-places family with the sites picked by
  declaration ORDER rather than by anyone's decision.
  `ffi_output_union_decl` builds the decl (`{ name, cases }`) on the spot.
  Widening the extern alone gives `[4014] has type JSValue?, wanted
  Auto_...?`, because there are THREE renderings of one export: the `.mbti`
  line comes from the DECL layer and the public wrapper is rendered FROM that
  line. `reconcile_bridge_widened_union_returns` makes the declaration agree
  with the extern that implements it — the principle
  `add_bridge_ergonomic_helper_decls` already states, that the `.mbt` is what
  the package really is. It has to be SCOPED and that is the whole
  difficulty: a declaration differing from its extern is the NORMAL case (a
  literal-union enum crosses as an `Int` and the wrapper converts it; an
  opaque type arrives as `JSValue` and the wrapper wraps it in an option), so
  it fires only where the extern hands back `JSValue` at the SAME optionality
  AND the declared type is one of the two things the widening can leave
  behind. Both halves are needed and only one was written first: when the
  union is still mentioned elsewhere the enum survives and the symptom is
  `[4014]`, and when the widened return was its LAST mention nothing
  synthesizes the enum any more and the identical stale line is `[4032] the
  type Auto_... is undefined` — which is how `walkUpBindingElementsAndPatterns`
  failed to COMPILE in the same run where `getNameOfJSDocTypedef` came out
  right.
  The `.mbti` emitter was found by INSTRUMENTING, and the first run of that
  experiment was a FALSE ZERO of exactly the kind this file keeps recording:
  markers in the three `declare pub fn` renderers of `parser_moonbit.mbt`
  attributed 0 of 11 lines, because the fixture chosen was a class-only
  `.d.ts` and a class declares no top-level function, so
  `func_decl_to_moonbit` was never called. A zero from a probe whose shape is
  ABSENT is not an answer, and the note that stood here — "it is not any of
  the `declare pub fn` literals in `moonbit_bridge.mbt`, so the body comes
  from elsewhere" — was drawn from it. It is `parser_moonbit.mbt:1426`,
  reached through `moonbit_decl.mbt:12526`.
  The last two sites are the family on a fresh axis each. An index
  signature's two DIRECTIONS are two questions and were rendered with one
  type name: `index_get` crosses JS -> MoonBit and widens, `index_set`
  crosses the other way, where `_to_js` reads `$tag` and needs no runtime
  predicate, so it keeps its type and converts in the body — and
  `ffi_inline_js_arg_expr_with_state`'s own tagged-union test was
  `Named`-only, which would have sent every synthesized union down the
  generic option unwrap to read `value._0` off a value MoonBit does not box.
  And a METHOD's return needed the widening, but NOT in
  `ffi_function_type_parts`: a function type has no direction of its own, so
  the same rendering types a method's return and a CALLBACK parameter's
  return, and widening there threw away a type that works and broke
  `Matcher::_call_`, whose wrapper reads a struct FIELD rendered elsewhere
  (`has type ExpectationResult, wanted JSValue`). It belongs in the one
  branch of `ffi_function_field_method_decl` that binds straight to a JS
  call. That leaves the struct FIELD itself still promising the enum
  (`erasedMethod : (String) -> Auto_BetaValue_or_AlphaValue` in `types.mbt`)
  — filed rather than half-applied, because the fix is a direction parameter
  on `ffi_func_type_name` and the probe did not read struct fields, so the
  honest first step was to COUNT them.
  That count is section C of the probe, and it retires the entry that asked
  for it. The label was standing in for the objective again — tenth instance
  here, and the widest miss yet at **54x**: filed as "the function-typed
  struct field" at 8, the class is ANY struct field carrying a payload enum,
  at **438**. And what is wrong is a missing DIRECTION rather than a missing
  arm. The corpus emits **259 `_to_js` struct converters and ZERO in the
  other direction**, so a JS object handed to MoonBit as a struct is used
  RAW: `Program::getSemanticDiagnostics` is
  `(self, a, b) => self.getSemanticDiagnostics(a, b)`, which unwraps its
  argument options and does nothing to the returned `Array[Diagnostic]`, so
  `diag.messageText` is a raw JS string under
  `Auto_StringValue_or_DiagnosticMessageChainValue` and a `match` on it reads
  `$tag` off something that has none — with 33 externs returning `Diagnostic`
  and `getSemanticDiagnostics` the most-used API the TypeScript compiler has.
  That MoonBit structs are name-keyed JS objects is measured rather than
  assumed: `__ts_mbt_to_js_diagnostic` reads one with `value["messageText"]`.
  READ-REACHABILITY is the filter that makes it tractable and it changed the
  answer by 50x — only a struct appearing in a RETURN position can receive a
  JS value at all, and one that only crosses MoonBit -> JS is served
  correctly by the `_to_js` converter that exists. 438 fields become **151**
  read-reachable, **8** convertible and **143** erased, and the alarming
  first reading ("247 React aria attributes would have to widen") was
  measuring the wrong set: react_types is **5** under the filter. The ranking
  is two rows, `typescript_ast` and `typescript` being the same
  `typescript.d.ts` generated twice at 68/67 each, so the distinct work is 68
  fields in ONE package plus 15 across six others.
  The instrument carried the same substitution bug as the code TWICE, the
  seventh time in this sequence: `bridge.js` helper names are the generator's
  snake_case, which DOUBLES the underscore at a PascalCase boundary inside an
  already-underscored name (`Auto_BoolValue_or_X` ->
  `auto__bool_value_or__x`), so a hand-written snake_case reported 8/430 and
  a too-loose match reported 260/178. Comparing with underscores stripped and
  reconstructing nothing gives 8/143. Budgeted per PACKAGE in
  `scripts/bridge_struct_enum_fields.txt` rather than declared per
  occurrence, because 438 declarations rank no work and eight rows rank it
  directly; growth fails, an undeclared package fails, and a drop is reported
  so the budget follows it down, all three mutation-proven.
  Both of the fixes that entry filed were worse than a third one, and one was
  wrong on its own terms: a CONVERTING accessor "keeps the type information"
  only where a converter EXISTS, and an erased enum has none, so that route
  never applied to the erased half at all. What moved the count was making
  more unions CONVERTIBLE. `tagged_union_from_js_expression` refused a union
  the moment ONE case lacked a runtime discriminator and only has to refuse at
  TWO: the union is CLOSED, so failing every other case's test IS the
  remaining case and that one needs no predicate. `string |
  DiagnosticMessageChain` is exactly that shape — and it is
  `Diagnostic.messageText`. Two erased cases and the else cannot choose
  (`CatchClause | VariableDeclarationList`), which is why the 133 left are the
  AST `parent` unions. The `throw` was the only thing that noticed a value the
  `.d.ts` mis-declared and such a value is now tagged as the fallback case;
  the alternative it replaces is the caller receiving a raw JS value under a
  type claiming `{$tag, _0}`, wrong in the same direction and silent, so
  nothing that used to be caught stops being caught.
  Relaxing the builder immediately exposed a SECOND copy of its judgement —
  the failure 8d227ad is already recorded for.
  `ffi_tagged_union_return_is_safe_to_wrap` had its own `None => return false`
  arm, so a `_from_js` now existed (the widening therefore stopped firing)
  while the gate still declined to CALL it, and five declarations promised the
  enum over a raw JS value again. It asks the builder now and keeps only its
  own reason, a `TypeofFunction` payload the auto-wrap cannot model. Three of
  those five were then the SEVENTH fail-open shape arm and the third distinct
  site of the `Named`-only spelling in this file:
  `ffi_type_needs_js_return_conversion_with_state` and
  `ffi_type_js_return_expr` — a predicate and an emitter, each in an optional
  and a non-optional spelling — matched `Named` at all FOUR arms, so a
  synthesized union fell through every one and
  `mkdtempSync_string_encoding_option_optional` declared
  `Auto_StringValue_or_NonSharedBufferValue` over a raw `mkdtempSync(…)`.
  And the budget gate shipped one commit earlier was itself wrong in the
  convertible direction: `convertible` RISING is an improvement, and gating
  all three axes upward reported five packages as having GROWN when ten fields
  moved out of the unfixable half — only `reachable` and `erased` are gated
  now. Measured: **8 -> 18 convertible, 143 -> 133 erased**, four of the eight
  packages at zero erased, converters 1,330 -> 1,377 with 15,147 exercised
  calls at **0 runtime failures**, which is the check that matters since every
  new fallback converter is executed there over a value battery. One test was
  UPDATED rather than fixed and the distinction is worth keeping: it asserted
  a deliberate abstention (`from_js is None` for `PathLike | number`), not a
  bug, and its real concern — that `v instanceof PathLike` is never emitted —
  is still asserted.
  That pair is the fourth time in this sequence that a declining note's
  own stated reason was false, and both of its reasons were.
  `ffi_inline_js_return_expr_with_state` said converting an optional would
  "box a value that path already boxed" — CHECKABLE and unchecked, since
  `ffi_option_return_inner_is_boxed` returns FALSE for a tagged-union
  alias, so `ffi_option_return_needs_wrap` never fires for one and no
  MoonBit-side wrap exists to collide with (`Some(v)` IS `v`, `None` IS
  `undefined`), confirmed against the emitted code rather than the source.
  It also said no corpus declaration had the shape, and
  `TypeChecker::getConstantValue` returns `Auto_NumberValue_or_StringValue?`
  — `String | Double`, both primitives, so `typeof` discriminates.
  And the site was a THIRD renderer. `TypeChecker` is an INTERFACE, so
  `getConstantValue` never reached the class-method path; patching that
  path, regenerating, and finding the count UNCHANGED is what found
  `ffi_function_field_method_decl`. Interface methods, class methods and
  the four accessor paths are three separate renderers of one decision, and
  the ARGUMENTS were routed through the conversion at all of them while the
  RETURN was routed at none — the same family as the accessors, one axis
  further out, and the reason to fix a renderer and then MEASURE rather
  than assume the site was the one that looked obvious.
  The 133 erased struct fields are `JSValue` now, which takes that count to
  **zero** — the declared type is the type the emitted JS actually hands
  over, where `VariableDeclaration.parent` used to promise
  `Auto_CatchClauseValue_or_VariableDeclarationListValue` over a raw JS
  object a `match` would read `$tag` off. What makes the widening safe to
  apply at all is that it is DIRECTIONAL, and computing the direction is
  the whole change: `ffi_collect_read_reachable_struct_names` seeds every
  RETURN position in the module set and closes over struct FIELDS, so a
  struct reachable from a returned struct is itself one a JS value can
  arrive as, while a write-only struct keeps its enum and its working
  `_to_js` converter — react_types' `aria_checked` still declares
  `Auto_BoolValue_or_...`. For a `Func` field only the RETURN is followed,
  because a callback's PARAMETERS are written by MoonBit and read by JS,
  which is the opposite direction and exactly what broke `Matcher::_call_`
  when an earlier attempt put the widening in `ffi_function_type_parts`.
  Two findings, and the first is this file's own recurring family committed
  INSIDE the fix for it: the change measured NOTHING on its first run
  because an INTERFACE-derived struct is rendered by
  `ffi_struct_decl_to_moonbit` and an anonymous one by
  `ffi_named_struct_decl_to_moonbit` — two renderers of one decision, one
  of them patched, found by regenerating and seeing 133 unchanged. And the
  last five erased were the PROBE over-counting rather than the generator
  under-widening, with the generator's AST pre-pass the thing that
  disagreed: `HTMLAttributes::asAriaAttributes(self) -> AriaAttributes =
  "%identity"` is a MoonBit-side upcast of a value the CALLER built, not a
  JS boundary crossing, and section C was reading it as a return position.
  Eighth time in this sequence that the measuring instrument carried the
  same substitution bug as the code. Measured: erased 133 -> 0, fields
  carrying an enum 438 -> 304, read-reachable 151 -> 17, synthesized enums
  227 -> 180 (47 nothing references any more), 14,630 converter calls at 0
  failures. The 17 left are CONVERTIBLE and widening them would be a
  regression — `Diagnostic.messageText`, `TypeChecker.getConstantValue`,
  vitest's `diff`, the two JSX `children` unions — each with a working
  `_from_js` that nothing calls at a struct field, which is the separately
  filed `_from_js` struct converter and 259 functions' worth of mirror.
  `ffi_func_type_name`'s missing direction parameter is untouched by this:
  "can a JS value arrive as this STRUCT" and "which way does this function
  TYPE cross" are different questions.
- `src/mtsc` is the type checker's LIBRARY surface — the one thing here
  that is not reached through the CLI. It is IO-free by construction, and
  it used to take that to its limit: `checkModuleGraph` made the caller
  pre-resolve the whole program and hand over module sources plus the
  import edges between them. That is exactly right for a bundler plugin,
  which already holds every source, and wrong for anybody else, because
  it makes module resolution a prerequisite for type-checking one file.
  So resolution moved IN and the IO moved OUT, behind the `MtscHost`
  trait — TypeScript's own split, where `LanguageServiceHost` supplies
  file access and the service resolves. Three questions (what are the
  roots, what text is at this path, what are the options) and four
  implementations: an in-memory map, Node's `fs`, a bundler's virtual
  filesystem, a test fixture.
  Four things about that boundary were settled by PROBING rather than
  reasoning, because the whole design depended on them and none is
  documented anywhere. A JS object crosses in as an `#external type` and
  a trait can be implemented FOR it, so generic dispatch over
  `MtscHost` monomorphizes on the JS backend. A JS `undefined` arrives
  as `None` for a `String?` return, which is what lets `read_file`
  double as the existence check. A `pub(all) struct` leaves as a plain
  object whose keys are the field names, so diagnostics can be
  structured rather than the string the old ABI flattened them into.
  And `Array` in an `extern "js"` SIGNATURE is deprecated while
  `FixedArray` is not — a distinction that does not apply to an exported
  function's return type, where `Array[MtscDiagnostic]` is fine.
  A TRAIT rather than a struct of closures, for the property this file
  records twenty-plus instances of paying for: MoonBit requires an
  `impl` to supply every method, so a new host cannot inherit a default
  that fails open. Same compiler-driven completeness as `TsFunc`'s
  `name_is_member_key`, which enumerated its 32 construction sites
  instead of leaving them to a grep.
  It is deliberately SYNCHRONOUS, and that is why the trait does NOT
  live in `src/parser` beside the resolver that already does filesystem
  IO. That resolver is `async` throughout — 26 `async fn`s over an async
  filesystem — so a sync trait cannot serve it and an async one cannot
  serve a `LanguageServiceHost`, whose `readFile` is sync by design. A
  shared interface today would be a guess that fits neither consumer;
  the two boundaries stay separate until something crosses both. The
  resolution this one does is relative specifiers only, with the
  `Types`-mode candidate ordering lifted from `module_resolver.mbt`
  (`.d.ts` before the implementation; `./util.js` probing `./util.ts`
  first, because in ESM TypeScript that specifier means the source and
  probing the written extension checks an emitted artifact instead).
  Bare specifiers are NOT resolved, and `MtscResolvedModule.isExternal`
  is what keeps that from being reported as a failure — "no such file"
  and "not this resolver's job" are different answers, and conflating
  them sends a caller looking for a file that was never meant to exist.
  An unresolved RELATIVE import is a diagnostic, and no rule was written
  for it: `graph_import_globals` already reports exactly that and
  already stays silent on a bare one, so the loader adds no edge and
  says nothing, which is one judgement in one place instead of two that
  can disagree.
  The checking itself is untouched. `collect_parsed_graph_issues` was
  EXTRACTED from `collect_module_graph_issues` — the body after the
  parse loop, verbatim — so a program loaded from a host lands in the
  same representation a caller of the old ABI would have built by hand
  and is checked by the same code. The host path cannot drift into
  answering differently from the pre-resolved path, and the extraction
  is regression-checked from both ends (`checkModuleGraph` in the Node
  harness, and the CLI's `--bundle --noEmit`, which is the other
  consumer).
  `start` and `length` are ABSENT from `MtscDiagnostic`, and that is a
  fact about the checker rather than a shortcut: `@checker.ExprIssue`
  carries a message and a breadcrumb, `@parser.ParseError` carries a
  message, and neither carries an offset. `ts.Diagnostic` declares both
  optional for precisely this case, so a consumer that checks first
  keeps working; inventing them would put a squiggle under the wrong
  code. The breadcrumb ships as `context` instead, which is what makes
  the diagnostic actionable without a span.
  Pinning that absence is where I made the mistake this file keeps
  warning about, and caught it only by mutating. The obvious spelling,
  `// @ts-expect-error` over `const n: number = d.start`, **passes
  whether or not the field exists** — add `start?: number` and the
  expression is `number | undefined`, still an error under `strict`, so
  the expectation still has something to suppress. Measured: adding the
  field left `tsc` green. The assertion is on `keyof` now, which is the
  claim being made, and it fails when the field is added. A test that
  cannot fail while the thing it checks is broken is coverage-shaped,
  and the only way I found out was breaking it on purpose.
  Two harnesses, because neither covers the other.
  `moon test --target native src/mtsc` drives the service through
  `MtscMemoryHost` — 35 cases over the same generic code JavaScript
  reaches, which is what makes the memory host more than a test double.
  `just verify-language-service` covers what only Node can see: the
  `extern "js"` host calls, the marshalling across them, a REAL
  filesystem under a temp directory, a `ts.LanguageServiceHost`-shaped
  host with `getScriptSnapshot` and no `readFile`, and the facade.
  Mutation-proven on its first run, which is the only reason to believe
  22/22 on a fresh harness: dropping the `.js` -> `.ts` remap, swallowing
  parse errors, and removing the `getScriptSnapshot` fallback each fail
  it. The second of those was a bug I actually shipped into the first
  draft and it is worth the note — `mtsc_load_program` looked for parse
  failures in `program.modules`, which holds exactly the files that
  PARSED, so the check could never fire and every syntax error in a
  program would have been reported as nothing at all. The loader records
  them at the point of failure now.
  `just check-js` is a separate gate for a structural reason: `targets`
  in `moon.pkg` restricts `host_js.mbt` and `service_js.mbt` to the `js`
  backend, so `moon check --deny-warn` never compiles the FFI layer at
  all. Without that step the whole boundary is unchecked until somebody
  runs a JS build. It covers the WHOLE MODULE — it was scoped to this
  package while the root's `moonbitlang/async/fs` import read as unused
  on `js`, and that is fixed at the source rather than excluded (see the
  `src/cmd/mtsc` entry: the dependency's own `unimplemented` symbol is
  named from the live `js` arm, so nothing is suppressed anywhere).
- `src/cmd/mtsc` is the ONLY binary, and it runs on Node as well as
  natively — `moon build --target js` produces the same CLI as a
  self-contained IIFE Node executes directly (`just build-cli-js`
  prints the path, `just verify-cli-node` is the gate). An earlier
  revision declared `supported_targets = "all-js"` so that build would
  SKIP this package instead of failing inside it; that fixed the build
  by trading the capability away, and the trade was unnecessary. Only
  ONE symbol was actually missing (`@async_fs.mtime`) and the rest of
  the CLI compiled for `js` untouched.
  The blocker is real and worth stating: `moonbitlang/async/fs` says in
  its own `unimplemented.mbt` that it "does not support JavaScript
  backend" and restricts every source file but that one to `native` /
  `wasm`, so both `mtime` and `rename` are absent there. What makes the
  per-target arm cheap is that the native arm is `async` ONLY by virtue
  of that call, so a sync JS arm makes the `async` on
  `mtsc_watch_stamps` useless (warning 0067) — and the fix for THAT is
  one `#warnings("-unused_async")` at that one declaration, not a
  per-target duplicate of a six-line loop. The alternative was
  genuinely worse: `node:fs/promises` would keep the signature `async`
  and match `mizchi/x/fs`'s own JS backend, but awaiting a JS promise
  needs `moonbitlang/async/js_async`, which is then unused on NATIVE,
  and that is the gate.
  The unused-import problem those two dependencies create has a fix
  that needs no suppression at all, and it is the dependency's own:
  `@async_fs.unimplemented` is the ONE symbol the package exposes on
  `js`, declared `#cfg(not(target="native"))` under that doc comment,
  i.e. it exists to be named in exactly this situation. Naming it from
  the live `js` arm in each of the two packages that need the
  dependency only on native makes the import genuinely referenced on
  every backend, so `moon check --deny-warn --target js` is clean for
  the WHOLE MODULE and `just check-js` widened from `src/mtsc` to
  everything. Deliberately not `warnings = "-0029"`, which
  `mizchi/x/fs` itself uses for this: a package-wide suppression also
  hides a genuinely dead import, on every target, which is how a gate
  stops being a gate. A standalone `#cfg(target="js")` function holding
  the reference was tried first and is worse — it is itself unused
  (warning 0001), so the reference has to sit in live code.
  Two bugs were found by RUNNING it, and neither is reachable by
  building. The first is the one that matters: **`@env.args()` does not
  have the same shape on every backend.** `moonbitlang/core/env` returns
  `process.argv` VERBATIM on `js`, which has TWO leading entries (the
  Node executable and the script) where the native runtime's argv has
  one (the program). `driver.mbt` reads that shape at six places, so
  under Node the CLI took its own 19 MB bundle as a second input file
  and reported `ParseError("Unexpected token: Gt")` against ITSELF,
  turning `mtsc ok.ts --noEmit` on a clean file into exit 1. Normalized
  once in `mtsc_argv` rather than patched at the six sites — the
  offset-assumed-in-several-places defect, avoided in its own fix. The
  `-e` case is declared rather than guarded: `node -e '…' a b` has no
  script path so the drop would eat `a`, and a built bundle is never run
  that way.
  The second was SILENT, and is the reason the watch round trip is in
  the harness rather than left to a smoke test. The mtime probe first
  read `require("node:fs")`, and this bundle is a `.js` IIFE under a
  `package.json` saying `"type": "module"`, so Node loads it as ESM —
  where `require` is not defined. Measured: a probe under ESM gives
  `ReferenceError: require is not defined`, which the body's own `catch`
  turned into "no stamp" for EVERY file; "no stamp" compares equal to
  the previous "no stamp", so `--watch` would have polled forever and
  never rebuilt, looking exactly like a watcher with nothing to do.
  `process.getBuiltinModule` is the sync builtin accessor that works
  from either module system (Node 22.3 / 20.16 up), with `require` kept
  as the CommonJS fallback.
  `just verify-cli-node` is a differential against the NATIVE binary —
  same source, a different backend and a different runtime for every
  syscall the CLI makes — over 16 cases plus a `--watch` round trip on
  both backends, comparing stdout, the exit code, and for the emit cases
  the FILE written (a backend whose `write_file` silently did nothing
  would otherwise pass on a matching empty stdout). Mutation-proven:
  reverting the argv normalization fails eight cases and reverting the
  mtime probe fails the watch round trip with the diagnostic written for
  it. Exactly ONE case is allowed to diverge and it says why — a missing
  entry file, where `mizchi/x/fs` relays the OS error text and the two
  backends word it differently (`@fs.open(): "nope.ts": No such file or
  directory` against `ENOENT: no such file or directory, open
  'nope.ts'`); the case asserts what must be true of both and still
  requires the exit codes to match exactly, and it FAILS if the two ever
  become identical, so the allowance cannot outlive its reason. Two
  measurement notes, both this file's recurring shape: `node … | tail`
  reports `tail`'s exit code, which made a correct exit 1 read as 0 and
  sent me looking for a bug that was not there; and the ESM `require`
  finding came from probing the extracted body under `.mjs` rather than
  from reasoning about the bundle's format.
  `ts2mbt`, `mbt2ts`, `tscheck` and
  `tsacc` were four more, and they are now four verbs —
  `mtsc bridge`, `mtsc pkg`, `mtsc check`, `mtsc conformance` — with the
  compile path staying the default, positional mode. The dispatch rule is
  that a VERB wins over a same-named file, so `mtsc check` does not depend
  on whether a directory called `check` happens to exist; `mtsc ./check`
  still names the file. `TODO.md` records the opposite move ("the `tsmbt`
  binary was split into per-direction `ts2mbt` / `mbt2ts` binaries"), and
  what makes the re-merge different is that the split was about a
  `--direction` FLAG, where the verbs are about one entry point.
  The compile mode's command line is a SUPERSET of `tsc` / `tsgo`, and the
  claim rests on three tiers rather than on a flag table.
  **HONOURED** is the set with real behaviour behind it. **ACCEPTED** is
  the set mtsc parses and has no behaviour for — `--target`, `--module`,
  `--strict` and ~90 more — and it reports them in one line rather than
  obeying or refusing them. That middle tier is the whole design: a
  pipeline built around `tsc` passes `--target es2020 --strict` as a
  matter of course, so refusing means the vocabulary can never be shared,
  and accepting silently means `--strict false` looks obeyed while the
  checker runs strictly anyway. **REJECTED** is everything else, and it
  now exits NON-ZERO — mtsc used to print "unknown option" and exit 0, so
  a typo in a build script was invisible. `--build` / `-b` is rejected
  with its own sentence, because `tsc -b` on a solution file is not a
  request to compile that file.
  Option NAMES match ignoring case, `-` and `_`, which is a strict
  superset of what `tsc` does (it lowercases and stops). That is what
  lets mtsc's kebab-case history (`--no-check`) and `tsc`'s camelCase
  (`--noCheck`) be ONE option rather than two tables that can disagree —
  and `--noCheck` turning out to be `tsc`'s own name for a flag mtsc had
  already invented is the reason the merge is free rather than a
  compromise.
  Four findings are worth more than the plumbing. **The two check paths
  are different questions and both are kept**: `mtsc --noEmit` walks the
  import graph and checks it as one program, which is what CI asks `tsc`
  for, while `mtsc check` checks ONE file with a single-file model, which
  is what the conformance corpus needs (each of its 4,484 cases is a
  one-file program). Folding the second into the first would have
  retargeted the checker's own gate. Its output is an INTERFACE for the
  same reason — `checker_conformance_oracle.sh`, `checker_precision.sh`,
  `verify_checker_scaling.mjs` and `checker_miss_buckets.mjs` all parse
  the summary line, and it exits 0 whatever it finds because those
  scripts run under `set -e`. Verified by capturing 36 cases from the five
  old binaries and diffing: **23 are byte-identical**, and the 13 that
  differ are help text, the version string and that one deliberate exit
  code. The oracle itself was then run end to end on a synthetic
  five-file corpus (the `typescript/` submodule is not checked out here),
  which classified 3 TP / 2 TN correctly through `mtsc check`.
  Second, **`-v` stopped being a conflict by being in two scopes**.
  `tscheck -v` is verbose and `tsc -v` is version; as verbs they never
  meet, which is the one thing the layout buys for free.
  Third, **a watcher never exits, so nothing ever flushes stdout**. C
  stdio block-buffers a pipe, so `mtsc --watch > build.log` produced an
  EMPTY log while compiling correctly — every line arrived at once when
  the process was killed. It is fixed with `fflush(NULL)`, bound as
  `extern "c" fn(Int64)` and passed `0L` because MoonBit has no pointer
  type and both target ABIs pass a 64-bit integer and a pointer in the
  same register — the same assumption the existing `exit` binding already
  makes. Proven by measurement rather than by reading: a probe printing,
  flushing, then sleeping 4 s puts its first line in a redirected log at
  t=2 s, and without the flush nothing lands until exit. A one-shot
  compile needs none of this, because exiting flushes.
  Fourth, **`--watch` watches the resolved PROGRAM, not the entry list**,
  and it reuses the loader to get it. An independent walk could disagree
  with the compiler's, and a watcher that disagrees misses rebuilds.
  Two limits are declared rather than left to be discovered: a file ADDED
  under an `include` pattern is not seen until something already in the
  program changes (a new path has no previous mtime to differ from), and
  the resolution caches in `main.mbt` have to be CLEARED per pass — their
  own comment says "a compile is one process over a snapshot of the tree,
  so nothing here can go stale within a run", and watch mode is the one
  caller for which that is false.
  `tsconfig` reading went into the PARSER, next to the scanner it reuses,
  rather than into the CLI. `tsconfig_compiler_option` answers for STRING
  options only — `parse_json_string_at` returns `None` for `true`, so
  every boolean in a tsconfig was invisible — and `-p` also needs the file
  sets. tsconfig is JSONC, so a second reader in the CLI would have been
  the one-rule-in-several-places defect with comments as the first thing
  the two copies disagree about. The FILESYSTEM half stayed in the CLI:
  the parser says what a config means, the CLI says which files that is.
  `node_modules` is pruned during the walk and not filtered after it,
  because a project with dependencies installed has two or three orders
  of magnitude more files there than in its own tree.
  Two pre-existing defects surfaced and are fixed, both stated here so
  they are not re-attributed to the merge. `CLI_VERSION` read `0.4.0`
  against a `moon.mod` reading `0.5.2` — harmless while the only consumer
  was a banner nobody asserted, and a wrong answer once `mtsc --version`
  became a `tsc`-compatible surface. And `checker_precision.sh` could
  never produce output: `find … | sort -z` fed newline-separated records
  to a NUL-separated reader, so the entire file list arrived as ONE
  record, `COUNTS` got a single multi-line key, and the later
  `${!COUNTS[@]} | tr ' ' '\n'` split it back into paths that were not
  keys — `unbound variable` under `set -u`. Its `find` also read
  `(depth<=3 AND *.ts) OR *.tsx`, collecting `.tsx` at any depth, since
  `-o` binds looser than the implicit `-a`. Proven pre-existing by
  running HEAD's version with only the binary path swapped; it now
  reports 160 files, 0 parse errors, 277 issues, which is its first real
  output. `moon check --deny-warn` was also not clean on this toolchain
  (moonc v0.10.13 against the v0.10.12 the file records) — four
  `unused_package` warnings, two of which vanished with `tsacc` and
  `tscheck` and two of which were genuinely unused `for "wbtest"` imports
  of `moonbitlang/core/debug`. It is clean again, and it IS the gate.
  `src/parser/pkg.generated.mbti` was stale too, missing a `Parser` field
  that HEAD's source already had; `moon info` corrects it.
  The one cost of the consolidation is written into `.moonignore`, which
  used to exclude `src/cmd/tscheck` from the published archive. The two
  development verbs now SHIP, because there is no longer a package
  boundary to exclude them at. They are inert unless invoked by name and
  add no dependency the compile path did not already link — `parser` and
  `checker` both arrive through `transform`, which is also why `tsacc`'s
  original reason for being a separate binary (a fast link of just those
  two) no longer existed.

## Project Structure

```
typescript.mbt/
├── moon.mod
├── js/                      # The JS library surface (see `src/mtsc`)
│   ├── language-service.mjs # `createLanguageService` facade + hosts
│   └── language-service.d.ts
└── src/
    ├── ast/                 # Shared AST types
    ├── parser/              # TypeScript / JavaScript parser + module resolver
    ├── checker/             # Declaration-level TS type system
    ├── transform/           # mtsc pipeline: bundle / fold / treeshake / mangle
    ├── mtsc/                # Checker entry points + the injectable-host API
    │   ├── checker.mbt      # `checkModuleGraph`: caller pre-resolves
    │   ├── host.mbt         # `MtscHost` trait + `MtscMemoryHost`
    │   ├── resolve.mbt      # sync host-driven module resolution
    │   ├── service.mbt      # the language service (target-independent)
    │   ├── host_js.mbt      # `extern "js"` host — `js` target only
    │   └── service_js.mbt   # the JS entry points — `js` target only
    ├── bridge/              # Bridge code generation (both directions)
    ├── main.mbt             # `mizchi/ts` library: bridge entry helpers
    ├── unified_cli.mbt      # `--input ... --out ...` unified driver
    ├── bridge_cli.mbt       # `mtsc bridge` / `mtsc pkg` verb dispatch
    └── cmd/
        └── mtsc/            # THE binary. Native + Node (`just build-cli-js`).
            ├── main.mbt             # compile pipeline + graph loader
            ├── driver.mbt           # verb dispatch, entry resolution, run loop
            ├── tsc_options.mbt      # the tsc-superset option layer
            ├── tsconfig_project.mbt # -p: include/exclude globbing
            ├── watch.mbt            # --watch (mtime polling)
            ├── check_cmd.mbt        # `mtsc check`      (was `tscheck`)
            └── conformance_cmd.mbt  # `mtsc conformance` (was `tsacc`)
```

## Dependencies

- `moonbitlang/async` - async file I/O for the CLI.

## Commands

```bash
# Check for errors AND warnings. This is clean and is the gate — an
# earlier note here said it could not be, which was true of a tree
# carrying 450+ warnings and is not true now. Keep it at zero: the way
# it stopped being a gate the first time was a `warnings = "-00.."`
# line in one package's moon.pkg, not a decision anyone made.
#
# Clean on moon 0.1.20260915 / moonc v0.10.13. It was NOT clean when
# that toolchain first ran against a tree last verified on v0.10.12 —
# four `unused_package` warnings appeared, which is the second way this
# gate stops being one: a newer compiler reports more. Two of the four
# were real dead imports and are gone. So "clean" is a claim about a
# toolchain as much as about the tree, and bumping the toolchain means
# re-running this before trusting it.
moon check --deny-warn

# Run tests. Takes about an hour, and most of that is NOT tests: the
# `*_bench_wbtest.mbt` files use the `(it : @bench.T)` signature, whose
# `it.bench(fn() { … })` runs its body many times to get a timing, and
# `moon test` executes those loops too. The checker's bench alone is
# 20-30 minutes of CPU in one process at 100%, which is indistinguishable
# from a hang — this was mistaken for one twice, once correctly (an
# O(n^2) rule, see batch CP) and once not. To tell them apart, run the
# one file: `moon test --target native src/checker/expr_check_wbtest.mbt`
# is ~10 seconds, so if THAT hangs the problem is real.
moon test --target native

# Run parser microbenchmarks
moon bench --target native

# Format code
moon fmt

# Generate type definitions
moon info

# Validate `--mangle-properties` against the mangle-safety corpus
just verify-mangle-safety

# The JavaScript backend. `moon check --deny-warn` does NOT see the
# `js`-only files — `src/mtsc/host_js.mbt` and `service_js.mbt` are
# restricted by `targets` in `moon.pkg`, and the CLI's
# `#cfg(target="js")` arms are compiled out — so this is the run that
# checks the whole FFI boundary, and it is a gate of its own. Clean for
# the whole module.
just check-js

# Build the library for JS and run it under Node. `just build-js` alone
# builds and copies the artifact next to the facade.
just verify-language-service
just verify-language-service-types

# The CLI on Node: build it, then diff its behaviour against the native
# binary (16 cases plus a `--watch` round trip on both backends).
just build-cli-js
just verify-cli-node
```

## Notes

- Target: `native` for every harness, and `js` is a SECOND target for
  the WHOLE module — the library (`src/mtsc`, consumed through
  `js/language-service.mjs`) and the CLI, which Node runs directly. Both
  backends are gated: `moon check --deny-warn` for native,
  `just check-js` (whole module) for the `js`-only files the native
  check structurally cannot see, `just verify-language-service` and
  `just verify-cli-node` for what only Node can observe.
- The repo no longer ships a JS interpreter or wasm codegen; entry-point
  parsing is read-only and produces declarations / bridge code only.
