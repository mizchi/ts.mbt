// Bindings named after TypeScript's CONTEXTUAL keywords.
//
// The mangler's built-in reserved list is consulted for two different
// questions at once (`ScopeFrame::bind`): which names the generated pool
// may not produce, and which existing bindings may not be renamed. The
// list is for the first. Answering the second from it costs bytes for
// every binding a program happens to name after a keyword that is not
// actually reserved in JavaScript.
//
// `type`, `namespace`, `declare`, `abstract` and `readonly` are legal
// variable names, in strict mode too. typebox's bundle declares
// `function a6(type, a = {})` throughout — 824 occurrences of a
// four-character parameter name in a bundle whose length-3 names are not
// even exhausted, against terser's four. Dropping the five from the list
// is −2,440 bytes on typebox alone.
//
// The ones that stay are reserved in strict mode, and a module is
// strict: `interface`, `implements`, `private`, `protected`, `public`,
// `static`, plus `enum` and the unconditional reserved words.
//
// This case exists to make sure renaming them is actually safe: each is
// declared, read, closed over, shadowed, and exported, and the observed
// values must match Node running the original.

const type: string = "outer-type";
const namespace: string = "outer-namespace";
const declare: number = Number(process.argv.length);
const abstract: number = declare + 1;
const readonly: string = type + "/" + namespace;

// A parameter named after one, plus a shadowing local — the shape the
// mangler most easily gets wrong, since the outer binding and the inner
// one now compete for the same short name.
function withParam(type: string): string {
  const namespace = "inner-namespace";
  return type + "|" + namespace;
}

// A closure reading the outer bindings after the parameter shadowed one
// of them. If the rename captured, this returns the inner value.
function closesOverOuter(): () => string {
  const abstract = 99;
  return () => type + ":" + String(abstract);
}

// A nested function whose own parameter shadows an outer contextual name
// while the body also reads a genuinely reserved-word-adjacent one.
function nested(readonly: number): number {
  function inner(declare: number): number {
    return declare + readonly;
  }
  return inner(5);
}

// Object keys spelled the same way are PROPERTIES, not bindings; they
// must survive untouched whatever happens to the variables.
const shape = { type, namespace, declare, abstract, readonly };

// `let` so the single-use inliner cannot fold it away, and reassigned so
// it survives to the mangler as a real binding.
let statik = 1;
statik = statik + Number(process.argv.length) - 2;

export const report = {
  type,
  namespace,
  declare,
  abstract,
  readonly,
  withParam: withParam("arg-type"),
  closesOverOuter: closesOverOuter()(),
  nested: nested(7),
  shapeKeys: Object.keys(shape).join(","),
  shapeType: shape.type,
  statik,
};
