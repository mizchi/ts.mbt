///|
priv enum TsmbtDirection {
  Auto
  TsToMbt
  MbtToTs
}

///|
priv struct UnifiedTsmbtOptions {
  input : String?
  out : String?
  direction : TsmbtDirection
  module_spec : String?
  import_rewrite_path : String?
  facade : Bool
}

///|
fn parse_tsmbt_direction(value : String) -> TsmbtDirection? {
  match value {
    "auto" => Some(TsmbtDirection::Auto)
    "ts-to-mbt" | "ts2mbt" | "ts" => Some(TsmbtDirection::TsToMbt)
    "mbt-to-ts" | "mbt2ts" | "mbt" => Some(TsmbtDirection::MbtToTs)
    _ => None
  }
}

///|
fn parse_unified_tsmbt_options(
  args : Array[String],
  start : Int,
) -> (UnifiedTsmbtOptions?, String?) {
  let mut input : String? = None
  let mut out : String? = None
  let mut direction = TsmbtDirection::Auto
  let mut module_spec : String? = None
  let mut import_rewrite_path : String? = None
  let mut facade = true
  let mut idx = start
  while idx < args.length() {
    let arg = args[idx]
    match arg {
      "--help" | "-h" => return (None, Some("help"))
      "--input" | "-i" => {
        if idx + 1 >= args.length() {
          return (None, Some("missing value for \{arg}"))
        }
        input = Some(args[idx + 1])
        idx += 2
        continue
      }
      "--out" | "-o" => {
        if idx + 1 >= args.length() {
          return (None, Some("missing value for \{arg}"))
        }
        out = Some(args[idx + 1])
        idx += 2
        continue
      }
      "--direction" => {
        if idx + 1 >= args.length() {
          return (None, Some("missing value for --direction"))
        }
        match parse_tsmbt_direction(args[idx + 1]) {
          Some(parsed) => direction = parsed
          None =>
            return (
              None,
              Some(
                "invalid --direction '\{args[idx + 1]}', expected auto, mbt-to-ts, or ts-to-mbt",
              ),
            )
        }
        idx += 2
        continue
      }
      "--module-spec" | "--runtime-module" => {
        if idx + 1 >= args.length() {
          return (None, Some("missing value for \{arg}"))
        }
        module_spec = Some(args[idx + 1])
        idx += 2
        continue
      }
      "--import-rewrites" | "--import-rewrite" => {
        if idx + 1 >= args.length() {
          return (None, Some("missing value for \{arg}"))
        }
        import_rewrite_path = Some(args[idx + 1])
        idx += 2
        continue
      }
      "--facade" => {
        facade = true
        idx += 1
        continue
      }
      "--no-facade" => {
        facade = false
        idx += 1
        continue
      }
      _ => ()
    }
    if arg.has_prefix("--input=") {
      input = Some(arg["--input=".length():arg.length()].to_string())
    } else if arg.has_prefix("--out=") {
      out = Some(arg["--out=".length():arg.length()].to_string())
    } else if arg.has_prefix("--direction=") {
      let value = arg["--direction=".length():arg.length()].to_string()
      match parse_tsmbt_direction(value) {
        Some(parsed) => direction = parsed
        None =>
          return (
            None,
            Some(
              "invalid --direction '\{value}', expected auto, mbt-to-ts, or ts-to-mbt",
            ),
          )
      }
    } else if arg.has_prefix("--module-spec=") {
      module_spec = Some(
        arg["--module-spec=".length():arg.length()].to_string(),
      )
    } else if arg.has_prefix("--runtime-module=") {
      module_spec = Some(
        arg["--runtime-module=".length():arg.length()].to_string(),
      )
    } else if arg.has_prefix("--import-rewrites=") {
      import_rewrite_path = Some(
        arg["--import-rewrites=".length():arg.length()].to_string(),
      )
    } else if arg.has_prefix("--import-rewrite=") {
      import_rewrite_path = Some(
        arg["--import-rewrite=".length():arg.length()].to_string(),
      )
    } else if !arg.has_prefix("-") && input is None {
      input = Some(arg)
    } else if !arg.has_prefix("-") && out is None {
      out = Some(arg)
    } else {
      return (None, Some("unknown option: \{arg}"))
    }
    idx += 1
  }
  (
    Some({ input, out, direction, module_spec, import_rewrite_path, facade }),
    None,
  )
}

