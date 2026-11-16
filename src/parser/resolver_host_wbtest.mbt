// `resolve_type_module_specifier_with` against `resolve_type_module_specifier`.
//
// Two walks over one algorithm can drift, and the drift would be silent:
// the CLI uses the async walk and a browser or wasm embedding uses the
// injected one, so a disagreement means the same program type-checks
// differently depending on where it runs. This pins them to each other
// over the resolver fixtures, which include the cases that are easiest
// to get subtly wrong — pnpm symlinks (`realpath`), `exports` conditions,
// `typesVersions`, `@types` fallbacks, `node:` builtins, tsconfig `paths`
// and package `imports`.

///|
/// The fixture tree, read once, served synchronously.
///
/// `real` holds the async resolver's own `canonical_file_path` answer for
/// every path the walk visited, so a symlinked package resolves to the
/// same spelling through both walks. That answer is absolute, so lookups
/// map an absolute path back under `cwd` before consulting the maps.
priv struct SnapshotHost {
  files : Map[String, String]
  dirs : Map[String, Unit]
  real : Map[String, String]
  cwd : String
}

///|
fn SnapshotHost::key(self : SnapshotHost, path : String) -> String {
  let prefix = self.cwd + "/"
  if path.has_prefix(prefix) {
    path[prefix.length():].to_owned()
  } else {
    path
  }
}

///|
impl ModuleResolutionHost for SnapshotHost with fn file_exists(self, path) {
  self.files.contains(self.key(path))
}

///|
impl ModuleResolutionHost for SnapshotHost with fn directory_exists(self, path) {
  self.dirs.contains(self.key(path))
}

///|
impl ModuleResolutionHost for SnapshotHost with fn read_file(self, path) {
  self.files.get(self.key(path))
}

///|
impl ModuleResolutionHost for SnapshotHost with fn realpath(self, path) {
  self.real.get(self.key(path)).unwrap_or(path)
}

///|
async fn snapshot_walk(host : SnapshotHost, dir : String) -> Unit {
  host.dirs[dir] = ()
  host.real[dir] = canonical_file_path(dir)
  for name in @fs.readdir(dir, sort=true) {
    let path = dir + "/" + name
    match @fs.kind(path) {
      @fs.FileKind::Directory => snapshot_walk(host, path)
      @fs.FileKind::Regular => {
        host.files[path] = @fs.read_file(path).text()
        host.real[path] = canonical_file_path(path)
      }
      _ => ()
    }
  }
}

///|
async fn snapshot_fixture_host() -> SnapshotHost {
  let host : SnapshotHost = {
    files: Map([]),
    dirs: Map([]),
    real: Map([]),
    cwd: canonical_file_path("."),
  }
  // Every ancestor of the fixture roots is a directory the walks pass
  // through on their way up to `.`.
  for d in [".", "fixtures"] {
    host.dirs[d] = ()
  }
  snapshot_walk(host, "fixtures/resolver")
  host
}

///|
async test "parser: the injected-host resolver agrees with the filesystem resolver" {
  let host = snapshot_fixture_host()
  let cases : Array[(String, String)] = [
    (resolver_base_path, "./local"),
    (resolver_base_path, "./dir"),
    (resolver_base_path, "./ts-specifier.ts"),
    (resolver_base_path, "./missing"),
    (resolver_nested_base_path, "pkg-types"),
    (resolver_nested_base_path, "pkg-main"),
    (resolver_nested_base_path, "pkg-exports/feature"),
    (resolver_nested_base_path, "@scope/pkg"),
    (resolver_nested_base_path, "pkg-untyped"),
    (resolver_nested_base_path, "@scope/untyped"),
    (resolver_nested_base_path, "node:fs"),
    (resolver_nested_base_path, "node:fs/promises"),
    (resolver_nested_base_path, "pkg-symlink"),
    (resolver_nested_base_path, "neverthrow-like"),
    (resolver_nested_base_path, "react"),
    (resolver_nested_base_path, "react/jsx-runtime"),
    (resolver_nested_base_path, "react/jsx-dev-runtime"),
    (resolver_nested_base_path, "hono/jsx"),
    (resolver_nested_base_path, "no-such-package"),
    (resolver_tsconfig_base_path, "@lib/util"),
    (resolver_tsconfig_base_path, "shared/tool"),
    (resolver_tsconfig_base_path, "#config"),
  ]
  let mut resolved_count = 0
  for case in cases {
    let (base, specifier) = case
    let expected = resolve_type_module_specifier(base, specifier)
    let actual = resolve_type_module_specifier_with(host, base, specifier)
    if expected is Some(_) {
      resolved_count = resolved_count + 1
    }
    assert_eq((specifier, actual), (specifier, expected))
  }
  // The comparison is only worth something if most cases resolve: two
  // resolvers that both answer `None` everywhere agree perfectly.
  assert_true(resolved_count >= 18)
}

