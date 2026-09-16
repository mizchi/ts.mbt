// `--watch` / `-w`.
//
// Polling, not notification: neither `mizchi/x/fs` nor
// `moonbitlang/async/fs` exposes a watch syscall, so there is nothing to
// subscribe to. `@async_fs.mtime` is what is available, and the loop is
// built around what that can and cannot tell us.
//
// What it watches is the resolved PROGRAM, not the entry list. A change
// to a file the entry imports has to trigger a rebuild, and in a bundle
// that file is reached through the import graph rather than named on the
// command line — so the set comes back out of the compile. The first
// pass therefore has to run before there is anything to watch, which is
// also what `tsc --watch` does.
//
// Two limits are worth stating rather than discovering. A file ADDED to
// a directory an `include` pattern covers is not noticed until something
// already in the program changes, because a new path has no previous
// mtime to differ from — the poll compares a set it already has. And the
// interval is a compromise with no good answer: a shorter one burns CPU
// on a large program (the stat is per file, per pass), a longer one
// makes the tool feel broken.

///|
/// How long to wait between polls, in milliseconds.
///
/// `tsc --watch` debounces around 250 ms after a change it was told
/// about; with no notification to debounce, this is the whole latency, so
/// it is the largest value that still feels immediate rather than the
/// smallest one that is cheap.
const MTSC_WATCH_INTERVAL_MS : Int = 300

///|
/// `(seconds, nanos)` for `path`, or `None` when it cannot be read.
///
/// A file that disappears reads as `None` and so differs from its
/// recorded stamp, which is the behaviour wanted: deleting an imported
/// file should trigger a rebuild that reports the broken import.
#cfg(not(target="js"))
async fn mtsc_watch_stamp(path : String) -> (Int64, Int)? {
  let v = @async_fs.mtime(path) catch { _ => return None }
  Some(v)
}

///|
/// `mtime` for the JavaScript backend.
///
/// `moonbitlang/async/fs` states in its own `unimplemented.mbt` that it
/// "does not support JavaScript backend" and restricts every source
/// file but that one to `native` / `wasm`, so `@async_fs.mtime` does
/// not exist here and this is why the CLI could not build for `js` at
/// all.
///
/// SYNCHRONOUS, unlike the native arm, and that is a deliberate choice
/// between two costs. `node:fs/promises`' `stat` would keep the
/// signature `async` and match `mizchi/x/fs`'s own JS backend — but
/// awaiting a JS promise needs `moonbitlang/async/js_async` imported,
/// which is then unused on native, and `moon check --deny-warn` on
/// native is THE gate. `statSync` needs no import, so the cost lands as
/// one suppressed diagnostic on the caller below instead of two
/// warnings on the gate.
#cfg(target="js")
fn mtsc_watch_stamp(path : String) -> (Int64, Int)? {
  // Keep the `moonbitlang/async/fs` import referenced on this backend.
  // It exists for the `@async_fs.mtime` in the arm above, and moon has
  // no per-target `import` syntax, so on `js` the dependency reads as
  // unused and warning 0029 fails `--deny-warn --target js` on a
  // package that is otherwise clean. `unimplemented` is the ONE symbol
  // that package exposes here — declared `#cfg(not(target="native"))`
  // under the doc comment "This package currently does not support
  // JavaScript backend", i.e. it exists to be named in exactly this
  // situation. Deliberately not `warnings = "-0029"`: a package-wide
  // suppression would also hide a genuinely dead import, on every
  // target, which is how a gate stops being a gate. A standalone
  // function was tried first and is worse — it is itself unused
  // (warning 0001), so the reference has to sit in live code.
  ignore(@async_fs.unimplemented)
  let stamp = mtsc_js_stat_mtime(path)
  if stamp.length() < 2 {
    return None
  }
  Some((stamp[0].to_int64(), stamp[1].to_int()))
}

