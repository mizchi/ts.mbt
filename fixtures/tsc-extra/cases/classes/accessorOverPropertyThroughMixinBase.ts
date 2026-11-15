// @strict: true
// @target: esnext

// TS2611 through a mixin: the base of `mixin(B)` is the intersection of the
// mixin's class and `B`, and a member several constituents declare is an
// accessor only when every declaration is one of the same kind.

function mixin<T extends { new (...args: any[]): {} }>(superclass: T) {
  return class extends superclass { get name() { return ""; } };
}
class B0 { }
class B1 { set name(v: string) {} }
class B2 { get name() { return "" } }
class B3 { name = "" }
class M0 extends mixin(B0) { get name() { return ""; } }
class M1 extends mixin(B1) { get name() { return ""; } }
class M2 extends mixin(B2) { get name() { return ""; } }
class M3 extends mixin(B3) { get name() { return ""; } }
