// The other side of the inversion: with "unknown call escapes" as the
// default, an allowlist is what keeps ordinary built-in calls from
// poisoning every value that flows through them. `acc` is passed to
// `Math.max` and its fields are stored in a `Map`, and neither of those
// can observe a property name — so `runningSum` / `largest` stay
// private and get renamed.
export function summarize(values: number[]): number {
  const acc = { runningSum: 0, largest: 0 };
  for (const v of values) {
    acc.runningSum = acc.runningSum + v;
    acc.largest = Math.max(acc.largest, v);
  }
  const seen = new Map<string, number>();
  seen.set("sum", acc.runningSum);
  seen.set("top", acc.largest);
  const sum = seen.get("sum");
  const top = seen.get("top");
  return (sum === undefined ? 0 : sum) + (top === undefined ? 0 : top);
}