///|
/// `[seconds, nanos]` for `path`, or `[]` when it cannot be stat'd.
///
/// An empty array rather than a thrown error, because a watched file
/// disappearing is an ordinary answer the caller turns into "changed",
/// and a directory is stat'able but is not a file we can compile.
///
/// `mtime` comes back in whole seconds plus nanoseconds to match the
/// native arm's `(Int64, Int)` exactly — `mtimeMs` alone loses
/// sub-millisecond resolution, and a rebuild triggered by an editor
/// that writes twice inside one millisecond is the case that needs it.
/// `mtimeNs` is a BigInt, so the nanosecond remainder is taken from it
/// when present and derived from `mtimeMs` when it is not.
///
/// `process.getBuiltinModule` is how the module is obtained, and that
/// is not a style choice. This bundle is an IIFE in a `.js` file, and
/// the repo's own `package.json` says `"type": "module"`, so Node loads
/// it as ESM — where `require` is NOT defined. Measured: the first
/// version of this body used `require("node:fs")` and a probe under ESM
/// gives `ReferenceError: require is not defined`, which the `catch`
/// below would have swallowed into `[]` for every file, leaving
/// `--watch` polling forever and never detecting a change. That is the
/// fail-open direction, so it is the one worth a measurement rather
/// than an assumption. `getBuiltinModule` is sync and works from both
/// module systems (Node 22.3 / 20.16 and up); `require` stays as the
/// fallback for an older Node loading this as CommonJS.
#cfg(target="js")
extern "js" fn mtsc_js_stat_mtime(path : String) -> FixedArray[Double] =
  #| function(path) {
  #|   try {
  #|     let fs = globalThis.__mtsc_node_fs;
  #|     if (fs === undefined) {
  #|       fs =
  #|         (typeof process !== "undefined" &&
  #|          typeof process.getBuiltinModule === "function")
  #|           ? process.getBuiltinModule("node:fs")
  #|           : (typeof require === "function" ? require("node:fs") : null);
  #|       globalThis.__mtsc_node_fs = fs;
  #|     }
  #|     if (!fs) return [];
  #|     const st = fs.statSync(path);
  #|     if (!st.isFile()) return [];
  #|     const seconds = Math.floor(st.mtimeMs / 1000);
  #|     const nanos = (st.mtimeNs !== undefined && st.mtimeNs !== null)
  #|       ? Number(BigInt(st.mtimeNs) % 1000000000n)
  #|       : Math.round((st.mtimeMs - seconds * 1000) * 1e6);
  #|     return [seconds, nanos];
  #|   } catch (e) {
  #|     return [];
  #|   }
  #| }

///|
/// Stamp every path in `paths`.
///
/// ONE definition rather than a per-target pair, and the annotation is
/// the price. On `js` the stamp read above is synchronous, so nothing in
/// this body awaits and the compiler correctly calls the `async` here
/// useless (warning 0067) — but the signature has to match the native
/// arm or every caller up the chain needs its own per-target variant,
/// which is the one-rule-in-several-places defect this repo keeps
/// paying for. Suppressing that one diagnostic at this one declaration
/// is the smaller cost than duplicating the loop; it is emphatically
/// not the package-wide `warnings = "-00.."` that CLAUDE.md records as
/// the way a gate stops being a gate.
#warnings("-unused_async")
async fn mtsc_watch_stamps(paths : Array[String]) -> Map[String, (Int64, Int)?] {
  let out : Map[String, (Int64, Int)?] = Map([])
  for p in paths {
    out[p] = mtsc_watch_stamp(p)
  }
  out
}

///|
/// Has any watched file changed since `previous`?
fn mtsc_watch_changed(
  previous : Map[String, (Int64, Int)?],
  current : Map[String, (Int64, Int)?],
) -> Bool {
  if previous.length() != current.length() {
    return true
  }
  for path, stamp in current {
    match previous.get(path) {
      // A path the previous pass did not have at all.
      None => return true
      Some(before) =>
        match (before, stamp) {
          (None, None) => ()
          (Some(a), Some(b)) => if a.0 != b.0 || a.1 != b.1 { return true }
          // Appeared or disappeared.
          _ => return true
        }
    }
  }
  false
}

