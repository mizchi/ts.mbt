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
    #|export function clampMaxListeners(requested: number): number {
    #|  if (requested < 1) return 1;
    #|  if (requested > 1000) return 1000;
    #|  return requested;
    #|}
    #|export function defaultErrorHandler(error: Error): void {
    #|  console.error("[emitter]", error.message);
    #|}
    #|export const internalUnusedHelper = (x: number) => x * 9999;
    #|export const anotherUnusedConst = "never-referenced-anywhere";
    #|
  files["emitter.ts"] =
    #|import { EventHandler, EmitterConfig, Emitter } from "./types";
    #|import { clampMaxListeners, defaultErrorHandler } from "./utils";
    #|export function createEmitter<T>(
    #|  config: Partial<EmitterConfig> = {},
    #|): Emitter<T> {
    #|  const maxListeners = clampMaxListeners(config.maxListeners ?? 10);
    #|  const errorHandler = config.errorHandler ?? defaultErrorHandler;
    #|  const listenerMap: Record<string, EventHandler<T>[]> = {};
    #|  function on(event: string, handler: EventHandler<T>) {
    #|    const list = listenerMap[event] ?? [];
    #|    if (list.length >= maxListeners) {
    #|      errorHandler(new Error("too many listeners"));
    #|      return;
    #|    }
    #|    list.push(handler);
    #|    listenerMap[event] = list;
    #|  }
    #|  function off(event: string, handler: EventHandler<T>) {
    #|    const list = listenerMap[event];
    #|    if (!list) return;
    #|    listenerMap[event] = list.filter(h => h !== handler);
    #|  }
    #|  function emit(event: string, payload: T) {
    #|    const list = listenerMap[event];
    #|    if (!list) return;
    #|    for (const h of list) h(payload);
    #|  }
    #|  function listenerCount(event: string): number {
    #|    return (listenerMap[event] ?? []).length;
    #|  }
    #|  return { on, off, emit, listenerCount };
    #|}
    #|
  files["entry.ts"] =
    #|import { createEmitter } from "./emitter";
    #|export const bus = createEmitter<{ value: number }>({ maxListeners: 5 });
    #|bus.on("tick", (payload) => {
    #|  console.log("got tick", payload.value);
    #|});
    #|bus.emit("tick", { value: 42 });
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
  let p = saved * 1000 / base
  let whole = p / 10
  let frac = if p < 0 { -p % 10 } else { p % 10 }
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
}
