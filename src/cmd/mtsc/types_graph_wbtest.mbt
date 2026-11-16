///|
/// Write `files` (relative path -> text) under a fresh `root`.
async fn types_graph_fixture(
  root : String,
  files : Array[(String, String)],
) -> Unit {
  @fs.rmdir(root, recursive=true) catch {
    _ => ()
  }
  for entry in files {
    let path = root + "/" + entry.0
    // Several files share a directory, and `mkdir` refuses one that exists.
    @fs.mkdir(mtsc_dirname(path), permission=0o755, recursive=true) catch {
      _ => ()
    }
    @fs.write_file(path, entry.1, create=0o644)
  }
}

///|
/// Load `entry` the way the CHECK does (`types_resolution`) or the way the
/// bundler does, and return the files and edges the walk produced.
async fn types_graph_load(
  entry : String,
  types_resolution : Bool,
) -> (Map[String, String], Array[@mtsc_core.MtscModuleEdge]) {
  let files : Map[String, String] = Map([])
  let edges : Array[@mtsc_core.MtscModuleEdge] = []
  let loaded = mtsc_load_bundle_files(
    entry,
    files,
    Map([]),
    Map([]),
    Map([]),
    false,
    [],
    Map([]),
    edges,
    types_resolution,
  )
  assert_true(loaded is Ok(_))
  (files, edges)
}

///|
fn types_graph_target(
  edges : Array[@mtsc_core.MtscModuleEdge],
  spec : String,
) -> String? {
  for edge in edges {
    if edge.moduleSpecifier == spec {
      return Some(edge.targetPath)
    }
  }
  None
}

///|
fn types_graph_check_opts() -> MtscOptions {
  let opts = mtsc_options_new()
  opts.no_emit = true
  opts
}

///|
/// The check used to walk the BUNDLER's graph, so a package import reached
/// the JavaScript that runs (`"default": "./dist/i.js"`) rather than the
/// declarations that describe it, which the checker does not read — every
/// npm import was `any`, and `mtsc --noEmit` reported nothing about any
/// library call. The check's walk takes the `types` condition; the
/// bundler's still takes the code.
async test "mtsc check graph: a package import resolves to its declarations" {
  let root = "/tmp/ts_mbt_types_graph_exports"
  types_graph_fixture(root, [
    (
      "node_modules/p/package.json", "{\"name\":\"p\",\"exports\":{\".\":{\"types\":\"./dist/i.d.ts\",\"default\":\"./dist/i.js\"}}}",
    ),
    ("node_modules/p/dist/i.d.ts", "export declare const n: number;\n"),
    ("node_modules/p/dist/i.js", "export const n = 1;\n"),
    ("bad.ts", "import { n } from \"p\";\nexport const bad: string = n;\n"),
    ("ok.ts", "import { n } from \"p\";\nexport const ok: number = n;\n"),
  ])
  let (types_files, types_edges) = types_graph_load(root + "/bad.ts", true)
  assert_true(
    types_graph_target(types_edges, "p")
    .unwrap_or("")
    .has_suffix("/dist/i.d.ts"),
  )
  // The JavaScript is a leaf of the check graph: recorded nowhere.
  assert_false(types_files.keys().any(fn(k) { k.has_suffix("/dist/i.js") }))
  let (_, runtime_edges) = types_graph_load(root + "/bad.ts", false)
  assert_true(
    types_graph_target(runtime_edges, "p")
    .unwrap_or("")
    .has_suffix("/dist/i.js"),
  )
  let opts = types_graph_check_opts()
  assert_true(mtsc_compile_all(opts, [root + "/bad.ts"]) > 0)
  assert_eq(mtsc_compile_all(opts, [root + "/ok.ts"]), 0)
}

///|
/// Inside a package, a relative specifier names the DECLARATION: `./u.js`
/// beside both `u.js` and `u.d.ts` is `u.d.ts`, and `./Version.ts` with no
/// `Version.ts` is `Version.d.ts` — how effect and date-fns, built with
/// `rewriteRelativeImportExtensions`, spell every re-export.
async test "mtsc check graph: relative specifiers prefer declarations" {
  let root = "/tmp/ts_mbt_types_graph_relative"
  types_graph_fixture(root, [
    ("node_modules/q/package.json", "{\"name\":\"q\",\"types\":\"index.d.ts\"}"),
    (
      "node_modules/q/index.d.ts", "export * from \"./Version.ts\";\nexport * from \"./u.js\";\n",
    ),
    ("node_modules/q/Version.d.ts", "export declare const version: number;\n"),
    ("node_modules/q/u.d.ts", "export declare const u: number;\n"),
    ("node_modules/q/u.js", "export const u = 1;\n"),
    (
      "main.ts", "import { version, u } from \"q\";\nexport const a: string = version;\nexport const b: string = u;\n",
    ),
  ])
  let (files, _) = types_graph_load(root + "/main.ts", true)
  assert_true(files.keys().any(fn(k) { k.has_suffix("/q/Version.d.ts") }))
  assert_true(files.keys().any(fn(k) { k.has_suffix("/q/u.d.ts") }))
  assert_false(files.keys().any(fn(k) { k.has_suffix("/q/u.js") }))
  assert_true(
    mtsc_compile_all(types_graph_check_opts(), [root + "/main.ts"]) > 0,
  )
}

