// The `mtsc` option layer: a superset of `tsc` / `tsgo`'s command line.
//
// "Superset" is a claim with three tiers behind it, and the third is the
// one that makes the first two safe to make:
//
//   HONOURED  — the option maps onto behaviour mtsc really has.
//   ACCEPTED  — mtsc understands the option, has no behaviour for it, and
//               SAYS SO once per run. A pipeline built around `tsc` passes
//               `--target es2020 --module esnext --strict`; hard-failing
//               there would make the superset claim useless, and silently
//               accepting it would be a wrong answer with no symptom.
//   REJECTED  — not a `tsc` option and not an mtsc option. Exit non-zero.
//
// The middle tier is the whole design. Every other compiler that claims
// `tsc` compatibility picks one of the two extremes, and both are worse:
// rejecting means the flag vocabulary can never be shared, accepting
// silently means `--strict false` looks obeyed while the checker runs
// strictly anyway.
//
// Option NAMES are matched case-insensitively with `-` and `_` removed,
// so `--noEmit`, `--no-emit`, `--noemit` and `--NoEmit` are one option.
// That is a strict superset of what `tsc` itself does (it lowercases the
// name and stops there), and it is what lets mtsc's own kebab-case
// history (`--no-check`, `--jsx-import-source`) and `tsc`'s camelCase
// spelling (`--noCheck`, `--jsxImportSource`) name the same flag without
// two tables that can disagree.

///|
/// `tsc`'s exit code for "diagnostics were reported and no output was
/// written", so a caller's `if mtsc ...; then` keeps meaning what it
/// meant under `tsc`.
///
/// The full set `tsc` uses is 0 success, 1 diagnostics with outputs
/// skipped, 2 diagnostics with outputs generated anyway. Only 0 and 1
/// are reachable here — a failing check stops the emit, and `--noCheck`
/// skips the check rather than demoting it, so there is no path that
/// reports a diagnostic and still writes — and a constant for a code
/// nothing can return would be a claim about behaviour mtsc does not
/// have.
///
/// `tsc` reports a bad command line as a diagnostic and exits 1 as well,
/// which is why there is no separate usage code. mtsc used to exit 0 on
/// an unknown option, so a typo in a build script was invisible.
const MTSC_EXIT_DIAGNOSTICS : Int = 1

///|
/// Canonical form of an option name: leading dashes stripped, ASCII
/// lowercased, `-` and `_` removed.
///
/// The dash removal is deliberate and is what makes one table serve both
/// spellings. It can only merge two names that differ solely in
/// separators and case, and no two distinct options in either vocabulary
/// do — `--out` / `--outDir` stay apart because they differ in letters,
/// not in punctuation.
fn mtsc_normalize_option(raw : String) -> String {
  let mut start = 0
  while start < raw.length() && raw[start] == '-' {
    start = start + 1
  }
  let out = StringBuilder()
  for i in start..<raw.length() {
    // A MoonBit `String` indexes UTF-16 code units, so the character has
    // to come back through `to_int()`; an option name is ASCII, which is
    // what makes that safe here.
    let code = raw[i].to_int()
    if code == '-'.to_int() || code == '_'.to_int() {
      continue
    }
    let lowered = if code >= 'A'.to_int() && code <= 'Z'.to_int() {
      code + 32
    } else {
      code
    }
    out.write_char(lowered.unsafe_to_char())
  }
  out.to_string()
}

///|
/// Split `--name=value` into its halves. Returns `None` when there is no
/// `=`, so the caller falls back to reading the next argv element.
///
/// `tsc` takes only the two-token form; accepting `=` as well costs
/// nothing and is what every other bundler's users expect.
fn mtsc_split_inline_value(arg : String) -> (String, String)? {
  match arg.find("=") {
    Some(i) => Some((arg[0:i].to_owned(), arg[i + 1:].to_owned()))
    None => None
  }
}

