// @strict: true
// @target: esnext

// A heritage clause that is a call followed by type arguments
// (`extends TaggedError("E")<{ ... }>`), as effect's `Data.TaggedError`.

declare function TaggedError(t: string): new <A>(a: A) => A
export class E extends TaggedError("E")<{
  message: string
}> {}
