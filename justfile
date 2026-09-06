# typescript.mbt justfile

# Default recipe
default: check

# Check for errors
check:
    moon check --deny-warn

# Run tests
test:
    moon test --target native

# Run tests with filter
test-filter filter:
    moon test --target native --filter '{{ filter }}'

# Run the development-only TypeScript checker on a source file
tscheck *ARGS:
    moon run --target native src/cmd/tscheck -- {{ ARGS }}

# Format code
fmt:
    moon fmt

# Generate type definitions
info:
    moon info

# Verify emitted TypeScript declarations from pkg.generated.mbti files
verify-mbti-dts:
    #!/usr/bin/env bash
    set -euo pipefail

    ROOT="_build/mbti_tscheck"
    TS_ROOT="$ROOT/mizchi/ts"
    MOONBIT_ROOT="$ROOT/moonbitlang/core"

    rm -rf "$ROOT"
    mkdir -p "$TS_ROOT" "$MOONBIT_ROOT"

    moon run src/cmd/mbt2ts -- decl src/ast/pkg.generated.mbti "$TS_ROOT/ast.d.ts" >/dev/null
    moon run src/cmd/mbt2ts -- decl src/parser/pkg.generated.mbti "$TS_ROOT/parser.d.ts" >/dev/null
    moon run src/cmd/mbt2ts -- decl src/checker/pkg.generated.mbti "$TS_ROOT/checker.d.ts" >/dev/null
    moon run src/cmd/mbt2ts -- decl src/bridge/pkg.generated.mbti "$TS_ROOT/bridge.d.ts" >/dev/null
    moon run src/cmd/mbt2ts -- decl src/pkg.generated.mbti "$TS_ROOT/root.d.ts" >/dev/null

    cat <<'EOF' > "$MOONBIT_ROOT/debug.d.ts"
    export interface Debug {}
    EOF

    cat <<'EOF' > "$MOONBIT_ROOT/json.d.ts"
    export interface ToJson {}
    EOF

    cat <<'EOF' > "$MOONBIT_ROOT/bigint.d.ts"
    export interface BigInt {}
    EOF

    cat <<'EOF' > "$ROOT/tsconfig.json"
    {
      "compilerOptions": {
        "strict": true,
        "noEmit": true,
        "module": "esnext",
        "moduleResolution": "bundler",
        "baseUrl": ".",
        "ignoreDeprecations": "6.0",
        "lib": ["es2020"]
      },
      "files": [
        "mizchi/ts/ast.d.ts",
        "mizchi/ts/parser.d.ts",
        "mizchi/ts/checker.d.ts",
        "mizchi/ts/bridge.d.ts",
        "mizchi/ts/root.d.ts",
        "moonbitlang/core/debug.d.ts",
        "moonbitlang/core/json.d.ts",
        "moonbitlang/core/bigint.d.ts"
      ]
    }
    EOF

    pnpm exec tsc -p "$ROOT/tsconfig.json" --pretty false

# Verify fixture-generated TypeScript and MoonBit outputs end-to-end
verify-generated-fixtures:
    bash scripts/verify_generated_fixtures.sh

# Verify high-level MoonBit <-> TypeScript scaffold commands
verify-scaffolds:
    bash scripts/verify_scaffolds.sh

# Verify checked-in examples
verify-examples:
    bash scripts/verify_examples.sh

# Verify optional ghq real-world MoonBit package scaffolds
verify-realworld-moonbit:
    bash scripts/verify_realworld_moonbit.sh

# Verify optional real-world TypeScript package scaffolds
verify-realworld-typescript:
    bash scripts/verify_realworld_typescript.sh

# Generate a fixture-backed bridge quality report
bridge-quality:
    bash scripts/bridge_quality_report.sh

# Correlate the checker against the TypeScript conformance error baselines.
# Reports agreement (TP), expected misses (subset checker), and — the
# signal that matters — false positives where TS accepts but we flag.
# Requires `moon build --target native` and the populated `typescript`
# submodule. Opt-in (not part of `ci`).
checker-conformance-oracle *ARGS:
    bash scripts/checker_conformance_oracle.sh {{ ARGS }}

