///|
let semantics_entry_path : String = "fixtures/resolver/project/src/graph/entry.ts"

///|
let semantics_conflict_entry_path : String = "fixtures/resolver/project/src/graph/conflict-entry.ts"

///|
let semantics_subpath_type_entry_path : String = "fixtures/resolver/project/types/subpath-package-entry.d.ts"

///|
let semantics_pattern_type_entry_path : String = "fixtures/resolver/project/types/pattern-package-entry.d.ts"

///|
let semantics_pattern_array_type_entry_path : String = "fixtures/resolver/project/types/pattern-array-package-entry.d.ts"

///|
let semantics_barrel_type_entry_path : String = "fixtures/resolver/project/types/barrel-package-entry.d.ts"

///|
let semantics_neverthrow_like_type_entry_path : String = "fixtures/resolver/project/types/neverthrow-like-entry.d.ts"

///|
let semantics_opaque_package_type_entry_path : String = "fixtures/resolver/project/types/opaque-package-entry.d.ts"

///|
let semantics_unresolved_bare_reexport_entry_path : String = "fixtures/resolver/project/types/unresolved-bare-reexport-entry.d.ts"

///|
let semantics_export_equals_entry_path : String = "fixtures/resolver/project/types/export-equals-entry.d.ts"

///|
let semantics_import_equals_entry_path : String = "fixtures/resolver/project/types/import-equals-entry.d.ts"

///|
fn find_resolved_export(
  exports : Array[ResolvedExport],
  name : String,
) -> ResolvedExport? {
  for export_ in exports {
    if export_.export_name == name {
      return Some(export_)
    }
  }
  None
}

///|
async test "analysis: load runtime module graph follows resolved imports and reexports" {
  let graph = load_runtime_module_graph(semantics_entry_path)
  assert_eq(graph.entry_path, semantics_entry_path)
  assert_eq(graph.modules.length(), 6)

  let paths : Array[String] = []
  for module_ in graph.modules {
    paths.push(module_.path)
  }
  assert_true(paths.contains("fixtures/resolver/project/src/graph/entry.ts"))
  assert_true(paths.contains("fixtures/resolver/project/src/graph/dep.ts"))
  assert_true(paths.contains("fixtures/resolver/project/src/graph/barrel.ts"))
  assert_true(paths.contains("fixtures/resolver/project/src/graph/bar.ts"))
  assert_true(paths.contains("fixtures/resolver/project/src/graph/leaf.ts"))
  assert_true(
    paths.contains(
      "fixtures/resolver/project/node_modules/pkg-exports/dist/index.js",
    ),
  )
}

///|
async test "analysis: resolve runtime export surface follows reexports and namespaces" {
  let exports = resolve_runtime_export_surface(semantics_entry_path)
  let names : Array[String] = []
  for export_ in exports {
    names.push(export_.export_name)
  }
  assert_true(names.contains("foo"))
  assert_true(names.contains("bar"))
  assert_true(names.contains("baz"))
  assert_true(names.contains("ns"))
  assert_true(names.contains("pkgValue"))

  match find_resolved_export(exports, "foo") {
    Some(export_) => {
      assert_eq(export_.kind, ResolvedExportKind::NamedReExport)
      assert_eq(
        export_.source_path,
        "fixtures/resolver/project/src/graph/dep.ts",
      )
      assert_eq(export_.local_name, Some("foo"))
    }
    None => fail("expected foo export")
  }

  match find_resolved_export(exports, "ns") {
    Some(export_) => {
      assert_eq(export_.kind, ResolvedExportKind::Namespace)
      assert_eq(
        export_.source_path,
        "fixtures/resolver/project/src/graph/barrel.ts",
      )
    }
    None => fail("expected ns export")
  }

  match find_resolved_export(exports, "pkgValue") {
    Some(export_) => {
      assert_eq(export_.kind, ResolvedExportKind::NamedReExport)
      assert_eq(
        export_.source_path,
        "fixtures/resolver/project/node_modules/pkg-exports/dist/index.js",
      )
      assert_eq(export_.local_name, Some("exportedRuntime"))
    }
    None => fail("expected pkgValue export")
  }
}