///|
/// Write `files` under a fresh `root`.
async fn resolver_host_fixture(
  root : String,
  files : Array[(String, String)],
) -> Unit {
  @fs.rmdir(root, recursive=true) catch {
    _ => ()
  }
  for entry in files {
    let path = root + "/" + entry.0
    @fs.mkdir(dirname(path), permission=0o755, recursive=true) catch {
      _ => ()
    }
    @fs.write_file(path, entry.1, create=0o644)
  }
}

///|
/// The fixture tree above only partly separates the two walks: neither a
/// reordering of the `types` / `main` fields nor a `realpath` that does
/// nothing changes one of its answers. So this tree is built to: every
/// package below is resolvable by exactly one rule, and the last case is
/// reachable only through the linked package's REAL path.
async test "parser: the injected-host resolver agrees on a tree built to separate the rules" {
  let root = "/tmp/ts_mbt_resolver_host_diff"
  resolver_host_fixture(root, [
    (
      "package.json", "{\"name\":\"app\",\"imports\":{\"#int/*\":\"./src/int/*.ts\"}}",
    ),
    (
      "tsconfig.json", "{\"compilerOptions\":{\"baseUrl\":\".\",\"paths\":{\"@/*\":[\"src/*\"]}}}",
    ),
    ("src/main.ts", ""),
    ("src/int/a.ts", ""),
    ("src/lib/a.ts", ""),
    (
      "node_modules/order/package.json", "{\"main\":\"main.d.ts\",\"types\":\"types.d.ts\"}",
    ),
    ("node_modules/order/main.d.ts", ""),
    ("node_modules/order/types.d.ts", ""),
    ("node_modules/jsmain/package.json", "{\"main\":\"index.js\"}"),
    ("node_modules/jsmain/index.js", ""),
    ("node_modules/jsmain/index.d.ts", ""),
    ("node_modules/onlyjs/package.json", "{\"main\":\"lib.js\"}"),
    ("node_modules/onlyjs/lib.js", ""),
    (
      "node_modules/tv/package.json", "{\"types\":\"old.d.ts\",\"typesVersions\":{\"*\":{\"*\":[\"ts4/*\"]}}}",
    ),
    ("node_modules/tv/old.d.ts", ""),
    ("node_modules/tv/ts4/sub.d.ts", ""),
    (
      "node_modules/cond/package.json", "{\"exports\":{\".\":{\"import\":{\"types\":\"./esm.d.mts\"},\"require\":{\"types\":\"./cjs.d.cts\"}}}}",
    ),
    ("node_modules/cond/esm.d.mts", ""),
    ("node_modules/cond/cjs.d.cts", ""),
    (
      "node_modules/wild/package.json", "{\"exports\":{\"./*\":{\"types\":\"./dist/*.d.ts\"}}}",
    ),
    ("node_modules/wild/dist/x.d.ts", ""),
    ("node_modules/@scoped/p/package.json", "{\"main\":\"i.js\"}"),
    ("node_modules/@scoped/p/i.js", ""),
    ("node_modules/@types/scoped__p/index.d.ts", ""),
    ("src/index.ts", ""),
    ("src.ts", ""),
    ("src/dirpkg/index.ts", ""),
    ("src/dirpkg/main.ts", ""),
    ("src/dirpkg.ts", ""),
    ("node_modules/selfref/package.json", "{\"types\":\"./\"}"),
    ("node_modules/selfref/index.d.ts", ""),
    ("node_modules/nested/package.json", "{\"types\":\"./lib\"}"),
    ("node_modules/nested/lib/package.json", "{\"types\":\"other.d.ts\"}"),
    ("node_modules/nested/lib/other.d.ts", ""),
    ("node_modules/nested/lib/index.d.ts", ""),
    ("packages/ws/package.json", "{\"types\":\"index.d.ts\"}"),
    ("packages/ws/index.d.ts", ""),
    ("packages/node_modules/shared/index.d.ts", ""),
  ])
  @fs.symlink(target="../packages/ws", root + "/node_modules/ws")
  let host : SnapshotHost = {
    files: Map([]),
    dirs: Map([]),
    real: Map([]),
    cwd: canonical_file_path("."),
  }
  // The walk up from an importer passes through every ancestor of `root`.
  let mut up = root
  while up != "/" && up != "." {
    host.dirs[up] = ()
    up = dirname(up)
  }
  snapshot_walk(host, root)
  let main = root + "/src/main.ts"
  let linked = root + "/node_modules/ws/index.d.ts"
  let dir_main = root + "/src/dirpkg/main.ts"
  let cases : Array[(String, String)] = [
    (dir_main, "."),
    (dir_main, "./"),
    (dir_main, ".."),
    (main, "selfref"),
    (main, "nested"),
    (main, "order"),
    (main, "jsmain"),
    (main, "onlyjs"),
    (main, "tv/sub"),
    (main, "cond"),
    (main, "wild/x"),
    (main, "@scoped/p"),
    (main, "ws"),
    (main, "#int/a"),
    (main, "@/lib/a"),
    (linked, "shared"),
  ]
  // A package with no manifest resolves to its `index.d.ts`: a scoped
  // `@types` package published that way beats the untyped `.js` beside
  // it, and a hoisted helper reached only through the linked package's
  // real path is found.
  assert_eq(
    resolve_type_module_specifier(main, "@scoped/p"),
    Some(root + "/node_modules/@types/scoped__p/index.d.ts"),
  )
  assert_true(
    resolve_type_module_specifier(linked, "shared")
    .unwrap_or("")
    .has_suffix("/packages/node_modules/shared/index.d.ts"),
  )
  // `.`, `./` and `..` name a DIRECTORY, so the sibling `dirpkg.ts` and
  // `src.ts` are never read for them.
  assert_eq(
    resolve_type_module_specifier(dir_main, "."),
    Some(root + "/src/dirpkg/index.ts"),
  )
  assert_eq(
    resolve_type_module_specifier(dir_main, ".."),
    Some(root + "/src/index.ts"),
  )
  // A package target that names a directory reads that directory's index,
  // never its manifest: `{ "types": "./" }` would otherwise re-enter the
  // manifest that named it forever, and a nested `package.json` under a
  // `types` directory is ignored, as TypeScript ignores it.
  assert_eq(
    resolve_type_module_specifier(main, "selfref"),
    Some(root + "/node_modules/selfref/index.d.ts"),
  )
  assert_eq(
    resolve_type_module_specifier(main, "nested"),
    Some(root + "/node_modules/nested/lib/index.d.ts"),
  )
  for case in cases {
    let (base, specifier) = case
    let expected = resolve_type_module_specifier(base, specifier)
    assert_true(expected is Some(_))
    assert_eq(
      (specifier, resolve_type_module_specifier_with(host, base, specifier)),
      (specifier, expected),
    )
  }
}

///|
/// A triple-slash directive counts only in the leading trivia: after
/// comments and other directives, before the first token of code. Both
/// quote styles name a value, `lib` is not a reference, and a `///` line
/// below the code is an ordinary comment.
test "parser: triple-slash references are read from the leading trivia only" {
  let source = "// header\n/* block\n   comment */\n/// <reference path=\"../g/globals.d.ts\" />\n///<reference types='node'/>\n/// <reference lib=\"es2020\" />\nexport const x = 1;\n/// <reference path=\"late.d.ts\" />\n"
  assert_eq(triple_slash_references(source), [
    ("path", "../g/globals.d.ts"),
    ("types", "node"),
  ])
  assert_eq(
    triple_slash_references("const a = 1;\n/// <reference path=\"x.d.ts\" />"),
    [],
  )
  assert_eq(triple_slash_references(""), [])
}
