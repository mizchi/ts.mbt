// Excalidraw's element package: the corpus's only UI application.
//
// What makes it worth measuring is the shape of its data model.
// `ExcalidrawElement` is a discriminated union over `type` ("rectangle"
// | "ellipse" | "arrow" | "freedraw" | "frame" | …) and `typeChecks.ts`
// plus `comparisons.ts` are sixty-odd predicates over it — exactly the
// input `predicate-inline` and `tag-rewrite` are built to consume, at a
// scale no fixture reaches.
//
// Two things about what is printed:
//
// Nothing prints an element wholesale. `id` is a nanoid and `seed` /
// `versionNonce` come from a PRNG seeded with `Date.now()`, and roughjs
// feeds `seed` into the sketchy-path generator, so even a line's
// computed BOUNDS move from run to run. Every element gets a pinned seed
// below and `shape()` names the fields that are a function of the input:
// a value that is not reproducible cannot witness a mangling bug.
//
// Class identity is asserted with `instanceof`, never `constructor.name`
// — see the note at `errorIdentity`.
//
// The bundle reads `import.meta.env.MODE` / `.DEV` / `.PROD`, which vite
// substitutes at build time and Node leaves `undefined`. The harness
// rewrites those reads to the global below (see `execReplace` in
// `scripts/measure_type_aware.mjs`), so it has to be set before the
// bundle is evaluated — hence the dynamic import.
globalThis.__EXCALIDRAW_ENV__ = { MODE: "production", DEV: false, PROD: true };

const El = await import("./target.mjs");

const out = [];
const p = (label, value) => out.push(`${label}: ${JSON.stringify(value)}`);
const seeded = (e, n) => ({ ...e, seed: 1000 + n, versionNonce: 2000 + n });

// ---------------------------------------------------------------------
// Construction
// ---------------------------------------------------------------------

