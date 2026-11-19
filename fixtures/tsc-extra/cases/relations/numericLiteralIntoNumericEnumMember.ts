// @strict: true
// @target: esnext

// A numeric literal type is assignable to a numeric enum only when some
// member holds that value (TypeScript 5.0). `number` itself still is, and
// so is any literal when a member's value is computed and so not known.

enum E { A = 0, B = 1 }
enum C { A = 0, B = f() }
declare function f(): number;

declare const o1: { r: 123 };
export const badLiteralNoMember: { r: E } = o1;
declare const o2: { r: 1 };
export const okLiteralMember: { r: E } = o2;
declare const o3: { r: number };
export const okBroadNumber: { r: E } = o3;
declare const o4: { r: 7 };
export const okComputedMemberMayHold: { r: C } = o4;
declare const o5: { r: 0 | 1 };
export const okUnionOfMembers: { r: E } = o5;
declare const o6: { r: 0 | 2 };
export const badUnionWithANonMember: { r: E } = o6;