///|
/// The mapping is a fallback, not a preference: a `.ts` that exists is the
/// source and wins over a `.d.ts` beside it, as in `tsc`.
async test "mtsc check graph: a TypeScript source wins over its declaration" {
  let root = "/tmp/ts_mbt_types_graph_source_wins"
  types_graph_fixture(root, [
    ("a.ts", "export const n: number = 1;\n"),
    ("a.d.ts", "export declare const n: string;\n"),
    ("main.ts", "import { n } from \"./a.ts\";\nexport const ok: number = n;\n"),
  ])
  let (_, edges) = types_graph_load(root + "/main.ts", true)
  assert_true(
    types_graph_target(edges, "./a.ts").unwrap_or("").has_suffix("/a.ts"),
  )
  assert_eq(mtsc_compile_all(types_graph_check_opts(), [root + "/main.ts"]), 0)
}

///|
/// The bundler has no use for `import type` from a package and skips it;
/// the checker needs the declaration it names.
async test "mtsc check graph: a type-only package import is followed" {
  let root = "/tmp/ts_mbt_types_graph_type_only"
  types_graph_fixture(root, [
    ("node_modules/p/package.json", "{\"name\":\"p\",\"types\":\"i.d.ts\"}"),
    ("node_modules/p/i.d.ts", "export interface Box { a: number }\n"),
    (
      "main.ts", "import type { Box } from \"p\";\nexport const bad: Box = { a: \"s\" };\n",
    ),
  ])
  let (_, types_edges) = types_graph_load(root + "/main.ts", true)
  assert_true(types_graph_target(types_edges, "p") is Some(_))
  let (_, runtime_edges) = types_graph_load(root + "/main.ts", false)
  assert_true(types_graph_target(runtime_edges, "p") is None)
  assert_true(
    mtsc_compile_all(types_graph_check_opts(), [root + "/main.ts"]) > 0,
  )
}

///|
/// zod names `"types": "./index.d.cts"` first, and its declarations import
/// `./external.cjs`. A `.d.cts` holds declarations only, so the check reads
/// it; a `.cts` SOURCE stays out, as before.
async test "mtsc check graph: a package typed by .d.cts is read" {
  let root = "/tmp/ts_mbt_types_graph_dcts"
  types_graph_fixture(root, [
    (
      "node_modules/z/package.json", "{\"name\":\"z\",\"exports\":{\".\":{\"types\":\"./index.d.cts\",\"import\":\"./index.js\",\"require\":\"./index.cjs\"}}}",
    ),
    ("node_modules/z/index.d.cts", "export * from \"./lib.cjs\";\n"),
    ("node_modules/z/lib.d.cts", "export declare const n: number;\n"),
    ("main.ts", "import { n } from \"z\";\nexport const bad: string = n;\n"),
  ])
  assert_true(
    mtsc_compile_all(types_graph_check_opts(), [root + "/main.ts"]) > 0,
  )
}

///|
/// One dependency declaration this parser cannot read used to fail the
/// whole types-mode load, which sent `-p` back to checking every entry on
/// its own. It is left untyped instead and the program is still checked.
async test "mtsc check graph: an unparsable dependency declaration is untyped" {
  let root = "/tmp/ts_mbt_types_graph_unparsable"
  types_graph_fixture(root, [
    ("node_modules/bad/package.json", "{\"name\":\"bad\",\"types\":\"i.d.ts\"}"),
    ("node_modules/bad/i.d.ts", "export declare const = = ;\n"),
    (
      "main.ts", "import { x } from \"bad\";\nexport const y = x;\nexport const own: string = 1;\n",
    ),
    ("ok.ts", "import { x } from \"bad\";\nexport const y = x;\n"),
  ])
  let (files, _) = types_graph_load(root + "/main.ts", true)
  assert_false(files.keys().any(fn(k) { k.contains("/bad/i.d.ts") }))
  assert_true(
    mtsc_compile_all(types_graph_check_opts(), [root + "/main.ts"]) > 0,
  )
  assert_eq(mtsc_compile_all(types_graph_check_opts(), [root + "/ok.ts"]), 0)
}

