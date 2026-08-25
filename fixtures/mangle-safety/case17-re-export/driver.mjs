export default async (mod) => ({
  sub: mod.subFunction({ id: 1, subValue: "s" }),
  nested: mod.nestedFunction({ id: 2, nestedValue: "n" }),
  pub: mod.publicFunction({ id: 3, pubValue: "p" }),
  all: mod.allExportedFunction({ id: 4, pubValue: "p" }, { name: "n", age: 5 }),
});
