// @strict: true
// @target: esnext

// `new Map<K, V>()` is the lib `Map` only when nothing in the module binds
// the name `Map` as a value: here it is `CustomMap`, and a field holding
// one has `CustomMap`'s members. A method PARAMETER named `Set` is not in
// scope at a field initializer, so a `new Set<T>()` field is the lib's.

class CustomMap<K, V> { hello(): string { return "hi"; } }
const Map = CustomMap;

class Holder {
  m = new Map<string, number>();
}

export function okUse(h: Holder): string { return h.m.hello(); }
export function badUse(h: Holder): number { return h.m.hello(); }

class SetHolder {
  s = new Set<string>();
  m(Set: number) { return Set; }
}
export function okSetHas(h: SetHolder): boolean { return h.s.has("x"); }
export function badSetHas(h: SetHolder): number { return h.s.has("x"); }
