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

///|
/// Two reachable modules declaring the same interface name used to share
/// one bare entry holding their MERGE, so a named import meant both.
/// univer's `@univerjs/core` and `@univerjs/protocol` both export
/// `ICommand`, and `import { ICommand } from '@univerjs/core'` was asked
/// for protocol's `data` member. A named import now binds the local name
/// to the declaring module's own key, as `ns.X` already did.
test "mtsc graph checker binds a named import to its own module's declaration" {
  let issues = collect_module_graph_issues({
    modules: [
      {
        path: "/src/entry.ts",
        source: "import type { ICommand } from \"./a\";\nimport type { ICommand as P } from \"./b\";\nexport const ok: ICommand = { id: \"a\", type: 1 };\nexport const ok2: P = { id: \"a\", data: \"s\" };\nexport const bad: ICommand = { id: \"a\", data: \"s\" };",
        allowJsx: false,
      },
      {
        path: "/src/a.ts",
        source: "export interface ICommand { id: string; type: number }",
        allowJsx: false,
      },
      {
        path: "/src/b.ts",
        source: "export interface ICommand { id: string; data: string }",
        allowJsx: false,
      },
    ],
    edges: [
      {
        importerPath: "/src/entry.ts",
        moduleSpecifier: "./a",
        targetPath: "/src/a.ts",
      },
      {
        importerPath: "/src/entry.ts",
        moduleSpecifier: "./b",
        targetPath: "/src/b.ts",
      },
    ],
  })
  let flagged = fn(binding : String) -> Bool {
    issues.iter().any(fn(i) { i.path.contains("binding `\{binding}` ") })
  }
  assert_false(flagged("ok"))
  assert_false(flagged("ok2"))
  assert_true(flagged("bad"))
}

///|
/// The VALUE side of the same collision: an enum member is looked up by
/// the value's name, so `BooleanNumber.TRUE` read whichever module's
/// `enum BooleanNumber` was ingested last — univer's protocol declares one
/// with `BOOLEAN_NUMBER_TRUE`, and every core `BooleanNumber.TRUE` became
/// "does not exist", depending on import order.
test "mtsc graph checker reads an imported enum's own members" {
  let issues = collect_module_graph_issues({
    modules: [
      {
        path: "/src/entry.ts",
        source: "import { BooleanNumber } from \"./a\";\nimport { B } from \"./b\";\nexport const ok: number = BooleanNumber.TRUE + B;\nexport const bad = BooleanNumber.BOOLEAN_NUMBER_TRUE;",
        allowJsx: false,
      },
      {
        path: "/src/a.ts",
        source: "export enum BooleanNumber { FALSE = 0, TRUE = 1 }",
        allowJsx: false,
      },
      {
        path: "/src/b.ts",
        source: "export enum BooleanNumber { BOOLEAN_NUMBER_FALSE = 0, BOOLEAN_NUMBER_TRUE = 1 }\nexport const B = 1;",
        allowJsx: false,
      },
    ],
    edges: [
      {
        importerPath: "/src/entry.ts",
        moduleSpecifier: "./a",
        targetPath: "/src/a.ts",
      },
      {
        importerPath: "/src/entry.ts",
        moduleSpecifier: "./b",
        targetPath: "/src/b.ts",
      },
    ],
  })
  let messages = issues.map(fn(i) { i.message })
  assert_false(messages.iter().any(fn(m) { m.contains("`TRUE`") }))
  assert_true(
    messages.iter().any(fn(m) { m.contains("`BOOLEAN_NUMBER_TRUE`") }),
  )
}

///|
/// A namespace's OWN `enum E` shadows the file's `import { E }` inside it:
/// the import redirect (which exists because two reachable modules declare
/// `E`) must not apply to a name the namespace declares itself.
test "mtsc graph checker keeps a namespace's own enum over a colliding import" {
  let issues = collect_module_graph_issues({
    modules: [
      {
        path: "/src/entry.ts",
        source: "import { E } from \"./a\";\nimport { B } from \"./b\";\nexport const outer: number = E.A + B;\nexport namespace N {\n  enum E { Local }\n  export const inner = E.Local;\n  export const bad = E.Nope;\n}",
        allowJsx: false,
      },
      { path: "/src/a.ts", source: "export enum E { A }", allowJsx: false, },
      {
        path: "/src/b.ts",
        source: "export enum E { X }\nexport const B = 1;",
        allowJsx: false,
      },
    ],
    edges: [
      {
        importerPath: "/src/entry.ts",
        moduleSpecifier: "./a",
        targetPath: "/src/a.ts",
      },
      {
        importerPath: "/src/entry.ts",
        moduleSpecifier: "./b",
        targetPath: "/src/b.ts",
      },
    ],
  })
  let messages = issues.map(fn(i) { i.message })
  assert_false(messages.iter().any(fn(m) { m.contains("`Local`") }))
  assert_false(messages.iter().any(fn(m) { m.contains("`A`") }))
  assert_true(messages.iter().any(fn(m) { m.contains("`Nope`") }))
}

///|
/// A third module's OWN import of a colliding name means that module's
/// declaration, whatever the checked module imports under the same
/// spelling: `consume(x: I)` in `c.ts` takes `b.ts`'s `I`.
test "mtsc graph checker judges an imported function by its own module's import" {
  let issues = collect_module_graph_issues({
    modules: [
      {
        path: "/src/entry.ts",
        source: "import type { I } from \"./a\";\nimport { consume } from \"./c\";\nexport const mine: I = { a: \"x\" };\nconsume({ b: \"ok\" });\nconsume({ a: \"bad\" });",
        allowJsx: false,
      },
      {
        path: "/src/a.ts",
        source: "export interface I { a: string }",
        allowJsx: false,
      },
      {
        path: "/src/b.ts",
        source: "export interface I { b: string }",
        allowJsx: false,
      },
      {
        path: "/src/c.ts",
        source: "import type { I } from \"./b\";\nexport function consume(x: I): void {}",
        allowJsx: false,
      },
    ],
    edges: [
      {
        importerPath: "/src/entry.ts",
        moduleSpecifier: "./a",
        targetPath: "/src/a.ts",
      },
      {
        importerPath: "/src/entry.ts",
        moduleSpecifier: "./c",
        targetPath: "/src/c.ts",
      },
      {
        importerPath: "/src/c.ts",
        moduleSpecifier: "./b",
        targetPath: "/src/b.ts",
      },
    ],
  })
  let messages = issues.map(fn(i) { i.message })
  let said = fn(text : String) -> Bool {
    messages.iter().any(fn(m) { m.contains(text) })
  }
  // `consume({ b: "ok" })` is legal: its `I` is `b.ts`'s.
  assert_false(said("property `b` does not exist"))
  assert_false(said("property `a` is required"))
  assert_false(issues.iter().any(fn(i) { i.path.contains("binding `mine` ") }))
  // `consume({ a: "bad" })` is not.
  assert_true(said("property `a` does not exist"))
}

///|
/// A named import goes through the target's EXPORT table: a private
/// `interface T` beside `export { T } from "./a"` is not what `import { T }`
/// binds.
test "mtsc graph checker binds a re-exported name, not a private same-named one" {
  let issues = collect_module_graph_issues({
    modules: [
      {
        path: "/src/entry.ts",
        source: "import type { T } from \"./index\";\nexport const ok: T = { a: 1 };\nexport const bad: T = { hidden: 1 };",
        allowJsx: false,
      },
      {
        path: "/src/index.ts",
        source: "interface T { hidden: number }\nexport const h: T = { hidden: 1 };\nexport { T } from \"./a\";",
        allowJsx: false,
      },
      {
        path: "/src/a.ts",
        source: "export interface T { a: number }",
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
        moduleSpecifier: "./a",
        targetPath: "/src/a.ts",
      },
    ],
  })
  let flagged = fn(binding : String) -> Bool {
    issues.iter().any(fn(i) { i.path.contains("binding `\{binding}` ") })
  }
  assert_false(flagged("ok"))
  assert_false(flagged("h"))
  assert_true(flagged("bad"))
}

///|
/// A tsconfig's `compilerOptions` reach every module of the program: with
/// `strict: false` a null into a `string` is legal, and with no `strict`
/// at all it is not, because TypeScript 7's `strict` defaults to true.
test "mtsc graph checker applies compiler options to every module" {
  let graph : MtscModuleGraph = {
    modules: [
      {
        path: "/src/entry.ts",
        source: "import { f } from \"./b\";\nexport const x: string = null;\nexport const y = f();",
        allowJsx: false,
      },
      {
        path: "/src/b.ts",
        source: "export function f(): number { const s: string = null; return 1 }",
        allowJsx: false,
      },
    ],
    edges: [
      {
        importerPath: "/src/entry.ts",
        moduleSpecifier: "./b",
        targetPath: "/src/b.ts",
      },
    ],
  }
  let loose = collect_module_graph_issues(graph, compiler_options=[
    ("strict", "false"),
  ])
  assert_eq(loose.length(), 0)
  let strict = collect_module_graph_issues(graph, compiler_options=[
    ("experimentalDecorators", "true"),
  ])
  assert_true(strict.iter().any(fn(i) { i.modulePath == "/src/entry.ts" }))
  assert_true(strict.iter().any(fn(i) { i.modulePath == "/src/b.ts" }))
  // An explicit flag beats `strict`, in either direction.
  let nulls_only = collect_module_graph_issues(graph, compiler_options=[
    ("strict", "false"),
    ("strictNullChecks", "true"),
  ])
  assert_true(nulls_only.length() > 0)
}

///|
test "compiler_option_header resolves the strict family flag by flag" {
  assert_eq(compiler_option_header([]), "")
  let h = compiler_option_header([
    ("strict", "false"),
    ("noImplicitAny", "true"),
    ("target", "ES2022"),
    ("lib", "ESNext,DOM"),
  ])
  assert_true(h.contains("// @noImplicitAny: true\n"))
  assert_true(h.contains("// @strictNullChecks: false\n"))
  assert_true(h.contains("// @alwaysStrict: false\n"))
  assert_true(h.contains("// @target: es2022\n"))
  assert_true(h.contains("// @lib: esnext,dom\n"))
  // Never `@strict:` itself: the detectors give `@strict: false`
  // precedence over a per-flag `true`.
  assert_false(h.contains("@strict:"))
  let d = compiler_option_header([("noImplicitOverride", "true")])
  assert_true(d.contains("// @strictPropertyInitialization: true\n"))
  assert_true(d.contains("// @noImplicitOverride: true\n"))
  assert_false(d.contains("@alwaysStrict"))
}

