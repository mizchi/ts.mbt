// Bundle throughput benchmarks — run with
// `moon bench --target native -p mizchi/ts/transform`.
//
// Each `test` here uses the `(it : @bench.T)` signature so the
// benchmarking harness times only the body of `it.bench(fn() { ... })`.
// We build the fixture VFS once outside the timed body.

///|
fn bench_fixture_event_bus() -> Map[String, String] {
  let files : Map[String, String] = {}
  files["types.ts"] =
    #|export interface EventHandler<T> { (payload: T): void }
    #|export interface EmitterConfig {
    #|  maxListeners: number;
    #|  captureRejections: boolean;
    #|  errorHandler: (error: Error) => void;
    #|}
    #|export interface Emitter<T> {
    #|  on(event: string, handler: EventHandler<T>): void;
    #|  off(event: string, handler: EventHandler<T>): void;
    #|  emit(event: string, payload: T): void;
    #|  listenerCount(event: string): number;
    #|}
    #|
  files["utils.ts"] =
    #|const limits = { minListeners: 1, maxListeners: 1000, defaultListeners: 10 };
    #|const env = { mode: "production", build: { verbose: false, version: "1.0.0" } };
    #|export function clampMaxListeners(requested: number): number {
    #|  if (requested < limits.minListeners) return limits.minListeners;
    #|  if (requested > limits.maxListeners) return limits.maxListeners;
    #|  return requested;
    #|}
    #|export function logEvents(events: ReadonlyArray<string>): void {
    #|  for (const e of events) console.log(e);
    #|}
    #|export function defaultErrorHandler(error: Error): void {
    #|  if (env.mode === "development") {
    #|    console.error("[emitter:dev]", error.message, error.stack);
    #|  }
    #|  if (env.build.verbose) {
    #|    console.error("[emitter:verbose:" + env.build.version + "]", error);
    #|  }
    #|  console.error("[emitter]", error.message);
    #|}
    #|export const internalUnusedHelper = (x: number) => x * 9999;
    #|export const anotherUnusedConst = "never-referenced-anywhere";
    #|
  files["emitter.ts"] =
    #|import { EventHandler, EmitterConfig, Emitter } from "./types";
    #|import { clampMaxListeners, defaultErrorHandler } from "./utils";
    #|export class TypedEmitter<T> {
    #|  private listenerMap: Record<string, EventHandler<T>[]> = {};
    #|  private maxListeners: number;
    #|  private errorHandler: (error: Error) => void;
    #|  constructor(config: Partial<EmitterConfig> = {}) {
    #|    this.maxListeners = clampMaxListeners(config.maxListeners ?? 10);
    #|    this.errorHandler = config.errorHandler ?? defaultErrorHandler;
    #|  }
    #|  on(event: string, handler: EventHandler<T>): void {
    #|    const list = this.listenerMap[event] ?? [];
    #|    if (list.length >= this.maxListeners) {
    #|      this.errorHandler(new Error("too many listeners"));
    #|      return;
    #|    }
    #|    list.push(handler);
    #|    this.listenerMap[event] = list;
    #|  }
    #|  off(event: string, handler: EventHandler<T>): void {
    #|    const list = this.listenerMap[event];
    #|    if (!list) return;
    #|    this.listenerMap[event] = list.filter(h => h !== handler);
    #|  }
    #|  emit(event: string, payload: T): void {
    #|    const list = this.listenerMap[event];
    #|    if (!list) return;
    #|    for (const h of list) h(payload);
    #|  }
    #|  listenerCount(event: string): number { return 0; }
    #|  removeAllListeners(): void { this.listenerMap = {}; }
    #|  eventNames(): string[] { return Object.keys(this.listenerMap); }
    #|  rawHandlers(event: string): EventHandler<T>[] {
    #|    return this.listenerMap[event] ?? [];
    #|  }
    #|}
    #|
  files["entry.ts"] =
    #|import { TypedEmitter } from "./emitter";
    #|const KNOWN_EVENTS = ["tick", "tock", "boom"] as const;
    #|export const bus = new TypedEmitter<{ value: number }>({ maxListeners: 5 });
    #|bus.on(KNOWN_EVENTS[0], (payload) => {
    #|  console.log("got", KNOWN_EVENTS[0], payload.value);
    #|});
    #|bus.emit(KNOWN_EVENTS[0], { value: 42 });
    #|
  files
}

