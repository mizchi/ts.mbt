import { Effect } from "effect";

// `Effect.succeed(1)` is an `Effect<number>`, not the number it yields.
export const bad: number = Effect.succeed(1);
