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
    let imported = self.parse_binding_ident()
    if self.match_(As) || self.match_ident("as") {
      let local = self.parse_binding_ident()
      self.imported_binding_names.push(local)
    } else {
      self.imported_binding_names.push(imported)
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
/// Same as `parse_named_imports`, but additionally reports whether each
/// specifier was prefixed with `type` (`import { type X, Y }`). The two
/// arrays are aligned positionally.
fn Parser::parse_named_imports_with_type_flags(
  self : Parser,
) -> (Array[(String, String)], Array[Bool]) raise ParseError {
  let items : Array[(String, String)] = []
  let type_flags : Array[Bool] = []
  while !self.check(RBrace) {
    let is_type = self.maybe_match_type_modifier()
    let imported = self.parse_binding_ident()
    let local_name = if self.match_(As) || self.match_ident("as") {
      self.parse_binding_ident()
    } else {
      imported
    }
    items.push((imported, local_name))
    type_flags.push(is_type)
    if self.match_(Comma) {
      if self.check(RBrace) {
        break
      }
      continue
    }
    break
  }
  (items, type_flags)
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
    enums: [],
    module_augmentations: [],
    strict_property_initialization: true,
    strict_null_checks: true,
    use_define_for_class_fields: false,
    top_level_stmts: [],
    deprecated_compiler_options: [],
    parameter_property_misuses: [],
    strict_mode_misuses: [],
    invalid_decorator_uses: [],
    grammar_misuses: [],
    imported_binding_names: [],
    import_module_specs: [],
    class_base_type_args: [],
    param_optional_initializer_misuses: [],
    interface_member_modifier_misuses: [],
    class_dup_diagnostics: [],
  }
}

///|
fn Parser::is_enum_keyword_at(self : Parser, offset : Int) -> Bool {
  match self.peek_at(offset).kind {
    Ident(name) => name == "enum"
    _ => false
  }
}

///|
fn Parser::is_const_enum_decl_start(self : Parser) -> Bool {
  self.check(Const) && self.is_enum_keyword_at(1)
}

///|
fn Parser::is_enum_member_initializer_delim(self : Parser) -> Bool {
  self.check(Comma) ||
  self.check(Semicolon) ||
  self.check(RBrace) ||
  self.check(Eof)
}

///|
fn Parser::skip_enum_member_initializer_tail(self : Parser) -> Unit {
  let mut paren_depth = 0
  let mut bracket_depth = 0
  let mut brace_depth = 0
  while !self.check(Eof) {
    match self.peek().kind {
      Comma | Semicolon if paren_depth == 0 &&
        bracket_depth == 0 &&
        brace_depth == 0 => return
      RBrace if paren_depth == 0 && bracket_depth == 0 && brace_depth == 0 =>
        return
      LParen => {
        paren_depth += 1
        let _ = self.advance()
      }
      RParen =>
        if paren_depth > 0 {
          paren_depth -= 1
          let _ = self.advance()
        } else {
          return
        }
      LBracket => {
        bracket_depth += 1
        let _ = self.advance()
      }
      RBracket =>
        if bracket_depth > 0 {
          bracket_depth -= 1
          let _ = self.advance()
        } else {
          return
        }
      LBrace => {
        brace_depth += 1
        let _ = self.advance()
      }
      RBrace =>
        if brace_depth > 0 {
          brace_depth -= 1
          let _ = self.advance()
        } else {
          return
        }
      _ => {
        let _ = self.advance()
      }
    }
  }
}

///|
fn Parser::parse_enum_member_initializer(
  self : Parser,
) -> (@ast.TsEnumMemberValue?, Bool) {
  let sign = if self.match_(Minus) {
    "-"
  } else if self.match_(Plus) {
    ""
  } else {
    ""
  }
  let value = match self.peek().kind {
    Str(value) if sign == "" => {
      let _ = self.advance()
      Some(@ast.TsEnumMemberValue::String(value))
    }
    Int(value) => {
      let _ = self.advance()
      Some(@ast.TsEnumMemberValue::Number(sign + value.to_string()))
    }
    Number(value) => {
      let _ = self.advance()
      Some(@ast.TsEnumMemberValue::Number(sign + value.to_string()))
    }
    BigInt(value) => {
      let _ = self.advance()
      Some(@ast.TsEnumMemberValue::BigInt(sign + value))
    }
    Bool(value) if sign == "" => {
      let _ = self.advance()
      Some(@ast.TsEnumMemberValue::Bool(value))
    }
    _ => {
      self.skip_enum_member_initializer_tail()
      return (None, true)
    }
  }
  if self.is_enum_member_initializer_delim() {
    (value, false)
  } else {
    self.skip_enum_member_initializer_tail()
    (None, true)
  }
}

///|
fn Parser::parse_enum_member_name(self : Parser) -> String raise ParseError {
  match self.peek().kind {
    Str(name) => {
      let _ = self.advance()
      name
    }
    _ => self.parse_binding_ident()
  }
}

///|
fn Parser::parse_enum_decl_after_enum_keyword(
  self : Parser,
  is_const : Bool,
  is_declare : Bool,
) -> @ast.TsEnumDecl raise ParseError {
  if !self.match_ident("enum") {
    raise ParseError("Expected enum declaration")
  }
  let name = self.parse_binding_ident()
  // TS1359: an enum name is a binding name (`enum void {}` is never legal).
  self.record_reserved_binding_name(name)
  let _ = self.expect(LBrace)
  let members : Array[@ast.TsEnumMember] = []
  while !self.check(RBrace) && !self.check(Eof) {
    if self.match_(Comma) || self.match_(Semicolon) {
      continue
    }
    let member_name = self.parse_enum_member_name()
    let (value, is_computed) = if self.match_(Eq) {
      self.parse_enum_member_initializer()
    } else {
      (None, false)
    }
    members.push({ name: member_name, value, is_computed })
    if self.match_(Comma) || self.match_(Semicolon) {
      continue
    }
  }
  let _ = self.expect(RBrace)
  self.consume_semicolon()
  { name, members, is_const, is_declare }
}

///|