///|
/// Every file the program reads, for one run of the entries.
///
/// In bundle mode this is the import graph, which is why it comes from
/// the loader rather than from the entry list: watching only the named
/// entries would miss every file they import, which is nearly the whole
/// program.
///
/// The walk here is the loader's, so the set is exactly what the compile
/// read — a second, independent walk could disagree with it, and a
/// watcher that disagrees with its compiler misses rebuilds.
async fn mtsc_watch_program_files(
  opts : MtscOptions,
  entries : Array[String],
) -> Array[String] {
  let out : Array[String] = []
  let seen : Map[String, Bool] = Map([])
  fn add(p : String) -> Unit {
    if !seen.contains(p) {
      seen[p] = true
      out.push(p)
    }
  }

  for entry in entries {
    add(entry)
    if !opts.bundle {
      continue
    }
    let files : Map[String, String] = Map([])
    let aliases : Map[String, String] = Map([])
    let type_props : Map[String, Bool] = Map([])
    let parsed : Map[String, @ast.TsModuleBlock] = Map([])
    let parse_split : Array[Double] = []
    let edges : Array[@mtsc_core.MtscModuleEdge] = []
    match
      mtsc_load_bundle_files(
        entry,
        files,
        aliases,
        opts.externals,
        type_props,
        false,
        parse_split,
        parsed,
        edges,
      ) {
      Ok(_) =>
        for path in files.keys() {
          if mtsc_is_module_path(path) || path.has_suffix(".d.ts") {
            add(path)
          }
        }
      // A load that failed still leaves the entry watched, so fixing the
      // file that broke it triggers the retry.
      Err(_) => ()
    }
  }
  out
}

///|
/// Compile, then recompile whenever a watched file changes.
///
/// Never exits on a failed compile — that is the whole point of the
/// mode, and it is why `mtsc_compile_entry` reports failure by returning
/// rather than by ending the process.
async fn mtsc_watch_loop(opts : MtscOptions, entries : Array[String]) -> Unit {
  // The resolution caches in `main.mbt` are memoized for the lifetime of
  // a process, on the stated assumption that "a compile is one process
  // over a snapshot of the tree, so nothing here can go stale within a
  // run". Watch mode breaks that assumption: the point is that the tree
  // changes. So every pass clears them, and the cost is per pass rather
  // than per run.
  let mut first = true
  let mut stamps : Map[String, (Int64, Int)?] = Map([])
  while true {
    if !first {
      let watched : Array[String] = []
      for path in stamps.keys() {
        watched.push(path)
      }
      let current = mtsc_watch_stamps(watched)
      if !mtsc_watch_changed(stamps, current) {
        @async.sleep(MTSC_WATCH_INTERVAL_MS)
        continue
      }
      println("mtsc: file change detected. Starting incremental compilation...")
      mtsc_clear_resolution_caches()
    }
    first = false
    let failed = mtsc_compile_all(opts, entries)
    // `tsc --watch`'s own summary line, so a watching human gets the
    // same signal from either tool.
    if failed == 0 {
      println("Found 0 errors. Watching for file changes.")
    } else if failed == 1 {
      println("Found errors in 1 file. Watching for file changes.")
    } else {
      println("Found errors in \{failed} files. Watching for file changes.")
    }
    stamps = mtsc_watch_stamps(mtsc_watch_program_files(opts, entries))
    // A watcher never exits, so nothing else ever flushes stdout. See
    // `mtsc_flush_stdout`: without this, `mtsc --watch > build.log`
    // leaves the log empty while the compile is working correctly.
    mtsc_flush_stdout()
    @async.sleep(MTSC_WATCH_INTERVAL_MS)
  }
}
