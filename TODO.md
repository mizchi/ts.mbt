## test262 status (2026-01-27)

- Allowlist run does not complete yet because some `Array.prototype.map` tests hang.
  - Example: `test262/test/built-ins/Array/prototype/map/15.4.4.19-8-4.js` did not finish in a single-file run.
- Last completed subset runs:
  - `test262.arrow.run.log`: total=343, passed=160, failed=49, skipped=134.
  - `test262.compound.run.log`: total=454, passed=241, failed=127, skipped=86.

## Priority backlog (ordered)

1. Add per-test step limit or timeout in the interpreter so the allowlist run always finishes.
2. Fix `Array.prototype.map` semantics (ToObject, thisArg, callback calling, holes, length tracking) and remove infinite loops.
3. Ensure the `JSON` global exists and implement minimal `JSON.parse`/`JSON.stringify`.
4. Implement `Function.prototype.call`/`apply`/`bind` and correct `this` binding (method calls + constructors).
5. Implement minimal `RegExp` behavior (constructor, `.test`, `.exec`) using `moonbitlang/regexp`.
6. Fill out String/Array built-ins used by the TypeScript compiler (indexOf, slice, substring, join, push/pop, etc.).
7. Expand test262 harness includes (propertyHelper.js, isConstructor.js, and friends) to reduce SKIPs.
8. Parser coverage for remaining syntax as needed: `??`, `?.`, class, modules, generators, async/await.
9. AnnexB Date `getYear`/`setYear` and other low-priority built-ins only if TS needs them.
