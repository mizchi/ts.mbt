// The consumer supplies the callback, so the payload's method is named
// only out here. A getter returning the field would widen to `this` and
// mask the hole under test — see the header of index.ts.
export default async (mod) => ({
  priv: mod.priv.use((p) => p.readPrivate("k")),
});
