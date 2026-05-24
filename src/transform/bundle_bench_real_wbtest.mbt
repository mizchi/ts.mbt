// Realistic bundle benchmarks — combines the corpus libraries into
// kitchen-sink fixtures and stresses scaling at larger module
// counts. Run with `moon bench --target native -p mizchi/ts/transform`.

// ---------------------------------------------------------------------------
// Kitchen-sink fixture — a mid-size "application" that imports
// several library-shaped modules (event bus, classnames, deep
// lookup, debounce, invariant, color codes, ID generator) and
// exercises each on the entry path. This is roughly what a real
// small-to-medium app's bundle looks like.
// ---------------------------------------------------------------------------

///|
fn realistic_kitchen_sink() -> Map[String, String] {
  let files : Map[String, String] = {}
  // mitt — event emitter
  files["lib/mitt.ts"] =
    #|export type Handler<T = any> = (event: T) => void;
    #|export default function mitt<E extends Record<string, any>>() {
    #|  const all = new Map<keyof E | "*", Handler[]>();
    #|  return {
    #|    all,
    #|    on(type: any, h: any) {
    #|      const list = all.get(type);
    #|      if (list) list.push(h); else all.set(type, [h]);
    #|    },
    #|    off(type: any, h: any) {
    #|      const list = all.get(type);
    #|      if (!list) return;
    #|      const i = list.indexOf(h);
    #|      if (i >= 0) list.splice(i, 1);
    #|    },
    #|    emit(type: any, ev: any) {
    #|      const list = all.get(type);
    #|      if (list) (list.slice() as any[]).map((h) => h(ev));
    #|    },
    #|  };
    #|}
    #|
  files["lib/classnames.ts"] =
    #|export default function cn(...args: any[]): string {
    #|  const out: string[] = [];
    #|  for (const a of args) {
    #|    if (!a) continue;
    #|    if (typeof a === "string") out.push(a);
    #|    else if (Array.isArray(a)) {
    #|      const inner = cn.apply(null, a as any);
    #|      if (inner) out.push(inner);
    #|    } else if (typeof a === "object") {
    #|      for (const k of Object.keys(a)) if (a[k]) out.push(k);
    #|    }
    #|  }
    #|  return out.join(" ");
    #|}
    #|
  files["lib/dlv.ts"] =
    #|export default function dlv(obj: any, key: string | string[], def?: any): any {
    #|  let p = 0;
    #|  const path = typeof key === "string" ? key.split(".") : key;
    #|  while (obj && p < path.length) obj = obj[path[p++]];
    #|  return obj === undefined || p < path.length ? def : obj;
    #|}
    #|
  files["lib/debounce.ts"] =
    #|export default function debounce<A extends any[]>(fn: (...a: A) => void) {
    #|  let pending: A | null = null;
    #|  const w = (...args: A) => { pending = args; };
    #|  w.flush = () => { if (pending) { fn(...pending); pending = null; } };
    #|  w.cancel = () => { pending = null; };
    #|  w.pending = () => pending !== null;
    #|  return w;
    #|}
    #|
  files["lib/invariant.ts"] =
    #|export default function invariant(c: any, msg?: string): asserts c {
    #|  if (c) return;
    #|  throw new Error(msg ? "Invariant: " + msg : "Invariant failed");
    #|}
    #|
  files["lib/kleur.ts"] =
    #|function w(o: number, c: number) {
    #|  return (s: string | number) => "\x1b[" + o + "m" + s + "\x1b[" + c + "m";
    #|}
    #|export const red = w(31, 39);
    #|export const green = w(32, 39);
    #|export const yellow = w(33, 39);
    #|export const blue = w(34, 39);
    #|export const bold = w(1, 22);
    #|
  files["lib/id.ts"] =
    #|const ALPHABET = "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ";
    #|export function createIdGen(size: number = 12) {
    #|  let counter = 0;
    #|  return (): string => {
    #|    let id = "";
    #|    for (let i = 0; i < size; i = i + 1) {
    #|      id = id + ALPHABET[counter % ALPHABET.length];
    #|      counter = counter + 1;
    #|    }
    #|    return id;
    #|  };
    #|}
    #|
  files["lib/state.ts"] =
    #|export type Action = { type: string; payload?: any };
    #|export function createStore<S>(reducer: (s: S, a: Action) => S, init: S) {
    #|  let state = init;
    #|  const listeners: Array<() => void> = [];
    #|  return {
    #|    getState() { return state; },
    #|    dispatch(a: Action) {
    #|      state = reducer(state, a);
    #|      for (const l of listeners) l();
    #|    },
    #|    subscribe(fn: () => void) {
    #|      listeners.push(fn);
    #|      return () => {
    #|        const i = listeners.indexOf(fn);
    #|        if (i >= 0) listeners.splice(i, 1);
    #|      };
    #|    },
    #|  };
    #|}
    #|
  files["lib/index.ts"] =
    #|export { default as mitt } from "./mitt";
    #|export { default as cn } from "./classnames";
    #|export { default as dlv } from "./dlv";
    #|export { default as debounce } from "./debounce";
    #|export { default as invariant } from "./invariant";
    #|export * as kleur from "./kleur";
    #|export { createIdGen } from "./id";
    #|export { createStore, type Action } from "./state";
    #|
  files["app/config.ts"] =
    #|export const CONFIG = {
    #|  mode: "production" as const,
    #|  retries: 3,
    #|  baseURL: "https://api.example.com",
    #|  timeouts: { connect: 5000, read: 30000 },
    #|  features: { logging: true, analytics: false, debug: false },
    #|};
    #|export const KNOWN_EVENTS = ["start", "stop", "error", "tick"] as const;
    #|
  files["app/logger.ts"] =
    #|import { kleur, debounce } from "../lib/index";
    #|export function makeLogger() {
    #|  const flush = debounce((line: string) => console.log(line));
    #|  return {
    #|    info: (m: string) => flush(kleur.green("[i] " + m)),
    #|    warn: (m: string) => flush(kleur.yellow("[w] " + m)),
    #|    error: (m: string) => flush(kleur.red("[e] " + m)),
    #|  };
    #|}
    #|
  files["app/main.ts"] =
    #|import { mitt, createStore, createIdGen, invariant, cn } from "../lib/index";
    #|import { CONFIG, KNOWN_EVENTS } from "./config";
    #|import { makeLogger } from "./logger";
    #|type Events = { start: { id: string }; stop: { code: number }; tick: number };
    #|const bus = mitt<Events>();
    #|const log = makeLogger();
    #|const idGen = createIdGen(8);
    #|const store = createStore<{ count: number; running: boolean }>(
    #|  (s, a) => {
    #|    if (a.type === "inc") return { ...s, count: s.count + 1 };
    #|    if (a.type === "toggle") return { ...s, running: !s.running };
    #|    return s;
    #|  },
    #|  { count: 0, running: false },
    #|);
    #|bus.on("start", (e) => log.info("start id=" + e.id));
    #|bus.on("tick", (n) => store.dispatch({ type: "inc" }));
    #|invariant(CONFIG.retries > 0, "retries must be positive");
    #|for (let i = 0; i < 5; i = i + 1) {
    #|  bus.emit("start", { id: idGen() });
    #|  bus.emit("tick", i);
    #|}
    #|const css = cn("app", { active: store.getState().running }, ["theme-" + CONFIG.mode]);
    #|log.info("css:" + css);
    #|log.info("count:" + store.getState().count);
    #|
  files
}