///|
/// Lower a parsed `enum` declaration to the equivalent runtime
/// statements:
///   `var Name = {}; Name["A"] = 0; Name[0] = "A"; …`
/// Reverse mapping (`Name[value] = "Name"`) is emitted only for
/// numeric members so string enums don't accidentally collide on
/// the value side. `declare enum` produces no runtime code.
pub fn lower_enum_decl_to_runtime_stmts(
  decl : @ast.TsEnumDecl,
) -> Array[@ast.TsStmt] {
  let out : Array[@ast.TsStmt] = []
  if decl.is_declare {
    return out
  }
  // `const enum` decls don't generate any runtime object —
  // their use sites are inlined to literal values by
  // `transform/const_enum_inline.mbt`. Emitting the var would
  // both bloat the bundle and break the TS-spec contract that
  // const enums vanish at runtime.
  if decl.is_const {
    return out
  }
  out.push(
    Var(@ast.TsBinding::Ident(decl.name), @ast.TsType::Any, ObjectLit([])),
  )
  let mut next_numeric : Int = 0
  for mem in decl.members {
    let value_expr : @ast.TsExpr? = match mem.value {
      Some(@ast.TsEnumMemberValue::Number(s)) =>
        try @string.parse_int(s) catch {
          _ =>
            // Float / hex / negative / etc — fall back to `0.0`
            // for auto-increment (rare in practice).
            Some(
              @ast.TsExpr::NumberLit(
                try @string.parse_double(s) catch {
                  _ => 0.0
                } noraise {
                  d => d
                },
              ),
            )
        } noraise {
          i => {
            next_numeric = i + 1
            Some(@ast.TsExpr::IntLit(i))
          }
        }
      Some(@ast.TsEnumMemberValue::String(s)) => Some(@ast.TsExpr::StringLit(s))
      Some(@ast.TsEnumMemberValue::BigInt(s)) => Some(@ast.TsExpr::BigIntLit(s))
      Some(@ast.TsEnumMemberValue::Bool(b)) => Some(@ast.TsExpr::BoolLit(b))
      None => {
        let v = next_numeric
        next_numeric = next_numeric + 1
        Some(@ast.TsExpr::IntLit(v))
      }
    }
    match value_expr {
      Some(v) => {
        out.push(
          IndexAssign(
            @ast.TsExpr::Var(decl.name),
            @ast.TsExpr::StringLit(mem.name),
            v,
          ),
        )
        // Reverse map only for numeric values.
        match v {
          IntLit(_) | NumberLit(_) | BigIntLit(_) =>
            out.push(
              IndexAssign(
                @ast.TsExpr::Var(decl.name),
                v,
                @ast.TsExpr::StringLit(mem.name),
              ),
            )
          _ => ()
        }
      }
      None => ()
    }
  }
  out
}

///|
fn Parser::parse_const_enum_decl(
  self : Parser,
  is_declare : Bool,
) -> @ast.TsEnumDecl raise ParseError {
  let _ = self.expect(Const)
  self.parse_enum_decl_after_enum_keyword(true, is_declare)
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
    self.src[brace_start_pos + 1:body_end_pos].to_owned()
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
  match self.parse_ambient_external_module_decl_with_spec() {
    Some((_, m)) => Some(m)
    None => None
  }
}

