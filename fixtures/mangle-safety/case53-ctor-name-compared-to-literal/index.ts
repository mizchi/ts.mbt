// `x.constructor.name` compared against a string literal.
//
// The read names no class syntactically, so `observed_names.mbt` used to
// reserve EVERY callable in the bundle. On typebox that cost 24.9% —
// from a single site in 5,000 lines. When the value is only ever
// compared against a literal the observation is a boolean, and it can
// only change if the set of names reaching the site gains or loses one
// of the compared literals. So the literals are what needs reserving.
//
// Both directions are observed here, because reserving a literal has to
// do two jobs:
//
//   * a class ALREADY called that keeps its name (`Shape`)
//   * no class may be renamed TO it (`"a"`, which is exactly the name
//     the mangler hands out first)
//
// and the second is the one a naive implementation misses.

type Named = { constructor: { name: string } };

const named = (v: object): Named => v as unknown as Named;

const trace: string[] = [];
const tap = (s: string): string => {
  trace.push(s);
  return s;
};

class Shape {
  area(): number {
    return 4;
  }
}

class Widget {
  spin(): number {
    return 9;
  }
}

// Direction 1: the literal IS a bundle class name. Renaming `Shape`
// would make this false.
const isShape = (v: Named): boolean => v.constructor.name === "Shape";

// Direction 2: the literal is a name the mangler HANDS OUT. Renaming
// any class to it would make this true where the original is false.
//
// The whole one-character space is listed rather than a single letter on
// purpose. Which letter a given class gets depends on the reference
// counts of every binding in the bundle, so a fixture naming one letter
// stops detecting the moment the mangler's ordering shifts — silently,
// by passing. Covering the space makes the assertion independent of the
// assignment: with the reservation removed, SOME class takes SOME letter
// and this flips.
//
// It also prices the rule honestly. Reserving eight one-character names
// is expensive, and that is the cost of code that really does compare a
// constructor name against `"a"`. Real code compares against `"Object"`,
// which costs nothing at all.
const isManglerName = (v: Named): boolean =>
  v.constructor.name === "a" ||
  v.constructor.name === "b" ||
  v.constructor.name === "c" ||
  v.constructor.name === "d" ||
  v.constructor.name === "e" ||
  v.constructor.name === "f" ||
  v.constructor.name === "g" ||
  v.constructor.name === "h";

// Direction 3: a literal no bundle class is called. Nothing needs
// reserving, and this is the shape typebox actually has.
const isPlain = (v: Named): boolean =>
  v.constructor.name === "Object" || v.constructor.name === "Array";

// The typebox spelling: the comparison goes through a one-line helper
// rather than being written as `===`. `call_inline` is what turns it
// into a comparison, and it only does so because substituting an impure
// argument is exact when the body reads its parameters once, in order —
// see `params_read_in_argument_order`.
const isEq = (l: string, r: string): boolean => l === r;
const isShapeVia = (v: Named): boolean => isEq(v.constructor.name, "Shape");

const shape = new Shape();
const widget = new Widget();

export const shapeIsShape: boolean = isShape(named(shape));
export const widgetIsShape: boolean = isShape(named(widget));
export const shapeIsManglerName: boolean = isManglerName(named(shape));
export const widgetIsManglerName: boolean = isManglerName(named(widget));
export const objIsPlain: boolean = isPlain(named({ k: 1 }));
export const arrIsPlain: boolean = isPlain(named([1, 2]));
export const shapeIsPlain: boolean = isPlain(named(shape));
export const shapeViaHelper: boolean = isShapeVia(named(shape));
export const widgetViaHelper: boolean = isShapeVia(named(widget));

// The methods still have to work: the narrowing lets the mangler rename
// these classes' bindings, and a rename that broke dispatch would show
// up here rather than in the name comparisons.
export const areas: number = shape.area() + widget.spin();

// ---------------------------------------------------------------------
// Evaluation order, which is what buys the inlining above
// ---------------------------------------------------------------------

// Exact: parameters read once, in argument order, unconditionally. The
// arguments may be impure, and the trace proves the order survives.
export const eqOrder: string = String(isEq(tap("l1"), tap("r1"))) +
  "|" +
  trace.join(",");

// NOT exact — the body short-circuits, so the right argument might not
// run in the substituted form while the CALL always evaluates it. If
// this were inlined the trace would lose `r2`.
const orFn = (l: boolean, r: boolean): boolean => l || r;
export const shortCircuit: string = String(
  orFn(tap("l2") === "l2", tap("r2") === "r2"),
) +
  "|" +
  trace.join(",");

// NOT exact — the body reads its parameters in the wrong order, so
// substitution would swap two argument evaluations. If this were
// inlined the trace would read `r3,l3`.
const swapped = (l: string, r: string): string => r + l;
export const swapOrder: string = swapped(tap("l3"), tap("r3")) +
  "|" +
  trace.join(",");
