// `mtsc conformance` — corpus accuracy, without the test harness.
//
// It replicates the parser package's "checker: accuracy against
// TypeScript conformance baselines" whitebox test. That test bundles
// every parser test into a ~25 MB generated C unit `tcc` can take many
// minutes to build; running the same measurement from the CLI lets the
// recall / false-positive numbers be read without paying that cost.
//
//   mtsc conformance                       # walks the pinned conformance dirs, prints the 2x2 table
//   mtsc conformance --list-misses         # also print every recall miss (`RECALL_MISS <case>`)
//                                          # and every false positive (`FALSE_POS <case> :: <path> :: <message>`)
//   mtsc conformance --list-misses <substr> # ...restricted to paths containing <substr>
//
// This was the `tsacc` binary. Its reason for being separate was build
// cost — it linked only `parser` + `checker` — and that reason is gone:
// `mtsc` already links both through `transform`, so the separate binary
// was paying for a link of its own and buying nothing.

///|
fn ts_case_basename(path : String) -> String {
  let parts = path.split("/")
  let arr : Array[StringView] = []
  for p in parts {
    arr.push(p)
  }
  let mut name = if arr.length() == 0 {
    path
  } else {
    arr[arr.length() - 1].to_owned()
  }
  if name.has_suffix(".tsx") {
    name = name[:name.length() - 4].to_owned()
  } else if name.has_suffix(".ts") {
    name = name[:name.length() - 3].to_owned()
  }
  name
}

///|
async fn collect_baseline_basenames() -> Map[String, Bool] {
  let dir = "typescript/tests/baselines/reference"
  let entries = @fs.readdir(
    dir,
    include_hidden=false,
    include_special=false,
    sort=false,
  ) catch {
    _ => []
  }
  let suffix = ".errors.txt"
  let set : Map[String, Bool] = Map([])
  for name in entries {
    if name.has_suffix(suffix) {
      let stem = name[:name.length() - suffix.length()].to_owned()
      match stem.find("(") {
        Some(i) => set[stem[:i].to_owned()] = true
        None => ()
      }
      set[stem] = true
    }
  }
  set
}

///|
async fn collect_ts_source_files_recursive(dir : String) -> Array[String] {
  let kind = @fs.kind(dir, follow_symlink=false) catch {
    _ => @fs.FileKind::Unknown
  }
  if !(kind is @fs.FileKind::Directory) {
    return []
  }
  let entries = @fs.readdir(
    dir,
    include_hidden=false,
    include_special=false,
    sort=true,
  ) catch {
    _ => []
  }
  let files : Array[String] = []
  for name in entries {
    let path = dir + "/" + name
    if name.has_suffix(".ts") && !name.has_suffix(".d.ts") {
      files.push(path)
    } else {
      let sub_kind = @fs.kind(path, follow_symlink=false) catch {
        _ => @fs.FileKind::Unknown
      }
      if sub_kind is @fs.FileKind::Directory {
        for f in collect_ts_source_files_recursive(path) {
          files.push(f)
        }
      }
    }
  }
  files
}

