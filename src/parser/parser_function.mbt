// ============================================
// function
// ============================================

///|
fn Parser::skip_param_decorators(self : Parser) -> Unit raise ParseError {
  while self.match_(At) {
    let _ = self.parse_binding_ident()
    while self.match_(Dot) {
      let _ = self.parse_binding_ident()
    }
    if self.check(Lt) {
      self.skip_type_args()
    }
    if self.check(LParen) {
      let _ = self.advance()
      let mut paren_depth = 1
      let mut brace_depth = 0
      let mut bracket_depth = 0
      while paren_depth > 0 && !self.check(Eof) {
        match self.peek().kind {
          LParen => {
            paren_depth += 1
            let _ = self.advance()
          }
          RParen => {
            paren_depth -= 1
            let _ = self.advance()
          }
          LBrace => {
            brace_depth += 1
            let _ = self.advance()
          }
          RBrace => {
            if brace_depth > 0 {
              brace_depth -= 1
            }
            let _ = self.advance()
          }
          LBracket => {
            bracket_depth += 1
            let _ = self.advance()
          }
          RBracket => {
            if bracket_depth > 0 {
              bracket_depth -= 1
            }
            let _ = self.advance()
          }
          _ => {
            let _ = self.advance()
          }
        }
      }
    }
  }
}

///|
fn Parser::skip_param_modifiers(self : Parser) -> Unit {
  let mut has_modifier = true
  while has_modifier {
    has_modifier = false
    match self.peek().kind {
      Ident(name) if name == "public" ||
        name == "private" ||
        name == "protected" ||
        name == "readonly" ||
        name == "override" =>
        match self.peek_at(1).kind {
          Ident(_)
          | PrivateIdent(_)
          | LBrace
          | LBracket
          | Yield
          | NumberType
          | BooleanType
          | StringType
          | VoidType
          | IntType
          | Type
          | Of
          | In => {
            let _ = self.advance()
            has_modifier = true
          }
          _ => ()
        }
      _ => ()
    }
  }
}

///|
fn wrap_optional_ts_type(type_ : @ast.TsType) -> @ast.TsType {
  match type_ {
    @ast.TsType::Undefined | @ast.TsType::Null =>
      @ast.TsType::Union([type_, @ast.TsType::Undefined])
    @ast.TsType::Union(items) => {
      for item in items {
        match item {
          @ast.TsType::Undefined | @ast.TsType::Null => return type_
          _ => ()
        }
      }
      @ast.TsType::Union([type_, @ast.TsType::Undefined])
    }
    _ => @ast.TsType::Union([type_, @ast.TsType::Undefined])
  }
}

///|
// / parameter
fn Parser::parse_param(self : Parser) -> @ast.TsParam raise ParseError {
  self.skip_param_decorators()
  self.skip_param_modifiers()
  let is_rest = self.match_ellipsis()
  let binding = self.parse_binding_pattern()
  let name = self.binding_first_name(binding)
  let is_optional = self.match_(Question)
  // type ()
  let base_type = if self.check(Colon) {
    let _ = self.advance()
    self.parse_type()
  } else {
    Any // type Any
  }
  let type_ = if is_optional {
    wrap_optional_ts_type(base_type)
  } else {
    base_type
  }
  // check
  let default : @ast.TsExpr? = if self.match_(Eq) {
    Some(self.parse_assignment())
  } else {
    None
  }
  { name, binding: Some(binding), is_rest, type_, default }
}

///|
// / parameter
fn Parser::parse_params(self : Parser) -> Array[@ast.TsParam] raise ParseError {
  let params : Array[@ast.TsParam] = []
  if !self.check(RParen) {
    params.push(self.parse_param())
    while self.match_(Comma) {
      if self.check(RParen) {
        break
      }
      params.push(self.parse_param())
    }
  }
  // Check for duplicate parameter names
  // In strict mode or with non-simple parameters (default, rest, destructuring),
  // duplicate names are forbidden
  let has_default = params.iter().any(fn(p) { !(p.default is None) })
  let has_rest = params.iter().any(fn(p) { p.is_rest })
  let has_destructuring = params
    .iter()
    .any(fn(p) {
      match p.binding {
        Some(@ast.TsBinding::Array(_)) | Some(@ast.TsBinding::Object(_)) => true
        _ => false
      }
    })
  let is_simple = !has_default && !has_rest && !has_destructuring
  // Collect all bound names
  let all_names : Array[String] = []
  for param in params {
    match param.binding {
      Some(binding) => self.collect_binding_names(binding, all_names)
      None => ()
    }
  }
  // Check for duplicates
  let seen : Map[String, Bool] = {}
  for name in all_names {
    if seen.contains(name) {
      // In strict mode or with non-simple params, duplicates are errors
      if self.in_strict || !is_simple {
        raise ParseError("Duplicate parameter name '\{name}' not allowed")
      }
    }
    seen[name] = true
  }
  params
}

