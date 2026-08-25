// `this.#rows[k]` is an entry lookup — the private field is a
// `Record`, and a private name cannot belong to anything but this
// class body — so unused methods on other classes may still go.
//
// `this.table[k]` in the object literal is the counter-case. `Registry`
// types `table` as a `Record`, but the literal's `table` holds a
// `Worker`, so that read really does name a `Worker` method. Reading a
// PUBLIC field's class annotation here deleted `spare` and turned
// `holder.call("spare")` into `undefined`.
class Worker {
  run(): string {
    return "R";
  }
  spare(): string {
    return "S";
  }
}

class Registry {
  #rows: Record<string, string> = { seed: "0" };
  table: Record<string, string> = {};
  read(k: string): string | undefined {
    return this.#rows[k];
  }
  find(k: string): string | undefined {
    return this.table[k];
  }
  unusedInternally(): number {
    return 99;
  }
}

const holder = {
  table: new Worker(),
  call(k: string): unknown {
    return this.table[k];
  },
};

const registry = new Registry();
const dynamic = holder.call("spare") as (() => string) | undefined;

export const report = {
  seeded: registry.read("seed"),
  missing: registry.find("nope"),
  viaDynamic: typeof dynamic === "function" ? dynamic.call(holder.table) : "GONE",
};
console.log(report);
