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
) -> (Array[@ast.TsStmt], Array[@ast.TsExportSpec], Array[@ast.TsReExportSpec]) raise ParseError {
  let stmts : Array[@ast.TsStmt] = []
  let exports : Array[@ast.TsExportSpec] = []
  let reexports : Array[@ast.TsReExportSpec] = []
  let _ = self.expect(Export)
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
    let temp = self.next_temp("__export_default__")
    let expr = self.parse_expr()
    stmts.push(Const(@ast.TsBinding::Ident(temp), Any, expr))
    exports.push({ local_name: temp, export_name: "default" })
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
  if self.check(Type) {
    self.skip_type_alias()
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
        self.skip_type_alias()
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
        } else if name == "namespace" ||
          name == "module" ||
          name == "global" ||
          name == "enum" ||
          name == "class" {
          self.skip_declaration_block()
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
      self.skip_declaration_block()
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
  imports : Array[@ast.TsImport],
  values : Array[@ast.TsValueDecl],
  classes : Array[@ast.TsClassDecl],
) -> Unit raise ParseError {
  let _ = self.expect(Export)
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
  if self.check(Type) {
    self.skip_type_alias()
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
      Type => self.skip_type_alias()
      Ident(name) =>
        if name == "abstract" && self.peek_at(1).kind == Class {
          classes.push(self.parse_declare_class_with_optional_abstract())
        } else if name == "namespace" ||
          name == "module" ||
          name == "global" ||
          name == "enum" ||
          name == "class" {
          self.skip_declaration_block()
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
    self.skip_declaration_block()
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
    let _ = self.parse_stmt()
    return
  }
  raise ParseError("Unsupported export statement")
}

///|

///|
// /
pub fn Parser::parse_module(self : Parser) -> @ast.TsModule raise ParseError {
  let funcs : Array[@ast.TsFunc] = []
  let interfaces : Array[@ast.TsInterface] = []
  let imports : Array[@ast.TsImport] = []
  let values : Array[@ast.TsValueDecl] = []
  let classes : Array[@ast.TsClassDecl] = []
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
      let _ = self.parse_class_decl()
      match self.take_last_runtime_class_decl() {
        Some(class_) => classes.push(class_)
        None => ()
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
        Type =>
          // Skip type alias: consume until semicolon or end of type
          self.skip_type_alias()
        Ident(name) =>
          if name == "abstract" && self.peek_at(1).kind == Class {
            classes.push(self.parse_declare_class_with_optional_abstract())
          } else if name == "namespace" ||
            name == "module" ||
            name == "global" ||
            name == "enum" ||
            name == "class" {
            // Skip namespace/module/global/enum/class declaration
            self.skip_declaration_block()
          } else {
            raise ParseError("Unexpected identifier after declare: \{name}")
          }
        k => raise ParseError("Expected Function, got \{k}")
      }
    } else if self.check(Import) {
      self.parse_import_stmt()
    } else if self.check(Export) {
      self.parse_export_stmt(funcs, interfaces, imports, values, classes)
    } else if self.check(Type) {
      // Skip type alias at top level
      self.skip_type_alias()
    } else if self.is_namespace_decl_start() {
      self.skip_declaration_block()
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
    } else if self.check(Const) {
      // Skip const declarations at top level (e.g., const enum)
      self.skip_until_semicolon()
    } else {
      raise ParseError(
        "Expected function, interface, declare, import, or export declaration",
      )
    }
  }
  { funcs, interfaces, imports, values, classes }
}

///|
// / module block (script with import/export)
pub fn Parser::parse_module_block(
  self : Parser,
) -> @ast.TsModuleBlock raise ParseError {
  let stmts : Array[@ast.TsStmt] = []
  let imports : Array[@ast.TsImportDecl] = []
  let exports : Array[@ast.TsExportSpec] = []
  let reexports : Array[@ast.TsReExportSpec] = []
  while !self.check(Eof) {
    while self.check(At) {
      self.skip_decorator()
    }
    if self.check(Import) {
      imports.push(self.parse_import_decl())
      continue
    }
    if self.check(Export) {
      let (block_stmts, export_specs, reexport_specs) = self.parse_export_decl_for_module()
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
      self.skip_until_semicolon()
      continue
    }
    stmts.push(self.parse_stmt())
  }
  { block: { stmts, }, imports, exports, reexports }
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
