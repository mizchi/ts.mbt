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
          "/src/g.d.ts", "type V = void;\nexport declare function vu<T>(x: T, v: number | void): T;\nexport declare function va<T>(x: T, v: number | V): T;\nexport declare const vm: <T>(x: T, v: number | void, w?: string) => T;\nexport declare function two<T>(x: T, n: number): T;\nexport declare function opt<T>(x: T, n?: number): T;\nexport declare function rest<T>(x: T, ...more: number[]): T;\nexport declare function tup<T extends unknown[]>(...args: T): T;\nexport declare function vparam<T>(x: T, v: void): T;\nexport declare function und<T>(x: T, u: number | undefined): T;\nexport declare function bare<T>(x: T): T;",
        ),
        (
          "/src/poly.ts", "export function poly<P extends number>(...points: P[]) { return points; }\nexport function pq<T extends string = string>(...args: Parameters<(a: number, b?: string) => T>): T { return \"\" as T; }",
        ),
        (
          "/src/main.ts", "import { two, opt, rest, tup, vparam, und, bare, vu, va, vm } from \"./g\";\nexport const ok12 = vu(1);\nexport const ok13 = va(1);\nexport const ok14 = vm(1);\nexport const bad7 = vm();\nimport { poly, pq } from \"./poly\";\nexport const ok9 = poly(1, 2, 3, 4);\nexport const ok10 = poly();\nexport const ok11 = pq(1, \"s\");\nexport const bad1 = two(1);\nexport const bad2 = two(1, 2, 3);\nexport const bad3 = opt(1, 2, 3);\nexport const bad4 = rest();\nexport const bad5 = und(1);\nexport const bad6 = bare();\nexport const ok1 = two(1, 2);\nexport const ok2 = opt(1);\nexport const ok3 = rest(1);\nexport const ok4 = rest(1, 2, 3, 4);\nexport const ok5 = tup();\nexport const ok6 = tup(1, \"a\");\nexport const ok7 = vparam(1);\nexport const ok8 = und(1, undefined);",
        ),
      ],
      [
        ("/src/main.ts", "./g", "/src/g.d.ts"),
        ("/src/main.ts", "./poly", "/src/poly.ts"),
      ],
    ),
    [
      "top-level > call `vm` :: expected 1-3 argument(s), got 0", "top-level > call `two` :: expected 2 argument(s), got 1",
      "top-level > call `two` :: expected 2 argument(s), got 3", "top-level > call `opt` :: expected 1-2 argument(s), got 3",
      "top-level > call `rest` :: expected at least 1 argument(s), got 0", "top-level > call `bare` :: expected 1 argument(s), got 0",
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
