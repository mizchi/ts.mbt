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
  and treats any observable difference as a safety violation. A corpus only
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
  ever traded for it. All three hunt
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
  31 win / 1 loss, and getting there is a caution about reading a
  harness's own labels: of the six rules it named, only one was
  missing as named. `typeofs` was already implemented and simply
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
  ten measured targets — every one behaviour-checked, no `size-only` and
  no `BLOCKED` rows left — there is **one win**: typebox at +247 bytes
  (0.21%), eight neutral, and one loss inside a byte of the noise floor
  (-0.11% on Excalidraw). Both of the numbers that moved came from
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
  type-reading phases (`switch-fold`, `tag-rewrite`, `class-method-dce`,
  `type-fold`) still move zero bytes on all ten targets. The property
  mangler was reported inert on
  every library measured, and that turned out to be one bug rather than
  a limit: a `const f = (…) => …` had no entry in the graph's function
  table, so a call to one was treated as opaque and marked `External` —
  which IS the wildcard, so a single arrow suppressed property mangling
  for a whole bundle. Giving an arrow its declared name as an identity
  moves real bytes (hono -9.4%, neverthrow -2.6%) and removed one of the
  three LOSSes.
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