///|
/// The namespace-import form of the same scoping: `c.ts`'s `ns.I` is the
/// `I` of the module ITS `ns` names, even when the checked module binds
/// `ns` to a module whose `I` differs.
test "mtsc graph checker reads a reachable module's ns.I through its own ns" {
  let issues = collect_module_graph_issues({
    modules: [
      {
        path: "/src/entry.ts",
        source: "import * as ns from \"./a\";\nimport { consume } from \"./c\";\nexport const mine: ns.I = { a: \"x\" };\nconsume({ b: \"ok\" });\nconsume({ a: \"bad\" });",
        allowJsx: false,
      },
      {
        path: "/src/a.ts",
        source: "export interface I { a: string }",
        allowJsx: false,
      },
      {
        path: "/src/b.ts",
        source: "export interface I { b: string }",
        allowJsx: false,
      },
      {
        path: "/src/c.ts",
        source: "import * as ns from \"./b\";\nexport function consume(x: ns.I): void {}",
        allowJsx: false,
      },
    ],
    edges: [
      {
        importerPath: "/src/entry.ts",
        moduleSpecifier: "./a",
        targetPath: "/src/a.ts",
      },
      {
        importerPath: "/src/entry.ts",
        moduleSpecifier: "./c",
        targetPath: "/src/c.ts",
      },
      {
        importerPath: "/src/c.ts",
        moduleSpecifier: "./b",
        targetPath: "/src/b.ts",
      },
    ],
  })
  let said = fn(text : String) -> Bool {
    issues.iter().any(fn(i) { i.message.contains(text) })
  }
  assert_false(said("property `b` does not exist"))
  assert_false(said("property `a` is required"))
  assert_false(issues.iter().any(fn(i) { i.path.contains("binding `mine` ") }))
  assert_true(said("property `a` does not exist"))
}

