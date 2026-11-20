// @strict: true
// @target: esnext

// An object literal whose discriminant is a union of literals is related to
// a discriminated union one combination at a time, and each combination is
// related STRUCTURALLY: the excess-property check runs once, on the whole
// literal, and with a discriminant that picks no single member it only asks
// whether some member declares the property. So zod's `return { status:
// status.value, value }` fits `OK<any> | DIRTY<any> | INVALID` although
// `INVALID` has no `value`. A property no member declares is still excess,
// and so is one the member a single-literal discriminant picks lacks.

type INVALID = { status: "aborted" };
type DIRTY<T> = { status: "dirty"; value: T };
type OK<T> = { status: "valid"; value: T };
type SRT<T = any> = OK<T> | DIRTY<T> | INVALID;
declare const st: { value: "aborted" | "dirty" | "valid" };

export function okBareAlias(): SRT { const arr: any[] = []; return { status: st.value, value: arr }; }
export function okExplicitArgument(): SRT<any> { const arr: any[] = []; return { status: st.value, value: arr }; }
export function badValueMismatch(): SRT<string> { return { status: st.value, value: 1 }; }
export function badNoMemberHasIt(): SRT<any> { return { status: st.value, value: 1, extra: 1 }; }
export function badMissingValue(): OK<any> | DIRTY<any> { return { status: st.value as "dirty" | "valid" }; }
export function badSingleDiscriminantExcess(): SRT<any> { return { status: "aborted", value: 1 }; }
