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
  [`docs/mangle-fuzzing.md`](./docs/mangle-fuzzing.md). All three hunt
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
  rewrites that assumed a type and checked nothing — see
  [`docs/rule-equivalence.md`](./docs/rule-equivalence.md). And
  `just compare-terser` asks the
  competitive version of that question: both optimizers start from the
  same unoptimized JS, and a LOSS names a terser compress rule we have
  not ported, while a LOSS *or a tie* on a `type-aware` case means the
  type-driven pass did not fire — see
  [`docs/terser-parity.md`](./docs/terser-parity.md).
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
  nine measured targets there is **no win left** — seven neutral and two
  losses, both inside a byte of the noise floor (-0.22% on typebox,
  -0.11% on Excalidraw) —
  and the property mangler is entirely inert on every library measured.
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
