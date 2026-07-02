///|
// /
fn Parser::parse_binding_ident(self : Parser) -> String raise ParseError {
  match self.peek().kind {
    Ident(_) =>
      match self.advance().kind {
        Ident(n) => {
          // In strict mode, `eval` and `arguments` cannot be used as binding
          // identifiers (TS1100 family). Recorded -- not raised -- so the
          // file still parses and the checker reports the diagnostic.
          if (self.in_strict || self.directive_strict) &&
            (n == "eval" || n == "arguments") {
            self.strict_mode_misuses.push(n)
          }
          n
        }
        _ => "<param>"
      }
    Yield => {
      let _ = self.advance()
      "yield"
    }
    NumberType => {
      let _ = self.advance()
      "number"
    }
    BooleanType => {
      let _ = self.advance()
      "boolean"
    }
    StringType => {
      let _ = self.advance()
      "string"
    }
    VoidType => {
      let _ = self.advance()
      "void"
    }
    IntType => {
      let _ = self.advance()
      "int"
    }
    Type => {
      let _ = self.advance()
      "type"
    }
    Function => {
      let _ = self.advance()
      "function"
    }
    Class => {
      let _ = self.advance()
      "class"
    }
    Interface => {
      let _ = self.advance()
      "interface"
    }
    New => {
      let _ = self.advance()
      "new"
    }
    Let => {
      let _ = self.advance()
      "let"
    }
    Var => {
      let _ = self.advance()
      "var"
    }
    Const => {
      let _ = self.advance()
      "const"
    }
    Switch => {
      let _ = self.advance()
      "switch"
    }
    Case => {
      let _ = self.advance()
      "case"
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
    For => {
      let _ = self.advance()
      "for"
    }
    Return => {
      let _ = self.advance()
      "return"
    }
    Break => {
      let _ = self.advance()
      "break"
    }
    Continue => {
      let _ = self.advance()
      "continue"
    }
    Default => {
      let _ = self.advance()
      "default"
    }
    With => {
      let _ = self.advance()
      "with"
    }
    Debugger => {
      let _ = self.advance()
      "debugger"
    }
    Try => {
      let _ = self.advance()
      "try"
    }
    Catch => {
      let _ = self.advance()
      "catch"
    }
    Finally => {
      let _ = self.advance()
      "finally"
    }
    Throw => {
      let _ = self.advance()
      "throw"
    }
    Import => {
      let _ = self.advance()
      "import"
    }
    Export => {
      let _ = self.advance()
      "export"
    }
    Declare => {
      let _ = self.advance()
      "declare"
    }
    From => {
      let _ = self.advance()
      "from"
    }
    Delete => {
      let _ = self.advance()
      "delete"
    }
    As => {
      let _ = self.advance()
      "as"
    }
    Of => {
      let _ = self.advance()
      "of"
    }
    In => {
      let _ = self.advance()
      "in"
    }
    Extends => {
      let _ = self.advance()
      "extends"
    }
    Typeof => {
      let _ = self.advance()
      "typeof"
    }
    Instanceof => {
      let _ = self.advance()
      "instanceof"
    }
    Null => {
      let _ = self.advance()
      "null"
    }
    Bool(true) => {
      let _ = self.advance()
      "true"
    }
    Bool(false) => {
      let _ = self.advance()
      "false"
    }
    k => raise ParseError("Expected identifier, got \{k}")
  }
}

///|
fn Parser::binding_first_name(
  self : Parser,
  binding : @ast.TsBinding,
) -> String {
  match binding {
    @ast.TsBinding::Ident(n) => n
    @ast.TsBinding::Array(arr) => {
      for item in arr.items {
        match item {
          Some(elem) => {
            let name = self.binding_first_name(elem.binding)
            if name != "<destruct>" {
              return name
            }
          }
          None => ()
        }
      }
      match arr.rest {
        Some(rest) => self.binding_first_name(rest)
        None => "<destruct>"
      }
    }
    @ast.TsBinding::Object(obj) => {
      for prop in obj.props {
        let name = self.binding_first_name(prop.binding)
        if name != "<destruct>" {
          return name
        }
      }
      match obj.rest {
        Some(name) => name
        None => "<destruct>"
      }
    }
    @ast.TsBinding::Target(_) => "<destruct>"
  }
}

///|
/// Collect all bound names from a binding pattern
fn Parser::collect_binding_names(
  self : Parser,
  binding : @ast.TsBinding,
  names : Array[String],
) -> Unit {
  match binding {
    @ast.TsBinding::Ident(n) => names.push(n)
    @ast.TsBinding::Array(arr) => {
      for item in arr.items {
        match item {
          Some(elem) => self.collect_binding_names(elem.binding, names)
          None => ()
        }
      }
      match arr.rest {
        Some(rest) => self.collect_binding_names(rest, names)
        None => ()
      }
    }
    @ast.TsBinding::Object(obj) => {
      for prop in obj.props {
        self.collect_binding_names(prop.binding, names)
      }
      match obj.rest {
        Some(name) => names.push(name)
        None => ()
      }
    }
    @ast.TsBinding::Target(_) => ()
  }
}

///|
fn Parser::parse_binding_element(
  self : Parser,
) -> @ast.TsBindingElem raise ParseError {
  let binding = self.parse_binding_pattern()
  let default : @ast.TsExpr? = if self.match_(Eq) {
    Some(self.parse_assignment())
  } else {
    None
  }
  { binding, default }
}

///|
fn Parser::parse_binding_array(
  self : Parser,
) -> @ast.TsBinding raise ParseError {
  let _ = self.expect(LBracket)
  let items : Array[@ast.TsBindingElem?] = []
  let mut rest : @ast.TsBinding? = None
  while !self.check(RBracket) {
    if self.match_(Ellipsis) {
      let rest_binding = self.parse_binding_pattern()
      rest = Some(rest_binding)
      if self.match_(Comma) {
        // trailing comma after rest
      }
      break
    }
    if self.match_(Comma) {
      items.push(None)
      continue
    }
    items.push(Some(self.parse_binding_element()))
    if self.match_(Comma) {
      if self.check(RBracket) {
        break
      }
      continue
    } else {
      break
    }
  }
  let _ = self.expect(RBracket)
  @ast.TsBinding::Array({ items, rest })
}

///|
fn Parser::parse_object_binding_key(self : Parser) -> String raise ParseError {
  match self.advance().kind {
    Ident(n) => n
    Yield => "yield"
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
    Let => "let"
    Const => "const"
    Var => "var"
    New => "new"
    Typeof => "typeof"
    Of => "of"
    In => "in"
    Do => "do"
    Try => "try"
    Switch => "switch"
    Case => "case"
    Default => "default"
    With => "with"
    Debugger => "debugger"
    Import => "import"
    Export => "export"
    From => "from"
    As => "as"
    Catch => "catch"
    Finally => "finally"
    Throw => "throw"
    Delete => "delete"
    Declare => "declare"
    Interface => "interface"
    Class => "class"
    Instanceof => "instanceof"
    NumberType => "number"
    BooleanType => "boolean"
    StringType => "string"
    VoidType => "void"
    IntType => "int"
    Type => "type"
    Extends => "extends"
    Null => "null"
    // Boolean literals are valid as object-destructure keys
    // (e.g. `const { true: a, false: b } = ...`).
    Bool(true) => "true"
    Bool(false) => "false"
    k => raise ParseError("Expected object binding key, got \{k}")
  }
}

///|
fn Parser::parse_binding_object(
  self : Parser,
) -> @ast.TsBinding raise ParseError {
  let _ = self.expect(LBrace)
  let props : Array[@ast.TsObjectBindingProp] = []
  let mut rest : String? = None
  if !self.check(RBrace) {
    while true {
      if self.match_(Ellipsis) {
        let name = self.parse_binding_ident()
        rest = Some(name)
        if self.match_(Comma) {
          // trailing comma
        }
        break
      }
      let (key, key_expr) = if self.match_(LBracket) {
        let expr = self.parse_assignment()
        let _ = self.expect(RBracket)
        ("<computed>", Some(expr))
      } else {
        (self.parse_object_binding_key(), None)
      }
      if self.match_(Colon) {
        let elem = self.parse_binding_element()
        props.push({
          key,
          key_expr,
          binding: elem.binding,
          default: elem.default,
        })
      } else {
        match key_expr {
          Some(_) => raise ParseError("Expected Colon, got \{self.peek().kind}")
          None => {
            let mut default : @ast.TsExpr? = None
            if self.match_(Eq) {
              default = Some(self.parse_assignment())
            }
            props.push({
              key,
              key_expr: None,
              binding: @ast.TsBinding::Ident(key),
              default,
            })
          }
        }
      }
      if self.check(RBrace) {
        break
      }
      let _ = self.expect(Comma)
      if self.check(RBrace) {
        break
      }
    }
  }
  let _ = self.expect(RBrace)
  @ast.TsBinding::Object({ props, rest })
}

///|
fn Parser::parse_binding_pattern(
  self : Parser,
) -> @ast.TsBinding raise ParseError {
  match self.peek().kind {
    LBracket => self.parse_binding_array()
    LBrace => self.parse_binding_object()
    _ => {
      let name = self.parse_binding_ident()
      @ast.TsBinding::Ident(name)
    }
  }
}

///|
fn Parser::parse_assignment_target_expr(
  self : Parser,
) -> @ast.TsExpr raise ParseError {
  let expr = self.parse_ternary()
  match expr {
    Var(_) | PropAccess(_, _) | IndexAccess(_, _) => expr
    _ => raise ParseError("Invalid assignment target")
  }
}

///|
fn Parser::parse_assignment_binding_element(
  self : Parser,
) -> @ast.TsBindingElem raise ParseError {
  let binding = self.parse_assignment_binding_pattern()
  let default : @ast.TsExpr? = if self.match_(Eq) {
    Some(self.parse_assignment())
  } else {
    None
  }
  { binding, default }
}

///|
fn Parser::parse_assignment_binding_array(
  self : Parser,
) -> @ast.TsBinding raise ParseError {
  let _ = self.expect(LBracket)
  let items : Array[@ast.TsBindingElem?] = []
  let mut rest : @ast.TsBinding? = None
  while !self.check(RBracket) {
    if self.match_(Ellipsis) {
      let rest_binding = self.parse_assignment_binding_pattern()
      rest = Some(rest_binding)
      if self.match_(Comma) {
        // trailing comma after rest
      }
      break
    }
    if self.match_(Comma) {
      items.push(None)
      continue
    }
    items.push(Some(self.parse_assignment_binding_element()))
    if self.match_(Comma) {
      if self.check(RBracket) {
        break
      }
      continue
    } else {
      break
    }
  }
  let _ = self.expect(RBracket)
  @ast.TsBinding::Array({ items, rest })
}

///|
fn Parser::parse_assignment_binding_object(
  self : Parser,
) -> @ast.TsBinding raise ParseError {
  let _ = self.expect(LBrace)
  let props : Array[@ast.TsObjectBindingProp] = []
  let mut rest : String? = None
  if !self.check(RBrace) {
    while true {
      if self.match_(Ellipsis) {
        let name = self.parse_binding_ident()
        rest = Some(name)
        if self.match_(Comma) {
          // trailing comma
        }
        break
      }
      let (key, key_expr) = if self.match_(LBracket) {
        let expr = self.parse_assignment()
        let _ = self.expect(RBracket)
        ("<computed>", Some(expr))
      } else {
        (self.parse_object_binding_key(), None)
      }
      if self.match_(Colon) {
        let elem = self.parse_assignment_binding_element()
        props.push({
          key,
          key_expr,
          binding: elem.binding,
          default: elem.default,
        })
      } else {
        match key_expr {
          Some(_) => raise ParseError("Expected Colon, got \{self.peek().kind}")
          None => {
            let mut default : @ast.TsExpr? = None
            if self.match_(Eq) {
              default = Some(self.parse_assignment())
            }
            props.push({
              key,
              key_expr: None,
              binding: @ast.TsBinding::Ident(key),
              default,
            })
          }
        }
      }
      if self.check(RBrace) {
        break
      }
      let _ = self.expect(Comma)
      if self.check(RBrace) {
        break
      }
    }
  }
  let _ = self.expect(RBrace)
  @ast.TsBinding::Object({ props, rest })
}

///|
fn Parser::parse_assignment_binding_pattern(
  self : Parser,
) -> @ast.TsBinding raise ParseError {
  let saved_pos = self.pos
  let saved_gen = self.in_generator
  let target = Some(self.parse_assignment_target_expr()) catch { _ => None }
  match target {
    Some(expr) =>
      match expr {
        Var(name) => @ast.TsBinding::Ident(name)
        _ => @ast.TsBinding::Target(expr)
      }
    None => {
      self.pos = saved_pos
      self.in_generator = saved_gen
      match self.peek().kind {
        LBracket => self.parse_assignment_binding_array()
        LBrace => self.parse_assignment_binding_object()
        _ => {
          let name = self.parse_binding_ident()
          @ast.TsBinding::Ident(name)
        }
      }
    }
  }
}

///|
// / ...
fn Parser::match_ellipsis(self : Parser) -> Bool {
  self.match_(Ellipsis)
}
