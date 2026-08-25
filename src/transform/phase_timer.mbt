// Wall-clock attribution for the pipeline.
//
// Compile time is superlinear in input size — 3 MB of `checker.ts` takes
// ~30s and 9 MB of `typescript.js` takes ~390s — and until now nothing
// said WHICH pass that is. A guess at the hot spot is worth very little
// against a pipeline of twenty passes, several of which run a fixed
// point over the whole bundle.
//
// So the passes report. `PhaseTimer` is a list of `(label, microseconds)`
// in the order the phases ran, threaded through `bundle_modules` and
// surfaced on `BundleOutput.timings` for `mtsc --timing` to print. It is
// off unless asked for: `PhaseTimer::disabled()` records nothing, so the
// instrumentation costs one branch per phase on the normal path.

///|
pub(all) struct PhaseTimer {
  enabled : Bool
  /// `(label, microseconds)` in execution order. Repeated labels are
  /// kept separate — a pass that runs twice (purity, treeshake) has two
  /// entries, because "the second treeshake is the slow one" is exactly
  /// the kind of thing this is for.
  entries : Array[(String, Double)]
}

///|
pub fn PhaseTimer::new() -> PhaseTimer {
  { enabled: true, entries: [] }
}

///|
pub fn PhaseTimer::disabled() -> PhaseTimer {
  { enabled: false, entries: [] }
}

///|
/// Run `body`, record how long it took under `label`, return its result.
/// Written as a wrapper rather than start/stop calls so a phase cannot
/// be left unclosed on an early return.
pub fn[T] PhaseTimer::phase(
  self : PhaseTimer,
  label : String,
  body : () -> T,
) -> T {
  if !self.enabled {
    return body()
  }
  let started = @bench.monotonic_clock_start()
  let out = body()
  self.entries.push((label, @bench.monotonic_clock_end(started)))
  out
}

///|
/// Record a measurement taken elsewhere (the CLI's file loading and
/// parsing happen before `bundle_modules` is called).
pub fn PhaseTimer::record(
  self : PhaseTimer,
  label : String,
  micros : Double,
) -> Unit {
  if self.enabled {
    self.entries.push((label, micros))
  }
}

///|
/// A table of phases, slowest first, with each phase's share of the
/// total. Sorted rather than chronological: the question this answers is
/// "where did the time go", and twenty rows in pipeline order do not
/// answer it at a glance.
pub fn PhaseTimer::report(self : PhaseTimer) -> Array[String] {
  let out : Array[String] = []
  if self.entries.is_empty() {
    return out
  }
  let mut total = 0.0
  for e in self.entries {
    total = total + e.1
  }
  // Merge repeated labels only for the total; keep the rows separate.
  let ranked : Array[(String, Double)] = []
  for e in self.entries {
    ranked.push(e)
  }
  for i in 0..<ranked.length() {
    let mut best = i
    for j in (i + 1)..<ranked.length() {
      if ranked[j].1 > ranked[best].1 {
        best = j
      }
    }
    if best != i {
      let tmp = ranked[i]
      ranked[i] = ranked[best]
      ranked[best] = tmp
    }
  }
  out.push("phase timings (slowest first)")
  out.push("")
  for r in ranked {
    let ms = r.1 / 1000.0
    if ms < 0.5 {
      continue
    }
    let share = if total > 0.0 { r.1 * 100.0 / total } else { 0.0 }
    out.push(
      "  " + format_millis(ms) + " ms  " + format_share(share) + "%  " + r.0,
    )
  }
  out.push("")
  out.push("  " + format_millis(total / 1000.0) + " ms  total")
  out
}

///|
/// Fixed-width milliseconds so the column lines up without a formatter.
fn format_millis(ms : Double) -> String {
  let whole = ms.to_int()
  let s = whole.to_string()
  let mut pad = ""
  for _ in 0..<(8 - s.length()) {
    pad = pad + " "
  }
  pad + s
}

///|
fn format_share(share : Double) -> String {
  let tenths = (share * 10.0).to_int()
  let whole = tenths / 10
  let frac = tenths % 10
  let s = whole.to_string() + "." + frac.to_string()
  let mut pad = ""
  for _ in 0..<(5 - s.length()) {
    pad = pad + " "
  }
  pad + s
}
