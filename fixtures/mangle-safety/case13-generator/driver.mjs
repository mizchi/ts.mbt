// `run()` iterates an infinite generator, so drive the async one and
// take a single element instead.
export default async (mod) => {
  const it = mod.asyncObjectGenerator();
  const first = await it.next();
  return { first: first.value, done: first.done };
};
