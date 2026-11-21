// @strict: true
// @target: esnext

// A type alias that is its own argument to a homomorphic mapped type
// (`{ [K in keyof T]: T[K] }`) circularly references itself, directly or
// inside a union argument. A checker that distributes the mapped type over
// a union argument has to stop expanding the alias, and the code after it
// is still checked. (A type alias is not an `ok…` / `bad…` claim here; mtsc
// does not report the TS2456 on either alias.)

type M<T> = { [K in keyof T]: T[K] };
type R = M<R>;
type N = M<N | null>;
export const badAfter: string = 1;
