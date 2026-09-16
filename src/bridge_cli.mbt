// The two bridge-generation namespaces of the `mtsc` CLI:
//
//   mtsc bridge <verb>   TypeScript -> MoonBit   (was the `ts2mbt` binary)
//   mtsc pkg    <verb>   MoonBit -> TypeScript   (was the `mbt2ts` binary)
//
// They live in the root `mizchi/ts` package rather than in
// `src/cmd/mtsc/` for two reasons. The unified flows they dispatch to
// (`run_ts_to_mbt_unified_cli`, `run_mbt_to_ts_unified_cli`,
// `run_mbt_to_ts_pkg_cli`) and every `emit_*` entry point are already
// here, so a dispatcher in the cmd package would be a layer of
// indirection over its own dependency; and the help surface stays
// assertable from `src/main_wbtest.mbt`, which is what kept
// `ts2mbt_help_lines` / `mbt2ts_help_lines` public before the merge.
//
// Both entry points take `(args, start)` rather than reading
// `@env.args()` themselves. That is what makes them reachable from a
// subcommand position: `mtsc bridge decl x.d.ts` hands them `start = 2`
// where the old binaries passed `1`.

///|
/// Every verb of `mtsc bridge`, one line each, in help order.
///
/// `all` is the verb the `ts2mbt` binary spelled `bridge`. Under a
/// `bridge` namespace that spelling reads as `mtsc bridge bridge`, so the
/// verb is renamed and the old spelling kept as an accepted alias — a
/// rename that breaks a script is not a consolidation.
pub fn bridge_help_lines() -> Array[String] {
  [
    "  --input <ts-entry> --out <dir> [--module-spec <spec>] [--diagnostics <path>] [--strict] Generate a complete build-backed MoonBit bridge scaffold from a TypeScript entrypoint",
    "  generate [--package-json <path>] [--out <dir>] Generate bridges for every dependency / devDependency listed in package.json",
    "  vendor <pkg> [--module-spec <spec>] [--out <dir>] Resolve a single <pkg> from node_modules and write its bridge sub-package",
    "  decl <ts-entry> [out] Emit MoonBit declare stubs from a TypeScript entrypoint",
    "  ffi <ts-entry> <module-spec> [ffi-out] [bridge-out] Emit MoonBit JS FFI stubs and ESM bridge from a TypeScript entrypoint",
    "  all <ts-entry> <module-spec> [decl-out] [ffi-out] [bridge-out] Emit a full MoonBit bridge bundle from a TypeScript entrypoint",
    "  package <ts-entry> <module-spec> <out-dir> Emit a generated MoonBit bridge package directory",
    "  package-validated <ts-entry> <module-spec> <out-dir> Emit a bridge package with opt-in structural runtime validators",
    "  scaffold <ts-entry> <module-spec> <out-dir> Emit a MoonBit bridge scaffold from a TypeScript entrypoint",
  ]
}

///|
/// Every verb of `mtsc pkg`, one line each, in help order.
///
/// `npm` is the flow the `mbt2ts` binary selected with a bare `--pkg`
/// flag. A flag that picks a whole mode is a verb wearing a flag's
/// spelling, and under a namespace it would have read as
/// `mtsc pkg --pkg`; `--pkg` stays an accepted alias.
pub fn pkg_help_lines() -> Array[String] {
  [
    "  npm [--out <dir>] [--strict] [--no-facade] [--import-rewrites <json>] Build current MoonBit library packages and write an npm-publishable package to ./npm",
    "  --input <pkg-or-mbti> --out <dir> [--diagnostics <path>] [--strict] [--no-facade] [--import-rewrites <json>] Generate a complete build-backed TypeScript package from a MoonBit pkg.generated.mbti",
    "  decl <mbti> [out] Emit TypeScript declarations directly from a MoonBit .mbti interface",
    "  link-config <mbti> [out] Emit MoonBit link.js.exports config from a .mbti interface",
    "  package <mbti> <out-dir> [import-rewrite-json] Emit a recursive TypeScript declaration package from a root .mbti interface",
    "  scaffold <mbti> <out-dir> [import-rewrite-json] Emit build-backed JS/TypeScript scaffold from a MoonBit package interface",
    "  facade-scaffold <mbti> <out-dir> [import-rewrite-json] Emit build-backed JS/TypeScript scaffold plus facade wrappers for omitted local methods",
    "  normalize <ts> [out] Normalize MoonBit-generated TypeScript declarations into clearer .d.ts output",
  ]
}

