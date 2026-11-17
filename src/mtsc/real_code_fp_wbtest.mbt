///|
/// False positives measured on univer and excalidraw, both of which tsc
/// accepts outright. Each test pairs the legal spelling with an illegal
/// neighbour tsc reports, so a fix that merely silences the rule fails.
fn issue_lines(source : String) -> Array[String] {
  let out = check_source(source, false)
  if out == "" {
    []
  } else {
    out.split("\n").map(fn(l) { l.to_owned() }).collect()
  }
}

///|
/// A class with a `private` member is assignable to any target that does
/// not ask for that member: a union of its bases, an object type, an
/// interface, `Base | undefined`. Only a target naming the private member,
/// or one the class does not reach structurally, is an error.
test "a class with a private member assigns to a target that does not name it" {
  let src =
    #|class Root { r = 1 }
    #|class Base extends Root { private p = 1; b = 2 }
    #|class Arr extends Base { private q = 1; a = 3 }
    #|class Ref extends Root { private z = 1; c = 4 }
    #|interface IB { b: number }
    #|type V = Base | Ref;
    #|export const ok1: V = new Arr();
    #|export const ok2: { b: number } = new Arr();
    #|export const ok3: IB = new Arr();
    #|export const ok4: Base | undefined = new Arr();
    #|export const ok5: Root = new Arr();
    #|export const bad1: { q: number } = new Arr();
    #|export const bad2: Ref = new Arr();
    #|export const bad3: Ref | { q: number } = new Arr();
    #|class Other { private p = 1; b = 2 }
    #|export const bad4: Base = new Other();
    #|export const bad5: Base | Ref = new Other();
    #|export function pick(c: boolean): void {
    #|  const x = c ? new Arr() : new Base();
    #|  const ok6: Base = x;
    #|  const bad6: Base = c ? new Arr() : new Other();
    #|}
  assert_eq(issue_lines(src), [
    "function pick > binding `bad6` init (else): expected `Base` but got `Other`",
    "top-level > binding `bad1` init: expected `{ q: number }` but got `Arr`", "top-level > binding `bad2` init: expected `Ref` but got `Arr`",
    "top-level > binding `bad3` init: expected `Ref | { q: number }` but got `Arr`",
    "top-level > binding `bad4` init: expected `Base` but got `Other`", "top-level > binding `bad5` init: expected `Base | Ref` but got `Other`",
  ])
}

///|
/// An unannotated function contextually typed by `() => void` infers its
/// own return type, and `() => boolean` is assignable to `() => void`, so
/// its `return` statements are not judged against `void`. An annotation
/// on the function itself is what they are judged against, and a
/// contextual `() => Promise<void>` still demands an empty async body.
test "a contextually void callback may return a value" {
  let src =
    #|declare const xs: number[];
    #|xs.forEach((x) => { if (x > 1) { return false; } });
    #|xs.forEach(function (x) { return false; });
    #|xs.forEach((x): boolean => { return false; });
    #|const k1: () => void = () => { return true; };
    #|const k2: () => void = async () => { return 1; };
    #|const k4: () => Promise<void> = async () => { };
    #|const k7: { (): void } = () => { return 1; };
    #|const k8: (() => void) | undefined = () => { return 1; };
    #|export function bad1(): void { return false; }
    #|const bad2: () => Promise<void> = async () => { return 1; };
    #|const bad3: () => void = (): void => { return true; };
  assert_eq(issue_lines(src), [
    "function bad1 > return: expected `void` but got `boolean`", "top-level > return: expected `void` but got `number`",
    "top-level > return: expected `void` but got `boolean`",
  ])
}

