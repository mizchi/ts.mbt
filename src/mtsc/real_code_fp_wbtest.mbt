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
  // A relative import of one is skipped the same way, not reported as an
  // unresolved local module.
  let vendor = "/src/vendor.d.ts"
  let relative = collect_module_graph_issues(
    {
      modules: [
        {
          path: "/src/root.ts",
          source: "import { x } from \"./vendor\";\nexport const n: number = x;",
          allowJsx: false,
        },
        {
          path: vendor,
          source: "export declare const x: number = ;;; }{",
          allowJsx: false,
        },
      ],
      edges: [
        {
          importerPath: "/src/root.ts",
          moduleSpecifier: "./vendor",
          targetPath: vendor,
        },
      ],
    },
    context_only=Map([(vendor, ())]),
  )
  assert_eq(relative.map(fn(i) { i.path + " :: " + i.message }), [])
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

///|
/// An import binds its name in the importing module's own scope, which a
/// global never overrides: beside `declare global { const shadowed:
/// number }` in another file, `import { shadowed } from "./other"` is the
/// import's `string`. The ambient entry used to be pushed after the import
/// and won.
test "an import shadows a global of the same name" {
  assert_eq(
    graph_messages(
      [
        (
          "/src/globals.d.ts", "export {};\ndeclare global { const shadowed: number }",
        ),
        ("/src/other.ts", "export const shadowed: string = \"s\";"),
        (
          "/src/imp.ts", "import { shadowed } from \"./other\";\nexport const s: string = shadowed;\nexport const bad: number = shadowed;",
        ),
        ("/src/plain.ts", "export const g: number = shadowed;"),
        // The module's own declaration shadows the global the same way,
        // in both spellings, and a function body is where it showed.
        (
          "/src/local.ts", "export declare const shadowed: string;\nexport function f(): string { return shadowed }",
        ),
        (
          "/src/local2.ts", "export const shadowed = \"s\";\nexport function g(): string { return shadowed }",
        ),
      ],
      [("/src/imp.ts", "./other", "/src/other.ts")],
    ),
    ["top-level > binding `bad` init :: expected `number` but got `string`"],
  )
}

///|
/// A recursive array alias unwraps to an array of itself, so relating its
/// elements never bottomed out and the check hung. tsc assumes a pair it
/// is already comparing is related, so `A[]` assigns to `B[]`, while `A[]`
/// against `string[]` fails where `A` meets `string`.
test "a recursive array alias relates to its twin" {
  assert_eq(
    issue_lines(
      "type A = A[];\ntype B = B[];\ndeclare const a: A[];\nexport const ok: B[] = a;\nexport const bad: string[] = a;",
    ),
    ["top-level > binding `bad` init: expected `string[]` but got `A[]`"],
  )
}

///|
/// An accessor pair carries one visibility per half: a read reaches the
/// getter and a write the setter. univer's `BaseObject` declares `get
/// left()` beside `protected set left(v)`, and every outside read of
/// `object.left` was reported. Writing it outside the class is still an
/// error, and so is `+=`, which reads and then writes. A plain `protected`
/// field under `+=` is reported once, not once per half.
test "a public getter beside a protected setter is readable" {
  assert_eq(
    issue_lines(
      "class B {\n  private _l = 0;\n  protected x = 0;\n  get left(): number { return this._l }\n  protected set left(v: number) { this._l = v }\n}\nclass D extends B { m() { this.left = 2; this.left += 1; return this.left; } }\ndeclare const b: B;\nfunction okRead() { const n: number = b.left; }\nfunction okDestructure() { const { left } = b; }\nfunction badWrite() { b.left = 1; }\nfunction badCompound() { b.left += 1; }\nfunction badField() { b.x += 1; }",
    ),
    [
      "function badWrite > access `.left`: property `left` is protected and only accessible within class `B` and its subclasses",
      "function badCompound > access `.left`: property `left` is protected and only accessible within class `B` and its subclasses",
      "function badField > access `.x`: property `x` is protected and only accessible within class `B` and its subclasses",
    ],
  )
}

