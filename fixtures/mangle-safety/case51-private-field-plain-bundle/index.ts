// A `#private` field is not an ordinary property: it is invisible to
// `JSON.stringify`, to `Object.keys`, to object spread and to `for…in`.
// mtsc represents it internally as `__private_brand__<N>__<member>`,
// which IS an ordinary own enumerable property, and
// `lower_private_fields` maps it back to `#member` before emit.
//
// That lowering ran only in the merged pipeline — gated on
// `--mangle` / `--treeshake` / `--fold` — so plain `mtsc --bundle`
// emitted the brand verbatim and every one of these observations was
// wrong. This case has no `mtscArgs`, which is the whole point: the
// baseline leg IS the plain path.

class Counter {
  #count = 0;
  #label: string;

  constructor(label: string) {
    this.#label = label;
  }

  inc(): number {
    this.#count += 1;
    return this.#count;
  }

  describe(): string {
    // A private read inside a template literal: the sub-parser used to
    // lose the enclosing class's brand here, which is a separate bug
    // with the same symptom.
    return `${this.#label}#${this.#count}`;
  }
}

// A SECOND class declaring the same private name. The parser numbers
// brands per module, so both are `__private_brand__0__count` after
// linking, and the lowering's guard used to refuse any brand mentioned
// by more than one top-level statement — which is what two classes
// declaring the same private name looks like. Each `#count` is scoped
// to its own class body, so renaming both is correct.
class Gauge {
  #count = 100;

  read(): number {
    return this.#count;
  }
}

const c = new Counter("c");
c.inc();
c.inc();
const g = new Gauge();

// The four ways a brand leaks that a real private field does not.
export const serialized = JSON.stringify(c);
export const ownKeys = Object.keys(c).join(",");
export const spread = JSON.stringify({ ...c });
export const enumerated = (() => {
  const seen: string[] = [];
  for (const k in c) {
    seen.push(k);
  }
  return seen.join(",");
})();

// And the values still work.
export const description = c.describe();
export const gauge = g.read();
