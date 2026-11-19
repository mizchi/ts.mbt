// @strict: true
// @target: esnext

// An enum member written as an object-literal property keeps its
// enum-LITERAL type `E.M` where a callback returns the object under a
// contextual type: it fits the member itself, a union of members, a union
// discriminated by it, and the enum. An enum-literal type is also
// assignable to its member's VALUE type (`S.X` to `"x"` and `string`,
// auto-numbered `E.A` to `0` and `number`), while another member, another
// value and a plain literal of a different value are not.

enum E { A, B }
enum S { X = "x", Y = "y" }
interface I { kind: E; n: number }
interface J { tag: S; n: number }
interface IA { kind: E.A }
interface JX { tag: S.X }
interface Cx { tag: S.X; a: number }
interface Cy { tag: S.Y; b: number }
declare const xs: number[];

export const okNumericToEnum: I[] = xs.map((n) => ({ kind: E.A, n }));
export const okStringToEnum: J[] = xs.map((n) => ({ tag: S.X, n }));
export const okEitherBranch: J[] = xs.map((n) => { if (n) { return { tag: S.X, n }; } return { tag: S.Y, n }; });
export const okNumericMember: IA[] = xs.map(() => ({ kind: E.A }));
export const okStringMember: JX[] = xs.map(() => ({ tag: S.X }));
export const okUnionOfMembers: { tag: S.X | S.Y }[] = xs.map(() => ({ tag: S.X }));
export const okDiscriminatedUnion: (Cx | Cy)[] = xs.map(() => ({ tag: S.X, a: 1 }));
export const okMemberToNumber: { kind: number }[] = xs.map(() => ({ kind: E.A }));
export const okMemberToString: { tag: string }[] = xs.map(() => ({ tag: S.X }));
export const okAutoNumberedToItsValue: { kind: 0 }[] = xs.map(() => ({ kind: E.A }));
export const okStringMemberToItsValue: { tag: "x" }[] = xs.map(() => ({ tag: S.X }));
const widenedNumeric = { kind: E.A };
export const okWidenedToNumber: { kind: number } = widenedNumeric;
const widenedString = { tag: S.X };
export const okWidenedToString: { tag: string } = widenedString;
export const okWidenedToStringOrNumber: { tag: string | number } = widenedString;
export const badOtherMember: { tag: S.Y }[] = xs.map(() => ({ tag: S.X }));
export const badOtherValue: { kind: 1 }[] = xs.map(() => ({ kind: E.A }));
export const badOtherLiteral: { tag: "y" }[] = xs.map(() => ({ tag: S.X }));
