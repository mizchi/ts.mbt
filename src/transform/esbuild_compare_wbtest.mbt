// esbuild comparison — bundle the same fixture with our pipeline
// at maximum optimization (Full + minify) and with esbuild
// (--minify --bundle --target=es2020), then compare:
//
//   1. Both bundles must execute under node and produce identical
//      stdout — semantic parity at the call boundary.
//   2. Output size (for size-curiosity, not a strict pass/fail).
//
// Run with `moon test --target native -p mizchi/ts/transform`. The
// esbuild path uses `npx --yes esbuild` so the test self-resolves
// the binary on first run.

///|
async fn run_esbuild_compare(
  label : String,
  files : Map[String, String],
  entry : String,
  expected_lines~ : Int = -1,
  extra_reserved_props~ : Array[String] = [],
) -> Unit raise {
  // Write the VFS to disk so esbuild can see it.
  let workdir = "/tmp/ts-mbt-esbuild-\{label}"
  let _ = @process.collect_output_merged("rm", ["-rf", workdir])
  let _ = @process.collect_output_merged("mkdir", ["-p", workdir])
  // Write each file, creating any subdirectories.
  for kv in files {
    let abs = workdir + "/" + kv.0
    let parent = match abs.rev_find("/") {
      Some(i) => abs.substring(start=0, end=i).to_string()
      None => workdir
    }
    let _ = @process.collect_output_merged("mkdir", ["-p", parent])
    @fs.write_file(abs, kv.1, create=0o644)
  }
  // Our bundle (Full + minify).
  let mangle = ManglerConfig::default()
    .with_mangle_properties(true)
    .with_reserved_properties(extra_reserved_props)
  let opts : BundleOptions = {
    ..BundleOptions::default(),
    tree_shake: true,
    mangle: Some(mangle),
    auto_reserve: true,
    drop_unused_methods: true,
    inline_immutable: true,
    fold_constants: true,
    minify: true,
  }
  let ours_out = match bundle_modules(files, entry, opts) {
    Ok(o) => o
    Err(e) => fail("[\{label}] our bundle: \{e}")
  }
  let ours_path = workdir + "/ours.js"
  @fs.write_file(ours_path, ours_out.js, create=0o644)
  // esbuild bundle.
  let esbuild_path = workdir + "/esbuild.js"
  let (esbuild_exit, esbuild_log) = @process.collect_output_merged("npx", [
    "--yes",
    "esbuild",
    workdir + "/" + entry,
    "--bundle",
    "--minify",
    "--format=cjs",
    "--target=es2020",
    "--outfile=" + esbuild_path,
  ])
  if esbuild_exit != 0 {
    fail("[\{label}] esbuild bundle failed: \{esbuild_log.text()}")
  }
  // Execute both, compare stdout.
  let (ours_exit, ours_stdout) = @process.collect_output_merged("node", [
    ours_path,
  ])
  let (eb_exit, eb_stdout) = @process.collect_output_merged("node", [
    esbuild_path,
  ])
  if ours_exit != 0 {
    fail("[\{label}] our bundle exec failed:\n\{ours_stdout.text()}")
  }
  if eb_exit != 0 {
    fail("[\{label}] esbuild bundle exec failed:\n\{eb_stdout.text()}")
  }
  let ours_text = ours_stdout.text()
  let eb_text = eb_stdout.text()
  if ours_text != eb_text {
    fail(
      "[\{label}] stdout diverged\n--- ours ---\n\{ours_text}--- esbuild ---\n\{eb_text}",
    )
  }
  if expected_lines >= 0 {
    let mut count = 0
    for line in ours_text.split("\n") {
      if line.to_string() != "" {
        count = count + 1
      }
    }
    if count != expected_lines {
      fail("[\{label}] expected \{expected_lines} lines, got \{count}")
    }
  }
  // Report size delta. The test always passes here — esbuild has
  // had years of optimization work, so we're documenting where
  // we stand rather than blocking on a specific ratio.
  let ours_size = ours_out.js.length()
  let eb_size = eb_text_len(esbuild_path)
  let pct = if eb_size > 0 {
    let delta = (ours_size - eb_size) * 100 / eb_size
    delta.to_string()
  } else {
    "n/a"
  }
  println("[\{label}] ours=\{ours_size}B  esbuild=\{eb_size}B  delta=\{pct}%")
}

///|
async fn eb_text_len(path : String) -> Int {
  let text = @fs.read_file(path).text() catch {
    _ => return 0
  }
  text.length()
}

// ---------------------------------------------------------------------------
// Test cases — each fixture covers a representative real-world
// shape and asserts semantic parity with esbuild's minified bundle.
// ---------------------------------------------------------------------------

///|
async test "esbuild: const config + computed branches match esbuild's output" {
  let files : Map[String, String] = {}
  files["entry.ts"] =
    #|const cfg = { mode: "prod", count: 3 };
    #|if (cfg.mode === "dev") {
    #|  console.log("dev");
    #|} else {
    #|  for (let i = 0; i < cfg.count; i = i + 1) {
    #|    console.log("tick", i);
    #|  }
    #|}
    #|
  run_esbuild_compare("const-config", files, "entry.ts")
}

///|
async test "esbuild: cross-module imports + tree-shake parity" {
  let files : Map[String, String] = {}
  files["lib.ts"] =
    #|export function used(n: number): number { return n * 2; }
    #|export function unused(n: number): number { return n + 100; }
    #|export const VERSION = "1.0";
    #|
  files["entry.ts"] =
    #|import { used, VERSION } from "./lib";
    #|console.log("v=" + VERSION);
    #|console.log("u=" + used(5));
    #|
  run_esbuild_compare("cross-module", files, "entry.ts")
}

///|
async test "esbuild: class with method calls matches" {
  let files : Map[String, String] = {}
  files["entry.ts"] =
    #|class Counter {
    #|  count: number = 0;
    #|  inc(): number { this.count = this.count + 1; return this.count; }
    #|  value(): number { return this.count; }
    #|}
    #|const c = new Counter();
    #|c.inc(); c.inc(); c.inc();
    #|console.log("count=" + c.value());
    #|
  run_esbuild_compare(
    "class-counter",
    files,
    "entry.ts",
    extra_reserved_props=["count"],
  )
}

///|
async test "esbuild: real-shape neverthrow library matches" {
  let files : Map[String, String] = {}
  files["neverthrow.ts"] = neverthrow_lib_source
  files["entry.ts"] =
    #|import { ok, err } from "./neverthrow";
    #|const a = ok<number, string>(10)
    #|  .map(n => n * 2)
    #|  .andThen(n => n > 50 ? err<number, string>("big") : ok<number, string>(n + 1));
    #|console.log(a.match(v => "v=" + v, e => "e=" + e));
    #|const b = err<number, string>("boom").mapErr(e => e.toUpperCase());
    #|console.log(b.match(v => "v=" + v, e => "e=" + e));
    #|
  run_esbuild_compare(
    "neverthrow",
    files,
    "entry.ts",
    extra_reserved_props=["value", "error"],
  )
}
