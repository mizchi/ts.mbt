// False positives the express recall work exposed on real code (effect,
// univer, excalidraw), and the cells that keep each fix honest. Every
// `ok…` line is accepted by the TypeScript nightly and every reported line
// is one it reports, probed one file or project per case.

///|
/// Single-file shapes: `"k" in x` on an interface narrows it to `T &
/// Record<"k", unknown>`; a union SOURCE assigns when each member does; a
/// callback whose returns all sit inside a `switch` is not `undefined`; a
/// plain call of a callable interface declaring `this: number` is TS2684;
/// a generic call signature's binder is not judged as a type; an expando
/// function keeps its assigned members; and the naked-union candidate
/// rules carried from #305's review (a construct-signature source, a
/// nullish constituent, two equal candidates).
test "callable shapes and the false positives exposed beside them" {
  let src =
    #|interface Constraint { readonly ast: string }
    #|export function okIn(schema: Constraint) { if ("members" in schema) { return schema.members; } return 0; }
    #|interface PO { readonly errors?: "first" | "all" | undefined }
    #|declare const y1: { errors: "first" } | PO;
    #|export const okUnion: PO = y1;
    #|declare const y2: { errors: "nope" } | PO;
    #|export const badUnion: PO = y2;
    #|declare const xs: [number, string][];
    #|export const acts = xs.map(([t, s]) => { switch (t) { case 0: { return { a: 1, s }; } default: { return { a: 2, s }; } } });
    #|export const okSwitch = acts.every((x) => x.a === 1);
    #|interface B { (this: number, b?: number): void }
    #|declare const b: B;
    #|export function badThis() { b(0); }
    #|interface G { <T>(x: T, m?: string): { v: T } }
    #|declare const g: G;
    #|export const okGeneric: number = g(1).v;
    #|function d() {}
    #|d.q = 1;
    #|export const okExpando = d.q;
    #|declare function make<T>(x: T | (new () => T)): T;
    #|declare const C: { new (): { id: number }; marker: true };
    #|export const okMake: { id: number } = make(C);
    #|export const okMakeId: number = make(C).id;
    #|declare function both<T>(a: T | null, b: T | null): T;
    #|export function nullish(s: string) { const ok: string | undefined = both(s, undefined); const bad: number = both(s, undefined); return [ok, bad]; }
    #|declare function both2<T>(a: T | undefined, b: T | undefined): T;
    #|export function same(ys: string[]) { const ok: string[] = both2(ys, ys); const bad: number = both2(ys, ys); return [ok, bad]; }
  assert_eq(issue_lines(src), [
    "function badThis > call `b`: the `this` context of type `void` is not assignable to the call signature's declared `this`",
    "function nullish > binding `bad` init: type `string | undefined` is not assignable to type `number`",
    "function same > binding `bad` init: expected `number` but got `string[]`", "top-level > binding `badUnion` init: expected `PO` but got `{ errors: \"nope\" (string) } | PO`",
  ])
}

///|
/// An interface a module AUGMENTATION adds to (`declare module "./e" {
/// interface ExpectStatic { poll(): void } }`, how vitest adds
/// `expect.poll`) is not complete without it, and the augmentation is not
/// merged, so member existence on it abstains: `expect.nope` is a MISS. An
/// interface nothing augments keeps its check.
test "an augmented interface abstains on member existence" {
  assert_eq(
    graph_messages(
      [
        (
          "/src/e.d.ts", "export interface ExpectStatic { (x: number): void; extend(): void }\nexport interface Plain { x: number }",
        ),
        (
          "/src/aug.d.ts", "import \"./e\";\ndeclare module \"./e\" { interface ExpectStatic { poll(): void } }\nexport {};",
        ),
        (
          "/src/main.ts", "import type { ExpectStatic, Plain } from \"./e\";\nimport \"./aug\";\ndeclare const expect: ExpectStatic;\ndeclare const p: Plain;\nexport const ok = expect.poll();\nexport const missed = expect.nope;\nexport const bad = p.nope;",
        ),
      ],
      [
        ("/src/main.ts", "./e", "/src/e.d.ts"),
        ("/src/main.ts", "./aug", "/src/aug.d.ts"),
        ("/src/aug.d.ts", "./e", "/src/e.d.ts"),
      ],
    ),
    [
      "top-level > PropAccess `.nope` :: property `nope` does not exist on `Plain`",
    ],
  )
}