# Rank the conformance MISSes so the next batch can be chosen instead of
# guessed. The oracle above gates on FP and prints "MISS 344", which ranks
# nothing — a baseline NAME list says that TS7 errored, not what it said.
# This reads the codes out of the submodule baselines and reports, per code,
# `solo` (files where it is the ONLY lever, so the guaranteed yield) beside
# `total`, then a greedy cover of the whole MISS set. Read both with the
# caveats in the script header: the unit that flips is a FILE not a
# (file, code) pair, a code is not a difficulty class, and a corpus count is
# not real-world frequency. `--code TS2322` lists one bucket's files with
# each file's other codes; `--refresh` recomputes the cached per-file
# classification (minutes), re-bucketing from the cache is instant.
# Opt-in (not part of `ci`).
checker-miss-buckets *ARGS:
    node scripts/checker_miss_buckets.mjs {{ ARGS }}

# Soundness gate: build the native binary and fail if the checker reports
# more conformance false positives than the current budget. The oracle
# script skips cleanly when the `typescript` submodule isn't populated, so
# this is safe to run anywhere. The budget is 0: the checker reports no
# false positives on the conformance corpus.
#
# `--max-miss` gates the OTHER direction, which nothing used to watch: a
# rule that stops firing moves a file from TP to MISS, and every other
# number here absorbs that silently. The budget is the current in-scope
# MISS count (`scripts/checker_out_of_scope.txt` holds the declared
# remainder, `docs/checker-triage.md` the argument) — lower it whenever a
# batch improves it, the same way the FP budget only ever tightened.
verify-checker-soundness:
    moon build --target native
    bash scripts/checker_conformance_oracle.sh --max-fp 0 --max-legal-parsefail 0 --max-miss 138

# Is any checker rule superlinear in the size of a module-wide list?
#
# `verify-checker-soundness` asks whether the answer is RIGHT, over 4,484
# conformance files that are a few dozen lines each — so a rule quadratic
# in the number of interfaces, classes or exports in ONE file is invisible
# to it, and to the test suite. Two such rules have shipped: batch CP's
# TS5076 span scan (a 9 MB file went from seconds to 180+, at 100% CPU for
# 36 minutes before anyone looked), and three nested scans added at once
# in batches CY-DB, which cost 6.5x at 4,000 interfaces while the oracle
# stayed at FP 0 and every test stayed green.
#
# So this asks by GROWTH rather than by stopwatch: a size ladder per axis,
# with an exponent fitted from the endpoints. Linear is ~1.0, quadratic
# ~2.0, and anything over the budget fails and names the axis. On its
# first run it found a quadratic the fix above had missed and a second one
# that predated the whole batch series.
#
#   just verify-checker-scaling
#   just verify-checker-scaling --axis interfaces
#   just verify-checker-scaling --baseline path/to/old/tscheck.exe
verify-checker-scaling *ARGS:
    moon build --target native --release
    node scripts/verify_checker_scaling.mjs {{ ARGS }}

# Full CI check
ci: fmt check test verify-mbti-dts verify-scaffolds verify-generated-fixtures verify-examples verify-mangle-safety verify-dce-coverage verify-rule-equivalence verify-graph-walk verify-checker-soundness verify-checker-scaling

# Update dependencies
update:
    moon update

# Clean build artifacts
clean:
    rm -rf _build target

# Validate `--mangle-properties` against the mangle-safety corpus
verify-mangle-safety *ARGS:
    moon build --target native
    node scripts/generate_mangle_cases.mjs --check
    node scripts/verify_mangle_safety.mjs {{ ARGS }}

# The other direction: dead code we could remove and do not. A table of
# small programs, each asserting a marker is gone from the bundle, that
# the live markers survive, and that stdout still matches Node running
# the original. Fails on a regression against
# fixtures/dce-coverage/expected.json.
#
#   just verify-dce-coverage
#   just verify-dce-coverage --only unused-label --verbose
verify-dce-coverage *ARGS:
    moon build --target native
    node scripts/verify_dce_coverage.mjs {{ ARGS }}

