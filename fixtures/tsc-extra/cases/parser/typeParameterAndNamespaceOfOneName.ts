// @strict: true
// @target: esnext

// A type parameter and a namespace share a name: `P.Encoded` is the
// namespace member.

declare namespace P { type Encoded = string }
interface D<P extends string> {
  readonly f?: ((p: P.Encoded) => number) | undefined
}