///|
/// Two scope facts of a declaration file the shared type table flattens.
/// @types/react's top-level `type NativeKeyboardEvent = KeyboardEvent`
/// means the DOM's, while `import type { KeyboardEvent } from "react"`
/// redirects every bare `KeyboardEvent` to `React.KeyboardEvent`, so a
/// member read through the alias abstains. And `class PureComponent
/// extends Component` inside `namespace React` is `React.Component`, even
/// with `@firebase/component`'s `class Component` in the same program:
/// read bare, `this.state` on every subclass was "does not exist". A real
/// typo on the subclass still reports.
test "an export-assigned namespace keeps its own scope" {
  assert_eq(
    graph_messages(
      [
        (
          "/src/r.d.ts", "export = R;\nexport as namespace R;\ntype NativeKeyboardEvent = KeyboardEvent;\ndeclare namespace R {\n  interface SyntheticEvent<E> { nativeEvent: E }\n  interface KeyboardEvent<T = Element> extends SyntheticEvent<NativeKeyboardEvent> { key: string }\n  class Component<P, S> { constructor(props: P); props: Readonly<P>; state: Readonly<S>; }\n  class PureComponent<P = {}, S = {}> extends Component<P, S> {}\n}",
        ),
        (
          "/src/fb.d.ts", "export declare class Component<T> { readonly name: string; constructor(name: string); }",
        ),
        (
          "/src/main.ts", "import type { KeyboardEvent } from \"r\";\nimport { PureComponent } from \"r\";\nimport { Component as FbC } from \"./fb\";\nexport const fbc: FbC<number> | undefined = undefined;\nexport function okNative(e: KeyboardEvent) { return e.nativeEvent.isComposing; }\ninterface St { a: number }\nexport class Collab extends PureComponent<{}, St> {\n  constructor(props: {}) { super(props); this.state = { a: 1 }; }\n  okState() { return this.state.a; }\n  bad() { return this.nope; }\n}",
        ),
      ],
      [
        ("/src/main.ts", "r", "/src/r.d.ts"),
        ("/src/main.ts", "./fb", "/src/fb.d.ts"),
      ],
    ),
    [
      "function Collab.bad > PropAccess `.nope` :: property `nope` does not exist on `Collab`",
    ],
  )
}

///|
/// A generic call signature declared in ANOTHER module (vitest's
/// `interface ExpectStatic { <T>(actual: T): Assertion<T> }`): its binder
/// is not carried, so a call through it would judge `T` as a type, and the
/// file holding the call has no `<T>` of its own to suppress that — and
/// with a real `class T` in the program (univer's engine-formula has one)
/// the bare `T` resolves to it. Such an interface is not called through; a
/// non-generic one still is.
test "a generic call signature from another module is not called through" {
  assert_eq(
    graph_messages(
      [
        (
          "/src/v.d.ts", "export interface Assertion<T> { toBe(v: T): void }\nexport interface ExpectStatic { <T>(actual: T, message?: string): Assertion<T>; extend(m: object): void }\nexport interface Plain { (n: number): string }",
        ),
        (
          "/src/main.ts", "import type { ExpectStatic, Plain } from \"./v\";\nexport class T { t = 1 }\ndeclare const expect: ExpectStatic;\ndeclare const plain: Plain;\nexport function ok() { expect(1).toBe(1); expect(\"s\", \"m\"); return plain(1); }\nexport function bad() { return plain(\"x\"); }",
        ),
      ],
      [("/src/main.ts", "./v", "/src/v.d.ts")],
    ),
    ["function bad > call `plain` arg[0] :: expected `number` but got `string`"],
  )
}

