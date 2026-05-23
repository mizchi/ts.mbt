// Differential corpus — small library-shaped TS programs modeled on
// real npm packages (mitt, nanoid, classnames, debounce, redux-tiny,
// rfdc, memoize, once, pick/omit, bytes-formatter). Each fixture is
// ~50–100 lines and exercises its public API via `console.log` so
// the differential runner has observable behavior to compare.
//
// The point is that these patterns are what library code *actually*
// looks like. If the optimizer breaks them, the breakage is visible
// immediately as a stdout divergence.

// ---------------------------------------------------------------------------
// mitt-style event emitter
// ---------------------------------------------------------------------------

///|
async test "corpus: mitt-style event emitter dispatches in registration order" {
  let files : Map[String, String] = {}
  files["mitt.ts"] =
    #|export type Handler<T> = (payload: T) => void;
    #|export interface Emitter<E extends Record<string, any>> {
    #|  on<K extends keyof E>(type: K, handler: Handler<E[K]>): void;
    #|  off<K extends keyof E>(type: K, handler: Handler<E[K]>): void;
    #|  emit<K extends keyof E>(type: K, payload: E[K]): void;
    #|}
    #|export function mitt<E extends Record<string, any>>(): Emitter<E> {
    #|  const handlers = new Map<string, Array<Handler<any>>>();
    #|  return {
    #|    on(type, handler) {
    #|      const list = handlers.get(type as string) ?? [];
    #|      list.push(handler);
    #|      handlers.set(type as string, list);
    #|    },
    #|    off(type, handler) {
    #|      const list = handlers.get(type as string);
    #|      if (!list) return;
    #|      const idx = list.indexOf(handler);
    #|      if (idx >= 0) list.splice(idx, 1);
    #|    },
    #|    emit(type, payload) {
    #|      const list = handlers.get(type as string);
    #|      if (!list) return;
    #|      for (const h of list.slice()) h(payload);
    #|    },
    #|  };
    #|}
    #|
  files["entry.ts"] =
    #|import { mitt } from "./mitt";
    #|type Events = { tick: { value: number }; pong: string };
    #|const bus = mitt<Events>();
    #|bus.on("tick", (p) => console.log("tick", p.value));
    #|bus.on("pong", (p) => console.log("pong", p));
    #|bus.emit("tick", { value: 1 });
    #|bus.emit("pong", "hello");
    #|bus.emit("tick", { value: 2 });
    #|
  run_differential(
    "corpus-mitt",
    files,
    "entry.ts",
    extra_reserved_props=["value"],
  )
}

// ---------------------------------------------------------------------------
// nanoid-style ID generator (deterministic — seeded by index)
// ---------------------------------------------------------------------------

///|
async test "corpus: nanoid-style id generator with custom alphabet" {
  let files : Map[String, String] = {}
  files["nano.ts"] =
    #|const ALPHABET = "0123456789abcdefghijklmnopqrstuvwxyz";
    #|export function generateId(seed: number, size: number): string {
    #|  let id = "";
    #|  let s = seed;
    #|  for (let i = 0; i < size; i = i + 1) {
    #|    s = (s * 1103515245 + 12345) & 0x7fffffff;
    #|    id = id + ALPHABET[s % ALPHABET.length];
    #|  }
    #|  return id;
    #|}
    #|
  files["entry.ts"] =
    #|import { generateId } from "./nano";
    #|console.log(generateId(1, 8));
    #|console.log(generateId(42, 12));
    #|console.log(generateId(2024, 4));
    #|
  run_differential("corpus-nanoid", files, "entry.ts")
}

// ---------------------------------------------------------------------------
// classnames-style class joiner (handles strings, objects, arrays)
// ---------------------------------------------------------------------------

