// Recall gaps the mutation differential (`just verify-mutations`) found on
// `fixtures/real-app/ok`: each edit there is one tsc reports and mtsc did
// not. Every expected list below is what tsc reports on the same files,
// probed one project per case, and each pairs the illegal spelling with
// the legal neighbour that must stay silent.

///|
/// An IMPORTED generic function's argument COUNT is judged the way a local
/// one's is. Its value arrives as a binder over the raw signature, and that
/// arm checked only binder-free parameter types, so every date-fns call
/// (`addDays(d)`) took any number of arguments.
///
/// A REST parameter, written as an array or as a `Parameters<…>` tuple,
/// takes any count here (testing-library's `queryByTestId(container, id)`
/// and excalidraw's `polygon(a, b, c, d)` were both "expected 1" in the
/// first version of this rule).
///
/// `und(1)` is TS2554 in tsc and stays silent here: the imported signature
/// spells `u?: number` as `number | undefined`, so it cannot tell that
/// parameter from a required `u: number | undefined`. That MISS is the
/// affordable direction.
test "an imported generic function's argument count is checked" {
  assert_eq(
    graph_messages(
      [
        (
          "/src/g.d.ts", "type V = void;\ntype T = void;\nexport declare function shadow<T>(x: T): T;\nexport declare function vu<T>(x: T, v: number | void): T;\nexport declare function va<T>(x: T, v: number | V): T;\nexport declare const vm: <T>(x: T, v: number | void, w?: string) => T;\nexport declare function two<T>(x: T, n: number): T;\nexport declare function opt<T>(x: T, n?: number): T;\nexport declare function rest<T>(x: T, ...more: number[]): T;\nexport declare function tup<T extends unknown[]>(...args: T): T;\nexport declare function vparam<T>(x: T, v: void): T;\nexport declare function und<T>(x: T, u: number | undefined): T;\nexport declare function bare<T>(x: T): T;",
        ),
        (
          "/src/poly.ts", "export function poly<P extends number>(...points: P[]) { return points; }\nexport function pq<T extends string = string>(...args: Parameters<(a: number, b?: string) => T>): T { return \"\" as T; }",
        ),
        (
          "/src/main.ts", "import { two, opt, rest, tup, vparam, und, bare, vu, va, vm, shadow } from \"./g\";\nexport const ok12 = vu(1);\nexport const ok13 = va(1);\nexport const ok14 = vm(1);\nexport const bad7 = vm();\nexport const bad8 = shadow();\nimport { poly, pq } from \"./poly\";\nexport const ok9 = poly(1, 2, 3, 4);\nexport const ok10 = poly();\nexport const ok11 = pq(1, \"s\");\nexport const bad1 = two(1);\nexport const bad2 = two(1, 2, 3);\nexport const bad3 = opt(1, 2, 3);\nexport const bad4 = rest();\nexport const bad5 = und(1);\nexport const bad6 = bare();\nexport const ok1 = two(1, 2);\nexport const ok2 = opt(1);\nexport const ok3 = rest(1);\nexport const ok4 = rest(1, 2, 3, 4);\nexport const ok5 = tup();\nexport const ok6 = tup(1, \"a\");\nexport const ok7 = vparam(1);\nexport const ok8 = und(1, undefined);",
        ),
      ],
      [
        ("/src/main.ts", "./g", "/src/g.d.ts"),
        ("/src/main.ts", "./poly", "/src/poly.ts"),
      ],
    ),
    [
      "top-level > call `vm` :: expected 1-3 argument(s), got 0", "top-level > call `shadow` :: expected 1 argument(s), got 0",
      "top-level > call `two` :: expected 2 argument(s), got 1", "top-level > call `two` :: expected 2 argument(s), got 3",
      "top-level > call `opt` :: expected 1-2 argument(s), got 3", "top-level > call `rest` :: expected at least 1 argument(s), got 0",
      "top-level > call `bare` :: expected 1 argument(s), got 0",
    ],
  )
}

