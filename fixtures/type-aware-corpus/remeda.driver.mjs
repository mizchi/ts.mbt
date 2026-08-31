// remeda: the data-first / data-last dual calling convention, and the
// lazy pipeline that makes it interesting to a minifier.
//
// This target was BLOCKED — not on a pass, on the parser. `setPath.ts`
// writes a conditional type whose check type is a union laid out one
// member per line:
//
//     type Paths<T, Prefix …> =
//       | Prefix
//       | (T extends object ? … : …) extends infer Path
//       ? Readonly<Path>
//       : never;
//
// The leading `|` took its own branch in `parse_type` that built the
// union and returned, skipping the `extends` tail. One file failing to
// parse blocked the whole package, so `setPath` gets exercised below on
// principle even though it is a small part of the API.
//
// What makes remeda worth measuring: nearly every function has two
// call forms — `map(data, fn)` and `map(fn)` for use inside `pipe` —
// dispatched at runtime by `purry` on `arguments.length`. That is an
// arity-sensitive indirection through a shared helper, which is exactly
// the shape an unused-parameter pass or a single-use inliner can get
// wrong without anything looking wrong. And `pipe` with lazy operators
// short-circuits: `take(2)` must stop the upstream `map`, so a fold that
// changed evaluation order would show up as extra calls, not as a wrong
// answer.
import * as R from "./target.mjs";

const out = [];

// Both calling conventions, same result.
out.push(R.map([1, 2, 3], (x) => x * 2));
out.push(R.pipe([1, 2, 3], R.map((x) => x * 2)));
out.push(R.filter([1, 2, 3, 4], (x) => x % 2 === 0));
out.push(R.pipe([1, 2, 3, 4], R.filter((x) => x % 2 === 0)));

// Laziness: `take` has to stop the upstream `map`, so count the calls.
let mapped = 0;
out.push(
  R.pipe(
    [1, 2, 3, 4, 5, 6],
    R.map((x) => {
      mapped += 1;
      return x + 1;
    }),
    R.take(2),
  ),
);
out.push(["upstream calls", mapped]);

// The path API, which is why the file that blocked this target exists.
out.push(R.setPath({ a: { b: [1, 2] } }, ["a", "b", 1], 9));
out.push(R.pathOr({ a: { b: 1 } }, ["a", "b"], 0));
out.push(R.pathOr({ a: {} }, ["a", "b"], "fallback"));

// Grouping / keying, which build objects from callbacks.
out.push(R.groupBy([{ a: 1, n: 1 }, { a: 2, n: 2 }, { a: 1, n: 3 }], (x) => x.a));
out.push(R.indexBy([{ id: "x" }, { id: "y" }], (x) => x.id));
out.push(R.countBy([1, 2, 2, 3, 3, 3], (x) => x));
out.push(R.mapValues({ a: 1, b: 2 }, (v) => v * 2));
out.push(R.mapKeys({ a: 1, b: 2 }, (k) => k.toUpperCase()));

// Ordering and dedup, including the comparator forms.
out.push(R.sortBy([3, 1, 2], (x) => x));
out.push(R.sortBy([{ n: 3 }, { n: 1 }], [(x) => x.n, "desc"]));
out.push(R.uniqueBy([1, 2, 2, 3], (x) => x));
out.push(R.reverse([1, 2, 3]));

// Shape operations over arrays and objects.
out.push(R.chunk([1, 2, 3, 4, 5], 2));
out.push(R.zip([1, 2], ["a", "b"]));
out.push(R.flat([[1, [2]], [3]]));
out.push(R.partition([1, 2, 3, 4], (x) => x % 2 === 0));
out.push(R.pick({ a: 1, b: 2, c: 3 }, ["a", "c"]));
out.push(R.omit({ a: 1, b: 2, c: 3 }, ["b"]));
out.push(R.merge({ a: 1, b: 2 }, { b: 3, c: 4 }));

// Deep equality and cloning, which walk every value shape.
out.push(R.isDeepEqual({ a: [1, { b: 2 }] }, { a: [1, { b: 2 }] }));
out.push(R.isDeepEqual({ a: [1, { b: 2 }] }, { a: [1, { b: 3 }] }));
out.push(R.clone({ a: { b: [1, 2] }, d: new Date(0).toISOString() }));

// The guards, which are plain predicates and the thing `predicate-inline`
// is built to fold.
out.push([
  R.isString("s"),
  R.isNumber(1),
  R.isArray([]),
  R.isObjectType({}),
  R.isNullish(null),
  R.isNullish(undefined),
  R.isNonNullish(0),
  R.isEmpty(""),
  R.isEmpty([]),
]);

// A longer pipe, so the composition is not just one operator deep.
out.push(
  R.pipe(
    [5, 3, 8, 1, 9, 2],
    R.filter((x) => x > 2),
    R.map((x) => x * 3),
    R.sortBy((x) => x),
    R.take(3),
  ),
);

console.log(JSON.stringify(out, null, 1));
