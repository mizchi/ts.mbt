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

# Soundness gate: build the native binary and fail if the checker reports
# more conformance false positives than the current budget. The oracle
# script skips cleanly when the `typescript` submodule isn't populated, so
# this is safe to run anywhere. The budget is 0: the checker reports no
# false positives on the conformance corpus.
verify-checker-soundness:
    moon build --target native
    bash scripts/checker_conformance_oracle.sh --max-fp 0 --max-legal-parsefail 0

# Full CI check
ci: fmt check test verify-mbti-dts verify-scaffolds verify-generated-fixtures verify-examples verify-mangle-safety verify-dce-coverage verify-checker-soundness

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
#   just verify-pass-lattice
#   just verify-pass-lattice --only fold+minify --keep
verify-pass-lattice *ARGS:
    moon build --target native --release
    node scripts/verify_pass_lattice.mjs {{ ARGS }}

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