///|
async fn main_file_exists(path : String) -> Bool {
  let kind = @fs.kind(path, follow_symlink=false) catch {
    _ => @fs.FileKind::Unknown
  }
  kind is @fs.FileKind::Regular
}

///|
fn unified_tsmbt_skip_scan_dir(name : String) -> Bool {
  name == ".git" ||
  name == ".mooncakes" ||
  name == "_build" ||
  name == "target" ||
  name == "node_modules" ||
  name == "test262"
}

///|
async fn collect_pkg_generated_mbti_files(
  path : String,
  out : Array[String],
) -> Unit {
  let kind = @fs.kind(path, follow_symlink=false) catch {
    _ => @fs.FileKind::Unknown
  }
  match kind {
    @fs.FileKind::Directory => {
      let entries = @fs.readdir(
        path,
        include_hidden=false,
        include_special=false,
        sort=true,
      ) catch {
        _ => []
      }
      for name in entries {
        if unified_tsmbt_skip_scan_dir(name) {
          continue
        }
        collect_pkg_generated_mbti_files(main_join_path(path, name), out)
      }
    }
    @fs.FileKind::Regular =>
      if path.has_suffix("pkg.generated.mbti") {
        out.push(path)
      }
    _ => ()
  }
}

///|
fn parse_mbti_package_name_from_source(source : String) -> String? {
  for line_view in source.split("\n") {
    let line = line_view.trim().to_string()
    if !line.has_prefix("package \"") {
      continue
    }
    let rest = line["package \"".length():line.length()].to_string()
    match rest.find("\"") {
      Some(end_idx) => return Some(rest[:end_idx].to_string())
      None => ()
    }
  }
  None
}

///|
async fn resolve_unified_mbt_input_path(input : String) -> String? {
  let roots : Array[String] = ["."]
  match infer_ghq_github_root_from_cwd() {
    Some(root) => roots.push(root)
    None => ()
  }
  resolve_unified_mbt_input_path_from_roots(input, roots)
}

///|
fn ghq_candidate_repo_paths(
  github_root : String,
  input : String,
) -> Array[String] {
  let paths = [main_join_path(github_root, input)]
  if !input.has_suffix(".mbt") {
    paths.push(main_join_path(github_root, input + ".mbt"))
  }
  paths
}

///|
async fn ghq_module_name_candidate_repo_paths(
  github_root : String,
  input : String,
) -> Array[String] {
  let paths : Array[String] = []
  let owner = match input.find("/") {
    Some(sep_idx) => input[:sep_idx].to_string()
    None => return paths
  }
  let owner_root = main_join_path(github_root, owner)
  if !@fs.exists(owner_root) {
    return paths
  }
  let entries = @fs.readdir(
    owner_root,
    include_hidden=false,
    include_special=false,
    sort=true,
  ) catch {
    _ => return paths
  }
  for name in entries {
    if unified_tsmbt_skip_scan_dir(name) {
      continue
    }
    let repo_path = main_join_path(owner_root, name)
    let kind = @fs.kind(repo_path, follow_symlink=false) catch {
      _ => @fs.FileKind::Unknown
    }
    if !(kind is @fs.FileKind::Directory) {
      continue
    }
    let moon_mod_path = main_join_path(repo_path, "moon.mod.json")
    if !main_file_exists(moon_mod_path) {
      continue
    }
    let moon_mod_source = @fs.read_file(moon_mod_path).text() catch {
      _ => continue
    }
    match parse_moon_mod_string_field(moon_mod_source, "name") {
      Some(module_name) if module_name == input => paths.push(repo_path)
      _ => ()
    }
  }
  paths
}

///|
async fn infer_ghq_github_root_from_cwd() -> String? {
  let cwd = @fs.realpath(".") catch { _ => "." }
  match cwd.find("/ghq/github.com/") {
    Some(idx) => Some(cwd[:idx + "/ghq/github.com".length()].to_string())
    None => None
  }
}

///|
async fn resolve_unified_mbt_input_path_from_roots(
  input : String,
  roots : Array[String],
) -> String? {
  if main_file_exists(input) {
    return Some(input)
  }
  let direct_pkg_path = main_join_path(input, "pkg.generated.mbti")
  if main_file_exists(direct_pkg_path) {
    return Some(direct_pkg_path)
  }
  for root in roots {
    let scan_roots = if root.has_suffix("/github.com") && input.contains("/") {
      let paths = ghq_candidate_repo_paths(root, input)
      for path in ghq_module_name_candidate_repo_paths(root, input) {
        if !paths.contains(path) {
          paths.push(path)
        }
      }
      paths
    } else {
      [root]
    }
    for scan_root in scan_roots {
      if !@fs.exists(scan_root) {
        continue
      }
      let candidates : Array[String] = []
      collect_pkg_generated_mbti_files(scan_root, candidates)
      for path in candidates {
        let source = @fs.read_file(path).text() catch { _ => continue }
        match parse_mbti_package_name_from_source(source) {
          Some(package_name) if package_name == input => return Some(path)
          _ => ()
        }
      }
    }
  }
  None
}

