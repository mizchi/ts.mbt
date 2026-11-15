// @strict: true
// @target: esnext

// Call signatures separated by a newline: `<B>` on the next line starts a
// new member; it is not type arguments of the previous return type.

export const dual: {
  <A>(x: A): A
  <B>(y: B): B
} = null as any
