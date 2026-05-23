// Size-sweep "benchmark" — runs the same multi-file TS bundle
// through the pipeline at increasing optimization levels and
// prints the byte deltas. Each stage layers on top of the previous
// one so the cumulative reduction is visible at a glance.
//
// This is a `test`, not a `@bench.T` benchmark — the value here is
// the printed table, not throughput. The assertions exist so a
// regression that bloats output instead of shrinking it shows up
// as a test failure rather than a silently-worse number.
//
// Run with:  moon test --target native -p mizchi/ts/transform
//            (find the "size sweep" test in the output).

///|
fn fixture_files() -> Map[String, String] {
  // A small multi-module fixture modeled after a typical event-bus
  // library. Long property / function names give the mangler something
  // to chew on; an inline `Config` type drives the auto-reserve walk.
  let files : Map[String, String] = {}
  files["types.ts"] =
    #|export interface EventHandler<T> {
    #|  (payload: T): void;
    #|}
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
fn measure(files : Map[String, String], opts : BundleOptions) -> Int {
  match bundle_modules(files, "entry.ts", opts) {
    Ok(out) => out.js.length()
    Err(_) => -1
  }
}

///|
fn raw_byte_count(files : Map[String, String]) -> Int {
  let mut n = 0
  for kv in files {
    n = n + kv.1.length()
  }
  n
}

///|
fn pct(base : Int, current : Int) -> String {
  if base == 0 {
    return "n/a"
  }
  let saved = base - current
  let abs_saved = if saved < 0 { -saved } else { saved }
  let p = abs_saved * 1000 / base
  let whole = p / 10
  let frac = p % 10
  let sign = if saved < 0 { "+" } else { "-" }
  sign + whole.to_string() + "." + frac.to_string() + "%"
}

///|
test "size sweep: pipeline reductions on a 4-module event-bus fixture" {
  let files = fixture_files()
  let raw = raw_byte_count(files)
  let bundled = measure(files, BundleOptions::default())
  let shaken = measure(files, {
    ..BundleOptions::default(),
    tree_shake: true,
  })
  let shaken_id_mangle = measure(files, {
    ..BundleOptions::default(),
    tree_shake: true,
    mangle: Some(ManglerConfig::default()),
  })
  let shaken_full_mangle = measure(files, {
    ..BundleOptions::default(),
    tree_shake: true,
    mangle: Some(ManglerConfig::default().with_mangle_properties(true)),
  })
  let shaken_auto_reserved = measure(files, {
    ..BundleOptions::default(),
    tree_shake: true,
    mangle: Some(ManglerConfig::default().with_mangle_properties(true)),
    auto_reserve: true,
  })
  let shaken_methods_dced = measure(files, {
    ..BundleOptions::default(),
    tree_shake: true,
    mangle: Some(ManglerConfig::default().with_mangle_properties(true)),
    auto_reserve: true,
    drop_unused_methods: true,
  })
  let shaken_inline_immutable = measure(files, {
    ..BundleOptions::default(),
    tree_shake: true,
    mangle: Some(ManglerConfig::default().with_mangle_properties(true)),
    auto_reserve: true,
    drop_unused_methods: true,
    inline_immutable: true,
  })
  let shaken_folded = measure(files, {
    ..BundleOptions::default(),
    tree_shake: true,
    mangle: Some(ManglerConfig::default().with_mangle_properties(true)),
    auto_reserve: true,
    drop_unused_methods: true,
    inline_immutable: true,
    fold_constants: true,
  })
  println("")
  println("┌──────────────────────────────────────────────┬─────────┬────────────┐")
  println("│ stage                                        │   bytes │  vs. raw   │")
  println("├──────────────────────────────────────────────┼─────────┼────────────┤")
  fn row(label : String, n : Int) -> Unit {
    let pad_label = label + String::make(45 - label.length(), ' ')
    let n_str = n.to_string()
    let pad_n = String::make(8 - n_str.length(), ' ') + n_str
    let p = pct(raw, n)
    let pad_p = String::make(11 - p.length(), ' ') + p
    println("│ " + pad_label + "│" + pad_n + " │" + pad_p + " │")
  }

  row("raw source (4 files, concatenated)", raw)
  row("bundle (no opt)", bundled)
  row("+ tree shake", shaken)
  row("+ identifier mangle", shaken_id_mangle)
  row("+ property mangle (built-in reserved only)", shaken_full_mangle)
  row("+ auto-reserve (type-aware reserved set)", shaken_auto_reserved)
  row("+ method DCE (drop unused class methods)", shaken_methods_dced)
  row("+ inline immutable (const → literal)", shaken_inline_immutable)
  row("+ const fold + dead-branch elim", shaken_folded)
  println("└──────────────────────────────────────────────┴─────────┴────────────┘")
  // Assertions — each successive optimization must not make output
  // worse. If a refactor regresses, this fails loudly.
  assert_true(bundled > 0)
  assert_true(shaken <= bundled)
  assert_true(shaken_id_mangle <= shaken)
  assert_true(shaken_full_mangle <= shaken_id_mangle)
  // Auto-reserve typically *grows* output vs. the unreserved property
  // mangle because it protects more keys. It must still be smaller
  // than the no-mangle baseline (`shaken`).
  assert_true(shaken_auto_reserved <= shaken)
  // Method DCE pares unused class methods on top of every other
  // pass; the final stage must be the smallest.
  assert_true(shaken_methods_dced <= shaken_auto_reserved)
  assert_true(shaken_inline_immutable <= shaken_methods_dced)
  assert_true(shaken_folded <= shaken_inline_immutable)
}
