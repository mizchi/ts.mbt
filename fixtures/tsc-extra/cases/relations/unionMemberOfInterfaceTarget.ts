// @strict: true
// @target: esnext

// An object type whose member is an object, against an interface whose
// member is `S | undefined` (or `S | null`), relates member by member: the
// source member has to fit some part of the target's union, and each part of
// a union source member has to fit. univer's permission payloads write
// `scope: { read, edit }` into `scope: IObjScope | undefined`. A wrong member
// type, a missing member, and `null` into `undefined` are still errors.

interface S { read: number; edit: number }
interface P { scope: S | undefined; name: string }
interface PN { scope: S | null; name: string }
declare const good: { name: string; scope: { read: number; edit: number } };
declare const wrongType: { name: string; scope: { read: string; edit: number } };
declare const missing: { name: string; scope: { read: number } };
declare const maybe: { name: string; scope: { read: number; edit: number } | undefined };
declare const maybeNull: { name: string; scope: { read: number; edit: number } | null };
export const okGood: P | undefined = good;
export const okMaybe: P = maybe;
export const okNullTarget: PN = maybeNull;
export const badWrongType: P | undefined = wrongType;
export const badMissing: P = missing;
export const badNullIntoUndefined: P = maybeNull;