///|
/// A dependency's declaration files are read for their types and not
/// reported on; a declaration file NAMED as an entry is checked, unless
/// `skipLibCheck` says otherwise, which also covers the program's own
/// `.d.ts`. A `.ts` source in `node_modules` is checked, as `tsc` checks it.
test "mtsc check graph: which declaration files are context only" {
  let files : Map[String, String] = {
    "/w/src/main.ts": "",
    "/w/src/env.d.ts": "",
    "/w/node_modules/p/i.d.ts": "",
    "/w/node_modules/p/i.d.cts": "",
    "/w/node_modules/ws/src/index.ts": "",
    "/w/node_modules/named/i.d.ts": "",
  }
  let off = mtsc_context_only_modules(
    files,
    ["/w/src/main.ts", "/w/node_modules/named/i.d.ts"],
    false,
  )
  assert_true(off.contains("/w/node_modules/p/i.d.ts"))
  assert_true(off.contains("/w/node_modules/p/i.d.cts"))
  assert_false(off.contains("/w/node_modules/named/i.d.ts"))
  assert_false(off.contains("/w/node_modules/ws/src/index.ts"))
  assert_false(off.contains("/w/src/env.d.ts"))
  assert_false(off.contains("/w/src/main.ts"))
  let skip = mtsc_context_only_modules(
    files,
    ["/w/node_modules/named/i.d.ts"],
    true,
  )
  assert_true(skip.contains("/w/src/env.d.ts"))
  assert_true(skip.contains("/w/node_modules/named/i.d.ts"))
  assert_false(skip.contains("/w/src/main.ts"))
}

///|
/// End to end: an error inside a dependency's `.d.ts` is not reported, the
/// same file named on the command line is, and `--skipLibCheck` silences
/// that again.
async test "mtsc check graph: a dependency declaration is not reported on" {
  let root = "/tmp/ts_mbt_types_graph_context"
  types_graph_fixture(root, [
    ("node_modules/p/package.json", "{\"name\":\"p\",\"types\":\"i.d.ts\"}"),
    (
      "node_modules/p/i.d.ts", "export declare const n: number;\nexport declare const w: Undeclared;\n",
    ),
    ("main.ts", "import { n } from \"p\";\nexport const ok: number = n;\n"),
  ])
  assert_eq(mtsc_compile_all(types_graph_check_opts(), [root + "/main.ts"]), 0)
  let named = root + "/node_modules/p/i.d.ts"
  assert_true(mtsc_compile_all(types_graph_check_opts(), [named]) > 0)
  let skip = types_graph_check_opts()
  skip.skip_lib_check = Some(true)
  assert_eq(mtsc_compile_all(skip, [named]), 0)
}

///|
/// `--skipLibCheck` is honoured rather than "accepted, no effect", and a
/// project's value does not override the command line.
test "mtsc flags: --skipLibCheck is read with its value" {
  let parsed = mtsc_parse_args(["mtsc", "--skipLibCheck", "a.ts"], 1)
  match parsed {
    Ok(opts) => {
      assert_eq(opts.skip_lib_check, Some(true))
      assert_false(opts.ignored.contains("--skipLibCheck"))
      assert_eq(opts.inputs, ["a.ts"])
    }
    Err(e) => fail(e)
  }
  match mtsc_parse_args(["mtsc", "--skipLibCheck", "false", "a.ts"], 1) {
    Ok(opts) => {
      assert_eq(opts.skip_lib_check, Some(false))
      assert_eq(opts.inputs, ["a.ts"])
    }
    Err(e) => fail(e)
  }
  match mtsc_parse_args(["mtsc", "a.ts"], 1) {
    Ok(opts) => assert_eq(opts.skip_lib_check, None)
    Err(e) => fail(e)
  }
}

