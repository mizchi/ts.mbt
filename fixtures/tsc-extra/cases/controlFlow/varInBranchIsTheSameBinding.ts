// @strict: true
// @target: esnext

// A `var` declared in a branch is the enclosing function's binding, not a
// new one, so writing it there drops the narrowing of a property read off
// it at the join, as any write does. A `let` in the branch is the branch's
// own binding, and the outer narrowing survives.

interface O { p: string | undefined }

export function okLetShadow(c: boolean, o: O, other: O) {
  o.p = "";
  if (c) { let o = other; o = other; }
  const s: string = o.p;
  return s;
}
export function badVarRedeclare(c: boolean, o: O, other: O) {
  o.p = "";
  if (c) { var o: O; o = other; }
  const s: string = o.p;
  return s;
}