///|
// / function
pub fn Parser::parse_function(self : Parser) -> @ast.TsFunc raise ParseError {
  let _ = self.expect(Function)
  let is_generator = self.match_(Star)
  let is_async = self.in_async
  let name = self.parse_binding_ident()
  self.skip_type_params()
  let _ = self.expect(LParen)
  let params = self.parse_params()
  let _ = self.expect(RParen)
  // return valuetype ()
  let return_type = if self.check(Colon) {
    let _ = self.advance()
    self.parse_type()
  } else {
    Any // type Any
  }
  if self.check(Semicolon) {
    let _ = self.advance()
    return {
      name,
      params,
      return_type,
      body: { stmts: [] },
      is_generator,
      is_async,
    }
  }
  if !self.check(LBrace) {
    return {
      name,
      params,
      return_type,
      body: { stmts: [] },
      is_generator,
      is_async,
    }
  }
  // Save and set function context (new function scope resets iteration/switch/labels context)
  let prev_generator = self.in_generator
  let prev_async = self.in_async
  let prev_function = self.in_function
  let prev_iteration = self.in_iteration
  let prev_switch = self.in_switch
  // Save labels and clear for new function scope (labels don't cross function boundaries)
  let prev_labels : Array[String] = []
  for label in self.labels {
    prev_labels.push(label)
  }
  if is_generator {
    self.in_generator = true
  }
  self.in_async = false // Reset for nested functions
  self.in_function = true
  self.in_iteration = false
  self.in_switch = false
  // Clear labels for new function scope
  while self.labels.length() > 0 {
    let _ = self.labels.pop()
  }
  let body = self.parse_block()
  self.in_generator = prev_generator
  self.in_async = prev_async
  self.in_function = prev_function
  self.in_iteration = prev_iteration
  self.in_switch = prev_switch
  // Restore labels
  while self.labels.length() > 0 {
    let _ = self.labels.pop()
  }
  for label in prev_labels {
    self.labels.push(label)
  }
  { name, params, return_type, body, is_generator, is_async }
}

///|
// / functionexpression()
fn Parser::parse_function_expr(self : Parser) -> @ast.TsFunc raise ParseError {
  let _ = self.expect(Function)
  let is_generator = self.match_(Star)
  let is_async = self.in_async
  let name = match self.peek().kind {
    Ident(_)
    | Yield
    | NumberType
    | BooleanType
    | StringType
    | VoidType
    | IntType
    | Type
    | Let
    | Switch
    | Case
    | Default
    | With
    | Debugger
    | Import
    | Export
    | From
    | As
    | Of
    | In => self.parse_binding_ident()
    _ => "<anon>"
  }
  self.skip_type_params()
  let _ = self.expect(LParen)
  let params = self.parse_params()
  let _ = self.expect(RParen)
  let return_type = if self.check(Colon) {
    let _ = self.advance()
    self.parse_type()
  } else {
    Any
  }
  // Save and set function context (new function scope resets iteration/switch/labels context)
  let prev_generator = self.in_generator
  let prev_async = self.in_async
  let prev_function = self.in_function
  let prev_iteration = self.in_iteration
  let prev_switch = self.in_switch
  // Save labels and clear for new function scope (labels don't cross function boundaries)
  let prev_labels : Array[String] = []
  for label in self.labels {
    prev_labels.push(label)
  }
  if is_generator {
    self.in_generator = true
  }
  self.in_async = false // Reset for nested functions
  self.in_function = true
  self.in_iteration = false
  self.in_switch = false
  // Clear labels for new function scope
  while self.labels.length() > 0 {
    let _ = self.labels.pop()
  }
  let body = self.parse_block()
  self.in_generator = prev_generator
  self.in_async = prev_async
  self.in_function = prev_function
  self.in_iteration = prev_iteration
  self.in_switch = prev_switch
  // Restore labels
  while self.labels.length() > 0 {
    let _ = self.labels.pop()
  }
  for label in prev_labels {
    self.labels.push(label)
  }
  { name, params, return_type, body, is_generator, is_async }
}