///|
/// A numeric enum accepts any `number`, and a union target holding one
/// (`keepLines?: BooleanNumber` is `BooleanNumber | undefined`) read
/// `number` as a mismatch while the bare enum target abstained. A string
/// is still not a numeric enum.
test "a number assigns to an optional numeric enum" {
  let src =
    #|export enum BooleanNumber { FALSE = 0, TRUE = 1 }
    #|interface S { keepLines?: BooleanNumber }
    #|export function f(s: S, value: boolean, n: number): void {
    #|  s.keepLines = value ? 1 : 0;
    #|  s.keepLines = n;
    #|  const e: BooleanNumber | undefined = n;
    #|  const bad: BooleanNumber | undefined = "x";
    #|}
  assert_eq(issue_lines(src), [
    "function f > binding `bad` init: expected `BooleanNumber | undefined` but got `string`",
  ])
}

///|
/// An interface method's rest parameter takes any number of arguments of
/// its element type; it was read as ONE parameter of the array type, so
/// every logger interface (`debug(...args: any[])`) reported its calls.
test "an interface method's rest parameter takes trailing arguments" {
  let src =
    #|interface ILog { debug(...args: any[]): void; info(...xs: number[]): void; plain(xs: number[]): void }
    #|declare const log: ILog;
    #|log.debug("a", 1, true);
    #|log.info(1, 2);
    #|log.info("bad");
    #|log.plain([1]);
    #|log.plain(1);
  assert_eq(issue_lines(src), [
    "top-level > call `info` arg[0]: expected `number` but got `string`", "top-level > call `plain` arg[0]: expected `number[]` but got `number`",
  ])
}

///|
/// A `declare class` answers for every constructor overload, not only the
/// last: @types/react's `constructor(props: P); constructor(props: P,
/// context: any)` accepts `new C(props)`. A count no overload accepts is
/// still an arity error.
test "a declare class accepts every constructor overload" {
  let src =
    #|declare class C<P> {
    #|  readonly props: P;
    #|  constructor(p: P);
    #|  constructor(p: P, c: any);
    #|}
    #|export const y = new C({ a: 1 });
    #|export const z = new C({ a: 1 }, 2);
    #|export const none = new C();
    #|export const three = new C({ a: 1 }, 2, 3);
  assert_eq(issue_lines(src), [
    "top-level > new `C`: expected 1-2 argument(s), got 0", "top-level > new `C`: expected 1-2 argument(s), got 3",
  ])
}

///|
/// A class merged with a same-named interface has the members of both:
/// @types/react declares `class Component<P, S>` and `interface
/// Component<P, S> extends ComponentLifecycle<P, S>`, and a subclass read
/// `this.props` as missing.
test "a class merged with an interface keeps the class members" {
  let src =
    #|declare class C<P> {
    #|  readonly props: P;
    #|  constructor(p: P);
    #|}
    #|interface C<P> extends L {}
    #|interface L { didMount?(): void }
    #|export class App extends C<{ a: number }> {
    #|  n(): number { return this.props.a; }
    #|}
    #|export const x = new App({ a: 1 });
    #|export const bad: string = x.n();
  assert_eq(issue_lines(src), [
    "top-level > binding `bad` init: expected `string` but got `number`",
  ])
}

///|
/// Destructuring a branded tuple (`[x: number, y: number] & { _brand }`)
/// reads the tuple member; an element was `undefined` before, so `x - y`
/// was "operator cannot be applied". The element type is still judged.
test "destructuring a branded tuple binds its elements" {
  let src =
    #|type P2 = [x: number, y: number] & { _brand: "g" };
    #|type P3 = [x: number, y: number] & { _brand: "l" };
    #|export function f2(p: P2): number { const [x, y] = p; return x - y; }
    #|export function f3<Q extends P2 | P3>(p: Q): number { const [x, y] = p; return x - y; }
    #|export function f4(ps: readonly P2[]): number { let c = 0; for (const [x, y] of ps) { c += x + y; } return c; }
    #|export function f5(p: P2): string { const [x] = p; return x; }
  assert_eq(issue_lines(src), [
    "function f5 > return: expected `string` but got `number`",
  ])
}