///|
async test "analysis: conflicting star exports are marked ambiguous" {
  let exports = resolve_runtime_export_surface(semantics_conflict_entry_path)
  match find_resolved_export(exports, "shared") {
    Some(export_) => {
      assert_eq(export_.kind, ResolvedExportKind::Ambiguous)
      assert_true(
        export_.ambiguous_source_paths.contains(
          "fixtures/resolver/project/src/graph/conflict-a.ts",
        ),
      )
      assert_true(
        export_.ambiguous_source_paths.contains(
          "fixtures/resolver/project/src/graph/conflict-b.ts",
        ),
      )
    }
    None => fail("expected shared export")
  }
}

///|
async test "analysis: resolve type export surface through package exports subpath" {
  let exports = resolve_type_export_surface(semantics_subpath_type_entry_path)
  match find_resolved_export(exports, "FeatureOptions") {
    Some(export_) => {
      assert_eq(export_.kind, ResolvedExportKind::NamedReExport)
      assert_eq(
        export_.source_path,
        "fixtures/resolver/project/node_modules/pkg-subpath/dist/feature.d.ts",
      )
      assert_eq(export_.local_name, Some("FeatureOptions"))
    }
    None => fail("expected FeatureOptions export")
  }
  match find_resolved_export(exports, "executeFeature") {
    Some(export_) => {
      assert_eq(export_.kind, ResolvedExportKind::NamedReExport)
      assert_eq(
        export_.source_path,
        "fixtures/resolver/project/node_modules/pkg-subpath/dist/feature.d.ts",
      )
      assert_eq(export_.local_name, Some("runFeature"))
    }
    None => fail("expected executeFeature export")
  }
}

///|
async test "analysis: resolve type export surface through package exports wildcard subpath" {
  let exports = resolve_type_export_surface(semantics_pattern_type_entry_path)
  match find_resolved_export(exports, "PatternOptions") {
    Some(export_) => {
      assert_eq(export_.kind, ResolvedExportKind::NamedReExport)
      assert_eq(
        export_.source_path,
        "fixtures/resolver/project/node_modules/pkg-exports-pattern/dist/feature/util.d.ts",
      )
      assert_eq(export_.local_name, Some("PatternOptions"))
    }
    None => fail("expected PatternOptions export")
  }
  match find_resolved_export(exports, "createPattern") {
    Some(export_) => {
      assert_eq(export_.kind, ResolvedExportKind::NamedReExport)
      assert_eq(
        export_.source_path,
        "fixtures/resolver/project/node_modules/pkg-exports-pattern/dist/feature/util.d.ts",
      )
      assert_eq(export_.local_name, Some("buildPattern"))
    }
    None => fail("expected createPattern export")
  }
}

///|
async test "analysis: resolve type export surface through package exports array fallback wildcard subpath" {
  let exports = resolve_type_export_surface(
    semantics_pattern_array_type_entry_path,
  )
  match find_resolved_export(exports, "ArrayPatternOptions") {
    Some(export_) => {
      assert_eq(export_.kind, ResolvedExportKind::NamedReExport)
      assert_eq(
        export_.source_path,
        "fixtures/resolver/project/node_modules/pkg-exports-array/dist/feature/util.d.ts",
      )
      assert_eq(export_.local_name, Some("ArrayPatternOptions"))
    }
    None => fail("expected ArrayPatternOptions export")
  }
  match find_resolved_export(exports, "createArrayPattern") {
    Some(export_) => {
      assert_eq(export_.kind, ResolvedExportKind::NamedReExport)
      assert_eq(
        export_.source_path,
        "fixtures/resolver/project/node_modules/pkg-exports-array/dist/feature/util.d.ts",
      )
      assert_eq(export_.local_name, Some("buildArrayPattern"))
    }
    None => fail("expected createArrayPattern export")
  }
}

