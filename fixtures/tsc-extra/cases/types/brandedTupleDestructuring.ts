// @strict: true
// @target: esnext

// Destructuring a branded tuple (`[x: number, y: number] & { _brand }`, how
// geometry libraries brand points) binds the tuple's elements, through a
// type parameter constrained to a union of brands and in a `for…of` head.

type P2 = [x: number, y: number] & { _brand: "g" };
type P3 = [x: number, y: number] & { _brand: "l" };

function okBranded(p: P2): number { const [x, y] = p; return x - y; }
function okConstrainedToUnion<Q extends P2 | P3>(p: Q): number { const [x, y] = p; return x - y; }
function okForOf(ps: readonly P2[]): number { let c = 0; for (const [x, y] of ps) { c += x + y; } return c; }
function badElementType(p: P2): string { const [x] = p; return x; }
