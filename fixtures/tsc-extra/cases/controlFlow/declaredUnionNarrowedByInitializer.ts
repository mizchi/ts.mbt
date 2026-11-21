// @strict: true
// @target: esnext

// A declaration narrows its declared union by the initializer, as the
// assignment `v = init` does: a class-typed initializer leaves the members it
// names. A later assignment replaces it.

class A { a = 1; isErr() { return false; } }
class B { b = 1; isErr() { return false; } }
type AB = A | B;
declare const av: A;
declare const bv: B;
declare const flag: boolean;
export function okLet(): A { let v: AB = flag ? (av as A) : av; if (v.isErr()) { return v; } return v; }
export function okConst(): A { const v: AB = av; return v; }
export function badReassigned(): A { let v: AB = av; v = bv; return v; }
export function badOtherMember(): A { let v: AB = bv; return v; }