///|
async test "analysis: resolve type export surface through package barrel reexports" {
  let exports = resolve_type_export_surface(semantics_barrel_type_entry_path)
  match find_resolved_export(exports, "BarrelOptions") {
    Some(export_) => {
      assert_eq(export_.kind, ResolvedExportKind::NamedReExport)
      assert_eq(
        export_.source_path,
        "fixtures/resolver/project/node_modules/pkg-barrel/dist/internal.d.ts",
      )
      assert_eq(export_.local_name, Some("BarrelOptions"))
    }
    None => fail("expected BarrelOptions export")
  }
  match find_resolved_export(exports, "createBarrel") {
    Some(export_) => {
      assert_eq(export_.kind, ResolvedExportKind::NamedReExport)
      assert_eq(
        export_.source_path,
        "fixtures/resolver/project/node_modules/pkg-barrel/dist/internal.d.ts",
      )
      assert_eq(export_.local_name, Some("buildBarrel"))
    }
    None => fail("expected createBarrel export")
  }
}

///|
async test "analysis: type module graph skips non-exported opaque package imports" {
  let graph = load_type_module_graph(semantics_neverthrow_like_type_entry_path)
  assert_eq(graph.entry_path, semantics_neverthrow_like_type_entry_path)
  assert_eq(graph.modules.length(), 1)
  let module_ = graph.modules[0]
  assert_eq(module_.path, semantics_neverthrow_like_type_entry_path)
  assert_eq(module_.imports.length(), 1)
  let import_ = module_.imports[0]
  assert_eq(import_.specifier, "neverthrow-like")
  assert_eq(import_.resolved_path, "")
}

///|
async test "analysis: type module graph keeps minimal opaque package imports unresolved" {
  let graph = load_type_module_graph(semantics_opaque_package_type_entry_path)
  assert_eq(graph.entry_path, semantics_opaque_package_type_entry_path)
  assert_eq(graph.modules.length(), 1)
  let module_ = graph.modules[0]
  assert_eq(module_.path, semantics_opaque_package_type_entry_path)
  assert_eq(module_.imports.length(), 1)
  let import_ = module_.imports[0]
  assert_eq(import_.specifier, "pkg-types")
  assert_eq(import_.resolved_path, "")
}

///|
async test "analysis: unresolved bare reexports do not fail type export surface resolution" {
  let exports = resolve_type_export_surface(
    semantics_unresolved_bare_reexport_entry_path,
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Resolve error: \{msg}")
      }
      return
    }
  }
  match find_resolved_export(exports, "LocalOptions") {
    Some(export_) => {
      assert_eq(
        export_.source_path,
        semantics_unresolved_bare_reexport_entry_path,
      )
      assert_eq(export_.local_name, Some("LocalOptions"))
    }
    None => fail("expected LocalOptions export")
  }
  match find_resolved_export(exports, "createOptions") {
    Some(export_) => {
      assert_eq(
        export_.source_path,
        semantics_unresolved_bare_reexport_entry_path,
      )
      assert_eq(export_.local_name, Some("createOptions"))
    }
    None => fail("expected createOptions export")
  }
}

///|
async test "analysis: resolve type export surface from namespace export assignment" {
  let exports = resolve_type_export_surface(semantics_export_equals_entry_path)
  match find_resolved_export(exports, "default") {
    Some(export_) => {
      assert_eq(export_.source_path, semantics_export_equals_entry_path)
      assert_eq(export_.local_name, Some("semver"))
      assert_eq(export_.kind, ResolvedExportKind::Local)
    }
    None => fail("expected default export")
  }
}

///|
async test "analysis: resolve type export surface from import-equals export assignment" {
  let exports = resolve_type_export_surface(semantics_import_equals_entry_path)
  match find_resolved_export(exports, "default") {
    Some(export_) => {
      assert_eq(export_.source_path, semantics_import_equals_entry_path)
      assert_eq(export_.local_name, Some("pkg"))
      assert_eq(export_.kind, ResolvedExportKind::Local)
    }
    None => fail("expected default export")
  }
}
