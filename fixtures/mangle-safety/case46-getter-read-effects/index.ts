// A getter's body runs on every read, and each of these four shapes
// discards the read's VALUE — which is not the same as discarding the
// read. `hits` counts what actually ran.
const trace: string[] = [];

class Counter {
  hits = 0;

  get tick(): number {
    this.hits += 1;
    trace.push("tick");
    return this.hits;
  }
}

const counter = new Counter();

// 1. A bare expression statement.
counter.tick;

// 2. `void EXPR` — falsy whatever EXPR is, and EXPR still runs.
void counter.tick;

// 3. The left operand of a discarded comma.
const nine = (counter.tick, 9);

// 4. An array literal whose `.length` is taken: the length is known
//    from the syntax, the elements are not therefore dead.
const two = [counter.tick, 1].length;

// The control. A read whose value IS used has never been at risk; it is
// here so that "the getter ran" cannot be satisfied by this one alone.
const used = counter.tick;

export const hits = counter.hits;
export const ran = trace.length;
export const values = [nine, two, used];
