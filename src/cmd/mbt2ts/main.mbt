///|
fn mbt2ts_command_failed() -> Unit {
  println("mbt2ts command failed")
  mbt2ts_cli_exit(1)
}

///|
#cfg(target="native")
extern "C" fn mbt2ts_cli_exit(code : Int) = "exit"

///|
#cfg(not(target="native"))
fn mbt2ts_cli_exit(code : Int) -> Unit {
  let _ = code
  abort("mbt2ts command failed")
}

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
async fn mbt2ts_main_async() -> Unit {
  let args = @env.args()
  if args.length() < 2 {
    mbt2ts_print_usage()
    return
  }
  if args[1].has_prefix("--") {
    if !@ts.run_mbt_to_ts_unified_cli(args, 1, print_help=mbt2ts_print_usage) {
      mbt2ts_command_failed()
    }
    return
  }
  let command = args[1]
  match command {
    "generate" | "scaffold-from-input" =>
      if !@ts.run_mbt_to_ts_unified_cli(args, 2, print_help=mbt2ts_print_usage) {
        mbt2ts_command_failed()
      }
    "decl" => {
      if args.length() < 3 {
        println("Error: expected <mbti>")
        return
      }
      let file_path = args[2]
      let output_path = if args.length() >= 4 { Some(args[3]) } else { None }
      @ts.emit_typescript_decl_from_mbti(file_path, output_path)
    }
    "link-config" => {
      if args.length() < 3 {
        println("Error: expected <mbti>")
        return
      }
      let file_path = args[2]
      let output_path = if args.length() >= 4 { Some(args[3]) } else { None }
      @ts.emit_js_link_config_from_mbti(file_path, output_path)
    }
    "package" => {
      if args.length() < 4 {
        println("Error: expected <mbti> <out-dir>")
        return
      }
      let file_path = args[2]
      let output_dir = args[3]
      let import_rewrite_path = if args.length() >= 5 {
        Some(args[4])
      } else {
        None
      }
      @ts.emit_typescript_package_from_mbti(
        file_path, output_dir, import_rewrite_path,
      )
    }
    "scaffold" => {
      if args.length() < 4 {
        println("Error: expected <mbti> <out-dir>")
        return
      }
      let file_path = args[2]
      let output_dir = args[3]
      let import_rewrite_path = if args.length() >= 5 {
        Some(args[4])
      } else {
        None
      }
      if !@ts.emit_typescript_scaffold_from_mbti(
          file_path, output_dir, import_rewrite_path,
        ) {
        mbt2ts_command_failed()
      }
    }
    "facade-scaffold" => {
      if args.length() < 4 {
        println("Error: expected <mbti> <out-dir>")
        return
      }
      let file_path = args[2]
      let output_dir = args[3]
      let import_rewrite_path = if args.length() >= 5 {
        Some(args[4])
      } else {
        None
      }
      if !@ts.emit_typescript_facade_scaffold_from_mbti(
          file_path, output_dir, import_rewrite_path,
        ) {
        mbt2ts_command_failed()
      }
    }
    "normalize" => {
      if args.length() < 3 {
        println("Error: expected <ts>")
        return
      }
      let file_path = args[2]
      let output_path = if args.length() >= 4 { Some(args[3]) } else { None }
      @ts.emit_typescript_decl(file_path, output_path)
    }
    "--help" | "-h" | "help" => mbt2ts_print_usage()
    _ => {
      println("Unknown subcommand: \{command}")
      mbt2ts_print_usage()
    }
  }
}

///|
fn main {
  @async.run_async_main(mbt2ts_main_async)
}