///|
/// A class whose base is a RENAMED import (`import { Base as B$1 }`, the
/// spelling a bundled `.d.ts` uses) resolves that base, so its inherited
/// members are known and an absent one is reported.
test "a class extending a renamed import resolves its base" {
  assert_eq(
    graph_messages(
      [
        (
          "/src/base.d.ts", "export declare class Base<E = {}> { m(x: number): void; p: string }",
        ),
        (
          "/src/derived.d.ts", "import { Base as B$1 } from \"./base\";\nexport declare class D<E = {}> extends B$1<E> { constructor(o?: number) }",
        ),
        (
          "/src/main.ts", "import { D } from \"./derived\";\ndeclare const d: D;\nexport const bad1 = d.nope;\nd.m(\"x\");\nd.m(1);\nexport const ok: string = d.p;",
        ),
      ],
      [
        ("/src/derived.d.ts", "./base", "/src/base.d.ts"),
        ("/src/main.ts", "./derived", "/src/derived.d.ts"),
      ],
    ),
    [
      "top-level > PropAccess `.nope` :: property `nope` does not exist on `D`",
      "top-level > call `m` arg[0] :: expected `number` but got `string`",
    ],
  )
}

///|
/// A namespace object whose export list is complete has no index
/// signature, so a typo'd member is TS2339 (`z.objectt`). A member the
/// checker cannot type (a class value) is still a member.
test "a complete namespace object reports an absent member" {
  assert_eq(
    graph_messages(
      [
        (
          "/src/inner.d.ts", "export declare const k: string;\nexport declare class C {}\nexport declare enum E { A }",
        ),
        (
          "/src/d.d.ts", "export * from \"./inner\";\nexport declare function f(): void;",
        ),
        (
          "/src/main.ts", "import * as D from \"./d\";\nexport const bad1 = D.nope;\nexport const ok1 = D.k;\nexport const ok2 = new D.C();\nexport const ok3 = D.E.A;\nD.f();",
        ),
      ],
      [
        ("/src/d.d.ts", "./inner", "/src/inner.d.ts"),
        ("/src/main.ts", "./d", "/src/d.d.ts"),
      ],
    ),
    [
      "top-level > PropAccess `.nope` :: property `nope` does not exist on `{ f: () => void; k: string; E: E; C: any }`",
    ],
  )
}

///|
/// The list is open — an unlisted member reads as unknown — whenever a name
/// could come from somewhere the graph does not see: an `export *` of a
/// module it does not hold, a `.ts` source (its exports can take shapes
/// the list does not enumerate), and an augmentation that can name the
/// module, since `declare module "./d" { export const added: string }`
/// makes `D.added` legal. An ambient module of ANOTHER name (`@types/node`
/// declares fifty) does not open it.
test "a namespace object stays open while a name could come from elsewhere" {
  let open_cases = [
    (
      [
        (
          "/src/d.d.ts", "export * from \"./gone\";\nexport declare const k: string;",
        ),
        (
          "/src/main.ts", "import * as D from \"./d\";\nexport const x = D.nope;",
        ),
      ],
      [("/src/main.ts", "./d", "/src/d.d.ts")],
    ),
    (
      [
        ("/src/d.ts", "export const k = 1;"),
        (
          "/src/main.ts", "import * as D from \"./d\";\nexport const x = D.nope;",
        ),
      ],
      [("/src/main.ts", "./d", "/src/d.ts")],
    ),
    (
      [
        ("/src/d.d.ts", "export declare const k: string;"),
        (
          "/src/aug.ts", "export {};\ndeclare module \"./d\" { export const added: string; }",
        ),
        (
          "/src/main.ts", "import * as D from \"./d\";\nexport const x: string = D.added;",
        ),
      ],
      [("/src/main.ts", "./d", "/src/d.d.ts")],
    ),
    (
      [
        ("/src/d.d.ts", "export declare const k: string;"),
        (
          "/src/aug.ts", "export {};\ndeclare module \"./d\" { export const added: string; }",
        ),
        (
          "/src/main.ts", "import * as D from \"./d\";\nexport const x: string = D.added;",
        ),
      ],
      [
        ("/src/main.ts", "./d", "/src/d.d.ts"),
        ("/src/aug.ts", "./d", "/src/d.d.ts"),
      ],
    ),
  ]
  // An augmentation of a module the barrel reaches through `export *`.
  open_cases.push(
    (
      [
        ("/src/base.d.ts", "export declare const k: string;"),
        ("/src/barrel.d.ts", "export * from \"./base\";"),
        (
          "/src/aug.ts", "export {};\ndeclare module \"./base\" { export const added: string; }",
        ),
        (
          "/src/main.ts", "import * as B from \"./barrel\";\nexport const x: string = B.added;",
        ),
      ],
      [
        ("/src/barrel.d.ts", "./base", "/src/base.d.ts"),
        ("/src/main.ts", "./barrel", "/src/barrel.d.ts"),
      ],
    ),
  )
  for c in open_cases {
    assert_eq(graph_messages(c.0, c.1), [])
  }
  assert_eq(
    graph_messages(
      [
        ("/src/d.d.ts", "export declare const k: string;"),
        (
          "/types/node.d.ts", "declare module \"assert\" { export function ok(v: unknown): void; }",
        ),
        (
          "/src/main.ts", "import * as D from \"./d\";\nexport const x = D.nope;",
        ),
      ],
      [("/src/main.ts", "./d", "/src/d.d.ts")],
    ),
    [
      "top-level > PropAccess `.nope` :: property `nope` does not exist on `{ k: string }`",
    ],
  )
}