# Compare against terser on the same input. Both optimizers start from
# `mtsc --bundle --no-check` plain JS, so what is measured is optimizer
# quality rather than TypeScript parsing. Two groups: `terser-rule` cases
# each aimed at one of terser's compress options, and `type-aware` cases
# terser cannot win because the saving needs the type system. A LOSS in
# the second group is a bug; a LOSS in the first is a rule we have not
# ported yet, and the report ranks them by bytes.
#
#   just compare-terser
#   just compare-terser --only inline --verbose
#   just compare-terser --update           # re-record expected.json
compare-terser *ARGS:
    moon build --target native --release
    node scripts/compare_terser.mjs {{ ARGS }}

# Every rewrite, checked against every awkward value. Each peephole /
# fold rule becomes a function body with holes, evaluated across the
# cross product of a value domain built out of counterexamples —
# undefined, -0, NaN, a Symbol, a BigInt, an object with a poisoned
# valueOf, an array-like with a negative length. One compile per rule
# covers ~600 input pairs, and the result is compared against Node
# running the TypeScript directly.
#
# UNSND means the rewrite is not equivalence-preserving. INERT means it
# never fired, so the case proves nothing.
#
#   just verify-rule-equivalence
#   just verify-rule-equivalence --rule comparisons --verbose
verify-rule-equivalence *ARGS:
    moon build --target native --release
    node scripts/verify_rule_equivalence.mjs {{ ARGS }}

# What the type information actually buys, in bytes. Each target is a
# real package cloned from git and optimized twice with identical flags,
# differing only in the input: the TypeScript SOURCE (so the six
# type-driven phases can fire) versus the same code with its types
# erased (so none of them can). `verify-real-world` cannot measure this
# — it feeds published `.js`, where the answer is zero by construction.
#
# All three legs must produce identical observations against the
# target's driver, or the row is not evidence. Needs network on the
# first run; shares the `verify-real-world` checkouts where it can.
#
# `--app` compiles an APPLICATION that consumes each library instead of
# the library's own package entry, which is the only way to ask two of
# these questions honestly: a barrel's exports are all live, so
# tree-shaking has nothing to remove, and a library's property names ARE
# its wire format, so the mangler is right to reserve them. The usage in
# each app entry is copied from that library's own README — see
# `fixtures/type-aware-corpus/app-entries/README.md`.
#
#   just measure-type-aware
#   just measure-type-aware --app
#   just measure-type-aware --only hono --verbose
#
# The `sprawlens` row is the corpus's first real APPLICATION — a preact
# app that mounts and exports nothing — and it is the only row where the
# type-reading phases move real bytes: +10,419 (2.81%), +2,491 gzipped,
# against under twelve bytes across all nine libraries combined.
#   just measure-type-aware --update        # re-record expected.json
#   just measure-type-aware --app --update  # re-record expected.app.json
measure-type-aware *ARGS:
    moon build --target native --release
    node scripts/measure_type_aware.mjs {{ ARGS }}

# Fuzz the property mangler: generate programs nobody wrote, compile each
# with and without mangling, run both, compare. A difference is a mangler
# false positive by construction. Failing programs are shrunk
# automatically, so a finding arrives as the smallest program that still
# fails rather than as a seed number.
#
#   just fuzz-mangle --iterations 500
#   just fuzz-mangle --seed 6 --iterations 1 --no-shrink   # reproduce one
fuzz-mangle *ARGS:
    moon build --target native --release
    node scripts/fuzz_mangle.mjs {{ ARGS }}

# Minify real published packages (react, the TypeScript compiler) and
# check they still behave. Needs network access on the first run, so it
# is deliberately not part of `ci`.
verify-real-world *ARGS:
    moon build --target native
    node scripts/verify_real_world_minify.mjs {{ ARGS }}

