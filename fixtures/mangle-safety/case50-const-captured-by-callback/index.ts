// The closure guard in `numeric_vars` / `container_vars` refused to
// promote any binding a nested function referenced, because "a closure
// could write anything into it". No frame may write a `const`, so the
// premise does not hold there — and until it was exempted,
// `arr.map((v, i) => arr[i])` left BOTH `arr` unprovable as a container
// and `i` unprovable as numeric, which turned class-method DCE off for
// the whole bundle.
//
// This case is about what still runs after the pass is allowed to
// delete. Every method named below has to survive, and the arithmetic
// has to match the original TypeScript.

const sizes = [2, 3, 4];

class Shape {
  constructor(readonly side: number) {}

  // Called through the callback below, so it must survive.
  area(): number {
    return this.side * this.side;
  }

  // Called only through a computed key whose value the bundle cannot
  // know, so it must survive too.
  perimeter(): number {
    return this.side * 4;
  }

  // Reached through the protocol, not by name.
  toJSON(): { s: number } {
    return { s: this.side };
  }
}

// `sizes` is captured here, and so is the index parameter. Both are the
// bindings the closure guard used to refuse.
const areas = sizes.map((_, index) => new Shape(sizes[index]).area());

// A computed key the bundle cannot fold: keep every method reachable
// this way.
const which: string = areas.length > 0 ? "perimeter" : "area";
const dynamic = (new Shape(5) as unknown as Record<string, () => number>)[
  which
]();

// The iteration protocol and JSON both read names nothing spells out.
const serialized = JSON.stringify(new Shape(7));

export const areaList = areas;
export const dynamicResult = dynamic;
export const json = serialized;
export const total = areas.reduce((a, b) => a + b, 0);