///|
/// Options that consume a value, by canonical name. Kept as one
/// predicate rather than per-arm `i + 1` arithmetic so a new value-taking
/// option cannot be added without deciding this question.
fn mtsc_option_takes_value(name : String) -> Bool {
  match name {
    // mtsc's own
    "out"
    | "o"
    | "external"
    | "disablephase"
    | "jsxruntime"
    | "jsximportsource"
    | "jsxfactory"
    | "jsxfragmentfactory" => true
    // tsc's, honoured
    "outfile" | "outdir" | "project" | "p" | "jsx" | "declarationdir" => true
    // tsc's, accepted with no effect — they still have to consume their
    // value, or it is read as an input file. `mtsc --target es2020 a.ts`
    // would otherwise compile a file called `es2020`.
    "target"
    | "t"
    | "module"
    | "m"
    | "moduleresolution"
    | "lib"
    | "rootdir"
    | "rootdirs"
    | "baseurl"
    | "paths"
    | "types"
    | "typeroots"
    | "tsbuildinfofile"
    | "newline"
    | "locale"
    | "charset"
    | "maxnodemodulejsdepth"
    | "reactnamespace"
    | "generatetrace"
    | "moduledetection"
    | "importsnotusedasvalues"
    | "jsxfrag"
    | "plugins"
    | "watchfile"
    | "watchdirectory"
    | "fallbackpolling"
    | "excludedirectories"
    | "excludefiles" => true
    _ => false
  }
}

///|
/// A `tsc` option mtsc understands and has no behaviour for. Listed
/// rather than inferred from "everything left over", because the leftover
/// set is exactly where a typo has to land.
///
/// Several of these are honest near-misses worth naming. `--strict` and
/// the strict family cannot be honoured because `@mtsc_core.collect_type_issues`
/// takes a source and a JSX flag and nothing else — strictness is read
/// per-file from the module's own directives — so wiring the flag through
/// means changing that API rather than this table. `--target` / `--module`
/// cannot be honoured because mtsc emits one level (ESM, current syntax)
/// and does not downlevel.
fn mtsc_option_accepted_no_effect(name : String) -> Bool {
  match name {
    "target"
    | "t"
    | "module"
    | "m"
    | "moduleresolution"
    | "lib"
    | "strict"
    | "noimplicitany"
    | "strictnullchecks"
    | "strictfunctiontypes"
    | "strictbindcallapply"
    | "strictpropertyinitialization"
    | "strictbuiltiniteratorreturn"
    | "noimplicitthis"
    | "usedefineforclassfields"
    | "alwaysstrict"
    | "nounusedlocals"
    | "nounusedparameters"
    | "exactoptionalpropertytypes"
    | "noimplicitreturns"
    | "nofallthroughcasesinswitch"
    | "nouncheckedindexedaccess"
    | "noimplicitoverride"
    | "nopropertyaccessfromindexsignature"
    | "allowunusedlabels"
    | "allowunreachablecode"
    | "incremental"
    | "composite"
    | "tsbuildinfofile"
    | "removecomments"
    | "importhelpers"
    | "downleveliteration"
    | "esmoduleinterop"
    | "allowjs"
    | "checkjs"
    | "skiplibcheck"
    | "skipdefaultlibcheck"
    | "rootdir"
    | "rootdirs"
    | "baseurl"
    | "paths"
    | "types"
    | "typeroots"
    | "allowsyntheticdefaultimports"
    | "allowumdglobalaccess"
    | "allowarbitraryextensions"
    | "allowimportingtsextensions"
    | "forceconsistentcasinginfilenames"
    | "isolatedmodules"
    | "isolateddeclarations"
    | "verbatimmodulesyntax"
    | "resolvejsonmodule"
    | "resolvepackagejsonexports"
    | "resolvepackagejsonimports"
    | "newline"
    | "preserveconstenums"
    | "preservesymlinks"
    | "preservewatchoutput"
    | "declarationmap"
    | "declarationdir"
    | "inlinesourcemap"
    | "inlinesources"
    | "sourceroot"
    | "maproot"
    | "diagnostics"
    | "extendeddiagnostics"
    | "generatetrace"
    | "noerrortruncation"
    | "explainfiles"
    | "traceresolution"
    | "locale"
    | "charset"
    | "experimentaldecorators"
    | "emitdecoratormetadata"
    | "emitbom"
    | "stripinternal"
    | "notemitonerror"
    | "noemitonerror"
    | "noemithelpers"
    | "nolib"
    | "noresolve"
    | "suppressexcesspropertyerrors"
    | "suppressimplicitanyindexerrors"
    | "keyofstringsonly"
    | "maxnodemodulejsdepth"
    | "reactnamespace"
    | "jsxfrag"
    | "moduledetection"
    | "importsnotusedasvalues"
    | "plugins"
    | "assumechangesonlyaffectdirectdependencies"
    | "disablesizelimit"
    | "disablesourceofprojectreferenceredirect"
    | "disablesolutionsearching"
    | "disablereferencedprojectload"
    | "erasablesyntaxonly"
    | "libreplacement"
    | "watchfile"
    | "watchdirectory"
    | "fallbackpolling"
    | "synchronouswatchdirectory"
    | "excludedirectories"
    | "excludefiles" => true
    _ => false
  }
}

