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
/// `mizchi/ts` package version reported by `--version` / `-V` from each
/// cmd binary. Sourced from `moon.mod.json` and bumped together with it
/// at release time.
pub const CLI_VERSION : String = "0.4.0"

///|
/// Print the version banner for the given binary name and exit with
/// status 0. Cmd dispatchers should intercept `--version` / `-V` and
/// route here.
pub fn cli_print_version(binary_name : String) -> Unit {
  println("\{binary_name} \{CLI_VERSION} (mizchi/ts)")
}

///|
/// Treat the given top-level token as a version request — `--version`
/// or `-V`. Cmd dispatchers use this to short-circuit the help/dispatch
/// pipeline and just print the version banner.
pub fn cli_token_is_version(token : String) -> Bool {
  token == "--version" || token == "-V"
}

///|
/// Sanitize a raw bridge / IO error message so the printed CLI text
/// doesn't leak the MoonBit `OSError("@fs.open(): ...")` debug shape.
/// Specifically: when the message contains `OSError("...")`, replace
/// that fragment with the inner reason (after the first `: ` delimiter)
/// so users see a single-quoted file path + plain reason.
pub fn cli_clean_error(message : String) -> String {
  let marker = "OSError(\""
  match message.find(marker) {
    None => message
    Some(start_idx) => {
      let prefix = message[:start_idx].to_owned()
      let body_start = start_idx + marker.length()
      let after = message[body_start:message.length()].to_owned()
      // The body looks like:
      //   <syscall>: \"<path>\": <reason>")
      // Strip the trailing `")` and pull the trailing reason after the
      // last `\": `.
      let trimmed = if after.has_suffix("\")") {
        after[:after.length() - 2].to_owned()
      } else {
        after
      }
      let reason = match trimmed.rev_find("\\\": ") {
        Some(idx) => trimmed[idx + 4:trimmed.length()].to_owned()
        None => trimmed
      }
      prefix + reason
    }
  }
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
/// exits with status 1) when fewer than `min_args` positionals are present
/// — the bail message includes a hint pointing at the per-subcommand
/// `--help` so users know how to recover.
///
/// `args` is the full process argv slice (`@env.args()`), `start` is the
/// index of the first positional after the subcommand verb, and
/// `usage` is the bail message printed when the arity check fails. The
/// optional `help_hint` (e.g. `"ts2mbt decl --help"`) is appended to the
/// bail message; pass `""` to suppress it.
pub fn cli_parse_subcommand_args(
  args : Array[String],
  start : Int,
  min_args : Int,
  usage : String,
  help_hint? : String = "",
) -> CliArgScan {
  if start < args.length() && cli_subcommand_is_help(args[start]) {
    return HelpRequested
  }
  let provided = args.length() - start
  if provided < min_args {
    let suffix = if help_hint == "" {
      ""
    } else {
      " (run `\{help_hint}` for usage)"
    }
    cli_bail("\{usage} — got \{provided} arg(s), need \{min_args}\{suffix}")
  }
  let positionals : Array[String] = []
  for i in start..<args.length() {
    positionals.push(args[i])
  }
  Args(positionals)
}