///|
/// `x!` removes `null`, `undefined` and `void`, and it applies to what an
/// alias stands for. univer's lookups return `Nullable<T> = T | null |
/// undefined | void`, and `m.getValue(r)!` kept all three, so every read
/// of the asserted value was "possibly undefined". Without `!` it still is.
test "a non-null assertion strips an aliased nullish union" {
  assert_eq(
    issue_lines(
      "type Nullable<T> = T | null | undefined | void;\ninterface V { b: number }\ndeclare class M<T> { getValue(r: number): Nullable<T>; }\ndeclare const m: M<V>;\ndeclare const v: string | void;\nfunction okVoid() { const s: string = v!; }\nfunction okMethod() { const c = m.getValue(1)!; const n: number = c.b; }\nfunction badNoAssertion() { const c = m.getValue(1); const n = c.b; }",
    ),
    [
      "function badNoAssertion > PropAccess `.b`: object is possibly `undefined`",
    ],
  )
}

///|
/// A type guard narrows its subject through a static method called on its
/// class and through a property path or an optional chain. univer guards
/// every optional read with `Tools.isDefine(props?.top)`, and neither the
/// static call nor the chain narrowed anything. A sibling member the guard
/// did not test is still possibly undefined.
test "a static guard narrows a path and an optional chain" {
  assert_eq(
    issue_lines(
      "class Tools { static isDefine<T>(value?: T | void): value is T { return value !== undefined && value !== null } }\ninterface P { top?: number; other?: number }\nfunction okStatic(x: number | undefined) { let t = 0; if (Tools.isDefine(x)) { t = x; } }\nfunction okPath(props: P) { let t = 0; if (Tools.isDefine(props.top)) { t = props.top; } }\nfunction okChain(props?: P) { let t = 0; if (Tools.isDefine(props?.top)) { t = props.top; } }\nfunction badSibling(props?: P) { let t = 0; if (Tools.isDefine(props?.top)) { t = props.other; } }",
    ),
    [
      "function badSibling > assign `t`: type `number | undefined` is not assignable to type `number`",
    ],
  )
}

///|
/// The false branch of a guard keeps `any` as `any`: there is no member to
/// remove. It used to remove "every member that fits", which emptied an
/// `any` to `never`, so `isFiniteNumber(a) ? a : a.value` reported `value`
/// on `never`. excalidraw's `restoreAppState` reaches the same shape
/// through a path. An optional `any` (`any | undefined`) is `any` as well,
/// as a receiver and as a guard's subject. An `unknown` stays `unknown`.
test "a guard's false branch and a member read keep any as any" {
  assert_eq(
    issue_lines(
      "declare const isFiniteNumber: (value: any) => value is number;\ndeclare const a: any;\ndeclare const u: unknown;\ninterface S { zoom?: any }\ndeclare const s: S;\nfunction okAny() { const v = isFiniteNumber(a) ? a : a.value; }\nfunction okPath() { const v = isFiniteNumber(s.zoom) ? s.zoom : s.zoom.value; }\nfunction okOptionalParam(p?: any) { return p.value; }\nfunction badUnknown() { const v = isFiniteNumber(u) ? u : u.value; }",
    ),
    [
      "function badUnknown > PropAccess `.value`: property `value` does not exist on `unknown`",
      "function badUnknown > PropAccess `.value`: property `value` does not exist on `unknown`",
    ],
  )
}

///|
/// A `declare global` value's type is written in its declaring module's
/// scope. Where that module is not reachable, `Payload` used to resolve
/// against the checked module's own `Payload`, so `payload.a` and
/// `take({ a: "x" })` were reported on legal lines. The reference abstains
/// there now. Where the module is reachable, it resolves to the right
/// declaration and the real mismatch is still reported.
test "a declare global value's type stays in its declaring module's scope" {
  let globals = (
    "/src/globals.d.ts", "export {};\ninterface Payload { a: string }\ndeclare global { const payload: Payload; function take(p: Payload): void }",
  )
  let body = "interface Payload { b: number }\nexport const ok: string = payload.a;\nexport function g() { take({ a: \"x\" }); }\nexport const bad: number = payload.a;"
  assert_eq(graph_messages([globals, ("/src/root.ts", body)], []), [])
  assert_eq(
    graph_messages(
      [globals, ("/src/root.ts", "import type {} from \"./globals\";\n" + body)],
      [("/src/root.ts", "./globals", "/src/globals.d.ts")],
    ),
    ["top-level > binding `bad` init :: expected `number` but got `string`"],
  )
}