///|
fn is_ts_input_path_like(input : String) -> Bool {
  input.has_suffix(".d.ts") ||
  input.has_suffix(".d.mts") ||
  input.has_suffix(".d.cts") ||
  input.has_suffix(".ts") ||
  input.has_suffix(".tsx") ||
  input.has_suffix(".mts") ||
  input.has_suffix(".cts")
}

///|
async fn resolve_unified_ts_input_path(input : String) -> String? {
  if main_file_exists(input) {
    return Some(input)
  }
  @parser.resolve_type_module_specifier("__tsmbt_entry__.ts", input)
}

///|
async fn infer_unified_tsmbt_direction(input : String) -> TsmbtDirection? {
  if is_ts_input_path_like(input) {
    return Some(TsmbtDirection::TsToMbt)
  }
  if input.has_suffix(".mbti") {
    return Some(TsmbtDirection::MbtToTs)
  }
  match resolve_unified_mbt_input_path(input) {
    Some(_) => return Some(TsmbtDirection::MbtToTs)
    None => ()
  }
  match resolve_unified_ts_input_path(input) {
    Some(_) => Some(TsmbtDirection::TsToMbt)
    None => None
  }
}

///|
async fn emit_unified_tsmbt_scaffold(
  input : String,
  out : String,
  direction~ : TsmbtDirection,
  module_spec~ : String?,
  import_rewrite_path~ : String?,
  facade~ : Bool,
) -> Bool {
  let resolved_direction = match direction {
    TsmbtDirection::Auto =>
      match infer_unified_tsmbt_direction(input) {
        Some(direction) => direction
        None => {
          println(
            "Error: could not infer direction for '\{input}'. Use --direction mbt-to-ts or --direction ts-to-mbt.",
          )
          return false
        }
      }
    _ => direction
  }
  match resolved_direction {
    TsmbtDirection::MbtToTs => {
      let mbti_path = match resolve_unified_mbt_input_path(input) {
        Some(path) => path
        None => {
          println(
            "Error: could not resolve MoonBit package or pkg.generated.mbti '\{input}'. Run moon info first or pass a pkg.generated.mbti path.",
          )
          return false
        }
      }
      if facade {
        emit_typescript_facade_scaffold_from_mbti(
          mbti_path, out, import_rewrite_path,
        )
      } else {
        emit_typescript_scaffold_from_mbti(mbti_path, out, import_rewrite_path)
      }
    }
    TsmbtDirection::TsToMbt => {
      let entry_path = match resolve_unified_ts_input_path(input) {
        Some(path) => path
        None => {
          println(
            "Error: could not resolve TypeScript entrypoint '\{input}'. Pass a .d.ts/.ts path or an installed package specifier.",
          )
          return false
        }
      }
      let runtime_module_spec = match module_spec {
        Some(spec) => spec
        None => input
      }
      emit_moonbit_scaffold_from_ts(entry_path, runtime_module_spec, out)
      true
    }
    TsmbtDirection::Auto => true
  }
}

///|
async fn run_unified_tsmbt_cli(args : Array[String], start : Int) -> Bool {
  let options = match parse_unified_tsmbt_options(args, start) {
    (Some(options), None) => options
    (_, Some("help")) => {
      print_usage()
      return true
    }
    (_, Some(message)) => {
      println("Error: \{message}")
      print_usage()
      return false
    }
    _ => {
      print_usage()
      return false
    }
  }
  let input = match options.input {
    Some(input) => input
    None => {
      println("Error: expected --input <pkg-or-entry>")
      print_usage()
      return false
    }
  }
  let out = match options.out {
    Some(out) => out
    None => {
      println("Error: expected --out <dir>")
      print_usage()
      return false
    }
  }
  emit_unified_tsmbt_scaffold(
    input,
    out,
    direction=options.direction,
    module_spec=options.module_spec,
    import_rewrite_path=options.import_rewrite_path,
    facade=options.facade,
  )
}
