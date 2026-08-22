export default async (mod) => ({
  myfn: mod.myfn({ input: 2 }),
  componentLike2: mod.componentLike2(),
});
