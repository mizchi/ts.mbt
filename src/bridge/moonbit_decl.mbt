///|
priv struct DeclModuleInfo {
  record : ResolvedModuleRecord
  module_ : @ast.TsModule
}

///|
fn is_declaration_path(path : String) -> Bool {
  path.has_suffix(".d.ts") ||
  path.has_suffix(".d.mts") ||
  path.has_suffix(".d.cts")
}

///|
priv struct ExportedInterfaceDecl {
  source_path : String
  local_name : String
  export_name : String
  iface : @ast.TsInterface
}

///|
priv struct ExportedEnumDecl {
  source_path : String
  local_name : String
  export_name : String
  enum_ : @ast.TsEnumDecl
}

///|
priv struct ExportedTaggedUnionDecl {
  source_path : String
  local_name : String
  export_name : String
  decl : BridgeTaggedUnionDecl
}

///|
priv struct ExportedTypeAliasDecl {
  source_path : String
  export_name : String
  type_alias : @ast.TsTypeAlias
}

///|
priv struct ExportedImportDecl {
  source_path : String
  local_name_prefix : String
  export_name : String
  source_export_name : String
  import_ : @ast.TsImport
}

///|
priv struct ExportedFuncDecl {
  source_path : String
  local_name_prefix : String
  export_name : String
  source_export_name : String
  func : @ast.TsFunc
}

///|
priv struct ExportedValueDecl {
  source_path : String
  local_name_prefix : String
  export_name : String
  source_export_name : String
  value : @ast.TsValueDecl
}

///|
priv struct ExportedClassDecl {
  source_path : String
  local_name : String
  local_name_prefix : String
  export_name : String
  source_export_name : String
  class_ : @ast.TsClassDecl
}

///|
priv struct ResultInterfaceSpec {
  export_name : String
  iface : @ast.TsInterface
  needs_runtime_tuple_wrapper : Bool
}

///|
priv struct ResolvedInterfaceOrigin {
  info : DeclModuleInfo
  export_name : String
  iface : @ast.TsInterface
}

///|
priv struct ResolvedClassOrigin {
  info : DeclModuleInfo
  local_name_prefix : String
  class_ : @ast.TsClassDecl
}

///|
priv struct ExportedConstValueSet {
  values : Map[String, @ast.TsExpr]
  explicit_names : Array[String]
  star_names : Array[String]
  ambiguous_names : Array[String]
}

///|

///|
fn decl_is_string_intrinsic_name(name : String) -> Bool {
  name == "Capitalize" ||
  name == "Uncapitalize" ||
  name == "Uppercase" ||
  name == "Lowercase"
}

///|
fn decl_apply_string_intrinsic_to_value(
  intrinsic : String,
  value : String,
) -> String? {
  if value.length() == 0 {
    return Some(value)
  }
  let head = value[0].unsafe_to_char()
  let rest = value[1:].to_string()
  match intrinsic {
    "Capitalize" =>
      if head >= 'a' && head <= 'z' {
        Some((head.to_int() - 32).unsafe_to_char().to_string() + rest)
      } else {
        Some(value)
      }
    "Uncapitalize" =>
      if head >= 'A' && head <= 'Z' {
        Some((head.to_int() + 32).unsafe_to_char().to_string() + rest)
      } else {
        Some(value)
      }
    "Uppercase" => Some(value.to_upper())
    "Lowercase" => Some(value.to_lower())
    _ => None
  }
}

///|
/// If `arg` is a literal string union (or a single literal), apply the
/// intrinsic string mapping pointwise and return the resulting type.
/// Returns `None` when any element is not a string literal.
fn decl_apply_string_intrinsic_to_literal_union(
  intrinsic : String,
  arg : @ast.TsType,
) -> @ast.TsType? {
  let items = match arg {
    @ast.TsType::Literal(_) => [arg]
    @ast.TsType::Union(members) => members
    _ => return None
  }
  let next_items : Array[@ast.TsType] = []
  for item in items {
    match item {
      @ast.TsType::Literal(value) =>
        match decl_apply_string_intrinsic_to_value(intrinsic, value) {
          Some(mapped) => next_items.push(@ast.TsType::Literal(mapped))
          None => return None
        }
      _ => return None
    }
  }
  if next_items.length() == 1 {
    Some(next_items[0])
  } else {
    Some(@ast.TsType::Union(next_items))
  }
}

///|
/// Walk a `Conditional` to its terminal `false` branch, collecting `true`
/// branches along the way. Returns `(true_branches, default_branch)`.
fn flatten_conditional_branches(
  t : @ast.TsType,
) -> (Array[@ast.TsType], @ast.TsType) {
  let trues : Array[@ast.TsType] = []
  let mut current = t
  while true {
    match current {
      @ast.TsType::Conditional(_, _, true_, false_) => {
        trues.push(true_)
        current = false_
      }
      _ => break
    }
  }
  (trues, current)
}

///|
/// If `inner` is a `Conditional` that survived all reduction passes, accept
/// its terminal `false` branch as the join when the default is a concrete,
/// non-trivial `Named(N)`. Real-world TypeScript patterns like
/// `Array<O extends X<infer T> ? T : I["start"] extends Date ? I["start"] :
/// ... : Date>` carry a default branch (`Date`) that all true branches are
/// expected to be assignable to via their own `extends` checks; widening to
/// the default upper bound matches what TypeScript itself emits for the
/// declared return type.
///
/// Rejects: `T extends X ? T : never` (default is `never`), conditionals
/// whose default is itself unresolved (`Conditional`, `Any`, generic), and
/// conditionals with no `Named` default name.
fn conditional_array_element_default_join(inner : @ast.TsType) -> @ast.TsType? {
  match inner {
    @ast.TsType::Conditional(_, _, _, _) => {
      let (_, default_) = flatten_conditional_branches(inner)
      match default_ {
        @ast.TsType::Named(name) if name != "never" =>
          Some(@ast.TsType::Named(name))
        _ => None
      }
    }
    _ => None
  }
}

///|
priv enum ResolvedDecl {
  Interface(ExportedInterfaceDecl)
  Enum(ExportedEnumDecl)
  TaggedUnion(ExportedTaggedUnionDecl)
  TypeAlias(ExportedTypeAliasDecl)
  Import(ExportedImportDecl)
  Function(ExportedFuncDecl)
  Value(ExportedValueDecl)
  Class(ExportedClassDecl)
  Unsupported(String, String)
  Missing
}

///|
fn decl_key(source_path : String, local_name : String) -> String {
  source_path + "\n" + local_name
}

