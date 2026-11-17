// @strict: true
// @target: esnext

// A `declare class` accepts the arguments of every constructor overload, not
// only the last one, and a class merged with a same-named interface (how
// `@types/react` declares `Component`) keeps the class's own members.

declare class C<P> {
  readonly props: P;
  constructor(p: P);
  constructor(p: P, c: any);
}
interface C<P> extends Lifecycle {}
interface Lifecycle { didMount?(): void }
class App extends C<{ a: number }> {
  n(): number { return this.props.a; }
}

function okFirstOverload() { const c = new C({ a: 1 }); }
function okSecondOverload() { const c = new C({ a: 1 }, 2); }
function okSubclassReadsClassMember() { const n: number = new App({ a: 1 }).n(); }
function okInterfaceMember() { new App({ a: 1 }).didMount?.(); }
function badTooFew() { const c = new C(); }
function badTooMany() { const c = new C({ a: 1 }, 2, 3); }
function badMemberType() { const s: string = new App({ a: 1 }).props.a; }
