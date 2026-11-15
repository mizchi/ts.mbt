// @strict: true
// @target: esnext

// `static #a` beside `#a` (TS2804), and a `readonly` field without an
// annotation having its LITERAL type: the constructor write is TS2322 while a
// read into a mutable `let` widens again.

class E { static #a() {} #a() {} }
class H { get #f() { return 0 } set #f(v: number) {} static #g = 1 }
class D {
  readonly noWiden = 1
  readonly typed: number = 1
  constructor() { this.noWiden = 5; this.typed = 7 }
  m() { let y = this.noWiden; y = 2; return y }
}
function outer(tag: string) {
  class Local { readonly t = tag; m() { return tag } }
  return Local
}