///|
test "bench bundle: realistic kitchen-sink (10 modules, no opts)" (
  it : @bench.T,
) {
  let files = realistic_kitchen_sink()
  it.bench(fn() {
    let out = match bundle_modules(files, "app/main.ts", BundleOptions::default()) {
      Ok(o) => o
      Err(_) => return
    }
    it.keep(out.js.length())
  })
}

///|
test "bench bundle: realistic kitchen-sink + tree-shake" (
  it : @bench.T,
) {
  let files = realistic_kitchen_sink()
  let opts = { ..BundleOptions::default(), tree_shake: true }
  it.bench(fn() {
    let out = match bundle_modules(files, "app/main.ts", opts) {
      Ok(o) => o
      Err(_) => return
    }
    it.keep(out.js.length())
  })
}

///|
test "bench bundle: realistic kitchen-sink + full opt" (it : @bench.T) {
  let files = realistic_kitchen_sink()
  let opts = full_opt_bundle_options()
  it.bench(fn() {
    let out = match bundle_modules(files, "app/main.ts", opts) {
      Ok(o) => o
      Err(_) => return
    }
    it.keep(out.js.length())
  })
}

// ---------------------------------------------------------------------------
// Scaling stress — repeat the base template up to N modules and
// see how the bundler scales. Each module gets distinct names so
// the collision resolver, name mangler, and tree-shake roots
// computation all have non-trivial work.
// ---------------------------------------------------------------------------