///|
/// Inference to a union target with ONE naked type parameter takes the
/// argument as that parameter's candidate once the members another
/// member matches are taken out, as tsc's `inferToMultipleTypes` does:
/// `S | (() => S)` (`useState`), `S | undefined` and `S | S[]` all infer
/// `S` from a plain argument. Before, the structural pass tried only the
/// non-naked member and left `S` as `any`, so a hook's state was
/// unchecked. A fresh literal argument widens, since `S` is not at the top
/// level of a tuple return: `hook("light")` is `string`, and leaving it
/// `"light"` would make `mode === "dark"` look impossible.
test "a naked type parameter in a union target infers from the argument" {
  let src =
    #|declare function one<S>(x: S | (() => S)): S;
    #|declare function opt<S>(x: S | undefined): S;
    #|declare function many<S>(x: S | S[]): S;
    #|declare function hook<S>(init: S | (() => S)): [S, (next: S) => void];
    #|export function okValues() {
    #|  const a: string = one("");
    #|  const b: string = one(() => "");
    #|  const c: string = opt("");
    #|  const d: string = many("");
    #|  const e: string = many([""]);
    #|  const f: { a: number } = one({ a: 1 });
    #|  const g: number[] = one([1]);
    #|  return [a, b, c, d, e, f, g];
    #|}
    #|export function okHookWidens() {
    #|  const [mode, setMode] = hook("light");
    #|  if (mode === "dark") { setMode("light"); }
    #|  setMode("dark");
    #|  return mode;
    #|}
    #|export function badOne() { const n: number = one(""); return n; }
    #|export function badOpt() { const n: number = opt(""); return n; }
    #|export function badObject() { const n: number = one({ a: 1 }); return n; }
    #|export function badState() { const [q] = hook(""); return q.nope; }
  assert_eq(issue_lines(src), [
    "function badOne > binding `n` init: expected `number` but got `string`", "function badOpt > binding `n` init: expected `number` but got `string`",
    "function badObject > binding `n` init: expected `number` but got `{ a: number }`",
    "function badState > PropAccess `.nope`: property `nope` does not exist on `string`",
  ])
}

