// Every TypeScript-only lowering, in one file, observed by VALUE.
//
// The lattice's other target is `lib/typescript.js`: 9 MB of published
// UMD, which is the right input for finding pass interactions nobody
// thought of and the wrong input for two questions it cannot ask.
//
//   1. It is published `.js`. No `#private` fields, no `enum`, no
//      `namespace`, no parameter properties, no accessors that need
//      lowering — so NO TypeScript-only lowering is exercised at all.
//      When `lower_private_fields` ran only in the merged pipeline and
//      bare `--bundle` emitted `__private_brand__0__x` verbatim, this
//      harness ran that exact combination on every run and reported
//      "behave identically", because there was nothing to leak.
//   2. Its only observation is whether `tsc`'s stdout matches. An extra
//      own enumerable property on an internal object never reaches
//      stdout, so even with such a field present the question could not
//      see the answer.
//
// So this file is deliberately not a real library. Its job is coverage
// of the lowerings, one of each, with an observation that inspects the
// VALUES: own keys, `JSON.stringify`, object spread and `for…in`, which
// is what a leaked brand or a dropped field actually changes. The
// realism half is the 9 MB target's job.
//
// The baseline is Node running THIS FILE through
// `--experimental-transform-types`, so the reference is the language,
// not another mtsc output.

// ---- #private fields, the shape that leaked --------------------------
class Counter {
  #count = 0;
  #label: string;
  static #made = 0;

  constructor(label: string) {
    this.#label = label;
    Counter.#made += 1;
  }
  bump(): number {
    this.#count += 1;
    return this.#count;
  }
  describe(): string {
    return this.#label + "=" + String(this.#count);
  }
  static made(): number {
    return Counter.#made;
  }
}

// ---- parameter properties -------------------------------------------
class Point {
  constructor(
    public readonly x: number,
    private y: number,
    protected z: number = 3,
  ) {}
  sum(): number {
    return this.x + this.y + this.z;
  }
}

// ---- accessors ------------------------------------------------------
class Box {
  #value = 1;
  get value(): number {
    return this.#value;
  }
  set value(v: number) {
    this.#value = v * 2;
  }
}

// ---- enum / const enum ----------------------------------------------
enum Level {
  Low = 1,
  High = 4,
}
const enum Arch {
  X64 = "x64",
  Arm = "arm",
}

// ---- namespace ------------------------------------------------------
namespace Geo {
  export const unit = 1;
  export function scale(n: number): number {
    return n * unit * 2;
  }
  export namespace Inner {
    export const tag = "inner";
  }
}

// ---- abstract / implements / override -------------------------------
interface Named {
  name(): string;
}
abstract class Base implements Named {
  abstract name(): string;
  greet(): string {
    return "hi " + this.name();
  }
}
class Impl extends Base {
  override name(): string {
    return "impl";
  }
}

// ---- optional chaining / nullish / satisfies / as const -------------
const table = { a: 1, b: 2 } as const;
const maybe: { deep?: { n: number } } = { deep: { n: 7 } };
const conf = { mode: "fast" } satisfies { mode: string };

// ---- decorate the observation ---------------------------------------
const c = new Counter("c");
c.bump();
c.bump();
const p = new Point(1, 2);
const b = new Box();
b.value = 5;

const spreadOfCounter = { ...c };
const forInOfCounter: string[] = [];
for (const k in c) {
  forInOfCounter.push(k);
}
const spreadOfPoint = { ...p };

export const report = {
  // A leaked brand shows up in three of these four.
  counterKeys: Object.keys(c).join(","),
  counterJson: JSON.stringify(c),
  counterSpreadKeys: Object.keys(spreadOfCounter).join(","),
  counterForIn: forInOfCounter.join(","),
  describe: c.describe(),
  made: Counter.made(),

  // A parameter property must exist and be enumerable, and `private` /
  // `protected` are erased at runtime, so all three are own keys.
  pointKeys: Object.keys(p).join(","),
  pointSpreadKeys: Object.keys(spreadOfPoint).join(","),
  pointSum: p.sum(),

  // An accessor is on the prototype, so it is NOT an own key, and the
  // setter has to have run.
  boxKeys: Object.keys(b).join(","),
  boxValue: b.value,
  boxHasProtoAccessor: Object.getOwnPropertyNames(
    Object.getPrototypeOf(b) as object,
  ).join(","),

  // An `enum` is a runtime object with a reverse map; a `const enum` is
  // not a runtime object at all.
  levelObjectKeys: Object.keys(Level).join(","),
  levelHigh: Level.High,
  levelReverse: Level[4],
  archX64: Arch.X64,

  // A namespace is a runtime object, nested one included.
  geoScale: Geo.scale(3),
  geoKeys: Object.keys(Geo).join(","),
  geoInner: Geo.Inner.tag,

  // Inheritance through an abstract base.
  greet: new Impl().greet(),
  implIsBase: new Impl() instanceof Base,

  tableA: table.a,
  deepN: maybe.deep?.n ?? -1,
  missing: (maybe as { gone?: { n: number } }).gone?.n ?? -1,
  mode: conf.mode,
};