///|
/// A module's `declare global { … }` adds globals the whole program sees —
/// vitest's `globals.d.ts` and every app's `env.d.ts` are written this way —
/// and only ambient SCRIPTS were read for them, so each use was "cannot
/// find name". A redeclaration of a name the lib already declares keeps the
/// lib's type: @types/node's `var performance` is a conditional over
/// `globalThis` that resolves to the DOM's. A name only `@types/node`
/// declares (`process`) has no lib declaration to keep.
test "a module's declare global is visible to every module" {
  assert_eq(
    graph_messages(
      [
        (
          "/src/globals.d.ts", "export {};\ndeclare global {\n  const APP_VERSION: string;\n  function describeIt(name: string, fn: () => void): void;\n  var performance: unknown;\n  var process: { pid: number };\n}",
        ),
        (
          "/src/root.ts", "export const v: string = APP_VERSION;\ndescribeIt(\"x\", () => {});\nexport const t: number = performance.now();\nexport const pid: number = process.pid;\nexport const bad: number = APP_VERSION;",
        ),
      ],
      [],
    ),
    ["top-level > binding `bad` init :: expected `number` but got `string`"],
  )
}

///|
/// Two declaration spellings a dependency's `.d.ts` uses that did not
/// parse, each failing the whole file: a reserved word after a dot in a
/// type reference (postcss's `AtRule.default`), and `export type * as ns`
/// (vitest's `optional-types.d.ts`).
test "a reserved word after a dot and export type * as ns parse" {
  let out = check_source(
    "declare namespace N { interface I { n: number } export { I as default } }\nexport type T = N.default;\nexport type * as ns from \"./x\";",
    false,
  )
  assert_false(out.contains("parse error"))
}

///|
/// A namespace is one scope across every body that declares it: @types/node
/// writes `global { namespace NodeJS { interface ProcessEnv extends
/// Dict<string> {} } }` inside `declare module "node:process"` for the
/// `NodeJS.Dict` that `globals.d.ts` declares in another file. The bare
/// `Dict` resolved to nothing, so `process.env.X` "did not exist" and the
/// heritage read "cannot find name `Dict`". The index signature still
/// types what it returns.
test "a namespace member extends a sibling another file declares" {
  assert_eq(
    graph_messages(
      [
        (
          "/src/env.d.ts", "declare namespace NodeJS {\n  interface Dict<T> { [key: string]: T | undefined }\n}\ndeclare var process: NodeJS.Process;",
        ),
        (
          "/src/m.d.ts", "declare module \"node:process\" {\n  global {\n    var process: NodeJS.Process;\n    namespace NodeJS {\n      interface ProcessEnv extends Dict<string> {}\n      interface Process { env: ProcessEnv }\n    }\n  }\n}",
        ),
        (
          "/src/root.ts", "import \"node:process\";\nexport const a: string | undefined = process.env.TZ;\nexport const bad: number = process.env.OTHER;",
        ),
      ],
      [],
    ),
    [
      "top-level > binding `bad` init :: type `string | undefined` is not assignable to type `number`",
    ],
  )
  // The same merge written as a module's `declare global`.
  assert_eq(
    graph_messages(
      [
        (
          "/src/env.d.ts", "declare namespace NodeJS {\n  interface Dict<T> { [key: string]: T | undefined }\n  interface Process { env: ProcessEnv }\n}\ndeclare var process: NodeJS.Process;",
        ),
        (
          "/src/m.d.ts", "export {};\ndeclare global {\n  namespace NodeJS {\n    interface ProcessEnv extends Dict<string> { TZ?: string }\n  }\n}",
        ),
        (
          "/src/root.ts", "export const a: string | undefined = process.env.TZ;\nexport const bad: number = process.env.OTHER;",
        ),
      ],
      [],
    ),
    [
      "top-level > binding `bad` init :: type `string | undefined` is not assignable to type `number`",
    ],
  )
}

