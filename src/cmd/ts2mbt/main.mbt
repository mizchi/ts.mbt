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
  min_args : Int,
  usage : String,
  handler : async (Array[String]) -> Bool,
) -> Unit {
  match @ts.cli_parse_subcommand_args(args, start, min_args, usage) {
    HelpRequested => ts2mbt_print_usage()
    Args(positionals) => if !handler(positionals) { @ts.cli_fail("ts2mbt") }
  }
}

///|
async fn ts2mbt_main_async() -> Unit {
  let args = @env.args()
  if args.length() < 2 {
    ts2mbt_print_usage()
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
    "generate" | "scaffold-from-input" =>
      if !@ts.run_ts_to_mbt_unified_cli(args, 2, print_help=ts2mbt_print_usage) {
        @ts.cli_fail("ts2mbt")
      }
    "decl" =>
      ts2mbt_dispatch(args, 2, 1, "ts2mbt decl: expected <ts-entry> [out]", async fn(
        p,
      ) {
        @ts.emit_moonbit_decl(
          p[0],
          if p.length() >= 2 {
            Some(p[1])
          } else {
            None
          },
        )
      })
    "ffi" =>
      ts2mbt_dispatch(
        args,
        2,
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
        3,
        "ts2mbt package: expected <ts-entry> <module-spec> <out-dir>",
        async fn(p) { @ts.emit_moonbit_bridge_package(p[0], p[1], p[2]) },
      )
    "scaffold" =>
      ts2mbt_dispatch(
        args,
        2,
        3,
        "ts2mbt scaffold: expected <ts-entry> <module-spec> <out-dir>",
        async fn(p) { @ts.emit_moonbit_scaffold_from_ts(p[0], p[1], p[2]) },
      )
    "--help" | "-h" | "help" => ts2mbt_print_usage()
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