const base = {
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

const rect = seeded(El.newElement({ type: "rectangle", ...base }), 1);
const ellipse = seeded(
  El.newElement({ type: "ellipse", ...base, x: 200, width: 60, height: 60 }),
  2,
);
const diamond = seeded(El.newElement({ type: "diamond", ...base, x: 400, y: 0 }), 3);
const arrow = seeded(
  El.newArrowElement({
    type: "arrow",
    ...base,
    x: 0,
    y: 0,
    elbowed: false,
    points: [
      [0, 0],
      [50, 10],
      [80, 60],
    ],
  }),
  4,
);
const line = seeded(
  El.newLinearElement({
    type: "line",
    ...base,
    x: 5,
    y: 5,
    points: [
      [0, 0],
      [30, 0],
      [30, 30],
      [0, 30],
      [0, 0],
    ],
  }),
  5,
);
const freedraw = seeded(
  El.newFreeDrawElement({
    type: "freedraw",
    ...base,
    x: 0,
    y: 0,
    points: [
      [0, 0],
      [3, 4],
      [10, 2],
      [20, 25],
    ],
    simulatePressure: true,
  }),
  6,
);
const frame = seeded(El.newFrameElement({ x: -50, y: -50, width: 600, height: 400 }), 7);
const rounded = seeded(
  El.newElement({ type: "rectangle", ...base, roundness: { type: 3 } }),
  8,
);
// Two elements the visibility filters are supposed to drop.
const tiny = seeded(El.newElement({ type: "rectangle", ...base, width: 0, height: 0 }), 9);
const stub = seeded(
  El.newArrowElement({ type: "arrow", ...base, elbowed: false, points: [[0, 0]] }),
  10,
);
const deleted = {
  ...seeded(El.newElement({ type: "ellipse", ...base }), 11),
  isDeleted: true,
};

const elements = [rect, ellipse, diamond, arrow, line, freedraw, frame];
const elementsMap = new Map([...elements, rounded].map((e) => [e.id, e]));

// The fields that are a function of the constructor's input.
const shape = (e) => ({
  type: e.type,
  x: e.x,
  y: e.y,
  w: e.width,
  h: e.height,
  angle: e.angle,
  stroke: e.strokeColor,
  fill: e.fillStyle,
  points: e.points ? e.points.length : null,
  locked: e.locked,
  deleted: e.isDeleted,
});
p("constructed", elements.map(shape));

// ---------------------------------------------------------------------
// The predicate surface over the union
// ---------------------------------------------------------------------

// Predicates that take an ELEMENT: each narrows the union by reading
// `element.type`, sometimes together with another field.
const ELEMENT_PREDICATES = [
  "isArrowElement",
  "isBindableElement",
  "isBindingElement",
  "isCurvedArrow",
  "isElbowArrow",
  "isEmbeddableElement",
  "isExcalidrawElement",
  "isFlowchartNodeElement",
  "isFrameElement",
  "isFrameLikeElement",
  "isFreeDrawElement",
  "isIframeElement",
  "isIframeLikeElement",
  "isImageElement",
  "isInGroup",
  "isLineElement",
  "isLinearElement",
  "isMagicFrameElement",
  "isRectangularElement",
  "isRectanguloidElement",
  "isSharpArrow",
  "isSimpleArrow",
  "isTextElement",
  "isTextBindableContainer",
  "isValidTextContainer",
  "hasBoundTextElement",
];
const subjects = [...elements, rounded];
const elementTable = {};
for (const name of ELEMENT_PREDICATES) {
  const fn = El[name];
  if (typeof fn !== "function") continue;
  elementTable[name] = subjects.map((e) => {
    try {
      return fn(e) ? 1 : 0;
    } catch {
      return "threw";
    }
  });
}
p("elementPredicates", elementTable);

// Predicates that take the TAG. These are the pure `type === "…" || …`
// chains in `comparisons.ts` and `typeChecks.ts` — the shape
// `tag-rewrite` and `switch-fold` read a union declaration to collapse.
// They take a string, so a mistaken argument reads `undefined` instead
// of throwing, which is why they are pinned separately from the above.
const TAG_PREDICATES = [
  "canChangeRoundness",
  "canHaveArrowheads",
  "hasBackground",
  "hasStrokeColor",
  "hasStrokeStyle",
  "hasStrokeWidth",
  "isBindingElementType",
  "isEligibleFrameChildType",
  "isFreeDrawElementType",
  "isLinearElementType",
  "isUsingAdaptiveRadius",
  "isUsingProportionalRadius",
];
const TAGS = [
  "rectangle",
  "ellipse",
  "diamond",
  "arrow",
  "line",
  "freedraw",
  "frame",
  "magicframe",
  "text",
  "image",
  "embeddable",
  "iframe",
  "selection",
];
const tagTable = {};
for (const name of TAG_PREDICATES) {
  const fn = El[name];
  if (typeof fn !== "function") continue;
  tagTable[name] = TAGS.map((t) => (fn(t) ? 1 : 0));
}
p("tagPredicates", tagTable);
p(
  "roundnessApplies",
  [2, 3].map((t) => subjects.map((e) => (El.canApplyRoundnessTypeToElement(t, e) ? 1 : 0))),
);

// ---------------------------------------------------------------------
// Geometry
// ---------------------------------------------------------------------

const round = (v) => (typeof v === "number" ? Math.round(v * 1000) / 1000 : v);

p(
  "absoluteCoords",
  elements.map((e) => El.getElementAbsoluteCoords(e, elementsMap).map(round)),
);
p("commonBounds", El.getCommonBounds(elements).map(round));
p(
  "commonBoundingBox",
  (() => {
    const b = El.getCommonBoundingBox(elements);
    return {
      minX: round(b.minX),
      minY: round(b.minY),
      width: round(b.width),
      height: round(b.height),
    };
  })(),
);
p(
  "elementBounds",
  elements.map((e) => El.getElementBounds(e, elementsMap).map(round)),
);
p("boundsFromPoints", El.getBoundsFromPoints(freedraw.points).map(round));
p("pathALoop", [El.isPathALoop(line.points), El.isPathALoop(arrow.points)]);
p(
  "perfectSize",
  [
    El.getPerfectElementSize("rectangle", 100, 40),
    El.getPerfectElementSize("line", 100, 40),
    El.getPerfectElementSize("arrow", 12, 100),
  ].map((r) => ({ w: round(r.width), h: round(r.height) })),
);
p(
  "normalizedDimensions",
  (() => {
    const n = El.getNormalizedDimensions({ ...rect, width: -30, height: -40 });
    return { x: round(n.x), y: round(n.y), w: round(n.width), h: round(n.height) };
  })(),
);
p(
  "cornerRadius",
  [0, 10, 40, 400].map((s) => [
    round(El.getCornerRadius(s, rect)),
    round(El.getCornerRadius(s, rounded)),
  ]),
);
p("pointInsideBounds", [
  El.pointInsideBounds([50, 30], [0, 0, 100, 100]),
  El.pointInsideBounds([500, 30], [0, 0, 100, 100]),
]);
p("lineSegments", El.getElementLineSegments(rect, elementsMap).length);
p(
  "intersect",
  El.intersectElementWithLineSegment(rect, elementsMap, [
    [-100, 45],
    [500, 45],
  ]).map((pt) => pt.map(round)),
);
p("distanceToElement", round(El.distanceToElement(rect, elementsMap, [200, 45])));
p("isPointInElement", [
  El.isPointInElement([50, 45], rect, elementsMap),
  El.isPointInElement([-50, 45], rect, elementsMap),
]);
p(
  "headings",
  [
    [0, -100],
    [100, 0],
    [0, 100],
    [-100, 0],
  ].map((pt) => {
    const h = El.headingForPointFromElement(rect, [10, 20, 110, 70, 60, 45], pt);
    return [round(h[0]), round(h[1])];
  }),
);

// ---------------------------------------------------------------------
// Selection / visibility / z-order
// ---------------------------------------------------------------------

p("invisiblySmall", [
  El.isInvisiblySmallElement(tiny),
  El.isInvisiblySmallElement(stub),
  El.isInvisiblySmallElement(rect),
  El.isInvisiblySmallElement(arrow),
]);
p("visible", El.getVisibleElements([...elements, tiny, stub, deleted]).length);
p("nonDeleted", El.getNonDeletedElements([...elements, deleted]).length);
p("sceneVersion", El.getSceneVersion(elements.map((e) => ({ ...e, version: 3 }))));
p("hashElementsVersion", El.hashElementsVersion(elements));
p("hashString", ["", "excalidraw", "a".repeat(64)].map((s) => El.hashString(s)));
p(
  "withinSelection",
  El.getElementsWithinSelection(
    elements,
    { x: -10, y: -10, width: 300, height: 200 },
    elementsMap,
  ).map((e) => e.type),
);
p("someSelected", [
  El.isSomeElementSelected(elements, { selectedElementIds: { [rect.id]: true } }),
  El.isSomeElementSelected(elements, { selectedElementIds: {} }),
]);
const zAppState = {
  selectedElementIds: { [rect.id]: true },
  selectedGroupIds: {},
  editingGroupId: null,
};
p("moveOneRight", El.moveOneRight(elements, zAppState).map((e) => e.type));
p("moveOneLeft", El.moveOneLeft(elements, zAppState).map((e) => e.type));
p("moveAllRight", El.moveAllRight(elements, zAppState).map((e) => e.type));
p(
  "moveAllLeft",
  El.moveAllLeft(elements, {
    ...zAppState,
    selectedElementIds: { [freedraw.id]: true },
  }).map((e) => e.type),
);

// ---------------------------------------------------------------------
// Fractional indices
// ---------------------------------------------------------------------

// Returns the elements as a Map keyed by id, so read it back in
// insertion order.
const indexed = [
  ...El.syncInvalidIndicesImmutable(elements.map((e) => ({ ...e, index: null }))).values(),
];
p("indicesOrdered", indexed.map((e) => e.type));
p(
  "indicesAscending",
  indexed.every((e, i) => i === 0 || indexed[i - 1].index < e.index),
);
try {
  throw new El.InvalidFractionalIndexError("boom");
} catch (e) {
  // Identity by `instanceof`, deliberately NOT by `constructor.name`.
  // `--mangle` renames a class whose name the BUNDLE never reads back;
  // `observed_names.mbt` reserves the names it can see the bundle
  // observe, and a consumer reading `.name` from outside is not one of
  // them — the same default terser and esbuild ship. Asserting the name
  // here would pin that limitation rather than test behaviour.
  p("errorIdentity", [
    e instanceof El.InvalidFractionalIndexError,
    e instanceof Error,
    e.message,
  ]);
}

// ---------------------------------------------------------------------
// Shape generation — the hand-off to roughjs and perfect-freehand
// ---------------------------------------------------------------------

// `getElementShape` dispatches on the union's tag: the rectangular arms
// take a pure polygon path, `arrow` / `line` go through roughjs's
// generator, `freedraw` through perfect-freehand. All three are
// exercised, so a break in the hand-off to any of them shows up here.
for (const [label, el] of [
  ["rect", rect],
  ["rounded", rounded],
  ["diamond", diamond],
  ["arrow", arrow],
  ["line", line],
  ["freedraw", freedraw],
]) {
  const g = El.getElementShape(el, elementsMap);
  p(`shape.${label}`, { type: g.type, points: g.data?.length ?? null });
}
p(
  "roughOptions",
  (() => {
    const o = El.generateRoughOptions(rect);
    return {
      seed: o.seed,
      strokeWidth: o.strokeWidth,
      roughness: o.roughness,
      fillStyle: o.fillStyle,
      stroke: o.stroke,
    };
  })(),
);
p("freedrawOutline", El.getFreedrawOutlinePoints(freedraw, 1).length > 0);
// The constant-width branch, which is a DIFFERENT code path: it runs the
// stroke through `LaserPointer` (`addPoint` in a loop, then
// `getStrokeOutline`) instead of perfect-freehand. Worth its own line
// because the first version of this driver only took the other branch,
// and all three legs agreed while every one of them was missing those
// methods — the class lives in one module and the calls in another, and
// class-method DCE had been answering "does anything access this name"
// per module. A reference leg can be wrong and still be agreed with.
p(
  "constantWidthOutline",
  (() => {
    const el = { ...freedraw, strokeOptions: { variability: "constant" } };
    const pts = El.getFreedrawOutlinePoints(el, 1);
    return [pts.length > 0, pts.length === El.getFreedrawOutlinePoints(freedraw, 1).length];
  })(),
);

// ---------------------------------------------------------------------
// Element copies
// ---------------------------------------------------------------------

const bumped = El.newElementWith(rect, { width: 250 });
p("newElementWith", [
  shape(bumped).w,
  bumped.version === rect.version + 1,
  bumped.id === rect.id,
]);
const copy = El.deepCopyElement(arrow);
p("deepCopy", [shape(copy), copy.points !== arrow.points]);

console.log(out.join("\n"));
