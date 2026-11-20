// @strict: true
// @target: esnext

// The falsy part of `x && y` for a `number`, `string` or `bigint` operand is
// `0`, `""` or `0n`, not the whole primitive, and a truthy test removes
// those literals. So a fallback chain guarded by `if (!s) return` leaves
// only the array. Without the truthy test the literals stay, and they are
// not iterable. A mutable binding widens the fresh `"a"`, which absorbs the
// non-fresh `""`.

interface T { stack?: T[]; value?: number | string | T }

export function okNarrow(t: T) {
  const s = t.stack || (t.value && (t.value as T).stack);
  if (!s) return;
  for (const x of s) { x.stack; }
}
export function okLet(s: string) { let r = s && "a"; r = "b"; return r; }
export function okLetNumber(n: number) { let r = n && 5; r = 7; return r; }
export function badNoGuard(t: T) {
  const s = t.value && (t.value as T).stack;
  if (s === undefined) return;
  for (const x of s) { x.stack; }
}
export function badStringLiteral(s: string) { const q: "a" = s && "a"; return q; }
export function badNumberLiteral(n: number) { const q: 5 = n && 5; return q; }
