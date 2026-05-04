///|
/// Shared CLI exit helpers used by `src/cmd/ts2mbt` and `src/cmd/mbt2ts`.
/// Each cmd binary owns its own `print_usage` callback and binary name; the
/// library only owns the exit + error-print pieces so the dispatchers stay
/// thin.

///|
#cfg(target="native")
extern "C" fn cli_exit_native(code : Int) = "exit"

///|
#cfg(not(target="native"))
fn cli_exit_native(code : Int) -> Unit {
  abort("tsmbt cli exit \{code}")
}

///|
/// Exit the CLI with the given status code. Use `0` for success and a
/// non-zero value for any failure path.
pub fn cli_exit(code : Int) -> Unit {
  cli_exit_native(code)
}

///|
/// Print a one-line "<binary> command failed" banner and exit with status 1.
/// Cmd dispatchers should call this from every error path so CI / scripts
/// can detect failure.
pub fn cli_fail(binary_name : String) -> Unit {
  println("\{binary_name} command failed")
  cli_exit(1)
}

///|
/// Bail out of the CLI: print `Error: <message>` then exit with status 1.
/// Suitable for missing-argument, unknown-subcommand, and other usage
/// errors that should not be silently ignored.
pub fn cli_bail(message : String) -> Unit {
  println("Error: \{message}")
  cli_exit(1)
}

///|
/// Treat the given subcommand token as a help request — `--help`, `-h`, or
/// `help`. Cmd dispatchers use this to short-circuit per-subcommand help
/// before treating the next positional as a path.
pub fn cli_subcommand_is_help(token : String) -> Bool {
  token == "--help" || token == "-h" || token == "help"
}

///|
/// Outcome of a CLI subcommand argument scan.
///
/// - `Args(positionals)`: the parse succeeded; `positionals` are the
///   subcommand-specific args (`args[start:]`).
/// - `HelpRequested`: the next token after the subcommand was a help
///   marker; the caller should print usage and return without erroring.
pub enum CliArgScan {
  Args(Array[String])
  HelpRequested
}

///|
/// Parse the positional arguments for a subcommand. Returns `HelpRequested`
/// when the user passed `--help` / `-h` / `help`. Calls `cli_bail` (which
/// exits with status 1) when fewer than `min_args` positionals are present.
///
/// `args` is the full process argv slice (`@env.args()`), `start` is the
/// index of the first positional after the subcommand verb, and
/// `usage` is the bail message printed when the arity check fails.
pub fn cli_parse_subcommand_args(
  args : Array[String],
  start : Int,
  min_args : Int,
  usage : String,
) -> CliArgScan {
  if start < args.length() && cli_subcommand_is_help(args[start]) {
    return HelpRequested
  }
  let provided = args.length() - start
  if provided < min_args {
    cli_bail(usage)
  }
  let positionals : Array[String] = []
  for i in start..<args.length() {
    positionals.push(args[i])
  }
  Args(positionals)
}
