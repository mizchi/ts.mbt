// Array built-ins with their OPTIONAL and REST parameters.
//
// The checker's `array_prototype_member` table declared every optional
// parameter as required and every rest parameter as a single slot, so it
// rejected ordinary JavaScript under the DEFAULT (checking) path:
//
//   arr.sort()            expected 1 argument(s), got 0
//   arr.slice()           expected 2 argument(s), got 0
//   arr.join()            expected 1 argument(s), got 0
//   arr.push(a, b)        expected 1 argument(s), got 2
//   arr.flat(2)           expected 0 argument(s), got 1
//
// `.sort()` with no comparator is about as ordinary as it gets. It
// survived because every fixture that would have hit it was written
// around it — the same reason the two holes this case and `case58` close
// were found by writing a NEW fixture rather than by any harness.
//
// The mechanism to express this already existed and the table simply did
// not use it: `required_arity_from_types` treats a parameter whose type
// accepts `undefined` as omittable (the parser widens `x?: T` to
// `T | undefined`), and never raises the required count for a `Rest`.
// So the fix is the table saying what it means.
//
// Every form below is compiled by mtsc AND run by Node against the same
// source, so a wrong signature that happens to type-check still has to
// produce the right answer.

const xs: number[] = [3, 1, 2];
const nested: number[][] = [[1], [2, 3]];
const deep: number[][][] = [[[1]], [[2]]];

function copy(): number[] {
  return [...xs];
}

export const report = {
  // sort: optional comparator
  sortDefault: copy().sort().join(","),
  sortCmp: copy().sort((a, b) => b - a).join(","),

  // slice: both bounds optional
  sliceNone: xs.slice().join(","),
  sliceFrom: xs.slice(1).join(","),
  sliceRange: xs.slice(1, 2).join(","),
  sliceNegative: xs.slice(-2).join(","),

  // join: optional separator
  joinDefault: xs.join(),
  joinSep: xs.join("|"),

  // flat: optional depth
  flatDefault: nested.flat().join(","),
  flatDepth: deep.flat(2).join(","),

  // indexOf / lastIndexOf / includes: optional fromIndex
  indexOfPlain: xs.indexOf(1),
  indexOfFrom: xs.indexOf(1, 2),
  lastIndexOfPlain: xs.lastIndexOf(2),
  lastIndexOfFrom: xs.lastIndexOf(2, 1),
  includesPlain: xs.includes(2),
  includesFrom: xs.includes(2, 2),

  // fill: value required, bounds optional
  fillAll: [0, 0, 0].fill(7).join(","),
  fillFrom: [0, 0, 0].fill(7, 1).join(","),
  fillRange: [0, 0, 0].fill(7, 1, 2).join(","),

  // splice: start required, deleteCount optional, items variadic
  spliceOne: (() => {
    const c = copy();
    c.splice(1);
    return c.join(",");
  })(),
  spliceCount: (() => {
    const c = copy();
    c.splice(1, 1);
    return c.join(",");
  })(),
  spliceInsert: (() => {
    const c = copy();
    c.splice(1, 1, 8, 9);
    return c.join(",");
  })(),

  // push / unshift / concat: variadic, including zero arguments
  pushNone: (() => {
    const c: number[] = [];
    return String(c.push());
  })(),
  pushMany: (() => {
    const c: number[] = [];
    c.push(1, 2, 3);
    return c.join(",");
  })(),
  unshiftMany: (() => {
    const c = [3];
    c.unshift(1, 2);
    return c.join(",");
  })(),
  // `concat` takes `(T | T[])[]`, and BOTH halves of that union are
  // load-bearing. The first draft of this case had only the bare-element
  // forms below, and passed while the fix under test rejected
  // `[1].concat([2, 3])` — the form nearly all real code uses. Writing
  // the signature as a rest of `T` alone is as wrong as the original's
  // single `T[]` slot, in the opposite direction; a case with only one
  // side of the union cannot tell those two apart.
  concatNone: [1].concat().join(","),
  concatMany: [1].concat(2, 3).join(","),
  concatArray: [1].concat([2, 3]).join(","),
  concatArrays: [1].concat([2], [3, 4]).join(","),
  concatMixed: [1].concat([2], 3).join(","),

  // The forms that were already right, so the fix cannot have loosened
  // them into accepting nonsense: these must still be the same answers.
  pop: (() => {
    const c = copy();
    return String(c.pop()) + "/" + c.join(",");
  })(),
  shift: (() => {
    const c = copy();
    return String(c.shift()) + "/" + c.join(",");
  })(),
  reverse: copy().reverse().join(","),
  length: xs.length,
};