///|
/// A spread whose source cannot be enumerated can supply any member, so
/// the object literal is not missing anything: `{ ...r, s: 0 }` with
/// `r: any` is `any` in tsc. A literal with no such spread still reports
/// what it omits, and so does one spreading a known shape that lacks it.
test "an object literal spreading an unknown source is not missing members" {
  let src =
    #|interface R { s: number; e: number; id: string; kind: number; extra?: boolean }
    #|interface P { s: number }
    #|export function f(a: any, t: unknown, p: P): void {
    #|  const x: R = { ...a, s: 0 };
    #|  const y: R = { ...(t as any), e: 1 };
    #|  const bad1: R = { s: 0, e: 1 };
    #|  const bad2: R = { ...p, e: 1, id: "" };
    #|}
  assert_eq(issue_lines(src), [
    "function f > binding `bad1` init.id: property `id` is required by `R`", "function f > binding `bad1` init.kind: property `kind` is required by `R`",
    "function f > binding `bad2` init.kind: property `kind` is required by `R`",
  ])
}

///|
/// One condition narrows both the receiver its `?.` guards and the member
/// it reads: inside `if (slice?.ranges)` both `slice` and `slice.ranges`
/// are non-nullish. The member's type was read off the still-nullable
/// receiver and came back `any`.
test "a truthy optional chain types the member it guards" {
  let src =
    #|interface R { id: string }
    #|interface Body { ranges?: R[] }
    #|export function f1(slice: Body | undefined): void {
    #|  if (slice?.ranges) { const t: number = slice.ranges; }
    #|}
    #|export function f2(slice: Body | undefined): void {
    #|  if (slice?.ranges?.length) { const ok: R | undefined = slice.ranges[0]; const t: number = slice.ranges; }
    #|}
  assert_eq(issue_lines(src), [
    "function f1 > binding `t` init: expected `number` but got `R[]`", "function f2 > binding `t` init: expected `number` but got `R[]`",
  ])
}

///|
/// An enum MEMBER type is assignable to its enum, and an array is
/// covariant in its element. univer's `IMutationInfo` narrows `type?:
/// CommandType` to `type?: CommandType.MUTATION`, and every mutation list
/// it hands `sequenceExecute(tasks: ICommandInfo[])` was a mismatch. A
/// member against a different member, and an element that is not
/// assignable, still report.
test "an enum member and an array of a subtype assign to the wider type" {
  let src =
    #|export enum CommandType { COMMAND = 0, OPERATION = 1, MUTATION = 2 }
    #|interface ICommandInfo<T extends object = object> { id: string; type?: CommandType; params?: T }
    #|interface IMutationInfo<T extends object = object> { id: string; type?: CommandType.MUTATION; params: T }
    #|declare function run(tasks: ICommandInfo[]): void;
    #|declare const ms: IMutationInfo[];
    #|declare const m: IMutationInfo;
    #|run(ms);
    #|const c: ICommandInfo = m;
    #|interface X { t: CommandType.COMMAND }
    #|interface Y { t: CommandType.MUTATION }
    #|declare const x: X;
    #|const bad1: Y = x;
    #|interface Bad { id: number }
    #|declare const bs: Bad[];
    #|run(bs);
  assert_eq(issue_lines(src), [
    "top-level > binding `bad1` init: expected `Y` but got `X`", "top-level > call `run` arg[0]: expected `ICommandInfo[]` but got `Bad[]`",
  ])
}