///|
/// `--external` keeps a package out of the BUNDLE, and its types still
/// describe the program: the check's walk follows it. It used to skip the
/// specifier before resolving it, so `--bundle --noEmit --external p` read
/// every import from `p` as `any`.
async test "mtsc check graph: an external package is still type-checked" {
  let root = "/tmp/ts_mbt_types_graph_external"
  types_graph_fixture(root, [
    ("node_modules/p/package.json", "{\"name\":\"p\",\"types\":\"index.d.ts\"}"),
    (
      "node_modules/p/index.d.ts", "export declare function f(x: number): string;\n",
    ),
    ("node_modules/p/index.js", "exports.f = (x) => String(x);\n"),
    ("bad.ts", "import { f } from \"p\";\nexport const n: number = f(1);\n"),
    ("ok.ts", "import { f } from \"p\";\nexport const s: string = f(1);\n"),
  ])
  let opts = types_graph_check_opts()
  opts.bundle = true
  opts.externals["p"] = true
  assert_true(mtsc_compile_all(opts, [root + "/bad.ts"]) > 0)
  assert_eq(mtsc_compile_all(opts, [root + "/ok.ts"]), 0)
}

///|
/// A `.d.cts` is a declaration file: a bodiless `export function` and a
/// destructuring rename in a signature are legal there, as in a `.d.ts`.
async test "mtsc check graph: a .d.cts entry is a declaration file" {
  let root = "/tmp/ts_mbt_types_graph_dcts_entry"
  types_graph_fixture(root, [
    (
      "lib.d.cts", "export function g(): void;\nexport function h({ a: b }: { a: number }): void;\n",
    ),
  ])
  assert_eq(
    mtsc_compile_all(types_graph_check_opts(), [root + "/lib.d.cts"]),
    0,
  )
}

///|
/// The watch set follows the CHECK's graph when checking is on: a
/// non-bundle `--noEmit --watch` checks the whole import graph and used to
/// poll the entry alone, so editing an imported file changed nothing. A
/// dependency's declarations are not polled.
async test "mtsc watch: the check's import graph is watched" {
  let root = "/tmp/ts_mbt_types_graph_watch"
  types_graph_fixture(root, [
    ("node_modules/p/package.json", "{\"name\":\"p\",\"types\":\"index.d.ts\"}"),
    ("node_modules/p/index.d.ts", "export declare const n: number;\n"),
    (
      "a.ts", "import { b } from \"./b\";\nimport type { n } from \"p\";\nexport const x: number = b;\n",
    ),
    ("b.ts", "export const b: number = 1;\n"),
  ])
  let opts = types_graph_check_opts()
  let watched = mtsc_watch_program_files(opts, [root + "/a.ts"])
  assert_true(watched.iter().any(fn(p) { p.has_suffix("/b.ts") }))
  assert_false(watched.iter().any(fn(p) { p.contains("/node_modules/") }))
  // With checking off, nothing reads the graph and only the entry is polled.
  opts.no_check = true
  assert_eq(mtsc_watch_program_files(opts, [root + "/a.ts"]).length(), 1)
}

///|
/// A load that fails still watches what it read: a syntax error in an
/// imported file stops the walk there, and polling that file is what lets
/// the fix trigger the retry.
async test "mtsc watch: a file that breaks the load is still watched" {
  let root = "/tmp/ts_mbt_types_graph_watch_broken"
  types_graph_fixture(root, [
    ("a.ts", "import { b } from \"./b\";\nexport const x: number = b;\n"),
    ("b.ts", "export const b: number = = 1;\n"),
  ])
  let opts = types_graph_check_opts()
  let watched = mtsc_watch_program_files(opts, [root + "/a.ts"])
  assert_true(watched.iter().any(fn(p) { p.has_suffix("/b.ts") }))
  opts.no_check = true
  opts.bundle = true
  let watched = mtsc_watch_program_files(opts, [root + "/a.ts"])
  assert_true(watched.iter().any(fn(p) { p.has_suffix("/b.ts") }))
}

///|
/// A workspace package linked into `node_modules` is the program's own
/// source under a dependency's path: the resolver returns the link's
/// spelling, so the watch set decides by the REAL path. A real dependency
/// stays unpolled.
async test "mtsc watch: a linked workspace package is watched" {
  let root = "/tmp/ts_mbt_types_graph_watch_linked"
  types_graph_fixture(root, [
    ("packages/ws/package.json", "{\"name\":\"ws\",\"types\":\"index.d.ts\"}"),
    ("packages/ws/index.d.ts", "export interface N { n: number }\n"),
    (
      "node_modules/dep/package.json", "{\"name\":\"dep\",\"types\":\"index.d.ts\"}",
    ),
    ("node_modules/dep/index.d.ts", "export interface D { d: number }\n"),
    (
      "a.ts", "import type { N } from \"ws\";\nimport type { D } from \"dep\";\nexport const x: N | D = { n: 1 };\n",
    ),
  ])
  @fs.symlink(target="../packages/ws", root + "/node_modules/ws")
  let watched = mtsc_watch_program_files(types_graph_check_opts(), [
    root + "/a.ts",
  ])
  assert_true(watched.iter().any(fn(p) { p.has_suffix("/ws/index.d.ts") }))
  assert_false(watched.iter().any(fn(p) { p.has_suffix("/dep/index.d.ts") }))
}

