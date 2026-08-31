// A class method whose parameter is a destructuring pattern.
//
// `TsClassMethodDecl.params` is `Array[(String, TsType)]` — a name and a
// type, with no slot for a binding pattern — so the class lift collapsed
// the pattern to the FIRST name it bound and dropped the rest:
//
//   flat({ a, b })      became  flat(a)   -> ReferenceError on `b`
//   nested({ a: { b } }) became nested(b) -> returns the argument object
//
// The second form is the dangerous one: it throws nothing and returns a
// wrong value. Every class method with a destructured parameter was
// affected, under plain `--bundle` with no optimization flag, and
// neither this corpus nor 2800 unit tests had one.
//
// Found by `mtsc --verify` on Excalidraw's
// `StoreDelta.load({ id, elements: { added, removed, updated }, … })`,
// which reported `added` / `removed` / `updated` as free variables.
//
// The keys below are read by the CALLER building the argument, so they
// are also ABI — a property mangler must not rename them.

type Pair = { left: number; right: number };
type Wrapped = { inner: { deep: number } };

export class Compute {
  flat({ left, right }: Pair) {
    return left + right;
  }

  nested({ inner: { deep } }: Wrapped) {
    return deep;
  }

  renamed({ left: aliased }: Pair) {
    return aliased * 2;
  }

  mixed(head: number, { right }: Pair) {
    return head + right;
  }

  withDefault({ left }: Pair = { left: 5, right: 0 }) {
    return left;
  }

  arrayPattern([first, second]: number[]) {
    return first - second;
  }

  restInPattern({ left, ...others }: Pair & { extra: number }) {
    return left + Object.keys(others).length;
  }

  // Echoes the destructured names back out, so the corpus's mutation
  // self-check can see them: a key that never reaches stdout cannot
  // witness a rename, and the harness rejects an `expectKeep` entry it
  // cannot test.
  echo({ left, right, inner: { deep }, extra }: Pair & Wrapped & { extra: number }) {
    return { left, right, deep, extra };
  }

  static staticFlat({ left, right }: Pair) {
    return left * right;
  }
}

const c = new Compute();
export const report = {
  flat: c.flat({ left: 1, right: 2 }),
  nested: c.nested({ inner: { deep: 7 } }),
  renamed: c.renamed({ left: 3, right: 0 }),
  mixed: c.mixed(10, { left: 0, right: 5 }),
  withDefault: c.withDefault(),
  withDefaultGiven: c.withDefault({ left: 9, right: 0 }),
  arrayPattern: c.arrayPattern([9, 4]),
  restInPattern: c.restInPattern({ left: 1, right: 2, extra: 3 }),
  staticFlat: Compute.staticFlat({ left: 3, right: 4 }),
  echo: c.echo({ left: 1, right: 2, inner: { deep: 3 }, extra: 4 }),
  // Arity has to be preserved: a pattern parameter counts as one.
  arity: [c.flat.length, c.mixed.length, c.withDefault.length],
};
console.log(JSON.stringify(report));
