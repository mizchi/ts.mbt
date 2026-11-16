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
