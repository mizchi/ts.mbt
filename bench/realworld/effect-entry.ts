import { Effect, pipe } from "effect";

const program = pipe(
  Effect.succeed(10),
  Effect.map((n) => n * 2),
  Effect.map((n) => n + 1),
);

const result = Effect.runSync(program);

if (result === 21) {
  console.log("effect ok:", result);
} else {
  console.log("effect fail:", result);
}
