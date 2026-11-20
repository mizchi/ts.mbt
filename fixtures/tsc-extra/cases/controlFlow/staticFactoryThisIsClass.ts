// @strict: true
// @target: esnext

// In a static method `this` is the class, so a singleton factory's
// `return this._instance` has the static field's declared type. A value
// assigned from it after `if (cell == null)` is never nullish. A static
// field that admits `undefined` leaves the binding nullable.

type Nullable<T> = T | null | undefined | void;
class Base { k = 1 }
class NullV extends Base {
  private static _instance: NullV;
  private static _maybe: NullV | undefined;
  static create() { this._instance = this._instance || new NullV(); return this._instance; }
  static maybe() { const m = this._maybe; return m; }
}

export function okSingleton(def: Nullable<Base>) {
  const out: Base[] = [];
  let cell = def;
  if (cell == null) { cell = NullV.create(); }
  out[0] = cell;
}
export function badMaybe(def: Nullable<Base>) {
  const out: Base[] = [];
  let cell = def;
  if (cell == null) { cell = NullV.maybe(); }
  out[0] = cell;
}