///|
priv struct MtscOptions {
  // Every input the command line named. `tsc` takes a list; mtsc's
  // pipeline is single-entry, so a list is compiled entry by entry.
  inputs : Array[String]
  mut out : String?
  // `--outDir`. With more than one input, or with `--outDir` and no
  // `--out`, this is where each entry's JavaScript lands.
  mut out_dir : String?
  // `-p` / `--project`: a directory holding a `tsconfig.json`, or the
  // config path itself. A bare `mtsc` with no inputs looks for
  // `tsconfig.json` in the working directory, the way `tsc` does.
  mut project : String?
  mut bundle : Bool
  mut treeshake : Bool
  mut fold : Bool
  mut minify : Bool
  // Library-mode opt-in. When `true`, every property name that
  // appears in an interface / type alias / class declaration is
  // added to the mangler's reserved set so downstream consumers
  // can still type-check against the emitted bundle. Off by
  // default because plain `--bundle` is self-contained.
  mut reserve_typed_props : Bool
  // Selective library mode: reserve only the property names
  // reachable from the ENTRY module's `export` declarations.
  // Internal helper types declared in the entry (or elsewhere)
  // are still fair game to mangle. External IO surface
  // (`console`, `fetch`, `JSON`, etc.) stays reserved via the
  // built-in globals list in `mangle_safety.mbt`. Off by default;
  // takes precedence over `--reserve-typed-props` when both are set.
  mut reserve_entry_exports : Bool
  // Emit a companion `.d.ts` next to the JS output. Contains only
  // the entry module's exported type surface — internal helper
  // types are omitted. Requires `--bundle`. `tsc`'s `--declaration`
  // / `-d` is the same request and sets this.
  mut dts : Bool
  // `--emitDeclarationOnly`: write the `.d.ts` and skip the JavaScript.
  mut dts_only : Bool
  // `--noEmit`: type-check and write nothing. This is what `tsc` does
  // by far the most often in CI, and mtsc had no spelling for it — the
  // only way to check without emitting was the separate `tscheck`
  // binary, whose single-file semantics are a different question.
  mut no_emit : Bool
  // Print a warning when a getter's body contains a direct side
  // effect (assignment, call to an impure function, `++` / `--`,
  // etc). Getters in JS are conventionally pure; an impure one
  // is almost always a bug. Off by default to keep output quiet.
  mut warn_impure_getters : Bool
  // Report reflection in the input that no optimization can see
  // through — `Reflect.ownKeys` and friends enumerate NON-enumerable
  // properties, which is exactly what a class prototype method is, so
  // one call anywhere keeps every method of every class in the bundle.
  //
  // On by default, unlike `--warn-impure-getters`, because the author
  // is the only one who can act on it and should not have to know a
  // flag exists to find out. Suppressed when the JS itself is going to
  // stdout: there the diagnostic would land inside the program.
  // `--warn-reflection` forces it on even then, `--no-warn-reflection`
  // off.
  mut warn_reflection : Bool?
  // Bare specifiers the user wants left as `import … from "<spec>"`
  // in the emitted bundle. Anything not on this list is resolved
  // through node_modules / tsconfig paths and inlined when found.
  externals : Map[String, Bool]
  mut mangle : Bool
  mut mangle_properties : Bool
  // `--explain-mangle`: print why each minify decision went the way it
  // did instead of only doing it. Implies the mangle passes, since a
  // decision has to be made before it can be explained.
  mut explain_mangle : Bool
  // `--verify`: re-parse the emitted bundle and report any name it
  // reads that nothing declares. See `docs/type-aware-dce.md` (E1).
  mut verify : Bool
  // `--disable-phase <name>`: run without a named pipeline phase, so a
  // size delta can be attributed to it. `--timing` names every phase.
  disabled_phases : Map[String, Bool]
  mut mangle_properties_shape_color : Bool
  // `--no-check` / `tsc`'s `--noCheck`: skip type-checking. The gate
  // exists because a type error usually means the program is wrong, but
  // it also makes the whole pipeline unreachable for input that is not
  // TypeScript in the first place — a published `.js` bundle, where an
  // object literal grows properties at runtime and every such site reads
  // as an error.
  //
  // It SKIPS rather than demotes. The checker is ~95% of a large
  // compile (29.4 s of 30.6 s on `checker.ts`), and once the caller has
  // said diagnostics must not stop the emit, running it buys output
  // nobody acts on. `mtsc check` is the way to see diagnostics without
  // an abort.
  mut no_check : Bool
  // `--timing`: report wall time per pipeline phase. The compile is
  // superlinear in input size and a twenty-pass pipeline gives a guess
  // nothing to stand on, so the passes report instead.
  mut timing : Bool
  mut sourcemap : Bool
  mut jsx_runtime : String?
  mut jsx_import_source : String?
  mut jsx_factory : String?
  mut jsx_fragment_factory : String?
  mut jsx_dev : Bool
  mut help : Bool
  mut version : Bool
  // `--watch` / `-w`: recompile when an input changes.
  mut watch : Bool
  // `--init`: write a starter `tsconfig.json`.
  mut init : Bool
  // `--showConfig`: print the resolved configuration and exit.
  mut show_config : Bool
  // `--listFiles` / `--listFilesOnly`: name every file in the program.
  mut list_files : Bool
  mut list_files_only : Bool
  // `tsc` options mtsc parsed and has no behaviour for, in the order
  // they were given. Reported once so an inherited `tsc` command line
  // does not quietly mean something narrower than it says.
  ignored : Array[String]
}

