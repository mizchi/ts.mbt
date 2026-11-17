// @strict: true
// @target: esnext

// A non-null assertion removes `null`, `undefined` and `void`, and it
// applies to what an alias stands for. `Nullable<T> = T | null | undefined
// | void` is a common helper alias for lookups, so `get()!` must leave the
// `T` behind whether the call is a function or a method. Without the
// assertion the value is still possibly nullish.

type Nullable<T> = T | null | undefined | void;
interface V { a?: { x: number }; b: number }
declare class M<T> { getValue(r: number): Nullable<T>; }
declare const m: M<V>;
declare function get(): Nullable<V>;
declare const v: string | void;

function okVoidStripped() { const s: string = v!; }
function okFunctionResult() { const n: number = get()!.b; }
function okMethodResult() { const c = m.getValue(1)!; const n: number = c.b; }
function okGuardedOptionalMember() { const c = m.getValue(1)!; if (c.a) { const x: number = c.a.x; } }
function badNoAssertion() { const c = m.getValue(1); const n = c.b; }
function badOptionalMemberUnguarded() { const c = m.getValue(1)!; const x = c.a.x; }
