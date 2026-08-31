// `Object.defineProperty` hands the runtime an object it reads BY NAME.
// Every key of a descriptor is somebody else's ABI, and since every
// `defineProperty` default is `false`, dropping a `true` flag INVERTS
// it — silently for `enumerable`, and into a throw for the other two,
// because a module body is strict-mode code.
const enumerableHolder: Record<string, any> = {};
Object.defineProperty(enumerableHolder, "visible", {
  value: 1,
  enumerable: true,
});

const writableHolder: Record<string, any> = {};
Object.defineProperty(writableHolder, "slot", { value: 1, writable: true });
writableHolder.slot = 2;

const configurableHolder: Record<string, any> = {};
Object.defineProperty(configurableHolder, "temp", {
  value: 1,
  configurable: true,
});
delete configurableHolder.temp;

// An accessor pair, whose `get` / `set` the runtime also reads by name.
const accessorHolder: Record<string, any> = {};
let backing = 0;
Object.defineProperty(accessorHolder, "via", {
  get(): number {
    return backing;
  },
  set(v: number) {
    backing = v;
  },
});
accessorHolder.via = 3;

// A `false` flag, which is the default anyway — dropping it is harmless,
// and it is what made two of the three original probes pass.
const defaultedHolder: Record<string, any> = {};
Object.defineProperty(defaultedHolder, "hidden", {
  value: 1,
  enumerable: false,
});

// The control: an ordinary object literal whose unread key must still go,
// so none of the above can be satisfied by switching the pass off.
const plain = { readMe: 1, deadmark_unread: 2 };

export const enumerableKeys = Object.keys(enumerableHolder);
export const writtenSlot = writableHolder.slot;
export const stillThere = "temp" in configurableHolder;
export const viaAccessor = accessorHolder.via;
export const defaultedKeys = Object.keys(defaultedHolder);
export const plainValue = plain.readMe;