///|
fn mtsc_options_new() -> MtscOptions {
  {
    inputs: [],
    out: None,
    out_dir: None,
    project: None,
    bundle: false,
    treeshake: false,
    fold: false,
    minify: false,
    reserve_typed_props: false,
    reserve_entry_exports: false,
    dts: false,
    dts_only: false,
    no_emit: false,
    warn_impure_getters: false,
    warn_reflection: None,
    externals: {},
    mangle: false,
    mangle_properties: false,
    explain_mangle: false,
    verify: false,
    disabled_phases: {},
    mangle_properties_shape_color: false,
    no_check: false,
    timing: false,
    sourcemap: false,
    jsx_runtime: None,
    jsx_import_source: None,
    jsx_factory: None,
    jsx_fragment_factory: None,
    jsx_dev: false,
    help: false,
    version: false,
    watch: false,
    init: false,
    show_config: false,
    list_files: false,
    list_files_only: false,
    ignored: [],
  }
}

///|
/// Outcome of reading a boolean option's optional value.
///
/// `tsc` lets every boolean take an explicit `true` / `false`
/// (`--strict false`), and the token is optional. So the value can only
/// be consumed when it IS one of those two words — consuming
/// unconditionally would eat the input file in `mtsc --noEmit a.ts`.
fn mtsc_read_bool_value(argv : Array[String], next : Int) -> (Bool, Bool) {
  if next < argv.length() {
    match argv[next] {
      "true" => return (true, true)
      "false" => return (false, true)
      _ => ()
    }
  }
  (true, false)
}

///|
/// Map `tsc`'s `--jsx` setting onto mtsc's JSX runtime selection.
///
/// `preserve` and `react-native` leave JSX in the output, which this
/// pipeline cannot do — it always lowers — so they map to the automatic
/// runtime and are reported rather than honoured. That is the same
/// decision `mtsc_build_jsx_config` already makes when it reads the
/// setting out of tsconfig; the difference here is that a command line
/// asked for it explicitly, so it gets a line of output.
fn mtsc_apply_jsx_setting(opts : MtscOptions, value : String) -> Unit {
  match value {
    "react" => opts.jsx_runtime = Some("classic")
    "react-jsx" => opts.jsx_runtime = Some("automatic")
    "react-jsxdev" => {
      opts.jsx_runtime = Some("automatic")
      opts.jsx_dev = true
    }
    "preserve" | "react-native" => {
      opts.jsx_runtime = Some("automatic")
      opts.ignored.push("--jsx \{value} (mtsc always lowers JSX)")
    }
    _ => opts.ignored.push("--jsx \{value} (unrecognized; using the automatic runtime)")
  }
}

