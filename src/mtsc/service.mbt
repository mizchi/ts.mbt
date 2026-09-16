// The language service.
//
// Modelled on TypeScript's `LanguageService`, and deliberately a small
// part of it. What is here is the part that needs the type checker: load
// the program a host describes, resolve its imports, and report
// diagnostics per file or for the whole program. What is not here —
// completions, quick info, definitions, renames, formatting — all needs
// position information that this checker does not produce (see
// `MtscDiagnostic` below), so it would be a shape with nothing behind it.
//
// The division of labour is the one that keeps the risky part small.
// This file discovers and resolves; the checking is `checker.mbt`'s
// `collect_parsed_graph_issues`, which predates it and is covered by the
// package's own tests and by whatever uses the `checkModuleGraph` ABI.
// A program loaded from a host ends up in exactly the representation a
// caller of that ABI would have built by hand, and is checked by the
// same code — so the host path cannot drift into answering differently
// from the pre-resolved path.

///|
/// One diagnostic, in the shape a JavaScript caller can use directly.
///
/// The field names are TypeScript's where TypeScript has one, because
/// the point is that an editor or bundler integration written against
/// `ts.Diagnostic` can render these without a translation layer.
///
/// `start` and `length` are ABSENT, and that is a fact about the checker
/// rather than a shortcut: `@checker.ExprIssue` carries a message and a
/// breadcrumb, `@parser.ParseError` carries a message, and neither
/// carries an offset — so there is no span to report and inventing one
/// would put a squiggle under the wrong code. `ts.Diagnostic` declares
/// both as optional for exactly this case (a diagnostic not tied to a
/// location), so a consumer that checks for them keeps working; one that
/// assumes them was already going to break on `tsc`'s own global
/// diagnostics.
///
/// `context` is what stands in for a span in the meantime — the
/// checker's dotted breadcrumb, e.g. `function foo > return`. It is
/// empty for diagnostics that have none.
pub(all) struct MtscDiagnostic {
  /// The file the diagnostic belongs to, as the host spelled it.
  file : String
  /// `"error"`. The checker has no warning tier; the field exists so the
  /// shape matches `ts.Diagnostic` for a consumer that switches on it.
  category : String
  /// Which phase produced it: `"syntactic"` for a parse failure,
  /// `"semantic"` for a type error, `"import"` for an unresolvable
  /// module or a missing export.
  ///
  /// This is what `getSemanticDiagnostics` and
  /// `getSyntacticDiagnostics` filter on, and it is carried on the
  /// diagnostic so a caller asking for everything at once can still
  /// tell them apart.
  source : String
  /// The human-readable message.
  messageText : String
  /// Where inside the file, as a dotted breadcrumb, or `""`.
  context : String
}

///|
/// A resolved import, for `resolveModuleName`.
///
/// `resolvedFileName` is empty when nothing resolved, and `isExternal`
/// says whether that was a failure or simply out of scope: a bare
/// specifier like `react` is not something this resolver claims to
/// handle (see `resolve.mbt`), and reporting it as a failure would tell
/// a caller to go looking for a file that was never meant to exist.
pub(all) struct MtscResolvedModule {
  resolvedFileName : String
  isExternal : Bool
}

///|
/// A program: every file reachable from the host's roots, parsed, with
/// the import edges between them.
priv struct MtscProgram {
  modules : Array[ParsedMtscModule]
  edges : Array[MtscModuleEdge]
  // Files the host supplied that did not parse.
  //
  // Recorded here rather than re-derived later, and the first draft of
  // this file got that wrong in a way worth keeping a note about: it
  // re-parsed `modules` to look for failures, and `modules` holds
  // exactly the files that PARSED — so the check could never fire and
  // every syntax error in the program would have been reported as
  // nothing at all.
  parse_errors : Array[(String, String)]
  // Paths the program named but the host could not supply text for.
  // Reported as diagnostics rather than dropped, because a root that
  // silently does not exist is a program that silently checks nothing.
  missing_files : Array[String]
}