///|
async test "corpus: classnames-style joiner with mixed argument types" {
  let files : Map[String, String] = {}
  files["cn.ts"] =
    #|export function cn(...args: any[]): string {
    #|  const out: string[] = [];
    #|  for (const a of args) {
    #|    if (!a) continue;
    #|    if (typeof a === "string") {
    #|      out.push(a);
    #|    } else if (Array.isArray(a)) {
    #|      const inner = cn(...a);
    #|      if (inner) out.push(inner);
    #|    } else if (typeof a === "object") {
    #|      for (const k of Object.keys(a)) {
    #|        if (a[k]) out.push(k);
    #|      }
    #|    }
    #|  }
    #|  return out.join(" ");
    #|}
    #|
  files["entry.ts"] =
    #|import { cn } from "./cn";
    #|console.log(cn("a", "b"));
    #|console.log(cn("base", { active: true, disabled: false }, ["extra-1", "extra-2"]));
    #|console.log(cn(null, undefined, "", "kept", { x: 0 }, { y: 1 }));
    #|
  run_differential(
    "corpus-classnames",
    files,
    "entry.ts",
    // Object.keys + dynamic `a[k]` mean property names are
    // user-facing — the caller protects them.
    extra_reserved_props=["active", "disabled", "x", "y"],
  )
}

// ---------------------------------------------------------------------------
// debounce — closure + setTimeout
// ---------------------------------------------------------------------------

///|
async test "corpus: debounce-style closure preserves identity across calls" {
  // We don't actually wait for the timer to fire (would require a
  // microtask in the test). Instead the entry script captures the
  // returned function's identity and pending state to verify the
  // closure was set up correctly. The optimizer must not collapse
  // either of the two private fields.
  let files : Map[String, String] = {}
  files["debounce.ts"] =
    #|export function debounce<A extends any[]>(fn: (...args: A) => void, ms: number) {
    #|  let timer: any = null;
    #|  let lastArgs: A | null = null;
    #|  const wrapped = (...args: A) => {
    #|    lastArgs = args;
    #|    if (timer === null) {
    #|      timer = "pending";
    #|    }
    #|  };
    #|  wrapped.flush = () => {
    #|    if (lastArgs !== null) {
    #|      fn(...(lastArgs as A));
    #|      lastArgs = null;
    #|      timer = null;
    #|    }
    #|  };
    #|  return wrapped;
    #|}
    #|
  files["entry.ts"] =
    #|import { debounce } from "./debounce";
    #|let count = 0;
    #|const d = debounce((n: number) => { count = count + n; }, 100);
    #|d(5);
    #|d(10);
    #|d(15);
    #|d.flush();
    #|console.log("count:", count);
    #|d.flush();
    #|console.log("count-after-second-flush:", count);
    #|
  run_differential(
    "corpus-debounce",
    files,
    "entry.ts",
    extra_reserved_props=["flush"],
  )
}

// ---------------------------------------------------------------------------
// redux-tiny — store / dispatch / subscribe
// ---------------------------------------------------------------------------

///|
async test "corpus: redux-style store dispatches actions through a reducer" {
  let files : Map[String, String] = {}
  files["store.ts"] =
    #|export type Action = { type: string; payload?: any };
    #|export type Reducer<S> = (state: S, action: Action) => S;
    #|export function createStore<S>(reducer: Reducer<S>, initial: S) {
    #|  let state = initial;
    #|  const listeners: Array<() => void> = [];
    #|  return {
    #|    getState() { return state; },
    #|    dispatch(action: Action) {
    #|      state = reducer(state, action);
    #|      for (const l of listeners) l();
    #|    },
    #|    subscribe(fn: () => void) {
    #|      listeners.push(fn);
    #|      return () => {
    #|        const idx = listeners.indexOf(fn);
    #|        if (idx >= 0) listeners.splice(idx, 1);
    #|      };
    #|    },
    #|  };
    #|}
    #|
  files["entry.ts"] =
    #|import { createStore, Action } from "./store";
    #|type State = { count: number };
    #|const reducer = (state: State, a: Action): State => {
    #|  if (a.type === "inc") return { count: state.count + 1 };
    #|  if (a.type === "dec") return { count: state.count - 1 };
    #|  if (a.type === "set") return { count: a.payload };
    #|  return state;
    #|};
    #|const store = createStore(reducer, { count: 0 });
    #|const events: string[] = [];
    #|const unsub = store.subscribe(() => {
    #|  events.push("change:" + store.getState().count);
    #|});
    #|store.dispatch({ type: "inc" });
    #|store.dispatch({ type: "inc" });
    #|store.dispatch({ type: "set", payload: 10 });
    #|unsub();
    #|store.dispatch({ type: "dec" });
    #|console.log("final:", store.getState().count);
    #|console.log("events:", events.join(","));
    #|
  run_differential(
    "corpus-redux",
    files,
    "entry.ts",
    extra_reserved_props=["type", "payload", "count"],
  )
}

