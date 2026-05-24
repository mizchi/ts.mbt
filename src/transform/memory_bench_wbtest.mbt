// Memory benchmarks — peak RSS measurement via `/usr/bin/time -v`.
//
// MoonBit's `@bench` harness measures wall-clock time, not memory.
// To get peak RSS we write a fixture's bundle output to /tmp via
// async-process, run the resulting JS through node under
// `/usr/bin/time -v`, and parse `Maximum resident set size`.
//
// The numbers reported here are dominated by the JS runtime
// (node), NOT by the MoonBit bundler — they're a sanity check
// that the produced bundles don't blow up node's heap, not a
// measurement of our bundler's memory profile.

///|
async fn measure_peak_rss(args : ArrayView[String]) -> Int raise {
  // Use `/usr/bin/time -v <cmd>` which prints
  //   Maximum resident set size (kbytes): 12345
  // to stderr. `collect_output_merged` glues stdout+stderr.
  let cmd : Array[String] = ["-v"]
  for a in args {
    cmd.push(a)
  }
  let (exit, output) = @process.collect_output_merged(
    "/usr/bin/time", cmd,
  )
  if exit != 0 {
    fail("time -v failed: \{output.text()}")
  }
  let text = output.text()
  for line in text.split("\n") {
    let s = line.to_string()
    if s.contains("Maximum resident set size") {
      // Format: `\tMaximum resident set size (kbytes): 12345`
      match s.rev_find(":") {
        Some(idx) => {
          let v = s.substring(start=idx + 1, end=s.length()).to_string().trim_space().to_string()
          match (try? @strconv.parse_int(v)) {
            Ok(n) => return n
            Err(_) => ()
          }
        }
        None => ()
      }
    }
  }
  fail("could not find RSS line in: \{text}")
}

///|
async fn bundle_and_measure_rss(
  files : Map[String, String],
  entry : String,
  opts : BundleOptions,
  label : String,
) -> Int raise {
  let out = match bundle_modules(files, entry, opts) {
    Ok(o) => o
    Err(e) => fail("bundle: \{e}")
  }
  let safe = label.replace(old=" ", new="_").replace(old="/", new="_")
  let path = "/tmp/ts-mbt-rss-\{safe}.js"
  @fs.write_file(path, out.js, create=0o644)
  measure_peak_rss(["node", path])
}

// ---------------------------------------------------------------------------
// Memory sweep — read peak RSS at increasing bundle sizes. Mostly
// useful as a regression alarm: if a bundle's output suddenly
// jumps node's heap by an order of magnitude, the optimizer
// probably emitted pathological code.
// ---------------------------------------------------------------------------

///|
async test "memory sweep: realistic kitchen-sink bundle peak RSS under node" {
  let files = realistic_kitchen_sink()
  let baseline = bundle_and_measure_rss(
    files, "app/main.ts", BundleOptions::default(), "kitchen-baseline",
  )
  let optimized = bundle_and_measure_rss(
    files, "app/main.ts", full_opt_bundle_options(), "kitchen-optimized",
  )
  println("┌────────────────────────────────────┬──────────┐")
  println("│ bundle                             │ peak RSS │")
  println("├────────────────────────────────────┼──────────┤")
  fn row(label : String, kb : Int) -> Unit {
    let pad_label = label + String::make(35 - label.length(), ' ')
    let v = kb.to_string() + " KB"
    let pad_v = String::make(9 - v.length(), ' ') + v
    println("│ " + pad_label + "│" + pad_v + " │")
  }

  row("kitchen-sink baseline (no opt)", baseline)
  row("kitchen-sink + full opt", optimized)
  println("└────────────────────────────────────┴──────────┘")
  // Sanity: RSS should be on the order of node startup
  // (~40-80 MB), not gigabytes.
  assert_true(baseline > 0)
  assert_true(baseline < 500_000)
  assert_true(optimized > 0)
  assert_true(optimized < 500_000)
}

///|
async test "memory sweep: 100/500-module scaling peak RSS under node" {
  let f100 = realistic_scaling_fixture(100)
  let f500 = realistic_scaling_fixture(500)
  let rss100 = bundle_and_measure_rss(
    f100, "entry.ts", full_opt_bundle_options(), "scaling-100",
  )
  let rss500 = bundle_and_measure_rss(
    f500, "entry.ts", full_opt_bundle_options(), "scaling-500",
  )
  println("┌────────────────────────────────────┬──────────┐")
  println("│ scaling                            │ peak RSS │")
  println("├────────────────────────────────────┼──────────┤")
  fn row(label : String, kb : Int) -> Unit {
    let pad_label = label + String::make(35 - label.length(), ' ')
    let v = kb.to_string() + " KB"
    let pad_v = String::make(9 - v.length(), ' ') + v
    println("│ " + pad_label + "│" + pad_v + " │")
  }

  row("100-module bundle output", rss100)
  row("500-module bundle output", rss500)
  println("└────────────────────────────────────┴──────────┘")
  assert_true(rss500 > 0 && rss500 < 1_000_000)
}
