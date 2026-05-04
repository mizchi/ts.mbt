///|
fn ts2mbt_print_usage() -> Unit {
  println(
    "Usage: ts2mbt [--input <ts-entry> --out <dir>] [<subcommand> args...]",
  )
  println("")
  println("Generate MoonBit bridge artifacts from a TypeScript entrypoint.")
  println("")
  println(
    "Recommended: use the unified `--input/--out` flow for build-backed scaffolds.",
  )
  println("Subcommands expose individual generation stages.")
  println("")
  println("Subcommands:")
  for line in ts2mbt_help_lines() {
    println(line)
  }
}

///|
/// Help lines for the `ts2mbt` CLI. Exposed so tests can keep the surface
/// stable.
pub fn ts2mbt_help_lines() -> Array[String] {
  [
    "  --input <ts-entry> --out <dir> [--module-spec <spec>] [--diagnostics <path>] [--strict] Generate a complete build-backed MoonBit bridge scaffold from a TypeScript entrypoint",
    "  generate [--package-json <path>] [--out <dir>] Generate bridges for every dependency / devDependency listed in package.json",
    "  vendor <pkg> [--module-spec <spec>] [--out <dir>] Resolve a single <pkg> from node_modules and write its bridge sub-package",
    "  decl <ts-entry> [out] Emit MoonBit declare stubs from a TypeScript entrypoint",
    "  ffi <ts-entry> <module-spec> [ffi-out] [bridge-out] Emit MoonBit JS FFI stubs and ESM bridge from a TypeScript entrypoint",
    "  bridge <ts-entry> <module-spec> [decl-out] [ffi-out] [bridge-out] Emit a full MoonBit bridge bundle from a TypeScript entrypoint",
    "  package <ts-entry> <module-spec> <out-dir> Emit a generated MoonBit bridge package directory",
    "  scaffold <ts-entry> <module-spec> <out-dir> Emit a MoonBit bridge scaffold from a TypeScript entrypoint",
  ]
}

///|
/// Run a subcommand handler against the parsed positional args. Centralises
/// the per-arm `parse args -> dispatch -> propagate exit code` pipeline so
/// each cmd arm shrinks to a single line.
async fn ts2mbt_dispatch(
  args : Array[String],
  start : Int,
  subcommand : String,
  min_args : Int,
  usage : String,
  handler : async (Array[String]) -> Bool,
) -> Unit {
  match
    @ts.cli_parse_subcommand_args(
      args,
      start,
      min_args,
      usage,
      help_hint="ts2mbt \{subcommand} --help",
    ) {
    HelpRequested => ts2mbt_print_usage()
    Args(positionals) => if !handler(positionals) { @ts.cli_fail("ts2mbt") }
  }
}

///|
/// Parse `vendor`'s positional + flag arguments into
/// `(pkg_spec, module_spec_override, vendor_root_override)`.
fn parse_vendor_args(
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
      module_spec = Some(
        arg["--module-spec=".length():arg.length()].to_string(),
      )
      idx += 1
      continue
    }
    if arg.has_prefix("--out=") {
      out_dir = Some(arg["--out=".length():arg.length()].to_string())
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
async fn ts2mbt_run_vendor(args : Array[String], start : Int) -> Unit {
  if start < args.length() && @ts.cli_subcommand_is_help(args[start]) {
    ts2mbt_print_usage()
    return
  }
  let (pkg_spec, module_spec, out_dir) = parse_vendor_args(args, start)
  let pkg = match pkg_spec {
    Some(p) => p
    None => {
      @ts.cli_bail(
        "ts2mbt vendor: expected <pkg> [--module-spec <spec>] [--out <dir>]",
      )
      return
    }
  }
  if !@ts.ts2mbt_vendor_package(
      pkg,
      module_spec_override=module_spec,
      vendor_root_override=out_dir,
    ) {
    @ts.cli_fail("ts2mbt")
  }
}

///|
/// Parse `generate`'s flag arguments into `(package_json_path?, vendor_root?)`.
fn parse_sync_args(args : Array[String], start : Int) -> (String?, String?) {
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
      pkg_json = Some(arg["--package-json=".length():arg.length()].to_string())
      idx += 1
      continue
    }
    if arg.has_prefix("--out=") {
      out_dir = Some(arg["--out=".length():arg.length()].to_string())
      idx += 1
      continue
    }
    idx += 1
  }
  (pkg_json, out_dir)
}

///|
async fn ts2mbt_run_generate(args : Array[String], start : Int) -> Unit {
  if start < args.length() && @ts.cli_subcommand_is_help(args[start]) {
    ts2mbt_print_usage()
    return
  }
  let (pkg_json, out_dir) = parse_sync_args(args, start)
  if !@ts.ts2mbt_generate_from_package_json(
      package_json_path_override=pkg_json,
      vendor_root_override=out_dir,
    ) {
    @ts.cli_fail("ts2mbt")
  }
}

///|
async fn ts2mbt_main_async() -> Unit {
  let args = @env.args()
  if args.length() < 2 {
    ts2mbt_print_usage()
    return
  }
  if @ts.cli_token_is_version(args[1]) {
    @ts.cli_print_version("ts2mbt")
    return
  }
  if args[1].has_prefix("--") || args[1] == "-h" {
    if args[1] == "--help" || args[1] == "-h" {
      ts2mbt_print_usage()
      return
    }
    if !@ts.run_ts_to_mbt_unified_cli(args, 1, print_help=ts2mbt_print_usage) {
      @ts.cli_fail("ts2mbt")
    }
    return
  }
  let command = args[1]
  match command {
    "scaffold-from-input" =>
      if !@ts.run_ts_to_mbt_unified_cli(args, 2, print_help=ts2mbt_print_usage) {
        @ts.cli_fail("ts2mbt")
      }
    "decl" =>
      ts2mbt_dispatch(
        args,
        2,
        "decl",
        1,
        "ts2mbt decl: expected <ts-entry> [out]",
        async fn(p) {
          @ts.emit_moonbit_decl(
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
      ts2mbt_dispatch(
        args,
        2,
        "ffi",
        2,
        "ts2mbt ffi: expected <ts-entry> <module-spec> [ffi-out] [bridge-out]",
        async fn(p) {
          @ts.emit_moonbit_js_ffi(
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
    "bridge" =>
      ts2mbt_dispatch(
        args,
        2,
        "bridge",
        2,
        "ts2mbt bridge: expected <ts-entry> <module-spec> [decl-out] [ffi-out] [bridge-out]",
        async fn(p) {
          @ts.emit_moonbit_bridge(
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
      ts2mbt_dispatch(
        args,
        2,
        "package",
        3,
        "ts2mbt package: expected <ts-entry> <module-spec> <out-dir>",
        async fn(p) { @ts.emit_moonbit_bridge_package(p[0], p[1], p[2]) },
      )
    "scaffold" =>
      ts2mbt_dispatch(
        args,
        2,
        "scaffold",
        3,
        "ts2mbt scaffold: expected <ts-entry> <module-spec> <out-dir>",
        async fn(p) { @ts.emit_moonbit_scaffold_from_ts(p[0], p[1], p[2]) },
      )
    "vendor" => ts2mbt_run_vendor(args, 2)
    "generate" => ts2mbt_run_generate(args, 2)
    "--help" | "-h" | "help" => ts2mbt_print_usage()
    "--version" | "-V" => @ts.cli_print_version("ts2mbt")
    _ => {
      println("Unknown subcommand: \{command}")
      ts2mbt_print_usage()
      @ts.cli_fail("ts2mbt")
    }
  }
}

///|
fn main {
  @async.run_async_main(ts2mbt_main_async)
}
