// @strict: true
// @target: esnext

// TypeScript 3.5 relates an object to a discriminated union by splitting a
// discriminant of union or enum type into its members: `{ t: T; len:
// number }` fits `Retain | Insert | Del` when the object with each member
// of `T` in place of `t` fits some arm. Every combination has to fit, so
// an enum with a member no arm takes, or a member whose arm needs another
// property, does not.

export enum T { RETAIN = "r", INSERT = "i", DELETE = "d" }
interface Retain { t: T.RETAIN; len: number }
interface Insert { t: T.INSERT; len: number; body: { dataStream: string } }
interface Del { t: T.DELETE; len: number }
type Action = Retain | Insert | Del;
type Small = Retain | Del;
declare function apply(a: Action[]): void;
declare function small(x: Small): void;

export function okArrayWithBody() { const actions = [{ t: T.INSERT, len: 1, body: { dataStream: "h" } }]; apply(actions); }
export function okUnionTypedDiscriminant(t: T.RETAIN | T.DELETE) { const x = { t, len: 1 }; small(x); }
export enum K { A, B }
export interface KA { k: K.A; a: number }
export interface KB { k: K.B; a: number }
declare function kk(x: KA | KB): void;
export function okNumericEnumSplits() { const x = { k: K.A, a: 1 }; kk(x); }
export function badArrayMissesInsertBody() { const actions = [{ t: T.RETAIN, len: 1 }]; apply(actions); }
export function badArrayMixedMissesInsertBody() { const actions = [{ t: T.RETAIN, len: 1 }, { t: T.DELETE, len: 2 }]; apply(actions); }
export function badEnumTypedTooWide(t: T) { const x = { t, len: 1 }; small(x); }
export function badLetWidensToEnum() { let a = { t: T.RETAIN, len: 1 }; small(a); }
export function badWrongPropertyType() { const actions = [{ t: T.RETAIN, len: "1" }]; apply(actions); }
export function badNumericEnumWrongShape() { const x = { k: K.A, b: 1 }; kk(x); }
