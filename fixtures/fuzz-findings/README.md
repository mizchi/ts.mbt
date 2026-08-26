# Findings from `just fuzz-mangle` that are not fixed yet

Fixed and removed from this list:

- **`private-field-lowered-enumerable.ts`** — `#secret` was lowered to
  `__private_brand__N__secret`, an ordinary own enumerable property, so
  `JSON.stringify` / `Object.keys` / `for...in` / spread all saw it where
  a real private field is invisible. It was the fuzzer's largest family
  (62 of 63 mismatches on a 150-seed campaign). Fixed by
  `src/transform/private_fields.mbt`, which renames the brand to `#x`
  once it can prove a declaration will be emitted for it.
  Regression cases: `src/transform/private_fields_wbtest.mbt`.

  Four shapes deliberately keep the brand, because a `#x` with no
  declaration in scope is a SyntaxError rather than a wrong value:
  `static #x` (the class lowering drops it outright, so `C.#x` already
  reads `undefined`), a typed field with no initializer, a class the
  IIFE lift declined, and a class nested inside a method. A fifth is a
  brand referenced from outside its class node — mtsc lowers an accessor
  to `Object.defineProperty(C.prototype, …, { get() { return this.#x } })`
  beside the class, and hono's `Context` does exactly that.

- **`prop-write-into-observed-object.ts`** — `obj['q'] = { ...bag }` with
  `obj` reaching a sink. There was no flow edge from a written value into
  the target's binding at all, so an observed object kept its own keys
  and lost everything written into it. Fixed by `sg_record_write_into`
  (the edge) plus `Symbol::written_values` / `collect_literal_keys` (the
  keys a written literal introduces, which name nothing else in the
  bundle). Regression case: `fixtures/mangle-safety/case39-write-into-observed`.

Each file is the smallest program the fuzzer could still fail on, as
`scripts/lib/fuzz-shrink.mjs` reduced it. They are kept here so an open
finding stays reproducible after the seed that found it drifts — the
generator changes, seeds do not survive it.

Reproduce one with:

```sh
mtsc <file> --bundle --treeshake --fold --minify --no-check --out /tmp/base.mjs
mtsc <file> --bundle --treeshake --fold --minify --no-check \
    --mangle --mangle-properties --reserve-entry-exports --out /tmp/mangled.mjs
node <file>; node /tmp/base.mjs; node /tmp/mangled.mjs
```
