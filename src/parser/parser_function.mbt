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
  params
}

///|
// / function
pub fn Parser::parse_function(self : Parser) -> @ast.TsFunc raise ParseError {
  let _ = self.expect(Function)
  let is_generator = self.match_(Star)
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
  let prev = self.in_generator
  if is_generator {
    self.in_generator = true
  }
  let body = self.parse_block()
  self.in_generator = prev
  { name, params, return_type, body, is_generator }
}

///|
// / functionexpression()
fn Parser::parse_function_expr(self : Parser) -> @ast.TsFunc raise ParseError {
  let _ = self.expect(Function)
  let is_generator = self.match_(Star)
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
  let prev = self.in_generator
  if is_generator {
    self.in_generator = true
  }
  let body = self.parse_block()
  self.in_generator = prev
  { name, params, return_type, body, is_generator }
}

///|
// / interface
pub fn Parser::parse_interface(self : Parser) -> @ast.TsInterface raise ParseError {
  let _ = self.expect(Interface)
  let name = match self.advance().kind {
    Ident(n) => n
    k => raise ParseError("Expected interface name, got \{k}")
  }
  let _ = self.expect(LBrace)
  let fields : Array[(String, @ast.TsType)] = []
  while not(self.check(RBrace)) && not(self.check(Eof)) {
    // field: type;
    let field_name = match self.advance().kind {
      Ident(n) => n
      k => raise ParseError("Expected field name, got \{k}")
    }
    let _ = self.expect(Colon)
    let field_type = self.parse_type()
    let _ = self.expect(Semicolon)
    fields.push((field_name, field_type))
  }
  let _ = self.expect(RBrace)
  { name, fields }
}

///|
// / declare function
/// declare function name(params): returnType;
pub fn Parser::parse_import(self : Parser) -> @ast.TsImport raise ParseError {
  let _ = self.expect(Declare)
  let _ = self.expect(Function)

  // function
  let name = match self.advance().kind {
    Ident(n) => n
    _ => raise ParseError("Expected function name after 'declare function'")
  }

  // parameter
  let _ = self.expect(LParen)
  let params : Array[(String, @ast.TsType)] = []
  while not(self.check(RParen)) {
    let param_name = match self.advance().kind {
      Ident(n) => n
      _ => raise ParseError("Expected parameter name")
    }
    let _ = self.expect(Colon)
    let param_type = self.parse_type()
    params.push((param_name, param_type))
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
