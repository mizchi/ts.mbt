import { Array as Arr } from "effect";

const xs = Arr.range(1, 5);
const sum = Arr.reduce(xs, 0, (acc, x) => acc + x);

if (sum === 15) {
  console.log("effect arr ok:", sum);
} else {
  console.log("effect arr fail:", sum);
}
