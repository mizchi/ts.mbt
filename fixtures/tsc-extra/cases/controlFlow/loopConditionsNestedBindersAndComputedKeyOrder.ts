// @strict: true
// @target: esnext

// A loop condition narrowed by the back edge, nested generic binders in a
// returned function, a caught versus an uncaught `throw` in a loop body, and
// the left-to-right order of computed keys in a destructuring pattern.

declare function acceptString(x: string): void;
class C1 {
  foo<U extends { kind: string }>(x: U) {
    function bar<V extends U>(v: V) { return v; }
    return bar;
  }
}
class C2 {
  foo<U extends string>(x: U) {
    function bar<U extends number>(v: U) { return v; }
    return bar;
  }
}
function okFreshObjectProperty() { const r = new C1().foo({ kind: "a" }); r({ kind: "b" }); }
function okShadowedBinder() { const r = new C2().foo("a"); r(1); }
function okCaughtThrow(c: boolean) { let x: "a" | "b" = "a"; while (c) { if (x === "b") break; try { x = "b"; throw 0; } catch {} } }
function okWhileCondition() { let x: "a" | "b" = "a"; while (x !== "b") { x = "b"; } }
function okForOfHead() { let x: string | number; for (x of ["a"]) { acceptString(x); x = 1; } }
function okComputedKeyOrder() { let k: 0 | 1 = 0; const { [(k = 1)]: first, [k]: second } = ["a", "b"] as const; const value: "b" = second; return [first, value]; }
function badUncaughtThrow(c: boolean) { let x: "a" | "b" = "a"; while (c) { if (x === "b") break; x = "b"; throw 0; } }
function badBodyJoin() { let y: string | number = "s"; for (const v of [1]) { acceptString(y); y = v; } }
function badWhileBody() { let x: "a" | "b" = "a"; while (x !== "b") { const z: "b" = x; x = "b"; } }
