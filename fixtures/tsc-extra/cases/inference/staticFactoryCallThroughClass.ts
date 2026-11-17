// @strict: true
// @target: esnext

// A static method called through its class returns what it declares.
// univer writes `if (v == null || v.isNull()) { v = NumberValueObject.create(0); }`,
// and after that `if` the value is non-nullish on both paths, including when
// `v`'s declared type is an alias such as `Nullable<T>`. A mismatch through
// the factory is a real error, and an assignment of a value typed `any`
// keeps the declared type, so it still needs a guard. An auto-typed `let b =
// null` assigned a value of a type the checker cannot name (a factory, or
// `new` on an `any` constructor) is non-nullish afterwards, not empty.

type Nullable<T> = T | null | undefined | void;
class BaseValue { isNull(): boolean { return false; } isBool(): boolean { return false; } }
class NumberValue extends BaseValue { static create(n: number): NumberValue { return new NumberValue(); } }
declare const anything: any;
declare const AnyCtor: any;

export function okFactoryNarrowsAfterIf(v: Nullable<BaseValue>) { let w = v; if (w == null || w.isNull()) { w = NumberValue.create(0); } return w.isBool(); }
export function okFactoryInCallback(xs: Nullable<BaseValue>[]) { xs.forEach((v) => { let w = v; if (w == null) { w = NumberValue.create(1); } w.isBool(); }); }
export function okAutoTypedThenFactory() { let b = null; b = NumberValue.create(4); return b.isBool(); }
export function okAutoTypedThenAnyNew() { let b = null; b = new AnyCtor(); return b.width; }
export function okFactoryInitializer() { const n: BaseValue = NumberValue.create(2); return n; }

export function badFactoryMismatch() { const s: string = NumberValue.create(3); return s; }
export function badAnyAssignmentKeepsDeclared(v: BaseValue | undefined) { v = anything; return v.isBool(); }
export function badReadBeforeFactory() { let b = null; const z = b.isBool(); b = NumberValue.create(5); return z; }
