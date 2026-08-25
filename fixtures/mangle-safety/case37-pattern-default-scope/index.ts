// A binding PATTERN hides value expressions in two places, and both
// were skipped by walkers that only looked at the initializer.
//
//   const [first = fallback] = xs      // an element default
//   const { [key]: picked } = table    // a computed key
//
// The default's `fallback` is a free reference of `pick`'s body, so its
// short name has to be reserved before the parameter allocator runs.
// It was not, so the parameter took the same letter and the default
// resolved to the parameter — `chosen` came back as the empty array
// instead of 9.
//
// The computed key is an ordinary value expression too. Carrying it
// through the rename verbatim left `{ [key]: picked }` in a function
// whose `key` had been renamed: ReferenceError.
const fallback = 9;

function pick(xs: number[]): number {
  const [first = fallback] = xs;
  return first;
}

function lookup(key: string): number | undefined {
  const table: Record<string, number> = { alphaTop: 1 };
  const { [key]: picked } = table;
  return picked;
}

export const report = {
  chosen: pick([]),
  found: lookup("alphaTop"),
};
console.log(report);
