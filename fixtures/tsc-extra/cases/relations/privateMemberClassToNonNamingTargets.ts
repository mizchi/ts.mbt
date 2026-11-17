// @strict: true
// @target: esnext

// A class with a `private` member is assignable to any target that does not
// declare a member of that name: a union of its bases, an object type, an
// interface, `Base | undefined`. Only a target naming the private member, or
// one the class does not satisfy structurally, rejects it. A union source is
// rejected when any member is.

class Root { r = 1 }
class Base extends Root { private p = 1; b = 2 }
class Arr extends Base { private q = 1; a = 3 }
class Ref extends Root { private z = 1; c = 4 }
class Other { private p = 1; b = 2 }
interface IB { b: number }
type V = Base | Ref;

function okUnionOfBases() { const v: V = new Arr(); }
function okObjectType() { const o: { b: number } = new Arr(); }
function okInterface() { const i: IB = new Arr(); }
function okOptionalBase() { const b: Base | undefined = new Arr(); }
function okRoot() { const r: Root = new Arr(); }
function okUnionSource(c: boolean) { const x = c ? new Arr() : new Base(); const b: Base = x; }
function badTargetNamesPrivateMember() { const o: { q: number } = new Arr(); }
function badUnrelatedClass() { const r: Ref = new Arr(); }
function badUnionWithoutAFit() { const t: Ref | { q: number } = new Arr(); }
function badSameShapeOtherDeclaration() { const b: Base = new Other(); }
function badUnionSourceMember(c: boolean) { const x = c ? new Arr() : new Other(); const b: Base = x; }
