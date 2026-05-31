// Minimal CLI for benchmarking the parse + check pipeline against a
// real `.ts` file. Designed to be invoked under `hyperfine` /
// `/usr/bin/time -v` so external tools can measure wall-clock and peak
// RSS without going through the full bridge-generation path.
//
//   tscheck <file.ts>            # parse + check, exits 0
//   tscheck --parse <file.ts>    # parse only (compares against the
//                                # full pipeline so the checker's
//                                # marginal cost is visible)
//   tscheck --iters N <file.ts>  # repeat N times so memory tools see
//                                # the steady-state heap

///|
async fn main {
  let argv = @env.args()
  if argv.length() < 2 {
    println("Usage: tscheck [--parse] [--iters N] <file.ts>")
    return
  }
  let mut parse_only = false
  let mut verbose = false
  let mut iters = 1
  let mut path = ""
  let mut i = 1
  while i < argv.length() {
    let arg = argv[i]
    if arg == "--parse" {
      parse_only = true
    } else if arg == "--verbose" || arg == "-v" {
      verbose = true
    } else if arg == "--iters" && i + 1 < argv.length() {
      i = i + 1
      iters = try @string.parse_int(argv[i]) catch {
        _ => 1
      } noraise {
        n if n > 0 => n
        _ => 1
      }
    } else {
      path = arg
    }
    i = i + 1
  }
  if path == "" {
    println("Usage: tscheck [--parse] [--iters N] <file.ts>")
    return
  }
  let text = @fs.read_file(path).text() catch {
    _ => {
      println("read error: " + path)
      return
    }
  }
  let allow_jsx = path.has_suffix(".tsx")
  let mut module_count = 0
  let mut issue_count = 0
  for _ in 0..<iters {
    let module_ = @parser.Parser::from_source_with_jsx(text, allow_jsx).parse_module() catch {
      e => {
        println("parse error: \{e}")
        return
      }
    }
    module_count = module_count + module_.funcs.length()
    if !parse_only {
      let issues = @checker.check_module_function_bodies(module_)
      issue_count = issue_count + issues.length()
      if verbose {
        for iss in issues {
          println("  ISSUE [\{iss.path}]: \{iss.message}")
        }
      }
    }
  }
  // Trivial output so the binary doesn't get fully optimized away;
  // hyperfine pipes stdout to /dev/null anyway.
  if parse_only {
    println("parsed \{iters}x — \{module_count} funcs total")
  } else {
    println(
      "checked \{iters}x — \{module_count} funcs, \{issue_count} issues total",
    )
  }
}