///|
/// `Record<K, V>` over a CLOSED key set has exactly those keys, so in
/// `Record<UnitAction, boolean> & { ruleId?: string }` — univer's
/// `ICellPermission` — `ruleId` is the string member, not `boolean`. A
/// constituent that declares a member outranks one answering through an
/// index signature, so beside an open `Record` an optional `label` is
/// `string | undefined`, not the record's value type. `xs.flat()` removes
/// one level of nesting, so its elements are not arrays.
test "a closed Record names only its keys and flat removes a level" {
  let src =
    #|export enum UnitAction { View = "view", Edit = "edit" }
    #|type ICellPermission = Record<UnitAction, boolean> & { ruleId?: string };
    #|export function g(p: ICellPermission, rows: number[][]): void {
    #|  const s: string | undefined = p.ruleId;
    #|  const b: boolean = p.view;
    #|  const bad: string = p.edit;
    #|  const n: number = rows.flat()[0];
    #|  const bad2: string = rows.flat()[0];
    #|}
    #|declare const openRecord: Record<string, number> & { label?: string };
    #|export function h(): void {
    #|  const any_: number = openRecord.anything;
    #|  const label: string | undefined = openRecord.label;
    #|  const bad3: number = openRecord.label;
    #|}
  assert_eq(issue_lines(src), [
    "function g > binding `bad` init: expected `string` but got `boolean`", "function g > binding `bad2` init: expected `string` but got `number`",
    "function h > binding `bad3` init: type `string | undefined` is not assignable to type `number`",
  ])
}

///|
/// An imported value whose initializer spreads other values has a shape
/// the importer cannot see: excalidraw's `MIME_TYPES = { ...STRING_MIME_TYPES,
/// "excalidraw.svg": …, ...IMAGE_MIME_TYPES } as const` read as having no
/// `svg` and no `text`, because each spread was recorded as a member named
/// `@@spread:N`. Such a value is `any` to its importers; one with no spread
/// keeps its shape.
test "an imported value built from spreads is not missing their members" {
  assert_eq(
    graph_messages(
      [
        (
          "/src/c.ts", "export const IMG = { svg: \"s\" } as const;\nexport const MIME = { ...IMG, \"x.svg\": \"v\" } as const;\nexport const PLAIN = { a: 1 };",
        ),
        (
          "/src/u.ts", "import { MIME, PLAIN } from \"./c\";\nexport const s: string = MIME.svg;\nexport const bad: string = PLAIN.a;",
        ),
      ],
      [("/src/u.ts", "./c", "/src/c.ts")],
    ),
    ["top-level > binding `bad` init :: expected `string` but got `number`"],
  )
}

///|
/// TS2537: a computed destructuring key of type `string` or `number` reads
/// through an index signature, and a source declaring none has nothing to
/// read. A literal key names a member, an index signature or an array
/// answers, and `any` answers anything. `objectRest` had been flagged only
/// by the private-member false positive this batch removed; this is its
/// real error.
test "a computed destructuring key needs an index signature" {
  let src =
    #|var o = { a: 1, b: 'no' };
    #|let computed = 'b';
    #|const lit = 'b';
    #|var { [computed]: bad1 } = o;
    #|var { [lit]: ok1 } = o;
    #|declare const r: Record<string, number>;
    #|var { [computed]: ok2 } = r;
    #|declare const an: any;
    #|var { [computed]: ok3 } = an;
    #|declare const ix: { [k: string]: number; a: number };
    #|var { [computed]: ok4 } = ix;
    #|declare const n: number;
    #|declare const arr: number[];
    #|var { [n]: ok5 } = arr;
    #|class C { a = 1 }
    #|var { [n]: bad2 } = new C();
    #|const K = { a: "a" };
    #|const { [K.a]: ok6 } = (() => { return { [K.a]: 1 }; })();
  assert_eq(issue_lines(src), [
    "top-level > destructure `[computed]`: type `{ a: number; b: string }` has no matching index signature for type `string`",
    "top-level > destructure `[computed]`: type `C` has no matching index signature for type `number`",
  ])
}

