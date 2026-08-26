# Findings from `just fuzz-mangle`

Open:

- **A nested class's reference to an outer private reads `undefined`.**
  The parser brands a `#x` reference with the class whose BODY encloses
  it; JS resolves `#x` to the nearest enclosing class that DECLARES it.
  So in
  `class Foo { #name = 7; m() { const B = class { g(o) { return o.#name } } } }`
  the reference carries B's brand and the field Foo's, and the read comes
  back `undefined`.

  The obvious fix — remap the reference to the field's spelling when the
  two share a top-level statement — was implemented, measured, and
  backed out, because it breaks the program one letter away from it:

  ```ts
  class Foo { #x = 1; m() { const B = class { #x = 2; g() { return this.#x } } } }
  ```

  Here `B` DECLARES its own `#x`, shadowing Foo's, and the program is
  correct as written. The two are indistinguishable from the property
  NAMES that `lower_private_fields` works with — same statement, same
  member, one brand declarable and one not, in both — so any gate built
  out of those name sets remaps both or neither. Remapping both merges
  B's field into Foo's, and since the IIFE lift has by then turned `B`
  into a plain `function`, `this.#x = 2` binds to Foo's declaration with a
  non-Foo `this`: *Cannot write private member #x to an object whose
  class did not declare it*. Trading a wrong value for a crash in a
  case of comparable frequency is the wrong trade, so the brand stays.

  Telling the two apart needs to know which class DECLARES the member,
  which means reaching a nested class's own declaration list — and a
  walker that misses a node shape fails toward the crash, not toward the
  wrong value. The fix belongs in the parser, where the scope chain
  already exists (`self.current_class_brand` in
  `src/parser/parser_expr.mbt`): brand a `#x` reference with the nearest
  enclosing class that declares `#x` rather than with the innermost one.
  That needs each class's member set complete before its method bodies
  are branded, i.e. a second pass over the class subtree once its body
  closes. Regression cases for both halves are in
  `src/transform/private_fields_wbtest.mbt`.

Fixed since, and kept here because the reasoning is the record:

- **`private-field-lowered-enumerable.ts`** — `#secret` was lowered to
  `__private_brand__N__secret`, an ordinary own enumerable property, so
  `JSON.stringify` / `Object.keys` / `for...in` / spread all saw it where
  a real private field is invisible. It was the fuzzer's largest family
  (62 of 63 mismatches on a 150-seed campaign). Fixed by
  `src/transform/private_fields.mbt`, which renames the brand to `#x`
  once it can prove a declaration will be emitted for it.
  Regression cases: `src/transform/private_fields_wbtest.mbt`.

  Three shapes deliberately keep the brand, because a `#x` with no
  declaration in scope is a SyntaxError rather than a wrong value: a
  typed field with no initializer, a class the IIFE lift declined, and a
  brand referenced from outside every class node — mtsc lowers an
  accessor to
  `Object.defineProperty(C.prototype, …, { get() { return this.#x } })`
  beside the class, and hono's `Context` does exactly that.

- **`static #x` dropped outright.** The class lowering discarded a
  `static #x = init` initializer and all, so `C.#x` read `undefined`
  where Node reads the value. Two causes: `iife_class_lift` claimed the
  `__private_brand__` prefix as class metadata and deleted the entry,
  and `rename_properties_in_class_decl` never visited
  `static_field_inits` keys, so once the entry survived, the declaration
  kept the brand while the read became `C.#x` — a SyntaxError instead of
  a wrong value. `static #x = init;` in a class body declares the member
  itself, so the brand can now be renamed like any other.

- **`prop-write-into-observed-object.ts`** — `obj['q'] = { ...bag }` with
  `obj` reaching a sink. There was no flow edge from a written value into
  the target's binding at all, so an observed object kept its own keys
  and lost everything written into it. Fixed by `sg_record_write_into`
  (the edge) plus `Symbol::written_values` / `collect_literal_keys` (the
  keys a written literal introduces, which name nothing else in the
  bundle). Regression case: `fixtures/mangle-safety/case39-write-into-observed`.

An open finding that the fuzzer can still reach keeps a `.ts` file in
this directory — the smallest program that still fails, as
`scripts/lib/fuzz-shrink.mjs` reduced it. The file is what makes the
finding reproducible once the seed that found it drifts: the generator
changes and seeds do not survive it. There are none right now; the open
finding above needs a class nested in a method, which the generator does
not yet produce, so its cases live as unit tests instead.

Reproduce one with:

```sh
mtsc <file> --bundle --treeshake --fold --minify --no-check --out /tmp/base.mjs
mtsc <file> --bundle --treeshake --fold --minify --no-check \
    --mangle --mangle-properties --reserve-entry-exports --out /tmp/mangled.mjs
node <file>; node /tmp/base.mjs; node /tmp/mangled.mjs
```
