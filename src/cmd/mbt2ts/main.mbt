///|
fn mbt2ts_print_usage() -> Unit {
  println(
    "Usage: mbt2ts [--input <pkg-or-mbti> --out <dir>] [<subcommand> args...]",
  )
  println("")
  println(
    "Generate TypeScript declarations and JS-backed packages from a MoonBit interface.",
  )
  println("")
  println(
    "Recommended: use the unified `--input/--out` flow for build-backed scaffolds.",
  )
  println("Subcommands expose individual generation stages.")
  println("")
  println("Subcommands:")
  for line in mbt2ts_help_lines() {
    println(line)
  }
}

///|
/// Help lines for the `mbt2ts` CLI. Exposed so tests can keep the surface
/// stable.
pub fn mbt2ts_help_lines() -> Array[String] {
  [
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
/// Run a subcommand handler against the parsed positional args. Centralises
/// the per-arm `parse args -> dispatch -> propagate exit code` pipeline so
/// each cmd arm shrinks to a single line.
async fn mbt2ts_dispatch(
  args : Array[String],
  start : Int,
  min_args : Int,
  usage : String,
  handler : async (Array[String]) -> Bool,
) -> Unit {
  match @ts.cli_parse_subcommand_args(args, start, min_args, usage) {
    HelpRequested => mbt2ts_print_usage()
    Args(positionals) => if !handler(positionals) { @ts.cli_fail("mbt2ts") }
  }
}

///|
async fn mbt2ts_main_async() -> Unit {
  let args = @env.args()
  if args.length() < 2 {
    mbt2ts_print_usage()
    return
  }
  if args[1].has_prefix("--") || args[1] == "-h" {
    if args[1] == "--help" || args[1] == "-h" {
      mbt2ts_print_usage()
      return
    }
    if !@ts.run_mbt_to_ts_unified_cli(args, 1, print_help=mbt2ts_print_usage) {
      @ts.cli_fail("mbt2ts")
    }
    return
  }
  let command = args[1]
  match command {
    "generate" | "scaffold-from-input" =>
      if !@ts.run_mbt_to_ts_unified_cli(args, 2, print_help=mbt2ts_print_usage) {
        @ts.cli_fail("mbt2ts")
      }
    "decl" =>
      mbt2ts_dispatch(args, 2, 1, "mbt2ts decl: expected <mbti> [out]", async fn(
        p,
      ) {
        @ts.emit_typescript_decl_from_mbti(
          p[0],
          if p.length() >= 2 {
            Some(p[1])
          } else {
            None
          },
        )
      })
    "link-config" =>
      mbt2ts_dispatch(args, 2, 1, "mbt2ts link-config: expected <mbti> [out]", async fn(
        p,
      ) {
        @ts.emit_js_link_config_from_mbti(
          p[0],
          if p.length() >= 2 {
            Some(p[1])
          } else {
            None
          },
        )
      })
    "package" =>
      mbt2ts_dispatch(
        args,
        2,
        2,
        "mbt2ts package: expected <mbti> <out-dir> [import-rewrite-json]",
        async fn(p) {
          @ts.emit_typescript_package_from_mbti(
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
      mbt2ts_dispatch(
        args,
        2,
        2,
        "mbt2ts scaffold: expected <mbti> <out-dir> [import-rewrite-json]",
        async fn(p) {
          @ts.emit_typescript_scaffold_from_mbti(
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
      mbt2ts_dispatch(
        args,
        2,
        2,
        "mbt2ts facade-scaffold: expected <mbti> <out-dir> [import-rewrite-json]",
        async fn(p) {
          @ts.emit_typescript_facade_scaffold_from_mbti(
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
      mbt2ts_dispatch(args, 2, 1, "mbt2ts normalize: expected <ts> [out]", async fn(
        p,
      ) {
        @ts.emit_typescript_decl(
          p[0],
          if p.length() >= 2 {
            Some(p[1])
          } else {
            None
          },
        )
      })
    "--help" | "-h" | "help" => mbt2ts_print_usage()
    _ => {
      println("Unknown subcommand: \{command}")
      mbt2ts_print_usage()
      @ts.cli_fail("mbt2ts")
    }
  }
}

///|
fn main {
  @async.run_async_main(mbt2ts_main_async)
}
