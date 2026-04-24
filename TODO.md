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
- [x] Minimize a fixture from the actual `neverthrow` package if more parser coverage is needed beyond the graph-resolution fix.
  - Covered by `fixtures/resolver/project/types/neverthrow-like-entry.d.ts` plus the pnpm-style `fixtures/resolver/project/node_modules/neverthrow-like` fixture, and exercised through decl / JS FFI / scaffold generation.

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

## Bridge / Scaffold Operational Hardening

### P0

- [x] Harden unsupported export handling in `emit-moonbit-scaffold-from-ts`.
  - Namespace exports are supported as opaque getters, and ambiguous re-exports no longer block scaffold generation; they are widened/omitted consistently with the low-level emitters and reported in `SCAFFOLD_DIAGNOSTICS.md`.
- [x] Add `just verify-scaffolds` and wire it into `just ci`.
  - Acceptance: `emit-typescript-scaffold-from-mbti` is compiled with `tsc`, and `emit-moonbit-scaffold-from-ts` is compiled/tested with `moon check/test --target js`.
- [x] Add external import rewrite mapping for `emit-typescript-scaffold-from-mbti`.
  - `emit-typescript-package-from-mbti` / `emit-typescript-scaffold-from-mbti` now accept an optional JSON rewrite map and apply it before writing external `.d.ts` imports.

### P1

- [x] Generate publish-ready metadata for `MoonBit -> TS` scaffold output.
  - `emit-typescript-scaffold-from-mbti` now writes `package.json` with `name`, `type`, `types`, and per-subpath `exports.types` entries alongside `moon.pkg.json` and `.d.ts` files.
- [x] Decide how to handle methods / static members omitted from `link.js.exports`.
  - The default scaffold still emits `AUTOLINK_DIAGNOSTICS.md` so omissions are explicit, and `emit-typescript-facade-scaffold-from-mbti` now provides an opt-in wrapper path for root-package local non-generic methods / constructors.

### P2

- [x] Minimize a stable real-world fixture from `neverthrow` if broader package-surface coverage is still needed.
  - `just verify-scaffolds` now exercises the stable `neverthrow-like` fixture end-to-end, including generated MoonBit scaffold compile/test under JS.

### P3

- [x] Revisit broader `namespace export` support after the scaffold path is stable.
  - `emit-moonbit-scaffold-from-ts` now accepts namespace exports and exposes them as opaque getter functions in the generated package. Ambiguous re-exports are emitted conservatively and surfaced in scaffold diagnostics instead of failing fast.

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

- [x] Re-verify the historical wasmtime mismatch regressions against the current codegen.
  - `src/codegen/codegen_wbtest.mbt` now passes end-to-end under the current wasmtime-backed runner, including the previously tracked `if-else`, `int factorial`, `js simple arithmetic`, `typed module with nested scopes`, `switch`, `switch default only`, and `do-while` cases.
  - The old hand-maintained mismatch list was stale and has been retired in favor of the executable regression suite.

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
