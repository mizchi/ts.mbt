///|
fn Parser::match_ident(self : Parser, name : String) -> Bool {
  match self.peek().kind {
    Ident(n) if n == name => {
      let _ = self.advance()
      true
    }
    _ => false
  }
}

///|
fn Parser::expect_from(self : Parser) -> Unit raise ParseError {
  if self.match_(From) || self.match_ident("from") {
    return
  }
  raise ParseError("Expected 'from' in import/export")
}

///|
fn Parser::maybe_match_type_modifier(self : Parser) -> Bool {
  let next_is_value_name = match self.peek_at(1).kind {
    As | Comma | RBrace => false
    _ => true
  }
  if !next_is_value_name {
    return false
  }
  self.match_(Type) || self.match_ident("type")
}

///|
fn Parser::parse_import_specifiers(self : Parser) -> Unit raise ParseError {
  while !self.check(RBrace) {
    let _ = self.maybe_match_type_modifier()
    let _ = self.parse_binding_ident()
    if self.match_(As) || self.match_ident("as") {
      let _ = self.parse_binding_ident()
    }
    if self.match_(Comma) {
      if self.check(RBrace) {
        break
      }
      continue
    }
    break
  }
}

///|
fn Parser::next_temp(self : Parser, prefix : String) -> String {
  let idx = self.temp_index
  self.temp_index += 1
  prefix + idx.to_string()
}

///|
fn Parser::parse_named_imports(
  self : Parser,
) -> Array[(String, String)] raise ParseError {
  let items : Array[(String, String)] = []
  while !self.check(RBrace) {
    let _ = self.maybe_match_type_modifier()
    let imported = self.parse_binding_ident()
    let local_name = if self.match_(As) || self.match_ident("as") {
      self.parse_binding_ident()
    } else {
      imported
    }
    items.push((imported, local_name))
    if self.match_(Comma) {
      if self.check(RBrace) {
        break
      }
      continue
    }
    break
  }
  items
}

///|
fn Parser::parse_named_exports(
  self : Parser,
) -> Array[(String, String)] raise ParseError {
  let items : Array[(String, String)] = []
  while !self.check(RBrace) {
    let _ = self.maybe_match_type_modifier()
    let local_name = self.parse_binding_ident()
    let export_name = if self.match_(As) || self.match_ident("as") {
      self.parse_binding_ident()
    } else {
      local_name
    }
    items.push((local_name, export_name))
    if self.match_(Comma) {
      if self.check(RBrace) {
        break
      }
      continue
    }
    break
  }
  items
}

///|
fn Parser::parse_declare_class_with_optional_abstract(
  self : Parser,
) -> @ast.TsClassDecl raise ParseError {
  let is_abstract = self.match_ident("abstract")
  self.parse_declare_class(is_abstract)
}

///|
fn empty_ts_module() -> @ast.TsModule {
  {
    funcs: [],
    interfaces: [],
    type_aliases: [],
    imports: [],
    values: [],
    classes: [],
    namespaces: [],
  }
}

///|
fn Parser::parse_declaration_block_source(
  self : Parser,
) -> String raise ParseError {
  let brace_start_pos = self.peek().pos
  let _ = self.expect(LBrace)
  let mut depth = 1
  while depth > 0 {
    let token = self.advance()
    match token.kind {
      LBrace => depth += 1
      RBrace => depth -= 1
      Eof => raise ParseError("Unterminated declaration block")
      _ => ()
    }
  }
  let body_end_pos = self.tokens[self.pos - 1].pos
  if body_end_pos <= brace_start_pos + 1 {
    ""
  } else {
    self.src[brace_start_pos + 1:body_end_pos].to_string()
  }
}

///|
fn parse_ambient_external_module_source(
  body_source : String,
) -> @ast.TsModule raise ParseError {
  if body_source.trim() == "" {
    empty_ts_module()
  } else {
    let parser = Parser::from_source(body_source)
    parser.parse_module_with_seeded_const_values_internal({}, true)
  }
}

///|
fn Parser::parse_ambient_external_module_decl(
  self : Parser,
) -> @ast.TsModule? raise ParseError {
  if !self.match_ident("module") {
    return None
  }
  match self.peek().kind {
    Str(_) => {
      let _ = self.expect_str_literal()
      if self.check(LBrace) {
        let body_source = self.parse_declaration_block_source()
        Some(parse_ambient_external_module_source(body_source))
      } else {
        self.skip_declaration_block()
        Some(empty_ts_module())
      }
    }
    _ => None
  }
}

///|
fn append_module_decls(
  module_ : @ast.TsModule,
  funcs : Array[@ast.TsFunc],
  interfaces : Array[@ast.TsInterface],
  type_aliases : Array[@ast.TsTypeAlias],
  imports : Array[@ast.TsImport],
  values : Array[@ast.TsValueDecl],
  classes : Array[@ast.TsClassDecl],
  namespaces : Array[@ast.TsNamespaceDecl],
) -> Unit {
  for func in module_.funcs {
    funcs.push(func)
  }
  for iface in module_.interfaces {
    interfaces.push(iface)
  }
  for type_alias in module_.type_aliases {
    type_aliases.push(type_alias)
  }
  for import_ in module_.imports {
    imports.push(import_)
  }
  for value in module_.values {
    values.push(value)
  }
  for class_ in module_.classes {
    classes.push(class_)
  }
  for namespace_ in module_.namespaces {
    namespaces.push(namespace_)
  }
}

///|
fn append_ambient_external_module_exports(
  module_ : @ast.TsModule,
  exports : Array[@ast.TsExportSpec],
) -> Unit {
  for func in module_.funcs {
    exports.push({ local_name: func.name, export_name: func.name })
  }
  for iface in module_.interfaces {
    exports.push({ local_name: iface.name, export_name: iface.name })
  }
  for type_alias in module_.type_aliases {
    exports.push({ local_name: type_alias.name, export_name: type_alias.name })
  }
  for import_ in module_.imports {
    exports.push({ local_name: import_.name, export_name: import_.name })
  }
  for value in module_.values {
    exports.push({ local_name: value.name, export_name: value.name })
  }
  for class_ in module_.classes {
    exports.push({ local_name: class_.name, export_name: class_.name })
  }
  for namespace_ in module_.namespaces {
    exports.push({ local_name: namespace_.name, export_name: namespace_.name })
  }
}

///|
fn Parser::parse_namespace_decl(
  self : Parser,
) -> (@ast.TsValueDecl?, @ast.TsNamespaceDecl?)? raise ParseError {
  let keyword = match self.peek().kind {
    Ident(name) if name == "namespace" || name == "module" || name == "global" =>
      name
    _ => return None
  }
  let _ = self.advance()
  if keyword == "global" {
    self.skip_declaration_block()
    return Some((None, None))
  }
  let name = if self.is_qualified_type_name_part(0) {
    Some(self.parse_binding_ident())
  } else {
    None
  }
  while self.match_(Dot) {
    if self.is_qualified_type_name_part(0) {
      let _ = self.parse_binding_ident()
    } else {
      break
    }
  }
  let value = match name {
    Some(name) => {
      let next_value : @ast.TsValueDecl = { name, type_: @ast.TsType::Any }
      Some(next_value)
    }
    None => None
  }
  let namespace_ = match name {
    Some(name) if self.check(LBrace) => {
      let body_source = self.parse_declaration_block_source()
      let module_ = if body_source.trim() == "" {
        empty_ts_module()
      } else {
        let parser = Parser::from_source(body_source)
        parser.parse_module_with_seeded_const_values_internal({}, true)
      }
      let next_namespace : @ast.TsNamespaceDecl = { name, module_ }
      Some(next_namespace)
    }
    _ => {
      self.skip_declaration_block()
      None
    }
  }
  Some((value, namespace_))
}

///|
fn Parser::parse_namespace_decl_value(
  self : Parser,
) -> @ast.TsValueDecl? raise ParseError {
  match self.parse_namespace_decl() {
    Some((value, _)) => value
    None => None
  }
}

///|
fn Parser::parse_import_equals_decl(
  self : Parser,
  local_name : String,
) -> @ast.TsImportDecl raise ParseError {
  let _ = self.expect(Eq)
  let module_spec = if self.match_ident("require") {
    let _ = self.expect(LParen)
    let spec = self.expect_str_literal()
    let _ = self.expect(RParen)
    spec
  } else {
    self.skip_until_semicolon()
    ""
  }
  self.consume_semicolon()
  {
    module_spec,
    default_binding: None,
    namespace_binding: Some(local_name),
    named_bindings: [],
    side_effect_only: false,
    type_only: false,
  }
}

///|
fn collect_decl_names_from_stmt(
  stmt : @ast.TsStmt,
  names : Array[String],
) -> Unit {
  match stmt {
    Var(binding, _, _) | Let(binding, _, _) | Const(binding, _, _) =>
      collect_binding_names(binding, names)
    Block(block) =>
      for inner in block.stmts {
        collect_decl_names_from_stmt(inner, names)
      }
    _ => ()
  }
}

///|
fn collect_static_const_exprs_from_stmt(
  stmt : @ast.TsStmt,
  const_values : Map[String, @ast.TsExpr],
) -> Unit {
  match stmt {
    Const(binding, _, init) =>
      collect_static_const_exprs_from_binding(binding, init, const_values)
    Block(block) =>
      for inner in block.stmts {
        collect_static_const_exprs_from_stmt(inner, const_values)
      }
    _ => ()
  }
}

