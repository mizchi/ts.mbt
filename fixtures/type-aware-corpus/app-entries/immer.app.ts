// immer, used the way its documentation's first example uses it: a
// `produce` over a nested draft, plus the patch and Map/Set plugins the
// package-entry driver enables.
//
// `readme.md` carries no TypeScript block, so the usage here is the
// first example from immer's own docs site (`docs/introduction.md`
// / `produce`), not a shape chosen to suit the compiler.
//
// Every export is a scalar.

import {
  applyPatches,
  enableMapSet,
  enablePatches,
  Patch,
  produce,
  produceWithPatches,
} from "./src/immer.ts";

enablePatches();
enableMapSet();

type Todo = { title: string; done: boolean };
type State = {
  todos: Todo[];
  meta: { count: number; tags: Set<string>; byId: Map<string, number> };
};

const base: State = {
  todos: [
    { title: "learn immer", done: true },
    { title: "try immer", done: false },
  ],
  meta: { count: 2, tags: new Set(["a"]), byId: new Map([["x", 1]]) },
};

const next = produce(base, (draft) => {
  draft.todos.push({ title: "tame immer", done: false });
  draft.todos[1].done = true;
  draft.meta.count = draft.todos.length;
  draft.meta.tags.add("b");
  draft.meta.byId.set("y", 2);
});

const [patched, patches, inverse] = produceWithPatches(base, (draft) => {
  draft.todos[0].title = "renamed";
  draft.meta.count = 99;
});

function shape(s: State): string {
  return s.todos.map((t) => t.title + ":" + t.done).join(",") +
    " count=" + s.meta.count +
    " tags=" + [...s.meta.tags].join("+") +
    " ids=" + [...s.meta.byId.entries()].map(([k, v]) => k + v).join("+");
}

export const unchanged: boolean = base.todos.length === 2 &&
  base.meta.count === 2;
export const produced: string = shape(next);
export const withPatches: string = shape(patched);
export const patchOps: string = (patches as Patch[])
  .map((p) => p.op + " " + p.path.join("/"))
  .join(",");
export const roundTrip: string = shape(
  applyPatches(patched, inverse as Patch[]),
);
export const frozen: boolean = Object.isFrozen(next.todos);
