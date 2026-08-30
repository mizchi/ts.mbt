// remeda, used the way its README's first example uses it, in both of
// the calling conventions `purry` dispatches on.
//
// Every export is a scalar.

import {
  filter,
  forEach,
  map,
  pipe,
  sortBy,
  sumBy,
  take,
  unique,
} from "./packages/remeda/src/index.ts";

const seen: number[] = [];

const lazy: number[] = pipe(
  [1, 2, 2, 3, 3, 4, 5, 6],
  forEach((value: number) => {
    seen.push(value);
  }),
  unique(),
  take(3),
);

// The data-first form of the same functions, which `purry` dispatches by
// `arguments.length` rather than by type.
const dataFirst: number[] = map(filter([1, 2, 3, 4, 5], (n) => n % 2 === 1), (
  n,
) => n * 10);

type Row = { id: number; name: string; score: number };
const rows: Row[] = [
  { id: 3, name: "c", score: 7 },
  { id: 1, name: "a", score: 12 },
  { id: 2, name: "b", score: 5 },
];

export const lazyResult: string = lazy.join(",");
export const upstreamCalls: string = seen.join(",");
export const dataFirstResult: string = dataFirst.join(",");
export const sorted: string = sortBy(rows, (r) => r.id).map((r) => r.name).join(
  "",
);
export const total: number = sumBy(rows, (r) => r.score);