///|
/// Skip generic type parameters <T, U extends Foo, V = Default>
fn Parser::skip_type_params(self : Parser) -> Unit {
  if !self.check(Lt) {
    return
  }
  let _ = self.advance() // consume <
  let mut depth = 1
  while depth > 0 && !self.check(Eof) {
    match self.peek().kind {
      Lt => {
        depth += 1
        let _ = self.advance()
      }
      Gt => {
        depth -= 1
        let _ = self.advance()
      }
      GtGt => {
        // >> counts as two >
        depth -= 2
        let _ = self.advance()
      }
      GtGtGt => {
        // >>> counts as three >
        depth -= 3
        let _ = self.advance()
      }
      _ => {
        let _ = self.advance()
      }
    }
  }
}

///|
/// Skip extends clause: extends Foo, Bar<T>
fn Parser::skip_extends_clause(self : Parser) -> Unit {
  if !self.check(Extends) {
    return
  }
  let _ = self.advance() // consume extends
  let mut paren_depth = 0
  let mut bracket_depth = 0
  let mut angle_depth = 0
  while !self.check(Eof) {
    match self.peek().kind {
      LBrace if paren_depth == 0 && bracket_depth == 0 && angle_depth == 0 =>
        break
      LParen => {
        paren_depth += 1
        let _ = self.advance()
      }
      RParen => {
        if paren_depth > 0 {
          paren_depth -= 1
        }
        let _ = self.advance()
      }
      LBracket => {
        bracket_depth += 1
        let _ = self.advance()
      }
      RBracket => {
        if bracket_depth > 0 {
          bracket_depth -= 1
        }
        let _ = self.advance()
      }
      Lt => {
        angle_depth += 1
        let _ = self.advance()
      }
      Gt => {
        if angle_depth > 0 {
          angle_depth -= 1
        }
        let _ = self.advance()
      }
      GtGt => {
        angle_depth = if angle_depth >= 2 { angle_depth - 2 } else { 0 }
        let _ = self.advance()
      }
      GtGtGt => {
        angle_depth = if angle_depth >= 3 { angle_depth - 3 } else { 0 }
        let _ = self.advance()
      }
      Comma => {
        let _ = self.advance()
      }
      _ => {
        let _ = self.advance()
      }
    }
  }
}

///|
fn Parser::can_consume_interface_readonly_modifier(self : Parser) -> Bool {
  if !self.check(Ident("readonly")) {
    return false
  }
  match self.peek_at(1).kind {
    Ident(_)
    | Str(_)
    | Int(_)
    | Number(_)
    | LBracket
    | New
    | Finally
    | Try
    | Catch
    | Throw
    | Delete
    | Debugger
    | Type
    | In
    | Of
    | For
    | From
    | With
    | Typeof
    | Return
    | If
    | Else
    | While
    | Do
    | Switch
    | Case
    | Default
    | Break
    | Continue
    | Extends
    | Class
    | Function
    | Var
    | Let
    | Const
    | StringType
    | NumberType
    | BooleanType
    | VoidType
    | IntType
    | Import
    | Export
    | As
    | Yield
    | Instanceof
    | Declare => true
    _ => false
  }
}

