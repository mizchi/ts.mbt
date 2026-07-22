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
  assert_eq(diagnostics.split("expected `string` but got `number`").length(), 3)
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