// ---------------------------------------------------------------------------
// rfdc — recursive deep clone
// ---------------------------------------------------------------------------

///|
async test "corpus: rfdc-style deep clone handles arrays and nested objects" {
  let files : Map[String, String] = {}
  files["clone.ts"] =
    #|export function clone<T>(value: T): T {
    #|  if (value === null) return value;
    #|  if (typeof value !== "object") return value;
    #|  if (Array.isArray(value)) {
    #|    const arr: any[] = [];
    #|    for (const item of value as any[]) arr.push(clone(item));
    #|    return arr as any;
    #|  }
    #|  const out: any = {};
    #|  for (const k of Object.keys(value as any)) {
    #|    out[k] = clone((value as any)[k]);
    #|  }
    #|  return out;
    #|}
    #|
  files["entry.ts"] =
    #|import { clone } from "./clone";
    #|const src = { a: 1, nested: { b: [2, 3, { c: "deep" }] }, list: ["x", "y"] };
    #|const dup = clone(src);
    #|console.log("eq?", dup === src);
    #|console.log("nested-eq?", dup.nested === src.nested);
    #|console.log(JSON.stringify(dup));
    #|
  run_differential(
    "corpus-rfdc",
    files,
    "entry.ts",
    extra_reserved_props=["a", "nested", "b", "c", "list"],
  )
}

// ---------------------------------------------------------------------------
// memoize — closure cache keyed on JSON.stringify
// ---------------------------------------------------------------------------

///|
async test "corpus: memoize caches results and skips repeat work" {
  let files : Map[String, String] = {}
  files["memo.ts"] =
    #|export function memoize<A extends any[], R>(fn: (...args: A) => R) {
    #|  const cache = new Map<string, R>();
    #|  let calls = 0;
    #|  const wrapped = (...args: A): R => {
    #|    const key = JSON.stringify(args);
    #|    const hit = cache.get(key);
    #|    if (hit !== undefined) return hit;
    #|    calls = calls + 1;
    #|    const value = fn(...args);
    #|    cache.set(key, value);
    #|    return value;
    #|  };
    #|  wrapped.callCount = () => calls;
    #|  return wrapped;
    #|}
    #|
  files["entry.ts"] =
    #|import { memoize } from "./memo";
    #|const square = memoize((n: number) => n * n);
    #|console.log(square(5));
    #|console.log(square(5));
    #|console.log(square(6));
    #|console.log(square(5));
    #|console.log("calls:", square.callCount());
    #|
  run_differential(
    "corpus-memoize",
    files,
    "entry.ts",
    extra_reserved_props=["callCount"],
  )
}

// ---------------------------------------------------------------------------
// once — function called only the first time
// ---------------------------------------------------------------------------

///|
async test "corpus: once wraps a function to fire at most once" {
  let files : Map[String, String] = {}
  files["once.ts"] =
    #|export function once<A extends any[], R>(fn: (...args: A) => R) {
    #|  let called = false;
    #|  let result: R;
    #|  return (...args: A): R => {
    #|    if (!called) {
    #|      called = true;
    #|      result = fn(...args);
    #|    }
    #|    return result;
    #|  };
    #|}
    #|
  files["entry.ts"] =
    #|import { once } from "./once";
    #|let counter = 0;
    #|const initOnce = once(() => {
    #|  counter = counter + 1;
    #|  return "result-" + counter;
    #|});
    #|console.log(initOnce());
    #|console.log(initOnce());
    #|console.log(initOnce());
    #|console.log("counter:", counter);
    #|
  run_differential("corpus-once", files, "entry.ts")
}

