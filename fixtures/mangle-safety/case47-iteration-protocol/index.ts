// The iteration protocol calls `next` — and `return` on an early exit —
// BY NAME, off an object it obtained through `Symbol.iterator`. Nothing
// in this bundle names either, so only the implicit-protocol list keeps
// them.
const trace: string[] = [];

class Range {
  private i = 0;

  // A computed key: nothing could drop this one.
  [Symbol.iterator](): Range {
    return this;
  }

  // A plain identifier: this is the one that went.
  next(): { value: number; done: boolean } {
    this.i += 1;
    return this.i <= 3 ? { value: this.i, done: false } : { value: 0, done: true };
  }

  // Called by `for…of` when the loop exits early.
  return(): { value: number; done: boolean } {
    trace.push("cleanup");
    return { value: 0, done: true };
  }
}

function* counted(): Generator<number, void, unknown> {
  trace.push("a");
  yield 1;
  trace.push("b");
  yield 2;
}

// A class whose only consumer is a spread.
const spread = [...new Range()];

// A `for…of` that breaks, so `return` runs.
let firstOnly = 0;
for (const v of new Range()) {
  firstOnly = v;
  break;
}

// A generator, driven by a spread.
const yielded = [...counted()];

// The control: a class that escapes nothing and whose one live method IS
// named, so the dead one must still go.
class Plain {
  live(): number {
    return 1;
  }

  deadWeight(): number {
    return 2;
  }
}

const plain = new Plain();

export const values = spread;
export const first = firstOnly;
export const generated = yielded;
export const liveValue = plain.live();
export const effects = trace;
