// immer: the four `ArchType` dispatch paths, plus patches and freezing.
//
// This driver exists because of a specific bug. `export const enum
// ArchType` is declared in one module and read from several others; a
// const enum emits no runtime binding, so the cross-module reads had
// nothing to resolve and the bundle threw `ArchType is not defined` at
// load. That made immer measurable by SIZE only, which is the weakest
// possible verdict — a size delta on a bundle that cannot run says
// nothing about whether the passes were correct.
//
// The values themselves are the thing to check, not just that the
// module loads: `ArchType` picks which proxy implementation handles a
// draft, so substituting the wrong literal would route an Array through
// the object path and still load fine. So every arch gets exercised
// and its result observed.
import {
  produce,
  produceWithPatches,
  applyPatches,
  createDraft,
  finishDraft,
  enableMapSet,
  enablePatches,
  freeze,
  isDraft,
  isDraftable,
  original,
  current,
  nothing,
  immerable,
  setAutoFreeze,
} from "./target.mjs";

enableMapSet();
enablePatches();

const out = [];

// ArchType.Object
const base = { a: 1, nested: { x: 1 }, keep: "same" };
const next = produce(base, (d) => {
  d.a = 2;
  d.nested.x = 9;
});
out.push([next.a, next.nested.x, next.keep, base.a, base.nested.x]);
// Structural sharing: an untouched subtree must be the SAME object.
out.push(next.keep === base.keep);

// ArchType.Array — including the length-changing operations, which the
// array proxy handles differently from a plain index write.
const arr = produce([1, 2, 3], (d) => {
  d.push(4);
  d[0] = 9;
});
out.push(arr);
// Block bodies throughout: immer rejects a recipe that both returns a
// value and mutates the draft, and `splice` / `sort` return one.
out.push(produce([1, 2, 3], (d) => { d.splice(1, 1); }));
out.push(produce([1, 2, 3], (d) => { d.length = 1; }));
out.push(produce([3, 1, 2], (d) => { d.sort(); }));

// ArchType.Map
const m = produce(new Map([["k", { v: 1 }]]), (d) => {
  d.get("k").v = 5;
  d.set("j", { v: 7 });
  d.delete("gone");
});
out.push([...m].map(([k, o]) => [k, o.v]));
out.push(produce(new Map([["a", 1], ["b", 2]]), (d) => d.clear()).size);

// ArchType.Set
out.push([...produce(new Set([1, 2]), (d) => { d.add(3); d.delete(1); })]);

// Patches — the inverse patch is what catches a value substituted with
// the wrong literal, because it has to describe the same path back.
const [withPatches, patches, inverse] = produceWithPatches(base, (d) => {
  d.a = 42;
});
out.push([withPatches.a, patches, inverse]);
out.push(applyPatches(withPatches, inverse).a);

// The explicit draft lifecycle, which does not go through `produce`.
const draft = createDraft({ n: 1 });
draft.n = 2;
out.push([isDraft(draft), original(draft).n, current(draft).n, finishDraft(draft).n]);

// `nothing` as a produce result, and the recipe returning a new value.
out.push(produce({ a: 1 }, () => nothing));
out.push(produce({ a: 1 }, () => ({ replaced: true })));

// Freezing, and the class opt-in.
const frozen = freeze({ deep: { x: 1 } }, true);
out.push([Object.isFrozen(frozen), Object.isFrozen(frozen.deep)]);
class Point {
  constructor(x) {
    this.x = x;
  }
}
Point.prototype[immerable] = true;
out.push([isDraftable(new Point(1)), produce(new Point(1), (d) => { d.x = 5; }).x]);

// Auto-freeze off, then back on, so the setting is observed rather than
// assumed.
setAutoFreeze(false);
out.push(Object.isFrozen(produce({ a: 1 }, (d) => { d.a = 2; })));
setAutoFreeze(true);
out.push(Object.isFrozen(produce({ a: 1 }, (d) => { d.a = 2; })));

console.log(JSON.stringify(out, null, 1));
