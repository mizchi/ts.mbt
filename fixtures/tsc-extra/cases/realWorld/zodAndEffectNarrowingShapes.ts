// @strict: true
// @target: esnext

// zod and effect: narrowing by a non-nullish declaration initializer, a
// property path narrowed by assignment and by `??=`, a getter key in the
// excess-property check, a `never`-returning method ending a path, an
// `asserts` predicate that already holds, and a discriminant union split.

interface N { next?: N; visit(): void }
declare const root: N;
declare function maybe(): N | undefined;
type Check = { kind: "min"; value: number } | { kind: "max"; value: number } | { kind: "int" };
type Ctx = { addIssue: (a: string) => void; readonly path: (string | number)[] };
declare const p: (string | number)[];
declare const o: { fail(m: string): never };
interface Trait { _zod: unknown }
interface Ctor<T extends Trait> { init(inst: T): asserts inst is T }
interface ZErr extends Trait { name: string }
declare const ZCtor: Ctor<ZErr>;
function okPatternLiteral() { let x: "a" | "b" = "a"; [x] = ["b"]; return x; }
function okDeclNarrow() { let c: N | undefined = root; c.visit(); }
function okDeclNarrowConst() { const c: N | null | undefined = root; c.visit(); }
function okDefensiveCheck(c: N) { if (c === undefined) {} c.visit(); }
class ResultCache { _c: { v: number } | null = null; get(): { v: number } { if (this._c !== null) return this._c; this._c = { v: 1 }; return this._c; } }
function okSplitDiscriminant(kind: "min" | "max", value: number) { const c: Check = { kind, value }; return c; }
function okGetterKey() { const c: Ctx = { addIssue: (a: string) => {}, get path() { return p; } }; return c; }
function okNeverMethod(c: Check): number { if (c.kind === "min") return 1; o.fail("x"); }
function okPropCoalesce(m: { message?: string }): string { m.message ??= "x"; return m.message; }
function okAssertsKeepsDeclared(inst: ZErr) { ZCtor.init(inst); return inst.name; }
function badDeclMaybe() { let c: N | undefined = maybe(); c.visit(); }
function badSplitOutside(kind: "min" | "other", value: number) { const c: Check = { kind, value }; return c; }
function badGetterExcess() { const c: Ctx = { addIssue: (a: string) => {}, path: p, get nope() { return 1; } }; return c; }
function badPropNoCoalesce(m: { message?: string }): string { return m.message; }