///|
fn bridge_print_usage() -> Unit {
  println(
    "Usage: mtsc bridge [--input <ts-entry> --out <dir>] [<verb> args...]",
  )
  println("")
  println("Generate MoonBit bridge artifacts from a TypeScript entrypoint.")
  println("")
  println(
    "Recommended: use the unified `--input/--out` flow for build-backed scaffolds.",
  )
  println("Verbs expose individual generation stages.")
  println("")
  println("Verbs:")
  for line in bridge_help_lines() {
    println(line)
  }
}

///|
fn pkg_print_usage() -> Unit {
  println(
    "Usage: mtsc pkg npm [options] | [--input <pkg-or-mbti> --out <dir>] [<verb> args...]",
  )
  println("")
  println(
    "Generate TypeScript declarations and JS-backed packages from a MoonBit interface.",
  )
  println("")
  println(
    "Recommended: use the unified `--input/--out` flow for build-backed scaffolds.",
  )
  println("Verbs expose individual generation stages.")
  println("")
  println("Verbs:")
  for line in pkg_help_lines() {
    println(line)
  }
}

///|
/// Run a verb handler against the parsed positional args. Centralises the
/// per-arm `parse args -> dispatch -> propagate exit code` pipeline so
/// each arm shrinks to a single line.
///
/// `namespace_` is the `bridge` / `pkg` prefix, so the `--help` hint names
/// the command the user actually typed.
async fn bridge_cli_dispatch(
  args : Array[String],
  start : Int,
  namespace_ : String,
  verb : String,
  min_args : Int,
  usage : String,
  print_help : () -> Unit,
  handler : async (Array[String]) -> Bool,
) -> Unit {
  match
    cli_parse_subcommand_args(
      args,
      start,
      min_args,
      usage,
      help_hint="mtsc \{namespace_} \{verb} --help",
    ) {
    HelpRequested => print_help()
    Args(positionals) => if !handler(positionals) { cli_fail("mtsc") }
  }
}

///|
/// Parse `vendor`'s positional + flag arguments into
/// `(pkg_spec, module_spec_override, vendor_root_override)`.
fn bridge_parse_vendor_args(
  args : Array[String],
  start : Int,
) -> (String?, String?, String?) {
  let mut pkg_spec : String? = None
  let mut module_spec : String? = None
  let mut out_dir : String? = None
  let mut idx = start
  while idx < args.length() {
    let arg = args[idx]
    if arg == "--module-spec" || arg == "--runtime-module" {
      if idx + 1 >= args.length() {
        return (None, None, None)
      }
      module_spec = Some(args[idx + 1])
      idx += 2
      continue
    }
    if arg == "--out" || arg == "-o" {
      if idx + 1 >= args.length() {
        return (None, None, None)
      }
      out_dir = Some(args[idx + 1])
      idx += 2
      continue
    }
    if arg.has_prefix("--module-spec=") {
      module_spec = Some(arg["--module-spec=".length():arg.length()].to_owned())
      idx += 1
      continue
    }
    if arg.has_prefix("--out=") {
      out_dir = Some(arg["--out=".length():arg.length()].to_owned())
      idx += 1
      continue
    }
    if arg.has_prefix("-") {
      idx += 1
      continue
    }
    if pkg_spec is None {
      pkg_spec = Some(arg)
    }
    idx += 1
  }
  (pkg_spec, module_spec, out_dir)
}

///|
async fn bridge_run_vendor(args : Array[String], start : Int) -> Unit {
  if start < args.length() && cli_subcommand_is_help(args[start]) {
    bridge_print_usage()
    return
  }
  let (pkg_spec, module_spec, out_dir) = bridge_parse_vendor_args(args, start)
  let pkg = match pkg_spec {
    Some(p) => p
    None => {
      cli_bail(
        "mtsc bridge vendor: expected <pkg> [--module-spec <spec>] [--out <dir>]",
      )
      return
    }
  }
  if !ts2mbt_vendor_package(
      pkg,
      module_spec_override=module_spec,
      vendor_root_override=out_dir,
    ) {
    cli_fail("mtsc")
  }
}

///|
/// Parse `generate`'s flag arguments into `(package_json_path?, vendor_root?)`.
fn bridge_parse_generate_args(
  args : Array[String],
  start : Int,
) -> (String?, String?) {
  let mut pkg_json : String? = None
  let mut out_dir : String? = None
  let mut idx = start
  while idx < args.length() {
    let arg = args[idx]
    if arg == "--package-json" {
      if idx + 1 >= args.length() {
        return (None, None)
      }
      pkg_json = Some(args[idx + 1])
      idx += 2
      continue
    }
    if arg == "--out" || arg == "-o" {
      if idx + 1 >= args.length() {
        return (None, None)
      }
      out_dir = Some(args[idx + 1])
      idx += 2
      continue
    }
    if arg.has_prefix("--package-json=") {
      pkg_json = Some(arg["--package-json=".length():arg.length()].to_owned())
      idx += 1
      continue
    }
    if arg.has_prefix("--out=") {
      out_dir = Some(arg["--out=".length():arg.length()].to_owned())
      idx += 1
      continue
    }
    idx += 1
  }
  (pkg_json, out_dir)
}

