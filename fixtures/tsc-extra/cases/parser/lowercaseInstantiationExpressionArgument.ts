// @strict: true
// @target: esnext

// An instantiation expression on a lower-case name followed by `,`.

declare const fx: <A>(a: A) => A
declare function g(a: unknown, b: unknown): void
g(fx<string>, 1)