///|
/// `mtsc conformance` — the checker's accuracy against the pinned
/// TypeScript conformance baselines.
///
/// `start` is the index of the first option, so the verb dispatch in
/// `driver.mbt` passes `2`. Every line it prints is unchanged from the
/// `tsacc` binary this replaces: the 2x2 table and the per-directory
/// breakdown are read by hand and by `docs/tsacc.md`, and a reworded
/// summary would invalidate every number recorded against it.
async fn mtsc_run_conformance(argv : Array[String], start : Int) -> Unit {
  // `--list-misses [substr]`: in addition to the 2x2 table, print one
  // `RECALL_MISS <case>` line per baseline-positive file we fail to flag
  // (a recall miss), optionally filtered to paths containing `substr`.
  // Handy for triaging which conformance cases to target next without
  // ad-hoc instrumentation.
  let mut list_misses = false
  let mut miss_filter = ""
  for i in start..<argv.length() {
    if argv[i] == "--list-misses" {
      list_misses = true
      if i + 1 < argv.length() && !argv[i + 1].has_prefix("--") {
        miss_filter = argv[i + 1]
      }
    }
  }
  let baseline_index = collect_baseline_basenames()
  let dirs = [
    "typescript/tests/cases/conformance/types/typeParameters", "typescript/tests/cases/conformance/controlFlow",
    "typescript/tests/cases/conformance/expressions/typeGuards", "typescript/tests/cases/conformance/types/typeGuards",
    "typescript/tests/cases/conformance/types/union", "typescript/tests/cases/conformance/types/intersection",
    "typescript/tests/cases/conformance/types/tuple", "typescript/tests/cases/conformance/types/literal",
    "typescript/tests/cases/conformance/types/conditional", "typescript/tests/cases/conformance/types/never",
    "typescript/tests/cases/conformance/types/unknown", "typescript/tests/cases/conformance/types/any",
    "typescript/tests/cases/conformance/types/keyof", "typescript/tests/cases/conformance/types/typeAliases",
    "typescript/tests/cases/conformance/types/objectTypeLiteral", "typescript/tests/cases/conformance/types/primitives",
    "typescript/tests/cases/conformance/types/stringLiteral", "typescript/tests/cases/conformance/types/uniqueSymbol",
    "typescript/tests/cases/conformance/types/rest", "typescript/tests/cases/conformance/types/specifyingTypes",
    "typescript/tests/cases/conformance/types/contextualTypes", "typescript/tests/cases/conformance/types/namedTypes",
    "typescript/tests/cases/conformance/types/typeRelationships", "typescript/tests/cases/conformance/types/nonPrimitive",
    "typescript/tests/cases/conformance/classes/propertyMemberDeclarations", "typescript/tests/cases/conformance/classes/classDeclarations",
    "typescript/tests/cases/conformance/classes/constructorDeclarations", "typescript/tests/cases/conformance/classes/classExpressions",
    "typescript/tests/cases/conformance/classes/indexMemberDeclarations", "typescript/tests/cases/conformance/classes/members",
  ]
  let mut total = 0
  let mut parsed = 0
  let mut recall_hit = 0
  let mut recall_miss = 0
  let mut precision_hit = 0
  let mut precision_miss = 0
  let per_dir : Map[String, (Int, Int, Int, Int)] = Map([])
  for dir in dirs {
    let files = collect_ts_source_files_recursive(dir)
    let mut d_rh = 0
    let mut d_rm = 0
    let mut d_ph = 0
    let mut d_pm = 0
    for path in files {
      total += 1
      let content = @fs.read_file(path).text() catch { _ => continue }
      let allow_jsx = path.has_suffix(".tsx")
      let case_name = ts_case_basename(path)
      let has_baseline = baseline_index.contains(case_name)
      let module_ = try
        @parser.Parser::from_source_with_jsx(content, allow_jsx).parse_module()
      catch {
        _ => {
          if has_baseline {
            recall_hit += 1
            d_rh += 1
          } else {
            precision_miss += 1
            d_pm += 1
          }
          continue
        }
      } noraise {
        m => {
          parsed += 1
          m
        }
      }
      let issues = @checker.check_module_function_bodies_permissive(module_)
      if issues.length() > 0 {
        if has_baseline {
          recall_hit += 1
          d_rh += 1
        } else {
          precision_miss += 1
          d_pm += 1
          if list_misses && (miss_filter == "" || path.contains(miss_filter)) {
            for iss in issues {
              println("FALSE_POS \{case_name} :: \{iss.path} :: \{iss.message}")
            }
          }
        }
      } else if has_baseline {
        recall_miss += 1
        d_rm += 1
        if list_misses && (miss_filter == "" || path.contains(miss_filter)) {
          println("RECALL_MISS \{case_name}")
        }
      } else {
        precision_hit += 1
        d_ph += 1
      }
    }
    per_dir[dir] = (d_rh, d_rm, d_ph, d_pm)
  }
  println(
    "=== per-directory breakdown (recall_hit / recall_miss / precision_hit / precision_miss) ===",
  )
  for kv in per_dir {
    println("  \{kv.0}: \{kv.1.0} / \{kv.1.1} / \{kv.1.2} / \{kv.1.3}")
  }
  let with_baseline = recall_hit + recall_miss
  let without_baseline = precision_hit + precision_miss
  println(
    "baseline accuracy: parsed=\{parsed}/\{total} | recall=\{recall_hit}/\{with_baseline} | precision=\{precision_hit}/\{without_baseline} (false-positives=\{precision_miss})",
  )
}