///|
async fn bridge_run_generate(args : Array[String], start : Int) -> Unit {
  if start < args.length() && cli_subcommand_is_help(args[start]) {
    bridge_print_usage()
    return
  }
  let (pkg_json, out_dir) = bridge_parse_generate_args(args, start)
  if !ts2mbt_generate_from_package_json(
      package_json_path_override=pkg_json,
      vendor_root_override=out_dir,
    ) {
    cli_fail("mtsc")
  }
}

///|
/// `mtsc bridge …` — the TypeScript -> MoonBit direction.
///
/// `start` is the index of the verb (or of the first `--input`-style flag
/// for the unified flow), so `mtsc bridge decl x.d.ts` passes `2`.
pub async fn run_bridge_cli(args : Array[String], start : Int) -> Unit {
  if start >= args.length() {
    bridge_print_usage()
    return
  }
  if cli_token_is_version(args[start]) {
    cli_print_version("mtsc")
    return
  }
  if args[start].has_prefix("--") || args[start] == "-h" {
    if args[start] == "--help" || args[start] == "-h" {
      bridge_print_usage()
      return
    }
    if !run_ts_to_mbt_unified_cli(args, start, print_help=bridge_print_usage) {
      cli_fail("mtsc")
    }
    return
  }
  let verb = args[start]
  let rest = start + 1
  match verb {
    "scaffold-from-input" =>
      if !run_ts_to_mbt_unified_cli(args, rest, print_help=bridge_print_usage) {
        cli_fail("mtsc")
      }
    "decl" =>
      bridge_cli_dispatch(
        args,
        rest,
        "bridge",
        "decl",
        1,
        "mtsc bridge decl: expected <ts-entry> [out]",
        bridge_print_usage,
        async fn(p) {
          emit_moonbit_decl(
            p[0],
            if p.length() >= 2 {
              Some(p[1])
            } else {
              None
            },
          )
        },
      )
    "ffi" =>
      bridge_cli_dispatch(
        args,
        rest,
        "bridge",
        "ffi",
        2,
        "mtsc bridge ffi: expected <ts-entry> <module-spec> [ffi-out] [bridge-out]",
        bridge_print_usage,
        async fn(p) {
          emit_moonbit_js_ffi(
            p[0],
            p[1],
            if p.length() >= 3 {
              Some(p[2])
            } else {
              None
            },
            if p.length() >= 4 {
              Some(p[3])
            } else {
              None
            },
          )
        },
      )
    // `bridge` is the spelling the `ts2mbt` binary used; keeping it as an
    // alias makes `mtsc bridge bridge …` work, so the script rewrite is a
    // prefix substitution rather than a per-call-site decision.
    "all" | "bridge" =>
      bridge_cli_dispatch(
        args,
        rest,
        "bridge",
        "all",
        2,
        "mtsc bridge all: expected <ts-entry> <module-spec> [decl-out] [ffi-out] [bridge-out]",
        bridge_print_usage,
        async fn(p) {
          emit_moonbit_bridge(
            p[0],
            p[1],
            if p.length() >= 3 {
              Some(p[2])
            } else {
              None
            },
            if p.length() >= 4 {
              Some(p[3])
            } else {
              None
            },
            if p.length() >= 5 {
              Some(p[4])
            } else {
              None
            },
          )
        },
      )
    "package" =>
      bridge_cli_dispatch(
        args,
        rest,
        "bridge",
        "package",
        3,
        "mtsc bridge package: expected <ts-entry> <module-spec> <out-dir>",
        bridge_print_usage,
        async fn(p) { emit_moonbit_bridge_package(p[0], p[1], p[2]) },
      )
    "package-validated" =>
      bridge_cli_dispatch(
        args,
        rest,
        "bridge",
        "package-validated",
        3,
        "mtsc bridge package-validated: expected <ts-entry> <module-spec> <out-dir>",
        bridge_print_usage,
        async fn(p) {
          emit_moonbit_bridge_package(p[0], p[1], p[2], runtime_validation=true)
        },
      )
    "scaffold" =>
      bridge_cli_dispatch(
        args,
        rest,
        "bridge",
        "scaffold",
        3,
        "mtsc bridge scaffold: expected <ts-entry> <module-spec> <out-dir>",
        bridge_print_usage,
        async fn(p) { emit_moonbit_scaffold_from_ts(p[0], p[1], p[2]) },
      )
    "vendor" => bridge_run_vendor(args, rest)
    "generate" => bridge_run_generate(args, rest)
    "--help" | "-h" | "help" => bridge_print_usage()
    "--version" | "-V" => cli_print_version("mtsc")
    _ => {
      println("Unknown `mtsc bridge` verb: \{verb}")
      bridge_print_usage()
      cli_fail("mtsc")
    }
  }
}

