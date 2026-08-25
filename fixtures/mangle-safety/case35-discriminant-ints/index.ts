// Discriminant tags become integers when their values can't be observed.
// Each `tag*` below is held back by exactly one condition, and every one
// of them changes what the driver sees if renumbered anyway.
type Shape =
  | { kind: "circle"; r: number }
  | { kind: "square"; s: number };

function area(x: Shape): number {
  switch (x.kind) {
    case "circle":
      return x.r * x.r * 3;
    case "square":
      return x.s * x.s;
    default:
      return 0;
  }
}

const shapes: Shape[] = [
  { kind: "circle", r: 2 },
  { kind: "square", s: 3 },
];

// Serialized — the value leaves as JSON text.
const ser = { tagA: "alpha" };
// The value is returned out of an exported function; the NAME never
// escapes, only the value.
const ret = { tagB: "beta" };
export function readB(): string {
  return ret.tagB;
}
// Interpolated into a string.
const tpl = { tagC: "gamma" };
// Truthiness: "delta" is truthy, 0 is not.
const truthy = { tagD: "delta" };
// Compared against a literal nobody writes, so the test is always false.
const odd = { tagF: "zeta" };

export const report = {
  areas: area(shapes[0]) + area(shapes[1]),
  round: shapes[0].kind === "circle" ? 1 : 0,
  serialized: JSON.stringify(ser),
  fromB: readB(),
  interpolated: `${tpl.tagC}`,
  truthy: truthy.tagD ? 1 : 0,
  odd: odd.tagF === "nobody-writes-this" ? 1 : 0,
};
