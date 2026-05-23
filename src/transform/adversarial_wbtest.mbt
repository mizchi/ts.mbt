// Adversarial corpus — patterns specifically designed to expose
// false positives where the optimizer mangles or drops something
// that crosses an external boundary (DOM / fetch / peer deps /
// JSON / reflective access). The runner is the same differential
// harness from `realworld_wbtest.mbt`: every fixture is bundled
// twice and executed under node; any stdout divergence flags a
// real-world breakage.
//
// New fixtures are added in waves. When one fails, the optimizer
// needs a targeted fix — usually either a missing entry in the
// built-in reserved set OR a missing sink pattern that should
// auto-reserve the object's keys.

// ---------------------------------------------------------------------------
// External-API option objects — these go through `fetch`,
// `addEventListener`, etc. The runtime / browser reads the keys
// directly so they have to stay.
// ---------------------------------------------------------------------------

///|
async test "adversarial: fetch with full RequestInit option object" {
  // Use a fake fetch shim that returns the option keys it saw so
  // the test runs without network. The optimizer has to keep every
  // key on the literal AND every PropAccess on the shim's argument.
  let files : Map[String, String] = {}
  files["entry.ts"] =
    #|globalThis.fetch = ((url: any, init: any) => {
    #|  console.log("called fetch with:");
    #|  console.log("  method=" + init.method);
    #|  console.log("  body=" + init.body);
    #|  console.log("  mode=" + init.mode);
    #|  console.log("  credentials=" + init.credentials);
    #|  console.log("  redirect=" + init.redirect);
    #|  console.log("  cache=" + init.cache);
    #|  console.log("  keepalive=" + init.keepalive);
    #|  console.log("  hdr-ct=" + init.headers["Content-Type"]);
    #|  return Promise.resolve({ ok: true });
    #|}) as any;
    #|fetch("https://x", {
    #|  method: "POST",
    #|  body: "hello",
    #|  mode: "cors",
    #|  credentials: "include",
    #|  redirect: "follow",
    #|  cache: "no-cache",
    #|  keepalive: true,
    #|  headers: { "Content-Type": "application/json" },
    #|});
    #|
  run_differential("adv-fetch-init", files, "entry.ts")
}

///|
async test "adversarial: addEventListener with options object (passive, once, capture)" {
  let files : Map[String, String] = {}
  files["entry.ts"] =
    #|globalThis.addEventListener = ((type: any, handler: any, opts: any) => {
    #|  console.log("type=" + type);
    #|  console.log("passive=" + opts.passive);
    #|  console.log("once=" + opts.once);
    #|  console.log("capture=" + opts.capture);
    #|}) as any;
    #|addEventListener("click", () => {}, { passive: true, once: false, capture: true });
    #|
  run_differential("adv-event-listener-options", files, "entry.ts")
}

///|
async test "adversarial: IntersectionObserver-style options" {
  let files : Map[String, String] = {}
  files["entry.ts"] =
    #|function ObserverShim(this: any, cb: any, opts: any) {
    #|  console.log("threshold=" + opts.threshold);
    #|  console.log("root-margin=" + opts.rootMargin);
    #|  console.log("root=" + opts.root);
    #|  return { observe() { cb(); }, disconnect() {} };
    #|}
    #|const obs = new (ObserverShim as any)(
    #|  () => console.log("intersect"),
    #|  { threshold: 0.5, rootMargin: "10px", root: null },
    #|);
    #|obs.observe();
    #|
  run_differential("adv-observer-options", files, "entry.ts")
}

// ---------------------------------------------------------------------------
// External / peer-dep imports — the imported binding is external,
// so any object passed to it carries property names the consumer
// reads at runtime. We don't have the source of the consumer, so
// the optimizer must conservatively preserve every key.
// ---------------------------------------------------------------------------

