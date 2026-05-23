// Real-library corpus — small but complete implementations of
// genuinely-shipped npm packages, slimmed down enough to fit in a
// single VFS but still exercising the package's actual public API.
// Each fixture uses the same differential harness: bundle baseline +
// full opt, run both with node, assert stdout matches.
//
// Sourced (and adapted) from:
//   - mitt          v3.0 (~28 lines)
//   - classnames    v2.x (~25 lines)
//   - dlv / dset    (~20 lines each)
//   - tiny-invariant (~6 lines)
//   - kleur-color   (~30 lines, ANSI escape codes)
//   - eventemitter3-tiny (~50 lines, subset)

// ---------------------------------------------------------------------------
// mitt — functional event emitter
// ---------------------------------------------------------------------------

///|
async test "real-lib: mitt — on / off / emit / all map" {
  let files : Map[String, String] = {}
  files["mitt.ts"] =
    #|export type Handler<T = any> = (event: T) => void;
    #|export type WildcardHandler<T extends Record<string, any>> = (type: keyof T, event: T[keyof T]) => void;
    #|export interface Emitter<E extends Record<string, any>> {
    #|  all: Map<keyof E | "*", any[]>;
    #|  on<K extends keyof E>(type: K, handler: Handler<E[K]>): void;
    #|  on(type: "*", handler: WildcardHandler<E>): void;
    #|  off<K extends keyof E>(type: K, handler?: Handler<E[K]>): void;
    #|  off(type: "*", handler?: WildcardHandler<E>): void;
    #|  emit<K extends keyof E>(type: K, event?: E[K]): void;
    #|  emit(type: "*", event?: any): void;
    #|}
    #|export default function mitt<E extends Record<string, any>>(all?: Map<any, any[]>): Emitter<E> {
    #|  all = all || new Map();
    #|  return {
    #|    all,
    #|    on(type, handler) {
    #|      const handlers = all!.get(type);
    #|      if (handlers) handlers.push(handler);
    #|      else all!.set(type, [handler]);
    #|    },
    #|    off(type, handler) {
    #|      const handlers = all!.get(type);
    #|      if (!handlers) return;
    #|      if (handler) {
    #|        const idx = handlers.indexOf(handler);
    #|        if (idx >= 0) handlers.splice(idx, 1);
    #|      } else {
    #|        all!.set(type, []);
    #|      }
    #|    },
    #|    emit(type, evt) {
    #|      const handlers = all!.get(type);
    #|      if (handlers) (handlers.slice() as any[]).map((h) => h(evt));
    #|      const star = all!.get("*");
    #|      if (star) (star.slice() as any[]).map((h) => h(type, evt));
    #|    },
    #|  } as Emitter<E>;
    #|}
    #|
  files["entry.ts"] =
    #|import mitt from "./mitt";
    #|type Events = { ping: { value: number }; pong: string };
    #|const bus = mitt<Events>();
    #|const trace: string[] = [];
    #|bus.on("ping", (p) => trace.push("ping:" + p.value));
    #|bus.on("pong", (p) => trace.push("pong:" + p));
    #|bus.on("*", (type, evt) => trace.push("*:" + String(type)));
    #|bus.emit("ping", { value: 1 });
    #|bus.emit("pong", "hi");
    #|bus.emit("ping", { value: 2 });
    #|console.log(trace.join(" | "));
    #|console.log("listeners:", bus.all.size);
    #|
  run_differential(
    "real-mitt",
    files,
    "entry.ts",
    extra_reserved_props=["value", "all"],
  )
}

// ---------------------------------------------------------------------------
// classnames — class name composer
// ---------------------------------------------------------------------------

///|
async test "real-lib: classnames — strings, objects, arrays, falsy" {
  let files : Map[String, String] = {}
  files["classnames.ts"] =
    #|export default function classNames(...args: any[]): string {
    #|  const classes: string[] = [];
    #|  for (const arg of args) {
    #|    if (!arg) continue;
    #|    const argType = typeof arg;
    #|    if (argType === "string" || argType === "number") {
    #|      classes.push(String(arg));
    #|    } else if (Array.isArray(arg)) {
    #|      if (arg.length > 0) {
    #|        const inner = classNames.apply(null, arg as any);
    #|        if (inner) classes.push(inner);
    #|      }
    #|    } else if (argType === "object") {
    #|      for (const key of Object.keys(arg)) {
    #|        if (arg[key]) classes.push(key);
    #|      }
    #|    }
    #|  }
    #|  return classes.join(" ");
    #|}
    #|
  files["entry.ts"] =
    #|import cn from "./classnames";
    #|console.log(cn("foo", "bar"));
    #|console.log(cn("base", { active: true, disabled: false }));
    #|console.log(cn(["nested-a", "nested-b"], "trail"));
    #|console.log(cn(0, null, undefined, "", "kept", { x: 1, y: 0 }));
    #|console.log(cn("a", false && "b", "c", true && "d"));
    #|
  run_differential(
    "real-classnames",
    files,
    "entry.ts",
    extra_reserved_props=["active", "disabled", "x", "y"],
  )
}

