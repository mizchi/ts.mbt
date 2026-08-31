// `tag-rewrite` replaces a discriminated union's string tags with small
// integers. It is sound only while the union is entirely internal: the
// pass rewrites the property's VALUE, and a consumer holding the value
// compares it against the string it was written as.
//
// Both directions of the boundary are here. The pass's own escape-sink
// scan can see neither: the consumer's comparison happens outside the
// bundle, and so does the consumer's construction of the value.
//
// Every observation below is an exported OBJECT rather than a tag read
// back inside the bundle. That distinction is the whole detection power
// of this case: an internal `unitCircle.kind === "circle"` is rewritten
// to `=== 0` alongside the literal and stays true, so it would agree
// with the reference leg while the exported object visibly did not.

export type Shape =
  | { kind: "circle"; r: number }
  | { kind: "square"; side: number };

// 1. An exported VALUE carrying a tag. A consumer reads `.kind` off it.
export const unitCircle: Shape = { kind: "circle", r: 1 };

// 2. An exported SIGNATURE over the same union — the mirrored hazard.
//    Here the CONSUMER builds `{ kind: "circle" }` and the bundle is the
//    side comparing it, so renumbering breaks the comparison from the
//    other end.
export function area(s: Shape): number {
  switch (s.kind) {
    case "circle":
      return 3 * s.r * s.r;
    case "square":
      return s.side * s.side;
  }
}

// 3. An exported function whose RETURN carries a tag, with no named type
//    in its signature at all — only the value walk can see this one.
export const makeSquare = () => ({ kind: "square" as const, side: 2 });

// 4. The exported objects, so the observation is the tag itself and not
//    a comparison the bundle performs on its own terms.
export const built = makeSquare();
export const areaOfUnit = area(unitCircle);
