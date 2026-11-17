// @strict: true
// @target: esnext

// A method overload set declared on a generic base class is inherited
// whole: rxjs's `declare class Subject<T> extends Observable<T>` declares no
// `pipe`, and `subject.pipe(take(1))` picks `pipe<A>(op1)` from `Observable`,
// with `T` taken from `Subject<number>`. The return type follows the selected
// overload, on the base and through the subclass alike. A subclass that
// declares the method once hides the base's whole set, and so does an own
// property of that name. A method's own `<T>` shadows the class's `T`. An
// overload is selected by the first signature that fits, with an alias
// parameter resolved and a rest parameter taking any count. (`last` makes `Obs`
// covariant in `T`, as rxjs's `Observable` is through `operator`; without a
// member that uses `T` outside a method, tsc relates `Obs<string>` and
// `Obs<number>` structurally and accepts the return-type mismatches.)

interface Op<T, R> { (source: Obs<T>): Obs<R> }
declare class Obs<T> {
  readonly last: T;
  pipe(): Obs<T>;
  pipe<A>(op1: Op<T, A>): Obs<A>;
  pipe<A, B>(op1: Op<T, A>, op2: Op<A, B>): Obs<B>;
}
declare class Sub<T> extends Obs<T> { next(v: T): void }
declare class Narrow<T> extends Obs<T> { pipe(): Obs<T> }
declare class HiddenByProperty<T> extends Obs<T> { pipe: any }
declare class Box<T> { pick<T>(x: T): T; pick(x: boolean): boolean; }
declare class Shadow<T> { pick<T>(x: T): T; pick(x: string): number; }
type Flag = boolean;
declare class Flagged<T> { m(x: T): string; m(x: boolean): number; }
declare class FlaggedSub extends Flagged<Flag> {}
declare class Rested<T> { m(...xs: T[]): string; m(x: number): number; }
declare class RestedSub extends Rested<number> {}
declare function take<T>(n: number): Op<T, T>;
declare function toStr(): Op<number, string>;

export function okInheritedOne(s: Sub<number>) { return s.pipe(take(1)); }
export function okInheritedTwo(s: Sub<number>) { return s.pipe(take(1), take(2)); }
export class OkFieldReceiver { private readonly a = new Sub<number>(); m() { return this.a.pipe(take(1)); } }
export function okInheritedReturnType(s: Sub<number>): Obs<string> { return s.pipe(toStr()); }
export function okPropertyHidesTheSet(s: HiddenByProperty<number>) { const x: string = s.pipe(take(1)); return x; }
export function okMethodBinderShadowsClass(b: Box<string>) { const n: number = b.pick(1); return n; }
export function okShadowSelectsGeneric(b: Shadow<number>) { const s: string = b.pick("a"); return s; }
export function okAliasArgumentSelectsFirst(d: FlaggedSub) { const s: string = d.m(true); return s; }
export function okAliasArgumentDirect(b: Flagged<Flag>) { const s: string = b.m(true); return s; }
export function okRestOverloadSelectsFirst(d: RestedSub) { const s: string = d.m(1); return s; }
export function okRestOverloadDirect(b: Rested<number>) { const s: string = b.m(1); return s; }
export function okDirectReturnType(s: Obs<number>): Obs<string> { return s.pipe(toStr()); }

export function badOverrideHidesTheSet(s: Narrow<number>) { return s.pipe(take(1)); }
export function badInheritedReturnType(s: Sub<number>): Obs<number> { return s.pipe(toStr()); }
export function badDirectReturnType(s: Obs<number>): Obs<number> { return s.pipe(toStr()); }
export function badTooManyOperators(s: Sub<number>) { return s.pipe(take(1), take(2), take(3)); }
export function badMethodBinderShadowsClass(b: Box<string>) { const s: string = b.pick(1); return s; }
export function badShadowSelectsGeneric(b: Shadow<number>) { const n: number = b.pick("a"); return n; }
export function badAliasArgumentSelectsFirst(d: FlaggedSub) { const n: number = d.m(true); return n; }
export function badRestOverloadSelectsFirst(d: RestedSub) { const n: number = d.m(1); return n; }