///|
// / interface
pub fn Parser::parse_interface(
  self : Parser,
) -> @ast.TsInterface raise ParseError {
  let _ = self.expect(Interface)
  let name = match self.advance().kind {
    Ident(n) => n
    k => raise ParseError("Expected interface name, got \{k}")
  }
  // Skip generic type parameters <T, U>
  self.skip_type_params()
  // Skip extends clause
  self.skip_extends_clause()
  let _ = self.expect(LBrace)
  let fields : Array[(String, @ast.TsType)] = []
  while !self.check(RBrace) && !self.check(Eof) {
    // Skip readonly modifier
    if self.can_consume_interface_readonly_modifier() {
      let _ = self.advance()
    }
    // Parse field/method name
    let field_name : String = match self.peek().kind {
      // Call signature: (...): T
      LParen => "<call>"
      // Generic call signature: <T>(...): U
      Lt => {
        self.skip_type_params()
        "<call>"
      }
      // Constructor signature: new(...): T
      New => {
        let _ = self.advance()
        "<new>"
      }
      // Computed property / index signature: [key: T]: U or [Symbol.xxx]: T
      LBracket => {
        let _ = self.advance()
        // Skip until ]
        while !self.check(RBracket) && !self.check(Eof) {
          let _ = self.advance()
        }
        let _ = self.expect(RBracket)
        "<computed>"
      }
      // Regular identifier
      Ident(n) => {
        let _ = self.advance()
        n
      }
      // String literal as field name: "fieldName"
      Str(s) => {
        let _ = self.advance()
        s
      }
      // Number literal as field name: 0, 1, etc.
      Int(n) => {
        let _ = self.advance()
        n.to_string()
      }
      // Keywords as field names (TypeScript allows this)
      Finally => {
        let _ = self.advance()
        "finally"
      }
      Try => {
        let _ = self.advance()
        "try"
      }
      Catch => {
        let _ = self.advance()
        "catch"
      }
      Throw => {
        let _ = self.advance()
        "throw"
      }
      Delete => {
        let _ = self.advance()
        "delete"
      }
      Debugger => {
        let _ = self.advance()
        "debugger"
      }
      Type => {
        let _ = self.advance()
        "type"
      }
      In => {
        let _ = self.advance()
        "in"
      }
      Of => {
        let _ = self.advance()
        "of"
      }
      For => {
        let _ = self.advance()
        "for"
      }
      From => {
        let _ = self.advance()
        "from"
      }
      With => {
        let _ = self.advance()
        "with"
      }
      Typeof => {
        let _ = self.advance()
        "typeof"
      }
      Return => {
        let _ = self.advance()
        "return"
      }
      If => {
        let _ = self.advance()
        "if"
      }
      Else => {
        let _ = self.advance()
        "else"
      }
      While => {
        let _ = self.advance()
        "while"
      }
      Do => {
        let _ = self.advance()
        "do"
      }
      Switch => {
        let _ = self.advance()
        "switch"
      }
      Case => {
        let _ = self.advance()
        "case"
      }
      Default => {
        let _ = self.advance()
        "default"
      }
      Break => {
        let _ = self.advance()
        "break"
      }
      Continue => {
        let _ = self.advance()
        "continue"
      }
      Extends => {
        let _ = self.advance()
        "extends"
      }
      Class => {
        let _ = self.advance()
        "class"
      }
      Function => {
        let _ = self.advance()
        "function"
      }
      Var => {
        let _ = self.advance()
        "var"
      }
      Let => {
        let _ = self.advance()
        "let"
      }
      Const => {
        let _ = self.advance()
        "const"
      }
      StringType => {
        let _ = self.advance()
        "string"
      }
      NumberType => {
        let _ = self.advance()
        "number"
      }
      BooleanType => {
        let _ = self.advance()
        "boolean"
      }
      VoidType => {
        let _ = self.advance()
        "void"
      }
      IntType => {
        let _ = self.advance()
        "int"
      }
      Import => {
        let _ = self.advance()
        "import"
      }
      Export => {
        let _ = self.advance()
        "export"
      }
      As => {
        let _ = self.advance()
        "as"
      }
      Yield => {
        let _ = self.advance()
        "yield"
      }
      Instanceof => {
        let _ = self.advance()
        "instanceof"
      }
      Declare => {
        let _ = self.advance()
        "declare"
      }
      k => raise ParseError("Expected field name, got \{k}")
    }
    // Skip method type parameters <T>
    self.skip_type_params()
    // Check for optional marker ?
    let is_optional = self.match_(Question)
    // Method signature: name(...): T or name<T>(...): U
    if self.check(LParen) {
      let _ = self.advance()
      // Skip parameters
      let mut paren_depth = 1
      while paren_depth > 0 && !self.check(Eof) {
        match self.peek().kind {
          LParen => {
            paren_depth += 1
            let _ = self.advance()
          }
          RParen => {
            paren_depth -= 1
            let _ = self.advance()
          }
          _ => {
            let _ = self.advance()
          }
        }
      }
      // Return type
      if self.check(Colon) {
        let _ = self.advance()
        let field_type = self.parse_type()
        fields.push(
          (
            field_name,
            if is_optional {
              wrap_optional_ts_type(field_type)
            } else {
              field_type
            },
          ),
        )
      } else {
        let field_type = @ast.TsType::Void
        fields.push(
          (
            field_name,
            if is_optional {
              wrap_optional_ts_type(field_type)
            } else {
              field_type
            },
          ),
        )
      }
    } else if self.check(Colon) {
      // Property: name: T
      let _ = self.advance()
      let field_type = self.parse_type()
      fields.push(
        (
          field_name,
          if is_optional {
            wrap_optional_ts_type(field_type)
          } else {
            field_type
          },
        ),
      )
    } else {
      // No type annotation - use Any
      let field_type = @ast.TsType::Any
      fields.push(
        (
          field_name,
          if is_optional {
            wrap_optional_ts_type(field_type)
          } else {
            field_type
          },
        ),
      )
    }
    // Skip trailing semicolon or comma (both optional)
    if self.check(Semicolon) || self.check(Comma) {
      let _ = self.advance()
    }
  }
  let _ = self.expect(RBrace)
  { name, fields }
}

