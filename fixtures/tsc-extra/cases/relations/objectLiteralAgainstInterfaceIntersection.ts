// @strict: true
// @target: esnext

// An object literal against an interface intersected with an object type is
// checked against the merged members, the interface's inherited ones
// included: an enum member satisfies an enum-typed field, an extra property
// is excess, and a missing inherited member is missing.

enum E { A, B }
interface I1 { type: E }
interface J extends I1 { name: string }
declare function n1(v: I1 & { event: string }): void;
declare function nj(v: J & { event: string }): void;

export function okEnumMemberField() { n1({ type: E.B, event: "x" }); }
export function okInheritedMembers() { nj({ type: E.A, name: "n", event: "x" }); }
export function badExcessProperty() { n1({ type: E.B, event: "x", extra: 1 }); }
export function badMissingMember() { n1({ event: "x" }); }
export function badMissingInheritedMember() { nj({ name: "n", event: "x" }); }
