// @strict: true
// @target: esnext

// An enum member `E.M` is assignable wherever `E` or `E.M` is expected, in
// an object literal's member, a property write, a return and a call
// argument, for a string enum as for a numeric one. A numeric enum accepts
// any `number`, also as the member of an object value that is not a
// literal. A plain string literal, a member of another enum and a member
// outside an expected member union are not assignable.

export enum DateSystem { AUTO = "auto", D1900 = "1900" }
export enum Other { AUTO = "auto" }
export interface Cfg { dateSystem?: DateSystem }
export enum Direction { UP, DOWN, LEFT, RIGHT }
export interface Ins { direction: Direction.LEFT | Direction.RIGHT }
export enum E { A, B }
declare const n: number;

export const okLiteralMember: Cfg = { dateSystem: DateSystem.AUTO };
export function okPropertyWrite(c: Cfg) { c.dateSystem = DateSystem.D1900; return c; }
export function okCallArgument(f: (d?: DateSystem) => void) { f(DateSystem.AUTO); }
export function okReturnedMember(): Cfg { return { dateSystem: DateSystem.AUTO }; }
export const okMemberUnion: Ins = { direction: Direction.LEFT };
export function okShadowedName(DateSystem: { AUTO: DateSystem }) { const c: Cfg = { dateSystem: DateSystem.AUTO }; return c; }
export const badOtherEnum: Cfg = { dateSystem: Other.AUTO };
export const badMemberOutsideUnion: Ins = { direction: Direction.UP };
export const badPlainLiteral: Cfg = { dateSystem: "auto" };

const numberMember = { r: n };
export const okNumberIntoNumericEnum: { r?: E } = numberMember;
const numberRequired = { r: n };
export const okNumberIntoRequiredEnum: { r: E } = numberRequired;
export interface I { r?: E }
const enumMember = { r: E.B };
export const okEnumMemberValue: I = enumMember;
const stringMember = { r: "x" };
export const badStringIntoNumericEnum: { r?: E } = stringMember;
const booleanMember = { r: true };
export const badBooleanIntoNumericEnum: { r?: E } = booleanMember;
const numberIntoString = { k: n };
export const badNumberIntoStringEnum: { k?: DateSystem } = numberIntoString;
