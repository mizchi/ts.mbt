// Excalidraw's element package, consumed the way a drawing surface
// consumes it: build a scene, ask the predicates about it, compute its
// geometry, filter it for display.
//
// Unlike the other app entries this one has no README quickstart to copy
// — `packages/element` is an internal workspace package with no usage
// documentation — so the usage is lifted from `excalidraw.driver.mjs`,
// which was itself written against the package's own tests. The
// difference that matters for THIS harness is that every call here is
// statically named. The driver reaches its predicates through
// `El[name]`, which is the one shape that defeats tree-shaking and
// property mangling by construction; an application writes the call.
//
// Every export is a scalar or a string built from scalars, and the
// `seed` / `versionNonce` / `id` fields are pinned or dropped for the
// reason `excalidraw.driver.mjs` gives: they come from a PRNG seeded
// with `Date.now()`, and a value that moves between runs cannot witness
// a mangling bug — only produce a false BROKEN.

import {
  canChangeRoundness,
  canHaveArrowheads,
  getBoundsFromPoints,
  getCommonBounds,
  getCornerRadius,
  getElementAbsoluteCoords,
  getElementBounds,
  getNonDeletedElements,
  getNormalizedDimensions,
  getPerfectElementSize,
  getVisibleElements,
  hasBackground,
  hasStrokeStyle,
  hasStrokeWidth,
  isArrowElement,
  isBindableElement,
  isFrameElement,
  isFreeDrawElement,
  isInvisiblySmallElement,
  isLinearElement,
  isPathALoop,
  isRectangularElement,
  isTextElement,
  newArrowElement,
  newElement,
  newFrameElement,
  newFreeDrawElement,
  newLinearElement,
  pointInsideBounds,
} from "./packages/element/src/index.ts";

type Base = {
  x: number;
  y: number;
  strokeColor: string;
  backgroundColor: string;
  fillStyle: string;
  strokeWidth: number;
  strokeStyle: string;
  roundness: { type: number } | null;
  roughness: number;
  opacity: number;
  width: number;
  height: number;
  angle: number;
};

const base: Base = {
  x: 10,
  y: 20,
  strokeColor: "#1e1e1e",
  backgroundColor: "transparent",
  fillStyle: "solid",
  strokeWidth: 2,
  strokeStyle: "solid",
  roundness: null,
  roughness: 1,
  opacity: 100,
  width: 100,
  height: 50,
  angle: 0,
};

// Pin the two PRNG-drawn fields, as the package-entry driver does.
function seeded<T>(e: T, n: number): T {
  return { ...(e as object), seed: 1000 + n, versionNonce: 2000 + n } as T;
}

const rect = seeded(newElement({ type: "rectangle", ...base } as never), 1);
const ellipse = seeded(
  newElement({ type: "ellipse", ...base, x: 200, width: 60, height: 60 } as never),
  2,
);
const diamond = seeded(
  newElement({ type: "diamond", ...base, x: 400, y: 0 } as never),
  3,
);
const arrow = seeded(
  newArrowElement({
    type: "arrow",
    ...base,
    x: 0,
    y: 0,
    elbowed: false,
    points: [[0, 0], [50, 10], [80, 60]],
  } as never),
  4,
);
const line = seeded(
  newLinearElement({
    type: "line",
    ...base,
    x: 5,
    y: 5,
    points: [[0, 0], [30, 0], [30, 30], [0, 30], [0, 0]],
  } as never),
  5,
);
const freedraw = seeded(
  newFreeDrawElement({
    type: "freedraw",
    ...base,
    x: 0,
    y: 0,
    points: [[0, 0], [3, 4], [10, 2], [20, 25]],
    simulatePressure: true,
  } as never),
  6,
);
const frame = seeded(
  newFrameElement({ x: -50, y: -50, width: 600, height: 400 } as never),
  7,
);
const rounded = seeded(
  newElement({ type: "rectangle", ...base, roundness: { type: 3 } } as never),
  8,
);
const tiny = seeded(
  newElement({ type: "rectangle", ...base, width: 0, height: 0 } as never),
  9,
);
const stub = seeded(
  newArrowElement({
    type: "arrow",
    ...base,
    elbowed: false,
    points: [[0, 0]],
  } as never),
  10,
);
const deleted = {
  ...seeded(newElement({ type: "ellipse", ...base } as never), 11),
  isDeleted: true,
};