# Every combination of {treeshake, fold, minify, mangle} on the 9 MB
# published TypeScript compiler, each run afterwards AS a compiler and
# compared against the pristine copy. `verify-real-world` checks the one
# shipping flag set; this checks all sixteen, so a failure names the pass
# — a combination that breaks while each of its parts passes is an
# interaction between them. Needs `verify-real-world` to have populated
# the cache first.
#
# A SECOND table runs the same combinations over
# `fixtures/pass-lattice/lowerings.ts` — one of every TypeScript-only
# lowering — and observes VALUES rather than stdout: own keys,
# `JSON.stringify`, spread, `for…in`. The 9 MB target cannot ask either
# question (published `.js` has no `#private` fields, no enums, no
# namespaces, and stdout never shows an extra own property), which is why
# this harness ran the guilty combination on every run while bare
# `--bundle` leaked mtsc's private-field brand. Re-introducing that bug
# fails the second table and names the leaked brands.
#
#   just verify-pass-lattice
#   just verify-pass-lattice --only fold+minify --keep
verify-pass-lattice *ARGS:
    moon build --target native --release
    node scripts/verify_pass_lattice.mjs {{ ARGS }}

# Does the module-graph walk stay linear in the graph? It did not: the
# walk deduplicated on the SPECIFIER a module wrote, so `./util.js` ->
# `util.ts` (resolution REPLACING an extension, which is what
# TypeScript-with-NodeNext sources write) was never recognised as an
# already-loaded module, and every repeat visit re-read the file,
# re-parsed it and re-pushed its imports. On a diamond graph that is
# 2^depth — zod could not finish parsing 133 files in eighteen minutes.
#
# Generates the shape directly and asserts on the GROWTH RATIO between
# two depths rather than on milliseconds, so the threshold does not
# depend on the machine. Fast; runs in `ci`.
#
#   just verify-graph-walk
#   just verify-graph-walk --verbose
verify-graph-walk *ARGS:
    moon build --target native --release
    node scripts/verify_graph_walk.mjs {{ ARGS }}

# Where the compile time goes. Runs the same size ladder as
# `verify-real-world` through `mtsc --timing` and tabulates the phases,
# so a superlinear pass shows up as falling throughput as input grows.
# Reads the same cache, so run `verify-real-world` first.
bench-pipeline *ARGS:
    moon build --target native --release
    node scripts/bench_pipeline.mjs {{ ARGS }}

# Regenerate the machine-derived mangle-safety cases
gen-mangle-cases:
    node scripts/generate_mangle_cases.mjs

# mtsc against terser on REAL bundles, not hand-written cases.
#
# `compare-terser` asks "is the rule we thought of missing?" over 34
# cases, and it stood at 32 win / 0 loss while mtsc was 51% behind terser
# on a real library. This asks the blunt question: same input (each
# type-aware target's unoptimized bundle), terser's compress+mangle
# against mtsc's full pipeline, raw AND gzipped.
#
# GZIP is the number that matters — nobody ships unzipped JS, and the
# two metrics disagree: mtsc has been smaller raw and larger gzipped on
# the same target.
#
# `--rules` asks TERSER to price its own compress rules, by running it
# once per rule with that rule off. That is the ceiling for porting each
# one, measured before writing any of it — and it corrected a ranking
# that had been made by counting occurrences instead of bytes.
#
# Needs `just measure-type-aware` to have run once (it writes the shared
# unoptimized bundles).
#
#   just compare-terser-bundles
#   just compare-terser-bundles --rules
#   just compare-terser-bundles --names
#   just compare-terser-bundles --only typebox
#
# `--names` reports the identifier-length distribution in VARIABLE
# positions on both sides, and names the long identifiers mtsc keeps and
# terser renamed away. On typebox that was 46% of the byte gap, all in
# one name the mangler had been refusing to touch.
compare-terser-bundles *ARGS:
    moon build --target native --release
    node scripts/compare_terser_bundles.mjs {{ ARGS }}