///|
fn realistic_scaling_fixture(n : Int) -> Map[String, String] {
  let files : Map[String, String] = {}
  for i in 0..<n {
    let s = i.to_string()
    files["lib/m_" + s + ".ts"] =
      "interface Cfg" +
      s +
      " { mode: string; retries: number; }\n" +
      "const cfg" +
      s +
      ": Cfg" +
      s +
      " = { mode: \"prod\", retries: " +
      s +
      " };\n" +
      "function helper" +
      s +
      "(x: number): number { return x + cfg" +
      s +
      ".retries; }\n" +
      "export function compute" +
      s +
      "(x: number): number {\n" +
      "  let n = x;\n" +
      "  for (let i = 0; i < 3; i = i + 1) n = helper" +
      s +
      "(n);\n" +
      "  return n + cfg" +
      s +
      ".retries;\n" +
      "}\n" +
      "export const VERSION" +
      s +
      ": string = \"1.0." +
      s +
      "\";\n"
  }
  // Aggregator that re-exports everything.
  let agg_lines : Array[String] = []
  for i in 0..<n {
    agg_lines.push(
      "export { compute" +
      i.to_string() +
      ", VERSION" +
      i.to_string() +
      " } from \"./m_" +
      i.to_string() +
      "\";",
    )
  }
  files["lib/all.ts"] = agg_lines.join("\n") + "\n"
  // Entry uses roughly 1/3 of the modules so tree-shake has
  // something to drop.
  let used = if n / 3 < 1 { 1 } else { n / 3 }
  let imports : Array[String] = []
  let usage : Array[String] = []
  for i in 0..<used {
    let s = i.to_string()
    imports.push("import { compute" + s + ", VERSION" + s + " } from \"./lib/all\";")
    usage.push("console.log(\"v\" + " + s + " + \":\" + compute" + s + "(" + s + "), VERSION" + s + ");")
  }
  files["entry.ts"] = (imports.join("\n") + "\n" + usage.join("\n")) + "\n"
  files
}

///|
test "bench bundle: realistic 25-module scaling + full opt" (it : @bench.T) {
  let files = realistic_scaling_fixture(25)
  let opts = full_opt_bundle_options()
  it.bench(fn() {
    let out = match bundle_modules(files, "entry.ts", opts) {
      Ok(o) => o
      Err(_) => return
    }
    it.keep(out.js.length())
  })
}

///|
test "bench bundle: realistic 100-module scaling + full opt" (it : @bench.T) {
  let files = realistic_scaling_fixture(100)
  let opts = full_opt_bundle_options()
  it.bench(fn() {
    let out = match bundle_modules(files, "entry.ts", opts) {
      Ok(o) => o
      Err(_) => return
    }
    it.keep(out.js.length())
  })
}

///|
test "bench bundle: realistic 500-module scaling + full opt" (it : @bench.T) {
  let files = realistic_scaling_fixture(500)
  let opts = full_opt_bundle_options()
  it.bench(fn() {
    let out = match bundle_modules(files, "entry.ts", opts) {
      Ok(o) => o
      Err(_) => return
    }
    it.keep(out.js.length())
  })
}

// ---------------------------------------------------------------------------
// Differential parity check — running the realistic kitchen-sink
// through the regular runner once also serves as a correctness
// sanity check (baseline vs. opt under node). Keeps the bench
// honest: a bundle that's fast but wrong isn't interesting.
// ---------------------------------------------------------------------------

///|
async test "bench fixture: realistic kitchen-sink stays correct under full opt" {
  let files = realistic_kitchen_sink()
  run_differential(
    "bench-kitchen-sink",
    files,
    "app/main.ts",
    // Cross-module / external-name keys the optimizer can't see.
    extra_reserved_props=[
      "all", "type", "payload", "count", "running", "mode",
      "retries", "baseURL", "timeouts", "connect", "read",
      "features", "logging", "analytics", "debug", "active",
      "flush", "cancel", "pending", "info", "warn", "error", "id",
    ],
  )
}
