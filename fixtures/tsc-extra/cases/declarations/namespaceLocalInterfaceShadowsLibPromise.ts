// @strict: true
// @target: esnext

// A namespace-local `interface Promise<T>` SHADOWS the lib type (at a
// script's top level it would merge), so its own `then` decides the call.

namespace m1 {
  interface Promise<T> { then<U>(cb: (x: T) => Promise<U>): Promise<U>; }
  declare function single(n: number): Promise<number>;
  declare var np: Promise<number>;
  var ok = np.then(single);
}
namespace m2 {
  interface Promise<T> { then<U>(cb: (x: T) => Promise<U>): Promise<U>; }
  declare function tf(n: number): Promise<number>;
  declare function tf(s: string): Promise<string>;
  declare var np: Promise<number>;
  var bad = np.then(tf);
}
