// TypeScript-specific adversarial corpus — features that only TS
// (not plain JS) introduces, where the transform layer has to
// strip / lower / preserve the right thing. Patterns explicitly
// chosen to stress the dividing line between "TS-only sugar that
// must vanish from JS output" and "runtime constructs that must
// survive".

// ---------------------------------------------------------------------------
// Interface declaration merging — multiple `interface X` decls
// for the same name fold into one. Runtime emit shouldn't care
// about interfaces at all.
// ---------------------------------------------------------------------------

///|
async test "ts-only: interface declaration merging produces no runtime artifact" {
  let files : Map[String, String] = {}
  files["entry.ts"] =
    #|interface User { id: number }
    #|interface User { name: string }
    #|interface User { roles?: string[] }
    #|const u: User = { id: 1, name: "alice", roles: ["admin"] };
    #|console.log("id:", u.id, "name:", u.name, "roles:", u.roles!.join(","));
    #|
  run_differential(
    "ts-interface-merge",
    files,
    "entry.ts",
    extra_reserved_props=["id", "name", "roles"],
  )
}

// ---------------------------------------------------------------------------
// Numeric / string enum — runtime has a real object, but TS
// initializers are tricky (auto-increment, reverse-mapping for
// numeric, etc.).
// ---------------------------------------------------------------------------

///|
async test "ts-only: numeric enum has reverse mapping at runtime" {
  let files : Map[String, String] = {}
  files["entry.ts"] =
    #|enum Color { Red, Green, Blue }
    #|console.log("red:", Color.Red);
    #|console.log("blue:", Color.Blue);
    #|console.log("reverse:", Color[1]);
    #|
  run_differential(
    "ts-numeric-enum",
    files,
    "entry.ts",
    extra_reserved_props=["Red", "Green", "Blue"],
  )
}

///|
async test "ts-only: string enum (no reverse mapping)" {
  let files : Map[String, String] = {}
  files["entry.ts"] =
    #|enum Direction { Up = "UP", Down = "DOWN" }
    #|console.log(Direction.Up);
    #|console.log(Direction.Down);
    #|const d = "UP";
    #|console.log("eq?", d === Direction.Up);
    #|
  run_differential(
    "ts-string-enum",
    files,
    "entry.ts",
    extra_reserved_props=["Up", "Down"],
  )
}

// ---------------------------------------------------------------------------
// Abstract class — `abstract` modifier is TS-only; runtime is a
// regular class. Concrete subclass extends it.
// ---------------------------------------------------------------------------

///|
async test "ts-only: abstract class with concrete subclass" {
  let files : Map[String, String] = {}
  files["entry.ts"] =
    #|abstract class Shape {
    #|  abstract area(): number;
    #|  describe(): string { return "shape:" + this.area(); }
    #|}
    #|class Circle extends Shape {
    #|  radius: number;
    #|  constructor(r: number) { super(); this.radius = r; }
    #|  area(): number { return Math.PI * this.radius * this.radius; }
    #|}
    #|const c = new Circle(2);
    #|console.log(c.area().toFixed(4));
    #|console.log(c.describe());
    #|
  run_differential(
    "ts-abstract-class",
    files,
    "entry.ts",
    extra_reserved_props=["radius"],
  )
}

// ---------------------------------------------------------------------------
// Method overload — multiple `function f(...)` signatures + one
// impl. Runtime sees the impl only.
// ---------------------------------------------------------------------------

///|
async test "ts-only: method overloads collapse to a single implementation" {
  let files : Map[String, String] = {}
  files["entry.ts"] =
    #|function format(n: number): string;
    #|function format(s: string): string;
    #|function format(arg: number | string): string {
    #|  if (typeof arg === "number") return "n:" + arg.toFixed(2);
    #|  return "s:" + arg;
    #|}
    #|console.log(format(3.14159));
    #|console.log(format("hi"));
    #|
  run_differential("ts-method-overload", files, "entry.ts")
}

// ---------------------------------------------------------------------------
// Type-only namespace — `namespace X { type ... }` has no runtime
// artifact. A value namespace (`namespace X { export const ... }`)
// becomes a runtime object.
// ---------------------------------------------------------------------------

///|
async test "ts-only: value namespace produces a runtime object" {
  let files : Map[String, String] = {}
  files["entry.ts"] =
    #|namespace Constants {
    #|  export const VERSION = "1.0";
    #|  export const MAX = 100;
    #|}
    #|console.log(Constants.VERSION);
    #|console.log(Constants.MAX);
    #|
  run_differential(
    "ts-namespace",
    files,
    "entry.ts",
    extra_reserved_props=["VERSION", "MAX"],
  )
}

// ---------------------------------------------------------------------------
// `declare` modifier — pure-type declarations that have no runtime
// presence. They should leave zero output behind.
// ---------------------------------------------------------------------------

///|
async test "ts-only: `declare const` emits no runtime decl" {
  let files : Map[String, String] = {}
  files["entry.ts"] =
    #|declare const __DEV__: boolean;
    #|declare function nodeOnly(x: number): number;
    #|// Provide shims so the runtime works (`declare` only tells TS
    #|// these exist elsewhere).
    #|(globalThis as any).__DEV__ = false;
    #|(globalThis as any).nodeOnly = (x: number) => x + 1;
    #|console.log("dev:", __DEV__);
    #|console.log("call:", nodeOnly(5));
    #|
  run_differential(
    "ts-declare",
    files,
    "entry.ts",
    extra_reserved_props=["__DEV__", "nodeOnly"],
  )
}

