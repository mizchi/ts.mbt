///|
let resolver_base_path : String = "fixtures/resolver/project/src/app.ts"

///|
let resolver_nested_base_path : String = "fixtures/resolver/project/src/nested/deep/app.ts"

///|
let resolver_tsconfig_base_path : String = "fixtures/resolver/tsconfig_project/src/app.ts"

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

///|
async test "parser: resolver uses tsconfig paths aliases" {
  let resolved = resolve_type_module_specifier(
    resolver_tsconfig_base_path, "@lib/util",
  )
  assert_eq(
    resolved,
    Some("fixtures/resolver/tsconfig_project/src/lib/util.ts"),
  )
}

///|
async test "parser: resolver uses tsconfig baseUrl fallback" {
  let resolved = resolve_type_module_specifier(
    resolver_tsconfig_base_path, "shared/tool",
  )
  assert_eq(
    resolved,
    Some("fixtures/resolver/tsconfig_project/src/shared/tool.ts"),
  )
}

///|
async test "parser: resolver uses package imports in types mode" {
  let resolved = resolve_type_module_specifier(
    resolver_tsconfig_base_path, "#config",
  )
  assert_eq(
    resolved,
    Some("fixtures/resolver/tsconfig_project/types/config.d.ts"),
  )
}

///|
async test "parser: resolver uses package imports for external package targets" {
  let resolved = resolve_type_module_specifier(
    resolver_tsconfig_base_path, "#pkg-exact",
  )
  assert_eq(
    resolved,
    Some(
      "fixtures/resolver/tsconfig_project/node_modules/pkg-import-target/dist/index.d.ts",
    ),
  )
}

///|
async test "parser: resolver uses package imports for external package targets in runtime mode" {
  let resolved = resolve_runtime_module_specifier(
    resolver_tsconfig_base_path, "#pkg-exact",
  )
  assert_eq(
    resolved,
    Some(
      "fixtures/resolver/tsconfig_project/node_modules/pkg-import-target/dist/index.js",
    ),
  )
}

///|
async test "parser: resolver follows package imports alias chains" {
  let resolved = resolve_type_module_specifier(
    resolver_tsconfig_base_path, "#pkg-chain",
  )
  assert_eq(
    resolved,
    Some(
      "fixtures/resolver/tsconfig_project/node_modules/pkg-import-target/dist/index.d.ts",
    ),
  )
}

///|
async test "parser: resolver uses package imports array fallback" {
  let resolved = resolve_type_module_specifier(
    resolver_tsconfig_base_path, "#pkg-array",
  )
  assert_eq(
    resolved,
    Some(
      "fixtures/resolver/tsconfig_project/node_modules/pkg-import-target/dist/index.d.ts",
    ),
  )
}

///|
async test "parser: resolver uses package imports pattern in runtime mode" {
  let resolved = resolve_runtime_module_specifier(
    resolver_tsconfig_base_path, "#internal/helper",
  )
  assert_eq(
    resolved,
    Some("fixtures/resolver/tsconfig_project/src/internal/helper.ts"),
  )
}

///|
async test "parser: resolver follows package imports wildcard alias chains" {
  let resolved = resolve_type_module_specifier(
    resolver_tsconfig_base_path, "#pkg-pattern-chain/util",
  )
  assert_eq(
    resolved,
    Some(
      "fixtures/resolver/tsconfig_project/node_modules/pkg-exports-pattern/dist/util.d.ts",
    ),
  )
}

///|
async test "parser: resolver uses package imports patterns for external package targets" {
  let resolved = resolve_type_module_specifier(
    resolver_tsconfig_base_path, "#pkg-pattern/util",
  )
  assert_eq(
    resolved,
    Some(
      "fixtures/resolver/tsconfig_project/node_modules/pkg-exports-pattern/dist/util.d.ts",
    ),
  )
}

///|
async test "parser: resolver uses typesVersions for typed subpaths" {
  let resolved = resolve_type_module_specifier(
    resolver_tsconfig_base_path, "pkg-types-versions/feature",
  )
  assert_eq(
    resolved,
    Some(
      "fixtures/resolver/tsconfig_project/node_modules/pkg-types-versions/ts5/feature/index.d.ts",
    ),
  )
}

///|
async test "parser: resolver uses exports wildcard patterns in types mode" {
  let resolved = resolve_type_module_specifier(
    resolver_tsconfig_base_path, "pkg-exports-pattern/util",
  )
  assert_eq(
    resolved,
    Some(
      "fixtures/resolver/tsconfig_project/node_modules/pkg-exports-pattern/dist/util.d.ts",
    ),
  )
}

///|
async test "parser: resolver uses exports wildcard patterns in runtime mode" {
  let resolved = resolve_runtime_module_specifier(
    resolver_tsconfig_base_path, "pkg-exports-pattern/util",
  )
  assert_eq(
    resolved,
    Some(
      "fixtures/resolver/tsconfig_project/node_modules/pkg-exports-pattern/dist/util.js",
    ),
  )
}

///|
async test "parser: resolver uses exports array fallback wildcard patterns in types mode" {
  let resolved = resolve_type_module_specifier(
    resolver_nested_base_path, "pkg-exports-array/feature/util",
  )
  assert_eq(
    resolved,
    Some(
      "fixtures/resolver/project/node_modules/pkg-exports-array/dist/feature/util.d.ts",
    ),
  )
}

///|
async test "parser: resolver uses exports array fallback wildcard patterns in runtime mode" {
  let resolved = resolve_runtime_module_specifier(
    resolver_nested_base_path, "pkg-exports-array/feature/util",
  )
  assert_eq(
    resolved,
    Some(
      "fixtures/resolver/project/node_modules/pkg-exports-array/dist/feature/util.js",
    ),
  )
}

///|
async test "parser: resolver uses typesVersions wildcard mappings" {
  let resolved = resolve_type_module_specifier(
    resolver_tsconfig_base_path, "pkg-types-versions/legacy/util",
  )
  assert_eq(
    resolved,
    Some(
      "fixtures/resolver/tsconfig_project/node_modules/pkg-types-versions/ts5/legacy/util.d.ts",
    ),
  )
}