///|
/// Three follow-ups from the review of #298. `++` and `--` write as well as
/// read, so a protected setter still decides them. A nullish constituent
/// can itself be an alias (`type Nothing = void`), and `x!` removes it.
/// And an `unknown` or `any` guard result proves nothing about the `?.`
/// receivers, so `o` stays possibly undefined.
test "increment, an aliased void under !, and an unproven guard result" {
  assert_eq(
    issue_lines(
      "class B { private _l = 0; get left(): number { return this._l } protected set left(v: number) { this._l = v } }\ndeclare const b: B;\ntype Nothing = void;\ntype Maybe = string | Nothing;\ndeclare function accepts(x: unknown): x is unknown;\ndeclare const o: { p?: any; q: number } | undefined;\nfunction badInc() { b.left++; }\nfunction okAlias(x: Maybe): string { return x!; }\nfunction badUnproven() { if (accepts(o?.p)) { const n = o.q; } }",
    ),
    [
      "function badInc > access `.left`: property `left` is protected and only accessible within class `B` and its subclasses",
      "function badUnproven > PropAccess `.q`: object is possibly `undefined`",
    ],
  )
}

///|
/// A qualified name in an unreachable declaring module's scope
/// (`Models.Payload`) moves with the bare ones, so it cannot resolve to the
/// checked module's own `Models.Payload`.
test "a declare global value's qualified type stays in its module's scope" {
  assert_eq(
    graph_messages(
      [
        (
          "/src/globals.d.ts", "export {};\ndeclare namespace Models { interface Payload { a: string } }\ndeclare global { const payload: Models.Payload }",
        ),
        (
          "/src/root.ts", "declare namespace Models { interface Payload { b: number } }\nexport const ok: string = payload.a;",
        ),
      ],
      [],
    ),
    [],
  )
}

///|
/// Destructuring a reference reads each property through what control
/// flow knows about it: after `if (!body.tables) body.tables = []`,
/// `const { tables } = body` is the narrowed array (univer's text-model
/// helpers, 96 reports in one file). A sibling property, an unguarded read
/// and a read after the source was reassigned keep the optional type.
test "destructuring reads a narrowed property" {
  assert_eq(
    issue_lines(
      "interface B { tables?: number[]; other?: number[] }\nfunction okAssigned(body: B) { if (!body.tables) { body.tables = []; } const { tables } = body; tables.push(1); }\nfunction okRenamed(body: B) { if (body.tables) { const { tables: t } = body; t.push(1); } }\nfunction badSibling(body: B) { if (!body.tables) { body.tables = []; } const { other } = body; other.push(1); }\nfunction badReassigned(body: B, next: B) { if (body.tables) { body = next; const { tables } = body; tables.push(1); } }",
    ),
    [
      "function badSibling > call `push`: object is possibly `undefined`", "function badReassigned > call `push`: object is possibly `undefined`",
    ],
  )
}

///|
/// A function value takes its parameter types from where it is assigned,
/// and a guard narrows those: after `isObject(color)` on `string | Color`
/// the parameter is `Color` (univer's `toColor` in `color-kit.ts`). The
/// body used to be walked with the parameters as `any` as well, where the
/// guard narrows to `object`, so `"r" in color` read as `{ r: unknown }`.
/// The `bad` lines keep a real error under each guard.
test "a guard narrows a contextually typed parameter, not any" {
  assert_eq(
    issue_lines(
      "interface IRgb { r: number; g: number }\ninterface IHsl { h: number; l: number }\ntype Color = IRgb | IHsl;\nconst isObject = (value: unknown): value is object => typeof value === \"object\" && value !== null;\ntype ToNumber = (color: string | Color) => number;\nconst okArrow: ToNumber = (color) => { if (isObject(color)) { if (\"r\" in color) { return color.g; } } return 0; };\nconst okMember: { f: ToNumber } = { f: (color) => { if (isObject(color)) { if (\"r\" in color) { return color.g; } } return 0; } };\nconst okElement: ToNumber[] = [(color) => { if (isObject(color)) { if (\"r\" in color) { return color.g; } } return 0; }];\nfunction okReturned(): ToNumber { return (color) => { if (isObject(color)) { if (\"r\" in color) { return color.g; } } return 0; }; }\nconst okFuncExpr: ToNumber = function (color) { if (isObject(color)) { if (\"r\" in color) { return color.g; } } return 0; };\nfunction badReturned(): ToNumber { return (color) => { if (isObject(color)) { if (\"r\" in color) { return color.l; } } return 0; }; }",
    ),
    [
      "function badReturned > PropAccess `.l`: property `l` does not exist on `IRgb`",
    ],
  )
}

