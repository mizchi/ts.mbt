// Synthetic corpus to exercise the PR #53 type-aware mangler paths.
// Each phase is exercised by enough instances that any size delta is
// measurable.
import { writeFileSync as externalSink } from "node:fs";

// Phase 1: typed local flowing directly (as an object, not stringified)
// to an external sink. Without the type-stamp, the External arm
// reserves '*' on every property name in the bundle — none of the
// $-prefixed fields below would be manglable. With the type-stamp,
// only {name, total} are reserved, so $alpha/$beta/$gamma/$delta/
// $epsilon become 1-2 char names.
declare function externalConsume(o: { name: string; total: number }): void;
type PublicRecord = { name: string; total: number };
function publishViaSink(name: string, total: number): void {
  const rec: PublicRecord = { name, total };
  // Direct typed-object flow into an external function — Phase 1's
  // narrowing applies to this binding.
  externalConsume(rec);
  externalSink("/tmp/x", JSON.stringify(rec));
}

// Many widget classes with internal-only $-prefixed fields. If
// property-mangling is unblocked, these become 1-2 char names.
class WidgetA {
  $alphaCount = 1;
  $alphaState = 2;
  $alphaCache = 3;
  bumpAlpha(): number {
    this.$alphaCount = this.$alphaCount + 1;
    return this.$alphaCount + this.$alphaState - this.$alphaCache;
  }
}
class WidgetB {
  $betaCount = 1;
  $betaState = 2;
  $betaCache = 3;
  bumpBeta(): number {
    this.$betaCount = this.$betaCount + 1;
    return this.$betaCount + this.$betaState - this.$betaCache;
  }
}
class WidgetC {
  $gammaCount = 1;
  $gammaState = 2;
  $gammaCache = 3;
  bumpGamma(): number {
    this.$gammaCount = this.$gammaCount + 1;
    return this.$gammaCount + this.$gammaState - this.$gammaCache;
  }
}
class WidgetD {
  $deltaCount = 1;
  $deltaState = 2;
  $deltaCache = 3;
  bumpDelta(): number {
    this.$deltaCount = this.$deltaCount + 1;
    return this.$deltaCount + this.$deltaState - this.$deltaCache;
  }
}
class WidgetE {
  $epsilonCount = 1;
  $epsilonState = 2;
  $epsilonCache = 3;
  bumpEpsilon(): number {
    this.$epsilonCount = this.$epsilonCount + 1;
    return this.$epsilonCount + this.$epsilonState - this.$epsilonCache;
  }
}

// Phase 4a: discriminated-union switch with `default: throw`. When
// every variant's kind literal is covered, drop the default arm.
type Shape =
  | { kind: "circle"; r: number }
  | { kind: "square"; side: number }
  | { kind: "triangle"; base: number; h: number };
function area(s: Shape): number {
  switch (s.kind) {
    case "circle":
      return s.r * s.r;
    case "square":
      return s.side * s.side;
    case "triangle":
      return (s.base * s.h) / 2;
    default:
      throw new Error("unreachable_shape");
  }
}
type Color =
  | { kind: "rgb"; r: number; g: number; b: number }
  | { kind: "hsl"; h: number; s: number; l: number }
  | { kind: "hex"; value: string };
function describeColor(c: Color): string {
  switch (c.kind) {
    case "rgb":
      return `rgb(${c.r},${c.g},${c.b})`;
    case "hsl":
      return `hsl(${c.h},${c.s},${c.l})`;
    case "hex":
      return c.value;
    default:
      throw new Error("unreachable_color");
  }
}
type Event =
  | { kind: "click"; x: number; y: number }
  | { kind: "key"; code: string }
  | { kind: "scroll"; delta: number };
function summarizeEvent(e: Event): string {
  switch (e.kind) {
    case "click":
      return `click@${e.x},${e.y}`;
    case "key":
      return `key:${e.code}`;
    case "scroll":
      return `scroll:${e.delta}`;
    default:
      throw new Error("unreachable_event");
  }
}

// Phase 4b: typeof on a typed parameter folds. The whole if/else
// block collapses to its true branch and the surrounding code
// shrinks.
function inspectShape(obj: { tag: string; count: number }): string {
  if (typeof obj === "object") {
    return `${obj.tag}:${obj.count}`;
  }
  return "?";
}
function inspectColor(obj: { name: string; hex: string }): string {
  if (typeof obj === "object") {
    return `${obj.name}=${obj.hex}`;
  }
  return "?";
}
function inspectEvent(obj: { kind: string; ts: number }): string {
  if (typeof obj === "object") {
    return `${obj.kind}@${obj.ts}`;
  }
  return "?";
}

// Drive everything so treeshake can't drop anything.
const wA = new WidgetA();
const wB = new WidgetB();
const wC = new WidgetC();
const wD = new WidgetD();
const wE = new WidgetE();
publishViaSink("alpha", wA.bumpAlpha());
publishViaSink("beta", wB.bumpBeta());
publishViaSink("gamma", wC.bumpGamma());
publishViaSink("delta", wD.bumpDelta());
publishViaSink("epsilon", wE.bumpEpsilon());

console.log(area({ kind: "circle", r: 2 }));
console.log(area({ kind: "square", side: 3 }));
console.log(area({ kind: "triangle", base: 4, h: 5 }));

console.log(describeColor({ kind: "rgb", r: 1, g: 2, b: 3 }));
console.log(describeColor({ kind: "hsl", h: 10, s: 20, l: 30 }));
console.log(describeColor({ kind: "hex", value: "#abc" }));

console.log(summarizeEvent({ kind: "click", x: 1, y: 2 }));
console.log(summarizeEvent({ kind: "key", code: "Enter" }));
console.log(summarizeEvent({ kind: "scroll", delta: 5 }));

console.log(inspectShape({ tag: "shape", count: 7 }));
console.log(inspectColor({ name: "blue", hex: "#00f" }));
console.log(inspectEvent({ kind: "ping", ts: 12345 }));