const elements = [rect, ellipse, diamond, arrow, line, freedraw, frame];
const elementsMap = new Map(
  [...elements, rounded].map((e) => [(e as { id: string }).id, e]),
);

const round = (v: number): number => Math.round(v * 1000) / 1000;
const bits = (flags: boolean[]): string => flags.map((f) => (f ? 1 : 0)).join("");

export const constructed: string = elements
  .map((e) => {
    const el = e as {
      type: string;
      x: number;
      y: number;
      width: number;
      height: number;
      points?: unknown[];
    };
    return el.type + "@" + el.x + "," + el.y + " " + el.width + "x" + el.height +
      (el.points ? "/" + el.points.length : "");
  })
  .join(" | ");

// The predicate surface over the discriminated union — the shape
// `predicate-inline` and `tag-rewrite` exist to consume — reached by
// name rather than through a table.
const subjects = [...elements, rounded];
export const predicates: string = [
  ["isArrowElement", subjects.map(isArrowElement)],
  ["isBindableElement", subjects.map(isBindableElement)],
  ["isFrameElement", subjects.map(isFrameElement)],
  ["isFreeDrawElement", subjects.map(isFreeDrawElement)],
  ["isLinearElement", subjects.map(isLinearElement)],
  ["isRectangularElement", subjects.map(isRectangularElement)],
  ["isTextElement", subjects.map(isTextElement)],
]
  .map(([name, flags]) => name + ":" + bits(flags as boolean[]))
  .join(" ");

const TAGS = [
  "rectangle",
  "ellipse",
  "diamond",
  "arrow",
  "line",
  "freedraw",
  "frame",
  "text",
  "image",
  "selection",
];
export const tagPredicates: string = [
  ["canChangeRoundness", TAGS.map((t) => canChangeRoundness(t as never))],
  ["canHaveArrowheads", TAGS.map((t) => canHaveArrowheads(t as never))],
  ["hasBackground", TAGS.map((t) => hasBackground(t as never))],
  ["hasStrokeStyle", TAGS.map((t) => hasStrokeStyle(t as never))],
  ["hasStrokeWidth", TAGS.map((t) => hasStrokeWidth(t as never))],
]
  .map(([name, flags]) => name + ":" + bits(flags as boolean[]))
  .join(" ");

export const absoluteCoords: string = elements
  .map((e) =>
    getElementAbsoluteCoords(e as never, elementsMap as never).map(round).join(",")
  )
  .join(" | ");
export const commonBounds: string = getCommonBounds(elements as never)
  .map(round)
  .join(",");
export const elementBounds: string = elements
  .map((e) => getElementBounds(e as never, elementsMap as never).map(round).join(","))
  .join(" | ");
export const pointBounds: string = getBoundsFromPoints(
  (freedraw as { points: never }).points,
).map(round).join(",");
export const loops: string = bits([
  isPathALoop((line as { points: never }).points),
  isPathALoop((arrow as { points: never }).points),
]);
export const perfect: string = [
  getPerfectElementSize("rectangle" as never, 100, 40),
  getPerfectElementSize("line" as never, 100, 40),
  getPerfectElementSize("arrow" as never, 12, 100),
]
  .map((r) => round(r.width) + "x" + round(r.height))
  .join(" ");
export const normalized: string = (() => {
  const n = getNormalizedDimensions({ ...rect, width: -30, height: -40 } as never);
  return n.x + "," + n.y + " " + n.width + "x" + n.height;
})();
export const radii: string = [0, 10, 40, 400]
  .map((s) => round(getCornerRadius(s, rect as never)) + "/" +
    round(getCornerRadius(s, rounded as never)))
  .join(" ");
export const inside: string = bits([
  pointInsideBounds([50, 30] as never, [0, 0, 100, 100] as never),
  pointInsideBounds([500, 30] as never, [0, 0, 100, 100] as never),
]);
export const invisiblySmall: string = bits([
  isInvisiblySmallElement(tiny as never),
  isInvisiblySmallElement(stub as never),
  isInvisiblySmallElement(rect as never),
  isInvisiblySmallElement(arrow as never),
]);
export const visibleCount: number = getVisibleElements(
  [...elements, tiny, stub, deleted] as never,
).length;
export const nonDeletedCount: number = getNonDeletedElements(
  [...elements, deleted] as never,
).length;