///|
/// Every module specifier `module_` imports or re-exports.
///
/// Both lists are read, and that is the point: `export * from "./x"` and
/// `export { a } from "./x"` pull `./x` into the program exactly as an
/// `import` does, and a loader that walked only `imports` would leave
/// every barrel's target unresolved while looking like it worked for
/// direct imports.
fn mtsc_module_specifiers(module_ : ParsedMtscModule) -> Array[String] {
  let out : Array[String] = []
  for import_ in module_.module_block.imports {
    mtsc_push_unique(out, import_.module_spec)
  }
  for reexport_ in module_.module_block.reexports {
    mtsc_push_unique(out, reexport_.module_spec)
  }
  out
}

///|
/// Load the program the host describes.
///
/// Breadth-first from the roots, following resolvable relative
/// specifiers. Each file is parsed once and each path is read once —
/// see `MtscSourceCache`.
fn[H : MtscHost] mtsc_load_program(host : H) -> MtscProgram {
  let options = host.compilation_settings()
  let cache = MtscSourceCache::new()
  let modules : Array[ParsedMtscModule] = []
  let edges : Array[MtscModuleEdge] = []
  let parse_errors : Array[(String, String)] = []
  let missing_files : Array[String] = []
  let seen : Map[String, Bool] = Map([])
  let pending : Array[String] = []

  // Roots first, in the order the host gave them, so diagnostics come
  // back in an order the caller can predict.
  for root in host.script_file_names() {
    let path = mtsc_root_path(host, root)
    if !seen.contains(path) {
      seen[path] = true
      pending.push(path)
    }
  }
  let mut cursor = 0
  while cursor < pending.length() {
    let path = pending[cursor]
    cursor = cursor + 1
    let source = match cache.read(host, path) {
      Some(text) => text
      None => {
        missing_files.push(path)
        continue
      }
    }
    let module_source : MtscModuleSource = {
      path,
      source,
      allowJsx: mtsc_allow_jsx_for(path, options),
    }
    // A file that does not parse yields no imports to follow, so the
    // walk stops there — but the failure is kept, because a syntax
    // error is the diagnostic the caller most needs.
    let parsed = match parse_graph_module(module_source) {
      Ok(parsed) => parsed
      Err(e) => {
        parse_errors.push((path, e))
        continue
      }
    }
    modules.push(parsed)
    for specifier in mtsc_module_specifiers(parsed) {
      match mtsc_resolve_module(host, cache, path, specifier) {
        Some(target) => {
          edges.push({
            importerPath: path,
            moduleSpecifier: specifier,
            targetPath: target,
          })
          if !seen.contains(target) {
            seen[target] = true
            pending.push(target)
          }
        }
        // Unresolved. No edge, and deliberately no diagnostic here:
        // `graph_import_globals` already reports an unresolvable LOCAL
        // specifier and stays silent on a bare one, so a rule written
        // here would be a second copy of that judgement — and the two
        // could only disagree.
        None => ()
      }
    }
  }
  { modules, edges, parse_errors, missing_files, }
}

///|
/// Classify a `MtscGraphIssue`'s `path` field into a diagnostic source.
///
/// `collect_parsed_graph_issues` tags a parse failure `"parse"` and an
/// import problem `"import"`, and leaves everything else carrying the
/// checker's breadcrumb — which is what makes the breadcrumb usable as
/// the discriminator: a type error's `path` is never one of the two
/// reserved words.
fn mtsc_diagnostic_source(issue_path : String) -> String {
  if issue_path == "parse" {
    return "syntactic"
  }
  if issue_path == "import" {
    return "import"
  }
  "semantic"
}

///|
/// Every diagnostic for the whole program.
pub fn[H : MtscHost] get_program_diagnostics(host : H) -> Array[MtscDiagnostic] {
  let program = mtsc_load_program(host)
  let out : Array[MtscDiagnostic] = []
  for path in program.missing_files {
    out.push({
      file: path,
      category: "error",
      source: "import",
      messageText: "cannot read file `\{path}`",
      context: "",
    })
  }
  let issues : Array[MtscGraphIssue] = []
  for failure in program.parse_errors {
    issues.push({
      modulePath: failure.0,
      path: "parse",
      message: "parse error: \{failure.1}",
    })
  }
  collect_parsed_graph_issues(program.modules, program.edges, issues)
  for issue in issues {
    out.push({
      file: issue.modulePath,
      category: "error",
      source: mtsc_diagnostic_source(issue.path),
      messageText: issue.message,
      context: if issue.path == "parse" || issue.path == "import" {
        ""
      } else {
        issue.path
      },
    })
  }
  out
}

