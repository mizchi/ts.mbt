# TODO

## Parser / Semantics Real-World Gaps

### Current bug
- [x] `emit-moonbit-decl` / `emit-moonbit-js-ffi` should not resolve non-exported opaque type imports.
  - Symptom: an entry like `import { ResultAsync, type Result } from "neverthrow"` crashed when the package actually existed under `/tmp/.../node_modules`.
  - Cause: `load_type_module_graph` eagerly resolved every import specifier even when the imported binding was never exported or re-exported from the entry surface.
  - Fix direction: keep re-exports / exported imports in the graph, but leave plain opaque imports unresolved.

### Remaining work
- [x] Add a stable end-to-end regression harness for the external `/tmp/tsmbt-realworld-check` repro instead of relying on ad-hoc local verification.
  - Covered by the `/tmp/ts_mbt_neverthrow_like_*` regression tests in `src/main_wbtest.mbt`, which exercise `emit_moonbit_decl_text` / `emit_moonbit_js_ffi_texts` against a pnpm-style temp project layout.
- [ ] Minimize a fixture from the actual `neverthrow` package if more parser coverage is needed beyond the graph-resolution fix.

## MoonBit / TypeScript Package Bridge Plan

Generate TypeScript-consumable bridge artifacts from MoonBit package interfaces without hand-writing `link.js.exports`, and keep the reverse `TS -> MoonBit` path aligned around the same surface model.

### Batch 1: MBTI autolink bootstrap

- [x] Emit `link.js.exports` JSON config from `.mbti` top-level public free functions.
- [x] Exclude methods / constructors / trait methods from the generated JS export surface.
- [x] Add CLI coverage so the generated config can be written directly from `pkg.generated.mbti`.

### Next batches

- [x] Add a recursive `.mbti` resolver so generated `.d.ts` imports can be rewritten to generated sibling packages instead of raw MoonBit package specifiers.
- [x] Add a high-level `MoonBit -> TS package scaffold` command that emits the autolink config and `.d.ts` bundle together.
- [x] Align the reverse `TS -> MoonBit bridge package` flow on the same top-level export surface model and resolver assumptions.

## TS Bridge Constraints

- [x] Prefer direct `#module("...")` imports when the runtime `moduleSpec` is non-relative.
  - Works for bare specifiers, `node:*`, and rooted specifiers like `/src/api/client.ts`.
  - This now covers top-level function exports, instance methods/properties, and class constructors.
- [x] Keep `bridge.js` fallback for relative module specs like `./client.js` and `../client.js`.
  - MoonBit currently rejects relative paths in `#module("...")`.
- [x] Keep wrappers for static members / value exports / namespace exports for now.
  - `= "Counter.from"` / `= "Counter.version"` style dotted import names compile poorly in the current JS backend.
  - `#module(...)` combined with inline `#|` JS also does not lower correctly for imported module bindings in the current backend.

## Normalized DTS Checker Scope

- [x] Split object-shape compatibility checks into `src/checker`.
  - `checker` currently exists to support `normalize-moonbit-dts`, not to become a full TypeScript checker.
- [x] Keep the checker scope narrow.
  - Current responsibility: decide whether object-like interface expansions can be flattened safely, or should fall back to intersections.
  - Current coverage: duplicate properties, `readonly`, optional-property keys, and "do not merge methods / overload-like members".
- [ ] Avoid growing `src/checker` into a full semantic checker unless a separate goal is explicitly chosen.
  - If future work needs real TS semantics, define that as a separate milestone instead of quietly expanding the normalization helper.

## Bridge Const-Table Batch Plan

Reduce the need to pick one edge case at a time by shipping the next `default export const table` batch together and keeping the smoke rail in sync.

### Batch scope

- [x] `import * as tables from "./x"` where `x` exports a const table.
- [x] `import tables from "./x"` where `x` re-exports a named `const TABLES`.
- [x] `import tables from "./x"` where `x` directly `export default { ... }`.
- [x] `import tables from "./x"` where `x` does `export default { ... } as const`.
- [x] `import tables from "./x"` where `x` does `export default (() => ({ ... }))()`.
- [x] `import tables from "./x"` where `x` does `export default (() => { const ...; return TABLES })()`.
- [x] `import tables from "./x"` where `x` does `export default (function() { const ...; return TABLES })()`.

### Acceptance rail

- [x] Add parser regression proving exported const-value collection for each new default-export shape.
- [x] Add decl / JS FFI / bridge-package regressions for each new shape.
- [x] Add bridge smoke fixtures so `just verify-generated-fixtures` and `just ci` execute the generated package under JS.

### Next batch: IIFE local let handling

- [x] `import tables from "./x"` where `x` does `export default (() => { let ...; return TABLES })()`.
- [x] `import tables from "./x"` where `x` does `export default (function() { let ...; return TABLES })()`.
- [x] Keep local `let` mutation conservative: if the returned table depends on reassigned locals, widen instead of resolving statically.
- [x] Add parser / decl / JS FFI / bridge-package regressions for the `let` cases.
- [x] Add bridge smoke fixtures for positive `let` cases and the conservative widened case.

### Next batch: IIFE local mutation conservative handling

- [x] `import tables from "./x"` where `x` mutates `KEYS.nested` before returning the table.
- [x] `import tables from "./x"` where `x` mutates `INDEXES[0]` before returning the table.
- [x] Keep local property/index mutation conservative even when the final runtime value is unchanged.
- [x] Add parser / decl / JS FFI / bridge-package regressions for the mutation cases.
- [x] Add bridge smoke fixtures for the conservative widened mutation cases.

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