///|
/// Skip until semicolon or end of file, respecting brace/bracket/paren nesting
fn Parser::skip_until_semicolon(self : Parser) -> Unit {
  let mut brace_depth = 0
  let mut bracket_depth = 0
  let mut paren_depth = 0
  while !self.check(Eof) {
    match self.peek().kind {
      Semicolon => {
        if brace_depth == 0 && bracket_depth == 0 && paren_depth == 0 {
          let _ = self.advance()
          return
        }
        let _ = self.advance()
      }
      LBrace => {
        brace_depth += 1
        let _ = self.advance()
      }
      RBrace => {
        brace_depth -= 1
        let _ = self.advance()
      }
      LBracket => {
        bracket_depth += 1
        let _ = self.advance()
      }
      RBracket => {
        bracket_depth -= 1
        let _ = self.advance()
      }
      LParen => {
        paren_depth += 1
        let _ = self.advance()
      }
      RParen => {
        paren_depth -= 1
        let _ = self.advance()
      }
      _ => {
        let _ = self.advance()
      }
    }
  }
}

///|
fn Parser::is_top_level_decl_start_token(self : Parser) -> Bool {
  match self.peek().kind {
    Var
    | Let
    | Const
    | Class
    | Import
    | Export
    | Declare
    | Interface
    | Type
    | Function => true
    Ident(name) =>
      name == "abstract" ||
      name == "namespace" ||
      name == "module" ||
      name == "global" ||
      name == "enum" ||
      name == "class"
    _ => false
  }
}

///|
/// Skip type alias: type Name<T> = ...;
fn Parser::skip_type_alias(self : Parser) -> Unit {
  let _ = self.advance() // consume 'type'
  // Skip until semicolon, handling nested braces and angle brackets
  let mut brace_depth = 0
  let mut angle_depth = 0
  while !self.check(Eof) {
    match self.peek().kind {
      LBrace => {
        brace_depth += 1
        let _ = self.advance()
      }
      RBrace => {
        if brace_depth == 0 && angle_depth <= 0 {
          break
        }
        brace_depth -= 1
        let _ = self.advance()
        if brace_depth < 0 {
          break
        }
      }
      Lt => {
        angle_depth += 1
        let _ = self.advance()
      }
      Gt => {
        angle_depth -= 1
        let _ = self.advance()
      }
      GtGt => {
        // >> counts as two >
        angle_depth -= 2
        let _ = self.advance()
      }
      GtGtGt => {
        // >>> counts as three >
        angle_depth -= 3
        let _ = self.advance()
      }
      Semicolon => {
        if brace_depth == 0 && angle_depth <= 0 {
          let _ = self.advance()
          break
        }
        let _ = self.advance()
      }
      _ if brace_depth == 0 &&
        angle_depth <= 0 &&
        self.has_line_terminator_before() &&
        self.is_top_level_decl_start_token() => break
      _ => {
        let _ = self.advance()
      }
    }
  }
}

///|
fn Parser::skip_type_param_clause(self : Parser) -> Unit {
  if !self.check(Lt) {
    return
  }
  let mut angle_depth = 0
  while !self.check(Eof) {
    match self.peek().kind {
      Lt => {
        angle_depth += 1
        let _ = self.advance()
      }
      Gt => {
        angle_depth -= 1
        let _ = self.advance()
        if angle_depth <= 0 {
          break
        }
      }
      GtGt => {
        angle_depth -= 2
        let _ = self.advance()
        if angle_depth <= 0 {
          break
        }
      }
      GtGtGt => {
        angle_depth -= 3
        let _ = self.advance()
        if angle_depth <= 0 {
          break
        }
      }
      _ => {
        let _ = self.advance()
      }
    }
  }
}

///|
fn type_alias_object_fields_to_interface(
  name : String,
  type_ : @ast.TsType,
) -> @ast.TsInterface? {
  match type_ {
    @ast.TsType::Object(fields) => {
      let iface_fields : Array[(String, @ast.TsType)] = []
      for field in fields {
        let (key_type, value_type) = field
        match key_type {
          @ast.TsType::Literal(field_name) =>
            iface_fields.push((field_name, value_type))
          _ => return None
        }
      }
      Some({ name, fields: iface_fields })
    }
    _ => None
  }
}

