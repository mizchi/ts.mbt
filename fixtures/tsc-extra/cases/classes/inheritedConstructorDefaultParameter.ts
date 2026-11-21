// @strict: true
// @target: esnext

// An inherited constructor's defaulted parameter is optional, as the class's
// own one is, so a subclass with no constructor of its own takes zero or one
// argument; two are too many.

enum DS { A = 0, B = 1 }
export class Base { private _d: DS; constructor(d: DS = DS.A) { this._d = d; } }
export class Sub extends Base {}
export function okBaseNoArgs() { return new Base(); }
export function okSubNoArgs() { return new Sub(); }
export function okSubOneArg() { return new Sub(DS.B); }
export function badSubTwoArgs() { return new Sub(DS.A, 2); }
