// @strict: true
// @target: esnext

// A method that implements an interface method is compared bivariantly, and
// an alias by what it expands to. A required `unit: Unit` implements
// `unit?: Unit`, a defaulted parameter implements an optional one, and a
// method taking a callback with fewer parameters implements one taking a
// wider callback. A class whose methods are compatible this way is assignable
// to the interface. An incompatible parameter or return is still an error.

type Unit = "day" | "millisecond";
interface IK { add(value: number, unit?: Unit): IK; }
export class OkDefault implements IK {
  add(value: number, unit: Unit = "millisecond") { return this; }
}
export class OkRequired implements IK {
  add(value: number, unit: Unit): IK { return this; }
}
interface IKString { add(value: number, unit?: string): IKString; }
export class OkRequiredString implements IKString {
  add(value: number, unit: string): IKString { return this; }
}

interface Info { id: string }
interface Opts { quiet?: boolean }
type Listener = (info: Readonly<Info>, options?: Opts) => void;
interface ISvc { on(listener: Listener): void; }
export class OkFewerCallbackParams implements ISvc {
  on(listener: (info: Info) => void): void {}
}

export function okAssignToInterface(a: OkRequired): IK { return a; }

export class BadParam implements IK {
  add(value: number, unit: boolean): IK { return this as any; }
}
interface IN { add(value: number): number; }
export class BadReturn implements IN {
  add(value: number): string { return ""; }
}
class Wrong { add(value: string): IK { return null as any; } }
export function badAssignToInterface(w: Wrong): IK { return w; }

// A callable against a scalar is incompatible in either direction.
interface IScalar { m(cb: number): void; }
export class BadCallableVsScalar implements IScalar { m(cb: () => void): void {} }
interface ICallable { m(cb: () => void): void; }
export class BadScalarVsCallable implements ICallable { m(cb: number): void {} }