///|
fn Parser::parse_type_alias_interface_after_type_keyword(
  self : Parser,
) -> @ast.TsInterface? raise ParseError {
  let name = self.parse_binding_ident()
  self.skip_type_param_clause()
  let _ = self.expect(Eq)
  let alias_type = self.parse_type()
  self.consume_semicolon()
  type_alias_object_fields_to_interface(name, alias_type)
}

///|
fn Parser::parse_type_alias_interface(
  self : Parser,
) -> @ast.TsInterface? raise ParseError {
  let _ = self.expect(Type)
  self.parse_type_alias_interface_after_type_keyword()
}

///|
/// Skip declaration block (namespace, module, class, enum, etc.)
fn Parser::skip_declaration_block(self : Parser) -> Unit {
  // Skip until we find { or ;
  while !self.check(LBrace) && !self.check(Semicolon) && !self.check(Eof) {
    let _ = self.advance()
  }
  if self.check(Semicolon) {
    let _ = self.advance()
    return
  }
  if self.check(LBrace) {
    let _ = self.advance()
    let mut depth = 1
    while depth > 0 && !self.check(Eof) {
      match self.peek().kind {
        LBrace => {
          depth += 1
          let _ = self.advance()
        }
        RBrace => {
          depth -= 1
          let _ = self.advance()
        }
        _ => {
          let _ = self.advance()
        }
      }
    }
  }
}

///|
// / declare function (without 'declare function' prefix - already consumed)

///|
/// name(params): returnType;
pub fn Parser::parse_declare_function(
  self : Parser,
) -> @ast.TsImport raise ParseError {

  // function
  let name = self.parse_binding_ident()

  // Skip type parameters if present
  self.skip_type_params()
  // parameter
  let _ = self.expect(LParen)
  let params : Array[(String, @ast.TsType)] = []
  while !self.check(RParen) && !self.check(Eof) {
    // Handle rest parameter: ...name
    let _ = self.match_ellipsis()
    let param_name = self.parse_declare_param_name()
    // Handle optional parameter: name?
    let is_optional = self.match_(Question)
    // Type annotation is optional
    if self.check(Colon) {
      let _ = self.advance()
      let param_type = self.parse_type()
      let param_type = if is_optional {
        wrap_optional_ts_type(param_type)
      } else {
        param_type
      }
      params.push((param_name, param_type))
    } else {
      let param_type = if is_optional {
        wrap_optional_ts_type(@ast.TsType::Any)
      } else {
        @ast.TsType::Any
      }
      params.push((param_name, param_type))
    }
    if self.check(Comma) {
      let _ = self.advance()
    }
  }
  let _ = self.expect(RParen)

  // return valuetype
  let _ = self.expect(Colon)
  let return_type = self.parse_type()
  self.consume_semicolon()
  { name, module_: "env", params, return_type }
}

///|
fn Parser::parse_declare_param_name(self : Parser) -> String raise ParseError {
  match self.peek().kind {
    Ident(n) => {
      let _ = self.advance()
      n
    }
    StringType => {
      let _ = self.advance()
      "string"
    }
    NumberType => {
      let _ = self.advance()
      "number"
    }
    BooleanType => {
      let _ = self.advance()
      "boolean"
    }
    VoidType => {
      let _ = self.advance()
      "void"
    }
    Type => {
      let _ = self.advance()
      "type"
    }
    New => {
      let _ = self.advance()
      "new"
    }
    Delete => {
      let _ = self.advance()
      "delete"
    }
    Typeof => {
      let _ = self.advance()
      "typeof"
    }
    In => {
      let _ = self.advance()
      "in"
    }
    Of => {
      let _ = self.advance()
      "of"
    }
    From => {
      let _ = self.advance()
      "from"
    }
    As => {
      let _ = self.advance()
      "as"
    }
    LBrace | LBracket => {
      let open_tok = self.peek().kind
      let close_tok : TokenKind = match open_tok {
        LBrace => RBrace
        _ => RBracket
      }
      let _ = self.advance()
      let mut depth = 1
      while depth > 0 && !self.check(Eof) {
        if self.peek().kind == open_tok {
          depth += 1
        } else if self.peek().kind == close_tok {
          depth -= 1
        }
        let _ = self.advance()
      }
      "<destructured>"
    }
    k => raise ParseError("Expected parameter name, got \{k}")
  }
}