///|
/// A project's program includes files nothing imports. With no `types`
/// option every package in `node_modules/@types` is included, and its
/// `/// <reference path>` and its `declare module "node:os"` come with it,
/// so `process` and `import { cpus } from "node:os"` both read
/// `@types/node`. Each legal line has an illegal twin that must report.
async test "mtsc check graph: a project includes its @types and their references" {
  let root = "/tmp/ts_mbt_types_graph_auto_types"
  types_graph_fixture(root, [
    (
      "tsconfig.json", "{\"compilerOptions\":{\"strict\":true},\"include\":[\"src\"]}",
    ),
    (
      "node_modules/@types/node/package.json", "{\"name\":\"@types/node\",\"types\":\"index.d.ts\"}",
    ),
    (
      "node_modules/@types/node/index.d.ts", "/// <reference path=\"globals.d.ts\" />\ndeclare module \"node:os\" { export function cpus(): number; }\n",
    ),
    (
      "node_modules/@types/node/globals.d.ts", "declare var process: { pid: number };\n",
    ),
    (
      "src/main.ts", "import { cpus } from \"node:os\";\nexport const a: number = process.pid;\nexport const b: number = cpus();\n",
    ),
  ])
  let opts = types_graph_check_opts()
  opts.project = Some(root)
  let (entries, _) = mtsc_resolve_entries(opts).unwrap()
  assert_eq(mtsc_compile_all(opts, entries), 0)
  @fs.write_file(
    root + "/src/main.ts",
    "import { cpus } from \"node:os\";\nexport const a: string = process.pid;\nexport const b: string = cpus();\n",
    create=0o644,
  )
  let opts = types_graph_check_opts()
  opts.project = Some(root)
  let (entries, _) = mtsc_resolve_entries(opts).unwrap()
  assert_true(mtsc_compile_all(opts, entries) > 0)
  // `types: []` turns automatic inclusion off, so `process` is undeclared.
  // Its own directory: the parser memoizes a config's text per path, so a
  // config rewritten in place would be read as before within this process.
  let none = "/tmp/ts_mbt_types_graph_no_types"
  types_graph_fixture(none, [
    (
      "tsconfig.json", "{\"compilerOptions\":{\"strict\":true,\"types\":[]},\"include\":[\"src\"]}",
    ),
    (
      "node_modules/@types/node/index.d.ts", "declare var process: { pid: number };\n",
    ),
    ("src/main.ts", "export const a: number = process.pid;\n"),
  ])
  let opts = types_graph_check_opts()
  opts.project = Some(none)
  let (entries, _) = mtsc_resolve_entries(opts).unwrap()
  assert_true(mtsc_compile_all(opts, entries) > 0)
}

///|
/// `typeRoots` replaces the default roots, and a source file's own
/// `/// <reference types>` and `/// <reference path>` load what they name.
async test "mtsc check graph: typeRoots and a file's own references" {
  let root = "/tmp/ts_mbt_types_graph_type_roots"
  types_graph_fixture(root, [
    (
      "tsconfig.json", "{\"compilerOptions\":{\"strict\":true,\"typeRoots\":[\"./typings\"],\"types\":[\"g\"]},\"files\":[\"src/main.ts\"]}",
    ),
    ("typings/g/index.d.ts", "declare var G: number;\n"),
    ("typings/h/index.d.ts", "declare var H: number;\n"),
    ("other/extra.d.ts", "declare var X: number;\n"),
    (
      "src/main.ts", "/// <reference types=\"h\" />\n/// <reference path=\"../other/extra.d.ts\" />\nexport const ok: number = G + H + X;\n",
    ),
  ])
  let opts = types_graph_check_opts()
  opts.project = Some(root)
  let (entries, _) = mtsc_resolve_entries(opts).unwrap()
  assert_eq(mtsc_compile_all(opts, entries), 0)
  @fs.write_file(
    root + "/src/main.ts",
    "/// <reference types=\"h\" />\n/// <reference path=\"../other/extra.d.ts\" />\nexport const bad: string = G + H + X;\n",
    create=0o644,
  )
  let opts = types_graph_check_opts()
  opts.project = Some(root)
  let (entries, _) = mtsc_resolve_entries(opts).unwrap()
  assert_true(mtsc_compile_all(opts, entries) > 0)
}