///|
/// A reachable module's import of a type that shadows a LIB name
/// (`interface Error`) is renamed like a colliding one: the declaration is
/// keyed `Error@a.ts`, and `make(): Error` in `b.ts` means it, not the lib
/// `Error` whose `message` is a string.
test "mtsc graph checker keeps an imported lib-shadowing type in its module's scope" {
  let issues = collect_module_graph_issues({
    modules: [
      {
        path: "/src/entry.ts",
        source: "import { make } from \"./b\";\nexport const n: number = make().message;",
        allowJsx: false,
      },
      {
        path: "/src/a.ts",
        source: "export interface Error { message: number }",
        allowJsx: false,
      },
      {
        path: "/src/b.ts",
        source: "import type { Error } from \"./a\";\nexport declare function make(): Error;",
        allowJsx: false,
      },
    ],
    edges: [
      {
        importerPath: "/src/entry.ts",
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
  assert_eq(issues.map(fn(i) { i.message }), [])
}

///|
/// `c.ts`'s rewritten declarations are cached per (module, rename set), and
/// the set has to carry each rename's DESTINATION: from `r1` (where `a.ts`
/// and `b.ts` both declare `Item`) `ns.Item` is `Item@/src/a.ts`, and from
/// `r2` (where only `a.ts` does) it is the bare `Item`. Keyed on the renamed
/// names alone, whichever root ran second reused the first one's rewrite.
test "mtsc graph checker does not share a rewrite across different rename destinations" {
  let module_ = fn(path : String, source : String) -> MtscModuleSource {
    { path, source, allowJsx: false, }
  }
  let edge = fn(from : String, spec : String, to : String) -> MtscModuleEdge {
    { importerPath: from, moduleSpecifier: spec, targetPath: to, }
  }
  let root = fn(ns : String, tag : String) -> String {
    "import * as ns from \"./\{ns}\";\nimport type { Box } from \"./c\";\nexport const ok\{tag}: Box = { item: { a: \"x\" } };\nexport const bad\{tag}: Box = { item: { a: 1 } };"
  }
  let issues = collect_module_graph_issues({
    modules: [
      module_("/src/r1.ts", root("b", "1")),
      module_("/src/r2.ts", root("d", "2")),
      module_("/src/a.ts", "export interface Item { a: string }"),
      module_("/src/b.ts", "export interface Item { b: number }"),
      module_("/src/d.ts", "export interface Other { z: number }"),
      module_(
        "/src/c.ts", "import * as ns from \"./a\";\nexport interface Box { item: ns.Item }",
      ),
    ],
    edges: [
      edge("/src/r1.ts", "./b", "/src/b.ts"),
      edge("/src/r1.ts", "./c", "/src/c.ts"),
      edge("/src/r2.ts", "./d", "/src/d.ts"),
      edge("/src/r2.ts", "./c", "/src/c.ts"),
      edge("/src/c.ts", "./a", "/src/a.ts"),
    ],
  })
  let at = fn(binding : String) -> Bool {
    issues.iter().any(fn(i) { i.path.contains("binding `\{binding}`") })
  }
  assert_false(at("ok1"))
  assert_false(at("ok2"))
  assert_true(at("bad1"))
  assert_true(at("bad2"))
}

///|
/// A `{ … }` payload is an expression of the enclosing function and class.
/// Its parser did not know either: `{yield <span title="x" />}` read
/// `yield` as a name and `<span` as a comparison (so `span` was
/// undeclared), and `{this.#n}` in a method was "not accessible outside its
/// class".
test "mtsc checker reads a JSX payload in its enclosing function and class" {
  let src =
    #|declare global { namespace JSX { interface IntrinsicElements { [k: string]: any } } }
    #|export function* f(): Generator<any, any, any> {
    #|  return <div>{yield <span title="x" />}</div>;
    #|}
    #|export async function g(p: Promise<any>) {
    #|  return <div>{await p}</div>;
    #|}
    #|export class C {
    #|  #n = 1;
    #|  view() {
    #|    return <div title={String(this.#n)}>{this.#n}</div>;
    #|  }
    #|}
  match collect_type_issues(src, true) {
    Ok(issues) => assert_eq(issues.map(fn(i) { i.message }), [])
    Err(e) => fail(e)
  }
}

///|
/// `c.ts` imports `Item` under another name. `Item` has one declarer, so it
/// gets no per-module key, and `It` used to read the shared bare table —
/// which holds the CHECKED module's own `It` — so `consume({ a: "x" })` was
/// judged against `{ b: number }`.
test "mtsc graph checker resolves a renamed import of a uniquely declared type" {
  let issues = collect_module_graph_issues({
    modules: [
      {
        path: "/src/root.ts",
        source: "import { consume } from \"./c\";\nexport interface It { b: number }\nexport const mine: It = { b: 1 };\nconsume({ a: \"x\" });\nconsume({ a: 1 });",
        allowJsx: false,
      },
      {
        path: "/src/a.ts",
        source: "export interface Item { a: string }",
        allowJsx: false,
      },
      {
        path: "/src/c.ts",
        source: "import type { Item as It } from \"./a\";\nexport function consume(x: It): void {}",
        allowJsx: false,
      },
    ],
    edges: [
      {
        importerPath: "/src/root.ts",
        moduleSpecifier: "./c",
        targetPath: "/src/c.ts",
      },
      {
        importerPath: "/src/c.ts",
        moduleSpecifier: "./a",
        targetPath: "/src/a.ts",
      },
    ],
  })
  let messages = issues.map(fn(i) { i.message })
  assert_false(messages.iter().any(fn(m) { m.contains("`b`") }))
  assert_eq(
    issues.filter(fn(i) { i.path.contains("call `consume` arg[0].a") }).length(),
    1,
  )
}

///|
/// The renamed-import mapping above must not land on a name the CHECKED
/// module redirects: its `import { Other as Item }` (with `Other` declared
/// twice) points `Item` at `Other@x1`, so mapping `b.ts`'s `It` to the bare
/// `Item` read `make()` as `Other` and reported `.n` as missing. Leaving
/// `It` unmapped is not enough either: the root's own `interface It` would
/// answer it.
test "mtsc graph checker keeps a renamed import off a name the checked module redirects" {
  let module_ = fn(path : String, source : String) -> MtscModuleSource {
    { path, source, allowJsx: false, }
  }
  let edge = fn(from : String, spec : String, to : String) -> MtscModuleEdge {
    { importerPath: from, moduleSpecifier: spec, targetPath: to, }
  }
  let issues = collect_module_graph_issues({
    modules: [
      module_(
        "/src/root.ts", "import { make } from \"./b\";\nimport type { Other as Item } from \"./x1\";\nimport type { Other as O2 } from \"./x2\";\nexport interface It { b: number }\nexport const m: Item = { z: \"s\" };\nexport const o: O2 = { w: true };\nexport const i: It = { b: 1 };\nexport const k: number = make().n;",
      ),
      module_("/src/a.ts", "export interface Item { n: number }"),
      module_(
        "/src/b.ts", "import type { Item as It } from \"./a\";\nexport declare function make(): It;",
      ),
      module_("/src/x1.ts", "export interface Other { z: string }"),
      module_("/src/x2.ts", "export interface Other { w: boolean }"),
    ],
    edges: [
      edge("/src/root.ts", "./b", "/src/b.ts"),
      edge("/src/root.ts", "./x1", "/src/x1.ts"),
      edge("/src/root.ts", "./x2", "/src/x2.ts"),
      edge("/src/b.ts", "./a", "/src/a.ts"),
    ],
  })
  assert_eq(issues.map(fn(i) { i.message }), [])
}

///|
/// A method's own type parameter shadows a renamed import inside that
/// method. `c.ts` imports `Item as It` and declares `identity<It>`; the
/// renamed-import mapping rewrote the binder's uses to `Item` too, so
/// `api.identity(1)` was "expected `Item` but got `number`".
test "mtsc graph checker keeps a method's own type parameter out of a rename" {
  let module_ = fn(path : String, source : String) -> MtscModuleSource {
    { path, source, allowJsx: false, }
  }
  let edge = fn(from : String, spec : String, to : String) -> MtscModuleEdge {
    { importerPath: from, moduleSpecifier: spec, targetPath: to, }
  }
  let issues = collect_module_graph_issues({
    modules: [
      module_(
        "/src/root.ts", "import { api } from \"./c\";\nexport const n: number = api.identity(1);\napi.take({ a: \"x\" });\napi.take({ a: 1 });",
      ),
      module_("/src/a.ts", "export interface Item { a: string }"),
      module_(
        "/src/c.ts", "import type { Item as It } from \"./a\";\nexport interface Api { identity<It>(x: It): It; take(x: It): void }\nexport declare const api: Api;",
      ),
    ],
    edges: [
      edge("/src/root.ts", "./c", "/src/c.ts"),
      edge("/src/c.ts", "./a", "/src/a.ts"),
    ],
  })
  // `take` still reads the import, so only its bad call is reported.
  assert_eq(
    issues
    .map(fn(i) { i.path })
    .filter(fn(p) { p.contains("identity") || p.contains("binding `n`") }),
    [],
  )
  assert_eq(
    issues.filter(fn(i) { i.path.contains("call `take` arg[0].a") }).length(),
    1,
  )
}

///|
/// The checked module's own RENAMED import is its binding of that name:
/// `import type { Other as Item }` means `x.ts`'s `Other` in here even
/// though `a.ts` declares an `interface Item` the graph also reaches. That
/// `Item` used to be registered at the bare name, the redirect then read
/// `Item` as already declared, and `m: Item = { z: 1 }` was judged against
/// `{ n: number }`. Counted as the checked module's name, `a.ts`'s `Item`
/// collides and is keyed, so both sides are judged against their own type.
test "mtsc graph checker reads the checked module's renamed import as its own name" {
  let module_ = fn(path : String, source : String) -> MtscModuleSource {
    { path, source, allowJsx: false, }
  }
  let edge = fn(from : String, spec : String, to : String) -> MtscModuleEdge {
    { importerPath: from, moduleSpecifier: spec, targetPath: to, }
  }
  let issues = collect_module_graph_issues({
    modules: [
      module_(
        "/src/root.ts", "import type { Other as Item } from \"./x\";\nimport { take } from \"./a\";\nexport const m: Item = { z: 1 };\nexport const bad: Item = { z: \"s\" };\nexport namespace N {\n  export const q: Item = { z: 1 };\n}\ntake({ n: 1 });\ntake({ n: \"s\" });",
      ),
      module_("/src/x.ts", "export interface Other { z: number }"),
      module_(
        "/src/a.ts", "export interface Item { n: number }\nexport declare function take(x: Item): void;",
      ),
    ],
    edges: [
      edge("/src/root.ts", "./x", "/src/x.ts"),
      edge("/src/root.ts", "./a", "/src/a.ts"),
    ],
  })
  let at = fn(text : String) -> Int32 {
    issues.filter(fn(i) { i.path.contains(text) }).length()
  }
  assert_eq(at("binding `m`"), 0)
  assert_eq(at("binding `q`"), 0)
  assert_eq(at("binding `bad`"), 1)
  assert_eq(at("call `take` arg[0].n"), 1)
  assert_eq(issues.length(), 2)
}

///|
/// A CLASS cannot be keyed (class lookups and `extends` walks go through
/// the bare name), so when the checked module renames something into the
/// name another module's class holds, `x: Item` (the import) and the
/// class's own `mk(): Item` are one name. Putting the import's interface
/// there made `mk().n`, `mk().m()` and `new Sub().n` read `Other`; leaving
/// the class there made the legal `read(x: Item) { x.z }` read the class.
/// The name is registered as neither, so every line below is silent and
/// `bad: string = mk().n` is a declared MISS.
test "mtsc graph checker leaves a foreign class its name beside a renamed import" {
  let module_ = fn(path : String, source : String) -> MtscModuleSource {
    { path, source, allowJsx: false, }
  }
  let edge = fn(from : String, spec : String, to : String) -> MtscModuleEdge {
    { importerPath: from, moduleSpecifier: spec, targetPath: to, }
  }
  let issues = collect_module_graph_issues({
    modules: [
      module_(
        "/src/root.ts", "import type { Other as Item } from \"./x\";\nimport { mk, Sub } from \"./a\";\nexport const m: Item = { z: 1 };\nexport function read(x: Item): number { return x.z }\nexport const k: number = mk().n;\nexport const k2: number = mk().m();\nexport const k3: number = new Sub().n;\nexport const bad: string = mk().n;",
      ),
      module_("/src/x.ts", "export interface Other { z: number }"),
      module_(
        "/src/a.ts", "export class Item { n = 1; m(): number { return this.n } }\nexport function mk(): Item { return new Item() }\nexport class Sub extends Item { s = \"x\" }",
      ),
    ],
    edges: [
      edge("/src/root.ts", "./x", "/src/x.ts"),
      edge("/src/root.ts", "./a", "/src/a.ts"),
    ],
  })
  assert_eq(issues.map(fn(i) { i.path + " :: " + i.message }), [])
}

///|
/// The same class guard when the renamed import's TARGET collides. Two
/// modules declare `Other`, so the redirect takes the keyed path
/// (`Item` -> `Other@x.ts`), and that path returned before the guard ran:
/// the class's own module then read `mk(): Item` as `Other@x.ts`, and the
/// legal `mk().n` was reported. `read` and `bad` are the two sides of the
/// test above.
test "mtsc graph checker leaves a foreign class its name beside a renamed colliding import" {
  let module_ = fn(path : String, source : String) -> MtscModuleSource {
    { path, source, allowJsx: false, }
  }
  let edge = fn(from : String, spec : String, to : String) -> MtscModuleEdge {
    { importerPath: from, moduleSpecifier: spec, targetPath: to, }
  }
  let issues = collect_module_graph_issues({
    modules: [
      module_(
        "/src/root.ts", "import type { Other as Item } from \"./x\";\nimport { yv } from \"./y\";\nimport { mk } from \"./a\";\nexport function read(x: Item): number { return x.z }\nexport const k: number = mk().n + yv;\nexport const bad: string = mk().n;",
      ),
      module_("/src/x.ts", "export interface Other { z: number }"),
      module_(
        "/src/y.ts", "export interface Other { w: string }\nexport declare const yv: number;",
      ),
      module_(
        "/src/a.ts", "export class Item { n = 1 }\nexport function mk(): Item { return new Item() }",
      ),
    ],
    edges: [
      edge("/src/root.ts", "./x", "/src/x.ts"),
      edge("/src/root.ts", "./y", "/src/y.ts"),
      edge("/src/root.ts", "./a", "/src/a.ts"),
    ],
  })
  assert_eq(issues.map(fn(i) { i.path + " :: " + i.message }), [])
}

///|
/// A module with no per-module key — an ambient `.d.ts`, whose
/// declarations every module sees — cannot have its references rewritten,
/// so reserving the checked module's renamed `Item` against it skipped
/// its `interface Item` and left its `Holder.item: Item` to the redirect:
/// the legal `holder.item.n` read `Other` and was reported. `bad2` is the same
/// read against `string`, so the ambient `Item` must resolve rather than
/// merely abstain.
test "mtsc graph checker keeps an ambient declaration's own name beside a renamed import" {
  let module_ = fn(path : String, source : String) -> MtscModuleSource {
    { path, source, allowJsx: false, }
  }
  let edge = fn(from : String, spec : String, to : String) -> MtscModuleEdge {
    { importerPath: from, moduleSpecifier: spec, targetPath: to, }
  }
  let issues = collect_module_graph_issues({
    modules: [
      module_(
        "/src/root.ts", "import type { Other as Item } from \"./x\";\nexport const m: Item = { z: 1 };\nexport const bad: Item = { z: \"s\" };\nexport const k: number = holder.item.n;\nexport const bad2: string = holder.item.n;",
      ),
      module_("/src/x.ts", "export interface Other { z: number }"),
      module_(
        "/src/env.d.ts", "interface Item { n: number }\ninterface Holder { item: Item }\ndeclare const holder: Holder;",
      ),
    ],
    edges: [edge("/src/root.ts", "./x", "/src/x.ts")],
  })
  assert_eq(issues.map(fn(i) { i.path + " :: " + i.message }), [
    "top-level > binding `bad` init.z :: expected `number` but got `string`", "top-level > binding `bad2` init :: expected `string` but got `number`",
  ])
}

///|
/// A `.d.ts` beside the entry, imported by path: how a package's
/// declarations reach an importer once the check graph loads them.
fn graph_dts(entry : String, dts : String) -> String {
  check_module_graph({
    modules: [
      { path: "/src/entry.ts", source: entry, allowJsx: false, },
      { path: "/src/lib.d.ts", source: dts, allowJsx: false, },
    ],
    edges: [
      {
        importerPath: "/src/entry.ts",
        moduleSpecifier: "./lib",
        targetPath: "/src/lib.d.ts",
      },
    ],
  })
}

///|
/// A `declare function` is held as a `TsImport`, and its value type used to
/// be the FIRST declaration as a bare `Func`. Each of the three ways that
/// went wrong is a false positive on code `tsc` accepts — drizzle's
/// `integer("id")`, its `and(a, b)` and preact's `useState(0)` — and each
/// legal call stays silent next to a real error of the same shape.
test "mtsc graph checker types an imported declare function like a declaration" {
  let dts =
    #|export declare function integer(): number;
    #|export declare function integer<M extends string>(config?: { mode: M }): number;
    #|export declare function integer<N extends string, M extends string>(name: N, config?: { mode: M }): number;
    #|export declare function and(...conditions: (string | undefined)[]): string | undefined;
    #|export declare function id<T>(x: T): T;
    #|export declare function bind(this: Window, n: number): void;
  // An overload set: any one signature may accept the call.
  assert_eq(
    graph_dts(
      "import { integer } from \"./lib\";\nexport const a = integer(\"id\");\nexport const b = integer();",
      dts,
    ),
    "",
  )
  assert_true(
    graph_dts(
      "import { integer } from \"./lib\";\nexport const a: string = integer();",
      dts,
    ).contains("expected `string` but got `number`"),
  )
  // A rest parameter takes each argument against its element type.
  assert_eq(
    graph_dts(
      "import { and } from \"./lib\";\nexport const a = and(\"x\", \"y\", undefined);",
      dts,
    ),
    "",
  )
  assert_true(
    graph_dts("import { and } from \"./lib\";\nexport const a = and(1);", dts).contains(
      "expected `string | undefined` but got `number`",
    ),
  )
  // A type parameter is solved at the call rather than left unbound.
  assert_true(
    graph_dts(
      "import { id } from \"./lib\";\nexport const s: string = id(1);", dts,
    ).contains("expected `string` but got `number`"),
  )
  assert_eq(
    graph_dts(
      "import { id } from \"./lib\";\nexport const n: number = id(1);", dts,
    ),
    "",
  )
  // A leading `this` parameter takes no argument.
  assert_eq(graph_dts("import { bind } from \"./lib\";\nbind(1);", dts), "")
}

///|
/// A bodiless `function` overload set in a `.d.ts` — preact's hooks are
/// written that way, not with `declare function` — carries its type
/// parameters too: without them `S` was an unbound name and the setter of
/// `const [n, setN] = useState(0)` came back `undefined`.
test "mtsc graph checker binds the type parameters of an imported overload set" {
  let dts =
    #|export function useState<S>(init: S | (() => S)): [S, (v: S) => void];
    #|export function useState<S = undefined>(): [S | undefined, (v: S | undefined) => void];
    #|export function id<T>(x: T): T;
    #|export function pair<S>(x: S): [S, (v: S) => void];
    #|export function pair<S = undefined>(): [S | undefined, (v: S | undefined) => void];
  assert_eq(
    graph_dts(
      "import { useState } from \"./lib\";\nexport function f() { const [n, setN] = useState(0); setN(n + 1); }",
      dts,
    ),
    "",
  )
  // `S` is solved where the parameter IS `S`. Through `S | (() => S)` it
  // comes out `any`, so `const s: string = n` after `useState(0)` is a
  // MISS — a limit of union-parameter inference, in the safe direction.
  assert_true(
    graph_dts(
      "import { pair } from \"./lib\";\nexport function f() { const [n, set] = pair(0); set(n); const s: string = n; }",
      dts,
    ).contains("expected `string` but got `number`"),
  )
  assert_true(
    graph_dts(
      "import { id } from \"./lib\";\nexport const s: string = id(1);", dts,
    ).contains("expected `string` but got `number`"),
  )
}

///|
/// Whether an import names an OVERLOAD set is a fact about the module that
/// DECLARES it, and the check used to ask the module the import named. An
/// overload set re-exported through a barrel — drizzle's `sqlite-core`
/// publishes `integer` with `export * from "./integer.js"` — read as a
/// union-typed value and took the every-member arity rule: "expected at
/// least 2 argument(s)" on `integer("id")`.
test "mtsc graph checker sees an overload set through a barrel re-export" {
  let diagnostics = check_module_graph({
    modules: [
      {
        path: "/src/entry.ts",
        source: "import { integer, int } from \"./index\";\nexport const a = integer(\"id\");\nexport const b = int(\"id\");",
        allowJsx: false,
      },
      {
        path: "/src/index.d.ts",
        source: "export * from \"./integer\";\nexport { integer as int } from \"./integer\";",
        allowJsx: false,
      },
      {
        path: "/src/integer.d.ts",
        source: "export declare function integer(): number;\nexport declare function integer(name: string, config: { mode: string }): number;\nexport declare function integer(name: string): number;",
        allowJsx: false,
      },
    ],
    edges: [
      {
        importerPath: "/src/entry.ts",
        moduleSpecifier: "./index",
        targetPath: "/src/index.d.ts",
      },
      {
        importerPath: "/src/index.d.ts",
        moduleSpecifier: "./integer",
        targetPath: "/src/integer.d.ts",
      },
    ],
  })
  assert_eq(diagnostics, "")
}

///|
/// A module the CLI marks as context — a dependency's `.d.ts` — is read for
/// its declarations and not checked itself.
test "mtsc graph checker does not report inside a context-only module" {
  let graph : MtscModuleGraph = {
    modules: [
      {
        path: "/src/entry.ts",
        source: "import { v } from \"./lib\";\nexport const s: string = v;",
        allowJsx: false,
      },
      {
        path: "/src/lib.d.ts",
        source: "export declare const v: number;\nexport declare const w: Undeclared;",
        allowJsx: false,
      },
    ],
    edges: [
      {
        importerPath: "/src/entry.ts",
        moduleSpecifier: "./lib",
        targetPath: "/src/lib.d.ts",
      },
    ],
  }
  let all = collect_module_graph_issues(graph)
  assert_true(all.iter().any(fn(i) { i.modulePath == "/src/lib.d.ts" }))
  let context = collect_module_graph_issues(graph, context_only={
    "/src/lib.d.ts": (),
  })
  assert_false(context.iter().any(fn(i) { i.modulePath == "/src/lib.d.ts" }))
  // Its declarations still type the importer.
  assert_true(
    context
    .iter()
    .any(fn(i) {
      i.modulePath == "/src/entry.ts" &&
      i.message.contains("expected `string` but got `number`")
    }),
  )
}

///|
/// An imported class read as a VALUE is its constructor, not an instance.
/// It used to arrive as the INSTANCE type, so redi's `injector.add([Svc])`
/// compared `Svc[]` against `[Ctor<T>]` and reported a line tsc accepts.
/// A class declared in the same file is `any` as a value, and the importer
/// now sees the same.
test "mtsc graph checker does not type an imported class value as an instance" {
  let lib = "export class Svc { run(): void {} }"
  assert_eq(
    graph2(
      "import { Svc } from \"./lib\";\ndeclare function add(dep: [new () => unknown]): void;\nadd([Svc]);\nexport const s: Svc = new Svc();",
      lib,
    ),
    "",
  )
  // Its instance type is still the class's.
  assert_true(
    graph2(
      "import { Svc } from \"./lib\";\nexport const n: number = new Svc();", lib,
    ).contains("expected `number`"),
  )
}

///|
/// An overload set's IMPLEMENTATION is not callable when overload
/// signatures exist. Imported with the rest it was the one non-generic
/// member, tried first and accepting any call, so effect's `pipe(a, f)`
/// came back `unknown` from `pipe(a: unknown, …): unknown`.
test "mtsc graph checker leaves an imported overload set's implementation out" {
  let lib = "export function pipe<A>(a: A): A;\nexport function pipe<A, B>(a: A, ab: (a: A) => B): B;\nexport function pipe(a: unknown, ab?: (a: unknown) => unknown): unknown { return ab ? ab(a) : a; }"
  assert_eq(
    graph2(
      "import { pipe } from \"./lib\";\nexport const n: number = pipe(1, (x: number) => x + 1);",
      lib,
    ),
    "",
  )
  // The one-argument overload solves `A` from the argument, so a wrong
  // use reports. (`B` from a callback's return is not inferred, so the
  // two-argument form is `any` — a MISS, not a finding.)
  assert_true(
    graph2(
      "import { pipe } from \"./lib\";\nexport const s: string = pipe(1);", lib,
    ).contains("expected `string` but got `number`"),
  )
}

///|
/// The implementation of an overload set is its LAST declaration, which
/// the parser marks (`<fn-impl:NAME>`); an empty body cannot tell it from
/// a signature by statement count, and kept callable it accepted any
/// argument through its `any` parameter.
test "mtsc graph checker leaves an empty-bodied implementation out" {
  let lib = "export function f(x: string): void;\nexport function f(x: any): void {}\n"
  assert_true(
    graph2("import { f } from \"./lib\";\nf(123);", lib).contains(
      "expected `string` but got `number`",
    ),
  )
  assert_eq(graph2("import { f } from \"./lib\";\nf(\"s\");", lib), "")
}

///|
/// A generic declared function's rest arguments are judged against the
/// rest element when it mentions no type parameter.
test "mtsc graph checker checks an imported generic function's rest arguments" {
  let dts = "export declare function f<T>(x: T, ...rest: string[]): void;\n"
  assert_true(
    graph_dts("import { f } from \"./lib\";\nf(0, 1);", dts).contains(
      "expected `string` but got `number`",
    ),
  )
  assert_eq(
    graph_dts("import { f } from \"./lib\";\nf(0, \"a\", \"b\");", dts),
    "",
  )
}

///|
/// An ambient VALUE typed with a name the checked module renames into:
/// `declare const ambientItem: Item` in an `env.d.ts`. The value's type is
/// computed outside the checker, so the unkeyed move of the ambient
/// `interface Item` did not reach it, and the legal `ambientItem.n` read
/// the checked module's `Other`.
test "mtsc graph checker keeps an ambient value's own type beside a renamed import" {
  let module_ = fn(path : String, source : String) -> MtscModuleSource {
    { path, source, allowJsx: false, }
  }
  let edge = fn(from : String, spec : String, to : String) -> MtscModuleEdge {
    { importerPath: from, moduleSpecifier: spec, targetPath: to, }
  }
  let issues = collect_module_graph_issues({
    modules: [
      module_(
        "/src/root.ts", "import type { Other as Item } from \"./x\";\nexport const m: Item = { z: 1 };\nexport const k: number = ambientItem.n;\nexport const bad: string = ambientItem.n;",
      ),
      module_("/src/x.ts", "export interface Other { z: number }"),
      module_(
        "/src/env.d.ts", "interface Item { n: number }\ndeclare const ambientItem: Item;",
      ),
    ],
    edges: [edge("/src/root.ts", "./x", "/src/x.ts")],
  })
  assert_eq(issues.map(fn(i) { i.path + " :: " + i.message }), [
    "top-level > binding `bad` init :: expected `string` but got `number`",
  ])
}

///|
/// A dependency CLASS member typed with that dependency's own `Item`.
/// Keying moves the dependency's `interface Item` to `Item@/src/b.ts` and
/// rewrites its interfaces and aliases, but class members were copied
/// unchanged, so `Box.item: Item` read the checked module's `Other`.
test "mtsc graph checker keeps a dependency class member's own type beside a renamed import" {
  let module_ = fn(path : String, source : String) -> MtscModuleSource {
    { path, source, allowJsx: false, }
  }
  let edge = fn(from : String, spec : String, to : String) -> MtscModuleEdge {
    { importerPath: from, moduleSpecifier: spec, targetPath: to, }
  }
  let issues = collect_module_graph_issues({
    modules: [
      module_(
        "/src/root.ts", "import type { Other as Item } from \"./x\";\nimport { box } from \"./b\";\nexport const m: Item = { z: 1 };\nexport const k: number = box.item.n;\nexport const bad: string = box.item.n;",
      ),
      module_("/src/x.ts", "export interface Other { z: number }"),
      module_(
        "/src/b.ts", "export interface Item { n: number }\nexport class Box { item!: Item; keep(): void {} }\nexport declare const box: Box;",
      ),
    ],
    edges: [
      edge("/src/root.ts", "./x", "/src/x.ts"),
      edge("/src/root.ts", "./b", "/src/b.ts"),
    ],
  })
  assert_eq(issues.map(fn(i) { i.path + " :: " + i.message }), [
    "top-level > binding `bad` init :: expected `string` but got `number`",
  ])
}

///|
/// A nested namespace gets the checked module's aliases again. Filtering
/// the ambiguous class name out BEFORE that recursion lost the reservation
/// one scope in, so the class was registered there and `x.z` read it.
test "mtsc graph checker keeps an ambiguous class name opaque inside a namespace" {
  let module_ = fn(path : String, source : String) -> MtscModuleSource {
    { path, source, allowJsx: false, }
  }
  let edge = fn(from : String, spec : String, to : String) -> MtscModuleEdge {
    { importerPath: from, moduleSpecifier: spec, targetPath: to, }
  }
  let issues = collect_module_graph_issues({
    modules: [
      module_(
        "/src/root.ts", "import type { Other as Item } from \"./x\";\nimport { mk } from \"./a\";\nexport namespace N {\n  export function read(x: Item): number { return x.z }\n}\nexport const k: number = mk().n;",
      ),
      module_("/src/x.ts", "export interface Other { z: number }"),
      module_(
        "/src/a.ts", "export class Item { n = 1 }\nexport function mk(): Item { return new Item() }",
      ),
    ],
    edges: [
      edge("/src/root.ts", "./x", "/src/x.ts"),
      edge("/src/root.ts", "./a", "/src/a.ts"),
    ],
  })
  assert_eq(issues.map(fn(i) { i.path + " :: " + i.message }), [])
}

///|
/// An interface METHOD's bound (`take<K extends keyof Item>`) is written in
/// the interface's scope, so it has to move with the keyed `Item` like the
/// method's parameters do. Left bare, the bound read the checked module's
/// `Other` and the legal `holder.take("n")` was judged against `"z"`.
test "mtsc graph checker renames a dependency method's bound beside a renamed import" {
  let module_ = fn(path : String, source : String) -> MtscModuleSource {
    { path, source, allowJsx: false, }
  }
  let edge = fn(from : String, spec : String, to : String) -> MtscModuleEdge {
    { importerPath: from, moduleSpecifier: spec, targetPath: to, }
  }
  let issues = collect_module_graph_issues({
    modules: [
      module_(
        "/src/root.ts", "import type { Other as Item } from \"./x\";\nimport { holder } from \"./b\";\nexport const m: Item = { z: 1 };\nholder.take(\"n\");",
      ),
      module_("/src/x.ts", "export interface Other { z: number }"),
      module_(
        "/src/b.ts", "export interface Item { n: number }\nexport interface Taker { take<K extends keyof Item>(k: K): void }\nexport declare const holder: Taker;",
      ),
    ],
    edges: [
      edge("/src/root.ts", "./x", "/src/x.ts"),
      edge("/src/root.ts", "./b", "/src/b.ts"),
    ],
  })
  assert_eq(issues.map(fn(i) { i.path + " :: " + i.message }), [])
}

///|
/// Ambient files share one scope: `env2.d.ts`'s `Holder.item: Item` means
/// `env1.d.ts`'s `interface Item`. A per-file rename map moved the
/// declaration and left the other file's reference bare.
test "mtsc graph checker moves a reserved name across ambient files" {
  let module_ = fn(path : String, source : String) -> MtscModuleSource {
    { path, source, allowJsx: false, }
  }
  let edge = fn(from : String, spec : String, to : String) -> MtscModuleEdge {
    { importerPath: from, moduleSpecifier: spec, targetPath: to, }
  }
  let issues = collect_module_graph_issues({
    modules: [
      module_(
        "/src/root.ts", "import type { Other as Item } from \"./x\";\nexport const m: Item = { z: 1 };\nexport const k: number = amb.item.n;\nexport const bad: string = amb.item.n;",
      ),
      module_("/src/x.ts", "export interface Other { z: number }"),
      module_("/src/env1.d.ts", "interface Item { n: number }"),
      module_(
        "/src/env2.d.ts", "interface Holder { item: Item }\ndeclare const amb: Holder;",
      ),
    ],
    edges: [edge("/src/root.ts", "./x", "/src/x.ts")],
  })
  assert_eq(issues.map(fn(i) { i.path + " :: " + i.message }), [
    "top-level > binding `bad` init :: expected `string` but got `number`",
  ])
}

///|
/// `declare module "m" { … }` in a script-shaped `.d.ts` declares a module
/// that an import of `"m"` reads. Every declaration in the body is exported
/// whether or not it writes `export` (probed: `const hidden` beside an
/// exported `const n` imports cleanly), a renamed import reads it like any
/// other, and the body's types are importable too.
test "mtsc graph checker reads an ambient module declaration as the imported module" {
  let module_ = fn(path : String, source : String) -> MtscModuleSource {
    { path, source, allowJsx: false, }
  }
  let issues = collect_module_graph_issues({
    modules: [
      module_(
        "/src/env.d.ts", "declare module \"m1\" { const n: number; function f(): string; interface I { x: number } }\ndeclare module \"m2\" { export const n: number; const hidden: number; }",
      ),
      module_(
        "/src/main.ts", "import { n, f, type I } from \"m1\";\nimport { n as n2, hidden } from \"m2\";\nexport const s1: string = n;\nexport const s2: number = f();\nexport const i: I = { x: \"s\" };\nexport const s3: string = n2;\nexport const h: number = hidden;\nexport const ok1: number = n + n2;\nexport const ok2: I = { x: 1 };",
      ),
    ],
    edges: [],
  })
  assert_eq(issues.map(fn(i) { i.path }), [
    "top-level > binding `s1` init", "top-level > binding `s2` init", "top-level > binding `i` init.x",
    "top-level > binding `s3` init",
  ])
}

///|
/// A PATTERN (`"*.css"`) answers only where resolution found nothing the
/// program reads: `./a.css` resolves to a file the checker does not read,
/// and the longest prefix wins. An EXACT ambient name wins over a module the
/// resolver did find — a `declare module "dup"` beside a real `dup` package
/// is what `"dup"` means (probed: `a` reads as the ambient `number`).
test "mtsc graph checker applies ambient module precedence" {
  let module_ = fn(path : String, source : String) -> MtscModuleSource {
    { path, source, allowJsx: false, }
  }
  let edge = fn(from : String, spec : String, to : String) -> MtscModuleEdge {
    { importerPath: from, moduleSpecifier: spec, targetPath: to, }
  }
  let issues = collect_module_graph_issues({
    modules: [
      module_(
        "/src/env.d.ts", "declare module \"*.css\" { const c: { [k: string]: number }; export default c; }\ndeclare module \"icons/*\" { const v: number; export default v; }\ndeclare module \"icons/big/*\" { const v: string; export default v; }\ndeclare module \"dup\" { export const a: number; }",
      ),
      module_("/node_modules/dup/index.d.ts", "export declare const a: string;"),
      module_(
        "/src/main.ts", "import c from \"./a.css\";\nimport small from \"icons/x\";\nimport big from \"icons/big/y\";\nimport { a } from \"dup\";\nexport const s1: string = c.x;\nexport const s2: string = small;\nexport const n1: number = big;\nexport const ok: number = a;",
      ),
    ],
    edges: [
      edge("/src/main.ts", "./a.css", "/src/a.css"),
      edge("/src/main.ts", "dup", "/node_modules/dup/index.d.ts"),
    ],
  })
  assert_eq(issues.map(fn(i) { i.path }), [
    "top-level > binding `s1` init", "top-level > binding `s2` init", "top-level > binding `n1` init",
  ])
}

///|
/// A script-shaped declaration file that also holds a `declare module` is
/// still a script. Its block's export list collects the ambient bodies'
/// `export`s, and reading that list made the file a module, so its
/// `declare const G` was invisible to every other file.
test "mtsc graph checker keeps a script's globals beside an ambient module" {
  let module_ = fn(path : String, source : String) -> MtscModuleSource {
    { path, source, allowJsx: false, }
  }
  let issues = collect_module_graph_issues({
    modules: [
      module_(
        "/src/env.d.ts", "declare module \"m\" { export const n: number; }\ndeclare const G: number;",
      ),
      module_(
        "/src/main.ts", "export const ok: number = G;\nexport const bad: string = G;",
      ),
    ],
    edges: [],
  })
  assert_eq(issues.map(fn(i) { i.path + " :: " + i.message }), [
    "top-level > binding `bad` init :: expected `string` but got `number`",
  ])
}

///|
/// An ambient declaration file's types are global: a module that never
/// imports `Holder` still names it, as an annotation and as a member type.
/// The single-file rule behind TS2304 knew only the module's own and
/// imported names, so `const h: Holder = get()` read as `cannot find name`.
test "mtsc graph checker sees an ambient interface as a global type" {
  let module_ = fn(path : String, source : String) -> MtscModuleSource {
    { path, source, allowJsx: false, }
  }
  let issues = collect_module_graph_issues({
    modules: [
      module_(
        "/src/env.d.ts", "interface Holder { item: { n: number } }\ndeclare function get(): Holder;",
      ),
      module_(
        "/src/root.ts", "export const h: Holder = get();\nexport const k: number = h.item.n;\nexport const bad: string = h.item.n;\nexport const q: Missing = 1;",
      ),
    ],
    edges: [],
  })
  assert_eq(issues.map(fn(i) { i.path + " :: " + i.message }), [
    "top-level > binding `bad` init :: expected `string` but got `number`", "var q :: cannot find name `Missing`",
  ])
}

///|
/// An ambient module body is a module of its own, so its `interface Item`
/// collides with the checked module's renamed import like any reachable
/// module's: keyed, it keeps meaning the body's own `Item` for `mk()`,
/// while the checked module's `Item` still reads `Other`.
test "mtsc graph checker keeps an ambient module's own type beside a renamed import" {
  let module_ = fn(path : String, source : String) -> MtscModuleSource {
    { path, source, allowJsx: false, }
  }
  let edge = fn(from : String, spec : String, to : String) -> MtscModuleEdge {
    { importerPath: from, moduleSpecifier: spec, targetPath: to, }
  }
  let issues = collect_module_graph_issues({
    modules: [
      module_(
        "/src/root.ts", "import type { Other as Item } from \"./x\";\nimport { mk } from \"m\";\nexport const m: Item = { z: 1 };\nexport const k: number = mk().n;\nexport const bad: string = mk().n;\nexport const bad2: Item = { z: \"s\" };",
      ),
      module_("/src/x.ts", "export interface Other { z: number }"),
      module_(
        "/src/env.d.ts", "declare module \"m\" { interface Item { n: number } function mk(): Item; }",
      ),
    ],
    edges: [edge("/src/root.ts", "./x", "/src/x.ts")],
  })
  assert_eq(issues.map(fn(i) { i.path + " :: " + i.message }), [
    "top-level > binding `bad` init :: expected `string` but got `number`", "top-level > binding `bad2` init.z :: expected `number` but got `string`",
  ])
}

///|
/// A barrel that re-exports from a module OUTSIDE the checked graph — a
/// bare package with no edge, a relative file that is not there — gives
/// the importer an alias whose origin is unknown. tsc binds such an alias
/// to an unknown symbol and reports nothing on the importer, so neither
/// does this. A name that no re-export chain can provide still reports.
test "mtsc graph checker leaves a re-export from outside the graph unknown" {
  let module_ = fn(path : String, source : String) -> MtscModuleSource {
    { path, source, allowJsx: false, }
  }
  let edge = fn(from : String, spec : String, to : String) -> MtscModuleEdge {
    { importerPath: from, moduleSpecifier: spec, targetPath: to, }
  }
  let issues = collect_module_graph_issues({
    modules: [
      module_(
        "/src/main.ts", "import { x, y, z, w } from \"./barrel\";\nimport d from \"./barrel2\";\nexport const a = x;\nexport const b = y;\nexport const c = z;\nexport const e = d;",
      ),
      module_(
        "/src/barrel.ts", "export { x } from \"ext-pkg\";\nexport { y } from \"./gone\";\nexport * from \"other-pkg\";\nexport const z = 1;",
      ),
      module_("/src/barrel2.ts", "export { default } from \"ext-pkg\";"),
      module_("/src/plain.ts", "export const q = 1;"),
    ],
    edges: [
      edge("/src/main.ts", "./barrel", "/src/barrel.ts"),
      edge("/src/main.ts", "./barrel2", "/src/barrel2.ts"),
    ],
  })
  assert_eq(issues.map(fn(i) { i.path + " :: " + i.message }), [])
  let missing = collect_module_graph_issues({
    modules: [
      module_(
        "/src/main.ts", "import { x, nope } from \"./barrel\";\nexport const a = x;",
      ),
      module_("/src/barrel.ts", "export { x } from \"ext-pkg\";"),
    ],
    edges: [edge("/src/main.ts", "./barrel", "/src/barrel.ts")],
  })
  assert_eq(missing.map(fn(i) { i.message }), [
    "module `./barrel` has no value export `nope`",
  ])
}

///|
fn graph_messages(
  modules : Array[(String, String)],
  edges : Array[(String, String, String)],
) -> Array[String] {
  let issues = collect_module_graph_issues({
    modules: modules.map(fn(m) { { path: m.0, source: m.1, allowJsx: false, } }),
    edges: edges.map(fn(e) {
      { importerPath: e.0, moduleSpecifier: e.1, targetPath: e.2, }
    }),
  })
  issues.map(fn(i) { i.path + " :: " + i.message })
}

///|
/// `import { I } from "./x"` of an interface or a type alias is legal
/// without `type` — only `verbatimModuleSyntax` asks for it — and it read
/// as "has no value export". A type export is not a missing value; a name
/// the module does not export at all still reports.
test "mtsc graph checker accepts an ordinary import of a type" {
  assert_eq(
    graph_messages(
      [
        (
          "/src/x.ts", "export interface I { n: number }\nexport type T = { n: number };",
        ),
        (
          "/src/root.ts", "import { I, T } from \"./x\";\nexport const a: I = { n: 1 };\nexport const b: T = { n: 1 };",
        ),
      ],
      [("/src/root.ts", "./x", "/src/x.ts")],
    ),
    [],
  )
  assert_eq(
    graph_messages(
      [
        (
          "/src/env.d.ts", "declare module \"m\" { export interface I { n: number } }",
        ),
        (
          "/src/root.ts", "import { I } from \"m\";\nexport const ok: I = { n: 1 };\nexport const bad: I = { n: \"s\" };",
        ),
      ],
      [],
    ),
    ["top-level > binding `bad` init.n :: expected `number` but got `string`"],
  )
  assert_eq(
    graph_messages(
      [
        ("/src/x.ts", "export interface I { n: number }"),
        (
          "/src/root.ts", "import { Nope } from \"./x\";\nexport const a = Nope;",
        ),
      ],
      [("/src/root.ts", "./x", "/src/x.ts")],
    ),
    ["import :: module `./x` has no value export `Nope`"],
  )
}

///|
/// `import { n } from "./a"; export { n }` is how a barrel re-exports, and
/// the export names an IMPORT binding, which has no declaration in the
/// barrel. The value is the one the import names, in its own module; a
/// renamed import and a default import follow the same way, a namespace
/// import is a value this checker does not model, and an import from
/// outside the graph is unknown rather than missing.
test "mtsc graph checker follows a barrel's export of an import binding" {
  let edges = [
    ("/src/b.ts", "./a", "/src/a.ts"),
    ("/src/root.ts", "./b", "/src/b.ts"),
  ]
  let a = (
    "/src/a.ts", "export const n: number = 1;\nexport default function d(): number { return 1 }",
  )
  assert_eq(
    graph_messages(
      [
        a,
        (
          "/src/b.ts", "import { n as m } from \"./a\";\nimport d from \"./a\";\nimport * as ns from \"./a\";\nimport { gone } from \"ext-pkg\";\nexport { m as k, d, ns, gone };",
        ),
        (
          "/src/root.ts", "import { k, d, ns, gone } from \"./b\";\nexport const bad: string = k;\nexport const bad2: string = d();\nexport const ok = [ns, gone];",
        ),
      ],
      edges,
    ),
    [
      "top-level > binding `bad` init :: expected `string` but got `number`", "top-level > binding `bad2` init :: expected `string` but got `number`",
    ],
  )
}

///|
/// A `declare module "m" { … }` body is a MODULE. Its virtual file carries
/// no import or export marker, so it read as a script: `hidden` became a
/// global of the whole program, and two bodies each declaring `interface
/// I` merged into one shape, so a legal `I` from `"a"` was missing `y`.
test "mtsc graph checker keeps an ambient module body out of the global scope" {
  assert_eq(
    graph_messages(
      [
        ("/src/env.d.ts", "declare module \"m\" { const hidden: number; }"),
        ("/src/root.ts", "export const x: string = hidden;"),
      ],
      [],
    ),
    ["top-level > use `hidden` :: cannot find name `hidden`"],
  )
  assert_eq(
    graph_messages(
      [
        (
          "/src/env.d.ts", "declare module \"a\" { interface I { x: number } }\ndeclare module \"b\" { interface I { y: string } }",
        ),
        (
          "/src/root.ts", "import type { I } from \"a\";\nexport const ok: I = { x: 1 };\nexport const bad: I = { x: \"s\" };",
        ),
      ],
      [],
    ),
    ["top-level > binding `bad` init.x :: expected `number` but got `string`"],
  )
}

///|
/// An ambient body's own imports and re-exports were resolved relative to
/// the file that holds it, so their edges are keyed by that file. The
/// virtual module is a different importer, so `export { n } from "dep"`
/// and a body-local `import { T } from "dep"` reached nothing.
test "mtsc graph checker follows an ambient body's own imports" {
  let dep = (
    "/node_modules/dep/index.d.ts", "export declare const n: number;\nexport interface T { k: number }",
  )
  let edges = [("/src/env.d.ts", "dep", "/node_modules/dep/index.d.ts")]
  assert_eq(
    graph_messages(
      [
        (
          "/src/env.d.ts", "declare module \"m\" { export { n } from \"dep\"; import { T } from \"dep\"; export function f(): T; }",
        ),
        dep,
        (
          "/src/root.ts", "import { n, f } from \"m\";\nexport const bad: string = n;\nexport const bad2: string = f().k;\nexport const ok: number = n + f().k;",
        ),
      ],
      edges,
    ),
    [
      "top-level > binding `bad` init :: expected `string` but got `number`", "top-level > binding `bad2` init :: expected `string` but got `number`",
    ],
  )
}

///|
/// `declare module "spec";` with no body makes every import from it `any`
/// — exact, a pattern such as `"*.svg"` for a relative import, and over a
/// file the resolver did find. And a default import of a DECLARATION file
/// with no default export (an empty braced body, a `.d.ts` package) gets
/// the synthetic default: TypeScript 7 removed
/// `allowSyntheticDefaultImports: false`, so tsc accepts all of these and
/// still reports TS1192 for the same import of a `.ts` file.
test "mtsc graph checker types shorthand ambient modules and synthetic defaults" {
  assert_eq(
    graph_messages(
      [
        (
          "/src/env.d.ts", "declare module \"spec\";\ndeclare module \"*.svg\";\ndeclare module \"dup\";\ndeclare module \"empty\" {}",
        ),
        ("/node_modules/dup/index.d.ts", "export declare const a: string;"),
        ("/node_modules/p/index.d.ts", "export declare const k: number;"),
        (
          "/src/root.ts", "import v, { w } from \"spec\";\nimport logo from \"./logo.svg\";\nimport { a } from \"dup\";\nimport e from \"empty\";\nimport p from \"p\";\nexport const x1: number = v;\nexport const x2: string = w;\nexport const x3: number = logo;\nexport const x4: number = a;\nexport const x5 = [e, p];",
        ),
      ],
      [
        ("/src/root.ts", "dup", "/node_modules/dup/index.d.ts"),
        ("/src/root.ts", "p", "/node_modules/p/index.d.ts"),
      ],
    ),
    [],
  )
  assert_eq(
    graph_messages(
      [
        ("/src/real.ts", "export const k: number = 1;"),
        ("/src/root.ts", "import d from \"./real\";\nexport const a = d;"),
      ],
      [("/src/root.ts", "./real", "/src/real.ts")],
    ),
    ["import :: module `./real` has no default value export"],
  )
}

///|
/// A body's own import of a module a SHORTHAND declares is untyped as
/// well. The body's edge is copied from the file that holds it, and that
/// copy skipped the shorthand filter, so `"short"` read the package file
/// the resolver had found and `x` came out a `string`.
test "mtsc graph checker leaves a body's shorthand import untyped" {
  assert_eq(
    graph_messages(
      [
        (
          "/src/env.d.ts", "declare module \"short\";\ndeclare module \"m\" { export { x } from \"short\"; }",
        ),
        ("/node_modules/short/index.d.ts", "export declare const x: string;"),
        (
          "/src/root.ts", "import { x } from \"m\";\nexport const n: number = x;",
        ),
      ],
      [("/src/env.d.ts", "short", "/node_modules/short/index.d.ts")],
    ),
    [],
  )
}

///|
/// Two more places ambient type names are global: the members of a
/// `declare global { … }` block in a reachable MODULE, and the single-letter
/// type-parameter check, which asked only the checked module.
test "mtsc graph checker sees declare-global and single-letter ambient types" {
  assert_eq(
    graph_messages(
      [
        (
          "/src/g.d.ts", "export declare const tag: number;\ndeclare global { interface Holder { n: number } function get(): Holder; }",
        ),
        (
          "/src/root.ts", "import { tag } from \"./g\";\nexport const t = tag;\nexport const h: Holder = get();\nexport const bad: string = h.n;",
        ),
      ],
      [("/src/root.ts", "./g", "/src/g.d.ts")],
    ),
    ["top-level > binding `bad` init :: expected `string` but got `number`"],
  )
  assert_eq(
    graph_messages(
      [
        ("/src/env.d.ts", "interface A { n: number }"),
        (
          "/src/root.ts", "declare const value: A;\nexport const bad: string = value.n;",
        ),
      ],
      [],
    ),
    ["top-level > binding `bad` init :: expected `string` but got `number`"],
  )
}

///|
/// A reserved name moved in a file with no key has to move inside its
/// namespace bodies too: `declare namespace N { interface Holder { item:
/// Item } }` read the checked module's renamed `Other`. A namespace that
/// declares its own `Item` keeps it.
test "mtsc graph checker moves a reserved name inside an ambient namespace" {
  let x = ("/src/x.ts", "export interface Other { z: number }")
  let edges = [("/src/root.ts", "./x", "/src/x.ts")]
  assert_eq(
    graph_messages(
      [
        (
          "/src/root.ts", "import type { Other as Item } from \"./x\";\nexport const m: Item = { z: 1 };\nexport const k: number = holder.item.n;\nexport const bad: string = holder.item.n;",
        ),
        x,
        (
          "/src/env.d.ts", "interface Item { n: number }\ndeclare namespace N { interface Holder { item: Item } }\ndeclare const holder: N.Holder;",
        ),
      ],
      edges,
    ),
    ["top-level > binding `bad` init :: expected `string` but got `number`"],
  )
  assert_eq(
    graph_messages(
      [
        (
          "/src/root.ts", "import type { Other as Item } from \"./x\";\nexport const m: Item = { z: 1 };\nexport const k: string = holder.item.s;",
        ),
        x,
        (
          "/src/env.d.ts", "interface Item { n: number }\ndeclare namespace N { interface Item { s: string } interface Holder { item: Item } }\ndeclare const holder: N.Holder;",
        ),
      ],
      edges,
    ),
    [],
  )
}

///|
/// An imported enum's members travel with it. Only the enum table was
/// copied into the importer, so `Kind.PARAGRAPH` read as `any` there: a
/// `n?.kind === Kind.PARAGRAPH` guard never ruled out `undefined` (univer's
/// `_applyContextualParagraphSpacing`), and a member against the wrong type
/// or the wrong arm of a discriminated union passed (probed: tsc reports
/// exactly the two `bad` lines).
test "mtsc graph checker types an imported enum's members (enumimport)" {
  let lib =
    #|export enum Kind { PARAGRAPH = "p", TABLE = "t" }
    #|export enum Level { LOW, HIGH }
    #|export interface Node { kind: Kind; text: string }
    #|export interface Para { kind: Kind.PARAGRAPH; text: string }
    #|export interface Table { kind: Kind.TABLE; rows: number }
    #|export interface Item { level: Level; label: string }
  let entry =
    #|import { Kind, Level, Node, Para, Table, Item } from "./lib";
    #|declare const n: Node | undefined;
    #|declare const xs: number[];
    #|export function okNarrow(): string { if (n?.kind === Kind.PARAGRAPH) { return n.text; } return ""; }
    #|export const badNumber: number = Kind.PARAGRAPH;
    #|export const okBlocks: (Para | Table)[] = xs.map(() => ({ kind: Kind.PARAGRAPH, text: "" }));
    #|export const okItems: Item[] = xs.map((i) => ({ level: Level.HIGH, label: String(i) }));
    #|export const badBlocks: Para[] = xs.map(() => ({ kind: Kind.TABLE, text: "" }));
  assert_eq(
    graph_messages([("/src/lib.ts", lib), ("/src/entry.ts", entry)], [
      ("/src/entry.ts", "./lib", "/src/lib.ts"),
    ]),
    [
      "top-level > binding `badNumber` init :: expected `number` but got `string`",
      "top-level > binding `badBlocks` init :: expected `Para[]` but got `{ kind: Kind.TABLE; text: \"\" (string) }[]`",
    ],
  )
}

///|
/// Two declarations of one enum NAME — the checked module's `S` and a
/// second module's, kept under its per-module key — are related only when
/// every member of the source is a member of the target with the same
/// value (TS 5.4). The name-only comparison accepted the checked module's
/// `S` wherever the other one was expected (#315's review; probed: tsc
/// reports exactly the two `bad` lines and accepts the identical enum).
test "mtsc graph checker keeps two same-named enums apart unless related (enumident)" {
  let lib =
    #|export enum S { X = "x", Y = "y" }
    #|export enum Same { X = "x" }
    #|export interface Holder { s: S }
    #|export interface HolderSame { s: Same }
  let entry =
    #|import { Holder, HolderSame } from "./lib";
    #|enum S { X = "q" }
    #|enum Same { X = "x" }
    #|declare const e: S;
    #|declare const same: Same;
    #|const o = { s: e };
    #|export const badViaBinding: Holder = o;
    #|export const badDirect: Holder = { s: e };
    #|const os = { s: same };
    #|export const okSameViaBinding: HolderSame = os;
    #|export const okSameDirect: HolderSame = { s: same };
  assert_eq(
    graph_messages([("/src/lib.ts", lib), ("/src/entry.ts", entry)], [
      ("/src/entry.ts", "./lib", "/src/lib.ts"),
    ]),
    [
      "top-level > binding `badViaBinding` init :: expected `Holder` but got `{ s: S }`",
      "top-level > binding `badDirect` init.s :: expected `S` but got `S`, a different declaration of the enum whose members differ",
    ],
  )
}

///|
/// A computed (numeric) member does not relate to a string member of the
/// same name in another declaration of the enum (#315's review; probed:
/// tsc reports `bad`).
test "mtsc graph checker keeps a computed member apart from a string one (enumident2)" {
  let lib =
    #|export enum S { A = "a" }
    #|export interface H { s: S }
  let entry =
    #|import { H } from "./lib";
    #|declare function f(): number;
    #|enum S { A = f() }
    #|declare const e: S;
    #|export const bad: H = { s: e };
  assert_eq(
    graph_messages([("/src/lib.ts", lib), ("/src/entry.ts", entry)], [
      ("/src/entry.ts", "./lib", "/src/lib.ts"),
    ]),
    [
      "top-level > binding `bad` init.s :: expected `S` but got `S`, a different declaration of the enum whose members differ",
    ],
  )
}

///|
/// An enum imported under another name, while the importer declares its
/// own enum of the original name, reads its members through the alias: a
/// `n?.kind === RE.A` guard narrows `n`, and `RE.A` against `number` is
/// reported (#315's review; probed: tsc reports `badMember` only).
test "mtsc graph checker reads members through an enum import alias (enumalias)" {
  let lib =
    #|export enum E { A = "a", B = "b" }
    #|export interface N { kind: E }
  let entry =
    #|import { E as RE, N } from "./lib";
    #|enum E { Z = "z" }
    #|declare const n: N | undefined;
    #|export function okNarrow(): string { if (n?.kind === RE.A) { return n.kind; } return ""; }
    #|export const badMember: number = RE.A;
  assert_eq(
    graph_messages([("/src/lib.ts", lib), ("/src/entry.ts", entry)], [
      ("/src/entry.ts", "./lib", "/src/lib.ts"),
    ]),
    [
      "top-level > binding `badMember` init :: expected `number` but got `string`",
    ],
  )
}

///|
/// A local binding of an enum import alias's name is what the name means:
/// a parameter `RE: any` and a local object both shadow `import { E as RE
/// }`, while the unshadowed `RE.A` still reads the enum (#315's review;
/// probed: tsc reports `badUnshadowed` only).
test "mtsc graph checker lets a local shadow an enum import alias (enumalias2)" {
  let lib =
    #|export enum E { A = "a", B = "b" }
  let entry =
    #|import { E as RE } from "./lib";
    #|export function okShadowedByAny(RE: any) { const n: number = RE.A; return n; }
    #|export function okShadowedByLocal() { const RE = { A: 1 }; const n: number = RE.A; return n; }
    #|export const badUnshadowed: number = RE.A;
  assert_eq(
    graph_messages([("/src/lib.ts", lib), ("/src/entry.ts", entry)], [
      ("/src/entry.ts", "./lib", "/src/lib.ts"),
    ]),
    [
      "top-level > binding `badUnshadowed` init :: expected `number` but got `string`",
    ],
  )
}

///|
/// An imported class's unannotated statics carry the parser's
/// `<unannotated-static-return:>` sentinel through the graph, so a factory
/// whose body is `return new Num(v)` narrows an assignment after
/// `if (x == null)` as it does in one file (univer's
/// `NumberValueObject.create(0)` in `mina`). A factory that can return
/// `null` keeps the binding nullable (probed: tsc reports `badMaybe` only).
test "mtsc graph checker reads an imported static factory's body (staticimport)" {
  let lib =
    #|export class Base { isBoolean(): boolean { return false; } }
    #|export class Num extends Base {
    #|  private constructor(public v: number) { super(); }
    #|  static create(value: number, pattern: string = "") { return new Num(value); }
    #|  static maybe(value: number) { return value > 0 ? new Num(value) : null; }
    #|}
  let entry =
    #|import type { Base } from "./lib";
    #|import { Num } from "./lib";
    #|export function okJoin(v: Base | null | undefined) { let x = v; if (x == null) { x = Num.create(0); } return x.isBoolean(); }
    #|export function badMaybe(v: Base | null | undefined) { let x = v; if (x == null) { x = Num.maybe(0); } return x.isBoolean(); }
  assert_eq(
    graph_messages([("/src/lib.ts", lib), ("/src/entry.ts", entry)], [
      ("/src/entry.ts", "./lib", "/src/lib.ts"),
    ]),
    ["function badMaybe > call `isBoolean` :: object is possibly `undefined`"],
  )
}

///|
/// An imported function with no return annotation is typed from its body,
/// as one declared in the importer's file is: the graph path read the
/// declaration, where the absent annotation is `any`, so univer's
/// `lineWidth = getLineWidth(style)` narrowed nothing. Only a primitive
/// result of the COMPLETE body is adopted, so a nested `return opaque`
/// keeps `any`; the declaring module's `strictNullChecks` decides `??`; a
/// bounded generic carries the result too; and a written `: any` stays
/// `any` (#317's review; probed: tsc reports the two bad cells only).
test "mtsc graph checker types an imported unannotated return (importedreturn)" {
  let lib =
    #|export enum Style { THIN, MEDIUM, THICK }
    #|export function getLineWidth(style: Style) {
    #|  let lineWidth = 1;
    #|  if (style === Style.MEDIUM) { lineWidth = 2; } else if (style === Style.THICK) { lineWidth = 3; }
    #|  return lineWidth;
    #|}
    #|export function getName(style: Style) { return style === Style.THIN ? "thin" : "other"; }
    #|export function written(): any { return 1; }
    #|declare const opaque: any;
    #|export function nested(flag: boolean) { if (flag) return opaque; return 1; }
    #|export function coalesce(x: number) { return x ?? "fallback"; }
    #|export function gen<T extends number>(t: T) { return 1; }
  let entry =
    #|import { getLineWidth, getName, written, nested, coalesce, gen, Style } from "./lib";
    #|declare function use(n: number): void;
    #|interface Ctx { lineWidth?: number; lineStyle?: Style }
    #|export function ok(c: Ctx, style: Style) {
    #|  let lineWidth = c.lineWidth;
    #|  if (c.lineStyle !== style || lineWidth === undefined) { lineWidth = getLineWidth(style); use(lineWidth); }
    #|  return (lineWidth - 1) / 2;
    #|}
    #|export function okWrittenAny() { const s: string = written(); return s; }
    #|export function okNestedAny() { const s: string = nested(true); return s; }
    #|export function okStrictCoalesce() { const n: number = coalesce(0); return n; }
    #|export function badName(style: Style) { const n: number = getName(style); return n; }
    #|export function badGeneric() { const s: string = gen(1); return s; }
  assert_eq(
    graph_messages([("/src/lib.ts", lib), ("/src/entry.ts", entry)], [
      ("/src/entry.ts", "./lib", "/src/lib.ts"),
    ]),
    [
      "function badName > binding `n` init :: expected `number` but got `string`",
      "function badGeneric > binding `s` init :: expected `string` but got `number`",
    ],
  )
}

///|
/// A type-alias parameter the use omits takes its DEFAULT. It stayed an
/// unbound name, and in graph mode that name resolves to whatever else the
/// program spells that way: testing-library's `RenderResult<typeof
/// queries>` left `container: Container`, which read react-dom's
/// unrelated `Container` (excalidraw's `container.querySelector`; probed:
/// tsc reports the `y` line only).
test "mtsc graph checker binds an omitted alias argument to its default (aliasdefault)" {
  assert_eq(
    graph_messages(
      [
        ("/src/rd.ts", "export interface Container { nope(): void }"),
        (
          "/src/lib.ts", "import * as RD from \"./rd\";\ntype RC = RD.Container;\nexport type R<Q = string, Container extends RC | Element = HTMLElement> = { container: Container; q: Q };",
        ),
        (
          "/src/root.ts", "import type { R } from \"./lib\";\ndeclare const r: R<boolean>;\nexport const x = r.container.querySelector(\"a\");\nexport const y: number = r.q;",
        ),
      ],
      [
        ("/src/lib.ts", "./rd", "/src/rd.ts"),
        ("/src/root.ts", "./lib", "/src/lib.ts"),
      ],
    ),
    ["top-level > binding `y` init :: expected `number` but got `boolean`"],
  )
}

///|
/// #319's review. An imported alias's default is written in the EXPORTING
/// module, so `A<T = Item>` from `./a` reads `a.ts`'s `Item` even where the
/// importer declares its own: the per-module rename reaches the defaults.
test "mtsc graph checker reads an imported alias's default in its own module (nsdefault)" {
  assert_eq(
    graph_messages(
      [
        (
          "/src/a.ts", "export type Item = string;\nexport type A<T = Item> = { v: T };",
        ),
        (
          "/src/root.ts", "import type { A } from \"./a\";\ntype Item = number;\ndeclare const a: A;\nexport const s: string = a.v;\nexport const n: number = a.v;\nexport const u: Item = 1;",
        ),
      ],
      [("/src/root.ts", "./a", "/src/a.ts")],
    ),
    ["top-level > binding `n` init :: expected `number` but got `string`"],
  )
}

///|
/// The same default inside a NAMESPACE of the exporting module: a keyed
/// module's namespace bodies are rewritten by `rename_namespace_body_refs`,
/// which has to reach the defaults too, or `N.A`'s `Item` reads the
/// importer's (probed: tsc reports `n` only).
test "mtsc graph checker reads a namespace alias's default in its own module (nsdefault)" {
  assert_eq(
    graph_messages(
      [
        (
          "/src/a.ts", "export type Item = string;\nexport namespace N { export type A<T = Item> = { v: T }; }",
        ),
        (
          "/src/root.ts", "import { N } from \"./a\";\ntype Item = number;\ndeclare const a: N.A;\nexport const s: string = a.v;\nexport const n: number = a.v;\nexport const u: Item = 1;",
        ),
      ],
      [("/src/root.ts", "./a", "/src/a.ts")],
    ),
    ["top-level > binding `n` init :: expected `number` but got `string`"],
  )
}

///|
/// `import { N }` of a namespace that holds only types binds no value and is
/// legal; it read as "has no value export". A namespace the module does not
/// export still reports (probed: tsc gives TS2459 for that one).
test "mtsc graph checker accepts an import of a type-only namespace" {
  assert_eq(
    graph_messages(
      [
        ("/src/a.ts", "export namespace N { export type A = { v: string }; }"),
        (
          "/src/b.ts", "namespace M { export type A = { v: string }; }\nexport type Keep = number;",
        ),
        (
          "/src/root.ts", "import { N } from \"./a\";\nimport { M } from \"./b\";\ndeclare const x: N.A;\nexport const s: string = x.v;",
        ),
      ],
      [
        ("/src/root.ts", "./a", "/src/a.ts"),
        ("/src/root.ts", "./b", "/src/b.ts"),
      ],
    ),
    ["import :: module `./b` has no value export `M`"],
  )
}

///|
/// An imported `const` object built with a SPREAD of another `const` of
/// its module was `any` to every importer, so `m?.keyword === MIME.ex` did
/// not narrow `m` (excalidraw's `MIME_TYPES`). A spread of the module's own
/// const object is folded in now; a result holding a computed key still
/// reads as `any`, since it is not enumerable. An optional property spread
/// over a required one keeps the required type in tsc, which the recorded
/// `T | undefined` cannot show, so that key reads as `any`. A member of an
/// unannotated `as const` object is its literal, spread or not, and an
/// annotation keeps its own type (#322's review; probed:
/// tsc reports `n`, `nope` and `Y.j`'s binding only).
test "mtsc graph checker folds a same-module const spread into an imported value" {
  assert_eq(
    graph_messages(
      [
        (
          "/src/c.ts", "export const SMIME = { ex: \"application/x\", text: \"text/plain\" } as const;\nexport const MIME = { ...SMIME, bin: \"b\" } as const;\nexport const K = \"k\";\nexport const CK = { [K]: 1 };\nexport const CM = { ...CK, z: 2 };\nexport const BASE: { k?: number } = {};\nexport const X = { k: 0, ...BASE };\nexport const BASE2: { j?: number } = {};\nexport const Y = { ...BASE2 };\nexport const AX: { k: string; j?: number } = { k: \"a\" } as const;",
        ),
        (
          "/src/root.ts", "import { MIME, SMIME, CM, X, Y, AX } from \"./c\";\ndeclare function get(): { keyword: string; text: string } | null;\nexport function okSpreadMember() { const m = get(); if (m?.keyword === MIME.ex) { return m.text; } return \"\"; }\nexport function probeSpread() { const n: number = MIME.ex; return n; }\nexport function badSpreadMemberMissing() { return MIME.nope; }\nexport function okComputedSpread() { return CM.k; }\nexport function okOptionalSpreadOverRequired() { const n: number = X.k; return n; }\nexport function badOptionalSpreadAlone() { const n: number = Y.j; return n; }\nexport function okConstMemberLiteral() { const ex: \"application/x\" = MIME.ex; return ex; }\nexport function okConstSourceLiteral() { const t: \"text/plain\" = SMIME.text; return t; }\nexport function okAnnotatedOptional() { const j: number | undefined = AX.j; return j; }\nexport function okAnnotatedWide() { let s = AX.k; s = \"zz\"; return s; }",
        ),
      ],
      [("/src/root.ts", "./c", "/src/c.ts")],
    ),
    [
      "function probeSpread > binding `n` init :: expected `number` but got `string`",
      "function badSpreadMemberMissing > PropAccess `.nope` :: property `nope` does not exist on `{ ex: \"application/x\" (string); text: \"text/plain\" (string); bin: \"b\" (string) }`",
      "function badOptionalSpreadAlone > binding `n` init :: type `number | undefined` is not assignable to type `number`",
    ],
  )
}

///|
/// A barrel passes a type-only namespace on as `export { N } from`, as
/// `export *`, as `export type { N } from`, and as an import it exports
/// again, including a type-only import exported as a type; each read as
/// "has no value export" (#321's and #322's reviews; probed: tsc accepts
/// all five). A name the barrel does not export still reports, and so does
/// `default` through `export *`, which does not re-export it (TS2305).
test "mtsc graph checker follows a barrel to a type-only namespace" {
  assert_eq(
    graph_messages(
      [
        ("/src/a.ts", "export namespace N { export type A = { v: string }; }"),
        ("/src/barrel.ts", "export { N } from \"./a\";"),
        ("/src/star.ts", "export * from \"./a\";"),
        ("/src/tbarrel.ts", "export type { N } from \"./a\";"),
        ("/src/reexp.ts", "import { N } from \"./a\";\nexport { N };"),
        (
          "/src/treexp.ts", "import type { N } from \"./a\";\nexport type { N };",
        ),
        (
          "/src/dsrc.ts", "namespace D { export type A = { v: string }; }\nexport default D;",
        ),
        ("/src/dstar.ts", "export * from \"./dsrc\";"),
        (
          "/src/amb.ts", "namespace M { export type A = { v: string }; }\nexport type Keep = number;",
        ),
        (
          "/src/root.ts", "import { N } from \"./barrel\";\nimport { N as N2 } from \"./star\";\nimport { N as N3 } from \"./tbarrel\";\nimport { N as N4 } from \"./reexp\";\nimport { N as N5 } from \"./treexp\";\nimport { default as N6 } from \"./dstar\";\nimport { M } from \"./amb\";\ndeclare const x: N.A;\nexport const s: string = x.v;",
        ),
      ],
      [
        ("/src/barrel.ts", "./a", "/src/a.ts"),
        ("/src/star.ts", "./a", "/src/a.ts"),
        ("/src/tbarrel.ts", "./a", "/src/a.ts"),
        ("/src/reexp.ts", "./a", "/src/a.ts"),
        ("/src/treexp.ts", "./a", "/src/a.ts"),
        ("/src/dstar.ts", "./dsrc", "/src/dsrc.ts"),
        ("/src/root.ts", "./barrel", "/src/barrel.ts"),
        ("/src/root.ts", "./star", "/src/star.ts"),
        ("/src/root.ts", "./tbarrel", "/src/tbarrel.ts"),
        ("/src/root.ts", "./reexp", "/src/reexp.ts"),
        ("/src/root.ts", "./treexp", "/src/treexp.ts"),
        ("/src/root.ts", "./dstar", "/src/dstar.ts"),
        ("/src/root.ts", "./amb", "/src/amb.ts"),
      ],
    ),
    [
      "import :: module `./dstar` has no value export `default`", "import :: module `./amb` has no value export `M`",
    ],
  )
}

///|
/// An ambient `.d.ts` has no per-module key, so a name the checked module
/// renames into moves to `Item@<unkeyed>` there, and its references move
/// with it. A default is one of them: `Box<T = Item>` has to keep reading
/// the ambient `Item`, not the checked module's renamed import, at the top
/// level and inside a `declare namespace` (probed: tsc reports `bad` and
/// `bad2` only).
test "mtsc graph checker keeps an ambient alias's default beside a renamed import" {
  let module_ = fn(path : String, source : String) -> MtscModuleSource {
    { path, source, allowJsx: false, }
  }
  let edge = fn(from : String, spec : String, to : String) -> MtscModuleEdge {
    { importerPath: from, moduleSpecifier: spec, targetPath: to, }
  }
  let issues = collect_module_graph_issues({
    modules: [
      module_(
        "/src/root.ts", "import type { Other as Item } from \"./x\";\nexport const m: Item = { z: 1 };\nexport const k: number = box.v.n;\nexport const bad: string = box.v.n;\nexport const k2: number = box2.v.n;\nexport const bad2: string = box2.v.n;",
      ),
      module_("/src/x.ts", "export interface Other { z: number }"),
      module_(
        "/src/env.d.ts", "interface Item { n: number }\ntype Box<T = Item> = { v: T };\ndeclare const box: Box;\ndeclare namespace NS { type Box2<T = Item> = { v: T }; }\ndeclare const box2: NS.Box2;",
      ),
    ],
    edges: [edge("/src/root.ts", "./x", "/src/x.ts")],
  })
  assert_eq(issues.map(fn(i) { i.path + " :: " + i.message }), [
    "top-level > binding `bad` init :: expected `string` but got `number`", "top-level > binding `bad2` init :: expected `string` but got `number`",
  ])
}

///|
/// An unannotated function's return type is read off its body while the
/// module is ingested, and an imported value was installed only after that,
/// so `function g() { return AL }` with `AL` imported from another module
/// returned `any` while `AL` itself read as `number` (univer's line
/// breaker). A primitive import is installed before ingestion as well
/// (probed: tsc reports `bad` and `badReturn` only).
test "mtsc graph checker reads an imported primitive const in an unannotated return" {
  assert_eq(
    graph_messages(
      [
        (
          "/src/classes.ts", "export const AL = 1;\nexport const AI = 3;\nconst K = 1;\nexport function returnsOwnConst() { return K; }",
        ),
        (
          "/src/root.ts", "import { AI, AL, returnsOwnConst } from \"./classes\";\nfunction mapClass(c: number) { switch (c) { case AI: return AL; default: return c; } }\nfunction g() { return AL; }\nfunction take(n: number) { return n; }\nexport function okNarrows() { let n: number | undefined = undefined; n = mapClass(1); return take(n); }\nexport function bad() { const s: string = mapClass(1); return s; }\nexport function badReturn() { const s: string = g(); return s; }\nexport function badImportedReturn() { const s: string = returnsOwnConst(); return s; }",
        ),
      ],
      [("/src/root.ts", "./classes", "/src/classes.ts")],
    ),
    [
      "function bad > binding `s` init :: expected `string` but got `number`", "function badReturn > binding `s` init :: expected `string` but got `number`",
      "function badImportedReturn > binding `s` init :: expected `string` but got `number`",
    ],
  )
}