// ---------------------------------------------------------------------------
// dlv — safe deep property access
// ---------------------------------------------------------------------------

///|
async test "real-lib: dlv — safe deep get with dotted path" {
  let files : Map[String, String] = {}
  files["dlv.ts"] =
    #|export default function dlv(obj: any, key: string | string[], def?: any): any {
    #|  let p = 0;
    #|  const path = (typeof key === "string" ? key.split(".") : key) as string[];
    #|  const len = path.length;
    #|  while (obj && p < len) obj = obj[path[p++]];
    #|  return obj === undefined || p < len ? def : obj;
    #|}
    #|
  files["entry.ts"] =
    #|import dlv from "./dlv";
    #|const data = {
    #|  user: { profile: { name: "alice", age: 30 } },
    #|  empty: null,
    #|  list: [1, 2, 3],
    #|};
    #|console.log("name:", dlv(data, "user.profile.name"));
    #|console.log("age:", dlv(data, "user.profile.age"));
    #|console.log("missing:", dlv(data, "user.profile.email", "n/a"));
    #|console.log("through-null:", dlv(data, "empty.foo", "default"));
    #|console.log("via-array:", dlv(data, ["user", "profile", "name"]));
    #|console.log("list-idx:", dlv(data, "list.1"));
    #|
  run_differential(
    "real-dlv",
    files,
    "entry.ts",
    extra_reserved_props=["user", "profile", "name", "age", "empty", "list"],
  )
}

// ---------------------------------------------------------------------------
// tiny-invariant
// ---------------------------------------------------------------------------

///|
async test "real-lib: tiny-invariant — throws / passes" {
  let files : Map[String, String] = {}
  files["invariant.ts"] =
    #|const prefix = "Invariant failed";
    #|export default function invariant(condition: any, message?: string | (() => string)): asserts condition {
    #|  if (condition) return;
    #|  const provided = typeof message === "function" ? message() : message;
    #|  throw new Error(provided ? prefix + ": " + provided : prefix);
    #|}
    #|
  files["entry.ts"] =
    #|import invariant from "./invariant";
    #|const log: string[] = [];
    #|try {
    #|  invariant(true, "passes");
    #|  log.push("p:ok");
    #|  invariant(1 > 0, () => "lazy-" + Date.now().toString().slice(0, 1));
    #|  log.push("p:ok2");
    #|  invariant(false, "bad value");
    #|  log.push("p:never");
    #|} catch (e: any) {
    #|  log.push("c:" + e.message);
    #|}
    #|try {
    #|  invariant(false);
    #|} catch (e: any) {
    #|  log.push("c-empty:" + e.message);
    #|}
    #|console.log(log.join("|"));
    #|
  run_differential("real-tiny-invariant", files, "entry.ts")
}

// ---------------------------------------------------------------------------
// kleur-color — ANSI escape coloring (subset)
// ---------------------------------------------------------------------------

///|
async test "real-lib: kleur — ANSI color codes via chain" {
  let files : Map[String, String] = {}
  files["kleur.ts"] =
    #|type Wrapper = (s: string | number) => string;
    #|function wrap(open: number, close: number): Wrapper {
    #|  return (s: string | number) => "\x1b[" + open + "m" + s + "\x1b[" + close + "m";
    #|}
    #|export const red = wrap(31, 39);
    #|export const green = wrap(32, 39);
    #|export const yellow = wrap(33, 39);
    #|export const blue = wrap(34, 39);
    #|export const bold = wrap(1, 22);
    #|export const dim = wrap(2, 22);
    #|
  files["entry.ts"] =
    #|import { red, green, bold, dim } from "./kleur";
    #|console.log(red("error"));
    #|console.log(green("ok"));
    #|console.log(bold(red("BAD")));
    #|console.log(dim("- subtle"));
    #|
  run_differential("real-kleur", files, "entry.ts")
}

// ---------------------------------------------------------------------------
// eventemitter3-tiny — slimmer version of Node EE
// ---------------------------------------------------------------------------

