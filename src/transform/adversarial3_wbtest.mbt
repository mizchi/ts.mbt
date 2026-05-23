// Round-three adversarial corpus — the "residual" patterns that
// the previous rounds either skipped or didn't cover at all:
//   - cross-module top-level name collisions
//   - spread / object-literal overwrite ordering
//   - computed property keys (`[Symbol.iterator]` etc.)
//   - circular imports (a ↔ b)
//   - a few more reflective / coercion patterns

// ---------------------------------------------------------------------------
// Top-level name collisions across modules
// ---------------------------------------------------------------------------

///|
async test "adv3: two modules both define `helper` at top-level" {
  // Each module has its own private `helper` referenced via an
  // exported function. After bundling both modules concatenate
  // into the same global scope; the bundler has to keep the two
  // `helper`s distinguishable (typically by renaming one).
  let files : Map[String, String] = {}
  files["a.ts"] =
    #|function helper(n: number): number { return n + 100; }
    #|export function fromA(x: number): number { return helper(x); }
    #|
  files["b.ts"] =
    #|function helper(n: number): number { return n * 1000; }
    #|export function fromB(x: number): number { return helper(x); }
    #|
  files["entry.ts"] =
    #|import { fromA } from "./a";
    #|import { fromB } from "./b";
    #|console.log("A(5)=", fromA(5));
    #|console.log("B(5)=", fromB(5));
    #|
  run_differential("adv3-name-collision", files, "entry.ts")
}

///|
async test "adv3: two modules both export `default`" {
  // Both exports are unnamed `default` from the parser's POV; the
  // bundler synthesises `__export_default__N` for each so they
  // can coexist.
  let files : Map[String, String] = {}
  files["plus.ts"] =
    #|export default function (n: number): number { return n + 1; }
    #|
  files["times.ts"] =
    #|export default function (n: number): number { return n * 2; }
    #|
  files["entry.ts"] =
    #|import plus from "./plus";
    #|import times from "./times";
    #|console.log("plus(5):", plus(5));
    #|console.log("times(5):", times(5));
    #|console.log("compose:", times(plus(5)));
    #|
  run_differential("adv3-double-default-export", files, "entry.ts")
}

// ---------------------------------------------------------------------------
// Object-literal overwrite ordering — later keys win, spread
// ordering matters
// ---------------------------------------------------------------------------

///|
async test "adv3: object literal key overwrite — last wins" {
  let files : Map[String, String] = {}
  files["entry.ts"] =
    #|const obj: any = { a: 1, b: 2, a: 99 };
    #|console.log("a=", obj.a, "b=", obj.b);
    #|
  run_differential("adv3-key-overwrite", files, "entry.ts")
}

///|
async test "adv3: spread ordering with overlapping keys" {
  // The merge order matters: later spreads override earlier ones,
  // and an explicit pair after a spread overrides the spread.
  let files : Map[String, String] = {}
  files["entry.ts"] =
    #|const a = { x: 1, y: 2 };
    #|const b = { y: 20, z: 30 };
    #|const merged = { ...a, ...b, x: 999 };
    #|console.log("x=", merged.x, "y=", merged.y, "z=", merged.z);
    #|const reordered = { x: 999, ...a, ...b };
    #|console.log("reordered x=", reordered.x);
    #|
  run_differential("adv3-spread-ordering", files, "entry.ts")
}

// ---------------------------------------------------------------------------
// Computed property keys — `[Symbol.iterator]`, dynamic strings
// ---------------------------------------------------------------------------

///|
async test "adv3: computed property key with string expression" {
  let files : Map[String, String] = {}
  files["entry.ts"] =
    #|const key = "userField";
    #|const obj: any = { [key]: 42, ["another-" + "field"]: "ok" };
    #|console.log("via-key:", obj[key]);
    #|console.log("via-literal:", obj["another-field"]);
    #|console.log("via-static:", obj.userField);
    #|
  run_differential(
    "adv3-computed-key",
    files,
    "entry.ts",
    // `userField` is set as a computed key whose value is the
    // string "userField" — at runtime the property name is the
    // literal. Static reads via `obj.userField` won't match any
    // statically-renamed key, so we reserve it explicitly.
    extra_reserved_props=["userField"],
  )
}

///|
async test "adv3: Symbol.iterator computed key on a class" {
  // The class declares an iterator method via `[Symbol.iterator]`.
  // The desugar has to leave that key as a computed expression at
  // emit time so the runtime picks the well-known Symbol.
  let files : Map[String, String] = {}
  files["entry.ts"] =
    #|class Three {
    #|  [Symbol.iterator]() {
    #|    let i = 0;
    #|    return {
    #|      next() {
    #|        return i < 3
    #|          ? { value: i++ * 10, done: false }
    #|          : { value: undefined, done: true };
    #|      },
    #|    };
    #|  }
    #|}
    #|const out: number[] = [];
    #|for (const v of new Three()) out.push(v);
    #|console.log("values:", out.join(","));
    #|
  run_differential("adv3-symbol-iterator-class", files, "entry.ts")
}

// ---------------------------------------------------------------------------
// Circular imports
// ---------------------------------------------------------------------------

