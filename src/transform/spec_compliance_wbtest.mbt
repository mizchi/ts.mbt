// Spec-compliance tests — for each slim real-library reimplementation
// in the corpus (neverthrow / zod / mitt), bundle through every
// optimization level (no-opt / Production / Full / Full+minify) and
// run a comprehensive assertion suite against the bundled output.
// Failures localize to "which library × which opt level" so a
// regression is immediately attributable.
//
// Adds a "spec test entry" alongside the library: a TS file that
// runs every public-API method and emits one `[name] PASS/FAIL`
// line per assertion. We check that every line says PASS.

// ---------------------------------------------------------------------------
// Spec test harness
// ---------------------------------------------------------------------------

///|
/// Bundle `files` from `entry` at every opt level we care about,
/// execute each bundle under node, and assert that every output
/// line says `PASS`. The opt-level matrix tests:
///   1. Development         — no optimization, baseline correctness
///   2. Production          — tree-shake + method DCE
///   3. Full                — all optimizations
///   4. Full + minify       — single-line output, identical semantics
async fn run_spec_matrix(
  label : String,
  files : Map[String, String],
  entry : String,
  extra_reserved_props~ : Array[String] = [],
) -> Unit raise {
  let levels : Array[(String, BundleOptions)] = []
  levels.push(("dev", BundleOptions::default()))
  levels.push(
    (
      "prod",
      {
        ..BundleOptions::default(),
        tree_shake: true,
        drop_unused_methods: true,
      },
    ),
  )
  let mangle = ManglerConfig::default()
    .with_mangle_properties(true)
    .with_reserved_properties(extra_reserved_props)
  levels.push(
    (
      "full",
      {
        ..BundleOptions::default(),
        tree_shake: true,
        mangle: Some(mangle),
        auto_reserve: true,
        drop_unused_methods: true,
        inline_immutable: true,
        fold_constants: true,
      },
    ),
  )
  levels.push(
    (
      "full+min",
      {
        ..BundleOptions::default(),
        tree_shake: true,
        mangle: Some(mangle),
        auto_reserve: true,
        drop_unused_methods: true,
        inline_immutable: true,
        fold_constants: true,
        minify: true,
      },
    ),
  )
  for entry_pair in levels {
    let level_name = entry_pair.0
    let opts = entry_pair.1
    let out = match bundle_modules(files, entry, opts) {
      Ok(o) => o
      Err(e) => fail("[\{label}/\{level_name}] bundle error: \{e}")
    }
    let path = "/tmp/ts-mbt-spec-\{label}-\{level_name}.js"
    @fs.write_file(path, out.js, create=0o644)
    let (exit, output) = @process.collect_output_merged("node", [path])
    if exit != 0 {
      fail(
        "[\{label}/\{level_name}] exec failed (exit=\{exit}):\n\{output.text()}",
      )
    }
    let text = output.text()
    // Each line must be `[name] PASS`. Any `FAIL` anywhere or
    // any line missing the `PASS` marker is a real spec break
    // — even if the differential vs baseline matches (a bug that
    // affects baseline and opt equally would silently survive
    // pure stdout diffing).
    let lines = text.split("\n")
    let mut total = 0
    let mut passed = 0
    for raw_line in lines {
      let line = raw_line.to_string()
      if line == "" {
        continue
      }
      total = total + 1
      if line.contains("PASS") && !line.contains("FAIL") {
        passed = passed + 1
      } else {
        println("[\{label}/\{level_name}] non-PASS line: \{line}")
      }
    }
    if total == 0 {
      fail("[\{label}/\{level_name}] no assertion output (empty stdout?)")
    }
    if passed != total {
      fail("[\{label}/\{level_name}] \{passed}/\{total} assertions passed")
    }
  }
}

// ---------------------------------------------------------------------------
// neverthrow: comprehensive API spec
// ---------------------------------------------------------------------------