///|
/// Parse the command line into `MtscOptions`.
///
/// `start` is the index of the first option, so the caller can hand this
/// an argv whose leading elements it has already consumed.
fn mtsc_parse_args(
  argv : Array[String],
  start : Int,
) -> Result[MtscOptions, String] {
  let opts = mtsc_options_new()
  let mut i = start
  while i < argv.length() {
    let raw = argv[i]
    // A bare `-` or anything not starting with `-` is an input path.
    if !raw.has_prefix("-") || raw == "-" {
      opts.inputs.push(raw)
      i = i + 1
      continue
    }
    // `--name=value` is split before normalization so the name half
    // normalizes on its own.
    let (name_token, inline_value) = match mtsc_split_inline_value(raw) {
      Some((n, v)) => (n, Some(v))
      None => (raw, None)
    }
    let name = mtsc_normalize_option(name_token)
    // Resolve this option's value, from `=value` or the next token.
    let mut consumed_next = false
    let value : String? = match inline_value {
      Some(v) => Some(v)
      None =>
        if mtsc_option_takes_value(name) {
          if i + 1 >= argv.length() {
            return Err("missing value for \{raw}")
          }
          consumed_next = true
          Some(argv[i + 1])
        } else {
          None
        }
    }
    // One accessor for the resolved value, so an arm cannot read a value
    // this function did not decide to consume.
    fn need_value() -> Result[String, String] {
      match value {
        Some(v) => Ok(v)
        None => Err("missing value for \{raw}")
      }
    }

    match name {
      // ----------------------------------------------------- help / info
      "help" | "h" | "all" | "?" => opts.help = true
      "version" | "v" => opts.version = true
      "init" => opts.init = true
      "showconfig" => opts.show_config = true
      "listfiles" => opts.list_files = true
      "listfilesonly" => {
        opts.list_files = true
        opts.list_files_only = true
      }
      // `--pretty` controls colour, and mtsc emits none either way, so
      // there is nothing to honour and nothing lost.
      "pretty" | "nocolors" | "nocolor" => ()
      // ------------------------------------------------------------ paths
      "out" | "o" | "outfile" =>
        match need_value() {
          Ok(v) => opts.out = Some(v)
          Err(e) => return Err(e)
        }
      "outdir" =>
        match need_value() {
          Ok(v) => opts.out_dir = Some(v)
          Err(e) => return Err(e)
        }
      "project" | "p" =>
        match need_value() {
          Ok(v) => opts.project = Some(v)
          Err(e) => return Err(e)
        }
      // ------------------------------------------------- emit selection
      "noemit" => {
        let (v, used) = mtsc_read_bool_value(argv, i + 1)
        opts.no_emit = v
        if used && inline_value is None {
          consumed_next = true
        }
      }
      "declaration" | "d" => {
        let (v, used) = mtsc_read_bool_value(argv, i + 1)
        opts.dts = v
        if v {
          opts.bundle = true
        }
        if used && inline_value is None {
          consumed_next = true
        }
      }
      "emitdeclarationonly" => {
        opts.dts = true
        opts.dts_only = true
        opts.bundle = true
      }
      "dts" => {
        opts.dts = true
        opts.bundle = true
      }
      "sourcemap" => {
        let (v, used) = mtsc_read_bool_value(argv, i + 1)
        opts.sourcemap = v
        if used && inline_value is None {
          consumed_next = true
        }
      }
      // ----------------------------------------------------- type-checking
      "nocheck" => {
        let (v, used) = mtsc_read_bool_value(argv, i + 1)
        opts.no_check = v
        if used && inline_value is None {
          consumed_next = true
        }
      }
      // ------------------------------------------------------------ watch
      "watch" | "w" => opts.watch = true
      // `--build` needs project references and an up-to-date check, and
      // mtsc has neither. Saying so beats accepting it and compiling
      // something else: `tsc -b` on a solution file is not a request to
      // compile that file.
      "build" | "b" =>
        return Err(
          "--build is not supported (mtsc has no project references); compile each project with -p",
        )
      // -------------------------------------------------------------- JSX
      "jsx" =>
        match need_value() {
          Ok(v) => mtsc_apply_jsx_setting(opts, v)
          Err(e) => return Err(e)
        }
      "jsxruntime" =>
        match need_value() {
          Ok(v) => opts.jsx_runtime = Some(v)
          Err(e) => return Err(e)
        }
      "jsximportsource" =>
        match need_value() {
          Ok(v) => opts.jsx_import_source = Some(v)
          Err(e) => return Err(e)
        }
      "jsxfactory" =>
        match need_value() {
          Ok(v) => opts.jsx_factory = Some(v)
          Err(e) => return Err(e)
        }
      "jsxfragmentfactory" =>
        match need_value() {
          Ok(v) => opts.jsx_fragment_factory = Some(v)
          Err(e) => return Err(e)
        }
      "jsxdev" => opts.jsx_dev = true
      // --------------------------------------------- mtsc's own pipeline
      "bundle" => opts.bundle = true
      "treeshake" => {
        opts.treeshake = true
        opts.bundle = true
      }
      "minify" => opts.minify = true
      "fold" => {
        opts.fold = true
        opts.bundle = true
      }
      "reservetypedprops" => opts.reserve_typed_props = true
      "reserveentryexports" => opts.reserve_entry_exports = true
      "warnimpuregetters" => opts.warn_impure_getters = true
      "warnreflection" => opts.warn_reflection = Some(true)
      "nowarnreflection" => opts.warn_reflection = Some(false)
      "external" =>
        match need_value() {
          Ok(v) => {
            for part in v.split(",") {
              let spec = part.to_owned().trim().to_owned()
              if spec != "" {
                opts.externals[spec] = true
              }
            }
          }
          Err(e) => return Err(e)
        }
      "mangle" => opts.mangle = true
      // Property mangling implies `--bundle`, the way `--treeshake` and
      // `--fold` already do — and for a stronger reason than they have.
      // The escape analysis (both doors, the wildcard, the whole safety
      // story) lives in `bundle_modules`. The single-file path has none
      // of it, so `--mangle-properties` there renamed whatever it liked,
      // including a CJS module's `exports.foo` and the keys of an
      // exported object. A flag whose only safe form is one path should
      // select that path rather than trust the user to.
      "mangleproperties" => {
        opts.mangle = true
        opts.mangle_properties = true
        opts.bundle = true
      }
      "explainmangle" => {
        opts.mangle = true
        opts.mangle_properties = true
        opts.explain_mangle = true
        opts.bundle = true
      }
      "manglepropertiesshapecolor" => {
        opts.mangle = true
        opts.mangle_properties = true
        opts.mangle_properties_shape_color = true
        opts.bundle = true
      }
      "verify" => opts.verify = true
      "disablephase" =>
        match need_value() {
          Ok(v) => {
            for part in v.split(",") {
              let phase = part.to_owned().trim().to_owned()
              if phase != "" {
                opts.disabled_phases[phase] = true
              }
            }
          }
          Err(e) => return Err(e)
        }
      "timing" => {
        opts.timing = true
        opts.bundle = true
      }
      // ------------------------------------------- accepted, no effect
      _ =>
        if mtsc_option_accepted_no_effect(name) {
          // A boolean in this tier may still carry `true` / `false`.
          if inline_value is None && !mtsc_option_takes_value(name) {
            let (_, used) = mtsc_read_bool_value(argv, i + 1)
            if used {
              consumed_next = true
            }
          }
          opts.ignored.push(name_token)
        } else {
          return Err("unknown option: \{raw}")
        }
    }
    i = i + (if consumed_next { 2 } else { 1 })
  }
  Ok(opts)
}

