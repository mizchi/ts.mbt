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
  diagnostics_path : String?
  strict : Bool
  facade : Bool
}

///|
/// Options that belong to the project-level `mbt2ts --pkg` entrypoint.
/// Unlike the lower-level unified input flow, this command owns `moon info`,
/// derives package metadata from the module manifest, and defaults to a
/// publish directory at `<module>/npm`.
priv struct Mbt2tsPkgOptions {
  out : String?
  import_rewrite_path : String?
  strict : Bool
  facade : Bool
}

///|
/// An executable source package to publish through `package.json#bin`.
/// Commands stay out of the TypeScript library export graph, but their
/// compiled JavaScript remains available to npm's command shim.
priv struct Mbt2tsPkgCommand {
  name : String
  source_relative_dir : String
}

///|
fn parse_mbt2ts_pkg_options(
  args : Array[String],
  start : Int,
) -> (Mbt2tsPkgOptions?, String?) {
  let mut out : String? = None
  let mut import_rewrite_path : String? = None
  let mut strict = false
  let mut facade = true
  let mut idx = start
  while idx < args.length() {
    let arg = args[idx]
    match arg {
      "--help" | "-h" => return (None, Some("help"))
      "--out" | "-o" => {
        if idx + 1 >= args.length() {
          return (None, Some("missing value for \{arg}"))
        }
        out = Some(args[idx + 1])
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
      "--strict" => {
        strict = true
        idx += 1
        continue
      }
      "--no-strict" => {
        strict = false
        idx += 1
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
    if arg.has_prefix("--out=") {
      out = Some(arg["--out=".length():arg.length()].to_owned())
    } else if arg.has_prefix("--import-rewrites=") {
      import_rewrite_path = Some(
        arg["--import-rewrites=".length():arg.length()].to_owned(),
      )
    } else if arg.has_prefix("--import-rewrite=") {
      import_rewrite_path = Some(
        arg["--import-rewrite=".length():arg.length()].to_owned(),
      )
    } else {
      return (None, Some("unknown option: \{arg}"))
    }
    idx += 1
  }
  (Some({ out, import_rewrite_path, strict, facade }), None)
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
  let mut diagnostics_path : String? = None
  let mut strict = false
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
      "--diagnostics" => {
        if idx + 1 >= args.length() {
          return (None, Some("missing value for --diagnostics"))
        }
        diagnostics_path = Some(args[idx + 1])
        idx += 2
        continue
      }
      "--strict" => {
        strict = true
        idx += 1
        continue
      }
      "--no-strict" => {
        strict = false
        idx += 1
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
      input = Some(arg["--input=".length():arg.length()].to_owned())
    } else if arg.has_prefix("--out=") {
      out = Some(arg["--out=".length():arg.length()].to_owned())
    } else if arg.has_prefix("--direction=") {
      let value = arg["--direction=".length():arg.length()].to_owned()
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
      module_spec = Some(arg["--module-spec=".length():arg.length()].to_owned())
    } else if arg.has_prefix("--runtime-module=") {
      module_spec = Some(
        arg["--runtime-module=".length():arg.length()].to_owned(),
      )
    } else if arg.has_prefix("--import-rewrites=") {
      import_rewrite_path = Some(
        arg["--import-rewrites=".length():arg.length()].to_owned(),
      )
    } else if arg.has_prefix("--import-rewrite=") {
      import_rewrite_path = Some(
        arg["--import-rewrite=".length():arg.length()].to_owned(),
      )
    } else if arg.has_prefix("--diagnostics=") {
      diagnostics_path = Some(
        arg["--diagnostics=".length():arg.length()].to_owned(),
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
    Some({
      input,
      out,
      direction,
      module_spec,
      import_rewrite_path,
      diagnostics_path,
      strict,
      facade,
    }),
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
    let line = line_view.trim().to_owned()
    if !line.has_prefix("package \"") {
      continue
    }
    let rest = line["package \"".length():line.length()].to_owned()
    match rest.find("\"") {
      Some(end_idx) => return Some(rest[:end_idx].to_owned())
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
    Some(sep_idx) => input[:sep_idx].to_owned()
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
    let moon_mod_source = match read_moon_mod_source(repo_path) {
      Some(source) => source
      None => continue
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
    Some(idx) => Some(cwd[:idx + "/ghq/github.com".length()].to_owned())
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
  let scan_order : Array[String] = []
  for root in roots {
    if root.has_suffix("/github.com") && !scan_order.contains(root) {
      scan_order.push(root)
    }
  }
  for root in roots {
    if !root.has_suffix("/github.com") && !scan_order.contains(root) {
      scan_order.push(root)
    }
  }
  for root in scan_order {
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
fn unified_ts_scaffold_diagnostics_path(
  output_dir : String,
  diagnostics_path : String?,
) -> String {
  match diagnostics_path {
    Some(path) => path
    None => main_join_path(output_dir, "SCAFFOLD_DIAGNOSTICS.md")
  }
}

///|
fn unified_ts_fallback_policy_for_package(
  package_spec : String,
) -> (String, String) {
  match package_spec {
    "clsx"
    | "node:path"
    | "node:crypto"
    | "node:os"
    | "node:url"
    | "node:querystring"
    | "node:buffer" =>
      (
        "zero-target", "Keep public JSValue surface at zero; any fallback is a regression.",
      )
    "hono" =>
      (
        "naturalize-target", "Reduce generic context/router fallbacks while keeping route handlers and response helpers natural.",
      )
    "react-router" =>
      (
        "naturalize-target", "Reduce route/path utility overload and option-object fallbacks; keep typed navigation helpers usable from MoonBit.",
      )
    "jose" =>
      (
        "naturalize-target", "Reduce builder option and compact JWS/JWT overload fallbacks around the smoke-tested APIs.",
      )
    "glob" =>
      (
        "naturalize-target", "Reduce pattern/options namespace fallbacks for common sync glob calls.",
      )
    "node:assert" | "node:util" =>
      (
        "naturalize-target", "Shrink remaining Node built-in overload/unknown fallbacks toward zero for the common API surface.",
      )
    "date-fns" | "magic-string" | "source-map" | "node:sqlite" | "node:fs" =>
      (
        "naturalize-target", "Keep reducing fallback around finite option bags, tuple results, and class/value helper APIs.",
      )
    "zod" | "valibot" =>
      (
        "budgeted-fallback", "Schema/parser generics are intentionally smoke-tested and budgeted, not treated as naturally typed MoonBit APIs yet.",
      )
    "preact" =>
      (
        "budgeted-fallback", "JSX/component/children generics are intentionally budgeted until a dedicated JSX/component binding layer exists.",
      )
    "playwright" =>
      (
        "budgeted-fallback", "Large event/callback-heavy API is smoke-tested; only selected launch/device/options surfaces are naturalization targets.",
      )
    "chalk"
    | "dotenv"
    | "ignore"
    | "colorette"
    | "immer"
    | "execa"
    | "vitest/runtime"
    | "express" =>
      (
        "low-fallback-maintain", "Current fallback is small and explicitly budgeted; naturalize only when a real smoke use case needs it.",
      )
    _ =>
      (
        "unclassified", "Add an explicit fallback policy before accepting this package into the real-world corpus.",
      )
  }
}

///|
fn render_unified_ts_fallback_policy_md(module_spec : String) -> String {
  let (class_name, policy) = unified_ts_fallback_policy_for_package(module_spec)
  [
    "## Fallback Policy",
    "",
    "This classification mirrors the real-world bridge quality policy. It is informational in non-strict mode; strict mode still rejects generated `JSValue` fallbacks.",
    "",
    "| package | class | policy |",
    "| --- | --- | --- |",
    "| `\{module_spec}` | \{class_name} | \{policy} |",
  ].join("\n")
}

///|
fn render_unified_ts_scaffold_diagnostics_md(
  module_spec : String,
  unsupported_exports : Array[String],
  jsvalue_fallbacks : Array[String],
) -> String {
  let mut base = render_moonbit_scaffold_diagnostics_md(unsupported_exports)
  // Avoid the contradictory "No unsupported exports were detected." banner
  // when the JSValue fallback list below it is non-empty: those JSValue
  // occurrences are themselves widened TypeScript boundary surfaces and
  // count as unsupported in any practical sense.
  if unsupported_exports.length() == 0 && jsvalue_fallbacks.length() > 0 {
    base = base.replace(
      old="No unsupported exports were detected.",
      new="No structural unsupported exports were detected; \{jsvalue_fallbacks.length()} `JSValue` boundary fallbacks are listed below.",
    )
  }
  let fallback_policy = render_unified_ts_fallback_policy_md(module_spec)
  if jsvalue_fallbacks.length() == 0 {
    return [base, "", fallback_policy].join("\n")
  }
  let lines = [
    base, "", fallback_policy, "", "## JSValue Fallbacks", "", "Strict mode treats these generated `JSValue` occurrences as unbudgeted TypeScript boundary fallbacks.",
    "",
  ]
  for item in jsvalue_fallbacks {
    lines.push("- " + item)
  }
  lines.join("\n")
}

///|
async fn write_unified_ts_scaffold_diagnostics(
  output_dir : String,
  diagnostics_path : String?,
  module_spec : String,
  unsupported_exports : Array[String],
  jsvalue_fallbacks : Array[String],
) -> Bool {
  let path = unified_ts_scaffold_diagnostics_path(output_dir, diagnostics_path)
  if !write_text_file(
      path,
      render_unified_ts_scaffold_diagnostics_md(
        module_spec, unsupported_exports, jsvalue_fallbacks,
      ),
    ) {
    return false
  }
  println("Wrote scaffold diagnostics to \{path}")
  true
}

///|
fn collect_unified_jsvalue_fallbacks_from_source(
  relative_path : String,
  source : String,
  out : Array[String],
) -> Unit {
  let mut line_no = 1
  for line_view in source.split("\n") {
    let line = line_view.trim().to_owned()
    if unified_jsvalue_line_is_fallback(line) {
      out.push("\{relative_path}:\{line_no}: \{line}")
    }
    line_no += 1
  }
}

///|
fn unified_jsvalue_line_is_fallback(line : String) -> Bool {
  if !line.contains("JSValue") {
    return false
  }
  match line {
    "/// Complex or unsupported TypeScript types are widened to JSValue."
    | "declare pub type JSValue"
    | "pub type JSValue"
    | "pub type JSValue = @js.Any" => false
    _ => true
  }
}

///|
async fn collect_unified_moonbit_scaffold_jsvalue_fallbacks(
  output_dir : String,
) -> Array[String] {
  let fallbacks : Array[String] = []
  for relative_path in ["bridge.mbti", "bridge.mbt"] {
    let path = main_join_path(output_dir, relative_path)
    let source = @fs.read_file(path).text() catch { _ => continue }
    collect_unified_jsvalue_fallbacks_from_source(
      relative_path, source, fallbacks,
    )
  }
  fallbacks.sort()
  fallbacks
}

///|
fn unified_autolink_diagnostics_has_omissions(source : String) -> Bool {
  source.contains("\n## ")
}

///|
async fn write_requested_unified_autolink_diagnostics(
  output_dir : String,
  diagnostics_path : String?,
) -> Bool {
  let path = match diagnostics_path {
    Some(path) => path
    None => return true
  }
  let autolink_path = main_join_path(output_dir, "AUTOLINK_DIAGNOSTICS.md")
  let diagnostics_md = @fs.read_file(autolink_path).text() catch {
    e => {
      println("Read error: \{e}")
      return false
    }
  }
  if !write_text_file(path, diagnostics_md) {
    return false
  }
  println("Wrote autolink diagnostics to \{path}")
  true
}

///|
async fn emit_unified_tsmbt_scaffold(
  input : String,
  out : String,
  direction~ : TsmbtDirection,
  module_spec~ : String?,
  import_rewrite_path~ : String?,
  diagnostics_path? : String? = None,
  strict? : Bool = false,
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
      let ok = if facade {
        emit_typescript_facade_scaffold_from_mbti(
          mbti_path, out, import_rewrite_path,
        )
      } else {
        emit_typescript_scaffold_from_mbti(mbti_path, out, import_rewrite_path)
      }
      if !ok {
        return false
      }
      let diagnostics_md = @fs.read_file(
        main_join_path(out, "AUTOLINK_DIAGNOSTICS.md"),
      ).text() catch {
        e => {
          println("Read error: \{e}")
          return false
        }
      }
      if !write_requested_unified_autolink_diagnostics(out, diagnostics_path) {
        return false
      }
      if strict && unified_autolink_diagnostics_has_omissions(diagnostics_md) {
        println(
          "Strict mode rejected MoonBit scaffold: omitted autolink members detected.",
        )
        return false
      }
      true
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
      let unsupported_exports = collect_moonbit_ts_scaffold_unsupported_exports(
        entry_path,
      ) catch {
        @bridge.ModuleGraphError::ReadError(msg)
        | @bridge.ModuleGraphError::ParseError(msg)
        | @bridge.ModuleGraphError::ResolveError(msg) => {
          println("Emit error: \{msg}")
          return false
        }
      }
      if strict && unsupported_exports.length() > 0 {
        if !write_unified_ts_scaffold_diagnostics(
            out,
            diagnostics_path,
            runtime_module_spec,
            unsupported_exports,
            [],
          ) {
          return false
        }
        println(
          "Strict mode rejected TypeScript scaffold: unsupported exports detected.",
        )
        return false
      }
      if !emit_moonbit_scaffold_from_ts(
          entry_path,
          runtime_module_spec,
          out,
          write_diagnostics=false,
        ) {
        return false
      }
      let jsvalue_fallbacks = collect_unified_moonbit_scaffold_jsvalue_fallbacks(
        out,
      )
      if !write_unified_ts_scaffold_diagnostics(
          out, diagnostics_path, runtime_module_spec, unsupported_exports, jsvalue_fallbacks,
        ) {
        return false
      }
      if strict && jsvalue_fallbacks.length() > 0 {
        println(
          "Strict mode rejected TypeScript scaffold: JSValue fallbacks detected.",
        )
        return false
      }
      true
    }
    TsmbtDirection::Auto => true
  }
}

///|
fn mbt2ts_pkg_path_is_absolute(path : String) -> Bool {
  path.has_prefix("/")
}

///|
fn mbt2ts_pkg_source_root(
  project_root : String,
  moon_mod_source : String,
) -> String {
  match parse_moon_mod_string_field(moon_mod_source, "source") {
    Some(source) if source != "" && source != "." =>
      main_join_path(project_root, source)
    _ => project_root
  }
}

///|
/// Development commands are executable implementation details, not library
/// subpath exports. Every other source directory with a `moon.pkg` becomes a
/// publishable npm submodule.
fn mbt2ts_pkg_skip_submodule_dir(name : String) -> Bool {
  unified_tsmbt_skip_scan_dir(name) ||
  name == "cmd" ||
  name.has_prefix("__tsmbt_")
}

///|
fn mbt2ts_pkg_skip_command_scan_dir(name : String) -> Bool {
  unified_tsmbt_skip_scan_dir(name) || name.has_prefix("__tsmbt_")
}

///|
fn mbt2ts_pkg_line_defines_main(line : String, prefix : String) -> Bool {
  if !line.has_prefix(prefix) {
    return false
  }
  if line.length() == prefix.length() {
    return true
  }
  let next = line[prefix.length()].unsafe_to_char()
  next == ' ' || next == '(' || next == '{'
}

///|
fn mbt2ts_pkg_source_defines_main(source : String) -> Bool {
  for line_view in source.split("\n") {
    let line = line_view.trim().to_owned()
    if mbt2ts_pkg_line_defines_main(line, "fn main") ||
      mbt2ts_pkg_line_defines_main(line, "async fn main") ||
      mbt2ts_pkg_line_defines_main(line, "pub fn main") ||
      mbt2ts_pkg_line_defines_main(line, "pub async fn main") {
      return true
    }
  }
  false
}

///|
fn mbt2ts_pkg_last_path_segment(path : String) -> String {
  match path.rev_find("/") {
    Some(idx) => path[idx + 1:path.length()].to_owned()
    None => path
  }
}

///|
fn mbt2ts_pkg_root_command_name(root_package_name : String) -> String {
  mbt2ts_pkg_last_path_segment(root_package_name)
}

///|
fn mbt2ts_pkg_command_name(
  source_relative_dir : String,
  root_package_name : String,
) -> String {
  if source_relative_dir == "" {
    mbt2ts_pkg_root_command_name(root_package_name)
  } else {
    mbt2ts_pkg_last_path_segment(source_relative_dir)
  }
}

///|
fn mbt2ts_pkg_quoted_strings(source : String) -> Array[String] {
  let values : Array[String] = []
  let mut cursor = 0
  while cursor < source.length() {
    let remaining = source[cursor:].to_owned()
    match remaining.find("\"") {
      None => return values
      Some(open_relative) => {
        let value_start = cursor + open_relative + 1
        let after_open = source[value_start:].to_owned()
        match after_open.find("\"") {
          None => return values
          Some(close_relative) => {
            values.push(
              source[value_start:value_start + close_relative].to_owned(),
            )
            cursor = value_start + close_relative + 1
          }
        }
      }
    }
  }
  values
}

///|
fn mbt2ts_pkg_normalize_excluded_source_dir(
  path : String,
  source_root_rel : String,
) -> String? {
  let normalized = path.trim().to_owned()
  if normalized == "" {
    return None
  }
  let source_root = source_root_rel.trim().to_owned()
  if source_root == "" || source_root == "." {
    return Some(normalized)
  }
  if normalized == source_root {
    return Some("")
  }
  let source_prefix = source_root + "/"
  if normalized.has_prefix(source_prefix) {
    return Some(normalized[source_prefix.length():].to_owned())
  }
  // MoonBit accepts an exclusion relative to the source root as well as a
  // module-root-relative one. Keeping the value lets either form match.
  Some(normalized)
}

///|
fn mbt2ts_pkg_manifest_excluded_command_dirs(
  moon_mod_source : String,
  source_root_rel : String,
) -> Array[String] {
  let dirs : Array[String] = []
  let mut cursor = 0
  while cursor < moon_mod_source.length() {
    let remaining = moon_mod_source[cursor:].to_owned()
    match remaining.find("exclude") {
      None => return dirs
      Some(exclude_relative) => {
        let after_key = cursor + exclude_relative + "exclude".length()
        let after_key_source = moon_mod_source[after_key:].to_owned()
        match after_key_source.find("[") {
          None => cursor = after_key
          Some(open_relative) => {
            let values_start = after_key + open_relative + 1
            let values_tail = moon_mod_source[values_start:].to_owned()
            match values_tail.find("]") {
              None => return dirs
              Some(close_relative) => {
                let values_source = moon_mod_source[values_start:values_start +
                close_relative].to_owned()
                for path in mbt2ts_pkg_quoted_strings(values_source) {
                  match
                    mbt2ts_pkg_normalize_excluded_source_dir(
                      path, source_root_rel,
                    ) {
                    Some(dir) if !dirs.contains(dir) => dirs.push(dir)
                    _ => ()
                  }
                }
                cursor = values_start + close_relative + 1
              }
            }
          }
        }
      }
    }
  }
  dirs
}

///|
fn mbt2ts_pkg_command_dir_is_excluded(
  source_relative_dir : String,
  excluded_dirs : Array[String],
) -> Bool {
  excluded_dirs.any(fn(excluded) {
    source_relative_dir == excluded ||
    source_relative_dir.has_prefix(excluded + "/")
  })
}

///|
async fn mbt2ts_pkg_collect_commands_from_dir(
  source_root : String,
  source_relative_dir : String,
  root_package_name : String,
  excluded_dirs : Array[String],
  commands : Array[Mbt2tsPkgCommand],
) -> Bool {
  if mbt2ts_pkg_command_dir_is_excluded(source_relative_dir, excluded_dirs) {
    return true
  }
  let dir = if source_relative_dir == "" {
    source_root
  } else {
    main_join_path(source_root, source_relative_dir)
  }
  let moon_pkg_path = main_join_path(dir, "moon.pkg")
  let main_path = main_join_path(dir, "main.mbt")
  if main_file_exists(moon_pkg_path) && main_file_exists(main_path) {
    let main_source = @fs.read_file(main_path).text() catch {
      e => {
        println("Error: --pkg could not read command source \{main_path}: \{e}")
        return false
      }
    }
    if mbt2ts_pkg_source_defines_main(main_source) {
      let name = mbt2ts_pkg_command_name(source_relative_dir, root_package_name)
      if name == "" || commands.any(fn(command) { command.name == name }) {
        println("Error: --pkg found duplicate or empty command name \{name}")
        return false
      }
      commands.push({ name, source_relative_dir })
    }
  }
  let entries = @fs.readdir(
    dir,
    include_hidden=false,
    include_special=false,
    sort=true,
  ) catch {
    e => {
      println("Error: --pkg could not read source directory \{dir}: \{e}")
      return false
    }
  }
  for name in entries {
    if mbt2ts_pkg_skip_command_scan_dir(name) {
      continue
    }
    let child_dir = main_join_path(dir, name)
    let kind = @fs.kind(child_dir, follow_symlink=false) catch {
      _ => @fs.FileKind::Unknown
    }
    if !(kind is @fs.FileKind::Directory) {
      continue
    }
    let child_relative_dir = if source_relative_dir == "" {
      name
    } else {
      source_relative_dir + "/" + name
    }
    if !mbt2ts_pkg_collect_commands_from_dir(
        source_root, child_relative_dir, root_package_name, excluded_dirs, commands,
      ) {
      return false
    }
  }
  true
}

///|
async fn mbt2ts_pkg_collect_commands(
  source_root : String,
  root_package_name : String,
  source_root_rel : String,
  moon_mod_source : String,
) -> Array[Mbt2tsPkgCommand]? {
  let commands : Array[Mbt2tsPkgCommand] = []
  let excluded_dirs = mbt2ts_pkg_manifest_excluded_command_dirs(
    moon_mod_source, source_root_rel,
  )
  if !mbt2ts_pkg_collect_commands_from_dir(
      source_root, "", root_package_name, excluded_dirs, commands,
    ) {
    return None
  }
  Some(commands)
}

///|
/// Collect generated interfaces for every library package below the source
/// root. `moon info` runs before this scan, so a package without its generated
/// interface is an actionable generation failure rather than a silent omission.
async fn mbt2ts_pkg_collect_submodule_mbti_paths(
  dir : String,
  paths : Array[String],
) -> Bool {
  let entries = @fs.readdir(
    dir,
    include_hidden=false,
    include_special=false,
    sort=true,
  ) catch {
    e => {
      println("Error: --pkg could not read source directory \{dir}: \{e}")
      return false
    }
  }
  for name in entries {
    if mbt2ts_pkg_skip_submodule_dir(name) {
      continue
    }
    let path = main_join_path(dir, name)
    let kind = @fs.kind(path, follow_symlink=false) catch {
      _ => @fs.FileKind::Unknown
    }
    if !(kind is @fs.FileKind::Directory) {
      continue
    }
    let moon_pkg_path = main_join_path(path, "moon.pkg")
    if main_file_exists(moon_pkg_path) {
      let mbti_path = main_join_path(path, "pkg.generated.mbti")
      if !main_file_exists(mbti_path) {
        println(
          "Error: moon info did not generate submodule interface \{mbti_path}",
        )
        return false
      }
      paths.push(mbti_path)
    }
    if !mbt2ts_pkg_collect_submodule_mbti_paths(path, paths) {
      return false
    }
  }
  true
}

///|
/// Select the local source submodules that belong to the root MoonBit package.
/// The generated umbrella MBTI below makes otherwise-unreferenced packages
/// visible to the existing recursive TypeScript scaffold emitter.
async fn mbt2ts_pkg_collect_submodule_names(
  source_root : String,
  root_package_name : String,
) -> Array[String]? {
  let paths : Array[String] = []
  if !mbt2ts_pkg_collect_submodule_mbti_paths(source_root, paths) {
    return None
  }
  let names : Array[String] = []
  let prefix = root_package_name + "/"
  for path in paths {
    let source = @fs.read_file(path).text() catch {
      e => {
        println("Error: --pkg could not read submodule interface \{path}: \{e}")
        return None
      }
    }
    let name = match parse_mbti_package_name_from_source(source) {
      Some(name) => name
      None => {
        println(
          "Error: --pkg submodule interface has no package declaration: \{path}",
        )
        return None
      }
    }
    if !name.has_prefix(prefix) {
      println(
        "Error: --pkg submodule \{name} is outside root package \{root_package_name}",
      )
      return None
    }
    if !names.contains(name) {
      names.push(name)
    }
  }
  names.sort()
  Some(names)
}

///|
/// Preserve the real root declarations while adding synthetic local imports.
/// The bridge emitter already knows how to turn a recursively loaded MBTI
/// graph into npm subpath exports; this only supplies the complete graph.
fn mbt2ts_pkg_render_umbrella_mbti(
  root_source : String,
  submodule_names : Array[String],
) -> String {
  let lines : Array[String] = []
  let mut inserted_imports = false
  for line_view in root_source.split("\n") {
    let line = line_view.to_owned()
    lines.push(line)
    if !inserted_imports && line.trim().has_prefix("package \"") {
      lines.push("")
      lines.push("import {")
      for idx in 0..<submodule_names.length() {
        lines.push("  \"\{submodule_names[idx]}\" @tsmbt_submodule_\{idx},")
      }
      lines.push("}")
      inserted_imports = true
    }
  }
  lines.join("\n")
}

///|
fn mbt2ts_pkg_output_dir(project_root : String, requested : String?) -> String {
  match requested {
    Some(path) if mbt2ts_pkg_path_is_absolute(path) => path
    Some(path) => main_join_path(project_root, path)
    None => main_join_path(project_root, "npm")
  }
}

///|
fn mbt2ts_pkg_command_build_target(
  source_root_rel : String,
  source_relative_dir : String,
) -> String {
  let root = if source_root_rel == "." { "" } else { source_root_rel }
  if root == "" {
    source_relative_dir
  } else if source_relative_dir == "" {
    root
  } else {
    root + "/" + source_relative_dir
  }
}

///|
fn mbt2ts_pkg_command_build_output_dir(
  module_root : String,
  command : Mbt2tsPkgCommand,
) -> String {
  let build_root = main_join_path(
    main_join_path(main_join_path(module_root, "_build"), "js"),
    "debug/build",
  )
  if command.source_relative_dir == "" {
    build_root
  } else {
    main_join_path(build_root, command.source_relative_dir)
  }
}

///|
async fn mbt2ts_pkg_copy_command_bin(
  built_js_path : String,
  command : Mbt2tsPkgCommand,
  output_dir : String,
) -> Bool {
  let source = @fs.read_file(built_js_path).text() catch {
    e => {
      println(
        "Error: --pkg could not read command build output \{built_js_path}: \{e}",
      )
      return false
    }
  }
  let command_js_name = command.name + ".js"
  let rendered = rewrite_moonbit_js_runtime_text(
    source,
    mbt2ts_pkg_last_path_segment(built_js_path) + ".map",
    command_js_name + ".map",
  )
  let bin_path = main_join_path(
    main_join_path(output_dir, "bin"),
    command_js_name,
  )
  let _ = ensure_dir_tree(main_dirname(bin_path)) catch {
    e => {
      println("Write error: could not create command bin directory: \{e}")
      return false
    }
  }
  let script = if rendered.has_prefix("#!") {
    rendered
  } else {
    "#!/usr/bin/env node\n" + rendered
  }
  let _ = @fs.write_file(bin_path, string_to_bytes(script), create=0o755) catch {
    e => {
      println("Write error: could not write command bin \{bin_path}: \{e}")
      return false
    }
  }
  let map_path = built_js_path + ".map"
  if @fs.exists(map_path) &&
    !copy_binary_file(
      map_path,
      main_join_path(
        main_join_path(output_dir, "bin"),
        command_js_name + ".map",
      ),
    ) {
    return false
  }
  true
}

///|
async fn emit_mbt2ts_pkg_command_bins(
  module_root : String,
  source_root_rel : String,
  output_dir : String,
  commands : Array[Mbt2tsPkgCommand],
) -> Bool {
  for command in commands {
    let target = mbt2ts_pkg_command_build_target(
      source_root_rel,
      command.source_relative_dir,
    )
    let args = ["-C", module_root, "build", "--target", "js"]
    if target != "" {
      args.push(target)
    }
    let (exit_code, output) = @process.collect_output_merged(
      "moon",
      args,
      cwd=".",
    )
    if exit_code != 0 {
      println("Error: --pkg could not build command \{command.name}")
      println(output.text())
      return false
    }
    let built_js_path = main_join_path(
      mbt2ts_pkg_command_build_output_dir(module_root, command),
      command.name + ".js",
    )
    if !mbt2ts_pkg_copy_command_bin(built_js_path, command, output_dir) {
      return false
    }
  }
  true
}

///|
fn mbt2ts_pkg_escape_json_string(source : String) -> String {
  let mut escaped = ""
  for c in source {
    if c == '\\' {
      escaped += "\\\\"
    } else if c == '"' {
      escaped += "\\\""
    } else if c == '\n' {
      escaped += "\\n"
    } else if c == '\r' {
      escaped += "\\r"
    } else if c == '\t' {
      escaped += "\\t"
    } else {
      escaped += c.to_string()
    }
  }
  escaped
}

///|
fn mbt2ts_pkg_publish_path_is_safe(path : String) -> Bool {
  path != "" &&
  !path.has_prefix("/") &&
  !path.contains("\\") &&
  !path.contains("..")
}

///|
fn mbt2ts_pkg_add_publish_path(paths : Array[String], path : String) -> Unit {
  if mbt2ts_pkg_publish_path_is_safe(path) && !paths.contains(path) {
    paths.push(path)
  }
}

///|
fn mbt2ts_pkg_collect_publish_paths(
  source : String,
  commands : Array[Mbt2tsPkgCommand],
) -> Array[String] {
  let paths : Array[String] = []
  for line_view in source.split("\n") {
    let line = line_view.to_owned()
    for marker in ["\"types\": \"./", "\"import\": \"./"] {
      match line.find(marker) {
        Some(index) => {
          let start = index + marker.length()
          let remainder = line[start:line.length()].to_owned()
          match remainder.find("\"") {
            Some(end) => {
              let path = remainder[:end].to_owned()
              mbt2ts_pkg_add_publish_path(paths, path)
              if path.has_suffix(".js") {
                mbt2ts_pkg_add_publish_path(paths, path + ".map")
              }
            }
            None => ()
          }
        }
        None => ()
      }
    }
  }
  for command in commands {
    let path = "bin/" + command.name + ".js"
    mbt2ts_pkg_add_publish_path(paths, path)
    mbt2ts_pkg_add_publish_path(paths, path + ".map")
  }
  paths.sort()
  paths
}

///|
fn mbt2ts_pkg_npm_repository_url(repository : String) -> String {
  if !repository.has_prefix("https://") {
    return repository
  }
  let git_url = "git+" + repository
  if git_url.has_suffix(".git") {
    git_url
  } else {
    git_url + ".git"
  }
}

///|
fn rewrite_mbt2ts_pkg_package_json(
  source : String,
  version : String,
  description : String?,
  license : String?,
  repository : String?,
  commands : Array[Mbt2tsPkgCommand],
) -> String? {
  let publish_paths = mbt2ts_pkg_collect_publish_paths(source, commands)
  if publish_paths.length() == 0 {
    return None
  }
  let lines : Array[String] = []
  let mut rewrote_version = false
  for line_view in source.split("\n") {
    let line = line_view.to_owned()
    if line.trim().has_prefix("\"version\":") {
      lines.push(
        "  \"version\": \"\{mbt2ts_pkg_escape_json_string(version)}\",",
      )
      match description {
        Some(value) =>
          lines.push(
            "  \"description\": \"\{mbt2ts_pkg_escape_json_string(value)}\",",
          )
        None => ()
      }
      match license {
        Some(value) =>
          lines.push(
            "  \"license\": \"\{mbt2ts_pkg_escape_json_string(value)}\",",
          )
        None => ()
      }
      match repository {
        Some(value) =>
          lines.push(
            "  \"repository\": { \"type\": \"git\", \"url\": \"\{mbt2ts_pkg_escape_json_string(mbt2ts_pkg_npm_repository_url(value))}\" },",
          )
        None => ()
      }
      if commands.length() > 0 {
        lines.push("  \"bin\": {")
        for idx in 0..<commands.length() {
          let command = commands[idx]
          let suffix = if idx + 1 < commands.length() { "," } else { "" }
          lines.push(
            "    \"\{mbt2ts_pkg_escape_json_string(command.name)}\": \"./bin/\{mbt2ts_pkg_escape_json_string(command.name)}.js\"\{suffix}",
          )
        }
        lines.push("  },")
      }
      lines.push("  \"files\": [")
      for idx in 0..<publish_paths.length() {
        let suffix = if idx + 1 < publish_paths.length() { "," } else { "" }
        lines.push(
          "    \"\{mbt2ts_pkg_escape_json_string(publish_paths[idx])}\"\{suffix}",
        )
      }
      lines.push("  ],")
      rewrote_version = true
    } else {
      lines.push(line)
    }
  }
  if !rewrote_version {
    return None
  }
  Some(lines.join("\n"))
}

///|
async fn copy_mbt2ts_pkg_publish_file(
  project_root : String,
  output_dir : String,
  candidate_names : Array[String],
) -> Bool {
  for name in candidate_names {
    let source = main_join_path(project_root, name)
    if main_file_exists(source) {
      return copy_binary_file(source, main_join_path(output_dir, name))
    }
  }
  true
}

///|
async fn copy_mbt2ts_pkg_publish_docs(
  project_root : String,
  output_dir : String,
) -> Bool {
  if !copy_mbt2ts_pkg_publish_file(project_root, output_dir, [
      "README.md", "README", "README.txt",
    ]) {
    return false
  }
  copy_mbt2ts_pkg_publish_file(project_root, output_dir, [
    "LICENSE", "LICENSE.md", "LICENSE.txt", "LICENCE", "LICENCE.md",
  ])
}

///|
/// Build the current MoonBit root package and write an npm publish directory.
///
/// This is deliberately project-oriented: it refreshes `pkg.generated.mbti`
/// from the module's `moon.mod`, sends the root source package through the
/// build-backed TypeScript scaffold, and then applies publish metadata owned
/// by the manifest. Low-level `--input` generation remains available for
/// tooling that already has an interface file.
async fn emit_typescript_npm_package_from_project(
  project_root : String,
  output_dir : String?,
  import_rewrite_path : String?,
  strict : Bool,
  facade : Bool,
) -> Bool {
  let module_root = @fs.realpath(project_root) catch { _ => project_root }
  let moon_mod_source = match read_moon_mod_source(module_root) {
    Some(source) => source
    None => {
      println("Error: --pkg could not read moon.mod from \{module_root}")
      return false
    }
  }
  let version = match parse_moon_mod_string_field(moon_mod_source, "version") {
    Some(version) if version != "" => version
    _ => {
      println("Error: --pkg requires a non-empty version in moon.mod")
      return false
    }
  }
  let description = parse_moon_mod_string_field(moon_mod_source, "description")
  let license = parse_moon_mod_string_field(moon_mod_source, "license")
  let repository = parse_moon_mod_string_field(moon_mod_source, "repository")
  let source_root_rel = match
    parse_moon_mod_string_field(moon_mod_source, "source") {
    Some(source) if source != "" => source
    _ => "."
  }
  let source_root = mbt2ts_pkg_source_root(module_root, moon_mod_source)
  let moon_pkg_path = main_join_path(source_root, "moon.pkg")
  if !main_file_exists(moon_pkg_path) {
    println(
      "Error: --pkg expects the module root package at \{moon_pkg_path}; add a root moon.pkg or use the lower-level --input flow.",
    )
    return false
  }
  let (info_exit, info_output) = @process.collect_output_merged(
    "moon",
    ["-C", module_root, "info"],
    cwd=".",
  )
  if info_exit != 0 {
    println("Error: moon info failed while preparing --pkg")
    println(info_output.text())
    return false
  }
  let mbti_path = main_join_path(source_root, "pkg.generated.mbti")
  if !main_file_exists(mbti_path) {
    println("Error: moon info did not generate \{mbti_path}")
    return false
  }
  let root_mbti_source = @fs.read_file(mbti_path).text() catch {
    e => {
      println("Error: --pkg could not read \{mbti_path}: \{e}")
      return false
    }
  }
  let root_package_name = match
    parse_mbti_package_name_from_source(root_mbti_source) {
    Some(name) => name
    None => {
      println(
        "Error: --pkg root interface has no package declaration: \{mbti_path}",
      )
      return false
    }
  }
  let submodule_names = match
    mbt2ts_pkg_collect_submodule_names(source_root, root_package_name) {
    Some(names) => names
    None => return false
  }
  let commands = match
    mbt2ts_pkg_collect_commands(
      source_root, root_package_name, source_root_rel, moon_mod_source,
    ) {
    Some(commands) => commands
    None => return false
  }
  let mut umbrella_mbti_path : String? = None
  let scaffold_mbti_path = if submodule_names.length() == 0 {
    mbti_path
  } else {
    let path = main_join_path(
      source_root, "__tsmbt_pkg_umbrella.generated.mbti",
    )
    if !write_text_file(
        path,
        mbt2ts_pkg_render_umbrella_mbti(root_mbti_source, submodule_names),
      ) {
      return false
    }
    umbrella_mbti_path = Some(path)
    path
  }
  let out = mbt2ts_pkg_output_dir(module_root, output_dir)
  let scaffold_ok = if facade {
    emit_typescript_facade_scaffold_from_mbti(
      scaffold_mbti_path, out, import_rewrite_path,
    )
  } else {
    emit_typescript_scaffold_from_mbti(
      scaffold_mbti_path, out, import_rewrite_path,
    )
  }
  match umbrella_mbti_path {
    Some(path) => {
      let _ = @fs.remove(path) catch { _ => () }
    }
    None => ()
  }
  if !scaffold_ok {
    return false
  }
  if !emit_mbt2ts_pkg_command_bins(module_root, source_root_rel, out, commands) {
    return false
  }
  let package_json_path = main_join_path(out, "package.json")
  let generated_package_json = @fs.read_file(package_json_path).text() catch {
    e => {
      println("Error: could not read generated package.json: \{e}")
      return false
    }
  }
  let publish_package_json = match
    rewrite_mbt2ts_pkg_package_json(
      generated_package_json, version, description, license, repository, commands,
    ) {
    Some(source) => source
    None => {
      println("Error: could not apply the moon.mod version to package.json")
      return false
    }
  }
  if !write_text_file(package_json_path, publish_package_json) {
    return false
  }
  if !copy_mbt2ts_pkg_publish_docs(module_root, out) {
    return false
  }
  let diagnostics_md = @fs.read_file(
    main_join_path(out, "AUTOLINK_DIAGNOSTICS.md"),
  ).text() catch {
    e => {
      println("Read error: \{e}")
      return false
    }
  }
  if strict && unified_autolink_diagnostics_has_omissions(diagnostics_md) {
    println(
      "Strict mode rejected MoonBit package: omitted autolink members detected.",
    )
    return false
  }
  println("Wrote publishable npm package to \{out}")
  true
}

///|
/// Run the unified `--input/--out/...` driver with a forced direction.
/// `print_help` is invoked on `--help`, missing required flags, or option
/// errors so each cmd module owns its own help banner.
async fn run_unified_cli_with_direction(
  args : Array[String],
  start : Int,
  forced_direction~ : TsmbtDirection,
  print_help~ : () -> Unit,
) -> Bool {
  let options = match parse_unified_tsmbt_options(args, start) {
    (Some(options), None) => options
    (_, Some("help")) => {
      print_help()
      return true
    }
    (_, Some(message)) => {
      println("Error: \{message}")
      print_help()
      return false
    }
    _ => {
      print_help()
      return false
    }
  }
  let direction = match (forced_direction, options.direction) {
    (TsmbtDirection::Auto, requested) => requested
    (TsmbtDirection::TsToMbt, TsmbtDirection::Auto)
    | (TsmbtDirection::TsToMbt, TsmbtDirection::TsToMbt) =>
      TsmbtDirection::TsToMbt
    (TsmbtDirection::MbtToTs, TsmbtDirection::Auto)
    | (TsmbtDirection::MbtToTs, TsmbtDirection::MbtToTs) =>
      TsmbtDirection::MbtToTs
    _ => {
      println(
        "Error: --direction conflicts with this command's fixed direction.",
      )
      return false
    }
  }
  let input = match options.input {
    Some(input) => input
    None => {
      println("Error: expected --input <pkg-or-entry>")
      print_help()
      return false
    }
  }
  let out = match options.out {
    Some(out) => out
    None => {
      println("Error: expected --out <dir>")
      print_help()
      return false
    }
  }
  emit_unified_tsmbt_scaffold(
    input,
    out,
    direction~,
    module_spec=options.module_spec,
    import_rewrite_path=options.import_rewrite_path,
    diagnostics_path=options.diagnostics_path,
    strict=options.strict,
    facade=options.facade,
  )
}

///|
/// Public entry: run the unified TS -> MoonBit scaffold driver with the
/// direction locked to `ts-to-mbt`. Used by `src/cmd/ts2mbt`.
pub async fn run_ts_to_mbt_unified_cli(
  args : Array[String],
  start : Int,
  print_help~ : () -> Unit,
) -> Bool {
  run_unified_cli_with_direction(
    args,
    start,
    forced_direction=TsmbtDirection::TsToMbt,
    print_help~,
  )
}

///|
/// Public entry: run the unified MoonBit -> TypeScript scaffold driver with
/// the direction locked to `mbt-to-ts`. Used by `src/cmd/mbt2ts`.
pub async fn run_mbt_to_ts_unified_cli(
  args : Array[String],
  start : Int,
  print_help~ : () -> Unit,
) -> Bool {
  run_unified_cli_with_direction(
    args,
    start,
    forced_direction=TsmbtDirection::MbtToTs,
    print_help~,
  )
}

///|
/// Public entry for `mbt2ts --pkg`. It discovers the enclosing MoonBit module
/// from the caller's working directory and leaves all package policy to the
/// project-level generator above.
pub async fn run_mbt_to_ts_pkg_cli(
  args : Array[String],
  start : Int,
  print_help~ : () -> Unit,
) -> Bool {
  let options = match parse_mbt2ts_pkg_options(args, start) {
    (Some(options), None) => options
    (_, Some("help")) => {
      print_help()
      return true
    }
    (_, Some(message)) => {
      println("Error: \{message}")
      print_help()
      return false
    }
    _ => {
      print_help()
      return false
    }
  }
  let cwd = @fs.realpath(".") catch { _ => "." }
  let module_root = match find_nearest_moon_mod_dir(cwd) {
    Some(root) => root
    None => {
      println(
        "Error: --pkg must run inside a MoonBit module containing moon.mod",
      )
      return false
    }
  }
  emit_typescript_npm_package_from_project(
    module_root,
    options.out,
    options.import_rewrite_path,
    options.strict,
    options.facade,
  )
}