///|
async test "adv3: circular import a ↔ b with lazy function references" {
  // `a.ts` and `b.ts` reference each other through functions, but
  // the functions are only called after both modules have finished
  // loading. JS semantics make this work — the bundler must
  // preserve module order so neither hits a TDZ.
  let files : Map[String, String] = {}
  files["a.ts"] =
    #|import { fromB } from "./b";
    #|export function fromA(n: number): number {
    #|  if (n <= 0) return 0;
    #|  return n + fromB(n - 1);
    #|}
    #|
  files["b.ts"] =
    #|import { fromA } from "./a";
    #|export function fromB(n: number): number {
    #|  if (n <= 0) return 0;
    #|  return n * 10 + fromA(n - 1);
    #|}
    #|
  files["entry.ts"] =
    #|import { fromA } from "./a";
    #|console.log("a(3)=", fromA(3));
    #|console.log("a(0)=", fromA(0));
    #|console.log("a(1)=", fromA(1));
    #|
  run_differential("adv3-circular-import", files, "entry.ts")
}

// ---------------------------------------------------------------------------
// Misc coercion / type-tag patterns
// ---------------------------------------------------------------------------

///|
async test "adv3: string coercion via `${}` template and `+`" {
  let files : Map[String, String] = {}
  files["entry.ts"] =
    #|const n = 42;
    #|const b = true;
    #|const o = { toString() { return "<custom>"; } };
    #|console.log(`num=${n}`);
    #|console.log(`bool=${b}`);
    #|console.log(`obj=${o}`);
    #|console.log("concat=" + n + b);
    #|
  run_differential("adv3-string-coercion", files, "entry.ts")
}

///|
async test "adv3: instanceof and constructor.name checks" {
  let files : Map[String, String] = {}
  files["entry.ts"] =
    #|class Animal {
    #|  name: string;
    #|  constructor(n: string) { this.name = n; }
    #|}
    #|class Dog extends Animal {
    #|  bark() { return this.name + ":woof"; }
    #|}
    #|const d = new Dog("rex");
    #|console.log("inst-Dog:", d instanceof Dog);
    #|console.log("inst-Animal:", d instanceof Animal);
    #|console.log("name:", d.name);
    #|console.log("bark:", d.bark());
    #|
  run_differential(
    "adv3-instanceof",
    files,
    "entry.ts",
    extra_reserved_props=["name", "bark"],
  )
}

///|
async test "adv3: nullish + optional chaining together" {
  let files : Map[String, String] = {}
  files["entry.ts"] =
    #|type Maybe = { inner?: { value?: number } };
    #|const a: Maybe = { inner: { value: 42 } };
    #|const b: Maybe = { inner: {} };
    #|const c: Maybe = {};
    #|console.log("a:", a.inner?.value ?? -1);
    #|console.log("b:", b.inner?.value ?? -1);
    #|console.log("c:", c.inner?.value ?? -1);
    #|
  run_differential(
    "adv3-optional-chain",
    files,
    "entry.ts",
    extra_reserved_props=["inner", "value"],
  )
}

// ---------------------------------------------------------------------------
// Module-level top-level await is parsed but its semantics are
// fragile — verify the basic case still round-trips.
// ---------------------------------------------------------------------------

///|
async test "adv3: top-level Promise resolution via .then chain" {
  // We avoid top-level `await` since that requires ESM mode under
  // node's CJS loader. A plain `.then` chain has the same effect
  // for testing purposes.
  let files : Map[String, String] = {}
  files["entry.ts"] =
    #|Promise.resolve("hello")
    #|  .then((s: string) => s + ", world")
    #|  .then((s: string) => console.log("final:", s))
    #|  .catch((e: any) => console.log("err:", e.message));
    #|
  run_differential("adv3-promise-then-chain", files, "entry.ts")
}

// ---------------------------------------------------------------------------
// Try/catch with nested closures + finally
// ---------------------------------------------------------------------------

///|
async test "adv3: try/catch/finally with nested closure side effects" {
  let files : Map[String, String] = {}
  files["entry.ts"] =
    #|const log: string[] = [];
    #|function run() {
    #|  try {
    #|    log.push("t:before");
    #|    try {
    #|      log.push("inner:before");
    #|      throw new Error("boom");
    #|    } finally {
    #|      log.push("inner:finally");
    #|    }
    #|    log.push("t:after");
    #|  } catch (e: any) {
    #|    log.push("t:catch:" + e.message);
    #|  } finally {
    #|    log.push("t:finally");
    #|  }
    #|}
    #|run();
    #|console.log(log.join("|"));
    #|
  run_differential("adv3-try-finally", files, "entry.ts")
}

// ---------------------------------------------------------------------------
// Re-export with rename + glob
// ---------------------------------------------------------------------------

///|
async test "adv3: `export * from \"./y\"` keeps every export alive" {
  let files : Map[String, String] = {}
  files["src.ts"] =
    #|export const used1 = "u1";
    #|export const used2 = "u2";
    #|export const unused = "drop?";
    #|export function helper(x: number): number { return x + 1; }
    #|
  files["facade.ts"] =
    #|export * from "./src";
    #|
  files["entry.ts"] =
    #|import { used1, used2, helper } from "./facade";
    #|console.log(used1, used2, helper(10));
    #|
  run_differential("adv3-export-star", files, "entry.ts")
}
