# TODO

## Parser / Semantics Real-World Gaps

### Current bug
- [x] `emit-moonbit-decl` / `emit-moonbit-js-ffi` should not resolve non-exported opaque type imports.
  - Symptom: an entry like `import { ResultAsync, type Result } from "neverthrow"` crashed when the package actually existed under `/tmp/.../node_modules`.
  - Cause: `load_type_module_graph` eagerly resolved every import specifier even when the imported binding was never exported or re-exported from the entry surface.
  - Fix direction: keep re-exports / exported imports in the graph, but leave plain opaque imports unresolved.

### Remaining work
- [ ] Add a stable end-to-end regression harness for the external `/tmp/tsmbt-realworld-check` repro instead of relying on ad-hoc local verification.
- [ ] Minimize a fixture from the actual `neverthrow` package if more parser coverage is needed beyond the graph-resolution fix.

## Codegen Type Mismatch Bugs

wasmtime's stricter validation exposed these pre-existing codegen bugs. The generated WASM has type mismatches that need to be fixed.

### 1. if-else statement (codegen_wbtest.mbt:99)
- **Error**: `expected f64 but nothing on stack`
- **Cause**: if-else branches don't properly leave a value on the stack
- **Test code**:
  ```typescript
  function max(a: number, b: number): number {
    if (a > b) {
      return a;
    } else {
      return b;
    }
  }
  ```

### 2. int factorial (codegen_wbtest.mbt:174)
- **Error**: `expected f64, found i32`
- **Cause**: Type inference returning i32 when f64 expected
- **Test code**:
  ```typescript
  function factorial(n: int): int {
    if (n <= 1) { return 1; }
    return n * factorial(n - 1);
  }
  ```

### 3. js simple arithmetic (codegen_wbtest.mbt:396)
- **Error**: `expected i32, found f64`
- **Cause**: JavaScript-style inference returning f64 when i32 expected
- **Test code**:
  ```javascript
  function add(a, b) { return a + b; }
  ```

### 4. typed module with nested scopes (codegen_wbtest.mbt:467)
- **Error**: `expected f64, found i32`
- **Cause**: Nested scope variable type inference incorrect
- **Test code**: Function with nested blocks and type inference

### 5. switch statement (codegen_wbtest.mbt:600)
- **Error**: `expected i32 but nothing on stack`
- **Cause**: switch cases don't properly return a value
- **Test code**:
  ```typescript
  function grade(score: int): int {
    switch (score) {
      case 5: return 100;
      case 4: return 80;
      default: return 0;
    }
  }
  ```

### 6. switch with default only (codegen_wbtest.mbt:618)
- **Error**: `expected i32 but nothing on stack`
- **Cause**: Same issue as #5, default-only case

### 7. do-while loop (codegen_wbtest.mbt:644)
- **Error**: `expected f64, found i32`
- **Cause**: Loop body type inference incorrect

## Root Causes

These bugs share common patterns:
1. **Control flow statements** (if-else, switch) not ensuring all branches leave a value
2. **Type inference** producing wrong types (i32 vs f64) in certain contexts
3. **Return value handling** in block-based control structures

## Expansion Plan (easy + coverage mix)

### Implemented (recent)
- [x] Comma operator (Seq) codegen + compilability
- [x] Logical `&&` / `||` short-circuit (i32/f64)
- [x] Unary `void` (evaluate side effects, return undefined)
- [x] `typeof` (restricted: only when operand type is statically known; return string literal)
- [x] Logical assignments `&&=` / `||=` / `??=` (Var/Prop/Index variants)
- [x] Template literals (untagged only, string-typed expressions only; desugar to concat)
- [x] Full template literals (ToString coercion for non-strings)
- [x] Computed property access in literals (const key only)

### Next in order
1. Spread in arrays/args (requires iterator protocol fixes)

### Candidates (need more groundwork)
- Spread in arrays/args (requires iterator protocol fixes)
- Arbitrary call expressions (function values / closures)

## CI Notes

- 4 parser tests also fail due to missing TypeScript submodule (not a codegen issue)
- Consider adding `actions/checkout` with `submodules: true` if those tests are needed in CI