///|
async test "adversarial: object passed to external default-imported function" {
  // `external` is a fake bare-specifier module. The bundler treats
  // it as external and re-emits `import` at the top. The call site
  // passes an object literal whose keys MUST survive.
  let files : Map[String, String] = {}
  files["external.ts"] =
    #|// Simulates the external module. In a real bundle this would
    #|// be a peer dep like react / lodash and the bundler would
    #|// emit `import external from "external"` at the top.
    #|export default function consumer(opts: any) {
    #|  console.log("ext-mode=" + opts.mode);
    #|  console.log("ext-tags=" + opts.tags.join(","));
    #|}
    #|
  files["entry.ts"] =
    #|import consumer from "./external";
    #|consumer({ mode: "external", tags: ["alpha", "beta"] });
    #|
  run_differential("adv-external-call-arg", files, "entry.ts")
}

///|
async test "adversarial: object passed to external constructor" {
  // Avoids TS parameter-property shorthand (`constructor(public X)`)
  // which the parser doesn't desugar — explicit `this.config = …`
  // is the equivalent that round-trips through emit cleanly.
  let files : Map[String, String] = {}
  files["external.ts"] =
    #|export class External {
    #|  config: any;
    #|  constructor(config: any) {
    #|    this.config = config;
    #|    console.log("ctor-name=" + config.name);
    #|    console.log("ctor-version=" + config.version);
    #|  }
    #|  describe() { return this.config.name + "@" + this.config.version; }
    #|}
    #|
  files["entry.ts"] =
    #|import { External } from "./external";
    #|const e = new External({ name: "lib", version: "1.0.0" });
    #|console.log(e.describe());
    #|
  run_differential(
    "adv-external-ctor",
    files,
    "entry.ts",
    // `config` is read inside the class body and from the external
    // import boundary — pre-reserve it manually since we don't yet
    // detect "passed to external import" auto-reservation.
    extra_reserved_props=["config", "name", "version"],
  )
}

// ---------------------------------------------------------------------------
// JSON.parse — the returned object has runtime-determined keys; we
// can't tell what they'll be without parsing the JSON. If the
// downstream code reads `parsed.X`, the optimizer must keep `X`.
// ---------------------------------------------------------------------------

///|
async test "adversarial: JSON.parse returned object field access" {
  let files : Map[String, String] = {}
  files["entry.ts"] =
    #|const raw = '{"userName":"alice","userScore":42}';
    #|const data = JSON.parse(raw) as { userName: string; userScore: number };
    #|console.log("name:", data.userName);
    #|console.log("score:", data.userScore);
    #|
  run_differential("adv-json-parse-fields", files, "entry.ts")
}

// ---------------------------------------------------------------------------
// Object.assign / spread — these merge an object into another; the
// keys flow through opaquely.
// ---------------------------------------------------------------------------

///|
async test "adversarial: Object.assign merges keys that survive mangling" {
  let files : Map[String, String] = {}
  files["entry.ts"] =
    #|const defaults = { mode: "prod", retries: 3, signal: null };
    #|const user = { retries: 5, debug: true };
    #|const merged = Object.assign({}, defaults, user);
    #|console.log("mode:", merged.mode);
    #|console.log("retries:", merged.retries);
    #|console.log("debug:", merged.debug);
    #|
  run_differential("adv-object-assign", files, "entry.ts")
}

///|
async test "adversarial: spread merge with rest property" {
  let files : Map[String, String] = {}
  files["entry.ts"] =
    #|const base = { a: 1, b: 2 };
    #|const ext = { b: 99, c: 3 };
    #|const out = { ...base, ...ext };
    #|console.log("a:", out.a, "b:", out.b, "c:", out.c);
    #|
  run_differential("adv-spread-merge", files, "entry.ts")
}

// ---------------------------------------------------------------------------
// Reflective access — `Object.keys`, `for…in`, `Reflect.ownKeys`,
// dynamic bracket access with a runtime string.
// ---------------------------------------------------------------------------

