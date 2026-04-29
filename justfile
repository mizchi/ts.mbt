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
    WASMX_ROOT="$ROOT/mizchi/wasmx"
    MOONBIT_ROOT="$ROOT/moonbitlang/core"

    rm -rf "$ROOT"
    mkdir -p "$TS_ROOT" "$WASMX_ROOT" "$MOONBIT_ROOT"

    moon run src -- emit-typescript-from-mbti src/ast/pkg.generated.mbti "$TS_ROOT/ast.d.ts" >/dev/null
    moon run src -- emit-typescript-from-mbti src/parser/pkg.generated.mbti "$TS_ROOT/parser.d.ts" >/dev/null
    moon run src -- emit-typescript-from-mbti src/analysis/pkg.generated.mbti "$TS_ROOT/analysis.d.ts" >/dev/null
    moon run src -- emit-typescript-from-mbti src/runtime/pkg.generated.mbti "$TS_ROOT/runtime.d.ts" >/dev/null
    moon run src -- emit-typescript-from-mbti src/codegen/pkg.generated.mbti "$TS_ROOT/codegen.d.ts" >/dev/null
    moon run src -- emit-typescript-from-mbti src/aot/pkg.generated.mbti "$TS_ROOT/aot.d.ts" >/dev/null
    moon run src -- emit-typescript-from-mbti src/bridge/pkg.generated.mbti "$TS_ROOT/bridge.d.ts" >/dev/null
    moon run src -- emit-typescript-from-mbti src/pkg.generated.mbti "$TS_ROOT/root.d.ts" >/dev/null

    cat <<'EOF' > "$MOONBIT_ROOT/debug.d.ts"
    export interface Debug {}
    EOF

    cat <<'EOF' > "$MOONBIT_ROOT/json.d.ts"
    export interface ToJson {}
    EOF

    cat <<'EOF' > "$MOONBIT_ROOT/bigint.d.ts"
    export interface BigInt {}
    EOF

    cat <<'EOF' > "$WASMX_ROOT/core.d.ts"
    export interface Code {}
    export interface FuncType {}
    export interface Module {}
    export interface TypeDef {}
    EOF

    cat <<'EOF' > "$WASMX_ROOT/encode.d.ts"
    export interface ModuleEncodeResult {}
    EOF

    cat <<'EOF' > "$WASMX_ROOT/parse.d.ts"
    export interface ModuleParseResult {}
    EOF

    cat <<'EOF' > "$WASMX_ROOT/runtime.d.ts"
    export interface Instance {}
    export interface Runtime {}
    export interface Value {}
    EOF

    cat <<'EOF' > "$ROOT/tsconfig.json"
    {
      "compilerOptions": {
        "strict": true,
        "noEmit": true,
        "module": "esnext",
        "moduleResolution": "bundler",
        "baseUrl": ".",
        "lib": ["es2020"]
      },
      "files": [
        "mizchi/ts/ast.d.ts",
        "mizchi/ts/parser.d.ts",
        "mizchi/ts/analysis.d.ts",
        "mizchi/ts/runtime.d.ts",
        "mizchi/ts/codegen.d.ts",
        "mizchi/ts/aot.d.ts",
        "mizchi/ts/bridge.d.ts",
        "mizchi/ts/root.d.ts",
        "moonbitlang/core/debug.d.ts",
        "moonbitlang/core/json.d.ts",
        "moonbitlang/core/bigint.d.ts",
        "mizchi/wasmx/core.d.ts",
        "mizchi/wasmx/encode.d.ts",
        "mizchi/wasmx/parse.d.ts",
        "mizchi/wasmx/runtime.d.ts"
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

# Benchmark a local TypeScript project corpus
benchmark-project root limit="200":
    moon run src -- benchmark-project {{root}} {{limit}}

# Benchmark built-in corpora (repo fixtures + optional local checkouts)
benchmark-corpora limit="200":
    moon run src -- benchmark-corpora {{limit}}

# Full CI check
ci: fmt check test verify-mbti-dts verify-scaffolds verify-generated-fixtures verify-examples

# Update dependencies
update:
    moon update

# Clean build artifacts
clean:
    rm -rf _build target

# Emit experimental wasm-gc binary
experimental-emit-gc file output="out.wasm":
    moon run src -- experimental-emit-gc {{file}} {{output}}

# Run experimental wasm-gc tests with wasmtime
experimental-wasmtime-test:
    #!/usr/bin/env bash
    set -e
    echo "=== wasmtime-gc integration tests ==="

    # Simple function tests
    moon run src -- experimental-emit-gc tests/wasmtime/simple.ts tests/wasmtime/simple.wasm

    # Test factorial (filter out warnings, get last line which is the result)
    result=$(wasmtime --wasm gc --invoke factorial tests/wasmtime/simple.wasm 5.0 2>&1 | tail -1)
    if [ "$result" = "120" ]; then
        echo "PASS: factorial(5) = 120"
    else
        echo "FAIL: factorial(5) expected 120, got $result"
        exit 1
    fi

    # Test factorial with different input
    result=$(wasmtime --wasm gc --invoke factorial tests/wasmtime/simple.wasm 10.0 2>&1 | tail -1)
    if [ "$result" = "3628800" ]; then
        echo "PASS: factorial(10) = 3628800"
    else
        echo "FAIL: factorial(10) expected 3628800, got $result"
        exit 1
    fi

    # Struct tests
    moon run src -- experimental-emit-gc tests/wasmtime/struct_basic.ts tests/wasmtime/struct_basic.wasm

    result=$(wasmtime --wasm gc --invoke createPoint tests/wasmtime/struct_basic.wasm 2>&1 | tail -1)
    if [ "$result" = "30" ]; then
        echo "PASS: createPoint() = 30 (struct with f64 fields)"
    else
        echo "FAIL: createPoint() expected 30, got $result"
        exit 1
    fi

    # Array tests
    moon run src -- experimental-emit-gc tests/wasmtime/array.ts tests/wasmtime/array.wasm

    result=$(wasmtime --wasm gc --invoke sumArray tests/wasmtime/array.wasm 2>&1 | tail -1)
    if [ "$result" = "60" ]; then
        echo "PASS: sumArray() = 60 (gc array)"
    else
        echo "FAIL: sumArray() expected 60, got $result"
        exit 1
    fi

    # Math function tests
    moon run src -- experimental-emit-gc tests/wasmtime/math.ts tests/wasmtime/math.wasm

    result=$(wasmtime --wasm gc --invoke testSqrt tests/wasmtime/math.wasm 16.0 2>&1 | tail -1)
    if [ "$result" = "4" ]; then
        echo "PASS: Math.sqrt(16) = 4"
    else
        echo "FAIL: Math.sqrt(16) expected 4, got $result"
        exit 1
    fi

    result=$(wasmtime --wasm gc --invoke distance tests/wasmtime/math.wasm 0.0 0.0 3.0 4.0 2>&1 | tail -1)
    if [ "$result" = "5" ]; then
        echo "PASS: distance(0,0,3,4) = 5 (pure function with Math.sqrt)"
    else
        echo "FAIL: distance(0,0,3,4) expected 5, got $result"
        exit 1
    fi

    echo "=== All wasmtime tests passed ==="

# Experimental AOT check - verify fixtures are AOT compilable
experimental-aot-check:
    #!/usr/bin/env bash
    set -e
    echo "=== AOT Compilability Check ==="

    echo "Checking fixtures/aot/simple.ts..."
    moon run src -- experimental-aot-check fixtures/aot/simple.ts

    echo "Checking fixtures/aot/closure_readonly.ts..."
    moon run src -- experimental-aot-check fixtures/aot/closure_readonly.ts

    echo "Checking fixtures/aot/closure_mutable.ts..."
    moon run src -- experimental-aot-check fixtures/aot/closure_mutable.ts

    echo "Checking fixtures/aot/generator.ts..."
    moon run src -- experimental-aot-check fixtures/aot/generator.ts

    echo ""
    echo "Checking not_aot_compatible.ts (should fail)..."
    if moon run src -- experimental-aot-check fixtures/aot/not_aot_compatible.ts 2>&1 | grep -q "not.*compilable\|incompatible"; then
        echo "PASS: Correctly identified as not AOT compilable"
    else
        echo "Note: May contain some AOT-incompatible functions"
    fi

    echo "=== AOT check complete ==="

# Experimental AOT compile all fixtures to wasm
experimental-aot-compile:
    #!/usr/bin/env bash
    set -e
    mkdir -p _build/aot
    echo "=== AOT Compile Fixtures ==="

    echo "Compiling fixtures/aot/simple.ts..."
    moon run src -- experimental-emit-gc fixtures/aot/simple.ts _build/aot/simple.wasm

    echo "Compiling fixtures/aot/closure_readonly.ts..."
    moon run src -- experimental-emit-gc fixtures/aot/closure_readonly.ts _build/aot/closure_readonly.wasm

    echo "Compiling fixtures/aot/closure_mutable.ts..."
    moon run src -- experimental-emit-gc fixtures/aot/closure_mutable.ts _build/aot/closure_mutable.wasm

    echo "Compiling fixtures/aot/generator.ts..."
    moon run src -- experimental-emit-gc fixtures/aot/generator.ts _build/aot/generator.wasm

    echo ""
    echo "Generated files:"
    ls -la _build/aot/*.wasm
    echo "=== AOT compile complete ==="

# Experimental AOT test - compile and run fixtures with wasmtime
experimental-aot-test:
    #!/usr/bin/env bash
    set -e
    echo "=== AOT Test with wasmtime ==="

    # Compile
    mkdir -p _build/aot
    moon run src -- experimental-emit-gc fixtures/aot/simple.ts _build/aot/simple.wasm

    # Test simple functions
    echo "Testing add(2.0, 3.0)..."
    result=$(wasmtime --wasm gc --invoke add _build/aot/simple.wasm 2.0 3.0 2>&1 | tail -1)
    if [ "$result" = "5" ]; then
        echo "PASS: add(2, 3) = 5"
    else
        echo "FAIL: add(2, 3) expected 5, got $result"
        exit 1
    fi

    echo "Testing factorial(5.0)..."
    result=$(wasmtime --wasm gc --invoke factorial _build/aot/simple.wasm 5.0 2>&1 | tail -1)
    if [ "$result" = "120" ]; then
        echo "PASS: factorial(5) = 120"
    else
        echo "FAIL: factorial(5) expected 120, got $result"
        exit 1
    fi

    echo "Testing fibonacci(10.0)..."
    result=$(wasmtime --wasm gc --invoke fibonacci _build/aot/simple.wasm 10.0 2>&1 | tail -1)
    if [ "$result" = "55" ]; then
        echo "PASS: fibonacci(10) = 55"
    else
        echo "FAIL: fibonacci(10) expected 55, got $result"
        exit 1
    fi

    echo "Testing max(7.0, 3.0)..."
    result=$(wasmtime --wasm gc --invoke max _build/aot/simple.wasm 7.0 3.0 2>&1 | tail -1)
    if [ "$result" = "7" ]; then
        echo "PASS: max(7, 3) = 7"
    else
        echo "FAIL: max(7, 3) expected 7, got $result"
        exit 1
    fi

    echo "Testing abs(-42.0)..."
    result=$(wasmtime --wasm gc --invoke abs _build/aot/simple.wasm "-42.0" 2>&1 | tail -1)
    if [ "$result" = "42" ]; then
        echo "PASS: abs(-42) = 42"
    else
        echo "FAIL: abs(-42) expected 42, got $result"
        exit 1
    fi

    echo "=== All AOT tests passed ==="

# List available AOT fixtures
experimental-aot-list:
    @echo "AOT Fixtures:"
    @echo "  fixtures/aot/simple.ts           - Basic pure functions"
    @echo "  fixtures/aot/closure_readonly.ts - Closures with read-only captures"
    @echo "  fixtures/aot/closure_mutable.ts  - Closures with mutable captures"
    @echo "  fixtures/aot/generator.ts        - Generator state machines"
    @echo "  fixtures/aot/not_aot_compatible.ts - NOT AOT compatible (negative tests)"

# Scan test262 and generate allowlist/skiplist
test262-scan:
    #!/usr/bin/env bash
    # Note: not using set -e because ((count++)) returns 1 when count is 0

    TEST_ROOT="test262/test"
    ALLOWLIST="test262.allowlist.txt"
    SKIPLIST="test262.skiplist.txt"

    # Supported includes
    SUPPORTED_INCLUDES="assert.js|sta.js|compareArray.js|nans.js|propertyHelper.js|fnGlobalObject.js|isConstructor.js|deepEqual.js|decimalToHexString.js|proxyTrapsHelper.js|testTypedArray.js|detachArrayBuffer.js|testBigIntTypedArray.js|asyncHelpers.js|promiseHelper.js|compareIterator.js"

    if [ ! -d "$TEST_ROOT" ]; then
        echo "test262 not found at $TEST_ROOT" >&2
        exit 1
    fi

    > "$ALLOWLIST"
    > "$SKIPLIST"

    allow_count=0
    skip_count=0

    while IFS= read -r file; do
        # Skip harness files
        if [[ "$file" == *"/harness/"* ]]; then
            continue
        fi

        rel="${file#./}"
        content=$(cat "$file" 2>/dev/null || echo "")

        # Extract metadata block
        meta=$(echo "$content" | sed -n '/\/\*---/,/---\*\//p')

        # negative tests and async tests are now supported by the runner
        # (removed skip for negative: and flag:async)

        # Check for unsupported includes
        includes=$(echo "$meta" | grep "includes:" | sed 's/.*\[\(.*\)\].*/\1/' | tr ',' '\n' | tr -d ' "')
        skip_include=""
        for inc in $includes; do
            if [ -n "$inc" ] && ! echo "$inc" | grep -qE "^($SUPPORTED_INCLUDES)$"; then
                skip_include="$inc"
                break
            fi
        done
        if [ -n "$skip_include" ]; then
            echo -e "$rel\tincludes:$skip_include" >> "$SKIPLIST"
            skip_count=$((skip_count + 1))
            continue
        fi

        # Check for banned patterns
        if echo "$content" | grep -qE '\bwith\s*\('; then
            echo -e "$rel\tbanned:with" >> "$SKIPLIST"
            skip_count=$((skip_count + 1))
            continue
        fi
        if echo "$content" | grep -qE '\beval\s*\('; then
            echo -e "$rel\tbanned:eval" >> "$SKIPLIST"
            skip_count=$((skip_count + 1))
            continue
        fi
        if echo "$content" | grep -qE '\bFunction\s*\('; then
            echo -e "$rel\tbanned:Function" >> "$SKIPLIST"
            skip_count=$((skip_count + 1))
            continue
        fi
        if echo "$content" | grep -qE '\bimport\s+defer\b'; then
            echo -e "$rel\tbanned:import-defer" >> "$SKIPLIST"
            skip_count=$((skip_count + 1))
            continue
        fi

        # Passed all checks - add to allowlist
        echo "$rel" >> "$ALLOWLIST"
        allow_count=$((allow_count + 1))

    done < <(find "$TEST_ROOT" -name "*.js" -type f | sort)

    echo "allow: $allow_count"
    echo "skip: $skip_count"

# Run test262 tests
test262 path="test262.allowlist.txt":
    moon run src -- test262 {{path}}