///|
/// The fallback candidate is one candidate among the call's, not a binding
/// that pins the parameter before the other arguments are seen. Each cell
/// was probed against tsc: the `ok…` functions are accepted, the `bad…`
/// ones report where tsc does.
test "a naked union member's candidate is reduced with the call's others" {
  let src =
    #|declare function pick<T>(x: T | number[]): T;
    #|declare function choose<T>(value: T | (() => T), values: T[]): T;
    #|declare function hookP<S>(init: S | Promise<S>): [S];
    #|declare function hookA<S>(init: S | Array<S>): [S];
    #|declare function hookL<S>(init: S | PromiseLike<S>): [S];
    #|declare function hookR<S>(init: S | ReadonlyArray<S>): [S];
    #|export function okPick(input: string | number[]) {
    #|  const r: string = pick(input);
    #|  return r;
    #|}
    #|export function okChoose(s: string, ss: string[], as_: "a"[], bs: "b"[]) {
    #|  const a: string = choose("a", ss);
    #|  let b = choose("a", ss);
    #|  b = "b";
    #|  const c: string = choose(s, as_);
    #|  const d: "a" | "b" = choose("a", bs);
    #|  return [a, b, c, d];
    #|}
    #|export function okHooks() {
    #|  const [p] = hookP("light");
    #|  const [a] = hookA("light");
    #|  const [l] = hookL("light");
    #|  const [r] = hookR("light");
    #|  return [p === "dark", a === "dark", l === "dark", r === "dark"];
    #|}
    #|export function badPick(input: string | number[]) {
    #|  const n: number = pick(input);
    #|  return n;
    #|}
    #|export function badChoose(ns: number[]) { return choose("a", ns); }
    #|export function badHook() { const [p] = hookP("light"); const n: number = p; return n; }
    #|declare function both<T>(a: T | undefined, b: T | undefined): T;
    #|declare function unwrap<T>(x: T | PromiseLike<T>): T;
    #|export function okRound2(anys: any[], p: { then(f?: (v: number) => any): any }) {
    #|  const u: "a" | "b" = both("a", "b");
    #|  const isB = both("a", "b") === "b";
    #|  const n: number = choose("a", anys);
    #|  const t: number = unwrap(p);
    #|  return [u, isB, n, t];
    #|}
    #|export function badBoth() { return both("a", 1); }
    #|export function badUnwrap() { const s: string = unwrap(5); return s; }
  assert_eq(issue_lines(src), [
    "function badPick > binding `n` init: expected `number` but got `string`", "function badChoose > call `choose` arg[1]: expected `\"a\" (string)[]` but got `number[]`",
    "function badHook > binding `n` init: expected `number` but got `string`", "function badBoth > call `both` arg[1]: expected `\"a\" (string) | undefined` but got `number`",
    "function badUnwrap > binding `s` init: expected `string` but got `number`",
  ])
}

///|
/// A value whose type is an object type or an interface with call
/// signatures is called through them: one signature is checked as a
/// function-typed value is, several as an overload set, and the result is
/// the signature's return. Every such call came back `any` before.
test "a callable object type is called through its call signatures" {
  let src =
    #|interface Express { listen(port: number): void }
    #|declare const q: { (): Express; json: () => number };
    #|declare const r: { (): Express; (x: string): number };
    #|interface CallI { (n: number): string; extra: boolean }
    #|declare const ci: CallI;
    #|export function okCalls() {
    #|  q().listen(1);
    #|  const n: number = r("s");
    #|  const s: string = ci(1);
    #|  return [n, s, q.json(), ci.extra];
    #|}
    #|export function badArity() { return q(1); }
    #|export function badReturn() { q().listen("x"); }
    #|export function badOverload() { return r(1, 2); }
    #|export function badArg() { return ci("x"); }
  assert_eq(issue_lines(src), [
    "function badArity > call `q`: expected 0 argument(s), got 1", "function badReturn > call `listen` arg[0]: expected `number` but got `string`",
    "function badOverload > call `r`: no overload matches this call", "function badArg > call `ci` arg[0]: expected `number` but got `string`",
  ])
}

