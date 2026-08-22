export default async (mod) => {
  const obj = mod.createObj();
  mod.runLocal();
  return {
    xxx: obj.xxx(),
    yyy: obj.yyy({ v1: "one" }),
    zzz: obj.zzz(),
    indirect: mod.indirect,
    items: mod.items,
  };
};