///|
async test "real-lib: eventemitter3-tiny — listeners, removeListener" {
  let files : Map[String, String] = {}
  files["ee.ts"] =
    #|export class EventEmitter {
    #|  private _events: { [key: string]: Function[] } = {};
    #|  on(event: string, listener: Function): this {
    #|    if (!this._events[event]) this._events[event] = [];
    #|    this._events[event].push(listener);
    #|    return this;
    #|  }
    #|  off(event: string, listener: Function): this {
    #|    if (!this._events[event]) return this;
    #|    const idx = this._events[event].indexOf(listener);
    #|    if (idx >= 0) this._events[event].splice(idx, 1);
    #|    return this;
    #|  }
    #|  emit(event: string, ...args: any[]): boolean {
    #|    const list = this._events[event];
    #|    if (!list || list.length === 0) return false;
    #|    for (const fn of list.slice()) fn.apply(null, args);
    #|    return true;
    #|  }
    #|  listeners(event: string): Function[] {
    #|    return this._events[event] ? this._events[event].slice() : [];
    #|  }
    #|}
    #|
  files["entry.ts"] =
    #|import { EventEmitter } from "./ee";
    #|const ee = new EventEmitter();
    #|const trace: string[] = [];
    #|const a = (x: number) => trace.push("a:" + x);
    #|const b = (x: number) => trace.push("b:" + x);
    #|ee.on("tick", a);
    #|ee.on("tick", b);
    #|ee.emit("tick", 1);
    #|ee.off("tick", a);
    #|ee.emit("tick", 2);
    #|console.log(trace.join("|"));
    #|console.log("remaining:", ee.listeners("tick").length);
    #|console.log("no-listener:", ee.emit("never"));
    #|
  run_differential(
    "real-eventemitter",
    files,
    "entry.ts",
    extra_reserved_props=["_events"],
  )
}

// ---------------------------------------------------------------------------
// nanoid (deterministic) — non-secure variant
// ---------------------------------------------------------------------------

///|
async test "real-lib: nanoid-deterministic — custom alphabet + counter" {
  let files : Map[String, String] = {}
  files["nanoid.ts"] =
    #|const URL_ALPHABET = "ModuleSymbhasOwnPr-0123456789ABCDEFGHIJKLMNQRTUVWXYZ_cfgijkpqtvxz";
    #|export function customAlphabet(alphabet: string, defaultSize: number = 21) {
    #|  let counter = 0;
    #|  return (size: number = defaultSize): string => {
    #|    let id = "";
    #|    for (let i = 0; i < size; i = i + 1) {
    #|      id = id + alphabet[counter % alphabet.length];
    #|      counter = counter + 1;
    #|    }
    #|    return id;
    #|  };
    #|}
    #|export const nanoid = customAlphabet(URL_ALPHABET);
    #|
  files["entry.ts"] =
    #|import { nanoid, customAlphabet } from "./nanoid";
    #|console.log(nanoid(8));
    #|console.log(nanoid(8));
    #|const hex = customAlphabet("0123456789abcdef", 4);
    #|console.log(hex());
    #|console.log(hex(6));
    #|
  run_differential("real-nanoid", files, "entry.ts")
}

// ---------------------------------------------------------------------------
// just-debounce-it (synchronous flush variant)
// ---------------------------------------------------------------------------

///|
async test "real-lib: debounce — flush + cancel API" {
  let files : Map[String, String] = {}
  files["debounce.ts"] =
    #|export default function debounce<A extends any[]>(fn: (...args: A) => void, wait: number) {
    #|  let pendingArgs: A | null = null;
    #|  const wrapped = (...args: A) => {
    #|    pendingArgs = args;
    #|  };
    #|  wrapped.flush = () => {
    #|    if (pendingArgs !== null) {
    #|      fn(...(pendingArgs as A));
    #|      pendingArgs = null;
    #|    }
    #|  };
    #|  wrapped.cancel = () => {
    #|    pendingArgs = null;
    #|  };
    #|  wrapped.pending = () => pendingArgs !== null;
    #|  return wrapped;
    #|}
    #|
  files["entry.ts"] =
    #|import debounce from "./debounce";
    #|let n = 0;
    #|const inc = debounce((by: number) => { n = n + by; }, 100);
    #|inc(5);
    #|inc(10);
    #|inc(20);
    #|console.log("pending?", inc.pending());
    #|inc.flush();
    #|console.log("n:", n);
    #|console.log("pending-after?", inc.pending());
    #|inc(99);
    #|inc.cancel();
    #|console.log("n-after-cancel:", n);
    #|
  run_differential(
    "real-debounce",
    files,
    "entry.ts",
    extra_reserved_props=["flush", "cancel", "pending"],
  )
}
