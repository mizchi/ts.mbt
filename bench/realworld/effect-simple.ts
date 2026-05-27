import { pipe } from "effect/Function";

const result = pipe(10, (n) => n * 2, (n) => n + 1);

if (result === 21) {
  console.log("effect simple ok:", result);
} else {
  console.log("effect simple fail:", result);
}