// ---------------------------------------------------------------------------
// pick / omit — object key filtering (heavy Object.keys use)
// ---------------------------------------------------------------------------

///|
async test "corpus: pick / omit produce expected subsets" {
  let files : Map[String, String] = {}
  files["filter.ts"] =
    #|export function pick<T extends object, K extends keyof T>(obj: T, keys: K[]): Pick<T, K> {
    #|  const out: any = {};
    #|  for (const k of keys) {
    #|    if (k in (obj as any)) out[k] = (obj as any)[k];
    #|  }
    #|  return out;
    #|}
    #|export function omit<T extends object, K extends keyof T>(obj: T, keys: K[]): Omit<T, K> {
    #|  const drop = new Set<string>(keys as any[]);
    #|  const out: any = {};
    #|  for (const k of Object.keys(obj as any)) {
    #|    if (!drop.has(k)) out[k] = (obj as any)[k];
    #|  }
    #|  return out;
    #|}
    #|
  files["entry.ts"] =
    #|import { pick, omit } from "./filter";
    #|const user = { id: 1, name: "alice", age: 30, email: "a@x" };
    #|console.log(JSON.stringify(pick(user, ["name", "age"])));
    #|console.log(JSON.stringify(omit(user, ["email"])));
    #|
  run_differential(
    "corpus-pick-omit",
    files,
    "entry.ts",
    // Every key of `user` is user-facing — both `Object.keys` and
    // `JSON.stringify` read them.
    extra_reserved_props=["id", "name", "age", "email"],
  )
}

// ---------------------------------------------------------------------------
// bytes-formatter — string conditionals, unit table
// ---------------------------------------------------------------------------

///|
async test "corpus: bytes-formatter produces human-readable sizes" {
  let files : Map[String, String] = {}
  files["bytes.ts"] =
    #|const UNITS = ["B", "KB", "MB", "GB", "TB"] as const;
    #|export function formatBytes(n: number, fractionDigits: number = 1): string {
    #|  if (n < 0) return "-" + formatBytes(-n, fractionDigits);
    #|  if (n < 1) return "0B";
    #|  let i = 0;
    #|  let v = n;
    #|  while (v >= 1024 && i < UNITS.length - 1) {
    #|    v = v / 1024;
    #|    i = i + 1;
    #|  }
    #|  return v.toFixed(fractionDigits) + UNITS[i];
    #|}
    #|
  files["entry.ts"] =
    #|import { formatBytes } from "./bytes";
    #|console.log(formatBytes(0));
    #|console.log(formatBytes(512));
    #|console.log(formatBytes(2048));
    #|console.log(formatBytes(1024 * 1024 * 3));
    #|console.log(formatBytes(-1500));
    #|
  run_differential("corpus-bytes", files, "entry.ts")
}

// ---------------------------------------------------------------------------
// tiny observable — `next` / `complete` / subscribe; pure-name patterns
// ---------------------------------------------------------------------------

///|
async test "corpus: tiny observable pushes values to subscribers" {
  let files : Map[String, String] = {}
  files["obs.ts"] =
    #|export type Observer<T> = { next: (v: T) => void; complete?: () => void };
    #|export function fromArray<T>(items: T[]) {
    #|  return {
    #|    subscribe(obs: Observer<T>) {
    #|      for (const it of items) obs.next(it);
    #|      if (obs.complete) obs.complete();
    #|    },
    #|  };
    #|}
    #|
  files["entry.ts"] =
    #|import { fromArray } from "./obs";
    #|const stream = fromArray([1, 2, 3, 4]);
    #|stream.subscribe({
    #|  next(v) { console.log("got:", v); },
    #|  complete() { console.log("done"); },
    #|});
    #|
  run_differential("corpus-observable", files, "entry.ts")
}