///|
/// The shape `@types/express` has: a function merged with a namespace,
/// assigned with `export =`, whose namespace interfaces extend a
/// namespace-imported module's and carry type parameters with defaults.
/// The call, the namespace's types imported by name, a renamed import of
/// the base, and member existence on the callable app all check, and a
/// generic interface named without arguments reads its parameters as
/// `any` instead of the raw binder (`res.json(1)` is legal).
test "an export-assigned function merged with a namespace of types" {
  assert_eq(
    graph_messages(
      [
        (
          "/src/core.d.ts", "export interface Request<P = string> { params: P; path: string }\nexport interface Response<B = any> { json(body?: B): this }\nexport interface Express { (req: any, res: any): void; listen(port: number): void }",
        ),
        (
          "/src/e.d.ts", "import * as core from \"./core\";\ndeclare function e(): core.Express;\ndeclare namespace e {\n  var json: () => (req: any, res: any) => void;\n  interface Request<P = string> extends core.Request<P> {}\n  interface Response<B = any> extends core.Response<B> {}\n}\nexport = e;",
        ),
        (
          "/src/main.ts", "import express from \"./e\";\nimport type { Request, Response } from \"./e\";\nimport type { Response as CoreRes } from \"./core\";\nconst app = express();\napp.listen(3000);\ndeclare const req: Request;\ndeclare const res: Response;\ndeclare const cres: CoreRes;\nres.json(1);\ncres.json(1);\nexport const okPath: string = req.path;\nexport const okBind = app.bind;\nexport const bad1 = express(1);\nexport const bad2 = app.lisen;\nexport const bad3 = req.nope;\nexport const bad4 = res.nope;\nexport const bad5: number = req.path;\nexport const bad6 = express.nope;",
        ),
      ],
      [
        ("/src/e.d.ts", "./core", "/src/core.d.ts"),
        ("/src/main.ts", "./e", "/src/e.d.ts"),
        ("/src/main.ts", "./core", "/src/core.d.ts"),
      ],
    ),
    [
      "top-level > call `express` :: expected 0 argument(s), got 1", "top-level > PropAccess `.lisen` :: property `lisen` does not exist on `Express`",
      "top-level > PropAccess `.nope` :: property `nope` does not exist on `Request`",
      "top-level > PropAccess `.nope` :: property `nope` does not exist on `Response`",
      "top-level > binding `bad5` init :: expected `number` but got `string`", "top-level > PropAccess `.nope` :: property `nope` does not exist on `{ <call>: () => Express; json: () => (any, any) => void }`",
    ],
  )
}

///|
/// A computed member key naming a value declared `unique symbol` is a
/// symbol key, which no `.name` access can reach, so it no longer makes
/// the member list undecidable — dotted (`[NS.s]`) or not. A key naming a
/// string `const` or an enum member still might name the accessed
/// member, and still abstains.
test "a symbol-keyed member does not block member existence" {
  let src =
    #|declare const k: unique symbol;
    #|declare namespace NS { const s: unique symbol; const lit: "lit"; }
    #|interface I1 { [k](): void; y: number }
    #|interface I2 { [NS.s]?(): void; y: number }
    #|const kk = "hello";
    #|interface I3 { [kk]: number; y: number }
    #|enum K { A = "a" }
    #|interface I4 { [K.A]: number; y: number }
    #|interface I5 { [NS.lit]: number; y: number }
    #|declare const i1: I1;
    #|declare const i2: I2;
    #|declare const i3: I3;
    #|declare const i4: I4;
    #|declare const i5: I5;
    #|export function okKeys() { return [i3.hello, i4.a, i5.lit, i1.y, i2.y]; }
    #|export function badSymbolKeyed1() { return i1.nope; }
    #|export function badSymbolKeyed2() { return i2.nope; }
  assert_eq(issue_lines(src), [
    "function badSymbolKeyed1 > PropAccess `.nope`: property `nope` does not exist on `I1`",
    "function badSymbolKeyed2 > PropAccess `.nope`: property `nope` does not exist on `I2`",
  ])
}
