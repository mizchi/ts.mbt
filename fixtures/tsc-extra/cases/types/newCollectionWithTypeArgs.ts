// @strict: true
// @target: esnext

// `new Map<K, V>()`, `new Set<T>()` and their weak variants are instances
// of the written arguments, at top level and as an unannotated class
// field's initializer; `get` adds `undefined`. A field holding a `Set`
// or a `WeakMap` is the same instance as a `Map` field.

interface St { ok: boolean }

const q1 = new Map<string, number>();
export const okMapGet: number | undefined = q1.get("k");
export const badMapGet: string = q1.get("k");

const q2 = new Set<string>();
export const okSetHas: boolean = q2.has("a");
export const badSetHas: string = q2.has("a");

const w = new WeakMap<object, number>();
export const okWeakGet: number | undefined = w.get({});
export const badWeakGet: string | undefined = w.get({});

export class Holder {
  private _m = new Map<string, St | null>();
  private _s = new Set<string>();
  okField(k: string): St | null | undefined { return this._m.get(k); }
  badField(k: string): number { return this._m.get(k); }
  okSetField(k: string): boolean { return this._s.has(k); }
  badSetField(k: string): string { return this._s.has(k); }
}
export class Guarded {
  private _states = new Map<string, St | null>();
  okEqualityAfterLookup(key: string, cur: St | undefined) {
    const previous = this._states.get(key);
    if (!(previous?.ok && cur === previous)) return false;
    return cur.ok;
  }
}