///|
fn collect_static_local_exprs_from_stmt(
  stmt : @ast.TsStmt,
  const_values : Map[String, @ast.TsExpr],
) -> Unit {
  match stmt {
    Const(binding, _, init) | Let(binding, _, init) =>
      collect_static_const_exprs_from_binding(binding, init, const_values)
    Block(block) =>
      for inner in block.stmts {
        collect_static_local_exprs_from_stmt(inner, const_values)
      }
    _ => ()
  }
}

///|
fn value_decl_static_return_expr_from_block_with_depth(
  block : @ast.TsBlock,
  const_values : Map[String, @ast.TsExpr],
  depth : Int,
) -> @ast.TsExpr? {
  if depth <= 0 {
    return None
  }
  let local_const_values : Map[String, @ast.TsExpr] = {}
  for entry in const_values {
    local_const_values[entry.0] = entry.1
  }
  for stmt in block.stmts {
    match stmt {
      @ast.TsStmt::Const(_, _, _) | @ast.TsStmt::Let(_, _, _) =>
        collect_static_local_exprs_from_stmt(stmt, local_const_values)
      @ast.TsStmt::Return(Some(expr)) =>
        return value_decl_static_resolve_expr_with_depth(
          expr,
          local_const_values,
          depth - 1,
        )
      @ast.TsStmt::Return(None) => return None
      @ast.TsStmt::Empty => ()
      _ => return None
    }
  }
  None
}

///|
fn value_decl_static_resolve_expr_with_depth(
  expr : @ast.TsExpr,
  const_values : Map[String, @ast.TsExpr],
  depth : Int,
) -> @ast.TsExpr? {
  if depth <= 0 {
    return None
  }
  match expr {
    @ast.TsExpr::ArrayLit(items) => {
      let resolved_items : Array[@ast.TsExpr] = []
      for item in items {
        match item {
          @ast.TsExpr::ArrayHole => resolved_items.push(item)
          _ =>
            match
              value_decl_static_resolve_expr_with_depth(
                item,
                const_values,
                depth - 1,
              ) {
              Some(value) => resolved_items.push(value)
              None => return None
            }
        }
      }
      Some(@ast.TsExpr::ArrayLit(resolved_items))
    }
    @ast.TsExpr::ObjectLit(props) => {
      let resolved_props : Array[(String, @ast.TsExpr)] = []
      for prop in props {
        let (key, value) = prop
        match
          value_decl_static_resolve_expr_with_depth(
            value,
            const_values,
            depth - 1,
          ) {
          Some(next_value) => resolved_props.push((key, next_value))
          None => return None
        }
      }
      Some(@ast.TsExpr::ObjectLit(resolved_props))
    }
    @ast.TsExpr::Var(name) =>
      match const_values.get(name) {
        Some(value) =>
          value_decl_static_resolve_expr_with_depth(
            value,
            const_values,
            depth - 1,
          )
        None => Some(expr)
      }
    @ast.TsExpr::CallExpr(callee, args) =>
      if args.length() != 0 {
        None
      } else {
        match
          value_decl_static_zero_arg_call_result_expr_with_depth(
            callee,
            const_values,
            depth - 1,
          ) {
          Some(value) =>
            value_decl_static_resolve_expr_with_depth(
              value,
              const_values,
              depth - 1,
            )
          None => None
        }
      }
    _ => Some(expr)
  }
}

///|
fn value_decl_static_zero_arg_call_result_expr_with_depth(
  callee : @ast.TsExpr,
  const_values : Map[String, @ast.TsExpr],
  depth : Int,
) -> @ast.TsExpr? {
  if depth <= 0 {
    return None
  }
  match callee {
    @ast.TsExpr::ArrowFunc(params, body, is_async) =>
      if params.length() != 0 || is_async {
        None
      } else {
        match body {
          @ast.TsArrowBody::ArrowExpr(expr) =>
            value_decl_static_resolve_expr_with_depth(
              expr,
              const_values,
              depth - 1,
            )
          @ast.TsArrowBody::ArrowBlock(block) =>
            value_decl_static_return_expr_from_block_with_depth(
              block,
              const_values,
              depth - 1,
            )
        }
      }
    @ast.TsExpr::FuncExpr(func) =>
      if func.params.length() != 0 || func.is_async || func.is_generator {
        None
      } else {
        value_decl_static_return_expr_from_block_with_depth(
          func.body,
          const_values,
          depth - 1,
        )
      }
    @ast.TsExpr::Var(name) =>
      match const_values.get(name) {
        Some(value) =>
          value_decl_static_zero_arg_call_result_expr_with_depth(
            value,
            const_values,
            depth - 1,
          )
        None => None
      }
    _ => None
  }
}

///|
fn value_decl_static_object_prop_expr_with_depth(
  expr : @ast.TsExpr,
  key : String,
  const_values : Map[String, @ast.TsExpr],
  depth : Int,
) -> @ast.TsExpr? {
  if depth <= 0 {
    return None
  }
  match expr {
    @ast.TsExpr::ObjectLit(props) => {
      for prop in props {
        if prop.0 == key {
          return Some(prop.1)
        }
      }
      None
    }
    @ast.TsExpr::Var(name) =>
      match const_values.get(name) {
        Some(value) =>
          value_decl_static_object_prop_expr_with_depth(
            value,
            key,
            const_values,
            depth - 1,
          )
        None => None
      }
    @ast.TsExpr::CallExpr(callee, args) =>
      if args.length() != 0 {
        None
      } else {
        match
          value_decl_static_zero_arg_call_result_expr_with_depth(
            callee,
            const_values,
            depth - 1,
          ) {
          Some(value) =>
            value_decl_static_object_prop_expr_with_depth(
              value,
              key,
              const_values,
              depth - 1,
            )
          None => None
        }
      }
    @ast.TsExpr::PropAccess(target, prop) =>
      match
        value_decl_static_object_prop_expr_with_depth(
          target,
          prop,
          const_values,
          depth - 1,
        ) {
        Some(value) =>
          value_decl_static_object_prop_expr_with_depth(
            value,
            key,
            const_values,
            depth - 1,
          )
        None => None
      }
    @ast.TsExpr::IndexAccess(target, index_expr) =>
      match
        value_decl_static_key_from_expr_with_depth(
          index_expr,
          const_values,
          depth - 1,
        ) {
        Some(index_key) =>
          match value_decl_parse_nonnegative_int_string(index_key) {
            Some(index) =>
              match
                value_decl_static_array_item_expr_with_depth(
                  target,
                  index,
                  const_values,
                  depth - 1,
                ) {
                Some(value) =>
                  value_decl_static_object_prop_expr_with_depth(
                    value,
                    key,
                    const_values,
                    depth - 1,
                  )
                None =>
                  match
                    value_decl_static_object_prop_expr_with_depth(
                      target,
                      index_key,
                      const_values,
                      depth - 1,
                    ) {
                    Some(value) =>
                      value_decl_static_object_prop_expr_with_depth(
                        value,
                        key,
                        const_values,
                        depth - 1,
                      )
                    None => None
                  }
              }
            None =>
              match
                value_decl_static_object_prop_expr_with_depth(
                  target,
                  index_key,
                  const_values,
                  depth - 1,
                ) {
                Some(value) =>
                  value_decl_static_object_prop_expr_with_depth(
                    value,
                    key,
                    const_values,
                    depth - 1,
                  )
                None => None
              }
          }
        None => None
      }
    _ => None
  }
}

///|
fn value_decl_parse_nonnegative_int_string(text : String) -> Int? {
  if text == "" {
    return None
  }
  let mut value = 0
  for c in text {
    if !value_decl_is_ascii_digit(c) {
      return None
    }
    value = value * 10 + (c.to_int() - '0'.to_int())
  }
  Some(value)
}

///|
fn value_decl_static_object_prop_expr(
  expr : @ast.TsExpr,
  key : String,
  const_values : Map[String, @ast.TsExpr],
) -> @ast.TsExpr? {
  value_decl_static_object_prop_expr_with_depth(expr, key, const_values, 16)
}

///|
fn value_decl_static_array_item_expr_with_depth(
  expr : @ast.TsExpr,
  index : Int,
  const_values : Map[String, @ast.TsExpr],
  depth : Int,
) -> @ast.TsExpr? {
  if depth <= 0 {
    return None
  }
  match expr {
    @ast.TsExpr::ArrayLit(items) =>
      match items.get(index) {
        Some(item) =>
          match item {
            @ast.TsExpr::ArrayHole | @ast.TsExpr::Spread(_) => None
            _ => Some(item)
          }
        None => None
      }
    @ast.TsExpr::Var(name) =>
      match const_values.get(name) {
        Some(value) =>
          value_decl_static_array_item_expr_with_depth(
            value,
            index,
            const_values,
            depth - 1,
          )
        None => None
      }
    @ast.TsExpr::CallExpr(callee, args) =>
      if args.length() != 0 {
        None
      } else {
        match
          value_decl_static_zero_arg_call_result_expr_with_depth(
            callee,
            const_values,
            depth - 1,
          ) {
          Some(value) =>
            value_decl_static_array_item_expr_with_depth(
              value,
              index,
              const_values,
              depth - 1,
            )
          None => None
        }
      }
    @ast.TsExpr::PropAccess(target, prop) =>
      match
        value_decl_static_object_prop_expr_with_depth(
          target,
          prop,
          const_values,
          depth - 1,
        ) {
        Some(value) =>
          value_decl_static_array_item_expr_with_depth(
            value,
            index,
            const_values,
            depth - 1,
          )
        None => None
      }
    @ast.TsExpr::IndexAccess(target, index_expr) =>
      match
        value_decl_static_key_from_expr_with_depth(
          index_expr,
          const_values,
          depth - 1,
        ) {
        Some(index_key) =>
          match value_decl_parse_nonnegative_int_string(index_key) {
            Some(inner_index) =>
              match
                value_decl_static_array_item_expr_with_depth(
                  target,
                  inner_index,
                  const_values,
                  depth - 1,
                ) {
                Some(value) =>
                  value_decl_static_array_item_expr_with_depth(
                    value,
                    index,
                    const_values,
                    depth - 1,
                  )
                None =>
                  match
                    value_decl_static_object_prop_expr_with_depth(
                      target,
                      index_key,
                      const_values,
                      depth - 1,
                    ) {
                    Some(value) =>
                      value_decl_static_array_item_expr_with_depth(
                        value,
                        index,
                        const_values,
                        depth - 1,
                      )
                    None => None
                  }
              }
            None =>
              match
                value_decl_static_object_prop_expr_with_depth(
                  target,
                  index_key,
                  const_values,
                  depth - 1,
                ) {
                Some(value) =>
                  value_decl_static_array_item_expr_with_depth(
                    value,
                    index,
                    const_values,
                    depth - 1,
                  )
                None => None
              }
          }
        None => None
      }
    _ => None
  }
}

