// Differential testing — runs each fixture through the pipeline at
// two configurations (baseline = no optimizations, optimized = the
// full stack) and executes both with `node`, asserting that the
// stdout matches. Any mismatch flags a false positive in the
// optimizer: a real program whose observable behavior changed after
// the supposedly-safe transforms.
//
// Goals:
//   1. Catch regressions where a transform breaks runtime semantics.
//   2. Capture known-tricky patterns so a future change can't
//      silently re-introduce a false positive.
//
// Each fixture lives as a `Map[String, String]` virtual file system
// keyed by entry path. The two bundles are written under
// `/tmp/ts-mbt-rw-<n>/{baseline,opt}.js` and then executed.

///|
fn full_opt_options() -> BundleOptions {
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
async fn run_differential(
  label : String,
  files : Map[String, String],
  entry : String,
  extra_reserved_props~ : Array[String] = [],
) -> Unit raise {
  // Baseline: no optimizations — just bundle into one file so we
  // can compare against the optimized output without depending on a
  // real module resolver at runtime.
  let baseline = match bundle_modules(files, entry, BundleOptions::default()) {
    Ok(out) => out
    Err(e) => fail("[\{label}] baseline bundle: \{e}")
  }
  let opt_cfg = if extra_reserved_props.length() > 0 {
    {
      ..full_opt_options(),
      mangle: Some(
        ManglerConfig::default()
          .with_mangle_properties(true)
          .with_reserved_properties(extra_reserved_props),
      ),
    }
  } else {
    full_opt_options()
  }
  let optimized = match bundle_modules(files, entry, opt_cfg) {
    Ok(out) => out
    Err(e) => fail("[\{label}] optimized bundle: \{e}")
  }
  // Write both to a temp dir keyed by the label so failures leave
  // inspectable artifacts behind.
  let safe_label = label.replace(old=" ", new="_").replace(old="/", new="_")
  let dir = "/tmp/ts-mbt-rw-\{safe_label}"
  let _ = @process.collect_output_merged("mkdir", ["-p", dir])
  let baseline_path = dir + "/baseline.js"
  let opt_path = dir + "/opt.js"
  @fs.write_file(baseline_path, baseline.js, create=0o644)
  @fs.write_file(opt_path, optimized.js, create=0o644)
  let (b_exit, b_out) = @process.collect_output_merged("node", [baseline_path])
  if b_exit != 0 {
    fail(
      "[\{label}] baseline exec failed (exit=\{b_exit}):\n--- output:\n\{b_out.text()}\n--- source: \{baseline_path}",
    )
  }
  let (o_exit, o_out) = @process.collect_output_merged("node", [opt_path])
  if o_exit != 0 {
    fail(
      "[\{label}] optimized exec failed (exit=\{o_exit}):\n--- output:\n\{o_out.text()}\n--- source: \{opt_path}",
    )
  }
  let b_text = b_out.text()
  let o_text = o_out.text()
  if b_text != o_text {
    fail(
      "[\{label}] OUTPUT DIVERGED\n--- baseline:\n\{b_text}--- optimized:\n\{o_text}--- compare \{baseline_path} vs \{opt_path}",
    )
  }
}

// ---------------------------------------------------------------------------
// Fixtures — each is a small library-shaped TS program. The
// `entry.ts` script exercises observable behavior via `console.log`
// so the differential check has something concrete to compare.
// ---------------------------------------------------------------------------

///|
async test "differential: const config with primitive properties + comparisons" {
  // The classic inline-immutable + const-fold target. Both branches
  // of every `cfg.X === literal` comparison must evaluate the same
  // way in the optimized bundle as in the baseline.
  let files : Map[String, String] = {}
  files["entry.ts"] =
    #|const cfg = { mode: "prod", port: 8080, debug: false };
    #|if (cfg.mode === "prod") console.log("prod-branch");
    #|if (cfg.mode === "dev") console.log("dev-branch");
    #|if (cfg.debug) console.log("debug-on"); else console.log("debug-off");
    #|console.log("port:", cfg.port);
    #|
  run_differential("const-config-primitives", files, "entry.ts")
}

///|
async test "differential: as-const array with index + length access" {
  let files : Map[String, String] = {}
  files["entry.ts"] =
    #|const TAGS = ["alpha", "beta", "gamma"] as const;
    #|console.log("tag-0:", TAGS[0]);
    #|console.log("tag-2:", TAGS[2]);
    #|console.log("count:", TAGS.length);
    #|
  run_differential("as-const-array", files, "entry.ts")
}

///|
async test "differential: nested const with two-level drill-through" {
  let files : Map[String, String] = {}
  files["entry.ts"] =
    #|const cfg = { db: { host: "localhost", port: 5432 }, retries: 3 };
    #|console.log("host:", cfg.db.host);
    #|console.log("port:", cfg.db.port);
    #|console.log("retries:", cfg.retries);
    #|
  run_differential("nested-const-drill", files, "entry.ts")
}

///|
async test "differential: class with multiple methods + private state" {
  let files : Map[String, String] = {}
  files["entry.ts"] =
    #|class Counter {
    #|  count: number = 0;
    #|  inc(): number { this.count = this.count + 1; return this.count; }
    #|  dec(): number { this.count = this.count - 1; return this.count; }
    #|  reset(): void { this.count = 0; }
    #|  value(): number { return this.count; }
    #|}
    #|const c = new Counter();
    #|c.inc(); c.inc(); c.inc(); c.dec();
    #|console.log("value-after:", c.value());
    #|c.reset();
    #|console.log("value-reset:", c.value());
    #|
  run_differential("class-counter", files, "entry.ts")
}

///|
async test "differential: function-local const inside an arrow body" {
  let files : Map[String, String] = {}
  files["entry.ts"] =
    #|const compute = () => {
    #|  const limits = { lower: 10, upper: 20 };
    #|  const value = 15;
    #|  if (value >= limits.lower && value <= limits.upper) {
    #|    return "in-range";
    #|  }
    #|  return "out-of-range";
    #|};
    #|console.log(compute());
    #|
  run_differential("function-local-const", files, "entry.ts")
}

///|
async test "differential: ReadonlyArray<T> parameter doesn't disqualify caller's const" {
  // The caller declares `TAGS as const`; without readonly recognition
  // the call to `pickFirst(TAGS)` would disqualify TAGS and skip
  // inlining its primitives. With it, the inline still fires.
  let files : Map[String, String] = {}
  files["entry.ts"] =
    #|const TAGS = ["alpha", "beta", "gamma"] as const;
    #|function pickFirst(items: ReadonlyArray<string>): string { return items[0]; }
    #|console.log("first:", pickFirst(TAGS));
    #|console.log("direct:", TAGS[0]);
    #|
  run_differential("readonly-array-param", files, "entry.ts")
}

///|
async test "differential: cross-module bundle with import + export chain" {
  let files : Map[String, String] = {}
  files["lib.ts"] =
    #|export const greet = (name: string): string => "hello, " + name;
    #|export function shout(s: string): string { return s.toUpperCase(); }
    #|
  files["entry.ts"] =
    #|import { greet, shout } from "./lib";
    #|console.log(greet("alice"));
    #|console.log(shout(greet("bob")));
    #|
  run_differential("cross-module-import", files, "entry.ts")
}

///|
async test "differential: short-circuit logic that the fold pass touches" {
  let files : Map[String, String] = {}
  files["entry.ts"] =
    #|const cfg = { feature: true, name: "alpha" };
    #|const result = cfg.feature && ("x:" + cfg.name);
    #|console.log("result:", result);
    #|const fallback = cfg.name || "anonymous";
    #|console.log("fallback:", fallback);
    #|
  run_differential("short-circuit-logic", files, "entry.ts")
}

// ---------------------------------------------------------------------------
// Known false-positive territory — these patterns either need a
// caller-supplied reserved set OR the optimizer must conservatively
// bail. The tests assert "no breakage" by either using the reserved
// list as documented or by relying on a structural escape that the
// analysis already detects.
// ---------------------------------------------------------------------------

///|
async test "differential: JSON.stringify works when keys are reserved" {
  // BARE `JSON.stringify(data)` of a manglable object IS a known
  // false positive — the property keys would be mangled and the
  // serialized JSON shape would change. We document the safe
  // pattern: callers protect the public keys via
  // `with_reserved_properties` and the differential check passes.
  let files : Map[String, String] = {}
  files["entry.ts"] =
    #|const data = { userName: "alice", userScore: 42 };
    #|console.log(JSON.stringify(data));
    #|
  run_differential(
    "json-stringify-reserved",
    files,
    "entry.ts",
    extra_reserved_props=["userName", "userScore"],
  )
}

///|
async test "differential: Object.keys / Object.values stay structural" {
  // `Object.keys(o)` reads the property names at runtime — if we
  // mangled them, the iteration would yield short names that the
  // user can't recognize. The caller protects via reserved list.
  let files : Map[String, String] = {}
  files["entry.ts"] =
    #|const meta = { sourceFile: "a.ts", lineNumber: 12 };
    #|for (const k of Object.keys(meta)) console.log(k);
    #|for (const v of Object.values(meta)) console.log(v);
    #|
  run_differential(
    "object-keys-values",
    files,
    "entry.ts",
    extra_reserved_props=["sourceFile", "lineNumber"],
  )
}

///|
async test "differential: computed property `obj[varName]` access stays intact" {
  // The mangler sees the static-name access AND the bare reference
  // — both code paths must end up at the same property in the
  // optimized bundle.
  let files : Map[String, String] = {}
  files["entry.ts"] =
    #|const TAGS = { primary: "first", secondary: "second" };
    #|const name: "primary" | "secondary" = "primary";
    #|console.log("computed:", TAGS[name]);
    #|console.log("static:", TAGS.primary);
    #|
  run_differential(
    "computed-property-access",
    files,
    "entry.ts",
    extra_reserved_props=["primary", "secondary"],
  )
}

///|
async test "differential: throw / try-catch behavior preserved" {
  let files : Map[String, String] = {}
  files["entry.ts"] =
    #|function risky(x: number): number {
    #|  if (x < 0) throw new Error("neg:" + x);
    #|  return x * 2;
    #|}
    #|try {
    #|  console.log("a:", risky(5));
    #|  console.log("b:", risky(-3));
    #|  console.log("never");
    #|} catch (e: any) {
    #|  console.log("caught:", e.message);
    #|}
    #|
  run_differential(
    "throw-catch",
    files,
    "entry.ts",
    // `message` is a reserved DOM-Error property already, but make
    // it explicit so the documented pattern is the one tested.
    extra_reserved_props=["message"],
  )
}