///|
/// `mtsc pkg …` — the MoonBit -> TypeScript direction.
///
/// `start` is the index of the verb, so `mtsc pkg decl x.mbti` passes `2`.
pub async fn run_pkg_cli(args : Array[String], start : Int) -> Unit {
  if start >= args.length() {
    pkg_print_usage()
    return
  }
  if cli_token_is_version(args[start]) {
    cli_print_version("mtsc")
    return
  }
  // `npm` is the verb; `--pkg` is the flag the `mbt2ts` binary used to
  // select the same flow, kept so existing invocations keep working.
  if args[start] == "npm" || args[start] == "--pkg" {
    if !run_mbt_to_ts_pkg_cli(args, start + 1, print_help=pkg_print_usage) {
      cli_fail("mtsc")
    }
    return
  }
  if args[start].has_prefix("--") || args[start] == "-h" {
    if args[start] == "--help" || args[start] == "-h" {
      pkg_print_usage()
      return
    }
    if !run_mbt_to_ts_unified_cli(args, start, print_help=pkg_print_usage) {
      cli_fail("mtsc")
    }
    return
  }
  let verb = args[start]
  let rest = start + 1
  match verb {
    "generate" | "scaffold-from-input" =>
      if !run_mbt_to_ts_unified_cli(args, rest, print_help=pkg_print_usage) {
        cli_fail("mtsc")
      }
    "decl" =>
      bridge_cli_dispatch(
        args,
        rest,
        "pkg",
        "decl",
        1,
        "mtsc pkg decl: expected <mbti> [out]",
        pkg_print_usage,
        async fn(p) {
          emit_typescript_decl_from_mbti(
            p[0],
            if p.length() >= 2 {
              Some(p[1])
            } else {
              None
            },
          )
        },
      )
    "link-config" =>
      bridge_cli_dispatch(
        args,
        rest,
        "pkg",
        "link-config",
        1,
        "mtsc pkg link-config: expected <mbti> [out]",
        pkg_print_usage,
        async fn(p) {
          emit_js_link_config_from_mbti(
            p[0],
            if p.length() >= 2 {
              Some(p[1])
            } else {
              None
            },
          )
        },
      )
    "package" =>
      bridge_cli_dispatch(
        args,
        rest,
        "pkg",
        "package",
        2,
        "mtsc pkg package: expected <mbti> <out-dir> [import-rewrite-json]",
        pkg_print_usage,
        async fn(p) {
          emit_typescript_package_from_mbti(
            p[0],
            p[1],
            if p.length() >= 3 {
              Some(p[2])
            } else {
              None
            },
          )
        },
      )
    "scaffold" =>
      bridge_cli_dispatch(
        args,
        rest,
        "pkg",
        "scaffold",
        2,
        "mtsc pkg scaffold: expected <mbti> <out-dir> [import-rewrite-json]",
        pkg_print_usage,
        async fn(p) {
          emit_typescript_scaffold_from_mbti(
            p[0],
            p[1],
            if p.length() >= 3 {
              Some(p[2])
            } else {
              None
            },
          )
        },
      )
    "facade-scaffold" =>
      bridge_cli_dispatch(
        args,
        rest,
        "pkg",
        "facade-scaffold",
        2,
        "mtsc pkg facade-scaffold: expected <mbti> <out-dir> [import-rewrite-json]",
        pkg_print_usage,
        async fn(p) {
          emit_typescript_facade_scaffold_from_mbti(
            p[0],
            p[1],
            if p.length() >= 3 {
              Some(p[2])
            } else {
              None
            },
          )
        },
      )
    "normalize" =>
      bridge_cli_dispatch(
        args,
        rest,
        "pkg",
        "normalize",
        1,
        "mtsc pkg normalize: expected <ts> [out]",
        pkg_print_usage,
        async fn(p) {
          emit_typescript_decl(
            p[0],
            if p.length() >= 2 {
              Some(p[1])
            } else {
              None
            },
          )
        },
      )
    "--help" | "-h" | "help" => pkg_print_usage()
    "--version" | "-V" => cli_print_version("mtsc")
    _ => {
      println("Unknown `mtsc pkg` verb: \{verb}")
      pkg_print_usage()
      cli_fail("mtsc")
    }
  }
}
