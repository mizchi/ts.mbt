// ============================================
// function
// ============================================

///|
// / parameter
fn Parser::parse_param(self : Parser) -> @ast.TsParam raise ParseError {
  let is_rest = self.match_ellipsis()
  let binding = self.parse_binding_pattern()
  let name = self.binding_first_name(binding)
  // type ()
  let type_ = if self.check(Colon) {
    let _ = self.advance()
    self.parse_type()
  } else {
    Any // type Any
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
  if not(self.check(RParen)) {
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
  let has_default = params.iter().any(fn(p) { not(p.default is None) })
  let has_rest = params.iter().any(fn(p) { p.is_rest })
  let has_destructuring = params
    .iter()
    .any(fn(p) {
      match p.binding {
        Some(@ast.TsBinding::Array(_)) | Some(@ast.TsBinding::Object(_)) => true
        _ => false
      }
    })
  let is_simple = not(has_default) && not(has_rest) && not(has_destructuring)
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
      if self.in_strict || not(is_simple) {
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
  let name = match self.advance().kind {
    Ident(n) => n
    k => raise ParseError("Expected function name, got \{k}")
  }
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
    Ident(n) => {
      let _ = self.advance()
      n
    }
    _ => "<anon>"
  }
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
  if not(self.check(Lt)) {
    return
  }
  let _ = self.advance() // consume <
  let mut depth = 1
  while depth > 0 && not(self.check(Eof)) {
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
  if not(self.check(Extends)) {
    return
  }
  let _ = self.advance() // consume extends
  // Parse comma-separated type references until { or EOF
  while not(self.check(LBrace)) && not(self.check(Eof)) {
    match self.peek().kind {
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
  while not(self.check(RBrace)) && not(self.check(Eof)) {
    // Skip readonly modifier
    if self.check(Ident("readonly")) {
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
        while not(self.check(RBracket)) && not(self.check(Eof)) {
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
    let _ = self.match_(Question)
    // Method signature: name(...): T or name<T>(...): U
    if self.check(LParen) {
      let _ = self.advance()
      // Skip parameters
      let mut paren_depth = 1
      while paren_depth > 0 && not(self.check(Eof)) {
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
        fields.push((field_name, field_type))
      } else {
        fields.push((field_name, @ast.TsType::Void))
      }
    } else if self.check(Colon) {
      // Property: name: T
      let _ = self.advance()
      let field_type = self.parse_type()
      fields.push((field_name, field_type))
    } else {
      // No type annotation - use Any
      fields.push((field_name, @ast.TsType::Any))
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
  while not(self.check(Eof)) {
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
/// Skip type alias: type Name<T> = ...;
fn Parser::skip_type_alias(self : Parser) -> Unit {
  let _ = self.advance() // consume 'type'
  // Skip until semicolon, handling nested braces and angle brackets
  let mut brace_depth = 0
  let mut angle_depth = 0
  while not(self.check(Eof)) {
    match self.peek().kind {
      LBrace => {
        brace_depth += 1
        let _ = self.advance()
      }
      RBrace => {
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
      _ => {
        let _ = self.advance()
      }
    }
  }
}

///|
/// Skip declaration block (namespace, module, class, enum, etc.)
fn Parser::skip_declaration_block(self : Parser) -> Unit {
  // Skip until we find { or ;
  while not(self.check(LBrace)) &&
        not(self.check(Semicolon)) &&
        not(self.check(Eof)) {
    let _ = self.advance()
  }
  if self.check(Semicolon) {
    let _ = self.advance()
    return
  }
  if self.check(LBrace) {
    let _ = self.advance()
    let mut depth = 1
    while depth > 0 && not(self.check(Eof)) {
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
  let name = match self.advance().kind {
    Ident(n) => n
    _ => raise ParseError("Expected function name after 'declare function'")
  }

  // Skip type parameters if present
  self.skip_type_params()
  // parameter
  let _ = self.expect(LParen)
  let params : Array[(String, @ast.TsType)] = []
  while not(self.check(RParen)) && not(self.check(Eof)) {
    // Handle rest parameter: ...name
    let _ = self.match_ellipsis()
    // Handle parameter name (can be identifier, keyword, or destructuring pattern)
    let param_name = match self.peek().kind {
      Ident(n) => {
        let _ = self.advance()
        n
      }
      // Type keywords can be used as parameter names
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
      // Other keywords that can be parameter names
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
        // Destructuring: { a, b } or [ a, b ]
        let open_tok = self.peek().kind
        let close_tok : TokenKind = match open_tok {
          LBrace => RBrace
          _ => RBracket
        }
        let _ = self.advance()
        let mut depth = 1
        while depth > 0 && not(self.check(Eof)) {
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
    // Handle optional parameter: name?
    let _ = self.match_(Question)
    // Type annotation is optional
    if self.check(Colon) {
      let _ = self.advance()
      let param_type = self.parse_type()
      params.push((param_name, param_type))
    } else {
      params.push((param_name, @ast.TsType::Any))
    }
    if self.check(Comma) {
      let _ = self.advance()
    }
  }
  let _ = self.expect(RParen)

  // return valuetype
  let _ = self.expect(Colon)
  let return_type = self.parse_type()
  let _ = self.expect(Semicolon)
  { name, module_: "env", params, return_type }
}
