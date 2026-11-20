// @strict: true
// @target: esnext

// A generic static factory called through its class returns an instance of
// the class, whatever type arguments it is called with, so assigning its
// result narrows a nullable binding. That holds when the factory builds the
// instance from `const` locals first, which is excalidraw's `Delta.create`.
// A factory that returns its own bare type parameter can return whatever the
// argument is, `null` included, so it narrows nothing.

class Delta<T> {
  private constructor(public readonly deleted: Partial<T>) {}
  static create<T>(d: Partial<T>) { return new Delta(d); }
  static viaLocal<T>(d: Partial<T>, m?: (x: Partial<T>) => Partial<T>) {
    const md = m ? m(d) : d;
    return new Delta(md);
  }
  static pick<T>(x: T) { return x; }
}
type EP = { a: number };

export function okExplicitTypeArgument(c: boolean, d: Delta<EP>) { let l: Delta<EP> | null = null; if (c) { l = Delta.create<EP>({}); } else { l = d; } return l.deleted; }
export function okInferredTypeArgument(d: Delta<EP>) { let l: Delta<EP> | null = null; l = Delta.create(d.deleted); return l.deleted; }
export function okBuiltFromLocals(c: boolean, d: Delta<EP>) { let l: Delta<EP> | null = null; if (c) { l = Delta.viaLocal(d.deleted); } else { l = d; } return l.deleted; }
export function badBareTypeParameter(c: boolean, n: string | null) { let v: string | null = null; if (c) { v = Delta.pick(n); } else { v = "x"; } return v.length; }
