export default async (mod) => ({
  a: mod.foo({ type: "A", payload: { a: "av" } }),
  b: mod.foo({ type: "B", payload: { b: "bv" } }),
  c: mod.createPayloadOfC(),
});
