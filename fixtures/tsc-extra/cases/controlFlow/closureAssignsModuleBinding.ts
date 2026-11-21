// @strict: true
// @target: esnext

// An assignment inside a closure to a module-level binding is judged against
// the binding's declared type, not against what the enclosing body had
// narrowed it to: the closure may run after any later assignment. A value
// the declared type does not admit is still an error there.

type Nullable<T> = T | null | undefined | void;

let dpiCache: Nullable<number>;
export function okNullAfterNarrowing(): number {
  if (dpiCache) { return dpiCache; }
  const i = 56;
  dpiCache = i;
  setTimeout(() => { dpiCache = null; }, 10);
  return i;
}

let plain: number | null = null;
export function okPlainNull(): number {
  plain = 1;
  setTimeout(() => { plain = null; }, 10);
  return 1;
}
export function badClosureString(): number {
  plain = 1;
  setTimeout(() => { plain = "x"; }, 10);
  return 1;
}
export function okLocalBinding(): number {
  let loc: Nullable<number>;
  loc = 1;
  setTimeout(() => { loc = null; }, 10);
  return 1;
}

// An unannotated module `let` has its initializer's widened type.
let inferred = 0;
export function badInferredFromFunction(): void { inferred = "y"; }
