// @strict: true
// @target: esnext

// Narrowing and assignability shapes that real code (effect, univer,
// excalidraw) writes and that a checker must not reject: `"k" in x` on an
// interface, a union source whose members each assign, an assertion over a
// condition, a union of unions destructured by a nested conditional, and
// the `default` of a switch that covers every variant of a union (`never`)
// beside one over a non-union receiver (not narrowed).

interface Constraint { readonly ast: string }
export function okInOnInterface(schema: Constraint) {
  if ("members" in schema && Array.isArray(schema.members)) {
    return schema.members.length;
  }
  return 0;
}
export function badInOnInterfaceStillChecksTheRest(schema: Constraint) {
  if ("members" in schema) {
    return schema.nope;
  }
  return 0;
}

interface PO { readonly errors?: "first" | "all" | undefined }
declare const y1: { errors: "first" } | PO;
declare const y2: { errors: "nope" } | PO;
export const okUnionSourceEachMemberAssigns: PO = y1;
export const badUnionSourceOneMemberDoesNot: PO = y2;

declare function invariant(c: any, m: string): asserts c;
export function okAssertOverCondition(q: string | undefined) {
  invariant(q != null, "x");
  const s: string = q;
  return s;
}
export function badAssertOverWeakCondition(q: string | undefined) {
  invariant(q !== undefined || true, "x");
  const s: string = q;
  return s;
}

type LP = [x: number, y: number] & { _brand: "lp" };
export function okNestedConditionalDestructures(points: readonly LP[], end: boolean) {
  const [px, py] = points.length > 1 ? (end ? points[2] : points[1]) : [0, 0];
  return 1 - py - px;
}

type A = { kind: "abc" } | { kind: "def" };
export function okExhaustiveDefaultIsNever(a: A) {
  switch (a.kind) {
    case "abc": return 1;
    case "def": return 2;
    default: { const n: number = a; return n; }
  }
}
export function badExhaustiveDefaultMember(a: A) {
  switch (a.kind) {
    case "abc":
    case "def": return;
    default: return a.kind;
  }
}
type Enc = { encoded: string; encoding: "bstring" };
export function okNonUnionIsNotNarrowed(data: Enc): string {
  switch (data.encoding) {
    case "bstring": return data.encoded;
    default: throw new Error(`unknown ${data.encoding}`);
  }
}
