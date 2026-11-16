import { Effect, Option, pipe } from "effect";
export const prog = pipe(Effect.succeed(1), Effect.map((n) => n + 1));
export const run: Promise<number> = Effect.runPromise(prog);
export const o: number = Option.getOrElse(Option.some(1), () => 0);
