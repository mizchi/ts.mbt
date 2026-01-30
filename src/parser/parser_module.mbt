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
fn Parser::parse_import_specifiers(self : Parser) -> Unit raise ParseError {
  while not(self.check(RBrace)) {
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
fn Parser::parse_named_imports(self : Parser) -> Array[(String, String)] raise ParseError {
  let items : Array[(String, String)] = []
  while not(self.check(RBrace)) {
    let imported = self.parse_binding_ident()
    let local_name =
      if self.match_(As) || self.match_ident("as") {
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
fn Parser::parse_named_exports(self : Parser) -> Array[(String, String)] raise ParseError {
  let items : Array[(String, String)] = []
  while not(self.check(RBrace)) {
    let local_name = self.parse_binding_ident()
    let export_name =
      if self.match_(As) || self.match_ident("as") {
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
fn collect_decl_names_from_stmt(stmt : @ast.TsStmt, names : Array[String]) -> Unit {
  match stmt {
    Let(binding, _, _) | Const(binding, _, _) =>
      match binding {
        @ast.TsBinding::Ident(name) => names.push(name)
        _ => ()
      }
    Block(block) =>
      for inner in block.stmts {
        collect_decl_names_from_stmt(inner, names)
      }
    _ => ()
  }
}

///|
fn Parser::parse_import_decl(self : Parser) -> @ast.TsImportDecl raise ParseError {
  let _ = self.expect(Import)
  let mut type_only = false
  if self.match_(Type) || self.match_ident("type") {
    type_only = true
  }
  match self.peek().kind {
    Str(_) => {
      let module_spec = self.expect_str_literal()
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
  if not(self.check(Star)) && not(self.check(LBrace)) {
    default_binding = Some(self.parse_binding_ident())
    if self.match_(Comma) {
      // continue to namespace/named
    } else {
      self.expect_from()
      let module_spec = self.expect_str_literal()
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
    if not(self.match_(As) || self.match_ident("as")) {
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
fn Parser::parse_export_decl_for_module(
  self : Parser,
) -> (Array[@ast.TsStmt], Array[@ast.TsExportSpec], Array[@ast.TsReExportSpec]) raise ParseError {
  let stmts : Array[@ast.TsStmt] = []
  let exports : Array[@ast.TsExportSpec] = []
  let reexports : Array[@ast.TsReExportSpec] = []
  let _ = self.expect(Export)
  if self.match_(Default) || self.match_ident("default") {
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
      reexports.push({
        module_spec,
        kind: @ast.TsReExportKind::Namespace(name),
      })
      self.consume_semicolon()
      return (stmts, exports, reexports)
    }
    self.expect_from()
    let module_spec = self.expect_str_literal()
    reexports.push({
      module_spec,
      kind: @ast.TsReExportKind::All,
    })
    self.consume_semicolon()
    return (stmts, exports, reexports)
  }
  if self.match_(LBrace) {
    let items = self.parse_named_exports()
    let _ = self.expect(RBrace)
    if self.match_(From) || self.match_ident("from") {
      let module_spec = self.expect_str_literal()
      reexports.push({
        module_spec,
        kind: @ast.TsReExportKind::Named(items),
      })
    } else {
      for item in items {
        let (local_name, export_name) = item
        exports.push({ local_name, export_name })
      }
    }
    self.consume_semicolon()
    return (stmts, exports, reexports)
  }
  if self.check(Function) {
    let func = self.parse_function()
    stmts.push(Let(@ast.TsBinding::Ident(func.name), Any, FuncExpr(func)))
    exports.push({ local_name: func.name, export_name: func.name })
    return (stmts, exports, reexports)
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
    let _ = self.parse_interface()
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
        self.consume_semicolon()
        return
      }
    }
    _ => ()
  }
  if self.match_(Star) {
    if not(self.match_(As) || self.match_ident("as")) {
      raise ParseError("Expected 'as' in import namespace")
    }
    let _ = self.parse_binding_ident()
  } else if self.match_(LBrace) {
    self.parse_import_specifiers()
    let _ = self.expect(RBrace)
  }
  self.expect_from()
  let _ = self.expect_str_literal()
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
fn Parser::parse_export_stmt(
  self : Parser,
  funcs : Array[@ast.TsFunc],
  interfaces : Array[@ast.TsInterface],
  imports : Array[@ast.TsImport],
) -> Unit raise ParseError {
  let _ = self.expect(Export)
  if self.match_(Default) || self.match_ident("default") {
    if self.check(Function) {
      let func = self.parse_function_expr()
      if func.name != "<anon>" {
        funcs.push(func)
      }
      return
    }
    if self.check(Class) {
      let _ = self.parse_class_decl()
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
  if self.check(Interface) {
    interfaces.push(self.parse_interface())
    return
  }
  if self.check(Declare) {
    let _ = self.advance() // consume 'declare'
    match self.peek().kind {
      Function => {
        let _ = self.advance() // consume 'function'
        imports.push(self.parse_declare_function())
      }
      Var | Let | Const => {
        self.skip_until_semicolon()
      }
      Interface => {
        interfaces.push(self.parse_interface())
      }
      Type => {
        self.skip_type_alias()
      }
      Ident(name) => {
        if name == "namespace" || name == "module" || name == "global" || name == "abstract" || name == "enum" || name == "class" {
          self.skip_declaration_block()
        } else {
          ()
        }
      }
      Class => {
        self.skip_declaration_block()
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
  // export let/const/var/class/function (fallback)
  if self.check(Class) {
    let _ = self.parse_class_decl()
    return
  }
  if self.check(Let) || self.check(Const) || self.check(Var) {
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
  while not(self.check(Eof)) {
    if self.check(Function) {
      funcs.push(self.parse_function())
    } else if self.check(Interface) {
      interfaces.push(self.parse_interface())
    } else if self.check(Declare) {
      let _ = self.advance() // consume 'declare'
      match self.peek().kind {
        Function => {
          let _ = self.advance() // consume 'function'
          imports.push(self.parse_declare_function())
        }
        Var | Let | Const => {
          // Skip declare var/let/const: just consume until semicolon
          self.skip_until_semicolon()
        }
        Interface => {
          interfaces.push(self.parse_interface())
        }
        Type => {
          // Skip type alias: consume until semicolon or end of type
          self.skip_type_alias()
        }
        Ident(name) => {
          if name == "namespace" || name == "module" || name == "global" || name == "abstract" || name == "enum" || name == "class" {
            // Skip namespace/module/global/abstract/enum/class declaration
            self.skip_declaration_block()
          } else {
            raise ParseError("Unexpected identifier after declare: \{name}")
          }
        }
        Class => {
          // Skip declare class
          self.skip_declaration_block()
        }
        k => raise ParseError("Expected Function, got \{k}")
      }
    } else if self.check(Import) {
      self.parse_import_stmt()
    } else if self.check(Export) {
      self.parse_export_stmt(funcs, interfaces, imports)
    } else if self.check(Type) {
      // Skip type alias at top level
      self.skip_type_alias()
    } else if self.check(Const) {
      // Skip const declarations at top level (e.g., const enum)
      self.skip_until_semicolon()
    } else {
      raise ParseError("Expected function, interface, declare, import, or export declaration")
    }
  }
  { funcs, interfaces, imports }
}

///|
// / module block (script with import/export)
pub fn Parser::parse_module_block(self : Parser) -> @ast.TsModuleBlock raise ParseError {
  let stmts : Array[@ast.TsStmt] = []
  let imports : Array[@ast.TsImportDecl] = []
  let exports : Array[@ast.TsExportSpec] = []
  let reexports : Array[@ast.TsReExportSpec] = []
  while not(self.check(Eof)) {
    if self.check(Import) {
      imports.push(self.parse_import_decl())
      continue
    }
    if self.check(Export) {
      let (block_stmts, export_specs, reexport_specs) =
        self.parse_export_decl_for_module()
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
pub fn parse_expr_from_source_strict(source : String, inherit_strict : Bool) -> @ast.TsExpr? raise ParseError {
  let lexer = Lexer::new(source)
  let tokens = lexer.tokenize()
  // Check if source itself declares strict mode
  let trimmed = source.trim_start()
  let source_strict = trimmed.has_prefix("\"use strict\";") || trimmed.has_prefix("'use strict';")
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
pub fn parse_block_from_source(source : String) -> @ast.TsBlock raise ParseError {
  let parser = Parser::from_source(source)
  let stmts : Array[@ast.TsStmt] = []
  while not(parser.check(Eof)) {
    stmts.push(parser.parse_stmt())
  }
  { stmts, }
}

///|
// / eval : statementblock with inherited strict mode
pub fn parse_block_from_source_strict(source : String, inherit_strict : Bool) -> @ast.TsBlock raise ParseError {
  let lexer = Lexer::new(source)
  let tokens = lexer.tokenize()
  // Check if source itself declares strict mode
  let trimmed = source.trim_start()
  let source_strict = trimmed.has_prefix("\"use strict\";") || trimmed.has_prefix("'use strict';")
  let parser = Parser::new_with_strict(tokens, inherit_strict || source_strict)
  let stmts : Array[@ast.TsStmt] = []
  while not(parser.check(Eof)) {
    stmts.push(parser.parse_stmt())
  }
  { stmts, }
}

///|
// / module block from source
pub fn parse_module_block_from_source(source : String) -> @ast.TsModuleBlock raise ParseError {
  let parser = Parser::from_source(source)
  parser.parse_module_block()
}
