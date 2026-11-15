// @strict: true
// @target: esnext

// TS2689 for a class extending an interface, but not for an interface merged
// with a `declare var` of a construct-signature type.

interface Base<T> { x: T }
class D0 extends Base<string> {}
interface X { a: number }
declare var X: { new (): X };
class D1 extends X {}
class D2 extends Error {}