///|
fn decl_is_ascii_letter(c : Char) -> Bool {
  (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
}

///|
fn decl_is_ascii_digit(c : Char) -> Bool {
  c >= '0' && c <= '9'
}

///|
fn decl_to_lower_ascii(c : Char) -> Char {
  if c >= 'A' && c <= 'Z' {
    (c.to_int() + 32).unsafe_to_char()
  } else {
    c
  }
}

///|
fn decl_to_upper_ascii(c : Char) -> Char {
  if c >= 'a' && c <= 'z' {
    (c.to_int() - 32).unsafe_to_char()
  } else {
    c
  }
}

///|
fn decl_sanitize_identifier(name : String, fallback : String) -> String {
  let mut result = ""
  for c in name {
    if decl_is_ascii_letter(c) || decl_is_ascii_digit(c) || c == '_' {
      result += c.to_string()
    } else {
      result += "_"
    }
  }
  if result == "" {
    result = fallback
  }
  let first = result[0].unsafe_to_char()
  if decl_is_ascii_digit(first) {
    result = "_" + result
  }
  result
}

///|
fn decl_trim_underscores(name : String) -> String {
  let mut start = 0
  let mut end_ = name.length()
  while start < end_ && name[start].unsafe_to_char() == '_' {
    start += 1
  }
  while end_ > start && name[end_ - 1].unsafe_to_char() == '_' {
    end_ -= 1
  }
  name[start:end_].to_string()
}

///|
fn decl_to_snake_case(name : String) -> String {
  let mut result = ""
  let mut prev_is_lower_or_digit = false
  for c in name {
    if c >= 'A' && c <= 'Z' {
      if result != "" && prev_is_lower_or_digit {
        result += "_"
      }
      result += decl_to_lower_ascii(c).to_string()
      prev_is_lower_or_digit = false
    } else if decl_is_ascii_letter(c) || decl_is_ascii_digit(c) {
      result += c.to_string()
      prev_is_lower_or_digit = (c >= 'a' && c <= 'z') || decl_is_ascii_digit(c)
    } else {
      if result != "" && !result.has_suffix("_") {
        result += "_"
      }
      prev_is_lower_or_digit = false
    }
  }
  decl_sanitize_identifier(decl_trim_underscores(result), "generated_name")
}

///|
fn decl_to_pascal_case(name : String) -> String {
  let snake = decl_to_snake_case(name)
  let parts = snake.split("_")
  let mut result = ""
  for part_view in parts {
    let part = part_view.to_string()
    if part == "" {
      continue
    }
    result += decl_to_upper_ascii(part[0].unsafe_to_char()).to_string() +
      part[1:].to_string()
  }
  decl_sanitize_identifier(result, "OpaqueType")
}

///|
fn tuple_result_interface_name(export_name : String) -> String {
  decl_to_pascal_case(export_name) + "Result"
}

///|
fn tuple_result_field_names(
  export_name : String,
  item_count : Int,
) -> Array[String] {
  match export_name {
    "useState" if item_count == 2 => ["state", "setState"]
    "useReducer" if item_count == 2 => ["state", "dispatch"]
    "useTransition" if item_count == 2 => ["isPending", "startTransition"]
    "useOptimistic" if item_count == 2 => ["state", "dispatch"]
    "useActionState" if item_count == 3 => ["state", "dispatch", "isPending"]
    _ => {
      let names : Array[String] = []
      for i in 0..<item_count {
        names.push("_" + i.to_string())
      }
      names
    }
  }
}

///|
fn decl_ambiguous_export_reason(
  export_ : ResolvedExport,
  base_reason : String,
) -> String {
  if export_.ambiguous_source_paths.length() == 0 {
    base_reason + "."
  } else {
    base_reason +
    "; candidates: " +
    export_.ambiguous_source_paths.join(", ") +
    "."
  }
}

///|
async fn load_decl_module_info(
  record : ResolvedModuleRecord,
  seeded_const_values : Map[String, @ast.TsExpr],
) -> DeclModuleInfo raise ModuleGraphError {
  let content = @fs.read_file(record.path).text() catch {
    e => raise ReadError("Failed to read module '\{record.path}': \{e}")
  }
  let module_ = @parser.parse_module_from_source_with_const_values(
    content, seeded_const_values,
  ) catch {
    @parser.ParseError(msg) =>
      if is_declaration_path(record.path) {
        raise ParseError(
          "Failed to parse declarations in '\{record.path}': \{msg}",
        )
      } else {
        {
          funcs: [],
          interfaces: [],
          type_aliases: [],
          imports: [],
          values: [],
          classes: [],
          namespaces: [],
          enums: [],
          module_augmentations: [],
        }
      }
  }
  // Optional hybrid oracle: when `TS_MBT_ORACLE_CACHE` is set, splice the
  // resolved-type cache produced by `scripts/oracle/resolve-types.mjs` into
  // this module's type-alias table. The rest of the bridge then resolves
  // `Named(name)` references through the standard alias path.
  match @env.get_env_var("TS_MBT_ORACLE_CACHE") {
    Some(cache_path) if cache_path != "" => {
      let resolutions = read_oracle_cache(cache_path) catch {
        _ => ({} : Map[String, @ast.TsType])
      }
      if resolutions.length() > 0 {
        apply_oracle_resolutions(module_, resolutions)
      }
    }
    _ => ()
  }
  { record, module_ }
}

///|
async fn build_direct_exported_const_value_map(
  record : ResolvedModuleRecord,
) -> Map[String, @ast.TsExpr] raise ModuleGraphError {
  let content = @fs.read_file(record.path).text() catch {
    e => raise ReadError("Failed to read module '\{record.path}': \{e}")
  }
  @parser.collect_exported_const_values_from_source(content, {}) catch {
    @parser.ParseError(msg) =>
      raise ParseError(
        "Failed to parse exported const values from '\{record.path}': \{msg}",
      )
  }
}

///|
fn new_exported_const_value_set(
  direct_values : Map[String, @ast.TsExpr],
) -> ExportedConstValueSet {
  let explicit_names : Array[String] = []
  for entry in direct_values {
    explicit_names.push(entry.0)
  }
  { values: direct_values, explicit_names, star_names: [], ambiguous_names: [] }
}

///|
fn exported_const_value_expr(
  set : ExportedConstValueSet,
  export_name : String,
) -> @ast.TsExpr? {
  if set.explicit_names.contains(export_name) {
    return set.values.get(export_name)
  }
  if set.ambiguous_names.contains(export_name) {
    return None
  }
  set.values.get(export_name)
}

///|
fn exported_const_namespace_expr(set : ExportedConstValueSet) -> @ast.TsExpr {
  let props : Array[(String, @ast.TsExpr)] = []
  for entry in set.values {
    let export_name = entry.0
    match exported_const_value_expr(set, export_name) {
      Some(expr) => props.push((export_name, expr))
      None => ()
    }
  }
  @ast.TsExpr::ObjectLit(props)
}

///|
fn build_record_map(graph : ModuleGraph) -> Map[String, ResolvedModuleRecord] {
  let records : Map[String, ResolvedModuleRecord] = {}
  for record in graph.modules {
    records[record.path] = record
  }
  records
}

///|
async fn build_exported_const_value_map_for_path(
  path : String,
  records : Map[String, ResolvedModuleRecord],
  cache : Map[String, ExportedConstValueSet],
  visiting : Array[String],
) -> ExportedConstValueSet raise ModuleGraphError {
  match cache.get(path) {
    Some(exported_const_values) => return exported_const_values
    None => ()
  }
  if visiting.contains(path) {
    return {
      values: {},
      explicit_names: [],
      star_names: [],
      ambiguous_names: [],
    }
  }
  let record = match records.get(path) {
    Some(record) => record
    None =>
      return {
        values: {},
        explicit_names: [],
        star_names: [],
        ambiguous_names: [],
      }
  }
  visiting.push(path)
  let exported_const_values = new_exported_const_value_set(
    build_direct_exported_const_value_map(record),
  )
  for reexport in record.reexports {
    match reexport.kind {
      @ast.TsReExportKind::Named(items) => {
        let dep_exported_const_values = build_exported_const_value_map_for_path(
          reexport.resolved_path,
          records,
          cache,
          visiting,
        )
        for item in items {
          let (imported_name, export_name) = item
          match
            exported_const_value_expr(dep_exported_const_values, imported_name) {
            Some(expr) => {
              exported_const_values.values[export_name] = expr
              if !exported_const_values.explicit_names.contains(export_name) {
                exported_const_values.explicit_names.push(export_name)
              }
            }
            None => ()
          }
        }
      }
      @ast.TsReExportKind::All => {
        let dep_exported_const_values = build_exported_const_value_map_for_path(
          reexport.resolved_path,
          records,
          cache,
          visiting,
        )
        for entry in dep_exported_const_values.values {
          let export_name = entry.0
          if export_name == "default" {
            continue
          }
          match
            exported_const_value_expr(dep_exported_const_values, export_name) {
            Some(expr) =>
              if exported_const_values.explicit_names.contains(export_name) ||
                exported_const_values.ambiguous_names.contains(export_name) {
                continue
              } else if exported_const_values.star_names.contains(export_name) {
                if !exported_const_values.ambiguous_names.contains(export_name) {
                  exported_const_values.ambiguous_names.push(export_name)
                }
              } else {
                exported_const_values.values[export_name] = expr
                exported_const_values.star_names.push(export_name)
              }
            None => ()
          }
        }
      }
      @ast.TsReExportKind::Namespace(_) => ()
    }
  }
  cache[path] = exported_const_values
  let _ = visiting.pop()
  exported_const_values
}

///|
async fn build_exported_const_value_map_by_path(
  graph : ModuleGraph,
) -> Map[String, ExportedConstValueSet] raise ModuleGraphError {
  let records = build_record_map(graph)
  let cache : Map[String, ExportedConstValueSet] = {}
  let visiting : Array[String] = []
  for record in graph.modules {
    cache[record.path] = build_exported_const_value_map_for_path(
      record.path,
      records,
      cache,
      visiting,
    )
  }
  cache
}

///|
fn build_imported_const_seed(
  record : ResolvedModuleRecord,
  exported_const_values_by_path : Map[String, ExportedConstValueSet],
) -> Map[String, @ast.TsExpr] {
  let seeded_const_values : Map[String, @ast.TsExpr] = {}
  for i, import_decl in record.module_block.imports {
    let resolved_edge = record.imports[i]
    if import_decl.type_only ||
      import_decl.side_effect_only ||
      resolved_edge.resolved_path == "" {
      continue
    }
    match exported_const_values_by_path.get(resolved_edge.resolved_path) {
      Some(exported_const_values) => {
        match import_decl.default_binding {
          Some(local_name) =>
            match exported_const_value_expr(exported_const_values, "default") {
              Some(expr) => seeded_const_values[local_name] = expr
              None => ()
            }
          None => ()
        }
        match import_decl.namespace_binding {
          Some(local_name) =>
            seeded_const_values[local_name] = exported_const_namespace_expr(
              exported_const_values,
            )
          None => ()
        }
        for binding in import_decl.named_bindings {
          let (imported_name, local_name) = binding
          match
            exported_const_value_expr(exported_const_values, imported_name) {
            Some(expr) => seeded_const_values[local_name] = expr
            None => ()
          }
        }
      }
      None => ()
    }
  }
  seeded_const_values
}

///|
async fn build_decl_module_map(
  graph : ModuleGraph,
) -> Map[String, DeclModuleInfo] raise ModuleGraphError {
  let exported_const_values_by_path = build_exported_const_value_map_by_path(
    graph,
  )
  let modules : Map[String, DeclModuleInfo] = {}
  for record in graph.modules {
    let seeded_const_values = build_imported_const_seed(
      record, exported_const_values_by_path,
    )
    modules[record.path] = load_decl_module_info(record, seeded_const_values)
  }
  modules
}

///|
fn find_interface_decl(
  module_ : @ast.TsModule,
  name : String,
) -> @ast.TsInterface? {
  for iface in module_.interfaces {
    if iface.name == name {
      return Some(iface)
    }
  }
  None
}

///|
/// Replace any `Named(name)` reachable inside `t` with the resolved
/// `Struct(...)` shape from the current module. Used to seed mapped /
/// keyof simplification with field-aware sources (`{ [K in keyof Foo]:
/// ... }` becomes `{ [K in keyof Struct(Foo, fields)]: ... }` so the
/// simplifier can iterate keys).
fn resolve_named_inside_type(
  info : DeclModuleInfo,
  t : @ast.TsType,
) -> @ast.TsType {
  match t {
    Named(name) =>
      match resolve_named_to_struct(info, name) {
        Some(s) => s
        None => t
      }
    Keyof(inner) => Keyof(resolve_named_inside_type(info, inner))
    Array(inner) => Array(resolve_named_inside_type(info, inner))
    Union(items) => {
      let out : Array[@ast.TsType] = []
      for it in items {
        out.push(resolve_named_inside_type(info, it))
      }
      Union(out)
    }
    Intersection(items) => {
      let out : Array[@ast.TsType] = []
      for it in items {
        out.push(resolve_named_inside_type(info, it))
      }
      Intersection(out)
    }
    _ => t
  }
}

///|
/// Inline a `Named(name)` reference to the body of its type alias.
/// `name` may be qualified (`util.HashAlgorithm`), in which case the
/// leading segment is matched against the current module's
/// `namespace_binding` imports to locate the source module before
/// looking up the unqualified tail. Recursively resolves chained
/// aliases (`type A = B`, `type B = "x" | "y"`) until reaching a
/// concrete shape; stops on parameterized aliases or cycles.
fn resolve_named_to_alias_body(
  info : DeclModuleInfo,
  modules : Map[String, DeclModuleInfo],
  name : String,
  visited : Array[String],
) -> @ast.TsType? {
  if visited.contains(name) {
    return None
  }
  // Qualified path: `util.HashAlgorithm` first walks the namespace
  // import in the current module, then resolves the tail in the imported
  // module's surface (its own type aliases / enums, plus its re-exports
  // from sub-modules — essential for split packages like zod where the
  // entry only re-exports through `import * as util`).
  let dot_pos = name.find(".")
  match dot_pos {
    Some(pos) => {
      let head = name[0:pos].to_string()
      let tail = name[pos + 1:].to_string()
      match resolve_namespace_alias_module(info, modules, head) {
        Some(target_info) => {
          let next_visited : Array[String] = []
          for v in visited {
            next_visited.push(v)
          }
          next_visited.push(name)
          return resolve_named_to_alias_body(
            target_info, modules, tail, next_visited,
          )
        }
        None => ()
      }
    }
    None => ()
  }
  match find_type_alias_decl(info.module_, name) {
    Some(ta) => {
      if ta.type_params.length() > 0 {
        return None
      }
      let next_visited : Array[String] = []
      for v in visited {
        next_visited.push(v)
      }
      next_visited.push(name)
      let body = inline_named_aliases(info, modules, ta.type_, next_visited)
      Some(body)
    }
    None =>
      // Parser already lifts string-literal-union aliases (`type Channel
      // = "info" | "warn"`) into enums, so the alias may not appear in
      // `type_aliases`. Reconstruct the union from the enum's string
      // members so template-literal / mapped passes can still see a
      // finite literal source.
      match find_enum_decl(info.module_, name) {
        Some(e) => {
          let items : Array[@ast.TsType] = []
          for m in e.members {
            match m.value {
              Some(@ast.TsEnumMemberValue::String(s)) => items.push(Literal(s))
              _ => return None
            }
          }
          if items.length() == 0 {
            None
          } else if items.length() == 1 {
            Some(items[0])
          } else {
            Some(Union(items))
          }
        }
        None => None
      }
  }
}

///|
/// Look up the module behind `import * as <local> from "<spec>"` (or
/// the matching re-export). Returns `None` when no namespace binding
/// matches `local` or when the spec doesn't resolve through the import
/// edges (e.g. a package whose graph wasn't fully loaded).
fn resolve_namespace_alias_module(
  info : DeclModuleInfo,
  modules : Map[String, DeclModuleInfo],
  local_alias : String,
) -> DeclModuleInfo? {
  for imp in info.record.module_block.imports {
    match imp.namespace_binding {
      Some(binding) if binding == local_alias =>
        for edge in info.record.imports {
          if edge.specifier == imp.module_spec {
            match modules.get(edge.resolved_path) {
              Some(target) => return Some(target)
              None => ()
            }
          }
        }
      _ => ()
    }
  }
  // Some packages re-export entire sub-modules with `export * as util
  // from './util'`. Check the namespace re-exports too.
  for re in info.record.module_block.reexports {
    match re.kind {
      Namespace(name) if name == local_alias =>
        for edge in info.record.imports {
          if edge.specifier == re.module_spec {
            match modules.get(edge.resolved_path) {
              Some(target) => return Some(target)
              None => ()
            }
          }
        }
      _ => ()
    }
  }
  None
}

///|
fn inline_named_aliases(
  info : DeclModuleInfo,
  modules : Map[String, DeclModuleInfo],
  t : @ast.TsType,
  visited : Array[String],
) -> @ast.TsType {
  match t {
    Named(name) =>
      match resolve_named_to_alias_body(info, modules, name, visited) {
        Some(body) => body
        None => t
      }
    Union(items) => {
      let out : Array[@ast.TsType] = []
      for it in items {
        out.push(inline_named_aliases(info, modules, it, visited))
      }
      Union(out)
    }
    Array(inner) => Array(inline_named_aliases(info, modules, inner, visited))
    Tuple(items) => {
      let out : Array[@ast.TsType] = []
      for it in items {
        out.push(inline_named_aliases(info, modules, it, visited))
      }
      Tuple(out)
    }
    Applied(name, args) => {
      let out : Array[@ast.TsType] = []
      for a in args {
        out.push(inline_named_aliases(info, modules, a, visited))
      }
      Applied(name, out)
    }
    Keyof(inner) => Keyof(inline_named_aliases(info, modules, inner, visited))
    TemplateLiteralType(parts, args) => {
      let out : Array[@ast.TsType] = []
      for a in args {
        out.push(inline_named_aliases(info, modules, a, visited))
      }
      TemplateLiteralType(parts, out)
    }
    _ => t
  }
}

///|
/// Look up `name` in the current module's interfaces / type aliases and
/// surface a `Struct(name, fields)` whose field types are good enough for
/// the simplifier to read keys off (`keyof Foo`, `{ [K in keyof Foo]: V }`,
/// etc.). Returns `None` for opaque module-level identifiers so callers
/// keep the original `Named(...)` and the bridge can fall back to `String`.
fn resolve_named_to_struct(
  info : DeclModuleInfo,
  name : String,
) -> @ast.TsType? {
  match find_interface_decl_recursive(info.module_, name) {
    Some(iface) => {
      let fields : Array[(String, @ast.TsType)] = []
      for f in iface.fields {
        fields.push(f)
      }
      Some(Struct(iface.name, fields))
    }
    None =>
      match find_type_alias_decl(info.module_, name) {
        Some(ta) =>
          match ta.type_ {
            Object(obj_fields) => {
              let fields : Array[(String, @ast.TsType)] = []
              for f in obj_fields {
                match f.0 {
                  Literal(k) => fields.push((k, f.1))
                  _ => return None
                }
              }
              Some(Struct(ta.name, fields))
            }
            Struct(_, _) => Some(ta.type_)
            _ => None
          }
        None => None
      }
  }
}

///|
fn find_interface_decl_recursive(
  module_ : @ast.TsModule,
  name : String,
) -> @ast.TsInterface? {
  match find_interface_decl(module_, name) {
    Some(iface) => Some(iface)
    None => {
      for namespace_ in module_.namespaces {
        match find_interface_decl_recursive(namespace_.module_, name) {
          Some(iface) => return Some(iface)
          None => ()
        }
      }
      None
    }
  }
}

///|
fn find_enum_decl(module_ : @ast.TsModule, name : String) -> @ast.TsEnumDecl? {
  for enum_ in module_.enums {
    if enum_.name == name {
      return Some(enum_)
    }
  }
  None
}

///|
fn find_import_decl(module_ : @ast.TsModule, name : String) -> @ast.TsImport? {
  let mut found : @ast.TsImport? = None
  for import_ in module_.imports {
    if import_.name == name {
      match found {
        Some(existing) =>
          if decl_import_widening_score(import_) <
            decl_import_widening_score(existing) {
            found = Some(import_)
          }
        None => found = Some(import_)
      }
    }
  }
  found
}

///|
fn find_import_decls(
  module_ : @ast.TsModule,
  name : String,
) -> Array[@ast.TsImport] {
  let found : Array[@ast.TsImport] = []
  for import_ in module_.imports {
    if import_.name == name {
      found.push(import_)
    }
  }
  found
}

///|
fn find_namespace_decl(
  module_ : @ast.TsModule,
  name : String,
) -> @ast.TsNamespaceDecl? {
  for namespace_ in module_.namespaces {
    if namespace_.name == name {
      return Some(namespace_)
    }
  }
  None
}

///|
fn find_jsx_intrinsic_elements_decl(
  module_ : @ast.TsModule,
) -> @ast.TsInterface? {
  for namespace_ in module_.namespaces {
    if namespace_.name == "JSX" {
      match find_interface_decl(namespace_.module_, "IntrinsicElements") {
        Some(iface) => return Some(iface)
        None => ()
      }
    }
    match find_jsx_intrinsic_elements_decl(namespace_.module_) {
      Some(iface) => return Some(iface)
      None => ()
    }
  }
  None
}

///|
fn find_func_decl(module_ : @ast.TsModule, name : String) -> @ast.TsFunc? {
  let mut found : @ast.TsFunc? = None
  for func in module_.funcs {
    if func.name == name {
      match found {
        Some(existing) =>
          if decl_func_widening_score(func) < decl_func_widening_score(existing) {
            found = Some(func)
          }
        None => found = Some(func)
      }
    }
  }
  found
}

///|
fn find_func_decls(
  module_ : @ast.TsModule,
  name : String,
) -> Array[@ast.TsFunc] {
  let found : Array[@ast.TsFunc] = []
  for func in module_.funcs {
    if func.name == name {
      found.push(func)
    }
  }
  found
}

///|
fn merge_func_param_types(
  params : Array[@ast.TsParam],
  declared_type : @ast.TsType,
) -> Array[@ast.TsParam] {
  let declared_params = match declared_type {
    @ast.TsType::Func(param_types, _) => Some(param_types)
    _ => None
  }
  let merged : Array[@ast.TsParam] = []
  for index, param in params {
    let next_type = match declared_params {
      Some(param_types) if index < param_types.length() &&
        param.type_ == @ast.TsType::Any => param_types[index]
      _ => param.type_
    }
    merged.push({
      name: param.name,
      binding: param.binding,
      is_rest: param.is_rest,
      type_: next_type,
      default: param.default,
    })
  }
  merged
}

///|
fn find_param_type(params : Array[@ast.TsParam], name : String) -> @ast.TsType? {
  for param in params {
    if param.name == name {
      return Some(param.type_)
    }
  }
  None
}

///|
fn infer_numeric_result_type(
  left : @ast.TsExpr,
  right : @ast.TsExpr,
  params : Array[@ast.TsParam],
) -> @ast.TsType {
  let left_type = infer_decl_expr_type(left, params)
  let right_type = infer_decl_expr_type(right, params)
  let left_is_number = left_type == @ast.TsType::Number ||
    left_type == @ast.TsType::Int
  let right_is_number = right_type == @ast.TsType::Number ||
    right_type == @ast.TsType::Int
  if !left_is_number || !right_is_number {
    return @ast.TsType::Any
  }
  if left_type == @ast.TsType::Int && right_type == @ast.TsType::Int {
    @ast.TsType::Int
  } else {
    @ast.TsType::Number
  }
}

///|
fn infer_decl_expr_type(
  expr : @ast.TsExpr,
  params : Array[@ast.TsParam],
) -> @ast.TsType {
  match expr {
    @ast.TsExpr::NumberLit(_) => @ast.TsType::Number
    @ast.TsExpr::IntLit(_) => @ast.TsType::Int
    @ast.TsExpr::BoolLit(_) => @ast.TsType::Boolean
    @ast.TsExpr::StringLit(_) | @ast.TsExpr::TemplateLiteral(_, _) =>
      @ast.TsType::String_
    @ast.TsExpr::NullLit => @ast.TsType::Null
    @ast.TsExpr::Var(name) =>
      match find_param_type(params, name) {
        Some(type_) => type_
        None => @ast.TsType::Any
      }
    @ast.TsExpr::UnaryOp(@ast.TsUnaryOp::Not, _) => @ast.TsType::Boolean
    @ast.TsExpr::UnaryOp(@ast.TsUnaryOp::Neg, inner) =>
      match infer_decl_expr_type(inner, params) {
        @ast.TsType::Int => @ast.TsType::Int
        @ast.TsType::Number => @ast.TsType::Number
        _ => @ast.TsType::Number
      }
    @ast.TsExpr::BinOp(op, left, right) =>
      match op {
        @ast.TsBinOp::Add =>
          if infer_decl_expr_type(left, params) == @ast.TsType::String_ ||
            infer_decl_expr_type(right, params) == @ast.TsType::String_ {
            @ast.TsType::String_
          } else {
            infer_numeric_result_type(left, right, params)
          }
        @ast.TsBinOp::Sub
        | @ast.TsBinOp::Mul
        | @ast.TsBinOp::Div
        | @ast.TsBinOp::Mod
        | @ast.TsBinOp::Pow => infer_numeric_result_type(left, right, params)
        @ast.TsBinOp::BinEq
        | @ast.TsBinOp::BinNe
        | @ast.TsBinOp::AbstractEq
        | @ast.TsBinOp::AbstractNe
        | @ast.TsBinOp::BinLt
        | @ast.TsBinOp::BinLe
        | @ast.TsBinOp::BinGt
        | @ast.TsBinOp::BinGe
        | @ast.TsBinOp::Instanceof
        | @ast.TsBinOp::In => @ast.TsType::Boolean
        @ast.TsBinOp::And | @ast.TsBinOp::Or | @ast.TsBinOp::Coalesce => {
          let left_type = infer_decl_expr_type(left, params)
          let right_type = infer_decl_expr_type(right, params)
          if left_type == right_type {
            left_type
          } else {
            @ast.TsType::Any
          }
        }
        _ => @ast.TsType::Any
      }
    @ast.TsExpr::Cond(_, then_, else_) => {
      let then_type = infer_decl_expr_type(then_, params)
      let else_type = infer_decl_expr_type(else_, params)
      if then_type == else_type {
        then_type
      } else {
        @ast.TsType::Any
      }
    }
    _ => @ast.TsType::Any
  }
}

///|
fn infer_block_return_type(
  block : @ast.TsBlock,
  params : Array[@ast.TsParam],
) -> @ast.TsType {
  for i in 0..<block.stmts.length() {
    let index = block.stmts.length() - 1 - i
    match block.stmts[index] {
      @ast.TsStmt::Return(Some(expr)) =>
        return infer_decl_expr_type(expr, params)
      @ast.TsStmt::Return(None) => return @ast.TsType::Void
      @ast.TsStmt::Block(inner) => {
        let inner_type = infer_block_return_type(inner, params)
        if inner_type != @ast.TsType::Any {
          return inner_type
        }
      }
      _ => ()
    }
  }
  @ast.TsType::Any
}

///|
fn infer_func_return_type(
  func : @ast.TsFunc,
  declared_type : @ast.TsType,
) -> @ast.TsType {
  if func.return_type != @ast.TsType::Any {
    return func.return_type
  }
  match declared_type {
    @ast.TsType::Func(_, return_type) => return_type
    _ => infer_block_return_type(func.body, func.params)
  }
}

///|
fn synthesize_func_from_expr(
  local_name : String,
  declared_type : @ast.TsType,
  expr : @ast.TsExpr,
) -> @ast.TsFunc? {
  match expr {
    @ast.TsExpr::FuncExpr(func) =>
      Some({
        name: local_name,
        type_params: func.type_params,
        params: merge_func_param_types(func.params, declared_type),
        return_type: infer_func_return_type(func, declared_type),
        body: func.body,
        is_generator: func.is_generator,
        is_async: func.is_async,
      })
    @ast.TsExpr::ArrowFunc(params, _declared_ret, body, is_async) => {
      let normalized_params = merge_func_param_types(params, declared_type)
      let normalized_body = match body {
        @ast.TsArrowBody::ArrowExpr(expr) =>
          @ast.TsBlock::{ stmts: [@ast.TsStmt::Return(Some(expr))] }
        @ast.TsArrowBody::ArrowBlock(block) => block
      }
      let return_type = match declared_type {
        @ast.TsType::Func(_, next_return_type) => next_return_type
        _ =>
          match body {
            @ast.TsArrowBody::ArrowExpr(expr) =>
              infer_decl_expr_type(expr, normalized_params)
            @ast.TsArrowBody::ArrowBlock(block) =>
              infer_block_return_type(block, normalized_params)
          }
      }
      Some({
        name: local_name,
        type_params: [],
        params: normalized_params,
        return_type,
        body: normalized_body,
        is_generator: false,
        is_async,
      })
    }
    _ => None
  }
}

///|
fn find_func_decl_from_stmts(
  stmts : Array[@ast.TsStmt],
  name : String,
) -> @ast.TsFunc? {
  for stmt in stmts {
    match stmt {
      @ast.TsStmt::Let(@ast.TsBinding::Ident(local_name), declared_type, expr)
      | @ast.TsStmt::Const(
        @ast.TsBinding::Ident(local_name),
        declared_type,
        expr
      )
      | @ast.TsStmt::Var(@ast.TsBinding::Ident(local_name), declared_type, expr) =>
        if local_name == name {
          match synthesize_func_from_expr(local_name, declared_type, expr) {
            Some(func) => return Some(func)
            None => ()
          }
        }
      @ast.TsStmt::Block(block) =>
        match find_func_decl_from_stmts(block.stmts, name) {
          Some(func) => return Some(func)
          None => ()
        }
      _ => ()
    }
  }
  None
}

///|
fn find_value_decl(module_ : @ast.TsModule, name : String) -> @ast.TsValueDecl? {
  for value in module_.values {
    if value.name == name {
      return Some(value)
    }
  }
  None
}

///|
fn find_class_decl(module_ : @ast.TsModule, name : String) -> @ast.TsClassDecl? {
  for class_ in module_.classes {
    if class_.name == name {
      return Some(class_)
    }
  }
  None
}

///|
fn find_class_decl_recursive(
  module_ : @ast.TsModule,
  name : String,
) -> @ast.TsClassDecl? {
  match find_class_decl(module_, name) {
    Some(class_) => Some(class_)
    None => {
      for namespace_ in module_.namespaces {
        match find_class_decl_recursive(namespace_.module_, name) {
          Some(class_) => return Some(class_)
          None => ()
        }
      }
      None
    }
  }
}

///|
fn module_has_runtime_value_decl(
  module_ : @ast.TsModule,
  name : String,
) -> Bool {
  let has_namespace = match find_namespace_decl(module_, name) {
    Some(_) => true
    None => false
  }
  let mut runtime_value_count = 0
  for value in module_.values {
    if value.name != name || !value_decl_has_runtime_binding(value) {
      continue
    }
    runtime_value_count += 1
    if !has_namespace || value.type_ != @ast.TsType::Any {
      return true
    }
  }
  runtime_value_count > 1
}

///|
fn module_has_non_namespace_runtime_decl(
  module_ : @ast.TsModule,
  name : String,
) -> Bool {
  match find_import_decl(module_, name) {
    Some(_) => return true
    None => ()
  }
  match find_func_decl(module_, name) {
    Some(_) => return true
    None => ()
  }
  match find_class_decl(module_, name) {
    Some(_) => return true
    None => ()
  }
  if module_has_runtime_value_decl(module_, name) {
    return true
  }
  false
}

///|
fn namespace_member_runtime_export_name(
  root_export_name : String,
  member_name : String,
) -> String {
  root_export_name + "." + member_name
}

///|
fn decl_to_camel_case(name : String) -> String {
  let pascal = decl_to_pascal_case(name)
  if pascal == "" {
    return pascal
  }
  decl_to_lower_ascii(pascal[0].unsafe_to_char()).to_string() +
  pascal[1:].to_string()
}

///|
fn namespace_local_export_name(prefix : String, member_name : String) -> String {
  if prefix == "" {
    member_name
  } else {
    prefix + member_name
  }
}

///|
fn namespace_type_export_name(prefix : String, member_name : String) -> String {
  if prefix == "" {
    member_name
  } else {
    prefix + decl_to_pascal_case(member_name)
  }
}

///|
fn namespace_value_export_name(prefix : String, member_name : String) -> String {
  if prefix == "" {
    member_name
  } else {
    prefix + decl_to_pascal_case(member_name)
  }
}

///|
fn namespace_next_type_export_prefix(
  prefix : String,
  namespace_name : String,
) -> String {
  let segment = decl_to_pascal_case(namespace_name)
  if prefix == "" {
    segment
  } else {
    prefix + segment
  }
}

///|
fn namespace_next_value_export_prefix(
  prefix : String,
  namespace_name : String,
) -> String {
  if prefix == "" {
    decl_to_camel_case(namespace_name)
  } else {
    prefix + decl_to_pascal_case(namespace_name)
  }
}

///|
fn append_exported_type_namespace_members_with_prefix(
  source_path : String,
  local_name_prefix : String,
  type_export_prefix : String,
  namespace_ : @ast.TsNamespaceDecl,
  interfaces : Array[ExportedInterfaceDecl],
  enums : Array[ExportedEnumDecl],
) -> Unit {
  for iface in namespace_.module_.interfaces {
    interfaces.push({
      source_path,
      local_name: namespace_local_export_name(local_name_prefix, iface.name),
      export_name: namespace_type_export_name(type_export_prefix, iface.name),
      iface,
    })
  }
  for enum_ in namespace_.module_.enums {
    enums.push({
      source_path,
      local_name: namespace_local_export_name(local_name_prefix, enum_.name),
      export_name: namespace_type_export_name(type_export_prefix, enum_.name),
      enum_,
    })
  }
  for nested in namespace_.module_.namespaces {
    append_exported_type_namespace_members_with_prefix(
      source_path,
      namespace_local_export_name(local_name_prefix, nested.name + "."),
      namespace_next_type_export_prefix(type_export_prefix, nested.name),
      nested,
      interfaces,
      enums,
    )
  }
}

///|
fn namespace_has_non_type_members(namespace_ : @ast.TsNamespaceDecl) -> Bool {
  if namespace_.module_.imports.length() > 0 ||
    namespace_.module_.funcs.length() > 0 ||
    namespace_.module_.classes.length() > 0 {
    return true
  }
  for value in namespace_.module_.values {
    if value_decl_has_runtime_binding(value) {
      return true
    }
  }
  for nested in namespace_.module_.namespaces {
    if namespace_has_non_type_members(nested) {
      return true
    }
  }
  false
}

///|
fn value_decl_has_runtime_binding(value : @ast.TsValueDecl) -> Bool {
  match value.type_ {
    // `.d.ts` files use `Symbol` / `unique symbol` for marker keys that
    // often do not exist as runtime exports. Both variants are treated
    // as non-runtime here.
    Symbol | UniqueSymbol(_) => false
    _ => true
  }
}

///|
fn resolved_export_is_non_runtime_value(
  export_ : ResolvedExport,
  modules : Map[String, DeclModuleInfo],
) -> Bool {
  let local_name = match export_.local_name {
    Some(local_name) => local_name
    None => return false
  }
  match modules.get(export_.source_path) {
    Some(info) =>
      match find_value_decl(info.module_, local_name) {
        Some(value) => !value_decl_has_runtime_binding(value)
        None =>
          match find_type_alias_decl(info.module_, local_name) {
            Some(_) => true
            None => false
          }
      }
    None => false
  }
}

///|
fn append_exported_namespace_members_with_prefix(
  source_path : String,
  runtime_prefix : String,
  local_name_prefix : String,
  type_export_prefix : String,
  value_export_prefix : String,
  namespace_ : @ast.TsNamespaceDecl,
  interfaces : Array[ExportedInterfaceDecl],
  enums : Array[ExportedEnumDecl],
  imports : Array[ExportedImportDecl],
  funcs : Array[ExportedFuncDecl],
  values : Array[ExportedValueDecl],
  classes : Array[ExportedClassDecl],
) -> Unit {
  let nested_namespace_names : Array[String] = []
  for nested in namespace_.module_.namespaces {
    nested_namespace_names.push(nested.name)
  }
  for iface in namespace_.module_.interfaces {
    interfaces.push({
      source_path,
      local_name: namespace_local_export_name(local_name_prefix, iface.name),
      export_name: namespace_type_export_name(type_export_prefix, iface.name),
      iface,
    })
  }
  for enum_ in namespace_.module_.enums {
    enums.push({
      source_path,
      local_name: namespace_local_export_name(local_name_prefix, enum_.name),
      export_name: namespace_type_export_name(type_export_prefix, enum_.name),
      enum_,
    })
  }
  for import_ in namespace_.module_.imports {
    imports.push({
      source_path,
      local_name_prefix,
      export_name: namespace_value_export_name(
        value_export_prefix,
        import_.name,
      ),
      source_export_name: namespace_member_runtime_export_name(
        runtime_prefix,
        import_.name,
      ),
      import_,
    })
  }
  for func in namespace_.module_.funcs {
    funcs.push({
      source_path,
      local_name_prefix,
      export_name: namespace_value_export_name(value_export_prefix, func.name),
      source_export_name: namespace_member_runtime_export_name(
        runtime_prefix,
        func.name,
      ),
      func,
    })
  }
  for value in namespace_.module_.values {
    if nested_namespace_names.contains(value.name) {
      continue
    }
    if !value_decl_has_runtime_binding(value) {
      continue
    }
    values.push({
      source_path,
      local_name_prefix,
      export_name: namespace_value_export_name(value_export_prefix, value.name),
      source_export_name: namespace_member_runtime_export_name(
        runtime_prefix,
        value.name,
      ),
      value,
    })
  }
  for class_ in namespace_.module_.classes {
    classes.push({
      source_path,
      local_name: namespace_local_export_name(local_name_prefix, class_.name),
      local_name_prefix,
      export_name: namespace_type_export_name(type_export_prefix, class_.name),
      source_export_name: namespace_member_runtime_export_name(
        runtime_prefix,
        class_.name,
      ),
      class_,
    })
  }
  for nested in namespace_.module_.namespaces {
    append_exported_namespace_members_with_prefix(
      source_path,
      namespace_member_runtime_export_name(runtime_prefix, nested.name),
      namespace_local_export_name(local_name_prefix, nested.name + "."),
      namespace_next_type_export_prefix(type_export_prefix, nested.name),
      namespace_next_value_export_prefix(value_export_prefix, nested.name),
      nested,
      interfaces,
      enums,
      imports,
      funcs,
      values,
      classes,
    )
  }
}

///|
fn append_exported_namespace_members(
  source_path : String,
  runtime_root_export_name : String,
  namespace_ : @ast.TsNamespaceDecl,
  interfaces : Array[ExportedInterfaceDecl],
  enums : Array[ExportedEnumDecl],
  imports : Array[ExportedImportDecl],
  funcs : Array[ExportedFuncDecl],
  values : Array[ExportedValueDecl],
  classes : Array[ExportedClassDecl],
) -> Unit {
  append_exported_namespace_members_with_prefix(
    source_path, runtime_root_export_name, "", "", "", namespace_, interfaces, enums,
    imports, funcs, values, classes,
  )
}

///|
fn exported_local_namespace_decl(
  export_ : ResolvedExport,
  modules : Map[String, DeclModuleInfo],
) -> @ast.TsNamespaceDecl? {
  let local_name = match export_.local_name {
    Some(local_name) => local_name
    None => return None
  }
  match modules.get(export_.source_path) {
    Some(info) => find_namespace_decl(info.module_, local_name)
    None => None
  }
}

///|
fn find_resolved_export_by_name(
  exports : Array[ResolvedExport],
  export_name : String,
) -> ResolvedExport? {
  for export_ in exports {
    if export_.export_name == export_name {
      return Some(export_)
    }
  }
  None
}

///|
fn get_export_surface_for_path(
  path : String,
  graph : ModuleGraph,
  surface_cache : Map[String, Array[ResolvedExport]],
) -> Array[ResolvedExport] {
  match surface_cache.get(path) {
    Some(exports) => exports
    None => {
      let exports = resolve_export_surface({
        entry_path: path,
        modules: graph.modules,
      })
      surface_cache[path] = exports
      exports
    }
  }
}

///|
fn resolve_decl_from_export_name(
  export_name : String,
  path : String,
  target_export_name : String,
  graph : ModuleGraph,
  modules : Map[String, DeclModuleInfo],
  surface_cache : Map[String, Array[ResolvedExport]],
  visiting : Array[String],
) -> ResolvedDecl {
  let exports = get_export_surface_for_path(path, graph, surface_cache)
  match find_resolved_export_by_name(exports, target_export_name) {
    Some(export_) =>
      match export_.kind {
        Ambiguous =>
          Unsupported(
            export_name,
            decl_ambiguous_export_reason(
              export_, "ambiguous re-export surface is widened to JSValue",
            ),
          )
        Namespace =>
          Unsupported(export_name, "namespace export is widened to JSValue.")
        _ =>
          match export_.local_name {
            Some(local_name) =>
              resolve_decl_from_local_name(
                export_name,
                export_.source_path,
                local_name,
                export_.source_export_name,
                graph,
                modules,
                surface_cache,
                visiting,
              )
            None => Missing
          }
      }
    None => Missing
  }
}

///|
fn resolve_decl_from_local_name(
  export_name : String,
  source_path : String,
  local_name : String,
  source_export_name : String,
  graph : ModuleGraph,
  modules : Map[String, DeclModuleInfo],
  surface_cache : Map[String, Array[ResolvedExport]],
  visiting : Array[String],
) -> ResolvedDecl {
  let key = decl_key(source_path, local_name)
  if visiting.contains(key) {
    return Missing
  }
  visiting.push(key)
  let result = match modules.get(source_path) {
    Some(info) =>
      match find_interface_decl(info.module_, local_name) {
        Some(iface) =>
          Interface({ source_path, local_name, export_name, iface })
        None =>
          match find_enum_decl(info.module_, local_name) {
            Some(enum_) =>
              match enum_decl_unsupported_reason(enum_) {
                Some(reason) => Unsupported(export_name, reason)
                None => Enum({ source_path, local_name, export_name, enum_ })
              }
            None =>
              match find_type_alias_decl(info.module_, local_name) {
                Some(type_alias) => {
                  // Pre-lower the alias body so template literal types and
                  // string-mapping intrinsics (`Capitalize<X>` etc.) get a
                  // chance to enumerate before enum lowering inspects the
                  // alias for a closed string-literal union. Canonical
                  // type names are not yet known at this resolve step;
                  // pass an empty map so the lower path falls back to the
                  // raw alias names.
                  let canonical_types_for_lower : Map[String, String] = {}
                  let lowered_alias_type = lower_react_utility_type(
                    info,
                    type_alias.type_,
                    modules,
                    canonical_types_for_lower,
                  )
                  let lowered_alias : @ast.TsTypeAlias = {
                    ..type_alias,
                    type_: lowered_alias_type,
                  }
                  match enum_lowering_type_alias_enum_decl(lowered_alias) {
                    Some(enum_) =>
                      Enum({ source_path, local_name, export_name, enum_ })
                    None =>
                      match tagged_union_type_alias_decl(lowered_alias) {
                        Some(decl) =>
                          TaggedUnion({
                            source_path,
                            local_name,
                            export_name,
                            decl,
                          })
                        None =>
                          match
                            tagged_union_widen_reason_for_alias(lowered_alias) {
                            Some(reason) => Unsupported(export_name, reason)
                            None =>
                              match
                                type_alias_enum_like_unsupported_reason(
                                  lowered_alias,
                                ) {
                                Some(reason) => Unsupported(export_name, reason)
                                None =>
                                  // After lowering (`{ [K in keyof Foo]: V }`
                                  // and similar partial-evaluations), an alias
                                  // body may collapse to a concrete object with
                                  // literal keys. Surface it as a synthetic
                                  // interface so emit produces a `pub(all)
                                  // struct` rather than dropping the alias as
                                  // `Missing` / `declare pub type X`. Also try
                                  // the original (pre-lowering) body for
                                  // utility instantiations like `Pick<Foo, K>`
                                  // since those reduce to a `Named(...)` whose
                                  // synthetic interface isn't reachable from
                                  // the lowered alias body alone.
                                  match
                                    type_alias_object_to_interface(
                                      lowered_alias,
                                    ) {
                                    Some(iface) =>
                                      Interface({
                                        source_path,
                                        local_name,
                                        export_name,
                                        iface,
                                      })
                                    None =>
                                      match
                                        type_alias_utility_to_interface(
                                          info, type_alias, modules, canonical_types_for_lower,
                                        ) {
                                        Some(iface) =>
                                          Interface({
                                            source_path,
                                            local_name,
                                            export_name,
                                            iface,
                                          })
                                        None =>
                                          if type_alias_passthrough_supported(
                                              lowered_alias,
                                            ) {
                                            TypeAlias({
                                              source_path,
                                              export_name,
                                              type_alias: lowered_alias,
                                            })
                                          } else {
                                            Missing
                                          }
                                      }
                                  }
                              }
                          }
                      }
                  }
                }
                None =>
                  match find_import_decl(info.module_, local_name) {
                    Some(import_) =>
                      Import({
                        source_path,
                        local_name_prefix: "",
                        export_name,
                        source_export_name,
                        import_,
                      })
                    None => {
                      let stmt_func = find_func_decl_from_stmts(
                        info.record.module_block.block.stmts,
                        local_name,
                      )
                      match find_func_decl(info.module_, local_name) {
                        Some(func) =>
                          Function({
                            source_path,
                            local_name_prefix: "",
                            export_name,
                            source_export_name,
                            func,
                          })
                        None =>
                          match stmt_func {
                            Some(func) =>
                              Function({
                                source_path,
                                local_name_prefix: "",
                                export_name,
                                source_export_name,
                                func,
                              })
                            None =>
                              // TS declaration merging: when both a class and
                              // a namespace declare the same name, the class
                              // is the load-bearing surface (instance shape +
                              // generics) and the namespace contributes a
                              // value-side `name` binding with type `Any`.
                              // Resolve the class first so the bridge keeps
                              // `class Foo<T>` methods/generics; otherwise the
                              // namespace's `Any`-typed value would shadow
                              // it as a runtime-only export.
                              match find_class_decl(info.module_, local_name) {
                                Some(class_) =>
                                  Class({
                                    source_path,
                                    local_name,
                                    local_name_prefix: "",
                                    export_name,
                                    source_export_name,
                                    class_,
                                  })
                                None =>
                                  match
                                    find_value_decl(info.module_, local_name) {
                                    Some(value) =>
                                      if value_decl_has_runtime_binding(value) {
                                        Value({
                                          source_path,
                                          local_name_prefix: "",
                                          export_name,
                                          source_export_name,
                                          value,
                                        })
                                      } else {
                                        Missing
                                      }
                                    None => {
                                      let mut resolved : ResolvedDecl = Missing
                                      for
                                        i, import_decl in info.record.module_block.imports {
                                        let edge = info.record.imports[i]
                                        if edge.resolved_path == "" {
                                          continue
                                        }
                                        for
                                          binding in import_decl.named_bindings {
                                          let (
                                            imported_name,
                                            imported_local_name,
                                          ) = binding
                                          if imported_local_name == local_name {
                                            resolved = resolve_decl_from_export_name(
                                              export_name,
                                              edge.resolved_path,
                                              imported_name,
                                              graph,
                                              modules,
                                              surface_cache,
                                              visiting,
                                            )
                                            break
                                          }
                                        }
                                        match resolved {
                                          Missing => ()
                                          _ => break
                                        }
                                        match import_decl.default_binding {
                                          Some(imported_local_name) =>
                                            if imported_local_name == local_name {
                                              resolved = resolve_decl_from_export_name(
                                                export_name,
                                                edge.resolved_path,
                                                "default",
                                                graph,
                                                modules,
                                                surface_cache,
                                                visiting,
                                              )
                                            }
                                          None => ()
                                        }
                                        match resolved {
                                          Missing => ()
                                          _ => break
                                        }
                                        match import_decl.namespace_binding {
                                          Some(imported_local_name) =>
                                            if imported_local_name == local_name {
                                              resolved = Value({
                                                source_path,
                                                local_name_prefix: "",
                                                export_name,
                                                source_export_name,
                                                value: {
                                                  name: local_name,
                                                  type_: @ast.TsType::Any,
                                                },
                                              })
                                            }
                                          None => ()
                                        }
                                        match resolved {
                                          Missing => ()
                                          _ => break
                                        }
                                      }
                                      resolved
                                    }
                                  }
                              }
                          }
                      }
                    }
                  }
              }
          }
      }
    None => Missing
  }
  let _ = visiting.pop()
  result
}

///|
fn collect_exported_decls(
  graph : ModuleGraph,
  export_surface : Array[ResolvedExport],
  modules : Map[String, DeclModuleInfo],
) -> (
  Array[ExportedInterfaceDecl],
  Array[ExportedEnumDecl],
  Array[ExportedTaggedUnionDecl],
  Array[ExportedTypeAliasDecl],
  Array[ExportedImportDecl],
  Array[ExportedFuncDecl],
  Array[ExportedValueDecl],
  Array[ExportedClassDecl],
  Array[String],
) {
  let interfaces : Array[ExportedInterfaceDecl] = []
  let enums : Array[ExportedEnumDecl] = []
  let tagged_unions : Array[ExportedTaggedUnionDecl] = []
  let type_aliases : Array[ExportedTypeAliasDecl] = []
  let imports : Array[ExportedImportDecl] = []
  let funcs : Array[ExportedFuncDecl] = []
  let values : Array[ExportedValueDecl] = []
  let classes : Array[ExportedClassDecl] = []
  let notes : Array[String] = []
  let surface_cache : Map[String, Array[ResolvedExport]] = {}
  for export_ in export_surface {
    match export_.kind {
      Namespace => {
        match exported_local_namespace_decl(export_, modules) {
          Some(namespace_) => {
            append_exported_type_namespace_members_with_prefix(
              export_.source_path,
              export_.export_name + ".",
              decl_to_pascal_case(export_.export_name),
              namespace_,
              interfaces,
              enums,
            )
            if namespace_has_non_type_members(namespace_) {
              notes.push(
                "///|\n/// Unsupported export \{export_.export_name}: runtime members inside exported namespace are omitted; only type members are exposed.",
              )
            }
          }
          None =>
            notes.push(
              "///|\n/// Unsupported export \{export_.export_name}: namespace export is widened to JSValue.",
            )
        }
        continue
      }
      Ambiguous => {
        let reason = decl_ambiguous_export_reason(
          export_, "ambiguous re-export surface is widened to JSValue",
        )
        notes.push(
          "///|\n/// Unsupported export \{export_.export_name}: \{reason}",
        )
        continue
      }
      _ => ()
    }
    let local_name = match export_.local_name {
      Some(local_name) => local_name
      None => continue
    }
    match exported_local_namespace_decl(export_, modules) {
      Some(namespace_) if export_.export_name != "default" => {
        let has_runtime_root = match modules.get(export_.source_path) {
          Some(info) =>
            module_has_non_namespace_runtime_decl(info.module_, local_name)
          None => false
        }
        if namespace_has_non_type_members(namespace_) {
          append_exported_namespace_members_with_prefix(
            export_.source_path,
            export_.source_export_name,
            export_.export_name + ".",
            decl_to_pascal_case(export_.export_name),
            decl_to_camel_case(export_.export_name),
            namespace_,
            interfaces,
            enums,
            imports,
            funcs,
            values,
            classes,
          )
        } else {
          append_exported_type_namespace_members_with_prefix(
            export_.source_path,
            export_.export_name + ".",
            decl_to_pascal_case(export_.export_name),
            namespace_,
            interfaces,
            enums,
          )
        }
        if has_runtime_root {
          ()
        } else {
          continue
        }
      }
      _ => ()
    }
    if export_.export_name == "default" {
      match modules.get(export_.source_path) {
        Some(info) =>
          match find_namespace_decl(info.module_, local_name) {
            Some(namespace_) =>
              append_exported_namespace_members(
                export_.source_path,
                export_.export_name,
                namespace_,
                interfaces,
                enums,
                imports,
                funcs,
                values,
                classes,
              )
            None => ()
          }
        None => ()
      }
    }
    let visiting : Array[String] = []
    match
      resolve_decl_from_local_name(
        export_.export_name,
        export_.source_path,
        local_name,
        export_.source_export_name,
        graph,
        modules,
        surface_cache,
        visiting,
      ) {
      Interface(exported) => interfaces.push(exported)
      Enum(exported) => enums.push(exported)
      TaggedUnion(exported) => tagged_unions.push(exported)
      TypeAlias(exported) => type_aliases.push(exported)
      Import(exported) => imports.push(exported)
      Function(exported) => funcs.push(exported)
      Value(exported) => values.push(exported)
      Class(exported) =>
        if export_.type_only {
          let properties : Array[@ast.TsClassPropertyDecl] = []
          for property in exported.class_.properties {
            if !property.is_static {
              properties.push(property)
            }
          }
          let methods : Array[@ast.TsClassMethodDecl] = []
          for class_method in exported.class_.methods {
            if !class_method.is_static {
              methods.push(class_method)
            }
          }
          classes.push({
            ..exported,
            class_: {
              ..exported.class_,
              constructor_params: None,
              properties,
              methods,
              is_constructible: false,
              index_signatures: [],
              decorators: [],
            },
          })
        } else {
          classes.push(exported)
        }
      Unsupported(name, reason) =>
        notes.push("///|\n/// Unsupported export \{name}: \{reason}")
      Missing => ()
    }
  }
  (
    interfaces, enums, tagged_unions, type_aliases, imports, funcs, values, classes,
    notes,
  )
}

///|
fn build_canonical_type_name_map(
  interfaces : Array[ExportedInterfaceDecl],
  enums : Array[ExportedEnumDecl],
  classes : Array[ExportedClassDecl],
) -> Map[String, String] {
  let canonical : Map[String, String] = {}
  for exported in interfaces {
    let key = decl_key(exported.source_path, exported.local_name)
    match canonical.get(key) {
      Some(existing) =>
        if existing != exported.local_name &&
          exported.export_name == exported.local_name {
          canonical[key] = exported.export_name
        }
      None => canonical[key] = exported.export_name
    }
  }
  for exported in enums {
    let key = decl_key(exported.source_path, exported.local_name)
    match canonical.get(key) {
      Some(existing) =>
        if existing != exported.local_name &&
          exported.export_name == exported.local_name {
          canonical[key] = exported.export_name
        }
      None => canonical[key] = exported.export_name
    }
  }
  for exported in classes {
    let key = decl_key(exported.source_path, exported.local_name)
    match canonical.get(key) {
      Some(existing) =>
        if existing != exported.local_name &&
          exported.export_name == exported.local_name {
          canonical[key] = exported.export_name
        }
      None => canonical[key] = exported.export_name
    }
  }
  canonical
}

///|
fn resolve_imported_type_origin(
  info : DeclModuleInfo,
  name : String,
) -> (String, String)? {
  for i, import_decl in info.record.module_block.imports {
    let resolved_edge = info.record.imports[i]
    for binding in import_decl.named_bindings {
      let (imported_name, local_name) = binding
      if local_name == name {
        return Some((resolved_edge.resolved_path, imported_name))
      }
    }
    match import_decl.default_binding {
      Some(local_name) =>
        if local_name == name {
          return Some((resolved_edge.resolved_path, "default"))
        }
      None => ()
    }
  }
  None
}

///|
fn resolve_exported_type_name(
  info : DeclModuleInfo,
  name : String,
  canonical_types : Map[String, String],
) -> String? {
  let local_key = decl_key(info.record.path, name)
  match canonical_types.get(local_key) {
    Some(export_name) => return Some(export_name)
    None => ()
  }
  match resolve_imported_type_origin(info, name) {
    Some((source_path, imported_name)) =>
      canonical_types.get(decl_key(source_path, imported_name))
    None => None
  }
}

///|
fn resolve_exported_type_name_in_scope(
  info : DeclModuleInfo,
  local_name_prefix : String,
  name : String,
  canonical_types : Map[String, String],
) -> String? {
  if local_name_prefix != "" {
    match
      canonical_types.get(decl_key(info.record.path, local_name_prefix + name)) {
      Some(export_name) => return Some(export_name)
      None => ()
    }
  }
  resolve_exported_type_name(info, name, canonical_types)
}

///|
fn resolve_interface_origin(
  info : DeclModuleInfo,
  name : String,
  modules : Map[String, DeclModuleInfo],
  canonical_types : Map[String, String],
) -> ResolvedInterfaceOrigin? {
  match find_interface_decl_recursive(info.module_, name) {
    Some(iface) =>
      Some({
        info,
        export_name: match
          resolve_exported_type_name(info, name, canonical_types) {
          Some(export_name) => export_name
          None => name
        },
        iface,
      })
    None =>
      match resolve_imported_type_origin(info, name) {
        Some((source_path, imported_name)) =>
          match modules.get(source_path) {
            Some(source_info) =>
              match
                find_interface_decl_recursive(
                  source_info.module_,
                  imported_name,
                ) {
                Some(iface) =>
                  Some({
                    info: source_info,
                    export_name: match
                      resolve_exported_type_name(
                        source_info, imported_name, canonical_types,
                      ) {
                      Some(export_name) => export_name
                      None => imported_name
                    },
                    iface,
                  })
                None => None
              }
            None => None
          }
        None => None
      }
  }
}

///|
fn resolved_class_origin_from_exported(
  exported : ExportedClassDecl,
  modules : Map[String, DeclModuleInfo],
) -> ResolvedClassOrigin? {
  match modules.get(exported.source_path) {
    Some(info) =>
      Some({
        info,
        local_name_prefix: exported.local_name_prefix,
        class_: exported.class_,
      })
    None => None
  }
}

///|
fn resolve_class_origin_from_export_name(
  name : String,
  source_path : String,
  imported_name : String,
  graph : ModuleGraph,
  modules : Map[String, DeclModuleInfo],
  surface_cache : Map[String, Array[ResolvedExport]],
) -> ResolvedClassOrigin? {
  let visiting : Array[String] = []
  match
    resolve_decl_from_export_name(
      name, source_path, imported_name, graph, modules, surface_cache, visiting,
    ) {
    Class(exported) => resolved_class_origin_from_exported(exported, modules)
    _ => None
  }
}

///|
fn resolve_class_origin(
  info : DeclModuleInfo,
  name : String,
  graph : ModuleGraph,
  modules : Map[String, DeclModuleInfo],
  surface_cache : Map[String, Array[ResolvedExport]],
) -> ResolvedClassOrigin? {
  match find_class_decl_recursive(info.module_, name) {
    Some(class_) => Some({ info, local_name_prefix: "", class_ })
    None =>
      match resolve_imported_type_origin(info, name) {
        Some((source_path, imported_name)) =>
          match modules.get(source_path) {
            Some(source_info) =>
              match
                find_class_decl_recursive(source_info.module_, imported_name) {
                Some(class_) =>
                  Some({ info: source_info, local_name_prefix: "", class_ })
                None =>
                  resolve_class_origin_from_export_name(
                    name, source_path, imported_name, graph, modules, surface_cache,
                  )
              }
            None => None
          }
        None =>
          resolve_class_origin_from_export_name(
            name,
            info.record.path,
            name,
            graph,
            modules,
            surface_cache,
          )
      }
  }
}

///|
fn props_with_children_interface_name(base_name : String) -> String {
  base_name + "WithChildren"
}

///|
fn component_props_with_ref_interface_name(base_name : String) -> String {
  base_name + "WithRef"
}

// Alias-name predicates moved to `mizchi/ts/checker`. Bridge code calls
// `@checker.is_*` directly.

///|
// Resolve a single `T[K]` indexed-access type to the matching field type when
// T is a concrete interface and K is a literal property name. Returns None
// for any case the resolver cannot decide on (generic T, computed K, etc.),
// letting the caller fall back to widening.

///|
/// Walk `type_` and replace any nested `IndexedAccess(target, key)` whose
/// base resolves to the same interface as `cycle_base` and whose key
/// matches `cycle_key` with `Any`. Used to break self-referential
/// indexed-access cycles before recursing through the resolved field
/// type — drizzle's `BuildRelationalQueryResult<TTable>['selection']`
/// references its own `selection` field deep inside an `Array<Object>`
/// so the recursion needs to short-circuit at every depth, not just at
/// the immediate level.
fn strip_self_indexed_access(
  type_ : @ast.TsType,
  cycle_base : @ast.TsType,
  cycle_key : @ast.TsType,
) -> @ast.TsType {
  match type_ {
    @ast.TsType::IndexedAccess(b, k) =>
      if indexed_access_targets_match(cycle_base, b) && cycle_key == k {
        @ast.TsType::Any
      } else {
        @ast.TsType::IndexedAccess(
          strip_self_indexed_access(b, cycle_base, cycle_key),
          strip_self_indexed_access(k, cycle_base, cycle_key),
        )
      }
    @ast.TsType::Array(inner) =>
      @ast.TsType::Array(
        strip_self_indexed_access(inner, cycle_base, cycle_key),
      )
    @ast.TsType::Tuple(items) => {
      let out : Array[@ast.TsType] = []
      for it in items {
        out.push(strip_self_indexed_access(it, cycle_base, cycle_key))
      }
      @ast.TsType::Tuple(out)
    }
    @ast.TsType::Object(fields) => {
      let out : Array[(@ast.TsType, @ast.TsType)] = []
      for f in fields {
        out.push(
          (
            strip_self_indexed_access(f.0, cycle_base, cycle_key),
            strip_self_indexed_access(f.1, cycle_base, cycle_key),
          ),
        )
      }
      @ast.TsType::Object(out)
    }
    @ast.TsType::Func(params, ret) => {
      let new_params : Array[@ast.TsType] = []
      for p in params {
        new_params.push(strip_self_indexed_access(p, cycle_base, cycle_key))
      }
      @ast.TsType::Func(
        new_params,
        strip_self_indexed_access(ret, cycle_base, cycle_key),
      )
    }
    @ast.TsType::Union(items) => {
      let out : Array[@ast.TsType] = []
      for it in items {
        out.push(strip_self_indexed_access(it, cycle_base, cycle_key))
      }
      @ast.TsType::Union(out)
    }
    @ast.TsType::Intersection(items) => {
      let out : Array[@ast.TsType] = []
      for it in items {
        out.push(strip_self_indexed_access(it, cycle_base, cycle_key))
      }
      @ast.TsType::Intersection(out)
    }
    @ast.TsType::Applied(name, args) => {
      let out : Array[@ast.TsType] = []
      for a in args {
        out.push(strip_self_indexed_access(a, cycle_base, cycle_key))
      }
      @ast.TsType::Applied(name, out)
    }
    @ast.TsType::Conditional(check, ext, t, f) =>
      @ast.TsType::Conditional(
        strip_self_indexed_access(check, cycle_base, cycle_key),
        strip_self_indexed_access(ext, cycle_base, cycle_key),
        strip_self_indexed_access(t, cycle_base, cycle_key),
        strip_self_indexed_access(f, cycle_base, cycle_key),
      )
    _ => type_
  }
}

///|
/// Compare two `IndexedAccess` base targets ignoring the `Applied` type
/// arguments — `Foo['selection']` and `Foo<T>['selection']` reference the
/// same field on the same interface for cycle-detection purposes.
fn indexed_access_targets_match(a : @ast.TsType, b : @ast.TsType) -> Bool {
  let name_a = match a {
    @ast.TsType::Named(n) => Some(n)
    @ast.TsType::Applied(n, _) => Some(n)
    _ => None
  }
  let name_b = match b {
    @ast.TsType::Named(n) => Some(n)
    @ast.TsType::Applied(n, _) => Some(n)
    _ => None
  }
  match (name_a, name_b) {
    (Some(x), Some(y)) => x == y
    _ => false
  }
}

///|
fn resolve_indexed_access(
  info : DeclModuleInfo,
  base : @ast.TsType,
  key : @ast.TsType,
  modules : Map[String, DeclModuleInfo],
  canonical_types : Map[String, String],
) -> @ast.TsType? {
  let key_name = match key {
    Literal(name) => name
    _ => return None
  }
  let type_name = match base {
    Named(name) => name
    Applied(name, _) => name
    _ => return None
  }
  match resolve_interface_origin(info, type_name, modules, canonical_types) {
    Some(origin) => {
      for field in origin.iface.fields {
        let (field_name, field_type) = field
        if field_name == key_name {
          return Some(field_type)
        }
      }
      None
    }
    None => None
  }
}

///|
fn props_with_children_object_interface_name(
  fields : Array[(@ast.TsType, @ast.TsType)],
) -> String {
  let mut prefix = ""
  for field in fields {
    let (key_type, _) = field
    match key_type {
      Literal(name) => prefix += decl_to_pascal_case(name)
      _ => ()
    }
  }
  if prefix == "" {
    "InlinePropsWithChildren"
  } else {
    prefix + "PropsWithChildren"
  }
}

///|
fn resolve_react_ref_type_name(
  info : DeclModuleInfo,
  canonical_types : Map[String, String],
) -> String {
  match resolve_exported_type_name(info, "Ref", canonical_types) {
    Some(name) => name
    None => "Ref"
  }
}

///|
fn props_with_children_named_interface_spec(
  info : DeclModuleInfo,
  name : String,
  modules : Map[String, DeclModuleInfo],
  canonical_types : Map[String, String],
) -> @ast.TsInterface? {
  match resolve_interface_origin(info, name, modules, canonical_types) {
    Some(origin) => {
      let fields : Array[(String, @ast.TsType)] = []
      for field in origin.iface.fields {
        let (field_name, field_type) = field
        fields.push(
          (
            field_name,
            lower_react_utility_type(
              origin.info,
              rewrite_type_refs(origin.info, field_type, canonical_types),
              modules,
              canonical_types,
            ),
          ),
        )
      }
      if !fields.iter().any(fn(field) { field.0 == "children" }) {
        fields.push(("children", Any))
      }
      Some({
        name: props_with_children_interface_name(origin.export_name),
        type_params: [],
        extends_names: [],
        extends_args: [],
        fields,
        readonly_fields: readonly_fields_for_fields(
          origin.iface.readonly_fields,
          fields,
        ),
        index_signatures: origin.iface.index_signatures,
      })
    }
    None => None
  }
}

///|
fn props_with_children_interface_spec(
  info : DeclModuleInfo,
  inner_type : @ast.TsType,
  modules : Map[String, DeclModuleInfo],
  canonical_types : Map[String, String],
) -> @ast.TsInterface? {
  match inner_type {
    Named(name) =>
      props_with_children_named_interface_spec(
        info, name, modules, canonical_types,
      )
    Object(inner_fields) => {
      let fields : Array[(String, @ast.TsType)] = []
      for field in inner_fields {
        let (key_type, field_type) = field
        match key_type {
          Literal(field_name) =>
            fields.push(
              (
                field_name,
                lower_react_utility_type(
                  info,
                  rewrite_type_refs(info, field_type, canonical_types),
                  modules,
                  canonical_types,
                ),
              ),
            )
          _ => return None
        }
      }
      if !fields.iter().any(fn(field) { field.0 == "children" }) {
        fields.push(("children", Any))
      }
      Some({
        name: props_with_children_object_interface_name(inner_fields),
        type_params: [],
        extends_names: [],
        extends_args: [],
        fields,
        readonly_fields: [],
        index_signatures: [],
      })
    }
    _ =>
      match
        lower_react_utility_type(info, inner_type, modules, canonical_types) {
        Named(name) =>
          props_with_children_named_interface_spec(
            info, name, modules, canonical_types,
          )
        _ => None
      }
  }
}

///|
fn component_props_resolved_type(
  info : DeclModuleInfo,
  inner_type : @ast.TsType,
  modules : Map[String, DeclModuleInfo],
  canonical_types : Map[String, String],
) -> @ast.TsType? {
  match inner_type {
    Literal(name) =>
      match find_jsx_intrinsic_elements_decl(info.module_) {
        Some(iface) => {
          for field in iface.fields {
            let (field_name, field_type) = field
            if field_name == name {
              return Some(
                lower_react_utility_type(
                  info,
                  rewrite_type_refs(info, field_type, canonical_types),
                  modules,
                  canonical_types,
                ),
              )
            }
          }
          None
        }
        None => None
      }
    _ => None
  }
}

///|
fn component_props_with_ref_interface_spec(
  info : DeclModuleInfo,
  inner_type : @ast.TsType,
  modules : Map[String, DeclModuleInfo],
  canonical_types : Map[String, String],
) -> @ast.TsInterface? {
  match
    component_props_resolved_type(info, inner_type, modules, canonical_types) {
    Some(Named(name)) =>
      match resolve_interface_origin(info, name, modules, canonical_types) {
        Some(origin) => {
          let fields : Array[(String, @ast.TsType)] = []
          for field in origin.iface.fields {
            let (field_name, field_type) = field
            fields.push(
              (
                field_name,
                lower_react_utility_type(
                  origin.info,
                  rewrite_type_refs(origin.info, field_type, canonical_types),
                  modules,
                  canonical_types,
                ),
              ),
            )
          }
          if !fields.iter().any(fn(field) { field.0 == "ref" }) {
            match
              resolve_interface_origin(
                info, "RefAttributes", modules, canonical_types,
              ) {
              Some(ref_origin) =>
                for field in ref_origin.iface.fields {
                  let (field_name, field_type) = field
                  if field_name == "ref" {
                    fields.push(
                      (
                        "ref",
                        lower_react_utility_type(
                          ref_origin.info,
                          rewrite_type_refs(
                            ref_origin.info,
                            field_type,
                            canonical_types,
                          ),
                          modules,
                          canonical_types,
                        ),
                      ),
                    )
                    break
                  }
                }
              None => ()
            }
          }
          Some({
            name: component_props_with_ref_interface_name(origin.export_name),
            type_params: [],
            extends_names: [],
            extends_args: [],
            fields,
            readonly_fields: readonly_fields_for_fields(
              origin.iface.readonly_fields,
              fields,
            ),
            index_signatures: origin.iface.index_signatures,
          })
        }
        None => None
      }
    _ => None
  }
}

///|
fn is_component_props_like_name(name : String) -> Bool {
  name == "ComponentProps" || name == "ComponentPropsWithoutRef"
}

///|
fn utility_literal_key_names(type_ : @ast.TsType) -> Array[String]? {
  match type_ {
    Literal(name) => Some([name])
    Union(items) => {
      let names : Array[String] = []
      for item in items {
        match item {
          Literal(name) => names.push(name)
          _ => return None
        }
      }
      Some(names)
    }
    _ => None
  }
}

///|
fn utility_source_type_name(type_ : @ast.TsType) -> String? {
  match type_ {
    Named(name) => Some(name)
    _ => None
  }
}

///|
fn utility_projection_interface_name(
  base_name : String,
  op_name : String,
  keys : Array[String],
) -> String {
  let mut suffix = ""
  for key in keys {
    suffix += decl_to_pascal_case(key)
  }
  if suffix == "" {
    suffix = "Empty"
  }
  base_name + op_name + suffix
}

///|
fn utility_mapped_interface_name(
  base_name : String,
  op_name : String,
) -> String {
  base_name + op_name
}

///|
fn readonly_fields_for_fields(
  source_readonly_fields : Array[String],
  fields : Array[(String, @ast.TsType)],
) -> Array[String] {
  let readonly_fields : Array[String] = []
  for field in fields {
    let (field_name, _) = field
    if source_readonly_fields.contains(field_name) &&
      !readonly_fields.contains(field_name) {
      readonly_fields.push(field_name)
    }
  }
  readonly_fields
}

///|
fn all_field_names(fields : Array[(String, @ast.TsType)]) -> Array[String] {
  let names : Array[String] = []
  for field in fields {
    let (field_name, _) = field
    if !names.contains(field_name) {
      names.push(field_name)
    }
  }
  names
}

///|
fn utility_optional_type(type_ : @ast.TsType) -> @ast.TsType {
  match @checker.classify_optional_like_union(type_) {
    Some(_) => type_
    None => Union([type_, Undefined])
  }
}

///|
fn utility_required_type(type_ : @ast.TsType) -> @ast.TsType {
  match @checker.classify_optional_like_union(type_) {
    Some((inner, _)) => inner
    None => type_
  }
}

///|
fn utility_mapped_field_type(
  op_name : String,
  type_ : @ast.TsType,
) -> @ast.TsType {
  match op_name {
    "Partial" => utility_optional_type(type_)
    "Required" => utility_required_type(type_)
    "Readonly" => type_
    _ => type_
  }
}

///|
fn utility_mapped_interface_spec(
  info : DeclModuleInfo,
  op_name : String,
  source_type : @ast.TsType,
  modules : Map[String, DeclModuleInfo],
  canonical_types : Map[String, String],
) -> @ast.TsInterface? {
  let source_name = match utility_source_type_name(source_type) {
    Some(name) => name
    None => return None
  }
  match resolve_interface_origin(info, source_name, modules, canonical_types) {
    Some(origin) => {
      let fields : Array[(String, @ast.TsType)] = []
      for field in origin.iface.fields {
        let (field_name, field_type) = field
        fields.push(
          (
            field_name,
            utility_mapped_field_type(
              op_name,
              lower_react_utility_type(
                origin.info,
                rewrite_type_refs(origin.info, field_type, canonical_types),
                modules,
                canonical_types,
              ),
            ),
          ),
        )
      }
      Some({
        name: utility_mapped_interface_name(origin.export_name, op_name),
        type_params: [],
        extends_names: [],
        extends_args: [],
        fields,
        readonly_fields: if op_name == "Readonly" {
          all_field_names(fields)
        } else {
          readonly_fields_for_fields(origin.iface.readonly_fields, fields)
        },
        index_signatures: origin.iface.index_signatures,
      })
    }
    None => None
  }
}

///|
fn utility_projection_interface_spec(
  info : DeclModuleInfo,
  op_name : String,
  source_type : @ast.TsType,
  keys_type : @ast.TsType,
  modules : Map[String, DeclModuleInfo],
  canonical_types : Map[String, String],
) -> @ast.TsInterface? {
  let source_name = match utility_source_type_name(source_type) {
    Some(name) => name
    None => return None
  }
  let keys = match utility_literal_key_names(keys_type) {
    Some(keys) => keys
    None => return None
  }
  match resolve_interface_origin(info, source_name, modules, canonical_types) {
    Some(origin) => {
      let fields : Array[(String, @ast.TsType)] = []
      for field in origin.iface.fields {
        let (field_name, field_type) = field
        let should_include = match op_name {
          "Pick" => keys.contains(field_name)
          "Omit" => !keys.contains(field_name)
          _ => false
        }
        if should_include {
          fields.push(
            (
              field_name,
              lower_react_utility_type(
                origin.info,
                rewrite_type_refs(origin.info, field_type, canonical_types),
                modules,
                canonical_types,
              ),
            ),
          )
        }
      }
      Some({
        name: utility_projection_interface_name(
          origin.export_name,
          op_name,
          keys,
        ),
        type_params: [],
        extends_names: [],
        extends_args: [],
        fields,
        readonly_fields: readonly_fields_for_fields(
          origin.iface.readonly_fields,
          fields,
        ),
        index_signatures: [],
      })
    }
    None => None
  }
}

///|
fn utility_type_list(type_ : @ast.TsType) -> Array[@ast.TsType] {
  match type_ {
    Union(items) => items
    _ => [type_]
  }
}

///|
fn utility_type_list_contains(
  items : Array[@ast.TsType],
  target : @ast.TsType,
) -> Bool {
  for item in items {
    if item == target {
      return true
    }
  }
  false
}

///|
fn utility_union_from_items(items : Array[@ast.TsType]) -> @ast.TsType? {
  if items.length() == 0 {
    None
  } else if items.length() == 1 {
    Some(items[0])
  } else {
    Some(Union(items))
  }
}

///|
fn utility_filter_union_type(
  op_name : String,
  source_type : @ast.TsType,
  filter_type : @ast.TsType,
) -> @ast.TsType? {
  let source_items = utility_type_list(source_type)
  let filter_items = utility_type_list(filter_type)
  let result : Array[@ast.TsType] = []
  for item in source_items {
    let matched = utility_type_list_contains(filter_items, item)
    match op_name {
      "Exclude" => if !matched { result.push(item) }
      "Extract" => if matched { result.push(item) }
      _ => return None
    }
  }
  utility_union_from_items(result)
}

///|
// Expand each `Named(name)` member of a Union (or the Union itself if it is
// just a single Named) once via the local module's type alias table, falling
// back to a cross-module lookup through `resolve_imported_type_origin` when
// the alias is imported. Used to crack open keys like
// `RequestHeader | CustomHeader` so subsequent simplification can fold them
// to a primitive.
fn expand_named_aliases_in_union(
  info : DeclModuleInfo,
  type_ : @ast.TsType,
  modules : Map[String, DeclModuleInfo],
  canonical_types : Map[String, String],
) -> @ast.TsType {
  fn expand_one(t : @ast.TsType) -> @ast.TsType {
    match t {
      Named(name) => {
        // Local alias first.
        match find_type_alias_decl(info.module_, name) {
          Some(ta) if ta.type_params.length() == 0 =>
            return lower_react_utility_type(
              info,
              ta.type_,
              modules,
              canonical_types,
            )
          _ => ()
        }
        // Cross-module: follow the import edge to the source module's alias.
        match resolve_imported_type_origin(info, name) {
          Some((source_path, imported_name)) =>
            match modules.get(source_path) {
              Some(source_info) =>
                match find_type_alias_decl(source_info.module_, imported_name) {
                  Some(ta) if ta.type_params.length() == 0 =>
                    lower_react_utility_type(
                      source_info,
                      ta.type_,
                      modules,
                      canonical_types,
                    )
                  _ => t
                }
              None => t
            }
          None => t
        }
      }
      _ => t
    }
  }

  match type_ {
    Union(members) => {
      let out : Array[@ast.TsType] = []
      for m in members {
        out.push(expand_one(m))
      }
      Union(out)
    }
    _ => expand_one(type_)
  }
}

///|
fn utility_record_key_suffix(type_ : @ast.TsType) -> String? {
  match type_ {
    String_ | Literal(_) => Some("String")
    Number | Int | NumberLiteral(_) => Some("Number")
    Symbol => Some("Symbol")
    Named("PropertyKey") => Some("PropertyKey")
    _ =>
      // String-literal unions collapse to "String" (e.g. hono's RequestHeader).
      if @checker.is_string_literal_union(type_) {
        Some("String")
      } else {
        // `string & {}` and similar transparent intersections; try the inner.
        match @checker.classify_transparent_intersection(type_) {
          Some(inner) => utility_record_key_suffix(inner)
          None => None
        }
      }
  }
}

///|
fn utility_record_type_suffix(type_ : @ast.TsType) -> String {
  match @checker.classify_optional_like_union(type_) {
    Some((inner, _)) => return utility_record_type_suffix(inner) + "Optional"
    None => ()
  }
  match type_ {
    Literal(value) => {
      let suffix = decl_to_pascal_case(value)
      if suffix == "" {
        "Literal"
      } else {
        suffix
      }
    }
    NumberLiteral(value) => "Number" + decl_to_pascal_case(value)
    BigIntLiteral(value) => "BigInt" + decl_to_pascal_case(value)
    BooleanLiteral(value) => if value { "True" } else { "False" }
    Number => "Double"
    Int => "Int"
    Boolean => "Bool"
    String_ => "String"
    Void => "Unit"
    BigInt => "BigInt"
    Symbol => "Symbol"
    Any => "Any"
    Never => "Never"
    Null => "Null"
    Undefined => "Undefined"
    Array(inner) => "ArrayOf" + utility_record_type_suffix(inner)
    Tuple(items) => {
      let parts : Array[String] = []
      for item in items {
        parts.push(utility_record_type_suffix(item))
      }
      "TupleOf" + parts.join("And")
    }
    Object(_) => "Object"
    Struct(name, _) | Named(name) => {
      let suffix = decl_to_pascal_case(name)
      if suffix == "" {
        "Type"
      } else {
        suffix
      }
    }
    Func(_, return_type) =>
      "FunctionTo" + utility_record_type_suffix(return_type)
    Union(items) => {
      let parts : Array[String] = []
      for item in items {
        parts.push(utility_record_type_suffix(item))
      }
      if parts.length() == 0 {
        "Union"
      } else {
        parts.join("Or")
      }
    }
    Intersection(items) => {
      let parts : Array[String] = []
      for item in items {
        parts.push(utility_record_type_suffix(item))
      }
      if parts.length() == 0 {
        "Intersection"
      } else {
        parts.join("And")
      }
    }
    Conditional(_, _, true_type, false_type) =>
      "ConditionalOf" +
      utility_record_type_suffix(true_type) +
      "Or" +
      utility_record_type_suffix(false_type)
    Applied(name, args) => {
      let prefix = {
        let suffix = decl_to_pascal_case(name)
        if suffix == "" {
          "Type"
        } else {
          suffix
        }
      }
      if args.length() == 0 {
        prefix
      } else {
        let parts : Array[String] = []
        for arg in args {
          parts.push(utility_record_type_suffix(arg))
        }
        prefix + "Of" + parts.join("And")
      }
    }
    TypeOf(query) => "TypeOf" + decl_to_pascal_case(query)
    IndexedAccess(base, key) =>
      utility_record_type_suffix(base) + "At" + utility_record_type_suffix(key)
    TemplateLiteralType(_, _) => "String"
    Keyof(inner) => "KeyOf" + utility_record_type_suffix(inner)
    MappedType(_, _, value, _) => "MappedTo" + utility_record_type_suffix(value)
    MappedTypeRemap(_, _, _, value, _) =>
      "RemapTo" + utility_record_type_suffix(value)
    TypePredicate(_, _) => "Bool"
    AssertsPredicate(_, _) => "Unit"
    // Outside a Tuple, a bare `Rest(T)` behaves like `Array(T)` for the
    // purposes of suffix naming; inside a Tuple it's handled by the
    // tuple-walker.
    Rest(inner) => "RestOf" + utility_record_type_suffix(inner)
    Constructor(_, ret, _) =>
      "CtorOf" + utility_record_type_suffix(ret)
    UniqueSymbol(_) => "Symbol"
  }
}

///|
fn utility_record_type_name(
  key_type : @ast.TsType,
  value_type : @ast.TsType,
) -> String? {
  match utility_record_key_suffix(key_type) {
    Some(key_suffix) =>
      Some(key_suffix + "RecordOf" + utility_record_type_suffix(value_type))
    None => None
  }
}

///|
fn utility_tuple_rest_array_type(type_ : @ast.TsType) -> @ast.TsType? {
  match type_ {
    Tuple(items) => {
      if items.length() < 2 {
        return None
      }
      let mut item_type : @ast.TsType? = None
      let mut has_rest_array = false
      for item in items {
        let current = match item {
          // `[T, ...T[]]` parsed with the variadic-tuple representation
          // surfaces the rest as `Rest(Array(inner))`; treat that as a
          // rest-array hit so the existing collapse path keeps working.
          Rest(Array(inner)) => {
            has_rest_array = true
            inner
          }
          Rest(inner) => {
            has_rest_array = true
            inner
          }
          Array(inner) => {
            has_rest_array = true
            inner
          }
          _ => item
        }
        match item_type {
          Some(existing) => if existing != current { return None }
          None => item_type = Some(current)
        }
      }
      if !has_rest_array {
        return None
      }
      match item_type {
        Some(inner) => Some(Array(inner))
        None => None
      }
    }
    _ => None
  }
}

///|
fn utility_awaited_type(type_ : @ast.TsType) -> @ast.TsType {
  match type_ {
    Applied("Promise", [inner]) | Applied("PromiseLike", [inner]) =>
      utility_awaited_type(inner)
    _ => type_
  }
}

///|
fn typeof_query_simple_name(query : String) -> String? {
  if query.has_prefix("import(") || query.contains(".") {
    None
  } else {
    Some(query)
  }
}

///|
fn resolve_typeof_class_origin(
  info : DeclModuleInfo,
  query : String,
  modules : Map[String, DeclModuleInfo],
) -> (DeclModuleInfo, @ast.TsClassDecl)? {
  let name = match typeof_query_simple_name(query) {
    Some(name) => name
    None => return None
  }
  match find_class_decl_recursive(info.module_, name) {
    Some(class_) => Some((info, class_))
    None =>
      match resolve_imported_type_origin(info, name) {
        Some((source_path, imported_name)) =>
          match modules.get(source_path) {
            Some(source_info) =>
              match
                find_class_decl_recursive(source_info.module_, imported_name) {
                Some(class_) => Some((source_info, class_))
                None => None
              }
            None => None
          }
        None => None
      }
  }
}

///|
fn typeof_class_instance_type(
  info : DeclModuleInfo,
  query : String,
  modules : Map[String, DeclModuleInfo],
  canonical_types : Map[String, String],
) -> @ast.TsType? {
  match resolve_typeof_class_origin(info, query, modules) {
    Some((origin_info, class_)) =>
      Some(
        Named(
          match
            resolve_exported_type_name(
              origin_info,
              class_.name,
              canonical_types,
            ) {
            Some(export_name) => export_name
            None => class_.name
          },
        ),
      )
    None => None
  }
}

///|
fn typeof_class_constructor_params_type(
  info : DeclModuleInfo,
  query : String,
  modules : Map[String, DeclModuleInfo],
  canonical_types : Map[String, String],
) -> @ast.TsType? {
  match resolve_typeof_class_origin(info, query, modules) {
    Some((origin_info, class_)) => {
      let items : Array[@ast.TsType] = []
      match class_.constructor_params {
        Some(params) =>
          for param in params {
            items.push(
              lower_react_utility_type(
                origin_info,
                param.1,
                modules,
                canonical_types,
              ),
            )
          }
        None => ()
      }
      Some(Tuple(items))
    }
    None => None
  }
}

///|
fn typeof_value_query_type(
  info : DeclModuleInfo,
  query : String,
  modules : Map[String, DeclModuleInfo],
  canonical_types : Map[String, String],
) -> @ast.TsType? {
  let name = match typeof_query_simple_name(query) {
    Some(name) => name
    None => return None
  }
  match find_import_decl(info.module_, name) {
    Some(import_) => {
      let type_ = typeof_import_decl_to_func_type(
        info, import_, modules, canonical_types,
      )
      if typeof_value_type_is_stable(info, type_) {
        Some(type_)
      } else {
        None
      }
    }
    None =>
      match find_func_decl(info.module_, name) {
        Some(func) => {
          let type_ = typeof_func_decl_to_func_type(
            info, func, modules, canonical_types,
          )
          if typeof_value_type_is_stable(info, type_) {
            Some(type_)
          } else {
            None
          }
        }
        None =>
          match find_value_decl(info.module_, name) {
            Some(value) =>
              match value.type_ {
                TypeOf(inner) if inner == query => None
                other => {
                  let type_ = lower_react_utility_type(
                    info, other, modules, canonical_types,
                  )
                  if typeof_value_type_is_stable(info, type_) {
                    Some(type_)
                  } else {
                    None
                  }
                }
              }
            None => None
          }
      }
  }
}

///|
fn typeof_import_decl_to_func_type(
  info : DeclModuleInfo,
  import_ : @ast.TsImport,
  modules : Map[String, DeclModuleInfo],
  canonical_types : Map[String, String],
) -> @ast.TsType {
  let params : Array[@ast.TsType] = []
  for param in import_.params {
    params.push(
      lower_react_utility_type(info, param.1, modules, canonical_types),
    )
  }
  Func(
    params,
    lower_react_utility_type(
      info,
      import_.return_type,
      modules,
      canonical_types,
    ),
  )
}

///|
fn typeof_func_decl_to_func_type(
  info : DeclModuleInfo,
  func : @ast.TsFunc,
  modules : Map[String, DeclModuleInfo],
  canonical_types : Map[String, String],
) -> @ast.TsType {
  let params : Array[@ast.TsType] = []
  for param in func.params {
    params.push(
      lower_react_utility_type(info, param.type_, modules, canonical_types),
    )
  }
  Func(
    params,
    lower_react_utility_type(info, func.return_type, modules, canonical_types),
  )
}

///|
fn typeof_value_type_is_stable(
  info : DeclModuleInfo,
  type_ : @ast.TsType,
) -> Bool {
  match @checker.classify_optional_like_union(type_) {
    Some((collapsed, _)) => return typeof_value_type_is_stable(info, collapsed)
    None => ()
  }
  match @checker.classify_transparent_intersection(type_) {
    Some(inner) => return typeof_value_type_is_stable(info, inner)
    None => ()
  }
  match type_ {
    Any | Never | Null | Undefined | TypeOf(_) => false
    Literal(_) | NumberLiteral(_) | BigIntLiteral(_) | BooleanLiteral(_) => true
    Number | Int | BigInt | Boolean | String_ | Void => true
    Named(name) => typeof_named_type_is_stable(info, name)
    Array(inner) => typeof_value_type_is_stable(info, inner)
    Tuple(items) => {
      for item in items {
        if !typeof_value_type_is_stable(info, item) {
          return false
        }
      }
      true
    }
    Func(params, return_type) => {
      for param in params {
        if !typeof_value_type_is_stable(info, param) {
          return false
        }
      }
      typeof_value_type_is_stable(info, return_type)
    }
    Applied(name, args) => {
      if !typeof_named_type_is_stable(info, name) {
        return false
      }
      for arg in args {
        if !typeof_value_type_is_stable(info, arg) {
          return false
        }
      }
      true
    }
    Union(items) | Intersection(items) => {
      for item in items {
        if !typeof_value_type_is_stable(info, item) {
          return false
        }
      }
      true
    }
    _ => false
  }
}

///|
fn typeof_named_type_is_stable(info : DeclModuleInfo, name : String) -> Bool {
  if name == "Array" ||
    name == "ReadonlyArray" ||
    name == "Promise" ||
    name == "PromiseLike" {
    return true
  }
  if name == "any" ||
    name == "unknown" ||
    name == "Function" ||
    name.contains(".") {
    return false
  }
  match find_interface_decl_recursive(info.module_, name) {
    Some(_) => return true
    None => ()
  }
  match find_class_decl_recursive(info.module_, name) {
    Some(_) => return true
    None => ()
  }
  match find_enum_decl(info.module_, name) {
    Some(_) => return true
    None => ()
  }
  match find_type_alias_decl(info.module_, name) {
    Some(_) => true
    None => false
  }
}

///|
fn type_alias_passthrough_supported(type_alias : @ast.TsTypeAlias) -> Bool {
  type_alias.type_params.length() == 0 &&
  type_alias_target_passthrough_supported(type_alias.type_)
}

///|
fn type_alias_target_passthrough_supported(type_ : @ast.TsType) -> Bool {
  match @checker.classify_optional_like_union(type_) {
    Some((collapsed, _)) =>
      return type_alias_target_passthrough_supported(collapsed)
    None => ()
  }
  match @checker.classify_transparent_intersection(type_) {
    Some(inner) => return type_alias_target_passthrough_supported(inner)
    None => ()
  }
  match type_ {
    Literal(_) | NumberLiteral(_) | BigIntLiteral(_) | BooleanLiteral(_) => true
    Number | Int | BigInt | Boolean | String_ | Void => true
    Named(_) => true
    Array(inner) => type_alias_target_passthrough_supported(inner)
    Tuple(items) => {
      if items.length() == 0 {
        return true
      }
      for item in items {
        if item != items[0] || !type_alias_target_passthrough_supported(item) {
          return false
        }
      }
      true
    }
    Func(params, return_type) => {
      for param in params {
        if !type_alias_target_passthrough_supported(param) {
          return false
        }
      }
      type_alias_target_passthrough_supported(return_type)
    }
    Applied("Array", [inner]) | Applied("ReadonlyArray", [inner]) =>
      type_alias_target_passthrough_supported(inner)
    Applied("Promise", [inner]) | Applied("PromiseLike", [inner]) =>
      type_alias_target_passthrough_supported(inner)
    Applied(name, args) => {
      if name == "any" || name == "Function" {
        return false
      }
      for arg in args {
        if !type_alias_target_passthrough_supported(arg) {
          return false
        }
      }
      true
    }
    _ => false
  }
}

///|
/// Synthesize a `TsInterface` from a type alias whose body is a direct
/// utility-type instantiation (`Pick<Foo, K>` / `Omit<Foo, K>` /
/// `Partial<Foo>` / `Required<Foo>` / `Readonly<Foo>`). Reuses the
/// existing utility-projection / mapped-interface specs but renames the
/// result to the alias name so consumers see `pub(all) struct IdOnly`
/// instead of an opaque `declare pub type IdOnly`.
fn type_alias_utility_to_interface(
  info : DeclModuleInfo,
  type_alias : @ast.TsTypeAlias,
  modules : Map[String, DeclModuleInfo],
  canonical_types : Map[String, String],
) -> @ast.TsInterface? {
  if type_alias.type_params.length() > 0 {
    return None
  }
  let spec : @ast.TsInterface? = match type_alias.type_ {
    Applied(name, args) =>
      if name == "Record" && args.length() == 2 {
        type_alias_record_to_interface_fields(
          info,
          modules,
          canonical_types,
          args[0],
          args[1],
        )
      } else if (name == "Pick" || name == "Omit") && args.length() == 2 {
        let (resolved_info, resolved_source) = redirect_qualified_named(
          info,
          modules,
          args[0],
        )
        match
          utility_projection_interface_spec(
            resolved_info,
            name,
            resolved_source,
            args[1],
            modules,
            canonical_types,
          ) {
          Some(iface) => Some(iface)
          None =>
            // Source might itself be a utility-instantiation alias
            // (e.g. `Pick<SchemaPartial, ...>` where `SchemaPartial =
            // Partial<Schema>`); resolve the chain to a synthetic
            // interface and re-run the projection over its fields.
            match
              resolve_alias_chain_to_interface(
                resolved_info,
                modules,
                canonical_types,
                resolved_source,
                [],
              ) {
              Some((_, synth)) => project_interface_fields(name, synth, args[1])
              None => None
            }
        }
      } else if @checker.is_mapped_interface_utility_name(name) &&
        args.length() == 1 {
        let (resolved_info, resolved_source) = redirect_qualified_named(
          info,
          modules,
          args[0],
        )
        match
          utility_mapped_interface_spec(
            resolved_info, name, resolved_source, modules, canonical_types,
          ) {
          Some(iface) => Some(iface)
          None =>
            match
              resolve_alias_chain_to_interface(
                resolved_info,
                modules,
                canonical_types,
                resolved_source,
                [],
              ) {
              Some((_, synth)) => map_interface_fields(name, synth)
              None => None
            }
        }
      } else {
        None
      }
    _ => None
  }
  match spec {
    Some(iface) => Some({ ..iface, name: type_alias.name })
    None => None
  }
}

///|
/// Lower a `Record<K, V>` whose keys are a finite literal union into an
/// interface body. Each literal key becomes a field; alias-indirected
/// literal-union sources resolve through the chain helpers so
/// `Record<MyKeys, number>` works whenever `MyKeys` reduces to literal
/// names. Returns `None` for non-finite key sources (`string`, opaque
/// `Named`, etc.) so callers fall back to the default `Record` lowering.
fn type_alias_record_to_interface_fields(
  info : DeclModuleInfo,
  modules : Map[String, DeclModuleInfo],
  canonical_types : Map[String, String],
  key_type : @ast.TsType,
  value_type : @ast.TsType,
) -> @ast.TsInterface? {
  // Walk through alias indirections so `Record<MyKeys, number>` resolves.
  let lowered_key = lower_react_utility_type(
    info, key_type, modules, canonical_types,
  )
  let inlined_key = inline_named_aliases(info, modules, lowered_key, [])
  let resolved_key = @checker.simplify_type(inlined_key)
  let keys = match utility_literal_key_names(resolved_key) {
    Some(ks) => ks
    None => return None
  }
  if keys.length() == 0 {
    return None
  }
  let lowered_value = lower_react_utility_type(
    info, value_type, modules, canonical_types,
  )
  let fields : Array[(String, @ast.TsType)] = []
  for k in keys {
    fields.push((k, lowered_value))
  }
  Some({
    name: "RecordSynthetic",
    type_params: [],
    extends_names: [],
    extends_args: [],
    fields,
    readonly_fields: [],
    index_signatures: [],
  })
}

///|
/// Walk a chain of `Named(alias)` references whose bodies are themselves
/// utility instantiations (`type SchemaPartial = Partial<Schema>` →
/// `type FullSchema = Required<SchemaPartial>`) until a synthetic
/// interface can be produced. Tracks visited names to avoid cycles.
fn resolve_alias_chain_to_interface(
  info : DeclModuleInfo,
  modules : Map[String, DeclModuleInfo],
  canonical_types : Map[String, String],
  source : @ast.TsType,
  visited : Array[String],
) -> (DeclModuleInfo, @ast.TsInterface)? {
  let (info1, source1) = redirect_qualified_named(info, modules, source)
  match source1 {
    Named(name) => {
      if visited.contains(name) {
        return None
      }
      // Reached a real interface — base of the chain.
      match find_interface_decl_recursive(info1.module_, name) {
        Some(iface) => return Some((info1, iface))
        None => ()
      }
      // Otherwise the chain continues through a type alias whose body is
      // itself a utility instantiation. Re-enter
      // `type_alias_utility_to_interface` on a synthetic alias view.
      match find_type_alias_decl(info1.module_, name) {
        Some(ta) => {
          let next_visited : Array[String] = []
          for v in visited {
            next_visited.push(v)
          }
          next_visited.push(name)
          match ta.type_ {
            Applied(_, _) =>
              match
                type_alias_utility_to_interface(
                  info1, ta, modules, canonical_types,
                ) {
                Some(iface) => Some((info1, iface))
                None => None
              }
            _ => None
          }
        }
        None => None
      }
    }
    _ => None
  }
}

///|
/// Apply `Pick<_, keys>` / `Omit<_, keys>` to an already-synthesized
/// interface's fields, returning a fresh interface with the projected
/// fields. Uses the same name as the input interface so callers (which
/// rename to the surrounding alias) keep working.
fn project_interface_fields(
  op_name : String,
  iface : @ast.TsInterface,
  keys_type : @ast.TsType,
) -> @ast.TsInterface? {
  let keys = match utility_literal_key_names(keys_type) {
    Some(ks) => ks
    None => return None
  }
  let fields : Array[(String, @ast.TsType)] = []
  for f in iface.fields {
    let (field_name, field_type) = f
    let should_include = match op_name {
      "Pick" => keys.contains(field_name)
      "Omit" => !keys.contains(field_name)
      _ => false
    }
    if should_include {
      fields.push((field_name, field_type))
    }
  }
  Some({
    name: iface.name,
    type_params: [],
    extends_names: [],
    extends_args: [],
    fields,
    readonly_fields: readonly_fields_for_fields(iface.readonly_fields, fields),
    index_signatures: [],
  })
}

///|
/// Apply `Partial` / `Required` / `Readonly` to the fields of an
/// already-synthesized interface, mirroring
/// `utility_mapped_interface_spec` but consuming a ready interface
/// instead of resolving a `Named(...)` source.
fn map_interface_fields(
  op_name : String,
  iface : @ast.TsInterface,
) -> @ast.TsInterface? {
  let fields : Array[(String, @ast.TsType)] = []
  for f in iface.fields {
    let (field_name, field_type) = f
    fields.push((field_name, utility_mapped_field_type(op_name, field_type)))
  }
  Some({
    name: iface.name,
    type_params: [],
    extends_names: [],
    extends_args: [],
    fields,
    readonly_fields: if op_name == "Readonly" {
      all_field_names(fields)
    } else {
      readonly_fields_for_fields(iface.readonly_fields, fields)
    },
    index_signatures: iface.index_signatures,
  })
}

///|
/// Rewrite a qualified `Named("util.Foo")` source to `Named("Foo")` and
/// return the `DeclModuleInfo` of the namespace target so utility-spec
/// resolvers (which only look at `info.module_`) can find the actual
/// interface. Falls back to the unchanged input when the operand isn't
/// qualified or the namespace can't be matched.
fn redirect_qualified_named(
  info : DeclModuleInfo,
  modules : Map[String, DeclModuleInfo],
  source : @ast.TsType,
) -> (DeclModuleInfo, @ast.TsType) {
  match source {
    Named(name) =>
      match name.find(".") {
        Some(pos) => {
          let head = name[0:pos].to_string()
          let tail = name[pos + 1:].to_string()
          match resolve_namespace_alias_module(info, modules, head) {
            Some(target_info) => (target_info, Named(tail))
            None => (info, source)
          }
        }
        None => (info, source)
      }
    _ => (info, source)
  }
}

///|
/// Synthesize a `TsInterface` from a type alias whose body has been
/// reduced to an `Object(fields)` shape with literal keys (e.g. through
/// mapped-type partial-evaluation). Returns `None` for parameterized
/// aliases or non-literal keys so callers can fall back to the standard
/// "Missing" / opaque-type emit path.
fn type_alias_object_to_interface(
  type_alias : @ast.TsTypeAlias,
) -> @ast.TsInterface? {
  if type_alias.type_params.length() > 0 {
    return None
  }
  match type_alias.type_ {
    Object(fields) => {
      let iface_fields : Array[(String, @ast.TsType)] = []
      for f in fields {
        match f.0 {
          Literal(key) => iface_fields.push((key, f.1))
          _ => return None
        }
      }
      if iface_fields.length() == 0 {
        return None
      }
      Some({
        name: type_alias.name,
        type_params: [],
        extends_names: [],
        extends_args: [],
        fields: iface_fields,
        readonly_fields: [],
        index_signatures: [],
      })
    }
    _ => None
  }
}

///|
fn find_type_alias_decl(
  module_ : @ast.TsModule,
  name : String,
) -> @ast.TsTypeAlias? {
  for type_alias in module_.type_aliases {
    if type_alias.name == name {
      return Some(type_alias)
    }
  }
  None
}

///|
fn type_alias_boolean_literal_primitive_type(
  type_alias : @ast.TsTypeAlias,
) -> @ast.TsType? {
  enum_lowering_type_alias_boolean_literal_primitive_type(type_alias)
}

///|
fn enum_decl_unsupported_reason(enum_ : @ast.TsEnumDecl) -> String? {
  enum_lowering_unsupported_reason(enum_)
}

///|
fn type_alias_enum_like_unsupported_reason(
  type_alias : @ast.TsTypeAlias,
) -> String? {
  enum_lowering_type_alias_enum_like_unsupported_reason(type_alias)
}

///|
fn type_has_anonymous_enum_like_literal_union(type_ : @ast.TsType) -> Bool {
  match type_ {
    Union(items) => {
      let mut has_enum_like_literal = false
      let mut only_literal_union_items = true
      for item in items {
        match item {
          Literal(_) | NumberLiteral(_) | BigIntLiteral(_) =>
            has_enum_like_literal = true
          BooleanLiteral(_) | Undefined | Null => ()
          _ => only_literal_union_items = false
        }
      }
      if has_enum_like_literal && only_literal_union_items {
        return true
      }
      for item in items {
        if type_has_anonymous_enum_like_literal_union(item) {
          return true
        }
      }
      false
    }
    Array(inner) => type_has_anonymous_enum_like_literal_union(inner)
    Tuple(items) | Intersection(items) => {
      for item in items {
        if type_has_anonymous_enum_like_literal_union(item) {
          return true
        }
      }
      false
    }
    Object(fields) => {
      for field in fields {
        if type_has_anonymous_enum_like_literal_union(field.1) {
          return true
        }
      }
      false
    }
    Struct(_, fields) => {
      for field in fields {
        if type_has_anonymous_enum_like_literal_union(field.1) {
          return true
        }
      }
      false
    }
    Func(params, return_type) => {
      for param in params {
        if type_has_anonymous_enum_like_literal_union(param) {
          return true
        }
      }
      type_has_anonymous_enum_like_literal_union(return_type)
    }
    Conditional(source, target, true_type, false_type) =>
      type_has_anonymous_enum_like_literal_union(source) ||
      type_has_anonymous_enum_like_literal_union(target) ||
      type_has_anonymous_enum_like_literal_union(true_type) ||
      type_has_anonymous_enum_like_literal_union(false_type)
    Applied(_, args) => {
      for arg in args {
        if type_has_anonymous_enum_like_literal_union(arg) {
          return true
        }
      }
      false
    }
    _ => false
  }
}

///|
fn interface_has_anonymous_enum_like_literal_union(
  iface : @ast.TsInterface,
) -> Bool {
  for field in iface.fields {
    if type_has_anonymous_enum_like_literal_union(field.1) {
      return true
    }
  }
  false
}

///|
fn import_has_anonymous_enum_like_literal_union(
  import_ : @ast.TsImport,
) -> Bool {
  for param in import_.params {
    if type_has_anonymous_enum_like_literal_union(param.1) {
      return true
    }
  }
  type_has_anonymous_enum_like_literal_union(import_.return_type)
}

///|
fn func_has_anonymous_enum_like_literal_union(func : @ast.TsFunc) -> Bool {
  for param in func.params {
    if type_has_anonymous_enum_like_literal_union(param.type_) {
      return true
    }
  }
  type_has_anonymous_enum_like_literal_union(func.return_type)
}

///|
fn push_anonymous_literal_union_note(
  notes : Array[String],
  export_name : String,
) -> Unit {
  let note = "///|\n/// Unsupported export \{export_name}: anonymous literal union in public surface is widened because no stable public enum name."
  if !notes.contains(note) {
    notes.push(note)
  }
}

///|
fn push_remaining_anonymous_literal_union_notes(
  notes : Array[String],
  interfaces : Array[@ast.TsInterface],
  imports : Array[@ast.TsImport],
  funcs : Array[@ast.TsFunc],
) -> Unit {
  for iface in interfaces {
    if interface_has_anonymous_enum_like_literal_union(iface) {
      push_anonymous_literal_union_note(notes, iface.name)
    }
  }
  for import_ in imports {
    if import_has_anonymous_enum_like_literal_union(import_) {
      push_anonymous_literal_union_note(notes, import_.name)
    }
  }
  for func in funcs {
    if func_has_anonymous_enum_like_literal_union(func) {
      push_anonymous_literal_union_note(notes, func.name)
    }
  }
}

///|
fn type_name_references_alias(
  module_ : @ast.TsModule,
  name : String,
  target : String,
  seen_aliases : Array[String],
) -> Bool {
  if name == target {
    return true
  }
  if seen_aliases.contains(name) {
    return false
  }
  match find_type_alias_decl(module_, name) {
    Some(type_alias) => {
      seen_aliases.push(name)
      let found = type_references_alias(
        module_,
        type_alias.type_,
        target,
        seen_aliases,
      )
      let _ = seen_aliases.pop()
      found
    }
    None => false
  }
}

///|
fn type_references_alias(
  module_ : @ast.TsModule,
  type_ : @ast.TsType,
  target : String,
  seen_aliases : Array[String],
) -> Bool {
  match type_ {
    Named(name) =>
      type_name_references_alias(module_, name, target, seen_aliases)
    Applied(name, args) => {
      if type_name_references_alias(module_, name, target, seen_aliases) {
        return true
      }
      for arg in args {
        if type_references_alias(module_, arg, target, seen_aliases) {
          return true
        }
      }
      false
    }
    Array(inner) => type_references_alias(module_, inner, target, seen_aliases)
    Tuple(items) | Union(items) | Intersection(items) => {
      for item in items {
        if type_references_alias(module_, item, target, seen_aliases) {
          return true
        }
      }
      false
    }
    Object(fields) => {
      for field in fields {
        if type_references_alias(module_, field.0, target, seen_aliases) ||
          type_references_alias(module_, field.1, target, seen_aliases) {
          return true
        }
      }
      false
    }
    Struct(_, fields) => {
      for field in fields {
        if type_references_alias(module_, field.1, target, seen_aliases) {
          return true
        }
      }
      false
    }
    Func(params, return_type) => {
      for param in params {
        if type_references_alias(module_, param, target, seen_aliases) {
          return true
        }
      }
      type_references_alias(module_, return_type, target, seen_aliases)
    }
    Conditional(source, constraint, true_type, false_type) =>
      type_references_alias(module_, source, target, seen_aliases) ||
      type_references_alias(module_, constraint, target, seen_aliases) ||
      type_references_alias(module_, true_type, target, seen_aliases) ||
      type_references_alias(module_, false_type, target, seen_aliases)
    _ => false
  }
}

///|
fn type_alias_is_recursive(
  module_ : @ast.TsModule,
  type_alias : @ast.TsTypeAlias,
) -> Bool {
  let seen_aliases : Array[String] = []
  seen_aliases.push(type_alias.name)
  type_references_alias(
    module_,
    type_alias.type_,
    type_alias.name,
    seen_aliases,
  )
}

///|
fn type_alias_param_binding(
  params : Array[String],
  args : Array[@ast.TsType],
  name : String,
) -> @ast.TsType? {
  for i, param_name in params {
    if param_name == name {
      if i < args.length() {
        return Some(args[i])
      }
      return None
    }
  }
  None
}

///|
fn substitute_type_alias_params(
  type_ : @ast.TsType,
  params : Array[String],
  args : Array[@ast.TsType],
) -> @ast.TsType {
  match type_ {
    Applied("__tsmbt_infer", _) => type_
    Named(name) =>
      match type_alias_param_binding(params, args, name) {
        Some(arg) => arg
        None => type_
      }
    Array(inner) => Array(substitute_type_alias_params(inner, params, args))
    Tuple(items) => {
      let out : Array[@ast.TsType] = []
      for item in items {
        out.push(substitute_type_alias_params(item, params, args))
      }
      Tuple(out)
    }
    Object(fields) => {
      let out : Array[(@ast.TsType, @ast.TsType)] = []
      for field in fields {
        let (key, value) = field
        out.push(
          (
            substitute_type_alias_params(key, params, args),
            substitute_type_alias_params(value, params, args),
          ),
        )
      }
      Object(out)
    }
    Func(fn_params, ret) => {
      let out : Array[@ast.TsType] = []
      for param in fn_params {
        out.push(substitute_type_alias_params(param, params, args))
      }
      Func(out, substitute_type_alias_params(ret, params, args))
    }
    Union(items) => {
      let out : Array[@ast.TsType] = []
      for item in items {
        out.push(substitute_type_alias_params(item, params, args))
      }
      // After substitution, members may collapse onto each other (e.g.
      // `T | string` with T := string becomes `string | string`); simplify
      // before re-wrapping. Keep the outer Union wrap even when only one
      // member survives so downstream Eq-based matchers still see a Union.
      Union(@checker.simplify_union(out))
    }
    Intersection(items) => {
      let out : Array[@ast.TsType] = []
      for item in items {
        out.push(substitute_type_alias_params(item, params, args))
      }
      Intersection(out)
    }
    Conditional(source, target, true_type, false_type) =>
      Conditional(
        substitute_type_alias_params(source, params, args),
        substitute_type_alias_params(target, params, args),
        substitute_type_alias_params(true_type, params, args),
        substitute_type_alias_params(false_type, params, args),
      )
    Applied(name, applied_args) => {
      let out : Array[@ast.TsType] = []
      for arg in applied_args {
        out.push(substitute_type_alias_params(arg, params, args))
      }
      Applied(name, out)
    }
    _ => type_
  }
}

///|
fn applied_type_alias(
  info : DeclModuleInfo,
  name : String,
  args : Array[@ast.TsType],
) -> @ast.TsType? {
  match find_type_alias_decl(info.module_, name) {
    Some(type_alias) =>
      if type_alias.type_params.length() == args.length() {
        if type_alias_is_recursive(info.module_, type_alias) {
          return None
        }
        let substituted = substitute_type_alias_params(
          type_alias.type_,
          type_alias.type_params,
          args,
        )
        if substituted == Applied(name, args) {
          None
        } else {
          Some(substituted)
        }
      } else {
        None
      }
    None => None
  }
}

// `decl_infer_marker_name`, `decl_match_infer_pattern`, and
// `decl_substitute_inferred_type` were duplicates of the helpers now in
// `mizchi/ts/checker`. Bridge calls `@checker.match_infer_pattern` etc.
// directly.

///|
// `decl_type_extends_simple` moved to `mizchi/ts/checker` as
// `extends_decision`. The shared version additionally recognises literal
// narrowing (Literal extends String_, NumberLiteral extends Number, etc.),
// which is strictly more permissive but does not regress any tests.

///|
fn lower_react_utility_type(
  info : DeclModuleInfo,
  type_ : @ast.TsType,
  modules : Map[String, DeclModuleInfo],
  canonical_types : Map[String, String],
) -> @ast.TsType {
  match utility_tuple_rest_array_type(type_) {
    Some(array_type) =>
      return lower_react_utility_type(
        info, array_type, modules, canonical_types,
      )
    None => ()
  }
  match type_ {
    Named(name) if @checker.is_qualified_react_node_name(name) =>
      Named("ReactNode")
    Named(name) if @checker.is_react_node_like_name(name) => Any
    Applied(name, [event_type]) if @checker.is_event_handler_alias_name(name) =>
      Func(
        [lower_react_utility_type(info, event_type, modules, canonical_types)],
        Void,
      )
    Applied(name, _) if @checker.is_signalish_alias_name(name) =>
      Named("Signalish")
    Named(name) if @checker.is_signalish_alias_name(name) => Named("Signalish")
    Applied(name, _) if @checker.is_params_alias_name(name) => Named("Params")
    Named(name) if @checker.is_params_alias_name(name) => Named("Params")
    Applied(name, _) if @checker.is_ref_alias_name(name) => Named("Ref")
    Named(name) if @checker.is_ref_alias_name(name) => Named("Ref")
    IndexedAccess(base, key) =>
      match resolve_indexed_access(info, base, key, modules, canonical_types) {
        Some(field_type) => {
          // Self-referential field types like
          // `interface Foo { selection: Foo['selection']; }`, or the
          // deeper drizzle pattern where the field's element type
          // re-references `Foo['selection']` from inside an `Array<{
          // ... selection: Foo['selection'] }>`, resolve back to the
          // same `IndexedAccess` shape we just consumed. Replace any
          // nested self-pointing `IndexedAccess` with `Any` before
          // recursing so `lower_react_utility_type` does not spin
          // forever.
          let pruned = strip_self_indexed_access(field_type, base, key)
          lower_react_utility_type(info, pruned, modules, canonical_types)
        }
        None => Any
      }
    Keyof(inner) => {
      // Lower the operand first so any Named base resolves to its struct
      // shape; `simplify_type` then turns `keyof Struct(...)` into a
      // literal-key union. When the operand still names an opaque module
      // type, look it up through the bridge resolver so we can see its
      // field shape. If even that fails we fall back to `String_` —
      // bridge consumers historically saw `keyof T` as a string-shaped
      // opaque key, and most call sites only use it as an index lookup
      // we already widen to `String`.
      let lowered_inner = lower_react_utility_type(
        info, inner, modules, canonical_types,
      )
      let resolved_inner = match lowered_inner {
        Named(name) =>
          match resolve_named_to_struct(info, name) {
            Some(s) => s
            None => lowered_inner
          }
        _ => lowered_inner
      }
      match @checker.simplify_type(Keyof(resolved_inner)) {
        Keyof(_) => String_
        other => other
      }
    }
    MappedType(key_param, source, value, optional) => {
      // Resolve `Named(...)` operands inside the source so `keyof Foo`
      // sees `Struct(Foo, fields)` and `simplify_type` can iterate keys.
      let lowered_source = lower_react_utility_type(
        info, source, modules, canonical_types,
      )
      let resolved_source = resolve_named_inside_type(info, lowered_source)
      match
        @checker.simplify_type(
          MappedType(key_param, resolved_source, value, optional),
        ) {
        Object(fields) => {
          // Recurse into the materialized field types so each substituted
          // `Literal` flows through the rest of the bridge pipeline (utility
          // type lowering, JSX flattening, etc.).
          let lowered : Array[(@ast.TsType, @ast.TsType)] = []
          for f in fields {
            lowered.push(
              (
                f.0,
                lower_react_utility_type(info, f.1, modules, canonical_types),
              ),
            )
          }
          Object(lowered)
        }
        // Source remained opaque (e.g. `{ [K in keyof T]: V }` for an
        // unbound generic `T`); widen to `Any` so downstream consumers
        // route through `JSValue` rather than carrying an unresolved
        // `MappedType` into emit.
        MappedType(_, _, _, _) => Any
        other => lower_react_utility_type(info, other, modules, canonical_types)
      }
    }
    MappedTypeRemap(key_param, source, remap, value, optional) => {
      let lowered_source = lower_react_utility_type(
        info, source, modules, canonical_types,
      )
      let resolved_source = resolve_named_inside_type(info, lowered_source)
      match
        @checker.simplify_type(
          MappedTypeRemap(key_param, resolved_source, remap, value, optional),
        ) {
        Object(fields) => {
          let lowered : Array[(@ast.TsType, @ast.TsType)] = []
          for f in fields {
            lowered.push(
              (
                f.0,
                lower_react_utility_type(info, f.1, modules, canonical_types),
              ),
            )
          }
          Object(lowered)
        }
        // Couldn't resolve the remap; widen to `Any` so we don't carry
        // the unresolved variant into emit.
        MappedTypeRemap(_, _, _, _, _) => Any
        other => lower_react_utility_type(info, other, modules, canonical_types)
      }
    }
    Applied(name, [inner_type]) if @checker.is_props_passthrough_name(name) =>
      lower_react_utility_type(info, inner_type, modules, canonical_types)
    Applied(name, [source_type]) if @checker.is_mapped_interface_utility_name(
        name,
      ) =>
      match
        utility_mapped_interface_spec(
          info, name, source_type, modules, canonical_types,
        ) {
        Some(iface) => Named(iface.name)
        None =>
          Applied(name, [
            lower_react_utility_type(
              info, source_type, modules, canonical_types,
            ),
          ])
      }
    Applied("PropsWithChildren", [inner_type]) =>
      match
        props_with_children_interface_spec(
          info, inner_type, modules, canonical_types,
        ) {
        Some(iface) => Named(iface.name)
        None =>
          Applied("PropsWithChildren", [
            lower_react_utility_type(info, inner_type, modules, canonical_types),
          ])
      }
    Applied("ComponentPropsWithRef", [inner_type]) =>
      match
        component_props_with_ref_interface_spec(
          info, inner_type, modules, canonical_types,
        ) {
        Some(iface) => Named(iface.name)
        None =>
          Applied("ComponentPropsWithRef", [
            lower_react_utility_type(info, inner_type, modules, canonical_types),
          ])
      }
    Applied(name, [_]) if @checker.is_component_ref_like_name(name) =>
      Named(resolve_react_ref_type_name(info, canonical_types))
    Applied("LibraryManagedAttributes", [_, props_type]) =>
      lower_react_utility_type(info, props_type, modules, canonical_types)
    Applied(name, [inner_type]) if is_component_props_like_name(name) =>
      match
        component_props_resolved_type(
          info, inner_type, modules, canonical_types,
        ) {
        Some(type_) => type_
        None =>
          Applied(name, [
            lower_react_utility_type(info, inner_type, modules, canonical_types),
          ])
      }
    Applied(name, [source_type, keys_type]) if name == "Pick" || name == "Omit" =>
      match
        utility_projection_interface_spec(
          info, name, source_type, keys_type, modules, canonical_types,
        ) {
        Some(iface) => Named(iface.name)
        None =>
          Applied(name, [
            lower_react_utility_type(
              info, source_type, modules, canonical_types,
            ),
            lower_react_utility_type(info, keys_type, modules, canonical_types),
          ])
      }
    Applied("NonNullable", [inner_type]) => {
      let lowered = lower_react_utility_type(
        info, inner_type, modules, canonical_types,
      )
      match @checker.classify_optional_like_union(lowered) {
        Some((collapsed, _)) => collapsed
        None => lowered
      }
    }
    Applied("ReturnType", [Func(_, return_type)]) =>
      lower_react_utility_type(info, return_type, modules, canonical_types)
    Applied("Awaited", [inner_type]) =>
      utility_awaited_type(
        lower_react_utility_type(info, inner_type, modules, canonical_types),
      )
    Applied("Parameters", [Func(params, _)]) => {
      let lowered_params : Array[@ast.TsType] = []
      for param in params {
        lowered_params.push(
          lower_react_utility_type(info, param, modules, canonical_types),
        )
      }
      Tuple(lowered_params)
    }
    Applied("ConstructorParameters", [Constructor(params, _, _)]) => {
      // Standalone `new (...args) => T` typedef: extract the param
      // tuple directly.
      let lowered_params : Array[@ast.TsType] = []
      for param in params {
        lowered_params.push(
          lower_react_utility_type(info, param, modules, canonical_types),
        )
      }
      Tuple(lowered_params)
    }
    Applied("InstanceType", [Constructor(_, ret, _)]) =>
      lower_react_utility_type(info, ret, modules, canonical_types)
    Applied("InstanceType", [TypeOf(query)]) =>
      match typeof_class_instance_type(info, query, modules, canonical_types) {
        Some(type_) => type_
        None => Applied("InstanceType", [TypeOf(query)])
      }
    Applied("ConstructorParameters", [TypeOf(query)]) =>
      match
        typeof_class_constructor_params_type(
          info, query, modules, canonical_types,
        ) {
        Some(type_) => type_
        None => Applied("ConstructorParameters", [TypeOf(query)])
      }
    TypeOf(query) =>
      match typeof_value_query_type(info, query, modules, canonical_types) {
        Some(type_) => type_
        None => type_
      }
    Applied("Record", [key_type, value_type]) => {
      let lowered_key = lower_react_utility_type(
        info, key_type, modules, canonical_types,
      )
      let lowered_value = lower_react_utility_type(
        info, value_type, modules, canonical_types,
      )
      // Try the lowered key first; if it does not classify (e.g. `RequestHeader |
      // CustomHeader`), expand each alias one level and run the checker's
      // `simplify_type` to fold string-literal unions and transparent
      // intersections back to a primitive.
      let resolved_key = match utility_record_key_suffix(lowered_key) {
        Some(_) => lowered_key
        None =>
          @checker.simplify_type(
            expand_named_aliases_in_union(
              info, lowered_key, modules, canonical_types,
            ),
          )
      }
      match utility_record_type_name(resolved_key, lowered_value) {
        Some(name) => Named(name)
        None => Any
      }
    }
    Applied(name, [source_type, filter_type]) if name == "Exclude" ||
      name == "Extract" => {
      let lowered_source = lower_react_utility_type(
        info, source_type, modules, canonical_types,
      )
      let lowered_filter = lower_react_utility_type(
        info, filter_type, modules, canonical_types,
      )
      match utility_filter_union_type(name, lowered_source, lowered_filter) {
        Some(filtered) => filtered
        None => Applied(name, [lowered_source, lowered_filter])
      }
    }
    Conditional(source, target, true_type, false_type) => {
      let lowered_source = lower_react_utility_type(
        info, source, modules, canonical_types,
      )
      let lowered_target = lower_react_utility_type(
        info, target, modules, canonical_types,
      )
      let infer_bindings : Map[String, @ast.TsType] = {}
      if @checker.match_infer_pattern(
          lowered_source, lowered_target, infer_bindings,
        ) {
        lower_react_utility_type(
          info,
          @checker.substitute_inferred_type(true_type, infer_bindings),
          modules,
          canonical_types,
        )
      } else {
        match @checker.extends_decision(lowered_source, lowered_target) {
          Some(true) =>
            lower_react_utility_type(info, true_type, modules, canonical_types)
          Some(false) =>
            lower_react_utility_type(info, false_type, modules, canonical_types)
          None =>
            Conditional(
              lowered_source,
              lowered_target,
              lower_react_utility_type(
                info, true_type, modules, canonical_types,
              ),
              lower_react_utility_type(
                info, false_type, modules, canonical_types,
              ),
            )
        }
      }
    }
    Applied(name, args) => {
      // `Array<T>` and `ReadonlyArray<T>` carry their element via the
      // generic-application form when written with angle-bracket syntax
      // (the postfix `T[]` form parses as `Array(inner)`). Funnel both
      // through the same Conditional element joining as the `Array(_)`
      // arm below so type aliases written as `Array<Conditional<...>>`
      // also recover their default branch.
      if args.length() == 1 && (name == "Array" || name == "ReadonlyArray") {
        let lowered_inner = lower_react_utility_type(
          info,
          args[0],
          modules,
          canonical_types,
        )
        match conditional_array_element_default_join(lowered_inner) {
          Some(joined) => return Array(joined)
          None => return Array(lowered_inner)
        }
      }
      // TypeScript intrinsic string-mapping types: `Capitalize<T>`,
      // `Uncapitalize<T>`, `Uppercase<T>`, `Lowercase<T>`. If the single
      // argument lowers to a finite literal union, apply the intrinsic
      // and emit the resulting union literally; this lets template
      // literal types like `bg${Capitalize<X>}` enumerate when X resolves
      // to a string-literal alias.
      if args.length() == 1 && decl_is_string_intrinsic_name(name) {
        let mut lowered_arg = lower_react_utility_type(
          info,
          args[0],
          modules,
          canonical_types,
        )
        // Walk through type alias references so the intrinsic can see the
        // underlying literal union behind a Named arg like
        // `Capitalize<InspectColorForeground>`.
        match lowered_arg {
          @ast.TsType::Named(alias_name) =>
            match applied_type_alias(info, alias_name, []) {
              Some(resolved) =>
                lowered_arg = lower_react_utility_type(
                  info, resolved, modules, canonical_types,
                )
              None => ()
            }
          _ => ()
        }
        match decl_apply_string_intrinsic_to_literal_union(name, lowered_arg) {
          Some(applied) => return applied
          None => ()
        }
      }
      match applied_type_alias(info, name, args) {
        Some(resolved) =>
          lower_react_utility_type(info, resolved, modules, canonical_types)
        None => {
          let next_args : Array[@ast.TsType] = []
          for arg in args {
            next_args.push(
              lower_react_utility_type(info, arg, modules, canonical_types),
            )
          }
          Applied(name, next_args)
        }
      }
    }
    TemplateLiteralType(parts, type_args) => {
      // Lower each interpolated arg, inline same-module alias bodies
      // (`type Channel = "info" | "warn"` becomes the union itself),
      // resolve any `Named(InterfaceName)` reachable inside to a struct
      // shape, then simplify so chained keyof / mapped reductions
      // (e.g. `type SchemaKeys = keyof Schema` → `'id' | 'name' | ...`)
      // happen before the cartesian expansion runs.
      let lowered_args : Array[@ast.TsType] = []
      for arg in type_args {
        let lowered = lower_react_utility_type(
          info, arg, modules, canonical_types,
        )
        let inlined = inline_named_aliases(info, modules, lowered, [])
        let with_struct = resolve_named_inside_type(info, inlined)
        lowered_args.push(@checker.simplify_type(with_struct))
      }
      let resolved_template = @ast.TsType::TemplateLiteralType(
        parts, lowered_args,
      )
      match enum_lowering_template_literal_expand(resolved_template) {
        Some(literals) =>
          if literals.length() == 1 {
            literals[0]
          } else {
            @ast.TsType::Union(literals)
          }
        None => resolved_template
      }
    }
    Array(inner) => {
      let lowered_inner = lower_react_utility_type(
        info, inner, modules, canonical_types,
      )
      // If the lowered Array element is still a Conditional after the main
      // utility-type pass, fall back to the conditional's terminal default
      // branch when every leaf is a `Named(N)` (incl. `infer X`-bounded by
      // N or `Foo[K]` whose top is N) that the default also names.
      match conditional_array_element_default_join(lowered_inner) {
        Some(joined) => Array(joined)
        None => Array(lowered_inner)
      }
    }
    Tuple(items) => {
      let next_items : Array[@ast.TsType] = []
      for item in items {
        next_items.push(
          lower_react_utility_type(info, item, modules, canonical_types),
        )
      }
      Tuple(next_items)
    }
    Object(fields) => {
      let next_fields : Array[(@ast.TsType, @ast.TsType)] = []
      for field in fields {
        let (key_type, value_type) = field
        next_fields.push(
          (
            lower_react_utility_type(info, key_type, modules, canonical_types),
            lower_react_utility_type(info, value_type, modules, canonical_types),
          ),
        )
      }
      Object(next_fields)
    }
    Struct(name, fields) => {
      let next_fields : Array[(String, @ast.TsType)] = []
      for field in fields {
        let (field_name, field_type) = field
        next_fields.push(
          (
            field_name,
            lower_react_utility_type(info, field_type, modules, canonical_types),
          ),
        )
      }
      Struct(name, next_fields)
    }
    Func(params, return_type) => {
      let next_params : Array[@ast.TsType] = []
      for param in params {
        next_params.push(
          lower_react_utility_type(info, param, modules, canonical_types),
        )
      }
      Func(
        next_params,
        lower_react_utility_type(info, return_type, modules, canonical_types),
      )
    }
    Union(types) => {
      let next_types : Array[@ast.TsType] = []
      for item in types {
        next_types.push(
          lower_react_utility_type(info, item, modules, canonical_types),
        )
      }
      Union(next_types)
    }
    Intersection(types) => {
      let next_types : Array[@ast.TsType] = []
      for item in types {
        next_types.push(
          lower_react_utility_type(info, item, modules, canonical_types),
        )
      }
      Intersection(next_types)
    }
    _ => type_
  }
}

///|
fn collect_react_utility_interfaces_from_type(
  info : DeclModuleInfo,
  type_ : @ast.TsType,
  modules : Map[String, DeclModuleInfo],
  canonical_types : Map[String, String],
  seen_names : Array[String],
  interfaces : Array[@ast.TsInterface],
) -> Unit {
  match type_ {
    Applied(name, [inner_type]) if @checker.is_props_passthrough_name(name) =>
      collect_react_utility_interfaces_from_type(
        info, inner_type, modules, canonical_types, seen_names, interfaces,
      )
    Applied(name, [source_type]) if @checker.is_mapped_interface_utility_name(
        name,
      ) => {
      match
        utility_mapped_interface_spec(
          info, name, source_type, modules, canonical_types,
        ) {
        Some(iface) => {
          if !seen_names.contains(iface.name) {
            seen_names.push(iface.name)
            interfaces.push(iface)
          }
          for field in iface.fields {
            let (_, field_type) = field
            collect_react_utility_interfaces_from_type(
              info, field_type, modules, canonical_types, seen_names, interfaces,
            )
          }
        }
        None => ()
      }
      collect_react_utility_interfaces_from_type(
        info, source_type, modules, canonical_types, seen_names, interfaces,
      )
    }
    Applied("PropsWithChildren", [inner_type]) => {
      match
        props_with_children_interface_spec(
          info, inner_type, modules, canonical_types,
        ) {
        Some(iface) =>
          if !seen_names.contains(iface.name) {
            seen_names.push(iface.name)
            interfaces.push(iface)
          }
        None => ()
      }
      collect_react_utility_interfaces_from_type(
        info, inner_type, modules, canonical_types, seen_names, interfaces,
      )
    }
    Applied("ComponentPropsWithRef", [inner_type]) => {
      match
        component_props_with_ref_interface_spec(
          info, inner_type, modules, canonical_types,
        ) {
        Some(iface) => {
          if !seen_names.contains(iface.name) {
            seen_names.push(iface.name)
            interfaces.push(iface)
          }
          for field in iface.fields {
            let (_, field_type) = field
            collect_react_utility_interfaces_from_type(
              info, field_type, modules, canonical_types, seen_names, interfaces,
            )
          }
        }
        None => ()
      }
      collect_react_utility_interfaces_from_type(
        info, inner_type, modules, canonical_types, seen_names, interfaces,
      )
    }
    Applied(name, [inner_type]) if @checker.is_component_ref_like_name(name) =>
      collect_react_utility_interfaces_from_type(
        info, inner_type, modules, canonical_types, seen_names, interfaces,
      )
    Applied("LibraryManagedAttributes", [component_type, props_type]) => {
      collect_react_utility_interfaces_from_type(
        info, component_type, modules, canonical_types, seen_names, interfaces,
      )
      collect_react_utility_interfaces_from_type(
        info, props_type, modules, canonical_types, seen_names, interfaces,
      )
    }
    Applied(name, [inner_type]) if is_component_props_like_name(name) => {
      match
        component_props_resolved_type(
          info, inner_type, modules, canonical_types,
        ) {
        Some(resolved_type) =>
          collect_react_utility_interfaces_from_type(
            info, resolved_type, modules, canonical_types, seen_names, interfaces,
          )
        None => ()
      }
      collect_react_utility_interfaces_from_type(
        info, inner_type, modules, canonical_types, seen_names, interfaces,
      )
    }
    Applied(name, [source_type, keys_type]) if name == "Pick" || name == "Omit" => {
      match
        utility_projection_interface_spec(
          info, name, source_type, keys_type, modules, canonical_types,
        ) {
        Some(iface) => {
          if !seen_names.contains(iface.name) {
            seen_names.push(iface.name)
            interfaces.push(iface)
          }
          for field in iface.fields {
            let (_, field_type) = field
            collect_react_utility_interfaces_from_type(
              info, field_type, modules, canonical_types, seen_names, interfaces,
            )
          }
        }
        None => ()
      }
      collect_react_utility_interfaces_from_type(
        info, source_type, modules, canonical_types, seen_names, interfaces,
      )
      collect_react_utility_interfaces_from_type(
        info, keys_type, modules, canonical_types, seen_names, interfaces,
      )
    }
    Applied("NonNullable", [inner_type]) =>
      collect_react_utility_interfaces_from_type(
        info, inner_type, modules, canonical_types, seen_names, interfaces,
      )
    Applied("ReturnType", [Func(params, return_type)]) => {
      for param in params {
        collect_react_utility_interfaces_from_type(
          info, param, modules, canonical_types, seen_names, interfaces,
        )
      }
      collect_react_utility_interfaces_from_type(
        info, return_type, modules, canonical_types, seen_names, interfaces,
      )
    }
    Applied("Parameters", [Func(params, return_type)]) => {
      for param in params {
        collect_react_utility_interfaces_from_type(
          info, param, modules, canonical_types, seen_names, interfaces,
        )
      }
      collect_react_utility_interfaces_from_type(
        info, return_type, modules, canonical_types, seen_names, interfaces,
      )
    }
    Applied("Record", [_, _]) => ()
    Applied(name, [source_type, filter_type]) if name == "Exclude" ||
      name == "Extract" => {
      collect_react_utility_interfaces_from_type(
        info, source_type, modules, canonical_types, seen_names, interfaces,
      )
      collect_react_utility_interfaces_from_type(
        info, filter_type, modules, canonical_types, seen_names, interfaces,
      )
    }
    Applied(_, args) =>
      for arg in args {
        collect_react_utility_interfaces_from_type(
          info, arg, modules, canonical_types, seen_names, interfaces,
        )
      }
    Array(inner) =>
      collect_react_utility_interfaces_from_type(
        info, inner, modules, canonical_types, seen_names, interfaces,
      )
    Tuple(items) | Union(items) | Intersection(items) =>
      for item in items {
        collect_react_utility_interfaces_from_type(
          info, item, modules, canonical_types, seen_names, interfaces,
        )
      }
    Object(fields) =>
      for field in fields {
        let (key_type, value_type) = field
        collect_react_utility_interfaces_from_type(
          info, key_type, modules, canonical_types, seen_names, interfaces,
        )
        collect_react_utility_interfaces_from_type(
          info, value_type, modules, canonical_types, seen_names, interfaces,
        )
      }
    Struct(_, fields) =>
      for field in fields {
        let (_, field_type) = field
        collect_react_utility_interfaces_from_type(
          info, field_type, modules, canonical_types, seen_names, interfaces,
        )
      }
    Func(params, return_type) => {
      for param in params {
        collect_react_utility_interfaces_from_type(
          info, param, modules, canonical_types, seen_names, interfaces,
        )
      }
      collect_react_utility_interfaces_from_type(
        info, return_type, modules, canonical_types, seen_names, interfaces,
      )
    }
    _ => ()
  }
}

///|
fn rewrite_type_refs(
  info : DeclModuleInfo,
  type_ : @ast.TsType,
  canonical_types : Map[String, String],
) -> @ast.TsType {
  rewrite_type_refs_in_scope(info, "", type_, canonical_types)
}

///|
fn rewrite_type_refs_in_scope(
  info : DeclModuleInfo,
  local_name_prefix : String,
  type_ : @ast.TsType,
  canonical_types : Map[String, String],
) -> @ast.TsType {
  match type_ {
    Named(name) =>
      match
        resolve_exported_type_name_in_scope(
          info, local_name_prefix, name, canonical_types,
        ) {
        Some(export_name) => Named(export_name)
        None =>
          match find_type_alias_decl(info.module_, name) {
            Some(type_alias) =>
              match type_alias_boolean_literal_primitive_type(type_alias) {
                Some(alias_type) =>
                  rewrite_type_refs_in_scope(
                    info, local_name_prefix, alias_type, canonical_types,
                  )
                None => type_
              }
            None => type_
          }
      }
    Applied(name, args) => {
      let next_args : Array[@ast.TsType] = []
      for arg in args {
        next_args.push(
          rewrite_type_refs_in_scope(
            info, local_name_prefix, arg, canonical_types,
          ),
        )
      }
      match
        resolve_exported_type_name_in_scope(
          info, local_name_prefix, name, canonical_types,
        ) {
        Some(export_name) => Applied(export_name, next_args)
        None => Applied(name, next_args)
      }
    }
    Array(inner) =>
      Array(
        rewrite_type_refs_in_scope(
          info, local_name_prefix, inner, canonical_types,
        ),
      )
    Tuple(items) => {
      let next_items : Array[@ast.TsType] = []
      for item in items {
        next_items.push(
          rewrite_type_refs_in_scope(
            info, local_name_prefix, item, canonical_types,
          ),
        )
      }
      Tuple(next_items)
    }
    Object(fields) => {
      let next_fields : Array[(@ast.TsType, @ast.TsType)] = []
      for field in fields {
        let (key_type, value_type) = field
        next_fields.push(
          (
            rewrite_type_refs_in_scope(
              info, local_name_prefix, key_type, canonical_types,
            ),
            rewrite_type_refs_in_scope(
              info, local_name_prefix, value_type, canonical_types,
            ),
          ),
        )
      }
      Object(next_fields)
    }
    Struct(name, fields) => {
      let next_name = match
        resolve_exported_type_name_in_scope(
          info, local_name_prefix, name, canonical_types,
        ) {
        Some(export_name) => export_name
        None => name
      }
      let next_fields : Array[(String, @ast.TsType)] = []
      for field in fields {
        let (field_name, field_type) = field
        next_fields.push(
          (
            field_name,
            rewrite_type_refs_in_scope(
              info, local_name_prefix, field_type, canonical_types,
            ),
          ),
        )
      }
      Struct(next_name, next_fields)
    }
    Func(params, return_type) => {
      let next_params : Array[@ast.TsType] = []
      for param in params {
        next_params.push(
          rewrite_type_refs_in_scope(
            info, local_name_prefix, param, canonical_types,
          ),
        )
      }
      Func(
        next_params,
        rewrite_type_refs_in_scope(
          info, local_name_prefix, return_type, canonical_types,
        ),
      )
    }
    Union(types) => {
      let next_types : Array[@ast.TsType] = []
      for item in types {
        let next_item = rewrite_type_refs_in_scope(
          info, local_name_prefix, item, canonical_types,
        )
        match next_item {
          Union(nested_types) =>
            for nested_item in nested_types {
              next_types.push(nested_item)
            }
          _ => next_types.push(next_item)
        }
      }
      Union(next_types)
    }
    Intersection(types) => {
      let next_types : Array[@ast.TsType] = []
      for item in types {
        next_types.push(
          rewrite_type_refs_in_scope(
            info, local_name_prefix, item, canonical_types,
          ),
        )
      }
      Intersection(next_types)
    }
    _ => type_
  }
}

///|
fn tuple_result_interface_spec(
  export_name : String,
  return_type : @ast.TsType,
) -> ResultInterfaceSpec? {
  match return_type {
    Tuple(items) => {
      let fields : Array[(String, @ast.TsType)] = []
      let field_names = tuple_result_field_names(export_name, items.length())
      for i, item in items {
        fields.push((field_names[i], item))
      }
      Some({
        export_name,
        needs_runtime_tuple_wrapper: true,
        iface: {
          name: tuple_result_interface_name(export_name),
          type_params: [],
          extends_names: [],
          extends_args: [],
          fields,
          readonly_fields: [],
          index_signatures: [],
        },
      })
    }
    _ => None
  }
}

///|
fn object_result_fields(
  fields : Array[(@ast.TsType, @ast.TsType)],
) -> Array[(String, @ast.TsType)]? {
  let iface_fields : Array[(String, @ast.TsType)] = []
  for field in fields {
    let (key_type, value_type) = field
    match key_type {
      Literal(field_name) => iface_fields.push((field_name, value_type))
      _ => return None
    }
  }
  Some(iface_fields)
}

///|
fn inline_object_result_interface_spec(
  export_name : String,
  return_type : @ast.TsType,
) -> ResultInterfaceSpec? {
  let fields = match return_type {
    Object(fields) => fields
    Applied("Promise", [Object(fields)]) => fields
    Applied("PromiseLike", [Object(fields)]) => fields
    _ => return None
  }
  match object_result_fields(fields) {
    Some(iface_fields) =>
      Some({
        export_name,
        needs_runtime_tuple_wrapper: false,
        iface: {
          name: tuple_result_interface_name(export_name),
          type_params: [],
          extends_names: [],
          extends_args: [],
          fields: iface_fields,
          readonly_fields: [],
          index_signatures: [],
        },
      })
    None => None
  }
}

///|
fn result_interface_spec(
  export_name : String,
  return_type : @ast.TsType,
) -> ResultInterfaceSpec? {
  match tuple_result_interface_spec(export_name, return_type) {
    Some(spec) => Some(spec)
    None => inline_object_result_interface_spec(export_name, return_type)
  }
}

///|
fn rewrite_inline_result_return_type(
  export_name : String,
  return_type : @ast.TsType,
) -> @ast.TsType {
  match return_type {
    Tuple(_) => Named(tuple_result_interface_name(export_name))
    Object(fields) =>
      match object_result_fields(fields) {
        Some(_) => Named(tuple_result_interface_name(export_name))
        None => return_type
      }
    Applied("Promise", [Object(fields)]) =>
      match object_result_fields(fields) {
        Some(_) =>
          Applied("Promise", [Named(tuple_result_interface_name(export_name))])
        None => return_type
      }
    Applied("PromiseLike", [Object(fields)]) =>
      match object_result_fields(fields) {
        Some(_) =>
          Applied("PromiseLike", [
            Named(tuple_result_interface_name(export_name)),
          ])
        None => return_type
      }
    _ => return_type
  }
}

///|
fn normalize_result_interfaces(
  exported_imports : Array[ExportedImportDecl],
  exported_funcs : Array[ExportedFuncDecl],
  modules : Map[String, DeclModuleInfo],
  canonical_types : Map[String, String],
) -> Array[ResultInterfaceSpec] {
  let specs : Array[ResultInterfaceSpec] = []
  let seen_export_names : Array[String] = []
  for exported in exported_imports {
    match modules.get(exported.source_path) {
      Some(info) =>
        match
          result_interface_spec(
            exported.export_name,
            lower_react_utility_type(
              info,
              rewrite_type_refs_in_scope(
                info,
                exported.local_name_prefix,
                exported.import_.return_type,
                canonical_types,
              ),
              modules,
              canonical_types,
            ),
          ) {
          Some(spec) =>
            if !seen_export_names.contains(spec.export_name) {
              seen_export_names.push(spec.export_name)
              specs.push(spec)
            }
          None => ()
        }
      None => ()
    }
  }
  for exported in exported_funcs {
    match modules.get(exported.source_path) {
      Some(info) =>
        match
          result_interface_spec(
            exported.export_name,
            lower_react_utility_type(
              info,
              rewrite_type_refs_in_scope(
                info,
                exported.local_name_prefix,
                exported.func.return_type,
                canonical_types,
              ),
              modules,
              canonical_types,
            ),
          ) {
          Some(spec) =>
            if !seen_export_names.contains(spec.export_name) {
              seen_export_names.push(spec.export_name)
              specs.push(spec)
            }
          None => ()
        }
      None => ()
    }
  }
  specs
}

///|
fn normalize_react_utility_interfaces(
  exported_interfaces : Array[ExportedInterfaceDecl],
  exported_imports : Array[ExportedImportDecl],
  exported_funcs : Array[ExportedFuncDecl],
  exported_values : Array[ExportedValueDecl],
  exported_classes : Array[ExportedClassDecl],
  modules : Map[String, DeclModuleInfo],
  canonical_types : Map[String, String],
) -> Array[@ast.TsInterface] {
  let interfaces : Array[@ast.TsInterface] = []
  let seen_names : Array[String] = []
  for exported in exported_interfaces {
    match modules.get(exported.source_path) {
      Some(info) =>
        for field in exported.iface.fields {
          let (_, field_type) = field
          collect_react_utility_interfaces_from_type(
            info,
            rewrite_type_refs(info, field_type, canonical_types),
            modules,
            canonical_types,
            seen_names,
            interfaces,
          )
        }
      None => ()
    }
  }
  for exported in exported_imports {
    match modules.get(exported.source_path) {
      Some(info) => {
        for param in exported.import_.params {
          let (_, param_type) = param
          collect_react_utility_interfaces_from_type(
            info,
            rewrite_type_refs_in_scope(
              info,
              exported.local_name_prefix,
              param_type,
              canonical_types,
            ),
            modules,
            canonical_types,
            seen_names,
            interfaces,
          )
        }
        collect_react_utility_interfaces_from_type(
          info,
          rewrite_type_refs_in_scope(
            info,
            exported.local_name_prefix,
            exported.import_.return_type,
            canonical_types,
          ),
          modules,
          canonical_types,
          seen_names,
          interfaces,
        )
      }
      None => ()
    }
  }
  for exported in exported_funcs {
    match modules.get(exported.source_path) {
      Some(info) => {
        for param in exported.func.params {
          collect_react_utility_interfaces_from_type(
            info,
            rewrite_type_refs_in_scope(
              info,
              exported.local_name_prefix,
              param.type_,
              canonical_types,
            ),
            modules,
            canonical_types,
            seen_names,
            interfaces,
          )
        }
        collect_react_utility_interfaces_from_type(
          info,
          rewrite_type_refs_in_scope(
            info,
            exported.local_name_prefix,
            exported.func.return_type,
            canonical_types,
          ),
          modules,
          canonical_types,
          seen_names,
          interfaces,
        )
      }
      None => ()
    }
  }
  for exported in exported_values {
    match modules.get(exported.source_path) {
      Some(info) =>
        collect_react_utility_interfaces_from_type(
          info,
          rewrite_type_refs_in_scope(
            info,
            exported.local_name_prefix,
            exported.value.type_,
            canonical_types,
          ),
          modules,
          canonical_types,
          seen_names,
          interfaces,
        )
      None => ()
    }
  }
  for exported in exported_classes {
    match modules.get(exported.source_path) {
      Some(info) => {
        for class_property in exported.class_.properties {
          collect_react_utility_interfaces_from_type(
            info,
            rewrite_type_refs_in_scope(
              info,
              exported.local_name_prefix,
              class_property.type_,
              canonical_types,
            ),
            modules,
            canonical_types,
            seen_names,
            interfaces,
          )
        }
        for class_method in exported.class_.methods {
          for param in class_method.params {
            let (_, param_type) = param
            collect_react_utility_interfaces_from_type(
              info,
              rewrite_type_refs_in_scope(
                info,
                exported.local_name_prefix,
                param_type,
                canonical_types,
              ),
              modules,
              canonical_types,
              seen_names,
              interfaces,
            )
          }
          collect_react_utility_interfaces_from_type(
            info,
            rewrite_type_refs_in_scope(
              info,
              exported.local_name_prefix,
              class_method.return_type,
              canonical_types,
            ),
            modules,
            canonical_types,
            seen_names,
            interfaces,
          )
        }
        match exported.class_.constructor_params {
          Some(params) =>
            for param in params {
              let (_, param_type) = param
              collect_react_utility_interfaces_from_type(
                info,
                rewrite_type_refs_in_scope(
                  info,
                  exported.local_name_prefix,
                  param_type,
                  canonical_types,
                ),
                modules,
                canonical_types,
                seen_names,
                interfaces,
              )
            }
          None => ()
        }
      }
      None => ()
    }
  }
  interfaces
}

///|
fn normalize_specialized_node_interfaces(
  exported_interfaces : Array[ExportedInterfaceDecl],
) -> Array[@ast.TsInterface] {
  let interfaces : Array[@ast.TsInterface] = []
  let exported_names : Array[String] = []
  let mut needs_cpu_info_times = false
  let mut needs_crypto_helpers = false
  let mut needs_vitest_environment_helpers = false
  for exported in exported_interfaces {
    exported_names.push(exported.export_name)
    exported_names.push(exported.local_name)
    if exported.export_name == "CpuInfo" || exported.local_name == "CpuInfo" {
      needs_cpu_info_times = true
    }
    if exported.export_name == "CipherGCM" ||
      exported.local_name == "CipherGCM" ||
      exported.export_name == "SubtleCrypto" ||
      exported.local_name == "SubtleCrypto" ||
      exported.export_name == "WebcryptoSubtleCrypto" ||
      exported.local_name == "WebcryptoSubtleCrypto" ||
      exported.export_name == "Argon2Parameters" ||
      exported.local_name == "Argon2Parameters" {
      needs_crypto_helpers = true
    }
    if exported.export_name == "Environment" ||
      exported.local_name == "Environment" {
      needs_vitest_environment_helpers = true
    }
  }
  if needs_cpu_info_times {
    interfaces.push({
      name: "CpuInfoTimes",
      type_params: [],
      extends_names: [],
      extends_args: [],
      fields: [
        ("user", @ast.TsType::Number),
        ("nice", @ast.TsType::Number),
        ("sys", @ast.TsType::Number),
        ("idle", @ast.TsType::Number),
        ("irq", @ast.TsType::Number),
      ],
      readonly_fields: [],
      index_signatures: [],
    })
  }
  if needs_crypto_helpers {
    if !exported_names.contains("CipherAADOptions") {
      interfaces.push({
        name: "CipherAADOptions",
        type_params: [],
        extends_names: [],
        extends_args: [],
        fields: [("plaintextLength", @ast.TsType::Number)],
        readonly_fields: [],
        index_signatures: [],
      })
    }
    if !exported_names.contains("GenerateKeyOptions") {
      interfaces.push({
        name: "GenerateKeyOptions",
        type_params: [],
        extends_names: [],
        extends_args: [],
        fields: [("length", @ast.TsType::Number)],
        readonly_fields: [],
        index_signatures: [],
      })
    }
    if !exported_names.contains("DiffieHellmanOptions") {
      interfaces.push({
        name: "DiffieHellmanOptions",
        type_params: [],
        extends_names: [],
        extends_args: [],
        fields: [
          ("privateKey", @ast.TsType::Named("KeyObject")),
          ("publicKey", @ast.TsType::Named("KeyObject")),
        ],
        readonly_fields: [],
        index_signatures: [],
      })
    }
  }
  if needs_vitest_environment_helpers &&
    !exported_names.contains("BuiltinEnvironments") {
    interfaces.push({
      name: "BuiltinEnvironments",
      type_params: [],
      extends_names: [],
      extends_args: [],
      fields: [
        ("node", @ast.TsType::Named("Environment")),
        ("jsdom", @ast.TsType::Named("Environment")),
      ],
      readonly_fields: [],
      index_signatures: [],
    })
  }
  interfaces
}

///|
fn should_expand_interface_base(origin : ResolvedInterfaceOrigin) -> Bool {
  origin.info.record.path.contains("@vitest/expect") ||
  origin.info.record.path.contains("callable-interface-reexport")
}

///|
fn append_lowered_interface_field(
  fields : Array[(String, @ast.TsType)],
  readonly_fields : Array[String],
  seen_field_names : Array[String],
  info : DeclModuleInfo,
  owner_name : String,
  field_name : String,
  field_type : @ast.TsType,
  is_readonly : Bool,
  modules : Map[String, DeclModuleInfo],
  canonical_types : Map[String, String],
) -> Unit {
  if seen_field_names.contains(field_name) {
    return
  }
  seen_field_names.push(field_name)
  let lowered_type = decl_specialize_generated_interface_field_type(
    owner_name,
    field_name,
    lower_react_utility_type(
      info,
      rewrite_type_refs(info, field_type, canonical_types),
      modules,
      canonical_types,
    ),
  )
  fields.push(
    (
      field_name,
      decl_rewrite_inline_callback_params_in_func_type(
        owner_name + "_" + field_name,
        lowered_type,
      ),
    ),
  )
  if is_readonly {
    readonly_fields.push(field_name)
  }
}

///|
fn append_interface_origin_fields(
  origin : ResolvedInterfaceOrigin,
  modules : Map[String, DeclModuleInfo],
  canonical_types : Map[String, String],
  fields : Array[(String, @ast.TsType)],
  readonly_fields : Array[String],
  seen_field_names : Array[String],
  seen_origins : Array[String],
) -> Unit {
  let origin_key = decl_key(origin.info.record.path, origin.iface.name)
  if seen_origins.contains(origin_key) {
    return
  }
  seen_origins.push(origin_key)
  for base_name in origin.iface.extends_names {
    match
      resolve_interface_origin(origin.info, base_name, modules, canonical_types) {
      Some(base_origin) =>
        if should_expand_interface_base(base_origin) {
          append_interface_origin_fields(
            base_origin, modules, canonical_types, fields, readonly_fields, seen_field_names,
            seen_origins,
          )
        }
      None => ()
    }
  }
  for field in origin.iface.fields {
    let (field_name, field_type) = field
    append_lowered_interface_field(
      fields,
      readonly_fields,
      seen_field_names,
      origin.info,
      origin.export_name,
      field_name,
      field_type,
      origin.iface.readonly_fields.contains(field_name),
      modules,
      canonical_types,
    )
  }
}

///|
fn clone_resolved_interface_origin(
  origin : ResolvedInterfaceOrigin,
  modules : Map[String, DeclModuleInfo],
  canonical_types : Map[String, String],
) -> @ast.TsInterface {
  let fields : Array[(String, @ast.TsType)] = []
  let readonly_fields : Array[String] = []
  let seen_field_names : Array[String] = []
  let seen_origins : Array[String] = []
  append_interface_origin_fields(
    origin, modules, canonical_types, fields, readonly_fields, seen_field_names,
    seen_origins,
  )
  {
    name: origin.export_name,
    type_params: origin.iface.type_params,
    extends_names: [],
    extends_args: [],
    fields,
    readonly_fields: readonly_fields_for_fields(readonly_fields, fields),
    index_signatures: origin.iface.index_signatures,
  }
}

///|
fn collect_interface_dependencies_from_type(
  info : DeclModuleInfo,
  type_ : @ast.TsType,
  modules : Map[String, DeclModuleInfo],
  canonical_types : Map[String, String],
  seen_names : Array[String],
  interfaces : Array[@ast.TsInterface],
) -> Unit {
  match type_ {
    Named(name) =>
      match resolve_interface_origin(info, name, modules, canonical_types) {
        Some(origin) => {
          let iface = clone_resolved_interface_origin(
            origin, modules, canonical_types,
          )
          if !seen_names.contains(iface.name) {
            seen_names.push(iface.name)
            interfaces.push(iface)
            for field in iface.fields {
              let (_, field_type) = field
              collect_interface_dependencies_from_type(
                origin.info,
                field_type,
                modules,
                canonical_types,
                seen_names,
                interfaces,
              )
            }
          }
        }
        None => ()
      }
    Applied(name, args) => {
      match resolve_interface_origin(info, name, modules, canonical_types) {
        Some(origin) => {
          let iface = clone_resolved_interface_origin(
            origin, modules, canonical_types,
          )
          if !seen_names.contains(iface.name) {
            seen_names.push(iface.name)
            interfaces.push(iface)
            for field in iface.fields {
              let (_, field_type) = field
              collect_interface_dependencies_from_type(
                origin.info,
                field_type,
                modules,
                canonical_types,
                seen_names,
                interfaces,
              )
            }
          }
        }
        None => ()
      }
      for arg in args {
        collect_interface_dependencies_from_type(
          info, arg, modules, canonical_types, seen_names, interfaces,
        )
      }
    }
    Array(inner) =>
      collect_interface_dependencies_from_type(
        info, inner, modules, canonical_types, seen_names, interfaces,
      )
    Tuple(items) | Union(items) | Intersection(items) =>
      for item in items {
        collect_interface_dependencies_from_type(
          info, item, modules, canonical_types, seen_names, interfaces,
        )
      }
    Object(fields) =>
      for field in fields {
        let (key_type, value_type) = field
        collect_interface_dependencies_from_type(
          info, key_type, modules, canonical_types, seen_names, interfaces,
        )
        collect_interface_dependencies_from_type(
          info, value_type, modules, canonical_types, seen_names, interfaces,
        )
      }
    Struct(name, fields) => {
      collect_interface_dependencies_from_type(
        info,
        Named(name),
        modules,
        canonical_types,
        seen_names,
        interfaces,
      )
      for field in fields {
        let (_, field_type) = field
        collect_interface_dependencies_from_type(
          info, field_type, modules, canonical_types, seen_names, interfaces,
        )
      }
    }
    Func(params, return_type) => {
      for param in params {
        collect_interface_dependencies_from_type(
          info, param, modules, canonical_types, seen_names, interfaces,
        )
      }
      collect_interface_dependencies_from_type(
        info, return_type, modules, canonical_types, seen_names, interfaces,
      )
    }
    _ => ()
  }
}

///|
fn collect_interface_dependencies(
  exported_interfaces : Array[ExportedInterfaceDecl],
  exported_imports : Array[ExportedImportDecl],
  exported_funcs : Array[ExportedFuncDecl],
  exported_values : Array[ExportedValueDecl],
  exported_classes : Array[ExportedClassDecl],
  modules : Map[String, DeclModuleInfo],
  canonical_types : Map[String, String],
  existing_interfaces : Array[@ast.TsInterface],
) -> Array[@ast.TsInterface] {
  let interfaces : Array[@ast.TsInterface] = []
  let seen_names : Array[String] = []
  for iface in existing_interfaces {
    seen_names.push(iface.name)
  }
  for exported in exported_interfaces {
    match modules.get(exported.source_path) {
      Some(info) =>
        for field in exported.iface.fields {
          let (_, field_type) = field
          collect_interface_dependencies_from_type(
            info,
            rewrite_type_refs(info, field_type, canonical_types),
            modules,
            canonical_types,
            seen_names,
            interfaces,
          )
        }
      None => ()
    }
  }
  for exported in exported_imports {
    match modules.get(exported.source_path) {
      Some(info) => {
        for param in exported.import_.params {
          let (_, param_type) = param
          collect_interface_dependencies_from_type(
            info,
            rewrite_type_refs_in_scope(
              info,
              exported.local_name_prefix,
              param_type,
              canonical_types,
            ),
            modules,
            canonical_types,
            seen_names,
            interfaces,
          )
        }
        collect_interface_dependencies_from_type(
          info,
          rewrite_type_refs_in_scope(
            info,
            exported.local_name_prefix,
            exported.import_.return_type,
            canonical_types,
          ),
          modules,
          canonical_types,
          seen_names,
          interfaces,
        )
      }
      None => ()
    }
  }
  for exported in exported_funcs {
    match modules.get(exported.source_path) {
      Some(info) => {
        for param in exported.func.params {
          collect_interface_dependencies_from_type(
            info,
            rewrite_type_refs_in_scope(
              info,
              exported.local_name_prefix,
              param.type_,
              canonical_types,
            ),
            modules,
            canonical_types,
            seen_names,
            interfaces,
          )
        }
        collect_interface_dependencies_from_type(
          info,
          rewrite_type_refs_in_scope(
            info,
            exported.local_name_prefix,
            exported.func.return_type,
            canonical_types,
          ),
          modules,
          canonical_types,
          seen_names,
          interfaces,
        )
      }
      None => ()
    }
  }
  for exported in exported_values {
    match modules.get(exported.source_path) {
      Some(info) =>
        collect_interface_dependencies_from_type(
          info,
          rewrite_type_refs_in_scope(
            info,
            exported.local_name_prefix,
            exported.value.type_,
            canonical_types,
          ),
          modules,
          canonical_types,
          seen_names,
          interfaces,
        )
      None => ()
    }
  }
  for exported in exported_classes {
    match modules.get(exported.source_path) {
      Some(info) => {
        for class_property in exported.class_.properties {
          collect_interface_dependencies_from_type(
            info,
            rewrite_type_refs_in_scope(
              info,
              exported.local_name_prefix,
              class_property.type_,
              canonical_types,
            ),
            modules,
            canonical_types,
            seen_names,
            interfaces,
          )
        }
        for class_method in exported.class_.methods {
          for param in class_method.params {
            let (_, param_type) = param
            collect_interface_dependencies_from_type(
              info,
              rewrite_type_refs_in_scope(
                info,
                exported.local_name_prefix,
                param_type,
                canonical_types,
              ),
              modules,
              canonical_types,
              seen_names,
              interfaces,
            )
          }
          collect_interface_dependencies_from_type(
            info,
            rewrite_type_refs_in_scope(
              info,
              exported.local_name_prefix,
              class_method.return_type,
              canonical_types,
            ),
            modules,
            canonical_types,
            seen_names,
            interfaces,
          )
        }
        match exported.class_.constructor_params {
          Some(params) =>
            for param in params {
              let (_, param_type) = param
              collect_interface_dependencies_from_type(
                info,
                rewrite_type_refs_in_scope(
                  info,
                  exported.local_name_prefix,
                  param_type,
                  canonical_types,
                ),
                modules,
                canonical_types,
                seen_names,
                interfaces,
              )
            }
          None => ()
        }
      }
      None => ()
    }
  }
  interfaces
}

///|
fn clone_exported_interface(
  exported : ExportedInterfaceDecl,
  info : DeclModuleInfo,
  modules : Map[String, DeclModuleInfo],
  canonical_types : Map[String, String],
) -> @ast.TsInterface {
  let fields : Array[(String, @ast.TsType)] = []
  let readonly_fields : Array[String] = []
  let seen_field_names : Array[String] = []
  let seen_origins : Array[String] = []
  append_interface_origin_fields(
    { info, export_name: exported.export_name, iface: exported.iface },
    modules,
    canonical_types,
    fields,
    readonly_fields,
    seen_field_names,
    seen_origins,
  )
  {
    name: exported.export_name,
    type_params: exported.iface.type_params,
    extends_names: [],
    extends_args: [],
    fields,
    readonly_fields: readonly_fields_for_fields(readonly_fields, fields),
    index_signatures: exported.iface.index_signatures,
  }
}

///|
fn clone_exported_enum(exported : ExportedEnumDecl) -> @ast.TsEnumDecl {
  { ..exported.enum_, name: exported.export_name }
}

///|
fn clone_exported_type_alias(
  exported : ExportedTypeAliasDecl,
  info : DeclModuleInfo,
  modules : Map[String, DeclModuleInfo],
  canonical_types : Map[String, String],
) -> @ast.TsTypeAlias {
  {
    name: exported.export_name,
    type_params: [],
    type_param_bounds: [],
    type_: lower_react_utility_type(
      info,
      rewrite_type_refs_in_scope(
        info,
        "",
        exported.type_alias.type_,
        canonical_types,
      ),
      modules,
      canonical_types,
    ),
  }
}

///|
fn clone_exported_import(
  exported : ExportedImportDecl,
  info : DeclModuleInfo,
  modules : Map[String, DeclModuleInfo],
  canonical_types : Map[String, String],
) -> @ast.TsImport {
  let params : Array[(String, @ast.TsType)] = []
  let callback_owner_name = if exported.source_export_name == "" ||
    exported.source_export_name == "default" ||
    exported.source_export_name.has_prefix("default.") {
    exported.export_name
  } else {
    exported.source_export_name
  }
  for param_index, param in exported.import_.params {
    let (param_name, param_type) = param
    let lowered = lower_react_utility_type(
      info,
      rewrite_type_refs_in_scope(
        info,
        exported.local_name_prefix,
        param_type,
        canonical_types,
      ),
      modules,
      canonical_types,
    )
    params.push(
      (
        param_name,
        decl_rewrite_inline_callback_param_type(
          callback_owner_name,
          param_name,
          param_index,
          decl_specialize_generated_api_param_type(
            callback_owner_name,
            param_name,
            param_index,
            decl_widen_react_factory_tag_param(
              exported.export_name,
              param_index,
              lowered,
            ),
          ),
        ),
      ),
    )
  }
  let return_type = lower_react_utility_type(
    info,
    rewrite_type_refs_in_scope(
      info,
      exported.local_name_prefix,
      exported.import_.return_type,
      canonical_types,
    ),
    modules,
    canonical_types,
  )
  let return_type = decl_specialize_generated_api_return_type(
    exported.export_name,
    return_type,
  )
  {
    name: exported.export_name,
    module_: exported.import_.module_,
    type_params: exported.import_.type_params,
    params,
    return_type: rewrite_inline_result_return_type(
      exported.export_name,
      return_type,
    ),
  }
}

///|
fn decl_is_react_factory_name(name : String) -> Bool {
  name == "createElement" || name == "jsx" || name == "jsxs"
}

///|
fn decl_specialize_generated_api_param_type(
  export_name : String,
  param_name : String,
  param_index : Int,
  type_ : @ast.TsType,
) -> @ast.TsType {
  match export_name {
    "createHmac" => if param_index == 1 { return Named("CipherKey") }
    "hash" =>
      if param_index == 2 {
        return decl_named_optional_type(
          "OneShotDigestOptionsWithStringEncoding",
        )
      }
    "hkdf" | "hkdfSync" => if param_index == 1 { return Named("CipherKey") }
    "sign" | "verify" => if param_index == 2 { return Named("KeyLike") }
    "decapsulate" =>
      if param_index == 0 {
        return Named("KeyLike")
      } else if param_index == 1 {
        return Named("BinaryLike")
      }
    "encapsulate" => if param_index == 0 { return Named("KeyLike") }
    "generateKey" | "generateKeySync" =>
      if param_index == 1 {
        return Named("GenerateKeyOptions")
      }
    "generateKeyPair" =>
      if param_index == 2 {
        return decl_crypto_generate_key_pair_callback_type(type_)
      }
    "diffieHellman" =>
      if param_index == 0 {
        return Named("DiffieHellmanOptions")
      }
    "getCipherInfo" => if param_index == 0 { return String_ }
    "publicDecrypt" | "publicEncrypt" | "privateDecrypt" | "privateEncrypt" =>
      if param_index == 0 {
        return Named("KeyLike")
      } else if param_index == 1 {
        return Named("BinaryLike")
      }
    "createPublicKey" | "createPrivateKey" =>
      if param_index == 0 {
        return Named("KeyLike")
      }
    _ => ()
  }
  if param_index == 0 &&
    (export_name == "fileURLToPath" || export_name == "fileURLToPathBuffer") {
    return String_
  }
  if param_index == 0 && (export_name == "isUtf8" || export_name == "isAscii") {
    return Named("Uint8Array")
  }
  // Preact / React `isValidElement(vnode: any): vnode is ReactElement` is a
  // type guard whose runtime cost is just a property check; lower the
  // parameter to the bridge's already-declared `VNode` opaque so MoonBit
  // callers can pass the typed VNode they already have without a manual
  // cast through JSValue.
  if export_name == "isValidElement" && param_index == 0 {
    return Named("VNode")
  }
  if param_name == "data" && decl_is_node_file_data_union(type_) {
    return String_
  }
  if decl_is_node_read_file_api_name(export_name) && param_name == "options" {
    return decl_node_read_file_options_type(type_)
  }
  match export_name {
    "createSourceFile" | "createLanguageServiceSourceFile" =>
      if param_index == 2 {
        Named("ScriptTarget")
      } else {
        type_
      }
    "visitEachChild" =>
      if param_index == 1 {
        Func([Named("Node")], Named("Node"))
      } else {
        type_
      }
    "transform" =>
      if param_index == 0 {
        Named("SourceFile")
      } else if param_index == 1 {
        Array(
          Func(
            [Named("TransformationContext")],
            Func([Named("SourceFile")], Named("SourceFile")),
          ),
        )
      } else {
        type_
      }
    "cp" | "cpSync" =>
      if (param_name == "source" || param_name == "destination") &&
        decl_is_node_string_url_union(type_) {
        String_
      } else {
        type_
      }
    "glob" | "globSync" =>
      if param_name == "pattern" && decl_is_string_or_string_array_union(type_) {
        String_
      } else {
        type_
      }
    "createReadStream" =>
      if param_name == "options" &&
        @checker.type_contains_named(type_, ["ReadStreamOptions"]) {
        Named("ReadStreamOptions")
      } else {
        type_
      }
    "createWriteStream" =>
      if param_name == "options" &&
        @checker.type_contains_named(type_, ["WriteStreamOptions"]) {
        Named("WriteStreamOptions")
      } else {
        type_
      }
    _ => type_
  }
}

///|
fn decl_is_node_read_file_api_name(name : String) -> Bool {
  name == "readFileSync" ||
  name == "readFile.__promisify__" ||
  name == "readFilePromisify"
}

///|
fn decl_struct_field_type(
  fields : Array[(String, @ast.TsType)],
  name : String,
) -> @ast.TsType? {
  for field in fields {
    if field.0 == name {
      return Some(field.1)
    }
  }
  None
}

///|
fn decl_object_type_field_type(
  fields : Array[(@ast.TsType, @ast.TsType)],
  name : String,
) -> @ast.TsType? {
  for field in fields {
    match field.0 {
      Literal(key) if key == name => return Some(field.1)
      _ => ()
    }
  }
  None
}

///|
fn decl_type_is_read_file_buffer_options(type_ : @ast.TsType) -> Bool {
  match @checker.classify_optional_like_union(type_) {
    Some((inner, _)) => return decl_type_is_read_file_buffer_options(inner)
    None => ()
  }
  if @checker.type_contains_named(type_, ["BufferEncoding"]) {
    return false
  }
  match type_ {
    Object(fields) =>
      match decl_object_type_field_type(fields, "encoding") {
        Some(_) => true
        None => false
      }
    Struct(_, fields) =>
      match decl_struct_field_type(fields, "encoding") {
        Some(_) => true
        None => false
      }
    _ => false
  }
}

///|
fn decl_node_read_file_options_type(type_ : @ast.TsType) -> @ast.TsType {
  if decl_type_is_read_file_buffer_options(type_) {
    return Union([Named("ReadFileBufferOptions"), Undefined])
  }
  if @checker.type_contains_named(type_, ["BufferEncoding"]) {
    match @checker.classify_optional_like_union(type_) {
      Some((_, true)) => Union([Named("BufferEncoding"), Undefined])
      _ => Named("BufferEncoding")
    }
  } else {
    type_
  }
}

///|
fn decl_type_has_optional_member(type_ : @ast.TsType) -> Bool {
  match type_ {
    Undefined | Null => true
    Union(items) => {
      for item in items {
        if decl_type_has_optional_member(item) {
          return true
        }
      }
      false
    }
    _ => false
  }
}

///|
fn decl_optionalize_if_needed(
  original : @ast.TsType,
  rewritten : @ast.TsType,
) -> @ast.TsType {
  if decl_type_has_optional_member(original) {
    Union([rewritten, Undefined])
  } else {
    rewritten
  }
}

// `decl_type_contains_boolean` moved to checker as `type_contains_boolean`.

///|
fn decl_copy_options_filter_type(type_ : @ast.TsType) -> @ast.TsType {
  let inner_type = match @checker.classify_optional_like_union(type_) {
    Some((inner, _)) => inner
    None => type_
  }
  match inner_type {
    Func([String_, String_], return_type) if @checker.type_contains_boolean(
        return_type,
      ) => decl_optionalize_if_needed(type_, Func([String_, String_], Boolean))
    _ => type_
  }
}

///|
fn decl_glob_options_cwd_type(type_ : @ast.TsType) -> @ast.TsType {
  if @checker.type_contains_string(type_) {
    decl_optionalize_if_needed(type_, String_)
  } else {
    type_
  }
}

///|
fn decl_glob_options_exclude_type(type_ : @ast.TsType) -> @ast.TsType {
  if @checker.type_contains_string_array(type_) {
    decl_optionalize_if_needed(type_, Array(String_))
  } else {
    type_
  }
}

///|
fn decl_specialize_generated_api_return_type(
  export_name : String,
  type_ : @ast.TsType,
) -> @ast.TsType {
  match export_name {
    "visitEachChild" => Named("Node")
    _ => type_
  }
}

///|
fn decl_specialize_generated_class_property_type(
  class_name : String,
  property_name : String,
  type_ : @ast.TsType,
) -> @ast.TsType {
  match class_name {
    "ReadStream" | "WriteStream" =>
      if property_name == "path" && decl_is_node_string_buffer_union(type_) {
        Named("PathLike")
      } else {
        type_
      }
    _ => type_
  }
}

///|
fn decl_watch_options_encoding_type(type_ : @ast.TsType) -> @ast.TsType {
  match type_ {
    Named("BufferEncoding") | String_ | Literal(_) => String_
    Union(items) => {
      let mut is_optional = false
      let mut is_encoding_only = true
      for item in items {
        match item {
          Named("BufferEncoding") | String_ | Literal(_) => ()
          Undefined | Null => is_optional = true
          _ => is_encoding_only = false
        }
      }
      if is_encoding_only {
        if is_optional {
          Union([String_, Undefined])
        } else {
          String_
        }
      } else {
        type_
      }
    }
    _ => type_
  }
}

///|
fn decl_string_optional_type() -> @ast.TsType {
  Union([String_, Undefined])
}

///|
fn decl_named_optional_type(name : String) -> @ast.TsType {
  Union([Named(name), Undefined])
}

///|
fn decl_url_pattern_base_url_type(type_ : @ast.TsType) -> @ast.TsType {
  match @checker.classify_optional_like_union(type_) {
    Some(_) => decl_string_optional_type()
    None =>
      match type_ {
        Any | String_ | Named("URL") => decl_string_optional_type()
        Union(_) if @checker.type_contains_string(type_) =>
          decl_string_optional_type()
        _ => type_
      }
  }
}

///|
fn decl_url_pattern_method_type(type_ : @ast.TsType) -> @ast.TsType {
  match type_ {
    Func(params, return_type) if params.length() == 2 => {
      let rewritten : Array[@ast.TsType] = [
        params[0],
        decl_string_optional_type(),
      ]
      Func(rewritten, return_type)
    }
    _ => type_
  }
}

///|
fn decl_url_search_params_this_arg_type(type_ : @ast.TsType) -> @ast.TsType {
  match @checker.classify_optional_like_union(type_) {
    Some(_) => decl_named_optional_type("URLSearchParamsForEachThisArg")
    None =>
      match type_ {
        Any => decl_named_optional_type("URLSearchParamsForEachThisArg")
        _ => type_
      }
  }
}

///|
fn decl_url_search_params_for_each_type(type_ : @ast.TsType) -> @ast.TsType {
  match type_ {
    Func(params, return_type) if params.length() == 2 => {
      let rewritten : Array[@ast.TsType] = [
        params[0],
        decl_url_search_params_this_arg_type(params[1]),
      ]
      Func(rewritten, return_type)
    }
    _ => type_
  }
}

///|
fn decl_is_crypto_aad_owner(owner_name : String) -> Bool {
  owner_name == "CipherCCM" ||
  owner_name == "CipherGCM" ||
  owner_name == "CipherOCB" ||
  owner_name == "CipherChaCha20Poly1305" ||
  owner_name == "DecipherCCM" ||
  owner_name == "DecipherGCM" ||
  owner_name == "DecipherOCB" ||
  owner_name == "DecipherChaCha20Poly1305"
}

///|
fn decl_crypto_aad_options_type(
  owner_name : String,
  original : @ast.TsType,
) -> @ast.TsType {
  if decl_type_has_optional_member(original) ||
    owner_name == "CipherGCM" ||
    owner_name == "CipherOCB" ||
    owner_name == "DecipherGCM" ||
    owner_name == "DecipherOCB" {
    decl_named_optional_type("CipherAADOptions")
  } else {
    Named("CipherAADOptions")
  }
}

///|
fn decl_crypto_set_aad_method_type(
  owner_name : String,
  type_ : @ast.TsType,
) -> @ast.TsType {
  match type_ {
    Func(params, return_type) if params.length() >= 2 => {
      let rewritten : Array[@ast.TsType] = []
      for param_index, param in params {
        if param_index == 1 {
          rewritten.push(decl_crypto_aad_options_type(owner_name, param))
        } else {
          rewritten.push(param)
        }
      }
      Func(rewritten, return_type)
    }
    _ => type_
  }
}

///|
fn decl_is_crypto_subtle_owner(owner_name : String) -> Bool {
  owner_name == "SubtleCrypto" || owner_name == "WebcryptoSubtleCrypto"
}

///|
fn decl_crypto_subtle_algorithm_param_type(
  owner_name : String,
  method_name : String,
  param_index : Int,
) -> @ast.TsType? {
  if !decl_is_crypto_subtle_owner(owner_name) {
    return None
  }
  match method_name {
    "decrypt"
    | "deriveBits"
    | "digest"
    | "encrypt"
    | "generateKey"
    | "sign"
    | "verify" =>
      if param_index == 0 {
        Some(Named("AlgorithmIdentifier"))
      } else {
        None
      }
    "deriveKey" =>
      if param_index == 0 || param_index == 2 {
        Some(Named("AlgorithmIdentifier"))
      } else {
        None
      }
    "decapsulateKey" =>
      if param_index == 3 {
        Some(Named("AlgorithmIdentifier"))
      } else {
        None
      }
    "encapsulateKey" =>
      if param_index == 2 {
        Some(Named("AlgorithmIdentifier"))
      } else {
        None
      }
    "importKey" =>
      if param_index == 2 {
        Some(Named("AlgorithmIdentifier"))
      } else {
        None
      }
    "unwrapKey" =>
      if param_index == 3 || param_index == 4 {
        Some(Named("AlgorithmIdentifier"))
      } else {
        None
      }
    "wrapKey" =>
      if param_index == 3 {
        Some(Named("AlgorithmIdentifier"))
      } else {
        None
      }
    _ => None
  }
}

///|
fn decl_crypto_subtle_method_type(
  owner_name : String,
  method_name : String,
  type_ : @ast.TsType,
) -> @ast.TsType {
  match type_ {
    Func(params, return_type) => {
      let rewritten : Array[@ast.TsType] = []
      for param_index, param in params {
        match
          decl_crypto_subtle_algorithm_param_type(
            owner_name, method_name, param_index,
          ) {
          Some(rewritten_param) => rewritten.push(rewritten_param)
          None => rewritten.push(param)
        }
      }
      Func(rewritten, return_type)
    }
    _ => type_
  }
}

///|
fn decl_crypto_get_random_values_type(type_ : @ast.TsType) -> @ast.TsType {
  match type_ {
    Func(params, _) if params.length() == 1 =>
      Func(
        [Named("NodeJS_NonSharedTypedArray")],
        Named("NodeJS_NonSharedTypedArray"),
      )
    _ => type_
  }
}

///|
fn decl_crypto_generate_key_pair_callback_type(
  type_ : @ast.TsType,
) -> @ast.TsType {
  match type_ {
    Func(params, return_type) if params.length() == 3 =>
      Func([params[0], Named("KeyObject"), Named("KeyObject")], return_type)
    _ => type_
  }
}

///|
fn decl_is_hono_route_method(method_name : String) -> Bool {
  method_name == "get" ||
  method_name == "hono_get" ||
  method_name == "post" ||
  method_name == "hono_post" ||
  method_name == "put" ||
  method_name == "hono_put" ||
  method_name == "delete" ||
  method_name == "hono_delete" ||
  method_name == "options" ||
  method_name == "hono_options" ||
  method_name == "patch" ||
  method_name == "hono_patch" ||
  method_name == "all" ||
  method_name == "hono_all"
}

///|
fn decl_hono_handler_type() -> @ast.TsType {
  Func([Named("Context")], Named("Response"))
}

///|
fn decl_is_hono_context_response_method(method_name : String) -> Bool {
  method_name == "body" ||
  method_name == "context_body" ||
  method_name == "text" ||
  method_name == "context_text" ||
  method_name == "json" ||
  method_name == "context_json" ||
  method_name == "html" ||
  method_name == "context_html" ||
  method_name == "redirect" ||
  method_name == "context_redirect"
}

///|
fn decl_promise_named_type(name : String) -> @ast.TsType {
  Applied("Promise", [Named(name)])
}

///|
fn decl_vitest_environment_setup_type(type_ : @ast.TsType) -> @ast.TsType {
  match type_ {
    Func(params, _) if params.length() == 2 =>
      Func([params[0], params[1]], decl_promise_named_type("EnvironmentReturn"))
    _ => type_
  }
}

///|
fn decl_vitest_environment_setup_vm_type(type_ : @ast.TsType) -> @ast.TsType {
  let params = match type_ {
    Func(params, _) => params
    _ => [Named("StringRecordOfAny")]
  }
  if params.length() == 1 {
    Union([
      Func([params[0]], decl_promise_named_type("VmEnvironmentReturn")),
      Undefined,
    ])
  } else {
    type_
  }
}

///|
fn decl_vitest_environment_return_teardown_type(
  type_ : @ast.TsType,
) -> @ast.TsType {
  match type_ {
    Func(params, _) if params.length() == 1 =>
      Func([params[0]], Applied("Promise", [Void]))
    _ => type_
  }
}

///|
fn decl_vitest_vm_environment_return_teardown_type(
  type_ : @ast.TsType,
) -> @ast.TsType {
  match type_ {
    Func(params, _) if params.length() == 0 =>
      Func([], Applied("Promise", [Void]))
    _ => type_
  }
}

///|
fn decl_specialize_generated_interface_field_type(
  owner_name : String,
  field_name : String,
  type_ : @ast.TsType,
) -> @ast.TsType {
  // Builder-style methods like `setIssuer(): this` parse as `Named("This")`.
  // Rewrite the function-typed-field's return so chained calls keep
  // type-checking on the owning interface / class.
  let type_ = decl_replace_this_in_function_return(type_, owner_name)
  if decl_is_crypto_aad_owner(owner_name) && field_name == "setAAD" {
    return decl_crypto_set_aad_method_type(owner_name, type_)
  }
  if decl_is_crypto_subtle_owner(owner_name) {
    return decl_crypto_subtle_method_type(owner_name, field_name, type_)
  }
  if owner_name == "WebcryptoCrypto" && field_name == "getRandomValues" {
    return decl_crypto_get_random_values_type(type_)
  }
  match owner_name {
    "CpuInfo" =>
      if field_name == "times" {
        Named("CpuInfoTimes")
      } else {
        type_
      }
    "UserInfo" =>
      if field_name == "username" || field_name == "homedir" {
        String_
      } else if field_name == "shell" {
        decl_string_optional_type()
      } else {
        type_
      }
    "UserInfoOptions" =>
      if field_name == "encoding" {
        decl_named_optional_type("BufferEncoding")
      } else {
        type_
      }
    "Url" =>
      if field_name == "query" {
        decl_string_optional_type()
      } else {
        type_
      }
    "UrlObject" =>
      if field_name == "port" {
        decl_string_optional_type()
      } else if field_name == "query" {
        decl_named_optional_type("ParsedUrlQueryInput")
      } else {
        type_
      }
    "URLPattern" =>
      if field_name == "exec" || field_name == "test" {
        decl_url_pattern_method_type(type_)
      } else {
        type_
      }
    "URLSearchParams" =>
      if field_name == "forEach" {
        decl_url_search_params_for_each_type(type_)
      } else {
        type_
      }
    "Environment" =>
      if field_name == "viteEnvironment" {
        decl_string_optional_type()
      } else if field_name == "setup" {
        decl_vitest_environment_setup_type(type_)
      } else if field_name == "setupVM" {
        decl_vitest_environment_setup_vm_type(type_)
      } else {
        type_
      }
    "EnvironmentReturn" =>
      if field_name == "teardown" {
        decl_vitest_environment_return_teardown_type(type_)
      } else {
        type_
      }
    "VmEnvironmentReturn" =>
      if field_name == "getVmContext" {
        Func([], Named("StringRecordOfAny"))
      } else if field_name == "teardown" {
        decl_vitest_vm_environment_return_teardown_type(type_)
      } else {
        type_
      }
    "PublicKeyInput" =>
      if field_name == "key" {
        Named("BinaryLike")
      } else {
        type_
      }
    "PrivateKeyInput" =>
      if field_name == "key" {
        Named("BinaryLike")
      } else if field_name == "passphrase" {
        decl_named_optional_type("BinaryLike")
      } else {
        type_
      }
    "SigningOptions" =>
      if field_name == "context" {
        decl_named_optional_type("NodeJS_BufferSource")
      } else {
        type_
      }
    "Argon2Parameters" =>
      if field_name == "message" || field_name == "nonce" {
        Named("BinaryLike")
      } else if field_name == "secret" || field_name == "associatedData" {
        decl_named_optional_type("BinaryLike")
      } else {
        type_
      }
    "KeyPairExportResult" =>
      if field_name == "publicKey" || field_name == "privateKey" {
        Named("KeyObject")
      } else {
        type_
      }
    "KeyPairExportOptions" =>
      if field_name == "publicKeyEncoding" {
        decl_named_optional_type("PublicKeyExportOptions")
      } else if field_name == "privateKeyEncoding" {
        decl_named_optional_type("PrivateKeyExportOptions")
      } else {
        type_
      }
    "PrivateKeyExportOptions" =>
      if field_name == "passphrase" {
        decl_named_optional_type("BinaryLike")
      } else {
        type_
      }
    "OneShotDigestOptions" =>
      if field_name == "outputEncoding" {
        decl_named_optional_type("BinaryToTextEncoding")
      } else {
        type_
      }
    "ReadStreamEventMap" =>
      if field_name == "data" {
        decl_stream_event_payload_array_type("ReadStream", type_)
      } else {
        type_
      }
    "Utf8StreamEventMap" =>
      if field_name == "drop" {
        decl_stream_event_payload_array_type("Utf8Stream", type_)
      } else {
        type_
      }
    "FSWatcherEventMap" =>
      if field_name == "change" {
        match type_ {
          Array(_) | Tuple(_) => Array(Named("FSWatcherChangeEventPayload"))
          _ => type_
        }
      } else {
        type_
      }
    "WatchOptions" =>
      if field_name == "encoding" {
        decl_watch_options_encoding_type(type_)
      } else {
        type_
      }
    "CopyOptions" =>
      if field_name == "filter" {
        decl_copy_options_filter_type(type_)
      } else {
        type_
      }
    "_GlobOptions" =>
      if field_name == "cwd" {
        decl_glob_options_cwd_type(type_)
      } else if field_name == "exclude" {
        decl_glob_options_exclude_type(type_)
      } else {
        type_
      }
    "StatSyncFn" =>
      if field_name == "<call>" {
        match type_ {
          Func([Named("PathLike"), _], Named("Stats")) =>
            Func(
              [Named("PathLike"), Union([Named("StatSyncOptions"), Undefined])],
              Named("Stats"),
            )
          _ => type_
        }
      } else {
        type_
      }
    _ => type_
  }
}

///|
fn decl_stream_event_payload_name(class_name : String) -> String? {
  match class_name {
    "ReadStream" => Some("ReadStreamEventPayload")
    "WriteStream" => Some("WriteStreamEventPayload")
    "Utf8Stream" => Some("Utf8StreamEventPayload")
    _ => None
  }
}

///|
fn decl_stream_event_payload_type(class_name : String) -> @ast.TsType? {
  match decl_stream_event_payload_name(class_name) {
    Some(name) => Some(Named(name))
    None => None
  }
}

///|
fn decl_stream_event_payload_array_type(
  class_name : String,
  type_ : @ast.TsType,
) -> @ast.TsType {
  match decl_stream_event_payload_type(class_name) {
    Some(payload_type) =>
      match type_ {
        Array(_) | Tuple(_) => Array(payload_type)
        _ => type_
      }
    None => type_
  }
}

///|
fn decl_stream_listener_func_type(
  class_name : String,
  type_ : @ast.TsType,
) -> @ast.TsType {
  match @checker.classify_optional_like_union(type_) {
    Some((inner, is_optional)) => {
      let rewritten = decl_stream_listener_func_type(class_name, inner)
      if rewritten == inner {
        type_
      } else if is_optional {
        Union([rewritten, Undefined])
      } else {
        rewritten
      }
    }
    None =>
      match decl_stream_event_payload_type(class_name) {
        Some(payload_type) =>
          match type_ {
            Func([_], Void) => Func([payload_type], Void)
            _ => type_
          }
        None => type_
      }
  }
}

///|
fn decl_stream_listener_array_type(
  class_name : String,
  type_ : @ast.TsType,
) -> @ast.TsType {
  match type_ {
    Array(inner) => {
      let rewritten = decl_stream_listener_func_type(class_name, inner)
      if rewritten == inner {
        type_
      } else {
        Array(rewritten)
      }
    }
    _ => type_
  }
}

///|
fn decl_is_stream_listener_method(method_name : String) -> Bool {
  method_name == "addListener" ||
  method_name == "off" ||
  method_name == "on" ||
  method_name == "once" ||
  method_name == "prependListener" ||
  method_name == "prependOnceListener" ||
  method_name == "removeListener" ||
  method_name == "listenerCount"
}

///|
fn decl_is_stream_listener_array_method(method_name : String) -> Bool {
  method_name == "listeners" || method_name == "rawListeners"
}

///|
fn decl_specialize_generated_class_method_param_type(
  class_name : String,
  method_name : String,
  _param_name : String,
  param_index : Int,
  type_ : @ast.TsType,
) -> @ast.TsType {
  if class_name == "Hono" && decl_is_hono_route_method(method_name) {
    if param_index == 0 {
      return String_
    }
    if param_index == 1 {
      return decl_hono_handler_type()
    }
  }
  if class_name == "Context" &&
    decl_is_hono_context_response_method(method_name) {
    match method_name {
      "text" | "context_text" | "html" | "context_html" =>
        if param_index == 0 {
          return String_
        } else if param_index == 1 {
          return decl_named_optional_type("StatusCode")
        }
      "body" | "context_body" =>
        if param_index == 0 {
          return Named("Data")
        } else if param_index == 1 {
          return decl_named_optional_type("StatusCode")
        }
      "json" | "context_json" =>
        if param_index == 1 {
          return decl_named_optional_type("StatusCode")
        }
      "redirect" | "context_redirect" =>
        if param_index == 0 {
          return String_
        } else if param_index == 1 {
          return decl_named_optional_type("StatusCode")
        }
      _ => ()
    }
  }
  if decl_is_crypto_aad_owner(class_name) &&
    method_name == "setAAD" &&
    param_index == 1 {
    return decl_crypto_aad_options_type(class_name, type_)
  }
  match
    decl_crypto_subtle_algorithm_param_type(
      class_name, method_name, param_index,
    ) {
    Some(rewritten_param) => return rewritten_param
    None => ()
  }
  if class_name == "WebcryptoCrypto" &&
    method_name == "getRandomValues" &&
    param_index == 0 {
    return Named("NodeJS_NonSharedTypedArray")
  }
  if class_name == "Sign" && method_name == "sign" && param_index == 0 {
    return Named("KeyLike")
  }
  if class_name == "Verify" && method_name == "verify" && param_index == 0 {
    return Named("KeyLike")
  }
  if class_name == "KeyObject" &&
    method_name == "toCryptoKey" &&
    param_index == 0 {
    return Named("AlgorithmIdentifier")
  }
  if class_name == "DiffieHellman" &&
    method_name == "computeSecret" &&
    (param_index == 1 || param_index == 2) {
    return decl_named_optional_type("BufferEncoding")
  }
  if class_name == "ECDH" && method_name == "getPublicKey" && param_index == 0 {
    return decl_named_optional_type("BufferEncoding")
  }
  if class_name == "URLPattern" &&
    (method_name == "exec" || method_name == "test") &&
    param_index == 1 {
    return decl_url_pattern_base_url_type(type_)
  }
  if class_name == "URLSearchParams" &&
    method_name == "forEach" &&
    param_index == 1 {
    return decl_url_search_params_this_arg_type(type_)
  }
  match decl_stream_event_payload_name(class_name) {
    Some(_) => ()
    None => return type_
  }
  if decl_is_stream_listener_method(method_name) && param_index == 1 {
    decl_stream_listener_func_type(class_name, type_)
  } else if method_name == "emit" && param_index == 1 {
    match decl_stream_event_payload_type(class_name) {
      Some(payload_type) => payload_type
      None => type_
    }
  } else {
    type_
  }
}

///|
fn decl_specialize_generated_class_method_return_type(
  class_name : String,
  method_name : String,
  type_ : @ast.TsType,
) -> @ast.TsType {
  // TypeScript `this` types in builder-style chains (`setIssuedAt(): this`)
  // are parsed as `Named("This")`. Replace them with the owning class so
  // chained calls keep type-checking.
  let type_ = decl_replace_this_type(type_, class_name)
  if class_name == "Context" &&
    decl_is_hono_context_response_method(method_name) {
    return Named("Response")
  }
  if class_name == "KeyObject" && method_name == "export" {
    return Named("NonSharedBuffer")
  }
  if class_name == "ECDH" && method_name == "convertKey" {
    return Named("NonSharedBuffer")
  }
  if class_name == "WebcryptoCrypto" && method_name == "getRandomValues" {
    return Named("NodeJS_NonSharedTypedArray")
  }
  match decl_stream_event_payload_name(class_name) {
    Some(_) => ()
    None => return type_
  }
  if decl_is_stream_listener_array_method(method_name) {
    decl_stream_listener_array_type(class_name, type_)
  } else {
    type_
  }
}

///|
fn decl_replace_this_in_function_return(
  type_ : @ast.TsType,
  owner_name : String,
) -> @ast.TsType {
  match type_ {
    @ast.TsType::Func(params, return_type) =>
      @ast.TsType::Func(params, decl_replace_this_type(return_type, owner_name))
    _ => type_
  }
}

///|
fn decl_replace_this_type(
  type_ : @ast.TsType,
  class_name : String,
) -> @ast.TsType {
  match type_ {
    @ast.TsType::Named(n) if n == "this" || n == "This" =>
      @ast.TsType::Named(class_name)
    @ast.TsType::Array(inner) =>
      @ast.TsType::Array(decl_replace_this_type(inner, class_name))
    @ast.TsType::Tuple(items) => {
      let next : Array[@ast.TsType] = []
      for item in items {
        next.push(decl_replace_this_type(item, class_name))
      }
      @ast.TsType::Tuple(next)
    }
    @ast.TsType::Union(items) => {
      let next : Array[@ast.TsType] = []
      for item in items {
        next.push(decl_replace_this_type(item, class_name))
      }
      @ast.TsType::Union(next)
    }
    @ast.TsType::Applied(name, args) => {
      let next_args : Array[@ast.TsType] = []
      for arg in args {
        next_args.push(decl_replace_this_type(arg, class_name))
      }
      @ast.TsType::Applied(name, next_args)
    }
    _ => type_
  }
}

///|
// `decl_type_is_named` and `decl_type_contains_named` moved to checker as
// `type_is_named` / `type_contains_named`.

// `decl_type_contains_string` and `decl_type_contains_string_array` moved to
// checker as `type_contains_string` / `type_contains_string_array`.

///|
fn decl_union_has_string_and_named(
  type_ : @ast.TsType,
  names : Array[String],
) -> Bool {
  match type_ {
    Union(items) => {
      let mut has_string = false
      let mut has_named = false
      for item in items {
        match item {
          String_ | Literal(_) => has_string = true
          _ => if @checker.type_is_named(item, names) { has_named = true }
        }
      }
      has_string && has_named
    }
    _ => false
  }
}

///|
fn decl_is_node_file_data_union(type_ : @ast.TsType) -> Bool {
  decl_union_has_string_and_named(type_, [
    "NodeJS.ArrayBufferView", "NodeJS_ArrayBufferView", "Uint8Array", "NonSharedBuffer",
    "Buffer",
  ])
}

///|
fn decl_is_node_string_url_union(type_ : @ast.TsType) -> Bool {
  decl_union_has_string_and_named(type_, ["URL"])
}

///|
fn decl_is_node_string_buffer_union(type_ : @ast.TsType) -> Bool {
  decl_union_has_string_and_named(type_, ["Buffer", "NonSharedBuffer"])
}

///|
fn decl_is_string_or_string_array_union(type_ : @ast.TsType) -> Bool {
  @checker.type_contains_string(type_) &&
  @checker.type_contains_string_array(type_)
}

// `decl_is_string_literal_union_type` moved to checker as
// `is_string_literal_union`.

///|
fn decl_querystring_stringify_type() -> @ast.TsType {
  Func(
    [
      decl_named_optional_type("ParsedUrlQueryInput"),
      decl_string_optional_type(),
      decl_string_optional_type(),
      decl_named_optional_type("StringifyOptions"),
    ],
    String_,
  )
}

///|
fn decl_querystring_parse_type() -> @ast.TsType {
  Func(
    [
      String_,
      decl_string_optional_type(),
      decl_string_optional_type(),
      decl_named_optional_type("ParseOptions"),
    ],
    Named("ParsedUrlQuery"),
  )
}

///|
fn decl_specialize_generated_value_type(
  value_name : String,
  type_ : @ast.TsType,
) -> @ast.TsType {
  match value_name {
    "builtinEnvironments" => Named("BuiltinEnvironments")
    "path" if type_ == Any => Named("PathModule")
    "constants" => Named("Constants")
    "encode" if type_ == Any => decl_querystring_stringify_type()
    "decode" if type_ == Any => decl_querystring_parse_type()
    _ => type_
  }
}

///|
fn decl_widen_react_factory_tag_param(
  export_name : String,
  param_index : Int,
  type_ : @ast.TsType,
) -> @ast.TsType {
  if param_index != 0 || !decl_is_react_factory_name(export_name) {
    return type_
  }
  if @checker.is_string_literal_union(type_) {
    String_
  } else {
    type_
  }
}

///|
fn decl_inline_callback_type_name(
  owner_name : String,
  param_name : String,
  param_index : Int,
) -> String {
  let safe_param_name = if param_name == "" {
    "arg" + param_index.to_string()
  } else {
    param_name
  }
  decl_to_pascal_case(owner_name) +
  decl_to_pascal_case(safe_param_name) +
  "Callback"
}

///|
fn decl_synthetic_callback_type_for_param(
  owner_name : String,
  param_name : String,
  param_index : Int,
) -> @ast.TsType? {
  if owner_name.length() > 10 && owner_name != "useActionState" {
    return None
  }
  let callback_type_name = decl_inline_callback_type_name(
    owner_name, param_name, param_index,
  )
  if callback_type_name.length() > 64 {
    None
  } else {
    Some(Named(callback_type_name))
  }
}

///|
fn decl_rewrite_inline_callback_param_type(
  owner_name : String,
  param_name : String,
  param_index : Int,
  type_ : @ast.TsType,
) -> @ast.TsType {
  match @checker.classify_optional_like_union(type_) {
    Some((Func(_, _), is_optional)) =>
      match
        decl_synthetic_callback_type_for_param(
          owner_name, param_name, param_index,
        ) {
        Some(named) =>
          if is_optional {
            Union([named, Undefined])
          } else {
            named
          }
        None => type_
      }
    _ =>
      match type_ {
        Func(_, _) =>
          match
            decl_synthetic_callback_type_for_param(
              owner_name, param_name, param_index,
            ) {
            Some(named) => named
            None => type_
          }
        _ => type_
      }
  }
}

///|
fn decl_rewrite_inline_callback_params_in_func_type(
  owner_name : String,
  type_ : @ast.TsType,
) -> @ast.TsType {
  match type_ {
    Func(params, return_type) => {
      let rewritten_params : Array[@ast.TsType] = []
      for param_index, param in params {
        rewritten_params.push(
          decl_rewrite_inline_callback_param_type(
            owner_name,
            "arg" + param_index.to_string(),
            param_index,
            param,
          ),
        )
      }
      Func(rewritten_params, return_type)
    }
    _ => type_
  }
}

// `decl_classify_optional_like_union` moved to `mizchi/ts/checker`. Bridge
// callers go through `@checker.classify_optional_like_union` directly. The
// shared implementation also normalizes literal members (Literal/NumberLiteral/
// BooleanLiteral/BigIntLiteral) before comparing, which is strictly more
// aggressive than the old decl-local version and matches the parser/ffi side.

///|
fn decl_type_widening_score(type_ : @ast.TsType) -> Int {
  match @checker.classify_optional_like_union(type_) {
    Some((inner, _)) => return decl_type_widening_score(inner)
    None => ()
  }
  match type_ {
    Any => 100
    Func(params, return_type) => {
      let mut score = 40 + decl_type_widening_score(return_type)
      for param in params {
        score += decl_type_widening_score(param)
      }
      score
    }
    Union(items) => {
      let mut score = 20
      for item in items {
        score += decl_type_widening_score(item)
      }
      score
    }
    Intersection(items) => {
      let mut score = 0
      for item in items {
        score += decl_type_widening_score(item)
      }
      score
    }
    Array(inner) => decl_type_widening_score(inner)
    Tuple(items) => {
      let mut score = 0
      for item in items {
        score += decl_type_widening_score(item)
      }
      score
    }
    Object(fields) => {
      let mut score = 0
      for field in fields {
        score += decl_type_widening_score(field.1)
      }
      score
    }
    Struct(_, fields) => {
      let mut score = 0
      for field in fields {
        score += decl_type_widening_score(field.1)
      }
      score
    }
    Applied(_, args) => {
      let mut score = 0
      for arg in args {
        score += decl_type_widening_score(arg)
      }
      score
    }
    _ => 0
  }
}

///|
fn decl_import_widening_score(import_ : @ast.TsImport) -> Int {
  let mut score = decl_type_widening_score(import_.return_type)
  for param in import_.params {
    score += decl_type_widening_score(param.1)
  }
  score
}

///|
fn decl_func_widening_score(func : @ast.TsFunc) -> Int {
  let mut score = decl_type_widening_score(func.return_type)
  for param in func.params {
    score += decl_type_widening_score(param.type_)
  }
  score
}

///|
fn push_preferred_import_decl(
  imports : Array[@ast.TsImport],
  import_ : @ast.TsImport,
) -> Unit {
  for i, existing in imports {
    if existing.name == import_.name &&
      existing.params.length() == import_.params.length() {
      if decl_import_widening_score(import_) <
        decl_import_widening_score(existing) {
        imports[i] = import_
      }
      return
    }
  }
  imports.push(import_)
}

///|
fn push_preferred_func_decl(
  funcs : Array[@ast.TsFunc],
  func : @ast.TsFunc,
) -> Unit {
  for i, existing in funcs {
    if existing.name == func.name &&
      existing.params.length() == func.params.length() {
      if decl_func_widening_score(func) < decl_func_widening_score(existing) {
        funcs[i] = func
      }
      return
    }
  }
  funcs.push(func)
}

// `decl_is_empty_object_type`, `decl_is_simple_primitive_type`,
// `decl_reduce_uniform_union`, and `decl_transparent_intersection_type` were
// straight duplicates of `mizchi/ts/checker` helpers; callers go through
// `@checker.is_empty_object_type` etc. directly.

///|
fn decl_normalize_overload_signature_type(type_ : @ast.TsType) -> @ast.TsType {
  match @checker.classify_optional_like_union(type_) {
    Some((inner, is_optional)) => {
      let normalized = decl_normalize_overload_signature_type(inner)
      if is_optional {
        return @ast.TsType::Union([normalized, @ast.TsType::Undefined])
      } else {
        return normalized
      }
    }
    None => ()
  }
  match @checker.classify_transparent_intersection(type_) {
    Some(inner) => return decl_normalize_overload_signature_type(inner)
    None => ()
  }
  match type_ {
    Union(items) => {
      let normalized : Array[@ast.TsType] = []
      for item in items {
        normalized.push(decl_normalize_overload_signature_type(item))
      }
      Union(normalized)
    }
    Array(inner) => Array(decl_normalize_overload_signature_type(inner))
    Tuple(items) => {
      let normalized : Array[@ast.TsType] = []
      for item in items {
        normalized.push(decl_normalize_overload_signature_type(item))
      }
      Tuple(normalized)
    }
    _ => type_
  }
}

///|
fn decl_overload_type_suffix(type_ : @ast.TsType) -> String? {
  let normalized_type = decl_normalize_overload_signature_type(type_)
  match @checker.classify_optional_like_union(normalized_type) {
    Some((inner, _)) =>
      match decl_overload_type_suffix(inner) {
        Some(suffix) => return Some(suffix + "_optional")
        None => return None
      }
    None => ()
  }
  match normalized_type {
    Literal(_) | String_ => Some("string")
    Number | NumberLiteral(_) => Some("number")
    Int => Some("int")
    Boolean | BooleanLiteral(_) => Some("bool")
    BigInt | BigIntLiteral(_) => Some("bigint")
    Symbol => Some("symbol")
    Named(name) if name != "any" && name != "Function" =>
      Some(decl_to_snake_case(name))
    Array(inner) =>
      match decl_overload_type_suffix(inner) {
        Some(suffix) => Some(suffix + "_array")
        None => None
      }
    _ => None
  }
}

///|
fn decl_overload_suffix_from_types(types : Array[@ast.TsType]) -> String? {
  if types.length() == 0 {
    return Some("no_args")
  }
  let parts : Array[String] = []
  for type_ in types {
    match decl_overload_type_suffix(type_) {
      Some(suffix) => parts.push(suffix)
      None => return None
    }
  }
  Some(parts.join("_"))
}

///|
fn decl_import_signature_types(import_ : @ast.TsImport) -> Array[@ast.TsType] {
  let types : Array[@ast.TsType] = []
  for param in import_.params {
    types.push(decl_normalize_overload_signature_type(param.1))
  }
  types
}

///|
fn decl_func_signature_types(func : @ast.TsFunc) -> Array[@ast.TsType] {
  let types : Array[@ast.TsType] = []
  for param in func.params {
    types.push(decl_normalize_overload_signature_type(param.type_))
  }
  types
}

///|
fn decl_import_same_signature(lhs : @ast.TsImport, rhs : @ast.TsImport) -> Bool {
  if lhs.return_type != rhs.return_type ||
    lhs.params.length() != rhs.params.length() {
    return false
  }
  for i in 0..<lhs.params.length() {
    if decl_normalize_overload_signature_type(lhs.params[i].1) !=
      decl_normalize_overload_signature_type(rhs.params[i].1) {
      return false
    }
  }
  true
}

///|
fn decl_import_same_params(lhs : @ast.TsImport, rhs : @ast.TsImport) -> Bool {
  if lhs.params.length() != rhs.params.length() {
    return false
  }
  for i in 0..<lhs.params.length() {
    if decl_normalize_overload_signature_type(lhs.params[i].1) !=
      decl_normalize_overload_signature_type(rhs.params[i].1) {
      return false
    }
  }
  true
}

///|
fn decl_func_same_signature(lhs : @ast.TsFunc, rhs : @ast.TsFunc) -> Bool {
  if lhs.return_type != rhs.return_type ||
    lhs.params.length() != rhs.params.length() {
    return false
  }
  for i in 0..<lhs.params.length() {
    if decl_normalize_overload_signature_type(lhs.params[i].type_) !=
      decl_normalize_overload_signature_type(rhs.params[i].type_) {
      return false
    }
  }
  true
}

///|
fn decl_func_same_params(lhs : @ast.TsFunc, rhs : @ast.TsFunc) -> Bool {
  if lhs.params.length() != rhs.params.length() {
    return false
  }
  for i in 0..<lhs.params.length() {
    if decl_normalize_overload_signature_type(lhs.params[i].type_) !=
      decl_normalize_overload_signature_type(rhs.params[i].type_) {
      return false
    }
  }
  true
}

///|
fn decl_import_wider_same_param_overload(
  candidate : @ast.TsImport,
  preferred : @ast.TsImport,
) -> Bool {
  decl_import_same_params(candidate, preferred) &&
  decl_type_widening_score(candidate.return_type) >
  decl_type_widening_score(preferred.return_type)
}

///|
fn decl_func_wider_same_param_overload(
  candidate : @ast.TsFunc,
  preferred : @ast.TsFunc,
) -> Bool {
  decl_func_same_params(candidate, preferred) &&
  decl_type_widening_score(candidate.return_type) >
  decl_type_widening_score(preferred.return_type)
}

///|
fn decl_import_wider_than_any_same_param_preferred(
  candidate : @ast.TsImport,
  preferred : Array[@ast.TsImport],
) -> Bool {
  for item in preferred {
    if decl_import_wider_same_param_overload(candidate, item) {
      return true
    }
  }
  false
}

///|
fn decl_func_wider_than_any_same_param_preferred(
  candidate : @ast.TsFunc,
  preferred : Array[@ast.TsFunc],
) -> Bool {
  for item in preferred {
    if decl_func_wider_same_param_overload(candidate, item) {
      return true
    }
  }
  false
}

///|
fn decl_type_is_string_nonshared_buffer_union(type_ : @ast.TsType) -> Bool {
  match type_ {
    Union(items) => {
      let mut has_string = false
      let mut has_buffer = false
      for item in items {
        match item {
          String_ => has_string = true
          Named("NonSharedBuffer") | Applied("NonSharedBuffer", _) =>
            has_buffer = true
          _ => ()
        }
      }
      has_string && has_buffer
    }
    Applied("Promise", [inner]) | Applied("PromiseLike", [inner]) =>
      decl_type_is_string_nonshared_buffer_union(inner)
    _ => false
  }
}

///|
fn decl_type_is_dirent_or_string_array_union(type_ : @ast.TsType) -> Bool {
  match type_ {
    Union(items) => {
      let mut has_dirent_array = false
      let mut has_string_array = false
      for item in items {
        match item {
          Array(Named("Dirent"))
          | Applied("Array", [Named("Dirent")])
          | Applied("ReadonlyArray", [Named("Dirent")]) =>
            has_dirent_array = true
          Array(String_)
          | Applied("Array", [String_])
          | Applied("ReadonlyArray", [String_]) => has_string_array = true
          _ => ()
        }
      }
      has_dirent_array && has_string_array
    }
    _ => false
  }
}

///|
fn decl_func_should_skip_broad_node_wrapper(func : @ast.TsFunc) -> Bool {
  if decl_is_node_read_file_api_name(func.name) &&
    decl_type_is_string_nonshared_buffer_union(func.return_type) {
    return true
  }
  if decl_is_broad_generate_prime_sync_wrapper_name(func.name) {
    return true
  }
  func.name == "globSync" &&
  decl_type_is_dirent_or_string_array_union(func.return_type)
}

///|
fn decl_import_should_skip_broad_node_wrapper(import_ : @ast.TsImport) -> Bool {
  if decl_is_node_read_file_api_name(import_.name) &&
    decl_type_is_string_nonshared_buffer_union(import_.return_type) {
    return true
  }
  if decl_is_broad_generate_prime_sync_wrapper_name(import_.name) {
    return true
  }
  import_.name == "globSync" &&
  decl_type_is_dirent_or_string_array_union(import_.return_type)
}

///|
fn decl_is_broad_generate_prime_sync_wrapper_name(name : String) -> Bool {
  name == "generatePrimeSync" ||
  (
    name.has_prefix("generatePrimeSync_") &&
    name.contains("generate_prime_options") &&
    !name.contains("generate_prime_options_big_int") &&
    !name.contains("generate_prime_options_array_buffer")
  )
}

///|
fn clone_exported_func(
  exported : ExportedFuncDecl,
  info : DeclModuleInfo,
  modules : Map[String, DeclModuleInfo],
  canonical_types : Map[String, String],
) -> @ast.TsFunc {
  let params : Array[@ast.TsParam] = []
  let callback_owner_name = if exported.source_export_name == "" ||
    exported.source_export_name == "default" ||
    exported.source_export_name.has_prefix("default.") {
    exported.export_name
  } else {
    exported.source_export_name
  }
  for param_index, param in exported.func.params {
    let lowered = lower_react_utility_type(
      info,
      rewrite_type_refs_in_scope(
        info,
        exported.local_name_prefix,
        param.type_,
        canonical_types,
      ),
      modules,
      canonical_types,
    )
    params.push({
      name: param.name,
      binding: param.binding,
      is_rest: param.is_rest,
      type_: decl_rewrite_inline_callback_param_type(
        callback_owner_name,
        param.name,
        param_index,
        decl_specialize_generated_api_param_type(
          callback_owner_name,
          param.name,
          param_index,
          decl_widen_react_factory_tag_param(
            exported.export_name,
            param_index,
            lowered,
          ),
        ),
      ),
      default: param.default,
    })
  }
  let return_type = lower_react_utility_type(
    info,
    rewrite_type_refs_in_scope(
      info,
      exported.local_name_prefix,
      exported.func.return_type,
      canonical_types,
    ),
    modules,
    canonical_types,
  )
  let return_type = decl_specialize_generated_api_return_type(
    exported.export_name,
    return_type,
  )
  {
    name: exported.export_name,
    type_params: exported.func.type_params,
    params,
    return_type: rewrite_inline_result_return_type(
      exported.export_name,
      return_type,
    ),
    body: exported.func.body,
    is_generator: exported.func.is_generator,
    is_async: exported.func.is_async,
  }
}

///|
fn exported_import_overload_wrappers(
  exported_imports : Array[ExportedImportDecl],
  modules : Map[String, DeclModuleInfo],
  canonical_types : Map[String, String],
) -> Array[ExportedImportDecl] {
  let wrappers : Array[ExportedImportDecl] = []
  let blocked_names : Array[String] = []
  for exported in exported_imports {
    if !blocked_names.contains(exported.export_name) {
      blocked_names.push(exported.export_name)
    }
  }
  for exported in exported_imports {
    let info = match modules.get(exported.source_path) {
      Some(info) => info
      None => continue
    }
    let overloads = find_import_decls(info.module_, exported.import_.name)
    if overloads.length() < 2 {
      continue
    }
    let preferred : Array[@ast.TsImport] = []
    for import_ in overloads {
      push_preferred_import_decl(
        preferred,
        clone_exported_import(
          {
            source_path: exported.source_path,
            local_name_prefix: exported.local_name_prefix,
            export_name: exported.export_name,
            source_export_name: exported.source_export_name,
            import_,
          },
          info,
          modules,
          canonical_types,
        ),
      )
    }
    if preferred.length() == 0 {
      continue
    }
    for import_ in overloads {
      let clone = clone_exported_import(
        {
          source_path: exported.source_path,
          local_name_prefix: exported.local_name_prefix,
          export_name: exported.export_name,
          source_export_name: exported.source_export_name,
          import_,
        },
        info,
        modules,
        canonical_types,
      )
      if decl_import_same_signature(clone, preferred[0]) {
        continue
      }
      if decl_import_wider_than_any_same_param_preferred(clone, preferred) {
        continue
      }
      if decl_import_should_skip_broad_node_wrapper(clone) {
        continue
      }
      let suffix = match
        decl_overload_suffix_from_types(decl_import_signature_types(clone)) {
        Some(suffix) => suffix
        None => continue
      }
      let wrapper_name = exported.export_name + "_" + suffix
      if blocked_names.contains(wrapper_name) {
        continue
      }
      blocked_names.push(wrapper_name)
      wrappers.push({
        source_path: exported.source_path,
        local_name_prefix: exported.local_name_prefix,
        export_name: wrapper_name,
        source_export_name: exported.source_export_name,
        import_,
      })
    }
  }
  wrappers
}

///|
fn exported_func_overload_wrappers(
  exported_funcs : Array[ExportedFuncDecl],
  modules : Map[String, DeclModuleInfo],
  canonical_types : Map[String, String],
) -> Array[ExportedFuncDecl] {
  let wrappers : Array[ExportedFuncDecl] = []
  let blocked_names : Array[String] = []
  for exported in exported_funcs {
    if !blocked_names.contains(exported.export_name) {
      blocked_names.push(exported.export_name)
    }
  }
  for exported in exported_funcs {
    let info = match modules.get(exported.source_path) {
      Some(info) => info
      None => continue
    }
    let overloads = find_func_decls(info.module_, exported.func.name)
    if overloads.length() < 2 {
      continue
    }
    let preferred : Array[@ast.TsFunc] = []
    for func in overloads {
      push_preferred_func_decl(
        preferred,
        clone_exported_func(
          {
            source_path: exported.source_path,
            local_name_prefix: exported.local_name_prefix,
            export_name: exported.export_name,
            source_export_name: exported.source_export_name,
            func,
          },
          info,
          modules,
          canonical_types,
        ),
      )
    }
    if preferred.length() == 0 {
      continue
    }
    for func in overloads {
      let clone = clone_exported_func(
        {
          source_path: exported.source_path,
          local_name_prefix: exported.local_name_prefix,
          export_name: exported.export_name,
          source_export_name: exported.source_export_name,
          func,
        },
        info,
        modules,
        canonical_types,
      )
      if decl_func_same_signature(clone, preferred[0]) {
        continue
      }
      if decl_func_wider_than_any_same_param_preferred(clone, preferred) {
        continue
      }
      if decl_func_should_skip_broad_node_wrapper(clone) {
        continue
      }
      let suffix = match
        decl_overload_suffix_from_types(decl_func_signature_types(clone)) {
        Some(suffix) => suffix
        None => continue
      }
      let wrapper_name = exported.export_name + "_" + suffix
      if blocked_names.contains(wrapper_name) {
        continue
      }
      blocked_names.push(wrapper_name)
      wrappers.push({
        source_path: exported.source_path,
        local_name_prefix: exported.local_name_prefix,
        export_name: wrapper_name,
        source_export_name: exported.source_export_name,
        func,
      })
    }
  }
  wrappers
}

///|
fn append_exported_imports(
  base : Array[ExportedImportDecl],
  extra : Array[ExportedImportDecl],
) -> Array[ExportedImportDecl] {
  let out : Array[ExportedImportDecl] = []
  for item in base {
    out.push(item)
  }
  for item in extra {
    out.push(item)
  }
  out
}

///|
fn append_exported_funcs(
  base : Array[ExportedFuncDecl],
  extra : Array[ExportedFuncDecl],
) -> Array[ExportedFuncDecl] {
  let out : Array[ExportedFuncDecl] = []
  for item in base {
    out.push(item)
  }
  for item in extra {
    out.push(item)
  }
  out
}

///|
fn clone_exported_value(
  exported : ExportedValueDecl,
  info : DeclModuleInfo,
  modules : Map[String, DeclModuleInfo],
  canonical_types : Map[String, String],
) -> @ast.TsValueDecl {
  {
    name: exported.export_name,
    type_: decl_specialize_generated_value_type(
      exported.export_name,
      lower_react_utility_type(
        info,
        rewrite_type_refs_in_scope(
          info,
          exported.local_name_prefix,
          exported.value.type_,
          canonical_types,
        ),
        modules,
        canonical_types,
      ),
    ),
  }
}

///|
fn clone_class_property_in_scope(
  class_property : @ast.TsClassPropertyDecl,
  class_name : String,
  info : DeclModuleInfo,
  local_name_prefix : String,
  modules : Map[String, DeclModuleInfo],
  canonical_types : Map[String, String],
) -> @ast.TsClassPropertyDecl {
  {
    name: class_property.name,
    type_: decl_specialize_generated_class_property_type(
      class_name,
      class_property.name,
      lower_react_utility_type(
        info,
        rewrite_type_refs_in_scope(
          info,
          local_name_prefix,
          class_property.type_,
          canonical_types,
        ),
        modules,
        canonical_types,
      ),
    ),
    is_static: class_property.is_static,
    is_readonly: class_property.is_readonly,
    is_accessor: false,
  }
}

///|
fn clone_class_method_in_scope(
  class_method : @ast.TsClassMethodDecl,
  class_name : String,
  info : DeclModuleInfo,
  local_name_prefix : String,
  modules : Map[String, DeclModuleInfo],
  canonical_types : Map[String, String],
) -> @ast.TsClassMethodDecl {
  let params : Array[(String, @ast.TsType)] = []
  for param_index, param in class_method.params {
    let (param_name, param_type) = param
    let lowered_param_type = lower_react_utility_type(
      info,
      rewrite_type_refs_in_scope(
        info, local_name_prefix, param_type, canonical_types,
      ),
      modules,
      canonical_types,
    )
    params.push(
      (
        param_name,
        decl_rewrite_inline_callback_param_type(
          class_name + "_" + class_method.name,
          param_name,
          param_index,
          decl_specialize_generated_class_method_param_type(
            class_name,
            class_method.name,
            param_name,
            param_index,
            lowered_param_type,
          ),
        ),
      ),
    )
  }
  {
    name: class_method.name,
    type_params: class_method.type_params,
    type_param_bounds: class_method.type_param_bounds,
    params,
    return_type: decl_specialize_generated_class_method_return_type(
      class_name,
      class_method.name,
      lower_react_utility_type(
        info,
        rewrite_type_refs_in_scope(
          info,
          local_name_prefix,
          class_method.return_type,
          canonical_types,
        ),
        modules,
        canonical_types,
      ),
    ),
    is_static: class_method.is_static,
    body: class_method.body,
  }
}

///|
fn callable_method_from_func_type(
  class_name : String,
  method_name : String,
  is_static : Bool,
  params : Array[@ast.TsType],
  return_type : @ast.TsType,
  info : DeclModuleInfo,
  local_name_prefix : String,
  modules : Map[String, DeclModuleInfo],
  canonical_types : Map[String, String],
) -> @ast.TsClassMethodDecl {
  let method_params : Array[(String, @ast.TsType)] = []
  for i, param_type in params {
    let param_name = "arg" + i.to_string()
    let lowered_param_type = lower_react_utility_type(
      info,
      rewrite_type_refs_in_scope(
        info, local_name_prefix, param_type, canonical_types,
      ),
      modules,
      canonical_types,
    )
    method_params.push(
      (
        param_name,
        decl_specialize_generated_class_method_param_type(
          class_name, method_name, param_name, i, lowered_param_type,
        ),
      ),
    )
  }
  let lowered_return_type = lower_react_utility_type(
    info,
    rewrite_type_refs_in_scope(
      info, local_name_prefix, return_type, canonical_types,
    ),
    modules,
    canonical_types,
  )
  {
    name: method_name,
    type_params: [],
    type_param_bounds: [],
    params: method_params,
    return_type: decl_specialize_generated_class_method_return_type(
      class_name, method_name, lowered_return_type,
    ),
    is_static,
    body: None,
  }
}

///|
fn preferred_callable_interface_field(iface : @ast.TsInterface) -> @ast.TsType? {
  let mut best : @ast.TsType? = None
  let mut best_param_count = -1
  for field in iface.fields {
    let (field_name, field_type) = field
    if field_name != "<call>" {
      continue
    }
    match field_type {
      Func(params, _) =>
        if params.length() > best_param_count {
          best = Some(field_type)
          best_param_count = params.length()
        }
      _ => ()
    }
  }
  best
}

///|
fn callable_method_from_property(
  class_name : String,
  class_property : @ast.TsClassPropertyDecl,
  info : DeclModuleInfo,
  local_name_prefix : String,
  modules : Map[String, DeclModuleInfo],
  canonical_types : Map[String, String],
) -> @ast.TsClassMethodDecl? {
  match class_property.type_ {
    Func(params, return_type) =>
      Some(
        callable_method_from_func_type(
          class_name,
          class_property.name,
          class_property.is_static,
          params,
          return_type,
          info,
          local_name_prefix,
          modules,
          canonical_types,
        ),
      )
    Named(type_name) | Applied(type_name, _) =>
      match
        resolve_interface_origin(info, type_name, modules, canonical_types) {
        Some(origin) =>
          match preferred_callable_interface_field(origin.iface) {
            Some(Func(params, return_type)) =>
              Some(
                callable_method_from_func_type(
                  class_name,
                  class_property.name,
                  class_property.is_static,
                  params,
                  return_type,
                  origin.info,
                  "",
                  modules,
                  canonical_types,
                ),
              )
            _ => None
          }
        None => None
      }
    _ => None
  }
}

///|
fn class_property_key(class_property : @ast.TsClassPropertyDecl) -> String {
  class_property.name + "\n" + class_property.is_static.to_string()
}

///|
fn class_method_key(class_method : @ast.TsClassMethodDecl) -> String {
  class_method.name + "\n" + class_method.is_static.to_string()
}

///|
fn append_class_property_once(
  properties : Array[@ast.TsClassPropertyDecl],
  seen_property_keys : Array[String],
  class_property : @ast.TsClassPropertyDecl,
) -> Unit {
  let key = class_property_key(class_property)
  if seen_property_keys.contains(key) {
    return
  }
  seen_property_keys.push(key)
  properties.push(class_property)
}

///|
fn append_class_method_once(
  methods : Array[@ast.TsClassMethodDecl],
  seen_method_keys : Array[String],
  class_method : @ast.TsClassMethodDecl,
) -> Unit {
  let key = class_method_key(class_method)
  if seen_method_keys.contains(key) {
    return
  }
  seen_method_keys.push(key)
  methods.push(class_method)
}

///|
fn append_class_origin_members(
  origin : ResolvedClassOrigin,
  graph : ModuleGraph,
  modules : Map[String, DeclModuleInfo],
  surface_cache : Map[String, Array[ResolvedExport]],
  canonical_types : Map[String, String],
  properties : Array[@ast.TsClassPropertyDecl],
  methods : Array[@ast.TsClassMethodDecl],
  seen_property_keys : Array[String],
  seen_method_keys : Array[String],
  seen_origins : Array[String],
) -> Unit {
  let origin_key = decl_key(origin.info.record.path, origin.class_.name)
  if seen_origins.contains(origin_key) {
    return
  }
  seen_origins.push(origin_key)
  for base_name in origin.class_.base_names {
    match
      resolve_class_origin(
        origin.info,
        base_name,
        graph,
        modules,
        surface_cache,
      ) {
      Some(base_origin) =>
        append_class_origin_members(
          base_origin, graph, modules, surface_cache, canonical_types, properties,
          methods, seen_property_keys, seen_method_keys, seen_origins,
        )
      None => ()
    }
  }
  for class_property in origin.class_.properties {
    let cloned_property = clone_class_property_in_scope(
      class_property,
      origin.class_.name,
      origin.info,
      origin.local_name_prefix,
      modules,
      canonical_types,
    )
    append_class_property_once(properties, seen_property_keys, cloned_property)
    match
      callable_method_from_property(
        origin.class_.name,
        class_property,
        origin.info,
        origin.local_name_prefix,
        modules,
        canonical_types,
      ) {
      Some(class_method) =>
        append_class_method_once(methods, seen_method_keys, class_method)
      None => ()
    }
  }
  for class_method in origin.class_.methods {
    append_class_method_once(
      methods,
      seen_method_keys,
      clone_class_method_in_scope(
        class_method,
        origin.class_.name,
        origin.info,
        origin.local_name_prefix,
        modules,
        canonical_types,
      ),
    )
  }
}

///|
fn clone_exported_class(
  exported : ExportedClassDecl,
  info : DeclModuleInfo,
  graph : ModuleGraph,
  modules : Map[String, DeclModuleInfo],
  surface_cache : Map[String, Array[ResolvedExport]],
  canonical_types : Map[String, String],
) -> @ast.TsClassDecl {
  let properties : Array[@ast.TsClassPropertyDecl] = []
  let methods : Array[@ast.TsClassMethodDecl] = []
  let seen_property_keys : Array[String] = []
  let seen_method_keys : Array[String] = []
  let seen_origins : Array[String] = []
  append_class_origin_members(
    {
      info,
      local_name_prefix: exported.local_name_prefix,
      class_: exported.class_,
    },
    graph,
    modules,
    surface_cache,
    canonical_types,
    properties,
    methods,
    seen_property_keys,
    seen_method_keys,
    seen_origins,
  )
  let constructor_params = match exported.class_.constructor_params {
    Some(params) => {
      let next_params : Array[(String, @ast.TsType)] = []
      for param in params {
        let (param_name, param_type) = param
        next_params.push(
          (
            param_name,
            lower_react_utility_type(
              info,
              rewrite_type_refs_in_scope(
                info,
                exported.local_name_prefix,
                param_type,
                canonical_types,
              ),
              modules,
              canonical_types,
            ),
          ),
        )
      }
      Some(next_params)
    }
    None => None
  }
  {
    name: exported.export_name,
    type_params: exported.class_.type_params,
    base_names: [],
    constructor_params,
    properties,
    methods,
    is_abstract: exported.class_.is_abstract,
    is_constructible: exported.class_.is_constructible,
    index_signatures: [],
    decorators: [],
  }
}

///|
pub async fn emit_moonbit_decl_from_entry_path(
  entry_path : String,
) -> String raise ModuleGraphError {
  let graph = load_type_module_graph(entry_path)
  let export_surface = resolve_export_surface(graph)
  let modules = build_decl_module_map(graph)
  let (
    exported_interfaces,
    exported_enums,
    exported_tagged_unions,
    exported_type_aliases,
    exported_imports,
    exported_funcs,
    exported_values,
    exported_classes,
    notes,
  ) = collect_exported_decls(graph, export_surface, modules)
  let tagged_union_sections : Array[String] = []
  let tagged_union_declared_names : Array[String] = []
  let tagged_union_referenced_inner_names : Array[String] = []
  // Generic-preserved class / interface arities so a tagged-union case
  // payload like `VNodeValue(VNode)` can be widened to `VNode[JSValue]`
  // when `VNode` itself was emitted as `pub type VNode[T]`.
  let tagged_union_arity_registry : Map[String, Array[String]] = {}
  for class_ in exported_classes {
    if class_.class_.type_params.length() > 0 {
      tagged_union_arity_registry[class_.class_.name] = class_.class_.type_params
    }
  }
  for iface in exported_interfaces {
    if iface.iface.type_params.length() > 0 &&
      !tagged_union_arity_registry.contains(iface.iface.name) {
      tagged_union_arity_registry[iface.iface.name] = iface.iface.type_params
    }
  }
  for tagged in exported_tagged_unions {
    match
      tagged_union_decl_to_moonbit_section_with_arity(
        tagged.decl,
        tagged_union_arity_registry,
      ) {
      Some(section) => {
        tagged_union_sections.push(section)
        tagged_union_declared_names.push(tagged.decl.name)
        for entry in tagged.decl.cases {
          let (_, inner) = entry
          let inner_named = match inner {
            @ast.TsType::Named(name) => Some(name)
            @ast.TsType::Array(@ast.TsType::Named(name)) => Some(name)
            _ => None
          }
          match inner_named {
            Some(name) =>
              if !tagged_union_referenced_inner_names.contains(name) {
                tagged_union_referenced_inner_names.push(name)
              }
            None => ()
          }
        }
      }
      None =>
        notes.push(
          "///|\n/// Heterogeneous union \{tagged.export_name} (\{tagged.source_path}::\{tagged.local_name}) could not be auto-lowered (unsupported case payload).",
        )
    }
  }
  let canonical_types = build_canonical_type_name_map(
    exported_interfaces, exported_enums, exported_classes,
  )
  let class_surface_cache : Map[String, Array[ResolvedExport]] = {}
  let emitted_exported_imports = append_exported_imports(
    exported_imports,
    exported_import_overload_wrappers(
      exported_imports, modules, canonical_types,
    ),
  )
  let emitted_exported_funcs = append_exported_funcs(
    exported_funcs,
    exported_func_overload_wrappers(exported_funcs, modules, canonical_types),
  )
  let tuple_result_interfaces = normalize_result_interfaces(
    emitted_exported_imports, emitted_exported_funcs, modules, canonical_types,
  )
  let react_utility_interfaces = normalize_react_utility_interfaces(
    exported_interfaces, emitted_exported_imports, emitted_exported_funcs, exported_values,
    exported_classes, modules, canonical_types,
  )
  let specialized_node_interfaces = normalize_specialized_node_interfaces(
    exported_interfaces,
  )
  let interfaces : Array[@ast.TsInterface] = []
  for exported in exported_interfaces {
    match modules.get(exported.source_path) {
      Some(info) =>
        interfaces.push(
          clone_exported_interface(exported, info, modules, canonical_types),
        )
      None => ()
    }
  }
  for spec in tuple_result_interfaces {
    interfaces.push(spec.iface)
  }
  for iface in react_utility_interfaces {
    interfaces.push(iface)
  }
  for iface in specialized_node_interfaces {
    interfaces.push(iface)
  }
  let enums : Array[@ast.TsEnumDecl] = []
  for exported in exported_enums {
    enums.push(clone_exported_enum(exported))
  }
  for
    iface in collect_interface_dependencies(
      exported_interfaces, emitted_exported_imports, emitted_exported_funcs, exported_values,
      exported_classes, modules, canonical_types, interfaces,
    ) {
    interfaces.push(iface)
  }
  let imports : Array[@ast.TsImport] = []
  for exported in emitted_exported_imports {
    match modules.get(exported.source_path) {
      Some(info) =>
        push_preferred_import_decl(
          imports,
          clone_exported_import(exported, info, modules, canonical_types),
        )
      None => ()
    }
  }
  let funcs : Array[@ast.TsFunc] = []
  for exported in emitted_exported_funcs {
    match modules.get(exported.source_path) {
      Some(info) =>
        push_preferred_func_decl(
          funcs,
          clone_exported_func(exported, info, modules, canonical_types),
        )
      None => ()
    }
  }
  let classes : Array[@ast.TsClassDecl] = []
  for exported in exported_classes {
    match modules.get(exported.source_path) {
      Some(info) =>
        classes.push(
          clone_exported_class(
            exported, info, graph, modules, class_surface_cache, canonical_types,
          ),
        )
      None => ()
    }
  }
  let values : Array[@ast.TsValueDecl] = []
  for exported in exported_values {
    match modules.get(exported.source_path) {
      Some(info) =>
        values.push(
          clone_exported_value(exported, info, modules, canonical_types),
        )
      None => ()
    }
  }
  let type_aliases : Array[@ast.TsTypeAlias] = []
  for exported in exported_type_aliases {
    match modules.get(exported.source_path) {
      Some(info) =>
        type_aliases.push(
          clone_exported_type_alias(exported, info, modules, canonical_types),
        )
      None => ()
    }
  }
  enum_lowering_rewrite_anonymous_enum_surfaces(
    enums, interfaces, imports, funcs, values, classes,
  )
  push_remaining_anonymous_literal_union_notes(
    notes, interfaces, imports, funcs,
  )
  let mut notes_need_jsvalue = false
  for note in notes {
    if note.contains("JSValue") {
      notes_need_jsvalue = true
      break
    }
  }
  let emitted_module : @ast.TsModule = {
    funcs,
    interfaces,
    type_aliases,
    imports,
    values,
    classes,
    namespaces: [],
    enums,
    module_augmentations: [],
  }
  // Run the checker over the final module shape and surface anything it
  // catches as a generator-level note. The emit pipeline is internally
  // expected to produce well-formed output; any warnings here flag a real
  // issue in bridge synthesis.
  let report = @checker.check_module(emitted_module)
  for issue in report.issues {
    if issue.kind is UnresolvedReference &&
      tagged_union_declared_names.contains(issue.name) {
      continue
    }
    let prefix = match issue.kind {
      UnresolvedReference => "Unresolved type reference"
      DuplicateDeclaration => "Duplicate top-level name"
      CircularTypeAlias => "Circular type alias"
      TypeAliasArityMismatch => "Type alias arity mismatch"
      InterfaceFieldDuplicate => "Duplicate interface field"
      EnumMemberDuplicate => "Duplicate enum member"
      InterfaceExtendsCycle => "Interface extends cycle"
      ClassPropertyDuplicate => "Duplicate class property"
    }
    // Emit as a plain `//` comment instead of `///` so the diagnostic
    // doesn't look like a doc comment binding to whatever entity follows
    // it. Without this guard, an "Unresolved type reference" line gets
    // attached as the public doc of the next struct / type declaration.
    let note = "// \{prefix} \{issue.name}: \{issue.detail}"
    if !notes.contains(note) {
      notes.push(note)
    }
  }
  let module_declared_names : Array[String] = []
  for iface in interfaces {
    module_declared_names.push(iface.name)
  }
  for class_ in classes {
    module_declared_names.push(class_.name)
  }
  for enum_ in enums {
    module_declared_names.push(enum_.name)
  }
  for name in tagged_union_declared_names {
    if !module_declared_names.contains(name) {
      module_declared_names.push(name)
    }
  }
  let opaque_declarations : Array[String] = []
  for name in tagged_union_referenced_inner_names {
    if !module_declared_names.contains(name) {
      // Generic-preserved inner-payload types need their type-parameter
      // suffix on the opaque companion declaration; otherwise the
      // generated bridge wrapper signature `task : Test` collides with
      // the `pub type Test[ExtraContext]` body emitted in `types.mbt`
      // and the consumer hits a `[4040]` arity mismatch.
      let suffix = match tagged_union_arity_registry.get(name) {
        Some(type_params) if type_params.length() > 0 =>
          "[" + type_params.join(", ") + "]"
        _ => ""
      }
      opaque_declarations.push("///|\ndeclare pub type \{name}\{suffix}")
      module_declared_names.push(name)
    }
  }
  let combined_extra_sections : Array[String] = []
  for decl in opaque_declarations {
    combined_extra_sections.push(decl)
  }
  for section in tagged_union_sections {
    combined_extra_sections.push(section)
  }
  for note in notes {
    combined_extra_sections.push(note)
  }
  let combined_declared_names : Array[String] = []
  for name in tagged_union_declared_names {
    combined_declared_names.push(name)
  }
  for name in tagged_union_referenced_inner_names {
    if !combined_declared_names.contains(name) {
      combined_declared_names.push(name)
    }
  }
  // Walk every loaded module so cross-file generic interfaces / classes
  // (e.g. vitest's `Test` interface declared in `@vitest/runner`'s
  // `tasks.d.ts` but referenced by exports of vitest's `index.d.ts`)
  // contribute their arity to the renderer. Otherwise call sites like
  // `recordArtifact(task : Test, ...)` widen to bare `Test` while the
  // FFI side emits `pub type Test[ExtraContext]`, hitting `[4040]`
  // arity-mismatch.
  let cross_module_arities : Map[String, Int] = {}
  collect_cross_module_iface_arities(modules, cross_module_arities)
  for class_ in exported_classes {
    if class_.class_.type_params.length() > 0 &&
      !cross_module_arities.contains(class_.class_.name) {
      cross_module_arities[class_.class_.name] = class_.class_.type_params.length()
    }
  }
  @parser.emit_moonbit_decl_with_sections_types_and_arities(
    emitted_module, combined_extra_sections, combined_declared_names, cross_module_arities,
    notes_need_jsvalue,
  )
}

///|
fn collect_cross_module_iface_arities(
  modules : Map[String, DeclModuleInfo],
  out : Map[String, Int],
) -> Unit {
  for entry in modules {
    let (_, info) = entry
    collect_arities_in_ts_module(info.module_, out)
  }
}

///|
fn collect_arities_in_ts_module(
  module_ : @ast.TsModule,
  out : Map[String, Int],
) -> Unit {
  for iface in module_.interfaces {
    if iface.type_params.length() > 0 && !out.contains(iface.name) {
      out[iface.name] = iface.type_params.length()
    }
  }
  for class_ in module_.classes {
    if class_.type_params.length() > 0 && !out.contains(class_.name) {
      out[class_.name] = class_.type_params.length()
    }
  }
  for namespace_ in module_.namespaces {
    collect_arities_in_ts_module(namespace_.module_, out)
  }
}
