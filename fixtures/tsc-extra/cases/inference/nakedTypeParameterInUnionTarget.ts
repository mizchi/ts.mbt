// @strict: true
// @target: esnext

// Inferring to a union that holds ONE naked type parameter: the argument's
// members that match another member are taken out, and the rest is a
// candidate for the naked one. So `S | (() => S)` (React's and preact's
// `useState`), `S | undefined` and `S | S[]` all infer `S` from a plain
// argument, and a fresh literal argument widens, since `S` is not at the
// top level of a tuple return.

declare function one<S>(x: S | (() => S)): S;
declare function opt<S>(x: S | undefined): S;
declare function many<S>(x: S | S[]): S;
declare function hook<S>(init: S | (() => S)): [S, (next: S) => void];

export function okOneFromValue() { const s: string = one(""); return s; }
export function badOneFromValue() { const n: number = one(""); return n; }
export function okOneFromThunk() { const s: string = one(() => ""); return s; }
export function badOneFromThunk() { const n: number = one(() => ""); return n; }
export function okOptFromValue() { const s: string = opt(""); return s; }
export function badOptFromValue() { const n: number = opt(""); return n; }
export function okManyFromElement() { const s: string = many(""); return s; }
export function okManyFromArray() { const s: string = many([""]); return s; }
export function badManyFromArray() { const n: number = many([""]); return n; }
export function okOneFromObject() { const o: { a: number } = one({ a: 1 }); return o; }
export function badOneFromObject() { const n: number = one({ a: 1 }); return n; }

export function okHookWidens() {
  const [mode, setMode] = hook("light");
  if (mode === "dark") { setMode("light"); }
  setMode("dark");
  return mode;
}
export function badHookState() {
  const [q] = hook("");
  return q.nope;
}