///|
/// An imported arrow-`const` type guard keeps its optional and defaulted
/// parameters omittable: excalidraw's `isBindingElement = <T>(element?: T |
/// null, includeLocked = true): element is … =>` read as "expected 2
/// argument(s), got 1" at every one-argument call. Too many is still TS2554.
test "an imported arrow guard's defaulted parameter may be omitted" {
  assert_eq(
    graph_messages(
      [
        (
          "/src/t.ts", "interface El { locked: boolean }\nexport const isB = <T extends El>(element?: T | null, includeLocked = true): element is T => element != null && includeLocked;",
        ),
        (
          "/src/u.ts", "import { isB } from \"./t\";\ndeclare const e: { locked: boolean };\nexport const one: boolean = isB(e);\ndeclare const m: { locked: boolean } | null;\nexport const nul: boolean = isB(m);\nexport const three: boolean = isB(e, false, 3);",
        ),
      ],
      [("/src/u.ts", "./t", "/src/t.ts")],
    ),
    ["top-level > call `isB` :: expected 0-2 argument(s), got 3"],
  )
}

///|
/// A dependency declaration file that does not parse is untyped, not
/// missing: its importers bind its names as `any`. The edge used to stay,
/// pointing at a module the graph does not hold, and every importer read
/// "resolved module … is absent". A checked file that does not parse is
/// still a parse error.
test "an import of an unparsable dependency declaration is untyped" {
  let dep = "/node_modules/dep/index.d.ts"
  let issues = collect_module_graph_issues(
    {
      modules: [
        {
          path: "/src/root.ts",
          source: "import { x } from \"dep\";\nexport const n: number = x;",
          allowJsx: false,
        },
        {
          path: dep,
          source: "export declare const x: number = ;;; }{",
          allowJsx: false,
        },
      ],
      edges: [
        {
          importerPath: "/src/root.ts",
          moduleSpecifier: "dep",
          targetPath: dep,
        },
      ],
    },
    context_only=Map([(dep, ())]),
  )
  assert_eq(issues.map(fn(i) { i.path + " :: " + i.message }), [])
}

///|
/// A constructor overload's parameter types are written in the declaring
/// module's scope like the rest of the class, so a name two modules declare
/// is renamed in every overload: `Box`'s `Item` is module `a`'s, whatever
/// the importer calls `Item`.
test "a declare class's constructor overloads keep their module's names" {
  assert_eq(
    graph_messages(
      [
        (
          "/src/a.ts", "export interface Item { a: string }\nexport declare class Box { constructor(i: Item); constructor(i: Item, n: number); }",
        ),
        ("/src/b.ts", "export interface Item { b: number }"),
        (
          "/src/root.ts", "import { Box } from \"./a\";\nimport type { Item } from \"./b\";\nexport const box = new Box({ a: \"x\" });\nexport const two = new Box({ a: \"x\" }, 1);\nexport const it: Item = { b: 1 };",
        ),
      ],
      [
        ("/src/root.ts", "./a", "/src/a.ts"),
        ("/src/root.ts", "./b", "/src/b.ts"),
      ],
    ),
    [],
  )
}

///|
/// `any | undefined` is `any` on either side of a relation: the spelling of
/// a defaulted `any` parameter flows into a `string` as `any` does.
test "an any union as a source is any" {
  assert_true(@checker.is_assignable_to(Union([Any, Undefined]), String_))
  assert_false(@checker.is_assignable_to(Union([Number, Undefined]), String_))
}

///|
/// A defaulted `any` parameter takes any argument, a `Partial<T>` included:
/// the parameter is `any | undefined`, and the Partial / Required lattice
/// read its core through `equivalent`, which calls `any` equivalent to
/// every type (univer's `Tools.isEmptyObject(value?: any)`).
test "a defaulted any parameter accepts a Partial argument" {
  let src =
    #|interface D { id: string; n: number }
    #|class Tools {
    #|  static isEmptyObject(value: any = {}): boolean { return Object.keys(value).length === 0; }
    #|}
    #|export function f(d: Partial<D>): boolean { return Tools.isEmptyObject(d); }
    #|export function g(d: D): boolean { return Tools.isEmptyObject(d, 1); }
  assert_eq(issue_lines(src), [
    "function g > call `isEmptyObject`: expected 0-1 argument(s), got 2",
  ])
}
