///|
test "mtsc module reports a strict return mismatch" {
  let diagnostics = check_source(
    "function formatScore(score: number): string { return score; }", false,
  )
  assert_true(diagnostics.contains("expected `string` but got `number`"))
}

///|
test "mtsc module accepts a valid function" {
  let diagnostics = check_source(
    "function formatScore(score: number): string { return \"score: \" + score; }",
    false,
  )
  assert_eq(diagnostics, "")
}

///|
test "mtsc module reports an error from an imported module source" {
  let diagnostics = check_module_sources([
    {
      path: "/src/entry.ts",
      source: "import { formatScore } from \"./score\";\nexport const result = formatScore(1);",
      allowJsx: false,
    },
    {
      path: "/src/score.ts",
      source: "export function formatScore(score: number): string { return score; }",
      allowJsx: false,
    },
  ])
  assert_true(diagnostics.contains("/src/score.ts:"))
  assert_true(diagnostics.contains("expected `string` but got `number`"))
}

///|
test "mtsc graph checker propagates a named import type to its consumer" {
  let diagnostics = check_module_graph({
    modules: [
      {
        path: "/src/entry.ts",
        source: "import { score } from \"./score\";\nexport const label: string = score;",
        allowJsx: false,
      },
      {
        path: "/src/score.ts",
        source: "export const score: number = 1;",
        allowJsx: false,
      },
    ],
    edges: [
      {
        importerPath: "/src/entry.ts",
        moduleSpecifier: "./score",
        targetPath: "/src/score.ts",
      },
    ],
  })
  assert_true(diagnostics.contains("/src/entry.ts:"))
  assert_true(diagnostics.contains("expected `string` but got `number`"))
}

///|
test "mtsc graph checker follows named value reexports" {
  let diagnostics = check_module_graph({
    modules: [
      {
        path: "/src/entry.ts",
        source: "import { score } from \"./index\";\nexport const label: string = score;",
        allowJsx: false,
      },
      {
        path: "/src/index.ts",
        source: "export { score } from \"./score\";",
        allowJsx: false,
      },
      {
        path: "/src/score.ts",
        source: "export const score: number = 1;",
        allowJsx: false,
      },
    ],
    edges: [
      {
        importerPath: "/src/entry.ts",
        moduleSpecifier: "./index",
        targetPath: "/src/index.ts",
      },
      {
        importerPath: "/src/index.ts",
        moduleSpecifier: "./score",
        targetPath: "/src/score.ts",
      },
    ],
  })
  assert_true(diagnostics.contains("expected `string` but got `number`"))
  assert_false(diagnostics.contains("has no value export `score`"))
}

///|
test "mtsc graph checker checks objects against imported interface parameters" {
  let diagnostics = check_module_graph({
    modules: [
      {
        path: "/src/consumer.ts",
        source: (
          #|import { greeting } from "./index";
          #|export const preview: string = greeting({ id: 42, displayName: "Ada" });
        ),
        allowJsx: false,
      },
      {
        path: "/src/index.ts",
        source: (
          #|export { greeting } from "./user-service";
          #|export type { User } from "./model";
        ),
        allowJsx: false,
      },
      {
        path: "/src/user-service.ts",
        source: (
          #|import type { User } from "./model";
          #|export function greeting(user: User): string { return `Hello, ${user.displayName}`; }
        ),
        allowJsx: false,
      },
      {
        path: "/src/model.ts",
        source: "export interface User { id: string; displayName: string; }",
        allowJsx: false,
      },
    ],
    edges: [
      {
        importerPath: "/src/consumer.ts",
        moduleSpecifier: "./index",
        targetPath: "/src/index.ts",
      },
      {
        importerPath: "/src/index.ts",
        moduleSpecifier: "./user-service",
        targetPath: "/src/user-service.ts",
      },
      {
        importerPath: "/src/index.ts",
        moduleSpecifier: "./model",
        targetPath: "/src/model.ts",
      },
      {
        importerPath: "/src/user-service.ts",
        moduleSpecifier: "./model",
        targetPath: "/src/model.ts",
      },
    ],
  })
  assert_true(diagnostics.contains("expected `string` but got `number`"))
}

///|
test "mtsc graph checker supports aliased and default imports" {
  let diagnostics = check_module_graph({
    modules: [
      {
        path: "/src/entry.ts",
        source: (
          #|import getAnswer, { count as answerCount } from "./answer";
          #|export const fromDefault: string = getAnswer();
          #|export const fromAlias: string = answerCount;
        ),
        allowJsx: false,
      },
      {
        path: "/src/answer.ts",
        source: (
          #|export default function getAnswer(): number { return 1; }
          #|export const count: number = 2;
        ),
        allowJsx: false,
      },
    ],
    edges: [
      {
        importerPath: "/src/entry.ts",
        moduleSpecifier: "./answer",
        targetPath: "/src/answer.ts",
      },
    ],
  })
  // Both the default and aliased named import are injected with their
  // exporter types, producing one mismatch each in the consuming module.
  assert_eq(diagnostics.split("expected `string` but got `number`").count(), 3)
}

