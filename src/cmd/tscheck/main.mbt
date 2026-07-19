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
/// True when `spec`, imported from `file_path`, resolves on disk. Used to
/// suppress "cannot find module" issues for files living under
/// node_modules: single-file checking cannot see sibling packages
/// (`csstype` is a real dependency of @types/react) or relative
/// self-imports (`./` resolves to the package's index.d.ts), and tsc
/// accepts both. Conformance corpora live outside node_modules, so oracle
/// behavior is unchanged.
async fn module_spec_resolves_on_disk(
  file_path : String,
  spec : String,
) -> Bool {
  let dir = match file_path.rev_find("/") {
    Some(idx) => file_path.substring(start=0, end=idx).to_string()
    None => "."
  }
  if spec.has_prefix("./") || spec.has_prefix("../") || spec == "." {
    let base = dir + "/" + spec
    for
      cand in [
        base,
        base + ".d.ts",
        base + ".ts",
        base + ".d.cts",
        base + ".d.mts",
        base + "/index.d.ts",
        base + "/index.ts",
      ] {
      if @fs.exists(cand) {
        return true
      }
    }
    return false
  }
  // Bare specifier: the package directory is the first path segment (the
  // first two for `@scope/name`). Walk up from the file's directory
  // probing node_modules, mirroring Node resolution. Package presence is
  // enough evidence to abstain -- subpath export validation is out of
  // scope for a single-file check.
  let head = if spec.has_prefix("@") {
    match spec.find("/") {
      Some(first) =>
        match spec.substring(start=first + 1).find("/") {
          Some(second) =>
            spec.substring(start=0, end=first + 1 + second).to_string()
          None => spec
        }
      None => spec
    }
  } else {
    match spec.find("/") {
      Some(first) => spec.substring(start=0, end=first).to_string()
      None => spec
    }
  }
  let mut cur = dir
  for _ in 0..<64 {
    if @fs.exists("\{cur}/node_modules/\{head}") ||
      @fs.exists("\{cur}/node_modules/@types/\{head}") {
      return true
    }
    match cur.rev_find("/") {
      Some(idx) if idx > 0 => cur = cur.substring(start=0, end=idx).to_string()
      _ => break
    }
  }
  false
}

///|
async fn main {
  let argv = @env.args()
  if argv.length() < 2 {
    println("Usage: tscheck [--parse] [--iters N] <file.ts>")
    return
  }
  let mut parse_only = false
  let mut verbose = false
  let mut strict = false
  let mut iters = 1
  let mut path = ""
  let mut i = 1
  while i < argv.length() {
    let arg = argv[i]
    if arg == "--parse" {
      parse_only = true
    } else if arg == "--verbose" || arg == "-v" {
      verbose = true
    } else if arg == "--strict" {
      strict = true
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
      let issues = if strict {
        @checker.check_module_function_bodies(module_)
      } else {
        @checker.check_module_function_bodies_permissive(module_)
      }
      // TS1046 applies only to declaration files -- keyed off the file
      // extension, which the general check pipeline can't see.
      if path.has_suffix(".d.ts") {
        for iss in @checker.check_dts_top_level_modifiers(module_) {
          issues.push(iss)
        }
      }
      // Files inside node_modules are real packages whose imports resolve
      // against the filesystem, which the single-file checker can't see.
      // Drop TS2307 issues whose specifier actually resolves on disk.
      let kept = if path.find("node_modules").is_empty() {
        issues
      } else {
        let out : Array[@checker.ExprIssue] = []
        for iss in issues {
          let prefix = "cannot find module `"
          if iss.message.has_prefix(prefix) && iss.message.has_suffix("`") {
            let spec = iss.message
              .substring(start=prefix.length(), end=iss.message.length() - 1)
              .to_string()
            if module_spec_resolves_on_disk(path, spec) {
              continue
            }
          }
          out.push(iss)
        }
        out
      }
      issue_count = issue_count + kept.length()
      if verbose {
        for iss in kept {
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
