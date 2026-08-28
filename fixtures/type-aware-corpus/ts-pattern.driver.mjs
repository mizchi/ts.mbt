// Exhaustive matching over a discriminated union — the shape
// `tag-rewrite` and `switch-fold` are built for, which is why this
// target is worth having.
//
// `P` used to be absent from this driver, because it was absent from the
// bundle. ts-pattern's entry says
//
//     import * as Pattern from './patterns';
//     export { Pattern, Pattern as P };
//
// and BOTH spellings were dropped: the namespace object is only
// synthesized when the namespace escapes, the escape test looks for a
// reference in the module BLOCK, and an export specifier is metadata
// rather than a block reference. So the entire `P` surface — which is
// most of what people import from ts-pattern — was missing while the
// row still reported NEUTRAL, because nothing exercised it.
//
// That is the argument for exercising a package's whole public surface
// rather than the part that happens to work: a driver written around a
// bug ratifies it.
import { match, isMatching, NonExhaustiveError, P, Pattern } from "./target.mjs";
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
// The `P` surface, and that the two spellings are the same object.
out.push(["P === Pattern", P === Pattern]);
out.push(match(3).with(P.union(1, 2, 3), () => "in").otherwise(() => "out"));
out.push(match("s").with(P.string, (v) => "str:" + v).otherwise(() => "no"));
out.push(match(1).with(P.number, (v) => "num:" + v).otherwise(() => "no"));
out.push(match(null).with(P.nullish, () => "nullish").otherwise(() => "no"));
out.push(
  match({ v: [1, 2] })
    .with({ v: P.array(P.number).select() }, (xs) => xs.length)
    .otherwise(() => -1),
);
out.push(
  match({ a: { b: "deep" } })
    .with({ a: { b: P.select() } }, (b) => b)
    .otherwise(() => "no"),
);
out.push(isMatching({ a: P.string }, { a: "x" }));
out.push(isMatching({ a: P.string }, { a: 1 }));
out.push(match(new Date(0)).with(P.instanceOf(Date), (d) => d.getTime()).otherwise(() => -1));
out.push(
  match({ n: 5 })
    .with({ n: P.when((x) => x > 3) }, () => "big")
    .otherwise(() => "small"),
);
out.push(match([1, 2, 3]).with([1, P._, 3], () => "triple").otherwise(() => "no"));
out.push(match({ o: undefined }).with({ o: P.optional(P.string) }, () => "opt").otherwise(() => "no"));
out.push(Object.keys(P).sort());

console.log(JSON.stringify(out, null, 1));