// ---------------------------------------------------------------------------
// invariant — small assertion helper that throws
// ---------------------------------------------------------------------------

///|
async test "corpus: invariant throws with formatted message" {
  let files : Map[String, String] = {}
  files["invariant.ts"] =
    #|export function invariant(cond: unknown, fmt: string, ...args: any[]): asserts cond {
    #|  if (cond) return;
    #|  let i = 0;
    #|  const msg = fmt.replace(/%s/g, () => String(args[i++]));
    #|  throw new Error("Invariant: " + msg);
    #|}
    #|
  files["entry.ts"] =
    #|import { invariant } from "./invariant";
    #|try {
    #|  invariant(true, "this %s pass", "should");
    #|  console.log("passed");
    #|  invariant(false, "expected %s but got %s", "X", "Y");
    #|  console.log("never");
    #|} catch (e: any) {
    #|  console.log("err:", e.message);
    #|}
    #|
  run_differential("corpus-invariant", files, "entry.ts")
}

// ---------------------------------------------------------------------------
// Edge-case patterns — these exercise corners of the language the
// optimizer historically gets wrong: async/await ordering, getters/
// setters on a class, destructuring with defaults, iterators, etc.
// ---------------------------------------------------------------------------

///|
async test "corpus: async/await preserves side-effect ordering through try/catch" {
  let files : Map[String, String] = {}
  files["entry.ts"] =
    #|async function chain(): Promise<void> {
    #|  const results: string[] = [];
    #|  const make = (label: string, ok: boolean) =>
    #|    new Promise<string>((resolve, reject) =>
    #|      ok ? resolve("ok:" + label) : reject(new Error("fail:" + label))
    #|    );
    #|  try {
    #|    results.push(await make("a", true));
    #|    results.push(await make("b", true));
    #|    results.push(await make("c", false));
    #|    results.push("never");
    #|  } catch (e: any) {
    #|    results.push("caught:" + e.message);
    #|  }
    #|  console.log(results.join("|"));
    #|}
    #|chain();
    #|
  run_differential("corpus-async-await", files, "entry.ts")
}

///|
async test "corpus: class getter / setter survives mangling" {
  let files : Map[String, String] = {}
  files["entry.ts"] =
    #|class Counter {
    #|  private _value: number = 0;
    #|  get value(): number { return this._value; }
    #|  set value(v: number) {
    #|    if (v < 0) throw new Error("negative");
    #|    this._value = v;
    #|  }
    #|}
    #|const c = new Counter();
    #|c.value = 5;
    #|console.log("value:", c.value);
    #|c.value = 10;
    #|console.log("value:", c.value);
    #|try {
    #|  c.value = -1;
    #|} catch (e: any) {
    #|  console.log("err:", e.message);
    #|}
    #|console.log("final:", c.value);
    #|
  run_differential("corpus-getter-setter", files, "entry.ts")
}

///|
async test "corpus: generator yields values via the iterator protocol" {
  let files : Map[String, String] = {}
  files["entry.ts"] =
    #|function* range(start: number, end: number, step: number = 1) {
    #|  for (let i = start; i < end; i = i + step) {
    #|    yield i;
    #|  }
    #|}
    #|const out: number[] = [];
    #|for (const v of range(1, 10, 2)) out.push(v);
    #|console.log(out.join(","));
    #|const gen = range(100, 105);
    #|console.log(gen.next().value);
    #|console.log(gen.next().value);
    #|console.log(gen.next().done);
    #|
  run_differential("corpus-generator", files, "entry.ts")
}

