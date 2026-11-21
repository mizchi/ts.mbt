// @strict: true
// @target: esnext

// `Array.isArray(x)` splits `x`'s union into its array members and the
// rest when a member is itself an alias to a union, as it does for the
// union written out. The array side is the alias's array; the other side
// is the alias's members. An alias whose members are not aliases splits
// the same way.

class Base { a = 1 }
class Err { e = "x" }
type V = Base | Err;
interface I { i: number }
type W = I | Base;
export function okAlias(area: V | V[], out: V[][]) {
    if (Array.isArray(area)) { out.push(area); } else { const one: V = area; return one; }
    return null;
}
export function okInterfaceMember(area: W | W[], out: W[][]) { if (Array.isArray(area)) { out.push(area); } }
export function badElseIsNotArray(area: V | V[]) {
    if (!Array.isArray(area)) { const xs: V[] = area; return xs; }
    return null;
}
type Plain = string | number[];
export function okPlainAlias(w: Plain) {
    if (Array.isArray(w)) { const n: number[] = w; return n; }
    const s: string = w; return s;
}
export function badPlainAlias(w: Plain) {
    if (Array.isArray(w)) { const s: string = w; return s; }
    return null;
}