///|
fn Parser::parse_declare_values(
  self : Parser,
) -> Array[@ast.TsValueDecl] raise ParseError {
  let values : Array[@ast.TsValueDecl] = []
  let name = self.parse_binding_ident()
  let type_ = self.parse_var_decl_type()
  if self.match_(Eq) {
    let _ = self.parse_expr()
  }
  values.push({ name, type_ })
  while self.match_(Comma) {
    let next_name = self.parse_binding_ident()
    let next_type = self.parse_var_decl_type()
    if self.match_(Eq) {
      let _ = self.parse_expr()
    }
    values.push({ name: next_name, type_: next_type })
  }
  self.consume_semicolon()
  values
}

///|
fn Parser::parse_declare_signature_params(
  self : Parser,
) -> Array[(String, @ast.TsType)] raise ParseError {
  let _ = self.expect(LParen)
  let params : Array[(String, @ast.TsType)] = []
  while !self.check(RParen) && !self.check(Eof) {
    let _ = self.match_ellipsis()
    let param_name = self.parse_declare_param_name()
    let is_optional = self.match_(Question)
    let base_param_type = if self.check(Colon) {
      let _ = self.advance()
      self.parse_type()
    } else {
      @ast.TsType::Any
    }
    let param_type = if is_optional {
      wrap_optional_ts_type(base_param_type)
    } else {
      base_param_type
    }
    params.push((param_name, param_type))
    if self.check(Comma) {
      let _ = self.advance()
    }
  }
  let _ = self.expect(RParen)
  params
}

///|
fn Parser::parse_declare_class_member_name(
  self : Parser,
) -> String? raise ParseError {
  if self.match_(LBracket) {
    let mut depth = 1
    while depth > 0 && !self.check(Eof) {
      match self.peek().kind {
        LBracket => {
          depth += 1
          let _ = self.advance()
        }
        RBracket => {
          depth -= 1
          let _ = self.advance()
        }
        _ => {
          let _ = self.advance()
        }
      }
    }
    return None
  }
  let name = match self.advance().kind {
    Ident(n) => n
    PrivateIdent(n) => "#" + n
    Str(s) => s
    Number(n) => "\{n}"
    Int(n) => "\{n}"
    Return => "return"
    If => "if"
    Else => "else"
    For => "for"
    While => "while"
    Break => "break"
    Continue => "continue"
    Function => "function"
    Try => "try"
    Catch => "catch"
    Finally => "finally"
    Throw => "throw"
    Yield => "yield"
    Declare => "declare"
    Type => "type"
    Let => "let"
    Const => "const"
    Var => "var"
    Class => "class"
    New => "new"
    Default => "default"
    Do => "do"
    In => "in"
    Case => "case"
    VoidType => "void"
    With => "with"
    Switch => "switch"
    Typeof => "typeof"
    Delete => "delete"
    Export => "export"
    Import => "import"
    Debugger => "debugger"
    Interface => "interface"
    Instanceof => "instanceof"
    Extends => "extends"
    From => "from"
    As => "as"
    k => raise ParseError("Expected class member name, got \{k}")
  }
  Some(name)
}

///|
fn Parser::skip_declare_class_heritage(self : Parser) -> Unit {
  let mut paren_depth = 0
  let mut bracket_depth = 0
  let mut brace_depth = 0
  let mut angle_depth = 0
  while !self.check(Eof) {
    match self.peek().kind {
      LBrace if paren_depth == 0 &&
        bracket_depth == 0 &&
        brace_depth == 0 &&
        angle_depth == 0 => break
      LParen => {
        paren_depth += 1
        let _ = self.advance()
      }
      RParen => {
        if paren_depth > 0 {
          paren_depth -= 1
        }
        let _ = self.advance()
      }
      LBracket => {
        bracket_depth += 1
        let _ = self.advance()
      }
      RBracket => {
        if bracket_depth > 0 {
          bracket_depth -= 1
        }
        let _ = self.advance()
      }
      LBrace => {
        brace_depth += 1
        let _ = self.advance()
      }
      RBrace => {
        if brace_depth > 0 {
          brace_depth -= 1
        }
        let _ = self.advance()
      }
      Lt => {
        angle_depth += 1
        let _ = self.advance()
      }
      Gt => {
        if angle_depth > 0 {
          angle_depth -= 1
        }
        let _ = self.advance()
      }
      GtGt => {
        angle_depth = if angle_depth >= 2 { angle_depth - 2 } else { 0 }
        let _ = self.advance()
      }
      GtGtGt => {
        angle_depth = if angle_depth >= 3 { angle_depth - 3 } else { 0 }
        let _ = self.advance()
      }
      _ => {
        let _ = self.advance()
      }
    }
  }
}