///|
fn value_decl_static_array_item_expr(
  expr : @ast.TsExpr,
  index : Int,
  const_values : Map[String, @ast.TsExpr],
) -> @ast.TsExpr? {
  value_decl_static_array_item_expr_with_depth(expr, index, const_values, 16)
}

///|
fn value_decl_static_array_rest_expr_with_depth(
  expr : @ast.TsExpr,
  start_index : Int,
  const_values : Map[String, @ast.TsExpr],
  depth : Int,
) -> @ast.TsExpr? {
  if depth <= 0 {
    return None
  }
  match expr {
    @ast.TsExpr::ArrayLit(items) => {
      let rest_items : Array[@ast.TsExpr] = []
      for i, item in items {
        if i < start_index {
          continue
        }
        match item {
          @ast.TsExpr::Spread(_) => return None
          _ => rest_items.push(item)
        }
      }
      Some(@ast.TsExpr::ArrayLit(rest_items))
    }
    @ast.TsExpr::Var(name) =>
      match const_values.get(name) {
        Some(value) =>
          value_decl_static_array_rest_expr_with_depth(
            value,
            start_index,
            const_values,
            depth - 1,
          )
        None => None
      }
    @ast.TsExpr::CallExpr(callee, args) =>
      if args.length() != 0 {
        None
      } else {
        match
          value_decl_static_zero_arg_call_result_expr_with_depth(
            callee,
            const_values,
            depth - 1,
          ) {
          Some(value) =>
            value_decl_static_array_rest_expr_with_depth(
              value,
              start_index,
              const_values,
              depth - 1,
            )
          None => None
        }
      }
    _ => None
  }
}

///|
fn value_decl_static_array_rest_expr(
  expr : @ast.TsExpr,
  start_index : Int,
  const_values : Map[String, @ast.TsExpr],
) -> @ast.TsExpr? {
  value_decl_static_array_rest_expr_with_depth(
    expr, start_index, const_values, 16,
  )
}

///|
fn value_decl_static_object_rest_expr_with_depth(
  expr : @ast.TsExpr,
  obj_binding : @ast.TsObjectBinding,
  const_values : Map[String, @ast.TsExpr],
  depth : Int,
) -> @ast.TsExpr? {
  if depth <= 0 {
    return None
  }
  match expr {
    @ast.TsExpr::ObjectLit(props) => {
      let excluded_keys : Array[String] = []
      for prop in obj_binding.props {
        match prop.key_expr {
          Some(key_expr) =>
            match value_decl_static_key_from_expr(key_expr, const_values) {
              Some(key) => excluded_keys.push(key)
              None => return None
            }
          None => excluded_keys.push(prop.key)
        }
      }
      let rest_props : Array[(String, @ast.TsExpr)] = []
      for prop in props {
        if !excluded_keys.contains(prop.0) {
          rest_props.push(prop)
        }
      }
      Some(@ast.TsExpr::ObjectLit(rest_props))
    }
    @ast.TsExpr::Var(name) =>
      match const_values.get(name) {
        Some(value) =>
          value_decl_static_object_rest_expr_with_depth(
            value,
            obj_binding,
            const_values,
            depth - 1,
          )
        None => None
      }
    @ast.TsExpr::CallExpr(callee, args) =>
      if args.length() != 0 {
        None
      } else {
        match
          value_decl_static_zero_arg_call_result_expr_with_depth(
            callee,
            const_values,
            depth - 1,
          ) {
          Some(value) =>
            value_decl_static_object_rest_expr_with_depth(
              value,
              obj_binding,
              const_values,
              depth - 1,
            )
          None => None
        }
      }
    _ => None
  }
}

///|
fn value_decl_static_object_rest_expr(
  expr : @ast.TsExpr,
  obj_binding : @ast.TsObjectBinding,
  const_values : Map[String, @ast.TsExpr],
) -> @ast.TsExpr? {
  value_decl_static_object_rest_expr_with_depth(
    expr, obj_binding, const_values, 16,
  )
}

///|
fn collect_static_const_exprs_from_binding(
  binding : @ast.TsBinding,
  init : @ast.TsExpr,
  const_values : Map[String, @ast.TsExpr],
) -> Unit {
  match binding {
    @ast.TsBinding::Ident(name) => const_values[name] = init
    @ast.TsBinding::Array(arr_binding) => {
      for i, item in arr_binding.items {
        match item {
          Some(elem) => {
            let init_expr = match
              value_decl_static_array_item_expr(init, i, const_values) {
              Some(expr) => Some(expr)
              None => elem.default
            }
            match init_expr {
              Some(expr) =>
                collect_static_const_exprs_from_binding(
                  elem.binding,
                  expr,
                  const_values,
                )
              None => ()
            }
          }
          None => ()
        }
      }
      match arr_binding.rest {
        Some(rest) =>
          match
            value_decl_static_array_rest_expr(
              init,
              arr_binding.items.length(),
              const_values,
            ) {
            Some(expr) =>
              collect_static_const_exprs_from_binding(rest, expr, const_values)
            None => ()
          }
        None => ()
      }
    }
    @ast.TsBinding::Object(obj_binding) => {
      for prop in obj_binding.props {
        let init_expr = match prop.key_expr {
          Some(key_expr) =>
            match value_decl_static_key_from_expr(key_expr, const_values) {
              Some(key) =>
                value_decl_static_object_prop_expr(init, key, const_values)
              None => None
            }
          None =>
            value_decl_static_object_prop_expr(init, prop.key, const_values)
        }
        match init_expr {
          Some(expr) =>
            collect_static_const_exprs_from_binding(
              prop.binding,
              expr,
              const_values,
            )
          None =>
            match prop.default {
              Some(default) =>
                collect_static_const_exprs_from_binding(
                  prop.binding,
                  default,
                  const_values,
                )
              None => ()
            }
        }
      }
      match obj_binding.rest {
        Some(rest_name) =>
          match
            value_decl_static_object_rest_expr(init, obj_binding, const_values) {
            Some(expr) => const_values[rest_name] = expr
            None => ()
          }
        None => ()
      }
    }
    @ast.TsBinding::Target(_) => ()
  }
}

///|
fn collect_value_decls_from_stmt(
  stmt : @ast.TsStmt,
  values : Array[@ast.TsValueDecl],
  const_values : Map[String, @ast.TsExpr],
) -> Unit {
  match stmt {
    Var(binding, type_, init)
    | Let(binding, type_, init)
    | Const(binding, type_, init) =>
      collect_value_decls_from_binding(
        binding,
        type_,
        Some(init),
        values,
        const_values,
      )
    Block(block) =>
      for inner in block.stmts {
        collect_value_decls_from_stmt(inner, values, const_values)
      }
    _ => ()
  }
}

///|
fn value_decl_infer_type_from_expr(expr : @ast.TsExpr) -> @ast.TsType {
  match expr {
    @ast.TsExpr::NumberLit(_) => @ast.TsType::Number
    @ast.TsExpr::IntLit(_) => @ast.TsType::Int
    @ast.TsExpr::BoolLit(_) => @ast.TsType::Boolean
    @ast.TsExpr::StringLit(_) => @ast.TsType::String_
    @ast.TsExpr::NullLit => @ast.TsType::Null
    @ast.TsExpr::ArrayLit(items) => {
      let item_types : Array[@ast.TsType] = []
      for item in items {
        match item {
          @ast.TsExpr::ArrayHole => item_types.push(@ast.TsType::Any)
          _ => item_types.push(value_decl_infer_type_from_expr(item))
        }
      }
      @ast.TsType::Tuple(item_types)
    }
    @ast.TsExpr::ObjectLit(props) => {
      let prop_types : Array[(@ast.TsType, @ast.TsType)] = []
      for prop in props {
        let (key, value) = prop
        prop_types.push(
          (@ast.TsType::Literal(key), value_decl_infer_type_from_expr(value)),
        )
      }
      @ast.TsType::Object(prop_types)
    }
    _ => @ast.TsType::Any
  }
}

