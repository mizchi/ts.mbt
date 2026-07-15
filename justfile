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
    moon test --target native --filter '{{filter}}'

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
    bash scripts/checker_conformance_oracle.sh {{ARGS}}

# Soundness gate: build the native binary and fail if the checker reports
# more conformance false positives than the current budget. The oracle
# script skips cleanly when the `typescript` submodule isn't populated, so
# this is safe to run anywhere. The budget is 0: the checker reports no
# false positives on the conformance corpus.
verify-checker-soundness:
    moon build --target native
    bash scripts/checker_conformance_oracle.sh --max-fp 0 --max-legal-parsefail 0

# Full CI check
ci: fmt check test verify-mbti-dts verify-scaffolds verify-generated-fixtures verify-examples verify-checker-soundness

# Update dependencies
update:
    moon update

# Clean build artifacts
clean:
    rm -rf _build target
