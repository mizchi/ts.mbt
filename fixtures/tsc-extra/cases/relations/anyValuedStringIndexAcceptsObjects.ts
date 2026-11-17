// @strict: true
// @target: esnext

// An interface value has no implicit index signature, but a target whose
// only index signature takes a `string` key with an `any` value accepts it
// anyway, because such a signature asks nothing of the source's properties.
// The key may be a union holding `string` (`number | string`) and the value
// a union holding `any`. An `unknown` value is not enough, and neither is a
// `number` key alone, and a primitive source is still an error.

interface S { a?: string; b?: number }
interface Req { a: string }
interface AnyIdx { [k: string]: any }
interface UnionKeyAny { [k: number | string]: any }
interface UnionValueAny { [k: string]: UnionValueAny | UnionValueAny[] | any }
interface UnknownIdx { [k: string]: unknown }
interface NumberKeyAny { [k: number]: any }
interface StringIdx { [k: string]: string }
declare const s: S;
declare const req: Req;
declare function take(o: UnionValueAny): void;

export const okInterfaceToAnyIndex: AnyIdx = s;
export const okRequiredMemberToAnyIndex: AnyIdx = req;
export const okInterfaceToUnionKey: UnionKeyAny = s;
export const okInterfaceToUnionValue: UnionValueAny = s;
export function okOrEmptyArgument(x: S | undefined) { take(x || {}); }
export const okLiteralToUnknownIndex: UnknownIdx = { a: 1 };

export const badInterfaceToUnknownIndex: UnknownIdx = s;
export const badInterfaceToNumberKey: NumberKeyAny = s;
export const badInterfaceToStringIndex: StringIdx = req;
export const badStringToAnyIndex: AnyIdx = "x";
export function badPrimitiveArgument() { take(1); }
// A class of the same name merges its members into the interface, so the
// interface's own empty member list does not make the target unrestricted.
class Merged { required!: number }
interface Merged { [k: string]: any }
export const badClassHalfOfMergedTarget: Merged = s;