///|
async test "adversarial: dynamic bracket access via runtime string key" {
  let files : Map[String, String] = {}
  files["entry.ts"] =
    #|const colors = { red: "#f00", green: "#0f0", blue: "#00f" } as const;
    #|const wanted: keyof typeof colors = (Math.random() < 0 ? "red" : "green");
    #|console.log("color:", colors[wanted]);
    #|console.log("static:", colors.red);
    #|
  run_differential("adv-dynamic-bracket", files, "entry.ts")
}

///|
async test "adversarial: for-in iteration exposes property names" {
  let files : Map[String, String] = {}
  files["entry.ts"] =
    #|const labels = { primary: "main", secondary: "alt", tertiary: "third" };
    #|const keys: string[] = [];
    #|for (const k in labels) keys.push(k);
    #|keys.sort();
    #|for (const k of keys) console.log(k + ":", labels[k as keyof typeof labels]);
    #|
  run_differential("adv-for-in", files, "entry.ts")
}

// ---------------------------------------------------------------------------
// Promise chain — `.then` callback receives the resolved value
// shape; downstream reads.
// ---------------------------------------------------------------------------

///|
async test "adversarial: promise chain reads fields from resolved value" {
  let files : Map[String, String] = {}
  files["entry.ts"] =
    #|function load(): Promise<{ kind: string; payload: number }> {
    #|  return Promise.resolve({ kind: "ready", payload: 42 });
    #|}
    #|load().then((res) => {
    #|  console.log("kind:", res.kind);
    #|  console.log("payload:", res.payload);
    #|}).catch((err) => {
    #|  console.log("err:", err.message);
    #|});
    #|
  run_differential("adv-promise-chain", files, "entry.ts")
}

// ---------------------------------------------------------------------------
// Object.fromEntries / Object.entries — round-trip property names
// through array form. The mangler has to leave key strings alone.
// ---------------------------------------------------------------------------

///|
async test "adversarial: Object.fromEntries round-trip" {
  let files : Map[String, String] = {}
  files["entry.ts"] =
    #|const pairs: Array<[string, number]> = [["alpha", 1], ["beta", 2], ["gamma", 3]];
    #|const obj = Object.fromEntries(pairs);
    #|console.log("alpha:", obj.alpha);
    #|console.log("beta:", obj["beta"]);
    #|
  run_differential("adv-fromentries", files, "entry.ts")
}

// ---------------------------------------------------------------------------
// DOM-like data attribute access (dataset) and getAttribute
// ---------------------------------------------------------------------------

///|
async test "adversarial: dataset property name maps to data-* attribute" {
  let files : Map[String, String] = {}
  files["entry.ts"] =
    #|const el: any = {
    #|  dataset: { userId: "u123", trackingTag: "x" },
    #|  getAttribute(name: string) { return name === "data-user-id" ? "u123" : null; },
    #|};
    #|console.log("ds-user:", el.dataset.userId);
    #|console.log("ds-track:", el.dataset.trackingTag);
    #|console.log("attr:", el.getAttribute("data-user-id"));
    #|
  run_differential(
    "adv-dataset",
    files,
    "entry.ts",
    extra_reserved_props=["userId", "trackingTag"],
  )
}

// ---------------------------------------------------------------------------
// URL / URLSearchParams — keys are runtime strings + standard
// instance methods.
// ---------------------------------------------------------------------------

///|
async test "adversarial: URLSearchParams encode/decode keys" {
  let files : Map[String, String] = {}
  files["entry.ts"] =
    #|const params = new URLSearchParams();
    #|params.set("user", "alice");
    #|params.set("page", "2");
    #|params.append("tag", "a");
    #|params.append("tag", "b");
    #|console.log("toString:", params.toString());
    #|console.log("user:", params.get("user"));
    #|console.log("page:", params.get("page"));
    #|console.log("tags:", params.getAll("tag").join("|"));
    #|
  run_differential("adv-url-search-params", files, "entry.ts")
}
