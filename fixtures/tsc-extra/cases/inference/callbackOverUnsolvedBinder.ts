// @strict: true
// @target: esnext

// A callback's parameter type comes from the written type argument, or from
// the type the call is assigned to, when no other argument fixes the type
// parameter: `Sub<void>`'s `next(value: void)` takes no argument. With neither,
// the parameter is inferred `unknown`, and `next()` needs one.

declare class Sub<T> { next(value: T): void; }
declare class Obs<T> { constructor(subscribe?: (s: Sub<T>) => void); }
declare function take<T>(cb: (s: Sub<T>) => void): T;
declare function takeWith<T>(x: T, cb: (s: Sub<T>) => void): T;
declare const av: any;

export function okExplicitVoid() { return new Obs<void>((s) => { s.next(); }); }
export function badExplicitNumber() { return new Obs<number>((s) => { s.next(); }); }
export function okContextual() { const c: Obs<void> = new Obs((s) => { s.next(); }); return c; }
export function badContextualNumber() { const c: Obs<number> = new Obs((s) => { s.next(); }); return c; }
export function badNoContext() { return new Obs((s) => { s.next(); }); }
export function okCallExplicitVoid() { return take<void>((s) => { s.next(); }); }
export function badCallExplicitNumber() { return take<number>((s) => { s.next(); }); }
export function badSolvedFromArgument() { return takeWith(1, (s) => { s.next(); }); }
export function badRealAny() { return takeWith(av, (s) => { s.next(); }); }

// Only the formal's parameters lose the binder: the callback's arity is
// still judged against the call signatures, which supply one argument.
declare function over<T>(cb: { (x: T): string; (x: T, y?: T): string }): T;
export function badOverloadArity() { return over((x, y) => ""); }
export function okOverloadArity() { return over((x) => ""); }
declare function single<T>(cb: (x: T) => string): T;
export function badSingleArity() { return single((x, y) => ""); }
declare function takeOpt<T>(cb: (s: Sub<T>, extra?: number) => void): T;
export function okMetaVoid() { return takeOpt<void>((s) => { s.next(); }); }
export function badMetaNumber() { return takeOpt<number>((s) => { s.next(); }); }
