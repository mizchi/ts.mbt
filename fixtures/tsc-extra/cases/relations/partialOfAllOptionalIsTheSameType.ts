// @strict: true
// @target: esnext

// `Partial<T>` is assignable to `T` when every member of `T` is already
// optional, through inheritance too, and to `Readonly<T>`. A `T` with a
// required member is not, including one whose required member admits
// `undefined`, and neither is a type parameter. In an intersection a member
// is required when any constituent requires it, in either order.

interface O { a?: string; b?: boolean }
interface R { a: string; b?: boolean }
interface U { a: string | undefined }
interface E extends O { c?: number }
declare const po: Partial<O>;
declare const pr: Partial<R>;
declare const pu: Partial<U>;
declare const pe: Partial<E>;
declare function g(o: O): O;
export const okAllOptional: O = po;
export const okReadonly: Readonly<O> = po;
export const okInherited: E = pe;
export function okArgument(p: { payload: Partial<O> }) { return g(p.payload); }
export const badRequired: R = pr;
export const badRequiredUndefined: U = pu;
export function badGeneric<T>(p: Partial<T>) { const t: T = p; return t; }
type LateRequired = { a?: number } & { a: number };
type EarlyRequired = { a: number } & { a?: number };
declare const pl: Partial<LateRequired>;
declare const pe2: Partial<EarlyRequired>;
export const badIntersectionLate: LateRequired = pl;
export const badIntersectionEarly: EarlyRequired = pe2;
