// An aliased import whose TARGET name is shadowed at the reference site.
//
// The linker records `subs[local_alias] = resolved` and rewrites
// `Var(local_alias)` to `Var(resolved)` inside the importing module. The
// rewrite walker tracks shadowing of the name it REPLACES — an inner
// scope that re-binds the alias keeps its own binding — and cannot track
// shadowing of the name it SUBSTITUTES, because that name is not in the
// map it narrows.
//
// So the target name being declared in a nested scope captures the
// reference. Found on `@sprawlens/viz`'s `App.tsx`, which does
//
//   import { parentFileOf as contractParentFileOf } from "@sprawlens/schema";
//   const moduleOfId = (id) => currentModuleIdOf()(contractParentFileOf(id));
//   ...
//   const parentFileOf = (id) => symbolMetaRef.current.get(id)?.fileId ?? …;
//
// inside one component body. `contractParentFileOf` appeared ZERO times
// in the bundle: every use became `parentFileOf`, which there is the
// local `const`. `ReferenceError: Cannot access 'parentFileOf' before
// initialization`, under plain `mtsc --bundle` with no optimization flag.
//
// Both failure modes are below, because they are not equally visible.

import { label as outerLabel, other as outerOther } from "./helper.ts";

// (1) TDZ. The import is read through `use` BEFORE the shadowing `const
// label` initializes, so a captured reference throws rather than
// returning the wrong thing. This is the form sprawlens hit.
function tdzForm(): string {
  const use = () => outerLabel("x");
  const early = use();
  const label = (id: string): string => "L:" + id;
  return early + "|" + label("y");
}

// (2) WRONG VALUE. Same capture, but the shadowing `const` is already
// initialized when the reference runs, so nothing throws and the answer
// is silently the local function's. No crash and no free variable, so
// `--verify` cannot see this one at all.
function wrongValueForm(): string {
  const label = (id: string): string => "L:" + id;
  const use = () => outerLabel("x");
  return use() + "|" + label("y");
}

// (3) A PARAMETER named after the target, which no block declares — the
// spelling that defeated a block-level check in `case43`.
function paramForm(label: (id: string) => string): string {
  return outerLabel("x") + "|" + label("y");
}

// (4) The control. Nothing shadows `other`, so the substitution must
// still happen and the import must still be reached — the fix cannot be
// "stop substituting".
function unshadowed(): string {
  return outerOther("x");
}

export const report = {
  tdzForm: tdzForm(),
  wrongValueForm: wrongValueForm(),
  paramForm: paramForm((id: string) => "P:" + id),
  unshadowed: unshadowed(),
};