///|
/// Diagnostics for one file, keeping only the requested kinds.
///
/// The whole program is loaded either way, and it has to be: `file`'s
/// type errors depend on the declarations its imports supply, so
/// checking it alone would report every imported type as unresolved.
/// That is the same reason `collect_module_graph_issues` exists rather
/// than a per-file entry point, and it is what TypeScript does too —
/// `getSemanticDiagnostics(fileName)` is a query against a program, not
/// a compilation of one file.
///
/// So this has a COST MODEL, and it is the caller's to respect: one call
/// is one whole-program load, which makes a loop over every file
/// quadratic in the program. `get_program_diagnostics` is the one-pass
/// form and is what "check everything" should call. TypeScript avoids
/// the same trap by caching per file behind `getScriptVersion`, and
/// caching here would need that version channel to invalidate against —
/// the host does not have one, and a cache with no invalidation is worse
/// than a documented cost. Left as a cost rather than papered over; the
/// version method is the thing to add if per-file querying ever becomes
/// the hot path.
fn[H : MtscHost] mtsc_file_diagnostics(
  host : H,
  file : String,
  want_syntactic : Bool,
  want_semantic : Bool,
) -> Array[MtscDiagnostic] {
  let wanted = mtsc_root_path(host, file)
  let out : Array[MtscDiagnostic] = []
  for diagnostic in get_program_diagnostics(host) {
    if diagnostic.file != file && diagnostic.file != wanted {
      continue
    }
    let keep = match diagnostic.source {
      "syntactic" => want_syntactic
      // An unresolvable import is a semantic problem in TypeScript's
      // terms — the file parses — so it rides with the semantic set
      // rather than being a third thing a caller has to ask for.
      "import" => want_semantic
      _ => want_semantic
    }
    if keep {
      out.push(diagnostic)
    }
  }
  out
}

///|
/// Type errors for one file.
pub fn[H : MtscHost] get_semantic_diagnostics(
  host : H,
  file : String,
) -> Array[MtscDiagnostic] {
  mtsc_file_diagnostics(host, file, false, true)
}

///|
/// Parse errors for one file.
pub fn[H : MtscHost] get_syntactic_diagnostics(
  host : H,
  file : String,
) -> Array[MtscDiagnostic] {
  mtsc_file_diagnostics(host, file, true, false)
}

///|
/// Every file in the program, roots first, then what they reach.
///
/// The counterpart of `ts.Program.getSourceFiles().map(f => f.fileName)`,
/// and the cheapest way for a caller to see what resolution actually
/// found — a build tool watching these paths is watching the program
/// rather than the entry list, which is the distinction `--watch` in the
/// CLI had to make too.
pub fn[H : MtscHost] get_program_file_names(host : H) -> Array[String] {
  let program = mtsc_load_program(host)
  let out : Array[String] = []
  for module_ in program.modules {
    out.push(module_.source.path)
  }
  out
}

///|
/// Type-check a set of files, with every one of them a root.
///
/// The short form of the whole API: hand over a map of path to source
/// and get the diagnostics. Resolution between the files still happens,
/// so a program spread across several modules is checked as a program
/// rather than file by file — which is the thing `checkModuleGraph`
/// asked the caller to arrange for itself.
///
/// For anything that needs its own filesystem, its own root set, or a
/// virtual module layer, build a host and call
/// `get_program_diagnostics` instead; this is that, with the obvious
/// host supplied.
pub fn check_files(
  files : Map[String, String],
  jsx? : Bool = false,
) -> Array[MtscDiagnostic] {
  get_program_diagnostics(MtscMemoryHost::over(files, jsx~))
}

///|
/// Resolve one specifier, the way the loader would.
///
/// Exposed because a build tool usually has to resolve the same edges
/// for its own graph, and two resolvers disagreeing is how a plugin ends
/// up checking a different program than it bundles.
pub fn[H : MtscHost] resolve_module_name(
  host : H,
  importer : String,
  specifier : String,
) -> MtscResolvedModule {
  let cache = MtscSourceCache::new()
  let from = mtsc_root_path(host, importer)
  match mtsc_resolve_module(host, cache, from, specifier) {
    Some(path) => { resolvedFileName: path, isExternal: false, }
    None =>
      {
        resolvedFileName: "",
        isExternal: !mtsc_is_relative_specifier(specifier),
      }
  }
}