///|
/// An explicit JSX attribute after a spread overrides the spread's field
/// of the same name, so only the attribute's value reaches inference and
/// the check: `<C {...{ value: 1 }} value="ok" />` passes `"ok"`.
test "an explicit JSX attribute overrides a spread field" {
  let src =
    #|declare namespace JSX { interface Element {} interface IntrinsicElements {} interface ElementAttributesProperty { props: {} } }
    #|declare function C<T>(props: { value?: T; on?: (v: T) => void }): JSX.Element;
    #|export const okGeneric = <C {...{ value: 1 }} value="ok" />;
    #|declare function D(props: { value: string }): JSX.Element;
    #|export const okPlain = <D {...{ value: 1 }} value="ok" />;
    #|export const bad = <D value={1} />;
  let out = check_source(src, true)
  assert_eq(
    out, "top-level > <D> attr `value`: expected `string` but got `number`",
  )
}

///|
/// `asserts cond` over a condition (`invariant(p != null, "…")`): after the
/// call the condition held, so its true branch's narrowing persists, as an
/// `if (!cond) throw` would leave it. It was applied only to a bare
/// variable argument, so excalidraw's every `invariant(p != null)` left `p`
/// possibly `undefined`.
test "an assertion over a condition narrows by it" {
  let src =
    #|declare function invariant(c: any, m: string): asserts c;
    #|export function ok(q: string | undefined) { invariant(q != null, "x"); const s: string = q; return s; }
    #|export function bad1(q: string | undefined) { invariant(q !== undefined || true, "x"); const s: string = q; return s; }
    #|export function bad2(q: string | null) { invariant(q != undefined, "x"); const n: number = q; return n; }
  assert_eq(issue_lines(src), [
    "function bad1 > binding `s` init: type `string | undefined` is not assignable to type `string`",
    "function bad2 > binding `n` init: expected `number` but got `string`",
  ])
}

///|
/// Two narrowing gaps the express work's real-code runs exposed, both on
/// main as well. A union of unions destructures as that union: a nested
/// conditional (`a ? (b ? p : q) : [0, 0]`, excalidraw's
/// `getArrowheadPoints`) infers as one, and its inner union is not a tuple
/// or an array, so every element bound `undefined`. And the `default` of
/// a switch whose labels cover every variant's discriminant is `never`:
/// the LAST variant stayed, because the split is for unions only. A
/// non-union receiver is not narrowed by its discriminant at all, and
/// `globalThis.Array.isArray` is `Array.isArray`.
test "a nested union destructures and an exhaustive default is never" {
  let src =
    #|type LP = [x: number, y: number] & { _brand: "lp" };
    #|type El = { readonly points: readonly LP[] };
    #|export const okNested = (element: El, position: "start" | "end") => {
    #|  const [px, py] = element.points.length > 1 ? (position === "end" ? element.points[2] : element.points[1]) : [0, 0];
    #|  return 1 - py - px;
    #|};
    #|type A = { kind: "abc" } | { kind: "def" };
    #|export function okExhaustive(a: A) {
    #|  switch (a.kind) {
    #|    case "abc": return 1;
    #|    case "def": return 2;
    #|    default: { const n: number = a; return n; }
    #|  }
    #|}
    #|type Enc = { encoded: string; encoding: "bstring" };
    #|export const okNonUnion = (data: Enc): string => {
    #|  switch (data.encoding) {
    #|    case "bstring": return data.encoded;
    #|    default: throw new Error(`unknown ${data.encoding}`);
    #|  }
    #|};
    #|interface C2 { readonly ast: string }
    #|export function okGlobalIsArray(schema: C2) {
    #|  if ("members" in schema && globalThis.Array.isArray(schema.members)) { return schema.members.every((m) => m); }
    #|  return false;
    #|}
    #|export function badNever(a: A) {
    #|  switch (a.kind) {
    #|    case "abc":
    #|    case "def": return;
    #|    default: a.kind;
    #|  }
    #|}
  assert_eq(issue_lines(src), [
    "function badNever > PropAccess `.kind`: property `kind` does not exist on `never`",
  ])
}