///|
fn mtsc_print_usage() -> Unit {
  println("Usage: mtsc [options] [files...]")
  println("       mtsc -p <tsconfig.json|dir> [options]")
  println("       mtsc <command> [args...]")
  println("")
  println(
    "Type-check TypeScript / TSX and compile it to JavaScript. A superset of the",
  )
  println(
    "`tsc` / `tsgo` command line: tsc option names are accepted, and the ones mtsc",
  )
  println("has no behaviour for are reported rather than silently ignored.")
  println("")
  println("Commands:")
  println(
    "  check <file.ts>           Report checker diagnostics for one file (no emit, always exits 0)",
  )
  println(
    "  conformance               Score the checker against the pinned TypeScript conformance corpus",
  )
  println(
    "  bridge <verb>             Generate a MoonBit bridge from TypeScript (`mtsc bridge --help`)",
  )
  println(
    "  pkg <verb>                Generate a TypeScript package from MoonBit (`mtsc pkg --help`)",
  )
  println("")
  println("tsc-compatible options:")
  println(
    "  --project, -p <path>      Compile the project at <path> (a directory or a tsconfig.json)",
  )
  println(
    "  --noEmit                  Type-check and write nothing",
  )
  println(
    "  --noCheck                 Skip type-checking entirely (also spelled --no-check)",
  )
  println(
    "  --outFile, --out, -o <f>  Write JavaScript to <f> (default: stdout)",
  )
  println("  --outDir <dir>            Write each input's JavaScript under <dir>")
  println(
    "  --declaration, -d         Emit a companion .d.ts (also spelled --dts)",
  )
  println("  --emitDeclarationOnly     Emit the .d.ts and skip the JavaScript")
  println("  --sourceMap               Emit <out>.map alongside the JavaScript")
  println(
    "  --jsx <mode>              react | react-jsx | react-jsxdev (preserve is lowered)",
  )
  println(
    "  --jsxImportSource <pkg>   Override the jsx-runtime import source",
  )
  println("  --jsxFactory <fn>         Classic-runtime element factory")
  println("  --jsxFragmentFactory <fn> Classic-runtime fragment factory")
  println("  --watch, -w               Recompile when an input changes")
  println("  --init                    Write a starter tsconfig.json")
  println("  --showConfig              Print the resolved configuration and exit")
  println("  --listFiles               Name every file in the program")
  println("  --listFilesOnly           Name every file in the program and stop")
  println("  --version, -v             Print the version")
  println("  --help, -h                Show this help")
  println("")
  println("mtsc options:")
  println(
    "  --bundle                  Follow relative imports from the entry and emit one bundle",
  )
  println(
    "  --treeshake               Drop top-level declarations unreached from any live stmt (implies --bundle)",
  )
  println(
    "  --minify                  Suppress indentation / newlines / optional whitespace",
  )
  println(
    "  --fold                    Constant-fold identity arithmetic and dead branches (implies --bundle)",
  )
  println(
    "  --external <spec>         Keep this bare-specifier import external (repeatable; comma-separated also OK)",
  )
  println(
    "  --reserve-typed-props     Reserve every property declared in an interface / type alias / class (library mode)",
  )
  println(
    "  --reserve-entry-exports   Reserve only property names reachable from the entry's exports (library mode, selective)",
  )
  println(
    "  --warn-impure-getters     Warn when a class getter body has a direct side effect (assign, call, mutation)",
  )
  println("  --mangle                  Rename non-exported local identifiers")
  println(
    "  --mangle-properties       Also rename non-reserved property keys (implies --bundle)",
  )
  println(
    "  --warn-reflection         Report reflection that blocks an optimization (default on when -o is given)",
  )
  println("  --no-warn-reflection      Silence the reflection report")
  println(
    "  --explain-mangle          Report why each minify decision went the way it did",
  )
  println(
    "  --mangle-properties-shape-color  Use shape-coloring property rename (opt-in, experimental)",
  )
  println(
    "  --verify                  Re-parse the emitted bundle and report any name nothing declares",
  )
  println(
    "  --disable-phase <name>    Run without a named pipeline phase, to attribute bytes to it (repeatable; --timing lists the names)",
  )
  println(
    "  --timing                  Report wall time per pipeline phase (implies --bundle)",
  )
  println("")
  println(
    "Option names are matched ignoring case, `-` and `_`, so --noEmit, --no-emit and",
  )
  println("--noemit are one option.")
}

///|
/// Report the `tsc` options this run parsed and did not act on.
///
/// One line, after the option scan and before any work, so the reader
/// sees it next to the command they typed rather than buried under the
/// output. Silence here would be the failure mode this whole tier exists
/// to avoid.
fn mtsc_report_ignored(opts : MtscOptions) -> Unit {
  if opts.ignored.length() == 0 {
    return
  }
  let names : Array[String] = []
  for name in opts.ignored {
    names.push(name)
  }
  println(
    "mtsc: accepted but not honoured: \{names.join(", ")} — mtsc emits current-syntax ESM and type-checks strictly, so these have no effect",
  )
}