///|
/// A bare `return;` and falling off the end are legal when the return type
/// admits `undefined` or `void`, through an alias too. univer's lookups are
/// typed `Nullable<T> = T | null | undefined | void` (100 reports). An alias
/// admitting only `null` still requires a value.
test "a return type alias admitting undefined allows no value" {
  assert_eq(
    issue_lines(
      "type Nullable<T> = T | null | undefined | void;\ntype OnlyNull<T> = T | null;\nfunction okBare(d: number | null): Nullable<string> { if (d == null) return; return \"x\"; }\nfunction okFallOff(d: number | null): Nullable<string> { if (d != null) return \"x\"; }\nfunction badBare(d: number | null): OnlyNull<string> { if (d == null) return; return \"x\"; }\nfunction badFallOff(d: number | null): OnlyNull<string> { if (d != null) return \"x\"; }",
    ),
    [
      "function badBare > return: expected `OnlyNull<string>` but no value returned",
      "function badFallOff: not all paths return a `OnlyNull<string>`",
    ],
  )
}

///|
/// An optional chain ending in a call narrows its receivers as a property
/// chain does: `x?.ok()` is `undefined` whenever `x` is nullish. Two arms
/// missed it, one per AST shape: `x?.ok()` is a `CallExpr` the chain walk
/// stopped at, and `x?.inner.has()` is a `MethodCall` the condition walk
/// sent to type-predicate narrowing only (univer's AST helpers and value
/// objects). The falsy branch and a `|| b` still prove nothing.
test "an optional chain ending in a call narrows its receivers" {
  assert_eq(
    issue_lines(
      "interface N { getParent(): N | undefined; ok(): boolean; v: number; inner: { has(): boolean } }\ntype Nullable<T> = T | null | undefined | void;\nfunction okIf(x: N | undefined) { if (x?.ok()) { return x.v; } return 0; }\nfunction okWhile(node: N) { let p: Nullable<N> = node; while (p?.getParent()) { p = p.getParent(); } return p; }\nfunction okNested(x: N | undefined) { if (x?.inner.has()) { return x.v; } return 0; }\nfunction badFalsy(x: N | undefined) { if (!x?.ok()) { return x.v; } return 0; }\nfunction badOr(x: N | undefined, b: boolean) { if (x?.ok() || b) { return x.v; } return 0; }",
    ),
    [
      "function badFalsy > PropAccess `.v`: object is possibly `undefined`", "function badOr > PropAccess `.v`: object is possibly `undefined`",
    ],
  )
}

///|
/// A trailing parameter accepting `void` may be omitted, through an alias
/// too: univer's `slice(row: Nullable<…>, col: Nullable<…>)` called with one
/// argument. A `T | undefined` alias is still required, as is a
/// void-accepting parameter before a required one.
test "a trailing parameter whose alias accepts void may be omitted" {
  assert_eq(
    issue_lines(
      "type Nullable<T> = T | null | undefined | void;\ntype MaybeU<T> = T | undefined;\ndeclare function fN(a: number, b: Nullable<number>): void;\ndeclare function fU(a: number, b: MaybeU<number>): void;\ndeclare function fM(a: Nullable<number>, b: number): void;\nfunction okOmitted() { fN(1); }\nfunction badUndefinedAlias() { fU(1); }\nfunction badMiddle() { fM(1); }",
    ),
    [
      "function badUndefinedAlias > call `fU`: expected 2 argument(s), got 1", "function badMiddle > call `fM`: expected 2 argument(s), got 1",
    ],
  )
}

///|
/// Under `noImplicitAny` an unannotated `let` / `var` initialized with
/// `null` or `undefined` is declared `any` and evolves (univer's
/// `let errorValue = null`). A read before any assignment still sees `null`,
/// and `void 0`, a `const` and `let e: null` are not auto-typed.
test "a let initialized with null is auto-typed" {
  assert_eq(
    issue_lines(
      "interface V { a: number }\ndeclare const v: V;\nfunction okLet() { let e = null; e = v; return e; }\nfunction okInCallback(xs: V[]) { let e = undefined; xs.forEach((x) => { e = x; }); return e; }\nfunction badRead() { let e = null; return e.a; }\nfunction badVoidZero() { let e = void 0; e = v; return e; }\nfunction badAnnotated() { let e: null = null; e = v; return e; }",
    ),
    [
      "function badRead > PropAccess `.a`: cannot access `.a` — receiver may be null or undefined",
      "function badVoidZero > assign `e`: expected `undefined` but got `V`", "function badAnnotated > assign `e`: expected `null` but got `V`",
    ],
  )
}

