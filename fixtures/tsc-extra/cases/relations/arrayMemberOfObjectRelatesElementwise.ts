// @strict: true
// @target: esnext

// An object member holding an array relates element-wise: `{ xs: [{ a: 1
// }] }` is assignable to `{ xs: A[] }` with `A` an interface or an alias,
// and to an interface with such a member, and an element with optional
// members accepts one that has them. A wrong element type is not, and a
// `readonly` array is not assignable to a mutable one, inside an object as
// at the top level.

interface A { a: number }
type TA = { a: number }
interface K { action?: number | undefined; allowed?: boolean | undefined }
interface H { xs: A[] }

const f = { xs: [{ a: 1 }] };
export const okInterfaceElement: { xs: A[] } = f;
export const okAliasElement: { xs: TA[] } = f;
export const okInterfaceWithArrayMember: H = f;
const e5: { action: number; allowed: boolean }[] = [];
const b5 = { actions: e5 };
export const okOptionalElementMembers: { actions: K[] } = b5;
const g = { xs: [{ a: "1" }] };
export const badElementType: { xs: A[] } = g;
const ro: { xs: readonly A[] } = { xs: [] };
export const badReadonlyMember: { xs: A[] } = ro;
declare const r2: readonly A[];
export const badReadonlyTopLevel: A[] = r2;