///|
async test "spec: neverthrow Result<T, E> covers every API method" {
  let files : Map[String, String] = {}
  files["neverthrow.ts"] = neverthrow_lib_source
  files["entry.ts"] =
    #|import { ok, err, Ok, Err, Result } from "./neverthrow";
    #|function check(name: string, cond: boolean) {
    #|  console.log("[" + name + "] " + (cond ? "PASS" : "FAIL"));
    #|}
    #|// ok() / err() construction
    #|const okVal = ok<number, string>(42);
    #|const errVal = err<number, string>("boom");
    #|check("ok.isOk", okVal.isOk());
    #|check("ok.isErr", !okVal.isErr());
    #|check("err.isOk", !errVal.isOk());
    #|check("err.isErr", errVal.isErr());
    #|// map preserves on Ok, no-op on Err
    #|check("ok.map", okVal.map(n => n * 2).match(v => v === 84, _ => false));
    #|check("err.map", errVal.map(n => n * 2).match(_ => false, e => e === "boom"));
    #|// mapErr no-op on Ok, transforms on Err
    #|check("ok.mapErr", okVal.mapErr(e => e + "!").match(v => v === 42, _ => false));
    #|check("err.mapErr", errVal.mapErr(e => e + "!").match(_ => false, e => e === "boom!"));
    #|// andThen chains Result<U, E>
    #|check("ok.andThen.ok", okVal.andThen(n => ok<string, string>("v=" + n)).match(v => v === "v=42", _ => false));
    #|check("ok.andThen.err", okVal.andThen(_ => err<string, string>("inner")).match(_ => false, e => e === "inner"));
    #|check("err.andThen", errVal.andThen(_ => ok<string, string>("x")).match(_ => false, e => e === "boom"));
    #|// match dispatches by tag
    #|check("ok.match", okVal.match(v => "v" + v, e => "e" + e) === "v42");
    #|check("err.match", errVal.match(v => "v" + v, e => "e" + e) === "eboom");
    #|// unwrapOr returns value on Ok, default on Err
    #|check("ok.unwrapOr", okVal.unwrapOr(-1) === 42);
    #|check("err.unwrapOr", errVal.unwrapOr(-1) === -1);
    #|// chain of map + andThen + mapErr
    #|const r = ok<number, string>(10)
    #|  .map(n => n + 1)
    #|  .andThen(n => n > 100 ? err<number, string>("big") : ok<number, string>(n * 2));
    #|check("chain", r.match(v => v === 22, _ => false));
    #|
  run_spec_matrix(
    "neverthrow",
    files,
    "entry.ts",
    extra_reserved_props=["value", "error"],
  )
}

// ---------------------------------------------------------------------------
// zod: comprehensive API spec
// ---------------------------------------------------------------------------

///|
async test "spec: zod-like schema validators cover the full surface" {
  let files : Map[String, String] = {}
  files["zod.ts"] = zod_lib_source
  files["entry.ts"] =
    #|import { z } from "./zod";
    #|function check(name: string, cond: boolean) {
    #|  console.log("[" + name + "] " + (cond ? "PASS" : "FAIL"));
    #|}
    #|// Primitive validators
    #|check("string.ok", z.string().safeParse("hello").ok);
    #|check("string.fail", !z.string().safeParse(42).ok);
    #|check("number.ok", z.number().safeParse(3.14).ok);
    #|check("number.fail", !z.number().safeParse("nope").ok);
    #|// min/max constraints
    #|check("string.min.ok", z.string().min(3).safeParse("foo").ok);
    #|check("string.min.fail", !z.string().min(3).safeParse("hi").ok);
    #|check("string.max.fail", !z.string().max(3).safeParse("hello").ok);
    #|// optional
    #|check("optional.undef", z.string().optional().safeParse(undefined).ok);
    #|check("optional.value", z.string().optional().safeParse("v").ok);
    #|// array
    #|check("array.ok", z.string().array().safeParse(["a", "b"]).ok);
    #|check("array.fail", !z.string().array().safeParse(["a", 1]).ok);
    #|check("array.empty", z.string().array().safeParse([]).ok);
    #|// object shape
    #|const userSchema = z.object<{ name: string; age: number }>({
    #|  name: z.string(),
    #|  age: z.number(),
    #|});
    #|check("object.ok", userSchema.safeParse({ name: "alice", age: 30 }).ok);
    #|check("object.missing", !userSchema.safeParse({ name: "alice" }).ok);
    #|check("object.wrong-type", !userSchema.safeParse({ name: 1, age: "x" }).ok);
    #|// parse throws on failure
    #|try {
    #|  userSchema.parse({ name: "", age: "thirty" });
    #|  check("parse.throws", false);
    #|} catch (e: any) {
    #|  check("parse.throws", e.issues.length > 0);
    #|}
    #|// safeParse data on success
    #|const ok1 = userSchema.safeParse({ name: "bob", age: 25 });
    #|check("safeParse.data", ok1.ok && ok1.data!.name === "bob" && ok1.data!.age === 25);
    #|// Nested validation
    #|const nestedSchema = z.object<{ user: { name: string } }>({
    #|  user: z.object<{ name: string }>({ name: z.string() }),
    #|});
    #|check("nested.ok", nestedSchema.safeParse({ user: { name: "x" } }).ok);
    #|check("nested.fail", !nestedSchema.safeParse({ user: { name: 1 } }).ok);
    #|
  run_spec_matrix(
    "zod",
    files,
    "entry.ts",
    extra_reserved_props=[
      "name", "age", "user", "shape", "inner", "ok", "data",
      "error", "issues", "path", "message", "_min", "_max",
    ],
  )
}

