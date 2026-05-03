///|
fn ts2mbt_command_failed() -> Unit {
  println("ts2mbt command failed")
  ts2mbt_cli_exit(1)
}

///|
#cfg(target="native")
extern "C" fn ts2mbt_cli_exit(code : Int) = "exit"

///|
#cfg(not(target="native"))
fn ts2mbt_cli_exit(code : Int) -> Unit {
  let _ = code
  abort("ts2mbt command failed")
}

///|
fn ts2mbt_print_usage() -> Unit {
  println(
    "Usage: ts2mbt [--input <ts-entry> --out <dir>] [<subcommand> args...]",
  )
  println("")
  println("Generate MoonBit bridge artifacts from a TypeScript entrypoint.")
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
async fn ts2mbt_main_async() -> Unit {
  let args = @env.args()
  if args.length() < 2 {
    ts2mbt_print_usage()
    return
  }
  if args[1].has_prefix("--") {
    if !@ts.run_ts_to_mbt_unified_cli(args, 1, print_help=ts2mbt_print_usage) {
      ts2mbt_command_failed()
    }
    return
  }
  let command = args[1]
  match command {
    "generate" | "scaffold-from-input" =>
      if !@ts.run_ts_to_mbt_unified_cli(args, 2, print_help=ts2mbt_print_usage) {
        ts2mbt_command_failed()
      }
    "decl" => {
      if args.length() < 3 {
        println("Error: expected <ts-entry>")
        return
      }
      let file_path = args[2]
      let output_path = if args.length() >= 4 { Some(args[3]) } else { None }
      @ts.emit_moonbit_decl(file_path, output_path)
    }
    "ffi" => {
      if args.length() < 4 {
        println("Error: expected <ts-entry> <module-spec>")
        return
      }
      let file_path = args[2]
      let module_spec = args[3]
      let ffi_out = if args.length() >= 5 { Some(args[4]) } else { None }
      let bridge_out = if args.length() >= 6 { Some(args[5]) } else { None }
      @ts.emit_moonbit_js_ffi(file_path, module_spec, ffi_out, bridge_out)
    }
    "bridge" => {
      if args.length() < 4 {
        println("Error: expected <ts-entry> <module-spec>")
        return
      }
      let file_path = args[2]
      let module_spec = args[3]
      let decl_out = if args.length() >= 5 { Some(args[4]) } else { None }
      let ffi_out = if args.length() >= 6 { Some(args[5]) } else { None }
      let bridge_out = if args.length() >= 7 { Some(args[6]) } else { None }
      @ts.emit_moonbit_bridge(
        file_path, module_spec, decl_out, ffi_out, bridge_out,
      )
    }
    "package" => {
      if args.length() < 5 {
        println("Error: expected <ts-entry> <module-spec> <out-dir>")
        return
      }
      let file_path = args[2]
      let module_spec = args[3]
      let output_dir = args[4]
      @ts.emit_moonbit_bridge_package(file_path, module_spec, output_dir)
    }
    "scaffold" => {
      if args.length() < 5 {
        println("Error: expected <ts-entry> <module-spec> <out-dir>")
        return
      }
      let file_path = args[2]
      let module_spec = args[3]
      let output_dir = args[4]
      @ts.emit_moonbit_scaffold_from_ts(file_path, module_spec, output_dir)
    }
    "--help" | "-h" | "help" => ts2mbt_print_usage()
    _ => {
      println("Unknown subcommand: \{command}")
      ts2mbt_print_usage()
    }
  }
}

///|
fn main {
  @async.run_async_main(ts2mbt_main_async)
}
