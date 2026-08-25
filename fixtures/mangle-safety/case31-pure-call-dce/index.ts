// `scale` writes nothing outside its own scope and calls nothing
// impure, so the purity proof clears it and `droppable`'s unused call
// can go. `announce` reaches `console.log`, so its call must survive
// even though nobody reads `kept` for its value alone.
function scale(n: number): number {
  return n * 2 + Math.max(n, 1);
}
function announce(stage: string): string {
  console.log({ stage, at: "announce" });
  return stage;
}
const droppable = scale(21);
const kept = announce("start");
export const total = scale(4) + kept.length;
