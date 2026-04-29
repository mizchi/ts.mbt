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
priv struct ExportedImportDecl {
  source_path : String
  export_name : String
  source_export_name : String
  import_ : @ast.TsImport
}

///|
priv struct ExportedFuncDecl {
  source_path : String
  export_name : String
  source_export_name : String
  func : @ast.TsFunc
}

///|
priv struct ExportedValueDecl {
  source_path : String
  export_name : String
  source_export_name : String
  value : @ast.TsValueDecl
}

///|
priv struct ExportedClassDecl {
  source_path : String
  local_name : String
  export_name : String
  source_export_name : String
  class_ : @ast.TsClassDecl
}

///|
priv struct TupleResultInterfaceSpec {
  export_name : String
  iface : @ast.TsInterface
}

///|
priv struct ResolvedInterfaceOrigin {
  info : DeclModuleInfo
  export_name : String
  iface : @ast.TsInterface
}

///|
priv struct ExportedConstValueSet {
  values : Map[String, @ast.TsExpr]
  explicit_names : Array[String]
  star_names : Array[String]
  ambiguous_names : Array[String]
}

///|
priv enum ResolvedDecl {
  Interface(ExportedInterfaceDecl)
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
          imports: [],
          values: [],
          classes: [],
          namespaces: [],
        }
      }
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
fn find_import_decl(module_ : @ast.TsModule, name : String) -> @ast.TsImport? {
  for import_ in module_.imports {
    if import_.name == name {
      return Some(import_)
    }
  }
  None
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
  for func in module_.funcs {
    if func.name == name {
      return Some(func)
    }
  }
  None
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
        params: merge_func_param_types(func.params, declared_type),
        return_type: infer_func_return_type(func, declared_type),
        body: func.body,
        is_generator: func.is_generator,
        is_async: func.is_async,
      })
    @ast.TsExpr::ArrowFunc(params, body, is_async) => {
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
) -> Unit {
  for iface in namespace_.module_.interfaces {
    interfaces.push({
      source_path,
      local_name: namespace_local_export_name(local_name_prefix, iface.name),
      export_name: namespace_type_export_name(type_export_prefix, iface.name),
      iface,
    })
  }
  for nested in namespace_.module_.namespaces {
    append_exported_type_namespace_members_with_prefix(
      source_path,
      namespace_local_export_name(local_name_prefix, nested.name + "."),
      namespace_next_type_export_prefix(type_export_prefix, nested.name),
      nested,
      interfaces,
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
    // The parser emits Symbol for `unique symbol`, which .d.ts files use for
    // type-level marker keys that often do not exist as runtime exports.
    Symbol => false
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
        None => false
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
  for import_ in namespace_.module_.imports {
    imports.push({
      source_path,
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
  imports : Array[ExportedImportDecl],
  funcs : Array[ExportedFuncDecl],
  values : Array[ExportedValueDecl],
  classes : Array[ExportedClassDecl],
) -> Unit {
  append_exported_namespace_members_with_prefix(
    source_path, runtime_root_export_name, "", "", "", namespace_, interfaces, imports,
    funcs, values, classes,
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
          match find_import_decl(info.module_, local_name) {
            Some(import_) =>
              Import({ source_path, export_name, source_export_name, import_ })
            None => {
              let stmt_func = find_func_decl_from_stmts(
                info.record.module_block.block.stmts,
                local_name,
              )
              match find_func_decl(info.module_, local_name) {
                Some(func) =>
                  Function({
                    source_path,
                    export_name,
                    source_export_name,
                    func,
                  })
                None =>
                  match stmt_func {
                    Some(func) =>
                      Function({
                        source_path,
                        export_name,
                        source_export_name,
                        func,
                      })
                    None =>
                      match find_value_decl(info.module_, local_name) {
                        Some(value) =>
                          if value_decl_has_runtime_binding(value) {
                            Value({
                              source_path,
                              export_name,
                              source_export_name,
                              value,
                            })
                          } else {
                            Missing
                          }
                        None =>
                          match find_class_decl(info.module_, local_name) {
                            Some(class_) =>
                              Class({
                                source_path,
                                local_name,
                                export_name,
                                source_export_name,
                                class_,
                              })
                            None => {
                              let mut resolved : ResolvedDecl = Missing
                              for
                                i, import_decl in info.record.module_block.imports {
                                let edge = info.record.imports[i]
                                if edge.resolved_path == "" {
                                  continue
                                }
                                for binding in import_decl.named_bindings {
                                  let (imported_name, imported_local_name) = binding
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
  Array[ExportedImportDecl],
  Array[ExportedFuncDecl],
  Array[ExportedValueDecl],
  Array[ExportedClassDecl],
  Array[String],
) {
  let interfaces : Array[ExportedInterfaceDecl] = []
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
      Import(exported) => imports.push(exported)
      Function(exported) => funcs.push(exported)
      Value(exported) => values.push(exported)
      Class(exported) => classes.push(exported)
      Unsupported(name, reason) =>
        notes.push("///|\n/// Unsupported export \{name}: \{reason}")
      Missing => ()
    }
  }
  (interfaces, imports, funcs, values, classes, notes)
}

///|
fn build_canonical_type_name_map(
  interfaces : Array[ExportedInterfaceDecl],
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
fn props_with_children_interface_name(base_name : String) -> String {
  base_name + "WithChildren"
}

///|
fn component_props_with_ref_interface_name(base_name : String) -> String {
  base_name + "WithRef"
}

///|
fn is_props_passthrough_name(name : String) -> Bool {
  name == "PropsWithoutRef" ||
  name == "PropsWithRef" ||
  name == "Partial" ||
  name == "Readonly"
}

///|
fn is_component_ref_like_name(name : String) -> Bool {
  name == "ComponentRef" || name == "ElementRef"
}

///|
fn is_react_node_like_name(name : String) -> Bool {
  name == "ReactNode" || name.has_suffix(".ReactNode")
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
        fields,
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
        fields,
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
            fields,
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
fn lower_react_utility_type(
  info : DeclModuleInfo,
  type_ : @ast.TsType,
  modules : Map[String, DeclModuleInfo],
  canonical_types : Map[String, String],
) -> @ast.TsType {
  match type_ {
    Named(name) if is_react_node_like_name(name) => Any
    Applied(name, [inner_type]) if is_props_passthrough_name(name) =>
      lower_react_utility_type(info, inner_type, modules, canonical_types)
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
    Applied(name, [_]) if is_component_ref_like_name(name) =>
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
    Applied(name, args) => {
      let next_args : Array[@ast.TsType] = []
      for arg in args {
        next_args.push(
          lower_react_utility_type(info, arg, modules, canonical_types),
        )
      }
      Applied(name, next_args)
    }
    Array(inner) =>
      Array(lower_react_utility_type(info, inner, modules, canonical_types))
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
    Applied(name, [inner_type]) if is_props_passthrough_name(name) =>
      collect_react_utility_interfaces_from_type(
        info, inner_type, modules, canonical_types, seen_names, interfaces,
      )
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
    Applied(name, [inner_type]) if is_component_ref_like_name(name) =>
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
  match type_ {
    Named(name) =>
      match resolve_exported_type_name(info, name, canonical_types) {
        Some(export_name) => Named(export_name)
        None => type_
      }
    Applied(name, args) => {
      let next_args : Array[@ast.TsType] = []
      for arg in args {
        next_args.push(rewrite_type_refs(info, arg, canonical_types))
      }
      match resolve_exported_type_name(info, name, canonical_types) {
        Some(export_name) => Applied(export_name, next_args)
        None => Applied(name, next_args)
      }
    }
    Array(inner) => Array(rewrite_type_refs(info, inner, canonical_types))
    Tuple(items) => {
      let next_items : Array[@ast.TsType] = []
      for item in items {
        next_items.push(rewrite_type_refs(info, item, canonical_types))
      }
      Tuple(next_items)
    }
    Object(fields) => {
      let next_fields : Array[(@ast.TsType, @ast.TsType)] = []
      for field in fields {
        let (key_type, value_type) = field
        next_fields.push(
          (
            rewrite_type_refs(info, key_type, canonical_types),
            rewrite_type_refs(info, value_type, canonical_types),
          ),
        )
      }
      Object(next_fields)
    }
    Struct(name, fields) => {
      let next_name = match
        resolve_exported_type_name(info, name, canonical_types) {
        Some(export_name) => export_name
        None => name
      }
      let next_fields : Array[(String, @ast.TsType)] = []
      for field in fields {
        let (field_name, field_type) = field
        next_fields.push(
          (field_name, rewrite_type_refs(info, field_type, canonical_types)),
        )
      }
      Struct(next_name, next_fields)
    }
    Func(params, return_type) => {
      let next_params : Array[@ast.TsType] = []
      for param in params {
        next_params.push(rewrite_type_refs(info, param, canonical_types))
      }
      Func(next_params, rewrite_type_refs(info, return_type, canonical_types))
    }
    Union(types) => {
      let next_types : Array[@ast.TsType] = []
      for item in types {
        next_types.push(rewrite_type_refs(info, item, canonical_types))
      }
      Union(next_types)
    }
    Intersection(types) => {
      let next_types : Array[@ast.TsType] = []
      for item in types {
        next_types.push(rewrite_type_refs(info, item, canonical_types))
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
) -> TupleResultInterfaceSpec? {
  match return_type {
    Tuple(items) => {
      let fields : Array[(String, @ast.TsType)] = []
      let field_names = tuple_result_field_names(export_name, items.length())
      for i, item in items {
        fields.push((field_names[i], item))
      }
      Some({
        export_name,
        iface: { name: tuple_result_interface_name(export_name), fields },
      })
    }
    _ => None
  }
}

///|
fn normalize_tuple_result_interfaces(
  exported_imports : Array[ExportedImportDecl],
  exported_funcs : Array[ExportedFuncDecl],
  modules : Map[String, DeclModuleInfo],
  canonical_types : Map[String, String],
) -> Array[TupleResultInterfaceSpec] {
  let specs : Array[TupleResultInterfaceSpec] = []
  let seen_export_names : Array[String] = []
  for exported in exported_imports {
    match modules.get(exported.source_path) {
      Some(info) =>
        match
          tuple_result_interface_spec(
            exported.export_name,
            rewrite_type_refs(
              info,
              exported.import_.return_type,
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
          tuple_result_interface_spec(
            exported.export_name,
            rewrite_type_refs(info, exported.func.return_type, canonical_types),
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
            rewrite_type_refs(info, param_type, canonical_types),
            modules,
            canonical_types,
            seen_names,
            interfaces,
          )
        }
        collect_react_utility_interfaces_from_type(
          info,
          rewrite_type_refs(info, exported.import_.return_type, canonical_types),
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
            rewrite_type_refs(info, param.type_, canonical_types),
            modules,
            canonical_types,
            seen_names,
            interfaces,
          )
        }
        collect_react_utility_interfaces_from_type(
          info,
          rewrite_type_refs(info, exported.func.return_type, canonical_types),
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
          rewrite_type_refs(info, exported.value.type_, canonical_types),
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
            rewrite_type_refs(info, class_property.type_, canonical_types),
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
              rewrite_type_refs(info, param_type, canonical_types),
              modules,
              canonical_types,
              seen_names,
              interfaces,
            )
          }
          collect_react_utility_interfaces_from_type(
            info,
            rewrite_type_refs(info, class_method.return_type, canonical_types),
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
                rewrite_type_refs(info, param_type, canonical_types),
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
fn clone_resolved_interface_origin(
  origin : ResolvedInterfaceOrigin,
  modules : Map[String, DeclModuleInfo],
  canonical_types : Map[String, String],
) -> @ast.TsInterface {
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
  { name: origin.export_name, fields }
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
            rewrite_type_refs(info, param_type, canonical_types),
            modules,
            canonical_types,
            seen_names,
            interfaces,
          )
        }
        collect_interface_dependencies_from_type(
          info,
          rewrite_type_refs(info, exported.import_.return_type, canonical_types),
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
            rewrite_type_refs(info, param.type_, canonical_types),
            modules,
            canonical_types,
            seen_names,
            interfaces,
          )
        }
        collect_interface_dependencies_from_type(
          info,
          rewrite_type_refs(info, exported.func.return_type, canonical_types),
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
          rewrite_type_refs(info, exported.value.type_, canonical_types),
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
            rewrite_type_refs(info, class_property.type_, canonical_types),
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
              rewrite_type_refs(info, param_type, canonical_types),
              modules,
              canonical_types,
              seen_names,
              interfaces,
            )
          }
          collect_interface_dependencies_from_type(
            info,
            rewrite_type_refs(info, class_method.return_type, canonical_types),
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
                rewrite_type_refs(info, param_type, canonical_types),
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
  for field in exported.iface.fields {
    let (field_name, field_type) = field
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
  }
  { name: exported.export_name, fields }
}

///|
fn clone_exported_import(
  exported : ExportedImportDecl,
  info : DeclModuleInfo,
  modules : Map[String, DeclModuleInfo],
  canonical_types : Map[String, String],
) -> @ast.TsImport {
  let params : Array[(String, @ast.TsType)] = []
  for param in exported.import_.params {
    let (param_name, param_type) = param
    params.push(
      (
        param_name,
        lower_react_utility_type(
          info,
          rewrite_type_refs(info, param_type, canonical_types),
          modules,
          canonical_types,
        ),
      ),
    )
  }
  let return_type = lower_react_utility_type(
    info,
    rewrite_type_refs(info, exported.import_.return_type, canonical_types),
    modules,
    canonical_types,
  )
  {
    name: exported.export_name,
    module_: exported.import_.module_,
    params,
    return_type: match return_type {
      Tuple(_) => Named(tuple_result_interface_name(exported.export_name))
      _ => return_type
    },
  }
}

///|
fn decl_classify_optional_like_union(
  type_ : @ast.TsType,
) -> (@ast.TsType, Bool)? {
  match type_ {
    Union(items) => {
      let mut concrete : @ast.TsType? = None
      let mut has_any = false
      let mut is_optional = false
      for item in items {
        match item {
          Any => has_any = true
          Undefined | Null => is_optional = true
          _ =>
            match concrete {
              Some(_) => return None
              None => concrete = Some(item)
            }
        }
      }
      match concrete {
        Some(inner) => if has_any { None } else { Some((inner, is_optional)) }
        None => if has_any { Some((Any, is_optional)) } else { None }
      }
    }
    _ => None
  }
}

///|
fn decl_type_widening_score(type_ : @ast.TsType) -> Int {
  match decl_classify_optional_like_union(type_) {
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
    if existing.name == import_.name {
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
    if existing.name == func.name {
      if decl_func_widening_score(func) < decl_func_widening_score(existing) {
        funcs[i] = func
      }
      return
    }
  }
  funcs.push(func)
}

///|
fn clone_exported_func(
  exported : ExportedFuncDecl,
  info : DeclModuleInfo,
  modules : Map[String, DeclModuleInfo],
  canonical_types : Map[String, String],
) -> @ast.TsFunc {
  let params : Array[@ast.TsParam] = []
  for param in exported.func.params {
    params.push({
      name: param.name,
      binding: param.binding,
      is_rest: param.is_rest,
      type_: lower_react_utility_type(
        info,
        rewrite_type_refs(info, param.type_, canonical_types),
        modules,
        canonical_types,
      ),
      default: param.default,
    })
  }
  let return_type = lower_react_utility_type(
    info,
    rewrite_type_refs(info, exported.func.return_type, canonical_types),
    modules,
    canonical_types,
  )
  {
    name: exported.export_name,
    params,
    return_type: match return_type {
      Tuple(_) => Named(tuple_result_interface_name(exported.export_name))
      _ => return_type
    },
    body: exported.func.body,
    is_generator: exported.func.is_generator,
    is_async: exported.func.is_async,
  }
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
    type_: lower_react_utility_type(
      info,
      rewrite_type_refs(info, exported.value.type_, canonical_types),
      modules,
      canonical_types,
    ),
  }
}

///|
fn clone_exported_class(
  exported : ExportedClassDecl,
  info : DeclModuleInfo,
  modules : Map[String, DeclModuleInfo],
  canonical_types : Map[String, String],
) -> @ast.TsClassDecl {
  let properties : Array[@ast.TsClassPropertyDecl] = []
  for class_property in exported.class_.properties {
    properties.push({
      name: class_property.name,
      type_: lower_react_utility_type(
        info,
        rewrite_type_refs(info, class_property.type_, canonical_types),
        modules,
        canonical_types,
      ),
      is_static: class_property.is_static,
      is_readonly: class_property.is_readonly,
    })
  }
  let methods : Array[@ast.TsClassMethodDecl] = []
  for class_method in exported.class_.methods {
    let params : Array[(String, @ast.TsType)] = []
    for param in class_method.params {
      let (param_name, param_type) = param
      params.push(
        (
          param_name,
          lower_react_utility_type(
            info,
            rewrite_type_refs(info, param_type, canonical_types),
            modules,
            canonical_types,
          ),
        ),
      )
    }
    methods.push({
      name: class_method.name,
      params,
      return_type: lower_react_utility_type(
        info,
        rewrite_type_refs(info, class_method.return_type, canonical_types),
        modules,
        canonical_types,
      ),
      is_static: class_method.is_static,
    })
  }
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
              rewrite_type_refs(info, param_type, canonical_types),
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
    constructor_params,
    properties,
    methods,
    is_abstract: exported.class_.is_abstract,
    is_constructible: exported.class_.is_constructible,
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
    exported_imports,
    exported_funcs,
    exported_values,
    exported_classes,
    notes,
  ) = collect_exported_decls(graph, export_surface, modules)
  let canonical_types = build_canonical_type_name_map(
    exported_interfaces, exported_classes,
  )
  let tuple_result_interfaces = normalize_tuple_result_interfaces(
    exported_imports, exported_funcs, modules, canonical_types,
  )
  let react_utility_interfaces = normalize_react_utility_interfaces(
    exported_interfaces, exported_imports, exported_funcs, exported_values, exported_classes,
    modules, canonical_types,
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
  for
    iface in collect_interface_dependencies(
      exported_interfaces, exported_imports, exported_funcs, exported_values, exported_classes,
      modules, canonical_types, interfaces,
    ) {
    interfaces.push(iface)
  }
  let imports : Array[@ast.TsImport] = []
  for exported in exported_imports {
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
  for exported in exported_funcs {
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
          clone_exported_class(exported, info, modules, canonical_types),
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
  @parser.emit_moonbit_decl_with_sections(
    { funcs, interfaces, imports, values, classes, namespaces: [] },
    notes,
    notes.length() > 0,
  )
}