///|
fn value_decl_is_ascii_letter(c : Char) -> Bool {
  (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
}

///|
fn value_decl_is_ascii_digit(c : Char) -> Bool {
  c >= '0' && c <= '9'
}

///|
fn value_decl_to_upper_ascii(c : Char) -> Char {
  if c >= 'a' && c <= 'z' {
    (c.to_int() - 32).unsafe_to_char()
  } else {
    c
  }
}

///|
fn value_decl_struct_name(name : String) -> String {
  let mut result = ""
  let mut capitalize_next = true
  for c in name {
    if value_decl_is_ascii_letter(c) || value_decl_is_ascii_digit(c) {
      if capitalize_next {
        result += value_decl_to_upper_ascii(c).to_string()
        capitalize_next = false
      } else {
        result += c.to_string()
      }
    } else {
      capitalize_next = true
    }
  }
  if result == "" {
    "GeneratedStruct"
  } else {
    result
  }
}

///|
fn value_decl_resolve_type(
  type_ : @ast.TsType,
  init : @ast.TsExpr?,
) -> @ast.TsType {
  if type_ != @ast.TsType::Any {
    return type_
  }
  match init {
    Some(expr) => value_decl_infer_type_from_expr(expr)
    None => @ast.TsType::Any
  }
}

///|
fn value_decl_static_key_from_expr_with_depth(
  expr : @ast.TsExpr,
  const_values : Map[String, @ast.TsExpr],
  depth : Int,
) -> String? {
  if depth <= 0 {
    return None
  }
  match expr {
    @ast.TsExpr::StringLit(key) => Some(key)
    @ast.TsExpr::IntLit(key) => Some(key.to_string())
    @ast.TsExpr::BigIntLit(key) => Some(key)
    @ast.TsExpr::BoolLit(key) => Some(if key { "true" } else { "false" })
    @ast.TsExpr::NullLit => Some("null")
    @ast.TsExpr::PropAccess(target, prop) =>
      match
        value_decl_static_object_prop_expr_with_depth(
          target,
          prop,
          const_values,
          depth - 1,
        ) {
        Some(value) =>
          value_decl_static_key_from_expr_with_depth(
            value,
            const_values,
            depth - 1,
          )
        None => None
      }
    @ast.TsExpr::IndexAccess(target, index_expr) =>
      match
        value_decl_static_key_from_expr_with_depth(
          index_expr,
          const_values,
          depth - 1,
        ) {
        Some(key) =>
          match value_decl_parse_nonnegative_int_string(key) {
            Some(index) =>
              match
                value_decl_static_array_item_expr_with_depth(
                  target,
                  index,
                  const_values,
                  depth - 1,
                ) {
                Some(value) =>
                  value_decl_static_key_from_expr_with_depth(
                    value,
                    const_values,
                    depth - 1,
                  )
                None =>
                  match
                    value_decl_static_object_prop_expr_with_depth(
                      target,
                      key,
                      const_values,
                      depth - 1,
                    ) {
                    Some(value) =>
                      value_decl_static_key_from_expr_with_depth(
                        value,
                        const_values,
                        depth - 1,
                      )
                    None => None
                  }
              }
            None =>
              match
                value_decl_static_object_prop_expr_with_depth(
                  target,
                  key,
                  const_values,
                  depth - 1,
                ) {
                Some(value) =>
                  value_decl_static_key_from_expr_with_depth(
                    value,
                    const_values,
                    depth - 1,
                  )
                None => None
              }
          }
        None => None
      }
    @ast.TsExpr::Var(name) =>
      match const_values.get(name) {
        Some(value) =>
          value_decl_static_key_from_expr_with_depth(
            value,
            const_values,
            depth - 1,
          )
        None => None
      }
    @ast.TsExpr::NumberLit(key) =>
      if key.to_int().to_double() == key {
        Some(key.to_int().to_string())
      } else {
        Some(key.to_string())
      }
    @ast.TsExpr::TemplateLiteral(cooked_parts, exprs) => {
      if cooked_parts.length() != exprs.length() + 1 {
        return None
      }
      let mut key = ""
      for i, part in cooked_parts {
        key += part
        match exprs.get(i) {
          Some(expr) =>
            match
              value_decl_static_key_from_expr_with_depth(
                expr,
                const_values,
                depth - 1,
              ) {
              Some(segment) => key += segment
              None => return None
            }
          None => ()
        }
      }
      Some(key)
    }
    @ast.TsExpr::BinOp(@ast.TsBinOp::Add, left, right) =>
      match (left, right) {
        (@ast.TsExpr::StringLit(_), _)
        | (@ast.TsExpr::TemplateLiteral(_, _), _)
        | (_, @ast.TsExpr::StringLit(_))
        | (_, @ast.TsExpr::TemplateLiteral(_, _)) =>
          match
            (
              value_decl_static_key_from_expr_with_depth(
                left,
                const_values,
                depth - 1,
              ),
              value_decl_static_key_from_expr_with_depth(
                right,
                const_values,
                depth - 1,
              ),
            ) {
            (Some(left_key), Some(right_key)) => Some(left_key + right_key)
            _ => None
          }
        (@ast.TsExpr::IntLit(left_num), @ast.TsExpr::IntLit(right_num)) =>
          Some((left_num + right_num).to_string())
        (@ast.TsExpr::NumberLit(left_num), @ast.TsExpr::NumberLit(right_num)) =>
          Some((left_num + right_num).to_string())
        (@ast.TsExpr::IntLit(left_num), @ast.TsExpr::NumberLit(right_num)) =>
          Some((left_num.to_double() + right_num).to_string())
        (@ast.TsExpr::NumberLit(left_num), @ast.TsExpr::IntLit(right_num)) =>
          Some((left_num + right_num.to_double()).to_string())
        _ => None
      }
    @ast.TsExpr::UnaryOp(@ast.TsUnaryOp::Plus, inner) =>
      match inner {
        @ast.TsExpr::IntLit(num) => Some(num.to_string())
        @ast.TsExpr::NumberLit(num) => Some(num.to_string())
        _ => None
      }
    @ast.TsExpr::UnaryOp(@ast.TsUnaryOp::Void, _) => Some("undefined")
    @ast.TsExpr::UnaryOp(@ast.TsUnaryOp::Neg, inner) =>
      match inner {
        @ast.TsExpr::IntLit(num) => Some((-num).to_string())
        @ast.TsExpr::NumberLit(num) => Some((-num).to_string())
        @ast.TsExpr::BigIntLit(num) => Some("-" + num)
        _ => None
      }
    _ => None
  }
}

///|
fn value_decl_static_key_from_expr(
  expr : @ast.TsExpr,
  const_values : Map[String, @ast.TsExpr],
) -> String? {
  value_decl_static_key_from_expr_with_depth(expr, const_values, 16)
}

///|
fn value_decl_object_prop_type(
  type_ : @ast.TsType,
  key : String,
) -> @ast.TsType {
  match type_ {
    @ast.TsType::Object(props) => {
      for prop in props {
        match prop.0 {
          @ast.TsType::Literal(prop_key) if prop_key == key => return prop.1
          _ => ()
        }
      }
      @ast.TsType::Any
    }
    @ast.TsType::Struct(_, fields) => {
      for field in fields {
        if field.0 == key {
          return field.1
        }
      }
      @ast.TsType::Any
    }
    _ => @ast.TsType::Any
  }
}

///|
fn value_decl_array_item_type(type_ : @ast.TsType, index : Int) -> @ast.TsType {
  match type_ {
    @ast.TsType::Tuple(items) =>
      match items.get(index) {
        Some(item_type) => item_type
        None => @ast.TsType::Any
      }
    @ast.TsType::Array(item_type) => item_type
    _ => @ast.TsType::Any
  }
}

///|
fn value_decl_tuple_rest_item_type(
  items : Array[@ast.TsType],
  start_index : Int,
) -> @ast.TsType {
  let mut rest_item_type = @ast.TsType::Any
  let mut found = false
  for i, item_type in items {
    if i < start_index {
      continue
    }
    if !found {
      rest_item_type = item_type
      found = true
      continue
    }
    if rest_item_type != item_type {
      return @ast.TsType::Any
    }
  }
  if found {
    rest_item_type
  } else {
    @ast.TsType::Any
  }
}

///|
fn value_decl_array_rest_type(
  type_ : @ast.TsType,
  start_index : Int,
) -> @ast.TsType {
  match type_ {
    @ast.TsType::Tuple(items) =>
      @ast.TsType::Array(value_decl_tuple_rest_item_type(items, start_index))
    @ast.TsType::Array(item_type) => @ast.TsType::Array(item_type)
    _ => @ast.TsType::Any
  }
}

///|
fn value_decl_object_rest_struct_type(
  type_ : @ast.TsType,
  obj_binding : @ast.TsObjectBinding,
  rest_name : String,
  const_values : Map[String, @ast.TsExpr],
) -> @ast.TsType {
  let excluded_keys : Array[String] = []
  for prop in obj_binding.props {
    match prop.key_expr {
      Some(key_expr) =>
        match value_decl_static_key_from_expr(key_expr, const_values) {
          Some(key) => excluded_keys.push(key)
          None => return @ast.TsType::Any
        }
      None => excluded_keys.push(prop.key)
    }
  }
  let fields : Array[(String, @ast.TsType)] = []
  match type_ {
    @ast.TsType::Object(props) =>
      for prop in props {
        match prop.0 {
          @ast.TsType::Literal(key) =>
            if !excluded_keys.contains(key) {
              fields.push((key, prop.1))
            }
          _ => ()
        }
      }
    @ast.TsType::Struct(_, struct_fields) =>
      for field in struct_fields {
        let (field_name, field_type) = field
        if !excluded_keys.contains(field_name) {
          fields.push((field_name, field_type))
        }
      }
    _ => return @ast.TsType::Any
  }
  @ast.TsType::Struct(value_decl_struct_name(rest_name), fields)
}

///|
fn collect_value_decls_from_binding(
  binding : @ast.TsBinding,
  type_ : @ast.TsType,
  init : @ast.TsExpr?,
  values : Array[@ast.TsValueDecl],
  const_values : Map[String, @ast.TsExpr],
) -> Unit {
  let source_type = value_decl_resolve_type(type_, init)
  match binding {
    @ast.TsBinding::Ident(name) => values.push({ name, type_: source_type })
    @ast.TsBinding::Array(arr_binding) => {
      for i, item in arr_binding.items {
        match item {
          Some(elem) =>
            collect_value_decls_from_binding(
              elem.binding,
              value_decl_array_item_type(source_type, i),
              None,
              values,
              const_values,
            )
          None => ()
        }
      }
      match arr_binding.rest {
        Some(rest) =>
          collect_value_decls_from_binding(
            rest,
            value_decl_array_rest_type(source_type, arr_binding.items.length()),
            None,
            values,
            const_values,
          )
        None => ()
      }
    }
    @ast.TsBinding::Object(obj_binding) => {
      for prop in obj_binding.props {
        let prop_type = match prop.key_expr {
          Some(key_expr) =>
            match value_decl_static_key_from_expr(key_expr, const_values) {
              Some(key) => value_decl_object_prop_type(source_type, key)
              None => @ast.TsType::Any
            }
          None => value_decl_object_prop_type(source_type, prop.key)
        }
        collect_value_decls_from_binding(
          prop.binding,
          prop_type,
          None,
          values,
          const_values,
        )
      }
      match obj_binding.rest {
        Some(rest_name) =>
          values.push({
            name: rest_name,
            type_: value_decl_object_rest_struct_type(
              source_type, obj_binding, rest_name, const_values,
            ),
          })
        None => ()
      }
    }
    @ast.TsBinding::Target(_) => ()
  }
}

///|
fn collect_binding_names(
  binding : @ast.TsBinding,
  names : Array[String],
) -> Unit {
  match binding {
    @ast.TsBinding::Ident(name) => names.push(name)
    @ast.TsBinding::Array(arr_binding) => {
      for item in arr_binding.items {
        match item {
          Some(elem) => collect_binding_names(elem.binding, names)
          None => ()
        }
      }
      match arr_binding.rest {
        Some(rest) => collect_binding_names(rest, names)
        None => ()
      }
    }
    @ast.TsBinding::Object(obj_binding) => {
      for prop in obj_binding.props {
        collect_binding_names(prop.binding, names)
      }
      match obj_binding.rest {
        Some(name) => names.push(name)
        None => ()
      }
    }
    @ast.TsBinding::Target(_) => () // Expression targets don't have names
  }
}

///|
fn Parser::parse_import_decl(
  self : Parser,
) -> @ast.TsImportDecl raise ParseError {
  let _ = self.expect(Import)
  let mut type_only = false
  if self.match_(Type) || self.match_ident("type") {
    type_only = true
  }
  match self.peek().kind {
    Str(_) => {
      let module_spec = self.expect_str_literal()
      self.skip_import_attributes()
      self.consume_semicolon()
      return {
        module_spec,
        default_binding: None,
        namespace_binding: None,
        named_bindings: [],
        side_effect_only: true,
        type_only,
      }
    }
    _ => ()
  }
  let mut default_binding : String? = None
  let mut namespace_binding : String? = None
  let named_bindings : Array[(String, String)] = []
  match self.peek().kind {
    Ident(_) =>
      if !type_only && self.peek_at(1).kind == Eq {
        let local_name = self.parse_binding_ident()
        return self.parse_import_equals_decl(local_name)
      }
    _ => ()
  }
  if !self.check(Star) && !self.check(LBrace) {
    default_binding = Some(self.parse_binding_ident())
    if self.match_(Comma) {
      // continue to namespace/named
    } else {
      self.expect_from()
      let module_spec = self.expect_str_literal()
      self.skip_import_attributes()
      self.consume_semicolon()
      return {
        module_spec,
        default_binding,
        namespace_binding: None,
        named_bindings,
        side_effect_only: false,
        type_only,
      }
    }
  }
  if self.match_(Star) {
    if !(self.match_(As) || self.match_ident("as")) {
      raise ParseError("Expected 'as' in import namespace")
    }
    namespace_binding = Some(self.parse_binding_ident())
  } else if self.match_(LBrace) {
    let items = self.parse_named_imports()
    for item in items {
      named_bindings.push(item)
    }
    let _ = self.expect(RBrace)
  }
  self.expect_from()
  let module_spec = self.expect_str_literal()
  self.skip_import_attributes()
  self.consume_semicolon()
  {
    module_spec,
    default_binding,
    namespace_binding,
    named_bindings,
    side_effect_only: false,
    type_only,
  }
}

///|
fn Parser::skip_import_attributes(self : Parser) -> Unit {
  if !(self.match_(With) || self.match_ident("assert")) {
    return
  }
  if self.check(LBrace) {
    self.skip_object_type()
  }
}

///|
fn Parser::parse_export_decl_for_module(
  self : Parser,
  const_values : Map[String, @ast.TsExpr],
) -> (Array[@ast.TsStmt], Array[@ast.TsExportSpec], Array[@ast.TsReExportSpec]) raise ParseError {
  let stmts : Array[@ast.TsStmt] = []
  let exports : Array[@ast.TsExportSpec] = []
  let reexports : Array[@ast.TsReExportSpec] = []
  let _ = self.expect(Export)
  if self.match_(As) || self.match_ident("as") {
    if self.match_ident("namespace") {
      let _ = self.parse_binding_ident()
      self.consume_semicolon()
      return (stmts, exports, reexports)
    }
    raise ParseError("Unsupported export statement")
  }
  if self.match_(Eq) {
    let expr = self.parse_expr()
    let local_name = match expr {
      @ast.TsExpr::Var(name) => name
      _ => {
        let temp = self.next_temp("__export_default__")
        stmts.push(Const(@ast.TsBinding::Ident(temp), Any, expr))
        temp
      }
    }
    exports.push({ local_name, export_name: "default" })
    self.consume_semicolon()
    return (stmts, exports, reexports)
  }
  if self.match_(Type) || self.match_ident("type") {
    if self.match_(Star) {
      if self.match_(From) || self.match_ident("from") {
        let _ = self.expect_str_literal()
      }
      self.consume_semicolon()
      return (stmts, exports, reexports)
    }
    if self.match_(LBrace) {
      let _ = self.parse_named_exports()
      let _ = self.expect(RBrace)
      if self.match_(From) || self.match_ident("from") {
        let _ = self.expect_str_literal()
      }
      self.consume_semicolon()
      return (stmts, exports, reexports)
    }
    match self.parse_type_alias_interface_after_type_keyword() {
      Some(iface) =>
        exports.push({ local_name: iface.name, export_name: iface.name })
      None => ()
    }
    return (stmts, exports, reexports)
  }
  if self.match_(Default) || self.match_ident("default") {
    if self.match_ident("async") && self.check(Function) {
      self.in_async = true
      let func = self.parse_function_expr()
      self.in_async = false
      if func.name != "<anon>" {
        stmts.push(Let(@ast.TsBinding::Ident(func.name), Any, FuncExpr(func)))
        exports.push({ local_name: func.name, export_name: "default" })
      } else {
        let temp = self.next_temp("__export_default__")
        stmts.push(Const(@ast.TsBinding::Ident(temp), Any, FuncExpr(func)))
        exports.push({ local_name: temp, export_name: "default" })
      }
      self.consume_semicolon()
      return (stmts, exports, reexports)
    }
    if self.check(Function) {
      let func = self.parse_function_expr()
      if func.name != "<anon>" {
        stmts.push(Let(@ast.TsBinding::Ident(func.name), Any, FuncExpr(func)))
        exports.push({ local_name: func.name, export_name: "default" })
      } else {
        let temp = self.next_temp("__export_default__")
        stmts.push(Const(@ast.TsBinding::Ident(temp), Any, FuncExpr(func)))
        exports.push({ local_name: temp, export_name: "default" })
      }
      self.consume_semicolon()
      return (stmts, exports, reexports)
    }
    if self.check(Class) {
      let name = match self.peek_at(1).kind {
        Ident(n) => Some(n)
        _ => None
      }
      match name {
        Some(class_name) => {
          let stmt = self.parse_class_decl()
          stmts.push(stmt)
          exports.push({ local_name: class_name, export_name: "default" })
        }
        None => {
          let temp = self.next_temp("__export_default__")
          let expr = self.parse_class_stub()
          stmts.push(Const(@ast.TsBinding::Ident(temp), Any, expr))
          exports.push({ local_name: temp, export_name: "default" })
        }
      }
      self.consume_semicolon()
      return (stmts, exports, reexports)
    }
    let expr = self.parse_expr()
    let local_name = match expr {
      @ast.TsExpr::Var(name) => name
      _ => {
        let temp = self.next_temp("__export_default__")
        let stmt = @ast.TsStmt::Const(
          @ast.TsBinding::Ident(temp),
          @ast.TsType::Any,
          expr,
        )
        collect_static_const_exprs_from_stmt(stmt, const_values)
        stmts.push(stmt)
        temp
      }
    }
    exports.push({ local_name, export_name: "default" })
    self.consume_semicolon()
    return (stmts, exports, reexports)
  }
  if self.match_(Star) {
    if self.match_(As) || self.match_ident("as") {
      let name = self.parse_binding_ident()
      self.expect_from()
      let module_spec = self.expect_str_literal()
      reexports.push({ module_spec, kind: @ast.TsReExportKind::Namespace(name) })
      self.consume_semicolon()
      return (stmts, exports, reexports)
    }
    self.expect_from()
    let module_spec = self.expect_str_literal()
    reexports.push({ module_spec, kind: @ast.TsReExportKind::All })
    self.consume_semicolon()
    return (stmts, exports, reexports)
  }
  if self.match_(LBrace) {
    let items = self.parse_named_exports()
    let _ = self.expect(RBrace)
    if self.match_(From) || self.match_ident("from") {
      let module_spec = self.expect_str_literal()
      reexports.push({ module_spec, kind: @ast.TsReExportKind::Named(items) })
    } else {
      for item in items {
        let (local_name, export_name) = item
        exports.push({ local_name, export_name })
      }
    }
    self.consume_semicolon()
    return (stmts, exports, reexports)
  }
  if self.match_(Import) || self.match_ident("import") {
    let name = self.parse_binding_ident()
    let _ = self.expect(Eq)
    self.skip_until_semicolon()
    exports.push({ local_name: name, export_name: name })
    return (stmts, exports, reexports)
  }
  if self.check(Function) {
    let func = self.parse_function()
    stmts.push(Let(@ast.TsBinding::Ident(func.name), Any, FuncExpr(func)))
    exports.push({ local_name: func.name, export_name: func.name })
    return (stmts, exports, reexports)
  }
  if self.match_ident("abstract") && self.check(Class) {
    let stmt = self.parse_class_decl()
    stmts.push(stmt)
    let names : Array[String] = []
    collect_decl_names_from_stmt(stmt, names)
    for name in names {
      exports.push({ local_name: name, export_name: name })
    }
    return (stmts, exports, reexports)
  }
  match self.peek().kind {
    Ident(name) if name == "async" &&
      self.peek_at(1).kind == Function &&
      !self.has_line_terminator_after() => {
      let _ = self.advance()
      self.in_async = true
      let func = self.parse_function()
      self.in_async = false
      stmts.push(Let(@ast.TsBinding::Ident(func.name), Any, FuncExpr(func)))
      exports.push({ local_name: func.name, export_name: func.name })
      return (stmts, exports, reexports)
    }
    _ => ()
  }
  if self.check(Const) &&
    (match self.peek_at(1).kind {
      Ident(name) => name == "enum"
      _ => false
    }) {
    self.skip_declaration_block()
    return (stmts, exports, reexports)
  }
  if (match self.peek().kind {
      Ident(name) => name == "enum"
      _ => false
    }) {
    self.skip_declaration_block()
    return (stmts, exports, reexports)
  }
  let is_declare = match self.peek().kind {
    Declare => true
    Ident(name) if name == "declare" => true
    _ => false
  }
  if is_declare {
    let _ = self.advance()
    match self.peek().kind {
      Function => {
        let _ = self.advance()
        let import_ = self.parse_declare_function()
        exports.push({ local_name: import_.name, export_name: import_.name })
        return (stmts, exports, reexports)
      }
      Interface => {
        let iface = self.parse_interface()
        exports.push({ local_name: iface.name, export_name: iface.name })
        return (stmts, exports, reexports)
      }
      Type => {
        match self.parse_type_alias_interface() {
          Some(iface) =>
            exports.push({ local_name: iface.name, export_name: iface.name })
          None => ()
        }
        return (stmts, exports, reexports)
      }
      Var | Let | Const => {
        let _ = self.advance()
        let values = self.parse_declare_values()
        for value in values {
          exports.push({ local_name: value.name, export_name: value.name })
        }
        return (stmts, exports, reexports)
      }
      Class => {
        let class_ = self.parse_declare_class(false)
        exports.push({ local_name: class_.name, export_name: class_.name })
        return (stmts, exports, reexports)
      }
      Ident(name) =>
        if name == "abstract" && self.peek_at(1).kind == Class {
          let class_ = self.parse_declare_class_with_optional_abstract()
          exports.push({ local_name: class_.name, export_name: class_.name })
          return (stmts, exports, reexports)
        } else if name == "module" &&
          (match self.peek_at(1).kind {
            Str(_) => true
            _ => false
          }) {
          match self.parse_ambient_external_module_decl() {
            Some(module_) =>
              append_ambient_external_module_exports(module_, exports)
            None => ()
          }
          return (stmts, exports, reexports)
        } else if name == "namespace" ||
          name == "module" ||
          name == "global" ||
          name == "enum" ||
          name == "class" {
          match self.parse_namespace_decl_value() {
            Some(value) =>
              exports.push({ local_name: value.name, export_name: value.name })
            None => self.skip_declaration_block()
          }
          return (stmts, exports, reexports)
        }
      _ => ()
    }
  }
  match self.peek().kind {
    Ident(name) if name == "namespace" ||
      name == "module" ||
      name == "global" ||
      name == "enum" => {
      match self.parse_namespace_decl_value() {
        Some(value) =>
          exports.push({ local_name: value.name, export_name: value.name })
        None => self.skip_declaration_block()
      }
      return (stmts, exports, reexports)
    }
    Ident(name) if name == "abstract" && self.peek_at(1).kind == Class => {
      let class_ = self.parse_declare_class_with_optional_abstract()
      exports.push({ local_name: class_.name, export_name: class_.name })
      return (stmts, exports, reexports)
    }
    _ => ()
  }
  if self.check(Class) {
    let stmt = self.parse_class_decl()
    stmts.push(stmt)
    let names : Array[String] = []
    collect_decl_names_from_stmt(stmt, names)
    for name in names {
      exports.push({ local_name: name, export_name: name })
    }
    return (stmts, exports, reexports)
  }
  if self.check(Let) || self.check(Const) || self.check(Var) {
    if self.is_ambient_export_value_decl() {
      let _ = self.advance()
      let parsed_values = self.parse_declare_values()
      for value in parsed_values {
        exports.push({ local_name: value.name, export_name: value.name })
      }
      return (stmts, exports, reexports)
    }
    let stmt = self.parse_stmt()
    stmts.push(stmt)
    collect_static_const_exprs_from_stmt(stmt, const_values)
    let names : Array[String] = []
    collect_decl_names_from_stmt(stmt, names)
    for name in names {
      exports.push({ local_name: name, export_name: name })
    }
    return (stmts, exports, reexports)
  }
  if self.check(Interface) {
    let iface = self.parse_interface()
    exports.push({ local_name: iface.name, export_name: iface.name })
    return (stmts, exports, reexports)
  }
  raise ParseError("Unsupported export statement")
}

///|
fn Parser::parse_import_stmt(self : Parser) -> Unit raise ParseError {
  let _ = self.expect(Import)
  if self.match_(Type) || self.match_ident("type") {
    // import type ...
  }
  match self.peek().kind {
    Str(_) => {
      let _ = self.advance()
      self.skip_import_attributes()
      self.consume_semicolon()
      return
    }
    _ => ()
  }
  match self.peek().kind {
    Ident(_) if self.peek_at(1).kind == Eq => {
      let local_name = self.parse_binding_ident()
      let _ = self.parse_import_equals_decl(local_name)
      return
    }
    _ => ()
  }
  match self.peek().kind {
    Ident(_) => {
      let _ = self.advance()
      if self.match_(Comma) {
        // continue to namespace/named
      } else {
        self.expect_from()
        let _ = self.expect_str_literal()
        self.skip_import_attributes()
        self.consume_semicolon()
        return
      }
    }
    _ => ()
  }
  if self.match_(Star) {
    if !(self.match_(As) || self.match_ident("as")) {
      raise ParseError("Expected 'as' in import namespace")
    }
    let _ = self.parse_binding_ident()
  } else if self.match_(LBrace) {
    self.parse_import_specifiers()
    let _ = self.expect(RBrace)
  }
  self.expect_from()
  let _ = self.expect_str_literal()
  self.skip_import_attributes()
  self.consume_semicolon()
}

///|
fn Parser::expect_str_literal(self : Parser) -> String raise ParseError {
  match self.advance().kind {
    Str(s) => s
    k => raise ParseError("Expected string literal, got \{k}")
  }
}

///|
fn Parser::is_ambient_export_value_decl(self : Parser) -> Bool {
  match self.peek_at(1).kind {
    Ident(_) => ()
    _ => return false
  }
  let mut i = 2
  let mut paren_depth = 0
  let mut bracket_depth = 0
  let mut brace_depth = 0
  let mut angle_depth = 0
  while i < 256 {
    match self.peek_at(i).kind {
      Eof => return true
      Eq if paren_depth == 0 &&
        bracket_depth == 0 &&
        brace_depth == 0 &&
        angle_depth == 0 => return false
      Semicolon | Comma if paren_depth == 0 &&
        bracket_depth == 0 &&
        brace_depth == 0 &&
        angle_depth == 0 => return true
      Export | Declare | Interface | Type if paren_depth == 0 &&
        bracket_depth == 0 &&
        brace_depth == 0 &&
        angle_depth == 0 => return true
      LParen => paren_depth += 1
      RParen => if paren_depth > 0 { paren_depth -= 1 }
      LBracket => bracket_depth += 1
      RBracket => if bracket_depth > 0 { bracket_depth -= 1 }
      LBrace => brace_depth += 1
      RBrace => if brace_depth > 0 { brace_depth -= 1 }
      Lt => angle_depth += 1
      Gt => if angle_depth > 0 { angle_depth -= 1 }
      GtGt => angle_depth = if angle_depth >= 2 { angle_depth - 2 } else { 0 }
      GtGtGt => angle_depth = if angle_depth >= 3 { angle_depth - 3 } else { 0 }
      _ => ()
    }
    i += 1
  }
  false
}

///|
fn Parser::parse_export_stmt(
  self : Parser,
  funcs : Array[@ast.TsFunc],
  interfaces : Array[@ast.TsInterface],
  type_aliases : Array[@ast.TsTypeAlias],
  imports : Array[@ast.TsImport],
  values : Array[@ast.TsValueDecl],
  classes : Array[@ast.TsClassDecl],
  namespaces : Array[@ast.TsNamespaceDecl],
  const_values : Map[String, @ast.TsExpr],
) -> Unit raise ParseError {
  let _ = self.expect(Export)
  if self.match_(As) || self.match_ident("as") {
    if self.match_ident("namespace") {
      let _ = self.parse_binding_ident()
      self.consume_semicolon()
      return
    }
    raise ParseError("Unsupported export statement")
  }
  if self.match_(Type) || self.match_ident("type") {
    if self.match_(Star) {
      if self.match_(From) || self.match_ident("from") {
        let _ = self.expect_str_literal()
      }
      self.consume_semicolon()
      return
    }
    if self.match_(LBrace) {
      let _ = self.parse_named_exports()
      let _ = self.expect(RBrace)
      if self.match_(From) || self.match_ident("from") {
        let _ = self.expect_str_literal()
      }
      self.consume_semicolon()
      return
    }
    let type_alias = self.parse_type_alias_after_type_keyword()
    type_aliases.push(type_alias)
    match type_alias_to_interface(type_alias) {
      Some(iface) => interfaces.push(iface)
      None => ()
    }
    return
  }
  if self.match_(Eq) {
    let _ = self.parse_expr()
    self.consume_semicolon()
    return
  }
  if self.match_(Default) || self.match_ident("default") {
    if self.match_ident("async") && self.check(Function) {
      self.in_async = true
      let func = self.parse_function_expr()
      self.in_async = false
      if func.name != "<anon>" {
        funcs.push(func)
      }
      return
    }
    if self.check(Function) {
      let func = self.parse_function_expr()
      if func.name != "<anon>" {
        funcs.push(func)
      }
      return
    }
    if self.check(Class) {
      let default_local_name = match self.peek_at(1).kind {
        Ident(name) => Some(name)
        _ => None
      }
      match default_local_name {
        Some(_) => {
          let _ = self.parse_class_decl()
          match self.take_last_runtime_class_decl() {
            Some(class_) => classes.push(class_)
            None => ()
          }
        }
        None => {
          let temp = self.next_temp("__export_default__")
          let _ = self.parse_class_stub()
          match self.take_last_runtime_class_decl() {
            Some(class_) => classes.push({ ..class_, name: temp })
            None => ()
          }
        }
      }
      return
    }
    let _ = self.parse_expr()
    self.consume_semicolon()
    return
  }
  if self.check(Function) {
    funcs.push(self.parse_function())
    return
  }
  match self.peek().kind {
    Ident(name) if name == "async" &&
      self.peek_at(1).kind == Function &&
      !self.has_line_terminator_after() => {
      let _ = self.advance()
      self.in_async = true
      funcs.push(self.parse_function())
      self.in_async = false
      return
    }
    _ => ()
  }
  if self.check(Interface) {
    interfaces.push(self.parse_interface())
    return
  }
  if self.check(Const) &&
    (match self.peek_at(1).kind {
      Ident(name) => name == "enum"
      _ => false
    }) {
    self.skip_declaration_block()
    return
  }
  match self.peek().kind {
    Ident(name) if name == "abstract" && self.peek_at(1).kind == Class => {
      classes.push(self.parse_declare_class_with_optional_abstract())
      return
    }
    _ => ()
  }
  let is_declare = match self.peek().kind {
    Declare => true
    Ident(name) if name == "declare" => true
    _ => false
  }
  if is_declare {
    let _ = self.advance() // consume 'declare'
    match self.peek().kind {
      Function => {
        let _ = self.advance() // consume 'function'
        imports.push(self.parse_declare_function())
      }
      Var | Let | Const => {
        let _ = self.advance()
        let parsed_values = self.parse_declare_values()
        for value in parsed_values {
          values.push(value)
        }
      }
      Interface => interfaces.push(self.parse_interface())
      Class => classes.push(self.parse_declare_class(false))
      Type => {
        let type_alias = self.parse_type_alias()
        type_aliases.push(type_alias)
        match type_alias_to_interface(type_alias) {
          Some(iface) => interfaces.push(iface)
          None => ()
        }
      }
      Ident(name) =>
        if name == "abstract" && self.peek_at(1).kind == Class {
          classes.push(self.parse_declare_class_with_optional_abstract())
        } else if name == "namespace" ||
          name == "module" ||
          name == "global" ||
          name == "enum" ||
          name == "class" {
          match self.parse_namespace_decl_value() {
            Some(value) => values.push(value)
            None => self.skip_declaration_block()
          }
        } else {
          ()
        }
      _ => ()
    }
    return
  }
  if self.match_(Star) {
    if self.match_(As) || self.match_ident("as") {
      let _ = self.parse_binding_ident()
    }
    self.expect_from()
    let _ = self.expect_str_literal()
    self.consume_semicolon()
    return
  }
  if self.match_(LBrace) {
    self.parse_import_specifiers()
    let _ = self.expect(RBrace)
    if self.match_(From) || self.match_ident("from") {
      let _ = self.expect_str_literal()
    }
    self.consume_semicolon()
    return
  }
  if self.match_(Import) || self.match_ident("import") {
    let _ = self.parse_binding_ident()
    let _ = self.expect(Eq)
    self.skip_until_semicolon()
    return
  }
  // export let/const/var/class/function (fallback)
  let is_namespace_like_export = match self.peek().kind {
    Ident(name) =>
      name == "namespace" ||
      name == "module" ||
      name == "global" ||
      name == "enum"
    _ => false
  }
  if is_namespace_like_export {
    match self.parse_namespace_decl() {
      Some((value, namespace_)) => {
        match value {
          Some(value) => values.push(value)
          None => ()
        }
        match namespace_ {
          Some(namespace_) => namespaces.push(namespace_)
          None => ()
        }
      }
      None => self.skip_declaration_block()
    }
    return
  }
  if self.check(Class) {
    let _ = self.parse_class_decl()
    match self.take_last_runtime_class_decl() {
      Some(class_) => classes.push(class_)
      None => ()
    }
    return
  }
  if self.match_ident("abstract") && self.check(Class) {
    let _ = self.parse_class_decl_with_abstract(true)
    match self.take_last_runtime_class_decl() {
      Some(class_) => classes.push(class_)
      None => ()
    }
    return
  }
  if self.check(Let) || self.check(Const) || self.check(Var) {
    if self.is_ambient_export_value_decl() {
      let _ = self.advance()
      let parsed_values = self.parse_declare_values()
      for value in parsed_values {
        values.push(value)
      }
      return
    }
    let stmt = self.parse_stmt()
    collect_static_const_exprs_from_stmt(stmt, const_values)
    collect_value_decls_from_stmt(stmt, values, const_values)
    return
  }
  raise ParseError("Unsupported export statement")
}

///|

///|
fn Parser::parse_module_with_seeded_const_values_internal(
  self : Parser,
  seeded_const_values : Map[String, @ast.TsExpr],
  ambient_decls : Bool,
) -> @ast.TsModule raise ParseError {
  let funcs : Array[@ast.TsFunc] = []
  let interfaces : Array[@ast.TsInterface] = []
  let type_aliases : Array[@ast.TsTypeAlias] = []
  let imports : Array[@ast.TsImport] = []
  let values : Array[@ast.TsValueDecl] = []
  let classes : Array[@ast.TsClassDecl] = []
  let namespaces : Array[@ast.TsNamespaceDecl] = []
  let const_values : Map[String, @ast.TsExpr] = {}
  for entry in seeded_const_values {
    const_values[entry.0] = entry.1
  }
  while !self.check(Eof) {
    if self.check(Function) {
      funcs.push(self.parse_function())
    } else if self.check(Interface) {
      interfaces.push(self.parse_interface())
    } else if (match self.peek().kind {
        Ident(name) => name == "abstract" && self.peek_at(1).kind == Class
        _ => false
      }) {
      let _ = self.advance()
      let _ = self.parse_class_decl_with_abstract(true)
      match self.take_last_runtime_class_decl() {
        Some(class_) => classes.push(class_)
        None => ()
      }
    } else if self.check(Class) {
      if ambient_decls {
        classes.push(self.parse_declare_class(false))
      } else {
        let _ = self.parse_class_decl()
        match self.take_last_runtime_class_decl() {
          Some(class_) => classes.push(class_)
          None => ()
        }
      }
    } else if self.check(Declare) {
      let _ = self.advance() // consume 'declare'
      match self.peek().kind {
        Function => {
          let _ = self.advance() // consume 'function'
          imports.push(self.parse_declare_function())
        }
        Var | Let | Const => {
          let _ = self.advance()
          let parsed_values = self.parse_declare_values()
          for value in parsed_values {
            values.push(value)
          }
        }
        Interface => interfaces.push(self.parse_interface())
        Class => classes.push(self.parse_declare_class(false))
        Type => {
          let type_alias = self.parse_type_alias()
          type_aliases.push(type_alias)
          match type_alias_to_interface(type_alias) {
            Some(iface) => interfaces.push(iface)
            None => ()
          }
        }
        Ident(name) =>
          if name == "abstract" && self.peek_at(1).kind == Class {
            classes.push(self.parse_declare_class_with_optional_abstract())
          } else if name == "module" &&
            (match self.peek_at(1).kind {
              Str(_) => true
              _ => false
            }) {
            match self.parse_ambient_external_module_decl() {
              Some(module_) =>
                append_module_decls(
                  module_, funcs, interfaces, type_aliases, imports, values, classes,
                  namespaces,
                )
              None => ()
            }
          } else if name == "namespace" ||
            name == "module" ||
            name == "global" ||
            name == "enum" ||
            name == "class" {
            match self.parse_namespace_decl() {
              Some((value, namespace_)) => {
                match value {
                  Some(value) => values.push(value)
                  None => ()
                }
                match namespace_ {
                  Some(namespace_) => namespaces.push(namespace_)
                  None => ()
                }
              }
              None => self.skip_declaration_block()
            }
          } else {
            raise ParseError("Unexpected identifier after declare: \{name}")
          }
        k => raise ParseError("Expected Function, got \{k}")
      }
    } else if self.check(Import) {
      self.parse_import_stmt()
    } else if self.check(Export) {
      self.parse_export_stmt(
        funcs, interfaces, type_aliases, imports, values, classes, namespaces, const_values,
      )
    } else if self.check(Type) {
      let type_alias = self.parse_type_alias()
      type_aliases.push(type_alias)
      match type_alias_to_interface(type_alias) {
        Some(iface) => interfaces.push(iface)
        None => ()
      }
    } else if self.is_namespace_decl_start() {
      match self.parse_namespace_decl() {
        Some((value, namespace_)) => {
          match value {
            Some(value) => values.push(value)
            None => ()
          }
          match namespace_ {
            Some(namespace_) => namespaces.push(namespace_)
            None => ()
          }
        }
        None => self.skip_declaration_block()
      }
    } else if (match self.peek().kind {
        Ident(name) => name == "enum"
        _ => false
      }) {
      self.skip_declaration_block()
    } else if self.check(Const) &&
      (match self.peek_at(1).kind {
        Ident(name) => name == "enum"
        _ => false
      }) {
      self.skip_declaration_block()
    } else if self.check(Let) || self.check(Const) || self.check(Var) {
      if ambient_decls {
        let _ = self.advance()
        let parsed_values = self.parse_declare_values()
        for value in parsed_values {
          values.push(value)
        }
      } else if self.check(Const) {
        let stmt = self.parse_stmt()
        collect_static_const_exprs_from_stmt(stmt, const_values)
      } else {
        let _ = self.parse_stmt()
      }
    } else {
      raise ParseError(
        "Expected function, interface, declare, import, or export declaration",
      )
    }
  }
  { funcs, interfaces, type_aliases, imports, values, classes, namespaces }
}

///|
fn Parser::parse_module_with_seeded_const_values(
  self : Parser,
  seeded_const_values : Map[String, @ast.TsExpr],
) -> @ast.TsModule raise ParseError {
  self.parse_module_with_seeded_const_values_internal(
    seeded_const_values, false,
  )
}

///|
// /
pub fn Parser::parse_module(self : Parser) -> @ast.TsModule raise ParseError {
  self.parse_module_with_seeded_const_values({})
}

///|
// / module block (script with import/export)
fn Parser::parse_module_block_with_const_values(
  self : Parser,
  seeded_const_values : Map[String, @ast.TsExpr],
) -> (@ast.TsModuleBlock, Map[String, @ast.TsExpr]) raise ParseError {
  let stmts : Array[@ast.TsStmt] = []
  let imports : Array[@ast.TsImportDecl] = []
  let exports : Array[@ast.TsExportSpec] = []
  let reexports : Array[@ast.TsReExportSpec] = []
  let const_values : Map[String, @ast.TsExpr] = {}
  for entry in seeded_const_values {
    const_values[entry.0] = entry.1
  }
  while !self.check(Eof) {
    while self.check(At) {
      self.skip_decorator()
    }
    if self.check(Import) {
      imports.push(self.parse_import_decl())
      continue
    }
    if self.check(Export) {
      let (block_stmts, export_specs, reexport_specs) = self.parse_export_decl_for_module(
        const_values,
      )
      for stmt in block_stmts {
        stmts.push(stmt)
      }
      for spec in export_specs {
        exports.push(spec)
      }
      for spec in reexport_specs {
        reexports.push(spec)
      }
      continue
    }
    if self.check(Declare) {
      let _ = self.advance()
      match self.peek().kind {
        Function => {
          let _ = self.advance()
          let _ = self.parse_declare_function()
        }
        Var | Let | Const => {
          let _ = self.advance()
          let _ = self.parse_declare_values()
        }
        Interface => {
          let _ = self.parse_interface()
        }
        Class => {
          let _ = self.parse_declare_class(false)
        }
        Type => self.skip_type_alias()
        Ident(name) =>
          if name == "abstract" && self.peek_at(1).kind == Class {
            let _ = self.parse_declare_class_with_optional_abstract()
          } else if name == "module" &&
            (match self.peek_at(1).kind {
              Str(_) => true
              _ => false
            }) {
            match self.parse_ambient_external_module_decl() {
              Some(module_) =>
                append_ambient_external_module_exports(module_, exports)
              None => ()
            }
          } else if name == "namespace" ||
            name == "module" ||
            name == "global" ||
            name == "enum" ||
            name == "class" {
            self.skip_declaration_block()
          } else {
            raise ParseError("Unexpected identifier after declare: \{name}")
          }
        k => raise ParseError("Expected declaration after declare, got \{k}")
      }
      continue
    }
    if self.check(Interface) {
      let _ = self.parse_interface()
      continue
    }
    match self.peek().kind {
      Ident(name) if name == "abstract" && self.peek_at(1).kind == Class => {
        stmts.push(self.parse_stmt())
        continue
      }
      _ => ()
    }
    if self.check(Type) {
      self.skip_type_alias()
      continue
    }
    if self.is_namespace_decl_start() {
      self.skip_declaration_block()
      continue
    }
    if (match self.peek().kind {
        Ident(name) => name == "enum"
        _ => false
      }) {
      self.skip_declaration_block()
      continue
    }
    if self.check(Const) &&
      (match self.peek_at(1).kind {
        Ident(name) => name == "enum"
        _ => false
      }) {
      self.skip_declaration_block()
      continue
    }
    if self.check(Const) {
      let stmt = self.parse_stmt()
      collect_static_const_exprs_from_stmt(stmt, const_values)
      continue
    }
    stmts.push(self.parse_stmt())
  }
  ({ block: { stmts, }, imports, exports, reexports }, const_values)
}

///|
pub fn Parser::parse_module_block(
  self : Parser,
) -> @ast.TsModuleBlock raise ParseError {
  let (module_block, _) = self.parse_module_block_with_const_values({})
  module_block
}

///|
// / eval : expression1 Some(expr)
pub fn parse_expr_from_source(source : String) -> @ast.TsExpr? raise ParseError {
  let parser = Parser::from_source(source)
  let expr = parser.parse_expr()
  if parser.check(Eof) {
    Some(expr)
  } else {
    None
  }
}

///|
// / eval : expression with inherited strict mode
pub fn parse_expr_from_source_strict(
  source : String,
  inherit_strict : Bool,
) -> @ast.TsExpr? raise ParseError {
  let lexer = Lexer::new(source)
  let tokens = lexer.tokenize()
  // Check if source itself declares strict mode
  let trimmed = source.trim_start()
  let source_strict = trimmed.has_prefix("\"use strict\";") ||
    trimmed.has_prefix("'use strict';")
  let parser = Parser::new_with_strict(tokens, inherit_strict || source_strict)
  let expr = parser.parse_expr()
  if parser.check(Eof) {
    Some(expr)
  } else {
    None
  }
}

///|
// / eval : statementblock
pub fn parse_block_from_source(
  source : String,
) -> @ast.TsBlock raise ParseError {
  let parser = Parser::from_source(source)
  let stmts : Array[@ast.TsStmt] = []
  while !parser.check(Eof) {
    stmts.push(parser.parse_stmt())
  }
  { stmts, }
}

///|
// / eval : statementblock with inherited strict mode
pub fn parse_block_from_source_strict(
  source : String,
  inherit_strict : Bool,
) -> @ast.TsBlock raise ParseError {
  let lexer = Lexer::new(source)
  let tokens = lexer.tokenize()
  // Check if source itself declares strict mode
  let trimmed = source.trim_start()
  let source_strict = trimmed.has_prefix("\"use strict\";") ||
    trimmed.has_prefix("'use strict';")
  let parser = Parser::new_with_strict(tokens, inherit_strict || source_strict)
  let stmts : Array[@ast.TsStmt] = []
  while !parser.check(Eof) {
    stmts.push(parser.parse_stmt())
  }
  { stmts, }
}

///|
// / module block from source
pub fn parse_module_block_from_source(
  source : String,
) -> @ast.TsModuleBlock raise ParseError {
  let parser = Parser::from_source(source)
  parser.parse_module_block()
}

///|
pub fn parse_module_from_source_with_const_values(
  source : String,
  seeded_const_values : Map[String, @ast.TsExpr],
) -> @ast.TsModule raise ParseError {
  let parser = Parser::from_source(source)
  parser.parse_module_with_seeded_const_values(seeded_const_values)
}

///|
pub fn collect_exported_const_values_from_source(
  source : String,
  seeded_const_values : Map[String, @ast.TsExpr],
) -> Map[String, @ast.TsExpr] raise ParseError {
  let parser = Parser::from_source(source)
  let (module_block, const_values) = parser.parse_module_block_with_const_values(
    seeded_const_values,
  )
  let exported_const_values : Map[String, @ast.TsExpr] = {}
  for export_ in module_block.exports {
    match const_values.get(export_.local_name) {
      Some(expr) => exported_const_values[export_.export_name] = expr
      None => ()
    }
  }
  exported_const_values
}
