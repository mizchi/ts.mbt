// Exhaustive matching over a discriminated union — the shape
// `tag-rewrite` and `switch-fold` are built for, which is why this
// target is worth having.
//
// `P` is deliberately not imported. ts-pattern's entry says
// `export { Pattern, Pattern as P }` — a re-export that ALIASES a name
// bound by `import * as Pattern from './patterns'` — and the linker
// drops both spellings, so the bundle offers only `match`, `isMatching`
// and `NonExhaustiveError`. That is its own bug, recorded in
// `docs/type-aware-measurement.md`; this driver stays within what the
// bundle actually exports so the row can still be behaviour-checked.
import { match, isMatching, NonExhaustiveError } from "./target.mjs";
const events = [
  { type: "click", x: 1, y: 2 },
  { type: "key", key: "a", shift: true },
  { type: "scroll", delta: -3 },
  { type: "resize", w: 10, h: 20 },
];
const out = events.map((e) =>
  match(e)
    .with({ type: "click", x: 1 }, (c) => `click(${c.x},${c.y})`)
    .with({ type: "key", shift: true }, (k) => `KEY:${k.key}`)
    .with({ type: "key" }, (k) => `key:${k.key}`)
    .with({ type: "scroll", delta: -3 }, (s) => `up${s.delta}`)
    .otherwise((o) => `other:${o.type}`),
);
out.push(match({ n: 5 }).with({ n: 1 }, () => "one").otherwise(({ n }) => "n=" + n));
out.push(match([1, 2, 3]).with([1, 2, 3], () => "exact").otherwise(() => "no"));
out.push(isMatching({ type: "x" }, { type: "x" }), isMatching({ type: "x" }, { type: "y" }));
out.push(match({ a: { b: { c: 7 } } }).with({ a: { b: { c: 7 } } }, () => "deep").otherwise(() => "no"));
out.push(
  (() => {
    try { return match({ k: "z" }).with({ k: "a" }, () => "a").exhaustive(); }
    catch (e) { return "threw:" + (e instanceof NonExhaustiveError); }
  })(),
);
console.log(JSON.stringify(out, null, 1));