///|
/// A method overload set declared on a generic base class is inherited
/// whole, with the base's `T` from the receiver: rxjs's `Subject<T> extends
/// Observable<T>` declares no `pipe` (24 univer reports of "expected 0
/// argument(s)"). Three things were missing: the overload count walked
/// interfaces only, the candidates kept the class's raw `T` (so even an
/// `Observable<number>` receiver selected `pipe(): Observable<T>`), and a
/// `declare class` did not record its `extends B<…>` arguments. An override
/// with one signature hides the set.
test "an inherited overload set on a generic base class" {
  assert_eq(
    issue_lines(
      "interface Op<T, R> { (source: Obs<T>): Obs<R> }\ndeclare class Obs<T> { readonly last: T; pipe(): Obs<T>; pipe<A>(op1: Op<T, A>): Obs<A>; }\ndeclare class Sub<T> extends Obs<T> { next(v: T): void }\ndeclare class Narrow<T> extends Obs<T> { pipe(): Obs<T> }\ndeclare function take<T>(n: number): Op<T, T>;\ndeclare function toStr(): Op<number, string>;\nfunction okInherited(s: Sub<number>) { return s.pipe(take(1)); }\nfunction okReturn(s: Sub<number>): Obs<string> { return s.pipe(toStr()); }\nfunction okDirect(s: Obs<number>): Obs<string> { return s.pipe(toStr()); }\nfunction badOverride(s: Narrow<number>) { return s.pipe(take(1)); }\nfunction badReturn(s: Sub<number>): Obs<number> { return s.pipe(toStr()); }",
    ),
    [
      "function badOverride > call `pipe`: expected 0 argument(s), got 1", "function badReturn > return: expected `Obs<number>` but got `Obs<string>`",
    ],
  )
}

///|
/// The three findings from the review of #299. A scalar alias for `void`
/// inside a union still makes a trailing parameter omissible. An assignment
/// inside an object literal's entry is applied before the literal is
/// judged, while a function value in it is still checked in context. And an
/// alias for `unknown` proves nothing about the `?.` receivers.
test "review of #299: void member alias, literal walk order, aliased unknown" {
  assert_eq(
    issue_lines(
      "type V = void;\ndeclare function f(a: number, b: number | V): void;\nfunction okScalarVoid() { f(1); }\ndeclare function isObject(v: unknown): v is object;\ninterface R { r: number; g: number }\nfunction okAssignInLiteral() { let x: string | number = 0; const y: { value: string } | { other: number } = { value: (x = \"ok\", x) }; return y; }\nfunction okNested() { const o: { a: { f: (c: string | R) => number } } = { a: { f: (c) => { if (isObject(c)) { if (\"r\" in c) { return c.g; } } return 0; } } }; return o; }\ntype Top = unknown;\ndeclare function acceptsTop(x: unknown): x is Top;\ndeclare const lo: { p: unknown; q: number } | undefined;\nfunction badAliasedUnknown() { if (acceptsTop(lo?.p)) { const n = lo.q; } }",
    ),
    [
      "function badAliasedUnknown > PropAccess `.q`: object is possibly `undefined`",
    ],
  )
}

///|
/// Assigning a static factory called through its class narrows a nullable
/// binding (univer's `v = NumberValueObject.create(0)` after `v == null`),
/// also when the binding is declared through an alias (`let w = v` with
/// `v: Nullable<…>`). The call itself is still `any`, so a mismatch through
/// it is a MISS, and an assignment of a value typed `any` keeps the declared
/// type, as tsc has it.
test "a static factory assignment narrows a nullable binding" {
  assert_eq(
    issue_lines(
      "type Nullable<T> = T | null | undefined | void;\nclass BaseValue { isNull(): boolean { return false; } isBool(): boolean { return false; } }\nclass NumberValue extends BaseValue { static create(n: number): NumberValue { return new NumberValue(); } }\ndeclare const anything: any;\nfunction okNarrows(v: Nullable<BaseValue>) { let w = v; if (w == null || w.isNull()) { w = NumberValue.create(0); } return w.isBool(); }\nfunction badMismatch() { const s: string = NumberValue.create(3); return s; }\nfunction badAny(v: BaseValue | undefined) { v = anything; return v.isBool(); }\ndeclare const AnyCtor: any;\nfunction okAutoTypedAnyNew() { let b = null; b = new AnyCtor(); return b.width; }",
    ),
    ["function badAny > call `isBool`: object is possibly `undefined`"],
  )
}