// ---------------------------------------------------------------------------
// Generic class + method — TS-only type params; runtime is plain.
// ---------------------------------------------------------------------------

///|
async test "ts-only: generic class + generic method round-trip" {
  let files : Map[String, String] = {}
  files["entry.ts"] =
    #|class Box<T> {
    #|  private value: T;
    #|  constructor(v: T) { this.value = v; }
    #|  map<U>(fn: (v: T) => U): Box<U> { return new Box(fn(this.value)); }
    #|  get(): T { return this.value; }
    #|}
    #|const a = new Box(5);
    #|const b = a.map(n => "n=" + n);
    #|const c = b.map(s => s.length);
    #|console.log("a:", a.get());
    #|console.log("b:", b.get());
    #|console.log("c:", c.get());
    #|
  run_differential(
    "ts-generic-class",
    files,
    "entry.ts",
    extra_reserved_props=["value"],
  )
}

// ---------------------------------------------------------------------------
// `import type { … }` and `type` modifier on a specifier
// ---------------------------------------------------------------------------

///|
async test "ts-only: `import type` produces no runtime import" {
  let files : Map[String, String] = {}
  files["types.ts"] =
    #|export type Status = "ok" | "fail";
    #|export interface Result { status: Status; value: number }
    #|
  files["entry.ts"] =
    #|import type { Status, Result } from "./types";
    #|function check(s: Status): Result { return { status: s, value: 42 }; }
    #|const r = check("ok");
    #|console.log("status:", r.status, "value:", r.value);
    #|
  run_differential(
    "ts-import-type",
    files,
    "entry.ts",
    extra_reserved_props=["status", "value"],
  )
}

// ---------------------------------------------------------------------------
// Non-null assertion `!` + type assertion `as` + `satisfies`
// ---------------------------------------------------------------------------

///|
async test "ts-only: assertion operators don't survive emit" {
  let files : Map[String, String] = {}
  files["entry.ts"] =
    #|interface Container { items: string[] }
    #|function pick(c: Container | null): string {
    #|  return c!.items[0];
    #|}
    #|const inputs = {
    #|  a: "alpha",
    #|  b: "beta",
    #|} satisfies Record<string, string>;
    #|console.log(pick({ items: ["one", "two"] }));
    #|console.log("from-sat:", (inputs as { a: string }).a);
    #|
  run_differential(
    "ts-assertions",
    files,
    "entry.ts",
    extra_reserved_props=["items", "a", "b"],
  )
}

// ---------------------------------------------------------------------------
// Index signatures `[k: string]: T` — runtime is just an object
// ---------------------------------------------------------------------------

///|
async test "ts-only: index signature on interface" {
  let files : Map[String, String] = {}
  files["entry.ts"] =
    #|interface Lookup { [key: string]: number }
    #|const scores: Lookup = { alice: 10, bob: 20 };
    #|scores["charlie"] = 30;
    #|console.log(Object.keys(scores).sort().join(","));
    #|console.log("alice:", scores.alice);
    #|console.log("charlie:", scores.charlie);
    #|
  run_differential(
    "ts-index-signature",
    files,
    "entry.ts",
    extra_reserved_props=["alice", "bob", "charlie"],
  )
}

// ---------------------------------------------------------------------------
// `readonly` on class field + `private` modifier
// ---------------------------------------------------------------------------

///|
async test "ts-only: readonly + private modifiers are TS-only" {
  let files : Map[String, String] = {}
  files["entry.ts"] =
    #|class Account {
    #|  readonly id: number;
    #|  private balance: number = 0;
    #|  constructor(id: number) { this.id = id; }
    #|  deposit(amount: number): void { this.balance = this.balance + amount; }
    #|  total(): number { return this.balance; }
    #|}
    #|const a = new Account(42);
    #|a.deposit(100);
    #|a.deposit(50);
    #|console.log("id:", a.id);
    #|console.log("total:", a.total());
    #|
  run_differential(
    "ts-readonly-private",
    files,
    "entry.ts",
    extra_reserved_props=["id", "balance"],
  )
}

// ---------------------------------------------------------------------------
// Type predicate function — `x is T` — runtime returns the bool
// the user wrote; TS adds narrowing semantics.
// ---------------------------------------------------------------------------

///|
async test "ts-only: type predicate function preserves the bool return" {
  let files : Map[String, String] = {}
  files["entry.ts"] =
    #|function isString(x: unknown): x is string {
    #|  return typeof x === "string";
    #|}
    #|const vals: unknown[] = ["hi", 1, true, "ok"];
    #|let count = 0;
    #|for (const v of vals) {
    #|  if (isString(v)) count = count + 1;
    #|}
    #|console.log("strings:", count);
    #|
  run_differential("ts-type-predicate", files, "entry.ts")
}

// ---------------------------------------------------------------------------
// `keyof` / mapped types — purely type-level
// ---------------------------------------------------------------------------

///|
async test "ts-only: `keyof` + indexed access don't affect runtime" {
  let files : Map[String, String] = {}
  files["entry.ts"] =
    #|interface User { id: number; name: string; email: string }
    #|type UserKey = keyof User;
    #|type UserVal = User[UserKey];
    #|function getField<K extends UserKey>(u: User, k: K): User[K] {
    #|  return u[k];
    #|}
    #|const u: User = { id: 1, name: "alice", email: "a@x" };
    #|console.log("id:", getField(u, "id"));
    #|console.log("name:", getField(u, "name"));
    #|console.log("email:", getField(u, "email"));
    #|
  run_differential(
    "ts-keyof",
    files,
    "entry.ts",
    extra_reserved_props=["id", "name", "email"],
  )
}