///|
async test "corpus: destructuring with defaults + rename" {
  let files : Map[String, String] = {}
  files["entry.ts"] =
    #|interface Opts { width?: number; height?: number; label?: string }
    #|function render({ width: w = 100, height: h = 50, label = "default" }: Opts = {}): string {
    #|  return "[" + label + " " + w + "x" + h + "]";
    #|}
    #|console.log(render());
    #|console.log(render({ width: 200, label: "wide" }));
    #|console.log(render({ height: 25 }));
    #|
  run_differential(
    "corpus-destructuring",
    files,
    "entry.ts",
    // The function's *call sites* pass these as keys, so the mangler
    // has to keep them. Renaming them would break the rendezvous
    // between caller and callee.
    extra_reserved_props=["width", "height", "label"],
  )
}

///|
async test "corpus: spread in calls + array merging" {
  let files : Map[String, String] = {}
  files["entry.ts"] =
    #|function sum(...nums: number[]): number {
    #|  let total = 0;
    #|  for (const n of nums) total = total + n;
    #|  return total;
    #|}
    #|const a = [1, 2, 3];
    #|const b = [4, 5];
    #|console.log("sum:", sum(...a, ...b, 6));
    #|const merged = [...a, 0, ...b];
    #|console.log("merged:", merged.join(","));
    #|console.log("merged-length:", merged.length);
    #|
  run_differential("corpus-spread", files, "entry.ts")
}

///|
async test "corpus: class inheritance with super calls" {
  let files : Map[String, String] = {}
  files["entry.ts"] =
    #|class Shape {
    #|  area(): number { return 0; }
    #|  describe(): string { return "shape area=" + this.area(); }
    #|}
    #|class Square extends Shape {
    #|  side: number;
    #|  constructor(side: number) { super(); this.side = side; }
    #|  area(): number { return this.side * this.side; }
    #|}
    #|const s = new Square(5);
    #|console.log(s.area());
    #|console.log(s.describe());
    #|
  run_differential(
    "corpus-inheritance",
    files,
    "entry.ts",
    extra_reserved_props=["side"],
  )
}

///|
async test "corpus: switch / case with fall-through and default" {
  let files : Map[String, String] = {}
  files["entry.ts"] =
    #|function classify(n: number): string {
    #|  switch (n) {
    #|    case 0: return "zero";
    #|    case 1:
    #|    case 2:
    #|    case 3: return "small";
    #|    case 10: return "ten";
    #|    default: return "other";
    #|  }
    #|}
    #|for (const n of [0, 1, 2, 3, 10, 99]) {
    #|  console.log(n + ":", classify(n));
    #|}
    #|
  run_differential("corpus-switch", files, "entry.ts")
}

///|
async test "corpus: tagged template literal forwards strings + interpolations" {
  let files : Map[String, String] = {}
  files["entry.ts"] =
    #|function tag(strings: TemplateStringsArray, ...values: any[]): string {
    #|  let out = "";
    #|  for (let i = 0; i < strings.length; i = i + 1) {
    #|    out = out + strings[i];
    #|    if (i < values.length) out = out + "<" + values[i] + ">";
    #|  }
    #|  return out;
    #|}
    #|const name = "world";
    #|const n = 42;
    #|console.log(tag`hello ${name}, the answer is ${n}!`);
    #|
  run_differential("corpus-tagged-template", files, "entry.ts")
}

///|
async test "corpus: map / set / weakmap-like iteration" {
  let files : Map[String, String] = {}
  files["entry.ts"] =
    #|const counts = new Map<string, number>();
    #|const words = ["a", "b", "a", "c", "b", "a"];
    #|for (const w of words) counts.set(w, (counts.get(w) ?? 0) + 1);
    #|const sortedKeys = Array.from(counts.keys()).sort();
    #|for (const k of sortedKeys) console.log(k + ":", counts.get(k));
    #|const seen = new Set<number>();
    #|for (const n of [1, 2, 2, 3, 1, 4]) seen.add(n);
    #|console.log("unique:", Array.from(seen).sort().join(","));
    #|
  run_differential("corpus-map-set", files, "entry.ts")
}