///|
fn full_opt_bundle_options() -> BundleOptions {
  {
    ..BundleOptions::default(),
    tree_shake: true,
    mangle: Some(ManglerConfig::default().with_mangle_properties(true)),
    auto_reserve: true,
    drop_unused_methods: true,
    inline_immutable: true,
    fold_constants: true,
  }
}

///|
test "bench bundle: 4-module event-bus baseline (no opts)" (it : @bench.T) {
  let files = bench_fixture_event_bus()
  it.bench(fn() {
    let out = match bundle_modules(files, "entry.ts", BundleOptions::default()) {
      Ok(o) => o
      Err(_) => return
    }
    it.keep(out.js.length())
  })
}

///|
test "bench bundle: 4-module event-bus tree-shake only" (it : @bench.T) {
  let files = bench_fixture_event_bus()
  let opts = { ..BundleOptions::default(), tree_shake: true }
  it.bench(fn() {
    let out = match bundle_modules(files, "entry.ts", opts) {
      Ok(o) => o
      Err(_) => return
    }
    it.keep(out.js.length())
  })
}

///|
test "bench bundle: 4-module event-bus identifier mangle only" (it : @bench.T) {
  let files = bench_fixture_event_bus()
  let opts = {
    ..BundleOptions::default(),
    tree_shake: true,
    mangle: Some(ManglerConfig::default()),
  }
  it.bench(fn() {
    let out = match bundle_modules(files, "entry.ts", opts) {
      Ok(o) => o
      Err(_) => return
    }
    it.keep(out.js.length())
  })
}

///|
test "bench bundle: 4-module event-bus property mangle" (it : @bench.T) {
  let files = bench_fixture_event_bus()
  let opts = {
    ..BundleOptions::default(),
    tree_shake: true,
    mangle: Some(ManglerConfig::default().with_mangle_properties(true)),
  }
  it.bench(fn() {
    let out = match bundle_modules(files, "entry.ts", opts) {
      Ok(o) => o
      Err(_) => return
    }
    it.keep(out.js.length())
  })
}

///|
test "bench bundle: 4-module event-bus full opt (all passes)" (
  it : @bench.T,
) {
  let files = bench_fixture_event_bus()
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
// Larger synthetic input — repeat the event-bus modules N times so
// the bundler has more work and the per-op cost becomes visible.
// ---------------------------------------------------------------------------

///|
fn bench_fixture_repeated(n : Int) -> Map[String, String] {
  let files : Map[String, String] = {}
  for i in 0..<n {
    let suffix = "_" + i.to_string()
    files["lib" + suffix + ".ts"] =
      "interface Cfg" +
      suffix +
      " { mode: string; n: number; }\n" +
      "export const cfg" +
      suffix +
      ": Cfg" +
      suffix +
      " = { mode: \"prod\", n: " +
      i.to_string() +
      " };\n" +
      "export function fetch" +
      suffix +
      "(x: number): number { return x + cfg" +
      suffix +
      ".n; }\n"
  }
  let lines : Array[String] = []
  for i in 0..<n {
    lines.push(
      "import { fetch_" +
      i.to_string() +
      " } from \"./lib_" +
      i.to_string() +
      "\";",
    )
  }
  for i in 0..<n {
    lines.push(
      "console.log(fetch_" + i.to_string() + "(" + i.to_string() + "));",
    )
  }
  files["entry.ts"] = lines.join("\n") + "\n"
  files
}

///|
test "bench bundle: 10x event-bus modules + full opt" (it : @bench.T) {
  let files = bench_fixture_repeated(10)
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
test "bench bundle: 50x event-bus modules + full opt" (it : @bench.T) {
  let files = bench_fixture_repeated(50)
  let opts = full_opt_bundle_options()
  it.bench(fn() {
    let out = match bundle_modules(files, "entry.ts", opts) {
      Ok(o) => o
      Err(_) => return
    }
    it.keep(out.js.length())
  })
}
