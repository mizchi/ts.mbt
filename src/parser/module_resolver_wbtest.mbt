///|
let resolver_base_path : String = "fixtures/resolver/project/src/app.ts"

///|
let resolver_nested_base_path : String = "fixtures/resolver/project/src/nested/deep/app.ts"

///|
async test "parser: resolver prefers relative file before directory index" {
  let resolved = resolve_type_module_specifier(resolver_base_path, "./local")
  assert_eq(resolved, Some("fixtures/resolver/project/src/local.ts"))
}

///|
async test "parser: resolver falls back to directory index for relative imports" {
  let resolved = resolve_type_module_specifier(resolver_base_path, "./dir")
  assert_eq(resolved, Some("fixtures/resolver/project/src/dir/index.ts"))
}

///|
async test "parser: resolver uses package types field for bare specifiers" {
  let resolved = resolve_type_module_specifier(
    resolver_nested_base_path, "pkg-types",
  )
  assert_eq(
    resolved,
    Some("fixtures/resolver/project/node_modules/pkg-types/dist/index.d.ts"),
  )
}

///|
async test "parser: resolver uses main with declaration substitution in types mode" {
  let resolved = resolve_type_module_specifier(
    resolver_nested_base_path, "pkg-main",
  )
  assert_eq(
    resolved,
    Some("fixtures/resolver/project/node_modules/pkg-main/dist/main.d.ts"),
  )
}

///|
async test "parser: resolver uses exports conditions in runtime mode" {
  let resolved = resolve_runtime_module_specifier(
    resolver_nested_base_path, "pkg-exports",
  )
  assert_eq(
    resolved,
    Some("fixtures/resolver/project/node_modules/pkg-exports/dist/index.js"),
  )
}

///|
async test "parser: resolver uses exports conditions for typed subpaths" {
  let resolved = resolve_type_module_specifier(
    resolver_nested_base_path, "pkg-exports/feature",
  )
  assert_eq(
    resolved,
    Some("fixtures/resolver/project/node_modules/pkg-exports/dist/feature.d.ts"),
  )
}

///|
async test "parser: resolver supports scoped packages" {
  let resolved = resolve_type_module_specifier(
    resolver_nested_base_path, "@scope/pkg",
  )
  assert_eq(
    resolved,
    Some("fixtures/resolver/project/node_modules/@scope/pkg/types/index.d.ts"),
  )
}

///|
async test "parser: resolver supports pnpm-style symlinked packages" {
  let resolved = resolve_type_module_specifier(
    resolver_nested_base_path, "pkg-symlink",
  )
  assert_eq(
    resolved,
    Some("fixtures/resolver/project/node_modules/pkg-symlink/dist/index.d.ts"),
  )
}

///|
async test "parser: resolver supports neverthrow-like pnpm packages" {
  let resolved = resolve_type_module_specifier(
    resolver_nested_base_path, "neverthrow-like",
  )
  assert_eq(
    resolved,
    Some(
      "fixtures/resolver/project/node_modules/neverthrow-like/dist/index.d.ts",
    ),
  )
}
