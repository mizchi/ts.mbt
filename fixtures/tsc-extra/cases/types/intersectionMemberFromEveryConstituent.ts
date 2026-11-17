// @strict: true
// @target: esnext

// A member several constituents of an intersection declare has the
// intersection of their types: `Base & { type: "line" }` reads `type` as
// `"line"`, not the base's `string`, so it discriminates a union of such
// intersections. A constituent that declares the member outranks one that
// answers through an index signature: beside an open `Record`, an optional
// `label?: string` is `string | undefined`, not the record's `number`.

interface Base { id: string; type: string }
type Line = Base & { type: "line"; points: number[] };
type Rect = Base & { type: "rectangle"; w: number };
type El = Line | Rect;
declare const rec: Record<string, number> & { label?: string };

function okLiteralFromSecondConstituent(e: Line): "line" { return e.type; }
function okSwitchDiscriminates(e: El): number {
  switch (e.type) {
    case "line": return e.points.length;
    case "rectangle": return e.w;
  }
  return 0;
}
function okDeclaredMemberOverIndexSignature() { const l: string | undefined = rec.label; const n: number = rec.other; }
function badDeclaredMemberNotTheRecordValue() { const n: number = rec.label; }
function badOtherLiteral(e: Line): "rectangle" { return e.type; }
function badMemberOfOtherBranch(e: El): number { if (e.type === "line") { return e.w; } return 0; }