///|
test "mtsc graph checker handles cycles and reports missing local modules" {
  let diagnostics = check_module_graph({
    modules: [
      {
        path: "/src/a.ts",
        source: (
          #|import { label } from "./b";
          #|import { absent } from "./absent";
          #|export const count: number = 1;
          #|export const invalid: number = label;
          #|void absent;
        ),
        allowJsx: false,
      },
      {
        path: "/src/b.ts",
        source: (
          #|import { count } from "./a";
          #|export const label: string = "value";
          #|export const copy: number = count;
        ),
        allowJsx: false,
      },
    ],
    edges: [
      {
        importerPath: "/src/a.ts",
        moduleSpecifier: "./b",
        targetPath: "/src/b.ts",
      },
      {
        importerPath: "/src/b.ts",
        moduleSpecifier: "./a",
        targetPath: "/src/a.ts",
      },
    ],
  })
  assert_true(diagnostics.contains("cannot resolve local module `./absent`"))
  assert_true(diagnostics.contains("expected `number` but got `string`"))
}

///|
test "mtsc graph checker accepts JSX when the module opts in" {
  let diagnostics = check_module_graph({
    modules: [
      {
        path: "/src/view.tsx",
        source: "export const view = <div />;",
        allowJsx: true,
      },
    ],
    edges: [],
  })
  assert_false(diagnostics.contains("parse error"))
}

///|
fn graph2(entry : String, lib : String) -> String {
  check_module_graph({
    modules: [
      { path: "/src/entry.ts", source: entry, allowJsx: false, },
      { path: "/src/lib.ts", source: lib, allowJsx: false, },
    ],
    edges: [
      {
        importerPath: "/src/entry.ts",
        moduleSpecifier: "./lib",
        targetPath: "/src/lib.ts",
      },
    ],
  })
}

///|
test "mtsc graph checker types an imported namespace by its members" {
  let lib = "export namespace util {\n  export function assertNever(_x: never): never { throw new Error(); }\n  export const n = 1;\n  export function join(xs: string[], sep = \",\"): string { return xs.join(sep); }\n}"
  // A member's type is checked (`util.n` is a number) ...
  assert_true(
    graph2(
      "import { util } from \"./lib\";\nexport const s: string = util.n;", lib,
    ).contains("expected `string` but got `number`"),
  )
  // ... a never-returning member ends a path, and a defaulted parameter
  // may be omitted.
  let ok = graph2(
    "import { util } from \"./lib\";\ntype E = { type: \"a\" } | { type: \"b\" };\nexport function f(e: E): number {\n  if (e.type === \"a\") return 1;\n  if (e.type === \"b\") return 2;\n  util.assertNever(e);\n}\nexport const j: string = util.join([\"a\"]);",
    lib,
  )
  assert_eq(ok, "")
}

///|
test "mtsc graph checker infers an imported bounded generic at the call" {
  let lib = "export interface Trait { _zod: { def: unknown } }\nexport interface Ctor<T extends Trait> { new (def: unknown): T }\nexport function make<T extends Trait>(name: string, init: (inst: T, def: unknown) => void): Ctor<T> { return null as any; }"
  let diags = graph2(
    "import { make, type Ctor, type Trait } from \"./lib\";\ninterface E extends Trait { issues: string[]; _zod: { def: string[] } }\nconst init = (inst: E, issues: unknown) => { inst.issues = []; };\nexport const E: Ctor<E> = make(\"E\", init);",
    lib,
  )
  assert_eq(diags, "")
}

///|
/// The DEFAULT-import spelling of the call-site solve. The named-import
/// branch marks an imported generic function (`@import-generic:`) and an
/// imported `Any` (`@imported:`), and the default-import branch marked
/// neither (review of mizchi/ts.mbt#285). A default import is usually bound
/// under another name, and then nothing else finds the declaration, so the
/// call came back with `T` unsolved and the mismatch below was silent while
/// the named spelling reported it, as tsc does.
test "mtsc graph checker solves a default-imported generic at the call" {
  let lib = "export default function ident<T extends { a: number }>(x: T): T { return x; }\nexport function named<T extends { a: number }>(x: T): T { return x; }"
  let named = graph2(
    "import { named as nn } from \"./lib\";\nexport const s: string = nn({ a: 1 });",
    lib,
  )
  let dflt = graph2(
    "import idd from \"./lib\";\nexport const s: string = idd({ a: 1 });", lib,
  )
  assert_true(named.contains("expected `string`"), msg=named)
  assert_true(dflt.contains("expected `string`"), msg=dflt)
  // The legal call stays silent.
  assert_eq(
    graph2(
      "import idd from \"./lib\";\nexport const s: { a: number } = idd({ a: 1 });",
      lib,
    ),
    "",
  )
}

///|
/// Review of mizchi/ts.mbt#285: the imported binder is over the
/// UN-inlined signature, so a constrained type parameter still occurs in
/// it, and a fresh literal for one whose constraint can be a primitive is
/// not widened (tsc's `getCovariantInference`, probed). Widening it made
/// `wrap("a")` a `string[]` and rejected the legal `"a"[]` target.
test "mtsc graph checker keeps a literal for a primitive-constrained import" {
  let lib = "export function wrap<T extends string>(x: T): T[] { return [x]; }\nexport function wrapU<T>(x: T): T[] { return [x]; }"
  assert_eq(
    graph2(
      "import { wrap } from \"./lib\";\nexport const r: \"a\"[] = wrap(\"a\");",
      lib,
    ),
    "",
  )
  // The unconstrained parameter still widens: pushing another string onto
  // its result is legal.
  assert_eq(
    graph2(
      "import { wrapU } from \"./lib\";\nconst q = wrapU(\"a\");\nq.push(\"b\");\nexport {};",
      lib,
    ),
    "",
  )
}
