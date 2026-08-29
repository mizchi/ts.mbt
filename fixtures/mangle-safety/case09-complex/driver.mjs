export default async (mod) => ({
  instance: new mod.GenericClass("hello"),
  identity: mod.genericFunction(1),
  color: [mod.Color.Red, mod.Color.Green, mod.Color.Blue, mod.Color[0]],
  namespaceFoo: mod.MyNamespace.foo(),
  mapped: mod.mapped,
});
