// @strict: true

// A local callback's return type comes from its body, and a `let` it
// assigns again (get-or-create) is not read by its initializer: here the
// `undefined` from `get` is gone by the `return`.

declare function sync<A>(f: () => A): A;
declare function later<A>(f: (n: number) => A): A;

export const okGetOrCreate = sync(() => {
  const stores = new Map<string, Map<string, number>>();
  const getStore = (id: string) => {
    let store = stores.get(id);
    if (store === undefined) {
      store = new Map<string, number>();
      stores.set(id, store);
    }
    return store;
  };
  return {
    make: (id: string) =>
      later((n) => {
        const map = getStore(id);
        return { clear: () => map.clear(), n };
      })
  };
});