///|
fn upsert_class_property(
  properties : Array[@ast.TsClassPropertyDecl],
  property : @ast.TsClassPropertyDecl,
) -> Unit {
  for i in 0..<properties.length() {
    let existing = properties[i]
    if existing.name == property.name &&
      existing.is_static == property.is_static {
      let merged_type = match existing.type_ {
        Any => property.type_
        _ => existing.type_
      }
      properties[i] = {
        name: existing.name,
        type_: merged_type,
        is_static: existing.is_static,
        is_readonly: existing.is_readonly && property.is_readonly,
      }
      return
    }
  }
  properties.push(property)
}

///|
fn Parser::parse_declare_class(
  self : Parser,
  is_abstract : Bool,
) -> @ast.TsClassDecl raise ParseError {
  let _ = self.expect(Class)
  let name = self.parse_binding_ident()
  if self.check(Lt) {
    self.skip_type_params()
  }
  self.skip_declare_class_heritage()
  let _ = self.expect(LBrace)
  let properties : Array[@ast.TsClassPropertyDecl] = []
  let methods : Array[@ast.TsClassMethodDecl] = []
  let mut constructor_params : Array[(String, @ast.TsType)]? = None
  let mut saw_public_constructor = false
  let mut saw_nonpublic_constructor = false
  while !self.check(RBrace) && !self.check(Eof) {
    if self.match_(Semicolon) {
      continue
    }
    let mut is_static = false
    let mut is_readonly = false
    let mut is_public = true
    let mut has_modifier = true
    while has_modifier {
      has_modifier = false
      match self.peek().kind {
        Ident(mod) if mod == "static" ||
          mod == "readonly" ||
          mod == "override" ||
          mod == "abstract" ||
          mod == "declare" ||
          mod == "accessor" ||
          mod == "public" ||
          mod == "private" ||
          mod == "protected" => {
          let _ = self.advance()
          if mod == "static" {
            is_static = true
          }
          if mod == "readonly" {
            is_readonly = true
          }
          if mod == "private" || mod == "protected" {
            is_public = false
          }
          has_modifier = true
        }
        _ => ()
      }
    }
    let mut accessor_kind : String? = None
    match self.peek().kind {
      Ident(n) if (n == "get" || n == "set") &&
        self.peek_at(1).kind != LParen &&
        self.peek_at(1).kind != Lt &&
        self.peek_at(1).kind != Colon => {
        let _ = self.advance()
        accessor_kind = Some(n)
      }
      _ => ()
    }
    let member_name = self.parse_declare_class_member_name()
    let _ = self.match_(Question)
    if self.check(Lt) {
      self.skip_type_params()
    }
    if self.check(LParen) {
      let params = self.parse_declare_signature_params()
      let return_type = if self.check(Colon) {
        let _ = self.advance()
        self.parse_type()
      } else {
        @ast.TsType::Any
      }
      self.consume_semicolon()
      match member_name {
        Some(member_name) =>
          match accessor_kind {
            Some("get") if is_public =>
              upsert_class_property(properties, {
                name: member_name,
                type_: return_type,
                is_static,
                is_readonly: true,
              })
            Some("set") if is_public => {
              let setter_type = if params.length() > 0 {
                let (_, type_) = params[0]
                type_
              } else {
                @ast.TsType::Any
              }
              upsert_class_property(properties, {
                name: member_name,
                type_: setter_type,
                is_static,
                is_readonly: false,
              })
            }
            _ =>
              if member_name == "constructor" &&
                !is_static &&
                accessor_kind is None {
                if is_public {
                  constructor_params = Some(params)
                  saw_public_constructor = true
                } else {
                  saw_nonpublic_constructor = true
                }
              } else if is_public {
                methods.push({
                  name: member_name,
                  params,
                  return_type,
                  is_static,
                })
              }
          }
        None => ()
      }
      continue
    }
    let mut property_type = @ast.TsType::Any
    if self.match_(Colon) {
      property_type = self.parse_type()
    }
    if self.match_(Eq) {
      let _ = self.parse_assignment()
    }
    self.consume_semicolon()
    match member_name {
      Some(member_name) if is_public && accessor_kind is None =>
        upsert_class_property(properties, {
          name: member_name,
          type_: property_type,
          is_static,
          is_readonly,
        })
      _ => ()
    }
  }
  let _ = self.expect(RBrace)
  let _ = self.match_(Semicolon)
  let is_constructible = if saw_public_constructor {
    !is_abstract
  } else if saw_nonpublic_constructor {
    false
  } else {
    !is_abstract
  }
  {
    name,
    constructor_params,
    properties,
    methods,
    is_abstract,
    is_constructible,
  }
}