// ---------------------------------------------------------------------------
// mitt: comprehensive event-emitter spec
// ---------------------------------------------------------------------------

///|
async test "spec: mitt emitter contracts hold across opt levels" {
  let files : Map[String, String] = {}
  files["mitt.ts"] =
    #|export type Handler<T = any> = (event: T) => void;
    #|export default function mitt<E extends Record<string, any>>() {
    #|  const all = new Map<any, Handler[]>();
    #|  return {
    #|    all,
    #|    on(type: any, h: Handler) {
    #|      const list = all.get(type);
    #|      if (list) list.push(h);
    #|      else all.set(type, [h]);
    #|    },
    #|    off(type: any, h: Handler) {
    #|      const list = all.get(type);
    #|      if (!list) return;
    #|      const i = list.indexOf(h);
    #|      if (i >= 0) list.splice(i, 1);
    #|    },
    #|    emit(type: any, ev?: any) {
    #|      const list = all.get(type);
    #|      if (list) (list.slice() as any[]).forEach((h) => h(ev));
    #|      const star = all.get("*");
    #|      if (star) (star.slice() as any[]).forEach((h) => h(type, ev));
    #|    },
    #|  };
    #|}
    #|
  files["entry.ts"] =
    #|import mitt from "./mitt";
    #|function check(name: string, cond: boolean) {
    #|  console.log("[" + name + "] " + (cond ? "PASS" : "FAIL"));
    #|}
    #|type Events = { foo: number; bar: string };
    #|// Basic on / emit
    #|let got = 0;
    #|const bus = mitt<Events>();
    #|const h = (n: number) => { got = got + n; };
    #|bus.on("foo", h);
    #|bus.emit("foo", 5);
    #|bus.emit("foo", 10);
    #|check("on/emit", got === 15);
    #|// off removes the handler
    #|bus.off("foo", h);
    #|bus.emit("foo", 100);
    #|check("off", got === 15);
    #|// Multiple listeners fire in order
    #|const trace: string[] = [];
    #|bus.on("bar", (s) => trace.push("a:" + s));
    #|bus.on("bar", (s) => trace.push("b:" + s));
    #|bus.emit("bar", "hi");
    #|check("multi-listener", trace[0] === "a:hi" && trace[1] === "b:hi");
    #|// Wildcard listener sees all events
    #|const wildTrace: string[] = [];
    #|bus.on("*", (type: any, ev: any) => wildTrace.push(type + ":" + ev));
    #|bus.emit("foo", 1);
    #|bus.emit("bar", "x");
    #|check("wildcard", wildTrace.length === 2);
    #|check("wildcard.type", wildTrace[0].startsWith("foo:"));
    #|// `all` map exposes raw state
    #|check("all-is-map", bus.all instanceof Map);
    #|check("all-has-foo", bus.all.has("foo"));
    #|// Emit unknown event is a no-op
    #|bus.emit("never" as any);
    #|check("unknown-emit", true);
    #|
  run_spec_matrix(
    "mitt",
    files,
    "entry.ts",
    extra_reserved_props=["all"],
  )
}