///|
/// Same as `parse_ambient_external_module_decl` but also returns the
/// declared module specifier string. Used by the top-level parse loop
/// to record `(spec, body)` augmentation entries on the surrounding
/// `TsModule`.
fn Parser::parse_ambient_external_module_decl_with_spec(
  self : Parser,
) -> (String, @ast.TsModule)? raise ParseError {
  if !self.match_ident("module") {
    return None
  }
  match self.peek().kind {
    Str(_) => {
      let spec = self.expect_str_literal()
      if self.check(LBrace) {
        let body_source = self.parse_declaration_block_source()
        Some((spec, parse_ambient_external_module_source(body_source)))
      } else {
        self.skip_declaration_block()
        Some((spec, empty_ts_module()))
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
  enums : Array[@ast.TsEnumDecl],
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
  for enum_ in module_.enums {
    enums.push(enum_)
  }
}

///|
/// Recursively collect every `enum` / `const enum` declaration reachable
/// through a module's nested namespaces into `out`. Used by the module-block
/// parser, which can only retain a flat `enums` list (`TsModuleBlock` has no
/// `namespaces` field) but must not silently drop enums declared inside a
/// `namespace N { ... }` / `declare namespace N { ... }` body — the bridge
/// const-table pass and downstream type resolution read `block.enums`.
fn collect_enums_recursive(
  module_ : @ast.TsModule,
  out : Array[@ast.TsEnumDecl],
) -> Unit {
  for enum_ in module_.enums {
    out.push(enum_)
  }
  for ns in module_.namespaces {
    collect_enums_recursive(ns.module_, out)
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
  for enum_ in module_.enums {
    exports.push({ local_name: enum_.name, export_name: enum_.name })
  }
}

///|
fn Parser::parse_namespace_decl(
  self : Parser,
) -> (@ast.TsValueDecl?, @ast.TsNamespaceDecl?)? raise ParseError {
  // Historical default: treat the body as ambient. Used by all
  // declare-context callers (`declare namespace X { ... }` inside `.d.ts`
  // files) so bodyless declarations like `const foo: T;` parse correctly.
  self.parse_namespace_decl_with_mode(true)
}

///|
fn Parser::parse_namespace_decl_runtime(
  self : Parser,
) -> (@ast.TsValueDecl?, @ast.TsNamespaceDecl?)? raise ParseError {
  // Parse the namespace body as runtime (non-ambient) code. Used by
  // `namespace X { ... }` / `export namespace X { ... }` at module scope
  // in real `.ts` source files, whose bodies may contain runtime class
  // method bodies, expression statements, and so on. Falls back to ambient
  // parsing if the runtime grammar rejects the body (e.g. for a namespace
  // whose members are all declare-style signatures).
  self.parse_namespace_decl_with_mode(false)
}

///|
fn Parser::parse_namespace_decl_with_mode(
  self : Parser,
  body_is_ambient : Bool,
) -> (@ast.TsValueDecl?, @ast.TsNamespaceDecl?)? raise ParseError {
  let keyword = match self.peek().kind {
    Ident(name) if name == "namespace" || name == "module" || name == "global" =>
      name
    _ => return None
  }
  let _ = self.advance()
  if keyword == "global" {
    // `declare global { ... }` — ambient global augmentation. Parse the
    // block as a mini-module and expose declarations as a synthetic
    // namespace so downstream resolvers can see augmented globals.
    if self.check(LBrace) {
      let body_source = self.parse_declaration_block_source()
      let augmented = parse_ambient_external_module_source(body_source)
      let ns : @ast.TsNamespaceDecl = { name: "<global>", module_: augmented }
      return Some((None, Some(ns)))
    } else {
      // bare `global` without a block — just skip to semicolon
      self.skip_until_semicolon()
      return Some((None, None))
    }
  }
  // TS1443: a module declaration name must be an identifier or a
  // single/double-quoted string -- template literals are rejected
  // (`declare module \`M1\` {}`).
  if keyword == "module" && self.peek().kind is Template(_, _, _) {
    self.grammar_misuses.push(
      "module declaration names may only use ' or \" quoted strings",
    )
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
      // A hard-reserved word as a dotted path segment
      // (`declare namespace chrome.debugger {}`) is never legal --
      // tsc reports TS1005/TS2304 recovery errors here.
      match self.peek().kind {
        Debugger
        | While
        | If
        | Else
        | For
        | Do
        | Switch
        | Case
        | Return
        | Break
        | Continue
        | Function
        | Class
        | Var
        | Const
        | New
        | Delete
        | Typeof
        | Instanceof
        | In
        | Import
        | Export
        | Extends
        | Try
        | Catch
        | Finally
        | Throw
        | With
        | Default =>
          self.grammar_misuses.push(
            "a reserved word cannot be used as a namespace path segment",
          )
        _ => ()
      }
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
      } else if body_is_ambient {
        // Inherit JSX permission from the outer parser so `<T>expr`
        // type assertions inside a `.ts` (non-JSX) source don't get
        // misread as JSX element starts.
        let parser = Parser::from_source_with_jsx(body_source, self.allow_jsx)
        parser.parse_module_with_seeded_const_values_internal({}, true)
      } else {
        // Runtime first, ambient fallback. This lets us parse runtime
        // namespaces in `.ts` files (with class method bodies) without
        // breaking .d.ts files that route through here via `parse_export`
        // helpers.
        let runtime_parser = Parser::from_source_with_jsx(
          body_source,
          self.allow_jsx,
        )
        try
          runtime_parser.parse_module_with_seeded_const_values_internal(
            {},
            false,
          )
        catch {
          _ => {
            let ambient_parser = Parser::from_source_with_jsx(
              body_source,
              self.allow_jsx,
            )
            ambient_parser.parse_module_with_seeded_const_values_internal(
              {},
              true,
            )
          }
        } noraise {
          module_ => module_
        }
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
fn Parser::parse_namespace_decl_value_runtime(
  self : Parser,
) -> @ast.TsValueDecl? raise ParseError {
  match self.parse_namespace_decl_runtime() {
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
    if !self.multi_file_source {
      self.import_module_specs.push(spec)
    }
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
    named_type_only: [],
    side_effect_only: false,
    type_only: false,
    attributes: [],
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
    // `class X extends Y { … }` produced as a native class
    // declaration. The export tracker needs to see `X` so
    // `export class App extends LitElement {}` registers the
    // export.
    NativeClassStmt(decl, _) => if decl.name != "" { names.push(decl.name) }
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
    @ast.TsExpr::ArrowFunc(params, _declared_ret, body, is_async) =>
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
      let attributes = self.parse_import_attributes()
      self.consume_semicolon()
      return {
        module_spec,
        default_binding: None,
        namespace_binding: None,
        named_bindings: [],
        named_type_only: [],
        side_effect_only: true,
        type_only,
        attributes,
      }
    }
    _ => ()
  }
  let mut default_binding : String? = None
  let mut namespace_binding : String? = None
  let named_bindings : Array[(String, String)] = []
  let named_type_only : Array[Bool] = []
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
      let attributes = self.parse_import_attributes()
      self.consume_semicolon()
      return {
        module_spec,
        default_binding,
        namespace_binding: None,
        named_bindings,
        named_type_only,
        side_effect_only: false,
        type_only,
        attributes,
      }
    }
  }
  if self.match_(Star) {
    if !(self.match_(As) || self.match_ident("as")) {
      raise ParseError("Expected 'as' in import namespace")
    }
    namespace_binding = Some(self.parse_binding_ident())
  } else if self.match_(LBrace) {
    let (items, type_flags) = self.parse_named_imports_with_type_flags()
    for item in items {
      named_bindings.push(item)
    }
    for f in type_flags {
      named_type_only.push(f)
    }
    let _ = self.expect(RBrace)
  }
  self.expect_from()
  let module_spec = self.expect_str_literal()
  let attributes = self.parse_import_attributes()
  self.consume_semicolon()
  {
    module_spec,
    default_binding,
    namespace_binding,
    named_bindings,
    named_type_only,
    side_effect_only: false,
    type_only,
    attributes,
  }
}

///|
fn Parser::skip_import_attributes(self : Parser) -> Unit {
  let _ = self.parse_import_attributes()
}

///|
/// Parse `with { key: "value", ... }` (or the legacy `assert { ... }`)
/// attribute object on an import declaration. Returns each
/// `(key, string_value)` pair in source order. Non-string values are
/// silently dropped — the spec only defines string-valued attributes
/// today.
fn Parser::parse_import_attributes(self : Parser) -> Array[(String, String)] {
  let out : Array[(String, String)] = []
  if !(self.match_(With) || self.match_ident("assert")) {
    return out
  }
  if !self.check(LBrace) {
    return out
  }
  let _ = self.advance() // consume `{`
  let mut depth = 1
  while depth > 0 && !self.check(Eof) {
    // Key: identifier or string literal.
    let key_opt : String? = match self.peek().kind {
      Ident(name) => {
        let _ = self.advance()
        Some(name)
      }
      // `type` is a reserved keyword that's still valid as an import
      // attribute key (e.g. `with { type: "json" }`).
      Type => {
        let _ = self.advance()
        Some("type")
      }
      Str(s) => {
        let _ = self.advance()
        Some(s)
      }
      RBrace => {
        let _ = self.advance()
        depth -= 1
        continue
      }
      _ => {
        let _ = self.advance()
        None
      }
    }
    match key_opt {
      Some(key) =>
        if self.match_(Colon) {
          match self.peek().kind {
            Str(value) => {
              let _ = self.advance()
              out.push((key, value))
            }
            _ => {
              // unknown value shape — skip token
              let _ = self.advance()
            }
          }
        }
      None => ()
    }
    if !self.match_(Comma) {
      // Expect closing `}` next (or another key if no comma).
      match self.peek().kind {
        RBrace => {
          let _ = self.advance()
          depth -= 1
        }
        _ => ()
      }
    }
  }
  out
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
    // TS2304: `export = name` references the value namespace; record the
    // bare-identifier shape so the checker can flag a provably undeclared
    // name (resolution folds in module-block / namespace declarations).
    match expr {
      @ast.TsExpr::Var(name) if !self.in_function =>
        self.grammar_misuses.push("<export-eq>" + name)
      _ => ()
    }
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
      if self.match_(As) || self.match_ident("as") {
        let name = self.parse_binding_ident()
        self.expect_from()
        let module_spec = self.expect_str_literal()
        reexports.push({
          module_spec,
          kind: @ast.TsReExportKind::Namespace(name),
          type_only: true,
        })
      } else if self.match_(From) || self.match_ident("from") {
        let module_spec = self.expect_str_literal()
        reexports.push({
          module_spec,
          kind: @ast.TsReExportKind::All,
          type_only: true,
        })
      }
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
          type_only: true,
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
    let type_alias = self.parse_type_alias_after_type_keyword()
    exports.push({ local_name: type_alias.name, export_name: type_alias.name })
    self.collected_type_aliases.push(type_alias)
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
      reexports.push({
        module_spec,
        kind: @ast.TsReExportKind::Namespace(name),
        type_only: false,
      })
      self.consume_semicolon()
      return (stmts, exports, reexports)
    }
    self.expect_from()
    let module_spec = self.expect_str_literal()
    reexports.push({
      module_spec,
      kind: @ast.TsReExportKind::All,
      type_only: false,
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
        type_only: false,
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
  if self.is_const_enum_decl_start() {
    let enum_ = self.parse_const_enum_decl(false)
    exports.push({ local_name: enum_.name, export_name: enum_.name })
    return (stmts, exports, reexports)
  }
  if (match self.peek().kind {
      Ident(name) => name == "enum"
      _ => false
    }) {
    let enum_ = self.parse_enum_decl_after_enum_keyword(false, false)
    exports.push({ local_name: enum_.name, export_name: enum_.name })
    return (stmts, exports, reexports)
  }
  let is_declare = match self.peek().kind {
    Declare => true
    Ident(name) if name == "declare" => true
    _ => false
  }
  if is_declare {
    let _ = self.advance()
    if self.is_const_enum_decl_start() {
      let enum_ = self.parse_const_enum_decl(true)
      exports.push({ local_name: enum_.name, export_name: enum_.name })
      return (stmts, exports, reexports)
    }
    if self.is_enum_keyword_at(0) {
      let enum_ = self.parse_enum_decl_after_enum_keyword(false, true)
      exports.push({ local_name: enum_.name, export_name: enum_.name })
      return (stmts, exports, reexports)
    }
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
        let type_alias = self.parse_type_alias()
        exports.push({
          local_name: type_alias.name,
          export_name: type_alias.name,
        })
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
      Ident("using") => {
        // `export declare using x: T` — treat like `const` declaration
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
    Ident(name) if name == "namespace" || name == "module" || name == "global" => {
      // Non-declare `export namespace X { ... }` — body may contain
      // runtime class bodies and statements.
      match self.parse_namespace_decl_value_runtime() {
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
fn Parser::parse_export_enum_decl_for_module_block(
  self : Parser,
) -> @ast.TsEnumDecl? raise ParseError {
  if !self.check(Export) {
    return None
  }
  let is_declare = match self.peek_at(1).kind {
    Declare => true
    Ident(name) => name == "declare"
    _ => false
  }
  let enum_offset = if is_declare { 2 } else { 1 }
  let is_enum_decl = self.is_enum_keyword_at(enum_offset)
  let is_const_enum_decl = self.peek_at(enum_offset).kind == Const &&
    self.is_enum_keyword_at(enum_offset + 1)
  if !is_enum_decl && !is_const_enum_decl {
    return None
  }
  let _ = self.expect(Export)
  if is_declare {
    let _ = self.advance()
  }
  if self.is_const_enum_decl_start() {
    Some(self.parse_const_enum_decl(is_declare))
  } else if self.is_enum_keyword_at(0) {
    Some(self.parse_enum_decl_after_enum_keyword(false, is_declare))
  } else {
    raise ParseError("Expected enum declaration after export")
  }
}

///|
fn Parser::parse_import_stmt(self : Parser) -> Unit raise ParseError {
  let _ = self.expect(Import)
  if self.match_(Type) || self.match_ident("type") {
    // import type ...
  }
  match self.peek().kind {
    Str(side_effect_spec) => {
      let _ = self.advance()
      if !self.multi_file_source {
        self.import_module_specs.push(side_effect_spec)
      }
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
    Ident(default_name) => {
      let _ = self.advance()
      self.imported_binding_names.push(default_name)
      if self.match_(Comma) {
        // continue to namespace/named
      } else {
        self.expect_from()
        let default_spec = self.expect_str_literal()
        if !self.multi_file_source {
          self.import_module_specs.push(default_spec)
        }
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
    let ns_name = self.parse_binding_ident()
    self.imported_binding_names.push(ns_name)
  } else if self.match_(LBrace) {
    self.parse_import_specifiers()
    let _ = self.expect(RBrace)
  }
  self.expect_from()
  let tail_spec = self.expect_str_literal()
  if !self.multi_file_source {
    self.import_module_specs.push(tail_spec)
  }
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
  // Ambient mode (`.d.ts` / ambient external module body) treats
  // every `export var/let/const X;` without initializer as type-only.
  //
  // Runtime mode (`.ts` / `.js`) must keep the binding, since
  // `export var X;` is valid JS that creates `var X = undefined;`.
  // The one exception is `const`: bare `export const X;` is a syntax
  // error in real JS, but for parser tolerance (and the historical
  // tests that hand-feed `.d.ts` shapes into `parse_module_block`)
  // we accept the ambient interpretation for `const` even outside
  // `.d.ts` mode. `var` / `let` get the runtime path so the actual
  // declaration emits.
  if !self.in_ambient_module {
    match self.peek_at(0).kind {
      Const => ()
      _ => return false
    }
  }
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
  enums : Array[@ast.TsEnumDecl],
  const_values : Map[String, @ast.TsExpr],
  top_level_stmts : Array[@ast.TsStmt],
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
    // TS2304: `export = name` over a provably undeclared value (see the
    // module-block variant above for the recording contract).
    match self.parse_expr() {
      @ast.TsExpr::Var(name) if !self.in_function =>
        self.grammar_misuses.push("<export-eq>" + name)
      _ => ()
    }
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
    let func = self.parse_function()
    // Exported *value* marker: class/namespace declaration merging needs
    // to know which namespace members were exported (the nested-module
    // re-parse otherwise erases `export`-ness).
    self.grammar_misuses.push("<export-value>" + func.name)
    funcs.push(func)
    return
  }
  match self.peek().kind {
    Ident(name) if name == "async" &&
      self.peek_at(1).kind == Function &&
      !self.has_line_terminator_after() => {
      let _ = self.advance()
      self.in_async = true
      let func = self.parse_function()
      self.grammar_misuses.push("<export-value>" + func.name)
      funcs.push(func)
      self.in_async = false
      return
    }
    _ => ()
  }
  if self.check(Interface) {
    interfaces.push(self.parse_interface())
    return
  }
  if self.is_const_enum_decl_start() {
    let enum_ = self.parse_const_enum_decl(false)
    self.grammar_misuses.push("<export-value>" + enum_.name)
    enums.push(enum_)
    return
  }
  if self.is_enum_keyword_at(0) {
    let enum_ = self.parse_enum_decl_after_enum_keyword(false, false)
    self.grammar_misuses.push("<export-value>" + enum_.name)
    enums.push(enum_)
    return
  }
  match self.peek().kind {
    Ident(name) if name == "abstract" && self.peek_at(1).kind == Class => {
      // `export abstract class` at module scope is a runtime class
      // declaration with a body (methods, definite-assignment fields,
      // static init blocks, etc.). Route to the same runtime parser used
      // by the non-export branch; it also tolerates bodyless method
      // signatures so ambient cases still work.
      let _ = self.advance() // consume `abstract`
      let _ = self.parse_class_decl_with_abstract(true)
      match self.take_last_runtime_class_decl() {
        Some(class_) => classes.push(class_)
        None => ()
      }
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
    if self.is_const_enum_decl_start() {
      enums.push(self.parse_const_enum_decl(true))
      return
    }
    if self.is_enum_keyword_at(0) {
      enums.push(self.parse_enum_decl_after_enum_keyword(false, true))
      return
    }
    match self.peek().kind {
      Function => {
        let _ = self.advance() // consume 'function'
        imports.push(self.parse_declare_function())
      }
      Var | Let | Const => {
        let _ = self.advance()
        let parsed_values = self.parse_declare_values()
        for value in parsed_values {
          self.grammar_misuses.push("<export-value>" + value.name)
          values.push(value)
        }
      }
      Ident("using") => {
        // `declare using x: T` — treat like `const` declaration
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
    let name = self.parse_binding_ident()
    let _ = self.expect(Eq)
    type_aliases.push({
      name,
      type_params: [],
      type_param_bounds: [],
      type_: @ast.TsType::Any,
    })
    self.skip_until_semicolon()
    return
  }
  // export let/const/var/class/function (fallback)
  let is_namespace_like_export = match self.peek().kind {
    Ident(name) => name == "namespace" || name == "module" || name == "global"
    _ => false
  }
  if is_namespace_like_export {
    // `export namespace X { ... }` — runtime context.
    match self.parse_namespace_decl_runtime() {
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
      Some(class_) => {
        self.grammar_misuses.push("<export-value>" + class_.name)
        classes.push(class_)
      }
      None => ()
    }
    return
  }
  if self.match_ident("abstract") && self.check(Class) {
    let _ = self.parse_class_decl_with_abstract(true)
    match self.take_last_runtime_class_decl() {
      Some(class_) => {
        self.grammar_misuses.push("<export-value>" + class_.name)
        classes.push(class_)
      }
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
    match stmt {
      Var(Ident(n), _, _) | Let(Ident(n), _, _) | Const(Ident(n), _, _) =>
        self.grammar_misuses.push("<export-value>" + n)
      _ => ()
    }
    // Retain the statement so the checker walks the initializer expression
    // (`export var b = C.bar`) the same way it does a non-exported
    // `var b = C.bar`. Without this the initializer was dropped, so no
    // expression-level check (accessibility, call arity, always-truthy, …)
    // ever fired on exported variable initializers -- including every
    // binding inside a namespace, where all members are exported.
    top_level_stmts.push(stmt)
    return
  }
  // ES2023 `using` / `await using` declarations at the module export
  // position. The body parses via the regular statement-level
  // `using` path (which builds an effective `Let(...)` binding).
  if self.is_using_declaration_start() ||
    self.is_await_using_declaration_start() {
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
  self.in_ambient_module = ambient_decls
  let funcs : Array[@ast.TsFunc] = []
  let interfaces : Array[@ast.TsInterface] = []
  let type_aliases : Array[@ast.TsTypeAlias] = []
  let imports : Array[@ast.TsImport] = []
  let values : Array[@ast.TsValueDecl] = []
  let classes : Array[@ast.TsClassDecl] = []
  let namespaces : Array[@ast.TsNamespaceDecl] = []
  let enums : Array[@ast.TsEnumDecl] = []
  let module_augmentations : Array[(String, @ast.TsModule)] = []
  let top_level_stmts : Array[@ast.TsStmt] = []
  let const_values : Map[String, @ast.TsExpr] = {}
  for entry in seeded_const_values {
    const_values[entry.0] = entry.1
  }
  while !self.check(Eof) {
    // Consume any top-level decorators (`@foo`, `@foo()`). Decorators are
    // erased from the bridge AST; we just skip them and parse the declaration
    // that follows (`class`, `export class`, `async function`, etc.).
    let mut saw_decorator_here = false
    while self.check(At) {
      self.skip_decorator()
      saw_decorator_here = true
    }
    // TS1206: decorators only attach to class declarations. When the next
    // token cannot begin one (`enum`, `function`, `interface`, `var`,
    // `import`, ...), the pending decorators are orphaned -- record one
    // diagnostic per group and drop them. `export ...` is left alone (the
    // class may follow the modifier chain). Gated on decorators actually
    // skipped in *this* iteration: some class-parse paths legitimately leave
    // stale pending entries behind, and those must not re-trigger here.
    if saw_decorator_here && self.pending_decorators.length() > 0 {
      let can_take_decorators = match self.peek().kind {
        Class | Export | At => true
        Ident("abstract") => true
        Declare => true
        _ => false
      }
      if !can_take_decorators {
        self.invalid_decorator_uses.push("top-level")
        self.pending_decorators.clear()
      }
    }
    if self.check(Function) {
      funcs.push(self.parse_function())
    } else if (match self.peek().kind {
        Ident("async") =>
          match self.peek_at(1).kind {
            // TS1042: `async` is only valid on functions / methods. An
            // `async class` / `async enum` / `async interface` /
            // `async namespace` records the misuse and drops the modifier so
            // the declaration itself still parses.
            Class | Interface | Ident("namespace") | Ident("enum") => {
              self.grammar_misuses.push("`async` modifier cannot be used here")
              let _ = self.advance()
              false
            }
            _ => self.peek_at(1).kind == Function
          }
        _ => false
      }) {
      // Top-level `async function f() { ... }` declaration.
      let _ = self.advance() // consume `async`
      let prev_async = self.in_async
      self.in_async = true
      let func = self.parse_function()
      self.in_async = prev_async
      funcs.push(func)
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
      if self.is_const_enum_decl_start() {
        enums.push(self.parse_const_enum_decl(true))
        continue
      }
      if self.is_enum_keyword_at(0) {
        enums.push(self.parse_enum_decl_after_enum_keyword(false, true))
        continue
      }
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
            match self.parse_ambient_external_module_decl_with_spec() {
              Some((spec, module_)) => {
                // Record the augmentation so downstream resolvers can
                // merge it into the imported module's surface; also
                // append the declarations into the surrounding scope
                // (TS's "module augmentation extends the surrounding
                // declaration file" behavior) so existing flows that
                // don't consult the augmentation list still see the
                // members.
                module_augmentations.push((spec, module_))
                append_module_decls(
                  module_, funcs, interfaces, type_aliases, imports, values, classes,
                  namespaces, enums,
                )
              }
              None => ()
            }
          } else if name == "namespace" ||
            name == "module" ||
            name == "global" ||
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
    } else if self.check(Import) &&
      self.peek_at(1).kind != LParen &&
      self.peek_at(1).kind != Dot {
      // `import a = Ns;` (import-equals alias) declares a value-level binding
      // `a`. `parse_import_stmt` consumes but discards it, so capture the
      // alias name first and record it as a value so references resolve
      // (otherwise it reads as an undefined identifier).
      let import_equals_alias = match
        (self.peek_at(1).kind, self.peek_at(2).kind) {
        (Ident(n), Eq) => Some(n)
        _ => None
      }
      self.parse_import_stmt()
      match import_equals_alias {
        Some(n) => values.push({ name: n, type_: @ast.TsType::Any })
        None => ()
      }
    } else if self.check(Import) {
      // `import(...)` (dynamic import) / `import.meta` in statement position —
      // parse as an expression statement rather than an import declaration.
      let _ = self.parse_stmt()
    } else if self.check(Export) {
      self.parse_export_stmt(
        funcs, interfaces, type_aliases, imports, values, classes, namespaces, enums,
        const_values, top_level_stmts,
      )
    } else if self.check(Type) {
      let type_alias = self.parse_type_alias()
      type_aliases.push(type_alias)
      match type_alias_to_interface(type_alias) {
        Some(iface) => interfaces.push(iface)
        None => ()
      }
    } else if self.is_namespace_decl_start() {
      // Inherit ambient/runtime mode from the enclosing parser so the body
      // is parsed under the same context the caller selected.
      let parse_result = if ambient_decls {
        self.parse_namespace_decl()
      } else {
        self.parse_namespace_decl_runtime()
      }
      match parse_result {
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
    } else if self.is_enum_keyword_at(0) {
      enums.push(self.parse_enum_decl_after_enum_keyword(false, ambient_decls))
    } else if self.is_const_enum_decl_start() {
      enums.push(self.parse_const_enum_decl(ambient_decls))
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
        top_level_stmts.push(stmt)
      } else {
        let stmt = self.parse_stmt()
        top_level_stmts.push(stmt)
      }
    } else if !ambient_decls {
      // Real TS / JS modules can contain ordinary top-level statements:
      // `if (...) {}`, expression statements (`foo();`), bare blocks
      // (`{ ... }` used for scoped local types), assignments, etc.
      // Delegate to the statement parser; it raises a ParseError for
      // anything genuinely malformed. Retain the parsed statement so
      // the checker can validate calls, assignments, and other
      // expression-level patterns against the declared types.
      let stmt = self.parse_stmt()
      top_level_stmts.push(stmt)
    } else {
      raise ParseError(
        "Expected function, interface, declare, import, or export declaration",
      )
    }
  }
  // Merge type aliases collected from function-body / block-level `type T = …`
  // declarations into the module's type-alias pool. These are erased at
  // runtime but the checker needs them to resolve Named(T) references inside
  // those bodies. Module-level declarations (already in `type_aliases`) take
  // priority: only add a collected alias if the name isn't already registered.
  let seen_aliases : Map[String, Bool] = {}
  for ta in type_aliases {
    seen_aliases[ta.name] = true
  }
  for ta in self.collected_type_aliases {
    if !seen_aliases.contains(ta.name) {
      type_aliases.push(ta)
      seen_aliases[ta.name] = true
      match type_alias_to_interface(ta) {
        Some(iface) => interfaces.push(iface)
        None => ()
      }
    }
  }
  {
    funcs,
    interfaces,
    type_aliases,
    imports,
    values,
    classes,
    namespaces,
    enums,
    module_augmentations,
    top_level_stmts,
    strict_property_initialization: detect_strict_property_initialization(
      self.src,
    ),
    strict_null_checks: detect_strict_null_checks(self.src),
    use_define_for_class_fields: detect_use_define_for_class_fields(self.src),
    deprecated_compiler_options: detect_deprecated_compiler_options(self.src),
    parameter_property_misuses: self.param_property_misuses,
    strict_mode_misuses: self.strict_mode_misuses,
    invalid_decorator_uses: self.invalid_decorator_uses,
    grammar_misuses: self.grammar_misuses,
    imported_binding_names: self.imported_binding_names,
    import_module_specs: self.import_module_specs,
    class_base_type_args: self.class_base_type_args,
    param_optional_initializer_misuses: self.param_optional_initializer_misuses,
    interface_member_modifier_misuses: self.interface_member_modifier_misuses,
    class_dup_diagnostics: self.collected_class_dups,
  }
}

///|
/// Scan the leading test-header directives for deprecated compiler options
/// that TypeScript 6.0+ reports (TS5107 / TS5101). Two shapes are handled:
///
///   - value-specific: `target=ES3` / `target=ES5`, exercised through
///     multi-target directive lists like `// @target: esnext, es2015, es5`.
///     Only the unambiguous `ES3` / `ES5` targets are surfaced.
///   - presence-based: `outFile` / `out` / `baseUrl` / `downlevelIteration`
///     are deprecated whenever specified, regardless of value, so the bare
///     presence of the `// @<option>:` directive is enough.
///
/// The directive comments only appear in the conformance corpus; real
/// `.d.ts` / `.ts` bridge inputs never carry them, so this stays empty for
/// them. Returns one canonical option string per detected deprecation, in a
/// stable order.
fn detect_deprecated_compiler_options(src : String) -> Array[String] {
  let out : Array[String] = []
  let head_len = if src.length() < 1024 { src.length() } else { 1024 }
  let head = src[:head_len].to_owned()
  let head_lower = head.to_lower()
  // Value-specific: the `@target:` directive's comma list.
  match head.find("@target:") {
    Some(idx) => {
      let after = head[idx + "@target:".length():].to_owned()
      let line = match after.find("\n") {
        Some(nl) => after[:nl].to_owned()
        None => after
      }
      let mut saw_es3 = false
      let mut saw_es5 = false
      for raw in line.split(",") {
        let tok = raw.trim().to_owned().to_lower()
        if tok == "es3" {
          saw_es3 = true
        } else if tok == "es5" {
          saw_es5 = true
        }
      }
      // One diagnostic per distinct deprecated value.
      if saw_es5 {
        out.push("target=ES5")
      }
      if saw_es3 {
        out.push("target=ES3")
      }
    }
    None => ()
  }
  // Value-specific: the `@module:` directive's comma list. TypeScript 6
  // deprecates the `amd` / `umd` / `system` module targets (TS5107).
  match head_lower.find("@module:") {
    Some(idx) => {
      let after = head_lower[idx + "@module:".length():].to_owned()
      let line = match after.find("\n") {
        Some(nl) => after[:nl].to_owned()
        None => after
      }
      let mut saw_amd = false
      let mut saw_umd = false
      let mut saw_system = false
      for raw in line.split(",") {
        let tok = raw.trim().to_owned()
        if tok == "amd" {
          saw_amd = true
        } else if tok == "umd" {
          saw_umd = true
        } else if tok == "system" {
          saw_system = true
        }
      }
      if saw_amd {
        out.push("module=AMD")
      }
      if saw_umd {
        out.push("module=UMD")
      }
      if saw_system {
        out.push("module=System")
      }
    }
    None => ()
  }
  // Presence-based options. `@out:` and `@outFile:` are distinct directives;
  // the trailing colon keeps `@out:` from matching inside `@outFile:` /
  // `@outDir:`.
  for opt in ["outFile", "out", "baseUrl", "downlevelIteration"] {
    if head_lower.find("@" + opt.to_lower() + ":") is Some(_) {
      out.push(opt)
    }
  }
  out
}

///|
/// Scan the file's leading TS-test header directives (`// @strict:
/// false`, `// @strictPropertyInitialization: false`,
/// `// @useDefineForClassFields: true`) to decide whether the
/// strict-property-initialization check (TS2564) should fire. The
/// conformance corpus uses these directives to opt individual test
/// files in or out of strict mode. Default is `true`: the tsc-
/// generated baselines for files *without* a directive include
/// TS2564, so emitting matches the baseline.
fn detect_strict_property_initialization(src : String) -> Bool {
  // Only scan the first ~1 KB; directives always live at the top.
  let head_len = if src.length() < 1024 { src.length() } else { 1024 }
  let head = src[:head_len].to_owned()
  // Explicit opt-outs.
  if head.contains("@strict: false") || head.contains("@strict:false") {
    return false
  }
  if head.contains("@strictPropertyInitialization: false") ||
    head.contains("@strictPropertyInitialization:false") {
    return false
  }
  // No directive (or explicit opt-in) -> default true.
  true
}

///|
/// Scan the file's leading TS-test header directives for the
/// `strictNullChecks` setting. Shares the default (`true`, matching the
/// conformance baseline) and the `@strict: false` opt-out with
/// `detect_strict_property_initialization`, but ignores
/// `@strictPropertyInitialization: false` and honours an explicit
/// `@strictNullChecks: false` opt-out instead.
fn detect_strict_null_checks(src : String) -> Bool {
  let head_len = if src.length() < 1024 { src.length() } else { 1024 }
  let head = src[:head_len].to_owned()
  if head.contains("@strict: false") || head.contains("@strict:false") {
    return false
  }
  if head.contains("@strictNullChecks: false") ||
    head.contains("@strictNullChecks:false") {
    return false
  }
  // No directive (or explicit opt-in) -> default true.
  true
}

///|
/// Detect whether class field initializers should be treated as
/// `[[DefineOwnProperty]]`-style runs (`useDefineForClassFields: true`).
/// Triggers TS2729 ("Property used before initialization") emission.
/// Fires on explicit `// @useDefineForClassFields: true` directives,
/// otherwise falls back to the TS default for the target (es2022+ /
/// esnext default to true).
fn detect_use_define_for_class_fields(src : String) -> Bool {
  let head_len = if src.length() < 1024 { src.length() } else { 1024 }
  let head = src[:head_len].to_owned()
  if head.contains("@useDefineForClassFields: true") ||
    head.contains("@useDefineForClassFields:true") {
    return true
  }
  if head.contains("@useDefineForClassFields: false") ||
    head.contains("@useDefineForClassFields:false") {
    return false
  }
  // Default per target: es2022+ / esnext use define semantics; older
  // targets emit assignment-style class fields. Only when the
  // directive line lists ONLY a "define-on" target do we opt in --
  // multi-target directives like `@target: es5, esnext` leave it off.
  // Sources without an explicit target are treated as pre-es2022
  // (the conformance default).
  if head.contains("@target: esnext") ||
    head.contains("@target:esnext") ||
    head.contains("@target: es2022") ||
    head.contains("@target:es2022") {
    return true
  }
  false
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
  let stmt_positions : Array[Int] = []
  let imports : Array[@ast.TsImportDecl] = []
  let exports : Array[@ast.TsExportSpec] = []
  let reexports : Array[@ast.TsReExportSpec] = []
  let enums : Array[@ast.TsEnumDecl] = []
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
      // Remember which JSDoc tags decorated this `export` token.
      // `@internal` hides the decl from `.d.ts`; `@deprecated`
      // gets carried over as a comment in the emitted decl.
      let export_pos = self.peek().pos
      let is_internal = self.internal_marker_positions.contains(export_pos)
      let mut deprecation_msg : String? = None
      let mut is_pure = false
      match self.jsdoc_at_pos.get(export_pos) {
        Some(jb) =>
          for t in jb.tags {
            match t {
              Deprecated(msg) => deprecation_msg = Some(msg)
              Pure | NoSideEffects => is_pure = true
              _ => ()
            }
          }
        None => ()
      }
      match self.parse_export_enum_decl_for_module_block() {
        Some(enum_) => {
          enums.push(enum_)
          exports.push({ local_name: enum_.name, export_name: enum_.name })
          if is_internal {
            self.collected_internal_names[enum_.name] = true
          }
          match deprecation_msg {
            Some(msg) => self.collected_deprecations[enum_.name] = msg
            None => ()
          }
          continue
        }
        None => ()
      }
      let (block_stmts, export_specs, reexport_specs) = self.parse_export_decl_for_module(
        const_values,
      )
      for stmt in block_stmts {
        stmts.push(stmt)
      }
      for spec in export_specs {
        exports.push(spec)
        if is_internal {
          self.collected_internal_names[spec.local_name] = true
        }
        if is_pure {
          self.collected_pure_declarations[spec.local_name] = true
        }
        match deprecation_msg {
          Some(msg) => self.collected_deprecations[spec.local_name] = msg
          None => ()
        }
      }
      for spec in reexport_specs {
        reexports.push(spec)
      }
      continue
    }
    if self.check(Declare) {
      let _ = self.advance()
      if self.is_const_enum_decl_start() {
        enums.push(self.parse_const_enum_decl(true))
        continue
      }
      if self.is_enum_keyword_at(0) {
        enums.push(self.parse_enum_decl_after_enum_keyword(false, true))
        continue
      }
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
        Type => self.collected_type_aliases.push(self.parse_type_alias())
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
          } else if name == "namespace" || name == "module" || name == "global" {
            // `declare namespace N { ... }` — not retained on the block, but
            // hoist any nested enums so they aren't silently dropped.
            match self.parse_namespace_decl() {
              Some((_, Some(ns))) => collect_enums_recursive(ns.module_, enums)
              _ => ()
            }
          } else if name == "enum" || name == "class" {
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
      // Type aliases are erased at runtime but we keep them in
      // `TsModuleBlock.type_aliases` so whole-program type-driven
      // passes (e.g. discriminant-tag rewrite) can inspect them.
      self.collected_type_aliases.push(self.parse_type_alias())
      continue
    }
    if self.is_namespace_decl_start() {
      // Namespaces aren't retained on `TsModuleBlock`, but enums declared
      // inside them must still be registered. Parse the body and hoist any
      // nested enums rather than dropping the whole block.
      match self.parse_namespace_decl_runtime() {
        Some((_, Some(ns))) => collect_enums_recursive(ns.module_, enums)
        _ => ()
      }
      continue
    }
    if self.is_const_enum_decl_start() {
      enums.push(self.parse_const_enum_decl(false))
      continue
    }
    if self.is_enum_keyword_at(0) {
      enums.push(self.parse_enum_decl_after_enum_keyword(false, false))
      continue
    }
    if self.check(Const) {
      let pos = self.peek().pos
      let stmt = self.parse_stmt()
      collect_static_const_exprs_from_stmt(stmt, const_values)
      // Keep the const declaration on the runtime statement stream
      // too — bridge passes consume `const_values` for build-time
      // table extraction, but the transform / bundle phase needs
      // every runtime statement in `block.stmts`.
      stmt_positions.push(pos)
      stmts.push(stmt)
      continue
    }
    let pos = self.peek().pos
    // Capture JSDoc purity annotations on non-export decls too.
    // `function helper() {}` with `/** @__NO_SIDE_EFFECTS__ */`
    // attached should be treated as pure by the analysis.
    let mut is_pure_decl = false
    match self.jsdoc_at_pos.get(pos) {
      Some(jb) =>
        for t in jb.tags {
          match t {
            Pure | NoSideEffects => is_pure_decl = true
            _ => ()
          }
        }
      None => ()
    }
    let stmt = self.parse_stmt()
    if is_pure_decl {
      let names : Array[String] = []
      collect_decl_names_from_stmt(stmt, names)
      for n in names {
        self.collected_pure_declarations[n] = true
      }
    }
    stmts.push(stmt)
    stmt_positions.push(pos)
  }
  (
    {
      block: { stmts, stmt_positions },
      imports,
      exports,
      reexports,
      enums,
      internal_names: self.collected_internal_names,
      deprecations: self.collected_deprecations,
      pure_declarations: self.collected_pure_declarations,
      type_aliases: self.collected_type_aliases,
    },
    const_values,
  )
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
  let stmt_positions : Array[Int] = []
  while !parser.check(Eof) {
    stmt_positions.push(parser.peek().pos)
    stmts.push(parser.parse_stmt())
  }
  { stmts, stmt_positions }
}

///|
/// Parse a statement block and also record each top-level statement's
/// start byte offset. Returned arrays are aligned: `positions[i]` is
/// the byte offset of the first token of `block.stmts[i]`. Used by
/// the source-map generator to attribute emit-side statements back
/// to their position in the original source.
pub fn parse_block_from_source_with_positions(
  source : String,
) -> (@ast.TsBlock, Array[Int]) raise ParseError {
  let block = parse_block_from_source(source)
  (block, block.stmt_positions)
}

///|
/// Parse a TypeScript type expression from a string. Used by the
/// JSDoc consumption pass to lift `@param {Type}` / `@returns {Type}`
/// brace contents into proper `TsType` values that downstream passes
/// can reason about.
pub fn parse_type_from_source(source : String) -> @ast.TsType raise ParseError {
  let parser = Parser::from_source(source)
  parser.parse_type()
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
  let stmt_positions : Array[Int] = []
  while !parser.check(Eof) {
    stmt_positions.push(parser.peek().pos)
    stmts.push(parser.parse_stmt())
  }
  { stmts, stmt_positions }
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
