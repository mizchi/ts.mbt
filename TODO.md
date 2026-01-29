## test262 status (2026-01-27)

- Allowlist run does not complete yet because some `Array.prototype.map` tests hang.
  - Example: `test262/test/built-ins/Array/prototype/map/15.4.4.19-8-4.js` did not finish in a single-file run.
- Last completed subset runs:
  - `test262.arrow.run.log`: total=343, passed=160, failed=49, skipped=134.
  - `test262.compound.run.log`: total=454, passed=241, failed=127, skipped=86.

## test262 gaps from allowlist run (test262.run.log)

- Biggest failing areas by path:
  - `language/statements/for-of` (iterator protocol + destructuring)
  - `language/statements/for` (destructuring in init/update, scoping)
  - `staging/sm/Iterator` (Iterator constructor + helpers)
  - `language/statements/{let,const,variable}` (binding/TDZ and destructuring)
  - `language/expressions/{function,arrow-function}` (destructuring + defaults)
  - `language/expressions/call`, `language/expressions/new` (call/construct semantics)
  - `language/expressions/array` (elision + spread semantics)
  - `annexB/built-ins/RegExp` (legacy flags/props)
  - `annexB/built-ins/String` (legacy methods)

## Priority backlog (updated)

1. Implement iterator protocol properly:
   - `Iterator` global, `Iterator.prototype`, `%IteratorPrototype%`
   - `@@iterator` on Array/String/Map/Set basics (as required by tests)
   - IteratorClose / abrupt completion handling.
2. Fix `for-of` semantics:
   - Iterator acquisition, per-iteration binding, destructuring assignment.
   - IteratorClose on `break`, `throw`, and errors in destructuring.
3. Destructuring binding semantics for `let/const/var` and parameters:
   - Array/object patterns, elisions, defaults, rest, computed keys.
   - Correct timing of default evaluation and binding initialization.
4. TDZ and lexical environment correctness:
   - `let/const` block scoping, temporal dead zone, redeclaration rules.
5. Function/arrow parameter initialization:
   - Default parameter evaluation order.
   - Destructuring in parameters with iterator errors.
6. Call/construct semantics:
   - `new` target handling, `this` binding, callable checks.
7. Array literal semantics:
   - Elision (`[,,]`) and spread (`[...iter]`) interaction.
8. AnnexB legacy RegExp/String behaviors needed by allowlist.

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

## Statements coverage gaps (parser/runtime)

- `import/export` are parsed but not executed/linked (module semantics missing).
- Labeled statements implemented; validate semantics against test262.
- `for await...of` is unsupported (no `await` keyword).

## Statements implementation order (suggested)

1. Decide `import/export` approach (skip or minimal parser stubs).
