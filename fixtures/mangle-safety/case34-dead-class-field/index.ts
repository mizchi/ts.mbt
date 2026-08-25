// A `this.x = …` write is what puts `x` on the instance. When nothing
// reads `x` and no door reaches it, the write's only effect is a field
// nobody can observe. The neighbours are each held by one condition.
let ticks = 0;
function bump(): number {
  ticks = ticks + 1;
  return 1;
}

class Counter {
  private total: number;
  private deadSlot: number;
  private impureSlot: number;
  constructor() {
    this.total = 0;
    this.deadSlot = 42;
    this.impureSlot = bump();
  }
  add(n: number): number {
    this.total = this.total + n;
    return n * 2;
  }
}

// Serialized, so every own key of THIS instance is published.
class Published {
  private slot: number;
  constructor() {
    this.slot = 7;
  }
}

// Probed with `in`, which names `probed` with a string the mangler
// doesn't rewrite.
class Probed {
  private probed: number;
  constructor() {
    this.probed = 9;
  }
}

const counter = new Counter();
const published = new Published();
const probed = new Probed();

export const report = {
  sum: counter.add(1) + counter.add(2),
  ticks,
  serialized: JSON.stringify(published),
  hasProbed: "probed" in probed ? 1 : 0,
};
